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

-- Finds one ore record by id, across every layer.
function Formulas.ore(config, oreId)
	for _, layer in ipairs(config.layers) do
		for _, ore in ipairs(layer.ores) do
			if ore.id == oreId then
				return ore
			end
		end
	end
	return nil
end

-- Finds one pickaxe tier record by tier number.
function Formulas.pickaxe(config, tier)
	for _, pickaxe in ipairs(config.pickaxeTiers) do
		if pickaxe.tier == tier then
			return pickaxe
		end
	end
	return nil
end

-- Finds one backpack level record by level number.
function Formulas.backpack(config, level)
	for _, backpack in ipairs(config.backpackLevels) do
		if backpack.level == level then
			return backpack
		end
	end
	return nil
end

-- The next pickaxe up, or nil when the player already owns the best one.
function Formulas.nextPickaxeTier(config, tier)
	return Formulas.pickaxe(config, tier + 1)
end

-- The next backpack level up, or nil at the top.
function Formulas.nextBackpackLevel(config, level)
	return Formulas.backpack(config, level + 1)
end

-- Ore value in coins, including the permanent rebirth bonus.
function Formulas.oreValue(config, ore, rebirths)
	return ore.value * Formulas.oreMultiplier(config, rebirths)
end

-- Hits one ore node takes at a pickaxe tier.
function Formulas.hitsToBreak(config, ore, tier)
	local pickaxe = Formulas.pickaxe(config, tier)
	return math.max(1, math.ceil(ore.health / pickaxe.damage))
end

-- Seconds to break one ore node, ignoring travel and node respawns.
function Formulas.secondsPerNode(config, ore, tier)
	return Formulas.hitsToBreak(config, ore, tier) * Formulas.pickaxe(config, tier).cooldown
end

-- Coins per hour of uninterrupted mining on one ore type.
function Formulas.coinsPerHour(config, ore, tier, rebirths)
	return Formulas.oreValue(config, ore, rebirths)
		/ Formulas.secondsPerNode(config, ore, tier)
		* 3600
end

-- Seconds of mining on one ore type to earn `coins`.
function Formulas.secondsToEarn(config, coins, ore, tier, rebirths)
	return coins / (Formulas.coinsPerHour(config, ore, tier, rebirths) / 3600)
end

-- How much ore the backpack holds at a level.
function Formulas.backpackCapacity(config, level)
	return Formulas.backpack(config, level).capacity
end

-- Ore items currently carried.
function Formulas.backpackTotal(backpack)
	local total = 0
	for _, count in pairs(backpack) do
		total = total + count
	end
	return total
end

-- Coins a full backpack sells for.
function Formulas.sellValue(config, backpack, rebirths)
	local total = 0
	for oreId, count in pairs(backpack) do
		local ore = Formulas.ore(config, oreId)
		if ore then
			total = total + Formulas.oreValue(config, ore, rebirths) * count
		end
	end
	return total
end

return Formulas
