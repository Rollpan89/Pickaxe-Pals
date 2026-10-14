-- The heads-up display: coins, backpack fill and the two upgrade buttons.
-- It shows only the state the server sends and asks the server for upgrades, so a wrong
-- number here is a display bug, never a balance bug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local Hud = {}

local player = Players.LocalPlayer

local gui
local coinsLabel
local packLabel
local pickaxeButton
local backpackButton
local toastLabel
local toastToken = 0

local AFFORDABLE = Color3.fromRGB(72, 158, 96)
local TOO_EXPENSIVE = Color3.fromRGB(92, 88, 104)

local function newInstance(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function makeUpgradeButton(name, position, onActivated)
	local button = newInstance("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = TOO_EXPENSIVE,
		Font = Enum.Font.Gotham,
		Position = position,
		-- Size = UDim2.new(1, -24, 0, 26),
		Size = UDim2.new(0.2, 300, 0, 26),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 13,
	}, gui)
	button.Activated:Connect(onActivated)
	return button
end

-- Buttons stay clickable when the price is out of reach: the server answers with the price,
-- which is friendlier than a dead button.
local function setUpgradeButton(button, currentName, next, coins)
	if next then
		button.Text = string.format("%s -> %s (%d coins)", currentName, next.name, next.cost)
		button.BackgroundColor3 = if coins >= next.cost then AFFORDABLE else TOO_EXPENSIVE
	else
		button.Text = string.format("%s (best)", currentName)
		button.BackgroundColor3 = TOO_EXPENSIVE
	end
end

function Hud.new(onBuyUpgrade)
	local playerGui = player:WaitForChild("PlayerGui")

	gui = newInstance("ScreenGui", {
		Name = "PickaxePalsHud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local panel = newInstance("Frame", {
		Name = "Stats",
		BackgroundColor3 = Color3.fromRGB(28, 26, 38),
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(248, 152),
	}, gui)
	newInstance("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)

	newInstance("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 22),
		Text = Config.layers[1].name,
		TextColor3 = Color3.fromRGB(255, 214, 120),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	coinsLabel = newInstance("TextLabel", {
		Name = "Coins",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "Coins: 0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	packLabel = newInstance("TextLabel", {
		Name = "Backpack",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "Backpack: 0 / 0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	pickaxeButton = makeUpgradeButton("BuyPickaxe", UDim2.fromOffset(12, 88), function()
		onBuyUpgrade("pickaxe")
	end)
	backpackButton = makeUpgradeButton("BuyBackpack", UDim2.fromOffset(12, 118), function()
		onBuyUpgrade("backpack")
	end)

	toastLabel = newInstance("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(114, 38, 38),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(420, 30),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		TextTransparency = 1,
	}, gui)
	newInstance("UICorner", { CornerRadius = UDim.new(0, 8) }, toastLabel)

	newInstance("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(560, 22),
		Text = "Hold on an ore node to mine. Stand on the Sell Pad to sell.",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 15,
		TextStrokeTransparency = 0.6,
	}, gui)

	return Hud
end

function Hud.update(state)
	if not gui then
		return
	end

	local pickaxe = Formulas.pickaxe(Config, state.pickaxeTier)
	local backpack = Formulas.backpack(Config, state.backpackLevel)

	coinsLabel.Text = string.format("Coins: %d", state.coins)
	packLabel.Text =
		string.format("Backpack: %d / %d", Formulas.backpackTotal(state.backpack), state.capacity)

	setUpgradeButton(
		pickaxeButton,
		pickaxe.name,
		Formulas.nextPickaxeTier(Config, state.pickaxeTier),
		state.coins
	)
	setUpgradeButton(
		backpackButton,
		backpack.name,
		Formulas.nextBackpackLevel(Config, state.backpackLevel),
		state.coins
	)
end

function Hud.toast(message)
	if not gui then
		return
	end

	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.25

	task.delay(2.5, function()
		if toastToken ~= token then
			return
		end
		local fade = TweenService:Create(toastLabel, TweenInfo.new(0.6), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fade:Play()
	end)
end

return Hud
