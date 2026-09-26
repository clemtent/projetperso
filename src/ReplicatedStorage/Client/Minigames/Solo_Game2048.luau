--[[
	Solo_Game2048 (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Game2048

	🔢 2048 de l'arcade : fais glisser les tuiles (flèches / ZQSD / WASD ou
	glissé du doigt), deux tuiles égales fusionnent. Atteins la tuile
	objectif de ta difficulté !
	Les nouvelles tuiles viennent d'une graine donnée par le SERVEUR
	(Solo_Logic) : à la fin, le client envoie ses coups ("URDL...") et le
	serveur rejoue la partie pour calculer le vrai score.
	Tuiles réutilisées (pool), glissements animés dans la boucle commune.
]]

local Kit = require(script.Parent.Solo_Kit)
local Logic = Kit.Logic
local C = Kit.Colors
local create = Kit.Create

local SLIDE_TIME = 0.11
local SIZE = Logic.Games.Game2048.Size

-- Couleurs des tuiles (fond, texte)
local TILE_STYLE = {
	[2] = { Color3.fromRGB(255, 236, 250), Color3.fromRGB(110, 70, 150) },
	[4] = { Color3.fromRGB(255, 210, 236), Color3.fromRGB(120, 60, 140) },
	[8] = { Color3.fromRGB(255, 166, 204), C.White },
	[16] = { Color3.fromRGB(255, 132, 176), C.White },
	[32] = { Color3.fromRGB(255, 112, 140), C.White },
	[64] = { Color3.fromRGB(255, 86, 110), C.White },
	[128] = { Color3.fromRGB(255, 208, 90), Color3.fromRGB(120, 70, 20) },
	[256] = { Color3.fromRGB(120, 232, 170), Color3.fromRGB(20, 90, 60) },
	[512] = { Color3.fromRGB(100, 210, 255), Color3.fromRGB(20, 70, 110) },
	[1024] = { Color3.fromRGB(170, 140, 255), C.White },
	[2048] = { Color3.fromRGB(255, 200, 60), C.White },
}
local BIG_STYLE = { Color3.fromRGB(60, 30, 110), C.Yellow }

local Module = { Id = "Game2048", Kind = "Solo" }

function Module.Build(container: Frame, api)
	local kit
	local startGame: (string) -> ()
	local function T(text: string, ...): string
		return Kit.Translate(api, text, ...)
	end

	local st = {
		Sim = nil :: any,
		Rules = nil :: any,
		Moves = {} :: { string },
		Token = nil,
		Generation = 0,
		Playing = false,
		Anim = nil :: any, -- glissement en cours
		Clock = 0,
	}
	local tiles = {} -- [case] = tuile affichée
	local pool = {}

	kit = Kit.new(container, api, {
		Id = "Game2048",
		Primary = "Score",
		SmallA = "Next ⭐",
		SmallB = "Top tile",
		Details = function(_, rules)
			return T("Goal: the %s tile", tostring(rules.Target))
				.. "\n⭐ " .. rules.Thresholds[1] .. "  ·  ⭐⭐ " .. rules.Thresholds[2] .. "  ·  ⭐⭐⭐ " .. rules.Thresholds[3]
		end,
		BestText = function(value)
			return Kit.FormatNumber(value) .. " " .. T("pts")
		end,
		ScoreText = function(result)
			local text = "🔢 " .. Kit.FormatNumber(tonumber(result.Score) or 0) .. " " .. T("pts")
			if type(result.MaxTile) == "number" then
				text ..= "  ·  🏅 " .. tostring(result.MaxTile)
			end
			return text
		end,
		NoStarHint = function(rules)
			return T("Make a %s tile for your first ⭐!", tostring(rules.Thresholds[1]))
		end,
		LoseTitle = "No more moves!",
		OnPlay = function(difficulty)
			startGame(difficulty)
		end,
		OnPicker = function()
			st.Generation += 1
			st.Playing = false
		end,
		QuitArg = function()
			return { Moves = table.concat(st.Moves) }
		end,
	})
	kit.PickerHelp.Text = kit.Touch and T("Swipe to slide the tiles · Same numbers merge")
		or T("Arrow keys / WASD to slide · Same numbers merge")

	----------------------------------------------------------------------
	-- Plateau
	----------------------------------------------------------------------
	local board = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 28, 88),
		ZIndex = 3,
		Parent = kit.Area,
	})
	Kit.Corner(board, 18)
	Kit.Stroke(board, kit.Accent, 2.5, 0.2)
	Kit.Gradient(board, Color3.fromRGB(64, 44, 128), Color3.fromRGB(34, 22, 74), 90)
	create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = board })
	local grid = create("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -14, 1, -14),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = board,
	})
	for index = 1, SIZE * SIZE do
		local x = (index - 1) % SIZE
		local y = (index - 1) // SIZE
		local slot = create("Frame", {
			Name = "Slot" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((x + 0.5) / SIZE, (y + 0.5) / SIZE),
			Size = UDim2.fromScale(0.92 / SIZE, 0.92 / SIZE),
			BackgroundColor3 = Color3.fromRGB(24, 16, 56),
			BackgroundTransparency = 0.35,
			ZIndex = 4,
			Parent = grid,
		})
		Kit.Corner(slot, UDim.new(0.16, 0))
	end

	-- "Fin de partie" (encaisser)
	local finishButton = Kit.Button({
		Name = "Finish",
		Text = "🏁 " .. T("Finish"),
		Color = C.CardLight,
		Size = UDim2.new(1, 0, 0, 40),
		MaxTextSize = 17,
		ZIndex = 3,
		Parent = kit.Extra,
	})

	local function cellCenter(index: number): UDim2
		local x = (index - 1) % SIZE
		local y = (index - 1) // SIZE
		return UDim2.fromScale((x + 0.5) / SIZE, (y + 0.5) / SIZE)
	end

	local function styleTile(tile, value: number)
		tile.Value = value
		local style = TILE_STYLE[value] or BIG_STYLE
		tile.Frame.BackgroundColor3 = style[1]
		tile.Gradient.Color = ColorSequence.new(style[1]:Lerp(C.White, 0.3), style[1]:Lerp(C.Black, 0.08))
		tile.Text.Text = tostring(value)
		tile.Text.TextColor3 = style[2]
		local digits = #tostring(value)
		tile.Text.Size = UDim2.fromScale(digits >= 4 and 0.84 or (digits == 3 and 0.78 or 0.6), 0.6)
		tile.Stroke.Color = value >= 128 and C.White or style[1]:Lerp(C.White, 0.5)
		tile.Stroke.Transparency = value >= 128 and 0.1 or 0.4
		tile.Glow.Visible = value >= 128
		tile.Glow.BackgroundColor3 = style[1]
		tile.Rainbow.Enabled = value == 2048
	end

	local function takeTile()
		for _, tile in ipairs(pool) do
			if not tile.Used then
				tile.Used = true
				tile.Frame.Visible = true
				return tile
			end
		end
		local frame = create("Frame", {
			Name = "Tile",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.92 / SIZE, 0.92 / SIZE),
			ZIndex = 6,
			Parent = grid,
		})
		Kit.Corner(frame, UDim.new(0.16, 0))
		local stroke = Kit.Stroke(frame, C.White, 2, 0.4)
		local gradientObj = create("UIGradient", { Rotation = 90, Parent = frame })
		local glow = create("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.16, 1.16),
			BackgroundTransparency = 0.75,
			Visible = false,
			ZIndex = 5,
			Parent = frame,
		})
		Kit.Corner(glow, UDim.new(0.2, 0))
		local rainbow = create("UIGradient", {
			Enabled = false,
			Rotation = 45,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 200)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 90)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 220, 255)),
			}),
			Parent = glow,
		})
		local shine = create("Frame", {
			Position = UDim2.fromScale(0.1, 0.07),
			Size = UDim2.fromScale(0.5, 0.1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.6,
			ZIndex = 7,
			Parent = frame,
		})
		Kit.Corner(shine, UDim.new(1, 0))
		local text = Kit.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.53),
			Size = UDim2.fromScale(0.6, 0.6),
			MaxTextSize = 44,
			ZIndex = 8,
			Parent = frame,
		})
		local tile = {
			Frame = frame,
			Stroke = stroke,
			Gradient = gradientObj,
			Glow = glow,
			Rainbow = rainbow,
			Text = text,
			Scale = create("UIScale", { Parent = frame }),
			Used = true,
			Value = 0,
		}
		table.insert(pool, tile)
		return tile
	end

	local function releaseTile(tile)
		tile.Used = false
		tile.Frame.Visible = false
	end

	local function spawnTile(index: number, value: number)
		local tile = takeTile()
		styleTile(tile, value)
		tile.Frame.Position = cellCenter(index)
		tile.Scale.Scale = 0.1
		Kit.Tween(tile.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		tiles[index] = tile
	end

	local function clearTiles()
		for _, tile in ipairs(pool) do
			releaseTile(tile)
		end
		table.clear(tiles)
	end

	local function rebuildFromSim()
		clearTiles()
		local sim = st.Sim
		for index = 1, SIZE * SIZE do
			local value = sim.Cells[index]
			if value > 0 then
				local tile = takeTile()
				styleTile(tile, value)
				tile.Frame.Position = cellCenter(index)
				tile.Scale.Scale = 1
				tiles[index] = tile
			end
		end
	end

	----------------------------------------------------------------------
	-- Coups
	----------------------------------------------------------------------
	local function refreshHud()
		local sim = st.Sim
		if not sim or not st.Rules then
			return
		end
		kit:SetStat("Primary", Kit.FormatNumber(sim.Score))
		kit:SetStat("A", kit:NextStarText(sim.MaxTile, st.Rules.Thresholds))
		kit:SetStat("B", "🏅 " .. tostring(sim.MaxTile))
	end

	-- Termine l'animation en cours tout de suite (coup suivant très rapide)
	local function completeAnim()
		local anim = st.Anim
		if not anim then
			return
		end
		st.Anim = nil
		for _, move in ipairs(anim.Moving) do
			move.Tile.Frame.Position = cellCenter(move.To)
		end
		for _, tile in ipairs(anim.Dying) do
			releaseTile(tile)
		end
		local best = 0
		for _, entry in ipairs(anim.Upgrades) do
			styleTile(entry.Tile, entry.Value)
			entry.Tile.Scale.Scale = 1.22
			Kit.Tween(entry.Tile.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			best = math.max(best, entry.Value)
			if entry.Value >= 128 then
				kit:Burst(entry.Tile.Frame, (TILE_STYLE[entry.Value] or BIG_STYLE)[1], 10)
			end
		end
		if anim.Spawn then
			spawnTile(anim.Spawn[1], anim.Spawn[2])
		end
		if best > 0 then
			kit:Sound("Pop", 0.9 + math.min(math.log(best, 2), 11) * 0.05)
		end
	end

	local function endRun(generation: number, reason: string)
		st.Playing = false
		if reason == "target" then
			kit:Mood("🥳", T("You made the %s tile!", tostring(st.Rules.Target)))
			kit:Confetti(20)
		elseif reason == "stuck" then
			kit:Mood("😵", T("No more moves!"))
			kit:Shake(board, 6)
		else
			kit:Mood("😊", T("Nice run!"))
		end
		local token = st.Token
		local moves = table.concat(st.Moves)
		task.spawn(function()
			local ok, result = kit:Invoke("solo:finish", { Token = token, Moves = moves })
			if generation ~= st.Generation or not kit.Alive then
				return
			end
			if not ok or type(result) ~= "table" then
				kit:Notify(type(result) == "string" and result or T("Something went wrong"), C.Red)
				kit:ShowPicker()
				return
			end
			task.wait(0.8)
			if generation == st.Generation then
				kit:ShowResult(result)
			end
		end)
	end

	local function play(dir: number)
		if not st.Playing or not st.Sim then
			return
		end
		completeAnim()
		local sim = st.Sim
		local previousMax = sim.MaxTile
		local moved, info = Logic.G2048Move(sim, dir)
		if not moved then
			kit:Shake(board, 3)
			return
		end
		table.insert(st.Moves, Logic.G2048Chars[dir])
		-- Prépare le glissement
		local anim = { T = 0, Moving = {}, Dying = {}, Upgrades = {}, Spawn = info.Spawn }
		local newTiles = {}
		for _, slide in ipairs(info.Slides) do
			local from, to, value, merged = slide[1], slide[2], slide[3], slide[4]
			local tile = tiles[from]
			if tile then
				table.insert(anim.Moving, { Tile = tile, From = from, To = to })
				if merged then
					table.insert(anim.Dying, tile)
					local survivor = newTiles[to]
					if survivor then
						table.insert(anim.Upgrades, { Tile = survivor, Value = value * 2 })
					end
				else
					newTiles[to] = tile
				end
			end
		end
		tiles = newTiles
		st.Anim = anim
		if info.Gain > 0 then
			kit:SetStat("Primary", Kit.FormatNumber(sim.Score), true)
			kit:Float(board, "+" .. tostring(info.Gain), C.Yellow)
		end
		refreshHud()
		if sim.MaxTile > previousMax then
			kit:SetStat("B", "🏅 " .. tostring(sim.MaxTile), true)
			for index, threshold in ipairs(st.Rules.Thresholds) do
				if sim.MaxTile == threshold and index < 3 then
					kit:Mood("🤩", T("%d ⭐ unlocked!", index))
					kit:Sound("Bonus")
				end
			end
		end
		local generation = st.Generation
		if sim.MaxTile >= st.Rules.Target then
			task.delay(SLIDE_TIME + 0.15, function()
				if generation == st.Generation and st.Playing then
					completeAnim()
					endRun(generation, "target")
				end
			end)
		elseif not Logic.G2048CanMove(sim) then
			task.delay(SLIDE_TIME + 0.3, function()
				if generation == st.Generation and st.Playing then
					completeAnim()
					endRun(generation, "stuck")
				end
			end)
		end
	end

	kit:OnKey(function(key)
		local dir = Kit.KeyDirections[key]
		if dir then
			play(dir)
		end
	end)
	kit:OnSwipe(board, play)

	finishButton.Activated:Connect(function()
		if not st.Playing then
			return
		end
		kit:Sound("Click")
		completeAnim()
		endRun(st.Generation, "finish")
	end)

	function startGame(difficulty: string)
		local rules = kit.GameRules.Difficulties[difficulty]
		st.Generation += 1
		local generation = st.Generation
		st.Rules = rules
		st.Moves = {}
		st.Token = nil
		st.Playing = false
		st.Anim = nil
		clearTiles()
		st.Sim = Logic.G2048New(1, SIZE)
		st.Sim.Cells = table.create(SIZE * SIZE, 0)
		st.Sim.MaxTile = 0
		refreshHud()
		kit:Mood("😊", T("Slide to merge equal tiles. Goal: %s!", tostring(rules.Target)))
		kit:Sound("Open")
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
			st.Sim = Logic.G2048New(reply.Seed, SIZE)
			clearTiles()
			for _, initial in ipairs(st.Sim.Initial) do
				if initial[1] then
					spawnTile(initial[1], initial[2])
				end
			end
			st.Playing = true
			refreshHud()
		end)
	end

	-- Boucle : glissements
	kit:OnFrame(function(dt)
		local anim = st.Anim
		if not anim then
			return
		end
		anim.T += dt
		local k = math.min(anim.T / SLIDE_TIME, 1)
		local eased = 1 - (1 - k) * (1 - k)
		for _, move in ipairs(anim.Moving) do
			local ax, ay = (move.From - 1) % SIZE, (move.From - 1) // SIZE
			local bx, by = (move.To - 1) % SIZE, (move.To - 1) // SIZE
			move.Tile.Frame.Position = UDim2.fromScale(
				(ax + (bx - ax) * eased + 0.5) / SIZE,
				(ay + (by - ay) * eased + 0.5) / SIZE
			)
		end
		if k >= 1 then
			completeAnim()
		end
	end)

	-- Premier affichage : une jolie grille d'exemple
	st.Rules = Logic.Games.Game2048.Difficulties.Normal
	st.Sim = Logic.G2048New(1, SIZE)
	st.Sim.Cells = { 2, 4, 8, 0, 0, 16, 32, 0, 0, 0, 64, 128, 0, 0, 0, 256 }
	st.Sim.MaxTile = 256
	rebuildFromSim()
	refreshHud()
	kit:Mood("😊", T("Slide to merge equal tiles."), false)
	kit:ShowPicker()

	return {
		Destroy = function()
			st.Generation += 1
			st.Playing = false
			kit:Destroy()
		end,
	}
end

return Module
