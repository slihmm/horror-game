--!strict
-- Shared type definitions.

export type ZoneId = string

export type SoundSpec = {
	Id: string?,
	Volume: number?,
	Pitch: number?,
	Looped: boolean?,
	Fallback: {
		Id: string,
		Volume: number?,
		Pitch: number?,
	}?,
}

export type ProfileStats = {
	HighestDistance: number,
	DeepestDescent: number,
	Completions: number,
	TimeUnderground: number,
	SecretsFound: number,
	FastestEscape: number, -- 0 means "never escaped"
	Deaths: number,
	Expeditions: number,
}

export type Profile = {
	Version: number,
	Stats: ProfileStats,
	Secrets: { [string]: boolean },
	Lore: { [string]: boolean },
	Currency: number,
	Collection: { [string]: number },
	Cosmetics: { [string]: boolean },
	Flags: { [string]: boolean },
	Settings: { [string]: any },
}

-- Snapshot of a player's profile that the server sends to its owning client.
export type ProfileSnapshot = {
	Stats: ProfileStats,
	Lore: { string },
	SecretsFound: number,
	Currency: number,
	Collection: { [string]: number },
	Cosmetics: { string },
	Settings: { [string]: any },
	Satchel: { { id: string, count: number } },
	Persistent: boolean,
}

return {}
