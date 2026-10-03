--!strict
-- Scripted camera moments: the first arrival, waking at camp, death, and the
-- ending. They are short and quiet. The ending gives the player a moment of
-- relief, then lets something small go wrong.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local LightingConfig = require(Shared.Config.LightingConfig)
local MathUtil = require(Shared.Utility.MathUtil)

local AudioController = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local HeadlampController = require(script.Parent.HeadlampController)
local HorrorController = require(script.Parent.HorrorController)
local LightingController = require(script.Parent.LightingController)
local MovementController = require(script.Parent.MovementController)
local UIController = require(script.Parent.UIController)

local LocalPlayer = Players.LocalPlayer

local DEATH_LINES: { [string]: string } = {
	Monster = "it took your light",
	Fall = "you fell a long way",
	Drowned = "the water was deeper than it looked",
	Rockfall = "the ceiling came down",
	Unknown = "you stopped moving",
}

local CinematicController = {}
CinematicController.__index = CinematicController

type State = {
	Playing: string?,
	_token: number,
}
export type CinematicController = typeof(setmetatable({} :: State, CinematicController))

local function camera(): Camera
	return Workspace.CurrentCamera :: Camera
end

-- Moves the scriptable camera between two CFrames over `time` seconds.
local function glide(from: CFrame, to: CFrame, time: number, ease: ((number) -> number)?)
	local cam = camera()
	local start = os.clock()
	while true do
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local e = if ease then ease(t) else MathUtil.smoothstep(t)
		cam.CFrame = from:Lerp(to, e)
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function headCFrame(): CFrame?
	local character = LocalPlayer.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	return head.CFrame
end

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	if m >= 60 then
		return string.format("%d:%02d:%02d", m // 60, m % 60, s)
	end
	return string.format("%d:%02d", m, s)
end

function CinematicController.Start(self: CinematicController)
	Net.Event("Cinematic").OnClientEvent:Connect(function(cinematicId: string, params: any)
		self._token += 1
		local token = self._token
		task.spawn(function()
			self:_play(cinematicId, if type(params) == "table" then params else {}, token)
		end)
	end)
end

function CinematicController._begin(self: CinematicController, id: string)
	self.Playing = id
	CameraController.Suspended = true
	MovementController:SetEnabled(false)
	camera().CameraType = Enum.CameraType.Scriptable
end

function CinematicController._finish(self: CinematicController, id: string, notify: boolean)
	local cam = camera()
	cam.CameraType = Enum.CameraType.Custom
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
	CameraController.Suspended = false
	MovementController:SetEnabled(true)
	self.Playing = nil
	if notify then
		Net.Event("CinematicFinished"):FireServer(id)
	end
end

function CinematicController._waitForCharacter(self: CinematicController): Model?
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Head", 10)
	return character
end

function CinematicController._play(self: CinematicController, id: string, params: { [string]: any }, token: number)
	if Workspace:GetAttribute(Constants.Attributes.CaveReady) ~= true then
		Workspace:GetAttributeChangedSignal(Constants.Attributes.CaveReady):Wait()
	end
	if id == "Intro" then
		self:_intro(params, token)
	elseif id == "Wake" then
		self:_wake()
	elseif id == "Death" then
		self:_death(params)
	elseif id == "Ending" then
		self:_ending(params, token)
	end
end

function CinematicController._wake(self: CinematicController)
	self:_waitForCharacter()
	task.wait(0.5)
	UIController:Fade(0, 3)
	Net.Event("CinematicFinished"):FireServer("Wake")
end

function CinematicController._intro(self: CinematicController, params: { [string]: any }, token: number)
	self:_waitForCharacter()
	self:_begin("Intro")
	local head = headCFrame() or CFrame.identity
	local mouth = (params.Mouth :: Vector3?) or (head.Position + head.LookVector * 80)
	local campPos = head.Position
	local toMouth = Vector3.new(mouth.X - campPos.X, 0, mouth.Z - campPos.Z).Unit

	-- Shot 1: high over the camp at dusk, drifting toward the hill.
	local high = campPos - toMouth * 70 + Vector3.new(0, 55, 0) + toMouth:Cross(Vector3.yAxis) * 30
	local highEnd = campPos - toMouth * 10 + Vector3.new(0, 34, 0)
	local from = CFrame.lookAt(high, mouth + Vector3.new(0, 25, 0))
	local to = CFrame.lookAt(highEnd, mouth + Vector3.new(0, 4, 0))
	camera().CFrame = from
	UIController:Fade(0, 4)
	UIController:Title("Wellmouth", "Expedition Five  ·  day one", 6)
	glide(from, to, 13)
	if token ~= self._token then
		return
	end

	-- Shot 2: at the mouth, looking into the dark.
	UIController:Fade(1, 1.2)
	task.wait(1.3)
	local near = mouth - toMouth * 14 + Vector3.new(0, 5, 0)
	local inside = mouth + toMouth * 30 - Vector3.new(0, 4, 0)
	local shot2From = CFrame.lookAt(near, inside)
	local shot2To = CFrame.lookAt(near + toMouth * 6 - Vector3.new(0, 0.6, 0), inside)
	camera().CFrame = shot2From
	UIController:Fade(0, 2)
	AudioController:PlayAt("WindGust", mouth + toMouth * 20, { Group = "Ambient", Volume = 1.2 })
	task.delay(2.5, function()
		UIController:Whisper("four groups went down before yours", 4)
	end)
	glide(shot2From, shot2To, 8)
	if token ~= self._token then
		return
	end

	UIController:Fade(1, 1.5)
	task.wait(1.6)
	self:_finish("Intro", true)
	UIController:Fade(0, 3)
	task.wait(2)
	UIController:Whisper("[F] lamp   ·   [Shift] run   ·   [C] crouch   ·   [E] interact   ·   [Tab] journal", 7)
end

function CinematicController._death(self: CinematicController, params: { [string]: any })
	local cam = camera()
	local start = cam.CFrame
	self:_begin("Death")
	CameraController:AddTrauma(0.8)
	-- Collapse: the view tips sideways and drops toward the floor.
	local slumped = start * CFrame.new(0.4, -2.6, 0) * CFrame.Angles(math.rad(-25), math.rad(10), math.rad(70))
	glide(start, slumped, 1.4, function(t: number): number
		return 1 - (1 - t) ^ 3
	end)
	HeadlampController:Darkness(6)
	UIController:Fade(1, 2.2)
	task.wait(2.4)
	local cause = if type(params.Cause) == "string" then params.Cause else "Unknown"
	UIController:Title("", DEATH_LINES[cause] or DEATH_LINES.Unknown, 3.5)
	-- Stay black; the next spawn's Wake fades back in.
	LocalPlayer.CharacterAdded:Wait()
	self:_finish("Death", true)
end

function CinematicController._ending(self: CinematicController, params: { [string]: any }, token: number)
	self:_waitForCharacter()
	self:_begin("Ending")
	LightingController:SetOverride(LightingConfig.Presets.Dawn, 6)
	AudioController:SetGroupVolume("Ambient", 0.5, 4)
	if AudioController:HasSound("SurfaceBirds") then
		AudioController:Play2D("SurfaceBirds", { Group = "Ambient", Volume = 0.6 })
	end
	local head = headCFrame() or camera().CFrame
	local eye = head.Position + Vector3.new(0, 0.4, 0)
	local mouth = (params.Mouth :: Vector3?) or (eye - head.LookVector * 30)
	local away = Vector3.new(eye.X - mouth.X, 0, eye.Z - mouth.Z)
	away = if away.Magnitude > 0.1 then away.Unit else head.LookVector
	-- Looking out, away from the cave, then up at the sky.
	local level = CFrame.lookAt(eye, eye + away * 20)
	local sky = CFrame.lookAt(eye, eye + away * 10 + Vector3.new(0, 16, 0))
	camera().CFrame = level
	glide(level, sky, 7)
	if token ~= self._token then
		return
	end
	UIController:Title("you came back up", "", 4)
	task.wait(5)
	local time = if type(params.Time) == "number" then params.Time else 0
	local depth = if type(params.Depth) == "number" then params.Depth else 0
	local secrets = if type(params.Secrets) == "number" then params.Secrets else 0
	local earned = if type(params.Earned) == "number" then params.Earned else 0
	local line = `{formatTime(time)} underground   ·   {depth} m below   ·   {secrets} {if secrets == 1 then "secret" else "secrets"}`
	if earned > 0 then
		line ..= `   ·   {earned} salvage`
	end
	UIController:Title("", line, 5)
	task.wait(5.5)

	-- And yet.
	HeadlampController:Flicker(0.4, 1)
	task.wait(0.8)
	HeadlampController:Flicker(0.3, 1)
	task.wait(1.5)
	AudioController:PlayAt("MonsterStep", mouth - away * 40, { Group = "Monster", Volume = 0.7, MaxDistance = 400, MinDistance = 30 })
	CameraController:AddTrauma(0.15)
	task.wait(1.2)
	-- Turn back toward the cave.
	local back = CFrame.lookAt(eye, mouth + Vector3.new(0, 3, 0))
	HorrorController:ShowFigure(mouth + away * 2, eye, { Duration = 5.5, VanishWhenSeen = false })
	glide(camera().CFrame, back, 4.5)
	task.wait(1.2)
	HeadlampController:Flicker(0.6, 1)
	task.wait(0.7)
	UIController:Fade(1, 2.5)
	task.wait(3)
	LightingController:SetOverride(nil, 0)
	AudioController:SetGroupVolume("Ambient", 0.9, 2)
	self:_finish("Ending", true)
end

local instance: CinematicController = setmetatable({
	Playing = nil,
	_token = 0,
} :: State, CinematicController)

return instance
