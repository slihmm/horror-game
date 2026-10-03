--!strict
-- Procedural generation tuning. Story locations live in CaveLayout; this
-- file controls everything procedural that grows around them.
return {
	-- nil = random seed per server. Set a number to reproduce a layout.
	Seed = nil :: number?,

	-- Terrain voxel size. Periodic geometry (the recursion corridor) relies on
	-- translations that are multiples of this value.
	VoxelSize = 4,

	-- Rock thickness wrapped around every carved volume so no void is visible.
	ShellThickness = 16,
	-- Spacing between carve spheres along a tunnel centerline.
	CarveSpacing = 3,
	-- Floor height as a fraction of the vertical radius below the center.
	FloorFraction = 0.55,
	-- Yield to the scheduler every N terrain operations during building.
	OpsPerYield = 60,

	Tunnel = {
		-- Default radius when an edge doesn't specify one.
		Radius = NumberRange.new(6, 9),
		-- Lateral wander as a fraction of tunnel length (clamped).
		Wander = 0.22,
		MaxWander = 40,
		VerticalWander = 0.25,
		ControlSpacing = 42,
		-- Nav/tracking nodes are placed every N studs along tunnels.
		NodeSpacing = 16,
		RadiusNoiseScale = 0.045,
	},

	Branches = {
		PerTunnel = NumberRange.new(2, 4),
		-- Extra branches per 100 studs of tunnel length.
		PerHundredStuds = 1,
		MaxAttempts = 6,
		-- Minimum clearance between a new branch and unrelated geometry.
		Clearance = 10,
		HiddenRooms = NumberRange.new(9, 13),
		Types = {
			-- [type] = weight
			SideChamber = 10,
			DeadEnd = 6,
			Loop = 4,
			Collapsed = 3,
			Pit = 3,
			Pool = 3,
			Bridge = 2,
			Alcove = 4,
		} :: { [string]: number },
		-- Second pass: branches growing off branches.
		Secondary = {
			PerTunnel = NumberRange.new(0, 2),
			Types = {
				SideChamber = 6,
				DeadEnd = 6,
				Loop = 3,
				Collapsed = 2,
				Alcove = 2,
			} :: { [string]: number },
		},
		-- Per-zone multipliers on the weights above.
		ZoneWeights = {
			WetCave = { Pool = 3, Pit = 0.5 },
			DeepCave = { Pit = 2, Bridge = 1.5, DeadEnd = 1.4 },
			Ancient = { Collapsed = 0.3, Pool = 0.2, SideChamber = 1.4 },
			UpperCave = { Pit = 0.4, Bridge = 0, Loop = 1.5 },
		} :: { [string]: { [string]: number } },
	},

	-- What fills an optional side chamber. Deliberately includes empty and
	-- beautiful rooms: not every room should be scary.
	RoomContents = {
		Empty = 10,
		Beautiful = 5,
		Loot = 8,
		Lore = 6,
		Bones = 4,
		Wrong = 3,
		MiniCamp = 3,
		Hiding = 4,
	} :: { [string]: number },

	HiddenRoomContents = {
		Treasure = 5,
		Lore = 5,
		Disturbing = 4,
		Nothing = 2,
		Remains = 4,
	} :: { [string]: number },

	Decoration = {
		-- Formations per 100 studs of tunnel / per chamber.
		StalactitesPerHundred = 5,
		StalagmitesPerHundred = 4,
		BouldersPerHundred = 3,
		ChamberFormations = NumberRange.new(5, 12),
		-- Light shafts from the surface in the upper cave.
		UpperLightShafts = 3,
		-- Crevice hiding spots per 100 studs of monster-habitat tunnel.
		HidingAlcovesPerHundred = 1.2,
		-- Ceiling cracks that may drop rocks (Hazard).
		RockfallSpotsPerHundred = 0.5,
	},

	Water = {
		TunnelDepth = 1.6,
		PoolDepth = 9,
	},

	Pit = {
		Depth = NumberRange.new(70, 130),
		Radius = NumberRange.new(7, 11),
	},

	-- The impossible corridor between the Deep Cave and the Abandoned Camp.
	Recursion = {
		ModuleLength = 24, -- multiple of VoxelSize
		Modules = 9,
		-- Teleport happens when the player passes this module boundary and
		-- sends them back by TeleportModules.
		TriggerModule = 6,
		TeleportModules = 2,
		Laps = NumberRange.new(2, 4),
		Radius = 7,
	},

	-- The disorientation loop.
	Ring = {
		Radius = 56,
		TunnelRadius = 7.5,
		Segments = 20,
	},
}
