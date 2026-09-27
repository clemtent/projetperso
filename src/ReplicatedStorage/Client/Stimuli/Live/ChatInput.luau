--[[
	ChatInput (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Live > ChatInput

	Champ de saisie du chat du live (utilisé par Stimuli > LiveStream) :
	  - TextBox "ChatBox" (« Envoyer un message… »), bouton rond "SendChat"
	    (flèche dessinée en Frames : ne dépend d'aucune police) ; Entrée
	    (FocusLost(true)) ou le bouton = envoyer ; 120 caractères maximum
	    (compteur à partir de 90) ;
	  - tactile : toucher la liste des messages (bouton transparent "ChatTap")
	    ouvre le clavier (CaptureFocus) ;
	  - envoi : RemoteFunction "FilterText" ("Live", texte) appelée dans un
	    task.spawn (InvokeServer attend le serveur). Pendant l'envoi le champ
	    est grisé (« Envoi… ») et le bouton montre "•••". Succès : le champ est
	    vidé et options.OnMessage(texteFiltré, sujets) est appelé. Échec : le
	    message du serveur s'affiche discrètement au-dessus du champ et le
	    brouillon reste (le texte tapé n'est JAMAIS affiché ailleurs que dans
	    le champ lui-même) ;
	  - anti-spam : COOLDOWN s entre deux messages (le bouton affiche le
	    compte à rebours ; « ⏳ Mode lent : 2s » si on insiste) ;
	  - tant que le joueur n'a rien écrit, le contour du champ "respire"
	    (invitation discrète).
	Step(now) est appelé par la boucle de rendu de LiveStream (≤ 30 Hz) :
	aucune boucle ni connexion par image ici.
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local ChatInput = {}

local MAX_CHARS = 120 -- = ChatService (purpose "Live")
local COUNTER_FROM = 90 -- le compteur apparaît à partir de 90 caractères
local COOLDOWN = 3 -- secondes entre deux messages (le serveur en impose 1,2)
local FAIL_COOLDOWN = 1.3
local TIMEOUT = 10 -- sans réponse du serveur : on rend la main
local STATUS_TIME = 3

local FIELD = Color3.fromRGB(44, 38, 64)
local STROKE_IDLE = Color3.fromRGB(96, 82, 140)
local STROKE_FOCUS = Color3.fromRGB(200, 156, 255)
local STROKE_INVITE = Color3.fromRGB(255, 150, 214)
local SEND_READY = Color3.fromRGB(145, 70, 255)
local SEND_WAIT = Color3.fromRGB(74, 66, 100)
local ERROR_COLOR = Color3.fromRGB(255, 130, 140)
local SLOW_COLOR = Color3.fromRGB(255, 208, 110)
local INFO_COLOR = Color3.fromRGB(205, 196, 240)
local ARROW_BOX = 18 -- taille "design" du dessin de la flèche

export type Options = {
	Parent: GuiObject, -- panneau du chat
	TapArea: GuiObject?, -- zone (liste des messages) qui ouvre le clavier au toucher
	ZIndex: number?,
	KnownTopics: { [string]: boolean }?, -- sujets acceptés (ChatTopics.Order)
	OnMessage: (text: string, topics: { string }) -> (),
	OnFocus: ((focused: boolean) -> ())?,
}

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$")) or ""
end

-- Tronque à maxChars caractères UTF-8 (texte invalide : laissé tel quel, le serveur le refusera)
local function limit(text: string, maxChars: number): string
	local length = utf8.len(text)
	if length and length > maxChars then
		local cut = utf8.offset(text, maxChars + 1)
		if cut then
			return string.sub(text, 1, cut - 1)
		end
	end
	return text
end

function ChatInput.new(ctx: any, options: Options)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local zBase = options.ZIndex or 3
	local placeholder = Locale.T("Send a message") .. "…"
	local compactPlaceholder = Locale.T("Type here…")
	local isCompact = false

	local height, sendSize = 22, 18
	local sending, token, sentAt = false, 0, 0
	local cooldownUntil = 0
	local statusUntil, statusKind = 0, "" -- "" | "counter" | "timed"
	local hasSent, focused = false, false
	local shownSend = "" -- état affiché du bouton ("ready" | "busy" | "wait3"...)
	local inviteOn = false

	------------------------------------------------------------------
	-- Construction
	------------------------------------------------------------------
	local frame = UI.Create("Frame", {
		Name = "ChatInput",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 5, 1, -5),
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = FIELD,
		BorderSizePixel = 0,
		ZIndex = zBase,
		Parent = options.Parent,
	})
	UI.Corner(frame, 8)
	UI.Gradient(frame, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 190, 220)), 90)
	local stroke = UI.Stroke(frame, STROKE_IDLE, 1, 0.3)

	-- Zone du texte : découpe ce qui dépasse (texte long, indication) avant le bouton
	local field = UI.Create("Frame", {
		Name = "Field",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -(8 + sendSize + 7), 1, 0),
		ZIndex = zBase + 1,
		Parent = frame,
	})
	local box = UI.Create("TextBox", {
		Name = "ChatBox",
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(154, 144, 190),
		TextColor3 = Color3.fromRGB(246, 242, 255),
		Font = Theme.Fonts.Body,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		MultiLine = false,
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zBase + 1,
		Parent = field,
	})

	local send = UI.Create("TextButton", {
		Name = "SendChat",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(sendSize, sendSize),
		BackgroundColor3 = SEND_READY,
		BorderSizePixel = 0,
		ZIndex = zBase + 1,
		Parent = frame,
	})
	UI.Corner(send, UDim.new(1, 0))
	UI.Gradient(send, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 176, 236)), 90)
	local sendStroke = UI.Stroke(send, Color3.fromRGB(214, 186, 255), 1, 0.35)
	UI.AnimateButton(send, 1.12, 0.86)

	-- Flèche "envoyer" : tige + deux traits de pointe (dessin 18 x 18 mis à l'échelle)
	local arrow = UI.Create("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ARROW_BOX, ARROW_BOX),
		BackgroundTransparency = 1,
		ZIndex = zBase + 2,
		Parent = send,
	})
	local arrowScale = UI.Create("UIScale", { Parent = arrow })
	local function bar(x: number, y: number, w: number, rotation: number)
		local piece = UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, 2),
			Rotation = rotation,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zBase + 2,
			Parent = arrow,
		})
		UI.Corner(piece, 1)
	end
	bar(8.2, 9, 8, 0) -- tige (x 4.2 -> 12.2)
	bar(10.9, 7.3, 5.4, 40) -- pointe (se rejoignent vers x = 13)
	bar(10.9, 10.7, 5.4, -40)

	-- Compte à rebours / "•••" sur le bouton
	local sendLabel = UI.Create("TextLabel", {
		Name = "Wait",
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(230, 222, 255),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = zBase + 3,
		Parent = send,
	})

	-- Ligne d'état au-dessus du champ : compteur, erreur, mode lent
	-- (texte sur plusieurs lignes si besoin : la ligne grandit vers le haut)
	local status = UI.Create("TextLabel", {
		Name = "ChatStatus",
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 9,
		TextColor3 = INFO_COLOR,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(16, 12, 28),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 5, 1, -(height + 8)),
		Size = UDim2.new(1, -10, 0, 14),
		Visible = false,
		ZIndex = zBase + 4,
		Parent = options.Parent,
	})
	UI.Corner(status, 5)
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		PaddingTop = UDim.new(0, 1),
		PaddingBottom = UDim.new(0, 1),
		Parent = status,
	})

	------------------------------------------------------------------
	-- États
	------------------------------------------------------------------
	local function showStatus(text: string, color: Color3, duration: number?)
		status.Text = text
		status.TextColor3 = color
		status.Visible = true
		if duration then
			statusKind = "timed"
			statusUntil = os.clock() + duration
		else
			statusKind = "counter"
			statusUntil = 0
		end
	end

	local function hideStatus()
		status.Visible = false
		statusKind = ""
		statusUntil = 0
	end

	-- Bouton : prêt (flèche violette), envoi ("•••"), attente (compte à rebours)
	local function refreshSend(now: number)
		local state
		if sending then
			state = "busy" .. (math.floor(now * 3) % 3)
		elseif now < cooldownUntil then
			state = "wait" .. math.ceil(cooldownUntil - now)
		else
			state = "ready"
		end
		if state == shownSend then
			return
		end
		local wasWaiting = string.sub(shownSend, 1, 4) == "wait" or string.sub(shownSend, 1, 4) == "busy"
		shownSend = state
		local ready = state == "ready"
		arrow.Visible = ready
		sendLabel.Visible = not ready
		send.BackgroundColor3 = ready and SEND_READY or SEND_WAIT
		sendStroke.Transparency = ready and 0.35 or 0.7
		if sending then
			sendLabel.Text = string.rep("•", math.floor(now * 3) % 3 + 1)
		elseif not ready then
			sendLabel.Text = tostring(math.ceil(cooldownUntil - now))
		elseif wasWaiting then
			UI.Pop(send, 1.25, 0.3) -- de nouveau prêt
		end
	end

	local function setBusy(busy: boolean)
		box.TextEditable = not busy
		box.TextTransparency = busy and 0.55 or 0
		box.PlaceholderText = busy and Locale.T("Sending…") or (isCompact and compactPlaceholder or placeholder)
		refreshSend(os.clock())
	end

	local function nudge()
		local home = UDim2.new(0, 5, 1, -5)
		frame.Position = home + UDim2.fromOffset(4, 0)
		UI.Tween(frame, 0.25, { Position = home }, Enum.EasingStyle.Elastic)
	end

	local function cleanTopics(raw: any): { string }
		local topics = {}
		if type(raw) == "table" then
			for _, topic in ipairs(raw) do
				if type(topic) == "string" and (options.KnownTopics == nil or options.KnownTopics[topic]) then
					table.insert(topics, topic)
					if #topics >= 4 then
						break
					end
				end
			end
		end
		return topics
	end

	-- Réponse du serveur (ignorée si une autre demande l'a remplacée)
	local function finish(requestToken: number, ok: boolean, success: any, result: any)
		if not ctx.IsAlive() or requestToken ~= token or not sending then
			return
		end
		sending = false
		setBusy(false)
		if ok and success == true and type(result) == "table" and type(result.Text) == "string" and trim(result.Text) ~= "" then
			box.Text = ""
			hasSent = true
			cooldownUntil = os.clock() + COOLDOWN
			hideStatus()
			refreshSend(os.clock())
			local handled, err = pcall(options.OnMessage, result.Text, cleanTopics(result.Topics))
			if not handled then
				warn("[LiveStream] " .. tostring(err))
			end
		else
			-- Message du serveur (déjà traduit) ou générique ; le brouillon reste
			local message = (ok and type(result) == "string" and result ~= "") and result
				or Locale.T("Message could not be sent, try again")
			showStatus("⚠️ " .. message, ERROR_COLOR, STATUS_TIME)
			cooldownUntil = os.clock() + FAIL_COOLDOWN
			refreshSend(os.clock())
		end
	end

	local function submit()
		if sending or not options.Parent.Visible then
			return
		end
		local text = limit(trim(box.Text), MAX_CHARS)
		if text == "" then
			nudge()
			return
		end
		local now = os.clock()
		if now < cooldownUntil then
			showStatus(Locale.T("⏳ Slow mode: %ss", tostring(math.ceil(cooldownUntil - now))), SLOW_COLOR, 1.6)
			nudge()
			return
		end
		sending = true
		token += 1
		sentAt = now
		local requestToken = token
		setBusy(true)
		task.spawn(function()
			local ok, success, result = pcall(function()
				return ctx.Net.Function("FilterText"):InvokeServer("Live", text)
			end)
			finish(requestToken, ok, success, result)
		end)
	end

	local function focus()
		if sending or not options.Parent.Visible then
			return
		end
		pcall(function()
			box:CaptureFocus()
		end)
	end

	------------------------------------------------------------------
	-- Événements
	------------------------------------------------------------------
	ctx.Connect(box.FocusLost, function(enterPressed: boolean)
		focused = false
		if options.OnFocus then
			options.OnFocus(false)
		end
		if enterPressed then
			submit()
		end
	end)
	ctx.Connect(box.Focused, function()
		focused = true
		if options.OnFocus then
			options.OnFocus(true)
		end
	end)
	ctx.Connect(send.Activated, submit)

	-- Une seule ligne, 120 caractères maximum, compteur
	ctx.Connect(box:GetPropertyChangedSignal("Text"), function()
		local text = box.Text
		if string.find(text, "[\r\n]") then
			box.Text = (string.gsub(text, "[\r\n]+", " ")) -- (rappelle ce gestionnaire)
			return
		end
		local limited = limit(text, MAX_CHARS)
		if limited ~= text then
			box.Text = limited
			return
		end
		local length = utf8.len(text) or #text
		if length >= COUNTER_FROM then
			if statusKind ~= "timed" then
				showStatus(string.format("%s/%s", tostring(length), tostring(MAX_CHARS)), length >= MAX_CHARS and SLOW_COLOR or INFO_COLOR, nil)
			end
		elseif statusKind == "counter" then
			hideStatus()
		end
	end)

	-- Tactile (et souris) : toucher la liste des messages ouvre le clavier
	if options.TapArea then
		local tap = UI.Create("TextButton", {
			Name = "ChatTap",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 20,
			Parent = options.TapArea,
		})
		ctx.Connect(tap.Activated, focus)
	end

	------------------------------------------------------------------
	-- API
	------------------------------------------------------------------
	local api = { Frame = frame, Box = box, Send = send, Height = height }

	function api.SetCompact(compact: boolean)
		height = compact and 30 or 22
		sendSize = compact and 26 or 18
		api.Height = height
		frame.Size = UDim2.new(1, -10, 0, height)
		isCompact = compact
		box.TextSize = compact and 14 or 11
		field.Size = UDim2.new(1, -(8 + sendSize + 7), 1, 0)
		if not sending then
			box.PlaceholderText = compact and compactPlaceholder or placeholder
		end
		send.Size = UDim2.fromOffset(sendSize, sendSize)
		arrowScale.Scale = sendSize / ARROW_BOX
		sendLabel.TextSize = compact and 14 or 10
		status.TextSize = compact and 12 or 9
		status.Size = UDim2.new(1, -10, 0, compact and 18 or 14)
		status.Position = UDim2.new(0, 5, 1, -(height + 8))
	end

	function api.Focus()
		focus()
	end

	function api.IsFocused(): boolean
		return focused
	end

	function api.HasSent(): boolean
		return hasSent
	end

	-- Appelé par la boucle de rendu (≤ 30 Hz)
	function api.Step(now: number)
		if sending and now - sentAt > TIMEOUT then
			-- Pas de réponse : on rend la main (une réponse tardive sera ignorée)
			token += 1
			sending = false
			setBusy(false)
			showStatus("⚠️ " .. Locale.T("Message could not be sent, try again"), ERROR_COLOR, STATUS_TIME)
		end
		refreshSend(now)
		if statusKind == "timed" and now >= statusUntil then
			hideStatus()
		end
		-- Contour : focus (vif), invitation tant que rien n'est écrit, repos
		if focused then
			if inviteOn or stroke.Color ~= STROKE_FOCUS then
				inviteOn = false
				stroke.Color, stroke.Transparency, stroke.Thickness = STROKE_FOCUS, 0, 1.5
			end
		elseif not hasSent then
			inviteOn = true
			stroke.Color, stroke.Thickness = STROKE_INVITE, 1.5
			stroke.Transparency = 0.15 + 0.5 * (0.5 + 0.5 * math.sin(now * 3.2))
		elseif inviteOn or stroke.Color ~= STROKE_IDLE then
			inviteOn = false
			stroke.Color, stroke.Transparency, stroke.Thickness = STROKE_IDLE, 0.3, 1
		end
	end

	return api
end

return ChatInput
