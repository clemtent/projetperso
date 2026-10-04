--[[
	RainbowService (ModuleScript)
	Emplacement : ServerScriptService > Services > RainbowService

	v11 (REALISM11) 🌈 le POT D'OR au pied de l'arc-en-ciel, validé par le
	SERVEUR (aucun remote : le client ne peut rien "réclamer").
	  - L'horloge de la météo est partagée (Shared/RainbowGold : mêmes
	    épisodes que Weather3D chez tous les clients). Quand un arc-en-ciel
	    "s'ouvre" (RainbowGold.Event(t).Open), le serveur choisit la place du
	    pot : la 1re place candidate (RainbowGold.Candidates / Order : sur un
	    trottoir) dont le sol est plat, au bon niveau, pas de l'eau, rien de
	    bâti au-dessus (5 lancers de rayon), et la publie :
	      workspace PotOfGoldId = n° de l'arc-en-ciel (-1 = aucun),
	      PotOfGoldPos (Vector3, au sol), PotOfGoldWinners, PotOfGoldMax,
	      PotOfGoldFirst (nom du 1er gagnant).
	  - 4 fois / s : chaque joueur EN VILLE dont la position (serveur) reste
	    RainbowGold.CONFIG.Dwell s dans le rayon du pot gagne, dans l'ordre
	    d'arrivée (3 gagnants au plus) : RainbowGold.Reward (secondes de
	    production 240 / 150 / 100, minimum, 6 pots payés par jour au plus,
	    une seule fois par arc-en-ciel). Refusé juste après un "saut"
	    (téléportation : RainbowGold.IsJump, attente JumpHold s).
	  - Gain : Dopamine (GameService:AddDopamine), notification, attribut
	    du joueur PotOfGoldWin = "id|place|montant" (les clients font la
	    gerbe de pièces : RainbowFx), annonce aux autres joueurs en ville.
	Données : data.Rainbow = { Day, Rewarded, Pots, Firsts, LastId }
	(RainbowGold.SanitizeData ; créé ici si absent).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RainbowGold = require(ReplicatedStorage.Shared.RainbowGold)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

local RainbowService = {}

local CFG = RainbowGold.CONFIG
local TICK = 0.25

local services: any = nil

type Pot = {
	Id: number,
	Pos: Vector3,
	Places: number, -- gagnants payés (ou capés) dans l'ordre
	Done: { [number]: boolean }, -- UserId déjà passés
}
local pot: Pot? = nil
local finished: { [number]: boolean } = {} -- arcs-en-ciel terminés (jamais rouverts)
type Track = { Pos: Vector3, At: number, JumpUntil: number, DwellFrom: number? }
local tracks: { [Player]: Track } = {}
local clock = 0
local connection: RBXScriptConnection? = nil

local clockFn: (() -> number)? = nil -- (tests : heure imposée)

local function now(): number
	local fn = clockFn
	if fn then
		return fn()
	end
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.time()
end

local function T(player: Player, text: string, ...): string
	if services and services.GameService then
		return services.GameService:T(player, text, ...)
	end
	return string.format(text, ...)
end

local function inTown(player: Player): boolean
	local world = services and services.WorldService
	if world and type(world.IsInTown) == "function" then
		local ok, result = pcall(world.IsInTown, world, player)
		return ok and result == true
	end
	return false
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then
			return nil
		end
		return root
	end
	return nil
end

----------------------------------------------------------------------
-- Place du pot (sol plat, au bon niveau, pas d'eau, rien au-dessus)
----------------------------------------------------------------------

local WATER_NAMES = { "water", "lake", "pond", "fountain", "pool", "eau", "lac", "bassin", "fontaine" }

local function isWater(inst: Instance, material: Enum.Material): boolean
	if material == Enum.Material.Water then
		return true
	end
	local name = string.lower(inst.Name)
	for _, word in ipairs(WATER_NAMES) do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function probe(base: Vector3, exclude: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = false
	local center: Vector3? = nil
	local offsets = { Vector3.zero, Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0), Vector3.new(0, 0, 2.5), Vector3.new(0, 0, -2.5) }
	for i, off in ipairs(offsets) do
		local ok, hit = pcall(function()
			return workspace:Raycast(base + off + Vector3.new(0, 220, 0), Vector3.new(0, -400, 0), params)
		end)
		if not ok or not hit then
			return nil
		end
		-- premier obstacle = le sol lui-même (pas un toit, pas un arbre du serveur)
		if hit.Normal.Y < 0.9 or math.abs(hit.Position.Y - base.Y) > 3 or isWater(hit.Instance, hit.Material) then
			return nil
		end
		if i == 1 then
			center = hit.Position
		end
	end
	return center
end

local function chooseSpot(id: number): Vector3?
	local count = WorldLayout.PlotCount(Players.MaxPlayers)
	local spots = RainbowGold.Candidates(count)
	if #spots == 0 then
		return nil
	end
	local exclude: { Instance } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local order = RainbowGold.Order(id, #spots)
	for _, index in ipairs(order) do
		local spot = spots[index]
		local base = WorldLayout.CityPoint(spot.X, spot.Y, spot.Z)
		local ground = probe(base, exclude)
		if ground then
			return ground
		end
	end
	-- (ville pas encore construite / rien de valide : la place prévue par le plan)
	local spot = spots[order[1]]
	return WorldLayout.CityPoint(spot.X, spot.Y, spot.Z)
end

local function publish(p: Pot?)
	if p then
		workspace:SetAttribute("PotOfGoldMax", CFG.MaxWinners)
		workspace:SetAttribute("PotOfGoldWinners", p.Places)
		workspace:SetAttribute("PotOfGoldPos", p.Pos)
		workspace:SetAttribute("PotOfGoldFirst", "")
		workspace:SetAttribute("PotOfGoldId", p.Id)
	else
		workspace:SetAttribute("PotOfGoldId", -1)
		workspace:SetAttribute("PotOfGoldWinners", 0)
	end
end

----------------------------------------------------------------------
-- Gain
----------------------------------------------------------------------

local function rainbowData(player: Player): any
	local data = services and services.DataService and services.DataService:GetData(player)
	if not data then
		return nil
	end
	data.Rainbow = RainbowGold.SanitizeData(data.Rainbow, RainbowGold.Today(os.time()))
	return data.Rainbow
end

local function award(player: Player, p: Pot)
	local rd = rainbowData(player)
	if not rd then
		return
	end
	p.Done[player.UserId] = true
	if rd.LastId == p.Id then
		return -- (déjà payé pour cet arc-en-ciel : nouvelle session, même arc)
	end
	local place = p.Places + 1
	local stats = services.GameService:GetStats(player)
	local amount, _seconds, capped = RainbowGold.Reward(stats, place, rd.Rewarded)
	if capped then
		services.GameService:Notify(player, { Type = "Info", Text = T(player, "🌈 Daily pot of gold limit reached: come back tomorrow!") })
		return
	end
	if amount <= 0 then
		return
	end
	p.Places = place
	services.GameService:AddDopamine(player, amount)
	rd.Rewarded += 1
	rd.Pots += 1
	if place == 1 then
		rd.Firsts += 1
	end
	rd.LastId = p.Id
	services.GameService:MarkDirty(player)
	workspace:SetAttribute("PotOfGoldWinners", p.Places)
	player:SetAttribute("PotOfGoldWin", string.format("%d|%d|%d", p.Id, place, math.floor(math.min(amount, 2 ^ 52))))
	services.GameService:Notify(player, {
		Type = "Info",
		Text = T(player, "🌈 Pot of gold! You arrived #%d: +%s Dopamine", place, NumberFormatter.Format(amount)),
	})
	if place == 1 then
		workspace:SetAttribute("PotOfGoldFirst", player.DisplayName)
		local name = player.DisplayName
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and inTown(other) then
				services.GameService:Notify(other, {
					Type = "Info",
					Text = Locale.TFor(services.GameService:GetLanguage(other), "🌈 %s found the pot of gold! Hurry, %d left", name, CFG.MaxWinners - 1),
				})
			end
		end
	end
end

----------------------------------------------------------------------
-- Boucle (4 fois / s)
----------------------------------------------------------------------

local function step()
	local t = now()
	local event = RainbowGold.Event(t)
	local p = pot
	-- fin de l'arc-en-ciel (ou un autre a commencé)
	if p and (not event or event.Id ~= p.Id or not event.Open) then
		finished[p.Id] = true
		pot = nil
		p = nil
		publish(nil)
	end
	-- ouverture
	if not p and event and event.Open and not finished[event.Id] then
		local pos = chooseSpot(event.Id)
		if pos then
			p = { Id = event.Id, Pos = pos, Places = 0, Done = {} }
			pot = p
			publish(p)
		else
			finished[event.Id] = true
		end
	end
	-- joueurs : sauts, présence au pied de l'arc
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local town = inTown(player)
		if not root or not town then
			tracks[player] = nil
		else
			local pos = root.Position
			local tr = tracks[player]
			if not tr then
				-- (arrivée en ville / réapparition = un saut : petite attente)
				tr = { Pos = pos, At = t, JumpUntil = t + CFG.JumpHold, DwellFrom = nil }
				tracks[player] = tr
			else
				if RainbowGold.IsJump((pos - tr.Pos).Magnitude, t - tr.At) then
					tr.JumpUntil = t + CFG.JumpHold
					tr.DwellFrom = nil
				end
				tr.Pos = pos
				tr.At = t
			end
			if p and p.Places < CFG.MaxWinners and not p.Done[player.UserId] then
				local d = pos - p.Pos
				if RainbowGold.InReach(d.X, d.Y, d.Z) and t >= tr.JumpUntil then
					tr.DwellFrom = tr.DwellFrom or t
					if t - (tr.DwellFrom :: number) >= CFG.Dwell then
						local ok, err = pcall(award, player, p)
						if not ok then
							warn("[RainbowService] gain : " .. tostring(err))
							p.Done[player.UserId] = true
						end
					end
				else
					tr.DwellFrom = nil
				end
			end
		end
	end
	-- (ménage : on ne garde que les derniers arcs terminés)
	if event then
		for id in pairs(finished) do
			if id < event.Id - 50 then
				finished[id] = nil
			end
		end
	end
end

function RainbowService:Init(allServices)
	services = allServices
end

function RainbowService:PlayerReady(_player: Player, data)
	data.Rainbow = RainbowGold.SanitizeData(data.Rainbow, RainbowGold.Today(os.time()))
end

function RainbowService:PlayerRemoving(player: Player)
	tracks[player] = nil
end

function RainbowService:Start()
	publish(nil)
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock < TICK then
			return
		end
		clock = 0
		local ok, err = pcall(step)
		if not ok then
			warn("[RainbowService] " .. tostring(err))
		end
	end)
end

-- (tests) état courant
function RainbowService:GetPot(): any
	return pot
end

function RainbowService._Step()
	step()
end

function RainbowService._SetClock(fn: (() -> number)?)
	clockFn = fn
end

return RainbowService
