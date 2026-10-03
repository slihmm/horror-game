--!strict
-- Server entry point. Services are plain ModuleScripts with optional
-- Init (wire-up, no yielding on other services) and Start (run) phases.
-- The order below is the dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Services = script.Parent:WaitForChild("Services")

-- Remotes exist before any service wires handlers or clients look for them.
Net.Setup()

local ORDER = {
	"NoiseService",
	"DataService",
	"CaveService",
	"PlayerService",
	"HeadlampService",
	"TraversalService",
	"ExpeditionService",
	"StatisticsService",
	"LeaderboardService",
	"LoreService",
	"LootService",
	"HazardService",
	"DisorientationService",
	"MonsterService",
	"HorrorDirector",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `Missing service module {name}`)
	loaded[name] = (require :: any)(module)
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Init) == "function" then
		service:Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Start) == "function" then
		task.spawn(function()
			service:Start()
		end)
	end
end
