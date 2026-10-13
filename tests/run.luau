-- Tests for the shared game math. Run from the project folder with: lune run tests/run
-- Expected values come from pickaxe-pals-economy-model.xlsx (sheet "Scenarios").

local Formulas = require("../src/shared/Formulas")
local Config = require("../src/shared/Config")

local failures = 0

local function check(name, actual, expected, tolerance)
	if math.abs(actual - expected) <= tolerance then
		print(string.format("ok   %s", name))
	else
		failures = failures + 1
		print(string.format("FAIL %s: got %.4f, expected %.4f (+/- %.4f)", name, actual, expected, tolerance))
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
	Formulas.daysToFinish(Config, { oreDouble = true, petSlots = true, palsClub = true, handsFree = true }),
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

if failures > 0 then
	error(string.format("%d test(s) failed", failures))
end
print("All tests passed.")
