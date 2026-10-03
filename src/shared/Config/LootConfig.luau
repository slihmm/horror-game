--!strict
-- Loot definitions. Everything picked up underground goes into the run's
-- satchel and is only banked if the player escapes; dying loses it.
-- Batteries are consumed immediately.

export type ItemDef = {
	Id: string,
	Name: string,
	Description: string,
	-- Battery | Currency | Collectible | Artifact | Cosmetic
	Kind: string,
	Rarity: string,
	Value: number, -- currency granted when banked (Currency/Collectible/Artifact)
	-- Restrict where an item can appear (zone ids); nil = anywhere.
	Zones: { string }?,
	-- Cosmetic items unlock a headlamp tint (HeadlampConfig.Tints).
	Tint: string?,
	-- Model shape hint for the PropFactory.
	Shape: string,
}

local Rarities: { [string]: { Weight: number, Color: Color3 } } = {
	Common = { Weight = 60, Color = Color3.fromRGB(190, 186, 176) },
	Uncommon = { Weight = 26, Color = Color3.fromRGB(150, 176, 150) },
	Rare = { Weight = 10, Color = Color3.fromRGB(140, 160, 200) },
	Epic = { Weight = 3.4, Color = Color3.fromRGB(184, 150, 206) },
	Mythic = { Weight = 0.6, Color = Color3.fromRGB(226, 196, 128) },
}

local Items: { ItemDef } = {
	{ Id = "Battery", Name = "Battery Pack", Description = "Half-drained, still useful.", Kind = "Battery", Rarity = "Common", Value = 0, Shape = "Battery" },
	{ Id = "OldCoin", Name = "Tarnished Coin", Description = "Worn smooth by a thumb, not by water.", Kind = "Currency", Rarity = "Common", Value = 4, Shape = "Coin" },
	{ Id = "DogTag", Name = "Dog Tag", Description = "The name has been scratched out.", Kind = "Currency", Rarity = "Common", Value = 8, Shape = "Tag" },
	{ Id = "Carabiner", Name = "Bent Carabiner", Description = "Something pulled hard enough to open the gate.", Kind = "Currency", Rarity = "Common", Value = 5, Shape = "Ring" },
	{ Id = "PocketWatch", Name = "Pocket Watch", Description = "Stopped. The hands point straight down.", Kind = "Currency", Rarity = "Uncommon", Value = 22, Shape = "Coin" },
	{ Id = "BrassCompass", Name = "Brass Compass", Description = "The needle points toward the deepest part of the cave.", Kind = "Currency", Rarity = "Uncommon", Value = 28, Shape = "Coin" },
	{ Id = "SilverLocket", Name = "Silver Locket", Description = "The photograph inside is of this cave's entrance.", Kind = "Currency", Rarity = "Rare", Value = 55, Shape = "Coin" },
	{ Id = "WeddingRing", Name = "Wedding Ring", Description = "Engraved: 'come home'.", Kind = "Currency", Rarity = "Rare", Value = 70, Shape = "Ring" },
	{ Id = "Fossil", Name = "Fossil Shell", Description = "From a sea that should not have been this deep.", Kind = "Collectible", Rarity = "Uncommon", Value = 15, Shape = "Stone", Zones = { "UpperCave", "WetCave", "DeepCave" } },
	{ Id = "CaveCrystal", Name = "Cave Crystal", Description = "Glows faintly after the light goes out.", Kind = "Collectible", Rarity = "Rare", Value = 40, Shape = "Crystal", Zones = { "WetCave", "DeepCave", "Ancient" } },
	{ Id = "SurveyBadge", Name = "Survey Badge (1911)", Description = "Hollis & Pryce Mining Co. — Ardent Survey.", Kind = "Collectible", Rarity = "Rare", Value = 45, Shape = "Tag", Zones = { "DeepCave", "ExplorerCamp", "FinalChamber" } },
	{ Id = "SocietyPin", Name = "Society Pin (1958)", Description = "Lindqvist Speleological Society.", Kind = "Collectible", Rarity = "Rare", Value = 45, Shape = "Coin", Zones = { "WetCave", "ExplorerCamp", "FinalChamber" } },
	{ Id = "Cassette", Name = "Unlabeled Cassette", Description = "Deep Strata Project. Side B is only breathing.", Kind = "Collectible", Rarity = "Uncommon", Value = 20, Shape = "Box", Zones = { "ExplorerCamp", "Ancient", "FinalChamber" } },
	{ Id = "Figurine", Name = "Carved Figurine", Description = "A small figure with too many lights on its head.", Kind = "Artifact", Rarity = "Epic", Value = 120, Shape = "Idol", Zones = { "Ancient", "FinalChamber" } },
	{ Id = "EyeStone", Name = "The Open Eye", Description = "A smooth black stone. It is warm.", Kind = "Artifact", Rarity = "Mythic", Value = 400, Shape = "Crystal", Zones = { "Ancient", "FinalChamber" } },
	{ Id = "AmberLens", Name = "Amber Lens", Description = "A headlamp lens from an older lamp. Warmer light.", Kind = "Cosmetic", Rarity = "Rare", Value = 0, Tint = "Amber", Shape = "Lens" },
	{ Id = "ArcticLens", Name = "Cold Lens", Description = "Blue-white. Makes the rock look like bone.", Kind = "Cosmetic", Rarity = "Rare", Value = 0, Tint = "Arctic", Shape = "Lens" },
	{ Id = "SodiumLens", Name = "Sodium Lens", Description = "The colour of a streetlight you'll never see again.", Kind = "Cosmetic", Rarity = "Epic", Value = 0, Tint = "Sodium", Shape = "Lens" },
	{ Id = "PaleLens", Name = "Pale Lens", Description = "Taken from the Lamplighter's lamps.", Kind = "Cosmetic", Rarity = "Mythic", Value = 0, Tint = "Pale", Shape = "Lens", Zones = { "FinalChamber" } },
}

local ById: { [string]: ItemDef } = {}
for _, item in Items do
	ById[item.Id] = item
end

return {
	Rarities = Rarities,
	Items = Items,
	ById = ById,
	-- Fraction of loot spawn points that actually contain something.
	FillChance = 0.55,
	-- Battery chance per filled point (rolled before the rarity table).
	BatteryChance = 0.3,
	BatteryCharge = 0.45,
	-- Rarity weight multipliers per zone: dangerous areas are richer.
	ZoneRarityBias = {
		UpperCave = { Rare = 0.4, Epic = 0.1, Mythic = 0 },
		WetCave = { Rare = 0.8, Epic = 0.4, Mythic = 0.1 },
		DeepCave = { Rare = 1.3, Epic = 1, Mythic = 0.6 },
		ExplorerCamp = { Rare = 1.2, Epic = 0.9, Mythic = 0.5 },
		Ancient = { Rare = 1.8, Epic = 2.2, Mythic = 1.6 },
		FinalChamber = { Rare = 2.2, Epic = 3, Mythic = 2.5 },
	} :: { [string]: { [string]: number } },
	-- Hidden rooms roll on a better table.
	HiddenRoomBias = { Common = 0.3, Uncommon = 1, Rare = 2.5, Epic = 3, Mythic = 3 },
	PickupRange = 9,
}
