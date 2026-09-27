--[[
	Tables (ModuleScript) — dessins des tables, sièges et meubles "à poser dessus" 🍽️🪑
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Tables
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).

	Les tables sont VIDES (le joueur y pose ce qu'il veut) : le dessus de
	chaque meuble est déclaré dans House/HouseSurfaces (mêmes coordonnées).
	Chaises "de profil" (DiningChair, RockingChair) : elles regardent à
	DROITE ; l'éditeur les retourne (miroir) pour les tourner vers une table.
]]

local Art = {}

----------------------------------------------------------------------
-- Petits outils partagés
----------------------------------------------------------------------

-- Pied tourné (fuseau arrondi) de (x, top) à (x, bottom)
local function turnedLeg(kit, parent, x, top, bottom, width, color, z)
	local leg = kit.Part(parent, x - width / 2, top, width, bottom - top, color, { Radius = math.floor(width / 2), Z = z or 1 })
	kit.Blob(parent, x, top + (bottom - top) * 0.35, width * 1.6, width * 1.3, kit.Lighten(color, 0.1), { Z = (z or 1) + 1, Thickness = 1.2 })
	return leg
end

-- Petit pied rond (patin)
local function foot(kit, parent, cx, y, w, color, z)
	return kit.Blob(parent, cx, y, w, w * 0.55, color, { Z = z or 1, Thickness = 1.2 })
end

-- Nappe festonnée devant un plateau : bande + petits arcs ; (x, y) = haut gauche
local function lace(kit, parent, x, y, w, h, color, z)
	local band = kit.Part(parent, x, y, w, h, color, { Radius = 3, Z = z, Shade = 0.08 })
	local count = math.max(3, math.floor(w / 9))
	local step = w / count
	for index = 0, count - 1 do
		kit.Circle(parent, x + step * (index + 0.5), y + h, step * 0.9, step * 0.7, color, 0, z)
	end
	return band
end

-- Tiroir avec poignée ronde
local function drawer(kit, parent, x, y, w, h, color, knob, z)
	local frame = kit.Part(parent, x, y, w, h, color, { Radius = 3, Z = z or 2, Thickness = 1.3 })
	kit.Blob(frame, w / 2, h / 2, math.min(8, w * 0.22), math.min(4.5, h * 0.36), knob, { Z = 2, Thickness = 1 })
	return frame
end

----------------------------------------------------------------------
-- Tables (dessus vides)
----------------------------------------------------------------------

-- Petite table d'appoint ronde : plateau crème bordé de rose, pied tulipe
Art.SideTable = function(body, kit, _item)
	local C = kit.C
	-- pied tulipe : 3 petites pattes + tige
	kit.Line(body, 50, 86, 30, 97, 5, C.WoodDark, 0, 1)
	kit.Line(body, 50, 86, 70, 97, 5, C.WoodDark, 0, 1)
	kit.Blob(body, 50, 94, 20, 9, C.Wood, { Z = 1, Thickness = 1.2 })
	local stem = kit.Part(body, 45, 44, 10, 50, C.Wood, { Radius = 5, Z = 2 })
	kit.Box(stem, 2.5, 4, 2, 42, C.White, 0.6, 2)
	kit.Blob(body, 50, 64, 18, 8, C.WoodLight, { Z = 3, Thickness = 1.2 })
	-- plateau (vu un peu de dessus) + chant
	kit.Part(body, 4, 38, 92, 11, kit.Darken(C.PinkSoft, 0.05), { Radius = -1, Z = 3 })
	local top = kit.Blob(body, 50, 38, 92, 16, C.Cream, { Z = 4, Shine = true })
	kit.Blob(top, 46, 8, 70, 8, C.White, { Z = 2, Outline = false, Shade = false, T = 0.5 })
	kit.Heart(body, 50, 44, 8, C.Pink, 0, 5)
	return nil
end

-- Table ronde de café : plateau marbre rose bordé d'or, pied en fer forgé
Art.CafeTable = function(body, kit, _item)
	local C = kit.C
	local metal = Color3.fromRGB(96, 84, 120)
	-- pied central + 3 pattes recourbées
	kit.Part(body, 46, 36, 8, 52, metal, { Radius = 4, Z = 1, Thickness = 1.2 })
	kit.Line(body, 50, 86, 22, 97, 5, metal, 0, 1)
	kit.Line(body, 50, 86, 78, 97, 5, metal, 0, 1)
	kit.Circle(body, 21, 96.5, 7, 5, metal, 0, 1)
	kit.Circle(body, 79, 96.5, 7, 5, metal, 0, 1)
	kit.Blob(body, 50, 60, 14, 7, C.Gold, { Z = 2, Thickness = 1 })
	-- volutes
	for _, side in ipairs({ -1, 1 }) do
		local curl = kit.Circle(body, 50 + side * 10, 46, 12, 12, metal, 1, 2)
		kit.Stroke(curl, metal, 2.2)
	end
	-- plateau
	kit.Part(body, 2, 30, 96, 10, C.Gold, { Radius = -1, Z = 3 })
	local top = kit.Blob(body, 50, 30, 96, 17, Color3.fromRGB(255, 228, 238), { Z = 4, Shine = true })
	kit.Line(top, 20, 6, 44, 11, 1.4, C.Pink, 0.55, 2) -- veines du marbre
	kit.Line(top, 58, 5, 80, 9, 1.2, C.Pink, 0.6, 2)
	return nil
end

-- Table basse : plateau bois clair, tablette basse, pieds boule
Art.CoffeeTable = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 12, 88 }) do
		kit.Part(body, x - 4, 58, 8, 36, C.WoodDark, { Radius = 3, Z = 1 })
		kit.Blob(body, x, 95, 12, 9, C.Wood, { Z = 2 })
	end
	-- tablette du bas (avec un joli motif)
	local shelf = kit.Part(body, 8, 76, 84, 8, C.Wood, { Radius = 3, Z = 2 })
	kit.Box(shelf, 3, 2, 78, 1.6, C.White, 0.6, 2)
	-- ceinture + plateau
	local apron = kit.Part(body, 6, 58, 88, 10, C.Wood, { Radius = 3, Z = 3 })
	for _, x in ipairs({ 22, 44, 66 }) do
		kit.Heart(apron, x, 5, 6, C.PinkSoft, 0, 2)
	end
	kit.Part(body, 1, 50, 98, 10, C.WoodLight, { Radius = 5, Z = 4, Shine = true })
	kit.Box(body, 6, 51.5, 60, 2, C.White, 0.5, 5)
	return nil
end

-- Grande table à manger : plateau bois, nappe festonnée, 4 pieds tournés
Art.DiningTable = function(body, kit, _item)
	local C = kit.C
	-- pieds du fond (plus sombres)
	for _, x in ipairs({ 16, 84 }) do
		kit.Part(body, x - 3, 42, 6, 50, kit.Darken(C.Wood, 0.2), { Radius = 3, Z = 1 })
	end
	-- pieds de devant
	for _, x in ipairs({ 8, 92 }) do
		turnedLeg(kit, body, x, 44, 97, 7, C.Wood, 3)
	end
	-- plateau
	kit.Part(body, 0, 34, 100, 10, C.WoodLight, { Radius = 4, Z = 5, Shine = true })
	kit.Box(body, 4, 35.5, 70, 2, C.White, 0.5, 6)
	-- nappe blanche festonnée (seulement devant, le dessus reste libre)
	lace(kit, body, 14, 42, 72, 9, C.White, 6)
	for _, x in ipairs({ 28, 50, 72 }) do
		kit.Heart(body, x, 47, 6, C.Pink, 0, 7)
	end
	return nil
end

-- Haute table de bar : petit plateau rond, long pied, repose-pieds
Art.BarTable = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(150, 222, 200)
	foot(kit, body, 50, 96, 44, C.GreyDark, 1)
	local stem = kit.Part(body, 45, 24, 10, 72, C.Grey, { Radius = 5, Z = 2 })
	kit.Box(stem, 2.5, 4, 2, 64, C.White, 0.5, 2)
	local ring = kit.Circle(body, 50, 70, 30, 9, C.White, 1, 3)
	kit.Stroke(ring, C.Gold, 2.4)
	kit.Part(body, 10, 16, 80, 9, kit.Darken(mint, 0.12), { Radius = -1, Z = 4 })
	local top = kit.Blob(body, 50, 16, 80, 14, mint, { Z = 5, Shine = true })
	kit.Blob(top, 40, 7, 50, 6, C.White, { Z = 2, Outline = false, Shade = false, T = 0.55 })
	return nil
end

-- Commode pastel : 2 x 3 tiroirs arc-en-ciel, dessus libre
Art.Dresser = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(226, 208, 250)
	for _, x in ipairs({ 12, 82 }) do
		kit.Part(body, x, 90, 6, 10, C.WoodDark, { Radius = 2, Z = 1 })
	end
	local cabinet = kit.Part(body, 6, 42, 88, 50, lilac, { Radius = 6, Z = 2 })
	local colors = { C.PinkSoft, C.MintSoft, kit.Lighten(C.Butter, 0.4) }
	for row = 0, 2 do
		for col = 0, 1 do
			drawer(kit, cabinet, 5 + col * 40, 5 + row * 14.5, 38, 12, colors[row + 1], C.Lilac, 2)
		end
	end
	kit.Part(body, 2, 36, 96, 8, kit.Lighten(lilac, 0.5), { Radius = 4, Z = 3, Shine = true })
	return nil
end

-- Meuble télé : console basse, niches (manette, disques), dessus libre
Art.TVStand = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(242, 212, 176)
	for _, x in ipairs({ 10, 86 }) do
		kit.Part(body, x - 3, 88, 6, 12, C.WoodDark, { Radius = 2, Z = 1, Rotation = x < 50 and 8 or -8 })
	end
	local cabinet = kit.Part(body, 3, 58, 94, 32, wood, { Radius = 6, Z = 2 })
	-- niche gauche : console de jeu ; niche droite : porte ronde
	local nook = kit.Part(cabinet, 5, 6, 40, 20, kit.Darken(wood, 0.35), { Radius = 4, Z = 2, Shade = false })
	local console = kit.Part(nook, 6, 9, 28, 8, C.White, { Radius = 3, Z = 2, Thickness = 1.2 })
	kit.Circle(console, 22, 4, 3, 3, C.Mint, 0, 2)
	kit.Box(console, 4, 3, 10, 2, C.GreyDark, 0.2, 2)
	for index, color in ipairs({ C.Pink, C.Sky, C.Butter }) do
		kit.Part(nook, 3 + index * 4.5, 1.5, 3.5, 7, color, { Radius = 1, Z = 2, Thickness = 1 })
	end
	local door = kit.Part(cabinet, 50, 6, 39, 20, kit.Lighten(wood, 0.3), { Radius = 4, Z = 2 })
	kit.Circle(door, 19.5, 10, 12, 12, C.PinkSoft, 0, 2)
	kit.Blob(door, 32, 10, 4, 4, C.Gold, { Z = 3, Thickness = 1 })
	kit.Part(body, 0, 52, 100, 8, kit.Lighten(wood, 0.35), { Radius = 4, Z = 3, Shine = true })
	return nil
end

-- Îlot de cuisine : placards menthe, plan de travail marbre qui dépasse
Art.KitchenIsland = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(176, 230, 210)
	kit.Part(body, 8, 94, 84, 6, kit.Darken(mint, 0.3), { Radius = 2, Z = 1, Shade = false }) -- socle
	local cabinet = kit.Part(body, 8, 44, 84, 52, mint, { Radius = 5, Z = 2 })
	-- tiroirs en haut, portes en bas
	for index = 0, 2 do
		drawer(kit, cabinet, 4 + index * 26.5, 4, 23, 10, kit.Lighten(mint, 0.45), C.Gold, 2)
		local door = kit.Part(cabinet, 4 + index * 26.5, 17, 23, 30, kit.Lighten(mint, 0.3), { Radius = 3, Z = 2, Thickness = 1.3 })
		kit.Part(door, 3, 3, 17, 24, kit.Lighten(mint, 0.5), { Radius = 2, Z = 2, Thickness = 1, Shade = false })
		kit.Blob(door, index == 1 and 5 or 18, 15, 3, 6, C.Gold, { Z = 3, Thickness = 1 })
	end
	-- plan de travail
	local top = kit.Part(body, 0, 36, 100, 10, Color3.fromRGB(252, 248, 255), { Radius = 4, Z = 3, Shine = true })
	kit.Line(top, 12, 6, 36, 4, 1.2, C.Lilac, 0.55, 2)
	kit.Line(top, 60, 5, 88, 7, 1.2, C.Lilac, 0.6, 2)
	return nil
end

-- Table de pique-nique : plateau à lattes, bancs attachés, nappe vichy
Art.PicnicTable = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(226, 176, 128)
	-- pieds en X
	for _, x in ipairs({ 20, 80 }) do
		kit.Line(body, x - 12, 98, x + 8, 44, 6, kit.Darken(wood, 0.2), 0, 1)
		kit.Line(body, x + 12, 98, x - 8, 44, 6, kit.Darken(wood, 0.12), 0, 2)
	end
	-- plateau (lattes) + nappe vichy sur le devant
	local top = kit.Part(body, 2, 38, 96, 10, wood, { Radius = 3, Z = 3, Shine = true })
	for _, x in ipairs({ 24, 48, 72 }) do
		kit.Box(top, x, 1, 1.5, 8, kit.Darken(wood, 0.3), 0.3, 2)
	end
	local cloth = kit.Part(body, 26, 42, 48, 12, C.White, { Radius = 2, Z = 4, Shade = 0.06 })
	for index = 0, 5 do
		kit.Box(cloth, 2 + index * 8, 0, 4, 12, C.Red, 0.55, 2)
	end
	for index = 0, 2 do
		kit.Box(cloth, 0, 1 + index * 4, 48, 2, C.Red, 0.6, 2)
	end
	-- banc de devant
	local bench = kit.Part(body, 0, 70, 100, 9, kit.Lighten(wood, 0.12), { Radius = 3, Z = 5, Shine = true })
	kit.Box(bench, 49, 1, 1.5, 7, kit.Darken(wood, 0.3), 0.3, 2)
	for _, x in ipairs({ 10, 90 }) do
		kit.Part(body, x - 3, 78, 6, 20, kit.Darken(wood, 0.08), { Radius = 2, Z = 4 })
	end
	return nil
end

-- Grand bureau en bois : 2 caissons à tiroirs, sous-main vert, dessus libre
Art.BigDesk = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(196, 140, 100)
	local light = kit.Lighten(wood, 0.25)
	kit.Part(body, 30, 46, 40, 34, kit.Darken(wood, 0.3), { Radius = 3, Z = 1, Shade = false }) -- fond
	for _, x in ipairs({ 4, 68 }) do
		local pedestal = kit.Part(body, x, 44, 28, 52, wood, { Radius = 4, Z = 2 })
		for row = 0, 2 do
			drawer(kit, pedestal, 3, 3 + row * 16, 22, 13, light, C.Gold, 2)
		end
		kit.Part(body, x + 1, 95, 26, 5, kit.Darken(wood, 0.25), { Radius = 2, Z = 1 })
	end
	local middle = kit.Part(body, 32, 44, 36, 10, light, { Radius = 3, Z = 2 })
	kit.Blob(middle, 18, 5, 8, 4, C.Gold, { Z = 2, Thickness = 1 })
	-- plateau + sous-main
	kit.Part(body, 0, 36, 100, 10, kit.Lighten(wood, 0.35), { Radius = 4, Z = 3, Shine = true })
	kit.Part(body, 30, 37.5, 40, 3, Color3.fromRGB(120, 190, 140), { Radius = 1.5, Z = 4, Outline = false, Shade = false })
	return nil
end

----------------------------------------------------------------------
-- Sièges
----------------------------------------------------------------------

-- Tabouret champignon : chapeau rouge à pois, pied crème
Art.MushroomStool = function(body, kit, _item)
	local C = kit.C
	local stem = kit.Part(body, 32, 36, 36, 62, C.Cream, { Radius = 14, Z = 1, Shade = 0.14 })
	kit.Face(stem, 18, 30, 22, { Eyes = "happy", Mouth = "cat", Z = 3 })
	kit.Blob(body, 50, 97, 44, 8, kit.Darken(C.Cream, 0.1), { Z = 0, Outline = false, Shade = false })
	local cap = kit.Part(body, 6, 12, 88, 34, C.Red, { Radius = -1, Z = 2, Shine = true })
	for _, dot in ipairs({ { 20, 10, 10 }, { 44, 7, 13 }, { 68, 12, 10 }, { 32, 22, 7 }, { 58, 24, 7 } }) do
		kit.Circle(cap, dot[1], dot[2], dot[3], dot[3] * 0.8, C.White, 0, 2)
	end
	kit.Part(body, 12, 34, 76, 8, kit.Darken(C.Red, 0.25), { Radius = -1, Z = 1, Outline = false })
	return nil
end

-- Deux gros coussins de sol empilés (façon dango : rose, crème, menthe)
Art.FloorCushion = function(body, kit, _item)
	local C = kit.C
	local low = kit.Part(body, 4, 70, 92, 28, C.MintSoft, { Radius = 13, Z = 1, Shade = 0.16 })
	kit.Circle(low, 46, 14, 5, 5, kit.Darken(C.Mint, 0.1), 0.2, 2)
	local high = kit.Part(body, 12, 46, 76, 28, C.PinkSoft, { Radius = 13, Z = 2, Shade = 0.16, Shine = true })
	kit.Circle(high, 38, 14, 5, 5, C.Pink, 0.2, 2)
	for _, x in ipairs({ 12, 64 }) do
		kit.Line(high, x, 6, x, 22, 1.5, C.Pink, 0.55, 2) -- coutures
	end
	kit.Face(high, 38, 15, 18, { Eyes = "happy", Mouth = "smile", Z = 3 })
	-- pompons aux coins
	for _, x in ipairs({ 10, 90 }) do
		kit.Blob(body, x, 50, 8, 8, C.Butter, { Z = 3, Thickness = 1.2 })
	end
	return nil
end

-- Chaise de salle à manger DE PROFIL (regarde à droite) : dossier à cœur, galette rose
Art.DiningChair = function(body, kit, _item)
	local C = kit.C
	local wood = C.Wood
	-- pieds (arrière-plan plus sombre)
	kit.Part(body, 30, 60, 6, 38, kit.Darken(wood, 0.2), { Radius = 3, Z = 1, Rotation = -4 })
	kit.Part(body, 72, 60, 6, 38, kit.Darken(wood, 0.2), { Radius = 3, Z = 1, Rotation = 4 })
	kit.Part(body, 24, 60, 7, 40, wood, { Radius = 3, Z = 3, Rotation = -6 })
	kit.Part(body, 76, 60, 7, 40, wood, { Radius = 3, Z = 3, Rotation = 6 })
	kit.Part(body, 28, 84, 50, 4, kit.Darken(wood, 0.1), { Radius = 2, Z = 2 }) -- barreau
	-- dossier (à gauche, un peu penché)
	local back = kit.Part(body, 18, 4, 14, 60, wood, { Radius = 6, Z = 4, Rotation = -6, Shine = true })
	kit.Heart(back, 7, 16, 9, C.Pink, 0, 2)
	-- assise + galette
	kit.Part(body, 20, 58, 64, 9, C.WoodLight, { Radius = 4, Z = 4 })
	local cushion = kit.Part(body, 28, 50, 56, 11, C.PinkSoft, { Radius = -1, Z = 5, Shine = true })
	for _, x in ipairs({ 14, 28, 42 }) do
		kit.Circle(cushion, x, 5.5, 2, 2, C.Pink, 0.2, 2)
	end
	return nil
end

-- Tabouret de bar : assise ronde matelassée, pieds hauts, repose-pieds doré
Art.BarStool = function(body, kit, _item)
	local C = kit.C
	local metal = Color3.fromRGB(150, 146, 172)
	kit.Line(body, 44, 36, 30, 98, 4, kit.Darken(metal, 0.15), 0, 1)
	kit.Line(body, 56, 36, 70, 98, 4, kit.Darken(metal, 0.15), 0, 1)
	kit.Line(body, 40, 36, 20, 98, 5, metal, 0, 2)
	kit.Line(body, 60, 36, 80, 98, 5, metal, 0, 2)
	local ring = kit.Circle(body, 50, 72, 44, 10, C.White, 1, 3)
	kit.Stroke(ring, C.Gold, 3)
	kit.Part(body, 22, 34, 56, 8, kit.Darken(C.Sky, 0.2), { Radius = -1, Z = 3 })
	local seat = kit.Blob(body, 50, 30, 60, 18, C.Sky, { Z = 4, Shine = true })
	kit.Circle(seat, 30, 9, 4, 4, kit.Darken(C.Sky, 0.25), 0.2, 2)
	return nil
end

-- Fauteuil douillet (de face) : dossier arrondi, accoudoirs, plaid
Art.Armchair = function(body, kit, _item)
	local C = kit.C
	local peach = Color3.fromRGB(255, 196, 170)
	for _, x in ipairs({ 16, 78 }) do
		kit.Part(body, x, 88, 6, 12, C.WoodDark, { Radius = 2, Z = 1, Rotation = x < 50 and 10 or -10 })
	end
	local back = kit.Part(body, 14, 16, 72, 52, peach, { Radius = 26, Z = 2 })
	for _, x in ipairs({ 26, 46 }) do
		kit.Circle(back, x, 24, 3.5, 3.5, kit.OutlineOf(peach), 0.3, 2) -- capitonnage
	end
	local seat = kit.Part(body, 12, 60, 76, 30, peach, { Radius = 12, Z = 3, Shade = 0.18 })
	kit.Part(seat, 8, 2, 60, 12, kit.Lighten(peach, 0.35), { Radius = -1, Z = 2, Shine = true }) -- coussin
	for _, x in ipairs({ 2, 76 }) do
		kit.Part(body, x, 44, 22, 46, kit.Darken(peach, 0.05), { Radius = 11, Z = 4, Shine = true })
	end
	-- plaid à carreaux sur l'accoudoir droit
	local throw = kit.Part(body, 70, 40, 20, 34, C.LilacSoft, { Radius = 5, Z = 5, Rotation = 6 })
	kit.Box(throw, 0, 10, 20, 3, C.Lilac, 0.3, 2)
	kit.Box(throw, 0, 22, 20, 3, C.Lilac, 0.3, 2)
	kit.Box(throw, 8, 0, 3, 34, C.Lilac, 0.4, 2)
	return nil
end

-- Banc de jardin : lattes de bois, accoudoirs en fer forgé
Art.GardenBench = function(body, kit, _item)
	local C = kit.C
	local iron = Color3.fromRGB(90, 110, 100)
	local wood = Color3.fromRGB(226, 180, 130)
	-- dossier (3 lattes)
	for index = 0, 2 do
		kit.Part(body, 10, 22 + index * 10, 80, 7, kit.Darken(wood, 0.05 * index), { Radius = 3, Z = 2, Shine = index == 0 })
	end
	-- assise (2 lattes)
	kit.Part(body, 6, 58, 88, 7, wood, { Radius = 3, Z = 3, Shine = true })
	kit.Part(body, 6, 64, 88, 7, kit.Darken(wood, 0.1), { Radius = 3, Z = 3 })
	-- flancs en fer forgé (volutes)
	for _, x in ipairs({ 8, 92 }) do
		kit.Part(body, x - 3, 18, 6, 80, iron, { Radius = 3, Z = 4 })
		local curl = kit.Circle(body, x + (x < 50 and 7 or -7), 50, 14, 14, iron, 1, 4)
		kit.Stroke(curl, iron, 2.6)
		kit.Blob(body, x, 97, 12, 6, iron, { Z = 4, Thickness = 1 })
	end
	-- petite fleur posée sur le dossier
	kit.Circle(body, 70, 20, 8, 8, C.Pink, 0, 5)
	kit.Circle(body, 70, 20, 3.5, 3.5, C.Butter, 0, 6)
	return nil
end

-- Rocking-chair DE PROFIL (regarde à droite) : patins courbes, plaid tricoté
Art.RockingChair = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(200, 146, 104)
	-- patin courbe (arc fait de 3 segments)
	kit.Line(body, 8, 88, 30, 96, 5, kit.Darken(wood, 0.1), 0, 1)
	kit.Line(body, 30, 96, 70, 96, 5, kit.Darken(wood, 0.1), 0, 1)
	kit.Line(body, 70, 96, 94, 86, 5, kit.Darken(wood, 0.1), 0, 1)
	-- pieds
	kit.Line(body, 28, 60, 30, 95, 5, wood, 0, 2)
	kit.Line(body, 72, 60, 70, 95, 5, wood, 0, 2)
	-- dossier (penché vers l'arrière, à gauche) avec barreaux
	local back = kit.Group(body, 10, 2, 30, 64, 3)
	back.Rotation = -12
	kit.Part(back, 2, 0, 8, 62, wood, { Radius = 4, Z = 1 })
	kit.Part(back, 18, 4, 8, 58, wood, { Radius = 4, Z = 1 })
	for _, y in ipairs({ 12, 26, 40 }) do
		kit.Part(back, 4, y, 20, 5, kit.Lighten(wood, 0.2), { Radius = 2, Z = 2 })
	end
	-- assise
	kit.Part(body, 22, 56, 60, 8, kit.Lighten(wood, 0.15), { Radius = 4, Z = 4, Shine = true })
	-- accoudoir
	kit.Line(body, 34, 40, 78, 44, 5, wood, 0, 5)
	kit.Line(body, 74, 44, 74, 58, 4, wood, 0, 5)
	-- plaid tricoté qui pend
	local throw = kit.Part(body, 16, 30, 30, 34, C.PinkSoft, { Radius = 6, Z = 6, Rotation = -8, Shine = true })
	for _, y in ipairs({ 9, 18, 27 }) do
		kit.Box(throw, 2, y, 26, 2, C.Pink, 0.35, 2)
	end
	-- pelote de laine au pied
	local ball = kit.Blob(body, 86, 92, 14, 13, C.Lilac, { Z = 6, Shine = true })
	kit.Line(ball, 3, 4, 11, 9, 1.2, C.White, 0.4, 2)
	kit.Line(body, 80, 94, 70, 99, 1.2, C.Lilac, 0, 5)
	return nil
end

-- Grand lit douillet (de face) : tête de lit cœur, couette, dessus libre pour
-- les coussins et les animaux
Art.DoubleBed = function(body, kit, _item)
	local C = kit.C
	local frameColor = Color3.fromRGB(255, 236, 226)
	-- tête de lit
	local head = kit.Part(body, 6, 10, 88, 60, frameColor, { Radius = 30, Z = 1, Shade = 0.12 })
	kit.Heart(head, 44, 24, 26, C.PinkSoft, 0, 2)
	kit.Heart(head, 44, 24, 14, C.Pink, 0, 3)
	for _, x in ipairs({ 0, 90 }) do
		local post = kit.Part(body, x, 26, 10, 72, kit.Darken(frameColor, 0.05), { Radius = 5, Z = 2 })
		kit.Blob(body, x + 5, 25, 14, 14, C.PinkSoft, { Z = 3, Shine = true })
		kit.Box(post, 3, 4, 2, 60, C.White, 0.5, 2)
	end
	-- matelas + couette
	kit.Part(body, 8, 52, 84, 14, C.White, { Radius = 6, Z = 3 })
	local duvet = kit.Part(body, 6, 58, 88, 32, Color3.fromRGB(196, 222, 255), { Radius = 10, Z = 4, Shine = true })
	for _, x in ipairs({ 18, 42, 66 }) do
		kit.Circle(duvet, x, 17, 8, 8, C.White, 0.35, 2) -- pois
	end
	kit.Part(body, 6, 56, 88, 8, C.White, { Radius = -1, Z = 5 }) -- revers du drap
	kit.Part(body, 10, 88, 80, 8, kit.Darken(frameColor, 0.08), { Radius = 3, Z = 5 }) -- cadre du pied
	return nil
end

-- Fauteuil-œuf suspendu : arceau, chaîne, coque en rotin, coussin
Art.EggChair = function(body, kit, _item)
	local C = kit.C
	local metal = Color3.fromRGB(236, 206, 150)
	-- arceau
	kit.Blob(body, 50, 96, 60, 8, kit.Darken(metal, 0.2), { Z = 1, Thickness = 1.2 })
	kit.Line(body, 26, 94, 32, 30, 5, metal, 0, 1)
	kit.Line(body, 32, 30, 56, 4, 5, metal, 0, 1)
	kit.Line(body, 56, 4, 66, 10, 5, metal, 0, 1)
	-- chaîne
	local chain = kit.Pivot(body, 64, 10, 2)
	for index = 0, 3 do
		local link = kit.Circle(chain, 0, 3 + index * 5, 4, 6, C.White, 1, 1)
		kit.Stroke(link, kit.Darken(metal, 0.3), 1.6)
	end
	-- coque (se balance doucement)
	local swing = kit.Pivot(body, 64, 30, 3)
	local shell = kit.Part(swing, -28, 0, 56, 68, Color3.fromRGB(240, 214, 176), { Radius = 26, Z = 1, Shade = 0.18 })
	for _, y in ipairs({ 14, 28, 42, 56 }) do
		kit.Box(shell, 4, y, 48, 1.6, kit.Darken(metal, 0.3), 0.5, 2) -- tressage
	end
	local inside = kit.Part(swing, -20, 10, 40, 44, Color3.fromRGB(180, 140, 110), { Radius = 20, Z = 2, Shade = false })
	kit.Part(inside, 4, 20, 32, 20, C.PinkSoft, { Radius = 10, Z = 2, Shine = true }) -- coussin
	kit.Heart(inside, 20, 29, 8, C.Pink, 0, 3)
	kit.Animate(swing, "Sway", 2.2, 0.35, 0)
	return nil
end

----------------------------------------------------------------------
-- Étagère murale (on pose des petits objets sur ses 2 planches)
----------------------------------------------------------------------

Art.FloatingShelf = function(body, kit, _item)
	local C = kit.C
	local wood = C.WoodLight
	for _, y in ipairs({ 34, 72 }) do
		-- consoles
		for _, x in ipairs({ 18, 82 }) do
			local bracket = kit.Part(body, x - 3, y + 3, 6, 12, kit.Darken(wood, 0.25), { Radius = 2, Z = 1 })
			kit.Stroke(bracket, kit.Darken(wood, 0.45), 1.2)
		end
		kit.Part(body, 4, y, 92, 7, wood, { Radius = 3, Z = 2, Shine = true })
		kit.Box(body, 8, y + 5, 84, 1.5, kit.Darken(wood, 0.25), 0.2, 3)
	end
	-- petites guirlandes de cœurs entre les planches
	for index = 0, 4 do
		kit.Heart(body, 20 + index * 15, 52 + (index % 2) * 3, 5, index % 2 == 0 and C.Pink or C.Lilac, 0.1, 1)
	end
	return { WallShadow = Vector2.new(0.9, 0.5) }
end

return Art
