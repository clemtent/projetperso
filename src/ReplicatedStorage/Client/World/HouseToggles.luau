--[[
	HouseToggles (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseToggles

	🚶 Dopamine Town (v9.8, HOUSE98) : ce qui s'allume, s'éteint, s'ouvre et
	se ferme dans une pièce de la maison 3D :
	  - 🪟 RIDEAUX d'une fenêtre : tringle + embouts + 2 pans de 3 plis
	    chacun ; ouverts = plis serrés de chaque côté de la fenêtre, fermés =
	    les 2 pans se rejoignent au milieu ; animation : les plis glissent le
	    long de la tringle (Size + CFrame, TweenService) ;
	  - 💡 INTERRUPTEUR mural : plaque + bascule qui pivote (haut = allumé) ;
	  - groupe de LUMIÈRES d'une pièce (plafonnier + lampes posées) : fondu de
	    la luminosité des vraies lumières, ampoules "Neon" qui s'éteignent
	    (matière + couleur gardées pour les rallumer).
	Tout est décor (ancré, sans collision, sans ombre) ; aucune interface ici :
	HouseBuilder pose les invites (ProximityPrompt) et sauvegarde l'état.

	API :
	  HouseToggles.Curtains(parent, cf, width, height, color, rodColor, open) -> Curtain
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
local CURTAIN_TIME = 0.7
local SWITCH_TIME = 0.12
local FADE_TIME = 0.35
local FOLDS = 3 -- plis par pan

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
-- 🪟 Rideaux
----------------------------------------------------------------------

export type Curtain = {
	Strips: { BasePart },
	Open: { { CFrame: CFrame, Size: Vector3 } },
	Closed: { { CFrame: CFrame, Size: Vector3 } },
	IsOpen: boolean,
	Anchor: BasePart,
	Set: (self: Curtain, open: boolean, animate: boolean) -> (),
}

local Curtain = {}
Curtain.__index = Curtain

function Curtain.Set(self: Curtain, open: boolean, animate: boolean)
	self.IsOpen = open
	local goals = open and self.Open or self.Closed
	for index, strip in ipairs(self.Strips) do
		local goal = goals[index]
		if animate then
			tween(strip, CURTAIN_TIME, { CFrame = goal.CFrame, Size = goal.Size })
		else
			strip.CFrame = goal.CFrame
			strip.Size = goal.Size
		end
	end
end

function HouseToggles.Curtains(parent: Instance, cf: CFrame, width: number, height: number, color: Color3, rodColor: Color3, open: boolean): Curtain
	local w, h = math.max(1, width), math.max(1, height)
	-- tringle : un peu au-dessus de la fenêtre, 0,9 stud dans la pièce
	local out = -0.9 -- (le long de LookVector : négatif = dans la pièce)
	local rodY = h / 2 + 0.7
	local rodLength = w + 3.4
	decor(parent, "CurtainRod", Vector3.new(rodLength, 0.14, 0.14), cf * CFrame.new(0, rodY, -out) * CFrame.Angles(0, 0, 0), rodColor, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		decor(parent, "CurtainFinial", Vector3.new(0.34, 0.34, 0.34), cf * CFrame.new(s * rodLength / 2, rodY, -out), rodColor, M.Metal, Enum.PartType.Ball)
		-- supports de la tringle (vers le mur)
		decor(parent, "CurtainBracket", Vector3.new(0.1, 0.1, 0.85), cf * CFrame.new(s * (rodLength / 2 - 0.5), rodY, -out / 2), rodColor, M.Metal)
	end
	-- pans : haut sous la tringle, bas sous l'appui
	local top = rodY - 0.1
	local bottom = -h / 2 - 0.75
	local stripH = top - bottom
	local midY = (top + bottom) / 2
	local closedHalf = w / 2 + 1.1 -- largeur d'un pan fermé (recouvre le milieu de 0,1)
	local openHalf = 1.7 -- largeur d'un pan ouvert (plis serrés)
	local strips: { BasePart } = {}
	local openGoals, closedGoals = {}, {}
	local shade = color:Lerp(Color3.new(0, 0, 0), 0.1)
	for _, s in ipairs({ -1, 1 }) do
		local outer = s * (w / 2 + 1.5) -- bord extérieur du pan (sous l'embout)
		for fold = 1, FOLDS do
			-- pli n° fold, du bord extérieur vers le milieu
			local depth = out - 0.05 - (fold % 2) * 0.1 -- plis alternés (relief)
			local function place(panelWidth: number): { CFrame: CFrame, Size: Vector3 }
				local stripW = panelWidth / FOLDS
				local center = outer - s * (fold - 0.5) * stripW
				return { CFrame = cf * CFrame.new(center, midY, -depth), Size = Vector3.new(stripW + 0.06, stripH, 0.12) }
			end
			local openGoal, closedGoal = place(openHalf), place(closedHalf + 0.4)
			local strip = decor(parent, "Curtain", Vector3.new(1, 1, 1), CFrame.identity, if fold % 2 == 0 then shade else color, M.Fabric)
			table.insert(strips, strip)
			table.insert(openGoals, openGoal)
			table.insert(closedGoals, closedGoal)
		end
	end
	-- point d'accroche de l'invite (milieu de la fenêtre, dans la pièce)
	local anchor = decor(parent, "CurtainPrompt", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 0, 1.6), color, M.SmoothPlastic)
	anchor.Transparency = 1
	local self = setmetatable({
		Strips = strips,
		Open = openGoals,
		Closed = closedGoals,
		IsOpen = open,
		Anchor = anchor,
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
