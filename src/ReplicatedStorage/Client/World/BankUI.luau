--[[
	BankUI (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > BankUI

	🏦 Interface de la Banque Dopamine (v11, BANK11) : ScreenGui "BankGui"
	(gardée visible en ville : KEEP_GUIS), pilotée par BankClient.
	  - PASTILLE 💎 en haut à gauche (sous la boussole) : solde de diamants,
	    un appui ouvre la banque ;
	  - FENÊTRE "Banque Dopamine" (bleu nuit et or) :
	      colonne des SOLDES : 🧠 Dopamine, 💎 en poche, 🔒 au coffre,
	        intérêts du jour (bouton Réclamer) ;
	      onglets : 🏦 Compte (déposer / retirer, montants rapides),
	        💱 Change (💎 -> Dopamine, cours, limite du jour),
	        💎 Luxe (boutique : bijoux, titres, peintures ; Acheter /
	        Porter / Retirer ; filtres), 📜 Historique, 🕶️ Casses (stats,
	        prochain casse, règles : aucune arme) ;
	      bandeau "Rends-toi à la banque" quand on n'y est pas (seuls
	      "Porter" et la consultation marchent à distance).
	Ordinateur + téléphone (UIScale, mise en page resserrée).

	API (BankClient) :
	  BankUI.Build(callbacks)  { Action(action, arg) -> (ok, message) }
	  BankUI.Destroy() ; BankUI.Open(tab?) ; BankUI.Close() ; BankUI.IsOpen()
	  BankUI.SetState(state) ; BankUI.SetNear(near) ; BankUI.Flash(text, good?)
	  BankUI.SetChipVisible(visible) ; BankUI.Debug()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local HeistRules = require(ReplicatedStorage.Shared.HeistRules)

local BankUI = {}

BankUI.GUI_NAME = "BankGui"

local rgb = Color3.fromRGB
local NAVY = rgb(18, 24, 44)
local NAVY2 = rgb(28, 36, 64)
local NAVY3 = rgb(40, 50, 86)
local GOLD = rgb(236, 190, 84)
local WHITE = rgb(255, 255, 255)
local SOFT = rgb(190, 200, 228)
local MINT = rgb(96, 222, 160)
local RED = rgb(240, 84, 96)
local PINK = rgb(255, 110, 170)
local DIAMOND = rgb(150, 230, 255)

local gui: ScreenGui? = nil
local parts: { [string]: any } = {}
local callbacks: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local state: any = nil
local near = false
local phone = false
local isOpen = false
local tab = "Account"
local amount = 1
local exchangeAmount = 1
local filter = "All"
local flashToken = 0

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

----------------------------------------------------------------------
-- Petites fabriques
----------------------------------------------------------------------

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = props.Font or Theme.Fonts.Title
	l.TextColor3 = props.Color or WHITE
	l.TextSize = props.TextSize or 18
	l.TextWrapped = props.Wrap == true
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	l.Text = props.Text or ""
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.fromScale(1, 1)
	l.Position = props.Position or UDim2.new()
	l.AnchorPoint = props.AnchorPoint or Vector2.zero
	l.ZIndex = props.ZIndex or 3
	l.RichText = props.Rich == true
	if props.Scaled then
		l.TextScaled = true
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.TextSize or 18, MinTextSize = 8, Parent = l })
	end
	l.Parent = props.Parent
	return l
end

local function box(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Name = props.Name or "Box"
	f.BackgroundColor3 = props.Color or NAVY2
	f.BackgroundTransparency = props.Transparency or 0
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.Position = props.Position or UDim2.new()
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.ZIndex = props.ZIndex or 2
	f.Visible = props.Visible ~= false
	f.ClipsDescendants = props.Clip == true
	if props.Radius then
		UIUtil.Corner(f, props.Radius)
	end
	if props.Stroke then
		UIUtil.Stroke(f, props.Stroke, props.StrokeThickness or 2, props.StrokeTransparency)
	end
	f.Parent = props.Parent
	return f
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Name = props.Name or "Button"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = props.Color or GOLD
	b.Size = props.Size or UDim2.fromOffset(120, 40)
	b.Position = props.Position or UDim2.new()
	b.AnchorPoint = props.AnchorPoint or Vector2.zero
	b.Font = Theme.Fonts.Title
	b.TextColor3 = props.TextColor or NAVY
	b.TextSize = props.TextSize or 17
	b.Text = props.Text or ""
	b.ZIndex = props.ZIndex or 4
	b.Visible = props.Visible ~= false
	b.TextWrapped = true
	UIUtil.Corner(b, props.Radius or UDim.new(0, 12))
	if props.Stroke ~= false then
		UIUtil.Stroke(b, props.StrokeColor or WHITE, 2, 0.6)
	end
	b.Parent = props.Parent
	pcall(UIUtil.AnimateButton, b)
	if props.OnClick then
		table.insert(conns, b.Activated:Connect(props.OnClick))
	end
	return b
end

local function clear(holder: Instance)
	for _, c in ipairs(holder:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function fmt(n: number): string
	return NumberFormatter.Format(n)
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local refresh: () -> ()

local function act(action: string, arg: any)
	local fn = callbacks.Action
	if type(fn) ~= "function" then
		return
	end
	task.spawn(function()
		local ok, message = fn(action, arg)
		if type(message) == "string" and message ~= "" then
			BankUI.Flash(message, ok == true)
		end
	end)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local TABS = {
	{ Id = "Account", Icon = "🏦", Name = "Account" },
	{ Id = "Exchange", Icon = "💱", Name = "Exchange" },
	{ Id = "Luxury", Icon = "💎", Name = "Luxury" },
	{ Id = "History", Icon = "📜", Name = "History" },
	{ Id = "Heists", Icon = "🕶️", Name = "Heists" },
}

local function balanceCard(parent: Instance, name: string, icon: string, title: string, color: Color3, y: number): TextLabel
	local card = box({ Name = name, Parent = parent, Color = NAVY2, Size = UDim2.new(1, 0, 0, 78), Position = UDim2.fromOffset(0, y), Radius = UDim.new(0, 14), Stroke = color, StrokeTransparency = 0.55 })
	local strip = box({ Name = "Strip", Parent = card, Color = color, Size = UDim2.new(0, 6, 1, -16), Position = UDim2.fromOffset(8, 8), Radius = UDim.new(1, 0), ZIndex = 3 })
	local _ = strip
	label({ Name = "Icon", Parent = card, Text = icon, TextSize = 30, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(20, 17) })
	label({ Name = "Title", Parent = card, Text = T(title), Color = SOFT, TextSize = 14, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -76, 0, 20), Position = UDim2.fromOffset(70, 12) })
	return label({ Name = "Value", Parent = card, Text = "0", Color = WHITE, TextSize = 28, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -76, 0, 34), Position = UDim2.fromOffset(70, 32), Scaled = true })
end

local function buildChip(root: Frame)
	local chip = Instance.new("TextButton")
	chip.Name = "DiamondChip"
	chip.AutoButtonColor = true
	chip.BackgroundColor3 = NAVY
	chip.BackgroundTransparency = 0.08
	chip.Size = UDim2.fromOffset(124, 40)
	chip.Position = UDim2.fromOffset(10, 112)
	chip.Text = ""
	chip.ZIndex = 5
	UIUtil.Corner(chip, UDim.new(1, 0))
	UIUtil.Stroke(chip, GOLD, 2, 0.2)
	chip.Parent = root
	label({ Name = "Gem", Parent = chip, Text = "💎", TextSize = 22, Size = UDim2.fromOffset(32, 40), Position = UDim2.fromOffset(6, 0), ZIndex = 6 })
	parts.ChipValue = label({ Name = "Value", Parent = chip, Text = "0", TextSize = 20, Color = WHITE, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -46, 1, 0), Position = UDim2.fromOffset(40, 0), ZIndex = 6, Scaled = true })
	parts.ChipScale = UIUtil.Create("UIScale", { Parent = chip })
	table.insert(conns, chip.Activated:Connect(function()
		if isOpen then
			BankUI.Close()
		else
			BankUI.Open(nil)
		end
	end))
	parts.Chip = chip
end

local function buildWindow(root: Frame)
	local win = box({ Name = "BankWindow", Parent = root, Color = NAVY, Size = UDim2.fromOffset(860, 500), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Radius = UDim.new(0, 22), Stroke = GOLD, StrokeTransparency = 0.25, StrokeThickness = 3, Visible = false, ZIndex = 10 })
	win.Active = true
	parts.Window = win
	parts.WindowScale = UIUtil.Create("UIScale", { Parent = win })
	UIUtil.Gradient(win, ColorSequence.new(rgb(26, 34, 62), rgb(14, 18, 34)), 90)
	pcall(UIUtil.SinkClicks, win)
	-- en-tête
	local head = box({ Name = "Head", Parent = win, Color = NAVY2, Size = UDim2.new(1, 0, 0, 62), Radius = UDim.new(0, 22), ZIndex = 11 })
	UIUtil.Gradient(head, ColorSequence.new(rgb(46, 56, 98), rgb(24, 30, 56)), 0)
	box({ Name = "GoldLine", Parent = win, Color = GOLD, Size = UDim2.new(1, -40, 0, 2), Position = UDim2.fromOffset(20, 62), ZIndex = 12 })
	label({ Name = "Logo", Parent = head, Text = "🏦", TextSize = 34, Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(16, 6), ZIndex = 12 })
	label({ Name = "Title", Parent = head, Text = T("Dopamine Bank"), Color = GOLD, TextSize = 26, Font = Enum.Font.Garamond, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(0, 420, 0, 30), Position = UDim2.fromOffset(72, 6), ZIndex = 12 })
	label({ Name = "Sub", Parent = head, Text = T("Your Dopamine, your diamonds, your vault"), Color = SOFT, TextSize = 14, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(0, 420, 0, 18), Position = UDim2.fromOffset(72, 36), ZIndex = 12 })
	local close = button({ Name = "CloseBank", Parent = head, Text = "✕", Color = NAVY3, TextColor = WHITE, Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), ZIndex = 13, OnClick = function()
		BankUI.Close()
	end })
	local _ = close
	-- colonne des soldes
	local left = box({ Name = "Balances", Parent = win, Transparency = 1, Size = UDim2.new(0, 238, 1, -86), Position = UDim2.fromOffset(16, 76), ZIndex = 11 })
	parts.Dopamine = balanceCard(left, "DopamineCard", "🧠", "Dopamine", PINK, 0)
	parts.Wallet = balanceCard(left, "WalletCard", "💎", "Diamonds in your pocket", DIAMOND, 86)
	parts.Vault = balanceCard(left, "VaultCard", "🔒", "Diamonds in your vault", GOLD, 172)
	local interest = box({ Name = "Interest", Parent = left, Color = rgb(30, 56, 58), Size = UDim2.new(1, 0, 0, 132), Position = UDim2.fromOffset(0, 258), Radius = UDim.new(0, 14), Stroke = MINT, StrokeTransparency = 0.5 })
	label({ Name = "Title", Parent = interest, Text = "📈 " .. T("Vault interest"), Color = MINT, TextSize = 16, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(12, 8) })
	parts.InterestText = label({ Name = "Text", Parent = interest, Text = "", Color = SOFT, TextSize = 13, Font = Theme.Fonts.Body, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(12, 32) })
	parts.InterestButton = button({ Name = "ClaimInterest", Parent = interest, Text = "", Color = MINT, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 82), OnClick = function()
		act("interest", nil)
	end })
	-- onglets
	local tabs = box({ Name = "Tabs", Parent = win, Transparency = 1, Size = UDim2.new(1, -290, 0, 44), Position = UDim2.fromOffset(270, 76), ZIndex = 11 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = tabs })
	parts.TabButtons = {}
	for i, t in ipairs(TABS) do
		local b = button({ Name = "Tab_" .. t.Id, Parent = tabs, Text = t.Icon .. " " .. T(t.Name), Color = NAVY3, TextColor = WHITE, TextSize = 15, Size = UDim2.new(0.2, -5, 1, 0), ZIndex = 12, OnClick = function()
			tab = t.Id
			refresh()
		end })
		b.LayoutOrder = i
		parts.TabButtons[t.Id] = b
	end
	-- page
	local page = box({ Name = "Page", Parent = win, Color = NAVY2, Size = UDim2.new(1, -290, 1, -184), Position = UDim2.fromOffset(270, 128), Radius = UDim.new(0, 16), ZIndex = 11, Clip = true })
	parts.Page = page
	-- bandeau "rends-toi à la banque" + message
	parts.NearBanner = label({ Name = "NearBanner", Parent = win, Text = "📍 " .. T("Go to the bank to deposit, exchange or buy (counters, ATMs, jeweller)"), Color = GOLD, TextSize = 14, Font = Theme.Fonts.Body, Wrap = true, Size = UDim2.new(1, -290, 0, 22), Position = UDim2.new(0, 270, 1, -50), ZIndex = 12 })
	parts.Flash = label({ Name = "Flash", Parent = win, Text = "", Color = MINT, TextSize = 16, Size = UDim2.new(1, -290, 0, 24), Position = UDim2.new(0, 270, 1, -28), ZIndex = 12, Scaled = true })
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

local function amountRow(parent: Instance, y: number, values: { any }, current: number, onPick: (any) -> ())
	local row = box({ Name = "Amounts", Parent = parent, Transparency = 1, Size = UDim2.new(1, -32, 0, 40), Position = UDim2.fromOffset(16, y), ZIndex = 12 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = row })
	for i, v in ipairs(values) do
		local text = if v == "All" then T("All") else tostring(v)
		local selected = (v == current)
		local b = button({ Name = "Amount_" .. tostring(v), Parent = row, Text = text, Color = selected and GOLD or NAVY3, TextColor = selected and NAVY or WHITE, Size = UDim2.new(1 / #values, -7, 1, 0), ZIndex = 13, OnClick = function()
			onPick(v)
		end })
		b.LayoutOrder = i
	end
end

local function pageAccount(page: Frame)
	local s = state or {}
	label({ Name = "Head", Parent = page, Text = "🔒 " .. T("Deposit or withdraw diamonds"), TextSize = 20, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 12) })
	label({ Name = "Info", Parent = page, Text = T("Diamonds in the vault earn %d%% interest per day (up to %d 💎). Diamonds in your pocket buy luxury items.", math.floor((Config.Bank.Vault.InterestRate or 0.02) * 100 + 0.5), Config.Bank.Vault.InterestMax or 10), Color = SOFT, TextSize = 14, Font = Theme.Fonts.Body, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -32, 0, 40), Position = UDim2.fromOffset(16, 44) })
	amountRow(page, 96, { 1, 5, 10, 50, "All" }, amount, function(v)
		amount = v
		refresh()
	end)
	local function resolve(max: number): number
		if amount == "All" then
			return max
		end
		return math.min(tonumber(amount) or 1, math.max(0, max))
	end
	local dep = resolve(tonumber(s.Wallet) or 0)
	local wit = resolve(tonumber(s.Vault) or 0)
	button({ Name = "Deposit", Parent = page, Text = "🔒 " .. T("Deposit %d 💎", dep), Color = GOLD, Size = UDim2.new(0.5, -22, 0, 58), Position = UDim2.fromOffset(16, 150), TextSize = 19, OnClick = function()
		if dep > 0 then
			act("deposit", dep)
		end
	end })
	button({ Name = "Withdraw", Parent = page, Text = "💎 " .. T("Withdraw %d 💎", wit), Color = DIAMOND, Size = UDim2.new(0.5, -22, 0, 58), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 150), TextSize = 19, OnClick = function()
		if wit > 0 then
			act("withdraw", wit)
		end
	end })
	-- total + gains du jour
	local cap = tonumber(s.DailyCap) or 80
	local today = tonumber(s.DayEarned) or 0
	label({ Name = "Today", Parent = page, Text = T("Earned from heists today: %d / %d 💎", today, cap), Color = SOFT, TextSize = 15, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 224) })
	local bar = box({ Name = "TodayBar", Parent = page, Color = NAVY3, Size = UDim2.new(1, -32, 0, 12), Position = UDim2.fromOffset(16, 250), Radius = UDim.new(1, 0) })
	box({ Name = "Fill", Parent = bar, Color = DIAMOND, Size = UDim2.new(math.clamp(today / math.max(1, cap), 0, 1), 0, 1, 0), Radius = UDim.new(1, 0), ZIndex = 3 })
	label({ Name = "Totals", Parent = page, Text = T("Total earned: %d 💎 · spent: %d 💎", tonumber(s.Earned) or 0, tonumber(s.Spent) or 0), Color = SOFT, TextSize = 14, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 272) })
end

local function pageExchange(page: Frame)
	local s = state or {}
	local rate = tonumber(s.ExchangeRate) or 0
	local left = tonumber(s.ExchangeLeft) or 0
	local max = (Config.Bank.Exchange.DailyMax or 15)
	label({ Name = "Head", Parent = page, Text = "💱 " .. T("Diamond exchange"), TextSize = 20, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 12) })
	local rateBox = box({ Name = "Rate", Parent = page, Color = NAVY3, Size = UDim2.new(1, -32, 0, 70), Position = UDim2.fromOffset(16, 48), Radius = UDim.new(0, 14), Stroke = GOLD, StrokeTransparency = 0.6 })
	label({ Name = "RateText", Parent = rateBox, Text = T("1 💎 = %s Dopamine", fmt(rate)), TextSize = 26, Color = WHITE, Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 6), Scaled = true })
	label({ Name = "RateSub", Parent = rateBox, Text = T("(%d seconds of your production)", Config.Bank.Exchange.SecondsPerDiamond or 30), TextSize = 14, Color = SOFT, Font = Theme.Fonts.Body, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 44) })
	amountRow(page, 130, { 1, 5, 10, "All" }, exchangeAmount, function(v)
		exchangeAmount = v
		refresh()
	end)
	local n = if exchangeAmount == "All" then math.min(left, tonumber(s.Wallet) or 0) else math.min(tonumber(exchangeAmount) or 1, left)
	button({ Name = "DoExchange", Parent = page, Text = "💱 " .. T("Exchange %d 💎 → %s Dopamine", n, fmt(rate * n)), Color = PINK, TextColor = WHITE, Size = UDim2.new(1, -32, 0, 56), Position = UDim2.fromOffset(16, 184), TextSize = 18, OnClick = function()
		if n > 0 then
			act("exchange", n)
		end
	end })
	label({ Name = "Left", Parent = page, Text = T("Exchanged today: %d / %d 💎", max - left, max), Color = SOFT, TextSize = 15, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 252) })
	local bar = box({ Name = "LeftBar", Parent = page, Color = NAVY, Size = UDim2.new(1, -32, 0, 12), Position = UDim2.fromOffset(16, 278), Radius = UDim.new(1, 0) })
	box({ Name = "Fill", Parent = bar, Color = PINK, Size = UDim2.new(math.clamp((max - left) / math.max(1, max), 0, 1), 0, 1, 0), Radius = UDim.new(1, 0), ZIndex = 3 })
end

local FILTERS = {
	{ Id = "All", Name = "All" },
	{ Id = "Wear", Name = "Jewels & style" },
	{ Id = "Title", Name = "Titles" },
	{ Id = "Paint", Name = "Car paints" },
}

local function pageLuxury(page: Frame)
	local s = state or {}
	local owned = type(s.Owned) == "table" and s.Owned or {}
	local equipped = type(s.Equipped) == "table" and s.Equipped or {}
	local heists = type(s.Heist) == "table" and s.Heist or {}
	local row = box({ Name = "Filters", Parent = page, Transparency = 1, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 10), ZIndex = 12 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = row })
	for i, f in ipairs(FILTERS) do
		local sel = filter == f.Id
		local b = button({ Name = "Filter_" .. f.Id, Parent = row, Text = T(f.Name), Color = sel and GOLD or NAVY3, TextColor = sel and NAVY or WHITE, TextSize = 14, Size = UDim2.new(0.25, -5, 1, 0), ZIndex = 13, OnClick = function()
			filter = f.Id
			refresh()
		end })
		b.LayoutOrder = i
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Catalogue"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, -16, 1, -54)
	scroll.Position = UDim2.fromOffset(8, 50)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 12
	scroll.Parent = page
	UIUtil.Create("UIGridLayout", { CellSize = UDim2.new(0.5, -8, 0, 92), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), Parent = scroll })
	for _, item in ipairs(Config.Bank.Luxury) do
		if filter == "All" or item.Kind == filter then
			local own = owned[item.Id] == true
			local worn = item.Slot and equipped[item.Slot] == item.Id
			local need = tonumber(item.NeedHeists) or 0
			local locked = need > 0 and (tonumber(heists.Success) or 0) < need
			local card = box({ Name = "Item_" .. item.Id, Parent = scroll, Color = own and rgb(36, 50, 74) or NAVY3, Radius = UDim.new(0, 14), Stroke = own and GOLD or SOFT, StrokeTransparency = own and 0.3 or 0.8, ZIndex = 13 })
			card.LayoutOrder = item.Order or 0
			local iconBg = box({ Name = "IconBg", Parent = card, Color = NAVY, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(10, 14), Radius = UDim.new(0, 12), ZIndex = 14 })
			if item.Color then
				box({ Name = "Swatch", Parent = iconBg, Color = item.Color, Size = UDim2.fromOffset(52, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Radius = UDim.new(0, 6), ZIndex = 15 })
			end
			label({ Name = "Icon", Parent = iconBg, Text = item.Icon or "💎", TextSize = 34, Size = UDim2.new(1, 0, 1, item.Color and -14 or 0), ZIndex = 15 })
			label({ Name = "Name", Parent = card, Text = T(item.Name), TextSize = 15, Color = WHITE, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -86, 0, 20), Position = UDim2.fromOffset(82, 8), ZIndex = 14, Scaled = true })
			label({ Name = "Desc", Parent = card, Text = T(item.Desc or ""), TextSize = 12, Color = SOFT, Font = Theme.Fonts.Body, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -86, 0, 30), Position = UDim2.fromOffset(82, 28), ZIndex = 14 })
			local text, color, textColor, action = "", GOLD, NAVY, nil
			if own then
				if item.Kind == "Paint" then
					text, color, textColor = "✅ " .. T("In your garage"), NAVY, MINT
				elseif worn then
					text, color, textColor, action = "✓ " .. T("Worn · remove"), MINT, NAVY, "equip"
				else
					text, color, textColor, action = T("Wear"), DIAMOND, NAVY, "equip"
				end
			elseif locked then
				text, color, textColor = "🔒 " .. T("%d heists", need), NAVY, SOFT
			else
				text, action = T("%d 💎", item.Price), "buy"
				if (tonumber(s.Wallet) or 0) < item.Price then
					color, textColor = NAVY, GOLD
				end
			end
			button({ Name = "Act", Parent = card, Text = text, Color = color, TextColor = textColor, TextSize = 14, Size = UDim2.new(1, -92, 0, 28), Position = UDim2.fromOffset(82, 58), ZIndex = 15, OnClick = function()
				if action then
					act(action, item.Id)
				end
			end })
		end
	end
end

local KIND_ICON = { Deposit = "🔒", Withdraw = "💎", Interest = "📈", Exchange = "💱", Buy = "🛍️", Spend = "🛍️", Bank = "🏦", Train = "🚂", Ocean = "🌊", Race = "🏁" }
-- (textes propres à la banque : pas de clé partagée avec d'autres traductions)
local KIND_TEXT = { Deposit = "Deposit to the vault", Withdraw = "Withdrawal from the vault", Interest = "Vault interest", Exchange = "Diamond exchange",
	Spend = "Spent", Bank = "Bank heist", Train = "Diamond convoy", Ocean = "Ocean visit bonus", Race = "Race bonus", Admin = "Gift" }

local function ago(t: number): string
	local d = math.max(0, os.time() - (tonumber(t) or 0))
	if d < 60 then
		return T("just now")
	elseif d < 3600 then
		return T("%d min ago", math.floor(d / 60))
	elseif d < 86400 then
		return T("%d h ago", math.floor(d / 3600))
	end
	return T("%d d ago", math.floor(d / 86400))
end

local function pageHistory(page: Frame)
	local s = state or {}
	local list = type(s.History) == "table" and s.History or {}
	label({ Name = "Head", Parent = page, Text = "📜 " .. T("Account history"), TextSize = 20, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 10) })
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "HistoryList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, -16, 1, -50)
	scroll.Position = UDim2.fromOffset(8, 44)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 12
	scroll.Parent = page
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	if #list == 0 then
		label({ Name = "Empty", Parent = scroll, Text = T("No transactions yet: pull off a heist to earn your first diamonds!"), TextSize = 15, Color = SOFT, Font = Theme.Fonts.Body, Wrap = true, Size = UDim2.new(1, -12, 0, 60), ZIndex = 13 })
		return
	end
	for i, h in ipairs(list) do
		local row = box({ Name = "Row", Parent = scroll, Color = (i % 2 == 0) and NAVY3 or rgb(34, 44, 76), Size = UDim2.new(1, -12, 0, 40), Radius = UDim.new(0, 10), ZIndex = 13 })
		row.LayoutOrder = i
		label({ Name = "Icon", Parent = row, Text = KIND_ICON[h.K] or "💎", TextSize = 20, Size = UDim2.fromOffset(36, 40), Position = UDim2.fromOffset(4, 0), ZIndex = 14 })
		local what = T(KIND_TEXT[h.K] or "Bonus diamonds")
		if h.K == "Buy" and Config.BankLuxuryById[h.N] then
			what = T("Bought: %s", T(Config.BankLuxuryById[h.N].Name))
		elseif h.K == "Exchange" and h.N ~= "" then
			what = T("Exchange → +%s Dopamine", h.N)
		end
		label({ Name = "What", Parent = row, Text = what, TextSize = 15, Color = WHITE, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 1, 0), Position = UDim2.fromOffset(42, 0), ZIndex = 14, Scaled = true })
		local a = tonumber(h.A) or 0
		label({ Name = "Amount", Parent = row, Text = (a >= 0 and "+" or "") .. tostring(a) .. " 💎", TextSize = 16, Color = a >= 0 and MINT or RED, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(80, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 0), ZIndex = 14 })
		label({ Name = "When", Parent = row, Text = ago(h.T), TextSize = 12, Color = SOFT, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(70, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), ZIndex = 14 })
	end
end

local function pageHeists(page: Frame)
	local s = state or {}
	local h = type(s.Heist) == "table" and s.Heist or {}
	label({ Name = "Head", Parent = page, Text = "🕶️ " .. T("Heists"), TextSize = 20, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 10) })
	local grid = box({ Name = "Stats", Parent = page, Transparency = 1, Size = UDim2.new(1, -32, 0, 70), Position = UDim2.fromOffset(16, 44), ZIndex = 12 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = grid })
	for i, st in ipairs({ { "🎯", "Heists", h.Done or 0 }, { "✅", "Successful", h.Success or 0 }, { "💰", "Best loot", tostring(h.Best or 0) .. " %" } }) do
		local c = box({ Name = "Stat", Parent = grid, Color = NAVY3, Size = UDim2.new(1 / 3, -6, 1, 0), Radius = UDim.new(0, 12), ZIndex = 13 })
		c.LayoutOrder = i
		label({ Name = "Value", Parent = c, Text = st[1] .. " " .. tostring(st[3]), TextSize = 22, Color = WHITE, Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 6), ZIndex = 14, Scaled = true })
		label({ Name = "Name", Parent = c, Text = T(st[2]), TextSize = 13, Color = SOFT, Font = Theme.Fonts.Body, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 42), ZIndex = 14 })
	end
	local K = Config.Bank.Heist.Kinds
	label({ Name = "Today", Parent = page, Text = T("Paid today: 🏦 %d/%d · 🚂 %d/%d", h.Bank or 0, K.Bank.Daily, h.Train or 0, K.Train.Daily), TextSize = 15, Color = WHITE, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 124) })
	parts.NextHeist = label({ Name = "Next", Parent = page, Text = "", TextSize = 15, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 150) })
	label({ Name = "Rules", Parent = page, Text = T("How it works: meet your crew (up to 4) at the heist plan behind the bank, hack the alarm box, drill the vault door, fill your bags and carry the loot to the hideout before time runs out. Cartoon heists only: crowbar, drill and laptop, never any weapons. Rewards: Dopamine + 💎, more with a bigger crew."), TextSize = 13, Color = SOFT, Font = Theme.Fonts.Body, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -32, 0, 110), Position = UDim2.fromOffset(16, 180) })
end

----------------------------------------------------------------------
-- Rafraîchissement
----------------------------------------------------------------------

refresh = function()
	if not parts.Window then
		return
	end
	local s = state or {}
	parts.ChipValue.Text = NumberFormatter.Format(tonumber(s.Wallet) or 0)
	parts.Dopamine.Text = fmt(tonumber(s.Dopamine) or 0)
	parts.Wallet.Text = tostring(tonumber(s.Wallet) or 0)
	parts.Vault.Text = tostring(tonumber(s.Vault) or 0)
	local due = tonumber(s.InterestDue) or 0
	if due > 0 then
		parts.InterestText.Text = T("Today's interest is ready!")
		parts.InterestButton.Text = T("Claim +%d 💎", due)
		parts.InterestButton.BackgroundColor3 = MINT
	else
		local tomorrow = tonumber(s.InterestTomorrow) or 0
		parts.InterestText.Text = if tomorrow > 0 then T("Tomorrow: +%d 💎", tomorrow) else T("Keep at least %d 💎 in your vault", Config.Bank.Vault.MinForInterest or 10)
		parts.InterestButton.Text = T("Come back tomorrow")
		parts.InterestButton.BackgroundColor3 = NAVY3
	end
	for id, b in pairs(parts.TabButtons) do
		local sel = id == tab
		b.BackgroundColor3 = sel and GOLD or NAVY3
		b.TextColor3 = sel and NAVY or WHITE
	end
	parts.NearBanner.Visible = not near
	if isOpen then
		clear(parts.Page)
		parts.NextHeist = nil
		if tab == "Account" then
			pageAccount(parts.Page)
		elseif tab == "Exchange" then
			pageExchange(parts.Page)
		elseif tab == "Luxury" then
			pageLuxury(parts.Page)
		elseif tab == "History" then
			pageHistory(parts.Page)
		else
			pageHeists(parts.Page)
		end
	end
end

-- Compte à rebours du prochain casse (appelé 2 fois / s par BankClient)
function BankUI.SetNextHeist(text: string)
	if parts.NextHeist and parts.NextHeist.Parent then
		parts.NextHeist.Text = text
	end
end

local function layout()
	local screen = gui
	if not screen or not parts.Root then
		return
	end
	local size = screen.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	phone = touch and math.min(size.X, size.Y) < 500
	local scale = math.clamp(math.min(size.X / 1100, size.Y / 620), 0.45, 1.3)
	parts.Scale.Scale = scale
	parts.Root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	-- fenêtre : tient dans l'écran (téléphone : presque plein écran)
	local rw, rh = size.X / scale, size.Y / scale
	parts.WindowScale.Scale = math.min(1, (rw - 16) / 860, (rh - 16) / 500)
	parts.ChipScale.Scale = if phone then 1.1 else 1
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function BankUI.Build(cb: { [string]: any })
	BankUI.Destroy()
	callbacks = cb or {}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(BankUI.GUI_NAME)
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = BankUI.GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 24
	screen.Parent = playerGui
	gui = screen
	local root = UIUtil.Create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(1100, 620), Parent = screen })
	parts.Root = root
	parts.Scale = UIUtil.Create("UIScale", { Parent = root })
	buildChip(root)
	buildWindow(root)
	table.insert(conns, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	layout()
	refresh()
end

function BankUI.Destroy()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(parts)
	isOpen = false
end

function BankUI.Open(which: string?)
	if not parts.Window then
		return
	end
	if which then
		tab = which
	end
	isOpen = true
	parts.Window.Visible = true
	refresh()
	pcall(UIUtil.Pop, parts.Window, 0.92, 0.18)
end

function BankUI.Close()
	isOpen = false
	if parts.Window then
		parts.Window.Visible = false
	end
end

function BankUI.IsOpen(): boolean
	return isOpen
end

function BankUI.SetState(s: any)
	if type(s) ~= "table" then
		return
	end
	local before = state and tonumber(state.Wallet) or nil
	state = s
	refresh()
	-- petit "pop" de la pastille quand on gagne des 💎
	if before and (tonumber(s.Wallet) or 0) > before and parts.Chip then
		pcall(UIUtil.Pop, parts.Chip, 1.25, 0.25)
	end
end

function BankUI.GetState(): any
	return state
end

function BankUI.SetNear(v: boolean)
	if near ~= v then
		near = v
		if parts.NearBanner then
			parts.NearBanner.Visible = not near
		end
	end
end

function BankUI.SetChipVisible(v: boolean)
	if parts.Chip then
		parts.Chip.Visible = v
	end
end

function BankUI.Flash(text: string, good: boolean?)
	local f = parts.Flash
	if not f then
		return
	end
	flashToken += 1
	local token = flashToken
	f.Text = text
	f.TextColor3 = if good == false then RED else MINT
	f.TextTransparency = 0
	task.delay(3, function()
		if token == flashToken and f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

function BankUI.Debug(): any
	return { Parts = parts, Refresh = refresh, Tab = function()
		return tab
	end, Clock = HeistRules.Clock }
end

return BankUI
