--[[
	Background (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Background

	Fond d'écran du jeu, piloté par le thème équipé (Config.Themes, état
	ClientState.Data.Themes.Equipped, "Classic" par défaut) :
	  - un dégradé vertical (Top -> Bottom du thème) ;
	  - une illustration animée en plusieurs PLANS (parallaxe : les plans
	    lointains bougent moins que les plans proches quand la souris bouge,
	    ou dérivent doucement sur mobile) selon theme.Decor :
	      "None"    : blanc / gris épuré (halos très discrets, reflet lent)
	      "Kawaii"  : arc-en-ciel pastel, nuages à bouille, ballons, collines
	                  fleuries, cœurs et paillettes
	      "Stars"   : aurore boréale, nébuleuses, lune, étoiles filantes,
	                  montagnes et ville en deux plans (fenêtres, antennes)
	      "Sunset"  : soleil couchant, bandes de lumière, mer scintillante,
	                  voilier, collines, palmiers, nuages, oiseaux
	      "Leaves"  : montagnes dans la brume, rayons, bokeh, bambous
	                  feuillus, feuilles qui tombent
	      "Bubbles" : reflets de surface, baleine au loin, méduses, algues,
	                  coraux, poissons et bulles
	      "Candy"   : glaçage qui coule, nuages barbe à papa, collines de
	                  bonbons, sucettes, bonbons gélifiés, vermicelles
	      "Grid"    : synthwave (soleil rayé, deux chaînes de montagnes néon,
	                  palmiers, grille qui défile)
	  - fondu enchaîné quand le thème change ;
	  - moins d'éléments si le joueur a coupé les effets (Settings.Effects).

	Mode sombre : actif si le thème est sombre (theme.Dark) OU si le joueur
	possède le mode néon (Feature "NeonMode") -> ClientState.SetDarkMode.
	Dopamine Rush : une lueur jaune pulse doucement en bas de l'écran
	(Background.SetRush).

	Background.BuildPreview(parent, themeId) : même illustration en
	miniature (panneau des thèmes), animée par l'appelant.

	Tout est dessiné en code (Frames, UIGradient, UICorner, UIStroke, emojis),
	et animé par UNE seule boucle (Heartbeat) sans créer d'objets à chaque image.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Background = {}

Background.ThemeChanged = Signal.new() -- (theme) : le thème affiché a changé

type Plane = { Frame: Frame, Depth: number }

type Layer = {
	Frame: Frame,
	Update: ((dt: number, t: number) -> ())?,
	Time: number,
	Planes: { Plane },
}

export type Preview = {
	Frame: Frame,
	Update: (dt: number) -> (),
	Destroy: () -> (),
}

local DEFAULT_THEME = "Classic"
local CROSSFADE_TIME = 0.9
local DESIGN = Vector2.new(1280, 720)
local PARALLAX_X = 22 -- décalage max (pixels "design") d'un plan de profondeur 1
local PARALLAX_Y = 12

local root: Frame? = nil
local glow: Frame? = nil
local rushActive = false
local currentThemeId: string? = nil
local currentReduced = false
local layers: { Layer } = {} -- couches animées (actuelle + celles qui s'effacent)
local parallax = Vector2.zero -- décalage lissé (-1..1)
local buildingPlanes: { Plane }? = nil -- plans du décor en cours de construction

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

----------------------------------------------------------------------
-- Outils de dessin
----------------------------------------------------------------------

local Create = UIUtil.Create

local function box(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	return Create("Frame", props)
end

local function circle(props: { [string]: any }): Frame
	local frame = box(props)
	UIUtil.Corner(frame, UDim.new(1, 0))
	return frame
end

local function emoji(text: string, size: number, props: { [string]: any }): TextLabel
	props.Text = text
	props.TextSize = size
	props.Font = Theme.Fonts.Body
	props.BackgroundTransparency = 1
	props.Size = UDim2.fromOffset(size + 8, size + 8)
	props.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	return Create("TextLabel", props)
end

local function fadeSequence(from: number, to: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to),
	})
end

-- Transparence "fondue aux deux bouts" (bandes, rubans)
local function edgeFade(edge: number, middle: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge, middle),
		NumberSequenceKeypoint.new(1 - edge, middle),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Dégradé vertical top -> bottom (le fond du parent passe en blanc pour
-- que les couleurs du dégradé s'affichent telles quelles)
local function vgradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	parent.BackgroundColor3 = WHITE
	return Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom), Parent = parent })
end

-- Plan de parallaxe (cadre plein écran un peu plus grand que l'écran, pour
-- que ses bords ne se voient jamais quand il glisse)
local function plane(parent: Instance, depth: number, z: number): Frame
	local frame = box({
		Name = "Plane" .. tostring(math.floor(depth * 100)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.06, 1.06),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	local list = buildingPlanes
	if list then
		table.insert(list, { Frame = frame, Depth = depth })
	end
	return frame
end

-- Halo doux : 3 disques concentriques transparents (faux dégradé radial)
local function softGlow(parent: Instance, size: number, color: Color3, opacity: number, z: number): Frame
	local holder = box({
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	for _, k in ipairs({ 1, 0.68, 0.4 }) do
		circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			BackgroundColor3 = color,
			BackgroundTransparency = 1 - opacity,
			ZIndex = z,
			Parent = holder,
		})
	end
	return holder
end

-- Nuage "dessiné" (disques qui se chevauchent). CanvasGroup : la
-- transparence s'applique au nuage entier (pas de zones plus foncées).
local function cloud(parent: Instance, width: number, color: Color3, transparency: number, z: number, shade: Color3?): CanvasGroup
	local height = math.floor(width * 0.5)
	local group = Create("CanvasGroup", {
		Name = "Cloud",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		GroupTransparency = transparency,
		ZIndex = z,
		Parent = parent,
	})
	local base = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.46),
		BackgroundColor3 = color,
		Parent = group,
	})
	UIUtil.Corner(base, UDim.new(1, 0))
	local puffs = { { 0.3, 0.62, 0.5 }, { 0.55, 0.45, 0.78 }, { 0.76, 0.6, 0.52 } }
	for _, puff in ipairs(puffs) do
		local d = height * puff[3] * 1.6
		circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(puff[1], puff[2]),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = color,
			Parent = group,
		})
	end
	-- Ombrage en bas
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, shade or Color3.fromRGB(225, 225, 235)),
		Parent = group,
	})
	return group
end

-- Grand disque dont on ne voit que le haut (colline)
local function mound(parent: Instance, x: number, top: number, diameter: number, color: Color3, z: number): Frame
	return circle({
		Name = "Mound",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(x, top),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = color,
		ZIndex = z,
		Parent = parent,
	})
end

-- Sommet de montagne : carré tourné à 45° (le bas est caché par le plan suivant)
local function peak(parent: Instance, x: number, baseY: number, size: number, color: Color3, z: number): Frame
	return box({
		Name = "Peak",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, baseY),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = color,
		ZIndex = z,
		Parent = parent,
	})
end

-- Palmier en silhouette (tronc courbé + palmes). Renvoie le support (ancré en bas au centre).
local function palm(parent: Instance, x: number, baseY: number, height: number, lean: number, color: Color3, z: number): Frame
	local holder = box({
		Name = "Palm",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(x, baseY),
		Size = UDim2.fromOffset(height, height),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	local segments = 7
	local topX, topY = height * 0.5, height
	for i = 0, segments - 1 do
		local p = i / segments
		local px = height * 0.5 + lean * height * 0.28 * p * p
		local py = height * (1 - p * 0.84)
		local width = math.max(6, height * (0.075 - p * 0.03))
		box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(px, py),
			Size = UDim2.fromOffset(width, height * 0.15),
			Rotation = lean * p * 12,
			BackgroundColor3 = color,
			ZIndex = z,
			Parent = holder,
		})
		topX, topY = px, py - height * 0.12
	end
	local length = height * 0.44
	for _, angle in ipairs({ -165, -135, -100, -65, -30, 8, 170, 40, 140 }) do
		local radians = math.rad(angle)
		local frond = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(topX + math.cos(radians) * length * 0.5, topY + math.sin(radians) * length * 0.5),
			Size = UDim2.fromOffset(length, math.max(6, height * 0.06)),
			Rotation = angle,
			BackgroundColor3 = color,
			ZIndex = z,
			Parent = holder,
		})
		UIUtil.Corner(frond, UDim.new(1, 0))
	end
	return holder
end

----------------------------------------------------------------------
-- Éléments qui flottent / tombent / montent (positions en fraction d'écran)
----------------------------------------------------------------------

type Floater = {
	Obj: GuiObject,
	X: number,
	Y: number,
	VX: number,
	VY: number,
	Amp: number,
	Freq: number,
	Phase: number,
	Rot: number,
	Spin: number,
	Wobble: number,
}

local function newFloater(obj: GuiObject, random: Random, params: { [string]: any }): Floater
	return {
		Obj = obj,
		X = params.X or random:NextNumber(0, 1),
		Y = params.Y or random:NextNumber(0, 1),
		VX = params.VX or 0,
		VY = params.VY or 0,
		Amp = params.Amp or 0,
		Freq = params.Freq or random:NextNumber(0.4, 1),
		Phase = random:NextNumber(0, math.pi * 2),
		Rot = params.Rot or 0,
		Spin = params.Spin or 0,
		Wobble = params.Wobble or 0,
	}
end

local function stepFloaters(list: { Floater }, dt: number, t: number)
	for _, f in ipairs(list) do
		f.X += f.VX * dt
		f.Y += f.VY * dt
		-- On fait le tour de l'écran (marge de 12 %)
		if f.Y < -0.12 then
			f.Y += 1.24
		elseif f.Y > 1.12 then
			f.Y -= 1.24
		end
		if f.X < -0.15 then
			f.X += 1.3
		elseif f.X > 1.15 then
			f.X -= 1.3
		end
		local sway = math.sin(t * f.Freq + f.Phase)
		f.Obj.Position = UDim2.fromScale(f.X + sway * f.Amp, f.Y)
		if f.Spin ~= 0 or f.Wobble ~= 0 then
			f.Obj.Rotation = (f.Rot + f.Spin * t) % 360 + sway * f.Wobble
		end
	end
end

-- Scintillement : { Obj, Property, Min, Max, Speed, Phase } (transparences, échelles)
type Twinkle = { Obj: Instance, Property: string, Min: number, Max: number, Speed: number, Phase: number }

local function stepTwinkles(list: { Twinkle }, t: number)
	for _, tw in ipairs(list) do
		local k = 0.5 + 0.5 * math.sin(t * tw.Speed + tw.Phase)
		local object: any = tw.Obj
		object[tw.Property] = tw.Min + (tw.Max - tw.Min) * k
	end
end

local function twinkle(list: { Twinkle }, obj: Instance, property: string, min: number, max: number, random: Random, speedMin: number?, speedMax: number?)
	table.insert(list, {
		Obj = obj,
		Property = property,
		Min = min,
		Max = max,
		Speed = random:NextNumber(speedMin or 1, speedMax or 3),
		Phase = random:NextNumber(0, math.pi * 2),
	})
end

-- Couleur du ciel (dégradé du thème) à la hauteur y (0 = haut, 1 = bas)
local function skyAt(theme, y: number): Color3
	return (theme.Top :: Color3):Lerp(theme.Bottom, math.clamp(y, 0, 1))
end

-- Étoile en croix (deux fines barres) qui "respire"
local function crossStar(parent: Instance, x: number, y: number, size: number, color: Color3, z: number): (Frame, UIScale)
	local holder = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	for _, rotation in ipairs({ 0, 90 }) do
		local bar = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 2, 1, 0),
			Rotation = rotation,
			BackgroundColor3 = color,
			ZIndex = z,
			Parent = holder,
		})
		Create("UIGradient", { Rotation = 90, Transparency = edgeFade(0.3, 0), Parent = bar })
	end
	circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = color,
		ZIndex = z,
		Parent = holder,
	})
	local scale = Create("UIScale", { Parent = holder })
	return holder, scale
end

----------------------------------------------------------------------
-- Décors (chaque fonction construit dans `frame` et renvoie Update / Layout)
----------------------------------------------------------------------

type DecorResult = { Update: ((dt: number, t: number) -> ())?, Layout: (() -> ())? }
type DecorBuilder = (frame: Frame, theme: any, reduced: boolean, random: Random) -> DecorResult

local Decors: { [string]: DecorBuilder } = {}

-- Classique : blanc / gris épuré, halos presque invisibles et reflet lent
Decors.None = function(frame, _theme, reduced, random)
	local far = plane(frame, 0.25, 1)
	local blobs = {}
	local count = reduced and 3 or 5
	for i = 1, count do
		local color = (i % 2 == 0) and Color3.fromRGB(200, 200, 208) or WHITE
		local blob = softGlow(far, random:NextInteger(280, 460), color, i % 2 == 0 and 0.05 or 0.35, 1)
		table.insert(blobs, {
			Obj = blob,
			X = random:NextNumber(0.05, 0.95),
			Y = random:NextNumber(0.1, 0.9),
			RX = random:NextNumber(0.03, 0.07),
			RY = random:NextNumber(0.03, 0.06),
			Speed = random:NextNumber(0.05, 0.1),
			Phase = random:NextNumber(0, math.pi * 2),
		})
	end
	-- Reflet diagonal qui traverse très lentement l'écran
	local sheen = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 260, 1.6, 0),
		Rotation = 25,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Transparency = edgeFade(0.45, 0.4), Parent = sheen })
	-- Légère ombre en bas (profondeur)
	local shade = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.35),
		BackgroundColor3 = Color3.fromRGB(190, 190, 196),
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.7), Parent = shade })

	return {
		Update = function(_dt, t)
			for _, b in ipairs(blobs) do
				b.Obj.Position = UDim2.fromScale(
					b.X + math.sin(t * b.Speed + b.Phase) * b.RX,
					b.Y + math.cos(t * b.Speed * 0.8 + b.Phase) * b.RY
				)
			end
			local cycle = (t % 24) / 24
			sheen.Position = UDim2.fromScale(-0.3 + cycle * 1.6, 0.5)
		end,
	}
end

-- Kawaii : arc-en-ciel, nuages à bouille, ballons, collines fleuries, cœurs
Decors.Kawaii = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local twinkles: { Twinkle } = {}
	local accent: Color3 = theme.Accent

	-- Plan lointain : halos pastel + pois
	local far = plane(frame, 0.15, 1)
	for index, color in ipairs({ Color3.fromRGB(255, 190, 220), Color3.fromRGB(200, 190, 255), Color3.fromRGB(190, 240, 225) }) do
		local halo = softGlow(far, random:NextInteger(420, 560), color, 0.16, 1)
		halo.Position = UDim2.fromScale(({ 0.15, 0.85, 0.5 })[index], ({ 0.3, 0.2, 0.75 })[index])
	end
	for _ = 1, reduced and 10 or 18 do
		local d = random:NextInteger(6, 12)
		circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = random:NextNumber(0.35, 0.6),
			ZIndex = 1,
			Parent = far,
		})
	end

	-- Arc-en-ciel pastel (haut droit) : anneaux coupés à mi-hauteur
	local RAINBOW = {
		Color3.fromRGB(255, 150, 170),
		Color3.fromRGB(255, 200, 150),
		Color3.fromRGB(255, 240, 160),
		Color3.fromRGB(170, 235, 190),
		Color3.fromRGB(160, 210, 255),
		Color3.fromRGB(200, 170, 255),
	}
	local rainbowPlane = plane(frame, 0.25, 2)
	local ARC = 420
	local clip = box({
		Name = "Rainbow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.84, 0.46),
		Size = UDim2.fromOffset(ARC + 36, ARC / 2 + 18),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = rainbowPlane,
	})
	for index, color in ipairs(RAINBOW) do
		local d = ARC - (index - 1) * 32
		local ring = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(d, d),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = clip,
		})
		UIUtil.Stroke(ring, color, 16, 0.3)
	end
	-- Petits nuages au pied de l'arc-en-ciel
	for _, x in ipairs({ 0.84 - ARC / 2 / 1280, 0.84 + ARC / 2 / 1280 }) do
		local c = cloud(rainbowPlane, 150, WHITE, 0.05, 3, Color3.fromRGB(240, 225, 245))
		c.Position = UDim2.fromScale(x, 0.45)
	end

	-- Plan du milieu : nuages (certains avec une petite bouille) qui dérivent
	local mid = plane(frame, 0.45, 3)
	for i = 1, reduced and 3 or 5 do
		local width = random:NextInteger(150, 240)
		local c = cloud(mid, width, WHITE, random:NextNumber(0.02, 0.18), 3, Color3.fromRGB(238, 226, 246))
		if i % 2 == 1 then
			-- Bouille : deux yeux, deux joues roses
			for side = -1, 1, 2 do
				circle({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, side * width * 0.09, 0.62, 0),
					Size = UDim2.fromOffset(7, 9),
					BackgroundColor3 = Color3.fromRGB(80, 60, 90),
					Parent = c,
				})
				circle({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, side * width * 0.16, 0.72, 0),
					Size = UDim2.fromOffset(14, 8),
					BackgroundColor3 = Color3.fromRGB(255, 150, 190),
					BackgroundTransparency = 0.3,
					Parent = c,
				})
			end
		end
		table.insert(floaters, newFloater(c, random, {
			X = (i - 1) / 4 + random:NextNumber(-0.05, 0.05),
			Y = random:NextNumber(0.1, 0.55),
			VX = random:NextNumber(0.005, 0.011),
			Amp = 0.004,
			Freq = random:NextNumber(0.2, 0.4),
		}))
	end

	-- Ballons qui montent doucement
	local BALLOONS = { Color3.fromRGB(255, 130, 180), Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 210, 110), Color3.fromRGB(180, 150, 255) }
	for i = 1, reduced and 2 or 4 do
		local color = BALLOONS[(i - 1) % #BALLOONS + 1]
		local balloon = box({
			Name = "Balloon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(46, 110),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = mid,
		})
		local body = circle({
			Size = UDim2.fromOffset(46, 54),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.08,
			ZIndex = 3,
			Parent = balloon,
		})
		vgradient(body, color:Lerp(WHITE, 0.35), color)
		circle({
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.fromOffset(10, 15),
			Rotation = 20,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.35,
			ZIndex = 3,
			Parent = body,
		})
		box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(23, 52),
			Size = UDim2.fromOffset(8, 6),
			Rotation = 45,
			BackgroundColor3 = color:Lerp(BLACK, 0.1),
			ZIndex = 3,
			Parent = balloon,
		})
		box({
			Name = "Cord",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(23, 57),
			Size = UDim2.fromOffset(1, 52),
			BackgroundColor3 = Color3.fromRGB(150, 130, 160),
			BackgroundTransparency = 0.3,
			ZIndex = 3,
			Parent = balloon,
		})
		table.insert(floaters, newFloater(balloon, random, {
			Y = random:NextNumber(0.2, 1),
			VY = -random:NextNumber(0.008, 0.014),
			Amp = random:NextNumber(0.006, 0.014),
			Freq = random:NextNumber(0.5, 0.9),
			Wobble = random:NextNumber(4, 8),
		}))
	end

	-- Collines fleuries en bas
	local hills = plane(frame, 0.7, 4)
	local HILLS = { { 0.12, 0.8, 760, Color3.fromRGB(205, 240, 215) }, { 0.9, 0.78, 820, Color3.fromRGB(255, 214, 232) }, { 0.52, 0.86, 900, Color3.fromRGB(226, 214, 255) } }
	for _, spec in ipairs(HILLS) do
		local hill = mound(hills, spec[1], spec[2], spec[3], spec[4], 4)
		vgradient(hill, spec[4]:Lerp(WHITE, 0.35), spec[4])
	end
	local FLOWERS = { "🌷", "🌼", "🌸", "🌷" }
	for i = 1, reduced and 4 or 8 do
		local flower = emoji(FLOWERS[(i - 1) % #FLOWERS + 1], random:NextInteger(16, 22), {
			Position = UDim2.fromScale(random:NextNumber(0.02, 0.98), random:NextNumber(0.83, 0.9)),
			ZIndex = 5,
			Parent = hills,
		})
		twinkle(twinkles, flower, "Rotation", -8, 8, random, 0.6, 1.2)
	end

	-- Plan proche : cœurs, étoiles, fleurs qui montent en se dandinant
	local near = plane(frame, 1, 5)
	local ICONS = { "💗", "💖", "⭐", "🌸", "💕", "🎀", "💗", "⭐" }
	for _ = 1, reduced and 6 or 12 do
		local size = random:NextInteger(18, 32)
		local label = emoji(ICONS[random:NextInteger(1, #ICONS)], size, {
			TextTransparency = random:NextNumber(0.15, 0.4),
			ZIndex = 5,
			Parent = near,
		})
		table.insert(floaters, newFloater(label, random, {
			VY = -random:NextNumber(0.012, 0.028),
			Amp = random:NextNumber(0.008, 0.02),
			Rot = random:NextNumber(-15, 15),
			Wobble = random:NextNumber(8, 16),
		}))
	end
	-- Paillettes qui scintillent
	for _ = 1, reduced and 5 or 10 do
		local label = emoji("✨", random:NextInteger(14, 24), {
			Position = UDim2.fromScale(random:NextNumber(0.02, 0.98), random:NextNumber(0.03, 0.97)),
			ZIndex = 5,
			Parent = near,
		})
		twinkle(twinkles, label, "TextTransparency", 0.05, 1, random, 1.2, 2.6)
	end

	-- Lueur pastel en bas
	local haze = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = accent,
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.85), Parent = haze })

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			stepTwinkles(twinkles, t)
		end,
	}
end

-- Nuit lofi : aurore, nébuleuses, lune, étoiles filantes, montagnes, ville en deux plans
Decors.Stars = function(frame, theme, reduced, random)
	local twinkles: { Twinkle } = {}
	local accent: Color3 = theme.Accent
	local bottom: Color3 = theme.Bottom

	-- Plan lointain : nébuleuses + étoiles
	local far = plane(frame, 0.08, 1)
	for index, color in ipairs({ Color3.fromRGB(150, 90, 255), Color3.fromRGB(60, 200, 220), Color3.fromRGB(255, 120, 200) }) do
		local nebula = softGlow(far, random:NextInteger(380, 520), color, 0.06, 1)
		nebula.Position = UDim2.fromScale(({ 0.2, 0.62, 0.4 })[index], ({ 0.22, 0.12, 0.45 })[index])
	end
	for _ = 1, reduced and 18 or 40 do
		local d = random:NextInteger(2, 4)
		local star = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 0.7)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = random:NextNumber() < 0.3 and accent or WHITE,
			ZIndex = 1,
			Parent = far,
		})
		twinkle(twinkles, star, "BackgroundTransparency", 0.05, 0.85, random, 1, 3.2)
	end
	for _ = 1, reduced and 2 or 5 do
		local _, scale = crossStar(far, random:NextNumber(0.05, 0.95), random:NextNumber(0.05, 0.45), random:NextInteger(14, 22), WHITE, 2)
		twinkle(twinkles, scale, "Scale", 0.35, 1.1, random, 0.8, 1.6)
	end

	-- Aurore boréale : rubans colorés qui ondulent
	local aurora = plane(frame, 0.12, 1)
	local ribbons = {}
	local AURORA = {
		{ Color3.fromRGB(80, 255, 190), Color3.fromRGB(80, 170, 255), 0.2 },
		{ Color3.fromRGB(150, 110, 255), Color3.fromRGB(255, 120, 220), 0.3 },
		{ Color3.fromRGB(90, 230, 255), Color3.fromRGB(140, 255, 160), 0.26 },
	}
	for index = 1, reduced and 2 or 3 do
		local spec = AURORA[index]
		local ribbon = box({
			Name = "Aurora",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, spec[3]),
			Size = UDim2.new(1.4, 0, 0, 90 - index * 12),
			Rotation = -8 + index * 5,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			ZIndex = 1,
			Parent = aurora,
		})
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, spec[1]),
				ColorSequenceKeypoint.new(0.5, spec[2]),
				ColorSequenceKeypoint.new(1, spec[1]),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.35),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(0.8, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ribbon,
		})
		UIUtil.Corner(ribbon, UDim.new(1, 0))
		table.insert(ribbons, { Frame = ribbon, Base = ribbon.Rotation, Y = spec[3], Phase = random:NextNumber(0, 6) })
	end

	-- Lune + halo + anneau
	local moonPlane = plane(frame, 0.18, 2)
	local moonGlow = softGlow(moonPlane, 280, accent, 0.07, 2)
	moonGlow.Position = UDim2.fromScale(0.86, 0.17)
	local halo = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.17),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = moonPlane,
	})
	UIUtil.Stroke(halo, accent, 2, 0.75)
	local moon = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.17),
		Size = UDim2.fromOffset(88, 88),
		BackgroundColor3 = Color3.fromRGB(255, 246, 214),
		ZIndex = 3,
		Parent = moonPlane,
	})
	Create("UIGradient", {
		Rotation = 135,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(236, 222, 180)),
		Parent = moon,
	})
	for _, crater in ipairs({ { 0.32, 0.36, 16 }, { 0.62, 0.58, 12 }, { 0.42, 0.72, 8 } }) do
		circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(crater[1], crater[2]),
			Size = UDim2.fromOffset(crater[3], crater[3]),
			BackgroundColor3 = Color3.fromRGB(226, 212, 170),
			BackgroundTransparency = 0.3,
			ZIndex = 3,
			Parent = moon,
		})
	end

	-- Nuages sombres qui passent devant la lune
	local wisps: { Floater } = {}
	for _ = 1, 2 do
		local wisp = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(random:NextInteger(220, 340), random:NextInteger(18, 28)),
			BackgroundColor3 = bottom:Lerp(BLACK, 0.2),
			BackgroundTransparency = 0.45,
			ZIndex = 4,
			Parent = moonPlane,
		})
		UIUtil.Corner(wisp, UDim.new(1, 0))
		Create("UIGradient", { Transparency = edgeFade(0.3, 0.2), Parent = wisp })
		table.insert(wisps, newFloater(wisp, random, {
			Y = random:NextNumber(0.14, 0.32),
			VX = random:NextNumber(0.004, 0.009),
		}))
	end

	-- Étoile filante (une seule, réutilisée)
	local shooting = box({
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(140, 2),
		BackgroundColor3 = WHITE,
		Rotation = 20,
		Visible = false,
		ZIndex = 2,
		Parent = far,
	})
	Create("UIGradient", { Transparency = fadeSequence(1, 0), Parent = shooting })
	local shootTimer = random:NextNumber(3, 6)
	local shootProgress = -1
	local shootFrom, shootTo = Vector2.zero, Vector2.zero

	-- Montagnes lointaines (silhouettes bleutées)
	local mountains = plane(frame, 0.3, 4)
	local mountainColor = bottom:Lerp(BLACK, 0.3)
	for i = 0, 6 do
		local size = random:NextInteger(220, 360)
		local m = peak(mountains, i / 6 + random:NextNumber(-0.04, 0.04), 0.84, size, mountainColor:Lerp(bottom, random:NextNumber(0, 0.2)), 4)
		UIUtil.Stroke(m, accent, 1, 0.85)
	end
	local fog = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.32),
		BackgroundColor3 = accent,
		ZIndex = 4,
		Parent = mountains,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.8), Parent = fog })

	-- Villes : un plan lointain (clair) puis un plan proche (sombre, plus haut)
	local lit: { Frame } = {}
	local beacons: { Frame } = {}
	local function city(parent: Instance, color: Color3, minH: number, maxH: number, z: number, windows: number, antennas: boolean)
		local x = -0.02
		while x < 1.02 do
			local w = random:NextNumber(0.035, 0.07)
			local h = random:NextInteger(minH, maxH)
			local building = box({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(x, 1),
				Size = UDim2.new(w, 1, 0, h),
				BackgroundColor3 = color:Lerp(BLACK, random:NextNumber(0, 0.2)),
				ZIndex = z,
				Parent = parent,
			})
			-- Toit : petit décroché ou antenne avec lumière rouge
			if antennas and random:NextNumber() < 0.35 then
				box({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(random:NextNumber(0.3, 0.7), 0),
					Size = UDim2.fromOffset(2, random:NextInteger(14, 26)),
					BackgroundColor3 = building.BackgroundColor3,
					ZIndex = z,
					Parent = building,
				})
				if #beacons < 4 then
					local beacon = circle({
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0, -22),
						Size = UDim2.fromOffset(5, 5),
						BackgroundColor3 = Color3.fromRGB(255, 70, 90),
						ZIndex = z,
						Parent = building,
					})
					table.insert(beacons, beacon)
				end
			elseif random:NextNumber() < 0.3 then
				box({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.new(0.55, 0, 0, random:NextInteger(8, 16)),
					BackgroundColor3 = building.BackgroundColor3,
					ZIndex = z,
					Parent = building,
				})
			end
			if h > minH + 10 and #lit < windows then
				for _ = 1, random:NextInteger(1, 3) do
					local window = box({
						Position = UDim2.fromScale(random:NextNumber(0.15, 0.75), random:NextNumber(0.1, 0.8)),
						Size = UDim2.fromOffset(4, 6),
						BackgroundColor3 = accent,
						BackgroundTransparency = random:NextNumber() < 0.6 and 0.1 or 1,
						ZIndex = z,
						Parent = building,
					})
					table.insert(lit, window)
				end
			end
			x += w
		end
	end
	local farCity = plane(frame, 0.5, 5)
	city(farCity, bottom:Lerp(BLACK, 0.45), 60, 140, 5, reduced and 10 or 20, false)
	local cityHaze = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 160),
		BackgroundColor3 = accent,
		ZIndex = 5,
		Parent = farCity,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.82), Parent = cityHaze })
	local nearCity = plane(frame, 0.85, 6)
	city(nearCity, bottom:Lerp(BLACK, 0.7), 40, 110, 6, reduced and 18 or 36, true)

	local windowTimer = 0.6
	return {
		Update = function(dt, t)
			stepTwinkles(twinkles, t)
			stepFloaters(wisps, dt, t)
			moonGlow.Size = UDim2.fromOffset(280 + math.sin(t * 0.7) * 16, 280 + math.sin(t * 0.7) * 16)
			for _, ribbon in ipairs(ribbons) do
				local s = math.sin(t * 0.22 + ribbon.Phase)
				ribbon.Frame.Rotation = ribbon.Base + s * 3
				ribbon.Frame.Position = UDim2.fromScale(0.5 + math.sin(t * 0.13 + ribbon.Phase) * 0.05, ribbon.Y + s * 0.02)
				ribbon.Frame.BackgroundTransparency = 0.7 + 0.12 * math.sin(t * 0.5 + ribbon.Phase)
			end
			for index, beacon in ipairs(beacons) do
				beacon.BackgroundTransparency = ((t + index * 0.37) % 1.6) < 0.5 and 0 or 0.85
			end

			-- Étoile filante
			if not reduced then
				if shootProgress < 0 then
					shootTimer -= dt
					if shootTimer <= 0 then
						shootProgress = 0
						shootFrom = Vector2.new(random:NextNumber(0.05, 0.6), random:NextNumber(0.03, 0.3))
						shootTo = shootFrom + Vector2.new(random:NextNumber(0.22, 0.35), 0.18)
						shooting.Rotation = math.deg(math.atan2(0.18 * 720, (shootTo.X - shootFrom.X) * 1280))
						shooting.Visible = true
					end
				else
					shootProgress += dt / 0.9
					local p = math.min(1, shootProgress)
					local eased = 1 - (1 - p) ^ 2
					local pos = shootFrom:Lerp(shootTo, eased)
					shooting.Position = UDim2.fromScale(pos.X, pos.Y)
					shooting.BackgroundTransparency = p < 0.15 and (1 - p / 0.15) or (p - 0.15) / 0.85
					if p >= 1 then
						shooting.Visible = false
						shootProgress = -1
						shootTimer = random:NextNumber(4, 9)
					end
				end
			end

			-- Une fenêtre s'allume / s'éteint de temps en temps
			windowTimer -= dt
			if windowTimer <= 0 and #lit > 0 then
				windowTimer = random:NextNumber(0.3, 1.2)
				local window = lit[random:NextInteger(1, #lit)]
				window.BackgroundTransparency = window.BackgroundTransparency < 0.5 and 1 or 0.1
			end
		end,
	}
end

-- Coucher de soleil : soleil, bandes de lumière, mer, voilier, collines, palmiers
Decors.Sunset = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local accent: Color3 = theme.Accent
	local bottom: Color3 = theme.Bottom
	local SUN_Y = 0.6
	local SEA_Y = 0.68

	-- Rayons qui tournent lentement derrière le soleil
	local sky = plane(frame, 0.1, 1)
	local rays = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, SUN_Y),
		Size = UDim2.fromOffset(1400, 1400),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = sky,
	})
	local rayCount = reduced and 6 or 10
	for i = 1, rayCount do
		local ray = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 70, 1, 0),
			Rotation = (i - 1) * (180 / rayCount),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.82,
			ZIndex = 1,
			Parent = rays,
		})
		Create("UIGradient", { Rotation = 90, Transparency = edgeFade(0.42, 0.4), Parent = ray })
	end
	-- Bandes de lumière horizontales près de l'horizon
	for index, spec in ipairs({ { 0.44, 26, 0.7 }, { 0.52, 16, 0.6 }, { 0.36, 12, 0.78 } }) do
		local band = box({
			Name = "Band" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, spec[1]),
			Size = UDim2.new(1.1, 0, 0, spec[2]),
			BackgroundColor3 = Color3.fromRGB(255, 225, 190),
			BackgroundTransparency = spec[3],
			ZIndex = 1,
			Parent = sky,
		})
		UIUtil.Corner(band, UDim.new(1, 0))
		Create("UIGradient", { Transparency = edgeFade(0.3, 0), Parent = band })
		table.insert(floaters, newFloater(band, random, {
			X = 0.5,
			Y = spec[1],
			VX = 0,
			Amp = 0.02,
			Freq = random:NextNumber(0.05, 0.1),
		}))
	end

	-- Soleil (derrière la mer)
	local sunPlane = plane(frame, 0.15, 2)
	local sunGlow = softGlow(sunPlane, 560, accent, 0.12, 2)
	sunGlow.Position = UDim2.fromScale(0.5, SUN_Y)
	local sun = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, SUN_Y),
		Size = UDim2.fromOffset(230, 230),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = sunPlane,
	})
	vgradient(sun, accent, Color3.fromRGB(255, 140, 90))

	-- Nuages roses
	local cloudPlane = plane(frame, 0.3, 3)
	for i = 1, reduced and 3 or 5 do
		local c = cloud(cloudPlane, random:NextInteger(150, 260), Color3.fromRGB(255, 236, 236), random:NextNumber(0.2, 0.4), 3, Color3.fromRGB(255, 190, 200))
		table.insert(floaters, newFloater(c, random, {
			X = (i - 1) / 4 + random:NextNumber(-0.05, 0.05),
			Y = random:NextNumber(0.08, 0.4),
			VX = random:NextNumber(0.004, 0.01),
			Amp = 0.003,
		}))
	end

	-- Mer : dégradé + reflet du soleil qui scintille + voilier
	local seaPlane = plane(frame, 0.35, 4)
	local sea = box({
		Name = "Sea",
		Position = UDim2.fromScale(0, SEA_Y),
		Size = UDim2.fromScale(1, 1 - SEA_Y),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = seaPlane,
	})
	vgradient(sea, bottom:Lerp(Color3.fromRGB(255, 170, 150), 0.35), bottom:Lerp(Color3.fromRGB(120, 60, 130), 0.6))
	local horizon = box({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, SEA_Y),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.fromRGB(255, 240, 210),
		BackgroundTransparency = 0.3,
		ZIndex = 4,
		Parent = seaPlane,
	})
	Create("UIGradient", { Transparency = edgeFade(0.35, 0), Parent = horizon })
	local glints = {}
	for i = 1, reduced and 5 or 9 do
		local glint = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, SEA_Y + 0.02 + i * 0.028),
			Size = UDim2.fromOffset(160 - i * 8, 3),
			BackgroundColor3 = accent:Lerp(WHITE, 0.4),
			BackgroundTransparency = 0.25,
			ZIndex = 4,
			Parent = seaPlane,
		})
		UIUtil.Corner(glint, UDim.new(1, 0))
		Create("UIGradient", { Transparency = edgeFade(0.3, 0), Parent = glint })
		table.insert(glints, { Frame = glint, Base = 160 - i * 8, Phase = random:NextNumber(0, 6) })
	end
	-- Voilier en silhouette
	local boat = box({
		Name = "Boat",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(46, 44),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = seaPlane,
	})
	local boatColor = bottom:Lerp(BLACK, 0.6)
	local hull = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(44, 8),
		BackgroundColor3 = boatColor,
		ZIndex = 4,
		Parent = boat,
	})
	UIUtil.Corner(hull, UDim.new(0, 4))
	box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.fromOffset(2, 34),
		BackgroundColor3 = boatColor,
		ZIndex = 4,
		Parent = boat,
	})
	box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 9, 1, -24),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = boatColor,
		ZIndex = 4,
		Parent = boat,
	})
	local boatX = random:NextNumber(0.1, 0.3)

	-- Oiseaux (deux ailes qui battent)
	local birds = {}
	if not reduced then
		for _ = 1, 4 do
			local bird = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(22, 10),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = cloudPlane,
			})
			local wings = {}
			for side = -1, 1, 2 do
				wings[#wings + 1] = box({
					AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(11, 2),
					BackgroundColor3 = Color3.fromRGB(90, 50, 80),
					BackgroundTransparency = 0.2,
					ZIndex = 3,
					Parent = bird,
				})
			end
			table.insert(floaters, newFloater(bird, random, {
				Y = random:NextNumber(0.15, 0.4),
				VX = random:NextNumber(0.012, 0.02),
				Amp = 0,
			}))
			table.insert(birds, { Wings = wings, Phase = random:NextNumber(0, 6), Speed = random:NextNumber(5, 8) })
		end
	end

	-- Collines sur les côtés (le centre laisse voir la mer), puis palmiers
	local hillPlane = plane(frame, 0.6, 5)
	local HILLS = {
		{ 0.05, 0.74, 620, bottom:Lerp(Color3.fromRGB(150, 70, 140), 0.5) },
		{ 0.98, 0.72, 660, bottom:Lerp(Color3.fromRGB(150, 70, 140), 0.5) },
		{ -0.05, 0.82, 700, bottom:Lerp(Color3.fromRGB(90, 35, 95), 0.72) },
		{ 1.08, 0.8, 720, bottom:Lerp(Color3.fromRGB(90, 35, 95), 0.72) },
	}
	for _, spec in ipairs(HILLS) do
		local hill = mound(hillPlane, spec[1], spec[2], spec[3], spec[4], 5)
		vgradient(hill, spec[4]:Lerp(accent, 0.12), spec[4])
	end
	local palmPlane = plane(frame, 0.9, 6)
	local palmColor = bottom:Lerp(Color3.fromRGB(40, 15, 45), 0.8)
	local palms = {
		palm(palmPlane, 0.06, 0.9, 250, 1, palmColor, 6),
		palm(palmPlane, 0.94, 0.88, 280, -1, palmColor, 6),
	}
	if not reduced then
		table.insert(palms, palm(palmPlane, 0.13, 0.94, 180, 0.6, palmColor, 6))
	end

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			rays.Rotation = (t * 2) % 360
			local pulse = math.sin(t * 0.6)
			sun.Size = UDim2.fromOffset(230 + pulse * 4, 230 + pulse * 4)
			sunGlow.Size = UDim2.fromOffset(560 + pulse * 30, 560 + pulse * 30)
			for _, glint in ipairs(glints) do
				local k = math.sin(t * 1.4 + glint.Phase)
				glint.Frame.Size = UDim2.fromOffset(glint.Base * (0.75 + 0.25 * k), 3)
				glint.Frame.BackgroundTransparency = 0.3 + 0.25 * k
			end
			boatX = (boatX + dt * 0.004) % 1.2
			boat.Position = UDim2.new(boatX - 0.1, 0, SEA_Y + 0.035, math.sin(t * 1.5) * 1.5)
			boat.Rotation = math.sin(t * 1.2) * 3
			for _, bird in ipairs(birds) do
				local flap = math.sin(t * bird.Speed + bird.Phase) * 28
				bird.Wings[1].Rotation = flap
				bird.Wings[2].Rotation = -flap
			end
			for index, tree in ipairs(palms) do
				tree.Rotation = math.sin(t * 0.7 + index) * 1.5
			end
		end,
	}
end

-- Matcha : montagnes dans la brume, rayons, bokeh, bambous feuillus, feuilles
Decors.Leaves = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local accent: Color3 = theme.Accent
	local top: Color3 = theme.Top

	-- Montagnes en couches, de plus en plus nettes, séparées par de la brume
	for layerIndex, spec in ipairs({ { 0.12, 0.6, 0.55 }, { 0.22, 0.7, 0.35 }, { 0.32, 0.8, 0.15 } }) do
		local mountains = plane(frame, spec[1], layerIndex)
		local color = accent:Lerp(top, spec[3])
		for i = 0, 5 do
			peak(mountains, i / 5 + random:NextNumber(-0.06, 0.06) + layerIndex * 0.05, spec[2] + 0.12, random:NextInteger(260, 420), color, layerIndex)
		end
		local mist = box({
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromScale(0, spec[2] + 0.02),
			Size = UDim2.fromScale(1, 0.5),
			BackgroundColor3 = top:Lerp(WHITE, 0.4),
			ZIndex = layerIndex,
			Parent = mountains,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.95, 0.1), Parent = mist })
	end

	-- Rayons de soleil venant du coin
	local light = plane(frame, 0.2, 4)
	for i = 1, 3 do
		local beam = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.08 + i * 0.07, -0.1),
			Size = UDim2.new(0, 70 + i * 20, 1.4, 0),
			Rotation = -28,
			BackgroundColor3 = Color3.fromRGB(255, 255, 230),
			BackgroundTransparency = 0.82,
			ZIndex = 4,
			Parent = light,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.3, 1), Parent = beam })
	end

	-- Bokeh : halos de lumière qui montent doucement
	local bokeh = plane(frame, 0.4, 4)
	for _ = 1, reduced and 4 or 8 do
		local g = softGlow(bokeh, random:NextInteger(50, 140), Color3.fromRGB(255, 255, 215), 0.14, 4)
		table.insert(floaters, newFloater(g, random, {
			VY = -random:NextNumber(0.002, 0.006),
			Amp = random:NextNumber(0.01, 0.03),
			Freq = random:NextNumber(0.1, 0.25),
		}))
	end

	-- Bambous sur les côtés (se balancent doucement) avec des feuilles
	local bamboo = plane(frame, 0.85, 5)
	local stalks = {}
	local STALKS = { { 0.02, 22 }, { 0.055, 16 }, { 0.09, 12 }, { 0.915, 12 }, { 0.95, 18 }, { 0.985, 22 } }
	for index, spec in ipairs(STALKS) do
		if reduced and index % 2 == 0 then
			continue
		end
		local color = accent:Lerp(WHITE, random:NextNumber(0.1, 0.3))
		local stalk = box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(spec[1], 1.02),
			Size = UDim2.new(0, spec[2], 1.1, 0),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.15,
			ZIndex = 5,
			Parent = bamboo,
		})
		UIUtil.Corner(stalk, UDim.new(0, 6))
		Create("UIGradient", {
			Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.15)),
			Parent = stalk,
		})
		for k = 1, 7 do
			box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, k / 8),
				Size = UDim2.new(1, 4, 0, 3),
				BackgroundColor3 = color:Lerp(BLACK, 0.25),
				BackgroundTransparency = 0.2,
				ZIndex = 5,
				Parent = stalk,
			})
			-- Feuilles aux nœuds (une sur deux)
			if k % 2 == 0 then
				local side = (index + k) % 2 == 0 and 1 or -1
				local leaf = box({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, side * 26, k / 8, -6),
					Size = UDim2.fromOffset(46, 12),
					Rotation = side * 25,
					BackgroundColor3 = accent:Lerp(BLACK, 0.05),
					ZIndex = 5,
					Parent = stalk,
				})
				UIUtil.Corner(leaf, UDim.new(1, 0))
				vgradient(leaf, accent:Lerp(WHITE, 0.3), accent:Lerp(BLACK, 0.1))
			end
		end
		table.insert(stalks, { Frame = stalk, Phase = random:NextNumber(0, 6), Speed = random:NextNumber(0.4, 0.7) })
	end

	-- Feuilles (formes dessinées + quelques emojis) qui tombent en tournoyant
	local near = plane(frame, 1, 6)
	local LEAF_COLORS = {
		accent,
		accent:Lerp(WHITE, 0.3),
		accent:Lerp(Color3.fromRGB(200, 220, 90), 0.5),
		accent:Lerp(BLACK, 0.15),
	}
	for i = 1, reduced and 9 or 18 do
		local obj: GuiObject
		if i % 5 == 0 then
			obj = emoji("🍃", random:NextInteger(20, 30), { TextTransparency = 0.15, ZIndex = 6, Parent = near })
		else
			local w = random:NextInteger(18, 30)
			local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]
			local leaf = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(w, math.floor(w * 0.42)),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.1,
				ZIndex = 6,
				Parent = near,
			})
			UIUtil.Corner(leaf, UDim.new(1, 0))
			vgradient(leaf, color:Lerp(WHITE, 0.25), color)
			box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.75, 0, 0, 1),
				BackgroundColor3 = color:Lerp(BLACK, 0.3),
				BackgroundTransparency = 0.35,
				ZIndex = 6,
				Parent = leaf,
			})
			obj = leaf
		end
		table.insert(floaters, newFloater(obj, random, {
			VY = random:NextNumber(0.025, 0.05),
			VX = random:NextNumber(0.002, 0.01),
			Amp = random:NextNumber(0.015, 0.035),
			Freq = random:NextNumber(0.8, 1.6),
			Rot = random:NextNumber(0, 360),
			Spin = random:NextNumber(-40, 40),
			Wobble = random:NextNumber(20, 45),
		}))
	end

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			for _, stalk in ipairs(stalks) do
				stalk.Frame.Rotation = math.sin(t * stalk.Speed + stalk.Phase) * 1.4
			end
		end,
	}
end

-- Océan : reflets de surface, baleine, méduses, algues, coraux, poissons, bulles
Decors.Bubbles = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local bottom: Color3 = theme.Bottom

	-- Rayons de lumière depuis la surface
	local light = plane(frame, 0.1, 1)
	local rays = {}
	local rayCount = reduced and 4 or 6
	for i = 1, rayCount do
		local ray = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale((i - 0.5) / rayCount + random:NextNumber(-0.04, 0.04), -0.08),
			Size = UDim2.new(0, random:NextInteger(60, 140), 1.3, 0),
			Rotation = random:NextNumber(-22, -10),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			ZIndex = 1,
			Parent = light,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.2, 1), Parent = ray })
		table.insert(rays, { Frame = ray, Base = ray.Rotation, Phase = random:NextNumber(0, 6), Speed = random:NextNumber(0.2, 0.4) })
	end
	-- Reflets ondulants de la surface (caustiques)
	local surface = box({
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = light,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.55, 1), Parent = surface })
	local caustics = {}
	for i = 1, reduced and 5 or 9 do
		local line = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(random:NextInteger(80, 170), 4),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.45,
			ZIndex = 1,
			Parent = light,
		})
		UIUtil.Corner(line, UDim.new(1, 0))
		Create("UIGradient", { Transparency = edgeFade(0.3, 0), Parent = line })
		table.insert(caustics, { Frame = line, X = (i - 0.5) / (reduced and 5 or 9), Y = random:NextNumber(0.03, 0.11), Phase = random:NextNumber(0, 6) })
	end

	-- Baleine au loin (silhouette qui traverse très lentement)
	local far = plane(frame, 0.2, 2)
	local whaleColor = bottom:Lerp(Color3.fromRGB(20, 60, 110), 0.5)
	local whale = box({
		Name = "Whale",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(330, 130),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = far,
	})
	local whaleBody = circle({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.fromOffset(250, 90),
		BackgroundColor3 = whaleColor,
		BackgroundTransparency = 0.6,
		ZIndex = 2,
		Parent = whale,
	})
	whaleBody.Name = "Body"
	for _, spec in ipairs({ { 0.86, 0.42, -35 }, { 0.86, 0.68, 35 } }) do
		local fluke = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromOffset(80, 26),
			Rotation = spec[3],
			BackgroundColor3 = whaleColor,
			BackgroundTransparency = 0.6,
			ZIndex = 2,
			Parent = whale,
		})
		fluke.Name = "Fluke"
	end
	local whaleX = random:NextNumber(0, 1)

	-- Récif lointain
	local reef = plane(frame, 0.35, 3)
	for i = 0, 5 do
		local rock = mound(reef, i / 5 + random:NextNumber(-0.05, 0.05), 0.86 + random:NextNumber(-0.03, 0.03), random:NextInteger(260, 420), bottom:Lerp(BLACK, 0.3), 3)
		rock.BackgroundTransparency = 0.25
	end

	-- Méduses
	local mid = plane(frame, 0.55, 4)
	local jellies = {}
	for i = 1, reduced and 1 or 3 do
		local color = ({ Color3.fromRGB(255, 160, 220), Color3.fromRGB(190, 160, 255), Color3.fromRGB(150, 230, 255) })[i]
		local jelly = box({
			Name = "Jelly",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(60, 110),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = mid,
		})
		local domeClip = box({
			Size = UDim2.fromOffset(60, 32),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			Parent = jelly,
		})
		local dome = circle({
			Size = UDim2.fromOffset(60, 60),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.3,
			ZIndex = 4,
			Parent = domeClip,
		})
		vgradient(dome, color:Lerp(WHITE, 0.5), color)
		local tentacles = {}
		for k = 1, 4 do
			local tentacle = box({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(12 + (k - 1) * 12, 30),
				Size = UDim2.fromOffset(3, 44 + (k % 2) * 18),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.3,
				ZIndex = 4,
				Parent = jelly,
			})
			Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.1, 1), Parent = tentacle })
			table.insert(tentacles, tentacle)
		end
		local scale = Create("UIScale", { Parent = jelly })
		table.insert(jellies, { Scale = scale, Tentacles = tentacles, Phase = random:NextNumber(0, 6) })
		table.insert(floaters, newFloater(jelly, random, {
			Y = random:NextNumber(0.2, 0.9),
			VY = -random:NextNumber(0.006, 0.012),
			Amp = random:NextNumber(0.01, 0.02),
			Freq = random:NextNumber(0.3, 0.6),
			Wobble = 6,
		}))
	end

	-- Poissons
	local FISH = { "🐠", "🐟", "🐡" }
	for _ = 1, reduced and 1 or 3 do
		local fish = emoji(FISH[random:NextInteger(1, #FISH)], random:NextInteger(26, 40), {
			TextTransparency = 0.2,
			ZIndex = 4,
			Parent = mid,
		})
		table.insert(floaters, newFloater(fish, random, {
			Y = random:NextNumber(0.2, 0.8),
			VX = -random:NextNumber(0.015, 0.03),
			Amp = 0.004,
			Freq = random:NextNumber(1, 2),
			Wobble = 5,
		}))
	end

	-- Algues et coraux (premier plan, sur les côtés)
	local near = plane(frame, 0.9, 5)
	local kelps = {}
	local KELP_X = reduced and { 0.03, 0.97 } or { 0.02, 0.06, 0.1, 0.9, 0.94, 0.98 }
	for _, x in ipairs(KELP_X) do
		local segments = {}
		local color = Color3.fromRGB(60, 170, 120):Lerp(bottom, random:NextNumber(0.1, 0.35))
		local count = random:NextInteger(7, 10)
		for k = 1, count do
			local seg = circle({
				AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.fromOffset(16, 36),
				BackgroundColor3 = color:Lerp(WHITE, k / count * 0.25),
				ZIndex = 5,
				Parent = near,
			})
			table.insert(segments, seg)
		end
		table.insert(kelps, { Segments = segments, X = x, Phase = random:NextNumber(0, 6) })
	end
	local CORAL = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 170, 90), Color3.fromRGB(200, 120, 255) }
	for i = 1, reduced and 2 or 4 do
		local x = ({ 0.14, 0.86, 0.2, 0.8 })[i]
		local color = CORAL[(i - 1) % #CORAL + 1]
		for k = 1, 4 do
			circle({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(x, (k - 2.5) * 14, 1.02, 0),
				Size = UDim2.fromOffset(14, 40 + (k % 2) * 22),
				Rotation = (k - 2.5) * 12,
				BackgroundColor3 = color:Lerp(WHITE, k * 0.06),
				ZIndex = 5,
				Parent = near,
			})
		end
	end

	-- Bulles
	local bubbles = plane(frame, 1, 6)
	for _ = 1, reduced and 11 or 22 do
		local d = random:NextInteger(8, 30)
		local bubble = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.85,
			ZIndex = 6,
			Parent = bubbles,
		})
		UIUtil.Stroke(bubble, WHITE, d > 16 and 2 or 1.5, 0.3)
		circle({
			Position = UDim2.fromScale(0.2, 0.18),
			Size = UDim2.fromScale(0.28, 0.28),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			ZIndex = 6,
			Parent = bubble,
		})
		table.insert(floaters, newFloater(bubble, random, {
			VY = -random:NextNumber(0.03, 0.07) * (0.6 + d / 40),
			Amp = random:NextNumber(0.004, 0.012),
			Freq = random:NextNumber(1.5, 3),
		}))
	end

	-- Fond plus sombre en bas (profondeur)
	local deep = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.45),
		BackgroundColor3 = bottom:Lerp(BLACK, 0.35),
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.55), Parent = deep })

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			for _, ray in ipairs(rays) do
				local k = math.sin(t * ray.Speed + ray.Phase)
				ray.Frame.Rotation = ray.Base + k * 3
				ray.Frame.BackgroundTransparency = 0.8 + k * 0.08
			end
			for _, c in ipairs(caustics) do
				local k = math.sin(t * 0.9 + c.Phase)
				c.Frame.Position = UDim2.fromScale(c.X + k * 0.02, c.Y + math.cos(t * 0.7 + c.Phase) * 0.01)
				c.Frame.Rotation = k * 8
			end
			whaleX = (whaleX + dt * 0.006) % 1.6
			whale.Position = UDim2.fromScale(1.3 - whaleX, 0.34 + math.sin(t * 0.2) * 0.02)
			for _, jelly in ipairs(jellies) do
				local pulse = math.sin(t * 2 + jelly.Phase)
				jelly.Scale.Scale = 1 + pulse * 0.05
				for k, tentacle in ipairs(jelly.Tentacles) do
					tentacle.Rotation = math.sin(t * 2.2 + jelly.Phase + k) * 10
				end
			end
			for _, kelp in ipairs(kelps) do
				for k, seg in ipairs(kelp.Segments) do
					local sway = math.sin(t * 0.9 + kelp.Phase + k * 0.45) * k * 1.6
					seg.Position = UDim2.new(kelp.X, sway, 1.03, -(k - 1) * 30)
					seg.Rotation = sway * 0.8
				end
			end
		end,
	}
end

-- Bonbon : glaçage qui coule, barbe à papa, collines, sucettes, bonbons gélifiés
Decors.Candy = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local accent: Color3 = theme.Accent

	-- Rayures en diagonale qui défilent lentement
	local STRIPES = 14
	local stripes = {}
	for i = 1, STRIPES do
		local stripe = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 46, 1.35, 0),
			Rotation = 35,
			BackgroundColor3 = i % 2 == 0 and accent or WHITE,
			BackgroundTransparency = i % 2 == 0 and 0.92 or 0.6,
			ZIndex = 1,
			Parent = frame,
		})
		table.insert(stripes, { Frame = stripe, Offset = (i - 1) / STRIPES })
	end

	-- Nuages barbe à papa
	local cloudPlane = plane(frame, 0.25, 2)
	local COTTON = { Color3.fromRGB(255, 200, 230), Color3.fromRGB(200, 225, 255), Color3.fromRGB(235, 210, 255) }
	for i = 1, reduced and 2 or 4 do
		local color = COTTON[(i - 1) % #COTTON + 1]
		local c = cloud(cloudPlane, random:NextInteger(170, 250), color, 0.1, 2, color:Lerp(accent, 0.3))
		table.insert(floaters, newFloater(c, random, {
			X = (i - 1) / 3.5 + random:NextNumber(-0.04, 0.04),
			Y = random:NextNumber(0.14, 0.45),
			VX = random:NextNumber(0.004, 0.009),
			Amp = 0.004,
			Freq = random:NextNumber(0.2, 0.4),
		}))
	end

	-- Collines de bonbon en bas, sucettes et bonbons gélifiés
	local hills = plane(frame, 0.6, 3)
	for _, spec in ipairs({
		{ 0.1, 0.8, 720, Color3.fromRGB(255, 205, 225) },
		{ 0.9, 0.78, 760, Color3.fromRGB(200, 240, 225) },
		{ 0.5, 0.88, 900, Color3.fromRGB(230, 215, 255) },
	}) do
		local hill = mound(hills, spec[1], spec[2], spec[3], spec[4], 3)
		vgradient(hill, spec[4]:Lerp(WHITE, 0.4), spec[4])
		UIUtil.Stroke(hill, WHITE, 3, 0.4)
	end
	local lollipops = {}
	local LOLLI = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(80, 190, 255), Color3.fromRGB(255, 190, 60) }
	local LOLLI_X = reduced and { 0.08, 0.92 } or { 0.06, 0.16, 0.86, 0.95 }
	for index, x in ipairs(LOLLI_X) do
		local color = LOLLI[(index - 1) % #LOLLI + 1]
		local height = random:NextInteger(120, 170)
		local holder = box({
			Name = "Lollipop",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, 0.9),
			Size = UDim2.fromOffset(80, height),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = hills,
		})
		local stick = box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(0, 7, 1, -40),
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = holder,
		})
		UIUtil.Corner(stick, UDim.new(1, 0))
		UIUtil.Stroke(stick, Color3.fromRGB(230, 200, 220), 1, 0.3)
		local disc = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(76, 76),
			BackgroundColor3 = WHITE,
			ZIndex = 5,
			Parent = holder,
		})
		UIUtil.Stroke(disc, color:Lerp(BLACK, 0.1), 3, 0.2)
		Create("UIGradient", {
			Rotation = 45,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.25, WHITE),
				ColorSequenceKeypoint.new(0.5, color),
				ColorSequenceKeypoint.new(0.75, WHITE),
				ColorSequenceKeypoint.new(1, color),
			}),
			Parent = disc,
		})
		for _, k in ipairs({ 0.66, 0.34 }) do
			local ring = circle({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(k, k),
				BackgroundTransparency = 1,
				ZIndex = 5,
				Parent = disc,
			})
			UIUtil.Stroke(ring, color, 3, 0.25)
		end
		circle({
			Position = UDim2.fromScale(0.18, 0.14),
			Size = UDim2.fromScale(0.22, 0.16),
			Rotation = -30,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.2,
			ZIndex = 5,
			Parent = disc,
		})
		table.insert(lollipops, { Disc = disc, Speed = random:NextNumber(8, 16) * (index % 2 == 0 and 1 or -1) })
	end
	local GUMS = { Color3.fromRGB(255, 110, 130), Color3.fromRGB(120, 220, 140), Color3.fromRGB(255, 200, 80), Color3.fromRGB(170, 130, 255) }
	for i = 1, reduced and 3 or 6 do
		local color = GUMS[(i - 1) % #GUMS + 1]
		local gum = box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(random:NextNumber(0.2, 0.8), random:NextNumber(0.9, 0.95)),
			Size = UDim2.fromOffset(34, 30),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.05,
			ZIndex = 4,
			Parent = hills,
		})
		UIUtil.Corner(gum, UDim.new(0.5, 0))
		vgradient(gum, color:Lerp(WHITE, 0.35), color)
		circle({
			Position = UDim2.fromScale(0.2, 0.15),
			Size = UDim2.fromOffset(8, 6),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			ZIndex = 4,
			Parent = gum,
		})
	end

	-- Vermicelles colorés
	local near = plane(frame, 0.9, 5)
	local SPRINKLES = {
		Color3.fromRGB(255, 90, 170),
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(80, 200, 255),
		Color3.fromRGB(140, 230, 110),
		Color3.fromRGB(180, 120, 255),
		Color3.fromRGB(255, 150, 80),
	}
	for _ = 1, reduced and 14 or 26 do
		local sprinkle = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(5, random:NextInteger(12, 18)),
			BackgroundColor3 = SPRINKLES[random:NextInteger(1, #SPRINKLES)],
			BackgroundTransparency = 0.1,
			ZIndex = 5,
			Parent = near,
		})
		UIUtil.Corner(sprinkle, UDim.new(1, 0))
		table.insert(floaters, newFloater(sprinkle, random, {
			VY = random:NextNumber(0.008, 0.02),
			Amp = random:NextNumber(0.002, 0.008),
			Rot = random:NextNumber(0, 360),
			Spin = random:NextNumber(-30, 30),
		}))
	end
	-- Bonbons qui flottent
	local CANDIES = { "🍭", "🍬", "🍩", "🧁", "🍓", "🍡" }
	for _ = 1, reduced and 3 or 6 do
		local label = emoji(CANDIES[random:NextInteger(1, #CANDIES)], random:NextInteger(26, 38), {
			TextTransparency = 0.12,
			ZIndex = 5,
			Parent = near,
		})
		table.insert(floaters, newFloater(label, random, {
			VY = -random:NextNumber(0.008, 0.018),
			Amp = random:NextNumber(0.01, 0.02),
			Rot = random:NextNumber(-20, 20),
			Wobble = random:NextNumber(10, 20),
		}))
	end

	-- Glaçage qui coule du haut de l'écran
	local icing = plane(frame, 0.05, 6)
	local icingColor = WHITE:Lerp(accent, 0.18)
	local band = box({
		Name = "Icing",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = icingColor,
		ZIndex = 6,
		Parent = icing,
	})
	vgradient(band, WHITE, icingColor)
	local drips = {}
	local x = 0.01
	while x < 1 do
		local length = random:NextInteger(20, 70)
		local drip = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 0, 30),
			Size = UDim2.fromOffset(random:NextInteger(18, 30), length),
			BackgroundColor3 = icingColor,
			ZIndex = 6,
			Parent = icing,
		})
		UIUtil.Corner(drip, UDim.new(1, 0))
		table.insert(drips, { Frame = drip, Base = length, Phase = random:NextNumber(0, 6) })
		x += random:NextNumber(0.03, 0.06)
	end

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			local scroll = (t * 0.012) % (1 / STRIPES * 2)
			for _, s in ipairs(stripes) do
				local sx = (s.Offset + scroll) % 1
				s.Frame.Position = UDim2.fromScale(-0.3 + sx * 1.6, 0.5)
			end
			for _, lolli in ipairs(lollipops) do
				lolli.Disc.Rotation = (t * lolli.Speed) % 360
			end
			for _, drip in ipairs(drips) do
				local width = drip.Frame.Size.X.Offset
				drip.Frame.Size = UDim2.fromOffset(width, drip.Base + math.sin(t * 0.5 + drip.Phase) * 6)
			end
		end,
	}
end

-- Synthwave : soleil rayé, deux chaînes de montagnes néon, palmiers, grille
Decors.Grid = function(frame, theme, reduced, random)
	local HORIZON = 0.62
	local twinkles: { Twinkle } = {}
	local accent: Color3 = theme.Accent
	local pink = Color3.fromRGB(255, 70, 170)

	-- Étoiles
	local far = plane(frame, 0.08, 1)
	for _ = 1, reduced and 12 or 26 do
		local d = random:NextInteger(2, 3)
		local star = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0.02, HORIZON - 0.25)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = far,
		})
		twinkle(twinkles, star, "BackgroundTransparency", 0.1, 0.9, random, 1, 3)
	end
	for _ = 1, reduced and 1 or 3 do
		local _, scale = crossStar(far, random:NextNumber(0.05, 0.95), random:NextNumber(0.05, 0.3), 16, accent, 1)
		twinkle(twinkles, scale, "Scale", 0.4, 1.1, random, 0.8, 1.5)
	end

	-- Soleil rayé : CanvasGroup arrondi (les bandes sont coupées au bord du
	-- disque) ; les bandes prennent la couleur du ciel derrière
	local SUN_SIZE = 300
	local sunCenterY = HORIZON - 0.08
	local sunPlane = plane(frame, 0.12, 2)
	local sunGlow = softGlow(sunPlane, 600, pink, 0.1, 2)
	sunGlow.Position = UDim2.fromScale(0.5, sunCenterY)
	local sun = Create("CanvasGroup", {
		Name = "Sun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, sunCenterY),
		Size = UDim2.fromOffset(SUN_SIZE, SUN_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = sunPlane,
	})
	UIUtil.Corner(sun, UDim.new(1, 0))
	local sunDisc = box({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = sun,
	})
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 110)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 130, 90)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 150)),
		}),
		Parent = sunDisc,
	})
	local bands = {}
	for i = 1, 5 do
		local y = 0.5 + i * 0.085
		local band = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(1, 0, 0, 3 + i * 2),
			ZIndex = 2,
			Parent = sun,
		})
		table.insert(bands, { Frame = band, Y = y })
	end

	-- Deux chaînes de montagnes (arrière : violet clair, avant : sombre), contour néon
	local backRange = plane(frame, 0.2, 4)
	for i = 0, 7 do
		local m = peak(backRange, i / 7 + random:NextNumber(-0.03, 0.03), HORIZON + 0.02, random:NextInteger(140, 230), Color3.fromRGB(70, 20, 110), 4)
		vgradient(m, Color3.fromRGB(120, 40, 160), Color3.fromRGB(40, 8, 70))
		UIUtil.Stroke(m, pink, 1.5, 0.5)
	end
	local frontRange = plane(frame, 0.32, 4)
	for _, spec in ipairs({ { 0.08, 200 }, { 0.2, 140 }, { 0.32, 90 }, { 0.7, 110 }, { 0.82, 170 }, { 0.94, 220 } }) do
		local m = peak(frontRange, spec[1], HORIZON + 0.03, spec[2], Color3.fromRGB(28, 6, 52), 4)
		UIUtil.Stroke(m, accent, 2, 0.3)
	end

	-- Sol + grille
	local groundPlane = plane(frame, 0.5, 5)
	local ground = box({
		Name = "Ground",
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.fromScale(1, 1 - HORIZON),
		BackgroundColor3 = Color3.fromRGB(16, 2, 34),
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = groundPlane,
	})
	vgradient(ground, Color3.fromRGB(60, 10, 90), Color3.fromRGB(12, 0, 28))
	local horizonLine = box({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = pink,
		ZIndex = 6,
		Parent = groundPlane,
	})
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.8),
		}),
		Parent = horizonLine,
	})
	local horizonGlow = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = pink,
		ZIndex = 5,
		Parent = groundPlane,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.7), Parent = horizonGlow })

	local H_LINES = reduced and 7 or 10
	local hLines = {}
	for index = 1, H_LINES do
		hLines[index] = box({
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = accent,
			ZIndex = 6,
			Parent = ground,
		})
	end
	local vLines = {}
	for k = -7, 7 do
		local line = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = accent,
			ZIndex = 6,
			Parent = ground,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.9, 0.25), Parent = line })
		table.insert(vLines, { Frame = line, K = k })
	end

	-- Palmiers en silhouette sur les côtés
	local palmPlane = plane(frame, 0.9, 7)
	local palmColor = Color3.fromRGB(20, 4, 36)
	local palms = { palm(palmPlane, 0.05, 1.02, 300, 1, palmColor, 7), palm(palmPlane, 0.95, 1.02, 320, -1, palmColor, 7) }
	if not reduced then
		table.insert(palms, palm(palmPlane, 0.13, 1.02, 200, 0.7, palmColor, 7))
		table.insert(palms, palm(palmPlane, 0.87, 1.02, 210, -0.7, palmColor, 7))
	end

	-- Vignette sombre en haut
	local vignette = box({
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = BLACK,
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.6, 1), Parent = vignette })

	-- Lignes fuyantes : partent du centre de l'horizon (dépend du format de l'écran)
	local function layout()
		local absolute = ground.AbsoluteSize
		if absolute.Y < 1 then
			return
		end
		local aspect = absolute.X / absolute.Y
		for _, entry in ipairs(vLines) do
			local dx = entry.K * aspect * 0.2
			entry.Frame.Size = UDim2.new(0, 2, math.sqrt(dx * dx + 1), 0)
			entry.Frame.Position = UDim2.fromScale((aspect / 2 + dx / 2) / aspect, 0.5)
			entry.Frame.Rotation = -math.deg(math.atan2(dx, 1))
		end
		-- Bandes du soleil : couleur du ciel à leur hauteur
		local canvas = frame.AbsoluteSize
		if canvas.Y > 0 then
			local scale = sun.AbsoluteSize.Y / SUN_SIZE
			for _, band in ipairs(bands) do
				local y = (sun.AbsolutePosition.Y - frame.AbsolutePosition.Y + band.Y * SUN_SIZE * scale) / canvas.Y
				band.Frame.BackgroundColor3 = skyAt(theme, y):Lerp(pink, 0.2) -- (+ la lueur du soleil)
			end
		end
	end

	local scroll = 0
	return {
		Layout = layout,
		Update = function(dt, t)
			stepTwinkles(twinkles, t)
			scroll = (scroll + dt * 0.2) % 1
			for index, line in ipairs(hLines) do
				local z = ((index - 1) / H_LINES + scroll) % 1
				line.Position = UDim2.fromScale(0, z ^ 2.1)
				line.BackgroundTransparency = 0.85 - z * 0.7
			end
			local pulse = math.sin(t * 0.8)
			sunGlow.Size = UDim2.fromOffset(600 + pulse * 30, 600 + pulse * 30)
			horizonGlow.BackgroundTransparency = 0.1 + 0.1 * pulse
			for index, tree in ipairs(palms) do
				tree.Rotation = math.sin(t * 0.8 + index) * 1.2
			end
		end,
	}
end

----------------------------------------------------------------------
-- Thème courant
----------------------------------------------------------------------

local function getTheme(id: string?): any
	local theme = id and Config.ThemesById[id]
	if theme then
		return theme
	end
	return Config.ThemesById[DEFAULT_THEME] or Config.Themes[1]
end

local function equippedId(): string
	local data = ClientState.Data
	local themes = data and data.Themes
	local id = themes and themes.Equipped
	if type(id) == "string" and Config.ThemesById[id] then
		return id
	end
	return DEFAULT_THEME
end

local function isReduced(): boolean
	local data = ClientState.Data
	return data ~= nil and data.Settings ~= nil and data.Settings.Effects == false
end

-- Mode sombre voulu : thème sombre OU mode néon possédé.
-- (source "principale" de ClientState ; le stimulus NeonMode a sa propre source)
local function desiredDark(): boolean
	local theme = getTheme(currentThemeId)
	return (theme and theme.Dark == true) or ClientState.HasFeature("NeonMode")
end

local function applyDark()
	ClientState.SetDarkMode(desiredDark())
end

-- Construit le décor d'un thème dans un nouveau cadre plein écran.
-- Renvoie (cadre, Update ou nil, Layout ou nil, plans de parallaxe)
local function buildDecor(theme, reduced: boolean, random: Random): (Frame, ((dt: number, t: number) -> ())?, (() -> ())?, { Plane })
	local frame = box({
		Name = "Theme_" .. tostring(theme.Id),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 1,
	})
	UIUtil.Gradient(frame, ColorSequence.new(theme.Top, theme.Bottom), 90)

	local planes: { Plane } = {}
	buildingPlanes = planes
	local builder = Decors[theme.Decor] or Decors.None
	local ok, result = pcall(builder, frame, theme, reduced, random)
	buildingPlanes = nil
	if not ok then
		warn("[Background] Erreur dans le décor " .. tostring(theme.Decor) .. " : " .. tostring(result))
		return frame, nil, nil, planes
	end
	if type(result) ~= "table" then
		return frame, nil, nil, planes
	end
	return frame, result.Update, result.Layout, planes
end

-- Branche la mise en page (Layout) d'un décor sur la taille de son cadre
local function bindLayout(frame: Frame, layout: (() -> ())?)
	if not layout then
		return
	end
	local function safeLayout()
		local success, err = pcall(layout)
		if not success then
			warn("[Background] Erreur de mise en page : " .. tostring(err))
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(safeLayout)
	task.defer(safeLayout)
end

local function buildLayer(theme, reduced: boolean): Layer
	local target = root :: Frame
	local frame, update, layout, planes = buildDecor(theme, reduced, Random.new())
	frame.Parent = target
	bindLayout(frame, layout)
	local layer: Layer = { Frame = frame, Update = update, Time = 0, Planes = planes }
	table.insert(layers, layer)
	return layer
end

local function removeLayer(layer: Layer)
	local index = table.find(layers, layer)
	if index then
		table.remove(layers, index)
	end
	if layer.Frame.Parent then
		layer.Frame:Destroy()
	end
end

-- Affiche un thème (fondu enchaîné sauf `instant`)
local function showTheme(themeId: string, reduced: boolean, instant: boolean)
	if not root then
		return
	end
	local theme = getTheme(themeId)
	local changedTheme = currentThemeId ~= theme.Id
	currentThemeId = theme.Id
	currentReduced = reduced

	local previous = layers[#layers]
	local layer = buildLayer(theme, reduced)

	-- L'ancien décor passe AU-DESSUS du nouveau (dans un CanvasGroup) et s'efface
	if previous and previous ~= layer then
		if instant then
			removeLayer(previous)
		else
			local group = Create("CanvasGroup", {
				Name = "FadeOut",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				GroupTransparency = 0,
				ZIndex = 2,
				Parent = root,
			})
			previous.Frame.Parent = group
			UIUtil.Tween(group, CROSSFADE_TIME, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
			task.delay(CROSSFADE_TIME + 0.05, function()
				removeLayer(previous)
				group:Destroy()
			end)
		end
	end
	-- Les couches plus anciennes encore visibles (changements rapides) disparaissent
	for i = #layers - 2, 1, -1 do
		local old = layers[i]
		if old ~= previous then
			local parent = old.Frame.Parent
			removeLayer(old)
			if parent and parent:IsA("CanvasGroup") then
				parent:Destroy()
			end
		end
	end

	if changedTheme then
		applyDark()
		Background.ThemeChanged:Fire(theme)
	end
end

local function refresh()
	local id = equippedId()
	local reduced = isReduced()
	if id ~= currentThemeId or reduced ~= currentReduced then
		showTheme(id, reduced, false)
	end
end

-- Cible de la parallaxe (-1..1) : position de la souris, ou dérive lente (tactile)
local function parallaxTarget(clock: number): Vector2
	if UserInputService.MouseEnabled then
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		if viewport.X > 1 and viewport.Y > 1 then
			local mouse = UserInputService:GetMouseLocation()
			return Vector2.new(
				math.clamp(mouse.X / viewport.X * 2 - 1, -1, 1),
				math.clamp(mouse.Y / viewport.Y * 2 - 1, -1, 1)
			)
		end
	end
	return Vector2.new(math.sin(clock * 0.11) * 0.6, math.sin(clock * 0.07) * 0.5)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- `parent` = calque Background de l'Interface (ou la ScreenGui en secours)
function Background.Build(parent: Instance)
	local bg = box({
		Name = "ThemeBackground",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Background,
		ClipsDescendants = true,
		ZIndex = 0, -- sous les fonds des stimuli (ZIndex >= 1)
		Parent = parent,
	})
	root = bg

	-- Lueur du Rush (invisible par défaut, au-dessus du décor)
	local rushGlow = box({
		Name = "RushGlow",
		Size = UDim2.new(1, 0, 0.45, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = bg,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.3), Parent = rushGlow })
	glow = rushGlow

	showTheme(equippedId(), isReduced(), true)

	-- Une seule boucle anime tout (couche actuelle + celles qui s'effacent)
	RunService.Heartbeat:Connect(function(dt: number)
		local speed = rushActive and 1.8 or 1
		local clock = os.clock()
		-- Parallaxe lissée (désactivée si les effets sont coupés)
		local target = currentReduced and Vector2.zero or parallaxTarget(clock)
		parallax += (target - parallax) * (1 - math.exp(-2.5 * dt))

		for _, layer in ipairs(table.clone(layers)) do
			local update = layer.Update
			if update then
				layer.Time += dt * speed
				local ok, err = pcall(update, dt * speed, layer.Time)
				if not ok then
					layer.Update = nil
					warn("[Background] Animation arrêtée : " .. tostring(err))
				end
			end
			for _, p in ipairs(layer.Planes) do
				p.Frame.Position = UDim2.new(0.5, -parallax.X * p.Depth * PARALLAX_X, 0.5, -parallax.Y * p.Depth * PARALLAX_Y)
			end
		end

		local g = glow
		if g then
			if rushActive then
				g.BackgroundTransparency = 0.55 + math.sin(clock * 3) * 0.2
			elseif g.BackgroundTransparency < 1 then
				g.BackgroundTransparency = math.min(1, g.BackgroundTransparency + 0.02)
			end
		end
	end)

	ClientState.Changed:Connect(refresh)
	ClientState.FeaturesChanged:Connect(applyDark)
	applyDark()
	return bg
end

function Background.SetRush(active: boolean)
	rushActive = active == true
end

-- Thème actuellement affiché (table de Config.Themes)
function Background.GetTheme(): any
	return getTheme(currentThemeId)
end

-- Vrai si le fond demande le mode sombre (thème sombre ou mode néon)
function Background.IsDark(): boolean
	return desiredDark()
end

-- Vrai si le thème ÉQUIPÉ est sombre (sans compter le mode néon)
function Background.IsThemeDark(): boolean
	local theme = getTheme(currentThemeId)
	return theme ~= nil and theme.Dark == true
end

-- Miniature animée d'un thème (le vrai décor, réduit) dans `parent`.
-- L'appelant fait avancer l'animation avec preview.Update(dt) et la
-- détruit avec preview.Destroy(). Version allégée (moins d'éléments).
function Background.BuildPreview(parent: GuiObject, themeId: string): Preview
	local theme = getTheme(themeId)
	local holder = box({
		Name = "ThemePreview",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local scale = Create("UIScale", { Scale = 0.12, Parent = holder })
	local frame, update, layout, _ = buildDecor(theme, true, Random.new(7))
	frame.Parent = holder
	holder.Parent = parent
	bindLayout(frame, layout)

	-- Mise à l'échelle "couvrante" : la miniature remplit le parent
	local connections = {}
	local function fit()
		local target = parent.AbsoluteSize
		local current = holder.AbsoluteSize
		if target.X < 1 or target.Y < 1 or current.X < 1 or current.Y < 1 then
			return
		end
		local factor = math.max(target.X / current.X, target.Y / current.Y)
		if math.abs(factor - 1) > 0.002 then
			scale.Scale = math.clamp(scale.Scale * factor, 0.02, 2)
		end
	end
	table.insert(connections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	-- (la taille du support n'est connue qu'après la première mise en page)
	table.insert(connections, holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	task.defer(fit)

	local time = 0
	local alive = true
	local preview: Preview = {
		Frame = holder,
		Update = function(dt: number)
			if not alive or not update then
				return
			end
			time += dt
			local ok, err = pcall(update, dt, time)
			if not ok then
				update = nil
				warn("[Background] Aperçu arrêté : " .. tostring(err))
			end
		end,
		Destroy = function()
			alive = false
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			holder:Destroy()
		end,
	}
	return preview
end

return Background
