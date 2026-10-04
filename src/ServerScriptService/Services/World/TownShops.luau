--[[
	TownShops (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownShops

	🛍️ Les BOUTIQUES OÙ L'ON ENTRE de Dopamine Town (v9.6) : le serveur ne
	construit que la COQUE (collisions justes pour tous les joueurs) ; tout
	l'intérieur (étagères, comptoir, objets 3D à acheter, étiquettes,
	lumières) est construit par chaque client (Client/World/ShopInteriors),
	en flux, car les modèles 3D des objets n'existent que côté client.
	  - 6 boutiques autour de la place (TownPlaza) : 🐾 Animalerie,
	    🍰 Cuisine & Maison, 🛋️ Meubles & Déco, 🖥️ Setup Store,
	    🪴 Jardinerie, 🧸 Jouets. Façade vitrine (deux grandes vitres,
	    VRAIE porte de 6 studs à portes coulissantes vitrées que le client
	    ouvre à l'approche), enseigne traduisible, stores, enseigne en
	    drapeau, étage avec fenêtres, toit ; murs, sol et plafond solides ;
	  - la 🚗 CONCESSION AUTO (v9.8 : hors de la porte, à gauche de la route
	    d'arrivée, WorldLayout.DealershipCFrame) : grand hall vitré 70 x 50,
	    porte de 14 studs pour les voitures, 8 podiums "CarSlot_<n>"
	    (attribut CarCF : sol du podium, LookVector = avant de la voiture),
	    parvis pavé avec le socle du plateau tournant (attributs
	    TurntableCF / TurntableR), totem ; décor : client (DealerShowroom).
	Repère d'une boutique (`cf`) : milieu du pied de la façade au niveau
	des trottoirs (WALK_Y), LookVector vers la rue, volume derrière (+Z).

	Contrat (client ShopInteriors / GARAGE96) : chaque boutique est un Model
	du dossier DopamineTown.Shops avec les attributs
	  ShopId       "Pets" | "Kitchen" | "Furniture" | "Setup" | "Garden" | "Toys" | "Cars"
	  ShopName     clé anglaise de l'enseigne (le client traduit)
	  ShopKind     "Items" | "Cars"
	  InteriorCF   CFrame : centre du SOL intérieur (dessus du plancher),
	               mêmes axes que `cf` (LookVector vers la rue / la porte)
	  InteriorSize Vector3 (largeur, hauteur sous plafond, profondeur)
	  DoorCF       CFrame : seuil de la porte (sol), LookVector vers la rue
	  AllowCars    (concession seulement) les voitures peuvent entrer
	  ShowroomSlots (concession) nombre de plateaux "CarSlot_<n>"
	Les vantaux vitrés s'appellent "DoorPanel" (attribut SlideX : de combien
	de studs le client les fait glisser le long de leur axe X pour ouvrir) ;
	ils ne bloquent jamais (CanCollide false).
	Aucune vraie lumière ici (l'intérieur a ses ≤ 2 lampes côté client).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownBuildings = require(script.Parent.TownBuildings)

local TownShops = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

-- Gabarit des boutiques de la place (tient 6 fois dans la couronne, quel
-- que soit le nombre de parcelles : voir TownPlaza.shopRing)
TownShops.W = 30
TownShops.D = 24
local FLOOR_TOP = 0.2 -- dessus du plancher (léger seuil depuis le trottoir)
local CEIL = 11.4 -- dessous du plafond
local WALL_TOP = 12.6 -- haut des murs du rez-de-chaussée (dans le corps de l'étage)
local BODY_Y = 12.5 -- bas du corps de l'étage
local UPPER_H = TownBuildings.FLOOR_H -- un étage au-dessus (non visitable)
local DOOR_W = 6
local DOOR_H = 9
local WIN_X0, WIN_X1 = 4.5, 12.6 -- vitrines (de chaque côté de la porte)
local WIN_Y0 = 1.8

export type ShopSpec = {
	Id: string,
	Sign: string,
	Icon: string,
	Wall: Color3,
	Material: Enum.Material,
	Front: Color3, -- devanture (piliers, bandeau)
	Trim: Color3,
	Awning: { Color3 },
	Roof: string, -- "Gable" | "Flat"
	RoofColor: Color3,
	SignColor: Color3,
	Shutters: Color3?,
}

-- Ordre = ordre de placement autour de la place (depuis l'avenue)
TownShops.SPECS = {
	{ Id = "Pets", Sign = "🐾 Pet Shop", Icon = "🐾", Wall = Color3.fromRGB(255, 228, 204), Material = M.Plaster, Front = Color3.fromRGB(86, 164, 146),
		Trim = C.White, Awning = { Color3.fromRGB(112, 200, 172), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(150, 98, 90),
		SignColor = Color3.fromRGB(226, 110, 60), Shutters = Color3.fromRGB(112, 190, 170) },
	{ Id = "Toys", Sign = "🧸 Toy Shop", Icon = "🧸", Wall = Color3.fromRGB(255, 216, 156), Material = M.Plaster, Front = Color3.fromRGB(236, 104, 140),
		Trim = C.White, Awning = { Color3.fromRGB(255, 150, 96), Color3.fromRGB(255, 238, 130) }, Roof = "Gable", RoofColor = Color3.fromRGB(168, 92, 122),
		SignColor = Color3.fromRGB(236, 72, 140), Shutters = Color3.fromRGB(120, 180, 250) },
	{ Id = "Kitchen", Sign = "🍰 Kitchen & Home", Icon = "🍰", Wall = Color3.fromRGB(255, 238, 236), Material = M.Brick, Front = Color3.fromRGB(206, 84, 104),
		Trim = C.White, Awning = { Color3.fromRGB(236, 112, 132), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(116, 108, 140),
		SignColor = Color3.fromRGB(206, 70, 96), Shutters = Color3.fromRGB(150, 206, 180) },
	{ Id = "Furniture", Sign = "🛋️ Furniture & Decor", Icon = "🛋️", Wall = Color3.fromRGB(240, 228, 212), Material = M.Plaster, Front = Color3.fromRGB(118, 94, 78),
		Trim = Color3.fromRGB(255, 250, 240), Awning = { Color3.fromRGB(190, 146, 108), C.Cream }, Roof = "Flat", RoofColor = Color3.fromRGB(120, 110, 100),
		SignColor = Color3.fromRGB(118, 84, 60) },
	{ Id = "Setup", Sign = "🖥️ Setup Store", Icon = "🖥️", Wall = Color3.fromRGB(88, 80, 124), Material = M.Brick, Front = Color3.fromRGB(44, 40, 66),
		Trim = Color3.fromRGB(214, 210, 236), Awning = { Color3.fromRGB(78, 68, 136), Color3.fromRGB(120, 214, 250) }, Roof = "Flat", RoofColor = Color3.fromRGB(70, 66, 90),
		SignColor = Color3.fromRGB(90, 70, 200) },
	{ Id = "Garden", Sign = "🪴 Garden Centre", Icon = "🪴", Wall = Color3.fromRGB(218, 238, 208), Material = M.Plaster, Front = Color3.fromRGB(84, 138, 88),
		Trim = C.White, Awning = { Color3.fromRGB(126, 192, 112), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(104, 128, 92),
		SignColor = Color3.fromRGB(64, 140, 80), Shutters = Color3.fromRGB(236, 150, 170) },
} :: { ShopSpec }

TownShops.DEALER = { Id = "Cars", Sign = "🚗 Car Dealership", Icon = "🚗" }
TownShops.DEALER_W = WorldLayout.DEALER_W -- (v9.8) 44 -> 70
TownShops.DEALER_D = WorldLayout.DEALER_D -- (v9.8) 48 -> 50

local GLASS = Color3.fromRGB(196, 228, 246)

local function glass(parent: Instance, name: string, size: Vector3, cf: CFrame, transparency: number): BasePart
	-- (vitre : bloque les avatars, ne gêne pas les rayons de la caméra)
	local g = part(parent, name, size, cf, GLASS, M.Glass, "prop")
	g.Transparency = transparency
	g.Reflectance = 0.12
	return g
end

-- Boîte entre deux coins (repère `cf`)
local function box(parent: Instance, name: string, cf: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, profile: string?): BasePart
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, profile)
end

-- Vantail vitré coulissant (le client le fait glisser de `slide` studs sur X)
local function doorPanel(parent: Instance, cf: CFrame, w: number, h: number, slide: number): BasePart
	local panel = part(parent, "DoorPanel", Vector3.new(w, h, 0.15), cf, GLASS, M.Glass, "deco")
	panel.Transparency = 0.45
	panel.Reflectance = 0.15
	panel:SetAttribute("SlideX", slide)
	return panel
end

-- Petit panneau texte (SurfaceGui) traduisible
local function plaque(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3, pps: number, maxDistance: number): BasePart
	local board = part(parent, name, size, cf, color, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, pps, nil, maxDistance, 0.3)
	TownKit.Label(body, "Text", text, 0.06, 0.1, 0.88, 0.8, textColor, Enum.Font.FredokaOne, true)
	return board
end

-- Store rayé au-dessus d'une vitrine (lames inclinées + lambrequin)
local function awning(parent: Instance, cf: CFrame, x0: number, x1: number, top: number, colors: { Color3 })
	local width = x1 - x0
	local n = math.max(2, math.floor(width / 2.6 + 0.5))
	local sw = width / n
	local tilt = CFrame.Angles(math.rad(22), 0, 0)
	for i = 1, n do
		local x = x0 + (i - 0.5) * sw
		part(parent, "Awning", Vector3.new(sw, 0.2, 3.2), cf * CFrame.new(x, top - 0.6, -1.58) * tilt, colors[i % 2 + 1], M.Fabric, i == 1 and "decoS" or "deco")
	end
	part(parent, "Valance", Vector3.new(width, 0.6, 0.12), cf * CFrame.new((x0 + x1) / 2, top - 1.5, -3.06), colors[1], M.Fabric, "deco")
end

local function attributes(model: Model, spec: { Id: string, Sign: string, Icon: string }, kind: string, interiorCF: CFrame, size: Vector3, doorCF: CFrame)
	model:SetAttribute("ShopId", spec.Id)
	model:SetAttribute("ShopName", spec.Sign)
	model:SetAttribute("ShopIcon", spec.Icon)
	model:SetAttribute("ShopKind", kind)
	model:SetAttribute("InteriorCF", interiorCF)
	model:SetAttribute("InteriorSize", size)
	model:SetAttribute("DoorCF", doorCF)
end

----------------------------------------------------------------------
-- Boutique de la place (coque visitable, ≈ 75 pièces)
----------------------------------------------------------------------

function TownShops.Shop(parent: Instance, cf: CFrame, spec: ShopSpec, seed: number): Model
	local model = TownKit.Model(parent, "Shop_" .. spec.Id)
	local W, D = TownShops.W, TownShops.D
	local hw = W / 2
	local wall, mat, front, trim = spec.Wall, spec.Material, spec.Front, spec.Trim
	local height = BODY_Y + UPPER_H
	-- plancher (léger retrait : aucune face collée à la façade)
	box(model, "Floor", cf, -hw + 0.1, hw - 0.1, FLOOR_TOP - 1.2, FLOOR_TOP, 0.1, D - 0.1, C.StoneDark, M.Concrete, "solid")
	box(model, "Threshold", cf, -DOOR_W / 2 - 0.1, DOOR_W / 2 + 0.1, FLOOR_TOP - 0.5, FLOOR_TOP - 0.02, -0.4, 0.3, C.MetalLight, M.Metal, "solid")
	-- murs de côté (pilastres de la façade) et du fond
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "SideWall", cf, sx < 0 and -hw or hw - 1, sx < 0 and -hw + 1 or hw, 0, WALL_TOP, 0, D, wall, mat, "solid")
	end
	box(model, "BackWall", cf, -hw + 1, hw - 1, 0, WALL_TOP, D - 1, D, wall, mat, "solid")
	-- plafond (déborde dans les murs : pas de face collée)
	box(model, "Ceiling", cf, -hw + 0.9, hw - 0.9, CEIL, BODY_Y + 0.2, 0.9, D - 0.9, wall, mat, "solid")
	-- devanture : piliers, allèges, bandeau au-dessus des vitrines et de la porte
	local doorTop = FLOOR_TOP + DOOR_H
	for _, sx in ipairs({ -1, 1 }) do
		local function sbox(name: string, a: number, b: number, y0: number, y1: number)
			local x0, x1 = sx * a, sx * b
			box(model, name, cf, math.min(x0, x1), math.max(x0, x1), y0, y1, -0.1, 1, front, M.WoodPlanks, "solid")
		end
		sbox("Pier", WIN_X1, hw - 1.04, 0, WALL_TOP) -- (fente de 0,04 : aucune face collée au mur)
		sbox("Sill", WIN_X0, WIN_X1, 0, WIN_Y0)
		sbox("DoorPier", DOOR_W / 2, WIN_X0, 0, doorTop)
		-- vitrine : grande vitre (solide), meneau, traverse, appui extérieur
		local cx = sx * (WIN_X0 + WIN_X1) / 2
		local ww = WIN_X1 - WIN_X0
		glass(model, "ShopWindow", Vector3.new(ww - 0.1, doorTop - WIN_Y0 - 0.1, 0.2), cf * CFrame.new(cx, (WIN_Y0 + doorTop) / 2, 0.45), 0.62)
		part(model, "Mullion", Vector3.new(0.25, doorTop - WIN_Y0 - 0.04, 0.5), cf * CFrame.new(cx, (WIN_Y0 + doorTop) / 2, 0.45), front, M.Wood, "deco")
		part(model, "Transom", Vector3.new(ww - 0.1, 0.25, 0.5), cf * CFrame.new(cx, doorTop - 1.7, 0.45), front, M.Wood, "deco")
		box(model, "WindowSill", cf, cx - ww / 2 - 0.3, cx + ww / 2 + 0.3, WIN_Y0 - 0.3, WIN_Y0 - 0.02, -0.55, -0.12, trim, M.Concrete, "deco")
		-- store rayé au-dessus de la vitrine
		awning(model, cf, cx - ww / 2 - 0.2, cx + ww / 2 + 0.2, doorTop + 0.6, spec.Awning)
		-- plante en pot de chaque côté de la porte
		local pot = (cf * CFrame.new(sx * (DOOR_W / 2 + 0.9), 0, -1.1)).Position
		TownKit.Column(model, "Pot", pot, 1.3, 1.3, Color3.fromRGB(214, 130, 96), M.Concrete, "prop")
		TownKit.Ball(model, "Shrub", pot + Vector3.new(0, 2.1, 0), 1.9, C.GrassDark, M.Grass, "deco")
	end
	box(model, "Header", cf, -WIN_X1, WIN_X1, doorTop, WALL_TOP, -0.1, 1, front, M.WoodPlanks, "solid")
	-- porte : encadrement, deux vantaux vitrés coulissants, auvent, plaque "Entrez"
	box(model, "DoorFrame", cf, -DOOR_W / 2 - 0.4, DOOR_W / 2 + 0.4, doorTop, doorTop + 0.3, -0.35, -0.15, trim, M.Metal, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		doorPanel(model, cf * CFrame.new(sx * DOOR_W / 4, FLOOR_TOP + (DOOR_H - 0.1) / 2, 0.3), DOOR_W / 2 - 0.05, DOOR_H - 0.1, sx * (DOOR_W / 2 - 0.2))
	end
	part(model, "DoorCanopy", Vector3.new(DOOR_W + 1.4, 0.3, 2.4), cf * CFrame.new(0, doorTop + 0.5, -1.25), spec.Awning[1], M.Metal, "deco")
	plaque(model, "OpenSign", Vector3.new(1.3, 1.5, 0.1), cf * CFrame.new(DOOR_W / 2 + 0.75, FLOOR_TOP + 5.4, -0.2), C.White, "Come in!", spec.SignColor, 60, 60)
	-- enseigne (texte traduit côté client : attribut LocText)
	local signW = W * 0.64
	box(model, "SignFrame", cf, -signW / 2 - 0.4, signW / 2 + 0.4, doorTop + 0.85, WALL_TOP - 0.05, -0.35, -0.15, trim, M.Wood, "deco")
	local board = part(model, "SignBoard", Vector3.new(signW, WALL_TOP - doorTop - 1.4, 0.2), cf * CFrame.new(0, (doorTop + 0.85 + WALL_TOP - 0.05) / 2, -0.42), C.Cream, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 30, nil, 360, 0.2)
	local label = TownKit.Label(body, "Title", spec.Sign, 0.03, 0.06, 0.94, 0.88, spec.SignColor, Enum.Font.FredokaOne, true)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.White
	stroke.Thickness = 2
	stroke.Parent = label
	-- étage (non visitable) : corps plein, bandeau, fenêtres, enseigne en drapeau
	part(model, "Body", Vector3.new(W, height - BODY_Y, D), cf * CFrame.new(0, (BODY_Y + height) / 2, D / 2), wall, mat, "solid")
	part(model, "Band", Vector3.new(W + 0.6, 0.6, 0.7), cf * CFrame.new(0, BODY_Y + 0.35, -0.05), trim, M.Concrete, "deco")
	for i = 1, 3 do
		local x = -hw + (i - 0.5) * W / 3
		TownBuildings.Window(model, cf * CFrame.new(x, BODY_Y + UPPER_H / 2 + 0.6, 0), 3.2, 4.4, trim, spec.Shutters, (i + seed) % 2 == 0, seed + i)
	end
	local blade = cf * CFrame.new(hw - 2.2, BODY_Y + 2.8, -2.2)
	part(model, "BladeBracket", Vector3.new(0.25, 0.25, 3.2), cf * CFrame.new(hw - 2.2, BODY_Y + 4.3, -1.6), C.Metal, M.Metal, "deco")
	local flag = part(model, "BladeSign", Vector3.new(0.3, 2.6, 2.6), blade, C.Cream, M.Wood, "deco")
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local _, fb = TownKit.Surface(flag, face, 40, spec.Awning[1], 200, 0.3)
		TownKit.Corner(fb, 20)
		TownKit.Label(fb, "Icon", spec.Icon, 0.12, 0.12, 0.76, 0.76, C.White, Enum.Font.FredokaOne, false)
	end
	-- corniche + toit
	part(model, "Cornice", Vector3.new(W + 1.2, 1, D + 1.2), cf * CFrame.new(0, height + 0.5, D / 2), trim, M.Concrete, "decoS")
	local top = cf * CFrame.new(0, height + 1, 0)
	if spec.Roof == "Gable" then
		TownBuildings.GableRoof(model, top, W, D, math.min(9, D * 0.4), spec.RoofColor)
		part(model, "Chimney", Vector3.new(2, 5, 2), top * CFrame.new(-W * 0.3, 4.5, D * 0.7), Color3.fromRGB(176, 110, 96), M.Brick, "deco")
	else
		part(model, "Parapet", Vector3.new(W + 1.2, 1.4, 0.6), top * CFrame.new(0, 0.7, -0.3), trim, M.Concrete, "deco")
		part(model, "RoofUnit", Vector3.new(4, 2.4, 3), top * CFrame.new(W * 0.25, 1.2, D * 0.6), C.MetalLight, M.DiamondPlate, "deco")
	end
	part(model, "Drainpipe", Vector3.new(0.4, height, 0.4), cf * CFrame.new(-hw + 0.5, height / 2, -0.3), C.MetalLight, M.Metal, "deco")
	attributes(model, spec, "Items", cf * CFrame.new(0, FLOOR_TOP, D / 2), Vector3.new(W - 2, CEIL - FLOOR_TOP, D - 2), cf * CFrame.new(0, FLOOR_TOP, 0))
	-- (v11, CITY11) arrière et côtés finis côté client (TownFacades, style
	-- "EnterShop" : fenêtres, porte de service, jardinet) : plus de dos nus
	model:SetAttribute("FacadeStyle", "EnterShop")
	model:SetAttribute("FacadeCF", cf)
	model:SetAttribute("W", W)
	model:SetAttribute("D", D)
	model:SetAttribute("Floors", 2)
	model:SetAttribute("Height", height)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("Wall", wall)
	model:SetAttribute("Trim", trim)
	model:SetAttribute("Accent", spec.Awning[1])
	model:SetAttribute("GroundH", BODY_Y)
	model:SetAttribute("FloorH", UPPER_H)
	return model
end

----------------------------------------------------------------------
-- 🚗 Concession auto (v9.8, CARS98) : GRAND hall vitré 70 x 50, hors de la
-- porte, à gauche de la route d'arrivée (WorldLayout.DealershipCFrame) ;
-- coque seulement (≈ 65 pièces) : tout le décor (plateau tournant animé,
-- couronnes lumineuses, podiums, pupitres, bureau de vente + vendeur·se,
-- salon, drapeaux, voitures) est construit par le client
-- (Client/World/DealerShowroom, via ShopInteriors).
----------------------------------------------------------------------

local DEALER_H = 16 -- hauteur du hall
local CAR_DOOR = 14 -- largeur de la porte (voitures)
local CAR_DOOR_H = 11
local APRON_Y = WorldLayout.ROAD_Y + 0.05 - WorldLayout.WALK_Y -- dessus du parvis (repère de la façade)
TownShops.DEALER_H = DEALER_H
TownShops.DEALER_SLOTS = 8
TownShops.TURNTABLE = Vector3.new(-14, 0.35, -18) -- plateau tournant (repère de la façade)
TownShops.TURNTABLE_R = 10.5 -- (v11, CARS11 : voitures x 1,3)

-- Places des 8 voitures (repère du hall : x, z du centre, lacet en degrés)
-- 2 rangées de 4 de part et d'autre d'une large allée centrale (porte ->
-- bureau de vente) ; podiums de 13 studs, voitures tournées vers l'allée
-- (v11, CITY11 pour CARS11 : voitures x 1,3, limousine 19,8) podiums de 16,
-- plus espacés ; les podiums extérieurs 0,04 plus haut (les disques voisins
-- se recouvrent d'un stud : jamais deux dessus confondus). Contrôle : une
-- voiture de 19,8 x 8 tournée de 22° tient en |x| ≤ 33,4 (mur à 34), en
-- z ∈ [2,4 ; 46,6] (vitrine à 1, fond à 49), et deux rangées ne se touchent pas
local SLOT_X = { -26, -11, 11, 26 }
local SLOT_Z = { 13, 36 }
TownShops.SLOT_DISC = 16

function TownShops.SlotFrames(cf: CFrame): { CFrame }
	local list = {}
	for row, z in ipairs(SLOT_Z) do
		for i, x in ipairs(SLOT_X) do
			local yaw = (i <= 2 and -1 or 1) * (row == 1 and 22 or 16)
			local lift = (i == 1 or i == #SLOT_X) and 0.04 or 0
			table.insert(list, cf * CFrame.new(x, FLOOR_TOP + 0.35 + lift, z) * CFrame.Angles(0, math.rad(yaw), 0))
		end
	end
	return list
end

function TownShops.Dealership(parent: Instance, cf: CFrame): Model
	local spec = TownShops.DEALER
	local model = TownKit.Model(parent, "Shop_Cars")
	local W, D, H = TownShops.DEALER_W, TownShops.DEALER_D, DEALER_H
	local hw = W / 2
	local white = Color3.fromRGB(246, 246, 250)
	local frame = Color3.fromRGB(58, 62, 78)
	local accent = Color3.fromRGB(236, 72, 120)
	-- plancher (sur un socle : le pré est plus bas), murs pleins (côté opposé
	-- à la porte de la ville + fond), toit, plafond
	box(model, "Floor", cf, -hw + 0.1, hw - 0.1, FLOOR_TOP - 1.4, FLOOR_TOP, 0.1, D - 0.1, C.StoneDark, M.Concrete, "solid")
	box(model, "BackWall", cf, -hw, hw, 0, H + 0.8, D - 1, D, white, M.SmoothPlastic, "solid")
	box(model, "SideWall", cf, hw - 1, hw, 0, H + 0.8, 1, D - 1, white, M.SmoothPlastic, "solid")
	box(model, "Roof", cf, -hw - 0.6, hw + 0.6, H + 0.5, H + 1.6, -0.8, D + 0.6, white, M.SmoothPlastic, "decoS")
	box(model, "Ceiling", cf, -hw + 0.9, hw - 0.9, H - 0.6, H + 0.55, 0.9, D - 0.9, white, M.SmoothPlastic, "solid")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "Parapet", cf, sx < 0 and -hw - 0.55 or hw - 0.2, sx < 0 and -hw - 0.2 or hw + 0.55, H + 1.5, H + 2.4, -0.1, D + 0.55, accent, M.SmoothPlastic, "deco")
	end
	box(model, "ParapetBack", cf, -hw - 0.2, hw + 0.2, H + 1.5, H + 2.4, D + 0.2, D + 0.55, accent, M.SmoothPlastic, "deco")
	for k = 0, 2 do
		glass(model, "Skylight", Vector3.new(W * 0.55, 0.5, 6), cf * CFrame.new(-4, H + 1.9, 10 + k * 14), 0.35).CanCollide = false
	end
	box(model, "RoofUnit", cf, 20, 27, H + 1.5, H + 3.6, D - 14, D - 7, C.MetalLight, M.DiamondPlate, "deco")
	-- façade vitrée (côté route) : poteaux, soubassement, vitres, grande porte
	local doorTop = FLOOR_TOP + CAR_DOOR_H
	local glassY0, glassY1 = 1, H - 1.4
	box(model, "Beam", cf, -hw, hw, glassY1, H + 0.6, -0.2, 1, frame, M.Metal, "solid")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "Post", cf, sx < 0 and -hw or hw - 1, sx < 0 and -hw + 1 or hw, 0, glassY1, -0.2, 1, frame, M.Metal, "solid")
		local x0, x1 = CAR_DOOR / 2 + 0.6, hw - 1
		local a, b = sx * x0, sx * x1
		box(model, "Kick", cf, math.min(a, b), math.max(a, b), 0, glassY0, -0.2, 1, frame, M.Metal, "solid")
		box(model, "DoorPost", cf, sx < 0 and -CAR_DOOR / 2 - 0.6 or CAR_DOOR / 2, sx < 0 and -CAR_DOOR / 2 or CAR_DOOR / 2 + 0.6, 0, glassY1, -0.2, 1, frame, M.Metal, "solid")
		glass(model, "Showcase", Vector3.new(x1 - x0 - 0.1, glassY1 - glassY0, 0.3), cf * CFrame.new(sx * (x0 + x1) / 2, (glassY0 + glassY1) / 2, 0.4), 0.72)
		for k = 1, 3 do
			local mx = sx * (x0 + (x1 - x0) * k / 4)
			part(model, "Mullion", Vector3.new(0.3, glassY1 - glassY0, 0.55), cf * CFrame.new(mx, (glassY0 + glassY1) / 2, 0.4), frame, M.Metal, "deco")
		end
		doorPanel(model, cf * CFrame.new(sx * CAR_DOOR / 4, FLOOR_TOP + (CAR_DOOR_H - 0.1) / 2, 0.35), CAR_DOOR / 2 - 0.05, CAR_DOOR_H - 0.1, sx * (CAR_DOOR / 2 - 0.5))
	end
	box(model, "DoorHeader", cf, -CAR_DOOR / 2, CAR_DOOR / 2, doorTop, doorTop + 0.4, -0.2, 1, frame, M.Metal, "solid")
	glass(model, "Transom", Vector3.new(CAR_DOOR - 0.1, glassY1 - doorTop - 0.4, 0.3), cf * CFrame.new(0, (doorTop + 0.4 + glassY1) / 2, 0.4), 0.72)
	-- auvent d'entrée (dalle en porte-à-faux + 2 colonnes fines)
	box(model, "Canopy", cf, -11, 11, doorTop + 0.9, doorTop + 1.6, -7.5, -0.2, white, M.SmoothPlastic, "decoS")
	box(model, "CanopyEdge", cf, -11.05, 11.05, doorTop + 0.7, doorTop + 0.95, -7.55, -7.3, accent, M.SmoothPlastic, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		TownKit.Column(model, "CanopyPost", (cf * CFrame.new(sx * 10.2, APRON_Y, -6.6)).Position, doorTop + 0.9 - APRON_Y, 0.45, frame, M.Metal, "prop")
	end
	-- côté porte de la ville (x < 0) : mur-rideau vitré
	local side = cf * CFrame.new(-hw + 0.5, 0, 0)
	box(model, "SideKick", side, -0.5, 0.5, 0, glassY0, 1, D - 6, frame, M.Metal, "solid")
	box(model, "SideBeam", side, -0.5, 0.5, glassY1, H + 0.6, 1, D - 6, frame, M.Metal, "solid")
	box(model, "SideBack", side, -0.5, 0.5, 0, H + 0.6, D - 6, D, white, M.SmoothPlastic, "solid")
	glass(model, "SideGlass", Vector3.new(0.3, glassY1 - glassY0, D - 7.1), side * CFrame.new(0, (glassY0 + glassY1) / 2, (1 + D - 6) / 2), 0.72)
	for k = 1, 5 do
		local z = 1 + (D - 7) * k / 6
		part(model, "SideMullion", Vector3.new(0.55, glassY1 - glassY0, 0.3), side * CFrame.new(0, (glassY0 + glassY1) / 2, z), frame, M.Metal, "deco")
	end
	-- enseigne (façade + côté porte de la ville) et bande d'accent
	local sign = part(model, "SignBand", Vector3.new(W * 0.62, 4.2, 0.6), cf * CFrame.new(0, H + 3.7, -0.5), white, M.SmoothPlastic, "decoS")
	local _, sb = TownKit.Surface(sign, Enum.NormalId.Front, 20, nil, 600, 0.2)
	local title = TownKit.Label(sb, "Title", spec.Sign, 0.06, 0.1, 0.88, 0.8, accent, Enum.Font.FredokaOne, true)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.White
	stroke.Thickness = 2
	stroke.Parent = title
	part(model, "SignStripe", Vector3.new(W + 1.3, 0.5, 0.7), cf * CFrame.new(0, H + 1.85, -0.5), accent, M.SmoothPlastic, "deco")
	local sideSign = part(model, "SideSign", Vector3.new(0.6, 4.2, D * 0.6), cf * CFrame.new(-hw - 0.75, H + 3.7, D * 0.4), white, M.SmoothPlastic, "deco")
	local _, ss = TownKit.Surface(sideSign, Enum.NormalId.Left, 20, nil, 600, 0.2)
	TownKit.Label(ss, "Title", spec.Sign, 0.06, 0.1, 0.88, 0.8, accent, Enum.Font.FredokaOne, true)
	-- podiums des voitures (le client y pose les voitures et les couronnes)
	for index, slotCF in ipairs(TownShops.SlotFrames(cf)) do
		local disc = part(model, "CarSlot_" .. index, Vector3.new(0.35, TownShops.SLOT_DISC, TownShops.SLOT_DISC), slotCF * CFrame.new(0, -0.175, 0) * CFrame.Angles(0, 0, math.rad(90)), white, M.Marble, "deco")
		;(disc :: Part).Shape = Enum.PartType.Cylinder
		disc:SetAttribute("CarCF", slotCF)
		disc:SetAttribute("Slot", index)
	end
	model:SetAttribute("ShowroomSlots", TownShops.DEALER_SLOTS)
	model:SetAttribute("AllowCars", true)
	model:SetAttribute("DealerW", W)
	model:SetAttribute("DealerD", D)
	attributes(model, spec, "Cars", cf * CFrame.new(0, FLOOR_TOP, D / 2), Vector3.new(W - 2, H - 0.6 - FLOOR_TOP, D - 2), cf * CFrame.new(0, FLOOR_TOP, 0))
	return model
end

-- Place la concession hors de la porte, à gauche de la route d'arrivée
-- (WorldLayout.DealershipCFrame) : parvis pavé, rampe, allée jusqu'à la
-- route, SOCLE du plateau tournant (le plateau et la voiture qui tourne :
-- client), totem. Réserve la zone (pas d'arbres de TownNature dessus).
function TownShops.BuildDealership(folder: Instance, geo: TownKit.Geo): Model
	local W = TownShops.DEALER_W
	local cf = WorldLayout.DealershipCFrame(geo.Count)
	local model = TownShops.Dealership(folder, cf)
	local hw = W / 2
	local depth = WorldLayout.DEALER_X - 24 -- parvis : de la façade à 24 studs de l'axe de la route
	-- parvis (sans toucher le petit parking d'arrivée, côté porte de la ville)
	local apron = box(model, "Forecourt", cf, -24, hw, APRON_Y - 0.7, APRON_Y, -depth, -0.05, C.Walk, M.Pavement, "solid")
	apron.CastShadow = false
	box(model, "ForecourtSide", cf, -hw, -24, APRON_Y - 0.7, APRON_Y, -12, -0.05, C.Walk, M.Pavement, "solid").CastShadow = false
	-- rampe douce jusqu'au plancher du hall (voitures et avatars)
	TownKit.Wedge(model, "Ramp", Vector3.new(CAR_DOOR, FLOOR_TOP - APRON_Y, 2.6), cf * CFrame.new(0, (FLOOR_TOP + APRON_Y) / 2, -1.35), C.MetalLight, M.Concrete, "solid")
	-- allée jusqu'à la route (asphalte)
	box(model, "Driveway", cf, -12, -2, APRON_Y - 0.7, APRON_Y - 0.02, -(WorldLayout.DEALER_X - 8), -depth, C.Asphalt, M.Asphalt, "solid")
	-- socle du plateau tournant (on marche dessus ; le plateau tourne côté client)
	local t = TownShops.TURNTABLE
	local base = part(model, "TurntableBase", Vector3.new(t.Y - APRON_Y, TownShops.TURNTABLE_R * 2, TownShops.TURNTABLE_R * 2),
		cf * CFrame.new(t.X, (t.Y + APRON_Y) / 2, t.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(58, 62, 78), M.Metal, "solid")
	;(base :: Part).Shape = Enum.PartType.Cylinder
	model:SetAttribute("TurntableCF", cf * CFrame.new(t.X, t.Y, t.Z))
	model:SetAttribute("TurntableR", TownShops.TURNTABLE_R)
	model:SetAttribute("ApronY", APRON_Y)
	-- totem au bord de l'allée
	local totem = cf * CFrame.new(-16, APRON_Y, -(depth - 3)) * CFrame.Angles(0, math.rad(-35), 0)
	part(model, "TotemBase", Vector3.new(3, 1, 1.6), totem * CFrame.new(0, 0.5, 0), C.StoneDark, M.Granite, "prop")
	plaque(model, "Totem", Vector3.new(2.6, 9, 0.9), totem * CFrame.new(0, 5.5, 0), Color3.fromRGB(58, 62, 78), "🚗", C.White, 30, 300)
	-- zones réservées (hall + parvis) : TownNature n'y plante rien
	geo.Reserve(cf * Vector3.new(0, 0, WorldLayout.DEALER_D / 2), math.sqrt(hw ^ 2 + (WorldLayout.DEALER_D / 2) ^ 2) + 4)
	geo.Reserve(cf * Vector3.new(0, 0, -depth / 2), math.max(hw, depth / 2) + 2)
	return model
end

-- Retire les arbres (modèles "Tree*") posés par d'autres modules sur le hall
-- ou le parvis (à appeler APRÈS la nature, comme TownMarket.ClearSite)
function TownShops.ClearDealerSite(decor: Instance, count: number): number
	local cf = WorldLayout.DealershipCFrame(count)
	local hw = TownShops.DEALER_W / 2 + 4
	local depth = WorldLayout.DEALER_X - 24 + 3
	local removed = 0
	for _, d in ipairs(decor:GetDescendants()) do
		if d:IsA("Model") and string.sub(d.Name, 1, 4) == "Tree" and d.Parent and not d:FindFirstAncestor("Shop_Cars") then
			local first = d:FindFirstChildWhichIsA("BasePart", true)
			local p = cf:PointToObjectSpace(first and first.Position or d:GetPivot().Position)
			if math.abs(p.X) <= hw and p.Z >= -depth and p.Z <= WorldLayout.DEALER_D + 4 then
				for _, x in ipairs(d:GetDescendants()) do
					if x:IsA("BasePart") then
						removed += 1
					end
				end
				d:Destroy()
			end
		end
	end
	TownKit.Stats.Parts -= removed
	return removed
end

return TownShops
