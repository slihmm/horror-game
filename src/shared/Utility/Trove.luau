--!strict
-- Tracks connections, instances, threads and cleanup callbacks so that a
-- system (or a per-character lifecycle) can be torn down in one call.

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, handler: (...any) -> ()) -> RBXScriptConnection,
	Clean: (self: Trove) -> (),
}

local Trove = {}
Trove.__index = Trove

function Trove.new(): Trove
	return (setmetatable({ _items = {} }, Trove) :: any) :: Trove
end

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Trove:Add(item)
	table.insert(self._items, item)
	return item
end

function Trove:Connect(signal, handler)
	local connection = signal:Connect(handler)
	table.insert(self._items, connection)
	return connection
end

function Trove:Clean()
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		cleanItem(items[i])
	end
end

return Trove
