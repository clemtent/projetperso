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

-- Résolution de référence : toute l'interface est pensée en 1280x720,
-- puis mise à l'échelle automatiquement (UIScale) selon l'écran.
Theme.DesignResolution = Vector2.new(1280, 720)
Theme.MinScale = 0.45
Theme.MaxScale = 1.6

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
