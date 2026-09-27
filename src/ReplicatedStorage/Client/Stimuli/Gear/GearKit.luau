--[[
	GearKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > GearKit

	Boîte à outils partagée des "accessoires de clic" (v9, CLICKGEAR) :
	Finger, Keyboard, Mouse, MegaFinger, CoralKeys, QuantumFinger, NeuralLink.

	  - dessin en Frames : rectangles arrondis, ovales, contours "silhouette"
	    (une forme sombre un peu plus grande DERRIÈRE la forme colorée : le
	    contour grandit / rétrécit avec les UIScale, contrairement aux UIStroke) ;
	  - le gros bouton "ClickButton" : recherche (mise en cache) et rectangle
	    sur la toile (pixels "design", taille de repos : le survol / l'écrasement
	    du bouton ne font pas bouger les accessoires) ;
	  - Animator : animations pilotées par ctx.OnRender, branché UNIQUEMENT
	    pendant qu'une animation tourne (rien ne tourne image par image au repos) ;
	  - Every : petite vie "au repos" (une animation courte toutes les X s,
	    seulement si le stimulus est visible) ;
	  - Pool : objets réutilisés (aucune instance créée à chaque clic) ;
	  - courbes d'animation (Ease) et petits calculs de géométrie.
]]

local Client = script.Parent.Parent.Parent
local Interface = require(Client.Interface)

local GearKit = {}

export type Rect = { X0: number, Y0: number, X1: number, Y1: number }

----------------------------------------------------------------------
-- Couleurs communes
----------------------------------------------------------------------

GearKit.Ink = Color3.fromRGB(46, 34, 58) -- contour "encre" des dessins
GearKit.White = Color3.new(1, 1, 1)

-- Couleur d'un arc-en-ciel (h dans [0, 1[), douce ou vive
function GearKit.Rainbow(h: number, saturation: number?, value: number?): Color3
	return Color3.fromHSV(h % 1, saturation or 0.75, value or 1)
end

-- Dégradé arc-en-ciel (7 points, sous la limite Roblox de 20)
function GearKit.RainbowSequence(offset: number?, saturation: number?): ColorSequence
	local points = {}
	local shift = offset or 0
	for index = 0, 6 do
		local t = index / 6
		table.insert(points, ColorSequenceKeypoint.new(t, Color3.fromHSV((t + shift) % 1, saturation or 0.8, 1)))
	end
	return ColorSequence.new(points)
end

----------------------------------------------------------------------
-- Courbes d'animation (t dans [0, 1])
----------------------------------------------------------------------

GearKit.Ease = {
	Linear = function(t: number): number
		return t
	end,
	OutQuad = function(t: number): number
		return 1 - (1 - t) * (1 - t)
	end,
	InQuad = function(t: number): number
		return t * t
	end,
	OutCubic = function(t: number): number
		local u = 1 - t
		return 1 - u * u * u
	end,
	InOutSine = function(t: number): number
		return -(math.cos(math.pi * t) - 1) / 2
	end,
	OutBack = function(t: number): number
		local c1 = 1.70158
		local c3 = c1 + 1
		local u = t - 1
		return 1 + c3 * u * u * u + c1 * u * u
	end,
	OutElastic = function(t: number): number
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
	end,
}

-- Bosse 0 -> 1 -> 0 (sinus)
function GearKit.Bump(t: number): number
	return math.sin(math.clamp(t, 0, 1) * math.pi)
end

function GearKit.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

----------------------------------------------------------------------
-- Dessin
----------------------------------------------------------------------

-- Frame simple. props : Name, Z, Radius (nombre, ou "round" = pilule),
-- Transparency, Rotation, Anchor (Vector2), Visible, Gradient (ColorSequence),
-- GradientRotation, GradientTransparency (NumberSequence)
function GearKit.Box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local p = props or {}
	local frame = Instance.new("Frame")
	frame.Name = p.Name or "Part"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = p.Transparency or 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	if p.Anchor then
		frame.AnchorPoint = p.Anchor
	end
	frame.ZIndex = p.Z or 1
	if p.Rotation then
		frame.Rotation = p.Rotation
	end
	if p.Visible == false then
		frame.Visible = false
	end
	local radius = p.Radius
	if radius == "round" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	elseif type(radius) == "number" and radius > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius)
		corner.Parent = frame
	end
	if p.Gradient or p.GradientTransparency then
		local gradient = Instance.new("UIGradient")
		if p.Gradient then
			gradient.Color = p.Gradient
		end
		if p.GradientTransparency then
			gradient.Transparency = p.GradientTransparency
		end
		gradient.Rotation = p.GradientRotation or 90
		gradient.Parent = frame
	end
	frame.Parent = parent
	return frame
end

-- Forme colorée + sa silhouette de contour (derrière, `outline` px plus grande).
-- Toutes les silhouettes d'un dessin ont un ZIndex plus petit que toutes les
-- formes colorées : le contour entoure l'ENSEMBLE du dessin (pas de traits
-- entre deux formes qui se touchent). Renvoie (forme, silhouette).
function GearKit.Outlined(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	props: { [string]: any }?
): (Frame, Frame)
	local p = props or {}
	local outline = p.Outline or 2.5
	local radius = p.Radius
	local lineRadius = radius
	if type(radius) == "number" then
		lineRadius = radius + outline
	end
	local line = GearKit.Box(parent, x - outline, y - outline, w + outline * 2, h + outline * 2, p.OutlineColor or GearKit.Ink, {
		Name = (p.Name or "Part") .. "Line",
		Z = p.LineZ or 1,
		Radius = lineRadius,
		Rotation = p.Rotation,
		Transparency = p.OutlineTransparency,
		Visible = p.Visible,
	})
	local fill = GearKit.Box(parent, x, y, w, h, color, {
		Name = p.Name,
		Z = p.Z or 3,
		Radius = radius,
		Rotation = p.Rotation,
		Gradient = p.Gradient,
		GradientRotation = p.GradientRotation,
		GradientTransparency = p.GradientTransparency,
		Transparency = p.Transparency,
		Visible = p.Visible,
	})
	return fill, line
end

-- Reflet blanc doux (ovale semi-transparent)
function GearKit.Shine(parent: Instance, x: number, y: number, w: number, h: number, transparency: number?, z: number?, rotation: number?): Frame
	return GearKit.Box(parent, x, y, w, h, GearKit.White, {
		Name = "Shine",
		Radius = "round",
		Transparency = transparency or 0.45,
		Z = z or 6,
		Rotation = rotation,
	})
end

-- Petite étoile à 4 branches (deux losanges) centrée en (cx, cy)
function GearKit.Star(parent: Instance, cx: number, cy: number, size: number, color: Color3, z: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Star"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(cx, cy)
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = z or 8
	for index = 0, 1 do
		local arm = GearKit.Box(holder, size / 2, size / 2, size * 0.28, size, color, {
			Name = "Arm",
			Anchor = Vector2.new(0.5, 0.5),
			Radius = "round",
			Rotation = index * 90,
			Z = z or 8,
		})
		arm.Name = "Arm" .. index
	end
	holder.Parent = parent
	return holder
end

-- Fixe l'opacité de tout un dessin : `base` garde la transparence d'origine
-- de chaque Frame (mesurée au premier appel) ; alpha = 0 (visible) .. 1 (invisible)
function GearKit.CaptureTransparency(root: Instance): { [Instance]: number }
	local base = {}
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Frame") then
			base[item] = item.BackgroundTransparency
		elseif item:IsA("TextLabel") then
			base[item] = item.TextTransparency
		end
	end
	if root:IsA("Frame") then
		base[root] = root.BackgroundTransparency
	end
	return base
end

function GearKit.ApplyFade(base: { [Instance]: number }, alpha: number)
	for item, original in pairs(base) do
		local value = original + (1 - original) * alpha
		if item:IsA("TextLabel") then
			item.TextTransparency = value
		else
			(item :: Frame).BackgroundTransparency = value
		end
	end
end

-- Cadre plein écran dans le calque Overlay pour les effets PASSAGERS d'un
-- stimulus dont le dessin permanent est dans le calque Background.
-- (à détruire dans Stop : il n'appartient pas au conteneur du stimulus)
function GearKit.FXLayer(ctx: any, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = false
	frame.ZIndex = 30
	frame.Parent = ctx.Overlay or ctx.Container
	return frame
end

----------------------------------------------------------------------
-- Toile et gros bouton
----------------------------------------------------------------------

function GearKit.Rect(x0: number, y0: number, x1: number, y1: number): Rect
	return { X0 = x0, Y0 = y0, X1 = x1, Y1 = y1 }
end

-- Rectangle d'un GuiObject sur la toile (pixels "design")
function GearKit.CanvasRect(object: GuiObject): Rect
	local root = Interface.Root
	local scale = math.max(Interface.Scale, 0.01)
	local origin = root and root.AbsolutePosition or Vector2.zero
	local position = (object.AbsolutePosition - origin) / scale
	local size = object.AbsoluteSize / scale
	return { X0 = position.X, Y0 = position.Y, X1 = position.X + size.X, Y1 = position.Y + size.Y }
end

function GearKit.CanvasSize(): Vector2
	return Interface.CanvasSize or Vector2.new(1280, 720)
end

local cachedButton: GuiObject? = nil

-- Le gros bouton "ClickButton" (colonne centrale), ou nil
function GearKit.GetButton(): GuiObject?
	local button = cachedButton
	if button and button.Parent then
		return button
	end
	cachedButton = nil
	local main = Interface.Layers and Interface.Layers.Main
	if not main then
		return nil
	end
	local found = main:FindFirstChild("ClickButton", true)
	if found and found:IsA("GuiObject") then
		cachedButton = found
		return found
	end
	return nil
end

-- Rectangle de repos du bouton sur la toile : centre réel, taille "design"
-- du support (ClickerHolder) ; nil si le bouton n'existe pas encore
function GearKit.GetButtonRect(): Rect?
	local button = GearKit.GetButton()
	if not button then
		return nil
	end
	local holder = button.Parent
	local reference: GuiObject = button
	if holder and holder:IsA("GuiObject") and holder.Name ~= "Main" then
		reference = holder
	end
	local rect = GearKit.CanvasRect(reference)
	local cx, cy = (rect.X0 + rect.X1) / 2, (rect.Y0 + rect.Y1) / 2
	local w, h = reference.Size.X.Offset, reference.Size.Y.Offset
	if w <= 0 or h <= 0 then
		w, h = rect.X1 - rect.X0, rect.Y1 - rect.Y0
	end
	if w <= 0 or h <= 0 then
		return nil
	end
	return { X0 = cx - w / 2, Y0 = cy - h / 2, X1 = cx + w / 2, Y1 = cy + h / 2 }
end

function GearKit.Center(rect: Rect): Vector2
	return Vector2.new((rect.X0 + rect.X1) / 2, (rect.Y0 + rect.Y1) / 2)
end

-- Point du bord de `rect` le plus proche de `point`
function GearKit.ClosestOnRect(rect: Rect, point: Vector2): Vector2
	local x = math.clamp(point.X, rect.X0, rect.X1)
	local y = math.clamp(point.Y, rect.Y0, rect.Y1)
	if x > rect.X0 and x < rect.X1 and y > rect.Y0 and y < rect.Y1 then
		-- point à l'intérieur : bord le plus proche
		local left, right, top, bottom = x - rect.X0, rect.X1 - x, y - rect.Y0, rect.Y1 - y
		local best = math.min(left, right, top, bottom)
		if best == left then
			x = rect.X0
		elseif best == right then
			x = rect.X1
		elseif best == top then
			y = rect.Y0
		else
			y = rect.Y1
		end
	end
	return Vector2.new(x, y)
end

-- Distance entre deux rectangles (0 s'ils se touchent / se chevauchent)
function GearKit.RectGap(a: Rect, b: Rect): number
	local dx = math.max(0, math.max(a.X0 - b.X1, b.X0 - a.X1))
	local dy = math.max(0, math.max(a.Y0 - b.Y1, b.Y0 - a.Y1))
	return math.sqrt(dx * dx + dy * dy)
end

-- Distance parcourue depuis `origin` dans la direction `dir` (unitaire)
-- avant d'entrer dans `rect` (math.huge si jamais)
function GearKit.RayToRect(origin: Vector2, dir: Vector2, rect: Rect): number
	local tMin, tMax = 0, math.huge
	for axis = 1, 2 do
		local o = axis == 1 and origin.X or origin.Y
		local d = axis == 1 and dir.X or dir.Y
		local lo = axis == 1 and rect.X0 or rect.Y0
		local hi = axis == 1 and rect.X1 or rect.Y1
		if math.abs(d) < 1e-6 then
			if o < lo or o > hi then
				return math.huge
			end
		else
			local t1, t2 = (lo - o) / d, (hi - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return math.huge
			end
		end
	end
	return tMin
end

-- Angle (degrés, sens horaire, 0 = vers le haut) pour viser `to` depuis `from`
function GearKit.AimAngle(from: Vector2, to: Vector2): number
	local d = to - from
	if d.Magnitude < 1e-3 then
		return 0
	end
	return math.deg(math.atan2(d.X, -d.Y))
end

-- Vecteur unitaire correspondant à un angle de AimAngle
function GearKit.AngleDir(angle: number): Vector2
	local r = math.rad(angle)
	return Vector2.new(math.sin(r), -math.cos(r))
end

----------------------------------------------------------------------
-- Animator : animations pilotées par ctx.OnRender, branché à la demande
----------------------------------------------------------------------

export type Animator = {
	Play: (self: Animator, key: any, duration: number, step: (t: number) -> (), done: (() -> ())?) -> (),
	Stop: (self: Animator, key: any, finish: boolean?) -> (),
	StopAll: (self: Animator) -> (),
	IsPlaying: (self: Animator, key: any) -> boolean,
	Count: (self: Animator) -> number,
}

type Track = { Key: any, T: number, D: number, Step: (t: number) -> (), Done: (() -> ())?, Dead: boolean }

function GearKit.Animator(ctx: any): Animator
	local list: { Track } = {}
	local byKey: { [any]: Track } = {}
	local connection: any = nil

	local function onRender(dt: number)
		local count = #list
		for index = 1, count do
			local track = list[index]
			if not track.Dead then
				track.T += dt
				local t = track.D > 0 and math.min(1, track.T / track.D) or 1
				track.Step(t)
				if t >= 1 then
					track.Dead = true
				end
			end
		end
		-- Nettoyage (les fins d'animation sont appelées APRÈS : elles peuvent relancer)
		local finished = nil
		local kept = {}
		for _, track in ipairs(list) do
			if track.Dead then
				if track.Key ~= nil and byKey[track.Key] == track then
					byKey[track.Key] = nil
				end
				if track.Done then
					finished = finished or {}
					table.insert(finished, track.Done)
				end
			else
				table.insert(kept, track)
			end
		end
		list = kept
		if finished then
			for _, done in ipairs(finished) do
				done()
			end
		end
		if #list == 0 and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local animator = {}

	function animator.Play(_self, key: any, duration: number, step: (t: number) -> (), done: (() -> ())?)
		local track = key ~= nil and byKey[key] or nil
		if track and not track.Dead then
			track.T = 0
			track.D = duration
			track.Step = step
			track.Done = done
		else
			track = { Key = key, T = 0, D = duration, Step = step, Done = done, Dead = false }
			table.insert(list, track :: Track)
			if key ~= nil then
				byKey[key] = track :: Track
			end
		end
		step(0)
		if not connection or not connection.Connected then
			connection = ctx.OnRender(onRender)
		end
	end

	-- Arrête une animation (finish = true : applique la fin et appelle Done)
	function animator.Stop(_self, key: any, finish: boolean?)
		local track = byKey[key]
		if not track or track.Dead then
			return
		end
		track.Dead = true
		byKey[key] = nil
		if finish then
			track.Step(1)
			if track.Done then
				track.Done()
			end
		end
	end

	function animator.StopAll(_self)
		for _, track in ipairs(list) do
			track.Dead = true
		end
		table.clear(byKey)
	end

	function animator.IsPlaying(_self, key: any): boolean
		local track = byKey[key]
		return track ~= nil and not track.Dead
	end

	function animator.Count(_self): number
		local count = 0
		for _, track in ipairs(list) do
			if not track.Dead then
				count += 1
			end
		end
		return count
	end

	return (animator :: any) :: Animator
end

----------------------------------------------------------------------
-- Vie au repos : fn() toutes les minDelay..maxDelay secondes (si visible)
----------------------------------------------------------------------

function GearKit.Every(ctx: any, minDelay: number, maxDelay: number, fn: () -> ())
	local random = ctx.Random or Random.new()
	local function schedule()
		task.delay(random:NextNumber(minDelay, maxDelay), function()
			if not ctx.IsAlive() then
				return
			end
			if ctx.IsVisible() then
				local ok, err = pcall(fn)
				if not ok then
					warn("[Gear] " .. tostring(ctx.Feature) .. " : " .. tostring(err))
				end
			end
			schedule()
		end)
	end
	schedule()
end

----------------------------------------------------------------------
-- Pool : objets réutilisés à tour de rôle (jamais créés pendant un clic)
----------------------------------------------------------------------

export type Pool<T> = { Items: { T }, Next: (self: Pool<T>) -> T }

function GearKit.Pool<T>(count: number, create: (index: number) -> T): Pool<T>
	local items = {}
	for index = 1, count do
		items[index] = create(index)
	end
	local cursor = 0
	local pool = { Items = items }
	function pool.Next(_self): T
		cursor = cursor % #items + 1
		return items[cursor]
	end
	return (pool :: any) :: Pool<T>
end

----------------------------------------------------------------------
-- Divers
----------------------------------------------------------------------

-- Vrai si le joueur n'a pas coupé les effets (particules) dans ⚙️
function GearKit.EffectsOn(ctx: any): boolean
	local data = ctx.State.Data
	return not (data and data.Settings and data.Settings.Effects == false)
end

-- Niveau d'une amélioration (0 si pas possédée)
function GearKit.Level(ctx: any, upgradeId: string): number
	local level = tonumber(ctx.GetLevel(upgradeId)) or 0
	return math.max(0, math.floor(level))
end

return GearKit
