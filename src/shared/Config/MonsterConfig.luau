--!strict
-- The Lamplighter. Server-authoritative AI tuning.
return {
	-- AI think rate (seconds). Movement integrates every Heartbeat, but
	-- perception and decisions only run at this interval.
	ThinkInterval = 0.2,
	-- Path requests are cached; replanning to a moving target is throttled.
	ReplanInterval = 1.2,

	Speeds = {
		Patrol = 6.5,
		Investigate = 9.5,
		Search = 7.5,
		Track = 12,
		Chase = 17.25, -- just faster than a sprinting player: break line of sight
		Returning = 8,
		Ambush = 0,
		TurnRate = 5, -- radians per second
	},

	Hearing = {
		-- A noise of loudness 1 is heard within this many studs.
		Range = 120,
		-- Multiplier when there is rock between the monster and the noise.
		OccludedMultiplier = 0.45,
		ListeningMultiplier = 1.7,
		-- Positional error as a fraction of distance: far noises are vague.
		Uncertainty = 0.22,
		MinUncertainty = 3,
	},

	Sight = {
		Range = 70,
		-- A lit headlamp is visible from much farther, even from behind rock
		-- corners if the beam itself is in view.
		HeadlampRange = 150,
		-- Without a headlamp the player is only a shape in the dark.
		DarkRange = 22,
		FieldOfView = 125, -- degrees
		CrouchMultiplier = 0.65,
		HidingMultiplier = 0.12,
		-- Anyone this close is noticed regardless of anything else.
		TouchRange = 6,
	},

	Awareness = {
		-- Per-player awareness 0..1 driving state changes.
		SightGain = 1.6, -- per second at point blank, scaled by distance
		NoiseGain = 0.5, -- per loudness unit heard
		Decay = 0.08, -- per second
		InvestigateThreshold = 0.2,
		TrackThreshold = 0.55,
		ChaseThreshold = 0.85,
	},

	Chase = {
		MaxDuration = 32,
		-- Seconds without seeing the target before giving up the chase.
		LoseSightTime = 4,
		-- After a chase ends the monster won't start another for a while
		-- unless a player literally walks into it.
		Cooldown = 45,
		KillRange = 5.5,
		-- Player loses this much health per hit; two hits kill.
		Damage = 60,
		HitCooldown = 1.6,
	},

	Search = {
		Duration = NumberRange.new(20, 38),
		Radius = 50,
		-- Chance the monster walks to a nearby hiding spot to check it.
		CheckHidingChance = 0.6,
		-- Chance a motionless, crouched player inside a checked spot is found.
		FindStillChance = 0.12,
		-- Chance a player who moves while being checked is found.
		FindMovingChance = 0.85,
		PeekTime = NumberRange.new(2, 4.5),
	},

	Listen = {
		Duration = NumberRange.new(2.5, 6),
		ChancePerPatrolNode = 0.22,
	},

	Patrol = {
		-- Prefer nodes not visited recently.
		MemorySize = 24,
		-- Chance to drift toward the area with players (it "feels" them).
		DriftTowardPlayersChance = 0.35,
		IdleTime = NumberRange.new(0.5, 3),
	},

	Ambush = {
		ChanceAfterSearch = 0.18,
		Duration = NumberRange.new(25, 50),
		TriggerRange = 18,
	},

	-- Activation is driven by story progress rather than time.
	Activation = {
		-- Monster stays dormant until a player reaches this anchor.
		WakeAnchor = "DeepHall",
		-- Before this anchor is reached the monster keeps its distance.
		FullHuntAnchor = "Camp",
		-- While "shy", it retreats when within this range of a player.
		ShyDistance = 55,
	},

	-- Client-side presentation of footsteps / presence.
	Presence = {
		StrideLength = 6.5,
		AudibleRange = 320,
		-- Beyond this distance only a fraction of steps are heard: BOOM...
		-- long silence... BOOM.
		SparseRange = 140,
		SparseMinChance = 0.25,
		ShakeRange = 60,
		BreathRange = 32,
		DebrisRange = 45,
		HeartbeatRange = 70,
	},

	Visual = {
		Height = 11.5,
		-- Number of dead explorer lamps fused to its head.
		Lamps = 5,
	},
}
