--!strict
-- The corridor that is longer than it is.
--
-- The corridor between the Deep Cave and the Abandoned Camp is built from
-- identical modules whose length is a multiple of the terrain voxel size,
-- so every module looks exactly the same. When the player walks past the
-- trigger module, they are shifted back by whole modules in the same frame,
-- before the camera updates. Nothing visibly changes. They just keep walking.
--
-- After a few laps the loop lets them go. Other systems (the Horror
-- controller) listen to LapCompleted to add small wrong details per lap.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utility.Signal)

local TraversalController = require(script.Parent.TraversalController)

local LocalPlayer = Players.LocalPlayer

type Corridor = {
	Origin: Vector3,
	Axis: Vector3,
	Side: Vector3,
	ModuleLength: number,
	Modules: number,
	TriggerModule: number,
	TeleportModules: number,
	LapsMin: number,
	LapsMax: number,
	Radius: number,
}

local RecursionController = {}
RecursionController.__index = RecursionController

type State = {
	LapCompleted: Signal.Signal<number, Corridor>,
	Released: Signal.Signal<Corridor>,
	_corridor: Corridor?,
	_inside: boolean,
	_lastAlong: number,
	_laps: number,
	_targetLaps: number,
	_visitDone: boolean,
	_lastVisit: number,
	_rng: Random,
}
export type RecursionController = typeof(setmetatable({} :: State, RecursionController))

-- After a completed loop, the next visit only loops again after this long.
local REVISIT_COOLDOWN = 900

local function readCorridor(marker: Instance): Corridor?
	if not marker:IsA("BasePart") then
		return nil
	end
	local cf = marker.CFrame
	local function num(name: string, fallback: number): number
		local value = marker:GetAttribute(name)
		return if type(value) == "number" then value else fallback
	end
	return {
		Origin = cf.Position,
		Axis = cf.LookVector,
		Side = cf.LookVector:Cross(Vector3.yAxis).Unit,
		ModuleLength = num("ModuleLength", 24),
		Modules = num("Modules", 9),
		TriggerModule = num("TriggerModule", 6),
		TeleportModules = num("TeleportModules", 2),
		LapsMin = num("LapsMin", 2),
		LapsMax = num("LapsMax", 4),
		Radius = num("Radius", 7),
	}
end

function RecursionController.Start(self: RecursionController)
	local function onMarker(marker: Instance)
		self._corridor = readCorridor(marker)
	end
	CollectionService:GetInstanceAddedSignal(Constants.Tags.RecursionCorridor):Connect(onMarker)
	for _, marker in CollectionService:GetTagged(Constants.Tags.RecursionCorridor) do
		onMarker(marker)
	end
	-- Runs before the camera so the shift is invisible.
	RunService:BindToRenderStep("DescentRecursion", Enum.RenderPriority.Input.Value + 1, function()
		self:_update()
	end)
end

function RecursionController._update(self: RecursionController)
	local corridor = self._corridor
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not corridor or not character or not root or TraversalController:IsActive() then
		return
	end
	local rel = root.Position - corridor.Origin
	local along = rel:Dot(corridor.Axis)
	local lateral = rel:Dot(corridor.Side)
	local length = corridor.Modules * corridor.ModuleLength
	local inside = along > 0 and along < length and math.abs(lateral) < corridor.Radius + 3 and math.abs(rel.Y) < 16

	if inside and not self._inside then
		-- Entering: decide how many laps this visit lasts.
		local now = os.clock()
		if now - self._lastVisit > REVISIT_COOLDOWN or self._lastVisit == 0 then
			self._laps = 0
			self._targetLaps = self._rng:NextInteger(corridor.LapsMin, corridor.LapsMax)
			self._visitDone = false
		end
		self._lastAlong = along
	end
	self._inside = inside
	if not inside then
		return
	end

	local trigger = corridor.TriggerModule * corridor.ModuleLength
	if not self._visitDone and self._lastAlong < trigger and along >= trigger then
		-- Shift back by whole modules: identical geometry, invisible jump.
		local shift = -corridor.Axis * (corridor.TeleportModules * corridor.ModuleLength)
		character:PivotTo(character:GetPivot() + shift)
		self._laps += 1
		along += shift:Dot(corridor.Axis)
		self.LapCompleted:Fire(self._laps, corridor)
		if self._laps >= self._targetLaps then
			self._visitDone = true
			self._lastVisit = os.clock()
			self.Released:Fire(corridor)
		end
	end
	self._lastAlong = along
end

function RecursionController.GetCorridor(self: RecursionController): Corridor?
	return self._corridor
end

local instance: RecursionController = setmetatable({
	LapCompleted = Signal.new(),
	Released = Signal.new(),
	_corridor = nil,
	_inside = false,
	_lastAlong = 0,
	_laps = 0,
	_targetLaps = 0,
	_visitDone = false,
	_lastVisit = 0,
	_rng = Random.new(),
} :: State, RecursionController)

return instance
