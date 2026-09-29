--[[
	GardenSnapshot (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > GardenSnapshot

	🌻 Résumé du Jardin de Dopamine d'un joueur, pour l'instantané de la
	ville (WorldService -> clients -> GardenBuilder). Fonction PURE :
	  - accepte les données du serveur (data) OU l'état du client
	    (ClientState.Data : mêmes champs Upgrades / Garden / House) ;
	  - ne lève jamais d'erreur (sauvegarde abîmée : valeurs ignorées) ;
	  - sûr pour le JSON et les RemoteEvents : clés texte, tableaux denses,
	    nombres finis, aucune Instance / aucun Color3 ;
	  - PETIT et STABLE : pas d'heure "Now" dedans (sinon la signature JSON de
	    WorldService changerait à chaque vérification) ; le client prend
	    l'heure du serveur avec workspace:GetServerTimeNow().

	GardenSnapshot.From(data) -> {
		Unlocked = bool,         -- Feature "Garden" possédée
		Count = n,               -- parterres possédés (BasePlots + "Flower Beds")
		Max = n,                 -- parterres possibles au maximum
		Windmill = bool,         -- moulin (Feature "Pinwheel") : déco du jardin
		Plots = { { Flower = "Daisy", PlantedAt = t, ReadyAt = t }, ... },
		-- v9.8 (GARDEN98) jardin aménagé librement :
		Level = 0..3,            -- agrandissements (Config.Garden.Expansion)
		Size = "Studio",         -- taille de la maison (zones du jardin)
		Decor = { id, ... },     -- déco du jardin sortie (data.House.Garden)
		Layout = { [clé] = { X, D, R } }, -- places choisies (repère de la maison)
	}
	GardenSnapshot.Sanitize(snapshot) -> même forme, validée (côté client :
	un instantané venu du réseau n'est jamais cru sur parole).
	GardenSnapshot.Progress(plot, now) -> (progress 0..1, prêt ?, secondes restantes)
	GardenSnapshot.Stage(plot, now) -> "Seed" | "Sprout" | "Bud" | "Bloom" | "Ready"

	v9.8 (GARDEN98) — règles PARTAGÉES du jardin libre (client, serveur, tests) :
	  Repère = celui de la maison (WorldLayout) : x vers la droite du visiteur
	  qui regarde la maison depuis la rue, d = profondeur depuis la façade
	  (d < 0 : jardin de devant, d > profondeur de la maison : jardin de
	  derrière). R = rotation en degrés (multiple de 15) ; R = 0 : l'objet
	  regarde la rue.
	  Clés des objets du jardin :
	    "B<i>"          parterre de Dopamine n° i (toujours posé)
	    "D:<id>"        déco du jardin (Config.House.GardenDecor) sortie
	    "P:<id>:<n>"    n-ième exemplaire d'un objet de jardin (Config.Garden.Pieces)
	    "F:<id>"        aménagement fixe : panneau, allées, lanternes, moulin,
	                    buissons, arrosoir, et les bonus des agrandissements
	  GardenSnapshot.Level(data) / LevelInfo(level) / DecorSlots(level) / PieceCap(level)
	  GardenSnapshot.OwnedPieces(data) -> { [id] = n }
	  GardenSnapshot.Footprint(key) -> (largeur, profondeur, plat ?)
	  GardenSnapshot.Zones(level, sizeId) -> { { X0, X1, D0, D1 } } ; Corridors(sizeId)
	  GardenSnapshot.Fits(level, sizeId, key, x, d, r) -> bool
	  GardenSnapshot.CleanLayout(raw, ctx) -> { [clé] = { X, D, R } } (tout vérifié)
	  GardenSnapshot.Fixtures(level, windmill) -> { "F:..." }
	  GardenSnapshot.Arrange(snapshot) -> { { Key, X, D, R, W, Dp, Flat, Moved } }
	      (tout ce qui est affiché, places par défaut comprises : même calcul
	      sur tous les clients -> tout le monde voit le même jardin)
]]

local Config = require(script.Parent.Config)

local GardenSnapshot = {}

GardenSnapshot.MAX_PLOTS = 24 -- même garde-fou que GardenService
GardenSnapshot.STAGES = { "Seed", "Sprout", "Bud", "Bloom", "Ready" }

local settings = Config.Garden or {}
local flowersById: { [string]: any } = {}
for _, flower in ipairs(settings.Flowers or {}) do
	flowersById[flower.Id] = flower
end
GardenSnapshot.FlowersById = flowersById

-- (WorldLayout facultatif : absent dans certains tests -> calcul de secours)
local WorldLayout: any = nil
pcall(function()
	local parent: any = script.Parent
	local module = parent.WorldLayout
	if module ~= nil then
		local loaded = require(module)
		if type(loaded) == "table" and type(loaded.Dims) == "function" then
			WorldLayout = loaded
		end
	end
end)

local function finite(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- Niveau d'une amélioration (données éventuellement incomplètes)
local function levelOf(data: any, upgradeId: string?): number
	if not upgradeId or type(data) ~= "table" or type(data.Upgrades) ~= "table" then
		return 0
	end
	return math.max(0, math.floor(finite(data.Upgrades[upgradeId]) or 0))
end

-- Amélioration qui porte une Feature (Config.FeatureToUpgrade, sinon on cherche)
local function upgradeFor(feature: string): string?
	local map = Config.FeatureToUpgrade
	if type(map) == "table" and type(map[feature]) == "string" then
		return map[feature]
	end
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == feature then
			return upgrade.Id
		end
	end
	return nil
end

-- Nombre maximum de parterres (tous les niveaux de "Flower Beds" achetés)
function GardenSnapshot.MaxPlots(): number
	local count = settings.BasePlots or 3
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == "GardenPlots" then
			count += math.max(0, math.floor(finite(upgrade.MaxLevel) or 0))
		end
	end
	return math.clamp(count, 1, GardenSnapshot.MAX_PLOTS)
end

-- Nombre de parterres possédés (même règle que Formulas.GetGardenPlotCount)
function GardenSnapshot.PlotCount(data: any): number
	local count = settings.BasePlots or 3
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == "GardenPlots" then
			count += levelOf(data, upgrade.Id)
		end
	end
	return math.clamp(math.floor(count), 1, GardenSnapshot.MAX_PLOTS)
end

-- Un parterre valide (copie propre) ou nil (parterre vide / abîmé)
local function cleanPlot(plot: any): { Flower: string, PlantedAt: number, ReadyAt: number }?
	if type(plot) ~= "table" or type(plot.Flower) ~= "string" or not flowersById[plot.Flower] then
		return nil
	end
	local plantedAt, readyAt = finite(plot.PlantedAt), finite(plot.ReadyAt)
	if not plantedAt or not readyAt then
		return nil
	end
	plantedAt, readyAt = math.floor(plantedAt), math.floor(readyAt)
	if readyAt < plantedAt then
		readyAt = plantedAt
	end
	return { Flower = plot.Flower, PlantedAt = plantedAt, ReadyAt = readyAt }
end

local function emptyPlot(): any
	-- (JSON : un tableau dense ne peut pas contenir nil -> "vide" = Flower "")
	return { Flower = "", PlantedAt = 0, ReadyAt = 0 }
end

----------------------------------------------------------------------
-- v9.8 (GARDEN98) : agrandissements, objets de jardin
----------------------------------------------------------------------

local EXPANSION: { any } = settings.Expansion or {}
GardenSnapshot.MAX_LEVEL = #EXPANSION
local piecesById: { [string]: any } = {}
for _, piece in ipairs(settings.Pieces or {}) do
	piecesById[piece.Id] = piece
end
GardenSnapshot.PiecesById = piecesById
GardenSnapshot.MAX_ENTRIES = 128 -- garde-fou (taille de la sauvegarde / du réseau)
GardenSnapshot.ROTATION_STEP = 15
GardenSnapshot.GRID = 0.5 -- (studs) aimant de la grille du mode édition

local function baseDecorSlots(): number
	local house: any = Config.House
	return math.max(1, math.floor(finite(house and house.GardenSlots) or 6))
end

-- Niveau du jardin 0..MAX_LEVEL (data.Garden.Level, ou un nombre)
function GardenSnapshot.Level(data: any): number
	local value: any = data
	if type(data) == "table" then
		local garden = data.Garden
		value = type(garden) == "table" and garden.Level or 0
	end
	return math.clamp(math.floor(finite(value) or 0), 0, GardenSnapshot.MAX_LEVEL)
end

-- Entrée de Config.Garden.Expansion pour un niveau (nil au niveau 0)
function GardenSnapshot.LevelInfo(level: number): any?
	return EXPANSION[math.floor(finite(level) or 0)]
end

-- Places de déco du jardin (data.House.Garden) à ce niveau
function GardenSnapshot.DecorSlots(level: number): number
	local info = GardenSnapshot.LevelInfo(level)
	return math.max(baseDecorSlots(), info and math.floor(finite(info.DecorSlots) or 0) or 0)
end

-- Objets de jardin POSÉS au plus à ce niveau
function GardenSnapshot.PieceCap(level: number): number
	local info = GardenSnapshot.LevelInfo(level)
	local base = math.floor(finite(settings.BasePieces) or 8)
	return math.max(base, info and math.floor(finite(info.Pieces) or 0) or 0)
end

-- Prix du prochain exemplaire d'un objet de jardin (+15 % par exemplaire possédé)
function GardenSnapshot.PieceCost(piece: any, owned: number?): number
	local base = type(piece) == "table" and finite(piece.Cost) or nil
	if not base or base < 0 then
		return math.huge
	end
	local n = math.max(0, math.floor(finite(owned) or 0))
	return math.floor(base * 1.15 ^ n + 0.5)
end

-- Objets de jardin possédés (data.Garden.Pieces), nettoyés : entiers 1..Max
function GardenSnapshot.OwnedPieces(data: any): { [string]: number }
	local owned = {}
	local garden = type(data) == "table" and data.Garden
	local source = type(garden) == "table" and garden.Pieces
	if type(source) ~= "table" then
		return owned
	end
	for id, count in pairs(source) do
		local piece = type(id) == "string" and piecesById[id] or nil
		local n = finite(count)
		if piece and n and n >= 1 then
			owned[id] = math.min(math.floor(n), math.floor(finite(piece.Max) or 10))
		end
	end
	return owned
end

-- Empreintes (studs) : déco du jardin (dessins de HouseGarden), aménagements
local DECOR_SIZE: { [string]: { number } } = {
	TulipBed = { 4.6, 2.4 }, GardenGnome = { 1.6, 1.6 }, PinkFlamingo = { 1.8, 1.6 }, Birdbath = { 2.8, 2.8 },
	Beehive = { 2.4, 2.4 }, DuckPond = { 5.6, 5.6 }, PumpkinPatch = { 4.4, 2.4 }, Snowman = { 2.2, 2.2 },
	WishingWell = { 4.6, 3.2 }, Trampoline = { 5.6, 5.6 }, RainbowArch = { 6.4, 2 }, UnicornStatue = { 3.2, 2.4 },
	YardHoop = { 3, 3.6 }, CampTent = { 4.8, 4.2 }, BBQGrill = { 2.2, 2.2 }, YardGoal = { 5.4, 3.8 },
	SkateRamp = { 4.2, 4.8 }, Treehouse = { 5.8, 5.8 }, DinoStatue = { 6.6, 3.2 },
}
local FIXTURE_SIZE: { [string]: { any } } = {
	Sign = { 6.4, 1.6 }, Windmill = { 3.4, 3.4 }, Lantern1 = { 1.2, 1.2 }, Lantern2 = { 1.2, 1.2 },
	Path1 = { 20, 3.6, true }, Path2 = { 20, 3.6, true }, Can = { 1.6, 1.6 }, Bush1 = { 4, 3.2 }, Bush2 = { 4, 3.2 },
	RoseArch = { 5.6, 2.2 }, Greenhouse = { 10.2, 7.2 }, KoiPond = { 9.2, 6.2 },
}
GardenSnapshot.BED_SIZE = { 6.6, 4 }

-- Découpe une clé : ("B", "3") / ("D", id) / ("P", id, n) / ("F", id) ; nil si invalide
function GardenSnapshot.Parse(key: any): (string?, string?, number?)
	if type(key) ~= "string" or #key > 48 then
		return nil, nil, nil
	end
	local bed = string.match(key, "^B(%d+)$")
	if bed then
		return "B", bed, tonumber(bed)
	end
	local kind, rest = string.match(key, "^([DPF]):(.+)$")
	if kind == "P" then
		local id, n = string.match(rest, "^([%w_]+):(%d+)$")
		if id and n then
			return "P", id, tonumber(n)
		end
		return nil, nil, nil
	elseif kind == "D" or kind == "F" then
		if string.match(rest, "^[%w_]+$") then
			return kind, rest, nil
		end
	end
	return nil, nil, nil
end

-- Empreinte (largeur x, profondeur d, plat ?) d'un objet du jardin
function GardenSnapshot.Footprint(key: string): (number, number, boolean)
	local kind, id = GardenSnapshot.Parse(key)
	if kind == "B" then
		return GardenSnapshot.BED_SIZE[1], GardenSnapshot.BED_SIZE[2], false
	elseif kind == "D" then
		local size = DECOR_SIZE[id :: string]
		if size then
			return size[1], size[2], false
		end
		return 4, 4, false
	elseif kind == "P" then
		local piece = piecesById[id :: string]
		if piece then
			return finite(piece.W) or 2, finite(piece.D) or 2, piece.Flat == true
		end
	elseif kind == "F" then
		local size = FIXTURE_SIZE[id :: string]
		if size then
			return size[1], size[2], size[3] == true
		end
	end
	return 2, 2, false
end

-- Aménagements présents (panneau, allées, lanternes... + bonus des niveaux)
function GardenSnapshot.Fixtures(level: number, windmill: boolean?): { string }
	local list = { "F:Sign", "F:Path1", "F:Path2", "F:Lantern1", "F:Lantern2", "F:Can", "F:Bush1", "F:Bush2" }
	if windmill then
		table.insert(list, "F:Windmill")
	end
	for index = 1, math.clamp(math.floor(finite(level) or 0), 0, GardenSnapshot.MAX_LEVEL) do
		local bonus = EXPANSION[index] and EXPANSION[index].Bonus
		if type(bonus) == "string" and FIXTURE_SIZE[bonus] then
			table.insert(list, "F:" .. bonus)
		end
	end
	return list
end

----------------------------------------------------------------------
-- Zones du jardin (repère de la maison)
----------------------------------------------------------------------

local PLOT_HALF = 86.5 -- (studs) bord de la parcelle (176 / 2 - la haie)
local FRONT_STREET = -28.5 -- jardin de devant côté rue
local FRONT_FENCE = -20.2 -- ... côté intérieur de la clôture de devant
local FRONT_HOUSE = -1.2 -- ... devant la façade
local BACK_FENCE = 52 -- fond de la parcelle (clôture à 52,5)
local HOUSE_DEPTH = 26

local function sizeDef(sizeId: any): any
	local byId: any = Config.HouseSizesById
	return type(sizeId) == "string" and byId and byId[sizeId] or (Config.House and Config.House.Sizes and Config.House.Sizes[1]) or nil
end

-- (demi-largeur de la maison, profondeur, x de la porte, x de la porte de derrière?)
local function houseGeometry(sizeId: any): (number, number, number, number?)
	local size = sizeDef(sizeId)
	if WorldLayout then
		local ok, dims = pcall(WorldLayout.Dims, size)
		if ok and type(dims) == "table" then
			local okDoor, doorX = pcall(WorldLayout.DoorX, size)
			local backX: number? = nil
			if type(WorldLayout.BackDoorX) == "function" then
				local okBack, value = pcall(WorldLayout.BackDoorX, size)
				backX = okBack and finite(value) or nil
			end
			return dims.Width / 2, dims.Depth, okDoor and finite(doorX) or 0, backX
		end
	end
	-- secours (tests sans WorldLayout) : même formule que WorldLayout.Dims
	local columns = size and finite(size.Columns) or 2
	local widthFactor = size and finite(size.Width) or 1
	local roomW = math.floor(760 * widthFactor + 0.5) * 0.036
	return (12 + columns * (roomW + 2)) / 2, HOUSE_DEPTH, 0, nil
end
GardenSnapshot.HouseGeometry = houseGeometry

-- Rectangles où l'on peut poser (tout l'objet doit tenir dans l'un d'eux)
function GardenSnapshot.Zones(level: number, sizeId: any): { { number } }
	local half, depth = houseGeometry(sizeId)
	local lv = math.clamp(math.floor(finite(level) or 0), 0, GardenSnapshot.MAX_LEVEL)
	local back0 = depth + 2.2
	local zones = {}
	if lv == 0 then
		local w = math.min(PLOT_HALF, half + 3.8)
		table.insert(zones, { -w, w, FRONT_FENCE, FRONT_HOUSE })
		table.insert(zones, { -40, 40, back0, BACK_FENCE })
	elseif lv == 1 then
		table.insert(zones, { -PLOT_HALF, PLOT_HALF, FRONT_STREET, FRONT_HOUSE })
		table.insert(zones, { -62, 62, back0, BACK_FENCE })
	else
		table.insert(zones, { -PLOT_HALF, PLOT_HALF, FRONT_STREET, FRONT_HOUSE })
		table.insert(zones, { -PLOT_HALF, PLOT_HALF, back0, BACK_FENCE })
		-- côtés de la maison (petites maisons)
		local side0 = half + 1.5
		if side0 + 2 < PLOT_HALF then
			table.insert(zones, { side0, PLOT_HALF, FRONT_HOUSE - 0.5, back0 + 0.5 })
			table.insert(zones, { -PLOT_HALF, -side0, FRONT_HOUSE - 0.5, back0 + 0.5 })
		end
	end
	return zones
end

-- Couloirs toujours libres : allée de la porte d'entrée, sortie de derrière
function GardenSnapshot.Corridors(sizeId: any): { { number } }
	local _, depth, doorX, backX = houseGeometry(sizeId)
	local list = { { doorX - 3.2, doorX + 3.2, -31, 0.5 } }
	if backX then
		table.insert(list, { backX - 3.2, backX + 3.2, depth - 0.5, depth + 7.5 })
	end
	return list
end

-- Demi-empreinte (x, d) une fois tournée de r degrés
local function halfExtents(w: number, dp: number, r: number): (number, number)
	local a = math.rad(r)
	local c, s = math.abs(math.cos(a)), math.abs(math.sin(a))
	return (w * c + dp * s) / 2, (w * s + dp * c) / 2
end
GardenSnapshot.HalfExtents = halfExtents

-- Rotation valide (degrés, multiple de 15, 0..345)
function GardenSnapshot.Rotation(value: any): number
	local r = finite(value) or 0
	return (math.floor(r / GardenSnapshot.ROTATION_STEP + 0.5) * GardenSnapshot.ROTATION_STEP) % 360
end

-- L'objet `key` tient-il en (x, d, r) ? (zones du niveau, couloirs libres)
function GardenSnapshot.Fits(level: number, sizeId: any, key: string, x: number, d: number, r: number): boolean
	local fx, fd = finite(x), finite(d)
	if not fx or not fd then
		return false
	end
	local w, dp, flat = GardenSnapshot.Footprint(key)
	local hx, hd = halfExtents(w, dp, GardenSnapshot.Rotation(r))
	local inside = false
	for _, zone in ipairs(GardenSnapshot.Zones(level, sizeId)) do
		if fx - hx >= zone[1] - 0.01 and fx + hx <= zone[2] + 0.01 and fd - hd >= zone[3] - 0.01 and fd + hd <= zone[4] + 0.01 then
			inside = true
			break
		end
	end
	if not inside then
		return false
	end
	if not flat then
		for _, lane in ipairs(GardenSnapshot.Corridors(sizeId)) do
			if fx + hx > lane[1] and fx - hx < lane[2] and fd + hd > lane[3] and fd - hd < lane[4] then
				return false
			end
		end
	end
	return true
end

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- Disposition reçue (client, sauvegarde, réseau) -> disposition sûre.
-- ctx = { Level, Size, Beds (nombre de parterres affichés), Decor = { [id] = true },
--         Pieces = { [id] = n } (nil : jusqu'au Max de l'objet), Windmill }
function GardenSnapshot.CleanLayout(raw: any, ctx: any): { [string]: any }
	local clean = {}
	if type(raw) ~= "table" or type(ctx) ~= "table" then
		return clean
	end
	local level = GardenSnapshot.Level(ctx.Level)
	local beds = math.clamp(math.floor(finite(ctx.Beds) or 0), 0, GardenSnapshot.MAX_PLOTS)
	local decor = type(ctx.Decor) == "table" and ctx.Decor or {}
	local owned = type(ctx.Pieces) == "table" and ctx.Pieces or nil
	local fixtures = {}
	for _, key in ipairs(GardenSnapshot.Fixtures(level, ctx.Windmill == true)) do
		fixtures[key] = true
	end
	-- (ordre stable : les clés triées -> même résultat partout)
	local keys = {}
	for key in pairs(raw) do
		if type(key) == "string" and #key <= 48 then
			table.insert(keys, key)
		end
		if #keys > GardenSnapshot.MAX_ENTRIES * 2 then
			break
		end
	end
	table.sort(keys)
	local count, pieces = 0, 0
	local cap = GardenSnapshot.PieceCap(level)
	for _, key in ipairs(keys) do
		if count >= GardenSnapshot.MAX_ENTRIES then
			break
		end
		local entry = raw[key]
		local kind, id, n = GardenSnapshot.Parse(key)
		local allowed = false
		if kind == "B" then
			allowed = n ~= nil and n >= 1 and n <= beds and key == "B" .. tostring(n)
		elseif kind == "D" then
			allowed = decor[id :: string] == true
		elseif kind == "P" then
			local piece = piecesById[id :: string]
			local limit = if owned then (owned[id :: string] or 0) else (piece and math.floor(finite(piece.Max) or 10) or 0)
			allowed = piece ~= nil and n ~= nil and n >= 1 and n <= limit and pieces < cap and key == "P:" .. id .. ":" .. tostring(n)
		elseif kind == "F" then
			allowed = fixtures[key] == true
		end
		if allowed and type(entry) == "table" then
			local x, d = finite(entry.X), finite(entry.D)
			local r = GardenSnapshot.Rotation(entry.R)
			if x and d then
				x, d = round(x, 0.05), round(d, 0.05)
				if GardenSnapshot.Fits(level, ctx.Size, key, x, d, r) then
					clean[key] = { X = x, D = d, R = r }
					count += 1
					if kind == "P" then
						pieces += 1
					end
				end
			end
		end
	end
	return clean
end

-- Déco sortie (data.House.Garden) : ids texte, sans doublon, places du niveau
local function decorOf(data: any, level: number): { string }
	local list = {}
	local house = type(data) == "table" and data.House
	local source = type(house) == "table" and house.Garden
	if type(source) ~= "table" then
		return list
	end
	local seen = {}
	local slots = GardenSnapshot.DecorSlots(level)
	for _, id in ipairs(source) do
		if #list >= slots then
			break
		end
		if type(id) == "string" and #id <= 64 and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	return list
end

local function setOf(list: { string }): { [string]: boolean }
	local set = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	return set
end

-- Nombre de parterres affichés (et donc déplaçables) pour un instantané
local function bedsShown(unlocked: boolean, count: number): number
	if unlocked then
		return count
	end
	return math.max(1, settings.BasePlots or 3)
end

function GardenSnapshot.From(data: any): { [string]: any }
	local count = GardenSnapshot.PlotCount(data)
	local unlocked = levelOf(data, upgradeFor(settings.Feature or "Garden")) > 0
	local plots = {}
	local garden = type(data) == "table" and data.Garden
	local source = type(garden) == "table" and type(garden.Plots) == "table" and garden.Plots or nil
	if unlocked then
		for index = 1, count do
			plots[index] = (source and cleanPlot(source[index])) or emptyPlot()
		end
	end
	local windmill = levelOf(data, upgradeFor("Pinwheel")) > 0
	local level = GardenSnapshot.Level(data)
	local house = type(data) == "table" and data.House
	local sizeId = type(house) == "table" and type(house.Size) == "string" and house.Size or nil
	if sizeId and not sizeDef(sizeId) then
		sizeId = nil
	end
	local decor = decorOf(data, level)
	local layout = GardenSnapshot.CleanLayout(type(garden) == "table" and garden.Layout or nil, {
		Level = level,
		Size = sizeId,
		Beds = bedsShown(unlocked, count),
		Decor = setOf(decor),
		Pieces = GardenSnapshot.OwnedPieces(data),
		Windmill = windmill,
	})
	return {
		Unlocked = unlocked,
		Count = count,
		Max = math.max(count, GardenSnapshot.MaxPlots()),
		Windmill = windmill,
		Plots = plots,
		Level = level,
		Size = sizeId or (Config.House.Sizes[1] and Config.House.Sizes[1].Id) or "Studio",
		Decor = decor,
		Layout = layout,
	}
end

-- Instantané reçu du réseau -> forme garantie (nil / n'importe quoi accepté)
function GardenSnapshot.Sanitize(snapshot: any): { [string]: any }
	local defaultSize = (Config.House.Sizes[1] and Config.House.Sizes[1].Id) or "Studio"
	if type(snapshot) ~= "table" then
		return { Unlocked = false, Count = settings.BasePlots or 3, Max = GardenSnapshot.MaxPlots(), Windmill = false, Plots = {},
			Level = 0, Size = defaultSize, Decor = {}, Layout = {} }
	end
	local count = math.clamp(math.floor(finite(snapshot.Count) or (settings.BasePlots or 3)), 1, GardenSnapshot.MAX_PLOTS)
	local maxPlots = math.clamp(math.floor(finite(snapshot.Max) or count), count, GardenSnapshot.MAX_PLOTS)
	local unlocked = snapshot.Unlocked == true
	local plots = {}
	if unlocked then
		local source = type(snapshot.Plots) == "table" and snapshot.Plots or {}
		for index = 1, count do
			plots[index] = cleanPlot(source[index]) or emptyPlot()
		end
	end
	local level = GardenSnapshot.Level(snapshot.Level)
	local sizeId = type(snapshot.Size) == "string" and sizeDef(snapshot.Size) and snapshot.Size or defaultSize
	local decor = decorOf({ House = { Garden = snapshot.Decor } }, level)
	local windmill = snapshot.Windmill == true
	local layout = GardenSnapshot.CleanLayout(snapshot.Layout, {
		Level = level,
		Size = sizeId,
		Beds = bedsShown(unlocked, count),
		Decor = setOf(decor),
		Pieces = nil,
		Windmill = windmill,
	})
	return { Unlocked = unlocked, Count = count, Max = maxPlots, Windmill = windmill, Plots = plots,
		Level = level, Size = sizeId, Decor = decor, Layout = layout }
end

----------------------------------------------------------------------
-- Places par défaut (tout ce qui n'a pas été déplacé) : même calcul partout
----------------------------------------------------------------------

local BACK_CENTER = (HOUSE_DEPTH + 2.5 + BACK_FENCE + 0.5) / 2 -- 40,5 : milieu du jardin de derrière
GardenSnapshot.BACK_CENTER = BACK_CENTER
local BED_PITCH = 9.8

-- Parterres par défaut : 1 rangée jusqu'à 5, sinon 2 de part et d'autre de
-- l'allée (celle du côté de la maison tournée vers l'allée)
function GardenSnapshot.BedSlots(total: number): ({ { number } }, number, number, number)
	local rows = total <= 5 and 1 or 2
	local perRow = math.max(1, math.ceil(total / rows))
	local rowD = rows == 1 and { BACK_CENTER + 1.6 } or { BACK_CENTER - 4.4, BACK_CENTER + 4.4 }
	local pathD = rows == 1 and BACK_CENTER - 2.8 or BACK_CENTER
	local slots = {}
	local index = 0
	for row = 1, rows do
		local count = math.min(perRow, total - index)
		for k = 1, count do
			index += 1
			slots[index] = { (k - (count + 1) / 2) * BED_PITCH, rowD[row], (rows == 2 and row == 1) and 180 or 0 }
		end
	end
	local halfLength = perRow * BED_PITCH / 2
	local backD = rows == 1 and (BACK_CENTER + 5) or (BACK_CENTER + 7.6)
	return slots, pathD, halfLength, backD
end

-- Tout ce qui est affiché dans le jardin, avec sa place (choisie ou par défaut)
function GardenSnapshot.Arrange(snapshot: any): { any }
	local state = snapshot
	local list = {}
	local layout = type(state.Layout) == "table" and state.Layout or {}
	local level = GardenSnapshot.Level(state.Level)
	local half, _, doorX = houseGeometry(state.Size)
	local beds = bedsShown(state.Unlocked == true, math.floor(finite(state.Count) or 3))
	local ghost = state.Unlocked == true and (finite(state.Max) or 0) > beds
	local slots, pathD, halfLength, backD = GardenSnapshot.BedSlots(beds + (ghost and 1 or 0))
	local function add(key: string, x: number, d: number, r: number)
		local w, dp, flat = GardenSnapshot.Footprint(key)
		local chosen = layout[key]
		local moved = type(chosen) == "table"
		table.insert(list, {
			Key = key,
			X = moved and chosen.X or x,
			D = moved and chosen.D or d,
			R = moved and chosen.R or r,
			W = w,
			Dp = dp,
			Flat = flat,
			Moved = moved,
		})
	end
	for index = 1, beds do
		local slot = slots[index]
		add("B" .. index, slot[1], slot[2], slot[3])
	end
	if ghost then
		local slot = slots[beds + 1]
		add("G", slot[1], slot[2], slot[3])
	end
	-- aménagements (autour de l'allée des parterres)
	local fixed: { [string]: { number } } = {
		["F:Path1"] = { -10.1, pathD, 0 },
		["F:Path2"] = { 10.1, pathD, 0 },
		["F:Sign"] = { -(halfLength + 3.6), pathD - 3.1, 345 },
		["F:Lantern1"] = { -(halfLength + 1.2), pathD + 2.6, 0 },
		["F:Lantern2"] = { halfLength + 1.2, pathD + 2.6, 0 },
		["F:Can"] = { -(halfLength - 1.5), pathD - 1.6, 30 },
		["F:Bush1"] = { -(halfLength + 2.6), backD, 0 },
		["F:Bush2"] = { halfLength + 2.6, backD, 0 },
		["F:Windmill"] = { halfLength + 6.8, backD - 0.5, 0 },
		["F:RoseArch"] = { halfLength + 13, pathD, 90 },
		["F:Greenhouse"] = { -(halfLength + 18), BACK_CENTER + 2.4, 0 },
		["F:KoiPond"] = { halfLength + 22, BACK_CENTER + 2.4, 0 },
	}
	for _, key in ipairs(GardenSnapshot.Fixtures(level, state.Windmill == true)) do
		local spot = fixed[key]
		if spot then
			add(key, spot[1], spot[2], spot[3])
		end
	end
	-- déco du jardin sortie : devant la maison (6 par rangée, comme la 2D)
	local decor = type(state.Decor) == "table" and state.Decor or {}
	local perRow = baseDecorSlots()
	local x0 = -math.min(PLOT_HALF - 2, half + 4)
	local x1 = math.min(PLOT_HALF - 2, half + 4)
	local mansion = state.Size == "Mansion"
	if mansion then
		x1 = math.min(x1, 43) -- (v9.6 : place de l'aile du garage)
	end
	local margin = (x1 - x0) * 0.07
	local spacing = (x1 - x0 - margin * 2) / math.max(1, perRow)
	for index, id in ipairs(decor) do
		local row = math.floor((index - 1) / perRow)
		local column = (index - 1) % perRow + 1
		local x = x0 + margin + (column - 0.5) * spacing
		local clear = if mansion then 9 else 5
		if math.abs(x - doorX) < clear then
			x = doorX + (if x < doorX then -clear else clear)
		end
		add("D:" .. id, x, row == 0 and -15 or -8.8, 0)
	end
	-- objets de jardin posés (seulement ceux qui ont une place)
	local pieceKeys = {}
	for key in pairs(layout) do
		if string.sub(key, 1, 2) == "P:" then
			table.insert(pieceKeys, key)
		end
	end
	table.sort(pieceKeys)
	for _, key in ipairs(pieceKeys) do
		local entry = layout[key]
		add(key, entry.X, entry.D, entry.R)
	end
	return list
end

----------------------------------------------------------------------
-- Pousse des fleurs
----------------------------------------------------------------------

-- Avancement d'un parterre à l'heure `now` (heure du serveur)
function GardenSnapshot.Progress(plot: any, now: number): (number, boolean, number)
	if type(plot) ~= "table" or not flowersById[plot.Flower] then
		return 0, false, 0
	end
	local plantedAt = finite(plot.PlantedAt) or now
	local readyAt = finite(plot.ReadyAt) or now
	local total = math.max(1, readyAt - plantedAt)
	local remaining = math.max(0, readyAt - now)
	local ready = now >= readyAt
	return ready and 1 or math.clamp(1 - remaining / total, 0, 1), ready, remaining
end

-- Stade visible : graine -> pousse -> bouton -> fleur -> prête (scintille)
function GardenSnapshot.Stage(plot: any, now: number): string
	if type(plot) ~= "table" or not flowersById[plot.Flower] then
		return "Empty"
	end
	local progress, ready = GardenSnapshot.Progress(plot, now)
	if ready then
		return "Ready"
	elseif progress < 0.12 then
		return "Seed"
	elseif progress < 0.45 then
		return "Sprout"
	elseif progress < 0.8 then
		return "Bud"
	end
	return "Bloom"
end

return GardenSnapshot
