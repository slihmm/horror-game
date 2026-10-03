--!strict
-- Smooth pseudo-random noise helpers built on math.noise, used for camera
-- shake, flicker and organic variation.
local Noise = {}

-- Fractal 1D noise in roughly [-1, 1].
function Noise.fbm1(x: number, seed: number, octaves: number?): number
	local total = 0
	local amplitude = 1
	local frequency = 1
	local norm = 0
	for _ = 1, octaves or 3 do
		total += math.noise(x * frequency, seed, seed * 0.37) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return math.clamp(total / norm * 2, -1, 1)
end

function Noise.noise3(p: Vector3, scale: number, seed: number): number
	return math.noise(p.X * scale + seed, p.Y * scale - seed * 0.5, p.Z * scale + seed * 0.25)
end

return Noise
