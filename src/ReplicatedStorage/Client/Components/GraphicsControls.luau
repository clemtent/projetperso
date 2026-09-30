--[[
	GraphicsControls (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > GraphicsControls

	v9.8 (REALISM98) 🎨 lignes de réglages "Graphismes / Mode réaliste",
	même allure que la fenêtre ⚙️ Paramètres (pastille d'icône, titre,
	sous-titre, interrupteur animé ou onglets à droite ; sous le titre quand
	c'est étroit, ex. téléphone). Utilisées par Panels/Settings (section
	"Graphismes") et par World/TownGraphics (fenêtre ouverte en ville).
	  - ✨ Mode réaliste (ON / OFF ; "Auto" = selon l'appareil) : c'est un
	    préréglage, il remet les réglages détaillés sur "Auto" ;
	  - 🪞 Reflets : Off / Miroirs / Tout ;
	  - 🌦️ Météo : On / Off (+ le temps qu'il fait en ville maintenant) ;
	  - 🌧️ Pluie : Faible / Moyenne / Forte ;
	  - 🌗 Ombres : Basses / Hautes ;
	  - 🌟 Effets (halo, rayons de soleil, flou lointain) : On / Off ;
	  - 🏙️ Détail (distance d'affichage du décor de la ville) : Bas / Moyen / Élevé ;
	  - (v9.9 REALISM99) 🕐 Heure du jour : Auto (l'heure de la ville) / Jour /
	    Coucher de soleil / Nuit : pour ce joueur seulement (Lighting local,
	    TownAtmosphere), gardée quand on bascule le Mode réaliste ;
	  - ↺ "Tout en automatique".
	Chaque choix s'applique TOUT DE SUITE (GraphicsQuality.SetLocal) puis
	est sauvegardé côté serveur (SetSetting, 3 essais ; sinon retour en
	arrière + message).

	API :
	  GraphicsControls.Build(parent, opts) -> { Refresh: () -> (), Destroy: () -> () }
	    parent : cadre avec un UIListLayout (les lignes y sont ajoutées)
	    opts = { Order: number?, Accent: Color3?, Toast: ((text, color) -> ())? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)
local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)

local GraphicsControls = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ROW_HOVER = Theme.Colors.Surface or Theme.Colors.PanelLight
local ROW_BORDER = Theme.Colors.Divider or Theme.Colors.Disabled
local ON_COLOR = Theme.Colors.Green
local OFF_COLOR = Theme.Colors.Disabled
local NARROW = 500 -- (px) en dessous : contrôle sous le titre

local WEATHER_ICON = { Clear = "☀️", Cloudy = "☁️", Showers = "🌦️", Rain = "🌧️", Storm = "⛈️" }
local WEATHER_TEXT = { Clear = "Clear", Cloudy = "Cloudy", Showers = "Showers", Rain = "Rain", Storm = "Storm" }

type ToggleUI = { Button: TextButton, Knob: Frame, Stroke: UIStroke, OnIcon: Frame, OffIcon: Frame }
type Row = { Frame: Frame, Title: TextLabel, Subtitle: TextLabel, Control: GuiObject, Tall: number, Dim: Frame? }

local function paintToggle(ui: ToggleUI, value: boolean, animate: boolean)
	local duration = animate and 0.22 or 0
	UIUtil.Tween(ui.Knob, duration, {
		Position = value and UDim2.new(1, -3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		AnchorPoint = value and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
	}, Enum.EasingStyle.Back)
	UIUtil.Tween(ui.Button, duration, { BackgroundColor3 = value and ON_COLOR or OFF_COLOR })
	UIUtil.Tween(ui.Stroke, duration, { Color = (value and ON_COLOR or OFF_COLOR):Lerp(BLACK, 0.25) })
	ui.OnIcon.Visible = value
	ui.OffIcon.Visible = not value
	UIUtil.SetIconColor(value and ui.OnIcon or ui.OffIcon, (value and ON_COLOR or OFF_COLOR):Lerp(BLACK, 0.2))
end

-- Interrupteur ON / OFF (même dessin que les Paramètres)
local function buildToggle(parent: Instance, onActivated: () -> ()): ToggleUI
	local button = UIUtil.Create("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(60, 32),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 14),
		BackgroundColor3 = ON_COLOR,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	local stroke = UIUtil.Stroke(button, ON_COLOR:Lerp(BLACK, 0.25), 1.5, 0.2)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 215)),
		Parent = button,
	})
	local knob = UIUtil.Create("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -3, 0.5, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = button,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	UIUtil.Stroke(knob, BLACK, 1, 0.8)
	local onIcon = UIUtil.Icon("Check", { Name = "OnIcon", Size = 13, Thickness = 3, Color = ON_COLOR, ZIndex = 3, Parent = knob })
	local offIcon = UIUtil.Icon("Cross", { Name = "OffIcon", Size = 10, Thickness = 3, Color = OFF_COLOR, ZIndex = 3, Parent = knob })
	UIUtil.AnimateButton(button, 1.06, 0.93)
	button.Activated:Connect(onActivated)
	local hitbox = UIUtil.Create("TextButton", {
		Name = "Hitbox",
		Size = UDim2.new(1, 20, 1, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 4,
		Parent = button,
	})
	hitbox.Activated:Connect(onActivated)
	return { Button = button, Knob = knob, Stroke = stroke, OnIcon = onIcon, OffIcon = offIcon }
end

-- Ligne : pastille d'icône, titre, sous-titre (fond au survol)
local function buildRow(parent: Instance, name: string, order: number, icon: string, title: string, accent: Color3): Row
	local row = UIUtil.Create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = ROW_HOVER,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Corner(row, Theme.Radius.M)
	row.MouseEnter:Connect(function()
		UIUtil.Tween(row, 0.15, { BackgroundTransparency = 0 })
	end)
	row.MouseLeave:Connect(function()
		UIUtil.Tween(row, 0.2, { BackgroundTransparency = 1 })
	end)
	local bubble = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(8, 12),
		BackgroundColor3 = accent:Lerp(WHITE, 0.85),
		Parent = row,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, accent, 1, 0.6)
	UIUtil.Label({
		Text = icon,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 20,
		Parent = bubble,
	})
	local titleLabel = UIUtil.Label({
		Name = "Title",
		Text = title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.fromOffset(56, 10),
		MaxTextSize = 17,
		Parent = row,
	})
	local subtitle = UIUtil.Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -150, 0, 17),
		Position = UDim2.fromOffset(56, 31),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	return { Frame = row, Title = titleLabel, Subtitle = subtitle, Control = row, Tall = 60, Dim = nil }
end

local function divider(parent: Instance, order: number)
	UIUtil.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = ROW_BORDER,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Onglets à droite (large) ou sous le titre (étroit)
local function layoutTabs(row: Row, width: number)
	local tabsFrame = row.Control
	local wide = width >= NARROW
	if wide then
		row.Frame.Size = UDim2.new(1, 0, 0, 60)
		tabsFrame.AnchorPoint = Vector2.new(1, 0)
		tabsFrame.Size = UDim2.fromOffset(math.min(300, math.floor(width * 0.46)), Theme.TouchTarget - 4)
		tabsFrame.Position = UDim2.new(1, -10, 0, 10)
		local titleW = -(math.min(300, math.floor(width * 0.46)) + 76)
		row.Title.Size = UDim2.new(1, titleW, 0, 20)
		row.Subtitle.Size = UDim2.new(1, titleW, 0, 17)
	else
		row.Frame.Size = UDim2.new(1, 0, 0, 106)
		tabsFrame.AnchorPoint = Vector2.new(0, 0)
		tabsFrame.Size = UDim2.new(1, -20, 0, Theme.TouchTarget - 4)
		tabsFrame.Position = UDim2.fromOffset(10, 58)
		row.Title.Size = UDim2.new(1, -66, 0, 20)
		row.Subtitle.Size = UDim2.new(1, -66, 0, 17)
	end
end

-- Envoie un réglage au serveur (3 essais) ; échec -> valeur d'avant + message
local saveTokens: { [string]: number } = {}
local function save(key: string, value: string, previous: string, toast: ((string, Color3?) -> ())?)
	saveTokens[key] = (saveTokens[key] or 0) + 1
	local token = saveTokens[key]
	GraphicsQuality.SetLocal(key, value)
	task.spawn(function()
		for attempt = 1, 3 do
			if saveTokens[key] ~= token then
				return -- un choix plus récent a pris le relais
			end
			local ok, success = pcall(function()
				return Net.Function("SetSetting"):InvokeServer(key, value)
			end)
			if ok and success == true then
				return
			end
			if attempt < 3 then
				task.wait(0.3)
			end
		end
		if saveTokens[key] == token then
			GraphicsQuality.SetLocal(key, previous)
			if toast then
				toast(Locale.T("Couldn't save the graphics setting, try again."), Theme.Colors.Red)
			end
		end
	end)
end

function GraphicsControls.Build(parent: Instance, opts: { [string]: any }?): { Refresh: () -> (), Destroy: () -> () }
	local o = opts or {}
	local base = tonumber(o.Order) or 1
	local accent: Color3 = o.Accent or Theme.Colors.Cyan
	local toast = o.Toast
	local connections: { any } = {}
	local tabRows: { { Row: Row, Tabs: UIUtil.Tabs, Key: string } } = {}
	local toggles: { [string]: ToggleUI } = {}
	local rows: { [string]: Row } = {}

	local function setKey(key: string, value: string)
		local previous = GraphicsQuality.GetSaved(key)
		if previous == value then
			return
		end
		save(key, value, previous, toast)
	end

	-- ✨ Mode réaliste (préréglage : les réglages détaillés repassent en "Auto")
	local realRow = buildRow(parent, "GfxRealisticRow", base, "✨", Locale.T("Realistic mode"), accent)
	rows.GfxRealistic = realRow
	local autoChip = UIUtil.Chip({
		Name = "AutoChip",
		Text = Locale.T("Auto"),
		Color = accent,
		TextColor3 = Theme.Colors.TextLight,
		Height = 20,
		TextSize = 12,
		Parent = realRow.Frame,
	})
	autoChip.AnchorPoint = Vector2.new(1, 0)
	autoChip.Position = UDim2.new(1, -84, 0, 20)
	toggles.GfxRealistic = buildToggle(realRow.Frame, function()
		local on = not GraphicsQuality.Get().Realistic
		setKey("GfxRealistic", on and "On" or "Off")
		for _, key in ipairs(GraphicsQuality.ORDER) do
			if key ~= "GfxRealistic" and not GraphicsQuality.NOT_PRESET[key] then
				setKey(key, "Auto")
			end
		end
	end)
	divider(parent, base + 1)

	local function tabsRow(key: string, name: string, order: number, icon: string, title: string, subtitle: string, choices: { { Id: string, Text: string } })
		local row = buildRow(parent, name, order, icon, title, accent)
		row.Subtitle.Text = subtitle
		local tabs = UIUtil.Tabs({
			Name = "Choice",
			Parent = row.Frame,
			Tabs = choices,
			Color = accent,
			Size = UDim2.fromOffset(260, Theme.TouchTarget - 4),
			TextSize = 15,
			Selected = choices[1].Id,
			OnSelect = function(id: string)
				setKey(key, id)
			end,
		})
		row.Control = tabs.Frame
		rows[key] = row
		table.insert(tabRows, { Row = row, Tabs = tabs, Key = key })
	end

	-- (v9.9) 🕐 heure du jour (juste après le Mode réaliste : bien visible)
	tabsRow("GfxTime", "GfxTimeRow", base + 2, "🕐", Locale.T("Time of day"), Locale.T("Just for you · Auto = the town"), {
		{ Id = "Auto", Text = Locale.T("Auto") },
		{ Id = "Day", Text = Locale.T("Day") },
		{ Id = "Sunset", Text = Locale.T("Dusk") },
		{ Id = "Night", Text = Locale.T("Night") },
	})

	tabsRow("GfxReflections", "GfxReflectionsRow", base + 3, "🪞", Locale.T("Reflections"), Locale.T("Real mirrors, glossy screens and floors"), {
		{ Id = "Off", Text = Locale.T("None") },
		{ Id = "Mirrors", Text = Locale.T("Mirrors") },
		{ Id = "All", Text = Locale.T("All") },
	})

	-- 🌦️ Météo + temps actuel en ville
	local weatherRow = buildRow(parent, "GfxWeatherRow", base + 4, "🌦️", Locale.T("Weather in town"), accent)
	rows.GfxWeather = weatherRow
	toggles.GfxWeather = buildToggle(weatherRow.Frame, function()
		setKey("GfxWeather", GraphicsQuality.Get().Weather and "Off" or "On")
	end)

	tabsRow("GfxRain", "GfxRainRow", base + 5, "🌧️", Locale.T("Rain"), Locale.T("How heavy the rain looks"), {
		{ Id = "Low", Text = Locale.T("Light") },
		{ Id = "Medium", Text = Locale.T("Moderate") },
		{ Id = "High", Text = Locale.T("Heavy") },
	})
	tabsRow("GfxShadows", "GfxShadowsRow", base + 6, "🌗", Locale.T("Shadows"), Locale.T("Simple = smoother on small devices"), {
		{ Id = "Low", Text = Locale.T("Simple") },
		{ Id = "High", Text = Locale.T("Detailed") },
	})

	local fxRow = buildRow(parent, "GfxEffectsRow", base + 7, "🌟", Locale.T("Light effects"), accent)
	fxRow.Subtitle.Text = Locale.T("Soft glow, sun rays, distant blur")
	rows.GfxEffects = fxRow
	toggles.GfxEffects = buildToggle(fxRow.Frame, function()
		setKey("GfxEffects", GraphicsQuality.Get().Effects and "Off" or "On")
	end)

	tabsRow("GfxDetail", "GfxDetailRow", base + 8, "🏙️", Locale.T("Detail"), Locale.T("How far the town decor is shown"), {
		{ Id = "Low", Text = Locale.T("Low") },
		{ Id = "Medium", Text = Locale.T("Medium") },
		{ Id = "High", Text = Locale.T("High") },
	})

	-- ↺ tout en automatique
	local footer = UIUtil.Create("Frame", {
		Name = "GfxFooter",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = base + 9,
		Parent = parent,
	})
	local reset = UIUtil.PillButton({
		Name = "GfxAuto",
		Text = Locale.T("↺ All automatic"),
		Color = WHITE,
		TextColor3 = Theme.Colors.Text,
		Height = 36,
		TextSize = 15,
		Parent = footer,
	})
	reset.AnchorPoint = Vector2.new(1, 0.5)
	reset.Position = UDim2.new(1, -8, 0.5, 0)
	reset.Activated:Connect(function()
		for _, key in ipairs(GraphicsQuality.ORDER) do
			setKey(key, "Auto")
		end
	end)
	local hint = UIUtil.Create("TextLabel", {
		Name = "Hint",
		Size = UDim2.new(1, -200, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("Applied right away in Dopamine Town"),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})

	-- Temps qu'il fait en ville maintenant (même calcul que Weather3D)
	local function weatherNow(): string
		local world = Client:FindFirstChild("World")
		local module = world and world:FindFirstChild("Weather3D")
		if not module then
			return ""
		end
		local ok, text = pcall(function()
			local Weather3D = require(module) :: any
			local s = Weather3D.At(workspace:GetServerTimeNow())
			local kind = s.Kind
			if kind ~= "Clear" and s.Rain < 0.05 and s.Cloud < 0.6 then
				kind = s.Rainbow > 0.05 and "Clear" or "Cloudy"
			end
			return Locale.T("Now in town: %s", WEATHER_ICON[kind] .. " " .. Locale.T(WEATHER_TEXT[kind]))
		end)
		return ok and text or ""
	end

	local function refresh(animate: boolean)
		local q = GraphicsQuality.Get()
		local mode = GraphicsQuality.GetSaved("GfxRealistic")
		paintToggle(toggles.GfxRealistic, q.Realistic, animate)
		autoChip.Visible = mode == "Auto"
		realRow.Subtitle.Text = q.Realistic and Locale.T("Live mirrors, puddles, glossy floors") or Locale.T("Lighter look, smoother on small devices")
		paintToggle(toggles.GfxWeather, q.Weather, animate)
		local now = weatherNow()
		weatherRow.Subtitle.Text = q.Weather and (now ~= "" and now or Locale.T("Rain, storms and rainbows (same for everyone)"))
			or Locale.T("Always sunny")
		paintToggle(toggles.GfxEffects, q.Effects, animate)
		local values = { GfxReflections = q.Reflections, GfxRain = q.Rain, GfxShadows = q.Shadows, GfxDetail = q.Detail, GfxTime = q.TimeOfDay }
		for _, entry in ipairs(tabRows) do
			local value = values[entry.Key]
			if value and entry.Tabs.GetSelected() ~= value then
				entry.Tabs.Select(value, true)
			end
		end
		-- pluie grisée quand la météo est coupée
		local rainRow = rows.GfxRain
		if rainRow then
			rainRow.Frame.BackgroundTransparency = 1
			rainRow.Title.TextTransparency = q.Weather and 0 or 0.5
			rainRow.Subtitle.TextTransparency = q.Weather and 0 or 0.5
		end
		local anyManual = false
		for _, key in ipairs(GraphicsQuality.ORDER) do
			if GraphicsQuality.GetSaved(key) ~= "Auto" then
				anyManual = true
			end
		end
		reset.Visible = anyManual
		hint.Size = anyManual and UDim2.new(1, -200, 1, 0) or UDim2.new(1, -20, 1, 0)
	end

	-- Mise en page selon la largeur disponible
	local lastWidth = -1
	local function layout()
		local width = 0
		if parent:IsA("GuiObject") then
			width = (parent :: GuiObject).AbsoluteSize.X
		end
		if width <= 0 or width == lastWidth then
			return
		end
		lastWidth = width
		for _, entry in ipairs(tabRows) do
			layoutTabs(entry.Row, width)
		end
	end
	if parent:IsA("GuiObject") then
		table.insert(connections, (parent :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	end
	layout()
	task.defer(layout)

	table.insert(connections, GraphicsQuality.Changed:Connect(function()
		refresh(true)
	end))
	refresh(false)

	return {
		Refresh = function()
			refresh(false)
			layout()
		end,
		Destroy = function()
			UIUtil.DisconnectAll(connections)
		end,
	}
end

return GraphicsControls
