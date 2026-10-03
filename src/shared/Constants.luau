--!strict
-- Names shared between server and client: CollectionService tags, attribute
-- keys and folder names. Keeping them here avoids string typos drifting
-- between systems.
local Constants = {}

Constants.Tags = {
	HidingSpot = "HidingSpot",
	LoreObject = "LoreObject",
	LootItem = "LootItem",
	Traversal = "Traversal",
	ZoneVolume = "ZoneVolume",
	SecretVolume = "SecretVolume",
	Landmark = "Landmark",
	FlickerLight = "FlickerLight",
	AmbientEmitter = "AmbientEmitter",
	Hazard = "Hazard",
	MonsterRoot = "MonsterRoot",
	Headlamp = "Headlamp",
	ShadowAnchor = "ShadowAnchor",
	Leaderboard = "Leaderboard",
	RecursionCorridor = "RecursionCorridor",
}

-- Attributes written by the server (clients only read them).
Constants.Attributes = {
	-- Player
	Zone = "Zone",
	Depth = "Depth", -- studs below the cave entrance
	Progress = "Progress", -- path distance from the entrance (studs)
	RunState = "RunState",
	RunStart = "RunStart",
	Battery = "Battery", -- 0..1
	HeadlampOn = "HeadlampOn",
	HeadlampTint = "HeadlampTint",
	Hiding = "Hiding",
	Traversing = "Traversing",
	DataLoaded = "DataLoaded",
	Currency = "Currency",
	SatchelValue = "SatchelValue",
	LookPitch = "LookPitch",
	-- Character
	Stance = "Stance",
	Injured = "Injured",
	-- Monster root
	MonsterState = "MonsterState",
	MonsterStep = "MonsterStep",
	MonsterSpeed = "MonsterSpeed",
	MonsterVisible = "MonsterVisible",
	-- World objects
	LoreId = "LoreId",
	LootId = "LootId",
	SecretId = "SecretId",
	TraversalId = "TraversalId",
	ZoneId = "ZoneId",
	CaveSeed = "CaveSeed",
	CaveReady = "CaveReady",
}

Constants.Folders = {
	Cave = "Cave",
	Props = "CaveProps",
	Interactables = "Interactables",
	Volumes = "Volumes",
	Monster = "Monster",
	Remotes = "Remotes",
	Leaderboards = "Leaderboards",
	ClientEffects = "ClientEffects",
}

Constants.CollisionGroups = {
	Players = "Players",
	Traversing = "Traversing",
	Blockers = "SqueezeBlockers",
	Effects = "Effects",
}

Constants.RunStates = {
	Surface = "Surface",
	Underground = "Underground",
	Escaping = "Escaping",
	Escaped = "Escaped",
	Dead = "Dead",
}

Constants.Stances = {
	Stand = "Stand",
	Crouch = "Crouch",
}

return Constants
