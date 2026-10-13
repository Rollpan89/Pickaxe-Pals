-- Setup check: if you can read this line in Studio's Output after pressing Play,
-- the project is syncing and the shared modules load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local freeDays = Formulas.daysToFinish(Config, {})
print(string.format("Pickaxe Pals server started. A free player finishes in %.1f days (the model says about 21).", freeDays))
