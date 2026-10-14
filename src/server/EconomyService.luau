-- Selling the backpack and buying upgrades. Both are decided here from the saved profile,
-- so the client can only ask for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Properties = require(Shared:WaitForChild("Properties"))

local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local EconomyService = {}

local function characterRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- Walking onto the Sell Pad is the whole interaction: no button, no confirm step.
local function sellBackpack(player, data)
	local backpack = DataService.backpack(player)
	if not backpack then
		return
	end

	local total = Formulas.sellValue(Config, backpack, data.rebirths)
	if total <= 0 then
		return
	end

	data.coins += total
	table.clear(backpack)
	State.push(player)
	State.notify(player, string.format("Sold for %d coins.", total))
end

-- Each Sell Pad the place has watches its own surroundings, so a world can have one by the mine
-- and another near the shop. A pad is anchored by definition, so where it is is read once.
local function watchSellPad(sellPad)
	local position = Properties.positionOf(sellPad)
	if not position then
		warn(
			string.format(
				"[EconomyService] the Sell Pad %s has no parts in it, so nobody can stand on it",
				sellPad.Name
			)
		)
		return
	end

	task.spawn(function()
		while sellPad.Parent do
			for _, player in ipairs(Players:GetPlayers()) do
				local data = DataService.get(player)
				local root = characterRoot(player)
				if
					data
					and root
					and (position - root.Position).Magnitude <= Config.mining.sellRangeStuds
				then
					sellBackpack(player, data)
				end
			end
			task.wait(Config.mining.sellIntervalSeconds)
		end
	end)
end

local function buyPickaxe(player, data)
	local nextTier = Formulas.nextPickaxeTier(Config, data.pickaxeTier)
	if not nextTier then
		State.notify(player, "That is the best pickaxe for now.")
		return
	end
	if data.rebirths < nextTier.unlockRebirth then
		State.notify(player, string.format("Locked until rebirth %d.", nextTier.unlockRebirth))
		return
	end
	if data.coins < nextTier.cost then
		State.notify(player, string.format("You need %d coins for that.", nextTier.cost))
		return
	end

	data.coins -= nextTier.cost
	data.pickaxeTier = nextTier.tier
	State.push(player)
	State.notify(player, string.format("Bought the %s. Mining is faster.", nextTier.name))
end

local function buyBackpack(player, data)
	local nextLevel = Formulas.nextBackpackLevel(Config, data.backpackLevel)
	if not nextLevel then
		State.notify(player, "That is the biggest backpack for now.")
		return
	end
	if data.coins < nextLevel.cost then
		State.notify(player, string.format("You need %d coins for that.", nextLevel.cost))
		return
	end

	data.coins -= nextLevel.cost
	data.backpackLevel = nextLevel.level
	State.push(player)
	State.notify(
		player,
		string.format("Bought the %s. It holds %d ore.", nextLevel.name, nextLevel.capacity)
	)
end

local function onBuyUpgrade(player, kind)
	local data = DataService.get(player)
	if not data then
		return
	end

	if kind == "pickaxe" then
		buyPickaxe(player, data)
	elseif kind == "backpack" then
		buyBackpack(player, data)
	else
		warn(
			string.format(
				"[EconomyService] %s asked for an unknown upgrade: %s",
				player.Name,
				tostring(kind)
			)
		)
	end
end

function EconomyService.start(world)
	-- A pad is a placeable object like any other, so a place without one simply has no way to sell
	-- yet. Saying so beats starting a loop that would error on nil, and the warning WorldBuilder
	-- already printed says what to place.
	if #world.pads == 0 then
		warn("[EconomyService] there is no Sell Pad, so nothing can be sold in this place")
	end
	for _, sellPad in ipairs(world.pads) do
		watchSellPad(sellPad)
	end

	Remotes.get("buyUpgrade").OnServerEvent:Connect(onBuyUpgrade)
end

return EconomyService
