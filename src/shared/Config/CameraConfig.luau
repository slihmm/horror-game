--!strict
-- First-person camera feel. Values are intentionally subtle; the
-- "CameraMotion" player setting scales everything (accessibility).
return {
	FieldOfView = 72,
	SprintFieldOfView = 76,

	Bob = {
		WalkFrequency = 1.75, -- steps per stud-ish, scaled by speed
		WalkVertical = 0.07,
		WalkHorizontal = 0.045,
		SprintMultiplier = 1.8,
		CrouchMultiplier = 0.55,
		RollDegrees = 0.45,
	},

	Breathing = {
		IdleRate = 0.22, -- breaths per second
		IdleAmplitude = 0.018,
		ExhaustedRate = 0.75,
		ExhaustedAmplitude = 0.06,
	},

	Sway = {
		StrafeRollDegrees = 1.4,
		LookLagDegrees = 0.8,
	},

	Landing = {
		DipPerVelocity = 0.012,
		MaxDip = 0.9,
		Recovery = 7,
	},

	Shake = {
		-- Trauma decays per second; shake magnitude = trauma^2.
		Decay = 1.1,
		MaxDegrees = 2.6,
		MaxOffset = 0.18,
		Frequency = 16,
	},

	-- Narrow squeezes and crawlspaces.
	Squeeze = {
		FieldOfView = 58,
		HeightOffset = -1.2,
		BreathAmplitude = 0.05,
	},

	-- Forced lean down when standing at the lip of the shaft.
	Rope = {
		FieldOfView = 80,
		LookDownBias = 18,
	},
}
