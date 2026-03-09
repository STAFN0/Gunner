local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local function createImpactEffect(position, normal, hitPart)
	local sparks = Instance.new("ParticleEmitter")
	local sparkAttachment = Instance.new("Attachment")
	sparkAttachment.Parent = workspace.Terrain
	sparkAttachment.WorldPosition = position

	sparks.Parent = sparkAttachment
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(10, 20)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Brightness = 2
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.ZOffset = 0.1

	sparks:Emit(8)

	local impactLight = Instance.new("PointLight")
	impactLight.Parent = sparkAttachment
	impactLight.Brightness = 3
	impactLight.Color = Color3.fromRGB(255, 180, 80)
	impactLight.Range = 6

	TweenService:Create(impactLight, TweenInfo.new(0.15), { Brightness = 0 }):Play()

	local smoke = Instance.new("ParticleEmitter")
	smoke.Parent = sparkAttachment
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.3, 0.5)
	smoke.Speed = NumberRange.new(2, 4)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Rate = 0
	smoke.LightEmission = 0.2
	smoke.Rotation = NumberRange.new(-180, 180)
	smoke.RotSpeed = NumberRange.new(-40, 40)

	smoke:Emit(3)

	if hitPart:IsA("BasePart") and hitPart ~= sparkAttachment then
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Transparency = 0.3

		local decalPart = Instance.new("Part")
		decalPart.Size = Vector3.new(0.5, 0.5, 0.05)
		decalPart.Transparency = 1
		decalPart.CanCollide = false
		decalPart.Anchored = true
		decalPart.Massless = true
		decalPart.CFrame = CFrame.new(position, position + normal)
		decalPart.Parent = workspace

		decal.Parent = decalPart

		Debris:AddItem(decalPart, 15)
	end

	Debris:AddItem(sparkAttachment, 1)

	local impactSound = Instance.new("Sound")
	impactSound.SoundId = "rbxassetid://109598434966968"
	impactSound.Volume = 0.5
	impactSound.Parent = sparkAttachment
	impactSound:Play()

	Debris:AddItem(impactSound, 1)
end
local create = function(startPos, direction, speed, ignore, onHit, lifetime)
	local bullet = ReplicatedStorage.Assets.Bullet:Clone()
	bullet.Parent = workspace
	bullet.CFrame = CFrame.new(startPos, startPos + direction)

	local tracer = Instance.new("Beam")
	local attachment0 = Instance.new("Attachment")
	local attachment1 = Instance.new("Attachment")

	attachment0.Parent = bullet
	attachment1.Parent = bullet
	attachment1.Position = Vector3.new(0, 0, -3)

	tracer.Attachment0 = attachment0
	tracer.Attachment1 = attachment1
	tracer.Width0 = 0.15
	tracer.Width1 = 0.05
	tracer.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	tracer.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	tracer.FaceCamera = true
	tracer.LightEmission = 1
	tracer.LightInfluence = 0
	tracer.Texture = "rbxasset://textures/particles/smoke_main.dds"
	tracer.TextureMode = Enum.TextureMode.Stretch
	tracer.ZOffset = 0.1
	tracer.Parent = bullet

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 200, 100)
	light.Range = 8
	light.Parent = bullet

	TweenService:Create(light, TweenInfo.new(0.1), { Brightness = 0 }):Play()

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { ignore, bullet }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local startTime = tick()
	local lastPos = startPos
	local traveled = 0
	local maxDistance = speed * lifetime

	local heartbeat
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		local elapsed = tick() - startTime

		if elapsed >= lifetime then
			heartbeat:Disconnect()
			bullet:Destroy()
			return
		end

		local distance = speed * dt
		traveled = traveled + distance

		local result = workspace:Raycast(lastPos, direction * distance, raycastParams)

		if result then
			bullet.CFrame = CFrame.new(result.Position, result.Position + direction)
			heartbeat:Disconnect()

			createImpactEffect(result.Position, result.Normal, result.Instance)

			if onHit then
				onHit(result.Instance, result.Position)
			end

			task.wait(0.05)
			bullet:Destroy()
		else
			local newPos = lastPos + (direction * distance)
			bullet.CFrame = CFrame.new(newPos, newPos + direction)
			lastPos = newPos
		end
	end)

	return bullet
end

return create
