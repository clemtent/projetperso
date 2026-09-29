--[[
	FoodBoostBadge (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > FoodBoostBadge

	🍦 Petite carte du BOOST NOURRITURE (v9.8, FAIR98) pour le HUD du
	clicker, à côté de la carte du boost Robux ("⏱️ x2") : "🍦 x1,5" +
	minuteur "1:42". Lit ClientState.Data.FoodBoost (envoyé par le serveur :
	FoodService:GetClientState) ; compte à rebours fluide entre deux états.
	Cachée quand aucun boost nourriture n'est actif.

	API (CenterColumn, 2 lignes) :
	  local card = FoodBoostBadge.Create(parent, layoutOrder)   -- à la construction
	  FoodBoostBadge.Update(card)                                -- à chaque image (updateStatus)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Theme = require(Client.Theme)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local FoodBoostBadge = {}

local PINK = Color3.fromRGB(236, 72, 140)

-- fin du boost (os.clock) mémorisée par carte, recalée quand l'état change
type Card = { Frame: Frame, Title: TextLabel, Timer: TextLabel, EndsAt: number, Mult: number, Icon: string, Seen: any }

function FoodBoostBadge.Create(parent: Instance, layoutOrder: number?): Card
	local frame = UIUtil.Create("Frame", {
		Name = "FoodBoost",
		Size = UDim2.fromOffset(62, 38),
		BackgroundColor3 = PINK,
		LayoutOrder = layoutOrder or 4,
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(frame, Theme.Radius.S)
	UIUtil.Stroke(frame, Theme.Colors.Border, 1.5, 0.3)
	UIUtil.Gradient(frame, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), 90)
	UIUtil.Create("UIScale", { Name = "PopScale", Parent = frame })
	local title = UIUtil.Label({
		Text = "🍦 x1.5",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -8, 0, 17),
		Position = UDim2.fromOffset(4, 3),
		MaxTextSize = 14,
		ZIndex = 2,
		Parent = frame,
	})
	local timer = UIUtil.Label({
		Text = "0:00",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -8, 0, 15),
		Position = UDim2.fromOffset(4, 20),
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = frame,
	})
	for _, label in ipairs({ title, timer }) do
		local stroke = UIUtil.Stroke(label, Color3.fromRGB(120, 20, 70), 1, 0.5)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	return { Frame = frame, Title = title, Timer = timer, EndsAt = 0, Mult = 1, Icon = "🍦", Seen = nil }
end

function FoodBoostBadge.Update(card: Card?)
	if not card then
		return
	end
	local data = ClientState.Data
	local boost = type(data) == "table" and data.FoodBoost or nil
	-- nouvel état reçu : on recale la fin (écarts < 1 s ignorés)
	if boost ~= card.Seen then
		card.Seen = boost
		local remaining = type(boost) == "table" and tonumber(boost.Remaining) or 0
		local m = type(boost) == "table" and tonumber(boost.Multiplier) or 1
		if remaining and remaining > 0 and m and m > 1 then
			local newEnd = os.clock() + remaining
			if math.abs(newEnd - card.EndsAt) > 1 then
				card.EndsAt = newEnd
			end
			card.Mult = m
			local food = Config.FoodById[boost.Food or ""]
			card.Icon = food and food.Icon or "🍦"
		else
			card.EndsAt = 0
		end
	end
	local left = card.EndsAt - os.clock()
	local visible = left > 0
	if card.Frame.Visible ~= visible then
		card.Frame.Visible = visible
		if visible then
			UIUtil.Pop(card.Frame, 0.3, 0.4)
		end
	end
	if visible then
		local title = card.Icon .. " " .. NumberFormatter.Multiplier(card.Mult)
		if card.Title.Text ~= title then
			card.Title.Text = title
		end
		local clock = UIUtil.FormatClock(left)
		if card.Timer.Text ~= clock then
			card.Timer.Text = clock
		end
		card.Frame.Rotation = math.sin(os.clock() * (if left < 30 then 9 else 3)) * 3
	end
end

return FoodBoostBadge
