-- The client only shows the game and asks the server for things.
-- Hold the mouse button or your finger on an ore node to mine it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Properties = require(Shared:WaitForChild("Properties"))

local Hud = require(script.Parent.Hud)
local Remotes = require(script.Parent.Remotes)

local player = Players.LocalPlayer

local state -- the last snapshot the server sent
local holding = false
local aimPosition = Vector2.new(0, 0)
local secondsSinceHit = 0

print("Pickaxe Pals client started. Hold on an ore node to mine it.")

-- A node is a part or a model, so the ray hits one part of it and the node is whichever object
-- above that carries the id. Walking up is what lets a cluster of rocks be a single node.
local function nodeOf(part)
	local instance = part
	while instance and instance ~= workspace do
		local nodeId = instance:GetAttribute(Properties.nodeId)
		if type(nodeId) == "string" and #nodeId > 0 then
			return nodeId
		end
		instance = instance.Parent
	end
	return nil
end

-- The server checks all of this again; this copy only keeps the aim and the pace honest.
local function aimedNode()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local ray = camera:ViewportPointToRay(aimPosition.X, aimPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result =
		workspace:Raycast(ray.Origin, ray.Direction * Config.mining.nodeRangeStuds, params)
	local part = result and result.Instance
	if not part then
		return nil, nil
	end
	return nodeOf(part), part
end

local function wobble(part)
	local original = part.CFrame
	part.CFrame = original * CFrame.Angles(0, 0, math.rad(6))
	TweenService:Create(part, TweenInfo.new(0.12), { CFrame = original }):Play()
end

RunService.Heartbeat:Connect(function(deltaTime)
	if not holding or not state then
		return
	end

	secondsSinceHit += deltaTime
	local pickaxe = Formulas.pickaxe(Config, state.pickaxeTier)
	if secondsSinceHit < pickaxe.cooldown then
		return
	end

	local nodeId, part = aimedNode()
	if not nodeId or not part then
		return
	end

	secondsSinceHit = 0
	Remotes.get("mineHit"):FireServer(nodeId)
	wobble(part)
end)

local function rememberAim(input)
	aimPosition = Vector2.new(input.Position.X, input.Position.Y)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		rememberAim(input)
		holding = true
	end
end)

UserInputService.InputChanged:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
		rememberAim(input)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		holding = false
	end
end)

Remotes.get("stateChanged").OnClientEvent:Connect(function(snapshot)
	state = snapshot
	Hud.update(snapshot)
end)

Remotes.get("notify").OnClientEvent:Connect(function(message)
	Hud.toast(message)
end)

Hud.new(function(kind)
	Remotes.get("buyUpgrade"):FireServer(kind)
end)

-- Ask for the first snapshot now that the handlers above are connected.
Remotes.get("requestState"):FireServer()
