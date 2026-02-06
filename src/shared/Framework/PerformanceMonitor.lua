local Signal = require(script.Parent.Signal)

export type PerformanceMetric = {
	name: string,
	count: number,
	totalTime: number,
	averageTime: number,
	minTime: number,
	maxTime: number,
	lastTime: number,
}

export type PerformanceMonitor = {
	Track: (self: PerformanceMonitor, name: string, fn: (...any) -> ...any, ...any) -> ...any,
	TrackAsync: (self: PerformanceMonitor, name: string, fn: (...any) -> ...any, ...any) -> (),
	StartMeasure: (self: PerformanceMonitor, name: string) -> () -> (),
	GetMetric: (self: PerformanceMonitor, name: string) -> PerformanceMetric?,
	GetAllMetrics: (self: PerformanceMonitor) -> { [string]: PerformanceMetric },
	Reset: (self: PerformanceMonitor, name: string?) -> (),
	SetWarningThreshold: (self: PerformanceMonitor, name: string, milliseconds: number) -> (),
	OnSlowOperation: Signal.Signal,
}

local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor
PerformanceMonitor.__type = "PerformanceMonitor"

function PerformanceMonitor.new(): PerformanceMonitor
	local self = setmetatable({
		_metrics = {},
		_thresholds = {},
		OnSlowOperation = Signal.new(),
	}, PerformanceMonitor)

	return self :: any
end

function PerformanceMonitor:_recordMetric(name: string, duration: number)
	if not self._metrics[name] then
		self._metrics[name] = {
			name = name,
			count = 0,
			totalTime = 0,
			averageTime = 0,
			minTime = math.huge,
			maxTime = 0,
			lastTime = 0,
		}
	end

	local metric = self._metrics[name]
	metric.count += 1
	metric.totalTime += duration
	metric.averageTime = metric.totalTime / metric.count
	metric.minTime = math.min(metric.minTime, duration)
	metric.maxTime = math.max(metric.maxTime, duration)
	metric.lastTime = duration

	local threshold = self._thresholds[name]
	if threshold and duration * 1000 > threshold then
		self.OnSlowOperation:Fire(name, duration * 1000, threshold)
	end
end

function PerformanceMonitor:Track(name: string, fn: (...any) -> ...any, ...: any): ...any
	assert(type(name) == "string", "name must be a string")
	assert(type(fn) == "function", "fn must be a function")

	local startTime = os.clock()
	local results = table.pack(fn(...))
	local duration = os.clock() - startTime

	self:_recordMetric(name, duration)

	return table.unpack(results, 1, results.n)
end

function PerformanceMonitor:TrackAsync(name: string, fn: (...any) -> ...any, ...: any)
	assert(type(name) == "string", "name must be a string")
	assert(type(fn) == "function", "fn must be a function")

	local args = { ... }
	task.spawn(function()
		self:Track(name, fn, table.unpack(args))
	end)
end

function PerformanceMonitor:StartMeasure(name: string): () -> ()
	assert(type(name) == "string", "name must be a string")

	local startTime = os.clock()

	return function()
		local duration = os.clock() - startTime
		self:_recordMetric(name, duration)
	end
end

function PerformanceMonitor:GetMetric(name: string): PerformanceMetric?
	return self._metrics[name]
end

function PerformanceMonitor:GetAllMetrics(): { [string]: PerformanceMetric }
	return self._metrics
end

function PerformanceMonitor:Reset(name: string?)
	if name then
		self._metrics[name] = nil
	else
		table.clear(self._metrics)
	end
end

function PerformanceMonitor:SetWarningThreshold(name: string, milliseconds: number)
	assert(type(name) == "string", "name must be a string")
	assert(type(milliseconds) == "number" and milliseconds > 0, "milliseconds must be positive")

	self._thresholds[name] = milliseconds
end

return PerformanceMonitor
