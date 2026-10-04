--[[
	TrainModels (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TrainModels

	🚂 Fabriques 3D du train de Dopamine Town (v11, TRAIN11), CÔTÉ CLIENT
	(rien au serveur, aucune vraie lumière, aucun son) :
	  - VOITURES (repère local : origine sur le dessus du rail au centre de
	    la voiture, -Z = avant, +X = droite = extérieur de la boucle,
	    -X = côté quai) :
	      Loco  : locomotive diesel-électrique, nez profilé, pare-brise
	              incliné, phares, chasse-pierres, grilles, ventilateurs,
	              cabine avec pupitre (et son conducteur PNJ, TrainClient) ;
	      Coach : voiture voyageurs, 4 portes coulissantes-louvoyantes, 8
	              fenêtres, 16 sièges en carrés (coussin à 1,85 du plancher),
	              tablettes, porte-bagages, plafonnier, écrans "Prochain arrêt" ;
	      Vault : WAGON BLINDÉ du convoi de diamants : tôle larmée, nervures,
	              bandes de danger, volet coulissant (pied-de-biche), boîtier
	              électronique (piratage), porte de coffre-fort à volant
	              (perceuse), étagères de diamants, lingots, sacs, gyrophare ;
	    + bogies, roues, soufflets, tampons, attelages, toit et clim.
	    Chaque voiture = liste de pièces + repères LOCAUX : TrainModels.Pose
	    les déplace d'un coup (workspace:BulkMoveTo). Portes, volet, coffre :
	    repères locaux recalculés (SetDoors / SetVault).
	    Pièces "Collider" invisibles (sol, parois, toit) : solides seulement
	    à l'arrêt (TrainModels.SetSolid) -> on entre dans une voiture en gare,
	    jamais de projection par un train qui roule.
	  - IMPOSTEURS (loin) : 3 à 5 blocs par voiture ;
	  - VOIE en morceaux (TrackChunk) : ballast, traverses béton (détail),
	    rails ; rien sur la chaussée des passages à niveau ;
	  - GARES (Station) : quai de plain-pied avec le plancher des voitures,
	    bordure et ligne de sécurité jaune, bande d'éveil, marquise sur
	    colonnes, bancs, horloge de quai, tableau des départs (SurfaceGui),
	    bâtiment voyageurs en briques à grandes baies (hall avec guichet,
	    bancs, tableau, portes vers le trottoir et vers le quai), marches ;
	  - PASSAGES À NIVEAU (Crossing) : platelage au niveau du rail avec
	    rampes, 2 demi-barrières rouges et blanches (bras qui pivotent), feux
	    rouges clignotants, croix de Saint-André ;
	  - PLANQUES (Hideout) : grange abandonnée, bottes de paille, caisses,
	    cercle de dépôt.
	Tout est ancré, sans requête ni contact ; seuls les quais, marches,
	platelages et colliders touchent l'avatar local. Pas de z-fight : aucune
	face coplanaire superposée (décalages >= 0,04).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainLine = require(ReplicatedStorage.Shared.TrainLine)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local TrainModels = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local TAU = math.pi * 2

local FL = TrainLine.FLOOR_L -- 3 : plancher local
local HW = TrainLine.CAR_W / 2 -- 5,5
local WALL_TOP = 11.5
local ROOF_TOP = 13

local DARK = rgb(42, 42, 48)
local STEEL = rgb(120, 126, 136)
local CHROME = rgb(196, 200, 208)
local BLACK = rgb(24, 24, 28)
local GLASS = rgb(120, 160, 190)
local WHITE = rgb(244, 242, 236)
local YELLOW = rgb(255, 204, 40)
local RED = rgb(214, 40, 48)

TrainModels.LIVERIES = {
	Express = { Body = rgb(186, 28, 44), Band = rgb(244, 234, 210), Stripe = rgb(212, 168, 64), Roof = rgb(70, 72, 80), Door = rgb(150, 20, 34), Text = "DOPAMINE EXPRESS" },
	Shuttle = { Body = rgb(238, 241, 244), Band = rgb(0, 146, 158), Stripe = rgb(255, 196, 40), Roof = rgb(92, 96, 104), Door = rgb(255, 196, 40), Text = "NAVETTE DE LA CEINTURE" },
}

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

export type CarRec = {
	Kind: string,
	Model: Model,
	Parts: { BasePart },
	Locals: { CFrame },
	Base: { CFrame }, -- repères locaux de départ (portes, volet, coffre)
	Colliders: { BasePart },
	Doors: { { Index: number, Side: number, Sign: number } },
	DoorOpen: number,
	Solid: boolean?,
	Vault: any?,
	Seats: { [number]: BasePart },
	DoorParts: { BasePart },
	Screens: { TextLabel },
	Glow: { BasePart },
	Len: number,
	Npc: { any },
	LastCF: CFrame?,
}

local function newPart(shape: string?): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	elseif shape == "Corner" then
		return Instance.new("CornerWedgePart")
	end
	local p = Instance.new("Part")
	if shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	return p
end

local function style(p: BasePart, name: string, size: Vector3, color: Color3, material: Enum.Material?)
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.X * size.Y * size.Z > 20
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- Pièce fixe (décor de la voie, des gares...) en repère MONDE
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p = newPart(shape)
	style(p, name, size, color, material)
	p.CFrame = cf
	p.Parent = parent
	return p
end
TrainModels.Part = part

-- Pièce d'une voiture (repère LOCAL, posée par Pose)
local function cp(rec: CarRec, name: string, size: Vector3, lcf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p = newPart(shape)
	style(p, name, size, color, material)
	p.CFrame = lcf
	p.Parent = rec.Model
	table.insert(rec.Parts, p)
	table.insert(rec.Locals, lcf)
	table.insert(rec.Base, lcf)
	return p
end

local function glass(p: BasePart, transparency: number?): BasePart
	p.Material = M.Glass
	p.Transparency = transparency or 0.35
	p.CastShadow = false
	p.Reflectance = 0.05
	return p
end

local function neon(p: BasePart, nightOnly: boolean?): BasePart
	p.Material = M.Neon
	p.CastShadow = false
	if nightOnly then
		p:SetAttribute("NightGlow", true)
	end
	return p
end

-- Pièce invisible portant une SurfaceGui (textes : jamais coplanaire)
local function canvasGui(p: BasePart, face: Enum.NormalId, pps: number): SurfaceGui
	p.Transparency = 1
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.6
	gui.MaxDistance = 260
	gui.ClipsDescendants = true
	gui.Parent = p
	return gui
end

local function label(parent: Instance, text: string, color: Color3, font: Enum.Font?, size: UDim2?, pos: UDim2?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size or UDim2.fromScale(1, 1)
	l.Position = pos or UDim2.fromScale(0, 0)
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = font or Enum.Font.GothamBlack
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- Repère local : position + lacet
local function L(x: number, y: number, z: number, yaw: number?): CFrame
	if yaw and yaw ~= 0 then
		return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	end
	return CFrame.new(x, y, z)
end

-- Cylindre dont l'axe suit Y (Roblox : axe des cylindres = X)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
-- Cylindre dont l'axe suit Z
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

local function newRec(kind: string, len: number): CarRec
	local model = Instance.new("Model")
	model.Name = "Train" .. kind
	return {
		Kind = kind,
		Model = model,
		Parts = {},
		Locals = {},
		Base = {},
		Colliders = {},
		Doors = {},
		DoorOpen = 0,
		Solid = nil,
		Vault = nil,
		Seats = {},
		DoorParts = {},
		Screens = {},
		Glow = {},
		Len = len,
		Npc = {},
		LastCF = nil,
	}
end

local function collider(rec: CarRec, name: string, size: Vector3, lcf: CFrame): BasePart
	local p = cp(rec, name, size, lcf, WHITE)
	p.Transparency = 1
	p.CastShadow = false
	p:SetAttribute("TrainCollider", true)
	table.insert(rec.Colliders, p)
	return p
end

----------------------------------------------------------------------
-- Éléments communs : châssis, bogies, extrémités, toit
----------------------------------------------------------------------

local function bogie(rec: CarRec, zc: number, axles: number)
	cp(rec, "BogieFrame", Vector3.new(7.2, 0.9, axles == 3 and 11 or 8.4), L(0, 1.75, zc), DARK, M.Metal)
	local spacing = 2.7
	for a = 1, axles do
		local za = zc + (a - (axles + 1) / 2) * spacing * (axles == 3 and 1.35 or 2)
		for _, sx in ipairs({ -1, 1 }) do
			cp(rec, "Wheel", Vector3.new(0.5, 2.6, 2.6), L(sx * 2.6, 1.3, za), rgb(60, 60, 66), M.Metal, "Cyl")
			cp(rec, "Hub", Vector3.new(0.6, 1.1, 1.1), L(sx * 2.9, 1.3, za), CHROME, M.Metal, "Cyl")
		end
		cp(rec, "Axle", Vector3.new(4.6, 0.45, 0.45), L(0, 1.3, za), STEEL, M.Metal, "Cyl")
	end
	-- ressorts (suspension) et boîtes d'essieu
	for _, sx in ipairs({ -1, 1 }) do
		cp(rec, "Spring", Vector3.new(0.9, 0.7, 0.7), L(sx * 3.3, 2.45, zc) * UPRIGHT, rgb(210, 170, 40), M.Metal, "Cyl")
	end
end

local function ends(rec: CarRec, len: number, front: boolean, back: boolean, livery: any)
	local h = len / 2
	for _, sz in ipairs({ -1, 1 }) do
		local isFront = sz < 0
		if (isFront and front) or (not isFront and back) then
			-- soufflet d'intercirculation (caoutchouc) + tampons + attelage
			cp(rec, "Bellows", Vector3.new(6.2, 8.4, 0.85), L(0, FL + 4.3, sz * (h + 0.42)), BLACK, M.Rubber)
			for _, sx in ipairs({ -1, 1 }) do
				cp(rec, "Buffer", Vector3.new(0.9, 0.9, 0.9), L(sx * 3.5, 2.3, sz * (h + 0.45)) * ALONG_Z, CHROME, M.Metal, "Cyl")
			end
			cp(rec, "Coupler", Vector3.new(0.7, 0.7, 1.0), L(0, 2.1, sz * (h + 0.5)), DARK, M.Metal)
		end
	end
	local _ = livery
end

local function roof(rec: CarRec, len: number, livery: any, zFrom: number?, zTo: number?)
	local z0 = zFrom or -len / 2
	local z1 = zTo or len / 2
	local l = z1 - z0
	local zc = (z0 + z1) / 2
	local col = livery.Roof
	cp(rec, "RoofTop", Vector3.new(7, 1.5, l), L(0, WALL_TOP + 0.75, zc), col, M.Metal)
	-- pans inclinés (WedgePart tourné : haut côté axe, bas côté bord)
	cp(rec, "RoofSlopeR", Vector3.new(l, 1.5, 2), L(4.5, WALL_TOP + 0.75, zc) * CFrame.Angles(0, -math.pi / 2, 0), col, M.Metal, "Wedge")
	cp(rec, "RoofSlopeL", Vector3.new(l, 1.5, 2), L(-4.5, WALL_TOP + 0.75, zc) * CFrame.Angles(0, math.pi / 2, 0), col, M.Metal, "Wedge")
	-- gouttières (fines, au bord)
	for _, sx in ipairs({ -1, 1 }) do
		cp(rec, "Gutter", Vector3.new(0.25, 0.25, l), L(sx * (HW + 0.12), WALL_TOP + 0.1, zc), CHROME, M.Metal)
	end
end

local function underframe(rec: CarRec, len: number)
	cp(rec, "Underframe", Vector3.new(9.6, 1.0, len - 1.2), L(0, 2.2, 0), DARK, M.Metal)
	cp(rec, "Floor", Vector3.new(10.4, 0.4, len - 0.6), L(0, FL - 0.2, 0), rgb(84, 88, 98))
	-- réservoirs / coffres sous caisse
	cp(rec, "Tank", Vector3.new(5.2, 1.1, 6), L(0, 1.75, 0), rgb(56, 58, 64), M.Metal)
end

----------------------------------------------------------------------
-- Voiture voyageurs
----------------------------------------------------------------------

local DOOR_W = 5
local DOOR_H = 8.2

local function coach(rec: CarRec, livery: any)
	local len = rec.Len
	local h = len / 2
	local zd = h - 4.5 -- centres des portes : ±zd
	local winZ = zd - DOOR_W / 2 -- section des fenêtres : [-winZ, winZ]
	underframe(rec, len)
	bogie(rec, -len * 0.32, 2)
	bogie(rec, len * 0.32, 2)
	ends(rec, len, true, true, livery)
	roof(rec, len, livery)
	-- clim + aérations sur le toit
	cp(rec, "AirCon", Vector3.new(4.6, 0.8, 7), L(0, ROOF_TOP + 0.4, -9), rgb(150, 154, 162), M.Metal)
	cp(rec, "AirCon", Vector3.new(4.6, 0.8, 7), L(0, ROOF_TOP + 0.4, 9), rgb(150, 154, 162), M.Metal)
	for _, sz in ipairs({ -1, 1 }) do
		cp(rec, "AirGrille", Vector3.new(3.6, 0.1, 5), L(0, ROOF_TOP + 0.85, sz * 9), DARK, M.Metal)
	end
	local nWin = 4
	local pillar = 1.0
	local winW = (2 * winZ - (nWin + 1) * pillar) / nWin
	local lowTop, winTop = FL + 2.8, FL + 6.6 -- 5,8 / 9,6
	for _, sx in ipairs({ -1, 1 }) do
		local xw = sx * (HW - 0.15)
		-- jupe sous la caisse
		cp(rec, "Skirt", Vector3.new(0.3, 0.8, len), L(xw, FL - 0.4, 0), livery.Body, M.Metal)
		-- extrémités pleines (entre la porte et le bout)
		for _, sz in ipairs({ -1, 1 }) do
			local zEnd0, zEnd1 = zd + DOOR_W / 2, h
			cp(rec, "EndPost", Vector3.new(0.3, WALL_TOP - FL, zEnd1 - zEnd0), L(xw, (FL + WALL_TOP) / 2, sz * (zEnd0 + zEnd1) / 2), livery.Body, M.Metal)
			-- linteau au-dessus de la porte
			cp(rec, "Lintel", Vector3.new(0.3, WALL_TOP - FL - DOOR_H, DOOR_W), L(xw, (FL + DOOR_H + WALL_TOP) / 2, sz * zd), livery.Body, M.Metal)
			-- voyant de porte
			local lamp = cp(rec, "DoorLamp", Vector3.new(0.12, 0.3, 0.6), L(sx * (HW + 0.06), FL + DOOR_H + 0.12, sz * zd), rgb(255, 170, 40))
			neon(lamp)
			-- bande de livrée sur l'extrémité
			cp(rec, "StripeEnd", Vector3.new(0.06, 0.4, zEnd1 - zEnd0), L(sx * (HW + 0.03), FL + 2.2, sz * (zEnd0 + zEnd1) / 2), livery.Stripe)
		end
		-- section des fenêtres
		cp(rec, "LowBand", Vector3.new(0.3, lowTop - FL, 2 * winZ), L(xw, (FL + lowTop) / 2, 0), livery.Body, M.Metal)
		cp(rec, "TopBand", Vector3.new(0.3, WALL_TOP - winTop, 2 * winZ), L(xw, (winTop + WALL_TOP) / 2, 0), livery.Body, M.Metal)
		cp(rec, "Stripe", Vector3.new(0.06, 0.4, 2 * winZ), L(sx * (HW + 0.03), FL + 2.2, 0), livery.Stripe)
		cp(rec, "WinBandTrim", Vector3.new(0.06, 0.25, 2 * winZ), L(sx * (HW + 0.03), lowTop - 0.2, 0), livery.Band)
		for k = 0, nWin do
			local zp = -winZ + pillar / 2 + k * (winW + pillar)
			cp(rec, "Pillar", Vector3.new(0.3, winTop - lowTop, pillar), L(xw, (lowTop + winTop) / 2, zp), livery.Band, M.Metal)
		end
		for k = 1, nWin do
			local zw = -winZ + pillar + (k - 1) * (winW + pillar) + winW / 2
			glass(cp(rec, "Window", Vector3.new(0.12, winTop - lowTop, winW), L(sx * (HW - 0.2), (lowTop + winTop) / 2, zw), GLASS))
		end
		-- doublage intérieur (crème) sous les fenêtres
		cp(rec, "Lining", Vector3.new(0.06, lowTop - FL - 0.1, 2 * winZ), L(sx * (HW - 0.33), (FL + lowTop) / 2 + 0.05, 0), rgb(232, 224, 206))
		-- porte-bagages
		cp(rec, "Rack", Vector3.new(1.3, 0.12, 2 * winZ - 1), L(sx * (HW - 1.0), FL + 6.95, 0), CHROME, M.Metal)
		-- portes (2 vantaux par porte)
		for _, sz in ipairs({ -1, 1 }) do
			for _, leaf in ipairs({ -1, 1 }) do
				local z = sz * zd + leaf * DOOR_W / 4
				local base = #rec.Parts + 1
				cp(rec, "DoorLeaf", Vector3.new(0.25, DOOR_H, DOOR_W / 2 - 0.04), L(xw, FL + DOOR_H / 2, z), livery.Door, M.Metal)
				glass(cp(rec, "DoorGlass", Vector3.new(0.1, 2.8, DOOR_W / 2 - 0.9), L(sx * (HW - 0.0), FL + 5.6, z), GLASS), 0.3)
				cp(rec, "DoorStripe", Vector3.new(0.05, 0.4, DOOR_W / 2 - 0.04), L(sx * (HW + 0.0), FL + 2.2, z), livery.Stripe)
				for i = base, #rec.Parts do
					table.insert(rec.Doors, { Index = i, Side = sx, Sign = leaf })
					if sx < 0 and i == base then
						table.insert(rec.DoorParts, rec.Parts[i])
					end
				end
			end
		end
	end
	-- parois d'about (porte d'intercirculation au milieu)
	for _, sz in ipairs({ -1, 1 }) do
		local z = sz * (h - 0.15)
		for _, sx in ipairs({ -1, 1 }) do
			cp(rec, "EndWall", Vector3.new(4, WALL_TOP - FL, 0.3), L(sx * 3.5, (FL + WALL_TOP) / 2, z), livery.Body, M.Metal)
		end
		cp(rec, "EndTop", Vector3.new(3, WALL_TOP - FL - 7.4, 0.3), L(0, (FL + 7.4 + WALL_TOP) / 2, z), livery.Body, M.Metal)
		glass(cp(rec, "GangwayDoor", Vector3.new(2.9, 7.3, 0.12), L(0, FL + 3.67, z), rgb(170, 200, 210)), 0.45)
		-- écran "prochain arrêt" (face vers l'intérieur)
		local scr = cp(rec, "InfoScreen", Vector3.new(3.4, 0.9, 0.12), L(0, FL + 7.9, sz * (h - 0.5)), BLACK)
		local gui = canvasGui(cp(rec, "InfoCanvas", Vector3.new(3.3, 0.8, 0.04), L(0, FL + 7.9, sz * (h - 0.58)), BLACK), if sz < 0 then Enum.NormalId.Back else Enum.NormalId.Front, 60)
		gui.LightInfluence = 0
		local text = label(gui, "", rgb(255, 190, 60), Enum.Font.Code)
		table.insert(rec.Screens, text)
		local _ = scr
	end
	-- intérieur : plafond, plafonniers, allée
	cp(rec, "Ceiling", Vector3.new(10.4, 0.2, len - 0.8), L(0, WALL_TOP - 0.1, 0), rgb(236, 236, 232))
	for _, sx in ipairs({ -1, 1 }) do
		local strip = cp(rec, "LightStrip", Vector3.new(0.5, 0.06, len - 6), L(sx * 2.4, WALL_TOP - 0.23, 0), rgb(255, 240, 214))
		neon(strip)
	end
	cp(rec, "Carpet", Vector3.new(2.4, 0.04, 2 * winZ), L(0, FL + 0.02, 0), rgb(70, 60, 110), M.Fabric)
	-- sièges (dessus du coussin : TrainLine.SeatsLocal, cibles SCALE11)
	local seatColor = if livery.Text == "DOPAMINE EXPRESS" then rgb(150, 30, 46) else rgb(30, 110, 150)
	for i, s in ipairs(TrainLine.SeatsLocal("Coach")) do
		local f = L(s.X, s.Y, s.Z, s.Yaw)
		local cushion = cp(rec, "SeatCushion", Vector3.new(1.9, 0.5, 2.1), f * CFrame.new(0, -0.25, 0), seatColor, M.Fabric)
		rec.Seats[i] = cushion
		cp(rec, "SeatBase", Vector3.new(1.4, s.Y - FL - 0.5, 1.5), f * CFrame.new(0, -(s.Y - FL) / 2 - 0.25, 0), DARK, M.Metal)
		cp(rec, "SeatBack", Vector3.new(1.9, 2.9, 0.45), f * CFrame.new(0, 1.2, 1.05 + 0.22) * CFrame.Angles(math.rad(-8), 0, 0), seatColor, M.Fabric)
		cp(rec, "Headrest", Vector3.new(1.4, 0.8, 0.06), f * CFrame.new(0, 2.2, 1.05 - 0.05) * CFrame.Angles(math.rad(-8), 0, 0), WHITE, M.Fabric)
	end
	-- tablettes entre les sièges en vis-à-vis (contre la fenêtre)
	for _, zc in ipairs({ -8.25, 8.25 }) do
		for _, sx in ipairs({ -1, 1 }) do
			cp(rec, "Table", Vector3.new(1.6, 0.16, 1.8), L(sx * 4.2, FL + 3.0, zc), rgb(196, 170, 130), M.Wood)
			cp(rec, "TableLeg", Vector3.new(0.2, 2.9, 0.2), L(sx * 3.6, FL + 1.5, zc), CHROME, M.Metal)
		end
	end
	-- colliders (solides à l'arrêt seulement : TrainModels.SetSolid)
	collider(rec, "ColFloor", Vector3.new(10.6, 0.4, len), L(0, FL - 0.2, 0))
	collider(rec, "ColRoof", Vector3.new(11, 0.6, len), L(0, WALL_TOP + 0.3, 0))
	for _, sx in ipairs({ -1, 1 }) do
		collider(rec, "ColWall", Vector3.new(0.6, WALL_TOP - FL, 2 * winZ), L(sx * (HW - 0.3), (FL + WALL_TOP) / 2, 0))
		for _, sz in ipairs({ -1, 1 }) do
			collider(rec, "ColEnd", Vector3.new(0.6, WALL_TOP - FL, h - zd - DOOR_W / 2), L(sx * (HW - 0.3), (FL + WALL_TOP) / 2, sz * (zd + DOOR_W / 2 + (h - zd - DOOR_W / 2) / 2)))
			if sx > 0 then
				-- (portes côté extérieur : toujours fermées)
				collider(rec, "ColDoorOut", Vector3.new(0.6, DOOR_H, DOOR_W), L(sx * (HW - 0.3), FL + DOOR_H / 2, sz * zd))
			end
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		collider(rec, "ColEndWall", Vector3.new(11, WALL_TOP - FL, 0.6), L(0, (FL + WALL_TOP) / 2, sz * (h - 0.3)))
	end
end

----------------------------------------------------------------------
-- Locomotive
----------------------------------------------------------------------

local function loco(rec: CarRec, livery: any, npcSeat: { CFrame })
	local len = rec.Len
	local h = len / 2
	local cabBack = -h + 8 -- -16 : fond de la cabine
	underframe(rec, len)
	bogie(rec, -h + 12, 3)
	bogie(rec, h - 12, 3)
	ends(rec, len, false, true, livery)
	roof(rec, len, livery, -h + 5.2, h)
	-- NEZ : bloc bas, capot incliné, chasse-pierres, pare-brise incliné
	cp(rec, "NoseLow", Vector3.new(11, 4.6, 3), L(0, 4.3, -h + 1.5), livery.Body, M.Metal)
	cp(rec, "NoseHood", Vector3.new(11, 1.2, 3), L(0, 7.2, -h + 1.5), livery.Body, M.Metal, "Wedge")
	cp(rec, "Plow", Vector3.new(10.6, 1.5, 1.4), L(0, 1.2, -h - 0.5), rgb(60, 62, 68), M.Metal, "Wedge")
	cp(rec, "NoseStripe", Vector3.new(11.08, 0.5, 3.08), L(0, 3.4, -h + 1.5), livery.Stripe)
	glass(cp(rec, "Windscreen", Vector3.new(10.4, 3.7, 2.2), L(0, 7.8 + 1.85, -h + 3 + 1.1), rgb(40, 60, 80)), 0.2)
	for _, sx in ipairs({ -1, 1 }) do
		cp(rec, "Cheek", Vector3.new(0.3, 3.7, 2.2), L(sx * (HW - 0.15), 7.8 + 1.85, -h + 3 + 1.1), livery.Body, M.Metal, "Wedge")
	end
	cp(rec, "CabRoof", Vector3.new(11, 1.5, 3), L(0, WALL_TOP + 0.75, -h + 6.7), livery.Roof, M.Metal)
	-- essuie-glaces
	for _, sx in ipairs({ -1, 1 }) do
		cp(rec, "Wiper", Vector3.new(0.12, 2.4, 0.12), L(sx * 2.2, 8.6, -h + 3.35) * CFrame.Angles(math.rad(-25), 0, math.rad(sx * 25)), BLACK)
	end
	-- phares (toujours allumés) + feux de position + feu haut
	for _, sx in ipairs({ -1, 1 }) do
		cp(rec, "LampRing", Vector3.new(0.3, 1.2, 1.2), L(sx * 3.6, 4.6, -h - 0.1) * ALONG_Z, CHROME, M.Metal, "Cyl")
		neon(cp(rec, "Headlight", Vector3.new(0.3, 0.9, 0.9), L(sx * 3.6, 4.6, -h - 0.2) * ALONG_Z, rgb(255, 248, 220), nil, "Cyl"))
		neon(cp(rec, "MarkerLight", Vector3.new(0.25, 0.5, 0.5), L(sx * 4.5, 3.2, -h - 0.15) * ALONG_Z, rgb(255, 230, 190), nil, "Cyl"))
	end
	neon(cp(rec, "TopLight", Vector3.new(0.25, 0.7, 0.7), L(0, WALL_TOP + 0.8, -h + 5.1) * ALONG_Z, rgb(255, 248, 220), nil, "Cyl"))
	-- nom de la machine sur le nez
	local plate = cp(rec, "NosePlate", Vector3.new(6, 1.0, 0.1), L(0, 5.8, -h - 0.06), BLACK)
	local gui = canvasGui(plate, Enum.NormalId.Front, 40)
	label(gui, livery.Text, livery.Stripe, Enum.Font.GothamBlack)
	plate.Transparency = 0
	-- cabine : flancs, vitres latérales, porte, pupitre
	for _, sx in ipairs({ -1, 1 }) do
		local xw = sx * (HW - 0.15)
		cp(rec, "CabLow", Vector3.new(0.3, 4.0, 5), L(xw, FL + 2, -h + 5.5), livery.Body, M.Metal)
		glass(cp(rec, "CabWindow", Vector3.new(0.12, 3.6, 2.6), L(sx * (HW - 0.2), FL + 6, -h + 4.6), GLASS))
		cp(rec, "CabPost", Vector3.new(0.3, 3.6, 2.4), L(xw, FL + 6, -h + 6.8), livery.Body, M.Metal)
		cp(rec, "CabTop", Vector3.new(0.3, WALL_TOP - FL - 7.8, 5), L(xw, (FL + 7.8 + WALL_TOP) / 2, -h + 5.5), livery.Body, M.Metal)
		cp(rec, "CabDoorLine", Vector3.new(0.06, 7.6, 0.12), L(sx * (HW + 0.03), FL + 3.8, -h + 7.9), BLACK)
		cp(rec, "GrabRail", Vector3.new(0.2, 3.4, 0.2), L(sx * (HW + 0.25), FL + 2.4, -h + 8.4), CHROME, M.Metal)
	end
	cp(rec, "CabBack", Vector3.new(10.4, WALL_TOP - FL, 0.3), L(0, (FL + WALL_TOP) / 2, cabBack), rgb(200, 200, 196))
	cp(rec, "Desk", Vector3.new(9.6, 2.6, 1.6), L(0, FL + 1.3, -h + 3.6), rgb(64, 66, 74))
	cp(rec, "DeskTop", Vector3.new(9.6, 0.2, 2.2), L(0, FL + 2.7, -h + 3.8) * CFrame.Angles(math.rad(12), 0, 0), rgb(40, 42, 48))
	for k = -1, 1 do
		local scr = cp(rec, "DeskScreen", Vector3.new(1.6, 1.0, 0.1), L(k * 2.2 - 1.2, FL + 3.4, -h + 3.3) * CFrame.Angles(math.rad(-20), 0, 0), rgb(60, 140, 200))
		neon(scr)
	end
	cp(rec, "Throttle", Vector3.new(0.3, 0.8, 0.3), L(-3.2, FL + 3.2, -h + 4.2), BLACK)
	cp(rec, "DriverSeat", Vector3.new(2.2, 0.5, 2.2), L(-2.2, FL + 1.6, -h + 6.2), rgb(40, 40, 46), M.Fabric)
	cp(rec, "DriverBack", Vector3.new(2.2, 2.6, 0.4), L(-2.2, FL + 3.1, -h + 7.3), rgb(40, 40, 46), M.Fabric)
	table.insert(npcSeat, L(-2.2, FL, -h + 6.2))
	-- salle des machines : flancs pleins, grilles, bandes, texte
	local mz0, mz1 = cabBack, h
	local ml = mz1 - mz0
	local mzc = (mz0 + mz1) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local xw = sx * (HW - 0.15)
		cp(rec, "Side", Vector3.new(0.3, WALL_TOP - FL, ml), L(xw, (FL + WALL_TOP) / 2, mzc), livery.Body, M.Metal)
		cp(rec, "Skirt", Vector3.new(0.3, 0.8, len - 2), L(xw, FL - 0.4, 0), livery.Body, M.Metal)
		cp(rec, "Stripe", Vector3.new(0.06, 0.5, ml), L(sx * (HW + 0.03), FL + 2.2, mzc), livery.Stripe)
		cp(rec, "Band", Vector3.new(0.06, 0.3, ml), L(sx * (HW + 0.03), FL + 3.0, mzc), livery.Band)
		-- grilles d'aération (3 panneaux à lames)
		for g = 0, 2 do
			local zg = mz0 + 6 + g * 9
			cp(rec, "Grille", Vector3.new(0.08, 3.2, 6.5), L(sx * (HW + 0.04), FL + 6.4, zg), rgb(52, 54, 60), M.Metal)
			for s = -2, 2 do
				cp(rec, "Louvre", Vector3.new(0.14, 0.18, 6.3), L(sx * (HW + 0.1), FL + 6.4 + s * 0.6, zg), rgb(30, 30, 34), M.Metal)
			end
		end
		-- grand nom sur le flanc
		local nameCanvas = cp(rec, "SideName", Vector3.new(0.05, 1.6, 22), L(sx * (HW + 0.06), FL + 4.6, mzc + 2), WHITE)
		local g2 = canvasGui(nameCanvas, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, 24)
		label(g2, livery.Text, livery.Band, Enum.Font.GothamBlack)
	end
	-- ventilateurs de toit + échappement + klaxon
	for k = 0, 1 do
		local zf = mz0 + 10 + k * 12
		cp(rec, "FanRing", Vector3.new(0.5, 4.2, 4.2), L(0, ROOF_TOP + 0.2, zf) * UPRIGHT, rgb(80, 82, 90), M.Metal, "Cyl")
		cp(rec, "FanGrid", Vector3.new(0.12, 3.8, 3.8), L(0, ROOF_TOP + 0.5, zf) * UPRIGHT, rgb(30, 30, 34), M.DiamondPlate, "Cyl")
	end
	cp(rec, "Exhaust", Vector3.new(1.2, 1.0, 1.0), L(2.2, ROOF_TOP + 0.55, mz0 + 4) * UPRIGHT, DARK, M.Metal, "Cyl")
	cp(rec, "Horn", Vector3.new(1.4, 0.45, 0.45), L(-1.6, ROOF_TOP + 0.3, -h + 7) * ALONG_Z, CHROME, M.Metal, "Cyl")
	-- arrière : paroi + feux rouges
	cp(rec, "RearWall", Vector3.new(11, WALL_TOP - FL, 0.3), L(0, (FL + WALL_TOP) / 2, h - 0.15), livery.Body, M.Metal)
	-- colliders
	collider(rec, "ColBody", Vector3.new(11, WALL_TOP - FL + 1, len - 1), L(0, (FL + WALL_TOP) / 2, 0.5))
	collider(rec, "ColNose", Vector3.new(11, 6, 3), L(0, 4, -h + 1.5))
end

----------------------------------------------------------------------
-- Wagon blindé (convoi de diamants)
----------------------------------------------------------------------

local function vault(rec: CarRec, livery: any)
	local len = rec.Len
	local h = len / 2
	local V = TrainLine.VaultLocal()
	local plate = rgb(118, 124, 132)
	underframe(rec, len)
	bogie(rec, -len * 0.3, 2)
	bogie(rec, len * 0.3, 2)
	ends(rec, len, true, false, livery)
	-- toit plat renforcé + gyrophare + antenne
	cp(rec, "Roof", Vector3.new(11, 1.0, len), L(0, WALL_TOP + 0.5, 0), rgb(96, 100, 108), M.DiamondPlate)
	local beaconBase = cp(rec, "BeaconBase", Vector3.new(0.5, 1.2, 1.2), L(0, WALL_TOP + 1.25, -h + 4) * UPRIGHT, DARK, M.Metal, "Cyl")
	local beacon = cp(rec, "Beacon", Vector3.new(1.0, 1.0, 1.0), L(0, WALL_TOP + 1.9, -h + 4), rgb(120, 60, 30), M.Glass, "Ball")
	beacon.Transparency = 0.15
	cp(rec, "Antenna", Vector3.new(2.4, 0.12, 0.12), L(2.5, WALL_TOP + 2.2, h - 4) * UPRIGHT, BLACK)
	local _ = beaconBase
	-- ouverture du coffre (côté quai, -X) : z dans [-DoorW/2, DoorW/2], y FL..FL+8
	local dw = V.DoorW
	local openTop = FL + 8
	for _, sx in ipairs({ -1, 1 }) do
		local xw = sx * (HW - 0.15)
		if sx > 0 then
			cp(rec, "Side", Vector3.new(0.3, WALL_TOP - FL, len), L(xw, (FL + WALL_TOP) / 2, 0), plate, M.DiamondPlate)
		else
			local segLen = h - dw / 2
			for _, sz in ipairs({ -1, 1 }) do
				cp(rec, "Side", Vector3.new(0.3, WALL_TOP - FL, segLen), L(xw, (FL + WALL_TOP) / 2, sz * (dw / 2 + segLen / 2)), plate, M.DiamondPlate)
			end
			cp(rec, "SideTop", Vector3.new(0.3, WALL_TOP - openTop, dw), L(xw, (openTop + WALL_TOP) / 2, 0), plate, M.DiamondPlate)
		end
		cp(rec, "Skirt", Vector3.new(0.3, 0.8, len), L(xw, FL - 0.4, 0), rgb(70, 74, 82), M.Metal)
		-- nervures verticales
		for k = -4, 4 do
			local z = k * 4
			if not (sx < 0 and math.abs(z) < dw / 2 + 0.6) then
				cp(rec, "Rib", Vector3.new(0.18, WALL_TOP - FL - 0.4, 0.5), L(sx * (HW + 0.09), (FL + WALL_TOP) / 2, z), rgb(90, 94, 102), M.Metal)
			end
		end
		-- bandes de danger jaunes et noires (bas de caisse)
		for k = 0, 8 do
			local z = -h + 2.1 + k * ((len - 4.2) / 8)
			cp(rec, "Hazard", Vector3.new(0.08, 0.7, 2.1), L(sx * (HW + 0.2), FL + 0.5, z), if k % 2 == 0 then YELLOW else BLACK)
		end
		-- inscription
		local sign = cp(rec, "Sign", Vector3.new(0.05, 1.5, 12), L(sx * (HW + 0.2), WALL_TOP - 1.3, if sx < 0 then -11 else 0), WHITE)
		local g = canvasGui(sign, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, 30)
		label(g, "💎 " .. Locale.T("DIAMOND CONVOY") .. " 💎", YELLOW, Enum.Font.GothamBlack)
	end
	-- parois d'about pleines
	for _, sz in ipairs({ -1, 1 }) do
		cp(rec, "EndWall", Vector3.new(11, WALL_TOP - FL, 0.3), L(0, (FL + WALL_TOP) / 2, sz * (h - 0.15)), plate, M.DiamondPlate)
	end
	-- feux de fin de convoi (rouges)
	for _, sx in ipairs({ -1, 1 }) do
		neon(cp(rec, "TailLight", Vector3.new(0.25, 0.6, 0.6), L(sx * 3.8, 3.6, h + 0.1) * ALONG_Z, rgb(255, 40, 40), nil, "Cyl"))
	end
	-- VOLET coulissant (pied-de-biche) : devant l'ouverture, glisse vers +Z
	local shutterIdx = {}
	local s1 = cp(rec, "Shutter", Vector3.new(0.3, 8.2, dw + 0.4), L(-HW - 0.35, FL + 4.05, 0), rgb(150, 156, 164), M.DiamondPlate)
	table.insert(shutterIdx, #rec.Parts)
	for k = -3, 3 do
		cp(rec, "ShutterRib", Vector3.new(0.12, 8.0, 0.25), L(-HW - 0.56, FL + 4.05, k * 1.2), rgb(110, 114, 122), M.Metal)
		table.insert(shutterIdx, #rec.Parts)
	end
	cp(rec, "ShutterLock", Vector3.new(0.4, 1.2, 0.8), L(-HW - 0.7, FL + 4.0, -dw / 2 + 0.8), rgb(220, 180, 40), M.Metal)
	table.insert(shutterIdx, #rec.Parts)
	cp(rec, "ShutterRail", Vector3.new(0.3, 0.3, dw * 2 + 1), L(-HW - 0.45, FL + 8.35, dw / 2), DARK, M.Metal)
	local _ = s1
	-- PORTE DU COFFRE (perceuse) : derrière le volet, pivote autour d'une charnière en z = -dw/2
	local doorIdx = {}
	cp(rec, "SafeDoor", Vector3.new(0.7, 7.6, dw - 0.3), L(-HW + 0.6, FL + 4, 0), rgb(150, 150, 160), M.Metal)
	table.insert(doorIdx, #rec.Parts)
	cp(rec, "SafeWheel", Vector3.new(0.3, 3.0, 3.0), L(-HW + 0.1, FL + 4, 0.6), CHROME, M.Metal, "Cyl")
	table.insert(doorIdx, #rec.Parts)
	for k = 0, 2 do
		cp(rec, "Spoke", Vector3.new(0.2, 3.6, 0.22), L(-HW - 0.02, FL + 4, 0.6) * CFrame.Angles(k * math.pi / 3, 0, 0), CHROME, M.Metal)
		table.insert(doorIdx, #rec.Parts)
	end
	for _, by in ipairs({ -2.8, 2.8 }) do
		for _, bz in ipairs({ -2.6, 2.6 }) do
			cp(rec, "Bolt", Vector3.new(0.3, 0.5, 0.5), L(-HW + 0.12, FL + 4 + by, bz), rgb(200, 190, 120), M.Metal, "Cyl")
			table.insert(doorIdx, #rec.Parts)
		end
	end
	cp(rec, "SafeFrame", Vector3.new(0.5, 0.6, dw), L(-HW + 0.6, FL + 8.1, 0), DARK, M.Metal)
	-- BOÎTIER électronique (piratage)
	local box = cp(rec, "HackBox", Vector3.new(0.5, 1.8, 1.4), L(V.Panel.X + 0.35, V.Panel.Y, V.Panel.Z), rgb(60, 64, 72), M.Metal)
	local screenPart = cp(rec, "HackScreen", Vector3.new(0.05, 1.0, 1.1), L(V.Panel.X + 0.07, V.Panel.Y + 0.2, V.Panel.Z), BLACK)
	local sg = canvasGui(screenPart, Enum.NormalId.Left, 80)
	sg.LightInfluence = 0
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(120, 10, 20)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local hackText = label(bg, "🔒 LOCKED", WHITE, Enum.Font.Code, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.25))
	local _b = box
	-- INTÉRIEUR : étagères de diamants, lingots, sacs, lumière
	cp(rec, "VaultFloor", Vector3.new(10.4, 0.06, len - 1), L(0, FL + 0.03, 0), rgb(70, 70, 78), M.DiamondPlate)
	for _, sz in ipairs({ -1, 1 }) do
		local zs = sz * (h - 3)
		cp(rec, "Shelf", Vector3.new(9.6, 7, 2.2), L(0, FL + 3.5, zs), rgb(80, 84, 92), M.Metal)
		for row = 0, 2 do
			for k = -3, 3 do
				local gem = cp(rec, "Gem", Vector3.new(0.6, 0.6, 0.6), L(k * 1.25, FL + 1.6 + row * 2.2, zs - sz * 1.3) * CFrame.Angles(math.rad(45), math.rad(30 + k * 10), 0), if (k + row) % 3 == 0 then rgb(120, 230, 255) elseif (k + row) % 3 == 1 then rgb(200, 160, 255) else rgb(255, 255, 255), M.Glass, "Ball")
				gem.Transparency = 0.1
				gem.Reflectance = 0.3
				if (k + row) % 2 == 0 then
					neon(gem)
				end
			end
		end
	end
	for k = 0, 5 do
		cp(rec, "GoldBar", Vector3.new(1.2, 0.5, 0.6), L(2.8 + (k % 2) * 1.3, FL + 0.25 + math.floor(k / 2) * 0.5, -1.2 + (k % 3) * 0.8), rgb(232, 186, 50), M.Metal)
	end
	local bags = {}
	for i, b in ipairs(V.Bags) do
		local bag = cp(rec, "LootBag", Vector3.new(1.6, 1.6, 1.6), L(b.X, b.Y - 0.2, b.Z), rgb(120, 96, 60), M.Fabric, "Ball")
		local tie = cp(rec, "BagTie", Vector3.new(0.6, 0.5, 0.6), L(b.X, b.Y + 0.7, b.Z), rgb(90, 70, 40), M.Fabric)
		local tag = cp(rec, "BagMark", Vector3.new(0.05, 0.6, 0.6), L(b.X - 0.82, b.Y - 0.1, b.Z), YELLOW)
		bags[i] = { bag, tie, tag }
	end
	neon(cp(rec, "VaultLight", Vector3.new(6, 0.08, 0.6), L(0, WALL_TOP - 0.25, 0), rgb(220, 240, 255)))
	cp(rec, "VaultCeiling", Vector3.new(10.4, 0.2, len - 0.8), L(0, WALL_TOP - 0.1, 0), rgb(90, 94, 102), M.Metal)
	-- colliders : la porte du coffre ouverte laisse entrer
	collider(rec, "ColFloor", Vector3.new(10.6, 0.4, len), L(0, FL - 0.2, 0))
	collider(rec, "ColRoof", Vector3.new(11, 0.6, len), L(0, WALL_TOP + 0.3, 0))
	collider(rec, "ColWallR", Vector3.new(0.6, WALL_TOP - FL, len), L(HW - 0.3, (FL + WALL_TOP) / 2, 0))
	for _, sz in ipairs({ -1, 1 }) do
		local segLen = h - dw / 2
		collider(rec, "ColWallL", Vector3.new(0.6, WALL_TOP - FL, segLen), L(-HW + 0.3, (FL + WALL_TOP) / 2, sz * (dw / 2 + segLen / 2)))
		collider(rec, "ColEnd", Vector3.new(11, WALL_TOP - FL, 0.6), L(0, (FL + WALL_TOP) / 2, sz * (h - 0.3)))
	end
	local gate = collider(rec, "ColVaultDoor", Vector3.new(0.8, 8, dw), L(-HW + 0.4, FL + 4, 0))
	rec.Vault = {
		Shutter = shutterIdx,
		Door = doorIdx,
		Bags = bags,
		Beacon = beacon,
		HackText = hackText,
		HackBg = bg,
		Gate = gate,
		Step = "",
		Open = 0,
		Swing = 0,
	}
end

----------------------------------------------------------------------
-- Construction d'une voiture complète / imposteur
----------------------------------------------------------------------

function TrainModels.BuildCar(kind: string, liveryId: string): CarRec
	local livery = TrainModels.LIVERIES[liveryId] or TrainModels.LIVERIES.Express
	local len = (TrainLine.CARS[kind] or TrainLine.CARS.Coach).Len
	local rec = newRec(kind, len)
	if kind == "Loco" then
		local npcSeats = {}
		loco(rec, livery, npcSeats)
		rec.Npc = npcSeats
	elseif kind == "Vault" then
		vault(rec, livery)
	else
		coach(rec, livery)
	end
	-- (tout part à l'origine : la première pose les met en place)
	return rec
end

function TrainModels.BuildImpostor(kind: string, liveryId: string): CarRec
	local livery = TrainModels.LIVERIES[liveryId] or TrainModels.LIVERIES.Express
	local len = (TrainLine.CARS[kind] or TrainLine.CARS.Coach).Len
	local rec = newRec(kind, len)
	local body = if kind == "Vault" then rgb(118, 124, 132) else livery.Body
	cp(rec, "Body", Vector3.new(11, WALL_TOP - 1.6, len - 0.4), L(0, (1.6 + WALL_TOP) / 2, 0), body, M.Metal)
	cp(rec, "Roof", Vector3.new(9, 1.4, len - 0.6), L(0, WALL_TOP + 0.7, 0), livery.Roof, M.Metal)
	if kind == "Coach" then
		cp(rec, "Windows", Vector3.new(11.1, 3.6, len - 10), L(0, FL + 4.7, 0), rgb(50, 70, 90), M.Glass)
		cp(rec, "Stripe", Vector3.new(11.08, 0.4, len - 0.6), L(0, FL + 2.2, 0), livery.Stripe)
	elseif kind == "Loco" then
		cp(rec, "Windscreen", Vector3.new(10.6, 3.6, 0.2), L(0, FL + 6.6, -len / 2 - 0.05), rgb(40, 60, 80), M.Glass)
		cp(rec, "Stripe", Vector3.new(11.08, 0.5, len - 0.6), L(0, FL + 2.2, 0), livery.Stripe)
		neon(cp(rec, "Lights", Vector3.new(8, 0.8, 0.2), L(0, 4.6, -len / 2 - 0.12), rgb(255, 248, 220)))
	else
		cp(rec, "Hazard", Vector3.new(11.08, 0.7, len - 0.6), L(0, FL + 0.5, 0), YELLOW)
	end
	return rec
end

-- Pose d'une voiture : repère monde de la voiture (origine sur le rail)
local poseFrames: { CFrame } = {}
function TrainModels.Pose(rec: CarRec, cf: CFrame)
	rec.LastCF = cf
	local n = #rec.Parts
	table.clear(poseFrames)
	for i = 1, n do
		poseFrames[i] = cf * rec.Locals[i]
	end
	workspace:BulkMoveTo(rec.Parts, poseFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Colliders solides (train à l'arrêt) ou non (train qui roule)
function TrainModels.SetSolid(rec: CarRec, solid: boolean)
	if rec.Solid == solid then
		return
	end
	rec.Solid = solid
	for _, p in ipairs(rec.Colliders) do
		p.CanCollide = solid
	end
end

-- Portes côté quai : k = 0 (fermées) .. 1 (ouvertes). Louvoiement puis glissement.
function TrainModels.SetDoors(rec: CarRec, k: number)
	k = math.clamp(k, 0, 1)
	if math.abs(rec.DoorOpen - k) < 1e-3 then
		return
	end
	rec.DoorOpen = k
	local pop = math.min(1, k * 4)
	local slide = math.max(0, (k - 0.25) / 0.75)
	slide = slide * slide * (3 - 2 * slide)
	for _, d in ipairs(rec.Doors) do
		if d.Side < 0 then
			local delta = Vector3.new(d.Side * 0.32 * pop, 0, d.Sign * (DOOR_W / 2) * slide)
			rec.Locals[d.Index] = CFrame.new(delta) * rec.Base[d.Index]
		end
	end
end

-- Wagon blindé : étape du casse ("" | "crowbar" | "hack" | "drill" | "grab"),
-- alarme (gyrophare), t (horloge)
local STEP_RANK = { [""] = 0, crowbar = 1, hack = 2, drill = 3, grab = 4 }
function TrainModels.SetVault(rec: CarRec, step: string, alarm: boolean, t: number, dt: number)
	local v = rec.Vault
	if not v then
		return
	end
	local rank = STEP_RANK[step] or 0
	-- volet : ouvert dès le pied-de-biche
	local wantOpen = if rank >= 1 then 1 else 0
	v.Open += math.clamp(wantOpen - v.Open, -dt * 0.8, dt * 0.8)
	local dw = TrainLine.VaultLocal().DoorW
	local slide = v.Open * v.Open * (3 - 2 * v.Open)
	for _, i in ipairs(v.Shutter) do
		rec.Locals[i] = CFrame.new(0, 0, (dw + 0.4) * slide) * rec.Base[i]
	end
	-- porte du coffre : pivote (charnière en z = -dw/2, côté quai) après la perceuse
	local wantSwing = if rank >= 3 then 1 else 0
	v.Swing += math.clamp(wantSwing - v.Swing, -dt * 0.5, dt * 0.5)
	local ang = -math.rad(105) * (v.Swing * v.Swing * (3 - 2 * v.Swing))
	local hinge = CFrame.new(-HW - 0.05, 0, -dw / 2)
	for _, i in ipairs(v.Door) do
		rec.Locals[i] = hinge * CFrame.Angles(0, ang, 0) * hinge:Inverse() * rec.Base[i]
	end
	v.Gate.CanCollide = rec.Solid == true and rank < 3
	-- écran du boîtier
	if v.Step ~= step then
		v.Step = step
		if rank >= 2 then
			v.HackText.Text = "🔓 " .. Locale.T("ACCESS GRANTED")
			v.HackBg.BackgroundColor3 = rgb(20, 130, 60)
		else
			v.HackText.Text = "🔒 " .. Locale.T("LOCKED")
			v.HackBg.BackgroundColor3 = rgb(120, 10, 20)
		end
		-- sacs : ramassés après "grab"
		for _, group in ipairs(v.Bags) do
			for _, p in ipairs(group) do
				p.Transparency = if rank >= 4 then 1 else 0
			end
		end
	end
	-- gyrophare : clignote pendant l'alarme
	local on = alarm and (math.floor(t * 4) % 2 == 0)
	v.Beacon.Material = if on then M.Neon else M.Glass
	v.Beacon.Color = if on then rgb(255, 120, 30) else rgb(120, 60, 30)
end

function TrainModels.SetScreens(rec: CarRec, text: string)
	for _, l in ipairs(rec.Screens) do
		if l.Text ~= text then
			l.Text = text
		end
	end
end

----------------------------------------------------------------------
-- Voie
----------------------------------------------------------------------

local BALLAST = rgb(122, 112, 100)
local SLEEPER = rgb(170, 166, 158)
local RAIL = rgb(110, 104, 98)
local RAIL_TOP = rgb(190, 190, 196)

-- (x, z) près d'un passage à niveau ? (pas de ballast sur la chaussée)
local function onCrossing(count: number, x: number, z: number, margin: number): boolean
	for _, c in ipairs(TrainLine.Crossings(count)) do
		-- distance le long de la route (perpendiculaire à la voie)
		local ax = math.abs((x - c.X) * (1 - math.abs(c.NX)) + (z - c.Z) * (1 - math.abs(c.NZ)))
		local ad = math.abs((x - c.X) * c.NX + (z - c.Z) * c.NZ)
		if ax <= c.Width / 2 + margin and ad <= 14 then
			return true
		end
	end
	return false
end

-- Morceau de voie entre les abscisses s0 et s1. level : 1 = rails + ballast,
-- 2 = + traverses. Les points suivent le tracé (pas de 5 à 20 studs).
function TrainModels.TrackChunk(parent: Instance, count: number, s0: number, s1: number, level: number): Model
	local model = Instance.new("Model")
	model.Name = "Track"
	local O = WorldLayout.Origin()
	local y0 = O.Y
	-- abscisses : points du tracé dans [s0, s1] + bornes
	local path = TrainLine.Path(count)
	local list = { s0 }
	for _, p in ipairs(path.Points) do
		if p.S > s0 + 0.5 and p.S < s1 - 0.5 then
			table.insert(list, p.S)
		end
	end
	table.insert(list, s1)
	local railTop = TrainLine.RAIL_Y
	local railH = 0.32
	local sleeperTop = railTop - railH
	local ballastTop = sleeperTop - 0.22
	for i = 2, #list do
		local a, b = list[i - 1], list[i]
		local ax, az = TrainLine.PointAt(count, a)
		local bx, bz = TrainLine.PointAt(count, b)
		local mx, mz = (ax + bx) / 2, (az + bz) / 2
		local dx, dz = bx - ax, bz - az
		local seg = math.sqrt(dx * dx + dz * dz)
		if seg > 0.05 then
			local crossing = onCrossing(count, mx, mz, 1)
			local look = CFrame.lookAt(Vector3.new(O.X + mx, y0, O.Z + mz), Vector3.new(O.X + mx + dx, y0, O.Z + mz + dz))
			if not crossing then
				local bh = ballastTop - WorldLayout.GROUND_Y + 0.25
				part(model, "Ballast", Vector3.new(8.6, bh, seg), look * CFrame.new(0, ballastTop - bh / 2, 0), BALLAST, M.Pebble)
				if level >= 2 then
					-- accotements (de part et d'autre du ballast, sans le recouvrir)
					for _, sx in ipairs({ -1, 1 }) do
						part(model, "BallastShoulder", Vector3.new(1.4, 0.14, seg), look * CFrame.new(sx * (4.3 + 0.7), WorldLayout.GROUND_Y + 0.02, 0), rgb(104, 96, 88), M.Pebble)
					end
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				local r = part(model, "Rail", Vector3.new(0.36, railH - 0.06, seg), look * CFrame.new(sx * TrainLine.GAUGE / 2, sleeperTop + (railH - 0.06) / 2, 0), RAIL, M.Metal)
				r.CastShadow = false
				part(model, "RailHead", Vector3.new(0.42, 0.06, seg), look * CFrame.new(sx * TrainLine.GAUGE / 2, railTop - 0.03, 0), RAIL_TOP, M.Metal)
			end
		end
	end
	-- traverses : tous les 3 studs
	if level >= 2 then
		local s = math.ceil(s0 / 3) * 3
		while s < s1 do
			local x, z, dx, dz = TrainLine.PointAt(count, s)
			if not onCrossing(count, x, z, 1) then
				local p = Vector3.new(O.X + x, y0 + sleeperTop - 0.13, O.Z + z)
				part(model, "Sleeper", Vector3.new(7.6, 0.26, 0.9), CFrame.lookAt(p, p + Vector3.new(dx, 0, dz)), SLEEPER, M.Concrete)
			end
			s += 3
		end
	end
	model.Parent = parent
	return model
end

----------------------------------------------------------------------
-- Passage à niveau
----------------------------------------------------------------------

export type CrossingRec = { Model: Model, Booms: { any }, Lights: { BasePart }, K: number, On: boolean? }

-- c : TrainLine.Crossings(count)[i]. Repère : origine au centre, -Z = sens de
-- marche du train (le long de la voie), +X = vers l'extérieur (le long de la route)
function TrainModels.Crossing(parent: Instance, c: any): CrossingRec
	local model = Instance.new("Model")
	model.Name = "LevelCrossing"
	local O = WorldLayout.Origin()
	local center = Vector3.new(O.X + c.X, O.Y, O.Z + c.Z)
	-- F : LookVector = sens de marche du train ; +X local = le long de la route (vers l'extérieur)
	local F = CFrame.lookAt(center, center + Vector3.new(-math.sin(c.Yaw), 0, -math.cos(c.Yaw)))
	local roadHalf = c.Width / 2
	local railTop = TrainLine.RAIL_Y
	local road = WorldLayout.ROAD_Y
	-- platelage : entre et autour des rails, au niveau du dessus du rail, + rampes
	local deckLen = c.Width + 2
	local deckH = railTop - road + 0.2
	local inner = TrainLine.GAUGE / 2 - 0.45 -- (bord intérieur des rails)
	local deck = part(model, "CrossingDeck", Vector3.new(2 * inner, deckH, deckLen), F * CFrame.new(0, road + deckH / 2 - 0.2, 0), rgb(60, 60, 64), M.Rubber)
	deck.CanCollide = true
	for _, sx in ipairs({ -1, 1 }) do
		local panel = part(model, "CrossingPanel", Vector3.new(1.6, deckH, deckLen), F * CFrame.new(sx * (TrainLine.GAUGE / 2 + 1.05), road + deckH / 2 - 0.2, 0), rgb(60, 60, 64), M.Rubber)
		panel.CanCollide = true
		-- rampe d'accès (de la chaussée au platelage) : bord haut côté rails
		local ramp = part(model, "CrossingRamp", Vector3.new(deckLen, deckH - 0.2, 3.5),
			F * CFrame.new(sx * (TrainLine.GAUGE / 2 + 1.85 + 1.75), road + (deckH - 0.2) / 2, 0) * CFrame.Angles(0, -sx * math.pi / 2, 0),
			rgb(66, 66, 70), M.Asphalt, "Wedge")
		ramp.CanCollide = true
		-- ligne d'arrêt (fine, au-dessus de la chaussée)
		part(model, "StopLine", Vector3.new(0.8, 0.04, c.Width - 1), F * CFrame.new(sx * c.StopDist, road + 0.02, 0), WHITE)
	end
	local booms = {}
	local lights = {}
	-- 2 demi-barrières : côté intérieur (voitures qui sortent) et extérieur (qui entrent)
	for _, side in ipairs({ -1, 1 }) do
		-- position le long de la route : de part et d'autre de la voie
		local along = side * 9 -- (repère F : +X = extérieur)
		-- circulation à droite : la voiture qui arrive du côté `side` roule vers -side ;
		-- sa droite : (look = -side * X) -> droite = ... poteau du côté -Z * side
		local postZ = -side * (roadHalf + 1.6)
		local postCF = F * CFrame.new(along, 0, postZ)
		part(model, "Post", Vector3.new(0.6, 4.6, 0.6), postCF * CFrame.new(0, road + 2.5, 0), WHITE, M.Metal)
		part(model, "PostBase", Vector3.new(1.4, 0.8, 1.4), postCF * CFrame.new(0, road + 0.4, 0), rgb(150, 150, 150), M.Concrete)
		part(model, "Motor", Vector3.new(1.2, 1.4, 1.0), postCF * CFrame.new(0, road + 3.6, 0), rgb(230, 230, 230), M.Metal)
		-- bras : pivote autour d'un axe horizontal (le long de la voie), du vertical à l'horizontal
		local pivot = postCF * CFrame.new(0, road + 3.8, 0)
		local armLen = roadHalf + 1
		local segs = {}
		local nSeg = 6
		for k = 1, nSeg do
			local sl = armLen / nSeg
			local p = part(model, "Boom", Vector3.new(0.35, 0.35, sl), pivot, if k % 2 == 1 then RED else WHITE, M.SmoothPlastic)
			p.CastShadow = false
			-- repère local du segment : le bras pointe vers -postZ (en travers de la voie de la route)
			table.insert(segs, { Part = p, Offset = (k - 0.5) * sl })
		end
		local lamp = part(model, "BoomLamp", Vector3.new(0.25, 0.25, 0.25), pivot, rgb(120, 20, 20), M.SmoothPlastic, "Ball")
		table.insert(segs, { Part = lamp, Offset = armLen - 0.3, Up = 0.3 })
		local counter = part(model, "Counterweight", Vector3.new(0.9, 0.9, 1.2), pivot, rgb(60, 60, 60), M.Metal)
		table.insert(segs, { Part = counter, Offset = -0.9 })
		table.insert(booms, { Pivot = pivot, Dir = if postZ > 0 then -1 else 1, Segs = segs })
		-- feux + croix de Saint-André (sur un mât, face aux voitures qui arrivent)
		local mastCF = F * CFrame.new(along + side * 1.6, 0, postZ) * CFrame.Angles(0, if side > 0 then -math.pi / 2 else math.pi / 2, 0)
		part(model, "Mast", Vector3.new(0.4, 8.6, 0.4), mastCF * CFrame.new(0, road + 4.3, 0), rgb(240, 240, 240), M.Metal)
		for _, rot in ipairs({ 1, -1 }) do
			part(model, "Crossbuck", Vector3.new(4.2, 0.6, 0.12), mastCF * CFrame.new(0, road + 7.6, -0.3) * CFrame.Angles(0, 0, rot * math.rad(40)), WHITE)
			part(model, "CrossbuckEdge", Vector3.new(4.3, 0.75, 0.08), mastCF * CFrame.new(0, road + 7.6, -0.2) * CFrame.Angles(0, 0, rot * math.rad(40)), RED)
		end
		part(model, "LightBar", Vector3.new(3.2, 0.4, 0.4), mastCF * CFrame.new(0, road + 5.4, -0.3), BLACK, M.Metal)
		for _, lx in ipairs({ -1.2, 1.2 }) do
			part(model, "LightHood", Vector3.new(1.3, 1.3, 0.7), mastCF * CFrame.new(lx, road + 5.4, -0.55), BLACK, M.Metal)
			local lens = part(model, "LightLens", Vector3.new(0.12, 0.9, 0.9), mastCF * CFrame.new(lx, road + 5.4, -0.95) * ALONG_Z, rgb(90, 20, 20), M.Glass, "Cyl")
			table.insert(lights, lens)
		end
	end
	model.Parent = parent
	local rec: CrossingRec = { Model = model, Booms = booms, Lights = lights, K = -1, On = nil }
	return rec
end

-- Barrières (k : 0 levées .. 1 baissées) et feux (clignotent en alternance)
function TrainModels.SetCrossing(rec: CrossingRec, on: boolean, k: number, t: number)
	if math.abs(rec.K - k) > 1e-3 then
		rec.K = k
		local ang = (1 - k) * math.rad(86) -- 86° = levée
		local parts, frames = {}, {}
		for _, b in ipairs(rec.Booms) do
			-- le bras part du pivot vers b.Dir * Z (repère F), relevé de `ang`
			local base = b.Pivot * CFrame.Angles(-b.Dir * ang, 0, 0)
			for _, s in ipairs(b.Segs) do
				table.insert(parts, s.Part)
				table.insert(frames, base * CFrame.new(0, s.Up or 0, b.Dir * s.Offset))
			end
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local phase = math.floor(t * 2.2) % 2
	for i, lens in ipairs(rec.Lights) do
		local lit = on and ((i % 2) == phase)
		lens.Material = if lit then M.Neon else M.Glass
		lens.Color = if lit then rgb(255, 50, 40) else rgb(90, 20, 20)
	end
	rec.On = on
end

----------------------------------------------------------------------
-- Gare
----------------------------------------------------------------------

export type StationRec = { Model: Model, Boards: { TextLabel }, Clock: any?, Name: string }

local BRICK = rgb(170, 92, 70)
local STONE = rgb(214, 206, 192)

-- st : TrainLine.Stations(count)[k]. Repère G : origine sur l'axe de la voie
-- au centre de la gare, au niveau d'Origin().Y ; LookVector = sens de marche ;
-- -X = côté intérieur (quai, bâtiment).
function TrainModels.Station(parent: Instance, count: number, st: any, detail: boolean, clockKit: any?): StationRec
	local model = Instance.new("Model")
	model.Name = "Station_" .. st.Id
	local O = WorldLayout.Origin()
	local p0 = Vector3.new(O.X + st.X, O.Y, O.Z + st.Z)
	local look = Vector3.new(-math.sin(st.Yaw), 0, -math.cos(st.Yaw))
	local G = CFrame.lookAt(p0, p0 + look)
	local off = function(o: number): number
		return o - TrainLine.OFF_OUT -- décalage (depuis l'axe de la ceinture) -> x local (négatif = intérieur)
	end
	local half = TrainLine.PLATFORM_LEN / 2
	local PY = TrainLine.PLATFORM_Y
	local ground = WorldLayout.GROUND_Y
	local walk = WorldLayout.WALK_Y
	local boards = {}
	-- QUAI
	local x0, x1 = off(TrainLine.PLATFORM_IN), off(TrainLine.PLATFORM_OUT) -- -20, -6
	local pw = x1 - x0
	local plat = part(model, "Platform", Vector3.new(pw - 0.6, PY - ground + 0.3, 2 * half), G * CFrame.new((x0 + x1) / 2 - 0.3, (PY + ground - 0.3) / 2, 0), rgb(176, 170, 162), M.Concrete)
	plat.CanCollide = true
	local edge = part(model, "PlatformEdge", Vector3.new(0.6, PY - ground + 0.3, 2 * half), G * CFrame.new(x1 - 0.3, (PY + ground - 0.3) / 2, 0), STONE, M.Slate)
	edge.CanCollide = true
	part(model, "SafetyLine", Vector3.new(0.5, 0.04, 2 * half - 1), G * CFrame.new(x1 - 1.5, PY + 0.02, 0), YELLOW)
	part(model, "TactileStrip", Vector3.new(0.8, 0.05, 2 * half - 1), G * CFrame.new(x1 - 2.4, PY + 0.025, 0), rgb(236, 236, 230), M.Slate)
	-- extrémités du quai : garde-corps (≥ 3,5)
	for _, sz in ipairs({ -1, 1 }) do
		part(model, "EndRail", Vector3.new(pw - 1, 0.25, 0.25), G * CFrame.new((x0 + x1) / 2, PY + 3.5, sz * (half - 0.3)), rgb(60, 70, 80), M.Metal)
		for _, px in ipairs({ x0 + 0.6, (x0 + x1) / 2, x1 - 0.8 }) do
			part(model, "EndRailPost", Vector3.new(0.25, 3.5, 0.25), G * CFrame.new(px, PY + 1.75, sz * (half - 0.3)), rgb(60, 70, 80), M.Metal)
		end
	end
	-- BÂTIMENT VOYAGEURS (au niveau du trottoir)
	local b0, b1 = off(TrainLine.BUILDING_IN), off(TrainLine.BUILDING_OUT) -- -52, -26
	local bw, bl = b1 - b0, TrainLine.BUILDING_LEN
	local bh = 16
	local floorY = walk
	local hall = Instance.new("Model")
	hall.Name = "Building"
	hall.Parent = model
	local slab = part(hall, "HallFloor", Vector3.new(bw, floorY - ground + 0.3, bl), G * CFrame.new((b0 + b1) / 2, (floorY + ground - 0.3) / 2, 0), rgb(200, 190, 176), M.Marble)
	slab.CanCollide = true
	local function wall(name: string, size: Vector3, cf: CFrame, color: Color3?, mat: Enum.Material?)
		local w = part(hall, name, size, cf, color or BRICK, mat or M.Brick)
		w.CanCollide = true
		return w
	end
	local doorW, doorH = 8, 10
	-- façade côté ville (x = b0) et côté quai (x = b1) : portes au centre + baies
	for _, side in ipairs({ -1, 1 }) do
		local xw = if side < 0 then b0 + 0.5 else b1 - 0.5
		-- pans de mur entre ouvertures : [-bl/2, -doorW/2] et [doorW/2, bl/2] avec 2 baies chacun
		for _, sz in ipairs({ -1, 1 }) do
			local zA, zB = doorW / 2, bl / 2
			local segL = zB - zA
			wall("WallLow", Vector3.new(1, 3.5, segL), G * CFrame.new(xw, floorY + 1.75, sz * (zA + segL / 2)))
			wall("WallHigh", Vector3.new(1, bh - 11.5, segL), G * CFrame.new(xw, floorY + 11.5 + (bh - 11.5) / 2, sz * (zA + segL / 2)))
			-- baies : 3 piliers, 2 vitrages
			local winW = (segL - 3 * 2) / 2
			for k = 0, 2 do
				local zp = zA + 1 + k * (winW + 2)
				wall("Pier", Vector3.new(1, 8, 2), G * CFrame.new(xw, floorY + 3.5 + 4, sz * zp))
			end
			for k = 0, 1 do
				local zc = zA + 2 + winW / 2 + k * (winW + 2)
				local g = part(hall, "Bay", Vector3.new(0.2, 8, winW), G * CFrame.new(xw, floorY + 7.5, sz * zc), rgb(150, 190, 210), M.Glass)
				g.Transparency = 0.45
				g.CanCollide = true
				-- arc de briques claires au-dessus de la baie
				part(hall, "BayArch", Vector3.new(1.1, 0.6, winW + 0.4), G * CFrame.new(xw, floorY + 11.83, sz * zc), STONE, M.Slate)
				part(hall, "Mullion", Vector3.new(0.3, 8, 0.25), G * CFrame.new(xw, floorY + 7.5, sz * zc), rgb(60, 60, 70), M.Metal)
			end
		end
		-- linteau de la porte
		wall("DoorLintel", Vector3.new(1, bh - doorH, doorW), G * CFrame.new(xw, floorY + doorH + (bh - doorH) / 2, 0))
		part(hall, "DoorCanopy", Vector3.new(3, 0.4, doorW + 3), G * CFrame.new(xw + side * 1.8, floorY + doorH + 0.6, 0), rgb(60, 64, 72), M.Metal)
	end
	-- pignons
	for _, sz in ipairs({ -1, 1 }) do
		wall("Gable", Vector3.new(bw, bh, 1), G * CFrame.new((b0 + b1) / 2, floorY + bh / 2, sz * (bl / 2 - 0.5)))
	end
	-- corniche, toit à deux pans (ardoise), lanterneau
	part(hall, "Cornice", Vector3.new(bw + 1.6, 1, bl + 1.6), G * CFrame.new((b0 + b1) / 2, floorY + bh + 0.5, 0), STONE, M.Slate)
	local roofH = 7
	for _, side in ipairs({ -1, 1 }) do
		part(hall, "RoofPane", Vector3.new(bl + 2, roofH, bw / 2 + 0.8), G * CFrame.new((b0 + b1) / 2 + side * (bw / 4 + 0.4), floorY + bh + 1 + roofH / 2, 0) * CFrame.Angles(0, if side < 0 then math.pi / 2 else -math.pi / 2, 0), rgb(70, 76, 90), M.Slate, "Wedge")
	end
	-- plafond intérieur + lustres doux
	part(hall, "HallCeiling", Vector3.new(bw - 2, 0.4, bl - 2), G * CFrame.new((b0 + b1) / 2, floorY + bh - 0.2, 0), rgb(240, 234, 222))
	-- horloge de façade (côté ville)
	if clockKit and type(clockKit.Build) == "function" then
		pcall(function()
			local cf = G * CFrame.new(b0 - 0.2, floorY + bh + 3.6, 0) * CFrame.Angles(0, math.pi / 2, 0)
			clockKit.Build(hall, cf, 4.2, { Style = "Wall" })
		end)
	end
	-- enseigne (côté ville et côté quai)
	for _, side in ipairs({ -1, 1 }) do
		local xs = if side < 0 then b0 - 0.08 else b1 + 0.08
		local sign = part(hall, "NameSign", Vector3.new(0.12, 2.2, 26), G * CFrame.new(xs, floorY + 13.3, 0), rgb(24, 40, 70))
		local g = canvasGui(part(hall, "NameCanvas", Vector3.new(0.04, 2.0, 25.6), G * CFrame.new(xs + side * 0.1, floorY + 13.3, 0), WHITE), if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left, 30)
		label(g, "🚉 " .. Locale.T(st.Name), WHITE, Enum.Font.GothamBold)
		-- (canvas : face vers l'extérieur ; l'enseigne est un panneau plein)
		local _ = sign
		g.Face = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
	end
	-- marches du bâtiment au quai (contremarches <= 1)
	local stepsX0, stepsX1 = b1, x0 -- -26 .. -20
	local rise = PY - floorY
	local nSteps = math.max(1, math.ceil(rise / 0.8))
	local tread = (stepsX1 - stepsX0) / nSteps
	for k = 1, nSteps do
		local top = floorY + rise * k / nSteps
		local s = part(model, "Step", Vector3.new(tread, top - ground, 16), G * CFrame.new(stepsX0 + (k - 0.5) * tread, (top + ground) / 2, 0), rgb(186, 180, 170), M.Concrete)
		s.CanCollide = true
	end
	-- main courante des marches
	for _, sz in ipairs({ -1, 1 }) do
		part(model, "StepRail", Vector3.new(stepsX1 - stepsX0 + 0.6, 0.22, 0.22), G * CFrame.new((stepsX0 + stepsX1) / 2, (floorY + PY) / 2 + 3.2, sz * 8.2) * CFrame.Angles(0, 0, math.atan2(rise, stepsX1 - stepsX0)), rgb(60, 70, 80), M.Metal)
	end
	-- parvis côté trottoir (16..18)
	local fx0 = off(TrainLine.STATION_IN)
	local fore = part(model, "Forecourt", Vector3.new(b0 - fx0, floorY - ground + 0.28, bl + 10), G * CFrame.new((fx0 + b0) / 2, (floorY + ground - 0.28) / 2, 0), rgb(196, 188, 176), M.Slate)
	fore.CanCollide = true
	-- remblai sous le quai côté bâtiment (entre les marches et les bouts du quai)
	for _, sz in ipairs({ -1, 1 }) do
		local zA, zB = 8.4, half
		local fill = part(model, "PlatformFill", Vector3.new(stepsX1 - stepsX0, PY - ground + 0.3, zB - zA), G * CFrame.new((stepsX0 + stepsX1) / 2, (PY + ground - 0.3) / 2, sz * (zA + zB) / 2), rgb(170, 164, 156), M.Concrete)
		fill.CanCollide = true
	end
	-- MARQUISE du quai (colonnes en fonte, toiture vitrée)
	local cx = (x0 + x1) / 2 - 2.5
	local cLen = 130
	for k = -4, 4 do
		local z = k * (cLen / 8)
		part(model, "Column", Vector3.new(0.7, 9.6, 0.7), G * CFrame.new(cx, PY + 4.8, z), rgb(40, 70, 60), M.Metal)
		part(model, "ColumnCap", Vector3.new(1.4, 0.6, 1.4), G * CFrame.new(cx, PY + 9.7, z), rgb(40, 70, 60), M.Metal)
		part(model, "Bracket", Vector3.new(12, 0.4, 0.4), G * CFrame.new(cx + 1, PY + 9.9, z) * CFrame.Angles(0, 0, math.rad(4)), rgb(40, 70, 60), M.Metal)
	end
	local canopy = part(model, "Canopy", Vector3.new(14.5, 0.4, cLen + 4), G * CFrame.new(cx + 1, PY + 10.4, 0) * CFrame.Angles(0, 0, math.rad(4)), rgb(180, 210, 220), M.Glass)
	canopy.Transparency = 0.3
	part(model, "CanopyBeam", Vector3.new(0.5, 0.8, cLen + 3), G * CFrame.new(cx + 1, PY + 10.0, 0), rgb(40, 70, 60), M.Metal)
	part(model, "Valance", Vector3.new(0.2, 1.0, cLen + 4), G * CFrame.new(cx + 8.2, PY + 10.4, 0), rgb(232, 226, 210), M.Wood)
	-- éclairage doux sous la marquise (verres "NightGlow")
	for k = -3, 3 do
		local lamp = part(model, "CanopyLamp", Vector3.new(1.4, 0.3, 1.4), G * CFrame.new(cx + 1, PY + 9.55, k * 18 + 9), rgb(255, 236, 190), M.SmoothPlastic, "Cyl")
		lamp.CFrame = lamp.CFrame * UPRIGHT
		lamp:SetAttribute("NightGlow", true)
	end
	-- bancs, poubelles, distributeur, panneau du nom (sur le quai)
	if detail then
		for k = -3, 3 do
			if k ~= 0 then
				local z = k * 18
				local bcf = G * CFrame.new(x0 + 1.6, PY, z) * CFrame.Angles(0, -math.pi / 2, 0)
				-- (assise 1,85, dossier ~3,8 : cibles SCALE11 ; banc décoratif)
				part(model, "BenchSeat", Vector3.new(5.6, 0.25, 2.0), bcf * CFrame.new(0, 1.73, 0), rgb(150, 100, 60), M.Wood)
				part(model, "BenchBack", Vector3.new(5.6, 1.6, 0.2), bcf * CFrame.new(0, 2.9, 1.0) * CFrame.Angles(math.rad(-10), 0, 0), rgb(150, 100, 60), M.Wood)
				for _, lx in ipairs({ -2.4, 2.4 }) do
					part(model, "BenchLeg", Vector3.new(0.3, 1.6, 1.8), bcf * CFrame.new(lx, 0.8, 0.1), rgb(40, 50, 50), M.Metal)
				end
			end
		end
		for _, z in ipairs({ -60, 60 }) do
			part(model, "Bin", Vector3.new(1.4, 2.6, 1.4), G * CFrame.new(x0 + 1.4, PY + 1.3, z) * UPRIGHT, rgb(40, 90, 60), M.Metal, "Cyl")
		end
		part(model, "TicketMachine", Vector3.new(1.4, 5.2, 2.2), G * CFrame.new(x0 + 1.0, PY + 2.6, 30), rgb(30, 90, 160), M.Metal)
		local tm = part(model, "TicketScreen", Vector3.new(0.05, 1.1, 1.4), G * CFrame.new(x0 + 1.73, PY + 3.6, 30), rgb(120, 200, 255))
		neon(tm)
		for _, z in ipairs({ -45, 45 }) do
			local pole = G * CFrame.new(x1 - 4, PY, z)
			part(model, "SignPole", Vector3.new(0.3, 9, 0.3), pole * CFrame.new(-2.4, 4.5, 0), rgb(40, 50, 60), M.Metal)
			part(model, "SignPole", Vector3.new(0.3, 9, 0.3), pole * CFrame.new(2.4, 4.5, 0), rgb(40, 50, 60), M.Metal)
			part(model, "PlatformSign", Vector3.new(5.6, 1.4, 0.2), pole * CFrame.new(0, 8.4, 0), rgb(24, 40, 70))
			for _, face in ipairs({ -1, 1 }) do
				local cv = part(model, "PlatformSignCanvas", Vector3.new(5.4, 1.2, 0.04), pole * CFrame.new(0, 8.4, face * 0.18), WHITE)
				local g = canvasGui(cv, if face < 0 then Enum.NormalId.Front else Enum.NormalId.Back, 50)
				label(g, Locale.T(st.Name), WHITE, Enum.Font.GothamBold)
			end
		end
	end
	-- TABLEAU DES DÉPARTS (2 faces, sous la marquise) + dans le hall
	local function board(cf: CFrame, w: number, h: number, faceIn: Enum.NormalId)
		part(model, "BoardFrame", Vector3.new(w + 0.4, h + 0.4, 0.3), cf, rgb(30, 32, 38), M.Metal)
		local cv = part(model, "BoardCanvas", Vector3.new(w, h, 0.04), cf * CFrame.new(0, 0, if faceIn == Enum.NormalId.Front then -0.18 else 0.18), BLACK)
		local g = canvasGui(cv, faceIn, 40)
		g.LightInfluence = 0
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = rgb(16, 20, 32)
		bg.BorderSizePixel = 0
		bg.Parent = g
		local title = label(bg, "🚉 " .. Locale.T(st.Name), rgb(255, 210, 90), Enum.Font.GothamBold, UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.03, 0.04), Enum.TextXAlignment.Left)
		local _ = title
		local l = label(bg, "", WHITE, Enum.Font.Code, UDim2.fromScale(0.94, 0.62), UDim2.fromScale(0.03, 0.34), Enum.TextXAlignment.Left)
		l.TextYAlignment = Enum.TextYAlignment.Top
		table.insert(boards, l)
	end
	local bcf = G * CFrame.new(cx + 1, PY + 8.0, -6)
	board(bcf * CFrame.Angles(0, math.pi / 2, 0), 7, 2.6, Enum.NormalId.Front)
	board(bcf * CFrame.new(0, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), 7, 2.6, Enum.NormalId.Front)
	-- hall : tableau sur le pignon, guichet, bancs
	board(G * CFrame.new((b0 + b1) / 2, floorY + 9, -bl / 2 + 1.2), 12, 4, Enum.NormalId.Back)
	if detail then
		local counter = part(hall, "TicketCounter", Vector3.new(4, 3.3, 16), G * CFrame.new(b0 + 6, floorY + 1.65, 20), rgb(150, 110, 70), M.Wood)
		counter.CanCollide = true
		part(hall, "CounterTop", Vector3.new(4.4, 0.2, 16.4), G * CFrame.new(b0 + 6, floorY + 3.4, 20), rgb(60, 40, 30), M.Wood)
		local glassPane = part(hall, "CounterGlass", Vector3.new(0.15, 3.6, 15), G * CFrame.new(b0 + 6.5, floorY + 5.3, 20), rgb(190, 220, 230), M.Glass)
		glassPane.Transparency = 0.6
		for k = -1, 1 do
			local bench = G * CFrame.new((b0 + b1) / 2 + 2, floorY, -12 + k * 9) * CFrame.Angles(0, math.pi / 2, 0)
			part(hall, "HallBench", Vector3.new(6, 0.3, 2.2), bench * CFrame.new(0, 1.7, 0), rgb(120, 80, 50), M.Wood)
			part(hall, "HallBenchBack", Vector3.new(6, 2.2, 0.25), bench * CFrame.new(0, 2.9, 1.0), rgb(120, 80, 50), M.Wood)
			part(hall, "HallBenchFoot", Vector3.new(5.6, 1.55, 1.6), bench * CFrame.new(0, 0.78, 0), rgb(50, 50, 56), M.Metal)
		end
		for k = -1, 1, 2 do
			local chand = part(hall, "HallLamp", Vector3.new(2.2, 1.2, 2.2), G * CFrame.new((b0 + b1) / 2, floorY + bh - 2.4, k * 18), rgb(255, 232, 180), M.SmoothPlastic, "Ball")
			chand:SetAttribute("NightGlow", true)
			part(hall, "HallLampRod", Vector3.new(0.15, 1.8, 0.15), G * CFrame.new((b0 + b1) / 2, floorY + bh - 1.0, k * 18), rgb(60, 50, 40), M.Metal)
		end
		for _, z in ipairs({ -38, 38 }) do
			part(hall, "Planter", Vector3.new(2.4, 2.4, 2.4), G * CFrame.new(b0 + 2.2, floorY + 1.2, z), rgb(150, 80, 60), M.Slate)
			part(hall, "Plant", Vector3.new(3.2, 3.2, 3.2), G * CFrame.new(b0 + 2.2, floorY + 3.6, z), rgb(60, 140, 70), M.Grass, "Ball")
		end
	end
	-- horloge de quai (double face, sous la marquise)
	local clock = nil
	if clockKit and type(clockKit.Build) == "function" then
		pcall(function()
			clock = clockKit.Build(model, G * CFrame.new(cx + 1.45, PY + 8.2, 10) * CFrame.Angles(0, math.pi / 2, 0), 2.4, { Style = "Station" })
		end)
	end
	model.Parent = parent
	return { Model = model, Boards = boards, Clock = clock, Name = st.Name }
end

-- Gare vue de loin : 4 blocs
function TrainModels.StationImpostor(parent: Instance, count: number, st: any): Model
	local model = Instance.new("Model")
	model.Name = "StationFar_" .. st.Id
	local O = WorldLayout.Origin()
	local function rectPart(name: string, r: any, y0: number, y1: number, color: Color3, mat: Enum.Material)
		part(model, name, Vector3.new(r.W, y1 - y0, r.D), CFrame.new(O.X + r.X, O.Y + (y0 + y1) / 2, O.Z + r.Z), color, mat)
	end
	rectPart("Platform", st.Platform, WorldLayout.GROUND_Y - 0.3, TrainLine.PLATFORM_Y, rgb(176, 170, 162), M.Concrete)
	rectPart("Building", st.Building, WorldLayout.GROUND_Y - 0.3, WorldLayout.WALK_Y + 16, BRICK, M.Brick)
	local roofR = { X = st.Building.X, Z = st.Building.Z, W = st.Building.W + 1, D = st.Building.D + 1 }
	rectPart("Roof", roofR, WorldLayout.WALK_Y + 16, WorldLayout.WALK_Y + 18, rgb(70, 76, 90), M.Slate)
	local _ = count
	model.Parent = parent
	return model
end

----------------------------------------------------------------------
-- Planque (fin du braquage)
----------------------------------------------------------------------

function TrainModels.Hideout(parent: Instance, h: any): Model
	local model = Instance.new("Model")
	model.Name = "Hideout"
	local O = WorldLayout.Origin()
	local p0 = Vector3.new(O.X + h.X, O.Y + WorldLayout.GROUND_Y, O.Z + h.Z)
	local F = CFrame.new(p0) * CFrame.Angles(0, h.Yaw, 0) -- (LookVector : vers la ville)
	local W, D = h.W, h.D
	local wood = rgb(130, 70, 50)
	local plank = rgb(150, 90, 60)
	-- grange : murs de planches, grande porte ouverte côté ville (-Z local)
	local wallH = 11
	for _, sx in ipairs({ -1, 1 }) do
		local w = part(model, "BarnSide", Vector3.new(0.8, wallH, D), F * CFrame.new(sx * (W / 2 - 0.4), wallH / 2, 4), wood, M.WoodPlanks)
		w.CanCollide = true
	end
	local back = part(model, "BarnBack", Vector3.new(W, wallH, 0.8), F * CFrame.new(0, wallH / 2, 4 + D / 2 - 0.4), wood, M.WoodPlanks)
	back.CanCollide = true
	for _, sx in ipairs({ -1, 1 }) do
		local f = part(model, "BarnFront", Vector3.new(W / 2 - 5, wallH, 0.8), F * CFrame.new(sx * (W / 4 + 2.5), wallH / 2, 4 - D / 2 + 0.4), wood, M.WoodPlanks)
		f.CanCollide = true
		-- vantaux ouverts (avec la croix blanche)
		local leafCF = F * CFrame.new(sx * 5.4, 0, 4 - D / 2 - 2.6) * CFrame.Angles(0, sx * math.rad(70), 0)
		part(model, "BarnDoor", Vector3.new(5, 9, 0.5), leafCF * CFrame.new(0, 4.5, 0), plank, M.WoodPlanks)
		for _, rot in ipairs({ 1, -1 }) do
			part(model, "DoorX", Vector3.new(6.4, 0.5, 0.2), leafCF * CFrame.new(0, 4.5, -0.33) * CFrame.Angles(0, 0, rot * math.atan2(9, 5)), WHITE, M.Wood)
		end
	end
	part(model, "BarnLintel", Vector3.new(10, wallH - 9, 0.8), F * CFrame.new(0, 9 + (wallH - 9) / 2, 4 - D / 2 + 0.4), wood, M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "BarnRoof", Vector3.new(D + 2, 6, W / 2 + 1), F * CFrame.new(sx * (W / 4 + 0.5), wallH + 3, 4) * CFrame.Angles(0, if sx < 0 then math.pi / 2 else -math.pi / 2, 0), rgb(110, 50, 40), M.CorrodedMetal, "Wedge")
	end
	part(model, "BarnFloor", Vector3.new(W - 1.6, 0.3, D - 1.6), F * CFrame.new(0, 0.15, 4), rgb(160, 130, 80), M.Wood)
	-- bottes de paille, caisses, lanterne, cercle de dépôt
	for k = 0, 3 do
		part(model, "HayBale", Vector3.new(4, 2.6, 2.6), F * CFrame.new(-W / 2 + 3.5, 1.3 + math.floor(k / 2) * 2.6, 8 + (k % 2) * 2.8), rgb(222, 196, 110), M.Grass)
	end
	for k = 0, 2 do
		part(model, "Crate", Vector3.new(2.6, 2.6, 2.6), F * CFrame.new(W / 2 - 3.5, 1.3 + (if k == 2 then 2.6 else 0), 6 + (k % 2) * 3), rgb(170, 130, 80), M.WoodPlanks)
	end
	local lantern = part(model, "Lantern", Vector3.new(0.8, 1.1, 0.8), F * CFrame.new(0, 9.6, 4 - D / 2 - 0.7), rgb(255, 210, 130))
	lantern:SetAttribute("NightGlow", true)
	local ring = part(model, "DropRing", Vector3.new(0.12, 12, 12), F * CFrame.new(0, 0.38, -2) * UPRIGHT, rgb(255, 200, 40), M.Neon, "Cyl")
	ring.Transparency = 0.55
	local inner = part(model, "DropInner", Vector3.new(0.14, 10.6, 10.6), F * CFrame.new(0, 0.39, -2) * UPRIGHT, rgb(60, 50, 40), M.Ground, "Cyl")
	inner.Transparency = 0.2
	-- panneau "Planque"
	local post = part(model, "SignPost", Vector3.new(0.4, 6, 0.4), F * CFrame.new(-W / 2 - 3, 3, -D / 2), plank, M.Wood)
	local _p = post
	local board = part(model, "SignBoard", Vector3.new(5, 1.6, 0.3), F * CFrame.new(-W / 2 - 3, 5.4, -D / 2), plank, M.Wood)
	local _b = board
	local cv = part(model, "SignCanvas", Vector3.new(4.8, 1.4, 0.04), F * CFrame.new(-W / 2 - 3, 5.4, -D / 2 - 0.2), WHITE)
	local g = canvasGui(cv, Enum.NormalId.Front, 40)
	label(g, "🕶️ " .. Locale.T("Hideout"), rgb(255, 230, 160), Enum.Font.Cartoon)
	model.Parent = parent
	return model
end

TrainModels.TAU = TAU

return TrainModels
