--[[
	Solo_Kit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Kit

	🕹️ Boîte à outils commune aux mini-jeux SOLO de l'arcade (style
	"arcade kawaii" sur fond néon sombre) :
	  - colonne de gauche (HUD) : icône + nom du jeu, difficulté, record,
	    une grosse tuile (score...) et deux petites, zone "Extra" pour les
	    commandes propres au jeu, boutons ↻ Rejouer / 🎚️ Difficulté ;
	  - zone de jeu (Area) : le module du jeu y construit son plateau ;
	  - écran de choix de la difficulté (3 cartes : détails, récompense, record) ;
	  - écran de fin (étoiles, score, record, 🎟️ tickets et 🧠 Dopamine gagnés) ;
	  - compte à rebours 3-2-1, confettis et "+1" (cadres RÉUTILISÉS),
	    secousse, UNE seule boucle d'animation (RenderStepped) par jeu.

	Utilisation (dans un module Solo_<Id>) :
	  local kit = Kit.new(container, api, spec)
	  spec = { Id, Details(difficulty, rules) -> string, Help, Primary, SmallA, SmallB,
	           OnPlay(difficulty), OnPicker(), BestText(value) -> string,
	           ScoreText(result) -> string, NoStarHint(rules) -> string? }
	  kit:OnFrame(fn(dt)) / kit:SetStat("Primary" | "A" | "B", texte) / kit:ShowResult(result)
	  kit:Invoke(action, arg) (ne plante jamais) / kit:Burst(guiObject, couleur) / kit:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Logic = require(script.Parent.Solo_Logic)

local NumberFormatter = nil
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("NumberFormatter")
	if module then
		local ok, result = pcall(require, module)
		if ok then
			NumberFormatter = result
		end
	end
end

local Kit = {}
Kit.__index = Kit
Kit.Logic = Logic

-- Palette "néon kawaii" (fond sombre, couleurs pastel lumineuses)
local C = {
	BgTop = Color3.fromRGB(44, 24, 92),
	BgBottom = Color3.fromRGB(18, 11, 44),
	Card = Color3.fromRGB(46, 30, 94),
	CardLight = Color3.fromRGB(66, 46, 128),
	CardDark = Color3.fromRGB(28, 18, 62),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 176, 240),
	Pink = Color3.fromRGB(255, 102, 190),
	Cyan = Color3.fromRGB(86, 228, 255),
	Yellow = Color3.fromRGB(255, 218, 84),
	Mint = Color3.fromRGB(96, 242, 178),
	Lilac = Color3.fromRGB(178, 142, 255),
	Orange = Color3.fromRGB(255, 160, 84),
	Red = Color3.fromRGB(255, 86, 118),
	Gold = Color3.fromRGB(255, 200, 60),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}
Kit.Colors = C
Kit.FontTitle = Enum.Font.FredokaOne
Kit.FontBody = Enum.Font.BuilderSansBold

local CONFETTI = { C.Pink, C.Cyan, C.Yellow, C.Mint, C.Lilac, C.Orange }

-- Mémorise la dernière difficulté choisie par jeu (le temps de la session)
local lastDifficulty: { [string]: string } = {}

----------------------------------------------------------------------
-- Petits constructeurs
----------------------------------------------------------------------

local function create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end
Kit.Create = create

local function corner(parent: Instance, radius: number | UDim)
	return create("UICorner", {
		CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius :: number),
		Parent = parent,
	})
end
Kit.Corner = corner

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end
Kit.Stroke = stroke

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number?)
	return create("UIGradient", {
		Color = ColorSequence.new(a, b),
		Rotation = rotation or 90,
		Parent = parent,
	})
end
Kit.Gradient = gradient

local function label(props: { [string]: any }): TextLabel
	local maxSize = props.MaxTextSize or 28
	props.MaxTextSize = nil
	local final = {
		BackgroundTransparency = 1,
		Font = Kit.FontTitle,
		TextColor3 = C.Text,
		TextScaled = true,
		Text = "",
	}
	for key, value in pairs(props) do
		final[key] = value
	end
	local l = create("TextLabel", final)
	create("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 6, Parent = l })
	return l
end
Kit.Label = label

local function tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end
Kit.Tween = tween

-- Bouton "bonbon" : dégradé, contour clair, léger relief, animation d'appui
local function candyButton(props: { [string]: any }): TextButton
	local color = props.Color or C.Pink
	local button = create("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(120, 36),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Kit.FontTitle,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or C.White,
		TextScaled = true,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	corner(button, props.Radius or 12)
	stroke(button, color:Lerp(C.White, 0.55), 1.5, 0.15)
	gradient(button, color:Lerp(C.White, 0.28), color:Lerp(C.Black, 0.12), 90)
	create("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 18, MinTextSize = 6, Parent = button })
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = button,
	})
	local scale = create("UIScale", { Name = "Press", Parent = button })
	button.MouseEnter:Connect(function()
		tween(scale, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.07, { Scale = 0.93 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	return button
end
Kit.Button = candyButton

----------------------------------------------------------------------
-- Formats
----------------------------------------------------------------------

function Kit.FormatNumber(value: number): string
	if NumberFormatter and type(NumberFormatter.Format) == "function" then
		local ok, text = pcall(NumberFormatter.Format, value)
		if ok and type(text) == "string" then
			return text
		end
	end
	return tostring(math.floor(value + 0.5))
end

function Kit.FormatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Temps précis au dixième ("42.3s" ou "1:02.3")
function Kit.FormatTime(seconds: number): string
	local s = math.max(0, seconds)
	if s < 60 then
		return string.format("%.1fs", s)
	end
	return string.format("%d:%04.1f", math.floor(s / 60), s % 60)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function Kit.new(container: Frame, api, spec)
	local self = setmetatable({}, Kit)
	self.Api = api or {}
	self.Spec = spec
	self.Id = spec.Id
	self.Alive = true
	self.Connections = {}
	self.FrameFns = {}
	self.Entry = (type(self.Api.Game) == "table" and self.Api.Game) or {}
	self.GameRules = Logic.Games[spec.Id]
	self.Difficulty = lastDifficulty[spec.Id] or "Normal"
	self.Bests = {}
	self.Accent = self.Entry.Color or C.Pink
	self.Accent2 = self.Entry.Accent or C.Lilac
	self.Touch = UserInputService.TouchEnabled

	local root = create("Frame", {
		Name = "Solo_" .. spec.Id,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.BgBottom,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = container,
	})
	root:SetAttribute("DarkSkinIgnore", true)
	corner(root, 16)
	gradient(root, C.BgTop, C.BgBottom, 90)
	self.Root = root
	self:_BuildDecor()
	self:_BuildHud()

	-- Zone de jeu (le module y construit son plateau)
	local area = create("Frame", {
		Name = "Area",
		Position = UDim2.fromOffset(222, 10),
		Size = UDim2.new(1, -232, 1, -20),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = root,
	})
	self.Area = area

	-- Calque des effets (confettis, "+1")
	self.Fx = create("Frame", {
		Name = "Fx",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	self.Particles = {}
	self.Floats = {}
	self:_BuildCountdown()
	self:_BuildPicker()
	self:_BuildResult()

	-- UNE seule boucle d'animation pour tout le jeu
	table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
		self:_Step(math.min(dt, 0.1))
	end))

	-- Records par difficulté (affichés sur le sélecteur)
	task.spawn(function()
		local ok, info = self:Invoke("solo:info", nil)
		if ok and type(info) == "table" and type(info.Best) == "table" and self.Alive then
			for key, value in pairs(info.Best) do
				if type(key) == "string" and type(value) == "number" then
					self.Bests[key] = value
				end
			end
			self:_RefreshPicker()
			self:_RefreshTitle()
		end
	end)
	return self
end

-- Petites étoiles / bulles de décor (fixes : aucun coût par image)
function Kit:_BuildDecor()
	local decor = create("Frame", {
		Name = "Decor",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = self.Root,
	})
	local rng = Logic.Rng(#self.Id * 131 + 7)
	for index = 1, 22 do
		local size = 2 + rng.Int(0, 3)
		local dot = create("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(rng.Next(), rng.Next()),
			BackgroundColor3 = CONFETTI[index % #CONFETTI + 1],
			BackgroundTransparency = 0.45 + rng.Next() * 0.35,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = decor,
		})
		corner(dot, UDim.new(1, 0))
	end
	-- Grand halo de la couleur du jeu, en bas à droite
	local glow = create("Frame", {
		Size = UDim2.fromScale(0.9, 1.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.72, 0.95),
		BackgroundColor3 = self.Accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = decor,
	})
	corner(glow, UDim.new(1, 0))
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = glow,
	})
end

-- Tuile de stat (étiquette + valeur)
local function statTile(parent: Instance, name: string, position: UDim2, size: UDim2, big: boolean, accent: Color3)
	local tile = create("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = C.Card,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = parent,
	})
	corner(tile, 12)
	stroke(tile, accent, 1.5, 0.45)
	gradient(tile, C.CardLight, C.CardDark, 90)
	local caption = label({
		Name = "Caption",
		Position = UDim2.new(0, 10, 0, big and 6 or 4),
		Size = UDim2.new(1, -20, 0, big and 14 or 12),
		Font = Kit.FontBody,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = big and 13 or 11,
		ZIndex = 3,
		Parent = tile,
	})
	local value = label({
		Name = "Value",
		Position = UDim2.new(0, 10, 0, big and 20 or 16),
		Size = UDim2.new(1, -20, 1, big and -24 or -19),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = big and 36 or 20,
		Text = "-",
		ZIndex = 3,
		Parent = tile,
	})
	create("UIScale", { Name = "Pop", Parent = value })
	return tile, caption, value
end

function Kit:_BuildHud()
	local spec = self.Spec
	local hud = create("Frame", {
		Name = "Hud",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(0, 202, 1, -20),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = self.Root,
	})
	self.Hud = hud

	-- Carte titre : icône + nom + difficulté / record
	local title = create("Frame", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = C.Card,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = hud,
	})
	corner(title, 14)
	gradient(title, self.Accent:Lerp(C.CardDark, 0.35), self.Accent2:Lerp(C.CardDark, 0.55), 20)
	stroke(title, self.Accent:Lerp(C.White, 0.4), 1.5, 0.3)
	local bubble = create("Frame", {
		Name = "Icon",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.82,
		ZIndex = 3,
		Parent = title,
	})
	corner(bubble, UDim.new(1, 0))
	stroke(bubble, C.White, 1.5, 0.55)
	label({
		Size = UDim2.fromScale(0.78, 0.78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Text = self.Entry.Icon or self.GameRules.Icon,
		MaxTextSize = 30,
		ZIndex = 4,
		Parent = bubble,
	})
	self.TitleName = label({
		Position = UDim2.fromOffset(58, 8),
		Size = UDim2.new(1, -64, 0, 22),
		Text = self:T(self.Entry.Name or self.GameRules.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 21,
		ZIndex = 3,
		Parent = title,
	})
	self.TitleSub = label({
		Position = UDim2.fromOffset(58, 32),
		Size = UDim2.new(1, -64, 0, 16),
		Font = Kit.FontBody,
		TextColor3 = C.White,
		TextTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = title,
	})

	-- Tuiles de stats
	local primary, primaryCaption, primaryValue =
		statTile(hud, "Primary", UDim2.fromOffset(0, 66), UDim2.new(1, 0, 0, 64), true, self.Accent)
	local tileA, captionA, valueA = statTile(hud, "A", UDim2.fromOffset(0, 138), UDim2.new(0.5, -4, 0, 48), false, C.Cyan)
	local tileB, captionB, valueB = statTile(hud, "B", UDim2.new(0.5, 4, 0, 138), UDim2.new(0.5, -4, 0, 48), false, C.Yellow)
	primaryCaption.Text = self:T(spec.Primary or "Score")
	captionA.Text = self:T(spec.SmallA or "Next ⭐")
	captionB.Text = self:T(spec.SmallB or "Time")
	self.Stats = {
		Primary = { Tile = primary, Value = primaryValue },
		A = { Tile = tileA, Value = valueA },
		B = { Tile = tileB, Value = valueB },
	}

	-- Zone libre pour les commandes du jeu (drapeau, fin de partie...)
	self.Extra = create("Frame", {
		Name = "Extra",
		Position = UDim2.fromOffset(0, 194),
		Size = UDim2.new(1, 0, 1, -296),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = hud,
	})

	-- Petit compagnon kawaii (humeur + conseil), en bas de la zone Extra
	local buddy = create("Frame", {
		Name = "Buddy",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -44),
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = C.CardDark,
		BackgroundTransparency = 0.25,
		ZIndex = 2,
		Parent = hud,
	})
	corner(buddy, 14)
	stroke(buddy, self.Accent2, 1, 0.6)
	local face = create("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.Yellow,
		ZIndex = 3,
		Parent = buddy,
	})
	corner(face, UDim.new(1, 0))
	gradient(face, C.Yellow:Lerp(C.White, 0.35), C.Orange, 90)
	stroke(face, C.White, 1.5, 0.4)
	local faceText = label({
		Size = UDim2.fromScale(0.86, 0.86),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = "😊",
		MaxTextSize = 30,
		ZIndex = 4,
		Parent = face,
	})
	local faceScale = create("UIScale", { Parent = face })
	local tip = label({
		Name = "Tip",
		Position = UDim2.fromOffset(54, 5),
		Size = UDim2.new(1, -60, 1, -10),
		Font = Kit.FontBody,
		TextColor3 = C.White,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = buddy,
	})
	self.Buddy = { Frame = buddy, Face = face, FaceText = faceText, Scale = faceScale, Tip = tip, Bob = 0 }

	-- Boutons du bas
	local restart = candyButton({
		Name = "Restart",
		Text = "↻ " .. self:T("Restart"),
		Color = self.Accent,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -4, 0, 36),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = hud,
	})
	local difficulty = candyButton({
		Name = "Difficulty",
		Text = "🎚️ " .. self:T("Level"),
		Color = C.CardLight,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -4, 0, 36),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = hud,
	})
	restart.Activated:Connect(function()
		self:Sound("Click")
		self:Play(self.Difficulty)
	end)
	difficulty.Activated:Connect(function()
		self:Sound("Click")
		self:ShowPicker()
	end)
	self:_RefreshTitle()
end

function Kit:_RefreshTitle()
	local info = Logic.DifficultyInfo[self.Difficulty]
	local text = (info and info.Icon or "") .. " " .. self:T(info and info.Name or self.Difficulty)
	local best = self.Bests[self.Id .. ":" .. self.Difficulty]
	if best then
		text ..= "  ·  🏆 " .. self:BestText(best)
	end
	self.TitleSub.Text = text
end

function Kit:BestText(value: number): string
	if self.Spec.BestText then
		return self.Spec.BestText(value)
	end
	return Kit.FormatNumber(value)
end

-- Compte à rebours 3, 2, 1, GO!
function Kit:_BuildCountdown()
	local holder = create("Frame", {
		Name = "Countdown",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = self.Area,
	})
	local text = label({
		Size = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = "3",
		MaxTextSize = 110,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = self.Accent,
		ZIndex = 31,
		Parent = holder,
	})
	self.CountdownFrame = holder
	self.CountdownText = text
	self.CountdownScale = create("UIScale", { Parent = text })
end

function Kit:Countdown(onDone: () -> ())
	self.CountdownId = (self.CountdownId or 0) + 1
	local id = self.CountdownId
	local holder = self.CountdownFrame
	holder.Visible = true
	holder.BackgroundTransparency = 0.55
	task.spawn(function()
		for _, step in ipairs({ "3", "2", "1", "GO!" }) do
			if not self.Alive or self.CountdownId ~= id then
				return
			end
			self.CountdownText.Text = step == "GO!" and self:T("GO!") or step
			self.CountdownText.TextColor3 = step == "GO!" and C.Mint or C.White
			self.CountdownScale.Scale = 1.6
			tween(self.CountdownScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			self:Sound(step == "GO!" and "Bonus" or "Click", step == "GO!" and 1.2 or 1)
			task.wait(step == "GO!" and 0.35 or 0.6)
		end
		if not self.Alive or self.CountdownId ~= id then
			return
		end
		holder.Visible = false
		onDone()
	end)
end

function Kit:CancelCountdown()
	self.CountdownId = (self.CountdownId or 0) + 1
	self.CountdownFrame.Visible = false
end

----------------------------------------------------------------------
-- Sélecteur de difficulté
----------------------------------------------------------------------

function Kit:_BuildPicker()
	local spec = self.Spec
	local picker = create("TextButton", {
		Name = "Picker",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.BgBottom,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 40,
		Parent = self.Root,
	})
	corner(picker, 16)
	gradient(picker, C.BgTop, C.BgBottom, 90)
	self.Picker = picker

	-- En-tête
	local header = create("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = picker,
	})
	local icon = create("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = self.Accent,
		ZIndex = 42,
		Parent = header,
	})
	corner(icon, UDim.new(1, 0))
	gradient(icon, self.Accent:Lerp(C.White, 0.25), self.Accent2, 45)
	stroke(icon, C.White, 2, 0.35)
	label({
		Size = UDim2.fromScale(0.72, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Text = self.Entry.Icon or self.GameRules.Icon,
		MaxTextSize = 30,
		ZIndex = 43,
		Parent = icon,
	})
	self.PickerIconScale = create("UIScale", { Parent = icon })
	label({
		Position = UDim2.fromOffset(20, 48),
		Size = UDim2.new(1, -40, 0, 24),
		Text = self:T("Choose your level"),
		MaxTextSize = 22,
		ZIndex = 42,
		Parent = header,
	})

	-- 3 cartes
	local row = create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(20, 94),
		Size = UDim2.new(1, -40, 1, -130),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = picker,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	self.PickerCards = {}
	for order, difficulty in ipairs(Logic.DifficultyOrder) do
		local info = Logic.DifficultyInfo[difficulty]
		local rules = self.GameRules.Difficulties[difficulty]
		local card = create("TextButton", {
			Name = difficulty,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1 / 3, -10, 1, 0),
			BackgroundColor3 = C.Card,
			LayoutOrder = order,
			ZIndex = 42,
			Parent = row,
		})
		create("UISizeConstraint", { MaxSize = Vector2.new(210, 230), Parent = card })
		corner(card, 16)
		gradient(card, C.CardLight, C.CardDark, 90)
		local cardStroke = stroke(card, info.Color, 2, 0.2)
		local scale = create("UIScale", { Parent = card })
		-- Bandeau coloré en haut
		local band = create("Frame", {
			Name = "Band",
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = info.Color,
			BorderSizePixel = 0,
			ZIndex = 43,
			Parent = card,
		})
		corner(band, 16)
		gradient(band, info.Color:Lerp(C.White, 0.25), info.Color:Lerp(C.Black, 0.1), 90)
		-- (bas du bandeau carré)
		create("Frame", {
			Position = UDim2.new(0, 0, 1, -14),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = info.Color:Lerp(C.Black, 0.08),
			BorderSizePixel = 0,
			ZIndex = 43,
			Parent = band,
		})
		label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 32),
			Text = info.Icon .. " " .. self:T(info.Name),
			MaxTextSize = 22,
			TextStrokeTransparency = 0.7,
			ZIndex = 44,
			Parent = band,
		})
		local details = label({
			Name = "Details",
			Position = UDim2.new(0, 10, 0, 50),
			Size = UDim2.new(1, -20, 1, -126),
			Font = Kit.FontBody,
			TextColor3 = C.White,
			TextWrapped = true,
			LineHeight = 1.15,
			Text = spec.Details and spec.Details(difficulty, rules, self) or "",
			MaxTextSize = 16,
			ZIndex = 43,
			Parent = card,
		})
		local reward = create("Frame", {
			Name = "Reward",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -40),
			Size = UDim2.new(1, -16, 0, 30),
			BackgroundColor3 = C.CardDark,
			BackgroundTransparency = 0.2,
			ZIndex = 43,
			Parent = card,
		})
		corner(reward, UDim.new(1, 0))
		stroke(reward, C.Gold, 1, 0.5)
		local rewardText = label({
			Size = UDim2.new(1, -12, 1, -8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Font = Kit.FontTitle,
			TextColor3 = C.Yellow,
			MaxTextSize = 15,
			ZIndex = 44,
			Parent = reward,
		})
		local best = label({
			Name = "Best",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -16, 0, 22),
			Font = Kit.FontBody,
			TextColor3 = C.TextDim,
			MaxTextSize = 13,
			ZIndex = 43,
			Parent = card,
		})
		card.MouseEnter:Connect(function()
			tween(scale, 0.15, { Scale = 1.04 }, Enum.EasingStyle.Back)
			cardStroke.Transparency = 0
		end)
		card.MouseLeave:Connect(function()
			tween(scale, 0.15, { Scale = 1 })
			cardStroke.Transparency = 0.2
		end)
		card.Activated:Connect(function()
			if not self.Picker.Visible then
				return
			end
			self:Sound("Click")
			self:Play(difficulty)
		end)
		self.PickerCards[difficulty] = { Card = card, Best = best, Reward = rewardText, Details = details, Scale = scale }
	end

	self.PickerHelp = label({
		Name = "Help",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 20),
		Font = Kit.FontBody,
		TextColor3 = C.TextDim,
		Text = spec.Help or "",
		MaxTextSize = 13,
		ZIndex = 41,
		Parent = picker,
	})
	self:_RefreshPicker()
end

function Kit:_RefreshPicker()
	for difficulty, entry in pairs(self.PickerCards) do
		local tickets, seconds = Logic.Reward(tonumber(self.Entry.Tickets) or 0, tonumber(self.Entry.RewardSeconds) or 0, difficulty, 3)
		if tickets > 0 or seconds > 0 then
			entry.Reward.Text = self:T("Up to 🎟️ %s · 🧠 %s", tostring(tickets), tostring(seconds) .. "s")
		else
			entry.Reward.Text = "🎟️ 🧠"
		end
		local best = self.Bests[self.Id .. ":" .. difficulty]
		entry.Best.Text = best and ("🏆 " .. self:T("Best: %s", self:BestText(best))) or self:T("No record yet")
		entry.Card.BackgroundTransparency = 0
		local selected = difficulty == self.Difficulty
		entry.Best.TextColor3 = selected and C.White or C.TextDim
	end
end

function Kit:ShowPicker()
	self:CancelCountdown()
	self:HideResult()
	if self.Spec.OnPicker then
		self.Spec.OnPicker()
	end
	self:_RefreshPicker()
	local picker = self.Picker
	picker.Visible = true
	self.PickerIconScale.Scale = 0.6
	tween(self.PickerIconScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	for index, difficulty in ipairs(Logic.DifficultyOrder) do
		local entry = self.PickerCards[difficulty]
		entry.Scale.Scale = 0.85
		task.delay(0.04 * index, function()
			if self.Alive then
				tween(entry.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end
end

function Kit:HidePicker()
	self.Picker.Visible = false
end

-- Lance une partie (sélecteur, bouton ↻, "Rejouer")
function Kit:Play(difficulty: string)
	if not self.GameRules.Difficulties[difficulty] then
		difficulty = "Normal"
	end
	self.Difficulty = difficulty
	lastDifficulty[self.Id] = difficulty
	self:HidePicker()
	self:HideResult()
	self:CancelCountdown()
	self:_RefreshTitle()
	self.Finished = false
	self.Token = nil
	if self.Spec.OnPlay then
		self.Spec.OnPlay(difficulty)
	end
end

-- Démarre la session serveur ; renvoie la réponse (ou nil + message affiché)
function Kit:StartSession(extra: { [string]: any }?)
	local arg = { Game = self.Id, Difficulty = self.Difficulty }
	if extra then
		for key, value in pairs(extra) do
			arg[key] = value
		end
	end
	self.StartSeq = (self.StartSeq or 0) + 1
	local seq = self.StartSeq
	local ok, reply = self:Invoke("solo:start", arg)
	if not self.Alive or seq ~= self.StartSeq then
		return nil
	end
	if not ok or type(reply) ~= "table" or reply.Token == nil then
		self:Notify(type(reply) == "string" and reply or self:T("Something went wrong"), C.Red)
		return nil
	end
	self.Token = reply.Token
	self.Finished = false
	if type(reply.Best) == "number" then
		self.Bests[self.Id .. ":" .. self.Difficulty] = reply.Best
	end
	self:_RefreshTitle()
	return reply
end

----------------------------------------------------------------------
-- Écran de fin
----------------------------------------------------------------------

function Kit:_BuildResult()
	local overlay = create("TextButton", {
		Name = "Result",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 50,
		Parent = self.Root,
	})
	corner(overlay, 16)
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 420, 1, -24),
		BackgroundColor3 = C.Card,
		ZIndex = 51,
		Parent = overlay,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(420, 330), Parent = card })
	corner(card, 20)
	gradient(card, C.CardLight, C.CardDark, 90)
	local cardStroke = stroke(card, self.Accent, 2.5, 0.1)
	local scale = create("UIScale", { Parent = card })

	local title = label({
		Name = "Title",
		Position = UDim2.new(0, 16, 0.04, 0),
		Size = UDim2.new(1, -32, 0.14, 0),
		MaxTextSize = 34,
		TextStrokeTransparency = 0.5,
		ZIndex = 52,
		Parent = card,
	})
	-- Étoiles
	local starsRow = create("Frame", {
		Name = "Stars",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.new(0.62, 0, 0.2, 0),
		BackgroundTransparency = 1,
		ZIndex = 52,
		Parent = card,
	})
	local stars = {}
	for index = 1, 3 do
		local holder = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((index - 0.5) / 3, index == 2 and 0.45 or 0.58),
			Size = UDim2.fromScale(index == 2 and 0.36 or 0.3, index == 2 and 1.05 or 0.9),
			BackgroundTransparency = 1,
			ZIndex = 52,
			Parent = starsRow,
		})
		create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
		local star = label({
			Size = UDim2.fromScale(1, 1),
			Text = "⭐",
			MaxTextSize = 60,
			ZIndex = 53,
			Parent = holder,
		})
		local starScale = create("UIScale", { Parent = holder })
		stars[index] = { Label = star, Scale = starScale, Holder = holder }
	end
	local score = label({
		Name = "Score",
		Position = UDim2.new(0, 16, 0.43, 0),
		Size = UDim2.new(1, -32, 0.1, 0),
		MaxTextSize = 24,
		ZIndex = 52,
		Parent = card,
	})
	local best = label({
		Name = "Best",
		Position = UDim2.new(0, 16, 0.535, 0),
		Size = UDim2.new(1, -32, 0.065, 0),
		Font = Kit.FontBody,
		TextColor3 = C.TextDim,
		MaxTextSize = 15,
		RichText = true,
		ZIndex = 52,
		Parent = card,
	})
	-- Récompenses
	local rewards = create("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(1, -32, 0.1, 0),
		BackgroundTransparency = 1,
		ZIndex = 52,
		Parent = card,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = rewards,
	})
	local function chip(name: string, color: Color3, order: number)
		local frame = create("Frame", {
			Name = name,
			Size = UDim2.new(0.42, 0, 1, 0),
			BackgroundColor3 = color:Lerp(C.CardDark, 0.55),
			LayoutOrder = order,
			ZIndex = 53,
			Parent = rewards,
		})
		corner(frame, UDim.new(1, 0))
		stroke(frame, color, 1.5, 0.2)
		local text = label({
			Size = UDim2.new(1, -16, 1, -6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = color:Lerp(C.White, 0.35),
			MaxTextSize = 20,
			ZIndex = 54,
			Parent = frame,
		})
		return frame, text
	end
	local ticketChip, ticketText = chip("Tickets", C.Yellow, 1)
	local dopaChip, dopaText = chip("Dopamine", C.Pink, 2)
	local note = label({
		Name = "Note",
		Position = UDim2.new(0, 20, 0.735, 0),
		Size = UDim2.new(1, -40, 0.075, 0),
		Font = Kit.FontBody,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		MaxTextSize = 13,
		ZIndex = 52,
		Parent = card,
	})
	-- Boutons
	local again = candyButton({
		Name = "Again",
		Text = "↻ " .. self:T("Play again"),
		Color = self.Accent,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 0.96, 0),
		Size = UDim2.new(0.5, -24, 0.13, 0),
		MaxTextSize = 18,
		ZIndex = 53,
		Parent = card,
	})
	local change = candyButton({
		Name = "Change",
		Text = "🎚️ " .. self:T("Change level"),
		Color = C.CardLight,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 0.96, 0),
		Size = UDim2.new(0.5, -24, 0.13, 0),
		MaxTextSize = 18,
		ZIndex = 53,
		Parent = card,
	})
	again.Activated:Connect(function()
		self:Sound("Click")
		self:Play(self.Difficulty)
	end)
	change.Activated:Connect(function()
		self:Sound("Click")
		self:ShowPicker()
	end)
	self.ResultUI = {
		Overlay = overlay,
		Card = card,
		Stroke = cardStroke,
		Scale = scale,
		Title = title,
		Stars = stars,
		Score = score,
		Best = best,
		TicketChip = ticketChip,
		TicketText = ticketText,
		DopaChip = dopaChip,
		DopaText = dopaText,
		Note = note,
	}
end

local RESULT_TITLES = { [0] = "Game over", [1] = "You win!", [2] = "Great job!", [3] = "Perfect!" }

function Kit:ShowResult(result)
	if not self.Alive or type(result) ~= "table" then
		return
	end
	self.Finished = true
	self.Token = nil
	local ui = self.ResultUI
	local stars = math.clamp(math.floor(tonumber(result.Stars) or 0), 0, 3)
	local won = stars >= 1
	if type(result.Rejected) == "string" then
		ui.Title.Text = self:T("Too fast!") .. " 🤔"
	else
		ui.Title.Text = self:T(won and RESULT_TITLES[stars] or (self.Spec.LoseTitle or RESULT_TITLES[0]))
			.. (won and " 🎉" or " 💫")
	end
	ui.Title.TextColor3 = won and C.Yellow or C.White
	ui.Stroke.Color = won and C.Yellow or self.Accent
	ui.Score.Text = self.Spec.ScoreText and self.Spec.ScoreText(result) or tostring(result.Score or 0)
	local bestText = ""
	if type(result.Best) == "number" then
		self.Bests[self.Id .. ":" .. self.Difficulty] = result.Best
		bestText = "🏆 " .. self:T("Best: %s", self:BestText(result.Best))
		if result.NewBest then
			bestText ..= '  <font color="#FFDA54"><b>' .. self:T("NEW RECORD!") .. "</b></font>"
		end
	end
	ui.Best.Text = bestText
	local tickets = tonumber(result.Tickets) or 0
	local dopamine = tonumber(result.Dopamine) or 0
	ui.TicketText.Text = "🎟️ +" .. Kit.FormatNumber(tickets)
	ui.DopaText.Text = "🧠 +" .. Kit.FormatNumber(dopamine)
	ui.TicketChip.Visible = won
	ui.DopaChip.Visible = won
	local note = ""
	if type(result.Rejected) == "string" then
		note = self:T(result.Rejected)
	elseif result.Capped then
		note = self:T("Daily rewards reached for this game. Come back tomorrow!")
	elseif not won then
		local hint = self.Spec.NoStarHint and self.Spec.NoStarHint(self.GameRules.Difficulties[self.Difficulty], result)
		note = hint or self:T("Earn at least 1 ⭐ to win rewards!")
	elseif stars < 3 then
		note = self:T("Harder levels and more ⭐ give bigger rewards!")
	end
	ui.Note.Text = note
	ui.Note.Position = UDim2.new(0, 20, won and 0.735 or 0.64, 0)
	ui.Note.Size = UDim2.new(1, -40, won and 0.075 or 0.12, 0)
	self:_RefreshTitle()

	ui.Overlay.Visible = true
	ui.Overlay.BackgroundTransparency = 1
	tween(ui.Overlay, 0.25, { BackgroundTransparency = 0.35 })
	ui.Scale.Scale = 0.7
	tween(ui.Scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	for index, star in ipairs(ui.Stars) do
		local lit = index <= stars
		star.Label.TextTransparency = lit and 0 or 0.72
		star.Label.TextColor3 = C.White
		star.Scale.Scale = 0
		task.delay(0.25 + index * 0.18, function()
			if not self.Alive or not ui.Overlay.Visible then
				return
			end
			tween(star.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			if lit then
				self:Sound("Pop", 0.9 + index * 0.15)
				self:Burst(star.Holder, C.Yellow, 7)
			end
		end)
	end
	if won then
		self:Sound(stars >= 3 and "Jackpot" or "SlotWin")
		task.delay(0.2, function()
			if self.Alive then
				self:Confetti(26)
			end
		end)
	else
		self:Sound("Error")
	end
end

function Kit:HideResult()
	self.ResultUI.Overlay.Visible = false
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------

function Kit:SetStat(key: string, text: string, pop: boolean?)
	local stat = self.Stats[key]
	if not stat then
		return
	end
	if stat.Value.Text ~= text then
		stat.Value.Text = text
		if pop then
			local s = stat.Value:FindFirstChild("Pop")
			if s then
				s.Scale = 1.25
				tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	end
end

function Kit:SetCaption(key: string, text: string)
	local stat = self.Stats[key]
	if stat then
		local caption = stat.Tile:FindFirstChild("Caption")
		if caption then
			caption.Text = text
		end
	end
end

-- Humeur du compagnon (emoji) + petit conseil ; bounce = petit saut
function Kit:Mood(emoji: string, tip: string?, bounce: boolean?)
	local buddy = self.Buddy
	buddy.FaceText.Text = emoji
	if tip then
		buddy.Tip.Text = tip
	end
	if bounce ~= false then
		buddy.Scale.Scale = 1.25
		tween(buddy.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- Texte "Prochaine ⭐" pour les jeux à seuils
function Kit:NextStarText(value: number, thresholds: { number }, format: ((number) -> string)?): string
	for index, threshold in ipairs(thresholds) do
		if value < threshold then
			return string.rep("⭐", index - 1) .. (format and format(threshold) or tostring(threshold))
		end
	end
	return "⭐⭐⭐"
end

----------------------------------------------------------------------
-- Effets (cadres réutilisés)
----------------------------------------------------------------------

-- Position (échelle 0..1 dans Root) du centre d'un objet
function Kit:RootPoint(guiObject: GuiObject): Vector2
	local root = self.Root
	local size = root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return Vector2.new(0.5, 0.5)
	end
	local center = guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2 - root.AbsolutePosition
	return Vector2.new(center.X / size.X, center.Y / size.Y)
end

local function takeFromPool(pool, make)
	for _, item in ipairs(pool) do
		if not item.Active then
			return item
		end
	end
	if #pool >= 64 then
		return nil
	end
	local item = make()
	table.insert(pool, item)
	return item
end

-- Petite explosion de confettis autour d'un objet
function Kit:Burst(guiObject: GuiObject?, color: Color3?, count: number?)
	local origin = guiObject and self:RootPoint(guiObject) or Vector2.new(0.5, 0.5)
	local root = self.Root
	local aspect = root.AbsoluteSize.Y > 0 and root.AbsoluteSize.X / root.AbsoluteSize.Y or 2
	for _ = 1, count or 8 do
		local particle = takeFromPool(self.Particles, function()
			local frame = create("Frame", {
				Size = UDim2.fromOffset(7, 7),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 21,
				Parent = self.Fx,
			})
			corner(frame, 2)
			return { Frame = frame, Active = false }
		end)
		if not particle then
			break
		end
		local angle = math.random() * math.pi * 2
		local speed = 0.18 + math.random() * 0.3
		particle.Active = true
		particle.X, particle.Y = origin.X, origin.Y
		particle.VX = math.cos(angle) * speed / aspect
		particle.VY = math.sin(angle) * speed - 0.25
		particle.Life = 0.55 + math.random() * 0.35
		particle.Age = 0
		particle.Spin = (math.random() - 0.5) * 720
		local frame = particle.Frame
		frame.BackgroundColor3 = (color and math.random() < 0.6) and color or CONFETTI[math.random(1, #CONFETTI)]
		local size = math.random(5, 9)
		frame.Size = UDim2.fromOffset(size, size)
		frame.Visible = true
	end
end

-- Pluie de confettis depuis le haut (victoire)
function Kit:Confetti(count: number)
	local root = self.Root
	local aspect = root.AbsoluteSize.Y > 0 and root.AbsoluteSize.X / root.AbsoluteSize.Y or 2
	for _ = 1, count do
		local particle = takeFromPool(self.Particles, function()
			local frame = create("Frame", {
				Size = UDim2.fromOffset(7, 7),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 21,
				Parent = self.Fx,
			})
			corner(frame, 2)
			return { Frame = frame, Active = false }
		end)
		if not particle then
			break
		end
		particle.Active = true
		particle.X = math.random()
		particle.Y = -0.05 - math.random() * 0.2
		particle.VX = (math.random() - 0.5) * 0.12 / aspect
		particle.VY = 0.25 + math.random() * 0.25
		particle.Life = 1.6 + math.random() * 0.6
		particle.Age = 0
		particle.Spin = (math.random() - 0.5) * 540
		local frame = particle.Frame
		frame.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]
		frame.Size = UDim2.fromOffset(math.random(5, 9), math.random(8, 12))
		frame.Visible = true
	end
end

-- Texte qui monte et s'efface ("+1", "-2"...)
function Kit:Float(guiObject: GuiObject?, text: string, color: Color3?)
	local origin = guiObject and self:RootPoint(guiObject) or Vector2.new(0.5, 0.5)
	local item = takeFromPool(self.Floats, function()
		local l = label({
			Size = UDim2.fromOffset(90, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			MaxTextSize = 26,
			TextStrokeTransparency = 0.3,
			Visible = false,
			ZIndex = 22,
			Parent = self.Fx,
		})
		return { Label = l, Active = false }
	end)
	if not item then
		return
	end
	item.Active = true
	item.X, item.Y = origin.X, origin.Y
	item.Age = 0
	item.Life = 0.8
	local l = item.Label
	l.Text = text
	l.TextColor3 = color or C.White
	l.TextStrokeColor3 = C.BgBottom
	l.Visible = true
end

-- Secousse d'un objet (position d'origine gardée)
function Kit:Shake(guiObject: GuiObject, strength: number?)
	if self.ShakeTarget and self.ShakeTarget ~= guiObject then
		self.ShakeTarget.Position = self.ShakeOrigin
	end
	if self.ShakeTarget ~= guiObject then
		self.ShakeOrigin = guiObject.Position
	end
	self.ShakeTarget = guiObject
	self.ShakeTime = 0.35
	self.ShakeStrength = strength or 6
end

function Kit:_Step(dt: number)
	if not self.Alive then
		return
	end
	for _, fn in ipairs(self.FrameFns) do
		local ok, err = pcall(fn, dt)
		if not ok then
			warn("[Solo_" .. self.Id .. "] " .. tostring(err))
		end
	end
	-- Confettis
	for _, particle in ipairs(self.Particles) do
		if particle.Active then
			particle.Age += dt
			if particle.Age >= particle.Life then
				particle.Active = false
				particle.Frame.Visible = false
			else
				particle.VY += 0.9 * dt
				particle.X += particle.VX * dt
				particle.Y += particle.VY * dt
				local frame = particle.Frame
				frame.Position = UDim2.fromScale(particle.X, particle.Y)
				frame.Rotation += particle.Spin * dt
				frame.BackgroundTransparency = math.clamp((particle.Age / particle.Life - 0.6) * 2.5, 0, 1)
			end
		end
	end
	-- Textes flottants
	for _, item in ipairs(self.Floats) do
		if item.Active then
			item.Age += dt
			local k = item.Age / item.Life
			if k >= 1 then
				item.Active = false
				item.Label.Visible = false
			else
				item.Label.Position = UDim2.fromScale(item.X, item.Y - 0.08 * k)
				item.Label.TextTransparency = math.clamp((k - 0.5) * 2, 0, 1)
				item.Label.TextStrokeTransparency = 0.3 + 0.7 * math.clamp((k - 0.5) * 2, 0, 1)
			end
		end
	end
	-- Compagnon qui respire doucement
	local buddy = self.Buddy
	buddy.Bob += dt
	buddy.FaceText.Rotation = math.sin(buddy.Bob * 2.2) * 6

	-- Secousse
	if self.ShakeTarget then
		self.ShakeTime -= dt
		local target = self.ShakeTarget
		if self.ShakeTime <= 0 then
			target.Position = self.ShakeOrigin
			self.ShakeTarget = nil
		else
			local amount = self.ShakeStrength * (self.ShakeTime / 0.35)
			target.Position = self.ShakeOrigin
				+ UDim2.fromOffset(math.random(-100, 100) / 100 * amount, math.random(-100, 100) / 100 * amount)
		end
	end
end

function Kit:OnFrame(fn: (number) -> ())
	table.insert(self.FrameFns, fn)
end

----------------------------------------------------------------------
-- Entrées, sons, textes
----------------------------------------------------------------------

-- Touches (flèches / ZQSD / WASD) -> direction 1 haut, 2 droite, 3 bas, 4 gauche
local KEY_DIRECTIONS = {
	[Enum.KeyCode.Up] = 1,
	[Enum.KeyCode.W] = 1,
	[Enum.KeyCode.Z] = 1,
	[Enum.KeyCode.Right] = 2,
	[Enum.KeyCode.D] = 2,
	[Enum.KeyCode.Down] = 3,
	[Enum.KeyCode.S] = 3,
	[Enum.KeyCode.Left] = 4,
	[Enum.KeyCode.A] = 4,
	[Enum.KeyCode.Q] = 4,
}
Kit.KeyDirections = KEY_DIRECTIONS

-- Clavier (ignoré pendant la saisie dans le chat / une zone de texte)
function Kit:OnKey(callback: (Enum.KeyCode) -> ())
	table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.Alive or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		callback(input.KeyCode)
	end))
end

-- Glissés du doigt / de la souris sur un objet -> direction
function Kit:OnSwipe(target: GuiObject, callback: (number) -> ())
	local start: Vector2? = nil
	table.insert(self.Connections, target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			start = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	local function finish(input)
		if not start then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - start
		start = nil
		if delta.Magnitude < 24 then
			return
		end
		if math.abs(delta.X) > math.abs(delta.Y) then
			callback(delta.X > 0 and 2 or 4)
		else
			callback(delta.Y > 0 and 3 or 1)
		end
	end
	table.insert(self.Connections, UserInputService.InputEnded:Connect(finish))
end

function Kit:Invoke(action: string, arg: any): (boolean, any)
	local invoke = self.Api.Invoke
	if type(invoke) ~= "function" then
		return false, nil
	end
	local ok, success, result = pcall(invoke, action, arg)
	if not ok then
		return false, nil
	end
	return success == true, result
end

function Kit:Sound(name: string, pitch: number?)
	local sounds = self.Api.Sounds
	if type(sounds) == "table" and type(sounds.Play) == "function" then
		pcall(sounds.Play, name, pitch)
	end
end

function Kit:Notify(text: string, color: Color3?)
	if type(self.Api.Notify) == "function" then
		pcall(self.Api.Notify, text, color)
	end
end

function Kit:T(text: string, ...): string
	return Kit.Translate(self.Api, text, ...)
end

-- Traduction sans instance (utilisable avant la fin de Kit.new)
function Kit.Translate(api, text: string, ...): string
	local translate = type(api) == "table" and api.T or nil
	if type(translate) == "function" then
		local ok, result = pcall(translate, text, ...)
		if ok and type(result) == "string" then
			return result
		end
	end
	if select("#", ...) > 0 then
		local ok, result = pcall(string.format, text, ...)
		if ok then
			return result
		end
	end
	return text
end

function Kit:Destroy()
	if not self.Alive then
		return
	end
	self.Alive = false
	-- Partie en cours : on la termine côté serveur (sans attendre)
	local token = self.Token
	if token and not self.Finished and self.Spec.QuitArg then
		local arg = self.Spec.QuitArg()
		if type(arg) == "table" then
			arg.Token = token
			task.spawn(function()
				pcall(self.Api.Invoke, "solo:finish", arg)
			end)
		end
	end
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.FrameFns)
	self.Root:Destroy()
end

return Kit
