--[[
	Solo_Snake (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Snake

	🐍 Snake de l'arcade : un serpent kawaii mange des fruits et grandit.
	Flèches / ZQSD / WASD, glissé du doigt sur le plateau, ou croix
	directionnelle (écrans tactiles).
	La simulation est celle de Solo_Logic (graine donnée par le SERVEUR) :
	à la fin, le client envoie ses virages { pas, direction } et le serveur
	rejoue la partie pour calculer le vrai score.
	Mouvement fluide : les anneaux glissent entre deux cases (interpolation).
]]

local Kit = require(script.Parent.Solo_Kit)
local UIUtil = require(script.Parent.Parent.UIUtil)
local Logic = Kit.Logic
local C = Kit.Colors
local create = Kit.Create

local FRUITS = { "🍓", "🍒", "🍑", "🍉", "🍇", "🍎", "🍍", "🥝" }
local HEAD_COLOR = Color3.fromRGB(110, 240, 170)
local TAIL_COLOR = Color3.fromRGB(70, 190, 255)
local DPAD_WIDTH = 150

local Module = { Id = "Snake", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	local st = {
		Sim = nil :: any,
		Rules = nil :: any,
		Running = false,
		Acc = 0,
		Interval = 0.12,
		Queue = {} :: { number },
		Turns = {} :: { number },
		Prev = {} :: { number }, -- case précédente de chaque anneau (interpolation)
		Token = nil,
		Generation = 0,
		Clock = 0,
		Cols = 16,
		Rows = 11,
	}
	local segments = {}
	local tiles = {}

	kit = Kit.new(container, api, {
		Id = "Snake",
		Primary = "Snacks",
		SmallA = "Next ⭐",
		SmallB = "Time",
		Details = function(_, rules)
			local walls = rules.Wrap and T("No walls: go through the edges") or T("Walls hurt!")
			return string.format("%d × %d  ·  ", rules.Cols, rules.Rows) .. walls
				.. "\n" .. T("⭐ %d snacks · ⭐⭐ %d · ⭐⭐⭐ %d", rules.Thresholds[1], rules.Thresholds[2], rules.Thresholds[3])
		end,
		BestText = function(value)
			return T("%s snacks", tostring(value))
		end,
		ScoreText = function(result)
			return "🍓 " .. T("%s snacks", tostring(result.Score or 0)) .. "  ·  ⏱️ " .. Kit.FormatClock(st.Clock)
		end,
		NoStarHint = function(rules)
			return T("Eat %d snacks for your first ⭐!", rules.Thresholds[1])
		end,
		LoseTitle = "Ouch!",
		OnPlay = function(difficulty)
			startGame(difficulty)
		end,
		OnPicker = function()
			st.Generation += 1
			st.Running = false
		end,
		QuitArg = function()
			local sim = st.Sim
			return { Turns = st.Turns, Ticks = sim and sim.Tick or 0 }
		end,
	})
	kit.PickerHelp.Text = kit.Touch and T("Swipe on the board or use the arrows to steer")
		or T("Arrow keys / WASD to steer · Eat snacks, avoid your tail")

	----------------------------------------------------------------------
	-- Plateau
	----------------------------------------------------------------------
	local holder = create("Frame", {
		Name = "BoardHolder",
		Size = UDim2.new(1, kit.Touch and -DPAD_WIDTH or 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = kit.Area,
	})
	local board = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(34, 26, 78),
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = holder,
	})
	Kit.Corner(board, 14)
	Kit.Stroke(board, kit.Accent, 2.5, 0.2)
	local aspect = create("UIAspectRatioConstraint", { AspectRatio = 16 / 11, Parent = board })
	local tileLayer = create("Frame", {
		Name = "Tiles",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = board,
	})
	local snakeLayer = create("Frame", {
		Name = "Snake",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = board,
	})
	local food = Kit.Label({
		Name = "Food",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "🍓",
		MaxTextSize = 40,
		ZIndex = 6,
		Parent = board,
	})
	local foodScale = create("UIScale", { Parent = food })
	local foodTime = 0

	-- Cases en damier (seulement les cases claires : moitié moins de cadres)
	local function buildTiles()
		for _, tile in ipairs(tiles) do
			tile.Visible = false
		end
		local count = 0
		for y = 0, st.Rows - 1 do
			for x = 0, st.Cols - 1 do
				if (x + y) % 2 == 0 then
					count += 1
					local tile = tiles[count]
					if not tile then
						tile = create("Frame", {
							BackgroundColor3 = Color3.fromRGB(52, 40, 108),
							BorderSizePixel = 0,
							ZIndex = 3,
							Parent = tileLayer,
						})
						tiles[count] = tile
					end
					tile.Position = UDim2.fromScale(x / st.Cols, y / st.Rows)
					tile.Size = UDim2.fromScale(1 / st.Cols, 1 / st.Rows)
					tile.Visible = true
				end
			end
		end
	end

	-- Anneaux du serpent (réutilisés)
	local function getSegment(index: number)
		local segment = segments[index]
		if segment then
			return segment
		end
		local frame = create("Frame", {
			Name = "Seg" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = HEAD_COLOR,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = snakeLayer,
		})
		Kit.Corner(frame, UDim.new(0.42, 0))
		segment = { Frame = frame }
		if index == 1 then
			frame.ZIndex = 7
			Kit.Stroke(frame, C.White, 1.5, 0.4)
			segment.Eyes = {}
			for side = 1, 2 do
				local eye = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromScale(0.34, 0.34),
					BackgroundColor3 = C.White,
					ZIndex = 8,
					Parent = frame,
				})
				Kit.Corner(eye, UDim.new(1, 0))
				local pupil = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.55, 0.55),
					Size = UDim2.fromScale(0.55, 0.55),
					BackgroundColor3 = Color3.fromRGB(30, 20, 50),
					ZIndex = 9,
					Parent = eye,
				})
				Kit.Corner(pupil, UDim.new(1, 0))
				segment.Eyes[side] = { Eye = eye, Pupil = pupil }
			end
			segment.Blush = {}
			for side = 1, 2 do
				local blush = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromScale(0.22, 0.14),
					BackgroundColor3 = Color3.fromRGB(255, 130, 170),
					BackgroundTransparency = 0.25,
					ZIndex = 8,
					Parent = frame,
				})
				Kit.Corner(blush, UDim.new(1, 0))
				segment.Blush[side] = blush
			end
		end
		segments[index] = segment
		return segment
	end

	local function cellXY(index: number): (number, number)
		return (index - 1) % st.Cols, (index - 1) // st.Cols
	end

	-- Couleurs + yeux (à chaque pas)
	local function styleSnake()
		local sim = st.Sim
		local length = #sim.Body
		for index = 1, math.max(length, #segments) do
			local segment = segments[index]
			if index <= length then
				segment = getSegment(index)
				local k = length > 1 and (index - 1) / (length - 1) or 0
				segment.Frame.BackgroundColor3 = HEAD_COLOR:Lerp(TAIL_COLOR, k)
				local size = index == 1 and 1.08 or (0.96 - 0.22 * k)
				segment.Frame.Size = UDim2.fromScale(size / st.Cols, size / st.Rows)
				segment.Frame.Visible = true
			elseif segment then
				segment.Frame.Visible = false
			end
		end
		-- yeux tournés vers la direction
		local head = getSegment(1)
		local d = Logic.Directions[sim.Dir]
		local fx, fy = d[1], d[2]
		local sx, sy = -fy, fx -- perpendiculaire
		for side = 1, 2 do
			local sign = side == 1 and -1 or 1
			local eye = head.Eyes[side]
			eye.Eye.Position = UDim2.fromScale(0.5 + fx * 0.14 + sx * 0.22 * sign, 0.5 + fy * 0.14 + sy * 0.22 * sign)
			eye.Pupil.Position = UDim2.fromScale(0.5 + fx * 0.18, 0.5 + fy * 0.18)
			local blush = head.Blush[side]
			blush.Position = UDim2.fromScale(0.5 - fx * 0.12 + sx * 0.34 * sign, 0.5 - fy * 0.12 + sy * 0.34 * sign)
		end
	end

	local function placeFood()
		local sim = st.Sim
		if not sim.Food then
			food.Visible = false
			return
		end
		local x, y = cellXY(sim.Food)
		food.Position = UDim2.fromScale((x + 0.5) / st.Cols, (y + 0.5) / st.Rows)
		food.Size = UDim2.fromScale(0.95 / st.Cols, 0.95 / st.Rows)
		food.Text = FRUITS[sim.Score % #FRUITS + 1]
		food.Visible = true
		foodScale.Scale = 0.2
		Kit.Tween(foodScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- Position interpolée des anneaux
	local function drawSnake(alpha: number)
		local sim = st.Sim
		if not sim then
			return
		end
		for index, cell in ipairs(sim.Body) do
			local segment = segments[index]
			if segment then
				local x, y = cellXY(cell)
				local prev = st.Prev[index] or cell
				local px, py = cellXY(prev)
				if math.abs(px - x) > 1 or math.abs(py - y) > 1 then
					px, py = x, y -- traversée d'un bord : pas d'interpolation
				end
				local ix = px + (x - px) * alpha
				local iy = py + (y - py) * alpha
				segment.Frame.Position = UDim2.fromScale((ix + 0.5) / st.Cols, (iy + 0.5) / st.Rows)
			end
		end
	end

	----------------------------------------------------------------------
	-- Commandes
	----------------------------------------------------------------------
	local function steer(dir: number)
		if not st.Running then
			return
		end
		local last = st.Queue[#st.Queue] or (st.Sim and st.Sim.Dir)
		if dir == last or (last and (dir - last) % 4 == 2) then
			return
		end
		if #st.Queue < 2 then
			table.insert(st.Queue, dir)
		end
	end

	kit:OnKey(function(key)
		local dir = Kit.KeyDirections[key]
		if dir then
			steer(dir)
		end
	end)
	kit:OnSwipe(board, steer)

	-- Croix directionnelle (écrans tactiles)
	if kit.Touch then
		local pad = create("Frame", {
			Name = "DPad",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(DPAD_WIDTH - 12, DPAD_WIDTH - 12),
			BackgroundColor3 = C.CardDark,
			BackgroundTransparency = 0.3,
			ZIndex = 3,
			Parent = kit.Area,
		})
		Kit.Corner(pad, UDim.new(1, 0))
		Kit.Stroke(pad, kit.Accent, 1.5, 0.5)
		-- Flèches DESSINÉES (triangles) : les polices Roblox n'ont pas ▲ ▶ ▼ ◀
		local ARROW_KINDS = { "Up", "Right", "Down", "Left" }
		local arrows = { { 0.5, 0.17 }, { 0.83, 0.5 }, { 0.5, 0.83 }, { 0.17, 0.5 } }
		for dir, info in ipairs(arrows) do
			local button = Kit.Button({
				Name = "Dir" .. dir,
				Text = "",
				Color = kit.Accent,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(info[1], info[2]),
				Size = UDim2.fromScale(0.34, 0.34),
				Radius = 12,
				MaxTextSize = 22,
				ZIndex = 4,
				Parent = pad,
			})
			UIUtil.Icon(ARROW_KINDS[dir], { Name = "Arrow", Size = 18, Color = C.White, ZIndex = 5, Parent = button })
			button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					steer(dir)
				end
			end)
		end
	end

	----------------------------------------------------------------------
	-- Partie
	----------------------------------------------------------------------
	kit:UseRating(0)
	local function refreshHud()
		local sim = st.Sim
		local score = sim and sim.Score or 0
		kit:SetStat("Primary", "🍓 " .. tostring(score))
		if st.Rules then
			kit:SetStat("A", kit:NextStarText(score, st.Rules.Thresholds))
			kit:SetRatingFromScore(score, st.Rules.Thresholds)
		end
		kit:SetStat("B", Kit.FormatClock(st.Clock))
	end

	local function die(generation: number)
		st.Running = false
		kit:Sound("Thunder")
		kit:Shake(board, 8)
		kit:Mood("😵", T("Bonk! Watch your tail."))
		local head = segments[1]
		if head then
			head.Frame.BackgroundColor3 = C.Red
		end
		local sim = st.Sim
		local token = st.Token
		local turns = table.clone(st.Turns)
		task.spawn(function()
			local ok, result = kit:Invoke("solo:finish", { Token = token, Turns = turns, Ticks = sim.Tick })
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			if not ok or type(result) ~= "table" then
				kit:Notify(type(result) == "string" and result or T("Something went wrong"), C.Red)
				kit:ShowPicker()
				return
			end
			task.wait(0.9)
			if generation == st.Generation then
				kit:ShowResult(result)
			end
		end)
	end

	local function tick(generation: number)
		local sim = st.Sim
		-- virage en attente
		local dir = table.remove(st.Queue, 1)
		if dir and Logic.SnakeTurn(sim, dir) then
			table.insert(st.Turns, sim.Tick + 1)
			table.insert(st.Turns, dir)
		end
		st.Prev = table.clone(sim.Body)
		-- l'anneau ajouté en mangeant part de la queue
		local event = Logic.SnakeStep(sim)
		st.Interval = Logic.SnakeInterval(st.Rules, sim.Score)
		if event == "dead" then
			if sim.Full then
				kit:Mood("🏆", T("The board is full. Legendary!"))
			end
			drawSnake(1)
			die(generation)
			return
		end
		if #st.Prev < #sim.Body then
			table.insert(st.Prev, st.Prev[#st.Prev])
		end
		styleSnake()
		if event == "eat" then
			kit:Burst(food, C.Pink, 8)
			kit:Float(food, "+1", C.Yellow)
			kit:Sound("Pop", 1 + math.min(sim.Score, 20) * 0.02)
			placeFood()
			kit:SetStat("Primary", "🍓 " .. tostring(sim.Score), true)
			refreshHud()
			local rules = st.Rules
			for index, threshold in ipairs(rules.Thresholds) do
				if sim.Score == threshold then
					kit:Mood("🤩", T("%d ⭐ unlocked!", index))
					kit:Sound("Bonus")
				end
			end
		end
	end

	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Rules = rules
		st.Cols, st.Rows = rules.Cols, rules.Rows
		st.Running = false
		st.Queue = {}
		st.Turns = {}
		st.Clock = 0
		st.Acc = 0
		st.Token = nil
		aspect.AspectRatio = st.Cols / st.Rows
		buildTiles()
		-- aperçu (graine locale) en attendant la vraie graine du serveur
		st.Sim = Logic.SnakeNew(1, rules)
		st.Prev = table.clone(st.Sim.Body)
		st.Interval = Logic.SnakeInterval(rules, 0)
		styleSnake()
		drawSnake(1)
		food.Visible = false
		refreshHud()
		kit:Mood("😊", rules.Wrap and T("No walls here: slide through the edges!") or T("Eat snacks, avoid walls and your tail."))
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
			st.Sim = Logic.SnakeNew(reply.Seed, rules)
			st.Prev = table.clone(st.Sim.Body)
			styleSnake()
			drawSnake(1)
			placeFood()
		end)
		kit:Countdown(function()
			local waited = 0
			while not st.Token and waited < 5 and generation == st.Generation do
				waited += task.wait(0.1)
			end
			if not st.Token or generation ~= st.Generation then
				return
			end
			st.Running = true
			st.Acc = 0
		end)
	end

	-- Boucle : pas de simulation + interpolation + fruit qui danse
	local hudTimer = 0
	kit:OnFrame(function(dt)
		foodTime += dt
		if food.Visible then
			food.Rotation = math.sin(foodTime * 4) * 10
		end
		if not st.Running then
			return
		end
		st.Clock += dt
		st.Acc += dt
		local generation = st.Generation
		local steps = 0
		while st.Running and st.Acc >= st.Interval and steps < 4 do
			st.Acc -= st.Interval
			steps += 1
			tick(generation)
		end
		if st.Running then
			drawSnake(math.clamp(st.Acc / st.Interval, 0, 1))
		end
		hudTimer += dt
		if hudTimer >= 0.25 then
			hudTimer = 0
			kit:SetStat("B", Kit.FormatClock(st.Clock))
		end
	end)

	-- Premier affichage
	local preview = Logic.Games.Snake.Difficulties.Normal
	st.Rules = preview
	st.Cols, st.Rows = preview.Cols, preview.Rows
	aspect.AspectRatio = st.Cols / st.Rows
	buildTiles()
	st.Sim = Logic.SnakeNew(3, preview)
	st.Prev = table.clone(st.Sim.Body)
	styleSnake()
	drawSnake(1)
	placeFood()
	refreshHud()
	kit:Mood("😊", T("Eat snacks, avoid walls and your tail."), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			st.Running = false
			kit:Destroy()
		end,
	}
end

return Module
