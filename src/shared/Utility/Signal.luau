--!strict
-- Minimal synchronous signal used for in-process communication between
-- services/controllers. Handlers run in their own thread so a yielding or
-- erroring handler never blocks the emitter.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { [any]: (T...) -> () } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(handler)
	local key = {}
	self._handlers[key] = handler
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		conn.Connected = false
		self._handlers[key] = nil
	end
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
