--[[
	Keyboard (ModuleScript - stimulus) — amélioration "Clavier mécanique" (12 niveaux)
	Emplacement : ReplicatedStorage > Client > Stimuli > Keyboard

	v9.1 : un VRAI clavier QWERTY cliquable, posé sur son tapis dans l'espace
	libre près de la colonne centrale (Gear/GearLayout, calque Background :
	il ne recouvre jamais l'interface).
	  - chaque touche (Q W E R T Y..., espace, entrée...) est un bouton :
	    l'appuyer l'enfonce, joue un son de touche (Config.ClickSounds
	    Keyboard1..5 selon le niveau, voir GearClick) et compte comme un VRAI
	    clic (même chemin que le gros bouton : gain, combo, quêtes, "+X") ;
	  - le vrai clavier du joueur appuie aussi sur les touches (Gear/KeyInput) ;
	  - quand la place manque, le clavier devient un petit clavier "résumé"
	    (Q W E R T Y / A S D F G H / Z X C V B N) ; si ses touches sont trop
	    petites pour être visées (≥ 22 px sur PC, 34 px en tactile), un appui
	    dessus ouvre le GRAND clavier flottant (Gear/KeyboardPanel) avec un
	    badge 🔍 pour le signaler.
	Chaque niveau ajoute quelque chose :
	  1 clavier blanc sur tapis lilas     2 touches colorées (retour, entrée, espace)
	  3 repose-poignets rose               4 tapis étoilé + 2 touches par clic
	  5 touches pastel                     6 tapis sombre + lueur cyan dessous
	  7 lueur RGB (tourne à chaque clic)   8 touches RGB + 3 touches par clic
	  9 gros "CLAC !" étincelants          10 touche artisanale dorée (étoile)
	  11 câble spiralé pastel              12 clavier doré + vague RGB + 4 touches
	Les sons de touches changent aussi avec le niveau (Keyboard1 -> Keyboard5).
	Au repos : de temps en temps, quelques touches "tapent" toutes seules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))
local KeyboardArt = require(Gear:WaitForChild("KeyboardArt"))
local GearClick = require(Gear:WaitForChild("GearClick"))
local ClickableKeys = require(Gear:WaitForChild("ClickableKeys"))

local Keyboard = {}
Keyboard.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local STEP_FULL = 24 -- pas d'une touche (touche + écart) du clavier posé, échelle 1
local STEP_MINI = 21
local GEO_FULL = KeyboardArt.Geometry("Full", STEP_FULL)
local GEO_MINI = KeyboardArt.Geometry("Mini", STEP_MINI)
local FULL = Vector2.new(GEO_FULL.W, GEO_FULL.H)
local MINI = Vector2.new(GEO_MINI.W, GEO_MINI.H)

local INK = Color3.fromRGB(52, 44, 72)
local POP_COLORS = {
	Color3.fromRGB(255, 110, 170),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(255, 196, 40),
	Color3.fromRGB(130, 230, 120),
}
local PASTEL = {
	Color3.fromRGB(255, 206, 228),
	Color3.fromRGB(196, 246, 222),
	Color3.fromRGB(220, 210, 255),
	Color3.fromRGB(255, 240, 204),
	Color3.fromRGB(206, 232, 255),
}

local active: { [any]: any } = {}

-- Nombre de touches enfoncées par clic sur le gros bouton
local function keysPerClick(level: number): number
	if level >= 12 then
		return 4
	elseif level >= 8 then
		return 3
	elseif level >= 4 then
		return 2
	end
	return 1
end

-- Couleur de base d'une touche selon le niveau
local function keyColorFn(level: number, hueOffset: number): (key: KeyboardArt.Key) -> Color3
	return function(key: KeyboardArt.Key): Color3
		if level >= 8 then
			return GearKit.Rainbow(key.Fx * 0.92 + key.Fy * 0.12 + hueOffset, 0.42, 1)
		end
		if level >= 2 then
			if key.Kind == "Back" then
				return Color3.fromRGB(255, 110, 124)
			elseif key.Kind == "Enter" then
				return Color3.fromRGB(255, 212, 70)
			elseif key.Kind == "Space" then
				return Color3.fromRGB(130, 200, 255)
			end
		end
		if level >= 5 then
			return PASTEL[(key.Row - 1) % #PASTEL + 1]
		end
		if key.Kind ~= "Key" then
			return Color3.fromRGB(226, 228, 238)
		end
		return Color3.fromRGB(250, 250, 253)
	end
end

-- Dessine le clavier (tapis, câble, lueur, boîtier, touches...) pour un pas
-- de touche `step`. Renvoie (touches, largeur, hauteur, dégradé de la lueur).
local function drawKeyboard(root: Instance, layout: string, step: number, level: number, hueOffset: number): ({ KeyboardArt.Key }, number, number, UIGradient?)
	local geo = KeyboardArt.Geometry(layout, step)
	local W, H = geo.W, geo.H
	local s = step / STEP_FULL -- facteur des détails (1 = clavier posé)
	local dark = level >= 6

	-- Tapis de bureau (+ couture)
	local matColor = dark and Color3.fromRGB(40, 34, 62) or Color3.fromRGB(206, 196, 255)
	GearKit.Outlined(root, 0, 0, W, H, matColor, { Name = "Mat", Radius = 13 * s, Outline = 2 * s, OutlineColor = INK, Z = 2, LineZ = 1 })
	local stitch = GearKit.Box(root, 4 * s, 4 * s, W - 8 * s, H - 8 * s, matColor, { Name = "Stitch", Radius = 10 * s, Transparency = 1, Z = 3 })
	local stitchStroke = Instance.new("UIStroke")
	stitchStroke.Color = dark and Color3.fromRGB(120, 110, 170) or Color3.new(1, 1, 1)
	stitchStroke.Transparency = 0.35
	stitchStroke.Thickness = math.max(1, s)
	stitchStroke.Parent = stitch
	if level >= 4 then
		local inset = 9 * s
		local spots = { { inset, inset }, { W - inset, inset }, { inset, H - inset }, { W - inset, H - inset } }
		for index, spot in ipairs(spots) do
			GearKit.Star(root, spot[1], spot[2], 9 * s, POP_COLORS[(index - 1) % #POP_COLORS + 1], 4)
		end
	end

	-- Lueur sous le clavier
	local glowGradient: UIGradient? = nil
	if level >= 6 then
		local glowColor = level >= 7 and Color3.new(1, 1, 1) or Color3.fromRGB(80, 230, 255)
		local glow = GearKit.Box(root, geo.CaseX - 6 * s, geo.CaseY - 6 * s, geo.CaseW + 12 * s, geo.CaseH + 12 * s, glowColor, {
			Name = "Underglow",
			Radius = 16 * s,
			Transparency = 0.12,
			Z = 4,
			Gradient = level >= 7 and GearKit.RainbowSequence(0, 0.85) or nil,
			GradientRotation = 0,
		})
		glowGradient = glow:FindFirstChildOfClass("UIGradient")
	end

	-- Câble (spiralé au niveau 11), en haut du boîtier
	local cableX = geo.CaseX + geo.CaseW * 0.74
	if level >= 11 then
		for index = 0, 4 do
			GearKit.Outlined(root, cableX - 14 * s + index * 7 * s, 2 * s, 6 * s, 8 * s, index % 2 == 0 and Color3.fromRGB(255, 190, 220) or Color3.fromRGB(170, 215, 255), {
				Name = "Coil",
				Radius = "round",
				Outline = 1.2 * s,
				OutlineColor = INK,
				Z = 6,
				LineZ = 5,
			})
		end
	else
		GearKit.Outlined(root, cableX, 1, 4 * s, geo.CaseY + 2, Color3.fromRGB(90, 92, 110), { Name = "Cable", Radius = 2 * s, Outline = 1.2 * s, OutlineColor = INK, Z = 6, LineZ = 5 })
	end

	-- Repose-poignets
	if level >= 3 then
		GearKit.Outlined(root, geo.CaseX + geo.CaseW * 0.08, geo.RestY, geo.CaseW * 0.84, geo.RestH, Color3.fromRGB(255, 196, 216), {
			Name = "WristRest",
			Radius = "round",
			Outline = 1.8 * s,
			OutlineColor = INK,
			Z = 6,
			LineZ = 5,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(235, 215, 225)),
		})
	end

	-- Boîtier + plaque
	local gold = level >= 12
	local caseColor = gold and Color3.fromRGB(255, 204, 70) or Color3.fromRGB(250, 250, 253)
	GearKit.Outlined(root, geo.CaseX, geo.CaseY, geo.CaseW, geo.CaseH, caseColor, {
		Name = "Case",
		Radius = 9 * s,
		Outline = 2.2 * s,
		OutlineColor = INK,
		Z = 8,
		LineZ = 7,
		Gradient = gold and ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(230, 160, 50))
			or ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 216, 228)),
	})
	GearKit.Box(root, geo.CaseX + 5 * s, geo.CaseY + 2 * s, geo.CaseW - 10 * s, 2.5 * s, Color3.new(1, 1, 1), { Name = "CaseShine", Radius = "round", Transparency = 0.35, Z = 9 })
	local plateColor = dark and Color3.fromRGB(58, 52, 86) or Color3.fromRGB(150, 156, 178)
	GearKit.Box(root, geo.KeysX - 3 * s, geo.KeysY - 3 * s, geo.KeysW + 6 * s, geo.KeysH + 6 * s, plateColor, { Name = "Plate", Radius = 6 * s, Z = 9 })

	-- Touches QWERTY
	local keys = KeyboardArt.Build(root, layout, geo.KeysX, geo.KeysY, geo.KeysW, geo.KeysH, {
		Color = keyColorFn(level, hueOffset),
		Z = 10,
	})

	-- Touche artisanale (étoile dorée) : "fn" (ou "enter" sur le petit clavier)
	if level >= 10 then
		local artisan = KeyboardArt.Find(keys, "Fn") or KeyboardArt.Find(keys, "Return")
		if artisan then
			KeyboardArt.Artisan(artisan, 14)
		end
	end
	return keys, W, H, glowGradient
end

function Keyboard.Start(ctx)
	local Theme = ctx.Theme
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "Keyboard",
		Size = FULL,
		Shapes = { MINI },
		Priority = 1.2, -- v9.1 : cliquable -> placé tôt (juste après le doigt)
		MinScale = 0.3,
		MaxScale = 1,
		SizePenalty = 520, -- préfère une grande place (touches cliquables)
		GlowColor = Color3.fromRGB(200, 190, 255),
		ContainerZ = 1104,
		Anchor = function(button, _canvas)
			-- En bas à gauche du bouton, à côté du compteur
			return Vector2.new(button.X0 - 170, button.Y1 + 95)
		end,
	}, animator)
	local random = ctx.Random

	local glowGradient: UIGradient? = nil
	local panelGlow: UIGradient? = nil
	local hueOffset = 0

	local function level(): number
		return math.max(1, piece.Level)
	end

	local keys = ClickableKeys.new(ctx, piece, animator, {
		Id = "Keyboard",
		InputPriority = 1,
		StepFull = STEP_FULL,
		StepMini = STEP_MINI,
		Draw = function(root: Instance, layout: string, step: number, lv: number)
			return drawKeyboard(root, layout, step, lv, hueOffset)
		end,
		Title = function(): string
			return ClickableKeys.TitleFor("⌨️", "Mechanical Keyboard", level())
		end,
		Tray = Color3.fromRGB(34, 28, 52),
		BadgeInk = INK,
		Lit = function(lv: number): Color3?
			return lv >= 9 and Color3.new(1, 1, 1) or nil
		end,
		OnBuilt = function(_root, _list, extra)
			glowGradient = extra
		end,
		OnPanelBuilt = function(_list, extra)
			panelGlow = extra
		end,
	})
	keys:Build(level())
	piece.OnLevel = function(lv, _previous)
		keys:LevelChanged(lv)
	end

	-- "clac !" réutilisés (calque Overlay, pas mis à l'échelle)
	local pops = GearKit.Pool(3, function(index)
		local label = Instance.new("TextLabel")
		label.Name = "Clack"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Size = UDim2.fromOffset(70, 20)
		label.Font = Theme.Fonts.Title
		label.Text = Locale.T("clack!")
		label.TextSize = 14
		label.TextColor3 = POP_COLORS[(index - 1) % #POP_COLORS + 1]
		label.ZIndex = 25
		label.Visible = false
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(40, 30, 60)
		stroke.Thickness = 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
		local scale = Instance.new("UIScale")
		scale.Parent = label
		label.Parent = piece.FX
		return label
	end)

	-- Couleurs RGB qui avancent à chaque clic (clavier posé + grand clavier ouvert)
	local function shiftRGB(lv: number)
		if lv < 7 then
			return
		end
		hueOffset = (hueOffset + 0.06) % 1
		for _, gradient in ipairs({ glowGradient, panelGlow }) do
			if gradient then
				gradient.Offset = Vector2.new(((hueOffset * 2) % 1) - 0.5, 0)
			end
		end
		if lv >= 8 and lv < 12 then
			for _, list in ipairs({ keys.Keys, keys.Panel:IsOpen() and keys.PanelKeys or {} }) do
				for _, key in ipairs(list) do
					if not key.Artisan then
						KeyboardArt.SetColor(key, GearKit.Rainbow(key.Fx * 0.92 + key.Fy * 0.12 + hueOffset, 0.42, 1))
					end
				end
			end
		end
	end

	-- Vague RGB (niveau 12) : les touches s'illuminent de gauche à droite
	local function wave()
		local list = keys.Panel:IsOpen() and keys.PanelKeys or keys.Keys
		animator:Play("wave", 0.45, function(t)
			for _, key in ipairs(list) do
				if not key.Artisan then
					local glow = GearKit.Bump(math.clamp((t * 1.6 - key.Fx * 0.6) / 0.6, 0, 1))
					local base = GearKit.Rainbow(key.Fx * 0.92 + key.Fy * 0.12 + hueOffset, 0.42 + 0.4 * glow, 1)
					key.Color = base
					if not animator:IsPlaying(key) then
						key.Frame.BackgroundColor3 = base
					end
				end
			end
		end)
	end

	local function popClack(key: KeyboardArt.Key, lv: number)
		if not GearKit.EffectsOn(ctx) then
			return
		end
		local point = keys:KeyPoint(key)
		if not point then
			return
		end
		local label = pops:Next()
		local scale = label:FindFirstChildOfClass("UIScale")
		local big = lv >= 9
		label.Text = big and Locale.T("CLACK!") or Locale.T("clack!")
		label.TextSize = big and 16 or 12
		local drift = random:NextNumber(-14, 14)
		local rise = (big and 30 or 22) + random:NextNumber(0, 10)
		animator:Play(label, 0.45, function(t)
			label.Visible = t < 1
			local e = GearKit.Ease.OutCubic(t)
			label.Position = UDim2.fromOffset(point.X + drift * e, point.Y - 2 - rise * e)
			if scale then
				scale.Scale = 0.6 + 0.5 * GearKit.Ease.OutBack(math.min(1, t * 2.5)) - 0.1 * t
			end
			label.TextTransparency = math.max(0, (t - 0.55) / 0.45)
			label.Rotation = drift * 0.8 * (1 - t)
		end, function()
			label.Visible = false
		end)
	end

	-- Touches au hasard (clic sur le gros bouton, ou au repos)
	local function pressRandom(count: number, lv: number, withPops: boolean)
		if #keys.Keys == 0 then
			return
		end
		for index, key in ipairs(KeyboardArt.Pick(keys.Keys, count, random)) do
			keys:AnimateKey(key, (index - 1) * 0.035)
			if withPops and index == 1 then
				popClack(key, lv)
			end
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if not ctx.IsVisible() then
			return
		end
		local lv = level()
		shiftRGB(lv)
		if lv >= 12 then
			wave()
		end
		local source = GearClick.Source
		if source == "Keyboard" or source == "CoralKeys" then
			return -- (la touche frappée s'anime déjà)
		end
		if piece:IsShown() then
			pressRandom(keysPerClick(lv), lv, true)
		end
	end)

	-- Au repos : quelques touches tapent toutes seules ; le badge 🔍 fait coucou
	GearKit.Every(ctx, 6, 11, function()
		if piece:IsShown() then
			pressRandom(3, level(), false)
			keys:Wiggle()
		end
	end)

	active[ctx] = { Piece = piece, Keys = keys }
end

function Keyboard.Stop(ctx)
	local entry = active[ctx]
	active[ctx] = nil
	if entry then
		entry.Keys:Destroy()
		entry.Piece:Destroy()
	end
end

return Keyboard
