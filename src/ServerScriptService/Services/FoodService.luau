--[[
	FoodService (ModuleScript)
	Emplacement : ServerScriptService > Services > FoodService

	🍦 Nourriture de Dopamine Town (v9.8, FAIR98) : glaces, barbe à papa,
	churros, popcorn, crêpes, pizza, tacos, milkshakes, hot-dogs, pommes
	d'amour, beignets (Config.Food).
	  - Achat à un STAND (place, fête foraine, coin gourmand) : les stands
	    s'enregistrent (RegisterStall) avec leur pièce et leurs aliments ;
	    le serveur vérifie l'aliment, le stand, la DISTANCE, le prix
	    (FoodRules.Price : secondes de la production du joueur), la limite de
	    fréquence, et qu'on n'a pas déjà quelque chose en main.
	  - L'aliment devient un Tool tenu en main (FoodModels : pièce "Handle"
	    + bouchées "Bite1…") ; chaque clic (Tool.Activated) ou le bouton
	    "🍴 Croquer" (remote "Food" : "bite") = une bouchée : la bouchée
	    disparaît, attributs "BitesLeft" / "BiteAt" (les clients animent le
	    bras et les miettes : FairFx).
	  - La DERNIÈRE bouchée donne le boost (FoodRules.Stack : un seul boost
	    nourriture, cumul converti, plafonds Config.Food). Un aliment pas
	    fini (on quitte la ville / le jeu) donne quand même son boost.
	  - Le boost est appliqué PAR LE SERVEUR dans l'économie :
	    GameService:GetStats multiplie par FoodService:GetMultiplier(player)
	    (clics, production, rebonds…). Pas de boost hors-ligne.
	Données : data.Food = { Multiplier = n, EndsAt = os.time() de fin,
	Food = id du dernier aliment } (créé ici si absent, réparé au chargement).
	État client (GetClientState) : FoodBoost = { Multiplier, Remaining, Food }.
	RemoteFunction "Food" (action, a, b) -> (succès, message, manquant?) :
	  "buy" foodId, stallId | "bite"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local FoodRules = require(ReplicatedStorage.Shared.FoodRules)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)

local FoodService = {}

FoodService.TOOL_NAME = "DopamineFood"

local services: any = nil

type Stall = { Part: BasePart, Foods: { [string]: boolean } }
local stalls: { [string]: Stall } = {}

type Holding = { Tool: Tool, Food: any, Done: number, Finished: boolean, LastBite: number }
local holdings: { [Player]: Holding } = {}

local function isValidNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function T(player: Player, text: string, ...): string
	if services and services.GameService then
		return services.GameService:T(player, text, ...)
	end
	return string.format(text, ...)
end

local function now(): number
	return os.time()
end

----------------------------------------------------------------------
-- Stands
----------------------------------------------------------------------

-- Appelé par TownFair / TownPlaza à la construction de la ville
function FoodService.RegisterStall(id: string, part: BasePart, foods: { string })
	local set = {}
	for _, foodId in ipairs(foods) do
		if Config.FoodById[foodId] then
			set[foodId] = true
		end
	end
	stalls[id] = { Part = part, Foods = set }
end

function FoodService.ClearStalls()
	table.clear(stalls)
end

----------------------------------------------------------------------
-- Boost
----------------------------------------------------------------------

local function sanitize(data)
	local food = data.Food
	if type(food) ~= "table" then
		data.Food = { Multiplier = 1, EndsAt = 0, Food = "" }
		return
	end
	local m = food.Multiplier
	if not isValidNumber(m) or m < 1 or m > Config.Food.MaxMultiplier or not isValidNumber(food.EndsAt)
		or food.EndsAt <= now() or food.EndsAt > now() + Config.Food.MaxSeconds + 5 then
		data.Food = { Multiplier = 1, EndsAt = 0, Food = "" }
	elseif type(food.Food) ~= "string" then
		food.Food = ""
	end
end

-- (multiplicateur, secondes restantes) du boost nourriture ; (1, 0) si aucun
function FoodService:GetBoost(data): (number, number)
	local food = data and data.Food
	if type(food) ~= "table" or not isValidNumber(food.Multiplier) or not isValidNumber(food.EndsAt) then
		return 1, 0
	end
	local remaining = food.EndsAt - now()
	if remaining <= 0 or food.Multiplier <= 1 then
		return 1, 0
	end
	return math.min(food.Multiplier, Config.Food.MaxMultiplier), remaining
end

-- Multiplicateur appliqué à l'économie (GameService:GetStats)
function FoodService:GetMultiplier(player: Player): number
	local data = services and services.DataService:GetData(player)
	if not data then
		return 1
	end
	local m = self:GetBoost(data)
	return m
end

-- Champ d'état envoyé au client (GameService:BuildState)
function FoodService:GetClientState(_player: Player, data)
	local m, remaining = self:GetBoost(data)
	local last = type(data.Food) == "table" and data.Food.Food or ""
	return {
		FoodBoost = { Multiplier = m, Remaining = math.max(0, math.floor(remaining)), Food = if remaining > 0 then last else "" },
	}
end

local expiryToken: { [Player]: number } = {}

local function applyBoost(player: Player, food: any)
	local data = services.DataService:GetData(player)
	if not data then
		return
	end
	sanitize(data)
	local m, remaining = FoodService:GetBoost(data)
	local newM, newRemaining = FoodRules.Stack(m, remaining, food)
	if newM <= 1 or newRemaining <= 0 then
		return
	end
	data.Food = { Multiplier = newM, EndsAt = now() + math.floor(newRemaining + 0.5), Food = food.Id }
	services.GameService:MarkDirty(player)
	-- fin du boost : un état complet (gains / badge) au bon moment
	local token = (expiryToken[player] or 0) + 1
	expiryToken[player] = token
	task.delay(newRemaining + 1, function()
		if expiryToken[player] == token and player.Parent then
			services.GameService:MarkDirty(player)
		end
	end)
end

----------------------------------------------------------------------
-- Aliment en main (Tool)
----------------------------------------------------------------------

local function characterOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function finish(player: Player, holding: Holding)
	if holding.Finished then
		return
	end
	holding.Finished = true
	if holdings[player] == holding then
		holdings[player] = nil
	end
	applyBoost(player, holding.Food)
end

local function makeTool(food: any): Tool?
	local base = CFrame.new(0, 200, 0)
	local model = FoodModels.Build(food.Id, base, FoodModels.HELD_SCALE)
	if not model then
		return nil
	end
	local handle = model.PrimaryPart
	if not handle then
		model:Destroy()
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = FoodService.TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = food.Icon .. " " .. food.Name
	-- (v11, ITEMS11 : capture 31) Tool.Grip est exprimé dans le repère de la
	-- pièce Handle : v10 oubliait que le Handle du cornet (cylindre) est
	-- tourné de 90° -> la glace sortait du poing à l'horizontale, sur le
	-- côté, dans toutes les poses. Grip = HandleLocal⁻¹ * GRIP : le +Y du
	-- MODÈLE = le +Y de la prise (= l'avant du bras : debout quand le bras
	-- est tendu). La pose du bras (tenue, geste) est faite par chaque client
	-- (Client/World/FairEat + FoodHold) : debout quelle que soit l'animation.
	tool.Grip = FoodModels.ToolGrip(model, base)
	tool:SetAttribute("FoodId", food.Id)
	tool:SetAttribute("BitesLeft", food.Bites)
	tool:SetAttribute("BiteAt", 0)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			p.Parent = tool
			if p ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model:Destroy()
	for _, p in ipairs(tool:GetChildren()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
		end
	end
	handle.Name = "Handle"
	return tool
end

local function bite(player: Player): (boolean, string?)
	local holding = holdings[player]
	if not holding or holding.Finished then
		return false, T(player, "You're not holding any food")
	end
	local t = os.clock()
	if t - holding.LastBite < Config.Food.BiteCooldown then
		return false, nil
	end
	holding.LastBite = t
	local tool = holding.Tool
	local character = player.Character
	if not tool.Parent then
		finish(player, holding)
		return true, nil
	end
	-- rangé (sac à dos caché) : on le remet en main
	if character and tool.Parent ~= character then
		tool.Parent = character
	end
	holding.Done += 1
	local food = holding.Food
	local serverTime = workspace:GetServerTimeNow()
	tool:SetAttribute("BitesLeft", math.max(0, food.Bites - holding.Done))
	tool:SetAttribute("BiteAt", serverTime)
	for _, p in ipairs(tool:GetChildren()) do
		if p.Name == "Bite" .. holding.Done then
			p:Destroy()
		end
	end
	if holding.Done >= food.Bites then
		finish(player, holding)
		-- (laisse le temps de voir la dernière bouchée)
		task.delay(0.45, function()
			if tool.Parent then
				tool:Destroy()
			end
		end)
	end
	return true, nil
end

local function give(player: Player, food: any): boolean
	local character, humanoid = characterOf(player)
	if not character or not humanoid then
		return false
	end
	local tool = makeTool(food)
	if not tool then
		return false
	end
	local holding: Holding = { Tool = tool, Food = food, Done = 0, Finished = false, LastBite = os.clock() - Config.Food.BiteCooldown - 0.05 }
	holdings[player] = holding
	tool.Activated:Connect(function()
		pcall(bite, player)
	end)
	-- détruit / parti avant la fin (sortie de la ville, personnage retiré) :
	-- le boost payé est quand même donné
	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil and not holding.Finished then
			finish(player, holding)
		end
	end)
	tool.Parent = character
	pcall(function()
		humanoid:EquipTool(tool)
	end)
	return true
end

local function buy(player: Player, foodId: any, stallId: any): (boolean, string, number?)
	local data = services.DataService:GetData(player)
	if not data then
		return false, T(player, "Invalid request")
	end
	local food = type(foodId) == "string" and Config.FoodById[foodId] or nil
	local stall = type(stallId) == "string" and stalls[stallId] or nil
	if not food or not stall or not stall.Foods[food.Id] or not stall.Part.Parent then
		return false, T(player, "Invalid request")
	end
	local _, _, root = characterOf(player)
	if not root then
		return false, T(player, "Walk to a food stall in Dopamine Town")
	end
	if (root.Position - stall.Part.Position).Magnitude > Config.Food.BuyDistance then
		return false, T(player, "Walk closer to the stall")
	end
	local holding = holdings[player]
	if holding and not holding.Finished and holding.Tool.Parent then
		return false, T(player, "Finish what you're eating first! 🍴")
	end
	local stats = services.GameService:GetStats(player)
	local currentFood = FoodService:GetBoost(data)
	local price = FoodRules.Price(food, stats.PerSecond, stats.ClickValue, currentFood)
	if not isValidNumber(price) or price < 0 then
		return false, T(player, "Invalid request")
	end
	if not isValidNumber(data.Dopamine) or data.Dopamine < price then
		local missing = math.max(0, price - (isValidNumber(data.Dopamine) and data.Dopamine or 0))
		return false, T(player, "Not enough %s", Config.Game.CurrencyName), missing
	end
	data.Dopamine -= price
	if not give(player, food) then
		data.Dopamine += price
		return false, T(player, "Invalid request")
	end
	services.GameService:MarkDirty(player)
	return true, T(player, "%s %s! Click to take a bite (%s)", food.Icon, T(player, food.Name), NumberFormatter.Format(price))
end

-- Prix actuel (tests / debug)
function FoodService:GetPrice(player: Player, foodId: string): number?
	local data = services.DataService:GetData(player)
	local food = Config.FoodById[foodId]
	if not data or not food then
		return nil
	end
	local stats = services.GameService:GetStats(player)
	return FoodRules.Price(food, stats.PerSecond, stats.ClickValue, (self:GetBoost(data)))
end

function FoodService:IsHolding(player: Player): boolean
	local holding = holdings[player]
	return holding ~= nil and not holding.Finished
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function FoodService:Init(allServices)
	services = allServices
end

function FoodService:PlayerReady(_player: Player, data)
	sanitize(data)
end

function FoodService:PlayerRemoving(player: Player)
	local holding = holdings[player]
	if holding and not holding.Finished then
		finish(player, holding)
	end
	holdings[player] = nil
	expiryToken[player] = nil
end

function FoodService:Start()
	Net.Function("Food").OnServerInvoke = function(player: Player, action: any, a: any, b: any)
		if not services.DataService:GetData(player) then
			return false, T(player, "Invalid request")
		end
		if action == "buy" then
			if not RateLimiter.Check(player, "FoodBuy", Config.Food.BuyCooldown) then
				return false, T(player, "Slow down a little!")
			end
			local ok, success, message, missing = pcall(buy, player, a, b)
			if not ok then
				warn("[FoodService] achat : " .. tostring(success))
				return false, T(player, "Invalid request")
			end
			return success, message, missing
		elseif action == "bite" then
			local ok, success, message = pcall(bite, player)
			if not ok then
				warn("[FoodService] bouchée : " .. tostring(success))
				return false, nil
			end
			return success, message
		end
		return false, T(player, "Invalid request")
	end
end

return FoodService
