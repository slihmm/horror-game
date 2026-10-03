--!strict
-- The handcrafted spine of the cave. Story locations are placed deliberately
-- here; the generator wanders tunnels between them, grows procedural branches
-- off those tunnels and fills them with content.
--
-- Vertical connections (Rope/Climb) carve their shaft at the *bottom*
-- anchor's XZ; the top anchor must sit horizontally clear of the shaft so its
-- floor doesn't cap it (a short connector tunnel joins them).
--
-- Positions are approximate: anchors with `Jitter` move a little each run so
-- the cave is familiar but never identical.

export type Anchor = {
	Id: string,
	Zone: string,
	Position: Vector3,
	Builder: string,
	-- Horizontal and vertical chamber radii.
	Radius: number?,
	Height: number?,
	Jitter: number?,
}

export type SpineEdge = {
	From: string,
	To: string,
	-- Surface | Tunnel | Rope | Climb | Recursion
	Kind: string,
	Zone: string?,
	Radius: NumberRange?,
	FromPort: string?,
	ToPort: string?,
	Flooded: boolean?,
	-- Insert a squeeze traversal halfway along the tunnel.
	Squeeze: boolean?,
	-- Only the monster uses this route; no branches grow off it.
	NoBranches: boolean?,
	Wander: number?,
}

local V = Vector3.new

local Anchors: { Anchor } = {
	{ Id = "SurfaceCamp", Zone = "Surface", Position = V(0, 0, 0), Builder = "SurfaceCamp" },
	{ Id = "Mouth", Zone = "UpperCave", Position = V(76, -2, 0), Builder = "CaveMouth", Radius = 11, Height = 10 },
	{ Id = "UpperHall", Zone = "UpperCave", Position = V(160, -34, 26), Builder = "UpperHall", Radius = 32, Height = 20, Jitter = 8 },
	{ Id = "ShaftTop", Zone = "Shaft", Position = V(212, -48, 52), Builder = "ShaftTop", Radius = 12, Height = 9 },
	{ Id = "ShaftBottom", Zone = "WetCave", Position = V(244, -302, 72), Builder = "ShaftBottom", Radius = 26, Height = 16 },
	{ Id = "Cistern", Zone = "WetCave", Position = V(404, -318, 176), Builder = "Cistern", Radius = 34, Height = 18, Jitter = 12 },
	{ Id = "Ring", Zone = "WetCave", Position = V(560, -334, 316), Builder = "LoopRing" },
	{ Id = "DeepHall", Zone = "DeepCave", Position = V(716, -366, 232), Builder = "DeepHall", Radius = 28, Height = 18, Jitter = 8 },
	{ Id = "Camp", Zone = "ExplorerCamp", Position = V(724, -384, -96), Builder = "ExplorerCamp", Radius = 30, Height = 16 },
	{ Id = "Hollow", Zone = "DeepCave", Position = V(590, -404, -214), Builder = "Lair", Radius = 24, Height = 15, Jitter = 10 },
	{ Id = "Threshold", Zone = "Ancient", Position = V(880, -434, -176), Builder = "AncientGate", Radius = 24, Height = 18 },
	{ Id = "Colonnade", Zone = "Ancient", Position = V(1012, -470, -288), Builder = "Colonnade", Radius = 36, Height = 22, Jitter = 6 },
	{ Id = "FinalChamber", Zone = "FinalChamber", Position = V(1196, -548, -196), Builder = "FinalChamber", Radius = 92, Height = 54 },
	{ Id = "ChimneyBase", Zone = "Escape", Position = V(1326, -566, -98), Builder = "ChimneyBase", Radius = 13, Height = 10 },
	{ Id = "ChimneyTop", Zone = "Escape", Position = V(1358, -336, -98), Builder = "ChimneyTop", Radius = 13, Height = 10 },
	{ Id = "Chimney2Base", Zone = "Escape", Position = V(1452, -306, -40), Builder = "ChimneyBase", Radius = 13, Height = 10 },
	{ Id = "Chimney2Top", Zone = "Escape", Position = V(1484, -124, -40), Builder = "ChimneyTop", Radius = 13, Height = 10 },
	{ Id = "ExitMouth", Zone = "Escape", Position = V(1650, -6, -84), Builder = "ExitMouth", Radius = 11, Height = 10 },
	{ Id = "ExitValley", Zone = "Surface", Position = V(1740, 0, -84), Builder = "ExitValley" },
}

local Spine: { SpineEdge } = {
	{ From = "SurfaceCamp", To = "Mouth", Kind = "Surface" },
	{ From = "Mouth", To = "UpperHall", Kind = "Tunnel", Radius = NumberRange.new(7, 10), Zone = "UpperCave" },
	{ From = "UpperHall", To = "ShaftTop", Kind = "Tunnel", Radius = NumberRange.new(6, 8), Zone = "UpperCave" },
	{ From = "ShaftTop", To = "ShaftBottom", Kind = "Rope", Zone = "Shaft" },
	{ From = "ShaftBottom", To = "Cistern", Kind = "Tunnel", Radius = NumberRange.new(7, 10), Zone = "WetCave", Flooded = true },
	{ From = "Cistern", To = "Ring", Kind = "Tunnel", ToPort = "Entry", Radius = NumberRange.new(6, 9), Zone = "WetCave" },
	{ From = "Ring", To = "DeepHall", Kind = "Tunnel", FromPort = "Exit", Radius = NumberRange.new(6, 8), Zone = "DeepCave" },
	{ From = "DeepHall", To = "Camp", Kind = "Recursion", Zone = "DeepCave" },
	{ From = "Camp", To = "Threshold", Kind = "Tunnel", Radius = NumberRange.new(6, 8), Zone = "Ancient", Squeeze = true },
	{ From = "Camp", To = "Hollow", Kind = "Tunnel", Radius = NumberRange.new(8, 10), Zone = "DeepCave" },
	{ From = "Hollow", To = "Threshold", Kind = "Tunnel", Radius = NumberRange.new(8, 10), Zone = "DeepCave" },
	{ From = "Threshold", To = "Colonnade", Kind = "Tunnel", Radius = NumberRange.new(8, 11), Zone = "Ancient", Wander = 0.12 },
	{ From = "Colonnade", To = "FinalChamber", Kind = "Tunnel", Radius = NumberRange.new(10, 14), Zone = "FinalChamber", Wander = 0.1 },
	{ From = "FinalChamber", To = "ChimneyBase", Kind = "Tunnel", Radius = NumberRange.new(5.5, 7), Zone = "Escape", NoBranches = true },
	{ From = "ChimneyBase", To = "ChimneyTop", Kind = "Climb", Zone = "Escape" },
	{ From = "ChimneyTop", To = "Chimney2Base", Kind = "Tunnel", Radius = NumberRange.new(6, 8), Zone = "Escape", NoBranches = true },
	{ From = "Chimney2Base", To = "Chimney2Top", Kind = "Climb", Zone = "Escape" },
	{ From = "Chimney2Top", To = "ExitMouth", Kind = "Tunnel", Radius = NumberRange.new(6, 9), Zone = "Escape", NoBranches = true },
	{ From = "ExitMouth", To = "ExitValley", Kind = "Surface" },
}

return {
	Anchors = Anchors,
	Spine = Spine,
	-- Where players stand when they join or respawn.
	SpawnAnchor = "SurfaceCamp",
	EntranceAnchor = "Mouth",
	-- Reaching this anchor is required before an escape counts.
	RequiredBeforeEscape = "FinalChamber",
	EscapeAnchor = "ExitMouth",
	-- Monster lair / spawn location.
	LairAnchor = "Hollow",
	-- Y of the surface ground plane; depth is measured from here.
	SurfaceY = 0,
}
