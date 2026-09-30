--[[
	MarketCheckout (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MarketCheckout

	🛒 MégaDopa (v9.9, SHOPS99) : les CAISSES du supermarché, 20x plus
	vraies (construites et animées pour MarketInterior, qui fournit ses
	aides de construction via MarketCheckout.Init(ctx)) :
	  - 5 caisses tenues (4 ouvertes, 1 fermée avec sangle) : meuble à
	    bandeau, plan inox, TAPIS à nervures qui défilent, rouleaux, rails,
	    cellule, barre « client suivant », scanner à plat + tour (lignes
	    laser, BIP visuel), balance, pistolet, tiroir-caisse, clavier,
	    écran caisse, afficheur client, TPE sur pied, imprimante à tickets,
	    carrousel à sacs, présentoir à bonbons, lampe numérotée à LED, poste
	    caissier (tabouret assis-debout, tapis anti-fatigue, paroi givrée) ;
	  - 4 caisses automatiques : écran tactile animé (articles, total,
	    paiement), scanner, lecteur de carte, balance + potence à sac, lampe ;
	  - personnages : caissier·ère qui scanne / encaisse / salue, FILE de
	    2 à 3 clients avec panier par caisse (le client pose ses articles,
	    paie par carte, part avec ses sacs ; la file avance ; un nouveau
	    client arrive), clients aux caisses automatiques.
	Tout est déterministe (cycle de 20 s par caisse, décalé) : aucune
	création / destruction par image, seulement des CFrame et des textes.
	Aucune vraie lumière, aucun son.

	API (MarketInterior) :
	  MarketCheckout.Init(ctx)                    aides de construction
	  MarketCheckout.Lane(m, parent, i)           une caisse (niveau complet)
	  MarketCheckout.SelfCheckout(m, parent)      caisses automatiques
	  MarketCheckout.Zone(m, parent, jobs)        personnages (zone "Checkout")
	  MarketCheckout.AnimateLane(belt, now)       une caisse, ≤ 30 i/s
	  MarketCheckout.AnimateKiosk(kiosk, now)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local ShopUI = require(script.Parent.ShopUI)

local MarketCheckout = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BRAND = rgb(236, 72, 140)
local BRAND2 = rgb(120, 90, 200)
local YELLOW = rgb(255, 208, 72)
local FACE_PX = CFrame.Angles(0, -math.pi / 2, 0) -- LookVector = +X

-- aides de MarketInterior (Init)
local C: any = nil
local box: any, cyl: any, cylX: any, newPart: any, label: any, text: any, corner: any
local printLabel: any, pick: any, hash: any, actor: any, hangingSign: any, NPC: any
local PALETTE: { Color3 } = {}
local FLOOR_TOP = 0.07
local LANES: { number } = {}
local OPEN_LANES = 4

function MarketCheckout.Init(ctx: any)
	C = ctx
	box, cyl, cylX, newPart = ctx.box, ctx.cyl, ctx.cylX, ctx.newPart
	label, text, corner = ctx.label, ctx.text, ctx.corner
	printLabel, pick, hash, actor, hangingSign, NPC = ctx.printLabel, ctx.pick, ctx.hash, ctx.actor, ctx.hangingSign, ctx.NPC
	PALETTE = ctx.PALETTE
	FLOOR_TOP = ctx.FLOOR_TOP
	LANES = ctx.LANES
	OPEN_LANES = ctx.OPEN_LANES
end

----------------------------------------------------------------------
-- 🛒 CAISSES (v9.9, SHOPS99) : 5 vraies caisses (4 ouvertes) + 4 caisses
-- automatiques. Repère d'une caisse L = F * (x, 0, 0) : u (x local) vers
-- l'allée des clients (+X), z vers le fond ; le client avance vers -z.
--   meuble (plinthe, bandeau, inox), TAPIS en caoutchouc à nervures qui
--   défilent, rouleaux chromés, rails, cellule photo, barre « client
--   suivant » (posée par le client, rangée par le·la caissier·ère),
--   scanner à plat + tour (vitres, lignes laser, BIP visuel), balance,
--   pistolet-scanner, clavier, écran caisse (tickets qui défilent),
--   afficheur client (TOTAL en direct), TPE sur pied (écran qui change :
--   « approchez la carte » -> « paiement accepté »), imprimante à tickets
--   (le ticket sort), tiroir-caisse, CARROUSEL À SACS qui tourne, présentoir
--   à bonbons, lampe de caisse numérotée (LED verte / rouge), poste
--   caissier (tabouret assis-debout, tapis anti-fatigue, paroi).
-- Animation déterministe (cycle de LANE_T s, décalé par caisse) : le
-- client pose ses articles, le tapis avance, chaque article passe au
-- scanner dans la main du·de la caissier·ère puis tombe dans le sac, le
-- client paie par carte, prend ses sacs et s'en va ; la file avance.
----------------------------------------------------------------------

local LANE_T = 20
local TOP_Y = 2.62 -- dessus du plan de travail inox
local BELT_Y = 2.7 -- dessus du tapis
local BELT_Z0, BELT_Z1 = 6.3, 11
local FRONT_Z = 6.75 -- premier article en attente devant le scanner
local SCAN_Z = 5.62 -- centre de la vitre du scanner
local BAG_Z = 3.95 -- axe du carrousel à sacs
local BAG_R = 0.62 -- longueur des bras du carrousel
local BELT_RUN = 1.4 * 6.4 + 6 * 0.8 -- (distance du tapis sur un cycle)

-- Articles : forme, largeur, hauteur, profondeur, couleurs, nom, prix
local ITEM_SPECS: { { any } } = {
	{ "Box", 0.5, 0.62, 0.22, { rgb(255, 170, 60), rgb(236, 72, 90), rgb(150, 110, 220) }, "Crunchy Brain", 2.99 },
	{ "Bottle", 0.26, 0.66, 0.26, { rgb(120, 200, 110), rgb(140, 200, 255), rgb(236, 60, 80) }, "Fizz", 1.49 },
	{ "Can", 0.24, 0.32, 0.24, { rgb(236, 60, 80), rgb(80, 150, 230), rgb(255, 214, 80) }, "Cola", 0.89 },
	{ "Carton", 0.3, 0.56, 0.3, { rgb(250, 250, 252), rgb(214, 236, 255) }, "Milk", 1.15 },
	{ "Bag", 0.46, 0.5, 0.2, { rgb(255, 214, 80), rgb(96, 186, 110), rgb(255, 130, 180) }, "Chips!", 1.79 },
}

-- Places de la file (u, z) : 1 paie, 2 décharge, 3 attend ; arrivée / sortie
local QUEUE = { { 2.05, 5.3 }, { 2.05, 9.3 }, { 2.25, 12.9 } }
local SPAWN = { 2.4, 17.4 }
local EXIT = { { 2.05, 1.7 }, { -4.2, 1.7 } }

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function placeAt(k: number): number
	return 3.2 + (k - 1) * 0.9
end

local function scanAt(k: number): number
	return 4.2 + k * 1.4
end

local function money(v: number): string
	local s = string.format("%.2f", v)
	if Locale.IsFrench() then
		s = (string.gsub(s, "%.", ","))
	end
	return s .. " €"
end

-- Groupe de pièces rangées par rapport à un pivot (déplacé d'un bloc)
local function group(parts: { BasePart }, pivot: CFrame): any
	local offsets = table.create(#parts)
	for i, p in ipairs(parts) do
		offsets[i] = pivot:ToObjectSpace(p.CFrame)
	end
	return { Parts = parts, Offsets = offsets, Shown = true }
end

local function moveGroup(g: any, pivot: CFrame)
	local frames = table.create(#g.Parts)
	for i, o in ipairs(g.Offsets) do
		frames[i] = pivot * o
	end
	workspace:BulkMoveTo(g.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function showGroup(g: any, on: boolean)
	if g.Shown ~= on then
		g.Shown = on
		for _, p in ipairs(g.Parts) do
			p.LocalTransparencyModifier = on and 0 or 1
		end
	end
end

-- Un article (pivot = milieu du dessous) ; 1 ou 2 pièces
local function makeItem(parent: Instance, spec: { any }, color: Color3, seed: number): any
	local kind, w, h, d = spec[1] :: string, spec[2] :: number, spec[3] :: number, spec[4] :: number
	local P = CFrame.new(0, -500, 0)
	local parts = {}
	if kind == "Bottle" or kind == "Can" then
		local body = cyl(parent, "Groceries", P, 0, 0, 0, h, w, color, kind == "Can" and M.Metal or M.Glass)
		if kind == "Bottle" then
			body.Transparency = 0.25
			table.insert(parts, cyl(parent, "GroceriesCap", P, 0, h - 0.02, 0, 0.12, w * 0.42, WHITE, M.SmoothPlastic))
		end
		table.insert(parts, 1, body)
	else
		local p = box(parent, "Groceries", P, -w / 2, w / 2, 0, h, -d / 2, d / 2, color, kind == "Bag" and M.Fabric or M.SmoothPlastic)
		if kind == "Carton" then
			-- toit du brique (arête)
			local roof = newPart(parent, "GroceriesTop", Vector3.new(w * 0.99, 0.16, 0.16), P * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, 0), color, M.SmoothPlastic)
			table.insert(parts, roof)
		elseif kind == "Box" and seed % 2 == 0 then
			printLabel(p, Enum.NormalId.Front, "Crunchy Brain", "🥣", color, 60)
		end
		table.insert(parts, 1, p)
	end
	for _, p in ipairs(parts) do
		p.LocalTransparencyModifier = 1
	end
	local g = group(parts, P)
	g.Shown = false
	return g
end

-- Panier à provisions (pivot = milieu du fond) ; ~8 pièces
local function basket(parent: Instance, seed: number): any
	local P = CFrame.new(0, -500, 0)
	local c = pick({ rgb(236, 72, 90), rgb(80, 150, 230), rgb(96, 186, 110) }, seed, 71)
	local parts = {
		box(parent, "BasketFloor", P, -0.45, 0.45, 0, 0.08, -0.28, 0.28, c, M.SmoothPlastic),
		box(parent, "BasketSide", P, -0.45, 0.45, 0.04, 0.5, -0.3, -0.25, c, M.SmoothPlastic),
		box(parent, "BasketSide", P, -0.45, 0.45, 0.04, 0.5, 0.25, 0.3, c, M.SmoothPlastic),
		box(parent, "BasketEnd", P, -0.47, -0.42, 0.04, 0.5, -0.27, 0.27, c, M.SmoothPlastic),
		box(parent, "BasketEnd", P, 0.42, 0.47, 0.04, 0.5, -0.27, 0.27, c, M.SmoothPlastic),
		box(parent, "BasketHandle", P, -0.4, 0.4, 0.78, 0.84, -0.03, 0.03, rgb(40, 40, 48), M.SmoothPlastic),
		box(parent, "BasketGoods", P, -0.35, -0.02, 0.06, 0.62, -0.18, 0.12, pick(PALETTE, seed, 73), M.SmoothPlastic),
		box(parent, "BasketGoods", P, 0.04, 0.34, 0.06, 0.44, -0.14, 0.16, pick(PALETTE, seed, 79), M.SmoothPlastic),
	}
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(parts, box(parent, "BasketHandlePost", P, sx * 0.4 - 0.03, sx * 0.4 + 0.03, 0.48, 0.82, -0.03, 0.03, rgb(40, 40, 48), M.SmoothPlastic))
	end
	return group(parts, P)
end

-- Petit écran (SurfaceGui « rétroéclairé ») : renvoie le texte
local function screenText(p: BasePart, face: Enum.NormalId, pps: number, bg: Color3, color: Color3, initial: string, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.1
	gui.MaxDistance = 45
	gui.Parent = p
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = bg
	back.BorderSizePixel = 0
	back.Parent = gui
	local t = text(back, "Text", initial, 0.05, 0.06, 0.9, 0.88, color, font or Enum.Font.GothamBold)
	return t
end

local function checkoutPrompt(m: any, parent: Instance, at: CFrame)
	local anchor = newPart(parent, "CheckoutPoint", Vector3.new(1, 1, 1), at, WHITE, M.SmoothPlastic)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CheckoutPrompt"
	prompt.ActionText = Locale.T("🛒 Checkout")
	prompt.ObjectText = Locale.T("🛒 MegaDopa")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local pos = anchor.Position
	table.insert(m.Checkouts, pos)
	prompt.Triggered:Connect(function()
		ShopUI.OpenShop("Market", { Anchor = pos })
	end)
end

function MarketCheckout.Lane(m: any, parent: Instance, i: number)
	local L = m.F * CFrame.new(LANES[i], 0, 0)
	local open = i <= OPEN_LANES
	local white = rgb(240, 240, 244)
	local inox = rgb(196, 200, 210)
	local graphite = rgb(52, 54, 64)
	-- meuble : caisson, plinthe en retrait, bandeau de l'enseigne côté client, plan inox
	box(parent, "CheckoutBody", L, -0.9, 0.9, FLOOR_TOP, 2.55, 3, 11.2, white, M.SmoothPlastic, true)
	box(parent, "CheckoutPlinth", L, 0.86, 0.93, FLOOR_TOP, 0.42, 3.1, 11.1, graphite, M.Metal)
	box(parent, "CheckoutBand", L, 0.88, 0.94, 1.05, 1.75, 3.2, 11, BRAND, M.SmoothPlastic)
	box(parent, "CheckoutBandLine", L, 0.9, 0.96, 1.75, 1.83, 3.2, 11, YELLOW, M.SmoothPlastic)
	local top = box(parent, "Worktop", L, -0.96, 0.96, 2.52, TOP_Y, 2.92, 11.3, inox, M.Metal)
	top.Reflectance = 0.08
	for _, z in ipairs({ 2.92, 11.3 }) do
		-- angles arrondis (côté client)
		cyl(parent, "WorktopCorner", L, 0.96, 2.52, z, TOP_Y - 2.52, 0.2, inox, M.Metal)
	end
	-- tapis : lit en caoutchouc, nervures qui défilent, rouleaux, rails, cellule
	box(parent, "Belt", L, -0.72, 0.72, 2.58, BELT_Y, BELT_Z0, BELT_Z1, rgb(30, 30, 36), M.Rubber)
	local slats = {}
	for k = 0, 5 do
		local z = BELT_Z0 + 0.3 + k * 0.75
		table.insert(slats, box(parent, "BeltRib", L, -0.68, 0.68, 2.66, 2.73, z - 0.05, z + 0.05, rgb(62, 62, 72), M.Rubber))
	end
	for _, z in ipairs({ BELT_Z0 + 0.1, BELT_Z1 - 0.1 }) do
		cylX(parent, "BeltRoller", L, -0.7, 0.7, 2.66, z, 0.2, rgb(210, 212, 222), M.Metal)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local rail = box(parent, "BeltGuide", L, sx * 0.76, sx * 0.86, 2.6, 2.86, BELT_Z0, BELT_Z1, inox, M.Metal)
		rail.Reflectance = 0.15
		box(parent, "PhotoEye", L, sx * 0.84 - 0.04, sx * 0.84 + 0.04, 2.8, 3.12, 6.46, 6.56, graphite, M.SmoothPlastic)
	end
	-- barre « client suivant » rangée sur son support (côté caisse)
	box(parent, "DividerTray", L, -1.1, -0.88, 2.56, 2.66, 9.3, 10.9, graphite, M.SmoothPlastic)
	local rest = L * CFrame.new(-0.99, 2.74, 10.1) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(45), 0, 0)
	local restBar = newPart(parent, "DividerBar", Vector3.new(1.3, 0.15, 0.15), rest, rgb(120, 90, 200), M.SmoothPlastic)
	printLabel(restBar, Enum.NormalId.Top, Locale.T("Next customer"), "➡️", BRAND2, 60)
	-- scanner : plateau-balance inox, vitre, lignes laser, tour, pistolet
	local bed = box(parent, "ScanScale", L, -0.7, 0.7, 2.56, 2.66, 5, 6.25, rgb(170, 174, 186), M.Metal)
	bed.Reflectance = 0.12
	local glass = box(parent, "ScanGlass", L, -0.42, 0.34, 2.62, 2.69, 5.3, 5.95, rgb(40, 14, 20), M.Glass)
	local lasers = {}
	for _, a in ipairs({ -32, 32 }) do
		local laser = newPart(parent, "ScanLaser", Vector3.new(0.72, 0.01, 0.025), L * CFrame.new(-0.04, 2.705, SCAN_Z) * CFrame.Angles(0, math.rad(a), 0), rgb(255, 60, 60), M.Neon)
		laser.Transparency = 1
		table.insert(lasers, laser)
	end
	box(parent, "ScanTower", L, 0.5, 0.78, 2.6, 3.55, 5.15, 6.1, graphite, M.SmoothPlastic)
	box(parent, "ScanTowerGlass", L, 0.47, 0.52, 2.8, 3.36, 5.35, 5.9, rgb(60, 18, 26), M.Glass)
	box(parent, "ScanTowerCap", L, 0.46, 0.82, 3.52, 3.62, 5.1, 6.15, rgb(236, 72, 140), M.SmoothPlastic)
	local beep = Instance.new("BillboardGui")
	beep.Name = "Beep"
	beep.Size = UDim2.fromScale(1.5, 0.6)
	beep.StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0)
	beep.MaxDistance = 30
	beep.LightInfluence = 0
	beep.Enabled = false
	beep.Parent = glass
	local bt = text(beep, "Text", "BIP ! ✓", 0, 0, 1, 1, rgb(255, 80, 90), Enum.Font.FredokaOne)
	local st = Instance.new("UIStroke")
	st.Color = WHITE
	st.Thickness = 2
	st.Parent = bt
	-- poste caissier : tiroir-caisse, tablette, clavier, pistolet, imprimante, écran
	box(parent, "CashDrawer", L, -1.3, -0.88, 1.5, 2.1, 5, 6.3, rgb(70, 66, 84), M.SmoothPlastic)
	box(parent, "DrawerHandle", L, -1.34, -1.28, 1.72, 1.86, 5.35, 5.95, inox, M.Metal)
	box(parent, "CashierDesk", L, -1.58, -0.88, 2.42, 2.5, 6.8, 9.2, graphite, M.SmoothPlastic)
	local kb = box(parent, "Keyboard", L, -1.48, -1.02, 2.46, 2.56, 7.55, 8.6, rgb(30, 30, 36), M.SmoothPlastic)
	kb.CFrame *= CFrame.Angles(0, 0, math.rad(-6))
	box(parent, "ScanGunCradle", L, -1.46, -1.1, 2.46, 2.66, 8.72, 8.92, rgb(40, 40, 48), M.SmoothPlastic)
	local gun = box(parent, "ScanGun", L, -1.38, -1.18, 2.62, 3.02, 8.75, 8.89, rgb(236, 190, 60), M.SmoothPlastic)
	gun.CFrame *= CFrame.Angles(math.rad(18), 0, 0)
	box(parent, "Printer", L, -1.48, -1.08, 2.46, 2.76, 6.9, 7.45, rgb(236, 236, 240), M.SmoothPlastic)
	local paperCF = L * CFrame.new(-1.28, 2.76, 7.3)
	local paper = newPart(parent, "Receipt", Vector3.new(0.26, 0.02, 0.01), paperCF, WHITE, M.SmoothPlastic)
	paper.LocalTransparencyModifier = 1
	cyl(parent, "ScreenArm", L, -1.3, 2.5, 9.05, 0.95, 0.1, graphite, M.Metal)
	local cashierScreen = newPart(parent, "CashierScreen", Vector3.new(0.08, 0.72, 1.0), L * CFrame.new(-1.3, 3.72, 8.85) * CFrame.Angles(0, 0, math.rad(-10)), rgb(28, 28, 34), M.SmoothPlastic)
	local screenLabel = screenText(cashierScreen, Enum.NormalId.Left, 90, rgb(20, 30, 50), rgb(210, 240, 255), "MegaDopa", Enum.Font.Code)
	screenLabel.TextXAlignment = Enum.TextXAlignment.Left
	-- afficheur client (TOTAL) sur un mât, côté allée
	cyl(parent, "PoleMast", L, 0.85, 2.55, 6.18, 1.4, 0.1, graphite, M.Metal)
	local pole = box(parent, "PoleDisplay", L, 0.7, 1.0, 3.9, 4.35, 5.85, 6.55, rgb(28, 28, 34), M.SmoothPlastic)
	local poleText = screenText(pole, Enum.NormalId.Right, 90, rgb(10, 30, 20), rgb(120, 255, 160), Locale.T("Hello! 👋"), Enum.Font.Code)
	-- TPE (terminal de paiement) sur pied pivotant
	cyl(parent, "TPEFoot", L, 0.72, 2.58, 4.9, 0.08, 0.34, graphite, M.Metal)
	cyl(parent, "TPEStem", L, 0.72, 2.62, 4.9, 0.5, 0.07, graphite, M.Metal)
	local T = L * CFrame.new(0.76, 3.28, 4.9) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.rad(28), 0, 0)
	box(parent, "TPE", T, -0.17, 0.17, -0.3, 0.3, -0.05, 0.07, rgb(40, 40, 48), M.SmoothPlastic)
	local tpeScreen = box(parent, "TPEScreen", T, -0.13, 0.13, 0.05, 0.26, -0.08, -0.03, rgb(20, 20, 24), M.SmoothPlastic)
	local tpeText = screenText(tpeScreen, Enum.NormalId.Front, 200, rgb(230, 240, 250), rgb(40, 40, 60), "🧠 MegaDopa")
	local keypad = box(parent, "TPEKeys", T, -0.13, 0.13, -0.26, 0.0, -0.075, -0.035, rgb(70, 70, 80), M.SmoothPlastic)
	do
		local g = Instance.new("SurfaceGui")
		g.Name = "Keys"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 200
		g.LightInfluence = 0.6
		g.MaxDistance = 18
		g.Parent = keypad
		for r = 0, 3 do
			for c = 0, 2 do
				local key = Instance.new("Frame")
				key.BorderSizePixel = 0
				key.BackgroundColor3 = r == 3 and (c == 0 and rgb(220, 70, 70) or (c == 2 and rgb(90, 190, 110) or rgb(236, 236, 240))) or rgb(220, 222, 230)
				key.Position = UDim2.fromScale(0.08 + c * 0.3, 0.06 + r * 0.235)
				key.Size = UDim2.fromScale(0.24, 0.18)
				key.Parent = g
				corner(key, 0.25)
			end
		end
	end
	-- zone d'ensachage : séparateur + CARROUSEL À SACS (mât, moyeu, 3 bras, 3 sacs)
	local C = L * CFrame.new(0, 0, BAG_Z)
	cyl(parent, "CarouselMast", C, 0, 2.58, 0, 1.4, 0.12, inox, M.Metal)
	local cparts = { cyl(parent, "CarouselHub", C, 0, 3.94, 0, 0.14, 0.3, graphite, M.Metal) }
	local bags = {}
	for k = 0, 2 do
		local a = C * CFrame.Angles(0, k * math.pi * 2 / 3, 0)
		table.insert(cparts, box(parent, "CarouselArm", a, -0.03, 0.03, 3.96, 4.04, 0, BAG_R + 0.05, inox, M.Metal))
		local bag = box(parent, "CarrierBag", a, -0.27, 0.27, 2.78, 3.9, BAG_R - 0.16, BAG_R + 0.16, rgb(250, 250, 252), M.SmoothPlastic)
		bag.Transparency = 0.18
		table.insert(cparts, bag)
		table.insert(bags, bag)
	end
	local carousel = group(cparts, C)
	-- présentoir à bonbons au bout de la caisse (face à la file)
	box(parent, "CandyBase", L, -0.9, 0.85, FLOOR_TOP, 0.6, 11.4, 12.8, graphite, M.SmoothPlastic, true)
	box(parent, "CandyBack", L, -0.9, -0.66, 0.6, 4.4, 11.4, 12.8, white, M.SmoothPlastic, true)
	for k = 0, 2 do
		local y = 1.25 + k * 1.02
		box(parent, "CandyShelf", L, -0.66, 0.62, y - 0.06, y, 11.45, 12.75, white, M.SmoothPlastic)
		for j = 0, 2 do
			local z = 11.7 + j * 0.45
			local c = pick(PALETTE, i * 9 + k * 3 + j, 83)
			local p = box(parent, "Candy", L, -0.1, 0.42, y - 0.02, y + 0.55 - k * 0.05, z - 0.18, z + 0.18, c, M.SmoothPlastic)
			if j == 1 and k == 1 then
				printLabel(p, Enum.NormalId.Right, "Choco", "🍫", c, 70)
			end
		end
	end
	local candySign = box(parent, "CandySign", L, -0.88, -0.78, 4.36, 5.1, 11.45, 12.75, BRAND, M.SmoothPlastic)
	label(candySign, Enum.NormalId.Right, Locale.T("🍬 Sweets"), WHITE, nil, 40, 50)
	-- lampe de caisse numérotée + LED d'état (vert : ouverte, rouge : fermée)
	cyl(parent, "LanePole", L, -0.62, 2.58, 11.15, 6.66, 0.14, inox, M.Metal)
	local lamp = box(parent, "LaneLight", L, -1.22, -0.02, 9.2, 10.4, 10.85, 11.25, rgb(36, 36, 46), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = label(lamp, face, tostring(i), WHITE, open and rgb(40, 150, 90) or rgb(170, 50, 60), 40, 120)
		g.LightInfluence = 0
	end
	box(parent, "LaneLED", L, -1.12, -0.12, 10.36, 10.5, 10.9, 11.2, open and rgb(90, 255, 140) or rgb(255, 70, 80), M.Neon)
	-- poste caissier : tapis anti-fatigue, tabouret assis-debout, paroi givrée
	box(parent, "CashierMat", L, -2.8, -1.05, 0.04, 0.11, 4.2, 9.4, rgb(46, 46, 52), M.Rubber)
	cyl(parent, "StoolBase", L, -2.45, 0.08, 7.4, 0.13, 0.9, graphite, M.Metal)
	cyl(parent, "StoolPost", L, -2.45, 0.2, 7.4, 1.62, 0.14, inox, M.Metal)
	cyl(parent, "StoolSeat", L, -2.45, 1.8, 7.4, 0.22, 0.84, rgb(30, 30, 36), M.Fabric)
	local panel = box(parent, "LanePanel", L, -2.97, -2.9, 0.12, 3.34, 4, 9.6, rgb(220, 230, 240), M.Glass, true)
	panel.Transparency = 0.45
	box(parent, "LanePanelRail", L, -3.0, -2.87, 3.3, 3.45, 4, 9.6, BRAND, M.SmoothPlastic)
	checkoutPrompt(m, parent, L * CFrame.new(1.9, 3.6, 5.3))
	if not open then
		-- caisse fermée : sangle rétractable en travers de l'allée + panneau
		cyl(parent, "QueuePost", L, 3.6, FLOOR_TOP, 11.3, 3.1, 0.16, inox, M.Metal)
		box(parent, "QueueTape", L, 0.96, 3.52, 2.72, 2.86, 11.27, 11.33, rgb(220, 50, 60), M.Fabric)
		local closed = box(parent, "ClosedSign", L, -0.5, 0.5, BELT_Y - 0.05, 3.5, 8.47, 8.53, rgb(236, 72, 90), M.SmoothPlastic)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(closed, face, Locale.T("🔒 Closed"), WHITE, nil, 40, 40)
		end
		return
	end
	-- articles du cycle (5 + la barre « client suivant »)
	local items = {}
	for k, spec in ipairs(ITEM_SPECS) do
		local colors = spec[5] :: { Color3 }
		table.insert(items, makeItem(parent, spec, colors[(i + k) % #colors + 1], i + k))
	end
	local bar = newPart(parent, "DividerBar", Vector3.new(1.3, 0.15, 0.15), CFrame.new(0, -500, 0), rgb(120, 90, 200), M.SmoothPlastic)
	bar.LocalTransparencyModifier = 1
	table.insert(items, { Parts = { bar }, Offsets = { CFrame.new(0, 0.11, 0) * CFrame.Angles(0, 0, math.rad(45)) }, Shown = false })
	table.insert(m.Belts, {
		Owner = "full",
		F = L,
		Index = i,
		Slats = slats,
		Items = items,
		Rest = rest,
		Scanner = glass,
		Lasers = lasers,
		Beep = beep,
		Carousel = carousel,
		CarouselCF = C,
		Bags = bags,
		Pole = poleText,
		Screen = screenLabel,
		Terminal = tpeText,
		Paper = paper,
		PaperCF = paperCF,
		Pos = (L * CFrame.new(0, 3, 7)).Position,
		Offset = i * 5.3,
		Flash = -10,
		Cashier = nil,
		Customers = {},
		Last = {},
	})
end

-- 🤖 caisses automatiques : écran tactile (achats qui défilent, total,
-- paiement), scanner, lecteur de carte, balance d'ensachage + potence à
-- sac, lampe d'état. Repère K : client à -X (regarde +X)
local KIOSK_T = 16
function MarketCheckout.SelfCheckout(m: any, parent: Instance)
	local white = rgb(240, 240, 244)
	local inox = rgb(196, 200, 210)
	local graphite = rgb(52, 54, 64)
	for i = 0, 3 do
		local K = m.F * CFrame.new(48.4, 0, 3 + i * 3.5)
		box(parent, "KioskBody", K, -0.9, 1.0, FLOOR_TOP, 2.55, -0.75, 0.75, white, M.SmoothPlastic, true)
		box(parent, "KioskKick", K, -0.94, -0.86, FLOOR_TOP, 0.4, -0.7, 0.7, graphite, M.Metal)
		box(parent, "KioskBand", K, -0.95, -0.88, 1.1, 1.6, -0.7, 0.7, BRAND2, M.SmoothPlastic)
		local top = box(parent, "KioskTop", K, -1.0, 1.05, 2.52, 2.6, -0.8, 0.8, inox, M.Metal)
		top.Reflectance = 0.08
		box(parent, "KioskScale", K, -0.75, 0.05, 2.56, 2.64, -0.5, 0.5, rgb(170, 174, 186), M.Metal)
		local glass = box(parent, "KioskGlass", K, -0.6, -0.1, 2.6, 2.67, -0.3, 0.3, rgb(40, 14, 20), M.Glass)
		local laser = newPart(parent, "ScanLaser", Vector3.new(0.45, 0.01, 0.025), K * CFrame.new(-0.35, 2.685, 0), rgb(255, 60, 60), M.Neon)
		laser.Transparency = 0.4
		box(parent, "KioskPost", K, 0.6, 0.78, 2.6, 4.2, -0.09, 0.09, graphite, M.Metal)
		local S = K * CFrame.new(0.52, 4.6, 0) * CFrame.Angles(0, 0, math.rad(-15))
		local screen = box(parent, "KioskScreen", S, -0.06, 0.06, -0.58, 0.58, -0.78, 0.78, rgb(28, 28, 34), M.SmoothPlastic)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 110
		gui.LightInfluence = 0.1
		gui.MaxDistance = 45
		gui.Parent = screen
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = rgb(246, 246, 252)
		back.BorderSizePixel = 0
		back.Parent = gui
		local head = Instance.new("Frame")
		head.Size = UDim2.fromScale(1, 0.18)
		head.BackgroundColor3 = BRAND
		head.BorderSizePixel = 0
		head.Parent = back
		text(head, "Brand", "🧠 MegaDopa", 0.04, 0.12, 0.6, 0.76, WHITE, Enum.Font.FredokaOne, Enum.TextXAlignment.Left)
		local list = text(back, "List", "", 0.05, 0.22, 0.9, 0.46, rgb(50, 50, 70), Enum.Font.Code, Enum.TextXAlignment.Left)
		list.TextYAlignment = Enum.TextYAlignment.Top
		local total = text(back, "Total", "", 0.05, 0.68, 0.9, 0.12, rgb(40, 40, 60), Enum.Font.GothamBlack, Enum.TextXAlignment.Right)
		local button = Instance.new("Frame")
		button.Position = UDim2.fromScale(0.1, 0.82)
		button.Size = UDim2.fromScale(0.8, 0.14)
		button.BackgroundColor3 = rgb(80, 190, 110)
		button.BorderSizePixel = 0
		button.Parent = back
		corner(button, 0.3)
		local btn = text(button, "Label", Locale.T("👋 Touch to start"), 0.05, 0.1, 0.9, 0.8, WHITE, Enum.Font.GothamBold)
		-- lecteur de carte, balance d'ensachage et potence à sac
		box(parent, "CardReader", K, 0.1, 0.46, 2.58, 2.84, 0.5, 0.74, rgb(40, 40, 48), M.SmoothPlastic)
		box(parent, "BagStand", K, -0.9, 0.9, FLOOR_TOP, 2.2, 0.85, 1.55, inox, M.Metal, true)
		box(parent, "BagScale", K, -0.8, 0.8, 2.16, 2.26, 0.9, 1.5, rgb(170, 174, 186), M.Metal)
		for _, u in ipairs({ -0.76, 0.76 }) do
			cyl(parent, "BagRod", K, u, 2.24, 1.48, 1.2, 0.06, graphite, M.Metal)
		end
		box(parent, "BagBar", K, -0.8, 0.8, 3.4, 3.48, 1.44, 1.52, graphite, M.Metal)
		local bag = box(parent, "CarrierBag", K, -0.55, 0.55, 2.24, 3.36, 0.98, 1.4, rgb(250, 250, 252), M.SmoothPlastic)
		bag.Transparency = 0.18
		-- lampe d'état sur la potence de l'écran
		cyl(parent, "StatusPole", K, 0.69, 4.9, 0, 1.35, 0.07, graphite, M.Metal)
		local light = cyl(parent, "StatusLight", K, 0.69, 6.2, 0, 0.36, 0.34, rgb(90, 255, 140), M.Neon)
		checkoutPrompt(m, parent, K * CFrame.new(-1.8, 3.6, 0))
		table.insert((m :: any).Kiosks, {
			Owner = "full",
			K = K,
			List = list,
			Total = total,
			Button = btn,
			ButtonFrame = button,
			Light = light,
			Glass = glass,
			Busy = i % 2 == 0,
			Offset = i * 4.1,
			Pos = K.Position,
			Last = "",
		})
	end
	hangingSign(m, parent, 47, 8.4, 9, Locale.T("🤖 Self-checkout"), BRAND2, true)
end


-- Personnages des caisses (v9.9) : caissier·ère + file de clients avec
-- panier ; clients aux caisses automatiques
local LANE_CROWD = { 3, 2, 2, 2 }
function MarketCheckout.Zone(m: any, parent: Instance, jobs: { () -> () })
	for i = 1, OPEN_LANES do
		table.insert(jobs, function()
			local belt: any? = nil
			for _, b in ipairs(m.Belts) do
				if b.Index == i then
					belt = b
				end
			end
			if not belt then
				return
			end
			local L = belt.F
			local a = actor(m, parent, "Checkout", "cashier", 10 + i * 7, L * CFrame.new(-1.85, FLOOR_TOP, 6) * FACE_PX, "idle")
			if a then
				a.Custom = true
				belt.Cashier = a
			end
			for slot = 1, LANE_CROWD[i] or 2 do
				local q = QUEUE[slot]
				local c = actor(m, parent, "Checkout", "shopper", 200 + i * 13 + slot * 5, L * CFrame.new(q[1], FLOOR_TOP, q[2]), "idle", { Prop = "none" })
				if c then
					c.Custom = true
					local parts = {}
					for _, d in ipairs(c.Model:GetDescendants()) do
						if d:IsA("BasePart") then
							table.insert(parts, d)
						end
					end
					local b = basket(parent, i * 5 + slot)
					C.AddParts(#b.Parts)
					table.insert(belt.Customers, { Actor = c, Slot = slot, Basket = b, Parts = parts, Alpha = 1, Owner = "Checkout" })
				end
			end
		end)
	end
	table.insert(jobs, function()
		for index, k in ipairs((m :: any).Kiosks) do
			if k.Busy then
				local c = actor(m, parent, "Checkout", "shopper", 300 + index * 17, k.K * CFrame.new(-1.75, FLOOR_TOP, 0) * FACE_PX, "scan", { Prop = "none" })
				if c then
					c.Custom = true
					k.Customer = c
				end
			end
		end
	end)
end


-- 🛒 Caisses (v9.9) : temps du cycle d'une caisse et numéro du cycle
local function laneClock(belt: any, now: number): (number, number)
	local t = now + belt.Offset
	return t % LANE_T, math.floor(t / LANE_T)
end

local function itemPrice(belt: any, cycle: number, k: number): number
	return (ITEM_SPECS[k][7] :: number) + math.floor(hash(cycle * 7 + belt.Index, k) * 6) * 0.1
end

-- Marche de A vers B (lissée au départ et à l'arrivée), regard dans le sens de la marche
local function walkCF(a: Vector3, b: Vector3, s: number): CFrame
	local p = a:Lerp(b, smooth(s))
	local d = b - a
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 1e-3 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, p + d.Unit)
end

local function laneSpot(L: CFrame, q: { number }): Vector3
	return (L * CFrame.new(q[1], FLOOR_TOP, q[2])).Position
end

-- Pose d'un client de la file : (repère au sol, anim, visibilité 0..1, panier à la main)
local function customerPose(belt: any, slot: number, count: number, tau: number, cycle: number): (CFrame, string, number, boolean)
	local L = belt.F
	local role = (slot - 1 - cycle) % count -- 0 : paie ; count-1 : le dernier arrivé
	local faceCounter = CFrame.Angles(0, math.pi / 2, 0) -- regard vers -X (le comptoir)
	local function standing(q: { number }, toCounter: boolean): CFrame
		return CFrame.new(laneSpot(L, q)) * (toCounter and (L - L.Position) * faceCounter or (L - L.Position))
	end
	if role == 0 then
		if tau < 2 then
			return walkCF(laneSpot(L, QUEUE[2]), laneSpot(L, QUEUE[1]), tau / 2), "walk", 1, true
		elseif tau < 14.6 then
			return standing(QUEUE[1], true), (tau >= 11.9 and "type" or (tau >= 5 and tau < 6.5 and "talk" or "idle")), 1, false
		elseif tau < 18.2 then
			-- départ vers la sortie (avec ses sacs), fondu à la fin
			local a, b, c = laneSpot(L, QUEUE[1]), laneSpot(L, EXIT[1]), laneSpot(L, EXIT[2])
			local l1, l2 = (b - a).Magnitude, (c - b).Magnitude
			local s = smooth((tau - 14.6) / 3.6) * (l1 + l2)
			local cf = s < l1 and walkCF(a, b, 0) or walkCF(b, c, 0)
			local p = s < l1 and a:Lerp(b, s / l1) or b:Lerp(c, (s - l1) / l2)
			cf = CFrame.new(p) * (cf - cf.Position)
			return cf, "walk", 1 - math.clamp((tau - 17.4) / 0.8, 0, 1), true
		end
		return standing(QUEUE[1], true), "idle", 0, true
	end
	local place = role + 1
	local unloading = place == 2
	if role == count - 1 then
		if tau < 1 then
			return standing(SPAWN, false), "idle", 0, true
		elseif tau < 3 then
			return walkCF(laneSpot(L, SPAWN), laneSpot(L, QUEUE[place]), (tau - 1) / 2), "walk", math.clamp((tau - 1) / 0.6, 0, 1), true
		end
	elseif tau < 2 then
		return walkCF(laneSpot(L, QUEUE[place + 1]), laneSpot(L, QUEUE[place]), tau / 2), "walk", 1, true
	end
	if unloading then
		return standing(QUEUE[2], true), (tau >= 3.1 and tau < 7.4) and "scan" or "idle", 1, false
	end
	return standing(QUEUE[place], false), "idle", 1, false
end

-- Repère d'un article (k = 1..5, 6 = barre « client suivant ») ; nil = caché
local function itemFrame(belt: any, k: number, tau: number): (CFrame?, boolean)
	local L = belt.F
	if tau < placeAt(k) then
		return nil, false
	end
	local ju = (hash(belt.Index, k) - 0.5) * 0.3
	local yaw = CFrame.Angles(0, (hash(k, belt.Index) - 0.5) * 0.6, 0)
	local done = 0
	for j = 1, math.min(k - 1, 5) do
		done += smooth((tau - (scanAt(j) + 0.3)) / 0.6)
	end
	local zq = FRONT_Z + (k - 1 - done) * 0.8
	local zc = 10.6 - 1.4 * (tau - placeAt(k))
	if k == 6 then
		-- la barre est rangée sur son support une fois les articles passés
		if tau < 12 then
			return L * CFrame.new(0, BELT_Y, math.max(zq, zc)), false
		elseif tau < 12.6 then
			local a = L * CFrame.new(0, BELT_Y, FRONT_Z)
			local target = belt.Rest * CFrame.new(0, -0.11, 0)
			return a:Lerp(target, smooth((tau - 12) / 0.6)) * CFrame.new(0, math.sin((tau - 12) / 0.6 * math.pi) * 0.25, 0), false
		end
		return nil, false
	end
	local t0 = scanAt(k)
	if tau < t0 then
		return L * CFrame.new(ju, BELT_Y + 0.005, math.max(zq, zc)) * yaw, false
	elseif tau < t0 + 0.8 then
		-- dans la main : au-dessus de la vitre (BIP), puis dans le sac
		local s = (tau - t0) / 0.8
		local p0 = L * Vector3.new(ju, BELT_Y + 0.005, FRONT_Z)
		local p1 = L * Vector3.new(-0.05, 2.8, SCAN_Z)
		local p2 = L * Vector3.new(0, 2.95, BAG_Z + BAG_R)
		local p
		if s < 0.5 then
			local q = smooth(s / 0.5)
			p = p0:Lerp(p1, q) + Vector3.new(0, math.sin(q * math.pi) * 0.12, 0)
		else
			p = p1:Lerp(p2, smooth((s - 0.5) / 0.5))
		end
		return CFrame.new(p) * (L - L.Position) * yaw * CFrame.Angles(0, s * math.pi * 0.6, 0), s >= 0.38 and s <= 0.62
	end
	return nil, false
end

local function setText(belt: any, key: string, label: TextLabel?, value: string)
	if label and belt.Last[key] ~= value then
		belt.Last[key] = value
		label.Text = value
	end
end

function MarketCheckout.AnimateLane(belt: any, now: number)
	local N = NPC()
	local tau, cycle = laneClock(belt, now)
	local L = belt.F
	-- nervures du tapis (distance cumulée : jamais de saut entre deux cycles)
	local run = 1.4 * (math.clamp(tau, 3.2, 9.6) - 3.2)
	for j = 1, 6 do
		run += 0.8 * smooth((tau - (scanAt(j) + 0.3)) / 0.6)
	end
	local dist = cycle * BELT_RUN + run
	local span = BELT_Z1 - BELT_Z0 - 0.4
	local ribFrames = table.create(#belt.Slats)
	for k = 1, #belt.Slats do
		local z = BELT_Z1 - 0.2 - ((dist + (k - 1) * span / #belt.Slats) % span)
		ribFrames[k] = L * CFrame.new(0, 2.695, z)
	end
	workspace:BulkMoveTo(belt.Slats, ribFrames, Enum.BulkMoveMode.FireCFrameChanged)
	-- articles
	local flashing = false
	for k, item in ipairs(belt.Items) do
		local cf, flash = itemFrame(belt, k, tau)
		if cf then
			showGroup(item, true)
			moveGroup(item, cf)
		else
			showGroup(item, false)
		end
		flashing = flashing or flash
	end
	if flashing then
		belt.Flash = now
	end
	local on = now - belt.Flash < 0.3
	belt.Scanner.Color = on and rgb(255, 60, 70) or rgb(40, 14, 20)
	for _, laser in ipairs(belt.Lasers) do
		laser.Transparency = on and 0.1 or 1
	end
	belt.Beep.Enabled = on
	-- carrousel à sacs : un tiers de tour après le 2e, le 4e article et au paiement
	local turns = smooth((tau - 7.6) / 0.8) + smooth((tau - 10.4) / 0.8) + smooth((tau - 13) / 0.8)
	moveGroup(belt.Carousel, belt.CarouselCF * CFrame.Angles(0, turns * math.pi * 2 / 3, 0))
	local bagsOn = not (tau >= 14.8 and tau < 19.4)
	if belt.Last.Bags ~= bagsOn then
		belt.Last.Bags = bagsOn
		for _, bag in ipairs(belt.Bags) do
			bag.LocalTransparencyModifier = bagsOn and 0 or 1
		end
	end
	-- écrans : afficheur client, écran caisse, TPE ; ticket qui sort
	local count, total = 0, 0
	local lines = {}
	for k = 1, 5 do
		if tau >= scanAt(k) + 0.4 then
			count += 1
			local price = itemPrice(belt, cycle, k)
			total += price
			table.insert(lines, string.format("%-13s %s", Locale.T(ITEM_SPECS[k][6] :: string), money(price)))
		end
	end
	local pole
	if tau >= 13.2 then
		pole = Locale.T("Thank you! 😊")
	elseif count == 0 then
		pole = Locale.T("Hello! 👋")
	else
		pole = Locale.T("TOTAL %s", money(total))
	end
	setText(belt, "Pole", belt.Pole, pole)
	while #lines > 4 do
		table.remove(lines, 1)
	end
	table.insert(lines, "")
	table.insert(lines, string.format("%-13s %s", Locale.T("TOTAL"), money(total)))
	setText(belt, "Screen", belt.Screen, count == 0 and ("🧠 MegaDopa  ·  " .. Locale.T("Lane %d", belt.Index)) or table.concat(lines, "\n"))
	local tpe
	if tau >= 11.9 and tau < 13.2 then
		tpe = Locale.T("💳 Tap your card") .. "\n" .. money(total)
	elseif tau >= 13.2 and tau < 14.8 then
		tpe = Locale.T("✅ Payment accepted")
	else
		tpe = "🧠 MegaDopa"
	end
	setText(belt, "TPE", belt.Terminal, tpe)
	local paper = belt.Paper
	if paper and belt.PaperCF then
		local len = (tau >= 13.2 and tau < 14.6) and smooth((tau - 13.2) / 1) * 0.55 or 0
		if len > 0.01 then
			paper.LocalTransparencyModifier = 0
			paper.Size = Vector3.new(0.26, len, 0.01)
			paper.CFrame = belt.PaperCF * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(0, len / 2, 0)
		elseif paper.LocalTransparencyModifier < 1 then
			paper.LocalTransparencyModifier = 1
		end
	end
	-- caissier·ère : scanne, encaisse, dit au revoir
	local cashier = belt.Cashier
	if cashier and N then
		local anim = "idle"
		if tau >= scanAt(1) - 0.6 and tau < 11.9 then
			anim = "scan"
		elseif tau >= 11.9 and tau < 14.3 then
			anim = "type"
		elseif tau >= 14.3 and tau < 16.5 then
			anim = "talk"
		end
		pcall(N.Animate, cashier.Model, anim, now + cashier.Offset)
	end
	-- file de clients
	local n = #belt.Customers
	for _, c in ipairs(belt.Customers) do
		local cf, anim, alpha, carry = customerPose(belt, c.Slot, n, tau, cycle)
		if math.abs(alpha - c.Alpha) > 0.04 or (alpha == 0) ~= (c.Alpha == 0) or (alpha == 1 and c.Alpha ~= 1) then
			c.Alpha = alpha
			local t = 1 - alpha
			for _, p in ipairs(c.Parts) do
				p.LocalTransparencyModifier = t
			end
			for _, p in ipairs(c.Basket.Parts) do
				p.LocalTransparencyModifier = t
			end
		end
		if alpha > 0 and N then
			local model = c.Actor.Model
			local root = model.PrimaryPart
			if root then
				root.CFrame = cf
			else
				model:PivotTo(cf)
			end
			pcall(N.Animate, model, anim, now + c.Actor.Offset)
			c.Actor.Pos = cf.Position
			moveGroup(c.Basket, cf * (carry and CFrame.new(0.95, 1.55, 0) or CFrame.new(0.9, 0.03, 0.2)))
		end
	end
end

-- 🤖 caisses automatiques : écran qui défile, lampe, client
function MarketCheckout.AnimateKiosk(k: any, now: number)
	local N = NPC()
	if not k.Busy then
		if k.Last ~= "idle" then
			k.Last = "idle"
			k.List.Text = Locale.T("Scan your first item\nor touch the screen")
			k.Total.Text = ""
			k.Button.Text = Locale.T("👋 Touch to start")
			k.Light.Color = rgb(236, 236, 240)
		end
		return
	end
	local tau = (now + k.Offset) % KIOSK_T
	local n = math.min(5, math.floor(tau / 1.8) + 1)
	local state = tau < 9 and ("scan" .. n) or (tau < 12 and "pay" or (tau < 14 and "thanks" or "idle"))
	k.Glass.Color = (tau < 9 and tau % 1.8 < 0.25) and rgb(255, 60, 70) or rgb(40, 14, 20)
	if k.Last ~= state then
		k.Last = state
		local lines, total = {}, 0
		local count = state == "idle" and 0 or (state == "pay" or state == "thanks") and 5 or n
		for j = 1, count do
			local price = (ITEM_SPECS[j][7] :: number) + (j % 3) * 0.2
			total += price
			table.insert(lines, string.format("%-12s %s", Locale.T(ITEM_SPECS[j][6] :: string), money(price)))
		end
		k.List.Text = state == "thanks" and Locale.T("Thank you, see you soon! 🧠") or (count == 0 and Locale.T("Scan your first item\nor touch the screen") or table.concat(lines, "\n"))
		k.Total.Text = count > 0 and Locale.T("TOTAL %s", money(total)) or ""
		k.Button.Text = state == "pay" and Locale.T("💳 Paying…") or (state == "thanks" and Locale.T("✅ Paid") or (count > 0 and Locale.T("💳 Pay") or Locale.T("👋 Touch to start")))
		k.ButtonFrame.BackgroundColor3 = state == "pay" and rgb(80, 150, 230) or rgb(80, 190, 110)
		k.Light.Color = count > 0 and rgb(90, 255, 140) or rgb(236, 236, 240)
	end
	local c = k.Customer
	if c and N then
		pcall(N.Animate, c.Model, tau < 9 and "scan" or (tau < 12 and "type" or "idle"), now + c.Offset)
	end
end


return MarketCheckout
