--[[
	Solo_Simon (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Simon

	🎵 Simon de l'arcade : regarde la séquence de pastilles kawaii qui
	s'allument, puis rejoue-la. Une couleur de plus à chaque manche.
	La séquence est tirée par le SERVEUR, qui vérifie chaque manche (et
	qu'elle n'a pas été rejouée plus vite qu'humainement possible).
	Touches 1 à 6 = pastilles.
]]

local Kit = require(script.Parent.Solo_Kit)
local C = Kit.Colors
local create = Kit.Create

local PAD_COLORS = {
	Color3.fromRGB(255, 96, 170),
	Color3.fromRGB(80, 214, 255),
	Color3.fromRGB(255, 212, 70),
	Color3.fromRGB(90, 232, 150),
	Color3.fromRGB(176, 130, 255),
	Color3.fromRGB(255, 150, 80),
}
local PAD_PITCH = { 0.8, 0.95, 1.1, 1.25, 1.42, 1.6 }
local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
}

local Module = { Id = "Simon", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	local st = {
		Pads = 4,
		Step = 0.45,
		Sequence = {} :: { number },
		Inputs = {} :: { number },
		Phase = "Idle", -- Idle | Watch | Input | Wait | Over
		Token = nil,
		Round = 0,
		Generation = 0,
	}
	local pads = {}

	kit = Kit.new(container, api, {
		Id = "Simon",
		Primary = "Round",
		SmallA = "Next ⭐",
		SmallB = "Speed",
		Details = function(_, rules)
			return T("%d pads · a note every %ss", rules.Pads, string.format("%.2f", rules.Step))
				.. "\n" .. T("⭐ %d rounds · ⭐⭐ %d · ⭐⭐⭐ %d", rules.Thresholds[1], rules.Thresholds[2], rules.Thresholds[3])
		end,
		BestText = function(value)
			return T("%s rounds", tostring(value))
		end,
		ScoreText = function(result)
			return "🎵 " .. T("%s rounds", tostring(result.Score or 0))
		end,
		NoStarHint = function(rules)
			return T("Reach round %d for your first ⭐!", rules.Thresholds[1])
		end,
		LoseTitle = "Oops!",
		OnPlay = function(difficulty)
			startGame(difficulty)
		end,
		OnPicker = function()
			st.Generation += 1
			st.Phase = "Idle"
		end,
		QuitArg = function()
			return {}
		end,
	})
	kit.PickerHelp.Text = kit.Touch and T("Watch the pads light up, then tap them in the same order")
		or T("Watch the pads light up, then click them in the same order (keys 1-6)")

	----------------------------------------------------------------------
	-- Plateau : bandeau d'état + pastilles
	----------------------------------------------------------------------
	local status = create("Frame", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 38),
		BackgroundColor3 = C.CardDark,
		BackgroundTransparency = 0.1,
		ZIndex = 3,
		Parent = kit.Area,
	})
	Kit.Corner(status, UDim.new(1, 0))
	local statusStroke = Kit.Stroke(status, kit.Accent, 2, 0.2)
	local statusText = Kit.Label({
		Size = UDim2.new(1, -24, 1, -10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 20,
		ZIndex = 4,
		Parent = status,
	})
	local statusScale = create("UIScale", { Parent = status })
	local function setStatus(text: string, color: Color3)
		statusText.Text = text
		statusStroke.Color = color
		statusScale.Scale = 1.08
		Kit.Tween(statusScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local board = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = kit.Area,
	})
	local grid = create("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = board,
	})
	local aspect = create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = grid })

	local onPad

	local function makePad(index: number)
		local color = PAD_COLORS[index]
		local button = create("TextButton", {
			Name = "Pad" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = grid,
		})
		-- Halo (visible quand la pastille s'allume)
		local glow = create("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.02, 1.02),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = button,
		})
		Kit.Corner(glow, UDim.new(0.3, 0))
		local body = create("Frame", {
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			BackgroundColor3 = color,
			ZIndex = 5,
			Parent = button,
		})
		Kit.Corner(body, UDim.new(0.28, 0))
		local bodyStroke = Kit.Stroke(body, color:Lerp(C.White, 0.55), 3, 0.3)
		local bodyGradient = create("UIGradient", {
			Color = ColorSequence.new(color:Lerp(C.White, 0.3), color:Lerp(C.Black, 0.25)),
			Rotation = 90,
			Parent = body,
		})
		-- Reflet
		local shine = create("Frame", {
			Position = UDim2.fromScale(0.14, 0.1),
			Size = UDim2.fromScale(0.36, 0.14),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.55,
			ZIndex = 6,
			Parent = body,
		})
		Kit.Corner(shine, UDim.new(1, 0))
		-- Visage kawaii : yeux, joues, bouche
		local face = create("Frame", {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromScale(0.56, 0.3),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Parent = body,
		})
		local eyes = {}
		for side = 0, 1 do
			local eye = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(side == 0 and 0.2 or 0.8, 0.3),
				Size = UDim2.fromScale(0.16, 0.5),
				BackgroundColor3 = Color3.fromRGB(40, 24, 60),
				ZIndex = 7,
				Parent = face,
			})
			Kit.Corner(eye, UDim.new(1, 0))
			local spark = create("Frame", {
				Position = UDim2.fromScale(0.22, 0.14),
				Size = UDim2.fromScale(0.42, 0.34),
				BackgroundColor3 = C.White,
				ZIndex = 8,
				Parent = eye,
			})
			Kit.Corner(spark, UDim.new(1, 0))
			local cheek = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(side == 0 and 0.02 or 0.98, 0.78),
				Size = UDim2.fromScale(0.2, 0.26),
				BackgroundColor3 = Color3.fromRGB(255, 120, 150),
				BackgroundTransparency = 0.35,
				ZIndex = 7,
				Parent = face,
			})
			Kit.Corner(cheek, UDim.new(1, 0))
			eyes[side + 1] = eye
		end
		local mouth = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.78),
			Size = UDim2.fromScale(0.14, 0.2),
			BackgroundColor3 = Color3.fromRGB(40, 24, 60),
			ZIndex = 7,
			Parent = face,
		})
		Kit.Corner(mouth, UDim.new(1, 0))
		local keyHint = Kit.Label({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(0.94, 0.95),
			Size = UDim2.fromScale(0.2, 0.16),
			Text = tostring(index),
			TextColor3 = C.White,
			TextTransparency = 0.35,
			MaxTextSize = 18,
			Visible = not kit.Touch,
			ZIndex = 7,
			Parent = body,
		})
		local scale = create("UIScale", { Parent = body })
		local pad = {
			Button = button,
			Body = body,
			Glow = glow,
			Stroke = bodyStroke,
			Gradient = bodyGradient,
			Eyes = eyes,
			Mouth = mouth,
			Scale = scale,
			Color = color,
			Index = index,
			Light = 0, -- secondes d'allumage restantes
			Key = keyHint,
		}
		button.Activated:Connect(function()
			onPad(pad.Index)
		end)
		return pad
	end

	for index = 1, 6 do
		pads[index] = makePad(index)
	end

	local function layout()
		local cols = st.Pads == 6 and 3 or 2
		local rows = 2
		aspect.AspectRatio = cols / rows
		for index, pad in ipairs(pads) do
			if index <= st.Pads then
				local x = (index - 1) % cols
				local y = (index - 1) // cols
				pad.Button.Position = UDim2.fromScale(x / cols, y / rows)
				pad.Button.Size = UDim2.fromScale(1 / cols, 1 / rows)
				pad.Button.Visible = true
			else
				pad.Button.Visible = false
			end
		end
	end

	local function light(index: number, duration: number)
		local pad = pads[index]
		if not pad then
			return
		end
		pad.Light = duration
		pad.Scale.Scale = 1.1
		Kit.Tween(pad.Scale, math.min(duration, 0.3), { Scale = 1 }, Enum.EasingStyle.Back)
		kit:Sound("Pop", PAD_PITCH[index])
	end

	local function speedText(step: number): string
		local icon = step >= 0.55 and "🐢" or (step >= 0.42 and "🐇" or "⚡")
		return icon .. " " .. string.format("%.2fs", step)
	end

	kit:UseRating(0)
	local function refreshHud()
		local rules = kit.GameRules.Difficulties[kit.Difficulty]
		kit:SetRatingFromScore(st.Round, rules.Thresholds)
		kit:SetStat("Primary", tostring(math.max(1, #st.Sequence)))
		kit:SetStat("A", kit:NextStarText(st.Round, rules.Thresholds))
		kit:SetStat("B", speedText(st.Step))
	end

	----------------------------------------------------------------------
	-- Déroulement
	----------------------------------------------------------------------
	local function playSequence(generation: number)
		st.Phase = "Watch"
		st.Inputs = {}
		setStatus("👀 " .. T("Watch closely!"), C.Cyan)
		kit:Mood("🤓", T("Remember the order..."), false)
		refreshHud()
		task.wait(0.7)
		for _, index in ipairs(st.Sequence) do
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			light(index, st.Step * 0.62)
			task.wait(st.Step)
		end
		if generation ~= st.Generation or not kit.Alive then
			return
		end
		st.Phase = "Input"
		setStatus("🎵 " .. T("Your turn! %d notes", #st.Sequence), kit.Accent)
		kit:Mood("😊", T("Your turn! Tap the pads in order."), false)
	end

	local function gameOver(result, expected: number?)
		st.Phase = "Over"
		setStatus("💫 " .. T("Oops! Wrong pad"), C.Red)
		kit:Mood("😵", T("So close! Try again?"))
		kit:Shake(grid, 7)
		kit:Sound("Error")
		-- montre la bonne pastille
		if expected then
			task.spawn(function()
				for _ = 1, 3 do
					task.wait(0.28)
					if not kit.Alive then
						return
					end
					local pad = pads[expected]
					if pad then
						pad.Light = 0.18
					end
				end
			end)
		end
		task.delay(1.4, function()
			if kit.Alive and st.Phase == "Over" then
				kit:ShowResult(result)
			end
		end)
	end

	local function submit(generation: number)
		st.Phase = "Wait"
		local token = st.Token
		local inputs = table.clone(st.Inputs)
		task.spawn(function()
			local ok, reply = kit:Invoke("solo:move", { Token = token, Inputs = inputs })
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			if not ok or type(reply) ~= "table" then
				-- (trop rapide : on rejoue la même manche)
				kit:Notify(type(reply) == "string" and reply or T("Something went wrong"), C.Red)
				task.wait(0.6)
				if generation == st.Generation then
					playSequence(generation)
				end
				return
			end
			if reply.Wrong then
				gameOver(reply.Result, tonumber(reply.Expected))
				return
			end
			st.Round = tonumber(reply.Round) or st.Round + 1
			refreshHud()
			kit:SetStat("A", kit:NextStarText(st.Round, kit.GameRules.Difficulties[kit.Difficulty].Thresholds), true)
			if reply.Done then
				st.Phase = "Over"
				setStatus("🏆 " .. T("Maximum reached!"), C.Yellow)
				kit:Mood("🥳", T("Incredible memory!"))
				task.delay(1, function()
					if kit.Alive then
						kit:ShowResult(reply.Result)
					end
				end)
				return
			end
			setStatus("✨ " .. T("Great!"), C.Mint)
			kit:Burst(grid, C.Mint, 10)
			kit:Sound("Bonus", 1 + math.min(st.Round, 10) * 0.03)
			if type(reply.Sequence) == "table" then
				st.Sequence = reply.Sequence
			end
			kit:SetStat("Primary", tostring(#st.Sequence), true)
			task.wait(0.6)
			if generation == st.Generation then
				playSequence(generation)
			end
		end)
	end

	function onPad(index: number)
		if index > st.Pads then
			return
		end
		if st.Phase ~= "Input" then
			if st.Phase ~= "Over" and st.Phase ~= "Idle" then
				local pad = pads[index]
				pad.Scale.Scale = 0.94
				Kit.Tween(pad.Scale, 0.2, { Scale = 1 })
			end
			return
		end
		light(index, 0.22)
		table.insert(st.Inputs, index)
		local position = #st.Inputs
		if st.Sequence[position] ~= index then
			submit(st.Generation) -- le serveur confirme l'erreur
			return
		end
		kit:Float(pads[index].Body, "♪", pads[index].Color)
		if position >= #st.Sequence then
			submit(st.Generation)
		end
	end

	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Pads = rules.Pads
		st.Step = rules.Step
		st.Sequence = {}
		st.Inputs = {}
		st.Round = 0
		st.Phase = "Idle"
		st.Token = nil
		layout()
		refreshHud()
		setStatus("⏳ " .. T("Get ready..."), C.TextDim)
		kit:Mood("😊", T("Watch, then repeat!"))
		kit:Sound("Open")
		task.spawn(function()
			local reply = kit:StartSession()
			if generation ~= st.Generation then
				return
			end
			if not reply or type(reply.Sequence) ~= "table" then
				kit:ShowPicker()
				return
			end
			st.Token = reply.Token
			st.Sequence = reply.Sequence
			st.Step = tonumber(reply.Step) or st.Step
			playSequence(generation)
		end)
	end

	kit:OnKey(function(key)
		local index = KEYS[key]
		if index then
			onPad(index)
		end
	end)

	-- Boucle : allumage des pastilles
	kit:OnFrame(function(dt)
		for index, pad in ipairs(pads) do
			if index <= st.Pads then
				local lit = pad.Light > 0
				if lit then
					pad.Light -= dt
				end
				local on = pad.Light > 0
				if on ~= pad.On then
					pad.On = on
					pad.Glow.BackgroundTransparency = on and 0.45 or 1
					pad.Glow.Size = on and UDim2.fromScale(1.02, 1.02) or UDim2.fromScale(0.9, 0.9)
					pad.Gradient.Color = on and ColorSequence.new(C.White, pad.Color:Lerp(C.White, 0.3))
						or ColorSequence.new(pad.Color:Lerp(C.White, 0.3), pad.Color:Lerp(C.Black, 0.25))
					pad.Stroke.Color = on and C.White or pad.Color:Lerp(C.White, 0.55)
					pad.Stroke.Transparency = on and 0 or 0.3
					-- yeux fermés (^^) quand elle chante
					for _, eye in ipairs(pad.Eyes) do
						eye.Size = on and UDim2.fromScale(0.2, 0.18) or UDim2.fromScale(0.16, 0.5)
					end
					pad.Mouth.Size = on and UDim2.fromScale(0.2, 0.42) or UDim2.fromScale(0.14, 0.2)
				end
			end
		end
	end)

	st.Pads = 4
	layout()
	refreshHud()
	setStatus("🎵 " .. T("Simon says..."), kit.Accent)
	kit:Mood("😊", T("Watch, then repeat!"), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			kit:Destroy()
		end,
	}
end

return Module
