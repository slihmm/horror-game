--!strict
-- How the Lamplighter is perceived.
--
-- Footsteps are the signature. The server counts strides; each stride here
-- becomes a footfall whose character depends on distance:
--   far away:  BOOM ... long silence ... BOOM      (most steps lost in rock)
--   closer:    BOOM ... BOOM ... BOOM              (louder, echo thinning)
--   near:      BOOM BOOM BOOM, grit falling, camera trembling, breathing
--   chasing:   BOOMBOOMBOOMBOOM
-- Players learn to read "it found me" without ever seeing it.
--
-- The creature itself is built and animated locally from the server's
-- invisible root: tall, bowed, long-armed, its head crowned with the dead
-- explorers' lamps, a few of which still flicker. Usually you see the lamps
-- moving in the dark long before you see what carries them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local MathUtil = require(Shared.Utility.MathUtil)

local AudioController = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local UIController = require(script.Parent.UIController)

local LocalPlayer = Players.LocalPlayer
local presence = MonsterConfig.Presence

type Limb = { Part: BasePart, Base: CFrame, Kind: string, Side: number }

local MonsterPresenceController = {}
MonsterPresenceController.__index = MonsterPresenceController

type State = {
	_root: BasePart?,
	_model: Model?,
	_limbs: { Limb },
	_lamps: { PointLight },
	_lampCount: number,
	_visual: CFrame?,
	_phase: number,
	_lastPos: Vector3?,
	_breath: Sound?,
	_nextHeartbeat: number,
	_rng: Random,
	_time: number,
	_connections: { RBXScriptConnection },
	_echo: EchoSoundEffect,
	_vignetteRaised: boolean,
}
export type MonsterPresenceController = typeof(setmetatable({} :: State, MonsterPresenceController))

local SKIN = Color3.fromRGB(48, 44, 42)
local HEIGHT = MonsterConfig.Visual.Height

local function part(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

function MonsterPresenceController._build(self: MonsterPresenceController, lampCount: number)
	if self._model then
		self._model:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "LamplighterVisual"
	local limbs: { Limb } = {}
	local lamps: { PointLight } = {}
	local function add(name: string, kind: string, side: number, size: Vector3, base: CFrame, shape: Enum.PartType?, color: Color3?, material: Enum.Material?)
		local p = part(model, name, size, color or SKIN, material or Enum.Material.SmoothPlastic, shape)
		local limb: Limb = { Part = p, Base = base, Kind = kind, Side = side }
		table.insert(limbs, limb)
		return p
	end
	-- Local space: origin at the feet, facing -Z. Bowed forward.
	add("Pelvis", "Body", 0, Vector3.new(2.2, 1.3, 1.4), CFrame.new(0, 6.3, 0))
	add("Torso", "Body", 0, Vector3.new(2.6, 3.4, 1.5), CFrame.new(0, 8.3, -0.6) * CFrame.Angles(math.rad(-24), 0, 0))
	add("Neck", "Head", 0, Vector3.new(0.7, 1.2, 0.7), CFrame.new(0, 10.1, -1.6) * CFrame.Angles(math.rad(-50), 0, 0))
	add("Head", "Head", 0, Vector3.new(1.4, 1.7, 1.6), CFrame.new(0, 10.4, -2.4) * CFrame.Angles(math.rad(-35), 0, 0), nil, SKIN)
	for _, side in { -1, 1 } do
		add("Thigh", "Leg", side, Vector3.new(0.75, 3.4, 0.75), CFrame.new(side * 0.75, 4.6, 0))
		add("Shin", "Shin", side, Vector3.new(0.6, 3.4, 0.6), CFrame.new(side * 0.8, 1.7, 0.2))
		add("Foot", "Shin", side, Vector3.new(0.8, 0.4, 2.2), CFrame.new(side * 0.8, 0.2, -0.6))
		add("UpperArm", "Arm", side, Vector3.new(0.55, 3.2, 0.55), CFrame.new(side * 1.6, 8.2, -1) * CFrame.Angles(math.rad(-10), 0, math.rad(side * 6)))
		add("Forearm", "Arm", side, Vector3.new(0.45, 3.4, 0.45), CFrame.new(side * 1.8, 5.2, -1.4))
		add("Hand", "Arm", side, Vector3.new(0.3, 1.6, 0.9), CFrame.new(side * 1.85, 3.1, -1.5))
	end
	-- The crown of lamps.
	for i = 1, lampCount do
		local angle = (i / lampCount) * math.pi * 1.6 - math.pi * 0.8
		local base = CFrame.new(0, 10.4, -2.4) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(math.sin(angle) * 0.75, 0.7 + math.cos(angle) * 0.25, -0.1) * CFrame.Angles(math.rad(-20), angle * 0.4, 0)
		add("Lamp", "Head", 0, Vector3.new(0.4, 0.35, 0.35), base, nil, Color3.fromRGB(60, 56, 50), Enum.Material.Metal)
		local lit = self._rng:NextNumber() < 0.55
		local lens = add("Lens", "Head", 0, Vector3.new(0.05, 0.28, 0.28), base * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder, if lit then Color3.fromRGB(255, 214, 160) else Color3.fromRGB(70, 70, 66), if lit then Enum.Material.Neon else Enum.Material.Glass)
		if lit then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 200, 140)
			light.Range = 9
			light.Brightness = 0.35
			light.Shadows = false
			light.Parent = lens
			table.insert(lamps, light)
		end
	end
	model.Parent = Workspace
	self._model = model
	self._limbs = limbs
	self._lamps = lamps
	self._lampCount = lampCount
end

function MonsterPresenceController.Start(self: MonsterPresenceController)
	self._echo.Delay = 0.32
	self._echo.Feedback = 0.35
	self._echo.DryLevel = 0
	self._echo.WetLevel = -6
	local function onRoot(root: Instance)
		if root:IsA("BasePart") then
			self:_attach(root)
		end
	end
	CollectionService:GetInstanceAddedSignal(Constants.Tags.MonsterRoot):Connect(onRoot)
	for _, root in CollectionService:GetTagged(Constants.Tags.MonsterRoot) do
		onRoot(root)
	end
	Net.Event("WorldEffect").OnClientEvent:Connect(function(kind: string, position: Vector3, params: any)
		if kind == "MonsterVocal" then
			self:_vocal(if type(params) == "table" then params.Kind else nil, position)
		elseif kind == "MonsterHit" then
			local victim = if type(params) == "table" then params.Victim else nil
			if victim == LocalPlayer.UserId then
				CameraController:AddTrauma(1)
				UIController:FlashDamage(0.7)
				AudioController:Play2D("Hurt", { Group = "Voice" })
			end
			AudioController:PlayAt("MonsterScrape", position, { Group = "Monster", Volume = 1, MaxDistance = 120 })
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		self:_render(dt)
	end)
end

function MonsterPresenceController._attach(self: MonsterPresenceController, root: BasePart)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	self._root = root
	self._visual = nil
	self:_build((root:GetAttribute("Lamps") :: number?) or MonsterConfig.Visual.Lamps)
	table.insert(self._connections, root:GetAttributeChangedSignal(Constants.Attributes.MonsterStep):Connect(function()
		self:_footstep()
	end))
	table.insert(self._connections, root:GetAttributeChangedSignal("Lamps"):Connect(function()
		self:_build((root:GetAttribute("Lamps") :: number?) or MonsterConfig.Visual.Lamps)
	end))
	table.insert(self._connections, root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(Workspace) then
			self._root = nil
			if self._model then
				self._model:Destroy()
				self._model = nil
			end
		end
	end))
end

function MonsterPresenceController._distance(self: MonsterPresenceController): number
	local root = self._root
	local cam = Workspace.CurrentCamera
	if not root or not cam then
		return math.huge
	end
	return (root.Position - cam.CFrame.Position).Magnitude
end

-- One stride of the Lamplighter, shaped by distance.
function MonsterPresenceController._footstep(self: MonsterPresenceController)
	local root = self._root
	if not root then
		return
	end
	local distance = self:_distance()
	if distance > presence.AudibleRange then
		return
	end
	-- Far away, the rock swallows most steps.
	if distance > presence.SparseRange then
		local t = (distance - presence.SparseRange) / (presence.AudibleRange - presence.SparseRange)
		if self._rng:NextNumber() > MathUtil.lerp(1, presence.SparseMinChance, t) then
			return
		end
	end
	local feet = root.Position - Vector3.yAxis * (HEIGHT / 2)
	local nearness = 1 - math.clamp(distance / presence.AudibleRange, 0, 1)
	-- Echo is strongest at mid-to-far range: close steps are dry and heavy.
	local echo = self._echo:Clone()
	echo.WetLevel = MathUtil.lerp(-2, -18, nearness)
	AudioController:PlayAt("MonsterStep", feet, {
		Group = "Monster",
		Volume = MathUtil.lerp(0.55, 1.3, nearness),
		Pitch = self._rng:NextNumber(0.92, 1.05),
		MinDistance = 30,
		MaxDistance = presence.AudibleRange,
		Effects = { echo :: Instance },
		Jitter = false,
	})
	if distance < presence.DebrisRange then
		AudioController:PlayAt("MonsterStepDebris", feet + Vector3.yAxis * 6, { Group = "Monster", Volume = 0.7 * nearness, MaxDistance = 60 })
	end
	if distance < presence.ShakeRange then
		CameraController:AddTrauma(0.08 + 0.3 * (1 - distance / presence.ShakeRange))
	end
	-- Loose stones shiver near the player when it is close.
	if distance < presence.ShakeRange * 0.7 and self._rng:NextNumber() < 0.35 then
		local cam = Workspace.CurrentCamera
		if cam then
			AudioController:PlayAt("PebbleSkitter", cam.CFrame.Position + Vector3.new(self._rng:NextNumber(-6, 6), 4, self._rng:NextNumber(-6, 6)), { Group = "Effects", Volume = 0.5 })
		end
	end
end

function MonsterPresenceController._vocal(self: MonsterPresenceController, kind: string?, position: Vector3)
	local distance = self:_distance()
	local root = self._root
	local sound = if kind == "Roar" then "MonsterRoar" elseif kind == "Growl" then "MonsterGrowl" elseif kind == "Breath" then "MonsterBreath" else nil
	if not sound then
		return
	end
	if root then
		AudioController:PlayAttached(sound, root, { Group = "Monster", Volume = 1, MinDistance = 20, MaxDistance = presence.AudibleRange })
	else
		AudioController:PlayAt(sound, position, { Group = "Monster", MinDistance = 20, MaxDistance = presence.AudibleRange })
	end
	if kind == "Roar" and distance < 120 then
		CameraController:AddTrauma(0.6 * (1 - distance / 120))
	end
end

function MonsterPresenceController._render(self: MonsterPresenceController, dt: number)
	local root = self._root
	local model = self._model
	if not root or not model then
		return
	end
	self._time += dt
	-- Smooth the replicated root (network updates are stepped).
	local target = root.CFrame * CFrame.new(0, -HEIGHT / 2, 0)
	local previous = self._visual
	local current: CFrame
	if not previous or (previous.Position - target.Position).Magnitude > 25 then
		current = target
	else
		current = previous:Lerp(target, MathUtil.damp(10, dt))
	end
	self._visual = current
	local position = current.Position
	local moved = if self._lastPos then (position - self._lastPos).Magnitude else 0
	self._lastPos = position
	local speed = moved / math.max(dt, 1e-3)
	self._phase += moved / presence.StrideLength * math.pi
	local state = root:GetAttribute(Constants.Attributes.MonsterState)
	local stride = math.clamp(speed / 10, 0, 1)
	local crouch = if state == "Dormant" then 3.2 elseif state == "Listening" or state == "Ambushing" then 0.8 else 0
	local bob = math.abs(math.sin(self._phase)) * 0.35 * stride
	local base = current * CFrame.new(0, -crouch + bob, 0)

	for _, limb in self._limbs do
		local cf = limb.Base
		if limb.Kind == "Leg" or limb.Kind == "Shin" then
			local swing = math.sin(self._phase + (if limb.Side > 0 then math.pi else 0)) * 0.55 * stride
			local hip = CFrame.new(limb.Side * 0.75, 6.2, 0)
			cf = hip * CFrame.Angles(swing, 0, 0) * hip:Inverse() * cf
		elseif limb.Kind == "Arm" then
			local swing = math.sin(self._phase + (if limb.Side > 0 then 0 else math.pi)) * 0.3 * stride + math.sin(self._time * 0.7 + limb.Side) * 0.04
			local shoulder = CFrame.new(limb.Side * 1.5, 9.6, -1.2)
			cf = shoulder * CFrame.Angles(swing, 0, 0) * shoulder:Inverse() * cf
		elseif limb.Kind == "Head" then
			-- A slow, searching tilt; sharper when listening.
			local tilt = math.sin(self._time * (if state == "Listening" then 1.6 else 0.5)) * (if state == "Listening" then 0.25 else 0.08)
			local neck = CFrame.new(0, 9.8, -1.4)
			cf = neck * CFrame.Angles(0, tilt, tilt * 0.5) * neck:Inverse() * cf
		end
		limb.Part.CFrame = base * cf
	end
	-- The lamps flicker like old batteries.
	for i, light in self._lamps do
		local n = math.noise(self._time * 4 + i * 3.1, i)
		light.Brightness = math.clamp(0.3 + n * 0.5, 0.02, 0.6)
	end

	self:_updateProximity(dt, state)
end

function MonsterPresenceController._updateProximity(self: MonsterPresenceController, _dt: number, state: any)
	local distance = self:_distance()
	-- Breathing you can hear when it is close.
	local breath = self._breath
	if distance < presence.BreathRange and self._root then
		if not breath then
			breath = AudioController:PlayAttached("MonsterBreath", self._root :: BasePart, { Group = "Monster", Looped = true, MinDistance = 6, MaxDistance = presence.BreathRange + 10, Jitter = false })
			self._breath = breath
		end
	elseif breath then
		breath:Destroy()
		self._breath = nil
	end
	-- Your heartbeat, when it is hunting nearby.
	local hunting = state == "Chasing" or state == "Tracking" or state == "Searching" or state == "Investigating"
	if hunting and distance < presence.HeartbeatRange then
		local now = os.clock()
		if now >= self._nextHeartbeat then
			local closeness = 1 - distance / presence.HeartbeatRange
			local bpm = MathUtil.lerp(72, 150, closeness)
			self._nextHeartbeat = now + 60 / bpm
			AudioController:Play2D("Heartbeat", { Group = "Effects", Volume = 0.25 + closeness * 0.6, Jitter = false })
			UIController:SetVignette(0.35 + closeness * 0.35, 0.3)
			self._vignetteRaised = true
		end
	elseif self._vignetteRaised then
		self._vignetteRaised = false
		UIController:SetVignette(0.35, 3)
	end
end

local instance: MonsterPresenceController = setmetatable({
	_root = nil,
	_model = nil,
	_limbs = {},
	_lamps = {},
	_lampCount = 0,
	_visual = nil,
	_phase = 0,
	_lastPos = nil,
	_breath = nil,
	_nextHeartbeat = 0,
	_rng = Random.new(),
	_time = 0,
	_connections = {},
	_echo = Instance.new("EchoSoundEffect"),
	_vignetteRaised = false,
} :: State, MonsterPresenceController)

return instance
