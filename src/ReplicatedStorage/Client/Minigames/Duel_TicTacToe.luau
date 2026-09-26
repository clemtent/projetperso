--[[
	Duel_TicTacToe (ModuleScript) — ⭕ Morpion en duel
	Emplacement : ReplicatedStorage > Client > Minigames > Duel_TicTacToe

	Plateau néon 3 x 3 : la place 1 joue ✕ (rose), la place 2 joue ◯ (cyan).
	Le client envoie seulement la case choisie (api.Move) ; le serveur vérifie
	le tour, la case libre et la victoire, puis renvoie l'état (duelUpdate).
	Aperçu immédiat du coup (semi-transparent) en attendant la réponse.
]]

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Kit = require(script.Parent.DuelKit)

local Game = { Id = "TicTacToe", Kind = "Duel" }

local WHITE = Color3.new(1, 1, 1)
local CELL = Color3.fromRGB(44, 30, 92)
local CELL_HOVER = Color3.fromRGB(64, 46, 128)

function Game.Build(container: Frame, api)
	local T = api.T
	local colors = api.Colors
	local seatColors = api.SeatColors or { colors.Pink, colors.Cyan }
	local duel = api.Duel
	local you = api.Seat or 1
	local connections = {}
	local pulses = {}
	local pending: number? = nil

	local banner = Kit.Banner(container, 30)

	-- Plateau carré centré sous le bandeau
	local area = UIUtil.Create("Frame", {
		Name = "Area",
		Size = UDim2.new(1, -40, 1, -70),
		Position = UDim2.fromOffset(20, 56),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = container,
	})
	local board = UIUtil.Create("Frame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(28, 18, 60),
		ZIndex = 22,
		Parent = area,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = board })
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(360, 360), Parent = board })
	UIUtil.Corner(board, 20)
	local boardStroke = UIUtil.Stroke(board, colors.Purple, 2.5, 0.1)
	UIUtil.Create("UIGradient", { Color = ColorSequence.new(seatColors[1], seatColors[2]), Rotation = 45, Parent = boardStroke })
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0.035, 0), PaddingRight = UDim.new(0.035, 0),
		PaddingTop = UDim.new(0.035, 0), PaddingBottom = UDim.new(0.035, 0),
		Parent = board,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 1 / 3, -8),
		CellPadding = UDim2.new(0, 12, 0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = board,
	})

	-- Marques : ✕ = deux barres croisées, ◯ = anneau
	local function drawMark(cell: GuiObject, seat: number, ghost: boolean)
		local old = cell:FindFirstChild("Mark")
		if old then
			old:Destroy()
		end
		local color = seatColors[seat]
		local mark = UIUtil.Create("Frame", {
			Name = "Mark",
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 25,
			Parent = cell,
		})
		local alpha = ghost and 0.55 or 0
		if seat == 1 then
			for _, rotation in ipairs({ 45, -45 }) do
				local bar = UIUtil.Create("Frame", {
					Size = UDim2.new(1.2, 0, 0.2, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Rotation = rotation,
					BackgroundColor3 = color,
					BackgroundTransparency = alpha,
					ZIndex = 26,
					Parent = mark,
				})
				UIUtil.Corner(bar, UDim.new(1, 0))
				UIUtil.Stroke(bar, color:Lerp(WHITE, 0.55), 2, math.max(alpha, 0.2))
			end
		else
			local ring = UIUtil.Create("Frame", {
				Size = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 26,
				Parent = mark,
			})
			UIUtil.Corner(ring, UDim.new(1, 0))
			local stroke = UIUtil.Stroke(ring, color, 12, alpha)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local inner = UIUtil.Create("Frame", {
				Size = UDim2.fromScale(0.62, 0.62),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 27,
				Parent = ring,
			})
			UIUtil.Corner(inner, UDim.new(1, 0))
			UIUtil.Stroke(inner, color:Lerp(WHITE, 0.55), 2, math.max(alpha, 0.35))
		end
		local scale = UIUtil.Create("UIScale", { Scale = 0.3, Parent = mark })
		UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		return mark
	end

	local cells = {}
	local shown = table.create(9, 0) -- marques déjà dessinées (confirmées)

	local function myTurn(): boolean
		return duel and not duel.Over and duel.Phase == "play" and duel.Turn == you
	end

	for index = 1, 9 do
		local cell = UIUtil.Create("TextButton", {
			Name = "Cell" .. index,
			BackgroundColor3 = CELL,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			ZIndex = 23,
			Parent = board,
		})
		UIUtil.Corner(cell, 16)
		UIUtil.Stroke(cell, Color3.fromRGB(110, 84, 200), 1.5, 0.45)
		UIUtil.Gradient(cell, ColorSequence.new(WHITE, Color3.fromRGB(200, 196, 230)), 90)
		cells[index] = cell
		table.insert(connections, cell.MouseEnter:Connect(function()
			if myTurn() and duel.Board[index] == 0 and not pending then
				cell.BackgroundColor3 = CELL_HOVER
			end
		end))
		table.insert(connections, cell.MouseLeave:Connect(function()
			cell.BackgroundColor3 = CELL
		end))
		table.insert(connections, cell.Activated:Connect(function()
			if not myTurn() or duel.Board[index] ~= 0 or pending then
				api.Sounds.Play("Error", 0.8)
				UIUtil.Shake(cell)
				return
			end
			pending = index
			cell.BackgroundColor3 = CELL
			local ghost = drawMark(cell, you, true)
			api.Sounds.Play("Pop", 1.2)
			task.spawn(function()
				local ok, message = api.Move(index)
				if pending == index then
					pending = nil
				end
				if not ok then
					if ghost.Parent then
						ghost:Destroy()
					end
					if type(message) == "string" then
						api.Notify(message, colors.Red)
					end
				end
			end)
		end))
	end

	-- Dessine l'état reçu du serveur
	local function render(state, kind: string?)
		duel = state
		local marks = state.Board or {}
		for index = 1, 9 do
			local seat = marks[index] or 0
			local cell = cells[index]
			if seat ~= shown[index] then
				shown[index] = seat
				if seat ~= 0 then
					drawMark(cell, seat, false)
					if index == state.Last and seat ~= you then
						api.Sounds.Play("Pop", 0.95)
					end
				else
					local mark = cell:FindFirstChild("Mark")
					if mark then
						mark:Destroy()
					end
				end
			end
		end
		-- Ligne gagnante
		if state.Line then
			local winners = {}
			for _, index in ipairs(state.Line) do
				winners[index] = true
			end
			local color = seatColors[state.Winner] or colors.Yellow
			for index, cell in ipairs(cells) do
				if winners[index] then
					cell.BackgroundColor3 = color:Lerp(CELL, 0.45)
					local stroke = cell:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = color:Lerp(WHITE, 0.3)
						stroke.Transparency = 0
						stroke.Thickness = 3
						table.insert(pulses, Kit.Pulse(stroke, { Transparency = 0.6 }, 0.45))
					end
				else
					cell.BackgroundTransparency = 0.45
				end
			end
		end
		-- Bandeau
		if state.Over then
			if state.Winner == you then
				banner.Set(T("🏆 You win!"), colors.Yellow, kind == "duelEnd")
			elseif state.Winner == 0 then
				banner.Set(T("🤝 Draw!"), colors.Cyan, kind == "duelEnd")
			else
				banner.Set(T("💔 You lose..."), colors.Red, kind == "duelEnd")
			end
		elseif state.Turn == you then
			banner.Set(T("Your turn! Tap a square"), seatColors[you], true)
		else
			local other = state.Players and state.Players[3 - you]
			banner.Set(T("%s is thinking...", other and other.Name or "?"), seatColors[3 - you], false)
		end
	end

	render(duel, "duelStart")
	table.insert(connections, Kit.Track(api, render))

	return {
		Destroy = function()
			for _, tween in ipairs(pulses) do
				tween:Cancel()
			end
			UIUtil.DisconnectAll(connections)
			area:Destroy()
			banner.Frame:Destroy()
		end,
	}
end

return Game
