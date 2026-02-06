-- =====================================================
-- STAFN0's Signal Implementation
-- Better than Roblox events with proper cleanup
-- =====================================================
local Types = require(script.Parent.Types)

export type Connection = Types.Connection
export type Signal = Types.Signal

local Signal = {}
Signal.__index = Signal
Signal.__type = "Signal"

function Signal.new(): Signal
	return setmetatable({
		_cons = {},
		_firing = false,
		_toAdd = {},
		_toRemove = {},
		_errorHandler = nil,
	}, Signal) :: any
end

function Signal:Connect(fn: (...any) -> ()): Connection
	assert(type(fn) == "function", "Connect requires a function")

	local connection = {
		fn = fn,
		connected = true,
	}

	if self._firing then
		table.insert(self._toAdd, connection)
	else
		table.insert(self._cons, connection)
	end

	local connObj = {
		Connected = true,
		_connection = connection,
		_parent = self,
	}

	connObj.Disconnect = function(self2)
		if not self2.Connected then
			return
		end
		self2.Connected = false
		self2._connection.connected = false

		local parent = self2._parent

		if parent._firing then
			table.insert(parent._toRemove, self2._connection)
		else
			for i, con in ipairs(parent._cons) do
				if con == self2._connection then
					table.remove(parent._cons, i)
					break
				end
			end
		end
	end

	return connObj
end

function Signal:Once(fn: (...any) -> ()): Connection
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...: any)
	self._firing = true
	local args = { ... }

	for i = #self._cons, 1, -1 do
		local con = self._cons[i]
		if con.connected then
			local ok, err = pcall(con.fn, table.unpack(args))
			if not ok then
				warn("[Signal] callback error:", err)
				if self._errorHandler then
					task.spawn(self._errorHandler, err, con.fn)
				end
			end
		end
	end

	self._firing = false

	if #self._toAdd > 0 then
		for _, con in ipairs(self._toAdd) do
			table.insert(self._cons, con)
		end
		table.clear(self._toAdd)
	end

	if #self._toRemove > 0 then
		local toRemoveSet = {}
		for _, con in ipairs(self._toRemove) do
			toRemoveSet[con] = true
		end

		local newCons = {}
		for _, con in ipairs(self._cons) do
			if not toRemoveSet[con] then
				table.insert(newCons, con)
			end
		end
		self._cons = newCons
		table.clear(self._toRemove)
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:SetErrorHandler(handler: (error: any, callback: (...any) -> ()) -> ())
	assert(type(handler) == "function", "error handler must be a function")
	self._errorHandler = handler
end

function Signal:DisconnectAll()
	table.clear(self._cons)
	table.clear(self._toAdd)
	table.clear(self._toRemove)
end

return Signal
