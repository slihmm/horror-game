--!strict
-- Footsteps for every character in earshot, driven by distance travelled
-- rather than animation, so they stay correct for any rig or speed.
-- Steps react to surface material, stance, sprinting, wading and injury
-- (an injured player limps: uneven rhythm, scuffs). Your own steps play
-- "in your head"; everyone else's are 3D, so you hear teammates moving in
-- the dark without knowing exactly where.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AudioConfig = require(Shared.Config.AudioConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local AudioController = require(script.Parent.AudioController)
local MovementController = require(script.Parent.MovementController)

local LocalPlayer = Players.LocalPlayer

type Walker = {
	Last: Vector3,
	Travelled: number,
	Step: number,
}

local FootstepController = {}
FootstepController.__index = FootstepController

type State = {
	_walkers: { [Model]: Walker },
	_params: RaycastParams,
	_breath: Sound?,
	_rng: Random,
}
export type FootstepController = typeof(setmetatable({} :: State, FootstepController))

local cfg = AudioConfig.Footsteps

local function groupFor(material: Enum.Material): string
	return cfg.MaterialGroups[material] or "Stone"
end

function FootstepController.Init(self: FootstepController)
	self._params.FilterType = Enum.RaycastFilterType.Exclude
	self._params.IgnoreWater = false
	MovementController.Landed:Connect(function(peak: number)
		if peak < 18 then
			return
		end
		local hard = peak > PlayerConfig.Fall.SafeVelocity * 0.7
		AudioController:Play2D(if hard then "Land_Hard" else "Land_Soft", {
			Group = "Footsteps",
			Volume = math.clamp(peak / 60, 0.3, 1.2),
		})
		if peak > PlayerConfig.Fall.SafeVelocity then
			AudioController:Play2D("Hurt", { Group = "Voice", Volume = 0.8 })
		end
	end)
end

function FootstepController.Start(self: FootstepController)
	RunService.Heartbeat:Connect(function()
		self:_update()
	end)
end

function FootstepController._surfaceUnder(self: FootstepController, character: Model, root: BasePart): (Enum.Material?, boolean)
	self._params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(root.Position, Vector3.yAxis * -5.5, self._params)
	if not result then
		return nil, false
	end
	return result.Material, result.Material == Enum.Material.Water
end

function FootstepController._update(self: FootstepController)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local listener = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local isLocal = player == LocalPlayer
		if not isLocal and (root.Position - listener).Magnitude > cfg.MaxHearDistance then
			self._walkers[character] = nil
			continue
		end
		seen[character] = true
		local walker = self._walkers[character]
		local position = root.Position
		if not walker then
			walker = { Last = position, Travelled = 0, Step = 0 }
			self._walkers[character] = walker
		end
		local delta = position - walker.Last
		walker.Last = position
		local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
		-- Ignore teleports (recursion corridor, respawns) and airborne motion.
		if flat > 6 or character:GetAttribute(Constants.Attributes.Traversing) == true then
			walker.Travelled = 0
			continue
		end
		-- Humanoid states of other players don't replicate reliably, so for
		-- them grounding is decided by the floor raycast at step time.
		local state = humanoid:GetState()
		local grounded = not isLocal
			or state == Enum.HumanoidStateType.Running
			or state == Enum.HumanoidStateType.RunningNoPhysics
			or state == Enum.HumanoidStateType.Swimming
		if not grounded or math.abs(delta.Y) > 3 then
			continue
		end
		walker.Travelled += flat
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local crouched = character:GetAttribute(Constants.Attributes.Stance) == Constants.Stances.Crouch
		local injured = character:GetAttribute(Constants.Attributes.Injured) == true
		local sprinting = speed > PlayerConfig.Movement.WalkSpeed + 2
		local stride = if crouched then cfg.StrideCrouch elseif sprinting then cfg.StrideSprint else cfg.StrideWalk
		if injured then
			-- Limp: alternate short and long strides.
			stride *= if walker.Step % 2 == 0 then 0.72 else 1.28
		end
		if walker.Travelled >= stride then
			walker.Travelled = 0
			walker.Step += 1
			self:_playStep(character, root, isLocal, crouched, sprinting, injured, state == Enum.HumanoidStateType.Swimming)
		end
	end
	for character in self._walkers do
		if not seen[character] then
			self._walkers[character] = nil
		end
	end
	self:_updateBreath()
end

function FootstepController._playStep(self: FootstepController, character: Model, root: BasePart, isLocal: boolean, crouched: boolean, sprinting: boolean, injured: boolean, swimming: boolean)
	local material, water = self:_surfaceUnder(character, root)
	if not material and not swimming then
		return
	end
	local volume = if crouched then cfg.StanceVolume.Crouch elseif sprinting then cfg.StanceVolume.Sprint else cfg.StanceVolume.Walk
	local sound: string
	if swimming or water then
		sound = "Wade"
	else
		sound = "Step_" .. groupFor(material :: Enum.Material)
	end
	if injured and self._rng:NextNumber() < 0.3 then
		volume *= 1.25 -- a dragged, scuffing step
	end
	local feet = root.Position - Vector3.yAxis * 2.8
	if isLocal then
		AudioController:Play2D(sound, { Group = "Footsteps", Volume = volume * 0.55 })
	else
		AudioController:PlayAt(sound, feet, {
			Group = "Footsteps",
			Volume = volume * 1.2,
			MinDistance = 5,
			MaxDistance = cfg.MaxHearDistance,
		})
	end
end

-- Heavy breathing after sprinting, in the player's own head.
function FootstepController._updateBreath(self: FootstepController)
	local deficit = 1 - MovementController.Stamina
	local wanted = MovementController.Exhausted or deficit > 0.55
	local breath = self._breath
	if wanted and not breath then
		local created = AudioController:Play2D("BreathExhausted", { Group = "Voice", Looped = true, Jitter = false })
		self._breath = created
		breath = created
	end
	if breath then
		if not wanted and deficit < 0.3 then
			breath:Destroy()
			self._breath = nil
		else
			breath.Volume = 0.06 + deficit * 0.18
		end
	end
end

local instance: FootstepController = setmetatable({
	_walkers = {},
	_params = RaycastParams.new(),
	_breath = nil,
	_rng = Random.new(),
} :: State, FootstepController)

return instance
