--[[
	StreetTrees (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > StreetTrees

	🌳 Dopamine Town (v11, CITY11) : les ARBRES D'ALIGNEMENT des rues,
	construits côté client (TownStreetLife : arbres du serveur posés sur une
	grille de pied d'arbre ; DistrictTownhouse : "TwnTree"). Des espèces de
	VILLE, chacune avec sa silhouette, son écorce et ses couleurs :
	  Plane     : platane (écorce tachetée crème / kaki, 3 charpentières en
	              fourche, grand houppier aplati) ;
	  Linden    : tilleul (tronc droit sombre, houppier ovale dense, vert tendre) ;
	  Ginkgo    : ginkgo (port pyramidal irrégulier, éventails dorés ou verts) ;
	  Hornbeam  : charme fastigié (colonne étroite vert foncé) ;
	  Cherry    : cerisier à fleurs (vase bas et large, nuage rose, pétales) ;
	  RedMaple  : érable rouge (boule rouge-orangé).
	Pied d'arbre : fosse (cadre en fonte + grille en 4 quarts à fentes,
	paillis) et CORSET de protection (4 barreaux + 2 colliers) pour les
	jeunes sujets. Taille / rotation / teintes variant avec la graine.
	Tronc solide (collision locale), feuillage sans collision ; aucune
	lumière ; 14 à 26 pièces par arbre.

	API :
	  StreetTrees.SPECIES : { string }
	  StreetTrees.Pick(seed) -> espèce
	  StreetTrees.Build(parent, base: Vector3, height, seed, species?, opts?) -> (Model, parts)
	      opts = { Pit = bool (fosse + grille), Guard = bool (corset), Lawn = bool (pétales au sol), Name = string? }
]]

local CityKit = require(script.Parent.CityKit)

local StreetTrees = {}

local M = CityKit.M
local rgb = CityKit.rgb
local hash = CityKit.Hash
local IRON = rgb(44, 46, 54)

StreetTrees.SPECIES = { "Plane", "Linden", "Ginkgo", "Hornbeam", "Cherry", "RedMaple" }

function StreetTrees.Pick(seed: number): string
	return StreetTrees.SPECIES[1 + math.floor(hash(seed, 41) * #StreetTrees.SPECIES) % #StreetTrees.SPECIES]
end

local BARK = {
	Plane = rgb(176, 162, 128), Linden = rgb(86, 70, 58), Ginkgo = rgb(110, 92, 76),
	Hornbeam = rgb(124, 116, 104), Cherry = rgb(110, 66, 58), RedMaple = rgb(96, 80, 70),
}

local function leaves(species: string, seed: number): { Color3 }
	if species == "Ginkgo" then
		return hash(seed, 3) < 0.55 and { rgb(250, 206, 60), rgb(240, 180, 40), rgb(252, 224, 110) } or { rgb(130, 180, 80), rgb(110, 160, 70), rgb(150, 196, 96) }
	elseif species == "Cherry" then
		return { rgb(255, 182, 206), rgb(250, 160, 190), rgb(255, 210, 226) }
	elseif species == "RedMaple" then
		return { rgb(206, 64, 46), rgb(232, 110, 50), rgb(190, 50, 50) }
	elseif species == "Hornbeam" then
		return { rgb(56, 106, 56), rgb(70, 122, 62), rgb(48, 94, 52) }
	elseif species == "Linden" then
		return { rgb(120, 176, 80), rgb(100, 160, 70), rgb(140, 190, 96) }
	end
	return { rgb(96, 150, 70), rgb(84, 136, 62), rgb(112, 164, 80) } -- platane
end

-- grappe de feuillage (ovale, sans collision)
local function clump(m: Instance, at: CFrame, size: Vector3, color: Color3)
	return CityKit.Egg(m, "Leaves", at, size, color, M.Grass)
end

function StreetTrees.Build(parent: Instance, base: Vector3, height: number, seed: number, species: string?, opts: { [string]: any }?): (Model, number)
	local o = opts or {}
	local sp = species or StreetTrees.Pick(seed)
	local m = Instance.new("Model")
	m.Name = o.Name or "StreetTree"
	local before = CityKit.Created()
	local H = math.clamp(height, 8, 26)
	local rot = CFrame.new(base) * CFrame.Angles(0, hash(seed, 1) * math.pi * 2, 0)
	local bark = BARK[sp] or BARK.Linden
	local cols = leaves(sp, seed)
	local function C(i: number): Color3
		return cols[1 + (i + seed) % #cols]
	end
	-- fosse : cadre en fonte, 4 quarts de grille à fentes, paillis
	if o.Pit then
		CityKit.Box(m, "PitMulch", rot, -1.5, 1.5, -0.2, 0.03, -1.5, 1.5, rgb(96, 70, 50), M.Ground)
		CityKit.Box(m, "PitFrame", rot, -1.9, 1.9, -0.1, 0.06, -1.9, -1.6, IRON, M.Metal)
		CityKit.Box(m, "PitFrame", rot, -1.9, 1.9, -0.1, 0.06, 1.6, 1.9, IRON, M.Metal)
		CityKit.Box(m, "PitFrame", rot, -1.9, -1.6, -0.1, 0.06, -1.6, 1.6, IRON, M.Metal)
		CityKit.Box(m, "PitFrame", rot, 1.6, 1.9, -0.1, 0.06, -1.6, 1.6, IRON, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local g = CityKit.Box(m, "PitGrate", rot, math.min(sx * 0.45, sx * 1.6), math.max(sx * 0.45, sx * 1.6), 0.04, 0.09, math.min(sz * 0.45, sz * 1.6), math.max(sz * 0.45, sz * 1.6), rgb(64, 66, 74), M.DiamondPlate)
				local _ = g
			end
		end
	end
	-- corset (4 barreaux + 2 colliers)
	if o.Guard then
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local foot = (rot * CFrame.new(math.cos(a) * 1.25, 0.05, math.sin(a) * 1.25)).Position
			local top = (rot * CFrame.new(math.cos(a) * 0.95, 4.6, math.sin(a) * 0.95)).Position
			CityKit.Rod(m, "GuardBar", foot, top, 0.12, IRON, M.Metal)
		end
		CityKit.Column(m, "GuardRing", rot, 0, 0, 2.2, 2.32, 2.3, IRON, M.Metal)
		CityKit.Column(m, "GuardRing", rot, 0, 0, 4.4, 4.52, 1.95, IRON, M.Metal)
	end
	-- tronc (évasé au pied) ; proportions par espèce
	local trunkD = math.clamp(H * 0.06, 0.6, 1.3)
	local split = H * (sp == "Hornbeam" and 0.22 or (sp == "Cherry" and 0.32 or 0.42))
	CityKit.Column(m, "Trunk", rot, 0, 0, -0.1, split + 0.6, trunkD, bark, M.Wood, true)
	CityKit.Egg(m, "TrunkFlare", rot * CFrame.new(0, 0.25, 0), Vector3.new(trunkD * 1.7, 0.9, trunkD * 1.7), bark:Lerp(rgb(60, 44, 34), 0.25), M.Wood)
	if sp == "Plane" then
		-- écorce tachetée
		for k = 0, 2 do
			local a = k * 2.1 + hash(seed, k) * 0.6
			CityKit.Egg(m, "BarkPatch", rot * CFrame.new(math.cos(a) * trunkD * 0.42, 1.4 + k * split * 0.28, math.sin(a) * trunkD * 0.42), Vector3.new(trunkD * 0.42, 0.9, trunkD * 0.42), k % 2 == 0 and rgb(222, 214, 180) or rgb(140, 140, 104), M.Wood)
		end
	end
	if sp == "Hornbeam" then
		-- colonne étroite (3 ovales empilés)
		for k = 0, 2 do
			local y = split + H * 0.12 + k * H * 0.22
			clump(m, rot * CFrame.new(hash(seed, k + 5) * 0.4 - 0.2, y, 0), Vector3.new(H * 0.26, H * 0.36, H * 0.26), C(k))
		end
	elseif sp == "Ginkgo" then
		-- pyramide irrégulière : étages qui rétrécissent
		CityKit.Column(m, "Leader", rot, 0, 0, split, H * 0.92, trunkD * 0.55, bark, M.Wood)
		for k = 0, 3 do
			local y = split + 1 + k * (H - split) * 0.22
			local r = H * (0.34 - k * 0.07)
			local a = hash(seed, k) * math.pi * 2
			clump(m, rot * CFrame.new(math.cos(a) * 0.6, y, math.sin(a) * 0.6), Vector3.new(r, H * 0.16, r * 0.9), C(k))
		end
	else
		-- charpentières (3) puis houppier en grappes
		local spread = sp == "Plane" and 0.32 or (sp == "Cherry" and 0.36 or 0.24)
		local crownY = sp == "Cherry" and H * 0.62 or H * 0.7
		for k = 0, 2 do
			local a = k * (math.pi * 2 / 3) + hash(seed, k + 9) * 0.5
			local from = (rot * CFrame.new(0, split, 0)).Position
			local to = (rot * CFrame.new(math.cos(a) * H * spread * 0.7, crownY - H * 0.08, math.sin(a) * H * spread * 0.7)).Position
			CityKit.Rod(m, "Limb", from, to, trunkD * 0.5, bark, M.Wood)
		end
		local n = sp == "Plane" and 6 or 5
		local width = sp == "Linden" and H * 0.5 or (sp == "Plane" and H * 0.62 or (sp == "Cherry" and H * 0.64 or H * 0.56))
		local tall = sp == "Linden" and H * 0.62 or (sp == "Plane" and H * 0.36 or (sp == "Cherry" and H * 0.34 or H * 0.48))
		clump(m, rot * CFrame.new(0, crownY, 0), Vector3.new(width * 0.78, tall, width * 0.78), C(0))
		for k = 1, n do
			local a = k * (math.pi * 2 / n) + hash(seed, k) * 0.7
			local r = width * (0.28 + hash(seed, k + 20) * 0.08)
			local y = crownY + (hash(seed, k + 30) - 0.4) * tall * 0.5
			local s = width * (0.42 + hash(seed, k + 40) * 0.12)
			clump(m, rot * CFrame.new(math.cos(a) * r, y, math.sin(a) * r), Vector3.new(s, s * (tall / width) * 1.1, s), C(k))
		end
		if sp == "Cherry" and o.Lawn == true then
			-- pétales au sol
			for k = 0, 2 do
				local a = k * 2.2 + hash(seed, k + 60)
				CityKit.Part(m, "Petals", Vector3.new(0.05, 2.4, 2.4), rot * CFrame.new(math.cos(a) * 2.8, 0.04 + k * 0.01, math.sin(a) * 2.8) * CityKit.UPRIGHT, rgb(255, 196, 214), M.SmoothPlastic, "Cyl")
			end
		end
	end
	m.Parent = parent
	return m, CityKit.Created() - before
end

return StreetTrees
