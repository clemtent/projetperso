--[[
	TownGraphics (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownGraphics

	v9.8 (REALISM98) 🎨 fenêtre "Graphismes / Mode réaliste" ouverte EN
	VILLE (bouton ⚙️ du HUD de la ville) : les fenêtres du clicker sont
	masquées dans Dopamine Town, celle-ci a sa propre ScreenGui
	"TownGraphicsGui" (à garder visible : KEEP_GUIS de TownClient).
	Mêmes réglages que ⚙️ Paramètres > Graphismes (Components/GraphicsControls),
	appliqués tout de suite (météo, miroirs, effets, ombres, détail).
	Fermer : ✕, clic en dehors, Échap / bouton B, ou en sortant de la ville.

	API : TownGraphics.Open() / Close() / Toggle() / IsOpen()
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local TownGraphics = {}

local GUI_NAME = "TownGraphicsGui"
local ACCENT = Theme.Colors.Cyan:Lerp(Theme.Colors.Blue, 0.35)
local WHITE = Color3.new(1, 1, 1)

local gui: ScreenGui? = nil
local card: Frame? = nil
local controls: any = nil
local toastLabel: TextLabel? = nil
local inputConn: RBXScriptConnection? = nil

local function toast(text: string, color: Color3?)
	local label = toastLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = color or Theme.Colors.Text
	label.Visible = true
	task.delay(3, function()
		if toastLabel == label and label.Text == text then
			label.Visible = false
		end
	end)
end

local function build(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = UIUtil.Create("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = playerGui,
	})
	-- voile : un clic en dehors ferme
	local shade = UIUtil.Create("TextButton", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		AutoButtonColor = false,
		Text = "",
		Parent = screen,
	})
	shade.Activated:Connect(function()
		TownGraphics.Close()
	end)
	local box = UIUtil.Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.88, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = screen,
	})
	UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(620, 640), Parent = box })
	UIUtil.Corner(box, Theme.Radius.L)
	UIUtil.Stroke(box, ACCENT:Lerp(Color3.new(0, 0, 0), 0.2), 2, 0.2)
	UIUtil.Shadow(box, 4, 0.75)
	UIUtil.SinkClicks(box)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ACCENT:Lerp(WHITE, 0.86)),
			ColorSequenceKeypoint.new(0.18, WHITE),
			ColorSequenceKeypoint.new(1, WHITE),
		}),
		Parent = box,
	})
	-- en-tête
	UIUtil.Label({
		Name = "Title",
		Text = Locale.T("🎨 Graphics / Realistic mode"),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -80, 0, 28),
		Position = UDim2.fromOffset(18, 14),
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = box,
	})
	UIUtil.Label({
		Name = "Subtitle",
		Text = Locale.T("Mirrors, weather, reflections and detail"),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -80, 0, 18),
		Position = UDim2.fromOffset(18, 44),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = box,
	})
	local close = UIUtil.CloseButton({
		Name = "CloseGraphics",
		Size = 40,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		ZIndex = 4,
	})
	close.Parent = box
	close.Activated:Connect(function()
		TownGraphics.Close()
	end)
	local scroll = UIUtil.Create("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(10, 72),
		Size = UDim2.new(1, -20, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
		Parent = box,
	})
	local list = UIUtil.Create("Frame", {
		Name = "List",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	toastLabel = UIUtil.Create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextSize = 15,
		Visible = false,
		ZIndex = 5,
		Parent = box,
	})
	local GraphicsControls = require(Client.Components.GraphicsControls) :: any
	controls = GraphicsControls.Build(list, { Order = 1, Accent = ACCENT, Toast = toast })
	card = box
	return screen
end

function TownGraphics.IsOpen(): boolean
	local g = gui
	return g ~= nil and g.Enabled
end

function TownGraphics.Open()
	local g = gui
	if not g or g.Parent == nil then
		g = build()
		gui = g
	end
	local screen = g :: ScreenGui
	screen.Enabled = true
	if controls then
		pcall(controls.Refresh)
	end
	local box = card
	if box then
		UIUtil.Pop(box, 0.92, 0.18)
	end
	if not inputConn then
		inputConn = UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				TownGraphics.Close()
			end
		end)
	end
end

function TownGraphics.Close()
	local g = gui
	if g then
		g.Enabled = false
	end
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
end

function TownGraphics.Toggle()
	if TownGraphics.IsOpen() then
		TownGraphics.Close()
	else
		TownGraphics.Open()
	end
end

return TownGraphics
