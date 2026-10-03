--!strict
-- Applies the current zone's lighting preset locally, blends between zones,
-- and runs the small atmospheric effects that only exist near the player:
-- dust drifting through the beam, drips falling from the ceiling, and the
-- guttering of nearby lanterns and candles.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local LightingConfig = require(Shared.Config.LightingConfig)
local MathUtil = require(Shared.Utility.MathUtil)

local AudioController = require(script.Parent.AudioController)

local LocalPlayer = Players.LocalPlayer

type Preset = LightingConfig.Preset

local LightingController = {}
LightingController.__index = LightingController

type State = {
	Atmosphere: Atmosphere?,
	Grade: ColorCorrectionEffect?,
	Bloom: BloomEffect?,
	_zone: string,
	_override: Preset?,
	_brightnessSetting: number,
	_dustPart: Part?,
	_dust: ParticleEmitter?,
	_preset: Preset?,
	_nextDrip: number,
	_rng: Random,
	_time: number,
	_terrainParams: RaycastParams,
	_zoneChangedAt: number,
}
export type LightingController = typeof(setmetatable({} :: State, LightingController))

local function ensure<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return (existing :: any) :: T
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = Lighting
	return (created :: any) :: T
end

function LightingController.Init(self: LightingController)
	-- Remove default post effects that would fight the presets.
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end
	self.Atmosphere = ensure("Atmosphere", "DescentAtmosphere")
	self.Grade = ensure("ColorCorrectionEffect", "DescentGrade")
	self.Bloom = ensure("BloomEffect", "DescentBloom")

	-- Dust volume that follows the camera; LightInfluence 1 means the motes
	-- are only visible where light actually falls (i.e. in the beam).
	local dustPart = Instance.new("Part")
	dustPart.Name = "DustVolume"
	dustPart.Anchored = true
	dustPart.CanCollide = false
	dustPart.CanQuery = false
	dustPart.CanTouch = false
	dustPart.Transparency = 1
	dustPart.Size = Vector3.new(36, 20, 36)
	dustPart.Parent = Workspace
	local dust = Instance.new("ParticleEmitter")
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(8, 14)
	dust.Speed = NumberRange.new(0.05, 0.25)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Drag = 0.5
	dust.Acceleration = Vector3.new(0, -0.03, 0)
	dust.RotSpeed = NumberRange.new(-20, 20)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.07),
		NumberSequenceKeypoint.new(0.85, 0.07),
		NumberSequenceKeypoint.new(1, 0),
	})
	dust.Transparency = NumberSequence.new(0.25)
	dust.LightInfluence = 1
	dust.LightEmission = 0
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 230, 220))
	dust.Parent = dustPart
	self._dustPart = dustPart
	self._dust = dust

	self._terrainParams.FilterType = Enum.RaycastFilterType.Include
	self._terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
end

function LightingController.Start(self: LightingController)
	local function onZone()
		local zone = LocalPlayer:GetAttribute(Constants.Attributes.Zone)
		if type(zone) == "string" then
			self:_setZone(zone, LightingConfig.TransitionTime)
		end
	end
	LocalPlayer:GetAttributeChangedSignal(Constants.Attributes.Zone):Connect(onZone)
	self:_setZone("Surface", 0)
	onZone()
	RunService.Heartbeat:Connect(function(dt: number)
		self:_tick(dt)
	end)
end

function LightingController._presetFor(self: LightingController, zone: string): Preset
	return self._override or LightingConfig.Presets[zone] or LightingConfig.Presets.UpperCave
end

function LightingController._setZone(self: LightingController, zone: string, time: number)
	self._zone = zone
	self._zoneChangedAt = os.clock()
	self:Apply(self:_presetFor(zone), time)
end

-- Forces a preset regardless of zone (cinematics). nil restores the zone's.
function LightingController.SetOverride(self: LightingController, preset: Preset?, time: number?)
	self._override = preset
	self:Apply(self:_presetFor(self._zone), time or LightingConfig.TransitionTime)
end

-- 0..1 from the settings menu.
function LightingController.SetBrightnessSetting(self: LightingController, value: number)
	self._brightnessSetting = math.clamp(value, 0, 1)
	local preset = self._preset
	if preset then
		self:Apply(preset, 0.5)
	end
end

function LightingController.Apply(self: LightingController, preset: Preset, time: number)
	self._preset = preset
	local range = LightingConfig.BrightnessSettingRange
	local exposure = preset.ExposureCompensation + MathUtil.lerp(range.Min, range.Max, self._brightnessSetting) - MathUtil.lerp(range.Min, range.Max, 0.5)
	local info = TweenInfo.new(math.max(time, 0.01), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local function go(instance: Instance?, goal: { [string]: any })
		if not instance then
			return
		end
		if time <= 0 then
			for k, v in goal do
				(instance :: any)[k] = v
			end
		else
			TweenService:Create(instance, info, goal):Play()
		end
	end
	go(Lighting, {
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		Brightness = preset.Brightness,
		ExposureCompensation = exposure,
		EnvironmentDiffuseScale = preset.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = preset.EnvironmentSpecularScale,
	})
	-- ClockTime snaps (tweening it would sweep the sun across the sky).
	Lighting.ClockTime = preset.ClockTime
	go(self.Atmosphere, preset.Atmosphere)
	go(self.Grade, preset.ColorCorrection)
	go(self.Bloom, preset.Bloom)
	local dust = self._dust
	if dust then
		dust.Rate = preset.Dust * 26
	end
end

function LightingController._tick(self: LightingController, dt: number)
	self._time += dt
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local dustPart = self._dustPart
	if dustPart then
		dustPart.CFrame = CFrame.new(camera.CFrame.Position)
	end
	self:_tickDrips(camera.CFrame.Position)
	self:_tickFlicker(camera.CFrame.Position)
	self:_tickDepthBlend(dt)
end

-- Continuous change with depth in the shaft and on the climb out.
function LightingController._tickDepthBlend(self: LightingController, dt: number)
	local blend = LightingConfig.DepthBlends[self._zone]
	if not blend or self._override or os.clock() - self._zoneChangedAt < LightingConfig.TransitionTime then
		return
	end
	local depth = (LocalPlayer:GetAttribute(Constants.Attributes.Depth) :: number?) or 0
	local t = math.clamp((depth - blend.Depth.Min) / (blend.Depth.Max - blend.Depth.Min), 0, 1)
	local range = LightingConfig.BrightnessSettingRange
	local setting = MathUtil.lerp(range.Min, range.Max, self._brightnessSetting) - MathUtil.lerp(range.Min, range.Max, 0.5)
	local ambient = blend.Shallow.Ambient:Lerp(blend.Deep.Ambient, t)
	local exposure = MathUtil.lerp(blend.Shallow.Exposure, blend.Deep.Exposure, t) + setting
	local k = MathUtil.damp(2, dt)
	Lighting.Ambient = Lighting.Ambient:Lerp(ambient, k)
	Lighting.ExposureCompensation = MathUtil.lerp(Lighting.ExposureCompensation, exposure, k)
end

-- Water dripping from the ceiling near the player.
function LightingController._tickDrips(self: LightingController, origin: Vector3)
	local preset = self._preset
	if not preset or preset.Drips <= 0 then
		return
	end
	local now = os.clock()
	if now < self._nextDrip then
		return
	end
	local rng = self._rng
	self._nextDrip = now + rng:NextNumber(0.6, 2.5) / preset.Drips
	local probe = origin + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14))
	local ceiling = Workspace:Raycast(probe, Vector3.yAxis * 40, self._terrainParams)
	local floor = Workspace:Raycast(probe, Vector3.yAxis * -40, self._terrainParams)
	if not ceiling or not floor then
		return
	end
	local drop = Instance.new("Part")
	drop.Name = "Drip"
	drop.Anchored = true
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CanTouch = false
	drop.CastShadow = false
	drop.Material = Enum.Material.Glass
	drop.Color = Color3.fromRGB(200, 215, 225)
	drop.Transparency = 0.35
	drop.Reflectance = 0.3
	drop.Size = Vector3.new(0.08, 0.3, 0.08)
	drop.CFrame = CFrame.new(ceiling.Position - Vector3.yAxis * 0.3)
	drop.Parent = Workspace
	local height = ceiling.Position.Y - floor.Position.Y
	local fallTime = math.sqrt(2 * height / Workspace.Gravity)
	local tween = TweenService:Create(drop, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(floor.Position + Vector3.yAxis * 0.1),
	})
	tween.Completed:Once(function()
		drop:Destroy()
		if (floor.Position - origin).Magnitude < 18 then
			AudioController:PlayAt("Drip", floor.Position, { Group = "Ambient", Volume = 0.7, MaxDistance = 40 })
		end
	end)
	tween:Play()
end

-- Lanterns and candles gutter: light brightness wobbles on nearby tagged parts.
function LightingController._tickFlicker(self: LightingController, origin: Vector3)
	for _, part in CollectionService:GetTagged(Constants.Tags.FlickerLight) do
		if part:IsA("BasePart") and (part.Position - origin).Magnitude < 140 then
			local light = part:FindFirstChildWhichIsA("Light")
			if light then
				local base = light:GetAttribute("BaseBrightness") :: number?
				if not base then
					base = light.Brightness
					light:SetAttribute("BaseBrightness", base)
				end
				local seed = (part.Position.X + part.Position.Z) * 0.13
				local n = math.noise(self._time * 3.1, seed) * 0.5 + math.noise(self._time * 11, seed + 4) * 0.25
				light.Brightness = (base :: number) * math.clamp(0.85 + n, 0.35, 1.2)
			end
		end
	end
end

function LightingController.GetZone(self: LightingController): string
	return self._zone
end

local instance: LightingController = setmetatable({
	Atmosphere = nil,
	Grade = nil,
	Bloom = nil,
	_zone = "Surface",
	_override = nil,
	_brightnessSetting = 0.5,
	_dustPart = nil,
	_dust = nil,
	_preset = nil,
	_nextDrip = 0,
	_rng = Random.new(),
	_time = 0,
	_terrainParams = RaycastParams.new(),
	_zoneChangedAt = 0,
} :: State, LightingController)

return instance
