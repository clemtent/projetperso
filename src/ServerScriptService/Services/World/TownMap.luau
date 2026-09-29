--[[
	TownMap (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownMap

	🚶 Dopamine Town (v9.4) : construit UNE fois, au démarrage du serveur, la
	ville commune dans Workspace > DopamineTown (≈ 3 500 Parts ancrées, 16
	vraies lumières au plus, rien par image) :
	  - TownPlaza     : place pavée, fontaine au cerveau, kiosque, manège,
	                    guirlandes, mairie + GRAND ÉCRAN des meilleurs joueurs,
	                    couronne de boutiques ;
	  - TownStreets   : boulevard polygonal devant les parcelles, avenue
	                    "rambla" de l'entrée à la place, rues latérales,
	                    passages piétons, mobilier, voitures garées ;
	  - TownEntrance  : GRANDE PORTE "DOPAMINE TOWN", place d'accueil, point
	                    d'apparition, plan de la ville (propriétaires), bus,
	                    parking ;
	  - TownNature    : lac + pont, aire de jeux, marché, jardin, basket,
	                    arbres, bois, collines, montagnes, ville lointaine,
	                    murs invisibles ;
	  - TownShops (v9.6) : les boutiques où l'on ENTRE (6 autour de la place,
	                    placées par TownPlaza) et la 🚗 concession auto (à
	                    droite de la place d'accueil), dans le dossier Shops ;
	  - TownMarket (v9.7) : le 🛒 supermarché MégaDopa et son parking, hors
	                    de la porte (WorldLayout.MarketCFrame), dossier Market ;
	  - ici : les N parcelles (WorldLayout) : pelouse, clôtures, haie, arbres,
	    boîte aux lettres et panneau du propriétaire (SetPlotSign, appelé par
	    WorldService) ; le grand écran et le plan suivent les panneaux.
	Les MAISONS ne sont pas ici : chaque client les construit (HouseBuilder).

	Contrat (ENTRY94 / WorldService) :
	  TownMap.SpawnCFrame() -> CFrame : pieds ~3 studs au-dessus du pavé,
	    juste à l'intérieur de la porte, regard vers l'avenue et la place ;
	  attributs de Workspace.DopamineTown : PlotCount, EntranceCF (= SpawnCFrame),
	    PlazaCF (centre de la place au sol), GateCF (arche, LookVector vers la
	    place), TownRadius (murs) ;
	  dossier Seats (sièges créés par WorldService) ; dossier Shops (v9.6 :
	    boutiques où l'on entre, attributs ShopId / InteriorCF… : TownShops) ;
	    attribut Shops (nombre de boutiques) ; Town.PlazaCFrame =
	    SpawnCFrame (retour de chute / apparition sans parcelle).
	  Les TextLabel des panneaux fixes ont un attribut "LocText" (clé anglaise) :
	  le client peut les traduire (Locale.T).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownStreets = require(script.Parent.TownStreets)
local TownPlaza = require(script.Parent.TownPlaza)
local TownEntrance = require(script.Parent.TownEntrance)
local TownNature = require(script.Parent.TownNature)
local TownShops = require(script.Parent.TownShops)
local TownMarket = require(script.Parent.TownMarket) -- (v9.7) 🛒 supermarché
local TownFair = require(script.Parent.TownFair) -- (v9.8, FAIR98) 🎡 fête foraine + 🍦 coin gourmand

local TownMap = {}

TownMap.FOLDER_NAME = "DopamineTown"

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

export type PlotInfo = {
	Index: number,
	Model: Model,
	CFrame: CFrame,
	HouseCFrame: CFrame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Stats: TextLabel,
	Board: BasePart,
}

export type Town = {
	Folder: Folder,
	Plots: { PlotInfo },
	Spawn: SpawnLocation,
	PlazaCFrame: CFrame,
	Seats: Folder,
}

-- État du dernier Build (écran + plan à tenir à jour)
local builtCount: number? = nil
local boards: {
	Plots: { PlotInfo },
	Screen: any,
	Map: any,
}? = nil
local refreshPending = false

----------------------------------------------------------------------
-- Parcelles
----------------------------------------------------------------------

local function signLabel(parent: Instance, name: string, text: string, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
	local l = TownKit.Label(parent, name, text, 0.05, y, 0.9, h, color, font, false)
	return l
end

local function buildPlot(parent: Instance, index: number, count: number): PlotInfo
	local plotCF = WorldLayout.PlotCFrame(index, count)
	local houseCF = WorldLayout.HouseCFrame(plotCF)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("OwnerId", 0)
	model.Parent = parent
	local W, D = WorldLayout.PLOT_W, WorldLayout.PLOT_D
	local g = WorldLayout.GROUND_Y
	-- pelouse (repère : -Z local = vers la rue / la place)
	local base = part(model, "Lawn", Vector3.new(W, 0.3, D), plotCF * CFrame.new(0, g - 0.1, 0), C.Lawn, M.Grass, "solid")
	base:SetAttribute("PlotIndex", index)
	-- bordure en pierre côté rue
	part(model, "Edging", Vector3.new(W, 0.25, 0.6), plotCF * CFrame.new(0, g + 0.1, -D / 2 + 0.3), C.Stone, M.Granite, "deco")
	-- clôtures blanches sur les côtés (planches + lisse + poteaux), haie au fond
	local fence = Color3.fromRGB(255, 252, 246)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 - 0.4)
		local len = D - 6
		local zc = 3
		part(model, "Fence", Vector3.new(0.25, 2.4, len), plotCF * CFrame.new(x, g + 1.4, zc), fence, M.WoodPlanks, "prop")
		part(model, "FenceRail", Vector3.new(0.4, 0.3, len), plotCF * CFrame.new(x, g + 2.75, zc), fence, M.Wood, "deco")
		local posts = 3
		for i = 0, posts do
			local z = zc - len / 2 + i * len / posts
			part(model, "FencePost", Vector3.new(0.6, 3.4, 0.6), plotCF * CFrame.new(x, g + 1.7, z), fence, M.Wood, "deco")
		end
	end
	-- (v9.7 NATURE97) haie taillée au dessus arrondi
	TownKit.Hedge(model, plotCF * CFrame.new(0, g, D / 2 - 1.35), W - 1.6, 2.6, 4.2, index)
	-- deux arbres aux coins avant (hors de la zone des décorations de jardin) :
	-- (v9.7 NATURE97) arbre fruitier / cerisier / bouleau selon la parcelle
	for _, sx in ipairs({ -1, 1 }) do
		local species = ({ "Fruit", "Cherry", "Birch", "Maple" })[(index + (sx > 0 and 1 or 0)) % 4 + 1]
		TownKit.Tree(model, (plotCF * CFrame.new(sx * (W / 2 - 5), g, -D / 2 + 5)).Position, 13 + (index % 3), index * 7 + sx, species, { Lawn = true })
	end
	-- boîte aux lettres (à gauche du chemin vu de la rue)
	local mailCF = plotCF * CFrame.new(-7, g, -D / 2 + 2.5)
	part(model, "MailPost", Vector3.new(0.45, 3.4, 0.45), mailCF * CFrame.new(0, 1.7, 0), C.Wood, M.Wood, "prop")
	part(model, "MailBox", Vector3.new(1.6, 1.2, 2.4), mailCF * CFrame.new(0, 3.9, 0), Color3.fromRGB(255, 140, 188), M.Metal, "deco")
	local lid = part(model, "MailTop", Vector3.new(2.4, 1.6, 1.6), mailCF * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 140, 188), M.Metal, "deco")
	;(lid :: Part).Shape = Enum.PartType.Cylinder
	part(model, "MailFlag", Vector3.new(0.12, 1, 0.5), mailCF * CFrame.new(0.85, 4.6, 0.5), Color3.fromRGB(236, 60, 90), M.SmoothPlastic, "deco")
	-- panneau du propriétaire (à droite du chemin, face à la rue)
	local signCF = plotCF * CFrame.new(10, g, -D / 2 + 2.5)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "SignPost", Vector3.new(0.5, 7.4, 0.5), signCF * CFrame.new(sx * 5.4, 3.7, 0.3), C.Wood, M.Wood, "prop")
	end
	part(model, "SignRoof", Vector3.new(12.4, 0.4, 1.6), signCF * CFrame.new(0, 7.6, 0.3), Color3.fromRGB(150, 116, 206), M.Slate, "deco")
	local board = part(model, "SignBoard", Vector3.new(11, 4.8, 0.4), signCF * CFrame.new(0, 4.8, 0), C.White, M.SmoothPlastic, "prop")
	part(model, "SignPlanter", Vector3.new(10, 0.9, 1.4), signCF * CFrame.new(0, 0.45, 0.2), C.Wood, M.WoodPlanks, "deco")
	part(model, "SignFlowers", Vector3.new(9.4, 0.8, 1), signCF * CFrame.new(0, 1.2, 0.2), TownKit.FLOWERS[index % #TownKit.FLOWERS + 1], M.Grass, "deco")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 36, C.White, 400, 0.2)
	TownKit.Gradient(body, Color3.fromRGB(255, 244, 250), Color3.fromRGB(255, 214, 236), 90)
	TownKit.Stroke(body, Color3.fromRGB(255, 170, 210), 4)
	local title = signLabel(body, "Title", "✨ Free plot", 0.06, 0.34, C.HotPink, Enum.Font.FredokaOne)
	local subtitle = signLabel(body, "Subtitle", "", 0.42, 0.22, C.Plum, Enum.Font.GothamBold)
	local stats = signLabel(body, "Stats", "", 0.68, 0.26, C.Ink, Enum.Font.GothamBold)
	model.PrimaryPart = base
	return {
		Index = index,
		Model = model,
		CFrame = plotCF,
		HouseCFrame = houseCF,
		Title = title,
		Subtitle = subtitle,
		Stats = stats,
		Board = board,
	}
end

----------------------------------------------------------------------
-- Grand écran + plan : suivent les panneaux des parcelles
----------------------------------------------------------------------

local MEDALS = { "🥇", "🥈", "🥉", "4.", "5." }

local function refreshBoards()
	refreshPending = false
	local current = boards
	if not current then
		return
	end
	local owned = {}
	for _, plot in ipairs(current.Plots) do
		local ownerId = plot.Model:GetAttribute("OwnerId")
		local name = plot.Model:GetAttribute("OwnerName")
		local owner = type(ownerId) == "number" and ownerId ~= 0 and type(name) == "string" and name ~= ""
		-- plan : pastille + légende
		local label = current.Map and current.Map.Labels[plot.Index]
		if label then
			label.Text = plot.Index .. ". " .. (owner and ("🏠 " .. name) or "✨ Free plot")
		end
		local marker = current.Map and current.Map.Markers[plot.Index]
		if marker then
			marker.BackgroundColor3 = owner and C.HotPink or Color3.fromRGB(150, 150, 170)
		end
		if owner then
			local likes = plot.Model:GetAttribute("Likes")
			table.insert(owned, { Name = name, Likes = type(likes) == "number" and likes or 0, Stats = plot.Stats.Text })
		end
	end
	table.sort(owned, function(a, b)
		if a.Likes ~= b.Likes then
			return a.Likes > b.Likes
		end
		return a.Name < b.Name
	end)
	local screen = current.Screen
	if screen then
		for i, row in ipairs(screen.Rows) do
			local entry = owned[i]
			if entry then
				row.Text = MEDALS[i] .. "  " .. entry.Name .. "     " .. entry.Stats
			elseif i == 1 then
				row.Text = "⏳ …"
			else
				row.Text = ""
			end
		end
	end
end

local function scheduleRefresh()
	if refreshPending then
		return
	end
	refreshPending = true
	-- (WorldService pose les attributs juste après SetPlotSign : on attend un peu)
	task.delay(0.1, function()
		local ok, err = pcall(refreshBoards)
		if not ok then
			refreshPending = false
			warn("[TownMap] écran / plan : " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

-- Point d'apparition à l'entrée (utilisable avant Build : nombre de parcelles par défaut)
function TownMap.SpawnCFrame(): CFrame
	return WorldLayout.EntranceCFrame(builtCount or WorldLayout.PlotCount(Players.MaxPlayers))
end

function TownMap.Build(plotCount: number): Town
	local old = workspace:FindFirstChild(TownMap.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	TownKit.Reset()
	builtCount = plotCount
	local geo = TownKit.Geo(plotCount)
	local folder = Instance.new("Folder")
	folder.Name = TownMap.FOLDER_NAME

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = folder
	local seats = Instance.new("Folder")
	seats.Name = "Seats"
	seats.Parent = folder
	-- (v9.6) boutiques où l'on entre (coques ; intérieurs : client ShopInteriors)
	local shops = Instance.new("Folder")
	shops.Name = "Shops"
	shops.Parent = folder

	-- (ordre = priorité des 16 vraies lumières : place, entrée, avenue)
	local plaza = TownPlaza.Build(decor, geo, shops)
	local entrance = TownEntrance.Build(decor, geo)
	-- 🚗 concession auto : hors de la porte, à gauche de la route d'arrivée (WorldLayout.DealershipCFrame) (avant la nature :
	-- sa place est réservée)
	TownShops.BuildDealership(shops, geo)
	-- (v9.7, BUILDINGS97) 🛒 supermarché MégaDopa + parking, hors de la porte
	-- (coque ; intérieur : client MarketInterior) ; dossier Market
	local market = Instance.new("Folder")
	market.Name = "Market"
	market.Parent = folder
	local okMarket, errMarket = pcall(TownMarket.Build, market, geo)
	if not okMarket then
		warn("[TownMap] supermarché : " .. tostring(errMarket))
	end
	-- (v9.8, FAIR98) 🎡 fête foraine derrière la mairie + 🍦 coin gourmand près
	-- de l'arrivée : AVANT les rues et la nature (leur place est réservée)
	local okFair, errFair = pcall(TownFair.Build, decor, geo)
	if not okFair then
		warn("[TownMap] fête foraine : " .. tostring(errFair))
	end
	local okCorner, errCorner = pcall(TownFair.BuildFoodCorner, decor, geo)
	if not okCorner then
		warn("[TownMap] coin gourmand : " .. tostring(errCorner))
	end
	TownStreets.Build(decor, geo)
	TownNature.Build(decor, geo)
	-- (v9.7) aucun arbre du bois planté sur le parking / dans le magasin
	pcall(TownMarket.ClearSite, decor, plotCount)
	pcall(TownShops.ClearDealerSite, decor, plotCount) -- (v9.8, CARS98) pas d'arbres sur la concession

	local plots: { PlotInfo } = {}
	for index = 1, plotCount do
		plots[index] = buildPlot(plotsFolder, index, plotCount)
	end

	local spawnCF = WorldLayout.EntranceCFrame(plotCount)
	-- (les clients recalculent les parcelles avec WorldLayout : même nombre)
	folder:SetAttribute("PlotCount", plotCount)
	folder:SetAttribute("EntranceCF", spawnCF)
	folder:SetAttribute("PlazaCF", WorldLayout.PlazaCFrame())
	folder:SetAttribute("GateCF", WorldLayout.GateCFrame(plotCount))
	folder:SetAttribute("TownRadius", WorldLayout.TownRadius(plotCount))
	folder:SetAttribute("Parts", TownKit.Stats.Parts)
	folder:SetAttribute("Lights", TownKit.Stats.Lights)
	folder:SetAttribute("Shops", #shops:GetChildren())
	folder.Parent = workspace

	boards = { Plots = plots, Screen = plaza.Screen, Map = entrance.Map }
	refreshBoards()
	return {
		Folder = folder,
		Plots = plots,
		Spawn = entrance.Spawn,
		PlazaCFrame = spawnCF,
		Seats = seats,
	}
end

-- Panneau d'une parcelle (textes déjà neutres : noms, chiffres, emoji)
function TownMap.SetPlotSign(plot: PlotInfo, title: string, subtitle: string, stats: string)
	plot.Title.Text = title
	plot.Subtitle.Text = subtitle
	plot.Stats.Text = stats
	scheduleRefresh()
end

return TownMap
