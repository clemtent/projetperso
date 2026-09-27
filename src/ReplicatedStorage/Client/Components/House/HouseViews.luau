--[[
	HouseViews (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseViews

	(v9.1) Ce qu'on voit par la fenêtre de la pièce (Config.House.Views,
	room.View) : jardin ensoleillé, coucher de soleil rose, ville, plage,
	sapins sous la neige, collines de cerisiers, lac de montagne, récif de
	corail, pays des bonbons, espace, ciel arc-en-ciel. Uniquement des
	Frames (≈ 15 à 40 par vue). La nuit (mode sombre) : ciel bleu nuit,
	étoiles, lune, fenêtres de la ville allumées.
	Utilisé par la pièce (fenêtre fixe), la boutique (aperçus) et la vue 3D
	(SurfaceGui de la vitre).

	API :
	  HouseViews.Paint(container, w, h, view, dark?)
	      efface puis dessine la vue dans `container` (qui doit couper son
	      contenu : ClipsDescendants) ; `view` = entrée de Config.House.Views
]]

local HousePatterns = require(script.Parent.HousePatterns)

local HouseViews = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NIGHT = Color3.fromRGB(34, 30, 88)
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Cloud = HousePatterns.Cloud
local Sparkle = HousePatterns.Sparkle
local Heart = HousePatterns.Heart
local Round = HousePatterns.Round

type View = { Kind: string?, Sky: Color3?, Horizon: Color3?, Ground: Color3? }
type Painter = (holder: Frame, w: number, h: number, view: View, dark: boolean) -> ()

local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

-- Couleur de nuit (voile bleu) si `dark`
local function nightly(color: Color3, dark: boolean, amount: number?): Color3
	if not dark then
		return color
	end
	return color:Lerp(NIGHT, amount or 0.55)
end

-- Dégradé vertical du ciel sur tout le conteneur
local function sky(holder: Frame, w: number, h: number, top: Color3, bottom: Color3, dark: boolean)
	local frame = Box(holder, 0, 0, w, h, WHITE, 0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(nightly(top, dark, 0.75), nightly(bottom, dark, 0.6))
	gradient.Parent = frame
end

-- Colline arrondie (grand ovale coupé par le bas du conteneur)
local function hill(holder: Frame, cx: number, top: number, w: number, color: Color3, z: number?)
	return Circle(holder, cx, top + w * 0.3, w, w * 0.6, color, 0, z or 3)
end

-- Soleil (jour) ou lune + étoiles (nuit)
local function sunOrMoon(holder: Frame, x: number, y: number, size: number, dark: boolean, sunColor: Color3?)
	if dark then
		local moon = Circle(holder, x, y, size, size, Color3.fromRGB(255, 244, 200), 0, 2)
		Circle(moon, size * 0.72, size * 0.3, size * 0.8, size * 0.8, NIGHT:Lerp(Color3.fromRGB(80, 70, 150), 0.4), 0, 2)
	else
		Circle(holder, x, y, size * 1.7, size * 1.7, sunColor or Color3.fromRGB(255, 240, 170), 0.6, 2)
		Circle(holder, x, y, size, size, sunColor or Color3.fromRGB(255, 226, 120), 0, 2)
	end
end

local function stars(holder: Frame, w: number, h: number, count: number, seed: number)
	for index = 1, count do
		local x = noise(index, seed) * w
		local y = noise(seed, index) * h * 0.55
		local s = 3 + noise(index + seed, 3) * 5
		if index % 3 == 0 then
			Sparkle(holder, x, y, s * 1.4, WHITE, 0.1, 2)
		else
			Circle(holder, x, y, s * 0.5, s * 0.5, WHITE, 0.15, 2)
		end
	end
end

local VIEWS: { [string]: Painter } = {}

-- ░ Jardin ensoleillé : ciel, nuages, soleil, collines, arbre rond, fleurs
VIEWS.Garden = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(150, 214, 255), view.Horizon or Color3.fromRGB(255, 226, 240), dark)
	sunOrMoon(holder, w * 0.76, h * 0.22, h * 0.2, dark)
	if dark then
		stars(holder, w, h, 7, 3)
	else
		Cloud(holder, w * 0.3, h * 0.36, w * 0.36, WHITE, 0.05, 3)
	end
	local ground = view.Ground or Color3.fromRGB(150, 222, 150)
	hill(holder, w * 0.2, h * 0.62, w * 0.9, nightly(ground:Lerp(WHITE, 0.25), dark), 3)
	hill(holder, w * 0.85, h * 0.68, w * 0.8, nightly(ground, dark), 4)
	-- arbre rond
	Box(holder, w * 0.26 - 2, h * 0.58, 4, h * 0.16, nightly(Color3.fromRGB(176, 124, 96), dark), 0, 5)
	Circle(holder, w * 0.26, h * 0.54, h * 0.24, h * 0.22, nightly(Color3.fromRGB(110, 196, 120), dark), 0, 6)
	for index = 1, 4 do
		local fx = w * (0.5 + index * 0.1)
		Circle(holder, fx, h * (0.84 + (index % 2) * 0.05), 5, 5, nightly(index % 2 == 0 and WHITE or Color3.fromRGB(255, 150, 190), dark), 0, 6)
	end
end

-- ░ Coucher de soleil rose : grand soleil qui se couche, oiseaux, collines violettes
VIEWS.Sunset = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(255, 150, 190), view.Horizon or Color3.fromRGB(255, 214, 150), dark)
	if dark then
		stars(holder, w, h, 8, 5)
		sunOrMoon(holder, w * 0.3, h * 0.25, h * 0.2, true)
	else
		Circle(holder, w * 0.5, h * 0.62, h * 0.56, h * 0.56, Color3.fromRGB(255, 236, 170), 0.35, 2)
		Circle(holder, w * 0.5, h * 0.62, h * 0.36, h * 0.36, Color3.fromRGB(255, 190, 110), 0, 2)
		for index = 0, 2 do
			Box(holder, 0, h * (0.5 + index * 0.07), w, 2, Color3.fromRGB(255, 170, 190), 0.3, 3)
		end
		-- oiseaux (deux petits "v")
		for index = 0, 1 do
			local bx, by = w * (0.2 + index * 0.14), h * (0.22 + index * 0.08)
			for _, side in ipairs({ -1, 1 }) do
				local wing = Box(holder, bx + side * 3, by, 7, 1.6, Color3.fromRGB(120, 70, 110), 0, 4)
				wing.AnchorPoint = Vector2.new(0.5, 0.5)
				wing.Rotation = side * 25
			end
		end
	end
	local ground = view.Ground or Color3.fromRGB(190, 120, 170)
	hill(holder, w * 0.15, h * 0.66, w * 0.8, nightly(ground:Lerp(WHITE, 0.2), dark), 4)
	hill(holder, w * 0.9, h * 0.7, w * 0.8, nightly(ground, dark), 5)
end

-- ░ Ville : immeubles pastel, fenêtres (allumées la nuit)
VIEWS.City = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(170, 200, 255), view.Horizon or Color3.fromRGB(240, 220, 255), dark)
	sunOrMoon(holder, w * 0.18, h * 0.2, h * 0.16, dark)
	if dark then
		stars(holder, w, h, 6, 7)
	else
		Cloud(holder, w * 0.72, h * 0.28, w * 0.3, WHITE, 0.1, 2)
	end
	local tones = { Color3.fromRGB(255, 190, 214), Color3.fromRGB(196, 180, 250), Color3.fromRGB(170, 214, 250), Color3.fromRGB(255, 220, 170), Color3.fromRGB(180, 230, 210) }
	local x = -w * 0.04
	local index = 0
	while x < w do
		index += 1
		local bw = w * (0.14 + noise(index, 1) * 0.1)
		local bh = h * (0.34 + noise(index, 2) * 0.36)
		local color = nightly(tones[index % #tones + 1], dark, 0.5)
		local building = Box(holder, x, h - bh, bw, bh + 2, color, 0, 3 + index % 2)
		Round(building, UDim.new(0, 3))
		-- fenêtres
		local lit = Color3.fromRGB(255, 226, 140)
		for row = 0, math.floor(bh / 12) - 1 do
			for col = 0, math.max(0, math.floor(bw / 10) - 1) do
				local n = noise(index * 7 + row, col)
				local on = dark and n > 0.35
				Box(building, 4 + col * 9, 6 + row * 12, 4, 5, on and lit or color:Lerp(WHITE, 0.45), on and 0 or 0.2, 2)
			end
		end
		x += bw + w * 0.01
	end
end

-- ░ Plage : mer, vagues, sable, parasol, palmier
VIEWS.Beach = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(140, 214, 255), Color3.fromRGB(226, 246, 255), dark)
	sunOrMoon(holder, w * 0.78, h * 0.18, h * 0.18, dark)
	if dark then
		stars(holder, w, h, 6, 9)
	end
	local sea = nightly(view.Horizon or Color3.fromRGB(110, 200, 230), dark)
	Box(holder, 0, h * 0.46, w, h * 0.3, sea, 0, 3)
	for index = 0, 3 do
		local wave = Box(holder, w * (index * 0.26 + 0.04), h * (0.52 + (index % 2) * 0.1), w * 0.14, 2, WHITE, 0.3, 4)
		Round(wave)
	end
	-- sable
	local sand = nightly(view.Ground or Color3.fromRGB(255, 228, 170), dark)
	hill(holder, w * 0.5, h * 0.72, w * 1.6, sand, 5)
	-- parasol
	Box(holder, w * 0.3, h * 0.6, 2, h * 0.3, nightly(WHITE, dark), 0, 6)
	local umbrella = Circle(holder, w * 0.3 + 1, h * 0.62, w * 0.3, h * 0.2, nightly(Color3.fromRGB(255, 130, 170), dark), 0, 7)
	Box(umbrella, 0, h * 0.1, w * 0.3, h * 0.1, sand, 0, 2)
	-- palmier
	Box(holder, w * 0.82, h * 0.44, 4, h * 0.4, nightly(Color3.fromRGB(190, 140, 100), dark), 0, 6).Rotation = 8
	for index = 0, 3 do
		local leaf = Circle(holder, w * 0.84, h * 0.44, w * 0.18, 6, nightly(Color3.fromRGB(100, 190, 120), dark), 0, 7)
		leaf.Rotation = -40 + index * 30
	end
end

-- ░ Sapins sous la neige : flocons, sapins blancs, bonhomme
VIEWS.Snow = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(196, 214, 255), view.Horizon or Color3.fromRGB(236, 240, 255), dark)
	if dark then
		sunOrMoon(holder, w * 0.75, h * 0.2, h * 0.16, true)
	end
	local snow = nightly(view.Ground or Color3.fromRGB(250, 252, 255), dark, 0.35)
	hill(holder, w * 0.3, h * 0.66, w * 1.1, snow, 4)
	hill(holder, w * 0.9, h * 0.72, w * 0.9, snow:Lerp(Color3.fromRGB(200, 214, 250), 0.25), 5)
	for index = 0, 2 do
		local tx = w * (0.18 + index * 0.3)
		local th = h * (0.3 + (index % 2) * 0.1)
		local ty = h * 0.7 - th
		for layer = 0, 2 do
			local lw = w * (0.1 + layer * 0.05)
			local frame = Box(holder, tx - lw / 2, ty + layer * th * 0.28, lw, th * 0.36, nightly(Color3.fromRGB(96, 170, 130), dark), 0, 6)
			Round(frame, UDim.new(0.4, 0))
			Box(frame, 2, 0, lw - 4, 4, snow, 0, 2)
		end
	end
	for index = 1, 12 do
		Circle(holder, noise(index, 4) * w, noise(4, index) * h * 0.9, 3, 3, WHITE, 0.1, 8)
	end
end

-- ░ Collines de cerisiers : arbres roses, pétales, torii au loin
VIEWS.Sakura = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(190, 220, 255), view.Horizon or Color3.fromRGB(255, 226, 238), dark)
	sunOrMoon(holder, w * 0.2, h * 0.2, h * 0.16, dark)
	-- mont (Fuji) enneigé
	local mountain = Circle(holder, w * 0.62, h * 0.62, w * 0.9, h * 0.8, nightly(Color3.fromRGB(170, 170, 220), dark), 0, 2)
	mountain.Rotation = 0
	Circle(holder, w * 0.62, h * 0.3, w * 0.3, h * 0.16, nightly(WHITE, dark, 0.3), 0, 3)
	local ground = view.Ground or Color3.fromRGB(170, 226, 160)
	hill(holder, w * 0.4, h * 0.72, w * 1.3, nightly(ground, dark), 4)
	for index = 0, 1 do
		local tx = w * (0.18 + index * 0.62)
		Box(holder, tx - 2, h * 0.56, 4, h * 0.22, nightly(Color3.fromRGB(150, 100, 90), dark), 0, 5)
		Circle(holder, tx, h * 0.52, w * 0.26, h * 0.26, nightly(Color3.fromRGB(255, 186, 214), dark), 0, 6)
		Circle(holder, tx + 6, h * 0.48, w * 0.14, h * 0.14, nightly(Color3.fromRGB(255, 214, 230), dark), 0, 7)
	end
	for index = 1, 8 do
		Heart(holder, noise(index, 6) * w, noise(6, index) * h * 0.8, 5, nightly(Color3.fromRGB(255, 170, 200), dark), 0.1, 8)
	end
end

-- ░ Lac de montagne : sommets enneigés, sapins, reflet
VIEWS.Mountains = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(150, 200, 255), view.Horizon or Color3.fromRGB(226, 240, 255), dark)
	sunOrMoon(holder, w * 0.8, h * 0.18, h * 0.14, dark)
	for index, peak in ipairs({ { 0.3, 0.26, 0.7 }, { 0.72, 0.18, 0.8 } }) do
		local cx, top, size = w * peak[1], h * peak[2], w * peak[3]
		local rock = HousePatterns.Diamond(holder, cx, top + size * 0.5, size * 0.72, nightly(index == 1 and Color3.fromRGB(150, 150, 200) or Color3.fromRGB(130, 136, 190), dark), 0, 2)
		local _ = rock
		HousePatterns.Diamond(holder, cx, top + size * 0.13, size * 0.2, nightly(WHITE, dark, 0.3), 0, 3)
	end
	local lake = nightly(view.Ground or Color3.fromRGB(120, 196, 220), dark)
	Box(holder, 0, h * 0.66, w, h * 0.34, lake, 0, 4)
	for index = 0, 2 do
		local ripple = Box(holder, w * (0.15 + index * 0.3), h * (0.76 + (index % 2) * 0.08), w * 0.16, 2, WHITE, 0.4, 5)
		Round(ripple)
	end
	for index = 0, 4 do
		local tx = w * (0.05 + index * 0.22)
		local tree = Box(holder, tx - 4, h * 0.52, 8, h * 0.16, nightly(Color3.fromRGB(80, 150, 110), dark), 0, 5)
		Round(tree, UDim.new(0.5, 0))
	end
end

-- ░ Récif de corail : eau turquoise, rayons, poissons, coraux, bulles
VIEWS.Underwater = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Horizon or Color3.fromRGB(120, 220, 230), view.Sky or Color3.fromRGB(70, 170, 220), dark)
	for index = 0, 2 do
		local ray = Box(holder, w * (0.15 + index * 0.3), -h * 0.1, w * 0.1, h * 0.9, WHITE, 0.82, 2)
		ray.Rotation = 16
	end
	local sand = nightly(view.Ground or Color3.fromRGB(240, 214, 170), dark)
	hill(holder, w * 0.5, h * 0.8, w * 1.6, sand, 4)
	for index, coral in ipairs({ { 0.16, Color3.fromRGB(255, 120, 150) }, { 0.5, Color3.fromRGB(255, 170, 90) }, { 0.84, Color3.fromRGB(190, 120, 240) } }) do
		for branch = -1, 1 do
			local piece = Box(holder, w * coral[1] + branch * 6, h * 0.62, 5, h * 0.24, nightly(coral[2], dark), 0, 5)
			piece.Rotation = branch * 18
			Round(piece)
		end
		local _ = index
	end
	for index, fish in ipairs({ { 0.3, 0.3, Color3.fromRGB(255, 200, 80) }, { 0.7, 0.44, Color3.fromRGB(255, 140, 180) } }) do
		local body = Circle(holder, w * fish[1], h * fish[2], 16, 10, nightly(fish[3], dark), 0, 6)
		local tail = Box(holder, w * fish[1] + 6, h * fish[2] - 4, 8, 8, nightly(fish[3], dark), 0, 6)
		tail.Rotation = 45
		Circle(body, 4, 3, 3, 3, Color3.fromRGB(60, 40, 70), 0, 2)
		local _ = index
	end
	for index = 1, 6 do
		Circle(holder, noise(index, 8) * w, noise(8, index) * h * 0.7, 5, 5, WHITE, 0.45, 7)
	end
end

-- ░ Pays des bonbons : collines roses, sucettes, nuages de barbe à papa
VIEWS.Candy = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(255, 200, 236), view.Horizon or Color3.fromRGB(255, 240, 200), dark)
	sunOrMoon(holder, w * 0.8, h * 0.2, h * 0.16, dark, Color3.fromRGB(255, 214, 120))
	Cloud(holder, w * 0.28, h * 0.34, w * 0.34, nightly(Color3.fromRGB(255, 220, 244), dark, 0.4), 0, 3)
	local ground = view.Ground or Color3.fromRGB(255, 170, 210)
	hill(holder, w * 0.2, h * 0.66, w * 0.9, nightly(ground:Lerp(WHITE, 0.3), dark), 4)
	hill(holder, w * 0.85, h * 0.7, w * 0.8, nightly(ground, dark), 5)
	for index, pop in ipairs({ { 0.34, Color3.fromRGB(120, 200, 255) }, { 0.66, Color3.fromRGB(255, 120, 160) } }) do
		local px = w * pop[1]
		Box(holder, px - 1.5, h * 0.54, 3, h * 0.3, nightly(WHITE, dark), 0, 6)
		local candy = Circle(holder, px, h * 0.5, h * 0.2, h * 0.2, nightly(pop[2], dark), 0, 7)
		Circle(candy, h * 0.1, h * 0.1, h * 0.12, h * 0.12, nightly(WHITE, dark), 0.2, 2)
		Circle(candy, h * 0.1, h * 0.1, h * 0.05, h * 0.05, nightly(pop[2], dark), 0, 3)
		local _ = index
	end
	for index = 1, 5 do
		Sparkle(holder, noise(index, 9) * w, noise(9, index) * h * 0.5, 6, WHITE, 0.2, 8)
	end
end

-- ░ Espace : étoiles, planète à anneaux, fusée
VIEWS.Space = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(30, 24, 70), view.Horizon or Color3.fromRGB(90, 50, 140), false)
	stars(holder, w, h * 1.6, 14, 11)
	local planet = Circle(holder, w * 0.66, h * 0.44, h * 0.34, h * 0.34, Color3.fromRGB(255, 170, 200), 0, 4)
	Circle(planet, h * 0.1, h * 0.1, h * 0.12, h * 0.08, WHITE, 0.6, 2)
	local ring = Box(holder, 0, 0, h * 0.62, h * 0.08, Color3.fromRGB(255, 226, 150), 0.1, 5)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(w * 0.66, h * 0.46)
	ring.Rotation = -18
	Round(ring)
	Circle(holder, w * 0.2, h * 0.3, h * 0.12, h * 0.12, Color3.fromRGB(170, 220, 255), 0, 4)
	-- sol lunaire
	local ground = view.Ground or Color3.fromRGB(200, 196, 220)
	hill(holder, w * 0.5, h * 0.84, w * 1.6, ground:Lerp(BLACK, dark and 0.3 or 0), 5)
	Circle(holder, w * 0.3, h * 0.92, 12, 4, ground:Lerp(BLACK, 0.2), 0, 6)
	Circle(holder, w * 0.7, h * 0.94, 16, 5, ground:Lerp(BLACK, 0.2), 0, 6)
end

-- ░ Ciel arc-en-ciel : arc-en-ciel, nuages, cœurs
VIEWS.Rainbow = function(holder, w, h, view, dark)
	sky(holder, w, h, view.Sky or Color3.fromRGB(170, 220, 255), view.Horizon or Color3.fromRGB(255, 240, 250), dark)
	if dark then
		stars(holder, w, h, 6, 13)
	end
	local colors = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 180, 100), Color3.fromRGB(255, 226, 110),
		Color3.fromRGB(140, 220, 150), Color3.fromRGB(130, 190, 255), Color3.fromRGB(190, 150, 250) }
	local base = h * 1.3
	for index, color in ipairs(colors) do
		local size = base - (index - 1) * h * 0.1
		Circle(holder, w * 0.5, h * 0.95, size * 1.2, size, nightly(color, dark, 0.35), 0, 2 + index)
	end
	Circle(holder, w * 0.5, h * 0.95, (base - 6 * h * 0.1) * 1.2, base - 6 * h * 0.1, nightly(view.Horizon or Color3.fromRGB(255, 240, 250), dark, 0.6), 0, 9)
	Cloud(holder, w * 0.16, h * 0.98, w * 0.42, nightly(WHITE, dark, 0.3), 0, 10)
	Cloud(holder, w * 0.84, h * 0.98, w * 0.42, nightly(WHITE, dark, 0.3), 0, 10)
	Heart(holder, w * 0.5, h * 0.62, h * 0.14, nightly(Color3.fromRGB(255, 120, 170), dark, 0.3), 0, 11)
end

-- Efface puis dessine la vue (nil / inconnue : jardin)
function HouseViews.Paint(container: GuiObject, w: number, h: number, view: View?, dark: boolean?)
	local old = container:FindFirstChild("View")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.Name = "View"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 1
	holder.ClipsDescendants = true
	local entry: View = view or {}
	local painter = VIEWS[entry.Kind or "Garden"] or VIEWS.Garden
	local ok, err = pcall(painter, holder, w, h, entry, dark == true)
	if not ok then
		warn("[HouseViews] " .. tostring(entry.Kind) .. " : " .. tostring(err))
	end
	holder.Parent = container
	return holder
end

return HouseViews
