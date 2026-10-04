--[[
	HouseLod (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseLod

	(v10 HOUSE10) 🏡 Niveaux de détail des maisons LOINTAINES (50 maisons en
	ville, fluide sur téléphone) :
	  - "Mid" (~250 à ~600 studs) : volume du bâtiment, vraies fenêtres
	    (cadre + vitre, une pièce chacune, volets si peu de fenêtres), porte,
	    toit de la bonne forme SANS détails (HouseDetail.Roof Detail = false),
	    cheminées, tours / fronton du manoir, clôtures et haies en blocs,
	    garage, arbres simplifiés ; ~60 à ~170 pièces ;
	  - "Far" (au-delà) : imposteur : bloc des murs, bandeaux de fenêtres par
	    étage, toit en 2 coins (ou bloc), tours du manoir ; <= ~12 pièces.
	Mêmes couleurs / formes que l'extérieur complet (HouseFacade.Resolve) :
	pas de "saut" visible quand on s'approche. La nuit, les vitres du Mid et
	les bandeaux du Far s'allument comme les vraies fenêtres (Glow.Part).

	API :
	  HouseLod.Build(kit, size, looks, level) -> { Glows = { [slot] = { Glow } }, Style, Arch }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local HouseDetail = require(script.Parent.HouseDetail)
local HouseFacade = require(script.Parent.HouseFacade)
local HouseKit = require(script.Parent.HouseKit)

local HouseLod = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GLASS_DAY = Color3.fromRGB(78, 100, 124)
local LEAF = Color3.fromRGB(104, 164, 96)
local TRUNK = Color3.fromRGB(128, 96, 74)
local DECO = { Shadow = false }

export type Result = { Glows: { [number]: { any } }, Style: string, Arch: string }

local function glow(result: Result, slot: number, part: BasePart)
	local list = result.Glows[slot]
	if not list then
		list = {}
		result.Glows[slot] = list
	end
	table.insert(list, { Part = part, Day = part.Color, DayMat = part.Material })
end

function HouseLod.Build(kit: any, size: any, looks: any, level: string): Result
	local spec = HouseFacade.Resolve(size, looks)
	local style, arch = spec.Style, spec.Arch
	local dims = WorldLayout.Dims(size)
	local T = WorldLayout.WALL_T
	local L, R = dims.Left - T, dims.Left + dims.Width + T
	local depth = dims.Depth
	local top = WorldLayout.FloorY(dims.Floors) + WorldLayout.WALL_H
	local hall0, hall1 = WorldLayout.HallSpan(size)
	local doorX = WorldLayout.DoorX(size)
	local result: Result = { Glows = {}, Style = style, Arch = arch }
	local wall, trim, roof = spec.Wall, spec.Trim, spec.Roof
	local g = kit:Sub(CFrame.new(0, HouseKit.LAWN, 0))
	local mansion = style == "Mansion" and arch == "Classic"
	local cottage = style == "Cottage" and arch == "Classic"

	-- corps du bâtiment (+ soubassement)
	kit:Box("LodBody", L, R, 0.05, top + 0.65, -0.3, depth + 0.3, wall, spec.WallMat, { Solid = true, Shadow = true })
	kit:Box("LodPlinth", L - 0.3, R + 0.3, -0.05, WorldLayout.PLINTH, -0.6, depth + 0.6, Color3.fromRGB(200, 194, 188), M.Concrete, DECO)

	if level == "Far" then
		-- bandeaux de fenêtres (devant / derrière), un par étage
		for floor = 1, dims.Floors do
			local y = WorldLayout.FloorY(floor)
			local front = kit:Box("LodWindows", L + 2, R - 2, y + 2.6, y + 8.6, -0.5, -0.3, GLASS_DAY, M.SmoothPlastic, DECO)
			glow(result, 0, front)
			kit:Box("LodWindows", L + 2, R - 2, y + 2.6, y + 8.6, depth + 0.3, depth + 0.5, GLASS_DAY, M.SmoothPlastic, DECO)
		end
		-- toit : 2 coins (pentes) ou un bloc plat
		local shape = spec.RoofShape
		if shape == "Flat" then
			kit:Box("LodRoof", L - 0.3, R + 0.3, top + 0.65, top + 1.6, -0.6, depth + 0.6, roof:Lerp(BLACK, 0.2), M.SmoothPlastic, DECO)
		else
			local rise = if shape == "Mansard" then 9 else depth * 0.36
			local x0, x1 = L, if cottage or style == "Townhouse" and arch == "Classic" then hall0 + 0.4 else R
			local up = Vector3.new(0, 1, 0)
			HouseDetail.Wedge(kit, "LodRoof", HouseDetail.V((x0 + x1) / 2, top + 0.65 + rise / 2, depth / 4 - 0.4), up, Vector3.new(0, 0, -1),
				Vector3.new(x1 - x0 + 2, rise, depth / 2 + 1.2), roof, spec.RoofMat, { Solid = true, Shadow = true })
			HouseDetail.Wedge(kit, "LodRoof", HouseDetail.V((x0 + x1) / 2, top + 0.65 + rise / 2, depth * 3 / 4 + 0.4), up, Vector3.new(0, 0, 1),
				Vector3.new(x1 - x0 + 2, rise, depth / 2 + 1.2), roof, spec.RoofMat, { Solid = true, Shadow = true })
		end
		if mansion then
			for _, s in ipairs({ -1, 1 }) do
				local tx = if s < 0 then L - 1 else R + 1
				kit:CylY("LodTower", tx, -0.15, 0.5, 14, top + 3.15, wall, spec.WallMat, { Solid = true })
				kit:Cone("LodTowerRoof", tx, top + 3.9, 0.5, 8.6, 12, 6, roof, spec.RoofMat)
			end
		end
		return result
	end

	-- ░░ Mid ░░
	-- fenêtres (cadre + vitre) des pièces, devant et derrière
	local count = 0
	for floor = 1, dims.Floors do
		for column = 1, dims.Columns do
			count += #HouseFacade.WindowRects(size, column, floor, spec)
		end
	end
	local shutters = spec.Shutters ~= "None" and count <= 16
	for floor = 1, dims.Floors do
		for column = 1, dims.Columns do
			local slot = (floor - 1) * dims.Columns + column
			for _, r in ipairs(HouseFacade.WindowRects(size, column, floor, spec)) do
				kit:Box("LodFrame", r[1] - 0.35, r[2] + 0.35, r[3] - 0.35, r[4] + 0.35, -0.42, -0.3, trim, M.SmoothPlastic, DECO)
				local pane = kit:Box("LodGlass", r[1], r[2], r[3], r[4], -0.48, -0.4, GLASS_DAY, M.SmoothPlastic, DECO)
				glow(result, slot, pane)
				if shutters then
					local w = math.min((r[2] - r[1]) / 2, 2.8)
					kit:Box("LodShutter", r[1] - 0.45 - w, r[1] - 0.45, r[3], r[4], -0.55, -0.3, spec.ShutterColor, M.Wood, DECO)
					kit:Box("LodShutter", r[2] + 0.45, r[2] + 0.45 + w, r[3], r[4], -0.55, -0.3, spec.ShutterColor, M.Wood, DECO)
				end
			end
			local b = HouseFacade.BackWindowRect(size, column, floor)
			local back = kit:Box("LodGlass", b[1], b[2], b[3], b[4], depth + 0.3, depth + 0.42, GLASS_DAY, M.SmoothPlastic, DECO)
			glow(result, slot, back)
		end
	end
	-- porte + perron
	local y1 = WorldLayout.FloorY(1)
	kit:Box("LodDoorFrame", doorX - 3.8, doorX + 3.8, y1, y1 + WorldLayout.DOOR_H + 0.6, -0.42, -0.3, trim, M.SmoothPlastic, DECO)
	kit:Box("LodDoor", doorX - 3.2, doorX + 3.2, y1, y1 + WorldLayout.DOOR_H - 0.1, -0.5, -0.4, spec.DoorColor, M.Wood, DECO)
	kit:Box("LodSteps", doorX - 5, doorX + 5, 0, y1 - 0.05, -4.5, -0.3, Color3.fromRGB(206, 200, 194), M.Limestone, { Solid = true, Shadow = false })
	-- volumes propres aux styles
	local roofX0, roofX1 = L, R
	if cottage then
		local annexTop = top + 3.2
		kit:Box("LodAnnex", hall0, hall1 + T + 0.05, top + 0.4, annexTop, -0.35, depth + 0.35, wall:Lerp(Color3.fromRGB(255, 126, 182), 0.1), spec.WallMat, { Solid = true })
		HouseDetail.GableX(kit, "LodAnnexGable", -0.3, depth + 0.3, hall0 - 0.9, hall1 + T + 0.9, annexTop, annexTop + 5.5, roof, spec.RoofMat, { Solid = true })
		roofX1 = hall0 + 0.4
	elseif style == "Townhouse" and arch == "Classic" then
		roofX1 = hall0 + 0.4
		kit:Box("LodCornice", L - 0.9, R + 0.9, top - 0.2, top + 1.1, -1.3, depth + 0.5, trim, M.Plaster, DECO)
	elseif mansion then
		kit:Box("LodCornice", L - 1, R + 1, top - 0.2, top + 1.3, -1.5, depth + 0.5, trim, M.Limestone, DECO)
		HouseDetail.GableX(kit, "LodPediment", -0.3, 1.5, doorX - 17, doorX + 17, top + 1.3, top + 12.3, trim, M.Limestone, { Solid = true })
		for _, s in ipairs({ -1, 1 }) do
			local tx = if s < 0 then L - 1 else R + 1
			kit:CylY("LodTower", tx, -0.15, 0.5, 14, top + 3.15, wall:Lerp(Color3.fromRGB(255, 126, 182), 0.06), spec.WallMat, { Solid = true })
			kit:CylY("LodTowerCrown", tx, top - 0.3, 0.5, 15.6, 1.2, trim, M.Limestone, DECO)
			kit:Cone("LodTowerRoof", tx, top + 3.9, 0.5, 8.6, 12, 6, roof, spec.RoofMat)
			for floor = 1, dims.Floors do
				local y = WorldLayout.FloorY(floor)
				local pane = kit:Box("LodGlass", tx - 1.8, tx + 1.8, y + 2.4, y + 8, -6.9, -6.4, GLASS_DAY, M.SmoothPlastic, DECO)
				glow(result, 0, pane)
			end
		end
	elseif arch == "Modern" then
		kit:Box("LodCladding", hall0 - 0.4, hall1 + T + 0.4, WorldLayout.PLINTH, top + 2.4, -1.1, depth + 0.45, Color3.fromRGB(176, 124, 82), M.WoodPlanks, { Solid = true })
	elseif style == "Loft" and spec.RoofShape == "Flat" then
		kit:Box("LodParapet", L, R, top + 0.65, top + 3.2, -0.3, depth + 0.3, wall, spec.WallMat, DECO)
		kit:Box("LodCoping", L - 0.4, R + 0.4, top + 3.2, top + 3.7, -0.7, depth + 0.7, Color3.fromRGB(216, 212, 208), M.Concrete, DECO)
		kit:CylY("LodTank", L + (R - L) * 0.2, top + 3.7, depth * 0.5, 6.4, 6, Color3.fromRGB(150, 110, 78), M.WoodPlanks, DECO)
	end
	-- toit (forme choisie, sans détails)
	if not (style == "Loft" and arch == "Classic" and spec.RoofShape == "Flat") then
		local info = HouseDetail.Roof(kit, roofX0, roofX1, -0.3, depth + 0.3, top + 0.65, {
			Shape = spec.RoofShape,
			Color = roof,
			Material = spec.RoofMat,
			Kind = spec.RoofKind,
			Over = if arch == "Chalet" then 3.2 else 1.6,
			Pitch = if arch == "Chalet" then 0.62 elseif arch == "Modern" then 0.35 else 0.75,
			Rise = if spec.RoofShape == "Mansard" then 9 else nil,
			Inset = 5,
			Fascia = trim,
			Wall = wall,
			WallMat = spec.WallMat,
			Detail = false,
			Parapet = spec.Parapet,
		})
		if spec.Chimney ~= "None" then
			local cx = roofX0 + (roofX1 - roofX0) * 0.7
			local cd = depth * 0.55
			local ytop = math.max(info.Ridge + 2.2, info.Surface(cx, cd) + 3)
			kit:Box("LodChimney", cx - 1.3, cx + 1.3, top + 0.7, ytop, cd - 1.3, cd + 1.3, if spec.Chimney == "Stone" then Color3.fromRGB(176, 168, 158) else Color3.fromRGB(168, 84, 66),
				M.Brick, DECO)
		end
	end
	-- garage attenant
	if style ~= "Mansion" and spec.Garage ~= "None" then
		local x0 = dims.Left + dims.Width + T + 0.05
		kit:Box("LodGarage", x0, x0 + 17, 0, 11, 1.2, 23.8, wall, spec.WallMat, { Solid = true }) -- (v11 HOUSE11 : = HouseFacade.GARAGE_D1)
		kit:Box("LodGarageDoor", x0 + 2, x0 + 14, 0.25, 8.2, 1.05, 1.2, trim:Lerp(WHITE, 0.5), M.SmoothPlastic, DECO)
	end
	-- jardin : clôture de devant, côtés, haie du fond, 2 arbres
	local fence = spec.Fence
	local fenceColor = if fence == "Picket" then Color3.fromRGB(250, 250, 246) elseif fence == "Hedge" then Color3.fromRGB(78, 138, 74)
		elseif fence == "Iron" then HouseDetail.IRON elseif fence == "Stone" then Color3.fromRGB(190, 182, 170) else Color3.fromRGB(150, 110, 76)
	local fenceMat = if fence == "Hedge" then M.Grass elseif fence == "Stone" then M.Cobblestone elseif fence == "Iron" then M.Metal else M.WoodPlanks
	local half = WorldLayout.PLOT_W / 2 - 0.4
	if fence ~= "None" then
		local f0, f1 = if mansion then L - 7 else dims.Left - 4, if mansion then R + 7 else dims.Left + dims.Width + 4
		g:Box("LodFence", f0, doorX - 2.4, 0, 2.6, -21.15, -20.85, fenceColor, fenceMat, DECO)
		g:Box("LodFence", doorX + 2.4, f1, 0, 2.6, -21.15, -20.85, fenceColor, fenceMat, DECO)
		for _, s in ipairs({ -1, 1 }) do
			g:Box("LodFence", s * half - 0.15, s * half + 0.15, 0, 2.6, -24, 51.4, fenceColor, fenceMat, DECO)
		end
	end
	g:Box("LodHedge", -half + 0.4, half - 0.4, 0, 2.6, 51.95, 53.35, Color3.fromRGB(78, 138, 74), M.Grass, DECO)
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (half - 5)
		g:CylY("LodTrunk", x, 0, -24.5, 1, 7, TRUNK, M.Wood, DECO)
		g:Ball("LodLeaves", x, 9, -24.5, 7.5, LEAF, M.Grass, DECO)
	end
	return result
end

return HouseLod
