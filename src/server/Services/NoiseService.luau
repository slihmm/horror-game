--!strict
-- Every audible gameplay event in the world goes through here: footsteps,
-- landings, struggling in a squeeze, rocks falling, a headlamp click. The
-- monster listens to this stream; it never sees players directly through it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Utility.Signal)

export type Noise = {
	Position: Vector3,
	Loudness: number, -- 0..1+, scaled by MonsterConfig.Hearing.Range
	Source: Player?,
	Kind: string,
	Time: number,
}

local NoiseService = {
	Emitted = Signal.new() :: Signal.Signal<Noise>,
}

function NoiseService.Emit(position: Vector3, loudness: number, kind: string, source: Player?)
	if loudness <= 0 then
		return
	end
	NoiseService.Emitted:Fire({
		Position = position,
		Loudness = loudness,
		Source = source,
		Kind = kind,
		Time = os.clock(),
	})
end

return NoiseService
