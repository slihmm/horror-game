--!strict
-- Natural hazards: ceilings that shed rock (with a warning crack first) and
-- plank bridges that give way under the first person to cross. Deep pits,
-- water and shafts are handled by geometry, fall damage and drowning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local Services = ServerScriptService.Server.Services
local CaveService = require(Services.CaveService)
local NoiseService = require(Services.NoiseService)
local PlayerService = require(Services.PlayerService)
local Dress = require(ServerScriptService.Server.Cave.DressContext)

type RockfallSpot = Dress.RockfallSpot

local ROCKFALL_TRIGGER_RADIUS = 7
local ROCKFALL_CHANCE = 0.35
local ROCKFALL_COOLDOWN = 600
local ROCK_DAMAGE = NumberRange.new(22, 40)
local BRIDGE_BREAK_DELAY = 0.7

local HazardService = {}
HazardService.__index = HazardService

type State = {
	_spots: { RockfallSpot },
	_spotCooldown: { [RockfallSpot]: number },
	_bridges: { { Model: Model, A: Vector3, B: Vector3, Broken: boolean } },
	_rng: Random,
	_folder: Folder?,
}
export type HazardService = typeof(setmetatable({} :: State, HazardService))

-- Broadcasts a world effect to every client within range.
function HazardService.Broadcast(self: HazardService, kind: string, position: Vector3, params: { [string]: any }, range: number)
	local remote = Net.Event("WorldEffect")
	for _, player in Players:GetPlayers() do
		local track = CaveService:GetTrack(player)
		if track and (track.Position - position).Magnitude <= range then
			remote:FireClient(player, kind, position, params)
		end
	end
end

function HazardService.Start(self: HazardService)
	CaveService:WaitUntilReady()
	local dressing = CaveService.Dressing
	if not dressing then
		return
	end
	self._spots = dressing.RockfallSpots
	for _, bridge in dressing.Bridges do
		table.insert(self._bridges, { Model = bridge.Model, A = bridge.A, B = bridge.B, Broken = false })
	end
	local folder = Instance.new("Folder")
	folder.Name = "Hazards"
	folder.Parent = Workspace:FindFirstChild(Constants.Folders.Cave) or Workspace
	self._folder = folder
	while true do
		task.wait(0.3)
		self:_tick()
	end
end

function HazardService._tick(self: HazardService)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local track = CaveService:GetTrack(player)
		if not track then
			continue
		end
		local p = track.Position
		for _, spot in self._spots do
			local flat = Vector3.new(p.X - spot.Floor.X, 0, p.Z - spot.Floor.Z).Magnitude
			if flat < ROCKFALL_TRIGGER_RADIUS and math.abs(p.Y - spot.Floor.Y) < 8 and now >= (self._spotCooldown[spot] or 0) then
				self._spotCooldown[spot] = now + ROCKFALL_COOLDOWN
				if self._rng:NextNumber() < ROCKFALL_CHANCE then
					task.spawn(function()
						self:Rockfall(spot.Ceiling, spot.Floor, 1)
					end)
				end
			end
		end
		for _, bridge in self._bridges do
			if not bridge.Broken then
				local mid = (bridge.A + bridge.B) / 2
				if (p - mid).Magnitude < 5 then
					bridge.Broken = true
					task.spawn(function()
						self:_breakBridge(bridge)
					end)
				end
			end
		end
	end
end

-- Drops rocks from a ceiling point. severity scales count and damage.
-- Also used by the Horror Director for "a rock falls somewhere nearby".
function HazardService.Rockfall(self: HazardService, ceiling: Vector3, floor: Vector3, severity: number)
	local folder = self._folder
	if not folder then
		return
	end
	self:Broadcast("Sound", ceiling, { Sound = "CaveCrack", Volume = 1, MaxDistance = 120, Shake = 0.15 * severity }, 160)
	self:Broadcast("Dust", ceiling, { Amount = severity }, 100)
	task.wait(0.8)
	local rng = self._rng
	local count = math.floor(3 + 5 * severity)
	for _ = 1, count do
		local size = rng:NextNumber(0.8, 2.4) * (0.7 + severity * 0.4)
		local rock = Instance.new("Part")
		rock.Name = "FallingRock"
		rock.Size = Vector3.new(size, size * rng:NextNumber(0.6, 0.9), size * rng:NextNumber(0.7, 1.1))
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(70, 66, 62)
		rock.CFrame = CFrame.new(ceiling + Vector3.new(rng:NextNumber(-2.5, 2.5), -size, rng:NextNumber(-2.5, 2.5))) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		rock.CollisionGroup = Constants.CollisionGroups.Effects
		rock.Parent = folder
		rock:SetNetworkOwner(nil)
		task.delay(10, function()
			rock:Destroy()
		end)
		task.wait(rng:NextNumber(0.02, 0.15))
	end
	-- Impact: damage anyone standing under it, make noise, rumble.
	local fallTime = math.sqrt(2 * math.max(1, ceiling.Y - floor.Y) / Workspace.Gravity)
	task.wait(fallTime)
	self:Broadcast("Sound", floor, { Sound = "RockFall", Volume = 1.2, MaxDistance = 180, Shake = 0.3 * severity }, 200)
	NoiseService.Emit(floor, 0.9 * severity, "Rockfall", nil)
	for _, player in Players:GetPlayers() do
		local track = CaveService:GetTrack(player)
		if track then
			local flat = Vector3.new(track.Position.X - floor.X, 0, track.Position.Z - floor.Z).Magnitude
			if flat < 3.5 and math.abs(track.Position.Y - floor.Y) < 7 then
				PlayerService:Damage(player, rng:NextNumber(ROCK_DAMAGE.Min, ROCK_DAMAGE.Max) * severity, "Rockfall")
			end
		end
	end
end

function HazardService._breakBridge(self: HazardService, bridge: { Model: Model, A: Vector3, B: Vector3, Broken: boolean })
	local mid = (bridge.A + bridge.B) / 2
	self:Broadcast("Sound", mid, { Sound = "PlankCrack", Volume = 1.2, MaxDistance = 90, Shake = 0.2 }, 120)
	task.wait(BRIDGE_BREAK_DELAY)
	-- The planks closest to the middle give way.
	local planks = {}
	for _, child in bridge.Model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Plank" then
			table.insert(planks, child)
		end
	end
	table.sort(planks, function(a: BasePart, b: BasePart)
		return (a.Position - mid).Magnitude < (b.Position - mid).Magnitude
	end)
	for i = 1, math.min(3, #planks) do
		local plank = planks[i]
		plank.Anchored = false
		plank.CanCollide = true
		plank.CollisionGroup = Constants.CollisionGroups.Effects
		plank:SetNetworkOwner(nil)
		task.delay(12, function()
			plank:Destroy()
		end)
	end
	self:Broadcast("Sound", mid, { Sound = "RockFall", Volume = 0.6, Pitch = 1.6, MaxDistance = 90 }, 120)
	NoiseService.Emit(mid, 0.8, "Bridge", nil)
end

local instance: HazardService = setmetatable({
	_spots = {},
	_spotCooldown = {},
	_bridges = {},
	_rng = Random.new(),
	_folder = nil,
} :: State, HazardService)

return instance
