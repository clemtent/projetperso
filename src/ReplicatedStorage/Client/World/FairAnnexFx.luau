--[[
	FairAnnexFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairAnnexFx

	🎢 Décor CLIENT des nouvelles attractions de la fête (v9.9, FAIR99) :
	  - 🎢 GRAND HUIT familial : vrais rails (2 rails tubulaires + poutre
	    dorsale + traverses), poteaux et contreventements jusqu'au sol,
	    chaîne de montée, gare couverte avec quai, barrières et portillon ;
	    train de 4 wagons (caisse arrondie, 2 sièges baquets, appuie-tête,
	    barres de sécurité, roues sur les rails) qui suit la pente et le
	    dévers (FairTrack) ;
	  - 🏴‍☠️ BATEAU PIRATE : 2 portiques en treillis, axe, 2 bras en V, coque
	    en bois (quille, bordages, proue et poupe relevées, bastingage doré,
	    hublots, écusson tête de mort), 4 rangées de bancs face au milieu,
	    plate-forme d'embarquement avec escalier ;
	  - 👻 TRAIN FANTÔME : maison hantée (bardage violet, pignons tordus,
	    tourelle, fenêtres aux yeux qui brillent, portes battantes qui
	    s'ouvrent au passage du train), rail au sol, fantômes, squelette qui
	    surgit, chauves-souris, cercueil, toiles d'araignée ; 3 wagonnets ;
	  - 🤸 TRAMPOLINES : 4 toiles (cadre rembourré, ressorts, filet) ; on y
	    REBONDIT pour de vrai (vitesse de l'avatar local, que le serveur
	    réplique : tout le monde le voit sauter) ; invite E "Sauter" ;
	  - 🪞 PALAIS DES GLACES : labyrinthe de miroirs (Reflectance, pas de
	    reflet "live"), cadres dorés, guirlande, miroirs déformants à
	    l'entrée.
	Toutes les pièces sont locales, ancrées ; seules les pièces où l'on
	marche sont solides. Mouvements : FairKit.StepRide (même pose que le
	serveur, fonction de l'heure).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FairRides = require(ReplicatedStorage.Shared.FairRides)
local FairTrack = require(ReplicatedStorage.Shared.FairTrack)
local Locale = require(ReplicatedStorage.Shared.Locale)
local FairKit = require(script.Parent.FairKit)

local FairAnnexFx = {}

local M = FairKit.M
local C = FairKit.C
local VERTICAL = FairKit.VERTICAL
local BALL, CYL = FairKit.BALL, FairKit.CYL
local TAU = FairKit.TAU
local Part, Solid, Glow = FairKit.Part, FairKit.Solid, FairKit.Glow
local Fixed, Moving = FairKit.Fixed, FairKit.Moving

type RideFx = FairKit.RideFx

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Rails (grand huit / train fantôme) : pièces FIXES le long de la spline
----------------------------------------------------------------------

local function railRod(r: RideFx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?)
	-- (a, b : repère de la Base) ; un peu plus long : aucun trou aux jonctions
	local dir = b - a
	local len = dir.Magnitude
	if len < 1e-3 then
		return
	end
	local mid = (a + b) / 2
	Part(r.Model, name, Vector3.new(len + d * 0.35, d, d), r.Base * (CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)), color, material or M.Metal, CYL)
end

-- Grand huit : rails + dorsale + traverses + poteaux
local function coasterTrack(r: RideFx)
	local entry = FairRides.Track("Coaster")
	local track = entry.Track
	local every = math.max(1, math.floor(1.2 / track.Step + 0.5)) -- un tronçon ~1,2 stud
	local rail = Color3.fromRGB(214, 220, 232)
	local spine = Color3.fromRGB(64, 178, 170)
	local tie = Color3.fromRGB(52, 132, 128)
	local support = Color3.fromRGB(244, 244, 248)
	local n = track.N
	local liftA = FairRides.COASTER_LIFT
	local prevL, prevR, prevS: Vector3? = nil, nil, nil
	local count = 0
	local frames = {}
	for i = 0, n, every do
		local s = math.min(i, n) * track.Step
		local f = FairTrack.Frame(track, s)
		table.insert(frames, { S = s, F = f })
	end
	for k, e in ipairs(frames) do
		local f = e.F
		local pl = (f * CFrame.new(-0.55, 0, 0)).Position
		local pr = (f * CFrame.new(0.55, 0, 0)).Position
		local ps = (f * CFrame.new(0, -0.5, 0)).Position
		if prevL and prevR and prevS then
			railRod(r, "Rail", prevL, pl, 0.26, rail)
			railRod(r, "Rail", prevR, pr, 0.26, rail)
			railRod(r, "Spine", prevS, ps, 0.5, spine, M.SmoothPlastic)
		end
		prevL, prevR, prevS = pl, pr, ps
		-- traverse (tous les 2 tronçons) : relie les rails à la dorsale
		if k % 2 == 0 then
			Part(r.Model, "Tie", Vector3.new(1.3, 0.16, 0.22), r.Base * f * CFrame.new(0, -0.2, 0), tie, M.Metal)
			Part(r.Model, "TieLeg", Vector3.new(0.16, 0.36, 0.2), r.Base * f * CFrame.new(0, -0.36, 0), tie, M.Metal)
		end
		-- poteau (tous les ~4,8 studs), avec semelle, et contreventement si haut
		if k % 4 == 1 then
			local top = ps - Vector3.new(0, 0.25, 0)
			local h = top.Y
			if h > 0.9 then
				local foot = Vector3.new(top.X, 0, top.Z)
				local col = Part(r.Model, "Column", Vector3.new(h, 0.42, 0.42), r.Base * CFrame.new((top + foot) / 2) * VERTICAL, support, M.Metal, CYL)
				col.CastShadow = true
				Solid(Part(r.Model, "Footing", Vector3.new(0.3, 1.1, 1.1), r.Base * CFrame.new(foot + Vector3.new(0, 0.15, 0)) * VERTICAL, Color3.fromRGB(176, 176, 180), M.Concrete, CYL))
				if h > 4.5 then
					-- deux jambes de force latérales (en A)
					local right = f.RightVector
					local flat = Vector3.new(right.X, 0, right.Z)
					if flat.Magnitude > 0.2 then
						flat = flat.Unit
						for _, sx in ipairs({ -1, 1 }) do
							local base = foot + flat * sx * math.min(3.2, h * 0.38)
							railRod(r, "Brace", base, top - Vector3.new(0, h * 0.35, 0), 0.26, support)
							Solid(Part(r.Model, "Footing", Vector3.new(0.25, 0.8, 0.8), r.Base * CFrame.new(base + Vector3.new(0, 0.12, 0)) * VERTICAL, Color3.fromRGB(176, 176, 180), M.Concrete, CYL))
						end
					end
				end
			end
		end
		count += 1
	end
	-- chaîne de montée (maillons sombres entre les rails)
	local sA = 0
	local sB = 0
	do
		local best, bestB = math.huge, math.huge
		for i = 1, n do
			local da = (track.Pos[i] - liftA.From).Magnitude
			local db = (track.Pos[i] - liftA.To).Magnitude
			if da < best then
				best = da
				sA = (i - 1) * track.Step
			end
			if db < bestB then
				bestB = db
				sB = (i - 1) * track.Step
			end
		end
	end
	local s = sA
	while s < sB do
		local f = FairTrack.Frame(track, s)
		Part(r.Model, "Chain", Vector3.new(0.3, 0.12, 0.9), r.Base * f * CFrame.new(0, 0.02, 0), Color3.fromRGB(44, 44, 50), M.DiamondPlate)
		s += 1.1
	end
	local _ = count
end

-- Wagon du grand huit (groupe g : repère = rail, -Z = avant)
local COASTER_COLORS = { Color3.fromRGB(236, 72, 120), Color3.fromRGB(255, 176, 60), Color3.fromRGB(80, 170, 255), Color3.fromRGB(128, 214, 150) }
local function coasterCar(r: RideFx, g: number, lead: boolean)
	local body = COASTER_COLORS[(g - 1) % #COASTER_COLORS + 1]
	local dark = Color3.fromRGB(48, 50, 60)
	-- châssis + roues (2 trains de roues sur les rails)
	Moving(r, g, "Chassis", Vector3.new(1.5, 0.3, 2.7), CFrame.new(0, 0.33, 0.1), dark, M.Metal)
	for _, z in ipairs({ -0.9, 1.1 }) do
		for _, sx in ipairs({ -1, 1 }) do
			Moving(r, g, "Wheel", Vector3.new(0.18, 0.46, 0.46), CFrame.new(sx * 0.55, 0.2, z) * CFrame.Angles(0, 0, 0), Color3.fromRGB(70, 72, 80), M.Metal, CYL)
		end
	end
	-- caisse : fond, flancs arrondis, dos, capot (nez rond pour le 1er wagon)
	Moving(r, g, "Tub", Vector3.new(2.1, 0.55, 2.8), CFrame.new(0, 0.72, 0.1), body, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		Moving(r, g, "Side", Vector3.new(0.22, 0.75, 2.7), CFrame.new(sx * 1.08, 1.12, 0.12), body, M.SmoothPlastic)
		Moving(r, g, "SideRoll", Vector3.new(2.72, 0.3, 0.3), CFrame.new(sx * 1.08, 1.52, 0.12) * CFrame.Angles(0, math.rad(90), 0), body:Lerp(Color3.new(1, 1, 1), 0.2), M.SmoothPlastic, CYL)
		Moving(r, g, "Stripe", Vector3.new(0.05, 0.14, 2.5), CFrame.new(sx * 1.2, 1.0, 0.12), C.White, M.SmoothPlastic)
	end
	if lead then
		Moving(r, g, "Nose", Vector3.new(2.1, 1.0, 1.4), CFrame.new(0, 0.95, -1.35), body, M.SmoothPlastic, BALL)
		Moving(r, g, "Eye", Vector3.new(0.34, 0.34, 0.2), CFrame.new(-0.45, 1.25, -1.98), C.White, M.SmoothPlastic, BALL)
		Moving(r, g, "Eye", Vector3.new(0.34, 0.34, 0.2), CFrame.new(0.45, 1.25, -1.98), C.White, M.SmoothPlastic, BALL)
		Glow(Moving(r, g, "Lamp", Vector3.new(0.3, 0.3, 0.14), CFrame.new(0, 0.85, -2.03), C.Bulb, M.SmoothPlastic, BALL))
	else
		Moving(r, g, "Front", Vector3.new(2.1, 0.8, 0.3), CFrame.new(0, 1.05, -1.2), body, M.SmoothPlastic)
	end
	Moving(r, g, "Back", Vector3.new(2.1, 1.25, 0.3), CFrame.new(0, 1.35, 1.35), body, M.SmoothPlastic)
	-- 2 sièges baquets (coussin, dossier, appuie-tête) + barre de sécurité
	for _, sx in ipairs({ -0.7, 0.7 }) do
		Moving(r, g, "Cushion", Vector3.new(0.95, 0.22, 0.95), CFrame.new(sx, 0.95, 0.35), Color3.fromRGB(40, 40, 48), M.Fabric)
		Moving(r, g, "SeatBack", Vector3.new(0.95, 1.1, 0.2), CFrame.new(sx, 1.5, 1.05) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(40, 40, 48), M.Fabric)
		Moving(r, g, "Headrest", Vector3.new(0.7, 0.45, 0.28), CFrame.new(sx, 2.25, 1.13), Color3.fromRGB(40, 40, 48), M.Fabric, BALL)
		Moving(r, g, "LapBar", Vector3.new(0.85, 0.16, 0.16), CFrame.new(sx, 1.72, -0.35), C.Lemon, M.Metal, CYL)
		Moving(r, g, "LapBarArm", Vector3.new(0.12, 0.7, 0.12), CFrame.new(sx, 1.4, -0.52) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(70, 72, 80), M.Metal)
	end
	-- attelage (vers le wagon suivant)
	Moving(r, g, "Hitch", Vector3.new(0.2, 0.2, 0.9), CFrame.new(0, 0.35, 1.75), dark, M.Metal)
end

local function coasterStation(r: RideFx)
	-- quai (le long des wagons en gare), toit, barrières, escalier, panneau
	local def = r.Def
	local plat = Color3.fromRGB(214, 200, 180)
	local roofA, roofB = Color3.fromRGB(64, 178, 170), C.White
	-- (quai à 1,6 : le plancher des wagons en gare est à ~2)
	local top = 1.6
	Solid(Fixed(r, "Platform", Vector3.new(18, top, 3.2), CFrame.new(-11, top / 2, -8.4), plat, M.WoodPlanks))
	Fixed(r, "PlatformEdge", Vector3.new(18, 0.1, 0.35), CFrame.new(-11, top + 0.05, -7.0), C.Lemon, M.SmoothPlastic)
	-- 3 marches de 0,4 vers le parvis (dessus 1,2 / 0,8 / 0,4)
	for i = 1, 3 do
		local h = top - i * 0.4
		Solid(Fixed(r, "Step", Vector3.new(3.2, h, 0.8), CFrame.new(-10, h / 2, -10 - (i - 0.5) * 0.8), plat, M.WoodPlanks))
	end
	-- toit à 2 pans sur 4 poteaux
	for _, x in ipairs({ -19.5, -2.5 }) do
		for _, z in ipairs({ -9.7, -3.2 }) do
			local post = Solid(Fixed(r, "Post", Vector3.new(0.35, 6.2, 0.35), CFrame.new(x, 3.1, z), C.White, M.Metal))
			post.CastShadow = true
		end
	end
	for i = 0, 7 do
		local x = -19.8 + (i + 0.5) * 17.6 / 8
		for _, sz in ipairs({ -1, 1 }) do
			local pane = Fixed(r, "Roof", Vector3.new(17.6 / 8 + 0.02, 0.2, 3.8), CFrame.new(x, 6.75, -6.45 + sz * 1.75) * CFrame.Angles(math.rad(sz * 14), 0, 0), if i % 2 == 0 then roofA else roofB, M.SmoothPlastic)
			pane.CastShadow = true
		end
	end
	Fixed(r, "RoofRidge", Vector3.new(17.8, 0.3, 0.3), CFrame.new(-11, 7.2, -6.45), C.White, M.Metal)
	-- barrière du quai (côté allée) avec portillon
	for _, seg in ipairs({ { -19.6, -12.2 }, { -7.8, -2.4 } }) do
		local x0, x1 = seg[1], seg[2]
		Fixed(r, "Handrail", Vector3.new(x1 - x0, 0.14, 0.14), CFrame.new((x0 + x1) / 2, top + 1.15, -9.9), C.White, M.Metal)
		for x = x0, x1, 1.2 do
			Fixed(r, "Baluster", Vector3.new(0.1, 1.1, 0.1), CFrame.new(x, top + 0.55, -9.9), C.White, M.Metal)
		end
	end
	-- panneau + ampoules
	local board = Fixed(r, "Board", Vector3.new(9, 1.8, 0.25), CFrame.new(-11, 8.3, -8.6), Color3.fromRGB(255, 250, 244), M.SmoothPlastic)
	FairKit.Sign(board, def.Icon .. " " .. Locale.T(def.Name), Color3.fromRGB(40, 140, 130), Color3.fromRGB(255, 250, 244))
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-15.2, 9.35, -8.75), r.Base * Vector3.new(-6.8, 9.35, -8.75), 9, 0.28, { C.Bulb, C.Pink })
end

function FairAnnexFx.BuildCoaster(r: RideFx)
	coasterTrack(r)
	coasterStation(r)
	for g = 1, FairRides.COASTER_CARS do
		coasterCar(r, g, g == 1)
	end
	r.Radius = 30
end

----------------------------------------------------------------------
-- 🏴‍☠️ Bateau pirate
----------------------------------------------------------------------

function FairAnnexFx.BuildPirate(r: RideFx)
	local H = FairRides.PIRATE_PIVOT
	local frameC = Color3.fromRGB(58, 64, 84)
	-- dalle + 2 portiques en treillis (plans z = ±3,9), axe, fanion
	Solid(Fixed(r, "Pad", Vector3.new(27, 0.3, 12.5), CFrame.new(0, 0.15, 0.5), Color3.fromRGB(196, 190, 186), M.Concrete))
	for _, z in ipairs({ -3.9, 3.9 }) do
		local top = r.Base * Vector3.new(0, H + 0.6, z)
		for _, sx in ipairs({ -1, 1 }) do
			local foot = r.Base * Vector3.new(sx * 9.5, 0.3, z)
			FairKit.Truss(r.Model, "Leg", foot, top, r.Base:VectorToWorldSpace(Vector3.new(0, 0, 1)), 0.9, 0.3, frameC, 7)
			Solid(Fixed(r, "Foot", Vector3.new(2, 0.6, 2), CFrame.new(sx * 9.5, 0.6, z), Color3.fromRGB(150, 150, 156), M.Concrete))
		end
		Fixed(r, "Hub", Vector3.new(0.8, 1.8, 1.8), CFrame.new(0, H, z) * CFrame.Angles(0, math.rad(90), 0), C.Gold, M.Metal, CYL)
		FairKit.Beam(r.Model, "Tie", r.Base * Vector3.new(-6, 4.5, z), r.Base * Vector3.new(6, 4.5, z), 0.35, 0.35, frameC, M.Metal)
	end
	Fixed(r, "Axle", Vector3.new(8.6, 0.7, 0.7), CFrame.new(0, H, 0) * CFrame.Angles(0, math.rad(90), 0), C.SteelLight, M.Metal, CYL)
	FairKit.Rod(r.Model, "FlagPole", r.Base * Vector3.new(0, H + 0.9, 3.9), r.Base * Vector3.new(0, H + 4.6, 3.9), 0.14, C.White)
	local fs, fl = FairKit.Tri(r.Base * Vector3.new(0, H + 4.4, 3.9), r.Base:VectorToWorldSpace(Vector3.new(1, 0, 0)), -FairKit.UP, 2.2, 1.4, 0.06)
	Part(r.Model, "Flag", fs, fl, Color3.fromRGB(30, 30, 36), M.Fabric, nil, "WedgePart")
	Part(r.Model, "Skull", Vector3.new(0.5, 0.5, 0.08), r.Base * CFrame.new(0.8, H + 3.75, 3.84), C.White, M.SmoothPlastic, BALL)
	-- plate-forme d'embarquement (niveau du pont) + escalier
	local deckY = H - FairRides.PIRATE_ARM - 0.25
	Solid(Fixed(r, "LoadDeck", Vector3.new(12, 0.4, 3.2), CFrame.new(0, deckY - 0.2, -4.9), Color3.fromRGB(150, 110, 76), M.WoodPlanks))
	for _, x in ipairs({ -5.6, 5.6 }) do
		Solid(Fixed(r, "DeckPost", Vector3.new(0.4, deckY - 0.4, 0.4), CFrame.new(x, (deckY - 0.4) / 2, -6.1), C.WoodDark, M.Wood))
	end
	local steps = math.ceil((deckY - 0.4) / 0.6)
	for i = 1, steps do
		local y = i * (deckY - 0.4) / steps
		-- (marches pleines, posées au sol : un vrai escalier)
		Solid(Fixed(r, "Stair", Vector3.new(2.6, y, 0.78), CFrame.new(0, y / 2, -6.5 - (steps - i) * 0.75), Color3.fromRGB(160, 120, 86), M.WoodPlanks))
	end
	Fixed(r, "DeckRail", Vector3.new(12, 0.14, 0.14), CFrame.new(0, deckY + 1.1, -6.4), C.Gold, M.Metal)
	-- (groupe 1 : repère = milieu du pont de la coque, pend sous l'axe)
	local hull = Color3.fromRGB(122, 78, 50)
	local hullDark = Color3.fromRGB(88, 56, 38)
	local arm = FairRides.PIRATE_ARM
	for _, z in ipairs({ -1.9, 1.9 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local a = Vector3.new(0, arm, z)
			local b = Vector3.new(sx * 2.8, 0.2, z)
			Moving(r, 1, "Arm", Vector3.new(0.42, 0.42, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), frameC, M.Metal)
		end
	end
	-- coque : fond en tranches (plus étroites aux bouts), quille, flancs
	local n = 9
	for i = 0, n - 1 do
		local x = -9 + (i + 0.5) * 18 / n
		local k = math.abs(x) / 9
		local w = 5.2 * (1 - 0.45 * k * k)
		local depth = 2.4 * (1 - 0.5 * k)
		Moving(r, 1, "Bottom", Vector3.new(18 / n + 0.05, depth, w), CFrame.new(x, -depth / 2 - 0.05, 0), hull, M.WoodPlanks)
		for _, sz in ipairs({ -1, 1 }) do
			Moving(r, 1, "Plank", Vector3.new(18 / n + 0.05, 1.3, 0.25), CFrame.new(x, 0.55, sz * (w / 2 + 0.05)) * CFrame.Angles(math.rad(sz * 8), 0, 0), if i % 2 == 0 then hull else hullDark, M.WoodPlanks)
		end
	end
	Moving(r, 1, "Keel", Vector3.new(17, 0.4, 0.5), CFrame.new(0, -2.35, 0), hullDark, M.Wood)
	Moving(r, 1, "Deck", Vector3.new(15, 0.2, 4.4), CFrame.new(0, 0.02, 0), Color3.fromRGB(170, 128, 88), M.WoodPlanks)
	-- proue et poupe relevées (coins en biseau) + figure de proue
	for _, sx in ipairs({ -1, 1 }) do
		local e = CFrame.new(sx * 9.6, 1.1, 0)
		Moving(r, 1, "End", Vector3.new(2.4, 3.6, 3.2), e * CFrame.Angles(0, 0, math.rad(sx * -14)), hull, M.WoodPlanks)
		Moving(r, 1, "EndCap", Vector3.new(2.6, 0.3, 3.4), e * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, math.rad(sx * -14)), C.Gold, M.Metal)
		Moving(r, 1, "Lantern", Vector3.new(0.5, 0.7, 0.5), e * CFrame.new(sx * 0.4, 2.6, 0), C.Bulb, M.SmoothPlastic, BALL)
		Glow(r.Parts[#r.Parts])
	end
	Moving(r, 1, "Figurehead", Vector3.new(1.2, 1.2, 1.2), CFrame.new(-11.1, 1.6, 0), C.Gold, M.Metal, BALL)
	-- bastingage doré + hublots + écusson
	for _, sz in ipairs({ -1, 1 }) do
		Moving(r, 1, "Gunwale", Vector3.new(16.6, 0.22, 0.3), CFrame.new(0, 1.28, sz * 2.62), C.Gold, M.Metal)
		for i = -3, 3 do
			if i ~= 0 then
				Moving(r, 1, "Porthole", Vector3.new(0.08, 0.6, 0.6), CFrame.new(i * 2.1, 0.45, sz * 2.74) * CFrame.Angles(0, math.rad(90), 0), C.Gold, M.Metal, CYL)
			end
		end
		Moving(r, 1, "Emblem", Vector3.new(1.3, 1.3, 0.1), CFrame.new(0, 0.2, sz * 2.8), Color3.fromRGB(30, 30, 36), M.SmoothPlastic, BALL)
		Moving(r, 1, "EmblemSkull", Vector3.new(0.6, 0.6, 0.08), CFrame.new(0, 0.25, sz * 2.86), C.White, M.SmoothPlastic, BALL)
	end
	-- 4 rangées de bancs (face au milieu), dossiers, barres
	for _, x in ipairs({ -7.2, -4.4, 4.4, 7.2 }) do
		local toward = if x < 0 then 1 else -1
		local y = 1.25 + (math.abs(x) - 4.4) * 0.3
		Moving(r, 1, "Riser", Vector3.new(1.4, y - 0.2, 4.4), CFrame.new(x, (y - 0.2) / 2 + 0.05, 0), hullDark, M.WoodPlanks)
		Moving(r, 1, "Bench", Vector3.new(1.2, 0.25, 4.2), CFrame.new(x, y - 0.08, 0), Color3.fromRGB(196, 60, 60), M.Fabric)
		Moving(r, 1, "BenchBack", Vector3.new(0.25, 1.3, 4.2), CFrame.new(x - toward * 0.62, y + 0.6, 0), hull, M.WoodPlanks)
		Moving(r, 1, "SafetyBar", Vector3.new(0.14, 0.14, 4), CFrame.new(x + toward * 0.75, y + 0.9, 0), C.Lemon, M.Metal, CYL)
	end
	r.Radius = 16
end

----------------------------------------------------------------------
-- 👻 Train fantôme
----------------------------------------------------------------------

local function ghostTrack(r: RideFx)
	local entry = FairRides.Track("Ghost")
	local track = entry.Track
	local step = math.max(1, math.floor(1.2 / track.Step + 0.5))
	local prev: Vector3? = nil
	local k = 0
	for i = 0, track.N, step do
		local f = FairTrack.Frame(track, math.min(i, track.N) * track.Step)
		local p = (f * CFrame.new(0, -0.25, 0)).Position
		if prev then
			railRod(r, "Rail", prev, p, 0.22, Color3.fromRGB(150, 150, 160))
		end
		prev = p
		k += 1
		if k % 2 == 0 then
			Part(r.Model, "Sleeper", Vector3.new(1.4, 0.12, 0.32), r.Base * CFrame.new(Vector3.new(p.X, 0.06, p.Z)) * f.Rotation, Color3.fromRGB(88, 64, 50), M.Wood)
		end
	end
end

local function ghostCar(r: RideFx, g: number, lead: boolean)
	local body = Color3.fromRGB(96, 60, 150)
	local trim = Color3.fromRGB(160, 230, 110)
	Moving(r, g, "Base", Vector3.new(1.9, 0.35, 2.4), CFrame.new(0, 0.3, 0.1), Color3.fromRGB(40, 36, 50), M.Metal)
	Moving(r, g, "Tub", Vector3.new(2, 0.9, 2.5), CFrame.new(0, 0.9, 0.1), body, M.SmoothPlastic)
	Moving(r, g, "Rim", Vector3.new(2.1, 0.16, 2.6), CFrame.new(0, 1.38, 0.1), trim, M.SmoothPlastic)
	Moving(r, g, "Back", Vector3.new(2, 1.2, 0.3), CFrame.new(0, 1.8, 1.25), body, M.SmoothPlastic)
	for _, sx in ipairs({ -0.66, 0.66 }) do
		Moving(r, g, "Cushion", Vector3.new(0.9, 0.2, 0.9), CFrame.new(sx, 1.05, 0.3), Color3.fromRGB(60, 30, 80), M.Fabric)
	end
	Moving(r, g, "Bar", Vector3.new(1.8, 0.14, 0.14), CFrame.new(0, 1.75, -0.45), trim, M.Metal, CYL)
	if lead then
		-- chauve-souris à l'avant : tête ronde, oreilles, ailes, yeux qui brillent
		Moving(r, g, "BatHead", Vector3.new(1.3, 1.1, 1), CFrame.new(0, 1.35, -1.35), Color3.fromRGB(50, 40, 66), M.SmoothPlastic, BALL)
		for _, sx in ipairs({ -1, 1 }) do
			Moving(r, g, "BatEar", Vector3.new(0.3, 0.6, 0.2), CFrame.new(sx * 0.4, 2.0, -1.35) * CFrame.Angles(0, 0, math.rad(sx * -15)), Color3.fromRGB(50, 40, 66), M.SmoothPlastic)
			Moving(r, g, "BatWing", Vector3.new(1.4, 0.8, 0.1), CFrame.new(sx * 1.3, 1.25, -1.1) * CFrame.Angles(0, math.rad(sx * 25), math.rad(sx * 18)), Color3.fromRGB(50, 40, 66), M.SmoothPlastic)
			Glow(Moving(r, g, "BatEye", Vector3.new(0.22, 0.22, 0.1), CFrame.new(sx * 0.28, 1.5, -1.84), Color3.fromRGB(255, 220, 90), M.SmoothPlastic, BALL))
		end
	end
end

-- Maison hantée : murs, toits, portes battantes, décor intérieur animé
local function hauntedHouse(r: RideFx): any
	local wall = Color3.fromRGB(88, 66, 110)
	local wallDark = Color3.fromRGB(66, 50, 86)
	local roof = Color3.fromRGB(44, 40, 56)
	local trim = Color3.fromRGB(196, 186, 210)
	local W, D, H = 24, 16, 9
	-- sol intérieur (sombre) + murs (bardage : planches alternées)
	Solid(Fixed(r, "Floor", Vector3.new(W, 0.2, D), CFrame.new(0, 0.1, 0), Color3.fromRGB(46, 42, 52), M.Slate))
	for i = 0, 11 do
		local x = -W / 2 + (i + 0.5) * W / 12
		Solid(Fixed(r, "BackWall", Vector3.new(W / 12 + 0.02, H, 0.5), CFrame.new(x, H / 2, D / 2), if i % 2 == 0 then wall else wallDark, M.WoodPlanks))
	end
	for _, sx in ipairs({ -1, 1 }) do
		Solid(Fixed(r, "SideWall", Vector3.new(0.5, H, D), CFrame.new(sx * W / 2, H / 2, 0), wall, M.WoodPlanks))
	end
	-- façade : 3 trumeaux autour des 2 portes (x ±8,3, largeur 3,4)
	local doors = { 8.3, -8.3 }
	local segs = { { -12, -10 }, { -6.6, 6.6 }, { 10, 12 } }
	for _, sgm in ipairs(segs) do
		local x0, x1 = sgm[1], sgm[2]
		Solid(Fixed(r, "Front", Vector3.new(x1 - x0, H, 0.5), CFrame.new((x0 + x1) / 2, H / 2, -D / 2), wall, M.WoodPlanks))
	end
	for _, dx in ipairs(doors) do
		Fixed(r, "Lintel", Vector3.new(3.4, H - 4.2, 0.5), CFrame.new(dx, 4.2 + (H - 4.2) / 2, -D / 2), wallDark, M.WoodPlanks)
		Fixed(r, "DoorFrame", Vector3.new(3.8, 0.4, 0.7), CFrame.new(dx, 4.3, -D / 2 - 0.05), trim, M.Wood)
	end
	-- toit à 2 pans (tordu) + pignon + tourelle
	for _, sz in ipairs({ -1, 1 }) do
		local pane = Fixed(r, "Roof", Vector3.new(W + 1.6, 0.4, D / 2 + 1.4), CFrame.new(0, H + 2.1, sz * (D / 4 + 0.2)) * CFrame.Angles(math.rad(sz * 26), 0, math.rad(2)), roof, M.Slate)
		pane.CastShadow = true
	end
	for _, sx in ipairs({ -1, 1 }) do
		local size, cf = FairKit.Tri(r.Base * Vector3.new(sx * (W / 2), H, -D / 2 + 0.3), FairKit.UP, r.Base:VectorToWorldSpace(Vector3.new(0, 0, 1)), 4.3, D / 2 - 0.3, 0.4)
		Part(r.Model, "Gable", size, cf, wallDark, M.WoodPlanks, nil, "WedgePart")
		local size2, cf2 = FairKit.Tri(r.Base * Vector3.new(sx * (W / 2), H, D / 2 - 0.3), FairKit.UP, r.Base:VectorToWorldSpace(Vector3.new(0, 0, -1)), 4.3, D / 2 - 0.3, 0.4)
		Part(r.Model, "Gable", size2, cf2, wallDark, M.WoodPlanks, nil, "WedgePart")
	end
	Fixed(r, "Tower", Vector3.new(3.6, 7, 3.6), CFrame.new(-7, H + 3, 3) * CFrame.Angles(0, 0, math.rad(-3)), wallDark, M.WoodPlanks)
	Fixed(r, "TowerRoof", Vector3.new(4.4, 4.4, 4.4), CFrame.new(-7.2, H + 7.6, 3), roof, M.Slate, BALL).Size = Vector3.new(4.6, 3.2, 4.6)
	Glow(Fixed(r, "TowerWindow", Vector3.new(1.2, 1.6, 0.1), CFrame.new(-7, H + 3.4, 1.15), Color3.fromRGB(255, 214, 110), M.SmoothPlastic))
	-- fenêtres (volets de travers) avec des yeux qui brillent
	for _, x in ipairs({ -3.8, 3.8 }) do
		Fixed(r, "Window", Vector3.new(2.4, 2.2, 0.1), CFrame.new(x, 6.2, -D / 2 - 0.3), Color3.fromRGB(24, 20, 30), M.SmoothPlastic)
		Fixed(r, "Shutter", Vector3.new(1.1, 2.4, 0.12), CFrame.new(x - 1.8, 6.1, -D / 2 - 0.36) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(110, 150, 90), M.Wood)
		for _, ex in ipairs({ -0.35, 0.35 }) do
			Glow(Fixed(r, "Eye", Vector3.new(0.3, 0.22, 0.08), CFrame.new(x + ex, 6.3, -D / 2 - 0.38), Color3.fromRGB(255, 236, 120), M.SmoothPlastic, BALL))
		end
	end
	-- enseigne + citrouilles + pierres tombales devant
	local board = Fixed(r, "Board", Vector3.new(11, 1.8, 0.3), CFrame.new(0, H + 0.4, -D / 2 - 0.45) * CFrame.Angles(0, 0, math.rad(-2)), Color3.fromRGB(36, 30, 44), M.Wood)
	FairKit.Sign(board, "👻 " .. Locale.T("Ghost train"), Color3.fromRGB(190, 255, 150), Color3.fromRGB(36, 30, 44), Enum.Font.Creepster)
	for i, x in ipairs({ -11.2, -5.6, 5.8, 11.2 }) do
		local p = Fixed(r, "Pumpkin", Vector3.new(1.2, 0.9, 1.2), CFrame.new(x, 0.45, -D / 2 - 2.8 - (i % 2) * 0.6), Color3.fromRGB(236, 130, 40), M.SmoothPlastic, BALL)
		p.CastShadow = true
		Fixed(r, "Stem", Vector3.new(0.15, 0.3, 0.15), CFrame.new(x, 1.0, -D / 2 - 2.8 - (i % 2) * 0.6), Color3.fromRGB(80, 110, 50), M.Wood)
	end
	for _, x in ipairs({ -10.5, 10.6 }) do
		Solid(Fixed(r, "Tomb", Vector3.new(1.4, 1.8, 0.4), CFrame.new(x, 0.9, -D / 2 - 5.5) * CFrame.Angles(0, 0, math.rad(x > 0 and 6 or -5)), Color3.fromRGB(150, 150, 160), M.Slate))
	end
	-- quai de la gare (devant, le long du rail z -12)
	Solid(Fixed(r, "Platform", Vector3.new(12, 0.6, 2.2), CFrame.new(-3, 0.3, -14.3), Color3.fromRGB(80, 70, 96), M.WoodPlanks))
	for x = -8.5, 2.5, 1.1 do
		Fixed(r, "Baluster", Vector3.new(0.1, 1, 0.1), CFrame.new(x, 1.1, -15.3), Color3.fromRGB(40, 36, 50), M.Metal)
	end
	Fixed(r, "PlatformRail", Vector3.new(11.2, 0.14, 0.14), CFrame.new(-3, 1.6, -15.3), Color3.fromRGB(40, 36, 50), M.Metal)
	-- portes battantes (2 battants par porte) : pivot sur les montants
	local doorsFx = {}
	for di, dx in ipairs(doors) do
		for _, side in ipairs({ -1, 1 }) do
			local hinge = r.Base * CFrame.new(dx + side * 1.65, 0, -D / 2)
			local leaf = Part(r.Model, "DoorLeaf", Vector3.new(1.6, 3.9, 0.2), hinge * CFrame.new(-side * 0.8, 2.1, 0), Color3.fromRGB(60, 40, 30), M.Wood)
			local spot = Part(r.Model, "DoorSkull", Vector3.new(0.6, 0.6, 0.1), hinge * CFrame.new(-side * 0.8, 2.6, -0.14), C.White, M.SmoothPlastic, BALL)
			table.insert(doorsFx, { Hinge = hinge, Side = side, Leaf = leaf, Skull = spot, Door = di, Pos = (r.Base * Vector3.new(dx, 0, -D / 2)) })
		end
	end
	-- intérieur : fantômes, squelette, chauves-souris, cercueil, toiles
	local ghosts = {}
	-- (au-dessus des têtes des passagers : ~4,7)
	for i, p in ipairs({ Vector3.new(4, 5.7, 3), Vector3.new(-3.2, 6.1, 5.6), Vector3.new(-6, 5.6, -3), Vector3.new(2.2, 6.4, -4.2) }) do
		local body = Part(r.Model, "Ghost", Vector3.new(1.6, 2.2, 1.4), r.Base * CFrame.new(p), Color3.fromRGB(240, 244, 255), M.SmoothPlastic, BALL)
		body.Transparency = 0.18
		local eyes = {}
		for _, ex in ipairs({ -0.3, 0.3 }) do
			table.insert(eyes, Part(r.Model, "GhostEye", Vector3.new(0.26, 0.36, 0.1), r.Base * CFrame.new(p + Vector3.new(ex, 0.3, -0.68)), Color3.fromRGB(30, 30, 40), M.SmoothPlastic, BALL))
		end
		table.insert(ghosts, { Body = body, Eyes = eyes, Home = p, Phase = i * 1.7 })
	end
	local skeleton = {}
	do
		local p = Vector3.new(4.6, 0, -6.6)
		local bone = Color3.fromRGB(238, 234, 220)
		local parts = {
			{ "Skull", Vector3.new(0.9, 1, 0.9), Vector3.new(0, 3.5, 0), BALL },
			{ "Ribs", Vector3.new(1.1, 1.3, 0.5), Vector3.new(0, 2.4, 0), nil },
			{ "Pelvis", Vector3.new(0.9, 0.35, 0.4), Vector3.new(0, 1.55, 0), nil },
			{ "Arm", Vector3.new(0.2, 1.3, 0.2), Vector3.new(-0.8, 2.6, -0.3), nil },
			{ "Arm", Vector3.new(0.2, 1.3, 0.2), Vector3.new(0.8, 2.6, -0.3), nil },
			{ "Leg", Vector3.new(0.22, 1.4, 0.22), Vector3.new(-0.3, 0.75, 0), nil },
			{ "Leg", Vector3.new(0.22, 1.4, 0.22), Vector3.new(0.3, 0.75, 0), nil },
		}
		Fixed(r, "Coffin", Vector3.new(1.9, 4.4, 0.5), CFrame.new(p + Vector3.new(0, 2.2, 0.55)), Color3.fromRGB(70, 44, 36), M.Wood)
		for _, d in ipairs(parts) do
			local q = Part(r.Model, d[1], d[2], r.Base * CFrame.new(p + d[3]), bone, M.SmoothPlastic, d[4])
			table.insert(skeleton, { Part = q, Off = d[3] })
		end
		skeleton.Home = p
	end
	local bats = {}
	for i = 1, 4 do
		local b = Part(r.Model, "Bat", Vector3.new(1.2, 0.3, 0.5), r.Base * CFrame.new(0, 6, 0), Color3.fromRGB(34, 28, 44), M.SmoothPlastic)
		table.insert(bats, { Part = b, Phase = i / 4 * TAU })
	end
	-- toiles d'araignée dans les coins, lueurs violettes
	for _, c in ipairs({ Vector3.new(-11.6, 8, 7.6), Vector3.new(11.6, 8, 7.6), Vector3.new(-11.6, 8, -7.6), Vector3.new(11.6, 8, -7.6) }) do
		local web = Fixed(r, "Web", Vector3.new(0.05, 3.2, 3.2), CFrame.new(c) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(230, 230, 240), M.SmoothPlastic)
		web.Transparency = 0.55
	end
	for _, p in ipairs({ Vector3.new(-9, 0.25, 6), Vector3.new(9.5, 0.25, 5.5), Vector3.new(0, 0.25, -2) }) do
		Glow(Fixed(r, "Mist", Vector3.new(0.12, 3.2, 3.2), CFrame.new(p) * VERTICAL, Color3.fromRGB(150, 110, 220), M.SmoothPlastic, CYL)).Transparency = 0.4
	end
	local parts, frames = {}, {}
	return {
		Step = function(t: number)
			table.clear(parts)
			table.clear(frames)
			-- portes : s'ouvrent quand un wagon approche (d'après les groupes)
			for _, d in ipairs(doorsFx) do
				local open = 0
				for g = 1, FairRides.GHOST_CARS do
					local cf = r.Groups[g]
					if cf then
						local w = r.Base * cf.Position
						local dist = (Vector3.new(w.X, 0, w.Z) - Vector3.new(d.Pos.X, 0, d.Pos.Z)).Magnitude
						open = math.max(open, math.clamp((3.6 - dist) / 1.4, 0, 1))
					end
				end
				local e = open * open * (3 - 2 * open)
				local swing = d.Hinge * CFrame.Angles(0, d.Side * math.rad(95) * e, 0)
				table.insert(parts, d.Leaf)
				table.insert(frames, swing * CFrame.new(-d.Side * 0.8, 2.1, 0))
				table.insert(parts, d.Skull)
				table.insert(frames, swing * CFrame.new(-d.Side * 0.8, 2.6, -0.14))
			end
			for _, gh in ipairs(ghosts) do
				local p = gh.Home + Vector3.new(math.sin(t * 0.7 + gh.Phase) * 0.8, math.sin(t * 1.6 + gh.Phase) * 0.45, math.cos(t * 0.5 + gh.Phase) * 0.6)
				local yaw = math.sin(t * 0.9 + gh.Phase) * 0.5
				local cf = r.Base * CFrame.new(p) * CFrame.Angles(0, yaw, 0)
				table.insert(parts, gh.Body)
				table.insert(frames, cf)
				for k, e in ipairs(gh.Eyes) do
					table.insert(parts, e)
					table.insert(frames, cf * CFrame.new(if k == 1 then -0.3 else 0.3, 0.3, -0.68))
				end
			end
			-- squelette : surgit du cercueil toutes les 7 s
			local u = (t % 7) / 7
			local pop = if u < 0.12 then (u / 0.12) else if u < 0.5 then 1 else math.max(0, 1 - (u - 0.5) / 0.2)
			pop = pop * pop * (3 - 2 * pop)
			local sk = r.Base * CFrame.new(skeleton.Home + Vector3.new(0, -0.2 + pop * 0.2, -pop * 1.2)) * CFrame.Angles(math.rad(-10 * pop), 0, 0)
			for _, b in ipairs(skeleton) do
				table.insert(parts, b.Part)
				local arm = if b.Part.Name == "Arm" then CFrame.Angles(math.rad(-80 * pop), 0, 0) else CFrame.identity
				table.insert(frames, sk * CFrame.new(b.Off) * arm)
			end
			for _, b in ipairs(bats) do
				local a = t * 1.3 + b.Phase
				local p = Vector3.new(math.sin(a) * 6.5, 6.4 + math.sin(t * 3 + b.Phase) * 0.5, math.cos(a) * 4)
				table.insert(parts, b.Part)
				table.insert(frames, r.Base * CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a))) * CFrame.Angles(0, 0, math.sin(t * 16 + b.Phase) * 0.5))
			end
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end,
	}
end

function FairAnnexFx.BuildGhost(r: RideFx)
	ghostTrack(r)
	for g = 1, FairRides.GHOST_CARS do
		ghostCar(r, g, g == 1)
	end
	r.Extra = hauntedHouse(r)
	r.Radius = 18
end

----------------------------------------------------------------------
-- 🤸 Trampolines (on rebondit vraiment : avatar local)
----------------------------------------------------------------------

function FairAnnexFx.BuildTrampolines(r: RideFx)
	local size = FairRides.TRAMPOLINE_BED
	local top = FairRides.TRAMPOLINE_TOP
	local pad = { Color3.fromRGB(80, 170, 255), Color3.fromRGB(255, 132, 180), Color3.fromRGB(128, 214, 150), Color3.fromRGB(255, 196, 70) }
	Solid(Fixed(r, "Mat", Vector3.new(17, 0.2, 13), CFrame.new(0, 0.1, 0), Color3.fromRGB(96, 170, 110), M.Grass))
	local beds = {}
	for i, c in ipairs(FairRides.TRAMPOLINE_BEDS) do
		local color = pad[(i - 1) % #pad + 1]
		-- cadre (4 boudins rembourrés) + pieds + ressorts
		for _, sd in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
			local horizontal = sd[1] == 0
			local s = if horizontal then Vector3.new(size + 1, 0.5, 0.6) else Vector3.new(0.6, 0.5, size + 1)
			Solid(Fixed(r, "Pad", s, CFrame.new(c + Vector3.new(sd[1] * (size / 2 + 0.2), top - 0.05, sd[2] * (size / 2 + 0.2))), color, M.Fabric))
		end
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				Fixed(r, "Leg", Vector3.new(0.2, top - 0.2, 0.2), CFrame.new(c + Vector3.new(sx * size / 2, (top - 0.2) / 2, sz * size / 2)), C.Steel, M.Metal)
				-- filet : poteau + rembourrage
				Fixed(r, "NetPole", Vector3.new(0.18, 6, 0.18), CFrame.new(c + Vector3.new(sx * (size / 2 + 0.3), top + 3, sz * (size / 2 + 0.3))), Color3.fromRGB(40, 40, 48), M.Metal)
				Fixed(r, "PoleFoam", Vector3.new(0.34, 5, 0.34), CFrame.new(c + Vector3.new(sx * (size / 2 + 0.3), top + 2.8, sz * (size / 2 + 0.3))), color, M.Fabric)
			end
		end
		-- filet (3 côtés ; le 4e ouvert : l'entrée, côté parvis -Z)
		for _, side in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
			local horizontal = side[1] == 0
			local s = if horizontal then Vector3.new(size + 0.6, 5, 0.05) else Vector3.new(0.05, 5, size + 0.6)
			local net = Fixed(r, "Net", s, CFrame.new(c + Vector3.new(side[1] * (size / 2 + 0.3), top + 3.1, side[2] * (size / 2 + 0.3))), Color3.fromRGB(30, 30, 36), M.Fabric)
			net.Transparency = 0.72
			Solid(net)
			net.CastShadow = false
		end
		-- toile (solide, locale : on marche / rebondit dessus)
		local bed = Solid(Fixed(r, "TrampolineBed", Vector3.new(size - 0.2, 0.1, size - 0.2), CFrame.new(c + Vector3.new(0, top - 0.05, 0)), Color3.fromRGB(30, 30, 36), M.Fabric))
		bed.CanQuery = true
		bed.CastShadow = false
		table.insert(beds, { Part = bed, Center = r.Base * (c + Vector3.new(0, top, 0)), Home = bed.CFrame, Dip = 0 })
	end
	-- panneau
	local board = Fixed(r, "Board", Vector3.new(6, 1.4, 0.2), CFrame.new(0, 4.2, -6.8), Color3.fromRGB(255, 250, 244), M.SmoothPlastic)
	FairKit.Sign(board, "🤸 " .. Locale.T("Trampolines"), Color3.fromRGB(56, 140, 220), Color3.fromRGB(255, 250, 244))
	for _, sx in ipairs({ -2.8, 2.8 }) do
		Solid(Fixed(r, "BoardLeg", Vector3.new(0.2, 3.6, 0.2), CFrame.new(sx, 1.8, -6.8), C.White, M.Metal))
	end
	-- invite locale "Sauter" (E) : pose l'avatar au-dessus d'une toile libre
	local host = Fixed(r, "JumpGate", Vector3.new(1, 3, 1), CFrame.new(0, 1.5, -7.6), C.White, M.SmoothPlastic)
	host.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FairLocalPrompt"
	prompt.ActionText = Locale.T("Jump!")
	prompt.ObjectText = "🤸 " .. Locale.T("Trampolines")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	local tramp = { Beds = beds, Streak = 0, LastBounce = 0 }
	prompt.Triggered:Connect(function()
		local character = LocalPlayer and LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			return
		end
		-- toile la moins occupée (personne au-dessus, de préférence)
		local best, bestScore = beds[1], math.huge
		for _, b in ipairs(beds) do
			local score = 0
			for _, pl in ipairs(Players:GetPlayers()) do
				local ch = pl.Character
				local rp = ch and ch:FindFirstChild("HumanoidRootPart")
				if rp and rp:IsA("BasePart") and pl ~= LocalPlayer then
					local d = Vector3.new(rp.Position.X - b.Center.X, 0, rp.Position.Z - b.Center.Z).Magnitude
					if d < size then
						score += 1
					end
				end
			end
			score += math.random() * 0.1
			if score < bestScore then
				best, bestScore = b, score
			end
		end
		pcall(function()
			character:PivotTo(CFrame.new(best.Center + Vector3.new(0, 4, 0)) * (r.Base.Rotation))
		end)
	end)
	r.Extra = {
		Tramp = tramp,
		Step = function(_t: number)
			-- (toiles qui se creusent sous le rebond : retour élastique)
			local parts, frames = {}, {}
			for _, b in ipairs(beds) do
				if b.Dip > 0.001 then
					b.Dip = b.Dip * 0.82
					table.insert(parts, b.Part)
					table.insert(frames, b.Home * CFrame.new(0, -b.Dip, 0))
				end
			end
			if #parts > 0 then
				workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end,
	}
	r.Radius = 12
end

-- Rebond de l'avatar LOCAL (à chaque image, près des trampolines) : le
-- client possède la physique de son avatar -> la vitesse est répliquée
function FairAnnexFx.StepTrampolines(r: RideFx, jumpHeld: boolean)
	local extra = r.Extra
	if not extra or not extra.Tramp then
		return
	end
	local character = LocalPlayer and LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil then
		return
	end
	local tramp = extra.Tramp
	local pos = root.Position
	local half = FairRides.TRAMPOLINE_BED / 2 - 0.3
	for _, b in ipairs(tramp.Beds) do
		local rel = r.Base:PointToObjectSpace(pos) - r.Base:PointToObjectSpace(b.Center)
		if math.abs(rel.X) < half and math.abs(rel.Z) < half then
			-- hauteur des pieds au-dessus de la toile
			local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
			local hip = legs + root.Size.Y / 2
			local feet = rel.Y - hip
			local vy = root.AssemblyLinearVelocity.Y
			if feet < 0.35 and vy <= 2 and os.clock() - tramp.LastBounce > 0.18 then
				tramp.LastBounce = os.clock()
				tramp.Streak = math.min(tramp.Streak + 1, 4)
				local speed = if jumpHeld then FairRides.TRAMPOLINE_BOOST else FairRides.TRAMPOLINE_BOUNCE + tramp.Streak * 2
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X * 0.7, speed, v.Z * 0.7)
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				end)
				b.Dip = 0.45
			end
			return
		end
	end
	if os.clock() - tramp.LastBounce > 1.5 then
		tramp.Streak = 0
	end
end

----------------------------------------------------------------------
-- 🪞 Palais des glaces (labyrinthe de miroirs)
----------------------------------------------------------------------

-- Labyrinthe : grille 5 x 4 cases de 3 studs (x -7,5..7,5, z -6..6) ; entrée
-- case (0, 0) et sortie case (4, 0), côté façade (-Z). PASSAGES ouverts
-- entre cases voisines (chemin + 2 culs-de-sac) ; tous les autres côtés
-- intérieurs sont des murs de miroirs. (Vérifié : toutes les cases sont
-- reliées, un seul chemin de l'entrée à la sortie.)
local MAZE_PASSAGES = {
	"0,0-0,1", "0,1-0,2", "0,2-1,2", "1,2-1,1", "1,1-2,1", "2,1-2,2", "2,2-2,3", "2,3-3,3", "3,3-4,3",
	"4,3-4,2", "4,2-3,2", "3,2-3,1", "3,1-4,1", "4,1-4,0",
	"0,0-1,0", "1,0-2,0", "2,0-3,0", "0,2-0,3", "0,3-1,3",
}
FairAnnexFx.MAZE_PASSAGES = MAZE_PASSAGES

local function mazeWalls(): { { number } }
	local open = {}
	for _, s in ipairs(MAZE_PASSAGES) do
		open[s] = true
		local a, b = string.match(s, "^(.-)%-(.-)$")
		open[(b :: string) .. "-" .. (a :: string)] = true
	end
	local walls = {}
	for c = 0, 4 do
		for k = 0, 3 do
			local x0, z0 = -7.5 + c * 3, -6 + k * 3
			if c < 4 and not open[c .. "," .. k .. "-" .. (c + 1) .. "," .. k] then
				table.insert(walls, { x0 + 3, z0, x0 + 3, z0 + 3 })
			end
			if k < 3 and not open[c .. "," .. k .. "-" .. c .. "," .. (k + 1)] then
				table.insert(walls, { x0, z0 + 3, x0 + 3, z0 + 3 })
			end
		end
	end
	return walls
end

function FairAnnexFx.BuildMirrors(r: RideFx)
	local frame = Color3.fromRGB(226, 190, 96)
	local glass = Color3.fromRGB(214, 226, 236)
	local W, D, H = 15, 12, 6.5
	Solid(Fixed(r, "Floor", Vector3.new(W + 1, 0.2, D + 1), CFrame.new(0, 0.1, 0), Color3.fromRGB(60, 50, 80), M.Marble))
	local function mirrorWall(a: Vector3, b: Vector3, solidWall: boolean)
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b)
		-- panneaux de 1,5 : cadre doré + miroir (légèrement bombés, alternés)
		local n = math.max(1, math.floor(len / 1.5 + 0.5))
		for i = 0, n - 1 do
			local z = -len / 2 + (i + 0.5) * len / n
			local tilt = CFrame.Angles(0, math.rad(if i % 2 == 0 then 3 else -3), 0)
			local pane = Fixed(r, "Mirror", Vector3.new(0.12, H - 0.9, len / n - 0.12), cf * CFrame.new(0, H / 2 + 0.1, z) * tilt, glass, M.SmoothPlastic)
			pane.Reflectance = 0.85
			if solidWall then
				Solid(pane)
				pane.CastShadow = false
			end
			Fixed(r, "MirrorFrame", Vector3.new(0.2, 0.2, len / n), cf * CFrame.new(0, H - 0.3, z), frame, M.Metal)
			Fixed(r, "MirrorFrame", Vector3.new(0.2, 0.3, len / n), cf * CFrame.new(0, 0.35, z), frame, M.Metal)
		end
		Fixed(r, "Post", Vector3.new(0.3, H, 0.3), CFrame.new(a + Vector3.new(0, H / 2, 0)), frame, M.Metal)
	end
	-- murs extérieurs (entrée et sortie sur la façade -Z)
	local x0, x1, z0, z1 = -W / 2, W / 2, -D / 2, D / 2
	mirrorWall(Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1), true)
	mirrorWall(Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1), true)
	mirrorWall(Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), true)
	mirrorWall(Vector3.new(-4.5, 0, z0), Vector3.new(4.5, 0, z0), true)
	for _, w in ipairs(mazeWalls()) do
		mirrorWall(Vector3.new(w[1], 0, w[2]), Vector3.new(w[3], 0, w[4]), true)
	end
	-- toit (verrière opaque) + frise à ampoules + fronton
	Fixed(r, "Roof", Vector3.new(W + 1.2, 0.4, D + 1.2), CFrame.new(0, H + 0.2, 0), Color3.fromRGB(120, 70, 150), M.SmoothPlastic).CastShadow = true
	Fixed(r, "Fascia", Vector3.new(W + 1.3, 1.2, 0.3), CFrame.new(0, H - 0.2, z0 - 0.7), Color3.fromRGB(150, 90, 190), M.SmoothPlastic)
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-7.4, H - 0.2, z0 - 0.9), r.Base * Vector3.new(7.4, H - 0.2, z0 - 0.9), 15, 0.28, { C.Bulb, C.Pink, C.Sky })
	local board = Fixed(r, "Board", Vector3.new(9, 1.8, 0.25), CFrame.new(0, H + 1.4, z0 - 0.6), Color3.fromRGB(150, 90, 190), M.SmoothPlastic)
	FairKit.Sign(board, "🪞 " .. Locale.T("Hall of mirrors"), Color3.fromRGB(255, 240, 200), Color3.fromRGB(150, 90, 190))
	-- miroirs déformants à l'entrée (bombés : sphères écrasées + cadre)
	for _, sx in ipairs({ -1, 1 }) do
		local base = CFrame.new(sx * 6, 0, z0 - 1.6) * CFrame.Angles(0, math.rad(sx * 20), 0)
		local m = Fixed(r, "FunMirror", Vector3.new(2.6, 4.6, 0.5), base * CFrame.new(0, 2.6, 0), glass, M.SmoothPlastic, BALL)
		m.Reflectance = 0.75
		Fixed(r, "FunFrame", Vector3.new(0.3, 4.2, 0.3), base * CFrame.new(-1.35, 2.3, 0.1), frame, M.Metal)
		Fixed(r, "FunFrame", Vector3.new(0.3, 4.2, 0.3), base * CFrame.new(1.35, 2.3, 0.1), frame, M.Metal)
		Fixed(r, "FunFoot", Vector3.new(2.8, 0.3, 1), base * CFrame.new(0, 0.15, 0.1), frame, M.Metal)
	end
	r.Radius = 12
end

return FairAnnexFx
