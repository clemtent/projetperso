--[[
	Solo_Memory (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Memory

	🃏 Memory de l'arcade : retrouve toutes les paires. Le paquet est gardé
	par le SERVEUR : chaque carte retournée est demandée au serveur (le
	client ne connaît jamais les cartes cachées). Moins de coups = plus
	d'étoiles ; le record est le meilleur temps.
]]

local Kit = require(script.Parent.Solo_Kit)
local Logic = Kit.Logic
local C = Kit.Colors
local create = Kit.Create

local CARD_RATIO = 0.8 -- largeur / hauteur d'une carte
local FLIP_TIME = 0.26

local Module = { Id = "Memory", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	local st = {
		Cols = 4,
		Rows = 4,
		Pairs = 8,
		Found = 0,
		Moves = 0,
		Token = nil,
		Done = true,
		Started = nil :: number?,
		Clock = 0,
		Generation = 0,
		InFlight = 0,
		Open = {} :: { number }, -- cartes retournées non appariées (max 2)
		CloseAt = nil :: number?,
		Streak = 0,
	}
	local cards = {}

	kit = Kit.new(container, api, {
		Id = "Memory",
		Primary = "Moves",
		SmallA = "Pairs",
		SmallB = "Time",
		Details = function(_, rules)
			return string.format("%d × %d  ·  ", rules.Cols, rules.Rows) .. T("%d pairs", rules.Pairs)
				.. "\n" .. T("⭐⭐⭐ in %d moves max", math.ceil(rules.Pairs * 1.5))
				.. "\n" .. T("⭐⭐ in %d moves max", math.ceil(rules.Pairs * 2.25))
		end,
		BestText = Kit.FormatTime,
		ScoreText = function(result)
			local text = "🃏 " .. T("%s moves", tostring(result.Score or 0))
			if result.Won or result.Rejected then
				text ..= "  ·  ⏱️ " .. Kit.FormatTime(tonumber(result.Time) or 0)
			end
			return text
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
	kit.PickerHelp.Text = T("Flip two cards: same picture = a pair. Fewer moves, more ⭐!")

	----------------------------------------------------------------------
	-- Plateau
	----------------------------------------------------------------------
	local board = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = kit.Area,
	})
	local aspect = create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = board })

	local function paintBack(card)
		card.Face.BackgroundColor3 = kit.Accent
		card.Gradient.Color = ColorSequence.new(kit.Accent:Lerp(C.White, 0.2), kit.Accent2)
		card.Gradient.Rotation = 45
		card.Stroke.Color = C.White
		card.Stroke.Transparency = 0.45
		card.Emoji.Text = "✨"
		card.Emoji.TextColor3 = C.White
		card.Emoji.TextTransparency = 0.25
		card.Emoji.Size = UDim2.fromScale(0.42, 0.42)
		card.Inner.Visible = true
	end

	local function paintFace(card, symbol: number, matched: boolean)
		local entry = Logic.MemorySymbols[symbol] or Logic.MemorySymbols[1]
		local color = entry[2]
		card.Face.BackgroundColor3 = color
		card.Gradient.Color = ColorSequence.new(color:Lerp(C.White, 0.72), color:Lerp(C.White, 0.35))
		card.Gradient.Rotation = 90
		card.Stroke.Color = matched and C.Yellow or color:Lerp(C.White, 0.3)
		card.Stroke.Transparency = matched and 0 or 0.1
		card.Emoji.Text = entry[1]
		card.Emoji.TextTransparency = 0
		card.Emoji.Size = UDim2.fromScale(0.72, 0.72)
		card.Inner.Visible = false
	end

	local onCard

	local function makeCard(index: number)
		local button = create("TextButton", {
			Name = "Card" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = board,
		})
		local face = create("Frame", {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundColor3 = kit.Accent,
			ZIndex = 4,
			Parent = button,
		})
		Kit.Corner(face, UDim.new(0.14, 0))
		local stroke = Kit.Stroke(face, C.White, 2, 0.45)
		local gradientObj = create("UIGradient", { Rotation = 45, Parent = face })
		-- Liseré intérieur du dos de carte
		local inner = create("Frame", {
			Name = "Inner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.82),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = face,
		})
		Kit.Corner(inner, UDim.new(0.14, 0))
		Kit.Stroke(inner, C.White, 1.5, 0.6)
		local emoji = Kit.Label({
			Name = "Emoji",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.42, 0.42),
			Text = "✨",
			MaxTextSize = 64,
			ZIndex = 6,
			Parent = face,
		})
		local scale = create("UIScale", { Parent = face })
		local card = {
			Button = button,
			Face = face,
			Stroke = stroke,
			Gradient = gradientObj,
			Inner = inner,
			Emoji = emoji,
			Scale = scale,
			Index = index,
			State = "Back", -- Back | Open | Matched
			Symbol = nil :: number?,
			Flip = nil :: any,
		}
		paintBack(card)
		button.Activated:Connect(function()
			onCard(card.Index)
		end)
		button.MouseEnter:Connect(function()
			if card.State == "Back" and not st.Done then
				Kit.Tween(scale, 0.12, { Scale = 1.05 })
			end
		end)
		button.MouseLeave:Connect(function()
			Kit.Tween(scale, 0.12, { Scale = 1 })
		end)
		return card
	end

	local function layout()
		local total = st.Cols * st.Rows
		aspect.AspectRatio = (st.Cols * CARD_RATIO) / st.Rows
		for index = 1, math.max(total, #cards) do
			local card = cards[index]
			if index <= total then
				if not card then
					card = makeCard(index)
					cards[index] = card
				end
				local x = (index - 1) % st.Cols
				local y = (index - 1) // st.Cols
				card.Button.Position = UDim2.fromScale(x / st.Cols, y / st.Rows)
				card.Button.Size = UDim2.fromScale(1 / st.Cols, 1 / st.Rows)
				card.Button.Visible = true
				card.State = "Back"
				card.Symbol = nil
				card.Flip = nil
				card.Face.Size = UDim2.new(1, -8, 1, -8)
				card.Scale.Scale = 1
				paintBack(card)
			elseif card then
				card.Button.Visible = false
			end
		end
	end

	-- Retourne une carte (animation dans la boucle commune)
	local function flip(card, toFace: boolean, symbol: number?, matched: boolean?, delay: number?)
		card.Flip = { T = -(delay or 0), ToFace = toFace, Symbol = symbol, Matched = matched == true, Swapped = false }
	end

	kit:UseRating(0, "Rating")
	local function refreshHud()
		local three, two = math.ceil(st.Pairs * 1.5), math.ceil(st.Pairs * 2.25)
		local rating = st.Moves <= three and 3 or (st.Moves <= two and 2 or 1)
		local budget = rating == 3 and three or (rating == 2 and two or st.Moves)
		local floor = rating == 3 and 0 or (rating == 2 and three or st.Moves)
		kit:SetRating(rating, 1 - (st.Moves - floor) / math.max(1, budget - floor))
		kit:SetStat("Primary", tostring(st.Moves))
		kit:SetStat("A", string.format("%d / %d", st.Found, st.Pairs))
		kit:SetStat("B", Kit.FormatClock(st.Clock))
	end

	local function closeOpen()
		for _, index in ipairs(st.Open) do
			local card = cards[index]
			if card and card.State == "Open" then
				card.State = "Back"
				flip(card, false)
			end
		end
		st.Open = {}
		st.CloseAt = nil
	end

	----------------------------------------------------------------------
	-- Partie
	----------------------------------------------------------------------
	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Cols, st.Rows, st.Pairs = rules.Cols, rules.Rows, rules.Pairs
		st.Found, st.Moves, st.Streak = 0, 0, 0
		st.Token = nil
		st.Done = false
		st.Started = nil
		st.Clock = 0
		st.InFlight = 0
		st.Open = {}
		st.CloseAt = nil
		layout()
		refreshHud()
		-- petite distribution animée
		for index = 1, st.Cols * st.Rows do
			local card = cards[index]
			card.Scale.Scale = 0.2
			task.delay(0.02 * index, function()
				if kit.Alive and generation == st.Generation then
					Kit.Tween(card.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			end)
		end
		kit:Sound("Open")
		kit:Mood("😊", T("Find all the pairs. Fewer moves = more ⭐!"))
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

	local function finish(result)
		st.Done = true
		kit:Mood("🥳", T("All pairs found!"))
		task.delay(0.9, function()
			if kit.Alive and st.Done then
				kit:ShowResult(result)
			end
		end)
	end

	local function applyReply(reply, generation: number)
		if type(reply) ~= "table" or reply.Ignored then
			return
		end
		local card = cards[reply.Cell]
		if not card then
			return
		end
		card.Symbol = reply.Symbol
		if reply.Other == nil then
			flip(card, true, reply.Symbol, false)
			return
		end
		local other = cards[reply.Other]
		st.Moves = tonumber(reply.Moves) or st.Moves + 1
		if reply.Match then
			st.Found = tonumber(reply.Pairs) or st.Found + 1
			st.Streak += 1
			card.State = "Matched"
			flip(card, true, reply.Symbol, true)
			if other then
				other.State = "Matched"
				paintFace(other, other.Symbol or reply.Symbol, true)
			end
			st.Open = {}
			task.delay(FLIP_TIME, function()
				if not kit.Alive or generation ~= st.Generation then
					return
				end
				for _, c in ipairs({ card, other }) do
					if c then
						c.Scale.Scale = 1.18
						Kit.Tween(c.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
						kit:Burst(c.Face, (Logic.MemorySymbols[c.Symbol or 1] or {})[2], 8)
					end
				end
				kit:Float(card.Face, "+1", C.Yellow)
				kit:Sound("Bonus", 1 + math.min(st.Streak, 5) * 0.08)
			end)
			if st.Streak >= 2 then
				kit:Mood("🤩", T("Combo x%d!", st.Streak))
			else
				kit:Mood("😍", T("A pair! Keep going."))
			end
			kit:SetStat("A", string.format("%d / %d", st.Found, st.Pairs), true)
		else
			st.Streak = 0
			flip(card, true, reply.Symbol, false)
			st.CloseAt = os.clock() + FLIP_TIME + 0.75
			kit:Mood("🤔", T("Not a pair... remember them!"), false)
		end
		refreshHud()
		kit:SetStat("Primary", tostring(st.Moves), true)
		if reply.Done then
			finish(reply.Result)
		end
	end

	function onCard(index: number)
		if st.Done or not st.Token then
			return
		end
		local card = cards[index]
		if not card or card.State ~= "Back" then
			return
		end
		-- deux cartes ratées encore visibles : on les referme tout de suite
		if #st.Open >= 2 then
			closeOpen()
		end
		if #st.Open >= 2 or st.InFlight >= 2 then
			return
		end
		if not st.Started then
			st.Started = os.clock()
		end
		card.State = "Open"
		table.insert(st.Open, index)
		card.Scale.Scale = 0.9
		kit:Sound("Click", 1.1)
		st.InFlight += 1
		local token, generation = st.Token, st.Generation
		task.spawn(function()
			local ok, reply = kit:Invoke("solo:move", { Token = token, Cell = index })
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			st.InFlight -= 1
			Kit.Tween(card.Scale, 0.15, { Scale = 1 })
			if not ok then
				card.State = "Back"
				local position = table.find(st.Open, index)
				if position then
					table.remove(st.Open, position)
				end
				kit:Notify(type(reply) == "string" and reply or T("Something went wrong"), C.Red)
				return
			end
			applyReply(reply, generation)
		end)
	end

	----------------------------------------------------------------------
	-- Boucle : retournements, fermeture automatique, chrono
	----------------------------------------------------------------------
	local hudTimer = 0
	kit:OnFrame(function(dt)
		for _, card in ipairs(cards) do
			local anim = card.Flip
			if anim then
				anim.T += dt
				if anim.T >= 0 then
					local k = math.min(anim.T / FLIP_TIME, 1)
					if k >= 0.5 and not anim.Swapped then
						anim.Swapped = true
						if anim.ToFace and anim.Symbol then
							paintFace(card, anim.Symbol, anim.Matched)
						else
							paintBack(card)
						end
					end
					local sx = math.abs(math.cos(math.pi * k))
					card.Face.Size = UDim2.new(math.max(sx, 0.02), -8 * sx, 1, -8)
					if k >= 1 then
						card.Flip = nil
						card.Face.Size = UDim2.new(1, -8, 1, -8)
					end
				end
			end
		end
		if st.CloseAt and os.clock() >= st.CloseAt then
			closeOpen()
		end
		if st.Started and not st.Done then
			st.Clock = os.clock() - st.Started
		end
		hudTimer += dt
		if hudTimer >= 0.25 then
			hudTimer = 0
			kit:SetStat("B", Kit.FormatClock(st.Clock))
		end
	end)

	st.Cols, st.Rows, st.Pairs = 4, 3, 6
	layout()
	refreshHud()
	kit:Mood("😊", T("Flip two cards to find a pair."), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			kit:Destroy()
		end,
	}
end

return Module
