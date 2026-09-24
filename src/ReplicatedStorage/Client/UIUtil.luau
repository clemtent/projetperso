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

-- Ajoute les animations de survol / appui à n'importe quel bouton
function UIUtil.AnimateButton(button: GuiButton, hoverScale: number?, pressScale: number?)
	local uiScale = button:FindFirstChild("AnimScale") :: UIScale?
	if not uiScale then
		uiScale = UIUtil.Create("UIScale", { Name = "AnimScale", Parent = button })
	end
	local scale = uiScale :: UIScale
	local hover = hoverScale or 1.06
	local press = pressScale or 0.92
	local hovering = false

	button.MouseEnter:Connect(function()
		hovering = true
		UIUtil.Tween(scale, 0.15, { Scale = hover }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		UIUtil.Tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIUtil.Tween(scale, 0.08, { Scale = press })
	end)
	button.MouseButton1Up:Connect(function()
		UIUtil.Tween(scale, 0.25, { Scale = hovering and hover or 1 }, Enum.EasingStyle.Back)
	end)
end

-- Bouton standard (fond coloré, léger contour, animé).
-- Garde son nom v1 "NeonButton" : le style suit simplement le thème.
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
	UIUtil.Stroke(button, props.StrokeColor or Theme.Colors.Border, props.StrokeThickness or 2, props.StrokeTransparency or 0.1)
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 26, Parent = button })
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = button,
	})
	-- Léger dégradé pour un effet "bouton"
	UIUtil.Gradient(button, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), 90)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button)
	return button
end

-- Active / grise un bouton (garde sa couleur d'origine en attribut).
-- Le bouton reste cliquable : l'appelant joue un son "erreur" + secousse
-- s'il est désactivé (meilleur retour pour le joueur).
function UIUtil.SetButtonEnabled(button: GuiButton, enabled: boolean)
	local baseColor = button:GetAttribute("BaseColor") or Theme.Colors.Pink
	button.BackgroundColor3 = enabled and baseColor or Theme.Colors.Disabled
	if button:IsA("TextButton") then
		button.TextTransparency = enabled and 0 or 0.35
	end
	button:SetAttribute("Enabled", enabled)
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

-- Ombre douce sous un cadre (un cadre noir transparent décalé, derrière)
function UIUtil.Shadow(frame: GuiObject, offset: number?, transparency: number?): Frame?
	local parent = frame.Parent
	if not parent then
		return nil
	end
	local shift = offset or 4
	local shadow = UIUtil.Create("Frame", {
		Name = frame.Name .. "Shadow",
		Size = frame.Size,
		AnchorPoint = frame.AnchorPoint,
		Position = frame.Position + UDim2.fromOffset(0, shift),
		BackgroundColor3 = Theme.Colors.Shadow,
		BackgroundTransparency = transparency or 0.85,
		BorderSizePixel = 0,
		ZIndex = math.max(0, frame.ZIndex - 1),
		LayoutOrder = frame.LayoutOrder,
		Parent = parent,
	})
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		UIUtil.Corner(shadow, corner.CornerRadius)
	end
	return shadow
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
function UIUtil.SetBadge(badge: TextLabel, value: number | string)
	if type(value) == "number" then
		badge.Visible = value > 0
		badge.Text = value > 99 and "99+" or tostring(math.floor(value))
	else
		badge.Visible = value ~= ""
		badge.Text = value
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
	UIUtil.Stroke(button, props.StrokeColor or Theme.Colors.Border, props.StrokeThickness or 1.5, props.StrokeTransparency or 0.2)
	if not round then
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0, math.floor(height * 0.45)),
			PaddingRight = UDim.new(0, math.floor(height * 0.45)),
			Parent = button,
		})
	end
	UIUtil.Gradient(button, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(222, 222, 222)), 90)
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button, 1.05, 0.93)
	return button
end

-- Bouton "basique" gris clair à contour fin (style du bouton "Clique-moi")
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
	UIUtil.Stroke(button, Theme.Colors.Border, props.StrokeThickness or 1.5, 0)
	UIUtil.Gradient(button, ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom), 90)
	button:SetAttribute("BaseColor", Color3.new(1, 1, 1))
	button:SetAttribute("Enabled", true)
	UIUtil.AnimateButton(button, 1.04, 0.94)
	return button
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

return UIUtil
