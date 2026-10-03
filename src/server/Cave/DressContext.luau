--!strict
-- Shared state and helpers for dressing the carved cave: raycasts against
-- terrain, prop placement, and the slot lists other services consume
-- (lore placements, loot spots, hiding spots, hazards, landmarks).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PropFactory = require(script.Parent.PropFactory)
local Primitives = require(script.Parent.CavePrimitives)

export type LoreSlot = {
	CFrame: CFrame, -- on the floor, facing into the room
	Wall: CFrame?, -- on a nearby wall, facing out (for carvings)
	Zone: string,
	Anchor: string?,
	Hidden: boolean,
	Used: boolean,
	-- Lore entries with a matching SlotTag are placed here first.
	Tag: string?,
	OnProp: boolean,
}

export type LootSpot = {
	Position: Vector3,
	Zone: string,
	Hidden: boolean,
}

export type HidingSpot = {
	CFrame: CFrame,
	Size: Vector3,
	Zone: string,
}

export type RockfallSpot = {
	Ceiling: Vector3,
	Floor: Vector3,
	Zone: string,
}

export type Results = {
	LoreSlots: { LoreSlot },
	LootSpots: { LootSpot },
	HidingSpots: { HidingSpot },
	RockfallSpots: { RockfallSpot },
	Landmarks: { [string]: { Model: Model, Position: Vector3, Facing: Vector3 } },
	Bridges: { { Model: Model, A: Vector3, B: Vector3 } },
	RingSeal: { CFrame: CFrame, Size: Vector3, Rubble: Model? }?,
	TraversalProps: { [string]: Model },
	EvidenceCount: number,
}

export type DressContext = {
	Plan: Primitives.Context,
	Rng: Random,
	Root: Folder,
	Props: Folder,
	Volumes: Folder,
	Markers: Model,
	Results: Results,
	Params: RaycastParams,
}

local Dress = {}

function Dress.new(plan: Primitives.Context): DressContext
	local root = Workspace:FindFirstChild(Constants.Folders.Cave) :: Folder?
	if not root then
		local folder = Instance.new("Folder")
		folder.Name = Constants.Folders.Cave
		folder.Parent = Workspace
		root = folder
	end
	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	-- Markers clients must always have (recursion corridor data, etc.)
	-- live in a persistent model so streaming never drops them.
	local markers = Instance.new("Model")
	markers.Name = "Markers"
	markers.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	markers.Parent = root

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true

	return {
		Plan = plan,
		Rng = Random.new(plan.Seed + 7),
		Root = root :: Folder,
		Props = sub(Constants.Folders.Props),
		Volumes = sub(Constants.Folders.Volumes),
		Markers = markers,
		Results = {
			LoreSlots = {},
			LootSpots = {},
			HidingSpots = {},
			RockfallSpots = {},
			Landmarks = {},
			Bridges = {},
			RingSeal = nil,
			TraversalProps = {},
			EvidenceCount = 0,
		},
		Params = params,
	}
end

-- Raycast helpers ------------------------------------------------------------

-- True when a point is inside terrain (a tiny ray hits immediately).
function Dress.InRock(ctx: DressContext, point: Vector3): boolean
	local hit = Workspace:Raycast(point, Vector3.yAxis * 0.05, ctx.Params)
	return hit ~= nil and hit.Distance < 0.01
end

-- Floor below a point. The ray must start in open space: a ray that starts
-- inside rock (next to a wall, in a narrow sloping passage) finds nothing
-- meaningful, so lower starts are tried before giving up.
function Dress.FloorAt(ctx: DressContext, position: Vector3, searchUp: number?, searchDown: number?): (Vector3?, Vector3?, Enum.Material?)
	local up = searchUp or 4
	local down = searchDown or 30
	for _, height in { up, up * 0.5, 0.5 } do
		local origin = position + Vector3.yAxis * height
		if not Dress.InRock(ctx, origin) then
			local result = Workspace:Raycast(origin, Vector3.yAxis * -(height + down), ctx.Params)
			if result then
				return result.Position, result.Normal, result.Material
			end
			return nil, nil, nil
		end
	end
	return nil, nil, nil
end

function Dress.CeilingAt(ctx: DressContext, position: Vector3, maxDistance: number?): Vector3?
	local result = Workspace:Raycast(position, Vector3.yAxis * (maxDistance or 60), ctx.Params)
	return if result then result.Position else nil
end

-- Casts horizontally to find a wall. Returns hit position and normal.
function Dress.WallFrom(ctx: DressContext, position: Vector3, direction: Vector3, maxDistance: number?): (Vector3?, Vector3?)
	local dir = Vector3.new(direction.X, 0, direction.Z)
	if dir.Magnitude < 0.01 then
		return nil, nil
	end
	local result = Workspace:Raycast(position, dir.Unit * (maxDistance or 40), ctx.Params)
	if result then
		return result.Position, result.Normal
	end
	return nil, nil
end

-- Finds the nearest wall around a point by sampling directions.
function Dress.NearestWall(ctx: DressContext, position: Vector3, maxDistance: number?): (Vector3?, Vector3?)
	local best: Vector3? = nil
	local bestNormal: Vector3? = nil
	local bestDist = math.huge
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local hit, normal = Dress.WallFrom(ctx, position, Vector3.new(math.cos(angle), 0, math.sin(angle)), maxDistance)
		if hit and normal and math.abs(normal.Y) < 0.6 then
			local d = (hit - position).Magnitude
			if d < bestDist then
				best = hit
				bestNormal = normal
				bestDist = d
			end
		end
	end
	return best, bestNormal
end

-- A random floor point within `radius` of `center` that has headroom.
function Dress.RandomFloor(ctx: DressContext, center: Vector3, radius: number, minFromCenter: number?): Vector3?
	local rng = ctx.Rng
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(minFromCenter or 0, radius)
		local probe = center + Vector3.new(math.cos(angle) * dist, 3, math.sin(angle) * dist)
		local floor, normal = Dress.FloorAt(ctx, probe, 4, 14)
		if floor and normal and normal.Y > 0.7 then
			local ceiling = Dress.CeilingAt(ctx, floor + Vector3.yAxis * 0.5, 12)
			if not ceiling or (ceiling - floor).Magnitude > 4 then
				return floor
			end
		end
	end
	return nil
end

function Dress.Yaw(ctx: DressContext): CFrame
	return CFrame.Angles(0, ctx.Rng:NextNumber(0, math.pi * 2), 0)
end

-- CFrame on a floor point whose -Z (look) faces `towards`.
function Dress.Facing(at: Vector3, towards: Vector3): CFrame
	local flat = Vector3.new(towards.X, at.Y, towards.Z)
	if (flat - at).Magnitude < 0.01 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, flat)
end

-- CFrame on a wall hit: -Z points away from the wall (toward the viewer).
function Dress.OnWall(hit: Vector3, normal: Vector3): CFrame
	local flatNormal = Vector3.new(normal.X, 0, normal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = Vector3.zAxis
	end
	return CFrame.lookAt(hit + flatNormal.Unit * 0.12, hit + flatNormal.Unit * 2)
end

-- Placement ------------------------------------------------------------------

function Dress.Place(ctx: DressContext, name: string, cframe: CFrame, params: { [string]: any }?, parent: Instance?): Model
	return PropFactory.Build(name, cframe, ctx.Rng, params, parent or ctx.Props)
end

-- Places a prop on the floor near a point (raycast). Returns nil if no floor.
function Dress.PlaceOnFloor(ctx: DressContext, name: string, position: Vector3, params: { [string]: any }?, parent: Instance?): Model?
	local floor = Dress.FloorAt(ctx, position + Vector3.yAxis * 2, 6, 20)
	if not floor then
		return nil
	end
	return Dress.Place(ctx, name, CFrame.new(floor) * Dress.Yaw(ctx), params, parent)
end

function Dress.Folder(ctx: DressContext, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = ctx.Props
	return f
end

-- Slots --------------------------------------------------------------------------

-- `onProp` marks slots resting on a prop (table, altar) rather than terrain.
function Dress.AddLoreSlot(ctx: DressContext, floor: Vector3, zone: string, anchor: string?, hidden: boolean?, facing: Vector3?, tag: string?, onProp: boolean?)
	if not onProp then
		-- Callers often offset from a measured point; measure again here.
		floor = Dress.FloorAt(ctx, floor + Vector3.yAxis * 2, 3, 10) or floor
	end
	local cf = if facing then Dress.Facing(floor, floor + facing) else CFrame.new(floor) * Dress.Yaw(ctx)
	local wallHit, wallNormal = Dress.NearestWall(ctx, floor + Vector3.yAxis * 3.5, 18)
	table.insert(ctx.Results.LoreSlots, {
		CFrame = cf,
		Wall = if wallHit and wallNormal then Dress.OnWall(wallHit, wallNormal) else nil,
		Zone = zone,
		Anchor = anchor,
		Hidden = hidden == true,
		Used = false,
		Tag = tag,
		OnProp = onProp == true,
	})
end

function Dress.AddLootSpot(ctx: DressContext, floor: Vector3, zone: string, hidden: boolean?)
	table.insert(ctx.Results.LootSpots, { Position = floor, Zone = zone, Hidden = hidden == true })
end

function Dress.AddHidingSpot(ctx: DressContext, cframe: CFrame, size: Vector3, zone: string)
	local volume = Instance.new("Part")
	volume.Name = "HidingSpot"
	volume.Anchored = true
	volume.CanCollide = false
	volume.CanQuery = false
	volume.CanTouch = false
	volume.Transparency = 1
	volume.CastShadow = false
	volume.CFrame = cframe
	volume.Size = size
	volume.Parent = ctx.Volumes
	CollectionService:AddTag(volume, Constants.Tags.HidingSpot)
	table.insert(ctx.Results.HidingSpots, { CFrame = cframe, Size = size, Zone = zone })
end

return Dress
