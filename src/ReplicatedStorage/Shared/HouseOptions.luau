--[[
	HouseOptions (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > HouseOptions

	(v10 HOUSE10) 🏡 Personnalisation de l'EXTÉRIEUR de la maison 3D, partagée
	serveur / client (aucun Enum ici : les matières sont des NOMS d'Enum.Material,
	converties côté client ; testable hors Roblox).

	Un "genre" (Kind) = un réglage (couleur de façade, forme du toit, volets...)
	avec une liste de choix. Le 1er choix de chaque genre est GRATUIT et veut dire
	"le look d'origine du style" (Auto) ou "rien" (None) : une maison sans
	personnalisation (anciennes sauvegardes) garde exactement son look.

	Données (HouseService) : data.House.Ext = { [Kind] = IdDuChoix, Num = 0..9999 }
	(Num = numéro affiché sur la maison et la boîte aux lettres, 0 = automatique),
	data.House.OwnedExt = { ["Kind.Id"] = true } (choix achetés, gardés pour
	toujours). Réplication pour la ville : attribut du propriétaire "HouseExt"
	= HouseOptions.Encode(ext) (seulement les choix non par défaut).

	Un choix : { Id, Name (anglais, traduit par Locale), Icon, Cost (Dopamine),
	Rebirths (visites à l'océan requises), Color (Color3)?, Material (nom)?, Value? }

	API :
	  HouseOptions.KINDS (liste ordonnée) ; HouseOptions.ByKind[kind] ;
	  HouseOptions.GROUPS (onglets de l'éditeur)
	  HouseOptions.Choice(kind, id) -> choix (le 1er si inconnu)
	  HouseOptions.Default(kind) -> Id du choix gratuit
	  HouseOptions.Applies(kind, style, floors) -> bool (ex. balcon : 2 étages ou plus)
	  HouseOptions.Sanitize(ext, owned) -> ext propre (choix connus ET possédés)
	  HouseOptions.Quote(design, owned, rebirths) -> (prix total, { choix à acheter }, verrou?)
	  HouseOptions.Encode(ext) -> texte ; HouseOptions.Decode(texte) -> ext
	  HouseOptions.Resolve(ext) -> ext complet (un Id par genre)
	  HouseOptions.OwnedKey(kind, id) -> "Kind.Id"
]]

local HouseOptions = {}

export type Choice = {
	Id: string,
	Name: string,
	Icon: string,
	Cost: number,
	Rebirths: number,
	Color: Color3?,
	Material: string?,
	Value: string?,
	Order: number?,
}

export type Kind = {
	Id: string,
	Name: string,
	Icon: string,
	Group: string,
	Swatch: boolean?, -- choix = pastilles de couleur
	Choices: { Choice },
	ById: { [string]: Choice },
	MinFloors: number?, -- (balcon) seulement pour les maisons à étages
	NotStyles: { [string]: boolean }?, -- styles où le genre ne s'applique pas
}

HouseOptions.MAX_NUMBER = 9999

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function c(id: string, name: string, icon: string, cost: number, rebirths: number?, extra: { [string]: any }?): Choice
	local choice: any = { Id = id, Name = name, Icon = icon, Cost = cost, Rebirths = rebirths or 0 }
	if extra then
		for k, v in pairs(extra) do
			choice[k] = v
		end
	end
	return choice :: Choice
end

-- Petites aides : choix de couleur
local function col(id: string, name: string, cost: number, color: Color3, rebirths: number?): Choice
	return c(id, name, "🎨", cost, rebirths, { Color = color })
end

----------------------------------------------------------------------
-- Catalogue (ordre = ordre de l'éditeur)
----------------------------------------------------------------------

local KINDS: { any } = {
	-- 🏛️ Architecture : le "style" de la maison, sur la même taille
	{ Id = "Arch", Name = "Architecture", Icon = "🏛️", Group = "Style", Choices = {
		c("Auto", "Original style", "🏠", 0),
		c("Chalet", "Mountain chalet", "🏔️", 2.5e6, 1),
		c("Modern", "Modern villa", "🏙️", 4e7, 2),
	} },

	-- 🧱 Façade
	{ Id = "WallColor", Name = "Facade colour", Icon = "🎨", Group = "Facade", Swatch = true, Choices = {
		c("Auto", "Style colour", "🏠", 0),
		col("Chalk", "Chalk white", 12000, rgb(244, 242, 236)),
		col("Cream", "Warm cream", 12000, rgb(240, 228, 204)),
		col("Sand", "Sandstone", 25000, rgb(222, 200, 162)),
		col("Greige", "Stone grey", 25000, rgb(184, 178, 166)),
		col("Rose", "Old rose", 40000, rgb(224, 168, 164)),
		col("Peach", "Apricot", 40000, rgb(242, 194, 158)),
		col("Butter", "Butter yellow", 60000, rgb(238, 216, 146)),
		col("Sage", "Sage green", 60000, rgb(166, 184, 148)),
		col("Mint", "Mint", 90000, rgb(184, 224, 202)),
		col("Powder", "Powder blue", 90000, rgb(168, 194, 214)),
		col("Lavender", "Lavender", 150000, rgb(196, 182, 216)),
		col("Terracotta", "Terracotta", 250000, rgb(198, 118, 86)),
		col("BrickRed", "Brick red", 400000, rgb(158, 72, 58)),
		col("Olive", "Olive", 600000, rgb(118, 122, 80)),
		col("Navy", "Navy blue", 1.2e6, rgb(52, 66, 96)),
		col("Charcoal", "Charcoal", 2e6, rgb(72, 74, 80)),
		col("Ink", "Midnight black", 8e6, rgb(36, 36, 40), 2),
	} },
	{ Id = "WallMat", Name = "Facade material", Icon = "🧱", Group = "Facade", Choices = {
		c("Auto", "Style material", "🏠", 0),
		c("Render", "Smooth render", "🪣", 20000, 0, { Material = "Plaster" }),
		c("Brick", "Brick", "🧱", 80000, 0, { Material = "Brick" }),
		c("Stone", "Rough stone", "🪨", 250000, 0, { Material = "Cobblestone" }),
		c("Ashlar", "Dressed stone", "🏛️", 800000, 1, { Material = "Limestone" }),
		c("Siding", "Wood siding", "🪵", 150000, 0, { Material = "WoodPlanks" }),
		c("Logs", "Log cabin", "🌲", 1.5e6, 1, { Material = "Wood" }),
		c("Concrete", "Architect concrete", "⬜", 3e6, 1, { Material = "Concrete" }),
		c("Marble", "Marble", "💎", 6e7, 3, { Material = "Marble" }),
	} },
	{ Id = "Trim", Name = "Trim colour", Icon = "🖌️", Group = "Facade", Swatch = true, Choices = {
		c("Auto", "Style trim", "🏠", 0),
		col("White", "White", 8000, rgb(250, 250, 246)),
		col("Cream", "Cream", 8000, rgb(244, 234, 214)),
		col("Oak", "Oak wood", 30000, rgb(168, 120, 78)),
		col("Walnut", "Walnut", 60000, rgb(98, 66, 46)),
		col("Sage", "Sage green", 60000, rgb(128, 148, 116)),
		col("Navy", "Navy", 120000, rgb(46, 60, 88)),
		col("Anthracite", "Anthracite", 200000, rgb(62, 64, 70)),
		col("Black", "Matte black", 400000, rgb(30, 30, 32)),
		col("Pink", "Candy pink", 400000, rgb(236, 140, 176)),
		col("Gold", "Gilded", 5e7, rgb(214, 172, 84), 3),
	} },

	-- 🏠 Toit
	{ Id = "RoofShape", Name = "Roof shape", Icon = "🏠", Group = "Roof", Choices = {
		c("Auto", "Style roof", "🏠", 0),
		c("Gable", "Gable roof", "🔺", 150000, 0, { Value = "Gable" }),
		c("Hip", "Hip roof", "⛺", 300000, 0, { Value = "Hip" }),
		c("Mansard", "Mansard roof", "🏰", 1.5e6, 1, { Value = "Mansard" }),
		c("Flat", "Flat roof terrace", "▬", 3e6, 1, { Value = "Flat" }),
	} },
	{ Id = "RoofMat", Name = "Roof covering", Icon = "🧱", Group = "Roof", Choices = {
		c("Auto", "Style covering", "🏠", 0),
		c("Tiles", "Clay tiles", "🧱", 40000, 0, { Material = "ClayRoofTiles" }),
		c("Slate", "Slate", "🪨", 120000, 0, { Material = "Slate" }),
		c("Shingles", "Shingles", "🪵", 200000, 0, { Material = "RoofShingles" }),
		c("Metal", "Standing seam metal", "🔩", 900000, 1, { Material = "Metal" }),
		c("Thatch", "Thatch", "🌾", 2e6, 1, { Material = "Grass" }),
		c("Copper", "Copper", "🥉", 3e7, 3, { Material = "Metal" }),
	} },
	{ Id = "RoofColor", Name = "Roof colour", Icon = "🎨", Group = "Roof", Swatch = true, Choices = {
		c("Auto", "Style colour", "🏠", 0),
		col("Terracotta", "Terracotta", 15000, rgb(184, 94, 66)),
		col("Clay", "Red clay", 15000, rgb(160, 60, 48)),
		col("Brown", "Chestnut", 30000, rgb(108, 76, 58)),
		col("Slate", "Slate grey", 30000, rgb(92, 100, 112)),
		col("Anthracite", "Anthracite", 60000, rgb(60, 62, 68)),
		col("Black", "Black", 90000, rgb(34, 34, 38)),
		col("Moss", "Moss green", 150000, rgb(84, 108, 70)),
		col("Blue", "Deep blue", 300000, rgb(66, 92, 136)),
		col("Verdigris", "Verdigris", 800000, rgb(104, 158, 138)),
		col("Rose", "Rose", 800000, rgb(212, 122, 142)),
		col("Lilac", "Lilac", 1.5e6, rgb(160, 132, 198)),
		col("Gold", "Royal gold", 2e8, rgb(222, 176, 72), 5),
	} },
	{ Id = "Chimney", Name = "Chimney", Icon = "🏭", Group = "Roof", Choices = {
		c("Auto", "Style chimney", "🏠", 0),
		c("None", "No chimney", "🚫", 5000),
		c("Brick", "Brick chimney", "🧱", 30000),
		c("Stone", "Stone chimney", "🪨", 120000),
		c("Flue", "Steel flue", "🔩", 400000, 1),
	} },

	-- 🪟 Fenêtres
	{ Id = "Window", Name = "Window style", Icon = "🪟", Group = "Windows", Choices = {
		c("Auto", "Style windows", "🏠", 0),
		c("Cross", "French casement", "✚", 25000),
		c("Colonial", "Colonial grid", "▦", 60000),
		c("Arched", "Arched", "⌒", 200000),
		c("Modern", "Slim modern", "▯", 600000, 1),
		c("Industrial", "Steel factory", "▩", 1e6, 1),
	} },
	{ Id = "Shutters", Name = "Shutters", Icon = "🚪", Group = "Windows", Choices = {
		c("None", "No shutters", "🚫", 0),
		c("Louvered", "Louvered shutters", "▤", 40000),
		c("Panel", "Panel shutters", "▯", 60000),
		c("Board", "Z-board shutters", "Ｚ", 90000),
	} },
	{ Id = "ShutterColor", Name = "Shutter colour", Icon = "🎨", Group = "Windows", Swatch = true, Choices = {
		c("Auto", "Matching", "🏠", 0),
		col("White", "White", 8000, rgb(246, 246, 242)),
		col("Sage", "Sage green", 15000, rgb(122, 146, 112)),
		col("Blue", "Provence blue", 15000, rgb(86, 124, 168)),
		col("Red", "Barn red", 30000, rgb(150, 52, 46)),
		col("Lavender", "Lavender", 30000, rgb(160, 140, 196)),
		col("Pink", "Candy pink", 60000, rgb(232, 138, 172)),
		col("Oak", "Oak wood", 60000, rgb(156, 108, 68)),
		col("Black", "Black", 120000, rgb(34, 34, 36)),
	} },

	-- 🚪 Entrée
	{ Id = "Door", Name = "Front door", Icon = "🚪", Group = "Entrance", Choices = {
		c("Auto", "Style door", "🏠", 0),
		c("Panel", "Six-panel", "▦", 30000),
		c("Glazed", "French glazed", "🪟", 90000),
		c("Rustic", "Rustic planks", "🪵", 150000),
		c("Modern", "Modern flush", "▯", 700000, 1),
		c("Grand", "Grand carved", "👑", 2e7, 3),
	} },
	{ Id = "DoorColor", Name = "Door colour", Icon = "🎨", Group = "Entrance", Swatch = true, Choices = {
		c("Auto", "Style colour", "🏠", 0),
		col("White", "White", 8000, rgb(246, 246, 242)),
		col("Oak", "Oak wood", 15000, rgb(160, 112, 70)),
		col("Walnut", "Walnut", 30000, rgb(92, 62, 42)),
		col("Red", "Red", 30000, rgb(172, 44, 44)),
		col("Green", "Racing green", 30000, rgb(40, 84, 60)),
		col("Navy", "Navy", 30000, rgb(40, 54, 90)),
		col("Yellow", "Sunny yellow", 60000, rgb(236, 190, 70)),
		col("Pink", "Candy pink", 60000, rgb(236, 128, 170)),
		col("Lilac", "Lilac", 60000, rgb(170, 140, 210)),
		col("Black", "Gloss black", 150000, rgb(28, 28, 30)),
	} },
	{ Id = "Porch", Name = "Porch", Icon = "🏡", Group = "Entrance", Choices = {
		c("Auto", "Style porch", "🏠", 0),
		c("Canopy", "Glass canopy", "🔲", 50000),
		c("Columns", "Column porch", "🏛️", 300000),
		c("Pergola", "Wooden pergola", "🌿", 600000),
	} },
	{ Id = "Balcony", Name = "Balconies", Icon = "🌇", Group = "Entrance", MinFloors = 2, Choices = {
		c("Auto", "Style balconies", "🏠", 0),
		c("None", "No balcony", "🚫", 5000),
		c("Iron", "Wrought iron", "⚜️", 120000),
		c("Glass", "Glass railing", "🔲", 500000, 1),
		c("Wood", "Wooden balcony", "🪵", 300000),
	} },
	{ Id = "Garage", Name = "Garage", Icon = "🚗", Group = "Entrance", NotStyles = { Mansion = true }, Choices = {
		c("None", "No garage", "🚫", 0),
		c("Garage", "Single garage", "🚗", 2e6, 1),
		c("Carport", "Carport", "🅿️", 600000),
	} },

	-- 🌷 Jardin de devant
	{ Id = "Fence", Name = "Fence", Icon = "🚧", Group = "Garden", Choices = {
		c("Auto", "Style fence", "🏠", 0),
		c("None", "Open lawn", "🌱", 5000),
		c("Picket", "White picket", "🤍", 20000),
		c("Hedge", "Clipped hedge", "🌳", 60000),
		c("Rail", "Split rail", "🪵", 60000),
		c("Iron", "Wrought iron", "⚜️", 200000),
		c("Stone", "Low stone wall", "🪨", 350000),
		c("Slats", "Modern slats", "▥", 900000, 1),
	} },
	{ Id = "Path", Name = "Garden path", Icon = "🛤️", Group = "Garden", Choices = {
		c("Auto", "Style path", "🏠", 0),
		c("Stones", "Stepping stones", "🪨", 10000),
		c("Gravel", "Gravel", "⚪", 20000),
		c("Pavers", "Pavers", "▦", 50000),
		c("Brick", "Herringbone brick", "🧱", 120000),
		c("Deck", "Wooden boardwalk", "🪵", 250000),
	} },
	{ Id = "Mailbox", Name = "Mailbox", Icon = "📫", Group = "Garden", Choices = {
		c("Auto", "Classic post box", "📫", 0),
		c("American", "American mailbox", "📬", 25000),
		c("Pillar", "Modern pillar", "▮", 150000),
		c("Birdhouse", "Birdhouse mailbox", "🐦", 300000),
		c("Wall", "Wall mailbox", "📪", 40000),
	} },
	{ Id = "Lights", Name = "Outdoor lights", Icon = "💡", Group = "Garden", Choices = {
		c("Auto", "Style lanterns", "🏮", 0),
		c("None", "No outdoor lights", "🚫", 3000),
		c("Sconces", "Modern wall lights", "💡", 60000),
		c("Bollards", "Path bollards", "🕯️", 150000),
		c("String", "Fairy lights", "✨", 250000),
	} },
}

HouseOptions.KINDS = KINDS :: { Kind }
HouseOptions.ByKind = {} :: { [string]: Kind }
for _, kind in ipairs(KINDS) do
	kind.ById = {}
	for index, choice in ipairs(kind.Choices) do
		choice.Order = index
		kind.ById[choice.Id] = choice
	end
	HouseOptions.ByKind[kind.Id] = kind
end

-- Onglets de l'éditeur (ordre)
HouseOptions.GROUPS = {
	{ Id = "Style", Name = "Style", Icon = "🏛️" },
	{ Id = "Facade", Name = "Facade", Icon = "🧱" },
	{ Id = "Roof", Name = "Roof", Icon = "🏠" },
	{ Id = "Windows", Name = "Windows", Icon = "🪟" },
	{ Id = "Entrance", Name = "Entrance", Icon = "🚪" },
	{ Id = "Garden", Name = "Garden", Icon = "🌷" },
}

----------------------------------------------------------------------
-- Règles
----------------------------------------------------------------------

function HouseOptions.OwnedKey(kind: string, id: string): string
	return kind .. "." .. id
end

function HouseOptions.Default(kind: string): string
	local def = HouseOptions.ByKind[kind]
	return def and def.Choices[1].Id or ""
end

-- Choix (le 1er = gratuit si l'Id est inconnu)
function HouseOptions.Choice(kind: string, id: any): Choice?
	local def = HouseOptions.ByKind[kind]
	if not def then
		return nil
	end
	return (type(id) == "string" and def.ById[id]) or def.Choices[1]
end

-- Le genre a-t-il un sens pour cette maison ? (balcon sans étage, garage du manoir...)
function HouseOptions.Applies(kind: string, style: string?, floors: number?): boolean
	local def = HouseOptions.ByKind[kind]
	if not def then
		return false
	end
	if def.MinFloors and (floors or 1) < def.MinFloors then
		return false
	end
	if def.NotStyles and style and def.NotStyles[style] then
		return false
	end
	return true
end

local function validNumber(value: any): number
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.clamp(math.floor(n), 0, HouseOptions.MAX_NUMBER)
end
HouseOptions.ValidNumber = validNumber

local function isOwned(owned: any, kind: string, id: string): boolean
	if id == HouseOptions.Default(kind) then
		return true
	end
	return type(owned) == "table" and owned[HouseOptions.OwnedKey(kind, id)] == true
end
HouseOptions.IsOwned = isOwned

-- Extérieur propre : seulement des genres connus, des choix connus ET
-- possédés (sinon le choix gratuit), Num entier 0..9999. Les choix par
-- défaut ne sont pas stockés (données légères).
function HouseOptions.Sanitize(ext: any, owned: any): { [string]: any }
	local clean: { [string]: any } = {}
	if type(ext) ~= "table" then
		return clean
	end
	for _, def in ipairs(KINDS) do
		local id = ext[def.Id]
		if type(id) == "string" and def.ById[id] and id ~= def.Choices[1].Id and isOwned(owned, def.Id, id) then
			clean[def.Id] = id
		end
	end
	local num = validNumber(ext.Num)
	if num > 0 then
		clean.Num = num
	end
	return clean
end

-- Possédés propres : { ["Kind.Id"] = true } connus seulement
function HouseOptions.CleanOwned(owned: any): { [string]: boolean }
	local clean: { [string]: boolean } = {}
	if type(owned) ~= "table" then
		return clean
	end
	for key, value in pairs(owned) do
		if value == true and type(key) == "string" then
			local kind, id = string.match(key, "^(%w+)%.(%w+)$")
			local def = kind and HouseOptions.ByKind[kind]
			if def and id and def.ById[id] then
				clean[key] = true
			end
		end
	end
	return clean
end

-- Prix d'un projet : (total des choix pas encore achetés, liste de ces choix
-- { Kind, Choice }, 1er verrou (choix qui demande plus de visites à l'océan)).
-- Les genres inconnus / choix inconnus sont ignorés (Sanitize les retire).
function HouseOptions.Quote(design: any, owned: any, rebirths: number?): (number, { { Kind: string, Choice: Choice } }, { Kind: string, Choice: Choice }?)
	local total = 0
	local toBuy = {}
	local locked = nil
	if type(design) ~= "table" then
		return 0, toBuy, nil
	end
	for _, def in ipairs(KINDS) do
		local id = design[def.Id]
		local choice = type(id) == "string" and def.ById[id] or nil
		if choice and not isOwned(owned, def.Id, choice.Id) then
			total += choice.Cost
			table.insert(toBuy, { Kind = def.Id, Choice = choice })
			if choice.Rebirths > (rebirths or 0) and not locked then
				locked = { Kind = def.Id, Choice = choice }
			end
		end
	end
	return total, toBuy, locked
end

-- Un Id par genre (défaut compris) + Num
function HouseOptions.Resolve(ext: any): { [string]: any }
	local full: { [string]: any } = {}
	local source = type(ext) == "table" and ext or {}
	for _, def in ipairs(KINDS) do
		local id = source[def.Id]
		full[def.Id] = if type(id) == "string" and def.ById[id] then id else def.Choices[1].Id
	end
	full.Num = validNumber(source.Num)
	return full
end

-- "Kind=Id;Kind=Id;Num=12" (choix non par défaut seulement, ordre du catalogue)
function HouseOptions.Encode(ext: any): string
	local parts = {}
	if type(ext) ~= "table" then
		return ""
	end
	for _, def in ipairs(KINDS) do
		local id = ext[def.Id]
		if type(id) == "string" and def.ById[id] and id ~= def.Choices[1].Id then
			table.insert(parts, def.Id .. "=" .. id)
		end
	end
	local num = validNumber(ext.Num)
	if num > 0 then
		table.insert(parts, "Num=" .. num)
	end
	return table.concat(parts, ";")
end

function HouseOptions.Decode(text: any): { [string]: any }
	local ext: { [string]: any } = {}
	if type(text) ~= "string" or #text > 2000 then
		return ext
	end
	for key, value in string.gmatch(text, "(%w+)=(%w+)") do
		if key == "Num" then
			ext.Num = validNumber(value)
		else
			local def = HouseOptions.ByKind[key]
			if def and def.ById[value] then
				ext[key] = value
			end
		end
	end
	return ext
end

return HouseOptions
