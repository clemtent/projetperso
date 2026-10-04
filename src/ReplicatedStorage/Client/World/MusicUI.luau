--[[
	MusicUI (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicUI

	🎵 Interface de la scène musicale (v9.9 MUSIC99, refaite en v11 MUSIC11) :
	ScreenGui "MusicStageGui" (TownClient : KEEP_GUIS).

	PANNEAUX D'INSTRUMENTS (v11) : chaque panneau RESSEMBLE à l'instrument.
	  🎹 piano à queue : caisse laquée noire, feutre rouge, touches ivoire et
	     ébène (dégradés, ombres), la touche s'enfonce tant qu'on appuie ;
	     ◀ OCTAVE ▶ + mini-clavier de 88 touches qui montre la plage jouée ;
	     plus on appuie bas sur la touche, plus la note est forte ;
	  🎛️ synthé : châssis gris anthracite, écran LCD (note jouée), boutons
	     rotatifs, touches à liseré cyan ;
	  🎶 xylophone : lames de bois colorées de plus en plus courtes, les
	     dièses au-dessus, clous et tubes résonateurs ;
	  🥁 batterie : le kit VU DU DESSUS, chaque pièce à sa vraie place
	     (charleston à gauche, caisse claire, toms sur la grosse caisse, tom
	     basse à droite, crash et ride en bronze) ; frapper au centre = plus
	     fort ; onde de choc et rebond à chaque coup ;
	  🎸 guitare : cartes d'accords + MANCHE en palissandre (frettes,
	     repères, 6 cordes qui vibrent quand on gratte) avec les notes du
	     solo (pentatonique) à leur vraie place ;
	  🎸 basse : manche à 4 cordes, notes sur les cases ;
	  🎧 DJ : 2 platines (vinyles qui tournent, toucher = scratch), table
	     de mixage avec CROSSFADER (le glisser vite = scratch), 8 pads de
	     boucles lumineux (rock, house, hip-hop, lofi, trap, reggae, disco,
	     techno) et 4 effets.
	  Barre du haut : instrument, VU-mètre (force de chaque coup), "▶️ Jouer
	  une musique", "✖ Se lever". Chaque touche montre sa touche du clavier
	  (GetStringForKeyCode : AZERTY / QWERTY justes). Téléphone : panneau
	  plus bas et compact, tout reste jouable au doigt (InputBegan : aucune
	  latence).

	"JOUER UNE MUSIQUE" (v11) : une vraie discothèque.
	  - barre "EN COURS" : pochette, titre, auteur, genre, progression et
	    temps, ⏭ suivant, ⏹ stop, 🔁 enchaîner ;
	  - filtres par GENRE (pop, rock, électro, hip-hop, lofi…) ;
	  - POCHETTES d'album (dégradé du genre, icône, BPM, durée,
	    instruments) : toucher = jouer maintenant, ➕ = file d'attente ;
	  - FILE D'ATTENTE ("À suivre", partagée par tout le monde) : ✖ retire ;
	  - 📻 radio lofi sur la scène.
	  PASTILLE "en cours" (en haut de l'écran) : titre + barre.

	API :
	  MusicUI.new(callbacks) -> ui     callbacks = { Note(value, vel),
	    Leave(), Picker(), Song(id, mode), StopSong(), Radio(index),
	    Octave(delta), Chain(on), Queue(id), Unqueue(index), Skip() }
	  ui:Open(stationId, layout) / ui:Close() / ui:IsOpen()
	  ui:Flash(value, vel?) / ui:SetLoop(index) / ui:SetOctaveText(text)
	  ui:SetOctaveRange(low, count)
	  ui:OpenPicker(state) / ui:UpdatePicker(state) / ui:ClosePicker()
	  ui:IsPickerOpen()
	  ui:SetNowPlaying(text?, progress?)
	  ui:Step(dt)
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
local WHITE = Color3.fromRGB(255, 255, 255)
local DARK = Color3.fromRGB(34, 30, 44)
local PANEL = Color3.fromRGB(26, 22, 34)
local PANEL2 = Color3.fromRGB(44, 36, 58)
local MINT = Color3.fromRGB(110, 210, 170)
local GOLD = Color3.fromRGB(236, 190, 90)
local CYAN = Color3.fromRGB(90, 220, 255)
local MUTED = Color3.fromRGB(190, 176, 206)
local IVORY = Color3.fromRGB(252, 249, 240)
local EBONY = Color3.fromRGB(22, 20, 26)
local RED_FELT = Color3.fromRGB(150, 24, 40)

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
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

local function corner(p: Instance, r: number | UDim)
	UIUtil.Corner(p, typeof(r) == "UDim" and r or UDim.new(0, r :: number))
end

local function round(p: Instance)
	UIUtil.Corner(p, UDim.new(1, 0))
end

local function gradient(p: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIUtil.Gradient(p, ColorSequence.new(top, bottom), rotation or 90)
end

local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font?, maxSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = color
	l.TextScaled = true
	l.Text = value
	l.ZIndex = (parent:IsA("GuiObject") and (parent :: GuiObject).ZIndex or 1) + 1
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize or 28
	c.MinTextSize = 6
	c.Parent = l
	return l
end

local function button(parent: Instance, name: string, label: string, color: Color3, textColor: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
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
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 22
	c.MinTextSize = 6
	c.Parent = b
	return b
end

-- (écran tactile sans clavier : les badges de touches sont masqués)
local hideKeys = false

-- Badge de touche du clavier (petite pastille)
local function keyBadge(parent: GuiObject, kc: Enum.KeyCode?, pos: UDim2, anchor: Vector2?, dark: boolean?): TextLabel?
	local label = keyLabel(kc)
	if label == "" or hideKeys then
		return nil
	end
	local b = Instance.new("TextLabel")
	b.Name = "KeyBadge"
	b.AnchorPoint = anchor or Vector2.new(0.5, 1)
	b.Position = pos
	b.Size = UDim2.fromOffset(math.max(18, 9 * #label + 8), 16)
	b.BackgroundColor3 = dark and Color3.fromRGB(20, 18, 26) or WHITE
	b.BackgroundTransparency = dark and 0.2 or 0.1
	b.TextColor3 = dark and PINK or HOT
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = label
	b.ZIndex = parent.ZIndex + 3
	b.Parent = parent
	corner(b, 5)
	return b
end

local function phone(self: any): boolean
	local size = self.Screen.AbsoluteSize
	return size.X < 820 or size.Y < 500 or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

-- Position relative (0..1) d'une entrée dans un objet (souris ou doigt)
local function relPos(obj: GuiObject, input: InputObject): Vector2
	local p = input.Position
	local a, s = obj.AbsolutePosition, obj.AbsoluteSize
	return Vector2.new(math.clamp((p.X - a.X) / math.max(1, s.X), 0, 1), math.clamp((p.Y - a.Y) / math.max(1, s.Y), 0, 1))
end

local function isPress(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

-- Appui immédiat (souris ou doigt) : InputBegan ; fn(input)
local function onPress(conns: { RBXScriptConnection }, b: GuiObject, fn: (InputObject) -> ())
	table.insert(conns, b.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			fn(input)
		end
	end))
end

local function onRelease(conns: { RBXScriptConnection }, b: GuiObject, fn: () -> ())
	table.insert(conns, b.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			fn()
		end
	end))
end

-- Clic "normal" (Activated) pour les boutons de menu
local function onClick(conns: { RBXScriptConnection }, b: GuiButton, fn: () -> ())
	table.insert(conns, b.Activated:Connect(fn))
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

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
		PickerConns = {} :: { RBXScriptConnection },
		Buttons = {} :: { [number]: { any } },
		Flashes = {} :: { [any]: number },
		Ripples = {} :: { any },
		Panel = nil :: Frame?,
		Picker = nil :: Frame?,
		Station = nil :: string?,
		Loop = 0,
		Clock = 0,
		Level = 0,
		PickerState = nil :: any,
		Genre = "All",
	}, MusicUI)
	-- pastille "en cours"
	local chip = Instance.new("Frame")
	chip.Name = "NowPlaying"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 58)
	chip.Size = UDim2.fromOffset(340, 46)
	chip.BackgroundColor3 = DARK
	chip.BackgroundTransparency = 0.1
	chip.Visible = false
	chip.Parent = screen
	corner(chip, 23)
	UIUtil.Stroke(chip, PINK, 2, 0)
	local chipText = text(chip, "Text", "", UDim2.fromOffset(16, 5), UDim2.new(1, -32, 0, 24), WHITE, Enum.Font.GothamBold, 18)
	local bar = frame(chip, "Track", UDim2.new(0, 18, 1, -12), UDim2.new(1, -36, 0, 4), Color3.fromRGB(80, 70, 96))
	corner(bar, 2)
	local fill = frame(bar, "Fill", UDim2.new(), UDim2.fromScale(0, 1), PINK)
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

-- Enregistre un élément "jouable" (allumé par Flash)
local function register(self: any, value: number, entry: any)
	local list = self.Buttons[value] or {}
	table.insert(list, entry)
	self.Buttons[value] = list
end

-- Onde de choc (cercle qui grandit et s'efface) sur `host`
local function ripple(self: any, host: GuiObject, vel: number, color: Color3)
	if not host.Parent then
		return
	end
	local r = Instance.new("Frame")
	r.Name = "Ripple"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.fromScale(0.6, 0.6)
	r.BackgroundTransparency = 1
	r.ZIndex = host.ZIndex + 4
	r.Parent = host
	round(r)
	local s = UIUtil.Stroke(r, color, 3, 0)
	table.insert(self.Ripples, { Frame = r, Stroke = s, T0 = self.Clock, Max = 1 + 0.6 * vel })
end

----------------------------------------------------------------------
-- Panneau : cadre commun
----------------------------------------------------------------------

local SKIN: { [string]: { Bg: Color3, Bg2: Color3, Edge: Color3, Accent: Color3 } } = {
	Piano = { Bg = Color3.fromRGB(18, 16, 22), Bg2 = Color3.fromRGB(42, 38, 50), Edge = GOLD, Accent = GOLD },
	Synth = { Bg = Color3.fromRGB(30, 32, 40), Bg2 = Color3.fromRGB(52, 56, 68), Edge = CYAN, Accent = CYAN },
	Xylophone = { Bg = Color3.fromRGB(58, 40, 30), Bg2 = Color3.fromRGB(96, 66, 44), Edge = Color3.fromRGB(255, 200, 120), Accent = Color3.fromRGB(255, 200, 120) },
	Drums = { Bg = Color3.fromRGB(26, 22, 34), Bg2 = Color3.fromRGB(46, 38, 62), Edge = PINK, Accent = PINK },
	Guitar = { Bg = Color3.fromRGB(34, 20, 24), Bg2 = Color3.fromRGB(70, 34, 40), Edge = Color3.fromRGB(255, 120, 120), Accent = Color3.fromRGB(255, 120, 120) },
	Bass = { Bg = Color3.fromRGB(20, 26, 40), Bg2 = Color3.fromRGB(36, 48, 74), Edge = Color3.fromRGB(120, 170, 255), Accent = Color3.fromRGB(120, 170, 255) },
	DJ = { Bg = Color3.fromRGB(14, 14, 20), Bg2 = Color3.fromRGB(34, 30, 48), Edge = Color3.fromRGB(190, 120, 255), Accent = Color3.fromRGB(190, 120, 255) },
}

-- layout : construit par MusicStage (voir layoutFor) ; Kind =
-- "keys" | "drums" | "guitar" | "bass" | "dj"
function MusicUI.Open(self: any, station: string, layout: any)
	self:Close()
	self.Station = station
	local st = MusicData.STATIONS[station]
	local skin = SKIN[station] or SKIN.Drums
	local small = phone(self)
	self.Small = small
	hideKeys = small and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local screenSize = self.Screen.AbsoluteSize
	local width = math.clamp(screenSize.X - (small and 10 or 24), 300, 1080)
	local height = small and math.clamp(screenSize.Y * 0.56, 190, 300) or ((layout.Kind == "drums" or layout.Kind == "guitar") and 350 or (layout.Kind == "dj" and 320 or 300))
	local panel = frame(self.Screen, "InstrumentPanel", UDim2.new(0.5, 0, 1, small and -4 or -22), UDim2.fromOffset(width, height), skin.Bg)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	corner(panel, small and 14 or 20)
	gradient(panel, skin.Bg2, skin.Bg, 90)
	UIUtil.Stroke(panel, skin.Edge, 2, 0.15)
	UIUtil.SinkClicks(panel)
	self.Panel = panel
	-- barre du haut
	local barH = small and 32 or 42
	local top = frame(panel, "TopBar", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, barH + 6), Color3.new(0, 0, 0))
	top.BackgroundTransparency = 1
	local icon = text(top, "Icon", st.Icon, UDim2.fromOffset(10, 4), UDim2.fromOffset(barH, barH - 2), WHITE, nil, 32)
	local title = text(top, "Title", T(st.Name), UDim2.fromOffset(barH + 16, 4), UDim2.new(small and 0.28 or 0.24, 0, 0, small and barH - 12 or barH - 18), WHITE, Enum.Font.FredokaOne, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local sub = text(top, "Sub", "", UDim2.new(0, barH + 16, 0, small and barH - 8 or barH - 13), UDim2.new(small and 0.28 or 0.24, 0, 0, small and 10 or 13), MUTED, Enum.Font.GothamBold, 13)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	self.SubLabel = sub
	local _ = icon
	-- VU-mètre (force des coups)
	local vu = frame(top, "VU", UDim2.new(small and 0.36 or 0.31, 0, 0, 10), UDim2.new(0, small and 60 or 110, 0, barH - 14), Color3.fromRGB(10, 10, 14))
	corner(vu, 6)
	local leds = {}
	local nLed = small and 8 or 12
	for i = 1, nLed do
		local c = i <= nLed * 0.6 and MINT or (i <= nLed * 0.85 and GOLD or Color3.fromRGB(255, 80, 90))
		local led = frame(vu, "Led", UDim2.new((i - 1) / nLed, 2, 0.2, 0), UDim2.new(1 / nLed, -3, 0.6, 0), c)
		corner(led, 2)
		led:SetAttribute("On", c)
		led.BackgroundTransparency = 0.8
		table.insert(leds, led)
	end
	self.Leds = leds
	-- boutons
	local leave = button(top, "Leave", T("✖ Stand up"), Color3.fromRGB(226, 80, 104))
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -10, 0, 6)
	leave.Size = UDim2.new(small and 0.2 or 0.15, 0, 0, barH - 6)
	onPress(self.PanelConns, leave, function()
		self.Cb.Leave()
	end)
	local songs = button(top, "Songs", T("▶️ Play a song"), HOT)
	songs.AnchorPoint = Vector2.new(1, 0)
	songs.Position = UDim2.new(small and 0.8 or 0.85, -18, 0, 6)
	songs.Size = UDim2.new(small and 0.3 or 0.22, 0, 0, barH - 6)
	gradient(songs, Color3.fromRGB(255, 150, 200), HOT, 90)
	onPress(self.PanelConns, songs, function()
		self.Cb.Picker()
	end)
	-- corps (l'instrument)
	local body = frame(panel, "Body", UDim2.fromOffset(10, barH + 8), UDim2.new(1, -20, 1, -(barH + (small and 12 or 30))), Color3.new(0, 0, 0))
	body.BackgroundTransparency = 1
	self.Buttons = {}
	self.Strings = nil
	self.Vinyls = nil
	if layout.Kind == "keys" then
		if station == "Xylophone" then
			self:BuildXylophone(body, layout)
		else
			self:BuildKeyboard(body, layout, station)
		end
	elseif layout.Kind == "drums" then
		self:BuildDrums(body, layout)
	elseif layout.Kind == "guitar" or layout.Kind == "bass" then
		self:BuildNeck(body, layout, station)
	elseif layout.Kind == "dj" then
		self:BuildDJ(body, layout)
	end
	if not small and not hideKeys then
		local hint = text(panel, "Hint", T("Keyboard keys play too · Space = stand up"), UDim2.new(0, 0, 1, -20), UDim2.new(1, 0, 0, 16), MUTED, Enum.Font.GothamBold, 14)
		hint.TextTransparency = 0.2
	end
	UIUtil.Pop(panel, 0.92, 0.2)
end

----------------------------------------------------------------------
-- 🎹 Clavier (piano à queue, synthé)
----------------------------------------------------------------------

local BLACK_PC = { [1] = true, [3] = true, [6] = true, [8] = true, [10] = true }

function MusicUI.BuildKeyboard(self: any, body: Frame, layout: any, station: string)
	local small = self.Small
	local synth = station == "Synth"
	local low, count = layout.Low, layout.Count
	-- colonne de commandes (octave, mini-clavier, écran du synthé)
	local sideW = small and 74 or 128
	local side = frame(body, "Controls", UDim2.fromOffset(0, 0), UDim2.new(0, sideW, 1, 0), synth and Color3.fromRGB(40, 44, 54) or Color3.fromRGB(12, 11, 16))
	corner(side, 10)
	UIUtil.Stroke(side, synth and CYAN or GOLD, 1, 0.6)
	local cap = text(side, "Cap", synth and "DOPA-SYNTH" or "DOPAMINE", UDim2.new(0, 6, 0, 4), UDim2.new(1, -12, 0, small and 12 or 16), synth and CYAN or GOLD, Enum.Font.GothamBlack, 14)
	local _ = cap
	if synth then
		-- écran LCD + 2 boutons rotatifs (décor)
		local lcd = frame(side, "LCD", UDim2.new(0, 8, 0, small and 18 or 24), UDim2.new(1, -16, 0, small and 22 or 30), Color3.fromRGB(120, 200, 150))
		corner(lcd, 4)
		gradient(lcd, Color3.fromRGB(150, 230, 170), Color3.fromRGB(90, 170, 120), 90)
		local lcdText = text(lcd, "Text", "PAD 01", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), Color3.fromRGB(20, 50, 30), Enum.Font.Code, 18)
		self.LCD = lcdText
		if not small then
			for i, name in ipairs({ "CUT", "RES" }) do
				local knob = frame(side, "Knob", UDim2.new((i - 1) * 0.5 + 0.12, 0, 0, 62), UDim2.fromOffset(26, 26), Color3.fromRGB(20, 22, 28))
				round(knob)
				UIUtil.Stroke(knob, Color3.fromRGB(140, 150, 170), 2, 0)
				local tick = frame(knob, "Tick", UDim2.new(0.5, -1, 0, 2), UDim2.new(0, 2, 0.42, 0), CYAN)
				local _t = tick
				text(side, "KnobLabel", name, UDim2.new((i - 1) * 0.5 + 0.08, 0, 0, 90), UDim2.fromOffset(34, 10), MUTED, Enum.Font.GothamBold, 10)
			end
		end
	end
	-- octave
	local octY = synth and (small and 44 or 106) or (small and 20 or 28)
	local octLabel = text(side, "OctaveCap", T("OCTAVE"), UDim2.new(0, 0, 0, octY), UDim2.new(1, 0, 0, small and 10 or 12), MUTED, Enum.Font.GothamBold, 12)
	local _o = octLabel
	local bh = small and 26 or 34
	local down = button(side, "OctDown", "◀", Color3.fromRGB(150, 120, 200))
	down.Position = UDim2.new(0, 6, 0, octY + (small and 12 or 16))
	down.Size = UDim2.new(0.5, -9, 0, bh)
	local up = button(side, "OctUp", "▶", Color3.fromRGB(150, 120, 200))
	up.Position = UDim2.new(0.5, 3, 0, octY + (small and 12 or 16))
	up.Size = UDim2.new(0.5, -9, 0, bh)
	onPress(self.PanelConns, down, function()
		self.Cb.Octave(-1)
	end)
	onPress(self.PanelConns, up, function()
		self.Cb.Octave(1)
	end)
	local octText = text(side, "Octave", "", UDim2.new(0, 4, 0, octY + bh + (small and 14 or 20)), UDim2.new(1, -8, 0, small and 14 or 18), WHITE, Enum.Font.GothamBold, 16)
	self.OctaveLabel = octText
	-- mini-clavier 88 touches : la plage jouée est éclairée
	if not small or not synth then
		local mini = frame(side, "Mini", UDim2.new(0, 6, 1, -(small and 16 or 22)), UDim2.new(1, -12, 0, small and 10 or 14), IVORY)
		corner(mini, 2)
		local range = frame(mini, "Range", UDim2.new(), UDim2.fromScale(0.3, 1), PINK)
		range.BackgroundTransparency = 0.35
		corner(range, 2)
		for k = 0, 7 do
			local line = frame(mini, "Oct", UDim2.new(k / 7.33, 0, 0, 0), UDim2.new(0, 1, 1, 0), Color3.fromRGB(150, 140, 150))
			local _l = line
		end
		self.MiniRange = range
		self:SetOctaveRange(low, count)
	end
	-- caisse du clavier
	local case = frame(body, "Case", UDim2.fromOffset(sideW + 8, 0), UDim2.new(1, -(sideW + 8), 1, 0), synth and Color3.fromRGB(46, 50, 60) or Color3.fromRGB(10, 10, 14))
	corner(case, 10)
	if synth then
		gradient(case, Color3.fromRGB(70, 76, 90), Color3.fromRGB(34, 36, 44), 90)
	else
		gradient(case, Color3.fromRGB(46, 44, 52), Color3.fromRGB(6, 6, 8), 90)
	end
	-- feutre (piano) / liseré lumineux (synthé)
	local felt = frame(case, "Felt", UDim2.new(0, 6, 0, 6), UDim2.new(1, -12, 0, 5), synth and CYAN or RED_FELT)
	corner(felt, 2)
	local keysArea = frame(case, "Keys", UDim2.new(0, 6, 0, 12), UDim2.new(1, -12, 1, -18), Color3.new(0, 0, 0))
	keysArea.BackgroundTransparency = 1
	local whites = {}
	for n = low, low + count - 1 do
		if not BLACK_PC[n % 12] then
			table.insert(whites, n)
		end
	end
	local nw = #whites
	local index = {}
	for i, n in ipairs(whites) do
		index[n] = i
	end
	local function addKey(k: TextButton, n: number, isBlack: boolean)
		local base = k.BackgroundColor3
		local entry = { Frame = k, Kind = "key", Base = base, Black = isBlack, Pos = k.Position }
		register(self, n, entry)
		onPress(self.PanelConns, k, function(input)
			-- (plus bas sur la touche = plus fort)
			local rel = relPos(k, input)
			local vel = math.clamp(0.45 + 0.6 * rel.Y, 0.4, 1)
			entry.Held = true
			self.Cb.Note(n, vel)
		end)
		onRelease(self.PanelConns, k, function()
			entry.Held = false
		end)
		table.insert(self.PanelConns, k.MouseLeave:Connect(function()
			entry.Held = false
		end))
	end
	for i, n in ipairs(whites) do
		local k = Instance.new("TextButton")
		k.Name = "White"
		k.AutoButtonColor = false
		k.BackgroundColor3 = IVORY
		k.BorderSizePixel = 0
		k.Position = UDim2.new((i - 1) / nw, 1, 0, 0)
		k.Size = UDim2.new(1 / nw, -2, 1, -2)
		k.Text = ""
		k.ZIndex = 3
		k.Parent = keysArea
		corner(k, small and 4 or 6)
		gradient(k, WHITE, Color3.fromRGB(226, 220, 210), 90)
		-- (ombre au bas de la touche)
		local lip = frame(k, "Lip", UDim2.new(0, 0, 1, -5), UDim2.new(1, 0, 0, 5), Color3.fromRGB(200, 190, 180), 3)
		corner(lip, 3)
		local name = MusicData.NoteName(n, Locale.IsFrench())
		local isC = n % 12 == 0
		local lab = text(k, "Note", isC and name or string.gsub(name, "%-?%d+$", ""), UDim2.new(0, 1, 1, small and -34 or -42), UDim2.new(1, -2, 0, small and 12 or 15), isC and HOT or Color3.fromRGB(150, 130, 160), Enum.Font.GothamBold, 14)
		lab.ZIndex = 4
		keyBadge(k, layout.Keys and layout.Keys[n], UDim2.new(0.5, 0, 1, -7))
		addKey(k, n, false)
	end
	for n = low, low + count - 1 do
		if BLACK_PC[n % 12] then
			local left = index[n - 1]
			if left then
				local k = Instance.new("TextButton")
				k.Name = "Black"
				k.AutoButtonColor = false
				k.BackgroundColor3 = EBONY
				k.BorderSizePixel = 0
				k.AnchorPoint = Vector2.new(0.5, 0)
				k.Position = UDim2.new(left / nw, 0, 0, 0)
				k.Size = UDim2.new(0.62 / nw, 0, 0.6, 0)
				k.Text = ""
				k.ZIndex = 6
				k.Parent = keysArea
				corner(k, 4)
				gradient(k, Color3.fromRGB(70, 66, 78), Color3.fromRGB(8, 8, 10), 90)
				local shine = frame(k, "Shine", UDim2.new(0.18, 0, 0.04, 0), UDim2.new(0.18, 0, 0.7, 0), WHITE, 7)
				shine.BackgroundTransparency = 0.82
				corner(shine, 2)
				if synth then
					local led = frame(k, "Accent", UDim2.new(0, 2, 1, -3), UDim2.new(1, -4, 0, 2), CYAN, 7)
					local _a = led
				end
				keyBadge(k, layout.Keys and layout.Keys[n], UDim2.new(0.5, 0, 1, -4), nil, true)
				addKey(k, n, true)
			end
		end
	end
	if self.SubLabel then
		self.SubLabel.Text = synth and T("Pad sound · lower on a key = louder") or T("Concert grand · lower on a key = louder")
	end
end

function MusicUI.SetOctaveRange(self: any, low: number, count: number)
	local range = self.MiniRange
	if range and range.Parent then
		-- (88 touches : La0 = 21 .. Do8 = 108)
		local a = math.clamp((low - 21) / 88, 0, 1)
		local b = math.clamp((low + count - 21) / 88, 0, 1)
		range.Position = UDim2.fromScale(a, 0)
		range.Size = UDim2.fromScale(math.max(0.02, b - a), 1)
	end
end

----------------------------------------------------------------------
-- 🎶 Xylophone : lames de bois colorées
----------------------------------------------------------------------

function MusicUI.BuildXylophone(self: any, body: Frame, layout: any)
	local small = self.Small
	local low, count = layout.Low, layout.Count
	local sideW = small and 74 or 110
	-- commandes d'octave (à gauche)
	local side = frame(body, "Controls", UDim2.new(), UDim2.new(0, sideW, 1, 0), Color3.fromRGB(70, 46, 32))
	corner(side, 10)
	local bh = small and 26 or 34
	text(side, "OctaveCap", T("OCTAVE"), UDim2.new(0, 0, 0, 8), UDim2.new(1, 0, 0, 12), Color3.fromRGB(255, 220, 170), Enum.Font.GothamBold, 12)
	local down = button(side, "OctDown", "◀", Color3.fromRGB(190, 120, 70))
	down.Position = UDim2.new(0, 6, 0, 24)
	down.Size = UDim2.new(0.5, -9, 0, bh)
	local up = button(side, "OctUp", "▶", Color3.fromRGB(190, 120, 70))
	up.Position = UDim2.new(0.5, 3, 0, 24)
	up.Size = UDim2.new(0.5, -9, 0, bh)
	onPress(self.PanelConns, down, function()
		self.Cb.Octave(-1)
	end)
	onPress(self.PanelConns, up, function()
		self.Cb.Octave(1)
	end)
	self.OctaveLabel = text(side, "Octave", "", UDim2.new(0, 4, 0, 30 + bh), UDim2.new(1, -8, 0, 16), WHITE, Enum.Font.GothamBold, 16)
	text(side, "Mallets", "🥢", UDim2.new(0, 0, 1, -40), UDim2.new(1, 0, 0, 30), WHITE, nil, 26)
	-- cadre (rails en bois)
	local area = frame(body, "Bars", UDim2.fromOffset(sideW + 8, 0), UDim2.new(1, -(sideW + 8), 1, 0), Color3.fromRGB(40, 28, 22))
	corner(area, 10)
	for _, y in ipairs({ 0.3, 0.8 }) do
		local rail = frame(area, "Rail", UDim2.new(0, 4, y, 0), UDim2.new(1, -8, 0, 6), Color3.fromRGB(120, 80, 50), 2)
		corner(rail, 3)
	end
	local naturals = {}
	for n = low, low + count - 1 do
		if not BLACK_PC[n % 12] then
			table.insert(naturals, n)
		end
	end
	local nn = #naturals
	local index = {}
	for i, n in ipairs(naturals) do
		index[n] = i
	end
	local function bar(n: number, x: number, w: number, y0: number, h: number, isSharp: boolean)
		local hue = ((n % 12) / 12 + 0.02) % 1
		local color = Color3.fromHSV(hue, isSharp and 0.55 or 0.45, isSharp and 0.78 or 0.96)
		local k = Instance.new("TextButton")
		k.Name = isSharp and "SharpBar" or "Bar"
		k.AutoButtonColor = false
		k.BackgroundColor3 = color
		k.BorderSizePixel = 0
		k.AnchorPoint = Vector2.new(0.5, 0)
		k.Position = UDim2.new(x, 0, y0, 0)
		k.Size = UDim2.new(w, -3, h, 0)
		k.Text = ""
		k.ZIndex = isSharp and 6 or 4
		k.Parent = area
		corner(k, 5)
		gradient(k, color:Lerp(WHITE, 0.25), color:Lerp(Color3.new(0, 0, 0), 0.25), 0)
		UIUtil.Stroke(k, color:Lerp(Color3.new(0, 0, 0), 0.45), 1, 0.2)
		-- clous (là où la lame repose sur les rails)
		for _, yy in ipairs({ 0.18, 0.82 }) do
			local nail = frame(k, "Nail", UDim2.new(0.5, -3, yy, -3), UDim2.fromOffset(6, 6), Color3.fromRGB(220, 220, 228), k.ZIndex + 1)
			round(nail)
		end
		if not isSharp then
			-- (dièses : lames trop courtes, seulement la touche du clavier)
			local name = MusicData.NoteName(n, Locale.IsFrench())
			local lab = text(k, "Note", n % 12 == 0 and name or string.gsub(name, "%-?%d+$", ""), UDim2.new(0, 0, 0.32, 0), UDim2.new(1, 0, 0.2, 0), Color3.fromRGB(50, 30, 40), Enum.Font.GothamBold, 13)
			lab.ZIndex = k.ZIndex + 1
		end
		keyBadge(k, layout.Keys and layout.Keys[n], UDim2.new(0.5, 0, isSharp and 0.72 or 0.74, 0), nil, true)
		local entry = { Frame = k, Kind = "bar", Base = color, Pos = k.Position }
		register(self, n, entry)
		onPress(self.PanelConns, k, function(input)
			local rel = relPos(k, input)
			-- (au milieu de la lame = son plus plein)
			local vel = math.clamp(1 - math.abs(rel.Y - 0.5) * 0.9, 0.5, 1)
			self.Cb.Note(n, vel)
		end)
	end
	for i, n in ipairs(naturals) do
		-- (lames de plus en plus courtes vers l'aigu)
		local h = 0.7 - 0.22 * (i - 1) / math.max(1, nn - 1)
		bar(n, (i - 0.5) / nn, 1 / nn, 0.29 + (0.7 - h) / 2, h, false)
	end
	for n = low, low + count - 1 do
		if BLACK_PC[n % 12] and index[n - 1] then
			local i = index[n - 1]
			local h = 0.27 - 0.06 * (i - 1) / math.max(1, nn - 1)
			bar(n, i / nn, 0.7 / nn, 0.02, h, true)
		end
	end
	if self.SubLabel then
		self.SubLabel.Text = T("Rosewood bars · hit the middle")
	end
end

----------------------------------------------------------------------
-- 🥁 Batterie vue du dessus
----------------------------------------------------------------------

function MusicUI.BuildDrums(self: any, body: Frame, layout: any)
	local small = self.Small
	-- tapis
	local rug = frame(body, "Rug", UDim2.fromScale(0.5, 0.5), UDim2.new(0.96, 0, 1.02, 0), Color3.fromRGB(60, 28, 46))
	rug.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(rug, UDim.new(0.5, 0))
	gradient(rug, Color3.fromRGB(86, 40, 66), Color3.fromRGB(40, 18, 34), 90)
	rug.BackgroundTransparency = 0.1
	local area = frame(body, "Kit", UDim2.new(), UDim2.fromScale(1, 1), Color3.new(0, 0, 0))
	area.BackgroundTransparency = 1
	local h = body.AbsoluteSize.Y > 0 and body.AbsoluteSize.Y or (small and 160 or 240)
	for _, pad in ipairs(layout.Pads) do
		local d = math.floor(2 * pad.R * h + 0.5)
		local holder = Instance.new("TextButton")
		holder.Name = pad.Name or "Pad"
		holder.AutoButtonColor = false
		holder.Text = ""
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(pad.X, pad.Y)
		holder.Size = pad.Type == "pill" and UDim2.fromOffset(math.floor(d * 2.2), math.floor(d * 0.9)) or UDim2.fromOffset(d, d)
		holder.ZIndex = pad.Type == "cymbal" and 8 or 4
		holder.BorderSizePixel = 0
		holder.Parent = area
		local scale = Instance.new("UIScale")
		scale.Name = "HitScale"
		scale.Parent = holder
		local base: Color3
		if pad.Type == "cymbal" or pad.Type == "hat" then
			base = Color3.fromRGB(214, 168, 76)
			holder.BackgroundColor3 = base
			round(holder)
			UIUtil.Gradient(holder, ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 220, 140)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 150, 60)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 200, 110)),
			}), 35)
			UIUtil.Stroke(holder, Color3.fromRGB(150, 104, 40), 2, 0)
			for _, s in ipairs({ 0.72, 0.46 }) do
				local ring = frame(holder, "Groove", UDim2.fromScale((1 - s) / 2, (1 - s) / 2), UDim2.fromScale(s, s), Color3.new(0, 0, 0), holder.ZIndex + 1)
				ring.BackgroundTransparency = 1
				round(ring)
				UIUtil.Stroke(ring, Color3.fromRGB(170, 120, 50), 1, 0.4)
			end
			local bell = frame(holder, "Bell", UDim2.fromScale(0.39, 0.39), UDim2.fromScale(0.22, 0.22), Color3.fromRGB(236, 196, 110), holder.ZIndex + 1)
			round(bell)
			UIUtil.Stroke(bell, Color3.fromRGB(150, 104, 40), 1, 0)
		elseif pad.Type == "kick" then
			base = Color3.fromRGB(40, 70, 160)
			holder.BackgroundColor3 = base
			round(holder)
			UIUtil.Stroke(holder, Color3.fromRGB(220, 224, 236), 4, 0)
			local head = frame(holder, "Head", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.84), Color3.fromRGB(246, 242, 232), holder.ZIndex + 1)
			round(head)
			gradient(head, WHITE, Color3.fromRGB(226, 220, 206), 120)
			local logo = text(head, "Logo", "🧠 DOPAMINE", UDim2.fromScale(0.1, 0.36), UDim2.fromScale(0.8, 0.22), HOT, Enum.Font.FredokaOne, 22)
			local _l = logo
		elseif pad.Type == "pill" then
			base = Color3.fromRGB(200, 150, 60)
			holder.BackgroundColor3 = base
			corner(holder, UDim.new(0.5, 0))
			UIUtil.Stroke(holder, Color3.fromRGB(255, 220, 140), 2, 0)
		else
			base = Color3.fromRGB(246, 242, 232)
			holder.BackgroundColor3 = pad.Shell or Color3.fromRGB(40, 70, 160)
			round(holder)
			UIUtil.Stroke(holder, Color3.fromRGB(200, 204, 216), 3, 0)
			local head = frame(holder, "Head", UDim2.fromScale(0.09, 0.09), UDim2.fromScale(0.82, 0.82), base, holder.ZIndex + 1)
			round(head)
			gradient(head, WHITE, Color3.fromRGB(222, 214, 198), 120)
			-- tirants (petits points chromés autour)
			for k = 0, 7 do
				local a = k / 8 * math.pi * 2
				local lug = frame(holder, "Lug", UDim2.fromScale(0.5 + 0.47 * math.cos(a), 0.5 + 0.47 * math.sin(a)), UDim2.fromOffset(5, 5), Color3.fromRGB(230, 232, 240), holder.ZIndex + 2)
				lug.AnchorPoint = Vector2.new(0.5, 0.5)
				round(lug)
			end
			base = holder.BackgroundColor3
		end
		local label = text(holder, "Label", pad.Label, UDim2.fromScale(0.08, pad.Type == "kick" and 0.6 or 0.28), UDim2.fromScale(0.84, pad.Type == "pill" and 0.5 or 0.24), pad.Type == "kick" and INK or Color3.fromRGB(60, 40, 50), Enum.Font.FredokaOne, small and 13 or 17)
		label.ZIndex = holder.ZIndex + 3
		keyBadge(holder, pad.KeyCode, UDim2.fromScale(0.5, pad.Type == "pill" and 1.05 or 0.86), Vector2.new(0.5, 1), true)
		local entry = { Frame = holder, Kind = "drum", Base = base, Scale = scale }
		register(self, pad.Value, entry)
		onPress(self.PanelConns, holder, function(input)
			local rel = relPos(holder, input)
			-- (au centre = plus fort ; au bord = plus doux)
			local dist = (rel - Vector2.new(0.5, 0.5)).Magnitude * 2
			self.Cb.Note(pad.Value, math.clamp(1 - 0.45 * dist, 0.45, 1))
		end)
	end
	if self.SubLabel then
		self.SubLabel.Text = T("Top view · hit the centre = louder")
	end
end

----------------------------------------------------------------------
-- 🎸 Guitare / basse : manche
----------------------------------------------------------------------

function MusicUI.BuildNeck(self: any, body: Frame, layout: any, station: string)
	local small = self.Small
	local bass = layout.Kind == "bass"
	local strings = bass and 4 or 6
	local frets = bass and 17 or 10
	local neckY = 0
	-- accords (guitare)
	if not bass then
		local row = frame(body, "Chords", UDim2.new(), UDim2.new(1, 0, 0.24, -4), Color3.new(0, 0, 0))
		row.BackgroundTransparency = 1
		local n = #layout.Chords
		for i, c in ipairs(layout.Chords) do
			local card = Instance.new("TextButton")
			card.Name = "Chord"
			card.AutoButtonColor = false
			card.Text = ""
			card.BorderSizePixel = 0
			card.Position = UDim2.new((i - 1) / n, 3, 0, 0)
			card.Size = UDim2.new(1 / n, -6, 1, 0)
			card.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(226, 80, 110) or Color3.fromRGB(240, 110, 150)
			card.ZIndex = 3
			card.Parent = row
			corner(card, 10)
			gradient(card, card.BackgroundColor3:Lerp(WHITE, 0.2), card.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.15), 90)
			UIUtil.Stroke(card, WHITE, 1, 0.5)
			text(card, "Name", c.Label, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.58), WHITE, Enum.Font.FredokaOne, 26).ZIndex = 5
			keyBadge(card, c.KeyCode, UDim2.fromScale(0.5, 0.95), Vector2.new(0.5, 1), true)
			local entry = { Frame = card, Kind = "pad", Base = card.BackgroundColor3, Strum = true }
			register(self, c.Value, entry)
			onPress(self.PanelConns, card, function()
				self.Cb.Note(c.Value, 0.85)
			end)
		end
		neckY = 0.26
	end
	-- manche
	local neck = frame(body, "Neck", UDim2.new(0, 0, neckY, 0), UDim2.new(1, 0, 1 - neckY, 0), Color3.fromRGB(72, 40, 28))
	corner(neck, 8)
	gradient(neck, Color3.fromRGB(96, 56, 38), Color3.fromRGB(52, 28, 20), 90)
	UIUtil.Stroke(neck, Color3.fromRGB(240, 230, 210), 2, 0.2)
	-- sillet + frettes (espacement qui diminue comme sur un vrai manche)
	local nut = frame(neck, "Nut", UDim2.new(0, 0, 0, 0), UDim2.new(0, 8, 1, 0), IVORY, 2)
	local _n = nut
	local xs = { 0 }
	local total = 0
	for f = 1, frets do
		total += 0.94 ^ f
		xs[f] = total
	end
	local function fretX(f: number): number
		return 8 / math.max(1, neck.AbsoluteSize.X) + (xs[f] or 0) / total * 0.985
	end
	for f = 1, frets do
		local wire = frame(neck, "Fret", UDim2.new(fretX(f), -1, 0, 2), UDim2.new(0, 3, 1, -4), Color3.fromRGB(200, 204, 214), 2)
		gradient(wire, WHITE, Color3.fromRGB(150, 154, 166), 0)
	end
	local function midX(f: number): number
		if f <= 0 then
			return 0.012
		end
		return (fretX(f - 1 >= 1 and f - 1 or 0) + fretX(f)) / 2
	end
	-- repères (nacre)
	for _, f in ipairs({ 3, 5, 7, 9, 12, 15, 17 }) do
		if f <= frets then
			local dots = f == 12 and { 0.3, 0.7 } or { 0.5 }
			for _, y in ipairs(dots) do
				local dot = frame(neck, "Inlay", UDim2.new(midX(f), -5, y, -5), UDim2.fromOffset(10, 10), Color3.fromRGB(236, 232, 226), 2)
				round(dot)
				dot.BackgroundTransparency = 0.25
			end
		end
	end
	-- cordes (la plus aiguë en haut, comme une tablature)
	self.Strings = {}
	for s = 1, strings do
		local y = (s - 0.5) / strings
		local thick = bass and (2 + s * 0.7) or (1 + s * 0.45)
		local str = frame(neck, "String", UDim2.new(0, 0, y, -thick / 2), UDim2.new(1, 0, 0, thick), Color3.fromRGB(220, 210, 180), 3)
		gradient(str, Color3.fromRGB(250, 240, 210), Color3.fromRGB(150, 140, 110), 90)
		table.insert(self.Strings, { Frame = str, Y = y, Thick = thick, T0 = -math.huge, Amp = 0 })
	end
	-- notes (sur leurs cases) : pastilles à la taille de l'écart entre cordes
	local neckH = neck.AbsoluteSize.Y > 0 and neck.AbsoluteSize.Y or (small and 120 or 190)
	local d = math.floor(math.clamp(neckH / strings * 0.94, 18, small and 30 or 40))
	for _, note in ipairs(layout.Notes) do
		local y = (note.String - 0.5) / strings
		local dot = Instance.new("TextButton")
		dot.Name = "FretNote"
		dot.AutoButtonColor = false
		dot.Text = ""
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(midX(note.Fret), 0, y, 0)
		dot.Size = UDim2.fromOffset(math.floor(d * (hideKeys and 2.2 or 1.25)), d)
		dot.BackgroundColor3 = note.Color or (bass and Color3.fromRGB(110, 160, 255) or Color3.fromRGB(190, 110, 255))
		dot.BorderSizePixel = 0
		dot.ZIndex = 6
		dot.Parent = neck
		corner(dot, UDim.new(0.5, 0))
		UIUtil.Stroke(dot, WHITE, 2, 0.1)
		local scale = Instance.new("UIScale")
		scale.Name = "HitScale"
		scale.Parent = dot
		local lab = text(dot, "Note", note.Label, UDim2.fromScale(0.05, hideKeys and 0.12 or 0.04), UDim2.fromScale(0.9, hideKeys and 0.76 or 0.5), WHITE, Enum.Font.GothamBold, 14)
		lab.ZIndex = 8
		if not hideKeys then
			local kb = keyLabel(note.KeyCode)
			local klab = text(dot, "Key", kb, UDim2.fromScale(0.05, 0.52), UDim2.fromScale(0.9, 0.42), Color3.fromRGB(255, 236, 250), Enum.Font.GothamBlack, 13)
			klab.ZIndex = 8
		end
		local entry = { Frame = dot, Kind = "drum", Base = dot.BackgroundColor3, Scale = scale, String = note.String }
		register(self, note.Value, entry)
		onPress(self.PanelConns, dot, function()
			self.Cb.Note(note.Value, 0.85)
		end)
	end
	if self.SubLabel then
		self.SubLabel.Text = bass and T("4 strings · root notes") or T("Chords strum · solo on the neck")
	end
	local _s = station
end

----------------------------------------------------------------------
-- 🎧 DJ : platines, table de mixage, pads
----------------------------------------------------------------------

function MusicUI.BuildDJ(self: any, body: Frame, layout: any)
	local small = self.Small
	local h = body.AbsoluteSize.Y > 0 and body.AbsoluteSize.Y or (small and 160 or 250)
	self.Vinyls = {}
	local deckD = math.floor(h * (small and 0.82 or 0.86))
	local function deck(xScale: number, anchorX: number, side: string)
		local plinth = frame(body, "Deck" .. side, UDim2.new(xScale, 0, 0.5, 0), UDim2.fromOffset(deckD + 14, deckD + 14), Color3.fromRGB(30, 30, 36))
		plinth.AnchorPoint = Vector2.new(anchorX, 0.5)
		corner(plinth, 12)
		gradient(plinth, Color3.fromRGB(58, 58, 68), Color3.fromRGB(22, 22, 28), 90)
		local platter = frame(plinth, "Platter", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(deckD, deckD), Color3.fromRGB(150, 152, 160), 2)
		platter.AnchorPoint = Vector2.new(0.5, 0.5)
		round(platter)
		local vinyl = Instance.new("TextButton")
		vinyl.Name = "Vinyl"
		vinyl.AutoButtonColor = false
		vinyl.Text = ""
		vinyl.AnchorPoint = Vector2.new(0.5, 0.5)
		vinyl.Position = UDim2.fromScale(0.5, 0.5)
		vinyl.Size = UDim2.fromScale(0.94, 0.94)
		vinyl.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
		vinyl.BorderSizePixel = 0
		vinyl.ZIndex = 3
		vinyl.Parent = platter
		round(vinyl)
		for _, s in ipairs({ 0.86, 0.74, 0.62 }) do
			local groove = frame(vinyl, "Groove", UDim2.fromScale((1 - s) / 2, (1 - s) / 2), UDim2.fromScale(s, s), Color3.new(0, 0, 0), 4)
			groove.BackgroundTransparency = 1
			round(groove)
			UIUtil.Stroke(groove, Color3.fromRGB(60, 60, 66), 1, 0.3)
		end
		local label = frame(vinyl, "Label", UDim2.fromScale(0.33, 0.33), UDim2.fromScale(0.34, 0.34), HOT, 5)
		round(label)
		local mark = frame(label, "Mark", UDim2.new(0.5, -2, 0, 2), UDim2.new(0, 4, 0.4, 0), WHITE, 6)
		local _m = mark
		local hole = frame(label, "Hole", UDim2.fromScale(0.44, 0.44), UDim2.fromScale(0.12, 0.12), Color3.fromRGB(200, 200, 206), 6)
		round(hole)
		-- bras de lecture
		local arm = frame(plinth, "Arm", UDim2.new(side == "L" and 0.9 or 0.1, 0, 0.12, 0), UDim2.new(0, 5, 0.55, 0), Color3.fromRGB(210, 212, 220), 7)
		arm.Rotation = side == "L" and 18 or -18
		corner(arm, 2)
		local entry = { Frame = vinyl, Kind = "vinyl", Base = vinyl.BackgroundColor3, Label = label, Angle = 0, Speed = 0 }
		table.insert(self.Vinyls, entry)
		register(self, MusicData.DJ_FX.Scratch, entry)
		onPress(self.PanelConns, vinyl, function()
			entry.Speed = -720
			self.Cb.Note(MusicData.DJ_FX.Scratch, 0.85)
		end)
		return plinth
	end
	deck(0, 0, "L")
	deck(1, 1, "R")
	-- table de mixage (au centre)
	local mixer = frame(body, "Mixer", UDim2.new(0.5, 0, 0, 0), UDim2.new(1, -2 * (deckD + 22), 1, 0), Color3.fromRGB(24, 22, 32))
	mixer.AnchorPoint = Vector2.new(0.5, 0)
	corner(mixer, 12)
	gradient(mixer, Color3.fromRGB(46, 40, 62), Color3.fromRGB(18, 16, 24), 90)
	UIUtil.Stroke(mixer, Color3.fromRGB(190, 120, 255), 1, 0.5)
	-- pads de boucles (2 rangées de 4)
	local padArea = frame(mixer, "Loops", UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 0.56, -6), Color3.new(0, 0, 0))
	padArea.BackgroundTransparency = 1
	for i, loop in ipairs(layout.Loops) do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local b = Instance.new("TextButton")
		b.Name = "LoopPad"
		b.AutoButtonColor = false
		b.Text = ""
		b.BorderSizePixel = 0
		b.Position = UDim2.new(col / 4, 3, row / 2, 3)
		b.Size = UDim2.new(0.25, -6, 0.5, -6)
		b.BackgroundColor3 = loop.Color
		b.ZIndex = 3
		b.Parent = padArea
		corner(b, 8)
		gradient(b, loop.Color:Lerp(WHITE, 0.25), loop.Color:Lerp(Color3.new(0, 0, 0), 0.3), 90)
		UIUtil.Stroke(b, WHITE, 2, 0.6)
		text(b, "Icon", loop.Icon, UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.42), WHITE, nil, 20).ZIndex = 5
		text(b, "Label", loop.Label, UDim2.fromScale(0.04, 0.42), UDim2.fromScale(0.92, 0.3), WHITE, Enum.Font.GothamBold, 13).ZIndex = 5
		keyBadge(b, loop.KeyCode, UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), true)
		local entry = { Frame = b, Kind = "pad", Base = loop.Color }
		register(self, loop.Value, entry)
		onPress(self.PanelConns, b, function()
			self.Cb.Note(loop.Value, 0.9)
		end)
	end
	-- crossfader
	local rail = frame(mixer, "FaderRail", UDim2.new(0.15, 0, 0.6, 4), UDim2.new(0.7, 0, 0, 8), Color3.fromRGB(8, 8, 10))
	corner(rail, 4)
	text(mixer, "FaderCap", T("CROSSFADER · slide fast = scratch"), UDim2.new(0, 0, 0.6, -10), UDim2.new(1, 0, 0, 12), MUTED, Enum.Font.GothamBold, 11)
	local knob = Instance.new("TextButton")
	knob.Name = "Crossfader"
	knob.AutoButtonColor = false
	knob.Text = ""
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(small and 22 or 30, small and 22 or 28)
	knob.BackgroundColor3 = Color3.fromRGB(230, 230, 236)
	knob.BorderSizePixel = 0
	knob.ZIndex = 4
	knob.Parent = rail
	corner(knob, 5)
	gradient(knob, WHITE, Color3.fromRGB(170, 172, 180), 90)
	local dragging = false
	local lastX, lastT, lastScratch = 0.5, 0, -math.huge
	onPress(self.PanelConns, knob, function()
		dragging = true
	end)
	table.insert(self.PanelConns, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragging = false
		end
	end))
	table.insert(self.PanelConns, UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
			return
		end
		local x = relPos(rail, input).X
		knob.Position = UDim2.fromScale(x, 0.5)
		local now = self.Clock
		local speed = math.abs(x - lastX) / math.max(1 / 120, now - lastT)
		if speed > 2.5 and now - lastScratch > 0.18 then
			lastScratch = now
			for _, v in ipairs(self.Vinyls or {}) do
				v.Speed = (x > lastX) and 720 or -720
			end
			self.Cb.Note(MusicData.DJ_FX.Scratch, 0.8)
		end
		lastX, lastT = x, now
	end))
	-- effets
	local fxArea = frame(mixer, "Fx", UDim2.new(0, 8, 0.72, 0), UDim2.new(1, -16, 0.28, -6), Color3.new(0, 0, 0))
	fxArea.BackgroundTransparency = 1
	for i, fx in ipairs(layout.Fx) do
		local b = button(fxArea, "FxPad", fx.Label, fx.Color)
		b.Position = UDim2.new((i - 1) / #layout.Fx, 3, 0, 0)
		b.Size = UDim2.new(1 / #layout.Fx, -6, 1, -14)
		b.ZIndex = 3
		keyBadge(b, fx.KeyCode, UDim2.new(0.5, 0, 1, 14), Vector2.new(0.5, 1), true)
		local entry = { Frame = b, Kind = "pad", Base = fx.Color }
		register(self, fx.Value, entry)
		onPress(self.PanelConns, b, function()
			self.Cb.Note(fx.Value, 0.9)
		end)
	end
	if self.SubLabel then
		self.SubLabel.Text = T("Loops in time with everyone · tap a vinyl = scratch")
	end
end

----------------------------------------------------------------------
-- Retours visuels
----------------------------------------------------------------------

function MusicUI.Close(self: any)
	if self.Panel then
		self.Panel:Destroy()
		self.Panel = nil
	end
	UIUtil.DisconnectAll(self.PanelConns)
	self.PanelConns = {}
	self.OctaveLabel = nil
	self.MiniRange = nil
	self.LCD = nil
	self.SubLabel = nil
	self.Leds = nil
	self.Strings = nil
	self.Vinyls = nil
	self.Station = nil
	self.Buttons = {}
	table.clear(self.Flashes)
	table.clear(self.Ripples)
end

function MusicUI.SetOctaveText(self: any, value: string)
	if self.OctaveLabel then
		self.OctaveLabel.Text = value
	end
end

-- Touche / pad qui s'allume (retour visuel de chaque note ; vel = force)
function MusicUI.Flash(self: any, value: number, vel: number?)
	local v = math.clamp(vel or 0.85, 0.05, 1)
	self.Level = math.max(self.Level, v)
	local list = self.Buttons[value]
	if not list then
		return
	end
	for _, entry in ipairs(list) do
		local f = entry.Frame
		if f and f.Parent then
			if entry.Kind == "key" then
				f.BackgroundColor3 = entry.Black and Color3.fromRGB(150, 60, 110) or Color3.fromRGB(255, 214, 232)
				f.Position = entry.Pos + UDim2.fromOffset(0, 2)
			elseif entry.Kind == "bar" then
				f.BackgroundColor3 = entry.Base:Lerp(WHITE, 0.55)
				f.Position = entry.Pos + UDim2.fromOffset(0, 2)
			elseif entry.Kind == "drum" then
				if entry.Scale then
					entry.Scale.Scale = 1 + 0.1 * v
				end
				ripple(self, f, v, entry.Base:Lerp(WHITE, 0.4))
			elseif entry.Kind == "vinyl" then
				entry.Speed = -720
			else
				f.BackgroundColor3 = entry.Base:Lerp(WHITE, 0.5)
				ripple(self, f, v, WHITE)
			end
			self.Flashes[entry] = self.Clock
			if entry.Strum and self.Strings then
				for _, s in ipairs(self.Strings) do
					s.T0 = self.Clock + (s.Y * 0.06)
					s.Amp = 2.5 * v
				end
			elseif entry.String and self.Strings and self.Strings[entry.String] then
				local s = self.Strings[entry.String]
				s.T0 = self.Clock
				s.Amp = 2 * v
			end
		end
	end
	if self.LCD and value < 200 then
		self.LCD.Text = "PAD 01  " .. MusicData.NoteName(value)
	end
end

function MusicUI.SetLoop(self: any, index: number)
	self.Loop = index
	for i = 1, MusicData.DJ_LOOPS do
		for _, entry in ipairs(self.Buttons[i] or {}) do
			local stroke = entry.Frame and entry.Frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = i == index and Color3.fromRGB(255, 240, 120) or WHITE
				stroke.Thickness = i == index and 4 or 2
				stroke.Transparency = i == index and 0 or 0.6
			end
		end
	end
	for _, v in ipairs(self.Vinyls or {}) do
		if v.Label and v.Label.Parent then
			v.Label.BackgroundColor3 = index > 0 and Color3.fromHSV((index - 1) / 8, 0.7, 1) or HOT
		end
	end
end

-- (appelé à chaque image : touches relâchées, ondes, cordes, vinyles, VU)
function MusicUI.Step(self: any, dt: number?)
	local step = dt or (1 / 60)
	self.Clock += step
	local t = self.Clock
	for entry, at in pairs(self.Flashes) do
		local age = t - at
		local f = entry.Frame
		if entry.Scale then
			entry.Scale.Scale = 1 + (entry.Scale.Scale - 1) * math.exp(-step * 18)
		end
		if age > 0.14 and not entry.Held then
			if f and f.Parent then
				if entry.Kind ~= "drum" and entry.Kind ~= "vinyl" then
					f.BackgroundColor3 = entry.Base
				end
				if entry.Pos then
					f.Position = entry.Pos
				end
			end
			if not entry.Scale or math.abs(entry.Scale.Scale - 1) < 0.005 then
				if entry.Scale then
					entry.Scale.Scale = 1
				end
				self.Flashes[entry] = nil
			end
		end
	end
	local keep = {}
	for _, r in ipairs(self.Ripples) do
		local u = (t - r.T0) / 0.45
		if u >= 1 or not r.Frame.Parent then
			r.Frame:Destroy()
		else
			local s = 0.6 + (r.Max - 0.6) * u
			r.Frame.Size = UDim2.fromScale(s, s)
			r.Stroke.Transparency = u
			table.insert(keep, r)
		end
	end
	self.Ripples = keep
	-- cordes qui vibrent
	for _, s in ipairs(self.Strings or {}) do
		local age = t - s.T0
		if age >= 0 and age < 0.6 and s.Frame.Parent then
			local off = s.Amp * math.exp(-age * 7) * math.sin(age * 90)
			s.Frame.Position = UDim2.new(0, 0, s.Y, -s.Thick / 2 + off)
		end
	end
	-- vinyles : tournent si une boucle joue, freinent après un scratch
	for _, v in ipairs(self.Vinyls or {}) do
		local target = (self.Loop or 0) > 0 and 200 or 0
		v.Speed = v.Speed + (target - v.Speed) * math.min(1, step * 4)
		v.Angle = (v.Angle + v.Speed * step) % 360
		if v.Frame.Parent then
			v.Frame.Rotation = v.Angle
		end
	end
	-- VU-mètre
	self.Level = self.Level * math.exp(-step * 3.5)
	for i, led in ipairs(self.Leds or {}) do
		local on = self.Level * #self.Leds >= i - 0.5
		led.BackgroundTransparency = on and 0 or 0.8
	end
end

----------------------------------------------------------------------
-- 🎵 Discothèque : choix des morceaux, file d'attente, radio
----------------------------------------------------------------------

local function genreOf(song: any): any
	return MusicData.GENRE_INDEX[song.Genre or ""] or MusicData.GENRES[1]
end

local INST_ICON: { [string]: string } = { Piano = "🎹", Drums = "🥁", Guitar = "🎸", Bass = "🎸", Xylophone = "🎶", Synth = "🎛️", DJ = "🎧" }

-- Pochette (dégradé du genre + icône)
local function cover(parent: Instance, song: any, size: UDim2, z: number): Frame
	local g = genreOf(song)
	local c = frame(parent, "Cover", UDim2.new(), size, rgb(g.A), z)
	corner(c, 10)
	gradient(c, rgb(g.A), rgb(g.B), 135)
	local big = text(c, "Icon", song.Icon or "🎵", UDim2.fromScale(0.18, 0.12), UDim2.fromScale(0.64, 0.62), WHITE, nil, 60)
	big.ZIndex = z + 2
	-- (disque qui dépasse : effet "album")
	local disc = frame(c, "Disc", UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(16, 16, 20), z + 1)
	round(disc)
	disc.BackgroundTransparency = 0.25
	local lab = frame(disc, "Label", UDim2.fromScale(0.35, 0.35), UDim2.fromScale(0.3, 0.3), rgb(g.A), z + 1)
	round(lab)
	return c
end

local function fmt(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function MusicUI.OpenPicker(self: any, state: any)
	self:ClosePicker()
	self.PickerState = state
	local small = phone(self)
	local screenSize = self.Screen.AbsoluteSize
	local w = math.clamp(screenSize.X - (small and 12 or 40), 300, 940)
	local h = math.clamp(screenSize.Y - (small and 16 or 90), 280, 620)
	local conns = self.PickerConns
	local dim = Instance.new("TextButton")
	dim.Name = "PickerDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.ZIndex = 20
	dim.Parent = self.Screen
	local card = frame(dim, "Picker", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(w, h), PANEL, 21)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(card, 22)
	gradient(card, PANEL2, PANEL, 90)
	UIUtil.Stroke(card, PINK, 2, 0.1)
	UIUtil.SinkClicks(card)
	onClick(conns, dim, function()
		self:ClosePicker()
	end)
	local title = text(card, "Title", T("🎤 Dopamine Live · Stage music"), UDim2.fromOffset(18, 10), UDim2.new(1, -80, 0, small and 26 or 32), WHITE, Enum.Font.FredokaOne, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 22
	local sub = text(card, "Sub", T("Everyone near the stage hears it. The instruments play by themselves!"), UDim2.fromOffset(18, small and 36 or 44), UDim2.new(1, -80, 0, 14), MUTED, Enum.Font.GothamBold, 14)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 22
	sub.Visible = not small
	local close = UIUtil.CloseButton({ Name = "ClosePicker", Size = 36, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), ZIndex = 23 })
	close.Parent = card
	onClick(conns, close, function()
		self:ClosePicker()
	end)
	-- barre "EN COURS"
	local nowY = small and 42 or 66
	local nowH = small and 46 or 74
	local now = frame(card, "NowBar", UDim2.fromOffset(12, nowY), UDim2.new(1, -24, 0, nowH), Color3.fromRGB(14, 12, 20), 22)
	corner(now, 14)
	UIUtil.Stroke(now, Color3.fromRGB(90, 70, 110), 1, 0.2)
	self.NowBar = now
	-- corps : genres + pochettes (+ file d'attente à droite sur grand écran)
	local bodyY = nowY + nowH + (small and 4 or 8)
	local queueW = small and 0 or 220
	local radioH = small and 28 or 40
	local chips = Instance.new("ScrollingFrame")
	chips.Name = "Genres"
	chips.Position = UDim2.fromOffset(12, bodyY)
	chips.Size = UDim2.new(1, -24 - queueW - (queueW > 0 and 8 or 0), 0, small and 28 or 34)
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.ScrollBarThickness = 0
	chips.ScrollingDirection = Enum.ScrollingDirection.X
	chips.AutomaticCanvasSize = Enum.AutomaticSize.X
	chips.CanvasSize = UDim2.new()
	chips.ZIndex = 22
	chips.Parent = card
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips
	local gridY = bodyY + (small and 32 or 42)
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Songs"
	grid.Position = UDim2.fromOffset(12, gridY)
	grid.Size = UDim2.new(1, -24 - queueW - (queueW > 0 and 8 or 0), 1, -(gridY + radioH + 18))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = PINK
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = 22
	grid.Parent = card
	local gridLayout = Instance.new("UIGridLayout")
	local cardW = small and 92 or 128
	gridLayout.CellSize = UDim2.fromOffset(cardW, math.floor(cardW * 1.42))
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	self.Grid = grid
	-- genres
	local genres = { { Id = "All", Name = "All genres", Icon = "✨", A = { 255, 132, 184 } } }
	for _, g in ipairs(MusicData.GENRES) do
		table.insert(genres, g)
	end
	local chipButtons = {}
	local function refreshChips()
		for id, b in pairs(chipButtons) do
			local on = id == self.Genre
			b.BackgroundTransparency = on and 0 or 0.65
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = on and 0 or 0.7
			end
		end
	end
	local fillGrid: () -> ()
	for i, g in ipairs(genres) do
		-- (seulement les genres qui ont des morceaux)
		local count = 0
		for _, song in ipairs(MusicData.SONGS) do
			if g.Id == "All" or song.Genre == g.Id then
				count += 1
			end
		end
		if count > 0 then
			local label = g.Icon .. " " .. T(g.Name)
			local b = button(chips, "Genre_" .. g.Id, label, rgb(g.A))
			b.LayoutOrder = i
			b.Size = UDim2.fromOffset(math.max(70, 10 * (utf8.len(label) or #label) + 26), small and 28 or 32)
			b.ZIndex = 23
			corner(b, UDim.new(0.5, 0))
			UIUtil.Stroke(b, WHITE, 2, 0.7)
			chipButtons[g.Id] = b
			onClick(conns, b, function()
				self.Genre = g.Id
				refreshChips()
				fillGrid()
			end)
		end
	end
	refreshChips()
	-- pochettes
	fillGrid = function()
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local st = self.PickerState or {}
		for i, song in ipairs(MusicData.SONGS) do
			if self.Genre == "All" or song.Genre == self.Genre then
				local playing = st.SongId == song.Id
				local cell = Instance.new("TextButton")
				cell.Name = song.Id
				cell.LayoutOrder = i
				cell.AutoButtonColor = false
				cell.Text = ""
				cell.BackgroundColor3 = playing and Color3.fromRGB(70, 40, 80) or Color3.fromRGB(36, 30, 48)
				cell.BorderSizePixel = 0
				cell.ZIndex = 22
				cell.Parent = grid
				corner(cell, 12)
				UIUtil.Stroke(cell, playing and PINK or Color3.fromRGB(70, 60, 90), playing and 3 or 1, 0)
				local cv = cover(cell, song, UDim2.new(1, -10, 0, cardW - 10), 23)
				cv.Position = UDim2.fromOffset(5, 5)
				local g = genreOf(song)
				local badge = text(cv, "Genre", g.Icon .. " " .. T(g.Name), UDim2.fromOffset(4, 4), UDim2.new(0.75, 0, 0, 14), WHITE, Enum.Font.GothamBold, 12)
				badge.TextXAlignment = Enum.TextXAlignment.Left
				badge.ZIndex = 26
				if playing then
					local eq = text(cv, "Playing", "🔊", UDim2.new(1, -26, 0, 2), UDim2.fromOffset(24, 22), WHITE, nil, 20)
					eq.ZIndex = 26
				end
				local name = text(cell, "Name", T(song.Name), UDim2.new(0, 6, 0, cardW - 2), UDim2.new(1, -12, 0, small and 16 or 18), WHITE, Enum.Font.GothamBold, 15)
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.ZIndex = 23
				local secs = MusicData.Duration(song.Id)
				local insts = {}
				for _, inst in ipairs(MusicData.SongInstruments(song.Id)) do
					if INST_ICON[inst] and not table.find(insts, INST_ICON[inst]) then
						table.insert(insts, INST_ICON[inst])
					end
				end
				local meta = text(cell, "Meta", T(song.Author) .. " · " .. fmt(secs) .. " · " .. tostring(song.Bpm) .. " BPM", UDim2.new(0, 6, 0, cardW + (small and 14 or 17)), UDim2.new(1, -12, 0, 12), MUTED, Enum.Font.GothamBold, 11)
				meta.TextXAlignment = Enum.TextXAlignment.Left
				meta.ZIndex = 23
				local instLabel = text(cell, "Instruments", table.concat(insts, ""), UDim2.new(0, 6, 1, -24), UDim2.new(1, -40, 0, 18), WHITE, nil, 16)
				instLabel.TextXAlignment = Enum.TextXAlignment.Left
				instLabel.ZIndex = 23
				local add = button(cell, "Queue", "➕", Color3.fromRGB(110, 90, 200))
				add.AnchorPoint = Vector2.new(1, 1)
				add.Position = UDim2.new(1, -4, 1, -4)
				add.Size = UDim2.fromOffset(30, 26)
				add.ZIndex = 25
				onClick(conns, add, function()
					if self.Cb.Queue then
						self.Cb.Queue(song.Id)
					end
					UIUtil.Pop(add, 1.3, 0.25)
				end)
				onClick(conns, cell, function()
					self.Cb.Song(song.Id, self.PickerState and self.PickerState.Chain and "all" or "one")
				end)
			end
		end
	end
	fillGrid()
	self.FillGrid = fillGrid
	-- file d'attente (grand écran)
	if queueW > 0 then
		local q = frame(card, "Queue", UDim2.new(1, -12 - queueW, 0, bodyY), UDim2.new(0, queueW, 1, -(bodyY + radioH + 18)), Color3.fromRGB(14, 12, 20), 22)
		corner(q, 14)
		UIUtil.Stroke(q, Color3.fromRGB(90, 70, 110), 1, 0.2)
		local qt = text(q, "Title", T("⏭ Up next"), UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 20), WHITE, Enum.Font.FredokaOne, 18)
		qt.TextXAlignment = Enum.TextXAlignment.Left
		qt.ZIndex = 23
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.Position = UDim2.fromOffset(8, 34)
		list.Size = UDim2.new(1, -16, 1, -42)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 4
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ZIndex = 23
		list.Parent = q
		local ll = Instance.new("UIListLayout")
		ll.Padding = UDim.new(0, 4)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = list
		self.QueueList = list
	end
	-- bas : radio
	local playlist = Config.Music and Config.Music.Playlist or {}
	local radio = button(card, "Radio", "", Color3.fromRGB(96, 150, 230))
	radio.AnchorPoint = Vector2.new(0, 1)
	radio.Position = UDim2.new(0, 12, 1, -10)
	radio.Size = UDim2.new(1, -24, 0, radioH)
	radio.ZIndex = 23
	self.RadioButton = radio
	onClick(conns, radio, function()
		local count = #playlist
		local st = self.PickerState or {}
		if count == 0 then
			return
		end
		local on = type(st.Radio) == "number" and st.Radio > 0
		self.Cb.Radio(on and (st.Radio % count + 1) or math.random(1, count))
	end)
	self.Picker = dim
	self.PickerSig = nil
	self:UpdatePicker(state)
	UIUtil.Pop(card, 0.92, 0.2)
end

-- Rafraîchit la barre "en cours", la file d'attente et la radio (état du serveur)
function MusicUI.UpdatePicker(self: any, state: any)
	if not self.Picker then
		return
	end
	self.PickerState = state
	local now = self.NowBar
	local queue = state.Queue or {}
	local sig = tostring(state.SongId) .. "|" .. tostring(state.Radio) .. "|" .. table.concat(queue, ",") .. "|" .. tostring(state.Chain)
	if sig ~= self.PickerSig then
		self.PickerSig = sig
		local conns = self.PickerConns
		-- barre "en cours"
		for _, c in ipairs(now:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local small = phone(self)
		local nowH = now.AbsoluteSize.Y > 0 and now.AbsoluteSize.Y or (small and 58 or 74)
		local idx = state.SongId and MusicData.SONG_INDEX[state.SongId]
		local song = idx and MusicData.SONGS[idx]
		local bw = small and 34 or 46
		if song then
			local cv = cover(now, song, UDim2.fromOffset(nowH - 12, nowH - 12), 23)
			cv.Position = UDim2.fromOffset(6, 6)
			local t1 = text(now, "Title", "🔊 " .. T(song.Name), UDim2.fromOffset(nowH + 2, 6), UDim2.new(1, -(nowH + 3 * bw + 30), 0, small and 18 or 22), WHITE, Enum.Font.FredokaOne, 22)
			t1.TextXAlignment = Enum.TextXAlignment.Left
			local g = genreOf(song)
			local t2 = text(now, "Author", T(song.Author) .. " · " .. g.Icon .. " " .. T(g.Name) .. " · " .. tostring(song.Bpm) .. " BPM", UDim2.fromOffset(nowH + 2, small and 24 or 30), UDim2.new(1, -(nowH + 3 * bw + 30), 0, 13), MUTED, Enum.Font.GothamBold, 13)
			t2.TextXAlignment = Enum.TextXAlignment.Left
		else
			local radioOn = type(state.Radio) == "number" and state.Radio > 0
			local t1 = text(now, "Title", radioOn and ("📻 " .. T("Stage radio")) or T("🎵 Nothing playing — pick a song!"), UDim2.fromOffset(14, 8), UDim2.new(1, -(3 * bw + 40), 0, small and 18 or 24), WHITE, Enum.Font.FredokaOne, 22)
			t1.TextXAlignment = Enum.TextXAlignment.Left
		end
		local track = frame(now, "Track", UDim2.new(0, song and nowH + 2 or 14, 1, -16), UDim2.new(1, -((song and nowH + 2 or 14) + 3 * bw + 30), 0, 6), Color3.fromRGB(60, 52, 76), 23)
		corner(track, 3)
		local fill = frame(track, "Fill", UDim2.new(), UDim2.fromScale(0, 1), PINK, 24)
		corner(fill, 3)
		local time = text(now, "Time", "", UDim2.new(1, -(3 * bw + 30) - 80, 1, -32), UDim2.fromOffset(78, 14), MUTED, Enum.Font.GothamBold, 12)
		time.TextXAlignment = Enum.TextXAlignment.Right
		self.NowFill, self.NowTime = fill, time
		local function control(i: number, name: string, label: string, color: Color3, fn: () -> ())
			local b = button(now, name, label, color)
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, -8 - (i - 1) * (bw + 6), 0.5, 0)
			b.Size = UDim2.fromOffset(bw, bw)
			b.ZIndex = 24
			corner(b, 12)
			onClick(conns, b, fn)
		end
		control(1, "Chain", state.Chain and "🔁" or "➡️", state.Chain and MINT or Color3.fromRGB(110, 90, 160), function()
			local st = self.PickerState
			st.Chain = not st.Chain
			if self.Cb.Chain then
				self.Cb.Chain(st.Chain)
			end
			self.PickerSig = nil
			self:UpdatePicker(st)
		end)
		control(2, "Stop", "⏹", Color3.fromRGB(226, 80, 104), function()
			self.Cb.StopSong()
		end)
		control(3, "Skip", "⏭", Color3.fromRGB(110, 90, 200), function()
			if self.Cb.Skip then
				self.Cb.Skip()
			end
		end)
		-- file d'attente
		local list = self.QueueList
		if list then
			for _, c in ipairs(list:GetChildren()) do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			if #queue == 0 then
				local empty = text(list, "Empty", T("Tap ➕ on a song to add it here."), UDim2.new(), UDim2.new(1, -4, 0, 40), MUTED, Enum.Font.GothamBold, 13)
				empty.TextWrapped = true
				empty.ZIndex = 24
			end
			for qi, id in ipairs(queue) do
				local i2 = MusicData.SONG_INDEX[id]
				local s2 = i2 and MusicData.SONGS[i2]
				if s2 then
					local row = frame(list, "Item", UDim2.new(), UDim2.new(1, -6, 0, 40), Color3.fromRGB(36, 30, 48), 24)
					row.LayoutOrder = qi
					corner(row, 10)
					local cv = cover(row, s2, UDim2.fromOffset(32, 32), 25)
					cv.Position = UDim2.fromOffset(4, 4)
					local nm = text(row, "Name", qi .. ". " .. T(s2.Name), UDim2.fromOffset(42, 4), UDim2.new(1, -78, 0, 18), WHITE, Enum.Font.GothamBold, 14)
					nm.TextXAlignment = Enum.TextXAlignment.Left
					nm.ZIndex = 25
					local mt = text(row, "Meta", fmt(MusicData.Duration(id)), UDim2.fromOffset(42, 23), UDim2.new(1, -78, 0, 12), MUTED, Enum.Font.GothamBold, 11)
					mt.TextXAlignment = Enum.TextXAlignment.Left
					mt.ZIndex = 25
					local rm = button(row, "Remove", "✖", Color3.fromRGB(226, 80, 104))
					rm.AnchorPoint = Vector2.new(1, 0.5)
					rm.Position = UDim2.new(1, -4, 0.5, 0)
					rm.Size = UDim2.fromOffset(28, 28)
					rm.ZIndex = 26
					onClick(conns, rm, function()
						if self.Cb.Unqueue then
							self.Cb.Unqueue(qi)
						end
					end)
				end
			end
		end
		-- radio
		local playlist = Config.Music and Config.Music.Playlist or {}
		local radioOn = type(state.Radio) == "number" and state.Radio > 0
		local trackInfo = radioOn and playlist[state.Radio] or nil
		if self.RadioButton then
			self.RadioButton.Text = radioOn and ("📻 " .. T("Stage radio: %s (tap: next)", tostring(trackInfo and trackInfo.Name or "?"))) or ("📻 " .. T("Stage radio: lo-fi on the speakers"))
			self.RadioButton.BackgroundColor3 = radioOn and MINT or Color3.fromRGB(96, 150, 230)
		end
		if self.FillGrid then
			self.FillGrid()
		end
	end
	-- progression
	if self.NowFill then
		local progress = math.clamp(tonumber(state.Progress) or 0, 0, 1)
		self.NowFill.Size = UDim2.fromScale(progress, 1)
		if state.Elapsed and state.Total then
			self.NowTime.Text = fmt(state.Elapsed) .. " / " .. fmt(state.Total)
		else
			self.NowTime.Text = ""
		end
	end
end

function MusicUI.ClosePicker(self: any)
	if self.Picker then
		self.Picker:Destroy()
		self.Picker = nil
	end
	UIUtil.DisconnectAll(self.PickerConns)
	self.PickerConns = {}
	self.NowBar = nil
	self.NowFill = nil
	self.NowTime = nil
	self.QueueList = nil
	self.RadioButton = nil
	self.Grid = nil
	self.FillGrid = nil
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
