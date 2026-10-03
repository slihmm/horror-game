--!strict
-- Executes a plan's terrain operations in the required order. Yields
-- periodically so a large cave never trips the script timeout and the server
-- stays responsive while it builds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local Primitives = require(script.Parent.CavePrimitives)

type Op = Primitives.Op
type Ops = Primitives.Ops

local TerrainBuilder = {}

local function run(terrain: Terrain, op: Op)
	local material = op.Material
	if op.Shape == "Ball" then
		terrain:FillBall(op.Center :: Vector3, op.Radius :: number, material)
	elseif op.Shape == "Block" then
		terrain:FillBlock(op.CFrame :: CFrame, op.Size :: Vector3, material)
	elseif op.Shape == "Cylinder" then
		terrain:FillCylinder(op.CFrame :: CFrame, op.Height :: number, op.Radius :: number, material)
	end
end

local function fillWater(terrain: Terrain, op: Op)
	-- Water only replaces air, so it never eats into walls.
	if op.Shape == "Block" then
		terrain:ReplaceMaterialInTransform(op.CFrame :: CFrame, op.Size :: Vector3, Enum.Material.Air, Enum.Material.Water)
	end
end

local ORDER = { "Shell", "Carve", "Floor", "Detail", "Late" }

-- onProgress(stageName, fraction) is optional.
function TerrainBuilder.Build(ops: Ops, onProgress: ((string, number) -> ())?)
	local terrain = Workspace.Terrain
	local perYield = CaveConfig.OpsPerYield
	local total = 0
	for _, stage in ORDER do
		total += #(ops :: any)[stage]
	end
	total += #ops.Water
	local done = 0
	local function tick(stage: string)
		done += 1
		if done % perYield == 0 then
			if onProgress then
				onProgress(stage, done / math.max(total, 1))
			end
			task.wait()
		end
	end
	for _, stage in ORDER do
		for _, op in (ops :: any)[stage] :: { Op } do
			run(terrain, op)
			tick(stage)
		end
	end
	for _, op in ops.Water do
		fillWater(terrain, op)
		tick("Water")
	end
	if onProgress then
		onProgress("Done", 1)
	end
end

return TerrainBuilder
