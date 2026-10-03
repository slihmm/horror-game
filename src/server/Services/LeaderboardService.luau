--!strict
-- Global leaderboards backed by OrderedDataStores, refreshed on an interval
-- and published to clients through ReplicatedStorage.Leaderboards (one
-- StringValue of JSON per statistic). Writes are queued and batched; every
-- call is retried with backoff. Without DataStore access the boards show
-- the players currently on this server.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StatsConfig = require(Shared.Config.StatsConfig)

local Services = ServerScriptService.Server.Services
local DataService = require(Services.DataService)

type Entry = { Name: string, Value: number, UserId: number }

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

type State = {
	_stores: { [string]: OrderedDataStore },
	_queue: { [number]: { [string]: number } },
	_names: { [number]: string },
	_folder: Folder?,
}
export type LeaderboardService = typeof(setmetatable({} :: State, LeaderboardService))

local function retry<T>(fn: () -> T, attempts: number?): (boolean, T?)
	local delay = 1
	for attempt = 1, attempts or 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < (attempts or 3) then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

function LeaderboardService.Init(self: LeaderboardService)
	local folder = Instance.new("Folder")
	folder.Name = Constants.Folders.Leaderboards
	folder.Parent = ReplicatedStorage
	self._folder = folder
	for _, stat in StatsConfig.Stats do
		local value = Instance.new("StringValue")
		value.Name = stat.Key
		value.Value = "[]"
		value.Parent = folder
	end
end

function LeaderboardService.Start(self: LeaderboardService)
	if DataService:IsPersistent() then
		for _, stat in StatsConfig.Stats do
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore(StatsConfig.LeaderboardPrefix .. stat.Key)
			end)
			if ok then
				self._stores[stat.Key] = store
			end
		end
	end
	DataService.Changed:Connect(function(player: Player)
		self:_queuePlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_queuePlayer(player)
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			self:_flush()
		end
	end)
	while true do
		self:_refresh()
		task.wait(StatsConfig.LeaderboardRefresh)
	end
end

function LeaderboardService._queuePlayer(self: LeaderboardService, player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	self._names[player.UserId] = player.DisplayName
	local values = {}
	for _, stat in StatsConfig.Stats do
		values[stat.Key] = math.floor((profile.Stats :: any)[stat.Key] or 0)
	end
	self._queue[player.UserId] = values
end

function LeaderboardService._flush(self: LeaderboardService)
	if next(self._stores) == nil then
		self._queue = {}
		return
	end
	local queue = self._queue
	self._queue = {}
	for userId, values in queue do
		for _, stat in StatsConfig.Stats do
			local store = self._stores[stat.Key]
			local value = values[stat.Key]
			if store and value and not (stat.IgnoreZero and value <= 0) then
				retry(function(): boolean
					store:SetAsync(tostring(userId), value)
					return true
				end)
			end
		end
	end
end

function LeaderboardService._name(self: LeaderboardService, userId: number): string
	local cached = self._names[userId]
	if cached then
		return cached
	end
	local ok, name = retry(function()
		return Players:GetNameFromUserIdAsync(userId)
	end, 2)
	local result = if ok and type(name) == "string" then name else "unknown"
	self._names[userId] = result
	return result
end

function LeaderboardService._refresh(self: LeaderboardService)
	local folder = self._folder
	if not folder then
		return
	end
	for _, stat in StatsConfig.Stats do
		local entries: { Entry } = {}
		local store = self._stores[stat.Key]
		if store then
			local ok, pages = retry(function()
				return store:GetSortedAsync(stat.Order == "asc", StatsConfig.LeaderboardSize, if stat.IgnoreZero then 1 else nil)
			end)
			if ok and pages then
				for _, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key) or 0
					table.insert(entries, { UserId = userId, Name = self:_name(userId), Value = item.value })
				end
			end
		else
			-- Offline fallback: this server's players.
			for _, player in Players:GetPlayers() do
				local profile = DataService:GetProfile(player)
				if profile then
					local value = (profile.Stats :: any)[stat.Key] or 0
					if not (stat.IgnoreZero and value <= 0) then
						table.insert(entries, { UserId = player.UserId, Name = player.DisplayName, Value = value })
					end
				end
			end
			table.sort(entries, function(a: Entry, b: Entry)
				return if stat.Order == "asc" then a.Value < b.Value else a.Value > b.Value
			end)
			while #entries > StatsConfig.LeaderboardSize do
				table.remove(entries)
			end
		end
		local value = folder:FindFirstChild(stat.Key) :: StringValue?
		if value then
			value.Value = HttpService:JSONEncode(entries)
		end
	end
end

local instance: LeaderboardService = setmetatable({
	_stores = {},
	_queue = {},
	_names = {},
	_folder = nil,
} :: State, LeaderboardService)

return instance
