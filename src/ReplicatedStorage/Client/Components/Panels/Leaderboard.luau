--[[
	Leaderboard (ModuleScript) — classement complet (disponible dès le début)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Leaderboard

	Deux classements (onglets du haut) :
	  - "💧 Dopamine"     : serveur = Dopamine actuelle ; monde = Dopamine
	    gagnée depuis toujours ;
	  - "♻️ Renaissances" : nombre de renaissances (visites à l'océan).
	Et pour chacun, deux portées (petit sélecteur à droite) :
	  - "🏠 Serveur" : les joueurs de ce serveur EN DIRECT (mis à jour toutes
	    les 2 s par le serveur), triés par Dopamine OU par renaissances
	    selon l'onglet du haut ;
	  - "🌍 Monde"   : le top de tous les serveurs (mis à jour chaque minute).
	Chaque joueur affiche son avatar, son nom, sa Dopamine ET ses
	renaissances (quand le serveur les connaît pour le top mondial).
	Podium illustré pour les 3 premiers (rayons, couronne, socles), liste
	pour la suite, et en bas "Ta place" (+ ce qu'il manque pour dépasser le
	joueur juste devant) avec tes propres compteurs. Toi : surligné.

	Données : ClientState.ServerLeaderboard / ClientState.Leaderboard /
	ClientState.RebirthLeaderboard (format { Global, GlobalRebirths, Server },
	anciens formats acceptés, voir ClientState).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Leaderboard = {
	Title = "🥇 Classement",
	Subtitle = "Qui a le plus gros cerveau ? Et qui est allé le plus loin ?",
	Color = Theme.Colors.Blue,
	Size = Vector2.new(700, 600),
}

-- Entrée normalisée d'un classement
type Entry = {
	UserId: number,
	Name: string,
	Primary: number, -- valeur classée (Dopamine ou renaissances)
	Dopamine: number?, -- Dopamine actuelle (serveur) ou gagnée depuis toujours (monde)
	Rebirths: number?, -- renaissances (nil = inconnues)
	Lifetime: number?, -- Dopamine gagnée depuis toujours (serveur)
	Rank: number?, -- rang envoyé par le serveur (monde)
}

type Avatar = { Frame: Frame, Image: ImageLabel, Initial: TextLabel }

type Row = {
	Holder: Frame,
	Card: Frame,
	Stroke: UIStroke,
	RankBubble: Frame,
	Rank: TextLabel,
	Avatar: Avatar,
	Name: TextLabel,
	Detail: TextLabel,
	Value: TextLabel,
	IsMe: boolean,
	Hovered: boolean,
}

type Podium = {
	Holder: Frame,
	Avatar: Avatar,
	Ring: UIStroke,
	Name: TextLabel,
	Value: TextLabel,
	Secondary: TextLabel,
	Me: Frame,
}

-- Couleurs d'un classement
type Palette = { Accent: Color3, Soft: Color3, Deep: Color3 }

local MEDALS = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = {
	Color3.fromRGB(255, 196, 40),
	Color3.fromRGB(176, 186, 204),
	Color3.fromRGB(214, 140, 84),
}
local REBIRTH_COLOR = Theme.Colors.Robux or Color3.fromRGB(0, 168, 107)
local PALETTES: { [string]: Palette } = {
	Dopamine = {
		Accent = Theme.Colors.Blue,
		Soft = Color3.fromRGB(230, 242, 255),
		Deep = Theme.Colors.Blue:Lerp(Color3.new(0, 0, 0), 0.3),
	},
	Rebirths = {
		Accent = REBIRTH_COLOR,
		Soft = Color3.fromRGB(224, 248, 237),
		Deep = REBIRTH_COLOR:Lerp(Color3.new(0, 0, 0), 0.3),
	},
}
local WHITE = Color3.new(1, 1, 1)

-- Mise en page (contenu d'environ 660 x 512)
local TOP_HEIGHT = 38
local INFO_Y = 46
local PODIUM_Y = 70
local PODIUM_HEIGHT = 172
local PODIUM_PADDING_TOP = 22 -- place pour la couronne du 1er
local LIST_Y = PODIUM_Y + PODIUM_HEIGHT + 8
local FOOTER_HEIGHT = 56
local ROW_HEIGHT = 50

local player = Players.LocalPlayer
local board = "Dopamine" -- "Dopamine" | "Rebirths"
local scope = "Server" -- "Server" | "World"
local visible = false
local dirty = true

local boardTabs: UIUtil.Tabs
local scopeTabs: UIUtil.Tabs
local liveDot: Frame
local infoLabel: TextLabel
local podiumCard: Frame
local podiumGradient: UIGradient
local podiumStroke: UIStroke
local rays: Frame
local raysConnection: RBXScriptConnection? = nil
local podiums: { Podium } = {}
local list: ScrollingFrame
local rows: { Row } = {}
local hintLabel: TextLabel
local emptyFrame: Frame
local emptyIcon: TextLabel
local emptyTitle: TextLabel
local emptyBody: TextLabel
local footer: Frame
local footerGradient: UIGradient
local footerStroke: UIStroke
local footerRing: UIStroke
local footerLabel: TextLabel
local footerDetail: TextLabel
local footerAvatar: Avatar
local myDopamineChip: Frame
local myRebirthChip: Frame

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

-- Nombre fiable (NaN / infini / texte -> `default`)
local function num(value: any, default: number?): number?
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return default
	end
	return number
end

local function formatValue(value: number): string
	if value < 1e6 then
		return NumberFormatter.WithSpaces(value)
	end
	return NumberFormatter.Format(value)
end

local function rebirthWord(count: number): string
	return count >= 2 and "renaissances" or "renaissance"
end

-- "1er", "2e", "3e"...
local function ordinal(rank: number): string
	return rank == 1 and "1er" or (tostring(rank) .. "e")
end

local function palette(): Palette
	return PALETTES[board] or PALETTES.Dopamine
end

-- Valeur principale mise en forme ("1.2M 💧" / "3 ♻️")
local function primaryText(value: number): string
	if board == "Rebirths" then
		return formatValue(math.floor(value)) .. " ♻️"
	end
	return formatValue(value) .. " 💧"
end

local function setChipText(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- Avatar rond (photo du joueur, ou initiale si indisponible)
local function buildAvatar(parent: Instance, size: number, zIndex: number): Avatar
	local frame = UIUtil.Create("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = zIndex,
		Parent = parent,
	})
	UIUtil.Corner(frame, UDim.new(1, 0))
	local initial = UIUtil.Label({
		Name = "Initial",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromScale(0.7, 0.7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = math.floor(size * 0.5),
		ZIndex = zIndex + 1,
		Parent = frame,
	})
	local image = UIUtil.Create("ImageLabel", {
		Name = "Image",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ZIndex = zIndex + 2,
		Parent = frame,
	})
	UIUtil.Corner(image, UDim.new(1, 0))
	return { Frame = frame, Image = image, Initial = initial }
end

local function setAvatar(avatar: Avatar, userId: number, name: string, background: Color3?)
	-- (les joueurs de test de Studio ont un UserId négatif : pas de photo)
	local url = userId > 0 and UIUtil.HeadshotUrl(userId, 48) or ""
	if avatar.Image.Image ~= url then
		avatar.Image.Image = url
	end
	avatar.Initial.Text = string.upper(string.sub(name, 1, 1))
	if background then
		avatar.Frame.BackgroundColor3 = background
	end
end

-- Petite étiquette "TOI"
local function meChip(parent: Instance, zIndex: number): Frame
	return UIUtil.Chip({
		Name = "Me",
		Text = "TOI",
		Color = Theme.Colors.Blue,
		TextColor3 = Theme.Colors.TextLight,
		Height = 18,
		TextSize = 11,
		ZIndex = zIndex,
		Visible = false,
		Parent = parent,
	})
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

-- Mes compteurs actuels (Dopamine, gagnée depuis toujours, renaissances)
local function myStats(): (number, number, number)
	local data = ClientState.Data
	if type(data) ~= "table" then
		return 0, 0, 0
	end
	local stats = type(data.Stats) == "table" and data.Stats or {}
	local dopamine = num(data.Dopamine, 0) :: number
	return dopamine, num(stats.LifetimeDopamine, 0) :: number, math.floor(num(data.Rebirths, 0) :: number)
end

local function sortEntries(result: { Entry })
	table.sort(result, function(a: Entry, b: Entry)
		if a.Rank and b.Rank and a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		if a.Primary ~= b.Primary then
			return a.Primary > b.Primary
		end
		-- Égalité : la Dopamine gagnée départage (utile pour les renaissances)
		local lifetimeA = a.Lifetime or a.Dopamine or 0
		local lifetimeB = b.Lifetime or b.Dopamine or 0
		if lifetimeA ~= lifetimeB then
			return lifetimeA > lifetimeB
		end
		return a.UserId < b.UserId
	end)
end

-- Classement du serveur (en direct), trié selon l'onglet du haut
local function getServerEntries(): { Entry }
	local result: { Entry } = {}
	local myDopamine, myLifetime, myRebirths = myStats()
	local source = ClientState.ServerLeaderboard
	local foundMe = false
	if type(source) == "table" then
		for _, raw in ipairs(source) do
			if type(raw) == "table" then
				local userId = num(raw.UserId, 0) :: number
				local dopamine = num(raw.Dopamine, nil) or num(raw.Value, 0) :: number
				local rebirths = math.floor(num(raw.Rebirths, 0) :: number)
				local lifetime = num(raw.Lifetime, nil)
				if userId == player.UserId and ClientState.Data then
					-- Ta ligne suit tes compteurs en direct (entre deux envois du serveur)
					foundMe = true
					dopamine = myDopamine
					rebirths = myRebirths
					lifetime = math.max(lifetime or 0, myLifetime)
				end
				table.insert(result, {
					UserId = userId,
					Name = tostring(raw.Name or "?"),
					Primary = board == "Rebirths" and rebirths or dopamine,
					Dopamine = dopamine,
					Rebirths = rebirths,
					Lifetime = lifetime,
				})
			end
		end
	end
	-- Classement du serveur pas encore reçu : au moins toi
	if not foundMe and #result == 0 and ClientState.Data then
		table.insert(result, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Primary = board == "Rebirths" and myRebirths or myDopamine,
			Dopamine = myDopamine,
			Rebirths = myRebirths,
			Lifetime = myLifetime,
		})
	end
	sortEntries(result)
	return result
end

-- Top mondial (Dopamine gagnée ou renaissances), dans l'ordre du serveur
local function getWorldEntries(): { Entry }
	local result: { Entry } = {}
	local _, myLifetime, myRebirths = myStats()
	local source = board == "Rebirths" and ClientState.RebirthLeaderboard or ClientState.Leaderboard
	if type(source) ~= "table" then
		return result
	end
	for _, raw in ipairs(source) do
		if type(raw) == "table" then
			local userId = num(raw.UserId, 0) :: number
			local isMe = userId == player.UserId and ClientState.Data ~= nil
			local entry: Entry
			if board == "Rebirths" then
				local value = math.floor(num(raw.Value, nil) or num(raw.Rebirths, 0) :: number)
				entry = {
					UserId = userId,
					Name = tostring(raw.Name or "?"),
					Primary = value,
					Rebirths = value,
					Dopamine = isMe and myLifetime or num(raw.Dopamine, nil),
					Rank = num(raw.Rank, nil),
				}
			else
				local value = num(raw.Value, nil) or num(raw.Lifetime, 0) :: number
				local rebirths = num(raw.Rebirths, nil)
				entry = {
					UserId = userId,
					Name = tostring(raw.Name or "?"),
					Primary = value,
					Dopamine = value,
					Rebirths = isMe and myRebirths or (rebirths and math.floor(rebirths) or nil),
					Rank = num(raw.Rank, nil),
				}
			end
			table.insert(result, entry)
		end
	end
	sortEntries(result)
	return result
end

local function getEntries(): { Entry }
	if scope == "Server" then
		return getServerEntries()
	end
	return getWorldEntries()
end

----------------------------------------------------------------------
-- Affichage
----------------------------------------------------------------------

-- Ligne secondaire d'un joueur (l'AUTRE compteur + le total)
local function detailText(entry: Entry): string
	local parts = {}
	if board == "Dopamine" then
		if entry.Rebirths then
			table.insert(parts, "♻️ " .. formatValue(entry.Rebirths) .. " " .. rebirthWord(entry.Rebirths))
		end
		if scope == "Server" and entry.Lifetime then
			table.insert(parts, "Total " .. NumberFormatter.Format(entry.Lifetime))
		end
		if #parts == 0 then
			return "Dopamine gagnée au total"
		end
	else
		if entry.Dopamine then
			local suffix = scope == "Server" and "" or " gagnés"
			table.insert(parts, "💧 " .. NumberFormatter.Format(entry.Dopamine) .. suffix)
		end
		if scope == "Server" and entry.Lifetime then
			table.insert(parts, "Total " .. NumberFormatter.Format(entry.Lifetime))
		end
		if #parts == 0 then
			return "Visites à l'océan"
		end
	end
	return table.concat(parts, "  •  ")
end

-- Petit texte sous la valeur du podium (l'autre compteur)
local function podiumSecondary(entry: Entry): string
	if board == "Dopamine" then
		return entry.Rebirths and ("♻️ " .. formatValue(entry.Rebirths)) or ""
	end
	return entry.Dopamine and ("💧 " .. NumberFormatter.Format(entry.Dopamine)) or ""
end

local function refreshPodium(entries: { Entry })
	local colors = palette()
	for rank, podium in ipairs(podiums) do
		local entry = entries[rank]
		podium.Holder.Visible = entry ~= nil
		if entry then
			local isMe = entry.UserId == player.UserId
			setAvatar(podium.Avatar, entry.UserId, entry.Name, MEDAL_COLORS[rank]:Lerp(WHITE, 0.7))
			podium.Name.Text = entry.Name
			podium.Name.TextColor3 = isMe and colors.Deep or Theme.Colors.Text
			podium.Value.Text = primaryText(entry.Primary)
			podium.Secondary.Text = podiumSecondary(entry)
			podium.Me.Visible = isMe
			podium.Me.BackgroundColor3 = colors.Accent
			podium.Ring.Thickness = isMe and 4 or 3
		end
	end
	rays.Visible = entries[1] ~= nil
end

-- Contour d'une ligne (toi / survol / normal)
local function paintRowStroke(row: Row)
	local colors = palette()
	if row.IsMe then
		row.Stroke.Color = colors.Accent
		row.Stroke.Transparency = 0
	elseif row.Hovered then
		row.Stroke.Color = colors.Accent
		row.Stroke.Transparency = 0.45
	else
		row.Stroke.Color = Theme.Colors.Divider
		row.Stroke.Transparency = 0
	end
end

local function ensureRow(index: number): Row
	local existing = rows[index]
	if existing then
		return existing
	end
	-- Support transparent (dans la liste) + carte (animée à l'intérieur)
	local holder = UIUtil.Create("Frame", {
		Name = "Row" .. index,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = list,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Card,
		Parent = holder,
	})
	UIUtil.Corner(card, Theme.Radius.M)
	local stroke = UIUtil.Stroke(card, Theme.Colors.Divider, 1.5)

	local bubble = UIUtil.Create("Frame", {
		Name = "RankBubble",
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = card,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, Theme.Colors.Divider, 1)
	local rank = UIUtil.Label({
		Name = "Rank",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -6, 1, -8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 15,
		Parent = bubble,
	})

	local avatar = buildAvatar(card, 36, 2)
	avatar.Frame.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Frame.Position = UDim2.new(0, 52, 0.5, 0)
	local name = UIUtil.Label({
		Name = "PlayerName",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, -98, 0, 20),
		Position = UDim2.fromOffset(98, 6),
		MaxTextSize = 17,
		Parent = card,
	})
	local detail = UIUtil.Label({
		Name = "Detail",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.66, -98, 0, 15),
		Position = UDim2.fromOffset(98, 28),
		MaxTextSize = 13,
		Parent = card,
	})
	local value = UIUtil.Label({
		Name = "Value",
		Font = Theme.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.34, -20, 0, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		MaxTextSize = 18,
		Parent = card,
	})

	local row: Row = {
		Holder = holder,
		Card = card,
		Stroke = stroke,
		RankBubble = bubble,
		Rank = rank,
		Avatar = avatar,
		Name = name,
		Detail = detail,
		Value = value,
		IsMe = false,
		Hovered = false,
	}
	-- Survol : contour de la couleur du classement
	card.MouseEnter:Connect(function()
		row.Hovered = true
		paintRowStroke(row)
	end)
	card.MouseLeave:Connect(function()
		row.Hovered = false
		paintRowStroke(row)
	end)
	rows[index] = row
	return row
end

local function refreshFooter(entries: { Entry })
	local colors = palette()
	local myDopamine, myLifetime, myRebirths = myStats()
	setAvatar(footerAvatar, player.UserId, player.DisplayName, colors.Soft)
	footerRing.Color = colors.Accent
	footerStroke.Color = colors.Accent
	footerGradient.Color = ColorSequence.new(colors.Soft, WHITE)
	footerLabel.TextColor3 = colors.Deep
	setChipText(myDopamineChip, "💧 " .. NumberFormatter.Format(scope == "World" and myLifetime or myDopamine))
	setChipText(myRebirthChip, "♻️ " .. formatValue(myRebirths))

	local myIndex: number? = nil
	for index, entry in ipairs(entries) do
		if entry.UserId == player.UserId then
			myIndex = index
			break
		end
	end

	if scope == "Server" then
		if myIndex then
			local me = entries[myIndex]
			footerLabel.Text = string.format("Ta place : %s sur %d", ordinal(myIndex), #entries)
			if myIndex == 1 then
				if #entries <= 1 then
					footerDetail.Text = "Seul(e) sur le serveur : invite tes amis !"
				elseif board == "Rebirths" then
					footerDetail.Text = "♻️ Tu es le plus grand voyageur du serveur !"
				else
					footerDetail.Text = "👑 Tu es le plus gros cerveau du serveur !"
				end
			else
				local ahead = entries[myIndex - 1]
				local gap = math.max(0, ahead.Primary - me.Primary)
				if board == "Rebirths" then
					local needed = math.floor(gap) + 1
					footerDetail.Text = string.format("Encore %d %s pour dépasser %s", needed, rebirthWord(needed), ahead.Name)
				else
					footerDetail.Text = string.format("Encore %s 💧 pour dépasser %s", formatValue(gap + 1), ahead.Name)
				end
			end
		else
			footerLabel.Text = "Ta place : ..."
			footerDetail.Text = "Chargement du classement du serveur"
		end
		return
	end

	-- Monde
	if myIndex then
		footerLabel.Text = string.format("Ta place : %s du monde !", ordinal(myIndex))
		footerDetail.Text = myIndex == 1 and "👑 Personne n'a fait mieux, nulle part." or "Tu fais partie des légendes 🌍"
		return
	end
	local size = math.max(#entries, 10)
	footerLabel.Text = "Pas encore dans le top " .. tostring(size)
	local last = entries[#entries]
	if board == "Rebirths" then
		if last and #entries >= size then
			local needed = math.max(0, math.floor(last.Primary) - myRebirths) + 1
			footerDetail.Text = string.format("Encore %d %s pour y entrer", needed, rebirthWord(needed))
		elseif myRebirths <= 0 then
			footerDetail.Text = "Va à l'océan 🌊 pour ta première renaissance !"
		else
			footerDetail.Text = "Ta place arrive à la prochaine mise à jour"
		end
	else
		if last then
			footerDetail.Text = string.format("Encore %s 💧 gagnés pour y entrer", formatValue(math.max(0, last.Primary - myLifetime) + 1))
		else
			footerDetail.Text = "Continue de cliquer !"
		end
	end
end

-- Couleurs qui dépendent du classement choisi
local function applyPalette()
	local colors = palette()
	podiumGradient.Color = ColorSequence.new(colors.Soft, WHITE)
	podiumStroke.Color = colors.Accent
	list.ScrollBarImageColor3 = colors.Accent
end

local function refreshInfo()
	local live = scope == "Server"
	liveDot.Visible = live
	infoLabel.Position = UDim2.fromOffset(live and 16 or 0, INFO_Y)
	infoLabel.Size = UDim2.new(1, live and -16 or 0, 0, 18)
	if live then
		infoLabel.Text = board == "Rebirths" and "En direct  •  classé par renaissances (visites à l'océan)"
			or "En direct  •  classé par Dopamine actuelle"
	else
		infoLabel.Text = board == "Rebirths" and "🌍 Renaissances de tous les serveurs  •  mis à jour chaque minute"
			or "🌍 Dopamine gagnée depuis toujours  •  mis à jour chaque minute"
	end
end

local function refresh()
	if not list then
		return
	end
	dirty = false
	local colors = palette()
	local entries = getEntries()

	refreshInfo()
	applyPalette()

	local isEmpty = #entries == 0
	emptyFrame.Visible = isEmpty
	podiumCard.Visible = not isEmpty
	list.Visible = not isEmpty
	if isEmpty then
		if scope == "Server" then
			emptyIcon.Text = "⏳"
			emptyTitle.Text = "Chargement..."
			emptyBody.Text = "Le classement du serveur arrive dans un instant."
		elseif board == "Rebirths" then
			emptyIcon.Text = "🌊"
			emptyTitle.Text = "Aucune renaissance pour l'instant"
			emptyBody.Text = RunService:IsStudio()
					and "Dans Studio, le classement mondial ne fonctionne que si l'accès aux API (DataStore) est activé dans les paramètres du jeu."
				or "Va à l'océan pour être le premier du monde ! (mise à jour chaque minute)"
		else
			emptyIcon.Text = "🌍"
			emptyTitle.Text = "Classement mondial en chargement..."
			emptyBody.Text = RunService:IsStudio()
					and "Dans Studio, le classement mondial ne fonctionne que si l'accès aux API (DataStore) est activé dans les paramètres du jeu."
				or "Reviens dans une minute : le top du monde arrive !"
		end
	end

	refreshPodium(entries)

	-- Liste à partir de la 4e place
	local shown = 0
	for index = 4, #entries do
		local entry = entries[index]
		shown += 1
		local row = ensureRow(shown)
		local isMe = entry.UserId == player.UserId
		row.IsMe = isMe
		row.Holder.Visible = true
		row.Card.BackgroundColor3 = isMe and colors.Soft or Theme.Colors.Card
		paintRowStroke(row)
		row.Rank.Text = tostring(index)
		row.RankBubble.BackgroundColor3 = isMe and colors.Accent or Theme.Colors.Surface
		row.Rank.TextColor3 = isMe and Theme.Colors.TextLight or Theme.Colors.TextDim
		setAvatar(row.Avatar, entry.UserId, entry.Name)
		row.Name.Text = isMe and (entry.Name .. "  (toi)") or entry.Name
		row.Name.TextColor3 = isMe and colors.Deep or Theme.Colors.Text
		row.Detail.Text = detailText(entry)
		row.Value.Text = primaryText(entry.Primary)
		row.Value.TextColor3 = isMe and colors.Deep or Theme.Colors.Text
	end
	for index = shown + 1, #rows do
		rows[index].Holder.Visible = false
	end
	-- Pas de 4e place : petit message à la place de la liste
	hintLabel.Visible = shown == 0
	hintLabel.Text = scope == "Server" and "Plus il y a de joueurs, plus c'est drôle 👀" or "Le reste du top arrive avec de nouveaux joueurs 🌍"

	refreshFooter(entries)
end

-- Petite entrée animée (changement d'onglet / ouverture)
local function animateIn()
	for rank, podium in ipairs(podiums) do
		if podium.Holder.Visible then
			UIUtil.Pop(podium.Avatar.Frame, 0.6, 0.35 + rank * 0.05)
		end
	end
	for index, row in ipairs(rows) do
		local card = row.Card
		if row.Holder.Visible and index <= 8 then
			card.Position = UDim2.fromOffset(18, 0)
			card.BackgroundTransparency = 0.4
			task.delay(index * 0.03, function()
				UIUtil.Tween(card, 0.28, { Position = UDim2.new(), BackgroundTransparency = 0 }, Enum.EasingStyle.Quint)
			end)
		end
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildPodium(parent: Frame, rank: number, x: number, blockHeight: number)
	local color = MEDAL_COLORS[rank]
	local holder = UIUtil.Create("Frame", {
		Name = "Podium" .. rank,
		Size = UDim2.new(1 / 3, -10, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(x, 0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})

	-- Socle (bloc au dégradé de la médaille)
	local block = UIUtil.Create("Frame", {
		Name = "Block",
		Size = UDim2.new(1, -30, 0, blockHeight),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = holder,
	})
	UIUtil.Corner(block, Theme.Radius.M)
	UIUtil.Stroke(block, color:Lerp(Color3.new(0, 0, 0), 0.3), 1.5, 0.3)
	UIUtil.SoftGradient(block, color, 90)
	UIUtil.Label({
		Name = "Medal",
		Text = MEDALS[rank],
		Size = UDim2.new(1, 0, 0, math.min(28, blockHeight - 6)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 26,
		ZIndex = 4,
		Parent = block,
	})

	-- Au-dessus du socle : l'autre compteur, la valeur, le nom, puis l'avatar
	local secondary = UIUtil.Label({
		Name = "Secondary",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -8, 0, 14),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(blockHeight + 3)),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = holder,
	})
	local value = UIUtil.Label({
		Name = "Value",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, -8, 0, 18),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(blockHeight + 17)),
		MaxTextSize = 17,
		ZIndex = 3,
		Parent = holder,
	})
	local name = UIUtil.Label({
		Name = "PlayerName",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -8, 0, 17),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(blockHeight + 35)),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = holder,
	})
	local avatarSize = rank == 1 and 52 or 44
	local avatarBottom = blockHeight + 54
	local avatar = buildAvatar(holder, avatarSize, 4)
	avatar.Frame.AnchorPoint = Vector2.new(0.5, 1)
	avatar.Frame.Position = UDim2.new(0.5, 0, 1, -avatarBottom)
	local ring = UIUtil.Stroke(avatar.Frame, color, 3, 0)
	if rank == 1 then
		-- Rayons dorés qui tournent derrière le 1er
		rays = UIUtil.Rays(holder, color, 8, 150, UDim2.new(0.5, 0, 1, -(avatarBottom + avatarSize / 2)), 2)
		UIUtil.Label({
			Name = "Crown",
			Text = "👑",
			Size = UDim2.fromOffset(28, 28),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 8),
			Rotation = -12,
			MaxTextSize = 24,
			ZIndex = 8,
			Parent = avatar.Frame,
		})
	end
	local me = meChip(avatar.Frame, 9)
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.new(0.5, 0, 1, 0)

	podiums[rank] = {
		Holder = holder,
		Avatar = avatar,
		Ring = ring,
		Name = name,
		Value = value,
		Secondary = secondary,
		Me = me,
	}
end

local function buildFooter(content: Frame)
	footer = UIUtil.Create("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Parent = content,
	})
	UIUtil.Corner(footer, Theme.Radius.L)
	footerStroke = UIUtil.Stroke(footer, Theme.Colors.Blue, 1.5, 0.35)
	footerGradient = UIUtil.Gradient(footer, ColorSequence.new(PALETTES.Dopamine.Soft, WHITE), 0)
	footerAvatar = buildAvatar(footer, 40, 2)
	footerAvatar.Frame.AnchorPoint = Vector2.new(0, 0.5)
	footerAvatar.Frame.Position = UDim2.new(0, 10, 0.5, 0)
	footerRing = UIUtil.Stroke(footerAvatar.Frame, Theme.Colors.Blue, 2, 0)
	footerLabel = UIUtil.Label({
		Name = "Place",
		Font = Theme.Fonts.Title,
		TextColor3 = PALETTES.Dopamine.Deep,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 20),
		Position = UDim2.fromOffset(62, 8),
		MaxTextSize = 17,
		Parent = footer,
	})
	footerDetail = UIUtil.Label({
		Name = "Detail",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 16),
		Position = UDim2.fromOffset(62, 30),
		MaxTextSize = 14,
		Parent = footer,
	})

	-- Tes compteurs (Dopamine et renaissances), à droite
	local chips = UIUtil.Create("Frame", {
		Name = "MyStats",
		Size = UDim2.new(0, 176, 0, 28),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = footer,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	myDopamineChip = UIUtil.Chip({
		Name = "Dopamine",
		Text = "💧 0",
		Color = Theme.Colors.Blue,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 1,
		Parent = chips,
	})
	myRebirthChip = UIUtil.Chip({
		Name = "Rebirths",
		Text = "♻️ 0",
		Color = REBIRTH_COLOR,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 2,
		Parent = chips,
	})
end

local function buildEmpty(content: Frame)
	emptyFrame = UIUtil.Create("Frame", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 1, -(PODIUM_Y + FOOTER_HEIGHT + 8)),
		Position = UDim2.fromOffset(0, PODIUM_Y),
		BackgroundColor3 = Theme.Colors.Surface,
		Visible = false,
		Parent = content,
	})
	UIUtil.Corner(emptyFrame, Theme.Radius.L)
	UIUtil.Stroke(emptyFrame, Theme.Colors.Divider, 1.5)
	local bubble = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(92, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		BackgroundColor3 = WHITE,
		Parent = emptyFrame,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, Theme.Colors.Divider, 2)
	emptyIcon = UIUtil.Label({
		Text = "🌍",
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 12),
		MaxTextSize = 50,
		Parent = bubble,
	})
	emptyTitle = UIUtil.Label({
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, 148),
		MaxTextSize = 22,
		Parent = emptyFrame,
	})
	emptyBody = UIUtil.Create("TextLabel", {
		Font = Theme.Fonts.Body,
		TextSize = 15,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -100, 0, 60),
		Position = UDim2.fromOffset(50, 184),
		Parent = emptyFrame,
	})
end

function Leaderboard.Build(content: Frame)
	-- Onglets du haut : le classement (Dopamine / renaissances)
	boardTabs = UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "Dopamine", Text = "💧 Dopamine" },
			{ Id = "Rebirths", Text = "♻️ Renaissances" },
		},
		Color = Theme.Colors.Blue,
		Size = UDim2.new(1, -236, 0, TOP_HEIGHT),
		Selected = board,
		OnSelect = function(id: string)
			board = id
			refresh()
			animateIn()
		end,
	})
	-- Sélecteur de portée (serveur / monde)
	scopeTabs = UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "Server", Text = "🏠 Serveur" },
			{ Id = "World", Text = "🌍 Monde" },
		},
		Color = Theme.Colors.Dark,
		Size = UDim2.new(0, 224, 0, TOP_HEIGHT),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		TextSize = 15,
		Selected = scope,
		OnSelect = function(id: string)
			scope = id
			refresh()
			animateIn()
		end,
	})

	-- Ligne d'info (point rouge qui pulse quand c'est en direct)
	liveDot = UIUtil.Create("Frame", {
		Name = "LiveDot",
		Size = UDim2.fromOffset(9, 9),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(2, INFO_Y + 9),
		BackgroundColor3 = Theme.Colors.Red,
		Parent = content,
	})
	UIUtil.Corner(liveDot, UDim.new(1, 0))
	TweenService:Create(
		liveDot,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.75 }
	):Play()
	infoLabel = UIUtil.Label({
		Name = "Info",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(16, INFO_Y),
		MaxTextSize = 14,
		Parent = content,
	})

	-- Carte du podium : 2e à gauche, 1er au centre (plus haut), 3e à droite
	podiumCard = UIUtil.Create("Frame", {
		Name = "PodiumCard",
		Size = UDim2.new(1, 0, 0, PODIUM_HEIGHT),
		Position = UDim2.fromOffset(0, PODIUM_Y),
		BackgroundColor3 = WHITE,
		ClipsDescendants = false,
		Parent = content,
	})
	UIUtil.Corner(podiumCard, Theme.Radius.L)
	podiumStroke = UIUtil.Stroke(podiumCard, Theme.Colors.Blue, 1.5, 0.6)
	podiumGradient = UIUtil.Gradient(podiumCard, ColorSequence.new(PALETTES.Dopamine.Soft, WHITE), 90)
	local podiumArea = UIUtil.Create("Frame", {
		Name = "Podium",
		Size = UDim2.new(1, -40, 1, -PODIUM_PADDING_TOP),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		Parent = podiumCard,
	})
	buildPodium(podiumArea, 2, 1 / 6, 32)
	buildPodium(podiumArea, 1, 0.5, 42)
	buildPodium(podiumArea, 3, 5 / 6, 22)
	-- Les rayons restent dans la carte (sinon ils débordent sur les onglets)
	podiumCard.ClipsDescendants = true

	list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -(LIST_Y + FOOTER_HEIGHT + 8)),
		Position = UDim2.fromOffset(0, LIST_Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Blue,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 4),
		Parent = list,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	hintLabel = UIUtil.Label({
		Name = "Hint",
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = 10000,
		MaxTextSize = 14,
		Visible = false,
		Parent = list,
	})

	buildEmpty(content)
	buildFooter(content)

	ClientState.LeaderboardChanged:Connect(function()
		dirty = true
		if visible then
			refresh()
		end
	end)
	refresh()
end

function Leaderboard.OnOpen()
	visible = true
	boardTabs.Select(board, true)
	scopeTabs.Select(scope, true)
	refresh()
	animateIn()
	-- Rayons du 1er : rotation lente, seulement quand la fenêtre est ouverte
	if not raysConnection then
		raysConnection = RunService.Heartbeat:Connect(function(dt: number)
			if rays and rays.Visible then
				rays.Rotation = (rays.Rotation + dt * 14) % 360
			end
		end)
	end
end

function Leaderboard.OnClose()
	visible = false
	local connection = raysConnection
	if connection then
		connection:Disconnect()
		raysConnection = nil
	end
end

-- Nouvel état : ta ligne suit tes compteurs (seulement si ouvert)
function Leaderboard.Update(_data)
	if visible then
		refresh()
	else
		dirty = true
	end
end

-- Vrai si la liste doit être recalculée à la prochaine ouverture (debug)
function Leaderboard.IsDirty(): boolean
	return dirty
end

return Leaderboard
