--[[
	DVDService (ModuleScript)
	Emplacement : ServerScriptService > Services > DVDService

	Logo DVD rebondissant. Le SERVEUR choisit la trajectoire (position,
	vitesse, heure de départ) et l'envoie au client, qui ne fait que
	l'afficher. Comme la trajectoire est déterministe (voir DVDMath), le
	serveur peut recalculer lui-même si un coin a vraiment été touché :
	un tricheur ne peut pas inventer de jackpot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DVDMath = require(ReplicatedStorage.Shared.DVDMath)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local DVDService = {}

local services
local random = Random.new()

-- [Player] = { Params = DVDMath.Params, ClaimedCorners = { [k] = true }, LastClick = number }
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
	local speed = Config.DVD.Speed
	local signX = random:NextNumber() < 0.5 and -1 or 1
	local signY = random:NextNumber() < 0.5 and -1 or 1
	return {
		X0 = random:NextNumber(0, 1 - w),
		Y0 = random:NextNumber(0, 1 - h),
		VX = math.cos(angle) * speed * signX,
		VY = math.sin(angle) * speed * signY,
		T0 = now(),
		W = w,
		H = h,
	}
end

function DVDService:SendSetup(player: Player)
	local state = states[player]
	if state then
		Net.Event("DVDSetup"):FireClient(player, state.Params)
	end
end

function DVDService:PlayerReady(player: Player)
	-- Taille par défaut (corrigée dès que le client envoie la vraie taille)
	states[player] = {
		Params = randomParams(0.13, 0.12),
		ClaimedCorners = {},
		LastClick = 0,
	}
end

function DVDService:PlayerRemoving(player: Player)
	states[player] = nil
end

-- Le client indique la taille du logo à l'écran (en fraction de l'écran).
-- On garde la position et la direction actuelles pour que le logo ne saute pas.
local function onResize(player: Player, w: any, h: any)
	local state = states[player]
	if not state or not RateLimiter.Check(player, "DVDResize", 0.5) then
		return
	end
	if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h then
		return
	end
	w = math.clamp(w, 0.03, 0.5)
	h = math.clamp(h, 0.03, 0.5)

	local params = state.Params
	local t = now()
	local x, y = DVDMath.Position(params, t)
	local dirX, dirY = DVDMath.Directions(params, t)

	state.Params = {
		X0 = math.clamp(x, 0, 1 - w),
		Y0 = math.clamp(y, 0, 1 - h),
		VX = math.abs(params.VX) * dirX,
		VY = math.abs(params.VY) * dirY,
		T0 = t,
		W = w,
		H = h,
	}
	state.ClaimedCorners = {} -- nouvelle trajectoire = nouveaux numéros de rebond
	DVDService:SendSetup(player)
end

-- Clic sur le logo : petit bonus, avec un temps de recharge
local function onClick(player: Player)
	local state = states[player]
	local data = services.DataService:GetData(player)
	if not state or not data then
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
	services.QuestService:Progress(player, "DVDClicks", 1)
	services.GameService:Notify(player, {
		Type = "Bonus",
		Source = "DVD",
		Amount = reward,
	})
end

-- Le client signale un coin au rebond horizontal numéro k : on VÉRIFIE
local function onCorner(player: Player, k: any)
	local state = states[player]
	local data = services.DataService:GetData(player)
	if not state or not data or not RateLimiter.Check(player, "DVDCorner", 0.3) then
		return
	end
	if type(k) ~= "number" or k ~= math.floor(k) or math.abs(k) > 1e9 then
		return
	end
	if state.ClaimedCorners[k] then
		return -- déjà récompensé
	end

	local params = state.Params
	local bounceTime = DVDMath.BounceTimeX(params, k)
	local t = now()
	-- Le rebond doit avoir eu lieu récemment (et après le début de la trajectoire)
	if bounceTime < params.T0 or bounceTime > t + 0.5 or bounceTime < t - 5 then
		return
	end
	if not DVDMath.IsCornerAtBounceX(params, k, Config.DVD.CornerTolerance) then
		return -- pas un vrai coin : tentative de triche ou erreur d'arrondi
	end

	state.ClaimedCorners[k] = true
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
		Text = "📀 COIN PARFAIT ! +" .. NumberFormatter.Format(reward),
	})
	services.GameService:NotifyAll({
		Type = "Info",
		Text = "📀 " .. player.DisplayName .. " a touché le COIN PARFAIT !",
	}, player)
end

-- TEST (Studio) : place le logo pour qu'il touche un coin dans 2 secondes
function DVDService:DebugCorner(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local params = state.Params
	local rangeX, rangeY = DVDMath.Ranges(params)
	local speedX, speedY = math.abs(params.VX), math.abs(params.VY)
	local delay = math.min(2, rangeX * 0.9 / speedX, rangeY * 0.9 / speedY)
	state.Params = {
		X0 = rangeX - speedX * delay,
		Y0 = rangeY - speedY * delay,
		VX = speedX,
		VY = speedY,
		T0 = now(),
		W = params.W,
		H = params.H,
	}
	state.ClaimedCorners = {}
	self:SendSetup(player)
end

function DVDService:Start()
	Net.Event("DVDResize").OnServerEvent:Connect(onResize)
	Net.Event("DVDClick").OnServerEvent:Connect(onClick)
	Net.Event("DVDCorner").OnServerEvent:Connect(onCorner)
end

return DVDService
