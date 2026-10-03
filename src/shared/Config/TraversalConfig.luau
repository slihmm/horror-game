--!strict
-- Scripted traversals: rope descents, chimney climbs and rock squeezes.
-- The client animates its own character along the path; the server owns the
-- state (who is on which traversal, whether they are stuck) and validates
-- the timing of every exit.

export type KindConfig = {
	Speed: number, -- studs per second at full input
	Acceleration: number,
	PromptText: string,
	ReversePromptText: string,
	-- Server rejects exits faster than pathLength / Speed * MinTimeFactor^-1.
	MinTimeFactor: number,
	SwayAmplitude: number,
	StuckChance: number,
	Bidirectional: boolean,
}

local Kinds: { [string]: KindConfig } = {
	Rope = {
		Speed = 11,
		Acceleration = 14,
		PromptText = "Descend",
		ReversePromptText = "Climb the rope",
		MinTimeFactor = 1.35,
		SwayAmplitude = 0.35,
		StuckChance = 0,
		Bidirectional = true,
	},
	Climb = {
		Speed = 7,
		Acceleration = 10,
		PromptText = "Climb",
		ReversePromptText = "Climb down",
		MinTimeFactor = 1.35,
		SwayAmplitude = 0.15,
		StuckChance = 0,
		Bidirectional = true,
	},
	Squeeze = {
		Speed = 2.6,
		Acceleration = 6,
		PromptText = "Squeeze through",
		ReversePromptText = "Squeeze through",
		MinTimeFactor = 1.4,
		SwayAmplitude = 0.05,
		StuckChance = 0.45,
		Bidirectional = true,
	},
}

return {
	Kinds = Kinds,
	Stuck = {
		-- Alternating left/right effort needed to work free.
		Effort = NumberRange.new(9, 15),
		-- Effort a teammate adds per pull.
		HelpEffort = 4,
		HelpRange = 14,
		-- Struggling makes noise the monster can hear.
		StruggleNoise = 0.45,
		-- Where along the squeeze the wedge can happen (fraction of path).
		At = NumberRange.new(0.3, 0.7),
		MaxEffortPerSecond = 6,
	},
	PromptRange = 8,
	-- Players who disconnect/die mid-traversal are released after this.
	Timeout = 240,
}
