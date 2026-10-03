--!nocheck
-- Simulates the Lamplighter's brain on a generated cave with a scripted
-- player, checking that perception drives the expected state progression.
--   lune run tests/monster.spec.luau
local Harness = require("./Harness")
local env = Harness.load("build/Descent.rbxlx")
local Random = env.Random
local Vector3 = require("@lune/roblox").Vector3

local CavePlanner = env.Require(env.Find("ServerScriptService.Server.Cave.CavePlanner"))
local Brain = env.Require(env.Find("ServerScriptService.Server.Monster.MonsterBrain"))

local failures = 0
local function check(cond, message)
	if not cond then
		failures += 1
		print("  FAIL: " .. message)
	end
end

local function simulate(name, seed, scenario)
	local plan = CavePlanner.Plan(seed)
	local graph = plan.Graph
	local camp = plan.Anchors.Camp
	local lair = plan.Anchors.Hollow
	local world = {
		LineOfSight = function(a, b)
			return (a - b).Magnitude < scenario.SightDistance
		end,
		HidingSpots = function()
			return scenario.Spots or {}
		end,
	}
	local brain = Brain.new(graph, world, lair.Position, Random.new(seed))
	brain:Wake(0)
	brain.Shy = scenario.Shy or false
	local bodyPos = lair.Position
	local path, index = nil, 1
	local arrived = true
	local visited, attacks = {}, 0
	-- Hidden players sit in a crevice off the walking line (as alcoves are).
	local offset = if scenario.Hidden then Vector3.new(camp.Radius * 0.9, 3, 0) else Vector3.new(0, 3, 0)
	local player = { Id = "P1", Position = camp.Position + offset, Velocity = Vector3.zero,
		Crouched = scenario.Crouched or false, Hidden = scenario.Hidden or false, HidingSpot = nil,
		LampOn = scenario.Lamp ~= false, BeamDirection = Vector3.new(1, 0, 0) }
	local now = 0
	for _ = 1, scenario.Ticks do
		now += 0.2
		local noises = {}
		if scenario.Noisy and math.floor(now * 5) % 3 == 0 then
			table.insert(noises, { Position = player.Position, Loudness = 0.85, Source = "P1" })
		end
		brain.Position = bodyPos
		local cmd = brain:Think({ player }, noises, 0.2, now, arrived)
		visited[brain.State] = true
		if cmd.Attack then
			attacks += 1
		end
		-- crude body: follow path
		if cmd.Path ~= path then
			path, index = cmd.Path, 1
			arrived = path == nil
		end
		if path then
			local budget = cmd.Speed * 0.2
			while budget > 0 and index <= #path do
				local d = path[index] - bodyPos
				if d.Magnitude <= budget then
					bodyPos = path[index]
					budget -= d.Magnitude
					index += 1
				else
					bodyPos += d.Unit * budget
					budget = 0
				end
				if d.Magnitude > 0.01 then
					brain.Facing = Vector3.new(d.X, 0, d.Z).Unit
				end
			end
			if index > #path then
				arrived = true
			end
		end
		assert(bodyPos.X == bodyPos.X, "NaN position")
	end
	local states = {}
	for s in visited do
		table.insert(states, s)
	end
	table.sort(states)
	print(string.format("%s: states {%s}, attacks %d, final distance to player %.0f", name, table.concat(states, ", "), attacks, (bodyPos - player.Position).Magnitude))
	return visited, attacks
end

-- A noisy, lit player at the camp is eventually found and attacked.
local visited, attacks = simulate("noisy player", 42, { Ticks = 1500, Noisy = true, SightDistance = 70 })
check(visited.Patrolling, "never patrolled")
check(visited.Investigating or visited.Tracking, "never investigated or tracked a noisy player")
check(visited.Chasing, "never chased a noisy, lit player")
check(attacks > 0, "never attacked")

-- A silent, dark, hidden, crouched player is not chased.
local visited2 = simulate("hidden player", 42, { Ticks = 1500, Noisy = false, Lamp = false, Hidden = true, Crouched = true, SightDistance = 70 })
check(not visited2.Chasing, "chased a hidden, silent, dark player")

-- While shy, it never chases.
local visited3 = simulate("shy monster", 7, { Ticks = 1200, Noisy = true, SightDistance = 70, Shy = true })
check(not visited3.Chasing, "chased while shy")

if failures > 0 then
	print(`{failures} check(s) failed`)
	require("@lune/process").exit(1)
end
print("monster checks passed")
