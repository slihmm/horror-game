--!strict
-- Places the story where it belongs and records what each player has read.
--
-- Placement order each run:
--   1. entries asking for a tagged slot (e.g. your own journal in the newest
--      camp of the Gathering)
--   2. entries anchored to a story location
--   3. hidden entries into hidden rooms
--   4. the remaining pool, scattered through matching zones
-- Story beats always land in the same rooms; the scattered entries move.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local LoreData = require(Shared.Config.LoreData)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local DataService = require(Services.DataService)
local NoiseService = require(Services.NoiseService)
local Cave = ServerScriptService.Server.Cave
local PropFactory = require(Cave.PropFactory)
local Dress = require(Cave.DressContext)
local LorePlacement = require(Cave.LorePlacement)

type LoreEntry = LoreData.LoreEntry
type LoreSlot = Dress.LoreSlot

local ACTIONS: { [string]: string } = {
	Journal = "Read",
	Note = "Read",
	Recording = "Listen",
	Device = "Look",
	Photograph = "Look",
	Carving = "Examine",
	Remains = "Search",
}

local LoreService = {}
LoreService.__index = LoreService

type State = {
	Placed: { [string]: Vector3 },
	_folder: Folder?,
	_rng: Random,
}
export type LoreService = typeof(setmetatable({} :: State, LoreService))

function LoreService.Start(self: LoreService)
	CaveService:WaitUntilReady()
	local dressing = CaveService.Dressing
	if not dressing then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Lore"
	folder.Parent = Workspace:FindFirstChild(Constants.Folders.Cave) or Workspace
	self._folder = folder
	self:_placeAll(dressing.LoreSlots)
end

function LoreService._placeAll(self: LoreService, slots: { LoreSlot })
	local placements, warnings = LorePlacement.Assign(LoreData.Entries, slots, self._rng)
	for _, placement in placements do
		self:_spawn(placement.Entry, placement.Slot)
	end
	for _, message in warnings do
		warn("[Lore] " .. message)
	end
	print(`[Lore] placed {#placements}/{#LoreData.Entries} entries`)
end

function LoreService._spawn(self: LoreService, entry: LoreEntry, slot: LoreSlot)
	local rng = self._rng
	local folder = self._folder
	local model: Model
	if entry.Kind == "Carving" then
		if slot.Wall then
			model = PropFactory.Build("WallText", slot.Wall * CFrame.new(0, 0.5, 0), rng, {
				Text = "≈ ◯ ⟟ ≈ ⊼ ⟊ ◯ ≈",
				Font = Enum.Font.Fondamento,
				Size = Vector2.new(4.5, 2.2),
				Color = Color3.fromRGB(150, 140, 120),
			}, folder)
		else
			model = PropFactory.Build("Tablet", slot.CFrame, rng, nil, folder)
		end
	elseif entry.Kind == "Remains" then
		model = PropFactory.Build("Skeleton", slot.CFrame, rng, { Pose = "Sitting" }, folder)
	elseif entry.Kind == "Recording" then
		model = PropFactory.Build("Recorder", slot.CFrame, rng, nil, folder)
	elseif entry.Kind == "Device" then
		model = PropFactory.Build("Recorder", slot.CFrame, rng, { Phone = true }, folder)
	elseif entry.Kind == "Photograph" then
		model = PropFactory.Build("Photograph", slot.CFrame, rng, nil, folder)
	elseif entry.Kind == "Note" then
		model = PropFactory.Build("Note", slot.CFrame, rng, nil, folder)
	else
		model = PropFactory.Build("Journal", slot.CFrame, rng, { Open = rng:NextNumber() < 0.4 }, folder)
	end
	model.Name = "Lore_" .. entry.Id
	model:SetAttribute(Constants.Attributes.LoreId, entry.Id)
	CollectionService:AddTag(model, Constants.Tags.LoreObject)

	local anchorPart = Instance.new("Part")
	anchorPart.Name = "PromptAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.5, 0.5, 0.5)
	anchorPart.CFrame = CFrame.new(model:GetPivot().Position + Vector3.yAxis * 1)
	anchorPart.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ACTIONS[entry.Kind] or "Examine"
	prompt.ObjectText = string.lower(entry.Kind)
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchorPart
	prompt.Triggered:Connect(function(player: Player)
		self:_onRead(player, entry, anchorPart.Position)
	end)
	self.Placed[entry.Id] = anchorPart.Position
end

function LoreService._onRead(self: LoreService, player: Player, entry: LoreEntry, position: Vector3)
	local profile = DataService:GetProfile(player)
	local firstTime = profile ~= nil and not profile.Lore[entry.Id]
	if firstTime then
		DataService:Update(player, function(p)
			p.Lore[entry.Id] = true
		end)
	end
	NoiseService.Emit(position, PlayerConfig.Noise.Interaction, "Interaction", player)
	Net.Event("LoreReveal"):FireClient(player, entry.Id, firstTime)
end

local instance: LoreService = setmetatable({
	Placed = {},
	_folder = nil,
	_rng = Random.new(),
} :: State, LoreService)

return instance
