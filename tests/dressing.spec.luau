--!nocheck
-- Builds a full cave into the emulated terrain and runs the real surface,
-- populator and room dressers over it, then checks the results make sense:
-- story lore has somewhere to go, loot and hiding spots exist, the ring has
-- its landmark and seal, and placed objects actually rest on floors.
--   lune run tests/dressing.spec.luau
local Harness = require("./Harness")
local WorldSim = require("./WorldSim")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local sim
local env = Harness.load("build/Descent.rbxlx", {
	Setup = function(game)
		sim = WorldSim.install(game)
		return sim
	end,
})

local Cave = "ServerScriptService.Server.Cave."
local CavePlanner = env.Require(env.Find(Cave .. "CavePlanner"))
local TerrainBuilder = env.Require(env.Find(Cave .. "TerrainBuilder"))
local SurfaceBuilder = env.Require(env.Find(Cave .. "SurfaceBuilder"))
local Dress = env.Require(env.Find(Cave .. "DressContext"))
local Populator = env.Require(env.Find(Cave .. "Populator"))
local NodeRefiner = env.Require(env.Find(Cave .. "NodeRefiner"))
local LoreData = env.Require(env.Find("ReplicatedStorage.Shared.Config.LoreData"))
local LorePlacement = env.Require(env.Find(Cave .. "LorePlacement"))

local failures = 0
local function check(cond, message)
	if not cond then
		failures += 1
		print("  FAIL: " .. message)
	end
end

local function run(seed)
WorldSim.Reset()
local caveFolder = env.Game:FindFirstChildOfClass("Workspace"):FindFirstChild("Cave")
if caveFolder then
	caveFolder:Destroy()
end
local t0 = os.clock()
local plan = CavePlanner.Plan(seed)
SurfaceBuilder.Terrain(plan)
TerrainBuilder.Build(plan.Ops)
local t1 = os.clock()
local ctx = Dress.new(plan)
SurfaceBuilder.Dress(ctx)
Populator.Run(ctx)
NodeRefiner.Refine(plan.Graph)
local t2 = os.clock()
local results = ctx.Results
print(string.format("seed %d: %d terrain ops; build %.1fs, dress %.1fs", seed, WorldSim.OpCount(), t1 - t0, t2 - t1))
print(string.format("  lore slots %d, loot %d, hiding %d, rockfall %d, bridges %d, evidence %d",
	#results.LoreSlots, #results.LootSpots, #results.HidingSpots, #results.RockfallSpots, #results.Bridges, results.EvidenceCount))

-- Every anchored lore entry has a slot at its anchor.
local needed, have = {}, {}
for _, entry in LoreData.Entries do
	if entry.Anchor then
		needed[entry.Anchor] = (needed[entry.Anchor] or 0) + 1
	end
end
local tagged = {}
for _, slot in results.LoreSlots do
	if slot.Anchor then
		have[slot.Anchor] = (have[slot.Anchor] or 0) + 1
	end
	if slot.Tag then
		tagged[slot.Tag] = true
	end
end
for anchor, count in needed do
	check((have[anchor] or 0) >= count, `{anchor}: {have[anchor] or 0} lore slots for {count} anchored entries`)
end
check(tagged.NewestCamp, "no NewestCamp slot for the player's own journal")
check(results.Landmarks.RingSkeleton ~= nil, "ring landmark missing")
check(results.RingSeal ~= nil, "ring seal missing")
check(#results.LootSpots >= 25, "too few loot spots")
check(#results.HidingSpots >= 15, "too few hiding spots")

-- Lore placement: every story entry lands, your journal in the newest camp.
local placements, warnings = LorePlacement.Assign(LoreData.Entries, results.LoreSlots, env.Random.new(seed))
local placedIds = {}
for _, p in placements do
	placedIds[p.Entry.Id] = p.Slot
end
for _, entry in LoreData.Entries do
	if entry.Anchor or entry.Hidden then
		check(placedIds[entry.Id] ~= nil, `story lore '{entry.Id}' not placed`)
	end
end
check(placedIds.final_current ~= nil and placedIds.final_current.Tag == "NewestCamp", "Expedition Five journal not in the newest camp")
check(#warnings == 0, "lore warnings: " .. table.concat(warnings, "; "))
local missing = {}
for _, entry in LoreData.Entries do
	if not placedIds[entry.Id] then
		table.insert(missing, entry.Id .. "[" .. table.concat(entry.Zones or {}, "/") .. "]")
	end
end
local free = {}
for _, slot in results.LoreSlots do
	if not slot.Anchor then
		free[slot.Zone] = (free[slot.Zone] or 0) + 1
	end
end
local freeList = {}
for zone, n in free do
	table.insert(freeList, zone .. "=" .. n)
end
print(`  lore placed {#placements}/{#LoreData.Entries}; unanchored slots {table.concat(freeList, " ")}`)
check(#placements == #LoreData.Entries, "some lore left unplaced")
if #missing > 0 then
	print("  not placed: " .. table.concat(missing, ", "))
end

-- Floor sanity: slots and loot spots sit on rock with headroom above.
local function grounded(p)
	local below = WorldSim.MaterialAt(p - Vector3.new(0, 0.8, 0))
	local above = WorldSim.MaterialAt(p + Vector3.new(0, 2.5, 0))
	return below ~= roblox.Enum.Material.Air and above == roblox.Enum.Material.Air
end
local badLore, badLoot = 0, 0
for _, slot in results.LoreSlots do
	if not slot.OnProp and not grounded(slot.CFrame.Position) then
		badLore += 1
	end
end
for _, spot in results.LootSpots do
	if not grounded(spot.Position) then
		badLoot += 1
	end
end
print(`  ungrounded: lore {badLore}/{#results.LoreSlots}, loot {badLoot}/{#results.LootSpots}`)
check(badLore <= math.max(2, #results.LoreSlots * 0.1), "too many lore slots not resting on a floor")
check(badLoot <= math.max(3, #results.LootSpots * 0.15), "too many loot spots not resting on a floor")

-- Graph nodes should be in open air (the monster walks them).
local buried = 0
for _, node in plan.Graph.Nodes do
	local m = WorldSim.MaterialAt(node.Position + Vector3.new(0, 3, 0))
	if m ~= roblox.Enum.Material.Air and m ~= roblox.Enum.Material.Water then
		buried += 1
	end
end
print(`  nodes buried in rock: {buried}/{#plan.Graph.Nodes}`)
check(buried <= math.max(2, #plan.Graph.Nodes * 0.01), "too many navigation nodes buried in rock")

end

for _, seed in { 42, 1337, 777777, 2024, 9 } do
	run(seed)
end

if failures > 0 then
	print(`{failures} check(s) failed`)
	require("@lune/process").exit(1)
end
print("dressing checks passed")
