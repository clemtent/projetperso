--[[
	HouseLookCards (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseLookCards

	(v9.1) Aperçus dessinés des cartes de personnalisation de la boutique
	(uniquement des Frames, taille fixe W x H de maquette) :
	  Trim      : coin de pièce (papier peint de la pièce, plafond, moulure,
	              plinthe et fenêtre dans la couleur des boiseries)
	  Mood      : petite pièce (mur, sol, lampe, canapé) sous l'ambiance
	              (voile + effet figé, HouseMoods.Static)
	  View      : grande fenêtre avec la vue (HouseViews)
	  Facade    : petite maison, murs de la couleur choisie
	  Roof      : petite maison, toit de la couleur choisie
	  RoofStyle : petite maison avec le motif du toit
	  Garden    : la déco du jardin (HouseArt.PaintGarden) sur un carré de gazon
	L'appelant coupe ce qui déborde (CanvasGroup arrondi).

	API :
	  HouseLookCards.Paint(frame, kind, entry, w, h, context?)
	      context = { Wallpaper = Style?, Floor = Style?, Facade = Color3?, Roof = Color3? }
	      (styles actuels de la pièce / de la maison, pour des aperçus fidèles)
]]

local HousePatterns = require(script.Parent.HousePatterns)
local HouseViews = require(script.Parent.HouseViews)
local HouseMoods = require(script.Parent.HouseMoods)
local HouseArt = require(script.Parent.HouseArt)
local HouseCommon = require(script.Parent.HouseCommon)

local HouseLookCards = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Heart = HousePatterns.Heart
local Sparkle = HousePatterns.Sparkle
local Round = HousePatterns.Round

type Context = { Wallpaper: any?, Floor: any?, Facade: Color3?, Roof: Color3? }

local DEFAULT_WALL = { Pattern = "Stripes", A = Color3.fromRGB(255, 214, 229), B = Color3.fromRGB(255, 186, 211) }
local DEFAULT_FLOOR = { Pattern = "Checker", A = Color3.fromRGB(188, 132, 192), B = Color3.fromRGB(152, 100, 162) }
local HOUSE_WALL = Color3.fromRGB(255, 232, 242)
local HOUSE_ROOF = Color3.fromRGB(190, 170, 240)

local function stroke(frame: GuiObject, color: Color3, thickness: number)
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = frame
end

-- Mur + sol de la pièce (motifs réduits)
local function roomBack(frame: Frame, w: number, h: number, context: Context?, wallRatio: number)
	local wallH = math.floor(h * wallRatio)
	local wall = Box(frame, 0, 0, w, wallH, WHITE, 0, 1)
	wall.ClipsDescendants = true
	HousePatterns.BuildWall(wall, w, wallH, (context and context.Wallpaper) or DEFAULT_WALL, 0.55)
	local floor = Box(frame, 0, wallH, w, h - wallH, WHITE, 0, 1)
	floor.ClipsDescendants = true
	HousePatterns.BuildFloor(floor, w, h - wallH, (context and context.Floor) or DEFAULT_FLOOR, 0.55)
	return wallH
end

-- Petite maison vue de face : murs, toit (trapèze en tranches), porte, fenêtres
local function miniHouse(frame: Frame, w: number, h: number, wall: Color3, roof: Color3, pattern: string?)
	-- ciel + herbe
	local sky = Box(frame, 0, 0, w, h, WHITE, 0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(196, 228, 255), Color3.fromRGB(255, 236, 244))
	gradient.Parent = sky
	Box(frame, 0, h - 12, w, 12, Color3.fromRGB(150, 222, 150), 0, 2)
	local cx = w / 2
	local bodyW, bodyH = math.min(w * 0.56, 120), h * 0.42
	local bodyTop = h - 12 - bodyH
	local body = Box(frame, cx - bodyW / 2, bodyTop, bodyW, bodyH + 1, wall, 0, 3)
	stroke(body, wall:Lerp(C.Ink, 0.45), 1.5)
	-- fenêtres + porte
	for _, side in ipairs({ -1, 1 }) do
		local win = Box(frame, cx + side * bodyW * 0.28 - 8, bodyTop + bodyH * 0.2, 16, 14, Color3.fromRGB(200, 232, 255), 0, 4)
		Round(win, UDim.new(0, 4))
		stroke(win, WHITE, 2)
	end
	local door = Box(frame, cx - 8, bodyTop + bodyH - 22, 16, 22, C.Pink, 0, 4)
	Round(door, UDim.new(0, 6))
	-- toit
	local roofH = h * 0.36
	local roofTop = bodyTop - roofH + 2
	local baseW = bodyW + 26
	local topW = 10
	local slices = 12
	for index = 1, slices do
		local k = (index - 0.5) / slices
		local sw = topW + (baseW - topW) * k
		Box(frame, cx - sw / 2, roofTop + (index - 1) * roofH / slices, sw, roofH / slices + 0.7, roof:Lerp(roof:Lerp(C.Ink, 0.25), k), 0, 5)
	end
	local eave = Box(frame, cx - baseW / 2 - 3, roofTop + roofH - 4, baseW + 6, 6, roof:Lerp(C.Ink, 0.3), 0, 6)
	Round(eave, UDim.new(0, 3))
	Heart(frame, cx, roofTop - 4, 10, C.Heart, 0, 7)
	-- motif du toit
	local function inside(x: number, y: number): boolean
		local k = (y - roofTop) / roofH
		return k > 0.15 and k < 0.9 and math.abs(x - cx) < (topW + (baseW - topW) * k) / 2 - 5
	end
	local spots = {}
	for row = 0, 3 do
		local y = roofTop + roofH * (0.3 + row * 0.18)
		for col = -4, 4 do
			local x = cx + col * 13 + (row % 2) * 6
			if inside(x, y) then
				table.insert(spots, Vector2.new(x, y))
			end
		end
	end
	if pattern == "Hearts" then
		for index, p in ipairs(spots) do
			Heart(frame, p.X, p.Y, 8, index % 3 == 0 and C.Heart or roof:Lerp(WHITE, 0.6), 0, 6)
		end
	elseif pattern == "Dots" then
		for _, p in ipairs(spots) do
			Circle(frame, p.X, p.Y, 7, 7, WHITE, 0.1, 6)
		end
	elseif pattern == "Stars" then
		for index, p in ipairs(spots) do
			Sparkle(frame, p.X, p.Y, index % 2 == 0 and 10 or 7, index % 3 == 0 and C.Butter or WHITE, 0, 6)
		end
	elseif pattern == "Flowers" then
		for index, p in ipairs(spots) do
			Circle(frame, p.X, p.Y, 8, 8, index % 3 == 0 and C.Butter or (index % 3 == 1 and C.Pink or WHITE), 0, 6)
			Circle(frame, p.X, p.Y, 3, 3, C.Butter, 0, 7)
		end
	elseif pattern == "Stripes" then
		for col = -4, 4 do
			if col % 2 == 0 then
				local x = cx + col * 8
				local k0 = math.clamp((2 * math.abs(x - cx) + 8 - topW) / (baseW - topW), 0.1, 1)
				local y0 = roofTop + roofH * k0
				if roofTop + roofH - 4 - y0 > 3 then
					Box(frame, x - 4, y0, 8, roofTop + roofH - 4 - y0, WHITE, 0.25, 6)
				end
			end
		end
	elseif pattern == "Snow" then
		for index = 0, 4 do
			Circle(frame, cx - 18 + index * 9, roofTop + roofH * 0.2, 14, 9, WHITE, 0, 6)
		end
		for index = 0, 6 do
			local icicle = Box(frame, cx - baseW / 2 + 6 + index * (baseW - 12) / 6, roofTop + roofH, 3, 6 + (index % 2) * 3, Color3.fromRGB(226, 240, 255), 0, 7)
			Round(icicle, UDim.new(0, 2))
		end
	elseif pattern == "Scales" then
		local tones = { Color3.fromRGB(120, 214, 210), Color3.fromRGB(170, 150, 240), Color3.fromRGB(255, 170, 214) }
		for index, p in ipairs(spots) do
			Circle(frame, p.X, p.Y, 13, 11, tones[index % #tones + 1], 0.1, 6)
		end
	end
end

-- Coin de pièce avec les boiseries dans la couleur choisie
local function trimPreview(frame: Frame, w: number, h: number, entry: any, context: Context?)
	local trim = entry.Color or C.Cream
	local edge = trim:Lerp(C.Ink, 0.4)
	local wallH = roomBack(frame, w, h, context, 0.72)
	-- plafond (coque) + moulure festonnée dans la couleur des boiseries
	local ceiling = Box(frame, 0, 0, w, 14, trim, 0, 3)
	stroke(ceiling, edge, 1.2)
	Box(frame, 0, 14, w, 6, trim:Lerp(WHITE, 0.25), 0, 3)
	for index = 0, math.floor(w / 14) do
		Circle(frame, 7 + index * 14, 20, 12, 9, trim, 0, 2)
	end
	-- plinthe épaisse
	local base = Box(frame, 0, wallH - 12, w, 12, trim, 0, 3)
	stroke(base, edge, 1)
	Box(frame, 0, wallH - 12, w, 3, WHITE, 0.35, 4)
	-- fenêtre (cadre épais, croisillon, rebord)
	local winX, winY, winW, winH = w * 0.3 - 26, 24, 52, 28
	local outer = Box(frame, winX, winY, winW, winH, trim, 0, 3)
	Round(outer, UDim.new(0, 7))
	stroke(outer, edge, 1.2)
	local glass = Box(frame, winX + 5, winY + 5, winW - 10, winH - 10, WHITE, 0, 4)
	glass.ClipsDescendants = true
	Round(glass, UDim.new(0, 4))
	HouseViews.Paint(glass, winW - 10, winH - 10, HouseCommon.Look("View", nil) :: any, false)
	Box(frame, winX + winW / 2 - 2, winY + 5, 4, winH - 10, trim, 0, 5)
	local sill = Box(frame, winX - 5, winY + winH - 3, winW + 10, 7, trim, 0, 6)
	Round(sill, UDim.new(0, 3))
	stroke(sill, edge, 1)
	-- encadrement de porte
	local doorX = w * 0.58
	local door = Box(frame, doorX, 26, 34, wallH - 38, trim, 0, 3)
	Round(door, UDim.new(0, 12))
	stroke(door, edge, 1.2)
	local inner = Box(frame, doorX + 6, 32, 22, wallH - 44, C.Pink:Lerp(WHITE, 0.3), 0, 4)
	Round(inner, UDim.new(0, 8))
	Circle(frame, doorX + 24, 26 + (wallH - 38) * 0.6, 4, 4, C.Gold, 0, 5)
end

-- Petite pièce meublée sous l'ambiance choisie
local function moodPreview(frame: Frame, w: number, h: number, entry: any, context: Context?)
	local wallH = roomBack(frame, w, h, context, 0.56)
	-- canapé
	local sofaY = wallH + (h - wallH) * 0.2
	local back = Box(frame, w * 0.12, sofaY - 16, 58, 22, C.Pink, 0, 3)
	Round(back, UDim.new(0, 8))
	local seat = Box(frame, w * 0.12 - 4, sofaY, 66, 16, C.Pink:Lerp(WHITE, 0.2), 0, 4)
	Round(seat, UDim.new(0, 6))
	-- lampe (halo)
	local lx = w * 0.78
	Box(frame, lx - 1.5, wallH - 26, 3, h * 0.46, C.WoodDark, 0, 3)
	local shade = Box(frame, lx - 12, wallH - 40, 24, 16, C.Butter, 0, 4)
	Round(shade, UDim.new(0, 5))
	local light = entry.Light or C.Butter
	for index, size in ipairs({ 70, 48, 30 }) do
		Circle(frame, lx, wallH - 30, size, size, light, 0.8 - index * 0.08, 2)
	end
	HouseMoods.Static(frame, w, h, entry, 6)
end

-- Grande fenêtre avec la vue
local function viewPreview(frame: Frame, w: number, h: number, entry: any, context: Context?)
	roomBack(frame, w, h, context, 1)
	local winW, winH = math.min(w - 30, 150), h - 14
	local winX, winY = (w - winW) / 2, 6
	local outer = Box(frame, winX, winY, winW, winH, C.Cream, 0, 3)
	Round(outer, UDim.new(0, 10))
	stroke(outer, C.WoodDark, 1.5)
	local glass = Box(frame, winX + 5, winY + 5, winW - 10, winH - 10, WHITE, 0, 4)
	glass.ClipsDescendants = true
	Round(glass, UDim.new(0, 7))
	HouseViews.Paint(glass, winW - 10, winH - 10, entry, false)
	Box(frame, winX + winW / 2 - 2, winY + 5, 4, winH - 10, C.Cream, 0, 5)
	-- rideaux
	for _, side in ipairs({ -1, 1 }) do
		local x = side < 0 and winX - 8 or winX + winW - 10
		local curtain = Box(frame, x, winY - 2, 18, winH + 4, C.Pink, 0, 6)
		Round(curtain, UDim.new(0, 7))
	end
end

-- Déco du jardin sur un carré de gazon
local function gardenPreview(frame: Frame, w: number, h: number, entry: any)
	local sky = Box(frame, 0, 0, w, h, WHITE, 0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(206, 234, 255), Color3.fromRGB(255, 240, 248))
	gradient.Parent = sky
	local lawn = Box(frame, -10, h * 0.62, w + 20, h * 0.6, Color3.fromRGB(150, 222, 150), 0, 2)
	Round(lawn, UDim.new(0.5, 0))
	local size = h * 0.96
	local body = Box(frame, 0, 0, 100, 100, WHITE, 1, 3)
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromOffset(w / 2, h - 2)
	local scale = Instance.new("UIScale")
	scale.Scale = size / 100
	scale.Parent = body
	Circle(frame, w / 2, h - 5, size * 0.7, 8, BLACK, 0.85, 2)
	HouseArt.PaintGarden(body, entry, true)
end

function HouseLookCards.Paint(frame: Frame, kind: string, entry: any, w: number, h: number, context: Context?)
	local ok, err = pcall(function()
		if kind == "Trim" then
			trimPreview(frame, w, h, entry, context)
		elseif kind == "Mood" then
			moodPreview(frame, w, h, entry, context)
		elseif kind == "View" then
			viewPreview(frame, w, h, entry, context)
		elseif kind == "Facade" then
			-- (Color nil = couleurs d'origine : l'aperçu les montre, pas la couleur actuelle)
			miniHouse(frame, w, h, entry.Color or HOUSE_WALL, (context and context.Roof) or HOUSE_ROOF, nil)
		elseif kind == "Roof" then
			miniHouse(frame, w, h, (context and context.Facade) or HOUSE_WALL, entry.Color or HOUSE_ROOF, nil)
		elseif kind == "RoofStyle" then
			miniHouse(frame, w, h, (context and context.Facade) or HOUSE_WALL, (context and context.Roof) or HOUSE_ROOF, entry.Pattern)
		elseif kind == "Garden" then
			gardenPreview(frame, w, h, entry)
		end
	end)
	if not ok then
		warn("[HouseLookCards] " .. tostring(kind) .. " " .. tostring(entry and entry.Id) .. " : " .. tostring(err))
	end
end

return HouseLookCards
