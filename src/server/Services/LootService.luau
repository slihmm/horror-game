--!strict
-- Server-authoritative loot. Each spot rolls once per cycle: a battery, or
-- an item from a rarity table that grows richer with danger (zone bias) and
-- in hidden rooms. Items go into the run satchel and are only kept if the
-- player gets back out. Taken spots quietly restock long after everyone has
-- moved on, so replays find different things.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local LootConfig = require(Shared.Config.LootConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local Weighted = require(Shared.Utility.Weighted)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local ExpeditionService = require(Services.ExpeditionService)
local HeadlampService = require(Services.HeadlampService)
local NoiseService = require(Services.NoiseService)
local PlayerService = require(Services.PlayerService)
local Cave = ServerScriptService.Server.Cave
local PropFactory = require(Cave.PropFactory)
local Dress = require(Cave.DressContext)

type ItemDef = LootConfig.ItemDef
type Spot = {
	Def: Dress.LootSpot,
	Model: Model?,
	TakenAt: number?,
}

local RESTOCK_SECONDS = 900
local RESTOCK_CLEAR_RADIUS = 150

local LootService = {}
LootService.__index = LootService

type State = {
	_spots: { Spot },
	_folder: Folder?,
	_rng: Random,
}
export type LootService = typeof(setmetatable({} :: State, LootService))

function LootService.Start(self: LootService)
	CaveService:WaitUntilReady()
	local dressing = CaveService.Dressing
	if not dressing then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = Workspace:FindFirstChild(Constants.Folders.Cave) or Workspace
	self._folder = folder
	for _, def in dressing.LootSpots do
		local spot: Spot = { Def = def, Model = nil, TakenAt = nil }
		table.insert(self._spots, spot)
		self:_roll(spot)
	end
	while true do
		task.wait(30)
		self:_restock()
	end
end

-- Chooses an item for a spot, or nil to leave it empty.
function LootService.RollItem(self: LootService, zone: string, hidden: boolean): ItemDef?
	local rng = self._rng
	if not hidden and rng:NextNumber() > LootConfig.FillChance then
		return nil
	end
	if not hidden and rng:NextNumber() < LootConfig.BatteryChance then
		return LootConfig.ById.Battery
	end
	local weights: { [string]: number } = {}
	local bias = LootConfig.ZoneRarityBias[zone] or {}
	for rarity, info in LootConfig.Rarities do
		local w = info.Weight * (bias[rarity] or 1)
		if hidden then
			w *= (LootConfig.HiddenRoomBias :: any)[rarity] or 1
		end
		weights[rarity] = w
	end
	for _ = 1, 4 do
		local rarity = Weighted.pickKey(weights, rng)
		if not rarity then
			return nil
		end
		local candidates = {}
		for _, item in LootConfig.Items do
			if item.Rarity == rarity and item.Kind ~= "Battery" and (not item.Zones or table.find(item.Zones, zone)) then
				table.insert(candidates, item)
			end
		end
		if #candidates > 0 then
			return candidates[rng:NextInteger(1, #candidates)]
		end
		weights[rarity] = 0
	end
	return nil
end

function LootService._roll(self: LootService, spot: Spot)
	local item = self:RollItem(spot.Def.Zone, spot.Def.Hidden)
	if item then
		self:_spawn(spot, item)
	end
end

function LootService._spawn(self: LootService, spot: Spot, item: ItemDef)
	local rarity = LootConfig.Rarities[item.Rarity]
	local model = PropFactory.Build("Loot", CFrame.new(spot.Def.Position) * CFrame.Angles(0, self._rng:NextNumber(0, math.pi * 2), 0), self._rng, {
		Shape = item.Shape,
		Color = if rarity then rarity.Color else nil,
	}, self._folder)
	model.Name = "Loot_" .. item.Id
	model:SetAttribute(Constants.Attributes.LootId, item.Id)
	local main = model:FindFirstChild("Main") :: BasePart?
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Take"
	prompt.ObjectText = string.lower(item.Name)
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = main or model:FindFirstChildWhichIsA("BasePart")
	spot.Model = model
	spot.TakenAt = nil
	prompt.Triggered:Connect(function(player: Player)
		self:_take(player, spot, item)
	end)
end

function LootService._take(self: LootService, player: Player, spot: Spot, item: ItemDef)
	local model = spot.Model
	if not model then
		return
	end
	local state = PlayerService:GetCharacterState(player)
	if not state or state.Humanoid.Health <= 0 then
		return
	end
	if (state.Root.Position - spot.Def.Position).Magnitude > LootConfig.PickupRange then
		return
	end
	if item.Kind == "Battery" then
		HeadlampService:AddCharge(player, LootConfig.BatteryCharge)
		Net.Event("Notify"):FireClient(player, "Loot", "fresh cells. the lamp steadies")
	else
		if not ExpeditionService:AddToSatchel(player, item.Id) then
			return
		end
		Net.Event("Notify"):FireClient(player, "Loot", string.lower(item.Name))
	end
	spot.Model = nil
	spot.TakenAt = os.clock()
	model:Destroy()
	NoiseService.Emit(spot.Def.Position, PlayerConfig.Noise.Interaction, "Interaction", player)
end

function LootService._restock(self: LootService)
	local now = os.clock()
	for _, spot in self._spots do
		local takenAt = spot.TakenAt
		if takenAt and now - takenAt > RESTOCK_SECONDS then
			local nearby = false
			for _, player in game:GetService("Players"):GetPlayers() do
				local track = CaveService:GetTrack(player)
				if track and (track.Position - spot.Def.Position).Magnitude < RESTOCK_CLEAR_RADIUS then
					nearby = true
					break
				end
			end
			if not nearby then
				spot.TakenAt = nil
				self:_roll(spot)
			end
		end
	end
end

local instance: LootService = setmetatable({
	_spots = {},
	_folder = nil,
	_rng = Random.new(),
} :: State, LootService)

return instance
