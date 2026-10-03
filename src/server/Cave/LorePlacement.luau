--!strict
-- Decides which lore entry goes in which slot (pure; no instances).
--
-- Order:
--   1. entries asking for a tagged slot (your own journal, newest camp)
--   2. entries anchored to a story location
--   3. hidden entries into hidden rooms, else any unanchored slot in zone
--   4. the remaining pool, shuffled, scattered through matching zones

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LoreData = require(Shared.Config.LoreData)
local Weighted = require(Shared.Utility.Weighted)
local Dress = require(script.Parent.DressContext)

type LoreEntry = LoreData.LoreEntry
type LoreSlot = Dress.LoreSlot

export type Placement = { Entry: LoreEntry, Slot: LoreSlot }

local LorePlacement = {}

function LorePlacement.Assign(entries: { LoreEntry }, slots: { LoreSlot }, rng: Random): ({ Placement }, { string })
	local placements: { Placement } = {}
	local warnings: { string } = {}
	local remaining: { LoreEntry } = table.clone(entries)
	local function take(entry: LoreEntry, slot: LoreSlot)
		slot.Used = true
		table.insert(placements, { Entry = entry, Slot = slot })
		local index = table.find(remaining, entry)
		if index then
			table.remove(remaining, index)
		end
	end
	local function firstSlot(predicate: (LoreSlot) -> boolean): LoreSlot?
		for _, slot in slots do
			if not slot.Used and predicate(slot) then
				return slot
			end
		end
		return nil
	end

	for _, entry in table.clone(remaining) do
		if entry.SlotTag then
			local slot = firstSlot(function(s)
				return s.Tag == entry.SlotTag
			end)
			if slot then
				take(entry, slot)
			end
		end
	end
	for _, entry in table.clone(remaining) do
		local anchor = entry.Anchor
		if anchor then
			local slot = firstSlot(function(s)
				return s.Anchor == anchor and s.Tag == nil
			end) or firstSlot(function(s)
				return s.Anchor == anchor
			end)
			if slot then
				take(entry, slot)
			else
				table.insert(warnings, `no slot left at {anchor} for '{entry.Id}'`)
			end
		end
	end
	for _, entry in table.clone(remaining) do
		if entry.Hidden then
			local zones = entry.Zones or {}
			local slot = firstSlot(function(s)
				return s.Hidden and table.find(zones, s.Zone) ~= nil
			end) or firstSlot(function(s)
				return s.Hidden
			end) or firstSlot(function(s)
				-- No hidden room took lore this run: tuck it somewhere quiet.
				return s.Anchor == nil and table.find(zones, s.Zone) ~= nil
			end)
			if slot then
				take(entry, slot)
			end
		end
	end
	local pool = {}
	for _, entry in remaining do
		if not entry.Anchor and not entry.Hidden then
			table.insert(pool, entry)
		end
	end
	Weighted.shuffle(pool, rng)
	for _, entry in pool do
		local zones = entry.Zones or {}
		local slot = firstSlot(function(s)
			return s.Anchor == nil and table.find(zones, s.Zone) ~= nil
		end)
		if slot then
			take(entry, slot)
		end
	end
	return placements, warnings
end

return LorePlacement
