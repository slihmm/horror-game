--!strict
-- Character lifecycle and the physical, server-owned side of being a player:
-- spawning, removing name tags, stance, noise, fall damage, injuries,
-- drowning, health regeneration, basic movement validation and proximity-
-- limited text chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local RateLimiter = require(Shared.Utility.RateLimiter)
local Signal = require(Shared.Utility.Signal)
local Trove = require(Shared.Utility.Trove)

local Services = ServerScriptService.Server.Services
local NoiseService = require(Services.NoiseService)
local DataService = require(Services.DataService)
local CaveService = require(Services.CaveService)
local SurfaceBuilder = require(ServerScriptService.Server.Cave.SurfaceBuilder)

type CharacterState = {
	Trove: Trove.Trove,
	Humanoid: Humanoid,
	Root: BasePart,
	PeakFallSpeed: number,
	LastDamage: number,
	Breath: number,
	LastValid: CFrame,
	Violations: number,
	LastCheck: number,
}

local PlayerService = {}
PlayerService.__index = PlayerService

type State = {
	CharacterSpawned: Signal.Signal<Player, Model>,
	CharacterDied: Signal.Signal<Player, string>,
	Damaged: Signal.Signal<Player, number, string>,
	_states: { [Player]: CharacterState },
	_spawnIndex: number,
	_lastDamageCause: { [Player]: string },
}
export type PlayerService = typeof(setmetatable({} :: State, PlayerService))

local stanceLimiter = RateLimiter.new(6, 4)

local function setCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = Constants.CollisionGroups.Players
		end
	end
end

local voxelRegion = Vector3.new(4, 4, 4)

local function headInWater(head: BasePart): boolean
	local center = head.Position
	local region = Region3.new(center - voxelRegion / 2, center + voxelRegion / 2):ExpandToGrid(4)
	local ok, materials, occupancies = pcall(function()
		return Workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok then
		return false
	end
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] == Enum.Material.Water and occupancies[x][y][z] > 0.5 then
					return true
				end
			end
		end
	end
	return false
end

function PlayerService.Init(self: PlayerService)
	Net.Event("SetStance").OnServerEvent:Connect(function(player: Player, stance)
		if not stanceLimiter:Allow(player) then
			return
		end
		if stance ~= Constants.Stances.Stand and stance ~= Constants.Stances.Crouch then
			return
		end
		local character = player.Character
		if character then
			character:SetAttribute(Constants.Attributes.Stance, stance)
		end
	end)
	self:_setupChat()
end

function PlayerService.Start(self: PlayerService)
	CaveService:WaitUntilReady()
	Players.PlayerAdded:Connect(function(player: Player)
		self:_onPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_onPlayer(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = self._states[player]
		if state then
			state.Trove:Clean()
		end
		self._states[player] = nil
		self._lastDamageCause[player] = nil
		stanceLimiter:Forget(player)
	end)
	task.spawn(function()
		while true do
			self:_tick(0.25)
			task.wait(0.25)
		end
	end)
end

function PlayerService._onPlayer(self: PlayerService, player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		self:_onCharacter(player, character)
	end)
	DataService:WaitForProfile(player, 60)
	if player.Parent then
		self:Spawn(player)
	end
end

-- Spawns (or respawns) the player at the surface camp.
function PlayerService.Spawn(self: PlayerService, player: Player)
	if not player.Parent then
		return
	end
	player:LoadCharacterAsync()
	local character = player.Character
	if not character then
		local deadline = os.clock() + 10
		while not player.Character and player.Parent and os.clock() < deadline do
			task.wait(0.1)
		end
		character = player.Character
	end
	if not character then
		return
	end
	self._spawnIndex += 1
	local plan = CaveService.Plan
	if plan then
		-- Sanctioned move: the speed check may not have seen this character yet.
		character:SetAttribute("Teleporting", true)
		character:PivotTo(SurfaceBuilder.SpawnPoint(plan, self._spawnIndex))
		task.delay(1.5, function()
			if character.Parent then
				character:SetAttribute("Teleporting", nil)
			end
		end)
	end
end

function PlayerService._onCharacter(self: PlayerService, player: Player, character: Model)
	local previous = self._states[player]
	if previous then
		previous.Trove:Clean()
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local trove = Trove.new()

	-- No floating names or health bars.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = PlayerConfig.Health.Max
	humanoid.Health = PlayerConfig.Health.Max
	humanoid.WalkSpeed = PlayerConfig.Movement.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = PlayerConfig.Movement.JumpHeight
	humanoid.BreakJointsOnDeath = false
	character:SetAttribute(Constants.Attributes.Stance, Constants.Stances.Stand)
	character:SetAttribute(Constants.Attributes.Injured, false)
	setCollisionGroup(character)
	trove:Connect(character.DescendantAdded, function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = Constants.CollisionGroups.Players
		end
	end)

	local state: CharacterState = {
		Trove = trove,
		Humanoid = humanoid,
		Root = root,
		PeakFallSpeed = 0,
		LastDamage = 0,
		Breath = PlayerConfig.Drowning.BreathSeconds,
		LastValid = root.CFrame,
		Violations = 0,
		LastCheck = os.clock(),
	}
	self._states[player] = state

	trove:Connect(humanoid.StateChanged, function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Landed then
			self:_onLanded(player, state)
		end
	end)
	trove:Connect(humanoid.HealthChanged, function(health: number)
		character:SetAttribute(Constants.Attributes.Injured, health < PlayerConfig.Health.InjuredThreshold)
	end)
	trove:Connect(humanoid.Died, function()
		local cause = self._lastDamageCause[player] or "Unknown"
		self.CharacterDied:Fire(player, cause)
	end)
	self.CharacterSpawned:Fire(player, character)
end

-- Damage -------------------------------------------------------------------------

function PlayerService.Damage(self: PlayerService, player: Player, amount: number, cause: string)
	local state = self._states[player]
	if not state or state.Humanoid.Health <= 0 then
		return
	end
	self._lastDamageCause[player] = cause
	state.LastDamage = os.clock()
	state.Humanoid:TakeDamage(amount)
	self.Damaged:Fire(player, amount, cause)
end

function PlayerService.Kill(self: PlayerService, player: Player, cause: string)
	local state = self._states[player]
	if not state then
		return
	end
	self._lastDamageCause[player] = cause
	state.Humanoid.Health = 0
end

function PlayerService.GetCharacterState(self: PlayerService, player: Player): CharacterState?
	return self._states[player]
end

function PlayerService._onLanded(self: PlayerService, player: Player, state: CharacterState)
	local speed = state.PeakFallSpeed
	state.PeakFallSpeed = 0
	local character = player.Character
	if not character or character:GetAttribute(Constants.Attributes.Traversing) then
		return
	end
	local fall = PlayerConfig.Fall
	local noise = PlayerConfig.Noise
	if speed > fall.SafeVelocity then
		local t = math.clamp((speed - fall.SafeVelocity) / (fall.LethalVelocity - fall.SafeVelocity), 0, 1)
		self:Damage(player, fall.MaxDamage * t * t + 8 * t, "Fall")
		NoiseService.Emit(state.Root.Position, noise.HardLand, "Land", player)
	elseif speed > 30 then
		NoiseService.Emit(state.Root.Position, noise.Land * math.clamp(speed / fall.SafeVelocity, 0.3, 1), "Land", player)
	end
end

-- Periodic simulation ---------------------------------------------------------------

function PlayerService._tick(self: PlayerService, dt: number)
	local now = os.clock()
	local noise = PlayerConfig.Noise
	local movement = PlayerConfig.Movement
	for player, state in self._states do
		local character = player.Character
		local humanoid = state.Humanoid
		if not character or humanoid.Health <= 0 or not state.Root.Parent then
			continue
		end
		local root = state.Root
		local velocity = root.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local traversing = character:GetAttribute(Constants.Attributes.Traversing) == true
		local track = CaveService:GetTrack(player)
		local underground = track ~= nil and ZoneConfig.Get(track.Zone).Underground

		-- Fall tracking (sampled; Landed applies the damage).
		if humanoid:GetState() == Enum.HumanoidStateType.Freefall and not traversing then
			state.PeakFallSpeed = math.max(state.PeakFallSpeed, -velocity.Y)
		end

		-- Movement noise.
		if underground and not traversing and horizontal > 1 then
			local stance = character:GetAttribute(Constants.Attributes.Stance)
			local loudness: number
			if stance == Constants.Stances.Crouch then
				loudness = noise.Crouch
			elseif horizontal > movement.WalkSpeed + 2 then
				loudness = noise.Sprint
			else
				loudness = noise.Walk
			end
			if track and track.Node and track.Node.Tags.Water then
				loudness += noise.InWaterBonus
			end
			NoiseService.Emit(root.Position, loudness, "Footsteps", player)
		end

		-- Health regeneration after a quiet period.
		local health = PlayerConfig.Health
		if humanoid.Health < humanoid.MaxHealth and now - state.LastDamage > health.RegenDelay then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + health.RegenPerSecond * dt)
		end

		-- Drowning.
		local head = character:FindFirstChild("Head") :: BasePart?
		if head and underground and headInWater(head) then
			state.Breath -= dt
			if state.Breath <= 0 then
				self:Damage(player, PlayerConfig.Drowning.DamagePerSecond * dt, "Drowned")
			end
		else
			state.Breath = math.min(PlayerConfig.Drowning.BreathSeconds, state.Breath + dt * 3)
		end

		-- Movement validation: catch blatant speed hacks, ignore falls,
		-- traversals and other legitimate fast movement.
		local check = PlayerConfig.SpeedCheck
		if now - state.LastCheck >= check.Window then
			local elapsed = now - state.LastCheck
			local moved = root.Position - state.LastValid.Position
			local flatMoved = Vector3.new(moved.X, 0, moved.Z).Magnitude
			local allowed = movement.SprintSpeed * check.Tolerance * elapsed + 4
			local exempt = traversing
				or humanoid:GetState() == Enum.HumanoidStateType.Freefall
				or character:GetAttribute("Teleporting") == true
				or CaveService:InRecursion(root.Position)
			if not exempt and flatMoved > allowed then
				state.Violations += 1
				if state.Violations >= check.ViolationsBeforeCorrection then
					root.CFrame = state.LastValid
					root.AssemblyLinearVelocity = Vector3.zero
					state.Violations = 0
				end
			else
				state.Violations = math.max(0, state.Violations - 1)
				state.LastValid = root.CFrame
			end
			state.LastCheck = now
		end
	end
end

-- Allows a server-sanctioned teleport without tripping the speed check.
function PlayerService.Teleport(self: PlayerService, player: Player, cframe: CFrame)
	local state = self._states[player]
	local character = player.Character
	if not state or not character then
		return
	end
	character:SetAttribute("Teleporting", true)
	character:PivotTo(cframe)
	state.LastValid = state.Root.CFrame
	state.LastCheck = os.clock()
	task.delay(1.5, function()
		if character.Parent then
			character:SetAttribute("Teleporting", nil)
		end
	end)
end

-- Text chat only reaches players who are close enough to hear you, or
-- everyone when you are both above ground.
function PlayerService._setupChat(self: PlayerService)
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		local general = channels and channels:WaitForChild("RBXGeneral", 30)
		if not general or not general:IsA("TextChannel") then
			return
		end
		general.ShouldDeliverCallback = function(message: TextChatMessage, textSource: TextSource)
			local sender = message.TextSource and Players:GetPlayerByUserId(message.TextSource.UserId)
			local receiver = Players:GetPlayerByUserId(textSource.UserId)
			if not sender or not receiver or sender == receiver then
				return true
			end
			local a = CaveService:GetTrack(sender)
			local b = CaveService:GetTrack(receiver)
			if not a or not b then
				return true
			end
			if not ZoneConfig.Get(a.Zone).Underground and not ZoneConfig.Get(b.Zone).Underground then
				return true
			end
			return (a.Position - b.Position).Magnitude < 70
		end
	end)
end


local instance: PlayerService = setmetatable({
	CharacterSpawned = Signal.new(),
	CharacterDied = Signal.new(),
	Damaged = Signal.new(),
	_states = {},
	_spawnIndex = 0,
	_lastDamageCause = {},
} :: State, PlayerService)

return instance
