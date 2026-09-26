--[[
	Effects (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Effects

	Effets visuels 2D : textes flottants "+X", particules, confettis,
	flash d'écran, gros messages. (Les ParticleEmitter ne fonctionnent pas
	dans les interfaces, on anime donc de petits Frames.)
	Le réglage "Effets" (SetEnabled) coupe particules et confettis.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)

local Effects = {}

local layer: Frame? = nil -- calque plein écran pour les effets
local enabled = true -- paramètre "Effets" (particules / confettis)
local random = Random.new()
local activeParticles = 0 -- confettis en cours (les particules de Burst sont comptées à part)
local MAX_PARTICLES = 160 -- limite pour les petits appareils
local MAX_TEXTS = 60

local CONFETTI_COLORS = {
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Purple,
	Theme.Colors.Yellow,
	Theme.Colors.Green,
	Theme.Colors.Orange,
	Theme.Colors.Red,
	Theme.Colors.Blue,
}

function Effects.Init(effectsLayer: Frame)
	layer = effectsLayer
end

function Effects.SetEnabled(value: boolean)
	enabled = value
end

function Effects.IsEnabled(): boolean
	return enabled
end

-- Calque plein écran des effets (nil avant Init)
function Effects.GetLayer(): Frame?
	return layer
end

-- Dans un emplacement de stimulus (calque "Slots", ClipsDescendants = true), un
-- texte qui monte de 100 px serait coupé : on le redessine dans le calque
-- "Overlay" (non coupé, sous les menus) à la même position à l'écran.
local function unclip(parent: GuiObject, position: UDim2): (GuiObject, UDim2)
	local root = layer and layer.Parent
	local slots = root and root:FindFirstChild("Slots")
	local overlay = root and root:FindFirstChild("Overlay")
	if not root or not slots or not overlay or not overlay:IsA("GuiObject") or not parent:IsDescendantOf(slots) then
		return parent, position
	end
	local clipped = false
	local node: Instance? = parent
	while node and node ~= slots do
		if node:IsA("GuiObject") and node.ClipsDescendants then
			clipped = true
			break
		end
		node = node.Parent
	end
	if not clipped then
		return parent, position
	end
	local uiScale = root:FindFirstChildOfClass("UIScale")
	local scale = uiScale and uiScale.Scale or 1
	if scale <= 0 then
		return parent, position
	end
	-- Les décalages (Offset) sont agrandis par TOUS les UIScale au-dessus du
	-- parent (toile + échelle du slot sur téléphone)
	local factor = 1
	local node2: Instance? = parent
	while node2 and node2 ~= root.Parent do
		local nodeScale = node2:FindFirstChildOfClass("UIScale")
		if nodeScale then
			factor *= nodeScale.Scale
		end
		node2 = node2.Parent
	end
	local absolute = parent.AbsolutePosition
		+ parent.AbsoluteSize * Vector2.new(position.X.Scale, position.Y.Scale)
		+ Vector2.new(position.X.Offset, position.Y.Offset) * factor
	local canvas = (absolute - overlay.AbsolutePosition) / scale
	return overlay, UDim2.fromOffset(canvas.X, canvas.Y)
end

----------------------------------------------------------------------
-- Moteur des textes flottants et des particules (réserve d'objets)
-- Au lieu de créer / détruire un TextLabel (et 3 tweens) à chaque "+X",
-- on recycle des objets et UNE seule connexion RenderStepped les anime
-- (coupée dès qu'il n'y a plus rien à animer).
----------------------------------------------------------------------

type Float = {
	Label: TextLabel,
	Stroke: UIStroke,
	Scale: UIScale,
	Gradient: UIGradient,
	Start: UDim2,
	Age: number,
	Life: number,
	Rise: number,
	Drift: number,
	Tilt: number,
	Peak: number,
	Shake: number,
	BaseStroke: number,
}

type Particle = {
	Frame: Frame,
	Start: UDim2,
	DX: number,
	DY: number,
	Age: number,
	Life: number,
	Size: number,
}

local floatPool: { Float } = {}
local floats: { Float } = {}
local particlePool: { Particle } = {}
local particles: { Particle } = {}
local loop: RBXScriptConnection? = nil
local POOL_KEEP = 40 -- objets gardés en réserve au maximum (par type)

-- Styles : couleurs des dégradés "critique" / "bonus"
local CRIT_TOP = Color3.fromRGB(255, 250, 190)
local CRIT_BOTTOM = Color3.fromRGB(255, 150, 0)
local NUMBER_FONT = Enum.Font.FredokaOne -- chiffres ronds et lisibles
local WHITE = Color3.new(1, 1, 1)

local function easeOutCubic(t: number): number
	local u = 1 - t
	return 1 - u * u * u
end

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

-- Remet un objet en réserve (ou le jette si son parent a été détruit entre-temps)
local function park(instance: Instance, pool: { any }, entry: any)
	local ok = pcall(function()
		instance.Parent = nil
	end)
	if ok and #pool < POOL_KEEP then
		table.insert(pool, entry)
	elseif not ok then
		pcall(function()
			instance:Destroy()
		end)
	else
		instance:Destroy()
	end
end

local function step(dt: number)
	-- Textes
	local index = 1
	while index <= #floats do
		local item = floats[index]
		item.Age += dt
		local age = item.Age
		if age >= item.Life or not item.Label.Parent then
			table.remove(floats, index)
			park(item.Label, floatPool, item)
		else
			local t = age / item.Life
			-- Échelle : "pop" rapide, léger rebond, puis rétrécit un peu
			local scale
			if age < 0.14 then
				scale = 0.35 + (item.Peak - 0.35) * easeOutBack(age / 0.14)
			elseif age < 0.3 then
				scale = item.Peak + (1 - item.Peak) * ((age - 0.14) / 0.16)
			else
				scale = 1 - 0.12 * ((t - 0.3 / item.Life) / (1 - 0.3 / item.Life))
			end
			item.Scale.Scale = math.max(0.05, scale)
			-- Trajectoire : monte en ralentissant, légère courbe sur le côté
			local rise = easeOutCubic(t)
			local x = item.Drift * (t * 0.6 + rise * 0.4)
			local y = -item.Rise * rise
			item.Label.Position = item.Start + UDim2.fromOffset(x, y)
			-- Inclinaison qui se redresse (+ secousse des coups critiques)
			local rotation = item.Tilt * (1 - rise)
			if item.Shake > 0 and age < 0.35 then
				rotation += math.sin(age * 70) * item.Shake * (1 - age / 0.35)
			end
			item.Label.Rotation = rotation
			-- Fondu sur la fin
			local fade = t < 0.6 and 0 or (t - 0.6) / 0.4
			item.Label.TextTransparency = fade
			item.Stroke.Transparency = math.min(1, fade * 1.1 + (1 - item.BaseStroke))
			index += 1
		end
	end
	-- Particules
	index = 1
	while index <= #particles do
		local item = particles[index]
		item.Age += dt
		if item.Age >= item.Life or not item.Frame.Parent then
			table.remove(particles, index)
			park(item.Frame, particlePool, item)
		else
			local t = item.Age / item.Life
			local move = 1 - (1 - t) ^ 4
			item.Frame.Position = item.Start + UDim2.fromOffset(item.DX * move, item.DY * move + 30 * t * t)
			local size = item.Size + (2 - item.Size) * t
			item.Frame.Size = UDim2.fromOffset(size, size)
			item.Frame.BackgroundTransparency = t * t
			index += 1
		end
	end
	if #floats == 0 and #particles == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function ensureLoop()
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

local function newFloat(): Float
	local label = UIUtil.Create("TextLabel", {
		Name = "FloatText",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = NUMBER_FONT,
		Text = "",
		TextSize = 30,
		TextColor3 = WHITE,
		ZIndex = 50,
	})
	local stroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local scale = UIUtil.Create("UIScale", { Parent = label })
	local gradient = UIUtil.Gradient(label, ColorSequence.new(CRIT_TOP, CRIT_BOTTOM), 90)
	gradient.Enabled = false
	return {
		Label = label,
		Stroke = stroke,
		Scale = scale,
		Gradient = gradient,
		Start = UDim2.new(),
		Age = 0,
		Life = 1,
		Rise = 90,
		Drift = 0,
		Tilt = 0,
		Peak = 1.15,
		Shake = 0,
		BaseStroke = 1,
	}
end

--[[
	Texte flottant (réserve d'objets). options :
	  Color  : couleur du texte (défaut : texte du thème)
	  Size   : taille en pixels (défaut 34)
	  Style  : "Normal" | "Crit" (dégradé doré, plus gros, secousse) |
	           "Bonus" (dégradé de la couleur, plus gros) | "Text" (phrase)
	  Rise   : hauteur de montée (défaut selon la taille)
]]
function Effects.Pop(parent: GuiObject, position: UDim2, text: string, options: { [string]: any }?)
	if not parent or not parent.Parent then
		return
	end
	local opts = options or {}
	parent, position = unclip(parent, position)
	local style = tostring(opts.Style or "Normal")
	local size = tonumber(opts.Size) or 34
	local color: Color3 = opts.Color or Theme.Colors.Text

	-- Trop de textes : on recycle le plus ancien (les nouveaux gains s'affichent toujours)
	local item: Float
	if #floats >= MAX_TEXTS then
		item = table.remove(floats, 1) :: Float
	else
		item = table.remove(floatPool) or newFloat()
	end
	local label = item.Label
	local ok = pcall(function()
		label.Parent = parent
	end)
	if not ok then
		item = newFloat()
		label = item.Label
		label.Parent = parent
	end

	local crit = style == "Crit"
	local bonus = style == "Bonus"
	local sentence = style == "Text" or not string.find(text, "^[%+%-]?%d") and not string.find(text, "^%+")
	if crit or bonus then
		size = math.max(size, 38)
	end
	label.Font = sentence and Theme.Fonts.Title or NUMBER_FONT
	label.Text = text
	label.TextSize = math.floor(size + 0.5)
	label.Size = UDim2.fromOffset(math.floor(size * 8), math.floor(size * 1.3))
	label.ZIndex = (crit or bonus) and 52 or 50
	label.TextTransparency = 0
	label.Rotation = 0

	-- Couleur + contour contrasté (épais pour les gros chiffres)
	if crit then
		label.TextColor3 = WHITE
		item.Gradient.Color = ColorSequence.new(CRIT_TOP, CRIT_BOTTOM)
		item.Gradient.Enabled = true
		item.Stroke.Color = Color3.fromRGB(90, 30, 0)
	elseif bonus then
		label.TextColor3 = WHITE
		item.Gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.55), color)
		item.Gradient.Enabled = true
		item.Stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.65)
	else
		label.TextColor3 = color
		item.Gradient.Enabled = false
		item.Stroke.Color = Theme.Luminance(color) > 0.5 and Theme.Colors.TextDark or WHITE
	end
	item.Stroke.Thickness = size >= 40 and 3 or (size >= 26 and 2.5 or 2)
	item.BaseStroke = (crit or bonus or Theme.Luminance(color) > 0.5) and 1 or 0.85
	item.Stroke.Transparency = 1 - item.BaseStroke

	-- Trajectoire aléatoire (légère courbe)
	item.Start = position
	item.Age = 0
	item.Life = (crit or bonus) and 1.35 or (sentence and 1.25 or 0.95)
	item.Rise = tonumber(opts.Rise) or math.clamp(size * 2.6, 70, 150)
	local side = random:NextNumber() < 0.5 and -1 or 1
	item.Drift = side * random:NextNumber(8, 34)
	item.Tilt = side * random:NextNumber(3, 9)
	item.Peak = crit and 1.4 or (bonus and 1.3 or 1.15)
	item.Shake = crit and 6 or 0
	item.Scale.Scale = 0.35
	label.Position = position

	table.insert(floats, item)
	ensureLoop()
end

-- Texte "+X" qui monte et disparaît (API historique, utilisée par les stimuli) :
-- un gros nombre doré (taille >= 40) prend le style "critique"
function Effects.FloatingText(parent: GuiObject, position: UDim2, text: string, color: Color3?, size: number?)
	local height = size or 34
	local style = "Normal"
	if height >= 40 and string.find(text, "^%+") then
		style = (color == nil or color == Theme.Colors.Gold or color == Theme.Colors.Yellow) and "Crit" or "Bonus"
	end
	Effects.Pop(parent, position, text, { Color = color, Size = height, Style = style })
end

-- Couleur / style d'un gain selon sa taille par rapport à une référence
-- (ex. la valeur d'un clic) : (couleur, style)
function Effects.AmountStyle(amount: number, reference: number, dark: boolean?): (Color3, string)
	local ratio = reference > 0 and amount / reference or 1
	if ratio >= 2.5 then
		return Theme.Colors.Gold, "Crit"
	elseif ratio >= 1.8 then
		return Theme.Colors.Orange, "Normal"
	elseif ratio >= 1.25 then
		return Color3.fromRGB(255, 196, 40), "Normal"
	end
	return dark and Theme.Colors.TextLight or Theme.Colors.Text, "Normal"
end

-- Explosion de petites particules rondes autour d'un point (réserve d'objets)
function Effects.Burst(parent: GuiObject, position: UDim2, color: Color3?, count: number?)
	if not enabled or not parent or not parent.Parent then
		return
	end
	for _ = 1, count or 8 do
		if #particles >= MAX_PARTICLES then
			return
		end
		local item: Particle? = table.remove(particlePool)
		if item then
			local ok = pcall(function()
				(item :: Particle).Frame.Parent = parent
			end)
			if not ok then
				item = nil
			end
		end
		if not item then
			local frame = UIUtil.Create("Frame", {
				Name = "Particle",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				ZIndex = 40,
				Parent = parent,
			})
			UIUtil.Corner(frame, UDim.new(1, 0))
			item = { Frame = frame, Start = position, DX = 0, DY = 0, Age = 0, Life = 0.5, Size = 8 }
		end
		local particle = item :: Particle
		local size = random:NextInteger(6, 14)
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(50, 140)
		particle.Start = position
		particle.DX = math.cos(angle) * distance
		particle.DY = math.sin(angle) * distance
		particle.Age = 0
		particle.Life = random:NextNumber(0.4, 0.7)
		particle.Size = size
		particle.Frame.Position = position
		particle.Frame.Size = UDim2.fromOffset(size, size)
		particle.Frame.BackgroundTransparency = 0
		particle.Frame.BackgroundColor3 = color or CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)]
		table.insert(particles, particle)
	end
	ensureLoop()
end

-- Pluie de confettis sur tout l'écran
function Effects.Confetti(count: number?)
	local target = layer
	if not enabled or not target then
		return
	end
	for _ = 1, count or 80 do
		if activeParticles >= MAX_PARTICLES then
			return
		end
		activeParticles += 1
		local piece = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(random:NextInteger(8, 16), random:NextInteger(14, 24)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0, 1), 0, 0, random:NextInteger(-200, -20)),
			Rotation = random:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			ZIndex = 90,
			Parent = target,
		})
		local duration = random:NextNumber(1.6, 3)
		local start = piece.Position
		UIUtil.Tween(piece, duration, {
			Position = UDim2.new(start.X.Scale + random:NextNumber(-0.15, 0.15), 0, 1.1, 0),
			Rotation = piece.Rotation + random:NextNumber(-720, 720),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(duration, function()
			activeParticles -= 1
			piece:Destroy()
		end)
	end
end

-- Flash coloré de tout l'écran
function Effects.Flash(color: Color3?, strength: number?)
	local target = layer
	if not target then
		return
	end
	local flash = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 1 - (strength or 0.6),
		BorderSizePixel = 0,
		ZIndex = 95,
		Parent = target,
	})
	UIUtil.Tween(flash, 0.6, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.7)
end

-- Gros message au centre de l'écran (jackpot, rush...)
function Effects.BigMessage(text: string, color: Color3?, duration: number?)
	local target = layer
	if not target then
		return
	end
	local label = UIUtil.Label({
		Text = text,
		Font = Theme.Fonts.Title,
		TextColor3 = color or Theme.Colors.Yellow,
		Size = UDim2.new(0.9, 0, 0, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		ZIndex = 100,
		MaxTextSize = 90,
		Parent = target,
	})
	local stroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 4)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local scale = UIUtil.Create("UIScale", { Scale = 0.1, Parent = label })
	UIUtil.Tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)

	-- Petit clignotement de couleur
	task.spawn(function()
		local colors = { color or Theme.Colors.Yellow, Theme.Colors.Cyan, Theme.Colors.Pink, Theme.Colors.Green }
		local index = 0
		local finish = os.clock() + (duration or 2.5)
		while label.Parent and os.clock() < finish do
			index = index % #colors + 1
			label.TextColor3 = colors[index]
			task.wait(0.12)
		end
		if not label.Parent then
			return
		end
		UIUtil.Tween(label, 0.4, { TextTransparency = 1 })
		UIUtil.Tween(stroke, 0.4, { Transparency = 1 })
		task.wait(0.4)
		label:Destroy()
	end)
end

return Effects
