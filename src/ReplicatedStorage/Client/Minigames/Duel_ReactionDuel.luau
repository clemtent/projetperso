--[[
	Duel_ReactionDuel (ModuleScript) — ⚡ Duel de réflexes
	Emplacement : ReplicatedStorage > Client > Minigames > Duel_ReactionDuel

	Un gros bouton rond : "Attends..." (violet) puis "TAPE !" (vert) quand le
	SERVEUR donne le départ. Le premier qui tape gagne la manche (le serveur
	mesure le temps et compense la latence) ; taper trop tôt = faux départ, le
	point va à l'adversaire. Premier à ArcadeConfig WinScore points.
	Clavier : barre d'espace (ordinateur).
]]

local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Kit = require(script.Parent.DuelKit)

local Game = { Id = "ReactionDuel", Kind = "Duel" }

local WHITE = Color3.new(1, 1, 1)
local WAIT_COLOR = Color3.fromRGB(120, 60, 220)
local GO_COLOR = Color3.fromRGB(60, 225, 120)
local IDLE_COLOR = Color3.fromRGB(70, 56, 130)

function Game.Build(container: Frame, api)
	local T = api.T
	local colors = api.Colors
	local seatColors = api.SeatColors or { colors.Pink, colors.Cyan }
	local duel = api.Duel
	local you = api.Seat or 1
	local connections = {}
	local tapped = false
	local lastRound = -1
	local lastPhase = ""
	local goAt = 0

	local banner = Kit.Banner(container, 30)
	local countdown = Kit.Countdown(container, 45)

	local area = UIUtil.Create("Frame", {
		Name = "Area",
		Size = UDim2.new(1, -40, 1, -110),
		Position = UDim2.fromOffset(20, 52),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = container,
	})
	-- Support carré (halo + gros bouton rond, frères : le bouton reste au-dessus du halo)
	local holder = UIUtil.Create("Frame", {
		Name = "PadHolder",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = area,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(250, 250), Parent = holder })
	local halo = UIUtil.Create("Frame", {
		Name = "Halo",
		Size = UDim2.fromScale(1.22, 1.22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WAIT_COLOR,
		BackgroundTransparency = 0.8,
		ZIndex = 23,
		Parent = holder,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	local pad = UIUtil.Create("TextButton", {
		Name = "Pad",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = IDLE_COLOR,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 24,
		Parent = holder,
	})
	UIUtil.Corner(pad, UDim.new(1, 0))
	local padStroke = UIUtil.Stroke(pad, WHITE, 4, 0.15)
	UIUtil.Create("UIGradient", { Color = ColorSequence.new(WHITE, Color3.fromRGB(170, 170, 200)), Rotation = 90, Parent = pad })
	local padScale = UIUtil.Create("UIScale", { Parent = pad })
	local padIcon = Kit.Label({ Text = "⚡", TextSize = 60, Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.14), ZIndex = 26, Parent = pad })
	local padText = Kit.Label({ Text = "", TextSize = 30, Font = Theme.Fonts.Number, Size = UDim2.fromScale(0.9, 0.2),
		Position = UDim2.fromScale(0.05, 0.56), ZIndex = 26, Parent = pad })
	UIUtil.Create("UIStroke", { Color = Color3.fromRGB(30, 10, 60), Thickness = 2, Transparency = 0.3, Parent = padText })
	local haloPulse = Kit.Pulse(halo, { BackgroundTransparency = 0.55 }, 0.6)

	-- Ligne du bas : manche, aide, temps
	local info = Kit.Label({ Text = "", TextSize = 16, Color = colors.TextDim, Size = UDim2.new(1, -40, 0, 22),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), ZIndex = 30, Parent = container })
	local times = Kit.Label({ Text = "", TextSize = 18, Color = colors.Yellow, Size = UDim2.new(1, -40, 0, 24),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), ZIndex = 30, Parent = container })

	local function setPad(color: Color3, icon: string, label: string)
		pad.BackgroundColor3 = color
		halo.BackgroundColor3 = color
		padIcon.Text = icon
		padText.Text = label
	end

	local function nameOf(seat: number): string
		if seat == you then
			return T("You")
		end
		local other = duel.Players and duel.Players[seat]
		return other and other.Name or "?"
	end

	local function tap()
		if not duel or duel.Over or tapped then
			return
		end
		if duel.Phase ~= "wait" and duel.Phase ~= "go" then
			return
		end
		tapped = true
		padScale.Scale = 0.9
		UIUtil.Tween(padScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if duel.Phase == "go" then
			api.Sounds.Play("Pop", 1.4)
			local mine = os.clock() - goAt
			times.Text = T("Your tap: %s s", string.format("%.3f", mine))
		end
		task.spawn(api.Move, "tap")
	end

	table.insert(connections, pad.Activated:Connect(tap))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space then
			tap()
		end
	end))

	local function render(state, kind: string?)
		duel = state
		local phase = state.Phase or ""
		local round = state.Round or 0
		local newPhase = phase ~= lastPhase or round ~= lastRound
		lastPhase, lastRound = phase, round
		local winScore = state.WinScore or 3
		info.Text = round > 0 and T("Round %d • first to %d points", round, winScore) or T("First to %d points", winScore)

		if state.Over then
			countdown.Hide()
			local won = state.Winner == you
			setPad(won and colors.Yellow or (state.Winner == 0 and colors.Cyan or colors.Red), won and "🏆" or (state.Winner == 0 and "🤝" or "💔"),
				won and T("WINNER!") or (state.Winner == 0 and T("DRAW") or T("DEFEAT")))
			banner.Set(won and T("🏆 Fastest fingers in the arcade!") or (state.Winner == 0 and T("🤝 Draw!") or T("💔 Too slow this time...")),
				won and colors.Yellow or colors.Red, kind == "duelEnd")
			return
		end
		if phase == "intro" then
			setPad(IDLE_COLOR, "⚡", T("Ready?"))
			banner.Set(T("Tap the moment it turns GREEN!"), colors.Yellow, false)
			if newPhase then
				countdown.Run(state.PhaseLeft or 3, api.Sounds.Play)
			end
		elseif phase == "wait" then
			if newPhase then
				tapped = false
				times.Text = ""
			end
			setPad(WAIT_COLOR, "✋", tapped and T("Too early!") or T("Wait..."))
			banner.Set(T("Wait for it... don't tap yet!"), colors.Purple, newPhase)
		elseif phase == "go" then
			if newPhase then
				goAt = os.clock()
				api.Sounds.Play("Bonus", 1.3)
				padScale.Scale = 1.12
				UIUtil.Tween(padScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			setPad(GO_COLOR, "👆", tapped and T("Tapped!") or T("TAP!"))
			banner.Set(T("GO GO GO!"), GO_COLOR, newPhase)
		elseif phase == "result" then
			local result = state.RoundResult or {}
			local winner = result.Winner or 0
			if result.Void then
				setPad(IDLE_COLOR, "💤", T("Nobody tapped"))
				banner.Set(T("Round replayed"), colors.TextDim, newPhase)
			elseif result.FalseStart then
				local cheater = result.FalseStart
				setPad(cheater == you and colors.Red or colors.Green, cheater == you and "😵" or "😏",
					cheater == you and T("False start!") or T("Point for you!"))
				banner.Set(T("False start by %s!", nameOf(cheater)), colors.Orange, newPhase)
			else
				local won = winner == you
				setPad(won and colors.Green or colors.Red, won and "⚡" or "🐢", won and T("Point!") or T("Too slow!"))
				banner.Set(T("%s wins the round!", nameOf(winner)), seatColors[winner] or colors.Yellow, newPhase)
				local t = result.Times or {}
				local mineTime, theirTime = t[you] or -1, t[3 - you] or -1
				local function fmt(value: number): string
					return value >= 0 and string.format("%.3f s", value) or "—"
				end
				times.Text = T("You: %s   •   %s: %s", fmt(mineTime), nameOf(3 - you), fmt(theirTime))
				if newPhase then
					api.Sounds.Play(won and "Bonus" or "Error", won and 1.1 or 0.8)
				end
			end
		end
		padStroke.Color = phase == "go" and WHITE or Color3.fromRGB(220, 200, 255)
	end

	render(duel, "duelStart")
	table.insert(connections, Kit.Track(api, render))

	return {
		Destroy = function()
			haloPulse:Cancel()
			countdown.Hide()
			UIUtil.DisconnectAll(connections)
			area:Destroy()
			info:Destroy()
			times:Destroy()
			banner.Frame:Destroy()
		end,
	}
end

return Game
