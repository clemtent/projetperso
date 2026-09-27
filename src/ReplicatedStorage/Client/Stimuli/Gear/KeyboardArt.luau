--[[
	KeyboardArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > KeyboardArt

	Touches de clavier dessinées en Frames (partagé par Keyboard et CoralKeys) :
	  - KeyboardArt.Keys(parent, x, y, w, h, options) : clavier (4 rangées :
	    3 x 11 touches + rangée du bas avec la barre d'espace) ;
	  - KeyboardArt.Numpad(parent, x, y, w, h, options) : pavé numérique compact
	    (forme de rechange en hauteur, pour les couloirs étroits) ;
	  - KeyboardArt.Press(key, amount) : touche enfoncée (0 = relâchée, 1 = au fond) ;
	  - KeyboardArt.Pick(keys, count, random) : quelques touches au hasard (sans doublon).
	Chaque touche = 1 Frame + 1 UICorner (+ un petit reflet pour les jolies séries).
	Kind = "Esc" | "Enter" | "Space" | "Key" ; Fx / Fy = position relative (0..1)
	(pour les couleurs arc-en-ciel et les vagues de lumière).
]]

local GearKit = require(script.Parent.GearKit)

local KeyboardArt = {}

export type Key = {
	Frame: Frame,
	Row: number,
	Col: number,
	X: number,
	Y: number,
	W: number,
	H: number,
	Fx: number,
	Fy: number,
	Kind: string,
	Color: Color3,
	Units: number,
}

export type KeysOptions = {
	Color: ((key: Key) -> Color3)?,
	Radius: number?,
	Gap: number?,
	Shine: boolean?,
	Z: number?,
}

-- Rangée du bas : largeurs en "unités" de touche (total 11)
local BOTTOM_ROW = { 1.5, 1, 1, 5, 1, 1.5 }

local function addKey(keys: { Key }, parent: Instance, x0: number, y0: number, w: number, h: number, key: Key, opts: KeysOptions)
	key.Fx = (key.X + key.W / 2 - x0) / math.max(1, w)
	key.Fy = (key.Y + key.H / 2 - y0) / math.max(1, h)
	local color = opts.Color and opts.Color(key) or Color3.fromRGB(240, 240, 246)
	key.Color = color
	local frame = GearKit.Box(parent, key.X, key.Y, key.W, key.H, color, {
		Name = "Key",
		Radius = opts.Radius or 2.5,
		Z = opts.Z or 5,
	})
	if opts.Shine then
		GearKit.Box(frame, 1.5, 1, math.max(1, key.W - 5), 2, Color3.new(1, 1, 1), {
			Name = "KeyShine",
			Radius = "round",
			Transparency = 0.45,
			Z = (opts.Z or 5) + 1,
		})
	end
	key.Frame = frame
	table.insert(keys, key)
end

local function newKey(row: number, col: number, x: number, y: number, w: number, h: number, units: number, kind: string): Key
	return {
		Frame = (nil :: any) :: Frame,
		Row = row,
		Col = col,
		X = x,
		Y = y,
		W = w,
		H = h,
		Fx = 0,
		Fy = 0,
		Kind = kind,
		Color = Color3.new(1, 1, 1),
		Units = units,
	}
end

function KeyboardArt.Keys(parent: Instance, x: number, y: number, w: number, h: number, options: KeysOptions?): { Key }
	local opts = options or {}
	local gap = opts.Gap or 2
	local rows = 4
	local unitW = (w - gap * 10) / 11
	local keyH = (h - gap * (rows - 1)) / rows
	local keys: { Key } = {}
	for row = 1, rows do
		local ky = y + (row - 1) * (keyH + gap)
		local widths = row == rows and BOTTOM_ROW or nil
		local count = widths and #widths or 11
		local kx = x
		for col = 1, count do
			local units = widths and widths[col] or 1
			local kw = unitW * units + gap * (units - 1)
			local kind = "Key"
			if row == 1 and col == 1 then
				kind = "Esc"
			elseif col == 11 and (row == 2 or row == 3) then
				kind = "Enter"
			elseif row == rows and units >= 4 then
				kind = "Space"
			end
			addKey(keys, parent, x, y, w, h, newKey(row, col, kx, ky, kw, keyH, units, kind), opts)
			kx += kw + gap
		end
	end
	return keys
end

-- Pavé numérique : 4 colonnes x 5 rangées, "Entrée" haute (2 rangées) en
-- bas à droite, "0" large (2 colonnes) en bas à gauche
function KeyboardArt.Numpad(parent: Instance, x: number, y: number, w: number, h: number, options: KeysOptions?): { Key }
	local opts = options or {}
	local gap = opts.Gap or 2
	local cols, rows = 4, 5
	local kw = (w - gap * (cols - 1)) / cols
	local kh = (h - gap * (rows - 1)) / rows
	local keys: { Key } = {}
	for row = 1, rows do
		for col = 1, cols do
			local kx = x + (col - 1) * (kw + gap)
			local ky = y + (row - 1) * (kh + gap)
			local width, height, units, kind = kw, kh, 1, "Key"
			local skip = false
			if col == 4 and row == 4 then
				height = kh * 2 + gap -- Entrée
				units = 2
				kind = "Enter"
			elseif col == 4 and row == 5 then
				skip = true
			elseif row == 5 and col == 1 then
				width = kw * 2 + gap -- 0
				units = 2
				kind = "Space"
			elseif row == 5 and col == 2 then
				skip = true
			elseif row == 1 and col == 1 then
				kind = "Esc"
			end
			if not skip then
				addKey(keys, parent, x, y, w, h, newKey(row, col, kx, ky, width, height, units, kind), opts)
			end
		end
	end
	return keys
end

-- Touche enfoncée : descend un peu et s'assombrit (ou s'illumine : `lit`)
function KeyboardArt.Press(key: Key, amount: number, lit: Color3?)
	local frame = key.Frame
	frame.Position = UDim2.fromOffset(key.X, key.Y + 1.6 * amount)
	if lit then
		frame.BackgroundColor3 = key.Color:Lerp(lit, 0.75 * amount)
	else
		frame.BackgroundColor3 = key.Color:Lerp(Color3.fromRGB(60, 60, 80), 0.32 * amount)
	end
end

-- Change la couleur "de base" d'une touche (lumières RGB...)
function KeyboardArt.SetColor(key: Key, color: Color3)
	key.Color = color
	key.Frame.BackgroundColor3 = color
end

-- `count` touches différentes au hasard (hors barre d'espace si possible)
function KeyboardArt.Pick(keys: { Key }, count: number, random: Random): { Key }
	local picked: { Key } = {}
	local used: { [number]: boolean } = {}
	local tries = 0
	while #picked < count and tries < 40 do
		tries += 1
		local index = random:NextInteger(1, #keys)
		if not used[index] and keys[index].Units < 4 then
			used[index] = true
			table.insert(picked, keys[index])
		end
	end
	return picked
end

return KeyboardArt
