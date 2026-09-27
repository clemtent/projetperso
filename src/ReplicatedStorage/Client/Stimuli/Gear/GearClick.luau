--[[
	GearClick (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > GearClick

	v9.1 : les accessoires CLIQUABLES (touches du clavier mécanique, du
	clavier corail, souris gaming) cliquent pour de vrai, par le même chemin
	que le gros bouton "Click me" :
	  - ClientState.Click() (gain prédit, combo, envoi au serveur qui
	    compte le clic : quêtes, statistiques, limite de clics par seconde) ;
	  - le "+X" qui s'envole (même couleur / style que le gros bouton :
	    Effects.AmountStyle, Effects.Pop) près de l'objet cliqué ;
	  - ClientState.Clicked est déclenché par ClientState.Click() : les
	    autres accessoires s'animent comme pour un clic sur le bouton.
	GearClick.Source vaut l'Id de l'accessoire PENDANT ce clic (les
	écouteurs de ClientState.Clicked savent d'où vient le clic).

	Sons de touches (exception v9.1 demandée par le joueur) : uniquement les
	sons existants Config.ClickSounds "Keyboard1".."Keyboard5", choisis selon
	le niveau de l'amélioration, joués par SoundManager (réglage Son et
	volume des effets respectés).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local GearClick = {}

GearClick.Source = nil :: string?

local random = Random.new()

local function formatAmount(value: number): string
	if value >= 1e6 then
		return NumberFormatter.Format(value)
	elseif value < 10 and value % 1 ~= 0 then
		return NumberFormatter.Format(value)
	end
	return NumberFormatter.WithSpaces(value)
end

-- Un vrai clic depuis l'accessoire `source` ; `point` = position sur la toile
-- (pixels "design") où faire s'envoler le "+X". Renvoie le gain (nil = refusé :
-- trop rapide, état pas encore reçu...).
function GearClick.Click(source: string, point: Vector2?): number?
	GearClick.Source = source
	local ok, gain = pcall(ClientState.Click)
	GearClick.Source = nil
	if not ok then
		warn("[GearClick] " .. tostring(gain))
		return nil
	end
	if not gain then
		return nil
	end
	local layer = Effects.GetLayer()
	if layer and point then
		local data = ClientState.Data
		local base = tonumber(data and data.ClickValue) or gain
		local color, style = Effects.AmountStyle(gain, base, ClientState.DarkMode)
		local ratio = math.clamp(ClientState.GetComboMeter() / 100, 0, 1)
		local position = UDim2.fromOffset(point.X + random:NextNumber(-10, 10), point.Y - 4)
		Effects.Pop(layer, position, "+" .. formatAmount(gain), { Color = color, Size = 24 + ratio * 8, Style = style, Rise = 30 })
	end
	return gain
end

-- Son du clic choisi par le joueur (le même que le gros bouton : souris)
function GearClick.PlayClickSound()
	local ratio = math.clamp(ClientState.GetComboMeter() / 100, 0, 1)
	SoundManager.PlayClick(0.95 + ratio * 0.6 + random:NextNumber(0, 0.08))
end

-- Son de touche selon le niveau : 1-2 -> Keyboard1, 3-5 -> 2, 6-7 -> 3,
-- 8-10 -> 4, 11+ -> 5 (`shift` décale le palier, ex. clavier corail)
function GearClick.KeySoundId(level: number, shift: number?): string
	local tier = 1
	if level >= 11 then
		tier = 5
	elseif level >= 8 then
		tier = 4
	elseif level >= 6 then
		tier = 3
	elseif level >= 3 then
		tier = 2
	end
	tier = math.clamp(tier + (shift or 0), 1, 5)
	return "Keyboard" .. tostring(tier)
end

local lastKeySound = 0

-- Joue le son d'une touche (hauteur un peu variable ; `pitch` de base)
function GearClick.PlayKeySound(level: number, pitch: number?, shift: number?)
	local now = os.clock()
	if now - lastKeySound < 0.03 then
		return
	end
	lastKeySound = now
	local id = GearClick.KeySoundId(level, shift)
	local speed = (pitch or 1) * random:NextNumber(0.96, 1.04)
	local play = (SoundManager :: any).PlayKeySound
	if type(play) == "function" then
		play(id, speed)
	else
		SoundManager.PreviewClickSound(id)
	end
end

return GearClick
