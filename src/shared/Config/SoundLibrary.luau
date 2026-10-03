--!strict
-- Every sound in the game is referenced by a logical name. To give the game
-- its real voice, upload cave audio and paste the asset ids into `Id`.
--
-- Until then each entry falls back to an `rbxasset://` sound that ships with
-- the Roblox client, re-pitched to approximate the intended sound. Entries
-- with no fallback stay silent (the AudioController logs them once in Studio).
--
-- Pitch/Volume on the entry apply to the real asset; the Fallback table has
-- its own values because the substitutes need heavy re-pitching.

local Types = require(script.Parent.Parent.Types)
type SoundSpec = Types.SoundSpec

local FOOTSTEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local HIT = "rbxasset://sounds/hit.wav"
local COLLIDE = "rbxasset://sounds/collide.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local GROAN = "rbxasset://sounds/uuhhh.mp3"
local GLASS = "rbxasset://sounds/glassbreak.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local ROCKET = "rbxasset://sounds/Rocket shot.wav"
local GETUP = "rbxasset://sounds/action_get_up.mp3"
local FALLING = "rbxasset://sounds/action_falling.mp3"

local Sounds: { [string]: SoundSpec } = {
	-- Footsteps (one entry per surface group; see FootstepConfig in AudioConfig)
	Step_Stone = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 1.08, Volume = 0.55 } },
	Step_Dirt = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 0.82, Volume = 0.5 } },
	Step_Mud = { Id = "", Fallback = { Id = WATER, Pitch = 0.55, Volume = 0.22 } },
	Step_Water = { Id = "", Fallback = { Id = WATER, Pitch = 1.35, Volume = 0.3 } },
	Step_Wood = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 0.68, Volume = 0.6 } },
	Step_Metal = { Id = "", Fallback = { Id = COLLIDE, Pitch = 1.6, Volume = 0.25 } },
	Step_Gravel = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 1.3, Volume = 0.5 } },
	Step_Grass = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 0.75, Volume = 0.35 } },
	Land_Soft = { Id = "", Fallback = { Id = LAND, Pitch = 0.9, Volume = 0.5 } },
	Land_Hard = { Id = "", Fallback = { Id = LAND, Pitch = 0.6, Volume = 0.9 } },
	Splash = { Id = "", Fallback = { Id = WATER, Pitch = 0.9, Volume = 0.6 } },
	Wade = { Id = "", Fallback = { Id = SWIM, Pitch = 0.8, Volume = 0.35 } },

	-- Ambient one-shots
	Drip = { Id = "", Fallback = { Id = WATER, Pitch = 2.8, Volume = 0.16 } },
	DistantDrip = { Id = "", Fallback = { Id = WATER, Pitch = 3.2, Volume = 0.08 } },
	RockFall = { Id = "", Fallback = { Id = COLLIDE, Pitch = 0.42, Volume = 0.55 } },
	PebbleSkitter = { Id = "", Fallback = { Id = COLLIDE, Pitch = 1.4, Volume = 0.18 } },
	CaveCrack = { Id = "", Fallback = { Id = GLASS, Pitch = 0.22, Volume = 0.35 } },
	DistantFootsteps = { Id = "", Fallback = { Id = FOOTSTEP, Pitch = 0.78, Volume = 0.35 } },
	FaintBreathing = { Id = "", Fallback = { Id = GROAN, Pitch = 0.32, Volume = 0.08 } },
	WindGust = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.22, Volume = 0.3 } },
	Scrape = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.5, Volume = 0.25 } },
	DistantScream = { Id = "", Fallback = { Id = GROAN, Pitch = 0.62, Volume = 0.22 } },
	WaterMovement = { Id = "", Fallback = { Id = SWIM, Pitch = 0.6, Volume = 0.3 } },
	ObjectFall = { Id = "", Fallback = { Id = HIT, Pitch = 0.75, Volume = 0.35 } },
	DistantImpact = { Id = "", Fallback = { Id = ROCKET, Pitch = 0.18, Volume = 0.4 } },
	Unidentifiable = { Id = "", Fallback = { Id = PING, Pitch = 0.11, Volume = 0.14 } },
	Knock = { Id = "", Fallback = { Id = HIT, Pitch = 0.55, Volume = 0.3 } },
	Whisper = { Id = "" },
	Rumble = { Id = "", Fallback = { Id = ROCKET, Pitch = 0.1, Volume = 0.5 } },

	-- Ambient beds (looped). No usable built-in loops exist, so these stay
	-- silent until real assets are assigned.
	Bed_SurfaceWind = { Id = "", Looped = true },
	Bed_CaveAir = { Id = "", Looped = true },
	Bed_Water = { Id = "", Looped = true },
	Bed_DeepDrone = { Id = "", Looped = true },
	Bed_Ancient = { Id = "", Looped = true },
	Bed_Chamber = { Id = "", Looped = true },

	-- Monster
	MonsterStep = { Id = "", Fallback = { Id = HIT, Pitch = 0.2, Volume = 1 } },
	MonsterStepDebris = { Id = "", Fallback = { Id = COLLIDE, Pitch = 0.6, Volume = 0.3 } },
	MonsterBreath = { Id = "", Fallback = { Id = GROAN, Pitch = 0.22, Volume = 0.5 } },
	MonsterRoar = { Id = "", Fallback = { Id = GROAN, Pitch = 0.18, Volume = 1 } },
	MonsterGrowl = { Id = "", Fallback = { Id = GROAN, Pitch = 0.14, Volume = 0.6 } },
	MonsterScrape = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.18, Volume = 0.6 } },

	-- Player body / equipment
	BreathExhausted = { Id = "", Fallback = { Id = SWOOSH, Pitch = 1.6, Volume = 0.06 } },
	Heartbeat = { Id = "", Fallback = { Id = HIT, Pitch = 0.42, Volume = 0.45 } },
	HeadlampClick = { Id = "", Fallback = { Id = CLICK, Pitch = 0.7, Volume = 0.35 } },
	RopeCreak = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.2, Volume = 0.25 } },
	RopeSlide = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.35, Volume = 0.12 } },
	Struggle = { Id = "", Fallback = { Id = GETUP, Pitch = 0.75, Volume = 0.6 } },
	RockGrind = { Id = "", Fallback = { Id = SWOOSH, Pitch = 0.15, Volume = 0.45 } },
	Hurt = { Id = "", Fallback = { Id = GROAN, Pitch = 0.95, Volume = 0.5 } },
	FallScream = { Id = "", Fallback = { Id = FALLING, Pitch = 0.9, Volume = 0.6 } },
	PageTurn = { Id = "", Fallback = { Id = SWOOSH, Pitch = 1.8, Volume = 0.15 } },
	Pickup = { Id = "", Fallback = { Id = BUTTON, Pitch = 0.6, Volume = 0.25 } },
	TapeStatic = { Id = "", Looped = true },
	PlankCrack = { Id = "", Fallback = { Id = GLASS, Pitch = 0.4, Volume = 0.6 } },

	-- Voices for the mimic event ("Hey, over here."). Record a few short,
	-- breathy lines and assign them; the event is skipped while empty.
	Mimic_OverHere = { Id = "" },
	Mimic_Wait = { Id = "" },
	Mimic_Name = { Id = "" },

	-- Ending
	SurfaceBirds = { Id = "" },
}

return Sounds
