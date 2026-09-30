--[[
	FoodModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FoodModels

	🍦 Modèles 3D de la nourriture, partagés (v9.8 FAIR98 ; v9.9 FAIR99 :
	refaits, réalistes et À LA TAILLE DE LA MAIN) :
	  - serveur (FoodService) : l'aliment TENU en main (un Tool dont la
	    pièce "Handle" est dans le poing) ;
	  - client (FairFx) : les aliments exposés sur les comptoirs des stands.

	FoodModels.Build(id, cf?, scale?) -> Model (ancré, sans collision) :
	repère = POINT DE PRISE (le centre du poing), +Y = le haut de l'aliment,
	-Z = vers l'avant (loin du mangeur). La pièce "Handle" est centrée sur ce
	point (cornet, bâton, gobelet, serviette…) ; les pièces "Bite1",
	"Bite2"… disparaissent une à une (bouchées, FoodService) ; la dernière
	bouchée finit l'aliment.
	Échelle : une main d'avatar fait ~1 stud de large ; un cornet de glace
	tenu fait ~1,5 stud de haut (v9.8 : 2,2 : trop gros, et la prise était
	sous le cornet).
	~12 à 30 pièces par aliment, aucune lumière, aucun son.

	FoodModels.GRIP : Tool.Grip conseillé (voir FoodService) : aucune
	rotation (l'aliment reste DEBOUT dans la pose "outil" R15 et R6) et le
	poing centré sur la prise.
]]

local FoodModels = {}

local M = Enum.Material
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)

-- (Grip = C1 de la soudure RightGrip : poignée = main * C0 * Grip⁻¹ ; ici
-- l'aliment remonte de 0,05 dans le poing et avance de 0,02 : aucune rotation)
FoodModels.GRIP = CFrame.new(0, -0.05, 0.02)

type Add = (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?) -> BasePart

local RECIPES: { [string]: (add: Add) -> () } = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Cornet de glace : gaufrette conique (anneaux qui s'affinent + quadrillage),
-- 2 boules (fraise, pistache) avec leur collerette qui coule, vermicelles, cerise
RECIPES.IceCream = function(add)
	local waffle = rgb(214, 158, 92)
	local waffleDark = rgb(178, 120, 64)
	-- (cône : du bas pointu jusqu'au bord, tenu par le milieu)
	add("Handle", Vector3.new(0.34, 0.36, 0.36), CFrame.new(0, 0, 0) * UPRIGHT, waffle, M.Fabric, CYL)
	add("ConeTip", Vector3.new(0.3, 0.2, 0.2), CFrame.new(0, -0.3, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	add("ConeLow", Vector3.new(0.14, 0.12, 0.12), CFrame.new(0, -0.5, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	add("Cone2", Vector3.new(0.26, 0.46, 0.46), CFrame.new(0, 0.3, 0) * UPRIGHT, waffle, M.Fabric, CYL)
	add("Bite3", Vector3.new(0.18, 0.56, 0.56), CFrame.new(0, 0.52, 0) * UPRIGHT, waffle, M.Fabric, CYL)
	add("Bite3", Vector3.new(0.1, 0.62, 0.62), CFrame.new(0, 0.64, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	-- relief de la gaufrette : fins anneaux plus foncés
	add("ConeRing", Vector3.new(0.04, 0.37, 0.37), CFrame.new(0, 0.1, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	add("Cone2", Vector3.new(0.04, 0.47, 0.47), CFrame.new(0, 0.34, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	add("ConeTip", Vector3.new(0.04, 0.24, 0.24), CFrame.new(0, -0.2, 0) * UPRIGHT, waffleDark, M.Fabric, CYL)
	-- boule du bas (fraise) + collerette qui coule
	local straw = rgb(255, 170, 196)
	add("Bite2", Vector3.new(0.7, 0.62, 0.7), CFrame.new(0, 0.9, 0), straw, M.SmoothPlastic, BALL)
	-- (une Ball Roblox reste ronde : collerette = disque)
	add("Bite2", Vector3.new(0.12, 0.74, 0.74), CFrame.new(0, 0.7, 0) * UPRIGHT, straw:Lerp(rgb(255, 255, 255), 0.1), M.SmoothPlastic, CYL)
	for i = 0, 2 do
		local a = math.rad(i * 130 + 25)
		add("Bite2", Vector3.new(0.14, 0.24, 0.14), CFrame.new(math.sin(a) * 0.3, 0.6, math.cos(a) * 0.3), straw, M.SmoothPlastic, BALL)
	end
	-- boule du haut (pistache) + vermicelles + cerise
	local pist = rgb(176, 222, 160)
	add("Bite1", Vector3.new(0.6, 0.54, 0.6), CFrame.new(0.02, 1.36, 0), pist, M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.1, 0.62, 0.62), CFrame.new(0.02, 1.16, 0) * UPRIGHT, pist:Lerp(rgb(255, 255, 255), 0.1), M.SmoothPlastic, CYL)
	local sprinkle = { rgb(236, 72, 120), rgb(80, 170, 255), rgb(255, 214, 60), rgb(255, 255, 255) }
	for i = 0, 6 do
		local a = math.rad(i * 51)
		local p = CFrame.new(math.sin(a) * 0.2, 1.56 - (i % 2) * 0.05, math.cos(a) * 0.2)
		add("Bite1", Vector3.new(0.08, 0.025, 0.025), p * CFrame.Angles(0, a, math.rad(30)), sprinkle[i % 4 + 1], M.SmoothPlastic)
	end
	add("Bite1", Vector3.new(0.17, 0.17, 0.17), CFrame.new(0.04, 1.69, 0), rgb(200, 24, 44), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.025, 0.16, 0.025), CFrame.new(0.07, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-20)), rgb(90, 130, 60), M.Wood)
end

-- Barbe à papa : bâton blanc + nuage duveteux (boules qui se chevauchent,
-- légèrement translucides, deux roses)
RECIPES.CandyFloss = function(add)
	add("Handle", Vector3.new(0.7, 0.09, 0.09), CFrame.new(0, 0.05, 0) * UPRIGHT, rgb(250, 246, 238), M.Wood, CYL)
	add("Stick", Vector3.new(0.5, 0.08, 0.08), CFrame.new(0, 0.6, 0) * UPRIGHT, rgb(250, 246, 238), M.Wood, CYL)
	local pinks = { rgb(255, 184, 214), rgb(255, 204, 226), rgb(248, 170, 206) }
	local puffs = {
		{ 3, Vector3.new(0, 1.05, 0), 0.72 }, { 3, Vector3.new(0.24, 0.95, 0.12), 0.5 }, { 3, Vector3.new(-0.22, 0.98, -0.1), 0.52 },
		{ 2, Vector3.new(0.18, 1.35, 0.14), 0.62 }, { 2, Vector3.new(-0.2, 1.32, 0.02), 0.6 }, { 2, Vector3.new(0.02, 1.28, -0.24), 0.52 },
		{ 1, Vector3.new(0.02, 1.62, 0.02), 0.58 }, { 1, Vector3.new(0.22, 1.56, -0.12), 0.42 }, { 1, Vector3.new(-0.18, 1.58, 0.16), 0.44 },
	}
	for i, pf in ipairs(puffs) do
		local p = add("Bite" .. pf[1], Vector3.one * pf[3], CFrame.new(pf[2]), pinks[i % #pinks + 1], M.Fabric, BALL)
		p.Transparency = 0.08
	end
end

-- Churros : cornet en papier rayé, 3 churros cannelés (étoile), sucre
RECIPES.Churros = function(add)
	add("Handle", Vector3.new(0.5, 0.42, 0.42), CFrame.new(0, 0, 0) * UPRIGHT, rgb(255, 250, 244), M.SmoothPlastic, CYL)
	add("Band", Vector3.new(0.12, 0.44, 0.44), CFrame.new(0, 0.08, 0) * UPRIGHT, rgb(226, 60, 80), M.SmoothPlastic, CYL)
	add("Band", Vector3.new(0.06, 0.44, 0.44), CFrame.new(0, -0.14, 0) * UPRIGHT, rgb(226, 60, 80), M.SmoothPlastic, CYL)
	local gold = rgb(206, 138, 70)
	local sugar = rgb(250, 240, 226)
	for i, s in ipairs({ { -0.09, 0.02, 7 }, { 0.1, 0.04, -6 }, { 0, -0.1, 1 } }) do
		local base = CFrame.new(s[1], 0.25, s[2]) * CFrame.Angles(math.rad(s[2] * 40), 0, math.rad(s[3]))
		for k, seg in ipairs({ { "Churro", 0.25 }, { "Bite2", 0.7 }, { "Bite1", 1.1 } }) do
			local name = seg[1]
			if i == 3 and k == 3 then
				name = "Bite2"
			end
			local c = base * CFrame.new(0, seg[2], 0)
			add(name, Vector3.new(0.14, 0.42, 0.14), c, gold, M.SmoothPlastic)
			add(name, Vector3.new(0.14, 0.42, 0.14), c * CFrame.Angles(0, math.rad(45), 0), gold:Lerp(rgb(160, 96, 50), 0.25), M.SmoothPlastic)
			add(name, Vector3.new(0.06, 0.04, 0.06), c * CFrame.new(0.05, 0.1 * k, 0.05), sugar, M.Sand)
		end
	end
end

-- Popcorn : boîte évasée rayée rouge / blanc, étiquette, grains qui débordent
RECIPES.Popcorn = function(add)
	add("Handle", Vector3.new(0.62, 0.72, 0.5), CFrame.new(0, 0, 0), rgb(255, 252, 246), M.SmoothPlastic)
	for _, x in ipairs({ -0.21, 0, 0.21 }) do
		add("Stripe", Vector3.new(0.09, 0.77, 0.55), CFrame.new(x, 0, 0), rgb(214, 36, 50), M.SmoothPlastic)
	end
	add("Rim", Vector3.new(0.68, 0.06, 0.56), CFrame.new(0, 0.37, 0), rgb(214, 36, 50), M.SmoothPlastic)
	add("Label", Vector3.new(0.4, 0.2, 0.02), CFrame.new(0, 0.05, -0.26), rgb(255, 214, 60), M.SmoothPlastic)
	local corn = { rgb(255, 248, 228), rgb(255, 236, 184), rgb(252, 244, 214) }
	local spots = {
		{ -0.2, 0.44, -0.12, 4 }, { 0.18, 0.45, 0.1, 4 }, { 0, 0.47, 0, 4 }, { -0.12, 0.45, 0.14, 4 }, { 0.2, 0.46, -0.14, 4 },
		{ -0.16, 0.56, 0.02, 3 }, { 0.12, 0.57, -0.04, 3 }, { 0.02, 0.58, 0.12, 3 }, { -0.04, 0.58, -0.14, 3 },
		{ 0.08, 0.68, 0.04, 2 }, { -0.1, 0.67, -0.04, 2 }, { 0.16, 0.66, 0.12, 2 },
		{ 0, 0.77, 0, 1 }, { -0.08, 0.75, 0.09, 1 }, { 0.09, 0.74, -0.08, 1 },
	}
	for i, s in ipairs(spots) do
		local size = 0.16 + (i % 3) * 0.035
		add("Bite" .. s[4], Vector3.new(size, size * 0.85, size), CFrame.new(s[1], s[2], s[3]) * CFrame.Angles(i, i * 2, 0), corn[i % 3 + 1], M.SmoothPlastic, BALL)
	end
end

-- Crêpe pliée en cône dans son papier, nappage chocolat, fraises, chantilly
RECIPES.Crepe = function(add)
	add("Handle", Vector3.new(0.5, 0.44, 0.44), CFrame.new(0, 0, 0) * UPRIGHT, rgb(250, 244, 232), M.SmoothPlastic, CYL)
	add("PaperEdge", Vector3.new(0.05, 0.46, 0.46), CFrame.new(0, 0.24, 0) * UPRIGHT, rgb(120, 190, 240), M.SmoothPlastic, CYL)
	local crepe = rgb(232, 190, 122)
	local tan = rgb(206, 150, 84)
	add("Roll", Vector3.new(0.4, 0.48, 0.48), CFrame.new(0, 0.46, 0) * UPRIGHT, crepe, M.Fabric, CYL)
	add("Bite3", Vector3.new(0.4, 0.46, 0.46), CFrame.new(0, 0.84, 0) * UPRIGHT, crepe, M.Fabric, CYL)
	add("Bite3", Vector3.new(0.34, 0.08, 0.3), CFrame.new(0.12, 0.84, -0.2) * CFrame.Angles(0, 0, math.rad(20)), tan, M.Fabric)
	add("Bite2", Vector3.new(0.3, 0.42, 0.42), CFrame.new(0, 1.18, 0.02) * UPRIGHT, crepe, M.Fabric, CYL)
	add("Bite2", Vector3.new(0.2, 0.36, 0.2), CFrame.new(0.06, 1.28, -0.12) * CFrame.Angles(0, 0, math.rad(12)), tan, M.Fabric)
	-- garniture : chantilly, fraises, chocolat
	add("Bite1", Vector3.new(0.34, 0.24, 0.34), CFrame.new(0, 1.44, 0), rgb(255, 252, 246), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.22, 0.2, 0.22), CFrame.new(0.02, 1.56, 0), rgb(255, 252, 246), M.SmoothPlastic, BALL)
	for i, p in ipairs({ Vector3.new(-0.14, 1.46, -0.1), Vector3.new(0.15, 1.44, 0.08) }) do
		add("Bite1", Vector3.new(0.14, 0.16, 0.12), CFrame.new(p) * CFrame.Angles(0, i, 0.4), rgb(226, 40, 60), M.SmoothPlastic, BALL)
	end
	for i = 0, 2 do
		add(if i == 0 then "Bite1" else "Bite2", Vector3.new(0.34, 0.025, 0.03), CFrame.new(0, 1.3 - i * 0.2, -0.235) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 18 else -18)), rgb(122, 72, 44), M.SmoothPlastic)
	end
end

-- Part de pizza (pointe en haut) : vrai triangle (2 coins), bord de pâte
-- gonflé, fromage, pepperoni, basilic, fil de fromage
RECIPES.PizzaSlice = function(add)
	local crust = rgb(210, 150, 80)
	local cheese = rgb(255, 204, 100)
	-- (le poing tient le bord de pâte, en bas ; la part monte en pointe)
	add("Handle", Vector3.new(0.95, 0.2, 0.2), CFrame.identity, crust, M.SmoothPlastic, CYL)
	add("CrustTop", Vector3.new(0.9, 0.08, 0.16), CFrame.new(0, 0.1, 0), crust:Lerp(rgb(150, 96, 50), 0.3), M.SmoothPlastic)
	-- 9 bandes horizontales de plus en plus étroites : un vrai triangle
	for i = 0, 8 do
		local y = 0.2 + i * 0.14
		local w = 0.86 * (1 - (i + 0.5) / 9.3)
		local b = if i <= 2 then 3 elseif i <= 5 then 2 else 1
		add("Bite" .. b, Vector3.new(w, 0.145, 0.06), CFrame.new(0, y, 0.02), crust:Lerp(cheese, 0.25), M.SmoothPlastic)
		add("Bite" .. b, Vector3.new(math.max(0.04, w - 0.05), 0.145, 0.04), CFrame.new(0, y, -0.03), cheese, M.SmoothPlastic)
	end
	local pep = rgb(186, 48, 44)
	for _, s in ipairs({ { -0.19, 0.3, 3 }, { 0.19, 0.34, 3 }, { 0.04, 0.6, 2 }, { -0.05, 0.9, 2 }, { 0.01, 1.12, 1 } }) do
		add("Bite" .. s[3], Vector3.new(0.03, 0.2, 0.2), CFrame.new(s[1], s[2], -0.065) * CFrame.Angles(0, math.rad(90), 0), pep, M.SmoothPlastic, CYL)
	end
	add("Bite2", Vector3.new(0.12, 0.08, 0.02), CFrame.new(0.14, 0.7, -0.065) * CFrame.Angles(0, 0, 0.6), rgb(60, 140, 60), M.SmoothPlastic)
	add("Bite3", Vector3.new(0.1, 0.07, 0.02), CFrame.new(-0.2, 0.48, -0.065) * CFrame.Angles(0, 0, -0.4), rgb(60, 140, 60), M.SmoothPlastic)
	add("Bite1", Vector3.new(0.04, 0.26, 0.04), CFrame.new(0.07, 1.0, -0.07), cheese, M.SmoothPlastic)
end

-- Taco : coquille dorée pliée en U (2 flancs + fond arrondi), viande,
-- salade qui dépasse, tomates, fromage râpé ; tenu par le bas, couché (axe X)
RECIPES.Taco = function(add)
	local shell = rgb(236, 186, 92)
	local shellDark = rgb(214, 160, 70)
	local meat = rgb(132, 72, 44)
	local lettuce = rgb(120, 196, 88)
	local cheese = rgb(255, 214, 90)
	local tomato = rgb(220, 50, 44)
	-- 5 tronçons le long de X : la coquille est plus haute au milieu, plus
	-- basse aux bouts (silhouette en demi-lune vue de côté) ; Handle = bout
	-- gauche (tenu), puis Bite3, Bite2, Bite1 (bout droit, croqué d'abord)
	local segs = { { "Handle", -0.5 }, { "Bite3", -0.25 }, { "Bite2", 0 }, { "Bite2", 0.25 }, { "Bite1", 0.5 } }
	for i, sg in ipairs(segs) do
		local name, x = sg[1], sg[2]
		local w = 0.26
		local u = x / 0.62
		local h = 0.64 * math.sqrt(math.max(0.12, 1 - u * u)) -- hauteur du flanc
		local r = 0.34 * math.sqrt(math.max(0.3, 1 - u * u)) -- rondeur du fond
		local shellName = if name == "Handle" and i == 1 then "Handle" else name
		add(shellName, Vector3.new(w, r, r), CFrame.new(x, r / 2, 0), shell, M.SmoothPlastic, CYL)
		for _, sz in ipairs({ -1, 1 }) do
			add(if name == "Handle" then "ShellSide" else name, Vector3.new(w + 0.01, h, 0.05), CFrame.new(x, r / 2 + h / 2 - 0.05, sz * (r / 2 + 0.03)) * CFrame.Angles(math.rad(sz * 12), 0, 0), if i % 2 == 0 then shell else shellDark, M.SmoothPlastic)
		end
		local fill = if name == "Handle" then "Filling" else name
		local top = r / 2 + h - 0.1
		add(fill, Vector3.new(w - 0.02, math.max(0.1, h - 0.25), r * 0.8), CFrame.new(x, r / 2 + (h - 0.25) / 2, 0), meat, M.Sand)
		add(fill, Vector3.new(w + 0.03, 0.12, r + 0.12), CFrame.new(x, top, 0) * CFrame.Angles(0.15 * i, 0, 0.25 * (i % 2 - 0.5)), lettuce, M.Grass)
		add(fill, Vector3.new(0.1, 0.1, 0.1), CFrame.new(x + 0.05, top + 0.06, (i % 2 - 0.5) * 0.14), tomato, M.SmoothPlastic)
		add(fill, Vector3.new(w - 0.06, 0.035, r * 0.7), CFrame.new(x, top + 0.08, 0.02), cheese, M.SmoothPlastic)
	end
end

-- Milkshake : gobelet évasé (logo), couvercle dôme transparent, chantilly
-- en spirale, cerise, paille rayée
RECIPES.Milkshake = function(add)
	add("Handle", Vector3.new(0.7, 0.5, 0.5), CFrame.new(0, 0, 0) * UPRIGHT, rgb(255, 176, 206), M.SmoothPlastic, CYL)
	add("CupLow", Vector3.new(0.2, 0.44, 0.44), CFrame.new(0, -0.42, 0) * UPRIGHT, rgb(255, 160, 196), M.SmoothPlastic, CYL)
	add("CupTop", Vector3.new(0.34, 0.56, 0.56), CFrame.new(0, 0.5, 0) * UPRIGHT, rgb(255, 186, 212), M.SmoothPlastic, CYL)
	add("Logo", Vector3.new(0.3, 0.22, 0.02), CFrame.new(0, 0.1, -0.255), rgb(255, 255, 255), M.SmoothPlastic)
	add("LogoHeart", Vector3.new(0.12, 0.12, 0.02), CFrame.new(0, 0.1, -0.265), rgb(236, 72, 140), M.SmoothPlastic, BALL)
	local lid = add("Lid", Vector3.new(0.3, 0.6, 0.6), CFrame.new(0, 0.82, 0) * UPRIGHT, rgb(240, 248, 255), M.Glass, CYL)
	lid.Transparency = 0.6
	-- chantilly en spirale (disques de plus en plus petits + pointe)
	local cream = rgb(255, 252, 246)
	add("Bite3", Vector3.new(0.14, 0.5, 0.5), CFrame.new(0, 0.74, 0) * UPRIGHT, cream, M.SmoothPlastic, CYL)
	add("Bite2", Vector3.new(0.14, 0.38, 0.38), CFrame.new(0.01, 0.86, 0) * UPRIGHT, cream, M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.12, 0.26, 0.26), CFrame.new(0, 0.97, 0.01) * UPRIGHT, cream, M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.15, 0.15, 0.15), CFrame.new(0.02, 1.08, 0), rgb(200, 24, 44), M.SmoothPlastic, BALL)
	-- paille rayée (2 couleurs, inclinée)
	local straw = CFrame.new(0.12, 1.02, 0.06) * CFrame.Angles(math.rad(12), 0, math.rad(-14))
	add("Bite3", Vector3.new(0.9, 0.07, 0.07), straw * UPRIGHT, rgb(255, 255, 255), M.SmoothPlastic, CYL)
	add("Bite3", Vector3.new(0.12, 0.075, 0.075), straw * CFrame.new(0, 0.2, 0) * UPRIGHT, rgb(80, 170, 255), M.SmoothPlastic, CYL)
	add("Bite3", Vector3.new(0.12, 0.075, 0.075), straw * CFrame.new(0, -0.05, 0) * UPRIGHT, rgb(80, 170, 255), M.SmoothPlastic, CYL)
end

-- Hot dog dans sa barquette en papier : pain brioché (2 moitiés bombées),
-- saucisse grillée (bouts arrondis), moutarde en zigzag, ketchup
RECIPES.HotDog = function(add)
	local bun = rgb(226, 170, 100)
	local bunTop = rgb(196, 130, 66)
	local sausage = rgb(176, 76, 52)
	add("Handle", Vector3.new(1.2, 0.16, 0.5), CFrame.new(0.1, -0.1, 0), rgb(255, 252, 246), M.SmoothPlastic)
	add("TrayCheck", Vector3.new(1.18, 0.02, 0.1), CFrame.new(0.1, 0.0, -0.2), rgb(226, 60, 70), M.SmoothPlastic)
	-- tronçons le long de X : Bite3 (gauche) .. Bite1 (bout droit)
	local segs = { { "Bite3", -0.3 }, { "Bite2", 0.1 }, { "Bite1", 0.5 } }
	for _, sg in ipairs(segs) do
		local name, x = sg[1], sg[2]
		for _, sz in ipairs({ -1, 1 }) do
			-- (moitiés de pain bombées : cylindres couchés le long de X)
			add(name, Vector3.new(0.42, 0.28, 0.28), CFrame.new(x, 0.1, sz * 0.12), bun, M.SmoothPlastic, CYL)
			add(name, Vector3.new(0.4, 0.04, 0.16), CFrame.new(x, 0.25, sz * 0.13), bunTop, M.SmoothPlastic)
		end
		add(name, Vector3.new(0.42, 0.15, 0.15), CFrame.new(x, 0.2, 0), sausage, M.SmoothPlastic, CYL)
		add(name, Vector3.new(0.1, 0.03, 0.06), CFrame.new(x - 0.1, 0.285, 0) * CFrame.Angles(0, math.rad(40), 0), rgb(255, 204, 40), M.SmoothPlastic)
		add(name, Vector3.new(0.1, 0.03, 0.06), CFrame.new(x + 0.08, 0.285, 0) * CFrame.Angles(0, math.rad(-40), 0), rgb(255, 204, 40), M.SmoothPlastic)
	end
	add("Bite3", Vector3.new(0.15, 0.15, 0.15), CFrame.new(-0.52, 0.2, 0), sausage, M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.15, 0.15, 0.15), CFrame.new(0.72, 0.2, 0), sausage, M.SmoothPlastic, BALL)
	add("Bite2", Vector3.new(0.9, 0.025, 0.035), CFrame.new(0.1, 0.29, 0.04), rgb(200, 30, 30), M.SmoothPlastic)
end

-- Pomme d'amour : bâton de bois, pomme vernie rouge brillante (+ collerette
-- de sucre qui a coulé au pied), feuille
RECIPES.CandyApple = function(add)
	add("Handle", Vector3.new(0.7, 0.09, 0.09), CFrame.new(0, 0, 0) * UPRIGHT, rgb(206, 164, 114), M.Wood, CYL)
	local glaze = rgb(196, 18, 40)
	local b2 = add("Bite2", Vector3.new(0.72, 0.62, 0.72), CFrame.new(0, 0.62, 0), glaze, M.SmoothPlastic, BALL)
	b2.Reflectance = 0.18
	local b1 = add("Bite1", Vector3.new(0.62, 0.52, 0.62), CFrame.new(0, 0.86, 0), rgb(214, 26, 48), M.SmoothPlastic, BALL)
	b1.Reflectance = 0.18
	add("Bite2", Vector3.new(0.08, 0.72, 0.72), CFrame.new(0, 0.36, 0) * UPRIGHT, rgb(170, 12, 30), M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.18, 0.04, 0.1), CFrame.new(0.1, 1.12, 0.02) * CFrame.Angles(0, 0.4, math.rad(25)), rgb(96, 170, 70), M.SmoothPlastic)
	add("Bite1", Vector3.new(0.12, 0.12, 0.03), CFrame.new(-0.12, 0.92, -0.29) * CFrame.Angles(0.3, 0.4, 0), rgb(255, 230, 230), M.SmoothPlastic).Transparency = 0.3
end

-- Beignet (vertical, tenu par le bas) : anneau de pâte (12 boules), glaçage
-- rose côté visage, vermicelles de couleur
RECIPES.Donut = function(add)
	local dough = rgb(214, 150, 84)
	local glaze = rgb(255, 150, 196)
	add("Handle", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0, 0), dough, M.SmoothPlastic, BALL)
	local sprinkle = { rgb(80, 170, 255), rgb(255, 214, 60), rgb(255, 255, 255), rgb(128, 214, 150) }
	for k = 1, 11 do
		local a = k / 12 * math.pi * 2
		local p = CFrame.new(math.sin(a) * 0.34, 0.34 - math.cos(a) * 0.34, 0)
		local bite = if k >= 4 and k <= 8 then 1 else 2 -- le haut part d'abord
		add("Bite" .. bite, Vector3.new(0.3, 0.3, 0.3), p, dough, M.SmoothPlastic, BALL)
		add("Bite" .. bite, Vector3.new(0.26, 0.26, 0.12), p * CFrame.new(0, 0, 0.1), glaze, M.SmoothPlastic, BALL)
		if k % 2 == 0 then
			add("Bite" .. bite, Vector3.new(0.07, 0.02, 0.02), p * CFrame.new(0.03, 0.02, 0.16) * CFrame.Angles(0, 0, k), sprinkle[k % 4 + 1], M.SmoothPlastic)
		end
	end
end

-- Aliment id -> Model (ancré) ; `cf` = repère de la prise ; `scale` (1)
function FoodModels.Build(id: string, cf: CFrame?, scale: number?): Model?
	local recipe = RECIPES[id]
	if not recipe then
		return nil
	end
	local base = cf or CFrame.identity
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = id
	local handle: BasePart? = nil
	recipe(function(name, size, loc, color, material, shape, className)
		local p = Instance.new((className or "Part") :: any) :: BasePart
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape and p:IsA("Part") then
			p.Shape = shape
		end
		p.Size = size * s
		p.CFrame = base * CFrame.new(loc.Position * s) * loc.Rotation
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Parent = model
		if name == "Handle" and handle == nil then
			handle = p
		end
		return p
	end)
	model.PrimaryPart = handle
	return model
end

function FoodModels.Has(id: string): boolean
	return RECIPES[id] ~= nil
end

return FoodModels
