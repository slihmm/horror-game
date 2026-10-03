--!nocheck
-- Offline world emulator for the Lune harness.
--
-- Terrain: every Fill*/ReplaceMaterial call is recorded in order. The
-- material at a point is decided by the last recorded operation containing
-- it, which mirrors how successive terrain writes overwrite each other.
-- Workspace:Raycast marches through that field. Exact geometry rather than
-- 4-stud voxels, but close enough to exercise placement code end to end.
--
-- Also shims the handful of engine APIs the dressing code touches that Lune
-- doesn't implement (pivots, tags, attachments' world positions, prompts).

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local WorldSim = {}

local CELL = 16
local ops = {}
local cells = {}

local function cellKey(x, y, z)
	return x * 1e8 + y * 1e4 + z
end

local function addOp(op)
	table.insert(ops, op)
	op.Index = #ops
	local minC = op.Min / CELL
	local maxC = op.Max / CELL
	for x = math.floor(minC.X), math.floor(maxC.X) do
		for y = math.floor(minC.Y), math.floor(maxC.Y) do
			for z = math.floor(minC.Z), math.floor(maxC.Z) do
				local key = cellKey(x, y, z)
				local bucket = cells[key]
				if not bucket then
					bucket = {}
					cells[key] = bucket
				end
				table.insert(bucket, op)
			end
		end
	end
end

local function boundsOf(cf, size)
	local half = size / 2
	local corners = {}
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
				maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
			end
		end
	end
	return minV, maxV
end

local function contains(op, p)
	if op.Shape == "Ball" then
		return (p - op.Center).Magnitude <= op.Radius
	end
	local l = op.Inverse * p
	if op.Shape == "Block" then
		return math.abs(l.X) <= op.Half.X and math.abs(l.Y) <= op.Half.Y and math.abs(l.Z) <= op.Half.Z
	elseif op.Shape == "Cylinder" then
		return math.abs(l.Y) <= op.Height / 2 and (l.X * l.X + l.Z * l.Z) <= op.Radius * op.Radius
	end
	return false
end

-- Material at a point considering ops with Index < before.
local function materialAt(p, before)
	local bucket = cells[cellKey(math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL))]
	if not bucket then
		return Enum.Material.Air
	end
	for i = #bucket, 1, -1 do
		local op = bucket[i]
		if op.Index < before and contains(op, p) then
			if op.Replace then
				local under = materialAt(p, op.Index)
				return if under == op.From then op.Material else under
			end
			return op.Material
		end
	end
	return Enum.Material.Air
end

function WorldSim.MaterialAt(p)
	return materialAt(p, math.huge)
end

-- The last recorded op containing p (for diagnostics), or nil.
function WorldSim.OpAt(p)
	local bucket = cells[cellKey(math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL))]
	if not bucket then
		return nil
	end
	for i = #bucket, 1, -1 do
		if contains(bucket[i], p) then
			return bucket[i]
		end
	end
	return nil
end

local function solid(p, ignoreWater)
	local m = materialAt(p, math.huge)
	if m == Enum.Material.Air then
		return false, m
	end
	if m == Enum.Material.Water and ignoreWater then
		return false, m
	end
	return true, m
end

function WorldSim.Raycast(origin, direction, ignoreWater)
	local length = direction.Magnitude
	if length < 1e-6 then
		return nil
	end
	local dir = direction / length
	local step = 1
	local t = 0
	local wasSolid = solid(origin, ignoreWater)
	if wasSolid then
		-- Starting inside rock: Roblox would hit immediately.
		return { Position = origin, Normal = -dir, Material = materialAt(origin, math.huge), Distance = 0 }
	end
	while t < length do
		local nextT = math.min(t + step, length)
		local p = origin + dir * nextT
		local isSolid, material = solid(p, ignoreWater)
		if isSolid then
			local lo, hi = t, nextT
			for _ = 1, 6 do
				local mid = (lo + hi) / 2
				if solid(origin + dir * mid, ignoreWater) then
					hi = mid
				else
					lo = mid
				end
			end
			local hit = origin + dir * hi
			local e = 0.7
			local function s(v)
				return if solid(hit + v, ignoreWater) then 1 else 0
			end
			local n = Vector3.new(s(Vector3.new(-e, 0, 0)) - s(Vector3.new(e, 0, 0)), s(Vector3.new(0, -e, 0)) - s(Vector3.new(0, e, 0)), s(Vector3.new(0, 0, -e)) - s(Vector3.new(0, 0, e)))
			if n.Magnitude < 0.01 then
				n = -dir
			end
			return { Position = hit, Normal = n.Unit, Material = material, Distance = hi }
		end
		t = nextT
	end
	return nil
end

-- Clears recorded terrain (for running several seeds in one process).
function WorldSim.Reset()
	table.clear(ops)
	table.clear(cells)
end

function WorldSim.OpCount()
	return #ops
end

-- Installs shims and returns a service lookup for the harness.
function WorldSim.install(game)
	local workspace = game:FindFirstChildOfClass("Workspace")
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		terrain = roblox.Instance.new("Terrain")
		terrain.Parent = workspace
	end

	roblox.implementMethod("Terrain", "FillBall", function(_, center, radius, material)
		addOp({ Shape = "Ball", Center = center, Radius = radius, Material = material, Min = center - Vector3.one * radius, Max = center + Vector3.one * radius })
	end)
	roblox.implementMethod("Terrain", "FillBlock", function(_, cf, size, material)
		local minV, maxV = boundsOf(cf, size)
		addOp({ Shape = "Block", Inverse = cf:Inverse(), Half = size / 2, Material = material, Min = minV, Max = maxV })
	end)
	roblox.implementMethod("Terrain", "FillCylinder", function(_, cf, height, radius, material)
		local minV, maxV = boundsOf(cf, Vector3.new(radius * 2, height, radius * 2))
		addOp({ Shape = "Cylinder", Inverse = cf:Inverse(), Height = height, Radius = radius, Material = material, Min = minV, Max = maxV })
	end)
	roblox.implementMethod("Terrain", "ReplaceMaterialInTransform", function(_, cf, size, from, to)
		local minV, maxV = boundsOf(cf, size)
		addOp({ Shape = "Block", Inverse = cf:Inverse(), Half = size / 2, Material = to, From = from, Replace = true, Min = minV, Max = maxV })
	end)
	roblox.implementMethod("Terrain", "SetMaterialColor", function() end)

	roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
		local result = WorldSim.Raycast(origin, direction, params and params.IgnoreWater)
		if result then
			result.Instance = terrain
		end
		return result
	end)

	-- Pivots. Roblox defaults an unset pivot to the bounding box; the first
	-- part's position is a close enough stand-in here.
	local function pivotOf(model)
		local ok, pivot = pcall(function()
			return model.WorldPivot
		end)
		if ok and pivot then
			return pivot
		end
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		return if part then CFrame.new(part.CFrame.Position) else CFrame.identity
	end
	roblox.implementMethod("Model", "GetPivot", function(self)
		return pivotOf(self)
	end)
	roblox.implementMethod("Model", "PivotTo", function(self, target)
		local delta = target * pivotOf(self):Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			elseif d:IsA("Model") then
				d.WorldPivot = delta * pivotOf(d)
			end
		end
		self.WorldPivot = target
	end)
	roblox.implementProperty("BasePart", "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = self.CFrame.Rotation + value
	end)
	roblox.implementMethod("BasePart", "GetPivot", function(self)
		return self.CFrame
	end)
	roblox.implementMethod("BasePart", "PivotTo", function(self, target)
		self.CFrame = target
	end)

	-- Attachments: world position relative to the parent part (or world).
	roblox.implementProperty("Attachment", "WorldPosition", function(self)
		local parent = self.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame * self.Position
		end
		return self.Position
	end, function(self, value)
		local parent = self.Parent
		if parent and parent:IsA("BasePart") then
			self.Position = parent.CFrame:PointToObjectSpace(value)
		else
			self.Position = value
		end
	end)

	local tags = {}
	local collection = {
		AddTag = function(_, instance, tag)
			tags[tag] = tags[tag] or {}
			table.insert(tags[tag], instance)
		end,
		GetTagged = function(_, tag)
			return tags[tag] or {}
		end,
	}
	local fakeSignal = { Connect = function() return { Disconnect = function() end } end }
	roblox.implementProperty("ProximityPrompt", "Triggered", function()
		return fakeSignal
	end)

	local raycastParams = {}
	raycastParams.__index = raycastParams
	local RaycastParams = {
		new = function()
			return setmetatable({ FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false }, raycastParams)
		end,
	}

	return {
		Services = { CollectionService = collection },
		Globals = { RaycastParams = RaycastParams },
		Tags = tags,
	}
end

return WorldSim
