--[[
	Leaderboard (ModuleScript) — classement (disponible dès le début)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Leaderboard

	Deux onglets :
	  - "🏠 Serveur" : les joueurs de ce serveur EN DIRECT (Dopamine actuelle,
	    visites à l'océan), mis à jour toutes les 2 s par le serveur ;
	  - "🌍 Monde"   : le top de tous les serveurs (Dopamine gagnée depuis
	    toujours), mis à jour chaque minute.
	Podium illustré pour les 3 premiers (avatar, médaille, socle), liste pour
	la suite, et en bas "Ta place" (+ ce qu'il manque pour dépasser le
	joueur juste devant). Toi : surligné en bleu.

	Données : ClientState.ServerLeaderboard / ClientState.Leaderboard
	(format v4 { Global, Server } ou ancien tableau, voir ClientState).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Leaderboard = {
	Title = "🥇 Classement",
	Subtitle = "Qui a le plus gros cerveau ?",
	Color = Theme.Colors.Blue,
	Size = Vector2.new(660, 580),
}

type Entry = { UserId: number, Name: string, Value: number, Rebirths: number?, Lifetime: number? }

type Avatar = { Frame: Frame, Image: ImageLabel, Initial: TextLabel }

type Row = {
	Frame: Frame,
	Stroke: UIStroke,
	Rank: TextLabel,
	Avatar: Avatar,
	Name: TextLabel,
	Detail: TextLabel,
	Value: TextLabel,
}

type Podium = {
	Holder: Frame,
	Avatar: Avatar,
	Ring: UIStroke,
	Name: TextLabel,
	Value: TextLabel,
	Me: Frame,
	Block: Frame,
}

local MEDALS = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = {
	Color3.fromRGB(255, 196, 40),
	Color3.fromRGB(176, 186, 204),
	Color3.fromRGB(214, 140, 84),
}
local ME_COLOR = Color3.fromRGB(228, 241, 255)
local PODIUM_HEIGHT = 172
local FOOTER_HEIGHT = 50

local player = Players.LocalPlayer
local tab = "Server"
local visible = false
local dirty = true

local tabs: UIUtil.Tabs
local infoLabel: TextLabel
local podiumFrame: Frame
local podiums: { Podium } = {}
local list: ScrollingFrame
local rows: { Row } = {}
local emptyFrame: Frame
local emptyTitle: TextLabel
local emptyBody: TextLabel
local footerLabel: TextLabel
local footerDetail: TextLabel
local footerAvatar: Avatar

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function formatValue(value: number): string
	if value < 1e6 then
		return NumberFormatter.WithSpaces(value)
	end
	return NumberFormatter.Format(value)
end

-- "1er", "2e", "3e"...
local function ordinal(rank: number): string
	return rank == 1 and "1er" or (tostring(rank) .. "e")
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

local function setAvatar(avatar: Avatar, entry: Entry, background: Color3?)
	local userId = tonumber(entry.UserId) or 0
	-- (les joueurs de test de Studio ont un UserId négatif : pas de photo)
	avatar.Image.Image = userId > 0 and UIUtil.HeadshotUrl(userId, 48) or ""
	avatar.Initial.Text = string.upper(string.sub(tostring(entry.Name or "?"), 1, 1))
	if background then
		avatar.Frame.BackgroundColor3 = background
	end
end

-- Petite étiquette "TOI"
local function meChip(parent: Instance, zIndex: number): Frame
	local chip = UIUtil.Chip({
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
	return chip
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

-- Liste normalisée de l'onglet courant (triée, Value = valeur affichée)
local function getEntries(which: string): { Entry }
	local result: { Entry } = {}
	if which == "Server" then
		local source = ClientState.ServerLeaderboard
		if type(source) == "table" then
			for _, raw in ipairs(source) do
				if type(raw) == "table" then
					table.insert(result, {
						UserId = tonumber(raw.UserId) or 0,
						Name = tostring(raw.Name or "?"),
						Value = tonumber(raw.Dopamine) or tonumber(raw.Value) or 0,
						Rebirths = tonumber(raw.Rebirths) or 0,
						Lifetime = tonumber(raw.Lifetime),
					})
				end
			end
		end
		-- Classement du serveur pas encore reçu : au moins toi
		if #result == 0 then
			local data = ClientState.Data
			if data then
				table.insert(result, {
					UserId = player.UserId,
					Name = player.DisplayName,
					Value = tonumber(data.Dopamine) or 0,
					Rebirths = tonumber(data.Rebirths) or 0,
					Lifetime = data.Stats and tonumber(data.Stats.LifetimeDopamine) or nil,
				})
			end
		else
			-- Ta ligne suit ton compteur en direct (entre deux envois du serveur)
			local data = ClientState.Data
			if data then
				for _, entry in ipairs(result) do
					if entry.UserId == player.UserId then
						entry.Value = tonumber(data.Dopamine) or entry.Value
					end
				end
			end
		end
		table.sort(result, function(a, b)
			if a.Value ~= b.Value then
				return a.Value > b.Value
			end
			return a.UserId < b.UserId
		end)
	else
		local source = ClientState.Leaderboard
		if type(source) == "table" then
			for _, raw in ipairs(source) do
				if type(raw) == "table" then
					table.insert(result, {
						UserId = tonumber(raw.UserId) or 0,
						Name = tostring(raw.Name or "?"),
						Value = tonumber(raw.Value) or tonumber(raw.Lifetime) or 0,
						Rebirths = tonumber(raw.Rebirths),
						Rank = tonumber(raw.Rank),
					} :: any)
				end
			end
		end
		table.sort(result, function(a: any, b: any)
			if a.Rank and b.Rank then
				return a.Rank < b.Rank
			end
			return a.Value > b.Value
		end)
	end
	return result
end

----------------------------------------------------------------------
-- Affichage
----------------------------------------------------------------------

local function detailText(entry: Entry): string
	if tab == "Server" then
		local parts = {}
		local rebirths = entry.Rebirths or 0
		table.insert(parts, "🌊 " .. tostring(math.floor(rebirths)) .. (rebirths >= 2 and " visites" or " visite"))
		if entry.Lifetime then
			table.insert(parts, "Total " .. NumberFormatter.Format(entry.Lifetime))
		end
		return table.concat(parts, "  •  ")
	end
	return "Dopamine gagnée au total"
end

local function refreshPodium(entries: { Entry })
	for rank, podium in ipairs(podiums) do
		local entry = entries[rank]
		podium.Holder.Visible = entry ~= nil
		if entry then
			local isMe = entry.UserId == player.UserId
			setAvatar(podium.Avatar, entry, MEDAL_COLORS[rank]:Lerp(Color3.new(1, 1, 1), 0.7))
			podium.Name.Text = entry.Name
			podium.Name.TextColor3 = isMe and Theme.Colors.Blue or Theme.Colors.Text
			podium.Value.Text = formatValue(entry.Value) .. " 💧"
			podium.Me.Visible = isMe
			podium.Ring.Thickness = isMe and 4 or 3
		end
	end
end

local function ensureRow(index: number): Row
	local existing = rows[index]
	if existing then
		return existing
	end
	local frame = UIUtil.Create("Frame", {
		Name = "Row" .. index,
		Size = UDim2.new(1, -8, 0, 48),
		BackgroundColor3 = Theme.Colors.Card,
		LayoutOrder = index,
		Parent = list,
	})
	UIUtil.Corner(frame, Theme.Radius.M)
	local stroke = UIUtil.Stroke(frame, Theme.Colors.Divider, 1.5)
	local rank = UIUtil.Label({
		Name = "Rank",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(44, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		MaxTextSize = 17,
		Parent = frame,
	})
	local avatar = buildAvatar(frame, 34, 2)
	avatar.Frame.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Frame.Position = UDim2.new(0, 56, 0.5, 0)
	local name = UIUtil.Label({
		Name = "PlayerName",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.55, -100, 0, 20),
		Position = UDim2.fromOffset(100, 6),
		MaxTextSize = 17,
		Parent = frame,
	})
	local detail = UIUtil.Label({
		Name = "Detail",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, -100, 0, 15),
		Position = UDim2.fromOffset(100, 27),
		MaxTextSize = 13,
		Parent = frame,
	})
	local value = UIUtil.Label({
		Name = "Value",
		Font = Theme.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.4, -20, 0, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		MaxTextSize = 18,
		Parent = frame,
	})
	local row: Row = {
		Frame = frame,
		Stroke = stroke,
		Rank = rank,
		Avatar = avatar,
		Name = name,
		Detail = detail,
		Value = value,
	}
	rows[index] = row
	return row
end

local function refreshFooter(entries: { Entry })
	local myIndex: number? = nil
	for index, entry in ipairs(entries) do
		if entry.UserId == player.UserId then
			myIndex = index
			break
		end
	end
	setAvatar(footerAvatar, { UserId = player.UserId, Name = player.DisplayName, Value = 0 }, ME_COLOR)
	if tab == "Server" then
		if myIndex then
			local me = entries[myIndex]
			footerLabel.Text = string.format("Ta place : %s sur %d", ordinal(myIndex), #entries)
			if myIndex == 1 then
				footerDetail.Text = #entries > 1 and "👑 Tu es le plus gros cerveau du serveur !" or "Seul(e) sur le serveur : invite tes amis !"
			else
				local ahead = entries[myIndex - 1]
				local gap = math.max(0, ahead.Value - me.Value)
				footerDetail.Text = string.format("Encore %s 💧 pour dépasser %s", formatValue(gap + 1), ahead.Name)
			end
		else
			footerLabel.Text = "Ta place : ..."
			footerDetail.Text = "Chargement du classement du serveur"
		end
	else
		if myIndex then
			footerLabel.Text = string.format("Ta place : %s du monde !", ordinal(myIndex))
			footerDetail.Text = "Tu fais partie des légendes 🌍"
		else
			local data = ClientState.Data
			local lifetime = data and data.Stats and tonumber(data.Stats.LifetimeDopamine) or 0
			footerLabel.Text = "Pas encore dans le top " .. tostring(math.max(#entries, 10))
			local last = entries[#entries]
			if last then
				footerDetail.Text = string.format("Encore %s 💧 gagnés pour y entrer", formatValue(math.max(0, last.Value - lifetime) + 1))
			else
				footerDetail.Text = "Continue de cliquer !"
			end
		end
	end
end

local function refresh()
	if not list then
		return
	end
	dirty = false
	local entries = getEntries(tab)

	infoLabel.Text = tab == "Server" and "🔴 En direct  •  classé par Dopamine actuelle"
		or "Dopamine gagnée depuis toujours  •  mis à jour chaque minute"

	local isEmpty = #entries == 0
	emptyFrame.Visible = isEmpty
	podiumFrame.Visible = not isEmpty
	list.Visible = not isEmpty
	if isEmpty then
		emptyTitle.Text = tab == "Server" and "Chargement..." or "Classement mondial en chargement..."
		emptyBody.Text = RunService:IsStudio()
				and "Dans Studio, le classement mondial ne fonctionne que si l'accès aux API (DataStore) est activé dans les paramètres du jeu."
			or "Reviens dans une minute : le top du monde arrive !"
	end

	refreshPodium(entries)

	-- Liste à partir de la 4e place
	local shown = 0
	for index = 4, #entries do
		local entry = entries[index]
		shown += 1
		local row = ensureRow(shown)
		local isMe = entry.UserId == player.UserId
		row.Frame.Visible = true
		row.Frame.BackgroundColor3 = isMe and ME_COLOR or Theme.Colors.Card
		row.Stroke.Color = isMe and Theme.Colors.Blue or Theme.Colors.Divider
		row.Rank.Text = "#" .. tostring(index)
		setAvatar(row.Avatar, entry)
		row.Name.Text = isMe and (entry.Name .. "  (toi)") or entry.Name
		row.Name.TextColor3 = isMe and Theme.Colors.Blue or Theme.Colors.Text
		row.Detail.Text = detailText(entry)
		row.Value.Text = formatValue(entry.Value) .. " 💧"
	end
	for index = shown + 1, #rows do
		rows[index].Frame.Visible = false
	end
	-- Pas de 4e place : petit message à la place de la liste
	local hint = list:FindFirstChild("Hint") :: TextLabel?
	if hint then
		hint.Visible = shown == 0
		hint.Text = tab == "Server" and "Plus il y a de joueurs, plus c'est drôle 👀" or ""
	end

	refreshFooter(entries)
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
		Parent = parent,
	})

	-- Socle (bloc au dégradé de la médaille avec le numéro)
	local block = UIUtil.Create("Frame", {
		Name = "Block",
		Size = UDim2.new(1, -24, 0, blockHeight),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	UIUtil.Corner(block, Theme.Radius.M)
	UIUtil.Stroke(block, color:Lerp(Color3.new(0, 0, 0), 0.3), 1.5, 0.3)
	UIUtil.SoftGradient(block, color, 90)
	UIUtil.Label({
		Name = "Number",
		Text = MEDALS[rank],
		Size = UDim2.new(1, 0, 0, math.min(34, blockHeight - 8)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 30,
		ZIndex = 3,
		Parent = block,
	})

	-- Valeur puis nom au-dessus du socle, puis l'avatar
	local value = UIUtil.Label({
		Name = "Value",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, -8, 0, 18),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(blockHeight + 4)),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = holder,
	})
	local name = UIUtil.Label({
		Name = "PlayerName",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -8, 0, 18),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(blockHeight + 22)),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = holder,
	})
	local avatarSize = rank == 1 and 58 or 48
	local avatar = buildAvatar(holder, avatarSize, 3)
	avatar.Frame.AnchorPoint = Vector2.new(0.5, 1)
	avatar.Frame.Position = UDim2.new(0.5, 0, 1, -(blockHeight + 44))
	local ring = UIUtil.Stroke(avatar.Frame, color, 3, 0)
	if rank == 1 then
		UIUtil.Label({
			Name = "Crown",
			Text = "👑",
			Size = UDim2.fromOffset(30, 30),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 8),
			Rotation = -12,
			MaxTextSize = 26,
			ZIndex = 6,
			Parent = avatar.Frame,
		})
	end
	local me = meChip(avatar.Frame, 7)
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.new(0.5, 0, 1, 0)

	podiums[rank] = {
		Holder = holder,
		Avatar = avatar,
		Ring = ring,
		Name = name,
		Value = value,
		Me = me,
		Block = block,
	}
end

function Leaderboard.Build(content: Frame)
	tabs = UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "Server", Text = "🏠 Serveur" },
			{ Id = "World", Text = "🌍 Monde" },
		},
		Color = Theme.Colors.Blue,
		Size = UDim2.new(1, 0, 0, 38),
		Selected = tab,
		OnSelect = function(id: string)
			tab = id
			refresh()
		end,
	})

	infoLabel = UIUtil.Label({
		Name = "Info",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 46),
		MaxTextSize = 14,
		Parent = content,
	})

	-- Podium : 2e à gauche, 1er au centre (plus haut), 3e à droite
	podiumFrame = UIUtil.Create("Frame", {
		Name = "Podium",
		Size = UDim2.new(1, -40, 0, PODIUM_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		BackgroundTransparency = 1,
		Parent = content,
	})
	buildPodium(podiumFrame, 2, 1 / 6, 38)
	buildPodium(podiumFrame, 1, 0.5, 54)
	buildPodium(podiumFrame, 3, 5 / 6, 28)

	list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -(70 + PODIUM_HEIGHT + 10 + FOOTER_HEIGHT + 8)),
		Position = UDim2.fromOffset(0, 70 + PODIUM_HEIGHT + 10),
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
	UIUtil.Label({
		Name = "Hint",
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = 10000,
		MaxTextSize = 14,
		Visible = false,
		Parent = list,
	})

	-- État vide
	emptyFrame = UIUtil.Create("Frame", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 1, -(70 + FOOTER_HEIGHT + 8)),
		Position = UDim2.fromOffset(0, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = content,
	})
	local bubble = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(96, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = emptyFrame,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, Theme.Colors.Divider, 2)
	UIUtil.Label({
		Text = "🌍",
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 12),
		MaxTextSize = 52,
		Parent = bubble,
	})
	emptyTitle = UIUtil.Label({
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, 140),
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
		Position = UDim2.fromOffset(50, 176),
		Parent = emptyFrame,
	})

	-- Pied : ta place
	local footer = UIUtil.Create("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = ME_COLOR,
		Parent = content,
	})
	UIUtil.Corner(footer, Theme.Radius.M)
	UIUtil.Stroke(footer, Theme.Colors.Blue, 1.5, 0.4)
	footerAvatar = buildAvatar(footer, 36, 2)
	footerAvatar.Frame.AnchorPoint = Vector2.new(0, 0.5)
	footerAvatar.Frame.Position = UDim2.new(0, 10, 0.5, 0)
	UIUtil.Stroke(footerAvatar.Frame, Theme.Colors.Blue, 2, 0)
	footerLabel = UIUtil.Label({
		Name = "Place",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Blue:Lerp(Color3.new(0, 0, 0), 0.3),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -70, 0, 20),
		Position = UDim2.fromOffset(56, 6),
		MaxTextSize = 17,
		Parent = footer,
	})
	footerDetail = UIUtil.Label({
		Name = "Detail",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -70, 0, 16),
		Position = UDim2.fromOffset(56, 27),
		MaxTextSize = 14,
		Parent = footer,
	})

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
	tabs.Select(tab, true)
	refresh()
end

function Leaderboard.OnClose()
	visible = false
end

-- Nouvel état : ta ligne suit ton compteur (seulement si ouvert)
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
