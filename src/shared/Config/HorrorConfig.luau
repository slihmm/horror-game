--!strict
-- Horror Director tuning. The director tracks a tension curve per player and
-- spends that tension on rare, subtle events. Silence is part of the design:
-- most ticks do nothing.

export type EventDef = {
	Weight: number,
	-- Seconds before this event can happen again for the same player.
	Cooldown: number,
	-- Tension range in which this event is eligible.
	Tension: NumberRange,
	-- Tension added when the event fires.
	Cost: number,
	-- Minimum zone Order (see ZoneConfig); nil = any underground zone.
	MinOrder: number?,
	MaxOrder: number?,
	Phases: { string },
	RequiresAlone: boolean?,
	RequiresTeammate: boolean?,
	-- Blocked while the monster is in one of these states.
	BlockedMonsterStates: { string }?,
	-- Requires a sound asset to be assigned (skipped otherwise).
	RequiresSound: string?,
}

local CHASING = { "Chasing", "Tracking" }

local Events: { [string]: EventDef } = {
	DistantFootsteps = { Weight = 6, Cooldown = 160, Tension = NumberRange.new(0.1, 0.8), Cost = 0.08, MinOrder = 1, Phases = { "Unease", "Build" } },
	FootstepsBehind = { Weight = 3, Cooldown = 320, Tension = NumberRange.new(0.25, 0.85), Cost = 0.16, MinOrder = 3, Phases = { "Build", "Peak" }, RequiresAlone = true, BlockedMonsterStates = CHASING },
	ShadowSighting = { Weight = 4, Cooldown = 260, Tension = NumberRange.new(0.2, 0.9), Cost = 0.18, MinOrder = 3, Phases = { "Build", "Peak" }, BlockedMonsterStates = CHASING },
	ShadowBehind = { Weight = 1.5, Cooldown = 480, Tension = NumberRange.new(0.4, 0.95), Cost = 0.22, MinOrder = 4, Phases = { "Peak" }, RequiresAlone = true, BlockedMonsterStates = CHASING },
	EchoWalker = { Weight = 2.5, Cooldown = 400, Tension = NumberRange.new(0.2, 0.9), Cost = 0.15, MinOrder = 3, Phases = { "Build", "Peak" }, BlockedMonsterStates = CHASING },
	BeamGlint = { Weight = 3, Cooldown = 220, Tension = NumberRange.new(0.15, 0.85), Cost = 0.1, MinOrder = 3, Phases = { "Unease", "Build", "Peak" } },
	RockFall = { Weight = 3, Cooldown = 200, Tension = NumberRange.new(0, 0.7), Cost = 0.12, MinOrder = 1, Phases = { "Unease", "Build" } },
	LightFlicker = { Weight = 5, Cooldown = 120, Tension = NumberRange.new(0.05, 0.9), Cost = 0.06, MinOrder = 1, Phases = { "Unease", "Build", "Peak" } },
	TemporaryDarkness = { Weight = 1.2, Cooldown = 600, Tension = NumberRange.new(0.45, 1), Cost = 0.25, MinOrder = 4, Phases = { "Peak" }, BlockedMonsterStates = CHASING },
	DistantScream = { Weight = 1.2, Cooldown = 700, Tension = NumberRange.new(0.3, 0.9), Cost = 0.2, MinOrder = 3, Phases = { "Build", "Peak" } },
	ObjectShift = { Weight = 2, Cooldown = 360, Tension = NumberRange.new(0.15, 0.8), Cost = 0.1, MinOrder = 3, Phases = { "Unease", "Build" } },
	WaterDisturbance = { Weight = 3, Cooldown = 200, Tension = NumberRange.new(0.1, 0.8), Cost = 0.08, MinOrder = 3, MaxOrder = 4, Phases = { "Unease", "Build" } },
	DistantMonster = { Weight = 3, Cooldown = 300, Tension = NumberRange.new(0.2, 0.85), Cost = 0.18, MinOrder = 3, Phases = { "Build", "Peak" }, BlockedMonsterStates = CHASING },
	Silence = { Weight = 2.5, Cooldown = 300, Tension = NumberRange.new(0.2, 0.9), Cost = 0.1, MinOrder = 2, Phases = { "Build", "Peak" } },
	Knocking = { Weight = 1.5, Cooldown = 500, Tension = NumberRange.new(0.3, 0.9), Cost = 0.14, MinOrder = 4, Phases = { "Build", "Peak" } },
	Whisper = { Weight = 1, Cooldown = 600, Tension = NumberRange.new(0.4, 1), Cost = 0.15, MinOrder = 5, Phases = { "Peak" }, RequiresAlone = true, RequiresSound = "Whisper" },
	MimicVoice = { Weight = 2, Cooldown = 700, Tension = NumberRange.new(0.3, 0.9), Cost = 0.22, MinOrder = 3, Phases = { "Build", "Peak" }, RequiresTeammate = true, RequiresSound = "Mimic_OverHere", BlockedMonsterStates = CHASING },
	MimicFootsteps = { Weight = 2.5, Cooldown = 420, Tension = NumberRange.new(0.2, 0.9), Cost = 0.16, MinOrder = 3, Phases = { "Build", "Peak" }, RequiresTeammate = true, BlockedMonsterStates = CHASING },
}

-- The tension curve: Calm -> Unease -> Build -> Peak -> Relief -> Calm ...
-- EventChance is the probability per director tick that *something* fires.
local Phases = {
	Calm = { Duration = NumberRange.new(70, 160), EventChance = 0, Next = "Unease" },
	Unease = { Duration = NumberRange.new(90, 180), EventChance = 0.05, Next = "Build" },
	Build = { Duration = NumberRange.new(90, 200), EventChance = 0.09, Next = "Peak" },
	Peak = { Duration = NumberRange.new(40, 90), EventChance = 0.16, Next = "Relief" },
	Relief = { Duration = NumberRange.new(60, 140), EventChance = 0, Next = "Calm" },
}

return {
	Events = Events,
	Phases = Phases,
	TickInterval = 3,
	-- Tension slowly drains toward 0 per second.
	TensionDecay = 0.004,
	-- No two events closer than this for one player (seconds).
	MinGap = 40,
	-- Chance a whole Build phase is "dry": nothing at all happens.
	DryPhaseChance = 0.25,
	-- A player is "alone" if no teammate is within this distance.
	AloneDistance = 70,
	-- After a monster chase, force Relief (temporary safety).
	PostChaseRelief = true,
	-- Recorded paths for EchoWalker: sample interval and history length.
	PathRecordInterval = 1,
	PathRecordLength = 600,
	-- Landmark revisit detection (the loop).
	LandmarkRadius = 14,
	LandmarkLeaveDistance = 70,
}
