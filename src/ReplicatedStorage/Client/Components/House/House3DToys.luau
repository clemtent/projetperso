--[[
	House3DToys (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DToys

	(v9.3) Recettes 3D des jouets, de l'électronique, de la cuisine
	gourmande, du coin gamer, du sport, de l'aventure, des accessoires des
	animaux et des tapis à forme : de vraies petites maquettes (blocs arrondis,
	ovales, tubes, pentes ; écrans et voyants en Neon) aux couleurs du dessin
	2D de chaque objet.

	Repère : House3DKit.Builder (boîte 2D = 100 unités ; y = hauteur depuis
	le sol ; +z = devant ; objets muraux : z = 0 = le mur). Branché par
	House3DRecipes (Register).
]]

local House3DKit = require(script.Parent.House3DKit)
-- (v9.9 SCALE99) aiguilles à l'heure réelle
local House3DTime = require(script.Parent.House3DTime)

type Builder = House3DKit.Builder

local House3DToys = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(60, 44, 66)
local CARBON = rgb(44, 42, 56)
local GOLD = rgb(245, 190, 60)
local CHROME = rgb(214, 218, 230)
local GLASS = rgb(200, 235, 255)
local SCREEN = rgb(120, 200, 255)
local NEON_PINK = rgb(255, 80, 200)
local NEON_CYAN = rgb(80, 230, 255)
local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

local R: { [string]: (b: Builder, ctx: any) -> () } = {}
local H: any = nil

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

local function screen(b: Builder, x: number, y: number, z: number, w: number, h: number, color: Color3?): BasePart
	local panel = b.Box(x, y, z, w, h, 0.8, color or SCREEN, M.Neon)
	panel.CastShadow = false
	table.insert(b.Glows, panel)
	return panel
end

local function wheel(b: Builder, x: number, y: number, z: number, diameter: number, width: number, rim: Color3?)
	b.CylZ(x, y, z, diameter, width, CARBON, M.Rubber)
	b.CylZ(x, y, z, diameter * 0.55, width + 0.4, rim or CHROME, M.Metal)
end

----------------------------------------------------------------------
-- JOUETS
----------------------------------------------------------------------

R.YoYo = function(b, _ctx)
	-- (v9.9 SCALE99) vrai yo-yo : deux moitiés bombées (bord arrondi, flasque
	-- intérieure, capuchon central transparent + étoile), axe métallique
	-- dans l'entrefer, ficelle enroulée, brin qui monte et boucle pour le doigt
	local color = vivid(b, 1, rgb(255, 110, 150))
	local g = House3DKit.Gap(b, 0.6)
	local cy = 36
	for _, side in ipairs({ -1, 1 }) do
		b.CylZ(0, cy, side * 9, 64, 11, color, M.SmoothPlastic)
		-- bord arrondi (anneau un peu plus large, plus sombre) et flasque bombée
		b.CylZ(0, cy, side * 9, 70, 6, darken(color, 0.12), M.SmoothPlastic)
		b.EggR(CFrame.new(0, cy, side * 14.5), 56, 56, 6, lighten(color, 0.08), M.SmoothPlastic)
		-- capuchon central transparent et son étoile
		local cap = b.CylZ(0, cy, side * (17.5 + g), 26, 2, rgb(236, 246, 255), M.Glass)
		cap.Transparency = 0.35
		House3DKit.Star(b, 0, cy, side > 0 and 17 + 2 * g or -(18 + 2 * g), 9, 1, WHITE, M.SmoothPlastic)
	end
	-- entrefer : axe + ficelle enroulée
	b.CylZ(0, cy, 0, 10, 8, CHROME, M.Metal)
	b.CylZ(0, cy, 0, 24, 5, rgb(250, 248, 240), M.Fabric)
	-- brin : part du bas de la bobine, monte, boucle du doigt en haut
	local path = { { 11, cy, 0 }, { 14, cy + 20, 0 }, { 12, cy + 40, 0 }, { 8, cy + 54, 0 } }
	for index = 0, 8 do
		local a = index / 8 * math.pi * 2
		table.insert(path, { 8 + math.sin(a) * 5, cy + 60 - math.cos(a) * 6, math.cos(a) * 1.5 })
	end
	House3DKit.Path(b, path, 1.4, rgb(250, 248, 240), M.Fabric)
	b.Footprint(70, 30, 80)
end

R.PuzzlePieces = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 120, 150)), vivid(b, 2, rgb(120, 190, 255)), vivid(b, 3, rgb(255, 210, 80)), vivid(b, 4, rgb(140, 220, 140)) }
	local spots = { { -20, 0, -12, 0.1 }, { 18, 0, -8, -0.3 }, { -6, 0, 16, 0.5 }, { 22, 6, 16, 0.2 } }
	for index, p in ipairs(spots) do
		local color = colors[index]
		local cf = CFrame.new(p[1], p[2] + 3, p[3]) * CFrame.Angles(0, p[4], p[2] > 0 and 0.3 or 0)
		b.BoxR(cf, 30, 6, 30, color, M.SmoothPlastic)
		b.Part("Part", cf * CFrame.new(15, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(6, 12, 12), color, M.SmoothPlastic, "Tenon");
		((b.Parts[#b.Parts]) :: Part).Shape = Enum.PartType.Cylinder
		b.Part("Part", cf * CFrame.new(0, 0, 15) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(6, 12, 12), color, M.SmoothPlastic, "Tenon");
		((b.Parts[#b.Parts]) :: Part).Shape = Enum.PartType.Cylinder
	end
	b.Footprint(80, 70, 20)
end

R.MagicWand = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 150, 210))
	b.Round(0, 0, 0, 60, 8, 30, 6, rgb(250, 240, 250), M.SmoothPlastic)
	b.Tube(-22, 12, 0, 20, 60, 0, 5, color, M.SmoothPlastic)
	for index = 0, 3 do
		local t = index / 4
		b.Ball(-22 + t * 42, 12 + t * 48, 0, 6, index % 2 == 0 and WHITE or GOLD, M.SmoothPlastic)
	end
	local before = #b.Parts
	House3DKit.Star(b, 24, 70, -4, 20, 8, rgb(255, 226, 110), M.Neon)
	b.Light(b.Parts[before + 1], rgb(255, 230, 150), 8, 0.6)
	for index = 0, 4 do
		local a = index * 1.3
		b.Ball(24 + math.cos(a) * 22, 70 + math.sin(a) * 18, 0, 3, index % 2 == 0 and NEON_CYAN or rgb(255, 170, 230), M.Neon)
	end
	b.Footprint(70, 30, 92)
end

-- Guitares
local function guitar(electric: boolean)
	return function(b: Builder, _ctx: any)
		local body = vivid(b, 1, electric and rgb(240, 60, 60) or rgb(255, 140, 190))
		local stand = rgb(60, 60, 70)
		b.Tube(-14, 0, -10, 0, 34, -8, 3, stand, M.Metal)
		b.Tube(14, 0, -10, 0, 34, -8, 3, stand, M.Metal)
		b.Tube(0, 0, 10, 0, 34, -8, 3, stand, M.Metal)
		local tilt = CFrame.Angles(-0.2, 0, 0)
		local base = CFrame.new(0, 30, 0) * tilt
		if electric then
			b.EggR(base, 44, 40, 10, body, M.SmoothPlastic)
			b.EggR(base * CFrame.new(-8, 18, 0) * CFrame.Angles(0, 0, 0.5), 18, 26, 10, body, M.SmoothPlastic)
			b.EggR(base * CFrame.new(8, 18, 0) * CFrame.Angles(0, 0, -0.3), 14, 22, 10, body, M.SmoothPlastic)
			-- flammes
			for index = 0, 2 do
				b.EggR(base * CFrame.new(-10 + index * 10, -8, 5.2) * CFrame.Angles(0, 0, 0.3), 8, 18, 1, index % 2 == 0 and rgb(255, 200, 60) or rgb(255, 130, 50), M.SmoothPlastic)
			end
			b.BoxR(base * CFrame.new(0, 2, 5.5), 22, 5, 1, CARBON)
			b.BoxR(base * CFrame.new(0, -10, 5.5), 20, 4, 1, CHROME, M.Metal)
		else
			b.EggR(base, 46, 36, 12, body, M.SmoothPlastic)
			b.EggR(base * CFrame.new(0, 24, 0), 34, 26, 12, body, M.SmoothPlastic)
			b.Part("Part", base * CFrame.new(0, 10, 6.2) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(1, 12, 12), CARBON, M.SmoothPlastic, "Rosace");
			((b.Parts[#b.Parts]) :: Part).Shape = Enum.PartType.Cylinder
			b.BoxR(base * CFrame.new(0, -6, 6.2), 16, 3, 1.5, darken(body, 0.35), M.Wood)
		end
		b.BoxR(base * CFrame.new(0, 58, 0), 6, 50, 4, rgb(150, 100, 70), M.Wood)
		b.BoxR(base * CFrame.new(0, 88, 0), 9, 14, 4, CARBON, M.Wood)
		-- clés d'accordage
		for index = 0, 2 do
			for _, side in ipairs({ -1, 1 }) do
				local p = (base * CFrame.new(side * 5.5, 84 + index * 4, 0)).Position
				b.CylX(p.X, p.Y, p.Z, 2, 3, CHROME, M.Metal)
			end
		end
		-- cordes
		for index = -1, 1 do
			local a = (base * CFrame.new(index * 1.4, -8, 6.4)).Position
			local c = (base * CFrame.new(index * 1.4, 84, 2.2)).Position
			b.Tube(a.X, a.Y, a.Z, c.X, c.Y, c.Z, 0.4, rgb(250, 250, 240), M.Metal)
		end
		b.Footprint(50, 36, 100)
	end
end
R.PinkGuitar = guitar(false)
R.ElectricGuitar = guitar(true)

-- Chevaux (à bascule / de manège)
local function horse(b: Builder, base: CFrame, body: Color3, mane: Color3, saddle: Color3)
	b.EggR(base * CFrame.new(0, 0, 0), 46, 26, 22, body, M.SmoothPlastic)
	b.EggR(base * CFrame.new(24, 14, 0) * CFrame.Angles(0, 0, -0.9), 14, 28, 14, body, M.SmoothPlastic)
	b.EggR(base * CFrame.new(34, 26, 0) * CFrame.Angles(0, 0, -0.35), 24, 14, 14, body, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		local eye = (base * CFrame.new(34, 30, side * 6.5)).Position
		b.Ball(eye.X, eye.Y, eye.Z, 3.5, INK, M.SmoothPlastic)
		local ear = base * CFrame.new(28, 36, side * 4)
		b.Part("WedgePart", ear, Vector3.new(3, 8, 5), body, M.SmoothPlastic, "Oreille")
	end
	for index = 0, 4 do
		local p = base * CFrame.new(18 - index * 2, 30 - index * 5, 0)
		b.EggR(p, 8, 10, 8, mane, M.Fabric)
	end
	b.EggR(base * CFrame.new(-26, 4, 0) * CFrame.Angles(0, 0, 0.8), 8, 24, 8, mane, M.Fabric)
	b.EggR(base * CFrame.new(-2, 12, 0), 20, 6, 24, saddle, M.Leather)
end

R.RockingHorse = function(b, _ctx)
	local body = vivid(b, 1, rgb(255, 250, 250))
	local mane = vivid(b, 2, rgb(255, 150, 200))
	local wood = H.woodOf(b, rgb(214, 164, 120))
	-- bascules courbes
	for _, z in ipairs({ -12, 12 }) do
		local points = {}
		for index = 0, 8 do
			local t = (index / 8 - 0.5) * 1.6
			table.insert(points, { math.sin(t) * 48, 10 - math.cos(t) * 10 + 4, z })
		end
		House3DKit.Path(b, points, 5, wood, M.Wood)
	end
	for _, x in ipairs({ -16, 16 }) do
		for _, z in ipairs({ -12, 12 }) do
			b.Tube(x, 4, z, x * 0.8, 40, z * 0.5, 4, body, M.SmoothPlastic)
		end
	end
	horse(b, CFrame.new(0, 48, 0), body, mane, vivid(b, 3, rgb(120, 190, 255)))
	b.Tube(18, 64, -12, 18, 64, 12, 2.5, GOLD, M.Metal)
	b.Seat(-2, 56, 0, 24, 20)
	b.Footprint(100, 34, 88)
end

R.CarouselHorse = function(b, _ctx)
	local body = vivid(b, 1, rgb(255, 250, 250))
	local mane = vivid(b, 2, rgb(255, 170, 210))
	b.Cyl(0, 0, 0, 60, 8, vivid(b, 3, rgb(120, 190, 255)), M.SmoothPlastic)
	b.Cyl(0, 8, 0, 50, 3, GOLD, M.Metal)
	b.Tube(0, 10, 0, 0, 100, 0, 4, GOLD, M.Metal)
	for index = 0, 8 do
		b.Ball(0, 16 + index * 10, 0, 5.5, index % 2 == 0 and GOLD or WHITE, M.Metal)
	end
	horse(b, CFrame.new(0, 54, 0) * CFrame.Angles(0, 0, 0.15), body, mane, rgb(255, 120, 160))
	for _, x in ipairs({ -14, 14 }) do
		b.Tube(x, 44, 6, x - 4, 30, 8, 4, body, M.SmoothPlastic)
		b.Tube(x, 44, -6, x + 4, 32, -8, 4, body, M.SmoothPlastic)
	end
	b.Footprint(64, 60, 100)
end

R.ToyTrain = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 110, 130)), vivid(b, 2, rgb(120, 190, 255)), vivid(b, 3, rgb(255, 210, 80)) }
	-- rails
	for _, z in ipairs({ -8, 8 }) do
		b.Box(0, 0, z, 100, 2, 2, CHROME, M.Metal)
	end
	for index = 0, 9 do
		b.Box(-45 + index * 10, 0, 0, 4, 1.5, 22, rgb(170, 120, 80), M.Wood)
	end
	-- locomotive
	b.Round(20, 8, 0, 34, 16, 20, 3, colors[1], M.SmoothPlastic)
	b.CylX(24, 32, 0, 18, 26, colors[1], M.SmoothPlastic)
	b.Box(10, 24, 0, 14, 22, 20, colors[1], M.SmoothPlastic)
	b.Box(10, 46, 0, 18, 3, 22, INK)
	screen(b, 10, 34, 10.1, 8, 7, rgb(255, 240, 180))
	b.Cyl(30, 40, 0, 7, 12, CARBON, M.Metal)
	b.Cyl(30, 52, 0, 10, 3, CARBON, M.Metal)
	b.Ball(38, 32, 0, 6, GOLD, M.Metal)
	b.Ball(30, 60, 0, 8, WHITE, M.SmoothPlastic)
	b.Ball(36, 66, 0, 6, WHITE, M.SmoothPlastic)
	-- wagons
	for index = 1, 2 do
		local x = 20 - index * 30
		b.Round(x, 8, 0, 26, 16, 20, 3, colors[index + 1], M.SmoothPlastic)
		b.Box(x, 24, 0, 22, 4, 16, lighten(colors[index + 1], 0.3), M.SmoothPlastic)
		for _, dx in ipairs({ -6, 6 }) do
			b.Ball(x + dx, 30, (dx > 0) and 3 or -2, 8, colors[(index + 1) % 3 + 1], M.SmoothPlastic)
		end
		for _, dx in ipairs({ -8, 8 }) do
			for _, z in ipairs({ -10, 10 }) do
				b.CylZ(x + dx, 7, z, 10, 2, GOLD, M.Metal)
			end
		end
	end
	for _, dx in ipairs({ 12, 28 }) do
		for _, z in ipairs({ -10, 10 }) do
			wheel(b, dx, 8, z, 12, 2, GOLD)
		end
	end
	b.Footprint(100, 26, 70)
end

R.BlanketFort = function(b, _ctx)
	local blanket = vivid(b, 1, rgb(255, 170, 200))
	local second = vivid(b, 2, rgb(170, 200, 255))
	local wood = rgb(214, 164, 120)
	-- deux chaises + un drap tendu
	for _, x in ipairs({ -40, 40 }) do
		b.Box(x, 0, -14, 4, 60, 4, wood, M.Wood)
		b.Box(x, 0, 14, 4, 60, 4, wood, M.Wood)
	end
	b.Tube(-42, 60, 0, 42, 60, 0, 3, wood, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(0, 34, side * 20) * CFrame.Angles(side * 0.55, 0, 0), 92, 60, 2, side < 0 and blanket or second, M.Fabric)
	end
	b.Box(0, 0, 2, 50, 3, 40, lighten(second, 0.3), M.Fabric)
	b.Cushion(-14, 3, 6, 18, 10, 14, rgb(255, 230, 150))
	-- guirlande lumineuse
	for index = 0, 6 do
		b.Ball(-36 + index * 12, 58 - (index % 2) * 3, 3, 4, index % 2 == 0 and rgb(255, 230, 120) or rgb(255, 150, 200), M.Neon)
	end
	b.Light(b.Parts[#b.Parts], rgb(255, 220, 160), 10, 0.6)
	b.Footprint(96, 60, 70)
end

R.DollCastle = function(b, _ctx)
	local wall = rgb(255, 240, 246)
	local roof = vivid(b, 1, rgb(255, 130, 180))
	local accent = vivid(b, 2, rgb(170, 150, 255))
	b.Box(0, 0, 0, 60, 50, 40, wall, M.SmoothPlastic)
	for index = 0, 4 do
		b.Box(-24 + index * 12, 50, 18, 6, 6, 4, wall, M.SmoothPlastic)
	end
	for _, x in ipairs({ -36, 36 }) do
		b.Cyl(x, 0, 0, 24, 66, wall, M.SmoothPlastic)
		for index = 0, 3 do
			b.Cyl(x, 66 + index * 6, 0, 28 - index * 7, 6.2, roof, M.SmoothPlastic)
		end
		b.Tube(x, 90, 0, x, 100, 0, 1, GOLD, M.Metal)
		House3DKit.Triangle(b, x + 4, 97, 0, 5, 8, -math.pi / 2, 1, accent, M.Fabric)
		b.Box(x, 36, 11.5, 8, 12, 1, rgb(160, 210, 255), M.Glass)
	end
	-- tour centrale
	b.Box(0, 50, 0, 26, 24, 26, wall, M.SmoothPlastic)
	for index = 0, 3 do
		b.Cyl(0, 74 + index * 6, 0, 34 - index * 8, 6.2, accent, M.SmoothPlastic)
	end
	House3DKit.Heart(b, 0, 62, 13, 12, 1, roof, M.SmoothPlastic)
	-- porte en arc + fenêtres
	b.Box(0, 0, 19.5, 16, 20, 1.5, rgb(200, 140, 110), M.Wood)
	b.CylZ(0, 20, 19.5, 16, 1.5, rgb(200, 140, 110), M.Wood)
	for _, x in ipairs({ -18, 18 }) do
		b.Box(x, 28, 20.2, 8, 10, 1, rgb(160, 210, 255), M.Glass)
	end
	b.Footprint(88, 40, 100)
end

R.FerrisWheel = function(b, _ctx)
	local frame = vivid(b, 1, rgb(255, 130, 180))
	local colors = { rgb(255, 214, 90), rgb(120, 200, 255), rgb(150, 220, 140), rgb(255, 150, 200), rgb(190, 150, 255), rgb(255, 170, 110) }
	b.Round(0, 0, 0, 70, 6, 34, 5, rgb(250, 244, 250), M.SmoothPlastic)
	for _, z in ipairs({ -8, 8 }) do
		b.Tube(-26, 6, z, 0, 54, z, 3, CHROME, M.Metal)
		b.Tube(26, 6, z, 0, 54, z, 3, CHROME, M.Metal)
	end
	b.CylZ(0, 54, 0, 8, 20, GOLD, M.Metal)
	local points = {}
	for index = 0, 12 do
		local a = index / 12 * math.pi * 2
		table.insert(points, { math.cos(a) * 40, 54 + math.sin(a) * 40, 0 })
	end
	House3DKit.Path(b, points, 3, frame, M.SmoothPlastic, false, true)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		local x, y = math.cos(a) * 40, 54 + math.sin(a) * 40
		b.Tube(0, 54, 0, x, y, 0, 1.5, WHITE, M.Metal)
		-- nacelle (toujours à l'endroit)
		b.Tube(x, y, 0, x, y - 6, 0, 1, CHROME, M.Metal)
		b.Box(x, y - 16, 0, 12, 10, 10, colors[index + 1], M.SmoothPlastic)
		b.Box(x, y - 6, 0, 13, 1.5, 11, lighten(colors[index + 1], 0.3), M.SmoothPlastic)
		local bulb = b.Ball(x, y, 0, 4, rgb(255, 240, 180), M.Neon)
		bulb.CastShadow = false
	end
	b.Light(b.Parts[#b.Parts], rgb(255, 230, 170), 10, 0.6)
	b.Footprint(90, 34, 100)
end

R.Xylophone = function(b, _ctx)
	local colors = { rgb(255, 110, 120), rgb(255, 170, 80), rgb(255, 226, 90), rgb(130, 220, 130), rgb(110, 180, 255), rgb(170, 130, 255), rgb(255, 140, 200) }
	local frame = vivid(b, 1, rgb(214, 164, 120))
	for _, z in ipairs({ -10, 10 }) do
		b.BoxR(CFrame.new(0, 8, z) * CFrame.Angles(0, 0.08 * (z > 0 and -1 or 1), 0), 92, 6, 4, frame, M.Wood)
	end
	for _, x in ipairs({ -40, 40 }) do
		for _, z in ipairs({ -10, 10 }) do
			wheel(b, x, 4, z + (z > 0 and 3 or -3), 8, 2, GOLD)
		end
	end
	for index, color in ipairs(colors) do
		local x = -36 + (index - 1) * 12
		local len = 34 - index * 2.4
		b.Box(x, 11, 0, 10, 3, len, color, M.SmoothPlastic)
		for _, z in ipairs({ -len / 2 + 4, len / 2 - 4 }) do
			b.Cyl(x, 14, z, 2, 0.6, CHROME, M.Metal)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 14, 16, 22, side * 30, 24, 30, 2, rgb(214, 164, 120), M.Wood)
		b.Ball(side * 14, 16, 22, 7, colors[side > 0 and 5 or 1], M.SmoothPlastic)
	end
	b.Footprint(96, 46, 30)
end

R.JackInTheBox = function(b, _ctx)
	local boxColor = vivid(b, 1, rgb(120, 190, 255))
	local jester = vivid(b, 2, rgb(255, 120, 160))
	b.Round(0, 0, 0, 50, 44, 50, 4, boxColor, M.SmoothPlastic)
	for _, z in ipairs({ -25.5, 25.5 }) do
		House3DKit.Star(b, 0, 22, z > 0 and 25 or -27, 10, 1.5, rgb(255, 226, 110), M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(0, 58, -30) * CFrame.Angles(-1.3, 0, 0), 50, 30, 3, boxColor, M.SmoothPlastic)
	b.CylX(27, 22, 0, 4, 6, GOLD, M.Metal)
	b.Tube(31, 22, 0, 31, 30, 8, 2, GOLD, M.Metal)
	-- ressort + clown
	for index = 0, 5 do
		b.Cyl(0, 44 + index * 3.5, 0, 14 - (index % 2) * 3, 1.5, CHROME, M.Metal)
	end
	b.Egg(0, 70, 0, 24, 16, 20, jester, M.Fabric)
	b.Ball(0, 84, 0, 20, rgb(255, 232, 214), M.SmoothPlastic)
	b.Ball(0, 83, 10, 6, rgb(255, 80, 90), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 4, 87, 9, 3, INK, M.SmoothPlastic)
		b.Tube(side * 4, 92, 0, side * 16, 100, 2, 5, side < 0 and jester or rgb(255, 214, 90), M.Fabric)
		b.Ball(side * 16, 100, 2, 5, rgb(255, 214, 90), M.SmoothPlastic)
	end
	b.Footprint(56, 56, 100)
end

-- Petites voitures
local function car(b: Builder, color: Color3, scale: number, monster: boolean)
	local wheelD = monster and 26 or 16
	local y0 = monster and 20 or 8
	b.Round(0, y0, 0, 70 * scale, 16, 36, 6, color, M.SmoothPlastic)
	b.Round(-4, y0 + 16, 0, 40 * scale, 14, 30, 6, lighten(color, 0.12), M.SmoothPlastic)
	local glass = b.Box(-4, y0 + 18, 0, 40 * scale + 1, 9, 26, rgb(170, 220, 255), M.Glass)
	glass.Transparency = 0.2
	for _, x in ipairs({ -22 * scale, 22 * scale }) do
		for _, z in ipairs({ -18, 18 }) do
			wheel(b, x, wheelD / 2, z, wheelD, monster and 10 or 5, monster and rgb(255, 214, 90) or CHROME)
		end
	end
	for _, z in ipairs({ -12, 12 }) do
		b.CylX(35 * scale + 0.5, y0 + 9, z, 6, 1.5, rgb(255, 240, 180), M.Neon)
		b.CylX(-35 * scale - 0.5, y0 + 9, z, 5, 1.5, rgb(255, 80, 80), M.Neon)
	end
	if monster then
		for _, z in ipairs({ -12, 12 }) do
			b.Tube(-18, y0, z, 18, y0, z, 3, CHROME, M.Metal)
		end
		b.Tube(-30, y0 + 30, 0, -30, y0 + 50, 0, 1, CARBON, M.Metal)
	end
end
R.ToyCar = function(b, _ctx)
	car(b, vivid(b, 1, rgb(255, 130, 180)), 1.25, false)
	b.Footprint(92, 44, 48)
end
R.RCCar = function(b, _ctx)
	car(b, vivid(b, 1, rgb(80, 150, 255)), 1.1, true)
	b.Footprint(90, 50, 80)
end

R.ToyGarage = function(b, _ctx)
	local wall = vivid(b, 1, rgb(255, 214, 90))
	local roof = vivid(b, 2, rgb(255, 110, 120))
	b.Box(0, 0, -6, 90, 40, 36, wall, M.SmoothPlastic)
	for index = 0, 1 do
		b.Box(-20 + index * 40, 4, 12.2, 30, 26, 1, rgb(60, 60, 80))
		b.Box(-20 + index * 40, 4, 12.6, 30, 3, 1, CHROME, M.Metal)
	end
	b.Box(0, 40, -6, 94, 4, 40, roof, M.SmoothPlastic)
	-- rampe qui descend du toit
	b.BoxR(CFrame.new(38, 24, 26) * CFrame.Angles(0, 0, 0.5), 50, 3, 18, rgb(120, 120, 140), M.SmoothPlastic)
	b.Box(0, 44, -6, 30, 18, 20, lighten(wall, 0.2), M.SmoothPlastic)
	b.Box(0, 62, -6, 34, 3, 24, roof, M.SmoothPlastic)
	House3DKit.Heart(b, 0, 52, 4, 8, 1, roof, M.SmoothPlastic)
	-- petite voiture garée devant
	b.Round(-20, 3, 26, 22, 7, 12, 3, rgb(120, 190, 255), M.SmoothPlastic)
	b.Round(-22, 10, 26, 12, 5, 10, 3, rgb(160, 210, 255), M.SmoothPlastic)
	for _, x in ipairs({ -27, -13 }) do
		for _, z in ipairs({ 20, 32 }) do
			wheel(b, x, 3, z, 6, 2)
		end
	end
	b.Footprint(96, 70, 66)
end

-- Tas de peluches (petites boules-animaux entassées)
R.PlushPile = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 180, 200)), vivid(b, 2, rgb(200, 170, 255)), vivid(b, 3, rgb(255, 220, 150)), vivid(b, 4, rgb(170, 220, 255)), rgb(250, 250, 252) }
	local spots = { { -24, 16, 6, 30 }, { 20, 16, 4, 32 }, { 0, 14, -16, 28 }, { -6, 40, 0, 28 }, { 18, 42, -8, 22 }, { 2, 62, -4, 22 } }
	for index, p in ipairs(spots) do
		local color = colors[(index - 1) % #colors + 1]
		b.Egg(p[1], p[2], p[3], p[4], p[4] * 0.9, p[4] * 0.9, color, M.Fabric)
		b.Ball(p[1], p[2] + p[4] * 0.45, p[3] + 2, p[4] * 0.7, color, M.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			b.Ball(p[1] + side * p[4] * 0.26, p[2] + p[4] * 0.72, p[3] + 1, p[4] * 0.28, color, M.Fabric)
			b.Ball(p[1] + side * p[4] * 0.12, p[2] + p[4] * 0.48, p[3] + 2 + p[4] * 0.33, p[4] * 0.1, INK, M.SmoothPlastic)
		end
	end
	b.Footprint(84, 60, 80)
end

----------------------------------------------------------------------
-- ÉLECTRONIQUE
----------------------------------------------------------------------

R.RotaryPhone = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 130, 170))
	b.Round(0, 0, 0, 64, 18, 48, 8, color, M.SmoothPlastic)
	b.Part("WedgePart", CFrame.new(0, 26, 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(56, 16, 36), color, M.SmoothPlastic, "Pente")
	b.Part("Part", CFrame.new(0, 28, 12) * CFrame.Angles(-0.42, 0, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(3, 30, 30), rgb(250, 246, 250), M.SmoothPlastic, "Cadran");
	((b.Parts[#b.Parts]) :: Part).Shape = Enum.PartType.Cylinder
	for index = 0, 9 do
		local a = index / 10 * math.pi * 1.6 + 0.4
		local p = (CFrame.new(0, 28, 12) * CFrame.Angles(-0.42, 0, 0) * CFrame.new(math.cos(a) * 10, math.sin(a) * 10, 1.8)).Position
		b.Ball(p.X, p.Y, p.Z, 3.5, INK, M.SmoothPlastic)
	end
	-- combiné
	b.Box(0, 34, -10, 56, 5, 10, darken(color, 0.1), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Egg(side * 28, 36, -10, 14, 10, 14, darken(color, 0.1), M.SmoothPlastic)
	end
	House3DKit.Path(b, { { -30, 8, -22 }, { -36, 4, -10 }, { -34, 8, 4 }, { -32, 30, -8 } }, 2, darken(color, 0.2), M.SmoothPlastic)
	b.Footprint(80, 50, 44)
end

R.RetroRadio = function(b, _ctx)
	local body = vivid(b, 1, rgb(140, 210, 190))
	b.Round(0, 4, 0, 86, 50, 34, 10, body, M.SmoothPlastic)
	b.CylZ(-18, 30, 17, 36, 1.5, rgb(240, 230, 214), M.Fabric)
	for index = 0, 4 do
		b.Box(-18, 16 + index * 6, 18, 30, 1.5, 1, darken(body, 0.25))
	end
	b.Box(22, 28, 17.3, 30, 14, 1, rgb(255, 240, 200))
	b.Box(18, 30, 18, 1.2, 10, 1, rgb(240, 70, 70))
	for _, x in ipairs({ 14, 30 }) do
		b.CylZ(x, 16, 18, 8, 3, CHROME, M.Metal)
	end
	for _, x in ipairs({ -30, 30 }) do
		b.Box(x, 0, 0, 8, 4, 30, darken(body, 0.3))
	end
	b.Tube(-26, 54, 0, 0, 66, 0, 3, CHROME, M.Metal)
	b.Tube(0, 66, 0, 26, 54, 0, 3, CHROME, M.Metal)
	b.Tube(30, 54, -6, 44, 92, -10, 1.5, CHROME, M.Metal)
	b.Footprint(90, 36, 90)
end

R.Smartphone = function(b, _ctx)
	local case = vivid(b, 1, rgb(255, 170, 200))
	b.Round(0, 0, -6, 44, 3, 30, 4, rgb(240, 236, 246), M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 40, 0) * CFrame.Angles(-0.25, 0, 0), 40, 78, 6, case, M.SmoothPlastic)
	local glass = b.BoxR(CFrame.new(0, 41, 0) * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 0, 3.2), 34, 66, 0.6, rgb(130, 190, 255), M.Neon)
	table.insert(b.Glows, glass)
	for row = 0, 2 do
		for column = 0, 2 do
			local p = CFrame.new(0, 41, 0) * CFrame.Angles(-0.25, 0, 0) * CFrame.new(-10 + column * 10, 18 - row * 10, 3.8)
			b.BoxR(p, 7, 7, 0.6, ({ rgb(255, 130, 160), rgb(255, 214, 90), rgb(130, 220, 150) })[(row + column) % 3 + 1])
		end
	end
	b.BoxR(CFrame.new(0, 41, 0) * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 30, 3.6), 10, 2, 0.6, CARBON)
	b.Footprint(46, 34, 84)
end

R.InstantCamera = function(b, _ctx)
	local body = vivid(b, 1, rgb(140, 200, 255))
	b.Round(0, 0, 0, 80, 56, 44, 10, body, M.SmoothPlastic)
	b.Round(0, 56, -6, 60, 10, 30, 6, lighten(body, 0.3), M.SmoothPlastic)
	b.CylZ(-4, 28, 22, 34, 6, rgb(240, 240, 246), M.SmoothPlastic)
	b.CylZ(-4, 28, 25, 24, 2, CARBON, M.SmoothPlastic)
	local lens = b.CylZ(-4, 28, 26.3, 14, 1, rgb(90, 130, 200), M.Glass)
	lens.Reflectance = 0.3
	b.Box(26, 40, 22, 14, 10, 1, rgb(255, 250, 230), M.Neon)
	b.CylZ(-28, 44, 22, 10, 2, CARBON)
	b.Cyl(26, 56, 6, 8, 4, rgb(255, 90, 110), M.SmoothPlastic)
	-- photo qui sort
	b.BoxR(CFrame.new(0, 4, 26) * CFrame.Angles(-0.3, 0, 0), 30, 2, 26, WHITE)
	b.BoxR(CFrame.new(0, 5.2, 27) * CFrame.Angles(-0.3, 0, 0), 24, 0.6, 18, rgb(255, 190, 150))
	b.Footprint(80, 50, 66)
end

R.RetroHandheld = function(b, _ctx)
	local body = vivid(b, 1, rgb(170, 150, 230))
	local cf = CFrame.new(0, 40, 0) * CFrame.Angles(-0.3, 0, 0)
	b.BoxR(cf, 50, 76, 12, body, M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.6)
	b.BoxR(cf * CFrame.new(0, 16, 6 + g / 2), 40, 32, g, rgb(90, 90, 110))
	local lcd = b.BoxR(cf * CFrame.new(0, 16, 6 + 1.5 * g), 32, 24, g, rgb(170, 230, 150), M.Neon)
	table.insert(b.Glows, lcd)
	b.BoxR(cf * CFrame.new(-12, -16, 6.8), 14, 4, 2, CARBON)
	b.BoxR(cf * CFrame.new(-12, -16, 6.8), 4, 14, 2, CARBON)
	for _, p in ipairs({ { 10, -12 }, { 18, -18 } }) do
		local q = (cf * CFrame.new(p[1], p[2], 6.8)).Position
		b.Ball(q.X, q.Y, q.Z, 7, rgb(255, 90, 140), M.SmoothPlastic)
	end
	b.Round(0, 0, -6, 44, 3, 28, 4, rgb(240, 236, 246), M.SmoothPlastic)
	b.Footprint(52, 30, 82)
end

-- Casques audio (chat / gamer RGB)
local function headphones(cat: boolean)
	return function(b: Builder, _ctx: any)
		local color = vivid(b, 1, cat and rgb(255, 170, 210) or rgb(90, 90, 120))
		b.Cyl(0, 0, 0, 36, 4, rgb(250, 246, 250), M.SmoothPlastic)
		b.Tube(0, 4, 0, 0, 58, 0, 4, CHROME, M.Metal)
		local points = {}
		for index = 0, 10 do
			local a = index / 10 * math.pi
			table.insert(points, { math.cos(a) * 30, 56 + math.sin(a) * 30, 0 })
		end
		House3DKit.Path(b, points, 7, color, M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			b.CylX(side * 32, 50, 0, 30, 10, color, M.SmoothPlastic)
			local pad = b.CylX(side * 26, 50, 0, 24, 3, cat and rgb(255, 240, 246) or CARBON, M.Fabric)
			local _ = pad
			if cat then
				House3DKit.Triangle(b, side * 22, 90, -3, 16, 16, side * -0.4, 6, color, M.SmoothPlastic)
				House3DKit.Triangle(b, side * 22, 89, 2.5, 8, 9, side * -0.4, 1, rgb(255, 196, 214), M.SmoothPlastic)
			else
				local ring = b.CylX(side * 37.3, 50, 0, 20, 1, side < 0 and NEON_PINK or NEON_CYAN, M.Neon)
				table.insert(b.Glows, ring)
				b.Light(ring, side < 0 and NEON_PINK or NEON_CYAN, 8, 0.5)
			end
		end
		if not cat then
			b.Tube(-32, 42, 8, -16, 34, 18, 3, CARBON, M.SmoothPlastic)
			b.Ball(-16, 34, 18, 5, CARBON, M.SmoothPlastic)
		end
		b.Footprint(80, 36, 100)
	end
end
R.CatHeadphones = headphones(true)
R.RGBHeadset = headphones(false)

R.RobotVacuum = function(b, _ctx)
	local body = vivid(b, 1, rgb(200, 190, 240))
	b.Cyl(0, 2, 0, 90, 16, body, M.SmoothPlastic)
	b.Cyl(0, 18, 0, 70, 3, lighten(body, 0.3), M.SmoothPlastic)
	b.Cyl(0, 0, 0, 86, 3, CARBON, M.Rubber)
	b.Box(0, 10, 44, 40, 6, 3, CARBON, M.Rubber)
	local led = b.Cyl(0, 21, 10, 10, 1.5, NEON_CYAN, M.Neon)
	table.insert(b.Glows, led)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 12, 22, 20, 6, INK, M.SmoothPlastic)
		b.Egg(side * 20, 20, 24, 8, 3, 4, rgb(255, 150, 180), M.SmoothPlastic)
		b.Tube(side * 30, 2, 36, side * 44, 1, 44, 1, CARBON, M.SmoothPlastic)
	end
	b.Footprint(90, 90, 24)
end

R.AirConditioner = function(b, _ctx)
	local body = rgb(248, 248, 252)
	local g = House3DKit.Gap(b, 0.6)
	-- (v9.8) split mural : coque arrondie, grille d'aspiration sur le dessus,
	-- volet orientable, lamelles, afficheur, tuyau d'évacuation
	b.Round(0, 30, 10, 96, 40, 20, 8, body, M.SmoothPlastic)
	for index = 0, 9 do
		b.Box(-40 + index * 8.8, 70, 10, 5, g, 16, rgb(220, 224, 236), M.SmoothPlastic)
	end
	b.BoxR(CFrame.new(0, 34, 20) * CFrame.Angles(0.5, 0, 0), 84, 8, 2, lighten(body, 0.1), M.SmoothPlastic)
	b.Box(0, 30.6, 17, 78, 3, 5, rgb(60, 64, 76), M.SmoothPlastic)
	for index = 0, 5 do
		b.Box(0, 36 + index * 4, 20 + g / 2, 80, 1, g, rgb(220, 224, 236))
	end
	b.Box(36, 54.5, 20 + g / 2, 12, 6, g, rgb(40, 44, 52), M.SmoothPlastic)
	b.Tube(-44, 32, 4, -46, 4, 4, 2.4, rgb(220, 220, 228), M.SmoothPlastic)
	local led = b.Box(36, 56, 20 + 1.5 * g, 6, 3, g, rgb(120, 255, 170), M.Neon)
	table.insert(b.Glows, led)
	-- petit souffle froid (flocons)
	for index = 0, 4 do
		local x = -30 + index * 15
		b.Ball(x, 22 - (index % 2) * 6, 26, 4, rgb(200, 240, 255), M.Neon)
	end
	b.Footprint(96, 24, 80)
end

R.SatelliteDish = function(b, _ctx)
	local body = rgb(236, 238, 246)
	local accent = vivid(b, 1, rgb(255, 130, 170))
	b.Box(0, 30, 3, 20, 30, 6, rgb(200, 200, 210), M.Metal)
	b.Tube(0, 45, 6, 0, 45, 22, 5, CHROME, M.Metal)
	b.EggR(CFrame.new(0, 54, 30) * CFrame.Angles(-1.0, 0.35, 0), 72, 72, 16, accent, M.Metal)
	b.EggR(CFrame.new(0, 56, 32) * CFrame.Angles(-1.0, 0.35, 0), 64, 64, 12, body, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 20, 40, 34, 0, 62, 50, 1.5, CHROME, M.Metal)
	end
	b.Tube(0, 76, 32, 0, 62, 50, 1.5, CHROME, M.Metal)
	local tip = b.Ball(0, 62, 50, 6, rgb(255, 90, 90), M.Neon)
	b.Light(tip, rgb(255, 90, 90), 6, 0.4)
	b.Footprint(76, 60, 100)
end

R.GameConsole = function(b, _ctx)
	local body = vivid(b, 1, rgb(90, 90, 110))
	b.Round(0, 0, 0, 80, 16, 50, 8, body, M.SmoothPlastic)
	b.Box(0, 16, 0, 60, 2, 36, lighten(body, 0.2), M.SmoothPlastic)
	local led = b.Box(28, 8, 25.3, 10, 2, 0.6, NEON_CYAN, M.Neon)
	table.insert(b.Glows, led)
	-- manette
	b.Egg(-6, 22, 18, 40, 8, 22, rgb(250, 250, 255), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Egg(-6 + side * 16, 22, 24, 12, 8, 14, rgb(250, 250, 255), M.SmoothPlastic)
	end
	b.Ball(-16, 26, 20, 5, CARBON, M.SmoothPlastic)
	b.Ball(4, 26, 20, 4, rgb(255, 90, 120), M.SmoothPlastic)
	b.Ball(8, 26, 16, 4, rgb(90, 200, 255), M.SmoothPlastic)
	b.Footprint(80, 50, 30)
end

R.ConsoleSet = function(b, _ctx)
	local body = vivid(b, 1, rgb(60, 60, 80))
	b.Round(0, 0, -8, 70, 44, 22, 6, body, M.SmoothPlastic)
	local stripe = b.Box(0, 4, 3.3, 4, 36, 0.6, NEON_CYAN, M.Neon)
	table.insert(b.Glows, stripe)
	for index, x in ipairs({ -22, 22 }) do
		local color = index == 1 and rgb(255, 110, 140) or rgb(110, 180, 255)
		b.Egg(x, 5, 18, 36, 8, 20, color, M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			b.Egg(x + side * 14, 5, 22, 12, 8, 14, color, M.SmoothPlastic)
		end
		b.Ball(x - 8, 9, 18, 5, CARBON, M.SmoothPlastic)
		b.Ball(x + 8, 9, 18, 5, CARBON, M.SmoothPlastic)
	end
	b.Footprint(90, 50, 48)
end

-- Casques VR
local function vr(pro: boolean)
	return function(b: Builder, _ctx: any)
		local body = vivid(b, 1, pro and rgb(70, 70, 90) or rgb(255, 255, 255))
		b.Round(0, 0, 0, 60, 6, 40, 6, rgb(240, 236, 246), M.SmoothPlastic)
		b.Round(0, 14, 0, 76, 32, 36, 12, body, M.SmoothPlastic)
		local visor = b.Box(0, 18, 18.2, 64, 24, 1, pro and NEON_CYAN or rgb(40, 40, 60), pro and M.Neon or M.Glass)
		if pro then
			table.insert(b.Glows, visor)
			b.Light(visor, NEON_CYAN, 8, 0.5)
		else
			visor.Reflectance = 0.3
		end
		-- (v9.9 SCALE99) casque complet : mousse de visage à l'arrière, sangle
		-- élastique qui fait le tour (et le dessus de la tête), capteurs devant
		local strap = pro and CARBON or rgb(220, 220, 236)
		local g = House3DKit.Gap(b, 0.6)
		b.Round(0, 16, -18 - g, 64, 26, 6, 6, rgb(60, 58, 70), M.Fabric)
		local loop = {}
		for index = 0, 12 do
			local a = index / 12 * math.pi
			table.insert(loop, { math.cos(a) * 38, 30, -18 - math.sin(a) * 30 })
		end
		House3DKit.Path(b, loop, 5, strap, M.Fabric)
		House3DKit.Path(b, { { 0, 46, -10 }, { 0, 52, -26 }, { 0, 34, -46 } }, 4, strap, M.Fabric)
		for _, x in ipairs({ -26, 26 }) do
			for _, y in ipairs({ 20, 38 }) do
				b.CylZ(x, y, 18.2 + g, 4, g, rgb(20, 20, 26), M.Glass)
			end
		end
		b.Footprint(80, 44, 52)
	end
end
R.VRGoggles = vr(false)
R.VRHeadset = vr(true)

R.KaraokeMic = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 150, 210))
	b.Cyl(0, 0, 0, 44, 5, CARBON, M.Metal)
	b.Tube(0, 5, 0, 0, 60, 0, 4, CHROME, M.Metal)
	b.Tube(0, 60, 0, 0, 72, 6, 7, color, M.SmoothPlastic)
	local head = b.Ball(0, 80, 8, 20, CHROME, M.DiamondPlate)
	local _ = head
	b.Cyl(0, 70, 7, 16, 3, color, M.SmoothPlastic)
	for index = 0, 3 do
		local a = index * 1.6
		b.Ball(math.cos(a) * 22, 76 + math.sin(a) * 12, 4, 4, index % 2 == 0 and rgb(255, 230, 120) or NEON_PINK, M.Neon)
	end
	b.Footprint(48, 44, 94)
end

R.Projector = function(b, _ctx)
	local body = vivid(b, 1, rgb(90, 90, 110))
	-- trépied
	for index = 0, 2 do
		local a = index / 3 * math.pi * 2
		b.Tube(0, 36, 0, math.cos(a) * 22, 0, math.sin(a) * 18, 3, CHROME, M.Metal)
	end
	b.Round(0, 36, 0, 60, 24, 40, 6, body, M.Metal)
	for _, x in ipairs({ -16, 16 }) do
		b.CylZ(x, 72, -4, 34, 6, darken(body, 0.2), M.Metal)
		b.CylZ(x, 72, -4, 10, 7, CHROME, M.Metal)
	end
	b.CylX(36, 48, 0, 16, 14, CARBON, M.Metal)
	local lens = b.CylX(43.5, 48, 0, 12, 1, rgb(255, 250, 220), M.Neon)
	b.Light(lens, rgb(255, 250, 220), 10, 0.7)
	-- faisceau
	local beam = b.Part("Part", CFrame.new(70, 52, 0) * CFrame.Angles(0, 0, 0.1), Vector3.new(44, 14, 14), rgb(255, 250, 230), M.Neon, "Faisceau");
	(beam :: Part).Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.85
	beam.CastShadow = false
	b.Footprint(76, 40, 92)
end

R.AlarmClock = function(b, _ctx)
	local body = vivid(b, 1, rgb(255, 120, 150))
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 18, 0, 0, side * 14, 12, 0, 5, CHROME, M.Metal)
		b.Egg(side * 20, 80, -2, 26, 18, 22, body, M.Metal)
	end
	b.Tube(-20, 80, -2, 20, 80, -2, 3, CHROME, M.Metal)
	b.CylZ(0, 44, 0, 70, 30, body, M.SmoothPlastic)
	-- (v9.9 SCALE99) cadran en couches franchement espacées (g ≈ 0,035 stud) :
	-- cadran, index, aiguilles à l'heure réelle, trotteuse, cache-axe (avant,
	-- les couches trop fines grossissaient à l'anti-scintillement et
	-- cachaient les aiguilles)
	local g = House3DKit.Gap(b, 0.6)
	local F = 15 -- (faces du même côté toujours à >= g l'une de l'autre)
	b.CylZ(0, 44, F + 0.25 * g, 56, 1.5 * g, rgb(255, 250, 240), M.SmoothPlastic)
	for index = 0, 11 do
		local a = index / 12 * math.pi * 2
		b.Box(math.sin(a) * 23, 44 + math.cos(a) * 23 - 1.5, F + 2 * g, index % 3 == 0 and 2.6 or 1.8, index % 3 == 0 and 4 or 3, g, INK)
	end
	House3DTime.Hand(b, "H", 0, 44, F + 3 * g, 14, 3, 3, g, INK)
	House3DTime.Hand(b, "M", 0, 44, F + 4.5 * g, 21, 4, 2.2, g, INK)
	House3DTime.Hand(b, "S", 0, 44, F + 6 * g, 23, 6, 0.9, g, rgb(220, 50, 60))
	b.Ball(0, 44, F + 7.6 * g, math.max(4, 1.6 * g), GOLD, M.Metal)
	b.Footprint(76, 34, 92)
end

R.Typewriter = function(b, _ctx)
	local body = vivid(b, 1, rgb(140, 200, 180))
	b.Round(0, 0, -4, 84, 26, 50, 8, body, M.SmoothPlastic)
	b.Part("WedgePart", CFrame.new(0, 13, 26) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 0), Vector3.new(76, 26, 12), body, M.SmoothPlastic, "Clavier")
	for row = 0, 2 do
		for column = 0, 7 do
			local x = -28 + column * 8 + row * 2
			b.Cyl(x, 12 + row * 6, 24 - row * 5, 5, 3, row == 1 and rgb(250, 250, 240) or INK, M.SmoothPlastic)
		end
	end
	b.CylX(0, 34, -12, 12, 92, CARBON, M.Rubber)
	for _, side in ipairs({ -1, 1 }) do
		b.CylX(side * 48, 34, -12, 8, 4, CHROME, M.Metal)
	end
	b.BoxR(CFrame.new(0, 50, -16) * CFrame.Angles(-0.2, 0, 0), 44, 34, 1, WHITE)
	for index = 0, 3 do
		b.BoxR(CFrame.new(-4, 56 - index * 5, -15.2) * CFrame.Angles(-0.2, 0, 0), 30 - index * 4, 1.2, 0.4, rgb(120, 120, 140))
	end
	b.Footprint(90, 60, 66)
end

R.DeskFan = function(b, _ctx)
	local color = vivid(b, 1, rgb(140, 210, 255))
	b.Cyl(0, 0, 0, 44, 6, color, M.SmoothPlastic)
	b.Tube(0, 6, 0, 0, 50, 0, 6, CHROME, M.Metal)
	b.Egg(0, 56, -8, 18, 18, 22, color, M.SmoothPlastic)
	-- cage ronde + pales
	local points = {}
	for index = 0, 16 do
		local a = index / 16 * math.pi * 2
		table.insert(points, { math.cos(a) * 34, 58 + math.sin(a) * 34, 6 })
	end
	House3DKit.Path(b, points, 2.5, CHROME, M.Metal)
	for index = 0, 5 do
		local a = index / 6 * math.pi
		b.Tube(math.cos(a) * 34, 58 + math.sin(a) * 34, 7, -math.cos(a) * 34, 58 - math.sin(a) * 34, 7, 0.8, CHROME, M.Metal)
	end
	for index = 0, 2 do
		local a = index / 3 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 14, 58 + math.sin(a) * 14, 4) * CFrame.Angles(0, 0.3, a), 26, 12, 1.5, lighten(color, 0.3), M.SmoothPlastic)
	end
	b.CylZ(0, 58, 6, 10, 4, color, M.SmoothPlastic)
	b.Footprint(70, 44, 94)
end

R.DrawingTablet = function(b, _ctx)
	local body = vivid(b, 1, rgb(90, 90, 110))
	local cf = CFrame.new(0, 14, 0) * CFrame.Angles(-1.1, 0, 0)
	b.BoxR(cf, 80, 56, 5, body, M.SmoothPlastic)
	local g = House3DKit.Gap(b, 0.6)
	local panel = b.BoxR(cf * CFrame.new(0, 0, 2.5 + g / 2), 66, 44, g, rgb(255, 250, 244), M.Neon)
	table.insert(b.Glows, panel)
	-- dessin : un arc-en-ciel de petits traits
	for index, color in ipairs({ rgb(255, 110, 140), rgb(255, 200, 90), rgb(120, 200, 255) }) do
		b.BoxR(cf * CFrame.new(-10 + index * 6, 4 - index * 3, 2.5 + 1.5 * g) * CFrame.Angles(0, 0, 0.3), 24, 2.5, g, color)
	end
	b.BoxR(CFrame.new(30, 6, 20) * CFrame.Angles(0, 0.6, 0), 4, 4, 40, rgb(250, 250, 255), M.SmoothPlastic)
	b.Footprint(84, 40, 34)
end

R.Hologram = function(b, _ctx)
	local color = vivid(b, 1, rgb(90, 220, 255))
	b.Cyl(0, 0, 0, 70, 10, CARBON, M.Metal)
	local ring = b.Cyl(0, 10, 0, 60, 2, color, M.Neon)
	b.Light(ring, color, 12, 0.8)
	-- globe holographique (anneaux néon semi-transparents)
	for index = 0, 3 do
		local a = index / 4 * math.pi
		local band = b.Part("Part", CFrame.new(0, 56, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0, 0, 0), Vector3.new(1, 60, 60), color, M.Neon, "Anneau");
		(band :: Part).Shape = Enum.PartType.Cylinder
		band.Transparency = 0.8
		band.CastShadow = false
	end
	local core = b.Ball(0, 56, 0, 26, lighten(color, 0.4), M.Neon)
	core.Transparency = 0.45
	core.CastShadow = false
	local beam = b.Cyl(0, 12, 0, 40, 16, color, M.Neon)
	beam.Transparency = 0.8
	beam.CastShadow = false
	b.Footprint(70, 70, 90)
end

----------------------------------------------------------------------
-- CUISINE GOURMANDE
----------------------------------------------------------------------

R.CroissantBasket = function(b, _ctx)
	local wicker = rgb(210, 160, 100)
	b.Cyl(0, 0, 0, 60, 6, darken(wicker, 0.15), M.WoodPlanks)
	b.Egg(0, 16, 0, 84, 28, 64, wicker, M.WoodPlanks)
	b.Cyl(0, 22, 0, 76, 4, lighten(wicker, 0.1), M.WoodPlanks)
	b.Cyl(0, 24, 0, 70, 2 + House3DKit.Gap(b, 0.6), rgb(255, 240, 240), M.Fabric)
	for index, p in ipairs({ { -18, 32, 4, 0.4 }, { 14, 34, -4, -0.5 }, { 0, 40, 10, 0.1 } }) do
		local cf = CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, p[4], 0)
		for seg = -2, 2 do
			local color = seg % 2 == 0 and rgb(236, 170, 80) or rgb(214, 140, 60)
			b.EggR(cf * CFrame.new(seg * 6, 0, math.abs(seg) * 2.5) * CFrame.Angles(0, seg * 0.35, 0), 9, 12 - math.abs(seg) * 2, 12 - math.abs(seg) * 2, color, M.SmoothPlastic)
		end
		local _ = index
	end
	b.Tube(-36, 22, 0, 0, 58, 0, 4, wicker, M.WoodPlanks)
	b.Tube(0, 58, 0, 36, 22, 0, 4, wicker, M.WoodPlanks)
	b.Footprint(84, 64, 62)
end

R.GiantLollipop = function(b, _ctx)
	local a = vivid(b, 1, rgb(255, 110, 170))
	local c = vivid(b, 2, rgb(120, 200, 255))
	b.Cyl(0, 0, 0, 30, 6, rgb(250, 240, 250), M.SmoothPlastic)
	b.Tube(0, 6, 0, 0, 60, 0, 5, WHITE, M.SmoothPlastic)
	b.CylZ(0, 74, 0, 50, 10, a, M.SmoothPlastic)
	-- spirale colorée sur les deux faces
	for _, z in ipairs({ -5.4, 5.4 }) do
		local points = {}
		for index = 0, 13 do
			local t = index / 13 * math.pi * 4
			local r = 3 + index * 1.6
			table.insert(points, { math.cos(t) * r, 74 + math.sin(t) * r, z })
		end
		House3DKit.Path(b, points, 3.5, z > 0 and c or lighten(c, 0.2), M.SmoothPlastic, false, true)
	end
	b.Egg(-4, 60, 4, 16, 10, 6, rgb(255, 240, 250), M.Fabric)
	b.Footprint(52, 30, 100)
end

-- Bar à glaces : comptoir, bacs de glace, coupe
R.SundaeBar = function(b, ctx)
	local top = ctx.TopY(1, 46)
	local body = vivid(b, 1, rgb(255, 190, 220))
	b.Round(0, 0, 0, 96, top - 4, 44, 4, body, M.SmoothPlastic)
	for index = 0, 5 do
		b.Box(-40 + index * 16, 0, 22.3, 8, top - 6, 1, index % 2 == 0 and WHITE or lighten(body, 0.3), M.SmoothPlastic)
	end
	b.Box(0, top - 4, 0, 100, 4, 48, rgb(250, 246, 250), M.Marble)
	local flavors = { rgb(255, 170, 200), rgb(255, 240, 200), rgb(140, 90, 70), rgb(170, 230, 190) }
	for index, color in ipairs(flavors) do
		local x = -36 + (index - 1) * 24
		b.Box(x, top - 2, -12, 18, 6, 14, CHROME, M.Metal)
		b.Egg(x, top + 4, -12, 16, 6, 12, color, M.SmoothPlastic)
	end
	-- coupe avec boules + cerise
	b.Cyl(20, top, 12, 12, 2, GLASS, M.Glass)
	b.Tube(20, top + 2, 12, 20, top + 10, 12, 3, GLASS, M.Glass)
	b.Egg(20, top + 14, 12, 20, 10, 20, GLASS, M.Glass)
	for index, color in ipairs({ flavors[1], flavors[4], flavors[2] }) do
		b.Ball(20 + (index - 2) * 5, top + 20 + (index == 2 and 4 or 0), 12, 11, color, M.SmoothPlastic)
	end
	b.Ball(20, top + 30, 12, 6, rgb(230, 40, 60), M.SmoothPlastic)
	b.Top(1, 0, top, 0, 90, 40)
	b.Footprint(100, 48, top + 32)
end

R.ChocolateFountain = function(b, _ctx)
	local choco = rgb(120, 70, 50)
	local chrome = CHROME
	b.Cyl(0, 0, 0, 80, 8, chrome, M.Metal)
	b.Cyl(0, 8, 0, 70, 8, choco, M.SmoothPlastic)
	for index = 0, 2 do
		local y = 24 + index * 22
		local d = 56 - index * 16
		b.Tube(0, y - 16, 0, 0, y, 0, 6, chrome, M.Metal)
		b.Cyl(0, y, 0, d, 4, chrome, M.Metal)
		b.Cyl(0, y - 10, 0, d - 4, 10, choco, M.SmoothPlastic)
	end
	b.Egg(0, 94, 0, 14, 10, 14, choco, M.SmoothPlastic)
	-- fruits à tremper
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.Egg(math.cos(a) * 34, 12, math.sin(a) * 34, 8, 10, 8, index % 2 == 0 and rgb(230, 50, 70) or rgb(255, 220, 110), M.SmoothPlastic)
	end
	b.Footprint(80, 80, 100)
end

R.ShavedIceMachine = function(b, _ctx)
	local body = vivid(b, 1, rgb(120, 200, 255))
	b.Round(0, 0, 0, 60, 40, 40, 8, body, M.SmoothPlastic)
	local glass = b.Cyl(0, 40, 0, 40, 30, GLASS, M.Glass)
	glass.Transparency = 0.5
	for index = 0, 5 do
		b.Ball((index % 3 - 1) * 10, 46 + math.floor(index / 3) * 8, (index % 2) * 6 - 3, 8, rgb(240, 250, 255), M.Glass)
	end
	b.Cyl(0, 70, 0, 44, 6, darken(body, 0.2), M.SmoothPlastic)
	b.Tube(24, 76, 0, 36, 90, 0, 3, CHROME, M.Metal)
	b.Ball(36, 90, 0, 6, rgb(255, 110, 150), M.SmoothPlastic)
	-- bol de glace pilée arc-en-ciel devant
	b.Cyl(-20, 40, 22, 22, 6, WHITE, M.SmoothPlastic)
	b.Egg(-20, 48, 22, 20, 14, 20, rgb(255, 160, 200), M.SmoothPlastic)
	b.Egg(-20, 52, 22, 12, 8, 12, rgb(160, 220, 255), M.SmoothPlastic)
	b.Box(0, 10, 20.2, 30, 16, 1, rgb(255, 250, 250), M.SmoothPlastic)
	b.Footprint(70, 50, 98)
end

R.Popsicles = function(b, _ctx)
	local colors = { vivid(b, 1, rgb(255, 120, 150)), vivid(b, 2, rgb(255, 210, 90)), vivid(b, 3, rgb(140, 220, 150)) }
	b.Round(0, 0, 0, 70, 14, 30, 6, rgb(250, 246, 250), M.SmoothPlastic)
	for index, color in ipairs(colors) do
		local x = -22 + (index - 1) * 22
		local tilt = (index - 2) * 0.2
		local cf = CFrame.new(x, 50, 0) * CFrame.Angles(0, 0, tilt)
		b.BoxR(cf * CFrame.new(0, -28, 0), 5, 22, 3, rgb(230, 190, 140), M.Wood)
		b.EggR(cf * CFrame.new(0, 6, 0), 18, 42, 12, color, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(0, 2, 0), 18, 30, 12, color, M.SmoothPlastic)
		b.EggR(cf * CFrame.new(-4, 14, 6), 4, 12, 1, lighten(color, 0.5), M.SmoothPlastic)
	end
	b.Footprint(76, 30, 84)
end

R.WaffleMaker = function(b, _ctx)
	local body = vivid(b, 1, rgb(255, 150, 190))
	b.Round(0, 0, 0, 76, 20, 60, 12, body, M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 40, -24) * CFrame.Angles(-1.1, 0, 0), 76, 12, 56, body, M.SmoothPlastic)
	-- gaufre dorée à carreaux
	b.Round(0, 20, 0, 58, 6, 46, 10, rgb(236, 180, 90), M.SmoothPlastic)
	for index = -2, 2 do
		b.Box(index * 10, 26, 0, 2, 1, 42, rgb(200, 140, 60))
		b.Box(0, 26, index * 8, 54, 1, 2, rgb(200, 140, 60))
	end
	b.Box(30, 10, 30.3, 10, 4, 1, rgb(120, 255, 170), M.Neon)
	b.CylX(-40, 12, 0, 8, 6, CARBON, M.SmoothPlastic)
	b.Footprint(84, 64, 60)
end

R.DumplingSteamer = function(b, _ctx)
	local bamboo = rgb(220, 180, 110)
	for index = 0, 1 do
		b.Cyl(0, index * 26, 0, 80, 24, index == 0 and bamboo or lighten(bamboo, 0.08), M.WoodPlanks)
		b.Cyl(0, index * 26 + 20, 0, 82, 4, darken(bamboo, 0.15), M.Wood)
	end
	b.Egg(0, 54, 0, 78, 18, 78, lighten(bamboo, 0.1), M.WoodPlanks)
	b.Cyl(0, 60, 0, 12, 4, darken(bamboo, 0.2), M.Wood)
	-- raviolis fumants posés devant
	for index, x in ipairs({ -18, 4, 24 }) do
		b.Egg(x, 58 + (index % 2) * 2, 26, 16, 12, 14, rgb(255, 250, 240), M.SmoothPlastic)
		b.Egg(x, 64 + (index % 2) * 2, 26, 6, 5, 6, rgb(255, 250, 240), M.SmoothPlastic)
	end
	for index = 0, 2 do
		local puff = b.Ball(-10 + index * 10, 78 + index * 6, 0, 10 - index * 2, WHITE, M.SmoothPlastic)
		puff.Transparency = 0.4
		puff.CastShadow = false
	end
	b.Footprint(82, 82, 96)
end

R.GingerbreadHouse = function(b, _ctx)
	local ginger = rgb(190, 120, 70)
	local icing = WHITE
	local candy = { vivid(b, 1, rgb(255, 110, 150)), vivid(b, 2, rgb(120, 200, 255)), vivid(b, 3, rgb(140, 220, 140)) }
	b.Cyl(0, 0, 0, 96, 4, rgb(250, 246, 250), M.SmoothPlastic)
	b.Box(0, 4, 0, 60, 36, 44, ginger, M.SmoothPlastic)
	b.Part("WedgePart", CFrame.new(-16, 54, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(50, 28, 34), ginger, M.SmoothPlastic, "Toit")
	b.Part("WedgePart", CFrame.new(16, 54, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(50, 28, 34), ginger, M.SmoothPlastic, "Toit")
	-- glaçage le long des bords du toit
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -25, 25 }) do
			b.BoxR(CFrame.new(side * 16, 55, z) * CFrame.Angles(0, 0, side * -0.69), 46, 3, 3, icing, M.SmoothPlastic)
		end
		b.Box(side * 32, 39, 0, 4, 3, 52, icing, M.SmoothPlastic)
		for index = 0, 3 do
			b.Ball(side * (8 + index * 7), 66 - index * 8, 24, 6, candy[index % 3 + 1], M.SmoothPlastic)
		end
	end
	b.Box(0, 4, 22.2, 14, 20, 1, rgb(120, 70, 40), M.SmoothPlastic)
	b.CylZ(0, 24, 22.2, 14, 1, rgb(120, 70, 40), M.SmoothPlastic)
	for _, x in ipairs({ -20, 20 }) do
		b.Box(x, 18, 22.2, 10, 10, 1, rgb(255, 230, 140), M.Neon)
		House3DKit.Frame(b, x, 17, 22.6, 12, 12, 1.5, 1, icing, M.SmoothPlastic)
	end
	b.Box(0, 38, 0, 62, 3, 46, icing, M.SmoothPlastic)
	for index = 0, 4 do
		local x = -40 + index * 20
		b.Tube(x, 4, 32, x, 18, 32, 3, WHITE, M.SmoothPlastic)
		b.BoxR(CFrame.new(x, 12, 32.3) * CFrame.Angles(0, 0, 0.6), 1.5, 5, 3.2, rgb(240, 60, 70))
	end
	b.Footprint(96, 96, 84)
end

----------------------------------------------------------------------
-- COIN GAMER / SPORT / AVENTURE
----------------------------------------------------------------------

R.BigScreenTV = function(b, _ctx)
	-- (v9.8) support mural, dos, cadre fin en alu brossé, vitre brillante
	-- devant la dalle, barre de son sous l'écran
	local g = House3DKit.Gap(b, 0.8)
	b.Box(0, 30, 0.5, 30, 20, 1, rgb(60, 60, 70), M.Metal)
	b.Round(0, 12, 3, 100, 60, 6, 3, CARBON, M.SmoothPlastic)
	b.Box(0, 12, 6 + g / 2, 99, 60, g, rgb(160, 164, 176), M.Metal).Reflectance = 0.2
	local cover = b.Box(0, 14.4, 6.6 + 5.5 * g, 95, 55.4, 0.4, rgb(220, 230, 250), M.Glass)
	cover.Transparency = 0.9
	cover.Reflectance = 0.2
	cover.CastShadow = false
	b.Box(0, 12.6, 6 + 1.5 * g, 16, 1, g, rgb(220, 224, 236), M.Metal)
	b.Round(0, 2.4, 6, 70, 5, 6, 2, rgb(34, 34, 44), M.Fabric)
	for index = -3, 3 do
		b.CylZ(index * 9, 4.9, 9 + g / 2, 3, g, rgb(20, 20, 26), M.SmoothPlastic)
	end
	local panel = screen(b, 0, 15, 6.2 + g, 94, 54, rgb(90, 150, 255))
	b.Light(panel, rgb(120, 170, 255), 14, 0.8)
	-- image de jeu : sol, montagnes, personnage
	b.Box(0, 15, 6.6 + 1.5 * g, 94, 12, g, rgb(110, 210, 120), M.Neon)
	House3DKit.Triangle(b, -24, 34, 6.6 + 2 * g, 34, 20, 0, g, rgb(140, 120, 220), M.Neon)
	House3DKit.Triangle(b, 10, 32, 6.6 + 3 * g, 26, 16, 0, g, rgb(170, 150, 240), M.Neon)
	b.Box(22, 27, 6.6 + 4.5 * g, 6, 8, g, rgb(255, 90, 90), M.Neon)
	b.Box(30, 44, 6.6 + 4.5 * g, 8, 3, g, rgb(255, 214, 90), M.Neon)
	-- rampe LED sous l'écran
	local strip = b.Box(0, 8, 4, 90, 2, 2, NEON_PINK, M.Neon)
	table.insert(b.Glows, strip)
	b.Footprint(100, 10, 76)
end

R.Dumbbells = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 110, 150))
	b.Box(0, 0, -6, 90, 6, 40, rgb(60, 60, 76), M.Metal)
	for _, z in ipairs({ -14, 6 }) do
		b.CylX(0, 18, z - 6, 6, 60, CHROME, M.Metal)
		for _, side in ipairs({ -1, 1 }) do
			b.CylX(side * 22, 18, z - 6, 26, 10, color, M.Rubber)
			b.CylX(side * 29, 18, z - 6, 20, 4, darken(color, 0.2), M.Rubber)
		end
	end
	b.Footprint(90, 40, 34)
end

R.SportsBallBin = function(b, _ctx)
	local wire = CHROME
	b.Cyl(0, 0, 0, 70, 4, rgb(80, 80, 100), M.Metal)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		b.Tube(math.cos(a) * 33, 4, math.sin(a) * 33, math.cos(a) * 36, 52, math.sin(a) * 36, 2, wire, M.Metal)
	end
	for _, y in ipairs({ 20, 52 }) do
		local points = {}
		for index = 0, 10 do
			local a = index / 10 * math.pi * 2
			table.insert(points, { math.cos(a) * 35, y, math.sin(a) * 35 })
		end
		House3DKit.Path(b, points, 2.5, wire, M.Metal, false, true)
	end
	local balls = { { rgb(255, 140, 50), 26 }, { WHITE, 24 }, { rgb(255, 214, 90), 22 }, { rgb(90, 160, 255), 24 }, { rgb(240, 70, 80), 20 } }
	local spots = { { -12, 18, -8 }, { 12, 18, 6 }, { 0, 20, 16 }, { -6, 42, 2 }, { 14, 40, -10 } }
	for index, p in ipairs(spots) do
		local ball = b.Ball(p[1], p[2], p[3], balls[index][2], balls[index][1], M.SmoothPlastic)
		local _ = ball
	end
	-- coutures du ballon de basket
	b.Tube(-12, 5, -8, -12, 31, -8, 1, INK, M.SmoothPlastic)
	b.Footprint(76, 76, 64)
end

R.Surfboard = function(b, _ctx)
	local color = vivid(b, 1, rgb(120, 200, 255))
	local stripe = vivid(b, 2, rgb(255, 150, 190))
	local cf = CFrame.new(0, 50, 0) * CFrame.Angles(-0.15, 0, 0.12)
	b.EggR(cf, 32, 100, 5, color, M.SmoothPlastic)
	b.BoxR(cf * CFrame.new(0, 0, 0.2), 4, 80, 5.2, stripe, M.SmoothPlastic)
	House3DKit.Heart(b, 0, 64, 2.2, 10, 1, stripe, M.SmoothPlastic)
	b.Part("WedgePart", cf * CFrame.new(0, -38, -4) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(6, 8, 1.5), CARBON, M.SmoothPlastic, "Aileron")
	b.Round(0, 0, -8, 30, 4, 18, 4, rgb(240, 220, 180), M.Sand)
	b.Footprint(40, 20, 100)
end

R.BMXBike = function(b, _ctx)
	local frame = vivid(b, 1, rgb(80, 180, 255))
	for _, x in ipairs({ -30, 30 }) do
		b.CylZ(x, 20, 0, 40, 5, CARBON, M.Rubber)
		b.CylZ(x, 20, 0, 32, 5 + 2 * House3DKit.Gap(b, 0.4), rgb(250, 250, 255), M.SmoothPlastic)
		for index = 0, 3 do
			local a = index / 4 * math.pi
			b.Tube(x + math.cos(a) * 15, 20 + math.sin(a) * 15, 0, x - math.cos(a) * 15, 20 - math.sin(a) * 15, 0, 0.8, CHROME, M.Metal)
		end
		b.CylZ(x, 20, 0, 6, 5 + 4 * House3DKit.Gap(b, 0.4), CHROME, M.Metal)
	end
	b.Tube(-30, 20, 0, -6, 22, 0, 3.5, frame, M.Metal)
	b.Tube(-6, 22, 0, 22, 44, 0, 3.5, frame, M.Metal)
	b.Tube(-10, 46, 0, 22, 44, 0, 3.5, frame, M.Metal)
	b.Tube(-10, 46, 0, -6, 22, 0, 3.5, frame, M.Metal)
	b.Tube(-30, 20, 0, -10, 46, 0, 3, frame, M.Metal)
	b.Tube(30, 20, 0, 22, 44, 0, 3.5, frame, M.Metal)
	b.Tube(22, 44, 0, 20, 58, 0, 3, CHROME, M.Metal)
	b.Tube(20, 58, -12, 20, 58, 12, 3, CHROME, M.Metal)
	for _, z in ipairs({ -12, 12 }) do
		b.CylZ(20, 58, z, 4.5, 6, CARBON, M.Rubber)
	end
	b.Egg(-12, 50, 0, 16, 5, 8, CARBON, M.Leather)
	b.Tube(-12, 46, 0, -12, 50, 0, 2, CHROME, M.Metal)
	b.CylZ(-6, 22, 0, 12, 2, CHROME, M.Metal)
	for _, z in ipairs({ -6, 6 }) do
		b.Box(-6, 20, z, 8, 2, 4, CARBON)
	end
	b.Footprint(100, 26, 62)
end

R.VolcanoModel = function(b, _ctx)
	local rock = rgb(150, 110, 100)
	b.Round(0, 0, 0, 90, 6, 70, 8, rgb(140, 200, 120), M.Grass)
	for index = 0, 4 do
		b.Cyl(0, 6 + index * 11, 0, 80 - index * 14, 11.2, index % 2 == 0 and rock or darken(rock, 0.1), M.Slate)
	end
	b.Cyl(0, 58, 0, 18, 3, rgb(255, 120, 40), M.CrackedLava)
	local lava = b.Ball(0, 64, 0, 14, rgb(255, 140, 50), M.Neon)
	b.Light(lava, rgb(255, 140, 60), 12, 1)
	for index = 0, 3 do
		local a = index * 1.6
		House3DKit.Path(b, { { math.cos(a) * 8, 58, math.sin(a) * 8 }, { math.cos(a) * 18, 42, math.sin(a) * 18 }, { math.cos(a) * 26, 26, math.sin(a) * 26 } }, 4, rgb(255, 120, 40), M.Neon, true)
	end
	for index = 0, 2 do
		local puff = b.Ball(-4 + index * 6, 76 + index * 8, 0, 12 - index * 2, rgb(200, 196, 210), M.SmoothPlastic)
		puff.CastShadow = false
	end
	for _, p in ipairs({ { -34, 20 }, { 32, -22 } }) do
		b.Cyl(p[1], 6, p[2], 3, 10, rgb(150, 100, 70), M.Wood)
		b.Ball(p[1], 20, p[2], 12, rgb(90, 170, 90), M.SmoothPlastic)
	end
	b.Footprint(90, 70, 92)
end

R.PirateShip = function(b, _ctx)
	local hull = rgb(150, 95, 60)
	local sail = rgb(250, 244, 230)
	local stand = rgb(100, 70, 50)
	b.Round(0, 0, 0, 60, 4, 26, 4, stand, M.Wood)
	for _, x in ipairs({ -18, 18 }) do
		b.Tube(x, 4, 0, x, 14, 0, 3, stand, M.Wood)
	end
	-- coque : bloc + proue en pente + poupe haute
	b.Box(-4, 14, 0, 60, 14, 22, hull, M.WoodPlanks)
	b.Part("WedgePart", CFrame.new(34, 21, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(22, 14, 16), hull, M.WoodPlanks, "Proue")
	b.Box(-28, 28, 0, 14, 10, 22, darken(hull, 0.1), M.WoodPlanks)
	b.Box(-4, 26, 0, 60, 2, 23, GOLD, M.Metal)
	for index = 0, 3 do
		b.CylZ(-20 + index * 12, 20, 11.5, 4, 2, CARBON, M.Metal)
	end
	-- mâts et voiles
	for index, x in ipairs({ -10, 12 }) do
		b.Tube(x, 28, 0, x, 92 - index * 6, 0, 3, stand, M.Wood)
		for sailIndex = 0, 1 do
			b.BoxR(CFrame.new(x, 48 + sailIndex * 20 - index * 3, 1) * CFrame.Angles(0.15, 0, 0), 30 - sailIndex * 6, 17, 1.5, sail, M.Fabric)
		end
	end
	House3DKit.Triangle(b, -8, 94, 0, 6, 12, -math.pi / 2, 1, CARBON, M.Fabric)
	b.BoxR(CFrame.new(-10, 60, 2.2), 6, 6, 0.5, CARBON, M.SmoothPlastic)
	b.Tube(34, 28, 0, 48, 40, 0, 2, stand, M.Wood)
	b.Footprint(90, 26, 100)
end

----------------------------------------------------------------------
-- ACCESSOIRES DES ANIMAUX
----------------------------------------------------------------------

R.PetFountain = function(b, _ctx)
	local body = vivid(b, 1, rgb(140, 210, 255))
	b.Cyl(0, 0, 0, 90, 10, body, M.SmoothPlastic)
	local water = b.Cyl(0, 10, 0, 80, 3, rgb(150, 210, 255), M.Glass)
	water.Transparency = 0.2
	b.Egg(0, 30, 0, 44, 40, 44, lighten(body, 0.2), M.SmoothPlastic)
	b.Cyl(0, 46, 0, 24, 6, body, M.SmoothPlastic)
	local jet = b.Cyl(0, 52, 0, 6, 10, rgb(190, 230, 255), M.Glass)
	jet.Transparency = 0.3
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		House3DKit.Path(b, { { 0, 62, 0 }, { math.cos(a) * 12, 58, math.sin(a) * 12 }, { math.cos(a) * 20, 42, math.sin(a) * 20 } }, 2, rgb(190, 230, 255), M.Glass)
	end
	House3DKit.Heart(b, 0, 26, 21, 14, 1.5, rgb(255, 130, 170), M.SmoothPlastic)
	b.Footprint(90, 90, 70)
end

R.BirdCage = function(b, _ctx)
	local metal = b.Map(GOLD)
	b.Cyl(0, 0, 0, 64, 8, darken(metal, 0.2), M.Metal)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2
		b.Tube(math.cos(a) * 28, 8, math.sin(a) * 28, math.cos(a) * 28, 70, math.sin(a) * 28, 1.2, metal, M.Metal)
		b.Tube(math.cos(a) * 28, 70, math.sin(a) * 28, 0, 90, 0, 1.2, metal, M.Metal)
	end
	for _, y in ipairs({ 30, 70 }) do
		local points = {}
		for index = 0, 10 do
			local a = index / 10 * math.pi * 2
			table.insert(points, { math.cos(a) * 28, y, math.sin(a) * 28 })
		end
		House3DKit.Path(b, points, 2, metal, M.Metal, false, true)
	end
	b.Ball(0, 91, 0, 6, metal, M.Metal)
	b.Tube(0, 94, 0, 0, 100, 0, 1.5, metal, M.Metal)
	b.CylX(0, 32, 0, 3, 50, rgb(170, 120, 80), M.Wood)
	-- oiseau bleu
	local bird = rgb(120, 190, 255)
	b.Egg(0, 42, 0, 16, 18, 16, bird, M.SmoothPlastic)
	b.Ball(3, 53, 2, 12, bird, M.SmoothPlastic)
	b.Ball(6, 55, 7, 3, INK, M.SmoothPlastic)
	b.EggR(CFrame.new(10, 52, 4) * CFrame.Angles(0, 0, -0.4), 6, 3, 3, rgb(255, 180, 60), M.SmoothPlastic)
	b.EggR(CFrame.new(-8, 36, -2) * CFrame.Angles(0, 0, 0.6), 4, 14, 6, darken(bird, 0.15), M.SmoothPlastic)
	b.Footprint(64, 64, 100)
end

----------------------------------------------------------------------
-- TAPIS À FORME (à plat)
----------------------------------------------------------------------

local function shadowless(b: Builder, from: number)
	for index = from, #b.Parts do
		b.Parts[index].CastShadow = false
	end
end

R.HeartRug = function(b, _ctx)
	local color = vivid(b, 1, rgb(255, 130, 170))
	local before = #b.Parts + 1
	-- cœur couché : les formes plates tournées à plat (x-z)
	local flat = CFrame.Angles(-math.pi / 2, 0, 0)
	local side = 100 / 1.707
	local offset = side / (2 * math.sqrt(2))
	b.BoxR(CFrame.new(0, 0.5, 4) * flat * CFrame.Angles(0, 0, math.pi / 4), side, side, 1, color, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		b.Cyl(sx * offset, 0, 4 - offset, side, 1, color, M.Fabric)
	end
	local inner = side * 0.72
	local innerOffset = inner / (2 * math.sqrt(2))
	b.BoxR(CFrame.new(0, 1.2, 2) * flat * CFrame.Angles(0, 0, math.pi / 4), inner, inner, 0.5, lighten(color, 0.35), M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		b.Cyl(sx * innerOffset, 1, 2 - innerOffset, inner, 0.5, lighten(color, 0.35), M.Fabric)
	end
	shadowless(b, before)
	b.Footprint(100, 90, 2)
end

R.CloudRug = function(b, _ctx)
	local color = vivid(b, 1, rgb(240, 244, 255))
	local before = #b.Parts + 1
	for _, p in ipairs({ { -30, 6, 40 }, { -8, -4, 46 }, { 18, -2, 42 }, { 34, 8, 34 }, { 4, 14, 44 }, { -24, 16, 30 } }) do
		b.Cyl(p[1], 0, p[2], p[3], 1, color, M.Fabric)
		b.Cyl(p[1], 0.8, p[2], p[3] * 0.8, 0.5, lighten(color, 0.4), M.Fabric)
	end
	shadowless(b, before)
	b.Footprint(100, 60, 2)
end

R.RaceTrackRug = function(b, _ctx)
	local grass = rgb(120, 200, 120)
	local road = rgb(90, 90, 104)
	local before = #b.Parts + 1
	b.Round(0, 0, 0, 100, 1, 66, 10, grass, M.Fabric)
	-- piste ovale (anneau de segments)
	local points = {}
	for index = 0, 20 do
		local a = index / 20 * math.pi * 2
		table.insert(points, { math.cos(a) * 36, 1.2, math.sin(a) * 20 })
	end
	for index = 1, #points - 1 do
		local p, q = points[index], points[index + 1]
		local from, to = Vector3.new(p[1], p[2], p[3]), Vector3.new(q[1], q[2], q[3])
		b.BoxR(CFrame.lookAt((from + to) / 2, to), 11, 1, (to - from).Magnitude + 2, road, M.Fabric)
	end
	for index = 0, 3 do
		b.Box(-4 + index * 2.5, 1.4, 20, 2, 0.5, 10, index % 2 == 0 and WHITE or CARBON, M.Fabric)
	end
	b.Box(-40, 1, -30, 12, 1, 8, rgb(255, 214, 90), M.Fabric)
	shadowless(b, before)
	b.Footprint(100, 66, 3)
end

----------------------------------------------------------------------
-- Branchement
----------------------------------------------------------------------

function House3DToys.Register(recipes: { [string]: any }, _family: { [string]: any }, helpers: any, _flags: any)
	H = helpers
	for id, recipe in pairs(R) do
		-- (v9.8) finition réaliste : reflets du métal, du verre, du marbre
		recipes[id] = House3DKit.Polished(recipe)
	end
end

return House3DToys
