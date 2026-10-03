--!strict
-- Per-zone lighting presets applied locally by the client's
-- LightingController. Each player sees the lighting of the zone they are in,
-- so a teammate on the surface never lights up the cave for you.
--
-- Underground presets keep Ambient/OutdoorAmbient near black: the headlamp
-- and placed light sources must do all the work.

export type Preset = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Brightness: number,
	ClockTime: number,
	ExposureCompensation: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	Atmosphere: {
		Density: number,
		Offset: number,
		Color: Color3,
		Decay: Color3,
		Glare: number,
		Haze: number,
	},
	ColorCorrection: {
		Brightness: number,
		Contrast: number,
		Saturation: number,
		TintColor: Color3,
	},
	Bloom: {
		Intensity: number,
		Size: number,
		Threshold: number,
	},
	-- Density of the dust motes that drift through the headlamp beam.
	Dust: number,
	-- Rate of drips falling from the ceiling near the player.
	Drips: number,
}

local BLACK = Color3.new(0, 0, 0)

local function cave(overrides: { [string]: any }): Preset
	local preset: { [string]: any } = {
		Ambient = Color3.fromRGB(3, 3, 4),
		OutdoorAmbient = BLACK,
		Brightness = 0,
		ClockTime = 0,
		ExposureCompensation = 0.15,
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.35,
		Atmosphere = {
			Density = 0.42,
			Offset = 0,
			Color = Color3.fromRGB(10, 10, 11),
			Decay = Color3.fromRGB(4, 4, 5),
			Glare = 0,
			Haze = 1.2,
		},
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.12,
			Saturation = -0.28,
			TintColor = Color3.fromRGB(248, 246, 255),
		},
		Bloom = { Intensity = 0.35, Size = 18, Threshold = 1.4 },
		Dust = 0.6,
		Drips = 0.2,
	}
	for key, value in overrides do
		if type(value) == "table" and type(preset[key]) == "table" then
			for k, v in value do
				preset[key][k] = v
			end
		else
			preset[key] = value
		end
	end
	return (preset :: any) :: Preset
end

local Presets: { [string]: Preset } = {
	-- Used by the ending: the first morning after the night underground.
	Dawn = {
		Ambient = Color3.fromRGB(96, 92, 88),
		OutdoorAmbient = Color3.fromRGB(128, 122, 118),
		Brightness = 2.2,
		ClockTime = 7.1,
		ExposureCompensation = 0.25,
		EnvironmentDiffuseScale = 0.8,
		EnvironmentSpecularScale = 0.6,
		Atmosphere = {
			Density = 0.3,
			Offset = 0.2,
			Color = Color3.fromRGB(214, 200, 186),
			Decay = Color3.fromRGB(150, 130, 120),
			Glare = 0.6,
			Haze = 1.4,
		},
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.04,
			Saturation = -0.05,
			TintColor = Color3.fromRGB(255, 246, 236),
		},
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 0.95 },
		Dust = 0,
		Drips = 0,
	},
	Surface = {
		Ambient = Color3.fromRGB(70, 74, 82),
		OutdoorAmbient = Color3.fromRGB(96, 100, 110),
		Brightness = 1.6,
		ClockTime = 17.6,
		ExposureCompensation = -0.1,
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.5,
		Atmosphere = {
			Density = 0.34,
			Offset = 0.12,
			Color = Color3.fromRGB(176, 180, 186),
			Decay = Color3.fromRGB(110, 112, 120),
			Glare = 0.2,
			Haze = 1.8,
		},
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.06,
			Saturation = -0.18,
			TintColor = Color3.fromRGB(246, 246, 255),
		},
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.1 },
		Dust = 0,
		Drips = 0,
	},
	-- Natural light still leaks in from above: the sun is up, so daylight
	-- falls through the cracks in the ceiling and pools on the floor.
	UpperCave = cave({
		Ambient = Color3.fromRGB(9, 9, 10),
		Brightness = 1.4,
		ClockTime = 13.5,
		Atmosphere = { Density = 0.36, Color = Color3.fromRGB(22, 22, 24), Haze = 1.6 },
		ColorCorrection = { Saturation = -0.18 },
		Dust = 0.9,
		Drips = 0.1,
	}),
	Shaft = cave({
		Ambient = Color3.fromRGB(4, 4, 5),
		Atmosphere = { Density = 0.48, Haze = 2.2 },
		Dust = 1,
	}),
	-- Water, reflections, dripping walls. Slightly cold.
	WetCave = cave({
		EnvironmentSpecularScale = 0.8,
		Atmosphere = { Density = 0.45, Color = Color3.fromRGB(9, 11, 13), Haze = 2.4 },
		ColorCorrection = { TintColor = Color3.fromRGB(236, 246, 255), Saturation = -0.22 },
		Dust = 0.3,
		Drips = 1,
	}),
	-- Almost completely dark.
	DeepCave = cave({
		Ambient = Color3.fromRGB(1, 1, 1),
		ExposureCompensation = 0,
		Atmosphere = { Density = 0.5, Color = Color3.fromRGB(5, 5, 6), Haze = 0.6 },
		ColorCorrection = { Contrast = 0.18, Saturation = -0.38 },
		Dust = 0.4,
		Drips = 0.3,
	}),
	-- Human remnants: warmer tones from abandoned lanterns.
	ExplorerCamp = cave({
		Ambient = Color3.fromRGB(3, 2, 2),
		Atmosphere = { Density = 0.44, Color = Color3.fromRGB(14, 11, 9) },
		ColorCorrection = { TintColor = Color3.fromRGB(255, 244, 232), Saturation = -0.24 },
		Dust = 0.8,
	}),
	-- Unnatural: a faint sickly cast, stillness, no dust.
	Ancient = cave({
		Ambient = Color3.fromRGB(2, 3, 2),
		Atmosphere = { Density = 0.4, Color = Color3.fromRGB(9, 11, 8), Haze = 0.4 },
		ColorCorrection = { TintColor = Color3.fromRGB(240, 255, 236), Contrast = 0.2, Saturation = -0.34 },
		Dust = 0.1,
		Drips = 0,
	}),
	-- Huge and heavy: the fog is thinner so the scale is felt.
	FinalChamber = cave({
		Ambient = Color3.fromRGB(2, 2, 3),
		Atmosphere = { Density = 0.3, Color = Color3.fromRGB(8, 8, 10), Haze = 2.8 },
		ColorCorrection = { Contrast = 0.22, Saturation = -0.42 },
		Dust = 1.2,
		Drips = 0.1,
	}),
	-- The way out: morning light reaches in from the exit.
	Escape = cave({
		Ambient = Color3.fromRGB(4, 4, 5),
		Brightness = 0.8,
		ClockTime = 7.2,
		Atmosphere = { Density = 0.4, Color = Color3.fromRGB(14, 14, 16) },
		Dust = 0.7,
	}),
}

return {
	Presets = Presets,
	-- Seconds to blend between zone presets.
	TransitionTime = 4,
	-- Player brightness setting maps to ExposureCompensation in this range.
	BrightnessSettingRange = NumberRange.new(-0.4, 0.6),
}
