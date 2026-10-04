--[[
	ParkKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ParkKit

	🌳 Dopamine Town (v11, PARK11) : la petite BOÎTE À OUTILS des parcs,
	fontaines et terrains de sport (FountainKit, ParkSports, ParkScenes,
	DistrictParks, TownGreenery). Rien n'est placé dans le monde ici : des
	fabriques de pièces (toutes ancrées, sans requête ni contact, collision
	seulement si `solid`), un hasard déterministe et les cotes "à l'échelle
	Roblox" de SCALE11 (avatar 5,2 studs, ~x1,3 par rapport au réel) :
	  - banc / muret où l'on s'assoit : dessus à 1,85 ; profondeur ≥ 2 ;
	    2,6 par place ; dossier vers 3,8 ;
	  - table (pique-nique, ping-pong...) : 3,0 à 3,2 ;
	  - garde-corps ≥ 3,5.
	Aucune lumière, aucun son, aucun script.
]]

local ParkKit = {}

local M = Enum.Material
ParkKit.M = M
ParkKit.rgb = Color3.fromRGB
ParkKit.UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
ParkKit.TAU = math.pi * 2

-- Cotes SCALE11 (studs, dessus des surfaces)
ParkKit.SEAT = 1.85 -- assise d'un banc / d'un muret
ParkKit.SEAT_DEPTH = 2.1
ParkKit.PLACE = 2.6 -- largeur d'une place
ParkKit.BACK = 3.8 -- haut du dossier
ParkKit.TABLE = 3.1 -- table (pique-nique, ping-pong)
ParkKit.RAIL = 3.6 -- garde-corps, barrière

local created = 0

-- Hasard déterministe 0..1 (même formule que TownKit.Hash / CityKit.Hash)
function ParkKit.Hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

function ParkKit.Pick<T>(list: { T }, seed: number, salt: number?): T
	return list[1 + math.floor(ParkKit.Hash(seed, salt or 3) * #list) % #list]
end

local function finish(p: BasePart, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?, parent: Instance): BasePart
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = solid == true or size.Magnitude > 5
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	created += 1
	return p
end

-- Pièce : shape "Ball" | "Cyl" | nil (bloc)
function ParkKit.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	return finish(p, size, cf, color, material, solid, parent)
end

function ParkKit.Wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	return finish(p, size, cf, color, material, solid, parent)
end

-- Ellipsoïde (bloc + SpecialMesh Sphere : forme douce)
function ParkKit.Egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = ParkKit.Part(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

function ParkKit.Ball(parent: Instance, name: string, pos: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return ParkKit.Part(parent, name, Vector3.new(d, d, d), CFrame.new(pos), color, material, "Ball")
end

-- Boîte dans le repère F : x0..x1, y0..y1, z0..z1
function ParkKit.Box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return ParkKit.Part(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, nil, solid)
end

-- Cylindre debout (diamètre d) de y0 à y1, en (x, z) du repère F
function ParkKit.Column(parent: Instance, name: string, F: CFrame, x: number, z: number, y0: number, y1: number, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return ParkKit.Part(parent, name, Vector3.new(math.abs(y1 - y0), d, d), F * CFrame.new(x, (y0 + y1) / 2, z) * ParkKit.UPRIGHT, color, material, "Cyl", solid)
end

-- Repère d'un cylindre de a vers b (axe X le long de a -> b)
function ParkKit.RodCF(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	local dir = b - a
	if dir.Magnitude < 1e-4 then
		return CFrame.new(mid)
	end
	local up = math.abs(dir.Unit.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return CFrame.lookAt(mid, b, up) * CFrame.Angles(0, math.rad(90), 0)
end

function ParkKit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return ParkKit.Part(parent, name, Vector3.new((b - a).Magnitude, d, d), ParkKit.RodCF(a, b), color, material, "Cyl", solid)
end

-- Poutre (bloc) de a vers b, section w x h
function ParkKit.Beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local mid = (a + b) / 2
	return ParkKit.Part(parent, name, Vector3.new(w, h, (b - a).Magnitude), CFrame.lookAt(mid, b), color, material, nil, solid)
end

-- Disque horizontal : dessus à `top` (repère F), rayon r, épaisseur t
function ParkKit.Disc(parent: Instance, name: string, F: CFrame, x: number, z: number, top: number, r: number, t: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return ParkKit.Column(parent, name, F, x, z, top - t, top, r * 2, color, material, solid)
end

-- Anneau polygonal (n blocs jointifs) : rayon moyen r, largeur w, y0..y1
function ParkKit.Ring(parent: Instance, name: string, F: CFrame, r: number, w: number, y0: number, y1: number, n: number, color: Color3, material: Enum.Material?, solid: boolean?, a0: number?, a1: number?): { BasePart }
	local out = {}
	local from, to = a0 or 0, a1 or ParkKit.TAU
	local span = (to - from) / n
	-- (longueur d'un côté au rayon EXTÉRIEUR : pas de trou aux joints)
	local len = 2 * (r + w / 2) * math.tan(span / 2) + 0.02
	for i = 0, n - 1 do
		local a = from + (i + 0.5) * span
		-- (un pan sur deux 0,004 plus haut et plus bas : les coins qui se
		-- recouvrent n'ont jamais de face confondue)
		local e = (i % 2) * 0.004
		local p = F * CFrame.Angles(0, -a, 0) * CFrame.new(r, (y0 + y1) / 2, 0)
		table.insert(out, ParkKit.Part(parent, name, Vector3.new(w, y1 - y0 + 2 * e, len), p, color, material, nil, solid))
	end
	return out
end

-- Triangle plein (a, b, c) en 2 coins (WedgePart), épaisseur t : toits en
-- pavillon, voiles...
function ParkKit.Triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, t: number, color: Color3, material: Enum.Material?, solid: boolean?): { BasePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local out = {}
	local w1 = Instance.new("WedgePart")
	w1.Name = name
	finish(w1, Vector3.new(t, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back), color, material, solid, parent)
	table.insert(out, w1)
	local w2 = Instance.new("WedgePart")
	w2.Name = name
	finish(w2, Vector3.new(t, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back), color, material, solid, parent)
	table.insert(out, w2)
	return out
end

-- Texte sur une face (SurfaceGui), pour panneaux et enseignes
function ParkKit.Text(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?, pps: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 40
	gui.MaxDistance = maxDistance or 120
	gui.LightInfluence = 1
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or Color3.new(1, 1, 1)
	label.TextColor3 = color
	label.Font = font or Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	return label
end

function ParkKit.Created(): number
	return created
end

----------------------------------------------------------------------
-- Mobilier commun (échelle SCALE11)
----------------------------------------------------------------------

local IRON = Color3.fromRGB(44, 48, 52)
local WOOD = Color3.fromRGB(158, 110, 70)

-- Banc de parc : dessus de l'assise à SEAT (1,85), profondeur 2,1, dossier
-- jusqu'à 3,8 ; F = milieu du banc AU SOL, -Z = devant (où l'on regarde).
-- Pieds en fonte moulée, lattes de bois arrondies, accoudoirs.
-- Renvoie le repère de l'assise (dessus, milieu) pour y asseoir un PNJ.
function ParkKit.Bench(m: Instance, F: CFrame, len: number?, wood: Color3?, iron: Color3?): CFrame
	local L = len or 5.6
	local c = iron or IRON
	local w = wood or WOOD
	local S = ParkKit.SEAT
	for _, x in ipairs({ -L / 2 + 0.35, L / 2 - 0.35 }) do
		-- pied en "S" : jambe avant, jambe arrière, traverse, accoudoir
		ParkKit.Box(m, "BenchFoot", F, x - 0.13, x + 0.13, 0, 0.18, -1.05, 1.0, c, M.Metal, true)
		ParkKit.Rod(m, "BenchLegF", (F * CFrame.new(x, 0.1, -0.85)).Position, (F * CFrame.new(x, S - 0.2, -0.75)).Position, 0.24, c, M.Metal)
		ParkKit.Rod(m, "BenchLegB", (F * CFrame.new(x, 0.1, 0.85)).Position, (F * CFrame.new(x, ParkKit.BACK - 0.1, 1.0)).Position, 0.22, c, M.Metal)
		ParkKit.Box(m, "BenchRail", F, x - 0.1, x + 0.1, S - 0.36, S - 0.16, -0.95, 0.9, c, M.Metal)
		ParkKit.Rod(m, "BenchArmPost", (F * CFrame.new(x, S - 0.2, -0.8)).Position, (F * CFrame.new(x, S + 0.8, -0.85)).Position, 0.16, c, M.Metal)
		ParkKit.Box(m, "BenchArm", F, x - 0.14, x + 0.14, S + 0.74, S + 0.88, -1.0, 0.75, c, M.Metal)
	end
	-- 5 lattes d'assise (dessus exact à S) + 3 lattes de dossier inclinées
	for i = 0, 4 do
		local z0 = -1.05 + i * 0.42
		ParkKit.Box(m, "BenchSlat", F, -L / 2, L / 2, S - 0.16, S, z0, z0 + 0.36, w:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.05), M.Wood, i == 2)
	end
	for i = 0, 2 do
		local y = S + 0.55 + i * 0.5
		local z = 0.9 + i * 0.06
		ParkKit.Part(m, "BenchBack", Vector3.new(L, 0.36, 0.14), F * CFrame.new(0, y, z) * CFrame.Angles(math.rad(-10), 0, 0), w, M.Wood)
	end
	return F * CFrame.new(0, S, -0.1)
end

-- Poubelle de parc (corbeille ajourée sur poteau + couvercle)
function ParkKit.Bin(m: Instance, F: CFrame, color: Color3?)
	local c = color or Color3.fromRGB(40, 86, 66)
	ParkKit.Column(m, "BinPost", F, 0, 0.62, 0, 3.2, 0.24, IRON, M.Metal, true)
	ParkKit.Column(m, "BinBody", F, 0, 0, 0.9, 3.3, 1.5, c, M.Metal, true)
	ParkKit.Column(m, "BinBand", F, 0, 0, 2.9, 3.05, 1.56, c:Lerp(Color3.new(0, 0, 0), 0.25), M.Metal)
	ParkKit.Column(m, "BinLid", F, 0, 0, 3.3, 3.5, 1.62, IRON, M.Metal)
	ParkKit.Column(m, "BinBag", F, 0, 0, 3.3, 3.36, 1.3, Color3.fromRGB(30, 30, 34), M.Plastic)
end

-- Lampadaire de parc "style" (fût cannelé, lanterne vitrée qui s'allume la
-- nuit : verre "NightGlow", TownAtmosphere)
function ParkKit.Lamp(m: Instance, F: CFrame, h: number?, color: Color3?)
	local H = h or 11
	local c = color or Color3.fromRGB(34, 52, 46)
	ParkKit.Column(m, "LampBase", F, 0, 0, 0, 1.2, 1.2, c, M.Metal, true)
	ParkKit.Column(m, "LampPole", F, 0, 0, 1.1, H - 1.4, 0.36, c, M.Metal, true)
	ParkKit.Column(m, "LampRing", F, 0, 0, H - 1.5, H - 1.3, 0.8, c, M.Metal)
	local glass = ParkKit.Box(m, "LampGlass", F, -0.5, 0.5, H - 1.3, H, -0.5, 0.5, Color3.fromRGB(255, 236, 190), M.Glass)
	glass.Transparency = 0.15
	glass:SetAttribute("NightGlow", true)
	ParkKit.Wedge(m, "LampCap", Vector3.new(1.3, 0.6, 0.65), F * CFrame.new(0, H + 0.3, 0.325), c, M.Metal)
	ParkKit.Wedge(m, "LampCap", Vector3.new(1.3, 0.6, 0.65), F * CFrame.new(0, H + 0.3, -0.325) * CFrame.Angles(0, math.pi, 0), c, M.Metal)
	ParkKit.Ball(m, "LampFinial", (F * CFrame.new(0, H + 0.75, 0)).Position, 0.3, c, M.Metal)
end

----------------------------------------------------------------------
-- PNJ (NPCModels, chargé paresseusement) et animations propres aux parcs
----------------------------------------------------------------------

local npcModule: any = nil
function ParkKit.NPC(): any
	if npcModule == nil then
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		local mod = shared and shared:FindFirstChild("NPCModels")
		local ok, result = false, nil
		if mod and mod:IsA("ModuleScript") then
			ok, result = pcall(require, mod)
		end
		npcModule = (ok and type(result) == "table") and result or false
	end
	return npcModule or nil
end

-- Personnage posé (pivot = entre les pieds, regard -Z) ; nil sans NPCModels
function ParkKit.Person(m: Instance, style: string, seed: number, cf: CFrame, prop: string?, solid: boolean?): Model?
	local NPC = ParkKit.NPC()
	if not NPC then
		return nil
	end
	local ok, model = pcall(function()
		return NPC.Build(style, { Seed = seed, Prop = prop or "none", Solid = solid == true })
	end)
	if not ok or not model then
		return nil
	end
	model.Parent = m
	model:PivotTo(cf)
	return model
end

-- Assis sur une assise dont le DESSUS est en `seatCF` (regard -Z) : pivot
-- au sol sous les hanches (0,15 en arrière du centre du coussin, comme
-- NPCModels.Passenger), PNJ "assis" quelle que soit son anim (SetSeated)
function ParkKit.Sitter(m: Instance, style: string, seed: number, seatCF: CFrame, groundY: number, prop: string?): Model?
	local NPC = ParkKit.NPC()
	local h = seatCF.Position.Y - groundY
	local pivot = seatCF * CFrame.new(0, -h, 0.15)
	local model = ParkKit.Person(m, style, seed, pivot, prop, false)
	if model and NPC then
		pcall(function()
			if NPC.SetSeated then
				NPC.SetSeated(model, h)
			elseif NPC.SetSitHeight then
				NPC.SetSitHeight(model, h)
			end
		end)
	end
	return model
end

-- Anims "maison" (enregistrées si NPCModels.AddAnim existe, NPC11) ;
-- sinon repli sur les anims de base
local hasCustom = false
local FALLBACK: { [string]: string } = {}

function ParkKit.RegisterAnims(list: { [string]: { Fn: (P: any, t: number, seed: number) -> (), Fallback: string } })
	local NPC = ParkKit.NPC()
	for name, def in pairs(list) do
		FALLBACK[name] = def.Fallback
		if NPC and type(NPC.AddAnim) == "function" then
			local ok = pcall(NPC.AddAnim, name, def.Fn)
			if ok then
				hasCustom = true
			end
		end
	end
end

function ParkKit.HasCustomAnims(): boolean
	return hasCustom
end

-- Pose d'un PNJ : anim maison (ou son repli)
function ParkKit.Animate(model: Model?, anim: string, t: number, look: Vector3?)
	if not model then
		return
	end
	local NPC = ParkKit.NPC()
	if not NPC then
		return
	end
	local name = anim
	if not hasCustom and FALLBACK[anim] then
		name = FALLBACK[anim]
	end
	pcall(NPC.Animate, model, name, t, look)
end

-- Repère de la MAIN droite / gauche d'un PNJ posé : orientation de
-- l'avant-bras (pièce du groupe NpcG 6 / 4 qui n'est pas dans la main,
-- d'après sa pose de repos NpcRest), position au creux de la main
-- (NPCModels.HandPoint, NPC11) ; nil si inconnu
local HAND_REST = { R = Vector3.new(0.745, 2.36, 0.0), L = Vector3.new(-0.745, 2.36, 0.0) }
local handCache: { [Model]: { [string]: { Part: BasePart, Rest: CFrame } } } = setmetatable({}, { __mode = "k" }) :: any

function ParkKit.Hand(model: Model?, side: string): CFrame?
	if not model then
		return nil
	end
	local cache = handCache[model]
	if not cache then
		cache = {}
		handCache[model] = cache
	end
	local entry = cache[side]
	if not entry or not entry.Part.Parent then
		local want = side == "L" and 4 or 6
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") and d:GetAttribute("NpcG") == want and d:GetAttribute("NpcHand") == nil and typeof(d:GetAttribute("NpcRest")) == "CFrame" then
				entry = { Part = d, Rest = d:GetAttribute("NpcRest") :: CFrame }
				break
			end
		end
		if not entry then
			return nil
		end
		cache[side] = entry
	end
	local s = tonumber(model:GetAttribute("NpcScale")) or 1
	-- (repère du groupe = pièce * repos^-1 ; la main y est à sa place de repos)
	local group = entry.Part.CFrame * entry.Rest:Inverse()
	local cf = group * CFrame.new(HAND_REST[side == "L" and "L" or "R"] * s)
	local NPC = ParkKit.NPC()
	if NPC and type(NPC.HandPoint) == "function" then
		local ok, p = pcall(NPC.HandPoint, model, side == "L" and -1 or 1)
		if ok and typeof(p) == "Vector3" then
			cf = cf.Rotation + p
		end
	end
	return cf
end

return ParkKit
