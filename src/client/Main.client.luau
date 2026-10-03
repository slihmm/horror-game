--!strict
-- Client entry point. Controllers follow the same Init/Start lifecycle as
-- server services, in dependency order.

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"AudioController",
	"UIController",
	"CameraController",
	"MovementController",
	"HeadlampController",
	"LightingController",
	"FootstepController",
	"InteractionController",
	"TraversalController",
	"CinematicController",
	"RecursionController",
	"HorrorController",
	"MonsterPresenceController",
	"MenuController",
}

local loaded = {}
for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	assert(module:IsA("ModuleScript"), `Controller {name} is not a ModuleScript`)
	loaded[name] = (require :: any)(module)
end
for _, name in ORDER do
	local controller = loaded[name]
	if type(controller.Init) == "function" then
		controller:Init()
	end
end
for _, name in ORDER do
	local controller = loaded[name]
	if type(controller.Start) == "function" then
		task.spawn(function()
			controller:Start()
		end)
	end
end
