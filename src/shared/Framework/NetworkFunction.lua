-- =====================================================
-- STAFN0's NetworkFunction
-- Request/response pattern with Promise support
-- =====================================================

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Promise = require(script.Parent.Promise)
local Types = require(script.Parent.Types)

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

export type Middleware = Types.Middleware
export type NetworkFunction = Types.NetworkFunction
export type Promise = Types.Promise

local NetworkFunction = {}
NetworkFunction.__index = NetworkFunction
NetworkFunction.__type = "NetworkFunction"

function NetworkFunction.new(serviceName: string, functionName: string, networkFolder: Folder): NetworkFunction
	local self = setmetatable({}, NetworkFunction)
	local id = serviceName .. "_" .. functionName

	self._functionName = id
	self._networkFolder = networkFolder
	self._middleware = {}
	self._callback = nil
	self._timeout = 10
	self._activeRequests = {}

	self._func = networkFolder:FindFirstChild(id .. "_RF")

	if not self._func then
		if IsServer then
			self._func = Instance.new("RemoteFunction")
			self._func.Name = id .. "_RF"
			self._func.Parent = networkFolder
		else
			self._func = networkFolder:WaitForChild(id .. "_RF", 10)
			if not self._func then
				warn(string.format("[NetworkFunction] Failed to find RemoteFunction: %s", id))
			end
		end
	end

	if self._func and IsServer then
		self._func.OnServerInvoke = function(player, ...)
			local requestId = HttpService:GenerateGUID(false)
			local startTime = os.clock()

			self._activeRequests[requestId] = {
				player = player,
				startTime = startTime,
			}

			for _, middleware in ipairs(self._middleware) do
				local allowed, reason = middleware(player, ...)
				if not allowed then
					warn(
						string.format("[NetworkFunction] '%s' blocked for %s: %s", id, player.Name, reason or "unknown")
					)
					self._activeRequests[requestId] = nil
					return { success = false, error = "blocked: " .. (reason or "unknown") }
				end
			end

			if self._callback then
				local ok, result = pcall(self._callback, player, ...)

				self._activeRequests[requestId] = nil

				if ok then
					return { success = true, data = result }
				else
					warn(string.format("[NetworkFunction] '%s' callback error: %s", id, tostring(result)))
					return { success = false, error = "callback error: " .. tostring(result) }
				end
			end

			self._activeRequests[requestId] = nil
			return { success = false, error = "no callback set" }
		end

		task.spawn(function()
			while self._func do
				task.wait(5)
				local now = os.clock()
				local toRemove = {}

				for reqId, request in pairs(self._activeRequests) do
					local elapsed = now - request.startTime

					if elapsed > 30 then
						warn(
							string.format(
								"[NetworkFunction] '%s' request from %s taking too long (%.1fs)",
								id,
								request.player.Name,
								elapsed
							)
						)
					end

					if elapsed > 60 then
						table.insert(toRemove, reqId)
					end
				end

				for _, reqId in ipairs(toRemove) do
					self._activeRequests[reqId] = nil
				end
			end
		end)
	end

	return self :: any
end

function NetworkFunction:SetCallback(callback: (...any) -> ...any)
	assert(IsServer, "SetCallback can only be called on the server")
	assert(type(callback) == "function", "callback must be a function")
	assert(self._func, "RemoteFunction not initialized")
	self._callback = callback
end

function NetworkFunction:SetTimeout(seconds: number)
	assert(type(seconds) == "number" and seconds > 0, "timeout must be positive number")
	self._timeout = seconds
end

function NetworkFunction:Call(...: any): Promise
	assert(IsClient, "Call can only be used on the client")
	assert(self._func, "RemoteFunction not initialized")

	local args = { ... }
	local timeout = self._timeout
	local cancelled = false

	local callPromise = Promise.new(function(resolve, reject, onCancel)
		onCancel(function()
			cancelled = true
		end)

		task.spawn(function()
			local ok, result = pcall(function()
				return self._func:InvokeServer(table.unpack(args))
			end)

			if cancelled then
				return
			end

			if not ok then
				reject("network error: " .. tostring(result))
				return
			end

			if type(result) ~= "table" then
				reject("invalid response format")
				return
			end

			if result.success then
				resolve(result.data)
			else
				reject(result.error or "unknown error")
			end
		end)
	end)

	local timeoutPromise = Promise.new(function(_, reject)
		task.delay(timeout, function()
			if not cancelled then
				reject(string.format("timeout after %ds", timeout))
			end
		end)
	end)

	local racePromise = Promise.Race({ callPromise, timeoutPromise })

	racePromise:Finally(function()
		callPromise:Cancel()
		timeoutPromise:Cancel()
	end)

	return racePromise
end

function NetworkFunction:AddMiddleware(middleware: Middleware)
	assert(IsServer, "middleware can only be added on the server")
	assert(type(middleware) == "function", "middleware must be a function")
	table.insert(self._middleware, middleware)
end

function NetworkFunction:Destroy()
	if IsServer and self._func then
		self._func.OnServerInvoke = nil
	end
	table.clear(self._middleware)
	table.clear(self._activeRequests)
	self._callback = nil
end

return NetworkFunction
