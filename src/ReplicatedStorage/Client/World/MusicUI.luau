--[[
	MusicUI (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicUI

	🎵 Interface de la scène musicale (v9.9, MUSIC99) : ScreenGui
	"MusicStageGui" (TownClient : KEEP_GUIS).
	  - PANNEAU D'INSTRUMENT (en bas, PC et téléphone) : clavier (piano,
	    synthé, xylophone : 2 octaves + 5 notes, touches noires par-dessus),
	    pads de batterie, accords + notes de solo (guitare), notes de basse,
	    boucles et effets (DJ). Chaque touche montre sa touche du clavier
	    (UserInputService:GetStringForKeyCode : AZERTY / QWERTY justes) ;
	    au doigt : on touche (InputBegan : aucune latence). Barre du haut :
	    instrument, "🎵 Jouer une musique", octave ◀ ▶, "✖ Se lever".
	  - CHOIX DES MORCEAUX (carte au centre) : les 8 morceaux (▶), "🔁
	    Enchaîner", "⏹ Stop", et la 📻 radio lofi (Config.Music) sur la scène.
	  - PASTILLE "en cours" (en haut) : titre + barre de progression.

	API :
	  MusicUI.new(callbacks) -> ui     callbacks = { Note(value, vel),
	    Leave(), Picker(), Song(id, mode), StopSong(), Radio(index),
	    Octave(delta), Chain(on) }
	  ui:Open(stationId, layout) / ui:Close() / ui:IsOpen()
	  ui:Flash(value) / ui:SetLoop(index) / ui:SetOctaveText(text)
	  ui:OpenPicker(state) / ui:ClosePicker() / ui:IsPickerOpen()
	  ui:SetNowPlaying(text?, progress?)
	  ui:Destroy()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local MusicData = require(ReplicatedStorage.Shared.MusicData)

local MusicUI = {}
MusicUI.__index = MusicUI

local PINK = Color3.fromRGB(255, 132, 184)
local HOT = Color3.fromRGB(236, 72, 140)
local INK = Color3.fromRGB(70, 44, 82)
local CARD = Color3.fromRGB(255, 250, 253)
local WHITE = Color3.fromRGB(255, 255, 255)
local DARK = Color3.fromRGB(34, 30, 44)
local MINT = Color3.fromRGB(110, 210, 170)

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function keyLabel(kc: Enum.KeyCode?): string
	if not kc then
		return ""
	end
	local ok, s = pcall(function()
		return UserInputService:GetStringForKeyCode(kc)
	end)
	if ok and type(s) == "string" and s ~= "" then
		return string.upper(s)
	end
	local name = kc.Name
	local digits = { Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Comma = "," }
	return digits[name] or name
end

local function corner(p: Instance, r: number)
	UIUtil.Corner(p, UDim.new(0, r))
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font?, scaled: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = color
	l.TextScaled = scaled ~= false
	l.Text = value
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, color: Color3, textColor: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = textColor or WHITE
	b.TextScaled = true
	b.Text = label
	b.Parent = parent
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	return b
end

-- Appui immédiat (souris ou doigt) : InputBegan, pas Activated
local function onPress(self: any, b: GuiObject, fn: () -> ())
	table.insert(self.Conns, b.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			fn()
		end
	end))
end

function MusicUI.new(callbacks: any)
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "MusicStageGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 24
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	local self = setmetatable({
		Screen = screen,
		Cb = callbacks,
		Conns = {} :: { RBXScriptConnection },
		PanelConns = {} :: { RBXScriptConnection },
		Buttons = {} :: { [number]: { GuiObject } },
		Flashes = {} :: { [GuiObject]: number },
		Panel = nil :: Frame?,
		Picker = nil :: Frame?,
		Station = nil :: string?,
		Loop = 0,
		PickerState = nil :: any,
	}, MusicUI)
	-- pastille "en cours"
	local chip = Instance.new("Frame")
	chip.Name = "NowPlaying"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 58)
	chip.Size = UDim2.fromOffset(330, 44)
	chip.BackgroundColor3 = DARK
	chip.BackgroundTransparency = 0.12
	chip.Visible = false
	chip.Parent = screen
	corner(chip, 22)
	UIUtil.Stroke(chip, PINK, 2, 0)
	local chipText = text(chip, "Text", "", UDim2.fromOffset(14, 5), UDim2.new(1, -28, 0, 24), WHITE, Enum.Font.GothamBold)
	local bar = Instance.new("Frame")
	bar.Name = "Track"
	bar.Position = UDim2.new(0, 16, 1, -11)
	bar.Size = UDim2.new(1, -32, 0, 4)
	bar.BackgroundColor3 = Color3.fromRGB(80, 70, 96)
	bar.BorderSizePixel = 0
	bar.Parent = chip
	corner(bar, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = PINK
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 2)
	self.Chip = { Frame = chip, Text = chipText, Fill = fill }
	return self
end

function MusicUI.IsOpen(self: any): boolean
	return self.Panel ~= nil
end

function MusicUI.IsPickerOpen(self: any): boolean
	return self.Picker ~= nil
end

local function phone(self: any): boolean
	local size = self.Screen.AbsoluteSize
	return size.X < 820 or size.Y < 500 or UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

----------------------------------------------------------------------
-- Panneau d'instrument
----------------------------------------------------------------------

-- layout = { Kind = "keys", Low, Count, Keys = { [note] = KeyCode } }
--        | { Kind = "pads", Rows = { { { Value, Label, KeyCode, Color?, Wide? } } } }
function MusicUI.Open(self: any, station: string, layout: any)
	self:Close()
	self.Station = station
	local st = MusicData.STATIONS[station]
	local small = phone(self)
	local screenSize = self.Screen.AbsoluteSize
	local width = math.clamp(screenSize.X - 16, 320, 1000)
	local height = small and math.clamp(screenSize.Y * 0.46, 170, 300) or 262
	local panel = Instance.new("Frame")
	panel.Name = "InstrumentPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -8)
	panel.Size = UDim2.fromOffset(width, height)
	panel.BackgroundColor3 = CARD
	panel.BackgroundTransparency = 0.04
	panel.Parent = self.Screen
	corner(panel, 18)
	UIUtil.Stroke(panel, PINK, 3, 0)
	UIUtil.SinkClicks(panel)
	self.Panel = panel
	-- barre du haut
	local barH = small and 34 or 40
	local title = text(panel, "Title", st.Icon .. " " .. T(st.Name), UDim2.fromOffset(14, 6), UDim2.new(0.34, -14, 0, barH - 6), HOT)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local leave = button(panel, "Leave", T("✖ Stand up"), Color3.fromRGB(226, 90, 110))
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -10, 0, 6)
	leave.Size = UDim2.new(0.2, 0, 0, barH - 6)
	onPress(self, leave, function()
		self.Cb.Leave()
	end)
	local songs = button(panel, "Songs", T("▶️ Play a song"), PINK)
	songs.AnchorPoint = Vector2.new(1, 0)
	songs.Position = UDim2.new(0.8, -18, 0, 6)
	songs.Size = UDim2.new(0.24, 0, 0, barH - 6)
	onPress(self, songs, function()
		self.Cb.Picker()
	end)
	if layout.Kind == "keys" then
		local down = button(panel, "OctDown", "◀", Color3.fromRGB(150, 120, 200))
		down.Position = UDim2.new(0.34, 4, 0, 6)
		down.Size = UDim2.fromOffset(barH, barH - 6)
		local oct = text(panel, "Octave", "", UDim2.new(0.34, barH + 8, 0, 8), UDim2.fromOffset(small and 70 or 96, barH - 10), INK, Enum.Font.GothamBold)
		local up = button(panel, "OctUp", "▶", Color3.fromRGB(150, 120, 200))
		up.Position = UDim2.new(0.34, barH + (small and 82 or 108), 0, 6)
		up.Size = UDim2.fromOffset(barH, barH - 6)
		onPress(self, down, function()
			self.Cb.Octave(-1)
		end)
		onPress(self, up, function()
			self.Cb.Octave(1)
		end)
		self.OctaveLabel = oct
	end
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(10, barH + 6)
	body.Size = UDim2.new(1, -20, 1, -(barH + 14))
	body.Parent = panel
	self.Buttons = {}
	if layout.Kind == "keys" then
		self:BuildKeys(body, layout)
	else
		self:BuildPads(body, layout)
	end
	if not small then
		local hint = text(panel, "Hint", T("Keyboard keys play too · Space = stand up"), UDim2.new(0, 0, 1, 2), UDim2.new(1, 0, 0, 16), INK, Enum.Font.GothamBold)
		hint.TextTransparency = 0.25
	end
	UIUtil.Pop(panel, 0.9, 0.18)
end

function MusicUI.BuildKeys(self: any, body: Frame, layout: any)
	local low, count = layout.Low, layout.Count
	local whites = {}
	for n = low, low + count - 1 do
		local pc = n % 12
		if not (pc == 1 or pc == 3 or pc == 6 or pc == 8 or pc == 10) then
			table.insert(whites, n)
		end
	end
	local nw = #whites
	local index = {}
	for i, n in ipairs(whites) do
		index[n] = i
	end
	for i, n in ipairs(whites) do
		local k = Instance.new("TextButton")
		k.Name = "White"
		k.AutoButtonColor = false
		k.BackgroundColor3 = WHITE
		k.Position = UDim2.new((i - 1) / nw, 1, 0, 0)
		k.Size = UDim2.new(1 / nw, -2, 1, 0)
		k.Text = ""
		k.ZIndex = 2
		k.Parent = body
		corner(k, 6)
		UIUtil.Stroke(k, Color3.fromRGB(200, 190, 210), 1, 0)
		local name = MusicData.NoteName(n, Locale.IsFrench())
		local lab = text(k, "Note", (n % 12 == 0) and name or string.gsub(name, "%-?%d+$", ""), UDim2.new(0, 2, 1, -38), UDim2.new(1, -4, 0, 16), Color3.fromRGB(150, 130, 160), Enum.Font.GothamBold)
		lab.ZIndex = 3
		local key = text(k, "Key", keyLabel(layout.Keys and layout.Keys[n]), UDim2.new(0, 2, 1, -20), UDim2.new(1, -4, 0, 16), HOT, Enum.Font.GothamBold)
		key.ZIndex = 3
		k:SetAttribute("Base", WHITE)
		self.Buttons[n] = { k }
		onPress(self, k, function()
			self.Cb.Note(n, 0.85)
		end)
	end
	for n = low, low + count - 1 do
		local pc = n % 12
		if pc == 1 or pc == 3 or pc == 6 or pc == 8 or pc == 10 then
			local left = index[n - 1]
			if left then
				local k = Instance.new("TextButton")
				k.Name = "Black"
				k.AutoButtonColor = false
				k.BackgroundColor3 = Color3.fromRGB(30, 26, 38)
				k.AnchorPoint = Vector2.new(0.5, 0)
				k.Position = UDim2.new(left / nw, 0, 0, 0)
				k.Size = UDim2.new(0.62 / nw, 0, 0.6, 0)
				k.Text = ""
				k.ZIndex = 4
				k.Parent = body
				corner(k, 5)
				local key = text(k, "Key", keyLabel(layout.Keys and layout.Keys[n]), UDim2.new(0, 1, 1, -18), UDim2.new(1, -2, 0, 14), PINK, Enum.Font.GothamBold)
				key.ZIndex = 5
				k:SetAttribute("Base", Color3.fromRGB(30, 26, 38))
				self.Buttons[n] = { k }
				onPress(self, k, function()
					self.Cb.Note(n, 0.85)
				end)
			end
		end
	end
end

function MusicUI.BuildPads(self: any, body: Frame, layout: any)
	local rows = layout.Rows
	local nRows = #rows
	for r, row in ipairs(rows) do
		local total = 0
		for _, pad in ipairs(row) do
			total += pad.Wide or 1
		end
		local x = 0
		for _, pad in ipairs(row) do
			local w = (pad.Wide or 1) / total
			local color = pad.Color or Color3.fromRGB(150, 120, 220)
			local b = button(body, "Pad", "", color)
			b.Position = UDim2.new(x, 3, (r - 1) / nRows, 3)
			b.Size = UDim2.new(w, -6, 1 / nRows, -6)
			UIUtil.Stroke(b, WHITE, 2, 0.3)
			local main = text(b, "Label", pad.Label, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.66), WHITE)
			main.ZIndex = 2
			local key = text(b, "Key", keyLabel(pad.KeyCode), UDim2.fromScale(0, 0.66), UDim2.fromScale(1, 0.32), Color3.fromRGB(255, 240, 250), Enum.Font.GothamBold)
			key.ZIndex = 2
			key.TextTransparency = 0.15
			b:SetAttribute("Base", color)
			local list = self.Buttons[pad.Value] or {}
			table.insert(list, b)
			self.Buttons[pad.Value] = list
			onPress(self, b, function()
				self.Cb.Note(pad.Value, 0.9)
			end)
			x += w
		end
	end
end

function MusicUI.Close(self: any)
	if self.Panel then
		self.Panel:Destroy()
		self.Panel = nil
	end
	self.OctaveLabel = nil
	self.Station = nil
	self.Buttons = {}
	table.clear(self.Flashes)
end

function MusicUI.SetOctaveText(self: any, value: string)
	if self.OctaveLabel then
		self.OctaveLabel.Text = value
	end
end

-- Touche / pad qui s'allume (retour visuel de chaque note)
function MusicUI.Flash(self: any, value: number)
	local list = self.Buttons[value]
	if not list then
		return
	end
	for _, b in ipairs(list) do
		b.BackgroundColor3 = PINK
		self.Flashes[b] = os.clock()
	end
end

function MusicUI.SetLoop(self: any, index: number)
	self.Loop = index
	for i = 1, MusicData.DJ_LOOPS do
		for _, b in ipairs(self.Buttons[i] or {}) do
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = i == index and Color3.fromRGB(255, 240, 120) or WHITE
				stroke.Thickness = i == index and 4 or 2
			end
		end
	end
end

-- (appelé à chaque image : les touches reprennent leur couleur)
function MusicUI.Step(self: any)
	local t = os.clock()
	for b, at in pairs(self.Flashes) do
		if t - at > 0.14 then
			local base = b:GetAttribute("Base")
			if typeof(base) == "Color3" then
				b.BackgroundColor3 = base
			end
			self.Flashes[b] = nil
		end
	end
end

----------------------------------------------------------------------
-- Choix des morceaux + radio
----------------------------------------------------------------------

function MusicUI.OpenPicker(self: any, state: any)
	self:ClosePicker()
	self.PickerState = state
	local small = phone(self)
	local screenSize = self.Screen.AbsoluteSize
	local w = math.clamp(screenSize.X - 24, 300, 560)
	local h = math.clamp(screenSize.Y - (small and 40 or 120), 260, 520)
	local dim = Instance.new("TextButton")
	dim.Name = "PickerDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.ZIndex = 20
	dim.Parent = self.Screen
	local card = Instance.new("Frame")
	card.Name = "Picker"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(w, h)
	card.BackgroundColor3 = CARD
	card.ZIndex = 21
	card.Parent = dim
	corner(card, 22)
	UIUtil.Stroke(card, PINK, 3, 0)
	UIUtil.SinkClicks(card)
	table.insert(self.Conns, dim.Activated:Connect(function()
		self:ClosePicker()
	end))
	local title = text(card, "Title", T("🎵 Stage music"), UDim2.fromOffset(18, 12), UDim2.new(1, -80, 0, 34), HOT)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 22
	local close = UIUtil.CloseButton({ Name = "ClosePicker", Size = 36, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), ZIndex = 23 })
	close.Parent = card
	table.insert(self.Conns, close.Activated:Connect(function()
		self:ClosePicker()
	end))
	local sub = text(card, "Sub", T("Everyone near the stage hears it. The instruments play by themselves!"), UDim2.fromOffset(18, 48), UDim2.new(1, -36, 0, 18), INK, Enum.Font.GothamBold)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 22
	local list = Instance.new("ScrollingFrame")
	list.Name = "Songs"
	list.Position = UDim2.fromOffset(12, 74)
	list.Size = UDim2.new(1, -24, 1, -74 - 112)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 22
	list.Parent = card
	local layoutList = Instance.new("UIListLayout")
	layoutList.Padding = UDim.new(0, 6)
	layoutList.SortOrder = Enum.SortOrder.LayoutOrder
	layoutList.Parent = list
	for i, song in ipairs(MusicData.SONGS) do
		local playing = state.SongId == song.Id
		local row = Instance.new("TextButton")
		row.Name = song.Id
		row.LayoutOrder = i
		row.AutoButtonColor = true
		row.Text = ""
		row.Size = UDim2.new(1, -8, 0, small and 44 or 50)
		row.BackgroundColor3 = playing and Color3.fromRGB(255, 226, 240) or WHITE
		row.ZIndex = 22
		row.Parent = list
		corner(row, 12)
		UIUtil.Stroke(row, playing and HOT or Color3.fromRGB(236, 210, 226), 2, 0)
		local icon = text(row, "Icon", song.Icon, UDim2.fromOffset(8, 6), UDim2.new(0, 34, 1, -12), INK)
		icon.ZIndex = 23
		local name = text(row, "Name", T(song.Name), UDim2.fromOffset(50, 4), UDim2.new(1, -140, 0.55, -2), INK)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 23
		local secs = math.floor(MusicData.Duration(song.Id) + 0.5)
		local meta = text(row, "Meta", T(song.Author) .. " · " .. string.format("%d:%02d", secs // 60, secs % 60), UDim2.new(0, 50, 0.55, 0), UDim2.new(1, -140, 0.4, -2), Color3.fromRGB(140, 110, 150), Enum.Font.GothamBold)
		meta.TextXAlignment = Enum.TextXAlignment.Left
		meta.ZIndex = 23
		local play = text(row, "Play", playing and "🔊" or "▶️", UDim2.new(1, -60, 0, 6), UDim2.new(0, 50, 1, -12), HOT)
		play.ZIndex = 23
		table.insert(self.Conns, row.Activated:Connect(function()
			self.Cb.Song(song.Id, self.PickerState and self.PickerState.Chain and "all" or "one")
			self:ClosePicker()
		end))
	end
	-- ligne du bas : enchaîner / stop ; radio
	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.BackgroundTransparency = 1
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, 12, 1, -10)
	bottom.Size = UDim2.new(1, -24, 0, 100)
	bottom.ZIndex = 22
	bottom.Parent = card
	local chain = button(bottom, "Chain", "", Color3.fromRGB(150, 120, 220))
	chain.Size = UDim2.new(0.5, -4, 0, 42)
	chain.ZIndex = 23
	local function refreshChain()
		chain.Text = (self.PickerState.Chain and "🔁 " or "➡️ ") .. (self.PickerState.Chain and T("Play all: on") or T("Play all: off"))
		chain.BackgroundColor3 = self.PickerState.Chain and MINT or Color3.fromRGB(150, 120, 220)
	end
	refreshChain()
	table.insert(self.Conns, chain.Activated:Connect(function()
		self.PickerState.Chain = not self.PickerState.Chain
		refreshChain()
		if self.Cb.Chain then
			self.Cb.Chain(self.PickerState.Chain)
		end
	end))
	local stop = button(bottom, "Stop", T("⏹ Stop"), Color3.fromRGB(226, 90, 110))
	stop.Position = UDim2.new(0.5, 4, 0, 0)
	stop.Size = UDim2.new(0.5, -4, 0, 42)
	stop.ZIndex = 23
	table.insert(self.Conns, stop.Activated:Connect(function()
		self.Cb.StopSong()
		self:ClosePicker()
	end))
	local playlist = Config.Music and Config.Music.Playlist or {}
	local radioOn = type(state.Radio) == "number" and state.Radio > 0
	local track = radioOn and playlist[state.Radio] or nil
	local radio = button(bottom, "Radio", "", radioOn and MINT or Color3.fromRGB(96, 150, 230))
	radio.Position = UDim2.fromOffset(0, 50)
	radio.Size = UDim2.new(1, 0, 0, 44)
	radio.ZIndex = 23
	radio.Text = radioOn and ("📻 " .. T("Stage radio: %s (tap: next)", tostring(track and track.Name or "?"))) or ("📻 " .. T("Stage radio: lo-fi on the speakers"))
	table.insert(self.Conns, radio.Activated:Connect(function()
		local count = #playlist
		if count == 0 then
			return
		end
		local nextIndex = radioOn and (state.Radio % count + 1) or math.random(1, count)
		self.Cb.Radio(nextIndex)
		self:ClosePicker()
	end))
	if radioOn then
		local off = button(bottom, "RadioOff", T("Off"), Color3.fromRGB(226, 90, 110))
		off.AnchorPoint = Vector2.new(1, 0)
		off.Position = UDim2.new(1, -6, 0, 56)
		off.Size = UDim2.fromOffset(70, 32)
		off.ZIndex = 24
		table.insert(self.Conns, off.Activated:Connect(function()
			self.Cb.Radio(0)
			self:ClosePicker()
		end))
	end
	self.Picker = dim
	UIUtil.Pop(card, 0.9, 0.18)
end

function MusicUI.ClosePicker(self: any)
	if self.Picker then
		self.Picker:Destroy()
		self.Picker = nil
	end
end

function MusicUI.SetNowPlaying(self: any, value: string?, progress: number?)
	local chip = self.Chip
	if not value then
		chip.Frame.Visible = false
		return
	end
	chip.Frame.Visible = true
	chip.Text.Text = value
	chip.Fill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
end

function MusicUI.Destroy(self: any)
	self:Close()
	self:ClosePicker()
	UIUtil.DisconnectAll(self.Conns)
	if self.Screen then
		self.Screen:Destroy()
	end
end

return MusicUI
