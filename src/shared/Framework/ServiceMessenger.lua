local Signal = require(script.Parent.Signal)
local Types = require(script.Parent.Types)

export type ServiceMessenger = {
	Subscribe: (self: ServiceMessenger, eventName: string, callback: (...any) -> ()) -> Types.Connection,
	Publish: (self: ServiceMessenger, eventName: string, ...any) -> (),
	Request: (self: ServiceMessenger, serviceName: string, methodName: string, ...any) -> ...any,
	PublishAsync: (self: ServiceMessenger, eventName: string, ...any) -> (),
	GetStats: (
		self: ServiceMessenger
	) -> { totalPublished: number, totalSubscribers: number, eventCounts: { [string]: number } },
	Clear: (self: ServiceMessenger) -> (),
}

local ServiceMessenger = {}
ServiceMessenger.__index = ServiceMessenger
ServiceMessenger.__type = "ServiceMessenger"

function ServiceMessenger.new(framework): ServiceMessenger
	local self = setmetatable({
		_framework = framework,
		_events = {},
		_stats = {
			totalPublished = 0,
			eventCounts = {},
		},
	}, ServiceMessenger)

	return self :: any
end

function ServiceMessenger:Subscribe(eventName: string, callback: (...any) -> ()): Types.Connection
	assert(type(eventName) == "string", "eventName must be a string")
	assert(type(callback) == "function", "callback must be a function")

	if not self._events[eventName] then
		self._events[eventName] = Signal.new()
		self._stats.eventCounts[eventName] = 0
	end

	return self._events[eventName]:Connect(callback)
end

function ServiceMessenger:Publish(eventName: string, ...: any)
	assert(type(eventName) == "string", "eventName must be a string")

	if not self._events[eventName] then
		return
	end

	self._stats.totalPublished += 1
	self._stats.eventCounts[eventName] = (self._stats.eventCounts[eventName] or 0) + 1

	self._events[eventName]:Fire(...)
end

function ServiceMessenger:PublishAsync(eventName: string, ...: any)
	assert(type(eventName) == "string", "eventName must be a string")

	local args = { ... }
	task.spawn(function()
		self:Publish(eventName, table.unpack(args))
	end)
end

function ServiceMessenger:Request(serviceName: string, methodName: string, ...: any): ...any
	assert(type(serviceName) == "string", "serviceName must be a string")
	assert(type(methodName) == "string", "methodName must be a string")

	local service = self._framework:GetService(serviceName)
	if not service then
		error(string.format("Service '%s' not found", serviceName))
	end

	local method = service[methodName]
	if not method or type(method) ~= "function" then
		error(string.format("Method '%s' not found on service '%s'", methodName, serviceName))
	end

	return method(service, ...)
end

function ServiceMessenger:GetStats(): {
	totalPublished: number,
	totalSubscribers: number,
	eventCounts: { [string]: number },
}
	local totalSubscribers = 0
	for _, signal in pairs(self._events) do
		local count = 0
		for _ in pairs(signal._cons) do
			count += 1
		end
		totalSubscribers += count
	end

	return {
		totalPublished = self._stats.totalPublished,
		totalSubscribers = totalSubscribers,
		eventCounts = self._stats.eventCounts,
	}
end

function ServiceMessenger:Clear()
	for _, signal in pairs(self._events) do
		signal:DisconnectAll()
	end
	table.clear(self._events)
	self._stats.totalPublished = 0
	table.clear(self._stats.eventCounts)
end

return ServiceMessenger
