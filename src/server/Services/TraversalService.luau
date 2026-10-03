--!strict
-- Rope descents, chimney climbs and rock squeezes.
--
-- The server owns the state: who is on which traversal, in which direction,
-- whether and where they get wedged, how much effort freeing them takes, and
-- whether an exit is legitimate (timing and position are validated). The
-- client animates its own character along the path (see TraversalController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local TraversalConfig = require(Shared.Config.TraversalConfig)
local RateLimiter = require(Shared.Utility.RateLimiter)
local Signal = require(Shared.Utility.Signal)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local NoiseService = require(Services.NoiseService)
local PlayerService = require(Services.PlayerService)
local Primitives = require(ServerScriptService.Server.Cave.CavePrimitives)

type Traversal = Primitives.Traversal

type Session = {
	Traversal: Traversal,
	Direction: number, -- 1 = path order, -1 = reversed
	Path: { Vector3 },
	Length: number,
	Started: number,
	StuckAt: number?, -- fraction of the path
	StuckActive: boolean,
	EffortNeeded: number,
	Effort: number,
	LastStruggle: number,
	HelpPrompt: ProximityPrompt?,
	Token: number,
}

local TraversalService = {}
TraversalService.__index = TraversalService

type State = {
	Completed: Signal.Signal<Player, string, string, number>,
	_byId: { [string]: Traversal },
	_sessions: { [Player]: Session },
	_token: number,
	_rng: Random,
	_folder: Folder?,
}
export type TraversalService = typeof(setmetatable({} :: State, TraversalService))

local remoteLimiter = RateLimiter.new(20, 12)

local function pathLength(path: { Vector3 }): number
	local total = 0
	for i = 2, #path do
		total += (path[i] - path[i - 1]).Magnitude
	end
	return total
end

local function reversed(path: { Vector3 }): { Vector3 }
	local out = table.create(#path)
	for i = #path, 1, -1 do
		table.insert(out, path[i])
	end
	return out
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function TraversalService.Init(self: TraversalService)
	Net.Event("Traversal").OnServerEvent:Connect(function(player: Player, action: any, token: any, value: any)
		if not remoteLimiter:Allow(player) then
			return
		end
		if type(action) ~= "string" or type(token) ~= "number" then
			return
		end
		local session = self._sessions[player]
		if not session or session.Token ~= token then
			return
		end
		if action == "Stuck" then
			self:_onStuck(player, session)
		elseif action == "Struggle" then
			self:_onStruggle(player, session)
		elseif action == "Finish" then
			self:_onFinish(player, session, value == true)
		end
	end)
end

function TraversalService.Start(self: TraversalService)
	CaveService:WaitUntilReady()
	local plan = CaveService.Plan
	if not plan then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Traversals"
	folder.Parent = Workspace:FindFirstChild(Constants.Folders.Cave) or Workspace
	self._folder = folder
	for _, traversal in plan.Traversals do
		self._byId[traversal.Id] = traversal
		local kind = TraversalConfig.Kinds[traversal.Kind]
		self:_makePrompt(traversal, 1, kind.PromptText)
		if kind.Bidirectional then
			self:_makePrompt(traversal, -1, kind.ReversePromptText)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = self._sessions[player]
		if session then
			self:_end(player, session)
		end
		remoteLimiter:Forget(player)
	end)
	PlayerService.CharacterDied:Connect(function(player: Player)
		local session = self._sessions[player]
		if session then
			self:_end(player, session)
		end
	end)
	-- Timeouts.
	while true do
		task.wait(5)
		for player, session in self._sessions do
			if os.clock() - session.Started > TraversalConfig.Timeout then
				self:_abort(player, session)
			end
		end
	end
end

function TraversalService._makePrompt(self: TraversalService, traversal: Traversal, direction: number, text: string)
	local path = if direction == 1 then traversal.Path else reversed(traversal.Path)
	local holder = Instance.new("Part")
	holder.Name = `{traversal.Id}_{if direction == 1 then "A" else "B"}`
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(path[1])
	holder:SetAttribute(Constants.Attributes.TraversalId, traversal.Id)
	holder.Parent = self._folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = text
	prompt.ObjectText = ""
	prompt.HoldDuration = if traversal.Kind == "Squeeze" then 0.6 else 0.4
	prompt.MaxActivationDistance = TraversalConfig.PromptRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = holder
	prompt.Triggered:Connect(function(player: Player)
		self:_begin(player, traversal, direction)
	end)
end

function TraversalService._begin(self: TraversalService, player: Player, traversal: Traversal, direction: number)
	if self._sessions[player] then
		return
	end
	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local path = if direction == 1 then traversal.Path else reversed(traversal.Path)
	if (root.Position - path[1]).Magnitude > TraversalConfig.PromptRange + 6 then
		return
	end
	local kind = TraversalConfig.Kinds[traversal.Kind]
	self._token += 1
	local stuckAt: number? = nil
	if self._rng:NextNumber() < kind.StuckChance then
		local range = TraversalConfig.Stuck.At
		stuckAt = self._rng:NextNumber(range.Min, range.Max)
	end
	local effortRange = TraversalConfig.Stuck.Effort
	local session: Session = {
		Traversal = traversal,
		Direction = direction,
		Path = path,
		Length = pathLength(path),
		Started = os.clock(),
		StuckAt = stuckAt,
		StuckActive = false,
		EffortNeeded = self._rng:NextInteger(effortRange.Min, effortRange.Max),
		Effort = 0,
		LastStruggle = 0,
		HelpPrompt = nil,
		Token = self._token,
	}
	self._sessions[player] = session
	character:SetAttribute(Constants.Attributes.Traversing, true)
	player:SetAttribute(Constants.Attributes.Traversing, traversal.Kind)
	Net.Event("Traversal"):FireClient(player, "Begin", session.Token, {
		Kind = traversal.Kind,
		Path = path,
		StuckAt = stuckAt,
		Id = traversal.Id,
	})
end

function TraversalService._onStuck(self: TraversalService, player: Player, session: Session)
	if not session.StuckAt or session.StuckActive then
		return
	end
	session.StuckActive = true
	local root = rootOf(player)
	if not root then
		return
	end
	NoiseService.Emit(root.Position, TraversalConfig.Stuck.StruggleNoise * 0.6, "Struggle", player)
	-- A teammate nearby can pull them free.
	local holder = Instance.new("Attachment")
	holder.Name = "HelpPoint"
	holder.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Pull"
	prompt.ObjectText = "someone is stuck"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = TraversalConfig.Stuck.HelpRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = holder
	session.HelpPrompt = prompt
	prompt.Triggered:Connect(function(helper: Player)
		if helper == player or self._sessions[helper] then
			return
		end
		session.Effort += TraversalConfig.Stuck.HelpEffort
		Net.Event("Notify"):FireClient(player, "Help", "a hand grips your pack and pulls")
		self:_checkFreed(player, session)
	end)
end

function TraversalService._onStruggle(self: TraversalService, player: Player, session: Session)
	if not session.StuckActive then
		return
	end
	local now = os.clock()
	local minInterval = 1 / TraversalConfig.Stuck.MaxEffortPerSecond
	if now - session.LastStruggle < minInterval then
		return
	end
	session.LastStruggle = now
	session.Effort += 1
	local root = rootOf(player)
	if root then
		NoiseService.Emit(root.Position, TraversalConfig.Stuck.StruggleNoise, "Struggle", player)
	end
	self:_checkFreed(player, session)
end

function TraversalService._checkFreed(self: TraversalService, player: Player, session: Session)
	if session.StuckActive and session.Effort >= session.EffortNeeded then
		session.StuckActive = false
		session.StuckAt = nil
		if session.HelpPrompt then
			local holder = session.HelpPrompt.Parent
			if holder then
				holder:Destroy()
			end
			session.HelpPrompt = nil
		end
		Net.Event("Traversal"):FireClient(player, "Freed", session.Token)
	end
end

function TraversalService._onFinish(self: TraversalService, player: Player, session: Session, backedOut: boolean)
	local root = rootOf(player)
	if not root then
		self:_end(player, session)
		return
	end
	if session.StuckActive then
		-- Can't leave while wedged.
		return
	end
	local kind = TraversalConfig.Kinds[session.Traversal.Kind]
	local target = if backedOut then session.Path[1] else session.Path[#session.Path]
	local elapsed = os.clock() - session.Started
	local minTime = if backedOut then 0 else session.Length / (kind.Speed * kind.MinTimeFactor)
	local closeEnough = (root.Position - target).Magnitude < 12
	if not closeEnough or elapsed < minTime then
		-- Reject: return them to where they started.
		warn(`[Traversal] Rejected exit for {player.Name} (dist ok: {closeEnough}, {string.format("%.1f", elapsed)}s < {string.format("%.1f", minTime)}s)`)
		self:_abort(player, session)
		return
	end
	self:_end(player, session)
	if not backedOut then
		self.Completed:Fire(player, session.Traversal.Id, session.Traversal.Kind, session.Direction)
	end
end

-- Ends a session and returns the player to the start of the path.
function TraversalService._abort(self: TraversalService, player: Player, session: Session)
	local start = session.Path[1]
	self:_end(player, session)
	Net.Event("Traversal"):FireClient(player, "Abort", session.Token)
	PlayerService:Teleport(player, CFrame.new(start + Vector3.yAxis * 1))
end

function TraversalService._end(self: TraversalService, player: Player, session: Session)
	if self._sessions[player] ~= session then
		return
	end
	self._sessions[player] = nil
	if session.HelpPrompt then
		local holder = session.HelpPrompt.Parent
		if holder then
			holder:Destroy()
		end
	end
	local character = player.Character
	if character then
		character:SetAttribute(Constants.Attributes.Traversing, nil)
	end
	player:SetAttribute(Constants.Attributes.Traversing, nil)
end

function TraversalService.IsTraversing(self: TraversalService, player: Player): boolean
	return self._sessions[player] ~= nil
end

local instance: TraversalService = setmetatable({
	Completed = Signal.new(),
	_byId = {},
	_sessions = {},
	_token = 0,
	_rng = Random.new(),
	_folder = nil,
} :: State, TraversalService)

return instance
