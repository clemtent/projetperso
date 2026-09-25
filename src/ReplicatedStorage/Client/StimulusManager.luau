--[[
	StimulusManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > StimulusManager

	Fait apparaître / disparaître les "stimuli" (Client > Stimuli > <Feature>)
	selon les Features débloquées par le joueur :
	  - Feature possédée + module présent + pas encore lancé : crée le cadre
	    (selon Module.Slot, voir Slots), construit le "ctx", lance
	    Module.Start(ctx) dans son propre thread (protégé par pcall) et fait
	    "pop" le cadre ;
	  - Feature perdue (après l'océan) : ctx mort, connexions coupées,
	    Module.Stop(ctx) (si présent), cadre détruit ;
	  - Notify "Detox" : joue la cinématique Stimuli > Ocean (Ocean.Play(ctx)) ;
	  - Notify "Bonus" : transmis aux abonnés ctx.OnBonus(Source, ...).

	Contrat d'un module stimulus :
		local Module = {}
		Module.Slot = "L3"                -- ou "Overlay" / "Background"
		function Module.Start(ctx) end    -- construit l'UI dans ctx.Container
		function Module.Stop(ctx) end     -- optionnel
		return Module

	Champs du ctx : Feature, Container, Overlay, State, Config, Formulas,
	Format, Net, Theme, UIUtil, Effects, Sound, DVDMath, Notify, FloatText,
	GetLevel, HasFeature, ClaimSpawn, Interact, OnSpawn, OnBonus, Connect,
	OnRender, IsAlive, SetDarkMode (+ bonus : Slot, Interface, Random,
	EffectsEnabled, GetSlotScale, GetSlotSize, et pour l'océan : Payload, Rebirths, Multiplier).
	v5 : sur téléphone / tablette, le cadre d'un slot porte un UIScale
	"SlotScale" (voir Slots) ; l'animation "pop" l'utilise directement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local NumberFormatter = require(Shared.NumberFormatter)
local DVDMath = require(Shared.DVDMath)

local Client = script.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Slots = require(Client.Slots)
local Notifications = require(Client.Components.Notifications)

local StimulusManager = {}

type Record = {
	Feature: string,
	Module: any,
	Ctx: any,
	Container: Frame,
	Slot: string,
	Alive: boolean,
	Dark: boolean,
	Connections: { any },
}

local modules: { [string]: any } = {} -- [nom] = module chargé, ou false si erreur
local running: { [string]: Record } = {}
local bonusSubscribers: { [string]: { { Record: Record, Callback: (any) -> () } } } = {}
local oceanPlaying = false
local initialized = false

----------------------------------------------------------------------
-- Chargement des modules
----------------------------------------------------------------------

local function getStimuliFolder(): Instance?
	return Client:FindFirstChild("Stimuli")
end

local function loadModule(name: string): any?
	local cached = modules[name]
	if cached ~= nil then
		return cached or nil
	end
	local folder = getStimuliFolder()
	local moduleScript = folder and folder:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil -- pas (encore) de module : on ignore silencieusement
	end
	local ok, result = pcall(require, moduleScript)
	if not ok or type(result) ~= "table" then
		warn("[StimulusManager] Impossible de charger Stimuli." .. name .. " : " .. tostring(result))
		modules[name] = false
		return nil
	end
	modules[name] = result
	return result
end

----------------------------------------------------------------------
-- Mode sombre : la source "Stimuli" est active si au moins un stimulus
-- vivant le demande (le thème équipé a sa propre source, voir ClientState)
----------------------------------------------------------------------

local function refreshDarkMode()
	local dark = false
	for _, record in pairs(running) do
		if record.Dark then
			dark = true
			break
		end
	end
	-- Source séparée du thème : un thème sombre reste sombre quand le néon s'arrête
	ClientState.SetDarkSource("Stimuli", dark)
end

----------------------------------------------------------------------
-- Construction du ctx
----------------------------------------------------------------------

local DEAD_CONNECTION = {
	Connected = false,
	Disconnect = function() end,
}

local function newContext(feature: string, container: Frame, slot: string): (any, Record)
	local record: Record = {
		Feature = feature,
		Module = nil,
		Ctx = nil,
		Container = container,
		Slot = slot,
		Alive = true,
		Dark = false,
		Connections = {},
	}

	local ctx = {}
	record.Ctx = ctx

	ctx.Feature = feature
	ctx.Slot = slot
	ctx.Container = container
	ctx.Overlay = Interface.Layers.Overlay
	ctx.Interface = Interface
	ctx.State = ClientState
	ctx.Config = Config
	ctx.Formulas = Formulas
	ctx.Format = NumberFormatter
	ctx.Net = Net
	ctx.Theme = Theme
	ctx.UIUtil = UIUtil
	ctx.Effects = Effects
	ctx.Sound = SoundManager
	ctx.DVDMath = DVDMath
	ctx.Random = Random.new()

	function ctx.IsAlive(): boolean
		return record.Alive
	end

	-- Échelle du slot (1 sur PC, plus petite sur téléphone / tablette).
	-- Le cadre garde sa taille "design" : rien à faire pour s'y adapter.
	function ctx.GetSlotScale(): number
		return Slots.GetScale(slot)
	end

	-- Taille "design" de la zone du slot (le cadre, lui, a une marge de
	-- découpe en plus, compensée par un UIPadding : voir Slots.ClipMargin)
	function ctx.GetSlotSize(): Vector2
		local size = Slots.GetDesignSize(slot)
		if size.X <= 0 or size.Y <= 0 then
			return container.AbsoluteSize
		end
		return size
	end

	-- Petit bandeau en bas de l'écran
	function ctx.Notify(text: string, color: Color3?)
		Notifications.Toast(text, color)
	end

	-- Texte "+X" flottant
	function ctx.FloatText(parent: GuiObject, position: UDim2, text: string, color: Color3?, size: number?)
		Effects.FloatingText(parent, position, text, color, size)
	end

	function ctx.GetLevel(upgradeId: string): number
		return ClientState.GetLevel(upgradeId)
	end

	function ctx.HasFeature(name: string): boolean
		return ClientState.HasFeature(name)
	end

	-- Vrai si le joueur n'a pas coupé les effets (particules)
	function ctx.EffectsEnabled(): boolean
		local data = ClientState.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	function ctx.ClaimSpawn(id: string)
		if type(id) ~= "string" then
			return
		end
		Net.Event("SpawnClick"):FireServer(id)
	end

	function ctx.Interact(kind: string, arg: any?)
		Net.Event("Interact"):FireServer(kind, arg)
	end

	-- Connexion suivie (fonctionne avec RBXScriptSignal ET Shared/Signal)
	function ctx.Connect(signal: any, callback: (...any) -> ()): any
		if not record.Alive or signal == nil then
			return DEAD_CONNECTION
		end
		local connection = signal:Connect(function(...)
			if record.Alive then
				callback(...)
			end
		end)
		table.insert(record.Connections, connection)
		return connection
	end

	-- Appelé à chaque image (RenderStepped) ; une erreur coupe la connexion (un seul avertissement)
	function ctx.OnRender(callback: (dt: number) -> ()): any
		local connection
		connection = ctx.Connect(RunService.RenderStepped, function(dt: number)
			local ok, err = pcall(callback, dt)
			if not ok then
				warn("[Stimuli." .. feature .. "] Erreur dans OnRender (boucle arrêtée) : " .. tostring(err))
				if connection then
					connection:Disconnect()
				end
			end
		end)
		return connection
	end

	-- Objets qui apparaissent (étoile, éclair, notif, mail) d'un type donné
	function ctx.OnSpawn(kind: string, callback: (info: any) -> ()): any
		return ctx.Connect(ClientState.SpawnReceived, function(info)
			if info.Kind == kind then
				callback(info)
			end
		end)
	end

	-- Récompenses "Bonus" envoyées par le serveur pour une source donnée
	function ctx.OnBonus(source: string, callback: (payload: any) -> ()): any
		if not record.Alive then
			return DEAD_CONNECTION
		end
		local list = bonusSubscribers[source]
		if not list then
			list = {}
			bonusSubscribers[source] = list
		end
		local entry = { Record = record, Callback = callback }
		table.insert(list, entry)
		local connection = {
			Connected = true,
			Disconnect = function(self)
				local current = bonusSubscribers[source]
				if current then
					local index = table.find(current, entry)
					if index then
						table.remove(current, index)
					end
				end
				if type(self) == "table" then
					self.Connected = false
				end
			end,
		}
		table.insert(record.Connections, connection)
		return connection
	end

	-- Mode sombre (utilisé par le mode néon). Toujours accepté (même dans Stop).
	function ctx.SetDarkMode(enabled: boolean)
		record.Dark = enabled == true and record.Alive
		refreshDarkMode()
	end

	return ctx, record
end

-- Tue un ctx : plus vivant, toutes ses connexions coupées
local function killRecord(record: Record)
	record.Alive = false
	for _, connection in ipairs(record.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(record.Connections)
end

----------------------------------------------------------------------
-- Démarrage / arrêt d'un stimulus
----------------------------------------------------------------------

local function startFeature(feature: string, module: any)
	local slot = module.Slot
	if type(slot) ~= "string" or not Slots.IsValid(slot) then
		warn("[StimulusManager] Stimuli." .. feature .. " : Slot invalide (" .. tostring(slot) .. "), Overlay utilisé")
		slot = "Overlay"
	end
	local layer = Interface.Layers[Slots.GetLayerName(slot)]
	if not layer then
		return
	end

	local container = Slots.Create(slot, nil)
	container.Name = feature
	local upgradeId = Config.FeatureToUpgrade[feature]
	local upgrade = upgradeId and Config.UpgradesById[upgradeId]
	container.ZIndex = upgrade and upgrade.Order or 1 -- ordre d'empilement stable
	local fullCanvas = slot == "Overlay" or slot == "Background"
	-- "Pop" : on anime l'UIScale du slot (SlotScale, échelle du slot sur
	-- téléphone) ou, à défaut, un UIScale temporaire (un seul UIScale par cadre)
	local slotScale = container:FindFirstChild("SlotScale") :: UIScale?
	local popScale: UIScale? = nil
	local targetScale = 1
	if not fullCanvas then
		if slotScale then
			popScale = slotScale
			targetScale = Slots.GetScale(slot)
			container:SetAttribute("SlotAnimating", true)
			slotScale.Scale = 0.3 * targetScale
		else
			popScale = UIUtil.Create("UIScale", { Name = "PopScale", Scale = 0.3, Parent = container })
		end
	end
	container.Parent = layer

	local ctx, record = newContext(feature, container, slot)
	record.Module = module
	running[feature] = record

	task.spawn(function()
		local ok, err = pcall(module.Start, ctx)
		if not ok then
			warn("[StimulusManager] Erreur dans Stimuli." .. feature .. ".Start : " .. tostring(err))
		end
	end)

	-- Apparition "pop"
	local scale = popScale
	if scale then
		UIUtil.Tween(scale, 0.45, { Scale = targetScale }, Enum.EasingStyle.Back)
		task.delay(0.5, function()
			if scale == slotScale then
				-- Fin de l'animation : échelle actuelle du slot (l'écran a pu changer)
				container:SetAttribute("SlotAnimating", nil)
				if scale.Parent and record.Alive then
					scale.Scale = Slots.GetScale(slot)
				end
			elseif scale.Parent then
				scale:Destroy()
			end
		end)
	end
end

local function stopFeature(feature: string)
	local record = running[feature]
	if not record then
		return
	end
	running[feature] = nil
	killRecord(record)

	local module = record.Module
	if module and type(module.Stop) == "function" then
		local ok, err = pcall(module.Stop, record.Ctx)
		if not ok then
			warn("[StimulusManager] Erreur dans Stimuli." .. feature .. ".Stop : " .. tostring(err))
		end
	end
	record.Dark = false
	refreshDarkMode()

	-- Disparition (petit rétrécissement pour les slots, immédiate sinon)
	local container = record.Container
	if record.Slot == "Overlay" or record.Slot == "Background" then
		container:Destroy()
	else
		local scale = (container:FindFirstChild("SlotScale") or container:FindFirstChild("PopScale")) :: UIScale?
		if not scale then
			scale = UIUtil.Create("UIScale", { Name = "PopScale", Parent = container })
		end
		container:SetAttribute("SlotAnimating", true)
		UIUtil.Tween(scale :: UIScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.3, function()
			container:Destroy()
		end)
	end
end

-- Compare les Features possédées avec les stimuli lancés
local function applyFeatures()
	if not ClientState.Data then
		return
	end
	-- Arrêt de ce qui n'est plus possédé
	local toStop = {}
	for feature in pairs(running) do
		if not ClientState.HasFeature(feature) then
			table.insert(toStop, feature)
		end
	end
	for _, feature in ipairs(toStop) do
		stopFeature(feature)
	end
	-- Démarrage dans l'ordre des améliorations (empilement stable)
	for _, upgrade in ipairs(Config.Upgrades) do
		local feature = upgrade.Feature
		if feature and not running[feature] and ClientState.HasFeature(feature) then
			local module = loadModule(feature)
			if module and type(module.Start) == "function" then
				startFeature(feature, module)
			end
		end
	end
end

----------------------------------------------------------------------
-- Cinématique de l'océan
----------------------------------------------------------------------

local function fallbackOcean(container: Frame, payload)
	-- Version minimale si Stimuli > Ocean n'existe pas
	local sea = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 140, 200),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = container,
	})
	UIUtil.Gradient(sea, ColorSequence.new(Color3.fromRGB(170, 225, 255), Color3.fromRGB(0, 90, 160)), 90)
	local label = UIUtil.Label({
		Text = Locale.T("Breathe..."),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		Size = UDim2.new(0.8, 0, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		ZIndex = 3,
		MaxTextSize = 64,
		Parent = sea,
	})
	SoundManager.Play("Detox", 1)
	UIUtil.Tween(sea, 1, { BackgroundTransparency = 0 })
	task.wait(1)
	UIUtil.Tween(label, 0.8, { TextTransparency = 0 })
	task.wait(2)
	label.Text = Locale.T("Rebirth %s", NumberFormatter.Multiplier(tonumber(payload.Multiplier) or 1))
	task.wait(1.5)
	UIUtil.Tween(label, 0.8, { TextTransparency = 1 })
	UIUtil.Tween(sea, 1, { BackgroundTransparency = 1 })
	task.wait(1)
end

local function playOcean(payload)
	if oceanPlaying then
		return
	end
	local layer = Interface.Layers.Cinematic
	if not layer then
		return
	end
	oceanPlaying = true

	local container = UIUtil.Create("Frame", {
		Name = "Ocean",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = true,
		Parent = layer,
	})
	-- Bloque les clics pendant la cinématique
	UIUtil.Create("TextButton", {
		Name = "InputBlocker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 0,
		Parent = container,
	})

	local ctx, record = newContext("Ocean", container, "Cinematic")
	ctx.Payload = payload
	ctx.Rebirths = tonumber(payload.Rebirths) or 0
	ctx.Multiplier = tonumber(payload.Multiplier) or 1
	local module = loadModule("Ocean")
	record.Module = module

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		oceanPlaying = false
		killRecord(record)
		container:Destroy()
	end

	task.spawn(function()
		local ok, err
		if module and type(module.Play) == "function" then
			ok, err = pcall(module.Play, ctx)
		else
			ok, err = pcall(fallbackOcean, container, payload)
		end
		if not ok then
			warn("[StimulusManager] Erreur dans la cinématique de l'océan : " .. tostring(err))
		end
		finish()
	end)
	task.delay(10, finish)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Traitement des notifications qui concernent les stimuli (Bonus, Detox)
function StimulusManager.HandleNotify(payload)
	local kind = payload.Type
	if kind == "Bonus" then
		SoundManager.Play("Bonus", 1.2 + math.random() * 0.2)
		local list = payload.Source and bonusSubscribers[payload.Source]
		local delivered = false
		if list then
			for _, entry in ipairs(table.clone(list)) do
				if entry.Record.Alive then
					delivered = true
					task.spawn(function()
						local ok, err = pcall(entry.Callback, payload)
						if not ok then
							warn("[Stimuli." .. entry.Record.Feature .. "] Erreur dans OnBonus : " .. tostring(err))
						end
					end)
				end
			end
		end
		-- Personne n'écoute : petit texte au centre (ou toast du serveur)
		if not delivered then
			local amount = tonumber(payload.Amount)
			local layer = Effects.GetLayer()
			if amount and layer then
				Effects.FloatingText(layer, UDim2.new(0.5, 0, 0, 200), "+" .. NumberFormatter.Format(amount), Theme.Colors.Gold, 40)
			elseif payload.Text then
				Notifications.Toast(payload.Text, Theme.Colors.Gold)
			end
		end
	elseif kind == "Detox" then
		playOcean(payload)
	end
end

-- Liste des stimuli lancés (debug)
function StimulusManager.GetRunning(): { string }
	local list = {}
	for feature in pairs(running) do
		table.insert(list, feature)
	end
	table.sort(list)
	return list
end

-- Relance l'évaluation (ex. après ajout d'un module)
function StimulusManager.Refresh()
	applyFeatures()
end

function StimulusManager.Init()
	if initialized then
		return
	end
	initialized = true

	-- Échelle / position des slots selon l'appareil (téléphone, tablette, PC)
	Slots.Bind(Interface)

	ClientState.FeaturesChanged:Connect(applyFeatures)

	-- Le dossier Stimuli (ou certains modules) peut arriver après nous
	local function watchFolder(folder: Instance)
		folder.ChildAdded:Connect(function()
			task.defer(applyFeatures)
		end)
	end
	local folder = getStimuliFolder()
	if folder then
		watchFolder(folder)
	else
		local connection
		connection = Client.ChildAdded:Connect(function(child)
			if child.Name == "Stimuli" then
				connection:Disconnect()
				watchFolder(child)
				task.defer(applyFeatures)
			end
		end)
	end

	applyFeatures()
end

return StimulusManager
