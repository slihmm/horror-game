--!strict
-- The minimal UI layer. There are no objective markers, quest logs, health
-- bars or names. What exists: fades, a quiet whisper line for discoveries,
-- the lore reader, a vignette, and a battery glyph that appears briefly when
-- it matters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local LoreData = require(Shared.Config.LoreData)
local HeadlampConfig = require(Shared.Config.HeadlampConfig)

local AudioController = require(script.Parent.AudioController)

local LocalPlayer = Players.LocalPlayer

local UI_FONT = Enum.Font.BuilderSans
local TEXT_COLOR = Color3.fromRGB(214, 208, 196)
local DIM_COLOR = Color3.fromRGB(130, 126, 118)

local UIController = {}
UIController.__index = UIController

type State = {
	Gui: ScreenGui?,
	LoreOpen: boolean,
	_fade: Frame?,
	_whisper: TextLabel?,
	_title: TextLabel?,
	_subtitle: TextLabel?,
	_vignette: { Frame },
	_vignetteStrength: number,
	_lorePanel: Frame?,
	_loreClose: (() -> ())?,
	_battery: Frame?,
	_batteryFill: Frame?,
	_batteryHideAt: number,
	_whisperToken: number,
	_loading: Frame?,
	_damage: Frame?,
}
export type UIController = typeof(setmetatable({} :: State, UIController))

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UI_FONT
	l.TextColor3 = TEXT_COLOR
	l.TextTransparency = 1
	l.TextWrapped = true
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Sine), goal)
	t:Play()
	return t
end

local KIND_FONTS: { [string]: Enum.Font } = {
	Journal = Enum.Font.IndieFlower,
	Note = Enum.Font.IndieFlower,
	Recording = Enum.Font.SpecialElite,
	Device = Enum.Font.RobotoMono,
	Photograph = Enum.Font.Merriweather,
	Carving = Enum.Font.Fondamento,
	Remains = Enum.Font.Merriweather,
}

function UIController.Init(self: UIController)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
	end)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Descent"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = gui

	-- Vignette: four gradient frames darkening the edges of vision.
	local function edge(rotation: number, size: UDim2, position: UDim2, anchor: Vector2)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.Size = size
		f.Position = position
		f.AnchorPoint = anchor
		f.ZIndex = 1
		f.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = f
		table.insert(self._vignette, f)
	end
	edge(90, UDim2.new(1, 0, 0.28, 0), UDim2.fromScale(0, 0), Vector2.zero)
	edge(-90, UDim2.new(1, 0, 0.28, 0), UDim2.fromScale(0, 1), Vector2.new(0, 1))
	edge(0, UDim2.new(0.22, 0, 1, 0), UDim2.fromScale(0, 0), Vector2.zero)
	edge(180, UDim2.new(0.22, 0, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0))
	self:SetVignette(0.35, 0)

	-- Damage tint.
	local damage = Instance.new("Frame")
	damage.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
	damage.BackgroundTransparency = 1
	damage.BorderSizePixel = 0
	damage.Size = UDim2.fromScale(1, 1)
	damage.ZIndex = 2
	damage.Parent = gui
	self._damage = damage

	-- Whisper line (bottom center).
	self._whisper = label(gui, {
		Size = UDim2.new(0.6, 0, 0, 28),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 20,
		TextColor3 = DIM_COLOR,
		ZIndex = 20,
	})

	-- Title / subtitle for cinematic beats.
	self._title = label(gui, {
		Size = UDim2.new(0.8, 0, 0, 60),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 44,
		Font = Enum.Font.Merriweather,
		ZIndex = 41,
	})
	self._subtitle = label(gui, {
		Size = UDim2.new(0.8, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 20,
		TextColor3 = DIM_COLOR,
		ZIndex = 41,
	})

	-- Battery glyph (top right), hidden unless relevant.
	local battery = Instance.new("Frame")
	battery.Size = UDim2.fromOffset(46, 14)
	battery.Position = UDim2.new(1, -28, 0, 28)
	battery.AnchorPoint = Vector2.new(1, 0)
	battery.BackgroundTransparency = 1
	battery.ZIndex = 20
	battery.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Color = TEXT_COLOR
	outline.Thickness = 1
	outline.Transparency = 1
	outline.Parent = battery
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = TEXT_COLOR
	fill.BackgroundTransparency = 1
	fill.Size = UDim2.new(1, -4, 1, -4)
	fill.Position = UDim2.fromOffset(2, 2)
	fill.ZIndex = 21
	fill.Parent = battery
	self._battery = battery
	self._batteryFill = fill

	-- Full-screen fade (above everything except titles).
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 0
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 40
	fade.Parent = gui
	self._fade = fade

	self:_buildLoading(gui)
	self:_buildLorePanel(gui)
end

function UIController.Start(self: UIController)
	Net.Event("Notify").OnClientEvent:Connect(function(_kind: string, text: string)
		if type(text) == "string" then
			self:Whisper(text)
		end
	end)
	Net.Event("LoreReveal").OnClientEvent:Connect(function(loreId: string, firstTime: boolean)
		local entry = LoreData.ById[loreId]
		if entry then
			self:ShowLore(entry, firstTime == true)
		end
	end)
	-- Battery glyph shows on change when low, or briefly after toggling.
	local function batteryChanged()
		local battery = (LocalPlayer:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
		if battery < HeadlampConfig.Battery.LowThreshold then
			self:ShowBattery(4)
		end
	end
	LocalPlayer:GetAttributeChangedSignal(Constants.Attributes.Battery):Connect(batteryChanged)
	LocalPlayer:GetAttributeChangedSignal(Constants.Attributes.HeadlampOn):Connect(function()
		self:ShowBattery(2.5)
	end)
	-- Wait for the cave, then lift the loading screen.
	if Workspace:GetAttribute(Constants.Attributes.CaveReady) ~= true then
		Workspace:GetAttributeChangedSignal(Constants.Attributes.CaveReady):Wait()
	end
	local loading = self._loading
	if loading then
		for _, child in loading:GetDescendants() do
			if child:IsA("TextLabel") then
				tween(child, 1.5, { TextTransparency = 1 })
			end
		end
		tween(loading, 2, { BackgroundTransparency = 1 })
		task.delay(2.2, function()
			loading:Destroy()
		end)
	end
	-- Damage flashes.
	local function hookCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health: number)
			if health < last - 1 then
				self:FlashDamage(math.clamp((last - health) / 60, 0.15, 0.6))
			end
			last = health
		end)
	end
	LocalPlayer.CharacterAdded:Connect(hookCharacter)
	if LocalPlayer.Character then
		task.spawn(hookCharacter, LocalPlayer.Character)
	end
end

function UIController._buildLoading(self: UIController, gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Loading"
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 60
	frame.Parent = gui
	local text = label(frame, {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 18,
		TextColor3 = DIM_COLOR,
		Text = "the cave is settling",
		TextTransparency = 0.2,
		ZIndex = 61,
	})
	task.spawn(function()
		local dots = 0
		while text.Parent do
			dots = (dots + 1) % 4
			text.Text = "the cave is settling" .. string.rep(".", dots)
			task.wait(0.6)
		end
	end)
	self._loading = frame
end

-- Fades --------------------------------------------------------------------------

-- 0 = fully visible scene, 1 = black.
function UIController.Fade(self: UIController, blackness: number, time: number): Tween?
	local fade = self._fade
	if not fade then
		return nil
	end
	return tween(fade, time, { BackgroundTransparency = 1 - blackness })
end

function UIController.SetVignette(self: UIController, strength: number, time: number?)
	self._vignetteStrength = strength
	for _, frame in self._vignette do
		if time and time > 0 then
			tween(frame, time, { BackgroundTransparency = 1 - strength })
		else
			frame.BackgroundTransparency = 1 - strength
		end
	end
end

function UIController.FlashDamage(self: UIController, intensity: number)
	local damage = self._damage
	if not damage then
		return
	end
	damage.BackgroundTransparency = 1 - intensity
	tween(damage, 1.4, { BackgroundTransparency = 1 })
end

-- Text -------------------------------------------------------------------------------

-- A quiet line at the bottom of the screen that fades by itself.
function UIController.Whisper(self: UIController, text: string, duration: number?)
	local whisper = self._whisper
	if not whisper then
		return
	end
	self._whisperToken += 1
	local token = self._whisperToken
	whisper.Text = text
	tween(whisper, 0.8, { TextTransparency = 0.15 })
	task.delay(duration or 4, function()
		if self._whisperToken == token then
			tween(whisper, 1.5, { TextTransparency = 1 })
		end
	end)
end

function UIController.Title(self: UIController, title: string, subtitle: string?, hold: number?)
	local t, s = self._title, self._subtitle
	if not t or not s then
		return
	end
	t.Text = title
	s.Text = subtitle or ""
	tween(t, 2, { TextTransparency = 0.05 })
	tween(s, 2.5, { TextTransparency = 0.2 })
	task.delay(hold or 4, function()
		tween(t, 2, { TextTransparency = 1 })
		tween(s, 2, { TextTransparency = 1 })
	end)
end

-- Battery glyph --------------------------------------------------------------------------

function UIController.ShowBattery(self: UIController, seconds: number)
	local battery, fill = self._battery, self._batteryFill
	if not battery or not fill then
		return
	end
	local level = (LocalPlayer:GetAttribute(Constants.Attributes.Battery) :: number?) or 0
	local on = LocalPlayer:GetAttribute(Constants.Attributes.HeadlampOn) == true
	fill.Size = UDim2.new(math.max(level, 0.02), -4, 1, -4)
	local color = if level < HeadlampConfig.Battery.CriticalThreshold then Color3.fromRGB(180, 70, 60) else TEXT_COLOR
	fill.BackgroundColor3 = color
	local stroke = battery:FindFirstChildOfClass("UIStroke")
	tween(fill, 0.3, { BackgroundTransparency = if on then 0.3 else 0.75 })
	if stroke then
		tween(stroke, 0.3, { Transparency = 0.4 })
	end
	self._batteryHideAt = os.clock() + seconds
	task.delay(seconds, function()
		if os.clock() >= self._batteryHideAt - 0.05 then
			tween(fill, 1, { BackgroundTransparency = 1 })
			if stroke then
				tween(stroke, 1, { Transparency = 1 })
			end
		end
	end)
end

-- Lore reader -----------------------------------------------------------------------------

function UIController._buildLorePanel(self: UIController, gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "Lore"
	panel.Size = UDim2.new(0, 560, 0.72, 0)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(14, 13, 12)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(560, 760)
	constraint.MinSize = Vector2.new(280, 300)
	constraint.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 36)
	padding.PaddingRight = UDim.new(0, 36)
	padding.PaddingTop = UDim.new(0, 30)
	padding.PaddingBottom = UDim.new(0, 30)
	padding.Parent = panel
	label(panel, {
		Name = "Meta",
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = DIM_COLOR,
		ZIndex = 31,
	})
	label(panel, {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 24,
		Font = Enum.Font.Merriweather,
		ZIndex = 31,
	})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -100)
	scroll.Position = UDim2.fromOffset(0, 70)
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = DIM_COLOR
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 31
	scroll.Parent = panel
	label(scroll, {
		Name = "Body",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 18,
		LineHeight = 1.3,
		ZIndex = 32,
	})
	label(panel, {
		Name = "Hint",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		TextColor3 = DIM_COLOR,
		Text = "[E] put it down",
		ZIndex = 31,
	})
	self._lorePanel = panel
end


function UIController.ShowLore(self: UIController, entry: LoreData.LoreEntry, firstTime: boolean)
	local panel = self._lorePanel
	if not panel then
		return
	end
	if self._loreClose then
		self._loreClose()
	end
	local meta = panel:FindFirstChild("Meta") :: TextLabel
	local heading = panel:FindFirstChild("Heading") :: TextLabel
	local body = (panel:FindFirstChild("Scroll") :: ScrollingFrame):FindFirstChild("Body") :: TextLabel
	local hint = panel:FindFirstChild("Hint") :: TextLabel
	meta.Text = string.upper(entry.Kind) .. "  ·  " .. entry.Expedition
	heading.Text = entry.Title
	body.Text = entry.Text
	body.Font = KIND_FONTS[entry.Kind] or Enum.Font.Merriweather
	body.TextSize = if body.Font == Enum.Font.IndieFlower then 22 else 18
	panel.Visible = true
	self.LoreOpen = true
	tween(panel, 0.5, { BackgroundTransparency = 0.06 })
	for _, l in { meta, heading, hint } do
		tween(l, 0.8, { TextTransparency = 0.15 })
	end
	-- The body fades in slowly; recordings "play" line by line.
	body.TextTransparency = 1
	body.MaxVisibleGraphemes = -1
	if entry.Kind == "Recording" then
		body.TextTransparency = 0.1
		body.MaxVisibleGraphemes = 0
		task.spawn(function()
			local total = utf8.len(entry.Text) or #entry.Text
			local shown = 0
			while shown < total and panel.Visible and body.Text == entry.Text do
				shown += 2
				body.MaxVisibleGraphemes = shown
				task.wait(0.03)
			end
			body.MaxVisibleGraphemes = -1
		end)
	else
		tween(body, 1.2, { TextTransparency = 0.1 })
	end
	AudioController:Play2D("PageTurn", { Group = "UI" })
	if firstTime then
		self:Whisper(`{string.lower(entry.Kind)} recovered`, 3)
	end

	local connection: RBXScriptConnection? = nil
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		self._loreClose = nil
		if connection then
			connection:Disconnect()
		end
		self.LoreOpen = false
		for _, l in { meta, heading, hint, body } do
			tween(l, 0.4, { TextTransparency = 1 })
		end
		tween(panel, 0.5, { BackgroundTransparency = 1 }).Completed:Once(function()
			if not self.LoreOpen then
				panel.Visible = false
			end
		end)
	end
	self._loreClose = close
	task.delay(0.4, function()
		if closed then
			return
		end
		connection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed and input.KeyCode ~= Enum.KeyCode.Escape then
				return
			end
			local key = input.KeyCode
			if key == Enum.KeyCode.E or key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				close()
			end
		end)
	end)
end

function UIController.CloseLore(self: UIController)
	if self._loreClose then
		self._loreClose()
	end
end


local instance: UIController = setmetatable({
	Gui = nil,
	LoreOpen = false,
	_fade = nil,
	_whisper = nil,
	_title = nil,
	_subtitle = nil,
	_vignette = {},
	_vignetteStrength = 0.35,
	_lorePanel = nil,
	_loreClose = nil,
	_battery = nil,
	_batteryFill = nil,
	_batteryHideAt = 0,
	_whisperToken = 0,
	_loading = nil,
	_damage = nil,
} :: State, UIController)

return instance
