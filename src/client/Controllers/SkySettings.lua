local ReplicatedStorage = game:GetService("ReplicatedStorage")
local skysettings = {
	Type = "Controller",
}

function skysettings:OnInit()
	self.Copies = ReplicatedStorage:WaitForChild("Sky"):GetChildren()
end

function skysettings:OnStart()
	for _, copy in pairs(self.Copies) do
		copy.Parent = game.Lighting
	end
end

return skysettings
