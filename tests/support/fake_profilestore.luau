-- A stand-in for ProfileStore with the shapes the real module documents: a store made by
-- New(), StartSessionAsync() returning a profile or nil, and a profile with Data, IsActive,
-- EndSession, Save and the OnSessionEnd signal. Every call is recorded, which is how the
-- lifecycle test checks what DataService asked the store to do.

local RobloxStub = require("./roblox_stub")

local FakeProfileStore = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deepCopy(entry)
	end
	return copy
end

-- Returns the module to hand to DataService and the `fake` table the test inspects:
-- `saved[key]` is what a returning player has on the store, `refuse[key]` makes a load fail,
-- and `records[key]` counts the calls made about that key.
function FakeProfileStore.new()
	local fake = {
		saved = {},
		refuse = {},
		records = {},
		profiles = {},
		IsClosing = false,
		newCalls = 0,
	}

	local function record(key)
		local entry = fake.records[key]
		if not entry then
			entry = { startSession = 0, save = 0, endSession = 0 }
			fake.records[key] = entry
		end
		return entry
	end

	local function newProfile(key, data)
		local profile = { Key = key, Data = data, userId = nil, active = true }
		profile.OnSessionEnd = RobloxStub.newSignal()

		function profile:IsActive()
			return profile.active
		end

		function profile:AddUserId(userId)
			profile.userId = userId
		end

		function profile:Save()
			record(key).save += 1
		end

		function profile:EndSession()
			record(key).endSession += 1
			if not profile.active then
				return -- the real module is safe to call on an ended session
			end
			profile.active = false
			profile.OnSessionEnd:Fire()
		end

		return profile
	end

	local module = {}

	function module.New(storeName, template)
		fake.newCalls += 1
		fake.storeName = storeName
		fake.template = template

		local store = { Name = storeName }

		function store:StartSessionAsync(key, params)
			local entry = record(key)
			entry.startSession += 1
			entry.cancel = params and params.Cancel

			if fake.refuse[key] then
				return nil
			end

			local profile = newProfile(key, fake.saved[key] or deepCopy(template))
			fake.profiles[key] = profile
			return profile
		end

		-- The real Mock hangs off the store rather than the module.
		store.Mock = { Name = storeName, isMock = true }

		return store
	end

	return module, fake
end

return FakeProfileStore
