--[[
	DuelKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > DuelKit

	Petits outils partagés par les duels de l'arcade (Duel_*) :
	  - Label(props)            : texte néon (police du thème) ;
	  - Banner(parent, api)     : bandeau d'état en haut du plateau ("À toi !", "Bob réfléchit...") ;
	  - Countdown(parent)       : gros compte à rebours 3, 2, 1 (début des jeux en manches) ;
	  - Pulse(instance, props)  : animation douce en boucle (une seule Tween, rien par image) ;
	  - Track(api, duel, fn)    : suit l'état du duel (duelUpdate / duelEnd) et appelle fn(état, genre).
	Ce n'est PAS un jeu : le panneau Arcade ne charge que les modules "Solo_*" / "Duel_*".
]]

local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)

local Kit = {}

local WHITE = Color3.new(1, 1, 1)

function Kit.Label(props)
	local label = UIUtil.Create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.Color or WHITE,
		TextSize = props.TextSize or 16,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped == true,
		Size = props.Size or UDim2.new(1, 0, 0, 20),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 30,
		Parent = props.Parent,
	})
	return label
end

-- Animation en boucle aller-retour (coupée par Stop / Destroy de l'objet)
function Kit.Pulse(instance: Instance, props, duration: number?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration or 0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		props
	)
	tween:Play()
	return tween
end

-- Bandeau d'état (pastille arrondie en haut, texte + couleur)
function Kit.Banner(parent: Instance, zIndex: number?)
	local z = zIndex or 30
	local frame = UIUtil.Create("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(40, 26, 84),
		ZIndex = z,
		Parent = parent,
	})
	UIUtil.Corner(frame, UDim.new(1, 0))
	local stroke = UIUtil.Stroke(frame, WHITE, 2, 0.2)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = frame })
	local label = UIUtil.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 17,
		ZIndex = z + 1,
		Parent = frame,
	})
	local scale = UIUtil.Create("UIScale", { Parent = frame })
	local banner = {}
	function banner.Set(text: string, color: Color3, pop: boolean?)
		if label.Text == text and stroke.Color == color then
			return
		end
		label.Text = text
		stroke.Color = color
		frame.BackgroundColor3 = color:Lerp(Color3.fromRGB(24, 14, 48), 0.72)
		if pop then
			scale.Scale = 1.15
			UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	banner.Frame = frame
	return banner
end

-- Gros compte à rebours (3, 2, 1) au centre
function Kit.Countdown(parent: Instance, zIndex: number?)
	local z = zIndex or 40
	local label = Kit.Label({
		Name = "Countdown",
		Text = "",
		TextSize = 96,
		Font = Theme.Fonts.Number,
		Color = Color3.fromRGB(255, 216, 74),
		Size = UDim2.fromOffset(200, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		ZIndex = z,
		Parent = parent,
	})
	label.Visible = false
	UIUtil.Create("UIStroke", { Color = Color3.fromRGB(255, 79, 176), Thickness = 3, Parent = label })
	local scale = UIUtil.Create("UIScale", { Parent = label })
	local token = 0
	local countdown = {}
	-- Affiche seconds, seconds-1, ... 1 puis "GO!"
	function countdown.Run(seconds: number, sound: ((string, number?) -> ())?)
		token += 1
		local mine = token
		local whole = math.max(1, math.ceil(seconds - 0.05))
		local offset = seconds - (whole - 1) - 1
		label.Visible = true
		local function show(value: string)
			if token ~= mine then
				return
			end
			label.Text = value
			scale.Scale = 1.6
			label.TextTransparency = 0
			UIUtil.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			if sound then
				sound("Click", value == "GO!" and 1.6 or 1.1)
			end
		end
		for index = 0, whole - 1 do
			task.delay(math.max(0, offset) + index, show, tostring(whole - index))
		end
		task.delay(math.max(0, offset) + whole, function()
			show("GO!")
			task.delay(0.5, function()
				if token == mine then
					label.Visible = false
				end
			end)
		end)
	end
	function countdown.Hide()
		token += 1
		label.Visible = false
	end
	return countdown
end

-- Suit l'état du duel : callback(état, genre) à chaque mise à jour du MÊME duel
function Kit.Track(api, callback: (any, string) -> ())
	local duelId = api.Duel and api.Duel.Id
	return api.OnEvent(function(kind: string, payload)
		if (kind == "duelUpdate" or kind == "duelEnd" or kind == "duelStart") and type(payload) == "table" and payload.Id == duelId then
			callback(payload, kind)
		end
	end)
end

return Kit
