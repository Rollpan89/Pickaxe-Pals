-- Ore nodes and mining hits. The client only asks; range, rate, damage and backpack room are all
-- decided here, so a modified client cannot mine faster or from further away.
--
-- A node is a part or a model that WorldBuilder found, so what a hit looks like is that object's
-- business: a single part goes opaque and clear again, while a model of parts keeps each part's
-- authored transparency and returns to it when the node respawns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Properties = require(Shared:WaitForChild("Properties"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))

local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local MiningService = {}

-- How see-through a node goes once it has been mined out.
local BROKEN_TRANSPARENCY = 0.85

-- [nodeId] = { id, oreId, instance, health, unlimited, position, parts }
local nodes = {}
local limiters = {} -- [player] = { limiter, tier }
local fullNotified = {} -- [player] = true while the last request found the backpack full
local lastLog = {} -- [player] = os.clock() of the last dropped-request warning

local function characterRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function limiterFor(player, data)
	local entry = limiters[player]
	if not entry or entry.tier ~= data.pickaxeTier then
		local pickaxe = Formulas.pickaxe(Config, data.pickaxeTier)
		entry = {
			limiter = RateLimiter.new(
				(1 / pickaxe.cooldown) * Config.mining.hitRateTolerance,
				Config.mining.hitBurst
			),
			tier = data.pickaxeTier,
		}
		limiters[player] = entry
	end
	return entry.limiter
end

-- Dropped requests are logged, but never often enough to flood the output window.
local function logDropped(player, reason)
	local now = os.clock()
	if lastLog[player] and now - lastLog[player] < 5 then
		return
	end
	lastLog[player] = now
	warn(string.format("[MiningService] dropped a request from %s: %s", player.Name, reason))
end

local function backpackFull(data, backpack)
	return Formulas.backpackTotal(backpack) >= Formulas.backpackCapacity(Config, data.backpackLevel)
end

-- The parts of an object with the transparency they were authored with, so that a node that is
-- broken and respawns looks exactly like the one that was placed rather than becoming opaque.
local function appearanceOf(instance)
	local appearance = {}
	for _, part in ipairs(Properties.partsOf(instance)) do
		table.insert(appearance, { part = part, transparency = part.Transparency })
	end
	return appearance
end

local function setBroken(node, broken)
	if broken then
		node.health = 0
		node.instance:SetAttribute(Properties.health, 0)
		for _, entry in ipairs(node.appearance) do
			entry.part.Transparency = BROKEN_TRANSPARENCY
		end
		return
	end

	node.health = node.maxHealth
	node.instance:SetAttribute(Properties.health, node.maxHealth)
	for _, entry in ipairs(node.appearance) do
		entry.part.Transparency = entry.transparency
	end
end

local function breakNode(player, backpack, node, ore)
	backpack[node.oreId] = (backpack[node.oreId] or 0) + 1
	State.push(player)

	-- An unlimited node is a test fixture: it pays out and is immediately ready again, so it can
	-- be mined without ever waiting out `respawnSeconds`.
	if node.unlimited then
		setBroken(node, false)
		return
	end

	setBroken(node, true)

	task.delay(ore.respawnSeconds, function()
		if node.instance.Parent then
			setBroken(node, false)
		end
	end)
end

local function onHit(player, nodeId)
	if typeof(nodeId) ~= "string" or #nodeId > 64 then
		logDropped(player, "bad node id")
		return
	end

	local data = DataService.get(player)
	local backpack = DataService.backpack(player)
	if not data or not backpack then
		return
	end

	local root = characterRoot(player)
	local node = nodes[nodeId]
	if not root or not node or node.health <= 0 then
		logDropped(player, "no character, unknown node, or node already broken")
		return
	end

	if (node.position - root.Position).Magnitude > Config.mining.nodeRangeStuds then
		logDropped(player, "out of range")
		return
	end

	if not limiterFor(player, data):allow() then
		logDropped(player, "over the hit rate")
		return
	end

	if backpackFull(data, backpack) then
		if not fullNotified[player] then
			fullNotified[player] = true
			State.notify(player, "Backpack full. Stand on the Sell Pad to sell.")
		end
		return
	end
	fullNotified[player] = nil

	local ore = Formulas.ore(Config, node.oreId)
	node.health -= Formulas.pickaxe(Config, data.pickaxeTier).damage
	if node.health > 0 then
		node.instance:SetAttribute(Properties.health, node.health)
		return
	end

	breakNode(player, backpack, node, ore)
end

function MiningService.start(world)
	for _, node in ipairs(world.nodes) do
		local ore = Formulas.ore(Config, node.oreId)
		nodes[node.id] = {
			id = node.id,
			oreId = node.oreId,
			instance = node.instance,
			health = ore.health,
			maxHealth = ore.health,
			unlimited = node.unlimited == true,
			position = Properties.positionOf(node.instance),
			appearance = appearanceOf(node.instance),
		}
		node.instance:SetAttribute(Properties.health, ore.health)
		node.instance:SetAttribute(Properties.maxHealth, ore.health)
	end

	Remotes.get("mineHit").OnServerEvent:Connect(onHit)

	Players.PlayerRemoving:Connect(function(player)
		limiters[player] = nil
		fullNotified[player] = nil
		lastLog[player] = nil
	end)
end

return MiningService
