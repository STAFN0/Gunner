-- =====================================================
-- STAFN0's NetworkSignal
-- Client-server communication with middleware support
-- =====================================================

local RunService = game:GetService("RunService")
local Types = require(script.Parent.Types)

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

export type Middleware = Types.Middleware
export type NetworkSignal = Types.NetworkSignal
export type Connection = Types.Connection

local NetworkSignal = {}
NetworkSignal.__index = NetworkSignal
NetworkSignal.__type = "NetworkSignal"

function NetworkSignal.new(serviceName: string, signalName: string, networkFolder: Folder): NetworkSignal
	local self = setmetatable({}, NetworkSignal)
	local id = serviceName .. "_" .. signalName

	self._signalName = id
	self._networkFolder = networkFolder
	self._serverCallbacks = {}
	self._clientCallbacks = {}
	self._middleware = {}
	self._serverConnection = nil
	self._clientConnection = nil

	-- EAGER LOADING: Create/find RemoteEvent immediately
	self._event = networkFolder:FindFirstChild(id .. "_RE")

	if not self._event then
		if IsServer then
			self._event = Instance.new("RemoteEvent")
			self._event.Name = id .. "_RE"
			self._event.Parent = networkFolder
		else
			self._event = networkFolder:WaitForChild(id .. "_RE", 10)
			if not self._event then
				warn(string.format("[NetworkSignal] Failed to find RemoteEvent: %s", id))
			end
		end
	end

	-- Set up connections immediately
	if self._event then
		if IsServer then
			self._serverConnection = self._event.OnServerEvent:Connect(function(player, ...)
				-- Run middleware
				for _, middleware in ipairs(self._middleware) do
					local allowed, reason = middleware(player, ...)
					if not allowed then
						warn(
							string.format(
								"[NetworkSignal] '%s' blocked for %s: %s",
								id,
								player.Name,
								reason or "unknown"
							)
						)
						return
					end
				end

				-- Execute callbacks
				for _, callback in ipairs(self._serverCallbacks) do
					task.spawn(callback, player, ...)
				end
			end)
		end

		if IsClient then
			self._clientConnection = self._event.OnClientEvent:Connect(function(...)
				for _, callback in ipairs(self._clientCallbacks) do
					task.spawn(callback, ...)
				end
			end)
		end
	end

	return self :: any
end

function NetworkSignal:Connect(fn: (...any) -> ()): Connection
	assert(type(fn) == "function", "Connect requires a function")
	assert(self._event, "RemoteEvent not initialized")

	local callbacks = IsServer and self._serverCallbacks or self._clientCallbacks
	table.insert(callbacks, fn)

	local connection = {
		Connected = true,
		_fn = fn,
		_callbacks = callbacks,
	}

	connection.Disconnect = function(self2)
		if not self2.Connected then
			return
		end
		self2.Connected = false

		for i, callback in ipairs(self2._callbacks) do
			if callback == self2._fn then
				table.remove(self2._callbacks, i)
				break
			end
		end
	end

	return connection
end

function NetworkSignal:AddMiddleware(middleware: Middleware)
	assert(IsServer, "middleware can only be added on the server")
	assert(type(middleware) == "function", "middleware must be a function")
	table.insert(self._middleware, middleware)
end

function NetworkSignal:Fire(...: any)
	assert(self._event, "RemoteEvent not initialized")

	if IsServer then
		local args = { ... }
		local firstArg = args[1]

		if typeof(firstArg) == "Instance" and firstArg:IsA("Player") then
			local player = table.remove(args, 1)
			self._event:FireClient(player, table.unpack(args))
		else
			self._event:FireAllClients(...)
		end
	else
		self._event:FireServer(...)
	end
end

function NetworkSignal:Destroy()
	if self._serverConnection then
		self._serverConnection:Disconnect()
	end
	if self._clientConnection then
		self._clientConnection:Disconnect()
	end
	table.clear(self._serverCallbacks)
	table.clear(self._clientCallbacks)
	table.clear(self._middleware)
end

return NetworkSignal
