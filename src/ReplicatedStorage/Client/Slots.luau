--[[
	Slots (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Slots

	Emplacements nommés de l'écran (toile de 1280x720 pixels "design") où
	les stimuli (Client > Stimuli) viennent se placer.

	Ancrage horizontal :
	  "L" = décalage depuis le bord gauche, "R" = depuis le bord droit,
	  "C" = centré (X = décalage du CENTRE du slot par rapport au centre),
	  "T" = toute la largeur.
	Verticalement, les slots de la moitié haute sont accrochés en haut et
	ceux de la moitié basse en bas : sur un écran plus haut que 16:9
	(tablette), l'espace libre se retrouve au milieu.

	Spéciaux : "Overlay" (plein écran, calque Overlay) et "Background"
	(plein écran, calque Background, sous tout le reste).

	La colonne centrale (bouton, compteur, améliorations) occupe
	x ∈ [centre-300, centre+300], y ∈ [30, 425] : elle doit rester lisible.

	v5 (téléphones / tablettes) : la toile y est plus petite (tout est plus
	gros), donc chaque slot reçoit une échelle (UIScale "SlotScale" sur son
	cadre, voir Slots.GetScale) pour ne pas recouvrir la colonne centrale.
	Le cadre garde sa taille "design" (288x190...) : les stimuli se
	construisent comme avant, tout est simplement réduit. Sur PC l'échelle
	vaut 1 et les positions sont exactement celles du tableau.
	Slots.Changed est déclenché quand la mise en page change (rotation...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local Slots = {}

Slots.DesignHeight = 720
Slots.Changed = Signal.new() -- () : échelles / positions recalculées

-- { Anchor, X, Y, W, H } (H = 0 et Anchor "T" : toute la largeur)
Slots.Definitions = {
	Ticker = { Anchor = "T", X = 0, Y = 0, W = 0, H = 30 },
	L1 = { Anchor = "L", X = 16, Y = 40, W = 288, H = 190 },
	R1 = { Anchor = "R", X = 16, Y = 40, W = 288, H = 190 },
	L2 = { Anchor = "L", X = 16, Y = 240, W = 288, H = 180 },
	R2 = { Anchor = "R", X = 16, Y = 240, W = 288, H = 180 },
	CL = { Anchor = "C", X = -250, Y = 40, W = 170, H = 170 },
	CR = { Anchor = "C", X = 250, Y = 40, W = 170, H = 170 },
	L3 = { Anchor = "L", X = 16, Y = 436, W = 384, H = 268 },
	C3 = { Anchor = "C", X = 0, Y = 436, W = 384, H = 268 },
	R3 = { Anchor = "R", X = 16, Y = 436, W = 384, H = 268 },
}

local TICKER_HEIGHT = 30
-- Bas de la colonne centrale (pixels "design") sur téléphone / tablette
local PHONE_COLUMN_BOTTOM = 388
local TABLET_COLUMN_BOTTOM = 456
local bound = false

-- Mise en page actuelle : { Device, Canvas, Scales = { [slot] = number }, CenterOffset = number }
local layout = {
	Device = "Desktop",
	Canvas = Vector2.new(1280, 720),
	Scales = {} :: { [string]: number },
	CenterOffset = 250, -- décalage horizontal de CL / CR (centre du slot)
}

-- Cadres créés par Slots.Create (pour les replacer si l'écran change)
local frames: { [Frame]: string } = setmetatable({}, { __mode = "k" }) :: any

-- Vrai si `name` est un emplacement connu (y compris Overlay / Background)
function Slots.IsValid(name: string): boolean
	return Slots.Definitions[name] ~= nil or name == "Overlay" or name == "Background"
end

-- Nom du calque de l'Interface où doit aller ce slot
function Slots.GetLayerName(name: string): string
	if name == "Overlay" then
		return "Overlay"
	elseif name == "Background" then
		return "Background"
	end
	return "Slots"
end

-- Échelle d'un slot (1 sur PC ; plus petite sur téléphone / tablette)
function Slots.GetScale(name: string): number
	return layout.Scales[name] or 1
end

-- Profil actuel ("Phone" | "Tablet" | "Desktop")
function Slots.GetDevice(): string
	return layout.Device
end

-- Calcule les échelles selon l'appareil et la taille de la toile (pixels "design").
-- Téléphone : la colonne centrale occupe le centre (voir GetCenterClearWidth)
-- et descend jusqu'à y ≈ 388 (toile de 540 de haut) ; tablette : ±340 et y ≈ 456.
local function computeLayout(device: string, canvas: Vector2)
	local scales: { [string]: number } = {}
	local centerOffset = 250
	local W, H = canvas.X, canvas.Y
	if device == "Phone" then
		-- Côtés : 0.75 (L1/L2/R1/R2), un peu moins si l'écran est étroit
		local side = math.clamp((W / 2 - 250) / 304, 0.6, 0.75)
		-- Rangée du bas : sous la colonne (qui finit vers y = 380)
		local bottomRoom = math.max(120, H - 12 - PHONE_COLUMN_BOTTOM)
		local center = math.clamp(bottomRoom / 268, 0.45, 0.62)
		local low = math.clamp(math.min(bottomRoom / 268 + 0.04, (W / 2 - 12 - 192 * center) / 400), 0.45, 0.66)
		local corner = math.clamp(side * 0.9, 0.55, 0.68)
		for _, name in ipairs({ "L1", "R1", "L2", "R2" }) do
			scales[name] = side
		end
		scales.L3, scales.R3, scales.C3 = low, low, center
		scales.CL, scales.CR = corner, corner
		-- CL / CR : entre les slots de côté et le bouton
		local sideEdge = (16 + 288) * side
		centerOffset = math.clamp(W / 2 - sideEdge - 8 - 85 * corner, 180, 250)
	elseif device == "Tablet" then
		local side = math.clamp((W / 2 - 340 - 8) / 304, 0.6, 1)
		local bottom = math.clamp(math.min((W / 2 - 8) / 592, (H - 16 - TABLET_COLUMN_BOTTOM) / 268), 0.55, 1)
		for _, name in ipairs({ "L1", "R1", "L2", "R2" }) do
			scales[name] = side
		end
		scales.L3, scales.R3, scales.C3 = bottom, bottom, bottom
		scales.CL, scales.CR = side, side
		local sideEdge = (16 + 288) * side
		centerOffset = math.clamp(W / 2 - sideEdge - 8 - 85 * side, 190, 250)
	end
	layout.Device = device
	layout.Canvas = canvas
	layout.Scales = scales
	layout.CenterOffset = centerOffset
end

-- Position (centre, AnchorPoint 0.5/0.5) et taille "design" d'un slot
-- (la taille réelle = taille x Slots.GetScale(name))
function Slots.GetPlacement(name: string): (UDim2, UDim2)
	local def = Slots.Definitions[name]
	if not def then
		return UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
	end
	local k = Slots.GetScale(name)

	local centerY = def.Y + def.H / 2
	local yUDim
	if centerY > Slots.DesignHeight / 2 then
		-- accroché en bas : marge (et hauteur) réduites de la même façon
		local bottomMargin = Slots.DesignHeight - (def.Y + def.H)
		yUDim = UDim.new(1, -(bottomMargin * k + def.H * k / 2))
	else
		-- accroché en haut, sous le bandeau d'actualités
		local top = def.Y
		if k ~= 1 and def.Anchor ~= "T" then
			top = TICKER_HEIGHT + (def.Y - TICKER_HEIGHT) * k
		end
		yUDim = UDim.new(0, top + def.H * k / 2)
	end

	local xUDim
	local size
	if def.Anchor == "T" then
		xUDim = UDim.new(0.5, 0)
		size = UDim2.new(1, 0, 0, def.H)
	elseif def.Anchor == "L" then
		xUDim = UDim.new(0, (def.X + def.W / 2) * k)
		size = UDim2.fromOffset(def.W, def.H)
	elseif def.Anchor == "R" then
		xUDim = UDim.new(1, -(def.X + def.W / 2) * k)
		size = UDim2.fromOffset(def.W, def.H)
	else -- "C"
		local offset = def.X
		if k ~= 1 and def.X ~= 0 then
			offset = (def.X < 0 and -1 or 1) * layout.CenterOffset
		end
		xUDim = UDim.new(0.5, offset)
		size = UDim2.fromOffset(def.W, def.H)
	end
	return UDim2.new(xUDim, yUDim), size
end

-- Replace un cadre de slot (position + UIScale "SlotScale")
local function place(frame: Frame, name: string)
	local position, size = Slots.GetPlacement(name)
	frame.Position = position
	frame.Size = size
	local scale = frame:FindFirstChild("SlotScale")
	if scale and scale:IsA("UIScale") and not frame:GetAttribute("SlotAnimating") then
		scale.Scale = Slots.GetScale(name)
	end
end

-- Recalcule la mise en page (appelé par Slots.Bind quand l'écran change)
function Slots.UpdateLayout(device: string, canvas: Vector2)
	computeLayout(device, canvas)
	for frame, name in pairs(frames) do
		if frame.Parent then
			place(frame, name)
		end
	end
	Slots.Changed:Fire()
end

-- Largeur (pixels "design") laissée libre au centre par les slots de côté
-- (L1/L2/R1/R2) : la colonne centrale ne doit pas dépasser. Sur PC : 1280 - 2 x 312.
function Slots.GetCenterClearWidth(): number
	local side = layout.Scales.L1 or 1
	return layout.Canvas.X - 2 * ((16 + 288) * side + 8)
end

-- Branche la mise en page sur l'Interface (profil d'appareil + taille de la toile).
-- Plusieurs appels possibles (un seul branchement).
function Slots.Bind(interface: any)
	if bound then
		return
	end
	bound = true
	local function update()
		Slots.UpdateLayout(interface.Device or "Desktop", interface.CanvasSize or Vector2.new(1280, 720))
	end
	interface.ScaleChanged:Connect(update)
	interface.DeviceChanged:Connect(update)
	update()
end

-- Crée le cadre (transparent) d'un slot dans `parent`.
-- Slots réels : ClipsDescendants = true + UIScale "SlotScale" (échelle du slot).
-- Overlay / Background : plein écran.
function Slots.Create(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)

	if name == "Overlay" or name == "Background" or not Slots.Definitions[name] then
		if not Slots.IsValid(name) then
			warn("[Slots] Emplacement inconnu : " .. tostring(name) .. " (plein écran utilisé)")
		end
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(1, 1)
		frame.ClipsDescendants = false
	else
		frame.ClipsDescendants = true
		if Slots.Definitions[name].Anchor ~= "T" then
			local scale = Instance.new("UIScale")
			scale.Name = "SlotScale"
			scale.Scale = Slots.GetScale(name)
			scale.Parent = frame
		end
		place(frame, name)
		frames[frame] = name
	end

	frame.Parent = parent
	return frame
end

return Slots
