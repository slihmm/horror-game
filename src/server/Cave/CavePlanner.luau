--!strict
-- Turns CaveLayout + a seed into a complete plan: terrain operations, the
-- cave graph, traversals, secrets and dressing features. Pure computation:
-- nothing touches the DataModel here, so a plan can be generated, inspected
-- and regenerated cheaply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveLayout = require(Shared.Config.CaveLayout)
local Primitives = require(script.Parent.CavePrimitives)
local RoomPlans = require(script.Parent.RoomPlans)
local CaveBranches = require(script.Parent.CaveBranches)

type Context = Primitives.Context
type Anchor = Primitives.Anchor

local CavePlanner = {}

local function resolveAnchors(ctx: Context)
	local rng = ctx.Rng
	for _, def in CaveLayout.Anchors do
		local position = def.Position
		if def.Jitter then
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(0, def.Jitter)
			position += Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		end
		local anchor: Anchor = {
			Id = def.Id,
			Zone = def.Zone,
			Builder = def.Builder,
			Position = position,
			Radius = def.Radius or 12,
			Height = def.Height or 10,
			FloorY = position.Y,
			Group = Primitives.NewGroup(ctx),
			Node = nil,
			Ports = {},
			PortNodes = {},
			Data = {},
		}
		ctx.Anchors[def.Id] = anchor
	end
end

local function port(anchor: Anchor, name: string?): (Vector3, any)
	if name and anchor.Ports[name] then
		return anchor.Ports[name], anchor.PortNodes[name]
	end
	return anchor.Position, anchor.Node
end

local function addBranchable(ctx: Context, samples: { Primitives.Sample }, nodes: { any }, zone: string, group: number)
	table.insert(ctx.Branchable, { Samples = samples, Nodes = nodes, Zone = zone, Group = group })
end

local function planTunnelEdge(ctx: Context, edge: any, from: Anchor, to: Anchor)
	local a, nodeA = port(from, edge.FromPort)
	local b, nodeB = port(to, edge.ToPort)
	local zone = edge.Zone or to.Zone
	local radius = edge.Radius or NumberRange.new(6, 9)
	local group = Primitives.NewGroup(ctx)
	local startTag = if edge.FromPort == "Exit" and from.Builder == "LoopRing" then "RingSeal" else nil

	if edge.Squeeze then
		local s1 = a:Lerp(b, 0.44)
		local s2 = a:Lerp(b, 0.56)
		local endA = ctx.Graph:AddNode(s1, 4, zone, group)
		local endB = ctx.Graph:AddNode(s2, 4, zone, group)
		local samples1, nodes1 = Primitives.Tunnel(ctx, a, s1, {
			Radius = radius,
			Zone = zone,
			Group = group,
			StartNode = nodeA,
			EndNode = endA,
			TaperEnd = 0.6,
			Flooded = edge.Flooded,
			StartLinkTag = startTag,
		})
		local samples2, nodes2 = Primitives.Tunnel(ctx, b, s2, {
			Radius = radius,
			Zone = zone,
			Group = group,
			StartNode = nodeB,
			EndNode = endB,
			TaperEnd = 0.6,
			Flooded = edge.Flooded,
		})
		Primitives.Squeeze(ctx, s1, s2, zone, endA, endB, `Squeeze_{from.Id}_{to.Id}`)
		if not edge.NoBranches then
			addBranchable(ctx, samples1, nodes1, zone, group)
			addBranchable(ctx, samples2, nodes2, zone, group)
		end
		return
	end

	local samples, nodes = Primitives.Tunnel(ctx, a, b, {
		Radius = radius,
		Zone = zone,
		Group = group,
		StartNode = nodeA,
		EndNode = nodeB,
		Flooded = edge.Flooded,
		Wander = edge.Wander,
		StartLinkTag = startTag,
	})
	if not edge.NoBranches then
		addBranchable(ctx, samples, nodes, zone, group)
	end
end

function CavePlanner.Plan(seed: number): Context
	local ctx = Primitives.NewContext(seed)
	resolveAnchors(ctx)

	-- Anchor rooms, in layout order (some plans look at other anchors).
	for _, def in CaveLayout.Anchors do
		local anchor = ctx.Anchors[def.Id]
		local plan = RoomPlans[anchor.Builder]
		assert(plan, `No room plan for builder '{anchor.Builder}'`)
		plan(ctx, anchor)
		assert(anchor.Node, `Room plan '{anchor.Builder}' did not create a node`)
		Primitives.AddFeature(ctx, { Kind = "Anchor", Id = anchor.Id })
	end

	-- Spine connections.
	for _, edge in CaveLayout.Spine do
		local from = ctx.Anchors[edge.From]
		local to = ctx.Anchors[edge.To]
		assert(from and to, `Spine edge references unknown anchor {edge.From} -> {edge.To}`)
		if edge.Kind == "Surface" then
			local _, nodeA = port(from, "Outside")
			local _, nodeB = port(to, "Outside")
			ctx.Graph:Link(nodeA, nodeB, "Walk", "Surface")
		elseif edge.Kind == "Tunnel" then
			planTunnelEdge(ctx, edge, from, to)
		elseif edge.Kind == "Rope" or edge.Kind == "Climb" then
			local bottom, top = from, to
			if from.FloorY > to.FloorY then
				bottom, top = to, from
			end
			Primitives.Vertical(ctx, bottom, top, edge.Kind, edge.Zone or bottom.Zone)
		elseif edge.Kind == "Recursion" then
			Primitives.Recursion(ctx, from, to, edge.Zone or from.Zone)
		else
			error(`Unknown spine edge kind '{edge.Kind}'`)
		end
	end

	-- Hidden rooms first: they matter more than ordinary branches and need
	-- the most free space around the spine.
	CaveBranches.GrowHidden(ctx)
	CaveBranches.Grow(ctx)
	CaveBranches.Decorate(ctx)

	local entrance = ctx.Anchors[CaveLayout.EntranceAnchor]
	ctx.Graph:ComputeDistances(entrance.Node :: any)
	return ctx
end

return CavePlanner
