--!strict
-- Snaps graph nodes onto the real floor after terrain is built, so the
-- monster walks on the ground and never through it.
--
-- Rays start inside each node's open space (scaled by its radius, capped),
-- never a fixed distance above the floor: a fixed offset can start inside a
-- mound or low ceiling, and a ray that starts in rock finds nothing useful.

local Workspace = game:GetService("Workspace")

local CaveGraph = require(script.Parent.CaveGraph)

local NodeRefiner = {}

local function inRock(params: RaycastParams, point: Vector3): boolean
	-- A short ray that hits immediately means the point is inside terrain.
	local hit = Workspace:Raycast(point, Vector3.yAxis * 0.05, params)
	return hit ~= nil and hit.Distance < 0.01
end

function NodeRefiner.Refine(graph: CaveGraph.CaveGraph, yieldEvery: number?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	for i, node in graph.Nodes do
		local reach = math.clamp(node.Radius * 1.2, 4, 30)
		-- Try from inside the space first; fall back to lower starts.
		for _, height in { reach, reach * 0.5, 4 } do
			local origin = node.Position + Vector3.yAxis * height
			if not inRock(params, origin) then
				local result = Workspace:Raycast(origin, Vector3.yAxis * -(height + 14), params)
				if result then
					node.Position = result.Position
				end
				break
			end
		end
		if yieldEvery and i % yieldEvery == 0 then
			task.wait()
		end
	end
	graph:Rehash()
end

return NodeRefiner
