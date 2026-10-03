--!strict
-- Movement, stamina, damage and noise tuning for player characters.
return {
	Movement = {
		WalkSpeed = 9,
		SprintSpeed = 15.5,
		CrouchSpeed = 4.5,
		InjuredMultiplier = 0.72,
		-- Terrain floors that slow movement.
		SurfaceSpeedMultipliers = {
			[Enum.Material.Mud] = 0.78,
			[Enum.Material.Water] = 0.65,
			[Enum.Material.Sand] = 0.88,
		} :: { [Enum.Material]: number },
		JumpHeight = 4,
		CrouchCameraOffset = -1.7,
		-- Steep slate/mud slopes become slick above this angle (degrees).
		SlipAngle = 40,
		SlipAcceleration = 24,
	},

	Stamina = {
		Max = 1,
		DrainPerSecond = 1 / 7.5, -- ~7.5s of continuous sprint
		RegenPerSecond = 1 / 9,
		RegenDelay = 1.2,
		-- Once empty, sprint is locked until stamina recovers past this.
		ExhaustedRecoverThreshold = 0.35,
	},

	Health = {
		Max = 100,
		RegenDelay = 20,
		RegenPerSecond = 0.6,
		InjuredThreshold = 45,
	},

	Fall = {
		-- Downward speed (studs/s) at landing before damage starts.
		SafeVelocity = 62,
		LethalVelocity = 132,
		-- Damage scales from 0 at SafeVelocity to Max at LethalVelocity.
		MaxDamage = 100,
		StunVelocity = 75,
	},

	Drowning = {
		BreathSeconds = 14,
		DamagePerSecond = 12,
	},

	-- Noise a player emits (0..1 loudness). The monster hears noise within
	-- loudness * MonsterConfig.Hearing.Range studs.
	Noise = {
		Idle = 0,
		Crouch = 0.12,
		Walk = 0.35,
		Sprint = 0.85,
		Land = 0.7,
		HardLand = 1,
		Interaction = 0.25,
		HeadlampClick = 0.08,
		InWaterBonus = 0.15,
	},

	-- Anti-exploit: horizontal speed allowed before a correction.
	SpeedCheck = {
		Tolerance = 1.6,
		ViolationsBeforeCorrection = 3,
		Window = 1,
	},

	Spawn = {
		SurfaceSpawnRadius = 10,
	},
}
