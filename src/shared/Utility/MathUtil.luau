--!strict
local MathUtil = {}

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.inverseLerp(a: number, b: number, v: number): number
	if a == b then
		return 0
	end
	return math.clamp((v - a) / (b - a), 0, 1)
end

function MathUtil.remap(v: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return MathUtil.lerp(outMin, outMax, MathUtil.inverseLerp(inMin, inMax, v))
end

function MathUtil.smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Framerate-independent exponential approach: returns the blend factor for
-- moving toward a target with the given "speed" (1/seconds) over dt.
function MathUtil.damp(speed: number, dt: number): number
	return 1 - math.exp(-speed * dt)
end

function MathUtil.approach(current: number, target: number, maxDelta: number): number
	if current < target then
		return math.min(current + maxDelta, target)
	end
	return math.max(current - maxDelta, target)
end

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function MathUtil.randomUnitVector(rng: Random): Vector3
	local z = rng:NextNumber(-1, 1)
	local theta = rng:NextNumber(0, math.pi * 2)
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(theta), z, r * math.sin(theta))
end

function MathUtil.randomFlatDirection(rng: Random): Vector3
	local theta = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

-- Returns the closest point on segment ab to p and the parametric t.
function MathUtil.closestPointOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return a, 0
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return a + ab * t, t
end

function MathUtil.snapToGrid(v: Vector3, grid: number): Vector3
	return Vector3.new(
		math.round(v.X / grid) * grid,
		math.round(v.Y / grid) * grid,
		math.round(v.Z / grid) * grid
	)
end

return MathUtil
