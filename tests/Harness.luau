--!nocheck
-- Offline test harness (Lune). Loads the Rojo-built place file and executes
-- ModuleScripts with a custom `require`, so pure server logic (cave planner,
-- graph, AI decision code) can be exercised without Roblox Studio.
--
-- Only systems that don't touch live engine services can run here; the
-- harness provides Roblox datatypes via @lune/roblox plus small polyfills.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

-- Deterministic stand-in for Roblox's Random (xorshift; not bit-identical).
local RandomClass = {}
RandomClass.__index = RandomClass
function RandomClass.new(seed)
	seed = math.floor(seed or os.clock() * 1e6) % 2147483647
	if seed == 0 then
		seed = 1
	end
	return setmetatable({ _s = seed }, RandomClass)
end
function RandomClass:_next()
	local x = self._s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._s = x
	return x / 4294967296
end
function RandomClass:NextNumber(min, max)
	local r = self:_next()
	if min == nil then
		return r
	end
	return min + (max - min) * r
end
function RandomClass:NextInteger(min, max)
	return math.floor(min + (max - min + 1) * self:_next())
end

-- opts.Setup(game) may return { Services = {...}, Globals = {...} } to stub
-- engine services and add globals (see WorldSim).
function Harness.load(placePath, opts)
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local extra = if opts and opts.Setup then opts.Setup(game) else {}
	local serviceOverrides = extra.Services or {}
	local extraGlobals = extra.Globals or {}
	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		local child = self:FindFirstChild(name)
		assert(child, `WaitForChild: {self:GetFullName()} has no child '{name}'`)
		return child
	end)
	roblox.implementMethod("DataModel", "GetService", function(self, name)
		if serviceOverrides[name] then
			return serviceOverrides[name]
		end
		local service = self:FindFirstChildOfClass(name)
		if service then
			return service
		end
		error(`Service '{name}' is not available in the offline harness`)
	end)

	-- Lune implements GetService natively, so overrides go through a proxy.
	local gameProxy = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					return serviceOverrides[name] or game:GetService(name)
				end
			end
			local value = game[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(game, ...)
				end
			end
			return value
		end,
	})
	local cache = {}
	local function requireModule(module)
		if cache[module] ~= nil then
			return cache[module]
		end
		assert(module.ClassName == "ModuleScript", `require: {module:GetFullName()} is not a ModuleScript`)
		local source = module.Source
		-- Lune copies the environment table, so globals are populated eagerly.
		local env = {
			game = gameProxy,
			workspace = game:FindFirstChildOfClass("Workspace"),
			script = module,
			require = requireModule,
			Random = RandomClass,
			task = task,
		}
		for key, value in roblox do
			if env[key] == nil then
				env[key] = value
			end
		end
		for key, value in extraGlobals do
			env[key] = value
		end
		local fn = luau.load(source, { debugName = module:GetFullName(), environment = env })
		local result = fn()
		cache[module] = result
		return result
	end

	return {
		Game = game,
		Random = RandomClass,
		Require = requireModule,
		Find = function(path)
			local current = game
			for part in string.gmatch(path, "[^%.]+") do
				current = current:FindFirstChild(part)
				assert(current, `Find: missing '{part}' in '{path}'`)
			end
			return current
		end,
	}
end

return Harness
