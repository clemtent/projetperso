--[[
	Background (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Background

	Fond d'écran du jeu, piloté par le thème équipé (Config.Themes, état
	ClientState.Data.Themes.Equipped, "Classic" par défaut) :
	  - un dégradé vertical (Top -> Bottom du thème) ;
	  - une décoration animée selon theme.Decor :
	      "None"    : blanc / gris épuré (quelques halos très discrets)
	      "Kawaii"  : nuages, cœurs, étoiles et paillettes pastel
	      "Stars"   : nuit étoilée, lune, étoiles filantes, ville au loin
	      "Sunset"  : soleil couchant, collines en couches, nuages, oiseaux
	      "Leaves"  : bambous et feuilles qui tombent en virevoltant
	      "Bubbles" : rayons de lumière, bulles qui montent, poissons
	      "Candy"   : rayures de sucre d'orge, vermicelles, bonbons
	      "Grid"    : synthwave (soleil rayé, montagnes, grille qui défile)
	  - fondu enchaîné quand le thème change ;
	  - moins d'éléments si le joueur a coupé les effets (Settings.Effects).

	Mode sombre : actif si le thème est sombre (theme.Dark) OU si le joueur
	possède le mode néon (Feature "NeonMode") -> ClientState.SetDarkMode.
	Dopamine Rush : une lueur jaune pulse doucement en bas de l'écran
	(Background.SetRush).

	Tout est dessiné en code (Frames, UIGradient, UICorner, emojis), et
	animé par UNE seule boucle (Heartbeat) sans créer d'objets à chaque image.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Background = {}

Background.ThemeChanged = Signal.new() -- (theme) : le thème affiché a changé

type Layer = {
	Frame: Frame,
	Update: ((dt: number, t: number) -> ())?,
	Time: number,
}

local DEFAULT_THEME = "Classic"
local CROSSFADE_TIME = 0.9

local root: Frame? = nil
local glow: Frame? = nil
local rushActive = false
local currentThemeId: string? = nil
local currentReduced = false
local layers: { Layer } = {} -- couches animées (actuelle + celles qui s'effacent)

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
local function cloud(parent: Instance, width: number, color: Color3, transparency: number, z: number): CanvasGroup
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
	-- Petit ombrage en bas
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(225, 225, 235)),
		Parent = group,
	})
	return group
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
		if f.X < -0.12 then
			f.X += 1.24
		elseif f.X > 1.12 then
			f.X -= 1.24
		end
		local sway = math.sin(t * f.Freq + f.Phase)
		f.Obj.Position = UDim2.fromScale(f.X + sway * f.Amp, f.Y)
		if f.Spin ~= 0 or f.Wobble ~= 0 then
			f.Obj.Rotation = (f.Rot + f.Spin * t) % 360 + sway * f.Wobble
		end
	end
end

-- Scintillement : { Obj, Property, Min, Max, Speed, Phase } (transparences)
type Twinkle = { Obj: GuiObject, Property: string, Min: number, Max: number, Speed: number, Phase: number }

local function stepTwinkles(list: { Twinkle }, t: number)
	for _, tw in ipairs(list) do
		local k = 0.5 + 0.5 * math.sin(t * tw.Speed + tw.Phase)
		local object: any = tw.Obj
		object[tw.Property] = tw.Min + (tw.Max - tw.Min) * k
	end
end

-- Couleur du ciel (dégradé du thème) à la hauteur y (0 = haut, 1 = bas)
local function skyAt(theme, y: number): Color3
	return (theme.Top :: Color3):Lerp(theme.Bottom, math.clamp(y, 0, 1))
end

----------------------------------------------------------------------
-- Décors (chaque fonction construit dans `frame` et renvoie Update / Layout)
----------------------------------------------------------------------

type DecorResult = { Update: ((dt: number, t: number) -> ())?, Layout: (() -> ())? }
type DecorBuilder = (frame: Frame, theme: any, reduced: boolean, random: Random) -> DecorResult

local Decors: { [string]: DecorBuilder } = {}

-- Classique : blanc / gris épuré, avec des halos presque invisibles
Decors.None = function(frame, _theme, reduced, random)
	local blobs = {}
	local count = reduced and 3 or 5
	for i = 1, count do
		local color = (i % 2 == 0) and Color3.fromRGB(200, 200, 208) or WHITE
		local blob = softGlow(frame, random:NextInteger(280, 460), color, i % 2 == 0 and 0.05 or 0.35, 1)
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
		end,
	}
end

-- Kawaii : nuages pastel, cœurs / étoiles qui montent, paillettes
Decors.Kawaii = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local twinkles: { Twinkle } = {}

	-- Pois blancs (statiques)
	for _ = 1, reduced and 14 or 26 do
		local d = random:NextInteger(6, 14)
		circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = random:NextNumber(0.35, 0.6),
			ZIndex = 1,
			Parent = frame,
		})
	end

	-- Nuages qui dérivent
	for i = 1, reduced and 3 or 5 do
		local c = cloud(frame, random:NextInteger(140, 240), WHITE, random:NextNumber(0.05, 0.25), 2)
		table.insert(floaters, newFloater(c, random, {
			X = (i - 1) / 4 + random:NextNumber(-0.05, 0.05),
			Y = random:NextNumber(0.08, 0.6),
			VX = random:NextNumber(0.006, 0.013),
			Amp = 0.004,
			Freq = random:NextNumber(0.2, 0.4),
		}))
	end

	-- Cœurs, étoiles, fleurs qui montent en se dandinant
	local ICONS = { "💗", "💖", "⭐", "🌸", "💕", "🎀", "💗", "⭐" }
	for _ = 1, reduced and 7 or 14 do
		local size = random:NextInteger(18, 34)
		local label = emoji(ICONS[random:NextInteger(1, #ICONS)], size, {
			TextTransparency = random:NextNumber(0.15, 0.4),
			ZIndex = 3,
			Parent = frame,
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
			ZIndex = 3,
			Parent = frame,
		})
		table.insert(twinkles, {
			Obj = label,
			Property = "TextTransparency",
			Min = 0.05,
			Max = 1,
			Speed = random:NextNumber(1.2, 2.6),
			Phase = random:NextNumber(0, math.pi * 2),
		})
	end

	-- Lueur pastel en bas
	local haze = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = theme.Accent,
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.82), Parent = haze })

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			stepTwinkles(twinkles, t)
		end,
	}
end

-- Nuit étoilée : étoiles, lune, étoiles filantes, ville au loin
Decors.Stars = function(frame, theme, reduced, random)
	local twinkles: { Twinkle } = {}

	-- Étoiles
	for _ = 1, reduced and 18 or 36 do
		local d = random:NextInteger(2, 4)
		local star = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 0.72)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = random:NextNumber() < 0.3 and theme.Accent or WHITE,
			ZIndex = 1,
			Parent = frame,
		})
		table.insert(twinkles, {
			Obj = star,
			Property = "BackgroundTransparency",
			Min = 0.05,
			Max = 0.85,
			Speed = random:NextNumber(1, 3.2),
			Phase = random:NextNumber(0, math.pi * 2),
		})
	end
	-- Quelques grosses étoiles en croix
	for _ = 1, reduced and 2 or 4 do
		local holder = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0.05, 0.95), random:NextNumber(0.05, 0.5)),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = frame,
		})
		for _, rotation in ipairs({ 0, 90 }) do
			box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0, 2, 1, 0),
				Rotation = rotation,
				BackgroundColor3 = WHITE,
				ZIndex = 2,
				Parent = holder,
			})
		end
		local scale = Create("UIScale", { Parent = holder })
		table.insert(twinkles, {
			Obj = scale :: any,
			Property = "Scale",
			Min = 0.35,
			Max = 1.1,
			Speed = random:NextNumber(0.8, 1.6),
			Phase = random:NextNumber(0, math.pi * 2),
		})
	end

	-- Lune
	local moonGlow = softGlow(frame, 260, theme.Accent, 0.07, 2)
	moonGlow.Position = UDim2.fromScale(0.85, 0.17)
	local moon = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.85, 0.17),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Color3.fromRGB(255, 246, 214),
		ZIndex = 3,
		Parent = frame,
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
			BackgroundColor3 = (theme.Bottom :: Color3):Lerp(BLACK, 0.2),
			BackgroundTransparency = 0.45,
			ZIndex = 4,
			Parent = frame,
		})
		UIUtil.Corner(wisp, UDim.new(1, 0))
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.2),
				NumberSequenceKeypoint.new(0.7, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = wisp,
		})
		table.insert(wisps, newFloater(wisp, random, {
			Y = random:NextNumber(0.14, 0.32),
			VX = random:NextNumber(0.004, 0.009),
		}))
	end

	-- Étoile filante (une seule, réutilisée)
	local shooting = box({
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(120, 2),
		BackgroundColor3 = WHITE,
		Rotation = 20,
		Visible = false,
		ZIndex = 2,
		Parent = frame,
	})
	Create("UIGradient", { Transparency = fadeSequence(1, 0), Parent = shooting })
	local shootTimer = random:NextNumber(3, 6)
	local shootProgress = -1
	local shootFrom, shootTo = Vector2.zero, Vector2.zero

	-- Ville au loin (silhouettes + fenêtres allumées)
	local skyline = (theme.Bottom :: Color3):Lerp(BLACK, 0.55)
	local lit: { Frame } = {}
	local x = -0.01
	while x < 1 do
		local w = random:NextNumber(0.035, 0.075)
		local h = random:NextInteger(50, 150)
		local building = box({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(x, 1),
			Size = UDim2.new(w, 1, 0, h),
			BackgroundColor3 = skyline:Lerp(BLACK, random:NextNumber(0, 0.25)),
			ZIndex = 5,
			Parent = frame,
		})
		if h > 70 and #lit < (reduced and 12 or 26) then
			for _ = 1, random:NextInteger(1, 3) do
				local window = box({
					Position = UDim2.fromScale(random:NextNumber(0.15, 0.75), random:NextNumber(0.1, 0.8)),
					Size = UDim2.fromOffset(4, 6),
					BackgroundColor3 = theme.Accent,
					BackgroundTransparency = random:NextNumber() < 0.6 and 0.1 or 1,
					ZIndex = 5,
					Parent = building,
				})
				table.insert(lit, window)
			end
		end
		x += w
	end
	-- Brume lumineuse au-dessus de la ville
	local haze = box({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -40),
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundColor3 = theme.Accent,
		ZIndex = 4,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(1, 0.85), Parent = haze })

	local windowTimer = 0.6
	return {
		Update = function(dt, t)
			stepTwinkles(twinkles, t)
			stepFloaters(wisps, dt, t)
			moonGlow.Size = UDim2.fromOffset(260 + math.sin(t * 0.7) * 14, 260 + math.sin(t * 0.7) * 14)

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
				windowTimer = random:NextNumber(0.4, 1.4)
				local window = lit[random:NextInteger(1, #lit)]
				window.BackgroundTransparency = window.BackgroundTransparency < 0.5 and 1 or 0.1
			end
		end,
	}
end

-- Coucher de soleil : soleil, rayons, collines en couches, nuages, oiseaux
Decors.Sunset = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local SUN_Y = 0.64

	-- Rayons qui tournent lentement derrière le soleil
	local rays = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, SUN_Y),
		Size = UDim2.fromOffset(1400, 1400),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = frame,
	})
	for i = 1, reduced and 6 or 10 do
		local ray = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 70, 1, 0),
			Rotation = (i - 1) * (180 / (reduced and 6 or 10)),
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 0.8,
			ZIndex = 1,
			Parent = rays,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 0.4),
				NumberSequenceKeypoint.new(0.58, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end

	-- Soleil
	local sunGlow = softGlow(frame, 520, theme.Accent, 0.12, 2)
	sunGlow.Position = UDim2.fromScale(0.5, SUN_Y)
	local sun = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, SUN_Y),
		Size = UDim2.fromOffset(230, 230),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = frame,
	})
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(theme.Accent, Color3.fromRGB(255, 150, 90)),
		Parent = sun,
	})

	-- Nuages roses
	for i = 1, reduced and 3 or 5 do
		local c = cloud(frame, random:NextInteger(150, 260), Color3.fromRGB(255, 236, 236), random:NextNumber(0.25, 0.45), 4)
		table.insert(floaters, newFloater(c, random, {
			X = (i - 1) / 4 + random:NextNumber(-0.05, 0.05),
			Y = random:NextNumber(0.08, 0.45),
			VX = random:NextNumber(0.004, 0.01),
			Amp = 0.003,
		}))
	end

	-- Oiseaux (deux ailes qui battent)
	local birds = {}
	if not reduced then
		for _ = 1, 3 do
			local bird = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(22, 10),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Parent = frame,
			})
			local wings = {}
			for side = -1, 1, 2 do
				wings[#wings + 1] = box({
					AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(11, 2),
					BackgroundColor3 = Color3.fromRGB(90, 50, 80),
					BackgroundTransparency = 0.2,
					ZIndex = 4,
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

	-- Collines (grands disques dont on ne voit que le haut)
	local hillLayers = {}
	local HILLS = {
		{ Color = (theme.Bottom :: Color3):Lerp(Color3.fromRGB(150, 70, 140), 0.45), Top = 0.7, Z = 5 },
		{ Color = (theme.Bottom :: Color3):Lerp(Color3.fromRGB(110, 45, 110), 0.65), Top = 0.78, Z = 6 },
		{ Color = (theme.Bottom :: Color3):Lerp(Color3.fromRGB(70, 30, 80), 0.8), Top = 0.87, Z = 7 },
	}
	for index, spec in ipairs(HILLS) do
		local holder = box({
			Size = UDim2.fromScale(1.1, 1),
			Position = UDim2.fromScale(-0.05, 0),
			BackgroundTransparency = 1,
			ZIndex = spec.Z,
			Parent = frame,
		})
		for k = 0, 3 do
			local diameter = random:NextInteger(520, 900)
			circle({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(k * 0.32 + random:NextNumber(0, 0.1) + (index % 2) * 0.12, spec.Top + random:NextNumber(-0.04, 0.04)),
				Size = UDim2.fromOffset(diameter, diameter),
				BackgroundColor3 = spec.Color,
				ZIndex = spec.Z,
				Parent = holder,
			})
		end
		table.insert(hillLayers, { Holder = holder, Depth = index })
	end

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			rays.Rotation = (t * 2) % 360
			local pulse = math.sin(t * 0.6)
			sun.Size = UDim2.fromOffset(230 + pulse * 4, 230 + pulse * 4)
			sunGlow.Size = UDim2.fromOffset(520 + pulse * 30, 520 + pulse * 30)
			for _, bird in ipairs(birds) do
				local flap = math.sin(t * bird.Speed + bird.Phase) * 28
				bird.Wings[1].Rotation = flap
				bird.Wings[2].Rotation = -flap
			end
			for _, hills in ipairs(hillLayers) do
				hills.Holder.Position = UDim2.fromScale(-0.05 + math.sin(t * 0.05 + hills.Depth) * 0.004 * hills.Depth, 0)
			end
		end,
	}
end

-- Matcha : bambous, halos de lumière, feuilles qui tombent
Decors.Leaves = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}
	local accent: Color3 = theme.Accent

	-- Halos de lumière
	local glows = {}
	for _ = 1, reduced and 3 or 6 do
		local g = softGlow(frame, random:NextInteger(120, 260), Color3.fromRGB(255, 255, 220), 0.12, 1)
		table.insert(floaters, newFloater(g, random, {
			VY = -random:NextNumber(0.002, 0.006),
			Amp = random:NextNumber(0.01, 0.03),
			Freq = random:NextNumber(0.1, 0.25),
		}))
		table.insert(glows, g)
	end

	-- Rayons de soleil venant du coin
	for i = 1, 3 do
		local beam = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.08 + i * 0.07, -0.1),
			Size = UDim2.new(0, 70 + i * 20, 1.4, 0),
			Rotation = -28,
			BackgroundColor3 = Color3.fromRGB(255, 255, 230),
			BackgroundTransparency = 0.82,
			ZIndex = 1,
			Parent = frame,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.3, 1), Parent = beam })
	end

	-- Bambous sur les côtés (se balancent doucement)
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
			BackgroundTransparency = 0.25,
			ZIndex = 2,
			Parent = frame,
		})
		UIUtil.Corner(stalk, UDim.new(0, 6))
		Create("UIGradient", {
			Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.12)),
			Parent = stalk,
		})
		for k = 1, 7 do
			box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, k / 8),
				Size = UDim2.new(1, 4, 0, 3),
				BackgroundColor3 = color:Lerp(BLACK, 0.25),
				BackgroundTransparency = 0.2,
				ZIndex = 2,
				Parent = stalk,
			})
		end
		table.insert(stalks, { Frame = stalk, Phase = random:NextNumber(0, 6), Speed = random:NextNumber(0.4, 0.7) })
	end

	-- Feuilles (formes dessinées + quelques emojis) qui tombent en tournoyant
	local LEAF_COLORS = {
		accent,
		accent:Lerp(WHITE, 0.3),
		accent:Lerp(Color3.fromRGB(200, 220, 90), 0.5),
		accent:Lerp(BLACK, 0.15),
	}
	for i = 1, reduced and 9 or 18 do
		local obj: GuiObject
		if i % 5 == 0 then
			obj = emoji("🍃", random:NextInteger(20, 30), { TextTransparency = 0.15, ZIndex = 3, Parent = frame })
		else
			local w = random:NextInteger(18, 30)
			local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]
			local leaf = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(w, math.floor(w * 0.42)),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.1,
				ZIndex = 3,
				Parent = frame,
			})
			UIUtil.Corner(leaf, UDim.new(1, 0))
			Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color), Parent = leaf })
			box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.75, 0, 0, 1),
				BackgroundColor3 = color:Lerp(BLACK, 0.3),
				BackgroundTransparency = 0.35,
				ZIndex = 3,
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

-- Océan : rayons de lumière, bulles qui montent, poissons
Decors.Bubbles = function(frame, theme, reduced, random)
	local floaters: { Floater } = {}

	-- Rayons de lumière depuis la surface
	local rays = {}
	for i = 1, reduced and 4 or 6 do
		local ray = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale((i - 0.5) / (reduced and 4 or 6) + random:NextNumber(-0.04, 0.04), -0.08),
			Size = UDim2.new(0, random:NextInteger(60, 140), 1.3, 0),
			Rotation = random:NextNumber(-22, -10),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			ZIndex = 1,
			Parent = frame,
		})
		Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.2, 1), Parent = ray })
		table.insert(rays, { Frame = ray, Base = ray.Rotation, Phase = random:NextNumber(0, 6), Speed = random:NextNumber(0.2, 0.4) })
	end

	-- Reflets de surface en haut
	local surface = box({
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = frame,
	})
	Create("UIGradient", { Rotation = 90, Transparency = fadeSequence(0.55, 1), Parent = surface })

	-- Poissons
	local FISH = { "🐠", "🐟", "🐡" }
	for _ = 1, reduced and 1 or 3 do
		local fish = emoji(FISH[random:NextInteger(1, #FISH)], random:NextInteger(26, 40), {
			TextTransparency = 0.3,
			ZIndex = 2,
			Parent = frame,
		})
		table.insert(floaters, newFloater(fish, random, {
			Y = random:NextNumber(0.2, 0.8),
			VX = -random:NextNumber(0.015, 0.03),
			Amp = 0.004,
			Freq = random:NextNumber(1, 2),
			Wobble = 5,
		}))
	end

	-- Bulles
	for _ = 1, reduced and 11 or 22 do
		local d = random:NextInteger(8, 30)
		local bubble = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.85,
			ZIndex = 3,
			Parent = frame,
		})
		UIUtil.Stroke(bubble, WHITE, d > 16 and 2 or 1.5, 0.3)
		circle({
			Position = UDim2.fromScale(0.2, 0.18),
			Size = UDim2.fromScale(0.28, 0.28),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			ZIndex = 3,
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
		BackgroundColor3 = (theme.Bottom :: Color3):Lerp(BLACK, 0.35),
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
		end,
	}
end

-- Bonbon : rayures de sucre d'orge, vermicelles, bonbons qui flottent
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
			BackgroundTransparency = i % 2 == 0 and 0.9 or 0.55,
			ZIndex = 1,
			Parent = frame,
		})
		table.insert(stripes, { Frame = stripe, Offset = (i - 1) / STRIPES })
	end

	-- Vermicelles colorés
	local SPRINKLES = {
		Color3.fromRGB(255, 90, 170),
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(80, 200, 255),
		Color3.fromRGB(140, 230, 110),
		Color3.fromRGB(180, 120, 255),
		Color3.fromRGB(255, 150, 80),
	}
	for _ = 1, reduced and 15 or 30 do
		local sprinkle = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(5, random:NextInteger(12, 18)),
			BackgroundColor3 = SPRINKLES[random:NextInteger(1, #SPRINKLES)],
			BackgroundTransparency = 0.1,
			ZIndex = 2,
			Parent = frame,
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
	for _ = 1, reduced and 4 or 8 do
		local label = emoji(CANDIES[random:NextInteger(1, #CANDIES)], random:NextInteger(26, 40), {
			TextTransparency = 0.12,
			ZIndex = 3,
			Parent = frame,
		})
		table.insert(floaters, newFloater(label, random, {
			VY = -random:NextNumber(0.008, 0.018),
			Amp = random:NextNumber(0.01, 0.02),
			Rot = random:NextNumber(-20, 20),
			Wobble = random:NextNumber(10, 20),
		}))
	end

	return {
		Update = function(dt, t)
			stepFloaters(floaters, dt, t)
			local scroll = (t * 0.012) % (1 / STRIPES * 2)
			for _, s in ipairs(stripes) do
				local x = (s.Offset + scroll) % 1
				s.Frame.Position = UDim2.fromScale(-0.3 + x * 1.6, 0.5)
			end
		end,
	}
end

-- Synthwave : soleil rayé, montagnes néon, grille en perspective
Decors.Grid = function(frame, theme, reduced, random)
	local HORIZON = 0.62
	local twinkles: { Twinkle } = {}
	local accent: Color3 = theme.Accent
	local pink = Color3.fromRGB(255, 70, 170)

	-- Étoiles
	for _ = 1, reduced and 10 or 20 do
		local d = random:NextInteger(2, 3)
		local star = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0.02, HORIZON - 0.25)),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = frame,
		})
		table.insert(twinkles, {
			Obj = star,
			Property = "BackgroundTransparency",
			Min = 0.1,
			Max = 0.9,
			Speed = random:NextNumber(1, 3),
			Phase = random:NextNumber(0, math.pi * 2),
		})
	end

	-- Soleil rayé : CanvasGroup arrondi (les bandes sont coupées au bord du
	-- disque) ; les bandes prennent la couleur du ciel derrière
	local SUN_SIZE = 300
	local sunCenterY = HORIZON - 0.08
	local sunGlow = softGlow(frame, 560, pink, 0.1, 2)
	sunGlow.Position = UDim2.fromScale(0.5, sunCenterY)
	local sun = Create("CanvasGroup", {
		Name = "Sun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, sunCenterY),
		Size = UDim2.fromOffset(SUN_SIZE, SUN_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = frame,
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
		local thickness = 3 + i * 2
		local band = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(1, 0, 0, thickness),
			ZIndex = 2,
			Parent = sun,
		})
		table.insert(bands, { Frame = band, Y = y })
	end

	-- Montagnes (losanges dont le bas est caché par le sol), contour néon
	local MOUNTAINS = { { 0.12, 170 }, { 0.24, 120 }, { 0.8, 150 }, { 0.92, 200 } }
	for _, spec in ipairs(MOUNTAINS) do
		local m = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], HORIZON),
			Size = UDim2.fromOffset(spec[2], spec[2]),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(28, 6, 52),
			ZIndex = 4,
			Parent = frame,
		})
		UIUtil.Stroke(m, accent, 2, 0.35)
	end

	-- Sol + grille
	local ground = box({
		Name = "Ground",
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.fromScale(1, 1 - HORIZON),
		BackgroundColor3 = Color3.fromRGB(16, 2, 34),
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = frame,
	})
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(60, 10, 90), Color3.fromRGB(12, 0, 28)),
		Parent = ground,
	})
	local horizonLine = box({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = pink,
		ZIndex = 6,
		Parent = frame,
	})
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.8),
		}),
		Parent = horizonLine,
	})

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
			sunGlow.Size = UDim2.fromOffset(560 + pulse * 30, 560 + pulse * 30)
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

local function buildLayer(theme, reduced: boolean): Layer
	local target = root :: Frame
	local frame = box({
		Name = "Theme_" .. tostring(theme.Id),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 1,
	})
	UIUtil.Gradient(frame, ColorSequence.new(theme.Top, theme.Bottom), 90)

	local layer: Layer = { Frame = frame, Update = nil, Time = 0 }
	local builder = Decors[theme.Decor] or Decors.None
	local ok, result = pcall(builder, frame, theme, reduced, Random.new())
	if not ok then
		warn("[Background] Erreur dans le décor " .. tostring(theme.Decor) .. " : " .. tostring(result))
	end
	frame.Parent = target

	if ok and type(result) == "table" then
		layer.Update = result.Update
		local layout = result.Layout
		if layout then
			local function safeLayout()
				local success, err = pcall(layout)
				if not success then
					warn("[Background] Erreur de mise en page : " .. tostring(err))
				end
			end
			frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(safeLayout)
			task.defer(safeLayout)
		end
	end
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
		end

		local g = glow
		if g then
			if rushActive then
				g.BackgroundTransparency = 0.55 + math.sin(os.clock() * 3) * 0.2
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

return Background
