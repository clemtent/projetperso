--[[
	FoodModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FoodModels

	🍦 Modèles 3D de la nourriture (v9.8, FAIR98), partagés :
	  - serveur (FoodService) : l'aliment TENU en main (un Tool dont la
	    pièce "Handle" est au creux de la main) ;
	  - client (FairFx) : les aliments exposés sur les comptoirs des stands.

	FoodModels.Build(id, cf?, scale?) -> Model (ancré, sans collision) :
	repère = centre de la pièce "Handle" (tenue dans la main, +Y vers le
	haut) ; les pièces "Bite1", "Bite2"… disparaissent une à une (bouchées,
	FoodService) ; la dernière bouchée finit l'aliment.
	~6 à 14 pièces par aliment, aucune lumière, aucun son.
]]

local FoodModels = {}

local M = Enum.Material
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)

type Add = (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?) -> BasePart

local RECIPES: { [string]: (add: Add) -> () } = {}

-- Cornet de glace : cornet en 3 anneaux, 2 boules, cerise
RECIPES.IceCream = function(add)
	local waffle = Color3.fromRGB(222, 168, 104)
	add("Handle", Vector3.new(0.5, 0.34, 0.34), UPRIGHT, waffle, M.Wood, CYL)
	add("Cone2", Vector3.new(0.4, 0.5, 0.5), CFrame.new(0, 0.42, 0) * UPRIGHT, Color3.fromRGB(228, 176, 110), M.Wood, CYL)
	add("Bite3", Vector3.new(0.34, 0.66, 0.66), CFrame.new(0, 0.78, 0) * UPRIGHT, Color3.fromRGB(234, 184, 118), M.Wood, CYL)
	add("Bite2", Vector3.new(0.78, 0.78, 0.78), CFrame.new(0, 1.2, 0), Color3.fromRGB(255, 176, 206), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.66, 0.66, 0.66), CFrame.new(0, 1.68, 0), Color3.fromRGB(170, 236, 206), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0.06, 2.05, 0), Color3.fromRGB(226, 40, 70), M.SmoothPlastic, BALL)
end

-- Barbe à papa : bâton + nuage rose (3 boules)
RECIPES.CandyFloss = function(add)
	add("Handle", Vector3.new(0.7, 0.14, 0.14), UPRIGHT, Color3.fromRGB(252, 246, 236), M.Wood, CYL)
	add("Stick", Vector3.new(0.9, 0.1, 0.1), CFrame.new(0, 0.75, 0) * UPRIGHT, Color3.fromRGB(252, 246, 236), M.Wood, CYL)
	add("Bite3", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.35, 0), Color3.fromRGB(255, 176, 214), M.SmoothPlastic, BALL)
	add("Bite2", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0.32, 1.72, 0.1), Color3.fromRGB(255, 196, 226), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.8, 0.8, 0.8), CFrame.new(-0.28, 1.85, -0.08), Color3.fromRGB(214, 190, 255), M.SmoothPlastic, BALL)
end

-- Churros : cornet en papier rayé + 2 bâtons dorés
RECIPES.Churros = function(add)
	add("Handle", Vector3.new(0.6, 0.46, 0.46), UPRIGHT, Color3.fromRGB(255, 250, 244), M.SmoothPlastic, CYL)
	add("Band", Vector3.new(0.14, 0.48, 0.48), CFrame.new(0, 0.1, 0) * UPRIGHT, Color3.fromRGB(236, 72, 96), M.SmoothPlastic, CYL)
	local gold = Color3.fromRGB(214, 150, 80)
	for i, x in ipairs({ -0.09, 0.1 }) do
		local tilt = CFrame.Angles(0, 0, math.rad(i == 1 and 6 or -5))
		add("Churro", Vector3.new(0.2, 0.7, 0.2), CFrame.new(x, 0.55, 0) * tilt, gold, M.SmoothPlastic)
		add("Bite2", Vector3.new(0.2, 0.5, 0.2), CFrame.new(x, 0.55, 0) * tilt * CFrame.new(0, 0.58, 0), gold, M.SmoothPlastic)
		add("Bite1", Vector3.new(0.2, 0.45, 0.2), CFrame.new(x, 0.55, 0) * tilt * CFrame.new(0, 1.05, 0), Color3.fromRGB(222, 160, 90), M.SmoothPlastic)
	end
end

-- Popcorn : boîte rayée rouge / blanc + grains
RECIPES.Popcorn = function(add)
	add("Handle", Vector3.new(0.7, 0.8, 0.55), CFrame.identity, Color3.fromRGB(255, 252, 246), M.SmoothPlastic)
	for _, x in ipairs({ -0.22, 0.22 }) do
		add("Stripe", Vector3.new(0.14, 0.82, 0.57), CFrame.new(x, 0, 0), Color3.fromRGB(226, 40, 60), M.SmoothPlastic)
	end
	local corn = { Color3.fromRGB(255, 248, 226), Color3.fromRGB(255, 236, 180) }
	local spots = { { -0.18, 0.5, -0.1 }, { 0.16, 0.52, 0.08 }, { 0, 0.62, 0 }, { -0.1, 0.6, 0.14 }, { 0.2, 0.62, -0.12 }, { -0.2, 0.7, 0.05 }, { 0.08, 0.76, -0.04 }, { 0.02, 0.84, 0.08 } }
	for i, s in ipairs(spots) do
		local bite = 4 - math.floor((i - 1) / 2) -- les grains du dessus partent d'abord
		add("Bite" .. bite, Vector3.new(0.3, 0.3, 0.3), CFrame.new(s[1], s[2], s[3]), corn[i % 2 + 1], M.SmoothPlastic, BALL)
	end
end

-- Crêpe roulée dans son cornet de papier, filet de chocolat
RECIPES.Crepe = function(add)
	add("Handle", Vector3.new(0.6, 0.5, 0.5), UPRIGHT, Color3.fromRGB(250, 244, 232), M.SmoothPlastic, CYL)
	local crepe = Color3.fromRGB(236, 196, 130)
	add("Roll", Vector3.new(0.5, 0.42, 0.42), CFrame.new(0, 0.5, 0) * UPRIGHT, crepe, M.SmoothPlastic, CYL)
	add("Bite3", Vector3.new(0.45, 0.4, 0.4), CFrame.new(0, 0.95, 0) * UPRIGHT, crepe, M.SmoothPlastic, CYL)
	add("Bite2", Vector3.new(0.4, 0.37, 0.37), CFrame.new(0, 1.37, 0) * UPRIGHT, Color3.fromRGB(230, 188, 120), M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, 1.66, 0), Color3.fromRGB(120, 76, 50), M.SmoothPlastic, BALL)
	add("Bite2", Vector3.new(0.44, 0.08, 0.08), CFrame.new(0, 1.2, -0.19) * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(110, 70, 46), M.SmoothPlastic)
end

-- Part de pizza (pointe en haut) : croûte, 3 bandes, pepperoni
RECIPES.PizzaSlice = function(add)
	add("Handle", Vector3.new(1.1, 0.22, 0.22), UPRIGHT * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(214, 150, 80), M.SmoothPlastic, CYL)
	local cheese = Color3.fromRGB(255, 206, 110)
	add("Slice", Vector3.new(0.95, 0.45, 0.08), CFrame.new(0, 0.33, 0), cheese, M.SmoothPlastic)
	add("Bite3", Vector3.new(0.72, 0.45, 0.08), CFrame.new(0, 0.78, 0), cheese, M.SmoothPlastic)
	add("Bite2", Vector3.new(0.48, 0.42, 0.08), CFrame.new(0, 1.2, 0), cheese, M.SmoothPlastic)
	add("Bite1", Vector3.new(0.24, 0.36, 0.08), CFrame.new(0, 1.58, 0), cheese, M.SmoothPlastic)
	local pep = Color3.fromRGB(196, 56, 50)
	add("Pepperoni", Vector3.new(0.05, 0.26, 0.26), CFrame.new(-0.2, 0.38, -0.05) * CFrame.Angles(0, math.rad(90), 0), pep, M.SmoothPlastic, CYL)
	add("Bite3", Vector3.new(0.05, 0.24, 0.24), CFrame.new(0.14, 0.8, -0.05) * CFrame.Angles(0, math.rad(90), 0), pep, M.SmoothPlastic, CYL)
	add("Bite2", Vector3.new(0.05, 0.2, 0.2), CFrame.new(-0.04, 1.22, -0.05) * CFrame.Angles(0, math.rad(90), 0), pep, M.SmoothPlastic, CYL)
end

-- Taco : coquille dorée (3 tronçons), salade, tomates
RECIPES.Taco = function(add)
	local shell = Color3.fromRGB(240, 196, 100)
	add("Handle", Vector3.new(0.45, 0.8, 0.8), CFrame.new(0, 0.2, 0), shell, M.SmoothPlastic, CYL)
	add("Bite2", Vector3.new(0.45, 0.8, 0.8), CFrame.new(0.44, 0.2, 0), shell, M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.4, 0.74, 0.74), CFrame.new(0.86, 0.2, 0), shell, M.SmoothPlastic, CYL)
	add("Bite3", Vector3.new(0.4, 0.74, 0.74), CFrame.new(-0.42, 0.2, 0), shell, M.SmoothPlastic, CYL)
	local lettuce = Color3.fromRGB(120, 200, 96)
	add("Lettuce", Vector3.new(0.5, 0.2, 0.5), CFrame.new(0, 0.64, 0), lettuce, M.Grass)
	add("Bite2", Vector3.new(0.45, 0.2, 0.5), CFrame.new(0.44, 0.64, 0), lettuce, M.Grass)
	add("Bite1", Vector3.new(0.4, 0.18, 0.46), CFrame.new(0.86, 0.62, 0), lettuce, M.Grass)
	add("Bite3", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-0.4, 0.66, -0.1), Color3.fromRGB(226, 60, 50), M.SmoothPlastic, BALL)
	add("Bite2", Vector3.new(0.18, 0.18, 0.18), CFrame.new(0.4, 0.7, 0.1), Color3.fromRGB(226, 60, 50), M.SmoothPlastic, BALL)
end

-- Milkshake : gobelet rose, chantilly, cerise, paille rayée
RECIPES.Milkshake = function(add)
	add("Handle", Vector3.new(1, 0.58, 0.58), UPRIGHT, Color3.fromRGB(255, 176, 206), M.SmoothPlastic, CYL)
	add("Lid", Vector3.new(0.08, 0.64, 0.64), CFrame.new(0, 0.52, 0) * UPRIGHT, Color3.fromRGB(255, 244, 250), M.SmoothPlastic, CYL)
	add("Bite2", Vector3.new(0.56, 0.4, 0.56), CFrame.new(0, 0.7, 0), Color3.fromRGB(255, 252, 248), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.4, 0.34, 0.4), CFrame.new(0, 0.92, 0), Color3.fromRGB(255, 252, 248), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.18, 0.18, 0.18), CFrame.new(0, 1.12, 0), Color3.fromRGB(226, 40, 70), M.SmoothPlastic, BALL)
	add("Bite3", Vector3.new(0.9, 0.08, 0.08), CFrame.new(0.14, 0.9, 0.05) * UPRIGHT * CFrame.Angles(0, 0, math.rad(0)) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(120, 196, 255), M.SmoothPlastic, CYL)
end

-- Hot dog : pain, saucisse, moutarde (tenu par le milieu, couché)
RECIPES.HotDog = function(add)
	local bun = Color3.fromRGB(236, 190, 120)
	local sausage = Color3.fromRGB(196, 86, 62)
	add("Handle", Vector3.new(0.5, 0.36, 0.52), CFrame.identity, bun, M.SmoothPlastic)
	add("Bite2", Vector3.new(0.45, 0.34, 0.5), CFrame.new(0.47, 0, 0), bun, M.SmoothPlastic)
	add("Bite1", Vector3.new(0.4, 0.32, 0.48), CFrame.new(0.89, 0, 0), bun, M.SmoothPlastic)
	add("Bite3", Vector3.new(0.4, 0.34, 0.5), CFrame.new(-0.45, 0, 0), bun, M.SmoothPlastic)
	add("Sausage", Vector3.new(1.5, 0.26, 0.26), CFrame.new(0.15, 0.22, 0), sausage, M.SmoothPlastic, CYL)
	add("Bite1", Vector3.new(0.3, 0.27, 0.27), CFrame.new(1.05, 0.22, 0), sausage, M.SmoothPlastic, CYL)
	add("Mustard", Vector3.new(1.3, 0.05, 0.08), CFrame.new(0.15, 0.36, 0), Color3.fromRGB(255, 214, 60), M.SmoothPlastic)
end

-- Pomme d'amour : bâton, pomme vernie rouge (2 parties), socle caramel
RECIPES.CandyApple = function(add)
	add("Handle", Vector3.new(0.8, 0.12, 0.12), UPRIGHT, Color3.fromRGB(214, 170, 120), M.Wood, CYL)
	add("Bite2", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 0.85, 0), Color3.fromRGB(214, 36, 56), M.SmoothPlastic, BALL)
	add("Bite1", Vector3.new(0.72, 0.72, 0.72), CFrame.new(0, 1.12, 0), Color3.fromRGB(226, 48, 64), M.SmoothPlastic, BALL)
	add("Caramel", Vector3.new(0.12, 0.78, 0.78), CFrame.new(0, 0.5, 0) * UPRIGHT, Color3.fromRGB(196, 120, 60), M.SmoothPlastic, CYL)
	add("Leaf", Vector3.new(0.2, 0.06, 0.12), CFrame.new(0.08, 1.46, 0) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(96, 170, 70), M.SmoothPlastic)
end

-- Beignet : anneau de 8 boules (glaçage rose), tenu par le bas
RECIPES.Donut = function(add)
	local dough = Color3.fromRGB(222, 164, 100)
	local glaze = Color3.fromRGB(255, 150, 196)
	add("Handle", Vector3.new(0.42, 0.42, 0.34), CFrame.identity, dough, M.SmoothPlastic, BALL)
	for k = 1, 7 do
		local a = k / 8 * math.pi * 2
		local p = CFrame.new(math.sin(a) * 0.42, 0.42 - math.cos(a) * 0.42, 0)
		local bite = if k <= 2 or k >= 6 then 2 else 1 -- le haut part d'abord
		add("Bite" .. bite, Vector3.new(0.42, 0.42, 0.34), p, dough, M.SmoothPlastic, BALL)
		add("Bite" .. bite, Vector3.new(0.36, 0.36, 0.12), p * CFrame.new(0, 0, -0.14), glaze, M.SmoothPlastic, BALL)
	end
	add("Sprinkle", Vector3.new(0.14, 0.04, 0.04), CFrame.new(0.3, 0.12, -0.2) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(120, 196, 255), M.SmoothPlastic)
end

-- Aliment id -> Model (ancré) ; `cf` = repère de la poignée ; `scale` (1)
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
	recipe(function(name, size, loc, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Size = size * s
		p.CFrame = base * CFrame.new(loc.Position * s) * loc.Rotation
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Parent = model
		if name == "Handle" then
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
