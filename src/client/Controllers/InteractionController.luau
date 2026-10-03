--!strict
-- Renders proximity prompts as a single quiet line of text near the bottom
-- of the screen instead of Roblox's default floating buttons. Hold prompts
-- show a thin progress line. Touch players can tap the line.

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIController = require(script.Parent.UIController)

local InteractionController = {}
InteractionController.__index = InteractionController

type State = {
	_frame: Frame?,
	_text: TextButton?,
	_bar: Frame?,
	_current: ProximityPrompt?,
	_holdTween: Tween?,
}
export type InteractionController = typeof(setmetatable({} :: State, InteractionController))

local TEXT_COLOR = Color3.fromRGB(214, 208, 196)

local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return (string.gsub(name, "^Button", ""))
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "tap"
	end
	return prompt.KeyboardKeyCode.Name
end

function InteractionController.Init(self: InteractionController)
	ProximityPromptService.MaxPromptsVisible = 1
	local gui = UIController.Gui
	if not gui then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "Prompt"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, 420, 0, 34)
	frame.Position = UDim2.new(0.5, 0, 0.78, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 25
	frame.Parent = gui
	local text = Instance.new("TextButton")
	text.AutoButtonColor = false
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 1, -4)
	text.Font = Enum.Font.BuilderSans
	text.TextSize = 19
	text.TextColor3 = TEXT_COLOR
	text.TextTransparency = 1
	text.Text = ""
	text.ZIndex = 26
	text.Parent = frame
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = TEXT_COLOR
	bar.BackgroundTransparency = 0.4
	bar.Size = UDim2.new(0, 0, 0, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -1)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.ZIndex = 26
	bar.Parent = frame
	self._frame = frame
	self._text = text
	self._bar = bar

	text.MouseButton1Down:Connect(function()
		local prompt = self._current
		if prompt and UserInputService.TouchEnabled then
			prompt:InputHoldBegin()
		end
	end)
	text.MouseButton1Up:Connect(function()
		local prompt = self._current
		if prompt and UserInputService.TouchEnabled then
			prompt:InputHoldEnd()
		end
	end)
end

function InteractionController.Start(self: InteractionController)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		self:_show(prompt, inputType)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt == self._current then
			self:_hide()
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		if prompt == self._current then
			self:_hold(prompt.HoldDuration)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		if prompt == self._current then
			self:_hold(nil)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt == self._current then
			self:_hold(nil)
		end
	end)
end

function InteractionController._show(self: InteractionController, prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local text = self._text
	if not text then
		return
	end
	self._current = prompt
	local action = string.lower(prompt.ActionText)
	local object = prompt.ObjectText
	text.Text = `[{keyLabel(prompt, inputType)}]  {action}{if object ~= "" then "  ·  " .. string.lower(object) else ""}`
	TweenService:Create(text, TweenInfo.new(0.35), { TextTransparency = 0.12 }):Play()
end

function InteractionController._hide(self: InteractionController)
	self._current = nil
	local text = self._text
	if text then
		TweenService:Create(text, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	end
	self:_hold(nil)
end

function InteractionController._hold(self: InteractionController, duration: number?)
	local bar = self._bar
	if not bar then
		return
	end
	if self._holdTween then
		self._holdTween:Cancel()
		self._holdTween = nil
	end
	if duration and duration > 0 then
		bar.Size = UDim2.new(0, 0, 0, 1)
		local tween = TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0.6, 0, 0, 1) })
		self._holdTween = tween
		tween:Play()
	else
		bar.Size = UDim2.new(0, 0, 0, 1)
	end
end

local instance: InteractionController = setmetatable({
	_frame = nil,
	_text = nil,
	_bar = nil,
	_current = nil,
	_holdTween = nil,
} :: State, InteractionController)

return instance
