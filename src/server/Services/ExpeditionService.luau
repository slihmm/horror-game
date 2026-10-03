--!strict
-- The run: enter the cave, go deep, find the way out (or don't).
--
-- Owns each player's run state and the moments that bracket it:
--   Surface -> Underground   when they step into the cave
--   Underground -> Escaped   when they surface through the true exit having
--                            reached the Gathering (cinematic ending)
--   Underground -> Surface   when they walk back out the way they came
--   Underground -> Dead      when the cave or the Lamplighter kills them
-- All statistics are computed here from server-side positions and times;
-- nothing the client says can change them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local CaveLayout = require(Shared.Config.CaveLayout)
local LootConfig = require(Shared.Config.LootConfig)
local StatsConfig = require(Shared.Config.StatsConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Signal = require(Shared.Utility.Signal)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local DataService = require(Services.DataService)
local PlayerService = require(Services.PlayerService)
local TraversalService = require(Services.TraversalService)
local SurfaceBuilder = require(ServerScriptService.Server.Cave.SurfaceBuilder)

export type Run = {
	State: string,
	StartedAt: number,
	MaxProgress: number,
	MaxDepth: number,
	Anchors: { [string]: boolean },
	Secrets: { [string]: boolean },
	Satchel: { [string]: number },
	LastTimeTick: number,
}

local RESPAWN_DELAY = 7

local ExpeditionService = {}
ExpeditionService.__index = ExpeditionService

type State = {
	RunStarted: Signal.Signal<Player>,
	RunEnded: Signal.Signal<Player, string>,
	SatchelChanged: Signal.Signal<Player>,
	StoryBeat: Signal.Signal<Player, string>,
	_runs: { [Player]: Run },
	_cinematic: { [Player]: string },
}
export type ExpeditionService = typeof(setmetatable({} :: State, ExpeditionService))

local function newRun(): Run
	return {
		State = Constants.RunStates.Surface,
		StartedAt = 0,
		MaxProgress = 0,
		MaxDepth = 0,
		Anchors = {},
		Secrets = {},
		Satchel = {},
		LastTimeTick = os.clock(),
	}
end

function ExpeditionService.Init(self: ExpeditionService)
	Net.Event("CinematicFinished").OnServerEvent:Connect(function(player: Player, cinematicId: any)
		if type(cinematicId) ~= "string" or self._cinematic[player] ~= cinematicId then
			return
		end
		self._cinematic[player] = nil
		self:_onCinematicFinished(player, cinematicId)
	end)
end

function ExpeditionService.Start(self: ExpeditionService)
	CaveService:WaitUntilReady()
	Players.PlayerAdded:Connect(function(player: Player)
		self._runs[player] = newRun()
	end)
	for _, player in Players:GetPlayers() do
		self._runs[player] = self._runs[player] or newRun()
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local run = self._runs[player]
		if run and run.State == Constants.RunStates.Underground then
			self:_bankTime(player, run)
		end
		self._runs[player] = nil
		self._cinematic[player] = nil
	end)

	PlayerService.CharacterSpawned:Connect(function(player: Player, _character: Model)
		self:_onSpawn(player)
	end)
	PlayerService.CharacterDied:Connect(function(player: Player, cause: string)
		self:_onDeath(player, cause)
	end)
	CaveService.ZoneChanged:Connect(function(player: Player, old: string, new: string)
		self:_onZoneChanged(player, old, new)
	end)
	CaveService.AnchorEntered:Connect(function(player: Player, anchorId: string)
		self:_onAnchor(player, anchorId)
	end)
	CaveService.SecretEntered:Connect(function(player: Player, secretId: string)
		self:_onSecret(player, secretId)
	end)
	TraversalService.Completed:Connect(function(player: Player, _id: string, kind: string, direction: number)
		if kind == "Rope" and direction == 1 then
			self.StoryBeat:Fire(player, "Descended")
		end
	end)

	-- Statistics sampling.
	while true do
		task.wait(1)
		self:_sample()
	end
end

function ExpeditionService.GetRun(self: ExpeditionService, player: Player): Run?
	return self._runs[player]
end

function ExpeditionService.IsUnderground(self: ExpeditionService, player: Player): boolean
	local run = self._runs[player]
	return run ~= nil and run.State == Constants.RunStates.Underground
end

function ExpeditionService.HasReached(self: ExpeditionService, player: Player, anchorId: string): boolean
	local run = self._runs[player]
	return run ~= nil and run.Anchors[anchorId] == true
end

-- Cinematics -----------------------------------------------------------------------

function ExpeditionService._play(self: ExpeditionService, player: Player, cinematicId: string, params: { [string]: any })
	self._cinematic[player] = cinematicId
	Net.Event("Cinematic"):FireClient(player, cinematicId, params)
end

function ExpeditionService._onSpawn(self: ExpeditionService, player: Player)
	local run = self._runs[player] or newRun()
	self._runs[player] = run
	run.State = Constants.RunStates.Surface
	player:SetAttribute(Constants.Attributes.RunState, run.State)
	local profile = DataService:GetProfile(player)
	if profile and not profile.Flags.IntroSeen then
		local plan = CaveService.Plan
		local mouth = plan and plan.Anchors[CaveLayout.EntranceAnchor]
		self:_play(player, "Intro", {
			Mouth = if mouth then (mouth.Ports.Outside or mouth.Position) else nil,
		})
	else
		self:_play(player, "Wake", {})
	end
end

function ExpeditionService._onCinematicFinished(self: ExpeditionService, player: Player, cinematicId: string)
	if cinematicId == "Intro" then
		DataService:Update(player, function(profile)
			profile.Flags.IntroSeen = true
		end)
	elseif cinematicId == "Ending" then
		-- Back to camp, morning gone, as if nothing happened.
		local plan = CaveService.Plan
		if plan then
			PlayerService:Teleport(player, SurfaceBuilder.SpawnPoint(plan, player.UserId % 16))
		end
		local run = self._runs[player]
		if run then
			run.State = Constants.RunStates.Surface
			player:SetAttribute(Constants.Attributes.RunState, run.State)
		end
		self:_play(player, "Wake", {})
	end
end

-- Run lifecycle ------------------------------------------------------------------------

function ExpeditionService._beginRun(self: ExpeditionService, player: Player, run: Run)
	run.State = Constants.RunStates.Underground
	run.StartedAt = os.clock()
	run.MaxProgress = 0
	run.MaxDepth = 0
	run.Anchors = {}
	run.Secrets = {}
	run.Satchel = {}
	run.LastTimeTick = os.clock()
	player:SetAttribute(Constants.Attributes.RunState, run.State)
	player:SetAttribute(Constants.Attributes.RunStart, os.time())
	DataService:Update(player, function(profile)
		profile.Stats.Expeditions += 1
	end)
	self.SatchelChanged:Fire(player)
	self.RunStarted:Fire(player)
end

function ExpeditionService._bankTime(self: ExpeditionService, player: Player, run: Run)
	local now = os.clock()
	local delta = math.max(0, now - run.LastTimeTick)
	run.LastTimeTick = now
	if delta > 0 then
		DataService:Update(player, function(profile)
			profile.Stats.TimeUnderground += delta
		end)
	end
end

-- Satchel contents become permanent: currency, collection, cosmetics.
function ExpeditionService._bankSatchel(self: ExpeditionService, player: Player, run: Run): (number, number)
	local earned, items = 0, 0
	DataService:Update(player, function(profile)
		for itemId, count in run.Satchel do
			local item = LootConfig.ById[itemId]
			if item then
				items += count
				if item.Kind == "Cosmetic" then
					profile.Cosmetics[itemId] = true
				else
					earned += item.Value * count
					profile.Collection[itemId] = (profile.Collection[itemId] or 0) + count
				end
			end
		end
		profile.Currency += earned
	end)
	run.Satchel = {}
	self.SatchelChanged:Fire(player)
	return earned, items
end

function ExpeditionService._endRun(self: ExpeditionService, player: Player, outcome: string)
	local run = self._runs[player]
	if not run or run.State ~= Constants.RunStates.Underground then
		return
	end
	self:_bankTime(player, run)
	run.State = outcome
	player:SetAttribute(Constants.Attributes.RunState, outcome)
	self.RunEnded:Fire(player, outcome)
end

function ExpeditionService._onZoneChanged(self: ExpeditionService, player: Player, old: string, new: string)
	local run = self._runs[player]
	if not run then
		return
	end
	local wasUnder = old ~= "" and ZoneConfig.Get(old).Underground
	local isUnder = ZoneConfig.Get(new).Underground
	-- Escaped counts as surfaced too, in case the ending's completion
	-- message never arrives: the player must always be able to go again.
	local surfaced = run.State == Constants.RunStates.Surface or run.State == Constants.RunStates.Escaped
	if isUnder and surfaced then
		self:_beginRun(player, run)
	elseif wasUnder and not isUnder and run.State == Constants.RunStates.Underground then
		local track = CaveService:GetTrack(player)
		local atTrueExit = track ~= nil and track.InAnchor == "ExitValley"
		if atTrueExit and run.Anchors[CaveLayout.RequiredBeforeEscape] then
			self:_escape(player, run)
		else
			-- Walked back out the way they came: alive, loot kept, no escape.
			local earned = self:_bankSatchel(player, run)
			self:_endRun(player, Constants.RunStates.Surface)
			if earned > 0 then
				Net.Event("Notify"):FireClient(player, "Banked", `you made it out with {earned} worth of salvage`)
			end
		end
	end
end

function ExpeditionService._escape(self: ExpeditionService, player: Player, run: Run)
	local elapsed = os.clock() - run.StartedAt
	local earned, items = self:_bankSatchel(player, run)
	local secrets = 0
	for _ in run.Secrets do
		secrets += 1
	end
	DataService:Update(player, function(profile)
		local stats = profile.Stats
		stats.Completions += 1
		if stats.FastestEscape <= 0 or elapsed < stats.FastestEscape then
			stats.FastestEscape = math.floor(elapsed)
		end
	end)
	local maxDepth = run.MaxDepth
	self:_endRun(player, Constants.RunStates.Escaped)
	local plan = CaveService.Plan
	local exit = plan and plan.Anchors[CaveLayout.EscapeAnchor]
	self:_play(player, "Ending", {
		Time = math.floor(elapsed),
		Depth = math.floor(maxDepth * StatsConfig.MetersPerStud),
		Secrets = secrets,
		Earned = earned,
		Items = items,
		Mouth = if exit then (exit.Ports.Outside or exit.Position) else nil,
	})
end

function ExpeditionService._onDeath(self: ExpeditionService, player: Player, cause: string)
	local run = self._runs[player]
	if run and run.State == Constants.RunStates.Underground then
		-- Whatever was in the satchel stays down here.
		run.Satchel = {}
		self.SatchelChanged:Fire(player)
		DataService:Update(player, function(profile)
			profile.Stats.Deaths += 1
		end)
		self:_endRun(player, Constants.RunStates.Dead)
	end
	self:_play(player, "Death", { Cause = cause })
	task.delay(RESPAWN_DELAY, function()
		if player.Parent then
			PlayerService:Spawn(player)
		end
	end)
end

function ExpeditionService._onAnchor(self: ExpeditionService, player: Player, anchorId: string)
	local run = self._runs[player]
	if not run or run.State ~= Constants.RunStates.Underground then
		return
	end
	if not run.Anchors[anchorId] then
		run.Anchors[anchorId] = true
		self.StoryBeat:Fire(player, anchorId)
	end
end

function ExpeditionService._onSecret(self: ExpeditionService, player: Player, secretId: string)
	local run = self._runs[player]
	if not run or run.State ~= Constants.RunStates.Underground or run.Secrets[secretId] then
		return
	end
	run.Secrets[secretId] = true
	DataService:Update(player, function(profile)
		profile.Stats.SecretsFound += 1
	end)
	Net.Event("Notify"):FireClient(player, "Secret", "nobody was meant to find this place")
end

-- Satchel ------------------------------------------------------------------------------

function ExpeditionService.AddToSatchel(self: ExpeditionService, player: Player, itemId: string): boolean
	local run = self._runs[player]
	if not run or run.State ~= Constants.RunStates.Underground then
		return false
	end
	run.Satchel[itemId] = (run.Satchel[itemId] or 0) + 1
	local value = 0
	for id, count in run.Satchel do
		local item = LootConfig.ById[id]
		if item then
			value += item.Value * count
		end
	end
	player:SetAttribute(Constants.Attributes.SatchelValue, value)
	self.SatchelChanged:Fire(player)
	return true
end

function ExpeditionService.GetSatchel(self: ExpeditionService, player: Player): { [string]: number }
	local run = self._runs[player]
	return if run then run.Satchel else {}
end

-- Sampling -------------------------------------------------------------------------------

function ExpeditionService._sample(self: ExpeditionService)
	for player, run in self._runs do
		if run.State ~= Constants.RunStates.Underground then
			continue
		end
		local track = CaveService:GetTrack(player)
		if not track then
			continue
		end
		local improvedDistance = track.Progress > run.MaxProgress
		local improvedDepth = track.Depth > run.MaxDepth
		run.MaxProgress = math.max(run.MaxProgress, track.Progress)
		run.MaxDepth = math.max(run.MaxDepth, track.Depth)
		if os.clock() - run.LastTimeTick >= 15 then
			self:_bankTime(player, run)
		end
		if improvedDistance or improvedDepth then
			local distance = math.floor(run.MaxProgress)
			local depth = math.floor(run.MaxDepth)
			local profile = DataService:GetProfile(player)
			if profile and (distance > profile.Stats.HighestDistance or depth > profile.Stats.DeepestDescent) then
				DataService:Update(player, function(p)
					p.Stats.HighestDistance = math.max(p.Stats.HighestDistance, distance)
					p.Stats.DeepestDescent = math.max(p.Stats.DeepestDescent, depth)
				end)
			end
		end
	end
end

local instance: ExpeditionService = setmetatable({
	RunStarted = Signal.new(),
	RunEnded = Signal.new(),
	SatchelChanged = Signal.new(),
	StoryBeat = Signal.new(),
	_runs = {},
	_cinematic = {},
} :: State, ExpeditionService)

return instance
