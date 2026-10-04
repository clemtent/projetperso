--[[
	TownPark (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownPark

	🛝 Aire de jeux de Dopamine Town, côté SERVEUR (v9.9, PARK99).
	Le serveur ne pose que le SQUELETTE qui doit exister pour tout le monde :
	  - le sol souple, les murs invisibles de la clôture (portillon côté place),
	    les volumes où l'on marche (plancher de la tour, glissière, tourniquet,
	    corps des jeux à ressort) et un mur d'escalade (TrussPart invisible :
	    on y grimpe "pour de vrai", comme une échelle Roblox) ;
	  - les SIÈGES (Seat invisibles, ancrés) des jeux qui bougent : 3
	    balançoires, 2 places du tape-cul, 4 du tourniquet, 2 jeux à ressort,
	    et les 2 bancs des parents (2 places chacun) ;
	  - les invites (E) : "Se balancer" / "Monter" / "S'asseoir" sur les
	    sièges (le serveur assoit : Seat:Sit), et "Glisser" / "Traverser" /
	    "Creuser" sur des repères invisibles (gérées par le CLIENT : ParkPlay
	    anime alors l'avatar : échelle + glissade, barres de singe, pelle).
	Tout le décor réaliste (portique, chaînes, tour, glissière, chevaux,
	clôture, bac à sable...) est construit côté CLIENT près de l'avatar
	(ParkPlay, appelé par TownGreenery : attribut NearDetail "Playground").

	Mouvement : quand le 1er enfant monte sur un jeu (ou le dernier descend),
	le serveur pose sur le Model du jeu les attributs On / T0 / A0 / W0
	(ParkMotion.Transition) ; chaque client en déduit la même pose, à chaque
	image, et déplace localement le siège (l'avatar assis suit, sans à-coup).

	+ TownPark.BenchPrompts(folder) : invite "S'asseoir" (E) sur les bancs du
	  parc (Models "Bench" de TownKit.Bench sous `folder`).

	API (TownNature.playground) :
	  TownPark.Build(model, g)   g = centre de l'aire au sol, -Z vers la place
	  TownPark.BenchPrompts(folder)
	  TownPark.ScenePlaces(model, F, kind, seed) -> nombre de Seats (v11)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParkMotion = require(ReplicatedStorage.Shared.ParkMotion)
local ParkLayout = require(ReplicatedStorage.Shared.ParkLayout) -- (v11, PARK11) places assises des scènes de parc
local TownKit = require(script.Parent.TownKit)

local TownPark = {}

local M = TownKit.M
local part = TownKit.Part

local PROMPT_RANGE = 8
local SIT_RANGE = 14 -- (studs) l'avatar doit être tout près
local COOLDOWN = 0.5 -- (s) entre deux demandes d'un même joueur
local RUBBER = Color3.fromRGB(214, 112, 96)

local lastAsk: { [Player]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Pièce invisible (repère, siège) : ni vue, ni visée, ni touchée
local function hidden(p: BasePart): BasePart
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- Invite (textes anglais ; ParkPlay les traduit : attributs LocAction / LocObject)
local function prompt(host: BasePart, action: string, object: string, kind: string?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "ParkPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = PROMPT_RANGE
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p:SetAttribute("LocAction", action)
	p:SetAttribute("LocObject", object)
	if kind then
		p:SetAttribute("ParkAction", kind)
	end
	p.Parent = host
	return p
end

local function characterOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

----------------------------------------------------------------------
-- Jeux (Model + sièges) et leurs attributs de mouvement
----------------------------------------------------------------------

type Piece = { Model: Model, Kind: string, Seats: { Seat } }

local function writeState(model: Model, s: ParkMotion.State)
	model:SetAttribute("On", s.On)
	model:SetAttribute("T0", s.T0)
	model:SetAttribute("A0", s.A0)
	model:SetAttribute("W0", s.W0)
end

local function riders(piece: Piece): number
	local n = 0
	for _, seat in ipairs(piece.Seats) do
		if seat.Parent and seat.Occupant then
			n += 1
		end
	end
	return n
end

local function refresh(piece: Piece)
	if not piece.Model.Parent or piece.Kind == "Bench" then
		return
	end
	local on = riders(piece) > 0
	local s = ParkMotion.StateOf(piece.Model)
	if s.On ~= on then
		writeState(piece.Model, ParkMotion.Transition(piece.Kind, s, serverNow(), on))
	end
end

local function newPiece(parent: Instance, name: string, kind: string): Piece
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("ParkKind", kind)
	if kind ~= "Bench" then
		writeState(model, { On = false, T0 = 0, A0 = 0, W0 = 0 })
	end
	model.Parent = parent
	return { Model = model, Kind = kind, Seats = {} }
end

-- Siège invisible `slot` du jeu `piece`, dessus en `topCF` (repère monde)
local ACTIONS = {
	Swing = { "Swing", "Swing seat" },
	Seesaw = { "Ride", "Seesaw" },
	Merry = { "Ride", "Merry-go-round" },
	Spring = { "Ride", "Spring rider" },
	Bench = { "Sit", "Bench" },
}

local function addSeat(piece: Piece, slot: number, topCF: CFrame, size: Vector3)
	local seat = part(piece.Model, "ParkSeat", size, topCF * CFrame.new(0, -size.Y / 2, 0), Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "deco", "Seat") :: Seat
	hidden(seat)
	seat:SetAttribute("ParkSlot", slot)
	if piece.Kind == "Bench" then
		seat:SetAttribute("SitKind", "bench") -- (SitAnimator : pose + attentes du banc)
	else
		seat:SetAttribute("SitKind", "ride")
		seat:SetAttribute("ParkPose", true) -- (ParkPlay anime l'enfant : mains sur les chaînes...)
	end
	table.insert(piece.Seats, seat)
	local texts = ACTIONS[piece.Kind] or ACTIONS.Bench
	local p = prompt(seat, texts[1], texts[2], "Sit")
	p.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if lastAsk[player] and now - lastAsk[player] < COOLDOWN then
			return
		end
		lastAsk[player] = now
		local _, humanoid, root = characterOf(player)
		if not humanoid or not root or not seat.Parent or humanoid.SeatPart ~= nil or seat.Occupant ~= nil then
			return
		end
		if (root.Position - seat.Position).Magnitude > SIT_RANGE then
			return
		end
		pcall(seat.Sit, seat, humanoid)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		refresh(piece)
	end)
end

-- Repère invisible d'une invite gérée par le client
local function anchor(model: Instance, name: string, cf: CFrame, action: string, object: string, kind: string, range: number?)
	local a = hidden(part(model, name, Vector3.new(1, 1, 1), cf, Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "deco"))
	local p = prompt(a, action, object, kind)
	p.MaxActivationDistance = range or 6
	return a
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownPark.Build(model: Model, g: CFrame)
	local W, D = ParkMotion.W, ParkMotion.D
	-- sol souple (dessus à FLOOR_TOP)
	part(model, "SoftFloor", Vector3.new(W, 0.3, D), g * CFrame.new(0, ParkMotion.FLOOR_TOP - 0.15, 0), RUBBER, M.Rubber, "solid")
	-- murs invisibles de la clôture (portillon ouvert face à la place)
	local hw, hd = W / 2 + 0.6, D / 2 + 0.6
	local gate = ParkMotion.GATE
	local function wall(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		part(model, "FenceWall", Vector3.new(0.4, 2.8, len), g * CFrame.lookAt(mid + Vector3.new(0, 1.4, 0), b + Vector3.new(0, 1.4, 0)), Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "ghost")
	end
	wall(Vector3.new(-hw, 0, hd), Vector3.new(hw, 0, hd))
	wall(Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, hd))
	wall(Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd))
	wall(Vector3.new(-hw, 0, -hd), Vector3.new(-gate - 0.3, 0, -hd))
	wall(Vector3.new(gate + 0.3, 0, -hd), Vector3.new(hw, 0, -hd))

	-- 🛝 toboggan : plancher de la tour, glissière (on peut marcher dessus),
	-- mur d'escalade (-X) grimpable, invites "Glisser"
	local S = ParkMotion.SLIDE
	local tower = g * ParkMotion.SlideTower()
	local slideModel = newPiece(model, "Slide", "Slide").Model
	local deck = part(slideModel, "TowerDeck", Vector3.new(S.Deck, 0.4, S.Deck), tower * CFrame.new(0, S.DeckTop - 0.2, 0), RUBBER, M.WoodPlanks, "ghost")
	deck.CanQuery = true
	local P = S.Profile
	local zA, yA = P[3][1], P[3][2]
	local zB, yB = P[4][1], P[4][2]
	local a = tower * Vector3.new(0, yA - 0.2, zA)
	local b = tower * Vector3.new(0, yB - 0.2, zB)
	part(slideModel, "ChuteSlope", Vector3.new(1.8, 0.3, (b - a).Magnitude + 0.6), CFrame.lookAt((a + b) / 2, b), RUBBER, M.SmoothPlastic, "ghost")
	part(slideModel, "ChuteOut", Vector3.new(1.8, 0.3, P[#P][1] - P[4][1] + 0.3), tower * CFrame.new(0, (P[5][2] + P[6][2]) / 2 - 0.2, (P[4][1] + P[#P][1]) / 2 + 0.15), RUBBER, M.SmoothPlastic, "ghost")
	local truss = Instance.new("TrussPart")
	truss.Name = "ClimbWall"
	truss.Anchored = true
	truss.Size = Vector3.new(2, 6, 2)
	truss.CFrame = tower * CFrame.new(-S.Deck / 2 - 1.05, 3, 0)
	truss.Transparency = 1
	truss.CanTouch = false
	truss.CanQuery = false
	truss.CastShadow = false
	truss.Parent = slideModel
	anchor(slideModel, "SlideLadder", tower * CFrame.new(0, 2.6, S.LadderZ - 1.2), "Slide", "Slide tower", "Slide", 7)
	anchor(slideModel, "SlideTop", tower * CFrame.new(0, S.DeckTop + 2.2, 0.8), "Slide", "Slide tower", "SlideTop", 5)

	-- 🐒 barres de singe (invites aux deux bouts, côté sol)
	local Mk = ParkMotion.MONKEY
	local monkeyModel = newPiece(model, "MonkeyBars", "Monkey").Model
	anchor(monkeyModel, "MonkeyA", g * CFrame.new(Mk.X0 - 1.1, 2.6, Mk.Z), "Cross", "Monkey bars", "MonkeyA", 6)
	anchor(monkeyModel, "MonkeyB", g * CFrame.new(Mk.X1 + 1.1, 2.6, Mk.Z), "Cross", "Monkey bars", "MonkeyB", 6)

	-- 🏖️ bac à sable
	local sandModel = newPiece(model, "Sandbox", "Sand").Model
	anchor(sandModel, "SandSpot", g * CFrame.new(ParkMotion.SAND.Center + Vector3.new(0, 1.2, 0)), "Dig", "Sandbox", "Dig", 7)

	-- 🎠 balançoires
	for i = 1, #ParkMotion.SWING.Xs do
		local piece = newPiece(model, "Swing" .. i, "Swing")
		piece.Model:SetAttribute("ParkIndex", i)
		addSeat(piece, 1, g * ParkMotion.SwingSeat(i, 0), Vector3.new(1.8, 0.2, 1.0))
	end
	-- ⚖️ tape-cul
	local seesaw = newPiece(model, "Seesaw", "Seesaw")
	local restAngle = ParkMotion.SeesawAngle(0, 0)
	for k = 1, 2 do
		addSeat(seesaw, k, g * ParkMotion.SeesawSeat(k, restAngle), Vector3.new(1.4, 0.2, 1.2))
	end
	-- 🌀 tourniquet (plateau : on peut y monter à pied)
	local merry = newPiece(model, "Merry", "Merry")
	local mc = ParkMotion.MERRY
	local deckDisc = TownKit.Disc(merry.Model, "MerryDeck", (g * CFrame.new(mc.Center + Vector3.new(0, mc.DeckTop, 0))).Position, mc.Radius, 0.7, RUBBER, M.Metal, "ghost")
	deckDisc.CanQuery = true
	for k = 1, mc.Seats do
		addSeat(merry, k, g * ParkMotion.MerrySeat(k, 0), Vector3.new(1.3, 0.2, 1.1))
	end
	-- 🐴 jeux à ressort (corps : bloc invisible pour ne pas passer à travers)
	for i = 1, #ParkMotion.SPRINGS do
		local piece = newPiece(model, "Spring" .. i, "Spring")
		piece.Model:SetAttribute("ParkIndex", i)
		part(piece.Model, "SpringBody", Vector3.new(1.3, 1.6, 2.6), g * ParkMotion.SpringBase(i) * CFrame.new(0, 1.3, 0), RUBBER, M.SmoothPlastic, "ghost")
		addSeat(piece, 1, g * ParkMotion.SpringSeat(i, 0, 0), Vector3.new(1.1, 0.2, 1.2))
	end
	-- 🪑 bancs des parents (2 places par banc)
	for bi = 1, #ParkMotion.BENCHES do
		local piece = newPiece(model, "ParkBench" .. bi, "Bench")
		piece.Model:SetAttribute("ParkIndex", bi)
		for k = 1, #ParkMotion.BENCH.Places do
			addSeat(piece, k, g * ParkMotion.BenchSeat(bi, k), Vector3.new(2.2, 0.2, 1.9))
		end
		part(piece.Model, "BenchBlock", Vector3.new(ParkMotion.BENCH.Length, ParkMotion.BENCH.SeatTop - 0.1, 2.0), g * ParkMotion.BenchFrame(bi) * CFrame.new(0, (ParkMotion.BENCH.SeatTop - 0.1) / 2, -0.15), RUBBER, M.Wood, "ghost")
	end
end

----------------------------------------------------------------------
-- (v11, PARK11) Places LIBRES des scènes de parc construites côté client
-- (roseraie, kiosque, place de la fontaine, bancs le long des allées,
-- tables de pique-nique...) : un Seat invisible par place (plan partagé
-- ParkLayout ; les places des PNJ n'en ont pas). Dessus du Seat = dessus
-- des lattes (SCALE11 : 1,85), centré sur l'assise, regard = LookVector.
----------------------------------------------------------------------

function TownPark.ScenePlaces(model: Model, F: CFrame, kind: string, seed: number): number
	local places = ParkLayout.Seats(kind, seed)
	if #places == 0 then
		return 0
	end
	local piece = newPiece(model, "SceneSeats", "Bench")
	local n = 0
	for _, st in ipairs(places) do
		if not st.Npc then
			n += 1
			addSeat(piece, n, F * st.CF, Vector3.new(2.2, 0.2, 1.9))
		end
	end
	return n
end

----------------------------------------------------------------------
-- Bancs du parc (TownKit.Bench) : invite "S'asseoir" (E)
----------------------------------------------------------------------

function TownPark.BenchPrompts(folder: Instance)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Seat") and d.Name == "Seat" and d.Parent and d.Parent.Name == "Bench" and not d:FindFirstChild("ParkPrompt") then
			local seat = d
			local p = prompt(seat, "Sit", "Bench", "Sit")
			p.MaxActivationDistance = 7
			p.Triggered:Connect(function(player: Player)
				local now = os.clock()
				if lastAsk[player] and now - lastAsk[player] < COOLDOWN then
					return
				end
				lastAsk[player] = now
				local _, humanoid, root = characterOf(player)
				if not humanoid or not root or not seat.Parent or humanoid.SeatPart ~= nil or seat.Occupant ~= nil then
					return
				end
				if (root.Position - seat.Position).Magnitude > SIT_RANGE then
					return
				end
				pcall(seat.Sit, seat, humanoid)
			end)
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastAsk[player] = nil
end)

return TownPark
