local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local EnemyService = {
	Type = "Service",
	Name = "EnemyService",
}

local CONFIG = {
	SPAWN_RADIUS_MIN = 30,
	SPAWN_RADIUS_MAX = 50,
	BASE_SPAWN_INTERVAL = 5,
	MAX_ENEMIES_PER_PLAYER = 15,
}

function EnemyService:OnInit()
	self.Difficulty = 1
	self.PlayerSpawnTimers = {}
	self.PlayerEnemyCounts = {}
	self.EnemyFolder = ReplicatedStorage:WaitForChild("Enemys")
	self.ActivePlayers = {}
	self.RecentSpawnPositions = {}

	self.EnemyTemplates = self.EnemyFolder:GetChildren()

	if #self.EnemyTemplates == 0 then
		warn("[EnemyService] No enemy templates found in ReplicatedStorage.Enemys!")
	end
end

function EnemyService:OnStart()
	for _, player in ipairs(Players:GetPlayers()) do
		self:RegisterPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:RegisterPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:UnregisterPlayer(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		self:UpdateSpawning(dt)
	end)

end

function EnemyService:RegisterPlayer(player)
	self.PlayerSpawnTimers[player] = 0
	self.PlayerEnemyCounts[player] = 0
	self.ActivePlayers[player] = true

	player.CharacterAdded:Connect(function(character)
		self.PlayerSpawnTimers[player] = 0
		self.PlayerEnemyCounts[player] = 0
	end)

	player.CharacterRemoving:Connect(function()
		self:CleanupPlayerEnemies(player)
	end)
end

function EnemyService:UnregisterPlayer(player)
	self.PlayerSpawnTimers[player] = nil
	self.PlayerEnemyCounts[player] = nil
	self.ActivePlayers[player] = nil

	self:CleanupPlayerEnemies(player)
end

function EnemyService:UpdateSpawning(dt)
	for player, _ in pairs(self.ActivePlayers) do
		if player.Parent and player.Character then
			local character = player.Character
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChild("Humanoid")

			if rootPart and humanoid and humanoid.Health > 0 then
				self.PlayerSpawnTimers[player] = self.PlayerSpawnTimers[player] + dt

				local spawnInterval = CONFIG.BASE_SPAWN_INTERVAL / self.Difficulty

				if self.PlayerSpawnTimers[player] >= spawnInterval then
					self.PlayerSpawnTimers[player] = 0

					if self.PlayerEnemyCounts[player] < CONFIG.MAX_ENEMIES_PER_PLAYER then
						self:SpawnEnemyNearPlayer(player, rootPart.Position)
					end
				end
			end
		end
	end
end

function EnemyService:SpawnEnemyNearPlayer(player, playerPosition)
	if #self.EnemyTemplates == 0 then
		return
	end

	local template = self.EnemyTemplates[math.random(1, #self.EnemyTemplates)]

	local spawnPos
	local attempts = 0
	local maxAttempts = 10
	local minDistanceBetweenEnemies = 5

	repeat
		attempts = attempts + 1

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(CONFIG.SPAWN_RADIUS_MIN, CONFIG.SPAWN_RADIUS_MAX)

		spawnPos = Vector3.new(
			playerPosition.X + math.cos(angle) * distance,
			playerPosition.Y,
			playerPosition.Z + math.sin(angle) * distance
		)

		local tooClose = false
		for _, recentPos in ipairs(self.RecentSpawnPositions) do
			if (spawnPos - recentPos.Position).Magnitude < minDistanceBetweenEnemies then
				tooClose = true
				break
			end
		end

		if not tooClose then
			break
		end

	until attempts >= maxAttempts

	local newEnemy = template:Clone()

	newEnemy:SetAttribute("OwnerPlayer", player.UserId)
	newEnemy:SetAttribute("SpawnTime", tick())

	newEnemy.Parent = workspace

	if newEnemy:IsA("Model") then
		newEnemy:PivotTo(CFrame.new(spawnPos))
	else
		newEnemy.CFrame = CFrame.new(spawnPos)
	end

	table.insert(self.RecentSpawnPositions, { Position = spawnPos, Time = tick() })
	if #self.RecentSpawnPositions > 20 then
		table.remove(self.RecentSpawnPositions, 1)
	end

	self.PlayerEnemyCounts[player] = self.PlayerEnemyCounts[player] + 1

	self:TrackEnemyDeath(newEnemy, player)

	return newEnemy
end

function EnemyService:TrackEnemyDeath(enemy, player)
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if self.PlayerEnemyCounts[player] then
				self.PlayerEnemyCounts[player] = math.max(0, self.PlayerEnemyCounts[player] - 1)
			end

			task.delay(2, function()
				if enemy and enemy.Parent then
					enemy:Destroy()
				end
			end)
		end)
	end
end

function EnemyService:CleanupPlayerEnemies(player)
	for _, enemy in ipairs(workspace:GetChildren()) do
		if enemy:GetAttribute("OwnerPlayer") == player.UserId then
			enemy:Destroy()
		end
	end

	if self.PlayerEnemyCounts[player] then
		self.PlayerEnemyCounts[player] = 0
	end
end

function EnemyService:IncreaseDifficulty(amount)
	self.Difficulty = self.Difficulty + (amount or 0.5)
	return self.Difficulty
end

function EnemyService:DecreaseDifficulty(amount)
	self.Difficulty = math.max(1, self.Difficulty - (amount or 0.5))
	return self.Difficulty
end

function EnemyService:SetDifficulty(value)
	self.Difficulty = math.max(1, value)
	return self.Difficulty
end

function EnemyService:GetDifficulty()
	return self.Difficulty
end

function EnemyService:GetPlayerEnemyCount(player)
	return self.PlayerEnemyCounts[player] or 0
end

function EnemyService:GetTotalEnemyCount()
	local total = 0
	for _, count in pairs(self.PlayerEnemyCounts) do
		total = total + count
	end
	return total
end

function EnemyService:ForceSpawnEnemy(player, enemyName)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	local template
	if enemyName then
		template = self.EnemyFolder:FindFirstChild(enemyName)
	else
		template = self.EnemyTemplates[math.random(1, #self.EnemyTemplates)]
	end

	if not template then
		warn("[EnemyService] Enemy template not found:", enemyName)
		return nil
	end

	return self:SpawnEnemyNearPlayer(player, player.Character.HumanoidRootPart.Position)
end

return EnemyService
