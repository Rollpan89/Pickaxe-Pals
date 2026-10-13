-- Balance numbers. These mirror the Inputs sheet of pickaxe-pals-economy-model.xlsx.
-- Later this file is generated from the spreadsheet; until then, change both together.

return {
	-- Rebirth curve
	firstRunCoins = 19000,
	runCoinGrowth = 0.25, -- each run needs 25% more coins than the one before
	baseIncomePerHour = 20000, -- coins per effective hour at rebirth 0
	rebirthOreBonus = 0.5, -- ore value multiplier = 1 + 0.5 x rebirths
	finalRebirth = 20, -- the game counts as finished here

	-- Play pattern assumed by the model
	activeHoursPerDay = 1,
	idleRate = 0.5, -- pets mine at half rate while the player is away
	idleCapHours = 2,
	idleCapHoursHandsFree = 12,
	awayHoursPerSession = 4,

	-- Purchases (multipliers on ore income)
	passes = {
		oreDouble = 2.0,
		petSlots = 1.4,
		palsClub = 1.2,
	},
	boost = {
		multiplier = 2.0,
		coverage = 0.4, -- share of mining time a heavy spender keeps a boost running
	},
}
