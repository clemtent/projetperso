--[[
	BankBuild (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > BankBuild

	🏦 La BANQUE DOPAMINE en 3D (v11, BANK11), construite CÔTÉ CLIENT et en
	flux par BankClient (aucune pièce serveur). Échelle Roblox (SCALE11 :
	guichets 3,3, écran des distributeurs à 4,3, bancs 1,85, portes ≥ 8 x 4,5,
	marches de 0,75, garde-corps 3,5). Repère : BankLayout (centre au sol,
	façade vers -Z / la rue du marché).
	  EXTÉRIEUR : parvis en granit, grand escalier (4 marches), socles avec
	  lanternes et drapeaux, PORTIQUE à 6 colonnes (bases, chapiteaux),
	  frise "BANQUE DOPAMINE", fronton triangulaire avec médaillon 💎,
	  façade en pierre de taille (soubassement, bandeaux, fenêtres hautes à
	  encadrements), portes de bronze ouvertes, 2 distributeurs sous le
	  portique, corniche, toit avec verrière ; RUELLE DE SERVICE (+X) :
	  quai, escalier, porte du personnel, boîtier d'alarme, caméra, benne,
	  caisses, tableau "Plan du casse" ; jardinet côté -X.
	  HALL : sol de marbre (tapis rouge, rosace dorée), 4 colonnes, plafond à
	  caissons + verrière, 2 lustres de cristal, 4 GUICHETS (comptoir en
	  acajou et marbre, vitres, numéros, lampes vertes, sonnettes, terminaux)
	  avec 4 guichetiers, file d'attente (poteaux dorés, cordons de velours),
	  bancs, distributeur de tickets + écran "n° appelé", tableau du COURS DU
	  DIAMANT, grande horloge, plantes, BOUTIQUE DE LUXE 💎 (vitrines,
	  bijoutier, couronne, collier), SALLE DES COFFRES (mur de coffrets
	  numérotés), 2 distributeurs, caméras de surveillance qui balaient.
	  ARRIÈRE : espace du personnel (bureaux, écrans, armoires, machine à
	  compter), PORTE RONDE DU COFFRE (volant, verrous, charnières, s'ouvre
	  pendant un casse), CHAMBRE FORTE (casiers, 8 piles de butin : lingots,
	  plateaux de diamants, liasses).
	Lumières : 2 PointLight doux (lustres, Brightness ≤ 0,8) + 1 rouge
	d'alarme (éteinte hors casse). Aucun son.

	API :
	  BankBuild.Build(parent, F) -> Bank   (F = BankLayout.CFrame(count))
	  BankBuild.BuildLow(parent, F) -> Model   (silhouette lointaine)
	  Bank = { Model, Spots = { Counters, ATMs, Luxury, Deposit, Lobby, Hack, Rates },
	           Vault = { Parts, Hinge, Open }, StaffDoor = { Parts, Hinge, Open },
	           Piles = { Model }, Cameras = { ... }, Npcs = { ... }, Board = SurfaceGui,
	           Screens = { ... }, AlarmLight = PointLight, Beacons = { BasePart }, Drill = Model }
	  BankBuild.SetDoor(door, openFraction)   0 fermé .. 1 ouvert
	  BankBuild.Animate(bank, t, dt)          caméras, drapeaux, diamants qui tournent, guichetiers
	  BankBuild.SetPileTaken(bank, i, taken)
	  BankBuild.SetDrill(bank, visible, progress, jammed)
	  BankBuild.SetAlarm(bank, on, t)
	  BankBuild.Count() -> pièces créées (budget)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityKit = require(script.Parent.CityKit)
local BankLayout = require(ReplicatedStorage.Shared.BankLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local okNpc, NPCModels = pcall(require, ReplicatedStorage.Shared.NPCModels)
local okClock, ClockKit = pcall(require, script.Parent.ClockKit)

local BankBuild = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local STONE = rgb(226, 218, 200) -- pierre de taille
local STONE_DARK = rgb(196, 186, 166)
local GRANITE = rgb(118, 114, 112)
local GRANITE_LIGHT = rgb(150, 146, 142)
local MARBLE = rgb(238, 233, 224)
local MARBLE_VEIN = rgb(206, 198, 186)
local MARBLE_DARK = rgb(64, 58, 60)
local GOLD = rgb(222, 178, 72)
local GOLD_DEEP = rgb(186, 138, 46)
local BRONZE = rgb(122, 84, 48)
local MAHOGANY = rgb(92, 44, 30)
local MAHOGANY_LIGHT = rgb(124, 62, 40)
local VELVET = rgb(150, 26, 44)
local GREEN_LAMP = rgb(40, 140, 86)
local STEEL = rgb(156, 162, 172)
local STEEL_DARK = rgb(74, 78, 88)
local IRON = rgb(46, 48, 56)
local GLASS = rgb(196, 226, 238)
local WHITE = rgb(248, 246, 242)
local INK = rgb(30, 28, 40)
local PLANT = rgb(58, 120, 64)
local DIAMOND = rgb(170, 236, 255)
local CASH = rgb(116, 196, 128)

local FLOOR = BankLayout.FLOOR
local HW = BankLayout.HALF_W -- 29
local ALLEY = BankLayout.ALLEY -- 35.5
local ROOF = FLOOR + BankLayout.HALL_H -- dessous du toit (27,6)
local FRONT = BankLayout.FRONT -- 21
local VW = BankLayout.VAULT_WALL -- 13
local VH = BankLayout.VAULT_HALF -- 11
local BACK = BankLayout.BACK -- 26
local DOOR_C = FLOOR + 6.0 -- centre de la porte ronde
local DOOR_R = 7.6

local created = 0

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

-- Porte : pivot (Hinge, Angle) ou porte ronde qui ROULE le long du mur (Roll : Travel studs, rayon R)
export type Door = { Parts: { { Part: BasePart, Rel: CFrame } }, Hinge: CFrame, Angle: number, Open: number, Roll: number?, R: number? }

----------------------------------------------------------------------
-- Fabriques (repère local de la banque)
----------------------------------------------------------------------

local Build = {}
Build.__index = Build

local function new(parent: Instance, F: CFrame, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return setmetatable({ M = model, F = F, Cur = model :: Instance }, Build)
end

function Build:Group(name: string): Instance
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = self.M
	self.Cur = m
	return m
end

function Build:Box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, solid: boolean?): BasePart
	created += 1
	return CityKit.Box(self.Cur, name, self.F, x0, x1, y0, y1, z0, z1, color, mat, solid)
end

function Build:Part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: string?, solid: boolean?): BasePart
	created += 1
	return CityKit.Part(self.Cur, name, size, self.F * cf, color, mat, shape, solid)
end

-- Cylindre debout
function Build:Col(name: string, x: number, z: number, y0: number, y1: number, d: number, color: Color3, mat: Enum.Material?, solid: boolean?): BasePart
	created += 1
	return CityKit.Column(self.Cur, name, self.F, x, z, y0, y1, d, color, mat, solid)
end

-- Disque (cylindre) d'axe Z local, centre (x, y, z), épaisseur t, diamètre d
function Build:DiscZ(name: string, x: number, y: number, z: number, t: number, d: number, color: Color3, mat: Enum.Material?, solid: boolean?): BasePart
	return self:Part(name, Vector3.new(t, d, d), CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), color, mat, "Cyl", solid)
end

-- Disque d'axe X local
function Build:DiscX(name: string, x: number, y: number, z: number, t: number, d: number, color: Color3, mat: Enum.Material?): BasePart
	return self:Part(name, Vector3.new(t, d, d), CFrame.new(x, y, z), color, mat, "Cyl")
end

function Build:Ball(name: string, x: number, y: number, z: number, d: number, color: Color3, mat: Enum.Material?): BasePart
	return self:Part(name, Vector3.new(d, d, d), CFrame.new(x, y, z), color, mat, "Ball")
end

function Build:Wedge(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, solid: boolean?): BasePart
	created += 1
	return CityKit.Wedge(self.Cur, name, size, self.F * cf, color, mat, solid)
end

-- Mur le long de X (de x0 à x1, épaisseur z0..z1) avec des trous { { a0, a1, b0, b1 } } (x, y)
function Build:WallX(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, holes: { { number } }, color: Color3, mat: Enum.Material?)
	local cuts = { x0, x1 }
	for _, h in ipairs(holes) do
		table.insert(cuts, math.clamp(h[1], x0, x1))
		table.insert(cuts, math.clamp(h[2], x0, x1))
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a > 0.01 then
			local mid = (a + b) / 2
			local spans = {}
			for _, h in ipairs(holes) do
				if mid > h[1] and mid < h[2] then
					table.insert(spans, { h[3], h[4] })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local y = y0
			for _, s in ipairs(spans) do
				if s[1] > y + 0.01 then
					self:Box(name, a, b, y, s[1], z0, z1, color, mat, true)
				end
				y = math.max(y, s[2])
			end
			if y1 > y + 0.01 then
				self:Box(name, a, b, y, y1, z0, z1, color, mat, true)
			end
		end
	end
end

-- Mur le long de Z (de z0 à z1, épaisseur x0..x1), trous { { z0, z1, y0, y1 } }
function Build:WallZ(name: string, z0: number, z1: number, y0: number, y1: number, x0: number, x1: number, holes: { { number } }, color: Color3, mat: Enum.Material?)
	local cuts = { z0, z1 }
	for _, h in ipairs(holes) do
		table.insert(cuts, math.clamp(h[1], z0, z1))
		table.insert(cuts, math.clamp(h[2], z0, z1))
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a > 0.01 then
			local mid = (a + b) / 2
			local spans = {}
			for _, h in ipairs(holes) do
				if mid > h[1] and mid < h[2] then
					table.insert(spans, { h[3], h[4] })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local y = y0
			for _, s in ipairs(spans) do
				if s[1] > y + 0.01 then
					self:Box(name, x0, x1, y, s[1], a, b, color, mat, true)
				end
				y = math.max(y, s[2])
			end
			if y1 > y + 0.01 then
				self:Box(name, x0, x1, y, y1, a, b, color, mat, true)
			end
		end
	end
end

-- Texte sur une face d'une pièce
local function label(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?, pps: number?): TextLabel
	return CityKit.Text(host, face, text, color, bg, font, maxDistance, pps)
end

-- Pièce invisible porteuse d'une SurfaceGui (aucun z-fight possible)
function Build:Sign(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): BasePart
	local p = self:Box(name, x0, x1, y0, y1, z0, z1, WHITE, M.SmoothPlastic, false)
	p.Transparency = 1
	p.CastShadow = false
	return p
end

----------------------------------------------------------------------
-- Portes qui pivotent
----------------------------------------------------------------------

local function makeDoor(F: CFrame, hingeLocal: CFrame, parts: { BasePart }, openAngle: number): Door
	local hinge = F * hingeLocal
	local list = {}
	for _, p in ipairs(parts) do
		table.insert(list, { Part = p, Rel = hinge:ToObjectSpace(p.CFrame) })
	end
	return { Parts = list, Hinge = hinge, Angle = openAngle, Open = 0 }
end

function BankBuild.SetDoor(door: Door?, open: number)
	if not door then
		return
	end
	local f = math.clamp(open, 0, 1)
	if math.abs(f - door.Open) < 1e-4 then
		return
	end
	door.Open = f
	-- (ease in-out : la lourde porte démarre et s'arrête en douceur)
	local e = f * f * (3 - 2 * f)
	local rot
	if door.Roll then
		-- (cartoon) la porte ronde roule sur son rail, le long du mur
		local d = (door.Roll :: number) * e
		rot = door.Hinge * CFrame.new(d, 0, 0) * CFrame.Angles(0, 0, -d / (door.R or 7.6))
	else
		rot = door.Hinge * CFrame.Angles(0, door.Angle * e, 0)
	end
	for _, item in ipairs(door.Parts) do
		item.Part.CFrame = rot * item.Rel
		item.Part.CanCollide = item.Part:GetAttribute("DoorSolid") == true and f < 0.5
	end
end

----------------------------------------------------------------------
-- EXTÉRIEUR
----------------------------------------------------------------------

local function exterior(b: any, out: any)
	b:Group("Exterior")
	-- parvis en granit (devant) + ruelles
	b:Box("Forecourt", -ALLEY, ALLEY, 0, 0.6, -BankLayout.STEPS_END - 2, -BankLayout.PORTICO, GRANITE_LIGHT, M.Slate, true)
	b:Box("AlleyEast", HW, ALLEY, 0, 0.6, -BankLayout.PORTICO, BACK + 2, GRANITE, M.Concrete, true)
	b:Box("GardenWest", -ALLEY, -HW, 0, 0.6, -BankLayout.PORTICO, BACK + 2, rgb(96, 142, 78), M.Grass, true)
	b:Box("BackWalk", -HW, HW, 0, 0.6, BACK, BACK + 2, GRANITE, M.Concrete, true)
	-- bande de pierre claire au pied de l'escalier
	b:Box("ForecourtBand", -ALLEY + 0.6, ALLEY - 0.6, 0.6, 0.64, -BankLayout.STEPS_END - 1.6, -BankLayout.STEPS_END - 0.8, MARBLE_VEIN, M.Slate)
	-- grand escalier (4 marches de 0,75, girons de 2,5)
	local z0 = -BankLayout.STEPS_END
	for k = 1, 4 do
		local za, zb = z0 + (k - 1) * 2.5, z0 + k * 2.5
		local top = 0.6 + 0.75 * k
		b:Box("Step", -20, 20, 0.6, top, za, zb, k % 2 == 0 and STONE or STONE_DARK, M.Limestone, true)
		-- nez de marche (pierre plus claire, en saillie)
		b:Box("StepNose", -20, 20, top - 0.16, top + 0.02, za - 0.12, za + 0.25, MARBLE, M.Marble)
	end
	-- socles des deux côtés de l'escalier (lanternes, drapeaux)
	for _, sx in ipairs({ -1, 1 }) do
		local xa, xb = sx > 0 and 20 or -27, sx > 0 and 27 or -20
		b:Box("StairPlinth", xa, xb, 0.6, FLOOR + 1.1, z0, -BankLayout.PORTICO, STONE_DARK, M.Limestone, true)
		b:Box("PlinthCap", xa - 0.3, xb + 0.3, FLOOR + 1.1, FLOOR + 1.6, z0 - 0.3, -BankLayout.PORTICO, MARBLE, M.Marble, true)
		-- jardinière + buis taillés
		b:Box("Planter", xa + 1, xb - 1, FLOOR + 1.6, FLOOR + 3.2, z0 + 1, z0 + 4.4, GRANITE, M.Slate, true)
		b:Box("PlanterSoil", xa + 1.3, xb - 1.3, FLOOR + 3.05, FLOOR + 3.2 + 0.05, z0 + 1.3, z0 + 4.1, rgb(80, 58, 40), M.Ground)
		for i = 0, 2 do
			local x = (xa + 1.3) + (i + 0.5) * ((xb - xa - 2.6) / 3)
			b:Ball("Topiary", x, FLOOR + 4.5, z0 + 2.7, 2.6, PLANT, M.Grass)
		end
		-- lanterne de bronze
		local lx = (xa + xb) / 2
		local LF = b.F * CFrame.new(lx, FLOOR + 1.6, -BankLayout.PORTICO - 2.4)
		local g = b.Cur
		CityKit.Lantern(g, LF, 7.5, BRONZE)
		created += 7
		-- mât + drapeau 💎
		local px = sx > 0 and 26 or -26
		b:Col("FlagBase", px, -BankLayout.PORTICO - 1.2, FLOOR + 1.6, FLOOR + 2.2, 1.2, BRONZE, M.Metal)
		b:Col("FlagPole", px, -BankLayout.PORTICO - 1.2, FLOOR + 2.2, FLOOR + 20, 0.32, rgb(220, 220, 226), M.Metal)
		b:Ball("FlagFinial", px, FLOOR + 20.3, -BankLayout.PORTICO - 1.2, 0.6, GOLD, M.Metal)
		local flag = b:Part("Flag", Vector3.new(5.2, 3.2, 0.08), CFrame.new(px - sx * 2.75, FLOOR + 18.2, -BankLayout.PORTICO - 1.2), rgb(36, 52, 112), M.Fabric)
		local canvas = CityKit.Canvas(flag, Enum.NormalId.Front, 220, 30)
		CityKit.Blob(canvas, 0.5, 0.5, 1, 0.16, GOLD)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.TextScaled = true
		t.Text = "💎"
		t.Parent = canvas
		local back = flag:Clone()
		back.Parent = flag.Parent
		back.CFrame = flag.CFrame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 0.001)
		back.Transparency = 1
		local bc = back:FindFirstChildOfClass("SurfaceGui")
		if bc then
			bc.Face = Enum.NormalId.Front
		end
		table.insert(out.Flags, { Part = flag, Back = back, Base = flag.CFrame, Pivot = b.F * CFrame.new(px, FLOOR + 18.2, -BankLayout.PORTICO - 1.2), Sx = sx })
	end
	-- socle (podium) du bâtiment : portique + hall
	b:Box("PorticoSlab", -HW, HW, 0, FLOOR, -BankLayout.PORTICO, -FRONT, STONE, M.Limestone, true)
	b:Box("HallSlab", -HW, HW, 0, FLOOR - 0.1, -FRONT, BACK, GRANITE, M.Concrete, true)
	-- dallage du portique (bandes de marbre)
	b:Box("PorticoInlay", -HW + 1, HW - 1, FLOOR, FLOOR + 0.03, -BankLayout.PORTICO + 0.8, -BankLayout.PORTICO + 1.3, GOLD_DEEP, M.Marble)
	-- soubassement en granit tout autour (au-dessus du sol)
	for _, sx in ipairs({ -1, 1 }) do
		b:Box("Plinth", sx > 0 and HW or -HW - 0.4, sx > 0 and HW + 0.4 or -HW, 0.6, FLOOR + 1.6, -FRONT, BACK, GRANITE, M.Slate, true)
	end
	b:Box("PlinthBack", -HW - 0.4, HW + 0.4, 0.6, FLOOR + 1.6, BACK, BACK + 0.4, GRANITE, M.Slate, true)
end

----------------------------------------------------------------------
-- MURS, FAÇADE, PORTIQUE, TOIT
----------------------------------------------------------------------

local WINDOW_X = { -19, -11, 11, 19 }

local function shell(b: any, out: any)
	b:Group("Shell")
	local wallTop = ROOF + 1
	-- façade (z -21..-20) : porte 10 x 14, 4 fenêtres hautes
	local holes = { { -5, 5, FLOOR - 0.1, FLOOR + 14 } }
	for _, x in ipairs(WINDOW_X) do
		table.insert(holes, { x - 2.4, x + 2.4, FLOOR + 5, FLOOR + 17 })
	end
	b:WallX("FrontWall", -HW, HW, FLOOR - 0.1, wallTop, -FRONT, -FRONT + 1, holes, STONE, M.Limestone)
	-- côtés (fenêtres hautes ; porte du personnel à l'est)
	local sideWin = { { -15.5, -10.5, FLOOR + 13, FLOOR + 21 }, { -5.5, -0.5, FLOOR + 13, FLOOR + 21 } }
	local east = table.clone(sideWin)
	table.insert(east, { BankLayout.STAFF_DOOR_Z - 2.25, BankLayout.STAFF_DOOR_Z + 2.25, FLOOR - 0.1, FLOOR + 8.5 })
	b:WallZ("EastWall", -FRONT + 1, BACK, FLOOR - 0.1, wallTop, HW - 1, HW, east, STONE, M.Limestone)
	b:WallZ("WestWall", -FRONT + 1, BACK, FLOOR - 0.1, wallTop, -HW, -HW + 1, sideWin, STONE, M.Limestone)
	b:Box("BackWall", -HW + 1, HW - 1, FLOOR - 0.1, wallTop, BACK - 1, BACK, STONE, M.Limestone, true)
	-- vitres + encadrements des fenêtres de façade
	for _, x in ipairs(WINDOW_X) do
		b:Box("WindowGlass", x - 2.4, x + 2.4, FLOOR + 5, FLOOR + 17, -FRONT + 0.42, -FRONT + 0.58, GLASS, M.Glass).Transparency = 0.45
		for _, y in ipairs({ FLOOR + 9, FLOOR + 13 }) do
			b:Box("WindowBar", x - 2.4, x + 2.4, y - 0.12, y + 0.12, -FRONT + 0.3, -FRONT + 0.7, BRONZE, M.Metal)
		end
		b:Box("WindowMullion", x - 0.12, x + 0.12, FLOOR + 5, FLOOR + 17, -FRONT + 0.3, -FRONT + 0.7, BRONZE, M.Metal)
		-- encadrement en saillie + clé de voûte dorée
		b:Box("WindowFrameL", x - 3.1, x - 2.4, FLOOR + 4.4, FLOOR + 17.7, -FRONT - 0.35, -FRONT, STONE_DARK, M.Limestone)
		b:Box("WindowFrameR", x + 2.4, x + 3.1, FLOOR + 4.4, FLOOR + 17.7, -FRONT - 0.35, -FRONT, STONE_DARK, M.Limestone)
		b:Box("WindowSill", x - 3.4, x + 3.4, FLOOR + 4.0, FLOOR + 4.6, -FRONT - 0.6, -FRONT, MARBLE, M.Marble)
		b:Box("WindowHead", x - 3.4, x + 3.4, FLOOR + 17.7, FLOOR + 18.6, -FRONT - 0.5, -FRONT, STONE_DARK, M.Limestone)
		b:Box("Keystone", x - 0.6, x + 0.6, FLOOR + 17.0, FLOOR + 18.9, -FRONT - 0.75, -FRONT - 0.5, GOLD, M.Metal)
		-- intérieur : même vitre vue du hall (encadrement intérieur)
		b:Box("WindowInnerSill", x - 2.8, x + 2.8, FLOOR + 4.6, FLOOR + 5.0, -FRONT + 1, -FRONT + 1.5, MARBLE, M.Marble)
	end
	for _, z in ipairs({ -13, -3 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local xa = sx > 0 and HW - 0.58 or -HW + 0.42
			b:Box("SideGlass", xa, xa + 0.16, FLOOR + 13, FLOOR + 21, z - 2.5, z + 2.5, GLASS, M.Glass).Transparency = 0.45
			b:Box("SideBar", xa - 0.1, xa + 0.26, FLOOR + 16.9, FLOOR + 17.1, z - 2.5, z + 2.5, BRONZE, M.Metal)
		end
	end
	-- bandeaux de pierre (refends) sur la façade et les côtés
	for _, y in ipairs({ FLOOR + 2.0, FLOOR + 3.5 }) do
		b:Box("Rustic", -HW - 0.2, HW + 0.2, y - 0.14, y + 0.14, -FRONT - 0.2, -FRONT, STONE_DARK, M.Limestone)
	end
	-- corniche + attique
	b:Box("Cornice", -HW - 0.8, HW + 0.8, wallTop, wallTop + 1.0, -FRONT - 0.8, BACK + 0.8, STONE_DARK, M.Limestone, true)
	b:Box("CorniceLip", -HW - 1.2, HW + 1.2, wallTop + 1.0, wallTop + 1.4, -FRONT - 1.2, BACK + 1.2, STONE, M.Limestone)
	b:Box("AtticFront", -HW, HW, wallTop + 1.4, wallTop + 3.2, -FRONT - 0.2, -FRONT + 1, STONE, M.Limestone)
	b:Box("AtticBack", -HW, HW, wallTop + 1.4, wallTop + 3.2, BACK - 1, BACK + 0.2, STONE, M.Limestone)
	b:Box("AtticEast", HW - 1, HW + 0.2, wallTop + 1.4, wallTop + 3.2, -FRONT + 1, BACK - 1, STONE, M.Limestone)
	b:Box("AtticWest", -HW - 0.2, -HW + 1, wallTop + 1.4, wallTop + 3.2, -FRONT + 1, BACK - 1, STONE, M.Limestone)
	-- toit (avec trou de la verrière) + verrière
	local sx0, sx1, sz0, sz1 = -8, 8, -16, -1
	b:Box("Roof", -HW + 1, sx0, ROOF, wallTop, -FRONT + 1, BACK - 1, rgb(110, 108, 106), M.Concrete, true)
	b:Box("Roof", sx1, HW - 1, ROOF, wallTop, -FRONT + 1, BACK - 1, rgb(110, 108, 106), M.Concrete, true)
	b:Box("Roof", sx0, sx1, ROOF, wallTop, -FRONT + 1, sz0, rgb(110, 108, 106), M.Concrete, true)
	b:Box("Roof", sx0, sx1, ROOF, wallTop, sz1, BACK - 1, rgb(110, 108, 106), M.Concrete, true)
	b:Box("RoofTop", -HW + 1, HW - 1, wallTop, wallTop + 0.04, -FRONT + 1, BACK - 1, rgb(92, 92, 96), M.Asphalt).CastShadow = false
	b:Box("SkylightGlass", sx0, sx1, ROOF + 0.4, ROOF + 0.6, sz0, sz1, GLASS, M.Glass).Transparency = 0.35
	for x = sx0, sx1, 4 do
		b:Box("SkylightRib", x - 0.15, x + 0.15, ROOF + 0.6, wallTop + 2.6, sz0, sz1, IRON, M.Metal)
	end
	b:Box("LanternGlass", sx0, sx1, wallTop + 0.05, wallTop + 2.6, sz0 + 0.3, sz0 + 0.5, GLASS, M.Glass).Transparency = 0.4
	b:Box("LanternGlass", sx0, sx1, wallTop + 0.05, wallTop + 2.6, sz1 - 0.5, sz1 - 0.3, GLASS, M.Glass).Transparency = 0.4
	b:Box("LanternRoof", sx0 - 0.4, sx1 + 0.4, wallTop + 2.6, wallTop + 2.9, sz0, sz1, IRON, M.Metal)
	-- clim + édicule sur le toit
	b:Box("RoofUnit", 14, 20, wallTop, wallTop + 2.6, 10, 16, rgb(176, 178, 184), M.Metal, true)
	b:Box("RoofUnitGrill", 14.4, 19.6, wallTop + 2.6, wallTop + 2.8, 10.4, 15.6, IRON, M.DiamondPlate)
	b:Box("RoofHut", -20, -13, wallTop, wallTop + 5, 12, 20, STONE_DARK, M.Limestone, true)

	-- PORTIQUE : 6 colonnes, entablement, fronton
	b:Group("Portico")
	local colZ = -FRONT - 2.6
	for _, x in ipairs({ -23, -15, -7, 7, 15, 23 }) do
		b:Box("ColumnBase", x - 1.9, x + 1.9, FLOOR, FLOOR + 0.9, colZ - 1.9, colZ + 1.9, MARBLE, M.Marble, true)
		b:Col("ColumnTorus", x, colZ, FLOOR + 0.9, FLOOR + 1.5, 3.3, MARBLE, M.Marble)
		b:Col("Column", x, colZ, FLOOR + 1.5, FLOOR + 18.2, 2.8, MARBLE, M.Marble, true)
		-- cannelures (fines bandes plus sombres)
		for k = 0, 3 do
			local a = k * math.pi / 4
			b:Part("Flute", Vector3.new(0.22, 15.8, 2.86), CFrame.new(x, FLOOR + 9.9, colZ) * CFrame.Angles(0, a, 0), MARBLE_VEIN, M.Marble)
		end
		b:Col("ColumnNeck", x, colZ, FLOOR + 18.2, FLOOR + 18.7, 3.1, GOLD, M.Metal)
		b:Box("Capital", x - 2, x + 2, FLOOR + 18.7, FLOOR + 19.6, colZ - 2, colZ + 2, MARBLE, M.Marble, true)
		-- volutes (boules dorées aux coins du chapiteau)
		for _, dx in ipairs({ -1.75, 1.75 }) do
			b:DiscZ("Volute", x + dx, FLOOR + 19.0, colZ - 2.02, 0.3, 1.0, GOLD, M.Metal)
		end
	end
	local eTop = FLOOR + 23
	local frieze = b:Box("Entablature", -27.5, 27.5, FLOOR + 19.6, eTop, -BankLayout.PORTICO, -FRONT, STONE, M.Limestone, true)
	local _ = frieze
	b:Box("Architrave", -27.7, 27.7, FLOOR + 19.6, FLOOR + 20.4, -BankLayout.PORTICO - 0.2, -BankLayout.PORTICO, STONE_DARK, M.Limestone)
	-- frise : lettres dorées sur un bandeau de bronze sombre (lisible à l'ombre)
	b:Box("FriezeBand", -23, 23, FLOOR + 20.55, FLOOR + 22.85, -BankLayout.PORTICO - 0.1, -BankLayout.PORTICO, rgb(70, 52, 36), M.Metal)
	local sign = b:Sign("BankName", -22.6, 22.6, FLOOR + 20.6, FLOOR + 22.8, -BankLayout.PORTICO - 0.22, -BankLayout.PORTICO - 0.12)
	local name = label(sign, Enum.NormalId.Front, T("DOPAMINE BANK"), rgb(255, 214, 110), nil, Enum.Font.Garamond, 520, 22)
	name.TextStrokeTransparency = 0.4
	name.TextStrokeColor3 = rgb(60, 40, 20)
	b:Box("PorticoCornice", -28.4, 28.4, eTop, eTop + 0.9, -BankLayout.PORTICO - 0.9, -FRONT, STONE_DARK, M.Limestone, true)
	-- fronton (2 coins) + corniche rampante + médaillon 💎
	local pH, pBase = 7, eTop + 0.9
	b:Wedge("Pediment", Vector3.new(5, pH, 27.4), CFrame.new(13.7, pBase + pH / 2, -BankLayout.PORTICO + 2.5) * CFrame.Angles(0, -math.pi / 2, 0), STONE, M.Limestone, true)
	b:Wedge("Pediment", Vector3.new(5, pH, 27.4), CFrame.new(-13.7, pBase + pH / 2, -BankLayout.PORTICO + 2.5) * CFrame.Angles(0, math.pi / 2, 0), STONE, M.Limestone, true)
	local slope = math.atan2(pH, 27.4)
	local rake = math.sqrt(pH * pH + 27.4 * 27.4)
	for _, sx in ipairs({ -1, 1 }) do
		b:Part("Rake", Vector3.new(rake + 0.8, 0.6, 6.2), CFrame.new(sx * 13.7, pBase + pH / 2 + 0.45, -BankLayout.PORTICO + 2.5) * CFrame.Angles(0, 0, sx * -slope), STONE_DARK, M.Limestone)
	end
	b:DiscZ("Medallion", 0, pBase + 2.9, -BankLayout.PORTICO - 0.15, 0.3, 4.2, GOLD, M.Metal)
	local med = b:Sign("MedallionSign", -1.6, 1.6, pBase + 1.3, pBase + 4.5, -BankLayout.PORTICO - 0.4, -BankLayout.PORTICO - 0.32)
	label(med, Enum.NormalId.Front, "💎", WHITE, nil, Enum.Font.GothamBlack, 420, 30)
	b:Box("Acroterion", -0.8, 0.8, pBase + pH, pBase + pH + 1.6, -BankLayout.PORTICO + 1.5, -BankLayout.PORTICO + 3.5, GOLD, M.Metal)
	-- plafond du portique (caissons)
	b:Box("PorticoSoffit", -27.5, 27.5, FLOOR + 19.0, FLOOR + 19.6, -BankLayout.PORTICO, -FRONT, MARBLE, M.Marble)

	-- PORTES de bronze (ouvertes, rabattues contre l'embrasure)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 5
		b:Box("BronzeDoor", x - (sx > 0 and 0.35 or 0), x + (sx > 0 and 0 or 0.35), FLOOR, FLOOR + 13.8, -FRONT + 1, -FRONT + 5.8, BRONZE, M.Metal, true)
		for _, y in ipairs({ FLOOR + 3, FLOOR + 7, FLOOR + 11 }) do
			b:Box("DoorPanel", x - (sx > 0 and 0.5 or -0.35), x + (sx > 0 and -0.35 or 0.5), y - 1.4, y + 1.4, -FRONT + 1.6, -FRONT + 5.2, GOLD_DEEP, M.Metal)
		end
	end
	b:Box("DoorTransom", -5, 5, FLOOR + 13.7, FLOOR + 14, -FRONT - 0.1, -FRONT + 1.1, GOLD, M.Metal)
	b:Box("Threshold", -5, 5, FLOOR, FLOOR + 0.12, -FRONT - 0.3, -FRONT + 1.2, GOLD_DEEP, M.Metal)
	-- enseigne dorée au-dessus de la porte
	local over = b:Sign("DoorSign", -4.6, 4.6, FLOOR + 15, FLOOR + 16.6, -FRONT - 0.12, -FRONT - 0.02)
	label(over, Enum.NormalId.Front, T("Open every day"), GOLD, nil, Enum.Font.Garamond, 140, 30)
	out.Shell = true
end

----------------------------------------------------------------------
-- DISTRIBUTEURS
----------------------------------------------------------------------

local function atm(b: any, out: any, cf: CFrame, index: number)
	-- cf : sol, devant la machine, LookVector = vers l'utilisateur
	local g = b:Group("ATM_" .. index)
	local function P(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, solid: boolean?): BasePart
		created += 1
		return CityKit.Box(g, name, b.F * cf, x0, x1, y0, y1, z0, z1, color, mat, solid)
	end
	P("AtmBody", -1.6, 1.6, 0, 6.6, 0, 1.7, rgb(58, 62, 72), M.Metal, true)
	P("AtmTrim", -1.75, 1.75, 6.6, 7.0, -0.1, 1.8, GOLD, M.Metal)
	P("AtmHood", -1.6, 1.6, 5.4, 5.7, -0.7, 0, rgb(40, 44, 52), M.Metal)
	local screen = P("AtmScreen", -1.05, 1.05, 3.6, 5.0, -0.08, 0, rgb(18, 30, 52), M.SmoothPlastic)
	local canvas = CityKit.Canvas(screen, Enum.NormalId.Front, 60, 60)
	local bg = CityKit.Blob(canvas, 0.5, 0.5, 1, 1, rgb(18, 34, 70))
	local _ = bg
	CityKit.Blob(canvas, 0.5, 0.17, 1, 0.34, rgb(36, 52, 112))
	local l1 = Instance.new("TextLabel")
	l1.BackgroundTransparency = 1
	l1.Size = UDim2.fromScale(1, 0.32)
	l1.TextScaled = true
	l1.Font = Enum.Font.GothamBlack
	l1.TextColor3 = GOLD
	l1.Text = "💎 " .. T("Dopamine Bank")
	l1.Parent = canvas
	local l2 = l1:Clone()
	l2.Position = UDim2.fromScale(0.05, 0.42)
	l2.Size = UDim2.fromScale(0.9, 0.3)
	l2.Font = Enum.Font.GothamBold
	l2.TextColor3 = WHITE
	l2.Text = T("Press E")
	l2.Parent = canvas
	table.insert(out.Screens, l2)
	-- clavier incliné, fente à carte, ticket
	created += 1
	local padCF = b.F * cf * CFrame.new(0, 3.3, -0.35) * CFrame.Angles(math.rad(-25), 0, 0)
	CityKit.Part(g, "AtmKeypad", Vector3.new(1.6, 0.12, 0.9), padCF, rgb(140, 146, 156), M.Metal)
	for r = 0, 2 do
		for c = 0, 2 do
			created += 1
			CityKit.Part(g, "AtmKey", Vector3.new(0.34, 0.06, 0.18), padCF * CFrame.new(-0.45 + c * 0.45, 0.09, -0.26 + r * 0.26), rgb(220, 224, 230), M.SmoothPlastic)
		end
	end
	P("AtmSlot", 0.95, 1.4, 3.05, 3.15, -0.12, 0, IRON, M.SmoothPlastic)
	P("AtmLed", 0.95, 1.4, 3.2, 3.28, -0.1, 0, rgb(80, 230, 140), M.Neon)
	P("AtmCash", -0.8, 0.8, 2.3, 2.45, -0.1, 0, IRON, M.SmoothPlastic)
	local prompt = P("AtmPrompt", -0.5, 0.5, 4.0, 4.6, -0.6, -0.1, WHITE, M.SmoothPlastic)
	prompt.Transparency = 1
	table.insert(out.Spots.ATMs, prompt)
end

----------------------------------------------------------------------
-- HALL
----------------------------------------------------------------------

local function hall(b: any, out: any)
	b:Group("HallFloor")
	-- sol de marbre (plaque de base + bandes + tapis + rosace)
	b:Box("Floor", -HW + 1, HW - 1, FLOOR - 0.1, FLOOR, -FRONT + 1, BACK - 1, MARBLE, M.Marble, true)
	for _, z in ipairs({ -15, -9, -3 }) do
		b:Box("FloorBand", -HW + 1, HW - 1, FLOOR, FLOOR + 0.02, z - 0.25, z + 0.25, MARBLE_VEIN, M.Marble)
	end
	for _, x in ipairs({ -20, -10, 10, 20 }) do
		b:Box("FloorBand", x - 0.25, x + 0.25, FLOOR, FLOOR + 0.02, -FRONT + 1, 3.8, MARBLE_VEIN, M.Marble)
	end
	b:Box("Runner", -3, 3, FLOOR + 0.03, FLOOR + 0.09, -FRONT + 1, 2.4, VELVET, M.Fabric)
	b:Box("RunnerEdge", -3.3, -3, FLOOR + 0.03, FLOOR + 0.08, -FRONT + 1, 2.4, GOLD, M.Fabric)
	b:Box("RunnerEdge", 3, 3.3, FLOOR + 0.03, FLOOR + 0.08, -FRONT + 1, 2.4, GOLD, M.Fabric)
	-- rosace dorée devant les guichets (sur le tapis)
	b:Part("Rosette", Vector3.new(0.04, 5.4, 5.4), CFrame.new(0, FLOOR + 0.11, -6.5) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Metal, "Cyl")
	b:Part("RosetteIn", Vector3.new(0.04, 3.6, 3.6), CFrame.new(0, FLOOR + 0.14, -6.5) * CFrame.Angles(0, 0, math.pi / 2), MARBLE_DARK, M.Marble, "Cyl")
	local rose = b:Sign("RosetteSign", -1.4, 1.4, FLOOR + 0.2, FLOOR + 0.22, -7.9, -5.1)
	label(rose, Enum.NormalId.Top, "💎", WHITE, nil, Enum.Font.GothamBlack, 80, 30)
	-- plinthes dorées + lambris
	b:Group("HallWalls")
	b:Box("Wainscot", -HW + 1, -HW + 1.25, FLOOR, FLOOR + 4.5, -FRONT + 1, 4, MAHOGANY, M.Wood)
	b:Box("Wainscot", HW - 1.25, HW - 1, FLOOR, FLOOR + 4.5, -FRONT + 1, -0.5, MAHOGANY, M.Wood)
	b:Box("WainscotCap", -HW + 1, -HW + 1.45, FLOOR + 4.5, FLOOR + 4.8, -FRONT + 1, 4, GOLD, M.Metal)
	b:Box("WainscotCap", HW - 1.45, HW - 1, FLOOR + 4.5, FLOOR + 4.8, -FRONT + 1, -0.5, GOLD, M.Metal)
	-- (pas de pilastres sur les murs latéraux : boutique de luxe, coffres et distributeurs y sont adossés)
	-- corniche intérieure + caissons du plafond
	b:Box("CrownMould", -HW + 1, HW - 1, ROOF - 0.8, ROOF, -FRONT + 1, -FRONT + 1.8, GOLD_DEEP, M.Metal)
	b:Box("CrownMould", -HW + 1, -HW + 1.8, ROOF - 0.8, ROOF, -FRONT + 1.8, VW, GOLD_DEEP, M.Metal)
	b:Box("CrownMould", HW - 1.8, HW - 1, ROOF - 0.8, ROOF, -FRONT + 1.8, VW, GOLD_DEEP, M.Metal)
	for _, x in ipairs({ -20, -12, 12, 20 }) do
		b:Box("CofferBeam", x - 0.5, x + 0.5, ROOF - 1.2, ROOF, -FRONT + 1.8, VW, WHITE, M.SmoothPlastic)
	end
	for _, z in ipairs({ -16, -1, 6 }) do
		b:Box("CofferBeam", -HW + 1.8, HW - 1.8, ROOF - 1.2, ROOF, z - 0.5, z + 0.5, WHITE, M.SmoothPlastic)
	end
	-- colonnes du hall
	b:Group("HallColumns")
	for _, x in ipairs({ -13, 13 }) do
		for _, z in ipairs({ -15, -5 }) do
			b:Box("HallColBase", x - 1.5, x + 1.5, FLOOR, FLOOR + 1, z - 1.5, z + 1.5, MARBLE_DARK, M.Marble, true)
			b:Col("HallColumn", x, z, FLOOR + 1, ROOF - 2, 2.2, MARBLE, M.Marble, true)
			b:Col("HallColRing", x, z, FLOOR + 4.6, FLOOR + 5.0, 2.4, GOLD, M.Metal)
			b:Box("HallColCap", x - 1.4, x + 1.4, ROOF - 2, ROOF - 1.2, z - 1.4, z + 1.4, GOLD, M.Metal)
		end
	end
	-- lustres de cristal (+ 2 lumières douces)
	b:Group("Chandeliers")
	for i, z in ipairs({ -13, -3 }) do
		local y = ROOF - 7
		b:Col("ChainRod", 0, z, y + 2.2, ROOF - 1.2, 0.18, GOLD, M.Metal)
		b:Col("ChHub", 0, z, y, y + 2.2, 1.0, GOLD, M.Metal)
		for tier = 0, 1 do
			local r = 3.2 - tier * 1.3
			local ty = y + 0.4 + tier * 1.4
			for k = 0, 7 do
				local a = k * math.pi / 4 + tier * 0.4
				local px, pz = math.cos(a) * r, z + math.sin(a) * r
				b:Part("ChArm", Vector3.new(r, 0.14, 0.14), CFrame.new(math.cos(a) * r / 2, ty, z + math.sin(a) * r / 2) * CFrame.Angles(0, -a, 0), GOLD, M.Metal)
				b:Col("ChCup", px, pz, ty, ty + 0.25, 0.45, GOLD, M.Metal)
				CityKit.Glow(b:Col("ChCandle", px, pz, ty + 0.25, ty + 0.9, 0.22, rgb(255, 238, 200), M.SmoothPlastic))
				local crystal = b:Part("ChCrystal", Vector3.new(0.34, 0.6, 0.34), CFrame.new(px, ty - 0.55, pz) * CFrame.Angles(0, a, math.rad(45)), DIAMOND, M.Glass)
				crystal.Transparency = 0.2
			end
		end
		local drop = b:Part("ChDrop", Vector3.new(0.8, 1.6, 0.8), CFrame.new(0, y - 0.9, z) * CFrame.Angles(0, 0, math.rad(45)), DIAMOND, M.Glass)
		drop.Transparency = 0.15
		local light = Instance.new("PointLight")
		light.Name = "ChandelierLight"
		light.Brightness = 0.75
		light.Range = 28
		light.Color = rgb(255, 230, 190)
		light.Shadows = false
		light.Parent = drop
		out.Lights[i] = light
	end
	-- grande horloge sur le mur du coffre (au-dessus de la porte ronde)
	if okClock and type(ClockKit) == "table" then
		local ok, clock = pcall(ClockKit.Build, b.M, b.F * CFrame.new(0, FLOOR + 17.6, VW - 0.5), 4.4, { Style = "Wall", Numerals = "Roman", Brand = "💎", MaxDistance = 140, Name = "BankClock" })
		if ok and clock then
			out.Clock = clock
		end
	end
	-- tableau du COURS DU DIAMANT (écran) sur le mur du coffre, côté gauche
	b:Group("RatesBoard")
	b:Box("RatesFrame", -26.6, -14.4, FLOOR + 12.4, FLOOR + 19.2, VW - 0.5, VW, IRON, M.Metal)
	local rates = b:Box("RatesScreen", -26.2, -14.8, FLOOR + 12.8, FLOOR + 18.8, VW - 0.62, VW - 0.5, rgb(14, 20, 34), M.SmoothPlastic)
	out.Rates = CityKit.Canvas(rates, Enum.NormalId.Front, 140, 22)
	-- panneau "n° appelé" (côté droit)
	b:Box("QueueFrame", 14.4, 26.6, FLOOR + 12.4, FLOOR + 19.2, VW - 0.5, VW, IRON, M.Metal)
	local queue = b:Box("QueueScreen", 14.8, 26.2, FLOOR + 12.8, FLOOR + 18.8, VW - 0.62, VW - 0.5, rgb(14, 20, 34), M.SmoothPlastic)
	out.Queue = CityKit.Canvas(queue, Enum.NormalId.Front, 140, 22)
	-- distributeur de tickets
	b:Group("Ticket")
	b:Box("TicketPost", -6.6, -5.4, FLOOR, FLOOR + 3.6, -8.2, -7.0, IRON, M.Metal, true)
	local tk = b:Box("TicketHead", -7.1, -4.9, FLOOR + 3.6, FLOOR + 5.4, -8.5, -6.7, rgb(36, 52, 112), M.SmoothPlastic)
	local tl = label(tk, Enum.NormalId.Front, "🎫 " .. T("Take a ticket"), WHITE, rgb(36, 52, 112), Enum.Font.GothamBold, 50, 30)
	tl.TextWrapped = true
	b:Box("TicketSlip", -6.3, -5.7, FLOOR + 3.9, FLOOR + 4.0, -8.8, -8.5, WHITE, M.SmoothPlastic)
	-- file d'attente : poteaux dorés + cordons de velours
	b:Group("Queue")
	local posts = {}
	for _, x in ipairs({ -17, -10, -3.6, 3.6, 10, 17 }) do
		table.insert(posts, x)
		b:Col("PostBase", x, -1.2, FLOOR, FLOOR + 0.18, 1.0, GOLD, M.Metal)
		b:Col("Post", x, -1.2, FLOOR + 0.18, FLOOR + 3.0, 0.22, GOLD, M.Metal)
		b:Ball("PostTop", x, FLOOR + 3.1, -1.2, 0.42, GOLD, M.Metal)
	end
	for i = 1, #posts - 1 do
		local a, c = posts[i], posts[i + 1]
		if not (a < 0 and c > 0) then -- passage libre au centre (tapis)
			local n = 4
			for k = 0, n - 1 do
				local t0, t1 = k / n, (k + 1) / n
				local function at(t: number): Vector3
					return Vector3.new(a + (c - a) * t, FLOOR + 2.8 - math.sin(t * math.pi) * 0.7, -1.2)
				end
				local p0, p1 = b.F * at(t0), b.F * at(t1)
				created += 1
				CityKit.Rod(b.Cur, "Rope", p0, p1, 0.16, VELVET, M.Fabric)
			end
		end
	end
	-- bancs d'attente (assise 1,85) face aux guichets
	b:Group("Benches")
	for _, cx in ipairs({ -8, 8 }) do
		local z = -12.5
		b:Box("BenchLeg", cx - 3.4, cx - 3, FLOOR, FLOOR + 1.65, z - 1, z + 1, BRONZE, M.Metal, true)
		b:Box("BenchLeg", cx + 3, cx + 3.4, FLOOR, FLOOR + 1.65, z - 1, z + 1, BRONZE, M.Metal, true)
		b:Box("BenchSeat", cx - 3.6, cx + 3.6, FLOOR + 1.65, FLOOR + 1.85, z - 1.2, z + 1.1, MAHOGANY, M.Wood, true)
		b:Box("BenchCushion", cx - 3.4, cx + 3.4, FLOOR + 1.85, FLOOR + 1.95, z - 1.1, z + 0.9, rgb(36, 72, 56), M.Fabric)
		b:Box("BenchBack", cx - 3.6, cx + 3.6, FLOOR + 1.85, FLOOR + 3.9, z + 1.1, z + 1.4, MAHOGANY, M.Wood, true)
		b:Box("BenchBackCap", cx - 3.7, cx + 3.7, FLOOR + 3.9, FLOOR + 4.1, z + 1.0, z + 1.5, GOLD_DEEP, M.Metal)
	end
	-- palmiers en pot près de l'entrée + table à brochures
	b:Group("Plants")
	for _, sx in ipairs({ -1, 1 }) do
		local x, z = sx * 8.5, -17.5
		b:Col("Pot", x, z, FLOOR, FLOOR + 2.2, 2.2, rgb(64, 60, 70), M.Slate)
		b:Col("PotRim", x, z, FLOOR + 2.2, FLOOR + 2.45, 2.5, GOLD, M.Metal)
		b:Col("PotSoil", x, z, FLOOR + 2.2, FLOOR + 2.3, 2.0, rgb(70, 50, 36), M.Ground)
		b:Col("Trunk", x, z, FLOOR + 2.3, FLOOR + 6.8, 0.45, rgb(120, 92, 60), M.Wood)
		for k = 0, 6 do
			local a = k * math.pi * 2 / 7
			b:Part("Frond", Vector3.new(3.6, 0.12, 1.0), CFrame.new(x + math.cos(a) * 1.5, FLOOR + 6.6, z + math.sin(a) * 1.5) * CFrame.Angles(0, -a, math.rad(-22)), PLANT, M.Grass)
		end
	end
	b:Box("BrochureTable", 5.2, 7.8, FLOOR, FLOOR + 3.0, -10.4, -9.2, MAHOGANY, M.Wood, true)
	for k = 0, 2 do
		b:Part("Brochure", Vector3.new(0.7, 0.9, 0.08), CFrame.new(5.8 + k * 0.7, FLOOR + 3.4, -9.6) * CFrame.Angles(math.rad(-15), 0, 0), ({ GOLD, rgb(36, 52, 112), VELVET })[k + 1], M.SmoothPlastic)
	end
	-- caméras de surveillance (coins hauts)
	b:Group("Cameras")
	for i, spec in ipairs({ { -HW + 1.4, -FRONT + 1.6, 0.6 }, { HW - 1.4, -FRONT + 1.6, -0.6 }, { -HW + 1.4, 3, 2.4 }, { HW - 1.4, 3, -2.4 } }) do
		local x, z, yaw = spec[1], spec[2], spec[3]
		local y = ROOF - 3
		b:Box("CamMount", x - 0.3, x + 0.3, y + 0.2, y + 1.2, z - 0.3, z + 0.3, rgb(220, 222, 226), M.SmoothPlastic)
		local body = b:Part("CamBody", Vector3.new(0.8, 0.8, 1.8), CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-25), 0, 0), rgb(236, 236, 240), M.SmoothPlastic)
		local led = b:Part("CamLed", Vector3.new(0.18, 0.18, 0.06), body.CFrame:ToWorldSpace(CFrame.new(0.25, 0.22, -0.92)) * CFrame.new(), rgb(255, 60, 60), M.Neon)
		led.CFrame = body.CFrame * CFrame.new(0.25, 0.22, -0.92)
		table.insert(out.Cameras, { Body = body, Led = led, Base = CFrame.new(x, y, z), Yaw = yaw, Phase = i * 1.7, F = b.F })
	end
end

----------------------------------------------------------------------
-- GUICHETS + ESPACE DU PERSONNEL
----------------------------------------------------------------------

local function counters(b: any, out: any)
	b:Group("Counters")
	local cz0, cz1 = BankLayout.COUNTER - 1, BankLayout.COUNTER + 1.4 -- 4 .. 6,4
	-- comptoir continu (acajou, panneaux, dessus de marbre)
	b:Box("CounterBody", -21, 21, FLOOR, FLOOR + 3.1, cz0, cz1, MAHOGANY, M.Wood, true)
	b:Box("CounterKick", -21, 21, FLOOR, FLOOR + 0.4, cz0 - 0.15, cz0, MARBLE_DARK, M.Marble)
	for x = -19.5, 19.5, 3 do
		b:Box("CounterPanel", x - 1.1, x + 1.1, FLOOR + 0.8, FLOOR + 2.6, cz0 - 0.12, cz0, MAHOGANY_LIGHT, M.Wood)
	end
	b:Box("CounterTop", -21.2, 21.2, FLOOR + 3.1, FLOOR + 3.3, cz0 - 0.3, cz1 + 0.2, MARBLE, M.Marble, true)
	-- vitres + montants + bandeau à numéros
	local gz = BankLayout.COUNTER + 0.2
	for i = 0, 5 do
		local x = -21 + i * 8.4
		b:Box("CounterPost", x - 0.3, x + 0.3, FLOOR + 3.3, FLOOR + 9.6, gz - 0.3, gz + 0.3, MAHOGANY, M.Wood, true)
	end
	for i = 0, 4 do
		local xa, xb = -21 + i * 8.4 + 0.3, -21 + (i + 1) * 8.4 - 0.3
		local g = b:Box("CounterGlass", xa, xb, FLOOR + 4.0, FLOOR + 9.6, gz - 0.06, gz + 0.06, GLASS, M.Glass, true)
		g.Transparency = 0.6
		b:Box("CounterSlot", xa, xb, FLOOR + 3.3, FLOOR + 4.0, gz - 0.25, gz + 0.25, MAHOGANY_LIGHT, M.Wood)
	end
	b:Box("CounterHeader", -21.4, 21.4, FLOOR + 9.6, FLOOR + 10.8, gz - 0.5, gz + 0.5, MAHOGANY, M.Wood, true)
	b:Box("CounterHeaderTrim", -21.5, 21.5, FLOOR + 10.8, FLOOR + 11.1, gz - 0.6, gz + 0.6, GOLD, M.Metal)
	-- côtés fermés jusqu'aux murs (portillons du personnel)
	for _, sx in ipairs({ -1, 1 }) do
		local xa, xb = sx > 0 and 21 or -HW + 1, sx > 0 and HW - 1 or -21
		b:Box("StaffPartition", xa, xb, FLOOR, FLOOR + 10.8, cz0 + 0.6, cz0 + 1.1, MAHOGANY, M.Wood, true)
		b:Box("PartitionTrim", xa, xb, FLOOR + 10.8, FLOOR + 11.1, cz0 + 0.5, cz0 + 1.2, GOLD, M.Metal)
		local dx = (xa + xb) / 2
		b:Box("StaffGate", dx - 1.8, dx + 1.8, FLOOR + 0.3, FLOOR + 7.6, cz0 + 0.45, cz0 + 0.6, MAHOGANY_LIGHT, M.Wood)
		local priv = b:Sign("PrivateSign", dx - 1.4, dx + 1.4, FLOOR + 5.6, FLOOR + 6.6, cz0 + 0.33, cz0 + 0.43)
		label(priv, Enum.NormalId.Front, T("Staff only"), WHITE, VELVET, Enum.Font.GothamBold, 60, 30)
	end
	-- les 4 guichets : numéro, lampe verte, sonnette, terminal, porte-stylo
	for i = 1, BankLayout.COUNTERS do
		local x = ((BankLayout.COUNTERS + 1) / 2 - i) * 8.5 -- (guichet 1 à gauche vu du hall = +X)
		local num = b:Sign("CounterNumber", x - 1.6, x + 1.6, FLOOR + 9.75, FLOOR + 10.65, gz - 0.62, gz - 0.52)
		label(num, Enum.NormalId.Front, T("Counter %d", i), GOLD, nil, Enum.Font.Garamond, 90, 40)
		CityKit.Glow(b:Box("CounterLamp", x + 2.4, x + 3.2, FLOOR + 9.9, FLOOR + 10.5, gz - 0.75, gz - 0.55, GREEN_LAMP, M.Neon))
		b:Col("Bell", x - 2.2, cz0 + 0.2, FLOOR + 3.3, FLOOR + 3.5, 0.55, GOLD, M.Metal)
		b:Ball("BellTop", x - 2.2, FLOOR + 3.55, cz0 + 0.2, 0.36, GOLD, M.Metal)
		b:Box("CardTerminal", x + 1.6, x + 2.4, FLOOR + 3.3, FLOOR + 3.6, cz0 - 0.1, cz0 + 0.7, IRON, M.SmoothPlastic)
		b:Box("TerminalScreen", x + 1.75, x + 2.25, FLOOR + 3.6, FLOOR + 3.66, cz0 + 0.05, cz0 + 0.4, rgb(80, 210, 160), M.Neon)
		b:Col("PenHolder", x + 0.8, cz0 + 0.1, FLOOR + 3.3, FLOOR + 3.7, 0.4, GOLD, M.Metal)
		b:Part("Pen", Vector3.new(0.08, 0.9, 0.08), CFrame.new(x + 0.8, FLOOR + 3.95, cz0 + 0.1) * CFrame.Angles(0, 0, math.rad(12)), INK, M.SmoothPlastic)
		-- tiroir à billets, côté personnel
		b:Box("TellerDrawer", x - 1.4, x + 1.4, FLOOR + 2.4, FLOOR + 3.0, cz1, cz1 + 0.15, MAHOGANY_LIGHT, M.Wood)
		-- point de l'invite (devant le guichet, côté clients)
		local spot = b:Box("CounterPrompt", x - 0.5, x + 0.5, FLOOR + 3.4, FLOOR + 4.0, cz0 - 0.9, cz0 - 0.4, WHITE, M.SmoothPlastic)
		spot.Transparency = 1
		spot.CastShadow = false
		table.insert(out.Spots.Counters, spot)
	end

	-- ESPACE DU PERSONNEL : parquet, bureaux, écrans, armoires
	b:Group("Staff")
	b:Box("Parquet", -HW + 1, HW - 1, FLOOR, FLOOR + 0.03, cz1, VW, rgb(150, 104, 66), M.WoodPlanks)
	for i = 1, BankLayout.COUNTERS do
		local x = ((BankLayout.COUNTERS + 1) / 2 - i) * 8.5 -- (guichet 1 à gauche vu du hall = +X)
		-- bureau debout derrière le guichetier (devant le rail de la porte ronde)
		b:Box("BackDesk", x - 2.4, x + 2.4, FLOOR, FLOOR + 3.3, 8.0, 9.5, MAHOGANY_LIGHT, M.Wood, true)
		b:Box("Monitor", x - 1.0, x + 1.0, FLOOR + 3.7, FLOOR + 5.1, 8.95, 9.1, IRON, M.SmoothPlastic)
		b:Box("MonitorStand", x - 0.15, x + 0.15, FLOOR + 3.3, FLOOR + 3.7, 9.0, 9.3, IRON, M.SmoothPlastic)
		local scr = b:Box("MonitorScreen", x - 0.9, x + 0.9, FLOOR + 3.8, FLOOR + 5.0, 8.89, 8.95, rgb(60, 120, 200), M.Neon)
		scr.Transparency = 0.15
		b:Box("Keyboard", x - 0.8, x + 0.8, FLOOR + 3.3, FLOOR + 3.38, 8.2, 8.6, rgb(220, 220, 226), M.SmoothPlastic)
	end
	-- armoires de classement + machine à compter + fontaine à eau
	for k = 0, 2 do
		b:Box("FilingCabinet", -HW + 1.2 + k * 2.3, -HW + 3.3 + k * 2.3, FLOOR, FLOOR + 5.2, VW - 1.8, VW, STEEL, M.Metal, true)
		for r = 0, 3 do
			b:Box("CabinetHandle", -HW + 1.9 + k * 2.3, -HW + 2.6 + k * 2.3, FLOOR + 1 + r * 1.2, FLOOR + 1.15 + r * 1.2, VW - 1.9, VW - 1.8, GOLD, M.Metal)
		end
	end
	b:Box("CountingMachine", 22.5, 24.5, FLOOR + 3.3, FLOOR + 4.4, 8.1, 9.3, rgb(210, 214, 220), M.SmoothPlastic)
	b:Box("CountingTable", 21.5, 25.5, FLOOR, FLOOR + 3.3, 7.9, 9.5, MAHOGANY_LIGHT, M.Wood, true)
	b:Box("CashStack", 22.9, 24.1, FLOOR + 4.4, FLOOR + 4.8, 8.4, 9.0, CASH, M.SmoothPlastic)
	b:Col("WaterCooler", 26.6, 7.6, FLOOR, FLOOR + 4.4, 1.4, rgb(230, 232, 236), M.SmoothPlastic, true)
	local jug = b:Col("WaterJug", 26.6, 7.6, FLOOR + 4.4, FLOOR + 5.8, 1.2, rgb(150, 210, 240), M.Glass)
	jug.Transparency = 0.3
end

----------------------------------------------------------------------
-- PORTE RONDE + CHAMBRE FORTE + BUTIN
----------------------------------------------------------------------

local function vault(b: any, out: any)
	b:Group("VaultWall")
	-- mur du coffre (z 13..14) : ouverture 9 x 11 au centre (seuil de 1,2)
	b:WallX("VaultWall", -HW + 1, HW - 1, FLOOR - 0.1, ROOF, VW, VW + 1, { { -4.2, 4.2, FLOOR + 0.2, FLOOR + 11.2 } }, rgb(214, 206, 192), M.Marble)
	b:Box("VaultThreshold", -4.2, 4.2, FLOOR + 0.2, FLOOR + 0.26, VW, VW + 1, STEEL, M.DiamondPlate)
	-- cadre circulaire (20 segments), en retrait de la porte (elle roule devant)
	local ringR = DOOR_R + 0.75
	for k = 0, 19 do
		local a = k * math.pi * 2 / 20
		b:Part("VaultRing", Vector3.new(2.7, 1.3, 0.35), CFrame.new(math.cos(a) * ringR, DOOR_C + math.sin(a) * ringR, VW - 0.225) * CFrame.Angles(0, 0, a + math.pi / 2), STEEL, M.Metal)
	end
	-- rail au sol sur lequel la porte roule (vers +X)
	b:Box("VaultRail", -8, 25.5, FLOOR, FLOOR + 0.08, VW - 2.15, VW - 0.45, STEEL_DARK, M.DiamondPlate)
	b:Box("VaultRailStop", 25.5, 26.2, FLOOR, FLOOR + 1.0, VW - 2.15, VW - 0.45, rgb(230, 190, 40), M.Metal)
	-- LA PORTE (roule le long du mur pendant un casse)
	local door = b:Group("VaultDoor")
	local _ = door
	local parts = {}
	local function add(p: BasePart): BasePart
		table.insert(parts, p)
		return p
	end
	local dz = VW - 1.3
	local slab = add(b:DiscZ("VaultDoorSlab", 0, DOOR_C, dz, 1.8, DOOR_R * 2, rgb(170, 176, 186), M.Metal, true))
	slab:SetAttribute("DoorSolid", true)
	add(b:DiscZ("VaultDoorFace", 0, DOOR_C, dz - 0.92, 0.06, DOOR_R * 2 - 1.2, rgb(190, 196, 206), M.Metal))
	add(b:DiscZ("VaultDoorRing", 0, DOOR_C, dz - 0.97, 0.06, DOOR_R * 2 - 3.4, rgb(150, 156, 166), M.Metal))
	-- verrous tout autour
	for k = 0, 11 do
		local a = k * math.pi * 2 / 12
		add(b:DiscZ("VaultBolt", math.cos(a) * (DOOR_R - 0.9), DOOR_C + math.sin(a) * (DOOR_R - 0.9), dz - 1.0, 0.18, 0.7, GOLD, M.Metal))
	end
	-- volant (moyeu + 3 rayons + poignées)
	add(b:DiscZ("WheelHub", 0, DOOR_C, dz - 1.35, 0.8, 1.6, GOLD, M.Metal))
	local spokes = {}
	for k = 0, 2 do
		local a = k * math.pi / 3
		local s = add(b:Part("WheelSpoke", Vector3.new(6.4, 0.32, 0.32), CFrame.new(0, DOOR_C, dz - 1.6) * CFrame.Angles(0, 0, a), GOLD, M.Metal))
		table.insert(spokes, s)
		for _, sgn in ipairs({ -1, 1 }) do
			local tip = add(b:Ball("WheelKnob", sgn * math.cos(a) * 3.3, DOOR_C + sgn * math.sin(a) * 3.3, dz - 1.6, 0.6, GOLD, M.Metal))
			table.insert(spokes, tip)
		end
	end
	local plate = add(b:Box("VaultPlate", -1.8, 1.8, DOOR_C - 5.4, DOOR_C - 4.4, dz - 1.08, dz - 1.03, GOLD, M.Metal))
	local plateSign = add(b:Sign("VaultPlateSign", -1.7, 1.7, DOOR_C - 5.35, DOOR_C - 4.45, dz - 1.14, dz - 1.1))
	label(plateSign, Enum.NormalId.Front, "💎 " .. T("VAULT"), INK, nil, Enum.Font.Garamond, 60, 40)
	local _ = plate
	-- roule de 16,6 studs vers +X (dégage toute l'ouverture)
	local vd = makeDoor(b.F, CFrame.new(0, DOOR_C, dz), parts, 0)
	vd.Roll = 16.6
	vd.R = DOOR_R
	out.Vault = vd
	out.Wheel = spokes

	-- CHAMBRE FORTE (x -11..11, z 14..25)
	b:Group("VaultRoom")
	b:Box("VaultFloor", -VH, VH, FLOOR, FLOOR + 0.04, VW + 1, BACK - 1, STEEL_DARK, M.DiamondPlate)
	for _, sx in ipairs({ -1, 1 }) do
		b:Box("VaultSide", sx > 0 and VH or -VH - 1, sx > 0 and VH + 1 or -VH, FLOOR - 0.1, FLOOR + 12, VW + 1, BACK - 1, STEEL_DARK, M.Metal, true)
	end
	b:Box("VaultCeiling", -VH - 1, VH + 1, FLOOR + 12, FLOOR + 12.8, VW + 1, BACK - 1, STEEL_DARK, M.Metal, true)
	b:Box("VaultBackLining", -VH, VH, FLOOR, FLOOR + 12, BACK - 1.3, BACK - 1, STEEL, M.Metal)
	-- casiers (coffrets) sur les murs latéraux
	for _, sx in ipairs({ -1, 1 }) do
		local xa = sx > 0 and VH - 0.25 or -VH
		for r = 0, 5 do
			for c = 0, 6 do
				local z = VW + 1.6 + c * 1.35
				local y = FLOOR + 1 + r * 1.6
				b:Box("Locker", xa, xa + 0.25, y, y + 1.4, z, z + 1.2, rgb(196, 168, 96), M.Metal)
				b:Box("LockerKnob", sx > 0 and xa - 0.08 or xa + 0.25, sx > 0 and xa or xa + 0.33, y + 0.6, y + 0.8, z + 0.5, z + 0.7, IRON, M.Metal)
			end
		end
	end
	CityKit.Glow(b:Box("VaultLamp", -6, 6, FLOOR + 11.6, FLOOR + 12, 18.5, 20.5, rgb(255, 246, 220), M.Neon))
	-- 8 PILES DE BUTIN
	local L = BankLayout.LocalPoints()
	for i, p in ipairs(L.Piles) do
		local g = b:Group("LootPile_" .. i)
		local kind = (i - 1) % 3
		b:Box("Pallet", p.X - 1.6, p.X + 1.6, FLOOR + 0.04, FLOOR + 0.6, p.Z - 1.4, p.Z + 1.4, rgb(150, 112, 70), M.WoodPlanks, true)
		if kind == 0 then
			-- pyramide de lingots d'or
			for layer = 0, 2 do
				for k = 0, 2 - layer do
					local x = p.X - (2 - layer) * 0.5 + k * 1.0
					for zz = 0, 1 do
						b:Part("GoldBar", Vector3.new(0.9, 0.5, 1.6), CFrame.new(x, FLOOR + 0.85 + layer * 0.5, p.Z - 0.6 + zz * 1.2 + layer * 0.0), GOLD, M.Metal)
					end
				end
			end
		elseif kind == 1 then
			-- plateau de diamants sur un chariot
			b:Box("Tray", p.X - 1.3, p.X + 1.3, FLOOR + 0.6, FLOOR + 2.6, p.Z - 1.0, p.Z + 1.0, rgb(40, 30, 60), M.Fabric, false)
			for k = 0, 5 do
				local gx = p.X - 0.9 + (k % 3) * 0.9
				local gz = p.Z - 0.45 + math.floor(k / 3) * 0.9
				local gem = b:Part("Diamond", Vector3.new(0.6, 0.6, 0.6), CFrame.new(gx, FLOOR + 3.0, gz) * CFrame.Angles(math.rad(45), math.rad(35), 0), DIAMOND, M.Glass)
				gem.Transparency = 0.1
				table.insert(out.Gems, { Part = gem, Base = gem.CFrame, Phase = i + k })
			end
		else
			-- liasses de billets "💎" (sanglées)
			for k = 0, 5 do
				local x = p.X - 0.7 + (k % 2) * 1.4
				local y = FLOOR + 0.9 + math.floor(k / 2) * 0.62
				b:Box("CashBundle", x - 0.65, x + 0.65, y - 0.3, y + 0.3, p.Z - 1.0, p.Z + 1.0, CASH, M.SmoothPlastic)
				b:Box("CashBand", x - 0.7, x + 0.7, y - 0.34, y + 0.34, p.Z - 0.15, p.Z + 0.15, GOLD, M.SmoothPlastic)
			end
		end
		out.Piles[i] = g
	end
end

----------------------------------------------------------------------
-- BOUTIQUE DE LUXE + SALLE DES COFFRES + DISTRIBUTEURS DU HALL
----------------------------------------------------------------------

local function luxury(b: any, out: any)
	b:Group("Luxury")
	local L = BankLayout.LocalPoints()
	local lp = L.Luxury -- (-20, F, -13) : le client
	-- fond de velours + enseigne
	b:Box("LuxBackdrop", -HW + 1.25, -HW + 1.45, FLOOR + 4.8, FLOOR + 12, -19.5, -7, VELVET, M.Fabric)
	local s = b:Sign("LuxSign", -HW + 1.5, -HW + 1.6, FLOOR + 10, FLOOR + 11.6, -18.5, -8)
	local sl = label(s, Enum.NormalId.Right, "💎 " .. T("Luxury boutique"), GOLD, nil, Enum.Font.Garamond, 120, 30)
	sl.TextStrokeTransparency = 0.5
	-- vitrine-comptoir (verre sur socle doré)
	local cz = lp.Z - 2.4
	b:Box("LuxCounterBase", -25, -15, FLOOR, FLOOR + 1.8, cz - 0.8, cz + 0.8, rgb(30, 26, 34), M.Marble, true)
	b:Box("LuxCounterTrim", -25.1, -14.9, FLOOR + 1.8, FLOOR + 2.0, cz - 0.9, cz + 0.9, GOLD, M.Metal, true)
	local glass = b:Box("LuxCounterGlass", -25, -15, FLOOR + 2.0, FLOOR + 3.3, cz - 0.8, cz + 0.8, GLASS, M.Glass, true)
	glass.Transparency = 0.7
	b:Box("LuxCounterVelvet", -24.8, -15.2, FLOOR + 2.0, FLOOR + 2.06, cz - 0.6, cz + 0.6, rgb(40, 20, 50), M.Fabric)
	-- bijoux posés dans la vitrine
	for k = 0, 4 do
		local x = -24 + k * 2.1
		if k % 2 == 0 then
			local ring = b:Part("Ring", Vector3.new(0.12, 0.7, 0.7), CFrame.new(x, FLOOR + 2.5, cz) * CFrame.Angles(0, math.pi / 2, 0), GOLD, M.Metal, "Cyl")
			local _ = ring
			local gem = b:Part("RingGem", Vector3.new(0.3, 0.3, 0.3), CFrame.new(x, FLOOR + 2.92, cz) * CFrame.Angles(math.rad(45), math.rad(45), 0), DIAMOND, M.Glass)
			table.insert(out.Gems, { Part = gem, Base = gem.CFrame, Phase = k })
		else
			b:Box("Watch", x - 0.35, x + 0.35, FLOOR + 2.1, FLOOR + 2.2, cz - 0.35, cz + 0.35, GOLD, M.Metal)
			b:Box("WatchFace", x - 0.25, x + 0.25, FLOOR + 2.2, FLOOR + 2.24, cz - 0.25, cz + 0.25, WHITE, M.SmoothPlastic)
		end
	end
	-- présentoirs : couronne sur coussin, buste au collier
	local function pedestal(x: number, z: number)
		b:Col("Pedestal", x, z, FLOOR, FLOOR + 3.6, 1.6, MARBLE, M.Marble, true)
		b:Col("PedestalCap", x, z, FLOOR + 3.6, FLOOR + 3.8, 1.9, GOLD, M.Metal)
		local case = b:Box("PedestalGlass", x - 0.9, x + 0.9, FLOOR + 3.8, FLOOR + 6.4, z - 0.9, z + 0.9, GLASS, M.Glass)
		case.Transparency = 0.75
	end
	pedestal(-26.3, -10.2)
	b:Box("Cushion", -26.9, -25.7, FLOOR + 3.8, FLOOR + 4.15, -10.8, -9.6, VELVET, M.Fabric)
	b:Col("CrownBand", -26.3, -10.2, FLOOR + 4.15, FLOOR + 4.65, 1.0, GOLD, M.Metal)
	for k = 0, 5 do
		local a = k * math.pi / 3
		b:Part("CrownPoint", Vector3.new(0.2, 0.55, 0.2), CFrame.new(-26.3 + math.cos(a) * 0.45, FLOOR + 4.9, -10.2 + math.sin(a) * 0.45) * CFrame.Angles(0, -a, math.rad(10)), GOLD, M.Metal)
		local g = b:Part("CrownGem", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-26.3 + math.cos(a) * 0.5, FLOOR + 4.42, -10.2 + math.sin(a) * 0.5) * CFrame.Angles(math.rad(45), a, 0), DIAMOND, M.Glass)
		local _ = g
	end
	pedestal(-16.4, -19.2)
	b:Part("Bust", Vector3.new(1.0, 1.4, 0.7), CFrame.new(-16.4, FLOOR + 4.5, -19.2), rgb(30, 26, 34), M.Fabric, "Egg")
	b:Part("BustNeck", Vector3.new(0.45, 0.7, 0.45), CFrame.new(-16.4, FLOOR + 5.4, -19.2), rgb(30, 26, 34), M.Fabric, "Cyl")
	for k = -4, 4 do
		local a = k * 0.22
		b:Ball("Necklace", -16.4 + math.sin(a) * 0.48, FLOOR + 5.05 - math.cos(a) * 0.12 + 0.12, -19.2 - math.cos(a) * 0.36, 0.16, DIAMOND, M.Glass)
	end
	-- miroir doré
	b:Box("MirrorFrame", -HW + 1.5, -HW + 1.7, FLOOR + 3, FLOOR + 8.6, -7.6, -4.4, GOLD, M.Metal)
	b:Box("Mirror", -HW + 1.7, -HW + 1.76, FLOOR + 3.2, FLOOR + 8.4, -7.4, -4.6, rgb(210, 220, 228), M.Glass).Reflectance = 0.25
	-- invite (devant la vitrine)
	local spot = b:Box("LuxPrompt", lp.X - 0.5, lp.X + 0.5, FLOOR + 3.4, FLOOR + 4.0, cz - 1.4, cz - 0.9, WHITE, M.SmoothPlastic)
	spot.Transparency = 1
	out.Spots.Luxury = spot

	-- SALLE DES COFFRES INDIVIDUELS (mur +X)
	b:Group("Deposit")
	local dp = L.Deposit -- (24, F, -10)
	b:Box("BoxesWall", HW - 1.6, HW - 1.25, FLOOR + 0.6, FLOOR + 11, -19, -1.5, rgb(176, 146, 80), M.Metal, true)
	for r = 0, 6 do
		for c = 0, 10 do
			local z = -18.6 + c * 1.55
			local y = FLOOR + 1.0 + r * 1.42
			local box = b:Box("SafeBox", HW - 1.75, HW - 1.6, y, y + 1.26, z, z + 1.4, rgb(212, 180, 104), M.Metal)
			local _ = box
			if (r + c) % 3 == 0 then
				b:Box("SafeKeyhole", HW - 1.85, HW - 1.75, y + 0.5, y + 0.76, z + 0.6, z + 0.8, IRON, M.Metal)
			end
		end
	end
	local dsign = b:Sign("DepositSign", HW - 1.85, HW - 1.78, FLOOR + 11.2, FLOOR + 12.4, -16, -4.5)
	label(dsign, Enum.NormalId.Left, "🔒 " .. T("Safe deposit boxes"), GOLD, nil, Enum.Font.Garamond, 120, 30)
	-- table d'examen + coffret ouvert
	b:Box("DepositTable", 21, 25, FLOOR, FLOOR + 3.0, -12, -9.6, MAHOGANY, M.Wood, true)
	b:Box("DepositTableTop", 20.8, 25.2, FLOOR + 3.0, FLOOR + 3.2, -12.2, -9.4, MARBLE, M.Marble, true)
	b:Box("OpenBox", 22.2, 23.8, FLOOR + 3.2, FLOOR + 3.9, -11.2, -10.2, rgb(212, 180, 104), M.Metal)
	local bg = b:Part("BoxGem", Vector3.new(0.4, 0.4, 0.4), CFrame.new(23, FLOOR + 4.15, -10.7) * CFrame.Angles(math.rad(45), math.rad(30), 0), DIAMOND, M.Glass)
	table.insert(out.Gems, { Part = bg, Base = bg.CFrame, Phase = 3 })
	-- garde-corps de laiton (3,5) avec passage
	for _, seg in ipairs({ { -19.5, -13.5 }, { -6.5, -1.5 } }) do
		for _, z in ipairs({ seg[1], seg[2] }) do
			b:Col("RailPost", 17, z, FLOOR, FLOOR + 3.5, 0.3, GOLD, M.Metal)
		end
		b:Box("RailBar", 16.88, 17.12, FLOOR + 3.35, FLOOR + 3.55, seg[1], seg[2], GOLD, M.Metal)
		b:Box("RailBar", 16.9, 17.1, FLOOR + 1.6, FLOOR + 1.75, seg[1], seg[2], GOLD, M.Metal)
	end
	local spot2 = b:Box("DepositPrompt", dp.X - 0.5, dp.X + 0.5, FLOOR + 3.4, FLOOR + 4.0, dp.Z - 0.5, dp.Z + 0.5, WHITE, M.SmoothPlastic)
	spot2.Transparency = 1
	out.Spots.Deposit = spot2
end

----------------------------------------------------------------------
-- RUELLE DE SERVICE (+X) : quai, porte du personnel, alarme, plan du casse
----------------------------------------------------------------------

local function alley(b: any, out: any)
	b:Group("Alley")
	local sz = BankLayout.STAFF_DOOR_Z
	-- quai (dessus = plancher du hall) + escalier vers -Z
	b:Box("Dock", HW + 0.4, HW + 5.5, 0.6, FLOOR, sz - 3.5, sz + 3.5, GRANITE, M.Concrete, true)
	for k = 1, 3 do
		local za, zb = sz - 3.5 - (4 - k) * 2, sz - 3.5 - (3 - k) * 2
		b:Box("DockStep", HW + 0.4, HW + 5.5, 0.6, 0.6 + 0.75 * k, za, zb, GRANITE_LIGHT, M.Concrete, true)
	end
	-- garde-corps (3,5) côté ruelle
	for _, z in ipairs({ sz - 3.3, sz + 3.3 }) do
		b:Col("DockRailPost", HW + 5.3, z, FLOOR, FLOOR + 3.5, 0.25, rgb(230, 190, 40), M.Metal)
	end
	b:Box("DockRail", HW + 5.18, HW + 5.42, FLOOR + 3.3, FLOOR + 3.5, sz - 3.3, sz + 3.3, rgb(230, 190, 40), M.Metal)
	b:Box("DockRail", HW + 5.2, HW + 5.4, FLOOR + 1.7, FLOOR + 1.85, sz - 3.3, sz + 3.3, rgb(230, 190, 40), M.Metal)
	-- PORTE DU PERSONNEL (s'ouvre pendant un casse)
	local leaf = b:Box("StaffDoor", HW - 0.75, HW - 0.35, FLOOR, FLOOR + 8.5, sz - 2.25, sz + 2.25, STEEL_DARK, M.Metal, true)
	leaf:SetAttribute("DoorSolid", true)
	local bar = b:Box("StaffDoorBar", HW - 0.35, HW - 0.15, FLOOR + 3.6, FLOOR + 3.9, sz - 1.6, sz + 1.6, STEEL, M.Metal)
	local ds = b:Sign("StaffDoorSign", HW - 0.33, HW - 0.29, FLOOR + 5.8, FLOOR + 6.8, sz - 1.2, sz + 1.2)
	label(ds, Enum.NormalId.Right, T("Staff only"), WHITE, VELVET, Enum.Font.GothamBold, 60, 30)
	out.StaffDoor = makeDoor(b.F, CFrame.new(HW - 0.55, FLOOR, sz + 2.25), { leaf, bar, ds }, math.rad(-95))
	b:Box("StaffDoorFrame", HW, HW + 0.3, FLOOR + 8.5, FLOOR + 9.0, sz - 2.6, sz + 2.6, STEEL, M.Metal)
	-- auvent + lampe
	b:Box("Awning", HW + 0.2, HW + 3.4, FLOOR + 9.6, FLOOR + 9.9, sz - 3, sz + 3, rgb(36, 52, 112), M.Metal)
	CityKit.Glow(b:Box("DockLamp", HW + 0.2, HW + 0.8, FLOOR + 9.0, FLOOR + 9.5, sz - 0.4, sz + 0.4, rgb(255, 236, 190), M.SmoothPlastic))
	-- BOÎTIER D'ALARME (étape "pirater")
	local L = BankLayout.LocalPoints()
	local hz = L.Hack.Z
	b:Box("AlarmBox", HW + 0.4, HW + 1.2, 3.4, 5.8, hz - 0.9, hz + 0.9, rgb(200, 204, 210), M.Metal, true)
	local panel = b:Box("AlarmPanel", HW + 1.2, HW + 1.26, 3.7, 5.5, hz - 0.7, hz + 0.7, rgb(20, 26, 40), M.SmoothPlastic)
	out.AlarmPanel = CityKit.Canvas(panel, Enum.NormalId.Right, 40, 40)
	local led = b:Box("AlarmLed", HW + 1.2, HW + 1.3, 5.9, 6.2, hz - 0.15, hz + 0.15, rgb(255, 60, 60), M.Neon)
	out.AlarmLed = led
	b:Box("AlarmConduit", HW + 0.4, HW + 0.7, 5.8, FLOOR + 9, hz - 0.12, hz + 0.12, rgb(180, 182, 188), M.Metal)
	-- sirène + gyrophares (allumés pendant l'alarme)
	for i, z in ipairs({ -FRONT + 2, BACK - 3 }) do
		b:Box("SirenBox", HW + 0.2, HW + 1.0, ROOF - 4, ROOF - 2.6, z - 0.8, z + 0.8, rgb(230, 230, 236), M.Metal)
		local beacon = b:Part("Beacon", Vector3.new(0.9, 1.0, 1.0), CFrame.new(HW + 1.1, ROOF - 3.3, z) * CFrame.Angles(0, 0, math.rad(90)), rgb(120, 30, 30), M.Glass, "Cyl")
		beacon.Name = "Beacon" .. i
		table.insert(out.Beacons, beacon)
	end
	-- caméra au-dessus de la porte
	local cam = b:Part("AlleyCam", Vector3.new(0.8, 0.8, 1.8), CFrame.new(HW + 0.9, FLOOR + 10.6, sz - 3) * CFrame.Angles(0, math.rad(-120), 0) * CFrame.Angles(math.rad(-25), 0, 0), rgb(236, 236, 240), M.SmoothPlastic)
	table.insert(out.Cameras, { Body = cam, Base = CFrame.new(HW + 0.9, FLOOR + 10.6, sz - 3), Yaw = math.rad(-120), Phase = 0.4, F = b.F })
	-- benne + caisses + palettes
	b:Box("Dumpster", HW + 1.2, HW + 5.6, 0.6, 4.2, 16, 22, rgb(40, 96, 70), M.Metal, true)
	b:Box("DumpsterLid", HW + 1.0, HW + 5.8, 4.2, 4.5, 16, 22, rgb(30, 74, 54), M.Plastic)
	for k = 0, 2 do
		b:Box("Crate", HW + 1.2 + (k % 2) * 2.2, HW + 3.2 + (k % 2) * 2.2, 0.6 + math.floor(k / 2) * 2, 2.6 + math.floor(k / 2) * 2, 13.4, 15.4, rgb(176, 136, 84), M.WoodPlanks, true)
	end
	-- MUR DE BRIQUES de la ruelle (côté extérieur), entrée par le parvis
	local brick = rgb(150, 78, 58)
	b:Box("AlleyWall", ALLEY - 0.8, ALLEY, 0.6, 6.2, -BankLayout.PORTICO + 2, BACK + 2, brick, M.Brick, true)
	b:Box("AlleyWallCap", ALLEY - 0.95, ALLEY + 0.15, 6.2, 6.5, -BankLayout.PORTICO + 2, BACK + 2, STONE_DARK, M.Limestone)
	b:Box("AlleyPier", ALLEY - 1.1, ALLEY + 0.2, 0.6, 7.4, -BankLayout.PORTICO + 1.4, -BankLayout.PORTICO + 2.6, brick, M.Brick, true)
	b:Box("AlleyPierCap", ALLEY - 1.25, ALLEY + 0.35, 7.4, 7.7, -BankLayout.PORTICO + 1.25, -BankLayout.PORTICO + 2.75, STONE_DARK, M.Limestone)
	-- applique (lampe de ruelle) + tuyau
	CityKit.Glow(b:Box("AlleyLamp", ALLEY - 1.5, ALLEY - 0.8, 5.0, 5.6, 4, 4.8, rgb(255, 230, 176), M.SmoothPlastic))
	b:Box("AlleyLampArm", ALLEY - 1.6, ALLEY - 0.8, 5.6, 5.8, 4.2, 4.6, IRON, M.Metal)
	-- PLAN DU CASSE : grand plan bleu fixé au mur de briques (rendez-vous de l'équipe)
	local lo = L.Lobby -- (32.3, 0.6, -14)
	b:Group("HeistBoard")
	local bx = ALLEY - 0.8
	b:Box("BoardFrame", bx - 0.2, bx, 1.6, 6.0, lo.Z - 3.2, lo.Z + 3.2, rgb(120, 86, 50), M.Wood, true)
	local board = b:Box("Blueprint", bx - 0.3, bx - 0.2, 1.8, 5.8, lo.Z - 3.0, lo.Z + 3.0, rgb(26, 70, 140), M.SmoothPlastic)
	out.Board = CityKit.Canvas(board, Enum.NormalId.Left, 80, 40)
	b:Box("BoardLight", bx - 0.9, bx - 0.2, 6.0, 6.3, lo.Z - 1.4, lo.Z + 1.4, IRON, M.Metal)
	b:Box("BoardShelf", bx - 0.7, bx - 0.2, 1.4, 1.6, lo.Z - 3.0, lo.Z + 3.0, rgb(120, 86, 50), M.Wood)
	-- caisses-sièges + boîte à outils + lampe de chantier
	b:Box("ToolBox", bx - 1.8, bx - 0.6, 0.6, 1.4, lo.Z + 3.0, lo.Z + 4.4, rgb(210, 40, 40), M.Metal, true)
	b:Box("ToolBoxHandle", bx - 1.3, bx - 1.1, 1.4, 1.7, lo.Z + 3.2, lo.Z + 4.2, IRON, M.Metal)
	b:Box("SeatCrate", HW + 1, HW + 2.8, 0.6, 2.4, lo.Z - 1, lo.Z + 1, rgb(176, 136, 84), M.WoodPlanks, true)
	local lobbySpot = b:Box("LobbyPrompt", lo.X - 0.5, lo.X + 0.5, 3.0, 3.6, lo.Z - 0.5, lo.Z + 0.5, WHITE, M.SmoothPlastic)
	lobbySpot.Transparency = 1
	out.Spots.Lobby = lobbySpot
	local hackSpot = b:Box("HackPrompt", HW + 1.3, HW + 1.8, 4.2, 4.8, hz - 0.3, hz + 0.3, WHITE, M.SmoothPlastic)
	hackSpot.Transparency = 1
	out.Spots.Hack = hackSpot
	-- graffiti-pochoir (cartoon) au mur
	local graf = b:Sign("Stencil", HW + 0.42, HW + 0.46, 2.0, 6.0, lo.Z + 6, lo.Z + 11)
	label(graf, Enum.NormalId.Right, "🕶️💰", WHITE, nil, Enum.Font.GothamBlack, 60, 20).TextTransparency = 0.35

	-- JARDINET (-X) : haies, banc, petits arbres
	b:Group("Garden")
	CityKit.Hedge(b.Cur, b.F * CFrame.new(-ALLEY + 1.2, 0.6, 0) * CFrame.Angles(0, math.pi / 2, 0), 44, 2.6, 1.8, 7)
	created += 18
	for _, z in ipairs({ -16, 14 }) do
		b:Col("TreeTrunk", -HW - 3.2, z, 0.6, 8, 0.7, rgb(110, 84, 58), M.Wood, true)
		b:Ball("TreeCrown", -HW - 3.2, 9.6, z, 5.2, rgb(70, 132, 66), M.Grass)
		b:Ball("TreeCrown2", -HW - 2.6, 8.4, z + 1.4, 3.6, rgb(84, 146, 72), M.Grass)
	end
end

----------------------------------------------------------------------
-- PNJ (guichetiers, bijoutier, gardien, clients)
----------------------------------------------------------------------

local function npc(parent: Instance, style: string, seed: number, cf: CFrame, shirt: Color3?, prop: string?): Model?
	if not okNpc or type(NPCModels) ~= "table" then
		return nil
	end
	local ok, model = pcall(function()
		return NPCModels.Build(style, { Seed = seed, Shirt = shirt, Prop = prop or "none" })
	end)
	if not ok or not model then
		return nil
	end
	model.Parent = parent
	model:PivotTo(cf)
	return model
end

local function people(b: any, out: any)
	local g = b:Group("People")
	for i = 1, BankLayout.COUNTERS do
		local x = ((BankLayout.COUNTERS + 1) / 2 - i) * 8.5 -- (guichet 1 à gauche vu du hall = +X)
		local m = npc(g, "cashier", 300 + i, b.F * CFrame.new(x, FLOOR, BankLayout.COUNTER + 2.2), ({ rgb(36, 52, 112), WHITE, rgb(60, 60, 70), rgb(120, 30, 50) })[i])
		if m then
			table.insert(out.Npcs, { Model = m, Anim = (i % 2 == 0) and "type" or "talk", Phase = i * 1.3 })
		end
	end
	local jeweler = npc(g, "salesperson", 411, b.F * CFrame.new(-20, FLOOR, -17.6) * CFrame.Angles(0, math.pi, 0), rgb(30, 26, 34))
	if jeweler then
		table.insert(out.Npcs, { Model = jeweler, Anim = "talk", Phase = 0.7 })
	end
	local guard = npc(g, "worker", 512, b.F * CFrame.new(7.5, FLOOR, -17.2) * CFrame.Angles(0, math.rad(200), 0), rgb(30, 40, 70))
	if guard then
		table.insert(out.Npcs, { Model = guard, Anim = "idle", Phase = 2.1 })
	end
	-- clients : un dans la file (guichet 2), deux assis
	local client = npc(g, "shopper", 613, b.F * CFrame.new(-4.25, FLOOR, 2.0) * CFrame.Angles(0, math.pi, 0), nil, "bag")
	if client then
		table.insert(out.Npcs, { Model = client, Anim = "talk", Phase = 1.9 })
	end
	for k, x in ipairs({ -9.5, 9 }) do
		local sitter = npc(g, k == 1 and "elder" or "pedestrian", 700 + k, b.F * CFrame.new(x, FLOOR, -12.6) * CFrame.Angles(0, math.pi, 0), nil, k == 2 and "phone" or "none")
		if sitter then
			table.insert(out.Npcs, { Model = sitter, Anim = "sit", Phase = k * 2.3 })
		end
	end
end

----------------------------------------------------------------------
-- Perceuse du casse (montrée pendant l'étape "percer")
----------------------------------------------------------------------

local function drill(b: any, out: any)
	local g = b:Group("HeistDrill")
	local z = VW - 3.4
	local parts = {}
	local function add(p: BasePart)
		table.insert(parts, p)
		p.Transparency = 1
	end
	-- trépied + corps jaune + mèche
	for _, a in ipairs({ 0, 2.1, 4.2 }) do
		add(b:Part("DrillLeg", Vector3.new(0.25, 4.6, 0.25), CFrame.new(math.cos(a) * 1.2 - 2.2, FLOOR + 2.2, z - 0.6 + math.sin(a) * 1.2) * CFrame.Angles(math.sin(a) * 0.3, 0, math.cos(a) * 0.3), IRON, M.Metal))
	end
	add(b:Part("DrillBody", Vector3.new(1.8, 1.8, 3.2), CFrame.new(-2.2, FLOOR + 4.6, z), rgb(255, 196, 30), M.SmoothPlastic))
	add(b:Part("DrillMotor", Vector3.new(1.4, 1.4, 1.2), CFrame.new(-2.2, FLOOR + 4.6, z - 2.0), IRON, M.Metal, "Cyl"))
	local bit = b:Part("DrillBit", Vector3.new(0.3, 0.3, 2.6), CFrame.new(-2.2, FLOOR + 4.6, z + 2.4), STEEL, M.Metal)
	add(bit)
	local stripe = b:Part("DrillStripe", Vector3.new(1.84, 0.4, 3.24), CFrame.new(-2.2, FLOOR + 4.6, z), INK, M.SmoothPlastic)
	add(stripe)
	out.Drill = { Model = g, Parts = parts, Bit = bit, BitBase = bit.CFrame }
end

----------------------------------------------------------------------
-- Construction complète
----------------------------------------------------------------------

function BankBuild.Build(parent: Instance, F: CFrame): any
	local before = created
	local b = new(parent, F, "DopamineBank")
	local out = {
		Model = b.M,
		F = F,
		Spots = { Counters = {}, ATMs = {} },
		Cameras = {},
		Npcs = {},
		Piles = {},
		Gems = {},
		Flags = {},
		Beacons = {},
		Screens = {},
		Lights = {},
	}
	exterior(b, out)
	shell(b, out)
	hall(b, out)
	counters(b, out)
	vault(b, out)
	luxury(b, out)
	alley(b, out)
	drill(b, out)
	-- distributeurs (façade : 2, hall : 2)
	local L = BankLayout.LocalPoints()
	for i, p in ipairs(L.ATMs) do
		local cf
		if p.Z < -FRONT then
			-- dos contre la façade, écran vers la rue
			cf = CFrame.new(p.X, FLOOR, -FRONT - 1.7)
		else
			-- dos contre le mur ouest (-X), écran vers +X
			cf = CFrame.new(-HW + 1.25 + 1.7, FLOOR, p.Z) * CFrame.Angles(0, -math.pi / 2, 0)
		end
		atm(b, out, cf, i)
	end
	-- lumière d'alarme (rouge, éteinte)
	local alarmHost = b:Box("AlarmLightHost", -0.2, 0.2, ROOF - 2.2, ROOF - 1.8, -6.2, -5.8, WHITE, M.SmoothPlastic)
	alarmHost.Transparency = 1
	local alarm = Instance.new("PointLight")
	alarm.Name = "AlarmLight"
	alarm.Color = rgb(255, 50, 50)
	alarm.Brightness = 0
	alarm.Range = 40
	alarm.Enabled = false
	alarm.Shadows = false
	alarm.Parent = alarmHost
	out.AlarmLight = alarm
	people(b, out)
	out.PartCount = created - before
	return out
end

-- Silhouette lointaine (~30 pièces, aucune collision)
function BankBuild.BuildLow(parent: Instance, F: CFrame): Model
	local b = new(parent, F, "DopamineBankLow")
	b:Box("LowPodium", -HW, HW, 0, FLOOR, -BankLayout.PORTICO, BACK, STONE_DARK, M.Limestone)
	b:Box("LowSteps", -20, 20, 0.6, FLOOR - 0.8, -BankLayout.STEPS_END, -BankLayout.PORTICO, STONE, M.Limestone)
	b:Box("LowBody", -HW, HW, FLOOR, ROOF + 1, -FRONT, BACK, STONE, M.Limestone)
	b:Box("LowCornice", -HW - 0.8, HW + 0.8, ROOF + 1, ROOF + 2.4, -FRONT - 0.8, BACK + 0.8, STONE_DARK, M.Limestone)
	b:Box("LowAttic", -HW, HW, ROOF + 2.4, ROOF + 4.2, -FRONT, BACK, STONE, M.Limestone)
	for _, x in ipairs(WINDOW_X) do
		b:Box("LowWindow", x - 2.4, x + 2.4, FLOOR + 5, FLOOR + 17, -FRONT - 0.1, -FRONT, rgb(70, 96, 120), M.Glass)
	end
	b:Box("LowDoor", -5, 5, FLOOR, FLOOR + 14, -FRONT - 0.1, -FRONT, BRONZE, M.Metal)
	for _, x in ipairs({ -23, -15, -7, 7, 15, 23 }) do
		b:Col("LowColumn", x, -FRONT - 2.6, FLOOR, FLOOR + 19.6, 2.8, MARBLE, M.Marble)
	end
	b:Box("LowEntablature", -27.5, 27.5, FLOOR + 19.6, FLOOR + 23.9, -BankLayout.PORTICO, -FRONT, STONE, M.Limestone)
	b:Wedge("LowPediment", Vector3.new(5, 7, 27.4), CFrame.new(13.7, FLOOR + 27.4, -BankLayout.PORTICO + 2.5) * CFrame.Angles(0, -math.pi / 2, 0), STONE, M.Limestone)
	b:Wedge("LowPediment", Vector3.new(5, 7, 27.4), CFrame.new(-13.7, FLOOR + 27.4, -BankLayout.PORTICO + 2.5) * CFrame.Angles(0, math.pi / 2, 0), STONE, M.Limestone)
	local sign = b:Sign("LowName", -18, 18, FLOOR + 20.6, FLOOR + 22.6, -BankLayout.PORTICO - 0.12, -BankLayout.PORTICO - 0.02)
	label(sign, Enum.NormalId.Front, T("DOPAMINE BANK"), GOLD, nil, Enum.Font.Garamond, 900, 8)
	for _, p in ipairs(b.M:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CastShadow = false
		end
	end
	return b.M
end

----------------------------------------------------------------------
-- Animation / états
----------------------------------------------------------------------

function BankBuild.Animate(bank: any, t: number, _dt: number)
	-- caméras qui balaient (±35°) + LED qui clignote
	for _, c in ipairs(bank.Cameras) do
		local yaw = c.Yaw + math.sin(t * 0.45 + c.Phase) * math.rad(35)
		c.Body.CFrame = c.F * c.Base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-25), 0, 0)
		if c.Led then
			c.Led.CFrame = c.Body.CFrame * CFrame.new(0.25, 0.22, -0.92)
			c.Led.Transparency = (math.floor(t * 1.5 + c.Phase) % 2 == 0) and 0 or 0.7
		end
	end
	-- diamants qui tournent doucement
	for _, gem in ipairs(bank.Gems) do
		if gem.Part.Parent then
			gem.Part.CFrame = CFrame.new(gem.Base.Position + Vector3.new(0, math.sin(t * 1.4 + gem.Phase) * 0.06, 0)) * CFrame.Angles(0, t * 0.9 + gem.Phase, 0) * gem.Base.Rotation
		end
	end
	-- drapeaux (ondulation)
	for _, f in ipairs(bank.Flags) do
		local a = math.sin(t * 1.7 + f.Sx) * 0.12
		local rel = f.Pivot:ToObjectSpace(f.Base)
		local cf = f.Pivot * CFrame.Angles(0, a, 0) * rel
		f.Part.CFrame = cf
		f.Back.CFrame = cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 0.001)
	end
	-- personnages
	for _, n in ipairs(bank.Npcs) do
		if n.Model.Parent then
			pcall(function()
				NPCModels.Animate(n.Model, n.Anim, t + n.Phase)
			end)
		end
	end
	if bank.Clock and okClock then
		pcall(ClockKit.Update, bank.Clock)
	end
end

function BankBuild.SetPileTaken(bank: any, i: number, taken: boolean)
	local g = bank.Piles[i]
	if not g then
		return
	end
	for _, p in ipairs(g:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Pallet" then
			p.Transparency = taken and 1 or (p.Name == "Diamond" and 0.1 or 0)
		end
	end
end

function BankBuild.SetDrill(bank: any, visible: boolean, progress: number, jammed: boolean, t: number)
	local d = bank.Drill
	if not d then
		return
	end
	for _, p in ipairs(d.Parts) do
		p.Transparency = visible and 0 or 1
	end
	if visible then
		-- la mèche avance avec le progrès et tourne (sauf bloquée : elle tremble)
		local wobble = jammed and math.sin(t * 40) * 0.05 or 0
		d.Bit.CFrame = d.BitBase * CFrame.new(wobble, 0, math.clamp(progress, 0, 1) * 0.6) * CFrame.Angles(0, 0, jammed and 0 or t * 25)
	end
end

function BankBuild.SetAlarm(bank: any, on: boolean, t: number)
	if bank.AlarmLight then
		bank.AlarmLight.Enabled = on
		bank.AlarmLight.Brightness = on and (0.4 + 0.4 * math.abs(math.sin(t * 4))) or 0
	end
	for i, b in ipairs(bank.Beacons) do
		local blink = on and (math.floor(t * 4 + i) % 2 == 0)
		b.Material = blink and Enum.Material.Neon or Enum.Material.Glass
		b.Color = blink and rgb(255, 50, 50) or rgb(120, 30, 30)
	end
	if bank.AlarmLed then
		bank.AlarmLed.Color = on and rgb(255, 40, 40) or rgb(60, 220, 120)
	end
end

function BankBuild.Count(): number
	return created
end

return BankBuild
