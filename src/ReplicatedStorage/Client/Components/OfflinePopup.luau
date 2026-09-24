--[[
	OfflinePopup (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > OfflinePopup

	Fenêtre "Bon retour !" affichée quand le serveur envoie
	Notify { Type = "Offline", Amount, Seconds, Rate, MaxSeconds } :
	  - petite scène de nuit animée (lune, étoiles, "Zzz") ;
	  - durée de l'absence, gain (compteur qui défile), taux et durée max ;
	  - jauge "temps comptabilisé" (plafond atteint ou non) ;
	  - astuce "Améliore Mode veille 😴" (si ce n'est pas déjà au maximum) ;
	  - gros bouton "Récupérer" (le gain est DÉJÀ donné par le serveur : le
	    bouton ferme juste la fenêtre, avec des confettis).
	Attend que l'écran de chargement ait disparu avant de s'ouvrir.
	La fenêtre vit dans le calque Toasts (au-dessus des panneaux, sous les
	effets pour que les confettis passent devant).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Interface = require(Client.Interface)
local LoadingScreen = require(script.Parent.LoadingScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Signal)

local OfflinePopup = {}

OfflinePopup.Closed = Signal.new() -- () : la fenêtre vient de se fermer

local CARD_SIZE = Vector2.new(470, 470)
local SKY_HEIGHT = 150
local NIGHT_TOP = Color3.fromRGB(38, 40, 92)
local NIGHT_BOTTOM = Color3.fromRGB(112, 82, 170)
local MOON = Color3.fromRGB(255, 236, 170)

local layer: Frame? = nil
local current: Frame? = nil -- fenêtre affichée
local renderConnection: RBXScriptConnection? = nil
local showToken = 0

-- Amélioration "Mode veille" (Effect = "Offline")
local function sleepUpgrade()
	for _, upgrade in ipairs(Config.Upgrades) do
		if upgrade.Effect == "Offline" then
			return upgrade
		end
	end
	return nil
end

local function stopAnimation()
	local connection = renderConnection
	if connection then
		connection:Disconnect()
		renderConnection = nil
	end
end

function OfflinePopup.Build(parent: Frame)
	layer = parent
end

function OfflinePopup.IsVisible(): boolean
	return current ~= nil
end

-- Ferme la fenêtre (avec ou sans fête)
local function close(celebrate: boolean)
	local window = current
	if not window then
		return
	end
	current = nil
	stopAnimation()
	local card = window:FindFirstChild("Card") :: Frame?
	local dimmer = window:FindFirstChild("Dimmer") :: GuiObject?
	if celebrate then
		SoundManager.Play("Jackpot", 1)
		task.delay(0.1, SoundManager.Play, "Cash", 1.2)
		Effects.Confetti(110)
		local effects = Effects.GetLayer()
		if effects and card then
			local center = Interface.GetCanvasCenter(card)
			Effects.Burst(effects, UDim2.fromOffset(center.X, center.Y + 150), Theme.Colors.Gold, 20)
		end
	else
		SoundManager.Play("Open", 0.9)
	end
	if dimmer then
		UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = 1 })
	end
	if card then
		local scale = card:FindFirstChildOfClass("UIScale")
		if scale then
			UIUtil.Tween(scale, 0.25, { Scale = 0.85 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		local group = card:FindFirstChild("Fade") :: CanvasGroup?
		if group then
			UIUtil.Tween(group, 0.25, { GroupTransparency = 1 })
		end
	end
	task.delay(0.3, function()
		window:Destroy()
	end)
	OfflinePopup.Closed:Fire()
end

-- Petite étiquette arrondie "icône + texte" (taux, durée max, niveau)
local function infoChip(parent: Instance, icon: string, title: string, value: string, color: Color3, order: number)
	local chip = UIUtil.Create("Frame", {
		Name = "Info" .. order,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.88),
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Corner(chip, Theme.Radius.M)
	UIUtil.Stroke(chip, color, 1.5, 0.55)
	UIUtil.Label({
		Text = icon .. " " .. title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 7),
		MaxTextSize = 13,
		Parent = chip,
	})
	UIUtil.Label({
		Text = value,
		Font = Theme.Fonts.Number,
		TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35),
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 24),
		MaxTextSize = 20,
		Parent = chip,
	})
end

-- Scène de nuit : dégradé, lune en croissant, étoiles qui scintillent, "Zzz"
local function buildSky(card: Frame): { twinkle: { TextLabel }, zzz: { TextLabel }, moon: Frame }
	local sky = UIUtil.Create("Frame", {
		Name = "Sky",
		Size = UDim2.new(1, 0, 0, SKY_HEIGHT),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(sky, 26)
	UIUtil.Gradient(sky, ColorSequence.new(NIGHT_TOP, NIGHT_BOTTOM), 90)
	-- Bas du ciel à angles droits (seuls les coins du haut sont arrondis)
	UIUtil.Create("Frame", {
		Name = "Filler",
		Size = UDim2.new(1, 0, 0, 30),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = NIGHT_BOTTOM,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = sky,
	})

	-- Collines douces en bas de la scène
	for index, info in ipairs({
		{ X = 0.15, W = 300, Color = Color3.fromRGB(80, 60, 140) },
		{ X = 0.8, W = 340, Color = Color3.fromRGB(70, 52, 128) },
	}) do
		local hill = UIUtil.Create("Frame", {
			Name = "Hill" .. index,
			Size = UDim2.fromOffset(info.W, 120),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(info.X, 0, 1, -34 - index * 4),
			BackgroundColor3 = info.Color,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = sky,
		})
		UIUtil.Corner(hill, UDim.new(0.5, 0))
	end

	-- Lune (croissant : un disque clair "mordu" par un disque couleur ciel)
	local moon = UIUtil.Create("Frame", {
		Name = "Moon",
		Size = UDim2.fromOffset(70, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 66),
		BackgroundColor3 = MOON,
		ZIndex = 4,
		Parent = sky,
	})
	UIUtil.Corner(moon, UDim.new(1, 0))
	UIUtil.Gradient(moon, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(230, 220, 200)), 45)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		Size = UDim2.fromOffset(130, 130),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = MOON,
		BackgroundTransparency = 0.82,
		ZIndex = 3,
		Parent = moon,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))
	local bite = UIUtil.Create("Frame", {
		Name = "Bite",
		Size = UDim2.fromOffset(58, 58),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 20, 0.5, -12),
		BackgroundColor3 = NIGHT_TOP:Lerp(NIGHT_BOTTOM, 0.35),
		ZIndex = 5,
		Parent = moon,
	})
	UIUtil.Corner(bite, UDim.new(1, 0))
	-- Petits cratères
	for _, crater in ipairs({ { 0.3, 0.35, 9 }, { 0.22, 0.62, 6 }, { 0.42, 0.78, 7 } }) do
		local dot = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(crater[3], crater[3]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(crater[1], crater[2]),
			BackgroundColor3 = Color3.fromRGB(230, 205, 140),
			BackgroundTransparency = 0.25,
			ZIndex = 5,
			Parent = moon,
		})
		UIUtil.Corner(dot, UDim.new(1, 0))
	end

	-- Étoiles
	local random = Random.new(7)
	local twinkle = {}
	for index = 1, 14 do
		local star = UIUtil.Label({
			Name = "Star" .. index,
			Text = index % 4 == 0 and "✦" or "•",
			TextColor3 = Color3.fromRGB(255, 250, 220),
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0.04, 0.96), 0, 0, random:NextInteger(10, 100)),
			MaxTextSize = index % 4 == 0 and 16 or 12,
			ZIndex = 3,
			Parent = sky,
		})
		star:SetAttribute("Phase", random:NextNumber(0, math.pi * 2))
		table.insert(twinkle, star)
	end

	-- "Zzz" qui s'envolent de la lune
	local zzz = {}
	for index = 1, 3 do
		local label = UIUtil.Label({
			Name = "Z" .. index,
			Text = "z",
			Font = Theme.Fonts.Title,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(24, 24),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 44, 0, 50),
			MaxTextSize = 22,
			ZIndex = 6,
			Parent = sky,
		})
		label:SetAttribute("Phase", (index - 1) / 3)
		table.insert(zzz, label)
	end
	return { twinkle = twinkle, zzz = zzz, moon = moon }
end

-- Construit et affiche la fenêtre
local function build(payload)
	local parent = layer
	if not parent then
		return
	end
	-- Une seule fenêtre : la nouvelle remplace l'ancienne
	if current then
		local old = current
		current = nil
		stopAnimation()
		old:Destroy()
	end

	local amount = math.max(0, tonumber(payload.Amount) or 0)
	local seconds = math.max(0, tonumber(payload.Seconds) or 0)
	local offlineState = ClientState.Data and ClientState.Data.Offline
	local rate = tonumber(payload.Rate) or (type(offlineState) == "table" and tonumber(offlineState.Rate)) or Config.Offline.BaseRate
	local maxSeconds = tonumber(payload.MaxSeconds)
		or (type(offlineState) == "table" and tonumber(offlineState.MaxSeconds))
		or Config.Offline.BaseMaxHours * 3600
	maxSeconds = math.max(1, maxSeconds)
	local counted = math.min(seconds, maxSeconds)
	local capped = seconds > maxSeconds

	local window = UIUtil.Create("Frame", {
		Name = "OfflinePopup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = parent,
	})
	current = window

	-- Fond assombri (un clic dehors = Récupérer aussi)
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = window,
	})
	UIUtil.Tween(dimmer, 0.3, { BackgroundTransparency = 0.4 })

	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = window,
	})
	local cardScale = UIUtil.Create("UIScale", { Scale = 0.7, Parent = card })
	UIUtil.Tween(cardScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Tout le contenu dans un CanvasGroup (fondu d'ensemble à la fermeture)
	local fade = UIUtil.Create("CanvasGroup", {
		Name = "Fade",
		Size = UDim2.new(1, 24, 1, 24),
		Position = UDim2.fromOffset(-12, -12),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	local body = UIUtil.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 10),
		BackgroundColor3 = Theme.Colors.Panel,
		Active = true,
		ZIndex = 2,
		Parent = fade,
	})
	UIUtil.Corner(body, 26)
	UIUtil.Stroke(body, Theme.Colors.CardBorder, 1.5, 0.3)
	UIUtil.Shadow(body, 6, 0.8, 3)

	local sky = buildSky(body)

	-- Titre et durée
	UIUtil.Label({
		Name = "Title",
		Text = "Bon retour !",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.fromOffset(20, SKY_HEIGHT + 12),
		MaxTextSize = 30,
		ZIndex = 3,
		Parent = body,
	})
	UIUtil.Label({
		Name = "Away",
		Text = "Tu étais absent(e) pendant " .. NumberFormatter.Time(seconds),
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -40, 0, 20),
		Position = UDim2.fromOffset(20, SKY_HEIGHT + 46),
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = body,
	})

	-- Gain (compteur qui défile)
	local amountRow = UIUtil.Create("Frame", {
		Name = "AmountRow",
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, SKY_HEIGHT + 70),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = body,
	})
	local amountLabel = UIUtil.Label({
		Name = "Amount",
		Text = "+0",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 44),
		MaxTextSize = 44,
		ZIndex = 4,
		Parent = amountRow,
	})
	UIUtil.Gradient(amountLabel, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 120, 20)),
	}), 90)
	local amountStroke = UIUtil.Stroke(amountLabel, Color3.fromRGB(120, 60, 0), 1.5, 0.55)
	amountStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	UIUtil.Label({
		Name = "Unit",
		Text = Config.Game.CurrencyName .. " gagnée pendant ton absence 💧",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -40, 0, 18),
		Position = UDim2.fromOffset(20, SKY_HEIGHT + 118),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = body,
	})

	-- Taux / durée max / niveau du Mode veille
	local upgrade = sleepUpgrade()
	local level = upgrade and ClientState.GetLevel(upgrade.Id) or 0
	local maxLevel = upgrade and upgrade.MaxLevel or nil
	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, SKY_HEIGHT + 144),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = body,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	infoChip(chips, "⚡", "Taux", tostring(math.floor(rate * 100 + 0.5)) .. " %", Theme.Colors.Orange, 1)
	infoChip(chips, "⏳", "Durée max", NumberFormatter.Time(maxSeconds), Theme.Colors.Blue, 2)
	infoChip(chips, upgrade and upgrade.Icon or "😴", "Mode veille", "Niv. " .. tostring(level), Theme.Colors.Purple, 3)

	-- Jauge : temps comptabilisé / durée max
	local gaugeY = SKY_HEIGHT + 204
	UIUtil.Label({
		Name = "GaugeText",
		Text = (capped and "⚠️ Plafond atteint : " or "Temps comptabilisé : ")
			.. NumberFormatter.Time(counted)
			.. " / "
			.. NumberFormatter.Time(maxSeconds),
		TextColor3 = capped and Theme.Colors.Red or Theme.Colors.TextDim,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -40, 0, 16),
		Position = UDim2.fromOffset(20, gaugeY),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = body,
	})
	local gauge = UIUtil.Create("Frame", {
		Name = "Gauge",
		Size = UDim2.new(1, -40, 0, 10),
		Position = UDim2.fromOffset(20, gaugeY + 20),
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = 3,
		Parent = body,
	})
	UIUtil.Corner(gauge, UDim.new(1, 0))
	UIUtil.Stroke(gauge, Theme.Colors.Divider, 1)
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = gauge,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(Theme.Colors.Purple, capped and Theme.Colors.Red or Theme.Colors.Cyan), 0)
	UIUtil.Tween(fill, 1.2, { Size = UDim2.fromScale(math.clamp(counted / maxSeconds, 0.02, 1), 1) }, Enum.EasingStyle.Quint)

	-- Astuce (cachée si Mode veille est au max)
	local canUpgrade = upgrade ~= nil and (maxLevel == nil or level < maxLevel)
	if canUpgrade then
		UIUtil.Label({
			Name = "Hint",
			Text = "💡 Améliore Mode veille 😴 pour gagner plus quand tu n'es pas là",
			TextColor3 = Theme.Colors.Purple,
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -40, 0, 16),
			Position = UDim2.fromOffset(20, gaugeY + 38),
			MaxTextSize = 14,
			ZIndex = 3,
			Parent = body,
		})
	end

	-- Bouton "Récupérer"
	local button = UIUtil.NeonButton({
		Name = "Collect",
		Text = "Récupérer",
		Color = Theme.Colors.Green,
		TextColor3 = Theme.Colors.TextDark,
		Size = UDim2.new(1, -80, 0, 52),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		CornerRadius = 26,
		MaxTextSize = 24,
		ZIndex = 4,
		Parent = body,
	})
	local shine = UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.new(0, 36, 1, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.2, 0, 0.5, 0),
		Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = button,
	})
	button.ClipsDescendants = true

	local collected = false
	local function collect()
		if collected or current ~= window then
			return
		end
		collected = true
		close(true)
	end
	button.Activated:Connect(collect)
	dimmer.Activated:Connect(collect)

	SoundManager.Play("Achievement", 0.9)

	-- Animations : compteur, étoiles, "Zzz", lune, reflet du bouton
	local started = os.clock()
	local lastShown = ""
	stopAnimation()
	renderConnection = RunService.RenderStepped:Connect(function()
		if not window.Parent then
			stopAnimation()
			return
		end
		local t = os.clock() - started
		-- Compteur (ease-out sur 1,3 s)
		local progress = math.clamp(t / 1.3, 0, 1)
		local eased = 1 - (1 - progress) ^ 3
		local text = "+" .. NumberFormatter.Format(amount * eased)
		if text ~= lastShown then
			lastShown = text
			amountLabel.Text = text
		end
		for _, star in ipairs(sky.twinkle) do
			local phase = star:GetAttribute("Phase") or 0
			star.TextTransparency = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(t * 2.2 + phase))
		end
		for _, label in ipairs(sky.zzz) do
			local phase = ((label:GetAttribute("Phase") or 0) + t * 0.35) % 1
			label.Position = UDim2.new(0.5, 44 + phase * 46, 0, 48 - phase * 44)
			label.TextTransparency = phase < 0.15 and (1 - phase / 0.15) or math.clamp((phase - 0.6) / 0.4, 0, 1)
			label.Rotation = math.sin(phase * math.pi * 2) * 12
		end
		sky.moon.Position = UDim2.new(0.5, 0, 0, 66 + math.sin(t * 1.3) * 4)
		-- Reflet qui traverse le bouton toutes les 2,5 s
		local sweep = (t % 2.5) / 0.9
		shine.Position = UDim2.new(-0.2 + math.clamp(sweep, 0, 1) * 1.4, 0, 0.5, 0)
	end)
end

-- Affiche la fenêtre pour une notification "Offline" (après l'écran de chargement)
function OfflinePopup.Show(payload)
	if type(payload) ~= "table" or (tonumber(payload.Amount) or 0) <= 0 then
		return
	end
	showToken += 1
	local token = showToken
	task.spawn(function()
		local waited = 0
		while LoadingScreen.IsVisible() and waited < 20 do
			waited += task.wait(0.2)
		end
		-- (laisse l'écran de chargement finir son fondu)
		if waited > 0 then
			task.wait(0.5)
		end
		if token ~= showToken then
			return -- une notification plus récente a pris le relais
		end
		build(payload)
	end)
end

return OfflinePopup
