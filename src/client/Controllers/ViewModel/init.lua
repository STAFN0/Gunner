local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SpringModule = require(ReplicatedStorage.Shared.Modules.Spring)

local ViewModel = {
	Type = "Controller",
	Name = "ViewModel",
}

function ViewModel:OnInit()
	self.ViewModel = ReplicatedStorage:WaitForChild("Viewmodel")
	self.Player = game.Players.LocalPlayer
	self.Camera = workspace.CurrentCamera

	self.Connections = {}

	self.ActiveViewModel = nil
	self.ActiveCharacter = nil

	self.bobSpring = SpringModule:new(5, 50, 4, 4)
	self.swaySpring = SpringModule:new(3, 30, 5, 6)

	self.Camera.FieldOfView = 60
end

function ViewModel:OnStart()
	self.Player.CharacterAdded:Connect(function(character)
		self.ActiveCharacter = character
		self:SetupViewModel()
		local hum = character:WaitForChild("Humanoid")
		local landConnection = hum.StateChanged:Connect(function(_oldState, newState)
			if newState == Enum.HumanoidStateType.Landed then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local fallSpeed = math.abs(hrp.AssemblyLinearVelocity.Y)
					local impactForce = math.clamp(fallSpeed / 50, 0.2, 1.5)
					self.bobSpring:shove(Vector3.new(0, -impactForce, 0))
				end
			end
		end)
		table.insert(self.Connections, landConnection)
	end)

	self.Player.CharacterRemoving:Connect(function()
		self.ActiveCharacter = nil
		if self.ActiveViewModel then
			self.ActiveViewModel:Destroy()
			self.ActiveViewModel = nil
		end
		self:StopBobbing()
	end)
end

function ViewModel:OnDestroy()
	for _, connection in pairs(self.Connections) do
		connection:Disconnect()
	end
end

function ViewModel:StartBobbing()
	if self.BobConnection then
		return
	end

	local hum = self.ActiveCharacter:WaitForChild("Humanoid")
	local hrp = self.ActiveCharacter:WaitForChild("HumanoidRootPart")

	self.BobConnection = RunService.RenderStepped:Connect(function(dt)
		if not self.ActiveViewModel or not self.ActiveCharacter then
			return
		end

		local hrp = self.ActiveCharacter:FindFirstChild("HumanoidRootPart")
		local hum = self.ActiveCharacter:FindFirstChild("Humanoid")
		if not hrp or not hum then
			return
		end

		local yVelocity = hrp.AssemblyLinearVelocity.Y
		local airLean = math.clamp(yVelocity / 80, -0.4, 0.4)
		self.bobSpring.Target = Vector3.new(airLean, 0, 0)

		local updateBob = self.bobSpring:update(dt)

		local mouseDelta = UserInputService:GetMouseDelta()
		self.swaySpring:shove(Vector3.new(mouseDelta.X, mouseDelta.Y, 0) / 60)
		local updateSway = self.swaySpring:update(dt)
		self.ActiveViewModel.CameraBone.CFrame = self.Camera.CFrame
			* CFrame.new(updateSway.X, updateSway.Y, 0)
			* CFrame.new(0, updateBob.Y - (updateBob.X / 2), 0)
			* CFrame.Angles(math.rad(updateBob.X * 10), 0, 0)
	end)
end

function ViewModel:StopBobbing()
	if self.BobConnection then
		self.BobConnection:Disconnect()
		self.BobConnection = nil
	end
end

function ViewModel:SetupViewModel()
	if self.ActiveCharacter then
		self.ActiveViewModel = self.ViewModel:Clone()
		self.ActiveViewModel.Parent = workspace.Camera

		for _, part in ipairs(self.ActiveViewModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Massless = true
				part.CastShadow = false
			end
		end

		self:StartBobbing()
	end
end

function ViewModel:GetViewModel()
	return self.ActiveViewModel
end

return ViewModel
