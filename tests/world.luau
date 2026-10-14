-- What WorldBuilder finds in the place: which parts and models claim which kind, what it says when
-- a kind or an ore id is wrong, and what an empty place reports. It creates nothing, and that is
-- what makes this testable without a running server: Lune has real Instances, so the place below is
-- a real, if tiny, one.
--
-- The place also captures the module's prints and warnings, because for a place that has nothing in
-- it those lines are the entire answer, and a mistyped property is worth exactly one warning.

local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")
local Properties = require("../src/shared/Properties")

local RobloxStub = require("./support/roblox_stub")

local function newPlace()
	local environment = RobloxStub.newEnvironment()
	local place = roblox.Instance.new("Folder")
	place.Name = "Workspace"
	local warnings, prints = {}, {}

	-- Loaded the way the game loads it: a workspace global, the shared modules behind require, and
	-- the two output functions kept rather than printed, so the tests can read them back.
	local module = RobloxStub.loadModule(
		"src/server/WorldBuilder.luau",
		{ ["shared.Formulas"] = Formulas, ["shared.Properties"] = Properties },
		environment,
		{
			workspace = place,
			warn = function(...)
				warnings[#warnings + 1] = table.concat({ ... }, " ")
			end,
			print = function(...)
				prints[#prints + 1] = table.concat({ ... }, " ")
			end,
		}
	)

	-- `attributes` is a table of attribute name to value, or nothing at all.
	local function placeable(name, className, attributes, parent)
		local instance = roblox.Instance.new(className or "Part")
		instance.Name = name
		if instance:IsA("BasePart") then
			-- Lune hands back no position for a part until one is set, where a part in a place always
			-- has one. The tests are about what discovery does with a position, not about having one.
			instance.Position = roblox.Vector3.new(0, 0, 0)
		end
		for key, value in pairs(attributes or {}) do
			instance:SetAttribute(key, value)
		end
		instance.Parent = parent or place
		return instance
	end

	return {
		place = place,
		module = module,
		warnings = warnings,
		prints = prints,
		placeable = placeable,
	}
end

-- Nodes come back in no guaranteed order, so the tests look them up by the object they stand for.
local function nodeFor(world, instance)
	for _, node in ipairs(world.nodes) do
		if node.instance == instance then
			return node
		end
	end
	return nil
end

local function says(messages, fragment)
	for _, message in ipairs(messages) do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

return function(t)
	-- An empty place is a real answer rather than a crash: what it says about itself is the report.
	local empty = newPlace()
	local nothing = empty.module.collect(Config)
	t.equal("a place with nothing in it has no ore", #nothing.nodes, 0)
	t.equal("and no Sell Pads", #nothing.pads, 0)
	t.equal("and one warning per thing it is missing", #empty.warnings, 2)
	t.equal(
		"the missing ore warning says what to set",
		says(empty.warnings, 'set its kind attribute to "ore"'),
		true
	)
	t.equal(
		"the missing pad warning says what to set",
		says(empty.warnings, 'attribute to "sellPad"'),
		true
	)

	-- Ore is an object claiming the ore kind, wherever it sits in the place.
	local place = newPlace()
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Sunny Burrow"
	folder.Parent = place.place
	local pebble =
		place.placeable("Chunky Rock", "Part", { kind = "ore", oreId = "pebblePop" }, folder)
	local daisy = place.placeable("Daisy Rock", "Part", { kind = "ore", oreId = "copperDaisy" })

	local world = place.module.collect(Config)
	t.equal("only objects claiming the ore kind become nodes", #world.nodes, 2)

	local pebbleNode = nodeFor(world, pebble)
	t.equal("a part nested in a folder is found too", pebbleNode ~= nil, true)
	t.equal("and keeps the ore it names", pebbleNode.oreId, "pebblePop")
	t.equal(
		"the client is given a node id to send back",
		pebble:GetAttribute(Properties.nodeId),
		pebbleNode.id
	)
	t.equal("a plain node is not unlimited", pebbleNode.unlimited, false)
	t.equal("a node says what it is in the output", says(place.prints, "is a pebblePop node"), true)
	t.equal(
		"a second ore is adopted as the ore it names",
		nodeFor(world, daisy).oreId,
		"copperDaisy"
	)

	-- A kind that is wrong, an ore id that does not exist, and a property that is missing: each is
	-- worth one warning naming the fix, and none of them is silently decoration.
	local broken = newPlace()
	broken.placeable("Not An Ore", "Part", { kind = "ore", oreId = "noSuchOre" })
	broken.placeable("Ore Without A Type", "Part", { kind = "ore" })
	broken.placeable("Ore Without A Kind", "Part", { oreId = "pebblePop" })
	broken.placeable("Mistyped", "Part", { kind = "rock", oreId = "pebblePop" })
	broken.placeable("Decoration", "Part")
	local brokenWorld = broken.module.collect(Config)
	t.equal("none of them becomes a node", #brokenWorld.nodes, 0)
	t.equal(
		"an ore id that does not exist is refused",
		says(broken.warnings, "does not exist"),
		true
	)
	t.equal(
		"and the message lists the ores that do, in order",
		says(broken.warnings, "copperDaisy, honeyQuartz, pebblePop"),
		true
	)
	t.equal("an ore with no type is refused", says(broken.warnings, "no oreId attribute"), true)
	t.equal(
		"an ore id with no kind is refused",
		says(broken.warnings, 'no kind: set its kind attribute to "ore"'),
		true
	)
	t.equal(
		"a kind that does not exist is refused",
		says(broken.warnings, "which is not one of"),
		true
	)
	t.equal(
		"and a part with nothing on it is simply decoration",
		#broken.warnings - 2, -- the two "nothing here" warnings
		4
	)

	-- A part with nothing on it is never a mistake, so it never warns on its own account.
	local quiet = newPlace()
	quiet.placeable("Grass", "Part")
	quiet.module.collect(Config)
	t.equal("decoration alone says only that the place is bare", #quiet.warnings, 2)

	-- The Sell Pad: found by kind, never a node, and more than one is allowed.
	local padded = newPlace()
	local pad = padded.placeable("Pad", "Part", { kind = "sellPad" })
	local secondPad = padded.placeable("Pad By The Shop", "Part", { kind = "sellPad" })
	local paddedWorld = padded.module.collect(Config)
	t.equal("an object claiming the pad kind is a pad", #paddedWorld.pads, 2)
	t.equal("the first one is kept", paddedWorld.pads[1], pad)
	t.equal("and so is the second", paddedWorld.pads[2], secondPad)
	t.equal("a pad is not also ore", #paddedWorld.nodes, 0)
	t.equal("and it says so", says(padded.prints, "is a Sell Pad"), true)
	t.equal("more than one pad is reported", says(padded.prints, "every one of them buys"), true)

	-- Everything a node needs is on the object that carries the kind, and `unlimited` is the one
	-- value that changes a node's behaviour rather than its identity.
	local endless = newPlace()
	local endlessPart = endless.placeable("Endless Rock", "Part", {
		kind = "ore",
		oreId = "honeyQuartz",
		unlimited = true,
	})
	local endlessNode = nodeFor(endless.module.collect(Config), endlessPart)
	t.equal("a node can be unlimited", endlessNode.unlimited, true)
	t.equal(
		"and the output says so, because it changes what the node does",
		says(endless.prints, ", unlimited"),
		true
	)

	-- Two objects with the same name keep separate ids, so neither is unreachable.
	local twins = newPlace()
	local twinA = twins.placeable("Twin", "Part", { kind = "ore", oreId = "pebblePop" })
	local twinB = twins.placeable("Twin", "Part", { kind = "ore", oreId = "pebblePop" })
	local twinWorld = twins.module.collect(Config)
	t.equal(
		"both twins are nodes",
		nodeFor(twinWorld, twinA) ~= nil and nodeFor(twinWorld, twinB) ~= nil,
		true
	)
	t.equal(
		"and they do not share an id",
		nodeFor(twinWorld, twinA).id ~= nodeFor(twinWorld, twinB).id,
		true
	)
	t.equal(
		"the id is written onto the object",
		twinB:GetAttribute(Properties.nodeId),
		nodeFor(twinWorld, twinB).id
	)

	-- A model is one object: its parts make it big, and the kind is set once, on the model.
	local modelPlace = newPlace()
	local rock = roblox.Instance.new("Model")
	rock.Name = "Rock Cluster"
	rock:SetAttribute("kind", "ore")
	rock:SetAttribute("oreId", "honeyQuartz")
	rock.Parent = modelPlace.place

	local primary = roblox.Instance.new("Part")
	primary.Name = "Middle Rock"
	primary.Position = roblox.Vector3.new(6, 1, 0)
	primary.Parent = rock
	local buried = roblox.Instance.new("Part")
	buried.Name = "Buried Rock"
	buried.Position = roblox.Vector3.new(20, 1, 0)
	buried.Parent = rock
	rock.PrimaryPart = primary

	-- A part inside the model that claims a kind of its own is part of the model, not a second
	-- placeable object: the outermost object wins.
	local inner = roblox.Instance.new("Part")
	inner.Name = "Inner Pad"
	inner.Position = roblox.Vector3.new(6, 1, 0)
	inner:SetAttribute("kind", "sellPad")
	inner.Parent = rock

	local modelWorld = modelPlace.module.collect(Config)
	local modelNode = nodeFor(modelWorld, rock)
	t.equal("a model claiming the ore kind is one node", modelNode ~= nil, true)
	t.equal("with the ore set on the model", modelNode.oreId, "honeyQuartz")
	t.equal("a kind inside the model is not a second object", #modelWorld.nodes, 1)
	t.equal("and a pad inside it is not a pad", #modelWorld.pads, 0)
	t.equal(
		"a model's position is its PrimaryPart's",
		Properties.positionOf(rock).X,
		primary.Position.X
	)
	t.equal(
		"and it counts every part, not just the first",
		#Properties.partsOf(rock),
		3 -- three rocks, one of which claims a kind of its own
	)

	-- A model with no PrimaryPart still stands somewhere: its first part does, so one can be placed
	-- without being told which rock is the middle of it.
	local loosePlace = newPlace()
	local loose = roblox.Instance.new("Model")
	loose.Name = "Loose Cluster"
	loose:SetAttribute("kind", "ore")
	loose:SetAttribute("oreId", "pebblePop")
	loose.Parent = loosePlace.place
	local first = roblox.Instance.new("Part")
	first.Name = "First Rock"
	first.Position = roblox.Vector3.new(3, 1, 0)
	first.Parent = loose
	local second = roblox.Instance.new("Part")
	second.Name = "Second Rock"
	second.Position = roblox.Vector3.new(9, 1, 0)
	second.Parent = loose

	local looseWorld = loosePlace.module.collect(Config)
	t.equal("a model with no PrimaryPart is still an ore", #looseWorld.nodes, 1)
	t.equal(
		"and its position is its first part's",
		Properties.positionOf(loose).X,
		first.Position.X
	)
	t.equal("both of its parts count", #Properties.partsOf(loose), 2)

	-- A model with nothing inside it has no position at all, which is the one way an ore can be
	-- unable to stand for itself.
	local hollowPlace = newPlace()
	local hollow = roblox.Instance.new("Model")
	hollow.Name = "Hollow Rock"
	hollow:SetAttribute("kind", "ore")
	hollow:SetAttribute("oreId", "pebblePop")
	hollow.Parent = hollowPlace.place
	local hollowWorld = hollowPlace.module.collect(Config)
	t.equal("an ore model with no parts is refused", #hollowWorld.nodes, 0)
	t.equal("and says why", says(hollowPlace.warnings, "no parts inside it"), true)

	-- The vocabulary itself, held against the balance numbers: an ore id a designer cannot use is
	-- as bad as one they can use but which nothing understands.
	local expectedOreIds = {}
	for _, layer in ipairs(Config.layers) do
		for _, ore in ipairs(layer.ores) do
			expectedOreIds[#expectedOreIds + 1] = ore.id
		end
	end
	table.sort(expectedOreIds)
	t.equal(
		"the accepted ore ids are the configured ones",
		table.concat(Properties.oreIds(Config), ", "),
		table.concat(expectedOreIds, ", ")
	)
	t.equal(
		"the accepted kinds are ore and sellPad",
		table.concat(Properties.kindNames(), ", "),
		"ore, sellPad"
	)
end
