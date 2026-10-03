--!nocheck
-- Runs the cave planner for several seeds and checks structural invariants.
--   lune run tests/planner.spec.luau
local Harness = require("./Harness")
local env = Harness.load("build/Descent.rbxlx")

local CavePlanner = env.Require(env.Find("ServerScriptService.Server.Cave.CavePlanner"))
local CaveLayout = env.Require(env.Find("ReplicatedStorage.Shared.Config.CaveLayout"))
local CaveConfig = env.Require(env.Find("ReplicatedStorage.Shared.Config.CaveConfig"))

local failures = 0
local function check(cond, message)
	if not cond then
		failures += 1
		print("  FAIL: " .. message)
	end
end

for _, seed in { 1, 42, 1337, 90210, 777777 } do
	local t0 = os.clock()
	local ctx = CavePlanner.Plan(seed)
	local elapsed = os.clock() - t0
	local ops = ctx.Ops
	local opCount = #ops.Shell + #ops.Carve + #ops.Floor + #ops.Detail + #ops.Late + #ops.Water
	local rooms, hidden, kinds = 0, 0, {}
	for _, f in ctx.Features do
		kinds[f.Kind] = (kinds[f.Kind] or 0) + 1
		if f.Kind == "Room" then
			rooms += 1
			if f.Hidden then
				hidden += 1
			end
		end
	end
	print(string.format("seed %d: %.2fs, %d nodes, %d ops, %d rooms (%d hidden), %d traversals, %d secrets",
		seed, elapsed, #ctx.Graph.Nodes, opCount, rooms, hidden, #ctx.Traversals, #ctx.Secrets))
	local kindList = {}
	for k, v in kinds do
		table.insert(kindList, `{k}={v}`)
	end
	table.sort(kindList)
	print("  features: " .. table.concat(kindList, " "))

	-- Every story anchor must be reachable from the entrance.
	for _, def in CaveLayout.Anchors do
		local anchor = ctx.Anchors[def.Id]
		check(anchor.Node ~= nil, `{def.Id} has no node`)
		if anchor.Node then
			check(anchor.Node.Dist < math.huge, `{def.Id} unreachable from entrance`)
		end
	end
	-- Hidden room target met.
	check(hidden >= CaveConfig.Branches.HiddenRooms.Min - 2, `only {hidden} hidden rooms`)
	-- Progress increases along the story.
	local order = { "Mouth", "UpperHall", "ShaftBottom", "Cistern", "DeepHall", "Camp", "Threshold", "FinalChamber", "ExitMouth" }
	for i = 2, #order do
		local a = ctx.Anchors[order[i - 1]].Node.Dist
		local b = ctx.Anchors[order[i]].Node.Dist
		check(b > a, `progress not increasing {order[i - 1]} ({a}) -> {order[i]} ({b})`)
	end
	-- The monster can walk from its lair to the final chamber without ropes.
	local lair = ctx.Anchors[CaveLayout.LairAnchor].Node
	local final = ctx.Anchors.FinalChamber.Node
	local path = ctx.Graph:FindPath(lair, final, function(link)
		return link.Kind == "Walk" and link.Tag ~= "Bridge"
	end)
	check(path ~= nil, "monster cannot walk from lair to final chamber")
	-- Nodes must have sane coordinates.
	for _, node in ctx.Graph.Nodes do
		local p = node.Position
		if p.Y > 50 or p.Y < -800 or p.X ~= p.X then
			check(false, `node {node.Id} at odd position {p}`)
			break
		end
	end
	-- Recursion corridor periodicity: module translation is a voxel multiple.
	for _, f in ctx.Features do
		if f.Kind == "Recursion" then
			local step = f.Axis * f.ModuleLength
			check(step.X % 4 == 0 and step.Z % 4 == 0, "recursion module step not voxel aligned")
		end
	end
end

if failures > 0 then
	print(`{failures} check(s) failed`)
	process = require("@lune/process")
	process.exit(1)
end
print("planner checks passed")
