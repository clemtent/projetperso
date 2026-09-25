--[[
	Theme (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Theme

	Direction artistique : "basique" et clair (fond blanc → gris clair,
	bouton gris, texte noir, cartes blanches à bord noir, pastilles rouges).
	L'écran se remplit ensuite de "stimuli" colorés, et le mode néon passe
	l'interface en sombre (voir Theme.DarkColors).
	Change les couleurs et polices ici pour modifier TOUTE l'interface.
]]

local Theme = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

Theme.Colors = {
	-- Fond
	Background = hex("#FFFFFF"),
	BackgroundBottom = hex("#E2E2E2"),

	-- Texte
	Text = hex("#111111"),
	TextDim = hex("#5A5A5A"),
	TextLight = hex("#FFFFFF"),
	TextDark = hex("#111111"),

	-- Contours, boutons, cartes
	Border = hex("#1E1E1E"),
	Button = hex("#F4F4F4"),
	ButtonBottom = hex("#D5D5D5"),
	Card = hex("#FFFFFF"),
	CardBorder = hex("#1A1A1A"),
	Disabled = hex("#B8B8B8"),
	Shadow = hex("#000000"),
	Panel = hex("#FFFFFF"),
	PanelLight = hex("#F2F2F2"),

	-- Couleurs vives
	Red = hex("#E3262B"),
	Green = hex("#3DDC3D"),
	Purple = hex("#8B32E0"),
	Blue = hex("#1E88E5"),
	Orange = hex("#FF8A1A"),
	Yellow = hex("#FFD21F"),
	Pink = hex("#FF3E8A"),
	Cyan = hex("#00C2E0"),
	Gold = hex("#FFC21A"),
	Dark = hex("#2A2A2A"),
}

-- Ajouts v3 (boutique Robux, VIP, boost, ombres)
Theme.Colors.Robux = hex("#00A86B") -- vert "achat"
Theme.Colors.RobuxDark = hex("#007A4D")
Theme.Colors.Premium = hex("#FFB800") -- VIP / Premium
Theme.Colors.Boost = hex("#FF6A00")
Theme.Colors.Divider = hex("#E6E6E6")
Theme.Colors.Surface = hex("#F7F7F8") -- fond des sections dans les fenêtres

-- Anciennes clés (v1) gardées pour compatibilité
Theme.Colors.BackgroundTop = Theme.Colors.Background
Theme.Colors.BackgroundMid = Theme.Colors.PanelLight

-- Couleurs utilisées quand le mode sombre (néon) est actif
Theme.DarkColors = {
	Text = hex("#FFFFFF"),
	TextDim = hex("#C9C3E6"),
	Card = hex("#16121F"),
	CardTransparency = 0.25,
	CardBorder = hex("#FFFFFF"),
	Background = hex("#0B0912"),
}

Theme.Fonts = {
	Title = Enum.Font.BuilderSansBold, -- titres
	Body = Enum.Font.BuilderSansMedium, -- textes
	Number = Enum.Font.BuilderSansBold, -- compteurs
	Mono = Enum.Font.RobotoMono, -- chiffres alignés (bourse...)
}

-- Hiérarchie typographique (tailles en pixels "design")
Theme.TextSize = {
	Display = 44, -- compteur principal
	Title = 26, -- titres de fenêtres
	Heading = 19, -- titres de sections / cartes
	Body = 16, -- textes courants
	Caption = 13, -- petites mentions
}

-- Espacements réguliers (multiples de 4)
Theme.Spacing = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
}

-- Rayons des coins
Theme.Radius = {
	S = 8,
	M = 12,
	L = 18,
	XL = 22,
}

-- Ombres douces (voir UIUtil.Shadow)
Theme.ShadowStyle = {
	Offset = 4, -- décalage vers le bas
	Transparency = 0.86, -- couche la plus sombre
	Layers = 3, -- nombre de couches (plus = plus doux)
	Spread = 3, -- élargissement par couche
}

-- Palette du mode sombre choisi par le joueur (⚙️ "Mode sombre") : appliquée
-- automatiquement à toute l'interface par DarkSkin (fenêtres, bandeaux,
-- colonne centrale, écran de chargement). Les couleurs vives ne changent pas.
Theme.DarkUI = {
	Background = hex("#121218"), -- fond du jeu (thème Classique)
	BackgroundBottom = hex("#1C1C27"),
	Card = hex("#1E1E28"), -- fenêtres, cartes (ancien blanc)
	Raised = hex("#464656"), -- gris clairs -> surfaces un peu plus claires
	Text = hex("#EDEDF2"),
	TextDim = hex("#A6A6B8"),
	Border = hex("#4A4A5E"), -- contours plus doux que le noir
	Divider = hex("#34343F"),
	Scroll = hex("#6A6A80"),
	TintedDark = 0.32, -- luminosité des fonds pastel une fois assombris
}

-- Résolution de référence : toute l'interface est pensée en 1280x720,
-- puis mise à l'échelle automatiquement (UIScale) selon l'écran.
Theme.DesignResolution = Vector2.new(1280, 720)
Theme.MinScale = 0.45
Theme.MaxScale = 1.6

-- Toile "design" selon l'appareil (voir Interface.Device) : plus petite sur
-- téléphone / tablette, donc tout y est affiché plus gros et lisible.
Theme.DeviceResolutions = {
	Phone = Vector2.new(960, 540),
	Tablet = Vector2.new(1120, 630),
	Desktop = Vector2.new(1280, 720),
}
-- Taille minimale (pixels "design") des zones tactiles sur téléphone / tablette
Theme.TouchTarget = 44

-- Dégradé néon (rose -> violet -> cyan), utilisé par le mode néon
Theme.NeonGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 46, 136)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(157, 78, 221)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 240, 255)),
})

-- Luminosité perçue (0 = noir, 1 = blanc) : sert à choisir un texte lisible
function Theme.Luminance(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- Texte lisible (noir ou blanc) sur un fond de couleur `color`
function Theme.ContrastText(color: Color3): Color3
	return Theme.Luminance(color) > 0.62 and Theme.Colors.TextDark or Theme.Colors.TextLight
end

return Theme
