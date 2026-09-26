--[[
	Solo_WhackAMole (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_WhackAMole

	🔨 Tape-taupe de l'arcade : 30 secondes pour tapoter les taupes kawaii.
	Taupe = +1, taupe dorée 👑 = +3, bombe 💣 = -2.
	Les apparitions suivent un programme tiré d'une graine donnée par le
	SERVEUR (Solo_Logic.WhackSchedule) : à la fin, le client envoie la liste
	des taupes touchées et le serveur recalcule le score.
]]

local Kit = require(script.Parent.Solo_Kit)
local Logic = Kit.Logic
local C = Kit.Colors
local create = Kit.Create

local RISE = 0.12 -- durée de la sortie / rentrée d'une taupe
local MOLE_COLOR = Color3.fromRGB(196, 140, 104)
local GOLD_COLOR = Color3.fromRGB(255, 206, 70)
local BOMB_COLOR = Color3.fromRGB(58, 48, 78)

local Module = { Id = "WhackAMole", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	local gameRules = Logic.Games.WhackAMole
	local st = {
		Schedule = {} :: { any },
		MaxScore = 1,
		Thresholds = { 1, 2, 3 },
		Hits = {} :: { number },
		HitSet = {} :: { [number]: boolean },
		Score = 0,
		Running = false,
		Clock = 0,
		Cursor = 1,
		Token = nil,
		Generation = 0,
		Duration = gameRules.Duration,
	}
	local holes = {}

	kit = Kit.new(container, api, {
		Id = "WhackAMole",
		Primary = "Score",
		SmallA = "Next ⭐",
		SmallB = "Time left",
		Details = function(difficulty, rules)
			local speed = difficulty == "Easy" and T("Chill moles") or (difficulty == "Normal" and T("Quick moles") or T("Turbo moles"))
			return speed .. "  ·  " .. T("%ds", gameRules.Duration)
				.. "\n🐹 +1   👑 +3   💣 -2"
				.. "\n" .. T("⭐⭐⭐ = %d%% of the moles", math.floor(rules.Fractions[3] * 100))
		end,
		BestText = function(value)
			return T("%s pts", tostring(value))
		end,
		ScoreText = function(result)
			return "🔨 " .. T("%s pts", tostring(result.Score or 0))
		end,
		NoStarHint = function()
			return T("Golden moles are worth 3 points!")
		end,
		LoseTitle = "Time's up!",
		OnPlay = function(difficulty)
			startGame(difficulty)
		end,
		OnPicker = function()
			st.Generation += 1
			st.Running = false
		end,
		QuitArg = function()
			return { Hits = st.Hits }
		end,
	})
	kit.PickerHelp.Text = T("Bonk the moles before they hide · Golden = +3 · Avoid the bombs!")

	----------------------------------------------------------------------
	-- Pré carré : 3 x 3 terriers
	----------------------------------------------------------------------
	local field = create("Frame", {
		Name = "Field",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(96, 200, 130),
		ZIndex = 3,
		Parent = kit.Area,
	})
	Kit.Corner(field, 22)
	Kit.Gradient(field, Color3.fromRGB(130, 226, 150), Color3.fromRGB(60, 160, 110), 90)
	Kit.Stroke(field, Color3.fromRGB(200, 255, 210), 3, 0.3)
	create("UIAspectRatioConstraint", { AspectRatio = 1.3, Parent = field })
	-- pelouse tondue (bandes) + quelques fleurs sur les bords (décor fixe)
	for index = 0, 5 do
		create("Frame", {
			Position = UDim2.fromScale(0, index / 6),
			Size = UDim2.fromScale(1, 1 / 12),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = field,
		})
	end
	for index, spot in ipairs({ { 0.035, 0.3 }, { 0.965, 0.42 }, { 0.03, 0.72 }, { 0.97, 0.86 }, { 0.06, 0.06 }, { 0.94, 0.06 } }) do
		Kit.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromScale(0.045, 0.06),
			Text = ({ "🌼", "🌸", "🍀", "🌷" })[index % 4 + 1],
			MaxTextSize = 18,
			ZIndex = 3,
			Parent = field,
		})
	end
	local timeBar = create("Frame", {
		Name = "TimeBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.8, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(30, 70, 50),
		BackgroundTransparency = 0.3,
		ZIndex = 4,
		Parent = field,
	})
	Kit.Corner(timeBar, UDim.new(1, 0))
	local timeFill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Yellow,
		ZIndex = 5,
		Parent = timeBar,
	})
	Kit.Corner(timeFill, UDim.new(1, 0))
	Kit.Gradient(timeFill, C.Yellow, C.Orange, 0)

	local grid = create("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 1, -34),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = field,
	})

	local onHole

	-- Dessine une taupe kawaii (ou une bombe) dans `parent`
	local function makeMole(parent: Frame)
		local mole = create("Frame", {
			Name = "Mole",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.8, 0.95),
			BackgroundColor3 = MOLE_COLOR,
			ZIndex = 6,
			Parent = parent,
		})
		Kit.Corner(mole, UDim.new(0.48, 0))
		local gradientObj = create("UIGradient", {
			Color = ColorSequence.new(MOLE_COLOR:Lerp(C.White, 0.25), MOLE_COLOR:Lerp(C.Black, 0.15)),
			Rotation = 90,
			Parent = mole,
		})
		local belly = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.62, 0.6),
			BackgroundColor3 = Color3.fromRGB(250, 222, 196),
			ZIndex = 7,
			Parent = mole,
		})
		Kit.Corner(belly, UDim.new(0.5, 0))
		local eyes = {}
		local cheeks = {}
		for side = 0, 1 do
			local eye = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(side == 0 and 0.32 or 0.68, 0.3),
				Size = UDim2.fromScale(0.13, 0.12),
				BackgroundColor3 = Color3.fromRGB(40, 24, 40),
				ZIndex = 8,
				Parent = mole,
			})
			Kit.Corner(eye, UDim.new(1, 0))
			local spark = create("Frame", {
				Position = UDim2.fromScale(0.2, 0.12),
				Size = UDim2.fromScale(0.45, 0.42),
				BackgroundColor3 = C.White,
				ZIndex = 9,
				Parent = eye,
			})
			Kit.Corner(spark, UDim.new(1, 0))
			local cheek = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(side == 0 and 0.2 or 0.8, 0.44),
				Size = UDim2.fromScale(0.16, 0.08),
				BackgroundColor3 = Color3.fromRGB(255, 130, 160),
				BackgroundTransparency = 0.3,
				ZIndex = 8,
				Parent = mole,
			})
			Kit.Corner(cheek, UDim.new(1, 0))
			eyes[side + 1] = eye
			cheeks[side + 1] = cheek
		end
		local nose = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(0.16, 0.1),
			BackgroundColor3 = Color3.fromRGB(255, 120, 150),
			ZIndex = 9,
			Parent = mole,
		})
		Kit.Corner(nose, UDim.new(1, 0))
		local icon = Kit.Label({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.fromScale(0.9, 0.62),
			Text = "",
			MaxTextSize = 60,
			ZIndex = 10,
			Parent = mole,
		})
		local crown = Kit.Label({
			Name = "Crown",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.08),
			Size = UDim2.fromScale(0.5, 0.24),
			Text = "👑",
			Visible = false,
			MaxTextSize = 30,
			ZIndex = 10,
			Parent = mole,
		})
		local scale = create("UIScale", { Parent = mole })
		local outline = Kit.Stroke(mole, C.Red, 2.5, 0)
		outline.Enabled = false
		return {
			Frame = mole,
			Cheeks = cheeks,
			Outline = outline,
			Gradient = gradientObj,
			Belly = belly,
			Eyes = eyes,
			Nose = nose,
			Icon = icon,
			Crown = crown,
			Scale = scale,
		}
	end

	local function styleMole(mole, kind: number)
		local bomb = kind == 3
		local color = kind == 2 and GOLD_COLOR or (bomb and BOMB_COLOR or MOLE_COLOR)
		mole.Frame.BackgroundColor3 = color
		mole.Gradient.Color = ColorSequence.new(color:Lerp(C.White, 0.25), color:Lerp(C.Black, 0.15))
		mole.Belly.Visible = not bomb
		mole.Nose.Visible = not bomb
		for _, eye in ipairs(mole.Eyes) do
			eye.Visible = not bomb
			eye.Size = UDim2.fromScale(0.13, 0.12)
		end
		mole.Frame.Visible = true
		mole.Icon.Text = bomb and "💣" or ""
		mole.Crown.Visible = kind == 2
		for _, cheek in ipairs(mole.Cheeks) do
			cheek.Visible = not bomb
		end
		-- contour : rouge = danger, doré = bonus
		mole.Outline.Enabled = kind ~= 1
		mole.Outline.Color = bomb and C.Red or C.White
	end

	for index = 1, gameRules.Holes do
		local x = (index - 1) % 3
		local y = (index - 1) // 3
		local cell = create("TextButton", {
			Name = "Hole" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(x / 3, y / 3),
			Size = UDim2.fromScale(1 / 3, 1 / 3),
			ZIndex = 5,
			Parent = grid,
		})
		-- Terrier : monticule + trou sombre
		local mound = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.97),
			Size = UDim2.fromScale(0.7, 0.4),
			BackgroundColor3 = Color3.fromRGB(150, 100, 70),
			ZIndex = 5,
			Parent = cell,
		})
		Kit.Corner(mound, UDim.new(0.5, 0))
		Kit.Gradient(mound, Color3.fromRGB(176, 124, 88), Color3.fromRGB(120, 78, 54), 90)
		local hole = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromScale(0.8, 0.56),
			BackgroundColor3 = Color3.fromRGB(46, 26, 22),
			ZIndex = 6,
			Parent = mound,
		})
		Kit.Corner(hole, UDim.new(0.5, 0))
		Kit.Gradient(hole, Color3.fromRGB(20, 10, 10), Color3.fromRGB(70, 40, 32), 90)
		-- Zone de sortie de la taupe (coupée au niveau du trou)
		local clip = create("Frame", {
			Name = "Clip",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.73),
			Size = UDim2.fromScale(0.6, 0.72),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 6,
			Parent = cell,
		})
		local mole = makeMole(clip)
		local hammer = Kit.Label({
			Name = "Hammer",
			AnchorPoint = Vector2.new(0.2, 0.8),
			Position = UDim2.fromScale(0.72, 0.35),
			Size = UDim2.fromScale(0.42, 0.42),
			Text = "🔨",
			Visible = false,
			MaxTextSize = 44,
			ZIndex = 12,
			Parent = cell,
		})
		local entry = {
			Cell = cell,
			Mole = mole,
			Hammer = hammer,
			Index = index,
			Current = nil :: number?, -- index de la taupe dans le programme
			HammerTime = 0,
			Squash = 0,
		}
		holes[index] = entry
		cell.Activated:Connect(function()
			onHole(entry.Index)
		end)
	end

	----------------------------------------------------------------------
	-- Partie
	----------------------------------------------------------------------
	kit:UseRating(0)
	local function refreshHud()
		kit:SetRatingFromScore(st.Score, st.Thresholds)
		kit:SetStat("Primary", tostring(st.Score))
		kit:SetStat("A", kit:NextStarText(st.Score, st.Thresholds))
		kit:SetStat("B", tostring(math.max(0, math.ceil(st.Duration - st.Clock))) .. "s")
		timeFill.Size = UDim2.fromScale(math.clamp(1 - st.Clock / st.Duration, 0, 1), 1)
	end

	local function finish(generation: number)
		st.Running = false
		kit:Mood("⏰", T("Time's up!"))
		kit:Sound("Bonus")
		local token = st.Token
		local hits = table.clone(st.Hits)
		task.spawn(function()
			local ok, result = kit:Invoke("solo:finish", { Token = token, Hits = hits })
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			if not ok or type(result) ~= "table" then
				kit:Notify(type(result) == "string" and result or T("Something went wrong"), C.Red)
				kit:ShowPicker()
				return
			end
			task.wait(0.4)
			kit:ShowResult(result)
		end)
	end

	function onHole(index: number)
		local entry = holes[index]
		if not st.Running or not entry then
			return
		end
		entry.HammerTime = 0.22
		entry.Hammer.Visible = true
		local moleIndex = entry.Current
		if not moleIndex or st.HitSet[moleIndex] then
			kit:Sound("Click", 0.8)
			return
		end
		local mole = st.Schedule[moleIndex]
		st.HitSet[moleIndex] = true
		table.insert(st.Hits, moleIndex)
		local value = Logic.WhackValues[mole.Kind] or 0
		st.Score = math.max(0, st.Score + value)
		entry.Squash = 0.25
		if mole.Kind == 3 then
			kit:Float(entry.Cell, "-2", C.Red)
			kit:Sound("Thunder")
			kit:Shake(field, 8)
			kit:Mood("😖", T("Ouch, a bomb! Avoid them."))
		elseif mole.Kind == 2 then
			kit:Float(entry.Cell, "+3", C.Yellow)
			kit:Burst(entry.Cell, C.Yellow, 12)
			kit:Sound("Cash")
			kit:Mood("🤑", T("Golden mole! +3"))
		else
			kit:Float(entry.Cell, "+1", C.White)
			kit:Burst(entry.Cell, MOLE_COLOR, 6)
			kit:Sound("Pop", 0.9 + math.random() * 0.3)
		end
		kit:SetStat("Primary", tostring(st.Score), true)
		refreshHud()
	end

	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Running = false
		st.Schedule = {}
		st.Hits = {}
		st.HitSet = {}
		st.Score = 0
		st.Clock = 0
		st.Cursor = 1
		st.Token = nil
		for _, entry in ipairs(holes) do
			entry.Current = nil
			entry.Mole.Frame.Position = UDim2.fromScale(0.5, 1)
			entry.Mole.Frame.Visible = false
			entry.Mole.Crown.Visible = false
		end
		refreshHud()
		kit:Mood("😊", T("Bonk the moles! Golden = +3, avoid bombs."))
		task.spawn(function()
			local reply = kit:StartSession()
			if generation ~= st.Generation then
				return
			end
			if not reply or type(reply.Seed) ~= "number" then
				kit:ShowPicker()
				return
			end
			st.Token = reply.Token
			st.Duration = tonumber(reply.Duration) or gameRules.Duration
			st.Schedule, st.MaxScore = Logic.WhackSchedule(reply.Seed, rules, gameRules.Holes, st.Duration)
			st.Thresholds = {}
			for index, fraction in ipairs(rules.Fractions) do
				st.Thresholds[index] = math.max(1, math.floor(st.MaxScore * fraction + 0.5))
			end
			refreshHud()
		end)
		kit:Countdown(function()
			if generation ~= st.Generation then
				return
			end
			-- (si le serveur n'a pas encore répondu, on attend un peu)
			local waited = 0
			while not st.Token and waited < 5 and generation == st.Generation do
				waited += task.wait(0.1)
			end
			if not st.Token or generation ~= st.Generation then
				return
			end
			st.Running = true
			kit:Mood("😆", T("Go go go!"), false)
		end)
	end

	-- Boucle : programme des taupes, animations, chrono
	local hudTimer = 0
	kit:OnFrame(function(dt)
		for _, entry in ipairs(holes) do
			if entry.HammerTime > 0 then
				entry.HammerTime -= dt
				entry.Hammer.Rotation = -50 + 70 * math.clamp(1 - entry.HammerTime / 0.22, 0, 1)
				if entry.HammerTime <= 0 then
					entry.Hammer.Visible = false
				end
			end
		end
		if not st.Running then
			return
		end
		st.Clock += dt
		local t = st.Clock
		-- nouvelles taupes
		local schedule = st.Schedule
		while st.Cursor <= #schedule and schedule[st.Cursor].T <= t do
			local mole = schedule[st.Cursor]
			local entry = holes[mole.Hole]
			if entry then
				entry.Current = st.Cursor
				styleMole(entry.Mole, mole.Kind)
				entry.Squash = 0
			end
			st.Cursor += 1
		end
		-- position des taupes visibles
		for _, entry in ipairs(holes) do
			local moleIndex = entry.Current
			if moleIndex then
				local mole = schedule[moleIndex]
				local age = t - mole.T
				local hit = st.HitSet[moleIndex]
				local frame = entry.Mole.Frame
				if age >= mole.Up or (hit and entry.Squash <= 0) then
					entry.Current = nil
					frame.Position = UDim2.fromScale(0.5, 1)
					frame.Visible = false
					entry.Mole.Crown.Visible = false
				else
					local up
					if hit then
						entry.Squash -= dt
						up = math.clamp(entry.Squash / 0.25, 0, 1)
						for _, eye in ipairs(entry.Mole.Eyes) do
							eye.Size = UDim2.fromScale(0.16, 0.04)
						end
					else
						up = math.min(age / RISE, (mole.Up - age) / RISE, 1)
					end
					up = math.clamp(up, 0, 1)
					frame.Position = UDim2.fromScale(0.5, 1 - 0.9 * up)
				end
			end
		end
		hudTimer += dt
		if hudTimer >= 0.1 then
			hudTimer = 0
			refreshHud()
			if st.Duration - t <= 5 and st.Duration - t > 4.9 then
				kit:Mood("⏰", T("Hurry up!"), true)
			end
		end
		if t >= st.Duration then
			for _, entry in ipairs(holes) do
				entry.Current = nil
				entry.Mole.Frame.Position = UDim2.fromScale(0.5, 1)
				entry.Mole.Frame.Visible = false
				entry.Mole.Crown.Visible = false
			end
			finish(st.Generation)
		end
	end)

	-- Premier affichage : quelques taupes qui saluent derrière le sélecteur
	for index, kind in pairs({ [2] = 1, [4] = 2, [9] = 3 }) do
		styleMole(holes[index].Mole, kind)
		holes[index].Mole.Frame.Position = UDim2.fromScale(0.5, 0.12)
	end
	refreshHud()
	kit:Mood("😊", T("Bonk the moles! Golden = +3, avoid bombs."), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			kit:Destroy()
		end,
	}
end

return Module
