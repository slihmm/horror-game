--!strict
-- The Horror Director.
--
-- Each player has a tension value and a pacing phase that cycles
-- Calm -> Unease -> Build -> Peak -> Relief. Events are rare: on most ticks
-- nothing happens, some Build phases are deliberately dry, and a minimum gap
-- separates events. When something does happen, the director picks an
-- event that fits the player's situation: where they are, how long they've
-- been down, how tense they already are, whether they are alone, what the
-- monster is doing, and what has happened recently.
--
-- The server decides *what* and *where*; most events are performed only on
-- that player's client, so teammates never see the same thing. That is the
-- point: nobody can confirm what anybody else saw.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local HorrorConfig = require(Shared.Config.HorrorConfig)
local SoundLibrary = require(Shared.Config.SoundLibrary)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local CaveLayout = require(Shared.Config.CaveLayout)
local Weighted = require(Shared.Utility.Weighted)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local ExpeditionService = require(Services.ExpeditionService)
local HazardService = require(Services.HazardService)
local HeadlampService = require(Services.HeadlampService)
local MonsterService = require(Services.MonsterService)
local TraversalService = require(Services.TraversalService)
local CaveGraph = require(ServerScriptService.Server.Cave.CaveGraph)

type Node = CaveGraph.Node
type EventDef = HorrorConfig.EventDef

type PlayerState = {
	Tension: number,
	Phase: string,
	PhaseEnds: number,
	Dry: boolean,
	LastEvent: number,
	Cooldowns: { [string]: number },
	Path: { Vector3 },
	PathTimes: { number },
	CrowdShown: boolean,
}

type Executor = (PlayerState, Player, Vector3) -> { [string]: any }?

local HorrorDirector = {}
HorrorDirector.__index = HorrorDirector

type State = {
	_players: { [Player]: PlayerState },
	_rng: Random,
	_executors: { [string]: Executor },
}
export type HorrorDirector = typeof(setmetatable({} :: State, HorrorDirector))

local function soundAvailable(name: string): boolean
	local spec = SoundLibrary[name]
	return spec ~= nil and ((spec.Id ~= nil and spec.Id ~= "") or spec.Fallback ~= nil)
end

local function underground(player: Player): boolean
	local track = CaveService:GetTrack(player)
	return track ~= nil and ZoneConfig.Get(track.Zone).Underground
end

-- Nearest other underground player, and their distance.
local function nearestTeammate(player: Player, position: Vector3): (Player?, number)
	local best: Player? = nil
	local bestDist = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player and underground(other) then
			local track = CaveService:GetTrack(other)
			if track then
				local d = (track.Position - position).Magnitude
				if d < bestDist then
					best = other
					bestDist = d
				end
			end
		end
	end
	return best, bestDist
end

function HorrorDirector.Start(self: HorrorDirector)
	CaveService:WaitUntilReady()
	self:_registerExecutors()
	Players.PlayerRemoving:Connect(function(player: Player)
		self._players[player] = nil
	end)
	ExpeditionService.RunStarted:Connect(function(player: Player)
		self:_reset(player)
	end)
	ExpeditionService.StoryBeat:Connect(function(player: Player, beat: string)
		self:_onStoryBeat(player, beat)
	end)
	MonsterService.ChaseStarted:Connect(function(player: Player)
		local state = self._players[player]
		if state then
			state.Tension = 1
			self:_setPhase(state, "Peak")
		end
	end)
	MonsterService.ChaseEnded:Connect(function(player: Player)
		local state = self._players[player]
		if state and HorrorConfig.PostChaseRelief then
			-- Temporary safety: the cave lets them breathe.
			self:_setPhase(state, "Relief")
		end
	end)
	-- Path recording runs faster than the director tick.
	task.spawn(function()
		while true do
			task.wait(HorrorConfig.PathRecordInterval)
			self:_recordPaths()
		end
	end)
	while true do
		task.wait(HorrorConfig.TickInterval)
		self:_tick()
	end
end

function HorrorDirector._state(self: HorrorDirector, player: Player): PlayerState
	local existing = self._players[player]
	if existing then
		return existing
	end
	do
		local state: PlayerState = {
			Tension = 0,
			Phase = "Calm",
			PhaseEnds = 0,
			Dry = false,
			LastEvent = os.clock(),
			Cooldowns = {},
			Path = {},
			PathTimes = {},
			CrowdShown = false,
		}
		self._players[player] = state
		self:_setPhase(state, "Calm")
		return state
	end
end

function HorrorDirector._reset(self: HorrorDirector, player: Player)
	local state = self:_state(player)
	state.Tension = 0
	state.CrowdShown = false
	self:_setPhase(state, "Calm")
end

function HorrorDirector._setPhase(self: HorrorDirector, state: PlayerState, phase: string)
	local def = HorrorConfig.Phases[phase]
	state.Phase = phase
	state.PhaseEnds = os.clock() + self._rng:NextNumber(def.Duration.Min, def.Duration.Max)
	state.Dry = phase == "Build" and self._rng:NextNumber() < HorrorConfig.DryPhaseChance
end

function HorrorDirector._recordPaths(self: HorrorDirector)
	for _, player in Players:GetPlayers() do
		if underground(player) then
			local track = CaveService:GetTrack(player)
			if track then
				local state = self:_state(player)
				table.insert(state.Path, track.Position)
				table.insert(state.PathTimes, os.clock())
				if #state.Path > HorrorConfig.PathRecordLength then
					table.remove(state.Path, 1)
					table.remove(state.PathTimes, 1)
				end
			end
		end
	end
end

function HorrorDirector._tick(self: HorrorDirector)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if not underground(player) or not ExpeditionService:IsUnderground(player) then
			continue
		end
		local track = CaveService:GetTrack(player)
		if not track then
			continue
		end
		local state = self:_state(player)
		state.Tension = math.max(0, state.Tension - HorrorConfig.TensionDecay * HorrorConfig.TickInterval)
		if now >= state.PhaseEnds then
			self:_setPhase(state, HorrorConfig.Phases[state.Phase].Next)
		end
		local phase = HorrorConfig.Phases[state.Phase]
		if phase.EventChance <= 0 or state.Dry or now - state.LastEvent < HorrorConfig.MinGap then
			continue
		end
		local zone = ZoneConfig.Get(track.Zone)
		-- Deeper and longer underground = slightly more often.
		local run = ExpeditionService:GetRun(player)
		local minutes = if run then (now - run.StartedAt) / 60 else 0
		local chance = phase.EventChance * (0.35 + zone.Intensity) * (1 + math.min(minutes / 60, 0.5))
		if self._rng:NextNumber() < chance then
			self:_fireEvent(player, state, track.Position, track.Zone)
		end
	end
end

function HorrorDirector._eligible(self: HorrorDirector, player: Player, state: PlayerState, position: Vector3, zoneId: string): { string }
	local zone = ZoneConfig.Get(zoneId)
	local now = os.clock()
	local _, teammateDistance = nearestTeammate(player, position)
	local alone = teammateDistance > HorrorConfig.AloneDistance
	local hasTeammate = teammateDistance < math.huge
	local monsterState = MonsterService:GetState()
	local traversing = TraversalService:IsTraversing(player)
	local result = {}
	for name, def in HorrorConfig.Events do
		if not self._executors[name] then
			continue
		end
		if now < (state.Cooldowns[name] or 0) then
			continue
		end
		if state.Tension < def.Tension.Min or state.Tension > def.Tension.Max then
			continue
		end
		if def.MinOrder and zone.Order < def.MinOrder then
			continue
		end
		if def.MaxOrder and zone.Order > def.MaxOrder then
			continue
		end
		if not table.find(def.Phases, state.Phase) then
			continue
		end
		if def.RequiresAlone and not alone then
			continue
		end
		if def.RequiresTeammate and not hasTeammate then
			continue
		end
		if def.BlockedMonsterStates and table.find(def.BlockedMonsterStates, monsterState) then
			continue
		end
		if def.RequiresSound and not soundAvailable(def.RequiresSound) then
			continue
		end
		if traversing and (name == "ShadowBehind" or name == "EchoWalker" or name == "ObjectShift") then
			continue
		end
		table.insert(result, name)
	end
	return result
end

function HorrorDirector._fireEvent(self: HorrorDirector, player: Player, state: PlayerState, position: Vector3, zoneId: string)
	local eligible = self:_eligible(player, state, position, zoneId)
	local name = Weighted.pick(eligible, function(n: string)
		return HorrorConfig.Events[n].Weight
	end, self._rng)
	if name then
		self:Trigger(player, name, true)
	end
end

-- Runs a named event for a player. `count` charges cooldown and tension.
function HorrorDirector.Trigger(self: HorrorDirector, player: Player, name: string, count: boolean?): boolean
	local executor = self._executors[name]
	local track = CaveService:GetTrack(player)
	if not executor or not track then
		return false
	end
	local state = self:_state(player)
	local params = executor(state, player, track.Position)
	if params == nil then
		return false
	end
	-- Executors that act purely in the world return { __send = false }.
	local send = params.__send ~= false
	params.__send = nil
	if send then
		Net.Event("HorrorEvent"):FireClient(player, name, params)
	end
	if count ~= false then
		local def = HorrorConfig.Events[name]
		if def then
			state.Cooldowns[name] = os.clock() + def.Cooldown
			state.Tension = math.clamp(state.Tension + def.Cost, 0, 1)
		end
		state.LastEvent = os.clock()
	end
	return true
end

-- Story beats ------------------------------------------------------------------------

function HorrorDirector._onStoryBeat(self: HorrorDirector, player: Player, beat: string)
	if beat == "DeepHall" then
		-- The first time they get deep: they hear it before anything else.
		task.delay(self._rng:NextNumber(18, 35), function()
			if player.Parent and underground(player) then
				self:Trigger(player, "DistantMonster", false)
			end
		end)
	elseif beat == "FinalChamber" then
		local state = self:_state(player)
		if not state.CrowdShown then
			state.CrowdShown = true
			self:Trigger(player, "Crowd", false)
		end
	elseif beat == "Descended" then
		-- Calm after the rope: nothing for a good while.
		local state = self:_state(player)
		self:_setPhase(state, "Calm")
	end
end

-- Executors -----------------------------------------------------------------------------

function HorrorDirector._registerExecutors(self: HorrorDirector)
	local rng = self._rng
	local ex = self._executors

	local function nodeAround(position: Vector3, minDist: number, maxDist: number, filter: ((Node) -> boolean)?): Node?
		return CaveService:RandomNodeAround(position, minDist, maxDist, rng, filter)
	end
	local function candidates(position: Vector3, minDist: number, maxDist: number, count: number): { Vector3 }
		local list = {}
		for _ = 1, count * 3 do
			local node = nodeAround(position, minDist, maxDist, function(n: Node)
				return not n.Tags.Surface
			end)
			if node then
				table.insert(list, node.Position)
				if #list >= count then
					break
				end
			end
		end
		return list
	end

	ex.DistantFootsteps = function(_state, _player, position)
		local node = nodeAround(position, 50, 110)
		if not node then
			return nil
		end
		return { Position = node.Position, Count = rng:NextInteger(5, 9) }
	end

	ex.FootstepsBehind = function()
		return { Count = rng:NextInteger(3, 6), Distance = rng:NextNumber(8, 14) }
	end

	ex.ShadowSighting = function(_state, _player, position)
		local list = candidates(position, 38, 95, 8)
		if #list == 0 then
			return nil
		end
		return { Candidates = list, Duration = rng:NextNumber(6, 14) }
	end

	ex.ShadowBehind = function()
		return { Distance = rng:NextNumber(8, 13), Duration = rng:NextNumber(4, 8) }
	end

	-- A figure retracing a path someone (maybe you) walked earlier.
	ex.EchoWalker = function(_state, player, position)
		local now = os.clock()
		local options = {}
		for _, other in Players:GetPlayers() do
			local otherState = self._players[other]
			if otherState then
				local path, times = otherState.Path, otherState.PathTimes
				for i = 1, #path - 14, 4 do
					if now - times[i] > 120 then
						local d = (path[i] - position).Magnitude
						if d > 35 and d < 90 then
							table.insert(options, { Path = path, Start = i, Own = other == player })
						end
					end
				end
			end
		end
		if #options == 0 then
			return nil
		end
		local pick = options[rng:NextInteger(1, #options)]
		local points = {}
		for i = pick.Start, math.min(#pick.Path, pick.Start + 16) do
			table.insert(points, pick.Path[i])
		end
		return { Path = points, Speed = rng:NextNumber(5.5, 8), Own = pick.Own }
	end

	ex.BeamGlint = function()
		return { Distance = rng:NextNumber(28, 50), Duration = rng:NextNumber(1, 2.2) }
	end

	ex.RockFall = function(_state, _player, position)
		local node = nodeAround(position, 25, 60)
		if not node then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { Workspace.Terrain }
		local hit = Workspace:Raycast(node.Position + Vector3.yAxis * 2, Vector3.yAxis * 40, params)
		if not hit then
			return nil
		end
		task.spawn(function()
			HazardService:Rockfall(hit.Position - Vector3.yAxis * 1.5, node.Position, 0.45)
		end)
		return { __send = false }
	end

	ex.LightFlicker = function()
		return { Duration = rng:NextNumber(1.2, 3), Severity = rng:NextNumber(0.6, 1) }
	end

	ex.TemporaryDarkness = function(_state, player)
		local seconds = rng:NextNumber(2.5, 4.5)
		HeadlampService:SetForcedOff(player, seconds)
		return { Duration = seconds }
	end

	ex.DistantScream = function()
		return { Distance = rng:NextNumber(140, 220) }
	end

	ex.ObjectShift = function()
		return { Radius = 26 }
	end

	ex.WaterDisturbance = function(_state, _player, position)
		local node = nodeAround(position, 12, 45, function(n: Node)
			return n.Tags.Water == true
		end)
		if not node then
			return nil
		end
		return { Position = node.Position }
	end

	ex.DistantMonster = function(_state, _player, position)
		-- Heard from the direction of the deep cave, far away.
		local plan = CaveService.Plan
		local lair = plan and plan.Anchors[CaveLayout.LairAnchor]
		local target = if lair then lair.Position else position + Vector3.new(0, -100, 150)
		local dir = target - position
		dir = if dir.Magnitude > 1 then dir.Unit else Vector3.zAxis
		return { Position = position + dir * rng:NextNumber(170, 240), Steps = rng:NextInteger(3, 6) }
	end

	ex.Silence = function()
		return { Duration = rng:NextNumber(18, 34) }
	end

	ex.Knocking = function()
		return { Count = 3 }
	end

	ex.Whisper = function()
		return {}
	end

	-- A teammate's voice from the wrong direction.
	local function awayFromTeammate(player: Player, position: Vector3): Vector3?
		local teammate = nearestTeammate(player, position)
		local teammateTrack = teammate and CaveService:GetTrack(teammate)
		local towardTeammate = if teammateTrack then (teammateTrack.Position - position) else Vector3.zero
		local flat = Vector3.new(towardTeammate.X, 0, towardTeammate.Z)
		for _ = 1, 10 do
			local node = nodeAround(position, 22, 55)
			if node then
				local d = node.Position - position
				local flatD = Vector3.new(d.X, 0, d.Z)
				if flat.Magnitude < 1 or flatD.Unit:Dot(flat.Unit) < -0.1 then
					return node.Position
				end
			end
		end
		return nil
	end

	ex.MimicVoice = function(_state, player, position)
		local at = awayFromTeammate(player, position)
		if not at then
			return nil
		end
		local lines = { "Mimic_OverHere", "Mimic_Wait", "Mimic_Name" }
		local available = {}
		for _, line in lines do
			if soundAvailable(line) then
				table.insert(available, line)
			end
		end
		if #available == 0 then
			return nil
		end
		return { Position = at, Sound = available[rng:NextInteger(1, #available)] }
	end

	ex.MimicFootsteps = function(_state, player, position)
		local at = awayFromTeammate(player, position)
		if not at then
			return nil
		end
		return { Position = at, Count = rng:NextInteger(6, 10) }
	end

	-- The Gathering: the bottom is full of people.
	ex.Crowd = function()
		local plan = CaveService.Plan
		local anchor = plan and plan.Anchors.FinalChamber
		if not anchor then
			return nil
		end
		local positions = {}
		for _ = 1, 34 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(anchor.Radius * 0.2, anchor.Radius * 0.75)
			table.insert(positions, anchor.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist))
		end
		return { Positions = positions, Center = anchor.Position, Radius = anchor.Radius }
	end
end

local instance: HorrorDirector = setmetatable({
	_players = {},
	_rng = Random.new(),
	_executors = {},
} :: State, HorrorDirector)

return instance
