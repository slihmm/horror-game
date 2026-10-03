--!strict
-- The cave does not keep its shape.
--
-- The ring: the way on is sealed until someone has walked all the way round
-- and passed the skeleton a second time. Then the passage is simply there,
-- and the skeleton is not quite how they left it. Mutations are sent to the
-- individual player, so two teammates may remember the room differently.
--
-- (The recursion corridor runs entirely on the client: see
-- RecursionController.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local HorrorConfig = require(Shared.Config.HorrorConfig)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local HazardService = require(Services.HazardService)

local RING_FALLBACK_SECONDS = 360
local MUTATIONS = { "Moved", "Flashlight", "Turned", "Gone", "Watcher" }

type LandmarkState = {
	Passes: number,
	Away: boolean,
	Mutated: { [string]: boolean },
}

local DisorientationService = {}
DisorientationService.__index = DisorientationService

type State = {
	_landmarks: { [Player]: { [string]: LandmarkState } },
	_ringTime: { [Player]: number },
	_rng: Random,
}
export type DisorientationService = typeof(setmetatable({} :: State, DisorientationService))

function DisorientationService.Start(self: DisorientationService)
	CaveService:WaitUntilReady()
	Players.PlayerRemoving:Connect(function(player: Player)
		self._landmarks[player] = nil
		self._ringTime[player] = nil
	end)
	while true do
		task.wait(0.5)
		self:_tick(0.5)
	end
end

function DisorientationService._tick(self: DisorientationService, dt: number)
	local dressing = CaveService.Dressing
	if not dressing then
		return
	end
	for _, player in Players:GetPlayers() do
		local track = CaveService:GetTrack(player)
		if not track then
			continue
		end
		local perPlayer = self._landmarks[player]
		if not perPlayer then
			perPlayer = {}
			self._landmarks[player] = perPlayer
		end
		for id, landmark in dressing.Landmarks do
			local state = perPlayer[id]
			if not state then
				state = { Passes = 0, Away = true, Mutated = {} }
				perPlayer[id] = state
			end
			local distance = (track.Position - landmark.Position).Magnitude
			if distance < HorrorConfig.LandmarkRadius then
				if state.Away then
					state.Away = false
					state.Passes += 1
					self:_onPass(player, id, state)
				end
			elseif distance > HorrorConfig.LandmarkLeaveDistance then
				state.Away = true
			end
		end
		-- Fallback: never trap anyone in the ring forever.
		if track.InAnchor == "Ring" then
			self._ringTime[player] = (self._ringTime[player] or 0) + dt
			if self._ringTime[player] > RING_FALLBACK_SECONDS and not CaveService:IsRingOpen() then
				self:_openRing()
			end
		end
	end
end

function DisorientationService._onPass(self: DisorientationService, player: Player, landmarkId: string, state: LandmarkState)
	if state.Passes < 2 then
		return
	end
	if landmarkId == "RingSkeleton" and not CaveService:IsRingOpen() then
		self:_openRing()
	end
	-- Each further pass shows something new, until the variations run out.
	local available = {}
	for _, mutation in MUTATIONS do
		if not state.Mutated[mutation] then
			table.insert(available, mutation)
		end
	end
	if #available == 0 then
		return
	end
	local mutation = available[self._rng:NextInteger(1, #available)]
	state.Mutated[mutation] = true
	Net.Event("HorrorEvent"):FireClient(player, "LandmarkShift", { Id = landmarkId, Mutation = mutation, Pass = state.Passes })
end

function DisorientationService._openRing(self: DisorientationService)
	local dressing = CaveService.Dressing
	local seal = dressing and dressing.RingSeal
	CaveService:OpenRingSeal()
	if seal then
		local position = seal.CFrame.Position
		-- Heard, not seen: stone shifting somewhere around the loop.
		HazardService:Broadcast("Sound", position, { Sound = "Rumble", Volume = 1, MaxDistance = 220, Shake = 0.12 }, 260)
		HazardService:Broadcast("Sound", position, { Sound = "RockFall", Volume = 0.8, MaxDistance = 200, Delay = 0.8 }, 260)
	end
end

local instance: DisorientationService = setmetatable({
	_landmarks = {},
	_ringTime = {},
	_rng = Random.new(),
} :: State, DisorientationService)

return instance
