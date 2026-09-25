--[[
	DVDService (ModuleScript)
	Emplacement : ServerScriptService > Services > DVDService

	Logos DVD rebondissants (un par niveau de l'amélioration "Logo DVD").
	Le SERVEUR choisit la trajectoire de chaque logo (position, vitesse, heure
	de départ) et l'envoie au client, qui ne fait que l'afficher. Comme les
	trajectoires sont déterministes (voir DVDMath), le serveur peut :
	  - compter lui-même les rebonds (gain passif à chaque rebond) ;
	  - vérifier si un coin a vraiment été touché : un tricheur ne peut pas
	    inventer de jackpot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DVDMath = require(ReplicatedStorage.Shared.DVDMath)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local DVDService = {}

local services
local random = Random.new()

-- Taille par défaut d'un logo (fraction de l'écran), corrigée dès que le
-- client envoie la vraie taille (DVDResize)
local DEFAULT_W = Config.DVD.LogoSize.X / 1280
local DEFAULT_H = Config.DVD.LogoSize.Y / 720
-- Zone de déplacement "de référence" : les gains de rebond sont ramenés à
-- cette taille, quelle que soit la taille envoyée par le client
local DEFAULT_RX, DEFAULT_RY = 1 - DEFAULT_W, 1 - DEFAULT_H
-- Après un redimensionnement, aucun coin n'est accepté pendant ce délai
-- (sinon le client pourrait choisir une taille qui "fabrique" un coin)
local RESIZE_CORNER_LOCK = 10
-- Temps minimum entre deux jackpots d'un même joueur (sécurité anti-abus)
local JACKPOT_COOLDOWN = 45

--[[
	[Player] = {
		Logos = { { Params, ClaimedCorners = { [k] = true }, LastBX, LastBY, Frac } },
		W, H = taille commune des logos,
		Carry = rebonds pas encore comptés (avant un changement de trajectoire),
		LastClick = os.clock() du dernier clic récompensé (recharge commune),
		LastResize = os.clock() du dernier redimensionnement appliqué,
		LastJackpot = os.clock() du dernier jackpot payé,
	}
]]
local states = {}

function DVDService:Init(allServices)
	services = allServices
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Nouvelle trajectoire aléatoire (angle entre 25° et 65° pour éviter les
-- trajectoires trop horizontales ou verticales)
local function randomParams(w: number, h: number): DVDMath.Params
	local angle = math.rad(random:NextNumber(25, 65))
	local variation = Config.DVD.SpeedVariation or 0
	local speed = Config.DVD.Speed * (1 + random:NextNumber(-variation, variation))
	local signX = random:NextNumber() < 0.5 and -1 or 1
	local signY = random:NextNumber() < 0.5 and -1 or 1
	return {
		X0 = random:NextNumber(0, math.max(0, 1 - w)),
		Y0 = random:NextNumber(0, math.max(0, 1 - h)),
		VX = math.cos(angle) * speed * signX,
		VY = math.sin(angle) * speed * signY,
		T0 = now(),
		W = w,
		H = h,
	}
end

-- (Re)définit la trajectoire d'un logo en repartant les compteurs de rebonds
local function setParams(logo, params: DVDMath.Params)
	logo.Params = params
	logo.ClaimedCorners = {} -- nouvelle trajectoire = nouveaux numéros de rebond
	logo.LastBX, logo.LastBY = DVDMath.BounceIndex(params, now())
end

local function newLogo(w: number, h: number)
	local logo = { Frac = 0 }
	setParams(logo, randomParams(w, h))
	return logo
end

-- Rebonds d'un logo depuis le dernier comptage (plafonnés).
-- Chaque rebond est pondéré par (zone réelle / zone de référence) : un logo
-- plus gros (zone plus petite) rebondit plus souvent mais chaque rebond vaut
-- moins, donc la taille envoyée par le client ne change pas les gains.
local function countBounces(logo, t: number): number
	local params = logo.Params
	local bx, by = DVDMath.BounceIndex(params, t)
	local rx, ry = DVDMath.Ranges(params)
	local weighted = math.abs(bx - logo.LastBX) * rx / DEFAULT_RX + math.abs(by - logo.LastBY) * ry / DEFAULT_RY
	logo.LastBX, logo.LastBY = bx, by
	if weighted ~= weighted or weighted == math.huge then
		return 0
	end
	-- On garde la partie décimale pour le prochain comptage
	logo.Frac = (logo.Frac or 0) + weighted
	local whole = math.floor(logo.Frac)
	logo.Frac -= whole
	return math.min(whole, Config.DVD.MaxBouncesPerTick)
end

-- Avant de changer une trajectoire : on met de côté les rebonds pas encore comptés
local function flushBounces(state)
	local t = now()
	for _, logo in ipairs(state.Logos) do
		state.Carry += countBounces(logo, t)
	end
	state.Carry = math.min(state.Carry, Config.DVD.MaxBouncesPerTick * math.max(1, #state.Logos))
end

-- Nombre de logos que le joueur doit avoir (niveau de "Logo DVD")
local function desiredCount(player: Player): number
	local data = services.DataService:GetData(player)
	if not data then
		return 0
	end
	return Formulas.ComputeStats(data).DVDCount
end

local function isValidIndex(state, index: any): boolean
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= #state.Logos
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function DVDService:SendSetup(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local list = {}
	for _, logo in ipairs(state.Logos) do
		local p = logo.Params
		table.insert(list, { X0 = p.X0, Y0 = p.Y0, VX = p.VX, VY = p.VY, T0 = p.T0, W = p.W, H = p.H })
	end
	Net.Event("DVDSetup"):FireClient(player, { Logos = list })
end

-- Ajoute / retire des logos pour correspondre au niveau de l'amélioration.
-- Les logos existants gardent leur trajectoire. Renvoie true si ça a changé.
function DVDService:SyncLogos(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	local wanted = desiredCount(player)
	local logos = state.Logos
	if #logos == wanted then
		return false
	end
	flushBounces(state)
	while #logos < wanted do
		table.insert(logos, newLogo(state.W, state.H))
	end
	while #logos > wanted do
		table.remove(logos)
	end
	self:SendSetup(player)
	return true
end

-- Détox / reset : tous les logos disparaissent (puis on recrée ceux encore dus)
function DVDService:Reset(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.Logos = {}
	state.Carry = 0
	state.LastClick = 0
	if not self:SyncLogos(player) then
		self:SendSetup(player) -- toujours prévenir le client (liste vide)
	end
end

-- Appelé par le tick passif de GameService : nombre total de rebonds
-- (tous les logos, horizontaux + verticaux) depuis le dernier appel
function DVDService:CollectBounces(player: Player, t: number): number
	local state = states[player]
	if not state then
		return 0
	end
	local total = state.Carry
	state.Carry = 0
	for _, logo in ipairs(state.Logos) do
		total += countBounces(logo, t)
	end
	return total
end

function DVDService:PlayerReady(player: Player)
	states[player] = {
		Logos = {},
		W = DEFAULT_W,
		H = DEFAULT_H,
		Carry = 0,
		LastClick = 0,
		-- -math.huge (et pas 0) : os.clock() peut être petit juste après le démarrage du serveur
		LastResize = -math.huge,
		LastJackpot = -math.huge,
		PendingResize = nil, -- taille reçue trop tôt, appliquée plus tard
		ResizeScheduled = false,
	}
	-- Crée les logos déjà achetés (le client recevra DVDSetup avec la synchro complète)
	local wanted = desiredCount(player)
	for _ = 1, wanted do
		table.insert(states[player].Logos, newLogo(DEFAULT_W, DEFAULT_H))
	end
end

function DVDService:PlayerRemoving(player: Player)
	states[player] = nil
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

-- Applique une nouvelle taille à tous les logos en gardant la position et
-- la direction actuelles de chacun (pour qu'aucun logo ne "saute")
local function applyResize(player: Player, state, w: number, h: number)
	if math.abs(w - state.W) < 1e-4 and math.abs(h - state.H) < 1e-4 then
		return -- rien ne change
	end
	flushBounces(state)
	state.W, state.H = w, h
	state.LastResize = os.clock()
	local t = now()
	for _, logo in ipairs(state.Logos) do
		local params = logo.Params
		local x, y = DVDMath.Position(params, t)
		local dirX, dirY = DVDMath.Directions(params, t)
		-- Borné juste AVANT le bord : un logo collé au bord ne compte pas un
		-- faux rebond et ne se retrouve pas pile sur un "coin"
		setParams(logo, {
			X0 = math.clamp(x, 0, math.max(0, 1 - w - 1e-6)),
			Y0 = math.clamp(y, 0, math.max(0, 1 - h - 1e-6)),
			VX = math.abs(params.VX) * dirX,
			VY = math.abs(params.VY) * dirY,
			T0 = t,
			W = w,
			H = h,
		})
	end
	DVDService:SendSetup(player)
end

-- Le client indique la taille d'un logo à l'écran (en fraction de l'écran).
-- Trop rapproché (< 0.5 s) : la dernière taille reçue est appliquée un peu plus tard.
local function onResize(player: Player, w: any, h: any)
	local state = states[player]
	if not state then
		return
	end
	if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h then
		return
	end
	w = math.clamp(w, 0.03, 0.5)
	h = math.clamp(h, 0.03, 0.5)

	if RateLimiter.Check(player, "DVDResize", 0.5) then
		state.PendingResize = nil
		applyResize(player, state, w, h)
		return
	end
	state.PendingResize = { W = w, H = h }
	if state.ResizeScheduled then
		return
	end
	state.ResizeScheduled = true
	task.delay(0.55, function()
		state.ResizeScheduled = false
		local pending = state.PendingResize
		state.PendingResize = nil
		-- Le joueur a pu partir (ou tout a été réinitialisé) entre-temps
		if pending and states[player] == state then
			applyResize(player, state, pending.W, pending.H)
		end
	end)
end

-- Clic sur un logo : petit bonus, avec un temps de recharge commun à tous les logos
local function onClick(player: Player, index: any)
	local state = states[player]
	local data = services.DataService:GetData(player)
	if not state or not data or not isValidIndex(state, index) then
		return
	end
	local clock = os.clock()
	-- 0.3 s de tolérance pour la latence
	if clock - state.LastClick < Config.DVD.ClickCooldown - 0.3 then
		return
	end
	state.LastClick = clock

	local reward = Formulas.ScaledReward(
		services.GameService:GetStats(player),
		Config.DVD.ClickRewardSeconds,
		Config.DVD.ClickMinReward
	)
	data.Stats.DVDClicks += 1
	services.GameService:AddDopamine(player, reward, true)
	services.GameService:Notify(player, {
		Type = "Bonus",
		Source = "DVD",
		Amount = reward,
		Index = index,
	})
end

-- Le client signale un coin du logo `index` au rebond horizontal numéro k : on VÉRIFIE
local function onCorner(player: Player, index: any, k: any)
	local state = states[player]
	local data = services.DataService:GetData(player)
	if not state or not data or not isValidIndex(state, index) then
		return
	end
	if type(k) ~= "number" or k ~= math.floor(k) or math.abs(k) > 1e9 then
		return
	end
	if not RateLimiter.Check(player, "DVDCorner" .. index, 0.3) then
		return
	end
	local clock = os.clock()
	-- Trajectoire tout juste imposée par un redimensionnement, ou jackpot trop récent : refusé
	if clock - state.LastResize < RESIZE_CORNER_LOCK or clock - state.LastJackpot < JACKPOT_COOLDOWN then
		return
	end
	local logo = state.Logos[index]
	if logo.ClaimedCorners[k] then
		return -- déjà récompensé
	end

	local params = logo.Params
	local bounceTime = DVDMath.BounceTimeX(params, k)
	local t = now()
	-- Le rebond doit avoir eu lieu récemment (et nettement après le début de la
	-- trajectoire : un "rebond" pile au départ n'est qu'un logo posé contre le bord)
	if bounceTime ~= bounceTime or bounceTime < params.T0 + 0.25 or bounceTime > t + 0.5 or bounceTime < t - 5 then
		return
	end
	if not DVDMath.IsCornerAtBounceX(params, k, Config.DVD.CornerTolerance) then
		return -- pas un vrai coin : tentative de triche ou erreur d'arrondi
	end

	logo.ClaimedCorners[k] = true
	state.LastJackpot = clock
	local reward = Formulas.ScaledReward(
		services.GameService:GetStats(player),
		Config.DVD.JackpotRewardSeconds,
		Config.DVD.JackpotMinReward
	)
	data.Stats.DVDCorners += 1
	services.GameService:AddDopamine(player, reward, true)
	services.GameService:Notify(player, {
		Type = "Jackpot",
		Amount = reward,
		Index = index,
		Text = services.GameService:T(player, "📀 PERFECT CORNER! +%s", NumberFormatter.Format(reward)),
	})
	local displayName = player.DisplayName
	services.GameService:NotifyAll(function(lang)
		return {
			Type = "Info",
			Text = Locale.TFor(lang, "📀 %s hit the PERFECT CORNER!", displayName),
		}
	end, player)
end

-- TEST (Studio) : place le 1er logo pour qu'il touche un coin dans ~2 secondes
function DVDService:DebugCorner(player: Player): boolean
	local state = states[player]
	if not state or #state.Logos == 0 then
		return false
	end
	flushBounces(state)
	-- Test : on lève les sécurités anti-abus des jackpots
	state.LastResize, state.LastJackpot = -math.huge, -math.huge
	local logo = state.Logos[1]
	local params = logo.Params
	local rangeX, rangeY = DVDMath.Ranges(params)
	local speedX, speedY = math.abs(params.VX), math.abs(params.VY)
	local delay = math.min(2, rangeX * 0.9 / speedX, rangeY * 0.9 / speedY)
	setParams(logo, {
		X0 = rangeX - speedX * delay,
		Y0 = rangeY - speedY * delay,
		VX = speedX,
		VY = speedY,
		T0 = now(),
		W = params.W,
		H = params.H,
	})
	self:SendSetup(player)
	return true
end

function DVDService:Start()
	Net.Event("DVDResize").OnServerEvent:Connect(onResize)
	Net.Event("DVDClick").OnServerEvent:Connect(onClick)
	Net.Event("DVDCorner").OnServerEvent:Connect(onCorner)
end

return DVDService
