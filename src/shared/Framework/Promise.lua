-- =====================================================
-- STAFN0's Promise Implementation
-- Based on JavaScript Promise API
-- =====================================================

local Types = require(script.Parent.Types)

export type Promise = Types.Promise

local Promise = {}
Promise.__index = Promise
Promise.__type = "Promise"

function Promise.new(
	executor: (resolve: (any) -> (), reject: (any) -> (), onCancel: ((fn: () -> ()) -> ())?) -> ()
): Promise
	local self = setmetatable({
		_status = "pending",
		_value = nil,
		_handlers = {},
		_cancelled = false,
		_cancelCallbacks = {},
	}, Promise)

	local function onCancel(callback)
		if self._cancelled then
			task.spawn(callback)
		else
			table.insert(self._cancelCallbacks, callback)
		end
	end

	local function resolve(val)
		if self._status ~= "pending" or self._cancelled then
			return
		end
		self._status = "fulfilled"
		self._value = val
		for _, handler in ipairs(self._handlers) do
			task.spawn(handler.onFulfilled, val)
		end
		self._handlers = nil
	end

	local function reject(err)
		if self._status ~= "pending" or self._cancelled then
			return
		end
		self._status = "rejected"
		self._value = err
		for _, handler in ipairs(self._handlers) do
			if handler.onRejected then
				task.spawn(handler.onRejected, err)
			end
		end
		self._handlers = nil
	end

	task.spawn(function()
		local ok, err = pcall(executor, resolve, reject, onCancel)
		if not ok then
			reject(err)
		end
	end)

	return self :: any
end

function Promise:Then(onResolved, onRejected)
	return Promise.new(function(resolve, reject)
		local function handleResolved(val)
			if not onResolved then
				resolve(val)
				return
			end

			local ok, result = pcall(onResolved, val)
			if ok then
				if type(result) == "table" and getmetatable(result) == Promise then
					result:Then(resolve, reject)
				else
					resolve(result)
				end
			else
				reject(result)
			end
		end

		local function handleRejected(err)
			if not onRejected then
				reject(err)
				return
			end

			local ok, result = pcall(onRejected, err)
			if ok then
				resolve(result)
			else
				reject(result)
			end
		end

		if self._status == "fulfilled" then
			task.spawn(handleResolved, self._value)
		elseif self._status == "rejected" then
			task.spawn(handleRejected, self._value)
		elseif self._handlers then
			table.insert(self._handlers, {
				onFulfilled = handleResolved,
				onRejected = handleRejected,
			})
		end
	end)
end

function Promise:Catch(onRejected)
	return self:Then(nil, onRejected)
end

function Promise:Finally(onFinally)
	return self:Then(function(val)
		onFinally()
		return val
	end, function(err)
		onFinally()
		error(err)
	end)
end

function Promise:Cancel()
	if self._status ~= "pending" then
		return
	end

	self._cancelled = true
	self._status = "rejected"
	self._value = "Promise was cancelled"

	for _, callback in ipairs(self._cancelCallbacks) do
		task.spawn(callback)
	end

	table.clear(self._cancelCallbacks)
	if self._handlers then
		table.clear(self._handlers)
		self._handlers = nil
	end
end

function Promise:Await()
	if self._status == "fulfilled" then
		return true, self._value
	elseif self._status == "rejected" then
		return false, self._value
	end

	local thread = coroutine.running()
	self:Then(function(val)
		task.spawn(thread, true, val)
	end, function(err)
		task.spawn(thread, false, err)
	end)
	return coroutine.yield()
end

function Promise.Resolve(val)
	return Promise.new(function(resolve)
		resolve(val)
	end)
end

function Promise.Reject(err)
	return Promise.new(function(_, reject)
		reject(err)
	end)
end

function Promise.All(promises)
	return Promise.new(function(resolve, reject)
		if #promises == 0 then
			resolve({})
			return
		end

		local results = {}
		local completed = 0
		local rejected = false

		for i, promise in ipairs(promises) do
			promise:Then(function(val)
				if rejected then
					return
				end
				results[i] = val
				completed += 1
				if completed == #promises then
					resolve(results)
				end
			end, function(err)
				if not rejected then
					rejected = true
					reject(err)
				end
			end)
		end
	end)
end

function Promise.Race(promises)
	return Promise.new(function(resolve, reject)
		for _, promise in ipairs(promises) do
			promise:Then(resolve, reject)
		end
	end)
end

return Promise
