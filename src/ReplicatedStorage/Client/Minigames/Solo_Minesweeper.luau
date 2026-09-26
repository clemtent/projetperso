--[[
	Solo_Minesweeper (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Minesweeper

	💣 Démineur de l'arcade. Le SERVEUR génère le plateau au premier clic
	(premier clic toujours sûr) et révèle les cases : le client ne connaît
	jamais les mines avant la fin de la partie.
	Commandes : clic / toucher = creuser ; clic droit, appui long ou mode
	🚩 = drapeau ; clic sur un chiffre entouré de ses drapeaux = ouvre les
	voisines ("accord") ; touche F = mode drapeau.
]]

local Kit = require(script.Parent.Solo_Kit)
local Logic = Kit.Logic
local C = Kit.Colors
local create = Kit.Create

local NUMBER_COLORS = {
	Color3.fromRGB(110, 205, 255),
	Color3.fromRGB(110, 240, 160),
	Color3.fromRGB(255, 120, 190),
	Color3.fromRGB(190, 150, 255),
	Color3.fromRGB(255, 170, 90),
	Color3.fromRGB(90, 230, 220),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(200, 200, 215),
}
local HIDDEN_A = Color3.fromRGB(176, 146, 255)
local HIDDEN_B = Color3.fromRGB(160, 128, 248)
local OPEN_COLOR = Color3.fromRGB(34, 22, 74)

local Module = { Id = "Minesweeper", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local st = {
		Cols = 8,
		Rows = 8,
		Mines = 10,
		State = {} :: { [number]: number }, -- 0 cachée, 1 ouverte, 2 drapeau
		Numbers = {} :: { [number]: number },
		Flags = 0,
		Token = nil,
		Done = true,
		Started = nil :: number?,
		Clock = 0,
		FlagMode = false,
		Queue = {} :: { any },
		QueueTime = 0,
		Generation = 0,
	}
	local cells = {} -- pool de cases (réutilisées d'une partie à l'autre)

	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	kit = Kit.new(container, api, {
		Id = "Minesweeper",
		Primary = "Mines left",
		SmallA = "Stars",
		SmallB = "Time",
		Help = "",
		Details = function(_, rules)
			return string.format("%d × %d  ·  %d 💣", rules.Cols, rules.Rows, rules.Mines)
				.. "\n" .. T("⭐⭐⭐ under %s", Kit.FormatClock(rules.Fast))
				.. "\n" .. T("⭐⭐ under %s", Kit.FormatClock(rules.Ok))
		end,
		BestText = Kit.FormatTime,
		ScoreText = function(result)
			if result.Won or result.Rejected then
				return "⏱️ " .. Kit.FormatTime(tonumber(result.Score) or 0)
			end
			return T("Boom! A mine woke up 💥")
		end,
		NoStarHint = function()
			return T("Tip: numbers tell how many mines touch the cell.")
		end,
		OnPlay = function(difficulty)
			startGame(difficulty)
		end,
		OnPicker = function()
			st.Done = true
		end,
		QuitArg = function()
			return {}
		end,
	})
	kit.PickerHelp.Text = kit.Touch and T("Tap to dig · Hold or use 🚩 to flag") or T("Click to dig · Right-click to flag · F = flag mode")

	----------------------------------------------------------------------
	-- Plateau
	----------------------------------------------------------------------
	local board = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.CardDark,
		ZIndex = 3,
		Parent = kit.Area,
	})
	Kit.Corner(board, 14)
	Kit.Stroke(board, kit.Accent, 2, 0.35)
	local aspect = create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = board })
	local grid = create("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = board,
	})

	-- Mode drapeau (utile au toucher)
	local flagButton = Kit.Button({
		Name = "FlagMode",
		Text = "⛏️ " .. T("Dig mode"),
		Color = C.CardLight,
		Size = UDim2.new(1, 0, 0, 40),
		MaxTextSize = 17,
		ZIndex = 3,
		Parent = kit.Extra,
	})
	local function refreshFlagButton()
		flagButton.Text = st.FlagMode and ("🚩 " .. T("Flag mode")) or ("⛏️ " .. T("Dig mode"))
		local color = st.FlagMode and C.Red or C.CardLight
		flagButton.BackgroundColor3 = color
		local g = flagButton:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(color:Lerp(C.White, 0.28), color:Lerp(C.Black, 0.12))
		end
	end
	flagButton.Activated:Connect(function()
		st.FlagMode = not st.FlagMode
		kit:Sound("Click")
		refreshFlagButton()
		kit:Mood(st.FlagMode and "🚩" or "😊", st.FlagMode and T("Flag mode: taps place flags.") or T("Dig mode: taps open cells."))
	end)

	----------------------------------------------------------------------
	-- Cases
	----------------------------------------------------------------------
	local onPrimary, toggleFlag

	local function paintCell(index: number)
		local cell = cells[index]
		if not cell then
			return
		end
		local state = st.State[index] or 0
		local x = (index - 1) % st.Cols
		local y = (index - 1) // st.Cols
		if state == 1 then
			local n = st.Numbers[index] or 0
			cell.Tile.BackgroundColor3 = OPEN_COLOR
			cell.Tile.BackgroundTransparency = (x + y) % 2 == 0 and 0.05 or 0.25
			cell.Gradient.Enabled = false
			cell.Stroke.Transparency = 0.85
			cell.Text.Text = n > 0 and tostring(n) or ""
			cell.Text.TextColor3 = NUMBER_COLORS[n] or C.White
		else
			cell.Tile.BackgroundColor3 = (x + y) % 2 == 0 and HIDDEN_A or HIDDEN_B
			cell.Tile.BackgroundTransparency = 0
			cell.Gradient.Enabled = true
			cell.Stroke.Transparency = 0.55
			cell.Text.Text = state == 2 and "🚩" or ""
			cell.Text.TextColor3 = C.White
		end
	end

	local function makeCell(index: number)
		local button = create("TextButton", {
			Name = "Cell" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = grid,
		})
		local tile = create("Frame", {
			Name = "Tile",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -3, 1, -3),
			BackgroundColor3 = HIDDEN_A,
			ZIndex = 5,
			Parent = button,
		})
		Kit.Corner(tile, UDim.new(0.18, 0))
		local stroke = Kit.Stroke(tile, C.White, 1, 0.55)
		local gradientObj = create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 190, 235)),
			Rotation = 90,
			Parent = tile,
		})
		local text = Kit.Label({
			Size = UDim2.fromScale(0.8, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 26,
			ZIndex = 6,
			Parent = tile,
		})
		local scale = create("UIScale", { Parent = tile })
		local cell = { Button = button, Tile = tile, Stroke = stroke, Gradient = gradientObj, Text = text, Scale = scale, Index = index }
		-- Appui long (toucher) = drapeau
		local pressId = 0
		local suppress = false
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressId += 1
				local id = pressId
				task.delay(0.42, function()
					if pressId == id and kit.Alive then
						suppress = true
						toggleFlag(cell.Index)
					end
				end)
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressId += 1
			end
		end)
		button.Activated:Connect(function()
			if suppress then
				suppress = false
				return
			end
			onPrimary(cell.Index)
		end)
		button.MouseButton2Click:Connect(function()
			toggleFlag(cell.Index)
		end)
		button.MouseEnter:Connect(function()
			if (st.State[cell.Index] or 0) ~= 1 and not st.Done then
				tile.BackgroundColor3 = tile.BackgroundColor3:Lerp(C.White, 0.18)
			end
		end)
		button.MouseLeave:Connect(function()
			paintCell(cell.Index)
		end)
		return cell
	end

	local function layout()
		local total = st.Cols * st.Rows
		aspect.AspectRatio = st.Cols / st.Rows
		for index = 1, math.max(total, #cells) do
			local cell = cells[index]
			if index <= total then
				if not cell then
					cell = makeCell(index)
					cells[index] = cell
				end
				local x = (index - 1) % st.Cols
				local y = (index - 1) // st.Cols
				cell.Button.Position = UDim2.fromScale(x / st.Cols, y / st.Rows)
				cell.Button.Size = UDim2.fromScale(1 / st.Cols, 1 / st.Rows)
				cell.Button.Visible = true
				cell.Scale.Scale = 1
				paintCell(index)
			elseif cell then
				cell.Button.Visible = false
			end
		end
	end

	local function refreshHud()
		kit:SetStat("Primary", "💣 " .. tostring(st.Mines - st.Flags))
		local rules = kit.GameRules.Difficulties[kit.Difficulty]
		local t = st.Clock
		if t <= rules.Fast then
			kit:SetStat("A", "⭐⭐⭐ " .. Kit.FormatClock(rules.Fast - t))
		elseif t <= rules.Ok then
			kit:SetStat("A", "⭐⭐ " .. Kit.FormatClock(rules.Ok - t))
		else
			kit:SetStat("A", "⭐")
		end
		kit:SetStat("B", Kit.FormatClock(t))
	end

	----------------------------------------------------------------------
	-- Partie
	----------------------------------------------------------------------
	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Cols, st.Rows, st.Mines = rules.Cols, rules.Rows, rules.Mines
		st.State = {}
		st.Numbers = {}
		st.Flags = 0
		st.Token = nil
		st.Done = false
		st.Started = nil
		st.Clock = 0
		st.Queue = {}
		st.QueueTime = 0
		layout()
		refreshHud()
		kit:Sound("Open")
		kit:Mood("😊", T("The first cell is always safe. Good luck!"))
		task.spawn(function()
			local reply = kit:StartSession()
			if generation ~= st.Generation then
				return
			end
			if not reply then
				st.Done = true
				kit:ShowPicker()
				return
			end
			st.Token = reply.Token
		end)
	end

	-- Révélation en vague (depuis la case cliquée)
	local function queueReveal(list, numbers, origin: number)
		local ox = (origin - 1) % st.Cols
		local oy = (origin - 1) // st.Cols
		for k, index in ipairs(list) do
			local x = (index - 1) % st.Cols
			local y = (index - 1) // st.Cols
			local distance = math.sqrt((x - ox) ^ 2 + (y - oy) ^ 2)
			st.Numbers[index] = numbers[k]
			if st.State[index] == 2 then
				st.Flags -= 1
			end
			st.State[index] = 1
			table.insert(st.Queue, { Index = index, At = st.QueueTime + math.min(distance * 0.022, 0.45) })
		end
	end

	local function revealMines(mines: { number }, won: boolean, boomCell: number?)
		local mineSet = {}
		for k, index in ipairs(mines) do
			mineSet[index] = true
			local cell = cells[index]
			if cell then
				task.delay((index == boomCell and 0 or 0.12 + k * 0.035), function()
					if not kit.Alive or not cell.Button.Visible then
						return
					end
					cell.Gradient.Enabled = false
					cell.Tile.BackgroundTransparency = 0
					if won then
						cell.Tile.BackgroundColor3 = Color3.fromRGB(255, 190, 225)
						cell.Text.Text = "🌸"
					else
						cell.Tile.BackgroundColor3 = index == boomCell and C.Red or Color3.fromRGB(120, 50, 110)
						cell.Text.Text = index == boomCell and "💥" or "💣"
					end
					cell.Scale.Scale = 0.4
					Kit.Tween(cell.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				end)
			end
		end
		if not won then
			-- Drapeaux mal placés
			for index, state in pairs(st.State) do
				if state == 2 and not mineSet[index] and cells[index] then
					cells[index].Text.Text = "❌"
				end
			end
		end
	end

	local function applyReply(reply, origin: number)
		if type(reply) ~= "table" then
			return
		end
		if type(reply.Cells) == "table" and type(reply.Numbers) == "table" and #reply.Cells > 0 then
			queueReveal(reply.Cells, reply.Numbers, origin)
			kit:Sound("Pop", 0.9 + math.min(#reply.Cells, 30) / 60)
			if #reply.Cells >= 12 then
				kit:Mood("🤩", T("Wow, a big opening!"))
			else
				kit:Mood("😊", nil, false)
			end
		end
		if reply.Done then
			st.Done = true
			local mines = type(reply.Mines) == "table" and reply.Mines or {}
			if reply.Boom then
				kit:Sound("Thunder")
				kit:Shake(board, 9)
				kit:Mood("😵", T("Boom! Numbers show how many mines touch a cell."))
				revealMines(mines, false, reply.Cell)
				task.delay(1.4, function()
					if kit.Alive and st.Done then
						kit:ShowResult(reply.Result)
					end
				end)
			else
				-- les drapeaux posés restent : on les compte comme trouvés
				st.Flags = st.Mines
				kit:Mood("😎", T("All clear! The mines turned into flowers."))
				refreshHud()
				task.delay(0.35, function()
					if kit.Alive then
						revealMines(mines, true, nil)
						kit:Burst(board, C.Pink, 16)
					end
				end)
				task.delay(1.3, function()
					if kit.Alive and st.Done then
						kit:ShowResult(reply.Result)
					end
				end)
			end
		end
	end

	local function send(list: { number }, origin: number)
		if st.Done or not st.Token then
			return
		end
		local token = st.Token
		local generation = st.Generation
		if not st.Started then
			st.Started = os.clock()
		end
		for _, index in ipairs(list) do
			local cell = cells[index]
			if cell then
				cell.Scale.Scale = 0.86
			end
		end
		kit:Mood("😮", nil, false)
		task.spawn(function()
			local arg = #list == 1 and { Token = token, Cell = list[1] } or { Token = token, Cells = list }
			local ok, reply = kit:Invoke("solo:move", arg)
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			for _, index in ipairs(list) do
				local cell = cells[index]
				if cell and (st.State[index] or 0) ~= 1 then
					Kit.Tween(cell.Scale, 0.15, { Scale = 1 })
				end
			end
			if not ok then
				kit:Notify(type(reply) == "string" and reply or T("Something went wrong"), C.Red)
				return
			end
			applyReply(reply, origin)
		end)
	end

	function onPrimary(index: number)
		if st.Done or not st.Token then
			return
		end
		local state = st.State[index] or 0
		if st.FlagMode and state ~= 1 then
			toggleFlag(index)
			return
		end
		if state == 2 then
			kit:Sound("Error")
			return
		end
		if state == 0 then
			send({ index }, index)
			return
		end
		-- Accord : chiffre entouré d'autant de drapeaux -> ouvre les voisines
		local number = st.Numbers[index] or 0
		if number <= 0 then
			return
		end
		local flags, hidden = 0, {}
		for _, neighbor in ipairs(Logic.Neighbors(st.Cols, st.Rows, index)) do
			local s = st.State[neighbor] or 0
			if s == 2 then
				flags += 1
			elseif s == 0 then
				table.insert(hidden, neighbor)
			end
		end
		if flags == number and #hidden > 0 then
			send(hidden, index)
		elseif #hidden > 0 then
			for _, neighbor in ipairs(hidden) do
				local cell = cells[neighbor]
				if cell then
					cell.Scale.Scale = 0.85
					Kit.Tween(cell.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			end
		end
	end

	function toggleFlag(index: number)
		if st.Done or not st.Token then
			return
		end
		local state = st.State[index] or 0
		if state == 1 then
			return
		end
		if state == 2 then
			st.State[index] = 0
			st.Flags -= 1
		else
			st.State[index] = 2
			st.Flags += 1
		end
		paintCell(index)
		local cell = cells[index]
		if cell then
			cell.Scale.Scale = 1.25
			Kit.Tween(cell.Scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		kit:Sound("Click", state == 2 and 0.9 or 1.15)
		refreshHud()
	end

	kit:OnKey(function(key)
		if key == Enum.KeyCode.F then
			st.FlagMode = not st.FlagMode
			refreshFlagButton()
			kit:Sound("Click")
		end
	end)

	-- Boucle : vague de révélation + chrono
	local hudTimer = 0
	kit:OnFrame(function(dt)
		st.QueueTime += dt
		if #st.Queue > 0 then
			local keep = {}
			for _, item in ipairs(st.Queue) do
				if item.At <= st.QueueTime then
					local cell = cells[item.Index]
					if cell then
						paintCell(item.Index)
						cell.Scale.Scale = 0.55
						Kit.Tween(cell.Scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
					end
				else
					table.insert(keep, item)
				end
			end
			st.Queue = keep
		end
		if st.Started and not st.Done then
			st.Clock = os.clock() - st.Started
		end
		hudTimer += dt
		if hudTimer >= 0.2 then
			hudTimer = 0
			refreshHud()
		end
	end)

	-- Premier affichage : plateau décoratif + choix de la difficulté
	st.Cols, st.Rows = 8, 8
	layout()
	refreshHud()
	kit:Mood("😊", kit.Touch and T("Hold a cell to flag it") or T("Right-click a cell to flag it"), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			kit:Destroy()
		end,
	}
end

return Module
