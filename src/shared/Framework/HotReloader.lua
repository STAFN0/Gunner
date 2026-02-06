local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Signal)

export type HotReloader = {
	Watch: (self: HotReloader, moduleScript: ModuleScript) -> (),
	Unwatch: (self: HotReloader, moduleScript: ModuleScript) -> (),
	Reload: (self: HotReloader, moduleScript: ModuleScript) -> boolean,
	IsWatching: (self: HotReloader, moduleScript: ModuleScript) -> boolean,
	SetAutoReload: (self: HotReloader, enabled: boolean) -> (),
	OnReloaded: Signal.Signal,
	OnReloadFailed: Signal.Signal,
}

local HotReloader = {}
HotReloader.__index = HotReloader
HotReloader.__type = "HotReloader"

function HotReloader.new(framework): HotReloader
	assert(RunService:IsServer(), "HotReloader is server-only")

	local self = setmetatable({
		_framework = framework,
		_watching = {},
		_moduleCache = {},
		_autoReload = false,
		OnReloaded = Signal.new(),
		OnReloadFailed = Signal.new(),
	}, HotReloader)

	return self :: any
end

function HotReloader:Watch(moduleScript: ModuleScript)
	assert(typeof(moduleScript) == "Instance" and moduleScript:IsA("ModuleScript"), "must be a ModuleScript")

	if self._watching[moduleScript] then
		return
	end

	local connection = moduleScript.Changed:Connect(function(property)
		if property == "Source" and self._autoReload then
			task.defer(function()
				self:Reload(moduleScript)
			end)
		end
	end)

	self._watching[moduleScript] = connection
	self._moduleCache[moduleScript] = moduleScript.Source
end

function HotReloader:Unwatch(moduleScript: ModuleScript)
	local connection = self._watching[moduleScript]
	if connection then
		connection:Disconnect()
		self._watching[moduleScript] = nil
		self._moduleCache[moduleScript] = nil
	end
end

function HotReloader:Reload(moduleScript: ModuleScript): boolean
	assert(typeof(moduleScript) == "Instance" and moduleScript:IsA("ModuleScript"), "must be a ModuleScript")

	local oldSource = self._moduleCache[moduleScript]
	local newSource = moduleScript.Source

	if oldSource == newSource then
		warn(string.format("[HotReloader] No changes detected in '%s'", moduleScript.Name))
		return false
	end

	local ok, newModule = pcall(require, moduleScript)
	if not ok then
		warn(string.format("[HotReloader] Failed to reload '%s': %s", moduleScript.Name, newModule))
		self.OnReloadFailed:Fire(moduleScript, newModule)
		return false
	end

	if type(newModule) ~= "table" then
		warn(string.format("[HotReloader] Module '%s' did not return a table", moduleScript.Name))
		self.OnReloadFailed:Fire(moduleScript, "Module did not return a table")
		return false
	end

	local serviceName = newModule.Name or moduleScript.Name
	local oldService = self._framework:GetService(serviceName)

	if not oldService then
		warn(string.format("[HotReloader] Service '%s' not found in framework", serviceName))
		self.OnReloadFailed:Fire(moduleScript, "Service not found")
		return false
	end

	if type(oldService.OnDestroy) == "function" then
		local destroyOk, destroyErr = pcall(oldService.OnDestroy, oldService)
		if not destroyOk then
			warn(string.format("[HotReloader] OnDestroy error in '%s': %s", serviceName, destroyErr))
		end
	end

	for key, value in pairs(newModule) do
		if key ~= "Name" and key ~= "Framework" then
			oldService[key] = value
		end
	end

	if type(oldService.OnInit) == "function" then
		local initOk, initErr = pcall(oldService.OnInit, oldService)
		if not initOk then
			warn(string.format("[HotReloader] OnInit error after reload in '%s': %s", serviceName, initErr))
			self.OnReloadFailed:Fire(moduleScript, initErr)
			return false
		end
	end

	if type(oldService.OnStart) == "function" then
		local startOk, startErr = pcall(oldService.OnStart, oldService)
		if not startOk then
			warn(string.format("[HotReloader] OnStart error after reload in '%s': %s", serviceName, startErr))
			self.OnReloadFailed:Fire(moduleScript, startErr)
			return false
		end
	end

	self._moduleCache[moduleScript] = newSource
	self.OnReloaded:Fire(moduleScript, serviceName)

	return true
end

function HotReloader:IsWatching(moduleScript: ModuleScript): boolean
	return self._watching[moduleScript] ~= nil
end

function HotReloader:SetAutoReload(enabled: boolean)
	assert(type(enabled) == "boolean", "enabled must be a boolean")
	self._autoReload = enabled
end

function HotReloader:Destroy()
	for _, connection in pairs(self._watching) do
		connection:Disconnect()
	end

	table.clear(self._watching)
	table.clear(self._moduleCache)
	self.OnReloaded:DisconnectAll()
	self.OnReloadFailed:DisconnectAll()
end

return HotReloader
