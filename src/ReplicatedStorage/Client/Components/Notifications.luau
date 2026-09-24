--[[
	Notifications (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Notifications

	Petits bandeaux ("toasts") blancs en bas de l'écran : ombre douce,
	liseré de couleur à gauche, titre optionnel et petite barre de temps
	restant. Un clic ferme le bandeau.
	Réagit aussi aux notifications du serveur (Info, Error, Achievement,
	Quest, Rush, Jackpot, Unlock, Detox, Purchase).
	Les notifications "Bonus" sont envoyées aux stimuli par StimulusManager.
]]

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local ClientState = require(Client.ClientState)

local Notifications = {}

local container: Frame? = nil
local MAX_TOASTS = 4
local TOAST_WIDTH = 440
local order = 0

function Notifications.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(TOAST_WIDTH + 20, 320),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIUtil.Create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = frame,
	})
	container = frame
end

-- Affiche un bandeau temporaire.
-- `celebrate` = true : style festif (fond doré, étincelles) pour les achats.
function Notifications.Toast(text: string, color: Color3?, duration: number?, title: string?, celebrate: boolean?)
	local target = container
	if not target or not text or text == "" then
		return
	end

	-- Supprime les plus anciens s'il y en a trop
	local existing = {}
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing >= MAX_TOASTS do
		local oldest = table.remove(existing, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	order += 1
	local accent = color or Theme.Colors.Blue
	local height = title and 64 or 46
	local lifetime = duration or 3.5

	-- Support (dans la liste) : porte l'ombre et l'animation d'apparition
	local holder = UIUtil.Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_WIDTH, height),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = target,
	})
	local scale = UIUtil.Create("UIScale", { Scale = 0.5, Parent = holder })

	-- TextButton (et non Frame) : le bandeau capte les clics au lieu de les laisser
	-- passer aux cartes / boutons en dessous ; un clic le ferme
	local toast = UIUtil.Create("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 16),
		BackgroundColor3 = Theme.Colors.Card,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = holder,
	})
	UIUtil.Corner(toast, 14)
	UIUtil.Stroke(toast, Theme.Colors.CardBorder, 1.5, celebrate and 0 or 0.35)
	UIUtil.Shadow(toast, 4, 0.8)
	if celebrate then
		UIUtil.Gradient(toast, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 225)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 232, 170)),
		}), 0)
	end

	-- Liseré de couleur à gauche
	UIUtil.Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = toast,
	})

	local textRight = celebrate and 54 or 20
	if title then
		UIUtil.Label({
			Text = title,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -(20 + textRight), 0, 22),
			Position = UDim2.fromOffset(20, 8),
			MaxTextSize = 17,
			ZIndex = 3,
			Parent = toast,
		})
	end
	UIUtil.Label({
		Text = text,
		TextColor3 = title and Theme.Colors.TextDim or Theme.Colors.Text,
		Font = title and Theme.Fonts.Body or Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(20 + textRight), 0, 24),
		Position = UDim2.fromOffset(20, title and 31 or 10),
		MaxTextSize = title and 16 or 17,
		ZIndex = 3,
		Parent = toast,
	})

	-- Étincelle qui tourne (style festif)
	if celebrate then
		local sparkle = UIUtil.Label({
			Text = "✨",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -28, 0.5, 0),
			Size = UDim2.fromOffset(34, 34),
			MaxTextSize = 30,
			ZIndex = 3,
			Parent = toast,
		})
		UIUtil.Tween(sparkle, lifetime, { Rotation = 360 }, Enum.EasingStyle.Linear)
	end

	-- Barre de temps restant (en bas)
	local timer = UIUtil.Create("Frame", {
		Name = "Timer",
		Size = UDim2.new(1, 0, 0, 3),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = toast,
	})
	UIUtil.Tween(timer, lifetime, { Size = UDim2.new(0, 0, 0, 3) }, Enum.EasingStyle.Linear)

	-- Apparition : zoom + glissement vers le haut
	UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	UIUtil.Tween(toast, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)

	local closing = false
	local function close()
		if closing or not holder.Parent then
			return
		end
		closing = true
		UIUtil.Tween(scale, 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.25, function()
			holder:Destroy()
		end)
	end
	toast.Activated:Connect(close)
	task.delay(lifetime, close)
end

-- Petite explosion au centre (vers le bouton) pour les déblocages
local function centerBurst(color: Color3?)
	local layer = Effects.GetLayer()
	if layer then
		Effects.Burst(layer, UDim2.new(0.5, 0, 0, 140), color, 16)
	end
end

-- Achat Robux confirmé : grosse fête
local function celebratePurchase(payload)
	SoundManager.Play("Jackpot", 0.9)
	task.delay(0.12, SoundManager.Play, "Jackpot", 1.2)
	task.delay(0.24, SoundManager.Play, "Achievement", 1.5)
	Effects.Flash(Theme.Colors.Premium, 0.35)
	Effects.Confetti(120)
	centerBurst(Theme.Colors.Premium)
	Effects.BigMessage("💎 MERCI ! 💎", Theme.Colors.Premium, 2.2)
	Notifications.Toast(
		tostring(payload.Text or "Ton achat est arrivé !"),
		Theme.Colors.Robux,
		6,
		payload.Title or "💎 ACHAT CONFIRMÉ",
		true
	)
end

-- Réagit à une notification envoyée par le serveur (sauf "Bonus")
function Notifications.Handle(payload)
	local kind = payload.Type
	local text = payload.Text

	if kind == "Achievement" then
		-- Les succès ne se montrent qu'une fois le menu "Succès" débloqué
		if not ClientState.HasFeature("Achievements") then
			return
		end
		SoundManager.Play("Achievement", 1.1)
		Effects.Confetti(40)
		Notifications.Toast(text or "", Theme.Colors.Purple, 4.5, payload.Title or "🏆 SUCCÈS DÉBLOQUÉ !")
	elseif kind == "Quest" then
		SoundManager.Play("Bonus", 1.2)
		Effects.Flash(Theme.Colors.Orange, 0.15)
		Notifications.Toast(text or "", Theme.Colors.Orange, 4, payload.Title or "📜 QUÊTE TERMINÉE !")
	elseif kind == "Jackpot" then
		SoundManager.Play("Jackpot", 0.8)
		task.delay(0.15, SoundManager.Play, "Jackpot", 1.2)
		task.delay(0.3, SoundManager.Play, "Jackpot", 1.6)
		Effects.Flash(Color3.new(1, 1, 1), 0.9)
		Effects.Confetti(150)
		Effects.BigMessage("JACKPOT !!!\nCOIN PARFAIT", Theme.Colors.Yellow, 3.5)
		Notifications.Toast(text or "", Theme.Colors.Gold, 6, "📀 LE LOGO A TOUCHÉ LE COIN !")
	elseif kind == "Rush" then
		SoundManager.Play("Rush", 1)
		Effects.Flash(Theme.Colors.Yellow, 0.4)
		Effects.BigMessage("⚡ DOPAMINE RUSH ⚡", Theme.Colors.Yellow, 2)
		Notifications.Toast(text or "", Theme.Colors.Yellow, 5)
	elseif kind == "Unlock" then
		SoundManager.Play("Achievement", 1.3)
		centerBurst(nil)
		Notifications.Toast(text or "✨ Nouveau !", Theme.Colors.Green, 4)
	elseif kind == "Purchase" then
		celebratePurchase(payload)
	elseif kind == "Detox" then
		-- La cinématique de l'océan (et son son) est jouée par StimulusManager ; le message arrive après
		local multiplier = tonumber(payload.Multiplier) or 1
		task.delay(6.5, function()
			Notifications.Toast(
				string.format("Tes gains sont maintenant multipliés par %s pour toujours.", tostring(math.floor(multiplier * 100 + 0.5) / 100)),
				Theme.Colors.Cyan,
				6,
				"🌊 Bienvenue de retour (visite n°" .. tostring(payload.Rebirths or 1) .. ")"
			)
		end)
	elseif kind == "Error" then
		SoundManager.Play("Error", 0.7)
		Notifications.Toast(text or "Erreur", Theme.Colors.Red, 5)
	elseif kind == "Bonus" then
		-- Géré par StimulusManager (texte flottant sur le stimulus concerné)
		return
	else
		Notifications.Toast(text or "", Theme.Colors.Blue)
	end
end

return Notifications
