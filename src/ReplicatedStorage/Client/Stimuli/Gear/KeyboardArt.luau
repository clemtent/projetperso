--[[
	KeyboardArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > KeyboardArt

	Vraies touches QWERTY CLIQUABLES (partagé par Keyboard, CoralKeys et le
	grand clavier flottant KeyboardPanel) :
	  - KeyboardArt.Build(parent, layout, x, y, w, h, options) : dessine un
	    clavier dans le rectangle (x, y, w, h), centré, touches aussi grandes
	    que possible. Deux dispositions :
	      "Full" : Q W E R T Y U I O P back / A S D F G H J K L enter /
	               ⇧ Z X C V B N M , . ? / ctrl alt [espace] alt fn
	      "Mini" : Q W E R T Y / A S D F G H / Z X C V B N / [espace] enter
	               (petit clavier "résumé" quand la place manque)
	    Renvoie (touches, unité) : unité = taille d'une touche carrée (px).
	  - chaque touche = un TextButton (le "socle", plus sombre) + la face
	    (Frame arrondie, léger dégradé) + la légende (TextLabel) : on clique
	    n'importe où sur la touche ; Key.Button reçoit les clics ;
	  - KeyboardArt.Press(key, amount, lit?) : touche enfoncée (0..1) ;
	  - KeyboardArt.SetColor(key, couleur) : nouvelle couleur de base ;
	  - KeyboardArt.Pick(keys, count, random) : quelques touches au hasard ;
	  - KeyboardArt.CodeFor(keyCodeName) : touche du jeu pour une touche du
	    vrai clavier (Enum.KeyCode.Name -> Code : "Q", "Space", "Return"...) ;
	  - KeyboardArt.Find(keys, code) : la touche qui porte ce Code (ou nil).
	Aucune instance n'est créée pendant les clics (tout est construit une fois).
]]

local GearKit = require(script.Parent.GearKit)

local KeyboardArt = {}

export type Key = {
	Button: TextButton,
	Frame: Frame, -- face de la touche (ce qui bouge quand on appuie)
	Label: TextLabel,
	Row: number,
	Col: number,
	X: number,
	Y: number,
	W: number,
	H: number,
	Fx: number,
	Fy: number,
	Kind: string, -- "Key" | "Mod" | "Space" | "Enter" | "Back"
	Code: string,
	Legend: string,
	Color: Color3,
	Units: number,
	Depth: number, -- hauteur du socle visible sous la face (px)
}

export type KeysOptions = {
	Color: ((key: Key) -> Color3)?,
	LegendColor: ((key: Key) -> Color3)?,
	Font: Enum.Font?,
	Radius: number?, -- en fraction de l'unité (défaut 0.16)
	Gap: number?, -- en fraction de l'unité (défaut 0.1)
	Z: number?,
	Name: string?,
}

-- { légende, Code, unités, genre }
type Spec = { string | number }

local ROWS: { [string]: { Indent: { number }, Rows: { { Spec } } } } = {
	Full = {
		Indent = { 0, 0.25, 0, 0 },
		Rows = {
			{ { "Q", "Q", 1 }, { "W", "W", 1 }, { "E", "E", 1 }, { "R", "R", 1 }, { "T", "T", 1 }, { "Y", "Y", 1 },
				{ "U", "U", 1 }, { "I", "I", 1 }, { "O", "O", 1 }, { "P", "P", 1 }, { "back", "Backspace", 1.5, "Back" } },
			{ { "A", "A", 1 }, { "S", "S", 1 }, { "D", "D", 1 }, { "F", "F", 1 }, { "G", "G", 1 }, { "H", "H", 1 },
				{ "J", "J", 1 }, { "K", "K", 1 }, { "L", "L", 1 }, { "enter", "Return", 2.25, "Enter" } },
			{ { "shift", "Shift", 1.5, "Mod" }, { "Z", "Z", 1 }, { "X", "X", 1 }, { "C", "C", 1 }, { "V", "V", 1 }, { "B", "B", 1 },
				{ "N", "N", 1 }, { "M", "M", 1 }, { ",", "Comma", 1 }, { ".", "Period", 1 }, { "?", "Slash", 1 } },
			{ { "ctrl", "Ctrl", 1.5, "Mod" }, { "alt", "Alt", 1.25, "Mod" }, { "", "Space", 6, "Space" },
				{ "alt", "AltRight", 1.25, "Mod" }, { "fn", "Fn", 1.5, "Mod" } },
		},
	},
	Mini = {
		Indent = { 0, 0, 0, 0 },
		Rows = {
			{ { "Q", "Q", 1 }, { "W", "W", 1 }, { "E", "E", 1 }, { "R", "R", 1 }, { "T", "T", 1 }, { "Y", "Y", 1 } },
			{ { "A", "A", 1 }, { "S", "S", 1 }, { "D", "D", 1 }, { "F", "F", 1 }, { "G", "G", 1 }, { "H", "H", 1 } },
			{ { "Z", "Z", 1 }, { "X", "X", 1 }, { "C", "C", 1 }, { "V", "V", 1 }, { "B", "B", 1 }, { "N", "N", 1 } },
			{ { "", "Space", 4, "Space" }, { "enter", "Return", 2, "Enter" } },
		},
	},
}

-- Largeur (en unités) d'une disposition
local function layoutUnits(layout: string): (number, number)
	local def = ROWS[layout] or ROWS.Full
	local widest = 0
	for index, row in ipairs(def.Rows) do
		local total = def.Indent[index] or 0
		for _, spec in ipairs(row) do
			total += spec[3] :: number
		end
		widest = math.max(widest, total)
	end
	return widest, #def.Rows
end
KeyboardArt.LayoutUnits = layoutUnits

-- Vraies touches (Enum.KeyCode.Name) -> Code des touches du jeu
local ALIASES: { [string]: string } = {
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	RightControl = "Ctrl",
	LeftAlt = "Alt",
	RightAlt = "AltRight",
	KeypadEnter = "Return",
	Question = "Slash",
}

function KeyboardArt.CodeFor(keyCodeName: string): string?
	if #keyCodeName == 1 and string.match(keyCodeName, "^%u$") then
		return keyCodeName
	end
	local alias = ALIASES[keyCodeName]
	if alias then
		return alias
	end
	if keyCodeName == "Space" or keyCodeName == "Return" or keyCodeName == "Backspace" or keyCodeName == "Comma"
		or keyCodeName == "Period" or keyCodeName == "Slash" then
		return keyCodeName
	end
	return nil
end

function KeyboardArt.Find(keys: { Key }, code: string): Key?
	for _, key in ipairs(keys) do
		if key.Code == code then
			return key
		end
	end
	return nil
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.fromRGB(40, 34, 60), amount)
end

-- Encre lisible sur la couleur de la touche
local function inkFor(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if luminance < 0.5 then
		return Color3.fromRGB(250, 248, 255)
	end
	return Color3.fromRGB(52, 44, 72)
end
KeyboardArt.InkFor = inkFor

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Dessine un clavier ; renvoie (touches, unité)
function KeyboardArt.Build(parent: Instance, layout: string, x: number, y: number, w: number, h: number, options: KeysOptions?): ({ Key }, number)
	local opts = options or {}
	local def = ROWS[layout] or ROWS.Full
	local unitsW, rows = layoutUnits(layout)
	local gapK = opts.Gap or 0.1
	-- Unité (touche + écart) la plus grande qui tient dans w x h
	local step = math.min(w / unitsW, h / rows)
	local gap = math.max(1, step * gapK)
	local unit = step - gap
	local totalW, totalH = step * unitsW - gap, step * rows - gap
	local x0 = x + (w - totalW) / 2
	local y0 = y + (h - totalH) / 2
	local radius = math.max(2, unit * (opts.Radius or 0.16))
	local depth = math.max(1.5, unit * 0.13)
	local z = opts.Z or 10
	local font = opts.Font or Enum.Font.BuilderSansBold
	local keys: { Key } = {}
	for rowIndex, row in ipairs(def.Rows) do
		local kx = x0 + (def.Indent[rowIndex] or 0) * step
		local ky = y0 + (rowIndex - 1) * step
		for colIndex, spec in ipairs(row) do
			local units = spec[3] :: number
			local kw = step * units - gap
			local legend = spec[1] :: string
			local key: Key = {
				Button = (nil :: any) :: TextButton,
				Frame = (nil :: any) :: Frame,
				Label = (nil :: any) :: TextLabel,
				Row = rowIndex,
				Col = colIndex,
				X = kx,
				Y = ky,
				W = kw,
				H = unit,
				Fx = (kx + kw / 2 - x0) / math.max(1, totalW),
				Fy = (ky + unit / 2 - y0) / math.max(1, totalH),
				Kind = (spec[4] :: string?) or "Key",
				Code = spec[2] :: string,
				Legend = legend,
				Color = Color3.new(1, 1, 1),
				Units = units,
				Depth = depth,
			}
			local color = opts.Color and opts.Color(key) or Color3.fromRGB(248, 248, 252)
			key.Color = color

			-- Socle (reçoit les clics)
			local button = Instance.new("TextButton")
			button.Name = (opts.Name or "Key_") .. key.Code
			button.AutoButtonColor = false
			button.Selectable = false
			button.Text = ""
			button.BorderSizePixel = 0
			button.BackgroundColor3 = darker(color, 0.42)
			button.Position = UDim2.fromOffset(kx, ky)
			button.Size = UDim2.fromOffset(kw, unit)
			button.ZIndex = z
			corner(button, radius)

			-- Face (bouge quand on appuie)
			local face = Instance.new("Frame")
			face.Name = "Face"
			face.BorderSizePixel = 0
			face.BackgroundColor3 = color
			face.Position = UDim2.fromOffset(0, 0)
			face.Size = UDim2.new(1, 0, 1, -depth)
			face.ZIndex = z + 1
			corner(face, radius)
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(222, 222, 234))
			gradient.Parent = face
			face.Parent = button

			-- Légende
			local label = Instance.new("TextLabel")
			label.Name = "Legend"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = font
			label.Text = legend
			local small = #legend > 1
			label.TextSize = math.max(6, math.floor(unit * (small and 0.36 or 0.56)))
			label.TextColor3 = opts.LegendColor and opts.LegendColor(key) or inkFor(color)
			label.ZIndex = z + 2
			label.Parent = face

			button.Parent = parent
			key.Button = button
			key.Frame = face
			key.Label = label
			table.insert(keys, key)
			kx += step * units
		end
	end
	return keys, unit
end

-- Touche enfoncée : la face descend sur son socle et s'assombrit (ou
-- s'illumine : `lit`). amount = 0 (relâchée) .. 1 (au fond)
function KeyboardArt.Press(key: Key, amount: number, lit: Color3?)
	local face = key.Frame
	face.Position = UDim2.fromOffset(0, key.Depth * amount)
	if lit then
		face.BackgroundColor3 = key.Color:Lerp(lit, 0.75 * amount)
	else
		face.BackgroundColor3 = key.Color:Lerp(Color3.fromRGB(60, 60, 80), 0.3 * amount)
	end
end

-- Change la couleur "de base" d'une touche (lumières RGB...)
function KeyboardArt.SetColor(key: Key, color: Color3)
	key.Color = color
	key.Frame.BackgroundColor3 = color
	key.Button.BackgroundColor3 = darker(color, 0.42)
end

-- `count` touches différentes au hasard (hors barre d'espace si possible)
function KeyboardArt.Pick(keys: { Key }, count: number, random: Random): { Key }
	local picked: { Key } = {}
	local used: { [number]: boolean } = {}
	local tries = 0
	while #picked < count and tries < 40 and #keys > 0 do
		tries += 1
		local index = random:NextInteger(1, #keys)
		if not used[index] and keys[index].Units < 4 then
			used[index] = true
			table.insert(picked, keys[index])
		end
	end
	return picked
end

-- Petite étoile dorée sur une touche (touche "artisanale")
function KeyboardArt.Artisan(key: Key, z: number)
	KeyboardArt.SetColor(key, Color3.fromRGB(255, 200, 60))
	key.Label.Text = ""
	GearKit.Star(key.Frame, key.W / 2, (key.H - key.Depth) / 2, math.min(key.W, key.H) * 0.62, Color3.new(1, 1, 1), z)
end

return KeyboardArt
