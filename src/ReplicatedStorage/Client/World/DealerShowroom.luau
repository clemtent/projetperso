--[[
	DealerShowroom (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DealerShowroom

	🚗 La CONCESSION de Dopamine Town, côté client (v9.8, CARS98) : tout le
	décor du grand hall vitré 70 x 50 (la coque est au serveur : TownShops)
	et de son parvis. Appelé par ShopInteriors (fonctions "voitures") :
	  DealerShowroom.Slots(shop) -> { { CF, Tag } }   podiums (CarSlot_<n>)
	  DealerShowroom.FrontJobs(shop, parent, ctx) -> { job }   niveau 1 (≤ 150 studs)
	      sol poli + allée, murs, plafond et COURONNES LUMINEUSES au-dessus
	      de chaque podium, les 8 voitures sur leurs podiums, plaques des
	      podiums ; dehors : PLATEAU TOURNANT à l'entrée avec la plus belle
	      voiture qui tourne lentement (animée ici), anneau lumineux, mâts
	      et oriflammes, jardinières, projecteurs, 2 voitures "offre du jour"
	  DealerShowroom.FullJobs(shop, parent, ctx) -> { job }    niveau 2 (≤ 60 studs)
	      pupitres d'information (écran : nom, prix, étoiles) + étiquettes de
	      prix / invites (ctx.AddTag), bureau de vente avec le VENDEUR
	      (NPCModels "salesperson", animé quand on est près), invite
	      "🛍️ Voir tout" (catalogue ShopUI), salon d'attente, écran géant,
	      espace "Remise des clés", 2 vraies lumières douces (shop.Lights)
	ctx = { AddTag = fn(shop, parent, display, tagCF, center), Entries = { Entry },
	        Stats = { Items: number }, OpenCatalog = fn(anchor: Vector3) }
	Animations (une seule connexion Heartbeat, arrêtée quand plus rien n'est
	construit) : plateau tournant (BulkMoveTo, 30 Hz, seulement à moins de
	160 studs de la caméra), vendeur (≤ 60 studs).
	Lumières : 2 PointLight douces (Brightness ≤ 1) dedans, allumées par
	ShopInteriors seulement quand on est dedans ; petites couronnes en Neon
	fin (jamais de grande surface lumineuse). Aucun son.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Locale = require(ReplicatedStorage.Shared.Locale)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local DealerShowroom = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(40, 42, 56)
local ACCENT = rgb(236, 72, 120)
local GRAPHITE = rgb(52, 56, 70)
local FLOOR = rgb(232, 232, 238)
local RING = rgb(246, 244, 255)
local GAP = 0.05

DealerShowroom.TURN_SPEED = 0.35 -- rad/s (un tour en ~18 s)
DealerShowroom.ANIM_RANGE = 160
DealerShowroom.NPC_RANGE = 60
DealerShowroom.FEATURED = "SportsCar" -- la plus belle voiture, sur le plateau tournant

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, solid)
end

-- Cylindre debout (axe Y) posé à y0
local function disc(parent: Instance, name: string, F: CFrame, x: number, y0: number, z: number, height: number, diameter: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = newPart(parent, name, Vector3.new(height, diameter, diameter), F * CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, solid)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Anneau de n segments fins (couronnes lumineuses, bord du plateau)
local function ring(parent: Instance, name: string, center: CFrame, radius: number, n: number, width: number, thick: number, color: Color3, material: Enum.Material)
	for k = 0, n - 1 do
		local a = (k + 0.5) / n * math.pi * 2
		local len = 2 * radius * math.tan(math.pi / n) + 0.02
		local cf = center * CFrame.Angles(0, -a, 0) * CFrame.new(radius, 0, 0)
		newPart(parent, name, Vector3.new(width, thick, len), cf, color, material)
	end
end

-- Panneau texte (SurfaceGui sur la face avant = -Z du panneau)
local function sign(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, lines: { { any } }, pps: number, maxDistance: number?): BasePart
	local board = newPart(parent, name, size, cf, color, M.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.3
	gui.Brightness = 1
	gui.MaxDistance = maxDistance or 90
	gui.Parent = board
	local y = 0.06
	local total = 0
	for _, line in ipairs(lines) do
		total += tonumber(line[3]) or 1
	end
	for index, line in ipairs(lines) do
		local share = (tonumber(line[3]) or 1) / total * 0.88
		local l = Instance.new("TextLabel")
		l.Name = "Line" .. index
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.9, share)
		l.Position = UDim2.fromScale(0.05, y)
		l.Font = if index == 1 then Enum.Font.FredokaOne else Enum.Font.GothamBold
		l.TextScaled = true
		l.Text = line[1]
		l.TextColor3 = if line[2] == "accent" then ACCENT elseif line[2] == "white" then WHITE elseif line[2] == "gold" then rgb(255, 200, 80) else INK
		l.Parent = gui
		y += share
	end
	return board
end

local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end

----------------------------------------------------------------------
-- Repères
----------------------------------------------------------------------

type Frames = { B: CFrame, W: number, D: number, H: number, Apron: number, Turn: CFrame?, TurnR: number }

-- B : sol du hall (dessus du plancher) au milieu de la façade, +Z vers le fond
local function frames(shop: any): Frames
	local model = shop.Model
	local B = shop.DoorCF
	local W = tonumber(model:GetAttribute("DealerW")) or shop.Size.X + 2
	local D = tonumber(model:GetAttribute("DealerD")) or shop.Size.Z + 2
	local apron = tonumber(model:GetAttribute("ApronY")) or -0.45
	local turn = model:GetAttribute("TurntableCF")
	return {
		B = B,
		W = W,
		D = D,
		H = shop.Size.Y,
		Apron = apron - 0.2, -- (repère B : le plancher est 0,2 au-dessus du repère de la façade)
		Turn = if typeof(turn) == "CFrame" then turn else nil,
		TurnR = tonumber(model:GetAttribute("TurntableR")) or 8,
	}
end

function DealerShowroom.Slots(shop: any): { { CF: CFrame, Tag: CFrame } }
	local list = {}
	local B = shop.DoorCF
	for index = 1, tonumber(shop.Model:GetAttribute("ShowroomSlots")) or 8 do
		local podium = shop.Model:FindFirstChild("CarSlot_" .. index)
		local cf = podium and podium:GetAttribute("CarCF")
		if typeof(cf) == "CFrame" then
			-- pupitre côté allée centrale, devant la voiture
			local p = B:PointToObjectSpace(cf.Position)
			local toAisle = if p.X < 0 then 1 else -1
			local tag = B * CFrame.new(p.X + toAisle * 6.8, 0, p.Z - 5.4) * CFrame.Angles(0, if toAisle > 0 then math.rad(-30) else math.rad(30), 0)
			table.insert(list, { CF = cf, Tag = tag })
		end
	end
	return list
end

----------------------------------------------------------------------
-- Animations (plateau tournant, vendeur)
----------------------------------------------------------------------

type Spinner = { Parts: { BasePart }, Offsets: { CFrame }, Frames: { CFrame }, Center: CFrame, Angle: number, Model: Instance }
type Seller = { Model: Model, CF: CFrame, Seed: number }

local spinners: { Spinner } = {}
local sellers: { Seller } = {}
local connection: RBXScriptConnection? = nil
local accum = 0
local npcModule: any = nil

local function NPC(): any
	if npcModule == nil then
		npcModule = false
		local module = ReplicatedStorage.Shared:FindFirstChild("NPCModels")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				npcModule = result
			end
		end
	end
	return npcModule or nil
end

local function cameraPos(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

local function localPos(): Vector3?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return cameraPos()
end

local function stepAnimations(dt: number)
	accum += dt
	if accum < 1 / 30 then
		return
	end
	local step = math.min(accum, 0.2)
	accum = 0
	local cam = cameraPos()
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		if not s.Model.Parent then
			table.remove(spinners, i)
		else
			s.Angle = (s.Angle + DealerShowroom.TURN_SPEED * step) % (math.pi * 2)
			if cam == nil or (cam - s.Center.Position).Magnitude < DealerShowroom.ANIM_RANGE then
				local pivot = s.Center * CFrame.Angles(0, s.Angle, 0)
				for k, off in ipairs(s.Offsets) do
					s.Frames[k] = pivot * off
				end
				workspace:BulkMoveTo(s.Parts, s.Frames, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
	local npc = NPC()
	local me = localPos()
	for i = #sellers, 1, -1 do
		local s = sellers[i]
		if not s.Model.Parent then
			table.remove(sellers, i)
		elseif npc and type(npc.Animate) == "function" and me and (me - s.CF.Position).Magnitude < DealerShowroom.NPC_RANGE then
			local near = (me - s.CF.Position).Magnitude < 14
			pcall(npc.Animate, s.Model, if near then "talk" else "type", os.clock() + s.Seed)
		end
	end
	if #spinners == 0 and #sellers == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureLoop()
	if not connection then
		accum = 0
		connection = RunService.Heartbeat:Connect(function(dt: number)
			local ok, err = pcall(stepAnimations, dt)
			if not ok then
				warn("[DealerShowroom] " .. tostring(err))
			end
		end)
	end
end

-- Fait tourner `parts` (déjà placés) autour de l'axe vertical de `center`
local function addSpinner(model: Instance, parts: { BasePart }, center: CFrame)
	local offsets, list = {}, {}
	for _, p in ipairs(parts) do
		table.insert(offsets, center:ToObjectSpace(p.CFrame))
		table.insert(list, p.CFrame)
	end
	table.insert(spinners, { Parts = parts, Offsets = offsets, Frames = list, Center = center, Angle = 0, Model = model })
	ensureLoop()
end

----------------------------------------------------------------------
-- Voitures
----------------------------------------------------------------------

local function findEntry(entries: { any }, id: string): any?
	for _, e in ipairs(entries) do
		if e.Id == id then
			return e
		end
	end
	return nil
end

local function buildCar(entry: any, detail: string, color: any?): Model?
	local ok, model = pcall(CarModels.Build, entry.Id, color, { Detail = detail, Plate = "DOPAMINE" })
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		return model
	end
	return nil
end

----------------------------------------------------------------------
-- Niveau 1 : habillage, couronnes, voitures, parvis + plateau tournant
----------------------------------------------------------------------

function DealerShowroom.FrontJobs(shop: any, parent: Instance, ctx: any): { () -> () }
	local jobs: { () -> () } = {}
	local f = frames(shop)
	local B, W, D, H = f.B, f.W, f.D, f.H
	local hw = W / 2
	local slots = DealerShowroom.Slots(shop)
	local entries = ctx.Entries or {}
	-- sol poli, allée centrale, murs, plafond
	table.insert(jobs, function()
		local floor = box(parent, "FloorFinish", B, -hw + 1.1, hw - 1.1, 0.02, 0.1, 1.1, D - 1.1, FLOOR, M.Marble)
		floor.Reflectance = 0.12
		box(parent, "AisleRunner", B, -4.5, 4.5, 0.1, 0.15, 1.3, D - 11, GRAPHITE, M.Fabric)
		for _, sx in ipairs({ -1, 1 }) do
			box(parent, "AisleEdge", B, sx * 4.5 - 0.12, sx * 4.5 + 0.12, 0.1, 0.17, 1.3, D - 11, ACCENT, M.SmoothPlastic)
		end
		-- mur du fond : paroi graphite + bandeau lumineux fin + grande enseigne
		box(parent, "FeatureWall", B, -hw + 1.2, hw - 1.2, 0.1, H - 0.1, D - 1.35, D - 1.2, GRAPHITE, M.SmoothPlastic)
		local strip = box(parent, "WallGlowStrip", B, -hw + 2, hw - 2, 7.6, 7.75, D - 1.45, D - 1.35, RING, M.Neon)
		strip.Transparency = 0.2
		sign(parent, "BackSign", Vector3.new(30, 4.2, 0.15), B * CFrame.new(0, 10.6, D - 1.45), GRAPHITE,
			{ { Locale.T("🚗 Car Dealership"), "white", 1.4 }, { "DOPAMINE MOTORS", "accent", 0.8 } }, 24, 160)
		-- mur plein (côté opposé à la porte de la ville) : lambris clair + 3 affiches
		local sideX = hw - 1.15
		box(parent, "SideLining", B, sideX - 0.1, sideX, 0.1, H - 0.1, 1.3, D - 1.5, rgb(248, 248, 252), M.SmoothPlastic)
		local posters = {
			{ "⚡ " .. Locale.T("Performance"), Locale.T("Up to 58 km/h in town") },
			{ "🎨 " .. Locale.T("12 paint colours"), Locale.T("Change them in 🏎️ My cars") },
			{ "🔑 " .. Locale.T("Drive it right away"), Locale.T("Press 🚗 My car in town") },
		}
		for k, poster in ipairs(posters) do
			local z = D * (k / 4)
			sign(parent, "Poster", Vector3.new(9, 5.4, 0.12), B * CFrame.new(sideX - 0.18, 7, z) * CFrame.Angles(0, math.pi / 2, 0), ACCENT,
				{ { poster[1], "white", 1.2 }, { poster[2], "white", 0.8 } }, 30, 90)
		end
		-- plafond : dalle blanche + couronnes lumineuses au-dessus des podiums
		box(parent, "CeilingFinish", B, -hw + 1.2, hw - 1.2, H - 0.12, H - GAP, 1.2, D - 1.2, rgb(250, 250, 252), M.SmoothPlastic)
	end)
	for index, slot in ipairs(slots) do
		table.insert(jobs, function()
			local p = B:PointToObjectSpace(slot.CF.Position)
			local center = B * CFrame.new(p.X, H - 0.45, p.Z)
			ring(parent, "LightRing", center, 5.2, 10, 0.3, 0.14, RING, M.Neon)
			ring(parent, "LightRingFrame", center * CFrame.new(0, 0.18, 0), 5.2, 10, 0.5, 0.2, GRAPHITE, M.Metal)
			-- podium : bord chromé + plaque de nom côté allée
			ring(parent, "PodiumTrim", slot.CF * CFrame.new(0, -0.17, 0), 6.55, 16, 0.12, 0.36, rgb(214, 218, 226), M.Metal)
			local entry = entries[index]
			if entry then
				local model = buildCar(entry, "Full", nil)
				if model then
					model:PivotTo(slot.CF)
					model.Parent = parent
					table.insert(shop.Displays, { Entry = entry, Model = model, Labels = {}, Key = "Car:" .. entry.Id })
					if ctx.Stats then
						ctx.Stats.Items += 1
					end
				end
			end
		end)
	end
	-- dehors : plateau tournant + la plus belle voiture
	local turn = f.Turn
	if turn then
		table.insert(jobs, function()
			local R = f.TurnR
			local holder = Instance.new("Model")
			holder.Name = "Turntable"
			holder.Parent = parent
			local spin = {}
			local deck = newPart(holder, "TurntableDeck", Vector3.new(0.14, (R - 0.55) * 2, (R - 0.55) * 2), turn * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(38, 40, 50), M.SmoothPlastic)
			;(deck :: Part).Shape = Enum.PartType.Cylinder
			deck.Reflectance = 0.15
			table.insert(spin, deck)
			-- rayures du plateau (on voit qu'il tourne)
			for k = 0, 3 do
				local stripe = newPart(holder, "DeckStripe", Vector3.new(0.3, 0.05, (R - 0.8) * 2), turn * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, 0.165, 0), rgb(70, 74, 92), M.SmoothPlastic)
				table.insert(spin, stripe)
			end
			ring(holder, "TurntableGlow", turn * CFrame.new(0, 0.04, 0), R - 0.28, 24, 0.22, 0.1, RING, M.Neon)
			ring(holder, "TurntableRim", turn * CFrame.new(0, 0.02, 0), R - 0.02, 24, 0.12, 0.34, rgb(214, 218, 226), M.Metal)
			local entry = findEntry(entries, DealerShowroom.FEATURED) or entries[#entries]
			if entry then
				local model = buildCar(entry, "Full", nil)
				if model then
					model.Name = "FeaturedCar"
					model:PivotTo(turn * CFrame.new(0, 0.14, 0) * CFrame.Angles(0, math.rad(-35), 0))
					model.Parent = holder
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") then
							table.insert(spin, d)
						end
					end
					local display = { Entry = entry, Model = model, Labels = {}, Key = "Car:" .. entry.Id .. ":Featured" }
					table.insert(shop.Displays, display)
					if ctx.AddTag then
						-- étiquette fixe à côté du plateau (côté route)
						local tagCF = turn * CFrame.new(R + 1.2, 1.2, 0) * CFrame.Angles(0, math.rad(90), 0)
						pcall(ctx.AddTag, shop, holder, display, tagCF, (turn * CFrame.new(0, 3, 0)).Position)
					end
				end
			end
			addSpinner(holder, spin, turn)
			-- panneau "Nouveauté" + 2 projecteurs (sans vraie lumière) tournés vers le plateau
			local tp = B:PointToObjectSpace(turn.Position)
			sign(parent, "FeaturedSign", Vector3.new(7, 2.2, 0.2), B * CFrame.new(tp.X, f.Apron + 1.8, tp.Z - R - 1.2) * CFrame.Angles(math.rad(12), 0, 0), GRAPHITE,
				{ { "✨ " .. Locale.T("New!"), "gold", 1 }, { entry and (entry.Icon .. " " .. Locale.T(entry.Name)) or "", "white", 0.9 } }, 30, 120)
			box(parent, "FeaturedSignLeg", B, tp.X - 0.12, tp.X + 0.12, f.Apron, f.Apron + 0.8, tp.Z - R - 1.25, tp.Z - R - 1.0, GRAPHITE, M.Metal)
			for _, sx in ipairs({ -1, 1 }) do
				local base = B * CFrame.new(tp.X + sx * (R + 2.6), f.Apron, tp.Z - R * 0.6)
				disc(parent, "SpotPole", base, 0, 0, 0, 5.2, 0.28, GRAPHITE, M.Metal)
				local head = CFrame.lookAt((base * CFrame.new(0, 5.4, 0)).Position, turn.Position + Vector3.new(0, 1.5, 0))
				local can = newPart(parent, "SpotHead", Vector3.new(0.9, 0.9, 1.4), head, GRAPHITE, M.Metal)
				can.CastShadow = false
				ellipsoid(parent, "SpotLens", head * CFrame.new(0, 0, -0.72), Vector3.new(0.7, 0.7, 0.1), rgb(255, 250, 230), M.Neon)
			end
		end)
	end
	-- parvis : mâts + oriflammes, jardinières, 2 voitures "offre du jour"
	table.insert(jobs, function()
		local ay = f.Apron
		local banner = { ACCENT, rgb(120, 196, 255), rgb(255, 214, 110), rgb(126, 214, 176) }
		for k = 0, 5 do
			local x = -hw + 6 + k * (W - 12) / 5
			local base = B * CFrame.new(x, ay, -3.6)
			disc(parent, "FlagPole", base, 0, 0, 0, 12, 0.26, rgb(214, 218, 226), M.Metal)
			local flag = newPart(parent, "Banner", Vector3.new(0.1, 5, 1.8), base * CFrame.new(0, 8.8, -1.05), banner[k % #banner + 1], M.Fabric)
			flag.CastShadow = false
			newPart(parent, "BannerArm", Vector3.new(0.12, 0.12, 2.1), base * CFrame.new(0, 11.35, -1.05), rgb(214, 218, 226), M.Metal)
		end
		for _, x in ipairs({ -hw + 2.5, hw - 2.5 }) do
			local cf = B * CFrame.new(x, ay, -1.8)
			box(parent, "Planter", cf, -1.6, 1.6, 0, 1.3, -1, 1, rgb(58, 62, 78), M.Concrete)
			box(parent, "PlanterSoil", cf, -1.45, 1.45, 1.3, 1.36, -0.85, 0.85, rgb(90, 64, 48), M.Ground)
			for k = -1, 1 do
				ellipsoid(parent, "Shrub", cf * CFrame.new(k * 0.95, 1.9, 0), Vector3.new(1.4, 1.3, 1.4), rgb(84 + k * 10, 150, 88), M.Grass)
			end
		end
		-- offres du jour (garées en épi sur le parvis, côté rond-point)
		local picks = { entries[2], entries[3] }
		for k, entry in ipairs(picks) do
			if entry then
				local model = buildCar(entry, "Parked", nil)
				if model then
					local x = 8 + k * 10
					model:PivotTo(B * CFrame.new(x, ay, -14) * CFrame.Angles(0, math.rad(-28), 0))
					model.Parent = parent
					local price = NumberFormatter.Format(tonumber(entry.Def and entry.Def.Cost) or 0)
					local post = B * CFrame.new(x + 3.6, ay, -21.5)
					sign(parent, "OfferSign", Vector3.new(3.4, 1.9, 0.12), post * CFrame.new(0, 2.9, 0) * CFrame.Angles(math.rad(10), 0, 0), WHITE,
						{ { "🔥 " .. Locale.T("Deal of the day"), "accent", 1 }, { "🧠 " .. price, "", 0.9 } }, 40, 60)
					box(parent, "OfferSignLeg", post, -0.08, 0.08, 0, 2.1, 0.08, 0.24, GRAPHITE, M.Metal)
				end
			end
		end
	end)
	return jobs
end

----------------------------------------------------------------------
-- Niveau 2 : pupitres + étiquettes, bureau de vente, vendeur, salon
----------------------------------------------------------------------

function DealerShowroom.FullJobs(shop: any, parent: Instance, ctx: any): { () -> () }
	local jobs: { () -> () } = {}
	local f = frames(shop)
	local B, W, D, H = f.B, f.W, f.D, f.H
	local hw = W / 2
	-- pupitres d'information (écran incliné : nom, prix, étoiles) + étiquettes
	for _, d in ipairs(shop.Displays) do
		if d.Model and d.Entry.Kind == "Car" and not string.find(d.Key, "Featured", 1, true) then
			local slot = nil
			for _, s in ipairs(DealerShowroom.Slots(shop)) do
				if (s.CF.Position - d.Model:GetPivot().Position).Magnitude < 0.5 then
					slot = s
				end
			end
			if slot then
				local chosen = slot
				table.insert(jobs, function()
					local tagCF = chosen.Tag
					disc(parent, "StandPost", tagCF, 0, 0, 0, 3, 0.3, rgb(214, 218, 226), M.Metal)
					disc(parent, "StandFoot", tagCF, 0, 0, 0, 0.12, 1.3, GRAPHITE, M.Metal)
					local h = CarModels.Handling(d.Entry.Id)
					local lines = {
						{ d.Entry.Icon .. " " .. Locale.T(d.Entry.Name), "white", 1.2 },
						{ "⚡ " .. Locale.T("Speed") .. "  " .. stars(h.Stars.Speed), "white", 0.7 },
						{ "🏁 " .. Locale.T("Acceleration") .. "  " .. stars(h.Stars.Accel), "white", 0.7 },
						{ "🌀 " .. Locale.T("Handling") .. "  " .. stars(h.Stars.Grip), "white", 0.7 },
						{ "🛋️ " .. Locale.T("Comfort") .. "  " .. stars(h.Stars.Comfort), "white", 0.7 },
					}
					sign(parent, "StandScreen", Vector3.new(2.4, 1.9, 0.12), tagCF * CFrame.new(0, 3.35, 0) * CFrame.Angles(math.rad(-25), 0, 0), GRAPHITE, lines, 60, 40)
					if ctx.AddTag then
						local center = (chosen.CF * CFrame.new(0, 3, 0)).Position
						pcall(ctx.AddTag, shop, parent, d, tagCF * CFrame.new(0, 4.3, 0), center)
					end
				end)
			end
		end
	end
	-- bureau de vente (courbe), écrans, vendeur, invite "Voir tout"
	table.insert(jobs, function()
		local z0 = D - 9
		local desk = B * CFrame.new(0, 0, z0)
		box(parent, "SalesDesk", desk, -5, 5, 0, 3.2, -1.1, 1.1, WHITE, M.SmoothPlastic, true)
		for _, sx in ipairs({ -1, 1 }) do
			disc(parent, "SalesDeskEnd", desk, sx * 5, 0, 0, 3.2, 2.2, WHITE, M.SmoothPlastic, true)
		end
		box(parent, "SalesDeskBand", desk, -5, 5, 1.2, 1.7, -1.16, -1.1, ACCENT, M.SmoothPlastic)
		box(parent, "SalesDeskTop", desk, -5.3, 5.3, 3.2, 3.4, -1.3, 1.3, rgb(58, 62, 78), M.Marble)
		for _, sx in ipairs({ -1, 1 }) do
			local mon = desk * CFrame.new(sx * 2.4, 3.4, 0.3)
			box(parent, "MonitorFoot", mon, -0.3, 0.3, 0, 0.08, -0.25, 0.25, GRAPHITE, M.Metal)
			box(parent, "MonitorStem", mon, -0.06, 0.06, 0.08, 0.7, -0.05, 0.07, GRAPHITE, M.Metal)
			local screen = box(parent, "Monitor", mon, -0.85, 0.85, 0.6, 1.6, -0.14, -0.05, rgb(30, 32, 42), M.SmoothPlastic)
			screen.CFrame *= CFrame.Angles(math.rad(8), math.pi, 0)
		end
		sign(parent, "SeeAll", Vector3.new(3.8, 1.2, 0.12), desk * CFrame.new(0, 4.3, -0.9) * CFrame.Angles(math.rad(-12), 0, 0), WHITE,
			{ { Locale.T("🛍️ See everything"), "accent", 1 } }, 60, 60)
		box(parent, "SeeAllFoot", desk, -0.4, 0.4, 3.4, 3.72, -0.95, -0.75, rgb(200, 196, 210), M.Metal)
		-- tabourets clients
		for _, sx in ipairs({ -1, 1 }) do
			local stool = desk * CFrame.new(sx * 2.6, 0, -2.6)
			disc(parent, "StoolLeg", stool, 0, 0, 0, 2.3, 0.22, rgb(214, 218, 226), M.Metal)
			disc(parent, "StoolSeat", stool, 0, 2.3, 0, 0.3, 1.3, ACCENT, M.Fabric)
		end
		-- vendeur·se (NPCModels de CITY98) derrière le bureau
		local npcMod = NPC()
		if npcMod and type(npcMod.Build) == "function" then
			local ok, npc = pcall(npcMod.Build, "salesperson", { Seed = 3 })
			if ok and typeof(npc) == "Instance" and npc:IsA("Model") then
				local cf = desk * CFrame.new(0.4, 0, 2.3) * CFrame.Angles(0, math.pi, 0)
				npc:PivotTo(cf)
				npc.Parent = parent
				table.insert(sellers, { Model = npc, CF = cf, Seed = 3 })
				ensureLoop()
			end
		end
		-- invite du catalogue
		local anchor = newPart(parent, "CatalogPoint", Vector3.new(1, 1, 1), desk * CFrame.new(0, 3.9, -1.6), WHITE, M.SmoothPlastic)
		anchor.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CatalogPrompt"
		prompt.ActionText = Locale.T("🛍️ See everything")
		prompt.ObjectText = Locale.T("🚗 Car Dealership")
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		local counterPos = anchor.Position
		shop.Counter = counterPos
		prompt.Triggered:Connect(function()
			if ctx.OpenCatalog then
				ctx.OpenCatalog(counterPos)
			end
		end)
	end)
	-- salon d'attente (côté porte de la ville) + écran géant
	table.insert(jobs, function()
		local lounge = B * CFrame.new(-hw + 9, 0, D - 7)
		box(parent, "LoungeRug", lounge, -6, 6, 0.1, 0.16, -4, 4, rgb(214, 206, 226), M.Fabric)
		for _, side in ipairs({ { 0, 3, 0 }, { -4.2, 0, 90 } }) do
			local cf = lounge * CFrame.new(side[1], 0, side[2]) * CFrame.Angles(0, math.rad(side[3]), 0)
			box(parent, "Sofa", cf, -3, 3, 0.16, 1.5, -0.9, 0.9, rgb(70, 74, 92), M.Fabric, true)
			box(parent, "SofaBack", cf, -3, 3, 1.5, 2.9, 0.5, 0.9, rgb(70, 74, 92), M.Fabric)
			for _, sx in ipairs({ -1, 1 }) do
				box(parent, "SofaArm", cf, sx * 3 - 0.35, sx * 3 + 0.35, 1.5, 2.2, -0.9, 0.9, rgb(62, 66, 84), M.Fabric)
			end
			for _, sx in ipairs({ -1.4, 1.4 }) do
				box(parent, "Cushion", cf, sx - 0.5, sx + 0.5, 1.6, 2.5, 0.25, 0.45, ACCENT, M.Fabric)
			end
		end
		disc(parent, "CoffeeTable", lounge, 0, 0.16, -0.4, 1.3, 3, WHITE, M.Marble, true)
		ellipsoid(parent, "Magazine", lounge * CFrame.new(0.4, 1.5, -0.4), Vector3.new(0.9, 0.06, 0.7), rgb(255, 214, 110), M.SmoothPlastic)
		disc(parent, "PlantPot", lounge, 4.6, 0.16, 2.8, 1.7, 1.8, WHITE, M.SmoothPlastic, true)
		for k = 0, 2 do
			ellipsoid(parent, "PlantLeaves", lounge * CFrame.new(4.6 + (k - 1) * 0.5, 2.8 + k * 0.5, 2.8), Vector3.new(1.6, 2, 1.6), rgb(86, 160 + k * 10, 96), M.Grass)
		end
		-- écran géant au mur du fond, au-dessus du salon
		local tv = B * CFrame.new(-hw + 9, 8.8, D - 1.6)
		box(parent, "BigScreenFrame", tv, -5.2, 5.2, -3, 3, -0.18, 0.1, rgb(24, 24, 30), M.SmoothPlastic)
		sign(parent, "BigScreen", Vector3.new(10, 5.6, 0.1), tv * CFrame.new(0, 0, -0.24), rgb(40, 34, 70),
			{ { "🏁 DOPAMINE MOTORS", "gold", 1.3 }, { Locale.T("Test drive: buy a car, then 🚗 My car"), "white", 0.8 }, { "🎨 ×12   ⚡ 58 km/h   🏎️ ×8", "white", 0.8 } }, 24, 120)
	end)
	-- espace "Remise des clés" (côté mur plein) + armoire à clés
	table.insert(jobs, function()
		local bay = B * CFrame.new(hw - 9, 0, D - 7)
		box(parent, "DeliveryMark", bay, -6, 6, 0.1, 0.15, -4.5, 4.5, rgb(255, 214, 110), M.SmoothPlastic)
		box(parent, "DeliveryInner", bay, -5.6, 5.6, 0.15, 0.2, -4.1, 4.1, FLOOR, M.Marble)
		sign(parent, "DeliverySign", Vector3.new(8, 1.6, 0.12), B * CFrame.new(hw - 9, 7.2, D - 1.45), rgb(255, 214, 110),
			{ { "🔑 " .. Locale.T("Key handover"), "", 1 } }, 40, 90)
		local cab = B * CFrame.new(hw - 3.2, 0, D - 3.4)
		box(parent, "KeyCabinet", cab, -1.4, 1.4, 3, 6, -0.3, 0.3, GRAPHITE, M.Metal)
		for k = 0, 5 do
			local x = -1.0 + (k % 3) * 1.0
			local y = 3.8 + math.floor(k / 3) * 1.2
			ellipsoid(parent, "Key", cab * CFrame.new(x, y, -0.36), Vector3.new(0.3, 0.45, 0.08), if k % 2 == 0 then ACCENT else rgb(120, 196, 255), M.SmoothPlastic)
		end
		-- 2 vraies lumières douces (allumées par ShopInteriors quand on est dedans)
		for _, z in ipairs({ D * 0.3, D * 0.68 }) do
			local host = newPart(parent, "ShowroomLightHost", Vector3.new(0.4, 0.4, 0.4), B * CFrame.new(0, H - 1.2, z), RING, M.SmoothPlastic)
			host.Transparency = 1
			local light = Instance.new("PointLight")
			light.Name = "ShopLight"
			light.Color = rgb(250, 248, 255)
			light.Brightness = 1
			light.Range = 26
			light.Shadows = false
			light.Enabled = shop.LightsOn == true
			light.Parent = host
			if type(shop.Lights) == "table" then
				table.insert(shop.Lights, light)
			end
		end
	end)
	return jobs
end

-- (tests / rendus)
function DealerShowroom.Debug(): any
	return {
		Spinners = spinners,
		Sellers = sellers,
		Step = stepAnimations,
	}
end

return DealerShowroom
