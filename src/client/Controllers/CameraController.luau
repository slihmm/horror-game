--!strict
-- Strict first-person camera with subtle, physical motion: walking bob,
-- breathing, strafe roll, landing dip and trauma-based shake. Effects are
-- layered on top of Roblox's camera after it updates each frame, so they
-- never accumulate or fight the default controls.
--
-- Everything scales with the player's "Camera motion" setting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)
local MathUtil = require(Shared.Utility.MathUtil)

local MovementController = require(script.Parent.MovementController)

local LocalPlayer = Players.LocalPlayer

local CameraController = {}
CameraController.__index = CameraController

type State = {
	Motion: number,
	Suspended: boolean,
	_trauma: number,
	_time: number,
	_bobPhase: number,
	_bobAmount: number,
	_landDip: number,
	_landVelocity: number,
	_roll: number,
	_fov: number,
	_fovOverride: number?,
	_heightOverride: number,
	_heightCurrent: number,
	_extraBreath: number,
	_lookBias: number,
	_applied: CFrame?,
}
export type CameraController = typeof(setmetatable({} :: State, CameraController))

function CameraController.Init(self: CameraController)
	LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	LocalPlayer.CameraMaxZoomDistance = 0.5
	LocalPlayer.CameraMinZoomDistance = 0.5
	MovementController.Landed:Connect(function(peak: number)
		if peak > 12 then
			local cfg = CameraConfig.Landing
			self._landVelocity = -math.min(cfg.MaxDip, peak * cfg.DipPerVelocity) * 8
			self:AddTrauma(math.clamp((peak - 40) / 80, 0, 0.7))
		end
	end)
end

function CameraController.Start(self: CameraController)
	-- Roblox's camera derives next frame's look direction from camera.CFrame,
	-- so the offset applied last frame is removed before it runs, then
	-- reapplied after it. Otherwise rotation offsets would accumulate.
	RunService:BindToRenderStep("DescentCameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
		local camera = Workspace.CurrentCamera
		local applied = self._applied
		if camera and applied then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CFrame = camera.CFrame * applied:Inverse()
			end
			self._applied = nil
		end
	end)
	RunService:BindToRenderStep("DescentCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		self:_update(dt)
	end)
end

-- Shake: trauma decays over time; shake magnitude is trauma squared, which
-- keeps small events subtle and big ones violent.
function CameraController.AddTrauma(self: CameraController, amount: number)
	self._trauma = math.clamp(self._trauma + amount, 0, 1)
end

function CameraController.SetFieldOfViewOverride(self: CameraController, fov: number?)
	self._fovOverride = fov
end

-- Lowers (negative) or raises the eye height, e.g. while squeezing.
function CameraController.SetHeightOverride(self: CameraController, offset: number)
	self._heightOverride = offset
end

-- Extra breathing amplitude (fear, squeezes, being stuck).
function CameraController.SetExtraBreath(self: CameraController, amount: number)
	self._extraBreath = amount
end

-- Pitches the view down by degrees (looking into the shaft).
function CameraController.SetLookBias(self: CameraController, degrees: number)
	self._lookBias = degrees
end

function CameraController._update(self: CameraController, dt: number)
	local camera = Workspace.CurrentCamera
	if not camera or self.Suspended or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	-- Enforce first person even if something tries to change it.
	if LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	self._time += dt
	local motion = self.Motion
	local t = self._time

	-- Walking bob, driven by speed so it naturally fades out when stopping.
	local bob = CameraConfig.Bob
	local speed = MovementController.Speed
	local moving = MovementController.Moving
	local targetAmount = if moving then math.clamp(speed / 9, 0, 1.6) else 0
	if MovementController.Sprinting then
		targetAmount *= bob.SprintMultiplier / 1.6
	elseif MovementController.Stance == "Crouch" then
		targetAmount *= bob.CrouchMultiplier
	end
	self._bobAmount = MathUtil.lerp(self._bobAmount, targetAmount, MathUtil.damp(8, dt))
	self._bobPhase += dt * speed / 4.2 * math.pi
	local bobX = math.sin(self._bobPhase) * bob.WalkHorizontal * self._bobAmount
	local bobY = -math.abs(math.cos(self._bobPhase)) * bob.WalkVertical * self._bobAmount
	-- An injured gait is uneven.
	if MovementController.Injured then
		bobY *= 1 + 0.6 * math.max(0, math.sin(self._bobPhase * 0.5))
	end
	local bobRoll = math.sin(self._bobPhase) * math.rad(bob.RollDegrees) * self._bobAmount

	-- Breathing.
	local breathing = CameraConfig.Breathing
	local exhausted = MovementController.Exhausted or MovementController.Stamina < 0.25
	local rate = if exhausted then breathing.ExhaustedRate else breathing.IdleRate
	local amplitude = (if exhausted then breathing.ExhaustedAmplitude else breathing.IdleAmplitude) + self._extraBreath
	local breathY = math.sin(t * rate * math.pi * 2) * amplitude
	local breathPitch = math.sin(t * rate * math.pi * 2 - 0.6) * amplitude * 0.6

	-- Strafe roll.
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoll = 0
	if root then
		local lateral = root.AssemblyLinearVelocity:Dot(camera.CFrame.RightVector)
		targetRoll = -math.clamp(lateral / 16, -1, 1) * math.rad(CameraConfig.Sway.StrafeRollDegrees)
	end
	self._roll = MathUtil.lerp(self._roll, targetRoll, MathUtil.damp(6, dt))

	-- Landing dip: a damped spring back to zero.
	local landing = CameraConfig.Landing
	self._landVelocity += (-self._landDip * landing.Recovery * landing.Recovery - self._landVelocity * 2 * landing.Recovery) * dt
	self._landDip += self._landVelocity * dt

	-- Shake.
	local shake = CameraConfig.Shake
	self._trauma = math.max(0, self._trauma - shake.Decay * dt)
	local s = self._trauma * self._trauma
	local f = shake.Frequency
	local shakePitch = math.rad(shake.MaxDegrees) * s * math.noise(t * f, 1.3)
	local shakeYaw = math.rad(shake.MaxDegrees) * s * math.noise(t * f, 7.1)
	local shakeRoll = math.rad(shake.MaxDegrees) * s * math.noise(t * f, 13.7)
	local shakeOffset = Vector3.new(math.noise(t * f, 21.3), math.noise(t * f, 34.9), 0) * shake.MaxOffset * s

	-- Height override (squeezes).
	self._heightCurrent = MathUtil.lerp(self._heightCurrent, self._heightOverride, MathUtil.damp(5, dt))

	local offset = CFrame.new(Vector3.new(bobX, bobY + breathY + self._landDip + self._heightCurrent, 0) * motion + shakeOffset)
		* CFrame.Angles(breathPitch * motion + shakePitch - math.rad(self._lookBias), shakeYaw, (bobRoll + self._roll) * motion + shakeRoll)
	camera.CFrame = camera.CFrame * offset
	self._applied = offset

	-- Field of view.
	local targetFov = self._fovOverride
		or (if MovementController.Sprinting then CameraConfig.SprintFieldOfView else CameraConfig.FieldOfView)
	self._fov = MathUtil.lerp(self._fov, targetFov, MathUtil.damp(4, dt))
	camera.FieldOfView = self._fov
end


local instance: CameraController = setmetatable({
	Motion = 1,
	Suspended = false,
	_trauma = 0,
	_time = 0,
	_bobPhase = 0,
	_bobAmount = 0,
	_landDip = 0,
	_landVelocity = 0,
	_roll = 0,
	_fov = CameraConfig.FieldOfView,
	_fovOverride = nil,
	_heightOverride = 0,
	_heightCurrent = 0,
	_extraBreath = 0,
	_lookBias = 0,
	_applied = nil,
} :: State, CameraController)

return instance
