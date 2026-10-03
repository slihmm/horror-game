--!strict
-- Geometry plans for the handcrafted story anchors (see CaveLayout). Each
-- plan carves its space, creates graph nodes and exposes ports for the spine
-- tunnels. Dressing (props, lights, lore) happens later in RoomDressers once
-- the terrain exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Primitives = require(script.Parent.CavePrimitives)

type Context = Primitives.Context
type Anchor = Primitives.Anchor
type Sample = Primitives.Sample

local UP = Vector3.yAxis
local FF = CaveConfig.FloorFraction
local SHELL = CaveConfig.ShellThickness

local RoomPlans: { [string]: (Context, Anchor) -> () } = {}

local function chamber(ctx: Context, anchor: Anchor, overrides: { [string]: any }?)
	local opts: Primitives.ChamberOptions = {
		Zone = anchor.Zone,
		Group = anchor.Group,
		Radius = anchor.Radius,
		Height = anchor.Height,
		Anchor = anchor.Id,
	}
	if overrides then
		for k, v in overrides do
			(opts :: any)[k] = v
		end
	end
	local result = Primitives.Chamber(ctx, anchor.Position, opts)
	anchor.Node = result.Center
	anchor.Data.Ring = result.Ring
	anchor.Data.Samples = result.Samples
	return result
end

local function surfaceNode(ctx: Context, anchor: Anchor)
	local node = ctx.Graph:AddNode(anchor.Position, 40, anchor.Zone, anchor.Group, anchor.Id)
	node.Tags.Surface = true
	anchor.Node = node
end

-- Carves a passage from the open surface into an anchor chamber and exposes
-- the outside end as the "Outside" port.
local function surfacePassage(ctx: Context, anchor: Anchor, towards: Vector3)
	local flatDir = Vector3.new(towards.X - anchor.Position.X, 0, towards.Z - anchor.Position.Z).Unit
	local outside = Vector3.new(anchor.Position.X, 0.6, anchor.Position.Z) + flatDir * 46
	local outsideNode = ctx.Graph:AddNode(outside, 10, "Surface", anchor.Group)
	outsideNode.Tags.Surface = true
	Primitives.Tunnel(ctx, outside, anchor.Position, {
		Radius = NumberRange.new(9, 12),
		Zone = anchor.Zone,
		Group = anchor.Group,
		StartNode = outsideNode,
		EndNode = anchor.Node,
		Wander = 0.1,
	})
	anchor.Ports.Outside = outside
	anchor.PortNodes.Outside = outsideNode
	anchor.Data.OutsideDirection = flatDir
end

RoomPlans.SurfaceCamp = surfaceNode
RoomPlans.ExitValley = surfaceNode

RoomPlans.CaveMouth = function(ctx, anchor)
	chamber(ctx, anchor)
	local camp = ctx.Anchors.SurfaceCamp
	surfacePassage(ctx, anchor, if camp then camp.Position else anchor.Position - Vector3.xAxis * 50)
end

RoomPlans.ExitMouth = function(ctx, anchor)
	chamber(ctx, anchor)
	local valley = ctx.Anchors.ExitValley
	surfacePassage(ctx, anchor, if valley then valley.Position else anchor.Position + Vector3.xAxis * 50)
end

RoomPlans.UpperHall = function(ctx, anchor)
	local result = chamber(ctx, anchor)
	-- Narrow cracks to the surface: real daylight falls through them.
	local rng = ctx.Rng
	local shafts = {}
	for i = 1, CaveConfig.Decoration.UpperLightShafts do
		local angle = (i / CaveConfig.Decoration.UpperLightShafts) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * anchor.Radius * rng:NextNumber(0.25, 0.55)
		local base = anchor.Position + offset
		local ceiling = base + UP * anchor.Height * (1 + FF) * 0.8
		local y = ceiling.Y
		while y < 140 do
			local wiggle = Vector3.new(math.noise(y * 0.05, i) * 2, 0, math.noise(y * 0.05, i + 9) * 2)
			Primitives.Ball(ctx.Ops.Late, Vector3.new(base.X, y, base.Z) + wiggle, 3.2, Enum.Material.Air)
			y += 3
		end
		table.insert(shafts, { Floor = base, Ceiling = ceiling })
	end
	anchor.Data.LightShafts = shafts
	anchor.Data.FloorY = result.FloorY
end

RoomPlans.ShaftTop = function(ctx, anchor)
	chamber(ctx, anchor)
end

RoomPlans.ShaftBottom = function(ctx, anchor)
	chamber(ctx, anchor)
end

RoomPlans.ChimneyBase = function(ctx, anchor)
	chamber(ctx, anchor)
end

RoomPlans.ChimneyTop = function(ctx, anchor)
	chamber(ctx, anchor)
end

RoomPlans.Cistern = function(ctx, anchor)
	chamber(ctx, anchor)
	local zone = ZoneConfig.Get(anchor.Zone)
	-- Central pool.
	local poolRadius = anchor.Radius * 0.42
	local bowl = anchor.Position - UP * poolRadius * 0.55
	Primitives.Ball(ctx.Ops.Shell, bowl, poolRadius + SHELL * 0.6, zone.WallMaterial)
	Primitives.Ball(ctx.Ops.Late, bowl, poolRadius, Enum.Material.Air)
	Primitives.Block(
		ctx.Ops.Water,
		CFrame.new(anchor.Position - UP * (poolRadius * 0.8)),
		Vector3.new(poolRadius * 2.2, poolRadius * 1.6 - 0.6, poolRadius * 2.2),
		Enum.Material.Water
	)
	anchor.Data.Pool = { Center = anchor.Position, Radius = poolRadius }
	-- Flowstone pillars around it (outside the node ring at 0.55R). Placed
	-- after the tunnels exist so none lands across a doorway.
	anchor.Data.PendingColumns = {
		Key = "Pillars",
		Count = 4,
		Distance = NumberRange.new(0.78, 0.86),
		Radius = NumberRange.new(2.2, 3.6),
		Height = anchor.Height * (1 + FF) + 4,
		Material = zone.AccentMaterial,
	}
end

-- The loop: a ring tunnel. The way on is sealed until someone has walked
-- all the way around and passed the skeleton twice.
RoomPlans.LoopRing = function(ctx, anchor)
	local cfg = CaveConfig.Ring
	local rng = ctx.Rng
	local zone = ZoneConfig.Get(anchor.Zone)
	local center = anchor.Position
	local entryTarget = ctx.Anchors.Cistern
	local exitTarget = ctx.Anchors.DeepHall
	local function angleTo(target: Anchor?, fallback: number): number
		if not target then
			return fallback
		end
		local d = target.Position - center
		return math.atan2(d.Z, d.X)
	end
	local entryAngle = angleTo(entryTarget, math.pi)
	local exitAngle = angleTo(exitTarget, 0)
	local phase1, phase2, phase3 = rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)
	local function ringPoint(a: number): (Vector3, number)
		local rr = cfg.Radius + 5 * math.sin(3 * a + phase1)
		local y = 3 * math.sin(2 * a + phase2)
		local r = cfg.TunnelRadius + 1.2 * math.sin(5 * a + phase3)
		return center + Vector3.new(math.cos(a) * rr, y, math.sin(a) * rr), r
	end
	local samples: { Sample } = {}
	local step = 3 / cfg.Radius
	local a = 0
	while a < math.pi * 2 do
		local floor, r = ringPoint(a)
		table.insert(samples, { P = floor + UP * FF * r, R = r, Floor = floor })
		a += step
	end
	local count = #samples
	for i, s in samples do
		Primitives.Ball(ctx.Ops.Carve, s.P, s.R, Enum.Material.Air)
		if i % 2 == 1 then
			Primitives.Ball(ctx.Ops.Shell, s.P, s.R + SHELL, zone.WallMaterial)
		end
		local nextP = samples[(i % count) + 1].P
		local cf = CFrame.lookAt(s.P, nextP)
		local thickness = (1 - FF) * s.R + 3
		Primitives.Block(
			ctx.Ops.Floor,
			cf.Rotation + (s.P - cf.UpVector * (FF * s.R + thickness / 2)),
			Vector3.new(s.R * 1.9, thickness, 6.8),
			zone.FloorMaterial
		)
	end
	Primitives.RegisterSamples(ctx, samples, anchor.Group)

	-- Ring nodes, linked as a cycle.
	local graph = ctx.Graph
	local nodes = {}
	local nodeCount = math.floor(2 * math.pi * cfg.Radius / 16)
	for k = 0, nodeCount - 1 do
		local floor, r = ringPoint(k / nodeCount * math.pi * 2)
		local node = graph:AddNode(floor, r, anchor.Zone, anchor.Group, if k == 0 then anchor.Id else nil)
		node.Tags.Ring = true
		table.insert(nodes, node)
	end
	for k, node in nodes do
		graph:Link(node, nodes[(k % nodeCount) + 1])
	end
	anchor.Node = nodes[1]
	local function nodeAtAngle(angle: number)
		local index = math.floor(((angle % (math.pi * 2)) / (math.pi * 2)) * nodeCount + 0.5) % nodeCount
		return nodes[index + 1]
	end
	local entryFloor = ringPoint(entryAngle)
	local exitFloor = ringPoint(exitAngle)
	anchor.Ports.Entry = entryFloor
	anchor.Ports.Exit = exitFloor
	anchor.PortNodes.Entry = nodeAtAngle(entryAngle)
	anchor.PortNodes.Exit = nodeAtAngle(exitAngle)
	anchor.Node = anchor.PortNodes.Entry

	-- The landmark sits a little way around from the entry so the player
	-- passes it immediately, and again after a full lap.
	local direction = if rng:NextNumber() < 0.5 then 1 else -1
	local landmarkAngle = entryAngle + direction * 0.32
	local landmarkFloor, landmarkR = ringPoint(landmarkAngle)
	local radial = Vector3.new(math.cos(landmarkAngle), 0, math.sin(landmarkAngle))
	anchor.Data.Landmark = {
		Position = landmarkFloor + radial * landmarkR * 0.55,
		Facing = -radial,
	}

	-- Seal on the exit passage: opened at runtime by the LandmarkService.
	local outward = Vector3.new(math.cos(exitAngle), 0, math.sin(exitAngle))
	local sealFloor = exitFloor + outward * (cfg.TunnelRadius + 6)
	local sealCFrame = CFrame.lookAt(sealFloor, sealFloor + outward)
	local sealSize = Vector3.new(cfg.TunnelRadius * 2 + 8, cfg.TunnelRadius * 2 + 6, 7)
	local sealCenter = sealCFrame + Vector3.new(0, sealSize.Y / 2 + 0.6, 0)
	Primitives.Block(ctx.Ops.Detail, sealCenter, sealSize, zone.WallMaterial)
	anchor.Data.Seal = { CFrame = sealCenter, Size = sealSize, Floor = sealFloor, Outward = outward }
	anchor.Data.Samples = samples
	anchor.Data.EntryAngle = entryAngle
	anchor.Data.ExitAngle = exitAngle
end

RoomPlans.DeepHall = function(ctx, anchor)
	chamber(ctx, anchor)
end

RoomPlans.ExplorerCamp = function(ctx, anchor)
	chamber(ctx, anchor)
	-- Two hiding crevices in the camp walls.
	local samples = anchor.Data.Samples :: { Sample }
	for i = 1, 2 do
		local angle = ctx.Rng:NextNumber(0, math.pi * 2)
		local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local s = samples[1]
		local wallSample: Sample = { P = s.P, R = anchor.Radius, Floor = anchor.Position }
		Primitives.Alcove(ctx, wallSample, side, anchor.Zone)
	end
end

RoomPlans.Lair = function(ctx, anchor)
	chamber(ctx, anchor)
	-- A low den scooped out of one side, where the lamps are piled.
	local angle = ctx.Rng:NextNumber(0, math.pi * 2)
	local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local den = anchor.Position + side * anchor.Radius * 0.8 - UP * 2
	Primitives.Ball(ctx.Ops.Late, den + UP * 4, 8, Enum.Material.Air)
	anchor.Data.Den = den
end

RoomPlans.AncientGate = function(ctx, anchor)
	chamber(ctx, anchor, { FloorMaterial = Enum.Material.Pavement })
end

RoomPlans.Colonnade = function(ctx, anchor)
	chamber(ctx, anchor, { FloorMaterial = Enum.Material.Pavement })
end

RoomPlans.FinalChamber = function(ctx, anchor)
	chamber(ctx, anchor)
	local zone = ZoneConfig.Get(anchor.Zone)
	-- A low mound in the middle where the structure stands.
	Primitives.Ball(ctx.Ops.Detail, anchor.Position - UP * 14, 22, zone.FloorMaterial)
	-- Ring of tall natural columns, between the two node rings (0.4R/0.75R).
	anchor.Data.PendingColumns = {
		Key = "Columns",
		Count = 7,
		Distance = NumberRange.new(0.56, 0.6),
		Radius = NumberRange.new(4, 7),
		Height = anchor.Height * 1.8,
		Material = zone.WallMaterial,
	}
end

return RoomPlans
