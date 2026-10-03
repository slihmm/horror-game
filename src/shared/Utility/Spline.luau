--!strict
-- Catmull-Rom spline sampling for organic tunnel centerlines.
local Spline = {}

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	-- Vector-first multiplication keeps this portable to the offline harness.
	local a = p1 * 2
	local b = (p2 - p0) * t
	local c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
	local d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
	return (a + b + c + d) * 0.5
end

-- Samples the spline through `points` so consecutive samples are roughly
-- `spacing` studs apart. The first and last control points are included.
function Spline.sample(points: { Vector3 }, spacing: number): { Vector3 }
	local count = #points
	if count < 2 then
		return table.clone(points)
	end
	local result = { points[1] }
	for i = 1, count - 1 do
		local p0 = points[math.max(i - 1, 1)]
		local p1 = points[i]
		local p2 = points[i + 1]
		local p3 = points[math.min(i + 2, count)]
		local steps = math.max(1, math.ceil((p2 - p1).Magnitude / spacing))
		for s = 1, steps do
			table.insert(result, catmullRom(p0, p1, p2, p3, s / steps))
		end
	end
	return result
end

function Spline.length(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

return Spline
