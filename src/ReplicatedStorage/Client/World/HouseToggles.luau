--[[
	HouseToggles (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseToggles

	🚶 Dopamine Town (v9.8, HOUSE98) : ce qui s'allume, s'éteint, s'ouvre et
	se ferme dans une pièce de la maison 3D :
	  - 🪟 RIDEAUX d'une fenêtre (v9.9 HOUSE99 : refaits) : tringle ronde à
	    anneaux, voilages translucides + doubles rideaux jusqu'au sol en 5
	    plis (alternés en relief et en teinte), drapés sur le côté par une
	    embrasse quand ils sont ouverts ; animation douce (Sine, plis décalés) ;
	  - 💡 INTERRUPTEUR mural : plaque + bascule qui pivote (haut = allumé) ;
	  - groupe de LUMIÈRES d'une pièce (plafonnier + lampes posées) : fondu de
	    la luminosité des vraies lumières, ampoules "Neon" qui s'éteignent
	    (matière + couleur gardées pour les rallumer).
	(v11 HOUSE11) un rideau PAR FENÊTRE, vrais plis en accordéon (le tissu ne
	s'étire plus : l'angle des plis change), un anneau par pli, voilages
	plissés sur une 2e tringle, balancement amorti du bas à l'arrêt ;
	interrupteur à PLUSIEURS bascules (une par lumière : switch:SetGang).
	Tout est décor (ancré, sans collision, sans ombre) ; aucune interface ici :
	HouseBuilder pose les invites (ProximityPrompt) et sauvegarde l'état.

	API :
	  HouseToggles.Curtains(parent, cf, width, height, color, rodColor, open, opts?) -> Curtain
	      opts.Drop = distance du centre de la fenêtre à l'ourlet (rideaux jusqu'au sol)
	      cf = centre de la fenêtre sur la face INTÉRIEURE du mur, RightVector
	      le long de la fenêtre, LookVector = de la pièce VERS le mur
	  curtain:Set(open, animate)
	  HouseToggles.Switch(parent, cf, on, gangs?) -> Switch   (cf : sur le mur, LookVector vers le mur)
	  switch:Set(on, animate) ; switch:SetGang(i, on, animate)
	  HouseToggles.Lights() -> Lights ; lights:Add(light) ; lights:AddGlow(part)
	  lights:Collect(model, onlyLamps) ; lights:Set(on, animate)
]]

local TweenService = game:GetService("TweenService")

local HouseToggles = {}

local M = Enum.Material
local CURTAIN_TIME = 1.15
local SWITCH_TIME = 0.12
local FADE_TIME = 0.35

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local ok = pcall(function()
		TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
	end)
	if not ok then
		for key, value in pairs(goal) do
			(instance :: any)[key] = value
		end
	end
end

local function decor(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

----------------------------------------------------------------------
-- 🪟 Rideaux (v11 HOUSE11 : un rideau PAR FENÊTRE, tissu réaliste)
----------------------------------------------------------------------
-- Une fenêtre = tringle double (embouts à boule, 2 supports) :
--   - DOUBLES RIDEAUX (devant) : 2 pans de PLIS EN ACCORDÉON. Le tissu ne
--     s'étire jamais : chaque pli garde sa largeur de tissu, c'est son ANGLE
--     qui change (fermé : plis ouverts ~28°, le pan couvre la moitié de la
--     fenêtre ; ouvert : plis serrés ~75°, le pan se tasse sur le côté). Un
--     ANNEAU par pli glisse sur la tringle (le bord d'attaque mène, les
--     autres suivent, décalés) ; ouverts, les pans sont serrés par une
--     EMBRASSE puis s'évasent jusqu'à l'ourlet ;
--   - VOILAGES (derrière, translucides) : 2 pans plissés plus fins, sur une
--     2e tringle, jusqu'à l'appui ; ils suivent les doubles rideaux, en
--     retard ;
--   - à l'arrêt, le bas des plis BALANCE un peu (oscillation amortie).
-- Tout en CFrame + Size (TweenService) ; le tissu garde une teinte moyenne.

export type Curtain = {
	Parts: { BasePart },
	Open: { { CFrame: CFrame, Size: Vector3, T: number? } },
	Closed: { { CFrame: CFrame, Size: Vector3, T: number? } },
	Delays: { number },
	Sway: { number }, -- longueur (studs) des plis qui balancent (0 = ne balance pas)
	IsOpen: boolean,
	Anchor: BasePart,
	Strips: { BasePart }, -- (compat v9.8 : les plis des doubles rideaux)
	Rings: { BasePart },
	Sheers: { BasePart },
	Axis: Vector3, -- axe de balancement (le long de la fenêtre)
	Generation: number,
	Set: (self: Curtain, open: boolean, animate: boolean) -> (),
}

export type CurtainOptions = {
	Drop: number?, -- distance du centre de la fenêtre à l'ourlet (défaut : jusque sous l'appui)
}

local Curtain = {}
Curtain.__index = Curtain

local FOLD_COUNT = 6 -- plis par pan de double rideau
local SHEER_FOLDS = 4 -- plis par pan de voilage
local CLOSED_ANGLE = math.rad(28) -- angle des plis, rideau fermé
local SHEER_CLOSED_ANGLE = math.rad(14)
local SWAY_ANGLE = math.rad(3.2)

-- CFrame tourné de `angle` autour de `axis` passant par `pivot` (monde)
local function swing(cf: CFrame, pivot: Vector3, axis: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot) * cf
end

-- Balancement amorti des plis (après l'arrivée) : +a, -0,4a, 0
local function startSway(self: Curtain, open: boolean, generation: number)
	local goals = if open then self.Open else self.Closed
	local stages = { { 1, 0.32, Enum.EasingDirection.Out }, { -0.4, 0.5, Enum.EasingDirection.InOut }, { 0, 0.55, Enum.EasingDirection.InOut } }
	local function stage(index: number)
		if self.Generation ~= generation or index > #stages then
			return
		end
		local spec = stages[index]
		for i, part in ipairs(self.Parts) do
			local length = self.Sway[i]
			if length and length > 0 and part.Parent then
				local goal = goals[i].CFrame
				local pivot = (goal * CFrame.new(0, length / 2, 0)).Position
				local target = if spec[1] == 0 then goal else swing(goal, pivot, self.Axis, SWAY_ANGLE * spec[1])
				pcall(function()
					TweenService:Create(part, TweenInfo.new(spec[2], Enum.EasingStyle.Sine, spec[3]), { CFrame = target }):Play()
				end)
			end
		end
		task.delay(spec[2], stage, index + 1)
	end
	stage(1)
end

function Curtain.Set(self: Curtain, open: boolean, animate: boolean)
	self.IsOpen = open
	self.Generation += 1
	local generation = self.Generation
	local goals = open and self.Open or self.Closed
	local last = 0
	for index, part in ipairs(self.Parts) do
		local goal = goals[index]
		if part.Parent then
			if animate then
				local props: { [string]: any } = { CFrame = goal.CFrame, Size = goal.Size }
				if goal.T ~= nil then
					props.Transparency = goal.T
				end
				local delayTime = self.Delays[index] or 0
				last = math.max(last, delayTime)
				local ok = pcall(function()
					TweenService:Create(part, TweenInfo.new(CURTAIN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, delayTime), props):Play()
				end)
				if not ok then
					part.CFrame = goal.CFrame
					part.Size = goal.Size
					if goal.T ~= nil then
						part.Transparency = goal.T
					end
				end
			else
				part.CFrame = goal.CFrame
				part.Size = goal.Size
				if goal.T ~= nil then
					part.Transparency = goal.T
				end
			end
		end
	end
	if animate then
		task.delay(CURTAIN_TIME + last, function()
			if self.Generation == generation then
				startSway(self, open, generation)
			end
		end)
	end
end

-- Teinte du tissu : jamais trop sombre ni criarde (tissu éclairé par la pièce)
local function fabricTone(color: Color3): Color3
	local h, sat, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(sat, 0.62), math.clamp(v, 0.62, 0.97))
end

function HouseToggles.Curtains(parent: Instance, cf: CFrame, width: number, height: number, color: Color3, rodColor: Color3, open: boolean,
	options: CurtainOptions?): Curtain
	local w, h = math.max(1, width), math.max(1, height)
	local opts: CurtainOptions = options or {}
	local base = fabricTone(color)
	local shade = base:Lerp(Color3.new(0, 0, 0), 0.14)
	local lit = base:Lerp(Color3.new(1, 1, 1), 0.08)
	-- (repère de `cf` : +X le long de la fenêtre, +Z = vers la pièce)
	-- plans : voilage à 0,78 du mur (devant l'appui intérieur, 0,58), doubles
	-- rideaux à 1,3 (leurs plis les plus serrés restent devant le voilage)
	local rodOut = 1.3
	local sheerOut = 0.78
	local rodY = h / 2 + 0.75
	local sheerRodY = rodY - 0.18
	local side = 2.2 -- les rideaux ouverts se rangent à côté de la fenêtre
	local rodLength = w + 2 * (side + 0.25)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local rod = decor(parent, "CurtainRod", Vector3.new(rodLength, 0.16, 0.16), at(0, rodY, rodOut), rodColor, M.Metal, Enum.PartType.Cylinder)
	rod.Reflectance = 0.12
	decor(parent, "SheerRod", Vector3.new(w + 2.3, 0.08, 0.08), at(0, sheerRodY, sheerOut), rodColor:Lerp(Color3.new(1, 1, 1), 0.3), M.Metal, Enum.PartType.Cylinder)
	for _, s in ipairs({ -1, 1 }) do
		decor(parent, "CurtainFinial", Vector3.new(0.38, 0.38, 0.38), at(s * (rodLength / 2 + 0.12), rodY, rodOut), rodColor, M.Metal, Enum.PartType.Ball)
		-- support (du mur aux deux tringles)
		decor(parent, "CurtainBracket", Vector3.new(0.12, 0.14, rodOut + 0.05), at(s * (rodLength / 2 - 0.45), rodY + 0.04, rodOut / 2), rodColor, M.Metal)
		decor(parent, "SheerBracket", Vector3.new(0.1, 0.1, sheerOut + 0.04), at(s * (w / 2 + 1.0), sheerRodY + 0.03, sheerOut / 2), rodColor, M.Metal)
	end
	local parts: { BasePart } = {}
	local openGoals, closedGoals = {}, {}
	local delays: { number } = {}
	local sway: { number } = {}
	local folds: { BasePart } = {}
	local rings: { BasePart } = {}
	local sheers: { BasePart } = {}
	local function add(part: BasePart, openGoal: any, closedGoal: any, delayTime: number, swayLength: number?)
		table.insert(parts, part)
		table.insert(openGoals, openGoal)
		table.insert(closedGoals, closedGoal)
		table.insert(delays, delayTime)
		table.insert(sway, swayLength or 0)
	end
	-- un pli : du point a (haut) au point b (bas), dans le plan de la fenêtre ;
	-- `fabric` = largeur du tissu, `span` = largeur occupée -> angle du pli
	local function pleat(ax: number, ay: number, bx: number, by: number, z: number, fabric: number, span: number, sign: number,
		thick: number): ({ CFrame: CFrame, Size: Vector3 }, number)
		local dx, dy = bx - ax, by - ay
		local length = math.max(0.1, math.sqrt(dx * dx + dy * dy))
		local roll = math.atan2(dx, -dy)
		local angle = math.acos(math.clamp(span / fabric, 0.12, 1))
		return {
			CFrame = at((ax + bx) / 2, (ay + by) / 2, z) * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, sign * angle, 0),
			Size = Vector3.new(fabric + 0.03, length, thick),
		}, length
	end
	local top = rodY - 0.24
	local bottom = -(opts.Drop or (h / 2 + 0.8)) + 0.1
	local tieY = bottom + 0.42 * (top - bottom)
	local F = FOLD_COUNT
	for panel, s in ipairs({ -1, 1 }) do
		local outer = s * (w / 2 + side)
		local inner = -s * 0.1 -- fermés : se croisent de 0,1 au milieu
		local closedSpan = math.abs(outer - inner)
		local pc = closedSpan / F
		local fabric = pc / math.cos(CLOSED_ANGLE) -- largeur de tissu d'un pli
		-- ouverts : tas de 1,5 en haut, 0,62 à l'embrasse, 1,6 en bas
		local stackTop, stackTie, stackBottom = 1.5, 0.62, 1.6
		local tieCenter = outer - s * 0.8
		local zPanel = rodOut + (if panel == 2 then 0.05 else 0) -- (pas de faces confondues au milieu)
		for f = 1, F do
			local sign = s * (if f % 2 == 0 then 1 else -1)
			local tone = if f % 2 == 0 then shade elseif f == F then lit else base
			-- fermés : tombés droits
			local cx = outer - s * (f - 0.5) * pc
			local closedUp, upLen = pleat(cx, top, cx, tieY, zPanel, fabric, pc, sign, 0.07)
			local closedLow, lowLen = pleat(cx, tieY, cx, bottom, zPanel, fabric, pc, sign, 0.07)
			-- ouverts : haut tassé sous la tringle, embrasse, bas évasé
			local xTop = outer - s * (f - 0.5) * stackTop / F
			local xTie = tieCenter + s * stackTie / 2 - s * (f - 0.5) * stackTie / F
			local xBot = outer + s * 0.05 - s * (f - 0.5) * stackBottom / F
			local openUp = pleat(xTop, top, xTie, tieY, zPanel, fabric, (stackTop + stackTie) / (2 * F), sign, 0.07)
			local openLow = pleat(xTie, tieY, xBot, bottom, zPanel, fabric, (stackTie + stackBottom) / (2 * F), sign, 0.07)
			for k, pair in ipairs({ { openUp, closedUp, upLen }, { openLow, closedLow, lowLen } }) do
				local part = decor(parent, "Curtain", pair[2].Size, pair[2].CFrame, tone, M.Fabric)
				table.insert(folds, part)
				-- (le pli du bord mène le mouvement, les autres suivent ; le bas balance)
				add(part, pair[1], pair[2], (F - f) * 0.035 + (k - 1) * 0.02, if k == 2 then lowLen else 0)
			end
		end
		-- anneaux : un par pli (+ le bord), glissent sur la tringle
		for r = 0, F do
			local xOpen = outer - s * (0.1 + r * (stackTop - 0.2) / F)
			local xClosed = outer - s * (0.1 + r * (closedSpan - 0.2) / F)
			local ring = decor(parent, "CurtainRing", Vector3.new(0.07, 0.32, 0.32), at(xClosed, rodY, rodOut), rodColor, M.Metal, Enum.PartType.Cylinder)
			table.insert(rings, ring)
			add(ring, { CFrame = at(xOpen, rodY, rodOut), Size = ring.Size }, { CFrame = ring.CFrame, Size = ring.Size }, (F - r) * 0.035)
		end
		-- embrasse : visible quand ils sont ouverts (entoure le tas de plis)
		local depth = fabric * math.sin(math.acos(math.clamp(stackTie / F / fabric, 0.12, 1))) + 0.22
		local band = decor(parent, "CurtainTieBack", Vector3.new(stackTie + 0.3, 0.26, depth), at(tieCenter, tieY, zPanel), base:Lerp(rodColor, 0.5), M.Fabric)
		add(band, { CFrame = band.CFrame, Size = band.Size, T = 0 }, { CFrame = band.CFrame, Size = band.Size, T = 1 }, 0)
		-- voilage : plis fins, translucides, jusqu'à l'appui ; suit en retard
		local sOuter = s * (w / 2 + 0.85) -- (ouvert : le tas de voilage dégage la vitre)
		local sInner = -s * 0.06
		local sSpan = math.abs(sOuter - sInner)
		local sp = sSpan / SHEER_FOLDS
		local sFabric = sp / math.cos(SHEER_CLOSED_ANGLE)
		local sTop, sBottom = sheerRodY - 0.1, -h / 2 + 0.12
		local zSheer = sheerOut + (if panel == 2 then 0.04 else 0)
		local sStack = 0.9
		for f = 1, SHEER_FOLDS do
			local sign = s * (if f % 2 == 0 then 1 else -1)
			local cxClosed = sOuter - s * (f - 0.5) * sp
			local cxOpen = sOuter - s * (f - 0.5) * sStack / SHEER_FOLDS
			local closedGoal, len = pleat(cxClosed, sTop, cxClosed, sBottom, zSheer, sFabric, sp, sign, 0.04)
			local openGoal = pleat(cxOpen, sTop, cxOpen, sBottom, zSheer, sFabric, sStack / SHEER_FOLDS, sign, 0.04)
			local sheer = decor(parent, "CurtainSheer", closedGoal.Size, closedGoal.CFrame, Color3.fromRGB(252, 250, 246), M.Fabric)
			sheer.Transparency = 0.6
			table.insert(sheers, sheer)
			add(sheer, openGoal, closedGoal, 0.14 + (SHEER_FOLDS - f) * 0.04, len)
		end
	end
	-- point d'accroche de l'invite (milieu de la fenêtre, dans la pièce)
	local anchor = decor(parent, "CurtainPrompt", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 0, 2.2), color, M.SmoothPlastic)
	anchor.Transparency = 1
	local self = setmetatable({
		Parts = parts,
		Open = openGoals,
		Closed = closedGoals,
		Delays = delays,
		Sway = sway,
		IsOpen = open,
		Anchor = anchor,
		Strips = folds,
		Rings = rings,
		Sheers = sheers,
		Axis = cf.RightVector,
		Generation = 0,
	}, Curtain) :: any
	self:Set(open, false)
	return self
end

----------------------------------------------------------------------
-- 💡 Interrupteur
----------------------------------------------------------------------

export type Switch = {
	Plate: BasePart,
	Rocker: BasePart, -- (compat : la 1re bascule)
	Rockers: { BasePart },
	Leds: { BasePart },
	Bases: { CFrame },
	Base: CFrame,
	IsOn: boolean,
	States: { boolean },
	Set: (self: Switch, on: boolean, animate: boolean) -> (),
	SetGang: (self: Switch, gang: number, on: boolean, animate: boolean) -> (),
}

local Switch = {}
Switch.__index = Switch

local TILT = math.rad(14)
local GANG_PITCH = 0.42 -- (v11) écart entre deux bascules d'une plaque multiple

-- (v11 HOUSE11) une bascule de la plaque (1 = la 1re, à gauche)
function Switch.SetGang(self: Switch, gang: number, on: boolean, animate: boolean)
	local rocker = self.Rockers[gang]
	local base = self.Bases[gang]
	if not rocker or not base then
		return
	end
	self.States[gang] = on
	if gang == 1 then
		self.IsOn = on
	end
	-- bascule : haut enfoncé = allumé (on appuie en haut)
	local goal = base * CFrame.Angles(if on then -TILT else TILT, 0, 0)
	if animate then
		tween(rocker, SWITCH_TIME, { CFrame = goal }, Enum.EasingStyle.Quad)
	else
		rocker.CFrame = goal
	end
	local led = self.Leds[gang]
	if led then
		led.Color = if on then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(120, 200, 255)
	end
end

function Switch.Set(self: Switch, on: boolean, animate: boolean)
	self:SetGang(1, on, animate)
end

-- `gangs` (v11) : nombre de bascules (une par lumière ; 1 à 4)
function HouseToggles.Switch(parent: Instance, cf: CFrame, on: boolean, gangs: number?): Switch
	local n = math.clamp(math.floor(gangs or 1), 1, 4)
	-- (repère de `cf` : +Z = vers la pièce ; la plaque dépasse du mur de 0,01..0,09)
	local plate = decor(parent, "SwitchPlate", Vector3.new(0.62 + (n - 1) * GANG_PITCH, 0.95, 0.08), cf * CFrame.new(0, 0, 0.05), Color3.fromRGB(252, 248, 244),
		M.SmoothPlastic)
	plate.CanQuery = true -- (clic / invite)
	local rockers, leds, bases = {}, {}, {}
	for gang = 1, n do
		local x = (gang - (n + 1) / 2) * GANG_PITCH
		local rocker = decor(parent, "SwitchRocker", Vector3.new(0.3, 0.44, 0.12), cf * CFrame.new(x, 0, 0.12), Color3.fromRGB(255, 255, 255), M.SmoothPlastic)
		-- petit voyant (repère dans le noir), sous la bascule
		local led = decor(plate, "Led", Vector3.new(0.1, 0.06, 0.03), cf * CFrame.new(x, -0.36, 0.1), Color3.fromRGB(255, 214, 140), M.SmoothPlastic)
		table.insert(rockers, rocker)
		table.insert(leds, led)
		table.insert(bases, cf * CFrame.new(x, 0, 0.12))
	end
	local self = setmetatable({
		Plate = plate,
		Rocker = rockers[1],
		Rockers = rockers,
		Leds = leds,
		Bases = bases,
		Base = bases[1],
		IsOn = on,
		States = {},
	}, Switch) :: any
	for gang = 1, n do
		self:SetGang(gang, on, false)
	end
	return self
end

----------------------------------------------------------------------
-- Groupe de lumières d'une pièce
----------------------------------------------------------------------

export type Lights = {
	Items: { { Light: Light, Base: number } },
	Glows: { { Part: BasePart, Material: Enum.Material, Color: Color3 } },
	IsOn: boolean,
	Add: (self: Lights, light: Light) -> (),
	AddGlow: (self: Lights, part: BasePart) -> (),
	Collect: (self: Lights, root: Instance, glows: boolean) -> number,
	Set: (self: Lights, on: boolean, animate: boolean) -> (),
}

local LightGroup = {}
LightGroup.__index = LightGroup

function LightGroup.Add(self: Lights, light: Light)
	local base = tonumber(light:GetAttribute("BaseBrightness")) or light.Brightness
	light:SetAttribute("BaseBrightness", base)
	table.insert(self.Items, { Light = light, Base = base })
end

function LightGroup.AddGlow(self: Lights, part: BasePart)
	table.insert(self.Glows, { Part = part, Material = part.Material, Color = part.Color })
end

-- Toutes les vraies lumières sous `root` (+ ses pièces "Neon" si `glows`)
function LightGroup.Collect(self: Lights, root: Instance, glows: boolean): number
	local count = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			self:Add(d :: Light)
			count += 1
		elseif glows and d:IsA("BasePart") and d.Material == M.Neon then
			self:AddGlow(d)
		end
	end
	return count
end

function LightGroup.Set(self: Lights, on: boolean, animate: boolean)
	self.IsOn = on
	for _, entry in ipairs(self.Items) do
		local light = entry.Light
		if light.Parent then
			if on then
				light.Enabled = true
				if animate then
					light.Brightness = 0
					tween(light, FADE_TIME, { Brightness = entry.Base })
				else
					light.Brightness = entry.Base
				end
			elseif animate then
				tween(light, FADE_TIME, { Brightness = 0 })
				task.delay(FADE_TIME + 0.05, function()
					if not self.IsOn and light.Parent then
						light.Enabled = false
					end
				end)
			else
				light.Brightness = 0
				light.Enabled = false
			end
		end
	end
	for _, glow in ipairs(self.Glows) do
		local part = glow.Part
		if part.Parent then
			if on then
				part.Material = glow.Material
				part.Color = glow.Color
			else
				-- ampoule éteinte : verre dépoli un peu grisé
				part.Material = M.SmoothPlastic
				part.Color = glow.Color:Lerp(Color3.fromRGB(150, 146, 160), 0.45)
			end
		end
	end
end

function HouseToggles.Lights(): Lights
	return setmetatable({ Items = {}, Glows = {}, IsOn = true }, LightGroup) :: any
end

return HouseToggles
