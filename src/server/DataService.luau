-- Player profiles: load on join, autosave while playing, save on leave and on shutdown.
--
-- ProfileStore (installed with Wally into ServerPackages) does the DataStore work and the
-- session locking that stops two servers from writing the same player at once. This module
-- owns everything around it: the architecture document's rule that a profile is loaded before
-- the player can act, the version upgrades in Schema, and, per that document, the shutdown path
-- where progress is most likely to be lost.
--
-- Carried ore is deliberately not part of the saved profile (see Schema), so it lives in the
-- session record below and lasts one visit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Schema = require(Shared:WaitForChild("Schema"))

local DataService = {}

local sessions = {} -- [player] = { profile, data, backpack }
local closing = {} -- [player] = true while this server is the one ending the session
local profileStoreModule
local profileStore
local started = false

local function resolveProfileStore()
	local packages = ServerScriptService:WaitForChild("ServerPackages")
	return require(packages:WaitForChild("ProfileStore"))
end

-- `Mock` hangs off the store, not the module: it answers the same methods but reads and
-- writes a throwaway DataStore, which is what a playtest wants when it should not touch the
-- real saves. Tests pass their own module instead.
local function resolveStore(module)
	local store = module.New(Config.saving.storeName, Schema.template)
	if Config.saving.useMockInStudio and RunService:IsStudio() then
		warn("[DataService] ProfileStore.Mock is on: this session will not save.")
		return store.Mock
	end
	return store
end

-- Runs when the session ends on this server, whether we ended it or another server took the
-- profile. In that second case the data in memory is no longer guaranteed to save, so the
-- player is better off rejoining than carrying on.
local function onSessionEnd(player)
	sessions[player] = nil
	if closing[player] then
		return -- we ended it on purpose, as part of leaving or shutting down
	end
	if profileStoreModule.IsClosing then
		return -- the server is going down and the store is already saving everything
	end
	if player.Parent == Players then
		player:Kick("Your save session ended. Please rejoin.")
	end
end

local function load(player)
	local profile = profileStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		player:Kick("Could not load your save. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)

	-- Schema.prepare upgrades and checks the save in place, and refuses one it must not open.
	local data, problem = Schema.prepare(Config, profile.Data)
	if not data then
		closing[player] = true
		profile:EndSession() -- release the lock rather than leave it held
		closing[player] = nil
		player:Kick(problem .. " Please rejoin.")
		return
	end

	sessions[player] = { profile = profile, data = data, backpack = {} }

	profile.OnSessionEnd:Connect(function()
		onSessionEnd(player)
	end)

	-- The player may have left while the profile was loading.
	if player.Parent ~= Players then
		DataService.release(player)
		return
	end

	if DataService.onLoaded then
		DataService.onLoaded(player)
	end
end

function DataService.start(deps)
	deps = deps or {}
	assert(not started, "DataService.start() was already called")
	started = true

	DataService.onLoaded = deps.onLoaded

	profileStoreModule = deps.profileStore or resolveProfileStore()
	profileStore = resolveStore(profileStoreModule)

	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		DataService.release(player)
	end)

	-- A player can join before this connects, so pick up whoever is already here.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end

	game:BindToClose(function()
		DataService.shutdown()
	end)
end

-- Saves and releases one profile. Safe to call twice: the second call has nothing to release.
function DataService.release(player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil

	if type(session.data) == "table" then
		session.data.lastSeen = os.time()
	end

	if session.profile:IsActive() then
		closing[player] = true
		session.profile:EndSession()
		closing[player] = nil
	end
end

-- Releases every open profile. Called when the server shuts down, which is the case most
-- likely to lose progress, so it is also the one the tests drive by hand.
function DataService.shutdown()
	local players = {}
	for player in pairs(sessions) do
		players[#players + 1] = player
	end
	for _, player in ipairs(players) do
		DataService.release(player)
	end
end

-- An immediate save, for the moments the document calls critical, such as granting a
-- developer product. Ordinary play leans on the store's own autosave: each Save() costs a
-- DataStore request.
function DataService.save(player)
	local session = sessions[player]
	if session and session.profile:IsActive() then
		session.profile:Save()
	end
end

-- The saved profile, or nil before it is loaded and after the player leaves. Every request
-- path checks this, and that check is what enforces the rule that a new join is loaded before
-- the player can act.
function DataService.get(player)
	local session = sessions[player]
	return session and session.data
end

-- Ore carried this visit. A live table: mining fills it, selling empties it.
function DataService.backpack(player)
	local session = sessions[player]
	return session and session.backpack
end

function DataService.isLoaded(player)
	return sessions[player] ~= nil
end

return DataService
