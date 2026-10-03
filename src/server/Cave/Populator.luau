--!strict
-- Dresses the carved terrain using the planner's features. Most rooms are
-- quiet. A few are beautiful, a few are wrong, and only some contain
-- anything frightening.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CaveConfig = require(Shared.Config.CaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Dress = require(script.Parent.DressContext)
local PropFactory = require(script.Parent.PropFactory)
local LoreData = require(Shared.Config.LoreData)
local RoomDressers = require(script.Parent.RoomDressers)
local Primitives = require(script.Parent.CavePrimitives)

type DressContext = Dress.DressContext
type Feature = Primitives.Feature

local UP = Vector3.yAxis

local Populator = {}

-- Room contents ---------------------------------------------------------------

local Contents: { [string]: (DressContext, Feature, Folder) -> () } = {}

Contents.Empty = function(ctx, f, folder)
	-- Sometimes an empty room has a page lying in it, and nothing else.
	if ctx.Rng:NextNumber() < 0.3 then
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.6)
		if p then
			Dress.AddLoreSlot(ctx, p, f.Zone, nil, false)
		end
	end
	if ctx.Rng:NextNumber() < 0.5 then
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.7)
		if p then
			Dress.Place(ctx, "Boulder", CFrame.new(p) * Dress.Yaw(ctx), nil, folder)
		end
	end
end

Contents.Nothing = function(_ctx, _f, _folder)
	-- Deliberately empty. Finding nothing at the end of a crawl is its own
	-- kind of unease.
end

Contents.Beautiful = function(ctx, f, folder)
	local rng = ctx.Rng
	if rng:NextNumber() < 0.6 then
		local ceiling = Dress.CeilingAt(ctx, f.Center + UP * 2, 40)
		if ceiling then
			Dress.Place(ctx, "GlowWorms", CFrame.new(ceiling - UP * 0.3), { Spread = f.Radius * 0.6, Count = 50 }, folder)
		end
	end
	for _ = 1, rng:NextInteger(2, 4) do
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.8, f.Radius * 0.3)
		if p then
			Dress.Place(ctx, "Crystals", CFrame.new(p) * Dress.Yaw(ctx), { Glow = rng:NextNumber() < 0.5 }, folder)
		end
	end
	for _ = 1, rng:NextInteger(3, 6) do
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.9)
		if p then
			Dress.Place(ctx, "Stalagmite", CFrame.new(p), { Length = rng:NextNumber(2, 6), Material = Enum.Material.Marble, Color = Color3.fromRGB(200, 192, 176) }, folder)
		end
	end
end

Contents.Loot = function(ctx, f, folder)
	for _ = 1, ctx.Rng:NextInteger(1, 3) do
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.75)
		if p then
			Dress.AddLootSpot(ctx, p, f.Zone, f.Hidden)
		end
	end
	if ctx.Rng:NextNumber() < 0.4 then
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.6)
		if p then
			Dress.Place(ctx, "Backpack", CFrame.new(p), nil, folder)
		end
	end
end

Contents.Treasure = function(ctx, f, folder)
	for _ = 1, ctx.Rng:NextInteger(2, 4) do
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.75)
		if p then
			Dress.AddLootSpot(ctx, p, f.Zone, true)
		end
	end
	local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.5)
	if p then
		Dress.Place(ctx, "Skeleton", CFrame.new(p) * Dress.Yaw(ctx), { Pose = "Lying" }, folder)
	end
end

Contents.Lore = function(ctx, f, folder)
	local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.5)
	if p then
		Dress.AddLoreSlot(ctx, p, f.Zone, nil, f.Hidden)
		if ctx.Rng:NextNumber() < 0.5 then
			local q = Dress.RandomFloor(ctx, p, 4)
			if q then
				Dress.Place(ctx, "Backpack", CFrame.new(q), nil, folder)
			end
		end
	end
end

Contents.Bones = function(ctx, f, folder)
	for _ = 1, ctx.Rng:NextInteger(1, 3) do
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.8)
		if p then
			Dress.Place(ctx, "BonePile", CFrame.new(p) * Dress.Yaw(ctx), nil, folder)
		end
	end
	if ctx.Rng:NextNumber() < 0.5 then
		local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.6)
		if p then
			Dress.AddLootSpot(ctx, p, f.Zone, f.Hidden)
		end
	end
end

Contents.Remains = function(ctx, f, folder)
	-- Several explorers huddled together, facing the same wall.
	local wall, normal = Dress.NearestWall(ctx, f.Center + UP * 3, f.Radius * 1.5)
	local base = if wall and normal then wall + Vector3.new(normal.X, 0, normal.Z).Unit * 2.5 else f.Center
	for i = 1, ctx.Rng:NextInteger(2, 4) do
		local p = Dress.FloorAt(ctx, base + Vector3.new((i - 2) * 2.4, 2, 0), 4, 10)
		if p then
			local cf = if wall then Dress.Facing(p, p + (p - wall)) else CFrame.new(p) * Dress.Yaw(ctx)
			Dress.Place(ctx, "Skeleton", cf, { Pose = "Sitting" }, folder)
		end
	end
	local p = Dress.RandomFloor(ctx, f.Center, f.Radius * 0.6)
	if p then
		Dress.AddLootSpot(ctx, p, f.Zone, true)
	end
end

-- "Why is this here?"
local WRONG = { "Chair", "DoorFrame", "Candle", "Telephone", "MadeBed", "ShoeLine" }

Contents.Wrong = function(ctx, f, folder)
	local rng = ctx.Rng
	local pick = WRONG[rng:NextInteger(1, #WRONG)]
	local wall, normal = Dress.NearestWall(ctx, f.Center + UP * 3, f.Radius * 1.4)
	local center = Dress.FloorAt(ctx, f.Center + UP * 2, 4, 12) or f.Center
	if pick == "Chair" and wall and normal then
		-- A chair placed a few studs from the wall, facing it.
		local p = Dress.FloorAt(ctx, wall + Vector3.new(normal.X, 0, normal.Z).Unit * 3 + UP * 2, 4, 12)
		if p then
			Dress.Place(ctx, "Chair", Dress.Facing(p, wall) * CFrame.Angles(0, math.rad(180), 0), nil, folder)
		end
	elseif pick == "DoorFrame" then
		Dress.Place(ctx, "DoorFrame", CFrame.new(center) * Dress.Yaw(ctx), nil, folder)
	elseif pick == "Candle" then
		-- Still burning. Nobody has been here in years.
		Dress.Place(ctx, "Candle", CFrame.new(center), nil, folder)
	elseif pick == "Telephone" then
		Dress.Place(ctx, "Telephone", CFrame.new(center), nil, folder)
	elseif pick == "MadeBed" then
		Dress.Place(ctx, "SleepingBag", CFrame.new(center) * Dress.Yaw(ctx), { Color = Color3.fromRGB(150, 150, 140) }, folder)
		Dress.Place(ctx, "Lantern", CFrame.new(center + Vector3.new(2.5, 0, 1.5)), { Fallen = false }, folder)
	elseif pick == "ShoeLine" then
		-- Boots lined up neatly, eight pairs, toes to the wall.
		local dir = if normal then Vector3.new(-normal.X, 0, -normal.Z).Unit else Vector3.zAxis
		local side = dir:Cross(UP)
		for i = -4, 3 do
			local p = Dress.FloorAt(ctx, center + side * (i * 1.4) + UP * 2, 4, 10)
			if p then
				local m = Dress.Place(ctx, "Boot", Dress.Facing(p, p + dir), nil, folder)
				m:PivotTo(Dress.Facing(p + UP * 0.4, p + dir + UP * 0.4))
			end
		end
	end
end

Contents.MiniCamp = function(ctx, f, folder)
	local center = Dress.FloorAt(ctx, f.Center + UP * 2, 4, 12) or f.Center
	Dress.Place(ctx, "SleepingBag", CFrame.new(center + Vector3.new(2, 0, 0)) * Dress.Yaw(ctx), { Occupied = ctx.Rng:NextNumber() < 0.3 }, folder)
	Dress.PlaceOnFloor(ctx, "Stove", center + Vector3.new(-2, 0, 1.5), nil, folder)
	Dress.PlaceOnFloor(ctx, "Lantern", center + Vector3.new(-1, 0, -2), nil, folder)
	Dress.PlaceOnFloor(ctx, "Backpack", center + Vector3.new(3, 0, 3), nil, folder)
	if ctx.Rng:NextNumber() < 0.6 then
		Dress.AddLoreSlot(ctx, center + Vector3.new(0, 0, 2.5), f.Zone, nil, f.Hidden)
	else
		Dress.AddLootSpot(ctx, center + Vector3.new(0.5, 0, 2.5), f.Zone, f.Hidden)
	end
end

Contents.Hiding = function(ctx, f, folder)
	-- A cluster of fallen slabs with a dark gap behind them.
	local wall, normal = Dress.NearestWall(ctx, f.Center + UP * 3, f.Radius * 1.4)
	if not (wall and normal) then
		return
	end
	local out = Vector3.new(normal.X, 0, normal.Z).Unit
	local gap = Dress.FloorAt(ctx, wall + out * 2.5 + UP * 2, 4, 12)
	if not gap then
		return
	end
	local side = out:Cross(UP)
	Dress.Place(ctx, "Boulder", CFrame.new(gap + out * 4 + side * 2.5) * Dress.Yaw(ctx), { Size = 5.5 }, folder)
	Dress.Place(ctx, "Boulder", CFrame.new(gap + out * 4.5 - side * 2.5) * Dress.Yaw(ctx), { Size = 4.5 }, folder)
	Dress.AddHidingSpot(ctx, Dress.Facing(gap + UP * 2.5, gap + out), Vector3.new(5, 5, 4), f.Zone)
end

Contents.Disturbing = function(ctx, f, folder)
	local rng = ctx.Rng
	local center = Dress.FloorAt(ctx, f.Center + UP * 2, 4, 12) or f.Center
	local variant = rng:NextInteger(1, 4)
	if variant == 1 then
		-- A circle of headlamps all pointed at the middle of the room.
		for i = 1, 9 do
			local angle = i / 9 * math.pi * 2
			local p = Dress.FloorAt(ctx, center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 4.5 + UP * 2, 4, 10)
			if p then
				Dress.Place(ctx, "Headlamp", Dress.Facing(p, center), nil, folder)
			end
		end
	elseif variant == 2 then
		-- The walls covered in the same sentence.
		for _ = 1, 7 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local hit, normal = Dress.WallFrom(ctx, center + UP * rng:NextNumber(2, 6), Vector3.new(math.cos(angle), 0, math.sin(angle)), f.Radius * 2)
			if hit and normal then
				Dress.Place(ctx, "WallText", Dress.OnWall(hit, normal), { Text = "it lets you go", Size = Vector2.new(5, 1.4), Rotation = rng:NextNumber(-8, 8) }, folder)
			end
		end
	elseif variant == 3 then
		-- Someone sat facing the wall with their hands over their ears.
		local wall, normal = Dress.NearestWall(ctx, center + UP * 3, f.Radius * 1.5)
		if wall and normal then
			local p = Dress.FloorAt(ctx, wall + Vector3.new(normal.X, 0, normal.Z).Unit * 1.6 + UP * 2, 4, 10)
			if p then
				Dress.Place(ctx, "Skeleton", Dress.Facing(p, wall), { Pose = "Sitting" }, folder)
			end
		end
	else
		-- Clothes folded neatly. Your size. Your colours.
		Dress.Place(ctx, "Clothing", CFrame.new(center), nil, folder)
		Dress.Place(ctx, "Helmet", CFrame.new(center + Vector3.new(1.2, 0, 0.5)), { Color = Color3.fromRGB(210, 120, 40) }, folder)
		Dress.Place(ctx, "Headlamp", CFrame.new(center + Vector3.new(-1, 0, 0.8)), nil, folder)
	end
	if rng:NextNumber() < 0.5 then
		Dress.AddLoreSlot(ctx, center + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)), f.Zone, nil, true)
	end
end

Contents.PitEdge = function(ctx, f, folder)
	-- Loot on the far side of the drop; bones of someone who tried.
	local rng = ctx.Rng
	local angle = rng:NextNumber(0, math.pi * 2)
	local far = f.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (f.Radius + 2)
	local floor = Dress.FloorAt(ctx, far + UP * 3, 4, 10)
	if floor then
		Dress.AddLootSpot(ctx, floor, f.Zone, false)
	end
	local near = f.Center - Vector3.new(math.cos(angle), 0, math.sin(angle)) * (f.Radius + 1.5)
	local nearFloor = Dress.FloorAt(ctx, near + UP * 3, 4, 10)
	if nearFloor then
		Dress.Place(ctx, "BonePile", CFrame.new(nearFloor), nil, folder)
	end
end

Contents.Pool = function(ctx, f, folder)
	-- Something glints at the bottom.
	local bottom = Dress.FloorAt(ctx, f.Center - UP * 2, 2, f.Depth or 12)
	if bottom then
		Dress.AddLootSpot(ctx, bottom, f.Zone, false)
		if ctx.Rng:NextNumber() < 0.5 then
			Dress.Place(ctx, "Skeleton", CFrame.new(bottom + Vector3.new(2, 0, 0)) * Dress.Yaw(ctx), { Pose = "Lying" }, folder)
		end
	end
end

-- Generic features --------------------------------------------------------------

local Features: { [string]: (DressContext, Feature) -> () } = {}

Features.Room = function(ctx, f)
	local folder = Dress.Folder(ctx, if f.Hidden then "HiddenRoom" else "Room")
	local handler = Contents[f.Content] or Contents.Empty
	handler(ctx, f, folder)
	if f.Hidden and f.SecretId then
		folder:SetAttribute(Constants.Attributes.SecretId, f.SecretId)
	end
end

Features.Alcove = function(ctx, f)
	local position = f.Position :: Vector3
	local normal = f.Normal :: Vector3
	Dress.AddHidingSpot(ctx, Dress.Facing(position, position + normal), Vector3.new(5, 5.5, 5), f.Zone)
end

Features.DeadEnd = function(ctx, f)
	local rng = ctx.Rng
	local floor = Dress.FloorAt(ctx, f.Position + UP * 2, 4, 12)
	if not floor or rng:NextNumber() < 0.35 then
		return
	end
	local folder = Dress.Folder(ctx, "DeadEnd")
	local dir = f.Direction :: Vector3
	-- Someone came this far, stopped, and left something behind.
	if ctx.Rng:NextNumber() < 0.4 then
		Dress.AddLoreSlot(ctx, floor - dir * 2.5, f.Zone, nil, false)
	end
	local roll = rng:NextInteger(1, 5)
	if roll == 1 then
		Dress.Place(ctx, "Boot", CFrame.new(floor), nil, folder)
	elseif roll == 2 then
		-- Footprints that walk straight into the wall.
		Dress.Place(ctx, "Footprints", Dress.Facing(floor - dir * 12, floor), { Count = 6 }, folder)
	elseif roll == 3 then
		local hit, normal = Dress.WallFrom(ctx, floor + UP * 3, dir, 12)
		if hit and normal then
			local messages = { "WRONG WAY", "not this one either", "||||  ||||  ||||  |||", "back. go back.", "it was here" }
			Dress.Place(ctx, "WallText", Dress.OnWall(hit, normal), { Text = messages[rng:NextInteger(1, #messages)], Size = Vector2.new(5, 1.6) }, folder)
		end
	elseif roll == 4 then
		Dress.Place(ctx, "Skeleton", Dress.Facing(floor, floor - dir), { Pose = "Sitting" }, folder)
	else
		Dress.Place(ctx, "Backpack", CFrame.new(floor), nil, folder)
		Dress.AddLootSpot(ctx, floor - dir * 1.5, f.Zone, false)
	end
end

Features.Collapse = function(ctx, f)
	local floor = Dress.FloorAt(ctx, f.Position + UP * 2, 4, 12)
	if not floor then
		return
	end
	local dir = f.Direction :: Vector3
	local folder = Dress.Folder(ctx, "Collapse")
	Dress.Place(ctx, "Rubble", Dress.Facing(floor, floor + dir), { Spread = f.Radius, Height = 3, Count = 22 }, folder)
	-- Sometimes there are sounds on the other side of the rubble.
	if ctx.Rng:NextNumber() < 0.5 then
		local emitter = Instance.new("Attachment")
		emitter.Name = "Behind"
		emitter.WorldPosition = floor + dir * 6 + UP * 3
		emitter:SetAttribute("Sound", if ctx.Rng:NextNumber() < 0.5 then "Knock" else "Scrape")
		emitter:SetAttribute("Chance", 0.25)
		emitter.Parent = workspace.Terrain
		CollectionService:AddTag(emitter, Constants.Tags.AmbientEmitter)
	end
end

Features.CrackMouth = function(ctx, f)
	-- A boulder half-covering the crack: visible only if you look closely.
	local floor = Dress.FloorAt(ctx, f.Position + UP * 2, 4, 12)
	if not floor then
		return
	end
	local dir = f.Direction :: Vector3
	local side = dir:Cross(UP)
	Dress.Place(ctx, "Boulder", CFrame.new(floor - dir * 2 + side * 3) * Dress.Yaw(ctx), { Size = 6.5 }, nil)
end

Features.SqueezeMouth = function(ctx, f)
	local position = f.Position :: Vector3
	local dir = f.Direction :: Vector3
	-- Invisible blocker: the passage is only passable through the traversal.
	local blocker = Instance.new("Part")
	blocker.Name = "SqueezeBlocker"
	blocker.Anchored = true
	blocker.Transparency = 1
	blocker.CanQuery = false
	blocker.CanTouch = false
	blocker.CastShadow = false
	blocker.Size = Vector3.new(8, 8, 1.5)
	blocker.CFrame = CFrame.lookAt(position + UP * 3.5 + dir * 1.5, position + UP * 3.5 + dir * 3)
	blocker.CollisionGroup = Constants.CollisionGroups.Blockers
	blocker.Parent = ctx.Volumes
	-- Frame the crack with a couple of slabs so it reads as a tight squeeze.
	local side = dir:Cross(UP)
	for _, s in { -1, 1 } do
		Dress.Place(ctx, "Boulder", CFrame.new(position + side * s * 3.6 - UP * 0.5) * Dress.Yaw(ctx), { Size = 3.5, Collide = false }, nil)
	end
end

Features.Pit = function(ctx, f)
	-- Loose stones at the lip so the edge reads as unstable.
	local folder = Dress.Folder(ctx, "PitLip")
	for _ = 1, 4 do
		local angle = ctx.Rng:NextNumber(0, math.pi * 2)
		local p = Dress.FloorAt(ctx, f.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (f.Radius + 1.5) + UP * 3, 4, 8)
		if p then
			Dress.Place(ctx, "Rubble", CFrame.new(p) * Dress.Yaw(ctx), { Spread = 1.5, Count = 4, Height = 0.2 }, folder)
		end
	end
end

Features.Bridge = function(ctx, f)
	local a = f.A :: Vector3
	local b = f.B :: Vector3
	local floorA = Dress.FloorAt(ctx, a + UP * 3, 4, 10) or a
	local floorB = Dress.FloorAt(ctx, b + UP * 3, 4, 10) or b
	local start = floorA - (f.Direction :: Vector3) * 2
	local finish = floorB + (f.Direction :: Vector3) * 2
	local length = (finish - start).Magnitude
	local cf = CFrame.lookAt(start, finish)
	local model = Dress.Place(ctx, "Bridge", cf * CFrame.new(0, -0.1, 0), { Length = length })
	model.Name = "UnstableBridge"
	table.insert(ctx.Results.Bridges, { Model = model, A = start, B = finish })
end

Features.Rope = function(ctx, f)
	-- The shaft rope plus older ropes left by previous expeditions.
	local path = f.Path :: { Vector3 }
	local top = path[2] + UP * 14
	local bottom = path[3]
	local length = (top - bottom).Magnitude + 2
	local folder = Dress.Folder(ctx, "ShaftRopes")
	local rope = Dress.Place(ctx, "HangingRope", CFrame.new(top), { Length = length, Sway = 0.3, Thickness = 0.28, Color = Color3.fromRGB(196, 92, 44) }, folder)
	ctx.Results.TraversalProps[f.TraversalId] = rope
	local dir = f.Direction :: Vector3
	local side = dir:Cross(UP)
	local olds = {
		{ Offset = side * 3, Length = length * 0.3, Color = Color3.fromRGB(110, 92, 60) }, -- 1911 hemp, rotted through
		{ Offset = -side * 3.5, Length = length * 0.92, Color = Color3.fromRGB(170, 170, 60) }, -- 1958
		{ Offset = side * 6, Length = length, Color = Color3.fromRGB(60, 110, 170) }, -- 1994
	}
	for _, old in olds do
		Dress.Place(ctx, "HangingRope", CFrame.new(top + old.Offset), { Length = old.Length, Sway = 1.2, Color = old.Color, Old = true }, folder)
	end
	local anchorFloor = Dress.FloorAt(ctx, path[1] + UP * 2, 4, 10)
	if anchorFloor then
		Dress.Place(ctx, "Tripod", Dress.Facing(anchorFloor + dir * 1.5, anchorFloor + dir * 5), nil, folder)
		Dress.Place(ctx, "RopeCoil", CFrame.new(anchorFloor - dir * 2 + side * 2), nil, folder)
	end
end

Features.ClimbRoute = function(ctx, f)
	local path = f.Path :: { Vector3 }
	local bottom = path[2]
	local top = path[3] + UP * 6
	local folder = Dress.Folder(ctx, "ClimbRope")
	local rope = Dress.Place(ctx, "HangingRope", CFrame.new(top), { Length = (top - bottom).Magnitude, Sway = 0.15, Color = Color3.fromRGB(140, 120, 80) }, folder)
	ctx.Results.TraversalProps[f.TraversalId] = rope
	-- Pitons hammered into the rock along the line.
	local dir = f.Direction :: Vector3
	local y = bottom.Y + 6
	while y < top.Y - 4 do
		local hit, normal = Dress.WallFrom(ctx, Vector3.new(bottom.X, y, bottom.Z), dir, 10)
		if hit and normal then
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.Size = Vector3.new(0.2, 0.2, 0.9)
			p.Material = Enum.Material.CorrodedMetal
			p.Color = Color3.fromRGB(90, 86, 80)
			p.CFrame = CFrame.lookAt(hit + normal * 0.3, hit + normal)
			p.Parent = folder
		end
		y += ctx.Rng:NextNumber(8, 14)
	end
end

Features.Recursion = function(ctx, f)
	-- Publish the corridor to clients through a persistent marker part.
	local origin = f.Origin :: Vector3
	local axis = f.Axis :: Vector3
	local cfg = CaveConfig.Recursion
	local marker = Instance.new("Part")
	marker.Name = "RecursionCorridor"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.CFrame = CFrame.lookAt(origin, origin + axis)
	marker:SetAttribute("ModuleLength", f.ModuleLength)
	marker:SetAttribute("Modules", f.Modules)
	marker:SetAttribute("TriggerModule", cfg.TriggerModule)
	marker:SetAttribute("TeleportModules", cfg.TeleportModules)
	marker:SetAttribute("LapsMin", cfg.Laps.Min)
	marker:SetAttribute("LapsMax", cfg.Laps.Max)
	marker:SetAttribute("Radius", f.Radius)
	marker.Parent = ctx.Markers
	CollectionService:AddTag(marker, Constants.Tags.RecursionCorridor)

	-- Identical dressing in every module: the same crack shaped like a seven,
	-- the same survey stake. A fixed seed keeps every module the same.
	local side = f.Side :: Vector3
	local folder = Dress.Folder(ctx, "Recursion")
	for m = 0, f.Modules - 1 do
		local moduleRng = Random.new(4242)
		local base = origin + axis * (m * f.ModuleLength)
		local ceiling = Dress.CeilingAt(ctx, base + axis * 15 + UP * 3, 20)
		if ceiling then
			local crack = Instance.new("Model")
			crack.Name = "Seven"
			local p1 = Instance.new("Part")
			p1.Anchored = true
			p1.CanCollide = false
			p1.CanQuery = false
			p1.Size = Vector3.new(3.2, 0.1, 0.25)
			p1.Color = Color3.fromRGB(18, 18, 18)
			p1.Material = Enum.Material.Slate
			p1.CFrame = CFrame.lookAt(ceiling - UP * 0.05, ceiling - UP * 0.05 + axis)
			p1.Parent = crack
			local p2 = p1:Clone()
			p2.Size = Vector3.new(0.25, 0.1, 4)
			p2.CFrame = p1.CFrame * CFrame.new(1.4, 0, 1.7) * CFrame.Angles(0, math.rad(-20), 0)
			p2.Parent = crack
			crack.Parent = folder
		end
		local stakeFloor = Dress.FloorAt(ctx, base + axis * 4 + side * (f.Radius * 0.55) + UP * 3, 4, 10)
		if stakeFloor then
			PropFactory.Build("Stake", CFrame.new(stakeFloor), moduleRng, nil, folder)
		end
	end
end

local function decorateTunnel(ctx: DressContext, f: Feature)
	local rng = ctx.Rng
	local deco = CaveConfig.Decoration
	local zone = ZoneConfig.Get(f.Zone)
	local samples = f.Samples :: { Primitives.Sample }
	local folder = Dress.Folder(ctx, "TunnelDecor")
	local stalactiteChance = deco.StalactitesPerHundred / 100 * 12
	local stalagmiteChance = deco.StalagmitesPerHundred / 100 * 12
	local boulderChance = deco.BouldersPerHundred / 100 * 12
	local rockfallChance = deco.RockfallSpotsPerHundred / 100 * 12
	local evidenceChance = if f.Zone == "WetCave" or f.Zone == "DeepCave" then 0.05 else 0
	local rootChance = if f.Zone == "UpperCave" then 0.12 else 0
	local i = 1
	while i <= #samples do
		local s = samples[i]
		local center = s.P
		local angle = rng:NextNumber(0, math.pi * 2)
		local lateral = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if rng:NextNumber() < stalactiteChance then
			local ceiling = Dress.CeilingAt(ctx, center + lateral * s.R * 0.4, s.R * 2)
			if ceiling then
				Dress.Place(ctx, "Stalactite", CFrame.new(ceiling + UP * 0.5), { Length = rng:NextNumber(1.5, math.min(6, s.R * 0.6)) }, folder)
			end
		end
		if rng:NextNumber() < stalagmiteChance then
			local floor = Dress.FloorAt(ctx, center + lateral * s.R * 0.7, 2, s.R * 2)
			if floor then
				Dress.Place(ctx, "Stalagmite", CFrame.new(floor - UP * 0.3), { Length = rng:NextNumber(1.5, 4.5) }, folder)
			end
		end
		if rng:NextNumber() < boulderChance then
			local floor = Dress.FloorAt(ctx, center + lateral * s.R * 0.65, 2, s.R * 2)
			if floor then
				Dress.Place(ctx, "Boulder", CFrame.new(floor) * Dress.Yaw(ctx), { Size = rng:NextNumber(1.5, 3.5), Material = zone.WallMaterial }, folder)
			end
		end
		if rng:NextNumber() < rockfallChance then
			local ceiling = Dress.CeilingAt(ctx, center, s.R * 2)
			local floor = Dress.FloorAt(ctx, center, 2, s.R * 2)
			if ceiling and floor then
				table.insert(ctx.Results.RockfallSpots, { Ceiling = ceiling - UP * 1.5, Floor = floor, Zone = f.Zone })
			end
		end
		if rng:NextNumber() < rootChance then
			local ceiling = Dress.CeilingAt(ctx, center + lateral * s.R * 0.3, s.R * 2)
			if ceiling then
				Dress.Place(ctx, "HangingRoots", CFrame.new(ceiling), nil, folder)
			end
		end
		if rng:NextNumber() < evidenceChance then
			-- Monster evidence: introduced long before the monster itself.
			ctx.Results.EvidenceCount += 1
			local nextS = samples[math.min(#samples, i + 4)]
			local forward = (nextS.P - s.P)
			if forward.Magnitude > 0.1 then
				forward = Vector3.new(forward.X, 0, forward.Z).Unit
				if f.Zone == "WetCave" then
					local floor = Dress.FloorAt(ctx, center, 2, s.R * 2)
					if floor then
						Dress.Place(ctx, "Footprints", Dress.Facing(floor, floor + forward), { Monster = true, Count = 4 }, folder)
					end
				else
					local hit, normal = Dress.WallFrom(ctx, center + UP * 2, lateral, s.R * 2)
					if hit and normal then
						Dress.Place(ctx, "Scratches", Dress.OnWall(hit, normal) * CFrame.new(0, 2, 0), { Length = rng:NextNumber(4, 7) }, folder)
					end
				end
			end
		end
		i += 4
	end
end

Features.TunnelDecor = decorateTunnel

-- Entry --------------------------------------------------------------------------

-- Scattered lore needs somewhere to land in every zone it belongs to. Top
-- each zone up to the number of entries that want it, with a dropped page or
-- device somewhere along that zone's tunnels.
local function ensureLoreSlots(ctx: DressContext)
	local wanted: { [string]: number } = {}
	for _, entry in LoreData.Entries do
		if not entry.Anchor and not entry.SlotTag and entry.Zones then
			-- Count each entry fully in every zone it may use: slots are
			-- cheap, and a shared entry must never starve a zone.
			for _, zone in entry.Zones do
				wanted[zone] = (wanted[zone] or 0) + 1
			end
		end
	end
	local have: { [string]: number } = {}
	for _, slot in ctx.Results.LoreSlots do
		if not slot.Anchor then
			have[slot.Zone] = (have[slot.Zone] or 0) + 1
		end
	end
	local tunnels: { [string]: { { Samples: { Primitives.Sample } } } } = {}
	for _, f in ctx.Plan.Features do
		if f.Kind == "TunnelDecor" then
			tunnels[f.Zone] = tunnels[f.Zone] or {}
			table.insert(tunnels[f.Zone], { Samples = f.Samples })
		end
	end
	local rng = ctx.Rng
	for zone, amount in wanted do
		local options = tunnels[zone]
		-- One spare: hidden entries fall back to ordinary slots when no
		-- hidden room in their zone took lore this run.
		local deficit = math.ceil(amount) + 1 - (have[zone] or 0)
		if not options then
			-- Zones without tunnels of their own (the camp): use their rooms.
			for _, anchor in ctx.Plan.Anchors do
				if anchor.Zone == zone and deficit > 0 then
					for _ = 1, deficit * 3 do
						local p = Dress.RandomFloor(ctx, anchor.Position, anchor.Radius * 0.8, anchor.Radius * 0.3)
						if p then
							Dress.AddLoreSlot(ctx, p, zone, nil, false)
							deficit -= 1
							if deficit <= 0 then
								break
							end
						end
					end
				end
			end
		end
		local attempts = 0
		while options and deficit > 0 and attempts < 40 do
			attempts += 1
			local tunnel = options[rng:NextInteger(1, #options)]
			local samples = tunnel.Samples
			if #samples > 10 then
				local sample = samples[rng:NextInteger(5, #samples - 5)]
				local angle = rng:NextNumber(0, math.pi * 2)
				local p = sample.Floor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * sample.R * 0.5
				local floor = Dress.FloorAt(ctx, p + UP * 3, 4, 10)
				if floor then
					Dress.AddLoreSlot(ctx, floor, zone, nil, false)
					deficit -= 1
				end
			end
		end
	end
end

function Populator.Run(ctx: DressContext)
	local plan = ctx.Plan
	local count = 0
	for _, f in plan.Features do
		if f.Kind == "Anchor" then
			local anchor = plan.Anchors[f.Id]
			local dresser = RoomDressers[anchor.Builder]
			if dresser then
				dresser(ctx, anchor)
			end
		else
			local handler = Features[f.Kind]
			if handler then
				handler(ctx, f)
			end
		end
		count += 1
		if count % 20 == 0 then
			task.wait()
		end
	end
	ensureLoreSlots(ctx)
end

return Populator
