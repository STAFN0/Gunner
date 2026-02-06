local Signal = require(script.Parent.Signal)

export type MockService = {
	Name: string,
	[any]: any,
}

export type SpyFunction = {
	calls: { { args: { any }, returned: any, errored: boolean } },
	callCount: number,
	lastCall: { args: { any }, returned: any }?,
	wasCalled: boolean,
	wasCalledWith: (...any) -> boolean,
	reset: () -> (),
}

export type TestUtilities = {
	CreateMockService: (name: string, methods: { [string]: (...any) -> any }?) -> MockService,
	CreateSpy: (implementation: ((...any) -> any)?) -> SpyFunction & ((...any) -> any),
	CreateMockFramework: () -> any,
	CreateMockPlayer: (name: string?, userId: number?) -> Player,
	AssertCalled: (spy: SpyFunction, times: number?) -> (),
	AssertCalledWith: (spy: SpyFunction, ...any) -> (),
	AssertNotCalled: (spy: SpyFunction) -> (),
}

local TestUtilities = {}

function TestUtilities.CreateMockService(name: string, methods: { [string]: (...any) -> any }?): MockService
	local mock = {
		Name = name,
		Type = "Service",
		Framework = nil,
	}

	if methods then
		for methodName, implementation in pairs(methods) do
			mock[methodName] = implementation
		end
	end

	return mock
end

function TestUtilities.CreateSpy(implementation: ((...any) -> any)?): SpyFunction & ((...any) -> any)
	local spy = {
		calls = {},
		callCount = 0,
		lastCall = nil,
		wasCalled = false,
	}

	local mt = {}

	mt.__call = function(_, ...)
		spy.callCount += 1
		spy.wasCalled = true

		local args = { ... }
		local callRecord = {
			args = args,
			returned = nil,
			errored = false,
		}

		if implementation then
			local ok, result = pcall(implementation, ...)
			if ok then
				callRecord.returned = result
			else
				callRecord.errored = true
				callRecord.returned = result
			end
		end

		table.insert(spy.calls, callRecord)
		spy.lastCall = callRecord

		if callRecord.errored then
			error(callRecord.returned)
		end

		return callRecord.returned
	end

	function spy.wasCalledWith(...): boolean
		local searchArgs = { ... }

		for _, call in ipairs(spy.calls) do
			local match = true
			for i, arg in ipairs(searchArgs) do
				if call.args[i] ~= arg then
					match = false
					break
				end
			end
			if match then
				return true
			end
		end

		return false
	end

	function spy.reset()
		table.clear(spy.calls)
		spy.callCount = 0
		spy.lastCall = nil
		spy.wasCalled = false
	end

	return setmetatable(spy, mt) :: any
end

function TestUtilities.CreateMockFramework()
	local services = {}
	local controllers = {}

	return {
		Signal = Signal,
		_services = services,
		_controllers = controllers,

		RegisterService = function(_, service)
			services[service.Name] = service
			return service
		end,

		RegisterController = function(_, controller)
			controllers[controller.Name] = controller
			return controller
		end,

		GetService = function(_, name)
			return services[name]
		end,

		GetController = function(_, name)
			return controllers[name]
		end,

		Start = function()
			for _, service in pairs(services) do
				if type(service.OnInit) == "function" then
					service:OnInit()
				end
			end

			for _, service in pairs(services) do
				if type(service.OnStart) == "function" then
					service:OnStart()
				end
			end

			for _, controller in pairs(controllers) do
				if type(controller.OnInit) == "function" then
					controller:OnInit()
				end
			end

			for _, controller in pairs(controllers) do
				if type(controller.OnStart) == "function" then
					controller:OnStart()
				end
			end

			return true
		end,

		CreateSignal = function()
			return Signal.new()
		end,
	}
end

function TestUtilities.CreateMockPlayer(name: string?, userId: number?): Player
	local mockPlayer = {
		Name = name or "MockPlayer",
		UserId = userId or math.random(1, 1000000),
		ClassName = "Player",
	}

	local mt = {
		__index = function(_, key)
			return mockPlayer[key]
		end,
		__tostring = function()
			return mockPlayer.Name
		end,
	}

	return setmetatable({}, mt) :: any
end

function TestUtilities.AssertCalled(spy: SpyFunction, times: number?)
	if times then
		if spy.callCount ~= times then
			error(string.format("Expected spy to be called %d times, but was called %d times", times, spy.callCount))
		end
	else
		if not spy.wasCalled then
			error("Expected spy to be called at least once, but it was never called")
		end
	end
end

function TestUtilities.AssertCalledWith(spy: SpyFunction, ...: any)
	if not spy.wasCalledWith(...) then
		local args = { ... }
		local argsStr = table.concat(args, ", ")
		error(string.format("Expected spy to be called with (%s)", argsStr))
	end
end

function TestUtilities.AssertNotCalled(spy: SpyFunction)
	if spy.wasCalled then
		error(string.format("Expected spy to not be called, but it was called %d times", spy.callCount))
	end
end

return TestUtilities
