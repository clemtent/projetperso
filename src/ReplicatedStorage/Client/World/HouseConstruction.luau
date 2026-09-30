--[[
	HouseConstruction (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseConstruction

	🏗️ v10 (CONSTRUCT10) : chantiers et maisons qui se construisent, côté
	client (lancé par TownClient : Start / Observe / Step / ArrivalDone / Stop).
	  - PARCELLE SANS PROPRIÉTAIRE = CHANTIER (ConstructionSite), aussi sur
	    les places vides des quartiers (WorldLayout.FillerLots) : en flux,
	    3 niveaux de détail selon la distance de la caméra et le réglage
	    "Détail" (GraphicsQuality) ; grues en silhouette jusqu'à ~1300 studs ;
	  - UN JOUEUR ARRIVE (nouvelle maison pendant qu'on est en ville), change
	    de style de maison, ou déménage de quartier : sa maison SE CONSTRUIT
	    sous les yeux de tous ceux qui sont près (HouseBuildAnim, ~11,5 s) ;
	    le chantier fait place nette et sa grue sert à la construction ;
	  - LE PROPRIÉTAIRE, à sa 1re entrée en ville de la session : sa maison
	    reste un chantier, puis (après le survol d'arrivée) moment caméra :
	    bandes de cinéma, la caméra rejoint sa parcelle (fondu si c'est loin),
	    tourne doucement pendant la construction, "🏠 Ta maison est prête !",
	    confettis, retour derrière l'avatar. Bouton "⏭ Passer" à tout moment ;
	  - petites animations : les portillons (attribut Micro = "Swing" posé par
	    HOUSE10 : HingeCF, OpenAngle, Range) s'ouvrent quand on approche ; le
	    drapeau des boîtes aux lettres (pièces "MailFlag") se lève quand
	    quelqu'un passe devant.
	Sûreté : quitter la ville, être DANS une maison en construction, ou une
	maison détruite -> l'animation se termine tout de suite (état exact).

	Crochets TownClient (voir le rapport CONSTRUCT10) :
	  HouseConstruction.Start({ Folder, Toast?, GetSnapshots, GetHouses })
	  HouseConstruction.Observe(userId, house, snapshot)  (après new / Update)
	  HouseConstruction.Step(dt)                            (chaque image)
	  HouseConstruction.ArrivalDone()                       (après le survol)
	  HouseConstruction.Stop()
	  HouseConstruction.Stats() -> { Sites, Full, Lite, Parts, Anims }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local ConstructionSite = require(script.Parent.ConstructionSite)
local HouseBuildAnim = require(script.Parent.HouseBuildAnim)
local Kit = require(script.Parent.ConstructionKit)

local HouseConstruction = {}

local LocalPlayer = Players.LocalPlayer

local FULL_IN = 220 -- (studs, x DetailScale) chantier complet plus près que ça
local FULL_OUT = 255
local LITE_IN = 1300 -- silhouette (grue) plus près que ça
local LITE_OUT = 1400
local SYNC_EVERY = 0.5
local ANIM_RANGE = 340 -- (studs) une maison plus loin que ça apparaît sans animation
local OWNER_FALLBACK = 16 -- (s) sans ArrivalDone : moment du propriétaire au plus tard
local MICRO_RANGE = 140
local LOAD_WINDOW = 12 -- (s) sans ArrivalDone : fin du chargement au plus tard

local GUI_NAME = "ConstructionGui"

local function T(text: string, ...: any): string
	local ok, value = pcall(Locale.T, text, ...)
	return if ok and type(value) == "string" then value else text
end

-- GraphicsQuality (facultatif)
local gfxModule: any = nil
local gfxTried = false
local function detailScale(): number
	if not gfxTried then
		gfxTried = true
		local module = ReplicatedStorage.Shared:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				gfxModule = result
			end
		end
	end
	if gfxModule and type(gfxModule.DetailScale) == "function" then
		local ok, value = pcall(gfxModule.DetailScale)
		if ok and type(value) == "number" and value > 0 then
			return value
		end
	end
	return 1
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

type Record = { House: any, Size: any, Plot: number? }

local S: any = {
	Active = false,
	Opts = nil,
	Folder = nil,
	Known = {} :: { [number]: boolean },
	Records = {} :: { [number]: Record },
	Sites = {} :: { [string]: any },
	Anims = {} :: { [number]: any },
	Clearing = {} :: { any }, -- chantiers en cours de retrait animé
	SyncClock = 0,
	StartedAt = 0,
	Owner = nil, -- { State, Anim, House, Plot, Since, ... }
	Micro = {} :: { any },
	MicroConns = {} :: { RBXScriptConnection },
	MicroParts = {} :: { [BasePart]: boolean },
	Gui = nil,
	DS = 1,
}
local ownerSeen = false -- (1re entrée de la session : le moment du propriétaire)
local ownerPlot: number? = nil -- (parcelle et taille de sa maison au dernier moment : un
local ownerSize: any = nil -- déménagement / nouveau style relance le moment)

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function camPos(): Vector3
	local cam = camera()
	return if cam then cam.CFrame.Position else WorldLayout.Origin()
end

local function plotCount(): number
	local folder = workspace:FindFirstChild("DopamineTown")
	local count = folder and folder:GetAttribute("PlotCount")
	return if type(count) == "number" then count else WorldLayout.PlotCount(Players.MaxPlayers)
end

local function localRoot(): BasePart?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

----------------------------------------------------------------------
-- Chantiers : quelles places ?
----------------------------------------------------------------------

type Spot = { Key: string, CF: CFrame, Style: string, W: number, D: number, Seed: number, Plot: number? }

local STYLES = { "Cottage", "Townhouse", "Loft", "Mansion" }

local function spotStyle(style: any, seed: number): string
	if type(style) == "string" and table.find(STYLES, style) then
		return style
	end
	return STYLES[(seed % 3) + 1]
end

local function allSpots(count: number): { Spot }
	local spots: { Spot } = {}
	for i = 1, count do
		local ok, cf = pcall(WorldLayout.PlotCFrame, i, count)
		if ok and typeof(cf) == "CFrame" then
			local style = nil
			pcall(function()
				local district = (WorldLayout :: any).PlotDistrict(i, count)
				style = district and district.Style
			end)
			local w, d = WorldLayout.PLOT_W, WorldLayout.PLOT_D
			pcall(function()
				local pw, pd = (WorldLayout :: any).PlotSize(i, count)
				if type(pw) == "number" and type(pd) == "number" then
					w, d = pw, pd
				end
			end)
			table.insert(spots, { Key = "P" .. i, CF = cf, Style = spotStyle(style, i), W = w, D = d, Seed = i, Plot = i })
		end
	end
	-- places vides des quartiers : chantiers permanents
	pcall(function()
		local lots = (WorldLayout :: any).FillerLots(count)
		for k, lot in ipairs(lots or {}) do
			local cf = (WorldLayout :: any).LotCFrame(lot)
			local style = nil
			pcall(function()
				local district = (WorldLayout :: any).District(count, lot.District)
				style = district and district.Style
			end)
			table.insert(spots, { Key = "L" .. k, CF = cf, Style = spotStyle(style, 100 + k), W = tonumber(lot.W) or WorldLayout.PLOT_W, D = tonumber(lot.D) or WorldLayout.PLOT_D, Seed = 100 + k, Plot = nil })
		end
	end)
	return spots
end

-- Parcelles occupées (d'après les instantanés : immédiat, côté client)
local function occupied(): { [number]: number }
	local map = {}
	local opts = S.Opts
	local snapshots = opts and opts.GetSnapshots and opts.GetSnapshots()
	if type(snapshots) == "table" then
		for userId, snapshot in pairs(snapshots) do
			local plot = type(snapshot) == "table" and tonumber(snapshot.Plot)
			if plot then
				map[plot] = tonumber(userId) or 0
			end
		end
	else
		-- secours : attributs des parcelles du serveur
		local town = workspace:FindFirstChild("DopamineTown")
		local plots = town and town:FindFirstChild("Plots")
		if plots then
			for _, model in ipairs(plots:GetChildren()) do
				local index, owner = model:GetAttribute("Index"), model:GetAttribute("OwnerId")
				if type(index) == "number" and type(owner) == "number" and owner ~= 0 then
					map[index] = owner
				end
			end
		end
	end
	return map
end

local spotCache: { Count: number, Spots: { Spot } }? = nil

local function syncSites()
	local count = plotCount()
	if not spotCache or spotCache.Count ~= count then
		spotCache = { Count = count, Spots = allSpots(count) }
	end
	local owners = occupied()
	local owner = S.Owner
	-- parcelles où une maison est DÉJÀ construite ici (jamais de chantier dessous)
	local built: { [number]: boolean } = {}
	for _, rec in pairs(S.Records) do
		if rec.Plot and rec.House and rec.House.Alive ~= false then
			built[rec.Plot] = true
		end
	end
	local wanted: { [string]: Spot } = {}
	for _, spot in ipairs((spotCache :: any).Spots) do
		local keep = true
		if spot.Plot and built[spot.Plot] then
			keep = false
		elseif spot.Plot then
			local userId = owners[spot.Plot]
			if userId then
				local rec = S.Records[userId]
				-- occupée : chantier gardé tant que la maison n'est pas là, ou
				-- pour le moment du propriétaire (pas encore joué)
				keep = rec == nil or rec.Plot ~= spot.Plot
			end
		end
		-- sa maison pas encore construite (moment du propriétaire) : chantier gardé
		if spot.Plot and owner and owner.Plot == spot.Plot and (owner.State == "Pending" or owner.State == "Moving") then
			keep = true
		end
		if keep then
			wanted[spot.Key] = spot
		end
	end
	for key, site in pairs(S.Sites) do
		if site.Done then
			S.Sites[key] = nil
		elseif not wanted[key] then
			site:Destroy()
			S.Sites[key] = nil
		end
	end
	local loaded = os.clock() - S.StartedAt > 4
	for key, spot in pairs(wanted) do
		if not S.Sites[key] then
			S.Sites[key] = ConstructionSite.new(spot.CF, {
				Parent = S.Folder,
				Seed = spot.Seed,
				Style = spot.Style,
				PlotW = spot.W,
				PlotD = spot.D,
				Name = "Site_" .. key,
				Appear = loaded, -- (une parcelle qui se libère : fondu)
			})
			S.Sites[key].Key = key
			S.Sites[key].Plot = spot.Plot
		end
	end
end

-- Niveaux de détail (au plus un chantier complet construit par image)
local function stepLevels()
	local pos = camPos()
	local ds = S.DS
	local owner = S.Owner
	local builtFull = false
	local builtLite = 0
	for _, site in pairs(S.Sites) do
		if not site.Done and not site.Clearing then
			local distance = (site.Ground.Position - pos).Magnitude
			local level = site.Level
			local want = level
			local forced = owner and (owner.State == "Pending" or owner.State == "Moving") and owner.Plot ~= nil and site.Plot == owner.Plot
			if forced or distance < FULL_IN * ds then
				want = 2
			elseif level == 2 and distance < FULL_OUT * ds then
				want = 2
			elseif distance < LITE_IN then
				want = 1
			elseif level >= 1 and distance < LITE_OUT then
				want = 1
			else
				want = 0
			end
			if want ~= level then
				if want == 2 then
					if not builtFull then
						builtFull = true
						site.DetailScale = ds
						site:SetLevel(2)
					end
				elseif want == 1 then
					if builtLite < 4 then
						builtLite += 1
						site:SetLevel(1)
					end
				else
					site:SetLevel(0)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Interface (moment du propriétaire)
----------------------------------------------------------------------

local function destroyGui()
	if S.Gui then
		S.Gui.Screen:Destroy()
		S.Gui = nil
	end
end

local function makeGui(): any
	if S.Gui then
		return S.Gui
	end
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 60
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local function frame(name: string, props: { [string]: any }): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		for k, v in pairs(props) do
			(f :: any)[k] = v
		end
		f.Parent = props.Parent or screen
		return f
	end
	local fade = frame("Fade", { BackgroundColor3 = Color3.fromRGB(255, 236, 246), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	local top = frame("BarTop", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0.085, 0), Position = UDim2.new(0, 0, -0.1, 0), ZIndex = 10 })
	local bottom = frame("BarBottom", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0.085, 0), Position = UDim2.new(0, 0, 1.02, 0), ZIndex = 10 })
	-- légende + barre de progression (au-dessus de la bande du bas)
	local caption = frame("Caption", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.12, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.9, -6), Size = UDim2.new(0.62, 0, 0.16, 0), ZIndex = 20, Visible = false })
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 90)
	limit.MinSize = Vector2.new(220, 50)
	limit.Parent = caption
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = caption
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 170, 210)
	stroke.Thickness = 2
	stroke.Parent = caption
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 6)
	title.Size = UDim2.new(1, -28, 0.42, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 72, 140)
	title.Text = T("🏗️ Your house is being built…")
	title.ZIndex = 21
	title.Parent = caption
	local phase = Instance.new("TextLabel")
	phase.Name = "Phase"
	phase.BackgroundTransparency = 1
	phase.Position = UDim2.new(0, 14, 0.46, 0)
	phase.Size = UDim2.new(1, -28, 0.26, 0)
	phase.Font = Enum.Font.GothamBold
	phase.TextScaled = true
	phase.TextColor3 = Color3.fromRGB(90, 60, 110)
	phase.Text = ""
	phase.ZIndex = 21
	phase.Parent = caption
	local track = frame("Track", { Parent = caption, BackgroundColor3 = Color3.fromRGB(255, 226, 240), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 7), ZIndex = 21 })
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local fill = frame("Fill", { Parent = track, BackgroundColor3 = Color3.fromRGB(236, 72, 140), Size = UDim2.fromScale(0, 1), ZIndex = 22 })
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	-- bouton Passer (grand pour le tactile)
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -16, 0.9, -8)
	skip.Size = UDim2.fromOffset(128, 46)
	skip.BackgroundColor3 = Color3.fromRGB(40, 32, 48)
	skip.BackgroundTransparency = 0.2
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 18
	skip.Text = T("⏭ Skip")
	skip.ZIndex = 30
	skip.Visible = false
	skip.AutoButtonColor = true
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 14)
	skipCorner.Parent = skip
	skip.Parent = screen
	-- carte "Ta maison est prête !"
	local card = frame("Ready", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.05, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(0.7, 0, 0.3, 0), ZIndex = 40, Visible = false })
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(620, 170)
	cardLimit.MinSize = Vector2.new(240, 90)
	cardLimit.Parent = card
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 24)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 150, 200)
	cardStroke.Thickness = 3
	cardStroke.Parent = card
	local cardGrad = Instance.new("UIGradient")
	cardGrad.Color = ColorSequence.new(Color3.fromRGB(255, 250, 236), Color3.fromRGB(255, 222, 240))
	cardGrad.Rotation = 90
	cardGrad.Parent = card
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card
	local readyTitle = Instance.new("TextLabel")
	readyTitle.Name = "Title"
	readyTitle.BackgroundTransparency = 1
	readyTitle.Position = UDim2.new(0, 16, 0, 12)
	readyTitle.Size = UDim2.new(1, -32, 0.55, 0)
	readyTitle.Font = Enum.Font.FredokaOne
	readyTitle.TextScaled = true
	readyTitle.TextColor3 = Color3.fromRGB(236, 72, 140)
	readyTitle.Text = T("🏠 Your house is ready!")
	readyTitle.ZIndex = 41
	readyTitle.Parent = card
	local readySub = Instance.new("TextLabel")
	readySub.Name = "Subtitle"
	readySub.BackgroundTransparency = 1
	readySub.Position = UDim2.new(0, 16, 0.6, 0)
	readySub.Size = UDim2.new(1, -32, 0.3, 0)
	readySub.Font = Enum.Font.GothamBold
	readySub.TextScaled = true
	readySub.TextColor3 = Color3.fromRGB(90, 60, 110)
	readySub.Text = T("Walk in, it's all yours!")
	readySub.ZIndex = 41
	readySub.Parent = card
	screen.Parent = playerGui
	local gui = { Screen = screen, Fade = fade, Top = top, Bottom = bottom, Caption = caption, Phase = phase, Fill = fill, Skip = skip, Card = card, Scale = scale }
	S.Gui = gui
	return gui
end

local function tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local ok = pcall(function()
		TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
	end)
	if not ok then
		for k, v in pairs(props) do
			(object :: any)[k] = v
		end
	end
end

local PHASE_TEXT = {
	Clear = "Clearing the site",
	Foundation = "Pouring the foundations",
	Walls = "Raising the walls",
	Roof = "Laying the roof",
	Openings = "Windows and doors",
	Garden = "Growing the garden",
	Finale = "Finishing touches",
}

----------------------------------------------------------------------
-- Construction animée d'une maison
----------------------------------------------------------------------

local function siteOfPlot(plot: number?): any
	if not plot then
		return nil
	end
	return S.Sites["P" .. plot]
end

local function dropSite(plot: number?)
	local site = siteOfPlot(plot)
	if site then
		site:Destroy()
		S.Sites["P" .. (plot :: number)] = nil
	end
end

local function finishAnim(userId: number, skipped: boolean)
	local anim = S.Anims[userId]
	if anim then
		S.Anims[userId] = nil
		anim:Finish(skipped)
	end
end

local function startBuild(userId: number, house: any, plot: number?, force: boolean?, prepared: any?): any
	finishAnim(userId, true)
	local center = house.HouseCF and house.HouseCF.Position or WorldLayout.Origin()
	local near = (center - camPos()).Magnitude < ANIM_RANGE
	if not near and not force then
		dropSite(plot)
		return nil
	end
	local site = siteOfPlot(plot)
	local crane = nil
	if site then
		crane = site:Clear(true)
		S.Sites["P" .. (plot :: number)] = nil
		if site.Clearing then
			table.insert(S.Clearing, site) -- (son retrait animé continue)
		end
	end
	if prepared and not prepared.Done then
		-- (maison déjà masquée : le moment du propriétaire)
		prepared.Crane = crane
		S.Anims[userId] = prepared
		local ok, err = pcall(prepared.Play, prepared)
		if not ok then
			warn("[HouseConstruction] " .. tostring(err))
			S.Anims[userId] = nil
			prepared:Finish(true)
			return nil
		end
		return prepared
	end
	local name = ""
	pcall(function()
		name = tostring(house.Snapshot and (house.Snapshot.DisplayName or house.Snapshot.Name) or "")
	end)
	local anim = HouseBuildAnim.new(house, {
		Parent = S.Folder,
		Crane = crane,
		Seed = userId % 997,
		Label = if userId ~= LocalPlayer.UserId and name ~= "" then T("🏗️ %s's house is being built!", name) else nil,
		OnDone = function()
			if S.Anims[userId] and S.Anims[userId].Done then
				S.Anims[userId] = nil
			end
		end,
	})
	S.Anims[userId] = anim
	local ok, err = pcall(anim.Play, anim)
	if not ok then
		warn("[HouseConstruction] " .. tostring(err))
		S.Anims[userId] = nil
		anim:Finish(true)
		return nil
	end
	return anim
end

----------------------------------------------------------------------
-- Moment du propriétaire (caméra)
----------------------------------------------------------------------

local function houseView(house: any): (CFrame, Vector3, number)
	local dims = WorldLayout.Dims(house.Size)
	local cf: CFrame = house.HouseCF
	local midX = dims.Left + dims.Width / 2
	local target = (cf * CFrame.new(midX, dims.Height * 0.4, -dims.Depth / 2)).Position
	-- en hauteur, de 3/4 face (au-dessus des chantiers d'en face, ~25° vers le bas)
	local dist = math.max(dims.Width * 0.78, dims.Height * 1.8, 55) + 10
	local view = cf * CFrame.new(midX, dims.Height * 0.8 + 24, dist)
	return view, target, dist
end

local function orbitCF(owner: any, k: number): CFrame
	local house = owner.House
	local view, target, dist = houseView(house)
	local swing = (k - 0.5) * 0.7 -- (radians, de gauche à droite)
	local offset = view.Position - target
	local rotated = CFrame.fromAxisAngle(Vector3.yAxis, swing):VectorToWorldSpace(offset)
	local pos = target + rotated * (1 - 0.08 * math.sin(k * math.pi))
	local _ = dist
	return CFrame.lookAt(pos, target)
end

-- HUD de la ville masqué pendant le moment (opts.Hud : objet TownHud, facultatif)
local function hudHidden(owner: any, hidden: boolean)
	local hud = S.Opts and S.Opts.Hud
	local value: any = hud and hud.Root
	if typeof(value) ~= "Instance" or not value:IsA("GuiObject") then
		return
	end
	local root = value :: GuiObject
	if hidden then
		if owner.HudWas == nil then
			owner.HudWas = root.Visible
			root.Visible = false
		end
	elseif owner.HudWas ~= nil then
		root.Visible = owner.HudWas
		owner.HudWas = nil
	end
end

local function endOwnerMoment(skipped: boolean)
	local owner = S.Owner
	if not owner or owner.State == "Done" then
		return
	end
	owner.State = "Returning"
	local gui = S.Gui
	if gui then
		gui.Caption.Visible = false
		gui.Skip.Visible = false
		gui.Card.Visible = true
		gui.Scale.Scale = 0.2
		tween(gui.Scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local hold = if skipped then 1.3 else 2.3
	task.delay(hold, function()
		if S.Owner ~= owner then
			return
		end
		local cam = camera()
		local root = localRoot()
		local function restore()
			if cam then
				local character = LocalPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				cam.CameraType = owner.CameraType or Enum.CameraType.Custom
				if humanoid then
					cam.CameraSubject = humanoid
				elseif owner.Subject then
					cam.CameraSubject = owner.Subject
				end
				if owner.FOV then
					cam.FieldOfView = owner.FOV
				end
			end
			owner.State = "Done"
			hudHidden(owner, false)
			if gui then
				tween(gui.Top, 0.4, { Position = UDim2.new(0, 0, -0.1, 0) })
				tween(gui.Bottom, 0.4, { Position = UDim2.new(0, 0, 1.02, 0) })
				tween(gui.Scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.5, function()
					if S.Owner == owner or S.Owner == nil then
						destroyGui()
					end
				end)
			end
			local toast = S.Opts and S.Opts.Toast
			if toast then
				pcall(toast, T("🏠 Your house is ready! Walk in, it's all yours"), Color3.fromRGB(236, 72, 140))
			end
		end
		if cam and root then
			local back = CFrame.lookAt((root.CFrame * CFrame.new(0, 6, 15)).Position, root.Position + Vector3.new(0, 2, 0))
			if (cam.CFrame.Position - back.Position).Magnitude > 400 and gui then
				tween(gui.Fade, 0.3, { BackgroundTransparency = 0 })
				task.delay(0.32, function()
					cam.CFrame = back
					restore()
					tween(gui.Fade, 0.4, { BackgroundTransparency = 1 })
				end)
			else
				owner.Return = { From = cam.CFrame, To = back, Start = os.clock(), Done = restore }
			end
		else
			restore()
		end
	end)
end

local function startOwnerMoment()
	local owner = S.Owner
	if not owner or owner.State ~= "Pending" then
		return
	end
	ownerSeen = true
	local house = owner.House
	if house.Alive == false or not house.Model.Parent then
		owner.State = "Done"
		if owner.Anim then
			owner.Anim:Finish(true)
		end
		return
	end
	local cam = camera()
	if not cam then
		owner.State = "Building"
		owner.Anim = startBuild(LocalPlayer.UserId, house, owner.Plot, true, owner.Anim) or owner.Anim
		return
	end
	owner.State = "Moving"
	owner.CameraType = cam.CameraType
	owner.Subject = cam.CameraSubject
	owner.FOV = cam.FieldOfView
	local gui = makeGui()
	hudHidden(owner, true)
	if gui then
		tween(gui.Top, 0.5, { Position = UDim2.new(0, 0, 0, 0) })
		tween(gui.Bottom, 0.5, { Position = UDim2.new(0, 0, 1 - 0.085, 0) })
		gui.Skip.Visible = true
		gui.Caption.Visible = true
		gui.Phase.Text = T(PHASE_TEXT.Clear)
		gui.Fill.Size = UDim2.fromScale(0, 1)
		gui.Skip.Activated:Connect(function()
			local current = S.Owner
			if current and (current.State == "Moving" or current.State == "Building") then
				if current.Anim and not current.Anim.Playing then
					-- (pas encore commencée : le chantier disparaît, la maison est là)
					dropSite(current.Plot)
				end
				if current.Anim then
					current.Anim:Finish(true)
				end
				endOwnerMoment(true)
			end
		end)
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 50
	local first = orbitCF(owner, 0)
	local far = (cam.CFrame.Position - first.Position).Magnitude > 400
	if far and gui then
		tween(gui.Fade, 0.35, { BackgroundTransparency = 0 })
		task.delay(0.37, function()
			if S.Owner ~= owner or (owner :: any).State ~= "Moving" then
				return -- (passé ou quitté pendant le fondu)
			end
			cam.CFrame = first
			tween(gui.Fade, 0.45, { BackgroundTransparency = 1 })
			owner.Move = nil
			owner.State = "Building"
			owner.BuildStart = os.clock()
			owner.Anim = startBuild(LocalPlayer.UserId, house, owner.Plot, true, owner.Anim) or owner.Anim
		end)
	else
		owner.Move = { From = cam.CFrame, Start = os.clock(), Time = 1.4 }
	end
end

local function stepOwner(dt: number)
	local owner = S.Owner
	if not owner then
		return
	end
	local cam = camera()
	if owner.State == "Pending" then
		-- secours : pas d'appel ArrivalDone (ou survol déjà fini)
		local waited = os.clock() - S.StartedAt
		if owner.Arrived or waited > OWNER_FALLBACK then
			local ready = cam ~= nil and cam.CameraType ~= Enum.CameraType.Scriptable and localRoot() ~= nil
			if ready or waited > OWNER_FALLBACK + 10 then
				startOwnerMoment()
			end
		end
	elseif owner.State == "Moving" and owner.Move and cam then
		local m = owner.Move
		local k = math.clamp((os.clock() - m.Start) / m.Time, 0, 1)
		cam.CFrame = m.From:Lerp(orbitCF(owner, 0), Kit.Smooth(k))
		if k >= 1 then
			owner.Move = nil
			owner.State = "Building"
			owner.BuildStart = os.clock()
			owner.Anim = startBuild(LocalPlayer.UserId, owner.House, owner.Plot, true, owner.Anim) or owner.Anim
		end
	elseif owner.State == "Building" then
		local anim = owner.Anim
		local k = if anim then anim:Progress() else 1
		if cam then
			cam.CFrame = orbitCF(owner, k)
		end
		local gui = S.Gui
		if gui and anim then
			gui.Fill.Size = UDim2.fromScale(k, 1)
			gui.Phase.Text = T(PHASE_TEXT[anim:PhaseName()] or PHASE_TEXT.Finale)
		end
		if not anim or anim.Done then
			endOwnerMoment(false)
		end
	elseif owner.State == "Returning" then
		local r = owner.Return
		if r and cam then
			local k = math.clamp((os.clock() - r.Start) / 1.3, 0, 1)
			cam.CFrame = r.From:Lerp(r.To, Kit.Smooth(k))
			if k >= 1 then
				owner.Return = nil
				r.Done()
			end
		elseif cam and owner.Anim and owner.Anim.Done then
			-- (pendant la carte : la caméra finit sa rotation doucement)
			cam.CFrame = orbitCF(owner, 1)
		end
	end
	local _ = dt
end

----------------------------------------------------------------------
-- Petites animations : portillons, drapeaux des boîtes aux lettres
----------------------------------------------------------------------

local function addMicro(part: BasePart)
	if S.MicroParts[part] then
		return
	end
	local kind = part:GetAttribute("Micro")
	local entry: any = nil
	if kind == "Swing" then
		local hinge = part:GetAttribute("HingeCF")
		local angle = tonumber(part:GetAttribute("OpenAngle")) or 90
		if typeof(hinge) == "CFrame" then
			entry = {
				Part = part,
				Hinge = part.CFrame * hinge:Inverse(),
				Local = hinge,
				Open = CFrame.Angles(0, math.rad(angle), 0),
				Closed = CFrame.identity,
				Range = tonumber(part:GetAttribute("Range")) or 7,
				Time = 0.55,
			}
		end
	elseif part.Name == "MailFlag" then
		-- drapeau : charnière en bas, au dos ; baissé (à plat) au repos, levé quand on passe
		local size = part.Size
		local hingeLocal = CFrame.new(0, -size.Y / 2 + 0.05, size.Z / 2 - 0.05)
		entry = {
			Part = part,
			Hinge = part.CFrame * hingeLocal,
			Local = hingeLocal:Inverse(),
			Open = CFrame.identity,
			Closed = CFrame.Angles(math.rad(-88), 0, 0),
			Range = 6.5,
			Time = 0.5,
			Rest = part.CFrame,
		}
	end
	if entry then
		S.MicroParts[part] = true
		entry.K = 0
		entry.Target = 0
		entry.Applied = -1
		table.insert(S.Micro, entry)
	end
end

local function watchMicro(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "MailFlag" or d:GetAttribute("Micro") ~= nil) then
			addMicro(d)
		end
	end
	table.insert(S.MicroConns, root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			task.defer(function()
				if S.Active and d.Parent and (d.Name == "MailFlag" or d:GetAttribute("Micro") ~= nil) then
					addMicro(d)
				end
			end)
		end
	end))
end

local function constructing(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Constructing") == true then
			return true
		end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return false
end

local microClock = 0
local microRoots: { Vector3 } = {}
local function stepMicro(dt: number)
	microClock += dt
	if microClock >= 0.15 then
		microClock = 0
		table.clear(microRoots)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				table.insert(microRoots, root.Position)
			end
		end
		local pos = camPos()
		local me = localRoot()
		local mine = if me then me.Position else pos
		local keep = {}
		for _, e in ipairs(S.Micro) do
			local part: BasePart = e.Part
			if part.Parent then
				table.insert(keep, e)
				local hinge = e.Hinge.Position
				e.Near = (hinge - pos).Magnitude < MICRO_RANGE or (hinge - mine).Magnitude < MICRO_RANGE
				local want = 0
				if e.Near and not constructing(part) then
					for _, p in ipairs(microRoots) do
						if (p - hinge).Magnitude < e.Range then
							want = 1
							break
						end
					end
				end
				e.Target = want
			else
				S.MicroParts[part] = nil
			end
		end
		S.Micro = keep
	end
	local parts, frames = {}, {}
	for _, e in ipairs(S.Micro) do
		if e.Near then
			local step = dt / e.Time
			if e.K < e.Target then
				e.K = math.min(e.Target, e.K + step)
			elseif e.K > e.Target then
				e.K = math.max(e.Target, e.K - step)
			end
			if e.K ~= e.Applied and not constructing(e.Part) then
				e.Applied = e.K
				-- ouverture avec léger dépassement, fermeture douce
				local k = if e.Target == 1 then math.min(1.06, 1 + 2.4 * (e.K - 1) ^ 3 + 1.4 * (e.K - 1) ^ 2) else Kit.Smooth(e.K)
				k = math.clamp(k, 0, 1.06)
				local rot = e.Closed:Lerp(e.Open, k)
				table.insert(parts, e.Part)
				table.insert(frames, e.Hinge * rot * e.Local)
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function HouseConstruction.Start(opts: any)
	if S.Active then
		HouseConstruction.Stop()
	end
	S.Active = true
	S.Opts = opts or {}
	S.StartedAt = os.clock()
	S.SyncClock = SYNC_EVERY
	S.DS = detailScale()
	table.clear(S.Known)
	table.clear(S.Records)
	local folder = Instance.new("Folder")
	folder.Name = "Construction"
	folder.Parent = (S.Opts.Folder :: Instance?) or workspace
	S.Folder = folder
	-- chargement : les maisons construites avant la fin de l'arrivée
	-- (ArrivalDone, ou LOAD_WINDOW s) apparaissent sans animation
	S.Loading = true
	S.Known[LocalPlayer.UserId] = true
	spotCache = nil
	pcall(function()
		local town = workspace:FindFirstChild("DopamineTown")
		local plots = town and town:FindFirstChild("Plots")
		if plots then
			watchMicro(plots)
		end
	end)
end

-- Après la création (HouseBuilder.new + jardin) ou la mise à jour d'une maison
function HouseConstruction.Observe(userId: number, house: any, snapshot: any)
	if not S.Active or type(house) ~= "table" or not house.Model then
		return
	end
	local plot = type(snapshot) == "table" and tonumber(snapshot.Plot) or nil
	local rec = S.Records[userId]
	if rec and rec.House == house then
		rec.Plot = plot or rec.Plot
		if house.Size ~= rec.Size then
			-- 🎨 nouveau style de maison : on la reconstruit sous nos yeux
			rec.Size = house.Size
			local owner = S.Owner
			if owner and owner.House == house and owner.State == "Pending" then
				owner.Anim:Finish(true)
				owner.Anim = HouseBuildAnim.new(house, { Parent = S.Folder, Seed = userId % 997 })
				if not pcall(owner.Anim.Prepare, owner.Anim) then
					owner.Anim:Finish(true)
				end
				ownerSize = house.Size
			elseif not (owner and owner.House == house and owner.State ~= "Done") then
				startBuild(userId, house, plot)
			end
		end
		return
	end
	local hadHouse = rec ~= nil
	S.Records[userId] = { House = house, Size = house.Size, Plot = plot }
	pcall(watchMicro, house.Model)
	local mine = userId == LocalPlayer.UserId
	if mine and ownerSeen and (plot ~= ownerPlot or house.Size ~= ownerSize) then
		-- (nouveau style / nouveau quartier depuis la dernière fois : on la
		-- reconstruit, avec le moment caméra)
		ownerSeen = false
	end
	if mine then
		ownerPlot, ownerSize = plot, house.Size
	end
	if mine and not ownerSeen then
		-- ta maison : chantier jusqu'au moment "ta maison se construit"
		local anim = HouseBuildAnim.new(house, { Parent = S.Folder, Seed = userId % 997 })
		local okPrep, errPrep = pcall(anim.Prepare, anim)
		if not okPrep then
			-- (jamais de maison cachée pour de bon)
			warn("[HouseConstruction] " .. tostring(errPrep))
			anim:Finish(true)
			dropSite(plot)
			return
		end
		S.Owner = { State = "Pending", House = house, Plot = plot, Anim = anim, Arrived = S.Owner ~= nil and S.Owner.Arrived or false }
		return
	end
	if (S.Loading or S.Known[userId]) and not hadHouse then
		-- (déjà là à notre arrivée : pas d'animation)
		S.Known[userId] = true
		dropSite(plot)
		return
	end
	-- 🆕 un joueur arrive / déménage : construction animée
	startBuild(userId, house, plot)
end

-- Fin du survol d'arrivée (ou arrivée directe) : moment du propriétaire
function HouseConstruction.ArrivalDone()
	S.Loading = false
	local owner = S.Owner
	if owner then
		owner.Arrived = true
	else
		S.Owner = { State = "None", Arrived = true }
	end
end

function HouseConstruction.Step(dt: number)
	if not S.Active then
		return
	end
	local now = workspace:GetServerTimeNow()
	if S.Loading and os.clock() - S.StartedAt > LOAD_WINDOW then
		S.Loading = false
	end
	S.SyncClock += dt
	if S.SyncClock >= SYNC_EVERY then
		S.SyncClock = 0
		S.DS = detailScale()
		local ok, err = pcall(syncSites)
		if not ok then
			warn("[HouseConstruction] chantiers : " .. tostring(err))
		end
	end
	local okLevels, errLevels = pcall(stepLevels)
	if not okLevels then
		warn("[HouseConstruction] niveaux : " .. tostring(errLevels))
	end
	local pos = camPos()
	for key, site in pairs(S.Sites) do
		if site.Done then
			S.Sites[key] = nil
		elseif site.Level > 0 or site.Clearing then
			local ok, err = pcall(site.Step, site, now, dt, pos)
			if not ok then
				warn("[HouseConstruction] chantier " .. key .. " : " .. tostring(err))
				site:Destroy()
				S.Sites[key] = nil
			end
		end
	end
	-- chantiers en cours de retrait (hors de la table) : leur animation continue
	if #S.Clearing > 0 then
		local keep = {}
		for _, site in ipairs(S.Clearing) do
			if not site.Done then
				pcall(site.Step, site, now, dt, pos)
				if not site.Done then
					table.insert(keep, site)
				end
			end
		end
		S.Clearing = keep
	end
	local root = localRoot()
	for userId, anim in pairs(S.Anims) do
		if anim.Done then
			S.Anims[userId] = nil
		else
			-- dans une maison en construction : on termine tout de suite
			local house = anim.House
			if root and house and type(house.RoomAt) == "function" and userId ~= LocalPlayer.UserId then
				local okRoom, slot = pcall(house.RoomAt, house, root.Position)
				if okRoom and slot ~= nil then
					anim:Finish(true)
				end
			end
			local ok, err = pcall(anim.Step, anim, dt)
			if not ok then
				warn("[HouseConstruction] animation : " .. tostring(err))
				anim:Finish(true)
			end
		end
	end
	local owner = S.Owner
	if owner and owner.Anim and owner.State ~= "Done" and not S.Anims[LocalPlayer.UserId] and owner.Anim.Playing then
		pcall(owner.Anim.Step, owner.Anim, dt)
	end
	local okOwner, errOwner = pcall(stepOwner, dt)
	if not okOwner then
		warn("[HouseConstruction] moment : " .. tostring(errOwner))
	end
	pcall(stepMicro, dt)
end

function HouseConstruction.Stop()
	if not S.Active then
		return
	end
	S.Active = false
	for userId in pairs(S.Anims) do
		finishAnim(userId, true)
	end
	local owner = S.Owner
	if owner then
		if owner.Anim and not owner.Anim.Done then
			owner.Anim:Finish(true)
		end
		if owner.State == "Moving" or owner.State == "Building" or owner.State == "Returning" then
			local cam = camera()
			if cam then
				cam.CameraType = owner.CameraType or Enum.CameraType.Custom
				if owner.Subject then
					cam.CameraSubject = owner.Subject
				end
				if owner.FOV then
					cam.FieldOfView = owner.FOV
				end
			end
		end
		hudHidden(owner, false)
	end
	S.Owner = nil
	destroyGui()
	for _, site in pairs(S.Sites) do
		site:Destroy()
	end
	table.clear(S.Sites)
	for _, site in ipairs(S.Clearing) do
		site:Destroy()
	end
	S.Clearing = {}
	for _, c in ipairs(S.MicroConns) do
		c:Disconnect()
	end
	table.clear(S.MicroConns)
	-- drapeaux des boîtes aux lettres (pièces du serveur) : remis comme avant
	for _, e in ipairs(S.Micro) do
		if e.Rest and e.Part.Parent then
			e.Part.CFrame = e.Rest
		end
	end
	table.clear(S.Micro)
	table.clear(S.MicroParts)
	if S.Folder then
		S.Folder:Destroy()
		S.Folder = nil
	end
	table.clear(S.Records)
	S.Opts = nil
end

-- Mesures (rapport / tests)
function HouseConstruction.Stats(): { [string]: number }
	local sites, full, lite, parts = 0, 0, 0, 0
	for _, site in pairs(S.Sites) do
		sites += 1
		if site.Level == 2 then
			full += 1
		elseif site.Level == 1 then
			lite += 1
		end
		parts += ConstructionSite.CountParts(site.Folder)
	end
	local anims = 0
	for _ in pairs(S.Anims) do
		anims += 1
	end
	return { Sites = sites, Full = full, Lite = lite, Parts = parts, Anims = anims, Micro = #S.Micro }
end

-- (tests) état interne
HouseConstruction._state = S
function HouseConstruction._resetSession()
	ownerSeen = false
end

return HouseConstruction
