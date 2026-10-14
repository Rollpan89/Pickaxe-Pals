-- Mining hits, driven through the real MiningService with stand-ins for the services it calls.
-- Two rules are worth stating out loud, and this is the only place they can be checked without a
-- running Roblox server: an `unlimited` node pays out and is never left broken, and a normal node
-- goes dark and stays dark until it respawns. Range, hit rate and backpack room are all decided by
-- the service, so those are driven here rather than trusted.
--
-- The nodes are real Instances, because the service reads a node the way the world presents it: a
-- part or a model, with its own position and its own transparency. That is what lets the model
-- case below check that every part of a model is put back as it was authored.

local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")
local Properties = require("../src/shared/Properties")
local RateLimiter = require("../src/shared/RateLimiter")

local RobloxStub = require("./support/roblox_stub")

-- The parts below are parented, so the service's respawn check sees them in the world the way a
-- part placed in Workspace is, and are removed from it at the end of the run.
local place = roblox.Instance.new("Folder")
place.Name = "Workspace"

local function newPart(name, position, transparency)
	local part = roblox.Instance.new("Part")
	part.Name = name
	part.Position = position or roblox.Vector3.new(0, 0, 0)
	part.Transparency = transparency or 0
	part.Parent = place
	return part
end

local function newModel(name, position)
	local model = roblox.Instance.new("Model")
	model.Name = name
	-- Both parts are authored see-through, at different amounts, so that restoring them to a single
	-- shared value would be visible as a failure below.
	local primary = newPart(name .. "_A", position, 0.25)
	primary.Parent = model
	local other = newPart(name .. "_B", position, 0.5)
	other.Parent = model
	model.PrimaryPart = primary
	-- Parented, because the service only respawns a node that is still in the world.
	model.Parent = place
	return model
end

-- A server whose hits can be fired by hand, the way the RemoteEvent would. `rootPosition` is where
-- the player is standing, so range can be tested, and `config` swaps the balance numbers, so a
-- respawn timer can be waited out.
local function newMining(nodes, options)
	options = options or {}
	local environment = RobloxStub.newEnvironment()
	local data = { pickaxeTier = 1, backpackLevel = 1 }
	local backpack = {}
	local notices = {}
	local warns = {}
	local pushes = 0
	local mineHit = RobloxStub.newSignal()
	local root = { Position = options.rootPosition or roblox.Vector3.new(0, 0, 0) }

	local standIns = {
		["shared.Config"] = options.config or Config,
		["shared.Formulas"] = Formulas,
		["shared.Properties"] = Properties,
		["shared.RateLimiter"] = RateLimiter,
		["server.DataService"] = {
			get = function()
				return data
			end,
			backpack = function()
				return backpack
			end,
		},
		["server.State"] = {
			push = function()
				pushes += 1
			end,
			notify = function(_, message)
				notices[#notices + 1] = message
			end,
		},
		["server.Remotes"] = {
			get = function()
				return { OnServerEvent = mineHit }
			end,
		},
	}

	local service = RobloxStub.loadModule("src/server/MiningService.luau", standIns, environment, {
		warn = function(...)
			warns[#warns + 1] = table.concat({ ... }, " ")
		end,
		script = {
			Parent = {
				DataService = "server.DataService",
				State = "server.State",
				Remotes = "server.Remotes",
			},
		},
	})
	service.start({ nodes = nodes })

	local player = {
		Name = "Tester",
		Character = {
			FindFirstChild = function()
				return root
			end,
		},
	}

	return {
		-- What the client's RemoteEvent would have done.
		hit = function(nodeId)
			mineHit:Fire(player, nodeId)
		end,
		data = data,
		backpack = backpack,
		notices = notices,
		warns = warns,
		pushes = function()
			return pushes
		end,
	}
end

-- How long one hit has to wait for the limiter to hand it its next token.
local function tokenSeconds(config)
	local pickaxe = Formulas.pickaxe(config, 1)
	return 1 / ((1 / pickaxe.cooldown) * config.mining.hitRateTolerance) + 0.05
end

local function says(messages, fragment)
	for _, message in ipairs(messages) do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

-- A config whose only change is a very short respawn, so a broken node can be watched coming back
-- without a four second wait. This also keeps the unlimited branch from quietly becoming the only
-- behaviour the suite covers.
local function quickConfig()
	local config = {}
	for key, value in pairs(Config) do
		config[key] = value
	end
	local pebble = Formulas.ore(Config, "pebblePop")
	config.layers = {
		{
			id = Config.layers[1].id,
			name = Config.layers[1].name,
			unlockRebirth = Config.layers[1].unlockRebirth,
			ores = {
				{
					id = pebble.id,
					name = pebble.name,
					health = pebble.health,
					value = pebble.value,
					respawnSeconds = 0.05,
				},
			},
		},
	}
	return config
end

return function(t)
	local pebble = Formulas.ore(Config, "pebblePop")
	local hitsToBreak = Formulas.hitsToBreak(Config, pebble, 1)
	t.equal(
		"Pebble Pop is the first ore of the first layer",
		pebble.id,
		Config.layers[1].ores[1].id
	)

	-- An unlimited node, which is what a test ore is: it pays out and never stays broken.
	local part = newPart("Endless Rock")
	local unlimited = newMining({
		{ id = "Endless Rock", oreId = pebble.id, instance = part, unlimited = true },
	})

	unlimited.hit("Endless Rock")
	t.equal(
		"a hit is visible to the client",
		part:GetAttribute(Properties.health),
		pebble.health - 1
	)
	for _ = 2, hitsToBreak do
		unlimited.hit("Endless Rock")
	end
	t.equal("an unlimited node pays out when it would break", unlimited.backpack[pebble.id], 1)
	t.equal("and is at full health again", part:GetAttribute(Properties.health), pebble.health)
	t.equal("never left dark for the client", part.Transparency, 0)
	t.equal(
		"and its maximum is published for the client's health bar",
		part:GetAttribute(Properties.maxHealth),
		pebble.health
	)

	for _ = 1, hitsToBreak do
		task.wait(tokenSeconds(Config))
		unlimited.hit("Endless Rock")
	end
	t.equal("mining on pays out again", unlimited.backpack[pebble.id], 2)

	-- Unlimited ore, not an unlimited bag: the backpack rule still applies to it.
	unlimited.backpack[pebble.id] = Formulas.backpackCapacity(Config, 1)
	task.wait(tokenSeconds(Config))
	unlimited.hit("Endless Rock")
	t.equal(
		"a full backpack stops even an unlimited node",
		unlimited.backpack[pebble.id],
		Formulas.backpackCapacity(Config, 1)
	)
	t.equal(
		"and that player is told why",
		unlimited.notices[#unlimited.notices],
		"Backpack full. Stand on the Sell Pad to sell."
	) -- A normal node, for contrast: it goes dark and stays dark until it respawns. It is queued at
	-- the default respawn time here, so the check below that a broken node pays nothing cannot race
	-- the node coming back. A respawned node is whole again, which is what makes that race real.
	local normalPart = newPart("Dim Rock", nil, 0.5)
	local normal = newMining({ { id = "Dim Rock", oreId = pebble.id, instance = normalPart } })
	for _ = 1, hitsToBreak do
		normal.hit("Dim Rock")
	end
	t.equal("a normal node pays out once when it breaks", normal.backpack[pebble.id], 1)
	t.near("then goes dark", normalPart.Transparency, 0.85, 0.001)
	t.equal("its health attribute drops to nothing", normalPart:GetAttribute(Properties.health), 0)

	task.wait(tokenSeconds(Config))
	normal.hit("Dim Rock")
	t.equal("hitting a broken node gives nothing", normal.backpack[pebble.id], 1)
	t.near("and it is still dark", normalPart.Transparency, 0.85, 0.001)

	-- The respawn timer, on a config whose only change is a very short one, so a broken node can be
	-- watched coming back without a four second wait. The part was placed see-through, and that is
	-- the look it has to return to: a respawn is not the same as turning opaque again.
	local quick = quickConfig()
	local quickPart = newPart("Quick Rock", nil, 0.5)
	local respawning = newMining(
		{ { id = "Quick Rock", oreId = pebble.id, instance = quickPart } },
		{ config = quick }
	)
	for _ = 1, hitsToBreak do
		respawning.hit("Quick Rock")
	end
	t.equal("the quick node broke once", respawning.backpack[pebble.id], 1)

	task.wait(0.2)
	t.equal(
		"a broken node comes back after its respawn wait",
		quickPart:GetAttribute(Properties.health),
		pebble.health
	)
	t.near("as it was authored, rather than merely opaque", quickPart.Transparency, 0.5, 0.001)

	for _ = 1, hitsToBreak do
		task.wait(tokenSeconds(quick))
		respawning.hit("Quick Rock")
	end
	t.equal("and it can be mined again", respawning.backpack[pebble.id], 2)

	-- A model is one node made of several parts, and every one of them has to go dark and come back
	-- as it was, part by part: restoring the whole model to one transparency would pass a test that
	-- only looked at whether it was dark.
	local model = newModel("RockCluster", roblox.Vector3.new(0, 0, 0))
	local cluster = newMining(
		{ { id = "RockCluster", oreId = pebble.id, instance = model } },
		{ config = quickConfig() }
	)
	for _ = 1, hitsToBreak do
		cluster.hit("RockCluster")
	end
	t.equal("a model node pays out when it breaks", cluster.backpack[pebble.id], 1)
	local allDark = true
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and math.abs(descendant.Transparency - 0.85) > 0.001 then
			allDark = false
		end
	end
	t.equal("every part of a model goes dark, not only the PrimaryPart", allDark, true)

	task.wait(0.2)
	t.equal("it comes back at full health", model:GetAttribute(Properties.health), pebble.health)
	local look = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			look[descendant.Name] = descendant.Transparency
		end
	end
	t.near("the PrimaryPart keeps the look it was placed with", look.RockCluster_A, 0.25, 0.001)
	t.near("and so does the part beside it", look.RockCluster_B, 0.5, 0.001)

	-- Range is the server's decision, not the client's.
	local farPart = newPart("Far Rock", roblox.Vector3.new(0, 0, Config.mining.nodeRangeStuds + 2))
	local far = newMining({ { id = "Far Rock", oreId = pebble.id, instance = farPart } })
	for _ = 1, hitsToBreak do
		far.hit("Far Rock")
	end
	t.equal("a hit from out of range is refused", far.backpack[pebble.id], nil)
	t.equal("and the drop is logged for the developer", says(far.warns, "out of range"), true)

	-- The parts are deliberately left parented. A respawn timer from the default config is still
	-- pending at this point, and Lune panics when a callback reaches into an instance that has been
	-- destroyed, which is a limitation of the stand-in rather than of the service: in Roblox the
	-- same callback finds a part with no parent and returns. The process exits straight after, and
	-- that is what frees them.
end
