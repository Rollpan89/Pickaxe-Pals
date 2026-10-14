-- A stand-in for the Roblox globals a server module calls, plus the loader that hands them
-- over. Lune gives every module its own environment, so the module under test is loaded with
-- the globals it expects instead of this file reaching into _G.
--
-- WaitForChild returns a label such as "shared.Config" here; the loader maps labels to the
-- real shared modules. In the game those calls return Instances, which is what the real
-- DataService wants, so the same source line works in both.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local luneTask = require("@lune/task")

local RobloxStub = {}

function RobloxStub.newSignal()
	local listeners = {}
	local signal = {}

	function signal:Connect(callback)
		listeners[#listeners + 1] = callback
		return {
			Disconnect = function() end,
		}
	end

	function signal:Fire(...)
		for _, callback in ipairs(listeners) do
			callback(...)
		end
	end

	function signal:count()
		return #listeners
	end

	return signal
end

-- Loads one file with `environment` in place of `game` and `sharedModules` behind `require`.
-- `path` is relative to the folder lune was started in, which is the project root.
--
-- `extras` adds any further globals the module expects. A server module reaches its siblings
-- through `script.Parent`, so passing `{ script = { Parent = { State = "server.State" } } }`
-- hands it the label that `require` then resolves, the same trick WaitForChild uses above.
function RobloxStub.loadModule(path, sharedModules, environment, extras)
	local source = fs.readFile(path)
	local globals = {
		game = environment.game,
		task = luneTask,
		os = os,
		require = function(label)
			local module = sharedModules[label]
			if module == nil then
				error(string.format("the stub has no module labelled %q", tostring(label)), 2)
			end
			return module
		end,
	}
	for key, value in pairs(extras or {}) do
		globals[key] = value
	end
	return luau.load(source, { environment = globals })()
end

-- The services, players and shutdown hook a server script sees, with the handful of methods
-- DataService calls. `join` and `leave` fire the signals the way Roblox does.
function RobloxStub.newEnvironment()
	local environment = {
		players = {},
		kicks = {}, -- [userId] = the message the player was kicked with
		closeCallbacks = {},
	}

	local shared = {
		WaitForChild = function(_, name)
			return "shared." .. name
		end,
	}

	local players = {
		PlayerAdded = RobloxStub.newSignal(),
		PlayerRemoving = RobloxStub.newSignal(),
	}
	function players:GetPlayers()
		return table.clone(environment.players)
	end

	local services = {
		Players = players,
		ServerScriptService = {},
		ReplicatedStorage = {
			WaitForChild = function(_, name)
				if name == "Shared" then
					return shared
				end
				return "shared." .. name
			end,
		},
		RunService = {
			IsStudio = function()
				return false
			end,
		},
	}

	local game = {}
	function game:GetService(name)
		local service = services[name]
		if not service then
			error(string.format("the stub has no service named %q", tostring(name)), 2)
		end
		return service
	end
	function game:BindToClose(callback)
		environment.closeCallbacks[#environment.closeCallbacks + 1] = callback
	end

	environment.game = game

	function environment:join(userId, name)
		local player = {
			UserId = userId,
			Name = name or string.format("Player%d", userId),
			Parent = players,
		}
		function player:Kick(message)
			environment.kicks[userId] = message
		end

		environment.players[#environment.players + 1] = player
		players.PlayerAdded:Fire(player)
		return player
	end

	function environment:leave(player)
		player.Parent = nil
		local index = table.find(environment.players, player)
		if index then
			table.remove(environment.players, index)
		end
		players.PlayerRemoving:Fire(player)
	end

	-- What Roblox does on shutdown: every BindToClose callback runs.
	function environment:shutdown()
		for _, callback in ipairs(environment.closeCallbacks) do
			callback()
		end
	end

	return environment
end

return RobloxStub
