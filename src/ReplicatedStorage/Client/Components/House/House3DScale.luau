--[[
	House3DScale (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DScale

	v9.9 📏 SCALE99 : proportions RÉELLES des objets de la maison à côté d'un
	avatar Roblox (~5,2 studs ; PNJ 5,3). Les recettes 3D sont dessinées dans
	la boîte 2D de l'objet (100 x 100 unités = item.Size px) : leurs
	proportions venaient du dessin, pas du monde réel (chaise de 1,7 stud de
	large pour des hanches de 2 studs, lit plus court que l'avatar, armoire de
	4 studs, table à manger à 3,3 studs de haut, canapé assis à 2 studs...).

	Chaque objet corrigé reçoit { f, s } :
	  f = facteur UNIFORME (toutes les dimensions) : il règle la cote qui
	      compte (hauteur d'assise, de plateau, de matelas, hauteur totale) ;
	  s = élargissement HORIZONTAL en plus (x et z seulement, 1 par défaut) :
	      une chaise plus large sans assise plus haute, un lit plus long...
	      (House3DKit.Builder : `stretch` ; les rotations autour de la
	      verticale restent exactes, boules et cylindres restent ronds).
	Les objets absents du tableau gardent f = 1, s = 1. Les objets muraux
	(Placement = "Wall") et les animaux ne sont jamais corrigés (la pose
	murale de House3DLayout et PetRoam en dépendent).

	Cotes visées (studs ; 1 m ≈ 3,06 studs à la hauteur d'un avatar ; jambes
	R15 courtes -> assises ≤ 1,55) :
	  chaise / chaise de bureau : assise 1,43-1,45, largeur ≥ 2,1, dossier ≈ 2,7-3
	  fauteuil / canapé : assise 1,45-1,55, ≥ 2,2 par place, canapé ≥ 5,5 de long
	  tabouret de bar 2,45 ; lit : matelas 1,6-1,85, longueur ≥ 6,2
	  table à manger / bureau 2,35 ; table basse 1,45 ; chevet 1,75 ;
	  plan de travail 2,8 ; commode 2,9 ; table haute 3,2
	  armoire 6 ; bibliothèque 5,6 ; frigo 5,6 ; lampadaire 5,2 ;
	  portes (objets) ≥ 7,4 de haut, ≤ 4,4 de large (portails ≤ 6,4)
	  petits objets : jamais réduits de plus de x0,7 (demande de main : le
	  joueur trouve déjà les objets trop petits) ; seuls les plus absurdes
	  (yo-yo, téléphone, réveil, console de poche) sont un peu réduits.
	Facteurs calculés depuis les mesures du scénario SCALE99 (toutes les
	recettes construites au PX du monde, 0,036 stud/px) : si une recette
	change de proportions, refaire la mesure (scratchpad scale99/factors.py).

	API :
	  House3DScale.Of(item) -> (f: number, s: number)
	  House3DScale.TABLE   (lecture seule, tests)
]]

local House3DScale = {}

-- [Id] = { f, s? }
local TABLE: { [string]: { number } } = {
	AlarmClock = { 0.78 },
	ArcFloorLamp = { 1.198 },
	ArcadeMachine = { 1.273 },
	Armchair = { 1.09 },
	BMXBike = { 1.3 },
	BarStool = { 1.084, 1.178 },
	BarTable = { 1.176 },
	BigDesk = { 0.7, 1.351 },
	Bookshelf = { 1.556, 0.924 },
	BookshelfWall = { 1.183 },
	BrickTable = { 0.735, 1.3 },
	BunkBed = { 1, 1.25 },
	CafeTable = { 1.098 },
	CandyDoor = { 1.551, 0.865 },
	CanopyBed = { 0.925, 1.5 },
	CapsuleBed = { 1, 1.15 },
	CastleGate = { 1.519, 0.78 },
	CatSofa = { 0.773, 1.341 },
	Chesterfield = { 0.701, 1.45 },
	CinemaRecliners = { 0.7, 1.339 },
	ClawMachine = { 1.197 },
	CloudBed = { 0.761, 1.5 },
	CoatRack = { 1.304 },
	CoffeeTable = { 0.747, 1.4 },
	CrystalThrone = { 0.754, 1.231 },
	DiningChair = { 0.948, 1.394 },
	DiningTable = { 0.716, 1.4 },
	DoubleBed = { 0.771, 1.488 },
	DrawerCabinet = { 1.179 },
	DreamPortal = { 1.481, 0.834 },
	Dresser = { 1.165 },
	DutchDoor = { 1.551, 0.777 },
	EggChair = { 0.847 },
	Elevator = { 1.508, 0.877 },
	FloorLamp = { 1.111 },
	Fridge = { 1.349 },
	GamerChair = { 1.09, 1.051 },
	GamingChair = { 1.208, 1.006 },
	GamingDesk = { 0.7, 1.378 },
	GardenBench = { 0.847, 1.308 },
	GardenDoor = { 1.551, 0.777 },
	GlassCoffeeTable = { 0.901, 1.094 },
	GoldThrone = { 0.806 },
	GrandPiano = { 1.15 },
	GrandfatherClock = { 1.19 },
	Harp = { 1.204 },
	HeartArmchair = { 1.115 },
	HeartDoor = { 1.551, 0.777 },
	KingBed = { 0.764, 1.499 },
	KitchenIsland = { 0.881, 1.173 },
	KitchenSink = { 1.256 },
	KotatsuTable = { 0.7, 1.35 },
	LadderShelf = { 1.301 },
	LockerCabinet = { 1.425, 0.868 },
	LoftBed = { 1.291, 1.388 },
	LoftShelf = { 1.25 },
	Mannequin = { 1.262 },
	MarbleIsland = { 0.851, 1.111 },
	MediaConsole = { 0.838, 1.197 },
	ModernBarStool = { 1.008, 1.198 },
	Motorbike = { 1.25 },
	MushroomStool = { 0.863, 1.09 },
	NeonArcade = { 1.222 },
	Nightstand = { 1.577 },
	OakDesk = { 0.851, 1.151 },
	PicnicTable = { 0.714, 1.38 },
	PingPongTable = { 0.833, 1.207 },
	PlatformBed = { 0.894, 1.283 },
	PoolTable = { 0.765, 1.339 },
	Pouf = { 1.368 },
	RaceCarBed = { 1, 1.15 },
	RetroHandheld = { 0.8 },
	RockingChair = { 0.882, 1.19 },
	SecretDoor = { 1.551, 0.75 },
	SectionalSofa = { 0.7, 1.45 },
	SetupDeskDuo = { 0.889, 1.129 },
	SetupDeskSolo = { 0.952, 1.128 },
	SetupDeskTrio = { 0.86, 1.128 },
	SetupDeskUltra = { 0.833, 1.083 },
	SetupTVStand = { 0.782, 1.257 },
	ShojiDoor = { 1.551, 0.777 },
	Shower = { 1.616, 0.876 },
	SideTable = { 1.306 },
	SimpleChair = { 1.202, 1.074 },
	SlotMachine = { 1.263 },
	Smartphone = { 0.72 },
	Sofa = { 0.781, 1.4 },
	SteelFridge = { 1.186 },
	Stove = { 1.256 },
	StudyDesk = { 1.141, 1.06 },
	Surfboard = { 1.282 },
	TVStand = { 0.813, 1.338 },
	ToriiGate = { 1.588, 0.75 },
	VanityTable = { 1.32 },
	VelvetChaise = { 0.749, 1.35 },
	Wardrobe = { 1.439, 0.895 },
	WhitePiano = { 1.1 },
	WoodenChair = { 1.182, 1.156 },
	WoodenDoor = { 1.551, 0.777 },
	Workbench = { 0.851, 1.088 },
	YoYo = { 0.72 },
}
House3DScale.TABLE = TABLE

local F_MIN, F_MAX = 0.7, 1.8
local S_MIN, S_MAX = 0.75, 1.5

function House3DScale.Of(item: any): (number, number)
	if type(item) ~= "table" or item.Placement == "Wall" or item.Category == "Pets" then
		return 1, 1
	end
	local row = TABLE[tostring(item.Id)]
	if not row then
		return 1, 1
	end
	local f = math.clamp(tonumber(row[1]) or 1, F_MIN, F_MAX)
	local s = math.clamp(tonumber(row[2]) or 1, S_MIN, S_MAX)
	return f, s
end

return House3DScale
