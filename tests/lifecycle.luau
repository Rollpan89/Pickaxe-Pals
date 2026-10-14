-- The saving lifecycle, driven through the real DataService with a stand-in for ProfileStore
-- and for the Roblox globals it calls. This is where the architecture document's shutdown
-- rule lives: a server going down must still save every profile that is open.

local task = require("@lune/task")

local Config = require("../src/shared/Config")
local Schema = require("../src/shared/Schema")

local RobloxStub = require("./support/roblox_stub")
local FakeProfileStore = require("./support/fake_profilestore")

local sharedModules = {
	["shared.Config"] = Config,
	["shared.Schema"] = Schema,
}

-- A fresh server: the stub services, a recording store, and DataService loaded the way the game
-- loads it. `preJoin` lists { userId, name } pairs who are already in before start runs.
local function newServer(preJoin)
	local environment = RobloxStub.newEnvironment()
	local module, fake = FakeProfileStore.new()

	local service = RobloxStub.loadModule("src/server/DataService.luau", sharedModules, environment)
	local loaded = {}

	for _, entry in ipairs(preJoin or {}) do
		environment:join(entry[1], entry[2])
	end

	service.start({
		profileStore = module,
		onLoaded = function(player)
			loaded[#loaded + 1] = player.Name
		end,
	})

	return { environment = environment, fake = fake, service = service, loaded = loaded }
end

return function(t)
	-- Joining
	local server = newServer()
	t.equal(
		"the store is created with the configured name",
		server.fake.storeName,
		Config.saving.storeName
	)
	t.equal("the store is created once", server.fake.newCalls, 1)
	t.equal("the store is given the schema template", server.fake.template, Schema.template)

	local player = server.environment:join(1, "Newcomer")
	local data = server.service.get(player)
	t.equal("a joining player has a loaded profile", data ~= nil, true)
	t.equal("the profile starts empty", data.coins, 0)
	t.equal("the profile carries the current version", data.version, Schema.version)
	t.equal("the profile is keyed by user id", server.fake.profiles["1"].Key, "1")
	t.equal("the profile is linked to the user id", server.fake.profiles["1"].userId, 1)
	t.equal("one session was started", server.fake.records["1"].startSession, 1)
	t.equal("the client was sent one first state", #server.loaded, 1)

	local cancel = server.fake.records["1"].cancel
	t.equal("a load is not cancelled while the player is here", cancel(), false)

	-- Playing, then leaving
	data.coins = 250
	data.pickaxeTier = 2
	server.environment:leave(player)

	local profile = server.fake.profiles["1"]
	t.equal("leaving ends the session", server.fake.records["1"].endSession, 1)
	t.equal("the coins are on the profile the store holds", profile.Data.coins, 250)
	t.equal("the pickaxe upgrade is saved too", profile.Data.pickaxeTier, 2)
	t.equal("lastSeen is written on the way out", profile.Data.lastSeen > 0, true)
	t.equal("a player who left has no profile in memory", server.service.get(player) ~= nil, false)
	t.equal("the load is cancelled once the player has left", cancel(), true)

	server.service.release(player)
	t.equal(
		"releasing twice does not end the session twice",
		server.fake.records["1"].endSession,
		1
	)

	-- A returning player whose save has been damaged
	server.fake.saved["2"] = {
		version = 1,
		coins = -80,
		gems = "lots",
		rebirths = 999,
		pets = { sprout = { normal = 3, shiny = 1 }, [4] = { normal = 1 } },
		receipts = { "r1", "r1", 7 },
	}
	local returning = server.environment:join(2, "Returning")
	local repaired = server.service.get(returning)
	t.equal("a returning player's save is opened", repaired ~= nil, true)
	t.equal("a negative balance is repaired on load", repaired.coins, 0)
	t.equal("gems that are not a number are repaired", repaired.gems, 0)
	t.equal("too many rebirths are capped on load", repaired.rebirths, Config.finalRebirth)
	t.equal("a good pet survives the repair", repaired.pets.sprout.normal, 3)
	t.equal("a pet key the store cannot hold is dropped", repaired.pets[4], nil)
	t.equal("receipt duplicates are dropped on load", #repaired.receipts, 1)

	-- A profile that will not load, and one written by a newer game
	server.fake.refuse["3"] = true
	local refused = server.environment:join(3, "Refused")
	t.equal(
		"a player whose save will not load gets no session",
		server.service.get(refused) ~= nil,
		false
	)
	t.equal(
		"that player is told why",
		server.environment.kicks[3],
		"Could not load your save. Please rejoin."
	)

	server.fake.saved["4"] = { version = Schema.version + 1, coins = 500 }
	local future = server.environment:join(4, "Future")
	t.equal("a save from a newer game is not loaded", server.service.get(future) ~= nil, false)
	t.equal("its lock is released rather than left held", server.fake.records["4"].endSession, 1)
	t.equal(
		"the player is told the save is too new",
		string.find(server.environment.kicks[4] or "", "newer version") ~= nil,
		true
	)

	-- Another server taking the session: the player has to rejoin
	local stolen = server.environment:join(5, "Stolen")
	server.fake.profiles["5"].OnSessionEnd:Fire()
	t.equal("a session taken elsewhere drops the profile", server.service.get(stolen) ~= nil, false)
	t.equal("that player is asked to rejoin", server.environment.kicks[5] ~= nil, true)

	-- Critical saves, the kind a purchase needs
	local buyer = server.environment:join(6, "Buyer")
	server.service.save(buyer)
	t.equal("a critical save reaches the store", server.fake.records["6"].save, 1)
	server.environment:leave(buyer)
	server.service.save(buyer)
	t.equal("saving after the player left does nothing", server.fake.records["6"].save, 1)

	-- A player who was already in the server when DataService started
	local early = newServer({ { 21, "EarlyBird" } })
	task.wait()
	t.equal(
		"a player already in the server is loaded at start",
		early.service.get(early.environment.players[1]) ~= nil,
		true
	)

	-- The shutdown path, which the document calls the case most likely to lose progress
	local closing = newServer()
	local one = closing.environment:join(11, "One")
	local two = closing.environment:join(12, "Two")
	closing.environment:shutdown()

	t.equal("shutdown ends the first session", closing.fake.records["11"].endSession, 1)
	t.equal("shutdown ends the second session too", closing.fake.records["12"].endSession, 1)
	t.equal(
		"nothing is left in memory after shutdown",
		closing.service.get(one) ~= nil or closing.service.get(two) ~= nil,
		false
	)
	t.equal(
		"shutdown writes lastSeen for every profile",
		closing.fake.profiles["11"].Data.lastSeen > 0,
		true
	)
	t.equal(
		"a clean shutdown kicks nobody",
		closing.environment.kicks[11] ~= nil or closing.environment.kicks[12] ~= nil,
		false
	)

	closing.service.shutdown()
	t.equal(
		"shutting down twice saves nothing a second time",
		closing.fake.records["11"].endSession,
		1
	)
end
