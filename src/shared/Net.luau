--!strict
-- Central registry of every remote in the game. The server creates them once
-- at boot; clients wait for them. Adding a remote means adding one line here,
-- which keeps the network surface small and auditable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local DEFINITIONS: { [string]: "RemoteEvent" | "UnreliableRemoteEvent" } = {
	-- client -> server
	LookPitch = "UnreliableRemoteEvent", -- (pitch: number)
	SetStance = "RemoteEvent", -- (stance: string)
	ToggleHeadlamp = "RemoteEvent", -- ()
	Traversal = "RemoteEvent", -- (action: string, ...)
	UpdateSetting = "RemoteEvent", -- (key: string, value: any)
	CinematicFinished = "RemoteEvent", -- (cinematicId: string)
	-- server -> client
	HorrorEvent = "RemoteEvent", -- (eventName: string, params: table)
	WorldEffect = "RemoteEvent", -- (kind: string, position: Vector3, params: table)
	LoreReveal = "RemoteEvent", -- (loreId: string, firstTime: boolean)
	Notify = "RemoteEvent", -- (kind: string, text: string)
	Cinematic = "RemoteEvent", -- (cinematicId: string, params: table)
	ProfileSync = "RemoteEvent", -- (snapshot: table)
}

local folder: Folder? = nil

local function getFolder(): Folder
	local cached = folder
	if cached then
		return cached
	end
	local resolved: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			resolved = existing
		else
			resolved = Instance.new("Folder")
			resolved.Name = "Remotes"
			resolved.Parent = ReplicatedStorage
		end
	else
		resolved = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	folder = resolved
	return resolved
end

-- Server only: creates every remote. Safe to call more than once.
function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server-only")
	local parent = getFolder()
	for name, className in DEFINITIONS do
		if not parent:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = parent
		end
	end
end

local function get(name: string): Instance
	assert(DEFINITIONS[name], `Unknown remote '{name}'`)
	local parent = getFolder()
	if RunService:IsServer() then
		local remote = parent:FindFirstChild(name)
		assert(remote, `Remote '{name}' missing; call Net.Setup first`)
		return remote
	end
	return parent:WaitForChild(name)
end

function Net.Event(name: string): RemoteEvent
	assert(DEFINITIONS[name] == "RemoteEvent", `'{name}' is not a RemoteEvent`)
	return get(name) :: RemoteEvent
end

function Net.Unreliable(name: string): UnreliableRemoteEvent
	assert(DEFINITIONS[name] == "UnreliableRemoteEvent", `'{name}' is not an UnreliableRemoteEvent`)
	return get(name) :: UnreliableRemoteEvent
end

return Net
