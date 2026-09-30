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
	Tout est décor (ancré, sans collision, sans ombre) ; aucune interface ici :
	HouseBuilder pose les invites (ProximityPrompt) et sauvegarde l'état.

	API :
	  HouseToggles.Curtains(parent, cf, width, height, color, rodColor, open, opts?) -> Curtain
	      opts.Drop = distance du centre de la fenêtre à l'ourlet (rideaux jusqu'au sol)
	      cf = centre de la fenêtre sur la face INTÉRIEURE du mur, RightVector
	      le long de la fenêtre, LookVector = de la pièce VERS le mur
	  curtain:Set(open, animate)
	  HouseToggles.Switch(parent, cf, on) -> Switch   (cf : sur le mur, LookVector vers le mur)
	  switch:Set(on, animate)
	  HouseToggles.Lights() -> Lights ; lights:Add(light) ; lights:AddGlow(part)
	  lights:Collect(model, onlyLamps) ; lights:Set(on, animate)
]]

local TweenService = game:GetService("TweenService")

local HouseToggles = {}

local M = Enum.Material
local CURTAIN_TIME = 0.95
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
-- 🪟 Rideaux (v9.9 HOUSE99 : "100x plus réalistes")
----------------------------------------------------------------------
-- Une fenêtre = tringle ronde (embouts à boule, 2 supports), anneaux qui
-- glissent sur la tringle, 2 VOILAGES (translucides, contre la vitre) et 2
-- DOUBLES RIDEAUX jusqu'au sol, chacun en 5 plis de 2 morceaux (au-dessus /
-- au-dessous de l'embrasse) : plis alternés en profondeur et en teinte ;
-- ouverts = drapés sur le côté, serrés par une EMBRASSE (bande) puis évasés
-- en bas ; fermés = tombés droits jusqu'au milieu. Animation douce (Sine
-- InOut, plis légèrement décalés), tout en CFrame + Size (TweenService).
-- Le tissu garde une teinte moyenne (jamais une plaque sombre).

export type Curtain = {
	Parts: { BasePart },
	Open: { { CFrame: CFrame, Size: Vector3, T: number? } },
	Closed: { { CFrame: CFrame, Size: Vector3, T: number? } },
	Delays: { number },
	IsOpen: boolean,
	Anchor: BasePart,
	Strips: { BasePart }, -- (compat v9.8 : les plis)
	Set: (self: Curtain, open: boolean, animate: boolean) -> (),
}

export type CurtainOptions = {
	Drop: number?, -- distance du centre de la fenêtre à l'ourlet (défaut : jusque sous l'appui)
}

local Curtain = {}
Curtain.__index = Curtain

local FOLD_COUNT = 5

function Curtain.Set(self: Curtain, open: boolean, animate: boolean)
	self.IsOpen = open
	local goals = open and self.Open or self.Closed
	for index, part in ipairs(self.Parts) do
		local goal = goals[index]
		if part.Parent then
			if animate then
				local props: { [string]: any } = { CFrame = goal.CFrame, Size = goal.Size }
				if goal.T ~= nil then
					props.Transparency = goal.T
				end
				local delayTime = self.Delays[index] or 0
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
	local shade = base:Lerp(Color3.new(0, 0, 0), 0.16)
	local light = base:Lerp(Color3.new(1, 1, 1), 0.1)
	-- (repère de `cf` : +X le long de la fenêtre, +Z = vers la pièce)
	local rodOut = 0.95 -- tringle à 0,95 du mur (plis au-delà de l'appui intérieur)
	local rodY = h / 2 + 0.75
	local side = 2.2 -- les rideaux ouverts se rangent à côté de la fenêtre
	local rodLength = w + 2 * (side + 0.25)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local rod = decor(parent, "CurtainRod", Vector3.new(rodLength, 0.16, 0.16), at(0, rodY, rodOut), rodColor, M.Metal, Enum.PartType.Cylinder)
	rod.Reflectance = 0.12
	for _, s in ipairs({ -1, 1 }) do
		decor(parent, "CurtainFinial", Vector3.new(0.38, 0.38, 0.38), at(s * (rodLength / 2 + 0.12), rodY, rodOut), rodColor, M.Metal, Enum.PartType.Ball)
		-- support (du mur à la tringle)
		decor(parent, "CurtainBracket", Vector3.new(0.12, 0.14, rodOut + 0.05), at(s * (rodLength / 2 - 0.45), rodY + 0.04, rodOut / 2), rodColor, M.Metal)
	end
	local parts: { BasePart } = {}
	local openGoals, closedGoals = {}, {}
	local delays: { number } = {}
	local folds: { BasePart } = {}
	local function add(part: BasePart, openGoal: any, closedGoal: any, delayTime: number)
		table.insert(parts, part)
		table.insert(openGoals, openGoal)
		table.insert(closedGoals, closedGoal)
		table.insert(delays, delayTime)
	end
	-- un morceau de pli : du point a (haut) au point b (bas), dans le plan de la fenêtre
	local function segment(ax: number, ay: number, bx: number, by: number, z: number, widthA: number, widthB: number): { CFrame: CFrame, Size: Vector3 }
		local dx, dy = bx - ax, by - ay
		local length = math.max(0.1, math.sqrt(dx * dx + dy * dy))
		local roll = math.atan2(dx, -dy)
		return {
			CFrame = at((ax + bx) / 2, (ay + by) / 2, z) * CFrame.Angles(0, 0, roll),
			Size = Vector3.new(math.max(0.12, (widthA + widthB) / 2 + 0.05), length, 0.1),
		}
	end
	local top = rodY - 0.24
	local bottom = -(opts.Drop or (h / 2 + 0.8)) + 0.1
	local tieY = bottom + 0.42 * (top - bottom)
	local F = FOLD_COUNT
	for panel, s in ipairs({ -1, 1 }) do
		local outer = s * (w / 2 + side)
		local inner = -s * 0.1 -- fermés : se croisent de 0,1 au milieu
		local closedW = math.abs(outer - inner) / F
		local openTop, tieW, botW = 2.0 / F, 0.62 / F, 1.55 / F
		local tieCenter = outer - s * 0.8
		local zPanel = rodOut + (if panel == 2 then 0.035 else 0) -- (pas de faces confondues au milieu)
		for f = 1, F do
			local z = zPanel + (if f % 2 == 0 then 0.11 else -0.02)
			local tone = if f % 2 == 0 then shade elseif f == F then light else base
			-- fermés : tombés droits
			local cx = outer - s * (f - 0.5) * closedW
			local closedUp = segment(cx, top, cx, tieY, z, closedW, closedW)
			local closedLow = segment(cx, tieY, cx, bottom, z, closedW, closedW)
			-- ouverts : haut serré sous la tringle, embrasse, bas évasé
			local xTop = outer - s * (f - 0.5) * openTop
			local xTie = tieCenter + s * 0.31 - s * (f - 0.5) * tieW
			local xBot = outer + s * 0.05 - s * (f - 0.5) * botW
			local openUp = segment(xTop, top, xTie, tieY, z, openTop, tieW)
			local openLow = segment(xTie, tieY, xBot, bottom, z, tieW, botW)
			for k, pair in ipairs({ { openUp, closedUp }, { openLow, closedLow } }) do
				local part = decor(parent, "Curtain", pair[2].Size, pair[2].CFrame, tone, M.Fabric)
				table.insert(folds, part)
				-- (le pli du bord mène le mouvement, les autres suivent)
				add(part, pair[1], pair[2], (F - f) * 0.03 + (k - 1) * 0.02)
			end
		end
		-- anneaux sur la tringle (3 par rideau)
		for r = 1, 3 do
			local xOpen = outer - s * (0.25 + (r - 1) * 0.8)
			local xClosed = outer - s * (0.3 + (r - 1) * (math.abs(outer - inner) - 0.6) / 2)
			local ring = decor(parent, "CurtainRing", Vector3.new(0.08, 0.34, 0.34), at(xClosed, rodY, rodOut), rodColor, M.Metal, Enum.PartType.Cylinder)
			add(ring, { CFrame = at(xOpen, rodY, rodOut), Size = ring.Size }, { CFrame = ring.CFrame, Size = ring.Size }, (3 - r) * 0.05)
		end
		-- embrasse : visible quand ils sont ouverts
		local band = decor(parent, "CurtainTieBack", Vector3.new(0.9, 0.24, 0.34), at(tieCenter, tieY, zPanel + 0.05), base:Lerp(rodColor, 0.5), M.Fabric)
		add(band, { CFrame = band.CFrame, Size = band.Size, T = 0 }, { CFrame = band.CFrame, Size = band.Size, T = 1 }, 0)
		-- voilage (translucide, contre la vitre) : suit les rideaux
		local sheerOuter = s * (w / 2 + 1.4)
		local zSheer = rodOut - 0.22 + (if panel == 2 then 0.03 else 0)
		local sheerH = top - bottom
		local sheer = decor(parent, "CurtainSheer", Vector3.new(1, sheerH, 0.05), at(0, (top + bottom) / 2, zSheer), Color3.fromRGB(252, 250, 246), M.Fabric)
		sheer.Transparency = 0.62
		local closedSheerW = math.abs(sheerOuter) + 0.08
		add(sheer, { CFrame = at(sheerOuter - s * 0.5, (top + bottom) / 2, zSheer), Size = Vector3.new(1, sheerH, 0.05) },
			{ CFrame = at(sheerOuter - s * closedSheerW / 2, (top + bottom) / 2, zSheer), Size = Vector3.new(closedSheerW, sheerH, 0.05) }, 0.12)
	end
	-- point d'accroche de l'invite (milieu de la fenêtre, dans la pièce)
	local anchor = decor(parent, "CurtainPrompt", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 0, 1.6), color, M.SmoothPlastic)
	anchor.Transparency = 1
	local self = setmetatable({
		Parts = parts,
		Open = openGoals,
		Closed = closedGoals,
		Delays = delays,
		IsOpen = open,
		Anchor = anchor,
		Strips = folds,
	}, Curtain) :: any
	self:Set(open, false)
	return self
end

----------------------------------------------------------------------
-- 💡 Interrupteur
----------------------------------------------------------------------

export type Switch = {
	Plate: BasePart,
	Rocker: BasePart,
	Base: CFrame,
	IsOn: boolean,
	Set: (self: Switch, on: boolean, animate: boolean) -> (),
}

local Switch = {}
Switch.__index = Switch

local TILT = math.rad(14)

function Switch.Set(self: Switch, on: boolean, animate: boolean)
	self.IsOn = on
	-- bascule : haut enfoncé = allumé (on appuie en haut)
	local goal = self.Base * CFrame.Angles(if on then -TILT else TILT, 0, 0)
	if animate then
		tween(self.Rocker, SWITCH_TIME, { CFrame = goal }, Enum.EasingStyle.Quad)
	else
		self.Rocker.CFrame = goal
	end
	local led = self.Plate:FindFirstChild("Led")
	if led and led:IsA("BasePart") then
		led.Color = if on then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(120, 200, 255)
	end
end

function HouseToggles.Switch(parent: Instance, cf: CFrame, on: boolean): Switch
	-- (repère de `cf` : +Z = vers la pièce ; la plaque dépasse du mur de 0,01..0,09)
	local plate = decor(parent, "SwitchPlate", Vector3.new(0.62, 0.95, 0.08), cf * CFrame.new(0, 0, 0.05), Color3.fromRGB(252, 248, 244), M.SmoothPlastic)
	plate.CanQuery = true -- (clic / invite)
	local rocker = decor(parent, "SwitchRocker", Vector3.new(0.3, 0.44, 0.12), cf * CFrame.new(0, 0, 0.12), Color3.fromRGB(255, 255, 255), M.SmoothPlastic)
	-- petit voyant (repère dans le noir), sous la bascule
	decor(plate, "Led", Vector3.new(0.1, 0.06, 0.03), cf * CFrame.new(0, -0.36, 0.1), Color3.fromRGB(255, 214, 140), M.SmoothPlastic)
	local self = setmetatable({
		Plate = plate,
		Rocker = rocker,
		Base = cf * CFrame.new(0, 0, 0.12),
		IsOn = on,
	}, Switch) :: any
	self:Set(on, false)
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
