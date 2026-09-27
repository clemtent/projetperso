--[[
	HouseStairs (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseStairs

	🚶 Dopamine Town (v9.4) : la cage d'escalier d'une maison 3D (dans la
	travée où la maison 2D dessine l'entrée, WorldLayout.HallSpan).
	  - Une volée DROITE par étage, au milieu de la cage, face à la porte :
	    13 marches (contremarche 1 stud, giron 1,4 stud, pente ~35,5°) en bois
	    avec un tapis rose, limons, sous-face, main courante et balustres des
	    deux côtés, poteaux (départ / arrivée) à boule.
	  - COLLISION : une rampe lisse INVISIBLE (StairRamp, CanCollide) sous les
	    marches (les marches visibles ne bloquent rien) : l'avatar (R15 / R6)
	    monte et descend sans jamais accrocher. Le haut de la rampe arrive au
	    ras du palier (WorldLayout.StairHeight) ; le palier ne devient solide
	    qu'à STAIR_D1 (le nez de la dernière marche n'est que décor).
	  - Trémie dans le plancher du dessus (STAIR_HOLE_D0..STAIR_D1) : >= 7,5
	    studs de hauteur libre partout sur le chemin ; garde-corps autour
	    (et en travers au dernier étage).
	  - Couloirs de chaque côté (3,5 studs) vers les passages des pièces
	    (alignés sur les passages des coques : milieu de la profondeur).
	  - Rez-de-chaussée : placard sous l'escalier (panneaux en coin), dallage,
	    paillasson ; plaques "Étage N" et flèches ⬆ / ⬇ pour s'y retrouver ;
	    une applique lumineuse par étage (budget du kit).

	API :
	  HouseStairs.Build(kit, size, colors) -> { Ramps: { BasePart }, Holes: { { number } } }
	  colors = { Wall: Color3, Trim: Color3, Accent: Color3 }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local HouseStairs = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local TREAD = Color3.fromRGB(176, 118, 84)
local RISER = Color3.fromRGB(255, 250, 244)
local RUNNER = Color3.fromRGB(236, 110, 150)
local RAIL = Color3.fromRGB(128, 82, 58)
local HALL_FLOOR = Color3.fromRGB(214, 170, 126)
local TILE = Color3.fromRGB(246, 236, 240)
local CEILING = Color3.fromRGB(255, 250, 244)

export type Colors = { Wall: Color3, Trim: Color3, Accent: Color3 }
export type Result = { Ramps: { BasePart }, Holes: { { number } }, Parts: number }

local function floorName(floor: number): string
	if floor <= 1 then
		return Locale.T("Ground floor")
	end
	return Locale.T("Floor %s", tostring(floor - 1))
end

-- Une volée : de l'étage `floor` à l'étage `floor + 1`
local function flight(kit: any, size: any, floor: number, colors: Colors, ramps: { BasePart })
	local s0, s1 = WorldLayout.StairSpan(size)
	local y0 = WorldLayout.FloorY(floor)
	local D0, D1 = WorldLayout.STAIR_D0, WorldLayout.STAIR_D1
	local T, R = WorldLayout.STAIR_TREAD, WorldLayout.STAIR_RISE
	local steps = WorldLayout.STAIR_STEPS
	local cx = (s0 + s1) / 2
	local width = s1 - s0
	local function ramp(d: number): number
		return y0 + WorldLayout.StairHeight(d)
	end

	-- 1. Rampe de collision : dessus EXACTEMENT de (D0, sol) à (D1, étage du
	-- dessus) ; prolongée sous le sol en bas (enterrée, aucune marche)
	local extra = 0.8
	local slope = WorldLayout.STORY / (D1 - D0)
	local rampPart = kit:Slab("StairRamp", cx, { y0 - extra * slope, D0 - extra }, { y0 + WorldLayout.STORY, D1 }, width - 0.1, 1, WHITE, M.SmoothPlastic,
		{ Solid = true, Query = true, T = 1, Shadow = false })
	rampPart:SetAttribute("StairFloor", floor)
	table.insert(ramps, rampPart)

	-- 2. Marches visibles (sans collision) : contremarche i au milieu de la
	-- rampe (i - 0,5), giron jusqu'à la contremarche suivante
	for i = 1, steps do
		local dRiser = D0 + (i - 0.5) * T
		local top = y0 + i * R
		-- (v9.6 z-fighting : contremarche un peu en retrait (dRiser - 0.03) et giron
		-- qui s'arrête 0.06 avant la contremarche suivante : aucune face commune)
		kit:Box("Riser", s0 + 0.35, s1 - 0.35, top - R, top - 0.2, dRiser - 0.12, dRiser - 0.03, RISER, M.SmoothPlastic, { Shadow = false })
		if i < steps then
			-- giron (bois, nez qui dépasse un peu) + tapis
			kit:Box("Tread", s0 + 0.3, s1 - 0.3, top - 0.25, top, dRiser - 0.16, dRiser + T - 0.06, TREAD, M.Wood, { Shadow = false })
			kit:Box("Runner", cx - 1.5, cx + 1.5, top, top + 0.06, dRiser - 0.05, dRiser + T - 0.13, RUNNER, M.Fabric, { Shadow = false })
		else
			-- dernière marche : nez du palier (décor, le palier solide est à D1)
			kit:Box("Nosing", s0 + 0.3, s1 - 0.3, top - 0.25, top, dRiser - 0.16, D1, TREAD, M.Wood, { Shadow = false })
		end
	end
	-- 3. Limons (côtés, au-dessus du nez des marches) + sous-face
	-- (v9.6 z-fighting : toutes les pièces du bord de l'escalier et du
	-- garde-corps de la trémie ont des faces distinctes d'au moins 0.03 stud :
	-- limon [0, 0.33], main courante / lisse [0.04, 0.36], balustres [0.11, 0.29],
	-- lisse basse [0.1, 0.3], poteaux [-0.05, 0.45] depuis le bord)
	for _, x in ipairs({ s0 + 0.165, s1 - 0.165 }) do
		kit:Slab("Stringer", x, { ramp(D0 - 0.6) + 0.95, D0 - 0.6 }, { ramp(D1) + 0.95, D1 }, 0.33, 2.2, colors.Trim, M.Wood, { Shadow = true })
	end
	kit:Slab("Soffit", cx, { ramp(D0 + 0.8) - 0.95, D0 + 0.8 }, { ramp(D1) - 0.95, D1 }, width - 0.4, 0.3, CEILING, M.SmoothPlastic, { Shadow = false })

	-- 4. Mains courantes + balustres + poteaux, des deux côtés
	local railH = 3.2
	for _, x in ipairs({ s0 + 0.2, s1 - 0.2 }) do
		kit:Slab("Handrail", x, { ramp(D0 - 0.3) + railH + 0.12, D0 - 0.3 }, { ramp(D1) + railH + 0.12, D1 }, 0.32, 0.24, RAIL, M.Wood, { Solid = true, Shadow = false })
		for i = 1, steps - 1 do
			local d = D0 + (i + 0.15) * T
			local base = y0 + i * R
			kit:Box("Baluster", x - 0.09, x + 0.09, base, ramp(d) + railH, d - 0.09, d + 0.09, WHITE, M.SmoothPlastic, { Shadow = false })
		end
		-- poteau de départ (boule dorée)
		kit:Box("Newel", x - 0.25, x + 0.25, y0, y0 + railH + 0.7, D0 - 0.75, D0 - 0.25, colors.Trim, M.Wood, { Solid = true, Shadow = false })
		kit:Ball("NewelCap", x, y0 + railH + 0.95, D0 - 0.5, 0.55, Color3.fromRGB(246, 196, 84), M.Metal)
	end
end

-- Plancher de l'étage `floor` dans la cage (trémie si un escalier arrive)
local function hallFloor(kit: any, size: any, floor: number, floors: number)
	local h0, h1 = WorldLayout.HallSpan(size)
	local s0, s1 = WorldLayout.StairSpan(size)
	local y = WorldLayout.FloorY(floor)
	local T = WorldLayout.WALL_T
	local dFront, dBack = T, T + WorldLayout.DEPTH
	if floor == 1 then
		-- soubassement plein + dallage (jusque sous la porte)
		-- (v9.6 z-fighting : commence DERRIÈRE la façade (d = T) ; avant, le dallage
		-- et le soubassement doublaient le seuil et la fondation de la façade)
		kit:Box("HallBase", h0, h1, 0, y - 0.2, dFront, dBack, Color3.fromRGB(226, 214, 222), M.Concrete, { Solid = true, Shadow = false })
		kit:Box("HallTiles", h0, h1, y - 0.2, y, dFront, dBack, TILE, M.Marble, { Solid = true, Shadow = false })
		-- paillasson devant la porte
		local door = WorldLayout.DoorX(size)
		kit:Box("DoorMat", door - 2, door + 2, y, y + 0.05, dFront + 0.2, dFront + 2, Color3.fromRGB(196, 150, 110), M.Fabric, { Shadow = false })
		return
	end
	local D1, H0 = WorldLayout.STAIR_D1, WorldLayout.STAIR_HOLE_D0
	-- (quatre morceaux autour de la trémie : couloirs gauche / droite, devant, fond)
	local pieces = {
		{ h0, s0, dFront, dBack },
		{ s1, h1, dFront, dBack },
		{ s0, s1, dFront, H0 },
		{ s0, s1, D1, dBack },
	}
	for _, r in ipairs(pieces) do
		kit:Box("HallSlab", r[1], r[2], y - WorldLayout.SLAB, y - 0.2, r[3], r[4], CEILING, M.SmoothPlastic, { Solid = true, Shadow = false })
		kit:Box("HallFloor", r[1], r[2], y - 0.2, y, r[3], r[4], HALL_FLOOR, M.WoodPlanks, { Solid = true, Shadow = false })
	end
	-- garde-corps autour de la trémie (côtés ; en travers au dernier étage)
	local railH = 3.2
	for _, x in ipairs({ s0 + 0.2, s1 - 0.2 }) do
		kit:Box("GuardRail", x - 0.16, x + 0.16, y + railH, y + railH + 0.24, H0, D1, RAIL, M.Wood, { Solid = true, Shadow = false })
		kit:Box("GuardBase", x - 0.1, x + 0.1, y, y + 0.25, H0, D1, WHITE, M.SmoothPlastic, { Solid = true, Shadow = false })
		local count = math.floor((D1 - H0) / 1.1)
		for i = 0, count do
			local d = H0 + 0.2 + i * (D1 - H0 - 0.4) / math.max(1, count)
			kit:Box("GuardBaluster", x - 0.09, x + 0.09, y + 0.25, y + railH, d - 0.09, d + 0.09, WHITE, M.SmoothPlastic, { Solid = i % 3 == 0, Shadow = false })
		end
		kit:Box("GuardPost", x - 0.25, x + 0.25, y, y + railH + 0.5, H0 - 0.25, H0 + 0.25, RAIL, M.Wood, { Solid = true, Shadow = false })
	end
	if floor == floors then
		kit:Box("GuardRail", s0, s1, y + railH, y + railH + 0.24, H0 - 0.16, H0 + 0.16, RAIL, M.Wood, { Solid = true, Shadow = false })
		kit:Box("GuardBase", s0, s1, y, y + 0.25, H0 - 0.12, H0 + 0.12, WHITE, M.SmoothPlastic, { Solid = true, Shadow = false })
		for i = 1, 3 do
			local x = s0 + i * (s1 - s0) / 4
			kit:Box("GuardBaluster", x - 0.09, x + 0.09, y + 0.25, y + railH, H0 - 0.09, H0 + 0.09, WHITE, M.SmoothPlastic, { Shadow = false })
		end
	end
end

-- Murs intérieurs de la cage (peau décorée, passages vers les pièces)
local function hallWalls(kit: any, size: any, floor: number, colors: Colors)
	local h0, h1 = WorldLayout.HallSpan(size)
	local y = WorldLayout.FloorY(floor)
	local T, D = WorldLayout.WALL_T, WorldLayout.DEPTH
	local dFront, dBack = T, T + D
	local hall = WorldLayout.HallAfter(size)
	local dims = WorldLayout.Dims(size)
	local mid = T + D / 2
	local pass = { mid - WorldLayout.PASS_W / 2, mid + WorldLayout.PASS_W / 2, y, y + WorldLayout.PASS_H }
	local dado = colors.Wall:Lerp(colors.Trim, 0.55)
	for _, side in ipairs({ -1, 1 }) do
		local room = if side < 0 then hall > 0 else hall < dims.Columns
		local face = if side < 0 then h0 else h1
		local x0, x1 = face, face - side * 0.15
		if x1 < x0 then
			x0, x1 = x1, x0
		end
		local holes = room and { pass } or {}
		kit:WallD("HallWall", x0, x1, y + 3.4, y + WorldLayout.WALL_H, dFront, dBack, holes, colors.Wall, M.Plaster, { Solid = false, Shadow = false })
		kit:WallD("HallDado", x0, x1, y, y + 3.4, dFront, dBack, holes, dado, M.Wood, { Solid = false, Shadow = false })
		-- (v9.6 z-fighting : les moulures s'arrêtent 0.03 avant la face arrière
		-- de la peau du mur, sinon faces confondues dans le passage)
		local r0, r1 = face - side * 0.3, face - side * 0.03
		if r1 < r0 then
			r0, r1 = r1, r0
		end
		kit:WallD("ChairRail", r0, r1, y + 3.3, y + 3.55, dFront, dBack, holes, colors.Trim, M.Wood, { Shadow = false })
		kit:WallD("Skirting", r0, r1, y, y + 0.6, dFront, dBack, holes, colors.Trim, M.Wood, { Shadow = false })
		if room then
			-- chambranle du passage
			for _, d in ipairs({ pass[1] - 0.2, pass[2] + 0.2 }) do
				kit:Box("PassFrame", r0, r1, y, y + WorldLayout.PASS_H + 0.3, d - 0.2, d + 0.2, colors.Trim, M.Wood, { Shadow = false })
			end
			kit:Box("PassFrame", r0, r1, y + WorldLayout.PASS_H, y + WorldLayout.PASS_H + 0.45, pass[1] - 0.4, pass[2] + 0.4, colors.Trim, M.Wood, { Shadow = false })
		end
	end
	-- corniche + plafonnier (vraie lumière, budget du kit)
	local cx = (h0 + h1) / 2
	local lampY = y + WorldLayout.WALL_H - 0.8
	local lampD = WorldLayout.STAIR_D0 - 1.6
	kit:CylY("CeilingRose", cx, y + WorldLayout.WALL_H - 0.2, lampD, 1.4, 0.2, colors.Trim, M.SmoothPlastic)
	-- (v9.6 "flash bang" : globe en verre dépoli, plus une boule Neon ; 22 / 1.1 -> 14 / 0.7)
	local shade = kit:Ball("HallLamp", cx, lampY, lampD, 1.3, Color3.fromRGB(255, 240, 214), M.SmoothPlastic, { Shadow = false })
	kit:Light(shade, Color3.fromRGB(255, 226, 180), 14, 0.7)
	-- plaque de l'étage (fond du palier) + flèches
	local plaque = kit:Box("FloorPlaque", cx - 2.6, cx + 2.6, y + 6.2, y + 7.6, dBack - 0.14, dBack - 0.02, WHITE, M.SmoothPlastic, { Shadow = false })
	local text = floorName(floor)
	kit:Text(plaque, Enum.NormalId.Back, text, colors.Accent, Enum.Font.FredokaOne, 30, 90)
	if floor > 1 then
		local down = kit:Box("DownSign", cx - 1.8, cx + 1.8, y + 4.8, y + 5.9, dBack - 0.14, dBack - 0.02, colors.Accent, M.SmoothPlastic, { Shadow = false })
		kit:Text(down, Enum.NormalId.Back, "⬇️ " .. floorName(floor - 1), WHITE, Enum.Font.GothamBold, 30, 90)
	end
end

function HouseStairs.Build(kit: any, size: any, colors: Colors): Result
	local dims = WorldLayout.Dims(size)
	local floors = dims.Floors
	local ramps: { BasePart } = {}
	local holes = {}
	local before = kit.Stats.Count
	for floor = 1, floors do
		hallFloor(kit, size, floor, floors)
		hallWalls(kit, size, floor, colors)
		if floor < floors then
			flight(kit, size, floor, colors, ramps)
			table.insert(holes, { floor + 1, WorldLayout.STAIR_HOLE_D0, WorldLayout.STAIR_D1 })
			-- flèche ⬆ au pied de la volée (sur la face de la première contremarche)
			local s0, s1 = WorldLayout.StairSpan(size)
			local y = WorldLayout.FloorY(floor)
			local riser = WorldLayout.STAIR_D0 + 0.5 * WorldLayout.STAIR_TREAD - 0.12
			local up = kit:Box("UpSign", s0 + 0.9, s1 - 0.9, y + 0.12, y + 0.72, riser - 0.05, riser - 0.01, colors.Accent, M.SmoothPlastic, { Shadow = false })
			kit:Text(up, Enum.NormalId.Back, "⬆️ " .. floorName(floor + 1), WHITE, Enum.Font.GothamBold, 40, 60)
		end
	end
	-- Rez-de-chaussée : placard sous la première volée (panneaux en coin)
	if floors >= 2 then
		local s0, s1 = WorldLayout.StairSpan(size)
		local y0 = WorldLayout.FloorY(1)
		local D0, D1 = WorldLayout.STAIR_D0, WorldLayout.STAIR_D1
		local length = D1 - (D0 + 3)
		local height = WorldLayout.StairHeight(D1) - WorldLayout.StairHeight(D0 + 3) - 0.9
		for _, x in ipairs({ s0 + 0.18, s1 - 0.18 }) do
			-- coin : face verticale au fond (D1), pente vers l'avant
			-- (v9.6 : 0.24 d'épaisseur, faces à 0.06 / 0.30 du bord, pas sur le limon)
			local center = CFrame.new(x, y0 + WorldLayout.StairHeight(D0 + 3) + height / 2 - 0.6, -(D0 + 3 + length / 2)) * CFrame.Angles(0, math.pi, 0)
			kit:Part("UnderStair", Vector3.new(0.24, height, length), center, Color3.fromRGB(236, 222, 236), M.Wood, { Solid = true }, "WedgePart")
			kit:Box("UnderStairLow", x - 0.12, x + 0.12, y0, y0 + WorldLayout.StairHeight(D0 + 3) - 0.6, D0 + 3, D1, Color3.fromRGB(236, 222, 236), M.Wood,
				{ Solid = true, Shadow = false })
		end
		-- petite porte de placard (décor) côté gauche
		kit:Box("ClosetDoor", s0 - 0.04, s0 + 0.03, y0, y0 + 4.2, D1 - 4.2, D1 - 1.6, Color3.fromRGB(214, 176, 206), M.Wood, { Shadow = false })
	end
	-- Plafond du dernier étage
	local h0, h1 = WorldLayout.HallSpan(size)
	local top = WorldLayout.FloorY(floors) + WorldLayout.WALL_H
	-- (v9.6 z-fighting : la façade pose déjà sa dalle de toit [top, top + 0.6] ;
	-- le plafond du hall descend de 0.1 et s'arrête dans la dalle)
	kit:Box("HallCeiling", h0, h1, top - 0.1, top + 0.5, WorldLayout.WALL_T, WorldLayout.WALL_T + WorldLayout.DEPTH, CEILING, M.SmoothPlastic, { Solid = true, Shadow = false })
	return { Ramps = ramps, Holes = holes, Parts = kit.Stats.Count - before }
end

return HouseStairs
