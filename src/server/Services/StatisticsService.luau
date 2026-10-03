--!strict
-- Keeps each client's view of its own profile in sync (stats, discovered
-- lore, collection, satchel, settings) and accepts validated settings
-- changes. Clients never write statistics; they only read snapshots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local HeadlampConfig = require(Shared.Config.HeadlampConfig)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = ServerScriptService.Server.Services
local DataService = require(Services.DataService)
local ExpeditionService = require(Services.ExpeditionService)
local HeadlampService = require(Services.HeadlampService)

local SYNC_THROTTLE = 1

local StatisticsService = {}
StatisticsService.__index = StatisticsService

type State = {
	_pending: { [Player]: boolean },
	_lastSync: { [Player]: number },
}
export type StatisticsService = typeof(setmetatable({} :: State, StatisticsService))

local settingsLimiter = RateLimiter.new(8, 2)

local function snapshot(player: Player): Types.ProfileSnapshot?
	local profile = DataService:GetProfile(player)
	if not profile then
		return nil
	end
	local lore = {}
	for id in profile.Lore do
		table.insert(lore, id)
	end
	local cosmetics = {}
	for id in profile.Cosmetics do
		table.insert(cosmetics, id)
	end
	local satchel = {}
	for id, count in ExpeditionService:GetSatchel(player) do
		table.insert(satchel, { id = id, count = count })
	end
	return {
		Stats = table.clone(profile.Stats),
		Lore = lore,
		SecretsFound = profile.Stats.SecretsFound,
		Currency = profile.Currency,
		Collection = table.clone(profile.Collection),
		Cosmetics = cosmetics,
		Settings = table.clone(profile.Settings),
		Satchel = satchel,
		Persistent = DataService:IsPersistent(),
	}
end

-- Validates a single setting. Returns the sanitized value or nil.
local function validateSetting(player: Player, key: string, value: any): any
	if key == "CameraMotion" or key == "Brightness" then
		if type(value) == "number" and value == value then
			return math.clamp(value, 0, 1)
		end
	elseif key == "HeadlampTint" then
		if type(value) == "string" and HeadlampConfig.Tints[value] then
			local profile = DataService:GetProfile(player)
			if value == "Default" or (profile and profile.Cosmetics[value .. "Lens"]) then
				return value
			end
		end
	end
	return nil
end

function StatisticsService.Init(self: StatisticsService)
	Net.Event("UpdateSetting").OnServerEvent:Connect(function(player: Player, key: any, value: any)
		if not settingsLimiter:Allow(player) or type(key) ~= "string" then
			return
		end
		local clean = validateSetting(player, key, value)
		if clean == nil then
			return
		end
		DataService:Update(player, function(profile)
			profile.Settings[key] = clean
		end)
		if key == "HeadlampTint" then
			HeadlampService:RefreshTint(player)
		end
	end)
end

function StatisticsService.Start(self: StatisticsService)
	DataService.ProfileLoaded:Connect(function(player: Player)
		self:Sync(player, true)
	end)
	DataService.Changed:Connect(function(player: Player)
		self:Sync(player, false)
	end)
	ExpeditionService.SatchelChanged:Connect(function(player: Player)
		self:Sync(player, false)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self._pending[player] = nil
		self._lastSync[player] = nil
		settingsLimiter:Forget(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService:GetProfile(player) then
			self:Sync(player, true)
		end
	end
end

-- Sends a snapshot, throttled so bursts of changes coalesce.
function StatisticsService.Sync(self: StatisticsService, player: Player, immediate: boolean)
	local now = os.clock()
	local last = self._lastSync[player] or 0
	if not immediate and now - last < SYNC_THROTTLE then
		if not self._pending[player] then
			self._pending[player] = true
			task.delay(SYNC_THROTTLE - (now - last), function()
				self._pending[player] = nil
				if player.Parent then
					self:Sync(player, true)
				end
			end)
		end
		return
	end
	self._lastSync[player] = now
	local data = snapshot(player)
	if data then
		player:SetAttribute(Constants.Attributes.Currency, data.Currency)
		Net.Event("ProfileSync"):FireClient(player, data)
	end
end

local instance: StatisticsService = setmetatable({
	_pending = {},
	_lastSync = {},
} :: State, StatisticsService)

return instance
