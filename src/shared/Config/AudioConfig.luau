--!strict
-- Dynamic ambient audio tuning. The AudioController picks one-shots from the
-- current zone's pool with weights, per-sound cooldowns and a global gap, and
-- places them in 3D around the listener.

export type AmbientEntry = {
	Sound: string,
	Weight: number,
	Distance: NumberRange, -- studs from the listener
	Cooldown: number, -- seconds before this entry may repeat
	BehindBias: number?, -- 0..1 chance the sound is placed behind the player
	Volume: NumberRange?,
	Pitch: NumberRange?,
	Burst: number?, -- play this many times in quick succession
	Above: boolean?, -- place above the listener (drips, cracks)
}

export type ZoneAmbience = {
	Beds: { { Sound: string, Volume: number } },
	-- Seconds between one-shots (random within range).
	Gap: NumberRange,
	Pool: { AmbientEntry },
}

local function entry(sound: string, weight: number, near: number, far: number, cooldown: number, extra: { [string]: any }?): AmbientEntry
	local e: { [string]: any } = {
		Sound = sound,
		Weight = weight,
		Distance = NumberRange.new(near, far),
		Cooldown = cooldown,
	}
	if extra then
		for k, v in extra do
			e[k] = v
		end
	end
	return (e :: any) :: AmbientEntry
end

local Zones: { [string]: ZoneAmbience } = {
	Surface = {
		Beds = { { Sound = "Bed_SurfaceWind", Volume = 0.4 } },
		Gap = NumberRange.new(10, 25),
		Pool = {
			entry("WindGust", 5, 20, 60, 8),
		},
	},
	UpperCave = {
		Beds = { { Sound = "Bed_CaveAir", Volume = 0.3 }, { Sound = "Bed_SurfaceWind", Volume = 0.12 } },
		Gap = NumberRange.new(7, 18),
		Pool = {
			entry("Drip", 10, 6, 24, 2, { Above = true }),
			entry("DistantDrip", 6, 30, 70, 4),
			entry("WindGust", 4, 20, 60, 15),
			entry("PebbleSkitter", 3, 10, 30, 20),
			entry("RockFall", 1, 40, 90, 60),
		},
	},
	Shaft = {
		Beds = { { Sound = "Bed_CaveAir", Volume = 0.35 } },
		Gap = NumberRange.new(6, 16),
		Pool = {
			entry("PebbleSkitter", 6, 8, 30, 6, { Above = true }),
			entry("DistantDrip", 6, 20, 60, 3),
			entry("WindGust", 3, 10, 40, 14, { Above = true }),
			entry("CaveCrack", 1, 30, 80, 70),
		},
	},
	WetCave = {
		Beds = { { Sound = "Bed_Water", Volume = 0.35 }, { Sound = "Bed_CaveAir", Volume = 0.2 } },
		Gap = NumberRange.new(5, 14),
		Pool = {
			entry("Drip", 14, 4, 20, 1, { Above = true }),
			entry("DistantDrip", 8, 25, 70, 2),
			entry("WaterMovement", 3, 20, 60, 25, { BehindBias = 0.5 }),
			entry("PebbleSkitter", 2, 10, 30, 30),
			entry("Scrape", 1, 30, 70, 90, { BehindBias = 0.6 }),
			entry("Unidentifiable", 0.6, 40, 90, 160),
		},
	},
	DeepCave = {
		Beds = { { Sound = "Bed_DeepDrone", Volume = 0.35 } },
		Gap = NumberRange.new(9, 26),
		Pool = {
			entry("DistantDrip", 6, 25, 80, 3),
			entry("RockFall", 2, 40, 120, 45),
			entry("CaveCrack", 2, 30, 90, 50),
			entry("DistantImpact", 1.2, 80, 160, 70),
			entry("Scrape", 1.5, 20, 60, 60, { BehindBias = 0.7 }),
			entry("DistantFootsteps", 0.8, 30, 70, 150, { BehindBias = 0.8, Burst = 4 }),
			entry("FaintBreathing", 0.4, 8, 16, 240, { BehindBias = 0.9 }),
			entry("Unidentifiable", 1, 50, 120, 90),
		},
	},
	ExplorerCamp = {
		Beds = { { Sound = "Bed_CaveAir", Volume = 0.25 }, { Sound = "Bed_DeepDrone", Volume = 0.15 } },
		Gap = NumberRange.new(10, 26),
		Pool = {
			entry("DistantDrip", 6, 20, 60, 3),
			entry("ObjectFall", 2, 15, 50, 60, { BehindBias = 0.6 }),
			entry("Knock", 0.8, 20, 50, 160),
			entry("Scrape", 1.5, 20, 60, 60),
			entry("DistantScream", 0.4, 120, 200, 300),
		},
	},
	Ancient = {
		Beds = { { Sound = "Bed_Ancient", Volume = 0.35 } },
		-- The Old Works are quiet. Long silences make each sound land harder.
		Gap = NumberRange.new(16, 40),
		Pool = {
			entry("DistantImpact", 2, 80, 160, 50),
			entry("Unidentifiable", 3, 40, 120, 45),
			entry("Scrape", 1.5, 20, 60, 70, { BehindBias = 0.8 }),
			entry("FaintBreathing", 0.6, 6, 14, 200, { BehindBias = 1 }),
			entry("Whisper", 0.5, 4, 10, 260, { BehindBias = 1 }),
			entry("Knock", 1, 30, 70, 120),
		},
	},
	FinalChamber = {
		Beds = { { Sound = "Bed_Chamber", Volume = 0.4 } },
		Gap = NumberRange.new(12, 30),
		Pool = {
			entry("RockFall", 2, 80, 200, 40),
			entry("DistantImpact", 2, 100, 220, 50),
			entry("DistantDrip", 4, 40, 120, 4),
			entry("Unidentifiable", 2, 60, 160, 60),
			entry("DistantScream", 0.5, 160, 260, 240),
		},
	},
	Escape = {
		Beds = { { Sound = "Bed_CaveAir", Volume = 0.3 }, { Sound = "Bed_SurfaceWind", Volume = 0.1 } },
		Gap = NumberRange.new(8, 20),
		Pool = {
			entry("PebbleSkitter", 4, 6, 24, 10, { Above = true }),
			entry("WindGust", 4, 20, 60, 12, { Above = true }),
			entry("DistantImpact", 1, 120, 220, 80),
		},
	},
}

return {
	Zones = Zones,
	Groups = {
		Master = 1,
		Ambient = 0.9,
		Footsteps = 0.8,
		Effects = 1,
		Monster = 1,
		Voice = 1,
		UI = 0.6,
	} :: { [string]: number },
	-- Randomization applied to every one-shot.
	DefaultVolumeJitter = NumberRange.new(0.75, 1.1),
	DefaultPitchJitter = NumberRange.new(0.9, 1.08),
	-- Max simultaneously playing ambient one-shots.
	MaxConcurrent = 4,
	-- Beds crossfade time when changing zones.
	BedFade = 5,
	-- Low-pass effect when deep underground: high-gain (dB) at max depth.
	DepthMuffle = {
		StartDepth = 60,
		FullDepth = 500,
		HighGainAtFull = -14,
	},
	BedFadeOutWhileSilenced = 2,

	Footsteps = {
		StrideWalk = 4.2,
		StrideSprint = 5.6,
		StrideCrouch = 3.1,
		MaxHearDistance = 85,
		MaterialGroups = {
			[Enum.Material.Rock] = "Stone",
			[Enum.Material.Slate] = "Stone",
			[Enum.Material.Basalt] = "Stone",
			[Enum.Material.Limestone] = "Stone",
			[Enum.Material.Sandstone] = "Stone",
			[Enum.Material.Pavement] = "Stone",
			[Enum.Material.Granite] = "Stone",
			[Enum.Material.Marble] = "Stone",
			[Enum.Material.Concrete] = "Stone",
			[Enum.Material.Cobblestone] = "Stone",
			[Enum.Material.Brick] = "Stone",
			[Enum.Material.Ground] = "Dirt",
			[Enum.Material.Sand] = "Dirt",
			[Enum.Material.Fabric] = "Dirt",
			[Enum.Material.Mud] = "Mud",
			[Enum.Material.Water] = "Water",
			[Enum.Material.Wood] = "Wood",
			[Enum.Material.WoodPlanks] = "Wood",
			[Enum.Material.Metal] = "Metal",
			[Enum.Material.CorrodedMetal] = "Metal",
			[Enum.Material.DiamondPlate] = "Metal",
			[Enum.Material.Pebble] = "Gravel",
			[Enum.Material.Salt] = "Gravel",
			[Enum.Material.Grass] = "Grass",
			[Enum.Material.LeafyGrass] = "Grass",
		} :: { [Enum.Material]: string },
		StanceVolume = {
			Crouch = 0.35,
			Walk = 0.7,
			Sprint = 1,
		},
	},
}
