--[[
	TownHighway (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownHighway

	🛣️ Dopamine Town (v10, CITY10) : l'AUTOROUTE (2 x 2 voies) habillée côté
	CLIENT, en flux (TownStreetLife). Les tronçons sont calculés par
	CityPlan à partir du tracé de LAYOUT10 (WorldLayout.HighwayPath) ; ici
	on construit, pour chaque emplacement :
	  - "HwySeg"   : un tronçon (≤ 40 studs) : chaussée (si le tracé n'a pas
	    de dalle serveur), lignes de rive continues, lignes de voies en
	    tirets, bande d'arrêt d'urgence, terre-plein central avec séparateur
	    en béton (profil "New Jersey") et écran anti-éblouissement, glissières
	    de sécurité (lisse à double onde sur poteaux), balises de bord ;
	    EN HAUTEUR (pont, viaduc) : corniche, parapets en béton et pile
	    (semelle, fûts ronds, chevêtre) ;
	  - "HwyRamp"  : tronçon de bretelle (1 voie, sens unique) ;
	  - "HwyLamp"  : grand candélabre à double crosse sur le terre-plein ;
	  - "HwyGantry": portique de signalisation (treillis, panneaux bleus
	    avec les noms des quartiers et des flèches) ;
	  - "HwyWall"  : mur antibruit (poteaux en H, panneaux absorbants et
	    bandes vitrées) le long des quartiers d'habitation ;
	  - "HwyExit"  : divergent de sortie (zébras, atténuateur de choc
	    jaune et noir, panneau "SORTIE") ;
	  - "HwySign"  : panneau de bord (sortie à 500 m, nom du quartier,
	    limitation 110) ;
	  - "HwyRest"  : aire de repos (bâtiment sanitaires, tables de
	    pique-nique, arbres, places tracées, distributeur).
	Loin (au-delà du rayon "gros objets") : IMPOSTEURS de quelques pièces
	(bande de chaussée, parapets, piles) jusqu'à ~900 studs.
	Tout est ancré ; chaussée, séparateurs, glissières, parapets et piles
	sont SOLIDES (collision locale : la voiture du joueur roule et se cogne),
	le reste est décor. Aucune lumière réelle (verres "NightGlow"), aucun
	son. Pas de face confondue : peinture 0,12 au-dessus du bitume, tronçons
	voisins décalés de 0,03 en hauteur (joints en biais).

	Données d'un emplacement (spot.Data, voir CityPlan) :
	  { Lanes, Lane, Median, ShL, ShR, Deck, Elev, Ground, Par, Oneway,
	    Signs = { {Text, Arrow} }, Exit, Name }
	API (TownStreetLife) : TownHighway.BUILDERS, .BIG, .IMPOSTORS
	  TownHighway.Width(d) -> largeur totale d'un tronçon
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local CityKit = require(script.Parent.CityKit)

local TownHighway = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local ASPHALT = rgb(70, 72, 82)
local ASPHALT_OLD = rgb(84, 86, 96)
local PAINT = rgb(250, 250, 246)
local YELLOW = rgb(250, 204, 40)
local CONCRETE = rgb(196, 194, 188)
local CONCRETE_D = rgb(164, 162, 156)
local GALVA = rgb(178, 184, 190)
local GALVA_D = rgb(140, 146, 152)
local SIGN_BLUE = rgb(24, 70, 160)
local SIGN_GREEN = rgb(24, 120, 70)
local WHITE = rgb(250, 250, 248)
local GRAPHITE = rgb(52, 54, 60)
local GLARE = rgb(52, 110, 70)
local LAMP = rgb(255, 226, 170)

local H_PAINT = 0.12 -- dessus de la peinture au-dessus du bitume
local T_PAINT = 0.05

----------------------------------------------------------------------
-- Profil en travers
----------------------------------------------------------------------

type Prof = { Lanes: number, Lane: number, Median: number, ShL: number, ShR: number, Oneway: boolean }

local function prof(d: any): Prof
	d = d or {}
	return {
		Lanes = d.Lanes or 2,
		Lane = d.Lane or 11,
		Median = d.Oneway and 0 or (d.Median or 5),
		ShL = d.ShL or 1.5,
		ShR = d.ShR or 5,
		Oneway = d.Oneway == true,
	}
end

-- Largeur d'une chaussée (un sens) et largeur totale
local function sideW(p: Prof): number
	return p.ShL + p.Lanes * p.Lane + p.ShR
end

function TownHighway.Width(d: any): number
	local p = prof(d)
	if p.Oneway then
		return sideW(p)
	end
	return p.Median + 2 * sideW(p)
end

-- Bandes de chaque sens : { x0 (bord gauche = côté terre-plein), dir (+1 à droite) }
local function carriageways(p: Prof): { { number } }
	if p.Oneway then
		return { { -sideW(p) / 2, 1 } }
	end
	return { { p.Median / 2, 1 }, { -p.Median / 2, -1 } }
end

----------------------------------------------------------------------
-- Tronçon
----------------------------------------------------------------------

-- ligne peinte le long de z (repère F : dessus du bitume à y = top)
local function line(m: Model, F: CFrame, x: number, z0: number, z1: number, w: number, top: number, color: Color3?)
	Box(m, "Paint", F, x - w / 2, x + w / 2, top + H_PAINT - T_PAINT, top + H_PAINT, z0, z1, color or PAINT, M.SmoothPlastic)
end

-- tirets le long de z, en phase avec la distance le long du tracé (s0)
local function dashes(m: Model, F: CFrame, x: number, L: number, s0: number, top: number)
	local DASH, GAP = 9, 15
	local period = DASH + GAP
	local s = s0 - (s0 % period) -- début d'une période
	while s < s0 + L do
		local a, b = math.max(s, s0), math.min(s + DASH, s0 + L)
		if b - a > 0.4 then
			-- z local : le tronçon va de +L/2 (début) à -L/2 (fin)
			line(m, F, x, L / 2 - (b - s0), L / 2 - (a - s0), 0.5, top)
		end
		s += period
	end
end

-- glissière de sécurité (lisse à double onde sur poteaux) côté `side`
local function guardrail(m: Model, F: CFrame, x: number, L: number, side: number, top: number, s0: number, extra: number?)
	local post = 6
	local first = post - (s0 % post)
	local s = first
	while s < L - 0.3 do
		local z = L / 2 - s
		Box(m, "RailPost", F, x - 0.18, x + 0.18, top, top + 2.3, z - 0.18, z + 0.18, GALVA_D, M.Metal, true)
		Box(m, "RailSpacer", F, x + side * 0.18, x + side * 0.02 + side * 0.3, top + 1.6, top + 2.2, z - 0.15, z + 0.15, GALVA_D, M.Metal)
		s += post
	end
	-- lisse : deux ondes (bandes) + creux
	local xr = x - side * 0.5
	local R = L / 2 + (extra or 0)
	Box(m, "RailWave", F, xr - 0.12, xr + 0.12, top + 1.95, top + 2.35, -R, R, GALVA, M.DiamondPlate, true)
	Box(m, "RailWave", F, xr - 0.12, xr + 0.12, top + 1.45, top + 1.85, -R, R, GALVA, M.DiamondPlate, true)
	Box(m, "RailTrough", F, xr + side * 0.05 - 0.04, xr + side * 0.05 + 0.04, top + 1.8, top + 2.0, -R, R, GALVA_D, M.Metal)
end

-- séparateur en béton "New Jersey" au milieu (x = 0) + écran anti-éblouissement
local function jersey(m: Model, F: CFrame, L: number, top: number, glare: boolean)
	Box(m, "JerseyFoot", F, -1.3, 1.3, top - 0.3, top + 0.9, -L / 2, L / 2, CONCRETE, M.Concrete, true)
	-- (coin : face verticale du coin côté intérieur, pente vers l'extérieur)
	Wedge(m, "JerseySlope", Vector3.new(L, 1.1, 0.8), F * CFrame.new(-0.9, top + 1.45, 0) * CFrame.Angles(0, math.pi / 2, 0), CONCRETE, M.Concrete, true)
	Wedge(m, "JerseySlope", Vector3.new(L, 1.1, 0.8), F * CFrame.new(0.9, top + 1.45, 0) * CFrame.Angles(0, -math.pi / 2, 0), CONCRETE, M.Concrete, true)
	Box(m, "JerseyTop", F, -0.5, 0.5, top + 0.9, top + 2.8, -L / 2, L / 2, CONCRETE, M.Concrete, true)
	if glare then
		-- lamelles vertes (anti-éblouissement), une tous les 1,2 studs
		Box(m, "GlareRail", F, -0.12, 0.12, top + 4.0, top + 4.14, -L / 2, L / 2, GALVA_D, M.Metal)
		local n = math.floor(L / 1.2)
		for i = 0, n - 1 do
			local z = -L / 2 + (i + 0.5) * L / n
			Box(m, "GlareBlade", F, -0.05, 0.05, top + 2.8, top + 4.0, z - 0.3, z + 0.3, GLARE, M.SmoothPlastic)
		end
	end
end

-- balises de bord (poteaux blancs à bande noire et catadioptre)
local function delineators(m: Model, F: CFrame, x: number, L: number, top: number, s0: number, side: number)
	local every = 20
	local s = every - (s0 % every)
	while s < L - 0.3 do
		local z = L / 2 - s
		Box(m, "Delineator", F, x - 0.25, x + 0.25, top, top + 3.4, z - 0.15, z + 0.15, WHITE, M.SmoothPlastic)
		Box(m, "DelineatorBand", F, x - 0.3, x + 0.3, top + 2.4, top + 2.9, z - 0.2, z + 0.2, GRAPHITE, M.SmoothPlastic)
		Glow(Box(m, "Reflector", F, x - 0.1, x + 0.1, top + 2.5, top + 2.8, z + side * 0.2, z + side * 0.24, rgb(255, 140, 40), M.SmoothPlastic))
		s += every
	end
end

-- pile de pont (semelle, 2 fûts ronds, chevêtre) sous la dalle à z
local function pier(m: Model, F: CFrame, z: number, half: number, deckBottom: number, groundDy: number)
	local cap = 2.2
	local capTop = deckBottom
	Box(m, "PierCap", F, -half * 0.9, half * 0.9, capTop - cap, capTop, z - 2, z + 2, CONCRETE_D, M.Concrete, true)
	local foot = groundDy
	for _, x in ipairs({ -half * 0.45, half * 0.45 }) do
		Column(m, "PierShaft", F, x, z, foot, capTop - cap, 3.4, CONCRETE, M.Concrete, true)
		Box(m, "PierFooting", F, x - 2.6, x + 2.6, foot - 0.2, foot + 0.5, z - 2.6, z + 2.6, CONCRETE_D, M.Concrete, true)
	end
end

local function buildSeg(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	local p = prof(d)
	local L = spot and spot.Size and spot.Size.Z or 40
	local top = ((d.Par == 1) and 0.03 or 0) + (d.PaintY or 0) -- tronçons voisins décalés (joints en biais)
	local s0 = d.S or 0 -- abscisse du début du tronçon le long du tracé
	local W = TownHighway.Width(d)
	local elev = (d.Elev or 0) > 3
	local extra = d.Overlap or 0 -- allongement aux joints en biais
	local Lx = L + 2 * extra
	-- chaussée (si pas de dalle serveur)
	if d.Deck ~= false then
		local tint = hash(seed, 1) < 0.25 and ASPHALT_OLD or ASPHALT
		Box(m, "HwyAsphalt", F, -W / 2, W / 2, top - (elev and 2.2 or 0.6), top, -Lx / 2, Lx / 2, tint, M.Asphalt, true)
	end
	for _, cw in ipairs(carriageways(p)) do
		local x0, dir = cw[1], cw[2]
		local inner = x0 + dir * p.ShL -- bord intérieur de la voie de gauche
		local outer = inner + dir * p.Lanes * p.Lane
		line(m, F, inner + dir * 0.35, -Lx / 2, Lx / 2, 0.5, top)
		line(m, F, outer - dir * 0.35, -Lx / 2, Lx / 2, 0.7, top)
		for k = 1, p.Lanes - 1 do
			dashes(m, F, inner + dir * k * p.Lane, L, s0, top)
		end
		local edge = outer + dir * p.ShR -- bord extérieur de la bande d'arrêt
		if elev then
			-- parapet en béton + corniche
			Box(m, "Parapet", F, edge - dir * 1.2 - 0.001, edge, top, top + 3.2, -Lx / 2, Lx / 2, CONCRETE, M.Concrete, true)
			Box(m, "ParapetCap", F, edge - dir * 1.35, edge + dir * 0.15, top + 3.2, top + 3.5, -Lx / 2, Lx / 2, CONCRETE_D, M.Concrete)
			Box(m, "Cornice", F, edge, edge + dir * 0.6, top - 2.2, top + 0.4, -Lx / 2, Lx / 2, CONCRETE_D, M.Concrete)
		elseif not d.NoRail then
			-- (v11, CARS11) bretelles : lisse NON allongée aux joints en biais (dans
			-- un virage serré, le bout allongé côté intérieur traversait la voie)
			-- (et posée sur l'accotement, 0,6 au-delà du bord : les tronçons droits
			-- d'une bretelle qui tourne ne pincent plus la voie)
			guardrail(m, F, if p.Oneway then edge + dir * 0.6 else edge - dir * 1.0, L, dir, top, s0, if p.Oneway then 0 else extra)
			delineators(m, F, edge - dir * 0.2, L, top, s0, dir)
		end
	end
	if not p.Oneway then
		-- terre-plein : séparateur + écran (en hauteur : pas d'écran)
		jersey(m, F, Lx, top, not elev and hash(seed, 5) < 0.7)
	end
	-- pile au milieu du tronçon (en hauteur seulement)
	if elev and d.Pier ~= false then
		local groundDy = (d.Ground or (F.Position.Y - (d.Elev or 0))) - F.Position.Y
		pier(m, F, 0, W / 2, top - 2.2, groundDy)
	end
end

-- (v11, CARS11) "BARRAGE" à l'entrée de l'autoroute : le 1er tronçon d'une
-- bretelle part du CENTRE du carrefour de la route locale ; sa glissière
-- (26 studs, solide) traversait la route d'accès et la bouche de la bretelle.
-- Plus de glissière à moins de 40 studs d'un carrefour de la ville.
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local function nearCityJunction(F: CFrame, L: number): boolean
	local town = workspace:FindFirstChild("DopamineTown")
	local count = town and town:GetAttribute("PlotCount")
	if type(count) ~= "number" then
		count = 8
	end
	local O = WorldLayout.Origin()
	for _, z in ipairs({ -L / 2, 0, L / 2 }) do
		local p = (F * CFrame.new(0, 0, z)).Position - O
		local ok, node = pcall(WorldLayout.NearestNode, count, p.X, p.Z, function(n: any): boolean
			return n.Kind == "Junction" or n.Kind == "Roundabout"
		end)
		if ok and node and (node.X - p.X) ^ 2 + (node.Z - p.Z) ^ 2 < 40 * 40 then
			return true
		end
	end
	return false
end

-- bretelle : même profil, 1 voie, sens unique
local function buildRamp(m: Model, F: CFrame, seed: number, spot: any)
	local d = table.clone(spot and spot.Data or {})
	if not d.NoRail and nearCityJunction(F, spot and spot.Size and spot.Size.Z or 26) then
		d.NoRail = true
	end
	d.Oneway = true
	d.Lanes = d.Lanes or 1
	d.ShL = d.ShL or 1.5
	d.ShR = d.ShR or 3
	buildSeg(m, F, seed, { Size = spot and spot.Size, Data = d })
end

----------------------------------------------------------------------
-- Équipements
----------------------------------------------------------------------

-- grand candélabre à double crosse (terre-plein) : F au pied, sur le séparateur
local function buildLamp(m: Model, F: CFrame, _seed: number, spot: any)
	local d = spot and spot.Data or {}
	local H = 22
	local reach = d.Reach or 9
	local base = 2.8 -- sur le séparateur
	Column(m, "HwyLampPole", F, 0, 0, base, H, 0.7, GALVA, M.Metal, true)
	Column(m, "HwyLampCollar", F, 0, 0, base, base + 1.2, 0.95, GALVA_D, M.Metal)
	local sides = d.Single and { 1 } or { -1, 1 }
	for _, sx in ipairs(sides) do
		local a = (F * CFrame.new(0, H - 0.3, 0)).Position
		local b = (F * CFrame.new(sx * reach, H + 0.9, 0)).Position
		CityKit.Rod(m, "HwyLampArm", a, b, 0.32, GALVA, M.Metal)
		local head = F * CFrame.new(sx * (reach + 0.9), H + 0.9, 0)
		Box(m, "HwyLampHead", head, -1.3, 1.3, -0.25, 0.3, -0.7, 0.7, GALVA_D, M.Metal)
		Glow(Box(m, "HwyLampGlass", head, -1.1, 1.1, -0.4, -0.25, -0.55, 0.55, LAMP, M.Glass))
	end
end

-- flèche en texte selon la direction du panneau
local ARROWS = { Up = "↑", Right = "↗", Left = "↖", Down = "↓", Exit = "↘" }

-- portique : F au milieu de la chaussée, au niveau du bitume ; spot.Data.W = portée
local function buildGantry(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	local W = d.W or 60
	local H = 17 -- sous-face des panneaux ~ 17 studs (≈ 5,5 m)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 + 1.5)
		Box(m, "GantryFooting", F, x - 1.6, x + 1.6, -0.3, 1.2, -1.6, 1.6, CONCRETE_D, M.Concrete, true)
		for _, dz in ipairs({ -0.8, 0.8 }) do
			Column(m, "GantryLeg", F, x, dz, 1.2, H + 3.6, 0.5, GALVA, M.Metal, true)
		end
		for k = 0, 4 do
			local y = 2 + k * 3.6
			CityKit.Rod(m, "GantryBrace", (F * CFrame.new(x, y, -0.8)).Position, (F * CFrame.new(x, y + 3.6, 0.8)).Position, 0.14, GALVA_D, M.Metal)
		end
	end
	-- poutre en treillis : 4 membrures + diagonales
	local span = W + 3
	for _, yy in ipairs({ H + 0.2, H + 3.4 }) do
		for _, zz in ipairs({ -0.8, 0.8 }) do
			Box(m, "GantryChord", F, -span / 2, span / 2, yy - 0.18, yy + 0.18, zz - 0.18, zz + 0.18, GALVA, M.Metal)
		end
	end
	local n = math.floor(span / 3.2)
	for i = 0, n - 1 do
		local x0 = -span / 2 + i * span / n
		local x1 = x0 + span / n
		local up = i % 2 == 0
		CityKit.Rod(m, "GantryDiag", (F * CFrame.new(x0, up and H + 0.2 or H + 3.4, -0.8)).Position, (F * CFrame.new(x1, up and H + 3.4 or H + 0.2, -0.8)).Position, 0.12, GALVA_D, M.Metal)
	end
	-- panneaux (face vers les conducteurs qui arrivent : +Z local)
	local signs = d.Signs or { { Text = Locale.T("City centre"), Arrow = "Up" } }
	local count = math.min(#signs, 3)
	-- zone des panneaux : au-dessus de la chaussée du sens concerné
	local x0, x1 = -W / 2 + 2, W / 2 - 2
	if d.Side == "Right" then
		x0, x1 = 1.5, W / 2 - 1
	elseif d.Side == "Left" then
		x0, x1 = -W / 2 + 1, -1.5
	end
	local slot = (x1 - x0) / math.max(1, count)
	for i = 1, count do
		local s = signs[i]
		local cx = x1 - (i - 0.5) * slot -- de droite à gauche
		local sw = math.min(slot - 1.2, 24)
		local color = s.Green and SIGN_GREEN or SIGN_BLUE
		local panel = Box(m, "GantrySign", F, cx - sw / 2, cx + sw / 2, H - 0.2, H + 5.2, 0.95, 1.25, color, M.SmoothPlastic)
		Box(m, "GantrySignRim", F, cx - sw / 2 - 0.15, cx + sw / 2 + 0.15, H - 0.35, H + 5.35, 0.85, 0.95, WHITE, M.SmoothPlastic)
		Text(panel, Enum.NormalId.Back, (ARROWS[s.Arrow or "Up"] or "↑") .. "  " .. tostring(s.Text), WHITE, nil, Enum.Font.GothamBold, 420, 14)
		Glow(Box(m, "GantrySignLamp", F, cx - sw / 2 + 0.5, cx + sw / 2 - 0.5, H + 5.35, H + 5.6, 1.6, 2.1, rgb(220, 226, 236), M.Metal))
	end
	local _ = seed
end

-- mur antibruit le long de x (repère F : pied du mur, face route vers +Z)
local function buildWall(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 40
	local H = 11
	local post = 8
	local n = math.max(1, math.floor(L / post + 0.5))
	local step = L / n
	local palette = { rgb(92, 128, 108), rgb(124, 110, 92), rgb(96, 112, 134) }
	local panel = palette[1 + math.floor(hash(seed, 2) * #palette) % #palette]
	Box(m, "WallPlinth", F, -L / 2, L / 2, -0.4, 1.6, -0.6, 0.6, CONCRETE, M.Concrete, true)
	for i = 0, n do
		local x = -L / 2 + i * step
		Box(m, "WallPostH", F, x - 0.35, x + 0.35, 1.6, H + 0.5, -0.45, 0.45, GALVA_D, M.Metal, true)
		if i < n then
			local xa, xb = x + 0.35, x + step - 0.35
			Box(m, "WallPanel", F, xa, xb, 1.6, H - 3.2, -0.3, 0.3, panel, M.Fabric, true)
			-- rainures horizontales des cassettes absorbantes
			for k = 1, 3 do
				local y = 1.6 + k * (H - 4.8) / 4
				Box(m, "WallGroove", F, xa, xb, y - 0.08, y + 0.08, 0.3, 0.36, panel:Lerp(Color3.new(0, 0, 0), 0.25), M.SmoothPlastic)
			end
			-- bande vitrée en haut (lumière, silhouettes d'oiseaux)
			local glass = Part(m, "WallGlass", Vector3.new(xb - xa, 3.2, 0.2), F * CFrame.new((xa + xb) / 2, H - 1.6, 0), rgb(190, 214, 226), M.Glass, nil, true)
			glass.Transparency = 0.45
			if hash(seed, i) < 0.3 then
				Box(m, "BirdSticker", F, (xa + xb) / 2 - 0.4, (xa + xb) / 2 + 0.4, H - 1.4, H - 0.9, 0.1, 0.14, GRAPHITE, M.SmoothPlastic)
			end
		end
	end
	Box(m, "WallCap", F, -L / 2, L / 2, H, H + 0.3, -0.4, 0.4, GALVA_D, M.Metal)
end

-- divergent de sortie : F au nez du divergent (entre autoroute et bretelle),
-- -Z = sens de circulation
local function buildExit(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	-- zébras (chevrons peints) sur le musoir
	for i = 0, 5 do
		local z = 4 + i * 4
		local w = math.max(0.8, 5 - i * 0.7)
		-- (au-dessus des lignes des tronçons et des bretelles : 0,24 / 0,27)
		Part(m, "GoreChevron", Vector3.new(w, T_PAINT, 0.7), F * CFrame.new(-w * 0.38, 0.24 - T_PAINT / 2, z + w * 0.32) * CFrame.Angles(0, math.rad(40), 0), PAINT, M.SmoothPlastic)
		Part(m, "GoreChevron", Vector3.new(w, T_PAINT, 0.7), F * CFrame.new(w * 0.38, 0.27 - T_PAINT / 2, z + w * 0.32) * CFrame.Angles(0, math.rad(-40), 0), PAINT, M.SmoothPlastic)
	end
	-- atténuateur de choc (bandes jaunes et noires)
	local A = F * CFrame.new(0, 0, -1)
	Box(m, "CushionBase", A, -1.2, 1.2, 0, 0.3, -4, 1.5, GRAPHITE, M.Metal, true)
	for k = 0, 3 do
		local z = -3.5 + k * 1.3
		Box(m, "Cushion", A, -1.05, 1.05, 0.3, 2.8, z, z + 1.1, k % 2 == 0 and YELLOW or GRAPHITE, M.SmoothPlastic, true)
	end
	Box(m, "CushionNose", A, -1.1, 1.1, 0.3, 2.9, 1.4, 1.62, YELLOW, M.SmoothPlastic)
	for i = 0, 2 do
		Box(m, "CushionStripe", A, -0.9 + i * 0.7, -0.6 + i * 0.7, 0.6, 2.6, 1.62, 1.66, GRAPHITE, M.SmoothPlastic)
	end
	-- panneau "SORTIE" sur le musoir, face aux conducteurs (+Z)
	local P = F * CFrame.new(0, 0, -6)
	Column(m, "ExitPost", P, -1.4, 0, 0, 7, 0.3, GALVA, M.Metal, true)
	Column(m, "ExitPost", P, 1.4, 0, 0, 7, 0.3, GALVA, M.Metal, true)
	local sign = Box(m, "ExitSign", P, -2.4, 2.4, 5, 7.6, 0.2, 0.4, SIGN_BLUE, M.SmoothPlastic)
	Text(sign, Enum.NormalId.Back, "↗ " .. Locale.T("EXIT") .. (d.Number and (" " .. tostring(d.Number)) or ""), WHITE, nil, Enum.Font.GothamBlack, 300, 20)
	local _ = seed
end

-- panneau de bord : F au pied, face aux conducteurs (+Z) ; Data.Text / Kind
local function buildSign(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	local kind = d.Kind or "Exit"
	if kind == "Speed" then
		Column(m, "SpeedPost", F, 0, 0, 0, 7.2, 0.3, GALVA, M.Metal, true)
		-- disque rouge (cylindre couché selon Z) + fond blanc devant
		Part(m, "SpeedDisc", Vector3.new(0.2, 3.4, 3.4), F * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(220, 30, 40), M.SmoothPlastic, "Cyl")
		Part(m, "SpeedFace", Vector3.new(0.2, 2.7, 2.7), F * CFrame.new(0, 7.6, 0.08) * CFrame.Angles(0, math.pi / 2, 0), WHITE, M.SmoothPlastic, "Cyl")
		local plate = Box(m, "SpeedText", F, -1, 1, 6.9, 8.3, 0.22, 0.24, WHITE, M.SmoothPlastic)
		plate.Transparency = 1
		Text(plate, Enum.NormalId.Back, tostring(d.Limit or 110), rgb(20, 20, 24), nil, Enum.Font.GothamBlack, 160, 40)
		return
	end
	local w = d.W or 12
	local color = kind == "Name" and rgb(250, 250, 250) or SIGN_BLUE
	local ink = kind == "Name" and rgb(20, 20, 24) or WHITE
	for _, x in ipairs({ -w / 2 + 1, w / 2 - 1 }) do
		Column(m, "SignPost", F, x, 0, 0, 9.6, 0.36, GALVA, M.Metal, true)
	end
	local panel = Box(m, "RoadSign", F, -w / 2, w / 2, 6.2, 9.8, -0.1, 0.1, color, M.SmoothPlastic)
	Box(m, "RoadSignRim", F, -w / 2 - 0.12, w / 2 + 0.12, 6.08, 9.92, -0.16, -0.1, kind == "Name" and rgb(200, 30, 40) or WHITE, M.SmoothPlastic)
	Text(panel, Enum.NormalId.Back, tostring(d.Text or ""), ink, nil, Enum.Font.GothamBold, 260, 16)
	local _ = seed
end

-- aire de repos : F au centre, -Z vers l'autoroute ; ~46 x 30
local function buildRest(m: Model, F: CFrame, seed: number, _spot: any)
	local W, D = 46, 30
	-- place de parking en bitume + places tracées
	Box(m, "RestLot", F, -W / 2, W / 2, 0.05, 0.25, -D / 2, 0, ASPHALT, M.Asphalt, true)
	for i = 0, 7 do
		local x = -W / 2 + 4 + i * 5.2
		Box(m, "RestBay", F, x - 0.2, x + 0.2, 0.25 + 0.07, 0.25 + 0.12, -9, -2, PAINT, M.SmoothPlastic)
	end
	-- bâtiment des sanitaires (toit monopente, bardage bois)
	local B = F * CFrame.new(-W / 2 + 10, 0.25, D / 2 - 7)
	Box(m, "RestHut", B, -7, 7, 0, 9, -4.5, 4.5, rgb(186, 150, 110), M.WoodPlanks, true)
	Wedge(m, "RestRoof", Vector3.new(16, 1.6, 11), B * CFrame.new(0, 9.8, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(70, 74, 84), M.Metal)
	for i, lbl in ipairs({ "WC", "♿", "🚿" }) do
		local x = -4.5 + (i - 1) * 4.5
		Box(m, "RestDoor", B, x - 1.2, x + 1.2, 0, 7.2, -4.62, -4.5, rgb(40, 90, 140), M.SmoothPlastic)
		local plate = Box(m, "RestPlate", B, x - 0.6, x + 0.6, 7.5, 8.5, -4.68, -4.62, WHITE, M.SmoothPlastic)
		Text(plate, Enum.NormalId.Front, lbl, rgb(40, 90, 140), nil, Enum.Font.GothamBlack, 80, 40)
	end
	-- distributeur, poubelles de tri, tables de pique-nique
	local V = F * CFrame.new(0, 0.25, D / 2 - 4)
	Box(m, "Vending", V, -1.6, 1.6, 0, 6.2, -1.1, 1.1, rgb(200, 40, 60), M.SmoothPlastic, true)
	Glow(Box(m, "VendingGlass", V, -1.2, 0.5, 1.6, 5.6, -1.16, -1.1, rgb(220, 236, 246), M.Glass))
	for i = 0, 2 do
		local T = F * CFrame.new(6 + i * 7, 0.25, 8 + (i % 2) * 3) * CFrame.Angles(0, hash(seed, i) * 0.6 - 0.3, 0)
		local wood = rgb(160, 112, 70)
		Box(m, "PicnicTop", T, -3, 3, 2.2, 2.5, -1.2, 1.2, wood, M.WoodPlanks, true)
		for _, z in ipairs({ -2.1, 2.1 }) do
			Box(m, "PicnicSeat", T, -3, 3, 1.3, 1.55, z - 0.5, z + 0.5, wood, M.WoodPlanks, true)
		end
		for _, x in ipairs({ -2.3, 2.3 }) do
			Box(m, "PicnicLeg", T, x - 0.18, x + 0.18, 0, 2.2, -2.4, 2.4, wood:Lerp(Color3.new(0, 0, 0), 0.2), M.Wood)
		end
	end
	for i = 0, 2 do
		CityKit.Bin(m, F * CFrame.new(-4 + i * 1.8, 0.25, 4), ({ rgb(240, 200, 40), rgb(40, 120, 70), rgb(40, 90, 160) })[i + 1])
	end
	-- arbres
	local okG, Greenery = pcall(require, ReplicatedStorage.Shared.Greenery)
	if okG then
		for i = 0, 3 do
			local p = (F * CFrame.new(-W / 2 + 4 + i * 13, 0.25, D / 2 + 3)).Position
			pcall(Greenery.Tree, m, p, 14 + hash(seed, i) * 5, seed + i * 17, i % 2 == 0 and "Oak" or "Poplar", 1)
		end
	end
	-- panneau "Aire de ..."
	local S = F * CFrame.new(W / 2 - 4, 0.25, -2)
	Column(m, "RestSignPost", S, 0, 0, 0, 8, 0.4, GALVA, M.Metal, true)
	local sign = Box(m, "RestSign", S, -3, 3, 6, 9.4, -0.12, 0.12, SIGN_BLUE, M.SmoothPlastic)
	Text(sign, Enum.NormalId.Front, "🅿️ " .. Locale.T("Rest area"), WHITE, nil, Enum.Font.GothamBold, 220, 20)
end

----------------------------------------------------------------------
-- 🌉 Ponts (habillage du tablier du serveur) et marquages des rues
----------------------------------------------------------------------

-- tronçon de tablier (F au dessus du tablier, au milieu ; -Z le long) :
-- le serveur pose la dalle (1,2 d'épaisseur, 26 de large), les parapets
-- (0,8 x 2,6) et les appuis ; ici : corniche en béton clair sous le bord,
-- garde-corps anti-jets (poteaux + grillage) sur les parapets, gouttes
-- d'eau, candélabres, et piles sous les rampes d'approche
local function buildBridge(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	local L = spot and spot.Size and spot.Size.Z or 20
	local half = (spot and spot.Size and spot.Size.X or 26) / 2
	local off = (d.Par == 1) and 0.02 or 0
	for _, sx in ipairs({ -1, 1 }) do
		-- corniche : bande claire à l'extérieur du tablier, plus bas que le dessus
		Box(m, "Fascia", F, sx * (half + 0.04), sx * (half + 0.64), -1.9 - off, 0.5 + off, -L / 2, L / 2, rgb(214, 210, 200), M.Concrete)
		Box(m, "FasciaDrip", F, sx * (half + 0.64), sx * (half + 0.8), -2.1 - off, -1.5 - off, -L / 2, L / 2, CONCRETE_D, M.Concrete)
		-- garde-corps anti-jets au-dessus du parapet (2,6)
		if (d.Elev or 0) > 3 then
			local n = math.max(1, math.floor(L / 4))
			for i = 0, n do
				local z = -L / 2 + i * L / n
				Box(m, "ScreenPost", F, sx * (half - 0.5) - 0.1, sx * (half - 0.5) + 0.1, 2.6, 6.2, z - 0.1, z + 0.1, GALVA_D, M.Metal)
			end
			local mesh = Box(m, "ScreenMesh", F, sx * (half - 0.5) - 0.03, sx * (half - 0.5) + 0.03, 2.7, 6.1, -L / 2, L / 2, GALVA, M.DiamondPlate, true)
			mesh.Transparency = 0.6
			Box(m, "ScreenTop", F, sx * (half - 0.5) - 0.08, sx * (half - 0.5) + 0.08, 6.1, 6.3, -L / 2, L / 2, GALVA_D, M.Metal)
		end
		if d.Lamp then
			local P = F * CFrame.new(sx * (half - 1.6), 0, 0) * CFrame.Angles(0, sx > 0 and math.pi / 2 or -math.pi / 2, 0)
			CityKit.StreetLamp(m, P, 12, GALVA_D)
		end
	end
	-- pile sous une rampe d'approche (le sol est d.Ground, monde)
	if d.Pier then
		local groundDy = (d.Ground or (F.Position.Y - (d.Elev or 0))) - F.Position.Y
		local capTop = -1.25
		Box(m, "PierCap", F, -half + 2, half - 2, capTop - 1.6, capTop, -1.4, 1.4, CONCRETE_D, M.Concrete, true)
		for _, x in ipairs({ -half * 0.5, half * 0.5 }) do
			if capTop - 1.6 - groundDy > 0.5 then
				Column(m, "PierShaft", F, x, 0, groundDy, capTop - 1.6, 2.4, CONCRETE, M.Concrete, true)
				Box(m, "PierFooting", F, x - 2, x + 2, groundDy - 0.3, groundDy + 0.4, -2, 2, CONCRETE_D, M.Concrete, true)
			end
		end
	end
	local _ = seed
end

-- marquages d'un tronçon de rue (F au milieu, sur la chaussée ; -Z = sens
-- +s de l'arête) : ligne médiane en tirets (double sens), lignes de rive,
-- lignes d'arrêt avant les carrefours ; rien dans les carrefours
local function buildRoadMarks(m: Model, F: CFrame, _seed: number, spot: any)
	local d = spot and spot.Data or {}
	local L = spot and spot.Size and spot.Size.Z or 40
	local W = d.Width or 20
	local S = d.S or 0 -- abscisse du début du tronçon
	local a, b = d.ClearA or 0, (d.Len or L) - (d.ClearB or 0)
	local s0, s1 = math.max(S, a), math.min(S + L, b)
	local top = d.Top or 0
	local function z(s: number): number
		return L / 2 - (s - S)
	end
	if s1 - s0 > 0.5 then
		-- lignes de rive (continues)
		for _, sx in ipairs({ -1, 1 }) do
			line(m, F, sx * (W / 2 - 0.9), z(s1), z(s0), 0.45, top)
		end
		if not d.OneWay then
			local dash, gap = d.Dash or 6, d.Gap or 8
			local period = dash + gap
			local s = s0 - ((s0 - a) % period)
			while s < s1 do
				local p0, p1 = math.max(s, s0), math.min(s + dash, s1)
				if p1 - p0 > 0.3 then
					line(m, F, 0, z(p1), z(p0), 0.45, top)
				end
				s += period
			end
		end
	end
	-- lignes d'arrêt (sens +s : moitié droite, +X ; sens -s : moitié gauche)
	-- (de x = 0,45 à W/2 - 1,25 : ne touche ni la médiane ni la rive)
	local sw = W / 2 - 1.7
	local sc = 0.45 + sw / 2
	if d.StopB and b >= S and b <= S + L then
		line(m, F, sc, z(b) + 0.5, z(b) + 1.3, sw, top)
	end
	if d.StopA and not d.OneWay and a >= S and a <= S + L then
		line(m, F, -sc, z(a) - 1.3, z(a) - 0.5, sw, top)
	end
end

----------------------------------------------------------------------
-- Imposteurs (loin) : quelques pièces
----------------------------------------------------------------------

local function impSeg(m: Model, F: CFrame, _seed: number, spot: any)
	local d = spot and spot.Data or {}
	local L = spot and spot.Size and spot.Size.Z or 40
	local W = TownHighway.Width(d)
	local top = (d.Par == 1) and 0.03 or 0
	local elev = (d.Elev or 0) > 3
	local extra = d.Overlap or 0
	if d.Deck ~= false then
		Box(m, "ImpAsphalt", F, -W / 2, W / 2, top - (elev and 2.2 or 0.6), top, -L / 2 - extra, L / 2 + extra, ASPHALT, M.Asphalt, true)
	end
	if not d.Oneway then
		Box(m, "ImpJersey", F, -0.9, 0.9, top, top + 2.8, -L / 2 - extra, L / 2 + extra, CONCRETE, M.Concrete, true)
	end
	if elev then
		for _, sx in ipairs({ -1, 1 }) do
			Box(m, "ImpParapet", F, sx * W / 2 - 1.2, sx * W / 2, top, top + 3.2, -L / 2, L / 2, CONCRETE, M.Concrete, true)
		end
		if d.Pier ~= false then
			local groundDy = (d.Ground or (F.Position.Y - (d.Elev or 0))) - F.Position.Y
			Box(m, "ImpPier", F, -W * 0.3, W * 0.3, groundDy, top - 2.2, -1.7, 1.7, CONCRETE_D, M.Concrete, true)
		end
	end
end

local function impWall(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 40
	local palette = { rgb(92, 128, 108), rgb(124, 110, 92), rgb(96, 112, 134) }
	Box(m, "ImpWall", F, -L / 2, L / 2, -0.4, 11.3, -0.4, 0.4, palette[1 + math.floor(hash(seed, 2) * #palette) % #palette], M.Fabric, true)
end

TownHighway.BUILDERS = {
	HwySeg = buildSeg,
	HwyRamp = buildRamp,
	HwyLamp = buildLamp,
	HwyGantry = buildGantry,
	HwyWall = buildWall,
	HwyExit = buildExit,
	HwySign = buildSign,
	HwyRest = buildRest,
	BridgeSeg = buildBridge,
	RoadMarks = buildRoadMarks,
}
TownHighway.BIG = { HwySeg = true, HwyRamp = true, HwyGantry = true, HwyWall = true, HwyLamp = true, HwyRest = true, BridgeSeg = true }
TownHighway.IMPOSTORS = {
	HwySeg = impSeg,
	HwyRamp = function(m: Model, F: CFrame, seed: number, spot: any)
		local d = table.clone(spot and spot.Data or {})
		d.Oneway = true
		d.Lanes = d.Lanes or 1
		d.ShR = d.ShR or 3
		impSeg(m, F, seed, { Size = spot and spot.Size, Data = d })
	end,
	HwyWall = impWall,
}

return TownHighway
