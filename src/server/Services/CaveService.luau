--!strict
-- Generates the cave at server start and answers spatial questions about it:
-- which zone a player is in, how deep, how far along the cave, which story
-- anchor or hidden room they have just entered.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLayout = require(Shared.Config.CaveLayout)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Signal = require(Shared.Utility.Signal)

local Cave = ServerScriptService.Server.Cave
local CavePlanner = require(Cave.CavePlanner)
local CaveGraph = require(Cave.CaveGraph)
local Primitives = require(Cave.CavePrimitives)
local TerrainBuilder = require(Cave.TerrainBuilder)
local SurfaceBuilder = require(Cave.SurfaceBuilder)
local Dress = require(Cave.DressContext)
local Populator = require(Cave.Populator)
local NodeRefiner = require(Cave.NodeRefiner)

type Node = CaveGraph.Node
type Anchor = Primitives.Anchor

export type Track = {
	Zone: string,
	Node: Node?,
	Depth: number,
	Progress: number,
	Position: Vector3,
	InAnchor: string?,
	InSecret: string?,
}

local TRACK_INTERVAL = 0.25

local CaveService = {}
CaveService.__index = CaveService

type State = {
	Ready: boolean,
	Plan: Primitives.Context?,
	Dressing: Dress.Results?,
	ReadySignal: Signal.Signal<>,
	ZoneChanged: Signal.Signal<Player, string, string>,
	AnchorEntered: Signal.Signal<Player, string>,
	SecretEntered: Signal.Signal<Player, string>,
	RingOpened: Signal.Signal<>,
	_tracks: { [Player]: Track },
	_ringOpen: boolean,
}
export type CaveService = typeof(setmetatable({} :: State, CaveService))

local function setupCollisionGroups()
	local groups = Constants.CollisionGroups
	for _, name in { groups.Players, groups.Traversing, groups.Blockers, groups.Effects } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(groups.Players, groups.Players, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Traversing, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(groups.Traversing, groups.Players, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Traversing, groups.Blockers, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Traversing, groups.Effects, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Blockers, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(groups.Effects, groups.Effects, false)
end

local function chooseSeed(): number
	if CaveConfig.Seed then
		return CaveConfig.Seed
	end
	return Random.new():NextInteger(1, 2 ^ 30)
end

local function inAnchor(anchor: Anchor, position: Vector3): boolean
	if anchor.Builder == "SurfaceCamp" or anchor.Builder == "ExitValley" then
		local flat = Vector3.new(position.X - anchor.Position.X, 0, position.Z - anchor.Position.Z).Magnitude
		return flat < 60 and position.Y > anchor.Position.Y - 10
	end
	if anchor.Builder == "LoopRing" then
		local flat = Vector3.new(position.X - anchor.Position.X, 0, position.Z - anchor.Position.Z).Magnitude
		return math.abs(flat - CaveConfig.Ring.Radius) < CaveConfig.Ring.TunnelRadius + 4
			and math.abs(position.Y - anchor.Position.Y) < 14
	end
	local flat = Vector3.new(position.X - anchor.Position.X, 0, position.Z - anchor.Position.Z).Magnitude
	local dy = position.Y - anchor.Position.Y
	return flat < anchor.Radius + 2 and dy > -6 and dy < anchor.Height * 1.8
end

function CaveService.Init(self: CaveService)
	setupCollisionGroups()
	for material, color in ZoneConfig.MaterialColors do
		Workspace.Terrain:SetMaterialColor(material, color)
	end
	Workspace:SetAttribute(Constants.Attributes.CaveReady, false)
end

function CaveService.Start(self: CaveService)
	local seed = chooseSeed()
	Workspace:SetAttribute(Constants.Attributes.CaveSeed, seed)
	local started = os.clock()

	local plan = CavePlanner.Plan(seed)
	self.Plan = plan
	local planned = os.clock()

	SurfaceBuilder.Terrain(plan)
	TerrainBuilder.Build(plan.Ops)
	local built = os.clock()

	local dressing = Dress.new(plan)
	SurfaceBuilder.Dress(dressing)
	Populator.Run(dressing)
	self.Dressing = dressing.Results
	self:_refineNodes()
	-- The ring's way on stays shut until the loop has been walked.
	plan.Graph:SetLinkEnabled("RingSeal", false)

	local secretsCount = #plan.Secrets
	print(
		string.format(
			"[CaveService] seed %d: %d nodes, %d secrets, %d lore slots, %d loot spots, %d hiding spots | plan %.2fs, terrain %.2fs, dress %.2fs",
			seed,
			#plan.Graph.Nodes,
			secretsCount,
			#dressing.Results.LoreSlots,
			#dressing.Results.LootSpots,
			#dressing.Results.HidingSpots,
			planned - started,
			built - planned,
			os.clock() - built
		)
	)

	self.Ready = true
	Workspace:SetAttribute(Constants.Attributes.CaveReady, true)
	self.ReadySignal:Fire()

	Players.PlayerRemoving:Connect(function(player: Player)
		self._tracks[player] = nil
	end)
	while true do
		self:_trackAll()
		task.wait(TRACK_INTERVAL)
	end
end

function CaveService.WaitUntilReady(self: CaveService)
	if not self.Ready then
		self.ReadySignal:Wait()
	end
end

function CaveService._refineNodes(self: CaveService)
	NodeRefiner.Refine((self.Plan :: Primitives.Context).Graph, 200)
end

-- Queries -----------------------------------------------------------------------

function CaveService.GetGraph(self: CaveService): CaveGraph.CaveGraph
	return (self.Plan :: Primitives.Context).Graph
end

function CaveService.GetAnchor(self: CaveService, id: string): Anchor?
	local plan = self.Plan
	return if plan then plan.Anchors[id] else nil
end

function CaveService.GetTrack(self: CaveService, player: Player): Track?
	return self._tracks[player]
end

function CaveService.NodeAt(self: CaveService, position: Vector3, maxDistance: number?): Node?
	local plan = self.Plan
	if not plan then
		return nil
	end
	return plan.Graph:Nearest(position, maxDistance or 40)
end


function CaveService._classify(self: CaveService, position: Vector3, previous: Track?): (string, Node?, string?)
	local plan = self.Plan :: Primitives.Context
	-- Story anchors first: their volumes are authoritative.
	for _, def in CaveLayout.Anchors do
		local anchor = plan.Anchors[def.Id]
		if anchor and inAnchor(anchor, position) then
			return anchor.Zone, anchor.Node, anchor.Id
		end
	end
	local node = plan.Graph:Nearest(position, 48)
	if node then
		return node.Zone, node, nil
	end
	if position.Y > CaveLayout.SurfaceY - 6 then
		return "Surface", nil, nil
	end
	return if previous then previous.Zone else "UpperCave", nil, nil
end

function CaveService._trackAll(self: CaveService)
	local plan = self.Plan
	if not plan then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local position = root.Position
			local previous = self._tracks[player]
			local zone: string, node: Node?, anchorId: string? = self:_classify(position, previous)
			local depth = math.max(0, CaveLayout.SurfaceY - position.Y)
			local progress = if node and node.Dist < math.huge then node.Dist else (if previous then previous.Progress else 0)
			if not ZoneConfig.Get(zone).Underground then
				depth = 0
			end
			local secretId: string? = nil
			for _, secret in plan.Secrets do
				if (secret.Center - position).Magnitude < secret.Radius then
					secretId = secret.Id
					break
				end
			end
			local track: Track = {
				Zone = zone,
				Node = node,
				Depth = depth,
				Progress = progress,
				Position = position,
				InAnchor = anchorId,
				InSecret = secretId,
			}
			self._tracks[player] = track
			player:SetAttribute(Constants.Attributes.Zone, zone)
			player:SetAttribute(Constants.Attributes.Depth, math.floor(depth))
			player:SetAttribute(Constants.Attributes.Progress, math.floor(progress))
			if not previous or previous.Zone ~= zone then
				self.ZoneChanged:Fire(player, if previous then previous.Zone else "", zone)
			end
			if anchorId and (not previous or previous.InAnchor ~= anchorId) then
				self.AnchorEntered:Fire(player, anchorId)
			end
			if secretId and (not previous or previous.InSecret ~= secretId) then
				self.SecretEntered:Fire(player, secretId)
			end
		end
	end
end

-- World changes ---------------------------------------------------------------

-- True inside the recursion corridor, where clients loop the player
-- backwards locally (the server must not treat that as cheating).
function CaveService.InRecursion(self: CaveService, position: Vector3): boolean
	local plan = self.Plan
	if not plan then
		return false
	end
	for _, f in plan.Features do
		if f.Kind == "Recursion" then
			local origin = f.Origin :: Vector3
			local axis = f.Axis :: Vector3
			local side = f.Side :: Vector3
			local rel = position - origin
			local along = rel:Dot(axis)
			return along > -6 and along < f.Modules * f.ModuleLength + 6 and math.abs(rel:Dot(side)) < f.Radius + 6 and math.abs(rel.Y) < 20
		end
	end
	return false
end

function CaveService.IsRingOpen(self: CaveService): boolean
	return self._ringOpen
end

-- Opens the sealed passage out of the loop. The cave rearranges itself:
-- terrain is cut away, rubble vanishes, and the monster's graph gains a link.
function CaveService.OpenRingSeal(self: CaveService)
	if self._ringOpen then
		return
	end
	local dressing = self.Dressing
	local seal = dressing and dressing.RingSeal
	if not seal then
		return
	end
	self._ringOpen = true
	Workspace.Terrain:FillBlock(seal.CFrame, seal.Size, Enum.Material.Air)
	if seal.Rubble then
		seal.Rubble:Destroy()
	end
	self:GetGraph():SetLinkEnabled("RingSeal", true)
	self.RingOpened:Fire()
end

-- Random graph node satisfying a filter, between minDist and maxDist from a
-- position (used for placing distant sounds and figures).
function CaveService.RandomNodeAround(self: CaveService, position: Vector3, minDist: number, maxDist: number, rng: Random, filter: ((Node) -> boolean)?): Node?
	local plan = self.Plan
	if not plan then
		return nil
	end
	local candidates = {}
	for _, node in plan.Graph:Within(position, maxDist) do
		local d = (node.Position - position).Magnitude
		if d >= minDist and (not filter or filter(node)) then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end



local instance: CaveService = setmetatable({
	Ready = false,
	Plan = nil,
	Dressing = nil,
	ReadySignal = Signal.new(),
	ZoneChanged = Signal.new(),
	AnchorEntered = Signal.new(),
	SecretEntered = Signal.new(),
	RingOpened = Signal.new(),
	_tracks = {},
	_ringOpen = false,
} :: State, CaveService)

return instance
