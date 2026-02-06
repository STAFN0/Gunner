-- =====================================================
-- STAFN0's Game Framework v2.1
-- @author STAFN0
-- Main entry point - all modules are children of this
-- =====================================================

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

-- Load all child modules
local Signal = require(script.Signal)
local Promise = require(script.Promise)
local NetworkSignal = require(script.NetworkSignal)
local NetworkFunction = require(script.NetworkFunction)
local RateLimiter = require(script.RateLimiter)
local Types = require(script.Types)

-- Re-export all types for VSCode IntelliSense
export type Signal = Types.Signal
export type Connection = Types.Connection
export type Promise = Types.Promise
export type NetworkSignal = Types.NetworkSignal
export type NetworkFunction = Types.NetworkFunction
export type Middleware = Types.Middleware
export type RateLimiter = Types.RateLimiter
export type Framework = Types.Framework
export type Service = Types.Service
export type Controller = Types.Controller
export type ServiceState = Types.ServiceState
export type DebugConfig = Types.DebugConfig

-- =====================================================
-- STAFN0's Main Framework
-- =====================================================
local Framework = {}
Framework.__index = Framework
Framework.__type = "Framework"

function Framework.new(): Types.Framework
	local self = setmetatable({}, Framework)

	-- Expose Signal and Promise
	self.Signal = Signal
	self.Promise = Promise

	-- Private state
	self._services = {} :: { [string]: Types.Service }
	self._controllers = {} :: { [string]: Types.Controller }
	self._serviceStates = {} :: { [string]: Types.ServiceState }
	self._controllerStates = {} :: { [string]: Types.ServiceState }
	self._started = false
	self._rateLimiters = {}
	self._serviceDependencies = {}
	self._shutdownHandlers = {}

	-- Debug configuration
	self._debug = {
		enabled = false,
		logLevel = "INFO", -- DEBUG, INFO, WARN, ERROR
		profileMethods = false,
		logLifecycle = true,
	} :: Types.DebugConfig

	-- Network folder
	local networkFolder = ReplicatedStorage:FindFirstChild("STAFN0-NETWORK")
	if not networkFolder then
		networkFolder = Instance.new("Folder")
		networkFolder.Name = "STAFN0-NETWORK"
		networkFolder.Parent = ReplicatedStorage
	end
	self._networkFolder = networkFolder

	-- Lifecycle signals
	self.Signals = {
		ServiceRegistered = Signal.new(),
		ServiceInitialized = Signal.new(),
		ServiceStarted = Signal.new(),
		ServiceFailed = Signal.new(),
		ControllerRegistered = Signal.new(),
		ControllerInitialized = Signal.new(),
		ControllerStarted = Signal.new(),
		ControllerFailed = Signal.new(),
		Error = Signal.new(),
		Shutdown = Signal.new(),
	}

	-- Cleanup rate limiters when players leave
	if IsServer then
		local Players = game:GetService("Players")
		Players.PlayerRemoving:Connect(function(player)
			for _, limiter in pairs(self._rateLimiters) do
				limiter:Cleanup(player)
			end
		end)
	end

	return self :: any
end

-- ======= DEBUG/LOGGING =======
function Framework:SetDebug(config: Types.DebugConfig)
	for k, v in pairs(config) do
		self._debug[k] = v
	end
end

function Framework:Log(level: string, message: string, ...)
	if not self._debug.enabled then
		return
	end

	local levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
	local currentLevel = levels[self._debug.logLevel] or 2
	local msgLevel = levels[level] or 2

	if msgLevel >= currentLevel then
		local formatted = string.format(message, ...)
		print(string.format("[STAFN0:%s] %s", level, formatted))
	end
end

-- ======= REGISTRATION =======
function Framework:RegisterService(moduleOrTable: any, name: string?): Types.Service
	assert(IsServer, "services are server only")

	local service = self:_loadModule(moduleOrTable, name) :: Types.Service
	if not service then
		error("Failed to load service module")
	end

	name = name or service.Name
	assert(type(name) == "string", "service needs a name")

	if self._services[name] then
		error(string.format("[STAFN0] service '%s' already registered", name))
	end

	service.Framework = self
	self._services[name] = service
	self._serviceStates[name] = "Uninitialized"

	-- Handle dependencies
	if service.Dependencies then
		if type(service.Dependencies) == "table" then
			if service.Dependencies.required or service.Dependencies.optional then
				-- New format
				self._serviceDependencies[name] = service.Dependencies
			else
				-- Old format (flat array) - convert to new format
				self._serviceDependencies[name] = {
					required = service.Dependencies,
					optional = {},
				}
			end
		end
	end

	self.Signals.ServiceRegistered:Fire(name, service)
	self:Log("INFO", "Registered service: %s", name)

	return service
end

function Framework:RegisterController(moduleOrTable: any, name: string?): Types.Controller
	assert(IsClient, "controllers are client only")

	local controller = self:_loadModule(moduleOrTable, name) :: Types.Controller
	if not controller then
		error("Failed to load controller module")
	end

	name = name or controller.Name
	assert(type(name) == "string", "controller needs a name")

	if self._controllers[name] then
		error(string.format("[STAFN0] controller '%s' already registered", name))
	end

	controller.Framework = self
	self._controllers[name] = controller
	self._controllerStates[name] = "Uninitialized"

	self.Signals.ControllerRegistered:Fire(name, controller)
	self:Log("INFO", "Registered controller: %s", name)

	return controller
end

function Framework:_loadModule(moduleOrTable: any, _: string?): any
	if typeof(moduleOrTable) == "Instance" and moduleOrTable:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleOrTable)
		if not ok then
			warn("[STAFN0] failed to require module:", result)
			return nil
		end
		return result
	elseif type(moduleOrTable) == "table" then
		return moduleOrTable
	end
	error("[STAFN0] expected ModuleScript or table")
end

-- ======= SERVICE/CONTROLLER ACCESS =======
function Framework:GetService(name: string): Types.Service?
	if not self._started then
		self:Log("WARN", "GetService called before framework started: %s", name)
	end
	return self._services[name]
end

function Framework:GetController(name: string): Types.Controller?
	if not self._started then
		self:Log("WARN", "GetController called before framework started: %s", name)
	end
	return self._controllers[name]
end

function Framework:GetServiceState(name: string): Types.ServiceState?
	return self._serviceStates[name]
end

function Framework:GetControllerState(name: string): Types.ServiceState?
	return self._controllerStates[name]
end

function Framework:WaitForService(name: string, timeout: number?): Types.Service?
	if self._services[name] then
		return self._services[name]
	end

	local timeoutPromise = timeout
			and Promise.new(function(resolve)
				task.delay(timeout, function()
					resolve(nil)
				end)
			end)
		or nil

	local servicePromise = Promise.new(function(resolve)
		local conn
		conn = self.Signals.ServiceRegistered:Connect(function(serviceName, service)
			if serviceName == name then
				conn:Disconnect()
				resolve(service)
			end
		end)

		if self._services[name] then
			conn:Disconnect()
			resolve(self._services[name])
		end
	end)

	if timeoutPromise then
		local _, result = Promise.Race({ servicePromise, timeoutPromise }):Await()
		return result
	else
		local _, result = servicePromise:Await()
		return result
	end
end

function Framework:WaitForController(name: string, timeout: number?): Types.Controller?
	if self._controllers[name] then
		return self._controllers[name]
	end

	local timeoutPromise = timeout
			and Promise.new(function(resolve)
				task.delay(timeout, function()
					resolve(nil)
				end)
			end)
		or nil

	local controllerPromise = Promise.new(function(resolve)
		local conn
		conn = self.Signals.ControllerRegistered:Connect(function(controllerName, controller)
			if controllerName == name then
				conn:Disconnect()
				resolve(controller)
			end
		end)

		if self._controllers[name] then
			conn:Disconnect()
			resolve(self._controllers[name])
		end
	end)

	if timeoutPromise then
		local _, result = Promise.Race({ controllerPromise, timeoutPromise }):Await()
		return result
	else
		local _, result = controllerPromise:Await()
		return result
	end
end

-- ======= NETWORK CREATION =======
function Framework:CreateSignal(service: Types.Service | Types.Controller, signalName: string): Types.NetworkSignal
	local serviceName = service.Name or "UnknownService"
	return NetworkSignal.new(serviceName, signalName, self._networkFolder)
end

function Framework:CreateFunction(
	service: Types.Service | Types.Controller,
	functionName: string
): Types.NetworkFunction
	local serviceName = service.Name or "UnknownService"
	return NetworkFunction.new(serviceName, functionName, self._networkFolder)
end

function Framework:CreateRateLimiter(maxRequests: number, windowSeconds: number): Types.RateLimiter
	local limiter = RateLimiter.new(maxRequests, windowSeconds)
	table.insert(self._rateLimiters, limiter)
	return limiter
end

-- ======= LIFECYCLE =======
function Framework:Start(): boolean
	if self._started then
		self:Log("WARN", "Framework already started")
		return false
	end

	self._started = true
	self:Log("INFO", "Starting framework...")

	if IsServer then
		local missingDeps = self:_checkDependencies(self._services, self._serviceDependencies)
		if #missingDeps > 0 then
			self:Log("ERROR", "Missing service dependencies:")
			for _, dep in ipairs(missingDeps) do
				self:Log("ERROR", "  %s", dep.chain)
			end
			error("[STAFN0] Cannot start with missing required dependencies")
		end
	end

	local function safeInit(collection, stateCollection, name, module, initSignal, failSignal, errorPrefix)
		stateCollection[name] = "Initializing"

		local startTime = os.clock()
		local success, err = pcall(function()
			if type(module.OnInit) == "function" then
				module:OnInit()
			end
		end)
		local duration = os.clock() - startTime

		if success then
			stateCollection[name] = "Initialized"
			initSignal:Fire(name, module)
			if self._debug.profileMethods then
				self:Log("DEBUG", "%s.OnInit took %.3fms", name, duration * 1000)
			end
			return true
		else
			stateCollection[name] = "Failed"
			self:Log("ERROR", "%s failed for %s: %s", errorPrefix, name, err)
			failSignal:Fire(name, module, err)
			self.Signals.Error:Fire(errorPrefix, name, err)
			collection[name] = nil
			return false
		end
	end

	local function safeStart(stateCollection, name, module, startSignal, failSignal, errorPrefix)
		stateCollection[name] = "Starting"

		local startTime = os.clock()
		local success, err = pcall(function()
			if type(module.OnStart) == "function" then
				module:OnStart()
			end
		end)
		local duration = os.clock() - startTime

		if success then
			stateCollection[name] = "Started"
			startSignal:Fire(name, module)
			if self._debug.profileMethods then
				self:Log("DEBUG", "%s.OnStart took %.3fms", name, duration * 1000)
			end
			return true
		else
			stateCollection[name] = "Failed"
			self:Log("ERROR", "%s failed for %s: %s", errorPrefix, name, err)
			failSignal:Fire(name, module, err)
			self.Signals.Error:Fire(errorPrefix, name, err)
			return false
		end
	end

	if IsServer then
		local initCount = 0
		for name, service in pairs(self._services) do
			if
				safeInit(
					self._services,
					self._serviceStates,
					name,
					service,
					self.Signals.ServiceInitialized,
					self.Signals.ServiceFailed,
					"ServiceInit"
				)
			then
				initCount += 1
			end
		end

		local successCount = 0
		local totalCount = 0
		for name, service in pairs(self._services) do
			totalCount += 1
			if
				safeStart(
					self._serviceStates,
					name,
					service,
					self.Signals.ServiceStarted,
					self.Signals.ServiceFailed,
					"ServiceStart"
				)
			then
				successCount += 1
			end
		end

		if self._debug.logLifecycle then
			self:Log("INFO", "✓ %d/%d services initialized", initCount, totalCount)
			self:Log("INFO", "✓ %d/%d services started", successCount, totalCount)
		end
	else
		local initCount = 0
		for name, controller in pairs(self._controllers) do
			if
				safeInit(
					self._controllers,
					self._controllerStates,
					name,
					controller,
					self.Signals.ControllerInitialized,
					self.Signals.ControllerFailed,
					"ControllerInit"
				)
			then
				initCount += 1
			end
		end

		local successCount = 0
		local totalCount = 0
		for name, controller in pairs(self._controllers) do
			totalCount += 1
			if
				safeStart(
					self._controllerStates,
					name,
					controller,
					self.Signals.ControllerStarted,
					self.Signals.ControllerFailed,
					"ControllerStart"
				)
			then
				successCount += 1
			end
		end

		if self._debug.logLifecycle then
			self:Log("INFO", "✓ %d/%d controllers initialized", initCount, totalCount)
			self:Log("INFO", "✓ %d/%d controllers started", successCount, totalCount)
		end
	end

	return true
end

function Framework:_checkDependencies(collection, dependencyMap)
	local missing = {}
	local visiting = {}
	local visited = {}

	local function checkCircular(serviceName, chain)
		if visiting[serviceName] then
			local cycleStart = table.find(chain, serviceName)
			local cycle = {}
			for i = cycleStart, #chain do
				table.insert(cycle, chain[i])
			end
			table.insert(cycle, serviceName)
			return true, table.concat(cycle, " -> ")
		end

		if visited[serviceName] then
			return false, nil
		end

		visiting[serviceName] = true
		table.insert(chain, serviceName)

		local deps = dependencyMap[serviceName]
		if deps then
			local requiredDeps = deps.required or deps

			for _, depName in ipairs(requiredDeps) do
				if not collection[depName] then
					table.insert(missing, {
						service = serviceName,
						missing = depName,
						chain = table.concat(chain, " -> ") .. " -> " .. depName,
					})
				else
					local hasCircular, cyclePath = checkCircular(depName, chain)
					if hasCircular then
						error(string.format("[STAFN0] Circular dependency detected: %s", cyclePath))
					end
				end
			end
		end

		table.remove(chain)
		visiting[serviceName] = nil
		visited[serviceName] = true

		return false, nil
	end

	for serviceName, _ in pairs(dependencyMap) do
		local chain = {}
		checkCircular(serviceName, chain)
	end

	return missing
end

-- ======= GRACEFUL SHUTDOWN =======
function Framework:RegisterShutdownHandler(name: string, handler: () -> ())
	assert(type(handler) == "function", "shutdown handler must be a function")
	self._shutdownHandlers[name] = handler
end

function Framework:Shutdown()
	self:Log("INFO", "Beginning graceful shutdown...")
	self.Signals.Shutdown:Fire()

	-- Run custom shutdown handlers
	for name, handler in pairs(self._shutdownHandlers) do
		local ok, err = pcall(handler)
		if not ok then
			self:Log("ERROR", "Shutdown handler '%s' failed: %s", name, err)
		end
	end

	-- Stop services/controllers in reverse order
	if IsServer then
		local serviceNames = {}
		for name, _ in pairs(self._services) do
			table.insert(serviceNames, name)
		end

		for i = #serviceNames, 1, -1 do
			local name = serviceNames[i]
			self:UnregisterService(name)
		end
	else
		local controllerNames = {}
		for name, _ in pairs(self._controllers) do
			table.insert(controllerNames, name)
		end

		for i = #controllerNames, 1, -1 do
			local name = controllerNames[i]
			self:UnregisterController(name)
		end
	end

	self:Log("INFO", "Shutdown complete")
end

-- ======= CLEANUP =======
function Framework:UnregisterService(name: string)
	assert(IsServer, "UnregisterService is server only")
	local service = self._services[name]
	if not service then
		return
	end

	if type(service.OnDestroy) == "function" then
		local ok, err = pcall(service.OnDestroy, service)
		if not ok then
			self:Log("ERROR", "OnDestroy error in %s: %s", name, err)
		end
	end

	self._services[name] = nil
	self._serviceStates[name] = nil
	self:Log("INFO", "Unregistered service: %s", name)
end

function Framework:UnregisterController(name: string)
	assert(IsClient, "UnregisterController is client only")
	local controller = self._controllers[name]
	if not controller then
		return
	end

	if type(controller.OnDestroy) == "function" then
		local ok, err = pcall(controller.OnDestroy, controller)
		if not ok then
			self:Log("ERROR", "OnDestroy error in %s: %s", name, err)
		end
	end

	self._controllers[name] = nil
	self._controllerStates[name] = nil
	self:Log("INFO", "Unregistered controller: %s", name)
end

-- ======= UTILITY =======
function Framework:RegisterFromFolder(folder: Folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, module = pcall(require, child)
			if ok and type(module) == "table" then
				if module.Type == "Service" then
					self:RegisterService(module, module.Name or child.Name)
				elseif module.Type == "Controller" then
					self:RegisterController(module, module.Name or child.Name)
				end
			end
		end
	end
end

function Framework:Destroy()
	self:Shutdown()

	for _, signal in pairs(self.Signals) do
		signal:DisconnectAll()
	end

	table.clear(self._rateLimiters)

	if self._networkFolder then
		self._networkFolder:ClearAllChildren()
	end

	self:Log("INFO", "Framework destroyed")
end

-- ======= EXPORT =======
local singleton = Framework.new()
return singleton
