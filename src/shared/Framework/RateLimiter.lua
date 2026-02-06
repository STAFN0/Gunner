-- =====================================================
-- STAFN0's Rate Limiter
-- Token bucket algorithm to prevent spam
-- =====================================================

local Types = require(script.Parent.Types)

export type RateLimiter = Types.RateLimiter

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxRequests: number, windowSeconds: number, inactiveThreshold: number?): RateLimiter
	return setmetatable({
		_capacity = maxRequests,
		_refillRate = maxRequests / windowSeconds,
		_buckets = {},
		_cleanupCounter = 0,
		_inactiveThreshold = inactiveThreshold or 3600,
		_maxBuckets = 10000,
	}, RateLimiter) :: any
end

function RateLimiter:Check(player: Player): (boolean, string?)
	local now = os.clock()
	local userId = player.UserId

	local bucketCount = 0
	for _ in pairs(self._buckets) do
		bucketCount += 1
	end

	if bucketCount > self._maxBuckets then
		self:_cleanupInactiveUsers(now)
	end

	if not self._buckets[userId] then
		self._buckets[userId] = {
			tokens = self._capacity - 1,
			lastRefill = now,
			firstSeen = now,
		}
		return true
	end

	local bucket = self._buckets[userId]
	local timePassed = now - bucket.lastRefill
	local tokensToAdd = timePassed * self._refillRate
	bucket.tokens = math.min(self._capacity, bucket.tokens + tokensToAdd)
	bucket.lastRefill = now

	if bucket.tokens >= 1 then
		bucket.tokens -= 1

		self._cleanupCounter += 1
		if self._cleanupCounter >= 100 then
			self._cleanupCounter = 0
			self:_cleanupInactiveUsers(now)
		end

		return true
	else
		local waitTime = (1 - bucket.tokens) / self._refillRate
		return false, string.format("rate limited, retry in %.1fs", waitTime)
	end
end

function RateLimiter:_cleanupInactiveUsers(now: number)
	local threshold = now - self._inactiveThreshold

	for userId, bucket in pairs(self._buckets) do
		if bucket.lastRefill < threshold then
			self._buckets[userId] = nil
		end
	end
end

function RateLimiter:Cleanup(player: Player)
	self._buckets[player.UserId] = nil
end

function RateLimiter:SetInactiveThreshold(seconds: number)
	assert(type(seconds) == "number" and seconds > 0, "threshold must be positive number")
	self._inactiveThreshold = seconds
end

function RateLimiter:SetMaxBuckets(max: number)
	assert(type(max) == "number" and max > 0, "max buckets must be positive number")
	self._maxBuckets = max
end

function RateLimiter:GetStats(player: Player): { tokens: number, capacity: number, refillRate: number }?
	local bucket = self._buckets[player.UserId]
	if not bucket then
		return nil
	end

	local now = os.clock()
	local timePassed = now - bucket.lastRefill
	local currentTokens = math.min(self._capacity, bucket.tokens + timePassed * self._refillRate)

	return {
		tokens = currentTokens,
		capacity = self._capacity,
		refillRate = self._refillRate,
	}
end

return RateLimiter
