--[[
	GarageLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > GarageLayout

	🏎️ Géométrie du garage du manoir (v9.6, GARAGE96), partagée par le client
	(HouseFacade : l'aile ; CarClient : porte, voitures garées) et le serveur
	(CarService : sortie de la voiture). Fonctions PURES (aucun service).

	Repère LOCAL de la maison (WorldLayout) : x vers la droite du visiteur qui
	arrive de la rue, y vers le haut (0 = sol de la parcelle), d = profondeur
	depuis la façade (d < 0 = jardin de devant, vers la rue).
	Le manoir + ses tours occupent 174,8 des 176 studs de la parcelle et le
	jardin de derrière est le Jardin de Dopamine 3D : le garage est donc une
	AILE DANS LA COUR DE DEVANT, côté droit (vu de la rue), devant la 4e
	colonne de pièces, sans toucher la tour de droite :
	  x 41..74, d -25,95..-3,4 (3 places côte à côte, portes vers la rue),
	  allée pavée jusqu'au bord de la rue (d -25,95..-30).
	v11 (CARS11) : voitures ×1,3 (CarModels.SCALE) -> garage plus profond
	(20,95 utiles : la limousine 19,8 y tient), portes 9,3 × 8,3, murs 10,8 ;
	places 10,5 de large (voiture la plus large : 7,8).
]]

local GarageLayout = {}

GarageLayout.X0 = 41 -- (v11 : 46 -> 41 : places de 10,5 pour les voitures ×1,3)
GarageLayout.X1 = 74 -- (v11 : 76 -> 74 : la tour de droite reste dégagée)
GarageLayout.D0 = -25.95 -- façade du garage (portes, côté rue) (v11 : -23,5 -> -25,95 ; allée ≥ 4)
GarageLayout.D1 = -3.4 -- mur du fond (devant la maison) (v11 : -6 -> -3,4)
GarageLayout.WALL = 0.8
GarageLayout.FLOOR = 0.7 -- dessus de la dalle (pelouse de la parcelle ≈ 0,45)
GarageLayout.HEIGHT = 10.8 -- haut des murs (au-dessus de y = 0)
GarageLayout.DOOR_W = 9.3 -- (v11 : 7,6 -> 9,3 ; voiture la plus large 7,8 ; encadrements voisins séparés)
GarageLayout.DOOR_H = 8.3 -- (v11 : 7,4 -> 8,3 ; voiture la plus haute 7,8)
GarageLayout.BAYS = 3
GarageLayout.STREET_D = -30 -- bord de la parcelle côté rue (WorldLayout.GARDEN_D)
GarageLayout.OPEN_RANGE = 26 -- la porte s'ouvre quand SA voiture arrive à moins de...

-- Le style de maison a-t-il un garage ? (seulement le manoir)
function GarageLayout.Supports(size: any): boolean
	if type(size) ~= "table" then
		return false
	end
	return size.Exterior == "Mansion" or size.Id == "Mansion"
end

-- Centre (x) de la place `bay` (1..BAYS, de gauche à droite vu de la rue)
function GarageLayout.BayX(bay: number): number
	local inner0 = GarageLayout.X0 + GarageLayout.WALL
	local inner1 = GarageLayout.X1 - GarageLayout.WALL
	local w = (inner1 - inner0) / GarageLayout.BAYS
	local b = math.clamp(math.floor(tonumber(bay) or 1), 1, GarageLayout.BAYS)
	return inner0 + (b - 0.5) * w
end

-- Milieu (d) d'une voiture garée (entre la porte et le mur du fond)
function GarageLayout.BayD(): number
	return (GarageLayout.D0 + GarageLayout.WALL + GarageLayout.D1 - GarageLayout.WALL) / 2
end

-- Profondeur utile (d) : la plus longue voiture (limousine 19,8 à l'échelle 1,3) y tient
function GarageLayout.InnerDepth(): number
	return (GarageLayout.D1 - GarageLayout.WALL) - (GarageLayout.D0 + GarageLayout.WALL)
end

-- Pivot (CFrame monde) d'une voiture garée : au sol de la dalle, AVANT vers la rue
function GarageLayout.BayCFrame(houseCF: CFrame, bay: number): CFrame
	local x = GarageLayout.BayX(bay)
	local d = GarageLayout.BayD()
	local p = houseCF * Vector3.new(x, GarageLayout.FLOOR, -d)
	-- (avant de la voiture = -Z du modèle = vers la rue = -LookVector de la maison)
	return CFrame.lookAt(p, p - houseCF.LookVector)
end

-- Porte `bay` : centre du bas de l'ouverture (d = façade)
function GarageLayout.DoorPoint(houseCF: CFrame, bay: number): Vector3
	return houseCF * Vector3.new(GarageLayout.BayX(bay), GarageLayout.FLOOR, -GarageLayout.D0)
end

-- Centre du garage (monde), pour les distances
function GarageLayout.Center(houseCF: CFrame): Vector3
	local x = (GarageLayout.X0 + GarageLayout.X1) / 2
	local d = (GarageLayout.D0 + GarageLayout.D1) / 2
	return houseCF * Vector3.new(x, 3, -d)
end

-- Point local (x, y, d) dans le garage ? (marge en studs)
function GarageLayout.Inside(x: number, y: number, d: number, margin: number?): boolean
	local m = margin or 0
	return x >= GarageLayout.X0 - m and x <= GarageLayout.X1 + m and d >= GarageLayout.D0 - m and d <= GarageLayout.D1 + m and y >= -2 and y <= GarageLayout.HEIGHT + 3
end

-- Place d'une voiture possédée (ordre d'affichage : la voiture choisie au
-- milieu, puis les autres dans l'ordre du catalogue) -> { [carId] = bay }
function GarageLayout.Assign(owned: { string }, selected: string?): { [string]: number }
	local order = { 2, 1, 3 }
	local out: { [string]: number } = {}
	local list: { string } = {}
	if type(selected) == "string" and table.find(owned, selected) then
		table.insert(list, selected)
	end
	for _, id in ipairs(owned) do
		if id ~= selected then
			table.insert(list, id)
		end
	end
	for index, id in ipairs(list) do
		local bay = order[index]
		if not bay then
			break
		end
		out[id] = bay
	end
	return out
end

return GarageLayout
