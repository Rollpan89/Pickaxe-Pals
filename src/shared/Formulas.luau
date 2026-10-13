-- Pure game math. It calls no Roblox services, so it runs in Studio and in the tests.
-- Every function takes the balance config as its first argument.

local Formulas = {}

-- Coins needed to finish the run that starts at `rebirths` rebirths.
function Formulas.coinRequirement(config, rebirths)
	return config.firstRunCoins * (1 + config.runCoinGrowth) ^ rebirths
end

-- Permanent ore value multiplier earned by rebirthing.
function Formulas.oreMultiplier(config, rebirths)
	return 1 + config.rebirthOreBonus * rebirths
end

-- Hours of effective mining, with no purchases, to finish one run.
function Formulas.runHours(config, rebirths)
	local income = config.baseIncomePerHour * Formulas.oreMultiplier(config, rebirths)
	return Formulas.coinRequirement(config, rebirths) / income
end

-- Hours with no purchases to finish the first `runs` runs.
function Formulas.totalHours(config, runs)
	local total = 0
	for rebirths = 0, runs - 1 do
		total = total + Formulas.runHours(config, rebirths)
	end
	return total
end

-- Effective mining hours in a day: active play plus idle mining while away.
function Formulas.effectiveHoursPerDay(config, handsFree)
	local cap = config.idleCapHours
	if handsFree then
		cap = config.idleCapHoursHandsFree
	end
	local idleHours = math.min(config.awayHoursPerSession, cap)
	return config.activeHoursPerDay + idleHours * config.idleRate
end

-- Product of the income passes the player owns.
function Formulas.incomeMultiplier(config, owned)
	local multiplier = 1
	if owned.oreDouble then
		multiplier = multiplier * config.passes.oreDouble
	end
	if owned.petSlots then
		multiplier = multiplier * config.passes.petSlots
	end
	if owned.palsClub then
		multiplier = multiplier * config.passes.palsClub
	end
	return multiplier
end

-- Average gain from timed boosts for a player who keeps them running.
function Formulas.boostFactor(config, owned)
	if owned.boosts then
		return 1 + config.boost.coverage * (config.boost.multiplier - 1)
	end
	return 1
end

-- Days to reach the final rebirth. `owned` is a table such as { oreDouble = true }.
function Formulas.daysToFinish(config, owned)
	owned = owned or {}
	local speed = Formulas.incomeMultiplier(config, owned) * Formulas.boostFactor(config, owned)
	local hoursPerDay = Formulas.effectiveHoursPerDay(config, owned.handsFree)
	return Formulas.totalHours(config, config.finalRebirth) / speed / hoursPerDay
end

-- Coins earned by pets while the player was away.
function Formulas.offlineCoins(config, coinsPerActiveHour, hoursAway, handsFree)
	local cap = config.idleCapHours
	if handsFree then
		cap = config.idleCapHoursHandsFree
	end
	return math.min(hoursAway, cap) * config.idleRate * coinsPerActiveHour
end

return Formulas
