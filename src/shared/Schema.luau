-- The saved player profile: the shape of it, its version, and the rules for opening an old
-- or damaged save. Pure, so the tests cover every case without a DataStore.
--
-- DataService owns the store; this module owns what a profile looks like. The shape is the
-- architecture document's PlayerData. Like Formulas, the entry points take the balance config
-- first, so nothing here reaches for a Roblox service and the whole file runs in the tests.

local Schema = {}

-- Bump this and add the matching entry to Schema.upgrades whenever the template changes.
Schema.version = 1

-- A new profile is a deep copy of this. The store fills in missing string keys from it by
-- name, so a save written before a key existed gets the template value when it is next opened.
Schema.template = {
	version = 1,
	coins = 0,
	gems = 0,
	rebirths = 0,
	pickaxeTier = 1,
	backpackLevel = 1,
	pets = {}, -- [petId] = { normal = n, shiny = n }
	equipped = {},
	pity = {}, -- [eggId] = hatches since the last guaranteed pet
	daily = { lastLoginDay = 0, streak = 0, quests = {} },
	lastSeen = 0,
	receipts = {}, -- recent purchase ids, newest last
	flags = {},
}

-- `Schema.upgrades[version] = function(data, template)` upgrades a save to `version + 1`.
-- The chain is empty while version 1 is the only format that has ever been written.
Schema.upgrades = {}

-- Ceilings that keep a damaged or hand-edited save from breaking the game. They are not
-- balance numbers: real progress stays far below them.
Schema.limits = {
	coins = 1e15,
	gems = 1e9,
	timestamp = 4102444800, -- 2100-01-01, so a clock or a save cannot push `lastSeen` far ahead
	entry = 1e9, -- ceiling for one ore or pet count
	receipts = 50, -- purchase ids kept per profile
	list = 64, -- entries kept in an array field such as `equipped`
	keyLength = 64, -- longest allowed table key
}

local function isFinite(value)
	return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

-- A whole number inside a range. Anything unusable becomes `fallback`, so one bad field never
-- costs the player the rest of the profile.
local function whole(value, minimum, maximum, fallback)
	if not isFinite(value) then
		return fallback
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

-- DataStore keys are JSON object keys, so only strings survive a save. Dropping everything
-- else here is what stops a corrupted table from failing the next write.
local function isSaveKey(key)
	return type(key) == "string"
		and #key > 0
		and #key <= Schema.limits.keyLength
		and not key:find("%c")
end

local function cleanMap(input, cleanValue)
	local output = {}
	if type(input) ~= "table" then
		return output
	end
	for key, value in pairs(input) do
		if isSaveKey(key) then
			local cleaned = cleanValue(value)
			if cleaned ~= nil then
				output[key] = cleaned
			end
		end
	end
	return output
end

local function cleanList(input, cleanValue, limit)
	local output = {}
	local seen = {}
	if type(input) ~= "table" then
		return output
	end
	for _, value in ipairs(input) do
		local cleaned = cleanValue(value)
		if cleaned ~= nil and not seen[cleaned] then
			seen[cleaned] = true
			output[#output + 1] = cleaned
		end
	end
	if #output <= limit then
		return output
	end
	-- These lists keep their newest entries at the end, so trim from the front.
	local trimmed = {}
	for index = #output - limit + 1, #output do
		trimmed[#trimmed + 1] = output[index]
	end
	return trimmed
end

local function cleanCount(value)
	if not isFinite(value) then
		return nil
	end
	return math.clamp(math.floor(value), 0, Schema.limits.entry)
end

local function cleanString(value)
	if type(value) ~= "string" or #value == 0 or #value > Schema.limits.keyLength then
		return nil
	end
	if value:find("%c") then
		return nil
	end
	return value
end

local function cleanPets(pets)
	return cleanMap(pets, function(entry)
		if type(entry) == "number" then -- a pet written as a plain count is forgiven
			return { normal = cleanCount(entry) or 0, shiny = 0 }
		end
		if type(entry) ~= "table" then
			return nil
		end
		return { normal = cleanCount(entry.normal) or 0, shiny = cleanCount(entry.shiny) or 0 }
	end)
end

local function cleanFlags(flags)
	return cleanMap(flags, function(value)
		if type(value) == "boolean" then
			return value
		end
		return nil
	end)
end

local function highest(list, field)
	local highestValue = nil
	for _, entry in ipairs(list) do
		local value = entry[field]
		if isFinite(value) and (highestValue == nil or value > highestValue) then
			highestValue = value
		end
	end
	return highestValue
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deepCopy(entry)
	end
	return copy
end

-- A fresh profile. The store deep-copies the template itself; the tests and any tooling want
-- one of their own.
function Schema.new()
	return deepCopy(Schema.template)
end

-- Fills in values a save predates, without touching anything it already has.
function Schema.reconcile(target, template)
	for key, value in pairs(template) do
		local existing = target[key]
		if type(value) == "table" then
			if type(existing) ~= "table" then
				target[key] = deepCopy(value)
			else
				Schema.reconcile(existing, value)
			end
		elseif existing == nil then
			target[key] = value
		end
	end
	return target
end

-- Coerces a profile into the template's shape. With the prune at the end this is a real
-- whitelist: only the keys the template still has are saved, so a profile stays small and
-- whatever a retired feature left behind is dropped instead of being written back forever.
function Schema.sanitize(config, data)
	local limits = Schema.limits

	data.coins = whole(data.coins, 0, limits.coins, 0)
	data.gems = whole(data.gems, 0, limits.gems, 0)
	data.rebirths = whole(data.rebirths, 0, config.finalRebirth, 0)
	data.pickaxeTier = whole(data.pickaxeTier, 1, highest(config.pickaxeTiers, "tier") or 1, 1)
	data.backpackLevel =
		whole(data.backpackLevel, 1, highest(config.backpackLevels, "level") or 1, 1)
	data.lastSeen = whole(data.lastSeen, 0, limits.timestamp, 0)

	data.pets = cleanPets(data.pets)
	data.pity = cleanMap(data.pity, cleanCount)
	data.equipped = cleanList(data.equipped, cleanString, limits.list)
	data.receipts = cleanList(data.receipts, cleanString, limits.receipts)
	data.flags = cleanFlags(data.flags)

	local daily = data.daily
	if type(daily) ~= "table" then
		daily = {}
	end
	data.daily = {
		lastLoginDay = whole(daily.lastLoginDay, 0, limits.timestamp, 0),
		streak = whole(daily.streak, 0, limits.entry, 0),
		quests = cleanMap(daily.quests, cleanCount),
	}

	-- The whitelist finishes its job here. The tables above were rebuilt from scratch, so only
	-- the top level can still be carrying a field the template does not have.
	for key in pairs(data) do
		if Schema.template[key] == nil then
			data[key] = nil
		end
	end

	data.version = Schema.version
	return data
end

-- Runs the upgrade functions in order from `fromVersion` to `toVersion`. A missing step is
-- logged rather than fatal: reconcile and sanitize still shape whatever comes out.
function Schema.runUpgrades(data, fromVersion, toVersion, upgrades, template)
	for version = fromVersion, toVersion - 1 do
		local upgrade = upgrades[version]
		if upgrade then
			upgrade(data, template)
		else
			warn(string.format("[Schema] no upgrade from version %d", version))
		end
		data.version = version + 1
	end
	return data
end

-- The one call DataService makes: returns the profile to use, or nil and a reason that keeps
-- the player out. `data` is changed in place, because that is the table the store will save.
function Schema.prepare(config, data)
	if type(data) ~= "table" then
		return nil, "Your save could not be read."
	end

	local version = tonumber(data.version)
	if not isFinite(version) then
		version = 1
	end
	version = math.floor(version)
	if version < 1 then
		version = 1
	end
	if version > Schema.version then
		-- Never downgrade a save: a newer build would lose whatever this one cannot see.
		return nil, "Your save is from a newer version of the game."
	end

	Schema.runUpgrades(data, version, Schema.version, Schema.upgrades, Schema.template)
	Schema.reconcile(data, Schema.template)
	Schema.sanitize(config, data)
	return data
end

-- Seconds since the player was last online, read from the save. Zero for a new profile and
-- never negative, so moving a device clock forward cannot mint offline earnings.
function Schema.awaySeconds(data, now)
	local lastSeen = data and tonumber(data.lastSeen) or 0
	if not isFinite(lastSeen) or lastSeen <= 0 then
		return 0
	end
	return math.max(0, math.floor(now - lastSeen))
end

return Schema
