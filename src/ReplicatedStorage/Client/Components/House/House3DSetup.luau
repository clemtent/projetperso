--[[
	House3DSetup (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DSetup

	v9.5 🖥️ "Dopamine Setup" : les modèles 3D de TOUS les objets de la
	catégorie "Setup" (Config.House.Items, champ Setup) : bureaux gamer (1 à 5
	écrans + chaise gamer), clavier mécanique RGB, souris + tapis, télés (de
	S à Géant, sur pied ou au mur avec support), meuble télé, chaînes hi-fi
	(radio-cassette, CD, platine vinyle, mur de studio), moulin à vent,
	presse hydraulique, table à papier bulle, coin live, écran d'infos,
	pots de fleurs du jardin.

	Mêmes conventions que House3DRecipes (Register) : House3DKit.Builder,
	boîte 2D = 100 unités, y = hauteur depuis le sol, +z = le devant ; le
	modèle final (House3DRecipes.BuildModel) regarde -Z, pivot = bas du
	centre, PrimaryPart "Root", attributs ItemId / Footprint / TopHeight...,
	"SeatPart" (chaise des bureaux), "Hitbox".

	Pièces "vivantes" (animées / cliquables par World/LiveProps) :
	  - "Screen" : écran (face Front = côté visible), attributs ScreenKind
	    ("Runner" | "Live" | "DVD" | "News" | "Music") et ScreenIndex ;
	    "ScreenWing" : bords de l'écran incurvé (attribut ScreenIndex) ;
	  - "Key_<A..Z | 0..9 | Space>" : touches du clavier ; "KeyboardBase" ;
	  - "MouseBody", "MouseLeft", "MouseRight", "MouseWheel" ;
	  - "Bubble_<i>" : bulles du papier bulle ;
	  - "PressRam" (tout ce qui descend), "PressButton", "Crushable"
	    (attribut Variant = 1..3 : un seul visible à la fois), "PressBeacon" ;
	  - "Blades" (moyeu) + "Blade" (ailes) : tournent autour de "Pivot_Blades" ;
	  - "Vinyl" (disque qui tourne autour de "Pivot_Vinyl"), "SpeakerCone",
	    "VU_<i>" (barres de niveau), "PlayButton", "NextButton" ;
	  - "RecLight", "OnAir", "RingLight" (coin live) ;
	  - "Flower" : la fleur du pot (se balance autour de "Pivot_Flower") ;
	  - "RGB" : bandes lumineuses arc-en-ciel animées ; "Glow" : lumière fixe.
	  - "Pivot_*" : repères invisibles (pivots des animations ; leur axe Y =
	    la verticale du modèle, leur axe Z = l'axe avant-arrière).

	API :
	  House3DSetup.Register(recipes, family, helpers, flags)  (House3DRecipes)
	  House3DSetup.Has(itemId) -> boolean
	  House3DSetup.SetupOf(itemId) -> { Kind, Tier, Screens, Feeds, ... }?
	  House3DSetup.KindOf(itemId) -> string?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local House3DKit = require(script.Parent.House3DKit)
local HouseCommon = require(script.Parent.HouseCommon)

type Builder = House3DKit.Builder

local House3DSetup = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(46, 40, 58)
local CARBON = rgb(38, 40, 52)
local CARBON_LIGHT = rgb(64, 66, 84)
local CHROME = rgb(214, 218, 230)
local STEEL = rgb(150, 156, 172)
local SCREEN_OFF = rgb(22, 24, 36)
local PINK = rgb(255, 92, 170)
local CYAN = rgb(70, 225, 255)
local PURPLE = rgb(170, 110, 255)
local MINT = rgb(90, 230, 170)
local GOLD = rgb(245, 190, 60)
local RED = rgb(236, 60, 72)
local ORANGE = rgb(255, 150, 50)
local YELLOW = rgb(255, 214, 60)
local WOOD = rgb(196, 146, 102)
local WOOD_DARK = rgb(128, 86, 60)
local CREAM = rgb(255, 247, 236)
local LEAF = rgb(110, 196, 110)
local LEAF_DARK = rgb(64, 146, 84)
local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

local RAINBOW = { rgb(255, 70, 110), rgb(255, 160, 50), rgb(255, 230, 70), rgb(90, 230, 120), rgb(60, 200, 255), rgb(150, 100, 255) }

local R: { [string]: (b: Builder, ctx: any) -> () } = {}

----------------------------------------------------------------------
-- Réglages "Setup" (lus dans Config ; repli si l'objet n'y est pas)
----------------------------------------------------------------------

-- Repli par préfixe d'id (objet futur sans champ Setup)
local PREFIX_KINDS = {
	{ "SetupDesk", "Desk" },
	{ "SetupKeyboard", "Keyboard" },
	{ "SetupMouse", "Mouse" },
	{ "SetupTVStand", "TVStand" },
	{ "SetupTV", "TV" },
	{ "SetupNewsTV", "NewsTV" },
	{ "SetupHiFi", "HiFi" },
	{ "SetupWindmill", "Windmill" },
	{ "SetupPress", "Press" },
	{ "SetupBubbleWrap", "BubbleWrap" },
	{ "SetupLiveStudio", "LiveStudio" },
	{ "SetupPlant", "Plant" },
}

function House3DSetup.SetupOf(itemId: string): { [string]: any }?
	local item = HouseCommon.ItemsById[itemId]
	if type(item) == "table" and type(item.Setup) == "table" then
		return item.Setup
	end
	if type(itemId) ~= "string" then
		return nil
	end
	for _, pair in ipairs(PREFIX_KINDS) do
		if string.sub(itemId, 1, #pair[1]) == pair[1] then
			local setup: { [string]: any } = { Kind = pair[2], Tier = 1 }
			if pair[2] == "Plant" then
				setup.Flower = string.sub(itemId, #pair[1] + 1)
			end
			return setup
		end
	end
	return nil
end

function House3DSetup.KindOf(itemId: string): string?
	local setup = House3DSetup.SetupOf(itemId)
	return setup and tostring(setup.Kind) or nil
end

local function setupOf(b: Builder): { [string]: any }
	local item = b.Item
	local id = type(item) == "table" and tostring(item.Id) or ""
	return House3DSetup.SetupOf(id) or { Kind = "Unknown", Tier = 1 }
end

local function tierOf(setup: { [string]: any }): number
	return math.clamp(math.floor(tonumber(setup.Tier) or 1), 1, 6)
end

local function sizeRank(setup: { [string]: any }): number
	local size = tostring(setup.Size or "M")
	return ({ S = 1, M = 2, L = 3, XL = 4 })[size] or 2
end

----------------------------------------------------------------------
-- Petits morceaux
----------------------------------------------------------------------

-- Épaisseur (unités) d'au moins `studs` à l'échelle de l'objet
local function th(b: Builder, units: number, studs: number?): number
	return math.max(units, (studs or 0.036) / math.max(0.001, b.K))
end


local function named(part: BasePart, name: string): BasePart
	part.Name = name
	return part
end

local function neon(b: Builder, part: BasePart, name: string?): BasePart
	b.Neon(part)
	if name then
		part.Name = name
	end
	return part
end

-- Repère invisible (pivot d'une animation), repère local = celui de la recette
local function pivot(b: Builder, name: string, x: number, y: number, z: number): BasePart
	local part = b.Part("Part", CFrame.new(x, y, z), Vector3.new(1, 1, 1), WHITE, M.SmoothPlastic, name)
	part.Transparency = 1
	part.CastShadow = false
	return part
end

-- Écran : sa face Front regarde le devant (repère `cf`, bas-centre du verre)
local function screenPart(b: Builder, cf: CFrame, w: number, h: number, kind: string, index: number, depth: number?): BasePart
	local part = b.Part("Part", cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, h, depth or 0.5), SCREEN_OFF, M.SmoothPlastic, "Screen")
	part.CastShadow = false
	part:SetAttribute("ScreenKind", kind)
	part:SetAttribute("ScreenIndex", index)
	return part
end

-- Moniteur complet (cadre, dos, pied) ; `cf` = bas-centre du cadre, face +z
local function monitor(b: Builder, cf: CFrame, w: number, h: number, kind: string, index: number, frame: Color3, stand: boolean, standH: number)
	local bezel = 1.4
	b.BoxR(cf * CFrame.new(0, h / 2, 0), w + bezel * 2, h + bezel * 2, 1.6, frame, M.SmoothPlastic)
	b.BoxR(cf * CFrame.new(0, h / 2, -1.6), w * 0.5, h * 0.55, 1.8, darken(frame, 0.15), M.SmoothPlastic)
	local glass = cf * CFrame.new(0, 0, 1.05)
	local screen = screenPart(b, glass, w, h, kind, index)
	-- petite diode de marche
	local led = b.BoxR(cf * CFrame.new(w / 2 - 1, -bezel + 0.35, 0.9), 1, 0.5, 0.3, MINT, M.Neon)
	neon(b, led)
	if stand then
		b.BoxR(cf * CFrame.new(0, -standH / 2 - bezel, -2.2), 3, standH, 1.6, CHROME, M.Metal)
		b.BoxR(cf * CFrame.new(0, -standH - bezel + 0.6, -1), 14, 1.2, 9, frame, M.Metal)
	end
	return screen
end

-- Chaise gamer (le personnage regarde vers -z : le bureau) ; assise à `seatY`
local function gamerChair(b: Builder, z: number, seatY: number, main: Color3, trim: Color3, glowing: boolean)
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2 + 0.3
		b.BoxR(CFrame.new(math.cos(angle) * 7, 1.5, z + math.sin(angle) * 7) * CFrame.Angles(0, -angle, 0), 15, 2, 2.6, CARBON, M.Metal)
		b.Ball(math.cos(angle) * 14, 1.5, z + math.sin(angle) * 14, 3, INK, M.Rubber)
	end
	b.Cyl(0, 2.5, z, 3.2, seatY - 8, CHROME, M.Metal)
	b.Cyl(0, seatY - 7, z, 8, 2, CARBON, M.Metal)
	-- assise
	b.Round(0, seatY - 6, z, 30, 6, 28, 3, CARBON, M.Leather)
	b.Box(0, seatY - 5.6, z, 12, 6.8, 27, main, M.Leather) -- (v9.6 : dépasse de 1.2, plus 0.2)
	-- dossier (côté +z), un peu penché vers l'arrière
	local back = CFrame.new(0, seatY, z + 14) * CFrame.Angles(0.12, 0, 0)
	b.BoxR(back * CFrame.new(0, 19, 0), 28, 38, 5, CARBON, M.Leather)
	b.BoxR(back * CFrame.new(0, 17, -2.6), 11, 30, 0.6, main, M.Leather)
	b.BoxR(back * CFrame.new(0, 17, -3.5), 2, 30, 1.2, trim, M.Leather)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(back * CFrame.new(side * 12, 16, -2.5) * CFrame.Angles(0, side * 0.35, 0), 6, 28, 4, main, M.Leather)
		-- accoudoirs
		b.Box(side * 16, seatY - 2, z + 1, 2.4, 9, 2.4, CARBON, M.Metal)
		b.Box(side * 16, seatY + 7, z + 1, 4, 1.6, 14, INK, M.Rubber)
	end
	-- coussin de tête
	b.EggR(back * CFrame.new(0, 34, -3), 14, 6, 4, trim, M.Fabric)
	if glowing then
		local strip = b.BoxR(back * CFrame.new(0, 1, 2.7), 26, 1, 0.4, trim, M.Neon)
		neon(b, strip, "RGB")
	end
	b.Seat(0, seatY, z, 26, 24)
end

----------------------------------------------------------------------
-- 🖥️ BUREAUX GAMER
----------------------------------------------------------------------

-- Disposition des écrans : x, largeur, hauteur, lacet, "Top" (étage), "Curved"
type Slot = { X: number, W: number, H: number, Yaw: number, Top: boolean?, Curved: boolean? }
local LAYOUTS: { [number]: { Slot } } = {
	[1] = { { X = 0, W = 48, H = 28, Yaw = 0 } },
	[2] = { { X = -21.5, W = 40, H = 24, Yaw = 0.2 }, { X = 21.5, W = 40, H = 24, Yaw = -0.2 } },
	[3] = { { X = -34, W = 28, H = 18, Yaw = 0.45 }, { X = 0, W = 36, H = 22, Yaw = 0 }, { X = 34, W = 28, H = 18, Yaw = -0.45 } },
	[4] = { { X = -38, W = 22, H = 15, Yaw = 0.55 }, { X = -12.5, W = 23, H = 14, Yaw = 0.1, Top = true }, { X = 0, W = 34, H = 19, Yaw = 0, Curved = true }, { X = 38, W = 22, H = 15, Yaw = -0.55 } },
	[5] = {
		{ X = -39, W = 22, H = 15, Yaw = 0.55 },
		{ X = -12.5, W = 23, H = 14, Yaw = 0.1, Top = true },
		{ X = 0, W = 34, H = 19, Yaw = 0, Curved = true },
		{ X = 12.5, W = 23, H = 14, Yaw = -0.1, Top = true },
		{ X = 39, W = 22, H = 15, Yaw = -0.55 },
	},
}
local DEFAULT_FEEDS = { "Runner", "Live", "News", "DVD", "Live" }

local DESK_STYLES = {
	{ Edge = PINK, Chair = PINK, Trim = WHITE, Top = CARBON },
	{ Edge = CYAN, Chair = rgb(60, 170, 255), Trim = CYAN, Top = CARBON },
	{ Edge = PURPLE, Chair = PURPLE, Trim = rgb(255, 120, 220), Top = rgb(30, 30, 44) },
	{ Edge = RAINBOW[1], Chair = rgb(255, 70, 140), Trim = CYAN, Top = rgb(24, 24, 34) },
}

-- Tour PC (au sol, sous le bureau) : façade vitrée + ventilateurs lumineux
local function pcTower(b: Builder, x: number, z: number, h: number, glow: Color3, rgbFans: boolean)
	b.Box(x, 0, z, 17, h, 32, CARBON, M.SmoothPlastic)
	-- (v9.6 z-fighting : vitre puis ventilateurs empilés SANS faces confondues :
	-- vitre 16..16.5, anneau 16.5..17.5, moyeu 17.5..18.2, centre 18.2..18.9)
	b.Box(x, 1, z + 16.25, 15, h - 2, 0.5, rgb(60, 70, 96), M.Glass).Transparency = 0.35
	for index = 1, 3 do
		local y = h * (index / 3.6) + 2
		local ring = b.CylZ(x, y, z + 17, 10, 1, rgbFans and RAINBOW[index * 2] or glow, M.Neon)
		neon(b, ring, rgbFans and "RGB" or "Glow")
		b.CylZ(x, y, z + 17.85, 7, 0.7, INK, M.SmoothPlastic)
		b.CylZ(x, y, z + 18.55, 2.4, 0.7, CARBON_LIGHT, M.Metal)
	end
	local power = b.CylZ(x + 5, h - 3, z + 16.9, 2, 0.8, glow, M.Neon)
	neon(b, power, "Glow")
end

local function desk(b: Builder, ctx: any)
	local setup = setupOf(b)
	local tier = math.clamp(tierOf(setup), 1, 4)
	local style = DESK_STYLES[tier]
	local count = math.clamp(math.floor(tonumber(setup.Screens) or tier), 1, 5)
	local feeds = type(setup.Feeds) == "table" and setup.Feeds or {}
	local rgbAll = setup.RGB == true or tier >= 4
	local T = ctx.TopY(1, 50)
	local deskW = tier >= 4 and 100 or 96
	local deskD = 46
	local deskZ = -25 -- centre du plateau (le dos du bureau à z = -48)
	local frame = rgb(28, 28, 38)
	local top = b.Map(style.Top)
	local edge = b.Map(style.Edge)
	-- plateau + chant lumineux
	b.Box(0, T - 3, deskZ, deskW, 3, deskD, top, M.SmoothPlastic)
	b.Box(0, T - 4, deskZ, deskW - 4, 1, deskD - 4, darken(top, 0.3), M.SmoothPlastic) -- (v9.6 : dessous 1 plus bas, plus 0.2)
	local strip = b.Box(0, T - 2.6, deskZ + deskD / 2 + 0.2, deskW - 2, 1.2, 0.6, edge, M.Neon)
	neon(b, strip, rgbAll and "RGB" or "Glow")
	-- tapis de bureau XXL (fin, à l'avant)
	b.Box(0, T, deskZ + 9, deskW - 14, 0.25, 22, rgb(34, 34, 48), M.Fabric)
	if tier >= 3 then
		local matEdge = b.Box(0, T, deskZ + 20.2, deskW - 14, 0.3, 0.5, edge, M.Neon)
		neon(b, matEdge, rgbAll and "RGB" or "Glow")
	end
	-- pieds en "Z" (panneaux latéraux)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (deskW / 2 - 3)
		b.Box(x, 0, deskZ, 3, T - 3, 6, CARBON_LIGHT, M.Metal)
		b.Box(x, 0, deskZ, 4, 2.4, deskD - 4, CARBON, M.Metal)
		b.Box(x, T - 7, deskZ, 4, 3, deskD - 6, CARBON, M.Metal)
		local foot = b.Box(x + side * 0.1, 2.4, deskZ + deskD / 2 - 6, 4.2, 0.6, 2, edge, M.Neon)
		neon(b, foot, rgbAll and "RGB" or "Glow")
	end
	-- goulotte à câbles + lumière sous le bureau
	b.Box(0, T - 9, -44, deskW * 0.6, 4, 6, CARBON, M.Metal)
	if tier >= 2 then
		local under = b.Box(0, T - 4.8, -40, deskW - 12, 0.8, 2, edge, M.Neon)
		neon(b, under, rgbAll and "RGB" or "Glow")
	end
	-- tour PC (au sol, à droite) ; bureau ultime : une seconde à gauche
	pcTower(b, deskW / 2 - 15, -30, math.min(T - 6, 40), edge, rgbAll)
	-- écrans
	local layout = LAYOUTS[count] or LAYOUTS[1]
	local baseY = T + 8
	local monitorZ = -38
	local topY = baseY
	local highest = baseY
	for _, slot in ipairs(layout) do
		if not slot.Top then
			topY = math.max(topY, baseY + slot.H + 3)
		end
	end
	for index, slot in ipairs(layout) do
		local kind = tostring(feeds[index] or DEFAULT_FEEDS[index] or "Runner")
		local y = slot.Top and topY or baseY
		local cf = CFrame.new(slot.X, y, monitorZ) * CFrame.Angles(0, slot.Yaw, 0)
		if slot.Curved and setup.Curved ~= false then
			-- ultra-large incurvé : panneau central + deux ailes tournées vers soi
			-- (v9.6 : pied posé SUR le plateau, plus enfoncé de 0.2 dedans)
			monitor(b, cf, slot.W, slot.H, kind, index, frame, true, y - T - 1.4)
			local wing = 9
			for _, side in ipairs({ -1, 1 }) do
				local a = -side * 0.38
				local inner = CFrame.new(slot.X + side * (slot.W / 2 + 1.4), y, monitorZ)
				local wingCF = inner * CFrame.Angles(0, a, 0) * CFrame.new(side * wing / 2, 0, 0)
				b.BoxR(wingCF * CFrame.new(0, slot.H / 2, 0), wing + 1.4, slot.H + 2.8, 1.6, frame, M.SmoothPlastic)
				local w = b.Part("Part", wingCF * CFrame.new(0, slot.H / 2, 1.05) * CFrame.Angles(0, math.pi, 0), Vector3.new(wing, slot.H, 0.5), rgb(60, 110, 170), M.Neon, "ScreenWing")
				w.CastShadow = false
				w:SetAttribute("ScreenIndex", index)
				table.insert(b.Glows, w)
			end
		else
			monitor(b, cf, slot.W, slot.H, kind, index, frame, not slot.Top, y - T - 1.4)
		end
		highest = math.max(highest, y + slot.H + 1.4)
	end
	-- bras de moniteur (écrans du haut) : mât + traverse
	if count >= 4 then
		b.Box(0, T, monitorZ - 5, 3, topY - T + 8, 3, CHROME, M.Metal)
		b.Box(0, topY + 6, monitorZ - 3.5, 34, 2, 2, CHROME, M.Metal)
		b.Box(0, T, monitorZ - 5, 12, 1.2, 8, frame, M.Metal)
	end
	-- rétroéclairage derrière les écrans
	if tier >= 3 then
		local barTop = count >= 4 and (topY + 16) or (baseY + 24)
		for _, side in ipairs({ -1, 1 }) do
			local bar = b.Box(side * (deskW / 2 - 12), T + 1, -47.4, 1.6, barTop - T - 1, 0.6, edge, M.Neon)
			neon(b, bar, rgbAll and "RGB" or "Glow")
		end
		local beam = b.Box(0, barTop - 1.6, -47.4, deskW - 22, 1.6, 0.6, edge, M.Neon)
		neon(b, beam, rgbAll and "RGB" or "Glow")
	end
	-- déco selon le palier : casque sur son crochet, enceintes, figurine
	if tier >= 2 then
		b.Box(deskW / 2 + 1, T - 12, deskZ + 10, 1.6, 6, 1.6, CHROME, M.Metal)
		House3DKit.Path(b, { { deskW / 2 + 1.5, T - 13, deskZ + 6 }, { deskW / 2 + 1.5, T - 5, deskZ + 7 }, { deskW / 2 + 1.5, T - 5, deskZ + 13 }, { deskW / 2 + 1.5, T - 13, deskZ + 14 } }, 1.4, INK, M.SmoothPlastic)
		for _, dz in ipairs({ 6, 14 }) do
			local cup = b.CylX(deskW / 2 + 1.5, T - 14, deskZ + dz, 5, 2.4, style.Chair, M.Fabric)
			cup.Name = "Casque"
		end
	end
	if tier >= 4 then
		for _, side in ipairs({ -1, 1 }) do
			local x = side * 45
			b.Box(x, T, -44, 7, 14, 7, CARBON, M.SmoothPlastic)
			local ring = b.CylZ(x, T + 9, -40.3, 5.5, 0.6, RAINBOW[side == -1 and 5 or 2], M.Neon)
			neon(b, ring, "RGB")
			b.CylZ(x, T + 9, -40.1, 4, 0.7, INK, M.SmoothPlastic)
			b.CylZ(x, T + 3.4, -40.3, 2.4, 0.6, CARBON_LIGHT, M.Metal)
		end
	end
	-- chaise gamer (devant le bureau, tournée vers les écrans)
	local seatY = math.clamp(T * 0.6, 20, 36)
	gamerChair(b, 26, seatY, b.Map(style.Chair), style.Trim, tier >= 3)
	-- (dessus libre = l'avant du plateau : clavier, souris, plantes)
	b.Top(1, 0, T, deskZ + 11, deskW - 10, 22)
	local height = count >= 4 and math.max(highest, topY + 8) or highest
	b.Footprint(deskW, 96, math.max(height, T + 30))
end

R.SetupDeskSolo = desk
R.SetupDeskDuo = desk
R.SetupDeskTrio = desk
R.SetupDeskUltra = desk

----------------------------------------------------------------------
-- ⌨️ CLAVIER MÉCANIQUE RGB (v9.8 : refait)
-- Cause du clavier "cassé" (v9.5 -> v9.7) : à cette échelle (1 unité ≈
-- 0,02 stud) la plaque "KeyboardBase" de 0,6 unité était gonflée à
-- l'épaisseur minimale (0,03 stud) puis encore poussée par l'anti-
-- scintillement (House3DKit.Separate) AU-DESSUS des touches : seules la
-- barre d'espace et les grandes touches dépassaient. Ici chaque couche
-- fait au moins l'épaisseur minimale et deux faces parallèles de couleurs
-- différentes sont toujours à plus de 0,03 stud l'une de l'autre.
-- Clavier 65 % : 5 rangées de 15 unités de touche, flèches, touches larges ;
-- légendes posées par LiveProps (une SurfaceGui par touche, seulement de
-- près) grâce à l'attribut "Legend" ; plaque RGB entre les touches (douce,
-- pas de néon) + fin liseré lumineux sous le boîtier.
----------------------------------------------------------------------

-- { nom, légende, largeur (unités de touche), style } ; style : "A" lettre,
-- "M" modificateur, "X" accent
local KEY_LAYOUT: { { any } } = {
	{ { "Grave", "`" }, { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "0" }, { "Minus", "-" }, { "Equals", "=" }, { "Backspace", "⌫", 2, "M" } },
	{ { "Tab", "Tab", 1.5, "M" }, { "Q" }, { "W" }, { "E" }, { "R" }, { "T" }, { "Y" }, { "U" }, { "I" }, { "O" }, { "P" }, { "LBracket", "[" }, { "RBracket", "]" }, { "Backslash", "\\", 1.5, "M" } },
	{ { "Caps", "Caps", 1.75, "M" }, { "A" }, { "S" }, { "D" }, { "F" }, { "G" }, { "H" }, { "J" }, { "K" }, { "L" }, { "Semicolon", ";" }, { "Quote", "'" }, { "Enter", "Enter", 2.25, "X" } },
	{ { "LShift", "Shift", 2.25, "M" }, { "Z" }, { "X" }, { "C" }, { "V" }, { "B" }, { "N" }, { "M" }, { "Comma", "," }, { "Period", "." }, { "Slash", "/" }, { "RShift", "Shift", 1.75, "M" }, { "Up", "▲", 1, "X" } },
	{ { "LCtrl", "Ctrl", 1.25, "M" }, { "Win", "◆", 1.25, "M" }, { "LAlt", "Alt", 1.25, "M" }, { "Space", "", 6.25, "A" }, { "RAlt", "Alt", 1, "M" }, { "Fn", "Fn", 1, "M" }, { "Left", "◀", 1, "X" }, { "Down", "▼", 1, "X" }, { "Right", "▶", 1, "X" } },
}
House3DSetup.KeyLayout = KEY_LAYOUT

R.SetupKeyboard = function(b, _ctx)
	local caseColor = b.Map(rgb(46, 48, 64))
	local rimColor = caseColor -- (même teinte que le bac : aucune face confondue de couleur différente)
	local alpha = b.Map(rgb(246, 242, 234))
	local modifier = b.Map(rgb(112, 108, 150))
	local accent = b.Map(rgb(255, 104, 170))
	local w, d = 100, 44
	local U = 6 -- une unité de touche
	local gap = 0.9
	local layer = th(b, 2.2)
	-- (règle anti-scintillement : deux faces parallèles, tournées du même
	-- côté, de couleurs différentes, qui se recouvrent -> au moins 0,03 stud
	-- d'écart ; sinon House3DKit.Separate déforme les pièces)
	local clear = th(b, 1.4, 0.031)
	-- boîtier (bac arrondi) + liseré lumineux dessous (doux, en retrait)
	local trayH = 5
	b.Round(0, 0, 0, w, trayH, d, 3, caseColor, M.SmoothPlastic)
	local glowY = clear
	local glow = b.Box(0, glowY, 0, w + clear * 2, th(b, 1.6), d + clear * 2, RAINBOW[5], M.Neon)
	neon(b, glow, "RGB")
	glow.Transparency = 0.45
	-- plaque (couleur RGB animée, SmoothPlastic : lueur douce entre les touches)
	local plateTop = trayH + clear
	local plateBottom = plateTop - layer
	local plateW, plateD = 90 + clear * 2 + 0.9, 30 + clear * 2 + 0.9
	named(b.Box(0, plateBottom, 0, plateW, layer, plateD, rgb(120, 90, 255), M.SmoothPlastic), "RGB").CastShadow = false
	-- rebord du boîtier (4 baguettes au-dessus de la plaque, même teinte que le bac)
	local rimH = math.max(th(b, 2.8), plateTop - plateBottom + clear)
	local rimTop = plateBottom + rimH
	local rimW = 2
	b.Box(0, plateBottom, d / 2 - rimW / 2, w, rimH, rimW, rimColor, M.SmoothPlastic)
	b.Box(0, plateBottom, -d / 2 + rimW / 2, w, rimH, rimW, rimColor, M.SmoothPlastic)
	b.Box(-w / 2 + rimW / 2, plateBottom, 0, rimW, rimH, d - rimW * 2 + 0.4, rimColor, M.SmoothPlastic)
	b.Box(w / 2 - rimW / 2, plateBottom, 0, rimW, rimH, d - rimW * 2 + 0.4, rimColor, M.SmoothPlastic)
	-- touches (le bas des touches est pris dans la plaque : aucune face confondue)
	local keyBottom = plateTop - math.min(0.5, layer - clear)
	local keyH = math.max(4, rimTop - keyBottom + 2.2)
	for rowIndex, row in ipairs(KEY_LAYOUT) do
		local z = -12 + (rowIndex - 1) * U -- rangée 1 au fond, espace devant
		local cursor = -45
		for _, spec in ipairs(row) do
			local id = spec[1]
			local legend = spec[2] or id
			local width = tonumber(spec[3]) or 1
			local style = spec[4] or "A"
			local x = cursor + width * U / 2
			cursor += width * U
			local color = style == "M" and modifier or (style == "X" and accent or alpha)
			-- rangée du fond un peu plus haute (profil "sculpté")
			local lift = (rowIndex == 1 and 0.5) or (rowIndex == 5 and -0.3) or 0
			local key = b.Box(x, keyBottom, z, width * U - gap, keyH + lift, U - gap, color, M.SmoothPlastic)
			key.Name = "Key_" .. id
			key:SetAttribute("Legend", legend)
			key:SetAttribute("KeyStyle", style)
		end
	end
	-- molette de volume (sur le rebord arrière droit) + diode
	b.Cyl(w / 2 - 7, rimTop - 1, -d / 2 + rimW / 2, 3.6, 2.6, CHROME, M.Metal)
	neon(b, b.Ball(w / 2 - 14, rimTop - 0.3, -d / 2 + rimW / 2, 1.6, MINT, M.Neon), "Glow")
	-- câble tressé vers l'arrière
	House3DKit.Path(b, { { -20, 3, -d / 2 - 0.5 }, { -22, 2, -d / 2 - 8 }, { -30, 1.6, -d / 2 - 14 } }, 2.2, INK, M.Fabric)
	b.Footprint(w, d, rimTop + keyH)
end

----------------------------------------------------------------------
-- 🖱️ SOURIS GAMING + TAPIS
----------------------------------------------------------------------

R.SetupMouse = function(b, _ctx)
	local body = b.Map(rgb(36, 36, 50))
	-- tapis (bord lumineux)
	-- (v9.6 z-fighting : tapis de 4 d'épaisseur (le tapis du bureau fait
	-- 0,03 stud : le dessus du tapis de souris est maintenant bien au-dessus),
	-- autocollant de 2 ; la souris posée dessus (+2.6))
	local pad = 4
	b.Round(0, 0, 0, 100, pad, 76, 5, rgb(30, 30, 42), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		-- (bords lumineux épais de 3 : l'épaisseur mini des pièces (0,03 stud)
		-- ne les ramène plus sur les faces du tapis)
		neon(b, b.Box(0, 0.2, side * 40, 94, pad - 1.4, 3, RAINBOW[5], M.Neon), "RGB")
		neon(b, b.Box(side * 52, 0.2, 0, 3, pad - 1.4, 70, RAINBOW[1], M.Neon), "RGB")
	end
	b.Box(-30, pad, -26, 22, 2, 10, rgb(255, 92, 170), M.SmoothPlastic)
	-- souris
	local mx, mz = 12, 4
	local up = pad - 1.4
	named(b.Egg(mx, 7 + up, mz + 3, 30, 14, 46, body, M.SmoothPlastic), "MouseBody")
	b.Box(mx, pad, mz + 3, 22, 3, 36, body, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		local button = b.BoxR(CFrame.new(mx + side * 6.6, 12.4 + up, mz - 9) * CFrame.Angles(0.22, 0, 0), 12, 2, 18, lighten(body, 0.12), M.SmoothPlastic)
		button.Name = side == -1 and "MouseLeft" or "MouseRight"
		b.BoxR(CFrame.new(mx + side * 14.4, 8 + up, mz + 2) * CFrame.Angles(0, 0, side * 0.35), 1.2, 6, 24, CARBON_LIGHT, M.Rubber)
	end
	local wheel = b.CylX(mx, 13.6 + up, mz - 10, 5, 3, RAINBOW[6], M.Neon)
	neon(b, wheel, "MouseWheel")
	local logo = b.Ball(mx, 12.2 + up, mz + 14, 4.5, RAINBOW[5], M.Neon)
	neon(b, logo, "RGB")
	-- câble (tressé) vers l'arrière
	House3DKit.Path(b, { { mx, 4 + up, mz - 20 }, { mx - 4, 2.2 + up, mz - 30 }, { mx - 20, 2 + up, -36 }, { mx - 30, 2 + up, -40 } }, 1.6, INK, M.Fabric)
	b.Footprint(100, 76, 16 + up)
end

----------------------------------------------------------------------
-- 📺 TÉLÉS (logo DVD) + MEUBLE TÉLÉ + ÉCRAN D'INFOS
----------------------------------------------------------------------

-- v9.8 📺 Télés "10x" : dalle ultra-fine aux coins arrondis, bords fins,
-- dos bombé, pieds / supports réalistes, barre de son, halo doux pour les
-- grandes, écran de cinéma (projecteur au plafond + toile). Les épaisseurs
-- suivent l'échelle (th) : aucune couche plus fine que 0,03 stud, aucune
-- face confondue (l'écran dépasse de 0,03 stud du cadre).

-- Bloc aux coins arrondis dans le plan de l'image (arêtes le long de Z) ;
-- `cf` = centre du bloc
local function roundRectZ(b: Builder, cf: CFrame, w: number, h: number, d: number, r: number, color: Color3, material: Enum.Material?)
	r = math.clamp(r, 0.3, math.min(w, h) / 2 - 0.05)
	local main = b.BoxR(cf, w - 2 * r, h, d, color, material)
	b.BoxR(cf, w, h - 2 * r, d, color, material)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			local corner = b.Part("Part", cf * CFrame.new(sx * (w / 2 - r), sy * (h / 2 - r), 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(d, 2 * r, 2 * r), color, material, "Cylindre")
			;(corner :: Part).Shape = Enum.PartType.Cylinder
		end
	end
	return main
end

type Panel = { W: number, H: number, Back: number, Screen: BasePart }

-- Dalle 16:9 : `cf` = bas-centre de la FACE AVANT du cadre ; renvoie ses mesures
local function tvPanel(b: Builder, cf: CFrame, w: number, kind: string, frameColor: Color3): Panel
	local h = w * 9 / 16
	local bezel = math.max(1.1, w * 0.011)
	local chin = bezel * 2.4
	local depth = th(b, 2.2)
	local bulge = th(b, 2.6)
	local gap = th(b, 0, 0.032)
	local W, H = w + bezel * 2, h + bezel + chin
	roundRectZ(b, cf * CFrame.new(0, H / 2, -depth / 2), W, H, depth, math.max(1.4, w * 0.018), frameColor, M.SmoothPlastic)
	-- dos bombé (électronique) : en partie pris dans la dalle
	roundRectZ(b, cf * CFrame.new(0, H * 0.52, -depth - bulge * 0.35), W * 0.7, H * 0.62, bulge, math.max(2, w * 0.05), darken(frameColor, 0.14), M.SmoothPlastic)
	-- écran : sa face avant à 0,03 stud devant le cadre
	local screenDepth = th(b, 0.8)
	local screen = screenPart(b, cf * CFrame.new(0, chin, gap - screenDepth / 2), w, h, kind, 1, screenDepth)
	-- logo de la marque + diode (dans le menton, même plan que l'écran)
	b.BoxR(cf * CFrame.new(0, chin / 2, gap - screenDepth / 2), math.min(10, w * 0.07), chin * 0.28, screenDepth, CHROME, M.Metal)
	neon(b, b.BoxR(cf * CFrame.new(w / 2 - 2, chin / 2, gap - screenDepth / 2), 1.2, chin * 0.24, screenDepth, RED, M.Neon), "Glow")
	return { W = W, H = H, Back = depth + bulge * 0.85, Screen = screen }
end

-- Barre de son (bouts arrondis, grille en tissu, diode) ; `z` = face arrière
local function soundbar(b: Builder, x: number, y: number, z: number, w: number)
	local h = 5
	local d = 6.5
	local r = h / 2
	b.Box(x, y, z + d / 2, w - h, h, d, CARBON, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		-- (cylindre couché avant-arrière : bouts arrondis vus de face)
		local cap = b.Part("Part", CFrame.new(x + side * (w / 2 - r), y + r, z + d / 2) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(d, h, h), CARBON, M.SmoothPlastic, "Cylindre")
		;(cap :: Part).Shape = Enum.PartType.Cylinder
	end
	-- grille (tissu) : devant la barre, un peu en retrait des bouts
	local fabric = th(b, 1)
	b.Box(x, y + 0.6, z + d + fabric / 2 - fabric * 0.4, w - h - 2, h - 1.2, fabric, rgb(62, 62, 78), M.Fabric)
	neon(b, b.Box(x + w * 0.3, y + h - 0.2, z + d * 0.5, 2.4, th(b, 0.6), 1.2, CYAN, M.Neon), "Glow")
end

-- 🎬 Écran de cinéma : toile déroulante + projecteur accroché au plafond
local function cinema(b: Builder, setup: { [string]: any }, kind: string)
	local w = 94 * math.clamp(tonumber(setup.Scale) or 2.2, 1, 3)
	local h = w * 9 / 16
	local border = math.max(3, w * 0.025)
	local W, H = w + border * 2, h + border * 2
	local t = th(b, 1.2)
	local gap = th(b, 0, 0.032)
	local y0 = 6
	-- fond noir (bordure de la toile)
	b.Box(0, y0, 2 + t / 2, W, H, t, rgb(20, 20, 26), M.Fabric)
	-- toile blanche (l'écran) : 0,03 stud devant le fond
	local screenDepth = th(b, 0.8)
	screenPart(b, CFrame.new(0, y0 + border, 2 + t + gap - screenDepth / 2), w, h, kind, 1, screenDepth).Material = M.Fabric
	-- carter du rouleau (en haut) + barre de lestage (en bas) + tirette
	local top = y0 + H
	b.CylX(0, top + 3.2, 4, 7, W + 8, rgb(236, 236, 244), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.CylX(side * (W / 2 + 4.6), top + 3.2, 4, 8, 1.4, CARBON, M.SmoothPlastic)
		b.Box(side * (W / 2 + 2), top + 1, 0, 3, 6, 4, CARBON_LIGHT, M.Metal)
	end
	b.CylX(0, y0 - 1.4, 2 + t / 2, 2.8, W + 2, CARBON, M.Metal)
	House3DKit.Path(b, { { 0, y0 - 2.4, 2 + t / 2 }, { 0, y0 - 9, 2 + t / 2 } }, 0.8, INK, M.Fabric)
	b.Ball(0, y0 - 10, 2 + t / 2, 2.6, CARBON, M.SmoothPlastic)
	-- projecteur au plafond (devant la toile, objectif tourné vers elle)
	local pz = math.max(60, w * 0.45)
	local py = top + 6
	b.Cyl(0, py + 12, pz, 12, th(b, 1.4), rgb(236, 236, 244), M.SmoothPlastic) -- platine de plafond
	b.Cyl(0, py + 6, pz, 2, 7, CHROME, M.Metal)
	b.Round(0, py - 4, pz, 28, 10, 24, 3, rgb(244, 244, 250), M.SmoothPlastic)
	b.Box(0, py - 4.6, pz, 20, th(b, 1), 18, CARBON_LIGHT, M.SmoothPlastic) -- dessous
	b.CylZ(-6, py + 1, pz - 12.6, 7, 2.4, CARBON, M.Metal)
	neon(b, b.CylZ(-6, py + 1, pz - 13.8 - th(b, 0.4) / 2, 4.4, th(b, 0.4), rgb(200, 230, 255), M.Neon), "Glow")
	for index = 0, 3 do
		b.Box(6 + index * 3, py + 3, pz + 12 + th(b, 0.6) / 2, 1.6, 4, th(b, 0.6), CARBON, M.SmoothPlastic)
	end
	neon(b, b.Ball(10, py + 6.2, pz - 8, 1.4, MINT, M.Neon), "Glow")
	b.Footprint(W + 12, 14, 100)
end

local function tvRecipe(b: Builder, _ctx: any)
	local setup = setupOf(b)
	local rank = sizeRank(setup)
	local scale = math.clamp(tonumber(setup.Scale) or 1, 1, 3)
	local frameColor = rank >= 3 and rgb(26, 26, 34) or b.Map(rgb(40, 40, 54))
	local feeds = type(setup.Feeds) == "table" and setup.Feeds or {}
	local kind = tostring(feeds[1] or "DVD")
	if setup.Cinema == true then
		cinema(b, setup, kind)
		return
	end
	local w = 94 * scale
	local h = w * 9 / 16
	local big = rank >= 4 or scale > 1
	if tostring(setup.Mount) == "Wall" then
		-- au mur : platine fine + bras (moyenne) ; la dalle presque contre le mur
		local armed = rank <= 2 and not big
		local plate = th(b, 1.2)
		local front = armed and 12 or 7.5
		local H = h + math.max(1.1, w * 0.011) * 3.4
		local y0 = math.max(4, 50 - H / 2)
		b.Box(0, y0 + H * 0.3, plate / 2, 26, 22, plate, CARBON_LIGHT, M.Metal)
		if armed then
			-- bras articulé (2 segments + rotules)
			House3DKit.Path(b, { { 0, y0 + H * 0.42, plate }, { -8, y0 + H * 0.46, front * 0.55 }, { 0, y0 + H * 0.5, front - 3.5 } }, 2.6, STEEL, M.Metal)
		else
			for _, side in ipairs({ -1, 1 }) do
				b.Box(side * 9, y0 + H * 0.34, plate, 3, 3, front - 3 - plate, STEEL, M.Metal)
			end
		end
		if big then
			-- halo doux derrière la télé (entre la télé et le mur)
			local halo = b.Box(0, y0 - 3, plate + th(b, 0.8), w + 10, H + 6, th(b, 0.4), CYAN, M.Neon)
			neon(b, halo, "Ambilight")
			halo.Transparency = 0.6
		end
		tvPanel(b, CFrame.new(0, y0, front), w, kind, frameColor)
		if rank >= 3 or big then
			soundbar(b, 0, y0 - 8.5, plate + 1, math.min(w * 0.7, 110))
			b.Box(0, y0 - 4, plate, 18, 1.4, 3, STEEL, M.Metal)
		end
		b.Footprint(w + 6, 14, 100)
		return
	end
	if big then
		-- grande sur pied : deux mâts de studio + barre de son
		local y0 = 24
		local panelBack = -3.4
		local legX = math.min(w * 0.3, 44)
		for _, side in ipairs({ -1, 1 }) do
			b.Cyl(side * legX, 2, panelBack - 4, 3.2, y0 + h * 0.6, CHROME, M.Metal)
			b.Round(side * legX, 0, panelBack - 2, 12, th(b, 2), 30, 3, CARBON, M.Metal)
		end
		b.Box(0, y0 + h * 0.3, panelBack - 4.6, legX * 2 + 4, 3, 2.6, CARBON_LIGHT, M.Metal)
		local halo = b.Box(0, y0 - 2, panelBack - 7.5, w + 8, h + 8, th(b, 0.4), CYAN, M.Neon)
		neon(b, halo, "Ambilight")
		halo.Transparency = 0.6
		tvPanel(b, CFrame.new(0, y0, 0), w, kind, frameColor)
		soundbar(b, 0, 3.4, 8, math.min(w * 0.75, 120))
		-- caisson de basses à côté
		b.Round(legX + 18, 0, 6, 16, 16, 16, 2.5, CARBON, M.SmoothPlastic)
		b.CylZ(legX + 18, 8, 14 + th(b, 0.8) / 2, 10, th(b, 0.8), rgb(56, 56, 70), M.Fabric)
		b.Footprint(math.max(w + 6, 100), 34, y0 + h + 8)
		return
	end
	-- petite / moyenne / grande sur meuble : pied central (petite, grande) ou lames (moyenne)
	local y0 = rank == 3 and 8 or 7
	if rank == 2 then
		for _, side in ipairs({ -1, 1 }) do
			local x = side * w * 0.36
			b.BoxR(CFrame.new(x, y0 * 0.5, -2) * CFrame.Angles(0, 0, side * 0.32), 2.2, y0 + 2.5, 3.2, CHROME, M.Metal)
			b.Round(x + side * 2, 0, -1, 9, th(b, 1.2), 14, 2, CHROME, M.Metal)
		end
	else
		b.Box(0, 0.8, -4.2, 7, y0 + 6, th(b, 1.6), CHROME, M.Metal)
		b.Round(0, 0, -2, rank == 3 and 40 or 30, th(b, 1.4), 14, 5, CARBON_LIGHT, M.Metal)
	end
	tvPanel(b, CFrame.new(0, y0, 0), w, kind, frameColor)
	if rank >= 3 then
		soundbar(b, 0, 0, 5, w * 0.6)
	end
	b.Footprint(100, rank >= 3 and 24 or 18, y0 + h + 5)
end

R.SetupTVSmall = tvRecipe
R.SetupTVMedium = tvRecipe
R.SetupTVLarge = tvRecipe
R.SetupTVGiant = tvRecipe
R.SetupTVWallMedium = tvRecipe
R.SetupTVWallLarge = tvRecipe
R.SetupTVWallGiant = tvRecipe

R.SetupNewsTV = function(b, _ctx)
	-- écran mural "Breaking news" : cadre rouge, bandeau lumineux
	b.Box(0, 44, 2, 26, 14, 4, CARBON_LIGHT, M.Metal)
	local w = 92
	local h = w * 9 / 16
	local y0 = 50 - h / 2 - 2
	b.Box(0, y0 - 2, 5, w + 6, h + 8, 2.4, rgb(40, 14, 24), M.SmoothPlastic)
	-- (v9.6 z-fighting : bandeaux 1 plus larges et 0.5 plus épais que le cadre)
	neon(b, b.Box(0, y0 - 3.2, 5, w + 8, 1.2, 4.4, RED, M.Neon), "Glow")
	neon(b, b.Box(0, y0 + h + 6, 5, w + 8, 1.2, 4.4, RED, M.Neon), "Glow")
	screenPart(b, CFrame.new(0, y0 + 2, 6.45), w, h, "News", 1)
	-- voyant "ON AIR" au-dessus
	local lamp = b.Round(0, y0 + h + 7, 4, 22, 5, 3, 1.5, RED, M.Neon)
	neon(b, lamp, "OnAir")
	b.Footprint(w + 8, 10, 100)
end

R.SetupTVStand = function(b, ctx)
	local T = ctx.TopY(1, 45)
	local body = b.Map(rgb(46, 42, 62))
	local d = 40
	-- pieds + caisson
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 44, 0, 0, 4, 6, 30, CARBON_LIGHT, M.Metal)
	end
	local inner = T - 9
	-- (v9.6 z-fighting : flancs plus larges que les plateaux (±50.5), cloisons
	-- posées SUR le plateau bas, fond en retrait : aucune face confondue)
	b.Box(0, 6, 0, 100, 3, d, body, M.Wood)
	b.Box(0, 6.5, -d / 2 + 2.5, 99, inner - 0.5, 2, darken(body, 0.2), M.Wood)
	for _, x in ipairs({ -49, 49 }) do
		b.Box(x, 5.5, 0, 3, inner + 0.5, d - 1, body, M.Wood)
	end
	for _, x in ipairs({ -14.5, 14.5 }) do
		b.Box(x, 9, 0, 3, inner - 3, d - 1, body, M.Wood)
	end
	b.Box(0, T - 3, 0, 100, 3, d + 1, darken(body, 0.25), M.SmoothPlastic)
	-- portes pleines (côtés) + niche ouverte au centre
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 31.5, 9, d / 2 - 0.6, 31, inner - 6, 1.2, lighten(body, 0.12), M.Wood)
		b.Box(side * 31.5, 10.5, d / 2 + 0.3, 27, inner - 9, 0.6, lighten(body, 0.2), M.Wood)
		b.Box(side * 17.5, 9 + (inner - 6) / 2 - 3, d / 2 + 0.4, 1, 6, 1, CHROME, M.Metal)
	end
	b.Box(0, 9, 0, 26, 0.6, d - 4, rgb(24, 22, 34), M.SmoothPlastic)
	neon(b, b.Box(0, T - 3.6, d / 2 - 3, 26, 0.5, 0.5, CYAN, M.Neon), "Glow")
	-- console + manettes + boîtiers de DVD dans la niche
	b.Round(0, 9.6, d / 2 - 10, 20, 5, 14, 2, WHITE, M.SmoothPlastic)
	neon(b, b.Box(0, 12, d / 2 - 2.9, 8, 0.6, 0.4, CYAN, M.Neon), "Glow")
	b.EggR(CFrame.new(-6, 10.5, d / 2 - 1) * CFrame.Angles(0, 0.3, 0), 8, 3, 5, rgb(255, 120, 190), M.SmoothPlastic)
	b.Box(0, 9 + inner * 0.5, 0, 26, 0.8, d - 4, rgb(40, 36, 54), M.SmoothPlastic)
	for index = 1, 6 do
		b.Box(-10 + index * 3, 9.8 + inner * 0.5, 2, 2.4, 11, 13, RAINBOW[index], M.SmoothPlastic)
	end
	-- bande lumineuse au pied (arc-en-ciel)
	neon(b, b.Box(0, 6.2, d / 2 + 0.3, 96, 1, 0.6, RAINBOW[1], M.Neon), "RGB")
	b.Top(1, 0, T, 0, 94, 34)
	b.Footprint(100, d, T)
end

----------------------------------------------------------------------
-- 🎧 CHAÎNES HI-FI (lofi)
----------------------------------------------------------------------

-- Boutons lecture / suivant (dessus d'un appareil)
local function transport(b: Builder, x: number, y: number, z: number, scale: number)
	b.Box(x, y, z, 15 * scale, 1, 7 * scale, INK, M.SmoothPlastic)
	local play = b.Box(x - 3.6 * scale, y + 1, z, 6 * scale, 2 * scale, 5 * scale, rgb(90, 220, 140), M.SmoothPlastic)
	play.Name = "PlayButton"
	local nextButton = b.Box(x + 3.6 * scale, y + 1, z, 6 * scale, 2 * scale, 5 * scale, rgb(110, 170, 255), M.SmoothPlastic)
	nextButton.Name = "NextButton"
end

-- Barres de niveau (VU) : `count` barres lumineuses, bas à `y` ; `z` = face
-- sur laquelle on les monte (v9.6 z-fighting : fond z..z+1.4, barres
-- z+1.4..z+2.8 : même dans un petit objet, faces à plus de 0,02 stud)
local function vuBars(b: Builder, x: number, y: number, z: number, w: number, h: number, count: number)
	b.Box(x, y - 1, z + 0.7, w + 2, h + 2, 1.4, INK, M.SmoothPlastic)
	local step = w / count
	for index = 1, count do
		local color = index <= count * 0.6 and MINT or (index <= count * 0.85 and YELLOW or RED)
		local bar = b.Box(x - w / 2 + step * (index - 0.5), y, z + 2.1, step * 0.6, h, 1.4, color, M.Neon)
		neon(b, bar, "VU_" .. index)
	end
end

-- Haut-parleur (face +z) : caisson, membranes qui battent
local function speaker(b: Builder, x: number, y: number, z: number, w: number, h: number, d: number, body: Color3, cones: number)
	b.Round(x, y, z, w, h, d, 1.5, body, M.Wood)
	-- (v9.6 z-fighting : grille, anneau, membrane, cache empilés sans faces
	-- confondues : d/2..+0.8, +0.8..+1.6, +1.6..+2.4, +2.4..+3)
	b.Box(x, y + 1, z + d / 2 + 0.4, w - 3, h - 2, 0.8, rgb(40, 40, 52), M.Fabric)
	for index = 1, cones do
		local cy = y + h * (index - 0.4) / (cones + 0.2)
		local size = math.min(w - 5, h / cones - 2) * (index == cones and 1 or 0.62)
		b.CylZ(x, cy, z + d / 2 + 1.2, size + 1.4, 0.8, CHROME, M.Metal)
		named(b.CylZ(x, cy, z + d / 2 + 2, size, 0.8, rgb(30, 30, 40), M.SmoothPlastic), "SpeakerCone")
		b.CylZ(x, cy, z + d / 2 + 2.7, size * 0.34, 0.6, rgb(70, 70, 86), M.SmoothPlastic)
	end
end

-- Platine : plateau + disque (tourne) + bras
local function turntable(b: Builder, x: number, y: number, z: number, w: number, d: number, plinth: Color3)
	b.Round(x, y, z, w, 5, d, 2, plinth, M.Wood)
	b.Box(x, y + 5, z, w - 2, 0.4, d - 2, rgb(30, 30, 40), M.Metal)
	local cx = x - w * 0.12
	local diameter = math.min(w * 0.7, d - 5)
	b.Cyl(cx, y + 5.2, z, diameter + 1, 1, CHROME, M.Metal)
	pivot(b, "Pivot_Vinyl", cx, y + 6.2, z)
	named(b.Cyl(cx, y + 6.2, z, diameter, 0.6, rgb(20, 20, 26), M.SmoothPlastic), "Vinyl")
	-- (v9.6 z-fighting : étiquette SUR le disque (6.8..7.2), repères au-dessus)
	named(b.Cyl(cx, y + 6.8, z, diameter * 0.36, 0.4, rgb(255, 90, 120), M.SmoothPlastic), "Vinyl")
	-- repère sur l'étiquette (on voit le disque tourner)
	named(b.Box(cx + diameter * 0.1, y + 7.2, z, diameter * 0.12, 0.3, 1.6, CREAM, M.SmoothPlastic), "Vinyl")
	named(b.Box(cx - diameter * 0.32, y + 6.8, z, diameter * 0.1, 0.4, 1.2, rgb(60, 60, 72), M.SmoothPlastic), "Vinyl")
	b.Cyl(cx, y + 6.6, z, 1, 1.4, CHROME, M.Metal)
	-- bras de lecture
	local ax, az = x + w * 0.36, z - d * 0.3
	b.Cyl(ax, y + 5, az, 4, 3, CHROME, M.Metal)
	House3DKit.Path(b, { { ax, y + 8, az }, { ax - 2, y + 8, z + d * 0.1 }, { cx + diameter * 0.3, y + 7.6, z + d * 0.18 } }, 1, CHROME, M.Metal, false, true)
	b.Box(cx + diameter * 0.3, y + 6.8, z + d * 0.18, 2, 1, 3, INK, M.SmoothPlastic)
end

-- Petit écran LCD (morceau en cours) ; `z` = face de montage (v9.6 : cadre
-- z..z+1.4, écran z+1.4..z+1.9)
local function lcd(b: Builder, x: number, y: number, z: number, w: number, h: number)
	b.Box(x, y - 0.8, z + 0.7, w + 1.6, h + 1.6, 1.4, INK, M.SmoothPlastic)
	screenPart(b, CFrame.new(x, y, z + 1.65), w, h, "Music", 1)
end

local function hifi(b: Builder, _ctx: any)
	local setup = setupOf(b)
	local tier = math.clamp(tierOf(setup), 1, 4)
	if tier == 1 then
		-- radio-cassette rétro
		local body = b.Map(rgb(255, 140, 180))
		b.Round(0, 0, 0, 100, 48, 30, 5, body, M.SmoothPlastic)
		-- (v9.6 z-fighting : petit objet (~0,02 stud / unité, épaisseur mini
		-- 0,03) -> façade 15..16.4 puis couches de 1,4 : anneau, tissu, membrane,
		-- cache ; fenêtre, bobines, repères)
		b.Box(0, 4, 15.7, 94, 40, 1.4, darken(body, 0.2), M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			b.CylZ(side * 29, 24, 17.1, 36, 1.4, CHROME, M.Metal)
			b.CylZ(side * 29, 24, 18.5, 32, 1.4, rgb(40, 40, 52), M.Fabric)
			named(b.CylZ(side * 29, 24, 19.9, 22, 1.4, rgb(30, 30, 40), M.SmoothPlastic), "SpeakerCone")
			b.CylZ(side * 29, 24, 21.3, 8, 1.4, CHROME, M.Metal)
		end
		-- fenêtre de la cassette + bobines
		b.Box(0, 20, 17.1, 22, 16, 1.4, rgb(60, 50, 80), M.Glass).Transparency = 0.2
		for _, side in ipairs({ -1, 1 }) do
			pivot(b, side == -1 and "Pivot_Spool1" or "Pivot_Spool2", side * 5.5, 28, 18.5)
			named(b.CylZ(side * 5.5, 28, 18.5, 6, 1.4, WHITE, M.SmoothPlastic), side == -1 and "Spool1" or "Spool2")
			named(b.Box(side * 5.5, 28, 19.9, 5.4, 1, 1.4, INK, M.SmoothPlastic), side == -1 and "Spool1" or "Spool2")
		end
		vuBars(b, 0, 8, 16.4, 20, 7, 5)
		lcd(b, 0, 38, 16.4, 24, 6)
		-- poignée
		House3DKit.Path(b, { { -34, 48, 0 }, { -30, 60, 0 }, { 30, 60, 0 }, { 34, 48, 0 } }, 3, CHROME, M.Metal)
		transport(b, -14, 48, 4, 1)
		b.CylZ(38, 52, 0, 1.4, 2, CHROME, M.Metal)
		House3DKit.Path(b, { { 38, 48, 0 }, { 40, 70, -2 } }, 1, CHROME, M.Metal)
		b.Footprint(100, 30, 62)
		return
	end
	if tier == 2 then
		-- mini chaîne CD : lecteur à chargement par le dessus + 2 enceintes
		local body = b.Map(rgb(210, 214, 232))
		b.Round(0, 0, 0, 40, 44, 34, 3, body, M.SmoothPlastic)
		b.Box(0, 44, 0, 38, 0.6, 32, darken(body, 0.2), M.Metal)
		-- CD sous le couvercle transparent
		pivot(b, "Pivot_Vinyl", 0, 44.8, 0)
		named(b.Cyl(0, 44.8, 0, 26, 0.4, rgb(220, 230, 255), M.Glass), "Vinyl")
		named(b.Box(6, 45.2, 0, 8, 0.2, 3, rgb(255, 120, 200), M.Neon), "Vinyl")
		named(b.Box(-7, 45.2, 3, 6, 0.2, 2, rgb(120, 220, 255), M.Neon), "Vinyl")
		local lid = b.Cyl(0, 44.9, 0, 30, 3, rgb(200, 230, 255), M.Glass)
		lid.Transparency = 0.6
		lcd(b, 0, 30, 17, 30, 8)
		vuBars(b, 0, 20, 17, 28, 6, 7)
		b.CylZ(-12, 10, 17.2, 8, 1.6, CHROME, M.Metal)
		transport(b, 6, 8, 17, 1)
		for _, side in ipairs({ -1, 1 }) do
			speaker(b, side * 38, 0, 0, 22, 40, 26, b.Map(WOOD_DARK), 2)
		end
		b.Footprint(100, 34, 50)
		return
	end
	if tier == 3 then
		-- meuble bas en bois + platine vinyle + ampli + enceintes sur pieds
		local wood = b.Map(WOOD)
		b.Box(0, 0, 0, 56, 36, 34, wood, M.Wood)
		b.Box(0, 36, 0, 58, 2, 36, darken(wood, 0.2), M.Wood)
		-- ampli (façade + VU + boutons) dans le meuble
		b.Box(0, 20, 17, 48, 13, 2, rgb(34, 32, 40), M.Metal)
		vuBars(b, -10, 23, 18, 20, 7, 8)
		b.CylZ(12, 26.5, 18.7, 7, 1.4, CHROME, M.Metal)
		transport(b, 14, 21, 17.5, 0.9)
		-- bac à vinyles (pochettes colorées)
		for index = 1, 7 do
			b.Box(-22 + index * 5.5, 3, 12, 1.2, 14, 14, RAINBOW[(index - 1) % #RAINBOW + 1], M.SmoothPlastic)
		end
		turntable(b, 0, 38, -2, 46, 30, darken(wood, 0.1))
		for _, side in ipairs({ -1, 1 }) do
			local x = side * 41
			b.Cyl(x, 0, 0, 12, 1.5, CARBON, M.Metal)
			b.Cyl(x, 1.5, 0, 3, 24, CARBON_LIGHT, M.Metal)
			speaker(b, x, 25, 0, 18, 32, 20, b.Map(WOOD_DARK), 2)
		end
		b.Footprint(100, 36, 57)
		return
	end
	-- palier 4 : mur de studio lofi (enceintes colonnes, console, mur de vinyles, VU)
	local wood = b.Map(rgb(90, 64, 52))
	b.Box(0, 0, -16, 100, 96, 4, rgb(52, 40, 64), M.Wood)
	-- mur de vinyles (pochettes exposées)
	for row = 0, 1 do
		for col = 0, 4 do
			local x = -24 + col * 12
			local y = 62 + row * 16
			b.Box(x, y, -13.6, 11, 11, 0.8, RAINBOW[(row * 5 + col) % #RAINBOW + 1], M.SmoothPlastic)
			b.CylZ(x, y + 5.5, -13, 7, 0.4, rgb(20, 20, 26), M.SmoothPlastic)
			b.CylZ(x, y + 5.5, -12.7, 2.6, 0.3, WHITE, M.SmoothPlastic)
		end
		b.Box(0, 61 + row * 16, -12, 62, 1, 4, darken(wood, 0.1), M.Wood)
	end
	-- enseigne néon "lofi"
	neon(b, b.Round(0, 90, -13.4, 30, 5, 1.2, 2, rgb(255, 120, 210), M.Neon), "RGB")
	-- console (meuble + platine + table de mixage)
	b.Box(0, 0, 0, 62, 34, 28, wood, M.Wood)
	b.Box(0, 34, 0, 64, 2, 30, darken(wood, 0.25), M.Wood)
	neon(b, b.Box(0, 33, 14.4, 62, 1, 0.6, RAINBOW[1], M.Neon), "RGB")
	turntable(b, -14, 36, 0, 30, 24, rgb(40, 38, 50))
	b.Box(14, 36, 0, 20, 4, 22, rgb(40, 38, 50), M.Metal)
	for index = 1, 3 do
		b.Box(8 + index * 3, 40, 2, 1, 1.2, 12, CHROME, M.Metal)
	end
	transport(b, 16, 40, -6, 0.8)
	vuBars(b, 0, 20, 14, 40, 10, 10)
	lcd(b, 0, 46, -14, 26, 8)
	-- enceintes colonnes
	for _, side in ipairs({ -1, 1 }) do
		speaker(b, side * 42, 0, -2, 16, 86, 20, rgb(30, 30, 38), 3)
		neon(b, b.Box(side * 42, 0.4, 8.3, 14, 1, 0.6, RAINBOW[side == -1 and 5 or 2], M.Neon), "RGB")
	end
	b.Footprint(100, 36, 98)
end

R.SetupHiFiBoombox = hifi
R.SetupHiFiCD = hifi
R.SetupHiFiVinyl = hifi
R.SetupHiFiStudio = hifi

----------------------------------------------------------------------
-- 🌀 MOULIN À VENT (jardin / terrasse)
----------------------------------------------------------------------

R.SetupWindmill = function(b, _ctx)
	local stone = rgb(214, 204, 196)
	local body = b.Map(rgb(255, 238, 222))
	local roof = b.Map(rgb(236, 110, 130))
	-- socle de pierre + massif de fleurs
	b.Cyl(0, 0, 0, 58, 6, stone, M.Slate)
	for index = 0, 9 do
		local angle = index / 10 * math.pi * 2
		b.Ball(math.cos(angle) * 27, 7, math.sin(angle) * 27, 6, RAINBOW[index % #RAINBOW + 1], M.SmoothPlastic)
		b.Ball(math.cos(angle + 0.3) * 27, 5, math.sin(angle + 0.3) * 27, 7, LEAF, M.Grass)
	end
	-- tour conique (3 tambours)
	b.Cyl(0, 6, 0, 42, 22, body, M.SmoothPlastic)
	b.Cyl(0, 28, 0, 36, 20, body, M.SmoothPlastic)
	b.Cyl(0, 48, 0, 30, 16, body, M.SmoothPlastic)
	b.Cyl(0, 27, 0, 44, 2, WOOD_DARK, M.Wood)
	-- balcon
	b.Cyl(0, 46, 0, 40, 1.4, WOOD, M.Wood)
	-- porte + fenêtres
	b.Box(0, 6, 20.3, 10, 16, 1.4, WOOD_DARK, M.Wood)
	b.CylZ(0, 22, 20.3, 10, 1.4, WOOD_DARK, M.Wood)
	for _, y in ipairs({ 34, 52 }) do
		b.Box(0, y, 17.6 - (y - 34) * 0.1, 7, 8, 1.2, rgb(150, 200, 255), M.Glass)
		b.Box(0, y + 3.6, 18 - (y - 34) * 0.1, 7, 0.8, 1.4, WHITE, M.Wood)
	end
	-- chapeau (toit)
	b.Cyl(0, 64, 0, 34, 3, roof, M.SmoothPlastic)
	b.Egg(0, 71, 0, 32, 22, 32, roof, M.SmoothPlastic)
	b.Ball(0, 82, 0, 5, GOLD, M.Metal)
	-- moyeu + ailes (tournent autour de Pivot_Blades, face +z)
	local hy, hz = 68, 19
	pivot(b, "Pivot_Blades", 0, hy, hz)
	b.CylZ(0, hy, hz - 3, 5, 6, WOOD_DARK, M.Wood)
	named(b.CylZ(0, hy, hz, 7, 2.4, rgb(120, 80, 60), M.Wood), "Blades")
	local sail = b.Map(rgb(255, 250, 244))
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local base = CFrame.new(0, hy, hz + 1.4) * CFrame.Angles(0, 0, angle)
		-- longeron
		named(b.BoxR(base * CFrame.new(22, 0, 0), 44, 2, 1.2, WOOD_DARK, M.Wood), "Blade")
		-- toile + lattes
		named(b.BoxR(base * CFrame.new(26, 4.2, -0.2), 30, 7, 0.4, sail, M.Fabric), "Blade")
		for slat = 0, 3 do
			named(b.BoxR(base * CFrame.new(13 + slat * 9, 4.2, 0.2), 0.8, 8, 0.6, WOOD, M.Wood), "Blade")
		end
		named(b.BoxR(base * CFrame.new(26, 8, 0.2), 30, 0.8, 0.6, WOOD, M.Wood), "Blade")
	end
	b.Footprint(62, 58, 100)
end

----------------------------------------------------------------------
-- 🗜️ PRESSE HYDRAULIQUE (v9.8 : refaite "comme la presse du clicker")
-- Bâti en H (lit + montants + traverse), vérin hydraulique chromé, coulisseau
-- (bélier) à bandes de danger, enclume striée, deux manomètres, pupitre
-- (gros bouton rouge, voyants, afficheur), tapis roulant qui AMÈNE les objets
-- sous la presse (lamelles qui défilent), bac à galettes, centrale
-- hydraulique + flexibles, gyrophare. Les pièces portent un attribut "Tint"
-- (Frame / FrameDark / AccentA / AccentB / Chrome / Hose / Bolt) : LiveProps
-- les peint aux couleurs du palier de la presse du clicker (niveau
-- "Presse hydraulique" du propriétaire, 10 paliers : bois -> diamant néon).
----------------------------------------------------------------------

-- Paliers de la presse du clicker (Stimuli > Press, TIERS) : couleurs 3D
House3DSetup.PressTiers = {
	{ Name = "Rustic wood", Frame = rgb(186, 128, 74), Dark = rgb(150, 100, 56), AccentA = rgb(226, 196, 138), AccentB = rgb(186, 150, 92), Chrome = rgb(214, 170, 84), Hose = rgb(122, 76, 42), Bolt = rgb(70, 58, 50), Wood = true, Debris = { rgb(186, 128, 74), rgb(226, 196, 138) } },
	{ Name = "Oak & iron", Frame = rgb(140, 90, 50), Dark = rgb(92, 94, 104), AccentA = rgb(92, 94, 104), AccentB = rgb(62, 64, 72), Chrome = rgb(160, 164, 172), Hose = rgb(64, 46, 32), Bolt = rgb(44, 44, 50), Wood = true, Debris = { rgb(140, 90, 50), rgb(120, 122, 130) } },
	{ Name = "Steel", Frame = rgb(160, 168, 182), Dark = rgb(110, 116, 132), AccentA = rgb(255, 200, 30), AccentB = INK, Chrome = rgb(210, 216, 226), Hose = rgb(40, 40, 46), Bolt = rgb(90, 96, 110), Debris = { rgb(200, 205, 215) } },
	{ Name = "Blue steel", Frame = rgb(48, 114, 204), Dark = rgb(36, 80, 150), AccentA = rgb(255, 200, 30), AccentB = INK, Chrome = rgb(214, 220, 230), Hose = rgb(30, 30, 36), Bolt = rgb(220, 226, 236), Debris = { rgb(48, 114, 204), rgb(220, 226, 236) } },
	{ Name = "Industrial", Frame = rgb(244, 140, 30), Dark = rgb(70, 74, 86), AccentA = rgb(255, 214, 40), AccentB = INK, Chrome = rgb(214, 220, 230), Hose = rgb(28, 28, 32), Bolt = rgb(60, 60, 66), Beacon = true, Steam = true, Debris = { rgb(244, 140, 30), rgb(120, 126, 140) } },
	{ Name = "Factory", Frame = rgb(78, 88, 104), Dark = rgb(50, 56, 68), AccentA = rgb(60, 214, 110), AccentB = rgb(26, 30, 36), Chrome = rgb(214, 220, 230), Hose = rgb(20, 20, 24), Bolt = rgb(150, 160, 176), Beacon = true, Steam = true, Debris = { rgb(78, 88, 104), rgb(60, 214, 110) } },
	{ Name = "Solid gold", Frame = rgb(240, 180, 40), Dark = rgb(200, 140, 30), AccentA = rgb(255, 240, 170), AccentB = rgb(214, 150, 20), Chrome = rgb(255, 230, 140), Hose = rgb(120, 72, 20), Bolt = rgb(150, 100, 10), Shine = true, Debris = { rgb(255, 214, 70), rgb(255, 246, 200) } },
	{ Name = "Royal gold", Frame = rgb(246, 190, 50), Dark = rgb(150, 20, 44), AccentA = rgb(196, 24, 56), AccentB = rgb(255, 222, 120), Chrome = rgb(255, 236, 160), Hose = rgb(150, 20, 44), Bolt = rgb(255, 236, 160), Shine = true, Debris = { rgb(255, 214, 70), rgb(196, 24, 56) } },
	{ Name = "Diamond", Frame = rgb(176, 232, 255), Dark = rgb(120, 190, 235), AccentA = WHITE, AccentB = rgb(130, 206, 255), Chrome = rgb(236, 250, 255), Hose = rgb(80, 164, 230), Bolt = rgb(90, 170, 230), Shine = true, Crystal = true, Debris = { rgb(190, 240, 255), WHITE } },
	{ Name = "Neon diamond", Frame = rgb(200, 238, 255), Dark = rgb(40, 24, 80), AccentA = rgb(0, 230, 255), AccentB = rgb(255, 60, 200), Chrome = rgb(236, 250, 255), Hose = rgb(255, 60, 200), Bolt = rgb(0, 230, 255), Beacon = true, Shine = true, Crystal = true, Neon = true, Debris = { rgb(0, 230, 255), rgb(255, 60, 200) } },
}
House3DSetup.PRESS_DEFAULT_TIER = 5 -- (visiteurs : palier "industriel")

local HAZARD_A, HAZARD_B = rgb(255, 204, 36), rgb(34, 34, 40)

-- Bandes de danger en diagonale sur une face (une SurfaceGui, 8 bandes)
local function hazard(part: BasePart, face: Enum.NormalId, faceW: number, faceH: number, stripes: number)
	local canvas = Vector2.new(256, math.max(16, math.floor(256 * faceH / math.max(0.01, faceW) + 0.5)))
	local gui = House3DKit.Surface(part, face, canvas, 1)
	gui.Name = "Hazard"
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = WHITE
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = gui
	local n = math.clamp(stripes, 2, 10)
	local keypoints = {}
	for i = 1, n do
		local color = i % 2 == 1 and HAZARD_A or HAZARD_B
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / n, color))
		table.insert(keypoints, ColorSequenceKeypoint.new(math.min(1, i / n - 0.002), color))
	end
	keypoints[#keypoints] = ColorSequenceKeypoint.new(1, n % 2 == 1 and HAZARD_A or HAZARD_B)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keypoints)
	gradient.Rotation = 35
	gradient.Parent = fill
end

local function tint(part: BasePart, role: string): BasePart
	part:SetAttribute("Tint", role)
	return part
end

R.SetupPress = function(b, _ctx)
	local tierStyle = House3DSetup.PressTiers[House3DSetup.PRESS_DEFAULT_TIER]
	local frame = b.Map(tierStyle.Frame)
	local dark = tierStyle.Dark
	local chrome = tierStyle.Chrome
	local t = th(b, 1.2)
	local PX, PZ = -10, -4 -- axe de la presse
	local ANVIL = 22 -- dessus de l'enclume
	-- plancher (tôle striée) + bande de danger au bord avant
	b.Box(0, 0, 0, 100, 3, 60, rgb(82, 86, 98), M.DiamondPlate)
	local strip = b.Box(0, 2.4, 27, 98, th(b, 1.6), 5, HAZARD_A, M.SmoothPlastic)
	hazard(strip, Enum.NormalId.Top, 98, 5, 10)
	-- lit (bâti bas) + enclume striée
	tint(b.Box(PX, 2.4, PZ, 46, 16, 34, frame, M.Metal), "Frame")
	b.Box(PX, 18, PZ, 34, ANVIL - 18, 28, rgb(120, 126, 142), M.DiamondPlate)
	pivot(b, "Pivot_Anvil", PX, ANVIL, PZ)
	-- montants
	for _, side in ipairs({ -1, 1 }) do
		tint(b.Box(PX + side * 27, 2.4, PZ, 10, 84, 22, frame, M.Metal), "Frame")
		-- boulons sur les montants
		for _, y in ipairs({ 14, 78 }) do
			tint(b.Ball(PX + side * 27, y, PZ + 11 + t * 0.2, 2.6, tierStyle.Bolt, M.Metal), "Bolt")
		end
	end
	-- traverse + bandeau de danger + manomètres
	tint(b.Box(PX, 84, PZ, 72, 16, 26, frame, M.Metal), "Frame")
	local band = b.Box(PX, 88, PZ + 13 + t * 0.3, 40, 7, t, HAZARD_A, M.SmoothPlastic)
	hazard(band, Enum.NormalId.Back, 40, 7, 8) -- (face vers +z : "Back" une fois l'objet retourné)
	for index, gx in ipairs({ PX - 27, PX + 27 }) do
		local dz = PZ + 13
		b.CylZ(gx, 92, dz - t * 0.15, 11, t, INK, M.Metal) -- boîtier
		named(b.CylZ(gx, 92, dz + t * 0.6, 9, t, rgb(250, 248, 240), M.SmoothPlastic), "GaugeDial" .. index)
		-- zone rouge du cadran
		b.BoxR(CFrame.new(gx + 2.4, 94.2, dz + t * 1.1 + th(b, 0.3) / 2 - 0.1) * CFrame.Angles(0, 0, -0.7), 2.6, 0.9, th(b, 0.3), RED, M.SmoothPlastic)
		named(b.BoxR(CFrame.new(gx, 94, dz + t * 1.1 + th(b, 0.8)), 0.8, 4.6, th(b, 0.6), RED, M.SmoothPlastic), "Gauge" .. index)
		b.CylZ(gx, 92, dz + t * 1.1 + th(b, 1.6), 1.6, th(b, 0.8), INK, M.Metal)
	end
	-- vérin hydraulique (sur la traverse) + gyrophare
	tint(b.Cyl(PX, 99, PZ, 24, 18, dark, M.Metal), "FrameDark")
	tint(b.Cyl(PX, 116.6, PZ, 26, 3, chrome, M.Metal), "Chrome")
	for _, dx in ipairs({ -11, 11 }) do
		tint(b.Cyl(PX + dx, 99, PZ + 9, 2.4, 17.6, chrome, M.Metal), "Chrome") -- tirants
	end
	b.Cyl(PX, 119.4, PZ, 7, 2, CARBON, M.Metal)
	neon(b, b.Egg(PX, 124.6, PZ, 6, 8, 6, ORANGE, M.Neon), "PressBeacon")
	-- coulisseau (descend) : tige chromée longue (reste dans le vérin), bélier, guides
	pivot(b, "Pivot_Ram", PX, 52, PZ)
	tint(named(b.Cyl(PX, 62, PZ, 9, 51, chrome, M.Metal), "PressRam"), "Chrome")
	local ram = named(b.Box(PX, 52, PZ, 46, 10, 24, dark, M.Metal), "PressRam")
	tint(ram, "FrameDark")
	local ramBand = named(b.Box(PX, 53.5, PZ + 12 + t * 0.3, 40, 7, t, HAZARD_A, M.SmoothPlastic), "PressRam")
	hazard(ramBand, Enum.NormalId.Back, 40, 7, 8)
	-- pupitre (devant à droite) : gros bouton rouge, voyants, afficheur
	local cx, cz = 38, 18
	b.Box(cx, 2.4, cz, 5, 36, 5, CARBON, M.Metal)
	b.Box(cx, 2.4, cz, 14, th(b, 1.6), 14, CARBON_LIGHT, M.Metal)
	local head = CFrame.new(cx, 42, cz) * CFrame.Angles(-0.55, 0, 0)
	tint(b.BoxR(head, 24, 7, 16, tierStyle.AccentA, M.Metal), "AccentA")
	local topFace = head * CFrame.new(0, 3.5, 0)
	local button = b.Part("Part", topFace * CFrame.new(-4, 1.2, 1) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2.4, 6.4, 6.4), RED, M.SmoothPlastic, "PressButton")
	;(button :: Part).Shape = Enum.PartType.Cylinder
	b.Part("Part", topFace * CFrame.new(-4, 0.4, 1) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(1.6, 8.4, 8.4), rgb(255, 214, 60), M.SmoothPlastic, "Collar").CastShadow = false
	;(b.Parts[#b.Parts] :: Part).Shape = Enum.PartType.Cylinder
	for index, color in ipairs({ MINT, YELLOW, RED }) do
		neon(b, b.Part("Part", topFace * CFrame.new(3 + index * 2.6, 0.5, -4), Vector3.new(1.8, 1.4, 1.8), color, M.Neon, "Lamp" .. index), nil)
	end
	named(b.Part("Part", topFace * CFrame.new(6, 0.3, 2.6), Vector3.new(10, th(b, 1.2), 5), rgb(10, 22, 16), M.SmoothPlastic, "PressDisplay"), "PressDisplay")
	-- tapis roulant (amène les objets de la droite vers l'enclume)
	local beltX0, beltX1 = PX + 24, 50
	local beltMid, beltLen = (beltX0 + beltX1) / 2, beltX1 - beltX0
	local beltTop = ANVIL
	b.Box(beltMid, beltTop - 2.6, PZ, beltLen, 2.6 - th(b, 0.2, 0.004), 22, rgb(36, 36, 44), M.Rubber)
	for _, side in ipairs({ -1, 1 }) do
		tint(b.Box(beltMid, beltTop - 5, PZ + side * 12.4, beltLen + 4, 7, 2.4, tierStyle.AccentA, M.Metal), "AccentA")
		b.Box(beltX0 + 4, 2.4, PZ + side * 9, 3, beltTop - 7.4, 3, CARBON, M.Metal)
		b.Box(beltX1 - 3, 2.4, PZ + side * 9, 3, beltTop - 7.4, 3, CARBON, M.Metal)
	end
	b.CylZ(beltX1, beltTop - 1.6, PZ, 3.4, 23, CHROME, M.Metal)
	b.CylZ(beltX0 + 0.5, beltTop - 1.6, PZ, 3.2, 23, CHROME, M.Metal)
	for index = 0, 5 do
		local x = beltX0 + 2 + index * (beltLen - 4) / 6
		named(b.Box(x, beltTop - th(b, 1) * 0.6, PZ, 1.8, th(b, 1), 20, rgb(78, 78, 92), M.Rubber), "BeltSlat")
	end
	-- bac à galettes (à gauche) : les objets écrasés y tombent
	local binX = -43
	b.Box(binX, 2.4, PZ, 14, th(b, 1.4), 26, CARBON, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		tint(b.Box(binX, 2.4, PZ + side * 12, 14, 14, 2, tierStyle.AccentB, M.Metal), "AccentB")
		tint(b.Box(binX + side * 6, 2.4, PZ, 2, 14, 23, tierStyle.AccentB, M.Metal), "AccentB")
	end
	for index, color in ipairs({ YELLOW, RED, rgb(70, 170, 80), rgb(255, 150, 190) }) do
		b.Cyl(binX + (index % 2) * 2 - 1, 2.2 + th(b, 1.4) + (index - 1) * 1.6, PZ + (index - 2.5) * 3, 9, 1.8, color, M.SmoothPlastic)
	end
	-- centrale hydraulique (au fond à droite) + flexibles jusqu'au vérin
	local ux, uz = 34, -21
	tint(b.Round(ux, 2.4, uz, 22, 20, 14, 3, dark, M.Metal), "FrameDark")
	tint(b.CylX(ux, 27, uz, 10, 16, chrome, M.Metal), "Chrome")
	b.CylX(ux - 9.6, 27, uz, 6, 3, CARBON, M.Metal)
	neon(b, b.Ball(ux + 6, 21, uz + 7.2, 1.6, MINT, M.Neon), "Glow")
	for index, dz in ipairs({ -3, 3 }) do
		local hose = House3DKit.Path(b, { { ux - 6, 23, uz + dz * 0.5 }, { ux - 14, 60, uz + dz }, { PX + 14, 108, PZ + dz * 1.4 } }, 2.4, tierStyle.Hose, M.Rubber, false, true)
		for _, part in ipairs(hose) do
			tint(part, "Hose")
		end
		local _ = index
	end
	-- objets à écraser (un seul visible à la fois ; ils arrivent par le tapis)
	local function crushable(list: { BasePart }, variant: number)
		for _, part in ipairs(list) do
			part.Name = "Crushable"
			part:SetAttribute("Variant", variant)
		end
	end
	local y = ANVIL - 0.8 -- (posés dans l'enclume : aucune face collée)
	-- 1 : canard en caoutchouc
	crushable({ b.Egg(PX, y + 8, PZ, 22, 16, 18, YELLOW, M.SmoothPlastic), b.Ball(PX + 1, y + 18, PZ - 3, 12, YELLOW, M.SmoothPlastic),
		b.Egg(PX + 1, y + 17, PZ - 10, 7, 3.4, 7, ORANGE, M.SmoothPlastic), b.Ball(PX - 2.6, y + 20, PZ - 7.4, 2.2, INK, M.SmoothPlastic),
		b.Ball(PX + 4.6, y + 20, PZ - 7.4, 2.2, INK, M.SmoothPlastic) }, 1)
	-- 2 : canette de soda
	crushable({ b.Cyl(PX, y, PZ, 14, 22, RED, M.Metal), b.Cyl(PX, y + 21.6, PZ, 12, 1.6, CHROME, M.Metal), b.Cyl(PX, y + 9, PZ, 14.6, 5, WHITE, M.SmoothPlastic) }, 2)
	-- 3 : pastèque
	crushable({ b.Egg(PX, y + 11, PZ, 26, 21, 20, rgb(70, 170, 80), M.SmoothPlastic), b.Egg(PX, y + 11, PZ, 26.6, 10, 20.6, rgb(40, 120, 60), M.SmoothPlastic) }, 3)
	-- 4 : gâteau (deux étages, glaçage, cerise)
	crushable({ b.Cyl(PX, y, PZ, 24, 8, rgb(255, 170, 200), M.SmoothPlastic), b.Cyl(PX, y + 7.6, PZ, 18, 7, rgb(255, 236, 214), M.SmoothPlastic),
		b.Cyl(PX, y + 14.2, PZ, 18.8, 1.8, WHITE, M.SmoothPlastic), b.Ball(PX, y + 17.2, PZ, 4.6, RED, M.SmoothPlastic) }, 4)
	-- 5 : paquet cadeau
	crushable({ b.Box(PX, y, PZ, 18, 16, 18, rgb(120, 110, 255), M.SmoothPlastic), b.Box(PX, y - 0.3, PZ, 4, 16.8, 18.8, GOLD, M.SmoothPlastic),
		b.Box(PX, y - 0.3, PZ, 18.8, 16.8, 4, GOLD, M.SmoothPlastic), b.Ball(PX - 2.4, y + 17.4, PZ, 4.4, GOLD, M.SmoothPlastic),
		b.Ball(PX + 2.4, y + 17.4, PZ, 4.4, GOLD, M.SmoothPlastic) }, 5)
	-- 6 : cube magique (faces colorées)
	crushable({ b.Box(PX, y, PZ, 16, 16, 16, INK, M.SmoothPlastic), b.Box(PX, y + 1, PZ + 8 + t * 0.2, 14, 14, t, RED, M.SmoothPlastic),
		b.Box(PX, y + 16 - t * 0.6, PZ, 14, t, 14, WHITE, M.SmoothPlastic), b.Box(PX + 8 + t * 0.2, y + 1, PZ, t, 14, 14, rgb(60, 200, 90), M.SmoothPlastic) }, 6)
	b.Footprint(100, 60, 130)
end

----------------------------------------------------------------------
-- 🔘 TABLE À PAPIER BULLE
----------------------------------------------------------------------

R.SetupBubbleWrap = function(b, ctx)
	local T = ctx.TopY(1, 48)
	local wood = b.Map(rgb(240, 214, 190))
	b.Box(0, T - 4, 0, 96, 4, 52, wood, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 42, 0, sz * 20, 5, T - 4, 5, darken(wood, 0.15), M.Wood)
		end
	end
	b.Box(0, T * 0.3, 0, 84, 2, 40, darken(wood, 0.1), M.Wood)
	-- rouleau (dérouleur) au fond
	b.Box(-44, T, -18, 3, 12, 4, CHROME, M.Metal)
	b.Box(44, T, -18, 3, 12, 4, CHROME, M.Metal)
	b.CylX(0, T + 9, -18, 4, 90, CHROME, M.Metal)
	local roll = b.CylX(0, T + 9, -18, 16, 84, rgb(200, 230, 255), M.Glass)
	roll.Transparency = 0.35
	b.CylX(0, T + 9, -18, 12, 86, rgb(230, 244, 255), M.SmoothPlastic).Transparency = 0.55
	-- feuille dépliée + bulles (cliquables)
	local sheet = b.Box(0, T, 6, 84, 0.6, 34, rgb(220, 240, 255), M.SmoothPlastic)
	sheet.Transparency = 0.35
	b.BoxR(CFrame.new(0, T + 4, -9) * CFrame.Angles(0.9, 0, 0), 84, 0.5, 12, rgb(220, 240, 255), M.SmoothPlastic).Transparency = 0.4
	local cols, rows = 9, 4
	local index = 0
	for row = 1, rows do
		for col = 1, cols do
			index += 1
			local x = -40 + (col - 0.5) * (80 / cols) + (row % 2 == 0 and 2 or -2)
			local z = -8 + (row - 0.5) * (30 / rows) + 2
			local bubble = b.Egg(x, T + 2.2, z, 7, 3.6, 6.4, rgb(232, 246, 255), M.SmoothPlastic)
			bubble.Name = "Bubble_" .. index
			bubble.Transparency = 0.05
			bubble.CastShadow = false
		end
	end
	-- petit panneau "POP ME"
	b.Box(40, T, 22, 12, 7, 1, rgb(255, 120, 190), M.SmoothPlastic)
	b.Top(1, 0, T + 1, 6, 80, 30)
	b.Footprint(96, 52, T + 18)
end

----------------------------------------------------------------------
-- 🎥 COIN LIVE (anneau lumineux, caméra, écran du stream)
----------------------------------------------------------------------

R.SetupLiveStudio = function(b, _ctx)
	-- petit bureau + écran du live (à gauche)
	local desk = b.Map(rgb(250, 236, 246))
	b.Box(-24, 38, -4, 48, 3, 30, desk, M.Wood)
	for _, sx in ipairs({ -46, -2 }) do
		b.Box(sx, 0, -4, 3, 38, 26, darken(desk, 0.1), M.Wood)
	end
	monitor(b, CFrame.new(-24, 50, -12), 36, 22, "Live", 1, rgb(30, 30, 40), true, 7.6)
	-- micro sur bras
	b.Cyl(-44, 41, -14, 4, 2, CARBON, M.Metal)
	House3DKit.Path(b, { { -44, 43, -14 }, { -44, 62, -12 }, { -34, 60, 4 } }, 1.2, CARBON_LIGHT, M.Metal, false, true)
	b.Egg(-34, 58, 5, 5, 8, 5, rgb(60, 60, 70), M.Metal)
	-- anneau lumineux sur trépied (à droite)
	local rx, ry, rz = 28, 62, 6
	for _, angle in ipairs({ 0, 2.1, 4.2 }) do
		b.Tube(rx, 30, rz, rx + math.cos(angle) * 12, 0, rz + math.sin(angle) * 12, 1.6, CARBON, M.Metal)
	end
	b.Cyl(rx, 30, rz, 2, ry - 30, CHROME, M.Metal)
	local segments = 14
	local radius = 15
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local part = b.BoxR(CFrame.new(rx + math.cos(angle) * radius, ry + math.sin(angle) * radius, rz) * CFrame.Angles(0, 0, angle), 2.6, 7.2, 2.4, rgb(255, 246, 236), M.Neon)
		neon(b, part, "RingLight")
	end
	-- téléphone / caméra au centre + voyant REC
	b.Box(rx, ry - 8, rz + 0.6, 9, 16, 1.4, rgb(30, 30, 40), M.SmoothPlastic)
	b.CylZ(rx, ry + 3, rz + 1.6, 3, 1, rgb(80, 120, 200), M.Glass)
	neon(b, b.Ball(rx + 3, ry + 6, rz + 1.6, 1.6, RED, M.Neon), "RecLight")
	-- enseigne ON AIR (au fond)
	b.Box(-6, 41, -16, 2, 30, 2, CARBON_LIGHT, M.Metal)
	b.Box(-6, 70, -16, 20, 8, 3, rgb(40, 14, 24), M.SmoothPlastic)
	neon(b, b.Round(-6, 71, -14.4, 17, 6, 0.6, 1.5, RED, M.Neon), "OnAir")
	-- tabouret
	b.Cyl(0, 0, 16, 16, 1.5, CARBON, M.Metal)
	b.Cyl(0, 1.5, 16, 3, 20, CHROME, M.Metal)
	b.Cyl(0, 21, 16, 18, 4, rgb(255, 120, 190), M.Leather)
	b.Footprint(100, 44, 88)
end

----------------------------------------------------------------------
-- 🌼 POTS DE FLEURS DU JARDIN (GardenBuilder.BuildFlower si présent)
----------------------------------------------------------------------

local FLOWER_COLORS: { [string]: { Color3 } } = {
	Daisy = { WHITE, YELLOW },
	Tulip = { rgb(255, 90, 130), rgb(255, 170, 190) },
	Rose = { rgb(214, 36, 70), rgb(150, 20, 50) },
	Sunflower = { rgb(255, 200, 40), rgb(120, 70, 30) },
	Lotus = { rgb(255, 200, 230), GOLD },
}

-- Module du jardin 3D (GARDEN3D95) : chargé une fois, jamais bloquant
local gardenModule: any = nil
local gardenTried = false
local function gardenBuilder(): any
	if gardenTried then
		return gardenModule
	end
	gardenTried = true
	local ok, result = pcall(function()
		local client = ReplicatedStorage:FindFirstChild("Client")
		local world = client and client:FindFirstChild("World")
		local module = world and world:FindFirstChild("GardenBuilder")
		if module and module:IsA("ModuleScript") then
			return require(module) :: any
		end
		return nil
	end)
	if ok and type(result) == "table" and type(result.BuildFlower) == "function" then
		gardenModule = result
	end
	return gardenModule
end

-- Fleur "maison" (repli) : une tige, des feuilles, une corolle ; y = base
local function simpleFlower(b: Builder, flower: string, x: number, y: number, z: number, height: number, lean: number)
	local colors = FLOWER_COLORS[flower] or FLOWER_COLORS.Daisy
	local petal, heart = colors[1], colors[2]
	local top = Vector3.new(x + lean, y + height, z)
	local parts = {}
	table.insert(parts, b.Tube(x, y, z, top.X, top.Y, top.Z, 2, LEAF_DARK, M.SmoothPlastic))
	table.insert(parts, b.EggR(CFrame.new(x + 3, y + height * 0.35, z) * CFrame.Angles(0, 0, -0.7), 9, 3.5, 4, LEAF, M.SmoothPlastic))
	table.insert(parts, b.EggR(CFrame.new(x - 3, y + height * 0.55, z) * CFrame.Angles(0, 0, 0.7), 8, 3, 4, LEAF, M.SmoothPlastic))
	if flower == "Tulip" then
		table.insert(parts, b.Egg(top.X, top.Y + 3, top.Z, 9, 12, 9, petal, M.SmoothPlastic))
		for index = 0, 2 do
			local angle = index / 3 * math.pi * 2
			table.insert(parts, b.EggR(CFrame.new(top.X + math.cos(angle) * 3, top.Y + 5, top.Z + math.sin(angle) * 3) * CFrame.Angles(math.sin(angle) * 0.3, 0, -math.cos(angle) * 0.3), 5, 12, 5, heart, M.SmoothPlastic))
		end
	elseif flower == "Rose" then
		table.insert(parts, b.Ball(top.X, top.Y + 3, top.Z, 10, petal, M.SmoothPlastic))
		table.insert(parts, b.Egg(top.X, top.Y + 6, top.Z, 7, 5, 7, heart, M.SmoothPlastic))
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			table.insert(parts, b.EggR(CFrame.new(top.X + math.cos(angle) * 4, top.Y + 2.5, top.Z + math.sin(angle) * 4) * CFrame.Angles(0, -angle, 0.5), 7, 3, 6, petal, M.SmoothPlastic))
		end
	elseif flower == "Sunflower" then
		local head = CFrame.new(top.X, top.Y + 6, top.Z + 1) * CFrame.Angles(-0.25, 0, 0)
		for index = 0, 11 do
			local angle = index / 12 * math.pi * 2
			table.insert(parts, b.EggR(head * CFrame.Angles(0, 0, angle) * CFrame.new(0, 9, 0), 5, 10, 1.6, petal, M.SmoothPlastic))
		end
		table.insert(parts, b.EggR(head * CFrame.new(0, 0, 0.6), 12, 12, 3, heart, M.SmoothPlastic))
	elseif flower == "Lotus" then
		for ring = 1, 2 do
			for index = 0, 5 do
				local angle = index / 6 * math.pi * 2 + ring * 0.5
				local r = ring == 1 and 6 or 3
				table.insert(parts, b.EggR(CFrame.new(top.X + math.cos(angle) * r, top.Y + 3 + ring * 1.5, top.Z + math.sin(angle) * r) * CFrame.Angles(0, -angle, ring == 1 and 0.9 or 0.5), 9, 3, 5, ring == 1 and petal or lighten(petal, 0.4), M.SmoothPlastic))
			end
		end
		local core = b.Ball(top.X, top.Y + 5, top.Z, 5, heart, M.Neon)
		b.Neon(core)
		table.insert(parts, core)
	else
		for index = 0, 9 do
			local angle = index / 10 * math.pi * 2
			table.insert(parts, b.EggR(CFrame.new(top.X + math.cos(angle) * 5, top.Y + 2, top.Z + math.sin(angle) * 5) * CFrame.Angles(0, -angle, 0), 8, 1.6, 3.4, petal, M.SmoothPlastic))
		end
		table.insert(parts, b.Ball(top.X, top.Y + 2.4, top.Z, 5, heart, M.SmoothPlastic))
	end
	for _, part in ipairs(parts) do
		part.Name = "Flower"
		part.CastShadow = false
	end
end

-- Fleur du jardin 3D (GARDEN3D95) mise à l'échelle et versée dans le modèle
local function gardenFlower(b: Builder, flower: string, y: number, height: number, x: number?, z: number?, lean: number?): boolean
	local module = gardenBuilder()
	if not module then
		return false
	end
	local ok, model = pcall(module.BuildFlower, flower, "Bloom")
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	local okMove = pcall(function()
		local source = model:GetPivot()
		local natural = tonumber(model:GetAttribute("TopHeight")) or 3
		local scale = (height * b.K) / math.max(0.2, natural)
		local parent = b.Parts[1] and b.Parts[1].Parent
		local originCF = (b.Parts[1] and (b.Parts[1].CFrame * b.Locals[1]:Inverse())) or CFrame.new()
		local base = originCF * CFrame.new((x or 0) * b.K, y * b.K, (z or 0) * b.K) * CFrame.Angles(0, (x or 0) * 0.07, -(lean or 0))
		for _, part in ipairs(model:GetDescendants()) do
			-- (v9.6 z-fighting : le pot du lotus a déjà son eau et ses nénuphars ;
			-- la mare du jardin se superposait exactement à eux)
			local skip = flower == "Lotus" and (part.Name == "Water" or part.Name == "WaterRim" or part.Name == "Pad")
			if part:IsA("BasePart") and part.Name ~= "Root" and not skip then
				local rel = source:ToObjectSpace(part.CFrame)
				part.Size = part.Size * scale
				part.CFrame = base * CFrame.new(rel.Position * scale) * rel.Rotation
				part.Name = "Flower"
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = parent
				table.insert(b.Parts, part)
				table.insert(b.Locals, originCF:ToObjectSpace(part.CFrame))
			end
		end
	end)
	pcall(function()
		model:Destroy()
	end)
	return okMove
end

R.SetupPlant = function(b, _ctx)
	local setup = setupOf(b)
	local flower = tostring(setup.Flower or "Daisy")
	local tier = tierOf(setup)
	local potColor, rim = rgb(214, 120, 84), rgb(236, 150, 110)
	if flower == "Tulip" then
		potColor, rim = b.Map(rgb(255, 190, 214)), WHITE
	elseif flower == "Rose" then
		potColor, rim = WHITE, GOLD
	elseif flower == "Sunflower" then
		potColor, rim = b.Map(WOOD), WOOD_DARK
	elseif flower == "Lotus" then
		potColor, rim = GOLD, rgb(255, 230, 150)
	end
	local soil = 30
	if flower == "Lotus" then
		-- vasque dorée + eau + nénuphar
		b.Cyl(0, 0, 0, 44, 4, darken(potColor, 0.2), M.Metal)
		b.Cyl(0, 4, 0, 70, 16, potColor, M.Metal)
		-- (v9.6 z-fighting : liseré sous le bord (18..19.4), eau puis nénuphars
		-- empilés à 1 d'écart ; la fleur du jardin n'apporte plus sa propre mare)
		b.Cyl(0, 17, 0, 74, 1.4, rim, M.Metal)
		local water = b.Cyl(0, 20, 0, 66, 1, rgb(90, 190, 230), M.SmoothPlastic)
		water.Transparency = 0.1
		b.Cyl(14, 21, 8, 20, 1, LEAF, M.SmoothPlastic)
		b.Cyl(-16, 21, -6, 16, 1, LEAF_DARK, M.SmoothPlastic)
		soil = 21
	elseif flower == "Sunflower" then
		-- jardinière en bois
		b.Box(0, 0, 0, 50, 30, 40, potColor, M.Wood)
		for index = 0, 3 do
			b.Box(0, 2 + index * 7, 20.2, 50, 0.6, 0.5, rim, M.Wood)
		end
		b.Box(0, 29, 0, 46, 2, 36, rgb(110, 76, 56), M.Grass)
		soil = 30
	else
		b.Cyl(0, 0, 0, 34, 4, darken(potColor, 0.15), M.SmoothPlastic)
		b.Cyl(0, 4, 0, 40, 22, potColor, M.SmoothPlastic)
		b.Cyl(0, 24, 0, 46, 6, rim, M.SmoothPlastic)
		b.Cyl(0, 29.4, 0, 40, 2, rgb(110, 76, 56), M.Grass) -- (v9.6 : dessus 1.4 au-dessus du pot)
		if tier >= 3 then
			-- motif en cœur sur le pot
			House3DKit.Heart(b, 0, 14, 20.2, 10, 0.6, PINK, M.SmoothPlastic)
		end
		soil = 30
	end
	pivot(b, "Pivot_Flower", 0, soil, 0)
	local height = 100 - soil - 16
	-- fleurs du jardin 3D : un bouquet (3 marguerites / tulipes, 2 roses)
	local count = (flower == "Daisy" or flower == "Tulip") and 3 or (flower == "Rose" and 2 or 1)
	local okGarden = true
	for index = 1, count do
		local offset = count > 1 and (index - (count + 1) / 2) * 11 or 0
		local tall = flower == "Lotus" and 26 or (height - math.abs(offset) * 0.9)
		if not gardenFlower(b, flower, soil, tall, offset, (index % 2) * 5 - 2, offset * 0.02) then
			okGarden = false
			break
		end
	end
	if not okGarden then
		if flower == "Sunflower" then
			simpleFlower(b, flower, 0, soil, 0, height - 6, 0)
		elseif flower == "Lotus" then
			simpleFlower(b, flower, 0, soil, 0, 1, 0)
		else
			local tufts = flower == "Rose" and 2 or 3
			for index = 1, tufts do
				local offset = (index - (tufts + 1) / 2) * 9
				simpleFlower(b, flower, offset, soil, (index % 2) * 4 - 2, height - 10 - math.abs(offset) * 0.6, offset * 0.4)
			end
		end
	end
	if flower == "Lotus" then
		-- étincelles dorées
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			local spark = b.Ball(math.cos(angle) * 22, 30 + (index % 2) * 10, math.sin(angle) * 22, 2, rgb(255, 236, 150), M.Neon)
			neon(b, spark, "Sparkle")
		end
	end
	b.Footprint(flower == "Lotus" and 74 or 50, flower == "Lotus" and 74 or 44, 100)
end

----------------------------------------------------------------------
-- Branchement (House3DRecipes.loadFamilies("House3DSetup"))
----------------------------------------------------------------------

-- Recette d'un objet Setup (d'après son Kind)
local BY_KIND: { [string]: (b: Builder, ctx: any) -> () } = {
	Desk = desk,
	Keyboard = R.SetupKeyboard,
	Mouse = R.SetupMouse,
	TV = tvRecipe,
	TVStand = R.SetupTVStand,
	NewsTV = R.SetupNewsTV,
	HiFi = hifi,
	Windmill = R.SetupWindmill,
	Press = R.SetupPress,
	BubbleWrap = R.SetupBubbleWrap,
	LiveStudio = R.SetupLiveStudio,
	Plant = R.SetupPlant,
}

function House3DSetup.Has(itemId: string): boolean
	local kind = House3DSetup.KindOf(itemId)
	return kind ~= nil and BY_KIND[kind] ~= nil
end

-- Liste des recettes { [itemId] = recette } pour tous les objets Setup de Config
function House3DSetup.Recipes(): { [string]: (b: Builder, ctx: any) -> () }
	local list = {}
	for id, recipe in pairs(R) do
		if id ~= "SetupPlant" then
			list[id] = recipe
		end
	end
	for flower in pairs(FLOWER_COLORS) do
		list["SetupPlant" .. flower] = R.SetupPlant
	end
	for id, item in pairs(HouseCommon.ItemsById) do
		if type(item) == "table" and (item.Category == "Setup" or type(item.Setup) == "table") then
			local kind = House3DSetup.KindOf(id)
			local recipe = kind and BY_KIND[kind]
			if recipe then
				list[id] = recipe
			end
		end
	end
	return list
end

function House3DSetup.Register(recipes: { [string]: any }, _family: { [string]: any }, _helpers: any, _flags: any)
	for id, recipe in pairs(House3DSetup.Recipes()) do
		recipes[id] = recipe
	end
end

return House3DSetup
