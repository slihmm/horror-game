--!strict
-- Geometry primitives for the cave planner. Planning is pure data: every
-- primitive appends terrain operations and graph nodes to the context; the
-- TerrainBuilder executes the operations later in a fixed order:
--
--   Shell (rock) -> Carve (air) -> Floor -> Detail (rock) -> Late (air) -> Water
--
-- Shells are written before any carving so overlapping volumes never refill
-- each other's interiors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Spline = require(Shared.Utility.Spline)
local MathUtil = require(Shared.Utility.MathUtil)
local CaveGraph = require(script.Parent.CaveGraph)

type Node = CaveGraph.Node
type CaveGraph = CaveGraph.CaveGraph

export type Sample = {
	P: Vector3, -- carve center
	R: number,
	Floor: Vector3,
}

export type Op = {
	Shape: string, -- Ball | Block | Cylinder
	Material: Enum.Material,
	Center: Vector3?,
	Radius: number?,
	CFrame: CFrame?,
	Size: Vector3?,
	Height: number?,
}

export type Ops = {
	Shell: { Op },
	Carve: { Op },
	Floor: { Op },
	-- Re-opens headroom along tunnel centerlines after floors are laid, so
	-- one space's floor never plugs another passage (e.g. a tunnel descending
	-- out of a chamber through the chamber's floor).
	Clear: { Op },
	Detail: { Op },
	Late: { Op },
	Water: { Op },
}

export type Feature = { [string]: any }

export type Traversal = {
	Id: string,
	Kind: string,
	Path: { Vector3 },
	Zone: string,
	NodeA: Node,
	NodeB: Node,
}

export type Anchor = {
	Id: string,
	Zone: string,
	Builder: string,
	Position: Vector3, -- floor point at the chamber center
	Radius: number,
	Height: number,
	FloorY: number,
	Group: number,
	Node: Node?,
	Ports: { [string]: Vector3 },
	PortNodes: { [string]: Node },
	Data: { [string]: any },
}

export type Secret = {
	Id: string,
	Center: Vector3,
	Radius: number,
	Zone: string,
}

export type Context = {
	Seed: number,
	Rng: Random,
	Graph: CaveGraph,
	Ops: Ops,
	Features: { Feature },
	Traversals: { Traversal },
	Anchors: { [string]: Anchor },
	Secrets: { Secret },
	SampleCells: { [number]: { { P: Vector3, R: number, Group: number } } },
	NextGroup: number,
	NoiseSeed: number,
	-- Tunnels that may grow branches: { samples, nodes, zone, group }.
	Branchable: { { Samples: { Sample }, Nodes: { Node }, Zone: string, Group: number } },
	-- Diagnostics: attempts/successes per branch type.
	BranchStats: { [string]: { Attempts: number, Placed: number } },
}

export type TunnelOptions = {
	Radius: NumberRange,
	Zone: string,
	Group: number,
	Wander: number?,
	Flooded: boolean?,
	StartNode: Node?,
	EndNode: Node?,
	StartLinkTag: string?,
	-- Narrow toward the end (dead ends, squeeze approaches).
	TaperEnd: number?,
	Late: boolean?,
	NoFloor: boolean?,
	FloorMaterial: Enum.Material?,
	WallMaterial: Enum.Material?,
	Straight: boolean?,
}

local UP = Vector3.yAxis
local FF = CaveConfig.FloorFraction
local SHELL = CaveConfig.ShellThickness
local CLEAR_CELL = 32

local Primitives = {}

function Primitives.NewContext(seed: number): Context
	return {
		Seed = seed,
		Rng = Random.new(seed),
		Graph = CaveGraph.new(),
		Ops = { Shell = {}, Carve = {}, Floor = {}, Clear = {}, Detail = {}, Late = {}, Water = {} },
		Features = {},
		Traversals = {},
		Anchors = {},
		Secrets = {},
		SampleCells = {},
		NextGroup = 1,
		NoiseSeed = (seed % 10007) / 97.3,
		Branchable = {},
		BranchStats = {},
	}
end

function Primitives.NewGroup(ctx: Context): number
	ctx.NextGroup += 1
	return ctx.NextGroup
end

function Primitives.Ball(list: { Op }, center: Vector3, radius: number, material: Enum.Material)
	table.insert(list, { Shape = "Ball", Material = material, Center = center, Radius = radius })
end

function Primitives.Block(list: { Op }, cframe: CFrame, size: Vector3, material: Enum.Material)
	table.insert(list, { Shape = "Block", Material = material, CFrame = cframe, Size = size })
end

function Primitives.Cylinder(list: { Op }, cframe: CFrame, height: number, radius: number, material: Enum.Material)
	table.insert(list, { Shape = "Cylinder", Material = material, CFrame = cframe, Height = height, Radius = radius })
end

function Primitives.AddFeature(ctx: Context, feature: Feature)
	table.insert(ctx.Features, feature)
end

-- Clearance hash ---------------------------------------------------------

local function clearKey(x: number, y: number, z: number): number
	return (x + 1024) * 4194304 + (y + 1024) * 2048 + (z + 1024)
end

function Primitives.RegisterSamples(ctx: Context, samples: { Sample }, group: number)
	for _, s in samples do
		local key = clearKey(math.floor(s.P.X / CLEAR_CELL), math.floor(s.P.Y / CLEAR_CELL), math.floor(s.P.Z / CLEAR_CELL))
		local bucket = ctx.SampleCells[key]
		if not bucket then
			bucket = {}
			ctx.SampleCells[key] = bucket
		end
		table.insert(bucket, { P = s.P, R = s.R, Group = group })
	end
end

-- True when none of `samples` comes within `clearance` of geometry owned by a
-- group that isn't in `ignore`.
function Primitives.IsClear(ctx: Context, samples: { Sample }, ignore: { [number]: boolean }, clearance: number): boolean
	for _, s in samples do
		local cx, cy, cz = math.floor(s.P.X / CLEAR_CELL), math.floor(s.P.Y / CLEAR_CELL), math.floor(s.P.Z / CLEAR_CELL)
		for x = cx - 2, cx + 2 do
			for y = cy - 2, cy + 2 do
				for z = cz - 2, cz + 2 do
					local bucket = ctx.SampleCells[clearKey(x, y, z)]
					if bucket then
						for _, other in bucket do
							if not ignore[other.Group] then
								local needed = s.R + other.R + clearance
								if (other.P - s.P).Magnitude < needed then
									return false
								end
							end
						end
					end
				end
			end
		end
	end
	return true
end

-- Tunnels -----------------------------------------------------------------

local function noise01(ctx: Context, t: number, salt: number): number
	return math.clamp(math.noise(t, ctx.NoiseSeed + salt, salt * 0.31) * 0.5 + 0.5 + 0.5 * math.noise(t * 2.3, salt) * 0.5, 0, 1)
end

-- Computes the samples of a tunnel between two floor points without
-- committing anything. Callers can test clearance before committing.
function Primitives.TunnelCompute(ctx: Context, a: Vector3, b: Vector3, opts: TunnelOptions): { Sample }
	local rng = ctx.Rng
	local cfg = CaveConfig.Tunnel
	local radius = opts.Radius
	local salt = rng:NextNumber(0, 1000)
	local delta = b - a
	local dist = delta.Magnitude
	if dist < 1 then
		return {}
	end
	local dir = delta.Unit
	local side = dir:Cross(UP)
	if side.Magnitude < 0.1 then
		side = Vector3.xAxis
	end
	side = side.Unit

	local startR = MathUtil.lerp(radius.Min, radius.Max, noise01(ctx, 0, salt))
	local controls = { a + UP * FF * startR }
	if not opts.Straight then
		local wander = math.min(cfg.MaxWander, dist * (opts.Wander or cfg.Wander))
		local count = math.max(0, math.floor(dist / cfg.ControlSpacing))
		for i = 1, count do
			local t = i / (count + 1)
			local envelope = math.sin(math.pi * t)
			local lateral = side * rng:NextNumber(-1, 1) * wander * envelope
			local segment = dist / (count + 1)
			local vertical = UP * rng:NextNumber(-1, 1) * math.min(segment * cfg.VerticalWander, 8) * envelope
			table.insert(controls, a:Lerp(b, t) + lateral + vertical + UP * FF * startR)
		end
	end
	table.insert(controls, b + UP * FF * startR)

	local centers = Spline.sample(controls, CaveConfig.CarveSpacing)
	local samples: { Sample } = {}
	local total = Spline.length(centers)
	local travelled = 0
	for i, p in centers do
		if i > 1 then
			travelled += (p - centers[i - 1]).Magnitude
		end
		local t = if total > 0 then travelled / total else 0
		local r = MathUtil.lerp(radius.Min, radius.Max, noise01(ctx, travelled * cfg.RadiusNoiseScale, salt))
		if opts.TaperEnd then
			r *= MathUtil.lerp(1, opts.TaperEnd, MathUtil.smoothstep((t - 0.6) / 0.4))
		end
		-- Control points are floor + FF*startR; re-derive the center from the
		-- floor so floor height stays continuous while the radius varies.
		local floorPoint = p - UP * FF * startR
		local center = floorPoint + UP * FF * r
		table.insert(samples, { P = center, R = r, Floor = floorPoint })
	end
	return samples
end

-- Writes terrain ops and graph nodes for computed samples. Returns the chain
-- of nodes from start to end (including StartNode/EndNode if given).
function Primitives.TunnelCommit(ctx: Context, samples: { Sample }, opts: TunnelOptions): { Node }
	local zone = ZoneConfig.Get(opts.Zone)
	local wall = opts.WallMaterial or zone.WallMaterial
	local floorMaterial = opts.FloorMaterial or zone.FloorMaterial
	local carveList = if opts.Late then ctx.Ops.Late else ctx.Ops.Carve
	local spacing = CaveConfig.CarveSpacing
	local count = #samples

	for i, s in samples do
		Primitives.Ball(carveList, s.P, s.R, Enum.Material.Air)
		if i % 2 == 1 or i == count then
			Primitives.Ball(ctx.Ops.Shell, s.P, s.R + SHELL, wall)
			if not opts.Late and not opts.NoFloor then
				-- Headroom core: bottom stays above this tunnel's own floor.
				Primitives.Ball(ctx.Ops.Clear, s.P + UP * s.R * 0.15, s.R * 0.55, Enum.Material.Air)
			end
		end
		if not opts.NoFloor then
			local nextP = samples[math.min(i + 1, count)].P
			local prevP = samples[math.max(i - 1, 1)].P
			local forward = nextP - prevP
			if forward.Magnitude < 0.01 then
				forward = Vector3.zAxis
			end
			local cf = CFrame.lookAt(s.P, s.P + forward.Unit)
			local thickness = (1 - FF) * s.R + 3
			local slabCenter = s.P - cf.UpVector * (FF * s.R + thickness / 2)
			Primitives.Block(
				ctx.Ops.Floor,
				cf.Rotation + slabCenter,
				Vector3.new(s.R * 1.9, thickness, spacing * 2.2),
				floorMaterial
			)
			if opts.Flooded then
				local depth = CaveConfig.Water.TunnelDepth + s.R * 0.08
				Primitives.Block(
					ctx.Ops.Water,
					cf.Rotation + (s.Floor + cf.UpVector * depth / 2),
					Vector3.new(s.R * 2.2, depth, spacing * 2.4),
					Enum.Material.Water
				)
			end
		end
	end

	Primitives.RegisterSamples(ctx, samples, opts.Group)

	-- Graph nodes along the tunnel.
	local graph = ctx.Graph
	local nodes: { Node } = {}
	local previous: Node? = opts.StartNode
	if previous then
		table.insert(nodes, previous)
	end
	local nodeSpacing = CaveConfig.Tunnel.NodeSpacing
	local sinceLast = 0
	local firstLink = true
	for i = 2, count - 1 do
		sinceLast += (samples[i].P - samples[i - 1].P).Magnitude
		if sinceLast >= nodeSpacing then
			sinceLast = 0
			local node = graph:AddNode(samples[i].Floor, samples[i].R, opts.Zone, opts.Group)
			if opts.Flooded then
				node.Tags.Water = true
			end
			if previous then
				graph:Link(previous, node, "Walk", if firstLink then opts.StartLinkTag else nil)
			end
			firstLink = false
			previous = node
			table.insert(nodes, node)
		end
	end
	local last = opts.EndNode
	if not last then
		local s = samples[count]
		last = graph:AddNode(s.Floor, s.R, opts.Zone, opts.Group)
	end
	if previous then
		graph:Link(previous, last :: Node, "Walk", if firstLink then opts.StartLinkTag else nil)
	end
	table.insert(nodes, last :: Node)
	return nodes
end

function Primitives.Tunnel(ctx: Context, a: Vector3, b: Vector3, opts: TunnelOptions): ({ Sample }, { Node })
	local samples = Primitives.TunnelCompute(ctx, a, b, opts)
	return samples, Primitives.TunnelCommit(ctx, samples, opts)
end

-- Chambers ------------------------------------------------------------------

export type ChamberOptions = {
	Zone: string,
	Group: number,
	Radius: number, -- horizontal
	Height: number, -- vertical radius of the carve balls
	FloorMaterial: Enum.Material?,
	WallMaterial: Enum.Material?,
	Anchor: string?,
	NoNodes: boolean?,
}

export type ChamberResult = {
	Samples: { Sample },
	Center: Node?,
	Ring: { Node },
	FloorY: number,
}

function Primitives.ChamberCompute(ctx: Context, floorCenter: Vector3, opts: ChamberOptions): { Sample }
	local rng = ctx.Rng
	local rh, rv = opts.Radius, opts.Height
	local core = floorCenter + UP * FF * rv
	local samples: { Sample } = {}
	local function add(offset: Vector3, r: number)
		local p = core + offset
		table.insert(samples, { P = p, R = r, Floor = Vector3.new(p.X, floorCenter.Y, p.Z) })
	end
	add(Vector3.zero, math.max(rv, math.min(rh, rv * 1.15)))
	if rh > rv * 1.05 then
		local step = rv * 0.8
		local d = step
		local outer = rh - rv * 0.75
		local rings = {}
		while d < outer do
			table.insert(rings, d)
			d += step
		end
		table.insert(rings, math.max(outer, step * 0.5))
		for _, ringDist in rings do
			local count = math.max(3, math.ceil(2 * math.pi * ringDist / (rv * 0.9)))
			local phase = rng:NextNumber(0, math.pi * 2)
			for k = 1, count do
				local angle = phase + (k / count) * math.pi * 2
				local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * ringDist * rng:NextNumber(0.9, 1.08)
				offset += UP * rng:NextNumber(-0.12, 0.18) * rv
				add(offset, rv * rng:NextNumber(0.82, 1.02))
			end
		end
	end
	return samples
end

function Primitives.ChamberCommit(ctx: Context, floorCenter: Vector3, samples: { Sample }, opts: ChamberOptions): ChamberResult
	local zone = ZoneConfig.Get(opts.Zone)
	local wall = opts.WallMaterial or zone.WallMaterial
	local floorMaterial = opts.FloorMaterial or zone.FloorMaterial
	for _, s in samples do
		Primitives.Ball(ctx.Ops.Carve, s.P, s.R, Enum.Material.Air)
		Primitives.Ball(ctx.Ops.Shell, s.P, s.R + SHELL, wall)
	end
	local thickness = (1 - FF) * opts.Height + 4
	Primitives.Cylinder(
		ctx.Ops.Floor,
		CFrame.new(floorCenter - UP * thickness / 2),
		thickness,
		opts.Radius + 2,
		floorMaterial
	)
	Primitives.RegisterSamples(ctx, samples, opts.Group)

	local result: ChamberResult = { Samples = samples, Center = nil, Ring = {}, FloorY = floorCenter.Y }
	if opts.NoNodes then
		return result
	end
	local graph = ctx.Graph
	local center = graph:AddNode(floorCenter, opts.Radius, opts.Zone, opts.Group, opts.Anchor)
	center.Tags.Chamber = true
	result.Center = center
	local ringCount = math.clamp(math.floor(opts.Radius / 7), 3, 10)
	local rings = { 0.55 }
	if opts.Radius > 40 then
		rings = { 0.4, 0.75 }
	end
	local previousRing: { Node }? = nil
	for _, fraction in rings do
		local ring: { Node } = {}
		for k = 1, ringCount do
			local angle = (k / ringCount) * math.pi * 2
			local p = floorCenter + Vector3.new(math.cos(angle), 0, math.sin(angle)) * opts.Radius * fraction
			local node = graph:AddNode(p, opts.Radius * 0.35, opts.Zone, opts.Group, nil)
			node.Tags.Chamber = true
			table.insert(ring, node)
			table.insert(result.Ring, node)
		end
		for k, node in ring do
			graph:Link(node, ring[(k % ringCount) + 1])
			if previousRing then
				graph:Link(node, previousRing[k])
			else
				graph:Link(node, center)
			end
		end
		previousRing = ring
	end
	return result
end

function Primitives.Chamber(ctx: Context, floorCenter: Vector3, opts: ChamberOptions): ChamberResult
	local samples = Primitives.ChamberCompute(ctx, floorCenter, opts)
	return Primitives.ChamberCommit(ctx, floorCenter, samples, opts)
end

-- Hiding alcove carved into a wall next to a tunnel sample.
function Primitives.Alcove(ctx: Context, sample: Sample, side: Vector3, zone: string)
	local pocket = sample.Floor + UP * 3.2 + side * (sample.R + 1.5)
	Primitives.Ball(ctx.Ops.Late, pocket, 3.8, Enum.Material.Air)
	Primitives.Ball(ctx.Ops.Late, pocket + side * 2 + UP * 0.5, 3, Enum.Material.Air)
	Primitives.AddFeature(ctx, {
		Kind = "Alcove",
		Position = pocket + side * 1,
		Normal = -side,
		Zone = zone,
	})
end

-- Squeeze passage: a narrow, wiggling crack the player can only pass through
-- with the scripted traversal. Returns the traversal record.
function Primitives.Squeeze(ctx: Context, a: Vector3, b: Vector3, zone: string, nodeA: Node, nodeB: Node, id: string): Traversal
	local rng = ctx.Rng
	local delta = b - a
	local dir = delta.Unit
	local side = dir:Cross(UP)
	if side.Magnitude < 0.1 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local controls = { a + UP * 2.6 }
	local bends = 3
	for i = 1, bends do
		local t = i / (bends + 1)
		table.insert(controls, a:Lerp(b, t) + UP * (2.6 + rng:NextNumber(-0.6, 0.6)) + side * rng:NextNumber(-2.5, 2.5))
	end
	table.insert(controls, b + UP * 2.6)
	local centers = Spline.sample(controls, 1.5)
	for i, p in centers do
		if i % 2 == 1 then
			Primitives.Ball(ctx.Ops.Late, p, 3.1, Enum.Material.Air)
		end
	end
	-- Approach points outside each mouth where the prompt lives.
	local path = { a - dir * 3 + UP * 2.8 }
	for _, p in centers do
		table.insert(path, p)
	end
	table.insert(path, b + dir * 3 + UP * 2.8)
	local traversal: Traversal = {
		Id = id,
		Kind = "Squeeze",
		Path = path,
		Zone = zone,
		NodeA = nodeA,
		NodeB = nodeB,
	}
	table.insert(ctx.Traversals, traversal)
	ctx.Graph:Link(nodeA, nodeB, "Squeeze")
	Primitives.AddFeature(ctx, { Kind = "SqueezeMouth", Position = a, Direction = dir, Zone = zone })
	Primitives.AddFeature(ctx, { Kind = "SqueezeMouth", Position = b, Direction = -dir, Zone = zone })
	return traversal
end

-- Vertical shaft (Rope) or chimney (Climb). The column is carved at the
-- bottom anchor's XZ; a connector tunnel joins it to the top anchor.
function Primitives.Vertical(ctx: Context, bottom: Anchor, top: Anchor, kind: string, zoneId: string)
	local rng = ctx.Rng
	local isRope = kind == "Rope"
	local radius = if isRope then 20 else 8
	local wobble = if isRope then 2 else 0.8
	local radiusNoise = if isRope then 0.16 else 0.08
	local axis = Vector3.new(bottom.Position.X, 0, bottom.Position.Z)
	local bottomY = bottom.FloorY
	local topY = top.FloorY
	local zone = ZoneConfig.Get(zoneId)
	local group = Primitives.NewGroup(ctx)
	local samples: { Sample } = {}
	local salt = rng:NextNumber(0, 100)
	local y = bottomY + radius * 0.4
	local ceiling = topY + (if isRope then 26 else 12)
	while y <= ceiling do
		local wx = math.noise(y * 0.03, salt) * wobble
		local wz = math.noise(y * 0.03, salt + 13) * wobble
		local r = radius * (1 + math.noise(y * 0.05, salt + 7) * radiusNoise)
		local p = Vector3.new(axis.X + wx, y, axis.Z + wz)
		table.insert(samples, { P = p, R = r, Floor = Vector3.new(p.X, bottomY, p.Z) })
		y += 4
	end
	for i, s in samples do
		Primitives.Ball(ctx.Ops.Carve, s.P, s.R, Enum.Material.Air)
		if i % 2 == 1 then
			Primitives.Ball(ctx.Ops.Shell, s.P, s.R + SHELL, zone.WallMaterial)
		end
	end
	Primitives.RegisterSamples(ctx, samples, group)

	local toTop = Vector3.new(top.Position.X, 0, top.Position.Z) - axis
	local dir = if toTop.Magnitude > 0.1 then toTop.Unit else Vector3.xAxis
	local rim = Vector3.new(axis.X, topY, axis.Z) + dir * (radius - 2)

	-- Ledges protruding from the shaft walls, away from the rope line.
	if isRope then
		for _ = 1, 7 do
			local angle = math.atan2(dir.Z, dir.X) + rng:NextNumber(1.2, math.pi * 2 - 1.2)
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local ledgeY = rng:NextNumber(bottomY + 30, topY - 10)
			Primitives.Ball(ctx.Ops.Detail, Vector3.new(axis.X, ledgeY, axis.Z) + out * (radius + 2.5), rng:NextNumber(4, 6.5), zone.AccentMaterial)
		end
	end

	-- Connector from the rim to the top anchor.
	local rimNode = ctx.Graph:AddNode(rim, 6, top.Zone, top.Group)
	local topNode = top.Node :: Node
	Primitives.Tunnel(ctx, rim, top.Position, {
		Radius = if isRope then NumberRange.new(6, 7) else NumberRange.new(5.5, 6.5),
		Zone = top.Zone,
		Group = top.Group,
		StartNode = rimNode,
		EndNode = topNode,
		Straight = true,
	})

	-- Keep the line well inside the noisy walls so the camera never clips.
	local hangOffset = radius - 7
	local topFloor = Vector3.new(axis.X, topY, axis.Z)
	local bottomFloor = Vector3.new(axis.X, bottomY, axis.Z)
	local path: { Vector3 }
	if isRope then
		path = {
			topFloor + dir * (radius + 1) + UP * 3,
			topFloor + dir * hangOffset + UP * 3,
			bottomFloor + dir * hangOffset + UP * 3.4,
			bottomFloor + dir * (hangOffset - 5) + UP * 3,
		}
	else
		path = {
			bottomFloor + dir * (radius - 6) + UP * 3,
			bottomFloor + dir * (radius - 4) + UP * 4,
			topFloor + dir * (radius - 4) + UP * 2.5,
			topFloor + dir * (radius + 3) + UP * 3,
		}
	end
	local bottomNode = bottom.Node :: Node
	local traversal: Traversal = {
		Id = `{kind}_{bottom.Id}`,
		Kind = kind,
		Path = path,
		Zone = zoneId,
		NodeA = if isRope then rimNode else bottomNode,
		NodeB = if isRope then bottomNode else rimNode,
	}
	table.insert(ctx.Traversals, traversal)
	ctx.Graph:Link(bottomNode, rimNode, if isRope then "Rope" else "Climb")
	Primitives.AddFeature(ctx, {
		Kind = if isRope then "Rope" else "ClimbRoute",
		Axis = axis,
		Direction = dir,
		Radius = radius,
		TopY = topY,
		BottomY = bottomY,
		Path = path,
		Zone = zoneId,
		TraversalId = traversal.Id,
	})
end

-- The impossible corridor: an axis-aligned passage made of identical modules.
-- Module translations are multiples of the voxel size, so every module
-- voxelizes identically and the client can loop the player seamlessly.
function Primitives.Recursion(ctx: Context, from: Anchor, to: Anchor, zoneId: string)
	local cfg = CaveConfig.Recursion
	local L = cfg.ModuleLength
	assert(L % CaveConfig.VoxelSize == 0, "Recursion.ModuleLength must be a multiple of VoxelSize")
	local zone = ZoneConfig.Get(zoneId)
	local group = Primitives.NewGroup(ctx)

	local delta = to.Position - from.Position
	local axis: Vector3
	if math.abs(delta.X) > math.abs(delta.Z) then
		axis = Vector3.new(math.sign(delta.X), 0, 0)
	else
		axis = Vector3.new(0, 0, math.sign(delta.Z))
	end
	local side = axis:Cross(UP).Unit
	local floorY = from.FloorY
	local origin = Vector3.new(from.Position.X, floorY, from.Position.Z) + axis * (from.Radius + 26)
	local steps = L // 3
	local samples: { Sample } = {}
	local baseR = cfg.Radius
	for m = 0, cfg.Modules - 1 do
		for j = 0, steps - 1 do
			local phase = j / steps * math.pi * 2
			local r = baseR + 0.9 * math.sin(phase) + 0.5 * math.sin(phase * 2 + 1)
			local lateral = side * 1.4 * math.sin(phase + 0.6)
			local floorPoint = origin + axis * (m * L + j * 3) + lateral
			local center = floorPoint + UP * FF * r
			table.insert(samples, { P = center, R = r, Floor = floorPoint })
			Primitives.Ball(ctx.Ops.Carve, center, r, Enum.Material.Air)
			if j % 2 == 0 then
				Primitives.Ball(ctx.Ops.Shell, center, r + SHELL, zone.WallMaterial)
			end
			local thickness = (1 - FF) * r + 3
			Primitives.Block(
				ctx.Ops.Floor,
				CFrame.lookAt(center, center + axis).Rotation + (floorPoint - UP * thickness / 2),
				Vector3.new(r * 1.9, thickness, 6.6),
				zone.FloorMaterial
			)
		end
		-- One rock rib per module on the same wall: identical every time.
		local rib = origin + axis * (m * L + 10) - side * (baseR + 1) + UP * 3.5
		Primitives.Ball(ctx.Ops.Detail, rib, 3.4, zone.WallMaterial)
	end
	Primitives.RegisterSamples(ctx, samples, group)

	local graph = ctx.Graph
	local length = cfg.Modules * L
	local corridorNodes: { Node } = {}
	local d = 0
	while d <= length do
		local node = graph:AddNode(origin + axis * d, baseR, zoneId, group)
		node.Tags.Recursion = true
		if #corridorNodes > 0 then
			graph:Link(corridorNodes[#corridorNodes], node)
		end
		table.insert(corridorNodes, node)
		d += 12
	end
	local startNode = corridorNodes[1]
	local endNode = corridorNodes[#corridorNodes]
	-- Approaches: these sit outside the periodic section.
	Primitives.Tunnel(ctx, from.Position, startNode.Position - axis * 2, {
		Radius = NumberRange.new(6.5, 8),
		Zone = from.Zone,
		Group = from.Group,
		StartNode = from.Node,
		EndNode = startNode,
		Straight = true,
	})
	Primitives.Tunnel(ctx, endNode.Position + axis * 2, to.Position, {
		Radius = NumberRange.new(6.5, 8),
		Zone = to.Zone,
		Group = to.Group,
		StartNode = endNode,
		EndNode = to.Node,
	})
	Primitives.AddFeature(ctx, {
		Kind = "Recursion",
		Origin = origin,
		Axis = axis,
		Side = side,
		ModuleLength = L,
		Modules = cfg.Modules,
		Radius = baseR,
		Zone = zoneId,
	})
end

return Primitives
