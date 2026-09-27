--[[
	InfiniteScroll (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > InfiniteScroll

	♾️ Défilement infini (+/s, 10 niveaux, après 8 visites à l'océan) : des
	téléphones translucides sur les côtés dont le fil (publications en
	couleurs, légendes, avatars) défile sans jamais s'arrêter, avec parfois un
	« coup de pouce » qui fait défiler très vite.
	Chaque niveau ajoute quelque chose :
	  1 : 2 téléphones                6 : contour lumineux
	  2 : cœurs qui s'envolent         7 : 4e téléphone
	  3 : pastille de notification     8 : 2e cœur par téléphone
	  4 : 3e téléphone                 9 : contour arc-en-ciel
	  5 : défilement « frénétique »   10 : 5e téléphone
	Le fil est UN seul cadre dont le dégradé dessine les publications
	(motif répété, défilement sans couture) : ~12 instances par téléphone.
	Chaque téléphone est posé par Cosmos/Zones (à gauche / à droite).
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local InfiniteScroll = {}
InfiniteScroll.Slot = "Background"

local ID = "InfiniteScroll"
local MAX_LEVEL = 10
local PHONE_W, PHONE_H = 50, 96
local SCREEN_W, SCREEN_H = 40, 78
local PERIOD = 88 -- hauteur d'un motif du fil (2 publications)

-- Applis (couleurs des publications)
local APPS = {
	{ Color3.fromRGB(255, 120, 180), Color3.fromRGB(170, 110, 255) },
	{ Color3.fromRGB(255, 90, 90), Color3.fromRGB(60, 60, 70) },
	{ Color3.fromRGB(80, 170, 255), Color3.fromRGB(120, 230, 210) },
	{ Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 110, 150) },
	{ Color3.fromRGB(110, 220, 120), Color3.fromRGB(90, 140, 255) },
}

-- Côtés et hauteurs préférés des téléphones (fractions de la toile)
local ANCHORS = {
	Vector2.new(0.2, 0.34),
	Vector2.new(0.8, 0.34),
	Vector2.new(0.2, 0.66),
	Vector2.new(0.8, 0.66),
	Vector2.new(0.2, 0.9),
}

local function phoneCount(level: number): number
	return math.min(5, 2 + math.floor((level - 1) / 3))
end

-- Dégradé du fil : 2 publications (image + légende) par motif, répété 2 fois
local function feedSequence(app: { Color3 }, caption: Color3): ColorSequence
	local points = {}
	local blocks = {
		{ app[1], 0.28 },
		{ caption, 0.22 },
		{ app[2], 0.28 },
		{ caption, 0.22 },
	}
	local t = 0
	for _ = 1, 2 do
		for _, block in ipairs(blocks) do
			local span = block[2] / 2
			table.insert(points, t)
			table.insert(points, block[1])
			t += span
			table.insert(points, math.min(1, t - 0.002))
			table.insert(points, block[1])
		end
	end
	points[#points - 1] = 1
	return Kit.Colors(points)
end

function InfiniteScroll.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local level = math.clamp(ctx.GetLevel(ID), 1, MAX_LEVEL)
	local dark = Kit.IsDark(ctx)

	type Heart = { Frame: Frame, Offset: number }
	type Phone = {
		Piece: any,
		Content: Frame?,
		Feed: Frame?,
		Scroll: number,
		Speed: number,
		Boost: number,
		Hearts: { Heart },
		Stroke: UIStroke?,
		Badge: Frame?,
	}
	local phones: { Phone } = {}

	local function buildPhone(phone: Phone, index: number)
		if phone.Content then
			phone.Content:Destroy()
		end
		table.clear(phone.Hearts)
		phone.Badge = nil
		local root = Kit.Box(phone.Piece.Frame, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		phone.Content = root
		local app = APPS[(index - 1) % #APPS + 1]

		-- Coque translucide
		local body = Kit.Box(root, {
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(PHONE_W / 2, PHONE_H / 2),
			Size = UDim2.fromOffset(PHONE_W - 4, PHONE_H - 4),
			Color = if dark then Kit.Rgb(24, 22, 40) else Kit.Rgb(60, 56, 80),
			Alpha = if dark then 0.35 else 0.55,
			ZIndex = 1,
		})
		Kit.Corner(body, 10)
		local strokeColor = if level >= 6 then app[1] elseif dark then Kit.Rgb(220, 210, 255) else Kit.Rgb(80, 70, 120)
		phone.Stroke = Kit.Stroke(body, strokeColor, if level >= 6 then 2 else 1.5, if dark then 0.35 else 0.25)
		-- Écran (découpe le fil)
		local screen = Kit.Box(root, {
			Name = "Screen",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(PHONE_W / 2, PHONE_H / 2 + 1),
			Size = UDim2.fromOffset(SCREEN_W, SCREEN_H),
			Color = if dark then Kit.Rgb(30, 28, 52) else Color3.new(1, 1, 1),
			Alpha = if dark then 0.4 else 0.35,
			ClipsDescendants = true,
			ZIndex = 2,
		})
		local caption = if dark then Kit.Rgb(70, 66, 100) else Kit.Rgb(245, 244, 250)
		local feed = Kit.Box(screen, {
			Name = "Feed",
			Position = UDim2.fromOffset(3, 0),
			Size = UDim2.fromOffset(SCREEN_W - 6, PERIOD * 2),
			Color = Color3.new(1, 1, 1),
			Alpha = if dark then 0.15 else 0.1,
			ZIndex = 3,
		})
		Kit.Gradient(feed, feedSequence(app, caption), nil, 90)
		phone.Feed = feed
		-- Cœurs (niveau 2+ ; 2 au niveau 8+)
		if level >= 2 then
			for heartIndex = 1, if level >= 8 then 2 else 1 do
				local heart = Kit.Text(root, "♥", PHONE_W - 8, PHONE_H - 22, 12, Kit.Rgb(255, 80, 130), 6)
				heart.TextTransparency = 1
				table.insert(phone.Hearts, { Frame = heart :: any, Offset = (heartIndex - 1) * 0.5 + random:NextNumber(0, 0.2) })
			end
		end
		-- Pastille de notification (niveau 3+)
		if level >= 3 then
			local badge = Kit.Diamond(root, PHONE_W - 5, 5, 8, Kit.Rgb(255, 60, 70), 0, 6)
			badge.Name = "Badge"
			phone.Badge = badge
		end
	end

	local function sync()
		local wanted = phoneCount(level)
		-- Ajoute les téléphones manquants (jamais recréés : le fil continue)
		for index = #phones + 1, wanted do
			local piece = Kit.Piece(ctx.Container, "Phone" .. index, PHONE_W, PHONE_H)
			phones[index] = { Piece = piece, Content = nil, Feed = nil, Scroll = random:NextNumber(0, PERIOD), Speed = random:NextNumber(14, 22), Boost = 0, Hearts = {}, Stroke = nil, Badge = nil }
		end
		for index, phone in ipairs(phones) do
			buildPhone(phone, index)
		end
		local items = {}
		for index = 1, #phones do
			table.insert(items, { W = PHONE_W, H = PHONE_H, Anchor = ANCHORS[index], MinScale = 0.5, MaxScale = 1.1, Gap = 4 })
		end
		Zones.Request(ID, items, function(placements)
			for index, phone in ipairs(phones) do
				Kit.Place(phone.Piece, placements[index])
			end
		end)
	end

	sync()
	Kit.WatchLevel(ctx, ID, function(newLevel)
		level = math.clamp(newLevel, 1, MAX_LEVEL)
		sync()
		for _, phone in ipairs(phones) do
			Kit.Bump(phone.Piece)
		end
	end)
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		for index, phone in ipairs(phones) do
			buildPhone(phone, index)
		end
	end)

	Kit.Loop(ctx, 20, function(dt, t)
		for index, phone in ipairs(phones) do
			if phone.Piece.Placed then
				-- Défilement (avec parfois un coup de pouce très rapide)
				if phone.Boost > 0 then
					phone.Boost = math.max(0, phone.Boost - dt)
				elseif effects and random:NextNumber() < dt * (if level >= 5 then 0.35 else 0.12) then
					phone.Boost = 0.6
				end
				local speed = phone.Speed * (if level >= 5 then 1.5 else 1) + (if phone.Boost > 0 then 220 * phone.Boost else 0)
				phone.Scroll = (phone.Scroll + speed * dt) % PERIOD
				local feed = phone.Feed
				if feed then
					feed.Position = UDim2.fromOffset(3, -phone.Scroll)
				end
				-- Cœurs qui s'envolent
				for _, heart in ipairs(phone.Hearts) do
					local p = (t / 2.4 + heart.Offset + index * 0.17) % 1
					local label = heart.Frame :: any
					label.Position = UDim2.fromOffset(PHONE_W - 10 + math.sin(p * 8) * 3, PHONE_H - 20 - p * 40)
					label.TextTransparency = if p < 0.15 then 1 - p / 0.15 elseif p > 0.6 then (p - 0.6) / 0.4 else 0
				end
				local badge = phone.Badge
				if badge then
					local pulse = 9 + math.max(0, math.sin(t * 3 + index)) * 3
					badge.Size = UDim2.fromOffset(pulse, pulse)
				end
				if level >= 9 then
					local stroke = phone.Stroke
					if stroke then
						stroke.Color = Color3.fromHSV((t * 0.15 + index * 0.2) % 1, 0.6, 1)
					end
				end
			end
		end
	end)
end

function InfiniteScroll.Stop(_ctx)
	Zones.Release(ID)
end

return InfiniteScroll
