--!strict
-- Graph of the generated cave. Nodes sit on the walkable floor along tunnel
-- centerlines and inside chambers. The same graph drives:
--   * monster navigation (A* over Walk links: no per-frame pathfinding)
--   * zone / depth / progress tracking for players
--   * placement queries for the Horror Director (shadow figures, sounds)

export type LinkKind = "Walk" | "Rope" | "Climb" | "Squeeze"

export type Link = {
	To: number,
	Cost: number,
	Kind: LinkKind,
	-- Disabled links are ignored by pathfinding (e.g. the sealed ring exit).
	Enabled: boolean,
	Tag: string?,
}

export type Node = {
	Id: number,
	Position: Vector3, -- point on the floor
	Radius: number, -- open space around the node (tunnel/chamber radius)
	Zone: string,
	Anchor: string?,
	Group: number,
	Links: { Link },
	-- Path distance from the cave entrance (studs). math.huge if unreachable.
	Dist: number,
	Tags: { [string]: boolean },
}

local CELL = 24

local CaveGraph = {}
CaveGraph.__index = CaveGraph

type GraphData = {
	Nodes: { Node },
	_hash: { [number]: { Node } },
}
export type CaveGraph = typeof(setmetatable({} :: GraphData, CaveGraph))

local function cellKey(x: number, y: number, z: number): number
	-- Packs three signed cell coordinates into one number key.
	return (x + 2048) * 16777216 + (y + 2048) * 4096 + (z + 2048)
end

local function cellOf(p: Vector3): (number, number, number)
	return math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL)
end

function CaveGraph.new(): CaveGraph
	local data: GraphData = { Nodes = {}, _hash = {} }
	return setmetatable(data, CaveGraph)
end

function CaveGraph._insert(self: CaveGraph, node: Node)
	local cx, cy, cz = cellOf(node.Position)
	local key = cellKey(cx, cy, cz)
	local bucket = self._hash[key]
	if not bucket then
		bucket = {}
		self._hash[key] = bucket
	end
	table.insert(bucket, node)
end

function CaveGraph.AddNode(self: CaveGraph, position: Vector3, radius: number, zone: string, group: number, anchor: string?): Node
	local node: Node = {
		Id = #self.Nodes + 1,
		Position = position,
		Radius = radius,
		Zone = zone,
		Anchor = anchor,
		Group = group,
		Links = {},
		Dist = math.huge,
		Tags = {},
	}
	table.insert(self.Nodes, node)
	self:_insert(node)
	return node
end

-- Rebuilds the spatial hash after node positions are refined.
function CaveGraph.Rehash(self: CaveGraph)
	table.clear(self._hash)
	for _, node in self.Nodes do
		self:_insert(node)
	end
end

function CaveGraph.Link(self: CaveGraph, a: Node, b: Node, kind: LinkKind?, tag: string?)
	if a == b then
		return
	end
	for _, link in a.Links do
		if link.To == b.Id then
			return
		end
	end
	local cost = (a.Position - b.Position).Magnitude
	local k: LinkKind = kind or "Walk"
	table.insert(a.Links, { To = b.Id, Cost = cost, Kind = k, Enabled = true, Tag = tag })
	table.insert(b.Links, { To = a.Id, Cost = cost, Kind = k, Enabled = true, Tag = tag })
end

function CaveGraph.SetLinkEnabled(self: CaveGraph, tag: string, enabled: boolean)
	for _, node in self.Nodes do
		for _, link in node.Links do
			if link.Tag == tag then
				link.Enabled = enabled
			end
		end
	end
end

function CaveGraph.Within(self: CaveGraph, position: Vector3, radius: number): { Node }
	local result: { Node } = {}
	local minX, minY, minZ = cellOf(position - Vector3.one * radius)
	local maxX, maxY, maxZ = cellOf(position + Vector3.one * radius)
	local radiusSq = radius * radius
	for x = minX, maxX do
		for y = minY, maxY do
			for z = minZ, maxZ do
				local bucket = self._hash[cellKey(x, y, z)]
				if bucket then
					for _, node in bucket do
						local d = node.Position - position
						if d:Dot(d) <= radiusSq then
							table.insert(result, node)
						end
					end
				end
			end
		end
	end
	return result
end

function CaveGraph.Nearest(self: CaveGraph, position: Vector3, maxDistance: number?, filter: ((Node) -> boolean)?): Node?
	local limit = maxDistance or 160
	-- Expand the search ring until something is found.
	local radius = CELL
	while radius <= limit + CELL do
		local best: Node? = nil
		local bestDist = math.huge
		for _, node in self:Within(position, math.min(radius, limit)) do
			if not filter or filter(node) then
				local d = (node.Position - position).Magnitude
				if d < bestDist then
					best = node
					bestDist = d
				end
			end
		end
		if best then
			return best
		end
		radius *= 2
	end
	return nil
end

-- Dijkstra from the entrance over every enabled link. Used for the
-- "furthest reached" statistic and to measure story progress.
function CaveGraph.ComputeDistances(self: CaveGraph, start: Node)
	for _, node in self.Nodes do
		node.Dist = math.huge
	end
	start.Dist = 0
	-- Small binary heap keyed on distance.
	local heap: { Node } = { start }
	local function push(node: Node)
		table.insert(heap, node)
		local i = #heap
		while i > 1 do
			local parent = i // 2
			if heap[parent].Dist <= heap[i].Dist then
				break
			end
			heap[parent], heap[i] = heap[i], heap[parent]
			i = parent
		end
	end
	local function pop(): Node
		local top = heap[1]
		local last = table.remove(heap) :: Node
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r = i * 2, i * 2 + 1
				local smallest = i
				if l <= #heap and heap[l].Dist < heap[smallest].Dist then
					smallest = l
				end
				if r <= #heap and heap[r].Dist < heap[smallest].Dist then
					smallest = r
				end
				if smallest == i then
					break
				end
				heap[smallest], heap[i] = heap[i], heap[smallest]
				i = smallest
			end
		end
		return top
	end
	local settled: { [number]: boolean } = {}
	while #heap > 0 do
		local node = pop()
		if not settled[node.Id] then
			settled[node.Id] = true
			for _, link in node.Links do
				local other = self.Nodes[link.To]
				local candidate = node.Dist + link.Cost
				if candidate < other.Dist then
					other.Dist = candidate
					push(other)
				end
			end
		end
	end
end

-- A* between two nodes. `canUse` filters links (e.g. the monster can only
-- walk; it cannot use ropes or squeezes).
function CaveGraph.FindPath(self: CaveGraph, from: Node, to: Node, canUse: ((Link, Node) -> boolean)?): { Node }?
	if from == to then
		return { from }
	end
	local nodes = self.Nodes
	local open: { [number]: boolean } = { [from.Id] = true }
	local openCount = 1
	local cameFrom: { [number]: number } = {}
	local g: { [number]: number } = { [from.Id] = 0 }
	local f: { [number]: number } = { [from.Id] = (from.Position - to.Position).Magnitude }
	local iterations = 0
	while openCount > 0 do
		iterations += 1
		if iterations > 6000 then
			return nil
		end
		-- Linear scan of the open set: graphs are small (low thousands of
		-- nodes) and searches are infrequent, so a heap isn't worth it here.
		local currentId: number? = nil
		local bestF = math.huge
		for id in open do
			local score = f[id]
			if score < bestF then
				bestF = score
				currentId = id
			end
		end
		local cid = currentId :: number
		if cid == to.Id then
			local path = { nodes[cid] }
			local cursor = cid
			while cameFrom[cursor] do
				cursor = cameFrom[cursor]
				table.insert(path, 1, nodes[cursor])
			end
			return path
		end
		open[cid] = nil
		openCount -= 1
		local current = nodes[cid]
		for _, link in current.Links do
			if link.Enabled then
				local neighbor = nodes[link.To]
				if not canUse or canUse(link, neighbor) then
					local tentative = g[cid] + link.Cost
					if tentative < (g[neighbor.Id] or math.huge) then
						cameFrom[neighbor.Id] = cid
						g[neighbor.Id] = tentative
						f[neighbor.Id] = tentative + (neighbor.Position - to.Position).Magnitude
						if not open[neighbor.Id] then
							open[neighbor.Id] = true
							openCount += 1
						end
					end
				end
			end
		end
	end
	return nil
end

return CaveGraph
