--[[
	KeyboardArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > KeyboardArt

	Touches de clavier dessinées en Frames (partagé par Keyboard et CoralKeys) :
	  - KeyboardArt.Keys(parent, x, y, w, h, options) : grille de 4 rangées
	    (3 x 11 touches + rangée du bas avec la barre d'espace) ;
	  - KeyboardArt.Press(key, amount) : touche enfoncée (0 = relâchée, 1 = au fond) ;
	  - KeyboardArt.Pick(keys, count, random) : quelques touches au hasard (sans doublon).
	Chaque touche = 1 Frame + 1 UICorner (+ un petit reflet pour les jolies séries).
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
	Color: Color3,
	Units: number,
}

export type KeysOptions = {
	Color: ((row: number, col: number, units: number) -> Color3)?,
	Radius: number?,
	Gap: number?,
	Shine: boolean?,
	Z: number?,
}

-- Rangée du bas : largeurs en "unités" de touche (total 11)
local BOTTOM_ROW = { 1.5, 1, 1, 5, 1, 1.5 }

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
			local color = opts.Color and opts.Color(row, col, units) or Color3.fromRGB(240, 240, 246)
			local frame = GearKit.Box(parent, kx, ky, kw, keyH, color, {
				Name = "Key",
				Radius = opts.Radius or 2.5,
				Z = opts.Z or 5,
			})
			if opts.Shine then
				GearKit.Box(frame, 1.5, 1, math.max(1, kw - 5), 2, Color3.new(1, 1, 1), {
					Name = "KeyShine",
					Radius = "round",
					Transparency = 0.45,
					Z = (opts.Z or 5) + 1,
				})
			end
			table.insert(keys, {
				Frame = frame,
				Row = row,
				Col = col,
				X = kx,
				Y = ky,
				W = kw,
				H = keyH,
				Color = color,
				Units = units,
			})
			kx += kw + gap
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
