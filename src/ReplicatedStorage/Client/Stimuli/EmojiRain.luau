--[[
	EmojiRain (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > EmojiRain

	Une pluie d'emojis variée et vivante, en décor derrière tout le reste :
	  - des thèmes qui changent toutes les ~25 s en fondu (fête, amour,
	    miam, espace, animaux, hype, nature, jackpot) ;
	  - plusieurs façons de tomber : balancement, toupie, feuille qui
	    virevolte, rebond sur le bas de l'écran puis disparition ;
	  - de la profondeur : petits emojis pâles et lents au loin, gros et
	    nets devant ;
	  - de temps en temps un emoji "héros" géant avec un halo, et une
	    explosion d'emojis (un gros qui gonfle puis éclate en morceaux).
	Uniquement des TextLabels non cliquables (Active = false) : on ne bloque
	jamais les boutons en dessous. Étiquettes recyclées (35 au maximum),
	beaucoup moins d'emojis si le réglage "Effets" est coupé.
]]

local EmojiRain = {}
EmojiRain.Slot = "Overlay"

local POOL_SIZE = 34 -- + 1 halo = 35 étiquettes au total
local MAX_ACTIVE = 26
local MAX_ACTIVE_LOW = 9 -- réglage "Effets" désactivé
local SPAWN_INTERVAL = 0.28
local SPAWN_INTERVAL_LOW = 0.95
local THEME_BLEND = 4 -- durée du fondu entre deux thèmes (s)
local DESIGN_H = 720 -- hauteur de la toile "design"
local GRAVITY = 1.5 -- (hauteur d'écran / s²) pour les rebonds et les éclats

local THEMES = {
	{ Emojis = { "🎉", "🥳", "🎊", "🎈", "✨", "🎁", "🍾" }, Hero = { "🥳", "🎉", "🎁" }, Glow = Color3.fromRGB(255, 214, 90) },
	{ Emojis = { "💖", "😍", "💕", "💘", "😘", "🌹", "💝" }, Hero = { "💖", "😍" }, Glow = Color3.fromRGB(255, 120, 176) },
	{ Emojis = { "🍕", "🍩", "🍔", "🍟", "🍓", "🧁", "🍪", "🍿" }, Hero = { "🍩", "🍕", "🍔" }, Glow = Color3.fromRGB(255, 172, 90) },
	{ Emojis = { "🚀", "⭐", "🌙", "👽", "🌍", "🛸", "💫", "🌟" }, Hero = { "🚀", "🛸", "🌍" }, Glow = Color3.fromRGB(140, 160, 255) },
	{ Emojis = { "🐶", "🐱", "🦊", "🐼", "🐸", "🐧", "🦄", "🐥" }, Hero = { "🦄", "🐼", "🐶" }, Glow = Color3.fromRGB(150, 226, 140) },
	{ Emojis = { "🔥", "💯", "🤯", "😂", "💀", "👀", "🤩", "😎" }, Hero = { "🔥", "💯", "🤯" }, Glow = Color3.fromRGB(255, 132, 60) },
	{ Emojis = { "🌸", "🍀", "🌈", "🌻", "🍁", "🌷", "🦋" }, Hero = { "🌈", "🦋", "🌻" }, Glow = Color3.fromRGB(140, 224, 176) },
	{ Emojis = { "💰", "💎", "🤑", "👑", "💵", "⭐" }, Hero = { "💎", "👑", "💰" }, Glow = Color3.fromRGB(255, 220, 60) },
}

-- Couches de profondeur : loin (petit, pâle, lent) -> près (gros, net, rapide)
local LAYERS = {
	{ Chance = 0.4, MinSize = 15, MaxSize = 22, Transparency = { 0.55, 0.7 }, Speed = { 0.045, 0.065 }, ZIndex = 1 },
	{ Chance = 0.35, MinSize = 25, MaxSize = 33, Transparency = { 0.3, 0.45 }, Speed = { 0.075, 0.1 }, ZIndex = 2 },
	{ Chance = 0.25, MinSize = 38, MaxSize = 50, Transparency = { 0.15, 0.28 }, Speed = { 0.11, 0.15 }, ZIndex = 3 },
}

-- Façons de tomber (probabilités cumulées plus bas)
local STYLES = {
	{ Name = "Sway", Weight = 0.38 },
	{ Name = "Spin", Weight = 0.2 },
	{ Name = "Flutter", Weight = 0.22 },
	{ Name = "Bounce", Weight = 0.2 },
}

function EmojiRain.Start(ctx)
	local container: Frame = ctx.Container
	-- Tout en dessous des autres stimuli du calque (notifications, mails...) :
	-- la pluie reste un décor et ne recouvre jamais un élément à lire / cliquer
	container.ZIndex = 0
	local UIUtil = ctx.UIUtil
	local random = Random.new()

	local pool: { any } = {}
	local activeCount = 0
	local spawnTimer = 0
	local clock = 0

	local themeIndex = random:NextInteger(1, #THEMES)
	local previousTheme = themeIndex
	local themeAge = THEME_BLEND -- pas de fondu au démarrage
	local themeDuration = random:NextNumber(20, 28)
	local burstTimer = random:NextNumber(6, 10)
	local heroTimer = random:NextNumber(8, 14)
	local heroDrop: any = nil -- l'emoji héros actuel (un seul à la fois)
	local rushLeft = 0 -- petite averse au changement de thème

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Halo derrière l'emoji héros (une étiquette ronde sans texte)
	local glow = UIUtil.Create("TextLabel", {
		Name = "HeroGlow",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEMES[themeIndex].Glow,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		Visible = false,
		ZIndex = 4,
		Parent = container,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))
	local glowStroke = UIUtil.Stroke(glow, THEMES[themeIndex].Glow, 8, 1)

	-- Crée toutes les étiquettes une fois pour toutes
	for _ = 1, POOL_SIZE do
		local label = UIUtil.Create("TextLabel", {
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
		table.insert(pool, { Label = label, Active = false })
	end

	local function acquire()
		for _, drop in ipairs(pool) do
			if not drop.Active then
				return drop
			end
		end
		return nil
	end

	local function release(drop)
		if drop.Active then
			drop.Active = false
			activeCount -= 1
		end
		drop.Label.Visible = false
		if drop == heroDrop then
			heroDrop = nil
			glow.Visible = false
		end
	end

	-- Thème du moment (pendant le fondu : mélange avec l'ancien)
	local function currentTheme()
		if themeAge < THEME_BLEND and random:NextNumber() > themeAge / THEME_BLEND then
			return THEMES[previousTheme]
		end
		return THEMES[themeIndex]
	end

	local function pick(list: { string }): string
		return list[random:NextInteger(1, #list)]
	end

	local function setSize(drop, size: number)
		drop.Size = size
		drop.Label.TextSize = size
		drop.Label.Size = UDim2.fromOffset(size * 1.3, size * 1.3)
	end

	-- Prépare une goutte commune à tous les styles
	local function activate(drop, text: string, size: number, transparency: number, zIndex: number)
		local label: TextLabel = drop.Label
		label.Text = text
		label.TextTransparency = transparency
		label.ZIndex = zIndex
		label.Rotation = 0
		label.Visible = true
		setSize(drop, size)
		drop.Active = true
		drop.Alpha = transparency
		drop.Age = 0
		drop.Rot = 0
		drop.Spin = 0
		drop.VX = 0
		drop.VY = 0
		drop.Bounces = 0
		drop.Fade = -1 -- < 0 : pas encore en train de disparaître
		activeCount += 1
	end

	-- Une goutte "normale" qui tombe du haut
	local function spawnDrop()
		local drop = acquire()
		if not drop then
			return
		end
		local roll = random:NextNumber()
		local layer = LAYERS[#LAYERS]
		local acc = 0
		for _, candidate in ipairs(LAYERS) do
			acc += candidate.Chance
			if roll <= acc then
				layer = candidate
				break
			end
		end
		local styleRoll = random:NextNumber()
		local style = "Sway"
		acc = 0
		for _, candidate in ipairs(STYLES) do
			acc += candidate.Weight
			if styleRoll <= acc then
				style = candidate.Name
				break
			end
		end

		local size = random:NextInteger(layer.MinSize, layer.MaxSize)
		activate(drop, pick(currentTheme().Emojis), size, random:NextNumber(layer.Transparency[1], layer.Transparency[2]), layer.ZIndex)
		drop.Style = style
		drop.BaseX = random:NextNumber(0.02, 0.98)
		drop.X = drop.BaseX
		drop.Y = -0.06
		drop.Speed = random:NextNumber(layer.Speed[1], layer.Speed[2])
		drop.Phase = random:NextNumber(0, math.pi * 2)
		drop.SwayAmp = random:NextNumber(0.006, 0.02)
		drop.SwayFreq = random:NextNumber(1, 2.2)
		drop.Rot = random:NextNumber(-25, 25)

		if style == "Spin" then
			drop.Speed *= 1.25
			drop.Spin = random:NextNumber(140, 280) * ((random:NextNumber() < 0.5) and -1 or 1)
		elseif style == "Flutter" then
			drop.Speed *= 0.75
			drop.SwayAmp = random:NextNumber(0.025, 0.05)
			drop.SwayFreq = random:NextNumber(0.9, 1.5)
		elseif style == "Bounce" then
			drop.VY = drop.Speed
			drop.VX = random:NextNumber(-0.03, 0.03)
			drop.Spin = random:NextNumber(-90, 90)
		end
	end

	-- Emoji héros : géant, lent, avec un halo qui pulse
	local function spawnHero()
		local drop = acquire()
		if not drop then
			return
		end
		local theme = THEMES[themeIndex]
		activate(drop, pick(theme.Hero), random:NextInteger(64, 78), 0.15, 5)
		drop.Style = "Hero"
		drop.BaseX = random:NextNumber(0.08, 0.92)
		drop.X = drop.BaseX
		drop.Y = -0.12
		drop.Speed = random:NextNumber(0.06, 0.075)
		drop.Phase = random:NextNumber(0, math.pi * 2)
		drop.SwayAmp = 0.025
		drop.SwayFreq = 0.8
		heroDrop = drop
		glow.BackgroundColor3 = theme.Glow
		glowStroke.Color = theme.Glow
		glow.Visible = true
	end

	-- Explosion : un gros emoji gonfle puis éclate en morceaux
	local function spawnBurst()
		local drop = acquire()
		if not drop then
			return
		end
		activate(drop, pick(THEMES[themeIndex].Hero), 1, 0.05, 5)
		drop.Style = "Burst"
		drop.X = random:NextNumber(0.1, 0.9)
		drop.Y = random:NextNumber(0.18, 0.5)
		drop.Spin = random:NextNumber(-40, 40)
	end

	local function explode(x: number, y: number)
		local theme = THEMES[themeIndex]
		local pieces = random:NextInteger(6, 8)
		for i = 1, pieces do
			local drop = acquire()
			if not drop then
				return
			end
			activate(drop, pick(theme.Emojis), random:NextInteger(22, 36), 0.1, 4)
			drop.Style = "Piece"
			drop.X, drop.Y = x, y
			local angle = (i / pieces) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
			local power = random:NextNumber(0.25, 0.45)
			-- Toile 16:9 : l'écart horizontal est "écrasé" pour rester rond
			drop.VX = math.cos(angle) * power * 0.5625
			drop.VY = math.sin(angle) * power - 0.25
			drop.Spin = random:NextNumber(-300, 300)
			drop.Life = random:NextNumber(0.9, 1.3)
		end
	end

	ctx.OnRender(function(rawDt: number)
		local dt = math.min(rawDt, 0.1)
		clock += dt
		local fx = effectsOn()

		-- Changement de thème (en fondu) + petite averse
		themeAge += dt
		if themeAge >= themeDuration then
			previousTheme = themeIndex
			local nextTheme = random:NextInteger(1, #THEMES - 1)
			if nextTheme >= themeIndex then
				nextTheme += 1
			end
			themeIndex = nextTheme
			themeAge = 0
			themeDuration = random:NextNumber(20, 28)
			rushLeft = fx and 6 or 0
		end

		-- Nouvelles gouttes
		local limit = fx and MAX_ACTIVE or MAX_ACTIVE_LOW
		spawnTimer -= dt
		if spawnTimer <= 0 then
			if rushLeft > 0 then
				rushLeft -= 1
				spawnTimer = 0.08
			else
				spawnTimer = (fx and SPAWN_INTERVAL or SPAWN_INTERVAL_LOW) * random:NextNumber(0.7, 1.3)
			end
			if activeCount < limit then
				spawnDrop()
			end
		end

		heroTimer -= dt
		if heroTimer <= 0 then
			heroTimer = random:NextNumber(10, 18) * (fx and 1 or 2)
			if not heroDrop and activeCount < limit then
				spawnHero()
			end
		end

		if fx then
			burstTimer -= dt
			if burstTimer <= 0 then
				burstTimer = random:NextNumber(9, 16)
				if activeCount <= POOL_SIZE - 9 then
					spawnBurst()
				end
			end
		end

		-- Petit vent qui change lentement de sens
		local wind = math.sin(clock * 0.23) * 0.012

		for _, drop in ipairs(pool) do
			if drop.Active then
				drop.Age += dt
				local label: TextLabel = drop.Label
				local style = drop.Style
				local x, y = drop.X, drop.Y
				local rotation = drop.Rot
				local transparency = drop.Alpha
				local remove = false
				local burstAt: Vector2? = nil

				if style == "Sway" or style == "Hero" then
					drop.Y += drop.Speed * dt
					drop.BaseX += wind * dt
					local wave = math.sin(clock * drop.SwayFreq + drop.Phase)
					x = drop.BaseX + wave * drop.SwayAmp
					y = drop.Y
					rotation = drop.Rot + wave * 14
					remove = y > 1.12
				elseif style == "Spin" then
					drop.Y += drop.Speed * dt
					drop.BaseX += wind * 1.4 * dt
					drop.Rot += drop.Spin * dt
					x = drop.BaseX + math.sin(clock * drop.SwayFreq + drop.Phase) * drop.SwayAmp * 0.5
					y = drop.Y
					rotation = drop.Rot
					remove = y > 1.1
				elseif style == "Flutter" then
					-- Feuille : zigzag large, penche dans le sens où elle glisse
					drop.Y += drop.Speed * dt * (0.75 + 0.25 * math.abs(math.cos(clock * drop.SwayFreq + drop.Phase)))
					drop.BaseX += wind * 1.8 * dt
					local wave = math.sin(clock * drop.SwayFreq + drop.Phase)
					x = drop.BaseX + wave * drop.SwayAmp
					y = drop.Y
					rotation = math.cos(clock * drop.SwayFreq + drop.Phase) * 38
					remove = y > 1.1
				elseif style == "Bounce" then
					-- Tombe, rebondit sur le bas de l'écran puis s'efface
					local floorY = 1 - (drop.Size * 0.5) / DESIGN_H
					if drop.Fade < 0 then
						drop.VY += GRAVITY * 0.35 * dt
						drop.Y += drop.VY * dt
						drop.X += (drop.VX + wind) * dt
						drop.Rot += drop.Spin * dt
						if drop.Y >= floorY and drop.VY > 0 then
							drop.Y = floorY
							drop.Bounces += 1
							drop.VY = -drop.VY * 0.5
							drop.Spin = -drop.Spin * 0.7
							if drop.Bounces >= 2 or math.abs(drop.VY) < 0.03 then
								drop.Fade = 0
							end
						end
					else
						-- Au sol : glisse un peu, s'aplatit et disparaît
						drop.Fade += dt
						drop.X += drop.VX * dt * 0.5
						drop.Y = floorY
						local t = math.clamp(drop.Fade / 0.6, 0, 1)
						transparency = drop.Alpha + (1 - drop.Alpha) * t
						remove = t >= 1
					end
					x, y = drop.X, drop.Y
					rotation = drop.Rot
				elseif style == "Burst" then
					-- Gonfle (avec rebond), tremble, puis éclate
					local age = drop.Age
					local grow = math.clamp(age / 0.35, 0, 1)
					local overshoot = 1 + math.sin(grow * math.pi) * 0.25
					local size = 60 * grow * overshoot
					if age > 0.55 then
						size = 60 * (1 + (age - 0.55) * 1.8)
						x = drop.X + random:NextNumber(-0.002, 0.002)
						y = drop.Y + random:NextNumber(-0.003, 0.003)
					end
					setSize(drop, math.max(1, size))
					rotation = math.sin(age * 30) * 8 * math.clamp((age - 0.4) * 4, 0, 1)
					if age > 0.8 then
						remove = true
						burstAt = Vector2.new(drop.X, drop.Y)
					end
				elseif style == "Piece" then
					drop.VY += GRAVITY * dt
					drop.X += drop.VX * dt
					drop.Y += drop.VY * dt
					drop.Rot += drop.Spin * dt
					x, y = drop.X, drop.Y
					rotation = drop.Rot
					local t = math.clamp(drop.Age / drop.Life, 0, 1)
					transparency = drop.Alpha + (1 - drop.Alpha) * t * t
					remove = t >= 1 or y > 1.1
				end

				if x < -0.08 or x > 1.08 then
					remove = true
				end

				if remove then
					release(drop)
					if burstAt then
						explode(burstAt.X, burstAt.Y) -- après la libération : l'étiquette peut servir d'éclat
					end
				else
					label.Position = UDim2.fromScale(x, y)
					label.Rotation = rotation
					label.TextTransparency = transparency
					if drop == heroDrop then
						local pulse = 1 + math.sin(clock * 3) * 0.08
						local glowSize = drop.Size * 1.5 * pulse
						glow.Position = label.Position
						glow.Size = UDim2.fromOffset(glowSize, glowSize)
						glow.BackgroundTransparency = 0.72 + math.sin(clock * 3) * 0.06
						glowStroke.Transparency = 0.8
					end
				end
			end
		end
	end)
end

function EmojiRain.Stop(_ctx)
	-- Les étiquettes sont dans ctx.Container (détruit par le StimulusManager)
end

return EmojiRain
