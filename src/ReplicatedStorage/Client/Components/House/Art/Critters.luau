--[[
	Critters (ModuleScript) — nouveaux animaux 🐾 (v9) : chaton calico, hérisson
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Critters
	Contrat : voir HouseArt et Art/Pets : les parties "animal" sont dans des
	groupes dont le nom commence par "Pet" (le reste = sa maison : coussin,
	tas de feuilles) ; "PetWalk" (caché) = pose debout pour marcher.
	Petits : on peut les poser sur le lit, le canapé, une chaise... (ils y
	font la sieste, sautent en bas, se promènent et y reviennent).
]]

local Art = {}

-- Conteneur qui respire : UIScale autour du bas-centre (les pattes restent au sol)
local function breather(parent, kit, x, y, w, h, z)
	local g = kit.Group(parent, x, y, w, h, z)
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Position = UDim2.fromOffset(x + w / 2, y + h)
	return g
end

-- Oreille pointue (carré arrondi tourné) avec intérieur rose
local function ear(parent, kit, cx, cy, size, color, inner, tilt, z)
	local frame = kit.Part(parent, cx - size / 2, cy - size / 2, size, size, color, {
		Radius = size * 0.24,
		Rotation = 45 + tilt,
		Z = z,
		Shade = false,
	})
	kit.Part(frame, size * 0.2, size * 0.2, size * 0.46, size * 0.46, inner, {
		Radius = size * 0.14,
		Z = 2,
		Outline = false,
		Shade = false,
	})
	return frame
end

-- Chaton calico roulé en boule sur son coussin cœur (se réveille pour se promener)
Art.Kitten = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 250, 246)
	local orange = Color3.fromRGB(255, 176, 108)
	local dark = Color3.fromRGB(120, 96, 110)
	-- coussin cœur (sa maison)
	kit.Heart(body, 50, 74, 64, kit.Darken(C.Pink, 0.12), 0, 1)
	kit.Blob(body, 50, 86, 92, 24, C.PinkSoft, { Z = 2, Shine = true })
	for index = 0, 4 do
		kit.Circle(body, 18 + index * 16, 97, 8, 5, C.White, 0.1, 2)
	end
	-- chaton endormi
	local cat = breather(body, kit, 0, 0, 100, 84, 3)
	cat.Name = "Pet"
	kit.Blob(cat, 58, 66, 56, 30, fur, { Z = 2, Shine = true })
	kit.Blob(cat, 66, 60, 20, 14, orange, { Z = 3, Outline = false, Shade = false })
	kit.Blob(cat, 50, 72, 14, 9, dark, { Z = 3, Outline = false, Shade = false })
	ear(cat, kit, 22, 50, 12, fur, C.Pink, -22, 1)
	ear(cat, kit, 40, 47, 12, orange, C.Pink, 10, 1)
	local head = kit.Blob(cat, 32, 63, 34, 28, fur, { Z = 4, Shine = true })
	kit.Blob(head, 24, 7, 12, 9, orange, { Z = 2, Outline = false, Shade = false })
	kit.Blob(head, 7, 9, 9, 7, dark, { Z = 2, Outline = false, Shade = false })
	kit.Face(cat, 32, 65, 22, { Eyes = "closed", Mouth = "cat", Z = 6 })
	kit.Animate(cat, "Breathe", 0.035, 0.6, 0.4)
	-- pattes et queue devant le coussin
	local front = kit.Group(body, 0, 0, 100, 100, 7)
	front.Name = "PetFront"
	for _, x in ipairs({ 30, 41 }) do
		kit.Blob(front, x, 76, 9, 6, C.White, { Z = 2, Thickness = 1.2 })
	end
	local tail = kit.Pivot(front, 84, 72, 2)
	tail.Name = "Tail"
	kit.Blob(tail, 2, 8, 8, 20, orange, { Rotation = -14, Thickness = 1.4 })
	kit.Animate(tail, "Sway", 6, 0.5, 1.1)
	local zzz = kit.Text(front, "z", 64, 36, 12, C.Lilac, 3)
	kit.Animate(zzz, "Bob", 2, 0.6, 0.3)
	-- pose debout (cachée) tournée vers la droite
	local walk = kit.Group(body, 0, 0, 100, 100, 9)
	walk.Name = "PetWalk"
	walk.Visible = false
	local wtail = kit.Pivot(walk, 30, 70, 1)
	kit.Blob(wtail, -5, -13, 8, 28, orange, { Rotation = -20, Thickness = 1.4 })
	kit.Animate(wtail, "Sway", 10, 1, 0.2)
	for index, x in ipairs({ 36, 45, 60, 69 }) do
		local leg = kit.Part(walk, x - 4.5, 82, 9, 16, index == 2 and orange or fur, { Radius = 4, Z = 1, Thickness = 1.3 })
		kit.Blob(leg, 4.5, 14, 10, 5, C.White, { Z = 2, Thickness = 1, Shade = false })
	end
	kit.Blob(walk, 52, 76, 48, 26, fur, { Z = 2, Shine = true })
	kit.Blob(walk, 44, 70, 16, 12, orange, { Z = 3, Outline = false, Shade = false })
	kit.Blob(walk, 58, 82, 12, 8, dark, { Z = 3, Outline = false, Shade = false })
	ear(walk, kit, 64, 46, 12, fur, C.Pink, -16, 3)
	ear(walk, kit, 84, 47, 12, orange, C.Pink, 18, 3)
	local whead = kit.Blob(walk, 74, 60, 32, 28, fur, { Z = 4, Shine = true })
	kit.Blob(whead, 24, 8, 12, 9, orange, { Z = 2, Outline = false, Shade = false })
	kit.Face(walk, 76, 62, 22, { Mouth = "cat", Z = 6 })
	kit.Animate(walk, "Breathe", 0.02, 1.2, 0.2)
	return nil
end

-- Hérisson sur son petit tas de feuilles (il trottine, renifle, mange)
Art.Hedgehog = function(root, kit, _item)
	local C = kit.C
	-- tas de feuilles (sa maison)
	for index, leaf in ipairs({ { 22, 92, -24, C.Orange }, { 44, 94, 8, C.Butter }, { 66, 92, 26, C.Red }, { 80, 95, -10, C.Leaf } }) do
		kit.Blob(root, leaf[1], leaf[2], 26, 11, leaf[4], { Z = 1, Rotation = leaf[3], Thickness = 1.2 })
		kit.Line(root, leaf[1] - 8, leaf[2], leaf[1] + 8, leaf[2], 1.2, kit.Darken(leaf[4], 0.3), 0.3, 2)
		if index == 2 then
			kit.Circle(root, 60, 86, 9, 9, C.Red, 0, 3) -- petite pomme
		end
	end
	local body = kit.Group(root, 0, 0, 100, 100, 3)
	body.Name = "Pet"
	local spines = Color3.fromRGB(150, 110, 86)
	local cream = Color3.fromRGB(255, 232, 206)
	local hog = breather(body, kit, 0, 0, 100, 96, 1)
	-- piquants (losanges en couronne)
	for index = 0, 9 do
		local a = math.pi * (0.1 + index * 0.09)
		local x = 58 - math.cos(a) * 30
		local y = 70 - math.sin(a) * 30
		kit.Diamond(hog, x, y, 14, index % 2 == 0 and spines or kit.Darken(spines, 0.15), 0, 1)
	end
	kit.Blob(hog, 58, 70, 60, 44, spines, { Z = 2, Shine = true })
	-- visage (tourné vers la gauche)
	local face = kit.Blob(hog, 34, 72, 38, 32, cream, { Z = 3, Shine = true })
	kit.Blob(hog, 16, 76, 12, 9, cream, { Z = 4, Thickness = 1.2 }) -- museau
	kit.Circle(hog, 11, 75, 6, 5, C.Ink, 0, 5) -- truffe
	kit.Circle(face, 17, 12, 5, 6, C.Ink, 0, 3)
	kit.Circle(face, 16, 10.5, 2, 2, C.White, 0, 4)
	kit.Circle(face, 22, 20, 8, 5, C.Blush, 0.35, 3)
	ear(hog, kit, 44, 56, 10, cream, C.PinkSoft, 0, 2)
	for _, x in ipairs({ 36, 64 }) do
		kit.Blob(hog, x, 94, 11, 7, cream, { Z = 4, Thickness = 1.2 })
	end
	kit.Animate(hog, "Breathe", 0.03, 1, 0.8)
	return nil
end

return Art
