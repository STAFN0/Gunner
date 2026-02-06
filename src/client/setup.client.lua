local Framework = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Framework"))
--------------------------------------------------------------------------------------
---------------------------   Start The Framework ------------------------------------
--------------------------------------------------------------------------------------

Framework:RegisterFromFolder(script.Parent.Controllers)
Framework:SetDebug({
	enabled = true,
	logLevel = "INFO",
	profileMethods = true,
	logLifecycle = true,
})
Framework:Start()
