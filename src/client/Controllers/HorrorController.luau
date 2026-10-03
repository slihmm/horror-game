--!strict
-- Performs Horror Director events on this client only.
--
-- Shadow figures follow one rule that makes them unsettling instead of
-- gamey: they exist only until you have seen them and look away. Approach
-- one and it is gone. Turn your head and it is gone. You can never confirm
-- what you saw, and nobody else saw it at all.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local AudioController = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local HeadlampController = require(script.Parent.HeadlampController)
local RecursionController = require(script.Parent.RecursionController)
local UIController = require(script.Parent.UIController)

local LocalPlayer = Players.LocalPlayer

export type FigureOptions = {
	Duration: number?,
	-- Vanish once it has been seen and then leaves view (default true).
	VanishWhenSeen: boolean?,
	-- Vanish when the player comes within this distance.
	ApproachDistance: number?,
	-- Walk along these points.
	Path: { Vector3 }?,
	Speed: number?,
	-- Keep turning to face the player while unobserved.
	Watch: boolean?,
	Group: string?,
}

type Figure = {
	Model: Model,
	Root: BasePart,
	Legs: { { Part: BasePart, Offset: CFrame } },
	Options: FigureOptions,
	Spawned: number,
	Seen: boolean,
	SeenTime: number,
	PathIndex: number,
	Position: Vector3,
	Facing: Vector3,
	StepTravel: number,
}

local HorrorController = {}
HorrorController.__index = HorrorController

type State = {
	_figures: { Figure },
	_template: Model?,
	_rng: Random,
	_terrainParams: RaycastParams,
	_folder: Folder?,
	_propCache: { Model }?,
	_handlers: { [string]: (any) -> () },
}
export type HorrorController = typeof(setmetatable({} :: State, HorrorController))

local FIGURE_COLOR = Color3.fromRGB(6, 6, 7)

local function camera(): Camera
	return Workspace.CurrentCamera :: Camera
end

local function buildTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "Figure"
	local function limb(name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		p.Size = size
		p.CFrame = cf
		p.Color = FIGURE_COLOR
		p.Material = Enum.Material.Fabric
		p.Reflectance = 0
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	-- Pivot at the feet, facing -Z. About the height of a person in gear.
	local root = limb("Root", Vector3.new(1.9, 2.3, 1), CFrame.new(0, 3.95, 0))
	limb("Hips", Vector3.new(1.8, 0.9, 0.95), CFrame.new(0, 2.6, 0))
	limb("Head", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, 5.75, 0.05), Enum.PartType.Ball)
	limb("Neck", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 5.2, 0))
	limb("Pack", Vector3.new(1.5, 1.9, 0.8), CFrame.new(0, 4.05, 0.85))
	for _, x in { -1.2, 1.2 } do
		limb("Arm", Vector3.new(0.5, 2.5, 0.55), CFrame.new(x, 3.75, 0) * CFrame.Angles(0, 0, math.rad(x * 2)))
	end
	for _, x in { -0.48, 0.48 } do
		limb(if x < 0 then "LegL" else "LegR", Vector3.new(0.65, 2.3, 0.7), CFrame.new(x, 1.15, 0))
	end
	model.PrimaryPart = root
	model.WorldPivot = CFrame.identity
	return model
end

function HorrorController.Init(self: HorrorController)
	self._template = buildTemplate()
	local folder = Instance.new("Folder")
	folder.Name = Constants.Folders.ClientEffects
	folder.Parent = Workspace
	self._folder = folder
	self._terrainParams.FilterType = Enum.RaycastFilterType.Include
	self._terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
	self:_registerHandlers()
end

function HorrorController.Start(self: HorrorController)
	Net.Event("HorrorEvent").OnClientEvent:Connect(function(name: string, params: any)
		local handler = self._handlers[name]
		if handler then
			task.spawn(handler, if type(params) == "table" then params else {})
		end
	end)
	Net.Event("WorldEffect").OnClientEvent:Connect(function(kind: string, position: Vector3, params: any)
		self:_worldEffect(kind, position, if type(params) == "table" then params else {})
	end)
	RecursionController.LapCompleted:Connect(function(lap: number, corridor: any)
		self:_onRecursionLap(lap, corridor)
	end)
	LocalPlayer:GetAttributeChangedSignal(Constants.Attributes.Zone):Connect(function()
		-- Leaving the Gathering empties it.
		if LocalPlayer:GetAttribute(Constants.Attributes.Zone) ~= "FinalChamber" then
			self:ClearGroup("Crowd")
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		self:_updateFigures(dt)
	end)
end

-- Geometry helpers ----------------------------------------------------------------

function HorrorController._floorAt(self: HorrorController, position: Vector3): Vector3?
	local hit = Workspace:Raycast(position + Vector3.yAxis * 4, Vector3.yAxis * -16, self._terrainParams)
	return if hit then hit.Position else nil
end

function HorrorController._lineOfSight(self: HorrorController, from: Vector3, to: Vector3): boolean
	return Workspace:Raycast(from, to - from, self._terrainParams) == nil
end

-- Angle (degrees) between the view direction and a world point.
local function viewAngle(position: Vector3): number
	local cf = camera().CFrame
	local dir = position - cf.Position
	if dir.Magnitude < 0.01 then
		return 0
	end
	return math.deg(math.acos(math.clamp(cf.LookVector:Dot(dir.Unit), -1, 1)))
end

function HorrorController._inView(self: HorrorController, position: Vector3): boolean
	local cam = camera()
	local _, onScreen = cam:WorldToViewportPoint(position)
	return onScreen and self:_lineOfSight(cam.CFrame.Position, position)
end

-- Figures ------------------------------------------------------------------------------

function HorrorController.ShowFigure(self: HorrorController, position: Vector3, lookAt: Vector3?, options: FigureOptions?): Model?
	local template = self._template
	local folder = self._folder
	if not template or not folder then
		return nil
	end
	local opts = options or {}
	local floor = self:_floorAt(position) or position
	local model = template:Clone()
	local face = if lookAt then Vector3.new(lookAt.X - floor.X, 0, lookAt.Z - floor.Z) else Vector3.zAxis
	face = if face.Magnitude > 0.01 then face.Unit else Vector3.zAxis
	model:PivotTo(CFrame.lookAt(floor, floor + face))
	model.Parent = folder
	local legs = {}
	for _, name in { "LegL", "LegR" } do
		local leg = model:FindFirstChild(name) :: BasePart?
		if leg then
			table.insert(legs, { Part = leg, Offset = model:GetPivot():ToObjectSpace(leg.CFrame) })
		end
	end
	table.insert(self._figures, {
		Model = model,
		Root = model.PrimaryPart :: BasePart,
		Legs = legs,
		Options = opts,
		Spawned = os.clock(),
		Seen = false,
		SeenTime = 0,
		PathIndex = 1,
		Position = floor,
		Facing = face,
		StepTravel = 0,
	})
	return model
end

function HorrorController.ClearGroup(self: HorrorController, group: string)
	for i = #self._figures, 1, -1 do
		local figure = self._figures[i]
		if figure.Options.Group == group then
			figure.Model:Destroy()
			table.remove(self._figures, i)
		end
	end
end

function HorrorController._updateFigures(self: HorrorController, dt: number)
	if #self._figures == 0 then
		return
	end
	local cam = camera()
	local eye = cam.CFrame.Position
	local now = os.clock()
	for i = #self._figures, 1, -1 do
		local figure = self._figures[i]
		local opts = figure.Options
		local head = figure.Position + Vector3.yAxis * 5.4
		local distance = (head - eye).Magnitude
		local visible = self:_inView(head)
		local remove = false
		if opts.Duration and now - figure.Spawned > opts.Duration then
			remove = true
		end
		if distance < (opts.ApproachDistance or 20) then
			remove = true
		end
		if visible then
			if not figure.Seen then
				figure.Seen = true
				figure.SeenTime = now
			end
		elseif figure.Seen and opts.VanishWhenSeen ~= false and now - figure.SeenTime > 0.25 then
			-- Seen, then looked away from: gone.
			remove = true
		end

		-- Walking figures.
		local path = opts.Path
		if path and not remove then
			local target = path[figure.PathIndex]
			if not target then
				remove = true
			else
				local delta = Vector3.new(target.X - figure.Position.X, 0, target.Z - figure.Position.Z)
				local step = (opts.Speed or 6) * dt
				if delta.Magnitude <= step then
					figure.PathIndex += 1
				else
					figure.Facing = delta.Unit
				end
				local move = if delta.Magnitude > 0 then delta.Unit * math.min(step, delta.Magnitude) else Vector3.zero
				local nextPos = figure.Position + move
				local floor = self:_floorAt(nextPos)
				figure.Position = Vector3.new(nextPos.X, if floor then floor.Y else target.Y, nextPos.Z)
				figure.StepTravel += move.Magnitude
				local swing = math.sin(figure.StepTravel * 1.4) * 0.5
				local pivot = CFrame.lookAt(figure.Position, figure.Position + figure.Facing)
				figure.Model:PivotTo(pivot)
				for k, leg in figure.Legs do
					local sign = if k == 1 then 1 else -1
					leg.Part.CFrame = pivot * CFrame.new(0, 2.3, 0) * CFrame.Angles(swing * sign, 0, 0) * CFrame.new(0, -2.3, 0) * leg.Offset
				end
				if figure.StepTravel > 4 then
					figure.StepTravel = 0
					if distance < 70 then
						AudioController:PlayAt("DistantFootsteps", figure.Position, { Group = "Footsteps", Volume = 0.5, MaxDistance = 70 })
					end
				end
			end
		elseif opts.Watch and not visible and not remove then
			-- Turns toward you only while you aren't looking.
			local toPlayer = Vector3.new(eye.X - figure.Position.X, 0, eye.Z - figure.Position.Z)
			if toPlayer.Magnitude > 0.1 then
				figure.Facing = figure.Facing:Lerp(toPlayer.Unit, math.min(1, dt * 0.8)).Unit
				figure.Model:PivotTo(CFrame.lookAt(figure.Position, figure.Position + figure.Facing))
			end
		end

		if remove then
			figure.Model:Destroy()
			table.remove(self._figures, i)
		end
	end
end

-- World effects ---------------------------------------------------------------------------

function HorrorController._worldEffect(self: HorrorController, kind: string, position: Vector3, params: { [string]: any })
	if kind == "Sound" then
		local sound = if type(params.Sound) == "string" then params.Sound else nil
		if sound then
			AudioController:PlayAt(sound, position, {
				Group = "Effects",
				Volume = params.Volume,
				Pitch = params.Pitch,
				MaxDistance = params.MaxDistance,
				MinDistance = 14,
				Delay = params.Delay,
			})
		end
		local shake = params.Shake
		if type(shake) == "number" then
			local distance = (camera().CFrame.Position - position).Magnitude
			CameraController:AddTrauma(shake * math.clamp(1 - distance / 140, 0, 1))
		end
	elseif kind == "Dust" then
		self:_dustBurst(position, if type(params.Amount) == "number" then params.Amount else 1)
	end
end

function HorrorController._dustBurst(self: HorrorController, position: Vector3, amount: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(6, 1, 6)
	holder.CFrame = CFrame.new(position)
	holder.Parent = self._folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Size = NumberSequence.new(0.1, 0.4)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.LightInfluence = 1
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 140, 125))
	emitter.Parent = holder
	emitter:Emit(math.floor(40 * amount))
	task.delay(5, function()
		holder:Destroy()
	end)
end

-- Event handlers ----------------------------------------------------------------------------

function HorrorController._behind(self: HorrorController, distance: number): Vector3
	local cf = camera().CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	return cf.Position - flat * distance
end

function HorrorController._registerHandlers(self: HorrorController)
	local rng = self._rng
	local h = self._handlers

	h.DistantFootsteps = function(params)
		local position = params.Position :: Vector3
		local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 1.8
		AudioController:Burst("DistantFootsteps", position, params.Count or 6, NumberRange.new(0.45, 0.62), { Group = "Footsteps", Volume = 0.8, MaxDistance = 140, MinDistance = 10 }, drift)
	end

	h.FootstepsBehind = function(params)
		-- Steps that keep pace behind you and stop the moment you turn.
		local startLook = camera().CFrame.LookVector
		for _ = 1, params.Count or 4 do
			if camera().CFrame.LookVector:Dot(startLook) < 0.6 then
				return
			end
			AudioController:PlayAt("Step_Stone", self:_behind(params.Distance or 10), { Group = "Footsteps", Volume = 0.7, MaxDistance = 40 })
			task.wait(rng:NextNumber(0.5, 0.62))
		end
	end

	h.ShadowSighting = function(params)
		local candidates = params.Candidates :: { Vector3 }
		local eye = camera().CFrame.Position
		local best: Vector3? = nil
		local bestScore = -math.huge
		for _, position in candidates do
			local head = position + Vector3.yAxis * 5
			if self:_lineOfSight(eye, head) then
				-- Prefer the edge of vision: noticed, not presented.
				local angle = viewAngle(head)
				local score = -math.abs(angle - 32)
				if score > bestScore then
					best, bestScore = position, score
				end
			end
		end
		if best then
			self:ShowFigure(best, eye, { Duration = params.Duration, ApproachDistance = 24 })
		end
	end

	h.ShadowBehind = function(params)
		local position = self:_behind(params.Distance or 10)
		if self:_lineOfSight(camera().CFrame.Position, position + Vector3.yAxis * 4) then
			self:ShowFigure(position, camera().CFrame.Position, { Duration = params.Duration, ApproachDistance = 6 })
			AudioController:PlayAt("FaintBreathing", position + Vector3.yAxis * 5, { Group = "Voice", Volume = 0.6, MaxDistance = 25 })
		end
	end

	h.EchoWalker = function(params)
		local path = params.Path :: { Vector3 }
		if #path < 2 then
			return
		end
		self:ShowFigure(path[1], path[2], { Path = path, Speed = params.Speed, ApproachDistance = 18, Duration = 40 })
	end

	h.BeamGlint = function(params)
		-- A pair of points at the edge of the beam, reflecting it back.
		local cf = camera().CFrame
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local dir = (cf * CFrame.Angles(math.rad(rng:NextNumber(-4, 2)), math.rad(side * rng:NextNumber(16, 24)), 0)).LookVector
		local distance = params.Distance or 35
		local hit = Workspace:Raycast(cf.Position, dir * distance, self._terrainParams)
		local at = if hit then hit.Position - dir * 2 else cf.Position + dir * distance
		local right = dir:Cross(Vector3.yAxis).Unit
		local eyes = {}
		for _, offset in { -0.32, 0.32 } do
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.14, 0.14, 0.14)
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(150, 140, 110)
			p.Transparency = 0.25
			p.CFrame = CFrame.new(at + right * offset)
			p.Parent = self._folder
			table.insert(eyes, p)
		end
		local deadline = os.clock() + (params.Duration or 1.5)
		while os.clock() < deadline do
			-- Gone the moment the beam's center lands on them.
			if viewAngle(at) < 6 then
				break
			end
			task.wait()
		end
		for _, p in eyes do
			p:Destroy()
		end
	end

	h.LightFlicker = function(params)
		HeadlampController:Flicker(params.Duration or 2, params.Severity or 0.8)
	end

	h.TemporaryDarkness = function(params)
		HeadlampController:Darkness(params.Duration or 3)
		CameraController:SetExtraBreath(0.05)
		task.delay((params.Duration or 3) + 2, function()
			CameraController:SetExtraBreath(0)
		end)
	end

	h.DistantScream = function(params)
		local distance = params.Distance or 180
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.1), rng:NextNumber(-1, 1)).Unit
		AudioController:PlayAt("DistantScream", camera().CFrame.Position + dir * distance, { Group = "Ambient", Volume = 0.8, MinDistance = 40, MaxDistance = distance + 80 })
	end

	h.ObjectShift = function(params)
		self:_objectShift(params.Radius or 25)
	end

	h.WaterDisturbance = function(params)
		local position = params.Position :: Vector3
		AudioController:PlayAt("WaterMovement", position, { Group = "Ambient", Volume = 1, MaxDistance = 70 })
		local surfaceParams = RaycastParams.new()
		surfaceParams.FilterType = Enum.RaycastFilterType.Include
		surfaceParams.FilterDescendantsInstances = { Workspace.Terrain }
		surfaceParams.IgnoreWater = false
		local hit = Workspace:Raycast(position + Vector3.yAxis * 6, Vector3.yAxis * -12, surfaceParams)
		if hit and hit.Material == Enum.Material.Water then
			for k = 0, 2 do
				task.delay(k * 0.35, function()
					local ring = Instance.new("Part")
					ring.Anchored = true
					ring.CanCollide = false
					ring.CanQuery = false
					ring.Shape = Enum.PartType.Cylinder
					ring.Material = Enum.Material.Glass
					ring.Color = Color3.fromRGB(180, 200, 210)
					ring.Transparency = 0.6
					ring.Size = Vector3.new(0.05, 0.5, 0.5)
					ring.CFrame = CFrame.new(hit.Position + Vector3.yAxis * 0.05) * CFrame.Angles(0, 0, math.rad(90))
					ring.Parent = self._folder
					local tween = TweenService:Create(ring, TweenInfo.new(2.5), { Size = Vector3.new(0.05, 9, 9), Transparency = 1 })
					tween.Completed:Once(function()
						ring:Destroy()
					end)
					tween:Play()
				end)
			end
		end
	end

	h.DistantMonster = function(params)
		local position = params.Position :: Vector3
		for _ = 1, params.Steps or 4 do
			AudioController:PlayAt("MonsterStep", position, { Group = "Monster", Volume = 0.7, MinDistance = 60, MaxDistance = 400 })
			CameraController:AddTrauma(0.03)
			task.wait(rng:NextNumber(1.6, 2.3))
		end
	end

	h.Silence = function(params)
		AudioController:Silence(params.Duration or 25)
	end

	h.Knocking = function(params)
		local eye = camera().CFrame.Position
		local best: Vector3? = nil
		for i = 0, 7 do
			local angle = i / 8 * math.pi * 2
			local hit = Workspace:Raycast(eye, Vector3.new(math.cos(angle), 0, math.sin(angle)) * 14, self._terrainParams)
			if hit and (not best or (hit.Position - eye).Magnitude < (best - eye).Magnitude) then
				best = hit.Position
			end
		end
		if not best then
			return
		end
		for _ = 1, params.Count or 3 do
			AudioController:PlayAt("Knock", best, { Group = "Effects", Volume = 0.9, MaxDistance = 40, Jitter = false })
			task.wait(0.62)
		end
	end

	h.Whisper = function()
		AudioController:PlayAt("Whisper", self:_behind(2.5) + Vector3.yAxis * 0.5, { Group = "Voice", Volume = 0.7, MaxDistance = 12 })
	end

	h.MimicVoice = function(params)
		AudioController:PlayAt(params.Sound, params.Position, { Group = "Voice", Volume = 1, MinDistance = 8, MaxDistance = 90 })
	end

	h.MimicFootsteps = function(params)
		local position = params.Position :: Vector3
		local eye = camera().CFrame.Position
		local toward = Vector3.new(eye.X - position.X, 0, eye.Z - position.Z)
		toward = if toward.Magnitude > 0.01 then toward.Unit * 1.9 else Vector3.zero
		AudioController:Burst("Step_Stone", position, params.Count or 8, NumberRange.new(0.48, 0.58), { Group = "Footsteps", Volume = 1, MaxDistance = 90 }, toward)
	end

	h.LandmarkShift = function(params)
		self:_landmarkShift(params.Id, params.Mutation)
	end

	h.Crowd = function(params)
		-- The bottom is full of people. They do not move while you look.
		local center = params.Center :: Vector3
		for _, position in params.Positions :: { Vector3 } do
			self:ShowFigure(position, center + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)), {
				VanishWhenSeen = false,
				ApproachDistance = 16,
				Watch = true,
				Group = "Crowd",
			})
			task.wait()
		end
		UIController:Whisper("you are not alone down here. you never were", 5)
	end
end

-- Moves a small prop behind the player when they're not looking.
function HorrorController._objectShift(self: HorrorController, radius: number)
	local cache: { Model } = self._propCache or {}
	if not self._propCache then
		local cave = Workspace:FindFirstChild(Constants.Folders.Cave)
		local props = cave and cave:FindFirstChild(Constants.Folders.Props)
		if props then
			local movable = { Backpack = true, Boot = true, Lantern = true, Helmet = true, Journal = true, Headlamp = true, Flashlight = true, Camera = true }
			for _, model in props:GetDescendants() do
				if model:IsA("Model") and movable[model.Name] then
					table.insert(cache, model)
				end
			end
		end
		self._propCache = cache
	end
	local eye = camera().CFrame.Position
	local options = {}
	for _, model in cache do
		if model.Parent then
			local p = model:GetPivot().Position
			if (p - eye).Magnitude < radius and not self:_inView(p + Vector3.yAxis) then
				table.insert(options, model)
			end
		end
	end
	if #options == 0 then
		return
	end
	local model = options[self._rng:NextInteger(1, #options)]
	local pivot = model:GetPivot()
	local offset = Vector3.new(self._rng:NextNumber(-1.8, 1.8), 0, self._rng:NextNumber(-1.8, 1.8))
	model:PivotTo(CFrame.new(offset) * pivot * CFrame.Angles(0, self._rng:NextNumber(-1, 1), 0))
	AudioController:PlayAt("Scrape", pivot.Position, { Group = "Effects", Volume = 0.6, MaxDistance = 40 })
end

function HorrorController._landmarkShift(self: HorrorController, id: string, mutation: string)
	local landmark: Model? = nil
	for _, instance in CollectionService:GetTagged(Constants.Tags.Landmark) do
		if instance:IsA("Model") and instance:GetAttribute("LandmarkId") == id then
			landmark = instance
		end
	end
	if not landmark then
		return
	end
	local pivot = landmark:GetPivot()
	local eye = camera().CFrame.Position
	local toPlayer = Vector3.new(eye.X - pivot.Position.X, 0, eye.Z - pivot.Position.Z)
	toPlayer = if toPlayer.Magnitude > 0.01 then toPlayer.Unit else pivot.LookVector
	if mutation == "Moved" then
		landmark:PivotTo(pivot + pivot.RightVector * 3.5 + pivot.LookVector * 1.5)
	elseif mutation == "Turned" then
		landmark:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + toPlayer))
	elseif mutation == "Gone" then
		for _, part in landmark:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
				part.Transparency = 1
			end
		end
	elseif mutation == "Flashlight" then
		-- A flashlight in its lap that wasn't there before. It's on.
		local torch = Instance.new("Part")
		torch.Anchored = true
		torch.CanCollide = false
		torch.CanQuery = false
		torch.Shape = Enum.PartType.Cylinder
		torch.Size = Vector3.new(1.4, 0.35, 0.35)
		torch.Material = Enum.Material.Metal
		torch.Color = Color3.fromRGB(30, 30, 32)
		local at = pivot.Position + Vector3.yAxis * 1.1 + pivot.LookVector * 0.8
		torch.CFrame = CFrame.lookAt(at, eye) * CFrame.Angles(0, math.rad(90), 0)
		torch.Parent = self._folder
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Right
		light.Angle = 40
		light.Range = 30
		light.Brightness = 1.4
		light.Shadows = true
		light.Color = Color3.fromRGB(255, 236, 200)
		light.Parent = torch
	elseif mutation == "Watcher" then
		self:ShowFigure(pivot.Position - pivot.LookVector * 5, eye, { ApproachDistance = 12, Duration = 30 })
	end
end

function HorrorController._onRecursionLap(self: HorrorController, lap: number, corridor: any)
	local origin = corridor.Origin :: Vector3
	local axis = corridor.Axis :: Vector3
	local side = corridor.Side :: Vector3
	local length = corridor.ModuleLength :: number
	if lap == 1 then
		AudioController:PlayAt("Unidentifiable", origin + axis * length * (corridor.Modules - 0.5), { Group = "Ambient", Volume = 0.6, MaxDistance = 200 })
	elseif lap == 2 then
		-- A chalk mark you don't remember making.
		local wall = Workspace:Raycast(origin + axis * length * 5 + Vector3.yAxis * 4, side * 14, self._terrainParams)
		if wall then
			local mark = Instance.new("Part")
			mark.Anchored = true
			mark.CanCollide = false
			mark.CanQuery = false
			mark.Transparency = 1
			mark.Size = Vector3.new(2, 2, 0.05)
			mark.CFrame = CFrame.lookAt(wall.Position + wall.Normal * 0.1, wall.Position + wall.Normal)
			mark.Parent = self._folder
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.LightInfluence = 1
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.Parent = mark
			local text = Instance.new("TextLabel")
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			text.Text = "X"
			text.TextScaled = true
			text.Font = Enum.Font.PermanentMarker
			text.TextColor3 = Color3.fromRGB(225, 225, 218)
			text.TextTransparency = 0.15
			text.Parent = gui
		end
	elseif lap >= 3 then
		-- Someone standing at the far end, where the corridor should open.
		self:ShowFigure(origin + axis * length * (corridor.Modules - 1.2), camera().CFrame.Position, { ApproachDistance = 30, Duration = 25 })
	end
end

local instance: HorrorController = setmetatable({
	_figures = {},
	_template = nil,
	_rng = Random.new(),
	_terrainParams = RaycastParams.new(),
	_folder = nil,
	_propCache = nil,
	_handlers = {},
} :: State, HorrorController)

return instance
