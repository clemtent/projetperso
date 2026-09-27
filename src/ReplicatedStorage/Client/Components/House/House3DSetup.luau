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
local function screenPart(b: Builder, cf: CFrame, w: number, h: number, kind: string, index: number): BasePart
	local part = b.Part("Part", cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, h, 0.5), SCREEN_OFF, M.SmoothPlastic, "Screen")
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
		local under = b.Box(0, T - 3.8, -40, deskW - 12, 0.6, 2, edge, M.Neon)
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
			monitor(b, cf, slot.W, slot.H, kind, index, frame, true, 8)
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
-- ⌨️ CLAVIER MÉCANIQUE RGB
----------------------------------------------------------------------

local KEY_ROWS = {
	{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
	{ "Z", "X", "C", "V", "B", "N", "M" },
}

R.SetupKeyboard = function(b, _ctx)
	local caseColor = b.Map(rgb(40, 40, 56))
	local w, d = 100, 36
	-- boîtier + plaque + halo dessous
	b.Round(0, 0, 0, w, 5, d, 2.5, caseColor, M.SmoothPlastic)
	named(b.Box(0, 5, 0, w - 5, 0.6, d - 5, rgb(26, 26, 36), M.Metal), "KeyboardBase")
	-- (v9.6 z-fighting : halo 1.2 plus large de chaque côté, plus 0.3)
	local glow = b.Box(0, 0.4, 0, w + 2.4, 1.4, d + 2.4, RAINBOW[5], M.Neon)
	neon(b, glow, "RGB")
	glow.Transparency = 0.3
	local unit = 8.4
	local cap = 7.2
	for rowIndex, row in ipairs(KEY_ROWS) do
		local z = -14 + (rowIndex - 1) * 7.2
		local offset = ({ 0, 0.25, 0.55, 1.05 })[rowIndex] * unit
		local startX = -w / 2 + 4.5 + offset + unit / 2
		for keyIndex, letter in ipairs(row) do
			local x = startX + (keyIndex - 1) * unit
			local color = RAINBOW[(keyIndex + rowIndex) % #RAINBOW + 1]:Lerp(WHITE, 0.45)
			local key = b.Box(x, 5.3, z, cap, 3.4, cap - 0.6, color, M.SmoothPlastic)
			key.Name = "Key_" .. letter
		end
		-- touches larges au bout des rangées (Tab / Maj / Entrée)
		local rowEnd = startX + (#row - 1) * unit + unit / 2 + 0.6
		local wide = w / 2 - 4 - rowEnd
		if wide > 3 then
			b.Box(rowEnd + wide / 2, 5.3, z, wide - 0.8, 3.2, cap - 0.6, rgb(90, 90, 116), M.SmoothPlastic)
		end
		if offset > 1 then
			b.Box(-w / 2 + 4.5 + offset / 2, 5.3, z, offset - 1, 3.2, cap - 0.6, rgb(90, 90, 116), M.SmoothPlastic)
		end
	end
	-- barre d'espace
	local space = b.Box(0, 5.3, 14.6, 44, 3.2, 6.2, rgb(240, 236, 250), M.SmoothPlastic)
	space.Name = "Key_Space"
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 33, 5.3, 14.6, 18, 3.2, 6.2, rgb(90, 90, 116), M.SmoothPlastic)
	end
	-- molette de volume + LED
	b.CylX(w / 2 - 6, 8, -16.5, 5, 3, CHROME, M.Metal)
	b.Footprint(w, d, 10)
end

----------------------------------------------------------------------
-- 🖱️ SOURIS GAMING + TAPIS
----------------------------------------------------------------------

R.SetupMouse = function(b, _ctx)
	local body = b.Map(rgb(36, 36, 50))
	-- tapis (bord lumineux)
	b.Round(0, 0, 0, 100, 1.4, 76, 5, rgb(30, 30, 42), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		neon(b, b.Box(0, 0.2, side * 38.2, 94, 1, 0.8, RAINBOW[5], M.Neon), "RGB")
		neon(b, b.Box(side * 50.2, 0.2, 0, 0.8, 1, 70, RAINBOW[1], M.Neon), "RGB")
	end
	b.Box(-30, 1.4, -26, 22, 0.8, 10, rgb(255, 92, 170), M.SmoothPlastic)
	-- souris
	local mx, mz = 12, 4
	named(b.Egg(mx, 7, mz + 3, 30, 14, 46, body, M.SmoothPlastic), "MouseBody")
	b.Box(mx, 1.4, mz + 3, 22, 3, 36, body, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		local button = b.BoxR(CFrame.new(mx + side * 6.6, 12.4, mz - 9) * CFrame.Angles(0.22, 0, 0), 12, 2, 18, lighten(body, 0.12), M.SmoothPlastic)
		button.Name = side == -1 and "MouseLeft" or "MouseRight"
		b.BoxR(CFrame.new(mx + side * 14.4, 8, mz + 2) * CFrame.Angles(0, 0, side * 0.35), 1.2, 6, 24, CARBON_LIGHT, M.Rubber)
	end
	local wheel = b.CylX(mx, 13.6, mz - 10, 5, 3, RAINBOW[6], M.Neon)
	neon(b, wheel, "MouseWheel")
	local logo = b.Ball(mx, 12.2, mz + 14, 4.5, RAINBOW[5], M.Neon)
	neon(b, logo, "RGB")
	-- câble (tressé) vers l'arrière
	House3DKit.Path(b, { { mx, 4, mz - 20 }, { mx - 4, 2.2, mz - 30 }, { mx - 20, 2, -36 }, { mx - 30, 2, -40 } }, 1.6, INK, M.Fabric)
	b.Footprint(100, 76, 16)
end

----------------------------------------------------------------------
-- 📺 TÉLÉS (logo DVD) + MEUBLE TÉLÉ + ÉCRAN D'INFOS
----------------------------------------------------------------------

-- Dalle : cadre fin + écran (bas-centre `cf`), largeur `w` (16:9)
local function flatPanel(b: Builder, cf: CFrame, w: number, kind: string, frameColor: Color3): number
	local h = w * 9 / 16
	local bezel = 1.6
	b.BoxR(cf * CFrame.new(0, h / 2 + bezel, 0), w + bezel * 2, h + bezel * 2, 2.4, frameColor, M.SmoothPlastic)
	b.BoxR(cf * CFrame.new(0, h / 2 + bezel, -2.2), w * 0.7, h * 0.7, 2.2, darken(frameColor, 0.1), M.SmoothPlastic)
	screenPart(b, cf * CFrame.new(0, bezel, 1.45), w, h, kind, 1)
	-- logo de la marque + diode
	b.BoxR(cf * CFrame.new(0, 0.7, 1.3), 6, 0.6, 0.3, CHROME, M.Metal)
	neon(b, b.BoxR(cf * CFrame.new(w / 2 - 2, 0.7, 1.3), 1, 0.5, 0.3, RED, M.Neon), "Glow")
	return h + bezel * 2
end

local function soundbar(b: Builder, x: number, y: number, z: number, w: number)
	b.Round(x, y, z, w, 4, 6, 2, CARBON, M.SmoothPlastic)
	b.Box(x, y + 0.6, z + 3.05, w - 4, 2.8, 0.2, rgb(70, 70, 90), M.Fabric)
	neon(b, b.Box(x, y + 0.3, z + 3.2, 3, 0.5, 0.2, CYAN, M.Neon), "Glow")
end

local function tvRecipe(b: Builder, _ctx: any)
	local setup = setupOf(b)
	local rank = sizeRank(setup)
	local frameColor = rank >= 3 and rgb(24, 24, 32) or b.Map(rgb(46, 46, 62))
	local feeds = type(setup.Feeds) == "table" and setup.Feeds or {}
	local kind = tostring(feeds[1] or "DVD")
	local w = 94
	local h = w * 9 / 16 + 3.2
	if tostring(setup.Mount) == "Wall" then
		-- au mur : platine + bras articulé, la télé 7 unités devant le mur
		b.Box(0, 42, 0.8, 30, 20, 1.6, CARBON_LIGHT, M.Metal)
		for _, side in ipairs({ -1, 1 }) do
			b.Box(side * 8, 50, 4, 3, 3, 6, STEEL, M.Metal)
			b.Box(side * 8, 44, 4, 3, 3, 6, STEEL, M.Metal)
		end
		local y0 = 50 - h / 2
		if rank >= 4 then
			-- "ambilight" : halo de couleur derrière la télé
			local halo = b.Box(0, y0 - 3, 4.2, w + 8, h + 6, 0.4, CYAN, M.Neon) -- (v9.6 : 1 plus en retrait)
			neon(b, halo, "Ambilight")
			halo.Transparency = 0.45
		end
		flatPanel(b, CFrame.new(0, y0, 8.4), w, kind, frameColor)
		if rank >= 3 then
			soundbar(b, 0, y0 - 9, 6, w * 0.7)
			b.Box(0, y0 - 5, 4, 20, 1.2, 4, STEEL, M.Metal)
		end
		b.Footprint(w + 4, 14, 100)
		return
	end
	if rank >= 4 then
		-- géante : grand pied en chevalet au sol + barre de son
		local y0 = 26
		for _, side in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(side * 26, y0 / 2 + 2, -4) * CFrame.Angles(0, 0, side * 0.08), 4, y0 + 6, 4, CARBON_LIGHT, M.Metal)
			b.Box(side * 26, 0, -4, 10, 2, 26, CARBON, M.Metal)
		end
		b.Box(0, y0 - 6, -4, 60, 3, 4, CARBON_LIGHT, M.Metal)
		flatPanel(b, CFrame.new(0, y0, 0), w, kind, frameColor)
		soundbar(b, 0, 2, 12, w * 0.8)
		b.Footprint(100, 30, y0 + h + 2)
		return
	end
	-- petite / moyenne / grande : pieds (sur un meuble ou au sol)
	local y0 = rank >= 3 and 8 or 7
	if rank == 1 then
		-- petite télé : pied central rond
		b.Cyl(0, 0, -1, 28, 1.6, CARBON, M.Metal)
		b.Box(0, 1.6, -3, 6, y0 - 1, 3, CHROME, M.Metal)
	else
		for _, side in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(side * 36, y0 / 2, 0) * CFrame.Angles(0, 0, side * 0.35), 2.6, y0 + 2, 3, CHROME, M.Metal)
			b.Box(side * 38, 0, 0, 8, 1.2, 14, CHROME, M.Metal)
		end
	end
	flatPanel(b, CFrame.new(0, y0, 0), w, kind, frameColor)
	if rank >= 3 then
		soundbar(b, 0, 0, 10, w * 0.6)
	end
	b.Footprint(100, rank >= 3 and 24 or 18, y0 + h)
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
	neon(b, b.Box(0, y0 - 2.6, 5, w + 8, 1.2, 3.4, RED, M.Neon), "Glow")
	neon(b, b.Box(0, y0 + h + 5, 5, w + 8, 1.2, 3.4, RED, M.Neon), "Glow")
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
	b.Box(0, 6.5, -d / 2 + 1.5, 99, inner - 0.5, 2, darken(body, 0.2), M.Wood)
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

-- Barres de niveau (VU) : `count` barres lumineuses, bas à `y`
local function vuBars(b: Builder, x: number, y: number, z: number, w: number, h: number, count: number)
	b.Box(x, y - 1, z - 0.3, w + 2, h + 2, 0.6, INK, M.SmoothPlastic)
	local step = w / count
	for index = 1, count do
		local color = index <= count * 0.6 and MINT or (index <= count * 0.85 and YELLOW or RED)
		local bar = b.Box(x - w / 2 + step * (index - 0.5), y, z, step * 0.6, h, 0.6, color, M.Neon)
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

-- Petit écran LCD (morceau en cours)
local function lcd(b: Builder, x: number, y: number, z: number, w: number, h: number)
	b.Box(x, y - 0.8, z - 0.3, w + 1.6, h + 1.6, 0.6, INK, M.SmoothPlastic)
	screenPart(b, CFrame.new(x, y, z + 0.3), w, h, "Music", 1)
end

local function hifi(b: Builder, _ctx: any)
	local setup = setupOf(b)
	local tier = math.clamp(tierOf(setup), 1, 4)
	if tier == 1 then
		-- radio-cassette rétro
		local body = b.Map(rgb(255, 140, 180))
		b.Round(0, 0, 0, 100, 48, 30, 5, body, M.SmoothPlastic)
		b.Box(0, 4, 15.1, 94, 40, 0.4, darken(body, 0.2), M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			b.CylZ(side * 29, 24, 15.3, 36, 0.8, CHROME, M.Metal)
			b.CylZ(side * 29, 24, 15.6, 32, 0.6, rgb(40, 40, 52), M.Fabric)
			named(b.CylZ(side * 29, 24, 16, 22, 1, rgb(30, 30, 40), M.SmoothPlastic), "SpeakerCone")
			b.CylZ(side * 29, 24, 16.6, 8, 1, CHROME, M.Metal)
		end
		-- fenêtre de la cassette + bobines
		b.Box(0, 20, 15.3, 22, 16, 0.6, rgb(60, 50, 80), M.Glass).Transparency = 0.2
		for _, side in ipairs({ -1, 1 }) do
			pivot(b, side == -1 and "Pivot_Spool1" or "Pivot_Spool2", side * 5.5, 28, 15.7)
			named(b.CylZ(side * 5.5, 28, 15.7, 6, 0.6, WHITE, M.SmoothPlastic), side == -1 and "Spool1" or "Spool2")
			named(b.Box(side * 5.5, 28, 16, 5.4, 1, 0.3, INK, M.SmoothPlastic), side == -1 and "Spool1" or "Spool2")
		end
		vuBars(b, 0, 8, 15.6, 20, 7, 5)
		lcd(b, 0, 38, 15.3, 24, 6)
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
		lcd(b, 0, 30, 17.1, 30, 8)
		vuBars(b, 0, 20, 17.3, 28, 6, 7)
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
		b.Box(0, 20, 16.4, 48, 13, 1.2, rgb(34, 32, 40), M.Metal)
		vuBars(b, -10, 23, 17.4, 20, 7, 8)
		b.CylZ(12, 26.5, 17.3, 7, 1.4, CHROME, M.Metal)
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
	vuBars(b, 0, 20, 14.4, 40, 10, 10)
	lcd(b, 0, 46, -13.3, 26, 8)
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
-- 🗜️ PRESSE HYDRAULIQUE
----------------------------------------------------------------------

R.SetupPress = function(b, _ctx)
	local yellowC = b.Map(rgb(255, 200, 40))
	local frame = rgb(60, 64, 80)
	-- socle + bandes de danger
	b.Box(0, 0, 0, 92, 8, 56, frame, M.Metal)
	for index = 0, 8 do
		b.BoxR(CFrame.new(-40 + index * 10, 4, 28.1) * CFrame.Angles(0, 0, 0.7), 4, 12, 0.4, index % 2 == 0 and yellowC or INK, M.SmoothPlastic)
	end
	b.Box(0, 0, 28.3, 92, 1.2, 0.6, frame, M.Metal)
	b.Box(0, 6.8, 28.3, 92, 1.2, 0.6, frame, M.Metal)
	-- enclume (matrice)
	b.Box(0, 8, 0, 50, 10, 40, rgb(110, 116, 132), M.DiamondPlate)
	pivot(b, "Pivot_Anvil", 0, 18, 0)
	-- colonnes + traverse
	for _, side in ipairs({ -1, 1 }) do
		b.Cyl(side * 36, 8, -6, 9, 80, CHROME, M.Metal)
		b.Box(side * 36, 8, -6, 14, 5, 14, frame, M.Metal)
	end
	b.Box(0, 84, -6, 92, 14, 26, yellowC, M.Metal)
	b.Box(0, 88, 7.1, 60, 6, 0.4, INK, M.SmoothPlastic)
	-- vérin hydraulique
	b.Cyl(0, 70, -2, 22, 14, frame, M.Metal)
	b.Cyl(0, 66, -2, 18, 4, CHROME, M.Metal)
	-- piston (descend) : tige + plateau
	pivot(b, "Pivot_Ram", 0, 60, 0)
	named(b.Cyl(0, 58, -2, 10, 40, CHROME, M.Metal), "PressRam")
	named(b.Box(0, 50, 0, 46, 8, 36, rgb(90, 96, 112), M.Metal), "PressRam")
	for index = 0, 4 do
		named(b.BoxR(CFrame.new(-18 + index * 9, 54, 18.1) * CFrame.Angles(0, 0, 0.7), 3, 9, 0.4, index % 2 == 0 and yellowC or INK, M.SmoothPlastic), "PressRam")
	end
	-- objets à écraser (un seul visible à la fois)
	-- 1 : canard en caoutchouc
	local duck = { b.Egg(0, 28, 0, 26, 20, 22, YELLOW, M.SmoothPlastic), b.Ball(0, 40, -4, 14, YELLOW, M.SmoothPlastic),
		b.Egg(0, 39, -12, 8, 4, 8, ORANGE, M.SmoothPlastic), b.Ball(-4, 42, -9.5, 2.4, INK, M.SmoothPlastic), b.Ball(4, 42, -9.5, 2.4, INK, M.SmoothPlastic) }
	-- 2 : canette de soda
	local can = { b.Cyl(0, 18, 0, 16, 26, RED, M.Metal), b.Cyl(0, 44, 0, 14, 1.6, CHROME, M.Metal), b.Cyl(0, 30, 0, 16.4, 5, WHITE, M.SmoothPlastic) }
	-- 3 : pastèque
	local melon = { b.Egg(0, 30, 0, 30, 24, 24, rgb(70, 170, 80), M.SmoothPlastic), b.Egg(0, 30, 0, 30.6, 12, 24.6, rgb(40, 120, 60), M.SmoothPlastic) }
	for variant, list in ipairs({ duck, can, melon }) do
		for _, part in ipairs(list) do
			part.Name = "Crushable"
			part:SetAttribute("Variant", variant)
		end
	end
	-- pupitre de commande (à droite) : gros bouton rouge, manomètre
	local px, pz = 44, 20
	b.Box(px + 6, 0, pz, 3, 42, 3, frame, M.Metal)
	b.BoxR(CFrame.new(px + 6, 46, pz) * CFrame.Angles(-0.4, 0, 0), 16, 12, 10, yellowC, M.Metal)
	b.CylZ(px + 6, 47, pz + 4.6, 9, 1.4, INK, M.Metal)
	local button = b.Part("Part", CFrame.new(px + 6, 47.4, pz + 6) * CFrame.Angles(-0.4, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(3, 7, 7), RED, M.SmoothPlastic, "PressButton")
	;(button :: Part).Shape = Enum.PartType.Cylinder
	b.Ball(px + 6, 48.6, pz + 8.4, 5, RED, M.SmoothPlastic).Name = "PressButton"
	b.CylZ(px + 1, 52, pz + 2, 6, 1, WHITE, M.SmoothPlastic)
	named(b.BoxR(CFrame.new(px + 1, 52.6, pz + 2.6) * CFrame.Angles(0, 0, 0.6), 0.5, 2.6, 0.3, RED, M.SmoothPlastic), "Gauge")
	-- gyrophare
	b.Cyl(0, 98, -6, 8, 2, frame, M.Metal)
	neon(b, b.Egg(0, 102, -6, 7, 8, 7, ORANGE, M.Neon), "PressBeacon")
	-- tuyaux hydrauliques
	House3DKit.Path(b, { { -20, 90, -18 }, { -40, 90, -20 }, { -44, 40, -18 }, { -44, 8, -16 } }, 2.4, INK, M.Rubber, false, true)
	b.Footprint(100, 56, 106)
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
	b.CylX(0, T + 9, -18, 12, 84.4, rgb(230, 244, 255), M.SmoothPlastic).Transparency = 0.55
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
		b.Cyl(0, 18, 0, 74, 1.4, rim, M.Metal)
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
		b.Cyl(0, 29.4, 0, 40, 1, rgb(110, 76, 56), M.Grass)
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
