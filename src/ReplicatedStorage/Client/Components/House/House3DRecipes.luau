--[[
	House3DRecipes (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DRecipes

	Recettes 3D des objets de la maison pour la vue 3D (House3D) : chaque
	recette construit l'objet avec de VRAIES pièces (blocs, cylindres,
	boules, pentes) via un House3DKit.Builder, en unités de la boîte 2D
	(100 = taille de l'objet ; y = hauteur depuis le sol ; z = vers l'avant).
	Les couleurs viennent de la palette du dessin 2D de l'objet (b.Pal,
	b.P(i, défaut)) ; les dessus des meubles sont à la hauteur donnée par
	HouseSurfaces (R.TopY) pour que les objets posés dessus tombent juste.

	Recette = function(b: Builder, R: Ctx)
	v9.3 : les 354 objets ont un vrai modèle 3D (ici + House3DCritters,
	House3DObjects, House3DToys) ; un objet inconnu (future mise à jour)
	reçoit une forme 3D de repli à ses couleurs, jamais un carton.

	API :
	  House3DRecipes.For(item) -> (Recipe, Info)   Info = { Wall = contre le mur ?, Flat = tapis ?, Pet = animal ? }
	  House3DRecipes.Has(itemId) -> boolean
	  House3DRecipes.Make(item, entry, k, parent, origin, trim?) -> ItemData  (pièces au repère `origin`, devant +Z)

	API du monde (Dopamine Town ; aucun lien avec la vue 3D, la caméra ou l'interface) :
	  House3DRecipes.BuildItem(itemId, entry?, options?) -> Model?
	    entry : { S?, F?, C? } (taille, miroir, variante de couleur ; R n'est
	    PAS appliqué ici : c'est l'appelant qui tourne le modèle)
	    options : Scale (studs par px de la pièce 2D, 0.05 par défaut : la
	    boîte 2D fait item.Size x S x Scale studs), Night, Collide (true),
	    Query (true), Trim (Color3), Shadows (true)
	    Modèle : toutes les pièces Anchored, CanTouch = false ; pièces visibles
	    CanCollide = false, CanQuery = Query ; PrimaryPart "Root" (invisible,
	    0.1 d'épaisseur) ; pivot = bas du centre de l'empreinte (objet mural :
	    bas de sa boîte 2D, contre le mur, l'objet avance vers -Z) ; DEVANT =
	    -Z ; gros meubles au sol : "Hitbox" invisible CanCollide = true jusqu'à
	    l'assise / au dessus ; "SeatPart" (Part transparente, face -Z) pour
	    s'asseoir ; attributs ItemId, Footprint (Vector3 L, H, P), TopHeight,
	    TopCenter (Vector3, repère du modèle), TopSize (Vector2), Wall,
	    AgainstWall, Flat, Pet.
	  House3DRecipes.BuildModel(itemId, entry?, options?) -> (Model?, ItemData?)
]]

local HouseSurfaces = require(script.Parent.HouseSurfaces)
local House3DKit = require(script.Parent.House3DKit)

type Builder = House3DKit.Builder

export type Ctx = {
	Item: any,
	Raw: { { number } }?,
	TopY: (index: number, default: number) -> number,
	Span: (index: number, default0: number, default1: number) -> (number, number),
	Trim: Color3,
}
export type Recipe = (b: Builder, R: Ctx) -> ()
export type Info = { Wall: boolean, Flat: boolean, Glow: boolean, Pet: boolean }

local House3DRecipes = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CREAM = rgb(255, 247, 236)
local WOOD = rgb(214, 164, 120)
local WOOD_LIGHT = rgb(236, 196, 150)
local WOOD_DARK = rgb(160, 110, 78)
local PINK = rgb(255, 126, 182)
local PINK_SOFT = rgb(255, 214, 232)
local LILAC = rgb(183, 148, 246)
local MINT = rgb(110, 214, 176)
local SKY = rgb(150, 205, 255)
local BUTTER = rgb(255, 226, 130)
local GOLD = rgb(245, 190, 60)
local GREY = rgb(200, 196, 210)
local GREY_DARK = rgb(120, 116, 136)
local INK = rgb(70, 48, 76)
local LEAF = rgb(120, 200, 120)
local LEAF_DARK = rgb(70, 150, 90)
local GLASS = rgb(200, 235, 255)
local FIRE = rgb(255, 150, 60)

local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

----------------------------------------------------------------------
-- Couleurs de la palette
----------------------------------------------------------------------

local function isWoody(h: number, s: number, v: number): boolean
	return h >= 0.02 and h <= 0.13 and s >= 0.18 and s <= 0.75 and v >= 0.35 and v <= 0.95
end

local function woodOf(b: Builder, fallback: Color3?): Color3
	return House3DKit.Wood(b.Pal, b.Map(fallback or WOOD_LIGHT))
end

-- n-ième couleur "vive" (ni bois, ni presque blanc / noir / gris)
local function accent(b: Builder, n: number, fallback: Color3): Color3
	local count = 0
	for _, color in ipairs(b.Pal) do
		local h, s, v = color:ToHSV()
		if s > 0.16 and v > 0.3 and not isWoody(h, s, v) then
			count += 1
			if count == n then
				return color
			end
		end
	end
	return b.Map(fallback)
end

local function greenOf(b: Builder, fallback: Color3): Color3
	return House3DKit.Pick(b.Pal, function(h, s, v)
		return h > 0.2 and h < 0.45 and s > 0.2 and v > 0.3
	end, b.Map(fallback))
end

local function lightOf(b: Builder, fallback: Color3): Color3
	return House3DKit.Pick(b.Pal, function(_h, s, v)
		return s < 0.14 and v > 0.86
	end, b.Map(fallback))
end

----------------------------------------------------------------------
-- Petits morceaux réutilisés
----------------------------------------------------------------------

local function legs4(b: Builder, w: number, d: number, h: number, t: number, color: Color3, material: Enum.Material?)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * (w / 2 - t / 2), 0, sz * (d / 2 - t / 2), t, h, t, color, material)
		end
	end
end

local function knob(b: Builder, x: number, y: number, z: number, size: number, color: Color3?)
	b.Ball(x, y, z, size, color or GOLD, M.Metal)
end

-- Caisson (commode, table de nuit...) : corps, tiroirs / portes, poignées
local function cabinet(b: Builder, w: number, d: number, h: number, body: Color3, front: Color3, drawers: number, doors: number, feet: number)
	local y0 = feet
	if feet > 0 then
		legs4(b, w - 6, d - 6, feet, 5, darken(body, 0.2), M.Wood)
	end
	b.Box(0, y0, 0, w, h - y0, d, body, M.Wood)
	local rows = math.max(drawers, 0)
	local inner = h - y0 - 6
	if rows > 0 then
		local rowH = inner / rows
		for index = 1, rows do
			local y = y0 + 3 + (index - 1) * rowH
			b.Box(0, y + 1, d / 2, w - 8, rowH - 2, 1.4, front, M.SmoothPlastic)
			knob(b, 0, y + rowH / 2, d / 2 + 1.6, 4)
		end
	elseif doors > 0 then
		local doorW = (w - 8) / doors
		for index = 1, doors do
			local x = -w / 2 + 4 + (index - 0.5) * doorW
			b.Box(x, y0 + 3, d / 2, doorW - 2, inner, 1.4, front, M.SmoothPlastic)
			local side = (index - 0.5) < doors / 2 and 1 or -1
			knob(b, x + side * (doorW / 2 - 5), y0 + 3 + inner * 0.55, d / 2 + 1.6, 4)
		end
	end
end

-- Cheveux d'herbe / feuillage en boules
local function bush(b: Builder, x: number, y: number, z: number, size: number, color: Color3, count: number)
	b.Ball(x, y, z, size, color, M.SmoothPlastic)
	for index = 1, count do
		local angle = index / count * math.pi * 2
		b.Ball(x + math.cos(angle) * size * 0.34, y + (index % 2 == 0 and 0.12 or -0.1) * size, z + math.sin(angle) * size * 0.3, size * 0.62,
			index % 2 == 0 and color or darken(color, 0.12), M.SmoothPlastic)
	end
end

local function pot(b: Builder, diameter: number, height: number, color: Color3)
	b.Cyl(0, 0, 0, diameter * 0.82, height * 0.2, darken(color, 0.12), M.SmoothPlastic)
	b.Cyl(0, height * 0.2, 0, diameter * 0.9, height * 0.62, color, M.SmoothPlastic)
	b.Cyl(0, height * 0.82, 0, diameter, height * 0.18, lighten(color, 0.15), M.SmoothPlastic)
	b.Cyl(0, height * 0.9, 0, diameter * 0.86, height * 0.12, rgb(120, 86, 70), M.Ground)
end

----------------------------------------------------------------------
-- Recettes
----------------------------------------------------------------------

local R: { [string]: Recipe } = {}

-- TABLES --------------------------------------------------------------

local function rectTable(depth: number, cloth: boolean, legColor: Color3?)
	return function(b: Builder, ctx: Ctx)
		local top = ctx.TopY(1, 60)
		local x0, x1 = ctx.Span(1, -48, 48)
		local w = x1 - x0
		local wood = woodOf(b)
		local legs = legColor and b.Map(legColor) or darken(wood, 0.12)
		legs4(b, w - 8, depth - 8, top - 5, 6, legs, M.Wood)
		b.Box((x0 + x1) / 2, top - 11, 0, w - 12, 6, depth - 12, darken(wood, 0.08), M.Wood)
		b.Box((x0 + x1) / 2, top - 5, 0, w, 5, depth, wood, M.Wood)
		if cloth then
			local clothColor = lightOf(b, WHITE)
			b.Box((x0 + x1) / 2, top - 0.2, 0, w * 0.74, 0.6, depth + 1.2, clothColor, M.Fabric)
			b.Box((x0 + x1) / 2, top - 9, depth / 2 + 0.5, w * 0.74, 9, 0.6, clothColor, M.Fabric)
			b.Box((x0 + x1) / 2, top - 9, -depth / 2 - 0.5, w * 0.74, 9, 0.6, clothColor, M.Fabric)
			b.Ball((x0 + x1) / 2, top - 7, depth / 2 + 1, 4, accent(b, 1, PINK))
		end
		b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
		b.Footprint(w, depth, top)
	end
end

R.DiningTable = rectTable(58, true)
R.CoffeeTable = function(b, ctx)
	local top = ctx.TopY(1, 49)
	local x0, x1 = ctx.Span(1, -47, 47)
	local w, depth = x1 - x0, 52
	local wood = woodOf(b)
	legs4(b, w - 10, depth - 10, top - 5, 7, darken(wood, 0.15), M.Wood)
	b.Box(0, top * 0.25, 0, w - 14, 3, depth - 14, darken(wood, 0.05), M.Wood)
	b.Box(0, top - 6, 0, w, 6, depth, wood, M.Wood)
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.SideTable = rectTable(60, false)
R.BigDesk = function(b, ctx)
	rectTable(56, false)(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -48, 48)
	local wood = woodOf(b)
	-- caisson à tiroirs à droite
	local cw = (x1 - x0) * 0.3
	b.Box(x1 - cw / 2 - 3, 0, 0, cw, top - 6, 48, darken(wood, 0.05), M.Wood)
	for index = 1, 3 do
		local y = 4 + (index - 1) * (top - 12) / 3
		b.Box(x1 - cw / 2 - 3, y, 24, cw - 5, (top - 12) / 3 - 2, 1.2, accent(b, 1, PINK_SOFT))
		knob(b, x1 - cw / 2 - 3, y + (top - 12) / 6, 25.5, 3.4)
	end
end
R.StudyDesk = R.BigDesk
R.PicnicTable = function(b, ctx)
	local top = ctx.TopY(1, 61)
	local bench = ctx.TopY(2, 29)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 44
	local wood = woodOf(b, WOOD)
	legs4(b, w - 16, depth - 10, top - 4, 6, darken(wood, 0.15), M.Wood)
	b.Box(0, top - 4, 0, w, 4, depth, wood, M.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		legs4(b, w - 20, 12, bench - 4, 5, darken(wood, 0.15), M.Wood)
		b.Box(0, bench - 4, side * (depth / 2 + 12), w + 2, 4, 14, wood, M.WoodPlanks)
		b.Box(0, 0, side * (depth / 2 + 12), 4, bench - 4, 4, darken(wood, 0.15), M.Wood)
	end
	-- nappe vichy
	b.Box(0, top, 0, w * 0.5, 0.5, depth * 0.8, accent(b, 1, rgb(255, 150, 170)), M.Fabric)
	b.Top(1, 0, top, 0, w, depth)
	b.Top(2, 0, bench, depth / 2 + 12, w, 14)
	b.Footprint(w, depth + 40, top)
end
R.KitchenIsland = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -48, 48)
	local w, depth = x1 - x0, 50
	local body = accent(b, 1, MINT)
	b.Box(0, 0, 0, w - 4, 4, depth - 6, darken(body, 0.25))
	b.Box(0, 4, 0, w - 4, top - 10, depth - 4, body, M.SmoothPlastic)
	for index = 1, 3 do
		local x = -w / 2 + 2 + (index - 0.5) * (w - 4) / 3
		b.Box(x, 8, depth / 2 - 1.5, (w - 4) / 3 - 3, top - 18, 1.2, lighten(body, 0.2))
		b.Box(x, top - 22, depth / 2, 12, 2, 2, GREY, M.Metal)
	end
	b.Box(0, top - 6, 0, w, 6, depth, lightOf(b, rgb(248, 246, 252)), M.Marble)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
local function roundTable(b: Builder, ctx: Ctx, defaultTop: number)
	local top = ctx.TopY(1, defaultTop)
	local x0, x1 = ctx.Span(1, -44, 44)
	local w = x1 - x0
	local wood = woodOf(b, WOOD_LIGHT)
	local metal = b.Map(GREY)
	b.Cyl(0, 0, 0, w * 0.5, 3, darken(metal, 0.2), M.Metal)
	b.Cyl(0, 3, 0, 8, top - 8, metal, M.Metal)
	b.Cyl(0, top - 5, 0, w, 5, accent(b, 1, wood), M.SmoothPlastic)
	b.Cyl(0, top - 5.4, 0, w + 2, 1.6, lighten(accent(b, 1, wood), 0.3), M.SmoothPlastic)
	if top > 60 then
		b.Cyl(0, top * 0.3, 0, w * 0.46, 2, GOLD, M.Metal)
	end
	b.Top(1, 0, top, 0, w * 0.8, w * 0.8)
	b.Footprint(w, w, top)
end
R.CafeTable = function(b, ctx)
	roundTable(b, ctx, 70)
end
R.BarTable = function(b, ctx)
	roundTable(b, ctx, 84)
end
R.VanityTable = function(b, ctx)
	local top = ctx.TopY(1, 45)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 44
	local wood = lightOf(b, CREAM)
	local trim = accent(b, 1, PINK)
	legs4(b, w - 6, depth - 6, top - 10, 5, wood, M.Wood)
	b.Box(0, top - 10, 0, w, 10, depth, wood, M.Wood)
	b.Box(0, top - 8, depth / 2, w * 0.5, 6, 1.2, trim)
	knob(b, 0, top - 5, depth / 2 + 1.4, 3)
	-- miroir ovale
	local mirrorH = math.max(20, 96 - top)
	b.Box(0, top, -depth / 2 + 3, 10, mirrorH * 0.3, 4, wood, M.Wood)
	local frame = b.CylZ(0, top + mirrorH * 0.55, -depth / 2 + 3, mirrorH * 0.9, 3, trim, M.SmoothPlastic)
	frame.Name = "Cadre"
	local glass = b.CylZ(0, top + mirrorH * 0.55, -depth / 2 + 4, mirrorH * 0.76, 2, rgb(214, 238, 255), M.Glass)
	glass.Reflectance = 0.2
	b.Top(1, 0, top, 4, w, depth - 10)
	b.Footprint(w, depth, 100)
end

-- RANGEMENTS -----------------------------------------------------------

R.Nightstand = function(b, ctx)
	local top = ctx.TopY(1, 56)
	local x0, x1 = ctx.Span(1, -42, 42)
	local w, depth = x1 - x0, 60
	local body = woodOf(b, WOOD_LIGHT)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, PINK_SOFT), 2, 0, 6)
	b.Box(0, top - 4, 0, w + 4, 4, depth + 4, lighten(body, 0.1), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 4, depth + 4, top)
end
R.Dresser = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 50
	local body = woodOf(b, WOOD_LIGHT)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, PINK_SOFT), 3, 0, 6)
	b.Box(0, top - 4, 0, w + 4, 4, depth + 3, lighten(body, 0.12), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 4, depth + 3, top)
end
R.DrawerCabinet = function(b, ctx)
	local top = ctx.TopY(1, 76)
	local x0, x1 = ctx.Span(1, -43, 44)
	local w, depth = x1 - x0, 44
	local body = woodOf(b, WOOD_LIGHT)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, rgb(255, 200, 220)), 4, 0, 5)
	b.Box(0, top - 4, 0, w + 3, 4, depth + 3, lighten(body, 0.12), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.TVStand = function(b, ctx)
	local top = ctx.TopY(1, 47)
	local x0, x1 = ctx.Span(1, -48, 48)
	local w, depth = x1 - x0, 40
	local body = woodOf(b, WOOD)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, lighten(body, 0.2)), 0, 3, 5)
	b.Box(0, top - 4, 0, w + 2, 4, depth + 2, lighten(body, 0.1), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 2, depth + 2, top)
end
R.Wardrobe = function(b, ctx)
	local top = ctx.TopY(1, 89)
	local x0, x1 = ctx.Span(1, -44, 44)
	local w, depth = x1 - x0, 42
	local body = woodOf(b, WOOD_LIGHT)
	local front = accent(b, 1, rgb(255, 200, 220))
	cabinet(b, w, depth, top - 5, body, front, 0, 2, 6)
	b.Box(0, top - 5, 0, w + 5, 5, depth + 4, lighten(body, 0.12), M.Wood)
	-- petits cœurs / médaillons sur les portes
	for _, side in ipairs({ -1, 1 }) do
		b.CylZ(side * w * 0.24, top * 0.7, depth / 2 + 1.6, 8, 1, lighten(front, 0.35))
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 5, depth + 4, top)
end
R.Bookshelf = function(b, ctx)
	local top = ctx.TopY(1, 91)
	local x0, x1 = ctx.Span(1, -42, 42)
	local w, depth = x1 - x0 + 4, 30
	local wood = woodOf(b, WOOD)
	b.Box(0, 0, -depth / 2 + 1, w, top, 2, darken(wood, 0.2), M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 2), 0, 0, 4, top, depth, wood, M.Wood)
	end
	local shelves = 4
	local colors = {}
	for index = 1, 6 do
		colors[index] = accent(b, index, ({ PINK, SKY, MINT, BUTTER, LILAC, rgb(255, 170, 120) })[index])
	end
	for index = 0, shelves do
		local y = index * (top - 4) / shelves
		b.Box(0, y, 0, w - 4, 4, depth, wood, M.Wood)
		if index < shelves then
			-- livres
			local x = -w / 2 + 5
			local n = 0
			while x < w / 2 - 12 do
				n += 1
				local bw = 4 + ((n * 7 + index * 3) % 4)
				local bh = (top - 4) / shelves - 8 - ((n * 5 + index) % 5)
				if (n + index) % 5 ~= 0 then
					b.Box(x + bw / 2, y + 4, 2, bw, bh, depth - 8, colors[(n + index) % 6 + 1], M.SmoothPlastic)
				end
				x += bw + 0.6
			end
		end
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.StorageBox = function(b, ctx)
	local top = ctx.TopY(1, 53)
	local x0, x1 = ctx.Span(1, -36, 36)
	local w, depth = x1 - x0, 60
	local body = House3DKit.Pick(b.Pal, function(_h, s, v)
		return v > 0.4 and s > 0.1
	end, b.Map(rgb(214, 180, 140)))
	b.Box(0, 0, 0, w, top - 6, depth, body, M.Cardboard)
	b.Box(0, top - 6, 0, w + 3, 6, depth + 3, lighten(body, 0.1), M.Cardboard)
	b.Box(0, top - 18, depth / 2 + 0.6, 16, 6, 1, darken(body, 0.35))
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.Suitcase = function(b, _ctx)
	local body = accent(b, 1, PINK)
	b.Box(0, 4, 0, 70, 62, 30, body, M.Leather)
	for _, x in ipairs({ -20, 20 }) do
		b.Box(x, 4, 0, 5, 62, 31, darken(body, 0.25), M.Leather)
	end
	b.Box(0, 66, 0, 22, 4, 6, INK)
	b.Box(0, 66, 0, 5, 8, 6, INK)
	for _, x in ipairs({ -28, 28 }) do
		b.Ball(x, 3, 12, 6, INK, M.Rubber)
	end
	b.Top(1, 0, 70, 0, 70, 30)
	b.Footprint(70, 30, 72)
end

-- SIÈGES -----------------------------------------------------------------

local function chair(b: Builder, ctx: Ctx, seatDefault: number, backH: number, width: number, depth: number, padColor: Color3?)
	local seat = ctx.TopY(1, seatDefault)
	local wood = woodOf(b, WOOD)
	legs4(b, width - 4, depth - 4, seat - 5, 5, darken(wood, 0.1), M.Wood)
	b.Box(0, seat - 5, 0, width, 5, depth, wood, M.Wood)
	if padColor then
		b.Box(0, seat, 1, width - 6, 2.2, depth - 8, padColor, M.Fabric)
	end
	-- dossier (derrière = -z)
	b.Box(-width / 2 + 3, seat, -depth / 2 + 2.5, 5, backH, 5, darken(wood, 0.05), M.Wood)
	b.Box(width / 2 - 3, seat, -depth / 2 + 2.5, 5, backH, 5, darken(wood, 0.05), M.Wood)
	b.Box(0, seat + backH * 0.45, -depth / 2 + 2.5, width - 6, backH * 0.5, 3, padColor or wood, padColor and M.Fabric or M.Wood)
	b.Top(1, 0, seat + (padColor and 2 or 0), 3, width - 10, depth - 10)
	b.Footprint(width, depth, seat + backH)
end
R.WoodenChair = function(b, ctx)
	chair(b, ctx, 48, 44, 64, 56, nil)
end
R.DiningChair = function(b, ctx)
	chair(b, ctx, 48, 44, 52, 52, accent(b, 1, PINK_SOFT))
end
R.RockingChair = function(b, ctx)
	chair(b, ctx, 43, 50, 58, 54, accent(b, 1, rgb(255, 190, 200)))
	local wood = woodOf(b, WOOD)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 27, 3, 0) * CFrame.Angles(0.12, 0, 0), 4, 3, 74, darken(wood, 0.2), M.Wood)
	end
end
R.GamingChair = function(b, ctx)
	local seat = ctx.TopY(1, 37)
	local main = accent(b, 1, PINK)
	local dark = darken(accent(b, 2, INK), 0.2)
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 12, 2, math.sin(angle) * 12) * CFrame.Angles(0, -angle, 0), 26, 3, 4, dark, M.Metal)
		b.Ball(math.cos(angle) * 24, 2, math.sin(angle) * 24, 4, INK, M.Rubber)
	end
	b.Cyl(0, 3, 0, 6, seat - 10, GREY, M.Metal)
	b.Box(0, seat - 8, 0, 54, 8, 50, main, M.Leather)
	b.Box(0, seat - 8, -22, 50, 60, 8, main, M.Leather)
	b.Box(0, seat + 10, -18, 20, 40, 1, dark, M.Leather)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 26, seat, 2, 4, 14, 30, dark, M.Leather)
		b.Wedge(side * 16, seat + 52, -22, 10, 12, 8, dark, "Front", M.Leather)
	end
	b.Top(1, 0, seat, 4, 44, 36)
	b.Footprint(56, 56, seat + 60)
end
R.BarStool = function(b, ctx)
	local seat = ctx.TopY(1, 74)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 34, 3, GREY_DARK, M.Metal)
	b.Cyl(0, 3, 0, 6, seat - 10, GREY, M.Metal)
	b.Cyl(0, seat * 0.35, 0, 30, 2, GOLD, M.Metal)
	b.Cyl(0, seat - 8, 0, 46, 8, color, M.Leather)
	b.Top(1, 0, seat, 0, 36, 36)
	b.Footprint(46, 46, seat)
end
R.MushroomStool = function(b, ctx)
	local seat = ctx.TopY(1, 85)
	local cap = accent(b, 1, rgb(255, 110, 120))
	local stem = lightOf(b, CREAM)
	b.Cyl(0, 0, 0, 34, seat * 0.62, stem, M.SmoothPlastic)
	b.Cyl(0, seat * 0.55, 0, 86, seat * 0.3, cap, M.SmoothPlastic)
	b.Cyl(0, seat * 0.85 - 1, 0, 70, seat * 0.15 + 1, lighten(cap, 0.08), M.SmoothPlastic)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		b.Ball(math.cos(angle) * 30, seat * 0.72, math.sin(angle) * 30, 12, WHITE)
	end
	b.Ball(0, seat - 1, 0, 14, WHITE)
	b.Top(1, 0, seat, 0, 50, 50)
	b.Footprint(86, 86, seat)
end
R.FloorCushion = function(b, ctx)
	local seat = ctx.TopY(1, 51)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 90, seat * 0.8, color, M.Fabric)
	b.Cyl(0, seat * 0.7, 0, 76, seat * 0.3, lighten(color, 0.12), M.Fabric)
	b.Ball(0, seat - 2, 0, 10, darken(color, 0.2), M.Fabric)
	b.Top(1, 0, seat, 0, 60, 60)
	b.Footprint(90, 90, seat)
end
R.Beanbag = function(b, _ctx)
	local color = accent(b, 1, LILAC)
	-- pouf poire : grosse goutte affaissée, creux d'assise, dossier relevé
	b.Egg(0, 24, 2, 92, 48, 86, color, M.Fabric)
	b.EggR(CFrame.new(0, 50, -18) * CFrame.Angles(-0.35, 0, 0), 70, 50, 40, darken(color, 0.05), M.Fabric)
	b.Egg(0, 44, 12, 56, 12, 46, lighten(color, 0.12), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.Egg(side * 32, 30, 8, 26, 30, 50, darken(color, 0.03), M.Fabric)
	end
	b.Ball(26, 20, 40, 5, lighten(color, 0.4), M.Fabric)
	b.Top(1, 0, 50, 10, 50, 40)
	b.Seat(0, 48, 10, 50, 40)
	b.Footprint(92, 86, 76)
end
local function sofa(b: Builder, ctx: Ctx, seatDefault: number, width: number, cushions: number)
	local seat = ctx.TopY(1, seatDefault)
	local main = accent(b, 1, PINK)
	local depth = 56
	local wood = woodOf(b, WOOD_DARK)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * (width / 2 - 8), 0, sz * (depth / 2 - 8), 6, 7, wood, M.Wood)
		end
	end
	b.Box(0, 7, 0, width, seat - 16, depth, darken(main, 0.08), M.Fabric)
	local cw = (width - 20) / cushions
	for index = 1, cushions do
		local x = -width / 2 + 10 + (index - 0.5) * cw
		b.Box(x, seat - 9, 4, cw - 1.5, 9, depth - 12, main, M.Fabric)
		b.Box(x, seat, -depth / 2 + 7, cw - 2, 30, 12, main, M.Fabric)
	end
	b.Box(0, 7, -depth / 2 + 3, width, seat + 26, 6, darken(main, 0.12), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (width / 2 - 5), 7, 0, 10, seat, depth, darken(main, 0.04), M.Fabric)
		b.CylZ(side * (width / 2 - 5), seat + 7, 0, 12, depth, lighten(main, 0.06), M.Fabric)
	end
	-- petit coussin
	local pillow = accent(b, 2, BUTTER)
	b.BoxR(CFrame.new(-width / 2 + 22, seat + 8, -depth / 2 + 16) * CFrame.Angles(-0.3, 0.2, 0.1), 16, 16, 5, pillow, M.Fabric)
	b.Top(1, 0, seat, 4, width - 26, depth - 16)
	b.Footprint(width, depth, seat + 30)
end
R.Sofa = function(b, ctx)
	sofa(b, ctx, 38, 100, 3)
end
R.Armchair = function(b, ctx)
	sofa(b, ctx, 37, 96, 1)
end
R.EggChair = function(b, ctx)
	local seat = ctx.TopY(1, 39)
	local shell = lightOf(b, WHITE)
	local pad = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 44, 4, GREY_DARK, M.Metal)
	b.Cyl(0, 4, 0, 6, seat - 14, GREY, M.Metal)
	b.Ball(0, seat + 18, -6, 80, shell, M.SmoothPlastic)
	b.Ball(0, seat + 16, 10, 62, pad, M.Fabric)
	b.Box(0, seat - 6, 12, 50, 6, 30, pad, M.Fabric)
	b.Top(1, 0, seat, 14, 40, 26)
	b.Footprint(80, 80, seat + 58)
end
R.GardenBench = function(b, ctx)
	local seat = ctx.TopY(1, 41)
	local wood = woodOf(b, WOOD)
	local metal = b.Map(rgb(90, 90, 110))
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 44, 0, 0, 4, seat + 12, 36, metal, M.Metal)
	end
	for index = 0, 3 do
		b.Box(0, seat - 3, -14 + index * 9.5, 88, 3, 8, wood, M.WoodPlanks)
	end
	for index = 0, 2 do
		b.BoxR(CFrame.new(0, seat + 8 + index * 9, -19 - index * 1.2) * CFrame.Angles(-0.15, 0, 0), 88, 7, 3, wood, M.WoodPlanks)
	end
	b.Top(1, 0, seat, 0, 80, 30)
	b.Footprint(92, 40, seat + 34)
end

-- LITS ---------------------------------------------------------------------

local function bed(b: Builder, ctx: Ctx, topDefault: number, width: number, depth: number)
	local top = ctx.TopY(1, topDefault)
	local wood = woodOf(b, WOOD_LIGHT)
	local blanket = accent(b, 1, PINK)
	local sheet = lightOf(b, WHITE)
	local frameTop = top - 12
	legs4(b, width - 2, depth - 2, frameTop, 6, darken(wood, 0.1), M.Wood)
	b.Box(0, frameTop * 0.45, 0, width, frameTop * 0.55, depth, wood, M.Wood)
	b.Box(0, frameTop, 0, width - 4, 12, depth - 4, sheet, M.Fabric)
	-- tête de lit (gauche) et pied (droite)
	b.Box(-width / 2 + 3, 0, 0, 6, top + 28, depth, wood, M.Wood)
	b.CylZ(-width / 2 + 3, top + 28, 0, 10, depth, lighten(wood, 0.1), M.Wood)
	b.Box(width / 2 - 3, 0, 0, 6, top + 8, depth, wood, M.Wood)
	-- couverture (retombe sur les côtés) + revers
	b.Box(width * 0.12, frameTop + 2, 0, width * 0.72, 11, depth, blanket, M.Fabric)
	b.Box(width * 0.12, frameTop - 8, depth / 2 + 0.5, width * 0.72, 12, 1, darken(blanket, 0.05), M.Fabric)
	b.Box(-width * 0.2, frameTop + 2.4, 0, 8, 11, depth + 0.2, lighten(blanket, 0.4), M.Fabric)
	-- oreillers
	local n = depth > 60 and 2 or 1
	for index = 1, n do
		local z = n == 1 and 0 or (index == 1 and -depth * 0.22 or depth * 0.22)
		b.BoxR(CFrame.new(-width / 2 + 16, top + 4, z) * CFrame.Angles(0, 0, -0.35), 18, 7, depth / n - 8, sheet, M.Fabric)
	end
	b.Top(1, 0, top + 1, 0, width - 20, depth - 10)
	b.Footprint(width, depth, top + 28)
end
R.DoubleBed = function(b, ctx)
	bed(b, ctx, 42, 100, 76)
end
R.CanopyBed = function(b, ctx)
	bed(b, ctx, 36, 70, 60)
	local wood = woodOf(b, WOOD_LIGHT)
	local drape = accent(b, 2, PINK_SOFT)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 34, 0, sz * 29, 4, 98, wood, M.Wood)
			b.Ball(sx * 34, 99, sz * 29, 6, GOLD, M.Metal)
		end
	end
	b.Box(0, 94, 0, 72, 3, 62, drape, M.Fabric)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, 82, sz * 30, 72, 12, 1, drape, M.Fabric)
	end
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 34, 50, 29, 6, 44, 2, lighten(drape, 0.2), M.Fabric)
	end
end
R.CloudBed = function(b, ctx)
	local top = ctx.TopY(1, 45)
	local cloud = lightOf(b, WHITE)
	local blanket = accent(b, 1, SKY)
	for index = 0, 6 do
		local x = -42 + index * 14
		b.Ball(x, 16, 0, 34 + (index % 2) * 6, index % 2 == 0 and cloud or rgb(236, 240, 255))
	end
	b.Box(0, 10, 0, 84, top - 22, 56, cloud, M.Fabric)
	b.Box(0, top - 12, 0, 80, 11, 54, WHITE, M.Fabric)
	b.Box(8, top - 10, 0, 60, 11, 55, blanket, M.Fabric)
	b.Ball(-40, top + 6, 0, 28, cloud)
	b.Ball(-30, top + 14, 0, 22, cloud)
	b.Ball(-32, top + 3, 0, 16, WHITE, M.Fabric)
	b.Top(1, 4, top, 0, 70, 50)
	b.Footprint(96, 60, top + 20)
end
R.LoftBed = function(b, ctx)
	local top = ctx.TopY(1, 77)
	local desk = ctx.TopY(2, 27)
	local wood = woodOf(b, WOOD)
	local blanket = accent(b, 1, LILAC)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 36, 0, sz * 22, 5, top + 14, 5, wood, M.Wood)
		end
	end
	b.Box(0, top - 12, 0, 76, 6, 48, wood, M.Wood)
	b.Box(0, top - 6, 0, 72, 6, 44, WHITE, M.Fabric)
	b.Box(6, top - 4, 0, 56, 5, 45, blanket, M.Fabric)
	b.Box(-26, top - 1, 0, 14, 5, 30, WHITE, M.Fabric)
	b.Box(0, top + 4, 22, 76, 4, 2, wood, M.Wood)
	-- bureau dessous
	b.Box(-14, desk - 4, 0, 44, 4, 40, lighten(wood, 0.15), M.Wood)
	-- échelle
	for _, x in ipairs({ 30, 42 }) do
		b.Box(x, 0, 26, 3, top, 3, darken(wood, 0.15), M.Wood)
	end
	for index = 1, 5 do
		b.Box(36, index * top / 6, 26, 12, 2.5, 2.5, darken(wood, 0.15), M.Wood)
	end
	b.Top(1, 0, top, 0, 60, 40)
	b.Top(2, -14, desk, 0, 40, 36)
	b.Footprint(80, 56, top + 14)
end
R.PetBed = function(b, _ctx)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 90, 22, color, M.Fabric)
	b.Cyl(0, 16, 0, 70, 7, lighten(color, 0.4), M.Fabric)
	b.Top(1, 0, 22, 0, 60, 60)
	b.Footprint(90, 90, 22)
end

-- CUISINE ---------------------------------------------------------------

R.Fridge = function(b, ctx)
	local top = ctx.TopY(1, 96)
	local body = House3DKit.Pick(b.Pal, function(_h, s, v)
		return v > 0.6
	end, b.Map(rgb(240, 250, 255)))
	local x0, x1 = ctx.Span(1, -30, 30)
	local w, depth = math.max(52, (x1 - x0) * 1.1), 46
	b.Box(0, 0, 0, w, 4, depth, darken(body, 0.3))
	b.Box(0, 4, 0, w, top - 4, depth, body, M.SmoothPlastic)
	b.Box(0, top * 0.62, depth / 2, w - 3, 1, 1, darken(body, 0.2))
	for _, y in ipairs({ top * 0.3, top * 0.8 }) do
		b.Box(w / 2 - 7, y - 8, depth / 2 + 1.2, 2.5, 18, 2.5, GREY, M.Metal)
	end
	b.CylZ(-w * 0.18, top * 0.8, depth / 2 + 0.8, 9, 1, accent(b, 1, PINK))
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.Stove = function(b, ctx)
	local top = ctx.TopY(1, 62)
	local x0, x1 = ctx.Span(1, -44, 44)
	local w, depth = x1 - x0, 50
	local body = accent(b, 1, rgb(255, 180, 190))
	b.Box(0, 0, 0, w, top - 4, depth, body, M.SmoothPlastic)
	b.Box(0, top - 4, 0, w + 2, 4, depth + 2, lightOf(b, WHITE), M.SmoothPlastic)
	b.Box(0, 8, depth / 2, w * 0.7, top * 0.5, 1.2, rgb(60, 50, 70), M.Glass)
	b.Box(0, top * 0.62, depth / 2 + 1, w * 0.6, 2.5, 2.5, GREY, M.Metal)
	for index = 1, 4 do
		knob(b, -w / 2 + index * w / 5, top - 10, depth / 2 + 1, 4, INK)
	end
	for _, x in ipairs({ -w / 4, w / 4 }) do
		for _, z in ipairs({ -depth / 4, depth / 4 }) do
			b.Cyl(x, top, z, 16, 1, rgb(70, 60, 80), M.Metal)
		end
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 2, depth + 2, top)
end
R.Microwave = function(b, _ctx)
	local body = lightOf(b, WHITE)
	b.Box(0, 0, 0, 90, 56, 50, body, M.SmoothPlastic)
	b.Box(-10, 8, 25, 56, 40, 1, rgb(50, 44, 70), M.Glass)
	b.Box(30, 8, 25, 18, 40, 1, accent(b, 1, PINK))
	b.Top(1, 0, 56, 0, 80, 46)
	b.Footprint(90, 50, 56)
end
R.Toaster = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 170, 190))
	b.Box(0, 0, 0, 80, 56, 44, body, M.SmoothPlastic)
	for _, z in ipairs({ -8, 8 }) do
		b.Box(0, 56, z, 60, 1, 7, INK)
		b.Box(0, 52, z, 40, 10, 5, rgb(222, 170, 110))
	end
	b.Box(42, 30, 0, 4, 6, 10, INK)
	b.Footprint(80, 44, 60)
end

-- SALLE DE BAIN ------------------------------------------------------------

R.Bathtub = function(b, ctx)
	local top = ctx.TopY(1, 54)
	local body = lightOf(b, WHITE)
	local w, depth = 96, 52
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(sx * 40, 4, sz * 18, 9, GOLD, M.Metal)
		end
	end
	b.Box(0, 6, 0, w, top - 10, depth, body, M.SmoothPlastic)
	b.Box(0, top - 4, 0, w + 2, 4, depth + 2, lighten(body, 0.2), M.SmoothPlastic)
	b.Box(0, top - 7, 0, w - 10, 4, depth - 10, rgb(170, 220, 255), M.Glass).Transparency = 0.15
	for index = 1, 7 do
		b.Ball(-30 + index * 9, top - 3, ((index * 13) % 20) - 10, 8 + index % 3 * 2, WHITE)
	end
	b.Cyl(-w / 2 + 6, top, 0, 4, 18, GREY, M.Metal)
	b.CylX(-w / 2 + 11, top + 17, 0, 4, 12, GREY, M.Metal)
	b.Box(0, 10, depth / 2 + 0.5, w * 0.6, 8, 1, accent(b, 1, PINK))
	b.Top(1, 0, top, 0, w - 8, depth - 8)
	b.Footprint(w + 2, depth + 2, top)
end
R.Toilet = function(b, ctx)
	local top = ctx.TopY(1, 82)
	local body = lightOf(b, WHITE)
	b.Cyl(0, 0, 8, 28, 26, body, M.SmoothPlastic)
	b.Cyl(0, 22, 10, 46, 12, body, M.SmoothPlastic)
	b.Cyl(0, 34, 10, 48, 3, accent(b, 1, PINK), M.SmoothPlastic)
	b.Box(0, 30, -20, 46, top - 30, 18, body, M.SmoothPlastic)
	b.Box(0, top - 3, -20, 50, 4, 20, lighten(body, 0.2), M.SmoothPlastic)
	b.Box(14, top - 12, -10, 8, 3, 2, GREY, M.Metal)
	b.Top(1, 0, top, -20, 40, 16)
	b.Footprint(50, 56, top)
end
R.Shower = function(b, _ctx)
	local tray = lightOf(b, WHITE)
	b.Box(0, 0, 0, 80, 6, 60, tray, M.SmoothPlastic)
	local glass = b.Box(0, 6, 29, 78, 90, 1.2, rgb(200, 230, 255), M.Glass)
	glass.Transparency = 0.6
	glass.CastShadow = false
	local side = b.Box(39, 6, 0, 1.2, 90, 58, rgb(200, 230, 255), M.Glass)
	side.Transparency = 0.6
	side.CastShadow = false
	b.Cyl(-30, 6, -26, 4, 92, GREY, M.Metal)
	b.CylZ(-30, 96, -18, 4, 16, GREY, M.Metal)
	b.Cyl(-30, 88, -10, 16, 3, GREY, M.Metal)
	b.Box(0, 96, 0, 82, 3, 60, accent(b, 1, SKY))
	b.Footprint(82, 62, 100)
end
R.HotSpring = function(b, _ctx)
	local stone = b.Map(rgb(170, 160, 180))
	for index = 0, 13 do
		local angle = index / 14 * math.pi * 2
		b.Ball(math.cos(angle) * 44, 10, math.sin(angle) * 30, 20 + index % 3 * 3, index % 2 == 0 and stone or darken(stone, 0.12), M.Slate)
	end
	b.Cyl(0, 0, 0, 80, 12, rgb(150, 210, 240), M.Glass)
	b.Cyl(0, 11, 0, 76, 2, rgb(190, 235, 255), M.SmoothPlastic)
	for index = 1, 5 do
		local steam = b.Ball(-20 + index * 8, 30 + index * 6, (index % 2) * 8, 14, WHITE)
		steam.Transparency = 0.55
		steam.CastShadow = false
	end
	b.Footprint(100, 70, 20)
end

-- LAMPES ---------------------------------------------------------------------

local function lampShade(b: Builder, y: number, diameter: number, height: number, color: Color3, light: Color3, range: number)
	local shade = b.Cyl(0, y, 0, diameter, height, color, M.Fabric)
	shade.CastShadow = false
	b.Cyl(0, y + height, 0, diameter * 0.8, 1, lighten(color, 0.3), M.Fabric)
	local bulb = b.Ball(0, y + height * 0.2, 0, diameter * 0.45, light)
	b.Neon(bulb)
	b.Light(bulb, light, range, 1)
end
R.FloorLamp = function(b, _ctx)
	local metal = b.Map(GOLD)
	local shade = accent(b, 1, PINK_SOFT)
	b.Cyl(0, 0, 0, 30, 4, metal, M.Metal)
	b.Cyl(0, 4, 0, 4, 72, metal, M.Metal)
	lampShade(b, 72, 36, 24, shade, BUTTER, 18)
	b.Footprint(36, 36, 100)
end
R.DeskLamp = function(b, _ctx)
	local color = accent(b, 1, MINT)
	b.Cyl(0, 0, 0, 40, 6, color, M.SmoothPlastic)
	b.BoxR(CFrame.new(-6, 30, 0) * CFrame.Angles(0, 0, 0.35), 5, 50, 5, color, M.SmoothPlastic)
	b.BoxR(CFrame.new(4, 58, 0) * CFrame.Angles(0, 0, -0.9), 5, 30, 5, color, M.SmoothPlastic)
	b.Ball(-14, 52, 0, 8, GREY, M.Metal)
	local head = b.BoxR(CFrame.new(18, 62, 0) * CFrame.Angles(0, 0, -0.6), 26, 14, 24, color, M.SmoothPlastic)
	head.CastShadow = false
	local bulb = b.Ball(22, 55, 0, 12, BUTTER)
	b.Neon(bulb)
	b.Light(bulb, BUTTER, 12, 0.9)
	b.Footprint(44, 40, 70)
end
R.LavaLamp = function(b, _ctx)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 34, 20, GREY_DARK, M.Metal)
	local glass = b.Cyl(0, 20, 0, 26, 56, lighten(color, 0.5), M.Glass)
	glass.Transparency = 0.25
	for index = 1, 3 do
		local blob = b.Ball(((index * 7) % 10) - 5, 28 + index * 14, 0, 12 - index, color)
		b.Neon(blob)
	end
	b.Cyl(0, 76, 0, 18, 10, GREY_DARK, M.Metal)
	b.Light(glass, color, 12, 0.9)
	b.Footprint(34, 34, 86)
end
R.MushroomLamp = function(b, _ctx)
	local cap = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 26, 50, CREAM, M.SmoothPlastic)
	local top = b.Cyl(0, 44, 0, 80, 18, cap, M.SmoothPlastic)
	top.CastShadow = false
	local glow = b.Cyl(0, 40, 0, 60, 4, BUTTER)
	b.Neon(glow)
	b.Ball(0, 60, 0, 30, lighten(cap, 0.1))
	for index = 1, 5 do
		local angle = index / 5 * math.pi * 2
		b.Ball(math.cos(angle) * 26, 58, math.sin(angle) * 26, 9, WHITE)
	end
	b.Light(glow, BUTTER, 12, 1)
	b.Footprint(80, 80, 72)
end
R.MoonLamp = function(b, _ctx)
	b.Cyl(0, 0, 0, 40, 6, woodOf(b, WOOD), M.Wood)
	b.Cyl(0, 6, 0, 4, 12, GREY, M.Metal)
	local moon = b.Ball(0, 50, 0, 64, lightOf(b, rgb(255, 244, 200)))
	b.Neon(moon)
	b.Light(moon, rgb(255, 236, 190), 14, 1)
	b.Footprint(64, 64, 82)
end
R.ScentedCandle = function(b, _ctx)
	local color = accent(b, 1, PINK_SOFT)
	b.Cyl(0, 0, 0, 70, 60, color, M.SmoothPlastic)
	b.Cyl(0, 58, 0, 60, 3, lighten(color, 0.3), M.SmoothPlastic)
	b.Cyl(0, 60, 0, 2, 8, INK)
	local flame = b.Ball(0, 74, 0, 12, FIRE)
	b.Neon(flame)
	b.Light(flame, rgb(255, 190, 120), 8, 0.8)
	b.Footprint(70, 70, 80)
end
R.OilLamp = function(b, _ctx)
	local metal = b.Map(GOLD)
	b.Cyl(0, 0, 0, 40, 6, metal, M.Metal)
	b.Ball(0, 20, 0, 40, metal, M.Metal)
	local glass = b.Cyl(0, 34, 0, 30, 40, rgb(255, 240, 210), M.Glass)
	glass.Transparency = 0.35
	local flame = b.Ball(0, 48, 0, 10, FIRE)
	b.Neon(flame)
	b.Cyl(0, 74, 0, 34, 4, metal, M.Metal)
	b.Light(flame, rgb(255, 190, 120), 10, 0.9)
	b.Footprint(40, 40, 80)
end
R.Candelabra = function(b, _ctx)
	local metal = b.Map(GOLD)
	b.Cyl(0, 0, 0, 34, 5, metal, M.Metal)
	b.Cyl(0, 5, 0, 5, 50, metal, M.Metal)
	b.CylX(0, 50, 0, 4, 56, metal, M.Metal)
	for _, x in ipairs({ -28, 0, 28 }) do
		b.Cyl(x, 50, 0, 10, 4, metal, M.Metal)
		b.Cyl(x, 54, 0, 8, 24, CREAM, M.SmoothPlastic)
		local flame = b.Ball(x, 83, 0, 7, FIRE)
		b.Neon(flame)
		if x == 0 then
			b.Light(flame, rgb(255, 190, 120), 10, 0.9)
		end
	end
	b.Footprint(64, 30, 88)
end

-- LUMIÈRES MURALES / SUSPENDUES (repère : bas de la boîte, y = 0..100) ---------

R.HangingBulb = function(b, _ctx)
	b.Cyl(0, 40, 0, 2, 70, INK)
	b.Cyl(0, 36, 0, 12, 10, GOLD, M.Metal)
	local bulb = b.Ball(0, 26, 0, 24, BUTTER)
	b.Neon(bulb)
	b.Light(bulb, BUTTER, 16, 1)
	b.Footprint(24, 24, 100)
end
R.PaperLantern = function(b, _ctx)
	local color = accent(b, 1, rgb(255, 140, 150))
	b.Cyl(0, 80, 0, 2, 30, INK)
	b.Cyl(0, 74, 0, 24, 6, INK)
	local lantern = b.Ball(0, 48, 0, 56, color, M.Fabric)
	b.Cyl(0, 20, 0, 24, 5, INK)
	b.Light(lantern, lighten(color, 0.4), 14, 1)
	table.insert(b.Glows, lantern)
	b.Footprint(56, 56, 100)
end
R.DiscoBall = function(b, _ctx)
	b.Cyl(0, 80, 0, 2, 30, GREY)
	local ball = b.Ball(0, 48, 0, 60, rgb(220, 220, 240), M.Foil)
	ball.Reflectance = 0.5
	b.Light(ball, accent(b, 1, LILAC), 16, 0.8)
	b.Footprint(60, 60, 100)
end
R.CloudLamp = function(b, _ctx)
	b.Cyl(0, 76, 0, 2, 40, GREY)
	for index = 0, 4 do
		local puff = b.Ball(-24 + index * 12, 50 + (index % 2) * 6, 0, 26 + (index % 2) * 8, WHITE)
		table.insert(b.Glows, puff)
		if index == 2 then
			b.Light(puff, rgb(255, 250, 235), 16, 0.9)
		end
	end
	b.Footprint(70, 36, 100)
end
R.FairyLights = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, BUTTER), accent(b, 3, MINT), accent(b, 4, SKY) }
	local count = 12
	for index = 0, count do
		local t = index / count
		local x = -48 + t * 96
		local y = 60 - math.sin(t * math.pi * 2) ^ 2 * 16
		b.Cyl(x, y - 1, 0.5, 1.2, 3, INK)
		local bulb = b.Ball(x, y - 4, 1, 6, colors[index % 4 + 1])
		b.Neon(bulb)
		if index % 6 == 3 then
			b.Light(bulb, colors[index % 4 + 1], 10, 0.6)
		end
	end
	b.Footprint(100, 4, 100)
end

-- ÉTAGÈRES MURALES (repère : bas de la boîte ; z = 0 contre le mur) --------

R.FloatingShelf = function(b, ctx)
	local wood = woodOf(b, WOOD)
	for index = 1, 2 do
		local y = ctx.TopY(index, index == 1 and 66 or 28)
		local x0, x1 = ctx.Span(index, -44, 44)
		b.Box((x0 + x1) / 2, y - 4, 11, x1 - x0 + 4, 4, 22, wood, M.Wood)
		for _, side in ipairs({ -1, 1 }) do
			b.Wedge((x0 + x1) / 2 + side * (x1 - x0) * 0.36, y - 14, 5, 3, 10, 10, darken(wood, 0.2), "Front", M.Wood)
		end
		b.Top(index, (x0 + x1) / 2, y, 11, x1 - x0, 18)
	end
	b.Footprint(100, 22, 100)
end
R.WallShelf = function(b, _ctx)
	local wood = woodOf(b, WOOD)
	b.Box(0, 44, 11, 96, 5, 22, wood, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Wedge(side * 36, 32, 5, 3, 12, 10, darken(wood, 0.2), "Front", M.Wood)
	end
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT) }
	for index = 1, 6 do
		b.Box(-40 + index * 5, 49, 10, 4.2, 18 + index % 3 * 3, 14, colors[index % 3 + 1])
	end
	b.Ball(28, 57, 10, 14, accent(b, 4, LEAF))
	b.Cyl(28, 49, 10, 12, 6, accent(b, 5, rgb(255, 170, 120)))
	b.Top(1, 0, 49, 11, 60, 18)
	b.Footprint(100, 22, 100)
end

-- FENÊTRES ET TABLEAUX (repère : bas de la boîte ; z = 0 contre le mur) --------

-- Fenêtre en relief : cadre (couleur des moulures), croisillon, rebord, vitre ;
-- la vue = le centre du dessin 2D de la fenêtre
local function windowRecipe(b: Builder, ctx: Ctx)
	local frame = ctx.Trim
	b.Art(0, 12, 0.5, 78, 76, 1.3)
	local glass = b.Box(0, 12, 3, 78, 76, 0.6, GLASS, M.Glass)
	glass.Transparency = 0.8
	glass.CastShadow = false
	b.Box(0, 88, 2.5, 90, 7, 6, frame)
	b.Box(0, 6, 2.5, 90, 6, 6, frame)
	for _, x in ipairs({ -42, 42 }) do
		b.Box(x, 12, 2.5, 6, 76, 6, frame)
	end
	b.Box(0, 12, 2.5, 3, 76, 4, frame)
	b.Box(0, 48.5, 2.5, 78, 3, 4, frame)
	b.Box(0, 1, 7, 100, 5, 14, frame)
	b.Footprint(100, 14, 100)
end
-- Tableau / affiche / calendrier : un cadre épais + le dessin sur la face avant
local function plaque(b: Builder, _ctx: Ctx)
	local back = darken(b.P(1, WOOD), 0.25)
	b.Box(0, 6, 1, 88, 88, 2, back, M.Wood)
	b.Art(0, 6, 2.1, 88, 88, 1)
	b.Footprint(88, 3, 100)
end
R.FramedPicture = plaque
R.MapPoster = plaque
R.WallCalendar = plaque

-- ÉLECTRONIQUE -----------------------------------------------------------

local function screen(b: Builder, x: number, y: number, z: number, w: number, h: number, color: Color3)
	local panel = b.Box(x, y, z, w, h, 1, color, M.SmoothPlastic)
	b.Neon(panel)
	panel.Color = color
	return panel
end
R.RetroTV = function(b, ctx)
	local top = ctx.TopY(1, 77)
	local body = accent(b, 1, rgb(255, 170, 190))
	legs4(b, 60, 36, 10, 4, INK, M.Wood)
	b.Box(0, 10, 0, 90, top - 10, 50, body, M.SmoothPlastic)
	b.Box(-10, 18, 25, 58, top - 30, 1, darken(body, 0.35))
	screen(b, -10, 21, 25.6, 52, top - 36, rgb(120, 180, 255))
	for index = 1, 2 do
		knob(b, 30, 20 + index * 16, 25.5, 7, INK)
	end
	b.BoxR(CFrame.new(-10, top + 12, -6) * CFrame.Angles(0, 0, 0.5), 1.5, 30, 1.5, GREY, M.Metal)
	b.BoxR(CFrame.new(4, top + 12, -6) * CFrame.Angles(0, 0, -0.5), 1.5, 30, 1.5, GREY, M.Metal)
	b.Top(1, 0, top, 0, 80, 44)
	b.Footprint(90, 50, top)
end
R.HomeCinema = function(b, _ctx)
	local wood = woodOf(b, WOOD_DARK)
	b.Box(0, 0, 0, 100, 18, 30, wood, M.Wood)
	b.Box(0, 18, -4, 8, 12, 8, GREY_DARK, M.Metal)
	b.Box(0, 28, -4, 96, 56, 4, INK, M.SmoothPlastic)
	screen(b, 0, 31, -1.8, 90, 50, accent(b, 1, rgb(140, 190, 255)))
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 44, 18, 6, 12, 30, 12, INK)
		b.CylZ(side * 44, 38, 12.2, 8, 1, GREY_DARK, M.Metal)
	end
	b.Top(1, 0, 18, 8, 70, 14)
	b.Footprint(100, 30, 84)
end
R.DesktopPC = function(b, _ctx)
	local color = accent(b, 1, rgb(230, 230, 245))
	b.Box(-8, 0, 0, 26, 6, 18, color)
	b.Box(-8, 6, -4, 5, 16, 5, color)
	b.Box(-8, 20, -4, 70, 46, 4, color)
	screen(b, -8, 23, -1.8, 64, 40, rgb(150, 210, 255))
	b.Box(-8, 0, 20, 56, 3, 16, lighten(color, 0.2))
	b.Box(36, 0, 0, 18, 56, 40, darken(color, 0.08))
	local led = b.Box(36, 48, 20.2, 8, 3, 0.5, accent(b, 2, MINT))
	b.Neon(led)
	b.Footprint(90, 40, 66)
end
R.Laptop = function(b, _ctx)
	local color = accent(b, 1, rgb(230, 225, 245))
	b.Box(0, 0, 8, 80, 4, 50, color, M.SmoothPlastic)
	b.Box(0, 4, 12, 64, 0.6, 26, darken(color, 0.25))
	local lid = b.BoxR(CFrame.new(0, 24, -17) * CFrame.Angles(-0.25, 0, 0), 80, 46, 3, color, M.SmoothPlastic)
	lid.Name = "Couvercle"
	local panel = b.BoxR(CFrame.new(0, 24, -15.2) * CFrame.Angles(-0.25, 0, 0), 72, 38, 0.6, rgb(150, 200, 255), M.Neon)
	table.insert(b.Glows, panel)
	b.Footprint(80, 56, 48)
end
R.ArcadeMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(160, 110, 230))
	b.Box(0, 0, 0, 64, 100, 50, body, M.SmoothPlastic)
	b.Box(0, 44, 26, 64, 8, 14, darken(body, 0.15))
	for index = 1, 3 do
		knob(b, -18 + index * 9, 52, 28, 5, ({ PINK, BUTTER, MINT })[index])
	end
	b.Box(-20, 52, 28, 3, 7, 3, INK)
	screen(b, 0, 58, 25.4, 50, 30, accent(b, 2, rgb(120, 230, 255)))
	local marquee = b.Box(0, 90, 25.4, 58, 8, 1, BUTTER)
	b.Neon(marquee)
	b.Footprint(64, 64, 100)
end
R.SlotMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 120, 140))
	b.Box(0, 0, 0, 64, 90, 44, body, M.SmoothPlastic)
	b.Box(0, 44, 22, 52, 28, 1, WHITE)
	for index = 0, 2 do
		b.Box(-16 + index * 16, 48, 22.6, 12, 20, 0.5, ({ PINK, BUTTER, MINT })[index + 1])
	end
	b.CylX(36, 64, 0, 4, 10, GREY, M.Metal)
	b.Box(40, 64, 0, 3, 24, 3, GREY, M.Metal)
	b.Ball(40, 90, 0, 10, rgb(255, 80, 100))
	local top = b.Box(0, 90, 0, 60, 8, 40, GOLD, M.Metal)
	top.Name = "Haut"
	b.Footprint(70, 44, 100)
end
R.Speaker = function(b, _ctx)
	local body = accent(b, 1, INK)
	b.Box(0, 0, 0, 56, 96, 46, body, M.SmoothPlastic)
	b.CylZ(0, 30, 23.4, 36, 1.2, darken(body, 0.3))
	b.CylZ(0, 30, 24, 14, 1.4, GREY, M.Metal)
	b.CylZ(0, 72, 23.4, 20, 1.2, darken(body, 0.3))
	b.Top(1, 0, 96, 0, 50, 40)
	b.Footprint(56, 46, 96)
end
R.GrandPiano = function(b, _ctx)
	local body = accent(b, 1, rgb(60, 50, 80))
	for _, x in ipairs({ -36, 36 }) do
		b.Box(x, 0, 10, 6, 40, 6, body)
	end
	b.Box(0, 0, -22, 6, 40, 6, body)
	b.Box(0, 40, -4, 90, 18, 62, body, M.SmoothPlastic)
	b.Box(0, 52, 30, 80, 3, 10, WHITE)
	for index = 0, 13 do
		b.Box(-36 + index * 5.6, 55, 27, 3, 2, 5, INK)
	end
	b.BoxR(CFrame.new(-4, 74, -8) * CFrame.Angles(-0.55, 0, 0), 86, 2, 60, body)
	b.Box(0, 58, 24, 70, 14, 2, darken(body, 0.2))
	b.Footprint(92, 72, 90)
end
R.Telescope = function(b, _ctx)
	local metal = b.Map(GREY_DARK)
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 12, 30, math.sin(angle) * 12) * CFrame.Angles(math.sin(angle) * 0.35, 0, -math.cos(angle) * 0.35), 3, 64, 3, woodOf(b, WOOD), M.Wood)
	end
	b.Ball(0, 62, 0, 8, metal, M.Metal)
	local tube = b.BoxR(CFrame.new(6, 74, 0) * CFrame.Angles(0, 0, 0.55), 64, 12, 12, accent(b, 1, rgb(90, 110, 200)), M.SmoothPlastic)
	tube.Name = "Tube"
	b.BoxR(CFrame.new(-16, 60, 0) * CFrame.Angles(0, 0, 0.55), 10, 8, 8, GOLD, M.Metal)
	b.Footprint(60, 40, 96)
end
R.RecordPlayer = function(b, ctx)
	local wood = woodOf(b, WOOD)
	b.Box(0, 0, 0, 90, 26, 60, wood, M.Wood)
	b.Cyl(-8, 26, 0, 52, 2, INK)
	b.Cyl(-8, 28, 0, 14, 1, accent(b, 1, PINK))
	b.BoxR(CFrame.new(26, 28, 4) * CFrame.Angles(0, 0.5, 0), 3, 3, 40, GREY, M.Metal)
	local horn = b.Cyl(30, 26, -20, 10, 30, GOLD, M.Metal)
	horn.Name = "Pavillon"
	b.Ball(30, 60, -20, 30, GOLD, M.Metal)
	b.Top(1, 0, ctx.TopY(1, 26), 0, 40, 40)
	b.Footprint(90, 60, 70)
end

-- CHEMINÉE ------------------------------------------------------------

R.Fireplace = function(b, ctx)
	local top = ctx.TopY(1, 86)
	local stone = House3DKit.Pick(b.Pal, function(_h, s, v)
		return v > 0.5 and s < 0.45
	end, b.Map(rgb(236, 220, 230)))
	local w, depth = 100, 34
	b.Box(0, 0, 0, w, top - 6, depth, stone, M.Brick)
	b.Box(0, 0, depth / 2 - 2, w * 0.56, top * 0.56, 6, rgb(60, 40, 50), M.SmoothPlastic)
	b.Box(0, 0, depth / 2 + 2, w + 6, 4, 10, darken(stone, 0.1), M.Slate)
	-- bûches et flammes
	for index = -1, 1 do
		b.CylX(index * 8, 5, depth / 2, 6, 26, WOOD_DARK, M.Wood)
	end
	local flames = { FIRE, rgb(255, 200, 80), rgb(255, 110, 70) }
	for index = 1, 3 do
		local flame = b.Ball(-12 + index * 6, 14 + (index % 2) * 4, depth / 2, 12 - (index % 2) * 3, flames[index])
		b.Neon(flame)
		if index == 2 then
			b.Light(flame, rgb(255, 160, 90), 18, 1.4)
		end
	end
	-- manteau
	local wood = woodOf(b, WOOD)
	b.Box(0, top - 6, 2, w + 8, 6, depth + 6, wood, M.Wood)
	b.Top(1, 0, top, 2, w, depth)
	b.Footprint(w + 8, depth + 6, top)
end

-- PLANTES ----------------------------------------------------------------

local function plantColors(b: Builder): (Color3, Color3, Color3)
	local green = greenOf(b, LEAF)
	local potColor = House3DKit.Pick(b.Pal, function(h, s, v)
		return not (h > 0.2 and h < 0.45) and s > 0.12 and v > 0.4
	end, b.Map(rgb(255, 170, 150)))
	local flower = House3DKit.Pick(b.Pal, function(h, s, v)
		return (h < 0.18 or h > 0.5) and s > 0.3 and v > 0.5
	end, b.Map(PINK))
	return green, potColor, flower
end
local function smallPlant(flowers: boolean)
	return function(b: Builder, _ctx: Ctx)
		local green, potColor, flower = plantColors(b)
		pot(b, 56, 40, potColor)
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			b.BoxR(CFrame.new(math.cos(angle) * 6, 52, math.sin(angle) * 6) * CFrame.Angles(math.sin(angle) * 0.4, 0, -math.cos(angle) * 0.4), 3, 30, 3, darken(green, 0.2))
		end
		bush(b, 0, 64, 0, 40, green, 5)
		if flowers then
			for index = 0, 4 do
				local angle = index / 5 * math.pi * 2 + 0.3
				local x, z = math.cos(angle) * 16, math.sin(angle) * 14
				b.Ball(x, 76 + (index % 2) * 8, z, 16, flower)
				b.Ball(x, 77 + (index % 2) * 8, z + 6, 6, BUTTER)
			end
		end
		b.Footprint(56, 56, 90)
	end
end
local function tree(canopyColor: Color3?, round: boolean)
	return function(b: Builder, _ctx: Ctx)
		local green, potColor, flower = plantColors(b)
		local canopy = canopyColor and flower or green
		pot(b, 34, 26, potColor)
		b.Cyl(0, 22, 0, 7, 44, woodOf(b, WOOD_DARK), M.Wood)
		if round then
			bush(b, 0, 72, 0, 44, canopy, 6)
			bush(b, -14, 62, 6, 26, canopy, 3)
		else
			for index = 0, 3 do
				b.Cyl(0, 36 + index * 15, 0, 58 - index * 13, 16, index % 2 == 0 and canopy or darken(canopy, 0.1), M.SmoothPlastic)
			end
			b.Ball(0, 98, 0, 12, BUTTER)
		end
		b.Footprint(60, 60, 100)
	end
end
R.PottedPlant = smallPlant(false)
R.Monstera = function(b, _ctx)
	local green, potColor = plantColors(b)
	pot(b, 40, 34, potColor)
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2
		local leaf = b.BoxR(CFrame.new(math.cos(angle) * 18, 58 + (index % 3) * 10, math.sin(angle) * 14) * CFrame.Angles(math.sin(angle) * 0.7, angle, -math.cos(angle) * 0.7),
			26, 2, 18, index % 2 == 0 and green or darken(green, 0.15))
		leaf.Name = "Feuille"
		b.BoxR(CFrame.new(math.cos(angle) * 9, 46 + (index % 3) * 5, math.sin(angle) * 7) * CFrame.Angles(math.sin(angle) * 0.5, 0, -math.cos(angle) * 0.5), 2, 26, 2, darken(green, 0.3))
	end
	b.Footprint(70, 60, 90)
end
for _, id in ipairs({ "DaisyPot", "RedRose", "TulipPot", "Hibiscus", "FlowerVase", "Bouquet", "LuckyClover" }) do
	R[id] = smallPlant(true)
end
R.Sprout = smallPlant(false)
R.TinyCactus = function(b, _ctx)
	local green, potColor, flower = plantColors(b)
	pot(b, 56, 40, potColor)
	b.Cyl(0, 36, 0, 26, 40, green, M.SmoothPlastic)
	b.Ball(0, 76, 0, 26, green)
	b.Cyl(-18, 50, 0, 10, 16, green)
	b.Ball(-18, 66, 0, 10, green)
	b.Ball(0, 90, 0, 12, flower)
	b.Footprint(56, 56, 96)
end
R.IndoorTree = tree(nil, true)
R.Bonsai = tree(nil, true)
R.CherryBlossom = tree(PINK, true)
R.MiniPine = tree(nil, false)
R.HolidayTree = tree(nil, false)
R.PalmTree = function(b, _ctx)
	local green, potColor = plantColors(b)
	pot(b, 34, 22, potColor)
	for index = 0, 5 do
		b.Cyl(index * 1.5, 20 + index * 11, 0, 9 - index * 0.4, 12, index % 2 == 0 and WOOD or WOOD_DARK, M.Wood)
	end
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		b.BoxR(CFrame.new(8 + math.cos(angle) * 18, 88, math.sin(angle) * 18) * CFrame.Angles(math.sin(angle) * 0.5, -angle, -math.cos(angle) * 0.5), 38, 2, 12, green)
	end
	b.Ball(8, 86, 0, 10, rgb(140, 100, 70))
	b.Footprint(70, 70, 100)
end
R.Bamboo = function(b, _ctx)
	local green, potColor = plantColors(b)
	b.Box(0, 0, 0, 60, 22, 36, potColor, M.SmoothPlastic)
	for index = 0, 4 do
		local x = -20 + index * 10
		local h = 70 + (index % 3) * 10
		b.Cyl(x, 22, (index % 2) * 8 - 4, 5, h, green, M.SmoothPlastic)
		for joint = 1, 3 do
			b.Cyl(x, 22 + joint * h / 4, (index % 2) * 8 - 4, 6, 1.2, darken(green, 0.25))
		end
		b.BoxR(CFrame.new(x + 6, 22 + h - 6, (index % 2) * 8 - 4) * CFrame.Angles(0, 0, -0.6), 14, 1, 5, lighten(green, 0.1))
	end
	b.Footprint(60, 36, 100)
end
R.Sunflower = function(b, _ctx)
	local green, potColor = plantColors(b)
	pot(b, 46, 30, potColor)
	b.Cyl(0, 28, 0, 4, 50, green)
	b.BoxR(CFrame.new(8, 48, 0) * CFrame.Angles(0, 0, -0.5), 18, 2, 10, green)
	b.CylZ(0, 82, 2, 40, 4, rgb(255, 210, 60))
	b.CylZ(0, 82, 4, 18, 3, rgb(140, 90, 60))
	b.Footprint(46, 46, 100)
end
R.GiantMushroom = R.MushroomStool
R.Terrarium = function(b, _ctx)
	local green = greenOf(b, LEAF)
	b.Cyl(0, 0, 0, 60, 8, woodOf(b, WOOD), M.Wood)
	bush(b, 0, 20, 0, 30, green, 3)
	local dome = b.Ball(0, 36, 0, 64, GLASS, M.Glass)
	dome.Transparency = 0.55
	dome.CastShadow = false
	b.Footprint(64, 64, 70)
end

-- TAPIS ----------------------------------------------------------------------

local function rug(b: Builder, _ctx: Ctx)
	local main = accent(b, 1, PINK)
	local second = accent(b, 2, lighten(main, 0.35))
	b.Box(0, 0, 0, 100, 0.8, 68, main, M.Fabric)
	b.Box(0, 0.8, 0, 84, 0.3, 54, second, M.Fabric)
	b.Box(0, 1.1, 0, 60, 0.3, 36, lighten(main, 0.2), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		for index = 0, 9 do
			b.Box(side * 51, 0, -30 + index * 6.6, 3, 0.5, 1.4, lightOf(b, CREAM), M.Fabric)
		end
	end
	for _, part in ipairs(b.Parts) do
		part.CastShadow = false
	end
	b.Footprint(100, 68, 1)
end

-- PORTES (contre le mur du fond) ----------------------------------------------

local function door(b: Builder, ctx: Ctx)
	local panel = accent(b, 1, rgb(255, 180, 200))
	local frame = ctx.Trim
	b.Box(-36, 0, 0, 6, 96, 6, frame, M.Wood)
	b.Box(36, 0, 0, 6, 96, 6, frame, M.Wood)
	b.Box(0, 96, 0, 78, 6, 6, frame, M.Wood)
	b.Box(0, 0, -1, 66, 96, 3, panel, M.Wood)
	for _, y in ipairs({ 12, 52 }) do
		b.Box(0, y, 0.8, 50, 32, 1, lighten(panel, 0.18), M.Wood)
	end
	knob(b, 24, 48, 2.5, 6)
	b.Box(0, 0, 4, 60, 1, 8, darken(panel, 0.2))
	b.Footprint(84, 8, 102)
end
R.ToriiGate = function(b, _ctx)
	local red = accent(b, 1, rgb(230, 70, 70))
	for _, x in ipairs({ -34, 34 }) do
		b.Cyl(x, 0, 0, 9, 90, red, M.Wood)
		b.Cyl(x, 0, 0, 12, 6, INK)
	end
	b.Box(0, 70, 0, 84, 6, 6, red, M.Wood)
	b.Box(0, 88, 0, 104, 6, 10, red, M.Wood)
	b.Box(0, 94, 0, 108, 4, 12, INK, M.Wood)
	b.Box(0, 76, 0, 12, 12, 3, INK)
	b.Footprint(108, 12, 98)
end

-- ANIMAUX ET PELUCHES ------------------------------------------------------

-- Petite bête kawaii : corps, tête, oreilles, yeux, joues, queue ; `kind` règle les détails
local function critter(kind: string)
	return function(b: Builder, _ctx: Ctx)
		local body = b.Pal[1] or b.Map(rgb(255, 200, 160))
		local h, s, v = body:ToHSV()
		if s < 0.08 and v < 0.2 then
			-- (le contour prune a gagné : on prend la couleur suivante)
			body = b.Pal[2] or body
		end
		local _ = h
		local belly = lightOf(b, lighten(body, 0.5))
		local head = 46
		local bodyD = 50
		local headY = 60
		if kind == "Bird" then
			b.Ball(0, 30, 0, 54, body)
			b.Ball(0, 30, 10, 36, belly)
			b.Ball(0, 66, 2, 40, body)
			b.Wedge(0, 60, 22, 10, 8, 8, rgb(255, 170, 60), "Front")
			for _, side in ipairs({ -1, 1 }) do
				b.BoxR(CFrame.new(side * 26, 34, 0) * CFrame.Angles(0, 0, side * 0.5), 6, 24, 20, darken(body, 0.1))
				b.Ball(side * 9, 70, 20, 6, INK)
			end
			for _, x in ipairs({ -8, 8 }) do
				b.Cyl(x, 0, 0, 3, 6, rgb(255, 170, 60))
			end
			b.Footprint(56, 56, 88)
			return
		elseif kind == "Fish" then
			local bowl = b.Ball(0, 40, 0, 80, GLASS, M.Glass)
			bowl.Transparency = 0.6
			bowl.CastShadow = false
			local water = b.Cyl(0, 6, 0, 66, 48, rgb(150, 210, 255), M.Glass)
			water.Transparency = 0.45
			water.CastShadow = false
			local fish = accent(b, 1, rgb(255, 150, 60))
			b.Ball(0, 36, 0, 24, fish)
			b.Wedge(-16, 30, 0, 12, 14, 4, fish, "Left")
			b.Ball(7, 40, 10, 4, INK)
			b.Cyl(0, 0, 0, 50, 6, rgb(200, 170, 250))
			b.Footprint(80, 80, 82)
			return
		elseif kind == "Turtle" then
			local shell = accent(b, 1, LEAF_DARK)
			b.Ball(0, 16, 0, 60, shell)
			b.Box(0, 0, 0, 60, 16, 56, body)
			b.Ball(34, 18, 0, 26, lightOf(b, rgb(170, 220, 150)))
			b.Ball(40, 22, 8, 5, INK)
			for _, x in ipairs({ -20, 20 }) do
				for _, z in ipairs({ -22, 22 }) do
					b.Ball(x, 4, z, 14, belly)
				end
			end
			b.Footprint(76, 60, 46)
			return
		end
		-- mammifères / peluches
		if kind == "Bear" or kind == "Big" then
			bodyD, head, headY = 58, 54, 66
		elseif kind == "Bunny" then
			headY = 56
		end
		b.Ball(0, 24, 0, bodyD, body)
		b.Ball(0, 22, 12, bodyD * 0.6, belly)
		b.Ball(0, headY, 4, head, body)
		-- pattes
		for _, x in ipairs({ -14, 14 }) do
			b.Ball(x, 6, 16, 16, body)
		end
		-- oreilles
		for _, side in ipairs({ -1, 1 }) do
			if kind == "Cat" or kind == "Fox" then
				b.Wedge(side * 13, headY + head * 0.34, 4, 14, 16, 8, body, "Front")
				b.Wedge(side * 13, headY + head * 0.34, 7.5, 7, 9, 1, PINK_SOFT, "Front")
			elseif kind == "Bunny" then
				b.BoxR(CFrame.new(side * 9, headY + head * 0.6, 2) * CFrame.Angles(0, 0, side * -0.15), 10, 34, 7, body)
				b.BoxR(CFrame.new(side * 9, headY + head * 0.6, 5.8) * CFrame.Angles(0, 0, side * -0.15), 5, 26, 1, PINK_SOFT)
			elseif kind == "Dog" then
				b.BoxR(CFrame.new(side * 24, headY - 2, 4) * CFrame.Angles(0, 0, side * 0.25), 10, 26, 12, darken(body, 0.18))
			elseif kind == "Panda" then
				b.Ball(side * 18, headY + head * 0.38, 2, 16, INK)
			else
				b.Ball(side * 18, headY + head * 0.38, 2, 16, body)
				b.Ball(side * 18, headY + head * 0.38, 6, 8, PINK_SOFT)
			end
			-- yeux et joues
			if kind == "Panda" then
				b.Ball(side * 10, headY + 2, 4 + head * 0.42, 12, INK)
				b.Ball(side * 10, headY + 3, 6 + head * 0.44, 4, WHITE)
			else
				b.Ball(side * 10, headY + 2, 4 + head * 0.45, 7, INK)
				b.Ball(side * 11, headY + 3.5, 5 + head * 0.47, 2.4, WHITE)
			end
			b.Ball(side * 16, headY - 6, 3 + head * 0.4, 8, rgb(255, 160, 180))
		end
		b.Ball(0, headY - 4, 5 + head * 0.47, 5, INK)
		if kind == "Fox" then
			b.Ball(-30, 20, -10, 22, body)
			b.Ball(-40, 26, -12, 12, WHITE)
		elseif kind == "Cat" then
			b.BoxR(CFrame.new(-26, 30, -14) * CFrame.Angles(0, 0, 0.8), 6, 40, 6, body)
		elseif kind == "Unicorn" then
			b.Wedge(0, headY + head * 0.42, 6, 6, 18, 6, GOLD, "Front")
		elseif kind == "Pig" then
			b.CylZ(0, headY - 6, 4 + head * 0.48, 14, 4, lighten(body, 0.2))
		end
		b.Footprint(bodyD + 10, bodyD, headY + head * 0.5)
	end
end
local CRITTERS: { [string]: string } = {
	Kitten = "Cat", SleepyCat = "Cat", KittyPlush = "Cat",
	Puppy = "Dog", PuppyPlush = "Dog",
	Bunny = "Bunny", BunnyPlush = "Bunny",
	TeddyBear = "Bear", BigBear = "Big", HamsterPlush = "Bear", Hamster = "Bear", Hedgehog = "Bear",
	PandaPlush = "Panda", Fox = "Fox", UnicornPlush = "Unicorn", PiggyBank = "Pig",
	Chick = "Bird", Parrot = "Bird", PenguinPlush = "Bird", RubberDucky = "Bird",
	Goldfish = "Fish", Turtle = "Turtle",
	Duckling = "Bird", Penguin = "Bird", Owl = "Bird", Axolotl = "Bear", WhalePlush = "Bear", OctopusPlush = "Bear",
	FroggyPlush = "Bear", DinoPlush = "Bear",
}
for id, kind in pairs(CRITTERS) do
	R[id] = critter(kind)
end

-- AFFAIRES DES ANIMAUX ----------------------------------------------------

R.DogHouse = function(b, _ctx)
	local wall = accent(b, 1, rgb(255, 190, 150))
	local roof = accent(b, 2, rgb(230, 90, 110))
	b.Box(0, 0, 0, 80, 56, 64, wall, M.WoodPlanks)
	b.Box(0, 0, 32, 30, 36, 1.2, rgb(60, 40, 50))
	b.Wedge(-21, 56, 0, 42, 26, 70, roof, "Left", M.RoofShingles)
	b.Wedge(21, 56, 0, 42, 26, 70, roof, "Right", M.RoofShingles)
	b.Box(0, 40, 32.6, 26, 8, 1, lightOf(b, CREAM))
	b.Footprint(84, 70, 82)
end
R.ScratchingPost = function(b, _ctx)
	local base = accent(b, 1, rgb(200, 170, 240))
	b.Box(0, 0, 0, 70, 8, 60, base, M.Fabric)
	b.Cyl(0, 8, 0, 20, 70, rgb(222, 190, 140), M.Fabric)
	b.Box(0, 78, 0, 50, 8, 44, base, M.Fabric)
	b.Cyl(20, 60, 10, 2, 16, INK)
	b.Ball(20, 58, 10, 8, accent(b, 2, PINK))
	b.Top(1, 0, 86, 0, 44, 40)
	b.Footprint(70, 60, 86)
end
R.CatTree = function(b, _ctx)
	local base = accent(b, 1, rgb(200, 170, 240))
	b.Box(0, 0, 0, 90, 8, 60, base, M.Fabric)
	b.Cyl(-20, 8, 0, 14, 80, rgb(222, 190, 140), M.Fabric)
	b.Cyl(24, 8, 0, 14, 40, rgb(222, 190, 140), M.Fabric)
	b.Box(24, 48, 0, 40, 6, 36, base, M.Fabric)
	b.Box(-20, 86, 0, 48, 6, 40, base, M.Fabric)
	b.Box(-30, 8, 0, 30, 26, 36, lighten(base, 0.1), M.Fabric)
	b.Top(1, -20, 92, 0, 40, 34)
	b.Footprint(90, 60, 92)
end
R.PetBowl = function(b, _ctx)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 80, 26, color)
	b.Cyl(0, 24, 0, 64, 3, rgb(190, 130, 90), M.Pebble)
	b.Footprint(80, 80, 28)
end
R.PetToys = function(b, _ctx)
	b.Ball(-16, 14, 0, 28, accent(b, 1, PINK))
	b.Ball(18, 10, 6, 20, accent(b, 2, BUTTER))
	b.CylX(4, 5, -14, 10, 30, accent(b, 3, SKY))
	b.Footprint(70, 50, 28)
end
R.Aquarium = function(b, ctx)
	local top = ctx.TopY(1, 84)
	local wood = woodOf(b, WOOD)
	b.Box(0, 0, 0, 94, top * 0.35, 44, wood, M.Wood)
	local tankY = top * 0.35
	local tankH = top - tankY - 2
	local glass = b.Box(0, tankY, 0, 90, tankH, 40, GLASS, M.Glass)
	glass.Transparency = 0.55
	glass.CastShadow = false
	local water = b.Box(0, tankY + 2, 0, 86, tankH - 8, 36, rgb(130, 200, 250), M.Glass)
	water.Transparency = 0.4
	water.CastShadow = false
	b.Box(0, tankY, 0, 86, 4, 36, rgb(240, 220, 180), M.Sand)
	for index = 1, 3 do
		local fish = b.Ball(-24 + index * 14, tankY + 12 + index * 5, (index % 2) * 10 - 5, 10, ({ rgb(255, 150, 60), PINK, BUTTER })[index])
		fish.CastShadow = false
	end
	b.Box(-30, tankY + 4, -10, 4, 22, 4, LEAF_DARK)
	b.Box(0, top - 2, 0, 94, 2, 44, darken(wood, 0.1), M.Wood)
	b.Light(water, rgb(160, 220, 255), 10, 0.6)
	b.Top(1, 0, top, 0, 80, 36)
	b.Footprint(94, 44, top)
end
R.MiniAquarium = function(b, _ctx)
	critter("Fish")(b, _ctx)
end

-- DÉCO / TABLE / JOUETS (petits objets) -------------------------------------

local function cup(straw: boolean)
	return function(b: Builder, _ctx: Ctx)
		local color = accent(b, 1, PINK)
		b.Cyl(0, 0, 0, 50, 60, color)
		b.Cyl(0, 58, 0, 44, 3, lightOf(b, rgb(255, 240, 230)))
		if straw then
			b.BoxR(CFrame.new(6, 72, 0) * CFrame.Angles(0, 0, -0.25), 5, 34, 5, accent(b, 2, SKY))
			for index = 1, 3 do
				b.Ball(-10 + index * 6, 8, (index % 2) * 6, 9, INK)
			end
		else
			b.CylZ(30, 34, 0, 26, 5, color)
			b.CylZ(30, 34, 0, 14, 6, lighten(color, 0.5))
		end
		b.Footprint(62, 50, 64)
	end
end
R.CocoaMug = cup(false)
R.StrawberryMilk = cup(true)
R.BubbleTea = cup(true)
R.Lemonade = cup(true)
local function bowl(b: Builder, _ctx: Ctx)
	local color = accent(b, 2, lightOf(b, WHITE))
	b.Cyl(0, 0, 0, 44, 8, darken(color, 0.1))
	b.Cyl(0, 6, 0, 86, 30, color)
	local fill = accent(b, 1, rgb(255, 200, 140))
	b.Cyl(0, 34, 0, 78, 4, fill)
	b.Ball(-14, 40, 4, 18, accent(b, 3, rgb(255, 150, 120)))
	b.Ball(12, 40, -6, 16, accent(b, 4, LEAF))
	b.Footprint(86, 86, 48)
end
R.RamenBowl = bowl
R.SaladBowl = bowl
R.FruitBowl = bowl
local function plate(b: Builder, _ctx: Ctx)
	b.Cyl(0, 0, 0, 96, 6, lightOf(b, WHITE))
	for index = 0, 3 do
		local angle = index / 4 * math.pi * 2
		b.Box(math.cos(angle) * 20, 6, math.sin(angle) * 18, 24, 14, 20, accent(b, index % 3 + 1, rgb(255, 210, 160)))
	end
	b.Footprint(96, 96, 20)
end
R.PizzaPlate = plate
R.OnigiriPlate = plate
R.SushiPlatter = plate
local function cake(tiers: number)
	return function(b: Builder, _ctx: Ctx)
		local cream = lightOf(b, rgb(255, 248, 240))
		local main = accent(b, 1, PINK)
		b.Cyl(0, 0, 0, 90, 4, WHITE)
		local y = 4
		for index = 1, tiers do
			local d = 80 - (index - 1) * 22
			local h = 44 / tiers + 6
			b.Cyl(0, y, 0, d, h, index % 2 == 1 and main or cream)
			b.Cyl(0, y + h - 2, 0, d + 2, 4, cream)
			y += h
		end
		b.Ball(0, y + 5, 0, 14, rgb(240, 60, 80))
		b.Footprint(90, 90, y + 12)
	end
end
R.StrawberryCake = cake(2)
R.BirthdayCake = cake(3)
R.PancakeTower = cake(3)
R.CupcakeStand = cake(3)
R.Pudding = cake(1)
R.MacaronTower = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, MINT), accent(b, 3, LILAC), accent(b, 4, BUTTER) }
	b.Cyl(0, 0, 0, 60, 4, GOLD, M.Metal)
	for index = 0, 5 do
		local d = 56 - index * 8
		b.Cyl(0, 4 + index * 12, 0, d, 10, colors[index % 4 + 1])
	end
	b.Footprint(60, 60, 80)
end
local function jar(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, rgb(255, 200, 120))
	local glass = b.Cyl(0, 0, 0, 70, 66, GLASS, M.Glass)
	glass.Transparency = 0.45
	b.Cyl(0, 2, 0, 62, 44, color)
	b.Cyl(0, 66, 0, 74, 10, accent(b, 2, PINK))
	b.Ball(0, 78, 0, 14, accent(b, 2, PINK))
	b.Footprint(74, 74, 84)
end
R.CookieJar = jar
R.HoneyPot = jar
R.Teapot = function(b, _ctx)
	local color = accent(b, 1, rgb(160, 220, 255))
	b.Ball(0, 34, 0, 64, color)
	b.Cyl(0, 0, 0, 40, 8, darken(color, 0.1))
	b.Cyl(0, 62, 0, 30, 6, lightOf(b, WHITE))
	b.Ball(0, 70, 0, 10, accent(b, 2, PINK))
	b.BoxR(CFrame.new(34, 40, 0) * CFrame.Angles(0, 0, -0.8), 8, 28, 8, color)
	b.CylZ(-34, 36, 0, 24, 5, color)
	b.Footprint(90, 64, 76)
end
R.TeaSet = R.Teapot
R.Watermelon = function(b, _ctx)
	b.Ball(0, 36, 0, 74, rgb(90, 180, 90))
	for index = 0, 3 do
		b.BoxR(CFrame.new(0, 36, 0) * CFrame.Angles(0, index * math.pi / 4, 0), 75, 70, 3, rgb(60, 140, 70))
	end
	b.Footprint(74, 74, 74)
end
local function boxThing(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, PINK)
	b.Box(0, 0, 0, 84, 40, 60, color)
	b.Box(0, 40, 0, 88, 8, 64, lighten(color, 0.2))
	b.Box(0, 0, 0, 12, 49, 64.4, accent(b, 2, BUTTER))
	b.Box(0, 0, 0, 88.4, 49, 12, accent(b, 2, BUTTER))
	b.Ball(0, 52, 0, 14, accent(b, 2, BUTTER))
	b.Top(1, 0, 48, 0, 70, 50)
	b.Footprint(88, 64, 56)
end
R.BentoBox = boxThing
R.DonutBox = boxThing
R.JewelryBox = boxThing
R.MusicBox = boxThing
R.GiftPile = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT) }
	local specs = { { -20, 0, 0, 50, 40 }, { 26, 0, 6, 36, 30 }, { -14, 40, 0, 32, 26 } }
	for index, spec in ipairs(specs) do
		local x, y, z, s, h = spec[1], spec[2], spec[3], spec[4], spec[5]
		b.Box(x, y, z, s, h, s * 0.9, colors[index])
		b.Box(x, y, z, 6, h + 0.4, s * 0.9 + 0.4, BUTTER)
		b.Ball(x, y + h + 3, z, 10, BUTTER)
	end
	b.Footprint(90, 50, 76)
end
R.BookStack = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT), accent(b, 4, BUTTER) }
	for index = 0, 4 do
		b.BoxR(CFrame.new((index % 2) * 4 - 2, 5 + index * 11, 0) * CFrame.Angles(0, (index % 3 - 1) * 0.15, 0), 84, 10, 60, colors[index % 4 + 1])
		b.Box((index % 2) * 4 - 2, index * 11 + 1, 30.1, 80, 8, 0.4, WHITE)
	end
	b.Top(1, 0, 55, 0, 60, 50)
	b.Footprint(84, 60, 56)
end
R.BlanketStack = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT), accent(b, 4, LILAC) }
	for index = 0, 3 do
		b.Box(0, index * 14, 0, 90 - index * 4, 14, 60, colors[index + 1], M.Fabric)
		b.CylZ(-(90 - index * 4) / 2, index * 14 + 7, 0, 14, 60, colors[index + 1], M.Fabric)
	end
	b.Top(1, 0, 56, 0, 70, 50)
	b.Footprint(94, 60, 56)
end
local function pillow(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, PINK)
	b.BoxR(CFrame.new(0, 34, 0) * CFrame.Angles(-0.2, 0, 0), 80, 64, 24, color, M.Fabric)
	b.Ball(0, 36, 12, 18, lighten(color, 0.3), M.Fabric)
	b.Footprint(80, 40, 70)
end
R.HeartPillow = pillow
R.MoonPillow = pillow
local function orb(b: Builder, _ctx: Ctx)
	local base = accent(b, 2, woodOf(b, WOOD))
	b.Cyl(0, 0, 0, 60, 16, base)
	local ball = b.Ball(0, 46, 0, 64, accent(b, 1, rgb(190, 170, 255)), M.Glass)
	ball.Transparency = 0.25
	b.Ball(0, 40, 0, 26, WHITE)
	b.Footprint(64, 64, 80)
end
R.SnowGlobe = orb
R.CrystalBall = orb
R.DeskGlobe = function(b, _ctx)
	b.Cyl(0, 0, 0, 44, 6, woodOf(b, WOOD), M.Wood)
	b.Cyl(0, 6, 0, 5, 20, GOLD, M.Metal)
	b.Ball(0, 58, 0, 64, accent(b, 1, rgb(110, 180, 250)))
	b.Ball(-10, 70, 16, 22, accent(b, 2, LEAF))
	b.CylZ(0, 58, 0, 74, 3, GOLD, M.Metal)
	b.Footprint(74, 64, 92)
end
R.GoldenTrophy = function(b, _ctx)
	local gold = b.Map(GOLD)
	b.Box(0, 0, 0, 44, 14, 36, woodOf(b, WOOD_DARK), M.Wood)
	b.Cyl(0, 14, 0, 10, 24, gold, M.Metal)
	b.Cyl(0, 36, 0, 50, 36, gold, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		b.CylZ(side * 28, 58, 0, 18, 4, gold, M.Metal)
	end
	b.Footprint(66, 50, 74)
end
R.MantelClock = function(b, _ctx)
	local wood = woodOf(b, WOOD)
	b.Box(0, 0, 0, 80, 50, 34, wood, M.Wood)
	b.Ball(0, 50, 0, 40, wood, M.Wood)
	b.CylZ(0, 42, 17, 40, 2, WHITE)
	b.BoxR(CFrame.new(0, 48, 18.4) * CFrame.Angles(0, 0, 0.2), 2, 14, 0.6, INK)
	b.BoxR(CFrame.new(3, 42, 18.4) * CFrame.Angles(0, 0, 1.3), 2, 10, 0.6, INK)
	b.Footprint(80, 40, 70)
end
R.Vase = function(b, _ctx)
	local color = accent(b, 1, rgb(160, 200, 255))
	b.Cyl(0, 0, 0, 40, 10, color)
	b.Ball(0, 30, 0, 54, color)
	b.Cyl(0, 50, 0, 26, 24, color)
	b.Cyl(0, 72, 0, 32, 4, lighten(color, 0.3))
	for index = 0, 2 do
		b.Ball(-10 + index * 10, 82 + (index % 2) * 8, 0, 14, accent(b, 2, PINK))
	end
	b.Footprint(56, 56, 96)
end
R.Fountain = function(b, _ctx)
	local stone = lightOf(b, rgb(236, 236, 246))
	b.Cyl(0, 0, 0, 96, 22, stone, M.Marble)
	local water = b.Cyl(0, 18, 0, 86, 3, rgb(150, 210, 255), M.Glass)
	water.Transparency = 0.2
	b.Cyl(0, 22, 0, 14, 40, stone, M.Marble)
	b.Cyl(0, 58, 0, 50, 8, stone, M.Marble)
	b.Cyl(0, 66, 0, 10, 16, stone, M.Marble)
	local spray = b.Ball(0, 86, 0, 16, rgb(190, 230, 255), M.Glass)
	spray.Transparency = 0.3
	b.Footprint(96, 96, 94)
end
R.MoaiStatue = function(b, _ctx)
	local stone = b.Map(rgb(170, 160, 170))
	b.Box(0, 0, 0, 50, 60, 40, stone, M.Slate)
	b.Box(0, 50, 2, 40, 46, 36, stone, M.Slate)
	b.Box(0, 80, 20.5, 30, 6, 2, darken(stone, 0.3))
	b.Box(0, 56, 21, 10, 22, 4, darken(stone, 0.1), M.Slate)
	b.Footprint(50, 42, 96)
end
R.BeachBall = function(b, _ctx)
	b.Ball(0, 48, 0, 96, accent(b, 1, PINK))
	b.Cyl(0, 40, 0, 97, 16, accent(b, 2, SKY))
	b.Cyl(0, 58, 0, 91, 8, WHITE)
	b.Ball(0, 90, 0, 20, WHITE)
	b.Footprint(96, 96, 96)
end
R.GiantDice = function(b, _ctx)
	b.BoxR(CFrame.new(0, 42, 0) * CFrame.Angles(0, 0.35, 0), 84, 84, 84, lightOf(b, WHITE))
	for _, p in ipairs({ { -20, 62 }, { 20, 22 }, { 0, 42 } }) do
		b.BoxR(CFrame.new(0, 0, 0) * CFrame.Angles(0, 0.35, 0) * CFrame.new(p[1], p[2], 42.2), 14, 14, 1, accent(b, 1, PINK))
	end
	b.Footprint(100, 100, 84)
end
R.ToyDrum = function(b, _ctx)
	local color = accent(b, 1, rgb(255, 110, 120))
	b.Cyl(0, 0, 0, 90, 60, color)
	b.Cyl(0, 58, 0, 92, 4, WHITE)
	b.Cyl(0, 0, 0, 92, 4, WHITE)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 45, 30, math.sin(angle) * 45) * CFrame.Angles(0, -angle, 0.4), 2, 60, 2, GOLD)
	end
	b.Footprint(92, 92, 64)
end
R.BoardGame = function(b, _ctx)
	b.Box(0, 0, 0, 96, 8, 70, accent(b, 1, PINK))
	b.Box(0, 8, 0, 80, 0.5, 56, WHITE)
	for index = 0, 3 do
		b.Cyl(-24 + index * 16, 8.5, (index % 2) * 12, 8, 10, ({ PINK, SKY, MINT, BUTTER })[index + 1])
	end
	b.Footprint(96, 70, 18)
end
R.ToyRobot = function(b, _ctx)
	local metal = accent(b, 1, rgb(170, 200, 230))
	for _, x in ipairs({ -12, 12 }) do
		b.Box(x, 0, 0, 14, 26, 18, darken(metal, 0.15), M.Metal)
	end
	b.Box(0, 26, 0, 48, 34, 30, metal, M.Metal)
	b.Box(0, 62, 0, 38, 28, 28, lighten(metal, 0.1), M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		local eye = b.Ball(side * 9, 76, 14, 8, rgb(120, 230, 255))
		b.Neon(eye)
		b.Box(side * 30, 34, 0, 8, 24, 10, darken(metal, 0.1), M.Metal)
	end
	b.Cyl(0, 90, 0, 2, 8, GREY)
	b.Ball(0, 98, 0, 6, rgb(255, 80, 100))
	b.Footprint(64, 30, 100)
end
R.NestingDolls = function(b, _ctx)
	local colors = { accent(b, 1, rgb(255, 110, 120)), accent(b, 2, BUTTER), accent(b, 3, MINT) }
	for index = 0, 2 do
		local s = 1 - index * 0.25
		local x = -28 + index * 30
		b.Ball(x, 20 * s, 0, 40 * s, colors[index + 1])
		b.Ball(x, 48 * s, 0, 30 * s, colors[index + 1])
		b.Ball(x, 48 * s, 12 * s, 16 * s, rgb(255, 230, 210))
	end
	b.Footprint(90, 40, 64)
end
R.ToyRocket = function(b, _ctx)
	local color = lightOf(b, WHITE)
	b.Cyl(0, 10, 0, 34, 60, color)
	b.Ball(0, 70, 0, 34, accent(b, 1, rgb(255, 90, 110)))
	b.Cyl(0, 78, 0, 16, 12, accent(b, 1, rgb(255, 90, 110)))
	b.CylZ(0, 50, 16, 14, 2, accent(b, 2, SKY))
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 20, 16, math.sin(angle) * 20) * CFrame.Angles(0, -angle, 0), 16, 26, 3, accent(b, 1, rgb(255, 90, 110)))
	end
	local flame = b.Ball(0, 6, 0, 16, FIRE)
	b.Neon(flame)
	b.Footprint(50, 50, 96)
end

-- v9.1 : NOUVEAUX MEUBLES (Art/Cozy91, Art/Fun91) ------------------------

R.ToyChest = function(b, ctx)
	local top = ctx.TopY(1, 68)
	local x0, x1 = ctx.Span(1, -42, 42)
	local w, depth = x1 - x0, 52
	local body = accent(b, 1, rgb(255, 170, 190))
	b.Box(0, 0, 0, w, top - 10, depth, body, M.Wood)
	b.Box(0, top - 10, 0, w + 3, 10, depth + 3, lighten(body, 0.15), M.Wood)
	for _, x in ipairs({ -w / 3, w / 3 }) do
		b.Box(x, 0, 0, 5, top + 0.4, depth + 3.4, accent(b, 2, BUTTER), M.Wood)
	end
	b.Box(0, top - 18, depth / 2 + 1.8, 10, 10, 1, GOLD, M.Metal)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.Pouf = function(b, ctx)
	local seat = ctx.TopY(1, 48)
	local color = accent(b, 1, LILAC)
	b.Cyl(0, 0, 0, 64, seat - 6, color, M.Fabric)
	b.Cyl(0, seat - 8, 0, 60, 8, lighten(color, 0.12), M.Fabric)
	b.Ball(0, seat - 1, 0, 8, darken(color, 0.2), M.Fabric)
	b.Top(1, 0, seat, 0, 50, 50)
	b.Footprint(64, 64, seat)
end
R.LadderShelf = function(b, ctx)
	local wood = woodOf(b, WOOD)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 40, 46, -4) * CFrame.Angles(-0.18, 0, 0), 4, 94, 4, darken(wood, 0.1), M.Wood)
	end
	for index = 1, 3 do
		local y = ctx.TopY(index, 30 * index)
		local x0, x1 = ctx.Span(index, -40, 40)
		local z = 8 - index * 5
		b.Box((x0 + x1) / 2, y - 3, z, x1 - x0 + 4, 3, 24 - index * 3, wood, M.Wood)
		b.Top(index, (x0 + x1) / 2, y, z, x1 - x0, 18 - index * 3)
	end
	b.Footprint(86, 36, 96)
end
R.KotatsuTable = function(b, ctx)
	local top = ctx.TopY(1, 58)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 60
	local quilt = accent(b, 1, rgb(255, 170, 190))
	b.Box(0, 0, 0, w - 4, top - 6, depth - 4, quilt, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (w / 2 - 1), 0, 0, 4, top - 10, depth + 2, darken(quilt, 0.08), M.Fabric)
	end
	b.Box(0, top - 6, 0, w + 4, 6, depth + 4, woodOf(b, WOOD), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 6, depth + 6, top)
end
R.HeartArmchair = function(b, ctx)
	sofa(b, ctx, 36, 92, 1)
	local color = accent(b, 1, PINK)
	local seat = ctx.TopY(1, 36)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 16, seat + 40, -20, 36, color, M.Fabric)
	end
	b.BoxR(CFrame.new(0, seat + 28, -20) * CFrame.Angles(0, 0, math.pi / 4), 32, 32, 10, color, M.Fabric)
end
R.CatSofa = function(b, ctx)
	sofa(b, ctx, 36, 100, 3)
	local color = accent(b, 1, rgb(255, 190, 150))
	local seat = ctx.TopY(1, 36)
	for _, side in ipairs({ -1, 1 }) do
		b.Wedge(side * 30, seat + 30, -21, 16, 16, 8, color, "Front", M.Fabric)
		b.Ball(side * 8, seat + 20, -14, 6, INK)
	end
end
R.CrystalThrone = function(b, ctx)
	chair(b, ctx, 44, 56, 64, 56, accent(b, 1, LILAC))
	local crystal = accent(b, 2, rgb(170, 220, 255))
	local seat = ctx.TopY(1, 44)
	for index = -2, 2 do
		local spike = b.Wedge(index * 11, seat + 50 - math.abs(index) * 8, -25, 9, 22 - math.abs(index) * 4, 6, crystal, "Front", M.Glass)
		spike.Transparency = 0.2
	end
end
R.Hammock = function(b, ctx)
	local seat = ctx.TopY(1, 44)
	local wood = woodOf(b, WOOD)
	local fabric = accent(b, 1, rgb(255, 170, 120))
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 46, 0, 0, 5, 70, 5, wood, M.Wood)
		b.Box(side * 46, 0, 0, 12, 4, 30, darken(wood, 0.15), M.Wood)
	end
	for index = -3, 3 do
		local y = seat - 6 + math.abs(index) ^ 1.6 * 2.2
		b.Box(index * 12, y, 0, 13, 3, 32, index % 2 == 0 and fabric or lighten(fabric, 0.3), M.Fabric)
	end
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 44, seat + 12, 0) * CFrame.Angles(0, 0, side * 0.9), 1.5, 22, 1.5, INK)
	end
	b.Top(1, 0, seat, 0, 60, 26)
	b.Footprint(100, 34, 70)
end
R.KitchenSink = function(b, ctx)
	local top = ctx.TopY(1, 62)
	local body = accent(b, 1, MINT)
	local w, depth = 98, 48
	b.Box(0, 0, 0, w, top - 6, depth, body, M.SmoothPlastic)
	for index = 1, 3 do
		local x = -w / 2 + (index - 0.5) * w / 3
		b.Box(x, 6, depth / 2, w / 3 - 3, top - 18, 1.2, lighten(body, 0.2))
		knob(b, x, top - 16, depth / 2 + 1.4, 3.5)
	end
	b.Box(0, top - 6, 0, w + 2, 6, depth + 2, lightOf(b, WHITE), M.Marble)
	b.Box(0, top - 5, 0, 36, 5.2, 30, rgb(150, 170, 190), M.Metal)
	local water = b.Box(0, top - 3, 0, 32, 1, 26, rgb(170, 220, 255), M.Glass)
	water.Transparency = 0.3
	b.Cyl(0, top, -18, 4, 16, GREY, M.Metal)
	b.CylZ(0, top + 16, -13, 4, 10, GREY, M.Metal)
	local x0, x1 = ctx.Span(1, -46, -22)
	b.Top(1, (x0 + x1) / 2, top, 0, x1 - x0, depth - 6)
	local x2, x3 = ctx.Span(2, 22, 46)
	b.Top(2, (x2 + x3) / 2, top, 0, x3 - x2, depth - 6)
	b.Footprint(w + 2, depth + 2, top + 18)
end
R.Jukebox = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 120, 150))
	b.Box(0, 0, 0, 70, 60, 40, body, M.SmoothPlastic)
	b.CylZ(0, 60, 0, 70, 40, body, M.SmoothPlastic)
	local arch = b.CylZ(0, 60, 20.5, 56, 1, BUTTER)
	b.Neon(arch)
	b.Box(0, 20, 20.5, 50, 30, 1, rgb(60, 50, 90), M.Glass)
	for index = 0, 3 do
		b.Box(-15 + index * 10, 24, 21.2, 6, 20, 0.5, ({ PINK, SKY, MINT, BUTTER })[index + 1])
	end
	b.Light(arch, BUTTER, 10, 0.8)
	b.Footprint(70, 40, 95)
end
R.PinballMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(120, 110, 230))
	for _, x in ipairs({ -26, 26 }) do
		for _, z in ipairs({ -30, 30 }) do
			b.Box(x, 0, z, 4, 40, 4, INK, M.Metal)
		end
	end
	b.BoxR(CFrame.new(0, 46, 0) * CFrame.Angles(-0.12, 0, 0), 60, 10, 76, body)
	local field = b.BoxR(CFrame.new(0, 51.5, 0) * CFrame.Angles(-0.12, 0, 0), 52, 1, 68, rgb(40, 40, 90))
	field.Name = "Plateau"
	b.Box(0, 46, -38, 60, 40, 8, body)
	local panel = b.Box(0, 56, -33.8, 52, 26, 0.6, accent(b, 2, PINK))
	b.Neon(panel)
	for index = 0, 2 do
		local bumper = b.Ball(-14 + index * 14, 56 - index * 0.8, -10 + index * 8, 8, ({ PINK, BUTTER, MINT })[index + 1])
		b.Neon(bumper)
	end
	b.Footprint(64, 84, 86)
end
R.RetroComputer = R.DesktopPC
R.TulipLamp = function(b, _ctx)
	local color = accent(b, 1, PINK)
	b.Cyl(0, 0, 0, 34, 5, greenOf(b, LEAF_DARK))
	b.Cyl(0, 5, 0, 4, 50, greenOf(b, LEAF_DARK))
	b.BoxR(CFrame.new(8, 26, 0) * CFrame.Angles(0, 0, -0.6), 16, 2, 8, greenOf(b, LEAF))
	local bulb = b.Ball(0, 66, 0, 34, color)
	b.Neon(bulb)
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.Wedge(math.cos(angle) * 8, 74, math.sin(angle) * 8, 10, 16, 6, color, "Front")
	end
	b.Light(bulb, lighten(color, 0.4), 12, 0.9)
	b.Footprint(40, 40, 92)
end
R.ToyBlocks = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, BUTTER), accent(b, 4, MINT) }
	local specs = { { -22, 0, 0 }, { 0, 0, 4 }, { 22, 0, -2 }, { -11, 26, 2 }, { 11, 26, 0 }, { 0, 52, 1 } }
	for index, spec in ipairs(specs) do
		b.BoxR(CFrame.new(spec[1], spec[2] + 13, spec[3]) * CFrame.Angles(0, (index % 3 - 1) * 0.2, 0), 24, 24, 24, colors[index % 4 + 1])
	end
	b.Footprint(70, 30, 78)
end

----------------------------------------------------------------------
-- (v9.2) Objets "cool" : coin gamer, sport, véhicules, espace, musique
-- (couleurs passées par b.Map : la couleur choisie pour l'objet s'applique)
----------------------------------------------------------------------

local NAVY = rgb(52, 60, 100)
local CARBON = rgb(40, 42, 58)
local NEON_CYAN = rgb(60, 222, 255)
local NEON_PINK = rgb(255, 84, 196)
local RACE_RED = rgb(236, 66, 76)
local CHROME = rgb(214, 222, 236)

-- Roue (axe avant-arrière : on voit le pneu de profil depuis la caméra)
local function wheel3D(b: Builder, x: number, y: number, z: number, d: number, width: number, rim: Color3?)
	b.CylZ(x, y, z, d, width, INK, M.Rubber)
	b.CylZ(x, y, z, d * 0.6, width + 0.6, rim or GREY, M.Metal)
end

R.GamingDesk = function(b, ctx)
	local top = ctx.TopY(1, 65)
	local x0, x1 = ctx.Span(1, -47, 47)
	local w, depth = x1 - x0, 56
	local legs = b.Map(RACE_RED)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 8), 0, 0, 10, top - 6, 10, legs, M.Metal)
		b.Box(side * (w / 2 - 8), 0, 0, 14, 4, depth - 6, CARBON, M.Metal)
	end
	b.Box(0, top * 0.55, -depth / 2 + 8, w - 20, 8, 12, CARBON, M.Metal) -- range-câbles
	b.Box(0, top - 6, 0, w, 6, depth, CARBON, M.SmoothPlastic)
	local led = b.Box(0, top - 5, depth / 2 + 0.3, w - 6, 2, 0.6, NEON_CYAN)
	b.Neon(led)
	b.Light(led, NEON_CYAN, 10, 0.6)
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.BrickTable = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -47, 47)
	local w, depth = x1 - x0, 54
	local colors = { RACE_RED, BUTTER, rgb(80, 150, 255), rgb(255, 152, 56) }
	for sideIndex, side in ipairs({ -1, 1 }) do
		for level = 0, 2 do
			local color = colors[(level + sideIndex) % #colors + 1]
			local y = level * ((top - 8) / 3)
			b.Box(side * (w / 2 - 9), y, 0, 14, (top - 8) / 3, 40, color, M.SmoothPlastic)
			b.Cyl(side * (w / 2 - 9), y + (top - 8) / 3, -8, 5, 1.5, color, M.SmoothPlastic)
			b.Cyl(side * (w / 2 - 9), y + (top - 8) / 3, 8, 5, 1.5, color, M.SmoothPlastic)
		end
	end
	local plate = b.Map(rgb(96, 196, 110))
	b.Box(0, top - 8, 0, w, 8, depth, plate, M.SmoothPlastic)
	for index = 0, 9 do
		b.CylZ(-w / 2 + 6 + index * (w - 12) / 9, top - 4, depth / 2 + 0.5, 4, 1.2, lighten(plate, 0.2), M.SmoothPlastic)
	end
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.GamerChair = function(b, ctx)
	local seat = ctx.TopY(1, 39)
	local main = b.Map(RACE_RED)
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 12, 2, math.sin(angle) * 12) * CFrame.Angles(0, -angle, 0), 26, 3, 4, CARBON, M.Metal)
		b.Ball(math.cos(angle) * 24, 2, math.sin(angle) * 24, 4, INK, M.Rubber)
	end
	b.Cyl(0, 3, 0, 6, seat - 10, GREY, M.Metal)
	b.Box(0, seat - 8, 0, 54, 8, 50, CARBON, M.Leather)
	b.Box(0, seat - 7, 0, 22, 8.4, 46, main, M.Leather)
	b.Box(0, seat - 8, -22, 52, 64, 8, CARBON, M.Leather)
	b.Box(0, seat + 4, -17.6, 22, 50, 1, main, M.Leather)
	b.Box(0, seat + 4, -17.2, 4, 50, 1, WHITE, M.Leather)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 22, seat + 6, -20, 8, 44, 12, main, M.Leather) -- ailes du baquet
		b.Box(side * 27, seat, 2, 4, 14, 30, CARBON, M.Leather)
	end
	b.Box(0, seat + 46, -16, 22, 10, 6, CARBON, M.Fabric) -- coussin de tête
	b.Top(1, 0, seat, 4, 44, 36)
	b.Footprint(56, 56, seat + 64)
end
R.GamerBeanbag = function(b, _ctx)
	local color = b.Map(rgb(76, 72, 112))
	b.Ball(0, 22, 0, 90, color, M.Fabric)
	b.Ball(0, 42, -20, 64, lighten(color, 0.08), M.Fabric)
	b.Box(0, 0, 0, 84, 4, 80, darken(color, 0.1), M.Fabric)
	local seam = b.Box(0, 30, 44.5, 60, 2, 0.8, NEON_CYAN)
	b.Neon(seam)
	b.Top(1, 0, 58, 8, 50, 40)
	b.Footprint(90, 90, 70)
end
R.LockerCabinet = function(b, ctx)
	local top = ctx.TopY(1, 91)
	local blue = b.Map(rgb(80, 130, 220))
	local w, depth = 86, 40
	b.Box(0, 0, 0, w, 6, depth, darken(blue, 0.35), M.Metal)
	b.Box(0, 6, 0, w, top - 6, depth, blue, M.Metal)
	for index = 0, 1 do
		local x = -w / 4 + index * w / 2
		b.Box(x, 9, depth / 2, w / 2 - 4, top - 14, 1, lighten(blue, 0.08), M.Metal)
		for vent = 0, 3 do
			b.Box(x, top - 16 - vent * 5, depth / 2 + 0.6, w / 2 - 16, 2, 0.4, darken(blue, 0.3), M.Metal)
		end
		b.Box(x + (index == 0 and 14 or -14), top * 0.5, depth / 2 + 1, 3, 12, 2, GREY, M.Metal)
	end
	b.Top(1, 0, top, 0, w - 8, depth - 6)
	b.Footprint(w, depth, top)
end
R.BunkBed = function(b, ctx)
	local upper = ctx.TopY(1, 73)
	local lower = ctx.TopY(2, 29)
	local frame = b.Map(rgb(96, 120, 190))
	local width, depth = 96, 60
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * (width / 2 - 3), 0, sz * (depth / 2 - 3), 6, 96, 6, frame, M.Wood)
		end
	end
	for index, top in ipairs({ upper, lower }) do
		b.Box(0, top - 16, 0, width - 4, 6, depth - 4, darken(frame, 0.2), M.Wood)
		b.Box(0, top - 10, 0, width - 10, 10, depth - 10, WHITE, M.Fabric)
		local blanket = index == 1 and NAVY or RACE_RED
		b.Box(width * 0.12, top - 9, 0, width * 0.62, 10.5, depth - 8, blanket, M.Fabric)
		b.BoxR(CFrame.new(-width / 2 + 16, top + 2, 0) * CFrame.Angles(0, 0, -0.3), 18, 7, depth - 22, lighten(frame, 0.5), M.Fabric)
		b.Top(index, 0, top, 0, width - 24, depth - 12)
	end
	b.Box(-width / 4, upper + 2, depth / 2 - 3, width / 2, 6, 3, frame, M.Wood) -- garde-corps
	-- échelle
	for _, x in ipairs({ width / 2 - 20, width / 2 - 6 }) do
		b.Box(x, 0, depth / 2 + 3, 3, upper, 3, WOOD_LIGHT, M.Wood)
	end
	for index = 1, 4 do
		b.Box(width / 2 - 13, index * upper / 5, depth / 2 + 3, 16, 3, 3, WOOD_LIGHT, M.Wood)
	end
	b.Footprint(width, depth, 96)
end
R.RaceCarBed = function(b, ctx)
	local top = ctx.TopY(1, 59)
	local red = b.Map(RACE_RED)
	local width, depth = 100, 60
	b.Box(0, 8, 0, width - 10, top - 18, depth, red, M.SmoothPlastic)
	b.Wedge(width / 2 - 4, 8, 0, 14, top - 26, depth, red, "Right", M.SmoothPlastic) -- nez
	b.Box(-width / 2 + 6, 8, 0, 10, top + 6, depth, darken(red, 0.1), M.SmoothPlastic)
	b.Box(-width / 2 + 2, top + 12, 0, 16, 4, depth + 6, CARBON, M.SmoothPlastic) -- aileron
	b.Box(0, top - 10, 0, width * 0.6, 10, depth - 8, WHITE, M.Fabric) -- matelas
	b.Box(width * 0.08, top - 9, 0, width * 0.34, 10.5, depth - 6, CARBON, M.Fabric)
	b.Box(0, top * 0.45, depth / 2 + 0.3, width - 14, 3, 0.6, WHITE)
	for _, x in ipairs({ -30, 30 }) do
		for _, z in ipairs({ -depth / 2 - 2, depth / 2 + 2 }) do
			wheel3D(b, x, 12, z, 24, 8, CHROME)
		end
	end
	local lamp = b.Ball(width / 2 - 8, top - 26, depth / 2 - 8, 8, BUTTER)
	b.Neon(lamp)
	b.Top(1, -6, top, 0, 52, depth - 12)
	b.Footprint(width, depth + 12, top + 16)
end
R.NeonArcade = function(b, _ctx)
	local body = b.Map(rgb(30, 32, 46))
	b.Box(0, 0, 0, 64, 100, 50, body, M.SmoothPlastic)
	for index, x in ipairs({ -32.4, 32.4 }) do
		local strip = b.Box(x, 6, 0, 0.8, 90, 46, index == 1 and NEON_CYAN or NEON_PINK)
		b.Neon(strip)
	end
	b.Box(0, 44, 26, 64, 8, 14, NAVY)
	for index = 1, 4 do
		knob(b, -18 + index * 8, 52, 28, 5, ({ NEON_CYAN, NEON_PINK, rgb(140, 240, 110), BUTTER })[index])
	end
	b.Box(-22, 52, 28, 3, 8, 3, RACE_RED)
	screen(b, 0, 58, 25.4, 50, 30, rgb(20, 30, 70))
	b.Art(0, 60, 26, 30, 22, 2.6)
	local marquee = b.Box(0, 90, 25.4, 58, 8, 1, NEON_PINK)
	b.Neon(marquee)
	b.Light(marquee, NEON_PINK, 12, 0.8)
	b.Footprint(64, 64, 100)
end
R.GamerPC = function(b, _ctx)
	-- écran + clavier + tour vitrée à LED
	b.Box(-16, 0, 0, 20, 4, 14, CARBON)
	b.Box(-16, 4, -4, 5, 14, 5, GREY_DARK, M.Metal)
	b.Box(-16, 16, -4, 64, 40, 4, CARBON)
	screen(b, -16, 19, -1.8, 58, 34, rgb(120, 170, 255))
	b.Box(-16, 0, 18, 58, 3, 14, CARBON)
	local keys = b.Box(-16, 3, 18, 52, 0.6, 10, NEON_PINK)
	b.Neon(keys)
	b.Box(32, 0, 0, 22, 62, 42, CARBON)
	local glass = b.Box(32, 6, 21.2, 16, 50, 0.6, NEON_CYAN)
	b.Neon(glass)
	glass.Transparency = 0.3
	b.Light(glass, NEON_CYAN, 10, 0.7)
	b.Footprint(90, 44, 62)
end
R.RacingRig = function(b, _ctx)
	b.Box(0, 0, 0, 96, 6, 44, CARBON, M.Metal)
	-- siège baquet
	local red = b.Map(RACE_RED)
	b.Box(-24, 6, 0, 36, 14, 40, CARBON, M.Leather)
	b.BoxR(CFrame.new(-38, 36, 0) * CFrame.Angles(0, 0, 0.25), 10, 56, 40, CARBON, M.Leather)
	b.BoxR(CFrame.new(-37, 36, 0) * CFrame.Angles(0, 0, 0.25), 11, 40, 12, red, M.Leather)
	-- colonne + volant + pédalier
	b.Box(22, 6, 0, 6, 44, 6, GREY, M.Metal)
	b.BoxR(CFrame.new(16, 50, 0) * CFrame.Angles(0, 0, 0.35), 4, 24, 24, INK, M.Rubber)
	b.Box(40, 6, 0, 16, 6, 24, GREY_DARK, M.Metal)
	-- écran
	b.Box(32, 6, -14, 4, 60, 4, GREY, M.Metal)
	b.Box(32, 60, -14, 40, 26, 3, CARBON)
	screen(b, 32, 62, -12.3, 36, 22, rgb(110, 170, 255))
	b.Footprint(96, 44, 86)
end
R.BasketHoop = function(b, _ctx)
	b.Box(-10, 0, 0, 40, 12, 36, CARBON, M.SmoothPlastic)
	b.Cyl(-10, 12, 0, 7, 76, GREY, M.Metal)
	b.BoxR(CFrame.new(4, 88, 0) * CFrame.Angles(0, 0, -0.5), 30, 4, 4, GREY, M.Metal)
	b.Box(22, 80, -2, 4, 30, 44, WHITE)
	b.Box(24.4, 86, -2, 0.4, 12, 16, RACE_RED)
	-- cercle orange (8 petits segments) + ballon
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		b.Box(36 + math.cos(angle) * 10, 80, math.sin(angle) * 10, 5, 2, 5, rgb(255, 130, 50), M.Metal)
	end
	local net = b.Cyl(36, 68, 0, 16, 12, WHITE, M.Fabric)
	net.Transparency = 0.5
	b.Ball(34, 10, 26, 18, rgb(250, 140, 60), M.Rubber)
	b.Footprint(70, 50, 110)
end
R.FootballGoal = function(b, _ctx)
	for _, x in ipairs({ -44, 44 }) do
		b.Box(x, 0, 12, 5, 80, 5, WHITE, M.Metal)
		b.BoxR(CFrame.new(x, 40, -4) * CFrame.Angles(-0.4, 0, 0), 3, 82, 3, WHITE, M.Metal)
	end
	b.Box(0, 78, 12, 93, 5, 5, WHITE, M.Metal)
	local net = b.BoxR(CFrame.new(0, 40, -6) * CFrame.Angles(-0.4, 0, 0), 88, 84, 0.6, WHITE, M.Fabric)
	net.Transparency = 0.6
	net.CastShadow = false
	b.Ball(10, 9, 22, 18, WHITE, M.SmoothPlastic)
	b.Footprint(98, 40, 82)
end
R.BoxingBag = function(b, _ctx)
	b.Box(-38, 0, 0, 20, 5, 30, CARBON, M.Metal)
	b.Box(-38, 5, 0, 7, 92, 7, CARBON, M.Metal)
	b.Box(-10, 92, 0, 62, 6, 6, CARBON, M.Metal)
	b.Box(18, 72, 0, 1.5, 20, 1.5, GREY, M.Metal)
	b.Cyl(18, 20, 0, 30, 52, b.Map(RACE_RED), M.Leather)
	b.Cyl(18, 34, 0, 30.6, 4, INK, M.Leather)
	b.Cyl(18, 58, 0, 30.6, 4, INK, M.Leather)
	b.Footprint(80, 34, 98)
end
R.GuitarAmp = function(b, _ctx)
	b.Box(0, 0, 0, 84, 76, 40, CARBON, M.Leather)
	b.Box(0, 62, 20.3, 78, 10, 0.8, GOLD, M.Metal)
	for index = 0, 4 do
		knob(b, -26 + index * 12, 67, 21.2, 5, INK)
	end
	b.Box(0, 6, 20.3, 76, 52, 0.8, rgb(70, 64, 80), M.Fabric)
	b.CylZ(0, 32, 20.8, 36, 0.6, INK, M.Fabric)
	b.Box(0, 76, 0, 34, 4, 8, INK, M.Leather)
	b.Footprint(84, 40, 80)
end
R.DrumKit = function(b, _ctx)
	local shell = b.Map(rgb(80, 110, 230))
	b.CylZ(0, 26, 0, 50, 32, shell, M.SmoothPlastic)
	b.CylZ(0, 26, 16.2, 44, 0.6, rgb(244, 246, 255), M.SmoothPlastic)
	for index, x in ipairs({ -14, 14 }) do
		b.Cyl(x, 52, -6, 20, 14, shell, M.SmoothPlastic)
		local _ = index
	end
	b.Cyl(-40, 0, 6, 3, 44, GREY, M.Metal)
	b.Cyl(-40, 44, 6, 26, 10, CHROME, M.Metal) -- caisse claire
	b.Cyl(40, 0, 6, 28, 38, shell, M.SmoothPlastic) -- tom basse
	for _, spec in ipairs({ { -46, 70, -10 }, { 46, 78, -10 } }) do
		b.Cyl(spec[1], 0, spec[3], 2.5, spec[2], GREY, M.Metal)
		b.Cyl(spec[1], spec[2], spec[3], 30, 1, GOLD, M.Metal)
	end
	b.Footprint(100, 60, 80)
end
R.DJBooth = function(b, _ctx)
	b.Box(0, 0, 0, 96, 64, 44, CARBON, M.SmoothPlastic)
	local front = b.Box(0, 6, 22.3, 88, 48, 0.8, rgb(20, 20, 34))
	local _ = front
	for index = 0, 9 do
		local bar = b.Box(-38 + index * 8.4, 10, 22.8, 5, 10 + (index * 7) % 5 * 7, 0.5, index % 2 == 0 and NEON_CYAN or NEON_PINK)
		b.Neon(bar)
	end
	for _, x in ipairs({ -28, 28 }) do
		b.Cyl(x, 64, 2, 30, 3, INK, M.SmoothPlastic)
		b.Cyl(x, 67, 2, 8, 0.6, NEON_PINK, M.SmoothPlastic)
	end
	b.Box(0, 64, 2, 18, 4, 22, rgb(60, 62, 84))
	b.Light(front, NEON_PINK, 12, 0.7)
	b.Footprint(96, 44, 70)
end
R.SharkTank = function(b, _ctx)
	b.Box(0, 0, 0, 96, 26, 46, CARBON, M.SmoothPlastic)
	local glass = b.Box(0, 26, 0, 94, 66, 44, GLASS, M.Glass)
	glass.Transparency = 0.55
	glass.CastShadow = false
	local water = b.Box(0, 28, 0, 90, 56, 40, rgb(60, 140, 220), M.Glass)
	water.Transparency = 0.45
	water.CastShadow = false
	b.Box(0, 26, 0, 90, 4, 40, rgb(240, 220, 180), M.Sand)
	for index, spec in ipairs({ { -18, 56, -6 }, { 18, 42, 8 } }) do
		local shark = b.BoxR(CFrame.new(spec[1], spec[2], spec[3]) * CFrame.Angles(0, index * 0.4, 0), 26, 10, 10, rgb(130, 150, 190), M.SmoothPlastic)
		shark.CastShadow = false
		b.Wedge(spec[1], spec[2] + 5, spec[3], 6, 8, 3, rgb(130, 150, 190), "Front")
	end
	b.Box(0, 92, 0, 98, 4, 48, CARBON, M.SmoothPlastic)
	b.Light(water, rgb(120, 200, 255), 12, 0.7)
	b.Footprint(98, 48, 96)
end
R.RocketModel = function(b, _ctx)
	b.Box(0, 0, 0, 80, 6, 50, GREY, M.Metal)
	b.Box(28, 6, -8, 8, 80, 8, b.Map(RACE_RED), M.Metal)
	b.Cyl(-6, 16, 0, 24, 54, WHITE, M.SmoothPlastic)
	b.Ball(-6, 70, 0, 24, RACE_RED, M.SmoothPlastic)
	b.Cyl(-6, 40, 0, 24.6, 4, RACE_RED, M.SmoothPlastic)
	local window = b.CylZ(-6, 52, 12.2, 9, 1, NEON_CYAN)
	b.Neon(window)
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.BoxR(CFrame.new(-6 + math.cos(angle) * 14, 20, math.sin(angle) * 14) * CFrame.Angles(0, -angle, 0), 10, 16, 2, RACE_RED)
	end
	local flame = b.Ball(-6, 10, 0, 14, rgb(255, 170, 60))
	b.Neon(flame)
	b.Footprint(80, 50, 82)
end
R.Observatory = function(b, _ctx)
	b.Cyl(0, 0, 0, 40, 8, CARBON, M.Metal)
	b.Cyl(0, 8, 0, 12, 40, GREY, M.Metal)
	b.Ball(0, 48, 0, 18, CARBON, M.Metal)
	b.BoxR(CFrame.new(0, 58, 0) * CFrame.Angles(0, 0, 0.5), 84, 20, 20, WHITE, M.SmoothPlastic)
	b.BoxR(CFrame.new(33, 78, 0) * CFrame.Angles(0, 0, 0.5), 18, 24, 24, CARBON, M.SmoothPlastic)
	b.BoxR(CFrame.new(-4, 72, 0) * CFrame.Angles(0, 0, 0.5), 30, 5, 5, GREY, M.Metal)
	b.Footprint(80, 40, 92)
end
R.MechRobot = function(b, _ctx)
	local white = b.Map(rgb(240, 244, 252))
	local blue = rgb(80, 150, 255)
	for _, x in ipairs({ -14, 14 }) do
		b.Box(x, 0, 0, 20, 10, 28, blue, M.SmoothPlastic)
		b.Box(x, 10, 0, 14, 26, 14, GREY, M.Metal)
	end
	b.Box(0, 36, 0, 50, 36, 30, white, M.SmoothPlastic)
	local core = b.Ball(0, 56, 15, 12, NEON_CYAN)
	b.Neon(core)
	b.Light(core, NEON_CYAN, 10, 0.8)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 30, 66, 0, 18, blue, M.SmoothPlastic)
		b.Box(side * 32, 34, 0, 12, 30, 12, white, M.SmoothPlastic)
		b.Ball(side * 32, 30, 0, 14, blue, M.SmoothPlastic)
	end
	b.Box(0, 72, 0, 30, 22, 24, white, M.SmoothPlastic)
	local visor = b.Box(0, 80, 12.3, 24, 7, 0.6, NEON_CYAN)
	b.Neon(visor)
	b.Cyl(0, 94, 0, 2, 8, GREY, M.Metal)
	local tip = b.Ball(0, 103, 0, 5, RACE_RED)
	b.Neon(tip)
	b.Footprint(76, 30, 104)
end
R.AstronautStatue = function(b, _ctx)
	b.Cyl(0, 0, 0, 80, 10, rgb(200, 196, 220), M.Slate)
	for _, x in ipairs({ -8, 8 }) do
		b.Box(x, 10, 0, 12, 18, 14, WHITE, M.Fabric)
	end
	b.Box(0, 28, -8, 36, 32, 10, GREY, M.Metal) -- sac à dos
	b.Box(0, 28, 0, 30, 32, 20, WHITE, M.Fabric)
	b.Box(0, 40, 10.2, 12, 8, 0.6, NAVY)
	b.BoxR(CFrame.new(-20, 44, 0) * CFrame.Angles(0, 0, 0.3), 10, 24, 10, WHITE, M.Fabric)
	b.BoxR(CFrame.new(20, 64, 0) * CFrame.Angles(0, 0, -0.3), 10, 24, 10, WHITE, M.Fabric)
	b.Ball(0, 72, 0, 30, WHITE, M.SmoothPlastic)
	local visor = b.Ball(0, 72, 5, 22, rgb(40, 60, 130), M.Glass)
	visor.Reflectance = 0.2
	b.Cyl(36, 10, 10, 2, 60, GREY, M.Metal)
	b.Box(44, 58, 10, 16, 10, 0.6, rgb(80, 150, 255))
	b.Footprint(80, 40, 88)
end
R.PirateChest = function(b, _ctx)
	local wood = b.Map(rgb(170, 110, 70))
	b.Box(0, 0, 0, 84, 40, 50, wood, M.Wood)
	for _, x in ipairs({ -30, 30 }) do
		b.Box(x, 0, 0, 7, 40.4, 50.4, GOLD, M.Metal)
	end
	b.BoxR(CFrame.new(0, 58, -28) * CFrame.Angles(-1.1, 0, 0), 84, 30, 8, wood, M.Wood)
	for index = 0, 8 do
		b.Ball(-30 + (index % 5) * 15, 40 + (index > 4 and 5 or 0), -6 + (index % 3) * 8, 12, GOLD, M.Metal)
	end
	b.Ball(-10, 48, 4, 8, RACE_RED, M.Glass)
	b.Ball(12, 48, 0, 8, NEON_CYAN, M.Glass)
	b.Box(0, 22, 25.3, 14, 14, 1.2, GOLD, M.Metal)
	b.Footprint(84, 50, 60)
end
R.Motorbike = function(b, _ctx)
	for _, x in ipairs({ -34, 34 }) do
		wheel3D(b, x, 18, 0, 36, 8, CHROME)
	end
	local red = b.Map(RACE_RED)
	b.Box(-4, 28, 0, 34, 20, 14, CHROME, M.Metal) -- moteur
	b.Box(6, 46, 0, 32, 14, 18, red, M.SmoothPlastic) -- réservoir
	b.Box(-22, 50, 0, 28, 6, 16, INK, M.Leather) -- selle
	b.BoxR(CFrame.new(30, 40, 0) * CFrame.Angles(0, 0, -0.45), 5, 50, 5, CHROME, M.Metal)
	b.Box(22, 64, 0, 4, 4, 34, INK, M.Metal)
	local lamp = b.CylX(36, 56, 0, 10, 4, BUTTER)
	b.Neon(lamp)
	b.BoxR(CFrame.new(-30, 22, 8) * CFrame.Angles(0, 0, 0.15), 40, 5, 5, CHROME, M.Metal) -- échappement
	b.Footprint(100, 24, 70)
end
R.DinoSkeleton = function(b, _ctx)
	b.Box(0, 0, 0, 96, 8, 36, CARBON, M.Marble)
	local bone = rgb(246, 238, 220)
	local spine = { { -46, 36 }, { -30, 44 }, { -14, 48 }, { 2, 50 }, { 16, 54 }, { 26, 64 }, { 30, 74 } }
	for index, p in ipairs(spine) do
		b.Ball(p[1], p[2], 0, 7, bone, M.Marble)
		local next = spine[index + 1]
		if next then
			local dx, dy = next[1] - p[1], next[2] - p[2]
			b.BoxR(CFrame.new((p[1] + next[1]) / 2, (p[2] + next[2]) / 2, 0) * CFrame.Angles(0, 0, math.atan2(dy, dx)), math.sqrt(dx * dx + dy * dy), 3, 3, bone, M.Marble)
		end
	end
	for index = 0, 3 do
		b.Box(-8 + index * 6, 30, 0, 2, 18 - index * 2, 16, bone, M.Marble)
	end
	for _, x in ipairs({ -10, 10 }) do
		b.Box(x, 8, 0, 4, 42, 4, bone, M.Marble)
	end
	b.Box(36, 70, 0, 26, 14, 14, bone, M.Marble)
	b.Box(38, 64, 0, 22, 5, 12, bone, M.Marble)
	b.Box(0, 4, 18.3, 20, 5, 0.6, GOLD, M.Metal)
	b.Footprint(96, 36, 86)
end

----------------------------------------------------------------------
-- Familles (v9.3) : recettes des autres modules + repli par catégorie
----------------------------------------------------------------------

-- Aides partagées avec les modules de recettes (House3DCritters, House3DObjects)
local H = {
	M = M,
	rgb = rgb,
	WHITE = WHITE,
	BLACK = BLACK,
	CREAM = CREAM,
	WOOD = WOOD,
	WOOD_LIGHT = WOOD_LIGHT,
	WOOD_DARK = WOOD_DARK,
	PINK = PINK,
	PINK_SOFT = PINK_SOFT,
	LILAC = LILAC,
	MINT = MINT,
	SKY = SKY,
	BUTTER = BUTTER,
	GOLD = GOLD,
	GREY = GREY,
	GREY_DARK = GREY_DARK,
	INK = INK,
	LEAF = LEAF,
	LEAF_DARK = LEAF_DARK,
	GLASS = GLASS,
	FIRE = FIRE,
	darken = darken,
	lighten = lighten,
	woodOf = woodOf,
	accent = accent,
	greenOf = greenOf,
	lightOf = lightOf,
	legs4 = legs4,
	knob = knob,
	cabinet = cabinet,
	bush = bush,
	pot = pot,
	rug = rug,
	door = door,
	windowRecipe = windowRecipe,
	plaque = plaque,
	screen = screen,
	critter = critter,
	smallPlant = smallPlant,
	tree = tree,
}
House3DRecipes.Helpers = H

-- Recettes par famille (id -> recette), remplies par les autres modules
local FAMILY: { [string]: Recipe } = {}
-- Objets à plat (tapis) / animaux (petite respiration dans la vue 3D)
local FLAT: { [string]: boolean } = {}
local PETS: { [string]: boolean } = {}

local function loadFamilies(name: string)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" and type(result.Register) == "function" then
		local okRegister, err = pcall(result.Register, R, FAMILY, H, { Flat = FLAT, Pets = PETS })
		if not okRegister then
			warn("[House3D] " .. name .. " : " .. tostring(err))
		end
	elseif not ok then
		warn("[House3D] " .. name .. " : " .. tostring(result))
	end
end
loadFamilies("House3DCritters")
loadFamilies("House3DObjects")
loadFamilies("House3DToys")

local DOORS_AS_CARD: { [string]: boolean } = {}

-- Objets qu'on colle contre le mur du fond (portes, grands rangements)
local AGAINST_WALL: { [string]: boolean } = {
	Wardrobe = true, Bookshelf = true, Fridge = true, Fireplace = true, Dresser = true, DrawerCabinet = true,
	HomeCinema = true, TVStand = true, KitchenIsland = false, Shower = true, ToriiGate = true, ArcadeMachine = true,
	SlotMachine = true, Speaker = true, VanityTable = true, Aquarium = true, Stove = true, Toilet = true,
	KitchenSink = true, Jukebox = true, PinballMachine = false, LadderShelf = true,
	-- v9.2
	LockerCabinet = true, NeonArcade = true, SharkTank = true, GuitarAmp = true,
}

-- Repli (objet inconnu d'une future mise à jour) : une forme 3D simple aux
-- couleurs de l'objet, jamais un carton
local function fallback(b: Builder, _ctx: Ctx)
	local main = accent(b, 1, PINK)
	local item = b.Item
	if item and item.Placement == "Wall" then
		b.Round(0, 10, 3, 84, 80, 6, 6, darken(main, 0.2), M.Wood)
		b.Round(0, 16, 6, 70, 68, 2, 4, lighten(main, 0.35), M.SmoothPlastic)
		b.Ball(0, 50, 8, 30, main)
		b.Footprint(84, 8, 90)
		return
	end
	b.Round(0, 0, 0, 70, 12, 50, 8, darken(main, 0.25), M.Wood)
	b.Egg(0, 40, 0, 56, 56, 40, main)
	b.Ball(0, 74, 0, 24, lighten(main, 0.3))
	b.Footprint(70, 50, 86)
end

function House3DRecipes.Has(itemId: string): boolean
	return R[itemId] ~= nil or FAMILY[itemId] ~= nil
end

-- Recette d'un objet (jamais nil : repli 3D par défaut)
function House3DRecipes.For(item: any): (Recipe, Info)
	local info: Info = { Wall = false, Flat = false, Glow = type(item) == "table" and item.Category == "Lights", Pet = false }
	if type(item) ~= "table" or type(item.Id) ~= "string" then
		return fallback, info
	end
	local id = item.Id
	local recipe = R[id] or FAMILY[id]
	if not recipe and item.Category == "Windows" and item.Placement == "Wall" then
		recipe = windowRecipe
	end
	if item.Category == "Doors" and item.Placement ~= "Wall" and not DOORS_AS_CARD[id] then
		info.Wall = true
		recipe = recipe or door
	end
	if FLAT[id] or id == "KnittedRug" or string.find(id, "Rug$") then
		info.Flat = true
		recipe = recipe or rug
	end
	if not recipe and item.Placement ~= "Wall" and item.Category == "Plants" then
		recipe = (tonumber(item.Size) or 60) >= 100 and tree(nil, true) or smallPlant(true)
	end
	if AGAINST_WALL[id] then
		info.Wall = true
	end
	info.Pet = PETS[id] == true
	return recipe or fallback, info
end

-- Contexte d'une recette (dessus de HouseSurfaces, couleur des moulures)
function House3DRecipes.Context(item: any, trim: Color3): Ctx
	local raw = nil
	local okRaw, value = pcall(HouseSurfaces.Raw, item.Id)
	if okRaw and type(value) == "table" then
		raw = value
	end
	local ctx: Ctx = {
		Item = item,
		Raw = raw,
		Trim = trim,
		TopY = function(index: number, default: number): number
			local surface = raw and raw[index]
			local y = surface and tonumber(surface[3])
			if y then
				return math.clamp(100 - y, 2, 100)
			end
			return default
		end,
		Span = function(index: number, default0: number, default1: number): (number, number)
			local surface = raw and raw[index]
			local x0 = surface and tonumber(surface[1])
			local x1 = surface and tonumber(surface[2])
			if x0 and x1 and x1 > x0 then
				return x0 - 50, x1 - 50
			end
			return default0, default1
		end,
	}
	return ctx
end

----------------------------------------------------------------------
-- Construction d'un objet (vue 3D et monde)
----------------------------------------------------------------------

local HouseCommon = require(script.Parent.HouseCommon)
local HouseTints: any = nil
do
	local module = script.Parent:FindFirstChild("HouseTints")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			HouseTints = result
		end
	end
end

-- Palette du dessin 2D d'un objet (peinte une seule fois, hors écran)
local paletteCache: { [string]: { Color3 } } = {}
function House3DRecipes.PaletteOf(item: any): { Color3 }
	local id = tostring(item.Id)
	local cached = paletteCache[id]
	if cached then
		return cached
	end
	local colors = {}
	local ok, painted = pcall(House3DKit.Paint, item, nil, nil)
	if ok and type(painted) == "table" then
		colors = painted.Colors
		pcall(function()
			painted.Content:Destroy()
		end)
	end
	paletteCache[id] = colors
	return colors
end

-- Couleur d'un objet teint (entry.C = id de Config.House.Tints)
local function tintMapper(itemId: string, tintId: any): ((Color3) -> Color3)?
	if not HouseTints or type(tintId) ~= "string" or type(HouseTints.Mapper) ~= "function" then
		return nil
	end
	local ok, result = pcall(HouseTints.Mapper, itemId, tintId)
	if not ok or type(result) ~= "function" then
		return nil
	end
	return function(color: Color3): Color3
		local okMap, mapped = pcall(result, color)
		return okMap and typeof(mapped) == "Color3" and mapped or color
	end
end

export type ItemData = {
	Item: any,
	K: number, -- studs par unité (la boîte 2D fait 100 x 100 unités)
	FW: number, -- empreinte (studs) : largeur, profondeur, hauteur
	FD: number,
	H: number,
	Tops: { [number]: House3DKit.Top }, -- dessus (unités, repère de la recette)
	Info: Info,
	SeatAt: { X: number, Y: number, Z: number, W: number, D: number }?,
	Lights: { Light },
	Glows: { BasePart },
	Parts: { BasePart },
	Locals: { CFrame },
}

-- Objets où l'on peut s'asseoir / s'allonger (monde) en plus des sièges et lits de HouseSurfaces
local SITTABLE: { [string]: boolean } = {
	Sofa = true, Armchair = true, Beanbag = true, EggChair = true, GardenBench = true, Pouf = true, HeartArmchair = true,
	CatSofa = true, CrystalThrone = true, Hammock = true, GamerBeanbag = true, FloorCushion = true, GamerChair = true,
	GamingChair = true, RockingChair = true, BarStool = true, MushroomStool = true, RacingRig = true, BunkBed = true,
	RaceCarBed = true, PetBed = true, KotatsuTable = false,
}

-- Construit les pièces d'un objet dans `parent`, au repère `origin` (x à
-- droite, y en haut depuis le sol, +z = le devant de l'objet)
function House3DRecipes.Make(item: any, entry: any?, k: number, parent: Instance, origin: CFrame, trim: Color3?): ItemData
	local recipe, info = House3DRecipes.For(item)
	local mirror = type(entry) == "table" and entry.F == true
	local tintId = type(entry) == "table" and entry.C or nil
	local mapper = tintMapper(item.Id, tintId)
	local b = House3DKit.Builder(parent, origin, k, mirror, mapper, House3DRecipes.PaletteOf(item))
	b.Item = item
	-- dessin 2D (tableaux, affiches) : peint seulement si la recette le demande
	b.PaintFn = function(): House3DKit.Painted?
		local okPaint, painted = pcall(House3DKit.Paint, item, entry, function(root: Instance)
			if HouseTints and type(HouseTints.Apply) == "function" and type(tintId) == "string" then
				HouseTints.Apply(root, tintId)
			end
		end)
		return okPaint and painted or nil
	end
	local ctx = House3DRecipes.Context(item, trim or CREAM)
	local ok, err = pcall(recipe, b, ctx)
	if not ok or #b.Parts == 0 then
		if not ok then
			warn("[House3D] Recette " .. tostring(item.Id) .. " : " .. tostring(err))
		end
		for _, p in ipairs(b.Parts) do
			p:Destroy()
		end
		b = House3DKit.Builder(parent, origin, k, mirror, mapper, House3DRecipes.PaletteOf(item))
		b.Item = item
		pcall(fallback, b, ctx)
	end
	-- place assise par défaut (sièges, lits, canapés) : le premier dessus
	if not b.SeatAt and (SITTABLE[item.Id] or HouseSurfaces.IsSeat(item.Id) or HouseSurfaces.IsBed(item.Id)) then
		local top = b.Tops[1]
		if top then
			b.SeatAt = { X = top.X, Y = top.Y, Z = top.Z, W = top.W, D = top.D }
		end
	end
	-- dessus déclarés par HouseSurfaces mais pas par la recette
	local raw = ctx.Raw
	if raw then
		for index, surface in ipairs(raw) do
			if not b.Tops[index] and type(surface) == "table" then
				local x0, x1, y = tonumber(surface[1]) or 10, tonumber(surface[2]) or 90, tonumber(surface[3]) or 50
				b.Tops[index] = { X = ((x0 + x1) / 2 - 50) * (mirror and -1 or 1), Y = 100 - y, Z = 0, W = x1 - x0, D = b.Depth * 0.8 }
			end
		end
	end
	return {
		Item = item,
		K = k,
		FW = b.Width * k,
		FD = math.max(0.2, b.Depth * k),
		H = b.Height * k,
		Tops = b.Tops,
		Info = info,
		SeatAt = b.SeatAt,
		Lights = b.Lights,
		Glows = b.Glows,
		Parts = b.Parts,
		Locals = b.Locals,
	}
end

-- Taille d'un objet posé : studs par unité (`scale` = studs par px de la pièce 2D)
function House3DRecipes.UnitScale(item: any, entry: any?, scale: number): number
	local s = type(entry) == "table" and tonumber(entry.S) or 1
	if s == nil or s ~= s then
		s = 1
	end
	return (tonumber(item.Size) or 80) * math.clamp(s, 0.2, 3) * scale / 100
end

export type BuildOptions = {
	Scale: number?, -- studs par px de la pièce 2D (0.05 par défaut, comme la vue 3D)
	Night: boolean?, -- lampes plus fortes
	Collide: boolean?, -- false = aucune collision (vue 3D) ; sinon gros meubles solides
	Query: boolean?, -- false = invisibles aux rayons (vue 3D) ; true par défaut
	Trim: Color3?, -- couleur des moulures (fenêtres, portes)
	Shadows: boolean?, -- false = aucune ombre portée
}

-- Modèle 3D autonome d'un objet (voir l'en-tête du module) + ses données
function House3DRecipes.BuildModel(itemId: string, entry: any?, options: BuildOptions?): (Model?, ItemData?)
	local item = HouseCommon.ItemsById[itemId]
	if type(item) ~= "table" then
		return nil, nil
	end
	local opts: BuildOptions = type(options) == "table" and options or {}
	local scale = tonumber(opts.Scale) or 0.05
	local k = House3DRecipes.UnitScale(item, entry, scale)
	local model = Instance.new("Model")
	model.Name = tostring(item.Id)
	-- (le devant de l'objet regarde -Z : demi-tour autour de Y)
	local turn = CFrame.Angles(0, math.pi, 0)
	local data = House3DRecipes.Make(item, entry, k, model, turn, opts.Trim)
	local wall = item.Placement == "Wall"
	local query = opts.Query ~= false
	for _, p in ipairs(data.Parts) do
		p.CanQuery = query
		if opts.Shadows == false then
			p.CastShadow = false
		end
	end
	if opts.Night ~= nil then
		for _, light in ipairs(data.Lights) do
			light.Brightness *= opts.Night == true and 1.7 or 0.9
		end
	end
	-- Pièce de base (PrimaryPart) : pivot = bas du centre de l'empreinte
	-- (objet mural : bas de la boîte, contre le mur), devant vers -Z
	local fw, fd, height = data.FW, data.FD, math.max(0.2, data.H)
	local rootZ = wall and -fd / 2 or 0
	local root = House3DKit.NewPart("Part", "Root", Vector3.new(math.max(0.2, fw), 0.1, fd), CFrame.new(0, 0.05, rootZ), WHITE, nil, 1)
	root.CastShadow = false
	root.CanQuery = query
	root.PivotOffset = CFrame.new(0, -0.05, -rootZ)
	root.Parent = model
	model.PrimaryPart = root
	-- Collisions (monde) : un bloc invisible pour les gros meubles au sol
	local collide = opts.Collide ~= false
	if collide and not wall and not data.Info.Flat and height >= 1.5 and math.max(fw, fd) >= 1.8 then
		local top = data.Tops[1]
		local solidH = height
		if data.SeatAt then
			solidH = math.max(0.4, data.SeatAt.Y * k)
		elseif top and top.Y * k > 0.8 then
			solidH = top.Y * k
		end
		local hitbox = House3DKit.NewPart("Part", "Hitbox", Vector3.new(math.max(0.4, fw * 0.92), solidH, math.max(0.4, fd * 0.92)), CFrame.new(0, solidH / 2, 0), WHITE, nil, 1)
		hitbox.CanCollide = true
		hitbox.CanQuery = true
		hitbox.CastShadow = false
		hitbox.Parent = model
	end
	-- Place assise
	local seat = data.SeatAt
	if seat then
		local seatPart = House3DKit.NewPart("Part", "SeatPart", Vector3.new(math.max(0.3, seat.W * k), 0.2, math.max(0.3, seat.D * k)),
			turn * CFrame.new(seat.X * k, seat.Y * k + 0.1, seat.Z * k) * turn, WHITE, nil, 1)
		seatPart.CastShadow = false
		seatPart.CanQuery = query
		seatPart.Parent = model
	end
	-- Attributs (voir l'en-tête)
	local top = data.Tops[1]
	model:SetAttribute("ItemId", tostring(item.Id))
	model:SetAttribute("Footprint", Vector3.new(fw, height, fd))
	model:SetAttribute("TopHeight", top and top.Y * k or 0)
	if top then
		model:SetAttribute("TopCenter", Vector3.new(-top.X * k, top.Y * k, -top.Z * k))
		model:SetAttribute("TopSize", Vector2.new(top.W * k, top.D * k))
	end
	model:SetAttribute("Wall", wall)
	model:SetAttribute("Flat", data.Info.Flat == true)
	model:SetAttribute("Pet", data.Info.Pet == true)
	model:SetAttribute("AgainstWall", data.Info.Wall == true)
	model.WorldPivot = CFrame.new()
	return model, data
end

-- API publique : modèle 3D d'un objet (nil si l'objet n'existe pas)
function House3DRecipes.BuildItem(itemId: string, entry: any?, options: BuildOptions?): Model?
	local result: Model? = nil
	local ok, err = pcall(function()
		result = (House3DRecipes.BuildModel(itemId, entry, options))
	end)
	if not ok then
		warn("[House3D] BuildItem " .. tostring(itemId) .. " : " .. tostring(err))
		return nil
	end
	return result
end

-- (pour les couleurs de secours ailleurs)
House3DRecipes.BLACK = BLACK

return House3DRecipes
