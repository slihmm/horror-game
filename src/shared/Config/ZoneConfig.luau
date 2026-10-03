--!strict
-- Every region of the cave has an identity: name, depth order, how intense
-- the Horror Director may get there, and which terrain materials it uses.
-- Lighting and ambience presets are keyed by the same ids
-- (see LightingConfig / AudioConfig).

export type Zone = {
	Id: string,
	DisplayName: string,
	Order: number,
	Underground: boolean,
	-- 0..1 multiplier on horror event probability and maximum tension.
	Intensity: number,
	-- Whether the monster may roam here on its own.
	MonsterHabitat: boolean,
	WallMaterial: Enum.Material,
	FloorMaterial: Enum.Material,
	AccentMaterial: Enum.Material,
	Reverb: Enum.ReverbType,
}

local Zones: { [string]: Zone } = {
	Surface = {
		Id = "Surface",
		DisplayName = "The Surface",
		Order = 0,
		Underground = false,
		Intensity = 0,
		MonsterHabitat = false,
		WallMaterial = Enum.Material.Rock,
		FloorMaterial = Enum.Material.Grass,
		AccentMaterial = Enum.Material.Ground,
		Reverb = Enum.ReverbType.Forest,
	},
	UpperCave = {
		Id = "UpperCave",
		DisplayName = "Upper Cave",
		Order = 1,
		Underground = true,
		Intensity = 0.15,
		MonsterHabitat = false,
		WallMaterial = Enum.Material.Rock,
		FloorMaterial = Enum.Material.Ground,
		AccentMaterial = Enum.Material.LeafyGrass,
		Reverb = Enum.ReverbType.Cave,
	},
	Shaft = {
		Id = "Shaft",
		DisplayName = "The Shaft",
		Order = 2,
		Underground = true,
		Intensity = 0.1,
		MonsterHabitat = false,
		WallMaterial = Enum.Material.Slate,
		FloorMaterial = Enum.Material.Rock,
		AccentMaterial = Enum.Material.Rock,
		Reverb = Enum.ReverbType.Quarry,
	},
	WetCave = {
		Id = "WetCave",
		DisplayName = "Wet Cave",
		Order = 3,
		Underground = true,
		Intensity = 0.35,
		MonsterHabitat = false,
		WallMaterial = Enum.Material.Slate,
		FloorMaterial = Enum.Material.Mud,
		AccentMaterial = Enum.Material.Rock,
		Reverb = Enum.ReverbType.SewerPipe,
	},
	DeepCave = {
		Id = "DeepCave",
		DisplayName = "Deep Cave",
		Order = 4,
		Underground = true,
		Intensity = 0.6,
		MonsterHabitat = true,
		WallMaterial = Enum.Material.Basalt,
		FloorMaterial = Enum.Material.Slate,
		AccentMaterial = Enum.Material.Rock,
		Reverb = Enum.ReverbType.StoneCorridor,
	},
	ExplorerCamp = {
		Id = "ExplorerCamp",
		DisplayName = "Abandoned Camp",
		Order = 5,
		Underground = true,
		Intensity = 0.5,
		MonsterHabitat = true,
		WallMaterial = Enum.Material.Rock,
		FloorMaterial = Enum.Material.Ground,
		AccentMaterial = Enum.Material.Slate,
		Reverb = Enum.ReverbType.StoneRoom,
	},
	Ancient = {
		Id = "Ancient",
		DisplayName = "The Old Works",
		Order = 6,
		Underground = true,
		Intensity = 0.8,
		MonsterHabitat = true,
		WallMaterial = Enum.Material.Limestone,
		FloorMaterial = Enum.Material.Sandstone,
		AccentMaterial = Enum.Material.Basalt,
		Reverb = Enum.ReverbType.StoneRoom,
	},
	FinalChamber = {
		Id = "FinalChamber",
		DisplayName = "The Gathering",
		Order = 7,
		Underground = true,
		Intensity = 0.9,
		MonsterHabitat = true,
		WallMaterial = Enum.Material.Basalt,
		FloorMaterial = Enum.Material.Ground,
		AccentMaterial = Enum.Material.Limestone,
		Reverb = Enum.ReverbType.Hangar,
	},
	Escape = {
		Id = "Escape",
		DisplayName = "The Climb",
		Order = 8,
		Underground = true,
		Intensity = 0.3,
		MonsterHabitat = false,
		WallMaterial = Enum.Material.Rock,
		FloorMaterial = Enum.Material.Ground,
		AccentMaterial = Enum.Material.Slate,
		Reverb = Enum.ReverbType.Cave,
	},
}

-- Terrain material colors applied once at boot. Cave rock reads far better
-- when it is darker and slightly warmer than Roblox defaults.
local MaterialColors: { [Enum.Material]: Color3 } = {
	[Enum.Material.Rock] = Color3.fromRGB(78, 72, 66),
	[Enum.Material.Slate] = Color3.fromRGB(58, 60, 62),
	[Enum.Material.Basalt] = Color3.fromRGB(38, 36, 38),
	[Enum.Material.Mud] = Color3.fromRGB(58, 46, 36),
	[Enum.Material.Ground] = Color3.fromRGB(74, 62, 50),
	[Enum.Material.Limestone] = Color3.fromRGB(122, 112, 96),
	[Enum.Material.Sandstone] = Color3.fromRGB(104, 88, 70),
	[Enum.Material.Grass] = Color3.fromRGB(66, 82, 52),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(58, 74, 46),
}

local ZoneConfig = {
	Zones = Zones,
	MaterialColors = MaterialColors,
	Default = "UpperCave",
}

function ZoneConfig.Get(zoneId: string?): Zone
	return Zones[zoneId or ""] or Zones[ZoneConfig.Default]
end

return ZoneConfig
