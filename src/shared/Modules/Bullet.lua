local create = function(startPos, direction, speed, ignore, onHit, lifetime)
	local bullet = Instance.new("Part")
	bullet.Size = Vector3.new(0.368, 0.436, 2)
	bullet.Material = Enum.Material.Neon
	bullet.Color = Color3.new(1, 1, 0)
	bullet.CanCollide = false
	bullet.Anchored = true
	bullet.CFrame = CFrame.new(startPos, startPos + direction)

	local attachment0 = Instance.new("Attachment", bullet)
	local attachment1 = Instance.new("Attachment", bullet)
	attachment1.Position = Vector3.new(0, 0, -0.2)

	local trail = Instance.new("Trail", bullet)
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = 0.2
	trail.Color = ColorSequence.new(Color3.new(1, 1, 0))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1)
	trail.MinLength = 0

	bullet.Parent = workspace

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { ignore, bullet }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local startTime = tick()
	local lastPos = startPos

	local heartbeat
	heartbeat = game:GetService("RunService").Heartbeat:Connect(function(dt)
		local elapsed = tick() - startTime
		if elapsed >= lifetime then
			heartbeat:Disconnect()
			bullet:Destroy()
			return
		end

		local distance = speed * dt
		local result = workspace:Raycast(lastPos, direction * distance, raycastParams)

		if result then
			bullet.CFrame = CFrame.new(result.Position, result.Position + direction)
			heartbeat:Disconnect()

			if onHit then
				onHit(result.Instance, result.Position)
			end

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
