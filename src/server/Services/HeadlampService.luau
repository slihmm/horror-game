--!strict
-- Server side of the headlamp: battery is server-authoritative, toggling is
-- validated and rate limited, and every character carries a replicated lamp
-- so other players see your beam sweep the dark. (The owning client hides
-- its replicated lamp and renders a responsive local one instead.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local HeadlampConfig = require(Shared.Config.HeadlampConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = ServerScriptService.Server.Services
local PlayerService = require(Services.PlayerService)
local CaveService = require(Services.CaveService)
local NoiseService = require(Services.NoiseService)
local DataService = require(Services.DataService)

local HeadlampService = {}
HeadlampService.__index = HeadlampService

type State = {
	_lamps: { [Player]: { Attachment: Attachment, Light: SpotLight } },
	_lastToggle: { [Player]: number },
}
export type HeadlampService = typeof(setmetatable({} :: State, HeadlampService))

local pitchLimiter = RateLimiter.new(12, HeadlampConfig.Remote.PitchSendRate * 1.5)

local function tintColor(player: Player): Color3
	local profile = DataService:GetProfile(player)
	local tint = profile and profile.Settings.HeadlampTint or "Default"
	if tint ~= "Default" and profile and not profile.Cosmetics[tint] then
		tint = "Default"
	end
	return HeadlampConfig.Tints[tint] or HeadlampConfig.Color
end

function HeadlampService.Init(self: HeadlampService)
	Net.Event("ToggleHeadlamp").OnServerEvent:Connect(function(player: Player)
		self:Toggle(player)
	end)
	Net.Unreliable("LookPitch").OnServerEvent:Connect(function(player: Player, pitch)
		if not pitchLimiter:Allow(player) then
			return
		end
		if type(pitch) ~= "number" or pitch ~= pitch then
			return
		end
		local lamp = self._lamps[player]
		if not lamp then
			return
		end
		local clamped = math.clamp(pitch, -80, 80)
		player:SetAttribute(Constants.Attributes.LookPitch, math.floor(clamped))
		lamp.Attachment.CFrame = CFrame.new(lamp.Attachment.Position) * CFrame.Angles(math.rad(clamped), 0, 0)
	end)
end

function HeadlampService.Start(self: HeadlampService)
	PlayerService.CharacterSpawned:Connect(function(player: Player, character: Model)
		self:_attach(player, character)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute(Constants.Attributes.Battery, HeadlampConfig.Battery.StartCharge)
		player:SetAttribute(Constants.Attributes.HeadlampOn, true)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Constants.Attributes.Battery, HeadlampConfig.Battery.StartCharge)
		player:SetAttribute(Constants.Attributes.HeadlampOn, true)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		self._lamps[player] = nil
		self._lastToggle[player] = nil
		pitchLimiter:Forget(player)
	end)
	-- Battery drain while the lamp is on underground.
	while true do
		local dt = 1
		task.wait(dt)
		for player, lamp in self._lamps do
			local on = player:GetAttribute(Constants.Attributes.HeadlampOn) == true
			local track = CaveService:GetTrack(player)
			local underground = track ~= nil and ZoneConfig.Get(track.Zone).Underground
			if on and underground then
				local battery = (player:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
				battery = math.max(0, battery - dt / HeadlampConfig.Battery.Lifetime)
				player:SetAttribute(Constants.Attributes.Battery, battery)
			end
			self:_refresh(player, lamp)
		end
	end
end

function HeadlampService._attach(self: HeadlampService, player: Player, character: Model)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "HeadlampAttachment"
	attachment.Position = Vector3.new(0, 0.35, -0.55)
	attachment.Parent = head
	local remote = HeadlampConfig.Remote
	local light = Instance.new("SpotLight")
	light.Name = "Headlamp"
	light.Face = Enum.NormalId.Front
	light.Brightness = remote.Brightness
	light.Range = remote.Range
	light.Angle = remote.Angle
	light.Shadows = remote.Shadows
	light.Color = tintColor(player)
	light.Parent = attachment
	light:AddTag(Constants.Tags.Headlamp)
	-- Keep the lamp state across deaths: a new life does not get a new battery.
	if player:GetAttribute(Constants.Attributes.Battery) == nil then
		player:SetAttribute(Constants.Attributes.Battery, HeadlampConfig.Battery.StartCharge)
	end
	if player:GetAttribute(Constants.Attributes.HeadlampOn) == nil then
		player:SetAttribute(Constants.Attributes.HeadlampOn, true)
	end
	local lamp = { Attachment = attachment, Light = light }
	self._lamps[player] = lamp
	self:_refresh(player, lamp)
end

-- Brightness multiplier for a given battery level (also used by clients).
function HeadlampService.BatteryScale(battery: number): number
	local cfg = HeadlampConfig.Battery
	if battery <= 0 then
		return 0
	end
	if battery >= cfg.LowThreshold then
		return 1
	end
	local t = battery / cfg.LowThreshold
	return cfg.EmptyBrightness + (1 - cfg.EmptyBrightness) * t
end

function HeadlampService._refresh(self: HeadlampService, player: Player, lamp: { Attachment: Attachment, Light: SpotLight })
	local on = player:GetAttribute(Constants.Attributes.HeadlampOn) == true
	local battery = (player:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
	local scale = HeadlampService.BatteryScale(battery)
	lamp.Light.Enabled = on and scale > 0
	lamp.Light.Brightness = HeadlampConfig.Remote.Brightness * scale
	lamp.Light.Color = tintColor(player)
end

function HeadlampService.Toggle(self: HeadlampService, player: Player)
	local now = os.clock()
	if now - (self._lastToggle[player] or 0) < HeadlampConfig.ToggleCooldown then
		return
	end
	self._lastToggle[player] = now
	local on = player:GetAttribute(Constants.Attributes.HeadlampOn) == true
	player:SetAttribute(Constants.Attributes.HeadlampOn, not on)
	local lamp = self._lamps[player]
	if lamp then
		self:_refresh(player, lamp)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		NoiseService.Emit(root.Position, PlayerConfig.Noise.HeadlampClick, "Click", player)
	end
end

-- Forces the lamp off for a moment (Horror Director: temporary darkness).
function HeadlampService.SetForcedOff(self: HeadlampService, player: Player, seconds: number)
	local lamp = self._lamps[player]
	if not lamp then
		return
	end
	lamp.Light.Enabled = false
	task.delay(seconds, function()
		local current = self._lamps[player]
		if current then
			self:_refresh(player, current)
		end
	end)
end

function HeadlampService.AddCharge(self: HeadlampService, player: Player, amount: number)
	local battery = (player:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
	player:SetAttribute(Constants.Attributes.Battery, math.clamp(battery + amount, 0, 1))
	local lamp = self._lamps[player]
	if lamp then
		self:_refresh(player, lamp)
	end
end

function HeadlampService.IsLit(self: HeadlampService, player: Player): boolean
	local lamp = self._lamps[player]
	return lamp ~= nil and lamp.Light.Enabled
end

-- World-space beam direction for the monster's perception.
function HeadlampService.BeamDirection(self: HeadlampService, player: Player): Vector3?
	local lamp = self._lamps[player]
	if not lamp or not lamp.Attachment.Parent then
		return nil
	end
	return lamp.Attachment.WorldCFrame.LookVector
end

function HeadlampService.RefreshTint(self: HeadlampService, player: Player)
	local lamp = self._lamps[player]
	if lamp then
		self:_refresh(player, lamp)
	end
end


local instance: HeadlampService = setmetatable({
	_lamps = {},
	_lastToggle = {},
} :: State, HeadlampService)

return instance
