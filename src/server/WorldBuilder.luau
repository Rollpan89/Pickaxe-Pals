-- The world's ore and Sell Pads, found in the place rather than built by this script.
--
-- Everything is authored in Studio and says what it is with a `kind` attribute, so what you can see
-- and click in the Explorer is what the game plays. Properties owns the property names and the
-- values each one accepts; this file decides which objects claim them, and reports anything that
-- claims a kind it cannot be. Nothing here creates an instance: appearance, position and count are
-- the place's business, and a world that is quietly empty is worse than one that says what it
-- expected to find.
--
-- A kind belongs to the outermost object that declares one: nothing inside a model that already is
-- ore is examined again, so a cluster of rocks is one node rather than one node per rock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local Properties = require(Shared:WaitForChild("Properties"))

local WorldBuilder = {}

-- A node needs an id the client can send back. Its own name is the natural one, and a name already
-- taken gets a suffix rather than quietly leaving a node unreachable. A `nodeId` set by hand is
-- honoured, which is how a node keeps the same id when it is renamed.
local function uniqueId(instance, taken)
	local id = instance:GetAttribute(Properties.nodeId)
	if type(id) ~= "string" or #id == 0 then
		id = instance.Name
	end
	local candidate = id
	local suffix = 2
	while taken[candidate] do
		candidate = string.format("%s_%d", id, suffix)
		suffix += 1
	end
	taken[candidate] = true
	return candidate
end

-- Workspace, the ore, and the pads. MiningService owns each node's health from here on;
-- EconomyService owns the pads.
function WorldBuilder.collect(config)
	local nodes = {}
	local pads = {}
	local claimed = {} -- objects that declared a kind: nothing inside them is looked at again
	local taken = {} -- node ids handed out, so that no two nodes share one
	local oreIds = table.concat(Properties.oreIds(config), ", ")

	-- An object nested inside one that already declared a kind is part of that object, not a
	-- placeable object of its own.
	local function insideClaimed(instance)
		local ancestor = instance.Parent
		while ancestor and ancestor ~= workspace do
			if claimed[ancestor] then
				return true
			end
			ancestor = ancestor.Parent
		end
		return false
	end

	local function adoptOre(instance)
		local oreId = instance:GetAttribute(Properties.oreId)
		if type(oreId) ~= "string" or not Formulas.ore(config, oreId) then
			warn(
				string.format(
					'[WorldBuilder] %s has kind "ore" but %s. The ores are: %s',
					instance.Name,
					type(oreId) == "string"
							and string.format("asks for ore %q, which does not exist", oreId)
						or "no oreId attribute",
					oreIds
				)
			)
			return
		end

		if not Properties.positionOf(instance) then
			warn(
				string.format(
					'[WorldBuilder] %s has kind "ore" but no parts inside it, so there is nothing '
						.. "to stand for it in the world",
					instance.Name
				)
			)
			return
		end

		local id = uniqueId(instance, taken)
		instance:SetAttribute(Properties.nodeId, id)
		local unlimited = instance:GetAttribute(Properties.unlimited) == true
		table.insert(nodes, {
			id = id,
			oreId = oreId,
			instance = instance,
			unlimited = unlimited,
		})

		print(
			string.format(
				"[WorldBuilder] %s is a %s node%s",
				instance.Name,
				oreId,
				unlimited and ", unlimited" or ""
			)
		)
	end

	for _, instance in ipairs(workspace:GetDescendants()) do
		if (instance:IsA("BasePart") or instance:IsA("Model")) and not insideClaimed(instance) then
			local kind = Properties.kindOf(instance)
			if kind == "ore" then
				claimed[instance] = true
				adoptOre(instance)
			elseif kind == "sellPad" then
				claimed[instance] = true
				table.insert(pads, instance)
				print(string.format("[WorldBuilder] %s is a Sell Pad", instance.Name))
			elseif instance:GetAttribute(Properties.kind) ~= nil then
				-- A kind nothing understands is a mistake rather than decoration, and either kind of
				-- silence here is an afternoon of wondering why a placed object does nothing.
				warn(
					string.format(
						"[WorldBuilder] %s has kind %q, which is not one of: %s",
						instance.Name,
						tostring(instance:GetAttribute(Properties.kind)),
						table.concat(Properties.kindNames(), ", ")
					)
				)
			elseif instance:GetAttribute(Properties.oreId) ~= nil then
				-- An ore id on an object that does not claim to be ore: the property that says so
				-- is missing, and naming it is the whole fix.
				warn(
					string.format(
						'[WorldBuilder] %s has an oreId but no kind: set its kind attribute to "ore"',
						instance.Name
					)
				)
			end
		end
	end

	if #nodes == 0 then
		warn(
			"[WorldBuilder] no ore in the place: place a part or a model, set its kind attribute to "
				.. '"ore" and its oreId to one of: '
				.. oreIds
		)
	end
	if #pads == 0 then
		warn(
			"[WorldBuilder] no Sell Pad in the place: place a part or a model and set its kind "
				.. 'attribute to "sellPad", and standing on it will sell'
		)
	elseif #pads > 1 then
		print(
			string.format(
				"[WorldBuilder] %d Sell Pads in this place; every one of them buys",
				#pads
			)
		)
	end

	return { nodes = nodes, pads = pads }
end

return WorldBuilder
