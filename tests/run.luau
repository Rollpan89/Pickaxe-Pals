-- Tests for everything that runs without Studio. Run from the project folder with:
-- lune run tests/run
--
-- Balance numbers come from pickaxe-pals-economy-model.xlsx (sheet "Scenarios"). The suites at
-- the bottom of this file live in tests/schema.luau (the saved profile and its version
-- upgrades), tests/lifecycle.luau (the real DataService against a stand-in ProfileStore),
-- tests/mining.luau (the real MiningService against stand-in services) and tests/world.luau
-- (what WorldBuilder finds in a place and what it says about what it cannot, on real Instances).

local Formulas = require("../src/shared/Formulas")
local Config = require("../src/shared/Config")
local Properties = require("../src/shared/Properties")
local RateLimiter = require("../src/shared/RateLimiter")
local Types = require("../src/shared/Types")

local failures = 0

local function check(name, actual, expected, tolerance)
	if math.abs(actual - expected) <= tolerance then
		print(string.format("ok   %s", name))
	else
		failures = failures + 1
		print(
			string.format(
				"FAIL %s: got %.4f, expected %.4f (+/- %.4f)",
				name,
				actual,
				expected,
				tolerance
			)
		)
	end
end

local function checkTrue(name, condition)
	if condition then
		print(string.format("ok   %s", name))
	else
		failures = failures + 1
		print(string.format("FAIL %s: expected a true value", name))
	end
end

local function checkEquals(name, actual, expected)
	if actual == expected then
		print(string.format("ok   %s", name))
	else
		failures = failures + 1
		print(
			string.format(
				"FAIL %s: got %s, expected %s",
				name,
				tostring(actual),
				tostring(expected)
			)
		)
	end
end

-- Rebirth curve
check("coin requirement, first run", Formulas.coinRequirement(Config, 0), 19000, 0.001)
check("coin requirement, second run", Formulas.coinRequirement(Config, 1), 23750, 0.001)
check("ore multiplier at rebirth 4", Formulas.oreMultiplier(Config, 4), 3, 0.001)

-- Days to Rebirth 20 for each purchase level in the Scenarios sheet
check("free player", Formulas.daysToFinish(Config, {}), 21.12, 0.01)
check("2x Ore pass", Formulas.daysToFinish(Config, { oreDouble = true }), 10.56, 0.01)
check(
	"+ Pet Slots pass",
	Formulas.daysToFinish(Config, { oreDouble = true, petSlots = true }),
	7.54,
	0.01
)
check(
	"+ Pals Club",
	Formulas.daysToFinish(Config, { oreDouble = true, petSlots = true, palsClub = true }),
	6.28,
	0.01
)
check(
	"+ Hands-Free Helper",
	Formulas.daysToFinish(
		Config,
		{ oreDouble = true, petSlots = true, palsClub = true, handsFree = true }
	),
	4.19,
	0.01
)
check(
	"+ Timed boosts (fully stacked)",
	Formulas.daysToFinish(
		Config,
		{ oreDouble = true, petSlots = true, palsClub = true, handsFree = true, boosts = true }
	),
	2.99,
	0.01
)

-- Offline earnings: 2 hour cap by default, 12 hours with Hands-Free Helper
check("offline, short trip", Formulas.offlineCoins(Config, 10000, 1, false), 5000, 0.001)
check("offline, capped at 2 hours", Formulas.offlineCoins(Config, 10000, 8, false), 10000, 0.001)
check("offline, Hands-Free cap", Formulas.offlineCoins(Config, 10000, 20, true), 60000, 0.001)

-- Shared modules load in Lune, which is what keeps them free of Roblox calls
checkTrue("Types module loads", type(Types) == "table")
checkTrue("RateLimiter module loads", type(RateLimiter) == "table")
checkTrue("Properties module loads", type(Properties) == "table")

-- Config sanity: the two sides of the game look the same data up by id, so ids must be
-- unique and the tiers must run in order from 1
local seenOres = {}
local oreCount = 0
for _, layer in ipairs(Config.layers) do
	for _, ore in ipairs(layer.ores) do
		oreCount = oreCount + 1
		seenOres[ore.id] = (seenOres[ore.id] or 0) + 1
	end
end
local duplicateOres = 0
for _, count in pairs(seenOres) do
	if count > 1 then
		duplicateOres = duplicateOres + 1
	end
end
checkEquals("ore ids are unique", duplicateOres, 0)
checkEquals(
	"pickaxe tiers run from 1 without gaps",
	#Config.pickaxeTiers,
	Config.pickaxeTiers[#Config.pickaxeTiers].tier
)
checkEquals(
	"backpack levels run from 1 without gaps",
	#Config.backpackLevels,
	Config.backpackLevels[#Config.backpackLevels].level
)

local seenRemotes = {}
local duplicateRemotes = 0
for _, name in pairs(Config.remotes) do
	if seenRemotes[name] then
		duplicateRemotes = duplicateRemotes + 1
	end
	seenRemotes[name] = true
end
checkEquals("remote names are unique", duplicateRemotes, 0)

local increasingCosts = true
for index = 2, #Config.pickaxeTiers do
	if Config.pickaxeTiers[index].cost <= Config.pickaxeTiers[index - 1].cost then
		increasingCosts = false
	end
end
checkEquals("each pickaxe costs more than the last", increasingCosts, true)

-- Layer 1 mining, tied back to the economy model
local layerOne = Config.layers[1]
local pebble = Formulas.ore(Config, "pebblePop")
checkEquals("the first pickaxe is free", Formulas.pickaxe(Config, 1).cost, 0)
checkEquals("Pebble Pop breaks in three tier-1 hits", Formulas.hitsToBreak(Config, pebble, 1), 3)
checkEquals(
	"Honey Quartz breaks in three tier-5 hits",
	Formulas.hitsToBreak(Config, Formulas.ore(Config, "honeyQuartz"), 5),
	3
)
check(
	"tier 1 on Pebble Pop matches the model's base income",
	Formulas.coinsPerHour(Config, pebble, 1, 0),
	Config.baseIncomePerHour,
	Config.baseIncomePerHour * 0.1
)

-- The design document wants the first upgrade inside 30 seconds of joining. Travel time is
-- not counted, so the mining budget leaves a few seconds for walking to a node.
local firstUpgrade = Formulas.nextPickaxeTier(Config, 1)
checkTrue(
	"the first pickaxe upgrade fits in 30 seconds of mining",
	Formulas.secondsToEarn(Config, firstUpgrade.cost, pebble, 1, 0) <= 30
)

local paysMore = true
local previousRate = 0
for _, ore in ipairs(layerOne.ores) do
	local rate = Formulas.coinsPerHour(Config, ore, 1, 0)
	if rate <= previousRate then
		paysMore = false
	end
	previousRate = rate
end
checkEquals("later ores in a layer pay more per hour", paysMore, true)

-- Ore value, the backpack and selling
check(
	"Honey Quartz is worth 65 coins at rebirth 0",
	Formulas.oreValue(Config, Formulas.ore(Config, "honeyQuartz"), 0),
	65,
	0.001
)
check("ore value doubles at rebirth 2", Formulas.oreValue(Config, pebble, 2), 16, 0.001)
checkEquals("the starter backpack holds 50 ore", Formulas.backpackCapacity(Config, 1), 50)
check(
	"a mixed backpack sells for its contents",
	Formulas.sellValue(Config, { pebblePop = 10, honeyQuartz = 2 }, 0),
	210,
	0.001
)
check(
	"selling at rebirth 2 pays the permanent bonus",
	Formulas.sellValue(Config, { honeyQuartz = 2 }, 2),
	260,
	0.001
)
checkEquals("an empty backpack sells for nothing", Formulas.sellValue(Config, {}, 0), 0)
checkEquals(
	"backpack total adds every ore",
	Formulas.backpackTotal({ pebblePop = 3, copperDaisy = 4 }),
	7
)
checkEquals(
	"the best pickaxe has no next tier",
	Formulas.nextPickaxeTier(Config, #Config.pickaxeTiers),
	nil
)
checkEquals(
	"the biggest backpack has no next level",
	Formulas.nextBackpackLevel(Config, #Config.backpackLevels),
	nil
)

-- The hit rate limiter: a client mining flat out at its own tier's pace is never throttled,
-- and a client asking faster than its gear allows is
local clock = { now = 0 }
local function fakeClock()
	return clock.now
end

local burst = RateLimiter.new(2, 3, fakeClock)
checkTrue("the limiter allows a burst", burst:allow() and burst:allow() and burst:allow())
checkEquals("the limiter blocks past the burst", burst:allow(), false)
clock.now += 0.5
checkTrue("the limiter refills over time", burst:allow())
checkEquals("the refilled token is spent", burst:allow(), false)
clock.now += 10
checkTrue(
	"refilling stops at the burst size",
	burst:allow() and burst:allow() and burst:allow() and not burst:allow()
)

burst:setRate(10, 2)
clock.now += 1
checkTrue("setRate refills at the new rate", burst:allow() and burst:allow())

local neverThrottled = true
for _, pickaxe in ipairs(Config.pickaxeTiers) do
	local paced = { now = 0 }
	local rate = (1 / pickaxe.cooldown) * Config.mining.hitRateTolerance
	local limiter = RateLimiter.new(rate, Config.mining.hitBurst, function()
		return paced.now
	end)
	for _ = 1, 60 do
		paced.now += pickaxe.cooldown
		if not limiter:allow() then
			neverThrottled = false
		end
	end
end
checkEquals("mining at the pickaxe's own pace is never rate limited", neverThrottled, true)

-- The saving suites report through the same three helpers, so one command still covers
-- everything the game can check without a running Roblox server.
local t = {
	near = check,
	equal = checkEquals,
	isTrue = checkTrue,
}

require("./schema")(t)
require("./lifecycle")(t)
require("./mining")(t)
require("./world")(t)

if failures > 0 then
	error(string.format("%d test(s) failed", failures))
end
print("All tests passed.")
