--!nocheck
-- Can the game be completed? Builds caves into the terrain emulator and walks
-- the story route from camp to the exit valley:
--   * walking links have a floor, headroom for a player, and no wall-like
--     steps between samples
--   * rope / climb / squeeze paths never pass through rock
--   * the ring's seal blocks the way on until it opens
--   * the recursion corridor's modules are identical (the loop is invisible)
--   lune run tests/traversal.spec.luau
local Harness = require("./Harness")
local WorldSim = require("./WorldSim")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Air = roblox.Enum.Material.Air
local Water = roblox.Enum.Material.Water

local env = Harness.load("build/Descent.rbxlx", {
	Setup = function(game)
		return WorldSim.install(game)
	end,
})
local Cave = "ServerScriptService.Server.Cave."
local CavePlanner = env.Require(env.Find(Cave .. "CavePlanner"))
local TerrainBuilder = env.Require(env.Find(Cave .. "TerrainBuilder"))
local SurfaceBuilder = env.Require(env.Find(Cave .. "SurfaceBuilder"))
local Dress = env.Require(env.Find(Cave .. "DressContext"))
local Populator = env.Require(env.Find(Cave .. "Populator"))
local NodeRefiner = env.Require(env.Find(Cave .. "NodeRefiner"))

local failures = 0
local function check(cond, message)
	if not cond then
		failures += 1
		print("  FAIL: " .. message)
	end
	return cond
end

local function open(p)
	local m = WorldSim.MaterialAt(p)
	return m == Air or m == Water
end

-- Floor under a point (searching down from `p`), or nil.
local function floorBelow(p, depth)
	local hit = WorldSim.Raycast(p, Vector3.new(0, -(depth or 12), 0), true)
	return hit and hit.Position
end

-- Walks a straight line between two nodes like a player would.
local function walkable(a, b)
	local delta = b - a
	local steps = math.max(1, math.ceil(delta.Magnitude / 2))
	local lastFloor = nil
	for i = 0, steps do
		local p = a:Lerp(b, i / steps)
		-- Probe from open air above the line (it may cross a mound).
		local start = p + Vector3.new(0, 4, 0)
		for _ = 1, 6 do
			if open(start) then
				break
			end
			start += Vector3.new(0, 2, 0)
		end
		local floor = floorBelow(start, 20)
		if not floor then
			local swim = false
			for h = 1, -8, -1 do
				if WorldSim.MaterialAt(p + Vector3.new(0, h, 0)) == Water then
					swim = true
					break
				end
			end
			if swim then
				-- Deep water: the player swims across.
				lastFloor = nil
				continue
			end
			return false, "no floor", p
		end
		-- A thin ledge low enough to step or jump onto counts as floor.
		-- (Real terrain is 4-stud voxels; the emulator's exact geometry keeps
		-- slivers the engine would smooth away, so this mirrors the player.)
		for _ = 1, 3 do
			local blockedAt = nil
			for h = 0.8, 5, 1.05 do
				if not open(floor + Vector3.new(0, h, 0)) then
					blockedAt = h
					break
				end
			end
			if not blockedAt then
				break
			end
			local top = nil
			for h = blockedAt, 4, 0.25 do
				if open(floor + Vector3.new(0, h, 0)) then
					top = h
					break
				end
			end
			if not top then
				local q = floor + Vector3.new(0, blockedAt, 0)
				return false, string.format("no headroom (%s at +%.1f)", WorldSim.MaterialAt(q).Name, blockedAt), floor
			end
			floor += Vector3.new(0, top, 0)
		end
		for h = 0.8, 5, 1.05 do
			if not open(floor + Vector3.new(0, h, 0)) then
				return false, "no headroom above ledge", floor
			end
		end
		-- Steps up to the player's jump height are fine.
		if lastFloor and floor.Y - lastFloor.Y > 4 then
			return false, string.format("step of %.1f", floor.Y - lastFloor.Y), floor
		end
		lastFloor = floor
	end
	return true
end

local function run(seed)
	WorldSim.Reset()
	local workspace = env.Game:FindFirstChildOfClass("Workspace")
	local caveFolder = workspace:FindFirstChild("Cave")
	if caveFolder then
		caveFolder:Destroy()
	end
	local plan = CavePlanner.Plan(seed)
	SurfaceBuilder.Terrain(plan)
	TerrainBuilder.Build(plan.Ops)
	local ctx = Dress.new(plan)
	SurfaceBuilder.Dress(ctx)
	Populator.Run(ctx)
	NodeRefiner.Refine(plan.Graph)
	local graph = plan.Graph

	-- 1. The route exists in the graph (with the ring seal open).
	local camp = plan.Anchors.SurfaceCamp.Node
	local valley = plan.Anchors.ExitValley.Node
	local path = graph:FindPath(camp, valley, function(link)
		return link.Tag ~= "Bridge"
	end)
	if not check(path ~= nil, `seed {seed}: no route from camp to exit`) then
		return
	end

	-- The way on out of the ring is sealed until the loop is walked; the
	-- route check is about the cave after that has happened.
	local seal = ctx.Results.RingSeal
	if check(seal ~= nil, `seed {seed}: no ring seal`) then
		check(not open(seal.CFrame.Position), `seed {seed}: ring seal does not block`)
		workspace.Terrain:FillBlock(seal.CFrame, seal.Size, Air)
		check(open(seal.CFrame.Position), `seed {seed}: ring seal does not open`)
	end

	-- 2. Each walking link along the route is physically walkable.
	local walks, bad = 0, 0
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local kind = "Walk"
		local tag = nil
		for _, link in a.Links do
			if link.To == b.Id then
				kind = link.Kind
				tag = link.Tag
			end
		end
		if kind == "Walk" and tag ~= "Surface" then
			walks += 1
			local ok, why, where = walkable(a.Position, b.Position)
			if not ok then
				bad += 1
				print(string.format("    blocked %s->%s (%s, %s): %s at (%.0f, %.0f, %.0f)", a.Id, b.Id, a.Zone, b.Zone, why, where.X, where.Y, where.Z))
			end
		end
	end
	check(bad == 0, `seed {seed}: {bad}/{walks} walking links on the route are blocked`)

	-- 3. Scripted traversals pass through open space.
	for _, traversal in plan.Traversals do
		local points = traversal.Path
		local blocked = 0
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			local steps = math.max(1, math.ceil((b - a).Magnitude))
			for k = 0, steps do
				if not open(a:Lerp(b, k / steps)) then
					blocked += 1
				end
			end
		end
		check(blocked == 0, `seed {seed}: traversal {traversal.Id} passes through rock at {blocked} points`)
	end

	-- 5. Recursion modules are identical (sampled inside the periodic part).
	for _, f in plan.Features do
		if f.Kind == "Recursion" then
			local mismatches, samples = 0, 0
			local rng = env.Random.new(seed)
			for _ = 1, 400 do
				local along = rng:NextNumber(f.ModuleLength * 1, f.ModuleLength * (f.Modules - 2))
				local lateral = rng:NextNumber(-f.Radius - 6, f.Radius + 6)
				local height = rng:NextNumber(-6, 12)
				local p = f.Origin + f.Axis * along + f.Side * lateral + Vector3.new(0, height, 0)
				samples += 1
				if WorldSim.MaterialAt(p) ~= WorldSim.MaterialAt(p + f.Axis * f.ModuleLength) then
					mismatches += 1
				end
			end
			check(mismatches == 0, `seed {seed}: recursion modules differ at {mismatches}/{samples} sample points`)
		end
	end
	print(string.format("seed %d: route %d nodes, %d walking links ok, %d traversals checked", seed, #path, walks - bad, #plan.Traversals))
end

for _, seed in { 42, 1337, 777777 } do
	run(seed)
end

if failures > 0 then
	print(`{failures} check(s) failed`)
	require("@lune/process").exit(1)
end
print("traversal checks passed")
