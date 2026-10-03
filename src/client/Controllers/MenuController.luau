--!strict
-- The field journal (Tab): what you have found, what you have pieced
-- together, what you are carrying, your record, and settings. Also renders
-- the expedition logbook board at camp. Deliberately plain: dark paper,
-- small type, no badges or colours.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local LoreData = require(Shared.Config.LoreData)
local LootConfig = require(Shared.Config.LootConfig)
local StatsConfig = require(Shared.Config.StatsConfig)
local HeadlampConfig = require(Shared.Config.HeadlampConfig)

local CameraController = require(script.Parent.CameraController)
local LightingController = require(script.Parent.LightingController)
local UIController = require(script.Parent.UIController)

local LocalPlayer = Players.LocalPlayer

local TEXT = Color3.fromRGB(214, 208, 196)
local DIM = Color3.fromRGB(128, 124, 116)
local FONT = Enum.Font.BuilderSans

local TABS = { "Journal", "Satchel", "Record", "Settings" }

local MenuController = {}
MenuController.__index = MenuController

type State = {
	Open: boolean,
	Profile: Types.ProfileSnapshot?,
	_root: Frame?,
	_content: ScrollingFrame?,
	_tab: string,
	_tabButtons: { [string]: TextButton },
	_modal: TextButton?,
}
export type MenuController = typeof(setmetatable({} :: State, MenuController))

local function formatStat(format: string, value: number): string
	if format == "distance" or format == "depth" then
		return `{math.floor(value * StatsConfig.MetersPerStud)} m`
	elseif format == "time" then
		if value <= 0 then
			return "—"
		end
		local h = math.floor(value / 3600)
		local m = math.floor((value % 3600) / 60)
		local s = math.floor(value % 60)
		return if h > 0 then string.format("%d:%02d:%02d", h, m, s) else string.format("%d:%02d", m, s)
	end
	return tostring(math.floor(value))
end

local function text(parent: Instance, value: string, size: number, color: Color3?, height: number?, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height or (size + 8))
	l.Font = font or FONT
	l.TextSize = size
	l.TextColor3 = color or TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = value
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: number, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.Size = UDim2.new(1, 0, 0, size + 10)
	b.Font = FONT
	b.TextSize = size
	b.TextColor3 = color or TEXT
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Text = value
	b.Parent = parent
	b.MouseEnter:Connect(function()
		b.TextTransparency = 0.35
	end)
	b.MouseLeave:Connect(function()
		b.TextTransparency = 0
	end)
	return b
end

local function leaderboard(key: string): { { Name: string, Value: number } }
	local folder = ReplicatedStorage:FindFirstChild(Constants.Folders.Leaderboards)
	local value = folder and folder:FindFirstChild(key)
	if value and value:IsA("StringValue") then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(value.Value)
		end)
		if ok and type(decoded) == "table" then
			return decoded
		end
	end
	return {}
end

function MenuController.Init(self: MenuController)
	local gui = UIController.Gui
	if not gui then
		return
	end
	local root = Instance.new("Frame")
	root.Name = "Journal"
	root.BackgroundColor3 = Color3.fromRGB(10, 9, 8)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.ZIndex = 50
	root.Parent = gui
	local modal = Instance.new("TextButton")
	modal.Modal = false
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Size = UDim2.fromScale(0, 0)
	modal.Parent = root
	self._modal = modal

	local sidebar = Instance.new("Frame")
	sidebar.BackgroundTransparency = 1
	sidebar.Size = UDim2.new(0, 200, 1, -120)
	sidebar.Position = UDim2.fromOffset(60, 70)
	sidebar.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = sidebar
	for _, name in TABS do
		local b = button(sidebar, string.lower(name), 22, DIM)
		b.ZIndex = 51
		b.Activated:Connect(function()
			self:_show(name)
		end)
		self._tabButtons[name] = b
	end
	local hint = text(root, "[Tab] close", 14, DIM, 20)
	hint.Position = UDim2.new(0, 60, 1, -50)
	hint.Size = UDim2.new(0, 200, 0, 20)

	local content = Instance.new("ScrollingFrame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, -360, 1, -120)
	content.Position = UDim2.fromOffset(300, 70)
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = DIM
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = root
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(720, math.huge)
	constraint.Parent = content
	self._root = root
	self._content = content
end

function MenuController.Start(self: MenuController)
	ContextActionService:BindAction("DescentJournal", function(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect)
	ContextActionService:SetTitle("DescentJournal", "Journal")
	ContextActionService:SetPosition("DescentJournal", UDim2.new(0, 20, 0, 80))

	Net.Event("ProfileSync").OnClientEvent:Connect(function(snapshot: Types.ProfileSnapshot)
		local first = self.Profile == nil
		self.Profile = snapshot
		self:_applySettings(snapshot.Settings)
		if first and not snapshot.Persistent then
			UIController:Whisper("progress is not being saved in this session", 5)
		end
		if self.Open then
			self:_show(self._tab)
		end
	end)

	-- The camp logbook board.
	for _, board in CollectionService:GetTagged(Constants.Tags.Leaderboard) do
		if board:IsA("BasePart") then
			task.spawn(function()
				self:_runBoard(board)
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal(Constants.Tags.Leaderboard):Connect(function(board: Instance)
		if board:IsA("BasePart") then
			self:_runBoard(board)
		end
	end)
end

function MenuController._applySettings(self: MenuController, settings: { [string]: any })
	local motion = settings.CameraMotion
	if type(motion) == "number" then
		CameraController.Motion = motion
	end
	local brightness = settings.Brightness
	if type(brightness) == "number" then
		LightingController:SetBrightnessSetting(brightness)
	end
end

function MenuController.Toggle(self: MenuController)
	local root = self._root
	if not root or UIController.LoreOpen then
		return
	end
	self.Open = not self.Open
	root.Visible = self.Open
	if self._modal then
		self._modal.Modal = self.Open
	end
	if self.Open then
		self:_show(self._tab)
	end
end

function MenuController._clear(self: MenuController): ScrollingFrame?
	local content = self._content
	if not content then
		return nil
	end
	for _, child in content:GetChildren() do
		child:Destroy()
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	return content
end

function MenuController._show(self: MenuController, tab: string)
	self._tab = tab
	for name, b in self._tabButtons do
		b.TextColor3 = if name == tab then TEXT else DIM
	end
	local content = self:_clear()
	if not content then
		return
	end
	local profile = self.Profile
	if tab == "Journal" then
		self:_journal(content, profile)
	elseif tab == "Satchel" then
		self:_satchel(content, profile)
	elseif tab == "Record" then
		self:_record(content, profile)
	elseif tab == "Settings" then
		self:_settings(content, profile)
	end
end

function MenuController._journal(self: MenuController, content: ScrollingFrame, profile: Types.ProfileSnapshot?)
	local found: { [string]: boolean } = {}
	if profile then
		for _, id in profile.Lore do
			found[id] = true
		end
	end
	local count = 0
	local layers: { [number]: boolean } = {}
	for _, entry in LoreData.Entries do
		if found[entry.Id] then
			count += 1
			layers[entry.Layer] = true
		end
	end
	text(content, `{count} of {#LoreData.Entries} recovered`, 15, DIM)
	-- What you understand so far: the layers of the mystery you've touched.
	local understood = {}
	for layer, line in LoreData.LayerNames do
		if layers[layer] then
			table.insert(understood, "—  " .. line)
		end
	end
	if #understood > 0 then
		text(content, "what you understand", 15, DIM, 30)
		for _, line in understood do
			text(content, line, 18, TEXT, 24, Enum.Font.Merriweather)
		end
	end
	text(content, "", 10, DIM, 14)
	-- Discovered entries, grouped by expedition.
	local order: { string } = {}
	local groups: { [string]: { LoreData.LoreEntry } } = {}
	for _, entry in LoreData.Entries do
		if found[entry.Id] then
			if not groups[entry.Expedition] then
				groups[entry.Expedition] = {}
				table.insert(order, entry.Expedition)
			end
			table.insert(groups[entry.Expedition], entry)
		end
	end
	for _, expedition in order do
		text(content, string.lower(expedition), 15, DIM, 28)
		for _, entry in groups[expedition] do
			local b = button(content, "    " .. entry.Title, 19)
			b.Activated:Connect(function()
				self:Toggle()
				UIController:ShowLore(entry, false)
			end)
		end
	end
	if count == 0 then
		text(content, "nothing yet. the cave keeps its records where it keeps everything else.", 18, DIM, 50, Enum.Font.Merriweather)
	end
end

function MenuController._satchel(self: MenuController, content: ScrollingFrame, profile: Types.ProfileSnapshot?)
	text(content, "carried this expedition. lost if you die down there; kept if you make it out.", 15, DIM, 40)
	local any = false
	if profile then
		for _, slot in profile.Satchel do
			local item = LootConfig.ById[slot.id]
			if item then
				any = true
				text(content, `{string.lower(item.Name)}{if slot.count > 1 then "  ×" .. slot.count else ""}`, 19)
				text(content, "    " .. item.Description, 15, DIM, 22)
			end
		end
	end
	if not any then
		text(content, "empty", 18, DIM)
	end
end

function MenuController._record(self: MenuController, content: ScrollingFrame, profile: Types.ProfileSnapshot?)
	if profile then
		for _, stat in StatsConfig.Stats do
			local value = (profile.Stats :: any)[stat.Key] or 0
			text(content, `{string.lower(stat.DisplayName)}   {formatStat(stat.Format, value)}`, 19)
		end
		text(content, `expeditions   {profile.Stats.Expeditions}      deaths   {profile.Stats.Deaths}`, 16, DIM)
		text(content, `salvage   {profile.Currency}`, 16, DIM)
		text(content, "", 10, DIM, 12)
		local collectionLines = {}
		for id, n in profile.Collection do
			local item = LootConfig.ById[id]
			if item and n > 0 then
				table.insert(collectionLines, `{string.lower(item.Name)}  ×{n}`)
			end
		end
		if #collectionLines > 0 then
			table.sort(collectionLines)
			text(content, "brought back", 15, DIM, 26)
			for _, line in collectionLines do
				text(content, "    " .. line, 17)
			end
		end
	end
	text(content, "", 10, DIM, 12)
	text(content, "the logbook", 15, DIM, 26)
	for _, stat in StatsConfig.Stats do
		local entries = leaderboard(stat.Key)
		text(content, string.lower(stat.DisplayName), 16, DIM, 24)
		for i, entry in entries do
			if i > 5 then
				break
			end
			text(content, `    {i}.  {entry.Name}   {formatStat(stat.Format, entry.Value)}`, 16, TEXT, 22)
		end
		if #entries == 0 then
			text(content, "    no entries", 15, DIM, 22)
		end
	end
end

function MenuController._settings(self: MenuController, content: ScrollingFrame, profile: Types.ProfileSnapshot?)
	local settings: { [string]: any } = if profile then profile.Settings else {}
	local function stepper(label: string, key: string, current: number)
		text(content, label, 16, DIM, 26)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 30)
		row.Parent = content
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 18)
		layout.Parent = row
		for _, step in { 0, 0.25, 0.5, 0.75, 1 } do
			local b = button(row, if math.abs(step - current) < 0.01 then `[{math.floor(step * 100)}]` else tostring(math.floor(step * 100)), 18, if math.abs(step - current) < 0.01 then TEXT else DIM)
			b.Size = UDim2.fromOffset(56, 28)
			b.Activated:Connect(function()
				Net.Event("UpdateSetting"):FireServer(key, step)
				local snapshot = self.Profile
				if snapshot then
					snapshot.Settings[key] = step
					self:_applySettings(snapshot.Settings)
					self:_show("Settings")
				end
			end)
		end
	end
	stepper("camera motion", "CameraMotion", if type(settings.CameraMotion) == "number" then settings.CameraMotion else 1)
	stepper("brightness", "Brightness", if type(settings.Brightness) == "number" then settings.Brightness else 0.5)
	text(content, "lamp lens", 16, DIM, 26)
	local owned: { [string]: boolean } = { Default = true }
	if profile then
		for _, id in profile.Cosmetics do
			local item = LootConfig.ById[id]
			if item and item.Tint then
				owned[item.Tint] = true
			end
		end
	end
	for name in HeadlampConfig.Tints do
		if owned[name] then
			local selected = settings.HeadlampTint == name
			local b = button(content, (if selected then "—  " else "    ") .. string.lower(name), 18, if selected then TEXT else DIM)
			b.Activated:Connect(function()
				Net.Event("UpdateSetting"):FireServer("HeadlampTint", name)
				local snapshot = self.Profile
				if snapshot then
					snapshot.Settings.HeadlampTint = name
					self:_show("Settings")
				end
			end)
		end
	end
end

-- Cycles the logbook board at camp through each statistic.
function MenuController._runBoard(self: MenuController, board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Adornee = board
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Parent = frame
	local index = 0
	while board.Parent do
		index = index % #StatsConfig.Stats + 1
		local stat = StatsConfig.Stats[index]
		for _, child in frame:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local title = text(frame, "EXPEDITION LOG  ·  " .. string.upper(stat.DisplayName), 26, Color3.fromRGB(230, 222, 200), 44, Enum.Font.SpecialElite)
		title.TextTransparency = 1
		local labels = { title }
		for i, entry in leaderboard(stat.Key) do
			if i > 6 then
				break
			end
			local l = text(frame, `{i}.  {entry.Name}  —  {formatStat(stat.Format, entry.Value)}`, 22, Color3.fromRGB(220, 214, 196), 34, Enum.Font.SpecialElite)
			l.TextTransparency = 1
			table.insert(labels, l)
		end
		for _, l in labels do
			TweenService:Create(l, TweenInfo.new(1), { TextTransparency = 0.1 }):Play()
		end
		task.wait(9)
		for _, l in labels do
			TweenService:Create(l, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end
		task.wait(1.1)
	end
	gui:Destroy()
end

local instance: MenuController = setmetatable({
	Open = false,
	Profile = nil,
	_root = nil,
	_content = nil,
	_tab = "Journal",
	_tabButtons = {},
	_modal = nil,
} :: State, MenuController)

return instance
