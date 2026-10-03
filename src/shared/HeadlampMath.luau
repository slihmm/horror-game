--!strict
-- Shared headlamp formulas so the server's replicated lamp and the client's
-- local lamp always agree.
local HeadlampConfig = require(script.Parent.Config.HeadlampConfig)

local HeadlampMath = {}

-- Brightness multiplier for a battery level (0..1).
function HeadlampMath.BatteryScale(battery: number): number
	local cfg = HeadlampConfig.Battery
	if battery <= 0 then
		return 0
	end
	if battery >= cfg.LowThreshold then
		return 1
	end
	local t = battery / cfg.LowThreshold
	return cfg.EmptyBrightness + (1 - cfg.EmptyBrightness) * t
end

function HeadlampMath.TintColor(tint: string?): Color3
	return HeadlampConfig.Tints[tint or "Default"] or HeadlampConfig.Color
end

return HeadlampMath
