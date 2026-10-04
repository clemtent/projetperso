--[[
	TownHallInterior (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownHallInterior

	🏛️ Dopamine Town (v11, CITY11) : l'INTÉRIEUR COMPLET de la mairie, où
	l'on ENTRE, construit côté client (0 pièce serveur) quand l'avatar /
	la caméra approche (≤ 120 studs, détruit au-delà de 165) :
	  - le volume plein du serveur ("Body") est masqué LOCALEMENT et
	    remplacé par une coque creuse identique vue de dehors (même pierre,
	    mêmes fenêtres : on voit enfin dedans) ; restauré quand on s'éloigne ;
	  - GRAND HALL à double hauteur : sol de marbre en damier, tapis rouge,
	    deux statues sur socles, colonnes, deux lustres, grand escalier à
	    deux volées (marches 0,93 x 1,5, rampes 3,2, pente invisible) vers
	    une galerie (garde-corps vitré 3,5) ;
	  - ACCUEIL : banque d'accueil (3,3) et deux agents ; plan de la ville
	    (dessiné depuis WorldLayout : quartiers, avenues, autoroute, place,
	    "Vous êtes ici") ; deux ÉCRANS DE CLASSEMENT (joueurs du serveur,
	    maisons les plus aimées) mis à jour toutes les 2 s ;
	  - SALLE D'ATTENTE (chaises à 1,85, ticket "prenez un numéro", écran
	    d'appel) ; GUICHETS (état civil, passeports, urbanisme) ;
	  - BUREAU DU MAIRE (grand bureau, fauteuil, drapeaux, bibliothèque,
	    portrait, visiteurs) ; SALLE DU CONSEIL (hémicycle de pupitres,
	    tribune du président, conseillers assis) ;
	  - à l'étage : BUREAUX ouverts (postes, écrans, fontaine à eau) et
	    ARCHIVES (rayonnages de boîtes) ;
	  - PNJ animés (CityKit.Actor : seulement près de la caméra) ; deux
	    vraies lumières douces, allumées seulement quand la caméra est dedans.
	Repère B = attribut "FacadeCF" de la mairie : face avant du corps à z = 0,
	corps en z ∈ [0, D], x ∈ [-W/2, W/2], y = 0 au pied (dessus du parvis).

	API (TownDisplays) :
	  TownHallInterior.Attach(hall: Model, folder: Instance, feeds)
	      feeds = { Players: () -> rows, Houses: () -> rows } (rows : Name, ValueText, Rank)
	  TownHallInterior.Step(position: Vector3, dt: number)
	  TownHallInterior.Detach()
	  TownHallInterior.Debug() -> table
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local CityKit = require(script.Parent.CityKit)

local TownHallInterior = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local Box = CityKit.Box
local Column = CityKit.Column
local WHITE = rgb(250, 250, 248)
local INK = rgb(36, 34, 44)
local STONE = rgb(250, 238, 230) -- (même pierre que le serveur)
local MARBLE = rgb(240, 236, 230)
local MARBLE_D = rgb(150, 140, 136)
local WOOD = rgb(150, 96, 60)
local WOOD_D = rgb(96, 60, 40)
local GOLD = rgb(214, 180, 92)
local RED = rgb(170, 30, 46)
local GLASS = rgb(196, 226, 240)

local BUILD_IN, BUILD_OUT = 120, 165
local JOB_BUDGET = 0.004
local SEAT_H = 1.85
local COUNTER_H = 3.3
local TABLE_H = 3.1

-- Géométrie (repère B)
local FLOOR = 2.35 -- dessus du sol fini (= dessus du perron du serveur 2,3 + 0,05)
local MEZZ = 14.5 -- dessus de la galerie
local MEZZ_T = 0.6
local ROOF = 33.5 -- dessous de la dalle de toit
local WALL_T = 0.55
local INSET = 0.05 -- les faces extérieures de la coque restent 0,05 en retrait du corps masqué
local ATRIUM = 13 -- demi-largeur du grand hall
local LANDING = 21 -- bord avant du palier du fond (z)
local PARTITION = 15 -- cloison avant / arrière des ailes (z)

type State = {
	Hall: Model,
	Folder: Instance,
	B: CFrame,
	W: number,
	D: number,
	H: number,
	Feeds: any,
	Model: Model?,
	Jobs: { () -> () }?,
	JobIndex: number,
	Built: boolean,
	Hidden: { { Part: BasePart, Mod: number, Collide: boolean } },
	Screens: { { Kind: string, Rows: { TextLabel }, Title: TextLabel } },
	ScreenTimer: number,
	Lights: { PointLight },
	LightsOn: boolean,
	Parts: number,
}

local state: State? = nil
local stats = { Builds = 0, Destroys = 0, Parts = 0, Npcs = 0 }

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function count(m: Instance): number
	local n = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- mur percé : rectangle (x0..x1, y0..y1) dans le plan z0..z1 du repère F,
-- moins les ouvertures { {x0, x1, y0, y1} } (découpe en bandes)
local function wallWithHoles(m: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, holes: { { number } }, color: Color3, mat: Enum.Material)
	-- bandes horizontales aux bords des ouvertures
	local ys = { y0, y1 }
	for _, h in ipairs(holes) do
		table.insert(ys, math.clamp(h[3], y0, y1))
		table.insert(ys, math.clamp(h[4], y0, y1))
	end
	table.sort(ys)
	local uniq = {}
	for _, y in ipairs(ys) do
		if #uniq == 0 or y - uniq[#uniq] > 1e-3 then
			table.insert(uniq, y)
		end
	end
	for i = 1, #uniq - 1 do
		local a, b = uniq[i], uniq[i + 1]
		local mid = (a + b) / 2
		-- trous qui traversent cette bande
		local cuts = {}
		for _, h in ipairs(holes) do
			if h[3] < mid and h[4] > mid then
				table.insert(cuts, { math.max(h[1], x0), math.min(h[2], x1) })
			end
		end
		table.sort(cuts, function(p, q)
			return p[1] < q[1]
		end)
		local x = x0
		for _, c in ipairs(cuts) do
			if c[1] - x > 0.02 then
				Box(m, name, F, x, c[1], a, b, z0, z1, color, mat, true)
			end
			x = math.max(x, c[2])
		end
		if x1 - x > 0.02 then
			Box(m, name, F, x, x1, a, b, z0, z1, color, mat, true)
		end
	end
end

local function npc(m: Instance, style: string, seed: number, cf: CFrame, anim: string, prop: string?, sitH: number?): Model?
	local model = CityKit.Npc(m, style, seed, cf, prop, false, true)
	if model then
		stats.Npcs += 1
		if sitH then
			model:SetAttribute("NpcSitHeight", sitH)
		end
		CityKit.Animate(model, anim, seed)
		CityKit.Idle(model, anim, seed % 13)
	end
	return model
end

-- chaise (assise 1,85) tournée vers -Z du repère C (dos à +Z)
local function chair(m: Instance, C: CFrame, color: Color3)
	Box(m, "ChairSeat", C, -1.1, 1.1, SEAT_H - 0.18, SEAT_H, -1.0, 1.0, color, M.Fabric, true)
	Box(m, "ChairBack", C, -1.1, 1.1, SEAT_H, 4.2, 0.82, 1.0, color, M.Fabric)
	for _, sx in ipairs({ -0.95, 0.95 }) do
		Box(m, "ChairSide", C, sx - 0.07, sx + 0.07, 0, SEAT_H - 0.18, -0.9, 0.9, INK, M.Metal)
	end
end

-- bureau (plateau 3,1) centré sur C, devant = -Z
local function desk(m: Instance, C: CFrame, w: number, color: Color3, screen: boolean)
	Box(m, "DeskTop", C, -w / 2, w / 2, TABLE_H - 0.15, TABLE_H, -1.2, 1.2, color, M.Wood, true)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "DeskSide", C, sx * w / 2 - sx * 0.3 - 0.15, sx * w / 2 - sx * 0.3 + 0.15, 0, TABLE_H - 0.15, -1.1, 1.1, color:Lerp(INK, 0.25), M.Wood)
	end
	Box(m, "DeskModesty", C, -w / 2 + 0.45, w / 2 - 0.45, 0.8, TABLE_H - 0.15, 0.9, 1.05, color:Lerp(INK, 0.25), M.Wood)
	if screen then
		Box(m, "Monitor", C, -0.9, 0.9, TABLE_H + 0.35, TABLE_H + 1.55, 0.35, 0.45, INK, M.SmoothPlastic)
		CityKit.Glow(Box(m, "MonitorGlow", C, -0.8, 0.8, TABLE_H + 0.42, TABLE_H + 1.48, 0.3, 0.35, rgb(120, 180, 240), M.SmoothPlastic))
		Column(m, "MonitorStem", C, 0, 0.55, TABLE_H, TABLE_H + 0.35, 0.15, INK, M.Metal)
		Box(m, "Keyboard", C, -0.8, 0.8, TABLE_H, TABLE_H + 0.08, -0.6, -0.1, rgb(60, 62, 70), M.SmoothPlastic)
	end
end

-- statue en marbre (personnage NPCModels figé, recolorié) sur socle
local function statue(m: Instance, P: CFrame, seed: number, title: string)
	Box(m, "StatuePlinth", P, -1.6, 1.6, 0, 3.4, -1.6, 1.6, MARBLE_D, M.Marble, true)
	Box(m, "StatuePlinthCap", P, -1.8, 1.8, 3.4, 3.7, -1.8, 1.8, MARBLE, M.Marble)
	local plate = Box(m, "StatuePlate", P, -1.1, 1.1, 1.6, 2.6, -1.66, -1.6, GOLD, M.Metal)
	CityKit.Text(plate, Enum.NormalId.Front, title, INK, GOLD, Enum.Font.Garamond, 30, 30)
	-- figure en marbre stylisée (quelques pièces : budget), bras levé
	local mar = rgb(226, 222, 214)
	local T = P * CFrame.new(0, 3.7, 0) * CFrame.Angles(0, (seed % 2 == 0) and 0.3 or -0.3, 0)
	CityKit.Egg(m, "StatueRobe", T * CFrame.new(0, 2.2, 0), Vector3.new(2.4, 4.4, 1.8), mar, M.Marble)
	CityKit.Egg(m, "StatueChest", T * CFrame.new(0, 4.6, 0), Vector3.new(2.2, 2.0, 1.4), mar, M.Marble)
	CityKit.Ball(m, "StatueHead", (T * CFrame.new(0, 6.3, 0)).Position, 1.5, mar, M.Marble)
	CityKit.Rod(m, "StatueArm", (T * CFrame.new(0.9, 5.0, 0)).Position, (T * CFrame.new(1.8, 7.4, -0.4)).Position, 0.5, mar, M.Marble)
	CityKit.Rod(m, "StatueArm", (T * CFrame.new(-0.9, 5.0, 0)).Position, (T * CFrame.new(-1.3, 3.2, -0.3)).Position, 0.5, mar, M.Marble)
	CityKit.Egg(m, "StatueBook", T * CFrame.new(-1.35, 3.0, -0.45), Vector3.new(0.9, 1.1, 0.3), mar, M.Marble)
	local _ = seed
end

local function lampGlobe(m: Instance, B: CFrame, x: number, y: number, z: number, size: number)
	Column(m, "ChandelierChain", B, x, z, y + size * 0.5, ROOF, 0.1, GOLD, M.Metal)
	Column(m, "ChandelierRing", B, x, z, y - 0.1, y + 0.1, size * 1.6, GOLD, M.Metal)
	CityKit.Glow(CityKit.Egg(m, "ChandelierGlobe", B * CFrame.new(x, y + size * 0.25, z), Vector3.new(size, size * 0.8, size), rgb(255, 238, 200), M.Glass))
	for k = 0, 5 do
		local a = k * math.pi / 3
		CityKit.Glow(CityKit.Ball(m, "ChandelierBulb", (B * CFrame.new(x + math.cos(a) * size * 0.8, y + 0.35, z + math.sin(a) * size * 0.8)).Position, 0.45, rgb(255, 230, 180), M.SmoothPlastic))
	end
end

-- texte simple dans un panneau (face avant -Z)
local function sign(m: Instance, F: CFrame, x0: number, x1: number, y0: number, y1: number, z: number, text: string, fg: Color3, bg: Color3)
	local p = Box(m, "Sign", F, x0, x1, y0, y1, z - 0.1, z, bg, M.SmoothPlastic)
	CityKit.Text(p, Enum.NormalId.Front, text, fg, bg, Enum.Font.GothamBold, 70, 30)
	return p
end

----------------------------------------------------------------------
-- Plan de la ville (SurfaceGui) : quartiers, avenues, autoroute, place
----------------------------------------------------------------------

local function cityMap(host: BasePart, count: number)
	local gui = CityKit.Canvas(host, Enum.NormalId.Front, 90, 40)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(222, 236, 210)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local WL: any = WorldLayout
	local ok, extent = pcall(function()
		return (WL.HighwayR(count) + 60)
	end)
	local E = ok and extent or 1200
	-- (le plan regarde vers la place : le haut du plan = le nord (-Z ville))
	local function px(x: number): number
		return 0.5 + x / (2 * E)
	end
	local function pz(z: number): number
		return 0.5 + z / (2 * E)
	end
	local styleColor = {
		Cottage = rgb(170, 214, 140), Townhouse = rgb(240, 196, 170), Loft = rgb(200, 150, 130),
		Mansion = rgb(214, 190, 240), Mixed = rgb(240, 226, 160),
	}
	pcall(function()
		for _, d in ipairs(WL.Districts(count)) do
			local R = d.Bounds
			local f = CityKit.Blob(gui, px(R.X), pz(R.Z), R.W / (2 * E), R.D / (2 * E), styleColor[d.Style] or WHITE, 0.08)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 0.4)
			l.Position = UDim2.fromScale(0, 0.3)
			l.TextScaled = true
			l.Font = Enum.Font.GothamBold
			l.TextColor3 = INK
			l.Text = (d.Emoji or "") .. " " .. Locale.T(d.Name or d.Style)
			l.Parent = f
		end
	end)
	-- avenues (carré du centre, ceinture) et autoroute
	local function square(r: number, thick: number, color: Color3)
		local t = thick / (2 * E)
		CityKit.Blob(gui, px(0), pz(-r), r / E, t, color)
		CityKit.Blob(gui, px(0), pz(r), r / E, t, color)
		CityKit.Blob(gui, px(-r), pz(0), t, r / E, color)
		CityKit.Blob(gui, px(r), pz(0), t, r / E, color)
	end
	square(250, 26, rgb(110, 112, 124))
	pcall(function()
		square(WL.BeltR(count), 26, rgb(110, 112, 124))
		square(WL.HighwayR(count), 58, rgb(70, 72, 84))
	end)
	-- avenue d'entrée (x = 0, vers le sud)
	CityKit.Blob(gui, px(0), pz(400), 22 / (2 * E), 600 / (2 * E), rgb(110, 112, 124))
	-- place + "vous êtes ici"
	CityKit.Blob(gui, px(0), pz(0), 188 / (2 * E), 188 / (2 * E), rgb(236, 200, 220), 1)
	local here = CityKit.Blob(gui, px(0), pz(-80), 0.035, 0.035, rgb(230, 40, 60), 1)
	local tag = Instance.new("TextLabel")
	tag.BackgroundColor3 = WHITE
	tag.BorderSizePixel = 0
	tag.Size = UDim2.fromScale(7, 1.8)
	tag.Position = UDim2.fromScale(-3, -2.2)
	tag.TextScaled = true
	tag.Font = Enum.Font.GothamBlack
	tag.TextColor3 = rgb(230, 40, 60)
	tag.Text = "📍 " .. Locale.T("You are here")
	tag.Parent = here
	local title = Instance.new("TextLabel")
	title.BackgroundColor3 = INK
	title.BorderSizePixel = 0
	title.Size = UDim2.fromScale(1, 0.07)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = WHITE
	title.Text = "🗺️ " .. Locale.T("Map of Dopamine Town")
	title.Parent = gui
end

----------------------------------------------------------------------
-- Écrans de classement
----------------------------------------------------------------------

local function board(st: State, m: Instance, F: CFrame, x0: number, x1: number, y0: number, y1: number, z: number, kind: string)
	Box(m, "BoardFrame", F, x0 - 0.3, x1 + 0.3, y0 - 0.3, y1 + 0.3, z - 0.2, z + 0.1, rgb(40, 36, 52), M.Metal)
	local p = Box(m, "BoardScreen", F, x0, x1, y0, y1, z - 0.3, z - 0.2, rgb(24, 20, 40), M.SmoothPlastic)
	local gui = CityKit.Canvas(p, Enum.NormalId.Front, 120, 30)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(28, 22, 52)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(rgb(60, 30, 100), rgb(20, 24, 50))
	grad.Rotation = 90
	grad.Parent = bg
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.04, 0.03)
	title.Size = UDim2.fromScale(0.92, 0.16)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = rgb(255, 214, 96)
	title.Text = kind == "Players" and Locale.T("🏆 Top players of the server") or Locale.T("❤️ Most-loved houses")
	title.Parent = bg
	local rows = {}
	for i = 1, 6 do
		local r = Instance.new("TextLabel")
		r.BackgroundColor3 = i % 2 == 0 and rgb(46, 38, 80) or rgb(56, 44, 96)
		r.BackgroundTransparency = 0.2
		r.BorderSizePixel = 0
		r.Position = UDim2.fromScale(0.05, 0.22 + (i - 1) * 0.125)
		r.Size = UDim2.fromScale(0.9, 0.11)
		r.TextScaled = true
		r.TextXAlignment = Enum.TextXAlignment.Left
		r.Font = Enum.Font.GothamBold
		r.TextColor3 = i == 1 and rgb(255, 236, 150) or WHITE
		r.Text = ""
		r.Parent = bg
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = r
		rows[i] = r
	end
	table.insert(st.Screens, { Kind = kind, Rows = rows, Title = title })
end

local function refreshScreens(st: State)
	for _, s in ipairs(st.Screens) do
		local feed = st.Feeds and st.Feeds[s.Kind]
		local ok, rows = pcall(function()
			return feed and feed() or {}
		end)
		if not ok or type(rows) ~= "table" then
			rows = {}
		end
		for i, label in ipairs(s.Rows) do
			local r = rows[i]
			if r then
				local medal = ({ "🥇", "🥈", "🥉" })[i] or ("  " .. tostring(i) .. ".")
				label.Text = "  " .. medal .. "  " .. tostring(r.Name) .. "  ·  " .. tostring(r.ValueText or "")
			else
				label.Text = i == 1 and ("  " .. Locale.T("Nobody yet: be the first!")) or ""
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction (travaux découpés)
----------------------------------------------------------------------

local function jobsFor(st: State, m: Model): { () -> () }
	local B = st.B
	local W, D = st.W, st.D
	local hw = W / 2
	local xi = hw - INSET - WALL_T -- face intérieure des murs latéraux
	local zf0, zf1 = INSET, INSET + WALL_T -- mur avant
	local zb1 = D - INSET
	local zb0 = zb1 - WALL_T -- mur du fond
	local jobs: { () -> () } = {}
	local hall = st.Hall

	-- 1. coque : murs percés, sols, galerie, toit ; on masque le volume plein
	table.insert(jobs, function()
		-- ouvertures de la façade = fenêtres du serveur + porte
		local holes = { { -3, 3, FLOOR - 0.6, 11.3 } }
		for _, sx in ipairs({ -1, 1 }) do
			for f = 0, 1 do
				for i = 0, 2 do
					local x = sx * (14 + 3.5 + i * 6.4)
					local y = 7 + f * 14
					table.insert(holes, { x - 1.7, x + 1.7, y - 3.2, y + 3.2 })
				end
			end
		end
		wallWithHoles(m, "HallWall", B, -hw + INSET, hw - INSET, 1.6, ROOF + 0.45, zf0, zf1, holes, STONE, M.Limestone)
		-- fond + côtés (pleins : leurs fenêtres sont peintes dehors par TownFacades)
		Box(m, "HallWall", B, -hw + INSET, hw - INSET, 1.6, ROOF + 0.45, zb0, zb1, STONE, M.Limestone, true)
		for _, sx in ipairs({ -1, 1 }) do
			local a, b = sx * (hw - INSET), sx * xi
			Box(m, "HallWall", B, math.min(a, b), math.max(a, b), 1.6, ROOF + 0.45, zf1, zb0, STONE, M.Limestone, true)
		end
		-- sol fini (damier de marbre : dalle + carreaux sombres en quinconce)
		Box(m, "HallFloor", B, -xi, xi, 1.6, FLOOR, zf1, zb0, MARBLE, M.Marble, true)
		for i = -4, 4 do
			for j = 0, 6 do
				if (i + j) % 2 == 0 then
					local x = i * 2.4
					local z = 1.6 + j * 2.4
					Box(m, "FloorTile", B, x - 1.2, x + 1.2, FLOOR, FLOOR + 0.03, z, z + 2.4, MARBLE_D, M.Marble)
				end
			end
		end
		-- tapis rouge de la porte à l'accueil
		Box(m, "RedCarpet", B, -2.2, 2.2, FLOOR + 0.03, FLOOR + 0.07, zf1 + 0.05, 10.8, RED, M.Fabric)
		-- galeries des ailes + palier du fond
		for _, sx in ipairs({ -1, 1 }) do
			local a, b = sx * ATRIUM, sx * xi
			Box(m, "Gallery", B, math.min(a, b), math.max(a, b), MEZZ - MEZZ_T, MEZZ, zf1, zb0, MARBLE, M.Marble, true)
		end
		Box(m, "Landing", B, -ATRIUM, ATRIUM, MEZZ - MEZZ_T, MEZZ, LANDING, zb0, MARBLE, M.Marble, true)
		-- dalle du toit (sous la corniche du serveur)
		Box(m, "HallCeiling", B, -xi, xi, ROOF, ROOF + 0.45, zf1, zb0, rgb(244, 238, 228), M.SmoothPlastic)
		-- caissons du plafond du hall
		for i = -2, 2 do
			Box(m, "CeilingBeam", B, i * 5 - 0.3, i * 5 + 0.3, ROOF - 0.6, ROOF, zf1, zb0, GOLD:Lerp(WHITE, 0.4), M.SmoothPlastic)
		end
		-- masquer localement le volume plein du serveur + la porte et les cadres de fenêtres
		for _, p in ipairs(hall:GetChildren()) do
			if p:IsA("BasePart") and (p.Name == "Body" or p.Name == "PortalDoor" or p.Name == "WinFrame") then
				table.insert(st.Hidden, { Part = p, Mod = tonumber(p.LocalTransparencyModifier) or 0, Collide = p.CanCollide == true })
				p.LocalTransparencyModifier = 1
				p.CanCollide = false
			elseif p:IsA("BasePart") and p.Name == "WinBar" then
				table.insert(st.Hidden, { Part = p, Mod = tonumber(p.LocalTransparencyModifier) or 0, Collide = p.CanCollide == true })
				p.LocalTransparencyModifier = 1
			elseif p:IsA("BasePart") and p.Name == "WinGlass" then
				table.insert(st.Hidden, { Part = p, Mod = tonumber(p.LocalTransparencyModifier) or 0, Collide = p.CanCollide == true })
				p.LocalTransparencyModifier = 0.55
			end
		end
	end)

	-- 2. encadrements des fenêtres (le cadre plein du serveur est masqué) + portes ouvertes
	table.insert(jobs, function()
		for _, sx in ipairs({ -1, 1 }) do
			for f = 0, 1 do
				for i = 0, 2 do
					local x = sx * (14 + 3.5 + i * 6.4)
					local y = 7 + f * 14
					local R = B * CFrame.new(x, y, 0)
					Box(m, "WinRing", R, -2.1, 2.1, 3.2, 3.6, -0.22, 0.04, WHITE, M.SmoothPlastic)
					Box(m, "WinRing", R, -2.1, 2.1, -3.6, -3.2, -0.22, 0.04, WHITE, M.SmoothPlastic)
					Box(m, "WinRing", R, -2.1, -1.7, -3.2, 3.2, -0.22, 0.04, WHITE, M.SmoothPlastic)
					Box(m, "WinRing", R, 1.7, 2.1, -3.2, 3.2, -0.22, 0.04, WHITE, M.SmoothPlastic)
					Box(m, "WinMullion", R, -0.12, 0.12, -3.2, 3.2, -0.42, -0.34, WHITE, M.SmoothPlastic)
				end
			end
		end
		-- portes à deux battants ouverts vers l'intérieur
		for _, sx in ipairs({ -1, 1 }) do
			local H = B * CFrame.new(sx * 3, 0, zf1 + 0.1) * CFrame.Angles(0, sx * math.rad(100), 0)
			Box(m, "HallDoor", H, sx < 0 and 0 or -2.95, sx < 0 and 2.95 or 0, FLOOR, 11.2, -0.1, 0.1, rgb(120, 80, 70), M.Wood)
			Box(m, "HallDoorPanel", H, sx < 0 and 0.4 or -2.55, sx < 0 and 2.55 or -0.4, 3.5, 6.8, -0.16, -0.1, rgb(140, 96, 80), M.Wood)
			Box(m, "HallDoorPanel", H, sx < 0 and 0.4 or -2.55, sx < 0 and 2.55 or -0.4, 7.4, 10.6, -0.16, -0.1, rgb(140, 96, 80), M.Wood)
		end
	end)

	-- 3. grand escalier (deux volées vers le palier) + garde-corps
	table.insert(jobs, function()
		local steps = 13
		local rise = (MEZZ - FLOOR) / steps
		local tread = 1.5
		local z0 = LANDING - steps * tread
		for _, sx in ipairs({ -1, 1 }) do
			local xa, xb = sx * 8.5, sx * 12.5
			local x0, x1 = math.min(xa, xb), math.max(xa, xb)
			for k = 1, steps do
				local top = FLOOR + k * rise
				local z = z0 + (k - 1) * tread
				Box(m, "Step", B, x0, x1, top - 0.32, top, z, z + tread, k % 2 == 0 and MARBLE or MARBLE:Lerp(MARBLE_D, 0.15), M.Marble)
				Box(m, "StepRiser", B, x0 + 0.05, x1 - 0.05, top - rise, top - 0.32, z + tread - 0.2, z + tread - 0.05, MARBLE_D, M.Marble)
			end
			-- limons (poutres inclinées) côté hall
			local xs = sx * 8.35
			local a = (B * CFrame.new(xs, FLOOR + 0.6, z0)).Position
			local b = (B * CFrame.new(xs, MEZZ + 0.4, LANDING)).Position
			CityKit.Beam(m, "Stringer", a, b, 0.3, 1.0, MARBLE_D, M.Marble)
			-- main courante (3,2 au-dessus des nez de marche) + 4 balustres
			local ra = (B * CFrame.new(xs, FLOOR + 3.2, z0)).Position
			local rb = (B * CFrame.new(xs, MEZZ + 3.2, LANDING)).Position
			CityKit.Beam(m, "Handrail", ra, rb, 0.3, 0.3, GOLD, M.Metal)
			for k = 0, 3 do
				local t = k / 3
				local p = a:Lerp(b, t)
				local q = ra:Lerp(rb, t)
				CityKit.Beam(m, "Baluster", p, q, 0.18, 0.18, GOLD, M.Metal)
			end
			-- pente INVISIBLE (on monte sans accrocher les marches)
			local ramp = CityKit.Wedge(m, "StairRamp", Vector3.new(4, MEZZ - FLOOR, LANDING - z0), B * CFrame.new(sx * 10.5, FLOOR + (MEZZ - FLOOR) / 2, (z0 + LANDING) / 2), MARBLE, M.Marble, true)
			ramp.Transparency = 1
			-- dessous de l'escalier : soubassement plein (visible)
			local under = CityKit.Wedge(m, "StairMass", Vector3.new(3.8, MEZZ - FLOOR - 1.0, LANDING - z0 - 1.5), B * CFrame.new(sx * 10.5, FLOOR + (MEZZ - FLOOR - 1.0) / 2, (z0 + 1.5 + LANDING) / 2), MARBLE_D:Lerp(WHITE, 0.4), M.Marble, false)
			local _ = under
		end
		-- garde-corps vitrés (3,5) : bords des galeries + palier (entre les volées)
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * ATRIUM
			local g = Box(m, "RailGlass", B, x - 0.06, x + 0.06, MEZZ + 0.3, MEZZ + 3.2, zf1 + 0.2, LANDING, GLASS, M.Glass, true)
			g.Transparency = 0.55
			Box(m, "RailTop", B, x - 0.2, x + 0.2, MEZZ + 3.2, MEZZ + 3.5, zf1 + 0.2, LANDING, GOLD, M.Metal, true)
		end
		local lg = Box(m, "RailGlass", B, -8.5, 8.5, MEZZ + 0.3, MEZZ + 3.2, LANDING - 0.06, LANDING + 0.06, GLASS, M.Glass, true)
		lg.Transparency = 0.55
		Box(m, "RailTop", B, -8.5, 8.5, MEZZ + 3.2, MEZZ + 3.5, LANDING - 0.2, LANDING + 0.2, GOLD, M.Metal, true)
		-- colonnes sous les galeries
		for _, sx in ipairs({ -1, 1 }) do
			for _, z in ipairs({ 4, 9.5, 15 }) do
				Column(m, "HallColumn", B, sx * ATRIUM, z, FLOOR, MEZZ - MEZZ_T, 1.3, MARBLE, M.Marble, true)
				Box(m, "ColumnCap", B, sx * ATRIUM - 0.9, sx * ATRIUM + 0.9, MEZZ - MEZZ_T - 0.5, MEZZ - MEZZ_T - 0.02, z - 0.9, z + 0.9, GOLD:Lerp(WHITE, 0.3), M.Marble)
				Box(m, "ColumnBase", B, sx * ATRIUM - 0.85, sx * ATRIUM + 0.85, FLOOR, FLOOR + 0.4, z - 0.85, z + 0.85, MARBLE_D, M.Marble)
			end
		end
	end)

	-- 4. accueil, statues, plan, écrans, lustres
	table.insert(jobs, function()
		local zc = 11.5
		Box(m, "Reception", B, -5.5, 5.5, FLOOR, FLOOR + COUNTER_H - 0.2, zc, zc + 1.6, WOOD, M.Wood, true)
		for _, sx in ipairs({ -1, 1 }) do
			local R = B * CFrame.new(sx * 6.6, 0, zc + 1.6) * CFrame.Angles(0, sx * math.rad(35), 0)
			Box(m, "Reception", R, -1.6, 1.6, FLOOR, FLOOR + COUNTER_H - 0.2, -1.6, 0, WOOD, M.Wood, true)
			Box(m, "ReceptionTop", R, -1.7, 1.7, FLOOR + COUNTER_H - 0.2, FLOOR + COUNTER_H, -1.7, 0.1, MARBLE, M.Marble)
		end
		Box(m, "ReceptionTop", B, -5.6, 5.6, FLOOR + COUNTER_H - 0.2, FLOOR + COUNTER_H, zc - 0.12, zc + 1.7, MARBLE, M.Marble)
		Box(m, "ReceptionBand", B, -5.5, 5.5, FLOOR + 1.2, FLOOR + 1.6, zc - 0.05, zc + 0.02, GOLD, M.Metal)
		sign(m, B * CFrame.new(0, 0, zc - 0.05), -2.4, 2.4, FLOOR + 0.4, FLOOR + 1.15, 0, "ℹ️ " .. Locale.T("Reception"), WHITE, rgb(30, 60, 110))
		for k, x in ipairs({ -2.2, 2.2 }) do
			npc(m, k == 1 and "salesperson" or "cashier", 900 + k, B * CFrame.new(x, FLOOR, zc + 3.1), k == 1 and "type" or "talk")
			Box(m, "Monitor", B, x - 0.8, x + 0.8, FLOOR + COUNTER_H + 0.3, FLOOR + COUNTER_H + 1.4, zc + 0.9, zc + 1.0, INK, M.SmoothPlastic)
		end
		npc(m, "shopper", 911, B * CFrame.new(-1.6, FLOOR, zc - 2.2) * CFrame.Angles(0, math.pi, 0), "talk", "bag")
		-- statues de part et d'autre de l'allée
		statue(m, B * CFrame.new(-5.6, FLOOR, 6.5), 21, Locale.T("Our town founder"))
		statue(m, B * CFrame.new(5.6, FLOOR, 6.5), 22, Locale.T("To the first clicker"))
		-- plan de la ville sur le mur du fond (sous le palier)
		Box(m, "MapFrame", B, -6.4, 6.4, FLOOR + 1.0, FLOOR + 11.2, zb0 - 0.25, zb0, WOOD_D, M.Wood)
		local map = Box(m, "CityMap", B, -6, 6, FLOOR + 1.4, FLOOR + 10.8, zb0 - 0.32, zb0 - 0.25, WHITE, M.SmoothPlastic)
		local count = 8
		local town = workspace:FindFirstChild("DopamineTown")
		if town and type(town:GetAttribute("PlotCount")) == "number" then
			count = town:GetAttribute("PlotCount") :: number
		end
		pcall(cityMap, map, count)
		-- écrans de classement au-dessus du palier
		board(st, m, B, -12.2, -1.2, MEZZ + 4.2, MEZZ + 11.2, zb0, "Players")
		board(st, m, B, 1.2, 12.2, MEZZ + 4.2, MEZZ + 11.2, zb0, "Houses")
		-- lustres + emblème
		lampGlobe(m, B, 0, 26, 7, 2.6)
		lampGlobe(m, B, 0, 26, 17, 2.6)
		local crest = Box(m, "Crest", B, -2.2, 2.2, MEZZ + 12.2, MEZZ + 16.4, zb0 - 0.2, zb0, GOLD, M.Metal)
		CityKit.Text(crest, Enum.NormalId.Front, "🧠", RED, nil, Enum.Font.GothamBlack, 120, 20)
		-- vraies lumières douces (allumées quand la caméra est dedans)
		for _, z in ipairs({ 7, 17 }) do
			local holder = Box(m, "LightHolder", B, -0.2, 0.2, 24.8, 25.2, z - 0.2, z + 0.2, WHITE, M.SmoothPlastic)
			holder.Transparency = 1
			local light = Instance.new("PointLight")
			light.Range = 42
			light.Brightness = 0.9
			light.Color = rgb(255, 236, 210)
			light.Shadows = false
			light.Enabled = false
			light.Parent = holder
			table.insert(st.Lights, light)
		end
	end)

	-- 5. aile gauche : salle d'attente (devant) + bureau du maire (fond)
	table.insert(jobs, function()
		local x0, x1 = -xi, -ATRIUM
		-- cloison avec porte (4,8 x 8)
		wallWithHoles(m, "Partition", B, x0, x1 - 0.9, FLOOR, MEZZ - MEZZ_T, PARTITION - 0.2, PARTITION + 0.2, { { -24.8, -20, FLOOR, FLOOR + 8 } }, STONE:Lerp(WOOD, 0.08), M.SmoothPlastic)
		Box(m, "Partition", B, x1 - 0.2, x1 + 0.2, FLOOR, MEZZ - MEZZ_T, PARTITION + 0.9, zb0, STONE:Lerp(WOOD, 0.08), M.SmoothPlastic, true)
		-- salle d'attente : 3 rangées de 4 chaises tournées vers l'écran d'appel
		for r = 0, 2 do
			for c = 0, 3 do
				local x = -28.4 + c * 2.6
				local z = 4 + r * 3.4
				chair(m, B * CFrame.new(x, FLOOR, z) * CFrame.Angles(0, math.pi, 0), rgb(40, 110, 170))
			end
		end
		npc(m, "elder", 921, B * CFrame.new(-25.8, FLOOR, 4) * CFrame.Angles(0, math.pi, 0), "sit", nil, SEAT_H)
		local screen = sign(m, B * CFrame.new(0, 0, PARTITION - 0.2), -28, -21, FLOOR + 6.4, FLOOR + 9.2, 0, "🎟️ N° 42  →  " .. Locale.T("Desk") .. " 2", rgb(120, 255, 160), INK)
		CityKit.Glow(screen)
		-- distributeur de tickets près de l'entrée
		local T = B * CFrame.new(-15.2, FLOOR, 2.4)
		Box(m, "TicketMachine", T, -0.6, 0.6, 0, 4.6, -0.5, 0.5, rgb(40, 110, 170), M.SmoothPlastic, true)
		local tag = Box(m, "TicketTag", T, -0.5, 0.5, 3.4, 4.4, 0.5, 0.56, WHITE, M.SmoothPlastic)
		CityKit.Text(tag, Enum.NormalId.Back, "🎟️ " .. Locale.T("Take a number"), rgb(40, 110, 170), WHITE, Enum.Font.GothamBold, 30, 30)
		Column(m, "PlantPot", B, -30, 13.2, FLOOR, FLOOR + 1.8, 1.6, WHITE, M.SmoothPlastic)
		CityKit.Egg(m, "Plant", B * CFrame.new(-30, FLOOR + 3.4, 13.2), Vector3.new(2.4, 3.6, 2.4), rgb(70, 140, 70), M.Grass)
		-- BUREAU DU MAIRE
		local O = B * CFrame.new(-22, FLOOR, 21.5)
		Box(m, "Rug", O, -5, 5, 0.03, 0.07, -4.5, 2.8, rgb(30, 60, 110), M.Fabric)
		desk(m, O, 6.4, WOOD_D, true)
		Box(m, "DeskLeather", O, -2.6, 2.6, TABLE_H, TABLE_H + 0.03, -1.0, 0.6, rgb(40, 90, 60), M.Fabric)
		local plate = Box(m, "NamePlate", O, 1.4, 2.8, TABLE_H, TABLE_H + 0.5, -1.15, -0.95, GOLD, M.Metal)
		CityKit.Text(plate, Enum.NormalId.Front, Locale.T("The Mayor"), INK, GOLD, Enum.Font.Garamond, 30, 40)
		-- fauteuil du maire (derrière, face au bureau)
		local A = O * CFrame.new(0, 0, 2.4)
		Box(m, "MayorChair", A, -1.3, 1.3, 0, SEAT_H, -1.1, 1.1, rgb(120, 30, 40), M.Fabric, true)
		Box(m, "MayorChairBack", A, -1.3, 1.3, SEAT_H, 5.2, 0.8, 1.15, rgb(120, 30, 40), M.Fabric)
		npc(m, "salesperson", 931, O * CFrame.new(-0.8, 0, 2.2), "talk")
		-- deux chaises de visiteurs + un visiteur assis
		for k, x in ipairs({ -1.6, 1.6 }) do
			chair(m, O * CFrame.new(x, 0, -3.0) * CFrame.Angles(0, math.pi, 0), rgb(150, 110, 70))
			local _ = k
		end
		-- drapeaux, bibliothèque, portrait
		for k, x in ipairs({ -4.4, 4.4 }) do
			Column(m, "FlagPole", O, x, 3.6, 0, 9.4, 0.2, GOLD, M.Metal)
			Box(m, "Flag", O, x + 0.1, x + 2.3, 5.6, 9.0, 3.55, 3.65, k == 1 and rgb(236, 90, 150) or rgb(150, 120, 230), M.Fabric)
		end
		local S = B * CFrame.new(-xi, FLOOR, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		Box(m, "Bookcase", S, 16.5, 24.5, 0, 9.5, -1.4, 0, WOOD_D, M.Wood, true)
		for k = 0, 4 do
			local y = 1.2 + k * 1.75
			Box(m, "BookRow", S, 16.9, 24.1, y, y + 1.3, -1.3, -0.1, ({ rgb(140, 40, 40), rgb(40, 70, 130), rgb(40, 110, 70), rgb(200, 160, 60), rgb(110, 60, 120) })[k + 1], M.SmoothPlastic)
		end
		local P = B * CFrame.new(-22, FLOOR, zb0)
		Box(m, "PortraitFrame", P, -2, 2, 4.6, 10, -0.25, 0, GOLD, M.Metal)
		local canvas = Box(m, "Portrait", P, -1.6, 1.6, 5.0, 9.6, -0.32, -0.25, rgb(80, 60, 70), M.SmoothPlastic)
		CityKit.Text(canvas, Enum.NormalId.Front, "🧑‍💼", WHITE, rgb(80, 60, 70), Enum.Font.GothamBold, 60, 20)
		sign(m, B * CFrame.new(-22.4, 0, PARTITION - 0.2), -2.8, 2.8, FLOOR + 8.3, FLOOR + 9.3, 0, "🎗️ " .. Locale.T("Mayor's office"), WHITE, RED)
	end)

	-- 6. aile droite : guichets (devant) + salle du conseil (fond)
	table.insert(jobs, function()
		local x0, x1 = ATRIUM, xi
		wallWithHoles(m, "Partition", B, x0 + 0.9, x1, FLOOR, MEZZ - MEZZ_T, PARTITION - 0.2, PARTITION + 0.2, { { 20, 24.8, FLOOR, FLOOR + 8 } }, STONE:Lerp(WOOD, 0.08), M.SmoothPlastic)
		Box(m, "Partition", B, x0 - 0.2, x0 + 0.2, FLOOR, MEZZ - MEZZ_T, PARTITION + 0.9, zb0, STONE:Lerp(WOOD, 0.08), M.SmoothPlastic, true)
		-- guichets : comptoir le long de la cloison, vitres, 3 agents
		local zc = 9.6
		Box(m, "Guichet", B, 15.4, 30.4, FLOOR, FLOOR + COUNTER_H - 0.2, zc, zc + 1.6, rgb(30, 60, 110), M.Wood, true)
		Box(m, "GuichetTop", B, 15.3, 30.5, FLOOR + COUNTER_H - 0.2, FLOOR + COUNTER_H, zc - 0.12, zc + 1.7, MARBLE, M.Marble)
		local g = Box(m, "GuichetGlass", B, 15.4, 30.4, FLOOR + COUNTER_H + 1.0, FLOOR + 8.4, zc + 0.8, zc + 0.86, GLASS, M.Glass)
		g.Transparency = 0.6
		local names = { "Civil registry", "Passports", "Town planning" }
		for k = 0, 2 do
			local x = 17.9 + k * 5
			Box(m, "GuichetPost", B, x + 2.4, x + 2.6, FLOOR + COUNTER_H, FLOOR + 8.4, zc + 0.75, zc + 0.9, GOLD, M.Metal)
			sign(m, B * CFrame.new(0, 0, zc + 0.7), x - 2.1, x + 2.1, FLOOR + 8.6, FLOOR + 9.6, 0, (k + 1) .. " · " .. Locale.T(names[k + 1]), WHITE, rgb(30, 60, 110))
			if k ~= 1 then
				npc(m, ({ "cashier", "salesperson", "worker" })[k + 1], 940 + k, B * CFrame.new(x, FLOOR, zc + 3.0), k == 2 and "type" or "scan")
			end
		end
		-- SALLE DU CONSEIL : tribune contre le mur est, hémicycle de pupitres
		local cx, cz = xi - 1.5, (PARTITION + zb0) / 2 + 0.2
		local T = B * CFrame.new(cx, FLOOR, cz) * CFrame.Angles(0, math.pi / 2, 0)
		Box(m, "Dais", T, -4.5, 4.5, 0, 0.8, -1.6, 1.4, WOOD_D, M.Wood, true)
		Box(m, "PresidentDesk", T, -3.2, 3.2, 0.8, 0.8 + COUNTER_H, -1.6, -0.6, WOOD, M.Wood, true)
		Box(m, "PresidentTop", T, -3.3, 3.3, 0.8 + COUNTER_H, 0.9 + COUNTER_H, -1.7, -0.5, WOOD_D, M.Wood)
		npc(m, "elder", 950, T * CFrame.new(0, 0.8, 0.5), "talk")
		local emblem = Box(m, "CouncilEmblem", T, -2, 2, 6.2, 10.2, 1.25, 1.35, GOLD, M.Metal)
		CityKit.Text(emblem, Enum.NormalId.Front, "⚖️", INK, nil, Enum.Font.GothamBlack, 60, 20)
		for row = 0, 1 do
			local r = 4.6 + row * 2.6
			for k = -2, 2 do
				local a = k * math.rad(row == 0 and 22 or 17)
				-- pupitre tourné vers la tribune
				local P = T * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
				Box(m, "CouncilDesk", P, -1.2, 1.2, 0, TABLE_H, 0.0, 0.8, WOOD, M.Wood, true)
				chair(m, P * CFrame.new(0, 0, -1.4) * CFrame.Angles(0, math.pi, 0), rgb(30, 60, 110))
				if row == 0 and k == 2 then
					npc(m, ({ "pedestrian", "salesperson", "elder", "shopper" })[(k + row) % 4 + 1], 960 + row * 5 + k, P * CFrame.new(0, 0, -1.4) * CFrame.Angles(0, math.pi, 0), "sit", "none", SEAT_H)
				end
			end
		end
		sign(m, B * CFrame.new(22.4, 0, PARTITION - 0.2), -2.8, 2.8, FLOOR + 8.3, FLOOR + 9.3, 0, "⚖️ " .. Locale.T("Council chamber"), WHITE, rgb(30, 60, 110))
	end)

	-- 7. étage : bureaux ouverts (gauche) + archives (droite)
	table.insert(jobs, function()
		for i = 0, 2 do
			for j = 0, 1 do
				local x = -28 + i * 5.2
				local z = 4 + j * 9
				desk(m, B * CFrame.new(x, MEZZ, z), 4, rgb(230, 230, 232), true)
				chair(m, B * CFrame.new(x, MEZZ, z + 2.2), rgb(60, 64, 76))
				if i == 1 and j == 0 then
					npc(m, "salesperson", 970 + i * 2 + j, B * CFrame.new(x, MEZZ, z + 2.2), "type", "none", SEAT_H)
				end
			end
		end
		Column(m, "WaterCooler", B, -16, 23.5, MEZZ, MEZZ + 3.4, 1.3, WHITE, M.SmoothPlastic, true)
		Column(m, "WaterBottle", B, -16, 23.5, MEZZ + 3.4, MEZZ + 5, 1.1, rgb(150, 200, 240), M.Glass)
		sign(m, B * CFrame.new(-22, 0, zf1 + 0.2) * CFrame.Angles(0, math.pi, 0), -3, 3, MEZZ + 11, MEZZ + 12.2, 0, "🗂️ " .. Locale.T("Town services"), WHITE, rgb(30, 60, 110))
		-- archives : rayonnages de boîtes
		for r = 0, 3 do
			local z = 3.5 + r * 5
			local S = B * CFrame.new(22.4, MEZZ, z)
			Box(m, "ArchiveRack", S, -7, 7, 0, 7.6, -0.9, 0.9, rgb(120, 126, 136), M.Metal, true)
			for k = 0, 3 do
				local y = 0.6 + k * 1.75
				for sz = -1, 1, 2 do
					Box(m, "ArchiveBoxes", S, -6.8, 6.8, y, y + 1.2, sz * 0.92 - 0.05, sz * 0.92 + 0.05, ({ rgb(200, 170, 120), rgb(220, 200, 160), rgb(180, 150, 110) })[(k + r) % 3 + 1], M.SmoothPlastic)
				end
			end
		end
		lampGlobe(m, B, -22, 29, 13, 1.6)
		lampGlobe(m, B, 22, 29, 13, 1.6)
	end)
	return jobs
end

local function destroy(st: State)
	if st.Model then
		st.Model:Destroy()
		st.Model = nil
		stats.Destroys += 1
	end
	st.Jobs = nil
	st.Built = false
	table.clear(st.Screens)
	table.clear(st.Lights)
	for _, h in ipairs(st.Hidden) do
		if h.Part.Parent then
			h.Part.LocalTransparencyModifier = h.Mod
			h.Part.CanCollide = h.Collide
		end
	end
	table.clear(st.Hidden)
end

local function runJobs(st: State)
	local jobs = st.Jobs
	if not jobs then
		return
	end
	local t0 = os.clock()
	repeat
		local job = jobs[st.JobIndex]
		if job then
			local ok, err = pcall(job)
			if not ok then
				warn("[TownHallInterior] " .. tostring(err))
			end
		end
		st.JobIndex += 1
	until st.JobIndex > #jobs or os.clock() - t0 > JOB_BUDGET
	if st.JobIndex > #jobs then
		st.Jobs = nil
		st.Built = true
		stats.Builds += 1
		st.Parts = st.Model and count(st.Model) or 0
		stats.Parts = st.Parts
		refreshScreens(st)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function TownHallInterior.Attach(hall: Model, folder: Instance, feeds: any)
	TownHallInterior.Detach()
	local B = hall:GetAttribute("FacadeCF")
	if typeof(B) ~= "CFrame" then
		return
	end
	state = {
		Hall = hall,
		Folder = folder,
		B = B,
		W = tonumber(hall:GetAttribute("W")) or 64,
		D = tonumber(hall:GetAttribute("D")) or 26,
		H = tonumber(hall:GetAttribute("Height")) or 34,
		Feeds = feeds,
		Model = nil,
		Jobs = nil,
		JobIndex = 1,
		Built = false,
		Hidden = {},
		Screens = {},
		ScreenTimer = 0,
		Lights = {},
		LightsOn = false,
		Parts = 0,
	}
end

local function inside(st: State, p: Vector3): boolean
	local l = st.B:PointToObjectSpace(p)
	return math.abs(l.X) < st.W / 2 and l.Z > 0 and l.Z < st.D and l.Y > 0 and l.Y < ROOF
end

function TownHallInterior.Step(position: Vector3, dt: number)
	local st = state
	if not st then
		return
	end
	if not st.Hall.Parent then
		destroy(st)
		state = nil
		return
	end
	local centre = (st.B * CFrame.new(0, 0, st.D / 2)).Position
	local d = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z).Magnitude
	if (st.Built or st.Jobs) and d > BUILD_OUT then
		destroy(st)
		return
	end
	if not st.Built and not st.Jobs and d <= BUILD_IN then
		local m = Instance.new("Model")
		m.Name = "TownHallInterior"
		m.Parent = st.Folder
		st.Model = m
		st.Jobs = jobsFor(st, m)
		st.JobIndex = 1
	end
	if st.Jobs then
		runJobs(st)
		return
	end
	if st.Built then
		st.ScreenTimer += dt
		if st.ScreenTimer >= 2 and d < 90 then
			st.ScreenTimer = 0
			refreshScreens(st)
		end
		local camera = workspace.CurrentCamera
		local eye = camera and camera.CFrame.Position or position
		local on = inside(st, eye)
		if on ~= st.LightsOn then
			st.LightsOn = on
			for _, l in ipairs(st.Lights) do
				l.Enabled = on
			end
		end
	end
end

function TownHallInterior.Detach()
	local st = state
	if st then
		destroy(st)
	end
	state = nil
end

function TownHallInterior.Debug(): any
	local st = state
	return {
		Stats = stats,
		Built = st and st.Built or false,
		Parts = st and st.Parts or 0,
		Model = st and st.Model,
		Frame = st and st.B,
		-- tout construire d'un coup (tests / rendus)
		BuildNow = function()
			local s = state
			if not s then
				return
			end
			if not s.Built and not s.Jobs then
				local m = Instance.new("Model")
				m.Name = "TownHallInterior"
				m.Parent = s.Folder
				s.Model = m
				s.Jobs = jobsFor(s, m)
				s.JobIndex = 1
			end
			for _ = 1, 50 do
				if not s.Jobs then
					break
				end
				local jobs = s.Jobs :: { () -> () }
				local job = jobs[s.JobIndex]
				if job then
					local ok, err = pcall(job)
					if not ok then
						warn("[TownHallInterior] " .. tostring(err))
					end
				end
				s.JobIndex += 1
				if s.JobIndex > #jobs then
					s.Jobs = nil
					s.Built = true
					s.Parts = s.Model and count(s.Model) or 0
					stats.Parts = s.Parts
					refreshScreens(s)
				end
			end
		end,
	}
end

return TownHallInterior
