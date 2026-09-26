--[[
	Duel_SpotRace (ModuleScript) — 🔎 Course "Trouve l'intrus"
	Emplacement : ReplicatedStorage > Client > Minigames > Duel_SpotRace

	Les deux joueurs voient la MÊME grille d'emojis (envoyée par le serveur) :
	un seul est différent. Le premier qui le touche marque le point. Une
	erreur bloque le joueur un court instant (vérifié par le serveur). Les
	grilles grandissent (4x4, 5x5, 6x6). Premier à WinScore points.
	Les cases sont réutilisées d'une manche à l'autre (pas de recréation).
]]

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Kit = require(script.Parent.DuelKit)

local Game = { Id = "SpotRace", Kind = "Duel" }

local WHITE = Color3.new(1, 1, 1)
local CELL = Color3.fromRGB(48, 34, 100)
local MAX_SIZE = 6

function Game.Build(container: Frame, api)
	local T = api.T
	local colors = api.Colors
	local seatColors = api.SeatColors or { colors.Pink, colors.Cyan }
	local duel = api.Duel
	local you = api.Seat or 1
	local connections = {}
	local lockedUntil = 0
	local lastKey = ""

	local banner = Kit.Banner(container, 30)
	local countdown = Kit.Countdown(container, 45)

	local area = UIUtil.Create("Frame", {
		Name = "Area",
		Size = UDim2.new(1, -40, 1, -92),
		Position = UDim2.fromOffset(20, 52),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = container,
	})
	local board = UIUtil.Create("Frame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(26, 16, 56),
		ZIndex = 22,
		Parent = area,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = board })
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(380, 380), Parent = board })
	UIUtil.Corner(board, 18)
	local boardStroke = UIUtil.Stroke(board, colors.Green, 2.5, 0.15)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
		PaddingTop = UDim.new(0.03, 0), PaddingBottom = UDim.new(0.03, 0),
		Parent = board,
	})
	local gridLayout = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0.25, -6),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = board,
	})
	-- Voile "bloqué" après une erreur
	local lock = UIUtil.Create("TextLabel", {
		Name = "Lock",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(60, 10, 30),
		BackgroundTransparency = 0.35,
		Font = Theme.Fonts.Number,
		Text = "🔒",
		TextColor3 = WHITE,
		TextSize = 48,
		Visible = false,
		ZIndex = 40,
		Parent = area,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = lock })
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(380, 380), Parent = lock })
	UIUtil.Corner(lock, 18)

	local info = Kit.Label({ Text = "", TextSize = 15, Color = colors.TextDim, Size = UDim2.new(1, -40, 0, 22),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), ZIndex = 30, Parent = container })

	-- Réserve de 36 cases (6 x 6), seules Size x Size sont visibles
	local cells = {}
	local function onCell(index: number)
		if not duel or duel.Over or duel.Phase ~= "play" then
			return
		end
		local now = os.clock()
		if now < lockedUntil then
			api.Sounds.Play("Error", 0.7)
			return
		end
		local cell = cells[index]
		api.Sounds.Play("Click", 1.3)
		task.spawn(function()
			local ok, result = api.Move(index)
			if type(result) == "table" and (result.Wrong or result.Locked) then
				local seconds = tonumber(result.Locked) or 1
				lockedUntil = os.clock() + seconds
				api.Sounds.Play("Error", 0.8)
				cell.BackgroundColor3 = colors.Red
				UIUtil.Shake(cell)
				lock.Visible = true
				lock.Text = "🔒"
				task.delay(seconds, function()
					if os.clock() >= lockedUntil - 0.01 then
						lock.Visible = false
						if cell.Parent then
							cell.BackgroundColor3 = CELL
						end
					end
				end)
			elseif ok and type(result) == "table" and result.Found then
				api.Sounds.Play("Bonus", 1.2)
			end
		end)
	end
	for index = 1, MAX_SIZE * MAX_SIZE do
		local cell = UIUtil.Create("TextButton", {
			Name = "Cell" .. index,
			BackgroundColor3 = CELL,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = "",
			TextScaled = true,
			TextColor3 = WHITE,
			LayoutOrder = index,
			Visible = false,
			ZIndex = 24,
			Parent = board,
		})
		UIUtil.Corner(cell, 10)
		UIUtil.Stroke(cell, Color3.fromRGB(120, 100, 210), 1.5, 0.55)
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0.14, 0), PaddingRight = UDim.new(0.14, 0),
			PaddingTop = UDim.new(0.14, 0), PaddingBottom = UDim.new(0.14, 0),
			Parent = cell,
		})
		cells[index] = cell
		table.insert(connections, cell.Activated:Connect(function()
			onCell(index)
		end))
	end

	local function resetCells(size: number)
		gridLayout.CellSize = UDim2.new(1 / size, -6, 1 / size, -6)
		for index, cell in ipairs(cells) do
			cell.Visible = index <= size * size
			cell.BackgroundColor3 = CELL
			cell.TextTransparency = 0
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Color3.fromRGB(120, 100, 210)
				stroke.Thickness = 1.5
				stroke.Transparency = 0.55
			end
		end
	end

	local function nameOf(seat: number): string
		if seat == you then
			return T("You")
		end
		local other = duel.Players and duel.Players[seat]
		return other and other.Name or "?"
	end

	local function render(state, kind: string?)
		duel = state
		local phase = state.Phase or ""
		local round = state.Round or 0
		local key = phase .. ":" .. round
		local changed = key ~= lastKey
		lastKey = key
		local winScore = state.WinScore or 4
		info.Text = round > 0 and T("Round %d • first to %d finds", round, winScore) or T("First to %d finds", winScore)

		if phase == "intro" then
			resetCells(4)
			for index = 1, 16 do
				cells[index].Text = "❔"
				cells[index].TextTransparency = 0.5
			end
			banner.Set(T("Find the odd emoji before your rival!"), colors.Green, false)
			if changed then
				countdown.Run(state.PhaseLeft or 3, api.Sounds.Play)
			end
		elseif phase == "play" and state.Grid then
			if changed then
				countdown.Hide()
				lock.Visible = false
				lockedUntil = 0
				local grid = state.Grid
				resetCells(grid.Size)
				for index, emoji in ipairs(grid.Cells) do
					local cell = cells[index]
					if cell then
						cell.Text = emoji
					end
				end
				board.Size = UDim2.fromScale(0.92, 0.92)
				UIUtil.Tween(board, 0.25, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
				api.Sounds.Play("Pop", 1)
			end
			banner.Set(T("Find the odd one out!"), colors.Green, changed)
			boardStroke.Color = colors.Green
		elseif phase == "result" then
			local result = state.RoundResult or {}
			local winner = result.Winner or 0
			local odd = result.Odd
			if odd and cells[odd] then
				local color = winner == 0 and colors.Yellow or seatColors[winner]
				local cell = cells[odd]
				cell.BackgroundColor3 = color:Lerp(CELL, 0.35)
				local stroke = cell:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = WHITE
					stroke.Thickness = 3
					stroke.Transparency = 0
				end
				if changed then
					UIUtil.Pop(cell, 1.4, 0.4)
				end
				for index, other in ipairs(cells) do
					if index ~= odd then
						other.TextTransparency = 0.6
					end
				end
			end
			lock.Visible = false
			if result.Void then
				banner.Set(T("Time's up! Here it was"), colors.Yellow, changed)
			elseif winner == you then
				banner.Set(T("Found it! +1 point (%ss)", tostring(result.Time or "?")), colors.Green, changed)
				if changed then
					api.Sounds.Play("Bonus", 1.25)
				end
			else
				banner.Set(T("%s was faster!", nameOf(winner)), seatColors[winner] or colors.Red, changed)
				if changed then
					api.Sounds.Play("Error", 0.8)
				end
			end
			boardStroke.Color = winner == 0 and colors.Yellow or (seatColors[winner] or colors.Green)
		end
		if state.Over then
			countdown.Hide()
			lock.Visible = false
			local won = state.Winner == you
			banner.Set(won and T("🏆 Eagle eyes! You win!") or (state.Winner == 0 and T("🤝 Draw!") or T("💔 You lose...")),
				won and colors.Yellow or colors.Red, kind == "duelEnd")
		end
	end

	render(duel, "duelStart")
	table.insert(connections, Kit.Track(api, render))

	return {
		Destroy = function()
			countdown.Hide()
			UIUtil.DisconnectAll(connections)
			area:Destroy()
			info:Destroy()
			banner.Frame:Destroy()
		end,
	}
end

return Game
