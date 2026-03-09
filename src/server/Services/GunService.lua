local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BulletService = {
	Type = "Service",
	Name = "BulletService",
}

local BulletModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Bullet"))

function BulletService:OnInit()
	self.AttemptAShot = self.Framework:CreateSignal(self, "AttemptAShot")
	self.BulletSpeed = 400
	self.BulletLifetime = 3
	self.BaseDamage = 25

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
		local direction = data.Direction.Unit
		self:CreateMuzzleFlash(startPos, direction)

		local function onHit(hit, position)
			local targetHumanoid = hit.Parent:FindFirstChildOfClass("Humanoid")

			if targetHumanoid and targetHumanoid ~= humanoid then
				local damage = self.BaseDamage
				if hit.Name == "Head" then
					damage = damage * 2
				end

				targetHumanoid:TakeDamage(damage)
			end
		end

		BulletModule(startPos, direction, self.BulletSpeed, character, onHit, self.BulletLifetime)
	end)
end

function BulletService:CreateMuzzleFlash(position, direction)
	local muzzleFlash = Instance.new("Part")
	muzzleFlash.Size = Vector3.new(0.5, 0.5, 0.5)
	muzzleFlash.Material = Enum.Material.Neon
	muzzleFlash.Color = Color3.fromRGB(255, 220, 150)
	muzzleFlash.Transparency = 0.3
	muzzleFlash.CanCollide = false
	muzzleFlash.Anchored = true
	muzzleFlash.CFrame = CFrame.new(position, position + direction)
	muzzleFlash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Color = Color3.fromRGB(255, 200, 100)
	light.Range = 12
	light.Parent = muzzleFlash

	local flash = Instance.new("ParticleEmitter")
	flash.Parent = muzzleFlash
	flash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	flash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	flash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	flash.Lifetime = NumberRange.new(0.05, 0.1)
	flash.Speed = NumberRange.new(0, 0)
	flash.Rate = 0
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.ZOffset = 1

	flash:Emit(3)

	game:GetService("TweenService"):Create(muzzleFlash, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(muzzleFlash, 0.15)
end

function BulletService:SendHitMarker(player, isHeadshot) end

return BulletService
