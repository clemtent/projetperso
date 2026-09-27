--[[
	ClickableKeys (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > ClickableKeys

	v9.1 : tout ce qui rend un clavier dessiné CLIQUABLE (partagé par le
	clavier mécanique et le clavier corail) :
	  - dessin posé (GearPiece) en deux formes : "Full" (QWERTY complet) et
	    "Mini" (petit clavier résumé, quand la place manque) ;
	  - chaque touche = un bouton : appui -> la touche s'enfonce, son de touche
	    (GearClick.PlayKeySound, selon le niveau), VRAI clic (GearClick.Click :
	    même chemin que le gros bouton) ;
	  - touches trop petites pour être visées (< 22 px réels sur PC, < 34 px
	    en tactile) : badge 🔍 et un appui ouvre le GRAND clavier flottant
	    (KeyboardPanel), dessiné avec la même fonction, en grand ;
	  - vrai clavier du joueur (KeyInput) : la touche correspondante s'enfonce
	    (grand clavier s'il est ouvert, sinon le clavier posé) et clique.

	API : ClickableKeys.new(ctx, piece, animator, options) -> controller
	  options = {
	    Id: string,                 -- source du clic ("Keyboard", "CoralKeys")
	    InputPriority: number,      -- (KeyInput) le plus petit clique
	    StepFull, StepMini: number, -- pas des touches du dessin posé (échelle 1)
	    Draw: (root, layout, step, level) -> (keys, largeur, hauteur, extra),
	    Title: () -> string, Tray: Color3?, BadgeInk: Color3?,
	    Lit: ((level) -> Color3?)?, -- couleur d'une touche enfoncée (nil = assombrie)
	    SoundPitch: number?, SoundShift: number?,
	    OnBuilt: ((root, keys, extra, mini) -> ())?,      -- dessin posé refait
	    OnPanelBuilt: ((keys, extra) -> ())?,             -- grand clavier refait
	    OnStrike: ((key, point) -> ())?,                  -- touche frappée (effets en plus)
	  }
	  controller.Keys / controller.PanelKeys / controller.Panel
	  controller:Build(level), controller:AnimateKey(key, delay?),
	  controller:KeyPoint(key) -> Vector2?, controller:Wiggle(), controller:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local GearKit = require(script.Parent.GearKit)
local KeyboardArt = require(script.Parent.KeyboardArt)
local GearClick = require(script.Parent.GearClick)
local KeyInput = require(script.Parent.KeyInput)
local KeyboardPanel = require(script.Parent.KeyboardPanel)

local ClickableKeys = {}
ClickableKeys.__index = ClickableKeys

local DIRECT_DESKTOP = 22 -- taille réelle minimale d'une touche pour la viser (px)
local DIRECT_TOUCH = 34

type Key = KeyboardArt.Key

local function isPress(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

function ClickableKeys.new(ctx: any, piece: any, animator: GearKit.Animator, options: { [string]: any })
	local self = setmetatable({
		Ctx = ctx,
		Piece = piece,
		Animator = animator,
		Options = options,
		Art = nil :: Frame?,
		Keys = {} :: { Key },
		PanelKeys = {} :: { Key },
		KeyUnit = options.StepFull,
		Direct = false,
		Badge = nil :: Frame?,
		Panel = nil :: any,
	}, ClickableKeys)
	local random = ctx.Random

	local function level(): number
		return math.max(1, piece.Level)
	end
	self.Level = level

	-- Grand clavier flottant (construit au premier affichage)
	self.Panel = KeyboardPanel.new(ctx, {
		Id = options.Id,
		Title = options.Title,
		Tray = options.Tray,
		Build = function(parent: Frame, step: number)
			for _, key in ipairs(self.PanelKeys) do
				animator:Stop(key)
			end
			local keys, W, H, extra = options.Draw(parent, "Full", step, level())
			self.PanelKeys = keys
			local callback = options.OnPanelBuilt
			if callback then
				callback(keys, extra)
			end
			return keys, W, H
		end,
		OnKey = function(key: Key)
			self:Strike(key, self.Panel:KeyPoint(key))
		end,
	})

	-- Vrai clavier du joueur -> touches du jeu
	KeyInput.Register(options.Id, {
		Priority = options.InputPriority or 1,
		Active = function(): boolean
			-- (même si le clavier n'a pas de place à l'écran : on tape quand même)
			return ctx.IsAlive() and ctx.GetVisibility() == "Visible"
		end,
		Press = function(code: string, doClick: boolean)
			local key: Key? = nil
			local point: Vector2? = nil
			if self.Panel:IsOpen() then
				key = KeyboardArt.Find(self.PanelKeys, code)
				if key then
					point = self.Panel:KeyPoint(key)
				end
			else
				key = KeyboardArt.Find(self.Keys, code) or KeyboardArt.Pick(self.Keys, 1, random)[1]
				if key then
					point = self:KeyPoint(key)
				end
			end
			if doClick then
				self:Strike(key, point)
			elseif key then
				self:AnimateKey(key)
			end
		end,
	})

	-- Crochets de l'accessoire
	piece.OnShape = function(_shape, _size)
		self:Build(level())
	end
	piece.OnPlaced = function(_placement, _first)
		self:RefreshMode()
	end
	piece.OnHidden = function()
		self:RefreshMode()
	end
	ctx.Connect(ctx.Interface.ScaleChanged, function()
		self:RefreshMode()
	end)
	ctx.Connect(ctx.Interface.DeviceChanged, function()
		self:RefreshMode()
	end)
	return self
end

-- Animation d'une touche (enfoncée puis relâchée)
function ClickableKeys.AnimateKey(self: any, key: Key, delay: number?)
	local wait = delay or 0
	local litFn = self.Options.Lit
	local lit = litFn and litFn(self.Level()) or nil
	self.Animator:Play(key, 0.17 + wait, function(t)
		local k = math.clamp((t * (0.17 + wait) - wait) / 0.17, 0, 1)
		local amount = k < 0.35 and k / 0.35 or 1 - (k - 0.35) / 0.65
		KeyboardArt.Press(key, amount, lit)
	end, function()
		KeyboardArt.Press(key, 0)
	end)
end

-- Point de la toile au-dessus d'une touche du clavier posé
function ClickableKeys.KeyPoint(self: any, key: Key): Vector2?
	return self.Piece:ToCanvas(Vector2.new(key.X + key.W / 2, key.Y))
end

-- Une touche frappée : animation, son de touche, vrai clic
function ClickableKeys.Strike(self: any, key: Key?, point: Vector2?)
	local options = self.Options
	if key then
		self:AnimateKey(key)
	end
	GearClick.PlayKeySound(self.Level(), options.SoundPitch, options.SoundShift)
	GearClick.Click(options.Id, point)
	local callback = options.OnStrike
	if callback and key then
		callback(key, point)
	end
end

-- Les touches posées sont-elles assez grandes pour être visées ?
function ClickableKeys.RefreshMode(self: any)
	local ctx = self.Ctx
	local placement = self.Piece.Placement
	local real = 0
	if placement then
		real = self.KeyUnit * placement.Scale * math.max(0.01, ctx.Interface.Scale or 1)
	end
	local touch = ctx.Interface.Device ~= "Desktop"
	self.Direct = real >= (touch and DIRECT_TOUCH or DIRECT_DESKTOP)
	local badge = self.Badge
	if badge then
		badge.Visible = placement ~= nil and not self.Direct
	end
end

-- (Re)dessine le clavier posé
function ClickableKeys.Build(self: any, lv: number)
	local options = self.Options
	local piece = self.Piece
	for _, key in ipairs(self.Keys) do
		self.Animator:Stop(key)
	end
	if self.Art then
		self.Art:Destroy()
	end
	local mini = piece.Shape > 0
	local size = piece.Size
	local root = Instance.new("Frame")
	root.Name = "Art"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.ZIndex = 2
	local step = mini and options.StepMini or options.StepFull
	local keys, W, _H, extra = options.Draw(root, mini and "Mini" or "Full", step, lv)
	self.Keys = keys
	self.KeyUnit = keys[1] and keys[1].H or step

	-- Badge 🔍 : "appuie pour ouvrir le grand clavier"
	local badgeSize = step * 1.3
	local badge = GearKit.Box(root, W - badgeSize * 0.32, badgeSize * 0.32, badgeSize, badgeSize, Color3.new(1, 1, 1), {
		Name = "ExpandBadge",
		Anchor = Vector2.new(0.5, 0.5),
		Radius = "round",
		Z = 30,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = options.BadgeInk or Color3.fromRGB(52, 44, 72)
	stroke.Thickness = 2
	stroke.Parent = badge
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.BuilderSansBold
	icon.Text = "🔍"
	icon.TextSize = math.floor(badgeSize * 0.6)
	icon.ZIndex = 31
	icon.Parent = badge
	badge.Visible = false
	self.Badge = badge

	-- Chaque touche est un vrai bouton
	for _, key in ipairs(keys) do
		key.Button.InputBegan:Connect(function(input: InputObject)
			if not isPress(input) then
				return
			end
			if self.Direct then
				self:Strike(key, self:KeyPoint(key))
			else
				self:AnimateKey(key)
				self.Panel:Open()
			end
		end)
	end

	root.Parent = piece.Content
	self.Art = root
	local callback = options.OnBuilt
	if callback then
		callback(root, keys, extra, mini)
	end
	self:RefreshMode()
end

-- Le niveau a changé : dessin posé et grand clavier refaits
function ClickableKeys.LevelChanged(self: any, lv: number)
	self:Build(lv)
	self.Panel:MarkDirty()
end

-- Le badge 🔍 fait coucou (au repos)
function ClickableKeys.Wiggle(self: any)
	local badge = self.Badge
	if badge and badge.Visible then
		self.Animator:Play("badge", 0.5, function(t)
			badge.Rotation = math.sin(t * math.pi * 3) * 14 * (1 - t)
		end, function()
			badge.Rotation = 0
		end)
	end
end

-- Titre du grand clavier : "<icône> <nom>  •  Niv. N"
function ClickableKeys.TitleFor(icon: string, name: string, lv: number): string
	return icon .. " " .. Locale.T(name) .. "  •  " .. Locale.T("Lv. %s", tostring(lv))
end

function ClickableKeys.Destroy(self: any)
	KeyInput.Unregister(self.Options.Id)
	self.Panel:Destroy()
end

return ClickableKeys
