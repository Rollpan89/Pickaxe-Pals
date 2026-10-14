-- A token bucket rate limiter, used to keep a client from asking faster than its gear allows.
-- Pure and clock-injected, so the tests can move time by hand instead of waiting.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- `ratePerSecond` tokens refill each second; `burst` is how many may bank up.
-- `clock` returns seconds (os.clock by default).
function RateLimiter.new(ratePerSecond, burst, clock)
	assert(ratePerSecond > 0, "ratePerSecond must be positive")
	local self = setmetatable({}, RateLimiter)
	self.clock = clock or os.clock
	self.rate = ratePerSecond
	self.burst = burst or math.max(1, math.ceil(ratePerSecond))
	self.tokens = self.burst
	self.lastRefill = self.clock()
	return self
end

-- Changes the allowed rate, for example after a pickaxe upgrade.
function RateLimiter:setRate(ratePerSecond, burst)
	assert(ratePerSecond > 0, "ratePerSecond must be positive")
	self.rate = ratePerSecond
	self.burst = burst or math.max(1, math.ceil(ratePerSecond))
	self.tokens = math.min(self.tokens, self.burst)
end

-- Spends one token. Returns false when the caller has to wait.
function RateLimiter:allow()
	local now = self.clock()
	local elapsed = math.max(0, now - self.lastRefill)
	self.lastRefill = now
	self.tokens = math.min(self.burst, self.tokens + elapsed * self.rate)
	if self.tokens < 1 then
		return false
	end
	self.tokens -= 1
	return true
end

return RateLimiter
