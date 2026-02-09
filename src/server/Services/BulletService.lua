local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BulletService = {
	Type = "Service",
	Name = "BulletService",
}

local BulletModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Bullet"))

function BulletService:OnInit()
	self.AttemptAShot = self.Framework:CreateSignal(self, "AttemptAShot")
	self.BulletSpeed = 300

	local limiter = self.Framework:CreateRateLimiter(10, 10)

	self.AttemptAShot:AddMiddleware(function(player, _data)
		return limiter:Check(player)
	end)
end

function BulletService:OnStart()
	self.AttemptAShot:Connect(function(player, data)
		local character = player.Character
		if not character then
			return
		end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then
			return
		end

		local startPos = data.StartPos
		local direction = data.Direction

		local function onHit(hit, position)
			local targetHumanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and targetHumanoid ~= humanoid then
				targetHumanoid:TakeDamage(25)
			end
		end

		BulletModule(startPos, direction, self.BulletSpeed, character, onHit, 3)
	end)
end

return BulletService
