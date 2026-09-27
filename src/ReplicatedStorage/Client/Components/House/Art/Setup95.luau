--[[
	Setup95 (ModuleScript) — (v9.5) 🖥️ "Dopamine Setup" : les stimuli du
	clicker deviennent de vrais objets de la maison
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Setup95
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au
	sol, objets muraux centrés).

	Bureaux gamer (1 à 5 écrans + chaise gamer vue de dos), clavier RGB,
	souris et tapis, télés DVD (sur pied / murales, du petit écran au
	cinéma géant) et leur meuble néon, écran flash info, chaînes hi-fi
	(radio-cassette -> mur de studio), moulin de jardin, vraie presse
	hydraulique, table à papier bulle, coin streaming live et plantes du
	Jardin de Dopamine en pot.
	Les écrans montrent une image fixe mais vivante (petites animations
	HouseArt) : coureur façon "Subway", live ASMR, logo DVD, flash info.
	Tout reste DANS le cadre de l'écran (le découpage ClipsDescendants ne
	marche plus si un parent est tourné).
	Les dessus (bureaux y = 50, meuble télé y = 55, table à papier bulle
	y = 52) sont déclarés dans House/HouseSurfaces (mêmes hauteurs que la 3D).
]]

local Art = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local NAVY = rgb(52, 60, 100)
local DARK = rgb(46, 48, 68)
local DARKER = rgb(30, 32, 46)
local STEEL = rgb(178, 188, 208)
local STEEL_DARK = rgb(120, 130, 152)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local LIME = rgb(140, 240, 110)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local YELLOW = rgb(255, 214, 70)
local PURPLE = rgb(150, 100, 230)
local SKIN = rgb(255, 214, 186)
local DESK_TOP = rgb(64, 68, 104)

-- Couleurs arc-en-ciel (claviers, LED)
local RAINBOW = {
	rgb(255, 92, 120),
	rgb(255, 160, 70),
	rgb(255, 222, 80),
	rgb(120, 230, 120),
	rgb(70, 210, 255),
	rgb(130, 130, 255),
	rgb(210, 110, 255),
}

-- Logo DVD : une couleur par écran (comme les rebonds du stimulus)
local DVD_COLORS = { rgb(255, 90, 150), rgb(90, 200, 255), rgb(255, 210, 70), rgb(140, 240, 120), rgb(190, 130, 255) }

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

-- Bande de LED dégradée (cyan -> magenta) avec halo qui respire
local function ledStrip(kit, parent, x, y, w, h, z, phase)
	local strip = kit.Box(parent, x, y, w, h, WHITE, 0, z)
	kit.Round(strip)
	kit.Gradient(strip, CYAN, MAGENTA, 0)
	local glow = kit.Box(parent, x - 2, y - 2, w + 4, h + 4, MAGENTA, 0.72, (z or 2) - 1)
	kit.Round(glow)
	kit.Animate(glow, "Pulse", 0.2, 1.3, phase or 0)
	return strip
end

-- Note de musique (rond + hampe + drapeau)
local function note(kit, parent, x, y, size, color, z)
	local holder = kit.Group(parent, x - size / 2, y - size / 2, size, size, z)
	kit.Blob(holder, size * 0.32, size * 0.78, size * 0.46, size * 0.36, color, { Z = 2, Outline = false, Shade = false })
	kit.Box(holder, size * 0.5, size * 0.1, size * 0.12, size * 0.7, color, 0, 2)
	kit.Line(holder, size * 0.56, size * 0.14, size * 0.84, size * 0.34, size * 0.12, color, 0, 2)
	return holder
end

-- Petite étoile de rareté (plantes)
local function star(kit, parent, cx, cy, size, color, z)
	return kit.Sparkle(parent, cx, cy, size, color, 0, z)
end

----------------------------------------------------------------------
-- 📺 Images des écrans (tout reste dans w x h)
----------------------------------------------------------------------

-- Coureur façon "Subway" : ciel couchant, immeubles, voie en perspective,
-- héros qui court, pièces, train
local function feedRunner(kit, screen, w, h)
	local sky = kit.Box(screen, 0, 0, w, h, WHITE, 0, 1)
	kit.Gradient(sky, rgb(255, 176, 120), rgb(255, 120, 186), 90)
	kit.Circle(screen, w * 0.8, h * 0.22, h * 0.24, h * 0.24, rgb(255, 240, 160), 0, 2)
	for _, b in ipairs({ { 0.02, 0.14, 0.3 }, { 0.17, 0.1, 0.2 }, { 0.68, 0.12, 0.26 }, { 0.84, 0.14, 0.18 } }) do
		kit.Box(screen, w * b[1], h * (0.52 - b[3]), w * b[2], h * b[3] + 1, rgb(160, 96, 170), 0.15, 2)
	end
	kit.Box(screen, 0, h * 0.5, w, h * 0.5, rgb(122, 204, 132), 0, 2)
	-- voie (triangle depuis l'horizon) + rails
	kit.Triangle(screen, w / 2, h * 0.46, w * 0.9, h * 0.54, rgb(126, 116, 148), 3, 0, 8)
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(screen, w / 2 + side * w * 0.02, h * 0.5, w / 2 + side * w * 0.16, h * 0.99, math.max(1, h * 0.03), rgb(236, 226, 255), 0.25, 4)
	end
	-- train dans le couloir de gauche
	local train = kit.Part(screen, w * 0.1, h * 0.58, w * 0.2, h * 0.34, RED, { Radius = 2, Z = 5, Thickness = 1, Shade = 0.2 })
	kit.Box(train, w * 0.03, h * 0.05, w * 0.14, h * 0.1, rgb(200, 236, 255), 0, 2)
	-- pièces qui flottent dans le couloir de droite
	for index, c in ipairs({ { 0.62, 0.56, 0.06 }, { 0.66, 0.66, 0.08 }, { 0.71, 0.8, 0.1 } }) do
		local coin = kit.Circle(screen, w * c[1], h * c[2], h * c[3] * 1.6, h * c[3] * 1.6, YELLOW, 0, 6)
		kit.Stroke(coin, rgb(210, 150, 40), 1, 0)
		kit.Animate(coin, "Bob", h * 0.03, 2.4, index * 0.7)
	end
	-- héros (sweat orange, casquette) au milieu
	local hero = kit.Group(screen, w * 0.44, h * 0.56, w * 0.12, h * 0.42, 7)
	local hw, hh = w * 0.12, h * 0.42
	kit.Part(hero, hw * 0.2, hh * 0.36, hw * 0.6, hh * 0.4, ORANGE, { Radius = 2, Z = 2, Thickness = 1 })
	kit.Box(hero, hw * 0.24, hh * 0.74, hw * 0.18, hh * 0.24, NAVY, 0, 1)
	kit.Box(hero, hw * 0.58, hh * 0.7, hw * 0.18, hh * 0.24, NAVY, 0, 1)
	kit.Circle(hero, hw * 0.5, hh * 0.24, hw * 0.52, hw * 0.52, SKIN, 0, 3)
	kit.Box(hero, hw * 0.22, hh * 0.08, hw * 0.56, hh * 0.1, rgb(80, 150, 255), 0, 4)
	kit.Animate(hero, "Bob", h * 0.04, 3, 0)
	-- score
	local score = kit.Text(screen, "1250", w * 0.16, h * 0.12, math.max(5, h * 0.16), WHITE, 8)
	score.TextStrokeTransparency = 0.4
end

-- Live ASMR : chambre violette, streameuse au casque qui croque un sandwich,
-- pastille LIVE, spectateurs, bulles de chat, cœurs
local function feedLive(kit, screen, w, h)
	local C = kit.C
	-- écran vertical (bureau ultime) : la streameuse au centre, sans le chat
	local tall = h > w * 1.1
	local room = kit.Box(screen, 0, 0, w, h, WHITE, 0, 1)
	kit.Gradient(room, rgb(120, 90, 200), rgb(60, 40, 110), 90)
	kit.Box(screen, 0, h * 0.78, w, h * 0.22, rgb(90, 60, 150), 0, 2) -- bureau
	-- guirlande lumineuse
	local bulbs = tall and 3 or 5
	for index = 0, bulbs - 1 do
		local size = math.min(w, h) * 0.07
		local bulb = kit.Circle(screen, w * (0.2 + index * (tall and 0.3 or 0.1)), h * (0.24 + (index % 2) * 0.04), size, size, C.Butter, 0, 2)
		kit.Animate(bulb, "Pulse", 0.5, 1.5, index)
	end
	-- streameuse
	local cx, cy, r = w * 0.34, h * 0.56, h * 0.48
	if tall then
		cx, cy, r = w * 0.5, h * 0.62, math.min(h * 0.36, w * 0.8)
	end
	kit.Blob(screen, cx, cy + r * 0.62, r * 1.1, r * 0.5, rgb(255, 140, 190), { Z = 3, Thickness = 1 }) -- sweat
	kit.Blob(screen, cx, cy - r * 0.06, r * 0.98, r * 0.9, rgb(120, 70, 60), { Z = 3, Thickness = 1, Shade = false }) -- cheveux
	local head = kit.Blob(screen, cx, cy + r * 0.04, r * 0.76, r * 0.72, SKIN, { Z = 4, Thickness = 1 })
	kit.Face(head, r * 0.38, r * 0.4, r * 0.62, { Eyes = "happy", Mouth = "o", Z = 3 })
	-- casque
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(screen, cx + side * r * 0.42, cy + r * 0.04, r * 0.2, r * 0.3, MAGENTA, { Z = 5, Thickness = 1 })
	end
	-- sandwich 🥪
	local sandwich = kit.Group(screen, cx + r * 0.2, cy + r * 0.2, r * 0.44, r * 0.3, 6)
	kit.Part(sandwich, 0, 0, r * 0.44, r * 0.1, rgb(236, 190, 120), { Radius = 2, Z = 1, Thickness = 0.8 })
	kit.Box(sandwich, 0, r * 0.1, r * 0.44, r * 0.06, LIME, 0, 2)
	kit.Part(sandwich, 0, r * 0.15, r * 0.44, r * 0.1, rgb(236, 190, 120), { Radius = 2, Z = 1, Thickness = 0.8 })
	kit.Animate(sandwich, "Bob", h * 0.02, 2.6, 0.5)
	-- LIVE (+ spectateurs sur les écrans larges)
	local liveW = tall and w * 0.62 or w * 0.22
	local liveH = tall and w * 0.24 or h * 0.15
	local live = kit.Part(screen, w * 0.05, h * 0.04, liveW, liveH, RED, { Radius = 3, Z = 7, Outline = false })
	kit.Animate(live, "Pulse", 0.25, 1.6, 0)
	kit.Text(live, "LIVE", liveW / 2, liveH / 2, math.max(4, liveH * 0.8), WHITE, 3)
	if not tall then
		kit.Text(screen, "👁 1.2K", w * 0.44, h * 0.12, math.max(4, h * 0.1), WHITE, 7)
		-- bulles de chat
		local chat = { MAGENTA, CYAN, C.Butter, LIME }
		for index, color in ipairs(chat) do
			local bubble = kit.Part(screen, w * 0.64, h * (0.1 + (index - 1) * 0.2), w * 0.32, h * 0.15, WHITE, { Radius = 3, Z = 6, Outline = false, T = 0.1 })
			kit.Box(bubble, w * 0.03, h * 0.04, w * 0.07, h * 0.07, color, 0, 2)
			kit.Box(bubble, w * 0.12, h * 0.05, w * 0.17, h * 0.04, rgb(170, 160, 200), 0, 2)
		end
	end
	-- cœurs qui montent
	for index = 1, 2 do
		local hx = if tall then w * (0.7 + index * 0.08) else w * (0.54 + index * 0.02)
		local size = math.min(h * 0.14, w * 0.3)
		local heartFrame = kit.Heart(screen, math.min(hx, w - size / 2), h * (0.66 - index * 0.14), size, C.Heart, 0, 8)
		kit.Animate(heartFrame, "Bob", h * 0.05, 1.8, index * 1.4)
	end
end

-- Logo DVD qui rebondit (dérive + montée : reste dans l'écran)
local function feedDVD(kit, screen, w, h, colorIndex: number?)
	local bg = kit.Box(screen, 0, 0, w, h, WHITE, 0, 1)
	kit.Gradient(bg, rgb(26, 22, 50), rgb(12, 10, 26), 90)
	-- étoiles de fond
	for index = 1, 5 do
		kit.Circle(screen, w * ((index * 0.37) % 1), h * ((index * 0.53) % 1), 1.5, 1.5, WHITE, 0.5, 2)
	end
	local color = DVD_COLORS[((colorIndex or 1) - 1) % #DVD_COLORS + 1]
	local lw, lh = w * 0.36, h * 0.34
	local driftBox = kit.Group(screen, w / 2 - lw / 2, h / 2 - lh / 2, lw, lh, 4)
	kit.Animate(driftBox, "Drift", (w - lw) * 0.42, 0.9, (colorIndex or 1) * 0.8)
	local logo = kit.Group(driftBox, 0, 0, lw, lh, 1)
	kit.Animate(logo, "Bob", (h - lh) * 0.4, 0.7, (colorIndex or 1) * 1.3)
	local plate = kit.Part(logo, 0, 0, lw, lh * 0.66, color, { Radius = math.max(2, lh * 0.2), Z = 1, Outline = false, Shade = 0.15 })
	local label = kit.Text(plate, "DVD", lw / 2, lh * 0.33, math.max(5, lh * 0.46), WHITE, 3)
	label.Font = Enum.Font.FredokaOne
	kit.Blob(logo, lw / 2, lh * 0.84, lw * 0.8, lh * 0.26, color, { Z = 1, Outline = false, Shade = false })
	kit.Blob(logo, lw / 2, lh * 0.84, lw * 0.26, lh * 0.1, rgb(26, 22, 50), { Z = 2, Outline = false, Shade = false })
	-- coin qui scintille (le fameux "coin parfait")
	local corner = kit.Sparkle(screen, w * 0.9, h * 0.14, math.max(5, h * 0.16), rgb(255, 240, 170), 0, 5)
	kit.Animate(corner, "Breathe", 0.2, 1.5, 0)
end

-- Flash info : studio bleu, présentateur, bandeau rouge et texte qui défile
local function feedNews(kit, screen, w, h)
	local studio = kit.Box(screen, 0, 0, w, h, WHITE, 0, 1)
	kit.Gradient(studio, rgb(70, 130, 230), rgb(30, 60, 140), 90)
	-- globe du studio
	local globe = kit.Circle(screen, w * 0.78, h * 0.34, h * 0.42, h * 0.42, rgb(120, 190, 255), 0.35, 2)
	kit.Stroke(globe, WHITE, 1, 0.5)
	kit.Box(screen, w * 0.78 - h * 0.21, h * 0.33, h * 0.42, 1, WHITE, 0.5, 3)
	-- présentateur
	local cx = w * 0.36
	kit.Blob(screen, cx, h * 0.7, h * 0.56, h * 0.36, NAVY, { Z = 3, Thickness = 1 }) -- veste
	kit.Box(screen, cx - h * 0.03, h * 0.56, h * 0.06, h * 0.16, RED, 0, 4) -- cravate
	local head = kit.Blob(screen, cx, h * 0.38, h * 0.3, h * 0.3, SKIN, { Z = 4, Thickness = 1 })
	kit.Face(head, h * 0.15, h * 0.16, h * 0.24, { Mouth = "o", Z = 3 })
	kit.Blob(screen, cx, h * 0.25, h * 0.3, h * 0.12, rgb(90, 60, 40), { Z = 5, Outline = false, Shade = false })
	-- bandeau "BREAKING"
	local bar = kit.Box(screen, 0, h * 0.64, w, h * 0.17, RED, 0, 6)
	local breaking = kit.Text(bar, "BREAKING", w * 0.26, h * 0.085, math.max(4, h * 0.12), WHITE, 3)
	breaking.Font = Enum.Font.FredokaOne
	local ticker = kit.Box(screen, 0, h * 0.81, w, h * 0.19, WHITE, 0, 6)
	local line = kit.Group(ticker, 0, 0, w, h * 0.19, 2, true)
	local text = kit.Text(line, "DOPAMINE +1000% • CLICKS AT ALL-TIME HIGH •", w * 0.5, h * 0.095, math.max(4, h * 0.1), rgb(40, 40, 70), 2)
	text.Size = UDim2.fromOffset(w * 1.3, h * 0.19)
	kit.Animate(text, "Drift", w * 0.12, 0.6, 0)
	local liveDot = kit.Circle(screen, w * 0.92, h * 0.1, h * 0.08, h * 0.08, RED, 0, 7)
	kit.Animate(liveDot, "Pulse", 0.6, 2, 0)
end

local FEEDS = {
	Runner = feedRunner,
	Live = feedLive,
	DVD = feedDVD,
	News = feedNews,
}

-- Écran encadré : cadre sombre + image (feed) + reflet ; renvoie le cadre
local function monitorFrame(kit, parent, x, y, w, h, feed: string, z: number, options: any?)
	local opts = options or {}
	local bezelColor = opts.Bezel or DARKER
	local bezel = kit.Part(parent, x, y, w, h, bezelColor, { Radius = opts.Radius or 3, Z = z, Thickness = 1.2, Shade = 0.1 })
	local inset = opts.Inset or math.max(1.6, math.min(w, h) * 0.06)
	local chin = opts.Chin or 0
	local sw, sh = w - inset * 2, h - inset * 2 - chin
	local screen = kit.Group(bezel, inset, inset, sw, sh, 2, true)
	local painter = FEEDS[feed] or feedDVD
	painter(kit, screen, sw, sh, opts.Color)
	-- reflet en biais (vitre)
	local glare = kit.Box(screen, sw * 0.62, -sh * 0.1, sw * 0.08, sh * 1.2, WHITE, 0.86, 20)
	glare.Rotation = 18
	if opts.Curved then
		-- écran incurvé : bords assombris (on devine la courbe)
		local shade = kit.Box(screen, 0, 0, sw, sh, rgb(10, 10, 30), 0, 19)
		local grad = Instance.new("UIGradient")
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.2, 1),
			NumberSequenceKeypoint.new(0.8, 1),
			NumberSequenceKeypoint.new(1, 0.35),
		})
		grad.Parent = shade
	end
	if chin > 0 then
		local led = kit.Circle(bezel, w / 2, h - chin / 2 - inset / 2, math.max(1.5, chin * 0.35), math.max(1.5, chin * 0.35), LIME, 0, 3)
		kit.Animate(led, "Pulse", 0.4, 1, x)
	end
	return bezel
end

-- Pied d'écran (col + socle) de l'écran vers baseY
local function monitorStand(kit, parent, cx, topY, baseY, z)
	kit.Part(parent, cx - 2, topY, 4, math.max(1, baseY - topY - 2), STEEL, { Radius = 1, Z = z, Thickness = 1 })
	kit.Blob(parent, cx, baseY - 1.4, 18, 3.2, STEEL_DARK, { Z = z, Thickness = 1 })
end

----------------------------------------------------------------------
-- 🖥️ Bureaux gamer
----------------------------------------------------------------------

-- Chaise gamer vue de dos (au milieu, devant le bureau)
local function chairBack(kit, parent, cx, top, accent, z)
	local zz = z or 8
	for _, dx in ipairs({ -15, 0, 15 }) do
		kit.Line(parent, cx, 91, cx + dx, 97, 3, DARKER, 0, zz)
		kit.Circle(parent, cx + dx, 98, 4.5, 4.5, DARK, 0, zz + 1)
	end
	kit.Part(parent, cx - 2, 80, 4, 12, STEEL, { Radius = 1, Z = zz, Thickness = 1 })
	kit.Blob(parent, cx, 81, 36, 8, DARK, { Z = zz + 1, Thickness = 1.2 })
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(parent, cx + side * 17 - 3, 68, 6, 13, DARKER, { Radius = 2, Z = zz + 1, Thickness = 1 })
		kit.Part(parent, cx + side * 17 - 4, 66, 8, 4, DARK, { Radius = 2, Z = zz + 2, Thickness = 1 })
	end
	local back = kit.Part(parent, cx - 14, top, 28, 78 - top, DARK, { Radius = 9, Z = zz + 3, Shine = true, Thickness = 1.4 })
	local bw = 28
	-- bandes "course" colorées
	kit.Box(back, 5, 6, 4, 78 - top - 12, accent, 0, 2)
	kit.Box(back, bw - 9, 6, 4, 78 - top - 12, accent, 0, 2)
	-- coussin de tête + petit cerveau (logo Dopamine)
	kit.Part(parent, cx - 8, top + 3, 16, 7, accent, { Radius = 3, Z = zz + 4, Thickness = 1 })
	kit.Heart(back, bw / 2, 78 - top - 12, 8, WHITE, 0.2, 3)
end

-- Plateau + pieds + LED du bureau (dessus à y = 50)
local function deskBase(kit, body, width: number?)
	local w = width or 98
	local x = (100 - w) / 2
	for _, lx in ipairs({ x + 4, x + w - 11 }) do
		kit.Part(body, lx, 54, 7, 45, DARK, { Radius = 2, Z = 1, Thickness = 1.2 })
		kit.Blob(body, lx + 3.5, 99, 11, 3, DARKER, { Z = 1, Outline = false, Shade = false })
	end
	kit.Part(body, x + 11, 55, w - 22, 12, DARKER, { Radius = 2, Z = 1, Thickness = 1 }) -- panneau arrière
	ledStrip(kit, body, x + 12, 56, w - 24, 1.6, 3, 0)
	local top = kit.Part(body, x, 49.5, w, 6, DESK_TOP, { Radius = 3, Z = 4, Shine = true, Thickness = 1.4 })
	local edge = kit.Box(top, 3, 4.2, w - 6, 1.2, WHITE, 0, 2)
	kit.Gradient(edge, CYAN, MAGENTA, 0)
	return top
end

-- Tour de PC vitrée à ventilateurs (au sol)
local function pcTower(kit, parent, x, y, w, h, z)
	local tower = kit.Part(parent, x, y, w, h, DARK, { Radius = 3, Z = z, Shine = true, Thickness = 1.2 })
	local glass = kit.Part(tower, 2.5, 3, w - 5, h - 10, rgb(20, 24, 44), { Radius = 2, Z = 2, Outline = CYAN, Thickness = 1 })
	for index, color in ipairs({ CYAN, MAGENTA }) do
		local fan = kit.Circle(glass, (w - 5) / 2, (h - 10) * (index == 1 and 0.28 or 0.66), (w - 5) * 0.7, (w - 5) * 0.7, DARKER, 0, 2)
		kit.Stroke(fan, color, 1.4, 0)
		local rotor = kit.Pivot(fan, (w - 5) * 0.35, (w - 5) * 0.35, 2)
		for k = 0, 2 do
			local arm = kit.Pivot(rotor, 0, 0, 1)
			arm.Rotation = k * 120
			local blade = kit.Box(arm, -1, -(w - 5) * 0.3, 2, (w - 5) * 0.24, kit.Lighten(color, 0.3), 0.1, 1)
			kit.Round(blade)
		end
		kit.Animate(rotor, "Spin", 1, 0.9, index)
	end
	kit.Circle(tower, w / 2, h - 3.5, 3, 3, LIME, 0, 3)
	return tower
end

-- Lampe de bureau néon (petit cercle lumineux)
local function deskLamp(kit, parent, x, baseY, color, z)
	kit.Blob(parent, x, baseY - 1.2, 10, 2.8, DARK, { Z = z, Outline = false })
	kit.Line(parent, x, baseY - 2, x + 3, baseY - 14, 1.6, STEEL_DARK, 0, z)
	local ring = kit.Circle(parent, x + 3, baseY - 18, 9, 9, WHITE, 0.2, z + 1)
	kit.Stroke(ring, color, 1.6, 0)
	local glow = kit.Circle(parent, x + 3, baseY - 18, 14, 14, color, 0.72, z)
	kit.Animate(glow, "Pulse", 0.2, 1.1, x)
end

-- 1 écran : coureur. Lampe néon, casque sur support, tour au sol
Art.SetupDeskSolo = function(body, kit, _item)
	local C = kit.C
	deskBase(kit, body)
	monitorStand(kit, body, 50, 38, 50, 3)
	monitorFrame(kit, body, 26, 11, 48, 29, "Runner", 5, { Chin = 2.5 })
	deskLamp(kit, body, 12, 50, MAGENTA, 5)
	-- casque sur son support
	kit.Part(body, 84, 34, 2.5, 16, STEEL, { Radius = 1, Z = 5, Thickness = 1 })
	kit.Blob(body, 85, 49, 10, 2.5, DARK, { Z = 5, Outline = false })
	local band = kit.Part(body, 79, 30, 13, 13, DARK, { Radius = -1, T = 1, Outline = CYAN, Thickness = 2.2, Shade = false, Z = 6 })
	local _ = band
	kit.Blob(body, 79.5, 40, 5, 7, CYAN, { Z = 7, Thickness = 1 })
	kit.Blob(body, 91.5, 40, 5, 7, CYAN, { Z = 7, Thickness = 1 })
	pcTower(kit, body, 72, 66, 16, 33, 6)
	chairBack(kit, body, 42, 57, MAGENTA, 8)
	kit.Sparkle(body, 8, 12, 8, C.Butter, 0, 9)
	return { Glow = CYAN }
end

-- 2 écrans : coureur + live
Art.SetupDeskDuo = function(body, kit, _item)
	local C = kit.C
	deskBase(kit, body)
	monitorStand(kit, body, 27, 38, 50, 3)
	monitorStand(kit, body, 73, 38, 50, 3)
	monitorFrame(kit, body, 4, 12, 45, 27, "Runner", 5, { Chin = 2.5 })
	monitorFrame(kit, body, 51, 12, 45, 27, "Live", 5, { Chin = 2.5 })
	pcTower(kit, body, 73, 64, 17, 35, 6)
	chairBack(kit, body, 44, 57, CYAN, 8)
	kit.Sparkle(body, 50, 6, 8, C.Butter, 0, 9)
	return { Glow = MAGENTA }
end

-- 3 écrans : live, coureur (au centre, plus haut), live ; écrans des côtés
-- tournés vers le joueur (plus étroits, bord foncé)
Art.SetupDeskTrio = function(body, kit, _item)
	local C = kit.C
	-- halo néon derrière
	local halo = kit.Part(body, 10, 4, 80, 40, PURPLE, { Radius = 18, Z = 1, Outline = false, Shade = false, T = 0.78 })
	kit.Animate(halo, "Pulse", 0.12, 1, 0)
	deskBase(kit, body)
	monitorStand(kit, body, 50, 36, 50, 3)
	monitorStand(kit, body, 16, 38, 50, 3)
	monitorStand(kit, body, 84, 38, 50, 3)
	monitorFrame(kit, body, 1, 15, 31, 24, "Live", 5, { Color = 2 })
	monitorFrame(kit, body, 68, 15, 31, 24, "Live", 5, { Color = 3 })
	for _, x in ipairs({ 1, 96.5 }) do
		kit.Box(body, x, 15.5, 2.5, 23, rgb(14, 14, 24), 0.3, 7) -- bord tourné
	end
	monitorFrame(kit, body, 31, 9, 38, 28, "Runner", 6, { Chin = 2.5 })
	pcTower(kit, body, 75, 62, 18, 37, 6)
	chairBack(kit, body, 44, 57, LIME, 8)
	kit.Sparkle(body, 94, 6, 8, C.Butter, 0, 9)
	return { Glow = PURPLE }
end

-- 5 écrans : grand écran incurvé (coureur), 2 écrans au-dessus (flash
-- info, DVD), 2 écrans verticaux (live) ; halo arc-en-ciel, LED partout
Art.SetupDeskUltra = function(body, kit, _item)
	local C = kit.C
	-- halo arc-en-ciel qui respire
	local halo = kit.Part(body, 2, -2, 96, 50, WHITE, { Radius = 20, Z = 1, Outline = false, Shade = false, T = 0.6 })
	kit.Gradient(halo, RAINBOW[1], RAINBOW[6], 0)
	kit.Animate(halo, "Pulse", 0.2, 0.9, 0)
	deskBase(kit, body)
	-- bras d'écrans (poteau central)
	kit.Part(body, 48.5, 4, 3, 46, STEEL_DARK, { Radius = 1, Z = 2, Thickness = 1 })
	kit.Blob(body, 50, 48.6, 16, 3, STEEL_DARK, { Z = 3, Thickness = 1 })
	monitorFrame(kit, body, 22, 1, 27, 17, "News", 4)
	monitorFrame(kit, body, 51, 1, 27, 17, "DVD", 4, { Color = 4 })
	monitorFrame(kit, body, 15, 20, 70, 25, "Runner", 6, { Curved = true, Chin = 2.5 })
	-- écrans verticaux sur pieds
	monitorStand(kit, body, 8, 44, 50, 3)
	monitorStand(kit, body, 92, 44, 50, 3)
	monitorFrame(kit, body, 0, 12, 15, 33, "Live", 5, { Color = 1 })
	monitorFrame(kit, body, 85, 12, 15, 33, "Live", 5, { Color = 2 })
	-- tour vitrée à gauche au sol + enceintes RGB sur le bureau
	pcTower(kit, body, 8, 62, 18, 37, 6)
	for index, x in ipairs({ 17, 79 }) do
		local speaker = kit.Part(body, x, 40, 5, 9.5, DARK, { Radius = 2, Z = 7, Thickness = 1 })
		local cone = kit.Circle(speaker, 2.5, 6, 3.5, 3.5, RAINBOW[index * 2], 0, 2)
		kit.Animate(cone, "Pulse", 0.4, 2, index)
	end
	chairBack(kit, body, 54, 56, MAGENTA, 8)
	for index, pos in ipairs({ { 3, 6 }, { 97, 52 } }) do
		local s = kit.Sparkle(body, pos[1], pos[2], 8, index == 2 and CYAN or C.Butter, 0, 9)
		kit.Animate(s, "Breathe", 0.2, 1.4, index)
	end
	return { Glow = MAGENTA }
end

----------------------------------------------------------------------
-- ⌨️ Clavier RGB, 🖱️ souris gamer
----------------------------------------------------------------------

Art.SetupKeyboard = function(body, kit, _item)
	-- câble qui remonte derrière
	kit.Line(body, 50, 60, 54, 44, 2, DARKER, 0, 1)
	kit.Line(body, 54, 44, 66, 38, 2, DARKER, 0, 1)
	local glow = kit.Part(body, 0, 60, 100, 38, MAGENTA, { Radius = 10, Z = 1, Outline = false, Shade = false, T = 0.7 })
	kit.Gradient(glow, CYAN, MAGENTA, 0)
	kit.Animate(glow, "Pulse", 0.2, 1.3, 0)
	local board = kit.Part(body, 2, 62, 96, 32, DARK, { Radius = 6, Z = 2, Shine = true, Thickness = 1.5 })
	-- 4 rangées de touches arc-en-ciel (couleur selon la colonne)
	local cols = 11
	local keyW, keyH, gap = 6.8, 5, 1.4
	for row = 0, 3 do
		local count = row == 3 and 3 or cols
		for col = 0, count - 1 do
			local x, w = 4 + col * (keyW + gap), keyW
			if row == 3 then
				-- rangée du bas : Ctrl, grande barre d'espace, flèche
				x = ({ 4, 20.4, 77.8 })[col + 1]
				w = ({ 14, 55, 14 })[col + 1]
			end
			local hue = RAINBOW[math.clamp(math.floor((x + w / 2) / 96 * #RAINBOW) + 1, 1, #RAINBOW)]
			local key = kit.Box(board, x, 4 + row * (keyH + gap), w, keyH, hue, 0, 3)
			kit.Round(key, 1.5)
			kit.Box(key, 1, 0.6, w - 2, 1.4, WHITE, 0.55, 2)
		end
	end
	-- touches qui s'enfoncent (petit clignement de lumière)
	for index, pos in ipairs({ { 2, 1 }, { 6, 2 }, { 9, 0 } }) do
		local flash = kit.Box(board, 4 + pos[1] * (keyW + gap), 4 + pos[2] * (keyH + gap), keyW, keyH, WHITE, 0.4, 5)
		kit.Round(flash, 1.5)
		kit.Animate(flash, "Pulse", 0.6, 2.2, index * 1.3)
	end
	-- repose-poignets
	kit.Part(body, 16, 92, 68, 6, rgb(80, 84, 116), { Radius = 3, Z = 3, Thickness = 1 })
	return { Glow = CYAN, Flat = false }
end

Art.SetupMouse = function(body, kit, _item)
	-- tapis (bord RGB)
	local pad = kit.Blob(body, 50, 90, 98, 18, DARKER, { Z = 1, Outline = MAGENTA, Thickness = 2 })
	kit.Blob(pad, 49, 9, 84, 10, DARK, { Z = 2, Outline = false, Shade = false })
	-- câble
	kit.Line(body, 50, 34, 56, 18, 2.2, DARKER, 0, 2)
	kit.Line(body, 56, 18, 70, 8, 2.2, DARKER, 0, 2)
	-- souris
	local glow = kit.Blob(body, 50, 64, 50, 58, CYAN, { Z = 2, Outline = false, Shade = false, T = 0.72 })
	kit.Animate(glow, "Pulse", 0.2, 1.4, 0)
	local mouse = kit.Blob(body, 50, 64, 42, 54, DARK, { Z = 3, Shine = true, Thickness = 1.6 })
	kit.Box(mouse, 20.2, 2, 1.6, 20, DARKER, 0, 2) -- séparation des boutons
	local wheel = kit.Part(mouse, 18, 7, 6, 11, CYAN, { Radius = 3, Z = 3, Thickness = 1 })
	kit.Gradient(wheel, CYAN, MAGENTA, 90)
	kit.Animate(wheel, "Pulse", 0.3, 2, 0.5)
	-- boutons latéraux + logo
	kit.Part(mouse, 1, 24, 4, 6, STEEL, { Radius = 2, Z = 3, Thickness = 0.8 })
	kit.Part(mouse, 1, 32, 4, 6, STEEL, { Radius = 2, Z = 3, Thickness = 0.8 })
	local logo = kit.Heart(mouse, 21, 38, 10, MAGENTA, 0, 3)
	kit.Animate(logo, "Pulse", 0.4, 1.2, 1)
	-- petit "clic !"
	local spark = kit.Sparkle(body, 26, 36, 10, rgb(255, 240, 170), 0, 5)
	kit.Animate(spark, "Breathe", 0.25, 2, 0)
	return { Glow = CYAN }
end

----------------------------------------------------------------------
-- 📺 Télés DVD
----------------------------------------------------------------------

-- Petite télé (sur un meuble) : antenne lapin, pieds courts
Art.SetupTVSmall = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 26, 34, 6, 2, STEEL_DARK, 0, 1)
	kit.Line(body, 50, 26, 68, 4, 2, STEEL_DARK, 0, 1)
	kit.Circle(body, 34, 6, 5, 5, C.Pink, 0, 2)
	kit.Circle(body, 68, 4, 5, 5, C.Mint, 0, 2)
	for _, x in ipairs({ 24, 76 }) do
		kit.Part(body, x - 3, 86, 6, 13, DARK, { Radius = 2, Z = 1, Thickness = 1 })
	end
	local case = kit.Part(body, 6, 24, 88, 64, rgb(255, 170, 200), { Radius = 12, Z = 2, Shine = true, Shade = 0.18 })
	local _ = case
	monitorFrame(kit, body, 12, 30, 62, 50, "DVD", 3, { Radius = 8, Color = 1, Bezel = rgb(60, 50, 80) })
	for index, color in ipairs({ C.Butter, C.Mint }) do
		local knob = kit.Blob(body, 84, 40 + (index - 1) * 14, 10, 10, color, { Z = 4, Shine = true })
		kit.Box(knob, 4.2, 1, 1.6, 4, kit.OutlineOf(color), 0, 3)
	end
	for i = 0, 2 do
		kit.Box(body, 79, 64 + i * 4, 11, 1.6, kit.OutlineOf(rgb(255, 170, 200)), 0.3, 4)
	end
	return { Glow = rgb(255, 120, 180) }
end

-- Télé plate sur petits pieds
Art.SetupTVMedium = function(body, kit, _item)
	for _, x in ipairs({ 14, 86 }) do
		kit.Line(body, x, 86, x + (x < 50 and -5 or 5), 99, 3, STEEL_DARK, 0, 1)
	end
	monitorFrame(kit, body, 2, 30, 96, 58, "DVD", 2, { Color = 2, Chin = 3, Inset = 2.5 })
	return { Glow = CYAN }
end

-- Grande télé : pied central + barre de son
Art.SetupTVLarge = function(body, kit, _item)
	kit.Part(body, 44, 80, 12, 12, STEEL_DARK, { Radius = 2, Z = 1, Thickness = 1 })
	kit.Blob(body, 50, 97, 46, 6, STEEL_DARK, { Z = 1, Thickness = 1 })
	local halo = kit.Part(body, -2, 22, 104, 64, CYAN, { Radius = 10, Z = 1, Outline = false, Shade = false, T = 0.8 })
	kit.Animate(halo, "Pulse", 0.12, 1, 0)
	monitorFrame(kit, body, 0, 24, 100, 60, "DVD", 2, { Color = 3, Inset = 2 })
	local bar = kit.Part(body, 22, 88, 56, 7, DARK, { Radius = 3, Z = 3, Thickness = 1 })
	for i = 0, 9 do
		kit.Box(bar, 4 + i * 5, 2.5, 2.4, 2, STEEL, 0.2, 2)
	end
	return { Glow = CYAN }
end

-- Télé cinéma géante sur chevalet (pieds écartés + barre), rétroéclairage
Art.SetupTVGiant = function(body, kit, _item)
	local C = kit.C
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(body, 50 + side * 26, 60, 50 + side * 38, 99, 3.5, DARK, 0, 1)
		kit.Blob(body, 50 + side * 38, 99, 10, 3, DARKER, { Z = 1, Outline = false })
	end
	kit.Box(body, 22, 84, 56, 3, DARK, 0, 1)
	local halo = kit.Part(body, -4, 0, 108, 70, WHITE, { Radius = 14, Z = 1, Outline = false, Shade = false, T = 0.62 })
	kit.Gradient(halo, MAGENTA, CYAN, 0)
	kit.Animate(halo, "Pulse", 0.2, 0.8, 0)
	monitorFrame(kit, body, 0, 4, 100, 62, "DVD", 2, { Color = 5, Inset = 1.8 })
	-- barre de son + caisson de basses
	local bar = kit.Part(body, 18, 70, 64, 7, DARK, { Radius = 3, Z = 3, Thickness = 1 })
	ledStrip(kit, bar, 4, 5, 56, 1, 3, 1)
	local sub = kit.Part(body, 74, 80, 20, 19, DARK, { Radius = 4, Z = 3, Thickness = 1.2 })
	local cone = kit.Circle(sub, 10, 9.5, 13, 13, DARKER, 0, 2)
	kit.Stroke(cone, MAGENTA, 1.2, 0)
	kit.Animate(cone, "Breathe", 0.06, 3, 0)
	kit.Sparkle(body, 8, 76, 9, C.Butter, 0, 4)
	return { Glow = MAGENTA }
end

-- Support mural (plaque + bras) derrière une télé murale
local function wallBracket(kit, body, cx, top, bottom)
	kit.Part(body, cx - 12, top, 24, bottom - top, rgb(90, 96, 120), { Radius = 3, Z = 1, Thickness = 1 })
	for _, dy in ipairs({ 3, bottom - top - 6 }) do
		for _, dx in ipairs({ -8, 5 }) do
			kit.Circle(body, cx + dx + 1.5, top + dy + 1.5, 2.4, 2.4, STEEL, 0, 2)
		end
	end
end

Art.SetupTVWallMedium = function(body, kit, _item)
	wallBracket(kit, body, 50, 14, 86)
	monitorFrame(kit, body, 2, 20, 96, 60, "DVD", 3, { Color = 2, Chin = 3, Inset = 2.5 })
	return { Glow = CYAN, WallShadow = Vector2.new(96, 60) }
end

Art.SetupTVWallLarge = function(body, kit, _item)
	wallBracket(kit, body, 50, 12, 88)
	local halo = kit.Part(body, -3, 15, 106, 70, CYAN, { Radius = 12, Z = 2, Outline = false, Shade = false, T = 0.74 })
	kit.Animate(halo, "Pulse", 0.14, 1, 0)
	monitorFrame(kit, body, 0, 18, 100, 64, "DVD", 3, { Color = 3, Inset = 2 })
	return { Glow = CYAN, WallShadow = Vector2.new(100, 64) }
end

Art.SetupTVWallGiant = function(body, kit, _item)
	wallBracket(kit, body, 50, 10, 90)
	local halo = kit.Part(body, -5, 11, 110, 78, WHITE, { Radius = 14, Z = 2, Outline = false, Shade = false, T = 0.6 })
	kit.Gradient(halo, MAGENTA, CYAN, 0)
	kit.Animate(halo, "Pulse", 0.2, 0.8, 0)
	monitorFrame(kit, body, 0, 14, 100, 70, "DVD", 3, { Color = 5, Inset = 1.8 })
	local s = kit.Sparkle(body, 96, 12, 9, kit.C.Butter, 0, 6)
	kit.Animate(s, "Breathe", 0.25, 1.4, 0)
	return { Glow = MAGENTA, WallShadow = Vector2.new(100, 70) }
end

-- Écran "flash info" mural
Art.SetupNewsTV = function(body, kit, _item)
	wallBracket(kit, body, 50, 16, 84)
	monitorFrame(kit, body, 4, 20, 92, 58, "News", 3, { Inset = 2.5 })
	local tag = kit.Part(body, 6, 12, 26, 9, RED, { Radius = 3, Z = 5, Thickness = 1 })
	kit.Text(tag, "NEWS", 13, 4.5, 6.5, WHITE, 3)
	return { Glow = rgb(120, 180, 255), WallShadow = Vector2.new(92, 58) }
end

-- Meuble télé néon (dessus à y = 55) : portes vitrées, console, disques
Art.SetupTVStand = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 8, 88 }) do
		kit.Part(body, x, 93, 5, 7, DARKER, { Radius = 2, Z = 1, Thickness = 1 })
	end
	local cab = kit.Part(body, 2, 58, 96, 36, rgb(70, 64, 110), { Radius = 5, Z = 2, Shine = true, Shade = 0.2 })
	local top = kit.Part(body, 0, 54.5, 100, 5.5, rgb(96, 90, 140), { Radius = 3, Z = 3, Thickness = 1.4 })
	local _ = top
	ledStrip(kit, body, 4, 60.5, 92, 1.6, 4, 0)
	-- portes vitrées (à gauche et à droite) avec disques
	for index, x in ipairs({ 4, 68 }) do
		local door = kit.Part(cab, x, 6, 24, 26, rgb(36, 32, 64), { Radius = 3, Z = 2, Outline = index == 1 and CYAN or MAGENTA, Thickness = 1.2 })
		for k = 0, 3 do
			kit.Box(door, 3 + k * 5, 6, 3.5, 17, RAINBOW[(k + index * 2) % #RAINBOW + 1], 0.1, 2)
		end
		kit.Box(door, 18, 2, 1.6, 22, WHITE, 0.75, 3)
	end
	-- niche du milieu : console + manette
	local niche = kit.Part(cab, 30, 6, 36, 26, rgb(30, 26, 52), { Radius = 3, Z = 2, Outline = false })
	local console = kit.Part(niche, 5, 12, 26, 9, WHITE, { Radius = 3, Z = 2, Thickness = 1 })
	local light = kit.Box(console, 3, 6, 20, 1.2, CYAN, 0, 2)
	kit.Animate(light, "Pulse", 0.5, 1.2, 0)
	kit.Blob(niche, 18, 5, 14, 6, MAGENTA, { Z = 2, Thickness = 1 })
	kit.Sparkle(body, 94, 46, 8, C.Butter, 0, 5)
	return { Glow = MAGENTA }
end

----------------------------------------------------------------------
-- 🎧 Chaînes hi-fi
----------------------------------------------------------------------

-- Haut-parleur rond (membrane qui "respire")
local function driver(kit, parent, cx, cy, size, ring, z, phase)
	kit.Circle(parent, cx, cy, size, size, rgb(236, 230, 250), 0, z)
	local cone = kit.Circle(parent, cx, cy, size * 0.78, size * 0.78, rgb(70, 64, 96), 0, z + 1)
	kit.Stroke(cone, ring, 1.2, 0)
	kit.Circle(cone, size * 0.39, size * 0.39, size * 0.28, size * 0.28, ring, 0, 2)
	kit.Animate(cone, "Breathe", 0.06, 3, phase or 0)
	return cone
end

-- Radio-cassette lofi (poignée, 2 haut-parleurs, cassette qui tourne)
Art.SetupHiFiBoombox = function(body, kit, _item)
	local C = kit.C
	local shell = rgb(190, 160, 250)
	kit.Line(body, 80, 40, 92, 6, 2, STEEL_DARK, 0, 1) -- antenne
	kit.Circle(body, 92, 6, 4, 4, C.Pink, 0, 2)
	local handle = kit.Part(body, 22, 24, 56, 18, shell, { Radius = 8, T = 1, Outline = kit.OutlineOf(shell), Thickness = 4, Shade = false, Z = 1 })
	local _ = handle
	local case = kit.Part(body, 4, 38, 92, 58, shell, { Radius = 12, Z = 2, Shine = true, Shade = 0.2 })
	kit.Box(case, 6, 6, 80, 5, kit.Lighten(shell, 0.4), 0, 2)
	driver(kit, body, 24, 70, 30, MAGENTA, 3, 0)
	driver(kit, body, 76, 70, 30, CYAN, 3, 1.5)
	-- cassette au milieu
	local tape = kit.Part(body, 38, 58, 24, 20, rgb(60, 50, 90), { Radius = 3, Z = 4, Thickness = 1.2 })
	kit.Box(tape, 3, 3, 18, 6, C.Butter, 0, 2)
	for _, x in ipairs({ 7, 17 }) do
		local reel = kit.Pivot(tape, x, 13, 3)
		kit.Circle(reel, 0, 0, 7, 7, WHITE, 0, 1)
		kit.Box(reel, -0.8, -3, 1.6, 6, rgb(60, 50, 90), 0, 2)
		kit.Animate(reel, "Spin", 1, 0.6, x)
	end
	-- boutons
	for i, color in ipairs({ RED, C.Butter, C.Mint, C.Sky }) do
		kit.Part(body, 36 + (i - 1) * 7.5, 44, 6, 6, color, { Radius = 2, Z = 4, Thickness = 1 })
	end
	for i, pos in ipairs({ { 10, 26 }, { 90, 30 } }) do
		local n = note(kit, body, pos[1], pos[2], 12, i == 1 and C.PinkDeep or PURPLE, 6)
		kit.Animate(n, "Bob", 2.5, 1.2, i * 1.1)
	end
	return { Glow = rgb(210, 170, 255) }
end

-- Mini-chaîne CD : unité centrale (écran bleu, égaliseur) + 2 enceintes,
-- un CD qui tourne sur le dessus
Art.SetupHiFiCD = function(body, kit, _item)
	local C = kit.C
	for index, x in ipairs({ 2, 72 }) do
		local box = kit.Part(body, x, 44, 26, 54, rgb(70, 66, 100), { Radius = 5, Z = 1, Shine = true, Shade = 0.2 })
		local _ = box
		driver(kit, body, x + 13, 58, 13, index == 1 and MAGENTA or CYAN, 2, index)
		driver(kit, body, x + 13, 82, 20, index == 1 and MAGENTA or CYAN, 2, index + 0.7)
	end
	local unit = kit.Part(body, 30, 38, 40, 60, rgb(210, 214, 236), { Radius = 5, Z = 2, Shine = true, Shade = 0.2 })
	local display = kit.Part(unit, 4, 5, 32, 16, rgb(30, 50, 110), { Radius = 3, Z = 2, Outline = false })
	for i = 0, 6 do
		local barH = 3 + ((i * 5) % 9)
		local eqBar = kit.Box(display, 3 + i * 4, 14 - barH, 2.6, barH, RAINBOW[i + 1], 0, 2)
		kit.Animate(eqBar, "Pulse", 0.6, 2.4, i * 0.8)
	end
	kit.Part(unit, 4, 26, 32, 5, rgb(160, 164, 190), { Radius = 2, Z = 2, Thickness = 1 }) -- tiroir CD
	for i, color in ipairs({ C.Pink, C.Butter, C.Mint }) do
		kit.Circle(unit, 9 + (i - 1) * 11, 40, 6, 6, color, 0, 2)
	end
	local knob = kit.Blob(unit, 20, 51, 11, 11, STEEL, { Z = 2, Shine = true })
	kit.Box(knob, 4.8, 1, 1.4, 4, DARK, 0, 3)
	-- CD brillant qui tourne sur le dessus
	local cd = kit.Pivot(body, 50, 28, 3)
	local disc = kit.Circle(cd, 0, 0, 22, 22, WHITE, 0, 1)
	kit.Gradient(disc, rgb(200, 240, 255), rgb(255, 190, 240), 45)
	kit.Stroke(disc, STEEL_DARK, 1, 0)
	kit.Circle(cd, 0, 0, 13, 13, WHITE, 0.5, 2)
	kit.Circle(cd, 0, 0, 6, 6, rgb(210, 214, 236), 0, 2)
	kit.Circle(cd, 0, 0, 2.6, 2.6, DARK, 0, 3)
	kit.Box(cd, -1, -10, 2, 5, WHITE, 0.2, 3)
	kit.Box(cd, 4, 3, 2, 5, rgb(255, 200, 240), 0.3, 3)
	kit.Animate(cd, "Spin", 1, 0.5, 0)
	return { Glow = C.Sky }
end

-- Platine vinyle sur console en bois + enceintes colonnes
Art.SetupHiFiVinyl = function(body, kit, _item)
	local C = kit.C
	-- enceintes colonnes
	for index, x in ipairs({ 0, 80 }) do
		kit.Part(body, x, 28, 20, 71, rgb(160, 110, 78), { Radius = 4, Z = 1, Shine = true, Shade = 0.2 })
		driver(kit, body, x + 10, 40, 11, C.Butter, 2, index)
		driver(kit, body, x + 10, 62, 16, C.Butter, 2, index + 0.4)
		driver(kit, body, x + 10, 84, 16, C.Butter, 2, index + 0.8)
	end
	-- console "années 60" : pieds obliques, étagère à vinyles
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(body, 50 + side * 22, 88, 50 + side * 27, 99, 2.6, C.WoodDark, 0, 2)
	end
	local console = kit.Part(body, 21, 56, 58, 34, C.Wood, { Radius = 4, Z = 3, Shine = true, Shade = 0.18 })
	for k = 0, 8 do
		kit.Box(console, 4 + k * 5.6, 12, 4.2, 18, RAINBOW[k % #RAINBOW + 1], 0.1, 2)
	end
	kit.Box(console, 3, 9, 52, 1.4, C.WoodDark, 0.3, 2)
	-- platine (plateau vu de biais + disque + bras)
	local deck = kit.Part(body, 25, 44, 50, 13, rgb(60, 56, 80), { Radius = 3, Z = 4, Thickness = 1.2 })
	local disc = kit.Blob(deck, 20, 5.5, 34, 8, rgb(30, 28, 40), { Z = 2, Outline = false })
	kit.Blob(disc, 17, 4, 10, 3.4, C.PinkDeep, { Z = 2, Outline = false, Shade = false })
	local shineDot = kit.Blob(disc, 8, 2.4, 8, 1.6, WHITE, { Z = 3, Outline = false, Shade = false, T = 0.5 })
	kit.Animate(shineDot, "Drift", 8, 2.4, 0)
	local armPivot = kit.Pivot(deck, 44, 2, 3)
	kit.Line(armPivot, 0, 0, -9, 4, 1.6, STEEL, 0, 1)
	kit.Circle(armPivot, 0, 0, 4, 4, STEEL_DARK, 0, 2)
	kit.Animate(armPivot, "Sway", 3, 0.8, 0)
	for i, pos in ipairs({ { 30, 32 }, { 50, 24 }, { 70, 34 } }) do
		local n = note(kit, body, pos[1], pos[2], 11, i == 2 and PURPLE or C.PinkDeep, 6)
		kit.Animate(n, "Bob", 2.5, 1.1, i * 1.3)
	end
	return { Glow = C.Butter }
end

-- Mur de studio lofi : étagère de pochettes, enceintes tours, table de
-- mixage avec VU-mètres, platine
Art.SetupHiFiStudio = function(body, kit, _item)
	local C = kit.C
	-- étagère murale de vinyles (pochettes colorées)
	local shelf = kit.Part(body, 18, 2, 64, 30, rgb(90, 70, 130), { Radius = 5, Z = 1, Shade = 0.15 })
	local sleeves = { { MAGENTA, CYAN }, { C.Butter, PURPLE }, { LIME, RED }, { rgb(255, 160, 90), C.Sky } }
	for index, pair in ipairs(sleeves) do
		local x = 4 + (index - 1) * 15
		kit.Circle(shelf, x + 12, 13, 12, 12, rgb(30, 28, 40), 0, 2)
		local sleeve = kit.Part(shelf, x, 4, 13, 20, pair[1], { Radius = 2, Z = 3, Thickness = 1 })
		kit.Circle(sleeve, 6.5, 10, 7, 7, pair[2], 0, 2)
	end
	local neon = kit.Text(body, "LOFI", 50, 38, 9, WHITE, 3)
	neon.TextStrokeColor3 = MAGENTA
	neon.TextStrokeTransparency = 0
	kit.Animate(neon, "Bob", 1, 1.3, 0)
	-- enceintes tours
	for index, x in ipairs({ 0, 82 }) do
		kit.Part(body, x, 20, 18, 79, DARK, { Radius = 4, Z = 2, Shine = true, Thickness = 1.3 })
		local led = kit.Box(body, x + 2, 22, 14, 1.4, index == 1 and MAGENTA or CYAN, 0, 4)
		kit.Animate(led, "Pulse", 0.5, 2, index)
		driver(kit, body, x + 9, 33, 10, index == 1 and MAGENTA or CYAN, 3, index)
		driver(kit, body, x + 9, 55, 15, index == 1 and MAGENTA or CYAN, 3, index + 0.3)
		driver(kit, body, x + 9, 80, 15, index == 1 and MAGENTA or CYAN, 3, index + 0.6)
	end
	-- table de mixage
	for _, x in ipairs({ 22, 74 }) do
		kit.Part(body, x, 66, 4, 33, DARKER, { Radius = 1, Z = 3, Thickness = 1 })
	end
	local desk = kit.Part(body, 19, 54, 62, 14, DARK, { Radius = 3, Z = 4, Shine = true, Thickness = 1.3 })
	-- VU-mètres (deux colonnes de LED qui montent / descendent)
	for column = 0, 1 do
		for level = 0, 5 do
			local color = if level >= 5 then RED elseif level >= 3 then YELLOW else LIME
			local led = kit.Box(desk, 36 + column * 5, 10 - level * 1.6, 3.6, 1.2, color, 0, 2)
			kit.Animate(led, "Pulse", 0.8, 2.6 + column, level * 0.9)
		end
	end
	for i = 0, 3 do
		kit.Circle(desk, 48 + i * 3.4, 4, 2.6, 2.6, RAINBOW[i + 2], 0, 2)
	end
	-- platine sur la table (disque qui tourne, vu de biais)
	local disc = kit.Blob(desk, 16, 4, 24, 5, rgb(30, 28, 40), { Z = 3, Outline = false })
	local glint = kit.Blob(disc, 6, 1.5, 6, 1.2, WHITE, { Z = 2, Outline = false, Shade = false, T = 0.4 })
	kit.Animate(glint, "Drift", 6, 2.4, 0)
	-- casque sur la table
	kit.Blob(body, 72, 52, 8, 7, MAGENTA, { Z = 5, Thickness = 1 })
	kit.Blob(body, 62, 52, 8, 7, MAGENTA, { Z = 5, Thickness = 1 })
	kit.Part(body, 60, 43, 14, 11, DARK, { Radius = -1, T = 1, Outline = DARK, Thickness = 2, Shade = false, Z = 5 })
	for i, pos in ipairs({ { 12, 10 }, { 88, 12 } }) do
		local n = note(kit, body, pos[1], pos[2], 10, i == 1 and C.Butter or CYAN, 6)
		kit.Animate(n, "Bob", 2.5, 1.1, i)
	end
	return { Glow = MAGENTA }
end

----------------------------------------------------------------------
-- 🌀 Moulin, 🗜️ presse, 🔘 papier bulle, 🎥 coin live
----------------------------------------------------------------------

-- Moulin de jardin : petite tour pastel + 4 ailes couleurs "moulin à vent"
Art.SetupWindmill = function(body, kit, _item)
	local C = kit.C
	-- herbe + fleurs
	kit.Blob(body, 50, 98, 90, 8, C.Leaf, { Z = 1, Outline = false })
	for i, x in ipairs({ 12, 22, 80, 90 }) do
		kit.Circle(body, x, 94 - (i % 2) * 2, 5, 5, ({ C.Pink, C.Butter, C.Sky, C.Pink })[i], 0, 2)
	end
	-- tour en trapèze (tranches qui s'élargissent vers le bas) + planches
	local towerColor = rgb(255, 238, 220)
	local tower = kit.Group(body, 20, 28, 60, 70, 3)
	local slices = 14
	for k = 0, slices - 1 do
		local t = k / (slices - 1)
		local sliceW = 30 + 26 * t
		local slice = kit.Box(tower, 30 - sliceW / 2, k * 5, sliceW, 5.4, towerColor, 0, 1)
		if k % 4 == 3 then
			kit.Box(slice, 0, 4.2, sliceW, 1.1, C.WoodDark, 0.55, 2)
		end
	end
	kit.Line(body, 35, 28, 22, 98, 1.6, kit.OutlineOf(towerColor), 0, 4)
	kit.Line(body, 65, 28, 78, 98, 1.6, kit.OutlineOf(towerColor), 0, 4)
	local door = kit.Part(body, 43, 78, 14, 20, C.Wood, { Radius = 6, Z = 4, Thickness = 1.2 })
	kit.Circle(door, 11, 11, 2, 2, C.Butter, 0, 2)
	local window = kit.Part(body, 44, 50, 12, 12, C.Sky, { Radius = -1, Z = 4, Shine = true })
	kit.Box(window, 5.4, 0, 1.2, 12, WHITE, 0.3, 2)
	kit.Blob(body, 50, 26, 36, 18, C.PinkDeep, { Z = 4, Shine = true }) -- toit
	-- ailes (pivot au moyeu)
	local hub = kit.Pivot(body, 50, 26, 6)
	local colors = { C.Pink, C.Butter, C.Mint, C.Sky }
	for index = 0, 3 do
		local arm = kit.Pivot(hub, 0, 0, 1)
		arm.Rotation = index * 90 + 20
		kit.Box(arm, -1.2, -34, 2.4, 34, C.WoodDark, 0, 1)
		local sail = kit.Part(arm, 1, -34, 12, 26, colors[index + 1], { Radius = 3, Z = 2, Thickness = 1.2, Shine = true })
		for k = 1, 3 do
			kit.Box(sail, 0, k * 6.5, 12, 0.8, WHITE, 0.4, 2)
		end
	end
	kit.Circle(hub, 0, 0, 8, 8, C.Butter, 0, 5)
	kit.Animate(hub, "Spin", 1, 0.35, 0)
	return nil
end

-- Vraie presse hydraulique : colonnes, traverse jaune, vérin qui descend,
-- canard en caoutchouc écrasé, bouton rouge
Art.SetupPress = function(body, kit, _item)
	local C = kit.C
	local yellow = rgb(255, 204, 40)
	-- socle à rayures de danger
	local base = kit.Part(body, 2, 88, 96, 12, DARK, { Radius = 3, Z = 1, Thickness = 1.3 })
	local stripes = kit.Group(base, 3, 3, 90, 5, 2, true)
	for k = 0, 9 do
		local stripe = kit.Box(stripes, k * 10 - 2, -3, 5, 12, yellow, 0, 1)
		stripe.Rotation = 35
	end
	-- colonnes
	for _, x in ipairs({ 8, 80 }) do
		kit.Part(body, x, 14, 12, 76, STEEL, { Radius = 2, Z = 2, Shine = true, Thickness = 1.3 })
	end
	-- traverse jaune + vérin
	local beam = kit.Part(body, 2, 6, 96, 16, yellow, { Radius = 4, Z = 4, Shine = true, Thickness = 1.5 })
	kit.Text(beam, "PRESS", 48, 8, 9, DARK, 3)
	kit.Part(body, 38, 21, 24, 18, STEEL_DARK, { Radius = 3, Z = 3, Thickness = 1.3 })
	-- piston (monte et descend)
	local ram = kit.Group(body, 0, 0, 100, 100, 5)
	kit.Part(ram, 45, 38, 10, 20, rgb(220, 226, 240), { Radius = 2, Z = 1, Shine = true, Thickness = 1 })
	local plate = kit.Part(ram, 20, 56, 60, 8, rgb(90, 96, 120), { Radius = 2, Z = 2, Thickness = 1.3 })
	kit.Box(plate, 2, 5.5, 56, 1.2, RED, 0.2, 2)
	kit.Animate(ram, "Bob", 3, 1.1, 0)
	-- canard écrasé sur le socle
	local duck = kit.Blob(body, 50, 82, 40, 12, C.Yellow, { Z = 3, Shine = true })
	kit.Face(duck, 20, 6, 12, { Eyes = "happy", Mouth = "o", Z = 3 })
	kit.Blob(body, 72, 82, 10, 5, C.Orange, { Z = 3 })
	for index, pos in ipairs({ { 24, 74 }, { 76, 72 } }) do
		local s = kit.Sparkle(body, pos[1], pos[2], 7, C.Butter, 0, 4)
		kit.Animate(s, "Breathe", 0.3, 2, index)
	end
	-- boîtier du bouton + manomètre
	local boxFrame = kit.Part(body, 84, 44, 15, 22, DARK, { Radius = 3, Z = 6, Thickness = 1.2 })
	local button = kit.Circle(boxFrame, 7.5, 7, 9, 9, RED, 0, 2)
	kit.Stroke(button, rgb(140, 20, 30), 1.2, 0)
	kit.Animate(button, "Pulse", 0.3, 1.6, 0)
	kit.Text(boxFrame, "PUSH", 7.5, 16, 4.5, WHITE, 3)
	local gauge = kit.Circle(body, 14, 34, 12, 12, WHITE, 0, 5)
	kit.Stroke(gauge, DARK, 1.4, 0)
	local needle = kit.Pivot(gauge, 6, 6, 2)
	kit.Box(needle, -0.6, -5, 1.2, 5, RED, 0, 1)
	kit.Animate(needle, "Sway", 35, 1.1, 0)
	return nil
end

-- Table à papier bulle (dessus à y = 52) : rouleau posé dessus, feuille
-- qui pend devant (bulles pleines et éclatées)
Art.SetupBubbleWrap = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 10, 86 }) do
		kit.Part(body, x, 56, 5, 44, C.WoodDark, { Radius = 2, Z = 1, Thickness = 1.2 })
	end
	kit.Part(body, 4, 51.5, 92, 6, C.Wood, { Radius = 3, Z = 3, Shine = true, Thickness = 1.3 })
	-- rouleau sur la table
	local roll = kit.Part(body, 54, 28, 38, 24, rgb(214, 240, 255), { Radius = 11, Z = 4, Shine = true, Thickness = 1.3 })
	for k = 0, 4 do
		kit.Box(roll, 4 + k * 7, 2, 1, 20, WHITE, 0.4, 2)
	end
	kit.Blob(body, 56, 40, 10, 22, rgb(190, 225, 250), { Z = 5, Thickness = 1.2 })
	kit.Circle(body, 56, 40, 4, 4, C.WoodLight, 0, 6)
	-- feuille qui pend devant la table
	local sheet = kit.Part(body, 14, 56, 64, 30, rgb(220, 244, 255), { Radius = 4, Z = 6, T = 0.1, Thickness = 1.2, Shade = 0.08 })
	for row = 0, 2 do
		for col = 0, 6 do
			local cx, cy = 5 + col * 9 + (row % 2) * 4, 5 + row * 9.5
			local popped = (row * 7 + col) % 5 == 2
			if popped then
				local flat = kit.Circle(sheet, cx, cy, 6, 3, rgb(180, 200, 220), 0.3, 2)
				local _ = flat
			else
				local bubble = kit.Circle(sheet, cx, cy, 7, 7, rgb(186, 228, 255), 0.15, 2)
				kit.Stroke(bubble, rgb(140, 196, 236), 0.8, 0)
				kit.Circle(bubble, 2.3, 2.3, 2.2, 2.2, WHITE, 0.1, 2)
				if (row + col) % 4 == 0 then
					kit.Animate(bubble, "Breathe", 0.06, 2, row + col)
				end
			end
		end
	end
	local pop = kit.Text(body, "POP!", 22, 44, 9, C.PinkDeep, 7)
	pop.TextStrokeColor3 = WHITE
	pop.TextStrokeTransparency = 0
	kit.Animate(pop, "Bob", 2, 1.6, 0)
	kit.Sparkle(body, 36, 42, 8, C.Butter, 0, 7)
	return nil
end

-- Coin streaming : anneau lumineux, écran du live sur petit bureau, micro,
-- caméra sur trépied, enseigne ON AIR
Art.SetupLiveStudio = function(body, kit, _item)
	local C = kit.C
	-- enseigne "ON AIR"
	local sign = kit.Part(body, 36, 0, 30, 10, DARKER, { Radius = 3, Z = 2, Thickness = 1 })
	local onAir = kit.Text(sign, "ON AIR", 15, 5, 6.5, rgb(255, 120, 130), 3)
	onAir.TextStrokeColor3 = RED
	onAir.TextStrokeTransparency = 0.2
	kit.Animate(sign, "Pulse", 0.25, 1.4, 0)
	-- anneau lumineux sur trépied (à gauche)
	for _, dx in ipairs({ -9, 0, 9 }) do
		kit.Line(body, 17, 60, 17 + dx, 99, 2, DARK, 0, 1)
	end
	kit.Line(body, 17, 42, 17, 60, 2.2, STEEL_DARK, 0, 1)
	local glow = kit.Circle(body, 17, 28, 36, 36, rgb(255, 250, 220), 0.6, 2)
	kit.Animate(glow, "Pulse", 0.2, 1, 0)
	local ring = kit.Circle(body, 17, 28, 28, 28, WHITE, 1, 3)
	kit.Stroke(ring, rgb(255, 222, 140), 4.5, 0)
	local rim = kit.Circle(body, 17, 28, 33, 33, WHITE, 1, 3)
	kit.Stroke(rim, STEEL_DARK, 1.2, 0)
	local inner = kit.Circle(body, 17, 28, 23, 23, WHITE, 1, 3)
	kit.Stroke(inner, STEEL_DARK, 1, 0.3)
	kit.Circle(body, 17, 28, 6, 6, DARK, 0, 3) -- téléphone au centre
	-- petit bureau + écran du live
	for _, x in ipairs({ 33, 70 }) do
		kit.Part(body, x, 66, 4, 33, DARKER, { Radius = 1, Z = 2, Thickness = 1 })
	end
	kit.Part(body, 30, 62, 44, 5.5, DESK_TOP, { Radius = 2, Z = 3, Shine = true, Thickness = 1.2 })
	monitorStand(kit, body, 52, 52, 62, 3)
	monitorFrame(kit, body, 32, 18, 40, 35, "Live", 4, { Chin = 2.5 })
	-- micro sur bras
	kit.Line(body, 34, 62, 38, 50, 1.6, STEEL_DARK, 0, 5)
	kit.Line(body, 38, 50, 44, 56, 1.6, STEEL_DARK, 0, 5)
	kit.Part(body, 42, 52, 6, 9, rgb(80, 80, 100), { Radius = 3, Z = 6, Thickness = 1 })
	-- caméra sur trépied (à droite)
	for _, dx in ipairs({ -8, 0, 8 }) do
		kit.Line(body, 88, 52, 88 + dx, 99, 2, DARK, 0, 1)
	end
	local cam = kit.Part(body, 78, 34, 18, 14, DARK, { Radius = 3, Z = 4, Shine = true, Thickness = 1.2 })
	local lens = kit.Circle(body, 78, 41, 11, 11, DARKER, 0, 5)
	kit.Stroke(lens, STEEL, 1.4, 0)
	kit.Circle(lens, 5.5, 5.5, 5, 5, rgb(90, 140, 255), 0, 2)
	local rec = kit.Circle(cam, 14.5, 3.5, 3.4, 3.4, RED, 0, 2)
	kit.Animate(rec, "Pulse", 0.7, 2, 0)
	kit.Heart(body, 96, 24, 8, C.Heart, 0, 6)
	return { Glow = rgb(255, 240, 200) }
end

----------------------------------------------------------------------
-- 🌼 Plantes du Jardin de Dopamine (pot lumineux + étoiles de rareté)
----------------------------------------------------------------------

-- Pot "Dopamine" : céramique pastel, bord doré, bandeau à étoiles ;
-- (cx, bottom) = milieu du bas ; renvoie le pot
local function dopaminePot(kit, body, cx, bottom, w, h, color, stars: number)
	local C = kit.C
	kit.Blob(body, cx, bottom - 1.5, w * 0.8, 4, rgb(0, 0, 0), { Z = 1, Outline = false, Shade = false, T = 0.85 })
	local potBody = kit.Part(body, cx - w / 2 + w * 0.08, bottom - h, w * 0.84, h, color, { Radius = 6, Z = 5, Shine = true, Shade = 0.2 })
	kit.Part(body, cx - w / 2, bottom - h - 2, w, 7, C.Gold, { Radius = 3, Z = 6, Shine = true, Thickness = 1.3 })
	local band = kit.Box(potBody, 2, h * 0.42, w * 0.84 - 4, h * 0.3, WHITE, 0.35, 2)
	kit.Round(band, 3)
	for index = 1, stars do
		local sx = (w * 0.84) / 2 + (index - (stars + 1) / 2) * math.min(9, (w * 0.84 - 6) / stars)
		star(kit, potBody, sx, h * 0.57, 7, C.Gold, 3)
	end
	return potBody
end

-- Halo de lumière derrière une plante rare
local function plantGlow(kit, body, cx, cy, size, color)
	local halo = kit.Circle(body, cx, cy, size, size, color, 0.7, 1)
	kit.Animate(halo, "Pulse", 0.2, 1, cx)
	return halo
end

-- Feuille (ovale tourné)
local function leaf(kit, parent, x, y, angle, w, h, color, z)
	local frame = kit.Blob(parent, x, y, w, h, color, { Z = z, Thickness = 1.1 })
	frame.Rotation = angle
	return frame
end

Art.SetupPlantDaisy = function(body, kit, _item)
	local C = kit.C
	plantGlow(kit, body, 50, 38, 70, C.Butter)
	local stems = kit.Pivot(body, 50, 70, 3)
	local flowers = { { -18, -36, 9 }, { 18, -34, 9 }, { 0, -52, 11 } }
	for _, f in ipairs(flowers) do
		kit.Line(stems, 0, 0, f[1], f[2], 2.4, C.Green, 0, 1)
	end
	leaf(kit, stems, -8, -10, -30, 18, 8, C.Leaf, 2)
	leaf(kit, stems, 8, -14, 30, 18, 8, C.Leaf, 2)
	for index, f in ipairs(flowers) do
		local x, y, r = f[1], f[2], f[3]
		for k = 0, 3 do
			local a = math.rad(k * 45)
			local dx, dy = math.cos(a) * r * 0.62, math.sin(a) * r * 0.62
			local petal = kit.Line(stems, x - dx, y - dy, x + dx, y + dy, r * 0.62, WHITE, 0, 3)
			kit.Stroke(petal, rgb(220, 205, 230), 1.1)
		end
		kit.Blob(stems, x, y, r * 0.95, r * 0.95, C.Yellow, { Z = 4, Shade = false, Thickness = 1.2 })
		if index == 3 then
			kit.Face(stems, x, y + 0.5, r * 0.95, { Mouth = "none", Blush = false, Z = 5 })
		end
	end
	kit.Animate(stems, "Sway", 2.5, 0.8, 1)
	dopaminePot(kit, body, 50, 100, 46, 30, C.Sky, 1)
	kit.Sparkle(body, 80, 20, 8, C.Butter, 0, 6)
	return { Glow = C.Butter }
end

Art.SetupPlantTulip = function(body, kit, _item)
	local C = kit.C
	plantGlow(kit, body, 50, 38, 72, C.PinkSoft)
	local stems = kit.Pivot(body, 50, 70, 3)
	local tulips = { { -16, -38, C.Pink }, { 16, -40, PURPLE }, { 0, -54, C.PinkDeep } }
	for _, t in ipairs(tulips) do
		kit.Line(stems, 0, 0, t[1], t[2], 2.4, C.Green, 0, 1)
	end
	leaf(kit, stems, -9, -12, -25, 22, 8, C.Leaf, 2)
	leaf(kit, stems, 9, -16, 25, 22, 8, C.LeafDark, 2)
	for _, t in ipairs(tulips) do
		local x, y, color = t[1], t[2], t[3]
		kit.Blob(stems, x, y, 13, 14, color, { Z = 3, Shine = true })
		for _, dx in ipairs({ -4, 0, 4 }) do
			local tip = kit.Blob(stems, x + dx, y - 6, 5, 8, color, { Z = 3, Outline = false, Shade = false })
			local _ = tip
		end
	end
	kit.Animate(stems, "Sway", 2.5, 0.8, 2)
	dopaminePot(kit, body, 50, 100, 46, 30, C.LilacSoft, 2)
	kit.Sparkle(body, 20, 22, 8, C.Butter, 0, 6)
	return { Glow = C.Pink }
end

Art.SetupPlantRose = function(body, kit, _item)
	local C = kit.C
	plantGlow(kit, body, 50, 36, 74, rgb(255, 170, 190))
	local stems = kit.Pivot(body, 50, 68, 3)
	local roses = { { -15, -34 }, { 15, -38 }, { 0, -52 } }
	for _, r in ipairs(roses) do
		kit.Line(stems, 0, 0, r[1], r[2], 2.4, C.LeafDark, 0, 1)
	end
	leaf(kit, stems, -10, -12, -35, 16, 8, C.Leaf, 2)
	leaf(kit, stems, 10, -20, 35, 16, 8, C.Leaf, 2)
	for index, r in ipairs(roses) do
		local size = index == 3 and 16 or 13
		kit.Blob(stems, r[1], r[2], size, size, RED, { Z = 3, Shine = true })
		kit.Blob(stems, r[1] + 1, r[2] - 1, size * 0.62, size * 0.62, rgb(255, 110, 120), { Z = 4, Thickness = 1 })
		kit.Blob(stems, r[1] + 1.5, r[2] - 1.5, size * 0.28, size * 0.28, rgb(200, 40, 60), { Z = 5, Outline = false, Shade = false })
	end
	kit.Animate(stems, "Sway", 2, 0.7, 3)
	dopaminePot(kit, body, 50, 100, 48, 32, C.PinkMist, 3)
	for index, pos in ipairs({ { 18, 18 }, { 84, 26 } }) do
		local s = kit.Sparkle(body, pos[1], pos[2], 8, C.Butter, 0, 6)
		kit.Animate(s, "Breathe", 0.25, 1.4, index)
	end
	return { Glow = rgb(255, 120, 150) }
end

Art.SetupPlantSunflower = function(body, kit, _item)
	local C = kit.C
	plantGlow(kit, body, 50, 26, 70, C.Butter)
	local plant = kit.Pivot(body, 50, 72, 3)
	kit.Line(plant, 0, 0, 0, -48, 3.4, C.Green, 0, 1)
	leaf(kit, plant, -10, -18, -30, 22, 10, C.Leaf, 2)
	leaf(kit, plant, 10, -28, 30, 22, 10, C.LeafDark, 2)
	-- fleur : couronne de pétales + cœur brun avec visage
	local head = kit.Pivot(plant, 0, -50, 3)
	for k = 0, 11 do
		local a = math.rad(k * 30)
		local px, py = math.cos(a) * 13, math.sin(a) * 13
		local petal = kit.Blob(head, px, py, 12, 7, C.Yellow, { Z = 1, Thickness = 1 })
		petal.Rotation = k * 30
	end
	local core = kit.Blob(head, 0, 0, 20, 20, rgb(140, 90, 50), { Z = 2, Shine = true })
	kit.Face(core, 10, 10, 14, { Eyes = "happy", Z = 3, Color = rgb(255, 230, 170) })
	kit.Animate(head, "Sway", 6, 0.6, 0)
	kit.Animate(plant, "Sway", 1.5, 0.5, 1)
	dopaminePot(kit, body, 50, 100, 52, 30, rgb(255, 214, 170), 4)
	kit.Sparkle(body, 84, 12, 9, C.Butter, 0, 6)
	return { Glow = C.Yellow }
end

Art.SetupPlantLotus = function(body, kit, _item)
	local C = kit.C
	plantGlow(kit, body, 50, 50, 84, C.Gold)
	-- bol doré plein d'eau
	kit.Blob(body, 50, 97, 76, 6, rgb(0, 0, 0), { Z = 1, Outline = false, Shade = false, T = 0.85 })
	local bowl = kit.Part(body, 14, 70, 72, 28, C.Gold, { Radius = 14, Z = 3, Shine = true, Shade = 0.25 })
	local _ = bowl
	local water = kit.Blob(body, 50, 71, 72, 12, rgb(120, 200, 240), { Z = 4, Thickness = 1.2 })
	kit.Blob(water, 20, 4, 18, 3, WHITE, { Z = 2, Outline = false, Shade = false, T = 0.4 })
	-- nénuphars
	kit.Blob(body, 26, 71, 16, 6, C.Leaf, { Z = 5, Thickness = 1 })
	kit.Blob(body, 76, 72, 14, 5, C.LeafDark, { Z = 5, Thickness = 1 })
	-- lotus d'or : pétales en éventail
	local flower = kit.Pivot(body, 50, 68, 6)
	for index, angle in ipairs({ -70, -40, -14, 14, 40, 70 }) do
		-- un pivot par pétale : il tourne autour de la base de la fleur
		local arm = kit.Pivot(flower, 0, 0, 1)
		arm.Rotation = angle
		kit.Part(arm, -5, -26, 10, 26, if index % 2 == 0 then rgb(255, 214, 110) else rgb(255, 236, 170), { Radius = -1, Z = 1, Thickness = 1.1, Shine = true })
	end
	local center = kit.Part(flower, -6, -24, 12, 22, rgb(255, 246, 200), { Radius = -1, Z = 3, Thickness = 1.1, Shine = true })
	local _c = center
	kit.Face(flower, 0, -12, 10, { Eyes = "closed", Mouth = "smile", Z = 4 })
	kit.Animate(flower, "Breathe", 0.04, 1.2, 0)
	for index, pos in ipairs({ { 22, 40 }, { 80, 34 }, { 50, 10 } }) do
		local s = kit.Sparkle(body, pos[1], pos[2], 9, index == 3 and WHITE or C.Butter, 0, 7)
		kit.Animate(s, "Breathe", 0.3, 1.4, index)
	end
	return { Glow = C.Gold }
end

return Art
