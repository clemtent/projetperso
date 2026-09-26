--[[
	Duel_Connect4 (ModuleScript) — 🔴 Puissance 4 en duel
	Emplacement : ReplicatedStorage > Client > Minigames > Duel_Connect4

	Grille 7 x 6 (ArcadeConfig.Logic) : on choisit une COLONNE, le serveur fait
	tomber le jeton (case la plus basse libre), vérifie le tour et les 4
	alignés. Jetons roses (place 1) / cyan (place 2), chute animée avec
	rebond, jeton fantôme au survol de la colonne, jetons gagnants qui brillent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Kit = require(script.Parent.DuelKit)
local ArcadeConfig = require(ReplicatedStorage.Shared.ArcadeConfig)

local Game = { Id = "Connect4", Kind = "Duel" }

local Logic = ArcadeConfig.Logic
local COLS, ROWS = Logic.C4Cols, Logic.C4Rows
local WHITE = Color3.new(1, 1, 1)
local HOLE = Color3.fromRGB(18, 10, 40)

function Game.Build(container: Frame, api)
	local T = api.T
	local colors = api.Colors
	local seatColors = api.SeatColors or { colors.Pink, colors.Cyan }
	local duel = api.Duel
	local you = api.Seat or 1
	local connections = {}
	local pulses = {}
	local pending = false

	local banner = Kit.Banner(container, 30)

	local area = UIUtil.Create("Frame", {
		Name = "Area",
		Size = UDim2.new(1, -40, 1, -64),
		Position = UDim2.fromOffset(20, 52),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = container,
	})
	-- Cadre : rangée "lanceur" (jeton fantôme) + grille bleue
	local frame = UIUtil.Create("Frame", {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = area,
	})
	-- 7 colonnes x (6 lignes + 0,8 de lanceur)
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = COLS / (ROWS + 0.8), Parent = frame })
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(470, 460), Parent = frame })
	local launcherShare = 0.8 / (ROWS + 0.8)

	local grid = UIUtil.Create("Frame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1 - launcherShare),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 24,
		Parent = frame,
	})
	UIUtil.Corner(grid, 18)
	UIUtil.Stroke(grid, Color3.fromRGB(160, 170, 255), 2.5, 0.1)
	UIUtil.Create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 110, 255), Color3.fromRGB(50, 34, 170)),
		Rotation = 90,
		Parent = grid,
	})

	-- Couche des jetons (derrière la grille : on les voit par les trous)
	local discsLayer = UIUtil.Create("Frame", {
		Name = "Discs",
		Size = UDim2.fromScale(1, 1 - launcherShare),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		ZIndex = 26,
		Parent = frame,
	})

	local cellW, cellH = 1 / COLS, 1 / ROWS
	local function cellPosition(row: number, col: number): UDim2
		return UDim2.fromScale((col - 0.5) * cellW, (row - 0.5) * cellH)
	end

	-- Trous (anneaux sombres)
	for row = 1, ROWS do
		for col = 1, COLS do
			local hole = UIUtil.Create("Frame", {
				Name = "Hole",
				Size = UDim2.fromScale(cellW * 0.78, cellH * 0.78),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = cellPosition(row, col),
				BackgroundColor3 = HOLE,
				BackgroundTransparency = 0.05,
				ZIndex = 25,
				Parent = grid,
			})
			UIUtil.Corner(hole, UDim.new(1, 0))
			UIUtil.Stroke(hole, Color3.fromRGB(30, 20, 110), 2, 0.2)
		end
	end

	local function makeDisc(parent: Instance, seat: number, ghost: boolean): Frame
		local color = seatColors[seat]
		local disc = UIUtil.Create("Frame", {
			Name = "Disc",
			Size = UDim2.fromScale(cellW * 0.74, cellH * 0.74),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = ghost and 0.5 or 0,
			ZIndex = 27,
			Parent = parent,
		})
		UIUtil.Corner(disc, UDim.new(1, 0))
		UIUtil.Stroke(disc, color:Lerp(WHITE, 0.5), 2, ghost and 0.5 or 0.1)
		UIUtil.Create("UIGradient", {
			Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color:Lerp(Color3.new(0, 0, 0), 0.15)),
			Rotation = 60,
			Parent = disc,
		})
		local shine = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(0.32, 0.18),
			Position = UDim2.fromScale(0.22, 0.16),
			Rotation = -25,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = ghost and 0.8 or 0.45,
			ZIndex = 28,
			Parent = disc,
		})
		UIUtil.Corner(shine, UDim.new(1, 0))
		return disc
	end

	-- Jeton fantôme au-dessus de la colonne survolée
	local launcher = UIUtil.Create("Frame", {
		Name = "Launcher",
		Size = UDim2.fromScale(1, launcherShare),
		BackgroundTransparency = 1,
		ZIndex = 26,
		Parent = frame,
	})
	local ghost = makeDisc(launcher, you, true)
	ghost.Size = UDim2.fromScale(cellW * 0.7, 0.9)
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = ghost })
	ghost.Position = UDim2.fromScale(0.5 * cellW, 0.5)
	ghost.Visible = false
	local arrow = Kit.Label({ Text = "▼", TextSize = 16, Color = seatColors[you], Size = UDim2.fromOffset(20, 16),
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 1), ZIndex = 29, Parent = ghost })
	arrow.TextTransparency = 0.1

	local discs = {} -- [index] = Frame
	local function myTurn(): boolean
		return duel and not duel.Over and duel.Phase == "play" and duel.Turn == you
	end

	local hoverCol: number? = nil
	local function showGhost(col: number?)
		hoverCol = col
		if col and myTurn() and not pending then
			ghost.Visible = true
			ghost.Position = UDim2.fromScale((col - 0.5) * cellW, 0.5)
		else
			ghost.Visible = false
		end
	end

	-- Chute d'un jeton : de la rangée du lanceur jusqu'à sa case
	local function dropDisc(index: number, seat: number, animate: boolean)
		local row = math.floor((index - 1) / COLS) + 1
		local col = (index - 1) % COLS + 1
		local disc = makeDisc(discsLayer, seat, false)
		disc.Name = "Disc" .. index
		local target = cellPosition(row, col)
		if animate then
			disc.Position = UDim2.fromScale((col - 0.5) * cellW, -0.5 * cellH)
			UIUtil.Tween(disc, 0.25 + row * 0.06, { Position = target }, Enum.EasingStyle.Bounce)
		else
			disc.Position = target
		end
		discs[index] = disc
	end

	-- Colonnes cliquables (au-dessus de tout, transparentes)
	for col = 1, COLS do
		local button = UIUtil.Create("TextButton", {
			Name = "Col" .. col,
			Size = UDim2.fromScale(cellW, 1),
			Position = UDim2.fromScale((col - 1) * cellW, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 35,
			Parent = frame,
		})
		table.insert(connections, button.MouseEnter:Connect(function()
			showGhost(col)
			if myTurn() then
				button.BackgroundTransparency = 0.93
			end
		end))
		table.insert(connections, button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
			if hoverCol == col then
				showGhost(nil)
			end
		end))
		table.insert(connections, button.Activated:Connect(function()
			if not myTurn() or pending then
				api.Sounds.Play("Error", 0.8)
				return
			end
			if not Logic.C4Drop(duel.Board, col) then
				api.Sounds.Play("Error", 0.8)
				UIUtil.Shake(button)
				return
			end
			pending = true
			ghost.Visible = false
			api.Sounds.Play("Pop", 1.15)
			task.spawn(function()
				local ok, message = api.Move(col)
				pending = false
				if not ok and type(message) == "string" then
					api.Notify(message, colors.Red)
				end
			end)
		end))
	end

	local function render(state, kind: string?)
		duel = state
		local board = state.Board or {}
		for index = 1, COLS * ROWS do
			local seat = board[index] or 0
			if seat ~= 0 and not discs[index] then
				dropDisc(index, seat, kind ~= "duelStart")
				if index == state.Last and seat ~= you then
					api.Sounds.Play("Pop", 0.9)
				end
			end
		end
		if state.Line then
			local winners = {}
			for _, index in ipairs(state.Line) do
				winners[index] = true
				local disc = discs[index]
				if disc then
					local stroke = disc:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = WHITE
						stroke.Thickness = 4
						stroke.Transparency = 0
						table.insert(pulses, Kit.Pulse(stroke, { Transparency = 0.7 }, 0.4))
					end
				end
			end
			for index, disc in pairs(discs) do
				if not winners[index] then
					disc.BackgroundTransparency = 0.45
				end
			end
		end
		showGhost(hoverCol)
		if state.Over then
			if state.Winner == you then
				banner.Set(T("🏆 Four in a row! You win!"), colors.Yellow, kind == "duelEnd")
			elseif state.Winner == 0 then
				banner.Set(T("🤝 Draw!"), colors.Cyan, kind == "duelEnd")
			else
				banner.Set(T("💔 You lose..."), colors.Red, kind == "duelEnd")
			end
		elseif state.Turn == you then
			banner.Set(T("Your turn! Pick a column"), seatColors[you], true)
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
