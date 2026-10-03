--!strict
-- Walking, sprinting, crouching and stamina. Movement is client-owned (as
-- Roblox characters are); the server validates speeds and uses the reported
-- stance for noise.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local MathUtil = require(Shared.Utility.MathUtil)
local Signal = require(Shared.Utility.Signal)

local LocalPlayer = Players.LocalPlayer

local MovementController = {}
MovementController.__index = MovementController

type State = {
	Stance: string,
	Sprinting: boolean,
	Moving: boolean,
	Speed: number,
	Stamina: number,
	Exhausted: boolean,
	Enabled: boolean,
	Injured: boolean,
	FloorMaterial: Enum.Material,
	StanceChanged: Signal.Signal<string>,
	Landed: Signal.Signal<number>,
	_sprintHeld: boolean,
	_lastSprint: number,
	_humanoid: Humanoid?,
	_root: BasePart?,
	_cameraOffset: number,
	_slipCheck: number,
	_slipDir: Vector3?,
	_fallPeak: number,
}
export type MovementController = typeof(setmetatable({} :: State, MovementController))

function MovementController.Init(self: MovementController)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if not humanoid or not root then
			return
		end
		self._humanoid = humanoid
		self._root = root
		self.Stance = Constants.Stances.Stand
		self.Stamina = PlayerConfig.Stamina.Max
		self.Exhausted = false
		self._cameraOffset = 0
		humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Freefall then
				self._fallPeak = 0
			elseif new == Enum.HumanoidStateType.Landed then
				self.Landed:Fire(self._fallPeak)
				self._fallPeak = 0
			end
		end)
	end
	LocalPlayer.CharacterAdded:Connect(onCharacter)
	if LocalPlayer.Character then
		task.spawn(onCharacter, LocalPlayer.Character)
	end
end

function MovementController.Start(self: MovementController)
	ContextActionService:BindAction("DescentSprint", function(_name: string, state: Enum.UserInputState)
		self._sprintHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("DescentSprint", "Run")
	ContextActionService:SetPosition("DescentSprint", UDim2.new(1, -170, 1, -150))

	ContextActionService:BindAction("DescentCrouch", function(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			self:SetStance(if self.Stance == Constants.Stances.Crouch then Constants.Stances.Stand else Constants.Stances.Crouch)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("DescentCrouch", "Crouch")
	ContextActionService:SetPosition("DescentCrouch", UDim2.new(1, -240, 1, -90))

	RunService.Heartbeat:Connect(function(dt: number)
		self:_update(dt)
	end)
end

function MovementController.SetStance(self: MovementController, stance: string)
	if stance == self.Stance then
		return
	end
	if stance == Constants.Stances.Stand and self:_ceilingBlocked() then
		return -- no room to stand up
	end
	self.Stance = stance
	Net.Event("SetStance"):FireServer(stance)
	self.StanceChanged:Fire(stance)
end

function MovementController.SetEnabled(self: MovementController, enabled: boolean)
	self.Enabled = enabled
	if not enabled then
		self.Sprinting = false
	end
end

function MovementController._ceilingBlocked(self: MovementController): boolean
	local root = self._root
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	return Workspace:Raycast(root.Position, Vector3.yAxis * 4, params) ~= nil
end

function MovementController._update(self: MovementController, dt: number)
	local humanoid = self._humanoid
	local root = self._root
	if not humanoid or not root or not root.Parent or humanoid.Health <= 0 then
		return
	end
	local cfg = PlayerConfig.Movement
	local stamina = PlayerConfig.Stamina
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	self.Speed = horizontal
	self.Moving = humanoid.MoveDirection.Magnitude > 0.1 and horizontal > 0.5
	self.FloorMaterial = humanoid.FloorMaterial
	self.Injured = (root.Parent :: Model):GetAttribute(Constants.Attributes.Injured) == true

	if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		self._fallPeak = math.max(self._fallPeak, -velocity.Y)
	end

	-- Sprint & stamina.
	local wantsSprint = self._sprintHeld and self.Enabled and self.Stance == Constants.Stances.Stand and self.Moving
	if self.Exhausted and self.Stamina >= stamina.ExhaustedRecoverThreshold then
		self.Exhausted = false
	end
	self.Sprinting = wantsSprint and not self.Exhausted and self.Stamina > 0
	if self.Sprinting then
		self.Stamina = math.max(0, self.Stamina - stamina.DrainPerSecond * dt)
		self._lastSprint = os.clock()
		if self.Stamina <= 0 then
			self.Exhausted = true
		end
	elseif os.clock() - self._lastSprint > stamina.RegenDelay then
		local regen = stamina.RegenPerSecond * (if self.Moving then 0.6 else 1)
		self.Stamina = math.min(stamina.Max, self.Stamina + regen * dt)
	end

	-- Speed.
	local speed: number
	if self.Stance == Constants.Stances.Crouch then
		speed = cfg.CrouchSpeed
	elseif self.Sprinting then
		speed = cfg.SprintSpeed
	else
		speed = cfg.WalkSpeed
	end
	speed *= cfg.SurfaceSpeedMultipliers[self.FloorMaterial] or 1
	if self.Injured then
		speed *= cfg.InjuredMultiplier
	end
	if not self.Enabled then
		speed = 0
	end
	humanoid.WalkSpeed = speed
	humanoid.JumpHeight = if self.Stance == Constants.Stances.Crouch or not self.Enabled then 0 else cfg.JumpHeight

	-- Crouch camera height.
	local targetOffset = if self.Stance == Constants.Stances.Crouch then cfg.CrouchCameraOffset else 0
	self._cameraOffset = MathUtil.lerp(self._cameraOffset, targetOffset, MathUtil.damp(9, dt))
	humanoid.CameraOffset = Vector3.new(0, self._cameraOffset, 0)

	-- Slick slopes: wet slate and mud slide you downhill.
	self._slipCheck -= dt
	if self._slipCheck <= 0 then
		self._slipCheck = 0.15
		self._slipDir = nil
		local material = self.FloorMaterial
		if material == Enum.Material.Slate or material == Enum.Material.Mud then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { Workspace.Terrain }
			local hit = Workspace:Raycast(root.Position, Vector3.yAxis * -6, params)
			if hit then
				local angle = math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
				if angle > cfg.SlipAngle then
					local downhill = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
					if downhill.Magnitude > 0.01 then
						self._slipDir = downhill.Unit
					end
				end
			end
		end
	end
	local slip = self._slipDir
	if slip and self.Enabled then
		root.AssemblyLinearVelocity += slip * cfg.SlipAcceleration * dt
	end
end


local instance: MovementController = setmetatable({
	Stance = Constants.Stances.Stand,
	Sprinting = false,
	Moving = false,
	Speed = 0,
	Stamina = PlayerConfig.Stamina.Max,
	Exhausted = false,
	Enabled = true,
	Injured = false,
	FloorMaterial = Enum.Material.Air,
	StanceChanged = Signal.new(),
	Landed = Signal.new(),
	_sprintHeld = false,
	_lastSprint = 0,
	_humanoid = nil,
	_root = nil,
	_cameraOffset = 0,
	_slipCheck = 0,
	_slipDir = nil,
	_fallPeak = 0,
} :: State, MovementController)

return instance
