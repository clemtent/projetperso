--[[
	GearPiece (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > GearPiece

	Un accessoire "posé" à l'écran (doigt, clavier, souris...) :
	  - cadre racine "Gear_<Id>" dans le conteneur du stimulus (Slot "Background" :
	    SOUS toute l'interface, au-dessus des fonds animés grâce au ZIndex du
	    conteneur), placé par GearLayout dans l'espace libre (attribut
	    LayoutObstacle = true : les autres stimuli peuvent l'éviter). Même si la
	    mise en page se trompait un instant, il ne recouvre JAMAIS une carte,
	    une pastille ou un bouton : il passerait dessous ;
	  - FX : cadre "Gear_<Id>FX" dans le calque Overlay pour les effets de clic
	    PASSAGERS (étoiles, "clac !", bulles, ondes...), au-dessus de l'interface ;
	  - Content : cadre de la taille "design" de l'accessoire, où le module dessine ;
	  - apparition "pop" (+ étincelles) au premier placement, glissement doux
	    quand la mise en page change, disparition si aucune place n'existe ;
	  - halo clair derrière l'accessoire en mode sombre (néon) pour qu'il reste
	    lisible sur fond noir ;
	  - suivi du niveau de l'amélioration (ctx.State.Changed) : OnLevel(niveau).
	Les animations passent par l'Animator du module (rien au repos).
]]

local GearKit = require(script.Parent.GearKit)
local GearLayout = require(script.Parent.GearLayout)

type Placement = GearLayout.Placement

export type Options = {
	Id: string,
	Size: Vector2,
	Priority: number,
	Anchor: (button: GearKit.Rect, canvas: Vector2) -> Vector2,
	MinScale: number?,
	MaxScale: number?,
	Near: number?,
	GlowColor: Color3?, -- couleur du halo (mode sombre)
	UpgradeId: string?, -- amélioration suivie pour OnLevel (par défaut Id)
	ContainerZ: number?, -- ZIndex du conteneur dans le calque Background (défaut 92)
}

local GearPiece = {}
GearPiece.__index = GearPiece

export type Piece = typeof(setmetatable(
	{} :: {
		Id: string,
		Ctx: any,
		Options: Options,
		Root: Frame,
		Content: Frame,
		FX: Frame,
		PlaceScale: UIScale,
		Glow: Frame,
		Animator: GearKit.Animator,
		Placement: Placement?,
		Level: number,
		OnPlaced: ((placement: Placement, first: boolean) -> ())?,
		OnHidden: (() -> ())?,
		OnLevel: ((level: number, previous: number) -> ())?,
		Sparkles: { Frame },
		SparkleCursor: number,
		Alive: boolean,
	},
	GearPiece
))

local SPARKLE_COLORS = {
	Color3.fromRGB(255, 214, 60),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(110, 220, 255),
	Color3.fromRGB(150, 255, 150),
}

function GearPiece.new(ctx: any, options: Options, animator: GearKit.Animator?): Piece
	local size = options.Size
	-- Au-dessus des fonds animés (thème, néon, aurores... : ZIndex < 90), sous tout le reste
	ctx.Container.ZIndex = options.ContainerZ or 92
	local fx = GearKit.FXLayer(ctx, "Gear_" .. options.Id .. "FX")
	local root = Instance.new("Frame")
	root.Name = "Gear_" .. options.Id
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.Visible = false
	root.Active = false
	root.ZIndex = 2
	root:SetAttribute("LayoutObstacle", true)
	local placeScale = Instance.new("UIScale")
	placeScale.Name = "PlaceScale"
	placeScale.Parent = root

	-- Halo (mode sombre) derrière le dessin
	local glowSize = math.max(size.X, size.Y) * 1.15
	local glow = GearKit.Box(root, size.X / 2, size.Y / 2, glowSize, glowSize, options.GlowColor or Color3.fromRGB(235, 225, 255), {
		Name = "Glow",
		Anchor = Vector2.new(0.5, 0.5),
		Radius = "round",
		Z = 1,
		Transparency = 0.2,
		Visible = false,
		GradientTransparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.86),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(0.7, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		}),
		GradientRotation = 0,
	})
	if size.X ~= size.Y then
		glow.Size = UDim2.fromOffset(size.X * 1.1, size.Y * 1.25)
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromOffset(size.X, size.Y)
	content.ZIndex = 2
	content.Parent = root

	-- Étincelles (réutilisées) : apparition, niveau supérieur
	local sparkles = {}
	for index = 1, 6 do
		local star = GearKit.Star(fx, 0, 0, 14, SPARKLE_COLORS[(index - 1) % #SPARKLE_COLORS + 1], 30)
		star.Visible = false
		table.insert(sparkles, star)
	end

	root.Parent = ctx.Container

	local self = setmetatable({
		Id = options.Id,
		Ctx = ctx,
		Options = options,
		Root = root,
		Content = content,
		FX = fx,
		PlaceScale = placeScale,
		Glow = glow,
		Animator = animator or GearKit.Animator(ctx),
		Placement = nil,
		Level = GearKit.Level(ctx, options.UpgradeId or options.Id),
		OnPlaced = nil,
		OnHidden = nil,
		OnLevel = nil,
		Sparkles = sparkles,
		SparkleCursor = 0,
		Alive = true,
	}, GearPiece)

	-- Mode sombre : halo clair
	local function applyDark(dark: boolean)
		glow.Visible = dark == true
	end
	applyDark(ctx.State.DarkMode == true)
	ctx.Connect(ctx.State.DarkModeChanged, applyDark)

	-- Niveau
	ctx.Connect(ctx.State.Changed, function()
		local level = GearKit.Level(ctx, options.UpgradeId or options.Id)
		if level ~= self.Level and level > 0 then
			local previous = self.Level
			self.Level = level
			local callback = self.OnLevel
			if callback then
				callback(level, previous)
			end
			if level > previous then
				self:Celebrate()
			end
		end
	end)

	GearLayout.Register(options.Id, {
		Size = size,
		Priority = options.Priority,
		Anchor = options.Anchor,
		MinScale = options.MinScale,
		MaxScale = options.MaxScale,
		Near = options.Near,
		OnPlace = function(placement: Placement?)
			self:_place(placement)
		end,
	})
	return self
end

-- Nouveau placement (ou nil : plus de place)
function GearPiece._place(self: Piece, placement: Placement?)
	if not self.Alive then
		return
	end
	local root = self.Root
	if not placement then
		self.Placement = nil
		root.Visible = false
		local hidden = self.OnHidden
		if hidden then
			hidden()
		end
		return
	end
	local first = self.Placement == nil or not root.Visible
	local from = root.Position
	local fromScale = self.PlaceScale.Scale
	self.Placement = placement
	root.Visible = true
	local target = UDim2.fromOffset(placement.CX, placement.CY)
	local scale = placement.Scale
	local animator = self.Animator
	if first then
		root.Position = target
		animator:Play("place", 0.5, function(t)
			self.PlaceScale.Scale = scale * math.max(0.01, GearKit.Ease.OutBack(t))
		end)
		self:Celebrate()
	else
		animator:Play("place", 0.4, function(t)
			local e = GearKit.Ease.OutCubic(t)
			root.Position = from:Lerp(target, e)
			self.PlaceScale.Scale = fromScale + (scale - fromScale) * e
		end)
	end
	local callback = self.OnPlaced
	if callback then
		callback(placement, first)
	end
end

-- Petite gerbe d'étincelles autour de l'accessoire
function GearPiece.Celebrate(self: Piece)
	local placement = self.Placement
	if not placement or not self.Alive or not GearKit.EffectsOn(self.Ctx) then
		return
	end
	local cx, cy = placement.CX, placement.CY
	local radius = math.max(placement.W, placement.H) * 0.5 + 6
	local count = #self.Sparkles
	local random = self.Ctx.Random
	for index = 1, count do
		local star = self.Sparkles[index]
		local angle = (index / count) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local dist = radius * random:NextNumber(0.75, 1.1)
		local delay = random:NextNumber(0, 0.12)
		self.Animator:Play(star, 0.65 + delay, function(t)
			local k = math.clamp((t * (0.65 + delay) - delay) / 0.65, 0, 1)
			if k <= 0 then
				star.Visible = false
				return
			end
			star.Visible = k < 1
			local out = GearKit.Ease.OutCubic(k)
			star.Position = UDim2.fromOffset(cx + math.cos(angle) * dist * (0.4 + 0.6 * out), cy + math.sin(angle) * dist * (0.4 + 0.6 * out))
			local s = 16 * GearKit.Bump(k)
			star.Size = UDim2.fromOffset(s, s)
			star.Rotation = 90 * k
		end, function()
			star.Visible = false
		end)
	end
end

-- Position (toile) d'un point du dessin (coordonnées locales de Content)
function GearPiece.ToCanvas(self: Piece, localPoint: Vector2): Vector2?
	local placement = self.Placement
	if not placement then
		return nil
	end
	local size = self.Options.Size
	local scale = placement.Scale
	return Vector2.new(placement.CX + (localPoint.X - size.X / 2) * scale, placement.CY + (localPoint.Y - size.Y / 2) * scale)
end

function GearPiece.IsShown(self: Piece): boolean
	return self.Alive and self.Placement ~= nil and self.Root.Visible
end

function GearPiece.Destroy(self: Piece)
	if not self.Alive then
		return
	end
	self.Alive = false
	GearLayout.Unregister(self.Id)
	if self.Root.Parent then
		self.Root:Destroy()
	end
	if self.FX.Parent then
		self.FX:Destroy()
	end
end

return GearPiece
