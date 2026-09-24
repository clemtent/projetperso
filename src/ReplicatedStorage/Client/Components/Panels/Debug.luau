--[[
	Debug (ModuleScript) — "🛠️ Test" (UNIQUEMENT dans Studio)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Debug

	Gros boutons pour tester le jeu sans attendre : Dopamine, tout
	débloquer, Rush, apparitions (étoile, éclair, notif, mail, don), océan,
	coffres, Game Passes de test (activer / désactiver), boost, thème,
	gain hors-ligne simulé, remise à zéro...
	Chaque bouton appelle la RemoteFunction "DebugCommand" (via DebugTools)
	et affiche le message renvoyé par le serveur dans la barre du haut.
	Les mêmes commandes existent dans le chat (/give, /unlockall, /aide...).
	Le panneau n'est enregistré que dans Studio (voir ClientMain).
]]

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local DebugTools = require(script.Parent.Parent.DebugTools)

local Debug = {
	Title = "🛠️ Outils de test",
	Subtitle = "Studio uniquement : jamais visible dans le jeu publié",
	Color = Theme.Colors.Red,
	Size = Vector2.new(740, 580),
}

type Action = {
	Text: string,
	Icon: string,
	Command: string,
	Arg: string?,
	Color: Color3,
	Confirm: boolean?,
	Pass: string?, -- Id du Game Pass (affiche ON / OFF)
}

local SECTIONS = {
	{
		Title = "💧 Dopamine",
		Color = Theme.Colors.Cyan,
		Actions = {
			{ Text = "+1 M", Icon = "💧", Command = "give", Arg = "1e6", Color = Theme.Colors.Cyan },
			{ Text = "+1 B", Icon = "💦", Command = "give", Arg = "1e9", Color = Theme.Colors.Blue },
			{ Text = "+1 T", Icon = "🌊", Command = "give", Arg = "1e12", Color = Theme.Colors.Purple },
			{ Text = "+1 Qa", Icon = "🧠", Command = "give", Arg = "1e15", Color = Theme.Colors.Pink },
		},
	},
	{
		Title = "🚀 Progression",
		Color = Theme.Colors.Green,
		Actions = {
			{ Text = "Tout débloquer", Icon = "🔓", Command = "unlockall", Color = Theme.Colors.Green },
			{ Text = "Rush", Icon = "⚡", Command = "rush", Color = Theme.Colors.Yellow },
			{ Text = "Océan", Icon = "🌊", Command = "detox", Color = Theme.Colors.Cyan },
			{ Text = "+3 coffres", Icon = "📦", Command = "chest", Arg = "3", Color = Theme.Colors.Orange },
			{ Text = "Cadeau dispo", Icon = "🎁", Command = "daily", Color = Theme.Colors.Pink },
			{ Text = "Coin DVD", Icon = "📀", Command = "corner", Color = Theme.Colors.Purple },
			{ Text = "Sauvegarder", Icon = "💾", Command = "save", Color = Theme.Colors.Dark },
		},
	},
	{
		Title = "✨ Apparitions",
		Color = Theme.Colors.Gold,
		Actions = {
			{ Text = "Étoile", Icon = "🌟", Command = "spawn", Arg = "golden", Color = Theme.Colors.Gold },
			{ Text = "Éclair", Icon = "⚡", Command = "spawn", Arg = "lightning", Color = Theme.Colors.Yellow },
			{ Text = "Notif", Icon = "🔔", Command = "spawn", Arg = "notif", Color = Theme.Colors.Blue },
			{ Text = "Mail", Icon = "✉️", Command = "spawn", Arg = "email", Color = Theme.Colors.Orange },
			{ Text = "Don (live)", Icon = "💸", Command = "spawn", Arg = "donation", Color = Theme.Colors.Robux },
		},
	},
	{
		Title = "💎 Robux (simulation)",
		Color = Theme.Colors.Robux,
		Actions = {
			{ Text = "Pass x10", Icon = "🚀", Command = "pass", Arg = "x10", Color = Theme.Colors.Purple, Pass = "X10" },
			{ Text = "Pass x2", Icon = "⚡", Command = "pass", Arg = "x2", Color = Theme.Colors.Blue, Pass = "X2" },
			{ Text = "Auto-clic", Icon = "🤖", Command = "pass", Arg = "autoclick", Color = Theme.Colors.Cyan, Pass = "AutoClick" },
			{ Text = "VIP", Icon = "👑", Command = "pass", Arg = "vip", Color = Theme.Colors.Premium, Pass = "VIP" },
			{ Text = "Boost x5 60 s", Icon = "🔥", Command = "boost", Arg = "5 60", Color = Theme.Colors.Boost },
			{ Text = "Thème Kawaii", Icon = "🌸", Command = "theme", Arg = "kawaii", Color = Theme.Colors.Pink },
		},
	},
	{
		Title = "😴 Hors-ligne",
		Color = Theme.Colors.Purple,
		Actions = {
			{ Text = "Absent 2 h", Icon = "🌙", Command = "offline", Arg = "7200", Color = Theme.Colors.Purple },
			{ Text = "Absent 12 h", Icon = "🛌", Command = "offline", Arg = "43200", Color = Theme.Colors.Blue },
		},
	},
	{
		Title = "⚠️ Danger",
		Color = Theme.Colors.Red,
		Actions = {
			{ Text = "Tout remettre à zéro", Icon = "🧨", Command = "reset", Color = Theme.Colors.Red, Confirm = true },
		},
	},
}

local CONFIRM_TIME = 3 -- secondes pour confirmer une action dangereuse

type Tile = { Action: Action, Button: TextButton, Label: TextLabel, State: Frame? }

local tiles: { Tile } = {}
local statusBar: Frame
local statusIcon: TextLabel
local statusText: TextLabel
local busyCount = 0

----------------------------------------------------------------------
-- Barre de résultat
----------------------------------------------------------------------

local function setStatus(ok: boolean?, text: string)
	if not statusBar then
		return
	end
	local color = ok == nil and Theme.Colors.Blue or (ok and Theme.Colors.Robux or Theme.Colors.Red)
	statusIcon.Text = ok == nil and "⏳" or (ok and "✅" or "❌")
	statusText.Text = text
	statusText.TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35)
	statusBar.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.88)
	local stroke = statusBar:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	UIUtil.Pop(statusBar, 1.03, 0.25)
end

----------------------------------------------------------------------
-- Tuiles
----------------------------------------------------------------------

local function refreshPasses()
	for _, tile in ipairs(tiles) do
		local passId = tile.Action.Pass
		local state = tile.State
		if passId and state then
			local owned = ClientState.HasPass(passId)
			local label = state:FindFirstChild("Label") :: TextLabel?
			if label then
				label.Text = owned and "ON" or "OFF"
			end
			state.BackgroundColor3 = owned and Theme.Colors.Green or Theme.Colors.Disabled
		end
	end
end

local function run(tile: Tile)
	local action = tile.Action
	-- Action dangereuse : deuxième clic pour confirmer
	if action.Confirm and not tile.Button:GetAttribute("Armed") then
		tile.Button:SetAttribute("Armed", true)
		tile.Label.Text = "Sûr ? Reclique !"
		SoundManager.Play("Error", 1)
		UIUtil.Shake(tile.Button)
		task.delay(CONFIRM_TIME, function()
			if tile.Button:GetAttribute("Armed") then
				tile.Button:SetAttribute("Armed", nil)
				tile.Label.Text = action.Text
			end
		end)
		return
	end
	tile.Button:SetAttribute("Armed", nil)
	tile.Label.Text = action.Text

	SoundManager.Play("Click", 1.2)
	busyCount += 1
	setStatus(nil, "/" .. action.Command .. (action.Arg and (" " .. action.Arg) or "") .. " ...")
	task.spawn(function()
		local ok, message = DebugTools.Run(action.Command, action.Arg)
		busyCount -= 1
		setStatus(ok, message)
		if ok then
			SoundManager.Play("Bonus", 1.3)
		else
			SoundManager.Play("Error", 0.8)
			if tile.Button.Parent then
				UIUtil.Shake(tile.Button)
			end
		end
	end)
end

local function buildTile(grid: Frame, action: Action, order: number)
	local button = UIUtil.Create("TextButton", {
		Name = action.Command .. (action.Arg or ""),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	})
	UIUtil.Corner(button, Theme.Radius.M)
	UIUtil.Stroke(button, action.Color:Lerp(Color3.new(0, 0, 0), 0.3), 1.5, 0.2)
	UIUtil.SoftGradient(button, action.Color, 90)
	UIUtil.AnimateButton(button, 1.04, 0.94)

	local icon = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		ZIndex = 2,
		Parent = button,
	})
	UIUtil.Corner(icon, UDim.new(1, 0))
	UIUtil.Label({
		Text = action.Icon,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		MaxTextSize = 20,
		ZIndex = 3,
		Parent = icon,
	})
	local label = UIUtil.Label({
		Name = "Text",
		Text = action.Text,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.ContrastText(action.Color),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, action.Pass and -96 or -54, 0, 22),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 48, 0.5, 0),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = button,
	})
	local contrast = Theme.ContrastText(action.Color)
	if contrast == Theme.Colors.TextLight then
		local stroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 1, 0.6)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end

	local state: Frame? = nil
	if action.Pass then
		local chip = UIUtil.Chip({
			Name = "State",
			Text = "OFF",
			Color = Theme.Colors.Disabled,
			TextColor3 = Theme.Colors.TextLight,
			Height = 20,
			TextSize = 12,
			ZIndex = 3,
			Parent = button,
		})
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -8, 0.5, 0)
		state = chip
	end

	local tile: Tile = { Action = action, Button = button, Label = label, State = state }
	button.Activated:Connect(function()
		run(tile)
	end)
	table.insert(tiles, tile)
end

----------------------------------------------------------------------
-- API du panneau
----------------------------------------------------------------------

function Debug.Build(content: Frame)
	-- Barre de résultat
	statusBar = UIUtil.Create("Frame", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = content,
	})
	UIUtil.Corner(statusBar, Theme.Radius.M)
	UIUtil.Stroke(statusBar, Theme.Colors.Divider, 1.5)
	statusIcon = UIUtil.Label({
		Text = "🛠️",
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		MaxTextSize = 20,
		Parent = statusBar,
	})
	statusText = UIUtil.Label({
		Text = "Clique un bouton : le message du serveur s'affiche ici.",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -56, 1, -10),
		Position = UDim2.fromOffset(44, 5),
		MaxTextSize = 15,
		Parent = statusBar,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Name = "Actions",
		Size = UDim2.new(1, 0, 1, -(48 + 30)),
		Position = UDim2.fromOffset(0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Red,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
		Parent = list,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	local order = 0
	for _, section in ipairs(SECTIONS) do
		order += 1
		UIUtil.SectionHeader(list, section.Title, order, section.Color)
		order += 1
		local grid = UIUtil.Create("Frame", {
			Name = "Grid",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = list,
		})
		UIUtil.Create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -8, 0, 50),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for index, action in ipairs(section.Actions) do
			buildTile(grid, action :: Action, index)
		end
	end

	-- Aide : commandes de chat
	local help = UIUtil.Create("TextLabel", {
		Name = "ChatHelp",
		Text = "💬 Dans le chat : " .. DebugTools.HelpText(),
		Font = Theme.Fonts.Body,
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Parent = content,
	})
	help.TextTruncate = Enum.TextTruncate.AtEnd

	-- Résultat des commandes lancées depuis le chat aussi
	DebugTools.Ran:Connect(function(command: string, argument: string, ok: boolean, message: string)
		if busyCount == 0 then
			setStatus(ok, "/" .. command .. (argument ~= "" and (" " .. argument) or "") .. " → " .. message)
		end
	end)
	refreshPasses()
end

function Debug.Update(_data)
	refreshPasses()
end

function Debug.OnOpen()
	refreshPasses()
end

return Debug
