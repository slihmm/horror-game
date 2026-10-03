--!strict
-- Dressing for the handcrafted story locations. These are deliberately
-- authored: the same beats in the same places every run, with small
-- variations in arrangement.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Dress = require(script.Parent.DressContext)
local Primitives = require(script.Parent.CavePrimitives)

type DressContext = Dress.DressContext
type Anchor = Primitives.Anchor

local UP = Vector3.yAxis

local RoomDressers: { [string]: (DressContext, Anchor) -> () } = {}

local function floorNear(ctx: DressContext, anchor: Anchor, offset: Vector3): Vector3?
	return Dress.FloorAt(ctx, anchor.Position + offset + UP * 4, 6, 20)
end

local function ringPoint(anchor: Anchor, fraction: number, angle: number): Vector3
	return anchor.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * anchor.Radius * fraction
end

local function lightBeam(parent: Instance, from: Vector3, to: Vector3, width: number)
	local holder = Instance.new("Part")
	holder.Name = "LightShaft"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(from)
	holder.Parent = parent
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 1.8
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(220, 226, 230))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(0.7, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Segments = 1
	beam.Parent = holder
	-- Dust drifting through the light.
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 3
	dust.Lifetime = NumberRange.new(6, 10)
	dust.Speed = NumberRange.new(0.2, 0.6)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new(0.06)
	dust.Transparency = NumberSequence.new(0.4)
	dust.LightInfluence = 0.2
	dust.LightEmission = 0.4
	dust.Color = ColorSequence.new(Color3.fromRGB(230, 230, 220))
	local emitterPart = Instance.new("Part")
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(width, (from - to).Magnitude * 0.7, width)
	emitterPart.CFrame = CFrame.new(from:Lerp(to, 0.55))
	emitterPart.Parent = holder
	dust.Parent = emitterPart
end

RoomDressers.CaveMouth = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "CaveMouth")
	local outside = anchor.Ports.Outside
	if outside then
		local dir = anchor.Data.OutsideDirection :: Vector3
		local side = dir:Cross(UP)
		local floor = Dress.FloorAt(ctx, outside - dir * 10 + UP * 6, 8, 20)
		if floor then
			-- Old warning stakes with flagging tape at the threshold.
			for _, s in { -1, 1 } do
				Dress.Place(ctx, "Stake", CFrame.new(floor + side * s * 6), nil, folder)
			end
			local hit, normal = Dress.WallFrom(ctx, floor + UP * 4 - dir * 4, side, 20)
			if hit and normal then
				Dress.Place(ctx, "WallText", Dress.OnWall(hit, normal), {
					Text = "DANGER\nUNSTABLE\nDO NOT ENTER",
					Font = Enum.Font.SpecialElite,
					Color = Color3.fromRGB(200, 70, 50),
					Size = Vector2.new(4, 3),
				}, folder)
			end
		end
	end
	for _ = 1, 3 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.8)
		if p then
			Dress.Place(ctx, "HangingRoots", CFrame.new((Dress.CeilingAt(ctx, p + UP, 30) or p + UP * 10)), nil, folder)
		end
	end
end

RoomDressers.UpperHall = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "UpperHall")
	for _, shaft in anchor.Data.LightShafts or {} do
		local floor = Dress.FloorAt(ctx, shaft.Floor + UP * 4, 6, 20) or shaft.Floor
		local ceiling = Dress.CeilingAt(ctx, floor + UP * 1, 60) or (floor + UP * 30)
		lightBeam(folder, ceiling + UP * 2, floor, 4)
		-- Moss and leaf litter where the daylight lands.
		local patch = Instance.new("Part")
		patch.Anchored = true
		patch.CanCollide = false
		patch.CanQuery = false
		patch.Size = Vector3.new(0.1, 7, 7)
		patch.Shape = Enum.PartType.Cylinder
		patch.Color = Color3.fromRGB(60, 78, 40)
		patch.Material = Enum.Material.Grass
		patch.CFrame = CFrame.new(floor + UP * 0.03) * CFrame.Angles(0, 0, math.rad(90))
		patch.Parent = folder
		-- A grate over the hole on the surface (found by probing beside it).
		local surface = Dress.FloorAt(ctx, Vector3.new(floor.X + 6, 200, floor.Z), 0, 260)
		if surface and surface.Y > -10 then
			Dress.Place(ctx, "Grate", CFrame.new(floor.X, surface.Y + 0.3, floor.Z), { Size = 9 }, folder)
		end
	end
	-- The initials carved by every expedition.
	local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6, anchor.Radius * 0.3)
	if p then
		Dress.AddLoreSlot(ctx, p, anchor.Zone, anchor.Id, false)
	end
	for _ = 1, 4 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.9)
		if q then
			Dress.Place(ctx, "Stalagmite", CFrame.new(q - UP * 0.3), { Length = ctx.Rng:NextNumber(3, 8) }, folder)
		end
	end
end

RoomDressers.ShaftTop = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ShaftTop")
	local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.5)
	if p then
		Dress.Place(ctx, "Backpack", CFrame.new(p), { Color = Color3.fromRGB(60, 110, 170) }, folder)
		Dress.PlaceOnFloor(ctx, "Helmet", p + Vector3.new(1.5, 0, 1), { Color = Color3.fromRGB(210, 210, 200) }, folder)
	end
end

RoomDressers.ShaftBottom = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ShaftBottom")
	-- Marrow's field book lies with his old gear near the rope.
	local p = floorNear(ctx, anchor, Vector3.new(anchor.Radius * 0.3, 0, -anchor.Radius * 0.3))
	if p then
		Dress.AddLoreSlot(ctx, p, anchor.Zone, anchor.Id, false)
		Dress.PlaceOnFloor(ctx, "Lantern", p + Vector3.new(1.5, 0, 1.2), { Fallen = true }, folder)
		Dress.PlaceOnFloor(ctx, "RopeCoil", p + Vector3.new(-2, 0, 2), nil, folder)
	end
	-- Old rope ends heaped where they fell.
	for _ = 1, 2 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6)
		if q then
			Dress.Place(ctx, "RopeCoil", CFrame.new(q) * Dress.Yaw(ctx), nil, folder)
		end
	end
	local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.8)
	if q then
		Dress.AddLootSpot(ctx, q, anchor.Zone, false)
	end
end

RoomDressers.Cistern = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "Cistern")
	-- Stoves stacked by each expedition, one on top of the other.
	local p = floorNear(ctx, anchor, Vector3.new(-anchor.Radius * 0.6, 0, anchor.Radius * 0.2))
	if p then
		for i = 0, 2 do
			Dress.Place(ctx, "Stove", CFrame.new(p + UP * (i * 1.6)) * Dress.Yaw(ctx), nil, folder)
		end
		Dress.AddLoreSlot(ctx, p + Vector3.new(2.5, 0, 0), anchor.Zone, anchor.Id, false)
	end
	for _ = 1, 2 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.85, anchor.Radius * 0.5)
		if q then
			Dress.AddLootSpot(ctx, q, anchor.Zone, false)
		end
	end
end

RoomDressers.LoopRing = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "Ring")
	local landmark = anchor.Data.Landmark
	if landmark then
		local floor = Dress.FloorAt(ctx, landmark.Position + UP * 4, 6, 14) or landmark.Position
		local facing = landmark.Facing :: Vector3
		local skeleton = Dress.Place(ctx, "Skeleton", Dress.Facing(floor, floor + facing), { Pose = "Sitting" }, folder)
		skeleton.Name = "RingSkeleton"
		skeleton:SetAttribute("LandmarkId", "RingSkeleton")
		CollectionService:AddTag(skeleton, Constants.Tags.Landmark)
		ctx.Results.Landmarks.RingSkeleton = { Model = skeleton, Position = floor, Facing = facing }
		-- Tally marks on the wall behind it.
		local hit, normal = Dress.WallFrom(ctx, floor + UP * 3, -facing, 12)
		if hit and normal then
			Dress.Place(ctx, "WallText", Dress.OnWall(hit, normal) * CFrame.new(0, 1, 0), {
				Text = string.rep("|||| ", 18),
				Size = Vector2.new(6, 2.5),
				Font = Enum.Font.Fondamento,
			}, folder)
		end
		Dress.AddLoreSlot(ctx, floor - facing * 0.5 + facing:Cross(UP) * 2.5, anchor.Zone, anchor.Id, false)
	end
	local seal = anchor.Data.Seal
	if seal then
		local outward = seal.Outward :: Vector3
		local floor = Dress.FloorAt(ctx, (seal.Floor :: Vector3) - outward * 3 + UP * 4, 6, 12) or seal.Floor
		local rubble = Dress.Place(ctx, "Rubble", Dress.Facing(floor, floor + outward), { Spread = 6, Height = 2.5, Count = 26 }, folder)
		rubble.Name = "RingSealRubble"
		ctx.Results.RingSeal = {
			CFrame = seal.CFrame,
			Size = seal.Size,
			Rubble = rubble,
		}
	end
end

RoomDressers.DeepHall = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "DeepHall")
	local rng = ctx.Rng
	-- A forest of stalagmites.
	for _ = 1, 22 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.95, anchor.Radius * 0.25)
		if p then
			Dress.Place(ctx, "Stalagmite", CFrame.new(p - UP * 0.4), { Length = rng:NextNumber(3, 11), Material = Enum.Material.Slate, Color = Color3.fromRGB(58, 56, 56) }, folder)
		end
	end
	for _ = 1, 10 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.9)
		if p then
			local ceiling = Dress.CeilingAt(ctx, p + UP, 50)
			if ceiling then
				Dress.Place(ctx, "Stalactite", CFrame.new(ceiling + UP * 0.5), { Length = rng:NextNumber(3, 9), Material = Enum.Material.Slate, Color = Color3.fromRGB(62, 60, 58) }, folder)
			end
		end
	end
	-- Marrow's second page, and the first clear evidence: prints and claw marks.
	local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.4)
	if p then
		Dress.AddLoreSlot(ctx, p, anchor.Zone, anchor.Id, false)
	end
	local prints = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6)
	if prints then
		Dress.Place(ctx, "Footprints", CFrame.new(prints) * Dress.Yaw(ctx), { Monster = true, Count = 5, Color = Color3.fromRGB(28, 24, 22) }, folder)
		ctx.Results.EvidenceCount += 1
	end
	local wall, normal = Dress.NearestWall(ctx, anchor.Position + UP * 4, anchor.Radius * 1.5)
	if wall and normal then
		Dress.Place(ctx, "Scratches", Dress.OnWall(wall, normal) * CFrame.new(0, 3, 0), { Length = 7, Count = 4 }, folder)
		ctx.Results.EvidenceCount += 1
	end
end

RoomDressers.ExplorerCamp = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ExplorerCamp")
	local rng = ctx.Rng
	-- Three camps laid out identically: left tent, central stove, ropes right.
	local eras = {
		{ Tent = Color3.fromRGB(150, 130, 90), Bag = Color3.fromRGB(110, 90, 60) }, -- 1911
		{ Tent = Color3.fromRGB(170, 140, 40), Bag = Color3.fromRGB(120, 40, 30) }, -- 1958
		{ Tent = Color3.fromRGB(46, 90, 150), Bag = Color3.fromRGB(46, 58, 82) }, -- 1994
	}
	local baseAngle = rng:NextNumber(0, math.pi * 2)
	for i, era in eras do
		local angle = baseAngle + (i - 2) * 0.9
		local center = ringPoint(anchor, 0.5, angle)
		local floor = Dress.FloorAt(ctx, center + UP * 4, 6, 14)
		if floor then
			local toCenter = (anchor.Position - floor)
			local facing = Vector3.new(toCenter.X, 0, toCenter.Z).Unit
			local side = facing:Cross(UP)
			local base = Dress.Facing(floor, floor + facing)
			Dress.Place(ctx, "Tent", base * CFrame.new(-4, 0, 2) * CFrame.Angles(0, math.rad(90), 0), { Color = era.Tent, Collapsed = i == 1 }, folder)
			Dress.PlaceOnFloor(ctx, "Stove", floor + facing * 2, nil, folder)
			Dress.PlaceOnFloor(ctx, "RopeCoil", floor + side * 3.5, nil, folder)
			Dress.PlaceOnFloor(ctx, "SleepingBag", floor - side * 2 - facing * 1.5, { Color = era.Bag, Occupied = i == 2 }, folder)
			Dress.PlaceOnFloor(ctx, "Crate", floor + side * 4 - facing * 2, nil, folder)
			Dress.PlaceOnFloor(ctx, "Backpack", floor - side * 4, { Color = era.Bag }, folder)
			if i == 2 then
				-- One lantern still lit, guttering. Who lit it?
				Dress.PlaceOnFloor(ctx, "Lantern", floor + facing * 3.2 + side, { Lit = true, Fallen = false, Range = 18, Brightness = 0.55 }, folder)
			end
		end
	end
	-- Lindqvist's journal and the Strata tape are always here.
	local slotA = floorNear(ctx, anchor, Vector3.new(math.cos(baseAngle) * 4, 0, math.sin(baseAngle) * 4))
	local slotB = floorNear(ctx, anchor, Vector3.new(-math.cos(baseAngle) * 5, 0, -math.sin(baseAngle) * 5))
	if slotA then
		Dress.AddLoreSlot(ctx, slotA, anchor.Zone, anchor.Id, false)
	end
	if slotB then
		Dress.AddLoreSlot(ctx, slotB, anchor.Zone, anchor.Id, false)
	end
	for _ = 1, 3 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.85, anchor.Radius * 0.4)
		if q then
			Dress.AddLootSpot(ctx, q, anchor.Zone, false)
		end
	end
	-- An extra random lore slot for pooled camp entries.
	local r = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.7)
	if r then
		Dress.AddLoreSlot(ctx, r, anchor.Zone, nil, false)
	end
end

RoomDressers.Lair = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "Lair")
	local den = anchor.Data.Den :: Vector3?
	local denFloor = if den then Dress.FloorAt(ctx, den + UP * 4, 6, 14) else nil
	if denFloor then
		Dress.Place(ctx, "LampPile", CFrame.new(denFloor) * Dress.Yaw(ctx), { Count = 32 }, folder)
		Dress.AddLoreSlot(ctx, denFloor + Vector3.new(3, 0, 3), anchor.Zone, anchor.Id, false)
	end
	for _ = 1, 6 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.9)
		if p then
			Dress.Place(ctx, "BonePile", CFrame.new(p) * Dress.Yaw(ctx), nil, folder)
		end
	end
	for _ = 1, 4 do
		local angle = ctx.Rng:NextNumber(0, math.pi * 2)
		local hit, normal = Dress.WallFrom(ctx, anchor.Position + UP * 4, Vector3.new(math.cos(angle), 0, math.sin(angle)), anchor.Radius * 2)
		if hit and normal then
			Dress.Place(ctx, "Scratches", Dress.OnWall(hit, normal) * CFrame.new(0, ctx.Rng:NextNumber(1, 5), 0), { Length = ctx.Rng:NextNumber(5, 9) }, folder)
		end
	end
	-- The richest, deadliest loot in the cave outside the Old Works.
	for _ = 1, 2 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.8)
		if q then
			Dress.AddLootSpot(ctx, q, anchor.Zone, true)
		end
	end
end

RoomDressers.AncientGate = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "AncientGate")
	-- The arch faces the tunnel from the camp side.
	local camp = ctx.Plan.Anchors.Camp
	local toward = if camp then (camp.Position - anchor.Position) else Vector3.xAxis
	local dir = Vector3.new(toward.X, 0, toward.Z).Unit
	local archFloor = Dress.FloorAt(ctx, anchor.Position + dir * anchor.Radius * 0.55 + UP * 4, 6, 16)
	if archFloor then
		Dress.Place(ctx, "Arch", Dress.Facing(archFloor, archFloor + dir), { Width = 12, Height = 14 }, folder)
		Dress.AddLoreSlot(ctx, archFloor - dir * 4, anchor.Zone, anchor.Id, false, dir)
	end
	-- Steps descending into the chamber.
	local stepsFloor = Dress.FloorAt(ctx, anchor.Position - dir * 4 + UP * 4, 6, 16)
	if stepsFloor then
		Dress.Place(ctx, "Steps", Dress.Facing(stepsFloor, stepsFloor - dir), { Count = 4, Width = 12 }, folder)
	end
	for _ = 1, 3 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.85, anchor.Radius * 0.4)
		if p then
			Dress.Place(ctx, "StonePillar", CFrame.new(p) * Dress.Yaw(ctx), { Height = 10, Radius = 1.6, Broken = true }, folder)
		end
	end
end

RoomDressers.Colonnade = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "Colonnade")
	local rng = ctx.Rng
	local axisAngle = rng:NextNumber(0, math.pi)
	local axis = Vector3.new(math.cos(axisAngle), 0, math.sin(axisAngle))
	local side = axis:Cross(UP)
	for row = -1, 1, 2 do
		for i = -3, 3 do
			local p = Dress.FloorAt(ctx, anchor.Position + axis * (i * 8) + side * (row * 9) + UP * 4, 6, 16)
			if p then
				Dress.Place(ctx, "StonePillar", CFrame.new(p) * Dress.Yaw(ctx), {
					Height = anchor.Height * 1.4,
					Radius = 1.8,
					Broken = rng:NextNumber() < 0.3,
				}, folder)
			end
		end
	end
	local far = Dress.FloorAt(ctx, anchor.Position + axis * anchor.Radius * 0.7 + UP * 4, 6, 16)
	if far then
		Dress.Place(ctx, "Monolith", Dress.Facing(far, anchor.Position), { Height = 14 }, folder)
		Dress.AddLoreSlot(ctx, far - axis * 4, anchor.Zone, anchor.Id, false, -axis)
	end
	for _ = 1, 2 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6)
		if q then
			Dress.AddLootSpot(ctx, q, anchor.Zone, false)
		end
	end
	local r = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6)
	if r then
		Dress.AddLoreSlot(ctx, r, anchor.Zone, nil, false)
	end
end

-- The Gathering. Evidence of everyone who came before.
RoomDressers.FinalChamber = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "FinalChamber")
	local rng = ctx.Rng
	local mound = Dress.FloorAt(ctx, anchor.Position + UP * 20, 22, 40) or anchor.Position
	-- Standing stones on the mound in a ring around an altar.
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local p = Dress.FloorAt(ctx, mound + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 11 + UP * 8, 10, 20)
		if p then
			Dress.Place(ctx, "Monolith", Dress.Facing(p, mound), { Height = rng:NextNumber(9, 15) }, folder)
		end
	end
	Dress.Place(ctx, "Altar", CFrame.new(mound) * Dress.Yaw(ctx), nil, folder)
	Dress.AddLoreSlot(ctx, mound + Vector3.new(0, 4.1, 0), anchor.Zone, anchor.Id, false)

	-- Camps from every era, arranged in a ring facing the stones.
	local campColors = {
		Color3.fromRGB(150, 130, 90),
		Color3.fromRGB(170, 140, 40),
		Color3.fromRGB(46, 90, 150),
		Color3.fromRGB(200, 90, 30),
		Color3.fromRGB(150, 130, 90),
		Color3.fromRGB(46, 90, 150),
		Color3.fromRGB(210, 120, 40), -- the newest: your expedition's colours
	}
	for i, color in campColors do
		local angle = i / #campColors * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local center = ringPoint(anchor, rng:NextNumber(0.42, 0.5), angle)
		local floor = Dress.FloorAt(ctx, center + UP * 10, 14, 30)
		if floor then
			local facing = Vector3.new(mound.X - floor.X, 0, mound.Z - floor.Z).Unit
			local side = facing:Cross(UP)
			local base = Dress.Facing(floor, floor + facing)
			Dress.Place(ctx, "Tent", base * CFrame.new(0, 0, 5) * CFrame.Angles(0, math.rad(90), 0), { Color = color, Collapsed = i < #campColors and rng:NextNumber() < 0.6 }, folder)
			for k = 1, rng:NextInteger(2, 4) do
				local p = Dress.FloorAt(ctx, floor + side * (k * 2.6 - 6) + facing * rng:NextNumber(-1, 2) + UP * 4, 6, 12)
				if p then
					Dress.Place(ctx, "Skeleton", Dress.Facing(p, mound), { Pose = if rng:NextNumber() < 0.6 then "Sitting" else "Lying" }, folder)
				end
			end
			Dress.PlaceOnFloor(ctx, "Backpack", floor + side * 4.5, { Color = color }, folder)
			Dress.PlaceOnFloor(ctx, if rng:NextNumber() < 0.5 then "Lantern" else "Headlamp", floor - side * 4.5, nil, folder)
			Dress.PlaceOnFloor(ctx, "Camera", floor + facing * 3, { Old = i <= 2 }, folder)
			Dress.PlaceOnFloor(ctx, "RopeCoil", floor - facing * 3 + side * 2, nil, folder)
			Dress.PlaceOnFloor(ctx, "Clothing", floor + side * 2 - facing * 2.5, nil, folder)
			if i == #campColors then
				-- The newest camp has the current expedition's journal.
				Dress.AddLoreSlot(ctx, floor + facing * 1.5 - side * 1.5, anchor.Zone, anchor.Id, false, nil, "NewestCamp")
			end
		end
	end
	-- Hundreds of small belongings scattered across the floor.
	local scatter = { "Boot", "Helmet", "Headlamp", "Flashlight", "Journal", "Note", "Photograph", "BonePile", "Clothing", "Pickaxe" }
	for _ = 1, 70 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.85, 16)
		if p then
			Dress.Place(ctx, scatter[rng:NextInteger(1, #scatter)], CFrame.new(p) * Dress.Yaw(ctx), nil, folder)
		end
	end
	-- Remaining fixed lore entries sit among the camps.
	for _ = 1, 3 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6, anchor.Radius * 0.3)
		if p then
			Dress.AddLoreSlot(ctx, p, anchor.Zone, anchor.Id, false)
		end
	end
	-- Pooled lore slot plus rich loot.
	local hiddenCorner = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.9, anchor.Radius * 0.7)
	if hiddenCorner then
		Dress.AddLoreSlot(ctx, hiddenCorner, anchor.Zone, nil, false)
	end
	for _ = 1, 6 do
		local q = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.85, 20)
		if q then
			Dress.AddLootSpot(ctx, q, anchor.Zone, false)
		end
	end
	-- Pale lichen glows faintly on the columns: the only light down here.
	for _, column in anchor.Data.Columns or {} do
		local floor = Dress.FloorAt(ctx, column + UP * 10, 14, 30)
		if floor then
			Dress.Place(ctx, "GlowWorms", CFrame.new(floor + UP * rng:NextNumber(12, 24)), { Spread = 4, Count = 18 }, folder)
		end
	end
end

RoomDressers.ChimneyBase = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ChimneyBase")
	local wall, normal = Dress.NearestWall(ctx, anchor.Position + UP * 4, anchor.Radius * 1.5)
	if wall and normal then
		for i = 1, 5 do
			Dress.Place(ctx, "WallText", Dress.OnWall(wall, normal) * CFrame.new((i - 3) * 1.4, ctx.Rng:NextNumber(-1, 2), 0), {
				Text = "↑",
				Size = Vector2.new(1.4, 1.8),
				Font = Enum.Font.Fondamento,
				Color = Color3.fromRGB(220, 220, 214),
				Rotation = ctx.Rng:NextNumber(-12, 12),
			}, folder)
		end
	end
	if anchor.Id == "ChimneyBase" then
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.5)
		if p then
			Dress.AddLoreSlot(ctx, p, anchor.Zone, anchor.Id, false)
		end
	end
end

RoomDressers.ChimneyTop = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ChimneyTop")
	local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.6)
	if p then
		Dress.Place(ctx, "RopeCoil", CFrame.new(p), nil, folder)
	end
end

RoomDressers.ExitMouth = function(ctx, anchor)
	local folder = Dress.Folder(ctx, "ExitMouth")
	for _ = 1, 4 do
		local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.9)
		if p then
			local ceiling = Dress.CeilingAt(ctx, p + UP, 30)
			if ceiling then
				Dress.Place(ctx, "HangingRoots", CFrame.new(ceiling), nil, folder)
			end
		end
	end
end

return RoomDressers
