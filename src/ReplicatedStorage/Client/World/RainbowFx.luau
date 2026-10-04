--[[
	RainbowFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RainbowFx

	v11 (REALISM11) 🌈 l'arc-en-ciel refait + 🍀 le pot d'or, côté client,
	AUCUN son. Piloté par Weather3D (Start / Step / Stop).

	Arc-en-ciel (le joueur : "l'arc-en-ciel est moche") :
	  - un VRAI arc lisse : chaque couleur = 2 Beams en quart de cercle
	    (courbes de Bézier exactes à 0,03 % près : points de contrôle à
	    0,5523 R le long des tangentes), 7 bandes douces qui se recouvrent
	    (rouge dehors -> violet dedans), lueur claire à l'intérieur de l'arc
	    et arc secondaire très pâle aux couleurs inversées (comme en vrai) ;
	  - grand (rayon 300 studs, sommet à 300 studs) et ANCRÉ dans la ville :
	    un de ses pieds touche le sol sur le POT D'OR (place choisie par le
	    serveur, RainbowService, mêmes règles : Shared/RainbowGold) ; l'arc
	    pivote doucement autour de ce pied pour toujours faire face au
	    joueur (un arc-en-ciel se voit toujours de face), figé quand on est
	    tout près ; la jambe lointaine s'efface dans la brume ;
	  - fondu à l'apparition / à la disparition (intensité RainbowGold.Event) ;
	    la nuit : "arc lunaire" pâle et presque blanc.
	Pot d'or :
	  - marmite noire pleine de pièces d'or, pièces au sol, lueur douce
	    (PointLight ≤ 1), étincelles (ParticleEmitter), colonne de lumière
	    dorée visible de loin, étiquette "🍀 Pot d'or · 230 m · 3 places"
	    (BillboardGui, toujours lisible) ; vidé quand les 3 gagnants sont
	    passés (attribut PotOfGoldWinners du serveur) ;
	  - gain (attribut PotOfGoldWin du joueur, posé par le serveur) : gerbe
	    de 24 pièces qui jaillissent en tournant puis volent vers le joueur,
	    pluie d'étincelles, "+X 🧠" qui monte (la notification du serveur dit
	    le reste).
	Attributs lus (serveur -> clients) : workspace PotOfGoldId (n° de
	l'arc-en-ciel), PotOfGoldPos (Vector3), PotOfGoldWinners, PotOfGoldMax ;
	joueur PotOfGoldWin = "id|place|montant". Sans serveur (tests) : place
	calculée ici (RainbowGold.Order) et posée au sol par un lancer de rayon.

	API : RainbowFx.Start(folder, opts?) / Stop() / Step(dt, t, camPos, night)
	      RainbowFx.State() -> { Id, Amount, Pos, Source, Beams, Coins, Emptied, Yaw }
	      RainbowFx.ArcPoint(foot, e1, side, radius, angle) -> Vector3   (pur, tests)
	      RainbowFx.Celebrate(amount)   (tests / rendus : la gerbe de pièces)
	Budget : 46 Beams + 13 pièces (pot) pendant l'arc-en-ciel seulement ;
	24 pièces volantes 2 s pendant un gain. Géométrie mise à jour 10 fois / s.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RainbowGold = require(ReplicatedStorage.Shared.RainbowGold)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local RainbowFx = {}

local K_BEZIER = 0.5523 -- quart de cercle en Bézier cubique
local RADIUS = RainbowGold.CONFIG.ArcRadius
local BAND_W = 2.3 -- (studs) écart entre deux bandes
local GEOM_EVERY = 0.1
local NEAR_FREEZE = 40 -- (studs) arc figé quand on est tout près du pot
local YAW_TIME = 1.8 -- (s) pivot doux de l'arc
local COLORS = {
	Color3.fromRGB(255, 108, 112), -- rouge (dehors)
	Color3.fromRGB(255, 166, 92),
	Color3.fromRGB(255, 226, 112),
	Color3.fromRGB(132, 218, 128),
	Color3.fromRGB(104, 172, 255),
	Color3.fromRGB(122, 124, 232),
	Color3.fromRGB(178, 120, 232), -- violet (dedans)
}
local GOLD = Color3.fromRGB(255, 198, 52)
local GOLD_DARK = Color3.fromRGB(214, 150, 28)
local POT_BLACK = Color3.fromRGB(34, 32, 38)

type Band = { Radius: number, Color: Color3, Opacity: number, Width: number, A0: Attachment, A1: Attachment, A2: Attachment, B0: Beam, B1: Beam, Fade: boolean }
type Coin = { Part: BasePart, P: Vector3, V: Vector3, Spin: number, Age: number }

local root: Folder? = nil
local anchor: BasePart? = nil
local bands: { Band } = {}
local pot: Model? = nil
local potParts: { [string]: any } = {}
local coins: { Coin } = {}
local current = { Id = -1, Amount = 0, Pos = nil :: Vector3?, Source = "", Emptied = false, Yaw = Vector3.new(1, 0, 0) }
local localSpots: { [number]: Vector3 } = {}
local geomClock = 0
local shownOpacity = -1
local winConn: RBXScriptConnection? = nil
local lastWin = ""
local fresh = false

-- Point de l'arc (pur) : pied `foot` (angle pi), centre = foot + side * e1 * r
function RainbowFx.ArcPoint(foot: Vector3, e1: Vector3, side: number, radius: number, angle: number): Vector3
	local center = foot + e1 * (side * radius)
	return center + e1 * (side * radius * math.cos(angle)) + Vector3.new(0, radius * math.sin(angle), 0)
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	return p
end

----------------------------------------------------------------------
-- Arc (Beams)
----------------------------------------------------------------------

local function newBeam(a0: Attachment, a1: Attachment, color: Color3, width: number, z: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(color)
	b.Width0 = width
	b.Width1 = width
	b.Segments = 40
	b.FaceCamera = true
	b.LightEmission = 0.35
	b.LightInfluence = 0
	b.ZOffset = z
	b.Transparency = NumberSequence.new(1)
	b.Parent = a0.Parent
	return b
end

local function buildArc(part: BasePart)
	table.clear(bands)
	local function add(radius: number, color: Color3, opacity: number, width: number, z: number, fade: boolean)
		local a0 = Instance.new("Attachment")
		a0.Name = "Foot"
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "Apex"
		a1.Parent = part
		local a2 = Instance.new("Attachment")
		a2.Name = "FarFoot"
		a2.Parent = part
		local b0 = newBeam(a0, a1, color, width, z)
		local b1 = newBeam(a1, a2, color, width, z)
		table.insert(bands, { Radius = radius, Color = color, Opacity = opacity, Width = width, A0 = a0, A1 = a1, A2 = a2, B0 = b0, B1 = b1, Fade = fade })
	end
	-- lueur claire à l'intérieur de l'arc (le ciel est plus clair sous un arc-en-ciel)
	add(RADIUS - 7.5 * BAND_W, Color3.fromRGB(255, 252, 240), 0.07, 8 * BAND_W, 0, true)
	-- arc principal : rouge dehors, violet dedans ; bandes larges qui se recouvrent (dégradé doux)
	for i, color in ipairs(COLORS) do
		local edge = (i == 1 or i == #COLORS)
		add(RADIUS + (4 - i) * BAND_W, color, edge and 0.36 or 0.5, BAND_W * 1.7, 1, false)
	end
	-- arc secondaire (couleurs inversées), très pâle, plus large
	for i, color in ipairs(COLORS) do
		add(RADIUS * 1.27 + (i - 4) * BAND_W * 1.2, color, 0.12, BAND_W * 2, 0, true)
	end
end

local function opacityCurve(opacity: number, fadeFar: boolean, near: boolean): NumberSequence
	local t = 1 - opacity
	if near then
		-- jambe du pot : pleine jusqu'au sol (on la voit plonger dans le pot)
		-- (plus légère tout en bas : on voit le pot dans la colonne de couleurs)
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.min(1, t + (1 - t) * 0.45)),
			NumberSequenceKeypoint.new(0.05, t),
			NumberSequenceKeypoint.new(1, t),
		})
	end
	if fadeFar then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, t),
			NumberSequenceKeypoint.new(0.45, math.min(1, t + (1 - t) * 0.35)),
			NumberSequenceKeypoint.new(0.85, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	-- jambe lointaine : s'efface dans la brume
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, t),
		NumberSequenceKeypoint.new(0.4, math.min(1, t + (1 - t) * 0.25)),
		NumberSequenceKeypoint.new(0.8, math.min(1, t + (1 - t) * 0.8)),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function paintArc(amount: number, night: boolean)
	local k = amount * amount * (3 - 2 * amount)
	local key = math.floor(k * 40 + 0.5) + (night and 1000 or 0)
	if key == shownOpacity then
		return
	end
	shownOpacity = key
	for _, band in ipairs(bands) do
		local color = band.Color
		local opacity = band.Opacity * k
		if night then
			color = color:Lerp(Color3.fromRGB(236, 240, 255), 0.65) -- arc lunaire
			opacity *= 0.45
		end
		band.B0.Color = ColorSequence.new(color)
		band.B1.Color = ColorSequence.new(color)
		band.B0.Transparency = opacityCurve(opacity, band.Fade, not band.Fade)
		band.B1.Transparency = opacityCurve(opacity, band.Fade, false)
	end
end

-- Place les attachements : pied au pot, sommet, pied lointain (quarts de cercle)
local function placeArc(foot: Vector3, e1: Vector3, side: number)
	local holder = anchor
	if not holder then
		return
	end
	-- (attachements en repère de l'ancre : CFrame local = monde exact)
	local base = holder.CFrame
	local up = Vector3.new(0, 1, 0)
	local dir = e1 * side -- du pied vers le centre
	for _, band in ipairs(bands) do
		local r = band.Radius
		-- (le pied de la bande du milieu est SUR le pot : les autres de part et d'autre)
		local center = foot + dir * RADIUS
		local p0 = center - dir * r
		local p1 = center + up * r
		local p2 = center + dir * r
		-- axes = sens du parcours : en haut au pied, vers le loin au sommet, en bas au loin
		band.A0.CFrame = base:ToObjectSpace(CFrame.fromMatrix(p0, up, dir))
		band.A1.CFrame = base:ToObjectSpace(CFrame.fromMatrix(p1, dir, up))
		band.A2.CFrame = base:ToObjectSpace(CFrame.fromMatrix(p2, -up, dir))
		local c = K_BEZIER * r
		band.B0.CurveSize0 = c
		band.B0.CurveSize1 = c
		band.B1.CurveSize0 = c
		band.B1.CurveSize1 = c
	end
end

----------------------------------------------------------------------
-- Pot d'or
----------------------------------------------------------------------

local function buildPot(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "PotOfGold"
	table.clear(potParts)
	local function put(name: string, part: BasePart, offset: CFrame)
		part:SetAttribute("Offset", offset)
		part.Parent = model
		potParts[name] = part
		return part
	end
	-- marmite : panse ronde, rebord épais, 3 pieds, anses
	put("Belly", newPart("Belly", Vector3.new(4.6, 3.6, 4.6), POT_BLACK, Enum.Material.Metal, Enum.PartType.Ball), CFrame.new(0, 2.05, 0))
	put("Rim", newPart("Rim", Vector3.new(0.5, 4.1, 4.1), Color3.fromRGB(46, 44, 52), Enum.Material.Metal, Enum.PartType.Cylinder), CFrame.new(0, 3.62, 0) * CFrame.Angles(0, 0, math.pi / 2))
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		put("Leg" .. i, newPart("Leg", Vector3.new(0.55, 0.9, 0.55), POT_BLACK, Enum.Material.Metal, Enum.PartType.Ball), CFrame.new(math.cos(a) * 1.35, 0.42, math.sin(a) * 1.35))
	end
	for _, sx in ipairs({ -1, 1 }) do
		put("Handle" .. sx, newPart("Handle", Vector3.new(0.3, 0.9, 0.9), Color3.fromRGB(52, 50, 58), Enum.Material.Metal, Enum.PartType.Cylinder), CFrame.new(sx * 2.45, 3.05, 0))
	end
	-- tas de pièces d'or qui déborde + quelques pièces posées / au sol
	put("Gold", newPart("Gold", Vector3.new(3.7, 1.5, 3.7), GOLD, Enum.Material.Metal, Enum.PartType.Ball), CFrame.new(0, 3.95, 0))
	local spots = {
		{ 0.6, 4.55, 0.3, 0.3 }, { -0.7, 4.45, -0.5, -0.4 }, { 0.1, 4.7, -0.2, 0.2 }, { 1.1, 4.25, -0.6, 0.6 },
		{ 2.9, 0.12, 1.2, 0 }, { -2.6, 0.12, 1.9, 0 }, { 1.4, 0.12, -2.9, 0 }, { -1.9, 0.12, -2.4, 0 },
	}
	for i, s in ipairs(spots) do
		local tilt = CFrame.Angles(0, i * 1.7, s[4])
		put("Coin" .. i, newPart("Coin", Vector3.new(0.16, 0.95, 0.95), if i % 2 == 0 then GOLD else GOLD_DARK, Enum.Material.Metal, Enum.PartType.Cylinder),
			CFrame.new(s[1], s[2], s[3]) * tilt * CFrame.Angles(0, 0, math.pi / 2))
	end
	local gold = potParts.Gold :: BasePart
	gold.Reflectance = 0.25
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 120)
	light.Brightness = 0.9
	light.Range = 14
	light.Shadows = false
	light.Parent = gold
	potParts.Light = light
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 236, 150))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkles.Lifetime = NumberRange.new(0.9, 1.6)
	sparkles.Rate = 10
	sparkles.Speed = NumberRange.new(1.5, 3.5)
	sparkles.SpreadAngle = Vector2.new(50, 50)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-120, 120)
	sparkles.Parent = gold
	potParts.Sparkles = sparkles
	-- colonne de lumière dorée (repère de loin)
	local a0 = Instance.new("Attachment")
	a0.Name = "BeaconBase"
	a0.CFrame = CFrame.new(0, 0.5, 0)
	a0.Parent = gold
	local a1 = Instance.new("Attachment")
	a1.Name = "BeaconTop"
	a1.CFrame = CFrame.new(0, 140, 0)
	a1.Parent = gold
	local beacon = Instance.new("Beam")
	beacon.Name = "Beacon"
	beacon.Attachment0 = a0
	beacon.Attachment1 = a1
	beacon.Color = ColorSequence.new(Color3.fromRGB(255, 224, 120))
	beacon.Width0 = 3.2
	beacon.Width1 = 0.8
	beacon.FaceCamera = true
	beacon.LightEmission = 0.8
	beacon.LightInfluence = 0
	beacon.Segments = 8
	beacon.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 1) })
	beacon.Parent = gold
	potParts.Beacon = beacon
	-- étiquette lisible de loin
	local bb = Instance.new("BillboardGui")
	bb.Name = "PotLabel"
	bb.Size = UDim2.fromOffset(190, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 8.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 4000
	bb.LightInfluence = 0
	bb.Adornee = gold
	pcall(function()
		(bb :: any).ResetOnSpawn = false
	end)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(255, 248, 224)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD_DARK
	stroke.Thickness = 2
	stroke.Parent = card
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -12, 0.56, 0)
	title.Position = UDim2.fromOffset(6, 3)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(150, 96, 10)
	title.Text = Locale.T("🍀 Pot of gold")
	title.Parent = card
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -12, 0.36, 0)
	info.Position = UDim2.new(0, 6, 0.58, 0)
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(120, 92, 60)
	info.Text = ""
	info.Parent = card
	bb.Parent = model
	potParts.Label = bb
	potParts.Info = info
	model.Parent = parent
	return model
end

local function placePot(pos: Vector3)
	local model = pot
	if not model then
		return
	end
	local base = CFrame.new(pos)
	local parts, cframes = {}, {}
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local offset = d:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				table.insert(parts, d)
				table.insert(cframes, base * offset)
			end
		end
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, part in ipairs(parts) do
			part.CFrame = cframes[i]
		end
	end
end

local function setEmptied(emptied: boolean)
	if current.Emptied == emptied then
		return
	end
	current.Emptied = emptied
	local gold = potParts.Gold
	if gold then
		gold.Transparency = emptied and 1 or 0
	end
	for i = 1, 4 do
		local c = potParts["Coin" .. i]
		if c then
			c.Transparency = emptied and 1 or 0
		end
	end
	local sparkles = potParts.Sparkles
	if sparkles then
		sparkles.Enabled = not emptied
	end
	local beacon = potParts.Beacon
	if beacon then
		beacon.Enabled = not emptied
	end
	local light = potParts.Light
	if light then
		light.Enabled = not emptied
	end
end

----------------------------------------------------------------------
-- Place du pot
----------------------------------------------------------------------

local function groundAt(base: Vector3): Vector3
	local exclude: { Instance } = {}
	if root then
		table.insert(exclude, root)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, 8 do
		params.FilterDescendantsInstances = exclude
		local ok, hit = pcall(function()
			return workspace:Raycast(base + Vector3.new(0, 7, 0), Vector3.new(0, -14, 0), params)
		end)
		if not ok or not hit then
			break
		end
		if hit.Normal.Y > 0.8 then
			return hit.Position
		end
		table.insert(exclude, hit.Instance)
	end
	return base
end

local function potPosition(id: number): (Vector3?, string)
	local sid = workspace:GetAttribute("PotOfGoldId")
	local spos = workspace:GetAttribute("PotOfGoldPos")
	if sid == id and typeof(spos) == "Vector3" then
		local cached = localSpots[-id - 1]
		if not cached or (Vector3.new(cached.X, 0, cached.Z) - Vector3.new(spos.X, 0, spos.Z)).Magnitude > 0.01 then
			-- (posé sur le sol VISIBLE du client : pavés, herbe...)
			cached = groundAt(spos)
			localSpots[-id - 1] = cached
		end
		return cached, "Server"
	end
	local cached = localSpots[id]
	if cached then
		return cached, "Local"
	end
	local count = WorldLayout.PlotCount(Players.MaxPlayers)
	local spots = RainbowGold.Candidates(count)
	if #spots == 0 then
		return nil, ""
	end
	local spot = spots[RainbowGold.Order(id, #spots)[1]]
	local pos = groundAt(WorldLayout.CityPoint(spot.X, spot.Y, spot.Z))
	localSpots[id] = pos
	return pos, "Local"
end

----------------------------------------------------------------------
-- Gain : gerbe de pièces
----------------------------------------------------------------------

local function clearCoins()
	for _, c in ipairs(coins) do
		c.Part:Destroy()
	end
	table.clear(coins)
end

local function floatText(text: string, at: Vector3)
	local r = root
	if not r then
		return
	end
	local holder = newPart("FloatText", Vector3.new(0.2, 0.2, 0.2), GOLD)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(at)
	holder.Parent = r
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 70)
	label.TextStrokeColor3 = Color3.fromRGB(120, 70, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = bb
	bb.Parent = holder
	task.spawn(function()
		for i = 1, 40 do
			task.wait(0.05)
			if holder.Parent == nil then
				return
			end
			holder.CFrame = CFrame.new(at + Vector3.new(0, i * 0.12, 0))
			if i > 24 then
				label.TextTransparency = (i - 24) / 16
				label.TextStrokeTransparency = 0.2 + 0.8 * (i - 24) / 16
			end
		end
		holder:Destroy()
	end)
end

function RainbowFx.Celebrate(amount: number?)
	local r = root
	local gold = potParts.Gold
	if not r or not gold then
		return
	end
	clearCoins()
	local origin = gold.Position + Vector3.new(0, 0.6, 0)
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2 + (i % 3) * 0.4
		local out = 5 + (i % 5) * 1.6
		local part = newPart("FlyingCoin", Vector3.new(0.16, 0.9, 0.9), if i % 2 == 0 then GOLD else GOLD_DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		part.Reflectance = 0.3
		part.CFrame = CFrame.new(origin)
		part.Parent = r
		table.insert(coins, { Part = part, P = origin, V = Vector3.new(math.cos(a) * out, 20 + (i % 4) * 3.5, math.sin(a) * out), Spin = 8 + (i % 6), Age = 0 })
	end
	local sparkles = potParts.Sparkles
	if sparkles then
		pcall(function()
			sparkles:Emit(45)
		end)
	end
	if amount and amount > 0 then
		floatText("+" .. NumberFormatter.Format(amount) .. " 🧠", origin + Vector3.new(0, 4, 0))
	end
end

local function stepCoins(dt: number)
	if #coins == 0 then
		return
	end
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local target = character and character:FindFirstChild("HumanoidRootPart")
	local targetPos = if target and target:IsA("BasePart") then target.Position else nil
	local parts, cframes = {}, {}
	local alive = 0
	for _, c in ipairs(coins) do
		c.Age += dt
		if c.Age < 2.2 then
			alive += 1
			if c.Age < 1.1 or not targetPos then
				c.V += Vector3.new(0, -46 * dt, 0)
				c.P += c.V * dt
			else
				-- elles volent vers le joueur
				local k = math.clamp((c.Age - 1.1) / 0.9, 0, 1)
				c.P = c.P:Lerp(targetPos :: Vector3, math.clamp(dt * (3 + 10 * k), 0, 1))
			end
			table.insert(parts, c.Part)
			table.insert(cframes, CFrame.new(c.P) * CFrame.Angles(0, c.Age * c.Spin, c.Age * c.Spin * 0.6) * CFrame.Angles(0, 0, math.pi / 2))
			if c.Age > 1.9 then
				c.Part.Transparency = math.clamp((c.Age - 1.9) / 0.3, 0, 1)
			end
		elseif c.Part.Parent then
			c.Part:Destroy()
		end
	end
	if #parts > 0 then
		pcall(function()
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end
	if alive == 0 then
		clearCoins()
	end
end

local function onWin()
	local player = Players.LocalPlayer
	local value = player and player:GetAttribute("PotOfGoldWin")
	if type(value) ~= "string" or value == lastWin or current.Id == -1 or pot == nil then
		return -- (pot pas encore affiché : on relira l'attribut à la prochaine passe)
	end
	lastWin = value
	local id, _place, amount = string.match(value, "^(%-?%d+)|(%d+)|(%d+)$")
	if id and tonumber(id) == current.Id then
		RainbowFx.Celebrate(tonumber(amount))
	end
end

----------------------------------------------------------------------
-- Cycle
----------------------------------------------------------------------

local function hideAll()
	if anchor then
		anchor:Destroy()
		anchor = nil
	end
	table.clear(bands)
	if pot then
		pot:Destroy()
		pot = nil
	end
	table.clear(potParts)
	current.Id = -1
	current.Amount = 0
	current.Pos = nil
	current.Source = ""
	current.Emptied = false
	shownOpacity = -1
end

function RainbowFx.Start(parent: Instance, _opts: any?)
	if root then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "DopamineRainbow"
	f.Parent = parent
	root = f
	geomClock = 1e9
	local player = Players.LocalPlayer
	if player then
		lastWin = tostring(player:GetAttribute("PotOfGoldWin") or "")
		winConn = player:GetAttributeChangedSignal("PotOfGoldWin"):Connect(function()
			pcall(onWin)
		end)
	end
end

function RainbowFx.Stop()
	if winConn then
		winConn:Disconnect()
		winConn = nil
	end
	clearCoins()
	hideAll()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(localSpots)
end

function RainbowFx.Step(dt: number, t: number, camPos: Vector3, night: boolean)
	local r = root
	if not r then
		return
	end
	stepCoins(dt)
	geomClock += dt
	-- (gain : aussi relu ici, au cas où le signal d'attribut arrive avant l'arc)
	if geomClock >= GEOM_EVERY then
		pcall(onWin)
	end
	if geomClock < GEOM_EVERY then
		return
	end
	local elapsed = math.min(geomClock, 1)
	geomClock = 0
	local event = RainbowGold.Event(t)
	if not event or event.Amount <= 0.01 then
		if current.Id ~= -1 then
			hideAll()
		end
		return
	end
	local pos, source = potPosition(event.Id)
	if not pos then
		return
	end
	if current.Id ~= event.Id then
		hideAll()
		current.Id = event.Id
		current.Yaw = Vector3.new(1, 0, 0)
		fresh = true
		local a = newPart("RainbowAnchor", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
		a.Transparency = 1
		a.CFrame = CFrame.new(pos)
		a.Parent = r
		anchor = a
		buildArc(a)
		pot = buildPot(r)
		geomClock = 0
	end
	current.Amount = event.Amount
	current.Source = source
	if current.Pos ~= pos then
		current.Pos = pos
		placePot(pos)
		if anchor then
			anchor.CFrame = CFrame.new(pos)
		end
	end
	-- l'arc fait face au joueur (pivot doux autour du pied), figé tout près
	local flat = Vector3.new(pos.X - camPos.X, 0, pos.Z - camPos.Z)
	local e1 = current.Yaw
	local want: Vector3? = if flat.Magnitude > 0.5 then Vector3.new(0, 1, 0):Cross(flat.Unit) else nil
	if fresh then
		fresh = false
		if want then
			e1 = want -- (première image : directement de face)
		end
	elseif want and flat.Magnitude > NEAR_FREEZE then
		local target = want
		if target:Dot(e1) < -0.2 then
			-- (le joueur passe de l'autre côté : l'arc reste du même côté, pas de saut)
			target = -target
		end
		local mixed = e1:Lerp(target, math.clamp(elapsed / YAW_TIME, 0, 1))
		if mixed.Magnitude > 1e-3 then
			e1 = mixed.Unit
		end
	end
	current.Yaw = e1
	placeArc(pos, e1, RainbowGold.Side(event.Id))
	paintArc(event.Amount, night)
	-- étiquette + pot vidé
	local winners = tonumber(workspace:GetAttribute("PotOfGoldWinners")) or 0
	local maxW = tonumber(workspace:GetAttribute("PotOfGoldMax")) or RainbowGold.CONFIG.MaxWinners
	local live = workspace:GetAttribute("PotOfGoldId") == event.Id
	setEmptied(live and winners >= maxW)
	local info = potParts.Info
	if info then
		local dist = (pos - camPos).Magnitude
		local meters = math.floor(dist * 0.28 + 0.5) -- (1 stud ≈ 0,28 m)
		if current.Emptied then
			info.Text = Locale.T("The pot is empty!")
		elseif live then
			info.Text = Locale.T("%d m · %d left", meters, math.max(0, maxW - winners))
		else
			info.Text = Locale.T("%d m", meters)
		end
	end
end

function RainbowFx.State(): any
	local nBeams = 0
	for _ in ipairs(bands) do
		nBeams += 2
	end
	return {
		Id = current.Id,
		Amount = current.Amount,
		Pos = current.Pos,
		Source = current.Source,
		Beams = nBeams,
		Coins = #coins,
		Emptied = current.Emptied,
		Yaw = current.Yaw,
		Bands = bands,
		Pot = pot,
	}
end

return RainbowFx
