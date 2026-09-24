--[[
	InteractService (ModuleScript)
	Emplacement : ServerScriptService > Services > InteractService

	Interactions "satisfaisantes" avec les éléments de l'écran
	(RemoteEvent Interact, réglages dans Config.Interactions) :
	  - "Bubble", "Butter" : papier bulle / beurre croustillant. Seau de
	                 jetons (MaxPerSecond), gain = gain par clic x ClickFraction,
	                 SANS notification (le client affiche lui-même le "+X") ;
	  - "Follow"   : bouton "Suivre" du live (OneTime) : UNE fois par partie
	                 (data.LiveFollowed, remis à false à la détox), gain = X
	                 secondes de production, notification "Bonus" ; les dons
	                 du live (spawner "Donation") ne viennent qu'après ;
	  - "Spin", "Headline", "Press" : temps de recharge, gain = X secondes de
	                 production, notification "Bonus".
	Chaque interaction exige la Feature correspondante.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)

local InteractService = {}

local services
local COOLDOWN_TOLERANCE = 0.2 -- marge (s) pour la latence réseau

-- [Player] = { Tokens = { [kind] = n }, LastRefill = { [kind] = clock }, LastUse = { [kind] = clock } }
local states = {}

-- Interactions "une seule fois par partie" : [kind] = clé booléenne dans data
local ONE_TIME_FLAGS = {
	Follow = "LiveFollowed",
}

function InteractService:Init(allServices)
	services = allServices
end

-- Seau de jetons : true si l'action est autorisée
local function takeToken(state, kind: string, perSecond: number): boolean
	local clock = os.clock()
	local tokens = state.Tokens[kind] or perSecond
	local last = state.LastRefill[kind] or clock
	tokens = math.min(perSecond, tokens + (clock - last) * perSecond)
	state.LastRefill[kind] = clock
	if tokens < 1 then
		state.Tokens[kind] = tokens
		return false
	end
	state.Tokens[kind] = tokens - 1
	return true
end

local function onInteract(player: Player, kind: any, _arg: any)
	local state = states[player]
	if not state or type(kind) ~= "string" then
		return
	end
	local settings = Config.Interactions[kind]
	if not settings then
		return
	end
	local data = services.DataService:GetData(player)
	if not data or not Formulas.HasFeature(data, settings.Feature) then
		return
	end

	local stats = services.GameService:GetStats(player)

	if settings.MaxPerSecond then
		-- Papier bulle : beaucoup de petits gains, pas de notification
		if not takeToken(state, kind, settings.MaxPerSecond) then
			return
		end
		if settings.Stat then
			data.Stats[settings.Stat] = (data.Stats[settings.Stat] or 0) + 1
		end
		services.GameService:AddDopamine(player, stats.ClickValue * (settings.ClickFraction or 1), true)
		if kind == "Bubble" then
			services.QuestService:Progress(player, "Bubbles", 1)
		end
		return
	end

	-- Une seule fois par partie (ex. s'abonner au live)
	if settings.OneTime then
		local flag = ONE_TIME_FLAGS[kind]
		if not flag or data[flag] == true then
			return -- déjà fait (ou interaction sans drapeau connu : refusée)
		end
		data[flag] = true
		local reward = Formulas.ScaledReward(stats, settings.RewardSeconds or 1, settings.MinReward or 1)
		if settings.Stat then
			data.Stats[settings.Stat] = (data.Stats[settings.Stat] or 0) + 1
		end
		services.GameService:AddDopamine(player, reward, true)
		services.GameService:SendState(player) -- le client voit tout de suite "✔ Abonné"
		services.GameService:Notify(player, {
			Type = "Bonus",
			Source = kind,
			Amount = reward,
		})
		return
	end

	-- Autres interactions : temps de recharge + notification
	local clock = os.clock()
	local last = state.LastUse[kind]
	if last and clock - last < (settings.Cooldown or 1) - COOLDOWN_TOLERANCE then
		return
	end
	state.LastUse[kind] = clock

	local reward = Formulas.ScaledReward(stats, settings.RewardSeconds or 1, settings.MinReward or 1)
	if settings.Stat then
		data.Stats[settings.Stat] = (data.Stats[settings.Stat] or 0) + 1
	end
	services.GameService:AddDopamine(player, reward, true)
	services.GameService:Notify(player, {
		Type = "Bonus",
		Source = kind,
		Amount = reward,
	})
end

function InteractService:PlayerReady(player: Player)
	states[player] = { Tokens = {}, LastRefill = {}, LastUse = {} }
end

function InteractService:PlayerRemoving(player: Player)
	states[player] = nil
end

function InteractService:Start()
	Net.Event("Interact").OnServerEvent:Connect(onInteract)
end

return InteractService
