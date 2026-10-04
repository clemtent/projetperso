--[[
	CityInteriors (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CityInteriors

	🏪 Dopamine Town (v11, CITY11) : les INTÉRIEURS des commerces et des
	lieux de la ville, construits côté CLIENT (0 pièce serveur), en flux par
	leurs propriétaires :
	  - TownFacades : rez-de-chaussée des immeubles de rue et boutiques de la
	    place (ouverts, éclairés, on y ENTRE) ;
	  - CityBuildings : les bâtiments du catalogue (quartiers).
	Chaque métier a son agencement : comptoir (3,3) et caisse, étagères
	(1,5 à 6,5) remplies de produits colorés, vitrines réfrigérées, tables
	(3,1) et chaises (assise 1,85, cibles SCALE11), fauteuils de coiffeur et
	miroirs, machines à laver, tapis de course, rayonnages de livres, bancs
	d'église, bureaux et écrans, guichets, lits de consultation, pont
	élévateur... + un·e employé·e qui travaille (NPCModels : scanne, tape,
	parle) et parfois un·e client·e, animés par CityKit.Actor (près de la
	caméra seulement). Suspensions "NightGlow" (aucune vraie lumière).
	Tout est ancré ; meubles hauts / comptoirs SOLIDES (collision locale) ;
	CanQuery / CanTouch false ; aucune face confondue (décalages ≥ 0,03).

	Repère `F` : milieu du MUR AVANT, au niveau du SOL fini ; l'intérieur
	s'étend en z ∈ [0, d] (+Z = vers le fond), x ∈ [-w/2, w/2], y ∈ [0, h].

	API :
	  CityInteriors.KINDS                       liste des métiers
	  CityInteriors.Info(kind) -> { Emoji, Name, Sign: Color3, Wall: Color3 }
	  CityInteriors.Shell(m, F, w, d, h, kind, opts?)   sol, murs latéraux /
	      du fond et plafond (solides) ; opts.Floor = false : pas de dalle
	  CityInteriors.Lamps(m, F, w, d, h, kind)        suspensions seules
	  CityInteriors.Furnish(m, F, w, d, h, kind, seed, opts?) -> nombre de PNJ
	      opts = { DoorX = x de la porte (allée libre), NoNpc = bool,
	               MaxNpc = n }
	  CityInteriors.ForShop(text) -> kind   (enseigne -> métier le plus proche)
]]

local CityKit = require(script.Parent.CityKit)

local CityInteriors = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local Box = CityKit.Box
local Column = CityKit.Column
local Hash = CityKit.Hash
local WHITE = rgb(250, 250, 248)
local INK = rgb(36, 34, 44)
local STEEL = rgb(180, 184, 192)
local WOOD = rgb(168, 118, 78)
local WOOD_DARK = rgb(104, 70, 48)
local GOODS = {
	rgb(232, 72, 84), rgb(250, 196, 60), rgb(82, 160, 230), rgb(110, 196, 110), rgb(236, 120, 200),
	rgb(255, 150, 70), rgb(160, 110, 230), rgb(90, 210, 200), rgb(250, 250, 240),
}

-- Cibles "échelle Roblox" (SCALE11)
local COUNTER_H = 3.3
local TABLE_H = 3.1
local SEAT_H = 1.85

----------------------------------------------------------------------
-- Métiers : emoji, nom (anglais -> Locale), couleurs
----------------------------------------------------------------------

type Info = { Emoji: string, Name: string, Sign: Color3, Wall: Color3, Floor: Color3, FloorMat: Enum.Material }

local INFO: { [string]: Info } = {
	Pharmacy = { Emoji = "💊", Name = "Pharmacy", Sign = rgb(40, 160, 90), Wall = rgb(244, 248, 246), Floor = rgb(226, 230, 232), FloorMat = M.Marble },
	Bakery = { Emoji = "🥖", Name = "Bakery", Sign = rgb(170, 110, 60), Wall = rgb(250, 236, 214), Floor = rgb(196, 150, 110), FloorMat = M.WoodPlanks },
	Cafe = { Emoji = "☕", Name = "Café", Sign = rgb(120, 76, 50), Wall = rgb(236, 222, 204), Floor = rgb(150, 104, 72), FloorMat = M.WoodPlanks },
	Restaurant = { Emoji = "🍝", Name = "Restaurant", Sign = rgb(150, 40, 50), Wall = rgb(244, 230, 214), Floor = rgb(132, 86, 62), FloorMat = M.WoodPlanks },
	Pizza = { Emoji = "🍕", Name = "Pizzeria", Sign = rgb(200, 60, 50), Wall = rgb(250, 238, 220), Floor = rgb(200, 190, 176), FloorMat = M.Slate },
	Sushi = { Emoji = "🍣", Name = "Sushi bar", Sign = rgb(40, 40, 50), Wall = rgb(238, 230, 214), Floor = rgb(170, 140, 100), FloorMat = M.WoodPlanks },
	Grocery = { Emoji = "🍎", Name = "Grocery", Sign = rgb(60, 140, 70), Wall = rgb(246, 244, 232), Floor = rgb(210, 206, 196), FloorMat = M.Slate },
	Florist = { Emoji = "💐", Name = "Florist", Sign = rgb(210, 90, 140), Wall = rgb(236, 246, 232), Floor = rgb(200, 196, 188), FloorMat = M.Slate },
	Books = { Emoji = "📚", Name = "Bookshop", Sign = rgb(60, 80, 140), Wall = rgb(238, 232, 218), Floor = rgb(140, 96, 64), FloorMat = M.WoodPlanks },
	Barber = { Emoji = "💈", Name = "Barber", Sign = rgb(40, 60, 120), Wall = rgb(240, 240, 236), Floor = rgb(60, 60, 66), FloorMat = M.Marble },
	Laundry = { Emoji = "🧺", Name = "Laundromat", Sign = rgb(60, 150, 200), Wall = rgb(226, 240, 248), Floor = rgb(220, 222, 226), FloorMat = M.Slate },
	Gym = { Emoji = "💪", Name = "Gym", Sign = rgb(60, 66, 90), Wall = rgb(214, 218, 226), Floor = rgb(54, 56, 62), FloorMat = M.Rubber },
	Post = { Emoji = "📮", Name = "Post office", Sign = rgb(250, 196, 30), Wall = rgb(240, 240, 232), Floor = rgb(206, 204, 198), FloorMat = M.Slate },
	Clinic = { Emoji = "🩺", Name = "Medical centre", Sign = rgb(220, 60, 70), Wall = rgb(244, 248, 250), Floor = rgb(214, 226, 232), FloorMat = M.SmoothPlastic },
	Police = { Emoji = "🚓", Name = "Police station", Sign = rgb(30, 60, 140), Wall = rgb(228, 232, 240), Floor = rgb(170, 176, 186), FloorMat = M.Slate },
	Fire = { Emoji = "🚒", Name = "Fire station", Sign = rgb(200, 40, 40), Wall = rgb(236, 230, 226), Floor = rgb(150, 150, 150), FloorMat = M.Concrete },
	Office = { Emoji = "🏢", Name = "Offices", Sign = rgb(50, 60, 80), Wall = rgb(236, 238, 242), Floor = rgb(120, 126, 140), FloorMat = M.Fabric },
	Hotel = { Emoji = "🏨", Name = "Hotel", Sign = rgb(150, 110, 50), Wall = rgb(240, 228, 206), Floor = rgb(220, 210, 196), FloorMat = M.Marble },
	Museum = { Emoji = "🏛️", Name = "Museum", Sign = rgb(90, 70, 50), Wall = rgb(246, 240, 228), Floor = rgb(226, 220, 210), FloorMat = M.Marble },
	Library = { Emoji = "📖", Name = "Library", Sign = rgb(80, 60, 110), Wall = rgb(236, 226, 206), Floor = rgb(130, 90, 60), FloorMat = M.WoodPlanks },
	Cinema = { Emoji = "🎬", Name = "Cinema", Sign = rgb(200, 40, 60), Wall = rgb(70, 30, 44), Floor = rgb(120, 30, 40), FloorMat = M.Fabric },
	Garage = { Emoji = "🔧", Name = "Garage", Sign = rgb(220, 120, 30), Wall = rgb(206, 208, 212), Floor = rgb(120, 122, 126), FloorMat = M.Concrete },
	School = { Emoji = "🏫", Name = "School", Sign = rgb(60, 120, 200), Wall = rgb(246, 238, 210), Floor = rgb(196, 150, 100), FloorMat = M.WoodPlanks },
	Church = { Emoji = "⛪", Name = "Church", Sign = rgb(120, 100, 70), Wall = rgb(236, 228, 212), Floor = rgb(196, 188, 176), FloorMat = M.Slate },
	IceCream = { Emoji = "🍦", Name = "Ice cream", Sign = rgb(236, 90, 150), Wall = rgb(236, 250, 246), Floor = rgb(250, 220, 230), FloorMat = M.Marble },
	Boba = { Emoji = "🧋", Name = "Bubble tea", Sign = rgb(150, 90, 60), Wall = rgb(250, 236, 218), Floor = rgb(210, 180, 150), FloorMat = M.WoodPlanks },
	Candy = { Emoji = "🍭", Name = "Candy shop", Sign = rgb(236, 90, 160), Wall = rgb(255, 234, 244), Floor = rgb(255, 214, 230), FloorMat = M.Marble },
	Arcade = { Emoji = "🕹️", Name = "Arcade", Sign = rgb(120, 60, 220), Wall = rgb(40, 30, 70), Floor = rgb(30, 26, 50), FloorMat = M.Fabric },
	Music = { Emoji = "🎧", Name = "Record shop", Sign = rgb(40, 40, 60), Wall = rgb(220, 236, 230), Floor = rgb(80, 80, 92), FloorMat = M.WoodPlanks },
	Toys = { Emoji = "🧸", Name = "Toy shop", Sign = rgb(255, 130, 70), Wall = rgb(255, 240, 222), Floor = rgb(140, 200, 230), FloorMat = M.Fabric },
	Optician = { Emoji = "👓", Name = "Optician", Sign = rgb(40, 40, 50), Wall = rgb(246, 246, 246), Floor = rgb(214, 214, 218), FloorMat = M.Marble },
	Fashion = { Emoji = "👗", Name = "Fashion", Sign = rgb(30, 30, 36), Wall = rgb(248, 244, 240), Floor = rgb(200, 196, 190), FloorMat = M.Marble },
	Bike = { Emoji = "🚲", Name = "Bike shop", Sign = rgb(40, 140, 120), Wall = rgb(236, 240, 236), Floor = rgb(110, 112, 118), FloorMat = M.Concrete },
	Chocolate = { Emoji = "🍫", Name = "Chocolatier", Sign = rgb(100, 60, 40), Wall = rgb(246, 230, 214), Floor = rgb(120, 80, 56), FloorMat = M.WoodPlanks },
}
CityInteriors.KINDS = {}
for k in pairs(INFO) do
	table.insert(CityInteriors.KINDS, k)
end
table.sort(CityInteriors.KINDS)

-- Commerces "de rue" (rez-de-chaussée des immeubles) : ordre de tirage
CityInteriors.STREET_SHOPS = {
	"Bakery", "Pharmacy", "Florist", "Books", "Barber", "Laundry", "Cafe", "Grocery", "Optician", "Fashion",
	"Chocolate", "Bike", "Restaurant", "Sushi", "Pizza", "Music", "Toys", "Post", "IceCream", "Boba", "Candy",
}

function CityInteriors.Info(kind: string): Info
	return INFO[kind] or INFO.Grocery
end

-- Enseigne (texte anglais d'une boutique existante) -> métier
local KEYWORDS = {
	{ "Café", "Cafe" }, { "Cafe", "Cafe" }, { "Mochi", "Cafe" }, { "Tea", "Cafe" }, { "Gelato", "IceCream" }, { "Ice", "IceCream" },
	{ "Arcade", "Arcade" }, { "Bakery", "Bakery" }, { "Petal", "Florist" }, { "Florist", "Florist" }, { "Boba", "Boba" },
	{ "Story", "Books" }, { "Book", "Books" }, { "Plush", "Toys" }, { "Toy", "Toys" }, { "Cinema", "Cinema" }, { "Pizza", "Pizza" },
	{ "Vinyl", "Music" }, { "Candy", "Candy" }, { "Gym", "Gym" }, { "Pharmacy", "Pharmacy" }, { "Hair", "Barber" },
	{ "Chocol", "Chocolate" }, { "Cheese", "Grocery" }, { "Grocery", "Grocery" }, { "Stationery", "Books" }, { "Optician", "Optician" },
	{ "Bike", "Bike" }, { "Laundromat", "Laundry" }, { "Hat", "Fashion" }, { "Haberdashery", "Fashion" }, { "Watch", "Optician" },
}
function CityInteriors.ForShop(text: string): string
	for _, kv in ipairs(KEYWORDS) do
		if string.find(text, kv[1], 1, true) then
			return kv[2]
		end
	end
	return "Grocery"
end

----------------------------------------------------------------------
-- Coque : sol fini, murs latéraux + du fond, plafond (solides)
----------------------------------------------------------------------

function CityInteriors.Shell(m: Instance, F: CFrame, w: number, d: number, h: number, kind: string, opts: { [string]: any }?)
	local info = CityInteriors.Info(kind)
	local o = opts or {}
	local hw = w / 2
	local t = 0.35
	if o.Floor ~= false then
		Box(m, "InFloor", F, -hw + 0.02, hw - 0.02, -0.4, 0, 0.02, d - 0.02, info.Floor, info.FloorMat, true)
	end
	-- murs (dans l'emprise : face extérieure 0,02 en retrait des bords)
	Box(m, "InWall", F, -hw + 0.02, hw - 0.02, 0, h, d - t - 0.02, d - 0.02, info.Wall, M.SmoothPlastic, true)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx * (hw - 0.02), sx * (hw - 0.02 - t)
		Box(m, "InWall", F, math.min(a, b), math.max(a, b), 0, h, 0.4, d - t - 0.02, info.Wall, M.SmoothPlastic, true)
	end
	-- plafond + plinthes
	Box(m, "InCeiling", F, -hw + 0.02 + t, hw - 0.02 - t, h - 0.3, h - 0.04, 0.02, d - t - 0.02, rgb(246, 244, 240), M.SmoothPlastic)
	Box(m, "InSkirting", F, -hw + 0.4, hw - 0.4, 0, 0.45, d - t - 0.1, d - t - 0.02, info.Wall:Lerp(INK, 0.35), M.Wood)
	CityInteriors.Lamps(m, F, w, d, h, kind)
end

-- suspensions (verre "NightGlow" : allumé la nuit) sous un plafond à h
function CityInteriors.Lamps(m: Instance, F: CFrame, w: number, d: number, h: number, kind: string)
	local info = CityInteriors.Info(kind)
	local hw = w / 2
	local n = math.max(1, math.floor(w / 9))
	for i = 1, n do
		local x = -hw + (i - 0.5) * w / n
		for _, z in ipairs({ d * 0.35, d * 0.72 }) do
			Column(m, "InLampCord", F, x, z, h - 1.6, h - 0.3, 0.06, INK, M.SmoothPlastic)
			local shade = CityKit.Part(m, "InLampShade", Vector3.new(0.9, 1.4, 1.4), F * CFrame.new(x, h - 1.75, z) * CityKit.UPRIGHT, info.Sign:Lerp(INK, 0.2), M.Metal, "Cyl")
			local _ = shade
			CityKit.Glow(CityKit.Ball(m, "InLampBulb", (F * CFrame.new(x, h - 2.3, z)).Position, 0.7, rgb(255, 236, 196), M.SmoothPlastic))
		end
	end
end

----------------------------------------------------------------------
-- Éléments de mobilier
----------------------------------------------------------------------

-- comptoir : de x0 à x1, face clients vers -Z, profondeur 1,6 à partir de z
local function counter(m: Instance, F: CFrame, x0: number, x1: number, z: number, color: Color3, top: Color3?, register: boolean?)
	Box(m, "Counter", F, x0, x1, 0, COUNTER_H - 0.2, z, z + 1.5, color, M.Wood, true)
	Box(m, "CounterKick", F, x0 + 0.1, x1 - 0.1, 0.02, 0.4, z - 0.06, z + 0.2, color:Lerp(INK, 0.4), M.SmoothPlastic)
	Box(m, "CounterTop", F, x0 - 0.12, x1 + 0.12, COUNTER_H - 0.2, COUNTER_H, z - 0.15, z + 1.62, top or rgb(236, 232, 226), M.Marble)
	if register ~= false then
		local rx = x1 - 1.2
		Box(m, "Register", F, rx - 0.55, rx + 0.55, COUNTER_H, COUNTER_H + 0.45, z + 0.45, z + 1.2, rgb(60, 64, 74), M.SmoothPlastic)
		local scr = Box(m, "RegisterScreen", F, rx - 0.45, rx + 0.45, COUNTER_H + 0.55, COUNTER_H + 1.25, z + 0.95, z + 1.05, rgb(30, 32, 40), M.SmoothPlastic)
		CityKit.Glow(Box(m, "RegisterGlow", F, rx - 0.38, rx + 0.38, COUNTER_H + 0.62, COUNTER_H + 1.18, z + 0.9, z + 0.95, rgb(120, 220, 200), M.SmoothPlastic))
		local _ = scr
		Column(m, "RegisterStem", F, rx, z + 1.0, COUNTER_H + 0.45, COUNTER_H + 0.55, 0.12, STEEL, M.Metal)
	end
end

-- étagère murale le long de x (fond) ou de z (côté), produits sur 4 niveaux
-- (repère local `S` : étagère de x0 à x1, dos à z = 0, avant vers -Z)
local function shelf(m: Instance, S: CFrame, x0: number, x1: number, seed: number, colors: { Color3 }?, frame: Color3?, levels: number?)
	local c = frame or WOOD
	local list = colors or GOODS
	local n = levels or 4
	Box(m, "ShelfBack", S, x0, x1, 0, 6.8, -0.12, 0, c:Lerp(WHITE, 0.25), M.Wood, true)
	for _, x in ipairs({ x0, x1 }) do
		Box(m, "ShelfSide", S, x - 0.1, x + 0.1, 0, 6.8, -1.3, -0.12, c, M.Wood, true)
	end
	local seg = math.max(1, math.floor((x1 - x0) / 2.2))
	for i = 0, n - 1 do
		local y = 1.5 + i * (5.0 / math.max(1, n - 1))
		if i == n - 1 then
			y = 6.5
		end
		Box(m, "ShelfBoard", S, x0 + 0.1, x1 - 0.1, y - 0.12, y, -1.25, -0.12, c, M.Wood)
		if i < n - 1 or n == 1 then
			for k = 0, seg - 1 do
				local a = x0 + 0.25 + k * (x1 - x0 - 0.5) / seg
				local b = a + (x1 - x0 - 0.5) / seg - 0.15
				local hh = 0.7 + Hash(seed + k, i) * 0.6
				local color = list[1 + math.floor(Hash(seed * 3 + k, i + 7) * #list) % #list]
				Box(m, "Goods", S, a, b, y, y + hh, -1.0, -0.3, color, M.SmoothPlastic)
			end
		end
	end
	Box(m, "ShelfBase", S, x0 + 0.1, x1 - 0.1, 0, 0.4, -1.3, -0.12, c:Lerp(INK, 0.3), M.Wood)
end

-- table + chaises (n = 2 ou 4) ; centre (x, z)
local function tableSet(m: Instance, F: CFrame, x: number, z: number, n: number, top: Color3, chair: Color3, round: boolean?)
	local T = F * CFrame.new(x, 0, z)
	if round then
		CityKit.Part(m, "TableTop", Vector3.new(0.14, 2.6, 2.6), T * CFrame.new(0, TABLE_H - 0.07, 0) * CityKit.UPRIGHT, top, M.Marble, "Cyl")
	else
		Box(m, "TableTop", T, -1.4, 1.4, TABLE_H - 0.14, TABLE_H, -1.1, 1.1, top, M.Wood)
	end
	Column(m, "TableLeg", T, 0, 0, 0, TABLE_H - 0.14, 0.25, INK, M.Metal, true)
	Column(m, "TableFoot", T, 0, 0, 0, 0.1, 1.3, INK, M.Metal)
	local dirs = n >= 4 and { 0, 1, 2, 3 } or { 0, 2 }
	for _, k in ipairs(dirs) do
		local C = T * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -2.25)
		-- chaise tournée vers la table (+Z local de C)
		Box(m, "ChairSeat", C, -1.15, 1.15, SEAT_H - 0.18, SEAT_H, -1.0, 1.0, chair, M.Wood)
		for _, sx in ipairs({ -1, 1 }) do
			Box(m, "ChairSide", C, sx * 1.0 - 0.07, sx * 1.0 + 0.07, 0, SEAT_H - 0.18, -0.9, 0.9, INK, M.Metal)
		end
		Box(m, "ChairBack", C, -1.1, 1.1, SEAT_H, 4.2, -1.0, -0.82, chair, M.Wood)
	end
end

-- vitrine réfrigérée / présentoir vitré (de x0 à x1, avant vers -Z à z)
local function glassCase(m: Instance, F: CFrame, x0: number, x1: number, z: number, body: Color3, items: { Color3 }, seed: number)
	Box(m, "CaseBody", F, x0, x1, 0, 2.4, z, z + 1.5, body, M.SmoothPlastic, true)
	local g = Box(m, "CaseGlass", F, x0 + 0.1, x1 - 0.1, 2.4, COUNTER_H + 0.3, z + 0.05, z + 0.12, rgb(210, 234, 244), M.Glass, true)
	g.Transparency = 0.6
	Box(m, "CaseTop", F, x0, x1, COUNTER_H + 0.3, COUNTER_H + 0.42, z, z + 1.5, rgb(236, 236, 236), M.Metal)
	local n = math.max(2, math.floor((x1 - x0) / 0.9))
	for k = 0, n - 1 do
		local x = x0 + 0.4 + k * (x1 - x0 - 0.8) / math.max(1, n - 1)
		local c = items[1 + (k + seed) % #items]
		CityKit.Egg(m, "CaseItem", F * CFrame.new(x, 2.68, z + 0.75), Vector3.new(0.7, 0.5, 0.7), c, M.SmoothPlastic)
	end
end

-- tableau / affiche au mur (repère S : mur à z = 0, face vers -Z)
local function picture(m: Instance, S: CFrame, x: number, y: number, ww: number, hh: number, seed: number, text: string?)
	Box(m, "PicFrame", S, x - ww / 2 - 0.15, x + ww / 2 + 0.15, y - hh / 2 - 0.15, y + hh / 2 + 0.15, -0.12, 0, rgb(70, 52, 40), M.Wood)
	local canvas = Box(m, "PicCanvas", S, x - ww / 2, x + ww / 2, y - hh / 2, y + hh / 2, -0.16, -0.12, WHITE, M.SmoothPlastic)
	local gui = CityKit.Canvas(canvas, Enum.NormalId.Front, 70, 10)
	local bg = GOODS[1 + seed % #GOODS]
	CityKit.Blob(gui, 0.5, 0.5, 1, 1, bg:Lerp(WHITE, 0.55))
	CityKit.Blob(gui, 0.3 + Hash(seed, 1) * 0.4, 0.62, 0.7, 0.36, GOODS[1 + (seed + 3) % #GOODS]:Lerp(INK, 0.1), 0.5)
	CityKit.Blob(gui, 0.25 + Hash(seed, 2) * 0.5, 0.32, 0.26, 0.26, GOODS[1 + (seed + 5) % #GOODS], 1)
	if text then
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.9, 0.3)
		l.Position = UDim2.fromScale(0.05, 0.05)
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = INK
		l.Text = text
		l.Parent = gui
	end
end

----------------------------------------------------------------------
-- PNJ (employé·e + client·e)
----------------------------------------------------------------------

local function npc(m: Instance, style: string, seed: number, cf: CFrame, anim: string, prop: string?): Model?
	local model = CityKit.Npc(m, style, seed, cf, prop, false, true)
	if model then
		if anim == "sit" then
			pcall(function()
				local NPCModels = require(game:GetService("ReplicatedStorage").Shared.NPCModels) :: any
				if NPCModels.SetSitHeight then
					NPCModels.SetSitHeight(model, SEAT_H)
				end
			end)
		end
		CityKit.Animate(model, anim, seed)
		CityKit.Idle(model, anim, seed % 17)
	end
	return model
end

----------------------------------------------------------------------
-- Agencements par métier
----------------------------------------------------------------------

type Ctx = { M: Instance, F: CFrame, W: number, D: number, H: number, Seed: number, Kind: string, Info: Info, DoorX: number, Npc: number, MaxNpc: number }

-- repères des murs : fond (dos à z = d - 0,4, avant vers -Z), côtés
local function backFrame(c: Ctx): CFrame
	return c.F * CFrame.new(0, 0, c.D - 0.4)
end
local function sideFrame(c: Ctx, sx: number): CFrame
	-- dos contre le mur latéral sx, avant vers l'intérieur ; x local = le long de z
	return c.F * CFrame.new(sx * (c.W / 2 - 0.4), 0, 0) * CFrame.Angles(0, sx * math.pi / 2, 0)
end

local function addNpc(c: Ctx, style: string, cf: CFrame, anim: string, prop: string?)
	if c.Npc >= c.MaxNpc then
		return
	end
	c.Npc += 1
	npc(c.M, style, c.Seed * 7 + c.Npc * 13, cf, anim, prop)
end

-- employé·e derrière un comptoir (au fond), qui regarde vers l'avant
local function clerkBehind(c: Ctx, x: number, z: number, style: string?, anim: string?)
	addNpc(c, style or "cashier", c.F * CFrame.new(x, 0, z), anim or "scan")
end

-- client·e debout, tourné·e vers le fond (+Z)
local function customer(c: Ctx, x: number, z: number, anim: string?, prop: string?)
	addNpc(c, "shopper", c.F * CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0), anim or "idle", prop or "bag")
end

-- côtés : étagères le long des deux murs latéraux (de z0 à z1)
local function sideShelves(c: Ctx, z0: number, z1: number, colors: { Color3 }?, frame: Color3?)
	if z1 - z0 < 2.5 then
		return
	end
	for _, sx in ipairs({ -1, 1 }) do
		local S = sideFrame(c, sx)
		-- (le battant de la porte, rabattu contre ce mur, prend les 5 premiers studs)
		local zz0 = z0
		if math.abs(c.DoorX - sx * c.W / 2) < 8 then
			zz0 = math.max(z0, 5.4)
		end
		-- x local du repère latéral : sx = -1 -> x = z ; sx = 1 -> x = -z
		local a, b = sx < 0 and zz0 or -z1, sx < 0 and z1 or -zz0
		if b - a >= 2.5 then
			shelf(c.M, S, a, b, c.Seed + sx * 5, colors, frame)
		end
	end
end

local function counterBack(c: Ctx, width: number, color: Color3?, top: Color3?, register: boolean?)
	local hw = math.min(width, c.W - 3) / 2
	local z = c.D - 4.4
	counter(c.M, c.F, -hw, hw, z, color or c.Info.Sign:Lerp(WOOD, 0.5), top, register)
	return z
end

local LAYOUTS: { [string]: (c: Ctx) -> () } = {}

-- commerce "à étagères" générique (épicerie, pharmacie, librairie...)
local function retail(c: Ctx, colors: { Color3 }?, frame: Color3?, centre: ((c: Ctx) -> ())?)
	local zc = counterBack(c, math.min(9, c.W * 0.45))
	shelf(c.M, backFrame(c), -c.W / 2 + 0.6, c.W / 2 - 0.6, c.Seed + 11, colors, frame)
	sideShelves(c, 1.8, zc - 1.2, colors, frame)
	clerkBehind(c, -1.2, c.D - 2.0)
	if centre then
		centre(c)
	elseif c.W >= 14 and c.D >= 14 then
		-- gondole centrale double face
		local G = c.F * CFrame.new(0, 0, c.D * 0.45)
		local len = math.min(c.D - 10, 8)
		Box(c.M, "Gondola", G, -0.9, 0.9, 0, 4.2, -len / 2, len / 2, frame or WOOD, M.Wood, true)
		for i = 0, 2 do
			local y = 1.5 + i * 1.3
			for _, sx in ipairs({ -1, 1 }) do
				Box(c.M, "GondolaGoods", G, sx * 0.95 - 0.35, sx * 0.95 + 0.35, y, y + 0.8, -len / 2 + 0.3, len / 2 - 0.3, (colors or GOODS)[1 + (i * 2 + (sx > 0 and 1 or 0) + c.Seed) % #(colors or GOODS)], M.SmoothPlastic)
			end
		end
	end
	customer(c, c.W * 0.22, c.D * 0.42, "idle", "bag")
end

LAYOUTS.Grocery = function(c)
	retail(c, nil, nil, function(c2)
		-- cagettes de fruits et légumes au milieu
		for i = 0, 2 do
			local z = 4 + i * 2.6
			if z < c2.D - 7 then
				local T = c2.F * CFrame.new(0, 0, z)
				Box(c2.M, "Crate", T, -2.2, 2.2, 0, 2.6, -1, 1, WOOD, M.WoodPlanks, true)
				for k = 0, 3 do
					local col = ({ rgb(220, 40, 40), rgb(250, 160, 30), rgb(120, 190, 60), rgb(250, 220, 60) })[1 + (k + i) % 4]
					CityKit.Egg(c2.M, "Produce", T * CFrame.new(-1.6 + k * 1.07, 2.75, 0), Vector3.new(1.0, 0.5, 1.6), col, M.SmoothPlastic)
				end
			end
		end
	end)
end
LAYOUTS.Pharmacy = function(c)
	retail(c, { rgb(250, 250, 250), rgb(120, 200, 140), rgb(130, 180, 240), rgb(240, 120, 130) }, rgb(236, 240, 238))
	local cross = Box(c.M, "PharmaCross", backFrame(c), -1.2, 1.2, 7.2, 9.4, -0.3, -0.2, rgb(40, 180, 90), M.SmoothPlastic)
	CityKit.Glow(cross)
end
LAYOUTS.Books = function(c)
	local cols = { rgb(150, 40, 40), rgb(40, 70, 130), rgb(40, 110, 70), rgb(200, 160, 60), rgb(110, 60, 120), rgb(220, 220, 210) }
	retail(c, cols, WOOD_DARK, function(c2)
		Box(c2.M, "BookTable", c2.F * CFrame.new(0, 0, c2.D * 0.4), -2.4, 2.4, 0, 2.9, -1.4, 1.4, WOOD_DARK, M.Wood, true)
		for k = 0, 4 do
			Box(c2.M, "BookPile", c2.F * CFrame.new(-1.9 + k * 0.95, 0, c2.D * 0.4), -0.35, 0.35, 2.9, 3.3 + Hash(c2.Seed, k) * 0.6, -0.5, 0.5, cols[1 + k % #cols], M.SmoothPlastic)
		end
	end)
end
LAYOUTS.Library = function(c)
	local cols = { rgb(140, 40, 40), rgb(40, 60, 120), rgb(40, 100, 60), rgb(190, 150, 60), rgb(100, 60, 110) }
	shelf(c.M, backFrame(c), -c.W / 2 + 0.6, c.W / 2 - 0.6, c.Seed, cols, WOOD_DARK, 5)
	sideShelves(c, 1.8, c.D - 1.4, cols, WOOD_DARK)
	-- tables de lecture + lampes vertes
	local nx = math.max(1, math.floor((c.W - 8) / 7))
	for i = 1, nx do
		local x = -c.W / 2 + 4 + (i - 0.5) * (c.W - 8) / nx
		local T = c.F * CFrame.new(x, 0, c.D * 0.5)
		Box(c.M, "ReadTable", T, -2.2, 2.2, TABLE_H - 0.14, TABLE_H, -1.2, 1.2, WOOD_DARK, M.Wood, true)
		for _, sx in ipairs({ -1, 1 }) do
			Box(c.M, "ReadLeg", T, sx * 1.9 - 0.15, sx * 1.9 + 0.15, 0, TABLE_H - 0.14, -1, 1, WOOD_DARK, M.Wood)
		end
		Column(c.M, "BankerLampStem", T, 0, 0, TABLE_H, TABLE_H + 0.9, 0.12, rgb(200, 170, 80), M.Metal)
		CityKit.Glow(CityKit.Part(c.M, "BankerLamp", Vector3.new(0.5, 0.5, 1.4), T * CFrame.new(0, TABLE_H + 1.0, 0), rgb(40, 130, 70), M.Glass))
		if i == 1 then
			addNpc(c, "elder", T * CFrame.new(0, 0, -2.0) * CFrame.Angles(0, math.pi, 0), "sit")
		end
	end
	clerkBehind(c, c.W / 2 - 4, c.D - 2.2, "salesperson", "type")
end
LAYOUTS.Florist = function(c)
	local cols = { rgb(255, 110, 160), rgb(255, 214, 96), rgb(186, 140, 255), rgb(255, 150, 110), WHITE, rgb(240, 70, 90) }
	counterBack(c, math.min(7, c.W * 0.4), WOOD)
	clerkBehind(c, 0, c.D - 2.0, "salesperson", "talk")
	-- seaux de fleurs en gradins (côtés + avant)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (c.W / 2 - 1.6)
		for k = 0, math.floor((c.D - 7) / 2.2) do
			local z = 2 + k * 2.2
			local B = c.F * CFrame.new(x, 0, z)
			Box(c.M, "Stand", B, -1, 1, 0, 1.2 + (k % 2) * 0.8, -0.9, 0.9, WOOD, M.WoodPlanks, true)
			local y = 1.2 + (k % 2) * 0.8
			Column(c.M, "Bucket", B, 0, 0, y, y + 1.0, 1.1, rgb(80, 90, 100), M.Metal)
			CityKit.Egg(c.M, "Bouquet", B * CFrame.new(0, y + 1.45, 0), Vector3.new(1.5, 1.1, 1.5), cols[1 + (k + (sx > 0 and 3 or 0) + c.Seed) % #cols], M.Grass)
		end
	end
	customer(c, 1.5, c.D * 0.45, "talk", "none")
end
LAYOUTS.Bakery = function(c)
	local z = c.D - 4.6
	glassCase(c.M, c.F, -c.W / 2 + 1.5, c.W / 2 - 1.5, z, rgb(170, 120, 80), { rgb(214, 160, 90), rgb(196, 130, 70), rgb(240, 200, 120), rgb(160, 90, 60) }, c.Seed)
	-- paniers à pain sur le mur du fond (étagères en bois)
	shelf(c.M, backFrame(c), -c.W / 2 + 0.6, c.W / 2 - 0.6, c.Seed, { rgb(214, 160, 90), rgb(190, 130, 70), rgb(230, 190, 120) }, WOOD, 3)
	clerkBehind(c, 0, c.D - 2.0, "baker", "scan")
	customer(c, -1.5, c.D - 7, "talk", "bag")
	picture(c.M, sideFrame(c, -1), c.D * 0.4, 5.2, 3.5, 2.4, c.Seed, "🥐")
end
LAYOUTS.Chocolate = function(c)
	glassCase(c.M, c.F, -c.W / 2 + 2, c.W / 2 - 2, c.D - 4.6, rgb(90, 56, 40), { rgb(90, 50, 30), rgb(130, 80, 50), rgb(200, 160, 120), rgb(240, 220, 200) }, c.Seed)
	shelf(c.M, backFrame(c), -c.W / 2 + 0.6, c.W / 2 - 0.6, c.Seed, { rgb(200, 40, 60), rgb(240, 200, 80), rgb(120, 70, 40) }, WOOD_DARK)
	clerkBehind(c, 0, c.D - 2.0, "salesperson", "talk")
	customer(c, 1.0, c.D - 7, "idle", "bag")
end
local function eatery(c: Ctx, top: Color3, chair: Color3, round: boolean, staff: string)
	counterBack(c, math.min(10, c.W * 0.5), c.Info.Sign:Lerp(WOOD, 0.5))
	shelf(c.M, backFrame(c), -c.W / 2 + 0.6, c.W / 2 - 0.6, c.Seed, { rgb(240, 240, 230), rgb(200, 120, 70), rgb(90, 160, 200) }, WOOD_DARK, 3)
	clerkBehind(c, 0.8, c.D - 2.0, staff, "talk")
	-- tables (allée libre devant la porte)
	local cols = math.max(1, math.floor((c.W - 4) / 7.5))
	local rows = math.max(1, math.floor((c.D - 10) / 7))
	local seated = false
	for i = 1, cols do
		for j = 1, rows do
			local x = -c.W / 2 + 2 + (i - 0.5) * (c.W - 4) / cols
			local z = 4.2 + (j - 1) * 7
			if math.abs(x - c.DoorX) > 3.4 or z > 7 then
				tableSet(c.M, c.F, x, z, (c.W > 16) and 4 or 2, top, chair, round)
				if not seated then
					seated = true
					-- client·e assis·e (chaise côté avant : regarde la table, +Z)
					addNpc(c, "pedestrian", c.F * CFrame.new(x, 0, z - 2.25) * CFrame.Angles(0, math.pi, 0), "sit", "coffee")
				end
			end
		end
	end
end
LAYOUTS.Cafe = function(c)
	eatery(c, rgb(240, 236, 228), WOOD, true, "cashier")
	-- machine à café sur le comptoir
	local z = c.D - 4.4
	Box(c.M, "CoffeeMachine", c.F, -2.6, -0.9, COUNTER_H, COUNTER_H + 1.6, z + 0.3, z + 1.4, rgb(170, 30, 40), M.Metal)
	local board = Box(c.M, "MenuBoard", backFrame(c), -2.5, 2.5, 7.0, 9.0, -0.3, -0.2, INK, M.SmoothPlastic)
	CityKit.Text(board, Enum.NormalId.Front, "☕ 2 · 🥐 1 · 🧁 2", WHITE, INK, Enum.Font.FredokaOne, 60, 24)
end
LAYOUTS.Restaurant = function(c)
	eatery(c, WHITE, rgb(150, 40, 50), false, "salesperson")
	picture(c.M, sideFrame(c, 1), -c.D * 0.5, 5.6, 4, 2.8, c.Seed + 2)
end
LAYOUTS.Pizza = function(c)
	eatery(c, rgb(220, 60, 60), WOOD, false, "baker")
	-- four à bois au fond
	local B = backFrame(c)
	Box(c.M, "OvenBase", B, c.W / 2 - 5.6, c.W / 2 - 1.2, 0, 2.6, -3.2, -0.05, rgb(170, 90, 60), M.Brick, true)
	CityKit.Egg(c.M, "OvenDome", B * CFrame.new(c.W / 2 - 3.4, 2.6, -1.6), Vector3.new(4.2, 3.6, 3.0), rgb(180, 96, 64), M.Brick)
	CityKit.Glow(Box(c.M, "OvenFire", B, c.W / 2 - 4.0, c.W / 2 - 2.8, 2.7, 3.5, -3.15, -3.08, rgb(255, 150, 60), M.SmoothPlastic))
end
LAYOUTS.Sushi = function(c)
	-- comptoir en L avec tabourets + tapis roulant
	local z = c.D - 6
	counter(c.M, c.F, -c.W / 2 + 1.5, c.W / 2 - 1.5, z, rgb(170, 130, 90), rgb(220, 200, 170), false)
	Box(c.M, "Conveyor", c.F, -c.W / 2 + 1.7, c.W / 2 - 1.7, COUNTER_H, COUNTER_H + 0.12, z + 0.5, z + 1.2, rgb(200, 200, 206), M.Metal)
	for k = 0, math.floor((c.W - 4) / 1.6) - 1 do
		local x = -c.W / 2 + 2.2 + k * 1.6
		CityKit.Part(c.M, "SushiPlate", Vector3.new(0.1, 0.9, 0.9), c.F * CFrame.new(x, COUNTER_H + 0.17, z + 0.85) * CityKit.UPRIGHT, GOODS[1 + k % #GOODS], M.SmoothPlastic, "Cyl")
	end
	for k = 0, math.floor((c.W - 4) / 3) - 1 do
		local x = -c.W / 2 + 3 + k * 3
		Column(c.M, "StoolLeg", c.F, x, z - 1.3, 0, 2.7, 0.25, INK, M.Metal)
		Column(c.M, "StoolSeat", c.F, x, z - 1.3, 2.7, 2.9, 1.4, rgb(150, 40, 40), M.Fabric)
	end
	clerkBehind(c, 0, c.D - 3.4, "baker", "scan")
	local lanterns = { rgb(230, 60, 50), rgb(250, 240, 220) }
	for i, x in ipairs({ -c.W / 4, c.W / 4 }) do
		CityKit.Glow(CityKit.Egg(c.M, "Lantern", c.F * CFrame.new(x, c.H - 2.2, c.D * 0.4), Vector3.new(1.4, 1.8, 1.4), lanterns[i], M.Fabric))
	end
end
LAYOUTS.IceCream = function(c)
	glassCase(c.M, c.F, -c.W / 2 + 2, c.W / 2 - 2, c.D - 4.6, rgb(120, 210, 190), { rgb(255, 180, 200), rgb(255, 240, 200), rgb(140, 90, 60), rgb(160, 230, 160), rgb(250, 220, 90) }, c.Seed)
	clerkBehind(c, 0, c.D - 2.0, "cashier", "scan")
	tableSet(c.M, c.F, -c.W / 2 + 4, 4.5, 2, rgb(255, 210, 230), rgb(120, 210, 190), true)
	customer(c, 2, c.D - 7, "talk", "none")
end
LAYOUTS.Boba = function(c)
	counterBack(c, math.min(10, c.W * 0.5), rgb(170, 120, 90))
	for k = 0, 3 do
		Column(c.M, "TeaJar", c.F, -3 + k * 1.6, c.D - 1.4, COUNTER_H - 0.2, COUNTER_H + 1.6, 1.0, ({ rgb(150, 90, 60), rgb(240, 200, 220), rgb(160, 220, 160), rgb(250, 220, 120) })[k + 1], M.Glass, true)
	end
	clerkBehind(c, 2.5, c.D - 2.2, "cashier", "scan")
	tableSet(c.M, c.F, -c.W / 2 + 4, 4.5, 2, rgb(240, 230, 210), rgb(170, 120, 90), true)
	customer(c, 1.5, c.D - 7, "idle", "coffee")
end
LAYOUTS.Candy = function(c)
	local cols = { rgb(255, 110, 170), rgb(255, 230, 90), rgb(120, 220, 255), rgb(170, 255, 160), rgb(220, 150, 255) }
	retail(c, cols, rgb(255, 255, 255), function(c2)
		for k = 0, 3 do
			local z = 4 + k * 2.2
			if z < c2.D - 7 then
				Column(c2.M, "CandyJar", c2.F, -1.2 + (k % 2) * 2.4, z, 0, 3.6, 1.6, cols[1 + k % #cols], M.Glass, true)
			end
		end
	end)
end
LAYOUTS.Toys = function(c)
	local cols = { rgb(255, 160, 90), rgb(120, 200, 255), rgb(250, 220, 90), rgb(240, 120, 160), rgb(140, 220, 140) }
	retail(c, cols, rgb(255, 255, 255), function(c2)
		CityKit.Egg(c2.M, "GiantBear", c2.F * CFrame.new(0, 2.2, c2.D * 0.45), Vector3.new(3.4, 4.4, 3), rgb(190, 130, 80), M.Fabric)
		CityKit.Egg(c2.M, "GiantBearHead", c2.F * CFrame.new(0, 5.2, c2.D * 0.45), Vector3.new(2.6, 2.4, 2.4), rgb(200, 140, 90), M.Fabric)
	end)
end
LAYOUTS.Music = function(c)
	retail(c, { INK, rgb(60, 60, 70), rgb(240, 90, 90), rgb(90, 200, 220) }, INK, function(c2)
		for _, sx in ipairs({ -1, 1 }) do
			local B = c2.F * CFrame.new(sx * 2.2, 0, c2.D * 0.45)
			Box(c2.M, "VinylBin", B, -1.2, 1.2, 0, 2.6, -2.5, 2.5, WOOD_DARK, M.Wood, true)
			for k = 0, 6 do
				Box(c2.M, "Vinyl", B, -1.0, 1.0, 2.6, 3.7, -2.2 + k * 0.7, -2.1 + k * 0.7, GOODS[1 + (k + (sx > 0 and 4 or 0)) % #GOODS], M.SmoothPlastic)
			end
		end
	end)
end
LAYOUTS.Optician = function(c)
	retail(c, { INK, rgb(140, 100, 60), rgb(200, 60, 60), rgb(60, 90, 160) }, WHITE, function(c2)
		local mirror = Box(c2.M, "Mirror", sideFrame(c2, 1), -c2.D * 0.55, -c2.D * 0.35, 2.5, 7.5, -0.2, -0.12, rgb(200, 220, 230), M.Glass)
		mirror.Reflectance = 0.35
	end)
end
LAYOUTS.Fashion = function(c)
	counterBack(c, 6, INK)
	clerkBehind(c, 0, c.D - 2.0, "salesperson", "talk")
	-- portants de vêtements + mannequins
	for _, sx in ipairs({ -1, 1 }) do
		local R = c.F * CFrame.new(sx * (c.W / 2 - 2.2), 0, c.D * 0.45)
		local len = math.max(3, c.D - 10)
		for _, zz in ipairs({ -len / 2, len / 2 }) do
			Column(c.M, "RackPost", R, 0, zz, 0, 5.6, 0.18, STEEL, M.Metal)
		end
		Box(c.M, "RackBar", R, -0.09, 0.09, 5.5, 5.68, -len / 2, len / 2, STEEL, M.Metal)
		local n = math.floor(len / 0.6)
		for k = 0, n - 1 do
			Box(c.M, "Garment", R, -0.8, 0.8, 2.6, 5.4, -len / 2 + 0.2 + k * 0.6, -len / 2 + 0.38 + k * 0.6, GOODS[1 + (k + c.Seed) % #GOODS], M.Fabric)
		end
	end
	for _, x in ipairs({ -1.8, 1.8 }) do
		local T = c.F * CFrame.new(x, 0, 2.2)
		Column(c.M, "MannequinStand", T, 0, 0, 0, 2.6, 0.2, STEEL, M.Metal)
		CityKit.Egg(c.M, "MannequinBody", T * CFrame.new(0, 4.1, 0), Vector3.new(1.8, 3.0, 1.1), GOODS[1 + (c.Seed + math.floor(x)) % #GOODS], M.Fabric)
		CityKit.Ball(c.M, "MannequinHead", (T * CFrame.new(0, 6.0, 0)).Position, 0.9, rgb(240, 236, 230), M.SmoothPlastic)
	end
	customer(c, 0, c.D * 0.5, "idle", "bag")
end
LAYOUTS.Bike = function(c)
	counterBack(c, 6, rgb(60, 66, 80))
	clerkBehind(c, 0, c.D - 2.0, "worker", "type")
	-- vélos alignés (cadre en V, deux roues)
	local n = math.max(2, math.floor((c.D - 8) / 2.4))
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, n - 1 do
			local B = c.F * CFrame.new(sx * (c.W / 2 - 2.4), 0, 2.2 + k * 2.4) * CFrame.Angles(0, math.pi / 2, 0)
			local col = GOODS[1 + (k * 2 + (sx > 0 and 1 or 0) + c.Seed) % #GOODS]
			for _, wx in ipairs({ -1.3, 1.3 }) do
				CityKit.Part(c.M, "BikeWheel", Vector3.new(0.12, 2.0, 2.0), B * CFrame.new(wx, 1.0, 0), INK, M.Rubber, "Cyl")
			end
			CityKit.Beam(c.M, "BikeFrame", (B * CFrame.new(-1.3, 1.0, 0)).Position, (B * CFrame.new(0, 2.1, 0)).Position, 0.15, 0.15, col, M.Metal)
			CityKit.Beam(c.M, "BikeFrame", (B * CFrame.new(1.3, 1.0, 0)).Position, (B * CFrame.new(0, 2.1, 0)).Position, 0.15, 0.15, col, M.Metal)
			CityKit.Beam(c.M, "BikeBar", (B * CFrame.new(0, 2.1, 0)).Position, (B * CFrame.new(1.1, 2.6, 0)).Position, 0.12, 0.12, col, M.Metal)
		end
	end
end
LAYOUTS.Barber = function(c)
	-- fauteuils face aux miroirs (mur latéral droit), bancs d'attente à gauche
	local n = math.max(1, math.floor((c.D - 6) / 4.2))
	local S = sideFrame(c, 1)
	for k = 0, n - 1 do
		local z = 2.8 + k * 4.2
		local mirror = Box(c.M, "Mirror", S, -z - 1.3, -z + 1.3, 3.2, 7.4, -0.2, -0.12, rgb(200, 220, 230), M.Glass)
		mirror.Reflectance = 0.35
		Box(c.M, "BarberShelf", S, -z - 1.4, -z + 1.4, 3.0, 3.15, -1.0, -0.12, WHITE, M.Marble)
		-- fauteuil (tourné vers le miroir)
		local C = c.F * CFrame.new(c.W / 2 - 3.6, 0, z) * CFrame.Angles(0, -math.pi / 2, 0)
		Column(c.M, "BarberBase", C, 0, 0, 0, 1.2, 1.4, STEEL, M.Metal, true)
		Box(c.M, "BarberSeat", C, -1.1, 1.1, 1.2, SEAT_H, -1.0, 1.0, rgb(150, 30, 40), M.Fabric)
		Box(c.M, "BarberBack", C, -1.1, 1.1, SEAT_H, 4.6, 0.8, 1.05, rgb(150, 30, 40), M.Fabric)
		if k == 0 then
			addNpc(c, "pedestrian", C * CFrame.Angles(0, math.pi, 0), "sit")
			addNpc(c, "salesperson", C * CFrame.new(-1.6, 0, -0.4) * CFrame.Angles(0, -math.pi / 2, 0), "scan")
		end
	end
	local W = sideFrame(c, -1)
	Box(c.M, "WaitBench", W, 2, math.max(4, c.D - 6), 0, SEAT_H, -2.2, -0.2, rgb(60, 60, 66), M.Fabric, true)
	-- enseigne tournante (poteau de barbier) près de la porte
	local pole = CityKit.Part(c.M, "BarberPole", Vector3.new(3, 0.7, 0.7), c.F * CFrame.new(-c.W / 2 + 1.2, 4.5, 0.8) * CityKit.UPRIGHT, WHITE, M.SmoothPlastic, "Cyl")
	CityKit.Text(pole, Enum.NormalId.Top, "💈", rgb(220, 40, 50), nil, nil, 40, 20)
end
LAYOUTS.Laundry = function(c)
	-- machines à laver en rang (hublot), table à plier, chaises
	local B = backFrame(c)
	local n = math.max(2, math.floor((c.W - 3) / 2.6))
	for k = 0, n - 1 do
		local x = -c.W / 2 + 1.5 + (k + 0.5) * (c.W - 3) / n
		Box(c.M, "Washer", B, x - 1.15, x + 1.15, 0, 3.2, -2.4, -0.05, WHITE, M.SmoothPlastic, true)
		local door = CityKit.Part(c.M, "WasherDoor", Vector3.new(0.12, 1.5, 1.5), B * CFrame.new(x, 1.7, -2.45) * CFrame.Angles(0, math.pi / 2, 0), rgb(150, 190, 220), M.Glass, "Cyl")
		door.Transparency = 0.2
		Box(c.M, "WasherPanel", B, x - 1.0, x + 1.0, 2.75, 3.1, -2.48, -2.4, rgb(200, 204, 210), M.SmoothPlastic)
	end
	Box(c.M, "FoldTable", c.F * CFrame.new(0, 0, c.D * 0.42), -2.6, 2.6, 0, TABLE_H, -1.1, 1.1, rgb(220, 224, 230), M.SmoothPlastic, true)
	local W = sideFrame(c, -1)
	Box(c.M, "WaitBench", W, 2, math.max(4, c.D - 6), 0, SEAT_H, -2.2, -0.2, rgb(60, 120, 170), M.SmoothPlastic, true)
	addNpc(c, "pedestrian", c.F * CFrame.new(-c.W / 2 + 1.7, 0, c.D * 0.4) * CFrame.Angles(0, math.pi / 2, 0), "sit", "phone")
	customer(c, 1.2, c.D * 0.42 - 1.8, "idle", "none")
end
LAYOUTS.Gym = function(c)
	-- tapis de course face à la vitrine, haltères, miroir
	local n = math.max(1, math.floor((c.W - 4) / 3.6))
	for k = 0, n - 1 do
		local x = -c.W / 2 + 2 + (k + 0.5) * (c.W - 4) / n
		local T = c.F * CFrame.new(x, 0, 4.5) * CFrame.Angles(0, math.pi, 0)
		Box(c.M, "TreadBelt", T, -1.0, 1.0, 0, 0.7, -2.6, 2.6, INK, M.Rubber, true)
		for _, sx in ipairs({ -1, 1 }) do
			Box(c.M, "TreadArm", T, sx * 1.05 - 0.1, sx * 1.05 + 0.1, 0.7, 4.6, -2.6, -2.3, STEEL, M.Metal)
		end
		CityKit.Glow(Box(c.M, "TreadConsole", T, -1.1, 1.1, 4.4, 5.1, -2.7, -2.3, rgb(40, 200, 240), M.SmoothPlastic))
		if k == 0 then
			addNpc(c, "jogger", T * CFrame.new(0, 0.7, 0), "walk")
		end
	end
	local mirror = Box(c.M, "Mirror", backFrame(c), -c.W / 2 + 1, c.W / 2 - 1, 1, 8, -0.2, -0.12, rgb(200, 220, 230), M.Glass)
	mirror.Reflectance = 0.35
	local R = backFrame(c) * CFrame.new(0, 0, -2)
	Box(c.M, "DumbbellRack", R, -4, 4, 0, 2.4, -0.8, 0.8, INK, M.Metal, true)
	for k = 0, 7 do
		CityKit.Part(c.M, "Dumbbell", Vector3.new(0.9, 0.5, 0.5), R * CFrame.new(-3.5 + k, 2.65, 0), GOODS[1 + k % #GOODS], M.Rubber, "Cyl")
	end
end
LAYOUTS.Post = function(c)
	-- guichets vitrés, présentoir de colis, boîte aux lettres
	local z = c.D - 4.4
	counter(c.M, c.F, -c.W / 2 + 1.5, c.W / 2 - 1.5, z, rgb(250, 196, 30), rgb(240, 240, 236), true)
	local n = math.max(2, math.floor((c.W - 3) / 5))
	for k = 0, n do
		local x = -c.W / 2 + 1.5 + k * (c.W - 3) / n
		Box(c.M, "Guichet", c.F, x - 0.08, x + 0.08, COUNTER_H, 7.5, z - 0.05, z + 0.12, rgb(40, 60, 120), M.Metal)
	end
	local g = Box(c.M, "GuichetGlass", c.F, -c.W / 2 + 1.6, c.W / 2 - 1.6, COUNTER_H + 1.2, 7.4, z + 0.02, z + 0.08, rgb(210, 230, 240), M.Glass)
	g.Transparency = 0.6
	clerkBehind(c, -c.W / 4, c.D - 2.2, "cashier", "type")
	shelf(c.M, sideFrame(c, -1), 2, c.D - 6, c.Seed, { rgb(200, 160, 110), rgb(180, 140, 100), rgb(220, 190, 150) }, rgb(40, 60, 120), 3)
	customer(c, -c.W / 4, z - 2.2, "talk", "bag")
	Column(c.M, "QueuePost", c.F, 1, z - 4, 0, 3.4, 0.25, STEEL, M.Metal)
	Column(c.M, "QueuePost", c.F, 4, z - 4, 0, 3.4, 0.25, STEEL, M.Metal)
	Box(c.M, "QueueBelt", c.F, 1, 4, 3.0, 3.25, z - 4.05, z - 3.95, rgb(40, 60, 140), M.Fabric)
end
LAYOUTS.Clinic = function(c)
	local z = counterBack(c, 8, WHITE, rgb(150, 210, 230))
	clerkBehind(c, -1.2, c.D - 2.0, "salesperson", "type")
	-- salle d'attente (sièges en rang), plante, écran
	local W = sideFrame(c, -1)
	local n = math.max(2, math.floor((z - 3) / 2.8))
	for k = 0, n - 1 do
		local x = 2 + k * 2.8
		Box(c.M, "WaitSeat", W, x, x + 2.5, SEAT_H - 0.2, SEAT_H, -2.4, -0.3, rgb(60, 160, 190), M.SmoothPlastic, true)
		Box(c.M, "WaitBack", W, x, x + 2.5, SEAT_H, 4.0, -0.5, -0.3, rgb(60, 160, 190), M.SmoothPlastic)
		Box(c.M, "WaitLeg", W, x + 1.1, x + 1.4, 0, SEAT_H - 0.2, -1.6, -1.2, STEEL, M.Metal)
	end
	addNpc(c, "elder", c.F * CFrame.new(-c.W / 2 + 1.75, 0, 3.25) * CFrame.Angles(0, math.pi / 2, 0), "sit")
	local cross = Box(c.M, "ClinicCross", backFrame(c), -1.0, 1.0, 7.0, 9.0, -0.3, -0.2, rgb(220, 60, 70), M.SmoothPlastic)
	CityKit.Glow(cross)
	Column(c.M, "PlantPot", c.F, c.W / 2 - 1.6, 2, 0, 1.6, 1.4, WHITE, M.SmoothPlastic)
	CityKit.Egg(c.M, "Plant", c.F * CFrame.new(c.W / 2 - 1.6, 2.8, 2), Vector3.new(2, 2.8, 2), rgb(70, 140, 70), M.Grass)
end
LAYOUTS.Police = function(c)
	local z = counterBack(c, math.min(12, c.W - 4), rgb(30, 60, 140), rgb(230, 232, 236))
	clerkBehind(c, -2, c.D - 2.0, "worker", "type")
	-- bureaux avec écrans, tableau de liège, banc d'attente
	for _, x in ipairs({ -c.W / 4, c.W / 4 }) do
		local T = c.F * CFrame.new(x, 0, z - 4)
		Box(c.M, "Desk", T, -2, 2, TABLE_H - 0.14, TABLE_H, -1, 1, rgb(200, 204, 210), M.SmoothPlastic, true)
		Box(c.M, "DeskSide", T, -2, -1.7, 0, TABLE_H - 0.14, -1, 1, rgb(170, 176, 184), M.SmoothPlastic)
		Box(c.M, "Monitor", T, -0.9, 0.9, TABLE_H + 0.3, TABLE_H + 1.5, 0.3, 0.4, INK, M.SmoothPlastic)
		CityKit.Glow(Box(c.M, "MonitorGlow", T, -0.8, 0.8, TABLE_H + 0.38, TABLE_H + 1.42, 0.25, 0.3, rgb(120, 180, 240), M.SmoothPlastic))
	end
	local board = Box(c.M, "CorkBoard", sideFrame(c, 1), -c.D * 0.6, -c.D * 0.25, 4, 7.5, -0.2, -0.1, rgb(190, 150, 100), M.Wood)
	local _ = board
	for k = 0, 5 do
		Box(c.M, "Note", sideFrame(c, 1), -c.D * 0.58 + k * 0.9, -c.D * 0.58 + k * 0.9 + 0.7, 5 + (k % 2) * 1.2, 5.9 + (k % 2) * 1.2, -0.24, -0.2, GOODS[1 + k % #GOODS]:Lerp(WHITE, 0.5), M.SmoothPlastic)
	end
	Box(c.M, "WaitBench", sideFrame(c, -1), 2, math.max(4, z - 2), 0, SEAT_H, -2.2, -0.2, rgb(60, 70, 90), M.Wood, true)
end
LAYOUTS.Office = function(c)
	local z = counterBack(c, math.min(10, c.W - 4), rgb(60, 66, 80), rgb(236, 236, 236), false)
	clerkBehind(c, 0, c.D - 2.0, "salesperson", "type")
	local logo = Box(c.M, "LobbyLogo", backFrame(c), -3.5, 3.5, 6.6, 8.6, -0.3, -0.2, rgb(40, 120, 200), M.SmoothPlastic)
	CityKit.Text(logo, Enum.NormalId.Front, "🧠 Dopa Corp", WHITE, nil, Enum.Font.GothamBlack, 60, 24)
	-- canapés d'accueil + plantes
	for _, sx in ipairs({ -1, 1 }) do
		local S = c.F * CFrame.new(sx * (c.W / 2 - 2), 0, z * 0.5) * CFrame.Angles(0, sx * math.pi / 2, 0)
		Box(c.M, "SofaBase", S, -2.8, 2.8, 0, 1.6, -1.3, 1.3, rgb(60, 64, 76), M.Fabric, true)
		Box(c.M, "SofaCushion", S, -2.7, 2.7, 1.6, 1.8, -1.2, 1.1, rgb(90, 96, 112), M.Fabric)
		Box(c.M, "SofaBack", S, -2.8, 2.8, 1.6, 3.9, 0.9, 1.3, rgb(60, 64, 76), M.Fabric)
		Column(c.M, "PlantPot", c.F, sx * (c.W / 2 - 1.5), 1.5, 0, 1.8, 1.4, WHITE, M.SmoothPlastic)
		CityKit.Egg(c.M, "Plant", c.F * CFrame.new(sx * (c.W / 2 - 1.5), 3.2, 1.5), Vector3.new(2, 3.2, 2), rgb(70, 140, 70), M.Grass)
	end
	customer(c, 2.5, z - 2, "talk", "phone")
end
LAYOUTS.Hotel = function(c)
	local z = counterBack(c, math.min(10, c.W - 4), rgb(110, 70, 40), rgb(236, 226, 206))
	clerkBehind(c, -1.5, c.D - 2.0, "salesperson", "type")
	-- clés au mur, tapis, fauteuils, lustre
	local B = backFrame(c)
	for k = 0, 9 do
		local x = 1 + (k % 5) * 0.8
		local y = 5.2 + math.floor(k / 5) * 0.9
		Box(c.M, "KeyHook", B, x - 0.2, x + 0.2, y - 0.3, y + 0.3, -0.2, -0.1, rgb(200, 170, 80), M.Metal)
	end
	Box(c.M, "Rug", c.F, -3, 3, 0, 0.04, 2, z - 1.2, rgb(150, 40, 50), M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		local A = c.F * CFrame.new(sx * (c.W / 2 - 2.4), 0, z * 0.45) * CFrame.Angles(0, sx * math.pi / 2, 0)
		Box(c.M, "Armchair", A, -1.4, 1.4, 0, SEAT_H, -1.3, 1.3, rgb(170, 130, 70), M.Fabric, true)
		Box(c.M, "ArmchairBack", A, -1.4, 1.4, SEAT_H, 4.0, 0.9, 1.3, rgb(170, 130, 70), M.Fabric)
	end
	CityKit.Glow(CityKit.Egg(c.M, "Chandelier", c.F * CFrame.new(0, c.H - 1.6, z * 0.5), Vector3.new(2.6, 1.4, 2.6), rgb(255, 230, 170), M.Glass))
	customer(c, 1.5, z - 2, "talk", "bag")
end
LAYOUTS.Museum = function(c)
	-- statue sur socle au centre, tableaux, cordons
	local P = c.F * CFrame.new(0, 0, c.D * 0.5)
	Box(c.M, "Plinth", P, -1.4, 1.4, 0, 2.6, -1.4, 1.4, rgb(236, 232, 226), M.Marble, true)
	CityKit.Egg(c.M, "StatueBody", P * CFrame.new(0, 4.6, 0), Vector3.new(1.6, 3.6, 1.2), rgb(214, 206, 196), M.Marble)
	CityKit.Ball(c.M, "StatueHead", (P * CFrame.new(0, 7.0, 0)).Position, 1.1, rgb(214, 206, 196), M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		local S = sideFrame(c, sx)
		local n = math.max(1, math.floor((c.D - 4) / 6))
		for k = 0, n - 1 do
			local zz = 3 + (k + 0.5) * (c.D - 6) / n
			picture(c.M, S, sx < 0 and zz or -zz, 5.4, 3.6, 2.8, c.Seed + k * 3 + (sx > 0 and 1 or 0))
		end
		for _, zz in ipairs({ 3, c.D - 3 }) do
			Column(c.M, "RopePost", c.F, sx * (c.W / 2 - 2.6), zz, 0, 3.2, 0.3, rgb(200, 170, 80), M.Metal)
		end
		Box(c.M, "Rope", c.F, sx * (c.W / 2 - 2.6) - 0.08, sx * (c.W / 2 - 2.6) + 0.08, 2.8, 2.96, 3, c.D - 3, rgb(150, 30, 40), M.Fabric)
	end
	addNpc(c, "shopper", c.F * CFrame.new(-c.W / 2 + 4, 0, c.D * 0.5) * CFrame.Angles(0, math.pi / 2, 0), "idle", "none")
	addNpc(c, "elder", c.F * CFrame.new(2.4, 0, c.D * 0.5 - 2.6) * CFrame.Angles(0, math.rad(150), 0), "talk", "cane")
end
LAYOUTS.Cinema = function(c)
	-- hall : caisse, machine à pop-corn, affiches lumineuses
	local z = counterBack(c, math.min(10, c.W - 4), rgb(150, 30, 40), rgb(250, 220, 120))
	clerkBehind(c, -1.5, c.D - 2.0, "cashier", "scan")
	local P = c.F * CFrame.new(c.W / 2 - 3, 0, z - 2.5)
	Box(c.M, "PopcornCart", P, -1.2, 1.2, 0, 3.2, -1, 1, rgb(220, 40, 40), M.SmoothPlastic, true)
	local glass = Box(c.M, "PopcornGlass", P, -1.1, 1.1, 3.2, 5.6, -0.9, 0.9, rgb(255, 250, 220), M.Glass)
	glass.Transparency = 0.3
	CityKit.Egg(c.M, "Popcorn", P * CFrame.new(0, 3.8, 0), Vector3.new(2, 1.2, 1.6), rgb(255, 240, 180), M.Sand)
	for _, sx in ipairs({ -1, 1 }) do
		local S = sideFrame(c, sx)
		for k = 0, 1 do
			local zz = 3 + k * 5
			local frame = Box(c.M, "PosterFrame", S, (sx < 0 and zz or -zz) - 1.6, (sx < 0 and zz or -zz) + 1.6, 2.6, 7.6, -0.25, -0.1, rgb(200, 170, 80), M.Metal)
			local _ = frame
			picture(c.M, S, sx < 0 and zz or -zz, 5.1, 2.8, 4.6, c.Seed + k + (sx > 0 and 5 or 0), ({ "🦖", "🚀", "👻", "💘" })[1 + (k + (sx > 0 and 2 or 0)) % 4])
		end
	end
	customer(c, -1.5, z - 2, "talk", "none")
	customer(c, 1.0, z - 3.5, "idle", "coffee")
end
LAYOUTS.Garage = function(c)
	-- pont élévateur (bras jaunes), mur d'outils, pneus, établi
	local L = c.F * CFrame.new(0, 0, c.D * 0.5)
	for _, sx in ipairs({ -1, 1 }) do
		Box(c.M, "LiftPost", L, sx * 4.2 - 0.5, sx * 4.2 + 0.5, 0, 9.5, -0.5, 0.5, rgb(240, 190, 40), M.Metal, true)
		Box(c.M, "LiftArm", L, sx * 4.2 - (sx > 0 and 3.0 or -0.5), sx * 4.2 + (sx > 0 and -0.5 or 3.0), 3.0, 3.35, -0.25, 0.25, rgb(240, 190, 40), M.Metal)
	end
	-- voiture levée (silhouette simple)
	Box(c.M, "CarBody", L, -2.7, 2.7, 3.4, 5.4, -4.5, 4.5, GOODS[1 + c.Seed % #GOODS], M.SmoothPlastic)
	Box(c.M, "CarCabin", L, -2.4, 2.4, 5.4, 7.2, -2.0, 2.4, rgb(150, 190, 220), M.Glass)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -3, 3 }) do
			CityKit.Part(c.M, "CarWheel", Vector3.new(0.9, 2.2, 2.2), L * CFrame.new(sx * 2.6, 3.6, sz), INK, M.Rubber, "Cyl")
		end
	end
	local B = backFrame(c)
	Box(c.M, "ToolBoard", B, -6, 6, 3.5, 8, -0.2, -0.1, rgb(80, 86, 96), M.Metal)
	for k = 0, 9 do
		Box(c.M, "Tool", B, -5.4 + k * 1.15, -5.0 + k * 1.15, 4.5 + (k % 3) * 0.8, 6.2 + (k % 3) * 0.8, -0.3, -0.2, ({ rgb(200, 40, 40), STEEL, rgb(40, 60, 160) })[1 + k % 3], M.Metal)
	end
	Box(c.M, "Workbench", B, -6, 6, 0, TABLE_H, -2.4, -0.2, rgb(150, 110, 70), M.WoodPlanks, true)
	for k = 0, 2 do
		CityKit.Part(c.M, "Tire", Vector3.new(0.9, 2.4, 2.4), c.F * CFrame.new(-c.W / 2 + 2, 0.5 + k * 0.92, 3) * CityKit.UPRIGHT, INK, M.Rubber, "Cyl")
	end
	addNpc(c, "worker", L * CFrame.new(-3.2, 0, -5.6) * CFrame.Angles(0, math.rad(200), 0), "scan")
end
LAYOUTS.School = function(c)
	-- salle de classe : tableau, bureaux d'élèves, bureau du maître
	local B = backFrame(c)
	Box(c.M, "Blackboard", B, -5, 5, 3.4, 7.8, -0.25, -0.1, rgb(36, 70, 52), M.Slate)
	local chalk = Box(c.M, "BoardText", B, -4.5, 4.5, 4.4, 7.2, -0.28, -0.25, rgb(36, 70, 52), M.SmoothPlastic)
	CityKit.Text(chalk, Enum.NormalId.Front, "2 + 2 = 🧠", WHITE, rgb(36, 70, 52), Enum.Font.PermanentMarker, 60, 20)
	local T = c.F * CFrame.new(0, 0, c.D - 4.2)
	Box(c.M, "TeacherDesk", T, -2.4, 2.4, 0, TABLE_H, -1.1, 1.1, WOOD, M.Wood, true)
	addNpc(c, "salesperson", T * CFrame.new(1.4, 0, 1.8), "talk")
	local cols = math.max(1, math.floor((c.W - 4) / 4.4))
	local rows = math.max(1, math.floor((c.D - 9) / 4))
	for i = 1, cols do
		for j = 1, rows do
			local x = -c.W / 2 + 2 + (i - 0.5) * (c.W - 4) / cols
			local z = 2.6 + (j - 1) * 4
			local D = c.F * CFrame.new(x, 0, z)
			Box(c.M, "PupilDesk", D, -1.3, 1.3, 2.6, 2.75, 0.2, 1.6, WOOD, M.Wood, true)
			Box(c.M, "PupilDeskLeg", D, -1.2, 1.2, 0, 2.6, 0.8, 1.0, STEEL, M.Metal)
			Box(c.M, "PupilChair", D, -0.9, 0.9, 1.5, 1.65, -1.1, 0.2, rgb(60, 120, 200), M.SmoothPlastic)
			Box(c.M, "PupilChairBack", D, -0.9, 0.9, 1.65, 3.2, -1.2, -1.05, rgb(60, 120, 200), M.SmoothPlastic)
		end
	end
end
LAYOUTS.Church = function(c)
	-- nef : bancs de part et d'autre de l'allée, autel, vitrail
	local B = backFrame(c)
	Box(c.M, "Altar", B, -2.5, 2.5, 0, 3.6, -3.4, -1.6, WHITE, M.Marble, true)
	Box(c.M, "AltarCloth", B, -2.6, 2.6, 3.6, 3.7, -3.5, -1.5, rgb(200, 40, 50), M.Fabric)
	for _, x in ipairs({ -1.6, 1.6 }) do
		Column(c.M, "Candle", B, x, -2.5, 3.7, 4.6, 0.25, rgb(250, 246, 230), M.SmoothPlastic)
		CityKit.Glow(CityKit.Ball(c.M, "Flame", (B * CFrame.new(x, 4.75, -2.5)).Position, 0.25, rgb(255, 200, 90), M.SmoothPlastic))
	end
	local win = Box(c.M, "StainedGlass", B, -2.5, 2.5, 5, math.min(c.H - 1.5, 11), -0.25, -0.1, rgb(80, 120, 220), M.Glass)
	local gui = CityKit.Canvas(win, Enum.NormalId.Front, 120, 8)
	for k = 0, 5 do
		CityKit.Blob(gui, 0.2 + (k % 3) * 0.3, 0.25 + math.floor(k / 3) * 0.45, 0.28, 0.4, GOODS[1 + k % #GOODS], 0.3)
	end
	local rows = math.max(2, math.floor((c.D - 8) / 3))
	for j = 0, rows - 1 do
		local z = 2.5 + j * 3
		for _, sx in ipairs({ -1, 1 }) do
			local P = c.F * CFrame.new(sx * (c.W / 4 + 0.6), 0, z)
			local half = c.W / 4 - 1.4
			Box(c.M, "PewSeat", P, -half, half, SEAT_H - 0.2, SEAT_H, -0.9, 0.9, WOOD_DARK, M.Wood, true)
			Box(c.M, "PewBack", P, -half, half, SEAT_H, 4.0, 0.75, 0.95, WOOD_DARK, M.Wood)
			for _, ex in ipairs({ -half, half }) do
				Box(c.M, "PewEnd", P, ex - 0.12, ex + 0.12, 0, 3.2, -0.9, 0.95, WOOD_DARK, M.Wood)
			end
		end
	end
	addNpc(c, "elder", c.F * CFrame.new(-(c.W / 4 + 0.6), 0, 2.5 + 0.0) * CFrame.Angles(0, math.pi, 0), "sit")
end
LAYOUTS.Fire = function(c)
	-- remise : camion rouge, échelle, casques au mur
	local T = c.F * CFrame.new(0, 0, c.D * 0.5)
	Box(c.M, "TruckBody", T, -3.2, 3.2, 1.2, 6.6, -6, 6, rgb(200, 30, 30), M.SmoothPlastic, true)
	Box(c.M, "TruckCab", T, -3.2, 3.2, 1.2, 8.2, -9, -6, rgb(210, 36, 36), M.SmoothPlastic, true)
	Box(c.M, "TruckWindshield", T, -2.9, 2.9, 5.2, 7.8, -9.06, -9.0, rgb(150, 190, 220), M.Glass)
	Box(c.M, "TruckLadder", T, -1.2, 1.2, 6.6, 7.1, -5, 6.5, STEEL, M.Metal)
	Box(c.M, "TruckStripe", T, -3.25, 3.25, 3.2, 3.6, -9.05, 6.05, WHITE, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -7.5, 2, 4.5 }) do
			CityKit.Part(c.M, "TruckWheel", Vector3.new(0.9, 2.6, 2.6), T * CFrame.new(sx * 3.0, 1.3, sz), INK, M.Rubber, "Cyl")
		end
	end
	CityKit.Glow(Box(c.M, "TruckBeacon", T, -1.6, 1.6, 8.2, 8.6, -8.4, -7.8, rgb(60, 120, 255), M.SmoothPlastic))
	local W = sideFrame(c, -1)
	for k = 0, 4 do
		local x = 2 + k * 1.6
		Box(c.M, "Hook", W, x - 0.1, x + 0.1, 6.2, 6.6, -0.5, -0.1, STEEL, M.Metal)
		CityKit.Egg(c.M, "Helmet", W * CFrame.new(x, 6.0, -0.6), Vector3.new(1.1, 0.8, 1.2), rgb(240, 200, 40), M.SmoothPlastic)
		Box(c.M, "Jacket", W, x - 0.6, x + 0.6, 2.8, 5.6, -0.6, -0.2, rgb(60, 50, 40), M.Fabric)
	end
	addNpc(c, "worker", T * CFrame.new(4.6, 0, -2) * CFrame.Angles(0, -math.pi / 2, 0), "talk")
end
LAYOUTS.Arcade = function(c)
	local n = math.max(2, math.floor((c.D - 4) / 3))
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, n - 1 do
			local A = c.F * CFrame.new(sx * (c.W / 2 - 1.6), 0, 2.4 + k * 3) * CFrame.Angles(0, sx * math.pi / 2, 0)
			Box(c.M, "Cabinet", A, -1.1, 1.1, 0, 6.6, -1.2, 1.0, GOODS[1 + (k + (sx > 0 and 3 or 0)) % #GOODS]:Lerp(INK, 0.4), M.SmoothPlastic, true)
			CityKit.Glow(Box(c.M, "CabScreen", A, -0.9, 0.9, 3.8, 5.4, -1.26, -1.2, GOODS[1 + (k + 2) % #GOODS], M.SmoothPlastic))
			Box(c.M, "CabPanel", A, -1.0, 1.0, 3.0, 3.4, -1.8, -1.2, INK, M.SmoothPlastic)
		end
	end
	customer(c, -c.W / 2 + 3.6, 3.0, "type", "none")
	counterBack(c, 6, rgb(90, 60, 150))
	clerkBehind(c, 0, c.D - 2.0, "cashier", "talk")
end

-- (métiers sans agencement dédié : commerce à étagères)
local function fallback(c: Ctx)
	retail(c)
end

function CityInteriors.Furnish(m: Instance, F: CFrame, w: number, d: number, h: number, kind: string, seed: number, opts: { [string]: any }?): number
	local o = opts or {}
	local c: Ctx = {
		M = m,
		F = F,
		W = w,
		D = d,
		H = h,
		Seed = seed,
		Kind = kind,
		Info = CityInteriors.Info(kind),
		DoorX = tonumber(o.DoorX) or 0,
		Npc = 0,
		MaxNpc = o.NoNpc and 0 or (tonumber(o.MaxNpc) or 3),
	}
	if w < 6 or d < 6 then
		return 0
	end
	local fn = LAYOUTS[kind] or fallback
	fn(c)
	return c.Npc
end

return CityInteriors
