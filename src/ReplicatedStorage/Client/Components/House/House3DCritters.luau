--[[
	House3DCritters (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DCritters

	(v9.3) Animaux et peluches de la vue 3D : de vraies petites figurines
	arrondies (ovales = Part + SpecialMesh "Sphere", boules, tubes) aux
	couleurs du dessin 2D de l'objet : corps, ventre, tête, museau, yeux
	brillants, joues, oreilles, pattes, queue, et les détails de chaque
	espèce (cornes, crinière, ailes, carapace, piquants, tentacules...).
	Les animaux (catégorie Pets) respirent doucement dans la vue 3D.

	Repère : House3DKit.Builder (boîte 2D = 100 unités ; y = hauteur depuis
	le sol ; +z = devant). Branché par House3DRecipes (Register).
	v9.8 (GARDEN98) : les VRAIS animaux (Pets) sont réalistes et articulés
	(voir "ANIMAUX RÉALISTES ARTICULÉS" plus bas) : Client/World/PetRoam les
	fait se promener dans la maison et le jardin. House3DCritters.ROAMERS =
	les espèces qui se promènent.
]]

local House3DKit = require(script.Parent.House3DKit)
-- (v11 ITEMS11) poissons vivants (bocal du poisson rouge)
local House3DFish = require(script.Parent.House3DFish)

type Builder = House3DKit.Builder

local House3DCritters = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(52, 36, 58)
local CHEEK = rgb(255, 150, 175)
local PINK_IN = rgb(255, 196, 214)
local BEAK = rgb(255, 170, 60)
local GOLD = rgb(245, 190, 60)
local GLASS = rgb(200, 235, 255)
local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

-- Couleur principale : la plus grande surface qui n'est pas un contour sombre
local function mainOf(b: Builder, fallback: Color3, allowWhite: boolean?): Color3
	for _, color in ipairs(b.Pal) do
		local _h, s, v = color:ToHSV()
		if v > 0.3 and (s > 0.1 or allowWhite) then
			return color
		end
	end
	return b.Map(fallback)
end

-- n-ième couleur vive de la palette (autre que `avoid`)
local function vivid(b: Builder, n: number, fallback: Color3, avoid: Color3?): Color3
	local count = 0
	for _, color in ipairs(b.Pal) do
		local _h, s, v = color:ToHSV()
		if s > 0.2 and v > 0.35 and (not avoid or House3DKit.Dist(color, avoid) > 0.12) then
			count += 1
			if count == n then
				return color
			end
		end
	end
	return b.Map(fallback)
end

-- z de la face avant d'un ovale (centre c, demi-axes r) au point (x, y)
local function front(cx: number, cy: number, cz: number, rx: number, ry: number, rz: number, x: number, y: number): number
	local u, v = (x - cx) / rx, (y - cy) / ry
	return cz + rz * math.sqrt(math.max(0, 1 - u * u - v * v))
end

type Head = { X: number, Y: number, Z: number, W: number, H: number, D: number }

-- Yeux brillants (+ reflet), joues roses, sur la face avant de la tête
local function face(b: Builder, head: Head, eye: number, spread: number, lift: number, sleepy: boolean?, cheeks: boolean?)
	local rx, ry, rz = head.W / 2, head.H / 2, head.D / 2
	for _, side in ipairs({ -1, 1 }) do
		local ex, ey = head.X + side * spread, head.Y + lift
		local ez = front(head.X, head.Y, head.Z, rx, ry, rz, ex, ey)
		if sleepy then
			b.BoxR(CFrame.new(ex, ey, ez - 0.3) * CFrame.Angles(0, side * 0.35, side * 0.15), eye * 1.2, eye * 0.22, eye * 0.5, INK)
		else
			b.Egg(ex, ey, ez - eye * 0.25, eye, eye * 1.12, eye * 0.7, INK, M.SmoothPlastic)
			b.Ball(ex + side * eye * 0.12, ey + eye * 0.22, ez + eye * 0.1, eye * 0.36, WHITE, M.SmoothPlastic)
		end
		if cheeks ~= false then
			local cx, cy = head.X + side * (spread + eye * 1.1), head.Y + lift - eye * 1.2
			local cz = front(head.X, head.Y, head.Z, rx, ry, rz, cx, cy)
			b.Egg(cx, cy, cz - 0.8, eye * 1.1, eye * 0.62, eye * 0.5, CHEEK, M.SmoothPlastic)
		end
	end
end

-- Museau clair + truffe
local function muzzle(b: Builder, head: Head, w: number, h: number, color: Color3, nose: Color3?)
	local my = head.Y - head.H * 0.14
	local mz = front(head.X, head.Y, head.Z, head.W / 2, head.H / 2, head.D / 2, head.X, my) - h * 0.35
	b.Egg(head.X, my, mz, w, h, h * 0.9, color, M.Fabric)
	b.Egg(head.X, my + h * 0.22, mz + h * 0.42, w * 0.3, h * 0.26, h * 0.26, nose or INK, M.SmoothPlastic)
end

-- Peluche / animal assis : corps, ventre, pattes, bras ; renvoie la tête
type Body = { Color: Color3, Belly: Color3, BW: number, BH: number, BD: number, HeadW: number, HeadH: number, HeadD: number, Feet: Color3? }
local function sitting(b: Builder, body: Body): Head
	local bw, bh, bd = body.BW, body.BH, body.BD
	local by = bh / 2 + 4
	b.Egg(0, by, 0, bw, bh, bd, body.Color, M.Fabric)
	b.Egg(0, by - bh * 0.06, bd * 0.2, bw * 0.64, bh * 0.72, bd * 0.66, body.Belly, M.Fabric)
	local feet = body.Feet or body.Color
	for _, side in ipairs({ -1, 1 }) do
		-- jambes assises (vers l'avant) + coussinets
		b.Egg(side * bw * 0.26, 7, bd * 0.36, bw * 0.3, 14, bd * 0.52, feet, M.Fabric)
		b.Egg(side * bw * 0.26, 7, bd * 0.36 + bd * 0.25, bw * 0.2, 10, 3, lighten(body.Belly, 0.2), M.Fabric)
		-- bras
		b.EggR(CFrame.new(side * bw * 0.44, by + bh * 0.08, bd * 0.18) * CFrame.Angles(0.35, 0, side * 0.35), bw * 0.24, bh * 0.52, bw * 0.24, body.Color, M.Fabric)
	end
	return { X = 0, Y = by + bh / 2 + body.HeadH * 0.36, Z = bd * 0.06, W = body.HeadW, H = body.HeadH, D = body.HeadD }
end

local function head(b: Builder, h: Head, color: Color3)
	b.Egg(h.X, h.Y, h.Z, h.W, h.H, h.D, color, M.Fabric)
end

-- Oreilles
local function roundEars(b: Builder, h: Head, size: number, color: Color3, inner: Color3?)
	for _, side in ipairs({ -1, 1 }) do
		local x, y = h.X + side * h.W * 0.36, h.Y + h.H * 0.38
		b.Egg(x, y, h.Z - 2, size, size, size * 0.6, color, M.Fabric)
		if inner then
			b.Egg(x, y - size * 0.05, h.Z - 2 + size * 0.22, size * 0.58, size * 0.58, size * 0.2, inner, M.Fabric)
		end
	end
end
local function pointyEars(b: Builder, h: Head, w: number, tall: number, color: Color3, inner: Color3?)
	for _, side in ipairs({ -1, 1 }) do
		local x, y = h.X + side * h.W * 0.3, h.Y + h.H * 0.36
		local cf = CFrame.new(x, y + tall / 2, h.Z) * CFrame.Angles(0, 0, -side * 0.28)
		b.Part("WedgePart", cf * CFrame.new(0, 0, -w * 0.25), Vector3.new(w, tall, w * 0.5), color, M.Fabric, "Oreille")
		b.Part("WedgePart", cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -w * 0.25), Vector3.new(w, tall, w * 0.5), color, M.Fabric, "Oreille")
		if inner then
			b.Part("WedgePart", cf * CFrame.new(0, -tall * 0.1, w * 0.26) * CFrame.Angles(0, math.pi, 0), Vector3.new(w * 0.55, tall * 0.7, 0.8), inner, M.Fabric, "Oreille")
		end
	end
end
local function longEars(b: Builder, h: Head, color: Color3, length: number)
	for _, side in ipairs({ -1, 1 }) do
		local cf = CFrame.new(h.X + side * h.W * 0.2, h.Y + h.H * 0.38 + length * 0.42, h.Z - 1) * CFrame.Angles(-0.12, 0, -side * 0.16)
		b.EggR(cf, h.W * 0.24, length, h.W * 0.14, color, M.Fabric)
		b.EggR(cf * CFrame.new(0, -length * 0.02, h.W * 0.05), h.W * 0.13, length * 0.78, h.W * 0.06, PINK_IN, M.Fabric)
	end
end

-- Queue en tubes (points successifs)
local function tail(b: Builder, points: { { number } }, diameter: number, color: Color3, tip: Color3?)
	for index = 1, #points - 1 do
		local a, c = points[index], points[index + 1]
		local d = diameter * (1 - (index - 1) / #points * 0.4)
		b.Tube(a[1], a[2], a[3], c[1], c[2], c[3], d, color, M.Fabric)
		b.Ball(c[1], c[2], c[3], d, (index == #points - 1 and tip) or color, M.Fabric)
	end
end

----------------------------------------------------------------------
-- Espèces
----------------------------------------------------------------------

local R: { [string]: (b: Builder, ctx: any) -> () } = {}

local function bear(big: boolean, bow: boolean)
	return function(b: Builder, _ctx: any)
		local fur = mainOf(b, rgb(214, 150, 100))
		local belly = lighten(fur, 0.45)
		local h = sitting(b, { Color = fur, Belly = belly, BW = 60, BH = 48, BD = 50, HeadW = 52, HeadH = 46, HeadD = 44 })
		head(b, h, fur)
		roundEars(b, h, 18, fur, belly)
		muzzle(b, h, 20, 14, belly)
		face(b, h, 6.5, 10, 2)
		if bow then
			local ribbon = vivid(b, 2, rgb(255, 110, 150), fur)
			local y = h.Y - h.H * 0.48
			for _, side in ipairs({ -1, 1 }) do
				b.EggR(CFrame.new(side * 7, y, 20) * CFrame.Angles(0, 0, side * 0.3), 14, 9, 5, ribbon, M.Fabric)
			end
			b.Ball(0, y, 22, 6, darken(ribbon, 0.1), M.Fabric)
		end
		if big then
			-- grand nounours : un cœur sur le ventre
			local heart = vivid(b, 2, rgb(255, 110, 150), fur)
			b.EggR(CFrame.new(-3, 30, 27) * CFrame.Angles(0, 0, 0.6), 9, 12, 3, heart, M.Fabric)
			b.EggR(CFrame.new(3, 30, 27) * CFrame.Angles(0, 0, -0.6), 9, 12, 3, heart, M.Fabric)
		end
		b.Seat(0, 30, 0, 40, 30)
		b.Footprint(66, 56, 98)
	end
end
R.TeddyBear = bear(false, true)
R.BigBear = bear(true, false)

R.PandaPlush = function(b, _ctx)
	local white = rgb(250, 250, 252)
	local black = rgb(46, 42, 54)
	local h = sitting(b, { Color = white, Belly = white, BW = 60, BH = 48, BD = 50, HeadW = 54, HeadH = 46, HeadD = 44, Feet = black })
	head(b, h, white)
	roundEars(b, h, 18, black)
	-- bras noirs + taches des yeux
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * 26, 34, 11) * CFrame.Angles(0.35, 0, side * 0.35), 15, 26, 15, black, M.Fabric)
		local x, y = side * 11, h.Y + 2
		b.EggR(CFrame.new(x, y, front(h.X, h.Y, h.Z, h.W / 2, h.H / 2, h.D / 2, x, y) - 2.5) * CFrame.Angles(0, 0, side * -0.5), 13, 16, 5, black, M.Fabric)
	end
	muzzle(b, h, 18, 12, white)
	face(b, h, 5.5, 11, 3, false, true)
	b.Seat(0, 30, 0, 40, 30)
	b.Footprint(66, 56, 96)
end

local function bunny(pet: boolean)
	return function(b: Builder, _ctx: any)
		local fur = mainOf(b, rgb(250, 246, 250), true)
		local belly = lighten(fur, 0.5)
		local h = sitting(b, { Color = fur, Belly = belly, BW = 56, BH = 44, BD = 50, HeadW = 46, HeadH = 40, HeadD = 40 })
		head(b, h, fur)
		longEars(b, h, fur, pet and 34 or 40)
		muzzle(b, h, 16, 11, belly, rgb(255, 140, 170))
		face(b, h, 5.5, 9, 2)
		b.Ball(0, 16, -26, 16, WHITE, M.Fabric) -- queue pompon
		b.Footprint(62, 58, 98)
	end
end
R.BunnyPlush = bunny(false)
R.Bunny = bunny(true)

local function cat(sleepy: boolean, calico: boolean?)
	return function(b: Builder, _ctx: any)
		local fur = mainOf(b, rgb(255, 196, 150))
		local belly = lighten(fur, 0.55)
		local patch = vivid(b, 2, darken(fur, 0.25), fur)
		if sleepy then
			-- chat couché en boule
			b.Egg(0, 17, 0, 84, 32, 54, fur, M.Fabric)
			b.Egg(0, 14, 14, 60, 22, 30, belly, M.Fabric)
			local h: Head = { X = 24, Y = 26, Z = 14, W = 40, H = 32, D = 34 }
			head(b, h, fur)
			pointyEars(b, h, 12, 13, fur, PINK_IN)
			face(b, h, 5, 8, 1, true)
			b.Egg(h.X, h.Y - 5, front(h.X, h.Y, h.Z, 20, 16, 17, h.X, h.Y - 5) - 1, 5, 3.5, 3, rgb(255, 130, 160), M.SmoothPlastic)
			tail(b, { { -38, 14, 0 }, { -40, 10, 18 }, { -26, 8, 28 }, { -8, 8, 30 } }, 9, fur, patch)
			for _, x in ipairs({ -2, 12 }) do
				b.Egg(x, 6, 26, 12, 9, 14, belly, M.Fabric)
			end
			b.Footprint(90, 60, 46)
			return
		end
		local h = sitting(b, { Color = fur, Belly = belly, BW = 54, BH = 46, BD = 46, HeadW = 50, HeadH = 42, HeadD = 40 })
		head(b, h, fur)
		pointyEars(b, h, 16, 18, fur, PINK_IN)
		face(b, h, 6.5, 10, 2)
		local nz = front(h.X, h.Y, h.Z, h.W / 2, h.H / 2, h.D / 2, 0, h.Y - 6)
		b.Egg(0, h.Y - 6, nz - 1, 6, 4, 3, rgb(255, 130, 160), M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			for _, dy in ipairs({ -1, 2 }) do
				b.BoxR(CFrame.new(side * 22, h.Y - 6 + dy, nz - 4) * CFrame.Angles(0, 0, side * dy * 0.06), 14, 0.8, 0.8, INK)
			end
		end
		-- patchs de couleur (chaton calico) + queue relevée
		if calico then
			b.Egg(-14, h.Y + 12, h.Z + 8, 18, 14, 22, patch, M.Fabric)
		else
			patch = lighten(fur, 0.4)
		end
		tail(b, { { -18, 12, -20 }, { -30, 24, -26 }, { -34, 44, -22 }, { -26, 58, -18 } }, 9, fur, patch)
		b.Footprint(60, 54, 96)
	end
end
R.KittyPlush = cat(false)
R.Kitten = cat(false, true)
R.SleepyCat = cat(true)

local function dog(plush: boolean)
	return function(b: Builder, _ctx: any)
		local fur = mainOf(b, rgb(236, 200, 160))
		local belly = lighten(fur, 0.5)
		local ear = darken(fur, 0.28)
		local h = sitting(b, { Color = fur, Belly = belly, BW = 56, BH = 46, BD = 50, HeadW = 50, HeadH = 42, HeadD = 42 })
		head(b, h, fur)
		for _, side in ipairs({ -1, 1 }) do
			b.EggR(CFrame.new(side * 25, h.Y - 2, h.Z) * CFrame.Angles(0, 0, side * 0.35), 13, 30, 12, ear, M.Fabric)
		end
		muzzle(b, h, 22, 15, belly)
		face(b, h, 6, 10, 4)
		b.EggR(CFrame.new(0, h.Y - 15, front(h.X, h.Y, h.Z, 25, 21, 21, 0, h.Y - 15) + 1) * CFrame.Angles(0.4, 0, 0), 7, 8, 3, rgb(255, 120, 150), M.SmoothPlastic)
		-- collier + médaille
		local collar = vivid(b, 2, rgb(255, 90, 120), fur)
		b.Egg(0, h.Y - h.H * 0.52, 2, 40, 6, 36, collar, M.Fabric)
		b.Ball(0, h.Y - h.H * 0.52 - 4, 20, 6, GOLD, M.Metal)
		tail(b, { { 0, 14, -24 }, { 6, 24, -32 }, { 10, 34, -30 } }, plush and 10 or 8, fur, belly)
		b.Footprint(64, 58, 96)
	end
end
R.PuppyPlush = dog(true)
R.Puppy = dog(false)

R.Fox = function(b, _ctx)
	local fur = mainOf(b, rgb(255, 140, 70))
	local cream = rgb(255, 246, 236)
	local h = sitting(b, { Color = fur, Belly = cream, BW = 52, BH = 44, BD = 46, HeadW = 50, HeadH = 40, HeadD = 42, Feet = rgb(70, 50, 60) })
	head(b, h, fur)
	pointyEars(b, h, 16, 20, fur, rgb(70, 50, 60))
	-- museau pointu blanc
	local mz = front(h.X, h.Y, h.Z, 25, 20, 21, 0, h.Y - 6)
	b.Egg(0, h.Y - 6, mz - 2, 26, 16, 16, cream, M.Fabric)
	b.Ball(0, h.Y - 4, mz + 6, 5, INK, M.SmoothPlastic)
	face(b, h, 5.5, 11, 4)
	-- grosse queue touffue au bout blanc
	b.EggR(CFrame.new(-26, 24, -18) * CFrame.Angles(0, 0.3, 0.9), 22, 50, 22, fur, M.Fabric)
	b.EggR(CFrame.new(-40, 44, -24) * CFrame.Angles(0, 0.3, 0.9), 16, 18, 16, cream, M.Fabric)
	b.Footprint(80, 56, 92)
end

R.HamsterPlush = function(b, _ctx)
	local fur = mainOf(b, rgb(255, 200, 140))
	local cream = rgb(255, 246, 232)
	b.Egg(0, 30, 0, 72, 58, 58, fur, M.Fabric)
	b.Egg(0, 26, 12, 50, 44, 40, cream, M.Fabric)
	local h: Head = { X = 0, Y = 46, Z = 4, W = 70, H = 46, D = 54 }
	for _, side in ipairs({ -1, 1 }) do
		b.Egg(side * 22, 40, 22, 24, 20, 16, cream, M.Fabric) -- bajoues
		b.Egg(side * 22, 70, 0, 16, 16, 8, fur, M.Fabric)
		b.Egg(side * 22, 70, 2, 9, 9, 6, PINK_IN, M.Fabric)
		b.Egg(side * 10, 8, 22, 12, 8, 12, PINK_IN, M.Fabric)
		b.Egg(side * 20, 30, 26, 10, 12, 8, PINK_IN, M.Fabric) -- menottes
	end
	face(b, h, 6.5, 12, 4)
	b.Ball(0, 45, 32, 5, rgb(255, 130, 160), M.SmoothPlastic)
	b.Footprint(72, 60, 76)
end

-- Roue du hamster (+ hamster dedans)
R.Hamster = function(b, _ctx)
	local frame = vivid(b, 1, rgb(120, 200, 255))
	local fur = rgb(255, 196, 130)
	b.Round(0, 0, 0, 80, 5, 50, 6, darken(frame, 0.2), M.SmoothPlastic)
	-- support derrière la roue ; la roue regarde la pièce (axe vers +z)
	for _, side in ipairs({ -1, 1 }) do
		b.Tube(side * 30, 5, -16, 0, 48, -16, 4, frame, M.SmoothPlastic)
	end
	local cy, r = 48, 36
	for index = 0, 15 do
		local a0, a1 = index / 16 * math.pi * 2, (index + 1) / 16 * math.pi * 2
		for _, z in ipairs({ -10, 10 }) do
			b.Tube(math.cos(a0) * r, cy + math.sin(a0) * r, z, math.cos(a1) * r, cy + math.sin(a1) * r, z, 3.5, frame, M.SmoothPlastic)
		end
		if index % 2 == 0 then
			b.Tube(math.cos(a0) * r, cy + math.sin(a0) * r, -10, math.cos(a0) * r, cy + math.sin(a0) * r, 10, 2, WHITE, M.Metal)
		end
	end
	for index = 0, 3 do
		local a = index / 4 * math.pi
		b.Tube(math.cos(a) * r, cy + math.sin(a) * r, -10, -math.cos(a) * r, cy - math.sin(a) * r, -10, 1.5, frame, M.SmoothPlastic)
	end
	b.CylZ(0, cy, -12, 8, 8, GOLD, M.Metal)
	-- hamster qui court en bas de la roue
	b.Egg(-4, 24, 0, 28, 20, 20, fur, M.Fabric)
	b.Egg(10, 28, 2, 18, 17, 18, fur, M.Fabric)
	b.Egg(12, 25, 9, 10, 9, 6, rgb(255, 246, 232), M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(9 + side * 4, 31, 10, 3.5, INK, M.SmoothPlastic)
		b.Ball(6 + side * 5, 37, 2, 7, PINK_IN, M.Fabric)
		b.Egg(-4 + side * 8, 15, 6, 6, 5, 6, PINK_IN, M.Fabric)
	end
	b.Footprint(80, 40, 86)
end

-- Grenouille
R.FroggyPlush = function(b, _ctx)
	local green = mainOf(b, rgb(120, 210, 110))
	local belly = rgb(236, 250, 200)
	b.Egg(0, 24, 0, 66, 42, 54, green, M.Fabric)
	b.Egg(0, 22, 14, 44, 30, 34, belly, M.Fabric)
	local h: Head = { X = 0, Y = 50, Z = 4, W = 70, H = 36, D = 50 }
	head(b, h, green)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 17, 68, 8, 22, green, M.Fabric)
		b.Ball(side * 17, 69, 17, 13, WHITE, M.SmoothPlastic)
		b.Ball(side * 17, 69, 22, 7, INK, M.SmoothPlastic)
		b.Ball(side * 15, 71, 25, 2.5, WHITE, M.SmoothPlastic)
		b.Egg(side * 26, 46, 22, 10, 6, 4, CHEEK, M.SmoothPlastic)
		b.Egg(side * 24, 6, 20, 22, 8, 22, green, M.Fabric) -- pattes palmées
		b.EggR(CFrame.new(side * 32, 24, 12) * CFrame.Angles(0.3, 0, side * 0.4), 12, 24, 12, green, M.Fabric)
	end
	-- grand sourire
	b.BoxR(CFrame.new(0, 45, 28.5) * CFrame.Angles(0, 0, 0), 22, 1.6, 1, INK)
	b.Footprint(72, 60, 80)
end

-- Dinosaures
local function dino(rex: boolean)
	return function(b: Builder, _ctx: any)
		local skin = mainOf(b, rgb(120, 200, 130))
		local belly = lighten(skin, 0.55)
		local spike = vivid(b, 2, rgb(255, 170, 90), skin)
		b.Egg(0, 30, 0, 52, 50, 50, skin, M.Fabric)
		b.Egg(0, 28, 14, 34, 38, 26, belly, M.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			b.Egg(side * 16, 8, 8, 18, 16, 26, skin, M.Fabric)
			b.EggR(CFrame.new(side * 20, 38, 18) * CFrame.Angles(0.9, 0, side * 0.2), 8, 14, 8, skin, M.Fabric) -- petits bras
		end
		-- tête allongée
		local h: Head = { X = 0, Y = rex and 66 or 62, Z = 8, W = 44, H = 36, D = 40 }
		head(b, h, skin)
		b.Egg(0, h.Y - 8, h.Z + 16, 32, 16, 26, skin, M.Fabric)
		b.Egg(0, h.Y - 12, h.Z + 18, 26, 6, 22, belly, M.Fabric)
		face(b, h, 6.5, 11, 6)
		for _, side in ipairs({ -1, 1 }) do
			b.Ball(side * 5, h.Y - 3, h.Z + 28, 3, darken(skin, 0.35), M.SmoothPlastic)
		end
		if rex then
			for index = 0, 4 do
				b.Part("WedgePart", CFrame.new(-9 + index * 4.5, h.Y - 16, h.Z + 27) * CFrame.Angles(math.pi, 0, 0), Vector3.new(2.4, 3, 1.5), WHITE, M.SmoothPlastic, "Dent")
			end
		end
		-- queue
		b.EggR(CFrame.new(0, 18, -30) * CFrame.Angles(-0.5, 0, 0), 26, 22, 30, skin, M.Fabric)
		b.EggR(CFrame.new(0, 10, -48) * CFrame.Angles(-0.4, 0, 0), 14, 12, 22, skin, M.Fabric)
		-- piquants dans le dos
		for index = 0, 5 do
			local y = 80 - index * 12
			local z = -4 - index * 7
			if index == 0 then
				y, z = h.Y + 16, h.Z - 10
			end
			b.Part("WedgePart", CFrame.new(0, y, z) * CFrame.Angles(0, 0, 0), Vector3.new(3, 9, 9), spike, M.Fabric, "Piquant")
		end
		b.Footprint(56, 76, 90)
	end
end
R.DinoPlush = dino(false)
R.TRexPlush = dino(true)

-- Oiseaux
local function bird(kind: string)
	return function(b: Builder, _ctx: any)
		local feather = mainOf(b, kind == "Penguin" and rgb(60, 70, 110) or rgb(255, 220, 90))
		local belly = kind == "Penguin" and WHITE or lighten(feather, 0.55)
		local beak = BEAK
		if kind == "Penguin" then
			b.Egg(0, 34, 0, 54, 64, 48, feather, M.Fabric)
			b.Egg(0, 32, 12, 38, 52, 28, belly, M.Fabric)
			local h: Head = { X = 0, Y = 66, Z = 2, W = 46, H = 38, D = 40 }
			head(b, h, feather)
			b.Egg(0, 62, 16, 30, 24, 16, WHITE, M.Fabric)
			face(b, { X = 0, Y = 66, Z = 4, W = 44, H = 36, D = 40 }, 5.5, 8, 2)
			b.Part("WedgePart", CFrame.new(0, 60, 23) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(8, 8, 4), beak, M.SmoothPlastic, "Bec")
			for _, side in ipairs({ -1, 1 }) do
				b.EggR(CFrame.new(side * 27, 36, 2) * CFrame.Angles(0, 0, side * 0.3), 8, 34, 16, feather, M.Fabric)
				b.Egg(side * 10, 3, 14, 14, 5, 20, beak, M.SmoothPlastic)
			end
			local scarf = vivid(b, 2, rgb(255, 110, 140), feather)
			b.Egg(0, 50, 2, 48, 8, 42, scarf, M.Fabric)
			b.Footprint(58, 50, 88)
			return
		end
		if kind == "Owl" then
			b.Egg(0, 34, 0, 58, 66, 50, feather, M.Fabric)
			b.Egg(0, 30, 12, 40, 44, 30, belly, M.Fabric)
			for _, side in ipairs({ -1, 1 }) do
				b.Egg(side * 12, 52, 20, 20, 20, 8, WHITE, M.SmoothPlastic)
				b.Ball(side * 12, 52, 24, 10, INK, M.SmoothPlastic)
				b.Ball(side * 10, 55, 27, 3.5, WHITE, M.SmoothPlastic)
				b.Part("WedgePart", CFrame.new(side * 18, 70, 2), Vector3.new(8, 12, 8), darken(feather, 0.2), M.Fabric, "Aigrette")
				b.EggR(CFrame.new(side * 28, 34, 0) * CFrame.Angles(0, 0, side * 0.2), 10, 38, 26, darken(feather, 0.15), M.Fabric)
				b.Egg(side * 9, 3, 12, 10, 5, 12, beak, M.SmoothPlastic)
			end
			b.Part("WedgePart", CFrame.new(0, 45, 25) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(6, 6, 6), beak, M.SmoothPlastic, "Bec")
			-- branche
			b.CylX(0, 0.5, 0, 6, 70, rgb(150, 100, 70), M.Wood)
			b.Footprint(70, 50, 76)
			return
		end
		-- poussin / caneton / canard de bain / perroquet
		local round = kind == "Chick" or kind == "Duck"
		b.Egg(0, 26, 0, 56, 46, 50, feather, M.SmoothPlastic)
		if kind == "Duck" then
			b.Egg(-4, 34, -16, 34, 24, 26, feather, M.SmoothPlastic)
		end
		local h: Head = { X = 0, Y = round and 60 or 62, Z = kind == "Duck" and 12 or 6, W = 40, H = 38, D = 38 }
		head(b, h, feather)
		face(b, h, 5.5, 8, 3, false, true)
		local bz = front(h.X, h.Y, h.Z, 20, 19, 19, 0, h.Y - 6)
		b.Egg(0, h.Y - 6, bz + 1, 16, 7, 12, beak, M.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			b.EggR(CFrame.new(side * 27, 30, 0) * CFrame.Angles(0, 0, side * 0.5), 8, 26, 24, darken(feather, 0.06), M.SmoothPlastic)
			if kind ~= "Duck" then
				b.Egg(side * 10, 3, 10, 10, 5, 14, beak, M.SmoothPlastic)
			end
		end
		if kind == "Chick" then
			for index = -1, 1 do
				b.EggR(CFrame.new(index * 3, h.Y + 19, h.Z) * CFrame.Angles(0, 0, index * 0.4), 3, 10, 3, feather, M.SmoothPlastic)
			end
		elseif kind == "Duck" then
			-- petite vague d'eau sous le canard de bain
			local water = b.Egg(0, 3, 0, 80, 8, 64, rgb(150, 210, 255), M.Glass)
			water.Transparency = 0.3
		end
		b.Footprint(62, 56, 82)
	end
end
R.Chick = bird("Chick")
R.Duckling = bird("Chick")
R.RubberDucky = bird("Duck")
R.PenguinPlush = bird("Penguin")
R.Penguin = bird("Penguin")
R.Owl = bird("Owl")

-- Perroquet sur son perchoir
R.Parrot = function(b, _ctx)
	local red = mainOf(b, rgb(240, 70, 80))
	local wing = vivid(b, 2, rgb(80, 150, 255), red)
	local yellow = vivid(b, 3, rgb(255, 210, 70), red)
	local wood = rgb(170, 120, 80)
	b.Cyl(0, 0, 0, 44, 5, darken(wood, 0.2), M.Wood)
	b.Cyl(0, 5, 0, 5, 58, wood, M.Wood)
	b.CylX(0, 62, 0, 5, 50, wood, M.Wood)
	b.Cyl(-22, 58, 0, 12, 4, rgb(220, 220, 230), M.Metal) -- gamelle
	-- oiseau
	b.EggR(CFrame.new(4, 76, 0) * CFrame.Angles(0, 0, -0.25), 22, 30, 22, red, M.SmoothPlastic)
	b.Ball(6, 92, 2, 18, red, M.SmoothPlastic)
	b.Egg(6, 90, 9, 12, 10, 6, WHITE, M.SmoothPlastic)
	b.Ball(10, 93, 10, 4, INK, M.SmoothPlastic)
	b.Ball(2, 93, 10, 4, INK, M.SmoothPlastic)
	b.EggR(CFrame.new(6, 86, 13) * CFrame.Angles(0.5, 0, 0), 6, 9, 7, rgb(60, 50, 60), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(4 + side * 11, 74, -2) * CFrame.Angles(0.2, 0, side * 0.3), 7, 24, 16, wing, M.SmoothPlastic)
	end
	b.EggR(CFrame.new(-2, 56, -6) * CFrame.Angles(0.35, 0, -0.1), 8, 26, 5, yellow, M.SmoothPlastic)
	b.Footprint(50, 44, 102)
end

R.Turtle = function(b, _ctx)
	local shell = vivid(b, 1, rgb(110, 190, 120))
	local skin = rgb(190, 230, 160)
	b.Egg(0, 18, 0, 64, 34, 58, shell, M.SmoothPlastic)
	b.Egg(0, 10, 0, 70, 10, 62, darken(shell, 0.2), M.SmoothPlastic)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		b.Egg(math.cos(a) * 16, 28, math.sin(a) * 14, 14, 6, 12, lighten(shell, 0.25), M.SmoothPlastic)
	end
	b.Egg(0, 33, 0, 16, 5, 14, lighten(shell, 0.25), M.SmoothPlastic)
	local h: Head = { X = 0, Y = 18, Z = 36, W = 24, H = 22, D = 22 }
	head(b, h, skin)
	face(b, h, 4, 5, 2)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Egg(sx * 26, 5, sz * 20, 14, 9, 16, skin, M.SmoothPlastic)
		end
	end
	b.Footprint(70, 72, 36)
end

R.Hedgehog = function(b, _ctx)
	local spikes = mainOf(b, rgb(150, 100, 80))
	local face_ = rgb(255, 226, 196)
	b.Egg(0, 24, -4, 64, 44, 58, spikes, M.Fabric)
	-- piquants (petites pentes tout autour du dos)
	for row = 0, 2 do
		for index = 0, 6 do
			local a = (index / 6 - 0.5) * 2.4
			local y = 30 + row * 8
			local z = -4 - row * 8
			b.Part("WedgePart", CFrame.new(math.sin(a) * (26 - row * 6), y + math.cos(a) * 8, z) * CFrame.Angles(-0.6, 0, -a * 0.8), Vector3.new(6, 12, 6), darken(spikes, 0.2), M.Fabric, "Piquant")
		end
	end
	local h: Head = { X = 0, Y = 22, Z = 22, W = 34, H = 30, D = 30 }
	head(b, h, face_)
	b.Egg(0, 18, 36, 12, 9, 12, face_, M.Fabric)
	b.Ball(0, 20, 42, 5, INK, M.SmoothPlastic)
	face(b, h, 4.5, 8, 3)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 12, 36, 20, 9, face_, M.Fabric)
		b.Egg(side * 14, 4, 14, 10, 7, 12, face_, M.Fabric)
	end
	b.Footprint(66, 64, 56)
end

R.UnicornPlush = function(b, _ctx)
	local white = rgb(252, 250, 255)
	local mane = { vivid(b, 1, rgb(255, 150, 200)), vivid(b, 2, rgb(170, 150, 255)), vivid(b, 3, rgb(140, 220, 255)) }
	local h = sitting(b, { Color = white, Belly = rgb(255, 240, 250), BW = 54, BH = 46, BD = 48, HeadW = 46, HeadH = 42, HeadD = 44 })
	head(b, h, white)
	b.Egg(0, h.Y - 8, h.Z + 14, 26, 18, 22, rgb(255, 232, 244), M.Fabric)
	face(b, h, 6, 10, 4)
	pointyEars(b, h, 12, 14, white, PINK_IN)
	-- corne dorée (cylindres de plus en plus fins)
	for index = 0, 3 do
		b.Cyl(0, h.Y + h.H * 0.42 + index * 5, h.Z + 6 - index * 0.5, 9 - index * 2, 5.2, GOLD, M.Metal)
	end
	-- crinière arc-en-ciel
	for index = 0, 5 do
		b.Ball(-4 + (index % 2) * 3, h.Y + 18 - index * 8, h.Z - 16 - index * 2, 14, mane[index % 3 + 1], M.Fabric)
	end
	tail(b, { { 0, 14, -22 }, { -8, 22, -32 }, { -4, 34, -36 } }, 12, mane[1], mane[2])
	b.Footprint(62, 60, 100)
end

R.WhalePlush = function(b, _ctx)
	local blue = mainOf(b, rgb(120, 170, 255))
	local belly = rgb(236, 244, 255)
	b.Egg(0, 30, 0, 90, 56, 58, blue, M.Fabric)
	b.Egg(8, 20, 8, 70, 30, 48, belly, M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(-50, 42, side * 10) * CFrame.Angles(side * 0.6, 0, 0.5), 10, 12, 24, blue, M.Fabric)
		b.EggR(CFrame.new(8, 16, side * 30) * CFrame.Angles(0, 0, 0.5), 20, 8, 12, blue, M.Fabric)
		b.Ball(26, 38, side * 24, 6, INK, M.SmoothPlastic)
		b.Ball(27, 40, side * 26.5, 2, WHITE, M.SmoothPlastic)
		b.Egg(30, 30, side * 24, 7, 4, 4, CHEEK, M.SmoothPlastic)
	end
	-- jet d'eau
	b.Tube(10, 58, 0, 10, 70, 0, 3, rgb(170, 220, 255), M.Glass)
	for _, dx in ipairs({ -5, 5 }) do
		b.Ball(10 + dx, 72, 0, 7, rgb(190, 230, 255), M.Glass)
	end
	b.Footprint(100, 62, 76)
end

R.OctopusPlush = function(b, _ctx)
	local pink = mainOf(b, rgb(255, 140, 170))
	b.Egg(0, 52, -2, 62, 60, 56, pink, M.Fabric)
	for index = 0, 7 do
		local a = index / 8 * math.pi * 2 + 0.2
		local x, z = math.cos(a), math.sin(a)
		b.Tube(x * 14, 26, z * 12, x * 30, 10, z * 26, 13, pink, M.Fabric)
		b.Tube(x * 30, 10, z * 26, x * 38, 7, z * 36, 10, pink, M.Fabric)
		b.Ball(x * 38, 8, z * 36, 11, lighten(pink, 0.25), M.Fabric)
	end
	local h: Head = { X = 0, Y = 46, Z = -2, W = 62, H = 60, D = 56 }
	face(b, h, 7, 11, 0)
	b.Egg(0, 36, front(0, 46, -2, 31, 30, 28, 0, 36) - 1, 8, 5, 3, rgb(200, 80, 110), M.SmoothPlastic)
	b.Footprint(80, 78, 84)
end

R.NinjaPlush = function(b, _ctx)
	local suit = b.Map(rgb(70, 72, 104))
	local skin = rgb(255, 226, 200)
	local band = vivid(b, 2, rgb(240, 70, 80), suit)
	local h = sitting(b, { Color = suit, Belly = darken(suit, 0.15), BW = 54, BH = 44, BD = 46, HeadW = 50, HeadH = 46, HeadD = 44 })
	head(b, h, suit)
	-- fente des yeux (visage) + bandeau et ses rubans
	local fz = front(h.X, h.Y, h.Z, 25, 23, 22, 0, h.Y + 1)
	b.Egg(0, h.Y + 1, fz - 4, 38, 12, 12, skin, M.Fabric)
	face(b, h, 5.5, 9, 1, false, false)
	b.Egg(0, h.Y + 12, h.Z, h.W + 2, 6, h.D + 2, band, M.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		b.EggR(CFrame.new(side * 6, h.Y + 8, h.Z - 26) * CFrame.Angles(0.4, 0, side * 0.5), 6, 18, 3, band, M.Fabric)
	end
	b.Egg(0, 30, 2, 58, 6, 50, band, M.Fabric) -- ceinture
	b.Footprint(62, 56, 96)
end

R.PiggyBank = function(b, _ctx)
	local pink = mainOf(b, rgb(255, 170, 200))
	b.Egg(0, 38, 0, 84, 62, 62, pink, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 22, 0, sz * 16, 14, 14, darken(pink, 0.08), M.SmoothPlastic)
		end
		b.Part("WedgePart", CFrame.new(28, 66, sx * 14) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(12, 12, 8), darken(pink, 0.1), M.SmoothPlastic, "Oreille")
		b.Ball(34, 50, sx * 12, 6, INK, M.SmoothPlastic)
		b.Ball(35, 52, sx * 13.5, 2, WHITE, M.SmoothPlastic)
	end
	b.CylX(44, 40, 0, 20, 8, lighten(pink, 0.15), M.SmoothPlastic)
	for _, dz in ipairs({ -4, 4 }) do
		b.CylX(48.5, 40, dz, 4, 1, darken(pink, 0.35), M.SmoothPlastic)
	end
	b.Box(-4, 68, 0, 18, 2, 3, INK) -- fente à pièces
	b.Cyl(-2, 69, 0, 9, 2, GOLD, M.Metal)
	tail(b, { { -42, 42, 0 }, { -48, 48, 4 }, { -46, 54, -2 } }, 4, pink)
	b.Footprint(96, 64, 72)
end

-- Bébé dragon
R.Dragon = function(b, _ctx)
	local scale = mainOf(b, rgb(150, 110, 230))
	local belly = rgb(255, 226, 170)
	local wing = vivid(b, 2, rgb(255, 150, 200), scale)
	local h = sitting(b, { Color = scale, Belly = belly, BW = 52, BH = 48, BD = 46, HeadW = 46, HeadH = 40, HeadD = 44 })
	head(b, h, scale)
	b.Egg(0, h.Y - 8, h.Z + 14, 28, 18, 24, scale, M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		b.Ball(side * 5, h.Y - 5, h.Z + 26, 3, INK, M.SmoothPlastic)
		-- cornes
		b.Tube(side * 10, h.Y + 16, h.Z - 6, side * 14, h.Y + 28, h.Z - 12, 5, belly, M.SmoothPlastic)
		-- ailes (voiles triangulaires)
		local cf = CFrame.new(side * 26, 52, -16) * CFrame.Angles(0.2, side * -0.6, side * -0.5)
		b.Part("WedgePart", cf, Vector3.new(2, 30, 26), wing, M.SmoothPlastic, "Aile")
		b.Tube(side * 18, 46, -12, side * 34, 66, -24, 3, scale, M.SmoothPlastic)
	end
	face(b, h, 6.5, 10, 6)
	-- queue à pointe
	tail(b, { { 0, 12, -20 }, { 16, 8, -34 }, { 32, 10, -32 } }, 12, scale)
	b.Part("WedgePart", CFrame.new(38, 12, -30) * CFrame.Angles(0, -math.pi / 2, -math.pi / 2), Vector3.new(10, 10, 6), wing, M.SmoothPlastic, "Pointe")
	-- petites plaques dans le dos
	for index = 0, 3 do
		b.Part("WedgePart", CFrame.new(0, 60 - index * 11, -18 - index * 3), Vector3.new(2.5, 7, 7), wing, M.SmoothPlastic, "Plaque")
	end
	b.Footprint(76, 60, 100)
end

-- Bocaux (poisson rouge, axolotl)
R.Goldfish = function(b, _ctx)
	local fish = vivid(b, 1, rgb(255, 140, 50))
	b.Cyl(0, 0, 0, 56, 6, rgb(200, 170, 250), M.SmoothPlastic)
	local bowl = b.Ball(0, 42, 0, 78, GLASS, M.Glass)
	bowl.Transparency = 0.8
	bowl.CastShadow = false
	local water = b.Egg(0, 36, 0, 70, 50, 70, rgb(160, 214, 255), M.Glass)
	water.Transparency = 0.68
	water.CastShadow = false
	b.Egg(0, 10, 0, 50, 8, 50, rgb(250, 230, 180), M.Sand)
	b.EggR(CFrame.new(-14, 22, -6) * CFrame.Angles(0, 0, 0.1), 4, 18, 4, rgb(90, 200, 120), M.SmoothPlastic)
	-- (v11) un vrai poisson rouge (double queue voilée) qui tourne dans le
	-- bocal, monte, descend, fait du sur-place ; bulles
	local goldfish = House3DFish.Fish(b, "Goldfish", 4, 42, 4, 24, 1)
	-- (teinte de la palette de l'objet sur le corps, comme avant)
	goldfish.Body.Color = fish
	local bubbles = {}
	for index = 0, 2 do
		local bubble = b.Ball(18, 20 + index * 12, 8, 3 + index * 0.5, WHITE, M.Glass)
		bubble.Transparency = 0.4
		table.insert(bubbles, bubble)
	end
	House3DFish.Tank(b, water, { goldfish }, { Kind = "Bowl", Bubbles = bubbles, Bubbler = Vector3.new(18, 16, 8), RefCenter = Vector3.new(0, 36, 0), RefSize = Vector3.new(70, 50, 70) })
	b.Footprint(80, 80, 82)
end

R.Axolotl = function(b, _ctx)
	local pink = vivid(b, 1, rgb(255, 170, 200))
	local frame = rgb(90, 80, 110)
	b.Round(0, 0, 0, 96, 8, 54, 4, frame, M.SmoothPlastic)
	local glass = b.Box(0, 8, 0, 94, 60, 52, GLASS, M.Glass)
	glass.Transparency = 0.7
	glass.CastShadow = false
	local water = b.Box(0, 8, 0, 90, 52, 48, rgb(120, 200, 230), M.Glass)
	water.Transparency = 0.5
	water.CastShadow = false
	b.Box(0, 8, 0, 90, 5, 48, rgb(240, 220, 180), M.Sand)
	b.Box(0, 68, 0, 98, 4, 56, frame, M.SmoothPlastic)
	for _, x in ipairs({ -30, 32 }) do
		for index = 0, 2 do
			b.EggR(CFrame.new(x + index * 5 - 5, 26, -12) * CFrame.Angles(0, 0, (index - 1) * 0.25), 4, 30, 4, rgb(90, 190, 120), M.SmoothPlastic)
		end
	end
	-- axolotl
	b.Egg(0, 24, 6, 36, 14, 16, pink, M.SmoothPlastic)
	b.Egg(18, 28, 6, 18, 16, 18, pink, M.SmoothPlastic)
	b.EggR(CFrame.new(-22, 24, 6) * CFrame.Angles(0, 0, 0.2), 16, 8, 3, lighten(pink, 0.2), M.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		for index = 0, 2 do
			b.EggR(CFrame.new(14, 34 + index * 2, 6 + side * (7 + index)) * CFrame.Angles(side * 0.5, 0, 0.4 - index * 0.4), 3, 10, 3, rgb(255, 110, 150), M.SmoothPlastic)
		end
		b.Ball(24, 30, 6 + side * 5, 3, INK, M.SmoothPlastic)
		b.Egg(4 + side * 8, 18, 6 + side * 7, 6, 4, 6, pink, M.SmoothPlastic)
	end
	b.Footprint(98, 56, 72)
end

----------------------------------------------------------------------
-- v9.8 (GARDEN98) 🐾 ANIMAUX RÉALISTES ARTICULÉS
-- Les vrais animaux (catégorie Pets) ne sont plus des peluches assises :
-- de vraies proportions (corps allongé sur 4 pattes, cou, museau, queue),
-- des couleurs de pelage naturelles (golden retriever, chaton calico, chat
-- tigré gris, renard roux aux chaussettes noires, lapin blanc, hérisson,
-- tortue, poussin, caneton, manchot, chouette, bébé dragon), des yeux
-- brillants (globe sombre, iris des chats / de la chouette, reflet).
-- Chaque pièce appartient à une ARTICULATION (nom "J_<articulation>_...") et
-- chaque articulation a un repère invisible "Joint_<articulation>" (pivot) :
-- Client/World/PetRoam anime ces modèles (marche, trot, sauts, dandinement,
-- vol, assis, couché, sieste) sans rien reconstruire. Au repos (maison 2D en
-- 3D, animalerie, pièce), l'animal est simplement debout.
-- Repère des recettes : 100 unités = la boîte 2D, +z = devant.
----------------------------------------------------------------------

-- Nomme une pièce d'après son articulation
local function jn(part: BasePart, joint: string, name: string): BasePart
	part.Name = "J_" .. joint .. "_" .. name
	return part
end

-- Pivot invisible d'une articulation
local function marker(b: Builder, joint: string, x: number, y: number, z: number)
	local p = b.Ball(x, y, z, 1, WHITE, M.SmoothPlastic)
	p.Transparency = 1
	p.CastShadow = false
	p.Name = "Joint_" .. joint
end

-- Œil réaliste : globe sombre brillant (+ iris coloré et pupille), reflet
local function realEye(b: Builder, joint: string, x: number, y: number, z: number, size: number, iris: Color3?, slit: boolean?)
	local globe = b.Ball(x, y, z, size, iris or rgb(34, 24, 20), M.SmoothPlastic)
	globe.Reflectance = 0.15
	jn(globe, joint, "Eye")
	if iris then
		local pupil = b.EggR(CFrame.new(x, y, z + size * 0.36), slit and size * 0.22 or size * 0.55, size * (slit and 0.8 or 0.55), size * 0.3, rgb(16, 12, 12), M.SmoothPlastic)
		jn(pupil, joint, "Eye")
	end
	local shine = b.Ball(x + size * 0.18, y + size * 0.2, z + size * 0.4, size * 0.26, WHITE, M.SmoothPlastic)
	jn(shine, joint, "Eye")
end

export type QuadSpec = {
	L: number, W: number, BH: number, H: number, LegW: number,
	Head: { number }, -- largeur, hauteur, profondeur du crâne
	Snout: { number }, -- longueur, largeur, hauteur du museau
	Neck: number, -- longueur du cou (vers l'avant/le haut)
	Main: Color3, Belly: Color3, Legs: Color3?, Paws: Color3?, Muzzle: Color3?, Nose: Color3,
	Ears: string, EarColor: Color3?, EarIn: Color3?, EarSize: number,
	Tail: string, TailColor: Color3?, TailTip: Color3?, TailLen: number,
	Eye: number, Iris: Color3?, Slit: boolean?,
	Patches: { any }?, Tongue: boolean?, Whiskers: boolean?,
}

-- Quadrupède (chien, chat, renard, dragon...) : renvoie le centre de la tête
local function quad(b: Builder, s: QuadSpec)
	local L, W, BH, H = s.L, s.W, s.BH, s.H
	local bodyY = H - BH / 2
	local legColor = s.Legs or s.Main
	local paws = s.Paws or legColor
	-- tronc : dos, poitrail, arrière-train, ventre clair
	jn(b.Egg(0, bodyY, -L * 0.04, W, BH, L * 0.92, s.Main, M.Fabric), "Body", "Torso")
	jn(b.Egg(0, bodyY + BH * 0.02, L * 0.3, W * 1.02, BH * 1.02, L * 0.42, s.Main, M.Fabric), "Body", "Chest")
	jn(b.Egg(0, bodyY + BH * 0.04, -L * 0.33, W * 0.98, BH * 0.98, L * 0.38, s.Main, M.Fabric), "Body", "Hips")
	jn(b.Egg(0, bodyY - BH * 0.2, L * 0.04, W * 0.78, BH * 0.62, L * 0.7, s.Belly, M.Fabric), "Body", "Belly")
	for index, patch in ipairs(s.Patches or {}) do
		jn(b.Egg(patch[1], patch[2], patch[3], patch[4], patch[5], patch[6], patch[7], M.Fabric), "Body", "Patch" .. index)
	end
	-- pattes : épaule / hanche = pivot ; cuisse, jambe, patte
	local legTop = bodyY - BH * 0.12
	for _, spot in ipairs({ { "LegFL", -1, 1 }, { "LegFR", 1, 1 }, { "LegBL", -1, -1 }, { "LegBR", 1, -1 } }) do
		local joint, sx, sz = spot[1], spot[2], spot[3]
		local x, z = sx * W * 0.3, sz * L * 0.33
		marker(b, joint, x, legTop, z)
		local thigh = sz < 0 and 1.35 or 1.1
		jn(b.Egg(x, legTop - legTop * 0.2, z - sz * s.LegW * 0.1, s.LegW * thigh, legTop * 0.62, s.LegW * thigh * 1.15, sz < 0 and s.Main or legColor, M.Fabric), joint, "Upper")
		jn(b.Tube(x, legTop * 0.6, z, x, s.LegW * 0.45, z + s.LegW * 0.08, s.LegW * 0.74, legColor, M.Fabric), joint, "Lower")
		jn(b.Egg(x, s.LegW * 0.28, z + s.LegW * 0.22, s.LegW * 0.78, s.LegW * 0.56, s.LegW * 1.05, paws, M.Fabric), joint, "Paw")
	end
	-- cou + tête (pivot à la base du cou)
	local neckZ = L * 0.44
	local neckY = bodyY + BH * 0.18
	marker(b, "Head", 0, neckY, neckZ)
	local hw, hh, hd = s.Head[1], s.Head[2], s.Head[3]
	local hx, hy, hz = 0, neckY + s.Neck * 0.75 + hh * 0.2, neckZ + s.Neck * 0.55 + hd * 0.25
	jn(b.Tube(0, neckY - BH * 0.05, neckZ - L * 0.05, hx, hy - hh * 0.2, hz - hd * 0.25, math.min(W, hw) * 0.72, s.Main, M.Fabric), "Head", "Neck")
	jn(b.Egg(hx, hy, hz, hw, hh, hd, s.Main, M.Fabric), "Head", "Skull")
	local sl, sw, sh = s.Snout[1], s.Snout[2], s.Snout[3]
	local muzzle = s.Muzzle or s.Main
	local sy, sz = hy - hh * 0.2, hz + hd * 0.34 + sl * 0.32
	jn(b.Egg(hx, sy, sz, sw, sh, sl + hd * 0.3, muzzle, M.Fabric), "Head", "Snout")
	jn(b.Egg(hx, sy - sh * 0.28, sz - sl * 0.08, sw * 0.8, sh * 0.5, sl + hd * 0.2, s.Belly, M.Fabric), "Head", "Chin")
	local nose = b.EggR(CFrame.new(hx, sy + sh * 0.26, sz + (sl + hd * 0.3) * 0.46), sw * 0.42, sh * 0.34, sh * 0.32, s.Nose, M.SmoothPlastic)
	nose.Reflectance = 0.1
	jn(nose, "Head", "Nose")
	if s.Tongue then
		jn(b.EggR(CFrame.new(hx, sy - sh * 0.46, sz + sl * 0.28) * CFrame.Angles(0.5, 0, 0), sw * 0.34, sh * 0.5, sh * 0.16, rgb(236, 110, 130), M.SmoothPlastic), "Head", "Tongue")
	end
	if s.Whiskers then
		for _, side in ipairs({ -1, 1 }) do
			for _, dy in ipairs({ -1, 1 }) do
				jn(b.BoxR(CFrame.new(hx + side * sw * 0.62, sy + dy * sh * 0.08, sz + sl * 0.2) * CFrame.Angles(0, side * 0.35, dy * side * 0.08), sw * 0.8, 0.5, 0.5, rgb(250, 248, 244)), "Head", "Whisker")
			end
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		realEye(b, "Head", hx + side * hw * 0.24, hy + hh * 0.08, hz + hd * 0.4, s.Eye, s.Iris, s.Slit)
	end
	-- oreilles
	local earColor = s.EarColor or s.Main
	local es = s.EarSize
	for _, side in ipairs({ -1, 1 }) do
		local ex, ey, ez = hx + side * hw * 0.3, hy + hh * 0.42, hz - hd * 0.1
		if s.Ears == "Floppy" then
			jn(b.EggR(CFrame.new(hx + side * hw * 0.48, hy + hh * 0.05, hz - hd * 0.05) * CFrame.Angles(0, 0, side * 0.25), es * 0.38, es, es * 0.24, earColor, M.Fabric), "Head", "Ear")
		elseif s.Ears == "Pointy" then
			local cf = CFrame.new(ex, ey + es * 0.4, ez) * CFrame.Angles(0, 0, -side * 0.22)
			jn(b.Part("WedgePart", cf * CFrame.new(0, 0, -es * 0.12), Vector3.new(es * 0.62, es, es * 0.24), earColor, M.Fabric, "Oreille"), "Head", "Ear")
			jn(b.Part("WedgePart", cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -es * 0.12), Vector3.new(es * 0.62, es, es * 0.24), earColor, M.Fabric, "Oreille"), "Head", "Ear")
			if s.EarIn then
				jn(b.Part("WedgePart", cf * CFrame.new(0, -es * 0.1, es * 0.13) * CFrame.Angles(0, math.pi, 0), Vector3.new(es * 0.36, es * 0.66, 0.6), s.EarIn, M.Fabric, "Oreille"), "Head", "EarIn")
			end
		elseif s.Ears == "Long" then
			local cf = CFrame.new(hx + side * hw * 0.18, hy + hh * 0.4 + es * 0.44, hz - hd * 0.12) * CFrame.Angles(-0.18, 0, -side * 0.12)
			jn(b.EggR(cf, hw * 0.28, es, hw * 0.14, earColor, M.Fabric), "Head", "Ear")
			if s.EarIn then
				jn(b.EggR(cf * CFrame.new(0, -es * 0.02, hw * 0.05), hw * 0.15, es * 0.78, hw * 0.06, s.EarIn, M.Fabric), "Head", "EarIn")
			end
		elseif s.Ears == "Round" then
			jn(b.Egg(ex, ey, ez, es, es, es * 0.5, earColor, M.Fabric), "Head", "Ear")
		end
	end
	-- queue (pivot à la base)
	local tailY, tailZ = bodyY + BH * 0.12, -L * 0.5
	marker(b, "Tail", 0, tailY, tailZ)
	local tc = s.TailColor or s.Main
	local tl = s.TailLen
	if s.Tail == "Wag" then
		jn(b.EggR(CFrame.new(0, tailY + tl * 0.22, tailZ - tl * 0.28) * CFrame.Angles(-0.7, 0, 0), W * 0.3, tl * 0.62, W * 0.3, tc, M.Fabric), "Tail", "Base")
		jn(b.EggR(CFrame.new(0, tailY + tl * 0.62, tailZ - tl * 0.62) * CFrame.Angles(-0.35, 0, 0), W * 0.26, tl * 0.46, W * 0.26, tc, M.Fabric), "Tail", "Tip")
		jn(b.Ball(0, tailY + tl * 0.8, tailZ - tl * 0.72, W * 0.15, s.TailTip or tc, M.Fabric), "Tail", "End")
	elseif s.Tail == "Cat" then
		jn(b.Tube(0, tailY, tailZ, 0, tailY + tl * 0.35, tailZ - tl * 0.42, W * 0.24, tc, M.Fabric), "Tail", "Base")
		jn(b.Tube(0, tailY + tl * 0.35, tailZ - tl * 0.42, 0, tailY + tl * 0.85, tailZ - tl * 0.5, W * 0.22, tc, M.Fabric), "Tail", "Mid")
		jn(b.Tube(0, tailY + tl * 0.85, tailZ - tl * 0.5, 0, tailY + tl * 1.05, tailZ - tl * 0.4, W * 0.2, s.TailTip or tc, M.Fabric), "Tail", "Tip")
	elseif s.Tail == "Bushy" then
		jn(b.EggR(CFrame.new(0, tailY - tl * 0.05, tailZ - tl * 0.42) * CFrame.Angles(-0.9, 0, 0), W * 0.52, tl * 0.9, W * 0.52, tc, M.Fabric), "Tail", "Brush")
		jn(b.EggR(CFrame.new(0, tailY - tl * 0.3, tailZ - tl * 0.8) * CFrame.Angles(-1.1, 0, 0), W * 0.38, tl * 0.32, W * 0.38, s.TailTip or tc, M.Fabric), "Tail", "Tip")
	elseif s.Tail == "Pom" then
		jn(b.Ball(0, tailY, tailZ - W * 0.08, W * 0.42, s.TailTip or WHITE, M.Fabric), "Tail", "Pom")
	elseif s.Tail == "Spiky" then
		jn(b.Tube(0, tailY, tailZ, 0, tailY - tl * 0.25, tailZ - tl * 0.6, W * 0.34, tc, M.SmoothPlastic), "Tail", "Base")
		jn(b.Tube(0, tailY - tl * 0.25, tailZ - tl * 0.6, tl * 0.18, tailY - tl * 0.38, tailZ - tl * 1.05, W * 0.2, tc, M.SmoothPlastic), "Tail", "Tip")
		jn(b.Part("WedgePart", CFrame.new(tl * 0.2, tailY - tl * 0.38, tailZ - tl * 1.12) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(W * 0.1, W * 0.36, W * 0.36), s.TailTip or tc, M.SmoothPlastic, "Pointe"), "Tail", "Spade")
	elseif s.Tail == "Stub" then
		jn(b.EggR(CFrame.new(0, tailY - BH * 0.1, tailZ - W * 0.05) * CFrame.Angles(-0.6, 0, 0), W * 0.2, W * 0.34, W * 0.2, tc, M.SmoothPlastic), "Tail", "Stub")
	end
	return hx, hy, hz
end

-- Oiseau (poussin, caneton, manchot, chouette) : pattes LegL / LegR, ailes WingL / WingR
local function realBird(b: Builder, kind: string)
	local feather, belly, bill, feet, eyeSize, iris
	local bodyW, bodyH, bodyD, bodyY, headD, headY, headZ, legH
	if kind == "Penguin" then
		feather, belly, bill, feet = rgb(34, 38, 48), rgb(246, 244, 238), rgb(236, 120, 50), rgb(236, 130, 60)
		bodyW, bodyH, bodyD, bodyY = 44, 68, 40, 42
		headD, headY, headZ, legH, eyeSize = 34, 84, 4, 8, 4.4
	elseif kind == "Owl" then
		feather, belly, bill, feet = rgb(150, 110, 72), rgb(226, 206, 170), rgb(90, 80, 70), rgb(200, 170, 100)
		bodyW, bodyH, bodyD, bodyY = 50, 58, 44, 38
		headD, headY, headZ, legH, eyeSize, iris = 46, 76, 2, 10, 12, rgb(250, 170, 40)
	elseif kind == "Duckling" then
		feather, belly, bill, feet = rgb(250, 214, 80), rgb(255, 234, 150), rgb(240, 150, 40), rgb(240, 150, 40)
		bodyW, bodyH, bodyD, bodyY = 46, 40, 56, 30
		headD, headY, headZ, legH, eyeSize = 34, 58, 16, 12, 4.8
	else -- Chick
		feather, belly, bill, feet = rgb(255, 222, 92), rgb(255, 238, 160), rgb(250, 160, 50), rgb(250, 160, 60)
		bodyW, bodyH, bodyD, bodyY = 48, 44, 50, 32
		headD, headY, headZ, legH, eyeSize = 36, 62, 10, 14, 5
	end
	jn(b.Egg(0, bodyY, 0, bodyW, bodyH, bodyD, feather, M.Fabric), "Body", "Body")
	jn(b.Egg(0, bodyY - bodyH * 0.06, bodyD * 0.2, bodyW * 0.7, bodyH * 0.78, bodyD * 0.62, belly, M.Fabric), "Body", "Belly")
	if kind == "Owl" then
		for k = 0, 4 do
			jn(b.Egg((k % 2 - 0.5) * 10, bodyY + 8 - k * 7, bodyD * 0.48, 5, 3, 1.6, rgb(160, 120, 80), M.Fabric), "Body", "Speckle")
		end
	elseif kind == "Duckling" then
		jn(b.EggR(CFrame.new(0, bodyY + 6, -bodyD * 0.45) * CFrame.Angles(0.6, 0, 0), 14, 16, 10, feather, M.Fabric), "Body", "TailTuft")
	end
	-- pattes
	for _, side in ipairs({ -1, 1 }) do
		local joint = side < 0 and "LegL" or "LegR"
		local x = side * bodyW * 0.2
		marker(b, joint, x, legH + 4, 0)
		jn(b.Tube(x, legH + 4, 0, x, 2, bodyD * 0.04, kind == "Owl" and 5 or 3, feet, M.SmoothPlastic), joint, "Shin")
		jn(b.Egg(x, 1.6, bodyD * 0.12, kind == "Penguin" and 14 or 10, 3, kind == "Penguin" and 18 or 13, feet, M.SmoothPlastic), joint, "Foot")
	end
	-- ailes / ailerons
	for _, side in ipairs({ -1, 1 }) do
		local joint = side < 0 and "WingL" or "WingR"
		local x = side * bodyW * 0.46
		marker(b, joint, x, bodyY + bodyH * 0.22, bodyD * 0.05)
		local wing = kind == "Penguin" and feather or feather:Lerp(rgb(0, 0, 0), kind == "Owl" and 0.15 or 0.05)
		jn(b.EggR(CFrame.new(x, bodyY - bodyH * 0.02, -bodyD * 0.05) * CFrame.Angles(0.25, 0, side * 0.12), bodyW * 0.18, bodyH * (kind == "Penguin" and 0.66 or 0.56), bodyD * 0.62, wing, M.Fabric), joint, "Wing")
	end
	-- tête
	marker(b, "Head", 0, headY - headD * 0.35, headZ)
	jn(b.Ball(0, headY, headZ, headD, feather, M.Fabric), "Head", "Head")
	if kind == "Penguin" then
		jn(b.Egg(0, headY - 4, headZ + 8, headD * 0.72, headD * 0.6, headD * 0.5, belly, M.Fabric), "Head", "Face")
		for _, side in ipairs({ -1, 1 }) do
			jn(b.Egg(side * headD * 0.36, headY - 10, headZ + 2, 8, 6, 12, rgb(250, 200, 70), M.Fabric), "Head", "Patch")
		end
	elseif kind == "Owl" then
		for _, side in ipairs({ -1, 1 }) do
			jn(b.Egg(side * headD * 0.2, headY, headZ + headD * 0.36, headD * 0.44, headD * 0.46, 6, belly, M.Fabric), "Head", "Disc")
			jn(b.Part("WedgePart", CFrame.new(side * headD * 0.32, headY + headD * 0.5, headZ - 2) * CFrame.Angles(0, 0, -side * 0.3), Vector3.new(8, 13, 7), feather:Lerp(rgb(0, 0, 0), 0.2), M.Fabric, "Aigrette"), "Head", "Tuft")
		end
	end
	local eyeZ = headZ + headD * (kind == "Owl" and 0.42 or 0.36)
	local eyeX = headD * (kind == "Owl" and 0.2 or 0.26)
	for _, side in ipairs({ -1, 1 }) do
		realEye(b, "Head", side * eyeX, headY + (kind == "Owl" and 0 or 3), eyeZ, eyeSize, iris, false)
	end
	if kind == "Duckling" then
		jn(b.Egg(0, headY - 4, headZ + headD * 0.5 + 5, 13, 5, 16, bill, M.SmoothPlastic), "Head", "Bill")
	elseif kind == "Owl" then
		jn(b.Part("WedgePart", CFrame.new(0, headY - 6, headZ + headD * 0.5) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(5, 5, 7), bill, M.SmoothPlastic, "Bec"), "Head", "Beak")
	else
		jn(b.Part("WedgePart", CFrame.new(0, headY - 3, headZ + headD * 0.5 + (kind == "Penguin" and 5 or 2)) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(7, kind == "Penguin" and 12 or 7, 5), bill, M.SmoothPlastic, "Bec"), "Head", "Beak")
	end
	if kind == "Chick" then
		for index = -1, 1 do
			jn(b.EggR(CFrame.new(index * 3, headY + headD * 0.5, headZ) * CFrame.Angles(0, 0, index * 0.4), 3, 9, 3, feather, M.Fabric), "Head", "Fluff")
		end
	end
	-- (queue fixe au corps : pas d'articulation, mais un pivot pour l'animation)
	marker(b, "Tail", 0, bodyY, -bodyD * 0.45)
end

-- Espèces : tables de proportions (unités de la boîte 2D) et pelages naturels
local REAL: { [string]: (b: Builder) -> () } = {}

REAL.Puppy = function(b)
	-- golden retriever : doré, museau et poitrail plus clairs, oreilles tombantes
	local gold = rgb(212, 158, 88)
	local cream = rgb(240, 214, 170)
	quad(b, {
		L = 60, W = 28, BH = 28, H = 56, LegW = 12, Head = { 28, 26, 30 }, Snout = { 20, 16, 14 }, Neck = 16,
		Main = gold, Belly = cream, Legs = gold, Muzzle = rgb(226, 182, 120), Nose = rgb(40, 30, 28),
		Ears = "Floppy", EarColor = rgb(184, 124, 64), EarSize = 20, Tail = "Wag", TailColor = gold, TailTip = cream, TailLen = 34,
		Eye = 5.4, Tongue = true,
	})
	-- collier + médaille
	jn(b.Egg(0, 62, 30, 22, 5, 20, rgb(214, 50, 70), M.Fabric), "Head", "Collar")
	jn(b.Ball(0, 58, 40, 5, GOLD, M.Metal), "Head", "Tag")
	b.Footprint(44, 100, 92)
end

REAL.Kitten = function(b)
	-- chaton calico : blanc, taches rousses et noires
	local white = rgb(246, 242, 236)
	quad(b, {
		L = 58, W = 22, BH = 24, H = 44, LegW = 9, Head = { 28, 25, 26 }, Snout = { 7, 12, 9 }, Neck = 10,
		Main = white, Belly = rgb(252, 250, 246), Legs = white, Muzzle = white, Nose = rgb(236, 140, 150),
		Ears = "Pointy", EarColor = rgb(230, 140, 60), EarIn = rgb(250, 196, 200), EarSize = 13, Tail = "Cat", TailColor = rgb(230, 140, 60), TailTip = rgb(50, 40, 40), TailLen = 40,
		Eye = 6.2, Iris = rgb(150, 190, 70), Slit = true, Whiskers = true,
		Patches = { { -5, 39.2, -8, 16, 10.8, 24, rgb(230, 140, 60) }, { 6, 39.2, 12, 12, 10.8, 16, rgb(52, 44, 44) }, { 0, 39.2, -22, 16, 10.8, 16, rgb(52, 44, 44) } },
	})
	b.Footprint(36, 96, 84)
end

REAL.SleepyCat = function(b)
	-- chat tigré gris : rayures foncées, ventre crème, yeux ambrés
	local grey = rgb(150, 148, 150)
	local stripe = rgb(96, 92, 96)
	quad(b, {
		L = 62, W = 24, BH = 26, H = 46, LegW = 9.5, Head = { 29, 26, 27 }, Snout = { 7, 12, 9 }, Neck = 10,
		Main = grey, Belly = rgb(236, 230, 220), Legs = grey, Muzzle = rgb(226, 222, 216), Nose = rgb(220, 130, 140),
		Ears = "Pointy", EarColor = grey, EarIn = rgb(240, 196, 200), EarSize = 13, Tail = "Cat", TailColor = grey, TailTip = stripe, TailLen = 42,
		Eye = 6.4, Iris = rgb(230, 170, 60), Slit = true, Whiskers = true,
		Patches = { { 0, 40.8, 8, 19, 11.7, 5, stripe }, { 0, 40.8, -4, 19.4, 11.7, 5, stripe }, { 0, 40.8, -16, 19, 11.7, 5, stripe } },
	})
	b.Footprint(38, 100, 86)
end

REAL.Fox = function(b)
	-- renard roux : poitrail et bout de queue blancs, chaussettes noires
	local red = rgb(214, 104, 44)
	local white = rgb(248, 244, 236)
	quad(b, {
		L = 62, W = 22, BH = 24, H = 48, LegW = 8.5, Head = { 26, 22, 26 }, Snout = { 20, 12, 10 }, Neck = 14,
		Main = red, Belly = white, Legs = red, Paws = rgb(44, 34, 32), Muzzle = white, Nose = rgb(30, 24, 24),
		Ears = "Pointy", EarColor = rgb(60, 40, 34), EarIn = white, EarSize = 18, Tail = "Bushy", TailColor = red, TailTip = white, TailLen = 46,
		Eye = 5, Iris = rgb(200, 150, 40), Slit = true,
		Patches = { { 0, 34, 20, 14, 18, 16, white } },
	})
	b.Footprint(40, 110, 90)
end

REAL.Bunny = function(b)
	-- lapin blanc aux yeux sombres, intérieur des oreilles rose
	local fur = rgb(246, 244, 240)
	quad(b, {
		L = 50, W = 34, BH = 36, H = 44, LegW = 11, Head = { 30, 28, 28 }, Snout = { 6, 16, 12 }, Neck = 6,
		Main = fur, Belly = rgb(252, 250, 248), Legs = fur, Muzzle = fur, Nose = rgb(240, 150, 160),
		Ears = "Long", EarColor = fur, EarIn = rgb(250, 190, 196), EarSize = 42, Tail = "Pom", TailTip = WHITE, TailLen = 8,
		Eye = 6, Whiskers = true,
	})
	-- grosses cuisses arrière
	for _, side in ipairs({ -1, 1 }) do
		jn(b.Egg(side * 13, 20, -14, 12, 22, 24, fur, M.Fabric), side < 0 and "LegBL" or "LegBR", "Haunch")
	end
	b.Footprint(40, 80, 90)
end

REAL.Hedgehog = function(b)
	local spines = rgb(112, 86, 66)
	local face = rgb(232, 210, 178)
	quad(b, {
		L = 54, W = 40, BH = 30, H = 34, LegW = 8, Head = { 22, 20, 22 }, Snout = { 14, 10, 8 }, Neck = 4,
		Main = face, Belly = face, Legs = rgb(200, 170, 140), Muzzle = face, Nose = rgb(30, 24, 24),
		Ears = "Round", EarColor = rgb(210, 180, 150), EarSize = 7, Tail = "Stub", TailColor = face, TailLen = 4,
		Eye = 4.4,
	})
	-- manteau de piquants
	jn(b.Egg(0, 26, -6, 44, 32, 58, spines, M.Fabric), "Body", "Coat")
	for row = 0, 3 do
		for k = 0, 6 do
			local a = (k / 6 - 0.5) * 2.6
			local y = 30 + math.cos(a) * 12 - row * 2
			local z = 10 - row * 11
			jn(b.Part("WedgePart", CFrame.new(math.sin(a) * 19, y, z) * CFrame.Angles(-0.9, 0, -a * 0.7), Vector3.new(4, 10, 5), (row + k) % 2 == 0 and rgb(90, 66, 50) or rgb(236, 220, 196), M.Fabric, "Piquant"), "Body", "Spine")
		end
	end
	b.Footprint(50, 80, 56)
end

REAL.Turtle = function(b)
	local shell = rgb(104, 122, 62)
	local skin = rgb(150, 160, 96)
	quad(b, {
		L = 44, W = 34, BH = 16, H = 22, LegW = 11, Head = { 16, 14, 18 }, Snout = { 4, 10, 8 }, Neck = 14,
		Main = skin, Belly = rgb(214, 200, 140), Legs = skin, Muzzle = skin, Nose = rgb(60, 70, 40),
		Ears = "None", EarSize = 0, Tail = "Stub", TailColor = skin, TailLen = 6, Eye = 3.6,
	})
	-- carapace bombée + écailles
	jn(b.Egg(0, 24, -2, 60, 30, 66, shell, M.SmoothPlastic), "Body", "Shell")
	jn(b.Egg(0, 17, -2, 64, 6, 70, rgb(80, 96, 50), M.SmoothPlastic), "Body", "Rim")
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		jn(b.Egg(math.cos(a) * 16, 33, math.sin(a) * 18 - 2, 14, 5, 13, rgb(126, 140, 74), M.SmoothPlastic), "Body", "Scute")
	end
	jn(b.Egg(0, 38.5, -2, 15, 4, 15, rgb(126, 140, 74), M.SmoothPlastic), "Body", "Scute")
	b.Footprint(66, 90, 40)
end

REAL.Dragon = function(b)
	local scale = rgb(126, 88, 196)
	local belly = rgb(250, 212, 140)
	local wing = rgb(200, 150, 240)
	local hx, hy, hz = quad(b, {
		L = 54, W = 28, BH = 28, H = 46, LegW = 11, Head = { 28, 24, 30 }, Snout = { 18, 16, 12 }, Neck = 18,
		Main = scale, Belly = belly, Legs = scale, Paws = rgb(96, 64, 150), Muzzle = scale, Nose = rgb(70, 40, 110),
		Ears = "None", EarSize = 0, Tail = "Spiky", TailColor = scale, TailTip = wing, TailLen = 46,
		Eye = 6, Iris = rgb(250, 190, 40), Slit = true,
	})
	for _, side in ipairs({ -1, 1 }) do
		jn(b.Tube(hx + side * 7, hy + 10, hz - 8, hx + side * 11, hy + 22, hz - 16, 5, belly, M.SmoothPlastic), "Head", "Horn")
		-- ailes (voiles) sur les épaules
		local joint = side < 0 and "WingL" or "WingR"
		marker(b, joint, side * 10, 52, 12)
		jn(b.Tube(side * 10, 52, 12, side * 34, 70, 0, 3.5, scale, M.SmoothPlastic), joint, "Bone")
		jn(b.Part("WedgePart", CFrame.new(side * 22, 58, 2) * CFrame.Angles(0.15, side * -0.35, side * -0.7), Vector3.new(1.6, 26, 24), wing, M.SmoothPlastic, "Aile"), joint, "Sail")
	end
	for index = 0, 3 do
		jn(b.Part("WedgePart", CFrame.new(0, 60 - index * 2, 16 - index * 12), Vector3.new(2.5, 7, 7), wing, M.SmoothPlastic, "Plaque"), "Body", "Plate")
	end
	b.Footprint(56, 110, 100)
end

REAL.Chick = function(b)
	realBird(b, "Chick")
	b.Footprint(56, 60, 82)
end
REAL.Duckling = function(b)
	realBird(b, "Duckling")
	b.Footprint(52, 72, 76)
end
REAL.Penguin = function(b)
	realBird(b, "Penguin")
	b.Footprint(56, 52, 100)
end
REAL.Owl = function(b)
	realBird(b, "Owl")
	b.Footprint(58, 54, 100)
end

-- Espèces qui se promènent (PetRoam) : même liste que les recettes réalistes
House3DCritters.ROAMERS = {}
for id in pairs(REAL) do
	House3DCritters.ROAMERS[id] = true
end

-- (les animaux réalistes remplacent les anciennes figurines assises ; les
-- peluches gardent leur style)
for id, build in pairs(REAL) do
	R[id] = function(b: Builder, _ctx: any)
		build(b)
	end
end

----------------------------------------------------------------------
-- Branchement
----------------------------------------------------------------------

-- Animaux qui respirent (pas les bocaux / la roue)
local PETS = { "Chick", "SleepyCat", "Turtle", "Puppy", "Bunny", "Parrot", "Fox", "Dragon", "Kitten", "Hedgehog", "Duckling", "Penguin", "Owl" }

function House3DCritters.Register(recipes: { [string]: any }, _family: { [string]: any }, _helpers: any, flags: any)
	for id, recipe in pairs(R) do
		recipes[id] = recipe
	end
	for _, id in ipairs(PETS) do
		flags.Pets[id] = true
	end
end

return House3DCritters
