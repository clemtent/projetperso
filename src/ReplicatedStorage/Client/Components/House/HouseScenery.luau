--[[
	HouseScenery (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseScenery

	Tout ce qui entoure la pièce pour lui donner un vrai air de "maison de
	poupée" kawaii (uniquement des Frames) :
	  - fond de scène : ciel pastel en dégradé, nuages qui passent
	    doucement, petites étincelles (la nuit : ciel bleu nuit, étoiles
	    qui scintillent, nuages plus sombres) ;
	  - toit en tuiles arrondies au-dessus de la pièce : rangées de tuiles,
	    bord festonné, faîtage, lucarne ronde (allumée la nuit) et cheminée
	    qui fume ;
	  - pelouse sous la maison avec de petites fleurs ;
	  - poussières de lumière qui flottent dans la pièce (lucioles la nuit).
	Coordonnées en px de "maquette" de la pièce (voir HouseRoom).

	API :
	  HouseScenery.ROOF, HouseScenery.GROUND : place prise au-dessus / en dessous
	  HouseScenery.new(stage, roomFrame, shell, ceil, zMotes) -> Scenery
	    :Rebuild(width, height, wallHeight)
	    :SetDark(dark)
	    :SetPalette(exterior)   (toit assorti : Cottage, Townhouse, Loft, Mansion)
	    :Update(dt)
]]

local Client = script.Parent.Parent.Parent
local UIUtil = require(Client.UIUtil)
local HouseCommon = require(script.Parent.HouseCommon)
local HousePatterns = require(script.Parent.HousePatterns)

local HouseScenery = {}

HouseScenery.ROOF = 66 -- hauteur du toit au-dessus du plafond
HouseScenery.GROUND = 22 -- pelouse sous la dalle

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Round = HousePatterns.Round

-- Couleurs du toit selon le style de l'immeuble (House/HouseExterior)
local ROOF_PALETTES: { [string]: { Color3 } } = {
	Cottage = { Color3.fromRGB(255, 150, 190), Color3.fromRGB(226, 104, 156) },
	Townhouse = { Color3.fromRGB(176, 166, 246), Color3.fromRGB(132, 118, 216) },
	Loft = { Color3.fromRGB(232, 142, 120), Color3.fromRGB(190, 98, 88) },
	Mansion = { Color3.fromRGB(162, 140, 232), Color3.fromRGB(112, 90, 196) },
}
local GRASS = Color3.fromRGB(150, 222, 150)
local GRASS_DARK = Color3.fromRGB(108, 190, 118)

local SKY_DAY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(196, 228, 255)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 226, 240)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 226)),
})
local SKY_NIGHT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 32, 88)),
	ColorSequenceKeypoint.new(0.65, Color3.fromRGB(86, 64, 150)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 96, 170)),
})

export type Scenery = {
	Rebuild: (self: Scenery, width: number, height: number, wallHeight: number) -> (),
	SetDark: (self: Scenery, dark: boolean) -> (),
	Update: (self: Scenery, dt: number) -> (),
	SetPalette: (self: Scenery, exterior: string?) -> (),
}

type Cloud = { Frame: Frame, Speed: number, Y: number, X: number }
type Mote = { Frame: Frame, X: number, Y: number, Speed: number, Phase: number }
type Puff = { Frame: Frame, Phase: number }

-- Pseudo-aléatoire stable
local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

function HouseScenery.new(stage: Frame, room: Frame, shellSize: number, ceil: number, zMotes: number): Scenery
	local dark = false
	local clock = 0
	local width, height = 760, 440
	local ROOF_COLOR = ROOF_PALETTES.Cottage[1]
	local ROOF_DARK = ROOF_PALETTES.Cottage[2]
	local paletteName = "Cottage"

	------------------------------------------------------------------
	-- Fond de scène (derrière la pièce, dans le Stage)
	------------------------------------------------------------------
	local backdrop = UIUtil.Create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = stage,
	})
	UIUtil.Corner(backdrop, 20)
	local sky = UIUtil.Gradient(backdrop, SKY_DAY, 90)

	local clouds: { Cloud } = {}
	for index = 1, 6 do
		local holder = UIUtil.Create("Frame", {
			Name = "Cloud" .. index,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(120, 80),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = backdrop,
		})
		local w = 70 + noise(index, 1) * 70
		HousePatterns.Cloud(holder, 60, 80, w, WHITE, 0.15 + noise(index, 2) * 0.25, 1)
		table.insert(clouds, {
			Frame = holder,
			Speed = 0.006 + noise(index, 3) * 0.01,
			Y = 0.12 + noise(index, 4) * 0.7,
			X = noise(index, 5),
		})
	end

	-- Étincelles (jour) / étoiles (nuit)
	local stars: { Frame } = {}
	for index = 1, 22 do
		local size = 5 + noise(index, 7) * 7
		local holder = UIUtil.Create("Frame", {
			Name = "Star" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.03 + noise(index, 8) * 0.94, 0.04 + noise(index, 9) * 0.9),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = backdrop,
		})
		HousePatterns.Sparkle(holder, size / 2, size / 2, size, WHITE, 0.2, 1)
		holder:SetAttribute("Phase", noise(index, 10) * 6)
		table.insert(stars, holder)
	end

	------------------------------------------------------------------
	-- Toit, pelouse (derrière la coque) et poussières (dans la pièce)
	------------------------------------------------------------------
	local roof = UIUtil.Create("Frame", {
		Name = "Roof",
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = room,
	})
	local ground = UIUtil.Create("Frame", {
		Name = "Ground",
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = room,
	})
	local motesLayer = UIUtil.Create("Frame", {
		Name = "Motes",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zMotes,
		Parent = room,
	})

	local atticGlass: Frame? = nil
	local atticGlow: Frame? = nil
	local puffs: { Puff } = {}
	local motes: { Mote } = {}

	local function clearChildren(frame: Frame)
		for _, child in ipairs(frame:GetChildren()) do
			child:Destroy()
		end
	end

	local function buildRoof()
		clearChildren(roof)
		table.clear(puffs)
		local roofH = HouseScenery.ROOF
		local baseW = width + shellSize * 2 + 40
		local topW = math.max(200, width * 0.46)
		local bottom = -ceil + 6 -- le bas du toit passe derrière le plafond
		roof.Position = UDim2.fromOffset(width / 2 - baseW / 2, bottom - roofH)
		roof.Size = UDim2.fromOffset(baseW, roofH)

		-- Cheminée (derrière le toit) + fumée
		local chimneyX = baseW * 0.74
		local chimney = Box(roof, chimneyX, -18, 30, 44, Color3.fromRGB(214, 128, 132), 0, 1)
		Round(chimney, UDim.new(0, 4))
		UIUtil.Stroke(chimney, Color3.fromRGB(150, 76, 96), 2, 0.2)
		for row = 0, 2 do
			Box(chimney, 0, 8 + row * 10, 30, 2, Color3.fromRGB(250, 214, 200), 0.3, 2)
		end
		local cap = Box(roof, chimneyX - 4, -24, 38, 9, Color3.fromRGB(190, 108, 118), 0, 2)
		Round(cap, UDim.new(0, 4))
		for index = 1, 3 do
			local puff = Circle(roof, chimneyX + 15, -30, 14 + index * 4, 14 + index * 4, WHITE, 0.3, 1)
			table.insert(puffs, { Frame = puff, Phase = (index - 1) / 3 })
		end

		-- Pan du toit : trapèze lisse (fines tranches) + rangées de tuiles arrondies
		local slices = 28
		for index = 0, slices - 1 do
			local k = (index + 1) / slices
			local rowW = topW + (baseW - topW) * k
			local band = Box(roof, baseW / 2 - rowW / 2, index * roofH / slices, rowW, roofH / slices + 0.8, ROOF_COLOR, 0, 3)
			band.BackgroundColor3 = ROOF_COLOR:Lerp(ROOF_DARK, 0.1 + k * 0.15)
		end
		local rows = 4
		for row = 1, rows do
			local k = row / rows
			local y = roofH * k - 4
			local rowW = topW + (baseW - topW) * (y / roofH)
			local tile = 24
			local count = math.max(1, math.floor(rowW / tile))
			local offset = (rowW - count * tile) / 2 + (row % 2) * tile / 2
			for index = 0, count - 1 - (row % 2) do
				local cx = baseW / 2 - rowW / 2 + offset + index * tile + tile / 2
				local shingle = Circle(roof, cx, y, tile - 3, 12, ROOF_DARK, 0.45, 4)
				shingle.Size = UDim2.fromOffset(tile - 3, 10)
			end
		end
		-- Reflet doux sur le pan
		local gloss = Box(roof, baseW / 2 - topW / 2 + 16, 6, topW * 0.5, 5, WHITE, 0.55, 5)
		Round(gloss)

		-- Bord du toit (gouttière) festonné
		local eave = Box(roof, -6, roofH - 4, baseW + 12, 10, ROOF_DARK, 0, 5)
		Round(eave)
		UIUtil.Stroke(eave, ROOF_DARK:Lerp(BLACK, 0.3), 1.5, 0.3)
		local scallop = 22
		local x = scallop / 2 - 6
		while x < baseW + 6 do
			Circle(roof, x, roofH + 6, scallop - 2, 14, ROOF_DARK, 0, 4)
			x += scallop
		end
		-- Faîtage
		local ridge = Box(roof, baseW / 2 - topW / 2 - 8, -5, topW + 16, 9, ROOF_DARK, 0, 5)
		Round(ridge)
		UIUtil.Stroke(ridge, ROOF_DARK:Lerp(BLACK, 0.3), 1.5, 0.3)
		HousePatterns.Heart(roof, baseW / 2, -12, 20, C.Heart, 0, 6)

		-- Lucarne ronde au milieu (lumière chaude la nuit)
		local cx, cy = baseW / 2, roofH * 0.52
		local glow = Circle(roof, cx, cy, 70, 70, Color3.fromRGB(255, 220, 140), 1, 5)
		atticGlow = glow
		local frame = Circle(roof, cx, cy, 44, 44, C.Cream, 0, 6)
		UIUtil.Stroke(frame, C.WoodDark, 2, 0.3)
		local glass = Circle(roof, cx, cy, 32, 32, Color3.fromRGB(180, 222, 255), 0, 7)
		UIUtil.Gradient(glass, ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 225)), 90)
		atticGlass = glass
		Box(roof, cx - 1.5, cy - 16, 3, 32, C.Cream, 0, 8)
		Box(roof, cx - 16, cy - 1.5, 32, 3, C.Cream, 0, 8)
		local shine = Box(roof, cx - 11, cy - 11, 8, 4, WHITE, 0.3, 9)
		Round(shine)
	end

	local function buildGround()
		clearChildren(ground)
		local groundW = width + shellSize * 2 + 70
		local top = height + shellSize - 6
		ground.Position = UDim2.fromOffset(width / 2 - groundW / 2, top)
		ground.Size = UDim2.fromOffset(groundW, HouseScenery.GROUND + 6)
		local lawn = Box(ground, 0, 6, groundW, HouseScenery.GROUND, GRASS, 0, 1)
		Round(lawn)
		UIUtil.Stroke(lawn, GRASS_DARK, 2, 0.2)
		UIUtil.Gradient(lawn, ColorSequence.new(WHITE, Color3.fromRGB(215, 225, 215)), 90)
		-- Petites touffes et fleurs devant la maison
		local count = math.floor(groundW / 60)
		for index = 0, count do
			local x = 16 + index * (groundW - 32) / count
			Circle(ground, x, 8 + noise(index, 20) * 3, 16, 12, GRASS:Lerp(GRASS_DARK, 0.3), 0, 2)
			if index % 2 == 1 then
				local colors = { C.Pink, C.Butter, WHITE, C.Lilac }
				local petal = colors[index % #colors + 1]
				local fx = x + 12
				for _, d in ipairs({ Vector2.new(-3, 0), Vector2.new(3, 0), Vector2.new(0, -3), Vector2.new(0, 3) }) do
					Circle(ground, fx + d.X, 12 + d.Y, 5, 5, petal, 0, 3)
				end
				Circle(ground, fx, 12, 3.5, 3.5, C.Butter:Lerp(C.Peach, 0.4), 0, 4)
			end
		end
	end

	local function buildMotes()
		clearChildren(motesLayer)
		table.clear(motes)
		for index = 1, 14 do
			local size = 3 + noise(index, 30) * 3
			local mote = Circle(motesLayer, 0, 0, size, size, WHITE, 0.35, 1)
			table.insert(motes, {
				Frame = mote,
				X = 0.08 + noise(index, 31) * 0.84,
				Y = noise(index, 32),
				Speed = 0.015 + noise(index, 33) * 0.025,
				Phase = noise(index, 34) * 6,
			})
		end
	end

	-- La nuit, le toit et la pelouse passent dans le bleu (couleurs du jour gardées en attribut)
	local NIGHT_TINT = Color3.fromRGB(40, 36, 100)
	local function tint(container: Frame)
		for _, child in ipairs(container:GetDescendants()) do
			if child:IsA("Frame") then
				local day = child:GetAttribute("DayColor")
				if typeof(day) ~= "Color3" then
					day = child.BackgroundColor3
					child:SetAttribute("DayColor", day)
				end
				child.BackgroundColor3 = dark and (day :: Color3):Lerp(NIGHT_TINT, 0.42) or day :: Color3
			end
		end
	end

	local function paint()
		sky.Color = dark and SKY_NIGHT or SKY_DAY
		tint(roof)
		tint(ground)
		for _, cloud in ipairs(clouds) do
			for _, child in ipairs(cloud.Frame:GetDescendants()) do
				if child:IsA("Frame") then
					child.BackgroundColor3 = dark and Color3.fromRGB(120, 110, 180) or WHITE
				end
			end
		end
		for _, star in ipairs(stars) do
			for _, child in ipairs(star:GetDescendants()) do
				if child:IsA("Frame") then
					child.BackgroundColor3 = dark and Color3.fromRGB(255, 244, 190) or WHITE
				end
			end
		end
		local glass = atticGlass
		if glass then
			glass.BackgroundColor3 = dark and Color3.fromRGB(255, 214, 120) or Color3.fromRGB(180, 222, 255)
		end
		local glow = atticGlow
		if glow then
			glow.BackgroundTransparency = dark and 0.72 or 1
		end
		for _, mote in ipairs(motes) do
			mote.Frame.BackgroundColor3 = dark and Color3.fromRGB(255, 240, 140) or WHITE
		end
	end

	local scenery = {} :: any

	function scenery:Rebuild(newWidth: number, newHeight: number, _wallHeight: number)
		width, height = newWidth, newHeight
		buildRoof()
		buildGround()
		buildMotes()
		paint()
	end

	-- Toit assorti à l'immeuble (reconstruit seulement si le style change)
	function scenery:SetPalette(exterior: string?)
		local name = exterior and ROOF_PALETTES[exterior :: string] and exterior :: string or "Cottage"
		if name == paletteName then
			return
		end
		paletteName = name
		ROOF_COLOR, ROOF_DARK = ROOF_PALETTES[name][1], ROOF_PALETTES[name][2]
		buildRoof()
		paint()
	end

	function scenery:SetDark(value: boolean)
		dark = value
		paint()
	end

	function scenery:Update(dt: number)
		clock += dt
		-- Nuages qui passent (ils repartent de l'autre côté)
		for _, cloud in ipairs(clouds) do
			cloud.X = (cloud.X + cloud.Speed * dt) % 1.3
			cloud.Frame.Position = UDim2.fromScale(cloud.X - 0.15, cloud.Y)
		end
		-- Étoiles / étincelles qui scintillent
		for _, star in ipairs(stars) do
			local phase = tonumber(star:GetAttribute("Phase")) or 0
			local wave = 0.5 + 0.5 * math.sin(clock * 2 + phase)
			local base = dark and 0.05 or 0.45
			for _, child in ipairs(star:GetChildren()) do
				if child:IsA("Frame") then
					child.BackgroundTransparency = base + wave * 0.45
				end
			end
		end
		-- Fumée de la cheminée : monte, grossit et s'efface
		for _, puff in ipairs(puffs) do
			local t = (clock * 0.35 + puff.Phase) % 1
			local size = 10 + t * 18
			puff.Frame.Size = UDim2.fromOffset(size, size)
			local roofW = width + shellSize * 2 + 40
			puff.Frame.Position = UDim2.fromOffset(roofW * 0.74 + 15 - size / 2 + math.sin(t * 6) * 4, -30 - t * 46 - size / 2)
			puff.Frame.BackgroundTransparency = 0.25 + t * 0.75
		end
		-- Poussières de lumière (lucioles la nuit) : montent doucement en ondulant
		for _, mote in ipairs(motes) do
			mote.Y = (mote.Y - mote.Speed * dt) % 1
			local x = mote.X + math.sin(clock * 0.8 + mote.Phase) * 0.012
			local y = 0.1 + mote.Y * 0.85
			mote.Frame.Position = UDim2.new(x, 0, y, 0)
			local twinkle = 0.5 + 0.5 * math.sin(clock * 2.3 + mote.Phase)
			mote.Frame.BackgroundTransparency = (dark and 0.1 or 0.45) + twinkle * 0.4
		end
	end

	return scenery :: Scenery
end

return HouseScenery
