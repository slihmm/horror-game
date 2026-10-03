--!strict
-- Procedural growth around the spine: side chambers, dead ends, loops,
-- pits, bridges, pools, collapsed passages, hiding alcoves and hidden rooms.
-- Every branch is computed first, tested for clearance against unrelated
-- geometry, and only then committed, so procedural rooms never punch holes
-- into handcrafted spaces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Weighted = require(Shared.Utility.Weighted)
local Primitives = require(script.Parent.CavePrimitives)
local CaveGraph = require(script.Parent.CaveGraph)

type Context = Primitives.Context
type Sample = Primitives.Sample
type Node = CaveGraph.Node
type Branchable = { Samples: { Sample }, Nodes: { Node }, Zone: string, Group: number }

local UP = Vector3.yAxis
local SHELL = CaveConfig.ShellThickness

local CaveBranches = {}

local function nearestNode(nodes: { Node }, p: Vector3): Node
	local best = nodes[1]
	local bestD = math.huge
	for _, n in nodes do
		local d = (n.Position - p).Magnitude
		if d < bestD then
			best = n
			bestD = d
		end
	end
	return best
end

local function tangentAt(samples: { Sample }, i: number): Vector3
	local a = samples[math.max(1, i - 2)].P
	local b = samples[math.min(#samples, i + 2)].P
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	return if d.Magnitude > 0.01 then d.Unit else Vector3.xAxis
end

-- Picks a branch origin on a tunnel and a direction leading away from it.
local function pickOrigin(ctx: Context, br: Branchable): (number, Vector3)
	local count = #br.Samples
	local i = ctx.Rng:NextInteger(math.max(2, math.floor(count * 0.18)), math.max(2, math.floor(count * 0.82)))
	local tangent = tangentAt(br.Samples, i)
	local side = tangent:Cross(UP).Unit * (if ctx.Rng:NextNumber() < 0.5 then 1 else -1)
	local dir = (side + tangent * ctx.Rng:NextNumber(-0.6, 0.6)).Unit
	return i, dir
end

-- Drops the samples that sit inside the parent tunnel before testing
-- clearance (they overlap the parent by design).
local function skipInside(samples: { Sample }, origin: Vector3, parentRadius: number): { Sample }
	local result = {}
	for _, s in samples do
		if (s.P - origin).Magnitude > parentRadius + s.R + 2 then
			table.insert(result, s)
		end
	end
	return result
end

local function isClear(ctx: Context, samples: { Sample }, ignore: { number }): boolean
	local set = {}
	for _, g in ignore do
		set[g] = true
	end
	return Primitives.IsClear(ctx, samples, set, CaveConfig.Branches.Clearance)
end

local function concat(...: { Sample }): { Sample }
	local out = {}
	for _, list in { ... } do
		for _, s in list do
			table.insert(out, s)
		end
	end
	return out
end

local function roomFeature(ctx: Context, center: Vector3, radius: number, zone: string, content: string, hidden: boolean?, extra: { [string]: any }?)
	local feature: Primitives.Feature = {
		Kind = "Room",
		Content = content,
		Center = center,
		Radius = radius,
		Zone = zone,
		Hidden = hidden == true,
	}
	if extra then
		for k, v in extra do
			feature[k] = v
		end
	end
	Primitives.AddFeature(ctx, feature)
	return feature
end

-- Branch types --------------------------------------------------------------
-- Each returns true if it committed something.

local Types: { [string]: (Context, Branchable) -> boolean } = {}

-- Tunnel + chamber with a content roll. Shared by several types.
local function tunnelToChamber(
	ctx: Context,
	br: Branchable,
	lengthRange: NumberRange,
	radiusRange: NumberRange,
	tunnelRadius: NumberRange,
	onCommit: (center: Vector3, chamberResult: Primitives.ChamberResult, group: number) -> ()
): boolean
	local rng = ctx.Rng
	local i, dir = pickOrigin(ctx, br)
	local origin = br.Samples[i]
	local length = rng:NextNumber(lengthRange.Min, lengthRange.Max)
	local roomRadius = rng:NextNumber(radiusRange.Min, radiusRange.Max)
	local roomHeight = math.clamp(roomRadius * rng:NextNumber(0.6, 0.85), 7, 14)
	local slope = rng:NextNumber(-0.18, 0.12)
	local tunnelEnd = origin.Floor + dir * length + UP * length * slope
	local roomCenter = tunnelEnd + dir * roomRadius * 0.6
	local group = Primitives.NewGroup(ctx)
	local opts: Primitives.TunnelOptions = { Radius = tunnelRadius, Zone = br.Zone, Group = group, EndRoomRadius = roomRadius }
	local tunnelSamples = Primitives.TunnelCompute(ctx, origin.Floor, roomCenter, opts)
	local chamberOpts: Primitives.ChamberOptions = { Zone = br.Zone, Group = group, Radius = roomRadius, Height = roomHeight }
	local roomSamples = Primitives.ChamberCompute(ctx, roomCenter, chamberOpts)
	local test = concat(skipInside(tunnelSamples, origin.P, origin.R), roomSamples)
	if #test == 0 or not isClear(ctx, test, { br.Group }) then
		return false
	end
	local roomResult = Primitives.ChamberCommit(ctx, roomCenter, roomSamples, chamberOpts)
	opts.StartNode = nearestNode(br.Nodes, origin.Floor)
	opts.EndNode = roomResult.Center
	local nodes = Primitives.TunnelCommit(ctx, tunnelSamples, opts)
	table.insert(ctx.Branchable, { Samples = tunnelSamples, Nodes = nodes, Zone = br.Zone, Group = group })
	onCommit(roomCenter, roomResult, group)
	return true
end

Types.SideChamber = function(ctx, br)
	return tunnelToChamber(ctx, br, NumberRange.new(22, 55), NumberRange.new(10, 19), NumberRange.new(5, 7.5), function(center, result, _group)
		local content = Weighted.pickKey(CaveConfig.RoomContents, ctx.Rng) or "Empty"
		roomFeature(ctx, center, (result.Samples[1] :: Sample).R, br.Zone, content)
	end)
end

Types.DeadEnd = function(ctx, br)
	local rng = ctx.Rng
	local i, dir = pickOrigin(ctx, br)
	local origin = br.Samples[i]
	local length = rng:NextNumber(30, 70)
	local target = origin.Floor + dir * length + UP * length * rng:NextNumber(-0.2, 0.15)
	local group = Primitives.NewGroup(ctx)
	local opts: Primitives.TunnelOptions = { Radius = NumberRange.new(4.5, 7), Zone = br.Zone, Group = group, TaperEnd = 0.45, Wander = 0.35 }
	local samples = Primitives.TunnelCompute(ctx, origin.Floor, target, opts)
	local test = skipInside(samples, origin.P, origin.R)
	if #test == 0 or not isClear(ctx, test, { br.Group }) then
		return false
	end
	opts.StartNode = nearestNode(br.Nodes, origin.Floor)
	local nodes = Primitives.TunnelCommit(ctx, samples, opts)
	table.insert(ctx.Branchable, { Samples = samples, Nodes = nodes, Zone = br.Zone, Group = group })
	local last = samples[#samples]
	Primitives.AddFeature(ctx, {
		Kind = "DeadEnd",
		Position = last.Floor,
		Direction = dir,
		Radius = last.R,
		Zone = br.Zone,
	})
	nodes[#nodes].Tags.DeadEnd = true
	return true
end

Types.Collapsed = function(ctx, br)
	local rng = ctx.Rng
	local i, dir = pickOrigin(ctx, br)
	local origin = br.Samples[i]
	local length = rng:NextNumber(25, 50)
	local target = origin.Floor + dir * length
	local group = Primitives.NewGroup(ctx)
	local opts: Primitives.TunnelOptions = { Radius = NumberRange.new(5.5, 7.5), Zone = br.Zone, Group = group }
	local samples = Primitives.TunnelCompute(ctx, origin.Floor, target, opts)
	local test = skipInside(samples, origin.P, origin.R)
	if #test == 0 or not isClear(ctx, test, { br.Group }) then
		return false
	end
	opts.StartNode = nearestNode(br.Nodes, origin.Floor)
	local nodes = Primitives.TunnelCommit(ctx, samples, opts)
	local last = samples[#samples]
	local zone = ZoneConfig.Get(br.Zone)
	local plugCenter = last.P + dir * 2
	local plugRadius = last.R + 2
	Primitives.Ball(ctx.Ops.Detail, plugCenter, plugRadius, zone.WallMaterial)
	-- The rubble buries the tunnel's end: stop the graph in front of it.
	for k = #samples, 1, -1 do
		if (samples[k].P - plugCenter).Magnitude > plugRadius + 3 then
			nodes[#nodes].Position = samples[k].Floor
			break
		end
	end
	Primitives.AddFeature(ctx, {
		Kind = "Collapse",
		Position = last.Floor - dir * (last.R * 0.6),
		Direction = dir,
		Radius = last.R,
		Zone = br.Zone,
	})
	return true
end

Types.Loop = function(ctx, br)
	local rng = ctx.Rng
	-- Find a node elsewhere that is close in space but far along the graph.
	local i = rng:NextInteger(math.max(1, math.floor(#br.Samples * 0.15)), math.max(1, math.floor(#br.Samples * 0.85)))
	local origin = br.Samples[i]
	local startNode = nearestNode(br.Nodes, origin.Floor)
	local candidates = {}
	for _, other in ctx.Branchable do
		for _, node in other.Nodes do
			local d = (node.Position - startNode.Position).Magnitude
			local flatOk = math.abs(node.Position.Y - startNode.Position.Y) < d * 0.45
			if d > 45 and d < 130 and flatOk and node ~= startNode then
				table.insert(candidates, { Node = node, Group = other.Group })
			end
		end
	end
	if #candidates == 0 then
		return false
	end
	local pick = candidates[rng:NextInteger(1, #candidates)]
	local group = Primitives.NewGroup(ctx)
	local opts: Primitives.TunnelOptions = {
		Radius = NumberRange.new(5, 7.5),
		Zone = br.Zone,
		Group = group,
		Wander = 0.38,
	}
	local samples = Primitives.TunnelCompute(ctx, startNode.Position, pick.Node.Position, opts)
	local test = {}
	for _, s in samples do
		if (s.P - startNode.Position).Magnitude > startNode.Radius + s.R + 2 and (s.P - pick.Node.Position).Magnitude > pick.Node.Radius + s.R + 2 then
			table.insert(test, s)
		end
	end
	if #test == 0 or not isClear(ctx, test, { br.Group, pick.Group }) then
		return false
	end
	opts.StartNode = startNode
	opts.EndNode = pick.Node
	local nodes = Primitives.TunnelCommit(ctx, samples, opts)
	table.insert(ctx.Branchable, { Samples = samples, Nodes = nodes, Zone = br.Zone, Group = group })
	return true
end

Types.Pit = function(ctx, br)
	local rng = ctx.Rng
	local pitCfg = CaveConfig.Pit
	return tunnelToChamber(ctx, br, NumberRange.new(20, 40), NumberRange.new(14, 18), NumberRange.new(5.5, 7), function(center, _result, _group)
		local pitRadius = rng:NextNumber(pitCfg.Radius.Min, pitCfg.Radius.Max)
		local depth = rng:NextNumber(pitCfg.Depth.Min, pitCfg.Depth.Max)
		local zone = ZoneConfig.Get(br.Zone)
		local y = 0
		while y < depth do
			local p = center - UP * y + Vector3.new(math.noise(y * 0.05, 3) * 2, 0, math.noise(y * 0.05, 7) * 2)
			Primitives.Ball(ctx.Ops.Late, p, pitRadius, Enum.Material.Air)
			if y % 8 == 0 then
				Primitives.Ball(ctx.Ops.Shell, p, pitRadius + SHELL * 0.75, zone.WallMaterial)
			end
			y += 4
		end
		Primitives.AddFeature(ctx, { Kind = "Pit", Center = center, Radius = pitRadius, Depth = depth, Zone = br.Zone })
		roomFeature(ctx, center, pitRadius + 6, br.Zone, "PitEdge")
	end)
end

Types.Pool = function(ctx, br)
	local rng = ctx.Rng
	return tunnelToChamber(ctx, br, NumberRange.new(20, 45), NumberRange.new(12, 16), NumberRange.new(5, 7), function(center, _result, _group)
		local zone = ZoneConfig.Get(br.Zone)
		local poolRadius = rng:NextNumber(6, 9)
		local depth = CaveConfig.Water.PoolDepth
		local bowl = center - UP * (depth * 0.5)
		Primitives.Ball(ctx.Ops.Shell, bowl, poolRadius + SHELL * 0.6, zone.WallMaterial)
		Primitives.Ball(ctx.Ops.Late, bowl, poolRadius, Enum.Material.Air)
		Primitives.Block(
			ctx.Ops.Water,
			CFrame.new(center - UP * (depth * 0.5 + 0.4)),
			Vector3.new(poolRadius * 2.4, depth + 0.2, poolRadius * 2.4),
			Enum.Material.Water
		)
		roomFeature(ctx, center, poolRadius, br.Zone, "Pool", false, { Depth = depth })
	end)
end

Types.Bridge = function(ctx, br)
	local rng = ctx.Rng
	local i, dir = pickOrigin(ctx, br)
	local origin = br.Samples[i]
	local approach = rng:NextNumber(18, 32)
	local trenchHalf = 7
	local a = origin.Floor + dir * approach
	local mid = a + dir * (trenchHalf + 6)
	local b = mid + dir * (trenchHalf + 6)
	local roomCenter = b + dir * 16
	local group = Primitives.NewGroup(ctx)
	local zone = ZoneConfig.Get(br.Zone)
	local tunnelOpts: Primitives.TunnelOptions = { Radius = NumberRange.new(6, 7.5), Zone = br.Zone, Group = group }
	local approachSamples = Primitives.TunnelCompute(ctx, origin.Floor, a, tunnelOpts)
	local spanOpts: Primitives.TunnelOptions = { Radius = NumberRange.new(9, 10), Zone = br.Zone, Group = group, Straight = true }
	local spanSamples = Primitives.TunnelCompute(ctx, a, b, spanOpts)
	local roomOpts: Primitives.ChamberOptions = { Zone = br.Zone, Group = group, Radius = 10, Height = 8 }
	local exitOpts: Primitives.TunnelOptions = { Radius = NumberRange.new(5.5, 7), Zone = br.Zone, Group = group }
	local exitSamples = Primitives.TunnelCompute(ctx, b, roomCenter, exitOpts)
	local roomSamples = Primitives.ChamberCompute(ctx, roomCenter, roomOpts)
	local trench: { Sample } = {
		{ P = mid - UP * 30, R = 14, Floor = mid - UP * 60 },
		{ P = mid - UP * 55, R = 14, Floor = mid - UP * 70 },
	}
	local test = concat(skipInside(approachSamples, origin.P, origin.R), spanSamples, exitSamples, roomSamples, trench)
	if not isClear(ctx, test, { br.Group }) then
		return false
	end
	local room = Primitives.ChamberCommit(ctx, roomCenter, roomSamples, roomOpts)
	local nearA = ctx.Graph:AddNode(a, 7, br.Zone, group)
	local nearB = ctx.Graph:AddNode(b, 7, br.Zone, group)
	tunnelOpts.StartNode = nearestNode(br.Nodes, origin.Floor)
	tunnelOpts.EndNode = nearA
	Primitives.TunnelCommit(ctx, approachSamples, tunnelOpts)
	Primitives.TunnelCommit(ctx, spanSamples, spanOpts)
	exitOpts.StartNode = nearB
	exitOpts.EndNode = room.Center
	Primitives.TunnelCommit(ctx, exitSamples, exitOpts)
	-- The trench is cut after floors so it removes them.
	local side = dir:Cross(UP).Unit
	local trenchCFrame = CFrame.fromMatrix(mid - UP * 34, side, UP, -dir)
	local trenchSize = Vector3.new(26, 70, trenchHalf * 2)
	Primitives.Block(ctx.Ops.Shell, trenchCFrame, trenchSize + Vector3.one * SHELL * 1.6, zone.WallMaterial)
	Primitives.Block(ctx.Ops.Late, trenchCFrame, trenchSize, Enum.Material.Air)
	-- Graph: the bridge is a separate link the monster won't use.
	ctx.Graph:Link(nearA, nearB, "Walk", "Bridge")
	Primitives.AddFeature(ctx, {
		Kind = "Bridge",
		A = mid - dir * (trenchHalf + 1.5),
		B = mid + dir * (trenchHalf + 1.5),
		Direction = dir,
		Zone = br.Zone,
	})
	roomFeature(ctx, roomCenter, 10, br.Zone, "Loot")
	return true
end

Types.Alcove = function(ctx, br)
	local i = ctx.Rng:NextInteger(1, #br.Samples)
	local sample = br.Samples[i]
	local tangent = tangentAt(br.Samples, i)
	local side = tangent:Cross(UP).Unit * (if ctx.Rng:NextNumber() < 0.5 then 1 else -1)
	Primitives.Alcove(ctx, sample, side, br.Zone)
	return true
end

-- Hidden rooms --------------------------------------------------------------

local function hiddenRoom(ctx: Context, br: Branchable): boolean
	local rng = ctx.Rng
	local i, dir = pickOrigin(ctx, br)
	local origin = br.Samples[i]
	local group = Primitives.NewGroup(ctx)
	local roomRadius = rng:NextNumber(8, 13)
	local roomHeight = rng:NextNumber(7, 10)
	local useSqueeze = rng:NextNumber() < 0.5
	local content = Weighted.pickKey(CaveConfig.HiddenRoomContents, rng) or "Nothing"
	local index = #ctx.Secrets + 1
	local roomCenter: Vector3

	if useSqueeze then
		-- tunnel stub -> squeeze -> room
		local stubLength = rng:NextNumber(10, 18)
		local squeezeLength = rng:NextNumber(14, 20)
		local stubEnd = origin.Floor + dir * stubLength
		local squeezeEnd = stubEnd + dir * squeezeLength + UP * rng:NextNumber(-2, 2)
		roomCenter = squeezeEnd + dir * roomRadius * 0.7
		local stubOpts: Primitives.TunnelOptions = { Radius = NumberRange.new(4.5, 5.5), Zone = br.Zone, Group = group, TaperEnd = 0.75 }
		local stub = Primitives.TunnelCompute(ctx, origin.Floor, stubEnd, stubOpts)
		local roomOpts: Primitives.ChamberOptions = { Zone = br.Zone, Group = group, Radius = roomRadius, Height = roomHeight }
		local roomSamples = Primitives.ChamberCompute(ctx, roomCenter, roomOpts)
		local squeezeProbe: { Sample } = { { P = stubEnd:Lerp(squeezeEnd, 0.5) + UP * 3, R = 4, Floor = stubEnd } }
		if not isClear(ctx, concat(skipInside(stub, origin.P, origin.R), squeezeProbe, roomSamples), { br.Group }) then
			return false
		end
		local room = Primitives.ChamberCommit(ctx, roomCenter, roomSamples, roomOpts)
		stubOpts.StartNode = nearestNode(br.Nodes, origin.Floor)
		local stubNodes = Primitives.TunnelCommit(ctx, stub, stubOpts)
		-- The squeeze opens into the room's near wall.
		local entryNode = ctx.Graph:AddNode(squeezeEnd + dir * 2, 4, br.Zone, group)
		ctx.Graph:Link(entryNode, room.Center :: Node)
		Primitives.Squeeze(ctx, stubEnd, squeezeEnd, br.Zone, stubNodes[#stubNodes], entryNode, `Squeeze_hidden_{index}`)
		Primitives.Ball(ctx.Ops.Late, squeezeEnd + dir * 2 + UP * 3, 4.5, Enum.Material.Air)
	else
		-- A narrow, twisting crack whose mouth is half hidden by a boulder.
		local crackLength = rng:NextNumber(28, 45)
		roomCenter = origin.Floor + dir * (crackLength + roomRadius * 0.6) + UP * rng:NextNumber(-4, 6)
		local crackOpts: Primitives.TunnelOptions = { Radius = NumberRange.new(4.1, 4.7), Zone = br.Zone, Group = group, Wander = 0.5 }
		local crack = Primitives.TunnelCompute(ctx, origin.Floor, roomCenter, crackOpts)
		local roomOpts: Primitives.ChamberOptions = { Zone = br.Zone, Group = group, Radius = roomRadius, Height = roomHeight }
		local roomSamples = Primitives.ChamberCompute(ctx, roomCenter, roomOpts)
		if not isClear(ctx, concat(skipInside(crack, origin.P, origin.R), roomSamples), { br.Group }) then
			return false
		end
		local room = Primitives.ChamberCommit(ctx, roomCenter, roomSamples, roomOpts)
		crackOpts.StartNode = nearestNode(br.Nodes, origin.Floor)
		crackOpts.EndNode = room.Center
		Primitives.TunnelCommit(ctx, crack, crackOpts)
		-- Find where the crack leaves the parent tunnel to place the boulder.
		local mouth = crack[1]
		for _, s in crack do
			if (s.P - origin.P).Magnitude > origin.R + 1 then
				mouth = s
				break
			end
		end
		Primitives.AddFeature(ctx, { Kind = "CrackMouth", Position = mouth.Floor, Direction = dir, Zone = br.Zone })
	end
	local secretId = `hidden_{index}`
	table.insert(ctx.Secrets, { Id = secretId, Center = roomCenter, Radius = roomRadius + 2, Zone = br.Zone })
	roomFeature(ctx, roomCenter, roomRadius, br.Zone, content, true, { SecretId = secretId })
	return true
end

-- Entry points ----------------------------------------------------------------

local function growFrom(ctx: Context, list: { Branchable }, perTunnel: NumberRange, perHundred: number, typeWeights: { [string]: number })
	local rng = ctx.Rng
	local cfg = CaveConfig.Branches
	for _, br in list do
		local length = #br.Samples * CaveConfig.CarveSpacing
		local count = rng:NextInteger(perTunnel.Min, perTunnel.Max) + math.floor(length / 100 * perHundred)
		local weights = table.clone(typeWeights)
		local zoneWeights = cfg.ZoneWeights[br.Zone]
		if zoneWeights then
			for k, mult in zoneWeights do
				if weights[k] then
					weights[k] *= mult
				end
			end
		end
		for _ = 1, count do
			for _attempt = 1, cfg.MaxAttempts do
				local kind = Weighted.pickKey(weights, rng)
				local builder = kind and Types[kind]
				if builder then
					local stats = ctx.BranchStats[kind :: string] or { Attempts = 0, Placed = 0 }
					ctx.BranchStats[kind :: string] = stats
					stats.Attempts += 1
					if builder(ctx, br) then
						stats.Placed += 1
						break
					end
				end
			end
		end
	end
end

-- Two passes: branches off the spine, then a sparser pass off those
-- branches, which is what turns the cave into a maze worth getting lost in.
function CaveBranches.Grow(ctx: Context)
	local cfg = CaveConfig.Branches
	local spineCount = #ctx.Branchable
	growFrom(ctx, table.clone(ctx.Branchable), cfg.PerTunnel, cfg.PerHundredStuds, cfg.Types)
	local secondary = {}
	for i = spineCount + 1, #ctx.Branchable do
		table.insert(secondary, ctx.Branchable[i])
	end
	growFrom(ctx, secondary, cfg.Secondary.PerTunnel, 0, cfg.Secondary.Types)
end

function CaveBranches.GrowHidden(ctx: Context)
	local rng = ctx.Rng
	local range = CaveConfig.Branches.HiddenRooms
	local target = rng:NextInteger(range.Min, range.Max)
	local eligible = {}
	for _, br in ctx.Branchable do
		local zone = ZoneConfig.Get(br.Zone)
		if zone.Underground and br.Zone ~= "Escape" then
			table.insert(eligible, br)
		end
	end
	if #eligible == 0 then
		return
	end
	local placed = 0
	local attempts = 0
	while placed < target and attempts < target * 10 do
		attempts += 1
		local br = eligible[rng:NextInteger(1, #eligible)]
		if hiddenRoom(ctx, br) then
			placed += 1
		end
	end
end

-- Hiding crevices in monster habitat and decoration markers for the
-- populator (formations, rockfall spots).
function CaveBranches.Decorate(ctx: Context)
	local rng = ctx.Rng
	local deco = CaveConfig.Decoration
	for _, br in ctx.Branchable do
		local zone = ZoneConfig.Get(br.Zone)
		local samples = br.Samples
		local length = #samples * CaveConfig.CarveSpacing
		if zone.MonsterHabitat then
			local count = math.max(1, math.floor(length / 100 * deco.HidingAlcovesPerHundred + rng:NextNumber()))
			for _ = 1, count do
				Types.Alcove(ctx, br)
			end
		end
		Primitives.AddFeature(ctx, { Kind = "TunnelDecor", Samples = samples, Zone = br.Zone })
	end
end

return CaveBranches
