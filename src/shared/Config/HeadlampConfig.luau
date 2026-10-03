--!strict
-- The headlamp is the player's primary tool. A narrow bright core beam plus
-- a dim wide spill: the center reads clearly, edges stay in darkness.
return {
	Color = Color3.fromRGB(255, 241, 218),

	Core = {
		Brightness = 2.4,
		Range = 60,
		Angle = 44,
		Shadows = true,
	},

	Spill = {
		Brightness = 0.32,
		Range = 24,
		Angle = 118,
		Shadows = false,
	},

	-- A faint glow around the player so hands/feet are never pitch black.
	Self = {
		Brightness = 0.12,
		Range = 7,
	},

	-- Offset from the camera (local space) so the beam origin sits on the
	-- forehead and casts visible shadows from nearby rocks.
	CameraOffset = Vector3.new(0.35, 0.25, 0),
	-- How quickly the beam follows the view (higher = snappier).
	FollowSharpness = 22,

	-- Replicated lamp on other players' heads.
	Remote = {
		Brightness = 2.0,
		Range = 52,
		Angle = 46,
		Shadows = false,
		PitchSendRate = 8, -- updates per second
	},

	Battery = {
		-- Seconds of continuous use from full.
		Lifetime = 26 * 60,
		LowThreshold = 0.2,
		CriticalThreshold = 0.06,
		-- Brightness multiplier at 0% (linear down from LowThreshold).
		EmptyBrightness = 0.12,
		StartCharge = 0.82,
	},

	Flicker = {
		-- Baseline chance per second of a subtle flicker burst.
		AmbientChancePerSecond = 0.012,
		LowBatteryChancePerSecond = 0.12,
		BurstDuration = NumberRange.new(0.12, 0.6),
		MinBrightnessScale = 0.05,
	},

	-- Tints unlocked as cosmetics (see LootConfig).
	Tints = {
		Default = Color3.fromRGB(255, 241, 218),
		Amber = Color3.fromRGB(255, 196, 128),
		Arctic = Color3.fromRGB(214, 232, 255),
		Sodium = Color3.fromRGB(255, 176, 92),
		Pale = Color3.fromRGB(236, 240, 228),
	} :: { [string]: Color3 },

	ToggleCooldown = 0.35,
}
