-- The server creates every RemoteEvent, so the client can only wait for them.
-- Names come from Config.remotes, which keeps the two sides from drifting apart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Remotes = {}
local events = {}

function Remotes.start()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for key, name in pairs(Config.remotes) do
		local event = folder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
		events[key] = event
	end
end

function Remotes.get(key)
	local event = events[key]
	assert(event, string.format("Remotes.start() has not created %q yet", key))
	return event
end

return Remotes
