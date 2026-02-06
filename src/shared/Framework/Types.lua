-- =====================================================
-- STAFN0's Framework Types
-- All type definitions for VSCode IntelliSense
-- =====================================================

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	DisconnectAll: (self: Signal) -> (),
}

export type Promise = {
	Then: (self: Promise, onResolved: ((any) -> any)?, onRejected: ((any) -> any)?) -> Promise,
	Catch: (self: Promise, onRejected: (any) -> any) -> Promise,
	Finally: (self: Promise, onFinally: () -> ()) -> Promise,
	Await: (self: Promise) -> (boolean, any),
}

export type Middleware = (player: Player, ...any) -> (boolean, string?)

export type NetworkSignal = {
	Connect: (self: NetworkSignal, fn: (...any) -> ()) -> Connection,
	Fire: (self: NetworkSignal, ...any) -> (),
	AddMiddleware: (self: NetworkSignal, middleware: Middleware) -> (),
	Destroy: (self: NetworkSignal) -> (),
}

export type NetworkFunction = {
	SetCallback: (self: NetworkFunction, callback: (...any) -> ...any) -> (),
	Call: (self: NetworkFunction, ...any) -> Promise,
	CallSync: (self: NetworkFunction, ...any) -> ...any,
	AddMiddleware: (self: NetworkFunction, middleware: Middleware) -> (),
	SetTimeout: (self: NetworkFunction, seconds: number) -> (),
	Destroy: (self: NetworkFunction) -> (),
}

export type RateLimiter = {
	Check: (self: RateLimiter, player: Player) -> (boolean, string?),
	Cleanup: (self: RateLimiter, player: Player) -> (),
}

export type ServiceState = "Uninitialized" | "Initializing" | "Initialized" | "Starting" | "Started" | "Failed"

export type DependencyConfig = {
	required: { string }?,
	optional: { string }?,
}

export type Service = {
	Name: string,
	Type: "Service"?,
	Framework: Framework?,
	Dependencies: ({ string } | DependencyConfig)?,
	OnInit: ((self: Service) -> ())?,
	OnStart: ((self: Service) -> ())?,
	OnDestroy: ((self: Service) -> ())?,
	[any]: any,
}

export type Controller = {
	Name: string,
	Type: "Controller"?,
	Framework: Framework?,
	OnInit: ((self: Controller) -> ())?,
	OnStart: ((self: Controller) -> ())?,
	OnDestroy: ((self: Controller) -> ())?,
	[any]: any,
}

export type DebugConfig = {
	enabled: boolean?,
	logLevel: ("DEBUG" | "INFO" | "WARN" | "ERROR")?,
	profileMethods: boolean?,
	logLifecycle: boolean?,
}

export type Framework = {
	Signal: any,
	Promise: any,
	Signals: {
		ServiceRegistered: Signal,
		ServiceInitialized: Signal,
		ServiceStarted: Signal,
		ServiceFailed: Signal,
		ControllerRegistered: Signal,
		ControllerInitialized: Signal,
		ControllerStarted: Signal,
		ControllerFailed: Signal,
		Error: Signal,
		Shutdown: Signal,
	},

	-- Registration
	RegisterService: (self: Framework, moduleOrTable: any, name: string?) -> Service,
	RegisterController: (self: Framework, moduleOrTable: any, name: string?) -> Controller,
	RegisterFromFolder: (self: Framework, folder: Folder) -> (),

	-- Access
	GetService: (self: Framework, name: string) -> Service?,
	GetController: (self: Framework, name: string) -> Controller?,
	GetServiceState: (self: Framework, name: string) -> ServiceState?,
	GetControllerState: (self: Framework, name: string) -> ServiceState?,
	WaitForService: (self: Framework, name: string, timeout: number?) -> Service?,
	WaitForController: (self: Framework, name: string, timeout: number?) -> Controller?,

	-- Networking
	CreateSignal: (self: Framework, service: Service | Controller, signalName: string) -> NetworkSignal,
	CreateFunction: (self: Framework, service: Service | Controller, functionName: string) -> NetworkFunction,
	CreateRateLimiter: (self: Framework, maxRequests: number, windowSeconds: number) -> RateLimiter,

	-- Lifecycle
	Start: (self: Framework) -> boolean,
	Shutdown: (self: Framework) -> (),
	RegisterShutdownHandler: (self: Framework, name: string, handler: () -> ()) -> (),

	-- Cleanup
	UnregisterService: (self: Framework, name: string) -> (),
	UnregisterController: (self: Framework, name: string) -> (),
	Destroy: (self: Framework) -> (),

	-- Debug
	SetDebug: (self: Framework, config: DebugConfig) -> (),
	Log: (self: Framework, level: string, message: string, ...any) -> (),
}

return nil
