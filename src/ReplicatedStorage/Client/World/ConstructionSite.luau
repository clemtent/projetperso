--[[
	ConstructionSite (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ConstructionSite

	🏗️ v10 (CONSTRUCT10) : un CHANTIER sur une parcelle sans propriétaire
	(côté client, en flux ; piloté par HouseConstruction).
	  - terrain de terre battue avec traces de pneus, allée de gravier ;
	  - palissade pleine côté rue (bâches "Bientôt ta maison ici !") avec
	    une entrée, clôture grillagée sur plots béton autour ;
	  - grand panneau "🏗️ Bientôt ta maison ici !" face à la rue ;
	  - maison en cours : dalle, murs de briques montés en escalier, poteaux,
	    plancher de l'étage, ossature bois, étais, fers en attente,
	    échafaudage avec filet ;
	  - grue à tour qui tourne LENTEMENT et livre des palettes (même cycle
	    pour tous les joueurs : heure du serveur) ;
	  - pelleteuse qui creuse une tranchée et vide son godet sur un tas ;
	  - palettes de briques, bois, poutrelles, sable, ciment, bétonnière
	    qui tourne, toilettes de chantier, bungalow, cônes, tréteau ;
	  - ouvriers (NPCModels "worker", casque + gilet) : l'un tape au
	    marteau, un autre porte des cartons de carrelage, un troisième pousse
	    un chariot de briques, le chef de chantier sur sa tablette, le
	    conducteur dans la pelleteuse.
	Niveaux de détail : 2 = complet (près), 1 = silhouette (~20 pièces :
	grue simplifiée qui tourne aussi, clôture, maison en cours), 0 = rien.
	Les ouvriers n'existent que tout près ; tout s'anime seulement à portée.

	API :
	  ConstructionSite.new(plotCF, opts) -> Site
	    opts : { Parent, Seed, Style?, PlotW?, PlotD? , Appear? }
	  site:SetLevel(level)          (0 | 1 | 2 ; construit / retire)
	  site:Step(now, dt, camPos)    (animations, à chaque image)
	  site:Clear(keepCrane) -> crane? (fondu + enfoncement ~1,2 s, puis détruit ;
	                                    keepCrane : la grue est rendue à l'appelant)
	  site:Destroy() ; site.Parts (compte) ; site.Level ; site.Done
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Kit = require(script.Parent.ConstructionKit)

local ConstructionSite = {}
ConstructionSite.__index = ConstructionSite

local M = Kit.M
local C = Kit.C
local P = Kit.Part
local rgb = Color3.fromRGB

local WORKER_RANGE = 150 -- (studs, x DetailScale) les ouvriers existent plus près que ça
local ANIM_RANGE = 110 -- ils bougent plus près que ça
local MACHINE_RANGE = 260 -- pelleteuse / bétonnière animées
local CLEAR_TIME = 1.25

-- NPCModels (facultatif : jamais bloquant)
local NPC: any = nil
local npcTried = false
local function npcModels(): any
	if not npcTried then
		npcTried = true
		local module = ReplicatedStorage.Shared:FindFirstChild("NPCModels")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				NPC = result
			end
		end
	end
	return NPC
end

-- Taille "maison type" du quartier (pour la maison en cours)
local function styleWidth(style: string?): number
	local ok, width = pcall(function()
		local Config = require(ReplicatedStorage.Shared.Config) :: any
		for _, def in ipairs(Config.House.Sizes) do
			if def.Exterior == style then
				return WorldLayout.Dims(def).Width
			end
		end
		return WorldLayout.Dims(Config.House.Sizes[1]).Width
	end)
	return if ok and type(width) == "number" then width else 70
end

local function T(text: string): string
	local ok, value = pcall(Locale.T, text)
	return if ok and type(value) == "string" then value else text
end

export type Site = typeof(setmetatable({} :: {
	PlotCF: CFrame,
	Ground: CFrame,
	Seed: number,
	Level: number,
	Folder: Model?,
	Parts: number,
	[string]: any,
}, ConstructionSite))

function ConstructionSite.new(plotCF: CFrame, opts: any): Site
	local o = opts or {}
	local plotW = tonumber(o.PlotW) or WorldLayout.PLOT_W
	local plotD = tonumber(o.PlotD) or WorldLayout.PLOT_D
	local seed = tonumber(o.Seed) or 1
	local ground = plotCF * CFrame.new(0, WorldLayout.GROUND_Y + 0.05, 0)
	local wf = math.clamp(styleWidth(o.Style), 50, math.max(50, plotW - 70))
	local front = -WorldLayout.HouseFrontOffset() -- façade (vers la rue = -Z)
	local self = setmetatable({
		PlotCF = plotCF,
		Ground = ground,
		Seed = seed,
		Level = 0,
		Folder = nil,
		Parts = 0,
		Parent = o.Parent or workspace,
		Name = o.Name or "Site",
		Wf = wf,
		Front = front,
		Back = front + WorldLayout.DEPTH + 2 * WorldLayout.WALL_T,
		-- clôture du chantier : tout le tour de la parcelle (v10 : plus de
		-- clôture de parcelle côté serveur), 6 studs derrière le bord côté rue
		XL = -(plotW / 2 - 3),
		XR = plotW / 2 - 3,
		ZF = -(plotD / 2 - 6),
		ZB = plotD / 2 - 3,
		Crane = nil,
		Excavator = nil,
		Drum = nil,
		DrumCF = nil,
		Workers = {},
		WorkersBuilt = false,
		Clearing = nil,
		Appear = o.Appear == true,
		AppearAt = 0,
		Done = false,
		CraneKeys = nil,
		LiteClock = 0,
	}, ConstructionSite)
	self.FloorTop = WorldLayout.FloorY(1) - WorldLayout.GROUND_Y - 0.05 -- dessus de la dalle (repère du sol)
	return self
end

-- Repère du sol du chantier : (x, y, z) avec -Z vers la rue
function ConstructionSite.At(self: Site, x: number, y: number, z: number): CFrame
	return self.Ground * CFrame.new(x, y, z)
end

----------------------------------------------------------------------
-- Construction : niveau 1 (silhouette) et niveau 2 (complet)
----------------------------------------------------------------------

local function box(self: Site, parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, opts: any?): BasePart
	return Kit.Box(parent, name, self.Ground, x0, x1, y0, y1, z0, z1, color, material, opts)
end

-- Grue : cycle (prise sur la palette près du mât, dépose sur le plancher)
local function craneKeys(self: Site, crane: any, pick: Vector3, drop: Vector3)
	local base = crane.Top * CFrame.new(0, -crane.Height, 0)
	local function key(p: Vector3, bottomY: number): { number }
		local rel = base:PointToObjectSpace(p)
		local angle = math.atan2(-rel.X, -rel.Z)
		local radius = math.sqrt(rel.X * rel.X + rel.Z * rel.Z) - 1.2
		local trolleyY = crane.Height + (crane.JibY or 3.2) - 0.45
		local blockY = bottomY + 4.8
		return { angle, radius, trolleyY - 0.6 - blockY }
	end
	local a = key(pick, base:PointToObjectSpace(pick).Y + 0.1)
	local b = key(drop, base:PointToObjectSpace(drop).Y + 0.1)
	self.CraneKeys = { A = a, B = b, High = 7 }
end

function ConstructionSite.BuildLite(self: Site)
	local folder = Instance.new("Model")
	folder.Name = self.Name .. "_Lite"
	local wf, f, b = self.Wf, self.Front, self.Back
	local ft = self.FloorTop
	box(self, folder, "Dirt", self.XL, self.XR, -0.25, 0.1, self.ZF, self.ZB, C.Dirt, M.Ground, { Shadow = false })
	box(self, folder, "Hoarding", self.XL, self.XR, 0.1, 6, self.ZF - 0.3, self.ZF, rgb(250, 236, 244), M.SmoothPlastic)
	for _, x in ipairs({ self.XL, self.XR }) do
		box(self, folder, "Fence", x - 0.1, x + 0.1, 0.1, 6, self.ZF, self.ZB, C.Steel, M.Metal, { Alpha = 0.55, Shadow = false })
	end
	box(self, folder, "Fence", self.XL, self.XR, 0.1, 6, self.ZB - 0.1, self.ZB + 0.1, C.Steel, M.Metal, { Alpha = 0.55, Shadow = false })
	box(self, folder, "Slab", -wf / 2 - 0.5, wf / 2 + 0.5, -0.3, ft, f - 0.5, b + 0.5, C.Concrete, M.Concrete)
	box(self, folder, "Walls", -wf / 2, -wf * 0.05, ft, ft + 12, b - 1, b, C.Brick, M.Brick)
	box(self, folder, "Walls", -wf / 2, -wf / 2 + 1, ft, ft + 12, f + 0.5, b - 1, C.Brick, M.Brick)
	box(self, folder, "Upper", -wf / 2, wf / 2, ft + 12, ft + 13, f - 0.5, b + 0.5, C.ConcreteDark, M.Concrete)
	box(self, folder, "Scaffold", -wf / 2, wf * 0.12, 0.1, ft + 14, f - 4.4, f - 1, C.Orange, M.Fabric, { Alpha = 0.45, Shadow = false })
	box(self, folder, "Office", -wf / 2 - 5, -wf / 2 + 13, 0.1, 8, b + 7, b + 14.8, C.Office, M.Metal)
	local craneBase = self:At(math.min(wf / 2 + 8, self.XR - 5), 0, b + 10)
	self.LiteCrane = Kit.Crane(folder, craneBase, { Lite = true })
	folder.Parent = self.Parent
	self.Folder = folder
	self.Crane = self.LiteCrane
	craneKeys(self, self.Crane, (self:At(wf / 2 + 8, 0, b - 2)).Position, (self:At(wf / 4, ft + 13, (f + b) / 2)).Position)
end

function ConstructionSite.BuildFull(self: Site)
	local folder = Instance.new("Model")
	folder.Name = self.Name
	local seed = self.Seed
	local wf, f, b = self.Wf, self.Front, self.Back
	local ft = self.FloorTop
	local xl, xr, zf, zb = self.XL, self.XR, self.ZF, self.ZB
	-- === terrain ===
	box(self, folder, "Dirt", xl, xr, -0.25, 0.1, zf, zb, C.Dirt, M.Ground, { Shadow = false, Solid = true })
	box(self, folder, "Gravel", -7, 6, -0.02, 0.14, zf, f - 0.6, rgb(150, 142, 132), M.Pebble, { Shadow = false })
	for _, x in ipairs({ -5.2, 4.2 }) do
		box(self, folder, "TyreTrack", x - 0.9, x + 0.9, -0.02, 0.17, zf + 0.5, f - 1.5, C.DirtDark, M.Ground, { Shadow = false })
	end
	-- === palissade côté rue (entrée au milieu) + clôture grillagée ===
	local gate0, gate1 = -7, 6
	local banner = T("Coming soon: your house here!")
	for _, span in ipairs({ { xl, gate0 }, { gate1, xr } }) do
		local a, bb = span[1], span[2]
		local panel = box(self, folder, "Hoarding", a, bb, 0.1, 6.4, zf - 0.35, zf, rgb(250, 240, 246), M.SmoothPlastic, { Solid = true })
		box(self, folder, "HoardingCap", a, bb, 6.4, 6.7, zf - 0.45, zf + 0.1, C.SteelDark, M.Metal, { Shadow = false })
		local count = math.max(1, math.floor((bb - a) / 10.5))
		for k = 0, count do
			local x = a + k * (bb - a) / count
			box(self, folder, "HoardingPost", x - 0.2, x + 0.2, 0.1, 6.5, zf + 0.02, zf + 0.42, C.TimberDark, M.Wood, { Shadow = false })
		end
		-- bâche imprimée (face rue)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 12
		gui.LightInfluence = 1
		gui.MaxDistance = 160
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = rgb(255, 244, 250)
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(rgb(255, 214, 236), rgb(214, 196, 255))
		grad.Parent = bg
		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0.14, 0)
		band.Position = UDim2.fromScale(0, 0.86)
		band.BackgroundColor3 = rgb(250, 196, 30)
		band.BorderSizePixel = 0
		band.Parent = bg
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.03, 0.18)
		label.Size = UDim2.fromScale(0.94, 0.55)
		label.Text = "🏗️ " .. banner .. "  ·  🏠 Dopamine Town"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = rgb(200, 60, 130)
		label.Parent = bg
		gui.Parent = panel
	end
	-- grillage (côtés + fond) : panneaux 10,5 sur plots béton
	local function heras(a: Vector3, bpos: Vector3)
		local length = (bpos - a).Magnitude
		local dir = (bpos - a).Unit
		local count = math.max(1, math.floor(length / 10.5 + 0.5))
		local base = CFrame.lookAt(a, bpos)
		P(folder, "FenceMesh", Vector3.new(0.08, 5.4, length), base * CFrame.new(0, 3.2, -length / 2), C.Steel, M.Metal, { Alpha = 0.62, Solid = true, Shadow = false })
		for _, y in ipairs({ 0.55, 5.9 }) do
			P(folder, "FenceRail", Vector3.new(0.14, 0.14, length), base * CFrame.new(0, y, -length / 2), C.Steel, M.Metal, { Shadow = false })
		end
		for k = 0, count do
			local p = a + dir * (k * length / count)
			local cf = CFrame.lookAt(p, p + dir)
			P(folder, "FencePost", Vector3.new(0.2, 6.1, 0.2), cf * CFrame.new(0, 3.05 + 0.25, 0), C.Steel, M.Metal, { Shadow = false })
			P(folder, "FenceFoot", Vector3.new(0.9, 0.5, 2.2), cf * CFrame.new(0, 0.25, 0), C.ConcreteDark, M.Concrete, { Shadow = false })
		end
	end
	heras((self:At(xl, 0, zf + 0.5)).Position, (self:At(xl, 0, zb)).Position)
	heras((self:At(xl, 0, zb)).Position, (self:At(xr, 0, zb)).Position)
	heras((self:At(xr, 0, zb)).Position, (self:At(xr, 0, zf + 0.5)).Position)
	-- === grand panneau face à la rue ===
	local title = Kit.Billboard(folder, self:At(math.min(wf / 2 - 4, xr - 9), 0, zf - 1.6), "🏗️ " .. banner, T("A new player's house will be built here"))
	self.Title = title
	-- cônes à l'entrée
	for k, x in ipairs({ gate0 - 1, gate1 + 1 }) do
		Kit.Cone(folder, self:At(x, 0.1, zf - 1.4))
		Kit.Cone(folder, self:At(x + (k == 1 and 1.6 or -1.6), 0.1, zf + 1.6))
	end
	-- === maison en cours ===
	local bx0, bx1 = -wf / 2, wf / 2
	box(self, folder, "Slab", bx0 - 0.5, bx1 + 0.5, -0.3, ft, f - 0.5, b + 0.5, C.Concrete, M.Concrete, { Solid = true })
	local brick = C.Brick:Lerp(rgb(160, 74, 56), (seed % 4) / 6)
	local wallTop = ft + 12
	-- mur du fond (2 fenêtres)
	local w1 = { -wf / 4 - 3, -wf / 4 + 3 }
	local w2 = { wf / 4 - 3, wf / 4 + 3 }
	for _, span in ipairs({ { bx0, w1[1] }, { w1[2], w2[1] }, { w2[2], bx1 } }) do
		box(self, folder, "BackWall", span[1], span[2], ft, wallTop, b - 1, b, brick, M.Brick, { Solid = true })
	end
	for _, w in ipairs({ w1, w2 }) do
		box(self, folder, "BackWall", w[1], w[2], ft, ft + 3.5, b - 1, b, brick, M.Brick, { Solid = true })
		box(self, folder, "Lintel", w[1] - 0.6, w[2] + 0.6, ft + 9.2, ft + 10, b - 1.05, b + 0.05, C.ConcreteDark, M.Concrete)
		box(self, folder, "BackWall", w[1], w[2], ft + 10, wallTop, b - 1, b, brick, M.Brick)
	end
	-- mur de gauche (1 fenêtre)
	local zc = (f + b) / 2
	box(self, folder, "SideWall", bx0, bx0 + 1, ft, wallTop, f + 0.5, zc - 3, brick, M.Brick, { Solid = true })
	box(self, folder, "SideWall", bx0, bx0 + 1, ft, wallTop, zc + 3, b - 1, brick, M.Brick, { Solid = true })
	box(self, folder, "SideWall", bx0, bx0 + 1, ft, ft + 3.5, zc - 3, zc + 3, brick, M.Brick)
	box(self, folder, "Lintel", bx0 - 0.05, bx0 + 1.05, ft + 9.2, ft + 10, zc - 3.6, zc + 3.6, C.ConcreteDark, M.Concrete)
	box(self, folder, "SideWall", bx0, bx0 + 1, ft + 10, wallTop, zc - 3, zc + 3, brick, M.Brick)
	-- façade montée "en escalier" (le maçon avance) + briques d'attente
	local run = wf * 0.62
	local heights = { 12, 9.6, 7.2, 4.8, 2.4 }
	local segW = run / #heights
	for k, h in ipairs(heights) do
		local x0 = bx0 + (k - 1) * segW
		box(self, folder, "FrontWall", x0, x0 + segW, ft, ft + h, f - 0.5, f + 0.5, brick, M.Brick, { Solid = true })
		if h < 12 then
			box(self, folder, "Toothing", x0, x0 + segW * 0.5, ft + h, ft + h + 0.8, f - 0.45, f + 0.45, brick:Lerp(rgb(200, 110, 80), 0.3), M.Brick)
		end
	end
	box(self, folder, "SideLow", bx1 - 1, bx1, ft, ft + 1.6, f + 0.5, b - 1, brick, M.Brick, { Solid = true })
	-- poteaux béton côté droit
	for _, z in ipairs({ f, zc, b - 1 }) do
		box(self, folder, "Column", bx1 - 1.3, bx1 - 0.1, ft, wallTop, z - 0.1, z + 1.1, C.Concrete, M.Concrete, { Solid = true })
	end
	-- plancher de l'étage + étais dessous côté droit
	box(self, folder, "UpperSlab", bx0, bx1, wallTop, wallTop + 1, f - 0.5, b, C.ConcreteDark, M.Concrete, { Solid = true })
	for k = 0, 3 do
		local x = bx1 - 6 - k * 6
		Kit.Rod(folder, "Prop", (self:At(x, ft, f + 3)).Position, (self:At(x, wallTop, f + 3)).Position, 0.25, C.Orange, M.Metal, true)
	end
	-- ossature bois de l'étage (moitié gauche)
	local fx1 = bx0 + wf * 0.42
	local ut = wallTop + 1
	box(self, folder, "SolePlate", bx0 + 0.5, fx1, ut, ut + 0.35, f, f + 0.8, C.Timber, M.Wood)
	box(self, folder, "TopPlate", bx0 + 0.5, fx1, ut + 10.6, ut + 11, f, f + 0.8, C.Timber, M.Wood)
	local studs = math.clamp(math.floor((fx1 - bx0) / 4), 4, 9)
	for k = 0, studs do
		local x = bx0 + 0.9 + k * (fx1 - bx0 - 1.3) / studs
		box(self, folder, "Stud", x - 0.25, x + 0.25, ut + 0.35, ut + 10.6, f + 0.05, f + 0.75, C.Timber:Lerp(C.TimberDark, (k % 3) / 5), M.Wood)
	end
	Kit.Rod(folder, "WallBrace", (self:At(bx0 + 1, ut + 0.5, f + 0.4)).Position, (self:At(bx0 + 1 + (fx1 - bx0) * 0.45, ut + 10.4, f + 0.4)).Position, 0.3, C.TimberDark, M.Wood)
	for k = 0, 3 do
		local z = f + 2 + k * 6
		box(self, folder, "SideStud", bx0 + 0.1, bx0 + 0.8, ut + 0.35, ut + 10.6, z - 0.25, z + 0.25, C.Timber, M.Wood)
	end
	-- fers en attente (côté droit de la dalle)
	for k = 0, 5 do
		local x = bx1 - 3 - k * 3.2
		Kit.Rod(folder, "Rebar", (self:At(x, ut, b - 2)).Position, (self:At(x, ut + 3.2, b - 2)).Position, 0.16, rgb(120, 70, 50), M.Metal, true, { Shadow = false })
	end
	-- échafaudage (façade, 2 planchers) avec filet
	local scaffoldFrame = self:At(bx0 - 0.5, 0.1, f - 0.6)
	Kit.Scaffold(folder, scaffoldFrame, run + 1, { Lifts = 2, LiftH = (wallTop + 1) / 2, Bay = 8, Net = true })
	-- === grue (arrière droit) ===
	local craneX = math.min(bx1 + 8, xr - 5)
	local craneBase = self:At(craneX, 0, b + 10)
	self.Crane = Kit.Crane(folder, craneBase, { Height = 60, Jib = 45 })
	-- palette à prendre près du mât + palette déjà livrée sur le plancher
	local pickCF = self:At(craneX - 7, 0.1, b + 2)
	Kit.BrickPallet(folder, pickCF, seed)
	local dropCF = self:At(wf / 4, ut, zc)
	Kit.BrickPallet(folder, dropCF * CFrame.new(3.8, 0, 0), seed + 1)
	craneKeys(self, self.Crane, (pickCF * CFrame.new(0, 3.4, 0)).Position, dropCF.Position)
	-- === pelleteuse (côté gauche) : tranchée devant, tas de terre sur le côté ===
	local exX = xl + 8.5
	local exCF = self:At(exX, 0.1, f + 6)
	self.Excavator = Kit.Excavator(folder, exCF)
	self.ExcavatorDump = -1.45
	box(self, folder, "Trench", exX - 2.6, exX + 2.6, -0.02, 0.15, f - 13.5, f - 5.5, rgb(78, 58, 42), M.Ground, { Shadow = false })
	Kit.Pile(folder, self:At(exX + 11.5, 0.1, f + 4.5), 7, 3, C.Dirt, M.Ground)
	-- === matériaux (côté droit, devant) ===
	local mx = (bx1 + xr) / 2
	Kit.BrickPallet(folder, self:At(mx - 1.8, 0.1, zf + 6), seed + 2)
	Kit.BrickPallet(folder, self:At(mx + 2.2, 0.1, zf + 6.5), seed + 3)
	Kit.TimberStack(folder, self:At(mx, 0.1, f - 3), 10)
	Kit.SteelBeams(folder, self:At(mx, 0.1, f + 9), 12)
	Kit.Pile(folder, self:At(mx - 0.5, 0.1, zf + 14), 6, 2.4, C.Sand, M.Sand)
	Kit.CementBags(folder, self:At(mx + 0.5, 0.1, b - 3))
	local drum, drumCF = Kit.Mixer(folder, self:At(mx, 0.1, b + 3.5) * CFrame.Angles(0, math.rad(90), 0))
	self.Drum, self.DrumCF = drum, drumCF
	-- === bungalow + toilettes (au fond, à gauche) ===
	local officeX = bx0 + 4
	Kit.Office(folder, self:At(officeX, 0.1, b + 11), T("Site office"))
	self.OfficeX = officeX
	Kit.Portaloo(folder, self:At(officeX + 12.5, 0.1, b + 11.5))
	-- établi du charpentier (devant la façade, à droite de l'entrée)
	local sawCF = self:At(gate1 + 7, 0.1, f - 6) * CFrame.Angles(0, math.rad(90), 0)
	Kit.Sawhorse(folder, sawCF)
	self.SawCF = sawCF
	-- chemins des ouvriers
	self.Paths = {
		Carry = { self:At(mx - 1.8, 0.1, zf + 9.5), self:At(bx1 - 5, 0.1, f - 3.2) },
		Trolley = { self:At(mx + 1, 0.1, zf + 16), self:At(mx + 1, 0.1, b - 6.5) },
	}
	folder.Parent = self.Parent
	self.Folder = folder
end

-- Nombre de pièces du chantier (mesure)
local function countParts(model: Instance?): number
	if not model then
		return 0
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
ConstructionSite.CountParts = countParts

----------------------------------------------------------------------
-- Ouvriers
----------------------------------------------------------------------

-- Marteau dans la main droite (groupe "avant-bras droit" du PNJ : suit le bras)
local function addHammer(model: Model, scale: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local hand = Vector3.new(0.745, 2.3, 0) * scale
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = P(model, name, size, root.CFrame * CFrame.new(hand) * offset, color, material, { Shadow = false })
		p:SetAttribute("NpcG", 6)
		p:SetAttribute("NpcRest", root.CFrame:ToObjectSpace(p.CFrame))
	end
	add("HammerHandle", Vector3.new(0.12, 0.12, 0.95), CFrame.new(0, -0.02, -0.38), C.Timber, M.Wood)
	add("HammerHead", Vector3.new(0.2, 0.46, 0.2), CFrame.new(0, 0.04, -0.82), C.SteelDark, M.Metal)
end

-- Bras droit du marteau : pose recalculée APRÈS NPCModels.Animate
local function hammerArm(w: any, t: number)
	local model: Model = w.Model
	local root = model.PrimaryPart
	if not root or not w.Chest then
		return
	end
	local J = NPC.Joints
	local s = w.Scale
	local pivot = root.CFrame
	local chestT = pivot:Inverse() * w.Chest.CFrame * w.ChestRest:Inverse()
	local u = (t * 1.25) % 1
	local up, elbow
	if u < 0.62 then
		local k = Kit.Smooth(u / 0.62)
		up, elbow = 0.55 + 1.35 * k, 0.4 + 1.1 * k -- lève le marteau
	elseif u < 0.76 then
		local k = (u - 0.62) / 0.14
		k = k * k
		up, elbow = 1.9 - 1.45 * k, 1.5 - 1.2 * k -- frappe (rapide)
	else
		local k = Kit.Smooth((u - 0.76) / 0.24)
		up, elbow = 0.45 + 0.1 * k, 0.3 + 0.1 * k -- petit rebond
	end
	local function about(p: Vector3, rot: CFrame): CFrame
		return CFrame.new(p) * rot * CFrame.new(-p)
	end
	local ru = chestT * about(J.ShoulderR * s, CFrame.Angles(up, 0, 0.08))
	local rl = ru * about(J.ElbowR * s, CFrame.Angles(elbow, 0, 0))
	local parts, frames = {}, {}
	for i, part in ipairs(w.ArmUp) do
		table.insert(parts, part)
		table.insert(frames, pivot * ru * w.ArmUpRest[i])
	end
	for i, part in ipairs(w.ArmLo) do
		table.insert(parts, part)
		table.insert(frames, pivot * rl * w.ArmLoRest[i])
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function newWorker(self: Site, kind: string, index: number, cf: CFrame, prop: string?): any
	local N = npcModels()
	if not N then
		return nil
	end
	local ok, model = pcall(N.Build, "worker", { Seed = self.Seed * 17 + index * 5, Prop = prop or "none", Name = "Worker_" .. kind })
	if not ok or not model then
		return nil
	end
	model:PivotTo(cf)
	local w: any = { Model = model, Kind = kind, Offset = index * 1.37 + self.Seed * 0.61, Scale = tonumber(model:GetAttribute("NpcScale")) or 1 }
	if kind == "Hammer" then
		addHammer(model, w.Scale)
		w.ArmUp, w.ArmUpRest, w.ArmLo, w.ArmLoRest = {}, {}, {}, {}
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") then
				local g = d:GetAttribute("NpcG")
				local rest = d:GetAttribute("NpcRest")
				if typeof(rest) == "CFrame" then
					if g == 5 then
						table.insert(w.ArmUp, d)
						table.insert(w.ArmUpRest, rest)
					elseif g == 6 then
						table.insert(w.ArmLo, d)
						table.insert(w.ArmLoRest, rest)
					elseif g == 1 and not w.Chest then
						w.Chest, w.ChestRest = d, rest
					end
				end
			end
		end
	elseif kind == "Operator" then
		pcall(N.SetSolid, model, false)
		pcall(N.SetSeated, model, 1.3)
	elseif kind == "Carry" then
		w.Box = {
			P(self.Folder :: Model, "TileBox", Vector3.new(1.6, 1.0, 1.1), cf, rgb(196, 160, 110), M.Cardboard, { Shadow = false }),
			P(self.Folder :: Model, "TileBoxTape", Vector3.new(1.62, 0.12, 1.12), cf, rgb(220, 200, 150), M.Plastic, { Shadow = false }),
		}
	elseif kind == "Trolley" then
		w.Cart = Kit.Trolley(self.Folder :: Model, cf)
		w.CartLocals = {}
		local base = cf
		for i, part in ipairs(w.Cart) do
			w.CartLocals[i] = base:ToObjectSpace(part.CFrame)
		end
	end
	model.Parent = self.Folder
	return w
end

function ConstructionSite.BuildWorkers(self: Site)
	if self.WorkersBuilt or not self.Folder or self.Level ~= 2 then
		return
	end
	self.WorkersBuilt = true
	local list = {}
	local saw = self.SawCF
	if saw then
		-- tourné face à l'établi (l'établi est dans l'axe X du chantier)
		local w = newWorker(self, "Hammer", 1, saw * CFrame.new(-1.45, 0, 0) * CFrame.Angles(0, math.rad(-90), 0))
		if w then
			table.insert(list, w)
		end
	end
	for i, kind in ipairs({ "Carry", "Trolley" }) do
		local path = self.Paths and self.Paths[kind]
		if path then
			local w = newWorker(self, kind, i + 1, path[1])
			if w then
				w.Path = path
				table.insert(list, w)
			end
		end
	end
	if self.OfficeX then
		local w = newWorker(self, "Boss", 4, self:At(self.OfficeX + 4.5, 0.1, self.Back + 5.2) * CFrame.Angles(0, math.rad(20), 0), "tablet")
		if w then
			table.insert(list, w)
		end
	end
	if self.Excavator then
		local w = newWorker(self, "Operator", 5, self.Excavator.CabCF or self:At(0, 0, 0))
		if w then
			table.insert(list, w)
		end
	end
	self.Workers = list
end

function ConstructionSite.DestroyWorkers(self: Site)
	for _, w in ipairs(self.Workers) do
		w.Model:Destroy()
		for _, key in ipairs({ "Box", "Cart" }) do
			local parts = w[key]
			if parts then
				for _, part in ipairs(parts) do
					part:Destroy()
				end
			end
		end
	end
	self.Workers = {}
	self.WorkersBuilt = false
end

-- Aller-retour : renvoie (cf, marche ?, sens aller ?)
local function shuttle(path: { CFrame }, t: number, speed: number, pause: number): (CFrame, boolean, boolean)
	local a, b = path[1].Position, path[2].Position
	local length = (b - a).Magnitude
	local walk = length / speed
	local period = 2 * (walk + pause)
	local u = t % period
	local pos, dir, moving, outbound
	if u < walk then
		pos, dir, moving, outbound = a:Lerp(b, u / walk), (b - a), true, true
	elseif u < walk + pause then
		pos, dir, moving, outbound = b, (b - a), false, true
	elseif u < 2 * walk + pause then
		pos, dir, moving, outbound = b:Lerp(a, (u - walk - pause) / walk), (a - b), true, false
	else
		pos, dir, moving, outbound = a, (a - b), false, false
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(pos, pos + look), moving, outbound
end

local function stepWorkers(self: Site, now: number)
	local N = NPC
	if not N then
		return
	end
	for _, w in ipairs(self.Workers) do
		local t = now + w.Offset
		local model: Model = w.Model
		if w.Kind == "Hammer" then
			N.Animate(model, "idle", t, (self.SawCF :: CFrame).Position + Vector3.new(0, 2.4, 0))
			pcall(hammerArm, w, t)
		elseif w.Kind == "Boss" then
			N.Animate(model, if (t % 14) < 9 then "type" else "talk", t)
		elseif w.Kind == "Operator" then
			local ex = self.Excavator
			if ex and ex.CabCF then
				N.Place(model, ex.CabCF * CFrame.new(0, -2.6, 0.35))
			end
			N.Animate(model, "sit", t)
		elseif w.Kind == "Carry" then
			local cf, moving, outbound = shuttle(w.Path, t, 3.6, 1.6)
			N.Place(model, cf)
			N.Animate(model, if moving then (if outbound then "push" else "walk") else "idle", t)
			local visible = outbound
			local boxCF = if moving then cf * CFrame.new(0, 3.2, -1.15) else cf * CFrame.new(0, 0.6, -1.4)
			for i, part in ipairs(w.Box) do
				part.LocalTransparencyModifier = if visible then 0 else 1
				part.CFrame = boxCF * CFrame.new(0, if i == 2 then 0.45 else 0, 0)
			end
		elseif w.Kind == "Trolley" then
			local cf, moving = shuttle(w.Path, t, 3.2, 2.2)
			N.Place(model, cf)
			N.Animate(model, if moving then "push" else "idle", t)
			local base = cf * CFrame.new(0, 0, -2.85)
			local frames = {}
			for i, l in ipairs(w.CartLocals) do
				frames[i] = base * l
			end
			workspace:BulkMoveTo(w.Cart, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

----------------------------------------------------------------------
-- Niveaux, animation, retrait
----------------------------------------------------------------------

function ConstructionSite.SetLevel(self: Site, level: number)
	if level == self.Level or self.Clearing or self.Done then
		return
	end
	self:DestroyWorkers()
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	self.Crane = nil
	self.LiteCrane = nil
	self.Excavator = nil
	self.Drum = nil
	self.Level = level
	if level == 1 then
		self:BuildLite()
	elseif level == 2 then
		self:BuildFull()
	end
	self.Parts = countParts(self.Folder)
	if self.Appear and self.Folder then
		-- (chantier qui (ré)apparaît : fondu doux)
		self.AppearAt = os.clock()
		self.AppearParts = {}
		for _, d in ipairs(self.Folder:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				table.insert(self.AppearParts, d)
			end
		end
	end
end

function ConstructionSite.Step(self: Site, now: number, dt: number, camPos: Vector3?)
	if self.Done then
		return
	end
	-- fondu d'apparition
	if self.AppearParts then
		local k = math.clamp((os.clock() - self.AppearAt) / 0.9, 0, 1)
		for _, part in ipairs(self.AppearParts) do
			part.LocalTransparencyModifier = 1 - k
		end
		if k >= 1 then
			self.AppearParts = nil
			self.Appear = false
		end
	end
	if self.Clearing then
		self:StepClear()
		return
	end
	local distance = if camPos then (camPos - self.Ground.Position).Magnitude else 0
	-- grue (cycle commun à tous les joueurs)
	local crane = self.Crane
	local keys = self.CraneKeys
	if crane and keys then
		local lite = self.Level == 1
		self.LiteClock += dt
		if not lite or self.LiteClock >= 0.2 then
			self.LiteClock = 0
			local angle, radius, drop, loaded = Kit.CraneCycle(now + self.Seed * 7.3, keys.A, keys.B, keys.High)
			crane:Pose(angle, radius, drop, loaded)
		end
	end
	if self.Level ~= 2 then
		return
	end
	if distance < MACHINE_RANGE then
		local ex = self.Excavator
		if ex then
			local swing, boom, stick, bucket, dirt = Kit.ExcavatorCycle(now + self.Seed * 3.1, self.ExcavatorDump or -1.4)
			ex:Pose(swing, boom, stick, bucket, dirt)
		end
		if self.Drum and self.DrumCF then
			self.Drum.CFrame = self.DrumCF * CFrame.Angles(now * 1.6 % (math.pi * 2), 0, 0)
		end
	end
	local ds = self.DetailScale or 1
	if distance < WORKER_RANGE * ds then
		if not self.WorkersBuilt then
			self:BuildWorkers()
			self.Parts = countParts(self.Folder)
		end
		if distance < ANIM_RANGE * ds then
			stepWorkers(self, now)
		end
	elseif self.WorkersBuilt and distance > (WORKER_RANGE + 30) * ds then
		self:DestroyWorkers()
		self.Parts = countParts(self.Folder)
	end
end

-- Retrait animé (le joueur arrive : on fait place nette). keepCrane : la
-- grue est détachée et rendue (l'animation de la maison la réutilise).
function ConstructionSite.Clear(self: Site, keepCrane: boolean?): any
	if self.Clearing or self.Done then
		return nil
	end
	local kept = nil
	if keepCrane and self.Crane and self.Level == 2 then
		kept = self.Crane
		kept.Keys = self.CraneKeys
		kept.Model.Parent = self.Parent
		self.Crane = nil
	end
	self:DestroyWorkers()
	local folder = self.Folder
	if not folder then
		self:Destroy()
		return kept
	end
	local parts, origins = {}, {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			table.insert(parts, d)
			table.insert(origins, d.CFrame)
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
	self.Clearing = { Start = os.clock(), Parts = parts, Origins = origins }
	return kept
end

function ConstructionSite.StepClear(self: Site)
	local c = self.Clearing
	if not c then
		return
	end
	local k = math.clamp((os.clock() - c.Start) / CLEAR_TIME, 0, 1)
	local e = k * k
	local frames = table.create(#c.Parts)
	local center = self.Ground.Position
	for i, part in ipairs(c.Parts) do
		local o = c.Origins[i]
		-- tout s'enfonce et rétrécit vers le centre du chantier (pelleté hors champ)
		local toward = (Vector3.new(center.X, o.Y, center.Z) - o.Position) * 0.08 * e
		frames[i] = o + toward - Vector3.new(0, e * 3.5, 0)
		part.LocalTransparencyModifier = math.min(1, e * 1.4)
	end
	workspace:BulkMoveTo(c.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	if k >= 1 then
		self:Destroy()
	end
end

function ConstructionSite.Destroy(self: Site)
	self.Done = true
	self:DestroyWorkers()
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	self.Clearing = nil
	self.Crane = nil
	self.Excavator = nil
end

-- (tests) local player pour les ouvriers
ConstructionSite._players = Players

return ConstructionSite
