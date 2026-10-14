-- Studio smoke test, driven by `run-in-roblox` (see the README). It opens the built place in
-- Roblox Studio and exercises the server modules in a real DataModel, which is the one thing
-- the Lune tests cannot do: there, instances and services are stand-ins.
--
-- run-in-roblox wraps this file as `return function() <body> end` and calls it once, at
-- plugin-level security in Edit mode. Three consequences shape everything below:
--
--   * the body runs directly, so this file must not define its own top-level function
--   * Edit mode means no players ever join and ServerScriptService scripts never start, so
--     Main.server.luau does not run; this file drives the modules by hand instead
--   * only strings survive the LogService bridge, so every line is formatted before printing
--
-- Everything it creates is destroyed again before it returns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local failures = 0

local function say(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		parts[#parts + 1] = tostring(value)
	end
	print("PROBE| " .. table.concat(parts, " "))
end

-- Runs one stage, reporting rather than aborting: the value of a run is getting every answer
-- out of a single Studio launch.
local function stage(name, body)
	local ok, err = pcall(body)
	if ok then
		say("PASS", name)
	else
		failures += 1
		say("FAIL", name, "->", err)
	end
	return ok
end

-- For behaviour that depends on Studio context rather than on the project's code. Reported
-- without counting as a failure, so the exit code keeps meaning "something is broken".
local function probe(name, body)
	local ok, err = pcall(body)
	say(ok and "NOTE" or "NOTE (raised)", name, "->", err)
end

local function count(table_)
	local total = 0
	for _ in pairs(table_) do
		total += 1
	end
	return total
end

-- If Studio forwards this launch into an already-open session, the place may already hold the
-- things below. Move them aside first and put them back at the end, so a run can never cost
-- someone their in-memory world.
local stashed = {}

local function stash(container, name)
	local existing = container:FindFirstChild(name)
	if not existing then
		return false
	end
	existing.Name = "ProbeStash_" .. name
	table.insert(stashed, { container = container, name = name, backup = existing.Name })
	return true
end

local function restoreStash()
	for _, entry in ipairs(stashed) do
		local backup = entry.container:FindFirstChild(entry.backup)
		if backup then
			backup.Name = entry.name
		end
	end
	stashed = {}
end

say(
	"start: Studio=",
	RunService:IsStudio(),
	"Edit=",
	RunService:IsEdit(),
	"Running=",
	RunService:IsRunning()
)
say("players=", #Players:GetPlayers())

-- 1. Every module has to load from its mapped instance. This is the require-path check the
-- Lune tests cannot make, because there the modules are plain files.
local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
local Server = ServerScriptService:WaitForChild("Server", 15)
local Packages = ServerScriptService:WaitForChild("ServerPackages", 15)

local function load(parent, name)
	local instance = parent:FindFirstChild(name)
	assert(instance, name .. " is not inside " .. parent:GetFullName())
	return require(instance)
end

local shared, server = {}, {}
for _, name in ipairs({ "Config", "Properties", "Formulas", "Schema", "Types", "RateLimiter" }) do
	stage("require Shared." .. name, function()
		shared[name] = load(Shared, name)
	end)
end
for _, name in ipairs({
	"DataService",
	"EconomyService",
	"MiningService",
	"Remotes",
	"State",
	"WorldBuilder",
}) do
	stage("require Server." .. name, function()
		server[name] = load(Server, name)
	end)
end

local Config, Schema = shared.Config, shared.Schema

-- 2. Schema, against the real Config rather than a test double.
stage("Schema.new gives a fresh profile", function()
	local profile = Schema.new()
	assert(profile.version == Schema.version, "version is " .. tostring(profile.version))
	assert(profile.coins == 0, "coins is " .. tostring(profile.coins))
	say("template keys=", count(Schema.template), "backpackLevel=", tostring(profile.backpackLevel))
end)

stage("Schema.prepare repairs a damaged save", function()
	local prepared, problem = Schema.prepare(Config, {
		version = 1,
		coins = math.huge,
		backpack = { pebblePop = -3 },
		unknownKey = true,
	})
	assert(prepared, "refused a valid save: " .. tostring(problem))
	assert(prepared.coins == prepared.coins, "coins is NaN")
	assert(math.abs(prepared.coins) < math.huge, "coins is still infinite")
	assert(prepared.unknownKey == nil, "an unknown key survived sanitize")
	assert(count(prepared) == count(Schema.template), "shape does not match the template")
	say("repaired coins=", prepared.coins, "unknownKey=", tostring(prepared.unknownKey))
end)

-- 3. Nothing this script does should cost the place anything it already had.
stage("stash anything already present", function()
	local hadRemotes = stash(ReplicatedStorage, "Remotes")
	say("pre-existing Remotes=", hadRemotes)
end)

-- 4. The remotes the client waits for.
stage("Remotes.start creates every event", function()
	server.Remotes.start()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	assert(folder, "no Remotes folder was created")
	local names = {}
	for _, child in ipairs(folder:GetChildren()) do
		names[#names + 1] = child.Name .. ":" .. child.ClassName
	end
	say("remotes=", table.concat(names, " "))
	assert(#names == count(Config.remotes), #names .. " events, expected " .. count(Config.remotes))
	assert(
		server.Remotes.get("stateChanged").ClassName == "RemoteEvent",
		"stateChanged is not a RemoteEvent"
	)
end)

-- 5. The world: what this probe puts in the place by hand, and what WorldBuilder makes of it.
local world
local byName = {}
local placed = {}

-- 5b. The world, put in the place by hand the way a developer drags a part in: three ore nodes
-- (one of them unlimited, one a model), two Sell Pads, and three objects that must be left alone.
stage("place the world by hand", function()
	local function newPart(name, position, parent)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = Vector3.new(3, 3, 3)
		part.Position = position
		part.Parent = parent or workspace
		table.insert(placed, part)
		return part
	end

	local unlimitedOre = newPart("TestOre1", Vector3.new(0, 3, 0))
	unlimitedOre:SetAttribute("kind", "ore")
	unlimitedOre:SetAttribute("oreId", "pebblePop")
	unlimitedOre:SetAttribute("unlimited", true)

	local tagged = newPart("CopperRock", Vector3.new(8, 3, 0))
	tagged:SetAttribute("kind", "ore")
	tagged:SetAttribute("oreId", "copperDaisy")

	-- An ore model: the kind is set once, on the model, and its parts are the rock.
	local cluster = Instance.new("Model")
	cluster.Name = "RockCluster"
	cluster:SetAttribute("kind", "ore")
	cluster:SetAttribute("oreId", "honeyQuartz")
	cluster.Parent = workspace
	table.insert(placed, cluster)
	local middle = newPart("RockCluster_A", Vector3.new(-8, 3, 0), cluster)
	newPart("RockCluster_B", Vector3.new(-10, 3, 2), cluster)
	cluster.PrimaryPart = middle

	-- Objects that must not be adopted: an ore that does not exist, an ore id with no kind, and a
	-- kind that is not in the vocabulary.
	local bogus = newPart("NotAnOre", Vector3.new(0, 3, -8))
	bogus:SetAttribute("kind", "ore")
	bogus:SetAttribute("oreId", "noSuchOre")

	local kindless = newPart("OreWithoutAKind", Vector3.new(4, 3, -8))
	kindless:SetAttribute("oreId", "pebblePop")

	local mistyped = newPart("Mistyped", Vector3.new(-4, 3, -8))
	mistyped:SetAttribute("kind", "rock")

	local pad = newPart("SellPad", Vector3.new(0, 1, 12))
	pad:SetAttribute("kind", "sellPad")
	local secondPad = newPart("SellPadTwo", Vector3.new(16, 1, 12))
	secondPad:SetAttribute("kind", "sellPad")

	say("placed three ore nodes (one a model), two pads, and three objects to ignore")
end)

stage("WorldBuilder.collect finds the world in the place", function()
	world = server.WorldBuilder.collect(Config)
	assert(#world.nodes >= 3, #world.nodes .. " nodes found; at least the three placed above")
	for _, node in ipairs(world.nodes) do
		assert(
			node.instance:GetAttribute("kind") == "ore",
			"adopted an object with no ore kind: " .. node.instance.Name
		)
		assert(
			node.instance:GetAttribute("oreId") == node.oreId,
			"oreId attribute mismatch on " .. node.id
		)
		assert(
			node.instance:GetAttribute("nodeId") == node.id,
			"nodeId attribute mismatch on " .. node.id
		)
	end
	-- The hand-placed objects joined the node list.
	for _, node in ipairs(world.nodes) do
		byName[node.instance.Name] = node
	end

	local unlimitedOre = byName.TestOre1
	assert(unlimitedOre, "the hand-placed TestOre1 was not adopted")
	assert(unlimitedOre.oreId == "pebblePop", "adopted as " .. tostring(unlimitedOre.oreId))
	assert(unlimitedOre.unlimited == true, "the unlimited node is not unlimited")

	local tagged = byName.CopperRock
	assert(tagged, "a part claiming the ore kind was not adopted")
	assert(tagged.oreId == "copperDaisy", "the tagged part took the wrong ore")
	assert(tagged.unlimited == false, "a tagged part became unlimited")

	local cluster = byName.RockCluster
	assert(cluster, "the hand-placed ore model was not adopted")
	assert(
		cluster.instance.ClassName == "Model",
		"the model node is a " .. cluster.instance.ClassName
	)
	assert(cluster.oreId == "honeyQuartz", "the model took the wrong ore")
	assert(
		cluster.instance.PrimaryPart ~= nil,
		"the model lost its PrimaryPart, so it has no position"
	)

	-- And the objects that must be left alone were.
	assert(not byName.NotAnOre, "a node naming an ore that does not exist was adopted")
	assert(not byName.OreWithoutAKind, "an oreId with no kind was adopted anyway")
	assert(not byName.Mistyped, "a kind that does not exist was adopted")

	assert(#world.pads == 2, #world.pads .. " pads found, expected the two placed")
	local pads = {}
	for _, pad in ipairs(world.pads) do
		pads[pad.Name] = true
		assert(not byName[pad.Name], "the Sell Pad " .. pad.Name .. " was taken as ore as well")
	end
	assert(pads.SellPad, "the part claiming the pad kind was not found")
	assert(pads.SellPadTwo, "the second Sell Pad was not found")

	say(
		"adopted",
		#world.nodes,
		"nodes and",
		#world.pads,
		"pads; TestOre1 unlimited=",
		unlimitedOre.unlimited,
		"model",
		cluster.id,
		"as",
		cluster.oreId
	)
end)

-- 5c. MiningService registers what WorldBuilder found, so a part or a model placed by hand is a
-- real node carrying the first tier's numbers.
stage("MiningService registers the placed ore", function()
	server.MiningService.start(world)
	local pebble = shared.Formulas.ore(Config, "pebblePop")
	local part = byName.TestOre1.instance
	local health = part:GetAttribute("health")
	assert(health == pebble.health, "health is " .. tostring(health))
	assert(part:GetAttribute("maxHealth") == pebble.health, "maxHealth is wrong")

	local quartz = shared.Formulas.ore(Config, "honeyQuartz")
	local model = byName.RockCluster.instance
	assert(
		model:GetAttribute("health") == quartz.health,
		"the model node's health is " .. tostring(model:GetAttribute("health"))
	)
	say("registered", part.Name, "health=", health, "of", pebble.health, "and the model too")
end)

-- 6. ProfileStore itself, and a save/reload round trip through its in-memory store. The mock
-- path runs the library's real session, save and release code, so it needs no DataStore access
-- and is the closest this tool can get to the production path.
local profileStore
stage("require ServerPackages.ProfileStore", function()
	profileStore = load(Packages, "ProfileStore")
	assert(profileStore.IsClosing == false, "IsClosing is " .. tostring(profileStore.IsClosing))
	say(
		"ProfileStore loaded, IsClosing=",
		profileStore.IsClosing,
		"DataStoreState=",
		profileStore.DataStoreState
	)
end)

stage("mock save then reload keeps the data", function()
	assert(profileStore, "ProfileStore did not load")
	local store = profileStore.New("PickaxePals_Probe", Schema.template)
	-- The docs list Mock on the module; the source only builds it on the instance. Accept both.
	local mock = profileStore.Mock or store.Mock
	assert(mock, "no Mock on the module or the store")

	local session = mock:StartSessionAsync("Probe_Key")
	assert(session, "start returned nil")
	assert(session:IsActive(), "the session is not active")
	session.Data.coins = 4242
	session.Data.pity = 7
	session:Save()
	session:EndSession()
	assert(not session:IsActive(), "the session is still active after EndSession")

	local reloaded = mock:StartSessionAsync("Probe_Key")
	assert(reloaded, "reload returned nil")
	assert(reloaded.Data.coins == 4242, "reloaded coins are " .. tostring(reloaded.Data.coins))
	assert(reloaded.Data.pity == 7, "reloaded pity is " .. tostring(reloaded.Data.pity))
	assert(count(reloaded.Data) == count(Schema.template), "the template shape did not survive")
	say(
		"saved coins=4242 pity=7, reloaded coins=",
		reloaded.Data.coins,
		"pity=",
		reloaded.Data.pity
	)
	reloaded:EndSession()
end)

-- 7. Whether this Studio can actually reach a DataStore, and what the library does about it.
-- ProfileStore probes DataStoreService once when it loads and publishes the verdict, so read
-- that instead of inferring anything from a session that came back: with no access it still
-- hands out a working session backed by memory, which is why a playtest can look healthy while
-- nothing is being saved. The probe store is deliberately not the real one, so nothing here can
-- touch a live profile.
probe("DataStore reachability", function()
	local state = profileStore.DataStoreState
	-- A read of a key that does not exist: enough to prove access, and it writes nothing.
	local allowed, err = pcall(function()
		return game:GetService("DataStoreService")
			:GetDataStore("PickaxePals_Probe")
			:GetAsync("probe")
	end)
	say("DataStoreState=", state, "direct GetAsync=", allowed and "allowed" or tostring(err))
	if state ~= "Access" then
		say("SAVING IS OFF here: profiles load blank and nothing is written back")
	end
end)

probe("real store session", function()
	local store = profileStore.New("PickaxePals_Probe", Schema.template)
	local ok, session = pcall(function()
		return store:StartSessionAsync("Probe_Real")
	end)
	if ok and session then
		say("the real store handed out a session; DataStoreState was", profileStore.DataStoreState)
		session:EndSession()
	else
		say("the real store refused a session:", session)
	end
end)

-- 8. The boot path. `useMockInStudio` is false in Config, so this asks for the real store; in
-- Edit mode BindToClose may also be refused, and the message says which.
probe("DataService.start", function()
	server.DataService.start({})
	say("started; isLoaded(missing player)=", server.DataService.isLoaded({}))
end)

-- 9. Leave the place as it was found: remove what this probe built, then put back whatever
-- was stashed above.
stage("cleanup", function()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		remotes:Destroy()
	end
	for _, instance in ipairs(placed) do
		instance:Destroy()
	end
	local restored = #stashed
	restoreStash()
	say("removed what this probe placed; restored", restored, "pre-existing instance(s)")
end)

say("RESULT failures=", failures)

-- A non-zero exit tells the caller something is genuinely wrong, not merely noteworthy.
if failures > 0 then
	error(string.format("studio probe: %d stage(s) failed", failures), 0)
end
