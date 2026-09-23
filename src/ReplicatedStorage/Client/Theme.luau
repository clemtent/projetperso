--[[
	Theme (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Theme

	Direction artistique : néon / cyberpunk / arcade.
	Change les couleurs et polices ici pour modifier TOUTE l'interface.
]]

local Theme = {}

Theme.Colors = {
	-- Fond
	BackgroundTop = Color3.fromRGB(26, 6, 51),
	BackgroundMid = Color3.fromRGB(58, 12, 94),
	BackgroundBottom = Color3.fromRGB(6, 22, 56),

	-- Néons
	Purple = Color3.fromRGB(157, 78, 221),
	Pink = Color3.fromRGB(255, 46, 136),
	Cyan = Color3.fromRGB(0, 240, 255),
	Yellow = Color3.fromRGB(255, 229, 59),
	Green = Color3.fromRGB(57, 255, 20),
	Orange = Color3.fromRGB(255, 140, 40),
	Red = Color3.fromRGB(255, 60, 80),
	Gold = Color3.fromRGB(255, 200, 40),

	-- Panneaux
	Panel = Color3.fromRGB(20, 10, 46),
	PanelLight = Color3.fromRGB(38, 20, 78),
	Card = Color3.fromRGB(30, 16, 62),
	Disabled = Color3.fromRGB(70, 64, 90),

	-- Texte
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 175, 225),
	TextDark = Color3.fromRGB(20, 10, 40),
}

Theme.Fonts = {
	Title = Enum.Font.Michroma, -- titres (style futuriste)
	Body = Enum.Font.GothamBold, -- textes
	Number = Enum.Font.GothamBlack, -- compteurs
}

-- Résolution de référence : toute l'interface est pensée en 1280x720,
-- puis mise à l'échelle automatiquement (UIScale) selon l'écran.
Theme.DesignResolution = Vector2.new(1280, 720)
Theme.MinScale = 0.45
Theme.MaxScale = 1.6

-- Dégradé néon principal (rose -> violet -> cyan)
Theme.NeonGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Colors.Pink),
	ColorSequenceKeypoint.new(0.5, Theme.Colors.Purple),
	ColorSequenceKeypoint.new(1, Theme.Colors.Cyan),
})

return Theme
