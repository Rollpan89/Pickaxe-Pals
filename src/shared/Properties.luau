-- The vocabulary of placeable objects. Every part or model the game plays is one of the kinds
-- below, and says which with a `kind` attribute. This module is the single home of those names
-- and the values they accept, so no two services can drift apart, and the tests can hold what is
-- accepted up against Config.
--
-- Authored by hand in Studio, in the Properties panel's Attributes section:
--
--   kind       "ore" | "sellPad"    what the object is; with no kind it is decoration
--   oreId      a configured ore id  which ore a kind = "ore" object is
--   unlimited  true | false         a kind = "ore" object that never runs dry
--
-- Written by the server once it has found an object, and not for authoring:
--
--   nodeId, health, maxHealth       what the client aims at, and how much of it is left

local Properties = {}

-- Every kind, and what placing one gets you. This table is the whole answer to "what can I put in
-- the world", and it only grows when something reads the kind: a property with nothing behind it
-- is worse than no property at all, because it looks like it works.
Properties.kinds = {
	ore = "a mineable node: hold on it to mine, and it pays out when it breaks",
	sellPad = "standing on it sells everything in the backpack",
}

-- Property names, so no service spells one of them by hand.
Properties.kind = "kind"
Properties.oreId = "oreId"
Properties.unlimited = "unlimited"
Properties.nodeId = "nodeId"
Properties.health = "health"
Properties.maxHealth = "maxHealth"

-- The kinds that are accepted, sorted, for a message that has to list them.
function Properties.kindNames()
	local names = {}
	for name in pairs(Properties.kinds) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Every ore id the config knows, sorted, for the same reason.
function Properties.oreIds(config)
	local seen = {}
	local names = {}
	for _, layer in ipairs(config.layers) do
		for _, ore in ipairs(layer.ores) do
			if not seen[ore.id] then
				seen[ore.id] = true
				table.insert(names, ore.id)
			end
		end
	end
	table.sort(names)
	return names
end

-- The kind an object claims, or nil when it claims none. A kind that is not in the table is a
-- mistake rather than decoration, so it answers nil here and the caller, which is the code that
-- knows what it was looking for, is the one to say so; a reader that warns on its own would report
-- a mistyped property into a module the tests cannot listen to.
function Properties.kindOf(instance)
	local kind = instance:GetAttribute(Properties.kind)
	if kind ~= nil and Properties.kinds[kind] then
		return kind
	end
	return nil
end

-- Where an object is. A model uses its PrimaryPart when it has one, so the designer decides where
-- the middle of a cluster of rocks is; otherwise the first part inside it stands in.
function Properties.positionOf(instance)
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance.PrimaryPart then
		return instance.PrimaryPart.Position
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end
	return nil
end

-- Every part of an object: itself when it is one part, its parts when it is a model.
function Properties.partsOf(instance)
	if instance:IsA("BasePart") then
		return { instance }
	end
	local parts = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

return Properties
