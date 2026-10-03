--!strict
-- Moves the local character along a server-issued traversal path.
--
-- Rope: you lower yourself hand over hand; the shaft swallows the light
-- below you. Climb: slow, swaying, the wind growing above. Squeeze: the
-- camera drops and narrows, rock grinds on both sides, your breathing gets
-- loud, and sometimes you get wedged and have to work yourself free by
-- shifting left and right (or wait for someone to pull you out).
--
-- The character is held by constraints (not anchored) so its motion still
-- replicates to the server, which validates the exit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local TraversalConfig = require(Shared.Config.TraversalConfig)
local CameraConfig = require(Shared.Config.CameraConfig)
local MathUtil = require(Shared.Utility.MathUtil)

local AudioController = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local MovementController = require(script.Parent.MovementController)
local UIController = require(script.Parent.UIController)

local LocalPlayer = Players.LocalPlayer

type Active = {
	Token: number,
	Kind: string,
	Path: { Vector3 },
	Cumulative: { number },
	Length: number,
	Distance: number,
	Velocity: number,
	StuckAt: number?,
	Stuck: boolean,
	LastSide: number,
	Attachment: Attachment,
	AlignPosition: AlignPosition,
	AlignOrientation: AlignOrientation,
	SavedGroups: { [BasePart]: string },
	NextSound: number,
	Facing: Vector3,
	Finished: boolean,
	Started: number,
}

local TraversalController = {}
TraversalController.__index = TraversalController

type State = {
	Active: Active?,
	_controls: any,
	_rng: Random,
	_time: number,
}
export type TraversalController = typeof(setmetatable({} :: State, TraversalController))

local function getControls(): any
	local ok, controls = pcall(function()
		local playerModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		return playerModule:GetControls()
	end)
	return if ok then controls else nil
end

-- Point and tangent at a distance along the polyline.
local function sample(path: { Vector3 }, cumulative: { number }, distance: number): (Vector3, Vector3)
	for i = 2, #path do
		if distance <= cumulative[i] or i == #path then
			local segment = cumulative[i] - cumulative[i - 1]
			local t = if segment > 0 then math.clamp((distance - cumulative[i - 1]) / segment, 0, 1) else 0
			local a, b = path[i - 1], path[i]
			local tangent = b - a
			return a:Lerp(b, t), if tangent.Magnitude > 0 then tangent.Unit else Vector3.zAxis
		end
	end
	return path[#path], Vector3.zAxis
end

function TraversalController.Init(self: TraversalController)
	self._controls = getControls()
	-- Dying mid-traversal: release everything for the next life.
	LocalPlayer.CharacterAdded:Connect(function()
		if self.Active then
			self:_finish(false, false)
		end
	end)
end

function TraversalController.Start(self: TraversalController)
	Net.Event("Traversal").OnClientEvent:Connect(function(action: string, token: number, data: any)
		if action == "Begin" then
			self:_begin(token, data)
		elseif action == "Freed" then
			self:_freed(token)
		elseif action == "Abort" then
			local active = self.Active
			if active and active.Token == token then
				self:_finish(true, false)
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		self:_update(dt)
	end)
end

function TraversalController._moveInput(self: TraversalController): Vector3
	local controls = self._controls
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

function TraversalController._begin(self: TraversalController, token: number, data: any)
	if self.Active then
		return
	end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	local path = data.Path :: { Vector3 }
	local cumulative = { 0 }
	for i = 2, #path do
		cumulative[i] = cumulative[i - 1] + (path[i] - path[i - 1]).Magnitude
	end

	-- Hold the body with constraints; ignore collisions while traversing.
	local attachment = Instance.new("Attachment")
	attachment.Name = "TraversalAttachment"
	attachment.Parent = root
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.RigidityEnabled = true
	alignPosition.Position = root.Position
	alignPosition.Parent = root
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.RigidityEnabled = true
	alignOrientation.CFrame = root.CFrame.Rotation
	alignOrientation.Parent = root
	local saved: { [BasePart]: string } = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			saved[part] = part.CollisionGroup
			part.CollisionGroup = Constants.CollisionGroups.Traversing
		end
	end
	humanoid.PlatformStand = true
	MovementController:SetEnabled(false)

	local kind = data.Kind :: string
	-- Rope/climb: face the rope line (toward the wall); squeeze: face along.
	local facing: Vector3
	if kind == "Squeeze" then
		local d = path[#path] - path[1]
		facing = Vector3.new(d.X, 0, d.Z).Unit
	else
		local d = path[1] - path[2]
		facing = Vector3.new(d.X, 0, d.Z)
		facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.zAxis
		if kind == "Climb" then
			facing = -facing
		end
	end

	self.Active = {
		Token = token,
		Kind = kind,
		Path = path,
		Cumulative = cumulative,
		Length = cumulative[#cumulative],
		Distance = 0,
		Velocity = 0,
		StuckAt = data.StuckAt,
		Stuck = false,
		LastSide = 0,
		Attachment = attachment,
		AlignPosition = alignPosition,
		AlignOrientation = alignOrientation,
		SavedGroups = saved,
		NextSound = 0,
		Facing = facing,
		Finished = false,
		Started = os.clock(),
	}

	if kind == "Squeeze" then
		CameraController:SetFieldOfViewOverride(CameraConfig.Squeeze.FieldOfView)
		CameraController:SetHeightOverride(CameraConfig.Squeeze.HeightOffset)
		CameraController:SetExtraBreath(CameraConfig.Squeeze.BreathAmplitude)
		UIController:SetVignette(0.75, 1.5)
		AudioController:Play2D("RockGrind", { Group = "Effects", Volume = 0.8 })
	elseif kind == "Rope" then
		CameraController:SetFieldOfViewOverride(CameraConfig.Rope.FieldOfView)
		UIController:SetVignette(0.5, 2)
		AudioController:Play2D("RopeCreak", { Group = "Effects" })
	else
		CameraController:SetFieldOfViewOverride(CameraConfig.Rope.FieldOfView - 4)
		UIController:SetVignette(0.5, 2)
	end
end

function TraversalController._freed(self: TraversalController, token: number)
	local active = self.Active
	if not active or active.Token ~= token then
		return
	end
	active.Stuck = false
	active.StuckAt = nil
	CameraController:AddTrauma(0.35)
	CameraController:SetExtraBreath(CameraConfig.Squeeze.BreathAmplitude)
	AudioController:Play2D("RockGrind", { Group = "Effects", Volume = 1, Pitch = 1.2 })
	UIController:Whisper("you tear free", 2.5)
end

function TraversalController._update(self: TraversalController, dt: number)
	local active = self.Active
	if not active or active.Finished then
		return
	end
	self._time += dt
	local kind = TraversalConfig.Kinds[active.Kind]
	local input = self:_moveInput()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		self:_finish(false, false)
		return
	end

	if active.Stuck then
		-- Work free by shifting your weight left and right.
		local side = if input.X > 0.5 then 1 elseif input.X < -0.5 then -1 else 0
		if side ~= 0 and side ~= active.LastSide then
			active.LastSide = side
			Net.Event("Traversal"):FireServer("Struggle", active.Token)
			CameraController:AddTrauma(0.12)
			if self._rng:NextNumber() < 0.5 then
				AudioController:Play2D("Struggle", { Group = "Voice", Volume = 0.6 })
			end
			AudioController:Play2D("RockGrind", { Group = "Effects", Volume = 0.5, Pitch = self._rng:NextNumber(0.8, 1.2) })
		end
		local p = sample(active.Path, active.Cumulative, active.Distance)
		local wiggle = math.sin(self._time * 25) * 0.08 * math.abs(input.X)
		active.AlignPosition.Position = p + active.Facing:Cross(Vector3.yAxis) * wiggle
		return
	end

	-- Forward input (W / stick up) moves along the path; back reverses.
	local wanted = -input.Z * kind.Speed
	if self._controls == nil then
		wanted = 0
	end
	active.Velocity = MathUtil.approach(active.Velocity, wanted, kind.Acceleration * dt)
	active.Distance = math.clamp(active.Distance + active.Velocity * dt, 0, active.Length)

	-- Wedged?
	local stuckAt = active.StuckAt
	if stuckAt and active.Distance >= stuckAt * active.Length then
		active.Distance = stuckAt * active.Length
		active.Stuck = true
		active.Velocity = 0
		CameraController:AddTrauma(0.5)
		CameraController:SetExtraBreath(CameraConfig.Squeeze.BreathAmplitude * 2.5)
		UIController:SetVignette(0.88, 0.6)
		AudioController:Play2D("Struggle", { Group = "Voice" })
		UIController:Whisper("you're wedged. shift left and right to work free", 5)
		Net.Event("Traversal"):FireServer("Stuck", active.Token)
	end

	-- Stepping off into the shaft: the view sinks into the drop for a few
	-- seconds, then eases back so the player keeps control of the camera.
	if active.Kind == "Rope" and active.Path[1].Y > active.Path[#active.Path].Y then
		local elapsed = os.clock() - active.Started
		CameraController:SetLookBias(CameraConfig.Rope.LookDownBias * math.clamp(1 - elapsed / 6, 0, 1) * math.clamp(elapsed / 1.5, 0, 1))
	end

	local position, tangent = sample(active.Path, active.Cumulative, active.Distance)
	local sway = Vector3.zero
	if active.Kind ~= "Squeeze" then
		sway = Vector3.new(math.sin(self._time * 1.3), 0, math.cos(self._time * 0.9)) * kind.SwayAmplitude
	end
	active.AlignPosition.Position = position + sway
	local facing = active.Facing
	if active.Kind == "Squeeze" then
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		if flat.Magnitude > 0.1 then
			facing = flat.Unit
		end
	end
	active.AlignOrientation.CFrame = CFrame.lookAt(Vector3.zero, facing)

	-- Sounds while moving.
	local now = os.clock()
	if math.abs(active.Velocity) > 0.3 and now >= active.NextSound then
		if active.Kind == "Squeeze" then
			active.NextSound = now + self._rng:NextNumber(0.6, 1.2)
			AudioController:Play2D("RockGrind", { Group = "Effects", Volume = 0.45 })
			CameraController:AddTrauma(0.05)
		elseif active.Kind == "Rope" then
			active.NextSound = now + self._rng:NextNumber(0.9, 1.6)
			AudioController:Play2D(if self._rng:NextNumber() < 0.5 then "RopeCreak" else "RopeSlide", { Group = "Effects", Volume = 0.6 })
		else
			active.NextSound = now + self._rng:NextNumber(1, 1.8)
			AudioController:Play2D("PebbleSkitter", { Group = "Effects", Volume = 0.5 })
		end
	end

	if active.Distance >= active.Length - 0.05 then
		self:_finish(false, true)
	elseif active.Distance <= 0 and active.Velocity < 0 then
		-- Backed out the way we came.
		self:_finish(true, true)
	end
end

function TraversalController._finish(self: TraversalController, backedOut: boolean, notifyServer: boolean)
	local active = self.Active
	if not active or active.Finished then
		return
	end
	active.Finished = true
	if notifyServer then
		Net.Event("Traversal"):FireServer("Finish", active.Token, backedOut)
	end
	active.AlignPosition:Destroy()
	active.AlignOrientation:Destroy()
	active.Attachment:Destroy()
	for part, group in active.SavedGroups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	MovementController:SetEnabled(true)
	CameraController:SetFieldOfViewOverride(nil)
	CameraController:SetHeightOverride(0)
	CameraController:SetExtraBreath(0)
	CameraController:SetLookBias(0)
	UIController:SetVignette(0.35, 1.5)
	self.Active = nil
end

function TraversalController.IsActive(self: TraversalController): boolean
	return self.Active ~= nil
end

local instance: TraversalController = setmetatable({
	Active = nil,
	_controls = nil,
	_rng = Random.new(),
	_time = 0,
} :: State, TraversalController)

return instance
