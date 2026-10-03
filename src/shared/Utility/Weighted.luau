--!strict
-- Weighted random selection helpers.
local Weighted = {}

-- Picks a key from a { [key]: weight } map.
function Weighted.pickKey<K>(weights: { [K]: number }, rng: Random): K?
	local total = 0
	for _, w in weights do
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local last: K? = nil
	for key, w in weights do
		if w > 0 then
			roll -= w
			last = key
			if roll <= 0 then
				return key
			end
		end
	end
	return last
end

-- Picks an element from an array using a weight accessor.
function Weighted.pick<T>(items: { T }, getWeight: (T) -> number, rng: Random): T?
	local total = 0
	for _, item in items do
		total += math.max(0, getWeight(item))
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, item in items do
		roll -= math.max(0, getWeight(item))
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

function Weighted.shuffle<T>(items: { T }, rng: Random): { T }
	for i = #items, 2, -1 do
		local j = rng:NextInteger(1, i)
		items[i], items[j] = items[j], items[i]
	end
	return items
end

return Weighted
