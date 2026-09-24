--[[
	Notifications (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Notifications

	Petits bandeaux ("toasts") blancs en bas de l'écran, avec une barre de
	couleur à gauche, + réaction aux notifications du serveur
	(Info, Error, Achievement, Quest, Rush, Jackpot, Unlock, Detox).
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
local order = 0

function Notifications.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(460, 300),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIUtil.Create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = frame,
	})
	container = frame
end

-- Affiche un bandeau temporaire
function Notifications.Toast(text: string, color: Color3?, duration: number?, title: string?)
	local target = container
	if not target or not text or text == "" then
		return
	end

	-- Supprime les plus anciens s'il y en a trop
	local existing = {}
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("Frame") then
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
	local height = title and 62 or 44
	local toast = UIUtil.Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(440, height),
		BackgroundColor3 = Theme.Colors.Card,
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = target,
	})
	UIUtil.Corner(toast, 12)
	UIUtil.Stroke(toast, Theme.Colors.CardBorder, 1.5, 0.15)

	-- Barre de couleur à gauche
	UIUtil.Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = toast,
	})

	if title then
		UIUtil.Label({
			Text = title,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -34, 0, 22),
			Position = UDim2.fromOffset(20, 6),
			MaxTextSize = 18,
			Parent = toast,
		})
	end
	UIUtil.Label({
		Text = text,
		TextColor3 = title and Theme.Colors.TextDim or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -34, 0, 26),
		Position = UDim2.fromOffset(20, title and 30 or 9),
		MaxTextSize = 18,
		Parent = toast,
	})

	-- Apparition avec rebond
	local scale = UIUtil.Create("UIScale", { Scale = 0.3, Parent = toast })
	UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(duration or 3.5, function()
		if toast.Parent then
			UIUtil.Tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

-- Petite explosion au centre (vers le bouton) pour les déblocages
local function centerBurst(color: Color3?)
	local layer = Effects.GetLayer()
	if layer then
		Effects.Burst(layer, UDim2.new(0.5, 0, 0, 140), color, 16)
	end
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
