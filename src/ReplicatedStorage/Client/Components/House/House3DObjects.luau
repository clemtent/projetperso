--[[
	House3DObjects (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DObjects

	(v9.3) Recettes 3D des objets de déco, lumières, portes, fenêtres et
	plantes qui n'avaient pas de vrai modèle : chaque objet est une petite
	maquette en vraies pièces (blocs, ovales, tubes, pentes, néons) aux
	couleurs de son dessin 2D. Les objets muraux sont construits contre le
	mur (z = 0 = le mur, +z vers la pièce ; y = 0..100 = leur boîte 2D).

	Branché par House3DRecipes (Register) ; voir House3DToys pour les jouets,
	l'électronique, la cuisine, le sport.
]]

local House3DKit = require(script.Parent.House3DKit)

type Builder = House3DKit.Builder

local House3DObjects = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(60, 44, 66)
local GOLD = rgb(245, 190, 60)
local BUTTER = rgb(255, 226, 130)
local GLASS = rgb(200, 235, 255)
local LEAF = rgb(110, 196, 110)
local WOOD = rgb(214, 164, 120)
local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

local R: { [string]: (b: Builder, ctx: any) -> () } = {}
local H: any = nil -- aides de House3DRecipes (Register)

local function vivid(b: Builder, n: number, fallback: Color3): Color3
	local count = 0
	for _, color in ipairs(b.Pal) do
		local _h, s, v = color:ToHSV()
		if s > 0.2 and v > 0.35 then
			count += 1
			if count == n then
				return color
			end
		end
	end
	return b.Map(fallback)
end

----------------------------------------------------------------------
-- DÉCO MURALE
----------------------------------------------------------------------

R.HeartSticker = function(b, _ctx)
	local pink = vivid(b, 1, rgb(255, 110, 160))
	House3DKit.Heart(b, 0, 50, 0, 84, 3, lighten(pink, 0.5), M.SmoothPlastic)
	House3DKit.Heart(b, 0, 51, 2, 70, 3, pink, M.SmoothPlastic)
	b.Egg(-16, 62, 5, 12, 8, 2, WHITE, M.SmoothPlastic)
	b.Footprint(84, 6, 90)
end

R.GiantBow = function(b, _ctx)
	local ribbon = vivid(b, 1, rgb(255, 110, 160))
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * 22, 58, 8) * CFrame.Angles(0, 0, side * 0.35), 44, 32, 14, ribbon, M.Fabric)
		b.EggR(CFrame.new(side * 22, 58, 12) * CFrame.Angles(0, 0, side * 0.35), 24, 14, 10, darken(ribbon, 0.2), M.Fabric)
		b.BoxR(CFrame.new(side * 12, 28, 6) * CFrame.Angles(0, 0, side * -0.3), 12, 40, 5, ribbon, M.Fabric)
		b.Part("WedgePart", CFrame.new(side * 17, 7, 6) * CFrame.Angles(0, math.pi / 2, math.pi), Vector3.new(5, 8, 12), ribbon, M.Fabric, "Pointe")
	end
	b.Egg(0, 58, 14, 18, 20, 14, lighten(ribbon, 0.15), M.Fabric)
	b.Footprint(96, 22, 90)
end

R.Balloons = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 120, 160)), vivid(b, 2, rgb(120, 190, 255)), vivid(b, 3, rgb(255, 214, 90)), vivid(b, 4, rgb(170, 140, 255)) }
	local spots = { { -18, 70, 10 }, { 14, 76, 14 }, { -2, 88, 6 }, { 24, 58, 8 }, { -26, 52, 14 } }
	for index, p in ipairs(spots) do
		local color = colors[(index - 1) % #colors + 1]
		b.Egg(p[1], p[2], p[3], 24, 30, 24, color, M.SmoothPlastic)
		b.Egg(p[1] - 5, p[2] + 7, p[3] + 10, 5, 8, 3, lighten(color, 0.6), M.SmoothPlastic)
		b.Cyl(p[1], p[2] - 17, p[3], 4, 3, darken(color, 0.1), M.SmoothPlastic)
		b.Tube(p[1], p[2] - 16, p[3], 0, 10, 8, 0.8, WHITE, M.SmoothPlastic)
	end
	b.EggR(CFrame.new(0, 10, 8), 8, 6, 6, colors[1], M.Fabric)
	b.Footprint(80, 30, 100)
end

-- Guirlande de fanions / d'étoiles / de lunes : une corde et des motifs
local function garland(kind: string)
	return function(b: Builder, _ctx: any)
		local colors = { vivid(b, 1, rgb(255, 120, 160)), vivid(b, 2, rgb(120, 200, 255)), vivid(b, 3, rgb(255, 214, 90)), vivid(b, 4, rgb(140, 220, 150)) }
		local count = kind == "Flags" and 9 or 7
		local points = {}
		for index = 0, count do
			local t = index / count
			table.insert(points, { -48 + t * 96, 78 - math.sin(t * math.pi) * 20, 3 })
		end
		House3DKit.Path(b, points, 1.4, kind == "Stars" and GOLD or rgb(240, 230, 220), M.SmoothPlastic)
		for index = 1, count - 1 do
			local p = points[index + 1]
			local color = colors[index % #colors + 1]
			if kind == "Flags" then
				House3DKit.Triangle(b, p[1], p[2] - 9, 2.5, 10, 16, math.pi, 1.5, color, M.Fabric)
			elseif kind == "Stars" then
				local star = b.Part("Part", CFrame.new(p[1], p[2] - 6, 4), Vector3.new(0.1, 0.1, 0.1), color, M.SmoothPlastic, "Accroche")
				star.Transparency = 1
				House3DKit.StarSoft(b, p[1], p[2] - 9, 2.5, 8, 2, index % 2 == 0 and BUTTER or color, M.Neon)
			else
				-- lunes : un disque et un disque "mangeur" couleur du mur
				local moon = b.CylZ(p[1], p[2] - 9, 3.5, 12, 2, BUTTER, M.SmoothPlastic)
				moon.Material = M.Neon
				b.CylZ(p[1] + 4, p[2] - 7, 4.8, 10, 1, lighten(color, 0.4), M.SmoothPlastic)
				b.Tube(p[1], p[2], 3, p[1], p[2] - 4, 3, 0.6, WHITE, M.SmoothPlastic)
			end
		end
		b.Footprint(100, 6, 100)
	end
end
R.PartyBunting = garland("Flags")
R.StarGarland = garland("Stars")
R.MoonGarland = garland("Moons")

R.PhotoString = function(b, _ctx)
	local points = {}
	for index = 0, 8 do
		local t = index / 8
		table.insert(points, { -48 + t * 96, 80 - math.sin(t * math.pi) * 14, 3 })
	end
	House3DKit.Path(b, points, 1.2, rgb(200, 160, 120), M.SmoothPlastic)
	local colors = { vivid(b, 1, rgb(255, 170, 200)), vivid(b, 2, rgb(140, 200, 255)), vivid(b, 3, rgb(255, 214, 120)), vivid(b, 4, rgb(150, 220, 170)) }
	for index = 1, 4 do
		local p = points[index * 2]
		local tilt = (index % 2 == 0 and 1 or -1) * 0.12
		local cf = CFrame.new(p[1], p[2] - 13, 3.5) * CFrame.Angles(0, 0, tilt)
		b.BoxR(cf, 17, 20, 1, WHITE)
		b.BoxR(cf * CFrame.new(0, 2, 0.6), 13, 12, 0.5, colors[index])
		b.BoxR(cf * CFrame.new(0, 10, 0.9), 3, 5, 1, rgb(200, 150, 110), M.Wood)
	end
	b.Footprint(100, 6, 100)
end

-- (v9.8) VRAI miroir : cadre en cœur (deux épaisseurs), glace en cœur
-- réfléchissante et, au centre, la surface "Mirror" (ovale) taguée pour les
-- reflets en temps réel de REALISM98 ; perles autour, attache
R.HeartMirror = function(b, _ctx)
	local frame = vivid(b, 1, rgb(255, 150, 190))
	local g = House3DKit.Gap(b, 0.8)
	House3DKit.Heart(b, 0, 50, 0, 90, 4, frame, M.SmoothPlastic)
	House3DKit.Heart(b, 0, 50.4, 4, 82, g, lighten(frame, 0.25), M.SmoothPlastic)
	local before = #b.Parts
	House3DKit.Heart(b, 0, 51, 4 + g, 72, 2, rgb(214, 228, 238), M.Glass)
	for index = before + 1, #b.Parts do
		b.Parts[index].Reflectance = 0.45
		b.Parts[index].CastShadow = false
	end
	House3DKit.Mirror(b, 0, 53, 6 + g + 0.4, 44, 40, "Oval")
	for index, p in ipairs(House3DKit.HeartPoints(0, 50, 5, 90, 14)) do
		if index <= 14 then
			b.Ball(p[1], p[2], 5, 5, index % 2 == 0 and GOLD or WHITE, M.SmoothPlastic).Reflectance = index % 2 == 0 and 0.3 or 0.1
		end
	end
	b.Ball(0, 90, 2, 5, GOLD, M.Metal)
	b.Footprint(90, 8, 90)
end

-- (v9.8) Grand miroir mural en arche : moulure dorée en relief (montants,
-- arc, filet intérieur), glace pleine hauteur taguée "Mirror" (rectangle +
-- arc réfléchissant), tablette basse, attaches
R.BigWallMirror = function(b, _ctx)
	local frame = vivid(b, 1, rgb(230, 190, 110))
	local g = House3DKit.Gap(b, 0.8)
	local w, y0, yArc = 56, 6, 64
	-- glace : partie droite = surface Mirror (Rect), arc = verre réfléchissant
	House3DKit.Mirror(b, 0, (y0 + yArc) / 2, 2 + g, w, yArc - y0, "Rect")
	local arc = b.CylZ(0, yArc, 2 - g / 2, w, g, rgb(214, 228, 238), M.Glass)
	arc.Reflectance = 0.45
	arc.CastShadow = false
	b.Box(0, y0, 0.5, w + 2, yArc - y0, 1, darken(frame, 0.5), M.SmoothPlastic)
	-- cadre mouluré
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 + 3), y0 - 2, 2, 6, yArc - y0 + 2, 6, frame, M.Metal)
		b.Box(side * (w / 2 + 0.6), y0, 3.4 + g, 1.2, yArc - y0, 2, lighten(frame, 0.25), M.Metal)
	end
	local points = {}
	for index = 0, 12 do
		local a = index / 12 * math.pi
		table.insert(points, { math.cos(a) * (w / 2 + 3), yArc + math.sin(a) * (w / 2 + 3), 5 })
	end
	for _, part in ipairs(House3DKit.Path(b, points, 6, frame, M.Metal)) do
		part.Reflectance = 0.25
	end
	b.Box(0, y0 - 6, 3, w + 14, 5, 8, frame, M.Metal)
	b.Box(0, y0 - 7, 5, w + 10, 2, 8, darken(frame, 0.15), M.Metal)
	House3DKit.StarSoft(b, 0, yArc + w / 2 + 3, 6, 4, 2, lighten(frame, 0.2), M.Metal)
	for _, x in ipairs({ -w / 2 - 3, w / 2 + 3 }) do
		b.Ball(x, y0 - 4, 7, 5, lighten(frame, 0.2), M.Metal).Reflectance = 0.3
	end
	b.Footprint(w + 14, 10, 100)
end

R.GlowStars = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 240, 150))
	local spots = { { -26, 70, 16 }, { 18, 78, 12 }, { 2, 46, 20 }, { -30, 30, 10 }, { 30, 36, 14 }, { 34, 64, 8 }, { -8, 18, 8 } }
	for index, p in ipairs(spots) do
		local core = House3DKit.StarSoft(b, p[1], p[2], 0, p[3], 2, index % 3 == 0 and rgb(190, 250, 200) or color, M.Neon)
		if index == 3 then
			b.Light(core, color, 8, 0.5)
		end
	end
	b.Footprint(90, 3, 100)
end

R.DreamCatcher = function(b, _ctx)
	local ring = vivid(b, 1, rgb(210, 160, 110))
	local feather = { vivid(b, 2, rgb(255, 170, 200)), vivid(b, 3, rgb(170, 150, 255)), WHITE }
	local points = {}
	for index = 0, 16 do
		local a = index / 16 * math.pi * 2
		table.insert(points, { math.cos(a) * 24, 66 + math.sin(a) * 24, 3 })
	end
	House3DKit.Path(b, points, 3.5, ring, M.Wood)
	-- toile
	for index = 0, 5 do
		local a = index / 6 * math.pi
		b.Tube(math.cos(a) * 22, 66 + math.sin(a) * 22, 3, -math.cos(a) * 22, 66 - math.sin(a) * 22, 3, 0.6, WHITE, M.SmoothPlastic)
	end
	b.Ball(0, 66, 3.5, 6, feather[2], M.Glass)
	-- plumes
	for index, x in ipairs({ -16, 0, 16 }) do
		local y = 34 - (index == 2 and 8 or 0)
		b.Tube(x, 44, 3, x, y + 8, 3, 0.6, WHITE, M.SmoothPlastic)
		b.Ball(x, y + 10, 3, 4, feather[index], M.SmoothPlastic)
		b.EggR(CFrame.new(x, y - 4, 3), 8, 22, 2, feather[index], M.Fabric)
	end
	b.Footprint(56, 6, 100)
end

-- Horloge à coucou : chalet, cadran, balancier, pommes de pin
R.CuckooClock = function(b, _ctx)
	local wood = darken(H.woodOf(b, rgb(170, 110, 70)), 0.1)
	b.Box(0, 30, 3, 50, 44, 10, wood, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 15, 82, 5) * CFrame.Angles(0, 0, side * -0.62), 38, 6, 16, darken(wood, 0.25), M.Wood)
	end
	b.CylZ(0, 50, 8.5, 30, 2, rgb(255, 248, 232), M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 54, 10), 1.6, 10, 1, INK)
	b.BoxR(CFrame.new(3, 50, 10) * CFrame.Angles(0, 0, -1.2), 1.6, 8, 1, INK)
	b.Box(0, 72, 7, 10, 8, 2, rgb(60, 40, 40))
	b.Ball(0, 76, 11, 7, rgb(255, 214, 90))
	b.Tube(0, 30, 6, 0, 10, 6, 1, GOLD, M.Metal)
	b.CylZ(0, 9, 6, 10, 1.5, GOLD, M.Metal)
	for _, x in ipairs({ -12, 12 }) do
		b.Tube(x, 30, 5, x, 16, 5, 0.6, INK, M.SmoothPlastic)
		b.Egg(x, 12, 5, 7, 12, 7, rgb(150, 100, 60), M.Wood)
	end
	b.Footprint(60, 16, 100)
end

-- Horloges murales (chat / soleil)
R.KittyClock = function(b, _ctx)
	local body = vivid(b, 1, rgb(255, 150, 190))
	b.CylZ(0, 50, 3, 70, 6, body, M.SmoothPlastic)
	b.CylZ(0, 50, 6.5, 56, 1, rgb(255, 250, 244), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		House3DKit.Triangle(b, side * 22, 88, 0, 20, 18, side * -0.3, 6, body, M.SmoothPlastic)
		b.Ball(side * 12, 60, 7.5, 7, INK, M.SmoothPlastic)
	end
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		b.Box(math.sin(a) * 23, 50 + math.cos(a) * 23 - 1.5, 7.2, 2, 3, 0.8, INK)
	end
	b.BoxR(CFrame.new(0, 58, 8), 2, 16, 1, INK)
	b.BoxR(CFrame.new(5, 48, 8.5) * CFrame.Angles(0, 0, -1.4), 2, 12, 1, INK)
	b.Ball(0, 50, 8.6, 4, body, M.SmoothPlastic)
	-- queue-balancier
	b.Tube(0, 16, 4, 6, 4, 4, 5, body, M.SmoothPlastic)
	b.Footprint(76, 12, 100)
end

R.Tapestry = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 120, 140)), vivid(b, 2, rgb(255, 190, 90)), vivid(b, 3, rgb(255, 236, 120)), vivid(b, 4, rgb(140, 220, 150)), vivid(b, 5, rgb(120, 180, 255)), vivid(b, 6, rgb(180, 140, 255)) }
	b.CylX(0, 92, 3, 5, 92, rgb(170, 120, 80), M.Wood)
	for index = 1, 6 do
		b.Box(0, 14 + (6 - index) * 13, 2, 80, 13, 1.5, colors[index], M.Fabric)
	end
	for index = 0, 9 do
		b.Box(-36 + index * 8, 6, 2, 2, 9, 1.2, rgb(250, 240, 230), M.Fabric)
	end
	b.Footprint(92, 6, 100)
end

R.ButterflyFrame = function(b, _ctx)
	local frame = vivid(b, 1, rgb(210, 170, 110))
	local wing = { vivid(b, 2, rgb(120, 190, 255)), vivid(b, 3, rgb(255, 150, 200)) }
	House3DKit.Frame(b, 0, 8, 3, 76, 84, 7, 6, frame, M.Wood)
	b.Box(0, 12, 1, 66, 76, 1, rgb(255, 250, 240), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * 12, 58, 2.5) * CFrame.Angles(0, 0, side * -0.4), 22, 28, 1.5, wing[1], M.SmoothPlastic)
		b.EggR(CFrame.new(side * 10, 38, 2.5) * CFrame.Angles(0, 0, side * 0.5), 16, 20, 1.5, wing[2], M.SmoothPlastic)
		b.Ball(side * 14, 60, 3.4, 5, WHITE, M.SmoothPlastic)
		b.Tube(0, 66, 3, side * 8, 78, 3, 0.8, INK, M.SmoothPlastic)
	end
	b.EggR(CFrame.new(0, 50, 3), 5, 34, 3, INK, M.SmoothPlastic)
	local glass = b.Box(0, 12, 6.2, 66, 76, 0.4, GLASS, M.Glass)
	glass.Transparency = 0.85
	b.Footprint(76, 8, 100)
end

-- Affiches, drapeaux : cadre / baguettes + le dessin 2D sur la face avant
local function poster(framed: boolean)
	return function(b: Builder, _ctx: any)
		local frame = framed and darken(vivid(b, 1, rgb(80, 90, 140)), 0.3) or rgb(240, 236, 230)
		if framed then
			House3DKit.Frame(b, 0, 4, 2, 84, 92, 5, 5, frame, M.Wood)
			b.Art(0, 8, 0.5, 74, 84, 1.05)
		else
			b.Art(0, 6, 0.5, 80, 88, 1.02)
			for _, x in ipairs({ -36, 36 }) do
				b.Ball(x, 90, 2.2, 5, rgb(255, 110, 140), M.SmoothPlastic)
			end
		end
		b.Footprint(84, 6, 100)
	end
end
R.HeroPoster = poster(false)
R.ComicPoster = poster(false)
R.JerseyFrame = function(b, _ctx)
	local shirt = vivid(b, 1, rgb(240, 70, 80))
	local frame = rgb(60, 60, 80)
	House3DKit.Frame(b, 0, 4, 3, 84, 92, 6, 6, frame, M.Wood)
	b.Box(0, 10, 1, 72, 80, 1, rgb(250, 248, 244), M.SmoothPlastic)
	b.Box(0, 18, 2.5, 38, 50, 2, shirt, M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(side * 25, 58, 3.5) * CFrame.Angles(0, 0, side * -0.6), 14, 24, 2, shirt, M.Fabric)
	end
	b.Box(0, 64, 3.8, 14, 4, 1, WHITE, M.Fabric)
	b.Box(0, 32, 3.6, 5, 22, 0.6, WHITE, M.SmoothPlastic)
	b.Box(6, 32, 3.6, 5, 22, 0.6, WHITE, M.SmoothPlastic)
	local glass = b.Box(0, 10, 5.8, 72, 80, 0.4, GLASS, M.Glass)
	glass.Transparency = 0.85
	b.Footprint(84, 8, 100)
end
R.NinjaBanner = function(b, _ctx)
	local paper = rgb(250, 240, 214)
	local red = vivid(b, 1, rgb(220, 60, 60))
	b.CylX(0, 92, 3, 6, 60, rgb(120, 70, 50), M.Wood)
	b.CylX(0, 8, 3, 6, 60, rgb(120, 70, 50), M.Wood)
	for _, x in ipairs({ -32, 32 }) do
		b.CylX(x, 92, 3, 8, 4, GOLD, M.Metal)
		b.CylX(x, 8, 3, 8, 4, GOLD, M.Metal)
	end
	b.Box(0, 10, 2, 50, 80, 1.5, paper, M.Fabric)
	b.CylZ(0, 64, 3, 22, 1, red, M.SmoothPlastic)
	-- trois traits d'encre (kanji stylisé)
	b.BoxR(CFrame.new(0, 40, 3.2), 4, 28, 1, INK)
	b.BoxR(CFrame.new(0, 44, 3.3) * CFrame.Angles(0, 0, 1.57), 4, 24, 1, INK)
	b.BoxR(CFrame.new(-6, 28, 3.3) * CFrame.Angles(0, 0, 0.7), 3, 14, 1, INK)
	b.BoxR(CFrame.new(6, 28, 3.3) * CFrame.Angles(0, 0, -0.7), 3, 14, 1, INK)
	b.Tube(-20, 92, 3, 0, 100, 3, 0.8, INK, M.SmoothPlastic)
	b.Tube(20, 92, 3, 0, 100, 3, 0.8, INK, M.SmoothPlastic)
	b.Footprint(64, 8, 100)
end

R.WindChime = function(b, _ctx)
	local color = vivid(b, 1, rgb(140, 200, 255))
	b.CylZ(0, 80, 8, 1, 1, INK, M.SmoothPlastic)
	b.Tube(0, 100, 8, 0, 82, 8, 0.8, INK, M.SmoothPlastic)
	local bell = b.Egg(0, 74, 8, 30, 18, 30, lighten(color, 0.3), M.Glass)
	bell.Transparency = 0.3
	b.Cyl(0, 66, 8, 30, 2, color, M.Glass)
	for index = 0, 4 do
		local a = index / 5 * math.pi * 2
		local x, z = math.cos(a) * 9, 8 + math.sin(a) * 6
		b.Tube(x, 66, z, x, 52 - index * 3, z, 0.6, WHITE, M.SmoothPlastic)
		b.Cyl(x, 34 - index * 3, z, 4, 18, index % 2 == 0 and rgb(220, 220, 235) or GOLD, M.Metal)
	end
	b.Tube(0, 66, 8, 0, 30, 8, 0.6, WHITE, M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 22, 8), 12, 16, 0.8, rgb(255, 240, 200), M.Fabric)
	b.Footprint(40, 20, 100)
end

R.CarpStreamer = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(240, 80, 80)), vivid(b, 2, rgb(90, 140, 255)), vivid(b, 3, rgb(255, 150, 190)) }
	b.Tube(-44, 96, 4, 44, 96, 4, 2.5, rgb(180, 130, 90), M.Wood)
	for index, color in ipairs(colors) do
		local y = 86 - (index - 1) * 26
		local len = 70 - index * 8
		b.Tube(-44 + index * 4, 96, 4, -40 + index * 4, y, 4, 0.6, INK, M.SmoothPlastic)
		b.EggR(CFrame.new(-40 + index * 4 + len / 2, y - 4, 6), len, 18, 10, color, M.Fabric)
		b.CylX(-40 + index * 4 + 3, y - 4, 6, 16, 3, WHITE, M.Fabric)
		b.Ball(-40 + index * 4 + 10, y - 2, 11, 7, WHITE, M.SmoothPlastic)
		b.Ball(-40 + index * 4 + 10, y - 2, 13.5, 3.5, INK, M.SmoothPlastic)
		House3DKit.Triangle(b, -40 + index * 4 + len + 2, y - 4, 5, 16, 10, -math.pi / 2, 2, darken(color, 0.1), M.Fabric)
	end
	b.Footprint(96, 16, 100)
end

R.Pinata = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 120, 170)), vivid(b, 2, rgb(255, 210, 80)), vivid(b, 3, rgb(120, 210, 255)), vivid(b, 4, rgb(140, 220, 140)) }
	b.Tube(0, 100, 8, 0, 70, 8, 0.8, INK, M.SmoothPlastic)
	-- âne en bandes de papier
	for index = 0, 4 do
		b.Box(-28 + index * 11, 40, 8, 11, 24, 22, colors[index % 4 + 1], M.Fabric)
	end
	for _, x in ipairs({ -22, 18 }) do
		for _, z in ipairs({ 1, 15 }) do
			b.Box(x, 14, z, 7, 26, 7, colors[(x + z) % 4 + 1], M.Fabric)
		end
	end
	b.Box(22, 60, 8, 14, 22, 14, colors[1], M.Fabric)
	b.Box(26, 72, 8, 16, 12, 16, colors[2], M.Fabric)
	b.Box(34, 76, 8, 8, 8, 12, colors[3], M.Fabric)
	b.Ball(33, 80, 15, 3.5, INK, M.SmoothPlastic)
	for _, dz in ipairs({ -4, 4 }) do
		House3DKit.Triangle(b, 22, 92, 8 + dz, 6, 10, 0, 2, colors[4], M.Fabric)
	end
	for index = 0, 4 do
		b.BoxR(CFrame.new(-32, 46 - index * 3, 8) * CFrame.Angles(0, 0, 0.3), 2, 18, 3, colors[index % 4 + 1], M.Fabric)
	end
	b.Footprint(80, 24, 100)
end

R.FloatingPlanet = function(b, _ctx)
	local planet = vivid(b, 1, rgb(255, 180, 110))
	local ring = vivid(b, 2, rgb(170, 150, 255))
	b.Tube(0, 100, 20, 0, 82, 20, 0.8, INK, M.SmoothPlastic)
	b.Ball(0, 55, 20, 52, planet, M.SmoothPlastic)
	b.Egg(-8, 64, 36, 16, 8, 8, lighten(planet, 0.3), M.SmoothPlastic)
	b.Egg(10, 46, 38, 12, 6, 6, darken(planet, 0.15), M.SmoothPlastic)
	b.Part("Part", CFrame.new(0, 55, 20) * CFrame.Angles(0, 0, 0.35) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2, 92, 92), ring, M.SmoothPlastic, "Anneau")
	local ringPart = b.Parts[#b.Parts];
	(ringPart :: Part).Shape = Enum.PartType.Cylinder
	b.Part("Part", CFrame.new(0, 55, 20) * CFrame.Angles(0, 0, 0.35) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2.4, 60, 60), lighten(planet, 0.1), M.SmoothPlastic, "Anneau");
	((b.Parts[#b.Parts]) :: Part).Shape = Enum.PartType.Cylinder
	for index = 0, 3 do
		local a = index * 1.7
		local star = b.Ball(math.cos(a) * 42, 55 + math.sin(a) * 36, 22, 5, BUTTER, M.Neon)
		star.CastShadow = false
	end
	b.Footprint(96, 44, 100)
end

R.PlanetMobile = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 170, 90)), vivid(b, 2, rgb(120, 180, 255)), vivid(b, 3, rgb(255, 120, 150)), vivid(b, 4, rgb(150, 220, 140)) }
	b.Tube(0, 100, 20, 0, 88, 20, 0.8, INK, M.SmoothPlastic)
	b.CylX(0, 86, 20, 2.5, 90, rgb(200, 170, 120), M.Wood)
	b.CylZ(0, 86, 20, 2.5, 30, rgb(200, 170, 120), M.Wood)
	local sun = b.Ball(0, 58, 20, 22, rgb(255, 214, 90), M.Neon)
	b.Light(sun, rgb(255, 220, 150), 8, 0.6)
	b.Tube(0, 86, 20, 0, 69, 20, 0.5, WHITE, M.SmoothPlastic)
	local spots = { { -42, 50, 20, 14 }, { 42, 42, 20, 18 }, { 0, 34, 6, 12 }, { 0, 48, 34, 10 } }
	for index, p in ipairs(spots) do
		local x, z = p[1], p[3]
		b.Tube(x, 86, z, x, p[2] + p[4] / 2, z, 0.5, WHITE, M.SmoothPlastic)
		b.Ball(x, p[2], z, p[4], colors[index], M.SmoothPlastic)
		if index == 2 then
			local ring = b.Part("Part", CFrame.new(x, p[2], z) * CFrame.Angles(0, 0, 0.3) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(1, 30, 30), lighten(colors[index], 0.4), M.SmoothPlastic, "Anneau");
			(ring :: Part).Shape = Enum.PartType.Cylinder
		end
	end
	b.Footprint(96, 40, 100)
end

-- Étagère à trophées murale
R.TrophyShelf = function(b, _ctx)
	local wood = H.woodOf(b, rgb(170, 120, 80))
	for _, y in ipairs({ 16, 56 }) do
		b.Box(0, y, 10, 96, 4, 20, wood, M.Wood)
		for _, x in ipairs({ -40, 40 }) do
			b.Wedge(x, y - 10, 4, 4, 10, 8, darken(wood, 0.2), "Front", M.Wood)
		end
	end
	local metals = { GOLD, rgb(210, 214, 226), rgb(210, 140, 90) }
	for row, y in ipairs({ 20, 60 }) do
		for index, x in ipairs({ -28, 0, 28 }) do
			local metal = metals[(index + row) % 3 + 1]
			b.Box(x, y, 12, 14, 5, 10, rgb(60, 50, 60), M.Wood)
			b.Cyl(x, y + 5, 12, 3, 8, metal, M.Metal)
			b.Egg(x, y + 20, 12, 16, 14, 16, metal, M.Metal)
			b.Cyl(x, y + 23, 12, 16, 3, metal, M.Metal)
			for _, side in ipairs({ -1, 1 }) do
				b.Tube(x + side * 8, y + 24, 12, x + side * 11, y + 17, 12, 2, metal, M.Metal)
			end
		end
	end
	b.Top(1, 0, 20, 10, 90, 16)
	b.Footprint(96, 20, 100)
end

-- Porte-skates mural : 3 planches en biais sur des crochets
R.SkateRack = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 110, 150)), vivid(b, 2, rgb(90, 180, 255)), vivid(b, 3, rgb(140, 220, 120)) }
	b.Box(0, 44, 1.5, 96, 12, 3, rgb(90, 80, 100), M.Wood)
	for index, color in ipairs(colors) do
		local x = -32 + (index - 1) * 32
		b.Box(x, 50, 5, 4, 3, 10, rgb(200, 200, 210), M.Metal)
		local cf = CFrame.new(x, 50, 9) * CFrame.Angles(0, 0, 0.12 * (index - 2))
		b.EggR(cf * CFrame.new(0, 0, 0), 20, 88, 3, color, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(0, 0, 1.6), 16, 70, 0.4, darken(color, 0.4), M.SmoothPlastic)
		for _, dy in ipairs({ -30, 30 }) do
			b.BoxR(cf * CFrame.new(0, dy, 4), 12, 3, 3, rgb(200, 200, 210), M.Metal)
			for _, dx in ipairs({ -8, 8 }) do
				local p = (cf * CFrame.new(dx, dy, 6)).Position
				b.CylX(p.X, p.Y, p.Z, 6, 4, rgb(255, 240, 200), M.SmoothPlastic)
			end
		end
	end
	b.Footprint(96, 14, 100)
end

R.Kite = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 110, 150)), vivid(b, 2, rgb(255, 210, 80)), vivid(b, 3, rgb(120, 200, 255)), vivid(b, 4, rgb(140, 220, 140)) }
	-- losange en 4 quartiers colorés + baguettes + queue à nœuds
	local cy, r = 62, 30
	local quarters = { { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }
	for index, q in ipairs(quarters) do
		b.BoxR(CFrame.new(q[1] * r / 4, cy + q[2] * r / 4, 3) * CFrame.Angles(0, 0, math.pi / 4), r * 0.707, r * 0.707, 1.5, colors[index], M.Fabric)
	end
	b.Tube(0, cy + r, 4.2, 0, cy - r, 4.2, 1.5, rgb(160, 110, 70), M.Wood)
	b.Tube(-r, cy, 4.2, r, cy, 4.2, 1.5, rgb(160, 110, 70), M.Wood)
	local points = { { 0, cy - r, 3.5 }, { 8, 20, 3.5 }, { -6, 10, 3.5 }, { 6, 2, 3.5 } }
	House3DKit.Path(b, points, 1, WHITE, M.SmoothPlastic)
	for index = 2, 4 do
		local p = points[index]
		b.BoxR(CFrame.new(p[1], p[2], 4) * CFrame.Angles(0, 0, 0.5), 9, 4, 1, colors[index], M.Fabric)
		b.BoxR(CFrame.new(p[1], p[2], 4) * CFrame.Angles(0, 0, -0.5), 9, 4, 1, colors[index], M.Fabric)
	end
	b.Footprint(64, 8, 100)
end

----------------------------------------------------------------------
-- DÉCO AU SOL
----------------------------------------------------------------------

R.GiantGem = function(b, _ctx)
	local gem = vivid(b, 1, rgb(140, 200, 255))
	b.Cushion(0, 0, 0, 60, 14, 60, vivid(b, 2, rgb(255, 150, 190)), M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(sx * 27, 8, sz * 27, 7, GOLD, M.Fabric)
		end
	end
	-- diamant : pavillon (pointe en bas) + ceinture + couronne, en pentes à facettes
	local girdle = 50
	local function crown(y: number, height: number, width: number, flip: boolean, color: Color3)
		for index = 0, 7 do
			local a = index / 8 * math.pi * 2
			local cf = CFrame.new(math.cos(a) * width / 4, y, math.sin(a) * width / 4) * CFrame.Angles(0, -a - math.pi / 2, 0)
			if flip then
				cf *= CFrame.Angles(0, 0, math.pi)
			end
			local part = b.Part("WedgePart", cf, Vector3.new(width * 0.42, height, width / 2), index % 2 == 0 and color or lighten(color, 0.18), M.Glass, "Facette")
			part.Transparency = 0.12
		end
	end
	crown(34, 30, 56, true, darken(gem, 0.05))
	local band = b.Cyl(0, 49, 0, 58, 4, lighten(gem, 0.25), M.Glass)
	band.Transparency = 0.1
	crown(59, 16, 56, false, gem)
	local top = b.Cyl(0, 66, 0, 28, 2, lighten(gem, 0.4), M.Glass)
	top.Transparency = 0.1
	local core = b.Ball(0, 46, 0, 18, lighten(gem, 0.55), M.Neon)
	b.Light(core, gem, 10, 0.7)
	local _ = girdle
	b.Footprint(62, 62, 70)
end

R.PhotoFrame = function(b, _ctx)
	local frame = vivid(b, 1, rgb(255, 170, 200))
	b.BoxR(CFrame.new(0, 44, 0) * CFrame.Angles(-0.2, 0, 0), 76, 84, 6, frame, M.Wood)
	b.BoxR(CFrame.new(0, 44, 0) * CFrame.Angles(-0.2, 0, 0) * CFrame.new(0, 0, 3.2), 58, 64, 1, rgb(160, 210, 255), M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 44, 0) * CFrame.Angles(-0.2, 0, 0) * CFrame.new(0, -14, 3.8), 58, 22, 1, rgb(140, 214, 140), M.SmoothPlastic)
	b.BoxR(CFrame.new(-8, 44, 0) * CFrame.Angles(-0.2, 0, 0) * CFrame.new(0, 2, 4), 14, 20, 1, rgb(255, 214, 170), M.SmoothPlastic)
	b.BoxR(CFrame.new(10, 44, 0) * CFrame.Angles(-0.2, 0, 0) * CFrame.new(0, 0, 4), 12, 16, 1, rgb(255, 200, 150), M.SmoothPlastic)
	b.Ball(20, 58, 12, 10, rgb(255, 236, 130), M.Neon)
	b.BoxR(CFrame.new(0, 24, -14) * CFrame.Angles(0.5, 0, 0), 10, 48, 3, darken(frame, 0.2), M.Wood)
	b.Footprint(76, 36, 90)
end

R.Mannequin = function(b, _ctx)
	local dress = vivid(b, 1, rgb(255, 140, 190))
	local fabric = rgb(250, 238, 228)
	b.Cyl(0, 0, 0, 36, 4, rgb(120, 90, 70), M.Wood)
	for index = 0, 2 do
		local a = index / 3 * math.pi * 2
		b.Tube(0, 20, 0, math.cos(a) * 16, 1, math.sin(a) * 16, 3, rgb(150, 110, 80), M.Wood)
	end
	b.Cyl(0, 18, 0, 4, 22, rgb(150, 110, 80), M.Wood)
	-- torse (buste) + robe
	b.Egg(0, 80, 0, 30, 30, 20, fabric, M.Fabric)
	b.Cyl(0, 92, 0, 6, 8, rgb(150, 110, 80), M.Wood)
	b.Ball(0, 101, 0, 8, GOLD, M.Metal)
	b.Egg(0, 76, 3, 30, 24, 18, dress, M.Fabric)
	b.Egg(0, 64, 0, 22, 10, 16, dress, M.Fabric)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.Part("WedgePart", CFrame.new(math.cos(a) * 12, 48, math.sin(a) * 10) * CFrame.Angles(0, -a - math.pi / 2, 0), Vector3.new(15, 30, 10), index % 2 == 0 and dress or lighten(dress, 0.15), M.Fabric, "Jupe")
	end
	b.Egg(0, 66, 10, 24, 5, 3, lighten(dress, 0.4), M.Fabric)
	b.Ball(-6, 67, 12, 5, rgb(255, 250, 250), M.SmoothPlastic)
	-- mètre ruban
	b.Tube(-15, 88, 4, -12, 50, 11, 1.2, rgb(255, 214, 90), M.Fabric)
	b.Footprint(40, 36, 104)
end

R.Harp = function(b, _ctx)
	local gold = b.Map(GOLD)
	b.Round(0, 0, 0, 40, 8, 26, 5, darken(gold, 0.15), M.Metal)
	b.Tube(-14, 8, 0, -16, 92, 0, 7, gold, M.Metal)
	b.Ball(-16, 94, 0, 12, gold, M.Metal)
	local points = { { -16, 90, 0 }, { 0, 92, 0 }, { 14, 84, 0 }, { 22, 70, 0 }, { 26, 50, 0 } }
	House3DKit.Path(b, points, 6, gold, M.Metal)
	b.Tube(26, 50, 0, 18, 8, 0, 9, darken(gold, 0.1), M.Metal)
	b.Egg(20, 30, 0, 14, 40, 16, lighten(gold, 0.1), M.Metal)
	for index = 0, 8 do
		local t = (index + 1) / 10
		local x = -14 + t * 36
		local topY = 90 - t * 36
		b.Tube(x, 12 + t * 8, 0, x, topY, 0, 0.7, rgb(255, 250, 235), M.SmoothPlastic)
	end
	b.Footprint(56, 30, 100)
end

R.SwanStatue = function(b, _ctx)
	local white = rgb(252, 252, 255)
	b.Cyl(0, 0, 0, 70, 10, rgb(230, 226, 240), M.Marble)
	b.Cyl(0, 10, 0, 62, 4, rgb(245, 240, 250), M.Marble)
	b.Egg(-4, 34, 0, 56, 30, 38, white, M.Marble)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(-8, 42, side * 14) * CFrame.Angles(side * 0.3, 0, 0.3), 44, 20, 10, white, M.Marble)
	end
	b.EggR(CFrame.new(-30, 44, 0) * CFrame.Angles(0, 0, -0.6), 18, 10, 12, white, M.Marble)
	House3DKit.Path(b, { { 16, 38, 0 }, { 22, 56, 0 }, { 16, 72, 0 }, { 18, 84, 0 } }, 8, white, M.Marble)
	b.Ball(22, 86, 0, 13, white, M.Marble)
	b.EggR(CFrame.new(31, 85, 0) * CFrame.Angles(0, 0, -0.3), 12, 5, 5, rgb(255, 160, 70), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(24, 88, side * 5, 3, INK, M.SmoothPlastic)
	end
	b.Footprint(76, 70, 92)
end

R.CrownCushion = function(b, _ctx)
	local velvet = vivid(b, 1, rgb(200, 60, 90))
	local gold = b.Map(GOLD)
	b.Cushion(0, 0, 0, 84, 30, 70, velvet, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(sx * 38, 12, sz * 30, 9, gold, M.Fabric)
		end
	end
	b.Cyl(0, 26, 0, 44, 12, gold, M.Metal)
	for index = 0, 4 do
		local a = index / 5 * math.pi * 2
		b.Part("WedgePart", CFrame.new(math.cos(a) * 19, 46, math.sin(a) * 19) * CFrame.Angles(0, -a + math.pi / 2, 0), Vector3.new(14, 16, 4), gold, M.Metal, "Pointe")
		b.Ball(math.cos(a) * 20, 54, math.sin(a) * 20, 5, WHITE, M.SmoothPlastic)
	end
	b.Ball(0, 34, 22, 8, rgb(90, 160, 255), M.Glass)
	b.Egg(0, 26, 0, 40, 6, 40, velvet, M.Fabric)
	b.Footprint(84, 70, 60)
end

-- Coussins
local function pillow(shape: string)
	return function(b: Builder, _ctx: any)
		local color = vivid(b, 1, shape == "Moon" and rgb(255, 220, 110) or rgb(255, 120, 160))
		if shape == "Heart" then
			local before = #b.Parts
			House3DKit.Heart(b, 0, 48, -14, 90, 28, color, M.Fabric)
			local _ = before
			b.Egg(-18, 60, 15, 20, 12, 6, lighten(color, 0.4), M.Fabric)
			b.Footprint(90, 30, 96)
		else
			-- croissant de lune dodu
			local points = {}
			for index = 0, 8 do
				local a = math.pi * (0.2 + index / 8 * 1.3)
				table.insert(points, { math.cos(a) * 34, 50 + math.sin(a) * 34, 0 })
			end
			for index = 1, #points - 1 do
				local p, q = points[index], points[index + 1]
				local t = math.sin((index - 0.5) / (#points - 1) * math.pi)
				b.Tube(p[1], p[2], p[3], q[1], q[2], q[3], 10 + t * 18, color, M.Fabric)
				b.Ball(q[1], q[2], q[3], 10 + t * 18, color, M.Fabric)
			end
			b.Ball(-24, 56, 12, 5, INK, M.SmoothPlastic)
			b.Egg(-22, 44, 12, 7, 4, 3, rgb(255, 160, 180), M.SmoothPlastic)
			b.Footprint(80, 30, 96)
		end
	end
end
R.HeartPillow = pillow("Heart")
R.MoonPillow = pillow("Moon")

----------------------------------------------------------------------
-- LUMIÈRES
----------------------------------------------------------------------

R.StarNightLight = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 226, 120))
	b.Cyl(0, 0, 0, 44, 8, rgb(250, 240, 250), M.SmoothPlastic)
	b.Cyl(0, 8, 0, 6, 16, rgb(250, 240, 250), M.SmoothPlastic)
	local before = #b.Parts
	House3DKit.Star(b, 0, 56, -6, 38, 12, color, M.Neon)
	b.Light(b.Parts[before + 1], color, 12, 0.9)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 8, 58, 6.5, 5, INK, M.SmoothPlastic)
	end
	b.Egg(0, 50, 6.5, 8, 3, 2, INK, M.SmoothPlastic)
	b.Footprint(76, 44, 96)
end

-- Enseignes néon murales (tubes néon sur un panneau transparent)
local function neon(kind: string)
	return function(b: Builder, _ctx: any)
		local color = vivid(b, 1, kind == "Lightning" and rgb(255, 230, 80) or rgb(255, 90, 180))
		local board = b.Box(0, 10, 0.5, 90, 80, 1.5, rgb(230, 236, 250), M.Glass)
		board.Transparency = 0.75
		for _, x in ipairs({ -40, 40 }) do
			for _, y in ipairs({ 14, 86 }) do
				b.CylZ(x, y, 2, 3, 3, rgb(200, 200, 210), M.Metal)
			end
		end
		local parts
		if kind == "Heart" then
			parts = House3DKit.Path(b, House3DKit.HeartPoints(0, 50, 4, 70, 20), 4, color, M.Neon, true)
		elseif kind == "Star" then
			parts = House3DKit.Path(b, House3DKit.StarPoints(0, 49, 4, 38, 0.45), 4, color, M.Neon, true)
		elseif kind == "Lightning" then
			parts = House3DKit.Path(b, { { 10, 88, 4 }, { -14, 48, 4 }, { 4, 50, 4 }, { -10, 12, 4 }, { 18, 56, 4 }, { 0, 54, 4 }, { 10, 88, 4 } }, 4, color, M.Neon, true)
		else
			-- "GG" : deux G en tubes
			parts = {}
			for _, cx in ipairs({ -20, 20 }) do
				local points = {}
				for index = 0, 10 do
					local a = math.pi * 0.25 + index / 10 * math.pi * 1.5
					table.insert(points, { cx + math.cos(a) * 16, 50 + math.sin(a) * 20, 4 })
				end
				table.insert(points, { cx + 16, 44, 4 })
				table.insert(points, { cx + 4, 44, 4 })
				for _, part in ipairs(House3DKit.Path(b, points, 4, color, M.Neon, true)) do
					table.insert(parts, part)
				end
			end
		end
		b.Light(parts[1], color, 14, 1)
		b.Footprint(90, 6, 100)
	end
end
R.NeonHeart = neon("Heart")
R.NeonStar = neon("Star")
R.LightningNeon = neon("Lightning")
R.NeonGG = neon("GG")

R.SparklerLights = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 150, 200)), vivid(b, 2, rgb(255, 230, 120)), vivid(b, 3, rgb(150, 220, 255)) }
	for column = 0, 6 do
		local x = -42 + column * 14
		local length = 50 + (column % 3) * 14
		b.Tube(x, 96, 2, x, 96 - length, 2, 0.8, rgb(250, 250, 250), M.SmoothPlastic)
		for index = 1, 4 do
			local bulb = b.Ball(x, 96 - length * index / 4, 3, 5, colors[(column + index) % 3 + 1], M.Neon)
			bulb.CastShadow = false
			if column == 3 and index == 2 then
				b.Light(bulb, colors[2], 12, 0.8)
			end
		end
	end
	b.CylX(0, 96, 2, 2, 96, rgb(220, 220, 230), M.Metal)
	b.Footprint(96, 6, 100)
end

R.RainbowProjector = function(b, _ctx)
	local colors = { rgb(255, 110, 120), rgb(255, 180, 90), rgb(255, 236, 110), rgb(130, 220, 140), rgb(110, 180, 255), rgb(180, 140, 255) }
	-- arc-en-ciel lumineux sur le mur
	for index, color in ipairs(colors) do
		local radius = 44 - (index - 1) * 5
		local points = {}
		for step = 0, 7 do
			local a = step / 7 * math.pi
			table.insert(points, { math.cos(a) * radius, 36 + math.sin(a) * radius, 1 + index * 0.2 })
		end
		local parts = House3DKit.Path(b, points, 5, color, M.Neon, true, true)
		for _, part in ipairs(parts) do
			part.Transparency = 0.25
		end
	end
	-- petit projecteur sur son support
	b.Box(0, 14, 4, 30, 4, 20, rgb(250, 246, 250), M.SmoothPlastic)
	b.Round(0, 18, 8, 22, 14, 16, 4, rgb(255, 250, 255), M.SmoothPlastic)
	local lens = b.CylZ(0, 25, 16.5, 10, 2, rgb(255, 250, 220), M.Neon)
	b.Light(lens, rgb(255, 240, 220), 12, 0.8)
	b.Footprint(96, 24, 100)
end

R.UFOLamp = function(b, _ctx)
	local body = vivid(b, 1, rgb(170, 190, 220))
	b.Tube(0, 100, 20, 0, 70, 20, 0.8, INK, M.SmoothPlastic)
	b.Egg(0, 60, 20, 86, 18, 56, body, M.Metal)
	local dome = b.Egg(0, 70, 20, 40, 26, 30, rgb(170, 240, 220), M.Glass)
	dome.Transparency = 0.35
	b.Egg(0, 68, 20, 12, 14, 10, rgb(140, 230, 120), M.SmoothPlastic)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		b.Ball(math.cos(a) * 38, 58, 20 + math.sin(a) * 24, 6, index % 2 == 0 and rgb(255, 230, 120) or rgb(255, 130, 200), M.Neon)
	end
	-- faisceau
	local beam = b.Cyl(0, 20, 20, 40, 38, rgb(200, 255, 230), M.Neon)
	beam.Transparency = 0.75
	beam.CastShadow = false
	b.Light(beam, rgb(200, 255, 230), 14, 0.8)
	b.Footprint(86, 56, 100)
end

-- (v9.8) Lustre à pampilles : rosace, chaîne, fût à nœuds, couronne dorée,
-- bras courbes, bobèches, bougies-ampoules, guirlandes de perles de cristal
-- et pendeloques à facettes (reflets)
R.CrystalChandelier = function(b, _ctx)
	local gold = b.Map(GOLD)
	local crystalColor = rgb(230, 245, 255)
	b.Cyl(0, 97, 20, 16, 3, gold, M.Metal).Reflectance = 0.3
	for index = 0, 3 do
		b.Egg(0, 94 - index * 4, 20, 2.4, 4, 1.4, gold, M.Metal)
	end
	b.Ball(0, 78, 20, 10, gold, M.Metal).Reflectance = 0.3
	b.Cyl(0, 62, 20, 4, 16, gold, M.Metal)
	b.Egg(0, 66, 20, 8, 6, 8, gold, M.Metal).Reflectance = 0.3
	b.Cyl(0, 56, 20, 60, 4, gold, M.Metal).Reflectance = 0.3
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		local x, z = math.cos(a) * 30, 20 + math.sin(a) * 18
		b.Tube(0, 70, 20, x * 0.6, 62, 20 + (z - 20) * 0.6, 1.5, gold, M.Metal)
		b.Tube(x * 0.6, 62, 20 + (z - 20) * 0.6, x, 60, z, 1.5, gold, M.Metal)
		b.Cyl(x, 60, z, 7, 2, gold, M.Metal).Reflectance = 0.3
		b.Cyl(x, 62, z, 3, 10, rgb(255, 250, 240), M.SmoothPlastic)
		local flame = b.Egg(x, 74, z, 3.4, 5, 3.4, rgb(255, 214, 140), M.Neon)
		flame.CastShadow = false
		for drop = 1, 2 do
			local crystal = b.Egg(x, 56 - drop * 6, z, 3.6, 6, 3.6, crystalColor, M.Glass)
			crystal.Transparency = 0.2
			crystal.Reflectance = 0.3
		end
		local prism = b.EggR(CFrame.new(x, 40, z) * CFrame.Angles(0, a, 0), 3, 9, 1.6, crystalColor, M.Glass)
		prism.Transparency = 0.15
		prism.Reflectance = 0.35
		-- guirlande de perles vers le bras suivant
		local a2 = (index + 1) / 8 * math.pi * 2
		local x2, z2 = math.cos(a2) * 30, 20 + math.sin(a2) * 18
		for bead = 1, 3 do
			local t = bead / 4
			local sag = math.sin(t * math.pi) * 5
			local pearl = b.Ball(x + (x2 - x) * t, 55 - sag, z + (z2 - z) * t, 2, crystalColor, M.Glass)
			pearl.Reflectance = 0.3
		end
	end
	local core = b.Egg(0, 44, 20, 14, 22, 14, crystalColor, M.Glass)
	core.Transparency = 0.1
	core.Reflectance = 0.25
	b.Egg(0, 30, 20, 6, 10, 6, crystalColor, M.Glass).Reflectance = 0.3
	b.Light(core, rgb(255, 236, 200), 18, 1)
	b.Footprint(76, 40, 100)
end

R.PocketSun = function(b, _ctx)
	local sun = rgb(255, 210, 80)
	b.Tube(0, 100, 20, 0, 78, 20, 0.8, INK, M.SmoothPlastic)
	local core = b.Ball(0, 50, 20, 44, sun, M.Neon)
	b.Light(core, rgb(255, 220, 140), 20, 1.2)
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		local ray = b.Tube(math.cos(a) * 26, 50 + math.sin(a) * 26, 20, math.cos(a) * 40, 50 + math.sin(a) * 40, 20, 5, rgb(255, 170, 60), M.Neon)
		ray.CastShadow = false
	end
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 8, 54, 41, 5, INK, M.SmoothPlastic)
		b.Egg(side * 14, 46, 40, 7, 4, 2, rgb(255, 130, 130), M.SmoothPlastic)
	end
	b.Footprint(90, 44, 100)
end

R.JellyfishLamp = function(b, _ctx)
	local color = vivid(b, 1, rgb(200, 150, 255))
	b.Cyl(0, 0, 0, 40, 6, rgb(240, 236, 250), M.SmoothPlastic)
	b.Tube(0, 6, 0, 0, 30, 0, 2, rgb(220, 220, 230), M.Metal)
	local bell = b.Egg(0, 76, 0, 54, 36, 54, color, M.Glass)
	bell.Transparency = 0.2
	local inner = b.Egg(0, 72, 0, 34, 20, 34, lighten(color, 0.5), M.Neon)
	b.Light(inner, color, 14, 1)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		local x, z = math.cos(a) * 16, math.sin(a) * 16
		House3DKit.Path(b, { { x, 62, z }, { x * 1.2, 48, z * 1.2 }, { x * 0.8, 36, z * 0.8 }, { x * 1.1, 26, z * 1.1 } }, 2, lighten(color, 0.3), M.Neon, true)
	end
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 8, 78, 26, 4, INK, M.SmoothPlastic)
	end
	b.Footprint(56, 56, 96)
end

R.DinoEggLamp = function(b, _ctx)
	local shell = vivid(b, 1, rgb(160, 230, 170))
	b.Cyl(0, 0, 0, 50, 8, rgb(150, 110, 80), M.Wood)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 20, 10, math.sin(a) * 20) * CFrame.Angles(0, -a, 0.4), 8, 16, 6, rgb(110, 200, 110), M.SmoothPlastic)
	end
	local egg = b.Egg(0, 50, 0, 56, 76, 56, shell, M.SmoothPlastic)
	b.Neon(egg)
	egg.Transparency = 0.1
	b.Light(egg, lighten(shell, 0.3), 12, 0.9)
	for index = 0, 5 do
		local a = index * 1.3
		b.Egg(math.cos(a) * 24, 36 + index * 8, math.sin(a) * 24, 10, 8, 10, darken(shell, 0.2), M.SmoothPlastic)
	end
	b.Footprint(56, 56, 90)
end

R.RocketLavaLamp = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 140, 60))
	local body = rgb(230, 234, 245)
	b.Cyl(0, 0, 0, 44, 14, darken(color, 0.2), M.Metal)
	for index = 0, 2 do
		local a = index / 3 * math.pi * 2
		b.Part("WedgePart", CFrame.new(math.cos(a) * 20, 16, math.sin(a) * 20) * CFrame.Angles(0, -a - math.pi / 2, 0), Vector3.new(3, 22, 12), color, M.SmoothPlastic, "Aileron")
	end
	local glass = b.Cyl(0, 14, 0, 30, 52, lighten(color, 0.6), M.Glass)
	glass.Transparency = 0.3
	for index = 1, 3 do
		b.Ball((index % 2) * 6 - 3, 20 + index * 13, 0, 13 - index * 2, color, M.Neon)
	end
	b.Light(glass, color, 12, 0.9)
	b.Cyl(0, 66, 0, 30, 8, body, M.Metal)
	for index = 0, 3 do
		b.Cyl(0, 74 + index * 5, 0, 26 - index * 6.5, 5.2, index == 3 and color or body, M.Metal)
	end
	b.Footprint(48, 48, 96)
end

----------------------------------------------------------------------
-- PORTES (contre le mur du fond)
----------------------------------------------------------------------

-- Porte : cadre (moulures), battant à panneaux, poignée, seuil
-- (v9.8) chambranle mouluré (baguette intérieure en retrait), corniche en
-- tête, plinthes de pied, paumelles en laiton, seuil biseauté
local function doorBase(b: Builder, ctx: any, panel: Color3, material: Enum.Material?, width: number?, height: number?): (number, number)
	local w = width or 66
	local h = height or 94
	local frame = ctx.Trim
	b.Box(-w / 2 - 3, 0, 0, 6, h + 2, 7, frame, M.Wood)
	b.Box(w / 2 + 3, 0, 0, 6, h + 2, 7, frame, M.Wood)
	b.Box(0, h + 2, 0, w + 14, 6, 8, frame, M.Wood)
	b.Box(0, h + 7.6, 0.6, w + 17, 1.8, 9.2, lighten(frame, 0.08), M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * (w / 2 - 0.6), 0, 1.6, 1.2, h + 2, 2.2, darken(frame, 0.08), M.Wood)
		b.Box(side * (w / 2 + 3), 0, 0.6, 7.4, 10, 8.2, darken(frame, 0.06), M.Wood)
	end
	b.Box(0, 0, -1, w, h + 2, 3, panel, material or M.Wood)
	for _, y in ipairs({ h * 0.12, h * 0.5, h * 0.86 }) do
		local hinge = b.Box(-w / 2 + 0.6, y, 1, 1.6, 7, 1.6, rgb(214, 172, 92), M.Metal)
		hinge.Reflectance = 0.25
	end
	House3DKit.Bevel(b, 0, 0, 4, w + 4, 1.2, 8, 0.5, darken(panel, 0.25), M.Wood)
	return w, h
end

R.WoodenDoor = function(b, ctx)
	local wood = H.woodOf(b, rgb(190, 130, 90))
	local w, h = doorBase(b, ctx, wood, M.WoodPlanks)
	for _, y in ipairs({ 10, 52 }) do
		House3DKit.Frame(b, 0, y, 0.8, w - 16, 36, 3, 1.5, darken(wood, 0.15), M.Wood)
	end
	b.Ball(w / 2 - 9, h * 0.5, 2.5, 6, GOLD, M.Metal)
	b.Box(w / 2 - 9, h * 0.5 - 8, 1, 4, 16, 1, darken(GOLD, 0.1), M.Metal)
	b.Footprint(w + 12, 8, h + 8)
end

R.GardenDoor = function(b, ctx)
	local paint = vivid(b, 1, rgb(140, 200, 140))
	local w, h = doorBase(b, ctx, paint, M.Wood)
	-- vitre à croisillons en haut, panneaux en bas
	local glass = b.Box(0, 50, 0.5, w - 16, 38, 1, rgb(190, 230, 255), M.Glass)
	glass.Transparency = 0.3
	House3DKit.Frame(b, 0, 48, 1.2, w - 12, 42, 4, 2, lighten(paint, 0.2), M.Wood)
	b.Box(0, 50, 1.4, 3, 38, 1.5, lighten(paint, 0.2), M.Wood)
	b.Box(0, 67, 1.4, w - 16, 3, 1.5, lighten(paint, 0.2), M.Wood)
	House3DKit.Frame(b, 0, 10, 0.8, w - 16, 30, 3, 1.5, darken(paint, 0.15), M.Wood)
	b.Ball(w / 2 - 9, 46, 2.5, 6, GOLD, M.Metal)
	-- couronne de feuilles
	local points = {}
	for index = 0, 10 do
		local a = index / 10 * math.pi * 2
		table.insert(points, { math.cos(a) * 9, 76 + math.sin(a) * 9, 4 })
	end
	for _, p in ipairs(points) do
		b.Ball(p[1], p[2], p[3], 6, LEAF, M.SmoothPlastic)
	end
	b.Ball(0, 67, 5, 5, rgb(255, 110, 140), M.SmoothPlastic)
	b.Footprint(w + 12, 8, h + 8)
end

R.HeartDoor = function(b, ctx)
	local paint = vivid(b, 1, rgb(255, 140, 180))
	local w, h = doorBase(b, ctx, paint, M.Wood)
	House3DKit.Heart(b, 0, 64, 0.5, 34, 2, lighten(paint, 0.35), M.SmoothPlastic)
	House3DKit.Heart(b, 0, 64.5, 2, 24, 2, rgb(255, 80, 140), M.SmoothPlastic)
	House3DKit.Frame(b, 0, 10, 0.8, w - 18, 34, 3, 1.5, darken(paint, 0.12), M.Wood)
	b.Ball(w / 2 - 9, 46, 2.5, 6, GOLD, M.Metal)
	b.Footprint(w + 12, 8, h + 8)
end

R.CandyDoor = function(b, ctx)
	local a = vivid(b, 1, rgb(255, 150, 200))
	local c = rgb(255, 250, 250)
	local w, h = doorBase(b, ctx, a, M.SmoothPlastic)
	-- rayures de sucre d'orge en biais
	for index = 0, 6 do
		b.BoxR(CFrame.new(-w / 2 + 6 + index * 10, 48, 1), 4, 94, 1, c)
	end
	-- sucettes de chaque côté
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * (w / 2 + 12), 0, 4, side * (w / 2 + 12), 60, 4, 2.5, WHITE, M.SmoothPlastic)
		b.CylZ(side * (w / 2 + 12), 68, 4, 20, 4, vivid(b, 2, rgb(120, 200, 255)), M.SmoothPlastic)
		b.CylZ(side * (w / 2 + 12), 68, 6.5, 12, 1, c, M.SmoothPlastic)
	end
	b.Ball(w / 2 - 9, 46, 3, 8, rgb(255, 80, 120), M.SmoothPlastic)
	b.Footprint(w + 36, 10, h + 8)
end

R.ShojiDoor = function(b, ctx)
	local wood = H.woodOf(b, rgb(170, 120, 80))
	local w, h = doorBase(b, ctx, rgb(255, 250, 236), M.Fabric)
	for column = 0, 3 do
		b.Box(-w / 2 + 2 + column * (w - 4) / 3, 0, 1, 3, h, 2, wood, M.Wood)
	end
	for row = 0, 5 do
		b.Box(0, 2 + row * (h - 4) / 5, 1, w, 3, 2, wood, M.Wood)
	end
	b.Box(w / 2 - 10, 44, 2, 6, 10, 1, darken(wood, 0.2), M.Wood)
	b.Footprint(w + 12, 8, h + 8)
end

-- Porte secrète : une vraie bibliothèque (livres en rangées)
R.SecretDoor = function(b, ctx)
	local wood = H.woodOf(b, rgb(150, 100, 70))
	local w, h = 70, 96
	local frame = ctx.Trim
	b.Box(-w / 2 - 3, 0, 0, 6, h, 10, frame, M.Wood)
	b.Box(w / 2 + 3, 0, 0, 6, h, 10, frame, M.Wood)
	b.Box(0, h, 0, w + 14, 6, 10, frame, M.Wood)
	b.Box(0, 0, -2, w, h, 4, darken(wood, 0.25), M.Wood)
	local colors = { vivid(b, 1, rgb(220, 90, 100)), vivid(b, 2, rgb(90, 140, 220)), vivid(b, 3, rgb(120, 190, 120)), vivid(b, 4, rgb(240, 200, 90)) }
	for row = 0, 3 do
		local y = 4 + row * 23
		b.Box(0, y, 1, w, 3, 8, wood, M.Wood)
		local x = -w / 2 + 3
		local index = row
		while x < w / 2 - 6 do
			local bw = 4 + (index * 7) % 4
			local bh = 14 + (index * 5) % 5
			if index % 9 == 4 then
				b.BoxR(CFrame.new(x + 4, y + 3 + bh / 2 - 1, 1.5) * CFrame.Angles(0, 0, -0.35), bw, bh, 6, colors[index % 4 + 1], M.SmoothPlastic)
				x += 6
			else
				b.Box(x + bw / 2, y + 3, 1.5, bw, bh, 6, colors[index % 4 + 1], M.SmoothPlastic)
			end
			x += bw + 0.6
			index += 1
		end
	end
	-- le livre levier (doré)
	b.BoxR(CFrame.new(w / 2 - 10, 60, 4) * CFrame.Angles(0, 0, 0.4), 4, 16, 6, GOLD, M.Metal)
	b.Footprint(w + 12, 10, h + 6)
end

R.Elevator = function(b, ctx)
	local metal = rgb(214, 218, 230)
	local frame = vivid(b, 1, rgb(245, 190, 60))
	b.Box(0, 0, -1, 84, 100, 3, frame, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 16.5, 2, 0.8, 32, 80, 1.5, metal, M.DiamondPlate)
		b.Box(side * 16.5, 2, 1.6, 30, 1, 1, darken(metal, 0.2), M.Metal)
	end
	b.Box(0, 2, 1, 1, 80, 2, rgb(80, 80, 100), M.Metal)
	b.Box(0, 86, 1, 30, 10, 1.5, rgb(40, 40, 60))
	local arrow = b.Box(-6, 88, 2, 5, 6, 1, rgb(255, 180, 60), M.Neon)
	b.Light(arrow, rgb(255, 180, 60), 6, 0.5)
	b.Box(6, 89, 2, 8, 4, 1, rgb(120, 255, 160), M.Neon)
	b.Box(46, 40, 1, 6, 16, 2, rgb(60, 60, 80), M.Metal)
	for _, y in ipairs({ 44, 50 }) do
		b.CylZ(46, y, 2.5, 3.5, 1, rgb(255, 214, 120), M.Neon)
	end
	b.Box(0, 0, 4, 84, 1, 8, darken(metal, 0.3), M.Metal)
	local _ = ctx
	b.Footprint(96, 8, 100)
end

R.MouseHole = function(b, _ctx)
	-- petit trou arrondi au pied du mur (tunnel sombre)
	local frame = rgb(150, 110, 90)
	b.Box(0, 0, -0.5, 60, 34, 1, rgb(30, 24, 30))
	b.CylZ(0, 34, -0.5, 60, 1, rgb(30, 24, 30))
	local points = {}
	for index = 0, 12 do
		local a = index / 12 * math.pi
		table.insert(points, { math.cos(a) * 32, 34 + math.sin(a) * 32, 1 })
	end
	table.insert(points, 1, { 32, 0, 1 })
	table.insert(points, { -32, 0, 1 })
	House3DKit.Path(b, points, 6, frame, M.Wood)
	b.Box(0, 0, 6, 70, 2, 12, frame, M.Wood)
	-- petite porte en bois entrouverte + paillasson
	b.Box(-10, 2, 1, 24, 40, 2, rgb(200, 140, 90), M.WoodPlanks)
	b.Ball(-2, 22, 3, 4, GOLD, M.Metal)
	b.Box(12, 0, 12, 26, 1.5, 10, rgb(255, 150, 180), M.Fabric)
	b.Footprint(76, 16, 70)
end

R.DreamPortal = function(b, _ctx)
	local a = vivid(b, 1, rgb(190, 130, 255))
	local c = vivid(b, 2, rgb(120, 220, 255))
	b.Cyl(0, 0, 4, 90, 8, rgb(80, 70, 110), M.Slate)
	-- anneau de pierre + tourbillon lumineux
	local points = {}
	for index = 0, 18 do
		local t = index / 18 * math.pi * 2
		table.insert(points, { math.cos(t) * 38, 52 + math.sin(t) * 44, 4 })
	end
	House3DKit.Path(b, points, 10, rgb(110, 96, 150), M.Slate)
	for ring = 0, 3 do
		local disc = b.EggR(CFrame.new(0, 52, 3 + ring * 0.6), 66 - ring * 14, 78 - ring * 16, 1, ring % 2 == 0 and a or c, M.Neon)
		disc.Transparency = 0.15
		disc.CastShadow = false
	end
	b.Light(b.Parts[#b.Parts], a, 16, 1)
	for index = 0, 4 do
		local t = index / 5 * math.pi * 2
		b.Ball(math.cos(t) * 38, 52 + math.sin(t) * 44, 9, 7, index % 2 == 0 and BUTTER or c, M.Neon)
	end
	b.Footprint(96, 12, 100)
end

R.DutchDoor = function(b, ctx)
	local paint = vivid(b, 1, rgb(160, 220, 210))
	local w, h = doorBase(b, ctx, paint, M.Wood)
	-- deux battants : le haut entrouvert
	b.Box(0, 48, 0.5, w, 2, 3, darken(paint, 0.25), M.Wood)
	b.BoxR(CFrame.new(-w / 2 + 2, 72, 12) * CFrame.Angles(0, -1.1, 0) * CFrame.new(w / 2 - 2, 0, 0), w, 44, 3, lighten(paint, 0.1), M.Wood)
	b.Box(0, 50, -0.8, w - 2, 44, 1, rgb(250, 236, 220), M.SmoothPlastic)
	House3DKit.Frame(b, 0, 8, 0.8, w - 16, 32, 3, 1.5, darken(paint, 0.15), M.Wood)
	b.Box(0, 46, 2, w - 6, 3, 8, lighten(paint, 0.25), M.Wood)
	b.Ball(w / 2 - 9, 38, 2.5, 6, GOLD, M.Metal)
	b.Egg(-10, 49, 5, 10, 6, 8, rgb(255, 170, 200), M.SmoothPlastic) -- pot de fleurs sur le rebord
	b.Footprint(w + 12, 20, h + 8)
end

R.CastleGate = function(b, _ctx)
	local stone = rgb(200, 196, 214)
	local wood = rgb(150, 100, 70)
	for _, side in ipairs({ -1, 1 }) do
		b.Box(side * 40, 0, 0, 20, 90, 14, stone, M.Brick)
		for index = 0, 1 do
			b.Box(side * 40 + (index - 0.5) * 10, 90, 0, 6, 8, 14, stone, M.Brick)
		end
		b.Part("WedgePart", CFrame.new(side * 40, 104, 0), Vector3.new(22, 12, 16), vivid(b, 1, rgb(255, 120, 160)), M.SmoothPlastic, "Toit")
	end
	b.Box(0, 70, 0, 60, 22, 12, stone, M.Brick)
	-- porte en arc (planches) + herse
	b.Box(0, 0, -1, 60, 50, 3, wood, M.WoodPlanks)
	b.CylZ(0, 50, -1, 60, 3, wood, M.WoodPlanks)
	for index = 0, 4 do
		b.Box(-24 + index * 12, 0, 1.5, 2.5, 60, 2, rgb(90, 90, 100), M.Metal)
	end
	for index = 0, 3 do
		b.Box(0, 8 + index * 13, 1.8, 58, 2, 2, rgb(90, 90, 100), M.Metal)
	end
	b.Box(-8, 80, 7, 16, 8, 1, vivid(b, 2, rgb(120, 170, 255)), M.Fabric)
	b.Footprint(100, 16, 100)
end

----------------------------------------------------------------------
-- FENÊTRES à formes spéciales (les autres : House3DRecipes.windowRecipe)
----------------------------------------------------------------------

R.PortholeWindow = function(b, _ctx)
	local brass = b.Map(GOLD)
	b.Art(0, 16, 0.3, 64, 64, 1.25)
	local glass = b.CylZ(0, 48, 2.5, 64, 0.6, GLASS, M.Glass)
	glass.Transparency = 0.75
	local points = {}
	for index = 0, 12 do
		local a = index / 12 * math.pi * 2
		table.insert(points, { math.cos(a) * 34, 48 + math.sin(a) * 34, 3 })
	end
	House3DKit.Path(b, points, 8, brass, M.Metal)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		b.Ball(math.cos(a) * 34, 48 + math.sin(a) * 34, 7, 4, darken(brass, 0.2), M.Metal)
	end
	b.Footprint(80, 10, 90)
end

R.ArchWindow = function(b, ctx)
	local frame = ctx.Trim
	b.Art(0, 8, 0.3, 70, 80, 1.15)
	local glass = b.Box(0, 8, 2.5, 70, 50, 0.6, GLASS, M.Glass)
	glass.Transparency = 0.75
	local top = b.CylZ(0, 58, 2.5, 70, 0.6, GLASS, M.Glass)
	top.Transparency = 0.75
	local points = { { 36, 6, 3 } }
	for index = 0, 12 do
		local a = index / 12 * math.pi
		table.insert(points, { math.cos(a) * 36, 58 + math.sin(a) * 36, 3 })
	end
	table.insert(points, { -36, 6, 3 })
	House3DKit.Path(b, points, 6, frame, M.Wood)
	b.Box(0, 8, 3, 3, 84, 4, frame, M.Wood)
	b.Box(0, 44, 3, 70, 3, 4, frame, M.Wood)
	b.Box(0, 2, 7, 86, 5, 14, frame, M.Wood)
	b.Footprint(86, 14, 100)
end

R.StainedGlass = function(b, ctx)
	local frame = ctx.Trim
	local colors = { rgb(255, 110, 140), rgb(255, 200, 90), rgb(120, 200, 255), rgb(150, 220, 130), rgb(190, 140, 255), rgb(255, 160, 200) }
	b.Box(0, 8, 0.4, 70, 58, 1, rgb(255, 250, 240), M.SmoothPlastic)
	for row = 0, 3 do
		for column = 0, 3 do
			local pane = b.Box(-26.25 + column * 17.5, 8 + row * 14.5, 1.5, 17, 14, 1, colors[(row + column * 2) % #colors + 1], M.Glass)
			pane.Transparency = 0.2
		end
	end
	local rose = b.CylZ(0, 66, 1.5, 70, 1, colors[5], M.Glass)
	rose.Transparency = 0.2
	for index = 0, 5 do
		local a = index / 6 * math.pi
		b.Tube(0, 66, 2.4, math.cos(a) * 34, 66 + math.sin(a) * 34, 2.4, 2, rgb(70, 60, 80), M.Metal)
	end
	b.CylZ(0, 66, 2.6, 14, 1, colors[2], M.Neon)
	local points = { { 36, 6, 3 } }
	for index = 0, 12 do
		local a = index / 12 * math.pi
		table.insert(points, { math.cos(a) * 36, 66 + math.sin(a) * 36, 3 })
	end
	table.insert(points, { -36, 6, 3 })
	House3DKit.Path(b, points, 5, frame, M.Wood)
	for column = 1, 3 do
		b.Box(-35 + column * 17.5, 8, 2.6, 1.5, 58, 1.5, rgb(70, 60, 80), M.Metal)
	end
	b.Box(0, 2, 7, 86, 5, 14, frame, M.Wood)
	b.Footprint(86, 14, 100)
end

----------------------------------------------------------------------
-- PLANTES (fleurs, suspensions)
----------------------------------------------------------------------

local function potColors(b: Builder): (Color3, Color3)
	local potColor = House3DKit.Pick(b.Pal, function(h, s, v)
		return not (h > 0.2 and h < 0.45) and s > 0.12 and v > 0.4
	end, b.Map(rgb(255, 170, 150)))
	local green = House3DKit.Pick(b.Pal, function(h, s, v)
		return h > 0.2 and h < 0.45 and s > 0.2 and v > 0.3
	end, b.Map(LEAF))
	return potColor, green
end

-- Pot arrondi (+ terre) ; renvoie le haut de la terre
local function roundPot(b: Builder, diameter: number, height: number, color: Color3): number
	-- (v9.8) soucoupe, pot galbé à reflet de céramique, lèvre roulée, terreau
	-- et petits cailloux
	b.Cyl(0, 0, 0, diameter * 0.9, height * 0.06, darken(color, 0.25), M.SmoothPlastic)
	b.Cyl(0, height * 0.06, 0, diameter * 0.74, height * 0.12, darken(color, 0.15), M.SmoothPlastic)
	local body = b.Egg(0, height * 0.5, 0, diameter * 0.96, height * 0.9, diameter * 0.96, color, M.SmoothPlastic)
	body.Reflectance = 0.05
	b.Cyl(0, height * 0.72, 0, diameter, height * 0.2, lighten(color, 0.12), M.SmoothPlastic)
	b.Cyl(0, height * 0.9, 0, diameter + 1, height * 0.04, lighten(color, 0.2), M.SmoothPlastic)
	b.Cyl(0, height * 0.86, 0, diameter * 0.86, height * 0.08, rgb(110, 80, 66), M.Ground)
	for index = 1, 3 do
		local a = index * 2.1
		b.Ball(math.cos(a) * diameter * 0.25, height * 0.95, math.sin(a) * diameter * 0.22, diameter * 0.07, rgb(214, 204, 196), M.Slate)
	end
	return height * 0.94
end

-- Feuille (ovale plat incliné) au bout d'une tige
local function leaf(b: Builder, x: number, y: number, z: number, length: number, yaw: number, pitch: number, color: Color3)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, length / 2)
	b.EggR(cf, length * 0.45, length * 0.08, length, color, M.SmoothPlastic)
end

-- Fleurs en pot : `kind` = forme de la fleur
local function flowerPot(kind: string)
	return function(b: Builder, _ctx: any)
		local potColor, green = potColors(b)
		local default = kind == "Rose" and rgb(235, 50, 80) or kind == "Hibiscus" and rgb(255, 80, 110) or kind == "Lavender" and rgb(170, 130, 230) or rgb(255, 110, 150)
		local flower = House3DKit.Pick(b.Pal, function(h, s, v)
			return not (h > 0.18 and h < 0.48) and s > 0.45 and v > 0.45
		end, b.Map(default))
		if House3DKit.Dist(flower, potColor) < 0.08 then
			flower = lighten(flower, 0.3)
		end
		local soil = roundPot(b, 48, 38, potColor)
		local stems: { { number } } = kind == "Rose" and { { 0, 88, 2 } }
			or kind == "Hibiscus" and { { 0, 80, 4 }, { -14, 66, -4 } }
			or kind == "Lavender" and { { -10, 84, 0 }, { 0, 92, 4 }, { 10, 86, -2 }, { -4, 80, -8 }, { 6, 78, 10 } }
			or { { -12, 80, 2 }, { 0, 90, -2 }, { 12, 78, 4 }, { 4, 74, 12 } }
		-- (v9.8) rosette de feuilles nervurées au pied des tiges
		for index = 1, 6 do
			local a = index * 2.4
			House3DKit.Leaf(b, math.cos(a) * 3, soil + 1, math.sin(a) * 3, 15, 6, math.atan2(math.cos(a), math.sin(a)), -0.45 - (index % 2) * 0.2,
				House3DKit.Vary(green, index, 0.1), darken(green, 0.3))
		end
		for index, top in ipairs(stems) do
			b.Tube(top[1] * 0.3, soil, top[3] * 0.3, top[1], top[2] - 4, top[3], 2.5, darken(green, 0.15), M.SmoothPlastic)
			leaf(b, top[1] * 0.6, soil + 14 + index * 3, top[3] * 0.6, 16, index * 1.9, 0.9, green)
			House3DKit.Leaf(b, top[1] * 0.75, soil + 24 + index * 2, top[3] * 0.75, 12, 5, index * 1.9 + math.pi, -0.2, lighten(green, 0.08), darken(green, 0.3))
			local x, y, z = top[1], top[2], top[3]
			if kind == "Tulip" then
				for petal = 0, 2 do
					local a = petal / 3 * math.pi * 2
					b.EggR(CFrame.new(x + math.cos(a) * 2.5, y, z + math.sin(a) * 2.5) * CFrame.Angles(math.sin(a) * 0.25, 0, -math.cos(a) * 0.25), 8, 16, 8, index % 2 == 0 and flower or lighten(flower, 0.15), M.SmoothPlastic)
				end
			elseif kind == "Daisy" then
				for petal = 0, 7 do
					local a = petal / 8 * math.pi * 2
					b.EggR(CFrame.new(x + math.cos(a) * 6, y, z + math.sin(a) * 6) * CFrame.Angles(0, -a, 0), 10, 2, 4, WHITE, M.SmoothPlastic)
				end
				b.Egg(x, y + 1, z, 7, 4, 7, rgb(255, 210, 60), M.SmoothPlastic)
			elseif kind == "Rose" then
				b.Egg(x, y, z, 20, 18, 20, flower, M.SmoothPlastic)
				for petal = 0, 4 do
					local a = petal / 5 * math.pi * 2
					b.EggR(CFrame.new(x + math.cos(a) * 8, y - 3, z + math.sin(a) * 8) * CFrame.Angles(0, -a, 0.5), 8, 12, 12, darken(flower, 0.1), M.SmoothPlastic)
				end
				b.Egg(x, y + 7, z, 9, 5, 9, lighten(flower, 0.1), M.SmoothPlastic)
			elseif kind == "Hibiscus" then
				for petal = 0, 4 do
					local a = petal / 5 * math.pi * 2
					b.EggR(CFrame.new(x + math.cos(a) * 9, y, z + math.sin(a) * 9) * CFrame.Angles(0, -a, 0.3), 18, 3, 14, flower, M.SmoothPlastic)
				end
				b.Tube(x, y, z, x + 3, y + 12, z + 3, 1.5, rgb(255, 220, 90), M.SmoothPlastic)
				b.Ball(x + 3, y + 12, z + 3, 3, rgb(255, 220, 90), M.SmoothPlastic)
			elseif kind == "Lavender" then
				for bud = 0, 5 do
					b.Egg(x, y - 16 + bud * 3.5, z, 5, 5, 5, bud % 2 == 0 and rgb(170, 130, 230) or rgb(150, 110, 220), M.SmoothPlastic)
				end
			elseif kind == "Clover" then
				for petal = 0, 3 do
					local a = petal / 4 * math.pi * 2 + index
					b.EggR(CFrame.new(x + math.cos(a) * 5, y, z + math.sin(a) * 5) * CFrame.Angles(0, -a, 0), 10, 2.5, 9, green, M.SmoothPlastic)
				end
			end
		end
		if kind == "Clover" then
			b.Ball(4, 76, 12, 6, rgb(255, 214, 90), M.SmoothPlastic)
		end
		b.Footprint(56, 50, 96)
	end
end
R.TulipPot = flowerPot("Tulip")
R.DaisyPot = flowerPot("Daisy")
R.RedRose = flowerPot("Rose")
R.Hibiscus = flowerPot("Hibiscus")
R.LavenderPot = flowerPot("Lavender")
R.LuckyClover = flowerPot("Clover")

-- Bouquet (papier en cône) et vase de fleurs
R.Bouquet = function(b, _ctx)
	local paper = vivid(b, 1, rgb(255, 200, 220))
	local colors = { vivid(b, 2, rgb(255, 110, 150)), vivid(b, 3, rgb(255, 214, 90)), rgb(255, 250, 250), vivid(b, 4, rgb(190, 140, 255)) }
	-- cône de papier (4 pentes) + ruban
	for index = 0, 3 do
		local a = index / 4 * math.pi * 2 + math.pi / 4
		b.Part("WedgePart", CFrame.new(math.cos(a) * 9, 34, math.sin(a) * 9) * CFrame.Angles(0, -a - math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), Vector3.new(26, 60, 18), paper, M.Fabric, "Papier")
	end
	b.Egg(0, 30, 6, 18, 8, 12, vivid(b, 5, rgb(255, 80, 120)), M.Fabric)
	for index = 0, 6 do
		local a = index / 7 * math.pi * 2
		local r = index == 0 and 0 or 13
		b.Egg(math.cos(a) * r, 70 + (index % 2) * 6, math.sin(a) * r * 0.8, 16, 14, 16, colors[index % 4 + 1], M.SmoothPlastic)
		b.Ball(math.cos(a) * r, 76 + (index % 2) * 6, math.sin(a) * r * 0.8 + 4, 5, rgb(255, 220, 90), M.SmoothPlastic)
	end
	for index = 0, 3 do
		local a = index / 4 * math.pi * 2 + 0.4
		leaf(b, math.cos(a) * 12, 62, math.sin(a) * 10, 18, -a + math.pi / 2, -0.5, LEAF)
	end
	b.Footprint(46, 40, 92)
end

R.FlowerVase = function(b, _ctx)
	local vase = vivid(b, 1, rgb(140, 190, 255))
	local colors = { vivid(b, 2, rgb(255, 120, 160)), vivid(b, 3, rgb(255, 214, 90)), rgb(255, 250, 250) }
	b.Cyl(0, 0, 0, 26, 4, darken(vase, 0.15), M.Glass)
	local body = b.Egg(0, 22, 0, 36, 40, 36, vase, M.Glass)
	body.Transparency = 0.25
	b.Cyl(0, 38, 0, 18, 12, vase, M.Glass)
	local water = b.Egg(0, 18, 0, 28, 24, 28, rgb(170, 220, 255), M.Glass)
	water.Transparency = 0.4
	local tops = { { -12, 84, 2 }, { 0, 94, -2 }, { 12, 82, 4 }, { 6, 72, 12 }, { -8, 70, -10 } }
	for index, top in ipairs(tops) do
		b.Tube(0, 20, 0, top[1], top[2] - 6, top[3], 2, rgb(90, 170, 90), M.SmoothPlastic)
		local color = colors[index % 3 + 1]
		for petal = 0, 4 do
			local a = petal / 5 * math.pi * 2
			b.Egg(top[1] + math.cos(a) * 5, top[2], top[3] + math.sin(a) * 5, 8, 6, 8, color, M.SmoothPlastic)
		end
		b.Ball(top[1], top[2] + 1, top[3], 5, rgb(255, 214, 90), M.SmoothPlastic)
	end
	leaf(b, 0, 50, 0, 20, 0.5, -0.6, LEAF)
	leaf(b, 0, 52, 0, 20, 3.6, -0.6, LEAF)
	b.Footprint(44, 40, 100)
end

R.SucculentTrio = function(b, _ctx)
	local potColor = vivid(b, 1, rgb(255, 190, 170))
	local greens = { rgb(130, 200, 150), rgb(150, 190, 120), rgb(110, 180, 170) }
	for index, x in ipairs({ -28, 0, 28 }) do
		local size = index == 2 and 30 or 24
		b.Cyl(x, 0, 0, size, size * 0.8, index == 2 and lighten(potColor, 0.2) or potColor, M.SmoothPlastic)
		b.Cyl(x, size * 0.8, 0, size + 2, 3, lighten(potColor, 0.3), M.SmoothPlastic)
		local base = size * 0.8 + 3
		-- rosette : feuilles épaisses en couronne
		for ring = 0, 1 do
			for leafIndex = 0, 5 do
				local a = leafIndex / 6 * math.pi * 2 + ring * 0.5
				local r = ring == 0 and 8 or 4
				b.EggR(CFrame.new(x + math.cos(a) * r, base + 4 + ring * 4, math.sin(a) * r) * CFrame.Angles(0, -a, 0.6 - ring * 0.3), 10 - ring * 3, 5, 6, ring == 0 and greens[index] or lighten(greens[index], 0.2), M.SmoothPlastic)
			end
		end
		if index == 1 then
			b.Ball(x, base + 12, 0, 5, rgb(255, 150, 180), M.SmoothPlastic)
		end
	end
	b.Footprint(90, 34, 56)
end

R.LotusBowl = function(b, _ctx)
	local bowl = vivid(b, 1, rgb(140, 190, 230))
	local lotus = vivid(b, 2, rgb(255, 170, 200))
	b.Cyl(0, 0, 0, 60, 6, darken(bowl, 0.15), M.SmoothPlastic)
	b.Egg(0, 16, 0, 90, 30, 90, bowl, M.SmoothPlastic)
	local water = b.Cyl(0, 22, 0, 80, 4, rgb(120, 190, 230), M.Glass)
	water.Transparency = 0.2
	for _, p in ipairs({ { -22, 8 }, { 20, -14 }, { 10, 22 } }) do
		b.Cyl(p[1], 25, p[2], 24, 1.5, rgb(100, 180, 100), M.SmoothPlastic)
	end
	for ring = 0, 1 do
		for index = 0, 5 do
			local a = index / 6 * math.pi * 2 + ring * 0.5
			local r = ring == 0 and 8 or 3
			b.EggR(CFrame.new(math.cos(a) * r, 34 + ring * 4, math.sin(a) * r) * CFrame.Angles(0, -a, 0.7 - ring * 0.4), 10, 16, 8, ring == 0 and lotus or lighten(lotus, 0.3), M.SmoothPlastic)
		end
	end
	b.Ball(0, 40, 0, 6, rgb(255, 220, 90), M.SmoothPlastic)
	b.Footprint(90, 90, 50)
end

R.RainbowTree = function(b, _ctx)
	local colors = { rgb(255, 120, 140), rgb(255, 180, 90), rgb(255, 230, 110), rgb(140, 220, 140), rgb(120, 180, 255), rgb(180, 140, 255) }
	local potColor = vivid(b, 1, rgb(255, 200, 220))
	local soil = roundPot(b, 36, 24, potColor)
	b.Tube(0, soil, 0, 0, 56, 0, 6, rgb(150, 100, 70), M.Wood)
	b.Tube(0, 46, 0, -14, 60, 4, 4, rgb(150, 100, 70), M.Wood)
	b.Tube(0, 50, 0, 14, 62, -4, 4, rgb(150, 100, 70), M.Wood)
	local spots = { { 0, 82, 0, 30 }, { -18, 70, 6, 24 }, { 18, 72, -4, 24 }, { -8, 64, -12, 20 }, { 10, 62, 12, 20 }, { 0, 96, 2, 18 } }
	for index, p in ipairs(spots) do
		b.Ball(p[1], p[2], p[3], p[4], colors[index], M.SmoothPlastic)
	end
	for index = 0, 5 do
		local a = index * 1.1
		b.Ball(math.cos(a) * 20, 76 + math.sin(a) * 14, 14, 4, WHITE, M.Neon)
	end
	b.Footprint(60, 50, 100)
end

-- Suspensions murales : pot suspendu à un crochet, feuilles qui retombent
local function hanging(kind: string)
	return function(b: Builder, _ctx: any)
		local potColor, green = potColors(b)
		b.Box(0, 94, 2, 8, 4, 4, rgb(200, 200, 210), M.Metal)
		b.Tube(0, 94, 6, 0, 88, 14, 1, rgb(200, 200, 210), M.Metal)
		if kind == "Terrarium" then
			for index = 0, 2 do
				local a = index / 3 * math.pi * 2
				b.Tube(0, 88, 14, math.cos(a) * 12, 64, 14 + math.sin(a) * 12, 0.6, rgb(200, 170, 120), M.SmoothPlastic)
			end
			local globe = b.Ball(0, 48, 14, 40, GLASS, M.Glass)
			globe.Transparency = 0.6
			globe.CastShadow = false
			b.Egg(0, 36, 14, 30, 8, 30, rgb(200, 170, 130), M.Sand)
			b.Ball(-6, 44, 14, 12, green, M.SmoothPlastic)
			b.Ball(6, 42, 18, 9, lighten(green, 0.15), M.SmoothPlastic)
			b.Ball(4, 40, 8, 6, rgb(255, 150, 180), M.SmoothPlastic)
			b.Footprint(44, 30, 100)
			return
		end
		for index = 0, 2 do
			local a = index / 3 * math.pi * 2
			b.Tube(0, 88, 14, math.cos(a) * 14, 62, 14 + math.sin(a) * 14, 0.6, rgb(230, 220, 200), M.Fabric)
		end
		b.Egg(0, 54, 14, 34, 24, 34, potColor, M.SmoothPlastic)
		b.Cyl(0, 60, 14, 32, 4, lighten(potColor, 0.15), M.SmoothPlastic)
		b.Cyl(0, 63, 14, 28, 2, rgb(110, 80, 66), M.Ground)
		if kind == "Herbs" then
			for index = 0, 6 do
				local a = index / 7 * math.pi * 2
				b.Tube(math.cos(a) * 6, 64, 14 + math.sin(a) * 6, math.cos(a) * 12, 80 + (index % 3) * 4, 14 + math.sin(a) * 12, 1.5, green, M.SmoothPlastic)
				b.Egg(math.cos(a) * 12, 80 + (index % 3) * 4, 14 + math.sin(a) * 12, 8, 5, 8, lighten(green, 0.1), M.SmoothPlastic)
			end
		else
			-- lianes qui retombent
			for index = 0, 5 do
				local a = index / 6 * math.pi * 2
				local x, z = math.cos(a) * 16, 14 + math.sin(a) * 14
				local points = { { x * 0.6, 64, (z - 14) * 0.6 + 14 }, { x, 56, z }, { x * 1.1, 40 - index * 3, z }, { x * 0.9, 24 - index * 3, z } }
				House3DKit.Path(b, points, 1.2, darken(green, 0.2), M.SmoothPlastic)
				for step = 2, 4 do
					local p = points[step]
					leaf(b, p[1], p[2], p[3], 9, a + step, -0.3, step % 2 == 0 and green or lighten(green, 0.2))
				end
			end
		end
		b.Footprint(56, 34, 100)
	end
end
R.HangingHerbs = hanging("Herbs")
R.HangingPothos = hanging("Pothos")
R.HangingTerrarium = hanging("Terrarium")

-- Échelle en bois (appuyée contre le mur)
R.Ladder = function(b, _ctx)
	local wood = H.woodOf(b, WOOD)
	for _, x in ipairs({ -16, 16 }) do
		b.BoxR(CFrame.new(x, 48, 0) * CFrame.Angles(-0.12, 0, 0), 6, 98, 6, wood, M.Wood)
	end
	for index = 0, 5 do
		local y = 10 + index * 16
		b.BoxR(CFrame.new(0, y, -(y - 48) * 0.12), 32, 4, 5, darken(wood, 0.08), M.Wood)
	end
	-- plaid posé sur un barreau
	local blanket = vivid(b, 1, rgb(255, 170, 200))
	b.Box(0, 56, 4, 30, 24, 2, blanket, M.Fabric)
	b.Box(0, 74, -1, 30, 3, 10, blanket, M.Fabric)
	b.Footprint(44, 20, 100)
end

----------------------------------------------------------------------
-- Branchement
----------------------------------------------------------------------

function House3DObjects.Register(recipes: { [string]: any }, _family: { [string]: any }, helpers: any, flags: any)
	H = helpers
	for id, recipe in pairs(R) do
		-- (v9.8) finition réaliste : reflets du métal, du verre, du marbre
		recipes[id] = House3DKit.Polished(recipe)
	end
	flags.Flat.CloudRug = true
	flags.Flat.RaceTrackRug = true
	flags.Flat.HeartRug = true
end

return House3DObjects
