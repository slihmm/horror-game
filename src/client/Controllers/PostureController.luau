--!strict
-- Layers procedural poses over the default R15 animations (see
-- PostureConfig) so a crouched or climbing player reads as such to others.
--
-- Runs after animation each frame. A joint that no animation track drives
-- keeps its Transform between frames, so the previous frame's layer is
-- removed first; otherwise the pose would accumulate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PostureConfig = require(Shared.Config.PostureConfig)
local MathUtil = require(Shared.Utility.MathUtil)

type Joint = { Motor: Motor6D, Applied: CFrame?, Written: CFrame? }
type Rig = {
	Model: Model,
	Joints: { [string]: Joint },
	Blend: { [string]: number },
}

local PostureController = {}
PostureController.__index = PostureController

type State = {
	_rigs: { [Model]: Rig },
}
export type PostureController = typeof(setmetatable({} :: State, PostureController))

local JOINTS: { [string]: string } = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	RightHip = "RightUpperLeg",
	LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftKnee = "LeftLowerLeg",
	RightAnkle = "RightFoot",
	LeftAnkle = "LeftFoot",
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm",
	LeftElbow = "LeftLowerArm",
}

local function findRig(character: Model): Rig?
	local joints: { [string]: Joint } = {}
	for name, partName in JOINTS do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			joints[name] = { Motor = motor, Applied = nil, Written = nil }
		end
	end
	if not joints.Root or not joints.RightHip then
		return nil -- not an R15 rig
	end
	return { Model = character, Joints = joints, Blend = {} }
end

local function poseFor(character: Model, player: Player?): string
	local traversal = if player then player:GetAttribute(Constants.Attributes.Traversing) else nil
	if type(traversal) == "string" and PostureConfig.Poses[traversal] then
		return traversal
	end
	if character:GetAttribute(Constants.Attributes.Stance) == Constants.Stances.Crouch then
		return "Crouch"
	end
	return "Stand"
end

function PostureController.Start(self: PostureController)
	RunService.PreSimulation:Connect(function(dt: number)
		self:_update(dt)
	end)
end

function PostureController._apply(self: PostureController, joint: Joint, offset: CFrame)
	local motor = joint.Motor
	local current = motor.Transform
	-- If nothing overwrote our last write, strip our previous layer first.
	local base = current
	if joint.Written and joint.Applied and current == joint.Written then
		base = current * joint.Applied:Inverse()
	end
	local result = base * offset
	motor.Transform = result
	joint.Written = result
	joint.Applied = offset
end

function PostureController._update(self: PostureController, dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	local k = MathUtil.damp(PostureConfig.BlendSpeed, dt)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root or (root.Position - eye).Magnitude > PostureConfig.MaxDistance then
			continue
		end
		local rig = self._rigs[character]
		if not rig then
			local found = findRig(character)
			if not found then
				continue
			end
			rig = found
			self._rigs[character] = found
		end
		seen[character] = true
		local target = poseFor(character, player)
		-- Blend weights toward the target pose.
		for name in PostureConfig.Poses do
			local goal = if name == target then 1 else 0
			rig.Blend[name] = MathUtil.lerp(rig.Blend[name] or (if name == "Stand" then 1 else 0), goal, k)
		end
		local pose: { [string]: number } = { RootDrop = 0, Waist = 0, Hip = 0, Knee = 0, Ankle = 0, Shoulder = 0, Elbow = 0 }
		for name, weight in rig.Blend do
			local p = PostureConfig.Poses[name] :: any
			for key in pose do
				pose[key] += p[key] * weight
			end
		end
		local joints = rig.Joints
		local function set(name: string, offset: CFrame)
			local joint = joints[name]
			if joint then
				self:_apply(joint, offset)
			end
		end
		local rad = math.rad
		set("Root", CFrame.new(0, -pose.RootDrop, 0))
		set("Waist", CFrame.Angles(rad(pose.Waist), 0, 0))
		set("RightHip", CFrame.Angles(rad(pose.Hip), 0, 0))
		set("LeftHip", CFrame.Angles(rad(pose.Hip), 0, 0))
		set("RightKnee", CFrame.Angles(rad(pose.Knee), 0, 0))
		set("LeftKnee", CFrame.Angles(rad(pose.Knee), 0, 0))
		set("RightAnkle", CFrame.Angles(rad(pose.Ankle), 0, 0))
		set("LeftAnkle", CFrame.Angles(rad(pose.Ankle), 0, 0))
		set("RightShoulder", CFrame.Angles(rad(pose.Shoulder), 0, 0))
		set("LeftShoulder", CFrame.Angles(rad(pose.Shoulder), 0, 0))
		set("RightElbow", CFrame.Angles(rad(pose.Elbow), 0, 0))
		set("LeftElbow", CFrame.Angles(rad(pose.Elbow), 0, 0))
	end
	for character in self._rigs do
		if not seen[character] then
			self._rigs[character] = nil
		end
	end
end

local instance: PostureController = setmetatable({
	_rigs = {},
} :: State, PostureController)

return instance
