local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateManager = {
	Type = "Controller",
	Name = "StateManager",
	Dependencies = { "ViewModel" },
}

local BulletModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Bullet"))

local Animations = {
	Idle = "73217042862044",
	Walking = "100741731373486",
	Running = "123747429202014",
	GunShot = "83192017140099",
	SwordSwing = "102694938743925",
}

function StateManager:OnInit()
	self.CurrentState = "Idle"
	self.PreviousState = nil
	self.ViewModelModule = self.Framework:GetController("ViewModel")
	self.LoadedAnimations = {}
	self.PreloadedTracks = {}
	self.ActiveAnimations = {}
	self.Connections = {}
	self.StateChangedCallbacks = {}
	self.AttemptaShot = self.Framework:CreateSignal({ Name = "BulletService" }, "AttemptAShot")
	self.hum = nil

	self.LastWPress = 0
	self.DoubleTapWindow = 0.5
	self.IsSprinting = false

	self.LastGunShot = 0
	self.LastSwordSwing = 0
	self.AttackCooldown = 0.5
	self.BulletSpeed = 300

	self.States = {
		Idle = {
			OnEnter = function()
				self:PlayAnimation("Idle")
			end,
			OnExit = function()
				self:StopAnimation("Idle")
			end,
		},
		Walking = {
			OnEnter = function()
				self:PlayAnimation("Walking")
			end,
			OnExit = function()
				self:StopAnimation("Walking")
			end,
		},
		Running = {
			OnEnter = function()
				self:PlayAnimation("Running")
			end,
			OnExit = function()
				self:StopAnimation("Running")
			end,
		},
	}
end

function StateManager:OnStart()
	self:LoadAnimations()

	local player = game.Players.LocalPlayer

	player.CharacterAdded:Connect(function(character)
		self:CleanupConnections()

		local hum = character:WaitForChild("Humanoid")
		local hrp = character:WaitForChild("HumanoidRootPart")

		self.hum = hum

		task.wait(0.5)
		self:PreloadAnimations()

		local stateConnection = RunService.Heartbeat:Connect(function()
			if not hum or hum.Health <= 0 then
				return
			end

			local speed = hrp.AssemblyLinearVelocity.Magnitude

			if speed < 1 then
				self:SetState("Idle")
				self.IsSprinting = false
				hum.WalkSpeed = 14
			elseif self.IsSprinting then
				self:SetState("Running")
			elseif speed < 9 then
				self:SetState("Walking")
			end
		end)

		table.insert(self.Connections, stateConnection)
	end)

	if player.Character then
		self.hum = player.Character:FindFirstChild("Humanoid")
		task.wait(0.5)
		self:PreloadAnimations()
	end

	self:SetState("Idle")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.hum then
			return
		end

		if input.KeyCode == Enum.KeyCode.W then
			local currentTime = tick()
			local timeSinceLastPress = currentTime - self.LastWPress

			if timeSinceLastPress <= self.DoubleTapWindow then
				self.IsSprinting = true
				self.hum.WalkSpeed = 35
			end

			self.LastWPress = currentTime
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local currentTime = tick()
			if currentTime - self.LastGunShot >= self.AttackCooldown then
				self.LastGunShot = currentTime
				self:ShootBullet()
			end
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			local currentTime = tick()
			if currentTime - self.LastSwordSwing >= self.AttackCooldown then
				self.LastSwordSwing = currentTime
				self:PlayOneShot("SwordSwing")
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.W then
			self.IsSprinting = false
			if self.hum then
				self.hum.WalkSpeed = 16
			end
		end
	end)

	player.CharacterRemoving:Connect(function()
		self:CleanupConnections()
		self:StopAllAnimations()
		self.PreloadedTracks = {}
	end)
end

function StateManager:ShootBullet()
	local track = self.PreloadedTracks["GunShot"]
	if track then
		track:Stop()
		track:Play(0, 1, 1)
	end

	local camera = workspace.CurrentCamera
	local viewModel = camera:FindFirstChild("ViewModel")

	local startPos
	local direction = camera.CFrame.LookVector

	if viewModel and viewModel:FindFirstChild("Gun") and viewModel.Gun:FindFirstChild("Fire") then
		startPos = viewModel.Gun.Fire.Position
	else
		startPos = camera.CFrame.Position + (direction * 2)
	end

	local player = game.Players.LocalPlayer
	if player.Character then
		BulletModule(startPos, direction, self.BulletSpeed, player.Character, function() end, 3)
	end

	self.AttemptaShot:Fire({
		StartPos = startPos,
		Direction = direction,
	})
end

function StateManager:PlayOneShot(animName)
	local track = self.PreloadedTracks[animName]
	if track then
		track:Stop()
		track:Play(0, 1, 1)
	end
end

function StateManager:PreloadAnimations()
	local viewModel = self.ViewModelModule:GetViewModel()
	if not viewModel then
		return
	end

	local hum = viewModel:FindFirstChildOfClass("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

	local animInstances = {}
	for _, anim in pairs(self.LoadedAnimations) do
		table.insert(animInstances, anim)
	end

	ContentProvider:PreloadAsync(animInstances)

	for name, anim in pairs(self.LoadedAnimations) do
		if name == "GunShot" or name == "SwordSwing" then
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			self.PreloadedTracks[name] = track
		end
	end
end

function StateManager:LoadAnimations()
	for name, animId in pairs(Animations) do
		if not tonumber(animId) then
			warn("Invalid animation ID for", name, "- skipping")
			continue
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. animId
		self.LoadedAnimations[name] = anim
	end
end

function StateManager:PlayAnimation(animName, looped)
	local viewModel = self.ViewModelModule:GetViewModel()
	if not viewModel then
		warn("ViewModel not found!")
		return
	end

	local hum = viewModel:FindFirstChildOfClass("Humanoid")
	if not hum then
		warn("ViewModel has no Humanoid!")
		return
	end

	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anim = self.LoadedAnimations[animName]
	if not anim then
		return
	end

	if self.ActiveAnimations[animName] then
		self.ActiveAnimations[animName]:Stop()
	end

	local animTrack = animator:LoadAnimation(anim)
	animTrack.Priority = Enum.AnimationPriority.Action
	animTrack.Looped = looped == nil and true or looped

	if animTrack.Length == 0 then
		local startTime = tick()
		repeat
			task.wait()
		until animTrack.Length > 0 or tick() - startTime > 5

		if animTrack.Length == 0 then
			warn("Animation failed to load:", animName)
			return
		end
	end

	animTrack:Play(0, 1, 1)
	self.ActiveAnimations[animName] = animTrack
end

function StateManager:StopAnimation(animName)
	if self.ActiveAnimations[animName] then
		self.ActiveAnimations[animName]:Stop(0)
		self.ActiveAnimations[animName] = nil
	end
end

function StateManager:StopAllAnimations()
	for _, track in pairs(self.ActiveAnimations) do
		track:Stop(0)
	end
	self.ActiveAnimations = {}
end

function StateManager:CleanupConnections()
	for _, connection in pairs(self.Connections) do
		connection:Disconnect()
	end
	self.Connections = {}
end

function StateManager:SetState(newState)
	if self.CurrentState == newState then
		return
	end
	if not self.States[newState] then
		warn("State", newState, "does not exist!")
		return
	end

	if self.CurrentState and self.States[self.CurrentState].OnExit then
		self.States[self.CurrentState].OnExit()
	end

	self.PreviousState = self.CurrentState
	self.CurrentState = newState

	if self.States[newState].OnEnter then
		self.States[newState].OnEnter()
	end

	for _, callback in pairs(self.StateChangedCallbacks) do
		callback(newState, self.PreviousState)
	end
end

function StateManager:GetState()
	return self.CurrentState
end

function StateManager:OnStateChanged(callback)
	table.insert(self.StateChangedCallbacks, callback)
end

function StateManager:OnDestroy()
	self:CleanupConnections()
	self:StopAllAnimations()
	self.StateChangedCallbacks = {}
end

return StateManager
