--[[
	ItemShop (ModuleScript) — boutique d'objets cosmétiques
	Emplacement : ReplicatedStorage > Client > Components > Panels > ItemShop

	Chapeaux (posés sur le bouton "Clique-moi") et couleurs du bouton.
	Achat / équipement / retrait via la RemoteFunction "ItemShop".
	Chaque objet possédé donne un petit bonus permanent (Config.CosmeticBonus).
	Débloqué par l'amélioration "Boutique d'objets" (Feature "ItemShop").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local ItemShop = {
	Title = "🛒 Boutique",
	Color = Theme.Colors.Green,
	Size = Vector2.new(720, 520),
}

local SLOT_NAMES = { Hat = "Chapeau", Skin = "Couleur du bouton" }

local header: TextLabel
local cards = {} -- [id] = { Card, Stroke, Button, Status, Cosmetic }
local busy = false

local function getCosmetics(data)
	local cosmetics = data and data.Cosmetics
	local owned = (cosmetics and cosmetics.Owned) or {}
	local equipped = (cosmetics and cosmetics.Equipped) or {}
	return owned, equipped
end

-- Envoie une action au serveur ("buy" | "equip" | "unequip")
local function request(action: string, cosmetic)
	if busy then
		return
	end
	busy = true
	local ok, success, message = pcall(function()
		return Net.Function("ItemShop"):InvokeServer(action, cosmetic.Id)
	end)
	busy = false

	local ui = cards[cosmetic.Id]
	if ok and success then
		if action == "buy" then
			SoundManager.Play("Buy", 1.1)
			Effects.Confetti(40)
			Notifications.Toast(
				cosmetic.Icon .. " " .. cosmetic.Name .. " : à toi ! (+" .. math.floor(Config.CosmeticBonus * 100 + 0.5) .. " % de gains)",
				Theme.Colors.Green,
				4
			)
		else
			SoundManager.Play("Open", action == "equip" and 1.2 or 0.9)
		end
		if ui then
			local scale = ui.Card:FindFirstChild("PopScale") :: UIScale?
			if scale then
				scale.Scale = 1.08
				UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	else
		SoundManager.Play("Error", 0.7)
		if ui then
			UIUtil.Shake(ui.Button)
		end
		local text = ok and tostring(message or "Impossible pour le moment.") or "Erreur réseau, réessaie."
		Notifications.Toast(text, Theme.Colors.Red)
	end
end

local function buildCard(list: ScrollingFrame, cosmetic)
	local card = UIUtil.Create("Frame", {
		Name = cosmetic.Id,
		BackgroundColor3 = Theme.Colors.Card,
		LayoutOrder = cosmetic.Order or 0,
		Parent = list,
	})
	UIUtil.Corner(card, 14)
	local stroke = UIUtil.Stroke(card, Theme.Colors.CardBorder, 1.5)
	UIUtil.Create("UIScale", { Name = "PopScale", Parent = card })

	-- Aperçu : emoji du chapeau, ou pastille aux couleurs du bouton
	local preview = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(64, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		BackgroundTransparency = 1,
		Parent = card,
	})
	if cosmetic.Slot == "Skin" and cosmetic.Top and cosmetic.Bottom then
		local swatch = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(70, 34),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = preview,
		})
		UIUtil.Corner(swatch, 8)
		UIUtil.Stroke(swatch, Theme.Colors.Border, 1.5)
		UIUtil.Gradient(swatch, ColorSequence.new(cosmetic.Top, cosmetic.Bottom), 90)
		UIUtil.Label({
			Text = "Clique-moi",
			TextColor3 = Theme.ContrastText(cosmetic.Bottom),
			Size = UDim2.new(1, -6, 1, -6),
			Position = UDim2.fromOffset(3, 3),
			MaxTextSize = 13,
			Parent = swatch,
		})
	else
		UIUtil.Label({
			Text = cosmetic.Icon,
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 44,
			Parent = preview,
		})
	end

	UIUtil.Label({
		Text = cosmetic.Name,
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 66),
		MaxTextSize = 16,
		Parent = card,
	})
	local status = UIUtil.Label({
		Text = SLOT_NAMES[cosmetic.Slot] or "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 86),
		MaxTextSize = 13,
		Parent = card,
	})

	local button = UIUtil.NeonButton({
		Text = "",
		Size = UDim2.new(1, -20, 0, 34),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Color = Theme.Colors.Green,
		CornerRadius = 17,
		MaxTextSize = 17,
		Parent = card,
	})
	button.Activated:Connect(function()
		local data = ClientState.Data
		if not data then
			return
		end
		local owned, equipped = getCosmetics(data)
		if not owned[cosmetic.Id] then
			if not button:GetAttribute("Enabled") then
				SoundManager.Play("Error", 0.7)
				UIUtil.Shake(button)
				return
			end
			task.spawn(request, "buy", cosmetic)
		elseif equipped[cosmetic.Slot] == cosmetic.Id then
			task.spawn(request, "unequip", cosmetic)
		else
			task.spawn(request, "equip", cosmetic)
		end
	end)

	cards[cosmetic.Id] = { Card = card, Stroke = stroke, Button = button, Status = status, Cosmetic = cosmetic }
end

function ItemShop.Build(content: Frame)
	header = UIUtil.Label({
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = content,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -32),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Green,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
		Parent = list,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 0, 156),
		CellPadding = UDim2.fromOffset(9, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for _, cosmetic in ipairs(Config.Cosmetics) do
		buildCard(list, cosmetic)
	end
end

function ItemShop.Update(data)
	local owned, equipped = getCosmetics(data)
	local dopamine = data.Dopamine or 0
	local ownedCount = 0

	for id, ui in pairs(cards) do
		local cosmetic = ui.Cosmetic
		local isOwned = owned[id] == true
		local isEquipped = isOwned and equipped[cosmetic.Slot] == id
		if isOwned then
			ownedCount += 1
		end

		if isEquipped then
			ui.Button.Text = "Retirer"
			ui.Button:SetAttribute("BaseColor", Theme.Colors.ButtonBottom)
			UIUtil.SetButtonEnabled(ui.Button, true)
			ui.Button.TextColor3 = Theme.Colors.Text
			ui.Status.Text = "✔ Équipé"
			ui.Status.TextColor3 = Theme.Colors.Green
			ui.Stroke.Color = Theme.Colors.Green
			ui.Stroke.Thickness = 3
		elseif isOwned then
			ui.Button.Text = "Équiper"
			ui.Button:SetAttribute("BaseColor", Theme.Colors.Blue)
			UIUtil.SetButtonEnabled(ui.Button, true)
			ui.Button.TextColor3 = Theme.Colors.TextLight
			ui.Status.Text = "Possédé"
			ui.Status.TextColor3 = Theme.Colors.TextDim
			ui.Stroke.Color = Theme.Colors.CardBorder
			ui.Stroke.Thickness = 1.5
		else
			local affordable = dopamine >= cosmetic.Cost
			ui.Button.Text = "💧 " .. NumberFormatter.Format(cosmetic.Cost)
			ui.Button:SetAttribute("BaseColor", Theme.Colors.Green)
			UIUtil.SetButtonEnabled(ui.Button, affordable)
			ui.Button.TextColor3 = Theme.Colors.TextDark
			ui.Status.Text = SLOT_NAMES[cosmetic.Slot] or ""
			ui.Status.TextColor3 = affordable and Theme.Colors.TextDim or Theme.Colors.Red
			ui.Stroke.Color = Theme.Colors.CardBorder
			ui.Stroke.Thickness = 1.5
		end
	end

	header.Text = string.format(
		"%d / %d objets  •  +%d %% par objet (bonus actuel +%d %%)",
		ownedCount,
		#Config.Cosmetics,
		math.floor(Config.CosmeticBonus * 100 + 0.5),
		math.floor(ownedCount * Config.CosmeticBonus * 100 + 0.5)
	)
end

return ItemShop
