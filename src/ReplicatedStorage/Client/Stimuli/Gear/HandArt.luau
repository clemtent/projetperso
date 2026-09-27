--[[
	HandArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > HandArt

	La petite main kawaii qui pointe du doigt (dessinée en Frames, boîte de
	100x100 "design", doigt vers le HAUT ; on la fait tourner pour viser).
	Utilisée par Finger (le doigt musclé), QuantumFinger (copies fantômes)
	et MegaFinger (la main géante qui écrase le bouton).

	Niveaux du "Doigt musclé" (1 à 15) — chaque niveau ajoute quelque chose :
	  1 main + petit visage   2 joues roses        3 plis des phalanges
	  4 bandeau éponge rouge  5 manche de sport    6 bague en or
	  7 vernis brillant       8 avant-bras musclé + sourcils décidés
	  9 gouttes de sueur      10 diamant sur la bague
	  11 veines, encore plus de muscle            12 bandeau de champion doré
	  13 aura de puissance + yeux étincelants     14 bague au pouce, aura orange
	  15 lunettes de soleil, aura arc-en-ciel (et la pose "flex" : voir Finger)
	La main grandit aussi un peu à chaque niveau.

	Contour : silhouettes sombres derrière les formes (voir GearKit.Outlined),
	donc il suit les UIScale. Aucun ClipsDescendants (la main est tournée).
]]

local GearKit = require(script.Parent.GearKit)

local HandArt = {}

HandArt.Size = 100 -- boîte de dessin
HandArt.TipY = 6 -- bout du doigt (y dans la boîte)

export type Hand = {
	Root: Frame, -- cadre 100x100 (contient un UIScale "ArtScale")
	ArtScale: UIScale,
	Finger: Frame, -- l'index (pour l'écraser au moment du "tap")
	FingerLine: Frame,
	Face: Frame?, -- groupe du visage (tourné à l'inverse de la main : reste droit)
	Aura: Frame?,
	Drops: { Frame },
	Base: { [Instance]: number }, -- transparences d'origine (fondu)
	FingerHeight: number,
}

export type Options = {
	Level: number?,
	Style: string?, -- "Normal" | "Ghost" | "Giant"
	Tint: Color3?, -- couleur des fantômes
	Face: boolean?,
	Name: string?,
}

local SKIN = Color3.fromRGB(255, 216, 190)
local SKIN_GRADIENT = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(236, 222, 216))
local INK = Color3.fromRGB(78, 44, 58)
local NAIL = Color3.fromRGB(255, 238, 240)
local POLISH = Color3.fromRGB(255, 92, 160)
local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_DARK = Color3.fromRGB(214, 140, 20)
local SLEEVE = Color3.fromRGB(128, 196, 255)
local SLEEVE_DARK = Color3.fromRGB(78, 146, 230)
local RED_BAND = Color3.fromRGB(235, 52, 64)

-- Caractéristiques de la main selon le niveau du doigt musclé
local function features(level: number)
	local l = math.clamp(level, 1, 15)
	return {
		Scale = 0.84 + 0.16 * (l - 1) / 14,
		FingerW = 14.5 + l * 0.42,
		FistW = 38 + l * 0.55,
		FistH = 30 + l * 0.22,
		WristW = 20 + l * 0.62,
		Blush = l >= 2,
		Creases = l >= 3,
		Band = l >= 4,
		GoldBand = l >= 12,
		SportSleeve = l >= 5,
		Ring = l >= 6,
		Gem = l >= 10,
		Polish = l >= 7,
		Muscle = l >= 8,
		BigMuscle = l >= 11,
		Brows = l >= 8,
		Sweat = l >= 9,
		Veins = l >= 11,
		Aura = l >= 13,
		SparkleEyes = l >= 13,
		ThumbRing = l >= 14,
		Shades = l >= 15,
	}
end

HandArt.Features = features

-- Couleur de l'aura selon le niveau (13 jaune, 14 orange, 15 arc-en-ciel)
local function auraColor(level: number): Color3
	if level >= 15 then
		return Color3.fromRGB(255, 120, 220)
	elseif level >= 14 then
		return Color3.fromRGB(255, 150, 40)
	end
	return Color3.fromRGB(255, 226, 60)
end

-- Construit la main dans `parent` (cadre 100x100, AnchorPoint 0.5 / centré)
function HandArt.Build(parent: Instance, options: Options?): Hand
	local opts = options or {}
	local level = opts.Level or 1
	local style = opts.Style or "Normal"
	local f = features(level)
	local ghost = style == "Ghost"
	local giant = style == "Giant"
	if giant then
		-- La main géante est au maximum de sa forme
		f = features(15)
		f.Shades = false
		f.Aura = false
	end

	local skin = SKIN
	local ink = INK
	local fillTransparency = 0
	local lineTransparency = 0
	if ghost then
		local tint = opts.Tint or Color3.fromRGB(90, 230, 255)
		skin = tint:Lerp(Color3.new(1, 1, 1), 0.55)
		ink = tint
		fillTransparency = 0.45
		lineTransparency = 0.15
	end

	local root = Instance.new("Frame")
	root.Name = opts.Name or "Hand"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
	local artScale = Instance.new("UIScale")
	artScale.Name = "ArtScale"
	artScale.Scale = f.Scale
	artScale.Parent = root

	local function part(name: string, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): (Frame, Frame)
		local p = props or {}
		p.Name = name
		p.OutlineColor = p.OutlineColor or ink
		p.OutlineTransparency = p.OutlineTransparency or lineTransparency
		p.Transparency = p.Transparency or fillTransparency
		if p.Gradient == nil and not ghost and color == skin then
			p.Gradient = SKIN_GRADIENT
		end
		return GearKit.Outlined(root, x, y, w, h, color, p)
	end

	-- Mesures
	local fistW, fistH = f.FistW, f.FistH
	local fistX = 50 - fistW / 2 + 2
	local fistY = 34
	local fingerW = f.FingerW
	local fingerX = fistX + 2
	local tipY = HandArt.TipY
	local fingerH = fistY + 12 - tipY
	local wristW = f.WristW
	local wristX = 50 - wristW / 2 + 2
	local wristY = fistY + fistH - 8
	local wristBottom = 89

	-- Aura (derrière tout)
	local aura: Frame? = nil
	if f.Aura and not ghost then
		-- Trois disques concentriques : une lueur "radiale"
		local color = auraColor(level)
		local halo = GearKit.Box(root, 50, 50, 106, 106, color, {
			Name = "Aura",
			Anchor = Vector2.new(0.5, 0.5),
			Radius = "round",
			Transparency = 0.86,
			Z = 0,
			Gradient = level >= 15 and GearKit.RainbowSequence(0, 0.6) or nil,
			GradientRotation = 45,
		})
		GearKit.Box(halo, 53, 53, 84, 84, color, { Name = "AuraMid", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.8, Z = 0 })
		GearKit.Box(halo, 53, 53, 62, 62, Color3.new(1, 1, 1):Lerp(color, 0.5), { Name = "AuraCore", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.72, Z = 0 })
		aura = halo
	end

	-- Avant-bras + manche
	part("Forearm", wristX, wristY, wristW, wristBottom - wristY, skin, { Radius = 8, Z = 3, LineZ = 1 })
	if f.Muscle and not ghost then
		local bulgeW = f.BigMuscle and wristW * 0.62 or wristW * 0.5
		local bulgeH = f.BigMuscle and 23 or 19
		part("Muscle", wristX + wristW - bulgeW * 0.55, wristY + 10, bulgeW, bulgeH, skin, { Radius = "round", Z = 3, LineZ = 1 })
		GearKit.Shine(root, wristX + wristW - bulgeW * 0.1, wristY + 14, bulgeW * 0.3, 6, 0.5, 9, -20)
	end
	if f.Veins and not ghost then
		GearKit.Box(root, wristX + 5, wristY + 15, 2, 10, Color3.fromRGB(200, 120, 160), { Name = "Vein", Radius = "round", Rotation = 16, Transparency = 0.2, Z = 9 })
		GearKit.Box(root, wristX + 9, wristY + 20, 2, 7, Color3.fromRGB(200, 120, 160), { Name = "Vein", Radius = "round", Rotation = -24, Transparency = 0.2, Z = 9 })
	end
	local sleeveW = wristW + 14
	local sleeveColor = ghost and skin or SLEEVE
	part("Sleeve", 50 - sleeveW / 2 + 2, wristBottom - 4, sleeveW, 14, sleeveColor, {
		Radius = 7,
		Z = 7,
		LineZ = 6,
		Gradient = (not ghost) and ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 222, 240)) or nil,
	})
	if f.SportSleeve and not ghost then
		GearKit.Box(root, 50 - sleeveW / 2 + 4, wristBottom, sleeveW - 4, 2.5, Color3.new(1, 1, 1), { Name = "Stripe", Z = 8 })
		GearKit.Box(root, 50 - sleeveW / 2 + 4, wristBottom + 4, sleeveW - 4, 2.5, SLEEVE_DARK, { Name = "Stripe", Z = 8 })
	end

	-- Poing
	part("Fist", fistX, fistY, fistW, fistH, skin, { Radius = 13, Z = 4, LineZ = 1 })
	-- Doigts repliés (bosses en haut à droite du poing)
	local bumpW = (fistX + fistW - (fingerX + fingerW)) / 3
	for index = 1, 3 do
		local bx = fingerX + fingerW - 1 + (index - 1) * bumpW
		part("Knuckle" .. index, bx, fistY - 4 + (index - 1) * 1.5, bumpW + 1, 14, skin, { Radius = "round", Z = 4, LineZ = 1 })
		if f.Creases and index > 1 then
			GearKit.Box(root, bx, fistY + 1 + (index - 1) * 1.5, 1.6, 9, ink, { Name = "Crease", Radius = "round", Transparency = 0.45, Z = 8 })
		end
	end

	-- Index
	local finger, fingerLine = part("Finger", fingerX, tipY, fingerW, fingerH, skin, { Radius = "round", Z = 5, LineZ = 1 })
	local nailColor = (f.Polish and not ghost) and (level >= 15 and GOLD or POLISH) or (ghost and skin or NAIL)
	local nail = GearKit.Box(finger, 3, 3, fingerW - 6, 10, nailColor, { Name = "Nail", Radius = 5, Z = 6, Transparency = fillTransparency })
	if not ghost then
		GearKit.Shine(nail, 2, 1.5, 3, 4, 0.35, 7)
		if f.Creases then
			GearKit.Box(finger, fingerW * 0.28, 22, fingerW * 0.44, 1.6, ink, { Name = "Crease", Radius = "round", Transparency = 0.5, Z = 7 })
			GearKit.Box(finger, fingerW * 0.3, 30, fingerW * 0.4, 1.6, ink, { Name = "Crease", Radius = "round", Transparency = 0.5, Z = 7 })
		end
		GearKit.Shine(finger, 2.5, 14, 3, fingerH * 0.35, 0.6, 7)
	end
	if f.Ring and not ghost then
		local ringY = fistY - 9
		GearKit.Box(root, fingerX - 1.5, ringY, fingerW + 3, 5.5, GOLD, {
			Name = "Ring",
			Radius = 2,
			Z = 8,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(230, 170, 60)),
		})
		if f.Gem then
			local gem = GearKit.Box(root, fingerX + fingerW / 2, ringY + 1, 7, 7, Color3.fromRGB(120, 235, 255), {
				Name = "Gem",
				Anchor = Vector2.new(0.5, 0.5),
				Rotation = 45,
				Z = 9,
			})
			GearKit.Shine(gem, 1, 1, 2.5, 2.5, 0.1, 10)
		end
	end

	-- Pouce (devant le poing : son contour passe par-dessus)
	local thumb = part("Thumb", fistX - 6, fistY + 4, 13, 24, skin, { Radius = "round", Rotation = 38, Z = 6, LineZ = 5 })
	if f.ThumbRing and not ghost then
		GearKit.Box(thumb, 1, 14, 12, 4.5, GOLD_DARK:Lerp(GOLD, 0.6), { Name = "ThumbRing", Radius = 2, Z = 8 })
	end

	-- Bandeau éponge (poignet)
	if f.Band and not ghost then
		local bandColor = f.GoldBand and GOLD or RED_BAND
		local bandY = fistY + fistH - 5
		local band = part("Band", wristX - 3, bandY, wristW + 6, 10, bandColor, {
			Radius = 3,
			Z = 7,
			LineZ = 6,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 205, 205)),
		})
		if f.GoldBand then
			GearKit.Star(band, (wristW + 6) / 2, 5, 8, Color3.new(1, 1, 1), 9)
		else
			GearKit.Box(band, 0, 4, wristW + 6, 2, Color3.new(1, 1, 1), { Name = "Stripe", Z = 8 })
		end
	end

	-- Visage (sur le poing), dans un groupe qui reste droit
	local face: Frame? = nil
	if opts.Face ~= false and not ghost then
		local group = Instance.new("Frame")
		group.Name = "Face"
		group.BackgroundTransparency = 1
		group.AnchorPoint = Vector2.new(0.5, 0.5)
		group.Size = UDim2.fromOffset(30, 20)
		group.Position = UDim2.fromOffset(fistX + fistW / 2 + 4, fistY + fistH / 2 + 3)
		group.ZIndex = 10
		group.Parent = root
		local eyeInk = Color3.fromRGB(58, 30, 40)
		if f.Shades then
			GearKit.Box(group, 1, 3, 28, 3, Color3.fromRGB(20, 20, 26), { Name = "Bridge", Radius = 1, Z = 2 })
			GearKit.Box(group, 2, 4, 11, 8, Color3.fromRGB(20, 20, 26), { Name = "Lens", Radius = 4, Z = 2 })
			GearKit.Box(group, 17, 4, 11, 8, Color3.fromRGB(20, 20, 26), { Name = "Lens", Radius = 4, Z = 2 })
			GearKit.Box(group, 4, 5.5, 5, 1.6, Color3.new(1, 1, 1), { Name = "Glint", Radius = "round", Transparency = 0.2, Z = 3 })
			GearKit.Box(group, 19, 5.5, 5, 1.6, Color3.new(1, 1, 1), { Name = "Glint", Radius = "round", Transparency = 0.2, Z = 3 })
		else
			for side = 0, 1 do
				local ex = side == 0 and 8 or 19
				local eye = GearKit.Box(group, ex, 5, 4, 5.5, eyeInk, { Name = "Eye", Radius = "round", Z = 2 })
				if f.SparkleEyes or giant then
					GearKit.Box(eye, 0.6, 0.6, 1.8, 1.8, Color3.new(1, 1, 1), { Name = "Glint", Radius = "round", Z = 3 })
				end
				if f.Brows then
					GearKit.Box(group, ex - 1.5, 1, 7, 2, eyeInk, {
						Name = "Brow",
						Radius = "round",
						Rotation = side == 0 and 18 or -18,
						Z = 2,
					})
				end
			end
		end
		if f.Blush then
			GearKit.Box(group, 1, 11, 6, 3.5, Color3.fromRGB(255, 130, 150), { Name = "Blush", Radius = "round", Transparency = 0.35, Z = 1 })
			GearKit.Box(group, 23, 11, 6, 3.5, Color3.fromRGB(255, 130, 150), { Name = "Blush", Radius = "round", Transparency = 0.35, Z = 1 })
		end
		local mouth = GearKit.Box(group, 12.5, 12, 5, 3.5, Color3.fromRGB(160, 50, 70), { Name = "Mouth", Radius = "round", Z = 2 })
		if f.Shades or giant then
			mouth.Size = UDim2.fromOffset(7, 2.5)
			mouth.Position = UDim2.fromOffset(12, 13)
			mouth.Rotation = -8
		end
		face = group
	end

	-- Gouttes de sueur (niveau 9+)
	local drops = {}
	if f.Sweat and not ghost then
		for index = 1, 2 do
			local drop = GearKit.Box(root, fistX + fistW + 1 + index * 3, fistY - 14 + index * 9, 5, 7, Color3.fromRGB(130, 210, 255), {
				Name = "Drop",
				Radius = "round",
				Z = 9,
			})
			GearKit.Box(drop, 1, 1, 1.6, 2.4, Color3.new(1, 1, 1), { Name = "Glint", Radius = "round", Transparency = 0.1, Z = 10 })
			table.insert(drops, drop)
		end
	end

	root.Parent = parent
	return {
		Root = root,
		ArtScale = artScale,
		Finger = finger,
		FingerLine = fingerLine,
		Face = face,
		Aura = aura,
		Drops = drops,
		Base = GearKit.CaptureTransparency(root),
		FingerHeight = fingerH,
	}
end

-- Visée d'une main posée en `placement` (GearLayout) vers le bouton :
-- angle (degrés), direction (unitaire), course du "tap" (px toile) et
-- vrai si le bout du doigt peut toucher le bouton (sinon petit coup dans le vide)
function HandArt.Aim(placement: any, artScale: number, touchRange: number?): (number, Vector2, number, boolean)
	local center = Vector2.new(placement.CX, placement.CY)
	local button = placement.Button
	local target = GearKit.Center(button)
	-- Un peu vers le bord le plus proche : le doigt touche le bouton "de face"
	local edge = GearKit.ClosestOnRect(button, center)
	target = target:Lerp(edge, 0.35)
	local angle = GearKit.AimAngle(center, target)
	local dir = GearKit.AngleDir(angle)
	local tipDistance = (HandArt.Size / 2 - HandArt.TipY) * artScale * placement.Scale
	local gap = GearKit.RayToRect(center + dir * tipDistance, dir, button)
	local touching = gap <= (touchRange or 46)
	return angle, dir, touching and (gap + 2) or 12, touching
end

-- Main "fantôme" légère (QuantumFinger) : mêmes formes que la vraie main,
-- mais seulement des aplats translucides (pas de contour ni de détails) :
-- ~12 instances au lieu d'une cinquantaine.
export type Ghost = {
	Root: Frame,
	ArtScale: UIScale,
	Parts: { Frame },
	Finger: Frame,
}

function HandArt.BuildGhost(parent: Instance, tint: Color3, level: number?, name: string?): Ghost
	local f = features(level or 1)
	local root = Instance.new("Frame")
	root.Name = name or "Ghost"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
	local artScale = Instance.new("UIScale")
	artScale.Name = "ArtScale"
	artScale.Scale = f.Scale
	artScale.Parent = root

	local light = tint:Lerp(Color3.new(1, 1, 1), 0.45)
	local parts = {}
	local function blob(partName: string, x: number, y: number, w: number, h: number, color: Color3, radius: any, rotation: number?, z: number): Frame
		local frame = GearKit.Box(root, x, y, w, h, color, {
			Name = partName,
			Radius = radius,
			Rotation = rotation,
			Transparency = 0.42,
			Z = z,
		})
		table.insert(parts, frame)
		return frame
	end
	local fistW, fistH = f.FistW, f.FistH
	local fistX = 50 - fistW / 2 + 2
	local fistY = 34
	local fingerW = f.FingerW
	local wristW = f.WristW
	local wristY = fistY + fistH - 8
	blob("Sleeve", 50 - (wristW + 14) / 2 + 2, 85, wristW + 14, 14, tint, 7, nil, 1)
	blob("Forearm", 50 - wristW / 2 + 2, wristY, wristW, 89 - wristY, light, 8, nil, 2)
	blob("Fist", fistX, fistY - 4, fistW, fistH + 4, light, 13, nil, 3)
	local finger = blob("Finger", fistX + 2, HandArt.TipY, fingerW, fistY + 12 - HandArt.TipY, light, "round", nil, 4)
	GearKit.Box(finger, 3, 3, fingerW - 6, 9, Color3.new(1, 1, 1), { Name = "Nail", Radius = 4, Transparency = 0.25, Z = 5 })
	blob("Thumb", fistX - 6, fistY + 4, 13, 24, tint, "round", 38, 5)
	root.Parent = parent
	return { Root = root, ArtScale = artScale, Parts = parts, Finger = finger }
end

-- Écrase un peu l'index (0 = normal, 1 = écrasé) : le bout du doigt descend
function HandArt.Squash(hand: Hand, amount: number)
	local squash = 5 * amount
	local h = hand.FingerHeight
	hand.Finger.Size = UDim2.fromOffset(hand.Finger.Size.X.Offset, h - squash)
	hand.Finger.Position = UDim2.fromOffset(hand.Finger.Position.X.Offset, HandArt.TipY + squash)
	local line = hand.FingerLine
	line.Size = UDim2.fromOffset(line.Size.X.Offset, h + 5 - squash)
	line.Position = UDim2.fromOffset(line.Position.X.Offset, HandArt.TipY - 2.5 + squash)
end

return HandArt
