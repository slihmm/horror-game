--!strict
-- The player's own headlamp, rendered locally for zero-latency response:
-- a narrow shadow-casting core beam, a weak wide spill, and a faint glow at
-- the body. It trails the view very slightly, flickers now and then, dims as
-- the battery dies, and can be made to fail by the Horror Director.
--
-- The server's replicated lamp on our own head is hidden locally; everyone
-- else sees that one.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local HeadlampConfig = require(Shared.Config.HeadlampConfig)
local HeadlampMath = require(Shared.HeadlampMath)
local MathUtil = require(Shared.Utility.MathUtil)
local Noise = require(Shared.Utility.Noise)

local AudioController = require(script.Parent.AudioController)

local LocalPlayer = Players.LocalPlayer

local HeadlampController = {}
HeadlampController.__index = HeadlampController

type State = {
	_part: Part?,
	_core: SpotLight?,
	_spill: SpotLight?,
	_glow: PointLight?,
	_cf: CFrame?,
	_flickerUntil: number,
	_flickerSeverity: number,
	_darkUntil: number,
	-- External multiplier (cinematics) and a hard override (nil = none).
	Multiplier: number,
	_rng: Random,
	_time: number,
	_hiddenConnection: RBXScriptConnection?,
}
export type HeadlampController = typeof(setmetatable({} :: State, HeadlampController))

local function makeSpot(parent: Instance, cfg: { Brightness: number, Range: number, Angle: number, Shadows: boolean }): SpotLight
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Brightness = cfg.Brightness
	light.Range = cfg.Range
	light.Angle = cfg.Angle
	light.Shadows = cfg.Shadows
	light.Color = HeadlampConfig.Color
	light.Parent = parent
	return light
end

function HeadlampController.Init(self: HeadlampController)
	local part = Instance.new("Part")
	part.Name = "LocalHeadlamp"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = Workspace
	self._part = part
	self._core = makeSpot(part, HeadlampConfig.Core)
	self._spill = makeSpot(part, HeadlampConfig.Spill)
	local glow = Instance.new("PointLight")
	glow.Brightness = HeadlampConfig.Self.Brightness
	glow.Range = HeadlampConfig.Self.Range
	glow.Shadows = false
	glow.Color = HeadlampConfig.Color
	glow.Parent = part
	self._glow = glow

	local function onCharacter(character: Model)
		self:_hideReplicatedLamp(character)
	end
	LocalPlayer.CharacterAdded:Connect(onCharacter)
	if LocalPlayer.Character then
		task.spawn(onCharacter, LocalPlayer.Character)
	end
end

function HeadlampController.Start(self: HeadlampController)
	ContextActionService:BindAction("DescentHeadlamp", function(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			AudioController:Play2D("HeadlampClick", { Group = "Effects", Volume = 0.8 })
			Net.Event("ToggleHeadlamp"):FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("DescentHeadlamp", "Lamp")
	ContextActionService:SetPosition("DescentHeadlamp", UDim2.new(1, -100, 1, -210))

	-- Send look pitch so others see where our beam points.
	task.spawn(function()
		local remote = Net.Unreliable("LookPitch")
		local lastSent = 999
		while true do
			task.wait(1 / HeadlampConfig.Remote.PitchSendRate)
			local camera = Workspace.CurrentCamera
			if camera then
				local pitch = math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
				if math.abs(pitch - lastSent) > 1.5 then
					lastSent = pitch
					remote:FireServer(pitch)
				end
			end
		end
	end)

	RunService:BindToRenderStep("DescentHeadlamp", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		self:_update(dt)
	end)
end

-- Hides the server-replicated lamp on our own head (we render our own).
function HeadlampController._hideReplicatedLamp(self: HeadlampController, character: Model)
	if self._hiddenConnection then
		self._hiddenConnection:Disconnect()
		self._hiddenConnection = nil
	end
	local head = character:WaitForChild("Head", 10)
	local attachment = head and head:WaitForChild("HeadlampAttachment", 10)
	local light = attachment and attachment:WaitForChild("Headlamp", 10)
	if light and light:IsA("SpotLight") then
		light.Enabled = false
		-- The server re-enables it when toggling; keep it off locally.
		self._hiddenConnection = light:GetPropertyChangedSignal("Enabled"):Connect(function()
			if light.Enabled then
				light.Enabled = false
			end
		end)
	end
end

-- A burst of flickering. severity 0..1.
function HeadlampController.Flicker(self: HeadlampController, duration: number, severity: number?)
	self._flickerUntil = math.max(self._flickerUntil, os.clock() + duration)
	self._flickerSeverity = severity or 0.7
end

-- The lamp dies completely for a few seconds, then sputters back.
function HeadlampController.Darkness(self: HeadlampController, seconds: number)
	self._darkUntil = os.clock() + seconds
	AudioController:Play2D("HeadlampClick", { Group = "Effects", Volume = 0.5, Pitch = 0.8 })
	task.delay(seconds, function()
		self:Flicker(1.2, 0.9)
	end)
end

function HeadlampController.IsOn(self: HeadlampController): boolean
	return LocalPlayer:GetAttribute(Constants.Attributes.HeadlampOn) == true and os.clock() >= self._darkUntil
end

function HeadlampController.GetCFrame(self: HeadlampController): CFrame?
	return self._cf
end

function HeadlampController._update(self: HeadlampController, dt: number)
	local camera = Workspace.CurrentCamera
	local part = self._part
	local core, spill, glow = self._core, self._spill, self._glow
	if not camera or not part or not core or not spill or not glow then
		return
	end
	self._time += dt
	local now = os.clock()

	-- Follow the view with a hint of lag, so fast turns sweep the beam.
	local target = camera.CFrame * CFrame.new(HeadlampConfig.CameraOffset)
	local previous = self._cf
	local current: CFrame
	if not previous or (previous.Position - target.Position).Magnitude > 20 then
		current = target
	else
		current = previous:Lerp(target, MathUtil.damp(HeadlampConfig.FollowSharpness, dt))
	end
	self._cf = current
	part.CFrame = current

	-- Brightness: switch, battery, flicker, overrides.
	local on = LocalPlayer:GetAttribute(Constants.Attributes.HeadlampOn) == true
	local battery = (LocalPlayer:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
	local scale = HeadlampMath.BatteryScale(battery)
	if not on or now < self._darkUntil then
		scale = 0
	end

	-- Random flicker bursts: rare when healthy, frequent on a dying battery.
	local flickerCfg = HeadlampConfig.Flicker
	local chance = if battery < HeadlampConfig.Battery.LowThreshold then flickerCfg.LowBatteryChancePerSecond else flickerCfg.AmbientChancePerSecond
	if on and self._rng:NextNumber() < chance * dt then
		self:Flicker(self._rng:NextNumber(flickerCfg.BurstDuration.Min, flickerCfg.BurstDuration.Max), if battery < 0.2 then 0.9 else 0.45)
	end
	if now < self._flickerUntil then
		local n = Noise.fbm1(self._time * 22, 3.7, 2)
		local drop = math.clamp((n + 0.2) * 1.4, 0, 1) * self._flickerSeverity
		scale *= math.max(flickerCfg.MinBrightnessScale, 1 - drop)
	end
	scale *= self.Multiplier

	local tint = LocalPlayer:GetAttribute(Constants.Attributes.HeadlampTint)
	local color = HeadlampMath.TintColor(if type(tint) == "string" then tint else nil)
	core.Brightness = HeadlampConfig.Core.Brightness * scale
	spill.Brightness = HeadlampConfig.Spill.Brightness * scale
	glow.Brightness = HeadlampConfig.Self.Brightness * scale
	core.Color = color
	spill.Color = color
	glow.Color = color
	local enabled = scale > 0.001
	core.Enabled = enabled
	spill.Enabled = enabled
	glow.Enabled = enabled
end

local instance: HeadlampController = setmetatable({
	_part = nil,
	_core = nil,
	_spill = nil,
	_glow = nil,
	_cf = nil,
	_flickerUntil = 0,
	_flickerSeverity = 0,
	_darkUntil = 0,
	Multiplier = 1,
	_rng = Random.new(),
	_time = 0,
	_hiddenConnection = nil,
} :: State, HeadlampController)

return instance
