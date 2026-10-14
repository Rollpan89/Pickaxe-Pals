-- Balance numbers. These mirror the Inputs sheet of pickaxe-pals-economy-model.xlsx.
-- Later this file is generated from the spreadsheet; until then, change both together.
-- Runs on both sides and in the Lune tests, so it holds plain data only: no Roblox values.

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

	-- Layers. Sunny Burrow is the first playable layer; the rest arrive with their art.
	-- An ore is worth `value` coins and takes `health` points of damage to break.
	layers = {
		{
			id = "sunnyBurrow",
			name = "Sunny Burrow",
			unlockRebirth = 0,
			ores = {
				{
					id = "pebblePop",
					name = "Pebble Pop",
					health = 3,
					value = 8,
					respawnSeconds = 4,
				},
				{
					id = "copperDaisy",
					name = "Copper Daisy",
					health = 8,
					value = 24,
					respawnSeconds = 8,
				},
				{
					id = "honeyQuartz",
					name = "Honey Quartz",
					health = 20,
					value = 65,
					respawnSeconds = 15,
				},
			},
		},
	},

	-- Pickaxe tiers. A hit lands every `cooldown` seconds and deals `damage`.
	pickaxeTiers = {
		{ tier = 1, name = "Pebble Pick", damage = 1, cooldown = 0.5, cost = 0, unlockRebirth = 0 },
		{
			tier = 2,
			name = "Copper Pick",
			damage = 2,
			cooldown = 0.5,
			cost = 120,
			unlockRebirth = 0,
		},
		{
			tier = 3,
			name = "Honey Pick",
			damage = 3,
			cooldown = 0.45,
			cost = 1200,
			unlockRebirth = 0,
		},
		{
			tier = 4,
			name = "Quartz Pick",
			damage = 5,
			cooldown = 0.4,
			cost = 6000,
			unlockRebirth = 0,
		},
		{
			tier = 5,
			name = "Crystal Pick",
			damage = 8,
			cooldown = 0.35,
			cost = 30000,
			unlockRebirth = 0,
		},
	},

	-- Backpack levels: how much ore can be carried before selling.
	backpackLevels = {
		{ level = 1, name = "Starter Satchel", capacity = 50, cost = 0 },
		{ level = 2, name = "Canvas Pack", capacity = 150, cost = 400 },
		{ level = 3, name = "Hauler Pack", capacity = 500, cost = 2000 },
		{ level = 4, name = "Big Rig Pack", capacity = 1500, cost = 10000 },
	},

	-- Server-side checks on what a client asks for
	mining = {
		nodeRangeStuds = 18, -- how far from a node a hit is accepted
		sellRangeStuds = 14, -- how close the Sell Pad starts buying
		sellIntervalSeconds = 0.5, -- how often the Sell Pad checks who is standing on it
		hitRateTolerance = 1.25, -- hits per second allowed above the pickaxe's own rate
		hitBurst = 3, -- hits a player may bank before the rate limiter slows them
	},

	-- Saving. `storeName` is the DataStore name every player's save lives under, so it must
	-- not change once the game is live. `useMockInStudio` keeps a Studio playtest off the real
	-- DataStore: leave it off while you are testing that progress survives a rejoin.
	saving = {
		storeName = "PickaxePals_PlayerData",
		useMockInStudio = false,
	},

	-- The world itself is not here: every placeable object is authored in the place and says what
	-- it is with a `kind` attribute. src/shared/Properties owns that vocabulary.

	-- RemoteEvent names, created by the server under ReplicatedStorage.Remotes
	remotes = {
		mineHit = "MineHit",
		buyUpgrade = "BuyUpgrade",
		requestState = "RequestState",
		stateChanged = "StateChanged",
		notify = "Notify",
	},
}
