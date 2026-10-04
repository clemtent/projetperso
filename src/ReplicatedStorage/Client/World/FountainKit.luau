--[[
	FountainKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FountainKit

	⛲ Dopamine Town (v11, PARK11) : de VRAIES fontaines, côté CLIENT
	("les fontaines sont nulles"). L'eau n'est plus faite de perles et de
	bâtons : ce sont des surfaces continues qui vivent.
	  - JETS EN ARC : une veine d'eau continue (tronçons cylindriques qui
	    s'affinent le long d'une parabole), qui scintille, avec des "paquets"
	    plus clairs qui filent le long de la courbe à la vitesse de l'eau, et
	    des ronds qui s'élargissent là où elle tombe ;
	  - NAPPES : l'eau déborde des vasques en un voile circulaire (panneaux
	    jointifs qui partent vers l'extérieur puis tombent), avec des filets
	    brillants qui DESCENDENT le long du voile et une couronne d'écume au
	    pied ;
	  - GERBES verticales (le panache monte, s'ouvre en ombrelle et retombe
	    dans la vasque), jets "dansants" qui montent et descendent en vague ;
	  - surface de l'eau transparente qui respire, reflets qui scintillent,
	    fond en mosaïque, pièces au fond ;
	  - pierre : margelle moulurée assez large pour s'asseoir (dessus à
	    1,85 : SCALE11), socle cannelé, feuilles d'acanthe, vasques à
	    rebord, bronze patiné (grenouilles, lotus).
	Styles :
	  "Tiered"   grande fontaine à 2 vasques (cœur d'un parc), R 11 ;
	  "Jets"     bassin moderne en granit, 9 jets dansants, 13 x 13 ;
	  "Basin"    petite fontaine de square (vasque + ombrelle), R 5,5 ;
	  "Wallace"  fontaine à boire en fonte (4 cariatides, dôme), ~10 de haut.
	Tout est ancré, sans collision (sauf margelle / socle : on s'y cogne),
	animé par CFrame / Size / Transparency (≤ 30 Hz, rien de créé par image).
	Aucune lumière, aucun son.

	API :
	  FountainKit.Build(parent, F: CFrame, style, seed?) -> fx   F = centre au sol
	  FountainKit.Step(fx, t)       (CityKit.Actor / TownPlazaFx...)
	  FountainKit.Size(style) -> rayon d'emprise
	  FountainKit.Water(parent) -> kit d'eau (utilisé par TownFountainFx)
]]

local ParkKit = require(script.Parent.ParkKit)

local FountainKit = {}

local M = ParkKit.M
local rgb = ParkKit.rgb
local TAU = ParkKit.TAU
local Part, Box, Column, Rod, Egg, Ring = ParkKit.Part, ParkKit.Box, ParkKit.Column, ParkKit.Rod, ParkKit.Egg, ParkKit.Ring
local hash = ParkKit.Hash

local WATER = rgb(178, 222, 242)
local WATER_LIGHT = rgb(226, 245, 255)
local FOAM = rgb(244, 251, 255)
local STONE = rgb(226, 218, 204)
local STONE_D = rgb(198, 188, 172)
local STONE_L = rgb(240, 234, 222)
local MOSAIC = rgb(58, 120, 132)
local BRONZE = rgb(112, 148, 120) -- bronze patiné (vert-de-gris)
local BRONZE_D = rgb(84, 112, 92)
local GRANITE = rgb(120, 122, 128)
local GRANITE_L = rgb(168, 170, 176)
local IRON = rgb(30, 70, 52)

local SIZES = { Tiered = 12.4, Jets = 9.6, Basin = 6.4, Wallace = 2.6 }
function FountainKit.Size(style: string): number
	return SIZES[style] or 8
end

----------------------------------------------------------------------
-- Kit d'eau : veines, nappes, gerbes, ronds, reflets
----------------------------------------------------------------------

export type Water = {
	Parent: Instance,
	Streams: { any },
	Sheets: { any },
	Plumes: { any },
	Ripples: { any },
	Sparkles: { any },
	Surfaces: { any },
	Last: number,
}

local function waterPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: string?): BasePart
	local p = Part(parent, name, size, cf, color, M.Glass, shape)
	p.Transparency = transparency
	p.CastShadow = false
	p.Reflectance = 0.06
	return p
end

function FountainKit.Water(parent: Instance): Water
	return { Parent = parent, Streams = {}, Sheets = {}, Plumes = {}, Ripples = {}, Sparkles = {}, Surfaces = {}, Last = -1 }
end

-- Point d'une parabole de p0 à p1, flèche h (au-dessus de la corde)
local function arcAt(p0: Vector3, p1: Vector3, h: number, u: number): Vector3
	return p0:Lerp(p1, u) + Vector3.new(0, 4 * h * u * (1 - u), 0)
end

-- Ronds dans l'eau en `p` (surface), rayon max r
local function addRipples(W: Water, p: Vector3, r: number, phase: number, count: number?)
	-- (chaque rond à sa hauteur : 4 niveaux espacés de 0,03, jamais deux faces
	-- confondues ; l'écume au-dessus)
	for k = 0, (count or 2) - 1 do
		-- niveau libre : aucun rond voisin (qui pourrait le recouvrir) au même niveau
		local used = {}
		for _, other in ipairs(W.Ripples) do
			if Vector3.new(other.P.X - p.X, 0, other.P.Z - p.Z).Magnitude < other.R + r + 0.6 and math.abs(other.Base - p.Y) < 0.5 then
				used[other.Level] = true
			end
		end
		local level = 0
		while used[level] and level < 6 do
			level += 1
		end
		local q = p + Vector3.new(0, 0.03 + level * 0.025, 0)
		local ring = waterPart(W.Parent, "Ripple", Vector3.new(0.02, 0.4, 0.4), CFrame.new(q) * ParkKit.UPRIGHT, FOAM, 0.4, "Cyl")
		table.insert(W.Ripples, { Part = ring, P = q, R = r, Phase = phase + k / (count or 2), Level = level, Base = p.Y })
	end
	-- (écume au point d'impact)
	local foam = waterPart(W.Parent, "Foam", Vector3.new(0.03, r * 0.55, r * 0.55), CFrame.new(p + Vector3.new(0, 0.34, 0)) * ParkKit.UPRIGHT, FOAM, 0.35, "Cyl")
	table.insert(W.Sparkles, { Part = foam, Base = 0.3, Amp = 0.15, Speed = 9 + phase * 3, Phase = phase * 7 })
end

-- Veine d'eau en arc de p0 (bec) à p1 (surface), flèche h, diamètre d0 -> d1
function FountainKit.Stream(W: Water, p0: Vector3, p1: Vector3, h: number, d0: number, d1: number, phase: number?, ripple: number?)
	local n = math.clamp(math.floor((p1 - p0).Magnitude / 1.1) + 3, 5, 10)
	local segs = {}
	for i = 0, n - 1 do
		local a = arcAt(p0, p1, h, i / n)
		local b = arcAt(p0, p1, h, (i + 1) / n)
		local d = d0 + (d1 - d0) * (i + 0.5) / n
		-- (tronçons qui se chevauchent un peu : veine continue)
		local dir = (b - a)
		local ext = dir.Unit * math.min(0.08, dir.Magnitude * 0.1)
		local seg = waterPart(W.Parent, "Stream", Vector3.new(dir.Magnitude + 0.16, d, d), ParkKit.RodCF(a - ext, b + ext), i % 2 == 0 and WATER_LIGHT or WATER, 0.32)
		table.insert(segs, seg)
	end
	-- 2 "paquets" plus clairs qui filent le long de la veine
	local beads = {}
	for k = 1, 2 do
		local bead = waterPart(W.Parent, "StreamPulse", Vector3.new(0.6, d0 * 1.15, d0 * 1.15), CFrame.new(p0), FOAM, 0.2, "Cyl")
		table.insert(beads, bead)
	end
	local s = { P0 = p0, P1 = p1, H = h, D0 = d0, D1 = d1, Segs = segs, Beads = beads, Phase = phase or 0, Rate = 0.9 + hash(p0.X, p0.Z) * 0.3 }
	table.insert(W.Streams, s)
	if ripple ~= 0 then
		addRipples(W, p1 + Vector3.new(0, 0.02, 0), ripple or 1.6, phase or 0)
	end
	return s
end

-- Nappe circulaire : déborde du rebord (rayon r0, hauteur y0) en partant
-- vers l'extérieur (r0 -> r1 en descendant de drop), puis tombe jusqu'à
-- y1 (rayon r2) ; n panneaux autour de F
function FountainKit.Sheet(W: Water, F: CFrame, r0: number, y0: number, r1: number, drop: number, r2: number, y1: number, n: number?, rippleR: number?)
	local count = n or 20
	local panels = {}
	local streaks = {}
	for i = 0, count - 1 do
		local a = (i + 0.5) / count * TAU
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = F.Position
		local pA = base + dir * r0 + Vector3.new(0, y0, 0)
		local pB = base + dir * r1 + Vector3.new(0, y0 - drop, 0)
		local pC = base + dir * r2 + Vector3.new(0, y1, 0)
		-- largeur du panneau au rayon le plus grand (jointif)
		for seg = 1, 2 do
			local a0, b0 = if seg == 1 then pA else pB, if seg == 1 then pB else pC
			local rr = if seg == 1 then r1 else math.max(r1, r2)
			local w = 2 * rr * math.sin(math.pi / count) * 1.06
			local mid = (a0 + b0) / 2
			local len = (b0 - a0).Magnitude + 0.06
			-- (panneau : largeur = tangente, longueur = le long de la chute, mince vers l'extérieur)
			local tangent = Vector3.new(-dir.Z, 0, dir.X)
			local down = (b0 - a0).Unit
			local cf = CFrame.fromMatrix(mid, tangent, -down)
			local p = waterPart(W.Parent, "Sheet", Vector3.new(w, len, 0.05), cf, WATER_LIGHT, seg == 1 and 0.56 or 0.7)
			table.insert(panels, { Part = p, Base = p.Transparency, Phase = i * 0.7 + seg })
		end
	end
	-- filets brillants qui descendent (10 autour)
	for k = 0, 9 do
		local a = (k + hash(k, r0) * 0.6) / 10 * TAU
		local streak = waterPart(W.Parent, "SheetStreak", Vector3.new(0.12, 0.9, 0.07), CFrame.new(F.Position), FOAM, 0.25)
		table.insert(streaks, { Part = streak, A = a, Phase = hash(k, 7.3 + r0) })
	end
	local sh = { F = F, R0 = r0, Y0 = y0, R1 = r1, Drop = drop, R2 = r2, Y1 = y1, Panels = panels, Streaks = streaks }
	table.insert(W.Sheets, sh)
	-- couronne d'écume au pied du voile + quelques ronds
	local foamRing = Ring(W.Parent, "SheetFoam", F, r2 + 0.15, 0.7, y1 + 0.24, y1 + 0.29, math.min(count, 16), FOAM, M.Glass)
	for _, p in ipairs(foamRing) do
		p.Transparency = 0.3
		p.CastShadow = false
		table.insert(W.Sparkles, { Part = p, Base = 0.3, Amp = 0.18, Speed = 6, Phase = hash(p.Position.X, p.Position.Z) * 6 })
	end
	for k = 0, 3 do
		local a = (k + 0.25) / 4 * TAU
		local rr = rippleR or (r2 + 1.0)
		-- (dans une vasque : petits ronds qui ne débordent pas sur le rebord)
		addRipples(W, F.Position + Vector3.new(math.cos(a) * rr, y1 + 0.02, math.sin(a) * rr), if rippleR then math.min(0.55, rr * 0.5) else math.min(1.4, rr * 0.5), k * 0.37, 1)
	end
	return sh
end

-- Gerbe verticale de `p` (bouche) : monte de h, s'ouvre en ombrelle
-- (8 retombées jusqu'au rayon rFall, hauteur yFall) ; dancing : la hauteur
-- suit une vague (jets dansants)
function FountainKit.Plume(W: Water, p: Vector3, h: number, d: number, rFall: number?, yFall: number?, dancing: number?)
	local n = 5
	local segs = {}
	for i = 1, n do
		table.insert(segs, waterPart(W.Parent, "Plume", Vector3.new(1, d, d), CFrame.new(p), i % 2 == 0 and WATER or WATER_LIGHT, 0.25 + i * 0.03, "Cyl"))
	end
	local crown = {}
	for k = 1, 3 do
		table.insert(crown, waterPart(W.Parent, "PlumeCrown", Vector3.new(d * 1.7, d * 1.7, d * 1.7), CFrame.new(p), FOAM, 0.5, "Ball"))
	end
	local falls = {}
	if rFall and yFall then
		for k = 0, 7 do
			local a = (k + 0.5) / 8 * TAU
			local top = p + Vector3.new(0, h, 0)
			local land = Vector3.new(p.X + math.cos(a) * rFall, yFall, p.Z + math.sin(a) * rFall)
			local s = FountainKit.Stream(W, top, land, 0.35, d * 0.38, d * 0.26, k * 0.13, 0)
			table.insert(falls, s)
		end
	end
	local pl = { P = p, H = h, D = d, Segs = segs, Crown = crown, Dancing = dancing, Falls = falls }
	table.insert(W.Plumes, pl)
	-- (ronds : au pied d'un jet posé sur l'eau, ou sous l'ombrelle)
	if yFall or dancing then
		addRipples(W, Vector3.new(p.X, (yFall or p.Y) + 0.02, p.Z), math.max(1.2, (rFall or 1) * 0.6), hash(p.X, p.Z), 2)
	end
	return pl
end

-- Surface d'eau qui respire (disque) + reflets
function FountainKit.Surface(W: Water, F: CFrame, x: number, z: number, top: number, r: number, sparkles: number?)
	local disc = waterPart(W.Parent, "WaterSurface", Vector3.new(0.12, r * 2, r * 2), F * CFrame.new(x, top - 0.06, z) * ParkKit.UPRIGHT, WATER, 0.32, "Cyl")
	disc.Reflectance = 0.18
	table.insert(W.Surfaces, { Part = disc, Base = 0.32 })
	for k = 1, sparkles or 0 do
		local a = hash(k, r * 3.1) * TAU
		local rr = math.sqrt(hash(k, r + 0.7)) * r * 0.85
		local sp = Part(W.Parent, "Glint", Vector3.new(0.02, 0.35, 0.35), F * CFrame.new(x + math.cos(a) * rr, top + 0.045, z + math.sin(a) * rr) * ParkKit.UPRIGHT, Color3.new(1, 1, 1), M.Neon, "Cyl")
		sp.CastShadow = false
		table.insert(W.Sparkles, { Part = sp, Base = 0.6, Amp = 0.45, Speed = 2.5 + hash(k, 2) * 3, Phase = k * 1.7, Glint = true })
	end
	return disc
end

-- Reflets seuls (sur une eau existante, ex. la fontaine du serveur)
function FountainKit.Glints(W: Water, center: Vector3, top: number, r: number, count: number)
	for k = 1, count do
		local a = hash(k, r * 3.1) * TAU
		local rr = math.sqrt(hash(k, r + 0.7)) * r * 0.9
		local sp = Part(W.Parent, "Glint", Vector3.new(0.02, 0.35, 0.35), CFrame.new(center.X + math.cos(a) * rr, top + 0.045, center.Z + math.sin(a) * rr) * ParkKit.UPRIGHT, Color3.new(1, 1, 1), M.Neon, "Cyl")
		sp.CastShadow = false
		table.insert(W.Sparkles, { Part = sp, Base = 0.6, Amp = 0.45, Speed = 2.5 + hash(k, 2) * 3, Phase = k * 1.7, Glint = true })
	end
end

-- Pose de l'eau au temps t
local function stepStream(s: any, t: number)
	local n = #s.Segs
	for i, seg in ipairs(s.Segs) do
		-- (la veine s'éclaircit et se disperse vers la fin de sa course)
		seg.Transparency = 0.26 + 0.22 * ((i - 0.5) / n) ^ 2 + 0.08 * (0.5 + 0.5 * math.sin(t * 9 + i * 1.3 + s.Phase * 5))
	end
	for k, bead in ipairs(s.Beads) do
		local u = ((t * s.Rate + s.Phase + (k - 1) / #s.Beads) % 1)
		local a = arcAt(s.P0, s.P1, s.H, u)
		local b = arcAt(s.P0, s.P1, s.H, math.min(1, u + 0.04))
		local d = s.D0 + (s.D1 - s.D0) * u
		local step = b - a
		bead.Size = Vector3.new(math.max(0.3, step.Magnitude * 3), d * 1.12, d * 1.12)
		if step.Magnitude > 1e-4 then
			bead.CFrame = ParkKit.RodCF(a, a + step.Unit * 0.01)
		end
		bead.Transparency = 0.15 + 0.5 * u * u
	end
	local _ = n
end

local function stepSheet(sh: any, t: number)
	for _, p in ipairs(sh.Panels) do
		p.Part.Transparency = p.Base + 0.06 * math.sin(t * 5 + p.Phase)
	end
	local base = sh.F.Position
	for _, st in ipairs(sh.Streaks) do
		-- (le filet descend le long du voile, puis recommence en haut)
		local u = (t * 0.9 + st.Phase) % 1
		local dir = Vector3.new(math.cos(st.A), 0, math.sin(st.A))
		local p0 = base + dir * sh.R0 + Vector3.new(0, sh.Y0, 0)
		local p1 = base + dir * sh.R1 + Vector3.new(0, sh.Y0 - sh.Drop, 0)
		local p2 = base + dir * sh.R2 + Vector3.new(0, sh.Y1, 0)
		local L1 = (p1 - p0).Magnitude
		local L2 = (p2 - p1).Magnitude
		local s = u * (L1 + L2)
		local pos, dn
		if s < L1 then
			pos = p0:Lerp(p1, s / L1)
			dn = (p1 - p0).Unit
		else
			pos = p1:Lerp(p2, (s - L1) / math.max(L2, 0.01))
			dn = (p2 - p1).Unit
		end
		local tangent = Vector3.new(-dir.Z, 0, dir.X)
		local outward = tangent:Cross(dn).Unit
		-- (accélère en tombant : le filet s'allonge)
		st.Part.Size = Vector3.new(0.12, 0.5 + u * 1.4, 0.07)
		st.Part.CFrame = CFrame.fromMatrix(pos + outward * 0.04, tangent, -dn)
		st.Part.Transparency = 0.2 + 0.6 * u
	end
end

local function stepPlume(pl: any, t: number)
	local h = pl.H
	if pl.Dancing then
		-- vague : monte, tient, retombe (chaque jet décalé)
		local w = (t * 0.45 + pl.Dancing) % 1
		local k = math.sin(w * math.pi)
		h = pl.H * (0.15 + 0.85 * k * k)
	else
		h = pl.H * (0.94 + 0.06 * math.sin(t * 3.1 + pl.P.X))
	end
	local n = #pl.Segs
	for i, seg in ipairs(pl.Segs) do
		local y0 = (i - 1) / n * h
		local y1 = i / n * h + 0.05
		local d = pl.D * (1 - (i - 1) / n * 0.45)
		seg.Size = Vector3.new(math.max(0.05, y1 - y0), d, d)
		seg.CFrame = CFrame.new(pl.P + Vector3.new(0, (y0 + y1) / 2, 0)) * ParkKit.UPRIGHT
		seg.Transparency = 0.22 + i * 0.04 + 0.06 * math.sin(t * 11 + i)
	end
	for k, c in ipairs(pl.Crown) do
		local a = t * 4 + k * 2.1
		local r = pl.D * 0.5
		c.CFrame = CFrame.new(pl.P + Vector3.new(math.cos(a) * r, h + math.sin(t * 7 + k) * 0.15 - 0.1, math.sin(a) * r))
		c.Transparency = 0.5 + 0.15 * math.sin(t * 6 + k)
	end
end

local function stepRipples(W: Water, t: number)
	for _, r in ipairs(W.Ripples) do
		local u = (t * 0.8 + r.Phase) % 1
		local d = 0.3 + u * r.R * 2
		r.Part.Size = Vector3.new(0.02, d, d)
		r.Part.CFrame = CFrame.new(r.P) * ParkKit.UPRIGHT
		r.Part.Transparency = 0.35 + 0.65 * u
	end
	for _, s in ipairs(W.Sparkles) do
		local v = math.sin(t * s.Speed + s.Phase)
		if s.Glint then
			-- (reflet bref : la plupart du temps invisible)
			s.Part.Transparency = v > 0.75 and (1 - (v - 0.75) * 3) or 1
		else
			s.Part.Transparency = s.Base + s.Amp * v
		end
	end
	for _, s in ipairs(W.Surfaces) do
		s.Part.Transparency = s.Base + 0.04 * math.sin(t * 0.9)
	end
end

function FountainKit.StepWater(W: Water, t: number)
	-- (30 Hz au plus)
	if t - W.Last < 1 / 30 and t >= W.Last then
		return
	end
	W.Last = t
	for _, s in ipairs(W.Streams) do
		stepStream(s, t)
	end
	for _, sh in ipairs(W.Sheets) do
		stepSheet(sh, t)
	end
	for _, pl in ipairs(W.Plumes) do
		stepPlume(pl, t)
	end
	stepRipples(W, t)
end

----------------------------------------------------------------------
-- Pierre et bronze
----------------------------------------------------------------------

-- Bassin rond : marche, mur mouluré, margelle (dessus à 1,85, on s'y
-- assoit), fond en mosaïque, pièces ; eau à `waterY`
local function roundBasin(m: Instance, F: CFrame, R: number, waterY: number, seed: number, stone: Color3?, n: number?)
	local c = stone or STONE
	local sides = n or 28
	Column(m, "BasinStep", F, 0, 0, 0, 0.32, (R + 1.3) * 2, STONE_D, M.Slate, true)
	-- mur (épaisseur 1,0) + plinthe + bandeau
	Ring(m, "BasinWall", F, R - 0.5, 1.0, 0.32, 1.6, sides, c, M.Limestone, true)
	Ring(m, "BasinPlinth", F, R - 0.4, 1.3, 0.32, 0.62, sides, STONE_D, M.Limestone)
	Ring(m, "BasinBand", F, R - 0.43, 1.0, 1.05, 1.18, sides, STONE_L, M.Limestone)
	-- margelle débordante (dessus = assise SCALE11)
	Ring(m, "BasinCoping", F, R - 0.55, 1.5, 1.6, ParkKit.SEAT, sides, STONE_L, M.Limestone, true)
	-- fond (mosaïque) + frise de carreaux
	Column(m, "PoolFloor", F, 0, 0, 0.32, 0.45, (R - 0.95) * 2, MOSAIC, M.Slate)
	for k = 0, 11 do
		local a = k / 12 * TAU
		local rr = R - 2.2
		Box(m, "Tile", F * CFrame.Angles(0, -a, 0), rr - 0.4, rr + 0.4, 0.45, 0.47, -0.4, 0.4, k % 2 == 0 and rgb(236, 210, 120) or rgb(40, 96, 120), M.Slate)
	end
	-- pièces (vœux)
	for k = 1, 9 do
		local a = hash(seed, k) * TAU
		local rr = 2.5 + hash(seed, k + 20) * (R - 5)
		local coin = Part(m, "Coin", Vector3.new(0.04, 0.32, 0.32), F * CFrame.new(math.cos(a) * rr, 0.48, math.sin(a) * rr) * ParkKit.UPRIGHT, k % 3 == 0 and rgb(190, 190, 196) or rgb(214, 172, 80), M.Metal, "Cyl")
		coin.CastShadow = false
	end
	local _ = waterY
end

-- Feuilles d'acanthe autour d'un fût (anneau de 8 feuilles recourbées)
local function acanthus(m: Instance, F: CFrame, y: number, r: number, h: number, color: Color3)
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * TAU
		local p = F * CFrame.Angles(0, -a, 0) * CFrame.new(r, y + h / 2, 0) * CFrame.Angles(0, 0, math.rad(-18))
		Egg(m, "Acanthus", p, Vector3.new(0.5, h, r * 0.9), color, M.Limestone)
		local tip = F * CFrame.Angles(0, -a, 0) * CFrame.new(r + 0.35, y + h * 0.95, 0)
		Egg(m, "AcanthusTip", tip, Vector3.new(0.6, 0.35, r * 0.6), color, M.Limestone)
	end
end

-- Vasque : dessus à y, rayon r ; dessous en coupe, rebord festonné ; eau
local function bowl(m: Instance, W: Water, F: CFrame, y: number, r: number, color: Color3)
	Egg(m, "BowlCup", F * CFrame.new(0, y - 0.55, 0), Vector3.new(r * 2, 1.5, r * 2), color, M.Limestone)
	Column(m, "BowlRim", F, 0, 0, y - 0.35, y, r * 2, color, M.Limestone)
	Ring(m, "BowlLip", F, r - 0.12, 0.34, y - 0.05, y + 0.2, 20, STONE_L, M.Limestone)
	for k = 0, 15 do
		local a = (k + 0.5) / 16 * TAU
		Egg(m, "BowlScallop", F * CFrame.new(math.cos(a) * (r + 0.02), y - 0.32, math.sin(a) * (r + 0.02)), Vector3.new(0.7, 0.55, 0.7), color, M.Limestone)
	end
	FountainKit.Surface(W, F, 0, 0, y + 0.1, r - 0.3, 2)
end

-- Grenouille de bronze (bouche vers -Z du repère G, posée sur la margelle)
local function frog(m: Instance, G: CFrame)
	Egg(m, "FrogBody", G * CFrame.new(0, 0.42, 0.1) * CFrame.Angles(math.rad(-20), 0, 0), Vector3.new(0.95, 0.75, 1.1), BRONZE, M.Metal)
	Egg(m, "FrogHead", G * CFrame.new(0, 0.78, -0.35), Vector3.new(0.85, 0.55, 0.7), BRONZE, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		ParkKit.Ball(m, "FrogEye", (G * CFrame.new(sx * 0.24, 1.05, -0.42)).Position, 0.26, BRONZE_D, M.Metal)
		Egg(m, "FrogLeg", G * CFrame.new(sx * 0.42, 0.2, 0.35), Vector3.new(0.35, 0.3, 0.8), BRONZE_D, M.Metal)
		Egg(m, "FrogHand", G * CFrame.new(sx * 0.3, 0.1, -0.35), Vector3.new(0.3, 0.16, 0.36), BRONZE_D, M.Metal)
	end
	-- (bouche ouverte : la veine part de là)
	return (G * CFrame.new(0, 0.7, -0.72)).Position
end

----------------------------------------------------------------------
-- Styles
----------------------------------------------------------------------

local function buildTiered(m: Model, F: CFrame, seed: number): Water
	local W = FountainKit.Water(m)
	local R = 11
	local WY = 1.35
	roundBasin(m, F, R, WY, seed)
	FountainKit.Surface(W, F, 0, 0, WY, R - 1.0, 10)
	-- socle octogonal + fût cannelé + acanthes
	Column(m, "Pedestal", F, 0, 0, 0.32, 2.5, 4.4, STONE_D, M.Limestone, true)
	Column(m, "PedestalCap", F, 0, 0, 2.5, 2.8, 4.8, STONE_L, M.Limestone)
	acanthus(m, F, 2.8, 1.3, 1.5, STONE)
	Column(m, "Shaft", F, 0, 0, 2.8, 5.4, 1.7, STONE, M.Limestone, true)
	for k = 0, 9 do
		local a = k / 10 * TAU
		Column(m, "Flute", F, math.cos(a) * 0.84, math.sin(a) * 0.84, 3.0, 5.2, 0.22, STONE_L, M.Limestone)
	end
	Column(m, "ShaftRing", F, 0, 0, 5.2, 5.45, 2.1, STONE_L, M.Limestone)
	-- vasque basse (dessus 5,9) + nappe jusqu'au bassin
	bowl(m, W, F, 5.9, 4.3, STONE)
	FountainKit.Sheet(W, F, 4.35, 6.0, 4.75, 0.55, 4.95, WY, 24)
	-- fût haut, boule, vasque haute (8,9) + sa nappe dans la vasque basse
	Column(m, "UpperShaft", F, 0, 0, 6.0, 8.0, 0.95, STONE, M.Limestone)
	ParkKit.Ball(m, "Knob", (F * CFrame.new(0, 7.1, 0)).Position, 1.5, STONE_L, M.Limestone)
	acanthus(m, F, 7.7, 0.55, 0.8, STONE_L)
	bowl(m, W, F, 8.9, 2.3, STONE)
	FountainKit.Sheet(W, F, 2.35, 9.0, 2.65, 0.4, 2.85, 6.0, 16, 3.35)
	-- lotus de bronze + gerbe en ombrelle qui retombe dans la vasque haute
	for k = 0, 5 do
		local a = k / 6 * TAU
		Egg(m, "Lotus", F * CFrame.new(math.cos(a) * 0.45, 9.45, math.sin(a) * 0.45) * CFrame.Angles(0, -a, math.rad(30)), Vector3.new(0.35, 0.9, 0.55), BRONZE, M.Metal)
	end
	-- CLOCHE d'eau : le lotus lance un voile en dôme qui retombe dans la vasque haute
	Column(m, "BellNozzle", F, 0, 0, 9.4, 10.35, 0.36, BRONZE_D, M.Metal)
	FountainKit.Sheet(W, F, 0.2, 10.4, 1.25, -0.3, 1.95, 9.0, 14, 1.2)
	-- 6 grenouilles sur la margelle crachent vers le socle
	for k = 0, 5 do
		local a = (k + 0.5) / 6 * TAU
		local G = F * CFrame.Angles(0, -a, 0) * CFrame.new(R - 0.6, ParkKit.SEAT, 0) * CFrame.Angles(0, math.rad(90), 0)
		local mouth = frog(m, G)
		local land = (F * CFrame.Angles(0, -a, 0) * CFrame.new(3.6, WY, 0)).Position
		FountainKit.Stream(W, mouth, land, 1.9, 0.26, 0.2, k * 0.17, 1.4)
	end
	-- brume au pied des nappes (particules douces, client)
	local mist = Part(m, "Mist", Vector3.new(1, 1, 1), F * CFrame.new(0, WY + 0.2, 0), WATER, M.SmoothPlastic)
	mist.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.Rate = 10
	e.Lifetime = NumberRange.new(1.2, 1.8)
	e.Speed = NumberRange.new(0.6, 1.2)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(FOAM)
	e.LightEmission = 0.2
	mist.Size = Vector3.new(10, 0.2, 10)
	e.Parent = mist
	return W
end

local function buildJets(m: Model, F: CFrame, seed: number): Water
	local W = FountainKit.Water(m)
	local H = 6.5 -- demi-côté du bassin
	local WY = 1.2
	-- dalle de granit autour + bassin carré à margelle assise (1,85)
	Box(m, "Apron", F, -H - 2.6, H + 2.6, 0, 0.2, -H - 2.6, H + 2.6, GRANITE_L, M.Granite, true)
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local sx, sz = side[1], side[2]
		local G = F * CFrame.new(sx * H, 0, sz * H) * CFrame.Angles(0, sx ~= 0 and math.rad(90) or 0, 0)
		-- (murs le long de x entiers, murs le long de z entre eux : aucun recouvrement)
		local full = sz ~= 0
		local wl = full and H + 0.6 or H - 0.6
		local cl = full and H + 0.85 or H - 0.85
		Box(m, "JetWall", G, -wl, wl, 0.2, 1.55, -0.6, 0.6, GRANITE, M.Granite, true)
		Box(m, "JetCoping", G, -cl, cl, 1.55, ParkKit.SEAT, -0.85, 0.85, GRANITE_L, M.Granite, true)
	end
	Box(m, "JetFloor", F, -H + 0.6, H - 0.6, 0.2, 0.35, -H + 0.6, H - 0.6, rgb(44, 70, 86), M.Slate)
	-- grille de lumières au fond (anneaux inox des buses)
	FountainKit.Surface(W, F, 0, 0, WY, 0, 0)
	local surf = W.Surfaces[#W.Surfaces].Part
	surf.Shape = Enum.PartType.Block
	surf.Size = Vector3.new(2 * H - 1.2, 0.12, 2 * H - 1.2)
	surf.CFrame = F * CFrame.new(0, WY - 0.06, 0)
	for i = -1, 1 do
		for k = -1, 1 do
			local p = (F * CFrame.new(i * 3.6, WY, k * 3.6)).Position
			Column(m, "Nozzle", F, i * 3.6, k * 3.6, 0.35, WY + 0.3, 0.7, rgb(200, 204, 210), M.Metal)
			local wave = ((i + 1) + (k + 1)) * 0.11 + (i == 0 and k == 0 and 0.5 or 0)
			FountainKit.Plume(W, p, (i == 0 and k == 0) and 8 or 5.5, 0.34, nil, nil, wave)
		end
	end
	-- 4 arcs croisés depuis les coins
	for c = 0, 3 do
		local a = c / 4 * TAU + math.pi / 4
		local p0 = F.Position + Vector3.new(math.cos(a) * (H - 0.5) * 1.41, WY + 0.4, math.sin(a) * (H - 0.5) * 1.41)
		local p1 = F.Position + Vector3.new(math.cos(a) * 1.5, WY, math.sin(a) * 1.5)
		Column(m, "CornerSpout", F, math.cos(a) * (H - 0.5) * 1.41, math.sin(a) * (H - 0.5) * 1.41, WY - 0.1, WY + 0.45, 0.5, rgb(200, 204, 210), M.Metal)
		FountainKit.Stream(W, p0, p1, 3.2, 0.24, 0.18, c * 0.25, 1.2)
	end
	local _ = seed
	return W
end

local function buildBasin(m: Model, F: CFrame, seed: number): Water
	local W = FountainKit.Water(m)
	local R = 5.5
	local WY = 1.3
	roundBasin(m, F, R, WY, seed, STONE, 20)
	FountainKit.Surface(W, F, 0, 0, WY, R - 1.0, 5)
	Column(m, "Pedestal", F, 0, 0, 0.32, 1.6, 2.4, STONE_D, M.Limestone, true)
	acanthus(m, F, 1.6, 0.8, 1.0, STONE)
	Column(m, "Shaft", F, 0, 0, 1.6, 3.8, 0.9, STONE, M.Limestone)
	bowl(m, W, F, 4.2, 2.2, STONE)
	FountainKit.Sheet(W, F, 2.25, 4.3, 2.55, 0.35, 2.75, WY, 16)
	ParkKit.Ball(m, "Finial", (F * CFrame.new(0, 4.6, 0)).Position, 0.8, BRONZE, M.Metal)
	FountainKit.Sheet(W, F, 0.18, 5.05, 0.95, -0.22, 1.5, 4.3, 12, 0.9)
	return W
end

-- Fontaine à boire en fonte (type Wallace, domaine public) : socle,
-- 4 cariatides stylisées, dôme à écailles, filet d'eau sur la grille
local function buildWallace(m: Model, F: CFrame, seed: number): Water
	local W = FountainKit.Water(m)
	Column(m, "WPlinth", F, 0, 0, 0, 0.6, 3.6, IRON, M.Metal, true)
	Column(m, "WBase", F, 0, 0, 0.6, 2.6, 2.6, IRON, M.Metal, true)
	Column(m, "WBaseRing", F, 0, 0, 2.6, 2.95, 3.2, IRON, M.Metal)
	for k = 0, 7 do
		local a = k / 8 * TAU
		Column(m, "WBaseRib", F, math.cos(a) * 1.3, math.sin(a) * 1.3, 0.7, 2.5, 0.22, IRON, M.Metal)
	end
	-- grille (où tombe l'eau)
	Column(m, "WGrate", F, 0, 0, 2.95, 3.02, 1.6, rgb(20, 40, 30), M.DiamondPlate)
	-- 4 cariatides : jambes en robe (fuseau), buste, tête, bras levés
	for k = 0, 3 do
		local a = (k + 0.5) / 4 * TAU
		local G = F * CFrame.Angles(0, -a, 0) * CFrame.new(1.15, 3.0, 0) * CFrame.Angles(0, math.rad(90), 0)
		Egg(m, "WRobe", G * CFrame.new(0, 1.5, 0), Vector3.new(0.75, 3.1, 0.7), IRON, M.Metal)
		Egg(m, "WBust", G * CFrame.new(0, 3.25, 0), Vector3.new(0.7, 0.9, 0.55), IRON, M.Metal)
		ParkKit.Ball(m, "WHead", (G * CFrame.new(0, 3.95, 0)).Position, 0.55, IRON, M.Metal)
		Rod(m, "WArm", (G * CFrame.new(-0.3, 3.5, 0)).Position, (G * CFrame.new(-0.25, 4.6, 0)).Position, 0.18, IRON, M.Metal)
		Rod(m, "WArm", (G * CFrame.new(0.3, 3.5, 0)).Position, (G * CFrame.new(0.25, 4.6, 0)).Position, 0.18, IRON, M.Metal)
	end
	-- dôme à écailles + bord festonné + pointe
	Column(m, "WDomeRim", F, 0, 0, 7.6, 7.9, 3.4, IRON, M.Metal)
	for k = 0, 11 do
		local a = (k + 0.5) / 12 * TAU
		Egg(m, "WFestoon", F * CFrame.new(math.cos(a) * 1.65, 7.45, math.sin(a) * 1.65), Vector3.new(0.6, 0.45, 0.6), IRON, M.Metal)
	end
	Egg(m, "WDome", F * CFrame.new(0, 8.2, 0), Vector3.new(3.1, 1.9, 3.1), IRON, M.Metal)
	for k = 0, 7 do
		local a = k / 8 * TAU
		Rod(m, "WDomeRib", (F * CFrame.new(math.cos(a) * 1.5, 7.9, math.sin(a) * 1.5)).Position, (F * CFrame.new(0, 9.1, 0)).Position, 0.12, IRON:Lerp(Color3.new(0, 0, 0), 0.2), M.Metal)
	end
	Column(m, "WSpire", F, 0, 0, 9.0, 9.9, 0.3, IRON, M.Metal)
	ParkKit.Ball(m, "WSpireTop", (F * CFrame.new(0, 10, 0)).Position, 0.35, IRON, M.Metal)
	-- filet d'eau continu du dôme à la grille
	local top = (F * CFrame.new(0, 7.55, 0)).Position
	local bottom = (F * CFrame.new(0, 3.05, 0)).Position
	FountainKit.Stream(W, top, bottom, 0, 0.16, 0.12, hash(seed, 3), 0.7)
	return W
end

local BUILDERS = { Tiered = buildTiered, Jets = buildJets, Basin = buildBasin, Wallace = buildWallace }
FountainKit.STYLES = { "Tiered", "Jets", "Basin", "Wallace" }

function FountainKit.Build(parent: Instance, F: CFrame, style: string, seed: number?): any
	local m = Instance.new("Model")
	m.Name = "Fountain" .. style
	local build = BUILDERS[style] or buildBasin
	local W = build(m, F, seed or 1)
	m.Parent = parent
	return { Model = m, Water = W, Style = style }
end

function FountainKit.Step(fx: any, t: number)
	if fx and fx.Water and fx.Model.Parent then
		FountainKit.StepWater(fx.Water, t)
	end
end

return FountainKit
