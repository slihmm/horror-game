--!strict
-- Builds every environmental prop from parts. Each builder returns a Model
-- whose pivot is the point where it rests on the floor, facing -Z.
--
-- Art override: if ServerStorage.Assets.Props contains a Model with the same
-- name as a prop, that model is cloned instead. This lets artists replace
-- any procedural prop with a real mesh without touching code.

local ServerStorage = game:GetService("ServerStorage")

local PropFactory = {}

type Builder = (model: Model, rng: Random, params: { [string]: any }) -> ()

local Builders: { [string]: Builder } = {}

local BONE = Color3.fromRGB(196, 186, 160)
local BONE_DARK = Color3.fromRGB(150, 140, 116)
local FABRIC_COLORS = {
	Color3.fromRGB(122, 74, 40), -- rust
	Color3.fromRGB(70, 82, 60), -- olive
	Color3.fromRGB(46, 58, 82), -- navy
	Color3.fromRGB(150, 110, 40), -- mustard
	Color3.fromRGB(110, 36, 30), -- faded red
}
local METAL = Color3.fromRGB(92, 88, 82)
local BRASS = Color3.fromRGB(150, 118, 60)
local WOOD = Color3.fromRGB(92, 68, 46)

local function part(
	model: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function wedge(model: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = model
	return p
end

local function cylinderAlong(model: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local length = (b - a).Magnitude
	-- Cylinders extend along their local X axis.
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return part(model, Vector3.new(length, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function jitterColor(rng: Random, color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * rng:NextNumber(1 - amount, 1 + amount), 0, 1))
end

-- Text that is only readable under the headlamp (LightInfluence = 1).
local function wallText(model: Instance, cframe: CFrame, size: Vector2, text: string, font: Enum.Font, color: Color3, rotation: number?)
	local holder = part(model, Vector3.new(size.X, size.Y, 0.05), cframe, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	holder.Transparency = 1
	holder.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0.12
	label.Font = font
	label.TextScaled = true
	label.TextWrapped = true
	label.Rotation = rotation or 0
	label.Parent = gui
	return holder
end

-- Skeletons -----------------------------------------------------------------

local function bone(model: Model, a: Vector3, b: Vector3, thickness: number, rng: Random)
	cylinderAlong(model, a, b, thickness, jitterColor(rng, BONE, 0.08), Enum.Material.Limestone)
end

local function skull(model: Model, at: CFrame, rng: Random)
	part(model, Vector3.new(1.05, 1.15, 1.25), at, jitterColor(rng, BONE, 0.05), Enum.Material.Limestone, Enum.PartType.Ball)
	part(model, Vector3.new(0.75, 0.32, 0.6), at * CFrame.new(0, -0.5, -0.32), BONE_DARK, Enum.Material.Limestone)
	-- Eye sockets.
	for _, x in { -0.22, 0.22 } do
		part(model, Vector3.new(0.26, 0.24, 0.1), at * CFrame.new(x, 0.05, -0.6), Color3.fromRGB(20, 18, 16), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

local function ribcage(model: Model, at: CFrame, rng: Random)
	for i = 0, 4 do
		local y = -i * 0.32
		local width = 1.6 - i * 0.12
		for _, side in { -1, 1 } do
			local a = at * Vector3.new(0, y, 0.1)
			local b = at * Vector3.new(side * width / 2, y - 0.25, -0.35)
			bone(model, a, b, 0.14, rng)
		end
	end
	bone(model, at * Vector3.new(0, 0.2, 0.15), at * Vector3.new(0, -1.9, 0.15), 0.22, rng)
end

Builders.Skeleton = function(model, rng, params)
	local pose = params.Pose or (if rng:NextNumber() < 0.5 then "Lying" else "Sitting")
	if pose == "Sitting" then
		-- Slumped against a wall: back toward +Z.
		local torso = CFrame.new(0, 1.9, 0.4) * CFrame.Angles(math.rad(-18), 0, 0)
		ribcage(model, torso, rng)
		skull(model, torso * CFrame.new(0.15, 0.85, -0.25) * CFrame.Angles(math.rad(25), math.rad(rng:NextNumber(-30, 30)), math.rad(12)), rng)
		local pelvis = CFrame.new(0, 0.35, 0.1)
		part(model, Vector3.new(1.3, 0.5, 0.7), pelvis, BONE, Enum.Material.Limestone)
		for _, side in { -0.4, 0.4 } do
			local hip = pelvis * Vector3.new(side, 0, 0)
			local knee = Vector3.new(side * 1.4, 0.9, -1.6)
			local foot = Vector3.new(side * 1.5, 0.1, -3.2)
			bone(model, hip, knee, 0.24, rng)
			bone(model, knee, foot, 0.2, rng)
			local shoulder = torso * Vector3.new(side * 1.9, -0.05, 0.1)
			local elbow = shoulder + Vector3.new(side * 0.4, -1.2, -0.3)
			local hand = elbow + Vector3.new(side * 0.2, -0.6, -0.9)
			bone(model, shoulder, elbow, 0.18, rng)
			bone(model, elbow, hand, 0.15, rng)
		end
	else
		local torso = CFrame.new(0, 0.3, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(rng:NextNumber(-12, 12)))
		ribcage(model, torso, rng)
		skull(model, CFrame.new(rng:NextNumber(-0.4, 0.4), 0.55, 0.85) * CFrame.Angles(0, math.rad(rng:NextNumber(-60, 60)), math.rad(80)), rng)
		part(model, Vector3.new(1.3, 0.45, 0.7), CFrame.new(0, 0.25, -1.9), BONE, Enum.Material.Limestone)
		for _, side in { -0.45, 0.45 } do
			local spread = rng:NextNumber(0.1, 0.6)
			bone(model, Vector3.new(side, 0.2, -2.1), Vector3.new(side * (1 + spread), 0.2, -3.9), 0.24, rng)
			bone(model, Vector3.new(side * (1 + spread), 0.2, -3.9), Vector3.new(side * (1.2 + spread), 0.15, -5.6), 0.2, rng)
			local shoulder = Vector3.new(side * 2, 0.25, 0.35)
			local hand = shoulder + Vector3.new(side * rng:NextNumber(0.5, 1.6), -0.05, rng:NextNumber(-2.5, 1))
			bone(model, shoulder, hand, 0.17, rng)
		end
	end
	if params.Clothed ~= false and rng:NextNumber() < 0.7 then
		-- Rotten scraps of clothing.
		local color = FABRIC_COLORS[rng:NextInteger(1, #FABRIC_COLORS)]
		local scrap = part(model, Vector3.new(1.8, 0.08, 1.6), CFrame.new(0, if pose == "Sitting" then 1.1 else 0.42, if pose == "Sitting" then 0.3 else -0.4) * CFrame.Angles(math.rad(if pose == "Sitting" then -70 else 0), 0, 0), color, Enum.Material.Fabric)
		scrap.Transparency = 0.15
	end
end

Builders.BonePile = function(model, rng, _params)
	for _ = 1, rng:NextInteger(8, 16) do
		local a = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0.1, 0.6), rng:NextNumber(-2, 2))
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 0.2), rng:NextNumber(-1, 1)).Unit
		bone(model, a, a + dir * rng:NextNumber(0.8, 2.2), rng:NextNumber(0.12, 0.26), rng)
	end
	if rng:NextNumber() < 0.6 then
		skull(model, CFrame.new(rng:NextNumber(-1, 1), 0.5, rng:NextNumber(-1, 1)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), rng)
	end
end

-- Explorer equipment ------------------------------------------------------

Builders.Backpack = function(model, rng, params)
	local color = params.Color or FABRIC_COLORS[rng:NextInteger(1, #FABRIC_COLORS)]
	local tilt = CFrame.Angles(math.rad(rng:NextNumber(-12, 70)), math.rad(rng:NextNumber(0, 360)), 0)
	local base = CFrame.new(0, 1, 0) * tilt
	part(model, Vector3.new(1.6, 2, 0.9), base, color, Enum.Material.Fabric)
	part(model, Vector3.new(1.5, 0.5, 1), base * CFrame.new(0, 0.95, 0.05), jitterColor(rng, color, 0.2), Enum.Material.Fabric)
	part(model, Vector3.new(1.2, 0.8, 0.4), base * CFrame.new(0, -0.3, -0.6), jitterColor(rng, color, 0.15), Enum.Material.Fabric)
	for _, x in { -0.45, 0.45 } do
		part(model, Vector3.new(0.18, 1.8, 0.08), base * CFrame.new(x, 0, 0.5), Color3.fromRGB(30, 30, 30), Enum.Material.Fabric)
	end
	-- Rolled mat on top.
	if rng:NextNumber() < 0.5 then
		part(model, Vector3.new(1.9, 0.5, 0.5), base * CFrame.new(0, 1.35, 0), Color3.fromRGB(60, 70, 50), Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
end

Builders.Lantern = function(model, rng, params)
	local fallen = params.Fallen or rng:NextNumber() < 0.4
	local base = if fallen then CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)) else CFrame.new(0, 0.05, 0)
	part(model, Vector3.new(0.15, 0.9, 0.9), base * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	local glass = part(model, Vector3.new(0.9, 0.7, 0.7), base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 190, 160), Enum.Material.Glass, Enum.PartType.Cylinder)
	glass.Transparency = 0.55
	part(model, Vector3.new(0.3, 0.75, 0.75), base * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.08, 0.6, 0.08), base * CFrame.new(0, 1.45, 0), BRASS, Enum.Material.Metal)
	if params.Lit then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Range = params.Range or 16
		light.Brightness = params.Brightness or 0.8
		light.Shadows = true
		light.Parent = glass
		glass.Material = Enum.Material.Neon
		glass.Color = Color3.fromRGB(255, 170, 90)
		glass.Transparency = 0.2
		glass:AddTag("FlickerLight")
	end
end

Builders.Headlamp = function(model, rng, _params)
	local base = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	-- Elastic band lying flat (cylinder axis is local X, so roll it upright).
	part(model, Vector3.new(0.18, 1.2, 1.2), base * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(26, 26, 28), Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.4, 0.35, 0.3), base * CFrame.new(0, 0.1, -0.6), Color3.fromRGB(40, 40, 42), Enum.Material.SmoothPlastic)
	local lens = part(model, Vector3.new(0.05, 0.26, 0.26), base * CFrame.new(0, 0.1, -0.76) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 220, 210), Enum.Material.Glass, Enum.PartType.Cylinder)
	lens.Reflectance = 0.3
end

Builders.Flashlight = function(model, rng, _params)
	local base = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	part(model, Vector3.new(1.4, 0.35, 0.35), base, Color3.fromRGB(30, 30, 32), Enum.Material.Metal, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.35, 0.5, 0.5), base * CFrame.new(0.8, 0, 0), Color3.fromRGB(40, 40, 42), Enum.Material.Metal, Enum.PartType.Cylinder)
	local lens = part(model, Vector3.new(0.05, 0.42, 0.42), base * CFrame.new(0.98, 0, 0), Color3.fromRGB(230, 230, 220), Enum.Material.Glass, Enum.PartType.Cylinder)
	lens.Reflectance = 0.4
end

Builders.RopeCoil = function(model, rng, _params)
	local color = Color3.fromRGB(150, 130, 90)
	for i = 0, 3 do
		part(model, Vector3.new(0.3, 2.2 - i * 0.12, 2.2 - i * 0.12), CFrame.new(0, 0.15 + i * 0.28, 0) * CFrame.Angles(0, 0, math.rad(90)), jitterColor(rng, color, 0.1), Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	cylinderAlong(model, Vector3.new(1, 0.2, 0), Vector3.new(rng:NextNumber(2, 4), 0.12, rng:NextNumber(-2, 2)), 0.2, color, Enum.Material.Fabric)
end

Builders.Crate = function(model, rng, params)
	local s = params.Size or rng:NextNumber(1.8, 2.8)
	local base = CFrame.new(0, s / 2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	local c = part(model, Vector3.one * s, base, jitterColor(rng, WOOD, 0.15), Enum.Material.WoodPlanks)
	c.CanCollide = true
	c.CanQuery = true
	for _, y in { -s * 0.35, s * 0.35 } do
		part(model, Vector3.new(s + 0.05, 0.18, s + 0.05), base * CFrame.new(0, y, 0), METAL, Enum.Material.CorrodedMetal)
	end
end

Builders.Stove = function(model, rng, _params)
	local base = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	part(model, Vector3.new(0.9, 0.9, 1.1), base * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 70, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.2, 1.3, 1.3), base * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), METAL, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	-- Pot.
	part(model, Vector3.new(0.7, 1, 1), base * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 70, 72), Enum.Material.Metal, Enum.PartType.Cylinder)
end

Builders.SleepingBag = function(model, rng, params)
	local color = params.Color or FABRIC_COLORS[rng:NextInteger(1, #FABRIC_COLORS)]
	local base = CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0)
	part(model, Vector3.new(6, 0.7, 2.4), base * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Fabric)
	part(model, Vector3.new(2.2, 0.9, 1.2), base * CFrame.new(0, 0.1, -2.6), jitterColor(rng, color, 0.2), Enum.Material.Fabric)
	if params.Occupied then
		-- Something still inside.
		part(model, Vector3.new(4.4, 0.9, 1.4), base * CFrame.new(0, 0.35, 0.3) * CFrame.Angles(0, math.rad(90), 0), jitterColor(rng, color, 0.25), Enum.Material.Fabric)
	end
end

Builders.Tent = function(model, rng, params)
	local color = params.Color or FABRIC_COLORS[rng:NextInteger(1, #FABRIC_COLORS)]
	local collapsed = params.Collapsed or rng:NextNumber() < 0.5
	local height = if collapsed then 1.6 else 4.5
	local width, length = 6, 8
	local sag = if collapsed then math.rad(rng:NextNumber(-12, 12)) else 0
	-- Two wedges back to back form the A-frame; a wedge's high edge is at +Z.
	wedge(model, Vector3.new(length, height, width / 2), CFrame.new(0, height / 2, -width / 4) * CFrame.Angles(sag, 0, 0), jitterColor(rng, color, 0.1), Enum.Material.Fabric)
	wedge(model, Vector3.new(length, height, width / 2), CFrame.new(0, height / 2, width / 4) * CFrame.Angles(-sag, math.rad(180), 0), jitterColor(rng, color, 0.1), Enum.Material.Fabric)
	-- Poles.
	if not collapsed then
		for _, x in { -length / 2, length / 2 } do
			part(model, Vector3.new(0.15, height, 0.15), CFrame.new(x, height / 2, 0), METAL, Enum.Material.Metal)
		end
	else
		cylinderAlong(model, Vector3.new(-length / 2, 0.1, -1), Vector3.new(-length / 2 - 1, 1.4, 0.5), 0.15, METAL, Enum.Material.Metal)
	end
end

Builders.Camera = function(model, rng, params)
	local old = params.Old or rng:NextNumber() < 0.5
	local base = CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-8, 8)))
	part(model, Vector3.new(1.3, 0.8, 0.6), base, if old then Color3.fromRGB(30, 26, 22) else Color3.fromRGB(26, 26, 28), if old then Enum.Material.Leather else Enum.Material.SmoothPlastic)
	part(model, Vector3.new(0.5, 0.55, 0.55), base * CFrame.new(0, 0, -0.5) * CFrame.Angles(0, math.rad(90), 0), METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	local lens = part(model, Vector3.new(0.05, 0.42, 0.42), base * CFrame.new(0, 0, -0.76) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(40, 50, 60), Enum.Material.Glass, Enum.PartType.Cylinder)
	lens.Reflectance = 0.5
	if old then
		part(model, Vector3.new(0.5, 0.5, 0.15), base * CFrame.new(0.35, 0.5, 0), Color3.fromRGB(180, 180, 180), Enum.Material.Metal)
	end
end

Builders.Journal = function(model, rng, params)
	local color = params.Color or Color3.fromRGB(70 + rng:NextInteger(0, 40), 46, 30)
	local base = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	if params.Open then
		for _, side in { -1, 1 } do
			part(model, Vector3.new(0.95, 0.06, 1.3), base * CFrame.new(side * 0.5, 0, 0) * CFrame.Angles(0, 0, math.rad(side * -6)), Color3.fromRGB(214, 204, 178), Enum.Material.SmoothPlastic)
		end
		part(model, Vector3.new(2.05, 0.05, 1.38), base * CFrame.new(0, -0.05, 0), color, Enum.Material.Leather)
	else
		part(model, Vector3.new(1, 0.22, 1.35), base, color, Enum.Material.Leather)
		part(model, Vector3.new(0.92, 0.18, 1.3), base * CFrame.new(0.05, 0, 0), Color3.fromRGB(214, 204, 178), Enum.Material.SmoothPlastic)
	end
end

Builders.Note = function(model, rng, _params)
	local base = CFrame.new(0, 0.03, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	part(model, Vector3.new(0.85, 0.02, 1.1), base, Color3.fromRGB(220, 212, 190), Enum.Material.SmoothPlastic)
	part(model, Vector3.new(0.85, 0.02, 1.1), base * CFrame.new(0.15, 0.02, 0.1) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0), Color3.fromRGB(206, 198, 176), Enum.Material.SmoothPlastic)
end

Builders.Photograph = function(model, rng, _params)
	local base = CFrame.new(0, 0.03, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	part(model, Vector3.new(0.9, 0.02, 0.7), base, Color3.fromRGB(230, 226, 214), Enum.Material.SmoothPlastic)
	local image = part(model, Vector3.new(0.78, 0.025, 0.58), base * CFrame.new(0, 0.003, 0), Color3.fromRGB(70, 66, 60), Enum.Material.SmoothPlastic)
	image.Reflectance = 0.08
end

Builders.Recorder = function(model, rng, params)
	local base = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	if params.Phone then
		part(model, Vector3.new(0.6, 0.06, 1.2), CFrame.new(0, 0.04, 0) * base.Rotation, Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
		local screen = part(model, Vector3.new(0.54, 0.02, 1.1), CFrame.new(0, 0.08, 0) * base.Rotation, Color3.fromRGB(30, 34, 40), Enum.Material.Glass)
		screen.Reflectance = 0.25
		return
	end
	part(model, Vector3.new(1.4, 0.55, 0.8), base, Color3.fromRGB(34, 34, 36), Enum.Material.SmoothPlastic)
	part(model, Vector3.new(0.8, 0.05, 0.5), base * CFrame.new(-0.15, 0.29, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Glass)
	for i = 0, 3 do
		part(model, Vector3.new(0.16, 0.1, 0.16), base * CFrame.new(0.4 + (i % 2) * 0.2, 0.3, -0.15 + (i // 2) * 0.3), Color3.fromRGB(150, 150, 150), Enum.Material.SmoothPlastic)
	end
end

Builders.Pickaxe = function(model, rng, _params)
	local base = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	part(model, Vector3.new(3.2, 0.22, 0.22), base, WOOD, Enum.Material.Wood)
	part(model, Vector3.new(0.3, 0.3, 2.2), base * CFrame.new(1.5, 0, 0), METAL, Enum.Material.CorrodedMetal)
end

Builders.Helmet = function(model, rng, params)
	local base = CFrame.new(0, 0.35, 0) * CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(0, 360)), 0)
	local color = params.Color or (if rng:NextNumber() < 0.5 then Color3.fromRGB(170, 140, 50) else Color3.fromRGB(210, 210, 200))
	part(model, Vector3.new(1.3, 0.9, 1.5), base, color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	part(model, Vector3.new(1.5, 0.08, 1.7), base * CFrame.new(0, -0.3, 0), color, Enum.Material.SmoothPlastic)
	part(model, Vector3.new(0.35, 0.3, 0.2), base * CFrame.new(0, 0.1, -0.75), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
end

Builders.Boot = function(model, rng, _params)
	local base = CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-80, 0)))
	part(model, Vector3.new(0.7, 0.4, 1.4), base * CFrame.new(0, -0.2, -0.2), Color3.fromRGB(40, 30, 24), Enum.Material.Leather)
	part(model, Vector3.new(0.65, 0.9, 0.6), base * CFrame.new(0, 0.3, 0.25), Color3.fromRGB(46, 34, 26), Enum.Material.Leather)
end

Builders.Clothing = function(model, rng, _params)
	local color = FABRIC_COLORS[rng:NextInteger(1, #FABRIC_COLORS)]
	for _ = 1, 3 do
		local p = part(model, Vector3.new(rng:NextNumber(1, 2), 0.06, rng:NextNumber(0.8, 1.6)), CFrame.new(rng:NextNumber(-0.5, 0.5), 0.05, rng:NextNumber(-0.5, 0.5)) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.1, 0.1)), jitterColor(rng, color, 0.2), Enum.Material.Fabric)
		p.Transparency = 0.05
	end
end

Builders.Tripod = function(model, rng, _params)
	local top = Vector3.new(0, 4.2, 0)
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		cylinderAlong(model, top, Vector3.new(math.cos(angle) * 1.6, 0, math.sin(angle) * 1.6), 0.16, METAL, Enum.Material.Metal)
	end
	part(model, Vector3.new(0.8, 0.5, 0.5), CFrame.new(top + Vector3.new(0, 0.3, 0)), Color3.fromRGB(150, 120, 40), Enum.Material.Metal)
end

Builders.Stake = function(model, rng, _params)
	part(model, Vector3.new(0.25, 2.4, 0.25), CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8))), WOOD, Enum.Material.Wood)
	local tag = part(model, Vector3.new(0.6, 0.35, 0.05), CFrame.new(0, 2.1, -0.15), Color3.fromRGB(190, 60, 40), Enum.Material.Fabric)
	tag.Transparency = 0.1
end

-- Formations / rocks --------------------------------------------------------

local ROCK_MATERIALS = { Enum.Material.Slate, Enum.Material.Rock, Enum.Material.Basalt }

Builders.Boulder = function(model, rng, params)
	local size = params.Size or rng:NextNumber(2.5, 6)
	local color = params.Color or Color3.fromRGB(70, 66, 62)
	local material = params.Material or ROCK_MATERIALS[rng:NextInteger(1, #ROCK_MATERIALS)]
	for i = 1, rng:NextInteger(2, 4) do
		local s = size * rng:NextNumber(0.6, 1)
		local p = part(
			model,
			Vector3.new(s * rng:NextNumber(0.8, 1.3), s * rng:NextNumber(0.6, 0.9), s * rng:NextNumber(0.8, 1.2)),
			CFrame.new(rng:NextNumber(-0.4, 0.4) * size, s * 0.3, rng:NextNumber(-0.4, 0.4) * size) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			jitterColor(rng, color, 0.12),
			material,
			if i == 1 then Enum.PartType.Block else Enum.PartType.Ball
		)
		p.CanCollide = params.Collide ~= false
		p.CanQuery = params.Collide ~= false
	end
end

Builders.Rubble = function(model, rng, params)
	local spread = params.Spread or 6
	local color = params.Color or Color3.fromRGB(74, 68, 62)
	for _ = 1, params.Count or rng:NextInteger(10, 18) do
		local s = rng:NextNumber(0.6, 2.6)
		local p = part(
			model,
			Vector3.new(s, s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.7, 1.2)),
			CFrame.new(rng:NextNumber(-spread, spread), s * 0.3 + rng:NextNumber(0, params.Height or 1), rng:NextNumber(-spread * 0.5, spread * 0.5)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			jitterColor(rng, color, 0.15),
			ROCK_MATERIALS[rng:NextInteger(1, #ROCK_MATERIALS)]
		)
		p.CanCollide = s > 1.4
		p.CanQuery = s > 1.4
	end
end

local function cone(model: Model, base: Vector3, direction: number, length: number, radius: number, color: Color3, material: Enum.Material)
	local segments = 4
	for i = 0, segments - 1 do
		local t = i / segments
		local segLength = length / segments
		local r = radius * (1 - t * 0.85)
		local y = base.Y + direction * (t * length + segLength / 2)
		part(model, Vector3.new(segLength * 1.05, r * 2, r * 2), CFrame.new(base.X, y, base.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
	end
end

Builders.Stalagmite = function(model, rng, params)
	local length = params.Length or rng:NextNumber(2, 7)
	cone(model, Vector3.zero, 1, length, rng:NextNumber(0.6, 1.4) * math.sqrt(length / 3), jitterColor(rng, params.Color or Color3.fromRGB(94, 86, 76), 0.1), params.Material or Enum.Material.Limestone)
end

Builders.Stalactite = function(model, rng, params)
	-- Pivot is the ceiling attachment point; grows downward.
	local length = params.Length or rng:NextNumber(2, 8)
	cone(model, Vector3.zero, -1, length, rng:NextNumber(0.4, 1.1) * math.sqrt(length / 3), jitterColor(rng, params.Color or Color3.fromRGB(100, 92, 80), 0.1), params.Material or Enum.Material.Limestone)
end

-- Marks on the world ---------------------------------------------------------
-- These props are placed with their pivot on a wall facing out (-Z is the
-- wall normal direction the viewer stands on).

Builders.Scratches = function(model, rng, params)
	local count = params.Count or rng:NextInteger(3, 5)
	local length = params.Length or rng:NextNumber(3, 6)
	local angle = math.rad(rng:NextNumber(-35, 35))
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * 0.45
		local p = part(model, Vector3.new(0.14, length * rng:NextNumber(0.85, 1.1), 0.08), CFrame.Angles(0, 0, angle) * CFrame.new(offset, 0, -0.02), Color3.fromRGB(26, 22, 20), Enum.Material.Slate)
		p.CastShadow = false
	end
end

Builders.WallText = function(model, _rng, params)
	wallText(
		model,
		CFrame.new(0, 0, -0.05) * CFrame.Angles(0, math.rad(180), 0),
		params.Size or Vector2.new(5, 2),
		params.Text or "",
		params.Font or Enum.Font.IndieFlower,
		params.Color or Color3.fromRGB(210, 205, 190),
		params.Rotation
	)
end

Builders.Footprints = function(model, rng, params)
	-- A trail along -Z. Huge, widely spaced prints when params.Monster.
	local monster = params.Monster == true
	local count = params.Count or (if monster then 6 else 10)
	local stride = if monster then 9 else 2.2
	local size = if monster then Vector3.new(2.6, 0.06, 5.4) else Vector3.new(0.75, 0.05, 1.6)
	local color = params.Color or Color3.fromRGB(36, 28, 22)
	for i = 0, count - 1 do
		local side = if i % 2 == 0 then -1 else 1
		local x = side * (if monster then 1.6 else 0.45) + rng:NextNumber(-0.2, 0.2)
		local at = CFrame.new(x, 0.03, -i * stride) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0)
		part(model, size, at, color, Enum.Material.Mud).CastShadow = false
		-- Heel.
		part(model, Vector3.new(size.X * 0.8, size.Y, size.Z * 0.3), at * CFrame.new(0, 0, size.Z * 0.62), color, Enum.Material.Mud).CastShadow = false
		if monster then
			-- Drag marks of the long toes.
			part(model, Vector3.new(0.2, 0.04, 2.5), at * CFrame.new(-0.7, 0, -size.Z * 0.5 - 1.2), color, Enum.Material.Mud).CastShadow = false
			part(model, Vector3.new(0.2, 0.04, 2.8), at * CFrame.new(0.7, 0, -size.Z * 0.5 - 1.4), color, Enum.Material.Mud).CastShadow = false
		end
	end
end

Builders.BloodTrail = function(model, rng, params)
	local length = params.Length or 14
	local z = 0
	while z < length do
		local s = rng:NextNumber(0.3, 1.1)
		local p = part(model, Vector3.new(s, 0.03, s * rng:NextNumber(1, 2.4)), CFrame.new(rng:NextNumber(-0.4, 0.4), 0.03, -z) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), Color3.fromRGB(52, 12, 10), Enum.Material.SmoothPlastic)
		p.Reflectance = 0.15
		p.CastShadow = false
		z += rng:NextNumber(0.6, 2)
	end
end

-- Ancient structures ---------------------------------------------------------

local STONE = Color3.fromRGB(116, 108, 94)

Builders.StonePillar = function(model, rng, params)
	local height = params.Height or 18
	local radius = params.Radius or 2
	local broken = params.Broken or false
	local h = if broken then height * rng:NextNumber(0.3, 0.6) else height
	local p = part(model, Vector3.new(h, radius * 2, radius * 2), CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), jitterColor(rng, STONE, 0.08), Enum.Material.Limestone, Enum.PartType.Cylinder)
	p.CanCollide = true
	p.CanQuery = true
	local plinth = part(model, Vector3.new(radius * 2.8, 1.2, radius * 2.8), CFrame.new(0, 0.6, 0), jitterColor(rng, STONE, 0.1), Enum.Material.Limestone)
	plinth.CanCollide = true
	if not broken then
		part(model, Vector3.new(radius * 2.9, 1.4, radius * 2.9), CFrame.new(0, h - 0.7, 0), jitterColor(rng, STONE, 0.1), Enum.Material.Limestone)
	else
		for _ = 1, 3 do
			local chunk = part(model, Vector3.new(radius * 1.6, radius * 1.2, radius * 1.4), CFrame.new(rng:NextNumber(-5, 5), radius * 0.6, rng:NextNumber(-5, 5)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)), jitterColor(rng, STONE, 0.1), Enum.Material.Limestone)
			chunk.CanCollide = true
		end
	end
	-- Carved rings.
	for i = 1, math.floor(h / 4) do
		part(model, Vector3.new(0.3, radius * 2.08, radius * 2.08), CFrame.new(0, i * 4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 74, 64), Enum.Material.Limestone, Enum.PartType.Cylinder)
	end
end

Builders.Arch = function(model, rng, params)
	local width = params.Width or 14
	local height = params.Height or 16
	local thickness = 3
	for _, side in { -1, 1 } do
		local leg = part(model, Vector3.new(thickness, height, thickness), CFrame.new(side * (width / 2 + thickness / 2), height / 2, 0), jitterColor(rng, STONE, 0.06), Enum.Material.Limestone)
		leg.CanCollide = true
		leg.CanQuery = true
	end
	local lintel = part(model, Vector3.new(width + thickness * 2 + 1, thickness, thickness + 0.6), CFrame.new(0, height + thickness / 2, 0), jitterColor(rng, STONE, 0.06), Enum.Material.Limestone)
	lintel.CanCollide = true
	-- Relief band on the lintel.
	for i = -3, 3 do
		part(model, Vector3.new(0.8, 1.6, 0.3), CFrame.new(i * 2, height + thickness / 2, -thickness / 2 - 0.15), Color3.fromRGB(84, 78, 66), Enum.Material.Limestone)
	end
end

Builders.Monolith = function(model, rng, params)
	local height = params.Height or 12
	local slab = part(model, Vector3.new(4, height, 1.6), CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-3, 3))), Color3.fromRGB(26, 26, 28), Enum.Material.Basalt)
	slab.CanCollide = true
	slab.CanQuery = true
	slab.Reflectance = 0.05
	-- The open eye, carved.
	part(model, Vector3.new(0.1, 2.6, 2.6), CFrame.new(0, height * 0.65, -0.82) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 58, 56), Enum.Material.Basalt, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.12, 0.9, 0.9), CFrame.new(0, height * 0.65, -0.84) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(10, 10, 10), Enum.Material.Basalt, Enum.PartType.Cylinder)
end

Builders.Altar = function(model, rng, _params)
	local top = part(model, Vector3.new(8, 1.2, 4), CFrame.new(0, 3.4, 0), jitterColor(rng, STONE, 0.05), Enum.Material.Limestone)
	top.CanCollide = true
	top.CanQuery = true
	for _, x in { -2.8, 2.8 } do
		local leg = part(model, Vector3.new(1.6, 2.8, 3.2), CFrame.new(x, 1.4, 0), jitterColor(rng, STONE, 0.05), Enum.Material.Limestone)
		leg.CanCollide = true
	end
end

Builders.Steps = function(model, rng, params)
	local count = params.Count or 6
	local width = params.Width or 10
	for i = 0, count - 1 do
		local step = part(model, Vector3.new(width, 0.9, 2), CFrame.new(0, 0.45 + i * 0.9, -i * 2), jitterColor(rng, STONE, 0.06), Enum.Material.Limestone)
		step.CanCollide = true
		step.CanQuery = true
	end
end

-- Hazards / structures --------------------------------------------------------

Builders.Grate = function(model, _rng, params)
	local size = params.Size or 8
	for i = -3, 3 do
		local bar = part(model, Vector3.new(0.25, 0.25, size), CFrame.new(i * size / 7, 0, 0), METAL, Enum.Material.CorrodedMetal)
		bar.CanCollide = true
		bar.CanQuery = true
		local cross = part(model, Vector3.new(size, 0.25, 0.25), CFrame.new(0, 0.05, i * size / 7), METAL, Enum.Material.CorrodedMetal)
		cross.CanCollide = true
	end
end

Builders.LampPile = function(model, rng, params)
	-- The Lamplighter's nest of torn-off lights.
	local count = params.Count or 26
	local builders = { "Headlamp", "Lantern", "Flashlight", "Helmet" }
	for _ = 1, count do
		local name = builders[rng:NextInteger(1, #builders)]
		local sub = Instance.new("Model")
		sub.Name = name
		Builders[name](sub, rng, { Fallen = true })
		sub:PivotTo(CFrame.new(rng:NextNumber(-3.5, 3.5), rng:NextNumber(0, 1.6), rng:NextNumber(-3, 3)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)))
		sub.Parent = model
	end
end

Builders.Bridge = function(model, rng, params)
	-- Built along -Z from the origin for params.Length studs.
	local length = params.Length or 16
	local width = params.Width or 4
	local planks: { BasePart } = {}
	local z = 0
	while z < length do
		local plank = part(model, Vector3.new(width, 0.35, 1.1), CFrame.new(0, 0, -z - 0.6) * CFrame.Angles(0, rng:NextNumber(-0.04, 0.04), 0), jitterColor(rng, WOOD, 0.2), Enum.Material.WoodPlanks)
		plank.CanCollide = true
		plank.CanQuery = true
		plank.Name = "Plank"
		table.insert(planks, plank)
		z += 1.25
	end
	for _, x in { -width / 2, width / 2 } do
		local beam = part(model, Vector3.new(0.4, 0.4, length), CFrame.new(x, -0.35, -length / 2), jitterColor(rng, WOOD, 0.1), Enum.Material.Wood)
		beam.Name = "Beam"
		local rope = cylinderAlong(model, Vector3.new(x, 2.6, 0), Vector3.new(x, 2.4, -length), 0.12, Color3.fromRGB(140, 120, 80), Enum.Material.Fabric)
		rope.Name = "Handline"
	end
end

-- Loot item visuals ----------------------------------------------------------

Builders.Loot = function(model, rng, params)
	local shape = params.Shape or "Coin"
	local color = params.Color or Color3.fromRGB(180, 160, 110)
	local main: Part
	if shape == "Battery" then
		main = part(model, Vector3.new(0.9, 0.45, 0.45), CFrame.new(0, 0.23, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part(model, Vector3.new(0.3, 0.47, 0.47), main.CFrame * CFrame.new(0.2, 0, 0), Color3.fromRGB(190, 150, 40), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif shape == "Coin" then
		main = part(model, Vector3.new(0.08, 0.5, 0.5), CFrame.new(0, 0.05, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(90)), color, Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif shape == "Ring" then
		main = part(model, Vector3.new(0.1, 0.42, 0.42), CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif shape == "Tag" then
		main = part(model, Vector3.new(0.5, 0.04, 0.8), CFrame.new(0, 0.03, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(160, 160, 164), Enum.Material.Metal)
	elseif shape == "Crystal" then
		main = part(model, Vector3.new(0.5, 1.1, 0.5), CFrame.new(0, 0.5, 0) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), color, Enum.Material.Glass)
		main.Transparency = 0.2
		local glow = Instance.new("PointLight")
		glow.Range = 4
		glow.Brightness = 0.25
		glow.Color = color
		glow.Parent = main
	elseif shape == "Idol" then
		main = part(model, Vector3.new(0.5, 0.9, 0.4), CFrame.new(0, 0.45, 0), Color3.fromRGB(50, 48, 46), Enum.Material.Basalt)
		part(model, Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 1.05, 0), Color3.fromRGB(50, 48, 46), Enum.Material.Basalt, Enum.PartType.Ball)
		for i = -2, 2 do
			part(model, Vector3.new(0.1, 0.1, 0.1), CFrame.new(i * 0.09, 1.3, -0.1), Color3.fromRGB(200, 190, 150), Enum.Material.Metal, Enum.PartType.Ball)
		end
	elseif shape == "Lens" then
		main = part(model, Vector3.new(0.12, 0.6, 0.6), CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Glass, Enum.PartType.Cylinder)
		main.Transparency = 0.25
		main.Reflectance = 0.4
	elseif shape == "Stone" then
		main = part(model, Vector3.new(0.8, 0.4, 0.7), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(150, 140, 120), Enum.Material.Limestone, Enum.PartType.Ball)
	else
		main = part(model, Vector3.new(0.8, 0.45, 0.6), CFrame.new(0, 0.23, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(40, 40, 42), Enum.Material.SmoothPlastic)
	end
	main.Name = "Main"
	main.Reflectance = math.max(main.Reflectance, 0.12)
end

-- Rooms that feel wrong / rooms that are beautiful ----------------------------

Builders.Tablet = function(model, rng, _params)
	-- A carved stone slab leaning against nothing, for carvings away from walls.
	local slab = part(model, Vector3.new(3.2, 4.4, 0.7), CFrame.new(0, 2.1, 0) * CFrame.Angles(math.rad(rng:NextNumber(-8, -2)), 0, math.rad(rng:NextNumber(-4, 4))), jitterColor(rng, STONE, 0.08), Enum.Material.Limestone)
	slab.CanCollide = true
	slab.CanQuery = true
end

Builders.Chair = function(model, rng, _params)
	local color = jitterColor(rng, WOOD, 0.1)
	part(model, Vector3.new(1.8, 0.2, 1.8), CFrame.new(0, 1.7, 0), color, Enum.Material.Wood)
	part(model, Vector3.new(1.8, 2, 0.2), CFrame.new(0, 2.8, 0.8), color, Enum.Material.Wood)
	for _, x in { -0.8, 0.8 } do
		for _, z in { -0.8, 0.8 } do
			part(model, Vector3.new(0.18, 1.7, 0.18), CFrame.new(x, 0.85, z), color, Enum.Material.Wood)
		end
	end
end

Builders.DoorFrame = function(model, rng, _params)
	local color = jitterColor(rng, Color3.fromRGB(200, 196, 186), 0.05)
	for _, x in { -2, 2 } do
		part(model, Vector3.new(0.4, 7.4, 0.5), CFrame.new(x, 3.7, 0), color, Enum.Material.Wood)
	end
	part(model, Vector3.new(4.4, 0.4, 0.5), CFrame.new(0, 7.4, 0), color, Enum.Material.Wood)
	-- The door, slightly open, hinged on nothing.
	local door = part(model, Vector3.new(3.6, 7, 0.2), CFrame.new(-1.8, 3.6, 0) * CFrame.Angles(0, math.rad(-28), 0) * CFrame.new(1.8, 0, 0), color, Enum.Material.Wood)
	door.CanCollide = true
	part(model, Vector3.new(0.15, 0.15, 0.3), door.CFrame * CFrame.new(1.4, 0, -0.2), BRASS, Enum.Material.Metal)
end

Builders.Candle = function(model, _rng, _params)
	part(model, Vector3.new(0.3, 0.9, 0.3), CFrame.new(0, 0.45, 0), Color3.fromRGB(226, 220, 200), Enum.Material.SmoothPlastic)
	local flame = part(model, Vector3.new(0.12, 0.25, 0.12), CFrame.new(0, 1.03, 0), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 9
	light.Brightness = 0.7
	light.Shadows = true
	light.Parent = flame
	flame:AddTag("FlickerLight")
end

Builders.Telephone = function(model, rng, _params)
	local base = CFrame.new(0, 0, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	part(model, Vector3.new(1.4, 0.6, 1.2), base * CFrame.new(0, 0.3, 0), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	part(model, Vector3.new(1.6, 0.35, 0.4), base * CFrame.new(0, 0.75, 0), Color3.fromRGB(24, 24, 24), Enum.Material.SmoothPlastic)
	part(model, Vector3.new(0.06, 0.5, 0.5), base * CFrame.new(0, 0.62, -0.62) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(200, 200, 190), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	-- The cord runs into the rock.
	cylinderAlong(model, base * Vector3.new(0.7, 0.2, 0), base * Vector3.new(4, 0.05, 1.5), 0.08, Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
end

Builders.GlowWorms = function(model, rng, params)
	-- Placed at a ceiling point: a field of faint blue-green specks.
	local spread = params.Spread or 10
	for _ = 1, params.Count or 40 do
		local speck = part(model, Vector3.new(0.12, 0.12, 0.12), CFrame.new(rng:NextNumber(-spread, spread), rng:NextNumber(-1.5, 0), rng:NextNumber(-spread, spread)), Color3.fromRGB(110, 230, 210), Enum.Material.Neon, Enum.PartType.Ball)
		speck.CastShadow = false
		speck.Transparency = rng:NextNumber(0, 0.5)
		if rng:NextNumber() < 0.5 then
			-- Silk threads hanging below.
			local thread = part(model, Vector3.new(0.03, rng:NextNumber(0.6, 2), 0.03), speck.CFrame * CFrame.new(0, -0.6, 0), Color3.fromRGB(180, 220, 220), Enum.Material.Glass)
			thread.Transparency = 0.6
			thread.CastShadow = false
		end
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 210, 200)
	light.Range = spread * 1.6
	light.Brightness = 0.12
	light.Shadows = false
	light.Parent = model:FindFirstChildWhichIsA("BasePart")
end

Builders.Crystals = function(model, rng, params)
	local color = params.Color or Color3.fromRGB(170, 200, 230)
	for _ = 1, params.Count or 9 do
		local h = rng:NextNumber(0.8, 3.2)
		local c = part(model, Vector3.new(h * 0.3, h, h * 0.3), CFrame.new(rng:NextNumber(-1.5, 1.5), h * 0.4, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6), rng:NextNumber(-0.5, 0.5)), color, Enum.Material.Glass)
		c.Transparency = 0.3
		c.Reflectance = 0.2
	end
	local first = model:FindFirstChildWhichIsA("BasePart")
	if first and params.Glow ~= false then
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = 10
		glow.Brightness = 0.18
		glow.Parent = first
	end
end

Builders.HangingRoots = function(model, rng, params)
	for _ = 1, params.Count or 8 do
		local x, z = rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)
		local length = rng:NextNumber(1.5, 5)
		cylinderAlong(model, Vector3.new(x, 0, z), Vector3.new(x + rng:NextNumber(-0.6, 0.6), -length, z + rng:NextNumber(-0.6, 0.6)), rng:NextNumber(0.08, 0.2), Color3.fromRGB(70, 52, 38), Enum.Material.Wood)
	end
end

Builders.HangingRope = function(model, rng, params)
	-- Pivot at the top anchor; hangs down params.Length studs.
	local length = params.Length or 40
	local color = params.Color or Color3.fromRGB(170, 150, 100)
	local material = if params.Old then Enum.Material.Fabric else Enum.Material.Fabric
	local sway = params.Sway or 0.6
	local segments = math.max(2, math.ceil(length / 25))
	local prev = Vector3.zero
	for i = 1, segments do
		local nextPoint = Vector3.new(rng:NextNumber(-sway, sway), -length * i / segments, rng:NextNumber(-sway, sway))
		local seg = cylinderAlong(model, prev, nextPoint, params.Thickness or 0.22, jitterColor(rng, color, 0.08), material)
		seg.Name = "Rope"
		prev = nextPoint
	end
	part(model, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 0.2, 0), METAL, Enum.Material.CorrodedMetal)
end

-- Public API -------------------------------------------------------------------

local function override(name: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local custom = props and props:FindFirstChild(name)
	if custom and custom:IsA("Model") then
		return custom:Clone()
	end
	return nil
end

function PropFactory.Has(name: string): boolean
	return Builders[name] ~= nil
end

-- Builds the named prop and pivots it to `cframe`.
function PropFactory.Build(name: string, cframe: CFrame, rng: Random, params: { [string]: any }?, parent: Instance?): Model
	local model = override(name)
	if not model then
		local builder = Builders[name]
		assert(builder, `Unknown prop '{name}'`)
		local built = Instance.new("Model")
		built.Name = name
		builder(built, rng, params or {})
		built.WorldPivot = CFrame.identity
		model = built
	end
	local m = model :: Model
	m:PivotTo(cframe)
	if parent then
		m.Parent = parent
	end
	return m
end

-- Utility for dressers that need loose parts (e.g. falling rocks).
PropFactory.Part = part
PropFactory.CylinderAlong = cylinderAlong

return PropFactory
