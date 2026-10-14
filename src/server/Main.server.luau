-- Server entry point: finds the world in the place and starts the services.
-- Setup check: if you can read this in Studio's Output after pressing Play, the project is
-- syncing and the shared modules load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MiningService = require(script.Parent.MiningService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local WorldBuilder = require(script.Parent.WorldBuilder)

local freeDays = Formulas.daysToFinish(Config, {})
print(
	string.format(
		"Pickaxe Pals server started. A free player finishes in %.1f days (the model says about 21).",
		freeDays
	)
)

Remotes.start()
local world = WorldBuilder.collect(Config)

-- DataService owns the join: it loads the profile before the player can act, and this
-- callback pushes the first state once that profile is in memory.
DataService.start({
	onLoaded = function(player)
		State.push(player)
	end,
})

print(string.format("Saving player profiles as %s with ProfileStore.", Config.saving.storeName))

-- The client asks for its first state once its handlers are connected, because the push
-- above may arrive before the client is listening.
Remotes.get("requestState").OnServerEvent:Connect(function(player)
	State.push(player)
end)

MiningService.start(world)
EconomyService.start(world)

print(
	string.format(
		"Sunny Burrow is live: hold on an ore node to mine it%s.",
		#world.pads > 0 and ", stand on the Sell Pad to sell" or " (no Sell Pad in this place yet)"
	)
)
