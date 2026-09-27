--[[
	Keyboard (ModuleScript - stimulus) — amélioration "Clavier mécanique" (12 niveaux)
	Emplacement : ReplicatedStorage > Client > Stimuli > Keyboard

	Un petit clavier mécanique sur son tapis de bureau, posé dans l'espace
	libre près de la colonne centrale (Gear/GearLayout, calque Background : il ne
	recouvre jamais l'interface). Quand la place manque (couloir étroit à côté
	des menus), il devient un pavé numérique en hauteur. À chaque clic, des
	touches s'enfoncent et des "clac !" sautent au-dessus (calque Overlay).
	Chaque niveau ajoute quelque chose :
	  1 clavier blanc sur tapis lilas     2 touches colorées (Échap, Entrée, espace)
	  3 repose-poignets rose               4 tapis étoilé + 2 touches par clic
	  5 touches pastel                     6 tapis sombre + lueur cyan dessous
	  7 lueur RGB (tourne à chaque clic)   8 touches RGB + 3 touches par clic
	  9 gros "CLAC !" étincelants          10 touche artisanale dorée (étoile)
	  11 câble spiralé pastel              12 clavier doré + vague RGB + 4 touches
	Au repos : de temps en temps, quelques touches "tapent" toutes seules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))
local KeyboardArt = require(Gear:WaitForChild("KeyboardArt"))

local Keyboard = {}
Keyboard.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local FULL = Vector2.new(180, 78)
local COMPACT = Vector2.new(76, 100) -- pavé numérique (forme de rechange)
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

-- Nombre de touches enfoncées par clic
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

function Keyboard.Start(ctx)
	local Theme = ctx.Theme
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "Keyboard",
		Size = FULL,
		Shapes = { COMPACT },
		Priority = 3,
		MinScale = 0.4,
		MaxScale = 1,
		GlowColor = Color3.fromRGB(200, 190, 255),
		ContainerZ = 1104,
		Anchor = function(button, _canvas)
			-- En bas à gauche du bouton, à côté du compteur
			return Vector2.new(button.X0 - 150, button.Y1 + 95)
		end,
	}, animator)
	active[ctx] = piece
	local random = ctx.Random

	local art: Frame? = nil
	local keys: { KeyboardArt.Key } = {}
	local glowGradient: UIGradient? = nil
	local hueOffset = 0

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

	local function rgbFor(key: KeyboardArt.Key): Color3
		return GearKit.Rainbow(key.Fx * 0.92 + key.Fy * 0.12 + hueOffset, 0.42, 1)
	end

	local function keyColor(level: number): (key: KeyboardArt.Key) -> Color3
		return function(key: KeyboardArt.Key): Color3
			if level >= 8 then
				return rgbFor(key)
			end
			if level >= 2 then
				if key.Kind == "Esc" then
					return Color3.fromRGB(255, 96, 110)
				elseif key.Kind == "Enter" then
					return Color3.fromRGB(255, 212, 70)
				elseif key.Kind == "Space" then
					return Color3.fromRGB(120, 196, 255)
				end
			end
			if level >= 5 then
				return PASTEL[(key.Row - 1) % #PASTEL + 1]
			end
			return Color3.fromRGB(250, 250, 253)
		end
	end

	local function build(level: number)
		for _, key in ipairs(keys) do
			animator:Stop(key)
		end
		animator:Stop("wave")
		if art then
			art:Destroy()
		end
		table.clear(keys)
		glowGradient = nil
		local compact = piece.Shape > 0
		local size = compact and COMPACT or FULL
		local W, H = size.X, size.Y
		local root = Instance.new("Frame")
		root.Name = "Art"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(W, H)
		root.ZIndex = 2

		-- Tapis de bureau
		local dark = level >= 6
		local matColor = dark and Color3.fromRGB(40, 34, 62) or Color3.fromRGB(206, 196, 255)
		GearKit.Outlined(root, 0, 0, W, H, matColor, { Name = "Mat", Radius = 13, Outline = 2, OutlineColor = INK, Z = 2, LineZ = 1 })
		local stitch = GearKit.Box(root, 4, 4, W - 8, H - 8, matColor, { Name = "Stitch", Radius = 10, Transparency = 1, Z = 3 })
		local stitchStroke = Instance.new("UIStroke")
		stitchStroke.Color = dark and Color3.fromRGB(120, 110, 170) or Color3.new(1, 1, 1)
		stitchStroke.Transparency = 0.35
		stitchStroke.Thickness = 1
		stitchStroke.Parent = stitch
		if level >= 4 then
			-- Petites étoiles sur le tapis
			local spots = { { 7, 8 }, { W - 9, 8 }, { 7, H - 9 }, { W - 9, H - 9 } }
			if not compact then
				table.insert(spots, { W / 2 - 50, 6 })
				table.insert(spots, { W / 2 + 40, H - 6 })
			end
			for index, spot in ipairs(spots) do
				GearKit.Star(root, spot[1], spot[2], index <= 4 and 8 or 6, POP_COLORS[(index - 1) % #POP_COLORS + 1], 4)
			end
		end

		-- Boîtier (rectangle) : plein clavier ou pavé
		local caseX, caseY, caseW, caseH
		if compact then
			caseX, caseY, caseW, caseH = 8, 12, W - 16, H - 26
		else
			caseX, caseY, caseW, caseH = 10, 11, W - 20, 51
		end

		-- Lueur sous le clavier
		if level >= 6 then
			local glowColor = level >= 7 and Color3.new(1, 1, 1) or Color3.fromRGB(80, 230, 255)
			local glow = GearKit.Box(root, caseX - 8, caseY - 7, caseW + 16, caseH + 14, glowColor, {
				Name = "Underglow",
				Radius = 16,
				Transparency = 0.12,
				Z = 4,
				Gradient = level >= 7 and GearKit.RainbowSequence(0, 0.85) or nil,
				GradientRotation = compact and 90 or 0,
			})
			GearKit.Box(root, caseX - 12, caseY - 10, caseW + 24, caseH + 20, glowColor, {
				Name = "UnderglowSoft",
				Radius = 18,
				Transparency = 0.72,
				Z = 4,
				Gradient = level >= 7 and GearKit.RainbowSequence(0.3, 0.85) or nil,
				GradientRotation = compact and 90 or 0,
			})
			glowGradient = glow:FindFirstChildOfClass("UIGradient")
		end

		-- Câble (spiralé au niveau 11)
		local cableX = compact and W - 22 or 137
		if level >= 11 then
			for index = 0, (compact and 2 or 5) do
				GearKit.Outlined(root, (compact and W - 34 or 124) + index * 7, 2, 6, 8, index % 2 == 0 and Color3.fromRGB(255, 190, 220) or Color3.fromRGB(170, 215, 255), {
					Name = "Coil",
					Radius = "round",
					Outline = 1.2,
					OutlineColor = INK,
					Z = 6,
					LineZ = 5,
				})
			end
		else
			GearKit.Outlined(root, cableX, 1, 4, caseY + 2, Color3.fromRGB(90, 92, 110), { Name = "Cable", Radius = 2, Outline = 1.2, OutlineColor = INK, Z = 6, LineZ = 5 })
		end

		-- Repose-poignets
		if level >= 3 then
			local restY = caseY + caseH + 3
			GearKit.Outlined(root, compact and 12 or 24, restY, compact and W - 24 or W - 48, compact and 7 or 9, Color3.fromRGB(255, 196, 216), {
				Name = "WristRest",
				Radius = "round",
				Outline = 1.8,
				OutlineColor = INK,
				Z = 6,
				LineZ = 5,
				Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(235, 215, 225)),
			})
		end

		-- Boîtier + plaque + touches
		local gold = level >= 12
		local caseColor = gold and Color3.fromRGB(255, 204, 70) or Color3.fromRGB(250, 250, 253)
		GearKit.Outlined(root, caseX, caseY, caseW, caseH, caseColor, {
			Name = "Case",
			Radius = 9,
			Outline = 2.2,
			OutlineColor = INK,
			Z = 8,
			LineZ = 7,
			Gradient = gold and ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(230, 160, 50))
				or ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 216, 228)),
		})
		GearKit.Box(root, caseX + 4, caseY + 3, caseW - 8, 3, Color3.new(1, 1, 1), { Name = "CaseShine", Radius = "round", Transparency = 0.35, Z = 9 })
		local plateColor = dark and Color3.fromRGB(58, 52, 86) or Color3.fromRGB(150, 156, 178)
		GearKit.Box(root, caseX + 4, caseY + 6, caseW - 8, caseH - 10, plateColor, { Name = "Plate", Radius = 5, Z = 9 })
		local keyOptions = {
			Color = keyColor(level),
			Radius = 2.5,
			Gap = 1.8,
			Shine = level >= 5,
			Z = 10,
		}
		if compact then
			keys = KeyboardArt.Numpad(root, caseX + 6, caseY + 8, caseW - 12, caseH - 14, keyOptions)
		else
			keys = KeyboardArt.Keys(root, caseX + 6, caseY + 8, caseW - 12, caseH - 14, keyOptions)
		end

		-- Touche artisanale (étoile dorée) : dernière touche de la 1re rangée
		if level >= 10 then
			local key: KeyboardArt.Key? = nil
			for _, candidate in ipairs(keys) do
				if candidate.Row == 1 and (key == nil or candidate.Col > (key :: KeyboardArt.Key).Col) then
					key = candidate
				end
			end
			if key then
				local artisan = GearKit.Box(root, key.X - 1, key.Y - 1, key.W + 2, key.H + 2, Color3.fromRGB(255, 196, 40), {
					Name = "Artisan",
					Radius = 3,
					Z = 12,
					Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 150, 30)),
				})
				GearKit.Star(artisan, (key.W + 2) / 2, (key.H + 2) / 2, 8, Color3.new(1, 1, 1), 13)
			end
		end

		root.Parent = piece.Content
		art = root
	end
	build(math.max(1, piece.Level))

	piece.OnLevel = function(level, _previous)
		build(level)
	end
	piece.OnShape = function(_shape, _size)
		build(math.max(1, piece.Level))
	end

	-- Couleurs RGB qui avancent à chaque clic
	local function shiftRGB(level: number)
		if level < 7 then
			return
		end
		hueOffset = (hueOffset + 0.06) % 1
		local gradient = glowGradient
		if gradient then
			gradient.Offset = Vector2.new(((hueOffset * 2) % 1) - 0.5, 0)
		end
		if level >= 8 and level < 12 then
			for _, key in ipairs(keys) do
				KeyboardArt.SetColor(key, rgbFor(key))
			end
		end
	end

	-- Vague RGB (niveau 12) : les touches s'illuminent de gauche à droite
	local function wave()
		local list = keys
		animator:Play("wave", 0.45, function(t)
			for _, key in ipairs(list) do
				local glow = GearKit.Bump(math.clamp((t * 1.6 - key.Fx * 0.6) / 0.6, 0, 1))
				local base = GearKit.Rainbow(key.Fx * 0.92 + key.Fy * 0.12 + hueOffset, 0.42 + 0.4 * glow, 1)
				key.Color = base
				if not animator:IsPlaying(key) then
					key.Frame.BackgroundColor3 = base
				end
			end
		end)
	end

	local function popClack(key: KeyboardArt.Key, level: number)
		if not GearKit.EffectsOn(ctx) then
			return
		end
		local point = piece:ToCanvas(Vector2.new(key.X + key.W / 2, key.Y))
		if not point then
			return
		end
		local label = pops:Next()
		local scale = label:FindFirstChildOfClass("UIScale")
		local big = level >= 9
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

	local function pressKeys(count: number, level: number, withPops: boolean)
		if not art or #keys == 0 then
			return
		end
		local lit = level >= 9 and Color3.new(1, 1, 1) or nil
		for index, key in ipairs(KeyboardArt.Pick(keys, count, random)) do
			local delay = (index - 1) * 0.035
			animator:Play(key, 0.17 + delay, function(t)
				local k = math.clamp((t * (0.17 + delay) - delay) / 0.17, 0, 1)
				local amount = k < 0.35 and k / 0.35 or 1 - (k - 0.35) / 0.65
				KeyboardArt.Press(key, amount, lit)
			end, function()
				KeyboardArt.Press(key, 0)
			end)
			if withPops and index == 1 then
				popClack(key, level)
			end
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if not ctx.IsVisible() or not piece:IsShown() then
			return
		end
		local level = math.max(1, piece.Level)
		shiftRGB(level)
		pressKeys(keysPerClick(level), level, true)
		if level >= 12 then
			wave()
		end
	end)

	-- Au repos : quelques touches tapent toutes seules
	GearKit.Every(ctx, 6, 11, function()
		if piece:IsShown() then
			pressKeys(3, math.max(1, piece.Level), false)
		end
	end)
end

function Keyboard.Stop(ctx)
	local piece = active[ctx]
	active[ctx] = nil
	if piece then
		piece:Destroy()
	end
end

return Keyboard
