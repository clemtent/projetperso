--[[
	DarkSkin (ModuleScript)
	Emplacement : ReplicatedStorage > Client > DarkSkin

	"Habillage sombre" automatique de l'interface claire. Toute l'interface
	est construite avec la palette claire (Theme.Colors) ; quand le mode
	sombre est actif (ClientState.DarkMode : réglage ⚙️ du joueur, thème
	sombre ou mode néon), DarkSkin repeint les éléments des cadres
	enregistrés (Register) :
	  - fonds blancs / gris clairs -> gris très foncés (Theme.DarkUI),
	    les fonds pastel -> version sombre teintée ;
	  - textes noirs / gris foncés -> blanc cassé / gris clair, SEULEMENT
	    s'ils sont posés sur un fond qui devient sombre (un texte noir sur
	    une pastille jaune reste noir) ;
	  - contours noirs -> contours gris plus doux ;
	  - les couleurs vives (boutons verts, badges rouges...) ne changent pas.
	Les couleurs d'origine sont gardées en attributs ("DS_*") et remises
	quand le mode sombre s'arrête. Les changements faits ensuite par le code
	(ex. texte qui passe au rouge) sont suivis automatiquement.

	Un élément (et tout ce qu'il contient) peut être exclu avec l'attribut
	"DarkSkinIgnore" = true (ex. miniatures des thèmes).

	API : DarkSkin.Register(root), DarkSkin.SetEnabled(bool), DarkSkin.IsEnabled(),
	      DarkSkin.MapBackground(color), DarkSkin.MapText(color) (utilitaires).
]]

local Theme = require(script.Parent.Theme)

local DarkSkin = {}

local P = Theme.DarkUI
local WHITE = Color3.new(1, 1, 1)

local enabled = false
local roots: { [Instance]: boolean } = {}
-- Objets déjà "branchés" (écouteurs de propriétés) : clés faibles
local bound: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Attributs : couleur d'origine (claire) et couleur appliquée (sombre)
local ATTR = {
	BackgroundColor3 = { "DS_Bg", "DS_BgOut" },
	TextColor3 = { "DS_Text", "DS_TextOut" },
	PlaceholderColor3 = { "DS_Ph", "DS_PhOut" },
	Color = { "DS_Stroke", "DS_StrokeOut" },
	ScrollBarImageColor3 = { "DS_Scroll", "DS_ScrollOut" },
}

----------------------------------------------------------------------
-- Couleurs
----------------------------------------------------------------------

local function luminance(color: Color3): number
	return Theme.Luminance(color)
end

local function saturation(color: Color3): number
	local _, s, _ = color:ToHSV()
	return s
end

-- Fond "clair" qui doit devenir sombre : blanc / gris clair, ou pastel très clair
local function isLightSurface(color: Color3): boolean
	local l = luminance(color)
	local s = saturation(color)
	if l >= 0.6 and s < 0.12 then
		return true
	end
	return l >= 0.86 and s < 0.4
end

-- Fond (couleur claire) -> fond sombre. Les autres couleurs ne changent pas.
function DarkSkin.MapBackground(color: Color3): Color3
	local l = luminance(color)
	local s = saturation(color)
	if isLightSurface(color) then
		-- Plus c'était clair, plus ça devient foncé (blanc -> carte sombre)
		local t = math.clamp((1 - l) / 0.4, 0, 1)
		local neutral = P.Card:Lerp(P.Raised, t)
		if s >= 0.05 then
			local h = color:ToHSV()
			local tinted = Color3.fromHSV(h, 0.45, P.TintedDark)
			return neutral:Lerp(tinted, math.clamp(s * 1.6, 0, 0.7))
		end
		return neutral
	end
	-- Gris foncés (pastilles "Dark") : un peu relevés pour rester visibles
	if s < 0.12 and l >= 0.12 and l < 0.35 then
		return color:Lerp(P.Raised, 0.35)
	end
	return color
end

-- Texte (couleur claire d'origine) posé sur un fond devenu sombre
function DarkSkin.MapText(color: Color3): Color3
	local l = luminance(color)
	local s = saturation(color)
	if s < 0.25 then
		if l < 0.25 then
			return P.Text
		elseif l < 0.55 then
			return P.TextDim
		end
		return color
	end
	-- Couleur foncée (vert foncé, bordeaux...) : éclaircie pour rester lisible
	if l < 0.4 then
		return color:Lerp(WHITE, 0.45)
	end
	return color
end

-- Contour (UIStroke en mode bordure)
local function mapStroke(color: Color3): Color3
	local l = luminance(color)
	local s = saturation(color)
	if s < 0.15 then
		if l < 0.35 then
			return P.Border
		elseif l >= 0.72 and l < 0.985 then
			return P.Divider
		end
	end
	return color
end

local function mapScroll(color: Color3): Color3
	if saturation(color) < 0.15 and luminance(color) < 0.45 then
		return P.Scroll
	end
	return color
end

----------------------------------------------------------------------
-- Analyse de l'arbre
----------------------------------------------------------------------

local function isIgnored(instance: Instance): boolean
	local node: Instance? = instance
	while node do
		if node:GetAttribute("DarkSkinIgnore") == true then
			return true
		end
		if roots[node] then
			return false
		end
		node = node.Parent
	end
	return false
end

-- Couleur de fond d'origine (claire) d'un objet
local function originalBg(guiObject: GuiObject): Color3
	local stored = guiObject:GetAttribute("DS_Bg")
	if typeof(stored) == "Color3" then
		return stored
	end
	return guiObject.BackgroundColor3
end

-- Dégradé coloré (ex. bouton aux couleurs d'un skin, carte "premium") :
-- le fond est alors donné par le dégradé, on n'y touche pas
local function hasColoredGradient(guiObject: Instance): boolean
	local gradient = guiObject:FindFirstChildOfClass("UIGradient")
	if not gradient or not gradient.Enabled then
		return false
	end
	for _, keypoint in ipairs(gradient.Color.Keypoints) do
		if saturation(keypoint.Value) > 0.2 then
			return true
		end
	end
	return false
end

-- Le fond de cet objet doit-il être assombri ?
local function shouldMapBg(guiObject: GuiObject): boolean
	return isLightSurface(originalBg(guiObject)) and not hasColoredGradient(guiObject)
end

-- Le texte de cet objet est-il posé sur un fond qui devient sombre ?
-- (premier ancêtre au fond visible ; aucun = fond du jeu, sombre aussi)
local function textOnDarkenedBg(textObject: GuiObject): boolean
	local node: Instance? = textObject
	while node and node:IsA("GuiObject") do
		local gui = node :: GuiObject
		if gui.BackgroundTransparency < 0.6 and gui.Visible then
			local bg = originalBg(gui)
			if hasColoredGradient(gui) then
				return false
			end
			if isLightSurface(bg) then
				return true
			end
			-- Fond foncé : le texte y est déjà clair (on ne touche qu'aux textes foncés)
			if luminance(bg) < 0.35 and saturation(bg) < 0.25 then
				return true
			end
			return false
		end
		if roots[node] then
			break
		end
		node = node.Parent
	end
	return true
end

----------------------------------------------------------------------
-- Application
----------------------------------------------------------------------

-- Applique (ou retire) la couleur sombre d'une propriété
local function applyProperty(instance: Instance, property: string, mapper: (Color3) -> Color3)
	local names = ATTR[property]
	local originalName, outName = names[1], names[2]
	local stored = instance:GetAttribute(originalName)
	if enabled then
		local original: Color3
		if typeof(stored) == "Color3" then
			original = stored
		else
			original = (instance :: any)[property]
			instance:SetAttribute(originalName, original)
		end
		local mapped = mapper(original)
		instance:SetAttribute(outName, mapped)
		if (instance :: any)[property] ~= mapped then
			(instance :: any)[property] = mapped
		end
	elseif typeof(stored) == "Color3" then
		instance:SetAttribute(originalName, nil)
		instance:SetAttribute(outName, nil)
		if (instance :: any)[property] ~= stored then
			(instance :: any)[property] = stored
		end
	end
end

local function identity(color: Color3): Color3
	return color
end

local function refreshText(guiObject: GuiObject)
	if not (guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox")) then
		return
	end
	local mapper = textOnDarkenedBg(guiObject) and DarkSkin.MapText or identity
	applyProperty(guiObject, "TextColor3", mapper)
	if guiObject:IsA("TextBox") then
		applyProperty(guiObject, "PlaceholderColor3", mapper)
	end
end

local function refreshBg(guiObject: GuiObject)
	local mapper = shouldMapBg(guiObject) and DarkSkin.MapBackground or function(color: Color3): Color3
		-- Gris foncé (pastille "Dark") : légèrement relevé
		if saturation(color) < 0.12 and luminance(color) >= 0.12 and luminance(color) < 0.35 then
			return DarkSkin.MapBackground(color)
		end
		return color
	end
	applyProperty(guiObject, "BackgroundColor3", mapper)
end

local function processObject(instance: Instance)
	if instance:IsA("GuiObject") then
		refreshBg(instance)
		refreshText(instance)
		if instance:IsA("ScrollingFrame") then
			applyProperty(instance, "ScrollBarImageColor3", mapScroll)
		end
	elseif instance:IsA("UIStroke") then
		-- Contour de TEXTE (Contextual sur un texte) : on n'y touche pas
		local parent = instance.Parent
		local isTextOutline = instance.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
			and parent ~= nil
			and (parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox"))
		if not isTextOutline then
			applyProperty(instance, "Color", mapStroke)
		end
	end
end

-- Suit les changements faits par le code (nouvelle couleur "claire")
local function watchProperty(instance: Instance, property: string, onChange: () -> ())
	local outName = ATTR[property][2]
	instance:GetPropertyChangedSignal(property):Connect(function()
		if not enabled then
			return
		end
		local current = (instance :: any)[property]
		if current == instance:GetAttribute(outName) then
			return -- c'est notre propre couleur
		end
		instance:SetAttribute(ATTR[property][1], current)
		onChange()
	end)
end

-- Le fond d'un objet a (peut-être) changé de nature : on le repeint, lui et ses textes
local function refreshSurface(gui: GuiObject)
	refreshBg(gui)
	refreshText(gui)
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("GuiObject") and bound[descendant] then
			refreshText(descendant)
		end
	end
end

local function bind(instance: Instance)
	if bound[instance] then
		return
	end
	bound[instance] = true
	if instance:IsA("UIGradient") then
		-- Dégradé qui devient coloré (skin du bouton, cartes "HD"...) ou neutre :
		-- le fond de son parent doit être réévalué
		local function onGradientChanged()
			local parent = instance.Parent
			if enabled and parent and parent:IsA("GuiObject") and not isIgnored(parent) then
				refreshSurface(parent)
			end
		end
		instance:GetPropertyChangedSignal("Color"):Connect(onGradientChanged)
		instance:GetPropertyChangedSignal("Enabled"):Connect(onGradientChanged)
		return
	end
	if instance:IsA("GuiObject") then
		local gui = instance :: GuiObject
		-- Le fond a changé : ses textes (lui-même et ses enfants directs) aussi
		watchProperty(gui, "BackgroundColor3", function()
			refreshSurface(gui)
		end)
		if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
			watchProperty(gui, "TextColor3", function()
				refreshText(gui)
			end)
		end
		if gui:IsA("ScrollingFrame") then
			watchProperty(gui, "ScrollBarImageColor3", function()
				applyProperty(gui, "ScrollBarImageColor3", mapScroll)
			end)
		end
	elseif instance:IsA("UIStroke") then
		watchProperty(instance, "Color", function()
			processObject(instance)
		end)
	end
end

local function handle(instance: Instance)
	local isGradient = instance:IsA("UIGradient")
	if not (instance:IsA("GuiObject") or instance:IsA("UIStroke") or isGradient) then
		return
	end
	if isIgnored(instance) then
		return
	end
	if enabled then
		bind(instance)
	end
	if isGradient then
		-- Dégradé ajouté après son parent : le fond du parent est réévalué
		local parent = instance.Parent
		if parent and parent:IsA("GuiObject") and bound[parent] then
			refreshSurface(parent)
		end
		return
	end
	processObject(instance)
end

local function processRoot(root: Instance)
	handle(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		handle(descendant)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Ajoute un cadre (et tout ce qu'il contient, même ajouté plus tard) à l'habillage
function DarkSkin.Register(root: Instance)
	if roots[root] then
		return
	end
	roots[root] = true
	root.DescendantAdded:Connect(function(descendant)
		if enabled and roots[root] then
			handle(descendant)
		end
	end)
	root.Destroying:Connect(function()
		roots[root] = nil
	end)
	if enabled then
		processRoot(root)
	end
end

-- Active / coupe le mode sombre de l'interface
function DarkSkin.SetEnabled(value: boolean)
	local newValue = value == true
	if newValue == enabled then
		return
	end
	enabled = newValue
	for root in pairs(roots) do
		if root.Parent then
			processRoot(root)
		end
	end
end

function DarkSkin.IsEnabled(): boolean
	return enabled
end

return DarkSkin
