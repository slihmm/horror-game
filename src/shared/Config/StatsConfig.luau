--!strict
-- Persistent statistics and their leaderboards.

export type StatDef = {
	Key: string,
	DisplayName: string,
	-- distance | depth | count | time
	Format: string,
	-- Leaderboard ordering: "desc" = higher is better.
	Order: string,
	-- 0 values are excluded from ascending boards (e.g. never escaped).
	IgnoreZero: boolean?,
}

local Stats: { StatDef } = {
	{ Key = "HighestDistance", DisplayName = "Furthest Reached", Format = "distance", Order = "desc" },
	{ Key = "DeepestDescent", DisplayName = "Deepest Descent", Format = "depth", Order = "desc" },
	{ Key = "Completions", DisplayName = "Escapes", Format = "count", Order = "desc" },
	{ Key = "TimeUnderground", DisplayName = "Time Underground", Format = "time", Order = "desc" },
	{ Key = "SecretsFound", DisplayName = "Secrets Found", Format = "count", Order = "desc" },
	{ Key = "FastestEscape", DisplayName = "Fastest Escape", Format = "time", Order = "asc", IgnoreZero = true },
}

return {
	Stats = Stats,
	-- 1 stud = 0.28 m (Roblox convention), used for display only.
	MetersPerStud = 0.28,
	LeaderboardSize = 10,
	LeaderboardRefresh = 150,
	-- OrderedDataStore names are prefixed with this + version, so a reset is
	-- a one-line change.
	LeaderboardPrefix = "LB_v1_",
}
