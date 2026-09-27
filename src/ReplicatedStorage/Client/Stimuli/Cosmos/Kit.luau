--[[
	Cosmos > Kit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Cosmos > Kit

	Petite boîte à outils commune aux stimuli « cosmiques » :
	  - dessin en Frames (cercles, anneaux, losanges-étoiles, éclats à 4
	    branches, arcs "◡" pour les yeux fermés, dégradés, contours) ;
	  - palette claire / sombre (les objets ont un contour "sticker" doux
	    sur fond clair, une lueur sur fond sombre) ;
	  - boucle d'animation limitée (≤ 20-24 images/s, une seule par
	    stimulus, en pause quand le stimulus est caché, ralentie quand une
	    fenêtre est ouverte par-dessus) ;
	  - suivi du niveau d'une amélioration et du mode sombre ;
	  - objet "posé" par le planificateur (Zones) : cadre centré + UIScale,
	    apparition "pop", glissement quand la place change.
	Rien n'est créé à chaque image : les stimuli construisent leurs objets
	une fois (ou à un changement de niveau / de thème) et les recyclent.
]]

local TweenService = game:GetService("TweenService")

local Kit = {}

----------------------------------------------------------------------
-- Création
----------------------------------------------------------------------

-- Instance + propriétés (Parent appliqué en dernier)
function Kit.New(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Cadre simple (sans bordure, non cliquable). props.Color / props.Alpha raccourcis.
function Kit.Box(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Active = false
	for key, value in pairs(props) do
		if key == "Color" then
			frame.BackgroundColor3 = value
		elseif key == "Alpha" then
			frame.BackgroundTransparency = value
		else
			(frame :: any)[key] = value
		end
	end
	frame.Parent = parent
	return frame
end

function Kit.Corner(parent: Instance, radius: (number | UDim)?): UICorner
	local value: any = radius or UDim.new(1, 0)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(value) == "UDim" then value else UDim.new(0, value)
	corner.Parent = parent
	return corner
end

function Kit.Stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

function Kit.Gradient(parent: Instance, color: ColorSequence?, transparency: NumberSequence?, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	if color then
		gradient.Color = color
	end
	if transparency then
		gradient.Transparency = transparency
	end
	gradient.Rotation = rotation or 0
	gradient.Parent = parent
	return gradient
end

-- NumberSequence depuis { t0, v0, t1, v1, ... } (t de 0 à 1, au plus 20 points)
function Kit.Fade(points: { number }): NumberSequence
	local keypoints = {}
	for index = 1, #points - 1, 2 do
		table.insert(keypoints, NumberSequenceKeypoint.new(math.clamp(points[index], 0, 1), math.clamp(points[index + 1], 0, 1)))
	end
	return NumberSequence.new(keypoints)
end

-- ColorSequence depuis { t0, c0, t1, c1, ... }
function Kit.Colors(points: { any }): ColorSequence
	local keypoints = {}
	for index = 1, #points - 1, 2 do
		table.insert(keypoints, ColorSequenceKeypoint.new(math.clamp(points[index] :: number, 0, 1), points[index + 1] :: Color3))
	end
	return ColorSequence.new(keypoints)
end

-- Cercle plein centré en (x, y) (repère du parent, pixels "design")
function Kit.Circle(parent: Instance, x: number, y: number, diameter: number, color: Color3, alpha: number?, z: number?): Frame
	local circle = Kit.Box(parent, {
		Name = "Circle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = color,
		BackgroundTransparency = alpha or 0,
		ZIndex = z or 1,
	})
	Kit.Corner(circle)
	return circle
end

-- Ellipse (cadre arrondi) centrée
function Kit.Ellipse(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, alpha: number?, z: number?): Frame
	local ellipse = Kit.Box(parent, {
		Name = "Ellipse",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = alpha or 0,
		ZIndex = z or 1,
	})
	Kit.Corner(ellipse)
	return ellipse
end

-- Anneau (contour seul) centré
function Kit.Ring(parent: Instance, x: number, y: number, diameter: number, color: Color3, thickness: number, alpha: number?, z: number?): (Frame, UIStroke)
	local ring = Kit.Box(parent, {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundTransparency = 1,
		ZIndex = z or 1,
	})
	Kit.Corner(ring)
	local stroke = Kit.Stroke(ring, color, thickness, alpha)
	return ring, stroke
end

-- Petite étoile en losange (carré tourné de 45°) : 1 seule instance
function Kit.Diamond(parent: Instance, x: number, y: number, size: number, color: Color3, alpha: number?, z: number?): Frame
	return Kit.Box(parent, {
		Name = "Star",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = alpha or 0,
		ZIndex = z or 1,
	})
end

-- Éclat à 4 branches (✦) : deux traits effilés (dégradé de transparence).
-- Renvoie le cadre porteur (à faire tourner / scintiller).
function Kit.Glint(parent: Instance, x: number, y: number, size: number, color: Color3, z: number?): Frame
	local holder = Kit.Box(parent, {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z or 1,
	})
	local taper = Kit.Fade({ 0, 1, 0.5, 0, 1, 1 })
	local thickness = math.max(2, math.floor(size * 0.16 + 0.5))
	local vertical = Kit.Box(holder, {
		Name = "V",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, thickness, 1, 0),
		BackgroundColor3 = color,
		ZIndex = z or 1,
	})
	Kit.Gradient(vertical, nil, taper, 90)
	local horizontal = Kit.Box(holder, {
		Name = "H",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.72, 0, 0, thickness),
		BackgroundColor3 = color,
		ZIndex = z or 1,
	})
	Kit.Gradient(horizontal, nil, taper, 0)
	return holder
end

-- Arc "◡" (œil fermé, sourire) : moitié basse d'une ellipse en contour,
-- découpée par un cadre (jamais tourné : la découpe reste valable).
function Kit.Arc(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, thickness: number, z: number?): Frame
	local clip = Kit.Box(parent, {
		Name = "Arc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w + thickness * 2 + 2, h / 2 + thickness + 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = z or 1,
	})
	local ellipse = Kit.Box(clip, {
		Name = "Curve",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		ZIndex = z or 1,
	})
	Kit.Corner(ellipse)
	Kit.Stroke(ellipse, color, thickness, 0)
	return clip
end

-- Texte simple (taille fixe, suit l'UIScale du parent)
function Kit.Text(parent: Instance, text: string, x: number, y: number, size: number, color: Color3, z: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(size * 2, size * 1.4)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color
	label.TextScaled = false
	label.ZIndex = z or 1
	label.Parent = parent
	return label
end

----------------------------------------------------------------------
-- Couleurs
----------------------------------------------------------------------

function Kit.Rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Mélange vers le blanc (t = 0..1)
function Kit.Tint(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), t)
end

-- Mélange vers le noir (t = 0..1)
function Kit.Shade(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), t)
end

-- Contour "sticker" : encre violette douce sur fond clair, lavande pâle sur fond sombre
function Kit.Ink(dark: boolean): Color3
	return if dark then Color3.fromRGB(226, 216, 255) else Color3.fromRGB(78, 62, 122)
end

----------------------------------------------------------------------
-- Suivi (niveau, thème, effets)
----------------------------------------------------------------------

function Kit.IsDark(ctx): boolean
	return ctx.State.DarkMode == true
end

-- callback(dark) quand le mode sombre change
function Kit.WatchTheme(ctx, callback: (dark: boolean) -> ())
	ctx.Connect(ctx.State.DarkModeChanged, function(enabled)
		callback(enabled == true)
	end)
end

-- callback(nouveau, ancien) quand le niveau de `upgradeId` change (état
-- serveur reçu ~5 fois/s : simple comparaison, rien d'autre)
function Kit.WatchLevel(ctx, upgradeId: string, callback: (level: number, previous: number) -> ()): number
	local current = math.max(1, ctx.GetLevel(upgradeId))
	ctx.Connect(ctx.State.Changed, function()
		local level = ctx.GetLevel(upgradeId)
		if level > 0 and level ~= current then
			local previous = current
			current = level
			callback(level, previous)
		end
	end)
	return current
end

-- Vrai si le joueur n'a pas coupé les effets (⚙️)
function Kit.Effects(ctx): boolean
	return ctx.EffectsEnabled == nil or ctx.EffectsEnabled()
end

-- Boucle d'animation (UNE par stimulus) limitée à `hz` images/s ; moitié
-- moins quand une fenêtre est ouverte par-dessus ; rien quand c'est caché.
-- fn(dt, t) : dt = temps écoulé depuis le dernier appel, t = temps total.
function Kit.Loop(ctx, hz: number, fn: (dt: number, t: number) -> ())
	local step = 1 / hz
	local pending = 0
	local clock = 0
	return ctx.OnRender(function(dt: number)
		pending += dt
		local wanted = step
		if ctx.GetVisibility() == "Dimmed" then
			wanted = step * 2
		end
		if pending < wanted then
			return
		end
		local elapsed = math.min(pending, 0.25)
		pending = 0
		if not ctx.IsVisible() then
			return
		end
		clock += elapsed
		fn(elapsed, clock)
	end)
end

----------------------------------------------------------------------
-- Objet posé par le planificateur
----------------------------------------------------------------------

export type Piece = {
	Frame: Frame,
	Scale: UIScale,
	Placed: boolean,
	Target: number, -- échelle donnée par le planificateur
}

-- Cadre transparent de taille "design" w x h, centré (AnchorPoint 0.5),
-- avec un UIScale ; caché tant qu'il n'a pas de place.
function Kit.Piece(parent: Instance, name: string, w: number, h: number): Piece
	local frame = Kit.Box(parent, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = frame
	return { Frame = frame, Scale = scale, Placed = false, Target = 1 }
end

-- Applique une place (Zones) : "pop" la 1re fois, glissement ensuite ;
-- false = pas de place (caché)
function Kit.Place(piece: Piece, placement: any)
	local frame, scale = piece.Frame, piece.Scale
	if not placement then
		frame.Visible = false
		piece.Placed = false
		return
	end
	local position = UDim2.fromOffset(placement.X, placement.Y)
	frame.Size = UDim2.fromOffset(placement.W, placement.H)
	piece.Target = placement.Scale
	if not piece.Placed then
		piece.Placed = true
		frame.Position = position
		frame.Visible = true
		scale.Scale = placement.Scale * 0.2
		TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = placement.Scale }):Play()
	else
		frame.Visible = true
		local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { Position = position }):Play()
		TweenService:Create(scale, info, { Scale = placement.Scale }):Play()
	end
end

-- Petit "boing" quand le niveau monte (l'objet grossit puis revient)
function Kit.Bump(piece: Piece)
	if not piece.Placed then
		return
	end
	local scale = piece.Scale
	local target = piece.Target
	scale.Scale = target * 1.12
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

-- Tween court (raccourci)
function Kit.Tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

return Kit
