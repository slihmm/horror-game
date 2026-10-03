--!strict
-- The Lamplighter's mind: perception and a state machine.
--
-- It does not know where players are. It knows what it has seen (limited by
-- distance, field of view, line of sight, darkness and whether a lamp is
-- shining at it) and what it has heard (noises are vague, and vaguer with
-- distance and rock in between). Per-player awareness rises with stimuli
-- and decays without them; states follow from awareness.
--
-- The world is injected (line of sight, hiding spots, the graph), so this
-- module has no engine dependencies beyond datatypes and can be exercised
-- offline in tests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local CaveGraph = require(ServerScriptService.Server.Cave.CaveGraph)

type Node = CaveGraph.Node
type Graph = CaveGraph.CaveGraph

export type PlayerSnapshot = {
	Id: any,
	Position: Vector3, -- root part (about 3 studs above the floor)
	Velocity: Vector3,
	Crouched: boolean,
	Hidden: boolean,
	HidingSpot: CFrame?,
	LampOn: boolean,
	BeamDirection: Vector3?,
}

export type Noise = {
	Position: Vector3,
	Loudness: number,
	Source: any?,
}

export type World = {
	LineOfSight: (from: Vector3, to: Vector3) -> boolean,
	HidingSpots: () -> { CFrame },
}

export type Command = {
	-- Where to go: a list of floor points, or nil to stand still.
	Path: { Vector3 }?,
	Speed: number,
	Face: Vector3?,
	Attack: any?,
	Vocal: string?, -- "Roar" | "Growl" | "Breath" | nil
}

type Memory = {
	Awareness: number,
	LastSeen: Vector3?,
	LastSeenTime: number,
	LastHeard: Vector3?,
	LastHeardTime: number,
}

local Brain = {}
Brain.__index = Brain

type BrainState = {
	State: string,
	StateTime: number,
	Position: Vector3,
	Facing: Vector3,
	Target: any?,
	Goal: Vector3?,
	Memory: { [any]: Memory },
	Shy: boolean,
	ChaseStarted: number,
	ChaseCooldownUntil: number,
	LastAttack: number,
	RecoverUntil: number,
	SearchCenter: Vector3?,
	SearchUntil: number,
	PeekSpot: CFrame?,
	PeekUntil: number,
	PeekTarget: CFrame?,
	PatrolIdleUntil: number?,
	WaitUntil: number,
	Visited: { number },
	Home: Vector3,
	Graph: Graph,
	World: World,
	Rng: Random,
	_path: { Vector3 }?,
	_pathGoal: Vector3?,
	_lastPlan: number,
	_events: { { Kind: string, Player: any? } },
}
export type Brain = typeof(setmetatable({} :: BrainState, Brain))

local cfg = MonsterConfig

function Brain.new(graph: Graph, world: World, home: Vector3, rng: Random?): Brain
	local state: BrainState = {
		State = "Dormant",
		StateTime = 0,
		Position = home,
		Facing = Vector3.zAxis,
		Target = nil,
		Goal = nil,
		Memory = {},
		Shy = true,
		ChaseStarted = 0,
		ChaseCooldownUntil = 0,
		LastAttack = 0,
		RecoverUntil = 0,
		SearchCenter = nil,
		SearchUntil = 0,
		PeekSpot = nil,
		PeekUntil = 0,
		PeekTarget = nil,
		PatrolIdleUntil = nil,
		WaitUntil = 0,
		Visited = {},
		Home = home,
		Graph = graph,
		World = world,
		Rng = rng or Random.new(),
		_path = nil,
		_pathGoal = nil,
		_lastPlan = -math.huge,
		_events = {},
	}
	return setmetatable(state, Brain)
end

-- Events since the last call (state changes, chase start/end, kills...).
function Brain.DrainEvents(self: Brain): { { Kind: string, Player: any? } }
	local events = self._events
	self._events = {}
	return events
end

function Brain._emit(self: Brain, kind: string, player: any?)
	table.insert(self._events, { Kind = kind, Player = player })
end

function Brain.SetState(self: Brain, state: string, now: number)
	if self.State == state then
		return
	end
	local previous = self.State
	if previous == "Chasing" then
		self.ChaseCooldownUntil = now + cfg.Chase.Cooldown
		self:_emit("ChaseEnded", self.Target)
	end
	self.State = state
	self.StateTime = now
	self._path = nil
	self._pathGoal = nil
	if state == "Chasing" then
		self.ChaseStarted = now
		self:_emit("ChaseStarted", self.Target)
	end
	self:_emit("State", nil)
end

function Brain.Wake(self: Brain, now: number)
	if self.State == "Dormant" then
		self:SetState("Patrolling", now)
	end
end

function Brain.Sleep(self: Brain, now: number)
	self.Memory = {}
	self.Target = nil
	self:SetState("Dormant", now)
end

function Brain._memory(self: Brain, id: any): Memory
	local memory = self.Memory[id]
	if not memory then
		memory = { Awareness = 0, LastSeen = nil, LastSeenTime = -math.huge, LastHeard = nil, LastHeardTime = -math.huge }
		self.Memory[id] = memory
	end
	return memory
end

-- Perception ------------------------------------------------------------------

function Brain._see(self: Brain, players: { PlayerSnapshot }, dt: number, now: number)
	local eye = self.Position + Vector3.new(0, 9.5, 0)
	local sight = cfg.Sight
	local halfFov = math.rad(sight.FieldOfView / 2)
	for _, p in players do
		local memory = self:_memory(p.Id)
		local head = p.Position + Vector3.yAxis * 1.5
		local offset = head - eye
		local distance = offset.Magnitude
		local direction = if distance > 0.01 then offset / distance else self.Facing
		local range = if p.LampOn then sight.HeadlampRange else sight.DarkRange
		if p.LampOn and distance > sight.Range then
			-- Beyond normal sight only the light itself gives them away: it
			-- has to be pointing roughly at the monster.
			local beam = p.BeamDirection
			if not beam or beam:Dot(-direction) < 0.75 then
				range = sight.Range
			end
		end
		if p.Crouched then
			range *= sight.CrouchMultiplier
		end
		if p.Hidden then
			range *= sight.HidingMultiplier
		end
		local inFov = math.acos(math.clamp(self.Facing:Dot(direction), -1, 1)) <= halfFov
		-- Someone tucked into a crevice is only found if it all but steps in.
		local touching = distance <= (if p.Hidden then sight.TouchRange * 0.45 else sight.TouchRange)
		if (touching or (distance <= range and inFov)) and self.World.LineOfSight(eye, head) then
			local closeness = 1 - math.clamp(distance / math.max(range, 1), 0, 1)
			memory.Awareness = math.min(1, memory.Awareness + cfg.Awareness.SightGain * (0.25 + closeness) * dt + (if touching then 1 else 0))
			memory.LastSeen = p.Position
			memory.LastSeenTime = now
		end
	end
end

function Brain._hear(self: Brain, noises: { Noise }, now: number)
	local hearing = cfg.Hearing
	local listening = self.State == "Listening" or self.State == "Ambushing"
	local ear = self.Position + Vector3.new(0, 8, 0)
	for _, noise in noises do
		local range = hearing.Range * noise.Loudness * (if listening then hearing.ListeningMultiplier else 1)
		local distance = (noise.Position - ear).Magnitude
		if distance > range then
			continue
		end
		if not self.World.LineOfSight(ear, noise.Position + Vector3.yAxis * 1.5) then
			range *= hearing.OccludedMultiplier
			if distance > range then
				continue
			end
		end
		local strength = 1 - distance / range
		-- Vague: the further away, the less precise the guess.
		local error = math.max(hearing.MinUncertainty, distance * hearing.Uncertainty) * (1 - strength * 0.5)
		local angle = self.Rng:NextNumber(0, math.pi * 2)
		local guess = noise.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * self.Rng:NextNumber(0, error)
		if noise.Source ~= nil then
			local memory = self:_memory(noise.Source)
			memory.Awareness = math.min(1, memory.Awareness + cfg.Awareness.NoiseGain * strength * noise.Loudness)
			memory.LastHeard = guess
			memory.LastHeardTime = now
		elseif strength > 0.35 and (self.State == "Patrolling" or self.State == "Listening") then
			-- A rockfall or a falling plank: worth a look.
			self.Goal = guess
			self:SetState("Investigating", now)
		end
	end
end

-- Most interesting player right now.
function Brain._focus(self: Brain): (any?, Memory?)
	local bestId, best = nil, nil
	for id, memory in self.Memory do
		if not best or memory.Awareness > best.Awareness then
			bestId, best = id, memory
		end
	end
	return bestId, best
end

-- Navigation ---------------------------------------------------------------------

local function canWalk(link: CaveGraph.Link, node: Node): boolean
	return link.Kind == "Walk" and link.Tag ~= "Bridge" and ZoneConfig.Get(node.Zone).Underground
end

-- Plans a path of floor points to a world position (throttled).
function Brain._planTo(self: Brain, goal: Vector3, now: number, force: boolean?): { Vector3 }?
	local current = self._pathGoal
	if not force and current and (current - goal).Magnitude < 4 and self._path then
		return self._path
	end
	if not force and now - self._lastPlan < cfg.ReplanInterval and self._path then
		return self._path
	end
	self._lastPlan = now
	local graph = self.Graph
	local from = graph:Nearest(self.Position, 60, function(n: Node)
		return ZoneConfig.Get(n.Zone).Underground
	end)
	local to = graph:Nearest(goal, 60, function(n: Node)
		return ZoneConfig.Get(n.Zone).Underground
	end)
	if not from or not to then
		return nil
	end
	local nodes = graph:FindPath(from, to, canWalk)
	if not nodes then
		return nil
	end
	local points = {}
	for _, node in nodes do
		table.insert(points, node.Position)
	end
	-- Final approach to the exact goal if it's in plain view of the last node.
	local last = points[#points]
	if (goal - last).Magnitude > 2 and self.World.LineOfSight(last + Vector3.yAxis * 3, goal + Vector3.yAxis * 1) then
		table.insert(points, goal)
	end
	self._path = points
	self._pathGoal = goal
	return points
end

function Brain._habitatNode(self: Brain, near: Vector3?, minDist: number, maxDist: number): Node?
	local graph = self.Graph
	local origin = near or self.Position
	local candidates = {}
	for _, node in graph:Within(origin, maxDist) do
		local zone = ZoneConfig.Get(node.Zone)
		if zone.MonsterHabitat and (node.Position - origin).Magnitude >= minDist and not table.find(self.Visited, node.Id) and not node.Tags.Recursion then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[self.Rng:NextInteger(1, #candidates)]
end

function Brain._remember(self: Brain, node: Node)
	table.insert(self.Visited, node.Id)
	while #self.Visited > cfg.Patrol.MemorySize do
		table.remove(self.Visited, 1)
	end
end

-- Decision ------------------------------------------------------------------------

-- One think step. `arrived` = the body reached the end of its current path.
function Brain.Think(self: Brain, players: { PlayerSnapshot }, noises: { Noise }, dt: number, now: number, arrived: boolean): Command
	if self.State == "Dormant" then
		return { Path = nil, Speed = 0 }
	end
	-- Decay, then perceive.
	for _, memory in self.Memory do
		memory.Awareness = math.max(0, memory.Awareness - cfg.Awareness.Decay * dt)
	end
	local present: { [any]: PlayerSnapshot } = {}
	for _, p in players do
		present[p.Id] = p
	end
	for id in self.Memory do
		if not present[id] then
			self.Memory[id] = nil
		end
	end
	self:_see(players, dt, now)
	self:_hear(noises, now)

	local thresholds = cfg.Awareness
	local focusId, focus = self:_focus()
	local seenRecently = focus ~= nil and now - focus.LastSeenTime < 0.6
	local state = self.State

	-- Global transitions driven by awareness.
	if focus and focusId ~= nil and state ~= "Chasing" then
		local canChase = now >= self.ChaseCooldownUntil or (focus.LastSeen ~= nil and (focus.LastSeen - self.Position).Magnitude < cfg.Sight.TouchRange * 1.5)
		if self.Shy then
			if seenRecently and focus.LastSeen and (focus.LastSeen - self.Position).Magnitude < cfg.Activation.ShyDistance and state ~= "Returning" then
				-- First encounters: it notices you, stops... and withdraws.
				self.Target = focusId
				self.WaitUntil = now + self.Rng:NextNumber(1.5, 3)
				self:SetState("Returning", now)
				return { Path = nil, Speed = 0, Face = (focus.LastSeen - self.Position), Vocal = "Growl" }
			end
		elseif focus.Awareness >= thresholds.ChaseThreshold and seenRecently and canChase then
			self.Target = focusId
			self:SetState("Chasing", now)
			return { Path = nil, Speed = 0, Face = (focus.LastSeen :: Vector3) - self.Position, Vocal = "Roar" }
		elseif focus.Awareness >= thresholds.TrackThreshold and state ~= "Tracking" and state ~= "Ambushing" then
			self.Target = focusId
			self:SetState("Tracking", now)
		elseif focus.Awareness >= thresholds.InvestigateThreshold and (self.State == "Patrolling" or self.State == "Listening" or self.State == "Returning") then
			self.Goal = focus.LastHeard or focus.LastSeen
			if self.Goal then
				self:SetState("Investigating", now)
			end
		end
	end

	state = self.State
	local speeds = cfg.Speeds

	if state == "Patrolling" then
		if arrived or not self._path then
			-- Pause where it arrived before choosing somewhere new.
			if self.PatrolIdleUntil == nil then
				self.PatrolIdleUntil = if arrived then now + self.Rng:NextNumber(cfg.Patrol.IdleTime.Min, cfg.Patrol.IdleTime.Max) else now
				if arrived and self.Rng:NextNumber() < cfg.Listen.ChancePerPatrolNode then
					self.PatrolIdleUntil = nil
					self:SetState("Listening", now)
					self.WaitUntil = now + self.Rng:NextNumber(cfg.Listen.Duration.Min, cfg.Listen.Duration.Max)
					return { Path = nil, Speed = 0, Vocal = "Breath" }
				end
			end
			if now < (self.PatrolIdleUntil :: number) then
				return { Path = nil, Speed = 0 }
			end
			self.PatrolIdleUntil = nil
			-- Choose somewhere new; sometimes drift toward where players are.
			local near: Vector3? = nil
			if self.Rng:NextNumber() < cfg.Patrol.DriftTowardPlayersChance and #players > 0 then
				near = players[self.Rng:NextInteger(1, #players)].Position
			end
			local node = self:_habitatNode(near, 30, 180) or self:_habitatNode(nil, 10, 260)
			if node then
				self:_remember(node)
				self:_planTo(node.Position, now, true)
			end
		end
		return { Path = self._path, Speed = speeds.Patrol }
	elseif state == "Listening" then
		if now >= self.WaitUntil then
			self:SetState("Patrolling", now)
		end
		-- Turn slowly while listening.
		local angle = math.sin(now * 0.7) * 0.8
		local face = CFrame.Angles(0, angle * dt, 0):VectorToWorldSpace(self.Facing)
		return { Path = nil, Speed = 0, Face = face }
	elseif state == "Investigating" then
		local goal = self.Goal
		if not goal then
			self:SetState("Patrolling", now)
			return { Path = nil, Speed = 0 }
		end
		local path = self:_planTo(goal, now)
		if arrived or not path or (self.Position - goal).Magnitude < 6 then
			self.SearchCenter = goal
			self.SearchUntil = now + self.Rng:NextNumber(cfg.Search.Duration.Min, cfg.Search.Duration.Max)
			self:SetState("Searching", now)
			return { Path = nil, Speed = 0, Vocal = "Breath" }
		end
		return { Path = path, Speed = speeds.Investigate }
	elseif state == "Tracking" then
		local memory = if self.Target ~= nil then self.Memory[self.Target] else nil
		if not memory or memory.Awareness < thresholds.InvestigateThreshold then
			self.SearchCenter = if memory then (memory.LastSeen or memory.LastHeard) else self.Position
			self.SearchUntil = now + self.Rng:NextNumber(cfg.Search.Duration.Min, cfg.Search.Duration.Max)
			self:SetState("Searching", now)
			return { Path = nil, Speed = 0 }
		end
		local remembered = if memory.LastSeenTime > memory.LastHeardTime then memory.LastSeen else memory.LastHeard
		if not remembered then
			return { Path = nil, Speed = 0 }
		end
		local goal = remembered - Vector3.yAxis * 3
		local path = self:_planTo(goal, now)
		if arrived and (self.Position - goal).Magnitude < 8 then
			self.SearchCenter = goal
			self.SearchUntil = now + self.Rng:NextNumber(cfg.Search.Duration.Min, cfg.Search.Duration.Max)
			self:SetState("Searching", now)
		end
		return { Path = path, Speed = speeds.Track }
	elseif state == "Chasing" then
		local target = self.Target
		local memory = if target ~= nil then self.Memory[target] else nil
		local snapshot = if target ~= nil then present[target] else nil
		if not memory or not snapshot then
			self:SetState("LostTarget", now)
			return { Path = nil, Speed = 0 }
		end
		local sinceSeen = now - memory.LastSeenTime
		if sinceSeen > cfg.Chase.LoseSightTime or now - self.ChaseStarted > cfg.Chase.MaxDuration or (snapshot.Hidden and sinceSeen > 0.5) then
			self.WaitUntil = now + self.Rng:NextNumber(3, 5)
			self:SetState("LostTarget", now)
			return { Path = nil, Speed = 0, Vocal = "Growl" }
		end
		if now < self.RecoverUntil then
			return { Path = nil, Speed = 0, Face = snapshot.Position - self.Position }
		end
		-- Strike.
		local toTarget = snapshot.Position - (self.Position + Vector3.yAxis * 3)
		toTarget = Vector3.new(toTarget.X, toTarget.Y * 0.5, toTarget.Z)
		if toTarget.Magnitude <= cfg.Chase.KillRange + 2 and sinceSeen < 0.3 and now - self.LastAttack > cfg.Chase.HitCooldown then
			self.LastAttack = now
			self.RecoverUntil = now + 1.4
			return { Path = nil, Speed = 0, Face = toTarget, Attack = target }
		end
		local floorOf = Vector3.yAxis * 3
		local goal = if sinceSeen < 0.3 then snapshot.Position - floorOf else (memory.LastSeen :: Vector3) - floorOf
		local path: { Vector3 }?
		if sinceSeen < 0.3 and self.World.LineOfSight(self.Position + Vector3.yAxis * 4, snapshot.Position) then
			path = { goal } -- straight at them
			self._path = path
		else
			path = self:_planTo(goal, now)
		end
		return { Path = path, Speed = speeds.Chase }
	elseif state == "LostTarget" then
		if now >= self.WaitUntil then
			local memory = if self.Target ~= nil then self.Memory[self.Target] else nil
			self.SearchCenter = if memory then (memory.LastSeen or memory.LastHeard) else self.Position
			self.SearchUntil = now + self.Rng:NextNumber(cfg.Search.Duration.Min, cfg.Search.Duration.Max)
			self:SetState("Searching", now)
		end
		local angle = math.sin(now * 1.3) * 1.2
		return { Path = nil, Speed = 0, Face = CFrame.Angles(0, angle * dt, 0):VectorToWorldSpace(self.Facing), Vocal = nil }
	elseif state == "Searching" then
		local center = self.SearchCenter or self.Position
		if now >= self.SearchUntil then
			if not self.Shy and self.Rng:NextNumber() < cfg.Ambush.ChanceAfterSearch then
				self.WaitUntil = now + self.Rng:NextNumber(cfg.Ambush.Duration.Min, cfg.Ambush.Duration.Max)
				self:SetState("Ambushing", now)
			else
				self:SetState("Returning", now)
			end
			return { Path = nil, Speed = 0 }
		end
		-- Peeking into a hiding spot.
		local peek = self.PeekSpot
		if peek then
			if now < self.PeekUntil then
				for _, p in players do
					if p.Hidden and p.HidingSpot and (p.HidingSpot.Position - peek.Position).Magnitude < 2 then
						local moving = Vector3.new(p.Velocity.X, 0, p.Velocity.Z).Magnitude > 1.2
						local chance = if moving then cfg.Search.FindMovingChance else cfg.Search.FindStillChance
						-- Rolled once per peek, scaled so it isn't per-tick.
						if self.Rng:NextNumber() < chance * dt / math.max(cfg.Search.PeekTime.Min, 0.5) then
							local memory = self:_memory(p.Id)
							memory.Awareness = 1
							memory.LastSeen = p.Position
							memory.LastSeenTime = now
						end
					end
				end
				return { Path = nil, Speed = 0, Face = peek.Position - self.Position }
			end
			self.PeekSpot = nil
		end
		if arrived and self.PeekTarget then
			-- Reached the spot it was heading for: look in.
			local spot = self.PeekTarget :: CFrame
			self.PeekTarget = nil
			self.PeekSpot = spot
			self.PeekUntil = now + self.Rng:NextNumber(cfg.Search.PeekTime.Min, cfg.Search.PeekTime.Max)
			return { Path = nil, Speed = 0, Face = spot.Position - self.Position, Vocal = "Breath" }
		end
		if arrived or not self._path then
			if self.Rng:NextNumber() < cfg.Search.CheckHidingChance then
				local spots = self.World.HidingSpots()
				local candidates = {}
				for _, spot in spots do
					if (spot.Position - center).Magnitude < cfg.Search.Radius then
						table.insert(candidates, spot)
					end
				end
				if #candidates > 0 then
					local spot = candidates[self.Rng:NextInteger(1, #candidates)]
					if (spot.Position - self.Position).Magnitude < 7 then
						self.PeekSpot = spot
						self.PeekUntil = now + self.Rng:NextNumber(cfg.Search.PeekTime.Min, cfg.Search.PeekTime.Max)
						return { Path = nil, Speed = 0, Face = spot.Position - self.Position, Vocal = "Breath" }
					end
					-- Walk to just outside the spot, then peek on arrival.
					local approach = spot.Position + spot.LookVector * 4 - Vector3.yAxis * 2.5
					self.PeekTarget = spot
					self:_planTo(approach, now, true)
					return { Path = self._path, Speed = speeds.Search }
				end
			end
			local node = self:_habitatNode(center, 6, cfg.Search.Radius) or self.Graph:Nearest(center, 40)
			if node then
				self:_planTo(node.Position, now, true)
			end
		end
		return { Path = self._path, Speed = speeds.Search }
	elseif state == "Ambushing" then
		-- Silent and still. Anyone who comes close is in trouble.
		if now >= self.WaitUntil then
			self:SetState("Returning", now)
		end
		for _, p in players do
			if (p.Position - self.Position).Magnitude < cfg.Ambush.TriggerRange and not p.Hidden then
				local memory = self:_memory(p.Id)
				memory.Awareness = 1
				memory.LastSeen = p.Position
				memory.LastSeenTime = now
				if not self.Shy then
					self.Target = p.Id
					self:SetState("Chasing", now)
					return { Path = nil, Speed = 0, Face = p.Position - self.Position, Vocal = "Roar" }
				end
			end
		end
		return { Path = nil, Speed = 0 }
	elseif state == "Returning" then
		if now < self.WaitUntil then
			return { Path = nil, Speed = 0 }
		end
		local path = self:_planTo(self.Home, now)
		if arrived or not path or (self.Position - self.Home).Magnitude < 10 then
			self.Target = nil
			self:SetState("Patrolling", now)
			return { Path = nil, Speed = 0 }
		end
		return { Path = path, Speed = speeds.Returning * (if self.Shy then 1.6 else 1) }
	end
	return { Path = nil, Speed = 0 }
end

return Brain
