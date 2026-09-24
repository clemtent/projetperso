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
]]

local Slots = {}

Slots.DesignHeight = 720

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

-- Position (centre, AnchorPoint 0.5/0.5) et taille d'un slot
function Slots.GetPlacement(name: string): (UDim2, UDim2)
	local def = Slots.Definitions[name]
	if not def then
		return UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
	end

	local centerY = def.Y + def.H / 2
	local yUDim
	if centerY > Slots.DesignHeight / 2 then
		yUDim = UDim.new(1, -(Slots.DesignHeight - centerY)) -- accroché en bas
	else
		yUDim = UDim.new(0, centerY) -- accroché en haut
	end

	local xUDim
	local size
	if def.Anchor == "T" then
		xUDim = UDim.new(0.5, 0)
		size = UDim2.new(1, 0, 0, def.H)
	elseif def.Anchor == "L" then
		xUDim = UDim.new(0, def.X + def.W / 2)
		size = UDim2.fromOffset(def.W, def.H)
	elseif def.Anchor == "R" then
		xUDim = UDim.new(1, -(def.X + def.W / 2))
		size = UDim2.fromOffset(def.W, def.H)
	else -- "C"
		xUDim = UDim.new(0.5, def.X)
		size = UDim2.fromOffset(def.W, def.H)
	end
	return UDim2.new(xUDim, yUDim), size
end

-- Crée le cadre (transparent) d'un slot dans `parent`.
-- Slots réels : ClipsDescendants = true. Overlay / Background : plein écran.
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
		local position, size = Slots.GetPlacement(name)
		frame.Position = position
		frame.Size = size
		frame.ClipsDescendants = true
	end

	frame.Parent = parent
	return frame
end

return Slots
