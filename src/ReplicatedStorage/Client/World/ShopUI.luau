--[[
	ShopUI (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ShopUI

	🛍️ Dopamine Town (v9.6, SHOPS96) : le CATALOGUE des boutiques de la ville
	(ScreenGui "TownShopGui", à part du HUD de la ville) et la logique
	d'achat partagée avec les objets exposés en 3D (ShopInteriors).
	  - une fenêtre par boutique : en-tête (icône, nom, Dopamine), onglets
	    des catégories de la boutique, grille de cartes (dessin 2D de
	    l'objet peint par petits paquets, ou vraie voiture 3D dans un
	    ViewportFrame), prix du prochain exemplaire, exemplaires possédés,
	    raison du verrou (visites à l'océan / amélioration du clicker),
	    bouton Acheter ; pied de page "✏️ Place tes achats chez toi" ;
	  - se ferme avec la croix dessinée (UIUtil.CloseButton), un clic hors
	    de la fenêtre, Échap, ou en s'éloignant du comptoir ;
	  - mise à l'échelle comme le HUD (PC / tablette / téléphone).
	Achats (ShopUI.Purchase, à appeler dans un task.spawn : ça attend le
	serveur) : vérifications locales (verrou, MAX, Dopamine), puis
	  "Item" : RemoteFunction House ("buyItem", id) ;
	  "Look" : House ("buyLook", { Kind = "Garden", Id }) (déco du jardin) ;
	  "Car"  : RemoteFunction Car ("buy", id) (GARAGE96) ;
	son existant "Buy" / "Error" (SoundManager, aucun nouveau son), petit
	message (toast du HUD de la ville), astuce "Place-le chez toi : ✏️
	Meubles", et le signal ShopUI.Bought. Faute de Dopamine : message
	"Il te manque X" (la fenêtre "Get Dopamine" du clicker est masquée en
	ville).

	API (require paresseux sans effet de bord ; l'interface est construite
	à la 1re ouverture) :
	  ShopUI.OpenShop(shopId, options?)  "Pets" | "Kitchen" | "Furniture" | "Setup" |
	                                     "Garden" | "Toys" | "Cars"
	      options : { Tab = catégorie?, Anchor = Vector3? (se ferme si
	      l'avatar s'en éloigne de plus de 18 studs) }
	  ShopUI.OpenCategory(categoryId?)   la boutique qui vend cette catégorie
	                                     (onglet choisi) ; nil -> "🛍️ Tout"
	  ShopUI.Close() / ShopUI.IsOpen()
	  ShopUI.Bought : Signal (itemId, kind)   après un achat RÉUSSI
	  ShopUI.Closed : Signal ()
	  ShopUI.SetToast(fn?)               fn(text, color?) (toast du HUD)
	  ShopUI.Entry(kind, id) -> Entry?   ShopUI.Price / Owned / LockText /
	  ShopUI.IsMaxed / ShopUI.ShopEntries(shopId) / ShopUI.ShopOf(categoryId)
	  ShopUI.Purchase(entry) -> boolean  (attend le serveur)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local HouseCommon = require(Client.Components.House.HouseCommon)

local ShopUI = {}

ShopUI.Bought = Signal.new()
ShopUI.Closed = Signal.new()

local PINK = Color3.fromRGB(255, 110, 170)
local PINK_DEEP = Color3.fromRGB(236, 72, 140)
local LILAC = Color3.fromRGB(170, 140, 245)
local MINT = Color3.fromRGB(64, 196, 150)
local INK = Color3.fromRGB(92, 58, 96)
local CARD = Color3.fromRGB(255, 250, 253)
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(176, 170, 190)
local RED = Color3.fromRGB(226, 80, 90)
local GREEN = Color3.fromRGB(70, 190, 120)

local ANCHOR_RANGE = 18 -- (studs) on s'éloigne du comptoir -> la fenêtre se ferme
local PAINT_PER_FRAME = 3 -- vignettes peintes par image

----------------------------------------------------------------------
-- Boutiques et onglets
----------------------------------------------------------------------

export type ShopDef = { Id: string, Name: string, Icon: string, Accent: Color3, Tabs: { string }, Blurb: string }

ShopUI.SHOPS = {
	Pets = { Id = "Pets", Name = "🐾 Pet Shop", Icon = "🐾", Accent = Color3.fromRGB(86, 176, 150), Tabs = { "Pets" },
		Blurb = "Cats, dogs, bunnies, fish… a new friend for your house" },
	Toys = { Id = "Toys", Name = "🧸 Toy Shop", Icon = "🧸", Accent = Color3.fromRGB(236, 104, 140), Tabs = { "Toys", "Sports", "Adventure" },
		Blurb = "Plushies, games, sports and adventure" },
	Kitchen = { Id = "Kitchen", Name = "🍰 Kitchen & Home", Icon = "🍰", Accent = Color3.fromRGB(214, 90, 110), Tabs = { "Kitchen" },
		Blurb = "Everything for a sweet kitchen" },
	Furniture = { Id = "Furniture", Name = "🛋️ Furniture & Decor", Icon = "🛋️", Accent = Color3.fromRGB(160, 116, 84),
		Tabs = { "Furniture", "Decor", "Lights", "Doors", "Windows" }, Blurb = "Sofas, beds, lamps, frames, doors and windows" },
	Setup = { Id = "Setup", Name = "🖥️ Setup Store", Icon = "🖥️", Accent = Color3.fromRGB(106, 90, 210), Tabs = { "Setup", "Electronics", "Gaming" },
		Blurb = "Desks, screens, TVs, hi-fi and gaming gear" },
	Garden = { Id = "Garden", Name = "🪴 Garden Centre", Icon = "🪴", Accent = Color3.fromRGB(84, 160, 96), Tabs = { "Plants", "SetupPlants", "GardenDecor" },
		Blurb = "Plants, dopamine flowers and garden decor" },
	Cars = { Id = "Cars", Name = "🚗 Car Dealership", Icon = "🚗", Accent = Color3.fromRGB(236, 72, 120), Tabs = { "Cars" },
		Blurb = "Buy a car, then drive it around town" },
} :: { [string]: ShopDef }
ShopUI.ORDER = { "Pets", "Toys", "Kitchen", "Furniture", "Setup", "Garden", "Cars" }

-- Catégorie de la maison -> boutique qui la vend
local SHOP_OF: { [string]: string } = {}
for _, id in ipairs(ShopUI.ORDER) do
	for _, tab in ipairs(ShopUI.SHOPS[id].Tabs) do
		SHOP_OF[tab] = id
	end
end

function ShopUI.ShopOf(categoryId: string?): string?
	return categoryId and SHOP_OF[categoryId] or nil
end

local function isSetupPlant(id: string): boolean
	return string.sub(id, 1, 10) == "SetupPlant"
end

export type Entry = { Kind: string, Id: string, Name: string, Icon: string, Def: any, Category: string }

local entryCache: { [string]: Entry } = {}

function ShopUI.Entry(kind: string, id: string): Entry?
	local key = kind .. ":" .. id
	local cached = entryCache[key]
	if cached then
		return cached
	end
	local def: any = nil
	local category = ""
	if kind == "Item" then
		def = HouseCommon.ItemsById[id]
		category = def and (isSetupPlant(id) and "SetupPlants" or tostring(def.Category)) or ""
	elseif kind == "Look" then
		local looks = (Config :: any).HouseLooksById
		def = looks and looks.Garden and looks.Garden[id]
		category = "GardenDecor"
	elseif kind == "Car" then
		local cars = (Config :: any).CarsById
		def = cars and cars[id]
		category = "Cars"
	end
	if type(def) ~= "table" then
		return nil
	end
	local entry: Entry = { Kind = kind, Id = id, Name = tostring(def.Name or id), Icon = tostring(def.Icon or "🎁"), Def = def, Category = category }
	entryCache[key] = entry
	return entry
end

-- Définition d'un onglet : nom, icône, entrées (triées par prix)
local function tabInfo(tabId: string): (string, string)
	local category = HouseCommon.CategoriesById[tabId]
	if category then
		return Locale.T(category.Name), tostring(category.Icon)
	elseif tabId == "SetupPlants" then
		return Locale.T("Dopamine plants"), "🌼"
	elseif tabId == "GardenDecor" then
		return Locale.T("Garden decor"), "🌷"
	elseif tabId == "Cars" then
		return Locale.T("Cars"), "🚗"
	end
	return tabId, "🛍️"
end

local tabCache: { [string]: { Entry } } = {}
local function tabEntries(tabId: string): { Entry }
	local cached = tabCache[tabId]
	if cached then
		return cached
	end
	local list: { Entry } = {}
	if tabId == "GardenDecor" then
		for _, look in ipairs((Config.House :: any).GardenDecor or {}) do
			local entry = ShopUI.Entry("Look", look.Id)
			if entry then
				table.insert(list, entry)
			end
		end
	elseif tabId == "Cars" then
		local cars = (Config :: any).Cars
		for _, car in ipairs(cars and cars.List or {}) do
			local entry = ShopUI.Entry("Car", car.Id)
			if entry then
				table.insert(list, entry)
			end
		end
	else
		for _, item in ipairs(HouseCommon.Config.Items) do
			local id = tostring(item.Id)
			local match
			if tabId == "SetupPlants" then
				match = isSetupPlant(id)
			else
				match = item.Category == tabId and not isSetupPlant(id)
			end
			if match then
				local entry = ShopUI.Entry("Item", id)
				if entry then
					table.insert(list, entry)
				end
			end
		end
	end
	local base: { [Entry]: number } = {}
	for index, entry in ipairs(list) do
		base[entry] = (tonumber(entry.Def.Cost) or 0) + index * 1e-6
	end
	table.sort(list, function(a, b)
		return base[a] < base[b]
	end)
	tabCache[tabId] = list
	return list
end

-- Toutes les entrées d'une boutique (par onglet, dans l'ordre)
function ShopUI.ShopEntries(shopId: string): { Entry }
	local shop = ShopUI.SHOPS[shopId]
	local list = {}
	for _, tab in ipairs(shop and shop.Tabs or {}) do
		for _, entry in ipairs(tabEntries(tab)) do
			table.insert(list, entry)
		end
	end
	return list
end

----------------------------------------------------------------------
-- Prix, possession, verrous
----------------------------------------------------------------------

local function carModels(): any?
	local module = ReplicatedStorage.Shared:FindFirstChild("CarModels")
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and type(result) == "table" and result or nil
end

local function house(): any
	return HouseCommon.GetHouse(ClientState.Data)
end

local function carsData(): any
	local data = ClientState.Data
	local cars = type(data) == "table" and data.Cars or nil
	return type(cars) == "table" and cars or {}
end

function ShopUI.Price(entry: Entry): number
	if entry.Kind == "Item" then
		return HouseCommon.Price(entry.Def, HouseCommon.Owned(house(), entry.Id))
	end
	return tonumber(entry.Def.Cost) or 0
end

function ShopUI.Owned(entry: Entry): number
	if entry.Kind == "Item" then
		return HouseCommon.Owned(house(), entry.Id)
	elseif entry.Kind == "Look" then
		return HouseCommon.OwnsLook(house(), "Garden", entry.Id) and 1 or 0
	end
	local owned = carsData().Owned
	return type(owned) == "table" and owned[entry.Id] == true and 1 or 0
end

function ShopUI.IsMaxed(entry: Entry): boolean
	if entry.Kind == "Item" then
		return HouseCommon.IsMaxed(entry.Def, ShopUI.Owned(entry))
	end
	return ShopUI.Owned(entry) > 0
end

-- Raison du verrou (texte traduit, sans cadenas) ou nil
function ShopUI.LockText(entry: Entry): string?
	local data = ClientState.Data
	if entry.Kind == "Car" then
		local cm = carModels()
		if cm and type(cm.LockReason) == "function" then
			local ok, text = pcall(cm.LockReason, data, entry.Id)
			if ok and type(text) == "string" and text ~= "" then
				return (string.gsub(text, "^🔒%s*", ""))
			end
			return nil
		end
	end
	local _, text = HouseCommon.LockReason(data, entry.Def)
	return text
end

function ShopUI.IsSelected(entry: Entry): boolean
	return entry.Kind == "Car" and carsData().Selected == entry.Id
end

local function fmt(value: number): string
	return NumberFormatter.Format(math.floor(value + 0.5))
end
ShopUI.Format = fmt

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------

local toastFn: ((string, Color3?) -> ())? = nil
local ui: any = nil -- interface (construite à la 1re ouverture)
local buildGui: () -> any -- (défini plus bas)

function ShopUI.SetToast(fn: ((string, Color3?) -> ())?)
	toastFn = fn
end

local function ensureGui(): any
	if ui then
		return ui
	end
	ui = buildGui()
	return ui
end

local function toast(text: string, color: Color3?)
	if toastFn then
		local ok = pcall(toastFn :: any, text, color)
		if ok then
			return
		end
	end
	local gui = ensureGui()
	gui.ShowToast(text, color)
end

-- Ligne d'état dans la fenêtre (si ouverte) + toast
local function status(text: string, color: Color3)
	if ui and ui.Open then
		ui.SetStatus(text, color)
	end
	toast(text, color)
end

----------------------------------------------------------------------
-- Achats
----------------------------------------------------------------------

local busy = false

local function invokeCar(action: string, id: string): (boolean, string?, any)
	local ok, success, message, extra = pcall(function()
		return Net.Function("Car"):InvokeServer(action, id)
	end)
	if not ok then
		return false, Locale.T("Network error, try again."), nil
	end
	return success == true, message ~= nil and tostring(message) or nil, extra
end

local function needDopamine(missing: number)
	status(Locale.T("You need %s more Dopamine", fmt(math.max(1, missing))) .. "  " .. Locale.T("👆 Click to earn more!"), PINK_DEEP)
end

-- Achète `entry` (attend le serveur) ; true si c'est fait
function ShopUI.Purchase(entry: Entry): boolean
	if busy then
		return false
	end
	local lock = ShopUI.LockText(entry)
	if lock then
		SoundManager.Play("Error", 0.7)
		status("🔒 " .. lock, LILAC)
		return false
	end
	if ShopUI.IsMaxed(entry) then
		SoundManager.Play("Error", 0.7)
		if entry.Kind == "Item" then
			status(Locale.T("You can't have more %s %s", entry.Icon, Locale.T(entry.Name)), LILAC)
		else
			status(Locale.T("✅ Already yours!"), MINT)
		end
		return false
	end
	local price = ShopUI.Price(entry)
	local have = HouseCommon.Dopamine()
	if have < price then
		SoundManager.Play("Error", 0.7)
		needDopamine(price - have)
		return false
	end
	busy = true
	local ok, message, extra
	if entry.Kind == "Item" then
		ok, message = HouseCommon.Invoke("buyItem", entry.Id)
	elseif entry.Kind == "Look" then
		ok, message = HouseCommon.Invoke("buyLook", { Kind = "Garden", Id = entry.Id })
	else
		ok, message, extra = invokeCar("buy", entry.Id)
	end
	busy = false
	if not ok then
		SoundManager.Play("Error", 0.7)
		if type(extra) == "number" and extra > 0 then
			needDopamine(extra)
		else
			status(message or Locale.T("Not possible right now."), RED)
		end
		return false
	end
	SoundManager.Play("Buy", 1.1)
	toast(message or (entry.Icon .. " " .. Locale.T(entry.Name)), GREEN)
	if entry.Kind == "Item" then
		toast(Locale.T("Place it at home: ✏️ Furniture"), LILAC)
	elseif entry.Kind == "Car" then
		toast(Locale.T("🚗 Drive it from the 🚗 My car button"), LILAC)
	end
	if ui and ui.Open then
		ui.SetStatus(message or "", GREEN)
		ui.Dirty = true
	end
	local fired = pcall(function()
		ShopUI.Bought:Fire(entry.Id, entry.Kind)
	end)
	if not fired then
		warn("[ShopUI] Bought")
	end
	return true
end

-- Voiture possédée : la choisir (celle qui sort avec "🚗 Ma voiture")
function ShopUI.SelectCar(entry: Entry): boolean
	if busy then
		return false
	end
	busy = true
	local ok, message = invokeCar("select", entry.Id)
	busy = false
	SoundManager.Play(ok and "Pop" or "Error", ok and 1.1 or 0.7)
	status(message or (ok and Locale.T("🚗 Selected!") or Locale.T("Not possible right now.")), ok and GREEN or RED)
	if ui then
		ui.Dirty = true
	end
	return ok
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

local function textWidth(text: string, size: number, font: Enum.Font?): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font or Theme.Fonts.Title, Vector2.new(4000, 200))
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return (utf8.len(text) or #text) * size * 0.55
end

local function label(props: { [string]: any }): TextLabel
	return UIUtil.Create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		TextColor3 = props.Color or INK,
		TextSize = props.TextSize or 16,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap == true,
		TextTruncate = props.Wrap == true and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 2,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
end

type Card = {
	Entry: Entry,
	Frame: Frame,
	Thumb: Frame,
	Price: TextLabel,
	Owned: TextLabel,
	Lock: TextLabel,
	Button: TextButton,
	Painted: boolean,
}

buildGui = function(): any
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("TownShopGui")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TownShopGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 25
	gui.Enabled = true
	gui.Parent = playerGui
	local root = UIUtil.Create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(1100, 620), Parent = gui })
	local scale = UIUtil.Create("UIScale", { Parent = root })

	local self: any = {
		Gui = gui,
		Root = root,
		Open = false,
		Dirty = false,
		Shop = nil :: ShopDef?,
		Tab = "",
		Cards = {} :: { Card },
		Queue = {} :: { Card },
		Anchor = nil :: Vector3?,
		Phone = false,
		Conns = {} :: { RBXScriptConnection },
		Clock = 0,
		StatusUntil = 0,
	}

	-- petits messages (si le HUD de la ville n'en fournit pas)
	local toasts = UIUtil.Create("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(640, 140), ZIndex = 40, Parent = root })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = toasts })
	local toastCount = 0
	function self.ShowToast(text: string, color: Color3?)
		toastCount += 1
		local frame = UIUtil.Create("Frame", { Name = "Toast", Size = UDim2.fromOffset(math.min(textWidth(text, 18) + 40, 640), 40), BackgroundColor3 = color or INK,
			BackgroundTransparency = 0.08, LayoutOrder = toastCount, ZIndex = 40, Parent = toasts })
		UIUtil.Corner(frame, UDim.new(1, 0))
		label({ Name = "Text", Text = text, Color = WHITE, TextSize = 18, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 41, Parent = frame })
		task.delay(3.4, function()
			frame:Destroy()
		end)
	end

	-- voile + fenêtre
	local dimmer = UIUtil.Create("TextButton", { Name = "Dimmer", Size = UDim2.new(1, 400, 1, 400), Position = UDim2.fromOffset(-200, -200),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 20, Parent = root })
	local card = UIUtil.Create("Frame", { Name = "ShopCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(860, 540),
		BackgroundColor3 = CARD, Visible = false, ZIndex = 21, Parent = root })
	UIUtil.Corner(card, 26)
	local cardStroke = UIUtil.Stroke(card, LILAC, 3, 0)
	UIUtil.SinkClicks(card)
	UIUtil.Gradient(card, ColorSequence.new(WHITE, Color3.fromRGB(248, 240, 255)), 90)
	-- bandeau coloré en haut (couleur de la boutique)
	local band = UIUtil.Create("Frame", { Name = "Band", Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = PINK, ZIndex = 21, Parent = card })
	UIUtil.Corner(band, 26)
	local bandGradient = UIUtil.Gradient(band, ColorSequence.new(WHITE, Color3.fromRGB(214, 214, 214)), 90)
	local bandFill = UIUtil.Create("Frame", { Name = "BandFill", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), BackgroundColor3 = PINK,
		BorderSizePixel = 0, ZIndex = 21, Parent = band })
	local bubble = UIUtil.Create("Frame", { Name = "IconBubble", Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(16, 12), BackgroundColor3 = WHITE,
		ZIndex = 22, Parent = card })
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, WHITE, 3, 0.2)
	local icon = label({ Name = "Icon", Text = "🛍️", TextSize = 36, Font = Enum.Font.BuilderSansMedium, ZIndex = 23, Parent = bubble })
	local title = label({ Name = "Title", Text = "", Color = WHITE, TextSize = 28, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -330, 0, 36),
		Position = UDim2.fromOffset(92, 12), ZIndex = 22, Parent = card })
	UIUtil.Create("UIStroke", { Color = Color3.fromRGB(90, 50, 90), Thickness = 1.5, Transparency = 0.55, Parent = title })
	local subtitle = label({ Name = "Subtitle", Text = "", Color = WHITE, TextSize = 15, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -330, 0, 22), Position = UDim2.fromOffset(92, 48), ZIndex = 22, Parent = card })
	local wallet = UIUtil.Create("Frame", { Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 22), Size = UDim2.fromOffset(190, 42),
		BackgroundColor3 = WHITE, ZIndex = 22, Parent = card })
	UIUtil.Corner(wallet, UDim.new(1, 0))
	UIUtil.Stroke(wallet, Color3.fromRGB(255, 200, 226), 2, 0)
	local walletText = label({ Name = "Amount", Text = "🧠 0", Color = PINK_DEEP, TextSize = 20, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
		ZIndex = 23, Parent = wallet })
	local close = UIUtil.CloseButton({ Name = "CloseShop", Size = 42, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 22), ZIndex = 24, Hitbox = 0 })
	close.Parent = card
	-- onglets
	local tabs = UIUtil.Create("ScrollingFrame", { Name = "Tabs", Position = UDim2.fromOffset(16, 96), Size = UDim2.new(1, -32, 0, 44), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
		ZIndex = 22, Parent = card })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = tabs })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), Parent = tabs })
	-- grille
	local grid = UIUtil.Create("ScrollingFrame", { Name = "Grid", Position = UDim2.fromOffset(14, 148), Size = UDim2.new(1, -28, 1, -196), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 7, ScrollBarImageColor3 = LILAC, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 22, Parent = card })
	local gridLayout = UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(156, 214), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = grid })
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 6), Parent = grid })
	-- pied : astuce + état
	local footer = label({ Name = "Hint", Text = "", Color = INK, TextSize = 15, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -40, 0, 34), Position = UDim2.new(0, 22, 1, -44), ZIndex = 22, Parent = card })
	local statusPill = UIUtil.Create("Frame", { Name = "Status", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(400, 34),
		BackgroundColor3 = PINK_DEEP, Visible = false, ZIndex = 30, Parent = card })
	UIUtil.Corner(statusPill, UDim.new(1, 0))
	local statusText = label({ Name = "Text", Text = "", Color = WHITE, TextSize = 16, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), ZIndex = 31,
		Parent = statusPill })

	function self.SetStatus(text: string, color: Color3)
		if text == "" then
			statusPill.Visible = false
			return
		end
		statusText.Text = text
		statusPill.BackgroundColor3 = color
		statusPill.Size = UDim2.fromOffset(math.min(textWidth(text, 16) + 40, card.AbsoluteSize.X / math.max(0.01, scale.Scale) - 40), 34)
		statusPill.Visible = true
		self.StatusUntil = os.clock() + 3.2
	end

	----------------------------------------------------------------
	-- Cartes
	----------------------------------------------------------------

	local function buttonFor(c: Card)
		local entry = c.Entry
		local button = c.Button
		local lock = ShopUI.LockText(entry)
		local owned = ShopUI.Owned(entry)
		local color, text
		if lock then
			color, text = LILAC, "🔒"
		elseif entry.Kind == "Car" and owned > 0 then
			if ShopUI.IsSelected(entry) then
				color, text = MINT, Locale.T("✅ Selected")
			else
				color, text = PINK, Locale.T("🚗 Choose")
			end
		elseif ShopUI.IsMaxed(entry) then
			color, text = GREY, entry.Kind == "Item" and "MAX" or Locale.T("✅ Yours")
		else
			local affordable = HouseCommon.Dopamine() >= ShopUI.Price(entry)
			color, text = affordable and GREEN or Color3.fromRGB(236, 150, 90), Locale.T("Buy")
		end
		if button:GetAttribute("BaseColor") ~= color then
			button.BackgroundColor3 = color
			button:SetAttribute("BaseColor", color)
			local stroke = button:FindFirstChild("ButtonStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = UIUtil.EdgeColor(color)
			end
		end
		button.Text = text
	end

	local function refreshCard(c: Card)
		local entry = c.Entry
		local lock = ShopUI.LockText(entry)
		local owned = ShopUI.Owned(entry)
		local maxed = ShopUI.IsMaxed(entry)
		c.Price.Text = (maxed and entry.Kind ~= "Item") and "" or ("🧠 " .. fmt(ShopUI.Price(entry)))
		c.Price.TextColor3 = HouseCommon.Dopamine() >= ShopUI.Price(entry) and PINK_DEEP or Color3.fromRGB(200, 120, 90)
		c.Lock.Text = lock and ("🔒 " .. lock) or ""
		c.Lock.Visible = lock ~= nil
		c.Price.Visible = lock == nil
		if owned > 0 then
			c.Owned.Text = entry.Kind == "Item" and ("✅ x" .. owned) or "✅"
			c.Owned.Visible = true
			c.Owned.Size = UDim2.fromOffset(textWidth(c.Owned.Text, 14) + 18, 24)
		else
			c.Owned.Visible = false
		end
		c.Thumb.BackgroundTransparency = lock and 0.35 or 0
		buttonFor(c)
	end

	local function paint(c: Card)
		if c.Painted then
			return
		end
		c.Painted = true
		local entry = c.Entry
		local ok, err = pcall(function()
			if entry.Kind == "Item" then
				local HouseArt = require(Client.Components.House.HouseArt) :: any
				HouseArt.Thumbnail(c.Thumb, entry.Def, 100, 24)
			elseif entry.Kind == "Look" then
				local HouseArt = require(Client.Components.House.HouseArt) :: any
				local holder = UIUtil.Create("Frame", { Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(100, 100), ZIndex = 24, Parent = c.Thumb })
				local body = UIUtil.Create("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 100), ZIndex = 24, Parent = holder })
				UIUtil.Create("UIScale", { Scale = 0.9, Parent = body })
				local result = HouseArt.PaintGarden(body, entry.Def, true)
				if result == nil and #body:GetChildren() <= 1 then
					label({ Name = "Emoji", Text = entry.Icon, TextSize = 60, Font = Enum.Font.BuilderSansMedium, ZIndex = 25, Parent = holder })
				end
			else
				-- vraie voiture 3D (CarModels) dans un ViewportFrame
				local cm = carModels()
				local vp = UIUtil.Create("ViewportFrame", { Name = "Car3D", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = c.Thumb })
				vp.Ambient = Color3.fromRGB(200, 196, 214)
				vp.LightColor = Color3.fromRGB(255, 250, 240)
				vp.LightDirection = Vector3.new(-1, -1.4, -0.6)
				if cm and type(cm.Build) == "function" then
					local model = cm.Build(entry.Id, nil, { Detail = "Parked" })
					local camera = Instance.new("Camera")
					camera.FieldOfView = 30
					local size = typeof(model:GetAttribute("Length")) == "number" and model:GetAttribute("Length") or 12
					model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(-35), 0))
					model.Parent = vp
					local dist = size * 2.05
					camera.CFrame = CFrame.lookAt(Vector3.new(dist * 0.55, size * 0.45, -dist * 0.85), Vector3.new(0, size * 0.13, 0))
					camera.Parent = vp
					vp.CurrentCamera = camera
				else
					label({ Name = "Emoji", Text = entry.Icon, TextSize = 60, Font = Enum.Font.BuilderSansMedium, ZIndex = 25, Parent = c.Thumb })
				end
			end
		end)
		if not ok then
			warn("[ShopUI] vignette " .. entry.Id .. " : " .. tostring(err))
		end
	end

	local function makeCard(entry: Entry, order: number): Card
		local frame = UIUtil.Create("Frame", { Name = "Card_" .. entry.Id, BackgroundColor3 = WHITE, LayoutOrder = order, ZIndex = 23, Parent = grid })
		UIUtil.Corner(frame, 18)
		UIUtil.Stroke(frame, Color3.fromRGB(236, 222, 250), 2, 0)
		local thumb = UIUtil.Create("Frame", { Name = "Thumb", Size = UDim2.new(1, -12, 0, 112), Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = entry.Kind == "Car" and Color3.fromRGB(236, 240, 252) or HouseCommon.CategoryTint(entry.Kind == "Item" and tostring(entry.Def.Category) or "Plants"),
			ZIndex = 23, ClipsDescendants = true, Parent = frame })
		UIUtil.Corner(thumb, 14)
		local owned = label({ Name = "Owned", Text = "", Color = WHITE, TextSize = 14, Size = UDim2.fromOffset(44, 24), Position = UDim2.fromOffset(12, 12), ZIndex = 27,
			Parent = frame })
		owned.BackgroundColor3 = MINT
		owned.BackgroundTransparency = 0
		UIUtil.Corner(owned, UDim.new(1, 0))
		label({ Name = "Name", Text = entry.Icon .. " " .. Locale.T(entry.Name), Color = INK, TextSize = 15, Wrap = true, Size = UDim2.new(1, -14, 0, 38),
			Position = UDim2.fromOffset(7, 120), ZIndex = 24, Parent = frame })
		local price = label({ Name = "Price", Text = "", Color = PINK_DEEP, TextSize = 17, Size = UDim2.new(1, -14, 0, 20), Position = UDim2.fromOffset(7, 157),
			ZIndex = 24, Parent = frame })
		local lock = label({ Name = "Lock", Text = "", Color = Color3.fromRGB(130, 100, 200), TextSize = 12, Font = Theme.Fonts.Body, Wrap = true,
			Size = UDim2.new(1, -14, 0, 26), Position = UDim2.fromOffset(7, 153), ZIndex = 24, Parent = frame })
		local button = UIUtil.PillButton({ Name = "Buy", Text = Locale.T("Buy"), Color = GREEN, Height = 30, TextSize = 16, ZIndex = 24, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -7), Parent = frame })
		button.AutomaticSize = Enum.AutomaticSize.None
		button.Size = UDim2.new(1, -24, 0, 30)
		local c: Card = { Entry = entry, Frame = frame, Thumb = thumb, Price = price, Owned = owned, Lock = lock, Button = button, Painted = false }
		button.Activated:Connect(function()
			if entry.Kind == "Car" and ShopUI.Owned(entry) > 0 and ShopUI.LockText(entry) == nil then
				task.spawn(ShopUI.SelectCar, entry)
				return
			end
			task.spawn(function()
				local okBuy = ShopUI.Purchase(entry)
				if not okBuy then
					UIUtil.Shake(button)
				else
					UIUtil.Pop(frame, 1.08, 0.25)
				end
				refreshCard(c)
			end)
		end)
		refreshCard(c)
		return c
	end

	local function clearCards()
		for _, c in ipairs(self.Cards) do
			c.Frame:Destroy()
		end
		table.clear(self.Cards)
		table.clear(self.Queue)
	end

	local tabButtons: { [string]: TextButton } = {}
	local function selectTab(tabId: string)
		self.Tab = tabId
		for id, button in pairs(tabButtons) do
			local on = id == tabId
			local color = on and (self.Shop and self.Shop.Accent or PINK) or WHITE
			button.BackgroundColor3 = color
			button:SetAttribute("BaseColor", color)
			button.TextColor3 = on and WHITE or INK
		end
		clearCards()
		local list = tabEntries(tabId)
		for index, entry in ipairs(list) do
			local c = makeCard(entry, index)
			table.insert(self.Cards, c)
			table.insert(self.Queue, c)
		end
		grid.CanvasPosition = Vector2.zero
		local shop = self.Shop
		local name = tabInfo(tabId)
		subtitle.Text = string.format("%s  ·  %s", Locale.T(shop and shop.Blurb or ""), Locale.T("%s items", tostring(#list)))
		if tabId == "Cars" then
			subtitle.Text = string.format("%s  ·  %s", Locale.T(shop and shop.Blurb or ""), Locale.T("%s cars", tostring(#list)))
		end
		local _ = name
	end

	local function buildTabs(shop: ShopDef, first: string)
		for _, child in ipairs(tabs:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(tabButtons)
		for index, tabId in ipairs(shop.Tabs) do
			local name, tabIcon = tabInfo(tabId)
			local text = string.format("%s %s  %d", tabIcon, name, #tabEntries(tabId))
			local button = UIUtil.PillButton({ Name = "Tab_" .. tabId, Text = text, Color = WHITE, Height = 38, TextSize = 17, LayoutOrder = index, ZIndex = 23,
				TextColor3 = INK, Parent = tabs })
			button.AutomaticSize = Enum.AutomaticSize.None
			button.Size = UDim2.fromOffset(textWidth(text, 17) + 40, 38)
			button.Activated:Connect(function()
				if self.Tab ~= tabId then
					SoundManager.Play("Click", 1.1)
					selectTab(tabId)
				end
			end)
			tabButtons[tabId] = button
		end
		tabs.Visible = #shop.Tabs > 1
		grid.Position = UDim2.fromOffset(14, #shop.Tabs > 1 and 148 or 100)
		grid.Size = UDim2.new(1, -28, 1, #shop.Tabs > 1 and -196 or -148)
		selectTab(first)
	end

	local function layout()
		local size = gui.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		local phone = touch and math.min(size.X, size.Y) < 500
		self.Phone = phone
		local designW, designH = phone and 820 or 1100, phone and 430 or 620
		local s = math.clamp(math.min(size.X / designW, size.Y / designH), 0.45, 1.35)
		scale.Scale = s
		root.Size = UDim2.fromOffset(size.X / s, size.Y / s)
		local rootW, rootH = size.X / s, size.Y / s
		card.Size = UDim2.fromOffset(math.min(900, rootW - 24), math.min(phone and 420 or 560, rootH - 16))
		gridLayout.CellSize = phone and UDim2.fromOffset(146, 206) or UDim2.fromOffset(156, 214)
		footer.Visible = not phone
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	local function updateWallet()
		walletText.Text = "🧠 " .. fmt(HouseCommon.Dopamine())
	end

	function self.Show(shop: ShopDef, tab: string, anchor: Vector3?)
		self.Shop = shop
		self.Anchor = anchor
		band.BackgroundColor3 = shop.Accent
		bandFill.BackgroundColor3 = shop.Accent
		bandGradient.Enabled = true
		cardStroke.Color = shop.Accent
		icon.Text = shop.Icon
		title.Text = Locale.T(shop.Name)
		footer.Text = shop.Id == "Cars" and Locale.T("🚗 Your cars wait in your garage: take one out with 🚗 My car")
			or Locale.T("✏️ Your purchases go to your inventory: place them at home with ✏️ Furniture")
		statusPill.Visible = false
		updateWallet()
		layout()
		dimmer.Visible = true
		card.Visible = true
		self.Open = true
		buildTabs(shop, tab)
		UIUtil.Pop(card, 0.92, 0.2)
	end

	function self.Hide()
		if not self.Open then
			return
		end
		self.Open = false
		dimmer.Visible = false
		card.Visible = false
		clearCards()
	end

	local function requestClose()
		(ShopUI :: any).Close()
	end
	dimmer.Activated:Connect(requestClose)
	close.Activated:Connect(requestClose)
	UserInputService.InputBegan:Connect(function(input)
		if self.Open and input.KeyCode == Enum.KeyCode.Escape then
			requestClose()
		end
	end)
	ClientState.Changed:Connect(function()
		if self.Open then
			self.Dirty = true
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not self.Open then
			return
		end
		-- vignettes : quelques-unes par image
		local painted = 0
		while painted < PAINT_PER_FRAME and self.Queue[1] do
			paint(table.remove(self.Queue, 1) :: Card)
			painted += 1
		end
		self.Clock += dt
		if self.Clock < 0.25 then
			return
		end
		self.Clock = 0
		updateWallet()
		if self.Dirty then
			self.Dirty = false
			for _, c in ipairs(self.Cards) do
				refreshCard(c)
			end
		end
		if statusPill.Visible and os.clock() > self.StatusUntil then
			statusPill.Visible = false
		end
		-- on s'éloigne du comptoir : la fenêtre se ferme
		local anchor = self.Anchor
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if anchor and rootPart and rootPart:IsA("BasePart") and (rootPart.Position - anchor).Magnitude > ANCHOR_RANGE then
			(ShopUI :: any).Close()
		end
	end)
	return self
end

----------------------------------------------------------------------
-- Ouvrir / fermer
----------------------------------------------------------------------

-- "🛍️ Tout" : toutes les catégories d'objets de la maison
local ALL_SHOP: ShopDef = { Id = "All", Name = "🛍️ Town catalog", Icon = "🛍️", Accent = PINK, Tabs = {}, Blurb = "Every item of every shop" }
do
	for _, category in ipairs(HouseCommon.Config.Categories or {}) do
		table.insert(ALL_SHOP.Tabs, tostring(category.Id))
	end
	table.insert(ALL_SHOP.Tabs, "SetupPlants")
end

function ShopUI.OpenShop(shopId: string, options: { Tab: string?, Anchor: Vector3? }?)
	local shop = ShopUI.SHOPS[shopId] or (shopId == "All" and ALL_SHOP or nil)
	if not shop then
		return
	end
	local tab = options and options.Tab
	if not tab or not table.find(shop.Tabs, tab) then
		tab = shop.Tabs[1]
	end
	local gui = ensureGui()
	if gui.Open then
		gui.Hide()
	end
	SoundManager.Play("Open", 1.1)
	gui.Show(shop, tab :: string, options and options.Anchor)
end

function ShopUI.OpenCategory(categoryId: string?)
	local shopId = ShopUI.ShopOf(categoryId)
	if shopId then
		ShopUI.OpenShop(shopId, { Tab = categoryId })
	else
		ShopUI.OpenShop("All", { Tab = categoryId })
	end
end

function ShopUI.Close()
	if ui and ui.Open then
		ui.Hide()
		pcall(function()
			ShopUI.Closed:Fire()
		end)
	end
end

function ShopUI.IsOpen(): boolean
	return ui ~= nil and ui.Open == true
end

-- (tests / rendus) état interne
function ShopUI.Debug(): any
	return ui
end

return ShopUI
