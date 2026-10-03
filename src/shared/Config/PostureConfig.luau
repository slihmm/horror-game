--!strict
-- Procedural body poses layered over Roblox's default animations so other
-- players can read what you are doing in the dark: crouching, hanging on a
-- rope, climbing, squeezing. Angles are degrees about each R15 joint's X axis
-- (positive swings a limb forward); offsets are studs. Tune in Studio.

export type Pose = {
	RootDrop: number,
	Waist: number,
	Hip: number,
	Knee: number,
	Ankle: number,
	Shoulder: number,
	Elbow: number,
}

local Poses: { [string]: Pose } = {
	Stand = { RootDrop = 0, Waist = 0, Hip = 0, Knee = 0, Ankle = 0, Shoulder = 0, Elbow = 0 },
	Crouch = { RootDrop = 1.45, Waist = -22, Hip = 70, Knee = -120, Ankle = 50, Shoulder = 15, Elbow = 25 },
	Rope = { RootDrop = 0, Waist = -8, Hip = 20, Knee = -35, Ankle = 10, Shoulder = 160, Elbow = 30 },
	Climb = { RootDrop = 0, Waist = -12, Hip = 45, Knee = -70, Ankle = 20, Shoulder = 145, Elbow = 45 },
	Squeeze = { RootDrop = 1.7, Waist = -45, Hip = 80, Knee = -125, Ankle = 45, Shoulder = 60, Elbow = 70 },
}

return {
	Poses = Poses,
	-- How fast poses blend (1/seconds).
	BlendSpeed = 7,
	-- Only pose characters within this distance of the camera.
	MaxDistance = 160,
}
