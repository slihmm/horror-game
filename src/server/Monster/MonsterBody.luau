--!strict
-- The Lamplighter's physical presence on the server: an invisible, anchored
-- root that moves kinematically along floor waypoints. Kinematic movement is
-- cheap, deterministic and never gets stuck on physics; clients render the
-- visible creature and interpolate it smoothly (MonsterPresenceController).
--
-- Every stride increments the MonsterStep attribute; clients turn that into
-- the footsteps players learn to dread.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonsterConfig = require(Shared.Config.MonsterConfig)

local Body = {}
Body.__index = Body

type BodyState = {
	Model: Model,
	Root: Part,
	Position: Vector3, -- floor point under the monster
	Facing: Vector3,
	Speed: number,
	Arrived: boolean,
	_path: { Vector3 }?,
	_index: number,
	_stride: number,
	_steps: number,
	_desiredFace: Vector3?,
}
export type Body = typeof(setmetatable({} :: BodyState, Body))

local HEIGHT = MonsterConfig.Visual.Height

function Body.new(parent: Instance, position: Vector3): Body
	local model = Instance.new("Model")
	model.Name = "Lamplighter"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Transparency = 1
	root.Size = Vector3.new(3, HEIGHT, 3)
	root.CFrame = CFrame.new(position + Vector3.yAxis * HEIGHT / 2)
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = parent
	CollectionService:AddTag(root, Constants.Tags.MonsterRoot)
	root:SetAttribute(Constants.Attributes.MonsterStep, 0)
	root:SetAttribute(Constants.Attributes.MonsterSpeed, 0)
	root:SetAttribute(Constants.Attributes.MonsterState, "Dormant")
	root:SetAttribute("Lamps", MonsterConfig.Visual.Lamps)
	local state: BodyState = {
		Model = model,
		Root = root,
		Position = position,
		Facing = Vector3.zAxis,
		Speed = 0,
		Arrived = true,
		_path = nil,
		_index = 1,
		_stride = 0,
		_steps = 0,
		_desiredFace = nil,
	}
	return setmetatable(state, Body)
end

-- New path (identity matters: the same table continues where it was).
function Body.SetPath(self: Body, path: { Vector3 }?)
	if path == self._path then
		return
	end
	self._path = path
	self._index = 1
	self.Arrived = path == nil or #path == 0
	-- Skip waypoints that are already behind us.
	if path and #path > 1 then
		local best, bestDist = 1, math.huge
		for i = 1, math.min(#path, 3) do
			local d = (path[i] - self.Position).Magnitude
			if d < bestDist then
				best, bestDist = i, d
			end
		end
		self._index = best
	end
end

function Body.Face(self: Body, direction: Vector3?)
	if direction then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		self._desiredFace = if flat.Magnitude > 0.01 then flat.Unit else nil
	else
		self._desiredFace = nil
	end
end

function Body.Teleport(self: Body, position: Vector3)
	self.Position = position
	self._path = nil
	self.Arrived = true
	self.Root.CFrame = CFrame.lookAt(position + Vector3.yAxis * HEIGHT / 2, position + Vector3.yAxis * HEIGHT / 2 + self.Facing)
end

function Body.Step(self: Body, dt: number, speed: number)
	local path = self._path
	local moved = 0
	local moveDir: Vector3? = nil
	if path and not self.Arrived and speed > 0 then
		local budget = speed * dt
		while budget > 0 and self._index <= #path do
			local target = path[self._index]
			local delta = target - self.Position
			local distance = delta.Magnitude
			if distance <= budget then
				self.Position = target
				budget -= distance
				moved += distance
				self._index += 1
			else
				local step = delta / distance * budget
				self.Position += step
				moved += budget
				budget = 0
			end
			if distance > 0.01 then
				moveDir = delta
			end
		end
		if self._index > #path then
			self.Arrived = true
		end
	end
	self.Speed = if dt > 0 then moved / dt else 0

	-- Turn toward travel direction (or an explicit facing).
	local desired = self._desiredFace
	if moveDir then
		local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
		if flat.Magnitude > 0.01 then
			desired = flat.Unit
		end
	end
	if desired then
		local current = self.Facing
		local angle = math.acos(math.clamp(current:Dot(desired), -1, 1))
		local maxTurn = MonsterConfig.Speeds.TurnRate * dt
		if angle <= maxTurn then
			self.Facing = desired
		else
			local cross = current:Cross(desired).Y
			local sign = if cross >= 0 then -1 else 1
			self.Facing = CFrame.Angles(0, sign * maxTurn, 0):VectorToWorldSpace(current)
		end
	end

	local center = self.Position + Vector3.yAxis * HEIGHT / 2
	self.Root.CFrame = CFrame.lookAt(center, center + self.Facing)

	-- Strides.
	self._stride += moved
	if self._stride >= MonsterConfig.Presence.StrideLength then
		self._stride = 0
		self._steps += 1
		self.Root:SetAttribute(Constants.Attributes.MonsterStep, self._steps)
	end
	local rounded = math.floor(self.Speed + 0.5)
	if self.Root:GetAttribute(Constants.Attributes.MonsterSpeed) ~= rounded then
		self.Root:SetAttribute(Constants.Attributes.MonsterSpeed, rounded)
	end
end

return Body
