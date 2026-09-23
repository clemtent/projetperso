--[[
	Notifications (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Notifications

	Petits bandeaux ("toasts") en bas de l'écran + réaction aux
	notifications du serveur (succès, quêtes, bonus, jackpot, rush...).
]]

local Debris = game:GetService("Debris")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)

local Notifications = {}

-- Fonctions appelées pour les bonus selon leur source ("DVD", "Golden"...)
Notifications.BonusHandlers = {} :: { [string]: (amount: number) -> () }

local container: Frame? = nil
local MAX_TOASTS = 4
local order = 0

function Notifications.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(520, 260),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -125, 1, -12),
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
	if not target then
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
	local accent = color or Theme.Colors.Cyan
	local height = title and 62 or 42
	local toast = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(500, height),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Parent = target,
	})
	UIUtil.Corner(toast, 14)
	UIUtil.Stroke(toast, accent, 2)

	if title then
		UIUtil.Label({
			Text = title,
			Font = Theme.Fonts.Title,
			TextColor3 = accent,
			Size = UDim2.new(1, -20, 0, 22),
			Position = UDim2.fromOffset(10, 5),
			MaxTextSize = 18,
			Parent = toast,
		})
	end
	UIUtil.Label({
		Text = text,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, title and 29 or 7),
		MaxTextSize = 18,
		Parent = toast,
	})

	-- Apparition avec rebond
	local scale = UIUtil.Create("UIScale", { Scale = 0.3, Parent = toast })
	UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(duration or 3.5, function()
		if toast.Parent then
			UIUtil.Tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Debris:AddItem(toast, 0.3)
		end
	end)
end

-- Réagit à une notification envoyée par le serveur
function Notifications.Handle(payload)
	local kind = payload.Type

	if kind == "Achievement" then
		SoundManager.Play("Achievement", 1.1)
		Effects.Confetti(50)
		Effects.Flash(Theme.Colors.Yellow, 0.3)
		Notifications.Toast(payload.Text, Theme.Colors.Yellow, 4.5, payload.Title)
	elseif kind == "Quest" then
		SoundManager.Play("Bonus", 1.2)
		Effects.Flash(Theme.Colors.Green, 0.2)
		Notifications.Toast(payload.Text, Theme.Colors.Green, 4, payload.Title)
	elseif kind == "Bonus" then
		SoundManager.Play("Bonus", 1.3)
		local handler = payload.Source and Notifications.BonusHandlers[payload.Source]
		if handler and payload.Amount then
			handler(payload.Amount)
		end
		if payload.Text then
			Notifications.Toast(payload.Text, Theme.Colors.Gold)
		end
	elseif kind == "Jackpot" then
		SoundManager.Play("Jackpot", 0.8)
		task.delay(0.15, SoundManager.Play, "Jackpot", 1.2)
		task.delay(0.3, SoundManager.Play, "Jackpot", 1.6)
		Effects.Flash(Color3.new(1, 1, 1), 0.9)
		Effects.Confetti(150)
		Effects.BigMessage("JACKPOT !!!\nCOIN PARFAIT", Theme.Colors.Yellow, 3.5)
		Notifications.Toast(payload.Text, Theme.Colors.Yellow, 6, "📀 LE LOGO A TOUCHÉ LE COIN !")
	elseif kind == "Rush" then
		SoundManager.Play("Rush", 1)
		Effects.Flash(Theme.Colors.Yellow, 0.5)
		Effects.BigMessage("⚡ DOPAMINE RUSH ⚡", Theme.Colors.Yellow, 2)
		Notifications.Toast(payload.Text, Theme.Colors.Yellow, 5)
	elseif kind == "Error" then
		SoundManager.Play("Error", 0.7)
		Notifications.Toast(payload.Text, Theme.Colors.Red, 5)
	else
		Notifications.Toast(payload.Text or "", Theme.Colors.Cyan)
	end
end

return Notifications
