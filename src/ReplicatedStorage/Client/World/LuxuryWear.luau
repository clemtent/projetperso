--[[
	LuxuryWear (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > LuxuryWear

	💎 Objets de LUXE portés en ville (v11, BANK11), dessinés par CHAQUE
	client sur TOUS les personnages proches d'après leurs attributs (posés
	par le serveur, BankService) : "LuxHead", "LuxFace", "LuxNeck",
	"LuxWrist", "LuxBack", "LuxAura" (= Id de Config.Bank.Luxury) et
	"LuxTitle" (texte du titre). Pièces soudées au corps (Weld), sans masse,
	sans collision ; R15 et R6. Animés de près : cape qui ondule, ailes qui
	battent doucement, diamants de l'aura qui tournent, halo qui flotte.
	Aucune lumière, aucun son.

	API : LuxuryWear.Step(dt) (BankClient) ; LuxuryWear.Clear() ;
	      LuxuryWear.Build(character, slot, id) -> Model? (tests / aperçu)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local LuxuryWear = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local GOLD = rgb(236, 188, 70)
local GOLD_DEEP = rgb(190, 140, 44)
local DIAMOND = rgb(176, 236, 255)
local VELVET = rgb(150, 22, 44)
local ERMINE = rgb(248, 246, 240)
local BLACK = rgb(24, 22, 30)
local GLASS = rgb(150, 200, 230)

local SLOTS = { "Head", "Face", "Neck", "Wrist", "Back", "Aura" }
local RANGE = 160 -- (studs) au-delà : rien n'est dessiné
local ANIM_RANGE = 90

type Worn = { Model: Model, Id: string, Anim: ((t: number) -> ())? }
type Entry = { Slots: { [string]: Worn }, Title: BillboardGui?, TitleText: string? }

local worn: { [Model]: Entry } = {}
local clock = 0

----------------------------------------------------------------------
-- Pièces soudées
----------------------------------------------------------------------

local function bodyPart(character: Model, names: { string }): BasePart?
	for _, n in ipairs(names) do
		local p = character:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- Pièce soudée à `host` avec l'offset `c0` (repère de host)
local function piece(m: Model, host: BasePart, name: string, size: Vector3, c0: CFrame, color: Color3, material: Enum.Material?, shape: string?): (BasePart, Weld)
	local p = Instance.new("Part")
	p.Name = name
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = host.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = host
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	p.Parent = m
	return p, w
end

local function gem(m: Model, host: BasePart, name: string, d: number, c0: CFrame): (BasePart, Weld)
	local p, w = piece(m, host, name, Vector3.new(d, d, d), c0 * CFrame.Angles(math.rad(45), math.rad(45), 0), DIAMOND, M.Glass)
	p.Transparency = 0.1
	p.Reflectance = 0.2
	return p, w
end

----------------------------------------------------------------------
-- Les objets
----------------------------------------------------------------------

local BUILDERS: { [string]: (m: Model, character: Model) -> ((t: number) -> ())? } = {}

-- (R15 : la tête ~1,2 ; on suit sa taille réelle)
local function headInfo(character: Model): (BasePart?, number, number)
	local head = bodyPart(character, { "Head" })
	if not head then
		return nil, 1, 1
	end
	return head, head.Size.Y, head.Size.X
end

BUILDERS.DiamondCrown = function(m, character)
	local head, hy, hx = headInfo(character)
	if not head then
		return nil
	end
	local top = hy / 2 + 0.12
	local r = hx * 0.42
	piece(m, head, "CrownCap", Vector3.new(r * 1.7, 0.28, r * 1.7), CFrame.new(0, top + 0.12, 0), VELVET, M.Fabric, "Ball")
	piece(m, head, "CrownBand", Vector3.new(0.34, r * 2.1, r * 2.1), CFrame.new(0, top, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Metal, "Cyl")
	for k = 0, 7 do
		local a = k * math.pi / 4
		local c = CFrame.new(math.cos(a) * r, top + 0.36, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
		piece(m, head, "CrownPoint", Vector3.new(0.08, 0.42, 0.22), c * CFrame.Angles(0, 0, 0), GOLD, M.Metal)
		piece(m, head, "CrownTip", Vector3.new(0.14, 0.14, 0.14), CFrame.new(math.cos(a) * r, top + 0.6, math.sin(a) * r), GOLD_DEEP, M.Metal, "Ball")
		if k % 2 == 0 then
			gem(m, head, "CrownGem", 0.16, CFrame.new(math.cos(a) * (r + 0.05), top, math.sin(a) * (r + 0.05)))
		end
	end
	gem(m, head, "CrownTopGem", 0.22, CFrame.new(0, top + 0.42, 0))
	return nil
end

BUILDERS.MogulHat = function(m, character)
	local head, hy, hx = headInfo(character)
	if not head then
		return nil
	end
	local top = hy / 2 + 0.08
	piece(m, head, "HatBrim", Vector3.new(0.08, hx * 1.6, hx * 1.6), CFrame.new(0, top, 0) * CFrame.Angles(0, 0, math.pi / 2), BLACK, M.Fabric, "Cyl")
	piece(m, head, "HatCrown", Vector3.new(0.95, hx * 0.95, hx * 0.95), CFrame.new(0, top + 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), BLACK, M.Fabric, "Cyl")
	piece(m, head, "HatBand", Vector3.new(0.2, hx * 0.97, hx * 0.97), CFrame.new(0, top + 0.16, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Metal, "Cyl")
	gem(m, head, "HatGem", 0.2, CFrame.new(0, top + 0.16, -hx * 0.49))
	return nil
end

BUILDERS.GoldShades = function(m, character)
	local head, _, hx = headInfo(character)
	if not head then
		return nil
	end
	local z = -head.Size.Z / 2 - 0.04
	for _, sx in ipairs({ -1, 1 }) do
		local lens = piece(m, head, "Lens", Vector3.new(hx * 0.34, 0.24, 0.05), CFrame.new(sx * hx * 0.2, 0.12, z), rgb(30, 30, 40), M.Glass)
		lens.Reflectance = 0.5
		piece(m, head, "Rim", Vector3.new(hx * 0.37, 0.04, 0.06), CFrame.new(sx * hx * 0.2, 0.25, z), GOLD, M.Metal)
		piece(m, head, "Arm", Vector3.new(0.04, 0.04, head.Size.Z * 0.7), CFrame.new(sx * hx * 0.5, 0.2, z + head.Size.Z * 0.35), GOLD, M.Metal)
	end
	piece(m, head, "Bridge", Vector3.new(hx * 0.08, 0.04, 0.05), CFrame.new(0, 0.18, z), GOLD, M.Metal)
	return nil
end

BUILDERS.DiamondMonocle = function(m, character)
	local head, _, hx = headInfo(character)
	if not head then
		return nil
	end
	local z = -head.Size.Z / 2 - 0.04
	piece(m, head, "MonocleRim", Vector3.new(0.05, 0.36, 0.36), CFrame.new(hx * 0.2, 0.12, z) * CFrame.Angles(0, math.pi / 2, 0), GOLD, M.Metal, "Cyl")
	local glass = piece(m, head, "MonocleGlass", Vector3.new(0.02, 0.3, 0.3), CFrame.new(hx * 0.2, 0.12, z - 0.01) * CFrame.Angles(0, math.pi / 2, 0), GLASS, M.Glass, "Cyl")
	glass.Transparency = 0.5
	gem(m, head, "MonocleGem", 0.1, CFrame.new(hx * 0.36, 0.12, z))
	for k = 1, 5 do
		piece(m, head, "MonocleChain", Vector3.new(0.05, 0.05, 0.05), CFrame.new(hx * 0.34 + k * 0.03, 0.02 - k * 0.12, z + k * 0.04), GOLD, M.Metal, "Ball")
	end
	return nil
end

local function torsoInfo(character: Model): (BasePart?, Vector3)
	local torso = bodyPart(character, { "UpperTorso", "Torso" })
	if not torso then
		return nil, Vector3.one
	end
	return torso, torso.Size
end

BUILDERS.GoldChain = function(m, character)
	local torso, s = torsoInfo(character)
	if not torso then
		return nil
	end
	local z = -s.Z / 2 - 0.05
	for k = -6, 6 do
		local a = k / 6 * 1.1
		piece(m, torso, "ChainLink", Vector3.new(0.14, 0.14, 0.14), CFrame.new(math.sin(a) * s.X * 0.32, s.Y / 2 - 0.1 - (1 - math.abs(k) / 6) * 0.5, z), GOLD, M.Metal, "Ball")
	end
	piece(m, torso, "ChainPendant", Vector3.new(0.34, 0.34, 0.08), CFrame.new(0, s.Y / 2 - 0.72, z - 0.02), GOLD_DEEP, M.Metal)
	return nil
end

BUILDERS.DiamondNecklace = function(m, character)
	local torso, s = torsoInfo(character)
	if not torso then
		return nil
	end
	local z = -s.Z / 2 - 0.05
	for k = -7, 7 do
		local a = k / 7 * 1.15
		gem(m, torso, "NecklaceGem", 0.12, CFrame.new(math.sin(a) * s.X * 0.3, s.Y / 2 - 0.08 - (1 - math.abs(k) / 7) * 0.42, z))
	end
	gem(m, torso, "NecklaceHeart", 0.3, CFrame.new(0, s.Y / 2 - 0.68, z - 0.04))
	return nil
end

BUILDERS.GoldWatch = function(m, character)
	local arm = bodyPart(character, { "LeftLowerArm", "Left Arm" })
	if not arm then
		return nil
	end
	local y = -arm.Size.Y / 2 + 0.25
	piece(m, arm, "WatchBand", Vector3.new(arm.Size.X + 0.08, 0.2, arm.Size.Z + 0.08), CFrame.new(0, y, 0), GOLD, M.Metal)
	piece(m, arm, "WatchFace", Vector3.new(0.05, 0.32, 0.32), CFrame.new(-arm.Size.X / 2 - 0.06, y, 0), GOLD_DEEP, M.Metal, "Cyl")
	piece(m, arm, "WatchDial", Vector3.new(0.02, 0.26, 0.26), CFrame.new(-arm.Size.X / 2 - 0.09, y, 0), rgb(250, 248, 240), M.SmoothPlastic, "Cyl")
	return nil
end

BUILDERS.VelvetCape = function(m, character)
	local torso, s = torsoInfo(character)
	if not torso then
		return nil
	end
	local z = s.Z / 2 + 0.08
	piece(m, torso, "CapeCollar", Vector3.new(s.X * 1.15, 0.3, 0.5), CFrame.new(0, s.Y / 2 - 0.02, z - 0.05), ERMINE, M.Fabric)
	for k = 0, 4 do
		piece(m, torso, "ErmineDot", Vector3.new(0.08, 0.12, 0.04), CFrame.new(-s.X * 0.45 + k * s.X * 0.22, s.Y / 2 - 0.02, z - 0.32), BLACK, M.Fabric)
	end
	local cape, w = piece(m, torso, "Cape", Vector3.new(s.X * 1.05, s.Y * 2.1, 0.08), CFrame.new(0, s.Y / 2 - s.Y * 1.05, z + 0.04), VELVET, M.Fabric)
	local hem = piece(m, torso, "CapeHem", Vector3.new(s.X * 1.07, 0.16, 0.1), CFrame.new(0, s.Y / 2 - s.Y * 2.1 + 0.08, z + 0.04), GOLD, M.Metal)
	local hemWeld = hem:FindFirstChildOfClass("Weld")
	local base = w.C0
	local hemBase = hemWeld and hemWeld.C0
	local pivot = CFrame.new(0, s.Y / 2, z)
	local _ = cape
	return function(t: number)
		local swing = math.rad(6 + math.sin(t * 1.6) * 5)
		local rot = pivot * CFrame.Angles(swing, 0, math.sin(t * 1.1) * 0.03)
		w.C0 = rot * pivot:Inverse() * base
		if hemWeld and hemBase then
			hemWeld.C0 = rot * pivot:Inverse() * hemBase
		end
	end
end

BUILDERS.CrystalWings = function(m, character)
	local torso, s = torsoInfo(character)
	if not torso then
		return nil
	end
	local z = s.Z / 2 + 0.15
	local wings = {}
	for _, sx in ipairs({ -1, 1 }) do
		local root = CFrame.new(sx * 0.25, s.Y * 0.25, z)
		local feathers = {}
		for k = 0, 3 do
			local len = 2.4 - k * 0.4
			local c0 = root * CFrame.Angles(0, 0, sx * math.rad(-20 - k * 18)) * CFrame.new(sx * len / 2, 0, 0.02 * k)
			local f, w = piece(m, torso, "Feather", Vector3.new(len, 0.42, 0.05), c0, DIAMOND, M.Glass)
			f.Transparency = 0.25
			table.insert(feathers, { W = w, Base = c0 })
		end
		table.insert(wings, { Sx = sx, Root = root, Feathers = feathers })
	end
	return function(t: number)
		local flap = math.sin(t * 2.2) * math.rad(14)
		for _, wing in ipairs(wings) do
			local rot = wing.Root * CFrame.Angles(0, wing.Sx * flap, 0) * wing.Root:Inverse()
			for _, f in ipairs(wing.Feathers) do
				f.W.C0 = rot * f.Base
			end
		end
	end
end

BUILDERS.SparkleAura = function(m, character)
	local root = bodyPart(character, { "HumanoidRootPart" })
	if not root then
		return nil
	end
	local gems = {}
	for k = 0, 5 do
		local _, w = gem(m, root, "AuraGem", 0.26, CFrame.new(0, 0, 0))
		table.insert(gems, { W = w, Phase = k * math.pi / 3, H = -1.6 + (k % 3) * 1.2 })
	end
	return function(t: number)
		for _, g in ipairs(gems) do
			local a = t * 1.3 + g.Phase
			g.W.C0 = CFrame.new(math.cos(a) * 2.2, g.H + math.sin(t * 2 + g.Phase) * 0.3, math.sin(a) * 2.2) * CFrame.Angles(math.rad(45), a * 2, math.rad(45))
		end
	end
end

BUILDERS.GoldenAura = function(m, character)
	local root = bodyPart(character, { "HumanoidRootPart" })
	local head = bodyPart(character, { "Head" })
	if not root or not head then
		return nil
	end
	local ring, rw = piece(m, root, "AuraRing", Vector3.new(0.06, 5.2, 5.2), CFrame.new(0, -2.9, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Neon, "Cyl")
	ring.Transparency = 0.7
	local halo, hw = piece(m, head, "Halo", Vector3.new(0.08, 1.5, 1.5), CFrame.new(0, head.Size.Y / 2 + 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Neon, "Cyl")
	halo.Transparency = 0.35
	local inner = piece(m, head, "HaloHole", Vector3.new(0.1, 1.1, 1.1), CFrame.new(0, head.Size.Y / 2 + 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 250, 230), M.SmoothPlastic, "Cyl")
	inner.Transparency = 0.85
	local hb = hw.C0
	return function(t: number)
		hw.C0 = CFrame.new(0, math.sin(t * 2) * 0.08, 0) * hb
		rw.C0 = CFrame.new(0, -2.9, 0) * CFrame.Angles(0, t * 0.6, math.pi / 2)
		ring.Transparency = 0.62 + 0.12 * math.sin(t * 2.5)
	end
end

----------------------------------------------------------------------
-- Titre (au-dessus de la tête)
----------------------------------------------------------------------

local function titleGui(character: Model, text: string): BillboardGui?
	local head = bodyPart(character, { "Head" })
	if not head then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "LuxTitle"
	bb.Size = UDim2.fromOffset(180, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.Adornee = head
	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = rgb(20, 24, 44)
	bg.BackgroundTransparency = 0.25
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = bg
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 1.5
	st.Parent = bg
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -10, 1, -4)
	l.Position = UDim2.fromOffset(5, 2)
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = GOLD
	l.Text = Locale.T(text)
	l.Parent = bg
	bb.Parent = head
	return bb
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function LuxuryWear.Build(character: Model, slot: string, id: string): (Model?, ((t: number) -> ())?)
	local fn = BUILDERS[id]
	if not fn then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Lux_" .. slot
	local ok, anim = pcall(fn, m, character)
	if not ok then
		m:Destroy()
		return nil
	end
	m.Parent = character
	return m, if type(anim) == "function" then anim else nil
end

local function dropEntry(character: Model)
	local e = worn[character]
	if not e then
		return
	end
	for _, w in pairs(e.Slots) do
		w.Model:Destroy()
	end
	if e.Title then
		e.Title:Destroy()
	end
	worn[character] = nil
end

local function sync(character: Model, near: boolean)
	local e = worn[character]
	if not near then
		if e then
			dropEntry(character)
		end
		return
	end
	if not e then
		e = { Slots = {}, Title = nil, TitleText = nil }
		worn[character] = e
	end
	for _, slot in ipairs(SLOTS) do
		local id = character:GetAttribute("Lux" .. slot)
		local cur = e.Slots[slot]
		if type(id) ~= "string" then
			if cur then
				cur.Model:Destroy()
				e.Slots[slot] = nil
			end
		elseif not cur or cur.Id ~= id or not cur.Model.Parent then
			if cur then
				cur.Model:Destroy()
			end
			local m, anim = LuxuryWear.Build(character, slot, id)
			if m then
				e.Slots[slot] = { Model = m, Id = id, Anim = anim }
			else
				e.Slots[slot] = nil
			end
		end
	end
	local title = character:GetAttribute("LuxTitle")
	if type(title) == "string" and title ~= "" then
		if e.TitleText ~= title or not e.Title or not e.Title.Parent then
			if e.Title then
				e.Title:Destroy()
			end
			e.Title = titleGui(character, title)
			e.TitleText = title
		end
	elseif e.Title then
		e.Title:Destroy()
		e.Title = nil
		e.TitleText = nil
	end
end

function LuxuryWear.Step(dt: number)
	clock += dt
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	-- synchro 2 fois / s
	if clock >= 0.5 then
		clock = 0
		local alive = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and character.Parent and root and root:IsA("BasePart") then
				alive[character] = true
				pcall(sync, character, (root.Position - eye).Magnitude < RANGE)
			end
		end
		for character in pairs(worn) do
			if not alive[character] then
				dropEntry(character)
			end
		end
	end
	-- animations de près
	local t = os.clock()
	for character, e in pairs(worn) do
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - eye).Magnitude < ANIM_RANGE then
			for _, w in pairs(e.Slots) do
				if w.Anim then
					pcall(w.Anim, t)
				end
			end
		end
	end
end

function LuxuryWear.Clear()
	for character in pairs(worn) do
		dropEntry(character)
	end
	table.clear(worn)
end

function LuxuryWear.Count(): number
	local n = 0
	for _ in pairs(worn) do
		n += 1
	end
	return n
end

return LuxuryWear
