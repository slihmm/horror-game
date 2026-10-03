--!strict
-- The world above: the expedition camp at dusk, the hill the cave runs under,
-- and the distant valley where the escape route surfaces.
--
-- Terrain() runs before the cave carve (the cave cuts through the hills);
-- Dress() runs afterwards and places the camp.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Primitives = require(script.Parent.CavePrimitives)
local Dress = require(script.Parent.DressContext)

type DressContext = Dress.DressContext

local UP = Vector3.yAxis

local SurfaceBuilder = {}

local function anchorPosition(plan: Primitives.Context, id: string): Vector3
	local anchor = plan.Anchors[id]
	return if anchor then anchor.Position else Vector3.zero
end

function SurfaceBuilder.Terrain(plan: Primitives.Context)
	local terrain = Workspace.Terrain
	local rng = Random.new(plan.Seed + 3)

	-- Camp meadow.
	local camp = anchorPosition(plan, "SurfaceCamp")
	terrain:FillBlock(CFrame.new(camp + Vector3.new(30, -10, 0)), Vector3.new(420, 20, 380), Enum.Material.Grass)
	for _ = 1, 14 do
		local p = camp + Vector3.new(rng:NextNumber(-170, 60), rng:NextNumber(-30, -22), rng:NextNumber(-170, 170))
		terrain:FillBall(p, rng:NextNumber(26, 40), Enum.Material.Grass)
	end
	-- The hill the cave runs under (east of camp).
	local mouth = anchorPosition(plan, "Mouth")
	terrain:FillBall(mouth + Vector3.new(94, -28, 30), 115, Enum.Material.Rock)
	terrain:FillBall(mouth + Vector3.new(44, -38, -60), 82, Enum.Material.Rock)
	terrain:FillBall(mouth + Vector3.new(54, -38, 100), 76, Enum.Material.Rock)
	-- Mountains ringing the meadow: a natural boundary.
	for i = 0, 15 do
		local angle = i / 16 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if dir.X < 0.55 then
			local p = camp + dir * rng:NextNumber(205, 230) + Vector3.new(0, rng:NextNumber(-40, -10), 0)
			terrain:FillBall(p, rng:NextNumber(70, 95), Enum.Material.Rock)
		end
	end

	-- Exit valley.
	local exitMouth = anchorPosition(plan, "ExitMouth")
	local valley = anchorPosition(plan, "ExitValley")
	terrain:FillBlock(CFrame.new(valley + Vector3.new(20, -10, 0)), Vector3.new(300, 20, 300), Enum.Material.Grass)
	terrain:FillBall(exitMouth + Vector3.new(-60, -26, 0), 105, Enum.Material.Rock)
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if dir.X > -0.5 then
			terrain:FillBall(valley + dir * rng:NextNumber(150, 170) + Vector3.new(0, -20, 0), rng:NextNumber(60, 80), Enum.Material.Rock)
		end
	end
end

local function tree(parent: Instance, at: Vector3, rng: Random, dead: boolean)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local height = rng:NextNumber(28, 48)
	local trunk = Instance.new("Part")
	trunk.Anchored = true
	trunk.Size = Vector3.new(height, 1.6, 1.6)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Color = Color3.fromRGB(52, 42, 34)
	trunk.Material = Enum.Material.Wood
	trunk.CFrame = CFrame.new(at + UP * (height / 2 - 1)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Parent = model
	if dead then
		for _ = 1, rng:NextInteger(4, 7) do
			local y = rng:NextNumber(height * 0.35, height * 0.95)
			local angle = rng:NextNumber(0, math.pi * 2)
			local length = rng:NextNumber(4, 9)
			local branch = Instance.new("Part")
			branch.Anchored = true
			branch.CanCollide = false
			branch.Size = Vector3.new(length, 0.4, 0.4)
			branch.Shape = Enum.PartType.Cylinder
			branch.Color = trunk.Color
			branch.Material = Enum.Material.Wood
			local origin = at + UP * y
			local tip = origin + Vector3.new(math.cos(angle) * length, rng:NextNumber(1, 3), math.sin(angle) * length)
			branch.CFrame = CFrame.lookAt((origin + tip) / 2, tip) * CFrame.Angles(0, math.rad(90), 0)
			branch.Parent = model
		end
	else
		local layers = rng:NextInteger(5, 7)
		for i = 1, layers do
			local t = i / layers
			local radius = (1 - t) * 9 + 2
			local cone = Instance.new("Part")
			cone.Anchored = true
			cone.CanCollide = false
			cone.Size = Vector3.new(3.5, radius * 2, radius * 2)
			cone.Shape = Enum.PartType.Cylinder
			cone.Color = Color3.fromRGB(30 + rng:NextInteger(0, 8), 44 + rng:NextInteger(0, 8), 32)
			cone.Material = Enum.Material.Grass
			cone.CFrame = CFrame.new(at + UP * (height * 0.3 + t * height * 0.7)) * CFrame.Angles(0, 0, math.rad(90))
			cone.Parent = model
		end
	end
	model.Parent = parent
end

local function boundary(parent: Instance, center: Vector3, radius: number, segments: number)
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Boundary"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CastShadow = false
		-- Above ground only: the cave runs underneath these boundaries.
		wall.Size = Vector3.new(2 * math.pi * radius / segments + 4, 306, 4)
		wall.CFrame = CFrame.new(center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius + UP * 147) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		wall.Parent = parent
	end
end

local function truck(at: CFrame, folder: Instance)
	local model = Instance.new("Model")
	model.Name = "Truck"
	local function box(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = at * offset
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Parent = model
		return p
	end
	local body = Color3.fromRGB(64, 70, 60)
	box(Vector3.new(7, 3.5, 15), CFrame.new(0, 3.2, 0), body)
	box(Vector3.new(6.6, 3, 6), CFrame.new(0, 6.2, -2), body)
	local glass = box(Vector3.new(6.4, 2.2, 0.2), CFrame.new(0, 6.4, -5.05), Color3.fromRGB(30, 36, 40), Enum.Material.Glass)
	glass.Reflectance = 0.3
	for _, x in { -3.4, 3.4 } do
		for _, z in { -4.5, 4.5 } do
			local wheel = box(Vector3.new(1.2, 3.2, 3.2), CFrame.new(x, 1.6, z), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
		end
	end
	-- Headlights left on: the warmest light the player will see for a while.
	for _, x in { -2.4, 2.4 } do
		local lamp = box(Vector3.new(1, 0.8, 0.2), CFrame.new(x, 3.6, -7.55), Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
		local light = Instance.new("SpotLight")
		light.Brightness = 1.4
		light.Range = 40
		light.Angle = 60
		light.Face = Enum.NormalId.Front
		light.Color = Color3.fromRGB(255, 232, 196)
		light.Shadows = true
		light.Parent = lamp
	end
	model.Parent = folder
end

function SurfaceBuilder.Dress(ctx: DressContext)
	local plan = ctx.Plan
	local rng = Random.new(plan.Seed + 11)
	local folder = Instance.new("Folder")
	folder.Name = "Surface"
	folder.Parent = ctx.Root

	local camp = anchorPosition(plan, "SurfaceCamp")
	local mouth = anchorPosition(plan, "Mouth")
	local toCave = Vector3.new(mouth.X - camp.X, 0, mouth.Z - camp.Z).Unit
	local side = toCave:Cross(UP)

	-- Trees around the meadow, kept off the path to the cave.
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(50, 190)
		local p = camp + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local alongPath = (p - camp):Dot(toCave)
		local offPath = math.abs((p - camp):Dot(side))
		if not (alongPath > 0 and offPath < 30) then
			local floor, normal, material = Dress.FloorAt(ctx, p + UP * 120, 0, 200)
			if floor and normal and normal.Y > 0.8 and material == Enum.Material.Grass then
				tree(folder, floor, rng, rng:NextNumber() < 0.35)
			end
		end
	end

	-- The camp.
	local campFolder = Instance.new("Folder")
	campFolder.Name = "Camp"
	campFolder.Parent = folder
	local base = Dress.Facing(Dress.FloorAt(ctx, camp + UP * 40, 0, 80) or camp, camp + toCave)
	local function at(x: number, z: number): Vector3
		local p = (base * CFrame.new(x, 0, z)).Position
		return Dress.FloorAt(ctx, p + UP * 20, 0, 40) or p
	end
	Dress.Place(ctx, "Tent", Dress.Facing(at(-12, 4), at(0, 0)), { Color = Color3.fromRGB(210, 120, 40), Collapsed = false }, campFolder)
	Dress.Place(ctx, "Tent", Dress.Facing(at(-6, 14), at(0, 0)), { Color = Color3.fromRGB(210, 120, 40), Collapsed = false }, campFolder)
	truck(Dress.Facing(at(14, 10), at(14, 30)), campFolder)
	for i = 1, 4 do
		Dress.Place(ctx, "Crate", CFrame.new(at(10 + i * 2.6, -4)), { Size = 2.2 }, campFolder)
	end
	Dress.Place(ctx, "RopeCoil", CFrame.new(at(4, -6)), nil, campFolder)
	Dress.Place(ctx, "RopeCoil", CFrame.new(at(5, -8)), nil, campFolder)
	Dress.Place(ctx, "Backpack", CFrame.new(at(-3, -5)), { Color = Color3.fromRGB(210, 120, 40) }, campFolder)
	-- Table with the permit and a lit lantern.
	local tablePos = at(-2, 0)
	local tableTop = Instance.new("Part")
	tableTop.Anchored = true
	tableTop.Size = Vector3.new(6, 0.3, 3)
	tableTop.Material = Enum.Material.Wood
	tableTop.Color = Color3.fromRGB(110, 86, 60)
	tableTop.CFrame = base.Rotation + (tablePos + UP * 2.6)
	tableTop.Parent = campFolder
	for _, dx in { -2.6, 2.6 } do
		for _, dz in { -1.2, 1.2 } do
			local leg = Instance.new("Part")
			leg.Anchored = true
			leg.Size = Vector3.new(0.25, 2.5, 0.25)
			leg.Material = Enum.Material.Metal
			leg.Color = Color3.fromRGB(80, 80, 80)
			leg.CFrame = tableTop.CFrame * CFrame.new(dx, -1.3, dz)
			leg.Parent = campFolder
		end
	end
	Dress.Place(ctx, "Lantern", tableTop.CFrame * CFrame.new(2, 0.15, 0), { Lit = true, Fallen = false, Range = 22, Brightness = 1 }, campFolder)
	Dress.AddLoreSlot(ctx, tablePos + UP * 2.76, "Surface", "SurfaceCamp", false)

	-- Expedition logbook board (LeaderboardService fills its SurfaceGui).
	local boardPos = at(-10, -8)
	local board = Instance.new("Part")
	board.Name = "LogbookBoard"
	board.Anchored = true
	board.Size = Vector3.new(7, 5, 0.4)
	board.Material = Enum.Material.WoodPlanks
	board.Color = Color3.fromRGB(80, 62, 44)
	board.CFrame = Dress.Facing(boardPos + UP * 4, at(0, 0) + UP * 4)
	board.Parent = campFolder
	board:AddTag(Constants.Tags.Leaderboard)
	for _, dx in { -3, 3 } do
		local post = Instance.new("Part")
		post.Anchored = true
		post.Size = Vector3.new(0.4, 6.5, 0.4)
		post.Material = Enum.Material.Wood
		post.Color = Color3.fromRGB(70, 54, 40)
		post.CFrame = board.CFrame * CFrame.new(dx, -1.5, 0.3)
		post.Parent = campFolder
	end

	-- Boundaries.
	boundary(folder, camp, 200, 24)
	local valley = anchorPosition(plan, "ExitValley")
	boundary(folder, valley, 140, 18)

	-- The valley: a few dead trees and silence.
	for _ = 1, 24 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(40, 130)
		local p = valley + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local floor, normal, material = Dress.FloorAt(ctx, p + UP * 120, 0, 200)
		if floor and normal and normal.Y > 0.8 and material == Enum.Material.Grass then
			tree(folder, floor, rng, rng:NextNumber() < 0.6)
		end
	end
end

-- Where players stand when they spawn at the surface.
function SurfaceBuilder.SpawnPoint(plan: Primitives.Context, index: number): CFrame
	local camp = anchorPosition(plan, "SurfaceCamp")
	local mouth = anchorPosition(plan, "Mouth")
	local angle = index * 2.399 -- golden angle spreads players out
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (4 + (index % 4) * 2)
	local p = camp + offset + UP * 4
	return CFrame.lookAt(p, Vector3.new(mouth.X, p.Y, mouth.Z))
end

return SurfaceBuilder
