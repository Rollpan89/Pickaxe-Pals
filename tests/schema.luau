-- Schema: opening new, old, damaged and impossible saves. Pure code, so it is checked here
-- rather than in Studio.

local Config = require("../src/shared/Config")
local Schema = require("../src/shared/Schema")

-- Every key path in a table, so a missing or extra field shows up as a difference.
local function keyPaths(data, prefix, names)
	names = names or {}
	for key, value in pairs(data) do
		local name = prefix .. tostring(key)
		names[#names + 1] = name
		if type(value) == "table" then
			keyPaths(value, name .. ".", names)
		end
	end
	table.sort(names)
	return names
end

return function(t)
	local function prepare(data)
		return Schema.prepare(Config, data)
	end

	-- A brand new profile
	local fresh = Schema.new()
	t.equal("a new profile starts with no coins", fresh.coins, 0)
	t.equal("a new profile carries the current version", fresh.version, Schema.version)
	fresh.pets.spot = 1
	fresh.daily.quests.mine = 1
	t.equal("Schema.new() does not share the template's pets", Schema.template.pets.spot, nil)
	t.equal(
		"Schema.new() does not share the template's quests",
		Schema.template.daily.quests.mine,
		nil
	)
	t.equal("a new profile opens", prepare(Schema.new()) ~= nil, true)

	-- The whitelist in sanitize has to cover the template, or a field would be dropped on
	-- every save. Comparing against an empty table shows exactly what sanitize writes.
	local templateKeys = table.concat(keyPaths(Schema.template, ""), ",")
	t.equal(
		"sanitize writes exactly the template's keys",
		table.concat(keyPaths(Schema.sanitize(Config, {}), ""), ","),
		templateKeys
	)

	-- The case above starts from an empty table, so it only proves sanitize writes the keys the
	-- template has. A save that already carries a field the template dropped is the one that
	-- catches sanitize normalising what it knows and leaving everything else in place.
	local retired = prepare({
		version = 1,
		coins = 5,
		backpack = { pebblePop = 3 }, -- carried ore lives in the session; it is not saved
		retiredBoost = true,
		daily = { streak = 2, retiredQuest = 1 },
	})
	t.equal(
		"a retired top-level field is dropped, not written back",
		table.concat(keyPaths(retired, ""), ","),
		templateKeys
	)
	t.equal("a retired nested field is dropped too", retired.daily.retiredQuest, nil)
	t.equal("carried ore never reaches the save", retired.backpack, nil)
	t.equal("the fields that do exist survive the prune", retired.coins, 5)

	-- Damaged values
	local junk = prepare({
		version = 1,
		coins = -50,
		gems = "lots",
		rebirths = 99,
		pickaxeTier = 0.5,
		backpackLevel = 99,
		lastSeen = -1,
		pets = "nope",
		equipped = "nope",
		receipts = { "a", "a", 5, "" },
		flags = { tutorialDone = true, junk = "yes" },
		daily = { streak = 3.7 },
	})
	t.equal("a negative balance is clamped to 0", junk.coins, 0)
	t.equal("gems that are not a number become 0", junk.gems, 0)
	t.equal("rebirths are capped at the final rebirth", junk.rebirths, Config.finalRebirth)
	t.equal("a fractional pickaxe tier floors to the first tier", junk.pickaxeTier, 1)
	t.equal("a backpack level past the top is capped", junk.backpackLevel, #Config.backpackLevels)
	t.equal("a negative lastSeen is clamped to 0", junk.lastSeen, 0)
	t.equal("text where a table belongs becomes an empty table", type(junk.pets), "table")
	t.equal("receipt duplicates and non-strings are dropped", #junk.receipts, 1)
	t.equal("a true flag survives", junk.flags.tutorialDone, true)
	t.equal("a flag that is not a boolean is dropped", junk.flags.junk, nil)
	t.equal("a fractional streak floors", junk.daily.streak, 3)

	local weird = prepare({ version = 1, coins = 0 / 0, gems = 1 / 0 })
	t.equal("NaN coins become 0", weird.coins, 0)
	t.equal("infinite gems become 0", weird.gems, 0)

	-- Keys a DataStore cannot hold
	local keys = prepare({
		version = 1,
		pets = {
			[1] = { normal = 2 },
			sprout = { normal = 1, shiny = 2 },
			[""] = { normal = 9 },
		},
	})
	t.equal("a numeric table key is dropped", keys.pets[1], nil)
	t.equal("a good pet keeps its normal count", keys.pets.sprout.normal, 1)
	t.equal("a good pet keeps its shiny count", keys.pets.sprout.shiny, 2)
	t.equal("an empty table key is dropped", keys.pets[""], nil)

	local numberPet = prepare({ version = 1, pets = { spot = 4 } })
	t.equal("a pet saved as a plain count is forgiven", numberPet.pets.spot.normal, 4)

	-- The upgrade chain
	local order = {}
	local upgrades = {
		[1] = function(data)
			order[#order + 1] = "1->2"
			data.coins = 10
		end,
		[2] = function(data)
			order[#order + 1] = "2->3"
			data.coins += 5
		end,
	}
	local upgraded = Schema.runUpgrades({ version = 1, coins = 0 }, 1, 3, upgrades, Schema.template)
	t.equal("upgrades run from the oldest version first", order[1], "1->2")
	t.equal("upgrades run one version at a time", order[2], "2->3")
	t.equal("each upgrade sees the one before it", upgraded.coins, 15)
	t.equal("the save ends at the target version", upgraded.version, 3)

	local gap = Schema.runUpgrades({ version = 1 }, 1, 3, { [1] = function() end }, Schema.template)
	t.equal("a missing upgrade step still reaches the target version", gap.version, 3)

	-- Refusals
	local newer, newerReason = prepare({ version = Schema.version + 1, coins = 5 })
	t.equal("a save from a newer game is refused", newer, nil)
	t.equal("the refusal gives a reason", type(newerReason), "string")

	local nothing, nothingReason = Schema.prepare(Config, nil)
	t.equal("a missing profile is refused", nothing, nil)
	t.equal("that refusal gives a reason too", type(nothingReason), "string")

	local ancient = prepare({ coins = 7 })
	t.equal("a save with no version opens as version 1", ancient.version, Schema.version)
	t.equal("its coins survive", ancient.coins, 7)

	-- Reconcile fills in what a save predates
	local profile = Schema.new()
	profile.coins = 500
	local richer = Schema.new()
	richer.newThing = { level = 0 }
	Schema.reconcile(profile, richer)
	t.equal("reconcile adds a key the template gained", profile.newThing.level, 0)
	t.equal("reconcile leaves existing values alone", profile.coins, 500)

	-- Receipts are capped to the newest ones
	local many = { version = 1, receipts = {} }
	for index = 1, Schema.limits.receipts + 5 do
		many.receipts[index] = string.format("receipt-%d", index)
	end
	local capped = prepare(many)
	t.equal("receipts keep only the newest entries", #capped.receipts, Schema.limits.receipts)
	t.equal(
		"the newest receipt is one of the ones kept",
		capped.receipts[#capped.receipts],
		string.format("receipt-%d", Schema.limits.receipts + 5)
	)

	-- Offline time
	t.equal("a new profile has no away time", Schema.awaySeconds(Schema.new(), 1000), 0)
	t.equal("away time counts from lastSeen", Schema.awaySeconds({ lastSeen = 1000 }, 4600), 3600)
	t.equal(
		"a clock behind lastSeen cannot go negative",
		Schema.awaySeconds({ lastSeen = 5000 }, 1000),
		0
	)
	t.equal("a fractional away time floors", Schema.awaySeconds({ lastSeen = 10 }, 15.9), 5)
end
