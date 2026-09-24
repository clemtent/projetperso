--[[
	AchievementPopup (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > AchievementPopup

	1) Médaillons de succès (utilisés aussi par le panneau des succès) :
	   AchievementPopup.Tier(succès)         -> palier { Name, Top, Bottom, Ring }
	   AchievementPopup.Medallion(parent, taille, succès) -> { Frame, Set(débloqué) }
	   Palier selon la taille de l'objectif : parmi les succès d'une même
	   statistique, le plus petit objectif est en bronze, puis argent, or,
	   diamant (un succès seul dans sa statistique : palier selon sa récompense).
	   Verrouillé : médaillon gris, icône fantôme et petit cadenas.

	2) Grande fenêtre de fête quand un succès est débloqué
	   (Notify { Type = "Achievement", Id, Name, Icon, Reward, BadgeAwarded }) :
	   médaillon qui tourne devant des rayons, titre, nom, récompense, et
	   "🏅 Badge Roblox obtenu !" si le serveur a donné un vrai badge.
	   Non bloquante (les clics passent au travers), en haut de l'écran, avec
	   une file d'attente (les suivants s'enchaînent, au-delà de 3 : résumé).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local AchievementPopup = {}

export type Tier = { Name: string, Top: Color3, Bottom: Color3, Ring: Color3 }
export type Medallion = { Frame: Frame, Set: (unlocked: boolean) -> () }

local TIERS: { Tier } = {
	{ Name = "Bronze", Top = Color3.fromRGB(245, 190, 130), Bottom = Color3.fromRGB(176, 106, 52), Ring = Color3.fromRGB(125, 68, 28) },
	{ Name = "Argent", Top = Color3.fromRGB(250, 252, 255), Bottom = Color3.fromRGB(160, 170, 188), Ring = Color3.fromRGB(105, 115, 132) },
	{ Name = "Or", Top = Color3.fromRGB(255, 240, 150), Bottom = Color3.fromRGB(232, 162, 20), Ring = Color3.fromRGB(165, 105, 0) },
	{ Name = "Diamant", Top = Color3.fromRGB(210, 248, 255), Bottom = Color3.fromRGB(90, 165, 255), Ring = Color3.fromRGB(40, 105, 200) },
}
local LOCKED = { Top = Color3.fromRGB(236, 236, 240), Bottom = Color3.fromRGB(185, 185, 192), Ring = Color3.fromRGB(150, 150, 158) }

local SHOW_TIME = 3.6 -- secondes d'affichage d'un succès
local MAX_QUEUE = 3 -- au-delà : un seul bandeau résumé

local tierCache: { [string]: Tier } = {}
local layer: Frame? = nil
local queue: { any } = {}
local skipped = 0
local showing = false

----------------------------------------------------------------------
-- Paliers
----------------------------------------------------------------------

local function computeTiers()
	local groups: { [string]: { any } } = {}
	for _, achievement in ipairs(Config.Achievements) do
		local stat = tostring(achievement.Stat)
		groups[stat] = groups[stat] or {}
		table.insert(groups[stat], achievement)
	end
	for _, list in pairs(groups) do
		table.sort(list, function(a, b)
			return (tonumber(a.Goal) or 0) < (tonumber(b.Goal) or 0)
		end)
		for rank, achievement in ipairs(list) do
			local index: number
			if #list == 1 then
				-- Seul dans sa statistique : selon la récompense
				local reward = tonumber(achievement.Reward) or 0
				index = reward < 1e5 and 1 or (reward < 1e6 and 2 or (reward < 1e8 and 3 or 4))
			else
				index = math.min(rank, #TIERS)
			end
			tierCache[achievement.Id] = TIERS[index]
		end
	end
end

function AchievementPopup.Tier(achievement): Tier
	if next(tierCache) == nil then
		computeTiers()
	end
	return tierCache[achievement and achievement.Id or ""] or TIERS[1]
end

----------------------------------------------------------------------
-- Médaillon
----------------------------------------------------------------------

-- `tierOverride` (optionnel) : impose un palier (ex. résumé de plusieurs succès)
function AchievementPopup.Medallion(parent: Instance, size: number, achievement, tierOverride: Tier?): Medallion
	local tier = tierOverride or AchievementPopup.Tier(achievement)
	local holder = UIUtil.Create("Frame", {
		Name = "Medallion",
		Size = UDim2.fromOffset(size, math.floor(size * 1.2)),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	-- Rubans sous le médaillon
	local ribbons = {}
	for side = -1, 1, 2 do
		local ribbon = UIUtil.Create("Frame", {
			Name = "Ribbon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, side * size * 0.16, 0, size * 0.62),
			Size = UDim2.fromOffset(math.floor(size * 0.24), math.floor(size * 0.52)),
			Rotation = side * 18,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = holder,
		})
		UIUtil.Corner(ribbon, 3)
		local gradient = UIUtil.Gradient(ribbon, ColorSequence.new(tier.Bottom, tier.Ring), 90)
		table.insert(ribbons, gradient)
	end

	local outer = UIUtil.Create("Frame", {
		Name = "Outer",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	UIUtil.Corner(outer, UDim.new(1, 0))
	local outerStroke = UIUtil.Stroke(outer, tier.Ring, math.max(1.5, size / 40), 0)
	local outerGradient = UIUtil.Gradient(outer, ColorSequence.new(tier.Top, tier.Bottom), 45)

	local inner = UIUtil.Create("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(0.74, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = outer,
	})
	UIUtil.Corner(inner, UDim.new(1, 0))
	UIUtil.Stroke(inner, Color3.new(1, 1, 1), math.max(1, size / 60), 0.4)
	local innerGradient = UIUtil.Gradient(inner, ColorSequence.new(tier.Bottom, tier.Top), 45)

	-- Reflet
	local shine = UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(0.34, 0.2),
		Position = UDim2.fromScale(0.14, 0.12),
		Rotation = -35,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.45,
		ZIndex = 5,
		Parent = outer,
	})
	UIUtil.Corner(shine, UDim.new(1, 0))

	local icon = UIUtil.Label({
		Name = "Icon",
		Text = tostring(achievement and achievement.Icon or "🏆"),
		Size = UDim2.fromScale(0.6, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = math.floor(size * 0.42),
		ZIndex = 4,
		Parent = outer,
	})

	local lock = UIUtil.Create("Frame", {
		Name = "Lock",
		Size = UDim2.fromOffset(math.floor(size * 0.34), math.floor(size * 0.34)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = Theme.Colors.Dark,
		ZIndex = 6,
		Visible = false,
		Parent = outer,
	})
	UIUtil.Corner(lock, UDim.new(1, 0))
	UIUtil.Stroke(lock, Color3.new(1, 1, 1), 1.5, 0)
	UIUtil.Label({
		Text = "🔒",
		Size = UDim2.fromScale(0.7, 0.7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = math.floor(size * 0.2),
		ZIndex = 7,
		Parent = lock,
	})

	local medallion: Medallion = {
		Frame = holder,
		Set = function(unlocked: boolean)
			local colors = unlocked and tier or LOCKED
			outerGradient.Color = ColorSequence.new(colors.Top, colors.Bottom)
			innerGradient.Color = ColorSequence.new(colors.Bottom, colors.Top)
			outerStroke.Color = colors.Ring
			for _, gradient in ipairs(ribbons) do
				gradient.Color = ColorSequence.new(colors.Bottom, colors.Ring)
			end
			icon.TextTransparency = unlocked and 0 or 0.78
			shine.BackgroundTransparency = unlocked and 0.45 or 0.7
			lock.Visible = not unlocked
		end,
	}
	medallion.Set(true)
	return medallion
end

----------------------------------------------------------------------
-- Fenêtre de fête
----------------------------------------------------------------------

function AchievementPopup.Build(parent: Frame)
	layer = parent
end

local showNext: () -> ()

-- Affiche une carte ; `summary` = texte de résumé (plusieurs succès)
local function present(payload, summary: string?)
	local target = layer
	if not target then
		showing = false
		return
	end
	local achievement = payload.Id and Config.AchievementsById[payload.Id] or nil
	local fallback = {
		Id = tostring(payload.Id or ""),
		Icon = payload.Icon or "🏆",
		Stat = "",
		Goal = 1,
		Reward = tonumber(payload.Reward) or 0,
	}
	local info = achievement or fallback
	local tier = summary and TIERS[3] or AchievementPopup.Tier(info)
	local badge = payload.BadgeAwarded == true

	-- Support (non bloquant : les clics passent au travers)
	local holder = UIUtil.Create("Frame", {
		Name = "AchievementPopup",
		Size = UDim2.fromOffset(440, 136),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -170),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = target,
	})
	local group = UIUtil.Create("CanvasGroup", {
		Name = "Fade",
		Size = UDim2.new(1, 24, 1, 24),
		Position = UDim2.fromOffset(-12, -12),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		ZIndex = 30,
		Parent = holder,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = group,
	})
	UIUtil.Corner(card, 24)
	UIUtil.Stroke(card, tier.Ring, 2, 0.1)
	UIUtil.Shadow(card, 5, 0.8, 3)
	UIUtil.Gradient(card, ColorSequence.new(Color3.new(1, 1, 1), tier.Top:Lerp(Color3.new(1, 1, 1), 0.55)), 90)

	-- Zone du médaillon (rayons qui tournent + médaillon qui "pop")
	local stage = UIUtil.Create("Frame", {
		Name = "Stage",
		Size = UDim2.fromOffset(120, 120),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	local rays = UIUtil.Rays(stage, tier.Bottom, 8, 150, UDim2.fromScale(0.5, 0.5), 3)
	local medallion = AchievementPopup.Medallion(stage, 76, info, tier)
	medallion.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
	medallion.Frame.Position = UDim2.fromScale(0.5, 0.56)
	medallion.Frame.ZIndex = 4 -- devant les rayons
	local medalScale = UIUtil.Create("UIScale", { Scale = 0.2, Parent = medallion.Frame })

	-- Textes
	UIUtil.Label({
		Name = "Title",
		Text = summary and "SUCCÈS EN RAFALE !" or "SUCCÈS DÉBLOQUÉ !",
		Font = Theme.Fonts.Title,
		TextColor3 = tier.Ring,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.fromOffset(134, 14),
		MaxTextSize = 16,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Label({
		Name = "AchievementName",
		Text = summary or tostring(payload.Name or (achievement and achievement.Name) or payload.Text or ""),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 30),
		Position = UDim2.fromOffset(134, 34),
		MaxTextSize = 26,
		ZIndex = 4,
		Parent = card,
	})
	local reward = summary and 0 or (tonumber(payload.Reward) or (achievement and tonumber(achievement.Reward)) or 0)
	UIUtil.Label({
		Name = "Reward",
		Text = (summary and "Chaque succès : " or "")
			.. (reward > 0 and ("🎁 +" .. NumberFormatter.Format(reward) .. " Dopamine  •  ") or "")
			.. "+" .. tostring(math.floor(Config.AchievementBonus * 100 + 0.5)) .. " % pour toujours",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 18),
		Position = UDim2.fromOffset(134, 66),
		MaxTextSize = 14,
		ZIndex = 4,
		Parent = card,
	})
	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -150, 0, 22),
		Position = UDim2.fromOffset(134, 88),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	UIUtil.Chip({
		Text = "Palier " .. tier.Name,
		Color = tier.Bottom,
		TextColor3 = Theme.ContrastText(tier.Bottom),
		Height = 22,
		TextSize = 12,
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = chips,
	})
	if badge then
		UIUtil.Chip({
			Text = "🏅 Badge Roblox obtenu !",
			Color = Theme.Colors.Robux,
			TextColor3 = Theme.Colors.TextLight,
			Height = 22,
			TextSize = 12,
			LayoutOrder = 2,
			ZIndex = 5,
			Parent = chips,
		})
	end

	-- Fête
	SoundManager.Play("Achievement", 1.1)
	task.delay(0.15, SoundManager.Play, "Bonus", 1.5)
	Effects.Confetti(badge and 70 or 45)

	-- Entrée : descend en rebondissant, le médaillon grossit
	UIUtil.Tween(holder, 0.55, { Position = UDim2.new(0.5, 0, 0, 36) }, Enum.EasingStyle.Back)
	task.delay(0.2, function()
		UIUtil.Tween(medalScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
	end)

	local started = os.clock()
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		rays.Rotation = (rays.Rotation + dt * 40) % 360
		local t = os.clock() - started
		medallion.Frame.Rotation = math.sin(t * 3) * 6
	end)

	task.delay(SHOW_TIME, function()
		UIUtil.Tween(holder, 0.35, { Position = UDim2.new(0.5, 0, 0, -170) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(group, 0.35, { GroupTransparency = 1 })
		task.wait(0.38)
		connection:Disconnect()
		holder:Destroy()
		showNext()
	end)
end

showNext = function()
	local nextPayload = table.remove(queue, 1)
	if nextPayload then
		present(nextPayload)
		return
	end
	if skipped > 0 then
		local count = skipped
		skipped = 0
		present({ Icon = "🏆" }, string.format("+%d autres succès !", count))
		return
	end
	showing = false
end

-- Nouveau succès débloqué (payload de Notify "Achievement")
function AchievementPopup.Show(payload)
	if type(payload) ~= "table" then
		return
	end
	if #queue >= MAX_QUEUE then
		skipped += 1
		return
	end
	table.insert(queue, payload)
	if not showing then
		showing = true
		showNext()
	end
end

return AchievementPopup
