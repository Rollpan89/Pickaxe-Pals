-- Client half of the remote names in Config.remotes. The server creates the events; this
-- module waits for them so a client script can never create one by accident.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local folder = ReplicatedStorage:WaitForChild("Remotes")

local Remotes = {}
local events = {}

for key, name in pairs(Config.remotes) do
	events[key] = folder:WaitForChild(name)
end

function Remotes.get(key)
	local event = events[key]
	assert(event, string.format("no remote named %q in Config.remotes", key))
	return event
end

return Remotes
