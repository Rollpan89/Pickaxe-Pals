-- The slice of player state the client is allowed to see, and the two messages the server
-- sends back. The client never edits these numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)

local State = {}

function State.snapshot(data, backpack)
	return {
		coins = data.coins,
		gems = data.gems,
		rebirths = data.rebirths,
		pickaxeTier = data.pickaxeTier,
		backpackLevel = data.backpackLevel,
		backpack = table.clone(backpack),
		capacity = Formulas.backpackCapacity(Config, data.backpackLevel),
	}
end

function State.push(player)
	local data = DataService.get(player)
	local backpack = DataService.backpack(player)
	if not data or not backpack then
		return
	end
	Remotes.get("stateChanged"):FireClient(player, State.snapshot(data, backpack))
end

function State.notify(player, message)
	Remotes.get("notify"):FireClient(player, message)
end

return State
