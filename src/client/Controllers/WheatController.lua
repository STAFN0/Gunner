local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local wheatController = {
	Type = "Controller",
}

function wheatController:OnInit()
	self.DetectionRadius = 8
	self.TransparentValue = 0.8
	self.FadeSpeed = 0.3

	self.OriginalTransparency = {}
	self.ActiveTweens = {}
	self.NearbyWheat = {}
	self.WheatParts = {}

	self.Character = game.Players.LocalPlayer.Character

	game.Players.LocalPlayer.CharacterAdded:Connect(function(newChar)
		self.Character = newChar
		self:ResetAllWheat()
	end)
end

function wheatController:OnStart()
	if not self.Character then
		self.Character = game.Players.LocalPlayer.CharacterAdded:Wait()
	end

	self.Wheats = Workspace.wheat.Model:GetChildren()
	for _, wheat in ipairs(self.Wheats) do
		if wheat:IsA("BasePart") then
			table.insert(self.WheatParts, wheat)
			self.OriginalTransparency[wheat] = wheat.Transparency
		elseif wheat:IsA("Model") then
			for _, part in ipairs(wheat:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(self.WheatParts, part)
					self.OriginalTransparency[part] = part.Transparency
				end
			end
		end
	end

	local updateTimer = 0

	RunService.Heartbeat:Connect(function(dt)
		updateTimer = updateTimer + dt

		if updateTimer < 0.1 then
			return
		end
		updateTimer = 0

		if not self.Character or not self.Character.PrimaryPart then
			return
		end

		local playerPos = self.Character.PrimaryPart.Position
		local currentNearby = {}

		for _, part in ipairs(self.WheatParts) do
			local distance = (playerPos - part.Position).Magnitude

			if distance <= self.DetectionRadius then
				currentNearby[part] = true

				if not self.NearbyWheat[part] then
					self:FadeWheat(part, self.TransparentValue)
				end
			end
		end

		for part, _ in pairs(self.NearbyWheat) do
			if not currentNearby[part] then
				self:FadeWheat(part, self.OriginalTransparency[part] or 0)
			end
		end

		self.NearbyWheat = currentNearby
	end)
end

function wheatController:FadeWheat(part, targetTransparency)
	if math.abs(part.Transparency - targetTransparency) < 0.01 then
		return
	end

	if self.ActiveTweens[part] then
		self.ActiveTweens[part]:Cancel()
	end

	local tween = TweenService:Create(
		part,
		TweenInfo.new(self.FadeSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = targetTransparency }
	)

	self.ActiveTweens[part] = tween
	tween:Play()

	tween.Completed:Connect(function()
		self.ActiveTweens[part] = nil
	end)
end

function wheatController:ResetAllWheat()
	for part, originalTransparency in pairs(self.OriginalTransparency) do
		if self.ActiveTweens[part] then
			self.ActiveTweens[part]:Cancel()
		end
		part.Transparency = originalTransparency
	end

	self.NearbyWheat = {}
	self.ActiveTweens = {}
end

return wheatController
