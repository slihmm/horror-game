--!strict
-- Per-key token bucket used to throttle client requests on the server.
export type RateLimiter = {
	Allow: (self: RateLimiter, key: any) -> boolean,
	Forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- capacity: burst size, refillPerSecond: sustained rate.
function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	local self = setmetatable({
		_capacity = capacity,
		_refill = refillPerSecond,
		_buckets = {} :: { [any]: { tokens: number, stamp: number } },
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter:Allow(key)
	local now = os.clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._capacity, stamp = now }
		self._buckets[key] = bucket
	end
	bucket.tokens = math.min(self._capacity, bucket.tokens + (now - bucket.stamp) * self._refill)
	bucket.stamp = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Forget(key)
	self._buckets[key] = nil
end

return RateLimiter
