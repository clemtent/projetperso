--[[
	EmojiRain (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > EmojiRain

	Une pluie légère et continue d'emojis qui tombent en tournoyant,
	balancés par un petit vent. Discrète (semi-transparente) et non
	cliquable : on ne bloque jamais les boutons en dessous.
	Les étiquettes sont recyclées (25 maximum, 10 si "Effets" est coupé).
]]

local EmojiRain = {}
EmojiRain.Slot = "Overlay"

local MAX_DROPS = 25
local MAX_DROPS_LOW = 10 -- réglage "Effets" désactivé
local SPAWN_INTERVAL = 0.32
local SPAWN_INTERVAL_LOW = 0.9

local EMOJIS = { "😂", "🔥", "💯", "😍", "🤯", "🎉", "💀", "👀", "✨", "🥳", "🤩", "💖", "🍩", "⭐", "🎈", "😎" }
local RARE = { "🦄", "🌈", "👑", "💎" } -- de temps en temps, plus gros

function EmojiRain.Start(ctx)
	local container: Frame = ctx.Container
	-- Tout en dessous des autres stimuli du calque (notifications, mails...) :
	-- la pluie reste un décor et ne recouvre jamais un élément à lire / cliquer
	container.ZIndex = 0
	local random = Random.new()

	local pool = {} -- toutes les gouttes (actives ou non)
	local activeCount = 0
	local spawnTimer = 0
	local clock = 0

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Récupère une goutte libre (ou en crée une tant qu'on est sous la limite)
	local function acquire()
		for _, drop in ipairs(pool) do
			if not drop.Active then
				return drop
			end
		end
		if #pool >= MAX_DROPS then
			return nil
		end
		local label = ctx.UIUtil.Create("TextLabel", {
			Name = "Emoji",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = ctx.Theme.Fonts.Body,
			Text = "",
			TextScaled = false,
			Active = false,
			Selectable = false,
			Visible = false,
			ZIndex = 1,
			Parent = container,
		})
		local drop = { Label = label, Active = false }
		table.insert(pool, drop)
		return drop
	end

	local function spawnDrop()
		local limit = effectsOn() and MAX_DROPS or MAX_DROPS_LOW
		if activeCount >= limit then
			return
		end
		local drop = acquire()
		if not drop then
			return
		end
		local rare = random:NextNumber() < 0.04
		local size = rare and random:NextInteger(46, 58) or random:NextInteger(20, 40)
		local label: TextLabel = drop.Label
		label.Text = rare and RARE[random:NextInteger(1, #RARE)] or EMOJIS[random:NextInteger(1, #EMOJIS)]
		label.TextSize = size
		label.Size = UDim2.fromOffset(size + 6, size + 6)
		label.TextTransparency = rare and 0.15 or random:NextNumber(0.2, 0.5)
		label.Rotation = random:NextNumber(-30, 30)
		label.Visible = true

		drop.Active = true
		drop.X = random:NextNumber(0.02, 0.98)
		drop.Y = -0.06
		-- Les gros tombent plus vite (effet de profondeur)
		drop.Speed = (0.05 + size / 400) * random:NextNumber(0.85, 1.15)
		drop.Spin = random:NextNumber(-80, 80)
		drop.SwayAmp = random:NextNumber(0.004, 0.018)
		drop.SwayFreq = random:NextNumber(1, 2.5)
		drop.Phase = random:NextNumber(0, math.pi * 2)
		activeCount += 1
	end

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt

		-- Nouvelles gouttes
		spawnTimer -= dt
		if spawnTimer <= 0 then
			spawnTimer = effectsOn() and SPAWN_INTERVAL or SPAWN_INTERVAL_LOW
			spawnDrop()
		end

		-- Petit vent qui change lentement de sens
		local wind = math.sin(clock * 0.25) * 0.012

		for _, drop in ipairs(pool) do
			if drop.Active then
				drop.Y += drop.Speed * dt
				drop.X += wind * dt
				local label: TextLabel = drop.Label
				if drop.Y > 1.08 or drop.X < -0.05 or drop.X > 1.05 then
					drop.Active = false
					label.Visible = false
					activeCount -= 1
				else
					local sway = math.sin(clock * drop.SwayFreq + drop.Phase) * drop.SwayAmp
					label.Position = UDim2.fromScale(drop.X + sway, drop.Y)
					label.Rotation += drop.Spin * dt
				end
			end
		end
	end)
end

function EmojiRain.Stop(_ctx)
	-- Les étiquettes sont dans ctx.Container (détruit par le StimulusManager)
end

return EmojiRain
