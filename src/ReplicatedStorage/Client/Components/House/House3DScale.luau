--[[
	House3DScale (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DScale

	v11 📏 SCALE11 : échelle "ROBLOX" (comme les grands jeux de vie Roblox),
	plus grande que le monde réel. Le joueur : "rien n'est à la bonne
	dimension, tout est trop petit" (chaises, tables, lits... à côté de
	l'avatar). Les cotes réelles de v9.9 (SCALE99) passent donc à x1,3 et
	les meubles qu'on utilise visent des cotes précises (ci-dessous).

	Avatar R15 standard (échelle 1), mesuré : 5,2 studs ; HipHeight 2 ;
	hanche 2,0 ; cuisse (hanche -> genou) 0,84 ; tibia 0,90 ; cheville ->
	semelle 0,25 ; jambe épaisse de 0,95. Assis sur un Seat de Roblox : le
	HumanoidRootPart est soudé à 1,5 stud au-dessus du DESSUS du siège ->
	hanche à dessus + 0,5 et dessous des cuisses PILE sur le siège. Les
	jambes R15 sont courtes : pieds à plat seulement si l'assise est ≤ 0,65 ;
	comme dans les jeux Roblox, les pieds pendent (SitAnimator plie les
	jambes, tibias pendants). Assis : épaules à dessus + 2,5, yeux + 3,2,
	haut de la tête + 3,7, coudes + 1,5.

	Cotes visées (studs, dessus VISUEL) :
	  chaise (salle à manger, cuisine, bureau, jardin) : assise 1,85, place
	    ≥ 2,5 de large ; chaise gamer 1,9 ; fauteuil / canapé 1,8 ;
	    banc 1,85 ; tabouret bas 1,6-1,7 ; tabouret de bar 2,9 ; trône 2,1
	  lit : matelas 2,2 (plateforme 1,95), longueur ≥ 7,5
	  table à manger / bureau 3,1 (assise + 1,25) ; table basse 1,75 ;
	    chevet 2,3 ; plan de travail / îlot / évier / four 3,3 ; commode 3,6 ;
	    table haute 4,1 ; meuble TV 2,1 ; ping-pong 3 ; billard 3,2
	  armoire 7,8 ; bibliothèque 7,3 ; frigo 7-7,2 ; lampadaire 6,6 ;
	    douche 8,3 ; portes 9,6 de haut (≤ 5,7 de large ; portails ≤ 8,3)
	  tout le reste (objets au sol, petits objets compris) : x1,3
	Plafond des pièces : 12 (le plus haut objet, le torii, fait 10,9).

	Chaque objet reçoit { f, s } :
	  f = facteur UNIFORME (toutes les dimensions) : il règle la cote qui
	      compte (hauteur d'assise, de plateau, de matelas, hauteur totale) ;
	  s = élargissement HORIZONTAL en plus (x et z seulement, 1 par défaut) :
	      une chaise plus large sans assise plus haute, un lit plus long...
	      (House3DKit.Builder : `stretch` ; les rotations autour de la
	      verticale restent exactes, boules et cylindres restent ronds).
	Les objets absents du tableau reçoivent f = DEFAULT_F (1,3), s = 1.
	Les objets muraux (Placement = "Wall") et les animaux ne sont jamais
	corrigés (la pose murale de House3DLayout et PetRoam en dépendent).
	Facteurs calculés depuis les mesures du scénario de mesure (toutes les
	recettes construites au PX du monde, 0,036 stud/px ; scratchpad
	scale11/work/factors11.py) : si une recette change de proportions,
	refaire la mesure.

	API :
	  House3DScale.Of(item) -> (f: number, s: number)
	  House3DScale.TABLE      (lecture seule, tests)
	  House3DScale.DEFAULT_F  (facteur des objets absents du tableau)
]]

local House3DScale = {}

-- Facteur des objets au sol absents du tableau (échelle Roblox = x1,3)
local DEFAULT_F = 1.3
House3DScale.DEFAULT_F = DEFAULT_F

-- [Id] = { f, s? }
local TABLE: { [string]: { number } } = {
	AlarmClock = { 1.014 },
	ArcFloorLamp = { 1.517 },
	ArcadeMachine = { 1.655 },
	Armchair = { 1.353, 1.026 },
	BMXBike = { 1.69 },
	BarStool = { 1.283, 1.27 },
	BarTable = { 1.507 },
	Beanbag = { 1.268, 1.04 },
	BigDesk = { 0.912, 1.351 },
	Bookshelf = { 2.025, 0.907 },
	BookshelfWall = { 1.538 },
	BrickTable = { 0.956, 1.3 },
	BunkBed = { 1.3, 1.25 },
	CafeTable = { 1.448 },
	CandyDoor = { 2.016, 0.863 },
	CanopyBed = { 1.1, 1.6 },
	CapsuleBed = { 1.3, 1.15 },
	CastleGate = { 1.975, 0.778 },
	CatSofa = { 0.928, 1.512 },
	Chesterfield = { 0.814, 1.6 },
	CinemaRecliners = { 0.785, 1.339 },
	ClawMachine = { 1.556 },
	CloudBed = { 0.905, 1.598 },
	CoatRack = { 1.695 },
	CoffeeTable = { 0.902, 1.431 },
	CrystalThrone = { 0.905, 1.231 },
	DiningChair = { 1.21, 1.6 },
	DiningTable = { 0.945, 1.4 },
	DoubleBed = { 0.917, 1.488 },
	DrawerCabinet = { 1.464 },
	DreamPortal = { 1.925, 0.832 },
	Dresser = { 1.441 },
	DutchDoor = { 2.012, 0.776 },
	EggChair = { 1.038 },
	Elevator = { 1.96, 0.875 },
	FloorLamp = { 1.41 },
	Fridge = { 1.689 },
	GamerBeanbag = { 0.962, 1.3 },
	GamerChair = { 1.428, 1.147 },
	GamingChair = { 1.583, 1.097 },
	GamingDesk = { 0.882, 1.378 },
	GardenBench = { 1.045, 1.399 },
	GardenDoor = { 2.012, 0.776 },
	GlassCoffeeTable = { 1.087, 1.094 },
	GoldThrone = { 0.967, 1.337 },
	GrandPiano = { 1.495 },
	GrandfatherClock = { 1.547 },
	Harp = { 1.565 },
	HeartArmchair = { 1.384 },
	HeartDoor = { 2.012, 0.776 },
	KingBed = { 0.909, 1.499 },
	KitchenIsland = { 1.038, 1.194 },
	KitchenSink = { 1.479 },
	KotatsuTable = { 0.91, 1.35 },
	LadderShelf = { 1.691 },
	LockerCabinet = { 1.781, 0.9 },
	LoftBed = { 1.678, 1.388 },
	LoftShelf = { 1.625 },
	Mannequin = { 1.641 },
	MarbleIsland = { 1.003, 1.131 },
	MediaConsole = { 1.067, 1.197 },
	ModernBarStool = { 1.193, 1.292 },
	Motorbike = { 1.625 },
	MushroomStool = { 1.012, 1.599 },
	NeonArcade = { 1.589 },
	Nightstand = { 2.073 },
	OakDesk = { 1.123, 1.151 },
	PicnicTable = { 0.942, 1.38 },
	PingPongTable = { 1.063, 1.207 },
	PlatformBed = { 1.09, 1.283 },
	PoolTable = { 0.942, 1.339 },
	Pouf = { 1.684, 1.023 },
	RaceCarBed = { 1.3, 1.15 },
	RetroHandheld = { 1.04 },
	RockingChair = { 1.088, 1.219 },
	SecretDoor = { 2.012, 0.75 },
	SectionalSofa = { 0.813, 1.588 },
	SetupDeskDuo = { 1.148, 1.129 },
	SetupDeskSolo = { 1.23, 1.128 },
	SetupDeskTrio = { 1.111, 1.128 },
	SetupDeskUltra = { 1.076, 1.083 },
	SetupTVStand = { 0.995, 1.257 },
	ShojiDoor = { 2.012, 0.776 },
	Shower = { 2.096, 0.876 },
	SideTable = { 1.716 },
	SimpleChair = { 1.555, 1.258 },
	SlotMachine = { 1.642 },
	Smartphone = { 0.936 },
	Sofa = { 0.937, 1.6 },
	SteelFridge = { 1.472 },
	Stove = { 1.48 },
	StudyDesk = { 1.505, 1.06 },
	Surfboard = { 1.667 },
	TVStand = { 1.035, 1.338 },
	ToriiGate = { 2.061, 0.75 },
	VanityTable = { 1.741 },
	VelvetChaise = { 0.87, 1.498 },
	Wardrobe = { 1.874, 0.858 },
	WhitePiano = { 1.43 },
	WoodenChair = { 1.529, 1.261 },
	WoodenDoor = { 2.012, 0.776 },
	Workbench = { 1.033, 1.088 },
	YoYo = { 0.936 },
}
House3DScale.TABLE = TABLE

local F_MIN, F_MAX = 0.7, 2.6
local S_MIN, S_MAX = 0.75, 1.9

function House3DScale.Of(item: any): (number, number)
	if type(item) ~= "table" or item.Placement == "Wall" or item.Category == "Pets" then
		return 1, 1
	end
	local row = TABLE[tostring(item.Id)]
	if not row then
		return DEFAULT_F, 1
	end
	local f = math.clamp(tonumber(row[1]) or DEFAULT_F, F_MIN, F_MAX)
	local s = math.clamp(tonumber(row[2]) or 1, S_MIN, S_MAX)
	return f, s
end

return House3DScale
