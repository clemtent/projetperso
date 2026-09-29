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

local vary = House3DKit.Vary
local BRASS = rgb(214, 172, 92)
local CHROME_METAL = rgb(206, 212, 224)

-- (v9.8) pieds fuselés : fût du haut + fût affiné du bas (les petits pieds : un bloc)
local function legs4(b: Builder, w: number, d: number, h: number, t: number, color: Color3, material: Enum.Material?)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * (w / 2 - t / 2), sz * (d / 2 - t / 2)
			if h < 12 then
				b.Box(x, 0, z, t, h, t, color, material)
			else
				b.Box(x, h * 0.42, z, t, h * 0.58, t, color, material)
				-- (le bas s'affine vers l'intérieur du meuble, comme un pied tourné)
				b.Box(x - sx * t * 0.1, 0, z - sz * t * 0.1, t * 0.72, h * 0.42, t * 0.72, color, material)
			end
		end
	end
end

-- Bouton de tiroir : rosace + bouton poli
local function knob(b: Builder, x: number, y: number, z: number, size: number, color: Color3?)
	local metal = color or BRASS
	local ball = b.Ball(x, y, z, size, metal, M.Metal)
	ball.Reflectance = 0.25
	b.CylZ(x, y, z - size * 0.42, size * 1.3, size * 0.22, darken(metal, 0.12), M.Metal)
end

-- Caisson (commode, table de nuit...) : corps, façade en creux sombre (les
-- joints entre les tiroirs se lisent), tiroirs / portes à panneau, poignées
-- chromées, charnières, socle en retrait
local function cabinet(b: Builder, w: number, d: number, h: number, body: Color3, front: Color3, drawers: number, doors: number, feet: number)
	local y0 = feet
	if feet > 0 then
		legs4(b, w - 6, d - 6, feet, 5, darken(body, 0.2), M.Wood)
		b.Box(0, feet * 0.4, 0, w - 12, feet * 0.6, d - 12, darken(body, 0.3), M.Wood)
	end
	b.Box(0, y0, 0, w, h - y0, d, body, M.Wood)
	local inner = h - y0 - 6
	-- (couches de la façade espacées d'au moins `g` : pas de scintillement)
	local g = House3DKit.Gap(b, 0.8)
	-- joints (fond sombre derrière les façades)
	b.Box(0, y0 + 1.6, d / 2, w - 6.8, inner + 2.8, 2 * g, darken(body, 0.55), M.SmoothPlastic)
	local rows = math.max(drawers, 0)
	if rows > 0 then
		local rowH = inner / rows
		for index = 1, rows do
			local y = y0 + 3 + (index - 1) * rowH
			b.Box(0, y + 0.8, d / 2 + 1.5 * g, w - 8, rowH - 1.6, 3 * g, front, M.Wood)
			-- panneau en léger relief (façade "shaker")
			b.Box(0, y + 3, d / 2 + 3 * g, w - 16, rowH - 6, 2 * g, lighten(front, 0.07), M.Wood)
			House3DKit.Handle(b, 0, y + rowH / 2 + 0.4, d / 2 + 4 * g, math.min(18, (w - 16) * 0.3), false)
		end
	elseif doors > 0 then
		local doorW = (w - 8) / doors
		for index = 1, doors do
			local x = -w / 2 + 4 + (index - 0.5) * doorW
			b.Box(x, y0 + 3, d / 2 + 1.5 * g, doorW - 1.6, inner, 3 * g, front, M.Wood)
			b.Box(x, y0 + 7, d / 2 + 3 * g, doorW - 9, inner - 8, 2 * g, lighten(front, 0.07), M.Wood)
			local side = (index - 0.5) < doors / 2 and 1 or -1
			House3DKit.Handle(b, x + side * (doorW / 2 - 2.7), y0 + 3 + inner * 0.55, d / 2 + 3 * g, math.min(16, inner * 0.22), true)
			-- charnières (côté opposé à la poignée)
			for _, hy in ipairs({ y0 + 3 + inner * 0.15, y0 + 3 + inner * 0.85 }) do
				local hinge = b.Cyl(x - side * (doorW / 2 - 0.4), hy - 2, d / 2 + 3 * g, 1.4, 4, BRASS, M.Metal)
				hinge.Reflectance = 0.2
			end
		end
	end
end

-- Feuillage : boule sombre au cœur, touffes autour, petites feuilles ovales en
-- surface (le volume se lit comme un vrai buisson)
local function bush(b: Builder, x: number, y: number, z: number, size: number, color: Color3, count: number)
	b.Ball(x, y, z, size * 0.9, darken(color, 0.18), M.SmoothPlastic)
	for index = 1, count do
		local angle = index / count * math.pi * 2
		b.Ball(x + math.cos(angle) * size * 0.34, y + (index % 2 == 0 and 0.12 or -0.1) * size, z + math.sin(angle) * size * 0.3, size * 0.62,
			vary(index % 2 == 0 and color or darken(color, 0.1), index, 0.08), M.SmoothPlastic)
	end
	local leaves = math.clamp(math.floor(size / 5), 4, 10)
	for index = 1, leaves do
		local angle = index * 2.4
		local up = ((index * 7) % 5) / 5 - 0.35
		local px, pz = math.cos(angle) * size * 0.46, math.sin(angle) * size * 0.4
		House3DKit.Leaf(b, x + px * 0.8, y + up * size * 0.55, z + pz * 0.8, size * 0.34, size * 0.2, math.atan2(px, pz), -0.3 - up * 0.5,
			vary(lighten(color, 0.08), index * 3, 0.12))
	end
end

-- Pot en terre : pied, corps évasé, lèvre roulée, terreau et petits cailloux
local function pot(b: Builder, diameter: number, height: number, color: Color3)
	b.Cyl(0, 0, 0, diameter * 0.74, height * 0.08, darken(color, 0.22), M.SmoothPlastic)
	b.Cyl(0, height * 0.06, 0, diameter * 0.8, height * 0.3, darken(color, 0.06), M.SmoothPlastic)
	b.Cyl(0, height * 0.34, 0, diameter * 0.88, height * 0.48, color, M.SmoothPlastic)
	b.Cyl(0, height * 0.8, 0, diameter, height * 0.2, lighten(color, 0.12), M.SmoothPlastic)
	local soilTop = height - House3DKit.Gap(b, 0.6)
	b.Cyl(0, height * 0.86, 0, diameter * 0.84, soilTop - height * 0.86, rgb(96, 70, 56), M.Ground)
	for index = 1, 3 do
		local angle = index * 2.1
		b.Ball(math.cos(angle) * diameter * 0.26, soilTop, math.sin(angle) * diameter * 0.22, diameter * 0.07, rgb(214, 204, 196), M.Slate)
	end
end

-- Moulure en gorge (corniche) : coin retourné, épais en haut, qui part de
-- l'arête (x, z) vers l'extérieur (yaw 0 = vers +z, ±pi/2 = vers ±x) ; y = bas
local function cove(b: Builder, x: number, y: number, z: number, length: number, h: number, out: number, yaw: number, color: Color3, material: Enum.Material?)
	local cf = CFrame.new(x + math.sin(yaw) * out / 2, y + h / 2, z + math.cos(yaw) * out / 2) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.pi, 0, 0)
	return b.Part("WedgePart", cf, Vector3.new(length, h, out), color, material, "Moulure")
end

----------------------------------------------------------------------
-- Recettes
----------------------------------------------------------------------

local R: { [string]: Recipe } = {}

-- TABLES --------------------------------------------------------------

-- (v9.8) pieds de table fuselés avec patins, ceinture sous le plateau
local function tableBase(b: Builder, cx: number, w: number, depth: number, top: number, thick: number, inset: number, legs: Color3, apron: Color3)
	local legH = top - thick
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local lx, lz = cx + sx * (w / 2 - inset), sz * (depth / 2 - inset)
			b.Box(lx, legH * 0.46, lz, 5.6, legH * 0.54, 5.6, legs, M.Wood)
			b.Box(lx - sx * 0.5, 1.4, lz - sz * 0.5, 4, legH * 0.46 - 1.4, 4, legs, M.Wood)
			b.Box(lx - sx * 0.5, 0, lz - sz * 0.5, 4.6, 1.4, 4.6, darken(legs, 0.45), M.Rubber)
		end
	end
	local apronH = math.min(7, legH * 0.18)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(cx, legH - apronH, sz * (depth / 2 - inset), w - 2 * inset - 5.6, apronH, 2.2, apron, M.Wood)
	end
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(cx + sx * (w / 2 - inset), legH - apronH, 0, 2.2, apronH, depth - 2 * inset - 5.6, apron, M.Wood)
	end
end

local function rectTable(depth: number, cloth: boolean, legColor: Color3?)
	return function(b: Builder, ctx: Ctx)
		local top = ctx.TopY(1, 60)
		local x0, x1 = ctx.Span(1, -48, 48)
		local w = x1 - x0
		local cx = (x0 + x1) / 2
		local wood = woodOf(b)
		local legs = legColor and b.Map(legColor) or darken(wood, 0.12)
		tableBase(b, cx, w, depth, top, 5, 6, legs, darken(wood, 0.08))
		-- plateau épais au chant biseauté
		House3DKit.Bevel(b, cx, top - 5, 0, w, 5, depth, 1.6, wood, M.Wood)
		if cloth then
			-- chemin de table brodé qui retombe devant / derrière, pompons
			local clothColor = lightOf(b, WHITE)
			local stripe = accent(b, 1, PINK)
			local runW = w * 0.3
			local g = House3DKit.Gap(b, 0.6)
			b.Box(cx, top - 0.2, 0, runW, g + 0.2, depth + 2 * g, clothColor, M.Fabric)
			for _, sz in ipairs({ -1, 1 }) do
				b.Box(cx, top - 10, sz * (depth / 2 + g / 2), runW, 10 + g, g, clothColor, M.Fabric)
				b.Box(cx, top - 8, sz * (depth / 2 + 1.5 * g), runW - 1, 1.4, g, stripe, M.Fabric)
				for _, sx in ipairs({ -1, 0, 1 }) do
					b.Ball(cx + sx * runW * 0.4, top - 11, sz * (depth / 2 + g), 2.4, stripe, M.Fabric)
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				b.Box(cx + sx * runW * 0.38, top + g, 0, 1.2, g, depth - 4, stripe, M.Fabric)
			end
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
	local legs = darken(wood, 0.15)
	-- pieds évasés (fuselés), tablette basse avec magazines et plateau
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local lx, lz = sx * (w / 2 - 8), sz * (depth / 2 - 8)
			b.BoxR(CFrame.new(lx, (top - 6) / 2, lz) * CFrame.Angles(-sz * 0.08, 0, sx * 0.08), 5.4, top - 6, 5.4, legs, M.Wood)
			b.Box(lx + sx * 1.5, 0, lz + sz * 1.5, 5, 1.4, 5, darken(legs, 0.4), M.Rubber)
		end
	end
	b.Box(0, top * 0.25, 0, w - 16, 3, depth - 16, darken(wood, 0.05), M.Wood)
	-- magazines + petit plateau sur la tablette
	local mag = { accent(b, 1, PINK), accent(b, 2, SKY), WHITE }
	for index = 1, 3 do
		b.BoxR(CFrame.new(-w * 0.18 + index * 1.2, top * 0.25 + 3 + index * 0.9 - 0.45, 1) * CFrame.Angles(0, index * 0.18, 0), 22, 0.9, 16, mag[index], M.SmoothPlastic)
	end
	b.Box(w * 0.2, top * 0.25 + 3, 0, 16, 2.4, 12, darken(wood, 0.3), M.Wood)
	b.Ball(w * 0.2, top * 0.25 + 6.5, 0, 5, accent(b, 3, BUTTER), M.SmoothPlastic)
	House3DKit.Bevel(b, 0, top - 6, 0, w, 6, depth, 2, wood, M.Wood)
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.SideTable = rectTable(60, false)
R.BigDesk = function(b, ctx)
	rectTable(56, false)(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -48, 48)
	local wood = woodOf(b)
	-- caisson à tiroirs à droite (façades à panneau, poignées, joints sombres)
	local cw = (x1 - x0) * 0.3
	local cx = x1 - cw / 2 - 2
	local front = accent(b, 1, PINK_SOFT)
	local g = House3DKit.Gap(b, 0.8)
	b.Box(cx, 0, 0, cw, top - 6.4, 52, darken(wood, 0.05), M.Wood)
	b.Box(cx, 1.5, 26, cw - 3, top - 9.4, 2 * g, darken(wood, 0.55), M.SmoothPlastic)
	for index = 1, 3 do
		local rowH = (top - 12) / 3
		local y = 4 + (index - 1) * rowH
		b.Box(cx, y, 26 + 1.5 * g, cw - 5, rowH - 1.4, 3 * g, front, M.Wood)
		b.Box(cx, y + 2.4, 26 + 3 * g, cw - 11, rowH - 6.2, 2 * g, lighten(front, 0.08), M.Wood)
		House3DKit.Handle(b, cx, y + rowH / 2, 26 + 4 * g, math.min(12, cw * 0.36), false)
	end
	-- voile de fond (panneau de modestie)
	b.Box((x0 + x1) / 2 - cw / 2 - 1, top - 30, -17.5, x1 - x0 - cw - 22, 22, 1.6, darken(wood, 0.1), M.Wood)
end
R.StudyDesk = R.BigDesk
R.PicnicTable = function(b, ctx)
	local top = ctx.TopY(1, 61)
	local bench = ctx.TopY(2, 29)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 44
	local wood = woodOf(b, WOOD)
	local dark = darken(wood, 0.15)
	-- pieds en A (de chaque côté) qui portent la table et les deux bancs
	for _, sx in ipairs({ -1, 1 }) do
		local lx = sx * (w / 2 - 12)
		for _, sz in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(lx, (top - 4) / 2, sz * (depth / 2 + 3)) * CFrame.Angles(-sz * 0.5, 0, 0), 5, (top - 4) / 0.88, 5, dark, M.Wood)
		end
		b.Box(lx, bench - 9, 0, 5, 4, depth + 52, dark, M.Wood) -- traverse sous les bancs
		b.Box(lx, top - 8, 0, 5, 4, depth - 4, dark, M.Wood) -- traverse sous la table
	end
	-- plateau en 5 lames (teintes variées, petits jours entre les lames)
	local n = 5
	local pd = (depth - (n - 1) * 0.8) / n
	for index = 1, n do
		b.Box(0, top - 4, -depth / 2 + pd / 2 + (index - 1) * (pd + 0.8), w, 4, pd, vary(wood, index, 0.08), M.WoodPlanks)
	end
	for _, side in ipairs({ -1, 1 }) do
		for index = 1, 2 do
			b.Box(0, bench - 4, side * (depth / 2 + 12) + (index - 1.5) * 7.2, w + 2, 4, 6.6, vary(wood, index * 5 + side, 0.08), M.WoodPlanks)
		end
	end
	-- nappe vichy (carreaux)
	local cloth = accent(b, 1, rgb(255, 150, 170))
	local cw, cd = w * 0.5 / 4, depth * 0.8 / 4
	for i = 0, 3 do
		for j = 0, 3 do
			b.Box(-w * 0.25 + (i + 0.5) * cw, top - 0.2, -depth * 0.4 + (j + 0.5) * cd, cw, House3DKit.Gap(b, 0.6) + 0.2, cd, (i + j) % 2 == 0 and cloth or lighten(cloth, 0.75), M.Fabric)
		end
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Top(2, 0, bench, depth / 2 + 12, w, 14)
	b.Footprint(w, depth + 40, top)
end
R.KitchenIsland = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -48, 48)
	local w, depth = x1 - x0, 50
	local body = accent(b, 1, MINT)
	-- socle en retrait (plinthe sombre), caisson, portes à panneau
	b.Box(0, 0, -1, w - 10, 5, depth - 12, darken(body, 0.45), M.SmoothPlastic)
	b.Box(0, 5, -1, w - 4, top - 11, depth - 6, body, M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.8)
	local fz = depth / 2 - 3
	b.Box(0, 6, fz, w - 8, top - 13, 2 * g, darken(body, 0.5), M.SmoothPlastic)
	for index = 1, 3 do
		local x = -w / 2 + 2 + (index - 0.5) * (w - 4) / 3
		local dw = (w - 4) / 3 - 1.6
		b.Box(x, 7, fz + 1.5 * g, dw, top - 16, 3 * g, lighten(body, 0.12), M.SmoothPlastic)
		b.Box(x, 11, fz + 3 * g, dw - 8, top - 24, 2 * g, lighten(body, 0.2), M.SmoothPlastic)
		House3DKit.Handle(b, x, top - 16, fz + 3 * g, math.min(14, dw * 0.5), false)
	end
	-- plan de travail en marbre, débord et chant biseauté
	House3DKit.Bevel(b, 0, top - 6, 0, w, 6, depth, 1.6, lightOf(b, rgb(248, 246, 252)), M.Marble)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
local function roundTable(b: Builder, ctx: Ctx, defaultTop: number)
	local top = ctx.TopY(1, defaultTop)
	local x0, x1 = ctx.Span(1, -44, 44)
	local w = x1 - x0
	local wood = woodOf(b, WOOD_LIGHT)
	local metal = b.Map(GREY)
	local slab = accent(b, 1, wood)
	-- pied tulipe : disque, dôme en gradins, colonne chromée à bagues
	b.Cyl(0, 0, 0, w * 0.5, 1.6, darken(metal, 0.35), M.Rubber)
	b.Cyl(0, 1.6, 0, w * 0.48, 2, darken(metal, 0.12), M.Metal).Reflectance = 0.25
	b.Cyl(0, 3.6, 0, w * 0.3, 2, metal, M.Metal).Reflectance = 0.25
	b.Cyl(0, 5.6, 0, 14, 2, metal, M.Metal).Reflectance = 0.25
	b.Cyl(0, 7.6, 0, 7, top - 14, metal, M.Metal).Reflectance = 0.3
	for _, y in ipairs({ 7.6, top - 9 }) do
		b.Cyl(0, y, 0, 9, 1.4, darken(metal, 0.2), M.Metal).Reflectance = 0.25
	end
	b.Cyl(0, top - 7.6, 0, w * 0.36, 2.6, darken(metal, 0.25), M.Metal) -- croisillon sous le plateau
	-- plateau : bord arrondi (anneau) + dessus
	b.Cyl(0, top - 5, 0, w, 5, slab, M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.8)
	b.Cyl(0, top - 5 + g, 0, w + 1.6, 5 - 2 * g, lighten(slab, 0.18), M.SmoothPlastic)
	if top > 60 then
		-- repose-pieds en anneau (8 barres dorées)
		local r = w * 0.22
		for index = 0, 7 do
			local a0, a1 = index / 8 * math.pi * 2, (index + 1) / 8 * math.pi * 2
			b.Tube(math.cos(a0) * r, top * 0.3, math.sin(a0) * r, math.cos(a1) * r, top * 0.3, math.sin(a1) * r, 2, GOLD, M.Metal).Reflectance = 0.3
		end
		for index = 0, 3 do
			local a = index / 4 * math.pi * 2 + math.pi / 8
			b.Tube(0, top * 0.3, 0, math.cos(a) * r, top * 0.3, math.sin(a) * r, 1.4, GOLD, M.Metal)
		end
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
	-- pieds cambrés fins (fuselés) + ceinture à tiroir central
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(sx * (w / 2 - 5), (top - 10) / 2, sz * (depth / 2 - 5)) * CFrame.Angles(-sz * 0.06, 0, sx * 0.06), 4.4, top - 10, 4.4, wood, M.Wood)
			b.Ball(sx * (w / 2 - 4.4), 1.6, sz * (depth / 2 - 4.4), 4, GOLD, M.Metal).Reflectance = 0.3
		end
	end
	House3DKit.Bevel(b, 0, top - 10, 0, w, 10, depth, 1.4, wood, M.Wood)
	local g = House3DKit.Gap(b, 0.8)
	b.Box(0, top - 8.6, depth / 2, w * 0.5, 6.4, 2 * g, darken(wood, 0.45), M.SmoothPlastic)
	b.Box(0, top - 7.6, depth / 2 + 1.5 * g, w * 0.5 - 1.4, 4.4, 3 * g, trim, M.Wood)
	knob(b, 0, top - 5.6, depth / 2 + 3 * g + 1.2, 3)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * w * 0.36, top - 8.2, depth / 2 + 0.75 * g, w * 0.14, 5.6, 1.5 * g, lighten(trim, 0.3), M.Wood)
	end
	-- miroir ovale sur pied, cadre en anneau, ampoules de loge autour
	local mirrorH = math.max(20, 96 - top)
	local my = top + mirrorH * 0.55
	local mz = -depth / 2 + 3
	b.Box(0, top, mz, 14, 3, 8, trim, M.SmoothPlastic)
	b.Box(0, top + 3, mz, 6, mirrorH * 0.18, 3, wood, M.Wood)
	local frame = b.CylZ(0, my, mz, mirrorH * 0.9, 3, trim, M.SmoothPlastic)
	frame.Name = "Cadre"
	b.CylZ(0, my, mz + 1, mirrorH * 0.82, 2.4, lighten(trim, 0.35), M.SmoothPlastic)
	House3DKit.Mirror(b, 0, my, mz + 2.2 + g, mirrorH * 0.74, mirrorH * 0.74, "Oval")
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2 + math.pi / 8
		local bulb = b.Ball(math.cos(a) * mirrorH * 0.43, my + math.sin(a) * mirrorH * 0.43, mz + 2.2 + g, mirrorH * 0.07, rgb(255, 244, 214))
		b.Neon(bulb)
		if index == 2 then
			b.Light(bulb, rgb(255, 236, 200), 10, 0.6)
		end
	end
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
	House3DKit.Bevel(b, 0, top - 4, 0, w + 4, 4, depth + 4, 1.4, lighten(body, 0.1), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 4, depth + 4, top)
end
R.Dresser = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 50
	local body = woodOf(b, WOOD_LIGHT)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, PINK_SOFT), 3, 0, 6)
	House3DKit.Bevel(b, 0, top - 4, 0, w + 4, 4, depth + 1.6, 1.4, lighten(body, 0.12), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 4, depth + 3, top)
end
R.DrawerCabinet = function(b, ctx)
	local top = ctx.TopY(1, 76)
	local x0, x1 = ctx.Span(1, -43, 44)
	local w, depth = x1 - x0, 44
	local body = woodOf(b, WOOD_LIGHT)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, rgb(255, 200, 220)), 4, 0, 5)
	House3DKit.Bevel(b, 0, top - 4, 0, w + 3, 4, depth + 3, 1.4, lighten(body, 0.12), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.TVStand = function(b, ctx)
	local top = ctx.TopY(1, 47)
	local x0, x1 = ctx.Span(1, -48, 48)
	local w, depth = x1 - x0, 40
	local body = woodOf(b, WOOD)
	cabinet(b, w, depth, top - 4, body, accent(b, 1, lighten(body, 0.2)), 0, 3, 5)
	House3DKit.Bevel(b, 0, top - 4, 0, w + 2, 4, depth + 2, 1.4, lighten(body, 0.1), M.Wood)
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
	-- corniche : gorge en pente + dessus biseauté
	cove(b, 0, top - 8, depth / 2, w + 5, 3, 2.3, 0, lighten(body, 0.06), M.Wood)
	cove(b, -w / 2, top - 8, 0, depth, 3, 2.3, -math.pi / 2, lighten(body, 0.06), M.Wood)
	cove(b, w / 2, top - 8, 0, depth, 3, 2.3, math.pi / 2, lighten(body, 0.06), M.Wood)
	House3DKit.Bevel(b, 0, top - 5, 0, w + 5, 5, depth + 4, 1.6, lighten(body, 0.12), M.Wood)
	-- médaillons ovales sculptés sur les portes (cœur en relief au centre)
	local g = House3DKit.Gap(b, 0.8)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * w * 0.24, top * 0.72, depth / 2 + 4 * g), 10, 13, 1.4, lighten(front, 0.3), M.Wood)
		House3DKit.Heart(b, side * w * 0.24, top * 0.72, depth / 2 + 4 * g + 0.5, 5, 0.8, lighten(front, 0.5), M.Wood)
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 5, depth + 4, top)
end
R.Bookshelf = function(b, ctx)
	local top = ctx.TopY(1, 91)
	local x0, x1 = ctx.Span(1, -42, 42)
	local w, depth = x1 - x0 + 4, 30
	local wood = woodOf(b, WOOD)
	-- fond, montants, socle en retrait, corniche biseautée
	b.Box(0, 0, -depth / 2 + 1, w - 4, top - 4, 2, darken(wood, 0.2), M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 2), 0, 0, 4, top - 4, depth, wood, M.Wood)
	end
	b.Box(0, 0, depth / 2 - 2.2, w - 8, 4, 1.2, darken(wood, 0.35), M.Wood)
	House3DKit.Bevel(b, 0, top - 4, 0, w, 4, depth, 1.2, lighten(wood, 0.06), M.Wood)
	local shelves = 3 -- (v9.6) 3 cases, comme le dessin 2D
	local colors = {}
	for index = 1, 6 do
		colors[index] = accent(b, index, ({ PINK, SKY, MINT, BUTTER, LILAC, rgb(255, 170, 120) })[index])
	end
	local caseH = (top - 4) / shelves
	for index = 0, shelves - 1 do
		local y = index * caseH
		if index > 0 then
			b.Box(0, y, 0, w - 8, 4, depth - 0.4, wood, M.Wood)
		end
		-- chant du rayon (plus clair, un peu en saillie)
		local g = House3DKit.Gap(b, 0.8)
		b.Box(0, y, depth / 2 - 0.2 + g / 2, w - 8, 4, g, lighten(wood, 0.12), M.Wood)
		-- livres aux dos variés + un objet déco au bout du rayon
		House3DKit.Books(b, -w / 2 + 5, w / 2 - 17, y + 4, 1.5, depth - 18, caseH - 7, colors, index + 1)
		local dx = w / 2 - 10
		if index == 0 then
			for pile = 0, 2 do
				b.Box(dx, y + 4 + pile * 2.6, -4, 11 - pile, 2.6, depth - 20, vary(colors[(pile + 3) % 6 + 1], pile, 0.15), M.SmoothPlastic)
			end
		elseif index == 1 then
			b.Cyl(dx, y + 4, -3, 7, 6, rgb(226, 150, 110), M.SmoothPlastic)
			b.Ball(dx, y + 12, -3, 9, LEAF, M.SmoothPlastic)
			b.Ball(dx - 2, y + 15, -2, 6, LEAF_DARK, M.SmoothPlastic)
		else
			b.Cyl(dx, y + 4, -3, 6, 2, darken(wood, 0.3), M.Wood)
			b.Ball(dx, y + 10, -3, 9, accent(b, 2, SKY), M.Glass)
		end
	end
	b.Top(1, 0, top, 0, w, depth)
	-- (v9.6) rayons devant les livres : dessus 2 (haut) .. 4 (bas), = HouseSurfaces
	for index = 0, shelves - 1 do
		b.Top(shelves + 1 - index, 0, index * (top - 4) / shelves + 4, depth / 2 - 6, w - 10, 10)
	end
	b.Footprint(w, depth, top)
end
R.StorageBox = function(b, ctx)
	local top = ctx.TopY(1, 53)
	local x0, x1 = ctx.Span(1, -36, 36)
	local w, depth = x1 - x0, 60
	local body = House3DKit.Pick(b.Pal, function(_h, s, v)
		return v > 0.4 and s > 0.1
	end, b.Map(rgb(214, 180, 140)))
	-- carton : corps, couvercle qui déborde, poignées découpées, étiquette,
	-- ruban adhésif, arêtes plus sombres
	b.Box(0, 0, 0, w, top - 6, depth, body, M.Cardboard)
	b.Box(0, top - 6, 0, w + 3, 6, depth + 3, lighten(body, 0.1), M.Cardboard)
	local g = House3DKit.Gap(b, 0.6)
	b.Box(0, top - 0.4, 0, 8, 0.4 + g, depth + 3 + 2 * g, rgb(222, 200, 150), M.SmoothPlastic)
	b.Box(0, top - 6.4, depth / 2 + 1.5 + g / 2, 8, 6.4, g, rgb(222, 200, 150), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (w / 2 + g / 2 - 0.4), top - 22, 0, g + 0.8, 6, 16, darken(body, 0.55), M.SmoothPlastic)
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * (w / 2 + g / 2 - 0.8), 0, sz * (depth / 2 + g / 2 - 0.8), 1.6 + g, top - 6, 1.6 + g, darken(body, 0.12), M.Cardboard)
		end
	end
	b.Box(-w * 0.18, top - 26, depth / 2 + g / 2 - 0.3, 20, 13, g + 0.6, WHITE, M.SmoothPlastic)
	for line = 0, 2 do
		b.Box(-w * 0.18 - 2, top - 17 - line * 3.2, depth / 2 + 1.5 * g, 14 - line * 3, 1, g, GREY_DARK, M.SmoothPlastic)
	end
	b.Box(w * 0.2, top - 18, depth / 2 + g / 2 - 0.3, 16, 6, g + 0.6, darken(body, 0.35))
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.Suitcase = function(b, _ctx)
	local body = accent(b, 1, PINK)
	-- coque aux arêtes arrondies, nervures, fermeture éclair, coins renforcés
	b.Round(0, 5, 0, 70, 61, 30, 5, body, M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.8)
	for _, x in ipairs({ -22, -8, 8, 22 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(x, 9, sz * 15, 3, 53, 2 * g, lighten(body, 0.12), M.SmoothPlastic)
		end
	end
	b.Box(0, 34, 0, 70 + 4 * g, 1.6, 30 + 4 * g, darken(body, 0.45), M.Fabric) -- fermeture
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ 7, 63 }) do
			b.Box(sx * (32.5 + g / 2), sy - (sy < 30 and 3 or 0), 0, 5 + g, 4, 30 + 2 * g, darken(body, 0.5), M.Rubber)
		end
	end
	-- poignée télescopique (rentrée) + poignée de côté + étiquette
	for _, x in ipairs({ -9, 9 }) do
		b.Box(x, 66, -8, 2.4, 2, 2.4, CHROME_METAL, M.Metal).Reflectance = 0.3
	end
	b.Box(0, 66, -8, 22, 4, 5, INK, M.Rubber)
	b.Box(0, 66, 6, 14, 3, 4, INK, M.Leather)
	b.Box(35 + g / 2 - 1, 30, 0, 2 + g, 3, 12, INK, M.Leather)
	b.BoxR(CFrame.new(-26, 58, 16) * CFrame.Angles(0, 0, 0.2), 8, 10, 0.8, lighten(accent(b, 2, BUTTER), 0.2), M.SmoothPlastic)
	-- roulettes pivotantes
	for _, x in ipairs({ -28, 28 }) do
		for _, z in ipairs({ -9, 9 }) do
			b.Box(x, 3, z, 5, 2.4, 5, GREY_DARK, M.Metal)
			b.CylX(x, 2.4, z, 4.8, 2.6, INK, M.Rubber)
		end
	end
	b.Top(1, 0, 70, 0, 70, 30)
	b.Footprint(70, 30, 72)
end

-- SIÈGES -----------------------------------------------------------------

-- (v9.8) Chaise en bois : pieds avant fuselés, montants arrière d'un seul
-- tenant (légèrement inclinés), ceinture, entretoises, assise biseautée,
-- galette passepoilée (chaise rembourrée) ou barreaux (chaise en bois)
local function chair(b: Builder, ctx: Ctx, seatDefault: number, backH: number, width: number, depth: number, padColor: Color3?)
	local seat = ctx.TopY(1, seatDefault)
	local wood = woodOf(b, WOOD)
	local legC = darken(wood, 0.1)
	local fx, fz = width / 2 - 4, depth / 2 - 4
	local h = seat + backH
	local tilt = 0.06
	local function backZ(y: number): number
		return -fz - 1 - (y - h / 2) * tilt
	end
	for _, sx in ipairs({ -1, 1 }) do
		House3DKit.Leg(b, sx * fx, 0, fz, 5.2, seat - 5, legC, M.Wood, darken(legC, 0.45))
		b.BoxR(CFrame.new(sx * fx, h / 2, backZ(h / 2)) * CFrame.Angles(-tilt, 0, 0), 5, h, 5, legC, M.Wood)
		-- entretoise basse (côté)
		b.Box(sx * fx, seat * 0.22, -1, 2.4, 2.6, 2 * fz - 6, legC, M.Wood)
	end
	b.Box(0, seat * 0.3, fz, 2 * fx - 5, 2.6, 2.4, legC, M.Wood)
	-- ceinture sous l'assise
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, seat - 10, sz * fz, 2 * fx - 5.2, 5, 2.2, wood, M.Wood)
	end
	House3DKit.Bevel(b, 0, seat - 5, 0.5, width, 5, depth - 1, 1.4, wood, M.Wood)
	-- dossier : traverse haute cintrée
	local railY = h - 7
	b.BoxR(CFrame.new(0, railY + 3.5, backZ(railY + 3.5)) * CFrame.Angles(-tilt, 0, 0), 2 * fx - 4.8, 7, 3.4, wood, M.Wood)
	if padColor then
		House3DKit.SeatCushion(b, 0, seat - 0.4, 1.5, width - 7, 2.6, depth - 9, padColor, darken(padColor, 0.25))
		-- dossier rembourré capitonné
		local py = seat + (railY - seat) / 2
		House3DKit.PillowR(b, CFrame.new(0, py, backZ(py) + 1.2) * CFrame.Angles(-tilt, 0, 0), 2 * fx - 6, railY - seat - 4, 4, padColor, M.Fabric)
		for _, bx in ipairs({ -0.22, 0.22 }) do
			b.Ball(bx * (2 * fx - 6), py, backZ(py) + 3.2, 1.8, darken(padColor, 0.25), M.Fabric)
		end
	else
		-- 3 barreaux + traverse basse du dossier
		b.BoxR(CFrame.new(0, seat + 3, backZ(seat + 3)) * CFrame.Angles(-tilt, 0, 0), 2 * fx - 4.8, 3, 2.6, wood, M.Wood)
		for _, bx in ipairs({ -0.25, 0, 0.25 }) do
			local sy = (seat + 4.5 + railY) / 2
			b.BoxR(CFrame.new(bx * (2 * fx), sy, backZ(sy)) * CFrame.Angles(-tilt, 0, 0), 3, railY - seat - 4.5, 2, lighten(wood, 0.05), M.Wood)
		end
	end
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
	-- patins courbes (arc en 5 segments) + accoudoirs
	for _, side in ipairs({ -1, 1 }) do
		local r, cy = 120, 123
		local prev = nil
		for index = 0, 5 do
			local a = -0.36 + index * 0.144
			local p = { side * 25, cy - math.cos(a) * r, math.sin(a) * r }
			if prev then
				b.Tube(prev[1], prev[2], prev[3], p[1], p[2], p[3], 3.4, darken(wood, 0.2), M.Wood)
			end
			prev = p
		end
		local seat = ctx.TopY(1, 43)
		b.Box(side * 27, seat + 16, -2, 4, 3, 36, darken(wood, 0.05), M.Wood)
		b.Box(side * 27, seat, 14, 3, 16, 3, darken(wood, 0.1), M.Wood)
	end
end
-- (v9.8) Fauteuil gamer "baquet" : piétement étoile à roulettes, vérin chromé,
-- assise baquet à bourrelets, dossier à ailes, coussins lombaire et de tête,
-- accoudoirs réglables, surpiqûres contrastées
local function racingChair(b: Builder, seat: number, main: Color3, dark: Color3, stitch: Color3)
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2 + math.pi / 2
		local cx, cz = math.cos(angle), math.sin(angle)
		b.BoxR(CFrame.new(cx * 11, 4, cz * 11) * CFrame.Angles(0, -angle, 0) * CFrame.Angles(0, 0, -0.08), 24, 3, 4.4, dark, M.Metal)
		b.Cyl(cx * 23, 1.4, cz * 23, 2, 2.4, GREY, M.Metal)
		b.CylX(cx * 23, 1.6, cz * 23, 3.4, 3, INK, M.Rubber)
	end
	b.Cyl(0, 2.4, 0, 9, 4, dark, M.Metal)
	local lift = b.Cyl(0, 6, 0, 4.4, seat - 18, CHROME_METAL, M.Metal)
	lift.Reflectance = 0.35
	b.Cyl(0, 6, 0, 6, 8, INK, M.Plastic)
	b.Box(0, seat - 13, -2, 26, 3, 26, dark, M.Metal) -- mécanisme
	-- assise baquet
	House3DKit.SeatCushion(b, 0, seat - 10, 3, 44, 10, 46, main, stitch)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 24, seat - 3.5, 3) * CFrame.Angles(0, 0, side * 0.35), 7, 12, 44, dark, M.Leather)
	end
	-- dossier à ailes
	local backCF = CFrame.new(0, seat + 26, -22) * CFrame.Angles(-0.12, 0, 0)
	b.BoxR(backCF, 40, 62, 8, main, M.Leather)
	local g = House3DKit.Gap(b, 0.6)
	b.BoxR(backCF * CFrame.new(0, 0, 4 + g / 2), 3, 54, g, stitch, M.Leather)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(backCF * CFrame.new(side * 22, -4, 2) * CFrame.Angles(0, side * 0.45, 0), 8, 50, 10, dark, M.Leather)
		b.BoxR(backCF * CFrame.new(side * 12, 0, 4 + g / 2), 1, 54, g, stitch, M.Leather)
		b.BoxR(backCF * CFrame.new(side * 14, 26, 0), 8, 5, 8 + 2 * g, dark, M.Leather) -- passage de harnais
	end
	House3DKit.PillowR(b, backCF * CFrame.new(0, 22, 6), 18, 9, 5, dark, M.Fabric) -- coussin de tête
	House3DKit.PillowR(b, backCF * CFrame.new(0, -20, 6), 26, 9, 5, dark, M.Fabric) -- coussin lombaire
	-- accoudoirs réglables
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 27, seat - 10, -2, 3, 12, 6, dark, M.Metal)
		b.Box(side * 27, seat + 2, 2, 7, 3, 20, INK, M.Rubber)
	end
end
R.GamingChair = function(b, ctx)
	local seat = ctx.TopY(1, 37)
	local main = accent(b, 1, PINK)
	local dark = darken(accent(b, 2, INK), 0.2)
	racingChair(b, seat, main, dark, lighten(main, 0.5))
	b.Top(1, 0, seat, 4, 44, 36)
	b.Footprint(56, 56, seat + 60)
end
R.BarStool = function(b, ctx)
	local seat = ctx.TopY(1, 74)
	local color = accent(b, 1, PINK)
	-- socle lesté (bord caoutchouc), colonne chromée, repose-pieds, galette capitonnée
	b.Cyl(0, 0, 0, 36, 1.4, INK, M.Rubber)
	b.Cyl(0, 1.4, 0, 34, 2.4, GREY_DARK, M.Metal).Reflectance = 0.25
	b.Cyl(0, 3.8, 0, 16, 2, GREY, M.Metal).Reflectance = 0.25
	b.Cyl(0, 5.8, 0, 6, seat - 16, CHROME_METAL, M.Metal).Reflectance = 0.35
	b.Cyl(0, seat * 0.35, 0, 8, 3, GREY_DARK, M.Metal)
	for index = 0, 7 do
		local a0, a1 = index / 8 * math.pi * 2, (index + 1) / 8 * math.pi * 2
		b.Tube(math.cos(a0) * 14, seat * 0.35 + 1.5, math.sin(a0) * 14, math.cos(a1) * 14, seat * 0.35 + 1.5, math.sin(a1) * 14, 2.2, GOLD, M.Metal).Reflectance = 0.3
	end
	for index = 0, 3 do
		local a = index / 4 * math.pi * 2
		b.Tube(0, seat * 0.35 + 1.5, 0, math.cos(a) * 14, seat * 0.35 + 1.5, math.sin(a) * 14, 1.4, GOLD, M.Metal)
	end
	b.Cyl(0, seat - 10.2, 0, 30, 2.4, GREY_DARK, M.Metal)
	b.Cyl(0, seat - 8, 0, 44, 6, color, M.Leather)
	b.Cyl(0, seat - 8 - House3DKit.Gap(b, 0.6), 0, 46, 1.4 + House3DKit.Gap(b, 0.6), darken(color, 0.3), M.Leather) -- passepoil
	b.Egg(0, seat - 2.4, 0, 44, 4.8, 44, color, M.Leather)
	b.Ball(0, seat - 0.2, 0, 3, darken(color, 0.25), M.Leather)
	b.Top(1, 0, seat, 0, 36, 36)
	b.Footprint(46, 46, seat)
end
R.MushroomStool = function(b, ctx)
	local seat = ctx.TopY(1, 85)
	local cap = accent(b, 1, rgb(255, 110, 120))
	local stem = lightOf(b, CREAM)
	-- pied renflé, anneau (jupe), lamelles sous le chapeau, chapeau bombé à pois
	b.Cyl(0, 0, 0, 40, seat * 0.12, darken(stem, 0.06), M.SmoothPlastic)
	b.Egg(0, seat * 0.14, 0, 42, seat * 0.2, 42, stem, M.SmoothPlastic)
	b.Cyl(0, seat * 0.1, 0, 32, seat * 0.5, stem, M.SmoothPlastic)
	b.Cyl(0, seat * 0.42, 0, 38, 3, lighten(stem, 0.3), M.SmoothPlastic)
	b.Cyl(0, seat * 0.44, 0, 76, seat * 0.12, darken(cap, 0.35), M.SmoothPlastic) -- lamelles
	b.Cyl(0, seat * 0.56, 0, 86, seat * 0.16, cap, M.SmoothPlastic)
	b.Egg(0, seat * 0.72, 0, 86, seat * 0.56, 86, cap, M.SmoothPlastic)
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2
		local r = 30
		b.EggR(CFrame.new(math.cos(angle) * r, seat * 0.915, math.sin(angle) * r) * CFrame.Angles(math.sin(angle) * 0.75, 0, -math.cos(angle) * 0.75), 13, 3, 11, WHITE, M.SmoothPlastic)
	end
	b.EggR(CFrame.new(0, seat - 0.6, 0), 14, 2, 14, WHITE, M.SmoothPlastic)
	b.Top(1, 0, seat, 0, 50, 50)
	b.Footprint(86, 86, seat)
end
R.FloorCushion = function(b, ctx)
	local seat = ctx.TopY(1, 51)
	local color = accent(b, 1, PINK)
	-- pouf rond : flanc, dessus bombé, passepoils, capiton central, poignée
	b.Cyl(0, 0, 0, 86, seat * 0.72, color, M.Fabric)
	b.Egg(0, seat * 0.1, 0, 90, seat * 0.26, 90, darken(color, 0.04), M.Fabric)
	b.Egg(0, seat * 0.72, 0, 86, seat * 0.56, 86, lighten(color, 0.08), M.Fabric)
	b.Cyl(0, seat * 0.7, 0, 88, 1.6, darken(color, 0.25), M.Fabric)
	b.Cyl(0, seat * 0.16, 0, 90, 1.6, darken(color, 0.25), M.Fabric)
	b.Ball(0, seat - 1.6, 0, 7, darken(color, 0.25), M.Fabric)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.Tube(0, seat - 2, 0, math.cos(a) * 24, seat - 4.5, math.sin(a) * 24, 1.2, darken(color, 0.12), M.Fabric)
	end
	b.Box(0, seat * 0.4, 43.6, 14, 4, 2, darken(color, 0.3), M.Fabric)
	b.Top(1, 0, seat, 0, 60, 60)
	b.Footprint(90, 90, seat)
end
R.Beanbag = function(b, _ctx)
	local color = accent(b, 1, LILAC)
	-- pouf poire : grosse goutte affaissée, creux d'assise, dossier relevé,
	-- coutures en relief, poignée sur le dessus
	b.Egg(0, 24, 2, 92, 48, 86, color, M.Fabric)
	b.EggR(CFrame.new(0, 50, -18) * CFrame.Angles(-0.35, 0, 0), 70, 50, 40, darken(color, 0.05), M.Fabric)
	b.Egg(0, 44, 12, 56, 12, 46, lighten(color, 0.12), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.Egg(side * 32, 30, 8, 26, 30, 50, darken(color, 0.03), M.Fabric)
		b.EggR(CFrame.new(side * 22, 34, 8) * CFrame.Angles(0, 0, side * 0.6), 2, 40, 58, darken(color, 0.22), M.Fabric)
	end
	b.EggR(CFrame.new(0, 26, 2), 93, 3, 87, darken(color, 0.2), M.Fabric)
	b.Egg(0, 5, 2, 80, 10, 74, darken(color, 0.1), M.Fabric)
	b.Tube(-6, 73, -30, 6, 73, -30, 3, darken(color, 0.3), M.Fabric)
	b.Ball(26, 20, 40, 5, lighten(color, 0.4), M.Fabric)
	b.Top(1, 0, 50, 10, 50, 40)
	b.Seat(0, 48, 10, 50, 40)
	b.Footprint(92, 86, 76)
end
-- (v9.8) Canapé : pieds fuselés, socle rembourré au bord roulé, galettes
-- d'assise passepoilées, coussins de dossier moelleux inclinés, accoudoirs
-- roulés à plastron, coussins déco
local function sofa(b: Builder, ctx: Ctx, seatDefault: number, width: number, cushions: number)
	local seat = ctx.TopY(1, seatDefault)
	local main = accent(b, 1, PINK)
	local depth = 56
	local wood = woodOf(b, WOOD_DARK)
	local frame = darken(main, 0.08)
	local pipe = darken(main, 0.28)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			House3DKit.Leg(b, sx * (width / 2 - 8), 0, sz * (depth / 2 - 8), 5.6, 7.4, wood, M.Wood, BRASS)
		end
	end
	-- socle (sous les galettes) au bord avant roulé
	b.Box(0, 7, -2, width - 4, seat - 17, depth - 8, frame, M.Fabric)
	b.CylX(0, 7 + (seat - 17) / 2, depth / 2 - 6, seat - 17, width - 4, frame, M.Fabric)
	-- galettes d'assise
	local cw = (width - 20) / cushions
	for index = 1, cushions do
		local x = -width / 2 + 10 + (index - 0.5) * cw
		House3DKit.SeatCushion(b, x, seat - 10, 3, cw - 1, 10, depth - 12, vary(main, index, 0.03), pipe)
	end
	-- dossier (structure) + boudin sur le dessus
	local g = House3DKit.Gap(b, 0.8)
	b.Box(0, 7 - g, -depth / 2 + 4, width - 2, seat + 19 + g, 8, darken(main, 0.12), M.Fabric)
	b.CylX(0, seat + 26, -depth / 2 + 4, 8, width - 2 + 2 * g, darken(main, 0.1), M.Fabric)
	-- coussins de dossier moelleux, inclinés
	for index = 1, cushions do
		local x = -width / 2 + 10 + (index - 0.5) * cw
		House3DKit.PillowR(b, CFrame.new(x, seat + 12, -depth / 2 + 13) * CFrame.Angles(-0.2, 0, 0), cw - 2, 27, 11, vary(main, index + 5, 0.03), M.Fabric)
	end
	-- accoudoirs roulés à plastron passepoilé
	for _, side in ipairs({ -1, 1 }) do
		local ax = side * (width / 2 - 5)
		b.Box(ax, 7 - 2 * g, 0, 10, seat - 1 + 2 * g, depth - 2, darken(main, 0.04), M.Fabric)
		b.CylZ(ax, seat + 5, 0, 12, depth - 2 + 2 * g, lighten(main, 0.06), M.Fabric)
		b.Box(ax, 8, depth / 2 - 1 + g / 2, 9, seat - 4, g, lighten(main, 0.02), M.Fabric)
		b.CylZ(ax, seat + 5, depth / 2 - 1 + 1.5 * g, 13, g, pipe, M.Fabric)
	end
	-- coussins déco (un de chaque côté, passepoilés)
	local pillow = accent(b, 2, BUTTER)
	for _, side in ipairs({ -1, 1 }) do
		if cushions > 1 or side < 0 then
			local cf = CFrame.new(side * (width / 2 - 20), seat + 9, -depth / 2 + 19) * CFrame.Angles(-0.35, side * -0.25, side * -0.12)
			House3DKit.PillowR(b, cf, 17, 17, 6, side < 0 and pillow or lighten(pillow, 0.35), M.Fabric)
			b.Ball(side * (width / 2 - 20), seat + 9.4, -depth / 2 + 22.2, 2, darken(pillow, 0.3), M.Fabric)
		end
	end
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
	-- pied étoile chromé, coquille brillante à liseré, coussin moelleux intérieur
	b.Cyl(0, 0, 0, 46, 1.4, INK, M.Rubber)
	b.Cyl(0, 1.4, 0, 44, 3, GREY_DARK, M.Metal).Reflectance = 0.3
	b.Cyl(0, 4.4, 0, 6, seat - 14, CHROME_METAL, M.Metal).Reflectance = 0.35
	local shellPart = b.Ball(0, seat + 18, -6, 80, shell, M.SmoothPlastic)
	shellPart.Reflectance = 0.08
	b.EggR(CFrame.new(0, seat + 18, 12) * CFrame.Angles(0.2, 0, 0), 76, 70, 18, darken(shell, 0.12), M.SmoothPlastic)
	b.Ball(0, seat + 16, 10, 62, pad, M.Fabric)
	House3DKit.SeatCushion(b, 0, seat - 6, 12, 50, 6, 30, pad, darken(pad, 0.25))
	House3DKit.PillowR(b, CFrame.new(0, seat + 22, 14) * CFrame.Angles(-0.2, 0, 0), 30, 18, 7, lighten(pad, 0.2), M.Fabric)
	b.Top(1, 0, seat, 14, 40, 26)
	b.Footprint(80, 80, seat + 58)
end
R.GardenBench = function(b, ctx)
	local seat = ctx.TopY(1, 41)
	local wood = woodOf(b, WOOD)
	local metal = b.Map(rgb(90, 90, 110))
	-- flancs en fonte (pied avant, montant arrière incliné, accoudoir à volute)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 44
		b.Box(x, 0, 14, 4, seat - 3, 4, metal, M.Metal)
		b.BoxR(CFrame.new(x, (seat + 34) / 2, -12) * CFrame.Angles(-0.15, 0, 0), 4, seat + 34, 4, metal, M.Metal)
		b.Box(x, seat - 6, 0, 4, 3, 34, metal, M.Metal)
		b.Box(x, seat + 12, 2, 4.6, 3, 26, metal, M.Metal)
		b.Tube(x, seat - 3, 14, x, seat + 12, 14, 3, metal, M.Metal)
		b.CylX(x, seat + 13.5, 15, 6, 5, metal, M.Metal)
		b.Box(x, 0, 14, 6, 1.6, 6, darken(metal, 0.3), M.Metal)
		b.Box(x, 0, -17, 6, 1.6, 6, darken(metal, 0.3), M.Metal)
	end
	for index = 0, 3 do
		b.Box(0, seat - 3, -14 + index * 9.5, 88, 3, 8, vary(wood, index, 0.08), M.WoodPlanks)
	end
	for index = 0, 2 do
		b.BoxR(CFrame.new(0, seat + 8 + index * 9, -19 - index * 1.2) * CFrame.Angles(-0.15, 0, 0), 88, 7, 3, vary(wood, index + 7, 0.08), M.WoodPlanks)
	end
	-- vis de fixation des lattes
	for index = 0, 3 do
		for _, side in ipairs({ -1, 1 }) do
			b.Cyl(side * 40, seat - 0.2, -14 + index * 9.5, 1.2, 0.6, GREY_DARK, M.Metal)
		end
	end
	b.Top(1, 0, seat, 0, 80, 30)
	b.Footprint(92, 40, seat + 34)
end

-- LITS ---------------------------------------------------------------------

-- (v9.8) Oreiller posé à plat, relevé contre la tête de lit (x = vers le pied)
local function bedPillow(b: Builder, x: number, y: number, z: number, lenX: number, widthZ: number, thick: number, color: Color3, lift: number)
	House3DKit.PillowR(b, CFrame.new(x, y, z) * CFrame.Angles(0, 0, -lift) * CFrame.Angles(math.pi / 2, 0, 0), lenX, widthZ, thick, color, M.Fabric)
end

-- (v9.8) Lit : pieds tournés, cadre, matelas aux bords roulés passepoilé,
-- tête de lit capitonnée entre deux montants à pommeaux, pied de lit,
-- couette qui retombe (bords arrondis, ourlet, piqûres), revers du drap,
-- plaid au pied, oreillers moelleux + coussin déco
local function bed(b: Builder, ctx: Ctx, topDefault: number, width: number, depth: number)
	local top = ctx.TopY(1, topDefault)
	local wood = woodOf(b, WOOD_LIGHT)
	local blanket = accent(b, 1, PINK)
	local sheet = lightOf(b, WHITE)
	local frameTop = top - 12
	local g = House3DKit.Gap(b, 0.8)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			House3DKit.Leg(b, sx * (width / 2 - 5), 0, sz * (depth / 2 - 4), 5.6, frameTop * 0.45 + 0.5, darken(wood, 0.1), M.Wood, darken(wood, 0.45))
		end
	end
	b.Box(0, frameTop * 0.45, 0, width - 8, frameTop * 0.55, depth - 2 * g, wood, M.Wood)
	House3DKit.SeatCushion(b, 1, frameTop, 0, width - 14, 12, depth - 4, sheet, darken(sheet, 0.12))
	-- tête de lit (gauche) : montants, panneau, capiton, boudin
	local hx = -width / 2 + 3
	local headColor = lighten(blanket, 0.25)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(hx, 0, sz * (depth / 2 - 3), 6, top + 27, 6, darken(wood, 0.05), M.Wood)
		local finial = b.Ball(hx, top + 29, sz * (depth / 2 - 3), 6, GOLD, M.Metal)
		finial.Reflectance = 0.25
	end
	b.Box(hx, frameTop * 0.45, 0, 5, top + 24 - frameTop * 0.45, depth - 12, wood, M.Wood)
	House3DKit.PillowR(b, CFrame.new(hx + 4, top + 12, 0) * CFrame.Angles(0, math.pi / 2, 0), depth - 16, 22, 4, headColor, M.Fabric)
	for _, bz in ipairs({ -0.25, 0, 0.25 }) do
		for _, by in ipairs({ top + 7, top + 17 }) do
			b.Ball(hx + 6.4, by, bz * (depth - 16), 1.8, darken(headColor, 0.25), M.Fabric)
		end
	end
	b.CylZ(hx, top + 26, 0, 7, depth - 6, lighten(wood, 0.1), M.Wood)
	-- pied de lit (droite)
	b.Box(width / 2 - 3, 0, 0, 6, top + 6, depth, wood, M.Wood)
	b.CylZ(width / 2 - 3, top + 6, 0, 7, depth + 2 * g, lighten(wood, 0.1), M.Wood)
	-- couette : bloc qui enveloppe le matelas, bords arrondis, ourlet, piqûres
	local x0, x1 = -width * 0.26, width / 2 - 7
	local len = x1 - x0
	local xc = (x0 + x1) / 2
	b.Box(xc, frameTop - 5, 0, len, top + 1.6 - (frameTop - 5), depth + 2 * g, blanket, M.Fabric)
	for _, sz in ipairs({ -1, 1 }) do
		b.CylX(xc, top + 0.2, sz * (depth / 2 + g - 1.2), 2.8, len, blanket, M.Fabric)
		b.Box(xc, frameTop - 4.4, sz * (depth / 2 + 1.5 * g), len - 0.4, 2, g, darken(blanket, 0.2), M.Fabric)
	end
	for _, qx in ipairs({ 0.3, 0.62 }) do
		b.Box(x0 + len * qx, top + 1.6, 0, 1, g, depth - 4, lighten(blanket, 0.25), M.Fabric)
	end
	-- revers du drap (rouleau blanc en tête de couette)
	b.CylZ(x0, top + 1, 0, 5.2, depth + 2 * g + 1, sheet, M.Fabric)
	-- plaid tricoté au pied
	local throw = accent(b, 2, lighten(blanket, 0.45))
	b.Box(x1 - 9, frameTop - 3, 0, 12, top + 1.6 + g - (frameTop - 3), depth + 4 * g, throw, M.Fabric)
	for _, tx in ipairs({ -4, 0, 4 }) do
		b.Box(x1 - 9 + tx, top + 1.6 + g, 0, 1, g, depth + 4 * g, darken(throw, 0.12), M.Fabric)
	end
	-- oreillers + coussin déco
	local n = depth > 60 and 2 or 1
	for index = 1, n do
		local z = n == 1 and 0 or (index == 1 and -depth * 0.22 or depth * 0.22)
		bedPillow(b, -width / 2 + 16, top + 4.5, z, 18, depth / n - 8, 7, sheet, 0.4)
	end
	House3DKit.PillowR(b, CFrame.new(-width / 2 + 22, top + 7, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(-0.35, 0, 0), 14, 12, 4, accent(b, 2, BUTTER), M.Fabric)
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
	-- colonnes tournées à bagues et pommeaux dorés
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local px, pz = sx * 34, sz * 29
			b.Box(px, 0, pz, 6, 8, 6, darken(wood, 0.08), M.Wood)
			b.Cyl(px, 8, pz, 4, 86, wood, M.Wood)
			for _, ry in ipairs({ 30, 60 }) do
				b.Cyl(px, ry, pz, 5.4, 2, lighten(wood, 0.12), M.Wood)
			end
			local knobPart = b.Ball(px, 99, pz, 6, GOLD, M.Metal)
			knobPart.Reflectance = 0.3
		end
	end
	-- ciel de lit : cadre + tissu + lambrequins festonnés
	b.Box(0, 94, 0, 72, 3, 62, drape, M.Fabric)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, 83, sz * 30, 72, 11, 1.2, drape, M.Fabric)
		for index = 0, 5 do
			b.EggR(CFrame.new(-30 + index * 12, 83, sz * 30), 12, 6, 1.2, drape, M.Fabric)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 35.4, 85, 0, 1.2, 9, 60, drape, M.Fabric)
	end
	-- rideaux plissés noués aux colonnes (devant et derrière)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			for fold = 0, 2 do
				local fx = sx * (34 - 4 - fold * 3.2)
				b.Tube(fx, 94, sz * 30.6, sx * 32, 60, sz * 30.6, 3.2, lighten(drape, 0.08 * fold), M.Fabric)
				b.Tube(sx * 32, 60, sz * 30.6, fx + sx * 1.5, 22, sz * 30.6, 3.4, lighten(drape, 0.08 * fold), M.Fabric)
			end
			b.Ball(sx * 32, 60, sz * 31.4, 4, accent(b, 1, PINK), M.Fabric)
		end
	end
end
R.CloudBed = function(b, ctx)
	local top = ctx.TopY(1, 45)
	local cloud = lightOf(b, WHITE)
	local blanket = accent(b, 1, SKY)
	-- nuage : grosses boules variées tout autour, matelas passepoilé, couette
	-- matelassée semée d'étoiles, oreillers-nuages
	for index = 0, 6 do
		local x = -42 + index * 14
		b.Ball(x, 16, 0, 34 + (index % 2) * 6, index % 2 == 0 and cloud or rgb(236, 240, 255))
		b.Ball(x + 7, 12 + (index % 3) * 2, 20, 18 + (index % 2) * 4, vary(cloud, index, 0.04))
		b.Ball(x - 5, 12 + (index % 2) * 3, -20, 18, vary(rgb(236, 240, 255), index, 0.03))
	end
	b.Box(0, 10, 0, 84, top - 22, 56, cloud, M.Fabric)
	House3DKit.SeatCushion(b, 0, top - 12, 0, 80, 11, 54, WHITE, rgb(210, 226, 255))
	b.Box(8, top - 10, 0, 60, 11, 55 + 2 * House3DKit.Gap(b, 0.8), blanket, M.Fabric)
	b.CylZ(-22, top, 0, 5, 56 + 2 * House3DKit.Gap(b, 0.8), WHITE, M.Fabric)
	for index = 0, 4 do
		b.EggR(CFrame.new(-12 + index * 10, top + 1, (index % 2 == 0) and -12 or 12), 5, 1.2, 5, BUTTER, M.SmoothPlastic)
	end
	b.Ball(-40, top + 6, 0, 28, cloud)
	b.Ball(-30, top + 14, 0, 22, cloud)
	b.Ball(-32, top + 3, 0, 16, WHITE, M.Fabric)
	b.Ball(-44, top + 10, 14, 18, vary(cloud, 3, 0.04))
	b.Ball(-44, top + 10, -14, 18, vary(cloud, 4, 0.04))
	b.Top(1, 4, top, 0, 70, 50)
	b.Footprint(96, 60, top + 20)
end
R.LoftBed = function(b, ctx)
	local top = ctx.TopY(1, 77)
	local desk = ctx.TopY(2, 27)
	local wood = woodOf(b, WOOD)
	local blanket = accent(b, 1, LILAC)
	local dark = darken(wood, 0.15)
	-- montants, longerons, garde-corps à barreaux
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 36, 0, sz * 22, 5, top + 14, 5, wood, M.Wood)
			b.Ball(sx * 36, top + 15, sz * 22, 5.4, lighten(wood, 0.1), M.Wood)
		end
	end
	b.Box(0, top - 12, 0, 76, 6, 48, wood, M.Wood)
	House3DKit.SeatCushion(b, 0, top - 6, 0, 70, 6, 44, WHITE, rgb(220, 214, 236))
	b.Box(6, top - 4, 0, 56, 5, 45 + 2 * House3DKit.Gap(b, 0.8), blanket, M.Fabric)
	b.CylZ(-22, top + 0.6, 0, 3.4, 45 + 2 * House3DKit.Gap(b, 0.8), WHITE, M.Fabric)
	bedPillow(b, -26, top + 1.5, 0, 14, 30, 5, WHITE, 0.35)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, top + 9, sz * 22, 72, 3, 2.4, wood, M.Wood)
		for index = -3, 3 do
			b.Box(index * 10, top - 6, sz * 22, 1.8, 15, 1.8, dark, M.Wood)
		end
	end
	b.Box(0, top + 4, 22, 76, 4, 2, wood, M.Wood)
	-- guirlande lumineuse sur le garde-corps avant
	for index = 0, 6 do
		local bulb = b.Ball(-30 + index * 10, top + 8.4 - (index % 2) * 1.2, 23.6, 2.2, ({ rgb(255, 200, 120), rgb(255, 170, 200), rgb(190, 220, 255) })[index % 3 + 1])
		b.Neon(bulb)
	end
	-- bureau dessous (plateau biseauté + petit tiroir)
	House3DKit.Bevel(b, -14, desk - 4, 0, 44, 4, 40, 1.2, lighten(wood, 0.15), M.Wood)
	b.Box(-14, desk - 9, 18, 20, 5, 3, lighten(wood, 0.05), M.Wood)
	House3DKit.Handle(b, -14, desk - 6.5, 19.5, 7, false)
	-- échelle (montants + barreaux ronds)
	for _, x in ipairs({ 30, 42 }) do
		b.Box(x, 0, 26, 3, top, 3, dark, M.Wood)
	end
	for index = 1, 5 do
		b.CylX(36, index * top / 6, 26, 2.6, 12, dark, M.Wood)
	end
	b.Top(1, 0, top, 0, 60, 40)
	b.Top(2, -14, desk, 0, 40, 36)
	b.Footprint(80, 56, top + 14)
end
R.PetBed = function(b, _ctx)
	local color = accent(b, 1, PINK)
	-- panier rond : fond, boudin tout autour, coussin moelleux, empreinte de patte
	b.Cyl(0, 0, 0, 86, 6, darken(color, 0.15), M.Fabric)
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 34, 12, math.sin(a) * 34) * CFrame.Angles(0, -a, 0), 16, 20, 22, vary(color, index, 0.04), M.Fabric)
	end
	b.Egg(0, 10, 0, 70, 12, 70, lighten(color, 0.4), M.Fabric)
	local paw = lighten(color, 0.15)
	b.EggR(CFrame.new(0, 15.6, 4), 12, 1.4, 10, paw, M.Fabric)
	for index = -1, 1 do
		b.EggR(CFrame.new(index * 7, 15.4, -5 + math.abs(index) * 2), 4.6, 1.4, 5, paw, M.Fabric)
	end
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
	local g = House3DKit.Gap(b, 0.8)
	-- frigo rétro : coins arrondis, socle à grille, deux portes à joints,
	-- poignées chromées, distributeur d'eau, magnets et petit mot
	b.Box(0, 0, -1, w - 6, 4, depth - 6, darken(body, 0.45), M.SmoothPlastic)
	for index = 0, 3 do
		b.Box(0, 0.8 + index * 0.8, depth / 2 - 3.6, w - 14, 0.4, g, darken(body, 0.6), M.Metal)
	end
	b.Round(0, 4, 0, w, top - 4, depth, 4, body, M.SmoothPlastic)
	local split = top * 0.62
	local doorColor = lighten(body, 0.05)
	b.Box(0, 5, depth / 2 + g / 2, w - 5, split - 6, g, doorColor, M.SmoothPlastic)
	b.Box(0, split + 1, depth / 2 + g / 2, w - 5, top - split - 2, g, doorColor, M.SmoothPlastic)
	b.Box(0, split - 1, depth / 2 + g / 2, w - 5, 2, g * 0.5, darken(body, 0.35), M.Rubber)
	for _, y in ipairs({ top * 0.3, top * 0.8 }) do
		House3DKit.Handle(b, w / 2 - 7, y, depth / 2 + g, 18, true)
	end
	-- distributeur (porte du haut)
	b.Box(-w * 0.18, split + 8, depth / 2 + 1.5 * g, 14, 18, g, rgb(60, 66, 80), M.SmoothPlastic)
	local screen = b.Box(-w * 0.18, split + 22, depth / 2 + 1.5 * g, 8, 3, g, rgb(120, 220, 255))
	b.Neon(screen)
	b.Box(-w * 0.18, split + 10, depth / 2 + 2 * g, 4, 5, 2, GREY, M.Metal)
	-- magnets + petit mot
	b.CylZ(-w * 0.2, top * 0.46, depth / 2 + g + 0.6, 7, 1.2, accent(b, 1, PINK), M.SmoothPlastic)
	House3DKit.Heart(b, -w * 0.02, top * 0.4, depth / 2 + g, 6, 1.2, accent(b, 2, rgb(255, 120, 150)), M.SmoothPlastic)
	House3DKit.StarSoft(b, -w * 0.22, top * 0.3, depth / 2 + g, 3.4, 1.2, BUTTER, M.SmoothPlastic)
	b.BoxR(CFrame.new(-w * 0.08, top * 0.25, depth / 2 + 1.5 * g) * CFrame.Angles(0, 0, 0.08), 10, 12, g, rgb(255, 250, 220), M.SmoothPlastic)
	b.Ball(-w * 0.08, top * 0.25 + 5, depth / 2 + g + 1, 2, rgb(255, 90, 110), M.SmoothPlastic)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.Stove = function(b, ctx)
	local top = ctx.TopY(1, 62)
	local x0, x1 = ctx.Span(1, -44, 44)
	local w, depth = x1 - x0, 50
	local body = accent(b, 1, rgb(255, 180, 190))
	local g = House3DKit.Gap(b, 0.8)
	-- cuisinière : caisson, plan émaillé biseauté, dosseret à horloge,
	-- four vitré (cadre, poignée chromée), tiroir bas, brûleurs à grilles
	b.Box(0, 0, 0, w, top - 4, depth, body, M.SmoothPlastic)
	b.Box(0, 0, depth / 2 - 2, w - 6, 3, 2, darken(body, 0.5), M.SmoothPlastic)
	House3DKit.Bevel(b, 0, top - 4, 0, w + 2, 4, depth + 2, 1.2, lightOf(b, WHITE), M.SmoothPlastic)
	b.Box(0, top - 4, -depth / 2 + 2, w + 2, 14, 4, body, M.SmoothPlastic)
	b.Box(0, top + 4, -depth / 2 + 4 + g / 2, 12, 4, g, rgb(40, 40, 52), M.SmoothPlastic)
	local digits = b.Box(0, top + 5, -depth / 2 + 4 + g, 8, 2, g, rgb(120, 255, 170))
	b.Neon(digits)
	-- four
	b.Box(0, 12, depth / 2 + g / 2, w * 0.8, top * 0.56, g, darken(body, 0.12), M.SmoothPlastic)
	local window = b.Box(0, 16, depth / 2 + 1.5 * g, w * 0.62, top * 0.4, g, rgb(40, 34, 52), M.Glass)
	window.Reflectance = 0.2
	House3DKit.Handle(b, 0, top * 0.66, depth / 2 + g, w * 0.6, false)
	-- tiroir bas
	b.Box(0, 3.4, depth / 2 + g / 2, w * 0.8, 7, g, darken(body, 0.08), M.SmoothPlastic)
	House3DKit.Handle(b, 0, 7, depth / 2 + g, w * 0.3, false)
	-- manettes
	for index = 1, 4 do
		local kx = -w / 2 + index * w / 5
		b.CylZ(kx, top - 10, depth / 2 + 0.8, 6, 1.6, CHROME_METAL, M.Metal).Reflectance = 0.3
		b.CylZ(kx, top - 10, depth / 2 + 2, 4, 2.4, INK, M.SmoothPlastic)
		b.Box(kx, top - 8.6, depth / 2 + 3.3, 0.8, 1.6, 0.4, WHITE, M.SmoothPlastic)
	end
	-- brûleurs (tête, chapeau) + grilles en fonte
	for _, bx in ipairs({ -w / 4, w / 4 }) do
		for _, bz in ipairs({ -depth / 4, depth / 4 }) do
			b.Cyl(bx, top, bz, 14, 0.8, rgb(70, 60, 80), M.Metal)
			b.Cyl(bx, top + 0.8, bz, 7, 0.8, rgb(40, 36, 48), M.Metal)
			b.Box(bx, top + 1.2, bz, 18, 1, 1.4, INK, M.Metal)
			b.Box(bx, top + 1.2, bz, 1.4, 1, 18, INK, M.Metal)
		end
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 2, depth + 2, top)
end
R.Microwave = function(b, _ctx)
	local body = lightOf(b, WHITE)
	local g = House3DKit.Gap(b, 0.8)
	-- micro-ondes : coins arrondis, porte à hublot sombre (reflet), plateau
	-- tournant, panneau de commande (afficheur + touches), poignée, pieds
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 38, 0, sz * 18, 5, 2, INK, M.Rubber)
		end
	end
	b.Round(0, 2, 0, 90, 54, 50, 4, body, M.SmoothPlastic)
	b.Box(-10, 7, 25 + g / 2, 60, 44, g, darken(body, 0.08), M.SmoothPlastic)
	local glass = b.Box(-12, 11, 25 + 1.5 * g, 50, 36, g, rgb(44, 38, 62), M.Glass)
	glass.Reflectance = 0.25
	House3DKit.Handle(b, 17, 29, 25 + g, 26, true)
	-- panneau de commande
	b.Box(30, 7, 25 + g / 2, 18, 44, g, accent(b, 1, PINK), M.SmoothPlastic)
	b.Box(30, 42, 25 + 1.5 * g, 13, 5, g, rgb(30, 40, 30), M.SmoothPlastic)
	local digits = b.Box(30, 43.2, 25 + 2.5 * g, 9, 2.4, g, rgb(120, 255, 170))
	b.Neon(digits)
	for row = 0, 3 do
		for col = 0, 2 do
			b.Box(26 + col * 4, 14 + row * 5.6, 25 + 1.5 * g, 3, 3.6, g, row == 0 and GREY_DARK or lighten(accent(b, 1, PINK), 0.35), M.SmoothPlastic)
		end
	end
	b.Top(1, 0, 56, 0, 80, 46)
	b.Footprint(90, 50, 56)
end
R.Toaster = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 170, 190))
	local g = House3DKit.Gap(b, 0.8)
	-- grille-pain rétro : coque arrondie, bandeau chromé, fentes avec deux
	-- tranches dorées (croûte), levier, molette, pieds
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 32, 0, 0, 8, 3, 36, INK, M.Rubber)
	end
	b.Round(0, 3, 0, 80, 50, 44, 10, body, M.SmoothPlastic)
	b.Egg(0, 53, 0, 76, 8, 40, body, M.SmoothPlastic)
	local band = b.Box(0, 22, 0, 80 + 2 * g, 5, 44 + 2 * g, CHROME_METAL, M.Metal)
	band.Reflectance = 0.35
	for _, z in ipairs({ -8, 8 }) do
		b.Box(0, 54, z, 60, 3, 7, INK, M.SmoothPlastic)
		b.Box(0, 50, z, 40, 12, 4.4, rgb(214, 160, 96), M.SmoothPlastic)
		b.Egg(0, 62, z, 40, 6, 4.4, rgb(176, 110, 60), M.SmoothPlastic)
	end
	b.Box(41, 34, 0, 4, 5, 10, INK, M.SmoothPlastic)
	b.Box(40 + g, 18, 0, g, 30, 4, darken(body, 0.35), M.SmoothPlastic)
	b.CylX(41, 14, 12, 7, 3, CHROME_METAL, M.Metal).Reflectance = 0.3
	b.Footprint(80, 44, 60)
end

-- SALLE DE BAIN ------------------------------------------------------------

R.Bathtub = function(b, ctx)
	local top = ctx.TopY(1, 54)
	local body = lightOf(b, WHITE)
	local w, depth = 96, 52
	local g = House3DKit.Gap(b, 0.8)
	-- baignoire sur pieds griffes : cuve arrondie, rebord roulé, eau
	-- transparente avec mousse, robinet col-de-cygne chromé à croisillons
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local fx, fz = sx * 38, sz * 16
			local foot = b.Ball(fx, 4.4, fz, 8, GOLD, M.Metal)
			foot.Reflectance = 0.3
			b.Cyl(fx, 0, fz, 7, 2, GOLD, M.Metal)
			b.Wedge(fx + sx * 3, 0, fz, 3, 4, 6, darken(GOLD, 0.1), sx > 0 and "Right" or "Left", M.Metal)
		end
	end
	b.Round(0, 8, 0, w - 4, top - 12, depth - 4, 14, body, M.SmoothPlastic)
	b.Egg(0, 9, 0, w - 8, 8, depth - 8, body, M.SmoothPlastic)
	b.Round(0, top - 4, 0, w + 2, 4, depth + 2, 16, lighten(body, 0.2), M.SmoothPlastic)
	local water = b.Box(0, top - 7, 0, w - 10, 3.4, depth - 10, rgb(170, 220, 255), M.Glass)
	water.Transparency = 0.25
	for index = 1, 9 do
		b.Ball(-32 + index * 7.5, top - 3.2, ((index * 13) % 20) - 10, 7 + index % 3 * 2.4, WHITE)
	end
	-- robinet
	local chrome = CHROME_METAL
	b.Cyl(-w / 2 + 6, top, 0, 4, 16, chrome, M.Metal).Reflectance = 0.4
	b.Tube(-w / 2 + 6, top + 16, 0, -w / 2 + 12, top + 18, 0, 3.4, chrome, M.Metal).Reflectance = 0.4
	b.Tube(-w / 2 + 12, top + 18, 0, -w / 2 + 14, top + 12, 0, 3, chrome, M.Metal).Reflectance = 0.4
	for _, sz in ipairs({ -1, 1 }) do
		b.Cyl(-w / 2 + 6, top, sz * 8, 3, 6, chrome, M.Metal)
		b.CylX(-w / 2 + 6, top + 6.5, sz * 8, 1.4, 7, chrome, M.Metal).Reflectance = 0.4
		b.CylZ(-w / 2 + 6, top + 6.5, sz * 8, 1.4, 7, chrome, M.Metal)
	end
	b.Box(0, 12, depth / 2 - 2 + g, w * 0.6, 7, g, accent(b, 1, PINK), M.SmoothPlastic)
	b.Top(1, 0, top, 0, w - 8, depth - 8)
	b.Footprint(w + 2, depth + 2, top)
end
R.Toilet = function(b, ctx)
	local top = ctx.TopY(1, 82)
	local body = lightOf(b, WHITE)
	-- WC : pied galbé, cuvette, lunette + abattant, réservoir aux angles
	-- arrondis, couvercle biseauté, bouton poussoir chromé
	b.Egg(0, 4, 8, 34, 12, 40, body, M.SmoothPlastic)
	b.Cyl(0, 0, 8, 28, 26, body, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		b.Ball(sx * 15, 3, 12, 4, lighten(body, 0.1), M.SmoothPlastic)
	end
	b.Egg(0, 28, 10, 46, 16, 50, body, M.SmoothPlastic)
	b.Cyl(0, 22, 10, 44, 12, body, M.SmoothPlastic)
	b.Cyl(0, 34, 10, 48, 2, lighten(body, 0.15), M.SmoothPlastic)
	b.Egg(0, 37, 11, 46, 3.4, 48, accent(b, 1, PINK), M.SmoothPlastic)
	b.CylX(0, 37, -12, 3, 16, CHROME_METAL, M.Metal)
	b.Round(0, 30, -20, 46, top - 34, 18, 4, body, M.SmoothPlastic)
	House3DKit.Bevel(b, 0, top - 4, -20, 50, 4, 20, 1.2, lighten(body, 0.2), M.SmoothPlastic)
	b.Cyl(0, top, -20, 7, 1.2, CHROME_METAL, M.Metal).Reflectance = 0.35
	b.Box(14, top - 12, -10.4, 8, 3, 2, GREY, M.Metal)
	b.Top(1, 0, top, -20, 40, 16)
	b.Footprint(50, 56, top)
end
R.Shower = function(b, _ctx)
	local tray = lightOf(b, WHITE)
	local chrome = CHROME_METAL
	local g = House3DKit.Gap(b, 0.8)
	-- receveur + bonde, faïence du fond (carreaux et joints), parois vitrées
	-- à profilés chromés, pommeau de pluie, douchette sur barre, mitigeur,
	-- tablette avec flacons
	b.Box(0, 0, 0, 80, 6, 60, tray, M.SmoothPlastic)
	b.Box(0, 6, 0, 72, 0.6, 52, darken(tray, 0.05), M.SmoothPlastic)
	b.Cyl(8, 6, 6, 6, 0.8, chrome, M.Metal)
	b.Box(0, 6, -29, 80, 90, 2, rgb(170, 180, 190), M.SmoothPlastic)
	local tile = accent(b, 1, SKY)
	for row = 0, 5 do
		for col = 0, 3 do
			b.Box(-30 + col * 20, 7.5 + row * 14.8, -28 + g / 2, 18.6, 13.4, g, vary(lighten(tile, 0.35), row * 5 + col, 0.05), M.SmoothPlastic)
		end
	end
	local glass = b.Box(0, 6, 29, 78, 90, 1.2, rgb(200, 230, 255), M.Glass)
	glass.Transparency = 0.6
	glass.CastShadow = false
	local side = b.Box(39, 6, 0, 1.2, 90, 58, rgb(200, 230, 255), M.Glass)
	side.Transparency = 0.6
	side.CastShadow = false
	for _, spec in ipairs({ { 39.8, 29.8 }, { -39.8, 29.8 }, { 39.8, -28 } }) do
		b.Box(spec[1], 6, spec[2], 1.8, 90, 1.8, chrome, M.Metal).Reflectance = 0.35
	end
	b.Box(0, 94.6, 29.8, 80, 1.8, 1.8, chrome, M.Metal).Reflectance = 0.35
	House3DKit.Handle(b, 20, 50, 29.6, 24, true)
	-- pommeau de pluie + bras
	b.Tube(-30, 92, -27, -30, 92, -12, 2.4, chrome, M.Metal).Reflectance = 0.4
	b.Cyl(-30, 88, -8, 18, 3, chrome, M.Metal).Reflectance = 0.4
	b.Cyl(-30, 87.6, -8, 15, 0.6, GREY_DARK, M.Metal)
	-- mitigeur + douchette sur barre
	b.CylZ(-30, 46, -27, 10, 2, chrome, M.Metal).Reflectance = 0.4
	b.Box(-30, 45, -24, 6, 2, 4, chrome, M.Metal)
	b.Box(-14, 30, -27.4, 2, 50, 2, chrome, M.Metal).Reflectance = 0.35
	b.Tube(-14, 70, -25, -14, 80, -22, 3, chrome, M.Metal)
	b.Cyl(-14, 80, -21, 7, 2, chrome, M.Metal)
	-- tablette et flacons
	b.Box(22, 50, -25, 18, 1.6, 6, chrome, M.Metal)
	for index, c in ipairs({ PINK, MINT, BUTTER }) do
		b.Cyl(16 + index * 4.4, 51.6, -25, 3.6, 7 + index % 2 * 2, c, M.SmoothPlastic)
	end
	b.Box(0, 96, 0, 82, 3, 60, accent(b, 1, SKY))
	b.Footprint(82, 62, 100)
end
R.HotSpring = function(b, _ctx)
	local stone = b.Map(rgb(170, 160, 180))
	-- source chaude : rochers variés, eau, bec en bambou qui verse, vapeur,
	-- seau en bois
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		local s = 18 + (index * 7) % 4 * 2.4
		b.EggR(CFrame.new(math.cos(angle) * 44, 8 + (index % 3) * 1.4, math.sin(angle) * 30) * CFrame.Angles(0, -angle, 0.2 * ((index % 2) * 2 - 1)), s * 1.2, s * 0.8, s,
			vary(index % 2 == 0 and stone or darken(stone, 0.12), index, 0.1), M.Slate)
	end
	b.Cyl(0, 0, 0, 80, 12, rgb(150, 210, 240), M.Glass)
	local surface = b.Cyl(0, 11, 0, 76, 2, rgb(190, 235, 255), M.Glass)
	surface.Transparency = 0.2
	surface.Reflectance = 0.2
	b.Tube(-44, 30, -18, -26, 22, -10, 4, rgb(150, 190, 90), M.Wood)
	b.Tube(-44, 30, -18, -44, 8, -18, 4.4, rgb(130, 170, 80), M.Wood)
	local stream = b.Tube(-26, 22, -10, -24, 12, -9, 2, rgb(200, 235, 255), M.Glass)
	stream.Transparency = 0.4
	for index = 1, 5 do
		local steam = b.Ball(-20 + index * 8, 30 + index * 6, (index % 2) * 8, 14, WHITE)
		steam.Transparency = 0.55
		steam.CastShadow = false
	end
	-- seau en bois cerclé + serviette pliée
	b.Cyl(40, 12, 22, 12, 9, rgb(200, 150, 100), M.Wood)
	for _, y in ipairs({ 13.5, 18.5 }) do
		b.Cyl(40, y, 22, 12.6, 1, GREY_DARK, M.Metal)
	end
	b.Box(30, 14, -24, 14, 3, 9, WHITE, M.Fabric)
	b.CylZ(23, 15.5, -24, 3, 9, WHITE, M.Fabric)
	b.Footprint(100, 70, 20)
end

-- LAMPES ---------------------------------------------------------------------

-- (v9.8) Abat-jour tambour légèrement conique (deux fûts), liserés haut / bas,
-- lyre + pommeau, douille et ampoule douce visibles par-dessous
local function lampShade(b: Builder, y: number, diameter: number, height: number, color: Color3, light: Color3, range: number)
	local shade = b.Cyl(0, y, 0, diameter, height * 0.55, color, M.Fabric)
	shade.CastShadow = false
	local upper = b.Cyl(0, y + height * 0.55, 0, diameter * 0.88, height * 0.45, color, M.Fabric)
	upper.CastShadow = false
	b.Cyl(0, y - 1.2, 0, diameter + 1, 1.8, darken(color, 0.18), M.Fabric)
	b.Cyl(0, y + height - 0.6, 0, diameter * 0.88 + 1, 1.4, darken(color, 0.18), M.Fabric)
	-- lyre (deux tiges) + pommeau
	for _, sx in ipairs({ -1, 1 }) do
		b.Tube(sx * diameter * 0.12, y + height * 0.2, 0, sx * 1, y + height + 2, 0, 1, BRASS, M.Metal)
	end
	b.Ball(0, y + height + 2.6, 0, 3.4, BRASS, M.Metal).Reflectance = 0.3
	b.Cyl(0, y + height * 0.05, 0, diameter * 0.18, height * 0.2, BRASS, M.Metal)
	House3DKit.Bulb(b, 0, y + height * 0.32, 0, diameter * 0.32, light, range, 1)
end
R.FloorLamp = function(b, _ctx)
	local metal = b.Map(GOLD)
	local shade = accent(b, 1, PINK_SOFT)
	-- socle lesté biseauté, tige à bagues, interrupteur, abat-jour tambour
	b.Cyl(0, 0, 0, 30, 1.6, darken(metal, 0.4), M.Rubber)
	b.Cyl(0, 1.6, 0, 28, 2.4, metal, M.Metal).Reflectance = 0.3
	b.Cyl(0, 4, 0, 16, 2, lighten(metal, 0.1), M.Metal).Reflectance = 0.3
	b.Cyl(0, 6, 0, 3.4, 66, metal, M.Metal).Reflectance = 0.3
	for _, y in ipairs({ 6, 38, 70 }) do
		b.Cyl(0, y, 0, 5, 2, lighten(metal, 0.12), M.Metal).Reflectance = 0.3
	end
	b.CylZ(0, 46, 2, 2.6, 3, INK, M.SmoothPlastic)
	lampShade(b, 72, 36, 24, shade, BUTTER, 18)
	b.Footprint(36, 36, 100)
end
R.DeskLamp = function(b, _ctx)
	local color = accent(b, 1, MINT)
	-- lampe d'architecte : socle, bras doubles à ressorts, rotules, tête en
	-- dôme, ampoule dessous
	b.Cyl(0, 0, 0, 40, 2, darken(color, 0.3), M.Rubber)
	b.Cyl(0, 2, 0, 36, 4, color, M.SmoothPlastic)
	b.Cyl(-8, 6, 0, 8, 4, GREY_DARK, M.Metal)
	local p0, p1, p2 = Vector3.new(-8, 9, 0), Vector3.new(-14, 52, 0), Vector3.new(14, 64, 0)
	for _, dz in ipairs({ -2.2, 2.2 }) do
		b.Tube(p0.X, p0.Y, dz, p1.X, p1.Y, dz, 2.2, color, M.SmoothPlastic)
		b.Tube(p1.X, p1.Y, dz, p2.X, p2.Y, dz, 2.2, color, M.SmoothPlastic)
	end
	b.Tube(-6, 20, 0, -12, 40, 0, 1.4, CHROME_METAL, M.Metal).Reflectance = 0.3
	b.Tube(-8, 56, 0, 6, 61, 0, 1.4, CHROME_METAL, M.Metal)
	for _, p in ipairs({ p1, p2 }) do
		b.CylZ(p.X, p.Y, 0, 5, 6.4, GREY, M.Metal).Reflectance = 0.25
	end
	local head = b.EggR(CFrame.new(20, 58, 0) * CFrame.Angles(0, 0, -0.5), 24, 20, 22, color, M.SmoothPlastic)
	head.CastShadow = false
	b.CylZ(16, 62, 0, 6, 5, color, M.SmoothPlastic)
	House3DKit.Bulb(b, 23, 53, 0, 11, BUTTER, 12, 0.9)
	b.Footprint(44, 40, 70)
end
R.LavaLamp = function(b, _ctx)
	local color = accent(b, 1, PINK)
	-- base conique (gradins), verre fuselé, cire en gouttes lumineuses, capuchon
	b.Cyl(0, 0, 0, 34, 6, GREY_DARK, M.Metal).Reflectance = 0.3
	b.Cyl(0, 6, 0, 30, 7, GREY_DARK, M.Metal).Reflectance = 0.3
	b.Cyl(0, 13, 0, 25, 7, GREY_DARK, M.Metal).Reflectance = 0.3
	local liquid = lighten(color, 0.55)
	local glass = b.Cyl(0, 20, 0, 24, 22, liquid, M.Glass)
	glass.Transparency = 0.3
	local glass2 = b.Cyl(0, 42, 0, 20, 18, liquid, M.Glass)
	glass2.Transparency = 0.3
	local glass3 = b.Cyl(0, 60, 0, 15, 12, liquid, M.Glass)
	glass3.Transparency = 0.3
	for index, spec in ipairs({ { -3, 26, 10, 8 }, { 4, 40, 7, 11 }, { -2, 52, 6, 7 }, { 1, 64, 4, 5 }, { 3, 22, 9, 5 } }) do
		local blob = b.Egg(spec[1], spec[2], (index % 2) * 2 - 1, spec[3], spec[4], spec[3], color)
		b.Neon(blob)
	end
	b.Cyl(0, 72, 0, 16, 4, GREY_DARK, M.Metal).Reflectance = 0.3
	b.Cyl(0, 76, 0, 12, 10, GREY_DARK, M.Metal).Reflectance = 0.3
	b.Light(glass, color, 12, 0.9)
	b.Footprint(34, 34, 86)
end
R.MushroomLamp = function(b, _ctx)
	local cap = accent(b, 1, PINK)
	-- pied, chapeau bombé à pois, dessous lumineux (lamelles), petit interrupteur
	b.Cyl(0, 0, 0, 34, 4, darken(CREAM, 0.08), M.SmoothPlastic)
	b.Cyl(0, 4, 0, 24, 42, CREAM, M.SmoothPlastic)
	b.Egg(0, 8, 0, 30, 14, 30, CREAM, M.SmoothPlastic)
	local glow = b.Cyl(0, 42, 0, 66, 3, BUTTER)
	b.Neon(glow)
	local top = b.Cyl(0, 44, 0, 80, 10, cap, M.SmoothPlastic)
	top.CastShadow = false
	b.Egg(0, 54, 0, 80, 34, 80, cap, M.SmoothPlastic)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		b.EggR(CFrame.new(math.cos(angle) * 26, 62, math.sin(angle) * 26) * CFrame.Angles(math.sin(angle) * 0.7, 0, -math.cos(angle) * 0.7), 11, 2.4, 9, WHITE, M.SmoothPlastic)
	end
	b.EggR(CFrame.new(0, 70.6, 0), 12, 1.6, 12, WHITE, M.SmoothPlastic)
	b.Box(0, 12, 12.4, 4, 6, 2, INK, M.SmoothPlastic)
	b.Light(glow, BUTTER, 12, 1)
	b.Footprint(80, 80, 72)
end
R.MoonLamp = function(b, _ctx)
	-- lune imprimée 3D (cratères) posée sur un berceau en bois
	b.Cyl(0, 0, 0, 40, 6, woodOf(b, WOOD), M.Wood)
	b.Cyl(0, 6, 0, 4, 12, GREY, M.Metal)
	b.Cyl(0, 16, 0, 22, 2, GREY, M.Metal)
	local moonColor = lightOf(b, rgb(255, 244, 200))
	local moon = b.Ball(0, 50, 0, 64, moonColor)
	b.Neon(moon)
	for index, spec in ipairs({ { -0.5, 0.3 }, { 0.4, -0.2 }, { 0.7, 0.5 }, { -0.2, -0.6 }, { 0.05, 0.75 }, { -0.9, -0.1 }, { 0.9, -0.5 } }) do
		local dir = Vector3.new(spec[1], spec[2], 1).Unit
		local p = Vector3.new(0, 50, 0) + dir * 31.2
		local size = 7 + (index % 3) * 3
		b.EggR(CFrame.lookAt(p, p + dir), size, size * 0.9, 2, darken(moonColor, 0.14), M.SmoothPlastic)
	end
	b.Light(moon, rgb(255, 236, 190), 14, 1)
	b.Footprint(64, 64, 82)
end
R.ScentedCandle = function(b, _ctx)
	local color = accent(b, 1, PINK_SOFT)
	-- bougie en pot de verre : verre épais, cire, étiquette, mèche, flamme
	-- en goutte, couvercle en bois posé à côté
	local jar = b.Cyl(0, 0, 0, 70, 62, rgb(230, 240, 250), M.Glass)
	jar.Transparency = 0.45
	b.Cyl(0, 1, 0, 64, 52, color, M.SmoothPlastic)
	b.Cyl(0, 53, 0, 64, 1, lighten(color, 0.3), M.SmoothPlastic)
	b.Cyl(0, 18, 0, 71, 20, rgb(250, 244, 230), M.SmoothPlastic)
	b.Cyl(0, 26, 0, 71.6, 4, accent(b, 2, GOLD), M.SmoothPlastic)
	b.Cyl(0, 54, 0, 2, 8, INK)
	local flame = b.Egg(0, 69, 0, 8, 16, 8, FIRE)
	b.Neon(flame)
	local core = b.Egg(0, 66, 0, 4, 7, 4, rgb(255, 250, 210))
	b.Neon(core)
	b.Light(flame, rgb(255, 190, 120), 8, 0.8)
	b.Footprint(70, 70, 80)
end
R.OilLamp = function(b, _ctx)
	local metal = b.Map(GOLD)
	-- lampe à huile : pied, réservoir, anse, verre de lampe galbé, mèche, flamme
	b.Cyl(0, 0, 0, 40, 4, darken(metal, 0.15), M.Metal).Reflectance = 0.3
	b.Cyl(0, 4, 0, 14, 6, metal, M.Metal).Reflectance = 0.3
	b.Egg(0, 20, 0, 40, 26, 40, metal, M.Metal).Reflectance = 0.3
	b.Cyl(0, 30, 0, 20, 4, darken(metal, 0.1), M.Metal)
	b.Tube(18, 26, 0, 26, 30, 0, 3, metal, M.Metal)
	b.Tube(26, 30, 0, 26, 18, 0, 3, metal, M.Metal)
	b.Tube(26, 18, 0, 18, 14, 0, 3, metal, M.Metal)
	local glass = b.Egg(0, 46, 0, 30, 30, 30, rgb(255, 240, 210), M.Glass)
	glass.Transparency = 0.45
	local chimney = b.Cyl(0, 58, 0, 18, 16, rgb(255, 240, 210), M.Glass)
	chimney.Transparency = 0.45
	b.Cyl(0, 34, 0, 6, 6, rgb(250, 240, 220), M.Fabric)
	local flame = b.Egg(0, 45, 0, 7, 13, 7, FIRE)
	b.Neon(flame)
	b.Cyl(0, 74, 0, 20, 2, metal, M.Metal)
	b.Light(flame, rgb(255, 190, 120), 10, 0.9)
	b.Footprint(40, 40, 80)
end
R.Candelabra = function(b, _ctx)
	local metal = b.Map(GOLD)
	-- chandelier à 3 branches : pied à gradins, tige à nœuds, bras courbes,
	-- bobèches, bougies avec coulures, flammes en goutte
	b.Cyl(0, 0, 0, 34, 3, darken(metal, 0.15), M.Metal).Reflectance = 0.3
	b.Egg(0, 4, 0, 26, 7, 26, metal, M.Metal).Reflectance = 0.3
	b.Cyl(0, 5, 0, 5, 46, metal, M.Metal).Reflectance = 0.3
	for _, y in ipairs({ 18, 34 }) do
		b.Ball(0, y, 0, 8, metal, M.Metal).Reflectance = 0.3
	end
	for _, x in ipairs({ -28, 28 }) do
		b.Tube(0, 44, 0, x * 0.5, 40, 0, 3, metal, M.Metal)
		b.Tube(x * 0.5, 40, 0, x, 46, 0, 3, metal, M.Metal)
		b.Tube(x, 46, 0, x, 50, 0, 3, metal, M.Metal)
	end
	for _, x in ipairs({ -28, 0, 28 }) do
		b.Cyl(x, 50, 0, 11, 2, metal, M.Metal).Reflectance = 0.3
		b.Cyl(x, 52, 0, 8, 24, CREAM, M.SmoothPlastic)
		b.Egg(x + 2.6, 70, 2.6, 2.4, 8, 2.4, CREAM, M.SmoothPlastic)
		b.Cyl(x, 76, 0, 1, 3, INK)
		local flame = b.Egg(x, 82, 0, 5, 10, 5, FIRE)
		b.Neon(flame)
		if x == 0 then
			b.Light(flame, rgb(255, 190, 120), 10, 0.9)
		end
	end
	b.Footprint(64, 30, 88)
end

-- LUMIÈRES MURALES / SUSPENDUES (repère : bas de la boîte, y = 0..100) ---------

R.HangingBulb = function(b, _ctx)
	-- ampoule Edison : cordon tressé, douille laiton cannelée, verre fumé
	-- transparent, filament lumineux en zigzag
	b.Cyl(0, 96, 0, 12, 4, INK, M.SmoothPlastic)
	b.Cyl(0, 44, 0, 2, 52, INK, M.Fabric)
	b.Cyl(0, 34, 0, 11, 10, BRASS, M.Metal).Reflectance = 0.3
	for _, y in ipairs({ 36, 39, 42 }) do
		b.Cyl(0, y, 0, 12, 1, darken(BRASS, 0.15), M.Metal)
	end
	local glass = b.Egg(0, 22, 0, 22, 26, 22, rgb(255, 230, 180), M.Glass)
	glass.Transparency = 0.45
	glass.CastShadow = false
	local prev = { -4, 16 }
	for index = 1, 4 do
		local p = { -4 + index * 2, 16 + (index % 2) * 6 }
		local wire = b.Tube(prev[1], prev[2], 0, p[1], p[2], 0, 1, rgb(255, 200, 110))
		b.Neon(wire)
		prev = p
	end
	local core = b.Ball(0, 22, 0, 5, BUTTER)
	b.Neon(core)
	b.Light(core, BUTTER, 16, 1)
	b.Footprint(24, 24, 100)
end
R.PaperLantern = function(b, _ctx)
	local color = accent(b, 1, rgb(255, 140, 150))
	-- lanterne en papier : sphère, nervures (anneaux), montures noires, gland
	b.Cyl(0, 80, 0, 2, 30, INK)
	b.Cyl(0, 74, 0, 24, 6, INK)
	local lantern = b.Ball(0, 48, 0, 56, color, M.Fabric)
	for _, dy in ipairs({ -18, -9, 0, 9, 18 }) do
		local r = math.sqrt(28 * 28 - dy * dy)
		b.Cyl(0, 48 + dy - 0.5, 0, r * 2 + 0.6, 1, darken(color, 0.15), M.Fabric)
	end
	b.Cyl(0, 20, 0, 24, 5, INK)
	b.Cyl(0, 12, 0, 1.4, 8, accent(b, 2, GOLD), M.Fabric)
	b.Egg(0, 9, 0, 4, 8, 4, accent(b, 2, GOLD), M.Fabric)
	b.Light(lantern, lighten(color, 0.4), 14, 1)
	table.insert(b.Glows, lantern)
	b.Footprint(56, 56, 100)
end
R.DiscoBall = function(b, _ctx)
	-- boule à facettes : chaîne, moteur, boule miroir + bandes de facettes
	b.Cyl(0, 86, 0, 2, 14, GREY)
	b.Cyl(0, 80, 0, 8, 6, GREY_DARK, M.Metal)
	local ball = b.Ball(0, 48, 0, 60, rgb(220, 220, 240), M.Foil)
	ball.Reflectance = 0.5
	for _, dy in ipairs({ -20, -10, 0, 10, 20 }) do
		local r = math.sqrt(30 * 30 - dy * dy)
		local band = b.Cyl(0, 48 + dy - 0.4, 0, r * 2 + 0.4, 0.8, rgb(170, 170, 196), M.Foil)
		band.Reflectance = 0.4
	end
	b.Light(ball, accent(b, 1, LILAC), 16, 0.8)
	b.Footprint(60, 60, 100)
end
R.CloudLamp = function(b, _ctx)
	-- nuage lumineux : bouffées de tailles variées, cœur éclairé, fil
	b.Cyl(0, 76, 0, 2, 40, GREY)
	for index = 0, 4 do
		local puff = b.Ball(-24 + index * 12, 50 + (index % 2) * 6, 0, 26 + (index % 2) * 8, WHITE)
		table.insert(b.Glows, puff)
		if index == 2 then
			b.Light(puff, rgb(255, 250, 235), 16, 0.9)
		end
	end
	for index = 0, 3 do
		local puff = b.Ball(-18 + index * 12, 44 + (index % 2) * 4, (index % 2) * 8 - 4, 20, rgb(246, 246, 255))
		table.insert(b.Glows, puff)
	end
	b.Footprint(70, 36, 100)
end
R.FairyLights = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, BUTTER), accent(b, 3, MINT), accent(b, 4, SKY) }
	local count = 12
	-- fil continu, douilles, ampoules en goutte, petites pinces
	local points = {}
	for index = 0, count do
		local t = index / count
		table.insert(points, { -48 + t * 96, 60 - math.sin(t * math.pi * 2) ^ 2 * 16, 0.5 })
	end
	House3DKit.Path(b, points, 1, rgb(60, 70, 60), M.SmoothPlastic, false, true)
	for index = 0, count do
		local p = points[index + 1]
		local x, y = p[1], p[2]
		b.Cyl(x, y - 3.4, 1, 2, 3, rgb(60, 70, 60), M.SmoothPlastic)
		local bulb = b.Egg(x, y - 6, 1, 4.4, 6, 4.4, colors[index % 4 + 1])
		b.Neon(bulb)
		if index % 6 == 3 then
			b.Light(bulb, colors[index % 4 + 1], 10, 0.6)
		end
	end
	for _, x in ipairs({ -48, 48 }) do
		b.Box(x, 57, 0.8, 3, 6, 1.6, WOOD_LIGHT, M.Wood)
	end
	b.Footprint(100, 4, 100)
end

-- ÉTAGÈRES MURALES (repère : bas de la boîte ; z = 0 contre le mur) --------

R.FloatingShelf = function(b, ctx)
	local wood = woodOf(b, WOOD)
	-- planches épaisses biseautées, chant plus clair, équerres en laiton
	for index = 1, 2 do
		local y = ctx.TopY(index, index == 1 and 66 or 28)
		local x0, x1 = ctx.Span(index, -44, 44)
		local cx = (x0 + x1) / 2
		House3DKit.Bevel(b, cx, y - 4, 11, x1 - x0 + 4, 4, 22, 1, vary(wood, index, 0.06), M.Wood)
		for _, side in ipairs({ -1, 1 }) do
			local bx = cx + side * (x1 - x0) * 0.36
			b.Box(bx, y - 14, 1, 2.4, 10, 2, BRASS, M.Metal).Reflectance = 0.25
			b.Box(bx, y - 5.6, 7, 2.4, 1.6, 14, BRASS, M.Metal).Reflectance = 0.25
			b.Tube(bx, y - 12, 1.8, bx, y - 5.6, 11, 1.2, BRASS, M.Metal)
		end
		b.Top(index, (x0 + x1) / 2, y, 11, x1 - x0, 18)
	end
	b.Footprint(100, 22, 100)
end
R.WallShelf = function(b, _ctx)
	local wood = woodOf(b, WOOD)
	House3DKit.Bevel(b, 0, 44, 11, 96, 5, 22, 1.2, wood, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Wedge(side * 36, 32, 5, 3, 12, 10, darken(wood, 0.2), "Front", M.Wood)
		b.Box(side * 36, 30, 1, 5, 16, 2, darken(wood, 0.25), M.Wood)
	end
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT) }
	House3DKit.Books(b, -44, -12, 49, 17, 14, 22, colors, 5)
	b.Box(-10.4, 49, 10, 2, 16, 12, GREY_DARK, M.Metal) -- serre-livres
	-- petite plante en pot
	b.Cyl(28, 49, 10, 12, 6, accent(b, 5, rgb(255, 170, 120)))
	b.Cyl(28, 54.6, 10, 13, 1.6, lighten(accent(b, 5, rgb(255, 170, 120)), 0.15))
	bush(b, 28, 61, 10, 12, accent(b, 4, LEAF), 4)
	b.Top(1, 0, 49, 11, 60, 18)
	b.Footprint(100, 22, 100)
end

-- FENÊTRES ET TABLEAUX (repère : bas de la boîte ; z = 0 contre le mur) --------

-- Fenêtre en relief : chambranle mouluré (couleur des moulures), dormant,
-- petits bois, vitre légèrement réfléchissante, rebord biseauté, crémone
-- en laiton, petits rideaux noués ; la vue = le centre du dessin 2D
local function windowRecipe(b: Builder, ctx: Ctx)
	local frame = ctx.Trim
	local g = House3DKit.Gap(b, 0.8)
	b.Art(0, 12, 0.5, 78, 76, 1.3)
	local glass = b.Box(0, 12, 3, 78, 76, 0.6, GLASS, M.Glass)
	glass.Transparency = 0.8
	glass.Reflectance = 0.15
	glass.CastShadow = false
	-- chambranle (extérieur) + dormant (en retrait, un peu plus sombre)
	b.Box(0, 88, 2.5, 92, 8, 6, frame, M.Wood)
	b.Box(0, 6, 2.5, 92, 6, 6, frame, M.Wood)
	for _, x in ipairs({ -42, 42 }) do
		b.Box(x, 12, 2.5, 8, 76, 6, frame, M.Wood)
	end
	b.Box(0, 94.5, 3, 96, 3, 7, lighten(frame, 0.08), M.Wood)
	for _, x in ipairs({ -37.5, 37.5 }) do
		b.Box(x, 12, 2.5, 3, 76, 3, darken(frame, 0.08), M.Wood)
	end
	-- petits bois (croisillon)
	b.Box(0, 12, 2.5, 3, 76, 4, frame, M.Wood)
	b.Box(0, 48.5, 2.5, 78, 3, 4, frame, M.Wood)
	-- rebord biseauté + console
	House3DKit.Bevel(b, 0, 1, 7, 100, 5, 14, 1.2, frame, M.Wood)
	b.Box(0, -3, 3, 80, 4, 6, darken(frame, 0.1), M.Wood)
	-- crémone
	b.Box(2.6, 44, 4.6 + g, 1.6, 9, 1.4, BRASS, M.Metal).Reflectance = 0.3
	b.Ball(2.6, 49, 5.8 + g, 2.2, BRASS, M.Metal)
	-- tringle + petits rideaux noués sur les côtés
	local curtain = accent(b, 1, PINK_SOFT)
	b.CylX(0, 97.5, 11, 2, 104, BRASS, M.Metal).Reflectance = 0.3
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 52, 97.5, 11, 3.4, BRASS, M.Metal)
		for fold = 0, 2 do
			local fx = side * (47 - fold * 3)
			b.Tube(fx, 96, 10 - fold * 0.6, side * 44, 50, 11, 3, lighten(curtain, fold * 0.08), M.Fabric)
			b.Tube(side * 44, 50, 11, fx + side * 1.5, 8, 10 - fold * 0.6, 3.2, lighten(curtain, fold * 0.08), M.Fabric)
		end
		b.Ball(side * 44, 50, 12.6, 3.4, accent(b, 2, PINK), M.Fabric)
	end
	b.Footprint(100, 14, 100)
end
-- Tableau / affiche / calendrier
local function plaque(kind: string)
	return function(b: Builder, _ctx: Ctx)
		local back = darken(b.P(1, WOOD), 0.25)
		local g = House3DKit.Gap(b, 0.8)
		if kind == "Poster" then
			-- affiche : papier fin, coins un peu relevés, punaises
			b.Box(0, 6, 0.5, 88, 88, 1, lighten(back, 0.5), M.SmoothPlastic)
			b.Art(0, 6, 1.6, 88, 88, 1)
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ 9, 91 }) do
					b.Ball(sx * 40, sy, 2.4 + g, 3.4, sy > 50 and rgb(255, 90, 110) or rgb(90, 160, 255), M.SmoothPlastic)
				end
				b.Wedge(sx * 41, 6, 2.2 + g * 0.5, 6, 6, g, lighten(back, 0.6), "Front", M.SmoothPlastic)
			end
		else
			-- tableau : fond, dessin, cadre mouluré (baguettes + filet doré), verre
			b.Box(0, 6, 1, 88, 88, 2, back, M.Wood)
			b.Art(0, 6, 2.1, 88, 88, 1)
			local frameColor = kind == "Calendar" and lighten(back, 0.3) or back
			House3DKit.Frame(b, 0, 6 - g, 2 + g, 88 + 2 * g, 88 + 2 * g, 5 + g, 4, frameColor, M.Wood)
			House3DKit.Frame(b, 0, 11, 3.3 + g, 78, 78, 1.2, 1.4 + 2 * g, GOLD, M.Metal)
			local cover = b.Box(0, 12.2, 4, 75.6, 75.6, 0.4, rgb(230, 240, 255), M.Glass)
			cover.Transparency = 0.88
			cover.Reflectance = 0.2
			cover.CastShadow = false
			if kind == "Calendar" then
				-- anneaux de reliure + clou
				for _, x in ipairs({ -24, -8, 8, 24 }) do
					b.CylX(x, 93, 3.4, 4, 2.4, GREY, M.Metal)
				end
				b.Cyl(0, 96, 1, 2, 3, GREY_DARK, M.Metal)
			end
		end
		b.Footprint(88, 3, 100)
	end
end
R.FramedPicture = plaque("Frame")
R.MapPoster = plaque("Poster")
R.WallCalendar = plaque("Calendar")

-- ÉLECTRONIQUE -----------------------------------------------------------

-- Écran allumé (face avant +z) : dalle lumineuse douce
local function screen(b: Builder, x: number, y: number, z: number, w: number, h: number, color: Color3)
	local panel = b.Box(x, y, z, w, h, 1, color, M.SmoothPlastic)
	b.Neon(panel)
	panel.Color = color
	return panel
end
R.RetroTV = function(b, ctx)
	local top = ctx.TopY(1, 77)
	local body = accent(b, 1, rgb(255, 170, 190))
	local g = House3DKit.Gap(b, 0.8)
	-- télé cathodique : pieds évasés, caisse aux coins arrondis, tube bombé,
	-- cadre, grille du haut-parleur, bouton de chaînes, antenne "oreilles de lapin"
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(sx * 30, 5, sz * 16) * CFrame.Angles(-sz * 0.15, 0, sx * 0.15), 3.4, 11, 3.4, INK, M.Wood)
		end
	end
	b.Round(0, 10, 0, 90, top - 10, 50, 6, body, M.SmoothPlastic)
	b.Box(-10, 17, 25 + g / 2, 60, top - 28, g, darken(body, 0.35), M.SmoothPlastic)
	screen(b, -10, 21, 25.5 + g, 52, top - 36, rgb(120, 180, 255))
	local bulge = b.EggR(CFrame.new(-10, 21 + (top - 36) / 2, 25 + g * 2), 52, top - 36, 3, rgb(200, 230, 255), M.Glass)
	bulge.Transparency = 0.75
	bulge.Reflectance = 0.2
	bulge.CastShadow = false
	-- grille + boutons
	for index = 0, 4 do
		b.Box(30, 16 + index * 3, 25 + g / 2, 16, 1.2, g, darken(body, 0.45), M.SmoothPlastic)
	end
	for index = 1, 2 do
		b.CylZ(30, 30 + index * 12, 25 + g, 8, 2, INK, M.SmoothPlastic)
		b.Box(30, 32 + index * 12, 25 + 2.2 * g, 1, 3, 0.6, WHITE, M.SmoothPlastic)
	end
	-- antenne
	b.Egg(0, top, -6, 12, 6, 10, INK, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		local tip = { side * 16, top + 30, -8 }
		b.Tube(side * 2, top + 2, -6, tip[1], tip[2], tip[3], 1.4, CHROME_METAL, M.Metal).Reflectance = 0.35
		b.Ball(tip[1], tip[2], tip[3], 2.4, CHROME_METAL, M.Metal)
	end
	b.Top(1, 0, top, 0, 80, 44)
	b.Footprint(90, 50, top)
end
R.HomeCinema = function(b, _ctx)
	local wood = woodOf(b, WOOD_DARK)
	local g = House3DKit.Gap(b, 0.8)
	-- meuble bas à 3 niches, TV extra-plate sur pied, barre de son, 2 enceintes
	-- colonnes à haut-parleurs
	b.Box(0, 0, 0, 100, 18, 30, wood, M.Wood)
	b.Box(0, 0, 0, 94, 1.6, 26, darken(wood, 0.4), M.Wood)
	for _, x in ipairs({ -30, 0, 30 }) do
		b.Box(x, 3, 15 + g / 2, 26, 12, g, darken(wood, 0.35), M.Wood)
		b.Box(x, 4, 15 + 1.5 * g, 24, 3, g, rgb(40, 40, 50), M.SmoothPlastic)
	end
	b.Box(0, 18, -4, 16, 2, 10, GREY_DARK, M.Metal).Reflectance = 0.25
	b.Box(0, 20, -4, 5, 9, 3, GREY_DARK, M.Metal)
	b.Box(0, 28, -4, 96, 56, 2.4, INK, M.SmoothPlastic)
	screen(b, 0, 29.5, -2.8 + g, 92, 53, accent(b, 1, rgb(140, 190, 255)))
	b.Box(0, 18, 8, 50, 5, 7, rgb(40, 40, 50), M.Fabric) -- barre de son
	for _, side in ipairs({ -1, 1 }) do
		local sx = side * 44
		b.Box(sx, 18, 6, 12, 30, 12, INK, M.SmoothPlastic)
		for index, y in ipairs({ 24, 34, 43 }) do
			local d = index == 3 and 4 or 8
			b.CylZ(sx, y, 12 + g / 2, d + 1.6, g, GREY_DARK, M.Metal)
			b.CylZ(sx, y, 12 + 1.5 * g, d, g, rgb(60, 60, 72), M.SmoothPlastic)
			b.CylZ(sx, y, 12 + 2.5 * g, d * 0.35, g, GREY, M.Metal)
		end
	end
	b.Top(1, 0, 18, 8, 70, 14)
	b.Footprint(100, 30, 84)
end
R.DesktopPC = function(b, _ctx)
	local color = accent(b, 1, rgb(230, 230, 245))
	local g = House3DKit.Gap(b, 0.8)
	-- écran à bords fins sur pied (col + socle), clavier à rangées de touches,
	-- souris sur tapis, tour avec façade, lecteur, LED
	b.Box(-8, 0, -4, 24, 2, 16, color, M.SmoothPlastic)
	b.Box(-8, 2, -6, 5, 18, 3, darken(color, 0.1), M.SmoothPlastic)
	b.Box(-8, 20, -4, 70, 46, 3, darken(color, 0.25), M.SmoothPlastic)
	screen(b, -8, 22, -2.5 + g, 66, 42, rgb(150, 210, 255))
	-- clavier
	b.BoxR(CFrame.new(-8, 1.4, 20) * CFrame.Angles(0.06, 0, 0), 56, 2.4, 16, lighten(color, 0.2), M.SmoothPlastic)
	for row = 0, 3 do
		b.BoxR(CFrame.new(-8, 2.9 + row * 0.24, 14.5 + row * 3.4) * CFrame.Angles(0.06, 0, 0), 50 - (row == 3 and 20 or 0), 1, 2.6, lighten(color, 0.35), M.SmoothPlastic)
	end
	b.Box(26, 0, 22, 14, 0.6, 12, accent(b, 2, PINK), M.Fabric)
	b.Egg(26, 1.8, 22, 5, 3.4, 8, WHITE, M.SmoothPlastic)
	-- tour
	b.Box(36, 0, 0, 18, 56, 40, darken(color, 0.08))
	b.Box(36, 4, 20 + g / 2, 14, 48, g, darken(color, 0.16), M.SmoothPlastic)
	b.Box(36, 40, 20 + g, 12, 3, g, rgb(60, 60, 72), M.SmoothPlastic)
	for index = 0, 5 do
		b.Box(36, 8 + index * 3, 20 + g, 12, 1, g, darken(color, 0.3), M.SmoothPlastic)
	end
	local led = b.Box(36, 48, 20 + 1.5 * g, 8, 2, g, accent(b, 2, MINT))
	b.Neon(led)
	b.Footprint(90, 40, 66)
end
R.Laptop = function(b, _ctx)
	local color = accent(b, 1, rgb(230, 225, 245))
	local g = House3DKit.Gap(b, 0.8)
	-- ordinateur portable : coque, touches en rangées, pavé tactile, charnière,
	-- couvercle incliné à bords fins, logo au dos
	b.Round(0, 0, 8, 80, 4, 50, 3, color, M.SmoothPlastic)
	b.Box(0, 4 - g, 3, 66, g * 2, 26, darken(color, 0.3), M.SmoothPlastic)
	for row = 0, 4 do
		b.Box(0, 4, -8 + row * 5, 62 - (row == 4 and 26 or 0), g, 3.8, lighten(color, 0.15), M.SmoothPlastic)
	end
	b.Box(0, 4 - g / 2, 24, 24, g, 12, darken(color, 0.08), M.SmoothPlastic)
	b.CylX(0, 3.4, -17, 3, 70, darken(color, 0.2), M.Metal)
	local lid = b.BoxR(CFrame.new(0, 24, -17) * CFrame.Angles(-0.25, 0, 0), 80, 46, 3, color, M.SmoothPlastic)
	lid.Name = "Couvercle"
	b.BoxR(CFrame.new(0, 24, -17) * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 0, 1.5 + g / 2), 76, 42, g, rgb(30, 30, 40), M.SmoothPlastic)
	local panel = b.BoxR(CFrame.new(0, 24.6, -17) * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 0, 1.5 + g), 72, 38, 0.6, rgb(150, 200, 255), M.Neon)
	table.insert(b.Glows, panel)
	House3DKit.Heart(b, 0, 22, -20.2, 8, 0.8, lighten(color, 0.4), M.SmoothPlastic)
	b.Footprint(80, 56, 48)
end
R.ArcadeMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(160, 110, 230))
	local g = House3DKit.Gap(b, 0.8)
	-- borne d'arcade : flancs décorés, plateau de commande incliné (joystick à
	-- boule, boutons), écran encastré, fronton lumineux, trappe à pièces
	b.Box(0, 0, -2, 60, 100, 46, darken(body, 0.2), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 31, 0, 0, 2.4, 100, 50, body, M.SmoothPlastic)
		b.Box(side * (32.2 + g / 2), 10, 4, g, 30, 30, accent(b, 2, rgb(120, 230, 255)), M.SmoothPlastic)
		House3DKit.StarSoft(b, side * (32.2 + g), 70, 0, 6, 1, BUTTER, M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(0, 48, 26) * CFrame.Angles(0.25, 0, 0), 60, 6, 16, darken(body, 0.15), M.SmoothPlastic)
	b.Cyl(-18, 50, 27, 2, 7, INK, M.Metal)
	b.Ball(-18, 57.4, 27, 5, rgb(255, 80, 100), M.SmoothPlastic)
	for index = 1, 4 do
		local c = ({ PINK, BUTTER, MINT, SKY })[index]
		b.Cyl(-6 + index * 7, 50.6 + index * 0.1, 28 - (index % 2) * 3, 5, 1.4, c, M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(0, 72, 20) * CFrame.Angles(-0.2, 0, 0), 56, 34, 4, INK, M.SmoothPlastic)
	screen(b, 0, 58, 22.6 + g, 48, 28, accent(b, 2, rgb(120, 230, 255)))
	local marquee = b.Box(0, 90, 20 + g, 58, 8, 1, BUTTER)
	b.Neon(marquee)
	b.Box(0, 12, 21 + g / 2, 20, 20, g, darken(body, 0.35), M.Metal)
	for _, x in ipairs({ -4, 4 }) do
		b.Box(x, 24, 21 + g, 3, 5, g, rgb(255, 200, 80), M.SmoothPlastic)
	end
	b.Footprint(64, 64, 100)
end
R.SlotMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 120, 140))
	local g = House3DKit.Gap(b, 0.8)
	-- machine à sous : caisse arrondie, vitre des rouleaux (3 rouleaux aux
	-- symboles), ligne gagnante, bac à pièces, levier à boule, gyrophare
	b.Round(0, 0, 0, 64, 90, 44, 5, body, M.SmoothPlastic)
	b.Box(0, 42, 22 + g / 2, 54, 30, g, GOLD, M.Metal).Reflectance = 0.25
	b.Box(0, 44, 22 + 1.5 * g, 50, 26, g, WHITE, M.SmoothPlastic)
	for index = 0, 2 do
		local x = -16 + index * 16
		b.CylX(x, 57, 21, 20, 13, WHITE, M.SmoothPlastic)
		local sym = ({ PINK, BUTTER, MINT })[index + 1]
		b.Box(x, 53.6, 22 + 2.5 * g, 8, 7, g, sym, M.SmoothPlastic)
	end
	b.Box(0, 56.4, 22 + 3.5 * g, 50, 0.8, g, rgb(255, 60, 80), M.SmoothPlastic)
	b.Box(0, 14, 22 + 2 * g, 36, 8, 8, darken(GOLD, 0.2), M.Metal)
	for index = 0, 4 do
		b.CylZ(-10 + index * 5, 21, 22 + 3 * g, 4, 1, GOLD, M.Metal)
	end
	b.CylX(36, 64, 0, 4, 10, GREY, M.Metal)
	b.Box(40, 64, 0, 3, 24, 3, CHROME_METAL, M.Metal).Reflectance = 0.35
	b.Ball(40, 90, 0, 10, rgb(255, 80, 100))
	local top = b.Box(0, 90, 0, 60, 8, 40, GOLD, M.Metal)
	top.Name = "Haut"
	local beacon = b.Egg(0, 99, 0, 12, 8, 12, rgb(255, 120, 80))
	b.Neon(beacon)
	b.Footprint(70, 44, 100)
end
R.Speaker = function(b, _ctx)
	local body = accent(b, 1, INK)
	local g = House3DKit.Gap(b, 0.8)
	-- enceinte colonne : caisse biseautée, boomer (membrane, cache-noyau),
	-- tweeter à dôme, évent, pointes de découplage
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 22, 0, sz * 18, 3, 3, CHROME_METAL, M.Metal).Reflectance = 0.3
		end
	end
	House3DKit.Bevel(b, 0, 3, 0, 56, 93, 46, 2, body, M.Wood)
	b.Box(0, 6, 23 + g / 2, 50, 86, g, darken(body, 0.25), M.SmoothPlastic)
	b.CylZ(0, 34, 23 + 1.5 * g, 38, g, GREY_DARK, M.Metal)
	b.CylZ(0, 34, 23 + 2.5 * g, 32, g, rgb(40, 40, 48), M.SmoothPlastic)
	b.Egg(0, 34, 23 + 3 * g, 12, 12, 4, GREY, M.Metal)
	b.CylZ(0, 70, 23 + 1.5 * g, 22, g, GREY_DARK, M.Metal)
	b.Egg(0, 70, 23 + 2 * g, 10, 10, 4, CHROME_METAL, M.Metal).Reflectance = 0.3
	b.CylZ(0, 9, 23 + g, 10, g * 2, rgb(20, 20, 26), M.SmoothPlastic)
	b.Top(1, 0, 96, 0, 50, 40)
	b.Footprint(56, 46, 96)
end
R.GrandPiano = function(b, _ctx)
	local body = accent(b, 1, rgb(60, 50, 80))
	-- piano à queue : caisse galbée (arrondi de la queue), couvercle ouvert
	-- sur sa béquille, clavier blanc + touches noires, pupitre, pieds tournés
	-- à roulettes, lyre et pédales
	local shine = function(part: BasePart)
		part.Reflectance = 0.12
	end
	for _, spec in ipairs({ { -36, 10 }, { 36, 10 }, { 0, -24 } }) do
		b.Cyl(spec[1], 3, spec[2], 7, 37, body, M.SmoothPlastic)
		b.Cyl(spec[1], 12, spec[2], 9, 3, GOLD, M.Metal)
		b.Ball(spec[1], 2, spec[2], 5, GOLD, M.Metal)
	end
	shine(b.Box(0, 40, 4, 90, 18, 46, body, M.SmoothPlastic))
	shine(b.Cyl(20, 40, -18, 50, 18, body, M.SmoothPlastic))
	shine(b.Box(-20, 40, -24, 50, 18, 12, body, M.SmoothPlastic))
	-- clavier
	b.Box(0, 50, 30, 84, 3, 12, body, M.SmoothPlastic)
	b.Box(0, 53, 30, 80, 2, 10, WHITE, M.SmoothPlastic)
	for index = 0, 13 do
		if index % 7 ~= 2 and index % 7 ~= 6 then
			b.Box(-37.5 + index * 5.7, 55, 28, 3, 1.6, 6, INK, M.SmoothPlastic)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 42, 50, 30, 3, 8, 12, body, M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(0, 64, 22) * CFrame.Angles(-0.2, 0, 0), 50, 12, 1.6, body, M.SmoothPlastic) -- pupitre
	-- couvercle levé + béquille
	shine(b.BoxR(CFrame.new(-4, 74, -8) * CFrame.Angles(-0.55, 0, 0), 86, 2, 60, body))
	b.Tube(30, 58, 8, 30, 76, -2, 1.4, darken(body, 0.2), M.Wood)
	-- lyre + pédales
	b.Box(0, 4, 20, 8, 36, 3, body, M.SmoothPlastic)
	for _, x in ipairs({ -3, 0, 3 }) do
		b.Box(x, 6, 23, 1.6, 1, 4, GOLD, M.Metal)
	end
	b.Footprint(92, 72, 90)
end
R.Telescope = function(b, _ctx)
	local metal = b.Map(GREY_DARK)
	local wood = woodOf(b, WOOD)
	-- trépied en bois (tablette à oculaires), monture, tube optique rond,
	-- pare-buée, chercheur, porte-oculaire et molette
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.Tube(math.cos(angle) * 24, 0, math.sin(angle) * 24, 0, 60, 0, 3.2, wood, M.Wood)
		b.Tube(math.cos(angle) * 10, 30, math.sin(angle) * 10, 0, 30, 0, 1.4, GREY, M.Metal)
	end
	b.Cyl(0, 29, 0, 16, 1.4, wood, M.Wood)
	b.Ball(0, 62, 0, 8, metal, M.Metal)
	b.Box(0, 60, 0, 10, 8, 10, metal, M.Metal)
	local body = accent(b, 1, rgb(90, 110, 200))
	local axis = Vector3.new(math.cos(0.55), math.sin(0.55), 0)
	local c = Vector3.new(4, 72, 0)
	local p0, p1 = c - axis * 30, c + axis * 30
	local tube = b.Tube(p0.X, p0.Y, 0, p1.X, p1.Y, 0, 12, body, M.SmoothPlastic)
	tube.Name = "Tube"
	tube.Reflectance = 0.1
	local d1 = p1 + axis * 6
	b.Tube(p1.X, p1.Y, 0, d1.X, d1.Y, 0, 13.4, darken(body, 0.3), M.SmoothPlastic)
	b.Tube(p0.X, p0.Y, 0, (p0 - axis * 3).X, (p0 - axis * 3).Y, 0, 13, GOLD, M.Metal)
	local e0 = p0 + axis * 6 + Vector3.new(0, 7, 0)
	b.Tube(e0.X, e0.Y, 0, e0.X - 2, e0.Y + 7, 0, 3, GREY, M.Metal)
	local f0, f1 = c + Vector3.new(0, 8, 4), c + Vector3.new(0, 8, 4) + axis * 16
	b.Tube(f0.X, f0.Y, f0.Z, f1.X, f1.Y, f1.Z, 3.4, GREY_DARK, M.Metal)
	b.CylZ(-16, 60, 6, 5, 3, GOLD, M.Metal)
	b.Footprint(60, 40, 96)
end
R.RecordPlayer = function(b, ctx)
	local wood = woodOf(b, WOOD)
	-- gramophone : caisse biseautée, plateau chromé, disque (sillons, étiquette),
	-- bras de lecture, grand pavillon évasé doré
	local g = House3DKit.Gap(b, 0.8)
	House3DKit.Bevel(b, 0, 0, 0, 90, 26, 60, 2, wood, M.Wood)
	b.Box(0, 8, 30 + g / 2, 70, 12, g, darken(wood, 0.2), M.Wood)
	b.CylZ(38, 14, 30 + g, 5, 3, GOLD, M.Metal)
	b.Cyl(-8, 26, 0, 54, 1.4, CHROME_METAL, M.Metal).Reflectance = 0.3
	local r0 = 27.4
	b.Cyl(-8, r0, 0, 52, g, INK)
	b.Cyl(-8, r0 + g / 2, 0, 44, 1.5 * g, rgb(50, 44, 60))
	b.Cyl(-8, r0 + g, 0, 14, 2 * g, accent(b, 1, PINK))
	b.Cyl(-8, r0 + g, 0, 2, 3 * g + 1, CHROME_METAL, M.Metal)
	b.Cyl(22, 26, 18, 6, 4, GREY_DARK, M.Metal)
	b.Tube(22, 30, 18, 4, 30, -2, 2, CHROME_METAL, M.Metal).Reflectance = 0.3
	b.Box(3, 28.4, -3, 4, 2, 5, INK, M.Metal)
	-- pavillon (sections qui s'évasent)
	local horn = b.Cyl(30, 26, -20, 10, 14, GOLD, M.Metal)
	horn.Name = "Pavillon"
	for index = 0, 3 do
		b.Tube(30, 40 + index * 5, -20, 30, 45 + index * 5, -20 - index * 1.5, 12 + index * 6, GOLD, M.Metal).Reflectance = 0.25
	end
	b.CylZ(30, 62, -26, 32, 2, darken(GOLD, 0.35), M.Metal)
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
	local g = House3DKit.Gap(b, 0.8)
	-- manteau de pierre, pilastres, foyer en briques sombres, âtre, bûches,
	-- flammes en couches, braises, pare-feu en laiton
	b.Box(0, 0, 0, w, top - 6, depth, stone, M.Brick)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 7), 4, depth / 2 + g / 2, 12, top - 14, g, lighten(stone, 0.08), M.Limestone)
		b.Box(side * (w / 2 - 7), 4, depth / 2 + g, 14, 5, g * 2, lighten(stone, 0.12), M.Limestone)
	end
	b.Box(0, top * 0.56 + 1, depth / 2 + g / 2, w * 0.66, 7, g, lighten(stone, 0.1), M.Limestone)
	b.Box(0, 0, depth / 2 - 2, w * 0.56, top * 0.56, 6, rgb(60, 40, 50), M.SmoothPlastic)
	b.Box(0, 4, depth / 2 - 6, w * 0.5, top * 0.5, 2, rgb(90, 50, 44), M.Brick)
	b.Box(0, 0, depth / 2 + 2, w + 6, 4, 10, darken(stone, 0.1), M.Slate)
	-- bûches et flammes
	for index = -1, 1 do
		b.CylX(index * 8, 5, depth / 2, 6, 26, WOOD_DARK, M.Wood)
	end
	b.CylZ(0, 9, depth / 2, 5, 10, darken(WOOD_DARK, 0.2), M.Wood)
	local ember = b.Box(0, 3.4, depth / 2, 26, 1.6, 8, rgb(255, 110, 50))
	b.Neon(ember)
	local flames = { FIRE, rgb(255, 200, 80), rgb(255, 110, 70) }
	for index = 1, 3 do
		local flame = b.Egg(-12 + index * 6, 16 + (index % 2) * 4, depth / 2, 10 - (index % 2) * 3, 18 - (index % 2) * 5, 8, flames[index])
		b.Neon(flame)
		if index == 2 then
			b.Light(flame, rgb(255, 160, 90), 18, 1)
		end
	end
	local core = b.Egg(0, 13, depth / 2 + 1, 6, 10, 5, rgb(255, 240, 170))
	b.Neon(core)
	-- pare-feu (cadre + barreaux)
	b.Box(0, 4, depth / 2 + 6, w * 0.5, 1.6, 1.6, BRASS, M.Metal)
	b.Box(0, 22, depth / 2 + 6, w * 0.5, 1.6, 1.6, BRASS, M.Metal)
	for index = -5, 5 do
		b.Box(index * 4.6, 5.6, depth / 2 + 6, 0.8, 16.4, 0.8, darken(BRASS, 0.2), M.Metal)
	end
	-- manteau (tablette en bois biseautée + corniche)
	local wood = woodOf(b, WOOD)
	House3DKit.Bevel(b, 0, top - 6, 2, w + 8, 6, depth + 6, 1.6, wood, M.Wood)
	cove(b, 0, top - 9, depth / 2, w - 4, 3, 2.4, 0, darken(wood, 0.1), M.Wood)
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

-- (v9.8) Fleur : tige, pétales ovales en couronne, cœur
local function flowerHead(b: Builder, x: number, y: number, z: number, size: number, petal: Color3, heart: Color3, petals: number)
	for index = 0, petals - 1 do
		local a = index / petals * math.pi * 2
		b.EggR(CFrame.new(x + math.cos(a) * size * 0.32, y, z + math.sin(a) * size * 0.32) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, 0.25), size * 0.5, size * 0.12, size * 0.3,
			vary(petal, index, 0.06), M.SmoothPlastic)
	end
	b.Ball(x, y + size * 0.04, z, size * 0.3, heart, M.SmoothPlastic)
end

-- (v9.8) Rosette de feuilles qui partent du centre du pot
local function rosette(b: Builder, y: number, count: number, length: number, width: number, green: Color3, seed: number)
	for index = 1, count do
		local a = index * 2.39996 + seed
		local up = -0.35 - (index % 3) * 0.25
		House3DKit.Leaf(b, math.cos(a) * 3, y + (index % 4) * 2, math.sin(a) * 3, length * (0.8 + (index % 3) * 0.12), width, math.atan2(math.cos(a), math.sin(a)), up,
			vary(index % 2 == 0 and green or darken(green, 0.12), index + seed, 0.1), darken(green, 0.3))
	end
end

local function smallPlant(flowers: boolean)
	return function(b: Builder, _ctx: Ctx)
		local green, potColor, flower = plantColors(b)
		pot(b, 56, 40, potColor)
		-- tiges + rosette de feuilles + touffe
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			b.Tube(0, 40, 0, math.cos(angle) * 12, 60 + (index % 2) * 6, math.sin(angle) * 10, 2.4, darken(green, 0.2), M.SmoothPlastic)
		end
		bush(b, 0, 64, 0, 36, green, 5)
		rosette(b, 44, 10, 22, 10, green, 1)
		if flowers then
			for index = 0, 4 do
				local angle = index / 5 * math.pi * 2 + 0.3
				local x, z = math.cos(angle) * 16, math.sin(angle) * 14
				flowerHead(b, x, 78 + (index % 2) * 8, z, 16, flower, BUTTER, 6)
			end
		end
		b.Footprint(56, 56, 90)
	end
end
-- (v9.8) Arbre en pot : tronc qui se divise en branches, bouquets de feuillage
-- au bout des branches ; version sapin : étages de rameaux retombants
local function tree(canopyColor: Color3?, round: boolean)
	return function(b: Builder, _ctx: Ctx)
		local green, potColor = plantColors(b)
		local canopy = canopyColor and House3DKit.Pick(b.Pal, function(h, s, v)
			return (h > 0.8 or h < 0.05) and s > 0.15 and v > 0.6
		end, b.Map(canopyColor)) or green
		local bark = woodOf(b, WOOD_DARK)
		pot(b, 34, 26, potColor)
		if round then
			b.Cyl(0, 22, 0, 7, 30, bark, M.Wood)
			for index, spec in ipairs({ { -14, 64, 6 }, { 14, 70, -4 }, { 2, 80, 2 }, { -6, 58, -10 } }) do
				b.Tube(0, 46 + index, 0, spec[1] * 0.8, spec[2] - 6, spec[3] * 0.8, 3.4 - index * 0.3, bark, M.Wood)
			end
			bush(b, 0, 74, 0, 40, canopy, 6)
			bush(b, -14, 62, 6, 24, canopy, 3)
			bush(b, 14, 66, -4, 22, vary(canopy, 3, 0.08), 3)
			if canopyColor then
				for index = 1, 8 do
					local a = index * 2.4
					b.Ball(math.cos(a) * 18, 70 + (index % 3) * 6, math.sin(a) * 16, 5, lighten(canopy, 0.35), M.SmoothPlastic)
				end
			end
		else
			b.Cyl(0, 22, 0, 6, 72, bark, M.Wood)
			for tier = 0, 4 do
				local y = 34 + tier * 13
				local len = 30 - tier * 5
				local n = 9 - tier
				for index = 1, n do
					local a = index / n * math.pi * 2 + tier * 0.4
					House3DKit.Leaf(b, 0, y + 10, 0, len, len * 0.55, math.atan2(math.cos(a), math.sin(a)), 0.55, vary(tier % 2 == 0 and canopy or darken(canopy, 0.1), index + tier * 9, 0.08))
				end
				b.Cyl(0, y, 0, len * 1.1, 10, darken(canopy, 0.12), M.SmoothPlastic)
			end
			b.Egg(0, 96, 0, 10, 10, 10, BUTTER)
			if canopyColor == nil and (b.Item and b.Item.Id == "HolidayTree") then
				-- boules, guirlande, étoile
				for index = 1, 10 do
					local a = index * 2.2
					local y = 38 + (index % 5) * 11
					local r = (30 - (y - 34) / 13 * 5) * 0.55
					b.Ball(math.cos(a) * r, y, math.sin(a) * r, 4.4, ({ rgb(255, 80, 100), BUTTER, SKY, PINK })[index % 4 + 1], M.SmoothPlastic).Reflectance = 0.3
				end
				local star = b.Egg(0, 99, 0, 9, 9, 3, rgb(255, 214, 90))
				b.Neon(star)
			end
		end
		b.Footprint(60, 60, 100)
	end
end
R.PottedPlant = smallPlant(false)
R.Monstera = function(b, _ctx)
	local green, potColor = plantColors(b)
	pot(b, 40, 34, potColor)
	-- grandes feuilles découpées sur longues tiges arquées, nervure centrale
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2 + (index % 2) * 0.3
		local reach = 14 + (index % 3) * 5
		local tip = Vector3.new(math.cos(angle) * reach, 56 + (index % 3) * 10, math.sin(angle) * reach * 0.8)
		b.Tube(0, 32, 0, tip.X * 0.7, tip.Y - 4, tip.Z * 0.7, 2, darken(green, 0.3), M.SmoothPlastic)
		local leaf = House3DKit.Leaf(b, tip.X * 0.7, tip.Y - 4, tip.Z * 0.7, 26, 20, math.atan2(math.cos(angle), math.sin(angle)), 0.35,
			vary(index % 2 == 0 and green or darken(green, 0.15), index, 0.08), darken(green, 0.35))
		leaf.Name = "Feuille"
		-- découpes (fentes sombres) sur le bord de la feuille
		local cf = CFrame.new(tip.X * 0.7, tip.Y - 4, tip.Z * 0.7) * CFrame.Angles(0, math.atan2(math.cos(angle), math.sin(angle)), 0) * CFrame.Angles(0.35, 0, 0)
		for _, side in ipairs({ -1, 1 }) do
			b.BoxR(cf * CFrame.new(side * 7, 0.6, 14), 5, 0.6, 1.4, darken(green, 0.45), M.SmoothPlastic)
		end
	end
	b.Footprint(70, 60, 90)
end
R.Sprout = smallPlant(false)
R.TinyCactus = function(b, _ctx)
	local green, potColor, flower = plantColors(b)
	pot(b, 56, 40, potColor)
	-- cactus à côtes, bras, épines, fleur, cailloux blancs
	b.Cyl(0, 36, 0, 26, 40, green, M.SmoothPlastic)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		b.Cyl(math.cos(a) * 11, 36, math.sin(a) * 11, 6, 40, vary(darken(green, 0.08), index, 0.06), M.SmoothPlastic)
	end
	b.Ball(0, 76, 0, 26, green)
	b.Tube(-12, 52, 0, -20, 52, 0, 10, green, M.SmoothPlastic)
	b.Cyl(-20, 52, 0, 10, 14, green)
	b.Ball(-20, 66, 0, 10, green)
	for index = 0, 9 do
		local a = index * 2.3
		local y = 44 + (index % 5) * 7
		b.Tube(math.cos(a) * 13, y, math.sin(a) * 13, math.cos(a) * 16, y + 1.5, math.sin(a) * 16, 0.6, rgb(250, 246, 220), M.SmoothPlastic)
	end
	flowerHead(b, 0, 90, 0, 12, flower, BUTTER, 6)
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
	-- stipe annelé, palmes (rachis + folioles), noix de coco
	for index = 0, 5 do
		b.Cyl(index * 1.5, 20 + index * 11, 0, 9 - index * 0.4, 12, index % 2 == 0 and WOOD or WOOD_DARK, M.Wood)
		b.Cyl(index * 1.5, 30 + index * 11, 0, 10 - index * 0.4, 1.6, darken(WOOD_DARK, 0.2), M.Wood)
	end
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = Vector3.new(8, 88, 0)
		local tip = base + dir * 34 + Vector3.new(0, -12, 0)
		local mid = base + dir * 18 + Vector3.new(0, 4, 0)
		b.Tube(base.X, base.Y, base.Z, mid.X, mid.Y, mid.Z, 1.6, darken(green, 0.2), M.SmoothPlastic)
		b.Tube(mid.X, mid.Y, mid.Z, tip.X, tip.Y, tip.Z, 1.4, darken(green, 0.2), M.SmoothPlastic)
		local yaw = math.atan2(dir.X, dir.Z)
		for leaflet = 1, 4 do
			local p = base:Lerp(tip, leaflet / 5) + Vector3.new(0, leaflet == 1 and 3 or 0, 0)
			for _, side in ipairs({ -1, 1 }) do
				House3DKit.Leaf(b, p.X, p.Y, p.Z, 17 - leaflet * 2.4, 4.6, yaw + side * 1.15, 0.45, vary(green, index * 7 + leaflet, 0.1))
			end
		end
	end
	for index = 0, 2 do
		b.Ball(8 + math.cos(index * 2.1) * 4, 85, math.sin(index * 2.1) * 4, 7, rgb(140, 100, 70))
	end
	b.Footprint(70, 70, 100)
end
R.Bamboo = function(b, _ctx)
	local green, potColor = plantColors(b)
	-- jardinière rectangulaire (bord), cailloux, cannes à nœuds, feuilles fines
	House3DKit.Bevel(b, 0, 0, 0, 60, 22, 36, 1.4, potColor, M.SmoothPlastic)
	b.Box(0, 21.4, 0, 54, 1.2, 30, rgb(96, 70, 56), M.Ground)
	for index = 0, 4 do
		local x = -20 + index * 10
		local z = (index % 2) * 8 - 4
		local h = 70 + (index % 3) * 10
		b.Cyl(x, 22, z, 5, h, vary(green, index, 0.06), M.SmoothPlastic)
		for joint = 1, 3 do
			b.Cyl(x, 22 + joint * h / 4, z, 6, 1.2, darken(green, 0.25))
		end
		for leaf = 0, 2 do
			House3DKit.Leaf(b, x, 22 + h * (0.6 + leaf * 0.14), z, 16, 3.4, leaf * 2.2 + index, 0.2 + leaf * 0.15, lighten(green, 0.08 + leaf * 0.04))
		end
	end
	b.Footprint(60, 36, 100)
end
R.Sunflower = function(b, _ctx)
	local green, potColor = plantColors(b)
	pot(b, 46, 30, potColor)
	-- tige, grandes feuilles, cœur de graines, couronne de pétales
	b.Tube(0, 28, 0, 1, 80, 2, 4, green, M.SmoothPlastic)
	House3DKit.Leaf(b, 1, 46, 0, 18, 12, 1.5, -0.2, green, darken(green, 0.3))
	House3DKit.Leaf(b, 1, 58, 0, 16, 10, -1.6, -0.1, darken(green, 0.08), darken(green, 0.3))
	for index = 0, 13 do
		local a = index / 14 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 13, 82 + math.sin(a) * 13, 3) * CFrame.Angles(0, 0, a - math.pi / 2), 6, 13, 1.6, vary(rgb(255, 210, 60), index, 0.08), M.SmoothPlastic)
	end
	b.CylZ(0, 82, 4, 20, 4, rgb(120, 80, 50))
	b.CylZ(0, 82, 5.5 + House3DKit.Gap(b, 0.6) / 2, 12, 1 + House3DKit.Gap(b, 0.6), rgb(90, 60, 40))
	b.Footprint(46, 46, 100)
end
R.GiantMushroom = R.MushroomStool
R.Terrarium = function(b, _ctx)
	local green = greenOf(b, LEAF)
	-- terrarium : socle bois, sable et cailloux, mousse, mini plantes, cloche en
	-- verre à bouton
	b.Cyl(0, 0, 0, 60, 8, woodOf(b, WOOD), M.Wood)
	b.Cyl(0, 8, 0, 56, 2, rgb(236, 214, 170), M.Sand)
	for index = 0, 4 do
		local a = index * 1.3
		b.Egg(math.cos(a) * 18, 10, math.sin(a) * 18, 7, 4, 6, rgb(200, 196, 204), M.Slate)
	end
	b.Egg(-6, 12, 4, 26, 8, 22, darken(green, 0.15), M.Grass)
	bush(b, 6, 20, -4, 22, green, 3)
	rosette(b, 12, 6, 10, 5, lighten(green, 0.1), 3)
	local dome = b.Ball(0, 36, 0, 64, GLASS, M.Glass)
	dome.Transparency = 0.55
	dome.Reflectance = 0.15
	dome.CastShadow = false
	b.Ball(0, 68, 0, 6, woodOf(b, WOOD), M.Wood)
	b.Footprint(64, 64, 70)
end

-- TAPIS ----------------------------------------------------------------------

-- (v9.8) Tapis : fond, bordure en frise, médaillon central, franges en
-- houppes (couches espacées pour ne pas scintiller)
local function rug(b: Builder, _ctx: Ctx)
	local main = accent(b, 1, PINK)
	local second = accent(b, 2, lighten(main, 0.35))
	local g = House3DKit.Gap(b, 0.4)
	b.Box(0, 0, 0, 100, 0.8, 68, main, M.Fabric)
	b.Box(0, 0.8, 0, 88, g, 58, second, M.Fabric)
	b.Box(0, 0.8 + g, 0, 80, g, 50, main, M.Fabric)
	b.Box(0, 0.8 + 2 * g, 0, 44, g, 26, lighten(main, 0.2), M.Fabric)
	b.EggR(CFrame.new(0, 0.8 + 2 * g, 0), 30, 2 * g, 18, second, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for index = 0, 4 do
			b.Box(sx * (18 + index * 4.4), 0.8 + 2 * g, 0, 2, g, 6 + (index % 2) * 4, lighten(second, 0.2), M.Fabric)
		end
	end
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

-- (v9.8) Porte à 6 panneaux moulurés : chambranle, huisserie, paumelles,
-- béquille + rosace, seuil
local function door(b: Builder, ctx: Ctx)
	local panel = accent(b, 1, rgb(255, 180, 200))
	local frame = ctx.Trim
	local g = House3DKit.Gap(b, 0.8)
	b.Box(-36, 0, 0, 6, 96, 6, frame, M.Wood)
	b.Box(36, 0, 0, 6, 96, 6, frame, M.Wood)
	b.Box(0, 96, 0, 78, 6, 6, frame, M.Wood)
	b.Box(0, 102, 0.5, 82, 2, 7, lighten(frame, 0.08), M.Wood)
	b.Box(0, 0, -1, 66, 96, 3, panel, M.Wood)
	for _, spec in ipairs({ { 12, 26 }, { 42, 30 }, { 76, 16 } }) do
		for _, sx in ipairs({ -1, 1 }) do
			b.Box(sx * 15, spec[1], 0.5 + g / 2, 24, spec[2], g, darken(panel, 0.1), M.Wood)
			b.Box(sx * 15, spec[1] + 2, 0.5 + g, 20, spec[2] - 4, g, lighten(panel, 0.14), M.Wood)
		end
	end
	for _, y in ipairs({ 14, 80 }) do
		b.Box(-32.4, y, 0.5, 1.6, 8, 1.6, BRASS, M.Metal)
	end
	b.CylZ(24, 48, 0.5 + g, 5, g, BRASS, M.Metal)
	b.Tube(24, 48, 0.5 + 2.4 * g, 18, 48, 0.5 + 2.4 * g, 1.6, BRASS, M.Metal).Reflectance = 0.35
	b.CylZ(24, 48, 0.5 + 1.2 * g, 1.6, 2.4 * g, BRASS, M.Metal)
	b.Box(0, 0, 4, 60, 1, 8, darken(panel, 0.2))
	b.Footprint(84, 8, 102)
end
R.ToriiGate = function(b, _ctx)
	local red = accent(b, 1, rgb(230, 70, 70))
	-- torii : piliers sur socles de pierre, nuki, kasagi aux pointes relevées,
	-- plaque centrale
	for _, x in ipairs({ -34, 34 }) do
		b.Cyl(x, 0, 0, 9, 90, red, M.Wood)
		b.Cyl(x, 0, 0, 12, 6, INK)
		b.Cyl(x, 6, 0, 10.4, 2, darken(INK, 0.2))
	end
	b.Box(0, 70, 0, 84, 6, 6, red, M.Wood)
	b.Box(0, 88, 0, 104, 6, 10, red, M.Wood)
	b.Box(0, 94, 0, 100, 4, 12, INK, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Wedge(side * 52, 94, 0, 4, 5, 12, INK, side > 0 and "Left" or "Right", M.Wood)
	end
	b.Box(0, 76, 0, 12, 12, 3, INK)
	b.Box(0, 78, 1.6, 8, 8, 0.6, GOLD, M.Metal)
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
	local g = House3DKit.Gap(b, 0.8)
	-- niche : socle, bardage en lames, porte en arche (bordure), toit à
	-- débords et faîtage, plaque au nom, gamelle devant
	b.Box(0, 0, 0, 84, 4, 68, darken(wall, 0.3), M.Wood)
	for index = 0, 6 do
		b.Box(0, 4 + index * 7.4, 0, 80, 7.4, 64, vary(wall, index, 0.05), M.WoodPlanks)
	end
	b.Box(0, 4, 32 - 0.6 + g / 4, 30, 30, 1.2 + g / 2, rgb(50, 32, 40))
	b.CylZ(0, 34, 32 - 0.6 + g / 4, 30, 1.2 + g / 2, rgb(50, 32, 40))
	b.Box(-16, 4, 32 + 0.75 * g, 3, 30, 1.5 * g, lighten(wall, 0.25), M.Wood)
	b.Box(16, 4, 32 + 0.75 * g, 3, 30, 1.5 * g, lighten(wall, 0.25), M.Wood)
	b.Wedge(-21, 56, 0, 44, 26, 72, roof, "Left", M.RoofShingles)
	b.Wedge(21, 56, 0, 44, 26, 72, roof, "Right", M.RoofShingles)
	b.CylZ(0, 81, 0, 4, 74, darken(roof, 0.25), M.Wood)
	b.Box(0, 40, 32 + 0.75 * g, 24, 7, 1.5 * g, lightOf(b, CREAM), M.Wood)
	House3DKit.Heart(b, 0, 43.5, 32 + 1.5 * g, 4, 0.6, accent(b, 3, PINK), M.SmoothPlastic)
	b.Cyl(30, 0, 36, 14, 5, accent(b, 3, SKY), M.SmoothPlastic)
	b.Cyl(30, 4, 36, 11, 1 + g, rgb(160, 110, 70), M.Pebble)
	b.Footprint(84, 70, 82)
end
R.ScratchingPost = function(b, _ctx)
	local base = accent(b, 1, rgb(200, 170, 240))
	-- griffoir : socle moquette, poteau en corde de sisal (spires), plateau,
	-- balle au bout d'un ressort
	b.Round(0, 0, 0, 70, 8, 60, 6, base, M.Fabric)
	b.Cyl(0, 8, 0, 20, 70, rgb(222, 190, 140), M.Fabric)
	for index = 0, 9 do
		b.Cyl(0, 10 + index * 6.6, 0, 21, 1.6, rgb(200, 166, 116), M.Fabric)
	end
	b.Round(0, 78, 0, 50, 8, 44, 6, base, M.Fabric)
	b.Egg(0, 86, 0, 44, 3, 38, lighten(base, 0.1), M.Fabric)
	b.Cyl(20, 60, 10, 2, 16, INK)
	b.Ball(20, 58, 10, 8, accent(b, 2, PINK), M.Fabric)
	b.Top(1, 0, 86, 0, 44, 40)
	b.Footprint(70, 60, 86)
end
R.CatTree = function(b, _ctx)
	local base = accent(b, 1, rgb(200, 170, 240))
	local sisal = rgb(222, 190, 140)
	-- arbre à chat : socle, poteaux en sisal, plateformes moquettées, niche
	-- avec entrée ronde, hamac, pompon
	b.Round(0, 0, 0, 90, 8, 60, 6, base, M.Fabric)
	b.Cyl(-20, 8, 0, 14, 80, sisal, M.Fabric)
	b.Cyl(24, 8, 0, 14, 40, sisal, M.Fabric)
	for index = 0, 5 do
		b.Cyl(-20, 12 + index * 12, 0, 15, 1.2, darken(sisal, 0.12), M.Fabric)
	end
	b.Round(24, 48, 0, 40, 6, 36, 5, base, M.Fabric)
	b.Round(-20, 86, 0, 48, 6, 40, 5, base, M.Fabric)
	b.Round(-30, 8, 0, 30, 26, 36, 4, lighten(base, 0.1), M.Fabric)
	b.CylZ(-30, 20, 18, 16, 1.2, darken(base, 0.45), M.Fabric)
	b.Egg(24, 50, 0, 34, 6, 30, lighten(base, 0.2), M.Fabric)
	b.Cyl(8, 60, 16, 1, 18, INK)
	b.Ball(8, 58, 16, 6, accent(b, 2, PINK), M.Fabric)
	b.Top(1, -20, 92, 0, 40, 34)
	b.Footprint(90, 60, 92)
end
R.PetBowl = function(b, _ctx)
	local color = accent(b, 1, PINK)
	-- gamelle en céramique : pied, flanc évasé, rebord, croquettes, os dessiné
	b.Cyl(0, 0, 0, 64, 4, darken(color, 0.2), M.SmoothPlastic)
	b.Cyl(0, 4, 0, 74, 14, color, M.SmoothPlastic)
	b.Cyl(0, 18, 0, 80, 8, lighten(color, 0.1), M.SmoothPlastic)
	b.Cyl(0, 24, 0, 64, 2, rgb(190, 130, 90), M.Pebble)
	for index = 0, 9 do
		local a = index * 2.4
		b.Ball(math.cos(a) * (8 + index * 2), 26, math.sin(a) * (8 + index * 2), 6, vary(rgb(180, 120, 76), index, 0.12), M.SmoothPlastic)
	end
	b.Box(0, 10, 37, 18, 4, 1, WHITE, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		b.CylZ(sx * 9, 12, 37.2, 4, 1, WHITE, M.SmoothPlastic)
		b.CylZ(sx * 9, 8, 37.2, 4, 1, WHITE, M.SmoothPlastic)
	end
	b.Footprint(80, 80, 28)
end
R.PetToys = function(b, _ctx)
	-- panier à jouets : panier tressé, balle de tennis (couture), os, souris
	local basket = rgb(214, 170, 110)
	b.Box(0, 0, 0, 64, 14, 40, basket, M.Fabric)
	for index = 0, 2 do
		b.Box(0, 2 + index * 4.4, 0, 64.6, 1.4, 40.6, darken(basket, 0.15), M.Fabric)
	end
	b.Ball(-16, 16, 0, 22, accent(b, 1, rgb(210, 240, 90)), M.Fabric)
	b.Tube(-26, 18, 4, -6, 18, 4, 1, WHITE, M.Fabric)
	b.Ball(14, 16, 6, 16, accent(b, 2, BUTTER), M.Rubber)
	b.CylX(4, 12, -12, 5, 26, WHITE, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		b.Ball(4 + sx * 13, 12, -14, 6, WHITE, M.SmoothPlastic)
		b.Ball(4 + sx * 13, 12, -10, 6, WHITE, M.SmoothPlastic)
	end
	b.Egg(22, 16, -6, 14, 8, 8, GREY, M.Fabric)
	b.Tube(29, 16, -6, 36, 14, -2, 1, PINK, M.Fabric)
	b.Footprint(70, 50, 28)
end
R.Aquarium = function(b, ctx)
	local top = ctx.TopY(1, 84)
	local wood = woodOf(b, WOOD)
	-- aquarium sur meuble : portes, cuve à bords noirs, eau, sable, rochers,
	-- plantes ondulantes, poissons à nageoires, bulleur, rampe lumineuse
	cabinet(b, 94, 44, top * 0.35, wood, lighten(wood, 0.12), 0, 2, 0)
	local tankY = top * 0.35
	local tankH = top - tankY - 2
	local glass = b.Box(0, tankY, 0, 90, tankH, 40, GLASS, M.Glass)
	glass.Transparency = 0.55
	glass.Reflectance = 0.1
	glass.CastShadow = false
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (44.3 + House3DKit.Gap(b, 0.8) / 2), tankY, 0, 1.4 + House3DKit.Gap(b, 0.8), tankH, 40 + 2 * House3DKit.Gap(b, 0.8), INK, M.SmoothPlastic)
	end
	local water = b.Box(0, tankY + 2, 0, 86, tankH - 8, 36, rgb(130, 200, 250), M.Glass)
	water.Transparency = 0.4
	water.CastShadow = false
	b.Box(0, tankY, 0, 84, 4, 34, rgb(240, 220, 180), M.Sand)
	for index = 0, 2 do
		b.Egg(-30 + index * 26, tankY + 5, -10 + index * 4, 12, 8, 10, rgb(170, 160, 180), M.Slate)
	end
	for index = 0, 3 do
		local px = -34 + index * 20
		b.Tube(px, tankY + 3, -12, px + 3, tankY + 20 + index * 3, -13, 2.4, index % 2 == 0 and LEAF_DARK or LEAF)
		b.Tube(px + 3, tankY + 20 + index * 3, -13, px - 1, tankY + 30 + index * 2, -12, 2, LEAF)
	end
	for index = 1, 3 do
		local fc = ({ rgb(255, 150, 60), PINK, BUTTER })[index]
		local fx, fy, fz = -24 + index * 14, tankY + 12 + index * 5, (index % 2) * 10 - 5
		local fish = b.Egg(fx, fy, fz, 10, 6, 4, fc)
		fish.CastShadow = false
		b.Wedge(fx - 6, fy - 3, fz, 4, 6, 2, fc, "Left")
	end
	for index = 0, 3 do
		local bubble = b.Ball(34, tankY + 8 + index * 8, 8, 2 + index * 0.4, WHITE, M.Glass)
		bubble.Transparency = 0.4
	end
	b.Box(0, top - 2, 0, 94, 2, 44, darken(wood, 0.1), M.Wood)
	local lamp = b.Box(0, top - 2.6, 0, 70, 0.6, 6, rgb(220, 240, 255))
	b.Neon(lamp)
	b.Light(water, rgb(160, 220, 255), 10, 0.6)
	b.Top(1, 0, top, 0, 80, 36)
	b.Footprint(94, 44, top)
end
R.MiniAquarium = function(b, _ctx)
	critter("Fish")(b, _ctx)
end

-- DÉCO / TABLE / JOUETS (petits objets) -------------------------------------

-- (v9.8) Tasse / gobelet : corps céramique, lèvre, anse (ou paille + perles),
-- boisson, soucoupe
local function cup(straw: boolean)
	return function(b: Builder, _ctx: Ctx)
		local color = accent(b, 1, PINK)
		local drink = lightOf(b, rgb(255, 240, 230))
		if straw then
			local glass = b.Cyl(0, 0, 0, 50, 62, rgb(230, 244, 255), M.Glass)
			glass.Transparency = 0.45
			b.Cyl(0, 1, 0, 46, 50, color, M.SmoothPlastic)
			b.Cyl(0, 51, 0, 46, 2, drink, M.SmoothPlastic)
			b.Egg(0, 62, 0, 50, 10, 50, rgb(236, 244, 255), M.Glass).Transparency = 0.5
			b.BoxR(CFrame.new(6, 72, 0) * CFrame.Angles(0, 0, -0.25), 5, 38, 5, accent(b, 2, SKY))
			for index = 1, 7 do
				b.Ball(-14 + index * 4, 5 + (index % 2) * 3, ((index * 5) % 12) - 6, 7, INK)
			end
			b.Box(0, 24, 25.2, 20, 10, 0.6, WHITE, M.SmoothPlastic)
		else
			b.Cyl(0, 0, 0, 56, 2, lighten(color, 0.3), M.SmoothPlastic)
			b.Cyl(0, 2, 0, 44, 4, color, M.SmoothPlastic)
			local g = House3DKit.Gap(b, 0.6)
			b.Cyl(0, 6, 0, 50, 51, color, M.SmoothPlastic)
			b.Cyl(0, 56, 0, 44, 1 + g, rgb(140, 90, 60), M.SmoothPlastic)
			b.Egg(-6, 57 + g, 4, 10, 4, 8, WHITE, M.SmoothPlastic)
			b.Egg(6, 57 + g, -4, 8, 4, 8, rgb(255, 214, 230), M.SmoothPlastic)
			b.Tube(24, 48, 0, 34, 42, 0, 5, color, M.SmoothPlastic)
			b.Tube(34, 42, 0, 34, 26, 0, 5, color, M.SmoothPlastic)
			b.Tube(34, 26, 0, 24, 18, 0, 5, color, M.SmoothPlastic)
			House3DKit.Heart(b, 0, 32, 25, 12, 0.8, lighten(color, 0.5), M.SmoothPlastic)
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
	-- bol : pied, flanc évasé (gradins), liseré, contenu (fruits / légumes),
	-- baguettes posées en travers
	b.Cyl(0, 0, 0, 40, 4, darken(color, 0.12))
	b.Cyl(0, 4, 0, 66, 10, color)
	b.Cyl(0, 14, 0, 80, 12, color)
	b.Cyl(0, 26, 0, 86, 8, color)
	b.Cyl(0, 30, 0, 87, 2, accent(b, 3, rgb(120, 170, 230)))
	local fill = accent(b, 1, rgb(255, 200, 140))
	b.Cyl(0, 32, 0, 78, 4, fill)
	b.Ball(-14, 40, 4, 18, accent(b, 3, rgb(255, 150, 120)))
	b.Ball(12, 40, -6, 16, accent(b, 4, LEAF))
	b.Ball(2, 39, 14, 12, BUTTER)
	b.EggR(CFrame.new(-2, 37, -14), 14, 5, 9, lighten(fill, 0.3))
	b.Tube(-30, 44, 20, 34, 44, 6, 2.4, woodOf(b, WOOD), M.Wood)
	b.Tube(-30, 44, 24, 34, 44, 11, 2.4, woodOf(b, WOOD), M.Wood)
	b.Footprint(86, 86, 48)
end
R.RamenBowl = bowl
R.SaladBowl = bowl
R.FruitBowl = bowl
local function plate(b: Builder, _ctx: Ctx)
	local dish = lightOf(b, WHITE)
	-- assiette à marli (bord relevé) et filet, 4 bouchées garnies
	local g = House3DKit.Gap(b, 0.8)
	b.Cyl(0, 0, 0, 70, 2, darken(dish, 0.08))
	b.Cyl(0, 2, 0, 96, 3, dish)
	b.Cyl(0, 5, 0, 90, g, accent(b, 2, rgb(120, 170, 230)))
	b.Cyl(0, 5 + g / 2, 0, 82, 1.5 * g, lighten(dish, 0.1))
	local y0 = 5 + 2 * g
	for index = 0, 3 do
		local angle = index / 4 * math.pi * 2
		local c = accent(b, index % 3 + 1, rgb(255, 210, 160))
		local x, z = math.cos(angle) * 20, math.sin(angle) * 18
		b.Round(x, y0, z, 24, 10, 20, 4, c, M.SmoothPlastic)
		b.Egg(x, y0 + 10, z, 20, 5, 16, lighten(c, 0.25), M.SmoothPlastic)
		b.Ball(x + 4, y0 + 12, z, 5, rgb(255, 90, 100), M.SmoothPlastic)
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
		-- gâteau : présentoir à pied, étages (génoise), nappage qui coule,
		-- perles de crème, fraise + feuille au sommet
		b.Cyl(0, 0, 0, 40, 3, WHITE)
		b.Cyl(0, 3, 0, 14, 3, WHITE)
		b.Cyl(0, 6, 0, 90, 2, WHITE, M.SmoothPlastic).Reflectance = 0.1
		local y = 8
		for index = 1, tiers do
			local d = 78 - (index - 1) * 22
			local h = 40 / tiers + 6
			b.Cyl(0, y, 0, d, h, index % 2 == 1 and main or cream)
			b.Cyl(0, y + h - 3, 0, d + 2, 3, cream)
			for drip = 0, 7 do
				local a = drip / 8 * math.pi * 2 + index
				b.Egg(math.cos(a) * (d / 2 + 0.6), y + h - 4 - (drip % 3) * 1.6, math.sin(a) * (d / 2 + 0.6), 4, 6 + (drip % 3) * 3, 4, cream)
			end
			for bead = 0, 9 do
				local a = bead / 10 * math.pi * 2
				b.Ball(math.cos(a) * (d / 2 - 3), y + h + 0.6, math.sin(a) * (d / 2 - 3), 4.4, WHITE)
			end
			y += h
		end
		b.Egg(0, y + 5, 0, 13, 15, 13, rgb(240, 60, 80))
		b.Wedge(0, y + 11, 0, 6, 4, 6, LEAF, "Front")
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
	-- pyramide de macarons : plateau doré, étages de macarons (coques + crème)
	b.Cyl(0, 0, 0, 60, 4, GOLD, M.Metal).Reflectance = 0.3
	for index = 0, 5 do
		local r = 24 - index * 4
		local n = math.max(1, 8 - index)
		local y = 4 + index * 12
		b.Cyl(0, y, 0, r * 2, 10, lighten(colors[index % 4 + 1], 0.1))
		for m = 0, n - 1 do
			local a = m / n * math.pi * 2 + index * 0.3
			local c = colors[(index + m) % 4 + 1]
			local mx, mz = math.cos(a) * r, math.sin(a) * r
			b.Egg(mx, y + 2.4, mz, 10, 4.6, 10, c)
			b.Cyl(mx, y + 4, mz, 8.4, 2, WHITE)
			b.Egg(mx, y + 7.4, mz, 10, 4.6, 10, c)
		end
	end
	b.Footprint(60, 60, 80)
end
local function jar(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, rgb(255, 200, 120))
	-- bocal : verre épais, contenu, couvercle vissé (stries), tissu vichy
	-- noué, étiquette
	local glass = b.Cyl(0, 0, 0, 70, 66, GLASS, M.Glass)
	glass.Transparency = 0.45
	glass.Reflectance = 0.15
	b.Cyl(0, 2, 0, 62, 44, color)
	b.Cyl(0, 62, 0, 64, 6, lighten(GLASS, 0.1), M.Glass).Transparency = 0.3
	local lid = accent(b, 2, PINK)
	b.Cyl(0, 66, 0, 74, 8, lid)
	for index = 0, 2 do
		b.Cyl(0, 67.4 + index * 2.4, 0, 74 + 2 * House3DKit.Gap(b, 0.5), 0.8, darken(lid, 0.15))
	end
	b.Egg(0, 76, 0, 60, 6, 60, lighten(lid, 0.4), M.Fabric)
	b.Ball(0, 78, 0, 14, lid)
	b.Box(0, 22, 35.4, 30, 18, 0.8, WHITE, M.SmoothPlastic)
	b.Footprint(74, 74, 84)
end
R.CookieJar = jar
R.HoneyPot = jar
R.Teapot = function(b, _ctx)
	local color = accent(b, 1, rgb(160, 220, 255))
	-- théière : corps rond, pied, couvercle à bouton, bec en col-de-cygne,
	-- anse en boucle, petits motifs
	b.Cyl(0, 0, 0, 40, 6, darken(color, 0.1))
	b.Ball(0, 34, 0, 64, color)
	b.Cyl(0, 62, 0, 32, 4, lightOf(b, WHITE))
	b.Egg(0, 66, 0, 26, 8, 26, lightOf(b, WHITE))
	b.Ball(0, 72, 0, 10, accent(b, 2, PINK))
	b.Tube(28, 30, 0, 38, 44, 0, 8, color, M.SmoothPlastic)
	b.Tube(38, 44, 0, 44, 54, 0, 5, color, M.SmoothPlastic)
	b.Tube(-30, 50, 0, -42, 44, 0, 5, color, M.SmoothPlastic)
	b.Tube(-42, 44, 0, -40, 26, 0, 5, color, M.SmoothPlastic)
	b.Tube(-40, 26, 0, -30, 22, 0, 5, color, M.SmoothPlastic)
	for index = 0, 4 do
		local a = index / 5 * math.pi - math.pi / 2
		House3DKit.Heart(b, math.sin(a) * 26, 34, math.cos(a) * 26 + 5, 7, 0.6, WHITE, M.SmoothPlastic)
	end
	b.Footprint(90, 64, 76)
end
R.TeaSet = R.Teapot
R.Watermelon = function(b, _ctx)
	-- pastèque : écorce rayée, part découpée (chair rouge, pépins)
	b.Ball(0, 36, 0, 74, rgb(90, 180, 90))
	for index = 0, 5 do
		b.EggR(CFrame.new(0, 36, 0) * CFrame.Angles(0, index * math.pi / 6, 0), 75, 75, 5, rgb(60, 140, 70))
	end
	b.Wedge(24, 0, 30, 24, 22, 14, rgb(90, 180, 90), "Front")
	b.Wedge(24, 1.6, 30.6, 21, 19, 12, rgb(255, 90, 100), "Front")
	for index = 0, 2 do
		b.Egg(20 + index * 4, 7 + index * 2, 34 + index, 2, 3, 1, INK)
	end
	b.Footprint(74, 74, 74)
end
local function boxThing(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, PINK)
	-- coffret : boîte, couvercle qui déborde, ruban croisé, gros nœud (boucles
	-- et pans), étiquette
	b.Round(0, 0, 0, 84, 40, 60, 3, color, M.SmoothPlastic)
	b.Round(0, 40, 0, 88, 8, 64, 3, lighten(color, 0.2), M.SmoothPlastic)
	local ribbon = accent(b, 2, BUTTER)
	b.Box(0, 0, 0, 12, 49, 64.8, ribbon, M.Fabric)
	b.Box(0, 0, 0, 88.8, 49, 12, ribbon, M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * 9, 54, 0) * CFrame.Angles(0, 0, side * 0.4), 16, 9, 8, ribbon, M.Fabric)
		b.BoxR(CFrame.new(side * 6, 49.6, 10) * CFrame.Angles(0, side * 0.5, 0), 4, 1, 16, ribbon, M.Fabric)
	end
	b.Ball(0, 53, 0, 8, darken(ribbon, 0.1), M.Fabric)
	b.BoxR(CFrame.new(24, 36, 32.4) * CFrame.Angles(0, 0, 0.2), 12, 8, 0.8, WHITE, M.SmoothPlastic)
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
	-- pile de cadeaux : papiers (petits motifs), rubans croisés, nœuds à boucles
	for index, spec in ipairs(specs) do
		local x, y, z, s, h = spec[1], spec[2], spec[3], spec[4], spec[5]
		local c = colors[index]
		local g = House3DKit.Gap(b, 0.6)
		b.Box(x, y, z, s, h - 3, s * 0.9, c)
		b.Box(x, y + h - 3, z, s + 1, 3, s * 0.9 + 1, lighten(c, 0.15))
		b.Box(x, y, z, 6, h + g, s * 0.9 + 1 + 2 * g, BUTTER, M.Fabric)
		b.Box(x, y, z, s + 1 + 2 * g, h + g, 6, BUTTER, M.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			b.EggR(CFrame.new(x + side * 6, y + h + 3, z) * CFrame.Angles(0, 0, side * 0.4), 10, 6, 5, BUTTER, M.Fabric)
		end
		b.Ball(x, y + h + 2, z, 5, darken(BUTTER, 0.1), M.Fabric)
		for dot = 0, 2 do
			b.CylZ(x - s * 0.3 + dot * s * 0.3, y + h * 0.3, z + s * 0.45 + 0.4, 3.4, 0.8, WHITE, M.SmoothPlastic)
		end
	end
	b.Footprint(90, 50, 76)
end
R.BookStack = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT), accent(b, 4, BUTTER) }
	-- pile de livres : couvertures (dos arrondis), tranches de pages, titres dorés
	for index = 0, 4 do
		local cf = CFrame.new((index % 2) * 4 - 2, 5 + index * 11, 0) * CFrame.Angles(0, (index % 3 - 1) * 0.15, 0)
		local c = colors[index % 4 + 1]
		b.BoxR(cf, 84, 10, 60, c, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(1.4, 0, 0), 82, 8.4, 60.6, rgb(250, 244, 226), M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(-42, 0, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), 10, 60, 2, c, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(-43.2, 0, 0), 0.6, 2, 30, GOLD, M.Metal)
	end
	b.Top(1, 0, 55, 0, 60, 50)
	b.Footprint(84, 60, 56)
end
R.BlanketStack = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, MINT), accent(b, 4, LILAC) }
	-- pile de plaids pliés : pli arrondi, rayures, franges
	for index = 0, 3 do
		local w = 90 - index * 4
		local c = colors[index + 1]
		b.Box(0, index * 14, 0, w, 14, 60, c, M.Fabric)
		b.CylZ(-w / 2, index * 14 + 7, 0, 14, 60, c, M.Fabric)
		b.Box(0, index * 14 + 5, 30.2, w - 8, 3, 0.6, lighten(c, 0.35), M.Fabric)
		for f = 0, 5 do
			b.Box(w / 2 + 1, index * 14 + 3 + (f % 2) * 6, -25 + f * 10, 2, 2, 2, lighten(c, 0.2), M.Fabric)
		end
	end
	b.Top(1, 0, 56, 0, 70, 50)
	b.Footprint(94, 60, 56)
end
local function pillow(b: Builder, _ctx: Ctx)
	local color = accent(b, 1, PINK)
	House3DKit.PillowR(b, CFrame.new(0, 34, 0) * CFrame.Angles(-0.2, 0, 0), 80, 64, 24, color, M.Fabric)
	b.Ball(0, 36, 12, 18, lighten(color, 0.3), M.Fabric)
	b.Footprint(80, 40, 70)
end
R.HeartPillow = pillow
R.MoonPillow = pillow
local function orb(b: Builder, _ctx: Ctx)
	local base = accent(b, 2, woodOf(b, WOOD))
	-- globe : socle mouluré, sphère de verre, décor intérieur, neige / étincelles
	b.Cyl(0, 0, 0, 60, 6, darken(base, 0.1))
	b.Cyl(0, 6, 0, 52, 10, base)
	b.Cyl(0, 14, 0, 44, 3, GOLD, M.Metal).Reflectance = 0.3
	local ball = b.Ball(0, 46, 0, 64, accent(b, 1, rgb(190, 170, 255)), M.Glass)
	ball.Transparency = 0.3
	ball.Reflectance = 0.2
	if b.Item and b.Item.Id == "SnowGlobe" then
		-- bonhomme de neige sur un tapis de neige, flocons en suspension
		b.Egg(0, 20, 0, 40, 6, 40, WHITE, M.SmoothPlastic)
		b.Ball(0, 36, 0, 18, WHITE)
		b.Ball(0, 48, 0, 12, WHITE)
		b.Ball(0, 49, 5.6, 2, INK)
		for index = 0, 7 do
			local a = index * 2.3
			b.Ball(math.cos(a) * 18, 40 + (index % 4) * 7, math.sin(a) * 18, 2.4, WHITE)
		end
	else
		-- boule de cristal : volutes lumineuses au cœur
		for index = 0, 4 do
			local a = index * 1.26
			local wisp = b.EggR(CFrame.new(math.cos(a) * 8, 42 + index * 2.4, math.sin(a) * 8) * CFrame.Angles(0, a, 0.6), 18, 5, 8, lighten(accent(b, 1, rgb(190, 170, 255)), 0.4))
			b.Neon(wisp)
		end
		b.Light(ball, lighten(accent(b, 1, rgb(190, 170, 255)), 0.3), 10, 0.6)
	end
	b.Footprint(64, 64, 80)
end
R.SnowGlobe = orb
R.CrystalBall = orb
R.DeskGlobe = function(b, _ctx)
	-- mappemonde : pied en bois tourné, méridien doré incliné, océans et continents
	b.Cyl(0, 0, 0, 44, 6, woodOf(b, WOOD), M.Wood)
	b.Egg(0, 6, 0, 30, 8, 30, woodOf(b, WOOD), M.Wood)
	b.Cyl(0, 6, 0, 5, 20, GOLD, M.Metal).Reflectance = 0.3
	local ocean = accent(b, 1, rgb(110, 180, 250))
	b.Ball(0, 58, 0, 64, ocean)
	local land = accent(b, 2, LEAF)
	for index, spec in ipairs({ { -10, 70, 16, 22 }, { 12, 50, 20, 16 }, { -18, 46, 12, 14 }, { 20, 66, 8, 12 } }) do
		local dir = Vector3.new(spec[1], spec[2] - 58, 24).Unit
		local p = Vector3.new(0, 58, 0) + dir * 31
		b.EggR(CFrame.lookAt(p, p + dir), spec[4], spec[3], 3, vary(land, index, 0.1))
	end
	b.BoxR(CFrame.new(0, 58, 0) * CFrame.Angles(0, 0, 0.4), 3, 76, 3, GOLD, M.Metal).Reflectance = 0.3
	b.CylZ(0, 58, 0, 74, 3, GOLD, M.Metal)
	b.Footprint(74, 64, 92)
end
R.GoldenTrophy = function(b, _ctx)
	local gold = b.Map(GOLD)
	-- coupe : socle en bois à plaque, pied, nœud, coupe évasée, anses, étoile
	House3DKit.Bevel(b, 0, 0, 0, 44, 14, 36, 1.4, woodOf(b, WOOD_DARK), M.Wood)
	b.Box(0, 4, 18.2, 24, 6, 0.8, lighten(gold, 0.2), M.Metal)
	b.Cyl(0, 14, 0, 18, 3, gold, M.Metal).Reflectance = 0.35
	b.Cyl(0, 17, 0, 8, 12, gold, M.Metal).Reflectance = 0.35
	b.Ball(0, 30, 0, 12, gold, M.Metal).Reflectance = 0.35
	b.Cyl(0, 34, 0, 36, 8, gold, M.Metal).Reflectance = 0.35
	b.Cyl(0, 42, 0, 46, 14, gold, M.Metal).Reflectance = 0.35
	b.Cyl(0, 56, 0, 52, 4, lighten(gold, 0.15), M.Metal).Reflectance = 0.35
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 22, 56, 0, side * 32, 52, 0, 4, gold, M.Metal)
		b.Tube(side * 32, 52, 0, side * 22, 40, 0, 4, gold, M.Metal)
	end
	House3DKit.StarSoft(b, 0, 46, 23.4, 6, 1, WHITE, M.Metal)
	b.Footprint(66, 50, 74)
end
R.MantelClock = function(b, _ctx)
	local wood = woodOf(b, WOOD)
	-- pendule de cheminée : caisse en chapeau de gendarme, pieds, cadran
	-- (index, aiguilles), lunette dorée, balancier derrière une vitre
	for _, sx in ipairs({ -1, 1 }) do
		b.Ball(sx * 34, 2, 12, 5, GOLD, M.Metal)
	end
	House3DKit.Bevel(b, 0, 2, 0, 80, 48, 34, 1.6, wood, M.Wood)
	b.Ball(0, 50, 0, 40, wood, M.Wood)
	local g = House3DKit.Gap(b, 0.6)
	b.CylZ(0, 42, 17, 42, 2, GOLD, M.Metal).Reflectance = 0.3
	b.CylZ(0, 42, 17.5 + g / 2, 38, 1 + g, WHITE)
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		b.Box(math.sin(a) * 15, 42 + math.cos(a) * 15 - 0.8, 18 + 1.5 * g, 1.2, index % 3 == 0 and 2.6 or 1.6, g, INK)
	end
	b.BoxR(CFrame.new(0, 48, 18 + 1.5 * g) * CFrame.Angles(0, 0, 0.2), 2, 14, g, INK)
	b.BoxR(CFrame.new(3, 42, 18 + 2.5 * g) * CFrame.Angles(0, 0, 1.3), 2, 10, g, INK)
	b.Ball(0, 42, 18 + 3 * g, 2.4, GOLD, M.Metal)
	b.CylZ(0, 12, 17 + g / 2, 7, g, GOLD, M.Metal)
	b.Box(0, 8, 17 + 1.5 * g, 20, 12, g, rgb(200, 220, 240), M.Glass).Transparency = 0.5
	b.Footprint(80, 40, 70)
end
R.Vase = function(b, _ctx)
	local color = accent(b, 1, rgb(160, 200, 255))
	-- vase en céramique (pied, panse, col, lèvre), frise, bouquet de fleurs
	-- sur tiges avec feuilles
	b.Cyl(0, 0, 0, 34, 4, darken(color, 0.15))
	b.Cyl(0, 4, 0, 40, 8, color)
	b.Ball(0, 30, 0, 54, color)
	b.Cyl(0, 30, 0, 55, 3, lighten(color, 0.4))
	b.Cyl(0, 50, 0, 26, 20, color)
	b.Cyl(0, 70, 0, 32, 4, lighten(color, 0.3))
	local green = accent(b, 3, LEAF)
	for index = 0, 2 do
		local x = -10 + index * 10
		local y = 82 + (index % 2) * 8
		b.Tube(0, 70, 0, x, y - 4, 0, 1.6, darken(green, 0.2), M.SmoothPlastic)
		flowerHead(b, x, y, 0, 14, accent(b, 2, PINK), BUTTER, 6)
		House3DKit.Leaf(b, x * 0.5, 76, 0, 10, 4, index * 2 - 2, -0.3, green)
	end
	b.Footprint(56, 56, 96)
end
R.Fountain = function(b, _ctx)
	local stone = lightOf(b, rgb(236, 236, 246))
	-- fontaine en marbre : bassin à margelle, eau (reflet), colonne cannelée,
	-- vasque, bouquet d'eau, filets qui retombent
	b.Cyl(0, 0, 0, 96, 22, stone, M.Marble)
	b.Cyl(0, 20, 0, 98, 3, lighten(stone, 0.2), M.Marble)
	local water = b.Cyl(0, 18, 0, 86, 3, rgb(150, 210, 255), M.Glass)
	water.Transparency = 0.2
	water.Reflectance = 0.25
	b.Cyl(0, 22, 0, 14, 40, stone, M.Marble)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.Cyl(math.cos(a) * 6.4, 24, math.sin(a) * 6.4, 3, 34, darken(stone, 0.06), M.Marble)
	end
	b.Cyl(0, 58, 0, 50, 8, stone, M.Marble)
	b.Cyl(0, 64, 0, 44, 2, rgb(150, 210, 255), M.Glass).Transparency = 0.2
	b.Cyl(0, 66, 0, 10, 16, stone, M.Marble)
	local spray = b.Egg(0, 86, 0, 16, 18, 16, rgb(190, 230, 255), M.Glass)
	spray.Transparency = 0.3
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		local jet = b.Tube(math.cos(a) * 24, 62, math.sin(a) * 24, math.cos(a) * 34, 24, math.sin(a) * 34, 1.6, rgb(200, 235, 255), M.Glass)
		jet.Transparency = 0.45
	end
	b.Footprint(96, 96, 94)
end
R.MoaiStatue = function(b, _ctx)
	local stone = b.Map(rgb(170, 160, 170))
	-- moaï : buste, tête allongée, arcades, long nez, lèvres, oreilles, pukao
	b.Box(0, 0, 0, 50, 60, 40, stone, M.Slate)
	b.Box(0, 50, 2, 40, 46, 36, stone, M.Slate)
	b.Box(0, 80, 20.5, 30, 6, 2, darken(stone, 0.3))
	b.Wedge(0, 56, 21, 10, 22, 6, darken(stone, 0.1), "Front", M.Slate)
	b.Box(0, 56, 21, 10, 22, 4, darken(stone, 0.1), M.Slate)
	b.Box(0, 52, 20.6, 18, 3, 2, darken(stone, 0.25), M.Slate)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 21, 56, 4, 3, 26, 10, darken(stone, 0.05), M.Slate)
		b.Box(side * 16, 20, 20.4, 3, 30, 1, darken(stone, 0.2), M.Slate)
	end
	b.Cyl(0, 96, 2, 30, 8, rgb(190, 110, 90), M.Slate)
	b.Footprint(50, 42, 96)
end
R.BeachBall = function(b, _ctx)
	-- ballon de plage : quartiers colorés (bandes), pôle blanc, valve
	b.Ball(0, 48, 0, 96, accent(b, 1, PINK))
	b.Cyl(0, 40, 0, 97, 16, accent(b, 2, SKY))
	b.Cyl(0, 58, 0, 91, 8, WHITE)
	b.Cyl(0, 26, 0, 88, 6, accent(b, 3, BUTTER))
	b.Ball(0, 90, 0, 20, WHITE)
	b.Cyl(0, 94, 18, 4, 3, WHITE, M.SmoothPlastic)
	b.Footprint(96, 96, 96)
end
R.GiantDice = function(b, _ctx)
	-- gros dé en mousse : arêtes arrondies, points en creux sur 3 faces
	local die = lightOf(b, WHITE)
	local cf = CFrame.new(0, 42, 0) * CFrame.Angles(0, 0.35, 0)
	b.BoxR(cf, 84, 76, 76, die)
	b.BoxR(cf, 76, 84, 76, die)
	b.BoxR(cf, 76, 76, 84, die)
	local dot = accent(b, 1, PINK)
	for _, p in ipairs({ { -20, 20 }, { 20, -20 }, { 0, 0 } }) do
		b.BoxR(cf * CFrame.new(p[1], p[2], 42.2), 14, 14, 1, dot)
	end
	for _, p in ipairs({ { -20, -20 }, { 20, 20 } }) do
		b.BoxR(cf * CFrame.new(42.2, p[1], p[2]) * CFrame.Angles(0, math.pi / 2, 0), 14, 14, 1, dot)
	end
	b.BoxR(cf * CFrame.new(0, 42.2, 0) * CFrame.Angles(math.pi / 2, 0, 0), 14, 14, 1, dot)
	b.Footprint(100, 100, 84)
end
R.ToyDrum = function(b, _ctx)
	local color = accent(b, 1, rgb(255, 110, 120))
	-- tambour : fût, cercles blancs, peau, cordage en zigzag, baguettes croisées
	b.Cyl(0, 0, 0, 90, 60, color)
	b.Cyl(0, 58, 0, 92, 4, WHITE)
	b.Cyl(0, 0, 0, 92, 4, WHITE)
	b.Cyl(0, 61, 0, 86, 1, rgb(250, 240, 220), M.Fabric)
	for index = 0, 9 do
		local a0, a1 = index / 10 * math.pi * 2, (index + 0.5) / 10 * math.pi * 2
		b.Tube(math.cos(a0) * 45.6, 56, math.sin(a0) * 45.6, math.cos(a1) * 45.6, 5, math.sin(a1) * 45.6, 1.6, GOLD, M.Fabric)
		b.Tube(math.cos(a1) * 45.6, 5, math.sin(a1) * 45.6, math.cos(a0 + math.pi / 5) * 45.6, 56, math.sin(a0 + math.pi / 5) * 45.6, 1.6, GOLD, M.Fabric)
	end
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 20, 63, -10, -side * 6, 70, 14, 2.4, woodOf(b, WOOD), M.Wood)
		b.Ball(-side * 6, 70, 14, 5, WHITE)
	end
	b.Footprint(92, 92, 64)
end
R.BoardGame = function(b, _ctx)
	-- jeu de société : boîte, plateau à cases colorées, pions, dé
	b.Box(0, 0, 0, 96, 8, 70, accent(b, 1, PINK))
	b.Box(0, 8, 0, 80, 0.5, 56, WHITE)
	local cols = { PINK, SKY, MINT, BUTTER }
	for index = 0, 11 do
		local x = -36 + (index % 6) * 14.4
		local z = index < 6 and -22 or 22
		b.Box(x, 8.5, z, 12, 0.5, 10, cols[index % 4 + 1], M.SmoothPlastic)
	end
	for index = 0, 3 do
		b.Cyl(-24 + index * 16, 8.5, (index % 2) * 12, 8, 7, cols[index + 1])
		b.Ball(-24 + index * 16, 18, (index % 2) * 12, 7, cols[index + 1])
	end
	b.Box(24, 8.5, -6, 8, 8, 8, WHITE, M.SmoothPlastic)
	b.Footprint(96, 70, 18)
end
R.ToyRobot = function(b, _ctx)
	local metal = accent(b, 1, rgb(170, 200, 230))
	-- robot en fer-blanc : jambes, torse à panneau (voyants, grille), bras à
	-- pinces, tête à hublots, oreilles, antenne
	for _, x in ipairs({ -12, 12 }) do
		b.Box(x, 0, 0, 16, 5, 22, darken(metal, 0.3), M.Metal)
		b.Box(x, 5, 0, 12, 21, 16, darken(metal, 0.15), M.Metal)
	end
	b.Round(0, 26, 0, 48, 34, 30, 4, metal, M.Metal)
	b.Box(0, 32, 15.4, 30, 20, 1, darken(metal, 0.25), M.Metal)
	for index = 0, 2 do
		local light = b.Ball(-8 + index * 8, 46, 16, 4, ({ rgb(255, 90, 110), BUTTER, MINT })[index + 1])
		b.Neon(light)
	end
	for index = 0, 2 do
		b.Box(0, 34 + index * 3, 16.2, 22, 1, 0.8, INK, M.Metal)
	end
	b.Round(0, 62, 0, 38, 28, 28, 4, lighten(metal, 0.1), M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		b.CylZ(side * 9, 76, 14, 10, 1.4, GOLD, M.Metal)
		local eye = b.Ball(side * 9, 76, 14.6, 7, rgb(120, 230, 255))
		b.Neon(eye)
		b.Box(side * 30, 34, 0, 8, 24, 10, darken(metal, 0.1), M.Metal)
		b.Ball(side * 30, 57, 0, 10, darken(metal, 0.2), M.Metal)
		b.Wedge(side * 30, 28, 3, 6, 6, 4, GREY_DARK, "Front", M.Metal)
		b.Wedge(side * 30, 28, -3, 6, 6, 4, GREY_DARK, "Back", M.Metal)
		b.CylX(side * 20, 76, 0, 8, 3, GOLD, M.Metal)
	end
	b.Box(0, 67, 14.6, 14, 2, 0.8, INK, M.Metal)
	b.Cyl(0, 90, 0, 2, 8, GREY)
	b.Ball(0, 98, 0, 6, rgb(255, 80, 100))
	b.Footprint(64, 30, 100)
end
R.NestingDolls = function(b, _ctx)
	local colors = { accent(b, 1, rgb(255, 110, 120)), accent(b, 2, BUTTER), accent(b, 3, MINT) }
	-- poupées gigognes : corps en poire, visage, foulard, fleurs peintes, joues
	for index = 0, 2 do
		local s = 1 - index * 0.25
		local x = -28 + index * 30
		local c = colors[index + 1]
		b.Egg(x, 20 * s, 0, 42 * s, 42 * s, 40 * s, c)
		b.Ball(x, 48 * s, 0, 30 * s, c)
		b.Egg(x, 48 * s, 11 * s, 18 * s, 16 * s, 8 * s, rgb(255, 230, 210))
		for _, side in ipairs({ -1, 1 }) do
			b.Ball(x + side * 4 * s, 49 * s, 15 * s, 2.4 * s, INK)
			b.Ball(x + side * 6 * s, 45 * s, 14.4 * s, 3 * s, rgb(255, 150, 170))
		end
		b.EggR(CFrame.new(x, 22 * s, 19 * s), 18 * s, 20 * s, 3, lighten(c, 0.5))
		b.Ball(x, 22 * s, 20.4 * s, 6 * s, darken(c, 0.2))
		b.Cyl(x, 34 * s, 0, 36 * s, 2 * s, GOLD)
	end
	b.Footprint(90, 40, 64)
end
R.ToyRocket = function(b, _ctx)
	local color = lightOf(b, WHITE)
	local red = accent(b, 1, rgb(255, 90, 110))
	-- fusée jouet : fuselage, bandes, hublot cerclé, ogive, ailerons, tuyère,
	-- flamme en couches
	b.Cyl(0, 10, 0, 34, 60, color)
	b.Cyl(0, 20, 0, 34.6, 4, red)
	b.Cyl(0, 58, 0, 34.6, 3, red)
	b.Egg(0, 70, 0, 34, 30, 34, red)
	b.Cyl(0, 82, 0, 10, 8, red)
	b.CylZ(0, 46, 16, 16, 2, GREY, M.Metal).Reflectance = 0.3
	b.CylZ(0, 46, 17, 12, 2, accent(b, 2, SKY), M.Glass)
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(angle) * 20, 16, math.sin(angle) * 20) * CFrame.Angles(0, -angle, 0), 16, 26, 3, red)
	end
	b.Cyl(0, 4, 0, 20, 6, GREY_DARK, M.Metal)
	local flame = b.Egg(0, 2, 0, 16, 12, 16, FIRE)
	b.Neon(flame)
	local core = b.Egg(0, 1, 0, 8, 7, 8, BUTTER)
	b.Neon(core)
	b.Footprint(50, 50, 96)
end

-- v9.1 : NOUVEAUX MEUBLES (Art/Cozy91, Art/Fun91) ------------------------

R.ToyChest = function(b, ctx)
	local top = ctx.TopY(1, 68)
	local x0, x1 = ctx.Span(1, -42, 42)
	local w, depth = x1 - x0, 52
	local body = accent(b, 1, rgb(255, 170, 190))
	local g = House3DKit.Gap(b, 0.8)
	-- coffre à jouets : caisse, couvercle bombé, sangles, serrure, charnières,
	-- poignées de côté, étoiles peintes
	b.Round(0, 0, 0, w, top - 10, depth, 3, body, M.Wood)
	b.Round(0, top - 10, 0, w + 3, 8, depth + 3, 3, lighten(body, 0.15), M.Wood)
	b.Box(0, top - 2, 0, w + 1, 2, depth + 1, lighten(body, 0.2), M.Wood)
	for _, x in ipairs({ -w / 3, w / 3 }) do
		b.Box(x, 0, 0, 5, top + 0.4, depth + 3.4, accent(b, 2, BUTTER), M.Wood)
	end
	b.Box(0, top - 18, depth / 2 + 1.5 + g / 2, 10, 10, g, GOLD, M.Metal).Reflectance = 0.3
	b.CylZ(0, top - 14, depth / 2 + 1.5 + g, 2.4, g, INK, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (w / 2 + g / 2), top - 26, 0, g, 4, 14, INK, M.Leather)
		b.Cyl(sx * w * 0.3, top - 10, -depth / 2 - 1, 2, 4, GOLD, M.Metal)
		House3DKit.StarSoft(b, sx * w * 0.17, (top - 10) * 0.5, depth / 2 + g, 5, 1, lighten(body, 0.45), M.SmoothPlastic)
	end
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 3, depth + 3, top)
end
R.Pouf = function(b, ctx)
	local seat = ctx.TopY(1, 48)
	local color = accent(b, 1, LILAC)
	-- pouf tricoté : côtes verticales en torsades, dessus bombé, bouton
	b.Cyl(0, 0, 0, 62, seat - 6, color, M.Fabric)
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		b.Cyl(math.cos(a) * 29, 1, math.sin(a) * 29, 7, seat - 9, vary(lighten(color, 0.06), index, 0.05), M.Fabric)
	end
	b.Cyl(0, seat - 8, 0, 60, 8, lighten(color, 0.12), M.Fabric)
	b.Egg(0, seat - 3, 0, 60, 6, 60, lighten(color, 0.12), M.Fabric)
	b.Ball(0, seat - 1, 0, 8, darken(color, 0.2), M.Fabric)
	b.Top(1, 0, seat, 0, 50, 50)
	b.Footprint(64, 64, seat)
end
R.LadderShelf = function(b, ctx)
	local wood = woodOf(b, WOOD)
	-- étagère échelle : montants inclinés, tablettes biseautées, déco (livres,
	-- plante, bocal) sur les côtés des tablettes
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 40, 46, -4) * CFrame.Angles(-0.18, 0, 0), 4, 94, 4, darken(wood, 0.1), M.Wood)
		b.Box(side * 40, 0, 4, 5, 1.4, 6, darken(wood, 0.4), M.Rubber)
	end
	for index = 1, 3 do
		local y = ctx.TopY(index, 30 * index)
		local x0, x1 = ctx.Span(index, -40, 40)
		local z = 8 - index * 5
		House3DKit.Bevel(b, (x0 + x1) / 2, y - 3, z, x1 - x0 + 4, 3, 24 - index * 3, 0.8, vary(wood, index, 0.05), M.Wood)
		b.Top(index, (x0 + x1) / 2, y, z, x1 - x0, 18 - index * 3)
	end
	b.Footprint(86, 36, 96)
end
R.KotatsuTable = function(b, ctx)
	local top = ctx.TopY(1, 58)
	local x0, x1 = ctx.Span(1, -46, 46)
	local w, depth = x1 - x0, 60
	local quilt = accent(b, 1, rgb(255, 170, 190))
	-- kotatsu : couette matelassée (motif), plateau en bois qui déborde,
	-- bord de couette qui traîne, mandarines dans un petit panier (côté)
	b.Box(0, 0, 0, w - 4, top - 6, depth - 4, quilt, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (w / 2 - 1), 0, 0, 4, top - 10, depth + 2, darken(quilt, 0.08), M.Fabric)
		b.Egg(sx * (w / 2 + 2), 2, 0, 8, 4, depth, darken(quilt, 0.08), M.Fabric)
	end
	local g = House3DKit.Gap(b, 0.8)
	for index = 0, 3 do
		b.Box(-w * 0.3 + index * w * 0.2, 6, depth / 2 - 2 + g / 2, 2, top - 16, g, lighten(quilt, 0.3), M.Fabric)
	end
	House3DKit.Bevel(b, 0, top - 6, 0, w + 4, 6, depth + 4, 1.4, woodOf(b, WOOD), M.Wood)
	b.Top(1, 0, top, 0, w, depth)
	b.Footprint(w + 6, depth + 6, top)
end
R.HeartArmchair = function(b, ctx)
	sofa(b, ctx, 36, 92, 1)
	local color = accent(b, 1, PINK)
	local seat = ctx.TopY(1, 36)
	-- dossier en cœur capitonné (lobes + pointe), boutons
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 16, seat + 40, -20, 36, color, M.Fabric)
		b.Ball(side * 16, seat + 44, -3, 3, darken(color, 0.25), M.Fabric)
	end
	b.BoxR(CFrame.new(0, seat + 28, -20) * CFrame.Angles(0, 0, math.pi / 4), 32, 32, 10, color, M.Fabric)
end
R.CatSofa = function(b, ctx)
	sofa(b, ctx, 36, 100, 3)
	local color = accent(b, 1, rgb(255, 190, 150))
	local seat = ctx.TopY(1, 36)
	-- oreilles de chat (intérieur rose), yeux brillants, moustaches, queue
	for _, side in ipairs({ -1, 1 }) do
		b.Wedge(side * 30, seat + 30, -21, 16, 16, 8, color, "Front", M.Fabric)
		b.Wedge(side * 30, seat + 31, -18.4, 9, 10, 3, PINK_SOFT, "Front", M.Fabric)
		b.Ball(side * 8, seat + 20, -14, 6, INK)
		b.Ball(side * 7, seat + 21.4, -11.2, 2, WHITE)
		for _, dy in ipairs({ -1.5, 1.5 }) do
			b.Tube(side * 4, seat + 14 + dy, -12, side * 16, seat + 15 + dy * 2, -11, 0.6, INK, M.SmoothPlastic)
		end
	end
	b.Ball(0, seat + 15, -12.4, 3, rgb(255, 140, 160))
	b.Tube(52, 12, -20, 60, 30, -24, 6, color, M.Fabric)
	b.Tube(60, 30, -24, 56, 44, -24, 5, color, M.Fabric)
end
R.CrystalThrone = function(b, ctx)
	chair(b, ctx, 44, 56, 64, 56, accent(b, 1, LILAC))
	local crystal = accent(b, 2, rgb(170, 220, 255))
	local seat = ctx.TopY(1, 44)
	-- couronne de cristaux (pointes facettées, reflets) + gemme centrale
	for index = -2, 2 do
		local h = 22 - math.abs(index) * 4
		local spike = b.Wedge(index * 11, seat + 50 - math.abs(index) * 8, -25, 9, h, 6, crystal, "Front", M.Glass)
		spike.Transparency = 0.2
		spike.Reflectance = 0.25
		local back = b.Wedge(index * 11, seat + 50 - math.abs(index) * 8, -28, 9, h, 3, lighten(crystal, 0.2), "Back", M.Glass)
		back.Transparency = 0.2
	end
	local gem = b.EggR(CFrame.new(0, seat + 30, -21) * CFrame.Angles(0, 0, math.pi / 4), 8, 8, 4, accent(b, 3, PINK), M.Glass)
	gem.Reflectance = 0.3
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 28, seat + 54, -24, 5, crystal, M.Glass).Reflectance = 0.3
	end
end
R.Hammock = function(b, ctx)
	local seat = ctx.TopY(1, 44)
	local wood = woodOf(b, WOOD)
	local fabric = accent(b, 1, rgb(255, 170, 120))
	-- hamac sur support : pieds en arc, toile rayée aux bords frangés,
	-- cordelettes, coussin
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 46, 0, 0, 5, 70, 5, wood, M.Wood)
		b.Box(side * 46, 0, 0, 12, 4, 30, darken(wood, 0.15), M.Wood)
		b.Ball(side * 46, 71, 0, 6, lighten(wood, 0.1), M.Wood)
	end
	b.Box(0, 0, 0, 92, 3, 5, darken(wood, 0.15), M.Wood)
	for index = -3, 3 do
		local y = seat - 6 + math.abs(index) ^ 1.6 * 2.2
		b.Box(index * 12, y, 0, 13, 3, 32, index % 2 == 0 and fabric or lighten(fabric, 0.3), M.Fabric)
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(index * 12, y - 0.6, sz * 16.6, 2, WHITE, M.Fabric)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -10, 0, 10 }) do
			b.Tube(side * 44, seat + 22, 0, side * 38, seat + 4, dz, 1, INK, M.Fabric)
		end
	end
	House3DKit.PillowR(b, CFrame.new(-26, seat + 8, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(-0.4, 0, 0), 20, 12, 5, accent(b, 2, BUTTER), M.Fabric)
	b.Top(1, 0, seat, 0, 60, 26)
	b.Footprint(100, 34, 70)
end
R.KitchenSink = function(b, ctx)
	local top = ctx.TopY(1, 62)
	local body = accent(b, 1, MINT)
	local w, depth = 98, 48
	local g = House3DKit.Gap(b, 0.8)
	-- évier sur meuble : socle en retrait, 3 portes à panneau + poignées,
	-- plan en marbre, cuve inox (bonde), mitigeur col-de-cygne, flacon
	b.Box(0, 0, -1, w - 6, 5, depth - 6, darken(body, 0.45), M.SmoothPlastic)
	b.Box(0, 5, 0, w, top - 11, depth, body, M.SmoothPlastic)
	b.Box(0, 6, depth / 2, w - 5, top - 13, 2 * g, darken(body, 0.5), M.SmoothPlastic)
	for index = 1, 3 do
		local x = -w / 2 + (index - 0.5) * w / 3
		b.Box(x, 7, depth / 2 + 1.5 * g, w / 3 - 3, top - 16, 3 * g, lighten(body, 0.2), M.SmoothPlastic)
		b.Box(x, 11, depth / 2 + 3 * g, w / 3 - 11, top - 24, 2 * g, lighten(body, 0.28), M.SmoothPlastic)
		House3DKit.Handle(b, x, top - 16, depth / 2 + 4 * g, 10, false)
	end
	House3DKit.Bevel(b, 0, top - 6, 0, w + 2, 6, depth + 2, 1.4, lightOf(b, WHITE), M.Marble)
	local basin = b.Box(0, top - 5, 0, 36, 5.2 + g, 30, rgb(190, 200, 214), M.Metal)
	basin.Reflectance = 0.35
	local water = b.Box(0, top - 3, 0, 32, 1, 26, rgb(170, 220, 255), M.Glass)
	water.Transparency = 0.3
	b.Cyl(0, top - 2, 0, 4, 1, GREY_DARK, M.Metal)
	b.Cyl(0, top, -18, 5, 3, CHROME_METAL, M.Metal).Reflectance = 0.4
	b.Cyl(0, top + 3, -18, 3.4, 13, CHROME_METAL, M.Metal).Reflectance = 0.4
	b.Tube(0, top + 16, -18, 0, top + 19, -12, 3, CHROME_METAL, M.Metal).Reflectance = 0.4
	b.Tube(0, top + 19, -12, 0, top + 14, -7, 2.6, CHROME_METAL, M.Metal).Reflectance = 0.4
	b.Tube(0, top + 10, -18, 6, top + 12, -18, 1.6, CHROME_METAL, M.Metal)
	b.Cyl(22, top, -18, 6, 9, accent(b, 2, PINK), M.SmoothPlastic)
	b.Cyl(22, top + 9, -18, 2.4, 3, WHITE, M.SmoothPlastic)
	local x0, x1 = ctx.Span(1, -46, -22)
	b.Top(1, (x0 + x1) / 2, top, 0, x1 - x0, depth - 6)
	local x2, x3 = ctx.Span(2, 22, 46)
	b.Top(2, (x2 + x3) / 2, top, 0, x3 - x2, depth - 6)
	b.Footprint(w + 2, depth + 2, top + 18)
end
R.Jukebox = function(b, _ctx)
	local body = accent(b, 1, rgb(255, 120, 150))
	local g = House3DKit.Gap(b, 0.8)
	-- juke-box : caisse à arche, arc lumineux, bulles, vitrine des disques,
	-- grille chromée, boutons de sélection
	b.Round(0, 0, 0, 70, 60, 40, 5, body, M.SmoothPlastic)
	b.CylZ(0, 60, 0, 70, 40, body, M.SmoothPlastic)
	local arch = b.CylZ(0, 60, 20 + g / 2, 56, g, BUTTER)
	b.Neon(arch)
	b.CylZ(0, 60, 20 + 1.5 * g, 48, g, darken(body, 0.2), M.SmoothPlastic)
	for index = 0, 5 do
		local a = math.pi * (0.1 + index * 0.16)
		local bub = b.Ball(math.cos(a) * 26, 60 + math.sin(a) * 26, 20 + 1.5 * g, 3, rgb(120, 230, 255), M.Glass)
		bub.Transparency = 0.2
	end
	local glass = b.Box(0, 20, 20 + 2.5 * g, 50, 30, g, rgb(60, 50, 90), M.Glass)
	glass.Reflectance = 0.2
	for index = 0, 3 do
		b.CylZ(-15 + index * 10, 34, 20 + 3.5 * g, 9, g, ({ PINK, SKY, MINT, BUTTER })[index + 1], M.SmoothPlastic)
	end
	for index = 0, 5 do
		b.Box(0, 4 + index * 2.4, 20 + g / 2, 44, 1.2, g, CHROME_METAL, M.Metal).Reflectance = 0.35
	end
	for index = 0, 4 do
		b.Box(-12 + index * 6, 17, 20 + 1.5 * g, 4, 2, g, WHITE, M.SmoothPlastic)
	end
	b.Light(arch, BUTTER, 10, 0.8)
	b.Footprint(70, 40, 95)
end
R.PinballMachine = function(b, _ctx)
	local body = accent(b, 1, rgb(120, 110, 230))
	-- flipper : pieds chromés à patins, caisse inclinée, plateau (bumpers,
	-- flippers, bille), fronton lumineux, lanceur
	for _, x in ipairs({ -26, 26 }) do
		for _, z in ipairs({ -30, 30 }) do
			b.Box(x, 2, z, 4, 38, 4, CHROME_METAL, M.Metal).Reflectance = 0.3
			b.Box(x, 0, z, 6, 2, 6, INK, M.Rubber)
		end
	end
	b.BoxR(CFrame.new(0, 46, 0) * CFrame.Angles(-0.12, 0, 0), 60, 10, 76, body)
	local field = b.BoxR(CFrame.new(0, 51.5, 0) * CFrame.Angles(-0.12, 0, 0), 52, 1, 68, rgb(40, 40, 90))
	field.Name = "Plateau"
	local glass = b.BoxR(CFrame.new(0, 53, 0) * CFrame.Angles(-0.12, 0, 0), 52, 0.4, 68, rgb(220, 240, 255), M.Glass)
	glass.Transparency = 0.8
	glass.Reflectance = 0.2
	b.Box(0, 46, -38, 60, 40, 8, body)
	local panel = b.Box(0, 56, -33.8, 52, 26, 0.6, accent(b, 2, PINK))
	b.Neon(panel)
	for index = 0, 2 do
		local bumper = b.Ball(-14 + index * 14, 56 - index * 0.8, -10 + index * 8, 8, ({ PINK, BUTTER, MINT })[index + 1])
		b.Neon(bumper)
	end
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 8, 51, 28) * CFrame.Angles(-0.12, side * 0.4, 0), 12, 2, 3, WHITE, M.SmoothPlastic)
	end
	b.Ball(6, 53, 16, 3, CHROME_METAL, M.Metal).Reflectance = 0.5
	b.CylZ(24, 46, 38.6, 3, 5, CHROME_METAL, M.Metal)
	b.Footprint(64, 84, 86)
end
R.RetroComputer = R.DesktopPC
R.TulipLamp = function(b, _ctx)
	local color = accent(b, 1, PINK)
	local stem = greenOf(b, LEAF_DARK)
	-- lampe tulipe : socle, tige, deux feuilles, calice de pétales qui
	-- entoure une ampoule douce
	b.Cyl(0, 0, 0, 34, 5, stem)
	b.Egg(0, 5, 0, 26, 4, 26, lighten(stem, 0.1))
	b.Tube(0, 5, 0, 0, 55, 0, 4, stem, M.SmoothPlastic)
	House3DKit.Leaf(b, 1, 16, 0, 20, 7, 1.6, -0.8, greenOf(b, LEAF), darken(stem, 0.2))
	House3DKit.Leaf(b, -1, 22, 0, 16, 6, -1.6, -0.9, greenOf(b, LEAF), darken(stem, 0.2))
	local bulb = b.Egg(0, 66, 0, 26, 30, 26, lighten(color, 0.3))
	b.Neon(bulb)
	for index = 0, 4 do
		local a = index / 5 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 11, 68, math.sin(a) * 11) * CFrame.Angles(math.sin(a) * 0.25, 0, -math.cos(a) * 0.25), 14, 30, 5, vary(color, index, 0.06))
	end
	b.Light(bulb, lighten(color, 0.4), 12, 0.9)
	b.Footprint(40, 40, 92)
end
R.ToyBlocks = function(b, _ctx)
	local colors = { accent(b, 1, PINK), accent(b, 2, SKY), accent(b, 3, BUTTER), accent(b, 4, MINT) }
	local specs = { { -22, 0, 0 }, { 0, 0, 4 }, { 22, 0, -2 }, { -11, 26, 2 }, { 11, 26, 0 }, { 0, 52, 1 } }
	-- cubes en bois : arêtes adoucies, lettres en relief sur la face avant
	for index, spec in ipairs(specs) do
		local c = colors[index % 4 + 1]
		local cf = CFrame.new(spec[1], spec[2] + 13, spec[3]) * CFrame.Angles(0, (index % 3 - 1) * 0.2, 0)
		b.BoxR(cf, 24, 22, 22, c)
		b.BoxR(cf, 22, 24, 22, c)
		b.BoxR(cf, 22, 22, 24, c)
		local g = House3DKit.Gap(b, 0.6)
		b.BoxR(cf * CFrame.new(0, 0, 12 + g / 2), 10, 12, g, WHITE, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(0, 0, 12 + 1.5 * g), 4, 8, g, darken(c, 0.2), M.SmoothPlastic)
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

-- Roue (axe avant-arrière : on voit le pneu de profil depuis la caméra) :
-- pneu à flanc, jante chromée à rayons, moyeu
local function wheel3D(b: Builder, x: number, y: number, z: number, d: number, width: number, rim: Color3?)
	local g = House3DKit.Gap(b, 0.4)
	b.CylZ(x, y, z, d, width, INK, M.Rubber)
	b.CylZ(x, y, z, d * 0.86, width + 2 * g, rgb(60, 60, 70), M.Rubber)
	local jante = b.CylZ(x, y, z, d * 0.6, width + 4 * g, rim or GREY, M.Metal)
	jante.Reflectance = 0.3
	for index = 0, 2 do
		b.BoxR(CFrame.new(x, y, z) * CFrame.Angles(0, 0, index * math.pi / 3), d * 0.56, d * 0.06, width + 6 * g, darken(rim or GREY, 0.2), M.Metal)
	end
	b.CylZ(x, y, z, d * 0.18, width + 8 * g, rim or GREY, M.Metal)
end

R.GamingDesk = function(b, ctx)
	local top = ctx.TopY(1, 65)
	local x0, x1 = ctx.Span(1, -47, 47)
	local w, depth = x1 - x0, 56
	local legs = b.Map(RACE_RED)
	-- bureau gamer : pieds en T, range-câbles, plateau carbone biseauté,
	-- ruban LED, crochet à casque, tapis de souris XXL
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 8), 4, 0, 10, top - 10, 10, legs, M.Metal)
		b.Box(side * (w / 2 - 8), 0, 0, 14, 4, depth - 6, CARBON, M.Metal)
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(side * (w / 2 - 8), 0, sz * (depth / 2 - 4), 6, 1.4, 6, INK, M.Rubber)
		end
		b.Box(side * (w / 2 - 8), top - 9, 0, 12, 3, depth - 10, CARBON, M.Metal)
	end
	b.Box(0, top * 0.55, -depth / 2 + 8, w - 20, 8, 12, CARBON, M.Metal) -- range-câbles
	House3DKit.Bevel(b, 0, top - 6, 0, w, 6, depth, 1.2, CARBON, M.SmoothPlastic)
	local led = b.Box(0, top - 5, depth / 2 + 0.3, w - 6, 2, 0.6, NEON_CYAN)
	b.Neon(led)
	b.Box(w / 2 - 4, top - 14, depth / 2 - 10, 2, 8, 2, GREY, M.Metal)
	b.Box(w / 2 - 4, top - 14, depth / 2 - 7, 2, 2, 6, GREY, M.Metal)
	b.Light(led, NEON_CYAN, 10, 0.6)
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end
R.BrickTable = function(b, ctx)
	local top = ctx.TopY(1, 63)
	local x0, x1 = ctx.Span(1, -47, 47)
	local w, depth = x1 - x0, 54
	local colors = { RACE_RED, BUTTER, rgb(80, 150, 255), rgb(255, 152, 56) }
	-- table en briques de construction : piles de briques à tenons, plaque verte
	for sideIndex, side in ipairs({ -1, 1 }) do
		for level = 0, 2 do
			local color = colors[(level + sideIndex) % #colors + 1]
			local y = level * ((top - 8) / 3)
			b.Box(side * (w / 2 - 9), y, 0, 14, (top - 8) / 3, 40, color, M.SmoothPlastic)
			for _, tz in ipairs({ -12, 0, 12 }) do
				b.Cyl(side * (w / 2 - 9), y + (top - 8) / 3, tz, 5, 1.5, color, M.SmoothPlastic)
			end
			b.Box(side * (w / 2 - 9), y, 0, 14 + 2 * House3DKit.Gap(b, 0.4), 0.8, 40 + 2 * House3DKit.Gap(b, 0.4), darken(color, 0.25), M.SmoothPlastic)
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
	racingChair(b, seat, b.Map(RACE_RED), CARBON, WHITE)
	b.Top(1, 0, seat, 4, 44, 36)
	b.Footprint(56, 56, seat + 64)
end
R.GamerBeanbag = function(b, _ctx)
	local color = b.Map(rgb(76, 72, 112))
	-- pouf gamer : grosse poire, dossier, coutures lumineuses, poignée, logo
	b.Ball(0, 22, 0, 90, color, M.Fabric)
	b.Ball(0, 42, -20, 64, lighten(color, 0.08), M.Fabric)
	b.Box(0, 0, 0, 84, 4, 80, darken(color, 0.1), M.Fabric)
	b.EggR(CFrame.new(0, 22, 0), 91, 3, 91, darken(color, 0.2), M.Fabric)
	local seam = b.Box(0, 30, 44.5, 60, 2, 0.8, NEON_CYAN)
	b.Neon(seam)
	b.Tube(-6, 74, -22, 6, 74, -22, 3, darken(color, 0.3), M.Fabric)
	House3DKit.StarSoft(b, 0, 42, 11, 6, 1, NEON_PINK, M.SmoothPlastic)
	b.Top(1, 0, 58, 8, 50, 40)
	b.Footprint(90, 90, 70)
end
R.LockerCabinet = function(b, ctx)
	local top = ctx.TopY(1, 91)
	local blue = b.Map(rgb(80, 130, 220))
	local w, depth = 86, 40
	local g = House3DKit.Gap(b, 0.8)
	-- casiers métalliques : socle, portes à aérations embouties, poignées à
	-- loquet, porte-étiquettes, cadenas
	b.Box(0, 0, 0, w, 6, depth, darken(blue, 0.35), M.Metal)
	b.Box(0, 6, 0, w, top - 6, depth, blue, M.Metal)
	b.Box(0, 8, depth / 2, w - 2, top - 10, 2 * g, darken(blue, 0.45), M.Metal)
	for index = 0, 1 do
		local x = -w / 4 + index * w / 2
		b.Box(x, 9, depth / 2 + 1.5 * g, w / 2 - 4, top - 14, 3 * g, lighten(blue, 0.08), M.Metal)
		for vent = 0, 3 do
			b.Box(x, top - 16 - vent * 5, depth / 2 + 3.5 * g, w / 2 - 16, 2, g, darken(blue, 0.3), M.Metal)
		end
		local hx = x + (index == 0 and 14 or -14)
		b.Box(hx, top * 0.5, depth / 2 + 3 * g, 3, 12, 3, CHROME, M.Metal).Reflectance = 0.3
		b.Box(x, top - 12, depth / 2 + 3.5 * g, 10, 4, g, WHITE, M.SmoothPlastic)
	end
	b.Box(14 - w / 4, top * 0.46, depth / 2 + 3 * g + 2, 4, 5, 2, GOLD, M.Metal)
	b.Top(1, 0, top, 0, w - 8, depth - 6)
	b.Footprint(w, depth, top)
end
R.BunkBed = function(b, ctx)
	local upper = ctx.TopY(1, 73)
	local lower = ctx.TopY(2, 29)
	local frame = b.Map(rgb(96, 120, 190))
	local width, depth = 96, 60
	-- lits superposés : montants à pommeaux, sommiers, matelas passepoilés,
	-- couettes rabattues, oreillers, garde-corps à barreaux, échelle
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * (width / 2 - 3), 0, sz * (depth / 2 - 3), 6, 96, 6, frame, M.Wood)
			b.Ball(sx * (width / 2 - 3), 97, sz * (depth / 2 - 3), 7, lighten(frame, 0.2), M.Wood)
		end
	end
	for index, top in ipairs({ upper, lower }) do
		b.Box(0, top - 16, 0, width - 4, 6, depth - 4, darken(frame, 0.2), M.Wood)
		House3DKit.SeatCushion(b, 0, top - 10, 0, width - 10, 10, depth - 10, WHITE, rgb(210, 214, 236))
		local blanket = index == 1 and NAVY or RACE_RED
		b.Box(width * 0.12, top - 9, 0, width * 0.62, 10.5, depth - 8, blanket, M.Fabric)
		b.CylZ(width * 0.12 - width * 0.31, top + 1, 0, 4, depth - 8, WHITE, M.Fabric)
		bedPillow(b, -width / 2 + 16, top + 2, 0, 18, depth - 22, 7, lighten(frame, 0.5), 0.3)
		b.Top(index, 0, top, 0, width - 24, depth - 12)
	end
	b.Box(-width / 4, upper + 2, depth / 2 - 3, width / 2, 6, 3, frame, M.Wood) -- garde-corps
	for index = 0, 3 do
		b.Box(-width / 2 + 8 + index * 10, upper - 6, depth / 2 - 3, 2, 8, 2, frame, M.Wood)
	end
	-- échelle
	for _, x in ipairs({ width / 2 - 20, width / 2 - 6 }) do
		b.Box(x, 0, depth / 2 + 3, 3, upper, 3, WOOD_LIGHT, M.Wood)
	end
	for index = 1, 4 do
		b.CylX(width / 2 - 13, index * upper / 5, depth / 2 + 3, 3, 16, WOOD_LIGHT, M.Wood)
	end
	b.Footprint(width, depth, 96)
end
R.RaceCarBed = function(b, ctx)
	local top = ctx.TopY(1, 59)
	local red = b.Map(RACE_RED)
	local width, depth = 100, 60
	-- lit voiture de course : carrosserie, nez, aileron sur mâts, numéro,
	-- bandes, roues à jantes, phares, matelas
	b.Box(0, 8, 0, width - 10, top - 18, depth, red, M.SmoothPlastic)
	b.Wedge(width / 2 - 4, 8, 0, 14, top - 26, depth, red, "Right", M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.6)
	b.Box(-width / 2 + 6, 8, 0, 10, top + 6, depth + 2 * g, darken(red, 0.1), M.SmoothPlastic)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(-width / 2 + 2, top + 6, sz * 18, 4, 6, 3, CARBON, M.Metal)
	end
	b.Box(-width / 2 + 2, top + 12, 0, 16, 4, depth + 6, CARBON, M.SmoothPlastic) -- aileron
	b.Box(0, top - 10, 0, width * 0.6, 10, depth - 8, WHITE, M.Fabric) -- matelas
	b.Box(width * 0.08, top - 9, 0, width * 0.34, 10.5, depth - 6, CARBON, M.Fabric)
	b.Box(0, top * 0.45, depth / 2 + g / 2, width - 14, 3, g, WHITE)
	b.CylZ(10, top * 0.3, depth / 2 + g / 2, 14, g, WHITE, M.SmoothPlastic)
	b.Box(10, top * 0.3 - 4, depth / 2 + 1.5 * g, 3, 8, g, INK, M.SmoothPlastic)
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
	local g = House3DKit.Gap(b, 0.8)
	-- borne néon : flancs à liserés lumineux, plateau (joystick, boutons),
	-- écran encastré, fronton néon, trappe à pièces
	b.Box(0, 0, -1, 64, 100, 48, body, M.SmoothPlastic)
	for index, x in ipairs({ -32 - g / 2, 32 + g / 2 }) do
		local strip = b.Box(x, 6, 0, g, 90, 46, index == 1 and NEON_CYAN or NEON_PINK)
		b.Neon(strip)
	end
	b.Box(0, 44, 26, 62, 8, 14, NAVY)
	for index = 1, 4 do
		knob(b, -18 + index * 8, 52, 28, 5, ({ NEON_CYAN, NEON_PINK, rgb(140, 240, 110), BUTTER })[index])
	end
	b.Box(-22, 52, 28, 3, 8, 3, RACE_RED)
	b.Ball(-22, 61, 28, 5, RACE_RED)
	screen(b, 0, 58, 23 + g, 50, 30, rgb(20, 30, 70))
	b.Art(0, 60, 23.6 + 2 * g, 30, 22, 2.6)
	local marquee = b.Box(0, 90, 23 + g, 58, 8, 1, NEON_PINK)
	b.Neon(marquee)
	b.Box(0, 12, 23 + g / 2, 20, 18, g, darken(body, 0.3), M.Metal)
	for _, x in ipairs({ -4, 4 }) do
		b.Box(x, 22, 23 + 1.5 * g, 3, 5, g, rgb(255, 200, 80), M.SmoothPlastic)
	end
	b.Light(marquee, NEON_PINK, 12, 0.8)
	b.Footprint(64, 64, 100)
end
R.GamerPC = function(b, _ctx)
	-- setup gamer : écran incurvé sur pied, clavier RGB (rangées), souris,
	-- tour vitrée (ventilos lumineux, carte graphique)
	b.Box(-16, 0, 0, 20, 2, 14, CARBON)
	b.Box(-16, 2, -4, 5, 16, 5, GREY_DARK, M.Metal)
	b.Box(-16, 16, -4, 64, 40, 3, CARBON)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(-16 + side * 34, 36, -2) * CFrame.Angles(0, -side * 0.35, 0), 8, 40, 3, CARBON, M.SmoothPlastic)
	end
	screen(b, -16, 18, -2, 60, 36, rgb(120, 170, 255))
	b.Box(-16, 0, 18, 58, 3, 14, CARBON)
	local g = House3DKit.Gap(b, 0.6)
	for row = 0, 3 do
		local keys = b.Box(-16, 3, 13 + row * 3.2, 52, g, 2.4, ({ NEON_PINK, NEON_CYAN, rgb(160, 120, 255), NEON_PINK })[row + 1])
		b.Neon(keys)
	end
	b.Egg(22, 1.6, 18, 6, 3.4, 9, INK, M.SmoothPlastic)
	b.Box(32, 0, 0, 22, 62, 42, CARBON)
	local glass = b.Box(32, 6, 21 + g / 2, 16, 50, g, NEON_CYAN)
	b.Neon(glass)
	glass.Transparency = 0.3
	for index = 0, 2 do
		local fan = b.CylZ(32, 14 + index * 16, 21 + 1.5 * g, 12, g, index == 1 and NEON_PINK or NEON_CYAN)
		b.Neon(fan)
	end
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
	for _, sz in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(-36, 34, sz * 18) * CFrame.Angles(0, 0, 0.25), 14, 50, 6, darken(CARBON, 0.2), M.Leather)
	end
	-- colonne + volant (jante, branches) + pédalier
	b.Box(22, 6, 0, 6, 44, 6, GREY, M.Metal)
	local wheelCF = CFrame.new(16, 50, 0) * CFrame.Angles(0, 0, 0.35)
	local rim = b.Part("Part", wheelCF, Vector3.new(3, 24, 24), INK, M.Rubber, "Cylindre")
	;(rim :: Part).Shape = Enum.PartType.Cylinder
	b.BoxR(wheelCF * CFrame.new(-0.6, 0, 0), 2, 20, 4, GREY_DARK, M.Metal)
	b.BoxR(wheelCF * CFrame.new(-0.6, -4, 0), 2, 4, 14, GREY_DARK, M.Metal)
	b.Box(40, 6, 0, 16, 6, 24, GREY_DARK, M.Metal)
	for index = -1, 1 do
		b.BoxR(CFrame.new(42, 13, index * 7) * CFrame.Angles(0, 0, 0.5), 2, 8, 5, CHROME, M.Metal)
	end
	-- écran
	b.Box(32, 6, -14, 4, 60, 4, GREY, M.Metal)
	b.Box(32, 60, -14, 40, 26, 3, CARBON)
	screen(b, 32, 62, -12.3, 36, 22, rgb(110, 170, 255))
	b.Footprint(96, 44, 86)
end
R.BasketHoop = function(b, _ctx)
	-- panier de basket : lest, poteau, bras, panneau (cadre, carré de visée),
	-- cercle orange, filet en mailles, ballon à coutures
	b.Round(-10, 0, 0, 40, 12, 36, 5, CARBON, M.SmoothPlastic)
	b.Cyl(-10, 12, 0, 7, 76, GREY, M.Metal).Reflectance = 0.2
	b.BoxR(CFrame.new(4, 88, 0) * CFrame.Angles(0, 0, -0.5), 30, 4, 4, GREY, M.Metal)
	b.Box(22, 80, -2, 4, 30, 44, WHITE)
	local g = House3DKit.Gap(b, 0.4)
	b.Box(24 + g / 2, 80, -2, g, 30, 44, darken(WHITE, 0.08))
	b.Box(24 + 1.5 * g, 86, -2, g, 12, 16, RACE_RED)
	b.Box(24 + 2.5 * g, 87, -2, g, 10, 14, WHITE)
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		b.Box(36 + math.cos(angle) * 10, 80, math.sin(angle) * 10, 5, 2, 5, rgb(255, 130, 50), M.Metal)
	end
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		local net = b.Tube(36 + math.cos(angle) * 10, 80, math.sin(angle) * 10, 36 + math.cos(angle + 0.8) * 6, 66, math.sin(angle + 0.8) * 6, 0.6, WHITE, M.Fabric)
		net.Transparency = 0.2
	end
	b.Cyl(36, 66, 0, 12.6, 1, WHITE, M.Fabric)
	b.Ball(34, 10, 26, 18, rgb(250, 140, 60), M.Rubber)
	b.CylX(34, 10, 26, 18.4, 0.8, INK, M.Rubber)
	b.CylZ(34, 10, 26, 18.4, 0.8, INK, M.Rubber)
	b.Footprint(70, 50, 110)
end
R.FootballGoal = function(b, _ctx)
	-- but de foot : montants, barre, filet, ballon à pentagones
	for _, x in ipairs({ -44, 44 }) do
		b.Box(x, 0, 12, 5, 80, 5, WHITE, M.Metal)
		b.BoxR(CFrame.new(x, 40, -4) * CFrame.Angles(-0.4, 0, 0), 3, 82, 3, WHITE, M.Metal)
	end
	b.Box(0, 78, 12, 93, 5, 5, WHITE, M.Metal)
	local net = b.BoxR(CFrame.new(0, 40, -6) * CFrame.Angles(-0.4, 0, 0), 88, 84, 0.6, WHITE, M.Fabric)
	net.Transparency = 0.6
	net.CastShadow = false
	for index = -3, 3 do
		b.BoxR(CFrame.new(index * 12, 40, -5.6) * CFrame.Angles(-0.4, 0, 0), 0.6, 84, 0.6, rgb(220, 220, 230), M.Fabric)
	end
	b.Ball(10, 9, 22, 18, WHITE, M.SmoothPlastic)
	for index = 0, 4 do
		local dir = Vector3.new(math.cos(index * 1.26), math.sin(index * 1.26) * 0.6 + 0.3, 1).Unit
		local p = Vector3.new(10, 9, 22) + dir * 8.8
		b.EggR(CFrame.lookAt(p, p + dir), 5, 5, 1, INK, M.SmoothPlastic)
	end
	b.Footprint(98, 40, 82)
end
R.BoxingBag = function(b, _ctx)
	-- sac de frappe : pied lesté, potence, chaînes, sac en cuir (bandes,
	-- coutures), gants suspendus
	b.Round(-38, 0, 0, 20, 5, 30, 4, CARBON, M.Metal)
	b.Box(-38, 5, 0, 7, 92, 7, CARBON, M.Metal)
	b.Box(-10, 92, 0, 62, 6, 6, CARBON, M.Metal)
	for _, dz in ipairs({ -4, 4 }) do
		b.Tube(18, 92, 0, 18 + dz * 0.8, 72, dz, 1.2, GREY, M.Metal)
	end
	b.Cyl(18, 70, 0, 20, 3, GREY_DARK, M.Metal)
	local red = b.Map(RACE_RED)
	b.Cyl(18, 20, 0, 30, 52, red, M.Leather)
	b.Egg(18, 20, 0, 30, 6, 30, red, M.Leather)
	b.Egg(18, 72, 0, 30, 6, 30, red, M.Leather)
	b.Cyl(18, 34, 0, 30.6, 4, INK, M.Leather)
	b.Cyl(18, 58, 0, 30.6, 4, INK, M.Leather)
	b.Box(18, 22, 15.2, 1, 48, 0.6, darken(red, 0.3), M.Leather)
	b.Egg(-30, 58, 6, 10, 12, 8, red, M.Leather)
	b.Tube(-32, 64, 6, -38, 80, 4, 0.6, WHITE, M.Fabric)
	b.Footprint(80, 34, 98)
end
R.GuitarAmp = function(b, _ctx)
	-- ampli : caisse gainée aux coins métal, panneau doré (potards, voyant),
	-- grille en tissu, logo, poignée
	b.Round(0, 0, 0, 84, 76, 40, 3, CARBON, M.Leather)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ 0, 72 }) do
			b.Box(sx * 40, sy, 18, 5, 4, 5, CHROME, M.Metal).Reflectance = 0.3
		end
	end
	local g = House3DKit.Gap(b, 0.6)
	b.Box(0, 62, 20 + g / 2, 78, 10, g, GOLD, M.Metal)
	for index = 0, 4 do
		knob(b, -26 + index * 12, 67, 20 + g + 2.2, 5, INK)
	end
	local lamp = b.Ball(32, 67, 20 + g + 1, 3, rgb(255, 80, 80))
	b.Neon(lamp)
	b.Box(0, 6, 20 + g / 2, 76, 52, g, rgb(70, 64, 80), M.Fabric)
	b.CylZ(0, 30, 20 + 1.5 * g, 36, g, INK, M.Fabric)
	b.Box(-20, 52, 20 + 1.5 * g, 16, 4, g, GOLD, M.Metal)
	b.Box(0, 76, 0, 34, 4, 8, INK, M.Leather)
	b.Footprint(84, 40, 80)
end
R.DrumKit = function(b, _ctx)
	local shell = b.Map(rgb(80, 110, 230))
	-- batterie : grosse caisse (cercles, tirants, peau à logo), toms montés,
	-- caisse claire chromée, tom basse sur pieds, cymbales, charleston
	local g = House3DKit.Gap(b, 0.6)
	b.CylZ(0, 26, 0, 50, 32, shell, M.SmoothPlastic)
	for _, sz in ipairs({ -1, 1 }) do
		b.CylZ(0, 26, sz * (15 + g / 2), 52, 2 + g, CHROME, M.Metal).Reflectance = 0.3
	end
	b.CylZ(0, 26, 15.5 + g, 44, 1 + 2 * g, rgb(244, 246, 255), M.SmoothPlastic)
	b.CylZ(0, 26, 16 + 2.5 * g, 16, g, RACE_RED, M.SmoothPlastic)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.BoxR(CFrame.new(math.cos(a) * 25.4, 26 + math.sin(a) * 25.4, 0) * CFrame.Angles(0, 0, a), 1.4, 2, 30, CHROME, M.Metal)
	end
	for _, x in ipairs({ -14, 14 }) do
		b.Cyl(x, 52, -6, 20, 14, shell, M.SmoothPlastic)
		b.Cyl(x, 65, -6, 21, 1 + g, CHROME, M.Metal)
		b.Tube(0, 50, -4, x, 52, -6, 1.4, CHROME, M.Metal)
	end
	b.Cyl(-40, 0, 6, 3, 44, GREY, M.Metal)
	b.Cyl(-40, 44, 6, 26, 10, CHROME, M.Metal).Reflectance = 0.35 -- caisse claire
	b.Cyl(-40, 54, 6, 25, 0.6, WHITE, M.SmoothPlastic)
	b.Cyl(40, 0, 6, 28, 38, shell, M.SmoothPlastic) -- tom basse
	b.Cyl(40, 37, 6, 29, 1 + g, CHROME, M.Metal)
	for _, spec in ipairs({ { -46, 70, -10 }, { 46, 78, -10 } }) do
		b.Cyl(spec[1], 0, spec[3], 2.5, spec[2], GREY, M.Metal)
		local cym = b.Cyl(spec[1], spec[2], spec[3], 30, 1, GOLD, M.Metal)
		cym.Reflectance = 0.3
		b.Ball(spec[1], spec[2] + 1, spec[3], 3, GOLD, M.Metal)
	end
	b.Footprint(100, 60, 80)
end
R.DJBooth = function(b, _ctx)
	-- régie DJ : caisson, façade à égaliseur lumineux, deux platines
	-- (plateau, disque, bras), table de mixage (faders, potards), casque
	b.Box(0, 0, 0, 96, 64, 44, CARBON, M.SmoothPlastic)
	local front = b.Box(0, 6, 22.3, 88, 48, 0.8, rgb(20, 20, 34))
	for index = 0, 9 do
		local bar = b.Box(-38 + index * 8.4, 10, 22.8, 5, 10 + (index * 7) % 5 * 7, 0.5, index % 2 == 0 and NEON_CYAN or NEON_PINK)
		b.Neon(bar)
	end
	for _, x in ipairs({ -28, 28 }) do
		b.Cyl(x, 64, 2, 30, 3, INK, M.SmoothPlastic)
		b.Cyl(x, 67, 2, 26, 0.6, rgb(50, 44, 60), M.SmoothPlastic)
		b.Cyl(x, 67, 2, 8, 0.8, NEON_PINK, M.SmoothPlastic)
		b.Tube(x + 12, 68, -8, x + 4, 68.4, 4, 1, CHROME, M.Metal)
	end
	b.Box(0, 64, 2, 18, 4, 22, rgb(60, 62, 84))
	for index = -1, 1 do
		b.Box(index * 5, 68, 6, 1.4, 1, 8, GREY, M.Metal)
		b.Box(index * 5, 68.6, 6 + index * 2, 3, 1.4, 2, WHITE, M.SmoothPlastic)
		b.Cyl(index * 5, 68, -4, 3, 1.4, NEON_CYAN, M.SmoothPlastic)
	end
	b.Egg(40, 66, -16, 10, 4, 10, INK, M.SmoothPlastic)
	b.Tube(34, 66, -16, 46, 66, -16, 2, INK, M.SmoothPlastic)
	b.Light(front, NEON_PINK, 12, 0.7)
	b.Footprint(96, 44, 70)
end
R.SharkTank = function(b, _ctx)
	local g = House3DKit.Gap(b, 0.8)
	-- aquarium à requins : meuble, cuve à profilés, eau profonde, sable,
	-- rochers et coraux, requins (nageoires, queue), bulles, rampe lumineuse
	b.Box(0, 0, 0, 96, 26, 46, CARBON, M.SmoothPlastic)
	local glass = b.Box(0, 26, 0, 94, 66, 44, GLASS, M.Glass)
	glass.Transparency = 0.55
	glass.Reflectance = 0.1
	glass.CastShadow = false
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (46.4 + g / 2), 26, 0, 1.2 + g, 66, 44 + 2 * g, INK, M.Metal)
	end
	local water = b.Box(0, 28, 0, 90, 56, 40, rgb(60, 140, 220), M.Glass)
	water.Transparency = 0.45
	water.CastShadow = false
	b.Box(0, 26, 0, 90, 4, 36, rgb(240, 220, 180), M.Sand)
	for index = 0, 3 do
		b.Egg(-34 + index * 22, 32, -12, 14, 10, 12, ({ rgb(170, 160, 180), rgb(255, 120, 130), rgb(255, 170, 90), rgb(160, 150, 170) })[index + 1], M.Slate)
	end
	for index, spec in ipairs({ { -18, 56, -6 }, { 18, 42, 8 } }) do
		local cf = CFrame.new(spec[1], spec[2], spec[3]) * CFrame.Angles(0, index * 0.4, 0)
		local shark = b.EggR(cf, 28, 10, 10, rgb(130, 150, 190), M.SmoothPlastic)
		shark.CastShadow = false
		b.EggR(cf * CFrame.new(2, -2, 0), 20, 5, 8, rgb(230, 236, 246), M.SmoothPlastic)
		b.Wedge(spec[1], spec[2] + 4, spec[3], 6, 8, 3, rgb(130, 150, 190), "Front")
		b.BoxR(cf * CFrame.new(-15, 0, 0) * CFrame.Angles(0, 0, 0.4), 3, 12, 2, rgb(120, 140, 180), M.SmoothPlastic)
	end
	for index = 0, 3 do
		local bubble = b.Ball(36, 34 + index * 11, 10, 2.4 + index * 0.4, WHITE, M.Glass)
		bubble.Transparency = 0.4
	end
	b.Box(0, 92, 0, 98, 4, 48, CARBON, M.SmoothPlastic)
	local lamp = b.Box(0, 91.4, 0, 80, 0.6, 8, rgb(210, 236, 255))
	b.Neon(lamp)
	b.Light(water, rgb(120, 200, 255), 12, 0.7)
	b.Footprint(98, 48, 96)
end
R.RocketModel = function(b, _ctx)
	-- maquette de fusée sur son pas de tir : socle, tour de lancement à
	-- croisillons, fusée (bandes, hublot, ogive, ailerons), flamme
	b.Box(0, 0, 0, 80, 6, 50, GREY, M.Metal)
	b.Box(28, 6, -8, 8, 80, 8, b.Map(RACE_RED), M.Metal)
	for index = 0, 5 do
		b.BoxR(CFrame.new(28, 12 + index * 12, -8) * CFrame.Angles(0, 0, (index % 2 == 0) and 0.8 or -0.8), 1.4, 14, 8.6, darken(b.Map(RACE_RED), 0.2), M.Metal)
	end
	b.Box(16, 60, -8, 16, 2, 3, GREY_DARK, M.Metal)
	b.Cyl(-6, 16, 0, 24, 54, WHITE, M.SmoothPlastic)
	b.Egg(-6, 70, 0, 24, 26, 24, RACE_RED, M.SmoothPlastic)
	b.Cyl(-6, 40, 0, 24.6, 4, RACE_RED, M.SmoothPlastic)
	b.Cyl(-6, 22, 0, 24.6, 2, INK, M.SmoothPlastic)
	local window = b.CylZ(-6, 52, 12.2, 9, 1, NEON_CYAN)
	b.Neon(window)
	b.CylZ(-6, 52, 11.8, 11, 1, GREY, M.Metal)
	for index = 0, 2 do
		local angle = index / 3 * math.pi * 2
		b.BoxR(CFrame.new(-6 + math.cos(angle) * 14, 20, math.sin(angle) * 14) * CFrame.Angles(0, -angle, 0), 10, 16, 2, RACE_RED)
	end
	b.Cyl(-6, 12, 0, 14, 4, GREY_DARK, M.Metal)
	local flame = b.Egg(-6, 9, 0, 14, 10, 14, rgb(255, 170, 60))
	b.Neon(flame)
	b.Footprint(80, 50, 82)
end
R.Observatory = function(b, _ctx)
	-- télescope d'observatoire : trépied à entretoise, monture équatoriale,
	-- tube blanc à bagues, pare-soleil, chercheur, contrepoids
	b.Cyl(0, 0, 0, 40, 8, CARBON, M.Metal)
	b.Cyl(0, 8, 0, 12, 40, GREY, M.Metal)
	b.Ball(0, 48, 0, 18, CARBON, M.Metal)
	local axis = CFrame.new(0, 58, 0) * CFrame.Angles(0, 0, 0.5)
	b.BoxR(axis, 84, 20, 20, WHITE, M.SmoothPlastic)
	for _, dx in ipairs({ -18, 18 }) do
		b.BoxR(axis * CFrame.new(dx, 0, 0), 4, 22, 22, CARBON, M.Metal)
	end
	b.BoxR(CFrame.new(33, 78, 0) * CFrame.Angles(0, 0, 0.5), 18, 24, 24, CARBON, M.SmoothPlastic)
	b.BoxR(CFrame.new(-4, 72, 0) * CFrame.Angles(0, 0, 0.5), 30, 5, 5, GREY, M.Metal)
	b.BoxR(axis * CFrame.new(-44, 0, 0), 4, 14, 14, GOLD, M.Metal)
	b.Tube(0, 48, 0, -14, 36, 0, 3, GREY, M.Metal)
	b.Ball(-16, 34, 0, 10, GREY_DARK, M.Metal)
	b.Footprint(80, 40, 92)
end
R.MechRobot = function(b, _ctx)
	local white = b.Map(rgb(240, 244, 252))
	local blue = rgb(80, 150, 255)
	-- robot méca : pieds, jambes à pistons, torse à plaques et réacteur,
	-- épaulières, bras, tête à visière, antenne
	for _, x in ipairs({ -14, 14 }) do
		b.Box(x, 0, 0, 20, 10, 28, blue, M.SmoothPlastic)
		b.Box(x, 10, 0, 14, 26, 14, GREY, M.Metal)
		b.Cyl(x, 12, 6, 3, 20, CHROME, M.Metal).Reflectance = 0.3
		b.Ball(x, 24, 7, 8, white, M.SmoothPlastic)
	end
	b.Box(0, 36, 0, 50, 36, 30, white, M.SmoothPlastic)
	for _, dy in ipairs({ 44, 60 }) do
		b.Box(0, dy, 15.2, 46, 1, 0.8, GREY, M.Metal)
	end
	local core = b.Ball(0, 56, 15, 12, NEON_CYAN)
	b.Neon(core)
	b.Light(core, NEON_CYAN, 10, 0.8)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 30, 66, 0, 18, blue, M.SmoothPlastic)
		b.Box(side * 32, 34, 0, 12, 30, 12, white, M.SmoothPlastic)
		b.Ball(side * 32, 30, 0, 14, blue, M.SmoothPlastic)
		b.Box(side * 12, 64, -16, 8, 14, 6, GREY_DARK, M.Metal)
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
	-- statue d'astronaute : socle, bottes, combinaison (plis), sac vital,
	-- panneau de poitrine, casque à visière dorée réfléchissante, drapeau
	b.Cyl(0, 0, 0, 80, 10, rgb(200, 196, 220), M.Slate)
	b.Cyl(0, 10, 0, 76, 1.4, lighten(rgb(200, 196, 220), 0.2), M.Slate)
	for _, x in ipairs({ -8, 8 }) do
		b.Box(x, 10, 1, 13, 6, 16, GREY_DARK, M.Rubber)
		b.Box(x, 16, 0, 12, 12, 14, WHITE, M.Fabric)
		b.Cyl(x, 22, 0, 13, 1.4, GREY, M.Fabric)
	end
	b.Box(0, 28, -8, 36, 32, 10, GREY, M.Metal) -- sac à dos
	b.Round(0, 28, 0, 30, 32, 20, 5, WHITE, M.Fabric)
	b.Box(0, 40, 10.2, 12, 8, 0.6, NAVY)
	for index = 0, 2 do
		local led = b.Box(-3 + index * 3, 42, 10.8, 2, 2, 0.4, ({ RACE_RED, NEON_CYAN, BUTTER })[index + 1])
		b.Neon(led)
	end
	b.BoxR(CFrame.new(-20, 44, 0) * CFrame.Angles(0, 0, 0.3), 10, 24, 10, WHITE, M.Fabric)
	b.BoxR(CFrame.new(20, 64, 0) * CFrame.Angles(0, 0, -0.3), 10, 24, 10, WHITE, M.Fabric)
	b.Ball(-24, 32, 0, 9, WHITE, M.Fabric)
	b.Ball(0, 72, 0, 30, WHITE, M.SmoothPlastic)
	local visor = b.Ball(0, 72, 5, 22, rgb(200, 150, 60), M.Glass)
	visor.Reflectance = 0.35
	b.Cyl(36, 10, 10, 2, 60, GREY, M.Metal)
	b.Box(44, 58, 10, 16, 10, 0.6, rgb(80, 150, 255))
	b.Footprint(80, 40, 88)
end
R.PirateChest = function(b, _ctx)
	local wood = b.Map(rgb(170, 110, 70))
	-- coffre au trésor : planches, cerclages dorés rivetés, couvercle ouvert,
	-- pièces d'or, joyaux, collier de perles, serrure
	for index = 0, 3 do
		b.Box(0, index * 10, 0, 84, 10, 50, vary(wood, index, 0.06), M.WoodPlanks)
	end
	for _, x in ipairs({ -30, 30 }) do
		b.Box(x, 0, 0, 7, 40.4, 50.4, GOLD, M.Metal).Reflectance = 0.25
		for _, y in ipairs({ 8, 30 }) do
			b.Ball(x, y, 25.4, 2, darken(GOLD, 0.2), M.Metal)
		end
	end
	b.BoxR(CFrame.new(0, 58, -28) * CFrame.Angles(-1.1, 0, 0), 84, 30, 8, wood, M.Wood)
	b.BoxR(CFrame.new(-30, 58, -28) * CFrame.Angles(-1.1, 0, 0), 7, 30.4, 8.4, GOLD, M.Metal)
	b.BoxR(CFrame.new(30, 58, -28) * CFrame.Angles(-1.1, 0, 0), 7, 30.4, 8.4, GOLD, M.Metal)
	for index = 0, 11 do
		local coin = b.Cyl(-30 + (index % 6) * 12, 40 + (index > 5 and 4 or 0) + (index % 3), -8 + (index % 4) * 6, 9, 1.6, GOLD, M.Metal)
		coin.Reflectance = 0.3
	end
	b.Egg(0, 44, 0, 50, 10, 34, GOLD, M.Metal)
	b.Ball(-10, 48, 4, 8, RACE_RED, M.Glass).Reflectance = 0.3
	b.Ball(12, 48, 0, 8, NEON_CYAN, M.Glass).Reflectance = 0.3
	b.EggR(CFrame.new(20, 47, 8) * CFrame.Angles(0, 0, 0.785), 6, 6, 4, rgb(120, 255, 140), M.Glass)
	for index = 0, 6 do
		b.Ball(-24 + index * 4, 46 - math.sin(index / 6 * math.pi) * 4, 20, 2.4, WHITE, M.SmoothPlastic)
	end
	b.Box(0, 22, 25.3, 14, 14, 1.2, GOLD, M.Metal)
	b.Box(0, 26, 26, 3, 5, 0.6, INK, M.SmoothPlastic)
	b.Footprint(84, 50, 60)
end
R.Motorbike = function(b, _ctx)
	for _, x in ipairs({ -34, 34 }) do
		wheel3D(b, x, 18, 0, 36, 8, CHROME)
	end
	local red = b.Map(RACE_RED)
	-- moto : moteur à ailettes, réservoir galbé, selle, fourche, guidon,
	-- phare, garde-boues, échappement chromé
	b.Box(-4, 28, 0, 34, 20, 14, CHROME, M.Metal).Reflectance = 0.3
	for index = 0, 3 do
		b.Box(-4, 30 + index * 4.4, 0, 36, 1.4, 16, GREY, M.Metal)
	end
	b.Egg(6, 52, 0, 34, 16, 18, red, M.SmoothPlastic).Reflectance = 0.15
	b.Box(-22, 50, 0, 28, 6, 16, INK, M.Leather)
	b.Egg(-22, 54, 0, 28, 4, 16, INK, M.Leather)
	b.BoxR(CFrame.new(30, 40, 0) * CFrame.Angles(0, 0, -0.45), 5, 50, 5, CHROME, M.Metal)
	b.Box(22, 64, 0, 4, 4, 34, INK, M.Metal)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(22, 64, sz * 17, 4 + 2 * House3DKit.Gap(b, 0.5), 4 + 2 * House3DKit.Gap(b, 0.5), 6, INK, M.Rubber)
	end
	local lamp = b.CylX(36, 56, 0, 10, 4, BUTTER)
	b.Neon(lamp)
	b.CylX(34, 56, 0, 12, 3, CHROME, M.Metal)
	for _, x in ipairs({ -34, 34 }) do
		b.BoxR(CFrame.new(x, 36, 0) * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3), 20, 2, 10, red, M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(-30, 22, 8) * CFrame.Angles(0, 0, 0.15), 40, 5, 5, CHROME, M.Metal).Reflectance = 0.35 -- échappement
	b.Footprint(100, 24, 70)
end
R.DinoSkeleton = function(b, _ctx)
	b.Box(0, 0, 0, 96, 8, 36, CARBON, M.Marble)
	local bone = rgb(246, 238, 220)
	-- squelette de dino : colonne (vertèbres à apophyses), côtes courbes,
	-- pattes à griffes, crâne à mâchoire et dents, plaque dorée
	local spine = { { -46, 36 }, { -30, 44 }, { -14, 48 }, { 2, 50 }, { 16, 54 }, { 26, 64 }, { 30, 74 } }
	for index, p in ipairs(spine) do
		b.Ball(p[1], p[2], 0, 7, bone, M.Marble)
		b.Box(p[1], p[2] + 2, 0, 2, 6, 2, bone, M.Marble)
		local next = spine[index + 1]
		if next then
			local dx, dy = next[1] - p[1], next[2] - p[2]
			b.BoxR(CFrame.new((p[1] + next[1]) / 2, (p[2] + next[2]) / 2, 0) * CFrame.Angles(0, 0, math.atan2(dy, dx)), math.sqrt(dx * dx + dy * dy), 3, 3, bone, M.Marble)
		end
	end
	for index = 0, 3 do
		for _, sz in ipairs({ -1, 1 }) do
			b.Tube(-8 + index * 6, 48, 0, -8 + index * 6, 36 - index, sz * 8, 2, bone, M.Marble)
			b.Tube(-8 + index * 6, 36 - index, sz * 8, -8 + index * 6, 30 + index * 2, 0, 2, bone, M.Marble)
		end
	end
	for _, x in ipairs({ -10, 10 }) do
		b.Box(x, 8, 0, 4, 42, 4, bone, M.Marble)
		b.Ball(x, 30, 0, 6, bone, M.Marble)
		for _, dz in ipairs({ -2, 2 }) do
			b.Wedge(x + 3, 8, dz, 4, 3, 2, bone, "Right", M.Marble)
		end
	end
	b.Box(36, 70, 0, 26, 14, 14, bone, M.Marble)
	b.Box(38, 64, 0, 22, 5, 12, bone, M.Marble)
	b.Ball(34, 74, 7.4, 4, INK, M.SmoothPlastic)
	for index = 0, 4 do
		b.Wedge(28 + index * 4.4, 68.4, 5, 2, 3, 2, WHITE, "Front", M.Marble)
	end
	b.Box(0, 4, 18.3, 20, 5, 0.6, GOLD, M.Metal)
	b.Footprint(96, 36, 86)
end

-- (v9.8) finition réaliste de toutes les recettes ci-dessus : reflets du
-- métal, du verre, du marbre (voir House3DKit.Polish)
do
	local polished: { [Recipe]: Recipe } = {}
	for id, recipe in pairs(R) do
		local wrapped = polished[recipe]
		if not wrapped then
			wrapped = House3DKit.Polished(recipe)
			polished[recipe] = wrapped
		end
		R[id] = wrapped
	end
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
	plaque = plaque("Frame"),
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
loadFamilies("House3DSetup") -- v9.5 🖥️ objets "Dopamine Setup"
loadFamilies("House3DLuxe") -- v9.8 🛍️ CATALOG98 : moderne, loft, luxe, gamer, sport, objets incroyables

local DOORS_AS_CARD: { [string]: boolean } = {}

-- Objets qu'on colle contre le mur du fond (portes, grands rangements)
local AGAINST_WALL: { [string]: boolean } = {
	Wardrobe = true, Bookshelf = true, Fridge = true, Fireplace = true, Dresser = true, DrawerCabinet = true,
	HomeCinema = true, TVStand = true, KitchenIsland = false, Shower = true, ToriiGate = true, ArcadeMachine = true,
	SlotMachine = true, Speaker = true, VanityTable = true, Aquarium = true, Stove = true, Toilet = true,
	KitchenSink = true, Jukebox = true, PinballMachine = false, LadderShelf = true,
	-- v9.2
	LockerCabinet = true, NeonArcade = true, SharkTank = true, GuitarAmp = true,
	-- v9.8 CATALOG98
	BookshelfWall = true, LoftShelf = true, GrandfatherClock = true, SteelFridge = true, AquariumWall = true, IndoorWaterfall = true,
	MediaConsole = true, TwinArcade = true, ClawMachine = true,
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
	-- (v9.6) anti-scintillement : faces confondues de l'objet écartées
	local okSep, errSep = pcall(House3DKit.Separate, b.Parts)
	if not okSep then
		warn("[House3D] Separate " .. tostring(item.Id) .. " : " .. tostring(errSep))
	end
	-- dessus déclarés par HouseSurfaces mais pas par la recette
	local raw = ctx.Raw
	if raw then
		for index, surface in ipairs(raw) do
			if not b.Tops[index] and type(surface) == "table" then
				local x0, x1, y = tonumber(surface[1]) or 10, tonumber(surface[2]) or 90, tonumber(surface[3]) or 50
				-- (v9.6 PLACE96) 4e valeur facultative : profondeur du centre du niveau,
				-- en fraction de la profondeur du modèle (-0,5 = fond, +0,5 = devant)
				b.Tops[index] = { X = ((x0 + x1) / 2 - 50) * (mirror and -1 or 1), Y = 100 - y, Z = (tonumber(surface[4]) or 0) * b.Depth, W = x1 - x0, D = b.Depth * 0.8 }
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
			-- (v9.6 "flash bang" : plus de x1,7 la nuit dans les pièces de la ville)
			light.Brightness *= opts.Night == true and 1.15 or 0.85
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
	-- (v9.8) le tunnel-aquarium est une arche sous laquelle on passe : pas de bloc plein
	local walkUnder = itemId == "AquariumTunnel"
	if collide and not wall and not walkUnder and not data.Info.Flat and height >= 1.5 and math.max(fw, fd) >= 1.8 then
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
	-- (v9.6 PLACE96) chaque niveau (étagères...) : FurnitureEdit choisit le
	-- niveau d'après la hauteur touchée en 3D (repère du modèle, devant -Z)
	for index, t in pairs(data.Tops) do
		model:SetAttribute("Top" .. tostring(index), Vector3.new(-t.X * k, t.Y * k, -t.Z * k))
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
