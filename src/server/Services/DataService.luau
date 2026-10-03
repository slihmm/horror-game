--!strict
-- Persistent player profiles.
--
--  * Session locking: a profile records which server owns it. Another server
--    waits (and eventually steals a stale lock) instead of loading a copy that
--    could overwrite newer progress.
--  * Every DataStore call is retried with exponential backoff and respects the
--    request budget.
--  * Saves are serialized per player (no overlapping writes); a save requested
--    while one is in flight is coalesced into a single follow-up save.
--  * Autosave, save-on-leave and BindToClose flushing.
--  * Loaded data is validated and reconciled against the template, so corrupt
--    or old-format records can't crash the game or inject values.
--  * Without DataStore access (Studio without API access, unpublished place)
--    profiles live in memory and are flagged non-persistent.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utility.Signal)
local Types = require(Shared.Types)

type Profile = Types.Profile

local STORE_NAME = "PlayerProfiles_v1"
local KEY_PREFIX = "player_"
local CURRENT_VERSION = 1
local AUTOSAVE_INTERVAL = 90
-- A lock older than this is assumed to belong to a crashed server.
local LOCK_STALE_SECONDS = AUTOSAVE_INTERVAL * 3
local LOAD_ATTEMPTS = 6
local LOCK_RETRY_DELAY = 6
local MAX_RETRIES = 5

type Session = {
	Profile: Profile,
	Dirty: boolean,
	Saving: boolean,
	SaveQueued: boolean,
	Released: boolean,
	Releasing: boolean,
	LoadedAt: number,
}

type Record = {
	Data: any,
	Lock: { JobId: string, Time: number }?,
	Version: number?,
}

local DataService = {}
DataService.__index = DataService

type State = {
	ProfileLoaded: Signal.Signal<Player, Profile>,
	Changed: Signal.Signal<Player>,
	_sessions: { [Player]: Session },
	_store: DataStore?,
	_persistent: boolean,
	_memory: { [string]: Record },
	_jobId: string,
	_shuttingDown: boolean,
}
export type DataService = typeof(setmetatable({} :: State, DataService))

-- Template & validation -------------------------------------------------------

local function template(): Profile
	return {
		Version = CURRENT_VERSION,
		Stats = {
			HighestDistance = 0,
			DeepestDescent = 0,
			Completions = 0,
			TimeUnderground = 0,
			SecretsFound = 0,
			FastestEscape = 0,
			Deaths = 0,
			Expeditions = 0,
		},
		Secrets = {},
		Lore = {},
		Currency = 0,
		Collection = {},
		Cosmetics = {},
		Flags = {},
		Settings = {
			CameraMotion = 1,
			Brightness = 0.5,
			HeadlampTint = "Default",
		},
	}
end

-- Older records are upgraded step by step. Add a function per version bump.
local MIGRATIONS: { [number]: (any) -> any } = {}

local function finiteNumber(value: any, fallback: number, min: number?, max: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	if min and value < min then
		return min
	end
	if max and value > max then
		return max
	end
	return value
end

local function boolSet(value: any, maxEntries: number): { [string]: boolean }
	local result = {}
	if type(value) ~= "table" then
		return result
	end
	local count = 0
	for k, v in value do
		if type(k) == "string" and #k <= 64 and v == true then
			result[k] = true
			count += 1
			if count >= maxEntries then
				break
			end
		end
	end
	return result
end

-- Coerces arbitrary stored data into a valid Profile.
local function sanitize(raw: any): Profile
	local profile = template()
	if type(raw) ~= "table" then
		return profile
	end
	local version = finiteNumber(raw.Version, CURRENT_VERSION, 0)
	while version < CURRENT_VERSION do
		local migrate = MIGRATIONS[version]
		if migrate then
			raw = migrate(raw)
		end
		version += 1
	end
	local stats = if type(raw.Stats) == "table" then raw.Stats else {}
	for key, default in profile.Stats :: any do
		(profile.Stats :: any)[key] = finiteNumber(stats[key], default, 0, 1e9)
	end
	profile.Secrets = boolSet(raw.Secrets, 2000)
	profile.Lore = boolSet(raw.Lore, 500)
	profile.Cosmetics = boolSet(raw.Cosmetics, 200)
	profile.Flags = boolSet(raw.Flags, 200)
	profile.Currency = math.floor(finiteNumber(raw.Currency, 0, 0, 1e9))
	if type(raw.Collection) == "table" then
		for id, count in raw.Collection do
			if type(id) == "string" and #id <= 64 then
				profile.Collection[id] = math.floor(finiteNumber(count, 0, 0, 1e6))
			end
		end
	end
	if type(raw.Settings) == "table" then
		profile.Settings.CameraMotion = finiteNumber(raw.Settings.CameraMotion, 1, 0, 1)
		profile.Settings.Brightness = finiteNumber(raw.Settings.Brightness, 0.5, 0, 1)
		if type(raw.Settings.HeadlampTint) == "string" and #raw.Settings.HeadlampTint <= 32 then
			profile.Settings.HeadlampTint = raw.Settings.HeadlampTint
		end
	end
	return profile
end

-- DataStore plumbing ----------------------------------------------------------

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 20 do
		task.wait(0.5)
		waited += 0.5
	end
end

-- Calls fn with retries and exponential backoff. Returns ok, result.
local function withRetries<T>(label: string, requestType: Enum.DataStoreRequestType, fn: () -> T): (boolean, T?)
	local delay = 1
	for attempt = 1, MAX_RETRIES do
		waitForBudget(requestType)
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] {label} failed (attempt {attempt}/{MAX_RETRIES}): {result}`)
		if attempt < MAX_RETRIES then
			task.wait(delay)
			delay = math.min(delay * 2, 16)
		end
	end
	return false, nil
end

function DataService._key(self: DataService, player: Player): string
	return KEY_PREFIX .. player.UserId
end

-- Runs an UpdateAsync-style transform against the real store or memory.
function DataService._update(self: DataService, key: string, transform: (Record?) -> Record?): (boolean, Record?)
	if not self._persistent then
		local current = self._memory[key]
		local nextRecord = transform(if current then table.clone(current) else nil)
		if nextRecord then
			self._memory[key] = nextRecord
		end
		return true, nextRecord or current
	end
	local store = self._store :: DataStore
	local ok, result = withRetries(`UpdateAsync {key}`, Enum.DataStoreRequestType.UpdateAsync, function()
		return store:UpdateAsync(key, function(current: any)
			return transform(current)
		end)
	end)
	return ok, result :: Record?
end

-- Lifecycle -----------------------------------------------------------------------

function DataService.Init(self: DataService)
	local canUseStore = game.PlaceId ~= 0
	if canUseStore then
		local ok, storeOrError = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if ok then
			self._store = storeOrError
			-- Probe access: Studio without API access errors here.
			local probeOk, probeError = pcall(function()
				(storeOrError :: DataStore):GetAsync("__probe")
			end)
			if not probeOk then
				warn(`[DataService] DataStore unavailable ({probeError}); using in-memory profiles`)
				canUseStore = false
			end
		else
			canUseStore = false
		end
	end
	self._persistent = canUseStore
	if not canUseStore then
		print("[DataService] Profiles are NOT persistent in this session (unpublished place or no API access).")
	end
end

function DataService.Start(self: DataService)
	Players.PlayerAdded:Connect(function(player: Player)
		self:_load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_release(player)
	end)
	game:BindToClose(function()
		self._shuttingDown = true
		local pending = 0
		for player in self._sessions do
			pending += 1
			task.spawn(function()
				self:_release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	-- Autosave loop, staggered across players.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, session in self._sessions do
				if not session.Released then
					task.spawn(function()
						self:Save(player)
					end)
					task.wait(1)
				end
			end
		end
	end)
end

function DataService._load(self: DataService, player: Player)
	if self._sessions[player] then
		return
	end
	local key = self:_key(player)
	local loaded: Record? = nil
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local ok, record = self:_update(key, function(current: Record?): Record?
			-- UpdateAsync may run this more than once; decide afresh each time.
			lockedByOther = false
			local now = os.time()
			if current and current.Lock and current.Lock.JobId ~= self._jobId then
				local age = now - current.Lock.Time
				if age < LOCK_STALE_SECONDS and attempt < LOAD_ATTEMPTS then
					lockedByOther = true
					return nil -- abort: leave the record untouched
				end
			end
			return {
				Data = if current then current.Data else nil,
				Lock = { JobId = self._jobId, Time = now },
				Version = CURRENT_VERSION,
			}
		end)
		if not player.Parent then
			-- Left during load: release whatever we may have locked.
			if ok and record and not lockedByOther then
				self:_update(key, function(current: Record?): Record?
					if current and current.Lock and current.Lock.JobId == self._jobId then
						current.Lock = nil
						return current
					end
					return nil
				end)
			end
			return
		end
		if ok and not lockedByOther then
			loaded = record
			break
		end
		if lockedByOther then
			print(`[DataService] {player.Name}'s profile is locked by another server; retrying ({attempt}/{LOAD_ATTEMPTS})`)
		end
		task.wait(LOCK_RETRY_DELAY)
	end
	if not loaded and self._persistent then
		player:Kick("Your expedition log could not be loaded. Please rejoin in a moment.")
		return
	end
	local profile = sanitize(if loaded then loaded.Data else nil)
	local session: Session = {
		Profile = profile,
		Dirty = false,
		Saving = false,
		SaveQueued = false,
		Released = false,
		Releasing = false,
		LoadedAt = os.clock(),
	}
	self._sessions[player] = session
	player:SetAttribute(Constants.Attributes.DataLoaded, true)
	self.ProfileLoaded:Fire(player, profile)
end

-- Saves the profile; with release=true the session lock is cleared too.
function DataService.Save(self: DataService, player: Player, release: boolean?): boolean
	local session = self._sessions[player]
	if not session then
		return false
	end
	if session.Saving then
		-- Coalesce: one more save after the current one finishes.
		session.SaveQueued = true
		while session.Saving do
			task.wait(0.1)
		end
		if not release and not session.SaveQueued then
			return true
		end
	end
	session.Saving = true
	session.SaveQueued = false
	local snapshot = sanitize(session.Profile)
	local stolen = false
	local ok = self:_update(self:_key(player), function(current: Record?): Record?
		stolen = false
		if current and current.Lock and current.Lock.JobId ~= self._jobId then
			-- Another server took over (we were assumed dead). Don't clobber.
			stolen = true
			return nil
		end
		return {
			Data = snapshot,
			Lock = if release then nil else { JobId = self._jobId, Time = os.time() },
			Version = CURRENT_VERSION,
		}
	end)
	session.Saving = false
	if stolen then
		warn(`[DataService] Session for {player.Name} was taken over by another server; local changes dropped`)
		session.Released = true
		return false
	end
	if ok then
		session.Dirty = false
	end
	return ok
end

function DataService._release(self: DataService, player: Player)
	local session = self._sessions[player]
	if not session or session.Released then
		self._sessions[player] = nil
		return
	end
	if session.Releasing then
		-- Shutdown and leaving can both release; let the first one finish.
		while not session.Released do
			task.wait(0.1)
		end
		return
	end
	session.Releasing = true
	self:Save(player, true)
	session.Released = true
	self._sessions[player] = nil
end

-- Public API ------------------------------------------------------------------------

function DataService.IsPersistent(self: DataService): boolean
	return self._persistent
end

function DataService.GetProfile(self: DataService, player: Player): Profile?
	local session = self._sessions[player]
	return if session and not session.Released then session.Profile else nil
end

function DataService.WaitForProfile(self: DataService, player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 60)
	while player.Parent and os.clock() < deadline do
		local profile = self:GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.2)
	end
	return nil
end

-- Mutates a profile through a callback. All writes go through here so the
-- profile is marked dirty and listeners can resync.
function DataService.Update(self: DataService, player: Player, mutator: (Profile) -> ())
	local session = self._sessions[player]
	if not session or session.Released then
		return
	end
	mutator(session.Profile)
	session.Dirty = true
	self.Changed:Fire(player)
end


local instance: DataService = setmetatable({
	ProfileLoaded = Signal.new(),
	Changed = Signal.new(),
	_sessions = {},
	_store = nil,
	_persistent = true,
	_memory = {},
	_jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false),
	_shuttingDown = false,
} :: State, DataService)

return instance
