--[[
	HousePets (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HousePets

	Les animaux posés dans une pièce (catégorie "Pets") VIVENT quand on ne
	décore pas : ils sortent de chez eux (l'endroit où le joueur les a posés
	= leur "maison" : coquille, panier, perchoir...), se promènent sur le
	sol de la pièce, s'arrêtent, s'assoient, font la sieste, jouent, et
	se servent de leurs affaires :
	  - dorment dans le coussin / la niche (ils entrent dedans !) / en haut
	    de l'arbre à chat ou sur un lit, mangent à la gamelle, boivent à la
	    fontaine, jouent avec le panier de jouets, se font les griffes sur
	    le griffoir, se perchent sur la cage (oiseaux) ;
	  - marche qui rebondit, sauts pour monter sur les meubles, vol pour
	    le perroquet et le dragon, regard dans le sens de la marche (dessin
	    retourné, HouseArt.Mirror), petites bulles 💤 ❤️ 🍖 💧 🎾 ✨ 🎵 ;
	  - profondeur : l'animal passe devant / derrière les meubles selon sa
	    position (même ordre que l'éditeur) ;
	  - toucher un animal = câlin (❤️ + petit saut).
	Visuel seulement : rien n'est sauvegardé, aucun appel au serveur.
	Pause quand la pièce n'est pas affichée (l'éditeur n'appelle Update que
	dans la vue pièce) ; en mode édition, chacun rentre chez soi.
	Les dessins (Art/Pets) rangent l'animal dans des groupes "Pet*" : le
	reste du dessin (sa maison) reste en place pendant sa promenade.
]]

local Client = script.Parent.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local Interface = require(Client.Interface)
local SoundManager = require(Client.SoundManager)
local HouseCommon = require(script.Parent.HouseCommon)
local HouseArt = require(script.Parent.HouseArt)
local HouseTints = require(script.Parent.HouseTints)
local HouseSurfaces = require(script.Parent.HouseSurfaces)

type Placed = HouseCommon.Placed
type Item = HouseCommon.Item

local HousePets = {}

local MAX_ACTORS = 10 -- animaux vivants au plus par pièce
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local random = Random.new()

-- Comportement de chaque animal :
--   Move : "Walk" | "Hop" | "Crawl" | "Fly" ; Speed = px de maquette / s
--   Anchor : ses pieds dans la boîte 100 x 100 du dessin
--   Native : sens où regarde le dessin (1 = droite, -1 = gauche)
--   Likes : envie de chaque activité ; Home : envie de rentrer chez lui
--   Climb : grimpe (arbre à chat, lits) ; Bird : oiseau (cage)
type Species = {
	Move: string,
	Speed: number,
	Anchor: Vector2,
	Native: number,
	Likes: { [string]: number },
	Home: number,
	Climb: boolean?,
	Bird: boolean?,
	Altitude: number?, -- vol : hauteur en px de maquette
	Rest: NumberRange?, -- durée d'une pause à la maison
	Curl: number?, -- pose "roulée en boule" (chat) : décalage vers le bas
}

local SPECIES: { [string]: Species } = {
	Chick = { Move = "Hop", Speed = 34, Anchor = Vector2.new(50, 88), Native = 1, Home = 1.4,
		Likes = { Eat = 2.5, Drink = 1.5, Play = 1.5, Sleep = 1 } },
	SleepyCat = { Move = "Walk", Speed = 40, Anchor = Vector2.new(50, 98), Native = 1, Home = 1.6, Climb = true,
		Rest = NumberRange.new(10, 22), Curl = 24,
		Likes = { Sleep = 3, Scratch = 2.2, Perch = 2, Sit = 1.8, Eat = 1.2, Drink = 1, Play = 1, Enter = 1.2 } },
	Turtle = { Move = "Crawl", Speed = 11, Anchor = Vector2.new(46, 96), Native = 1, Home = 0.8,
		Likes = { Eat = 2.5, Drink = 2, Sleep = 0.6 } },
	Puppy = { Move = "Walk", Speed = 72, Anchor = Vector2.new(50, 98), Native = -1, Home = 0.6,
		Likes = { Enter = 2, Sleep = 1.4, Eat = 2, Drink = 1.5, Play = 3 } },
	Bunny = { Move = "Hop", Speed = 56, Anchor = Vector2.new(50, 98), Native = -1, Home = 0.8,
		Likes = { Eat = 2.5, Drink = 1.5, Sleep = 1.4, Play = 1.5, Enter = 0.8 } },
	Fox = { Move = "Walk", Speed = 60, Anchor = Vector2.new(46, 98), Native = -1, Home = 0.8, Climb = true,
		Likes = { Sleep = 2, Enter = 1.6, Play = 2, Eat = 1.5, Drink = 1, Perch = 0.6 } },
	Parrot = { Move = "Fly", Speed = 90, Anchor = Vector2.new(42, 42), Native = 1, Home = 1.5, Bird = true, Altitude = 44,
		Likes = { Perch = 3, Eat = 0.8, Drink = 0.6, Play = 0.6 } },
	Dragon = { Move = "Fly", Speed = 52, Anchor = Vector2.new(50, 98), Native = -1, Home = 1, Altitude = 22,
		Likes = { Perch = 1.4, Sleep = 1.5, Play = 2, Eat = 1 } },
	-- v9 : chaton (grimpe sur les lits, canapés, chaises...) et hérisson
	Kitten = { Move = "Walk", Speed = 46, Anchor = Vector2.new(52, 98), Native = 1, Home = 1.4, Climb = true,
		Rest = NumberRange.new(8, 18), Curl = 18,
		Likes = { Sleep = 2.6, Play = 2.4, Scratch = 1.6, Perch = 1.6, Sit = 1.6, Eat = 1.2, Drink = 1, Enter = 1 } },
	Hedgehog = { Move = "Walk", Speed = 24, Anchor = Vector2.new(46, 96), Native = -1, Home = 1.2,
		Likes = { Eat = 2.6, Drink = 1.6, Sleep = 1.6, Play = 1, Enter = 0.8 } },
}

local EMOTES: { [string]: { string } } = {
	Sleep = { "💤" },
	Enter = { "💤" },
	Eat = { "🍖", "😋" },
	Drink = { "💧" },
	Play = { "🎾", "✨" },
	Scratch = { "✨" },
	Perch = { "🎵", "❤️" },
	Sit = { "❤️" },
	Happy = { "❤️", "💕" },
	Idle = { "❤️", "✨", "🎵" },
}

export type Step = {
	K: string, -- "Walk" | "Jump" | "Fly" | "Act" | "Home"
	X: number?,
	Y: number?,
	Elev: Placed?, -- meuble sur lequel il arrive (en hauteur)
	Base: number?,
	Act: string?,
	Dur: number?,
	Face: number?,
	Z: number?, -- décalage de profondeur par rapport au meuble (-1 derrière, +1 devant)
	Target: Placed?,
	Key: string?,
}

type Actor = {
	Entry: Placed,
	Item: Item,
	Def: Species,
	Sticker: any,
	Parts: { GuiObject }, -- parties "animal" du dessin posé (cachées pendant la promenade)
	HasProps: boolean,
	Holder: Frame?,
	Body: Frame?,
	Shrink: UIScale?,
	Shadow: Frame?,
	Anims: { HouseArt.Anim },
	WalkPose: GuiObject?,
	CurlParts: { GuiObject },
	CanTilt: boolean,
	Mirrored: boolean,
	X: number,
	Y: number,
	Alt: number, -- vol : hauteur actuelle (px de boîte)
	Elev: Placed?,
	Base: number,
	Out: boolean,
	State: string,
	Timer: number,
	Plan: { Step },
	Current: Step?,
	From: Vector2?,
	Progress: number,
	Joy: number, -- saut de joie (câlin), secondes restantes
	Phase: number,
	Facing: number,
	Curled: boolean,
	ZTimer: number,
	Emote: Frame?,
	EmoteLabel: TextLabel?,
	EmoteScale: UIScale?,
	EmoteStroke: UIStroke?,
	EmoteT: number,
	EmoteEvery: number,
	Spot: string?, -- place occupée (clé)
	Hidden: boolean, -- entré dans la niche / la cachette
	HiddenOver: Placed?,
}

export type Pets = {
	Refresh: (layout: { Placed }, stickers: { [Placed]: any }) -> (),
	SetLive: (on: boolean) -> (),
	IsLive: () -> boolean,
	Update: (dt: number) -> (),
	Clear: () -> (),
	Count: () -> number,
	Poke: (entry: Placed) -> boolean,
}

local function isPetPart(object: Instance): boolean
	return object:IsA("GuiObject") and string.sub(object.Name, 1, 3) == "Pet"
end

-- Parties "animal" du dessin d'un autocollant ; (liste, a-t-il une maison ?)
local function stickerParts(sticker: any): ({ GuiObject }, boolean)
	local parts: { GuiObject } = {}
	local props = false
	local body = sticker and sticker.Body
	if not body then
		return parts, false
	end
	for _, child in ipairs(body:GetChildren()) do
		if child:IsA("GuiObject") then
			if isPetPart(child) then
				if child.Name ~= "PetWalk" then
					table.insert(parts, child)
				end
			elseif child.Name ~= "Emoji" and child.Name ~= "Glow" then
				props = true
			end
		end
	end
	return parts, props
end

function HousePets.Has(itemId: string): boolean
	return SPECIES[itemId] ~= nil
end

function HousePets.new(room: any): Pets
	local pets: Pets
	local actors: { [Placed]: Actor } = {}
	local layout: { Placed } = {}
	local stickers: { [Placed]: any } = {}
	local live = false
	local clock = 0
	local occupied: { [string]: Actor } = {}
	-- Profondeur : objets au sol (Y "effectif", ZIndex) et fond (murs, tapis)
	local floorZ: { { Y: number, Z: number } } = {}
	local baseZ = 10

	local function roomW(): number
		return math.max(1, room.Width)
	end
	local function roomH(): number
		return math.max(1, room.Height)
	end

	-- Bornes du sol (pieds)
	local function floorBounds(): (number, number)
		local minY = HouseCommon.ZoneBounds("Floor")
		return minY + 0.05, 0.965
	end

	local function clampFloor(actor: Actor, x: number, y: number): (number, number)
		local minY, maxY = floorBounds()
		local half = actor.Item.Size * actor.Entry.S * 0.3 / roomW()
		return math.clamp(x, math.max(0.07, half), math.min(0.93, 1 - half)), math.clamp(y, minY, maxY)
	end

	local function stickerZ(entry: Placed?): number
		local sticker = entry and stickers[entry]
		if sticker and sticker.Frame then
			return sticker.Frame.ZIndex
		end
		return baseZ
	end

	local function floorDepth(y: number): number
		local z = baseZ
		for _, info in ipairs(floorZ) do
			if info.Y <= y and info.Z + 1 > z then
				z = info.Z + 1
			end
		end
		return z
	end

	----------------------------------------------------------------------
	-- Construction d'un animal vivant
	----------------------------------------------------------------------

	local function showSticker(actor: Actor, visible: boolean)
		for _, part in ipairs(actor.Parts) do
			part.Visible = visible
		end
		local sticker = actor.Sticker
		if sticker and not actor.HasProps and sticker.Shadow then
			sticker.Shadow.Visible = visible
		end
	end

	local function setCurled(actor: Actor, curled: boolean)
		local walk = actor.WalkPose
		if not walk or actor.Curled == curled then
			return
		end
		actor.Curled = curled
		walk.Visible = not curled
		for _, part in ipairs(actor.CurlParts) do
			part.Visible = curled
		end
	end

	local function setFacing(actor: Actor, dir: number)
		if dir == 0 or dir == actor.Facing then
			return
		end
		actor.Facing = dir
		local body = actor.Body
		local want = dir ~= actor.Def.Native
		if body and want ~= actor.Mirrored then
			actor.Mirrored = want
			HouseArt.Mirror(body, actor.Anims, actor.Def.Anchor.X)
		end
	end

	local function emote(actor: Actor, text: string?)
		local frame = actor.Emote
		local label = actor.EmoteLabel
		if not frame or not label or not text then
			return
		end
		label.Text = text
		actor.EmoteT = 0
		frame.Visible = true
	end

	local function emoteFor(actor: Actor, act: string)
		local list = EMOTES[act]
		if list then
			emote(actor, list[random:NextInteger(1, #list)])
		end
	end

	local function build(actor: Actor)
		if actor.Holder then
			return
		end
		local def = actor.Def
		local holder = UIUtil.Create("Frame", {
			Name = "Pet_" .. actor.Item.Id,
			Size = UDim2.fromOffset(100, 100),
			AnchorPoint = Vector2.new(def.Anchor.X / 100, def.Anchor.Y / 100),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = baseZ,
		})
		UIUtil.Create("UIScale", { Scale = actor.Item.Size * actor.Entry.S / 100, Parent = holder })
		local shadow = UIUtil.Create("Frame", {
			Name = "Shadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(def.Anchor.X, def.Anchor.Y - 2),
			Size = UDim2.fromOffset(62, 12),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = holder,
		})
		UIUtil.Corner(shadow, UDim.new(1, 0))
		local body = UIUtil.Create("Frame", {
			Name = "Body",
			Size = UDim2.fromOffset(100, 100),
			AnchorPoint = Vector2.new(def.Anchor.X / 100, def.Anchor.Y / 100),
			Position = UDim2.fromOffset(def.Anchor.X, def.Anchor.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = holder,
		})
		local _, anims = HouseArt.Paint(body, actor.Item, false)
		-- (v9.1) même couleur que l'autocollant posé
		if actor.Entry.C then
			HouseTints.Apply(body, actor.Entry.C)
		end
		-- (rétrécit vers ses pieds quand il entre dans la niche)
		local shrink = UIUtil.Create("UIScale", { Name = "Shrink", Parent = body })
		-- On ne garde que l'animal (pas sa coquille, son panier, son perchoir...)
		local canTilt = true
		for _, child in ipairs(body:GetChildren()) do
			if not isPetPart(child) then
				child:Destroy()
			end
		end
		local kept: { HouseArt.Anim } = {}
		for _, anim in ipairs(anims) do
			if anim.Object:IsDescendantOf(body) then
				table.insert(kept, anim)
			end
		end
		for _, object in ipairs(body:GetDescendants()) do
			if object:IsA("GuiObject") and object.ClipsDescendants then
				-- (Roblox ne découpe pas dans un cadre tourné : pas d'inclinaison)
				canTilt = false
			end
			if object.Name == "Tail" and object:IsA("GuiObject") then
				object.Visible = false
			end
		end
		local walk = body:FindFirstChild("PetWalk") :: GuiObject?
		local curl: { GuiObject } = {}
		if walk then
			walk.Visible = true
			for _, child in ipairs(body:GetChildren()) do
				if child:IsA("GuiObject") and child ~= walk then
					child.Visible = false
					table.insert(curl, child)
				end
			end
		end
		-- Zone de câlin
		local hit = UIUtil.Create("TextButton", {
			Name = "Hit",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(def.Anchor.X, def.Anchor.Y),
			Size = UDim2.fromOffset(74, math.min(90, def.Anchor.Y)),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 5,
			Parent = holder,
		})
		-- Bulle d'émotion (calque au-dessus de la pièce, taille fixe)
		local bubble = UIUtil.Create("Frame", {
			Name = "PetEmote",
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(34, 32),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.05,
			Visible = false,
			ZIndex = 30,
			Parent = room.Overlay,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
		local stroke = UIUtil.Stroke(bubble, C.Pink, 2, 0.2)
		local bubbleScale = UIUtil.Create("UIScale", { Parent = bubble })
		local tailDot = UIUtil.Create("Frame", {
			Name = "Tip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 4, 1, 3),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = WHITE,
			ZIndex = 30,
			Parent = bubble,
		})
		UIUtil.Corner(tailDot, UDim.new(1, 0))
		local label = UIUtil.Create("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansMedium,
			Text = "",
			TextSize = 20,
			TextColor3 = WHITE,
			ZIndex = 31,
			Parent = bubble,
		})
		actor.Holder = holder
		actor.Body = body
		actor.Shrink = shrink
		actor.Shadow = shadow
		actor.Anims = kept
		actor.WalkPose = walk
		actor.CurlParts = curl
		actor.Curled = false
		actor.CanTilt = canTilt
		actor.Mirrored = false
		actor.Facing = def.Native
		actor.Emote = bubble
		actor.EmoteLabel = label
		actor.EmoteScale = bubbleScale
		actor.EmoteStroke = stroke
		hit.Activated:Connect(function()
			if not live or not actor.Out or actor.Hidden then
				return
			end
			emoteFor(actor, "Happy")
			SoundManager.Play("Pop", 1.15 + random:NextNumber() * 0.2)
			local layer = Effects.GetLayer()
			if layer then
				local center = Interface.GetCanvasCenter(body)
				Effects.Burst(layer, UDim2.fromOffset(center.X, center.Y), C.Pink, 7)
			end
			-- Petit saut de joie (sans interrompre ce qu'il fait)
			actor.Joy = 0.45
			local current = actor.Current
			if current and current.K == "Act" and current.Act == "Sleep" then
				-- réveillé par un câlin
				actor.Timer = math.min(actor.Timer, 0.6)
			end
		end)
		holder.Parent = room.Items
	end

	local function destroyActor(actor: Actor)
		if actor.Spot then
			occupied[actor.Spot] = nil
			actor.Spot = nil
		end
		if actor.Holder then
			(actor.Holder :: Frame):Destroy()
		end
		if actor.Emote then
			(actor.Emote :: Frame):Destroy()
		end
		actor.Holder = nil
		actor.Body = nil
		actor.Emote = nil
		showSticker(actor, true)
	end

	----------------------------------------------------------------------
	-- Choix de la prochaine activité
	----------------------------------------------------------------------

	local function home(actor: Actor): (number, number, Placed?, number)
		local entry = actor.Entry
		local support = HouseSurfaces.SupportOf(entry, layout, roomW(), roomH())
		if support then
			return entry.X, entry.Y, support.Entry, support.Base
		end
		return entry.X, entry.Y, nil, entry.Y
	end

	-- Étapes pour aller en (x, y) ; elev = meuble en hauteur à l'arrivée
	local function route(actor: Actor, x: number, y: number, elev: Placed?, base: number): { Step }
		local steps: { Step } = {}
		if actor.Def.Move == "Fly" then
			table.insert(steps, { K = "Fly", X = x, Y = y, Elev = elev, Base = base })
			return steps
		end
		if actor.Elev then
			local fx, fy = clampFloor(actor, actor.X + (random:NextNumber() - 0.5) * 0.06, actor.Base + 0.02)
			table.insert(steps, { K = "Jump", X = fx, Y = fy })
		end
		if elev then
			local fx, fy = clampFloor(actor, x, base + 0.02)
			table.insert(steps, { K = "Walk", X = fx, Y = fy })
			table.insert(steps, { K = "Jump", X = x, Y = y, Elev = elev, Base = base })
		else
			table.insert(steps, { K = "Walk", X = x, Y = y })
		end
		return steps
	end

	local function chooseNext(actor: Actor)
		local def = actor.Def
		local options: { { W: number, Plan: { Step } } } = {}
		local function add(weight: number, plan: { Step })
			if weight > 0 then
				table.insert(options, { W = weight, Plan = plan })
			end
		end
		local minY, maxY = floorBounds()
		-- Promenade
		do
			local x = actor.X + (random:NextNumber() - 0.5) * 0.6
			local y = minY + random:NextNumber() * (maxY - minY)
			local fx, fy = clampFloor(actor, x, y)
			local plan = route(actor, fx, fy, nil, fy)
			table.insert(plan, { K = "Act", Act = random:NextNumber() < 0.5 and "Idle" or "Sit", Dur = 1.2 + random:NextNumber() * 2.5 })
			add(def.Move == "Fly" and 2 or 3, plan)
		end
		-- Petite pause sur place
		if not actor.Elev then
			add(1, { { K = "Act", Act = "Idle", Dur = 1.5 + random:NextNumber() * 2 } })
		end
		-- Retour à la maison
		do
			local hx, hy, elev, base = home(actor)
			local plan = route(actor, hx, hy, elev, base)
			table.insert(plan, { K = "Home" })
			add(def.Home, plan)
		end
		-- Affaires des animaux (gamelle, niche, arbre à chat...) et meubles
		for index, entry in ipairs(layout) do
			local item = HouseCommon.ItemsById[entry.I]
			local spots = HouseSurfaces.Spots(entry.I)
			if item and spots then
				for spotIndex, spot in ipairs(spots) do
					local like = def.Likes[spot.Act] or 0
					local key = tostring(index) .. ":" .. entry.I .. ":" .. spotIndex
					local allowed = like > 0 and (occupied[key] == nil or occupied[key] == actor)
					if spot.High and not (def.Climb or def.Move == "Fly") then
						allowed = false
					end
					if spot.Birds and not def.Bird then
						allowed = false
					end
					if spot.Act == "Enter" and def.Move == "Fly" then
						allowed = false
					end
					if allowed then
						local sx, sy = HouseSurfaces.BoxToRoom(entry, item, spot.X, spot.Y, roomW(), roomH())
						local side = actor.X < sx and -1 or 1
						local petW = actor.Item.Size * actor.Entry.S / roomW()
						local furnW = item.Size * entry.S / roomW()
						local x, y, zOffset, elev = sx, sy, 1, nil
						if spot.Place == "Behind" then
							x = sx + side * petW * 0.22
							y = entry.Y - 0.012
							zOffset = -1
						elseif spot.Place == "Beside" then
							x = sx + side * (furnW * 0.3 + petW * 0.3)
							y = entry.Y + 0.008
						elseif spot.High then
							elev = entry
						end
						if not elev then
							x, y = clampFloor(actor, x, y)
						end
						local plan = route(actor, x, y, elev, entry.Y)
						local duration = spot.Act == "Sleep" and (8 + random:NextNumber() * 8)
							or (spot.Act == "Enter" and (7 + random:NextNumber() * 7))
							or (3.5 + random:NextNumber() * 3)
						table.insert(plan, {
							K = "Act",
							Act = spot.Act,
							Dur = duration,
							Face = -side,
							Z = zOffset,
							Target = entry,
							Key = key,
						})
						add(like, plan)
					end
				end
			end
			-- Sieste sur un lit / perchoir sur un meuble
			if item and HouseSurfaces.Has(entry.I) and (def.Climb or def.Move == "Fly") then
				local act = def.Move == "Fly" and "Perch" or (HouseSurfaces.IsBed(entry.I) and "Sleep" or nil)
				local like = act and (def.Likes[act] or 0) * 0.5 or 0
				if act and like > 0 then
					for _, surface in ipairs(HouseSurfaces.Of(entry, roomW(), roomH())) do
						if surface.Y >= HouseSurfaces.MinY() - 0.1 and surface.R - surface.L > 0.03 then
							local x = surface.L + (surface.R - surface.L) * (0.25 + random:NextNumber() * 0.5)
							local plan = route(actor, x, surface.Y, entry, surface.Base)
							table.insert(plan, {
								K = "Act",
								Act = act,
								Dur = act == "Sleep" and (8 + random:NextNumber() * 7) or (3 + random:NextNumber() * 4),
								Z = 1,
								Target = entry,
							})
							add(like, plan)
						end
					end
				end
			end
		end
		-- Tirage pondéré
		local total = 0
		for _, option in ipairs(options) do
			total += option.W
		end
		local pick = random:NextNumber() * total
		for _, option in ipairs(options) do
			pick -= option.W
			if pick <= 0 then
				actor.Plan = option.Plan
				return
			end
		end
		actor.Plan = options[1] and options[1].Plan or {}
	end

	----------------------------------------------------------------------
	-- Sortir / rentrer
	----------------------------------------------------------------------

	local function goHome(actor: Actor, instant: boolean)
		if actor.Spot then
			occupied[actor.Spot] = nil
			actor.Spot = nil
		end
		actor.Out = false
		actor.Hidden = false
		actor.HiddenOver = nil
		actor.Plan = {}
		actor.Current = nil
		actor.State = "Home"
		local rest = actor.Def.Rest
		actor.Timer = instant and (0.6 + random:NextNumber() * 3)
			or (rest and (rest.Min + random:NextNumber() * (rest.Max - rest.Min)) or (4 + random:NextNumber() * 7))
		local x, y, elev, base = home(actor)
		actor.X, actor.Y, actor.Elev, actor.Base = x, y, elev, base
		actor.Alt = 0
		local holder = actor.Holder
		if holder then
			holder.Visible = false
		end
		if actor.Emote then
			(actor.Emote :: Frame).Visible = false
		end
		showSticker(actor, true)
	end

	local function leaveHome(actor: Actor)
		build(actor)
		local x, y, elev, base = home(actor)
		actor.X, actor.Y, actor.Elev, actor.Base = x, y, elev, base
		actor.Alt = 0
		actor.Out = true
		actor.Hidden = false
		setCurled(actor, false)
		showSticker(actor, false)
		local holder = actor.Holder :: Frame
		holder.Visible = true
		actor.State = "Plan"
		actor.Plan = {}
		actor.Current = nil
		chooseNext(actor)
		-- (une petite bulle en sortant, parfois)
		if random:NextNumber() < 0.4 then
			emoteFor(actor, "Idle")
		end
	end

	----------------------------------------------------------------------
	-- Mise à jour
	----------------------------------------------------------------------

	local function startStep(actor: Actor, step: Step)
		actor.Current = step
		actor.From = Vector2.new(actor.X, actor.Y)
		actor.Progress = 0
		actor.Timer = step.Dur or 0
		if step.K == "Act" then
			local act = step.Act or "Idle"
			if step.Face then
				setFacing(actor, step.Face :: number)
			end
			if step.Key then
				occupied[step.Key :: string] = actor
				actor.Spot = step.Key
			end
			if act == "Sleep" and actor.Def.Curl then
				setCurled(actor, true)
			end
			if act == "Enter" then
				actor.HiddenOver = step.Target
			end
			actor.EmoteEvery = 0.4
			if act ~= "Idle" or random:NextNumber() < 0.3 then
				emoteFor(actor, act)
			end
		elseif step.K == "Home" then
			goHome(actor, false)
		else
			local tx = step.X or actor.X
			if math.abs(tx - actor.X) > 0.004 then
				setFacing(actor, tx > actor.X and 1 or -1)
			end
		end
	end

	local function finishStep(actor: Actor)
		local step = actor.Current
		if step and step.K == "Act" then
			if actor.Spot then
				occupied[actor.Spot :: string] = nil
				actor.Spot = nil
			end
			setCurled(actor, false)
			if actor.Hidden then
				actor.Hidden = false
				actor.HiddenOver = nil
			end
		elseif step and (step.K == "Jump" or step.K == "Fly") then
			actor.Elev = step.Elev
			actor.Base = step.Base or (step.Y or actor.Y)
		end
		actor.Current = nil
	end

	local function moveTowards(actor: Actor, tx: number, ty: number, speed: number, dt: number): boolean
		local dx = (tx - actor.X) * roomW()
		local dy = (ty - actor.Y) * roomH()
		local distance = math.sqrt(dx * dx + dy * dy)
		local stepLength = speed * dt
		if distance <= stepLength or distance < 0.5 then
			actor.X, actor.Y = tx, ty
			return true
		end
		actor.X += dx / distance * stepLength / roomW()
		actor.Y += dy / distance * stepLength / roomH()
		return false
	end

	local function updateActor(actor: Actor, dt: number)
		if not actor.Out then
			actor.Timer -= dt
			if actor.Timer <= 0 and live then
				leaveHome(actor)
			end
			return
		end
		local holder = actor.Holder :: Frame
		local body = actor.Body :: Frame
		local shadow = actor.Shadow :: Frame
		local def = actor.Def
		local k = actor.Item.Size * actor.Entry.S / 100 -- px de maquette par unité de boîte
		if not actor.Current then
			if #actor.Plan == 0 then
				chooseNext(actor)
			end
			local nextStep = table.remove(actor.Plan, 1)
			if nextStep then
				startStep(actor, nextStep)
			end
			if not actor.Out then
				return
			end
		end
		local step = actor.Current
		local lift = 0 -- (px de boîte, vers le haut)
		local tilt = 0
		local speed = def.Speed
		local flying = def.Move == "Fly"
		local targetAlt = 0
		if step then
			local kind = step.K
			if kind == "Walk" then
				local tx, ty = step.X or actor.X, step.Y or actor.Y
				if def.Move == "Hop" then
					-- sauts de lapin : on avance pendant le saut, pause entre deux
					local cycle = 0.62
					local before = actor.Phase % cycle
					actor.Phase += dt
					local t = actor.Phase % cycle
					if t < 0.44 then
						local arrived = moveTowards(actor, tx, ty, speed * 1.45, dt)
						lift = math.sin(t / 0.44 * math.pi) * 13
						if arrived then
							finishStep(actor)
						end
					elseif before < 0.44 and moveTowards(actor, tx, ty, 0, dt) then
						finishStep(actor)
					end
				else
					actor.Phase += dt * (def.Move == "Crawl" and 5 or 9)
					lift = math.abs(math.sin(actor.Phase)) * (def.Move == "Crawl" and 1 or 4.5)
					tilt = def.Move == "Crawl" and 0 or math.sin(actor.Phase) * 5
					if moveTowards(actor, tx, ty, speed, dt) then
						finishStep(actor)
					end
				end
			elseif kind == "Fly" then
				local tx, ty = step.X or actor.X, step.Y or actor.Y
				actor.Phase += dt
				local arrived = moveTowards(actor, tx, ty, speed, dt)
				targetAlt = arrived and 0 or (def.Altitude or 30)
				-- (atterrissage en douceur)
				local remaining = math.abs(tx - actor.X) * roomW() + math.abs(ty - actor.Y) * roomH()
				if remaining < 40 then
					targetAlt = (def.Altitude or 30) * remaining / 40
				end
				tilt = math.sin(actor.Phase * 3) * 3
				if arrived and actor.Alt < 2 then
					finishStep(actor)
				end
			elseif kind == "Jump" then
				local from = actor.From or Vector2.new(actor.X, actor.Y)
				local tx, ty = step.X or actor.X, step.Y or actor.Y
				actor.Progress += dt / 0.55
				local t = math.min(1, actor.Progress)
				actor.X = from.X + (tx - from.X) * t
				actor.Y = from.Y + (ty - from.Y) * t
				local climb = math.max(0, (from.Y - ty) * roomH()) / k
				lift = math.sin(t * math.pi) * (18 + climb * 0.25) + (1 - t) * 0
				tilt = -actor.Facing * 8 * math.sin(t * math.pi)
				if t >= 1 then
					finishStep(actor)
				end
			elseif kind == "Act" then
				local act = step.Act or "Idle"
				actor.Timer -= dt
				actor.Phase += dt
				local t = actor.Phase
				if act == "Eat" or act == "Drink" then
					lift = -1.5 + math.abs(math.sin(t * 7)) * 1.5
					tilt = actor.Facing * (7 + math.sin(t * 7) * 3)
				elseif act == "Play" then
					local hop = (t % 0.7) / 0.7
					lift = math.sin(hop * math.pi) * 9
					if hop < dt / 0.7 and random:NextNumber() < 0.5 then
						setFacing(actor, -actor.Facing)
					end
				elseif act == "Scratch" then
					tilt = actor.Facing * 6 + math.sin(t * 22) * 4
					lift = 2 + math.sin(t * 22) * 1
				elseif act == "Sleep" then
					lift = def.Curl and -def.Curl or 0
					lift -= math.sin(t * 1.6) * 0.6
				elseif act == "Sit" or act == "Perch" or act == "Idle" then
					lift = 0
					if flying and not actor.Elev and act == "Idle" then
						targetAlt = (def.Altitude or 30) * 0.8
					end
					-- regarde autour de lui de temps en temps
					if random:NextNumber() < dt * 0.25 then
						setFacing(actor, -actor.Facing)
					end
				elseif act == "Enter" then
					-- disparaît dans la niche / la cachette
					actor.Progress += dt / 0.35
					if not actor.Hidden and actor.Progress >= 1 then
						actor.Hidden = true
					end
				end
				-- bulle répétée (💤...)
				actor.EmoteEvery -= dt
				if actor.EmoteEvery <= 0 then
					actor.EmoteEvery = (act == "Sleep" or act == "Enter") and 2.8 or 3.6
					if act == "Sleep" or act == "Enter" or act == "Eat" or act == "Drink" or act == "Play" then
						emoteFor(actor, act)
					end
				end
				if actor.Timer <= 0 then
					if act == "Enter" and actor.Hidden then
						-- ressort de la niche
						actor.Hidden = false
						actor.HiddenOver = nil
						actor.Progress = 0
						actor.Joy = 0.45
					end
					finishStep(actor)
				end
			end
		end
		-- Câlin : petit saut par-dessus le reste
		if actor.Joy > 0 then
			actor.Joy = math.max(0, actor.Joy - dt)
			lift += math.sin(actor.Joy / 0.45 * math.pi) * 10
		end
		-- Vol : hauteur qui suit la cible
		if flying then
			actor.Alt += (targetAlt - actor.Alt) * math.min(1, dt * 4)
			lift += actor.Alt + (actor.Alt > 3 and math.sin(clock * 4 + actor.X * 20) * 2.5 or 0)
		end
		-- Dessin
		holder.Position = UDim2.fromScale(actor.X, actor.Y)
		local hidden = actor.Hidden
		local current = actor.Current
		local entering = current and current.K == "Act" and current.Act == "Enter" and not hidden
		local shrink = 1
		if entering then
			shrink = math.max(0.05, 1 - math.clamp(actor.Progress, 0, 1) * 0.95)
		end
		if holder.Visible == hidden then
			holder.Visible = not hidden
		end
		body.Position = UDim2.fromOffset(def.Anchor.X, def.Anchor.Y - lift)
		body.Rotation = actor.CanTilt and tilt or 0
		local shrinkScale = actor.Shrink
		if shrinkScale and shrinkScale.Scale ~= shrink then
			shrinkScale.Scale = shrink
		end
		local altitude = math.max(0, lift)
		shadow.Visible = not (current and current.K == "Act" and current.Act == "Sleep" and def.Curl ~= nil)
		shadow.Size = UDim2.fromOffset(62 * math.clamp(1 - altitude / 70, 0.45, 1) * shrink, 12 * math.clamp(1 - altitude / 70, 0.45, 1) * shrink)
		shadow.BackgroundTransparency = 0.86 + math.clamp(altitude / 70, 0, 1) * 0.08
		-- Profondeur (quelques fois par seconde)
		actor.ZTimer -= dt
		if actor.ZTimer <= 0 then
			actor.ZTimer = 0.15
			local z
			local over = actor.Elev
			if current and current.K == "Act" and current.Target and current.Z then
				z = stickerZ(current.Target) + (current.Z :: number)
			elseif over then
				z = stickerZ(over) + 1
			elseif current and current.K == "Jump" and current.Elev then
				z = stickerZ(current.Elev) + 1
			else
				z = floorDepth(actor.Y)
			end
			if flying and actor.Alt > 10 then
				z = math.max(z, floorDepth(actor.Y + 0.02))
			end
			if holder.ZIndex ~= z then
				holder.ZIndex = z
			end
		end
		if #actor.Anims > 0 then
			HouseArt.Step(actor.Anims, clock)
		end
		-- Bulle d'émotion
		local bubble = actor.Emote
		if bubble and bubble.Visible then
			actor.EmoteT += dt
			local t = actor.EmoteT
			local headY = actor.Y * roomH() - (def.Anchor.Y - 6) * k - lift * k
			local anchorX = actor.X * roomW()
			local over = actor.HiddenOver
			if hidden and over then
				local item = HouseCommon.ItemsById[over.I]
				if item then
					headY = over.Y * roomH() - item.Size * over.S * 0.95
					anchorX = over.X * roomW()
				end
			end
			bubble.Position = UDim2.fromOffset(anchorX + 10, headY - math.min(t, 1.6) * 8)
			local scale = actor.EmoteScale :: UIScale
			scale.Scale = t < 0.18 and (0.3 + t / 0.18 * 0.8) or (t < 0.3 and 1.1 - (t - 0.18) / 0.12 * 0.1 or 1)
			local fade = math.clamp((t - 1.3) / 0.4, 0, 1)
			bubble.BackgroundTransparency = 0.05 + fade * 0.95
			local label = actor.EmoteLabel :: TextLabel
			label.TextTransparency = fade
			local stroke = actor.EmoteStroke :: UIStroke
			stroke.Transparency = 0.2 + fade * 0.8
			local tip = bubble:FindFirstChild("Tip") :: Frame?
			if tip then
				tip.BackgroundTransparency = bubble.BackgroundTransparency
			end
			if t >= 1.7 then
				bubble.Visible = false
			end
		end
	end

	----------------------------------------------------------------------
	-- API
	----------------------------------------------------------------------

	local function computeDepths()
		table.clear(floorZ)
		baseZ = 10
		for entry, sticker in pairs(stickers) do
			local item = HouseCommon.ItemsById[entry.I]
			local frame = sticker and sticker.Frame
			if item and frame then
				if item.Placement == "Wall" or sticker.Flat then
					baseZ = math.max(baseZ, frame.ZIndex + 1)
				else
					local support = HouseSurfaces.SupportOf(entry, layout, roomW(), roomH())
					local root = support and support.Base or entry.Y
					table.insert(floorZ, { Y = root, Z = frame.ZIndex })
				end
			end
		end
	end

	pets = {
		Refresh = function(newLayout: { Placed }, newStickers: { [Placed]: any })
			layout = newLayout
			stickers = newStickers
			local present: { [Placed]: boolean } = {}
			local count = 0
			for _, entry in ipairs(layout) do
				present[entry] = true
				local def = SPECIES[entry.I]
				local item = HouseCommon.ItemsById[entry.I]
				if def and item then
					local actor = actors[entry]
					if not actor and count < MAX_ACTORS then
						actor = {
							Entry = entry,
							Item = item,
							Def = def,
							Sticker = nil,
							Parts = {},
							HasProps = false,
							Holder = nil,
							Body = nil,
							Shrink = nil,
							Shadow = nil,
							Anims = {},
							WalkPose = nil,
							CurlParts = {},
							CanTilt = true,
							Mirrored = false,
							X = entry.X,
							Y = entry.Y,
							Alt = 0,
							Elev = nil,
							Base = entry.Y,
							Out = false,
							State = "Home",
							Timer = 0.5 + random:NextNumber() * 3,
							Plan = {},
							Current = nil,
							From = nil,
							Progress = 0,
							Joy = 0,
							Phase = random:NextNumber() * 3,
							Facing = def.Native,
							Curled = false,
							ZTimer = 0,
							Emote = nil,
							EmoteLabel = nil,
							EmoteScale = nil,
							EmoteStroke = nil,
							EmoteT = 0,
							EmoteEvery = 0,
							Spot = nil,
							Hidden = false,
							HiddenOver = nil,
						}
						actors[entry] = actor
					end
					if actor then
						count += 1
						local sticker = stickers[entry]
						if sticker ~= actor.Sticker then
							actor.Sticker = sticker
							actor.Parts, actor.HasProps = stickerParts(sticker)
							showSticker(actor, not actor.Out)
						end
					end
				end
			end
			for entry, actor in pairs(actors) do
				if not present[entry] then
					destroyActor(actor)
					actors[entry] = nil
				end
			end
			computeDepths()
		end,
		SetLive = function(on: boolean)
			if live == on then
				return
			end
			live = on
			for _, actor in pairs(actors) do
				if actor.Out or not on then
					goHome(actor, true)
				end
				if on then
					actor.Timer = 0.4 + random:NextNumber() * 2.5
				end
			end
			computeDepths()
		end,
		IsLive = function(): boolean
			return live
		end,
		Update = function(dt: number)
			if not live then
				return
			end
			clock += dt
			for _, actor in pairs(actors) do
				updateActor(actor, dt)
			end
		end,
		Clear = function()
			for entry, actor in pairs(actors) do
				destroyActor(actor)
				actors[entry] = nil
			end
			table.clear(occupied)
		end,
		-- Toucher un animal resté chez lui : il se réveille et sort (❤️)
		Poke = function(entry: Placed): boolean
			local actor = actors[entry]
			if not live or not actor or actor.Out then
				return false
			end
			leaveHome(actor)
			emoteFor(actor, "Happy")
			actor.Joy = 0.45
			return true
		end,
		Count = function(): number
			local count = 0
			for _ in pairs(actors) do
				count += 1
			end
			return count
		end,
	}
	return pets
end

return HousePets
