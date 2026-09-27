--[[
	UIUtil (ModuleScript)
	Emplacement : ReplicatedStorage > Client > UIUtil

	Fonctions utilitaires pour créer l'interface en code : création
	d'instances, coins arrondis, contours, dégradés, boutons animés,
	pastilles ("pills"), badges rouges, ombres...
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UIUtil = {}

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(12, 10, 28) -- "noir" légèrement bleuté (contours, ombres)

--[[
	v9 — boutons "premium" (tous les boutons partagés : NeonButton, PillButton,
	BasicButton, Tabs, CloseButton) :
	  - dégradé vertical (multiplie la couleur du fond) : haut lumineux,
	    fine "lèvre" plus sombre en bas = effet de relief ;
	  - reflet intérieur ("Gloss") : bande blanche translucide en haut ;
	  - contour dans une teinte plus sombre de la couleur du bouton (plus de
	    contour noir "basique") ;
	  - petite ombre portée quand c'est possible ;
	  - survol : le reflet s'allume ; appui : écrasement + reflet éteint ;
	  - désactivé (SetButtonEnabled) : gris, texte estompé, contour gris,
	    sans reflet.
	Les couleurs restent celles données par l'appelant (BackgroundColor3 /
	attribut "BaseColor"), le dégradé ne fait que les nuancer.
]]
UIUtil.ButtonShading = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(242, 242, 242)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(226, 226, 226)),
	ColorSequenceKeypoint.new(0.86, Color3.fromRGB(200, 200, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(188, 188, 188)),
})
-- Même relief, plus doux, pour les boutons blancs / très clairs
local LIGHT_SHADING = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(244, 245, 248)),
	ColorSequenceKeypoint.new(0.84, Color3.fromRGB(232, 234, 240)),
	ColorSequenceKeypoint.new(0.88, Color3.fromRGB(216, 219, 228)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(208, 211, 222)),
})
local GLOSS_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.55, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
local DISABLED_EDGE = Color3.fromRGB(150, 150, 160)
local LIGHT_EDGE = Color3.fromRGB(178, 183, 198)

-- Couleur très claire (blanc, pastel) ?
local function isLightColor(color: Color3): boolean
	return Theme.Luminance(color) > 0.82
end

-- Contour "premium" d'un bouton de couleur `color` : une teinte plus sombre de
-- la même couleur (gris bleuté doux pour les boutons blancs), jamais du noir pur
function UIUtil.EdgeColor(color: Color3): Color3
	if isLightColor(color) then
		return LIGHT_EDGE
	end
	return color:Lerp(INK, 0.42)
end

-- Dégradé de relief adapté à la couleur (clair / coloré)
function UIUtil.ShadingFor(color: Color3): ColorSequence
	return isLightColor(color) and LIGHT_SHADING or UIUtil.ButtonShading
end

-- Opacité du reflet selon le fond : discret sur un fond sombre (mode sombre,
-- pastilles foncées), marqué sur les couleurs vives
local function glossBaseFor(color: Color3, colored: number?): number
	local luminance = Theme.Luminance(color)
	if luminance < 0.3 then
		return 0.84
	elseif luminance > 0.82 then
		return 0.3
	end
	return colored or 0.55
end

--[[
	Reflet intérieur d'un bouton : bande blanche translucide sur le haut
	(coins arrondis, s'estompe vers le bas). Ignoré par le mode sombre
	(DarkSkin) mais il suit le fond du bouton : très discret quand le fond
	devient sombre. ZIndex 0 : sous les autres décorations du bouton. Taille
	en échelle : n'influence jamais une taille automatique (AutomaticSize).
	`transparency` = opacité du haut du reflet sur une couleur vive.
]]
function UIUtil.Gloss(button: GuiObject, transparency: number?, heightScale: number?): Frame
	local existing = button:FindFirstChild("Gloss")
	if existing and existing:IsA("Frame") then
		return existing
	end
	local base = glossBaseFor(button.BackgroundColor3, transparency)
	local gloss = UIUtil.Create("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -6, heightScale or 0.44, 0),
		Position = UDim2.fromOffset(3, 2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = base,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = button,
	})
	gloss:SetAttribute("DarkSkinIgnore", true)
	gloss:SetAttribute("GlossBase", base)
	UIUtil.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gloss })
	UIUtil.Create("UIGradient", { Rotation = 90, Transparency = GLOSS_FADE, Parent = gloss })
	-- Le fond change (mode sombre, autre couleur) : le reflet se réajuste
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local newBase = glossBaseFor(button.BackgroundColor3, transparency)
		if gloss:GetAttribute("GlossBase") ~= newBase then
			gloss:SetAttribute("GlossBase", newBase)
			gloss.BackgroundTransparency = newBase
		end
	end)
	return gloss
end

-- Crée une instance avec ses propriétés et ses enfants.
-- Le Parent est appliqué en dernier (meilleures performances).
function UIUtil.Create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIUtil.Corner(parent: Instance, radius: (number | UDim)?): UICorner
	local value = radius or 12
	return UIUtil.Create("UICorner", {
		CornerRadius = (typeof(value) == "UDim") and value or UDim.new(0, value :: number),
		Parent = parent,
	})
end

function UIUtil.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIUtil.Create("UIStroke", {
		Color = color or Theme.Colors.Border,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UIUtil.Gradient(parent: Instance, color: ColorSequence?, rotation: number?): UIGradient
	return UIUtil.Create("UIGradient", {
		Color = color or Theme.NeonGradient,
		Rotation = rotation or 0,
		Parent = parent,
	})
end

function UIUtil.Padding(parent: Instance, pixels: number): UIPadding
	local padding = UDim.new(0, pixels)
	return UIUtil.Create("UIPadding", {
		PaddingTop = padding,
		PaddingBottom = padding,
		PaddingLeft = padding,
		PaddingRight = padding,
		Parent = parent,
	})
end

-- Lance une animation (Tween) et la renvoie
function UIUtil.Tween(
	instance: Instance,
	duration: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Texte simple, transparent, avec la police du thème.
-- MaxTextSize limite la taille du texte (TextScaled) pour éviter les textes géants.
function UIUtil.Label(props: { [string]: any }): TextLabel
	local maxTextSize = props.MaxTextSize or 48
	local finalProps = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		Text = "",
	}
	for key, value in pairs(props) do
		if key ~= "MaxTextSize" then
			finalProps[key] = value
		end
	end
	local label = UIUtil.Create("TextLabel", finalProps)
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = maxTextSize, MinTextSize = 6, Parent = label })
	return label
end

-- Ajoute les animations de survol / appui à n'importe quel bouton.
-- v9 : si le bouton a un reflet ("Gloss"), il s'allume au survol et
-- s'éteint pendant l'appui (le bouton a l'air "enfoncé").
function UIUtil.AnimateButton(button: GuiButton, hoverScale: number?, pressScale: number?)
	local uiScale = button:FindFirstChild("AnimScale") :: UIScale?
	if not uiScale then
		uiScale = UIUtil.Create("UIScale", { Name = "AnimScale", Parent = button })
	end
	local scale = uiScale :: UIScale
	local hover = hoverScale or 1.06
	local press = pressScale or 0.92
	local hovering = false

	local function glow(state: string)
		local gloss = button:FindFirstChild("Gloss")
		if not gloss or not gloss:IsA("GuiObject") then
			return
		end
		local base = tonumber(gloss:GetAttribute("GlossBase")) or 0.5
		local target = base
		if state == "hover" then
			target = math.max(0, base - 0.22)
		elseif state == "press" then
			target = math.min(1, base + 0.35)
		end
		UIUtil.Tween(gloss, 0.12, { BackgroundTransparency = target })
	end

	button.MouseEnter:Connect(function()
		hovering = true
		UIUtil.Tween(scale, 0.15, { Scale = hover }, Enum.EasingStyle.Back)
		glow("hover")
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		UIUtil.Tween(scale, 0.15, { Scale = 1 })
		glow("rest")
	end)
	button.MouseButton1Down:Connect(function()
		UIUtil.Tween(scale, 0.08, { Scale = press })
		glow("press")
	end)
	button.MouseButton1Up:Connect(function()
		UIUtil.Tween(scale, 0.25, { Scale = hovering and hover or 1 }, Enum.EasingStyle.Back)
		glow(hovering and "hover" or "rest")
	end)
end

-- Habillage commun des boutons v9 : relief, contour teinté, reflet.
-- `strokeColor` nil = contour automatique (suit la couleur du bouton).
local function dressButton(button: GuiButton, color: Color3, strokeColor: Color3?, thickness: number?, transparency: number?, glossTransparency: number?)
	local stroke = UIUtil.Stroke(button, strokeColor or UIUtil.EdgeColor(color), thickness or 2, transparency or 0)
	stroke.Name = "ButtonStroke"
	button:SetAttribute("AutoStroke", strokeColor == nil)
	UIUtil.Gradient(button, UIUtil.ShadingFor(color), 90)
	UIUtil.Gloss(button, glossTransparency)
end

-- Habille un bouton construit à la main avec le style v9 (relief, contour
-- teinté, reflet) + animations survol / appui. props : StrokeColor,
-- StrokeThickness, StrokeTransparency, Gloss (opacité du reflet), Hover,
-- Press (échelles), Animate (false = pas d'animation).
function UIUtil.DressButton(button: GuiButton, color: Color3, props: { [string]: any }?)
	local options = props or {}
	dressButton(button, color, options.StrokeColor, options.StrokeThickness or 1.5, options.StrokeTransparency or 0, options.Gloss)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("Enabled", true)
	if options.Animate ~= false then
		UIUtil.AnimateButton(button, options.Hover or 1.05, options.Press or 0.93)
	end
end

-- Bouton standard (fond coloré, animé). Garde son nom v1 "NeonButton".
-- v9 : relief (dégradé + lèvre sombre en bas), reflet, contour teinté,
-- ombre portée (props.Shadow = false pour s'en passer).
function UIUtil.NeonButton(props: { [string]: any }): TextButton
	local color = props.Color or Theme.Colors.Pink
	local button = UIUtil.Create("TextButton", {
		Name = props.Name or "NeonButton",
		Size = props.Size or UDim2.fromOffset(160, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.ContrastText(color),
		TextScaled = true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	UIUtil.Corner(button, props.CornerRadius or 12)
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 26, Parent = button })
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 5),
		Parent = button,
	})
	dressButton(button, color, props.StrokeColor, props.StrokeThickness or 2, props.StrokeTransparency or 0)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button, 1.05, 0.93)
	if props.Shadow ~= false then
		UIUtil.ButtonShadow(button, 3, 0.8)
	end
	return button
end

-- Active / grise un bouton (garde sa couleur d'origine en attribut).
-- Le bouton reste cliquable : l'appelant joue un son "erreur" + secousse
-- s'il est désactivé (meilleur retour pour le joueur).
-- v9 : le contour automatique suit la couleur ("BaseColor") et le reflet
-- disparaît quand le bouton est grisé (état désactivé bien visible).
function UIUtil.SetButtonEnabled(button: GuiButton, enabled: boolean)
	local baseColor = button:GetAttribute("BaseColor") or Theme.Colors.Pink
	button.BackgroundColor3 = enabled and baseColor or Theme.Colors.Disabled
	if button:IsA("TextButton") then
		button.TextTransparency = enabled and 0 or 0.35
	end
	button:SetAttribute("Enabled", enabled)
	if button:GetAttribute("AutoStroke") == true then
		local stroke = button:FindFirstChild("ButtonStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = enabled and UIUtil.EdgeColor(baseColor) or DISABLED_EDGE
		end
	end
	local gloss = button:FindFirstChild("Gloss")
	if gloss and gloss:IsA("GuiObject") then
		gloss.Visible = enabled
	end
end

-- Petite animation "non !" (secousse) sur un élément
function UIUtil.Shake(guiObject: GuiObject)
	if guiObject:GetAttribute("Shaking") then
		return -- déjà en train de trembler : on ne décale pas la position d'origine
	end
	guiObject:SetAttribute("Shaking", true)
	-- Placé par un UIListLayout / UIGridLayout : Position est ignorée,
	-- on fait trembler la rotation à la place
	local parent = guiObject.Parent
	if parent and parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		local originRotation = guiObject.Rotation
		task.spawn(function()
			for i = 1, 6 do
				if not guiObject.Parent then
					break
				end
				guiObject.Rotation = originRotation + ((i % 2 == 0) and 4 or -4)
				task.wait(0.03)
			end
			guiObject.Rotation = originRotation
			guiObject:SetAttribute("Shaking", nil)
		end)
		return
	end
	local origin = guiObject.Position
	task.spawn(function()
		for i = 1, 6 do
			if not guiObject.Parent then
				break
			end
			local offset = (i % 2 == 0) and 6 or -6
			guiObject.Position = origin + UDim2.fromOffset(offset, 0)
			task.wait(0.03)
		end
		guiObject.Position = origin
		guiObject:SetAttribute("Shaking", nil)
	end)
end

----------------------------------------------------------------------
-- Ajouts v2
----------------------------------------------------------------------

-- Produit des UIScale des ancêtres de `instance` (sert à convertir une
-- AbsoluteSize en pixels "design" de la toile)
local function ancestorScale(instance: Instance?): number
	local scale = 1
	local node = instance
	while node do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
		node = node.Parent
	end
	return scale
end

local SHADOW_PROPS = {
	Position = true,
	Size = true,
	AnchorPoint = true,
	Rotation = true,
	Visible = true,
	ZIndex = true,
	AbsoluteSize = true,
}

-- Ombre douce sous un cadre : plusieurs couches noires très transparentes,
-- de plus en plus larges, placées DERRIÈRE le cadre (même parent, ZIndex - 1).
-- L'ombre suit automatiquement la position, la taille, la visibilité, la
-- rotation et l'UIScale du cadre, et disparaît avec lui.
-- Renvoie nil si le parent est géré par un UIListLayout / UIGridLayout
-- (l'ombre y prendrait une place) : dans ce cas, mets le cadre dans un
-- support transparent et appelle Shadow dessus.
-- (v9 : `layers` optionnel = nombre de couches ; une seule ombre par cadre)
local shadowOf: { [GuiObject]: Frame } = setmetatable({}, { __mode = "k" }) :: any

function UIUtil.Shadow(frame: GuiObject, offset: number?, transparency: number?, spread: number?, layerCount: number?): Frame?
	local parent = frame.Parent
	if not parent or parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return nil
	end
	local already = shadowOf[frame]
	if already and already.Parent then
		return already
	end
	local style = Theme.ShadowStyle
	local shift = offset or style.Offset
	local base = math.clamp(transparency or style.Transparency, 0, 1)
	local layers = math.max(1, math.floor(layerCount or style.Layers))
	local step = spread or style.Spread
	-- Transparence par couche pour qu'au centre (toutes couches empilées)
	-- l'ombre ait la transparence `base`
	local layerTransparency = base ^ (1 / layers)

	local holder = UIUtil.Create("Frame", {
		Name = frame.Name .. "Shadow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = frame.ZIndex - 1,
		LayoutOrder = frame.LayoutOrder,
		Parent = parent,
	})
	shadowOf[frame] = holder

	local corner = frame:FindFirstChildOfClass("UICorner")
	local radius = corner and corner.CornerRadius or UDim.new(0, 0)
	for index = 1, layers do
		local grow = (index - 1) * step
		local layer = UIUtil.Create("Frame", {
			Name = "Layer" .. index,
			Size = UDim2.new(1, grow * 2, 1, grow * 2),
			Position = UDim2.fromOffset(-grow, -grow),
			BackgroundColor3 = Theme.Colors.Shadow,
			BackgroundTransparency = layerTransparency,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = frame.ZIndex - 1,
			Parent = holder,
		})
		local layerRadius = radius.Scale > 0 and radius or UDim.new(0, radius.Offset + grow)
		UIUtil.Corner(layer, layerRadius)
	end

	-- UIScale du cadre (animations "pop") recopié sur l'ombre
	local holderScale: UIScale? = nil
	local function bindScale(uiScale: UIScale)
		local mirror = holderScale
		if not mirror then
			mirror = UIUtil.Create("UIScale", { Parent = holder })
			holderScale = mirror
		end
		local target = mirror :: UIScale
		target.Scale = uiScale.Scale
		uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
			if holder.Parent then
				target.Scale = uiScale.Scale
			end
		end)
	end

	local function sync()
		if not holder.Parent and not frame.Parent then
			return
		end
		holder.AnchorPoint = frame.AnchorPoint
		holder.Position = frame.Position + UDim2.fromOffset(0, shift)
		holder.Rotation = frame.Rotation
		holder.Visible = frame.Visible
		if holder.ZIndex ~= frame.ZIndex - 1 then
			holder.ZIndex = frame.ZIndex - 1
			for _, child in ipairs(holder:GetChildren()) do
				if child:IsA("GuiObject") then
					child.ZIndex = frame.ZIndex - 1
				end
			end
		end
		local automatic = frame.AutomaticSize
		if automatic ~= nil and automatic ~= Enum.AutomaticSize.None then
			-- Taille automatique : on lit la taille réelle (sans l'UIScale du cadre)
			local ownScale = frame:FindFirstChildOfClass("UIScale")
			local factor = ancestorScale(frame.Parent) * (ownScale and ownScale.Scale or 1)
			if factor > 0 then
				local size = frame.AbsoluteSize / factor
				holder.Size = UDim2.fromOffset(size.X, size.Y)
			end
		else
			holder.Size = frame.Size
		end
	end

	frame.Changed:Connect(function(property: string)
		if SHADOW_PROPS[property] then
			sync()
		end
	end)
	frame.AncestryChanged:Connect(function()
		if frame.Parent ~= holder.Parent then
			holder.Parent = frame.Parent
		end
	end)
	frame.Destroying:Connect(function()
		holder:Destroy()
	end)
	local existing = frame:FindFirstChildOfClass("UIScale")
	if existing then
		bindScale(existing)
	end
	frame.ChildAdded:Connect(function(child)
		if child:IsA("UIScale") and not holderScale then
			bindScale(child)
		end
	end)
	sync()
	return holder
end

--[[
	Ombre portée d'un BOUTON (v9), sans risque avec les listes :
	  - créée au cycle suivant (task.defer) : l'appelant a le temps de poser
	    un UIListLayout / UIGridLayout ou de déplacer le bouton ;
	  - jamais dans un parent qui a (ou reçoit ensuite) un UIListLayout /
	    UIGridLayout : elle y deviendrait un élément de la liste ;
	  - suit le bouton (position, taille réelle, visibilité, échelle) et le
	    suit s'il change de parent ; disparaît avec lui.
	Une seule couche (bon marché). Renvoie rien (l'ombre peut apparaître /
	disparaître selon le parent).
]]
function UIUtil.ButtonShadow(button: GuiObject, offset: number?, transparency: number?)
	if button:GetAttribute("HasButtonShadow") then
		return
	end
	button:SetAttribute("HasButtonShadow", true)
	local shift = offset or 3
	local alpha = transparency or 0.8
	local holder: Frame? = nil
	local watched: Instance? = nil -- parent surveillé (arrivée d'une liste)
	local layoutWatch: RBXScriptConnection? = nil
	local alive = true

	local function inLayout(parent: Instance?): boolean
		return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
	end
	local function remove()
		local current = holder
		holder = nil
		if current then
			current:Destroy()
		end
	end
	local function sync()
		local current = holder
		if not current then
			return
		end
		current.AnchorPoint = button.AnchorPoint
		current.Position = button.Position + UDim2.fromOffset(0, shift)
		current.Rotation = button.Rotation
		current.Visible = button.Visible
		current.ZIndex = button.ZIndex - 1
		local automatic = button.AutomaticSize
		if automatic ~= nil and automatic ~= Enum.AutomaticSize.None then
			-- Taille automatique : on lit la taille réelle (sans les UIScale du bouton)
			local own = 1
			for _, child in ipairs(button:GetChildren()) do
				if child:IsA("UIScale") then
					own *= child.Scale
				end
			end
			local factor = ancestorScale(button.Parent) * own
			if factor > 0 then
				local size = button.AbsoluteSize / factor
				current.Size = UDim2.fromOffset(size.X, size.Y)
			end
		else
			current.Size = button.Size
		end
		local animScale = button:FindFirstChild("AnimScale")
		local mirror = current:FindFirstChildOfClass("UIScale")
		if animScale and animScale:IsA("UIScale") and mirror then
			mirror.Scale = animScale.Scale
		end
	end
	local function place()
		if not alive then
			return
		end
		local parent = button.Parent
		-- Parent surveillé : s'il reçoit une liste, l'ombre s'en va
		if watched ~= parent then
			if layoutWatch then
				layoutWatch:Disconnect()
				layoutWatch = nil
			end
			watched = parent
			if parent then
				layoutWatch = parent.ChildAdded:Connect(function(child)
					if child:IsA("UIGridStyleLayout") then
						remove()
					end
				end)
			end
		end
		if not parent or not parent:IsA("GuiBase2d") or inLayout(parent) then
			remove()
			return
		end
		local current = holder
		if not current then
			current = UIUtil.Create("Frame", {
				Name = button.Name .. "Shadow",
				BackgroundColor3 = Theme.Colors.Shadow,
				BackgroundTransparency = alpha,
				BorderSizePixel = 0,
				Active = false,
			})
			local corner = button:FindFirstChildOfClass("UICorner")
			if corner then
				UIUtil.Create("UICorner", { CornerRadius = corner.CornerRadius, Parent = current })
			end
			UIUtil.Create("UIScale", { Parent = current })
			local created = current :: Frame
			created.Destroying:Connect(function()
				if holder == created then
					holder = nil
				end
			end)
			holder = created
		end
		sync()
		local target = current :: Frame
		if target.Parent ~= parent then
			target.Parent = parent
		end
	end

	task.defer(place)
	button.AncestryChanged:Connect(function(child: Instance)
		if child == button then
			place()
		end
	end)
	button.Changed:Connect(function(property: string)
		if SHADOW_PROPS[property] or property == "AutomaticSize" then
			sync()
		end
	end)
	local animScale = button:FindFirstChild("AnimScale")
	if animScale and animScale:IsA("UIScale") then
		animScale:GetPropertyChangedSignal("Scale"):Connect(sync)
	end
	button.Destroying:Connect(function()
		alive = false
		if layoutWatch then
			layoutWatch:Disconnect()
			layoutWatch = nil
		end
		remove()
	end)
end

-- Badge rouge rond (compteur) accroché en haut à droite d'un élément
function UIUtil.Badge(parent: GuiObject, size: number?): TextLabel
	local diameter = size or 24
	local badge = UIUtil.Create("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(diameter, diameter),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = Theme.Colors.Red,
		Font = Theme.Fonts.Number,
		Text = "",
		TextColor3 = Theme.Colors.TextLight,
		TextSize = math.floor(diameter * 0.62),
		ZIndex = parent.ZIndex + 5,
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(badge, UDim.new(1, 0))
	UIUtil.Stroke(badge, Theme.Colors.TextLight, 2)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, math.floor(diameter * 0.25)),
		PaddingRight = UDim.new(0, math.floor(diameter * 0.25)),
		Parent = badge,
	})
	return badge
end

-- Met à jour un badge : caché si 0, sinon affiche le nombre (ou un texte)
-- (petit "pop" animé quand la valeur change)
function UIUtil.SetBadge(badge: TextLabel, value: number | string)
	local wasVisible = badge.Visible
	local oldText = badge.Text
	if type(value) == "number" then
		badge.Visible = value > 0
		badge.Text = value > 99 and "99+" or tostring(math.floor(value))
	else
		badge.Visible = value ~= ""
		badge.Text = value
	end
	if badge.Visible and (not wasVisible or badge.Text ~= oldText) then
		UIUtil.Pop(badge, wasVisible and 1.35 or 0.2, 0.4)
	end
end

-- Pastille arrondie ("pill") à largeur automatique, comme
-- "🛒 Boutique" ou "⚙️". props : Text, Color, TextColor3, Height, TextSize,
-- LayoutOrder, Name, Parent, Round (true = cercle).
function UIUtil.PillButton(props: { [string]: any }): TextButton
	local color = props.Color or Theme.Colors.Dark
	local height = props.Height or 36
	local round = props.Round == true
	local button = UIUtil.Create("TextButton", {
		Name = props.Name or "Pill",
		Size = UDim2.fromOffset(round and height or 0, height),
		AutomaticSize = round and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.ContrastText(color),
		TextSize = props.TextSize or math.floor(height * 0.5),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	if not round then
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0, math.floor(height * 0.45)),
			PaddingRight = UDim.new(0, math.floor(height * 0.45)),
			Parent = button,
		})
	end
	dressButton(button, color, props.StrokeColor, props.StrokeThickness or 1.5, props.StrokeTransparency or 0)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button, 1.05, 0.93)
	if props.Shadow ~= false then
		UIUtil.ButtonShadow(button, 2, 0.82)
	end
	return button
end

-- Bouton "basique" clair (boutons neutres, ✕...) : v9 blanc nacré en relief,
-- contour gris bleuté doux, reflet et ombre portée.
function UIUtil.BasicButton(props: { [string]: any }): TextButton
	local button = UIUtil.Create("TextButton", {
		Name = props.Name or "BasicButton",
		Size = props.Size or UDim2.fromOffset(160, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Font = props.Font or Theme.Fonts.Body,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.Colors.Text,
		TextSize = props.TextSize or 22,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	UIUtil.Corner(button, props.CornerRadius or 10)
	dressButton(button, WHITE, nil, props.StrokeThickness or 1.5, 0)
	button:SetAttribute("BaseColor", Color3.new(1, 1, 1))
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button, 1.04, 0.94)
	if props.Shadow ~= false then
		UIUtil.ButtonShadow(button, 2, 0.84)
	end
	return button
end

--[[
	Bouton de fermeture "✕" rond, commun à toutes les fenêtres : disque
	blanc nacré en relief, croix foncée, qui passe au rouge au survol.
	props : Name, Size (diamètre, 40), Position, AnchorPoint, ZIndex, Parent,
	Hitbox (diamètre de la zone tactile invisible, 0 = aucune),
	OnClose (appelée par le bouton ET par sa zone tactile).
]]
function UIUtil.CloseButton(props: { [string]: any }): TextButton
	local diameter = props.Size or 40
	local button = UIUtil.BasicButton({
		Name = props.Name or "Close",
		Text = "✕",
		Font = Theme.Fonts.Title,
		TextSize = math.floor(diameter * 0.46),
		TextColor3 = Color3.fromRGB(58, 60, 76),
		Size = UDim2.fromOffset(diameter, diameter),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		CornerRadius = UDim.new(1, 0),
		ZIndex = props.ZIndex or 1,
		Shadow = props.Shadow,
		Parent = props.Parent,
	})
	-- Survol : la croix et l'anneau passent au rouge
	local hot = Color3.fromRGB(235, 64, 80)
	local stroke = button:FindFirstChild("ButtonStroke") :: UIStroke?
	button.MouseEnter:Connect(function()
		button.TextColor3 = hot
		if stroke then
			stroke.Color = hot
		end
	end)
	button.MouseLeave:Connect(function()
		button.TextColor3 = Color3.fromRGB(58, 60, 76)
		if stroke then
			stroke.Color = LIGHT_EDGE
		end
	end)
	local onClose = props.OnClose
	local hitboxSize = props.Hitbox or 0
	if hitboxSize > diameter and button.Parent then
		-- Zone tactile agrandie : bouton invisible SOUS le ✕ (même parent),
		-- centré sur lui ; le ✕ garde le survol et l'appui, la zone attrape
		-- les appuis tout autour
		local anchor = button.AnchorPoint
		local center = button.Position + UDim2.fromOffset((0.5 - anchor.X) * diameter, (0.5 - anchor.Y) * diameter)
		local hitbox = UIUtil.Create("TextButton", {
			Name = "CloseHitbox",
			Size = UDim2.fromOffset(hitboxSize, hitboxSize),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = center,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = math.max(0, button.ZIndex - 1),
			Parent = button.Parent,
		})
		local animScale = button:FindFirstChild("AnimScale") :: UIScale?
		hitbox.MouseButton1Down:Connect(function()
			if animScale then
				UIUtil.Tween(animScale, 0.08, { Scale = 0.9 })
			end
		end)
		hitbox.MouseButton1Up:Connect(function()
			if animScale then
				UIUtil.Tween(animScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
		button.Destroying:Connect(function()
			hitbox:Destroy()
		end)
		if onClose then
			hitbox.Activated:Connect(onClose)
		end
	end
	if onClose then
		button.Activated:Connect(onClose)
	end
	return button
end

----------------------------------------------------------------------
-- Ajouts v3 (finitions "pro")
----------------------------------------------------------------------

-- Petite animation "pop" (UIScale nommé PopScale, créé si besoin)
function UIUtil.Pop(guiObject: GuiObject, fromScale: number?, duration: number?)
	local scale = guiObject:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIUtil.Create("UIScale", { Name = "PopScale", Parent = guiObject })
	end
	local target = scale :: UIScale
	target.Scale = fromScale or 1.2
	UIUtil.Tween(target, duration or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Durée en secondes -> "12:34" (ou "1:02:03" au-delà d'une heure)
function UIUtil.FormatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	local h = math.floor(total / 3600)
	local m = math.floor((total % 3600) / 60)
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Étiquette arrondie non cliquable ("chip") à largeur automatique :
-- ex. "👑 VIP", "⏱️ x2 • 12:34". props : Text, Color, TextColor3, Height,
-- TextSize, LayoutOrder, Name, Parent, ZIndex, StrokeColor.
-- Renvoie le cadre ; le texte est l'enfant "Label".
function UIUtil.Chip(props: { [string]: any }): Frame
	local color = props.Color or Theme.Colors.Dark
	local height = props.Height or 24
	local chip = UIUtil.Create("Frame", {
		Name = props.Name or "Chip",
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	UIUtil.Corner(chip, UDim.new(1, 0))
	-- v9 : contour teinté (plus de contour noir) + léger relief
	if props.StrokeColor then
		UIUtil.Stroke(chip, props.StrokeColor, 1, 0.55)
	else
		UIUtil.Stroke(chip, UIUtil.EdgeColor(color), 1, 0.3)
	end
	UIUtil.Gradient(chip, isLightColor(color) and LIGHT_SHADING or ColorSequence.new(WHITE, Color3.fromRGB(222, 222, 222)), 90)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, math.floor(height * 0.45)),
		PaddingRight = UDim.new(0, math.floor(height * 0.45)),
		Parent = chip,
	})
	UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.ContrastText(color),
		TextSize = props.TextSize or math.floor(height * 0.6),
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = chip,
	})
	return chip
end

-- Titre de section (texte gras aligné à gauche + fine ligne) pour les fenêtres
function UIUtil.SectionHeader(parent: Instance, text: string, order: number?, color: Color3?): Frame
	local frame = UIUtil.Create("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	local accent = UIUtil.Create("Frame", {
		Name = "Accent",
		Size = UDim2.fromOffset(4, 18),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = color or Theme.Colors.Dark,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UIUtil.Corner(accent, 2)
	UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return frame
end

-- Déconnecte toutes les connexions d'une liste (RBXScriptConnection ou Signal) puis la vide
function UIUtil.DisconnectAll(connections: { any })
	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(connections)
end

----------------------------------------------------------------------
-- Ajouts v4 (boutiques, classement)
----------------------------------------------------------------------

export type Tabs = {
	Frame: Frame,
	Select: (id: string, silent: boolean?) -> (),
	GetSelected: () -> string,
	SetText: (id: string, text: string) -> (),
}

-- Onglets (contrôle segmenté) : fond gris clair arrondi et curseur blanc qui
-- glisse sous l'onglet choisi. props : Parent, Tabs = { { Id, Text } },
-- Color (accent), Size, Position, AnchorPoint, LayoutOrder, ZIndex,
-- TextSize, Selected (Id de départ), OnSelect(id).
function UIUtil.Tabs(props: { [string]: any }): Tabs
	local list = props.Tabs or {}
	local count = math.max(1, #list)
	local accent: Color3 = props.Color or Theme.Colors.Blue
	-- v9 : curseur de la couleur de l'accent (en relief, avec reflet), texte
	-- de l'onglet choisi en contraste ; rail légèrement creusé
	local fill = accent:Lerp(INK, 0.12)
	local selectedColor = Theme.ContrastText(fill)
	local zIndex = props.ZIndex or 1
	local frame = UIUtil.Create("Frame", {
		Name = props.Name or "Tabs",
		Size = props.Size or UDim2.new(1, 0, 0, 38),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.fromRGB(238, 240, 245),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = zIndex,
		Parent = props.Parent,
	})
	UIUtil.Corner(frame, UDim.new(1, 0))
	UIUtil.Stroke(frame, Color3.fromRGB(214, 218, 228), 1)
	-- Rail creusé : un peu plus sombre en haut
	UIUtil.Gradient(frame, ColorSequence.new(Color3.fromRGB(226, 226, 226), WHITE), 90)

	-- Ombre douce du curseur (le suit)
	local indicatorShadow = UIUtil.Create("Frame", {
		Name = "IndicatorShadow",
		Size = UDim2.new(1 / count, -6, 1, -6),
		Position = UDim2.new(0, 3, 0, 5),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = frame,
	})
	UIUtil.Corner(indicatorShadow, UDim.new(1, 0))
	local indicator = UIUtil.Create("Frame", {
		Name = "Indicator",
		Size = UDim2.new(1 / count, -6, 1, -6),
		Position = UDim2.new(0, 3, 0, 3),
		BackgroundColor3 = fill,
		ZIndex = zIndex + 1,
		Parent = frame,
	})
	UIUtil.Corner(indicator, UDim.new(1, 0))
	UIUtil.Stroke(indicator, UIUtil.EdgeColor(fill), 1.5, 0)
	UIUtil.Gradient(indicator, UIUtil.ButtonShading, 90)
	UIUtil.Gloss(indicator, 0.5)

	local buttons: { [string]: TextButton } = {}
	local indexOf: { [string]: number } = {}
	local selected = ""
	local tabs: Tabs

	local function paint()
		for id, button in pairs(buttons) do
			local isSelected = id == selected
			button.TextColor3 = isSelected and selectedColor or Theme.Colors.TextDim
			local outline = button:FindFirstChild("SelectedStroke")
			if outline and outline:IsA("UIStroke") then
				outline.Enabled = isSelected and selectedColor == Theme.Colors.TextLight
			end
		end
	end

	for index, tab in ipairs(list) do
		-- Zone cliquable un peu plus haute que l'onglet (4 px de chaque côté) :
		-- plus facile à toucher au doigt, le texte reste centré
		local button = UIUtil.Create("TextButton", {
			Name = tostring(tab.Id),
			Size = UDim2.new(1 / count, 0, 1, 8),
			Position = UDim2.new((index - 1) / count, 0, 0, -4),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = tostring(tab.Text or tab.Id),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = props.TextSize or 16,
			ZIndex = zIndex + 2,
			Parent = frame,
		})
		buttons[tab.Id] = button
		indexOf[tab.Id] = index
		-- Contour du texte de l'onglet choisi (texte blanc sur l'accent)
		local outline = UIUtil.Create("UIStroke", {
			Name = "SelectedStroke",
			Color = INK,
			Thickness = 1,
			Transparency = 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Enabled = false,
			Parent = button,
		})
		outline:SetAttribute("DarkSkinIgnore", true)
		button.MouseEnter:Connect(function()
			if tab.Id ~= selected then
				button.TextColor3 = Theme.Colors.Text
			end
		end)
		button.MouseLeave:Connect(paint)
		button.Activated:Connect(function()
			tabs.Select(tab.Id)
		end)
	end

	tabs = {
		Frame = frame,
		Select = function(id: string, silent: boolean?)
			local index = indexOf[id]
			if not index then
				return
			end
			local changed = id ~= selected
			selected = id
			UIUtil.Tween(indicator, 0.25, {
				Position = UDim2.new((index - 1) / count, 3, 0, 3),
			}, Enum.EasingStyle.Quint)
			UIUtil.Tween(indicatorShadow, 0.25, {
				Position = UDim2.new((index - 1) / count, 3, 0, 5),
			}, Enum.EasingStyle.Quint)
			paint()
			if changed and not silent and props.OnSelect then
				props.OnSelect(id)
			end
		end,
		GetSelected = function(): string
			return selected
		end,
		SetText = function(id: string, text: string)
			local button = buttons[id]
			if button then
				button.Text = text
			end
		end,
	}

	local first = props.Selected or (list[1] and list[1].Id)
	if first then
		local index = indexOf[first] or 1
		selected = first
		indicator.Position = UDim2.new((index - 1) / count, 3, 0, 3)
		indicatorShadow.Position = UDim2.new((index - 1) / count, 3, 0, 5)
		paint()
	end
	return tabs
end

-- Rayons de lumière en étoile (fines bandes qui s'estompent vers
-- l'extérieur), à placer derrière une icône. Renvoie le cadre (carré,
-- centré sur `position`) : fais-le tourner pour un effet "vitrine".
function UIUtil.Rays(parent: Instance, color: Color3, count: number?, size: number?, position: UDim2?, zIndex: number?): Frame
	local total = count or 6
	local diameter = size or 160
	local z = zIndex or 1
	local holder = UIUtil.Create("Frame", {
		Name = "Rays",
		Size = UDim2.fromOffset(diameter, diameter),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	for index = 1, total do
		local bar = UIUtil.Create("Frame", {
			Name = "Ray" .. index,
			Size = UDim2.new(0, math.max(6, math.floor(diameter * 0.09)), 1, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (index - 1) * 180 / total,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = holder,
		})
		UIUtil.Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
	end
	return holder
end

-- Dégradé vertical clair -> foncé d'une couleur (fonds de cartes "premium")
function UIUtil.SoftGradient(parent: Instance, color: Color3, rotation: number?): UIGradient
	return UIUtil.Gradient(parent, ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.55)),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(1, 1, 1), 0.08)),
	}), rotation or 90)
end

-- Avatar (tête) d'un joueur sans requête bloquante (URL rbxthumb://)
--[[
	Empêche les clics DANS une fenêtre de la fermer. Sur Roblox, une Frame
	(même Active) ne retient pas un clic destiné à un bouton placé derrière :
	cliquer sur une zone vide d'une fenêtre activait le fond sombre (qui
	ferme). On pose donc un bouton invisible sous tout le contenu de `frame` :
	il "avale" les clics qui ne touchent aucun autre bouton. Les boutons,
	champs de texte et listes défilantes de la fenêtre marchent comme avant.
	À appeler une fois sur la carte / fenêtre de chaque popup ou panneau.
]]
function UIUtil.SinkClicks(frame: GuiObject): TextButton
	local existing = frame:FindFirstChild("ClickSink")
	if existing and existing:IsA("TextButton") then
		return existing
	end
	local sink = Instance.new("TextButton")
	sink.Name = "ClickSink"
	sink.Size = UDim2.fromScale(1, 1)
	sink.BackgroundTransparency = 1
	sink.BorderSizePixel = 0
	sink.Text = ""
	sink.AutoButtonColor = false
	sink.Selectable = false
	sink.ZIndex = 0
	sink.Parent = frame
	return sink
end

function UIUtil.HeadshotUrl(userId: number, size: number?): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d", math.floor(userId), size or 48, size or 48)
end

return UIUtil
