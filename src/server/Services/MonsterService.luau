--!strict
-- Runs the Lamplighter: perception input, the brain, the body, attacks and
-- story-driven activation. It sleeps until someone gets deep enough, keeps
-- its distance during early encounters, and hunts in earnest once the
-- expedition has reached the abandoned camp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local CaveLayout = require(Shared.Config.CaveLayout)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Signal = require(Shared.Utility.Signal)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local ExpeditionService = require(Services.ExpeditionService)
local HeadlampService = require(Services.HeadlampService)
local NoiseService = require(Services.NoiseService)
local PlayerService = require(Services.PlayerService)
local TraversalService = require(Services.TraversalService)
local Monster = ServerScriptService.Server.Monster
local Brain = require(Monster.MonsterBrain)
local Body = require(Monster.MonsterBody)

local SLEEP_AFTER = 90
local VOCAL_RANGE = 260

local MonsterService = {}
MonsterService.__index = MonsterService

type State = {
	ChaseStarted: Signal.Signal<Player>,
	ChaseEnded: Signal.Signal<Player>,
	StateChanged: Signal.Signal<string>,
	_brain: Brain.Brain?,
	_body: Body.Body?,
	_noises: { Brain.Noise },
	_command: Brain.Command,
	_lastThink: number,
	_noDeepPlayersSince: number,
	_hidden: { [Player]: boolean },
	_params: RaycastParams,
}
export type MonsterService = typeof(setmetatable({} :: State, MonsterService))

function MonsterService.Start(self: MonsterService)
	CaveService:WaitUntilReady()
	local plan = CaveService.Plan
	local dressing = CaveService.Dressing
	if not plan or not dressing then
		return
	end
	local lair = plan.Anchors[CaveLayout.LairAnchor]
	local home: Vector3 = if lair then (lair.Data.Den or lair.Position) else plan.Graph.Nodes[1].Position
	-- The den point is computed, not measured: put its feet on the floor.
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Include
	floorParams.FilterDescendantsInstances = { Workspace.Terrain }
	local floorHit = Workspace:Raycast(home + Vector3.yAxis * 6, Vector3.yAxis * -20, floorParams)
	if floorHit then
		home = floorHit.Position
	end
	local folder = Instance.new("Folder")
	folder.Name = Constants.Folders.Monster
	folder.Parent = Workspace:FindFirstChild(Constants.Folders.Cave) or Workspace
	local body = Body.new(folder, home)
	self._body = body

	self._params.FilterType = Enum.RaycastFilterType.Include
	self._params.FilterDescendantsInstances = { Workspace.Terrain }
	local spots = {}
	for _, spot in dressing.HidingSpots do
		table.insert(spots, spot.CFrame)
	end
	local world: Brain.World = {
		LineOfSight = function(from: Vector3, to: Vector3): boolean
			return Workspace:Raycast(from, to - from, self._params) == nil
		end,
		HidingSpots = function(): { CFrame }
			return spots
		end,
	}
	self._brain = Brain.new(plan.Graph, world, home)

	NoiseService.Emitted:Connect(function(noise: NoiseService.Noise)
		table.insert(self._noises, { Position = noise.Position, Loudness = noise.Loudness, Source = noise.Source })
	end)
	ExpeditionService.StoryBeat:Connect(function(_player: Player, beat: string)
		local brain = self._brain
		if not brain then
			return
		end
		if beat == MonsterConfig.Activation.WakeAnchor then
			brain:Wake(os.clock())
		elseif beat == MonsterConfig.Activation.FullHuntAnchor then
			brain:Wake(os.clock())
			brain.Shy = false
		end
	end)
	PlayerService.CharacterDied:Connect(function(_player: Player, cause: string)
		if cause == "Monster" then
			-- It takes their light. One more lamp burns on its head.
			local lamps = (body.Root:GetAttribute("Lamps") :: number?) or MonsterConfig.Visual.Lamps
			body.Root:SetAttribute("Lamps", lamps + 1)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self._hidden[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		self:_move(dt)
	end)
	while true do
		task.wait(MonsterConfig.ThinkInterval)
		self:_think()
	end
end

function MonsterService.GetState(self: MonsterService): string
	local brain = self._brain
	return if brain then brain.State else "Dormant"
end

function MonsterService.GetPosition(self: MonsterService): Vector3?
	local body = self._body
	return if body then body.Position else nil
end

-- Hiding: crouched inside a hiding volume.
function MonsterService._updateHiding(self: MonsterService, player: Player, root: BasePart, crouched: boolean): CFrame?
	local dressing = CaveService.Dressing
	local found: CFrame? = nil
	if dressing and crouched then
		for _, spot in dressing.HidingSpots do
			local localPos = spot.CFrame:PointToObjectSpace(root.Position)
			local half = spot.Size / 2 + Vector3.new(0.5, 1, 0.5)
			if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
				found = spot.CFrame
				break
			end
		end
	end
	local hidden = found ~= nil
	if (self._hidden[player] == true) ~= hidden then
		if hidden then
			self._hidden[player] = true
		else
			self._hidden[player] = nil
		end
		player:SetAttribute(Constants.Attributes.Hiding, hidden)
	end
	return found
end

function MonsterService._snapshots(self: MonsterService): { Brain.PlayerSnapshot }
	local list = {}
	local anyDeep = false
	for _, player in Players:GetPlayers() do
		local state = PlayerService:GetCharacterState(player)
		local track = CaveService:GetTrack(player)
		if not state or not track or state.Humanoid.Health <= 0 then
			continue
		end
		local zone = ZoneConfig.Get(track.Zone)
		if not zone.Underground or TraversalService:IsTraversing(player) then
			continue
		end
		if zone.Order >= 3 then
			anyDeep = true
		end
		local character = player.Character
		local crouched = character ~= nil and character:GetAttribute(Constants.Attributes.Stance) == Constants.Stances.Crouch
		local spot = self:_updateHiding(player, state.Root, crouched)
		table.insert(list, {
			Id = player,
			Position = state.Root.Position,
			Velocity = state.Root.AssemblyLinearVelocity,
			Crouched = crouched,
			Hidden = spot ~= nil,
			HidingSpot = spot,
			LampOn = HeadlampService:IsLit(player),
			BeamDirection = HeadlampService:BeamDirection(player),
		})
	end
	if anyDeep then
		self._noDeepPlayersSince = os.clock()
	end
	return list
end

function MonsterService._think(self: MonsterService)
	local brain = self._brain
	local body = self._body
	if not brain or not body then
		return
	end
	local now = os.clock()
	local dt = now - self._lastThink
	self._lastThink = now
	brain.Position = body.Position
	brain.Facing = body.Facing
	local players = self:_snapshots()

	-- Nobody deep enough for a while: go back to sleep in the lair.
	if brain.State ~= "Dormant" and now - self._noDeepPlayersSince > SLEEP_AFTER then
		brain:Sleep(now)
		brain.Shy = true
		body:Teleport(brain.Home)
	end

	local noises = self._noises
	self._noises = {}
	local command = brain:Think(players, noises, math.min(dt, 1), now, body.Arrived)
	self._command = command
	body:SetPath(command.Path)
	body:Face(command.Face)

	if command.Vocal then
		self:_broadcast("MonsterVocal", body.Root.Position, { Kind = command.Vocal })
	end
	local victim = command.Attack
	if victim ~= nil and typeof(victim) == "Instance" and victim:IsA("Player") then
		PlayerService:Damage(victim, MonsterConfig.Chase.Damage, "Monster")
		self:_broadcast("MonsterHit", body.Root.Position, { Victim = victim.UserId })
	end
	for _, event in brain:DrainEvents() do
		if event.Kind == "State" then
			body.Root:SetAttribute(Constants.Attributes.MonsterState, brain.State)
			self.StateChanged:Fire(brain.State)
		elseif event.Kind == "ChaseStarted" and typeof(event.Player) == "Instance" then
			self.ChaseStarted:Fire(event.Player :: Player)
		elseif event.Kind == "ChaseEnded" and typeof(event.Player) == "Instance" then
			self.ChaseEnded:Fire(event.Player :: Player)
		end
	end
end

function MonsterService._move(self: MonsterService, dt: number)
	local body = self._body
	if not body then
		return
	end
	body:Step(dt, self._command.Speed)
end

function MonsterService._broadcast(self: MonsterService, kind: string, position: Vector3, params: { [string]: any })
	local remote = Net.Event("WorldEffect")
	for _, player in Players:GetPlayers() do
		local track = CaveService:GetTrack(player)
		if track and (track.Position - position).Magnitude < VOCAL_RANGE then
			remote:FireClient(player, kind, position, params)
		end
	end
end

local instance: MonsterService = setmetatable({
	ChaseStarted = Signal.new(),
	ChaseEnded = Signal.new(),
	StateChanged = Signal.new(),
	_brain = nil,
	_body = nil,
	_noises = {},
	_command = { Path = nil, Speed = 0 },
	_lastThink = os.clock(),
	_noDeepPlayersSince = os.clock(),
	_hidden = {},
	_params = RaycastParams.new(),
} :: State, MonsterService)

return instance
