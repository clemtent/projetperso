--[[
	HouseDetail (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseDetail

	(v10 HOUSE10) 🏡 Éléments RÉALISTES de l'extérieur des maisons 3D, dans le
	repère local d'une maison (HouseKit : x vers la droite du visiteur, y vers
	le haut, d = profondeur depuis la façade, d < 0 = jardin de devant) :
	  - toits (deux pans, croupe, mansarde, terrasse) avec rangs de tuiles /
	    ardoises / bardeaux ou joints debout, faîtage, arêtiers, planches de
	    rive, sous-face, gouttières et descentes d'eau pluviale ;
	  - pignons (murs triangulaires), coins (WedgePart) orientés ;
	  - fenêtres (croisillons, petits bois, cintrées, fines modernes, acier
	    d'usine), appuis de pierre, linteaux, volets (persiennes, pleins, en Z) ;
	  - cheminées (briques, pierre, conduit d'acier) avec chapeau et mitrons ;
	  - clôtures (piquets, haie, lisses, fer forgé, muret, lames) avec
	    portillon FERMÉ (attributs Micro = "Swing" pour CONSTRUCT10) ;
	  - allées, boîte aux lettres (drapeau animable), plaque du numéro,
	    luminaires doux, balcons, garage / abri à voiture.
	Chaque pièce reçoit l'attribut BuildPhase (Foundation / Walls / Roof /
	Openings / Garden) : l'animation de construction (CONSTRUCT10) s'en sert.
	Les lumières réelles passent par le budget du kit (kit:Light), Brightness <= 1.
]]

local HouseDetail = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GLASS = Color3.fromRGB(190, 222, 244)
local IRON = Color3.fromRGB(46, 44, 52)
local LAMP = Color3.fromRGB(255, 214, 150)

HouseDetail.GLASS = GLASS
HouseDetail.IRON = IRON

-- Point du repère de la maison (x, y, d) -> vecteur local du kit (axe Z = -d)
local function V(x: number, y: number, d: number): Vector3
	return Vector3.new(x, y, -d)
end
HouseDetail.V = V

-- Phase de construction des pièces créées ensuite par ce kit (et ses Sub)
function HouseDetail.Phase(kit: any, phase: string?)
	kit.Stats.Phase = phase
end

----------------------------------------------------------------------
-- Géométrie de base
----------------------------------------------------------------------

-- Coin (WedgePart) : `up` = normale du côté plat du dessous vers le haut du
-- triangle, `toHigh` = direction du grand côté vertical ; size = (épaisseur,
-- hauteur, longueur) ; `center` = centre local (Vector3 du kit)
function HouseDetail.Wedge(kit: any, name: string, center: Vector3, up: Vector3, toHigh: Vector3, size: Vector3, color: Color3, material: Enum.Material?, opts: any?): BasePart
	local xAxis = up:Cross(toHigh)
	return kit:Part(name, size, CFrame.fromMatrix(center, xAxis, up, toHigh), color, material, opts, "WedgePart")
end

-- Pignon vertical (triangle) dans le plan x = [x0, x1] (épaisseur), base de dA
-- à dB en yBase, sommet au milieu en yTop
function HouseDetail.GableD(kit: any, name: string, x0: number, x1: number, dA: number, dB: number, yBase: number, yTop: number, color: Color3, material: Enum.Material?, opts: any?)
	local dm = (dA + dB) / 2
	local h = yTop - yBase
	if h < 0.05 then
		return
	end
	local xc, thick = (x0 + x1) / 2, math.abs(x1 - x0)
	local up = Vector3.new(0, 1, 0)
	HouseDetail.Wedge(kit, name, V(xc, yBase + h / 2, (dA + dm) / 2), up, Vector3.new(0, 0, -1), Vector3.new(thick, h, dm - dA), color, material, opts)
	HouseDetail.Wedge(kit, name, V(xc, yBase + h / 2, (dm + dB) / 2), up, Vector3.new(0, 0, 1), Vector3.new(thick, h, dB - dm), color, material, opts)
end

-- Pignon face à la rue (triangle dans le plan d = [d0, d1]) : base de xA à xB
function HouseDetail.GableX(kit: any, name: string, d0: number, d1: number, xA: number, xB: number, yBase: number, yTop: number, color: Color3, material: Enum.Material?, opts: any?)
	local xm = (xA + xB) / 2
	local h = yTop - yBase
	if h < 0.05 then
		return
	end
	local dc, thick = (d0 + d1) / 2, math.abs(d1 - d0)
	local up = Vector3.new(0, 1, 0)
	HouseDetail.Wedge(kit, name, V((xA + xm) / 2, yBase + h / 2, dc), up, Vector3.new(1, 0, 0), Vector3.new(thick, h, xm - xA), color, material, opts)
	HouseDetail.Wedge(kit, name, V((xm + xB) / 2, yBase + h / 2, dc), up, Vector3.new(-1, 0, 0), Vector3.new(thick, h, xB - xm), color, material, opts)
end

-- Barre (pièce allongée) entre deux points locaux (x, y, d), section w x h
-- (h = le long de `up`, facultatif : vertical par défaut)
function HouseDetail.Rod(kit: any, name: string, a: { number }, b: { number }, w: number, h: number, color: Color3, material: Enum.Material?, opts: any?, up: Vector3?): BasePart?
	local pa, pb = V(a[1], a[2], a[3]), V(b[1], b[2], b[3])
	local along = pb - pa
	local len = along.Magnitude
	if len < 0.02 then
		return nil
	end
	local z = along.Unit
	local u = up or Vector3.new(0, 1, 0)
	if math.abs(u:Dot(z)) > 0.98 then
		u = Vector3.new(1, 0, 0)
	end
	local x = u:Cross(z).Unit
	local y = z:Cross(x).Unit
	return kit:Part(name, Vector3.new(w, h, len), CFrame.fromMatrix((pa + pb) / 2, x, y, -z), color, material, opts)
end

-- Tube (cylindre) entre deux points locaux
function HouseDetail.Tube(kit: any, name: string, a: { number }, b: { number }, diameter: number, color: Color3, material: Enum.Material?, opts: any?): BasePart?
	local pa, pb = V(a[1], a[2], a[3]), V(b[1], b[2], b[3])
	local along = pb - pa
	local len = along.Magnitude
	if len < 0.02 then
		return nil
	end
	local o: any = opts and table.clone(opts) or {}
	o.Shape = Enum.PartType.Cylinder
	if o.Shadow == nil then
		o.Shadow = false
	end
	local x = along.Unit
	local ref = if math.abs(x.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local z = x:Cross(ref).Unit
	local y = z:Cross(x).Unit
	return kit:Part(name, Vector3.new(len, diameter, diameter), CFrame.fromMatrix((pa + pb) / 2, x, y, z), color, material, o)
end

-- Quadrilatère plan (toit) : A, B = bas (égout), C, D = haut ; dessus passant
-- par les points ; une seule pièce si c'est un rectangle, sinon 2 triangles
local function quad(kit: any, name: string, A: { number }, B: { number }, C: { number }, D: { number }, thick: number, color: Color3, material: Enum.Material?, opts: any?)
	local a, b, cc, d = V(A[1], A[2], A[3]), V(B[1], B[2], B[3]), V(C[1], C[2], C[3]), V(D[1], D[2], D[3])
	local ab, dc = b - a, cc - d
	local ad = d - a
	local isRect = (ab - dc).Magnitude < 0.02 and math.abs(ab.Unit:Dot(ad.Unit)) < 0.01
	if isRect then
		local n = ab:Cross(ad).Unit
		if n.Y < 0 then
			n = -n
		end
		local x = ab.Unit
		local z = x:Cross(n).Unit
		local center = (a + cc) / 2 - n * (thick / 2)
		kit:Part(name, Vector3.new(ab.Magnitude, thick, ad.Magnitude), CFrame.fromMatrix(center, x, n, z), color, material, opts)
		return
	end
	if (d - cc).Magnitude < 0.02 then
		kit:Triangle(name, A, B, C, thick, color, material, opts)
		return
	end
	kit:Triangle(name, A, B, C, thick, color, material, opts)
	kit:Triangle(name, A, C, D, thick, color, material, opts)
end
HouseDetail.Quad = quad

-- Normale (vers le haut) d'un pan A, B (égout), D (haut gauche)
local function planeNormal(A: { number }, B: { number }, D: { number }): Vector3
	local a, b, d = V(A[1], A[2], A[3]), V(B[1], B[2], B[3]), V(D[1], D[2], D[3])
	local n = (b - a):Cross(d - a).Unit
	if n.Y < 0 then
		n = -n
	end
	return n
end

local function lerp3(p: { number }, q: { number }, t: number): { number }
	return { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t }
end

-- Rangs (tuiles / ardoises / bardeaux) sur un pan : baguettes parallèles à
-- l'égout, de l'égout (A-B) vers le haut (D-C) ; ou joints debout (métal) :
-- nervures de l'égout vers le haut
local function courses(kit: any, A: { number }, B: { number }, C: { number }, D: { number }, kind: string, color: Color3, material: Enum.Material, step: number?)
	local n = planeNormal(A, B, D)
	local a, d = V(A[1], A[2], A[3]), V(D[1], D[2], D[3])
	local slopeLen = (d - a).Magnitude
	if kind == "Metal" or kind == "Copper" then
		-- nervures : de l'égout au faîtage, espacées le long de l'égout
		local eave = (V(B[1], B[2], B[3]) - a).Magnitude
		local count = math.clamp(math.floor(eave / 2.4), 2, 44)
		for k = 1, count - 1 do
			local t = k / count
			local p0 = lerp3(A, B, t)
			local p1 = lerp3(D, C, t)
			local v0, v1 = V(p0[1], p0[2], p0[3]) + n * 0.06, V(p1[1], p1[2], p1[3]) + n * 0.06
			local along = v1 - v0
			if along.Magnitude > 0.6 then
				local z = along.Unit
				local x = n:Cross(z).Unit
				kit:Part("RoofSeam", Vector3.new(0.14, 0.16, along.Magnitude - 0.3), CFrame.fromMatrix((v0 + v1) / 2, x, n, -z), color, material, { Shadow = false })
			end
		end
		return
	end
	if kind == "Thatch" then
		return
	end
	local gap = step or (if kind == "Slate" then 0.95 elseif kind == "Shingles" then 1.05 else 1.25)
	local count = math.clamp(math.floor(slopeLen / gap), 1, 18)
	for k = 1, count - 1 do
		local t = k / count
		local p0 = lerp3(A, D, t)
		local p1 = lerp3(B, C, t)
		local v0, v1 = V(p0[1], p0[2], p0[3]), V(p1[1], p1[2], p1[3])
		local along = v1 - v0
		local len = along.Magnitude - 0.4
		if len > 0.5 then
			local x = along.Unit
			local z = x:Cross(n).Unit
			kit:Part("RoofCourse", Vector3.new(len, 0.12, 0.28), CFrame.fromMatrix((v0 + v1) / 2 + n * 0.05, x, n, z), color, material, { Shadow = false })
		end
	end
end
HouseDetail.Courses = courses

----------------------------------------------------------------------
-- Toits
----------------------------------------------------------------------

export type RoofSpec = {
	Shape: string, -- "Gable" | "Hip" | "Mansard" | "Flat"
	Color: Color3,
	Dark: Color3?,
	Material: Enum.Material,
	Kind: string, -- "Tiles" | "Slate" | "Shingles" | "Metal" | "Thatch" | "Copper"
	Over: number?, -- débord de l'égout
	Pitch: number?, -- pente (hauteur / demi-profondeur)
	Rise: number?, -- hauteur imposée (sinon Pitch)
	Inset: number?, -- mansarde : retrait du brisis
	Hip: number?, -- croupe : longueur des croupes (sinon ~ la demi-profondeur)
	Fascia: Color3?,
	Gutter: Color3?,
	Wall: Color3?, -- pignons
	WallMat: Enum.Material?,
	Detail: boolean?, -- rangs, rives, gouttières (faux = LOD)
	Pipes: { number }?, -- x des descentes d'eau pluviale (devant ET derrière)
	Parapet: boolean?, -- toit-terrasse : acrotère (sinon dalle en débord)
	Thick: number?,
	Eaves: boolean?, -- faux = pas de rives / gouttières (corniche du style)
}

export type RoofInfo = {
	Shape: string,
	Base: number, -- y du haut des murs
	Ridge: number, -- y du faîtage / du dessus
	Eave: number, -- y de l'égout
	X0: number,
	X1: number,
	D0: number,
	D1: number,
	Over: number,
	Surface: (x: number, d: number) -> number, -- y du dessus du toit (avant de la maison)
	Front: BasePart?, -- plaque du pan avant (motif)
	FrontFace: { { number } }?, -- pan avant (A, B, C, D)
}

-- Toit sur la boîte [x0, x1] x [d0, d1] (nus extérieurs des murs), murs en y
function HouseDetail.Roof(kit: any, x0: number, x1: number, d0: number, d1: number, y: number, spec: RoofSpec): RoofInfo
	local shape = spec.Shape
	local detail = spec.Detail ~= false
	local color, mat = spec.Color, spec.Material
	local dark = spec.Dark or color:Lerp(BLACK, 0.25)
	local fascia = spec.Fascia or WHITE
	local gutterC = spec.Gutter or Color3.fromRGB(226, 228, 232)
	local ov = spec.Over or 1.6
	local th = spec.Thick or (if spec.Kind == "Thatch" then 1.3 else 0.55)
	local depth = d1 - d0
	local dm = (d0 + d1) / 2
	local solid = { Solid = true, Shadow = true }
	local info: RoofInfo = {
		Shape = shape, Base = y, Ridge = y, Eave = y, X0 = x0, X1 = x1, D0 = d0, D1 = d1, Over = ov,
		Surface = function(_x: number, _d: number): number
			return y
		end,
		Front = nil,
		FrontFace = nil,
	}
	local courseColor = color:Lerp(BLACK, if spec.Kind == "Slate" then 0.18 else 0.14)
	-- égout (avant / arrière) : planche de rive, sous-face, gouttière, descentes
	local function eaves(ax0: number, ax1: number, ye: number, dFront: number, dBack: number)
		if not detail or spec.Eaves == false then
			return
		end
		local fy0 = ye - th - 0.55
		for _, side in ipairs({ { dFront, -1 }, { dBack, 1 } }) do
			local de, s = side[1], side[2]
			local dOut = de + s * 0.02
			local dIn = de - s * 0.3
			kit:Box("Fascia", ax0, ax1, fy0, ye - 0.06, math.min(dOut, dIn), math.max(dOut, dIn), fascia, M.Wood, { Shadow = false })
			local wallFace = if s < 0 then d0 else d1
			-- (s'arrête 0,5 avant le nu du mur : jamais contre les cadres / colombages)
			local soffitEnd = wallFace + s * 0.5
			local sa, sb = math.min(dIn, soffitEnd), math.max(dIn, soffitEnd)
			if sb - sa > 0.2 then
				kit:Box("Soffit", ax0 + 0.05, ax1 - 0.05, fy0 + 0.03, fy0 + 0.17, sa, sb, fascia:Lerp(WHITE, 0.3), M.SmoothPlastic, { Shadow = false })
			end
			local gd = de + s * 0.36
			kit:CylX("Gutter", (ax0 + ax1) / 2, fy0 + 0.3, gd, 0.55, ax1 - ax0 + 0.2, gutterC, M.Metal, { Shadow = false })
			for _, pipeX in ipairs(spec.Pipes or {}) do
				-- naissance, coude vers le mur, descente, colliers, dauphin
				local wd = wallFace + s * 0.55
				kit:CylY("Downpipe", pipeX, fy0 - 0.2, gd, 0.36, 0.5, gutterC, M.Metal, { Shadow = false })
				HouseDetail.Tube(kit, "Downpipe", { pipeX, fy0 - 0.15, gd }, { pipeX, fy0 - 1.3, wd }, 0.34, gutterC, M.Metal)
				kit:CylY("Downpipe", pipeX, 0.9, wd, 0.36, fy0 - 0.9 - 0.5, gutterC, M.Metal, { Shadow = false })
				HouseDetail.Tube(kit, "Downpipe", { pipeX, 1.0, wd }, { pipeX, 0.5, wd + s * 0.55 }, 0.36, gutterC, M.Metal)
				for _, by in ipairs({ fy0 * 0.35, fy0 * 0.7 }) do
					kit:Box("PipeClip", pipeX - 0.24, pipeX + 0.24, by, by + 0.12, math.min(wd, wallFace + s * 0.05), math.max(wd, wallFace + s * 0.05), gutterC:Lerp(BLACK, 0.2), M.Metal,
						{ Shadow = false })
				end
			end
		end
	end

	if shape == "Flat" then
		local top = y + 0.65
		if spec.Parapet then
			info.Ridge = y + 3.2
			info.Eave = y + 3.2
		else
			-- dalle en débord (maison moderne) : bandeau épais + membrane
			local a0, a1 = x0 - ov, x1 + ov
			kit:Box("RoofSlab", a0, a1, top, top + 0.7, d0 - ov, d1 + ov, fascia, M.SmoothPlastic, solid)
			kit:Box("RoofMembrane", a0 + 0.4, a1 - 0.4, top + 0.7, top + 0.86, d0 - ov + 0.4, d1 + ov - 0.4, color, mat, { Shadow = false })
			if detail then
				-- relevé (petit acrotère intérieur) + naissances
				kit:Box("RoofUpstand", a0 + 0.1, a1 - 0.1, top + 0.86, top + 1.25, d0 - ov + 0.1, d0 - ov + 0.4, fascia:Lerp(BLACK, 0.12), M.SmoothPlastic, { Shadow = false })
				for _, pipeX in ipairs(spec.Pipes or {}) do
					kit:CylY("Downpipe", pipeX, 0.9, d0 - 0.55, 0.34, top - 0.9, gutterC, M.Metal, { Shadow = false })
				end
			end
			info.Ridge = top + 1.25
			info.Eave = top
		end
		info.Surface = function(_x: number, _d: number): number
			return top + 0.86
		end
		return info
	end

	local pitch = spec.Pitch or 0.72
	local rise = spec.Rise or ((depth / 2 + ov) * pitch)
	if shape == "Mansard" then
		local inset = spec.Inset or 4.8
		local mrise = spec.Rise or 8.5
		local ye = y - 0.1
		local a0, a1 = x0 - 0.7, x1 + 0.7
		local e0, e1 = d0 - 0.7, d1 + 0.7
		local t0, t1 = x0 + inset, x1 - inset
		local f0, f1 = d0 + inset, d1 - inset
		local yt = y + mrise
		local faces = {
			{ { a0, ye, e0 }, { a1, ye, e0 }, { t1, yt, f0 }, { t0, yt, f0 } },
			{ { a1, ye, e1 }, { a0, ye, e1 }, { t0, yt, f1 }, { t1, yt, f1 } },
			{ { a0, ye, e1 }, { a0, ye, e0 }, { t0, yt, f0 }, { t0, yt, f1 } },
			{ { a1, ye, e0 }, { a1, ye, e1 }, { t1, yt, f1 }, { t1, yt, f0 } },
		}
		for index, f in ipairs(faces) do
			quad(kit, if index <= 2 then "Roof" else "RoofSide", f[1], f[2], f[3], f[4], th, color, mat, solid)
			if detail then
				courses(kit, f[1], f[2], f[3], f[4], spec.Kind, courseColor, mat, 1.1)
			end
		end
		-- terrasson (dessus presque plat) + bourrelet de zinc
		kit:Box("RoofTop", t0 - 0.05, t1 + 0.05, yt - 0.5, yt + 0.05, f0 - 0.05, f1 + 0.05, dark, M.Slate, solid)
		if detail then
			kit:Box("RoofEdge", t0 - 0.3, t1 + 0.3, yt - 0.15, yt + 0.35, f0 - 0.3, f0 + 0.1, dark:Lerp(Color3.fromRGB(92, 58, 96), 0.2), M.Metal, { Shadow = false })
			for _, e in ipairs({ { a0, e0, t0, f0 }, { a1, e0, t1, f0 }, { a0, e1, t0, f1 }, { a1, e1, t1, f1 } }) do
				HouseDetail.Rod(kit, "RoofHipCap", { e[1], ye + 0.25, e[2] }, { e[3], yt + 0.15, e[4] }, 0.5, 0.45, dark, M.Metal, { Shadow = false })
			end
		end
		eaves(a0, a1, ye + 0.05, e0, e1)
		info.Ridge = yt
		info.Eave = ye
		info.Front = nil
		info.FrontFace = faces[1]
		info.Surface = function(_x: number, d: number): number
			if d <= f0 then
				return ye + (d - e0) / (f0 - e0) * (yt - ye)
			elseif d >= f1 then
				return ye + (e1 - d) / (e1 - f1) * (yt - ye)
			end
			return yt
		end
		return info
	end

	-- deux pans / croupe : égouts avant et arrière, faîtage au milieu
	local e0, e1 = d0 - ov, d1 + ov
	local drop = ov * pitch * 0.9
	local ye = y - drop + 0.2
	local yr = y + (depth / 2) * pitch + 0.2
	if spec.Rise then
		yr = y + spec.Rise
		ye = y - ov * (spec.Rise / (depth / 2)) + 0.2
	end
	-- (l'égout ne descend jamais au niveau des fenêtres du dernier étage)
	ye = math.max(ye, y - 0.6 + (th - 0.55))
	local _ = rise
	local ox = if shape == "Gable" then ov * 0.8 else ov
	local a0, a1 = x0 - ox, x1 + ox
	local hip = if shape == "Hip" then math.clamp(spec.Hip or (depth / 2 + ov), 3, (x1 - x0) / 2 - 0.5) else 0
	local r0, r1 = a0 + hip, a1 - hip
	local front = { { a0, ye, e0 }, { a1, ye, e0 }, { r1, yr, dm }, { r0, yr, dm } }
	local back = { { a1, ye, e1 }, { a0, ye, e1 }, { r0, yr, dm }, { r1, yr, dm } }
	quad(kit, "Roof", front[1], front[2], front[3], front[4], th, color, mat, solid)
	quad(kit, "Roof", back[1], back[2], back[3], back[4], th, color, mat, solid)
	if detail then
		courses(kit, front[1], front[2], front[3], front[4], spec.Kind, courseColor, mat)
		courses(kit, back[1], back[2], back[3], back[4], spec.Kind, courseColor, mat)
	end
	if shape == "Hip" then
		kit:Triangle("RoofHip", { a0, ye, e0 }, { a0, ye, e1 }, { r0, yr, dm }, th, color, mat, solid)
		kit:Triangle("RoofHip", { a1, ye, e0 }, { a1, ye, e1 }, { r1, yr, dm }, th, color, mat, solid)
		if detail then
			for _, e in ipairs({ { a0, e0, r0 }, { a1, e0, r1 }, { a0, e1, r0 }, { a1, e1, r1 } }) do
				HouseDetail.Rod(kit, "RoofHipCap", { e[1], ye + 0.2, e[2] }, { e[3], yr + 0.22, dm }, 0.6, 0.5, dark, mat, { Shadow = false })
			end
		end
	else
		-- pignons (murs triangulaires) + planches de rive
		local wall = spec.Wall or color
		local wallMat = spec.WallMat or M.Plaster
		HouseDetail.GableD(kit, "GableWall", x0, x0 + 1, d0, d1, y, yr - 0.6, wall, wallMat, { Solid = true, Shadow = true })
		HouseDetail.GableD(kit, "GableWall", x1 - 1, x1, d0, d1, y, yr - 0.6, wall, wallMat, { Solid = true, Shadow = true })
		if detail then
			for _, gx in ipairs({ a0 + 0.12, a1 - 0.12 }) do
				HouseDetail.Rod(kit, "Barge", { gx, ye + 0.1, e0 - 0.05 }, { gx, yr + 0.15, dm }, 0.34, 0.9, fascia, M.Wood, { Shadow = false })
				HouseDetail.Rod(kit, "Barge", { gx, yr + 0.15, dm }, { gx, ye + 0.1, e1 + 0.05 }, 0.34, 0.9, fascia, M.Wood, { Shadow = false })
			end
			-- aérations des combles (petites persiennes dans le pignon)
			for _, s in ipairs({ -1, 1 }) do
				local vx = if s < 0 then x0 - 0.06 else x1 + 0.06
				local vy = y + (yr - y) * 0.45
				kit:Box("GableVent", math.min(vx, vx - s * 0.1), math.max(vx, vx - s * 0.1), vy - 0.9, vy + 0.9, dm - 0.8, dm + 0.8, fascia, M.Wood, { Shadow = false })
			end
		end
	end
	if detail then
		-- faîtage (tuiles faîtières / couvre-joint)
		local ridgeLen = r1 - r0 + (if shape == "Gable" then 0.2 else 0.6)
		if spec.Kind == "Thatch" then
			kit:CylX("Ridge", (r0 + r1) / 2, yr + 0.1, dm, 1.9, ridgeLen, dark, M.Grass, { Shadow = false })
		elseif spec.Kind == "Metal" or spec.Kind == "Copper" then
			kit:Box("Ridge", r0 - 0.1, r1 + 0.1, yr - 0.1, yr + 0.35, dm - 0.55, dm + 0.55, dark, M.Metal, { Shadow = false })
		else
			kit:CylX("Ridge", (r0 + r1) / 2, yr + 0.05, dm, 0.95, ridgeLen, dark, mat, { Shadow = false })
		end
	end
	eaves(a0 + 0.1, a1 - 0.1, ye, e0, e1)
	info.Ridge = yr
	info.Eave = ye
	info.X0, info.X1 = a0, a1
	info.FrontFace = front
	info.Surface = function(x: number, d: number): number
		local yFront
		if d <= dm then
			yFront = ye + (d - e0) / (dm - e0) * (yr - ye)
		else
			yFront = ye + (e1 - d) / (e1 - dm) * (yr - ye)
		end
		if shape == "Hip" then
			-- croupes : même pente depuis les bouts
			local fromEnd = math.min(x - a0, a1 - x)
			local yHip = ye + fromEnd / math.max(0.1, hip) * (yr - ye)
			return math.min(yFront, yHip)
		end
		return yFront
	end
	return info
end

-- Plaque invisible posée sur le pan avant (motif du toit : SurfaceGui)
function HouseDetail.PatternBand(kit: any, info: RoofInfo, color: Color3, material: Enum.Material): BasePart?
	local f = info.FrontFace
	if not f then
		return nil
	end
	-- partie centrale rectangulaire du pan avant (entre les croupes)
	local A, B, C, D = f[1], f[2], f[3], f[4]
	local x0 = math.max(A[1], D[1])
	local x1 = math.min(B[1], C[1])
	if x1 - x0 < 2 then
		return nil
	end
	local cx = (x0 + x1) / 2
	-- (décollée de 0,3 perpendiculairement au pan : bien au-dessus des rangs de tuiles)
	local dy, dd = D[2] - A[2], D[3] - A[3]
	local len = math.sqrt(dy * dy + dd * dd)
	local ny, nd = dd / len, -dy / len
	if ny < 0 then
		ny, nd = -ny, -nd
	end
	return kit:Slab("RoofPatternBand", cx, { A[2] + ny * 0.3, A[3] + nd * 0.3 }, { D[2] + ny * 0.3, D[3] + nd * 0.3 }, x1 - x0, 0.1, color, material,
		{ T = 1, Shadow = false })
end

----------------------------------------------------------------------
-- Fenêtres
----------------------------------------------------------------------

export type WindowSpec = {
	Style: string, -- "Cross" | "Colonial" | "Tall" | "Arched" | "Modern" | "Industrial"
	Frame: Color3,
	FrameMat: Enum.Material?,
	Sill: Color3?,
	SillMat: Enum.Material?,
	Lintel: string?, -- "Stone" | "Brick" | "Band" | nil
	LintelColor: Color3?,
	Shutters: string?, -- "None" | "Louvered" | "Panel" | "Board"
	ShutterColor: Color3?,
	ShutterRoom: number?, -- place libre de chaque côté (sinon largeur / 2)
	Face: number?, -- d du nu extérieur du mur (défaut -0.3)
	Arch: ((x0: number, x1: number, y1: number) -> ())?, -- imposte cintrée (dessinée par la façade)
	FlowerBox: Color3?,
}

-- Décor d'une fenêtre de façade AVANT (le trou est déjà percé ; la vitre est
-- posée par la façade) : cadre, meneaux / petits bois, appui, linteau, volets
function HouseDetail.Window(kit: any, x0: number, x1: number, y0: number, y1: number, w: WindowSpec)
	local face = w.Face or -0.3
	local frame = w.Frame
	local fm = w.FrameMat or M.Wood
	local style = w.Style
	local slim = style == "Modern"
	local f = if slim then 0.2 elseif style == "Industrial" then 0.28 else 0.34
	local fo = face - (if slim then 0.1 else 0.15) -- avant du cadre
	-- cadre (dormant) : déborde de 0,05 dans le trou, jamais coplanaire
	kit:Box("WinFrame", x0 - f, x1 + f, y1 - 0.05, y1 + f, fo, 0.33, frame, fm)
	kit:Box("WinFrame", x0 - f, x1 + f, y0 - f, y0 + 0.05, fo, 0.33, frame, fm)
	kit:Box("WinFrame", x0 - f, x0 + 0.05, y0 + 0.05, y1 - 0.05, fo, 0.33, frame, fm)
	kit:Box("WinFrame", x1 - 0.05, x1 + f, y0 + 0.05, y1 - 0.05, fo, 0.33, frame, fm)
	local cx = (x0 + x1) / 2
	local bar = if slim then 0.09 else 0.11
	local md0, md1 = 0.18, 0.32
	if style == "Colonial" then
		-- petits bois : 3 x 3 carreaux
		for k = 1, 2 do
			local x = x0 + k * (x1 - x0) / 3
			kit:Box("Muntin", x - bar, x + bar, y0 + 0.05, y1 - 0.05, md0, md1, frame, fm, { Shadow = false })
			local y = y0 + k * (y1 - y0) / 3
			kit:Box("Muntin", x0 + 0.05, x1 - 0.05, y - bar, y + bar, md0, md1, frame, fm, { Shadow = false })
		end
	elseif style == "Industrial" then
		local nx = math.max(2, math.floor((x1 - x0) / 3.2 + 0.5))
		for k = 1, nx - 1 do
			local x = x0 + k * (x1 - x0) / nx
			kit:Box("Muntin", x - bar, x + bar, y0 + 0.05, y1 - 0.05, md0, md1, frame, M.Metal, { Shadow = false })
		end
		for k = 1, 2 do
			local y = y0 + k * (y1 - y0) / 3
			kit:Box("Muntin", x0 + 0.05, x1 - 0.05, y - bar, y + bar, md0, md1, frame, M.Metal, { Shadow = false })
		end
	elseif style == "Modern" then
		-- grand vitrage : un seul montant décalé (ouvrant)
		local x = x0 + (x1 - x0) * 0.62
		kit:Box("Muntin", x - bar, x + bar, y0 + 0.05, y1 - 0.05, md0, md1, frame, fm, { Shadow = false })
	else
		-- croisée (Cross / Tall / Arched) : meneau + traverse d'imposte
		kit:Box("Mullion", cx - 0.12, cx + 0.12, y0 + 0.05, y1 - 0.05, md0, md1, frame, fm, { Shadow = false })
		local ym = y0 + (y1 - y0) * (if style == "Tall" or style == "Arched" then 0.72 else 0.62)
		kit:Box("Transom", x0 + 0.05, x1 - 0.05, ym - 0.1, ym + 0.1, md0, md1, frame, fm, { Shadow = false })
		-- petits bois horizontaux des battants (croisillons à la française)
		if style == "Cross" and y1 - y0 > 4 then
			local yb = y0 + (ym - y0) * 0.5
			kit:Box("Muntin", x0 + 0.05, x1 - 0.05, yb - 0.07, yb + 0.07, md0 + 0.02, md1, frame, fm, { Shadow = false })
		end
	end
	-- appui (pierre, qui avance, avec larmier)
	local sillC = w.Sill or frame:Lerp(WHITE, 0.25)
	local sm = w.SillMat or M.Limestone
	if slim then
		kit:Box("Sill", x0 - 0.3, x1 + 0.3, y0 - 0.34, y0 - f + 0.01, face - 0.55, fo + 0.02, sillC, M.Metal, { Shadow = false })
	else
		kit:Box("Sill", x0 - 0.65, x1 + 0.65, y0 - 0.62, y0 - f - 0.01, face - 0.8, fo + 0.02, sillC, sm, { Shadow = false })
	end
	-- linteau
	local lintel = if w.Arch then nil else w.Lintel -- (cintrée : pas de linteau droit)
	if lintel == "Stone" or lintel == "Brick" then
		local lc = w.LintelColor or sillC
		local lm = if lintel == "Brick" then M.Brick else M.Limestone
		kit:Box("Lintel", x0 - 0.7, x1 + 0.7, y1 + f + 0.02, y1 + f + 0.75, face - 0.14, face + 0.02, lc, lm, { Shadow = false })
		if lintel == "Stone" then
			kit:Box("Keystone", cx - 0.42, cx + 0.42, y1 + f + 0.02, y1 + f + 1.05, face - 0.26, face - 0.1, lc:Lerp(WHITE, 0.15), lm, { Shadow = false })
		end
	elseif lintel == "Band" then
		kit:Box("Lintel", x0 - 0.5, x1 + 0.5, y1 + f + 0.02, y1 + f + 0.32, face - 0.2, face + 0.02, w.LintelColor or frame, M.SmoothPlastic, { Shadow = false })
	end
	if w.Arch then
		w.Arch(x0, x1, y1)
	end
	if w.FlowerBox then
		HouseDetail.FlowerBox(kit, x0 + 0.2, x1 - 0.2, y0 - 0.8, face, w.FlowerBox)
	end
	-- volets (ouverts, contre le mur de part et d'autre)
	local sh = w.Shutters
	if sh and sh ~= "None" then
		HouseDetail.Shutters(kit, x0 - f, x1 + f, y0 - 0.1, y1 + (if w.Arch then 0 else 0.1), face, sh, w.ShutterColor or Color3.fromRGB(122, 146, 112), w.ShutterRoom)
	end
end

-- Paire de volets ouverts (contre le mur) de part et d'autre de x0..x1
function HouseDetail.Shutters(kit: any, x0: number, x1: number, y0: number, y1: number, face: number, kind: string, color: Color3, room: number?)
	local width = math.min((x1 - x0) / 2, room or math.huge)
	if width < 1.2 then
		return
	end
	local h = y1 - y0
	local d0, d1 = face - 0.3, face - 0.06
	local rail = color:Lerp(BLACK, 0.12)
	for _, s in ipairs({ -1, 1 }) do
		local a = if s < 0 then x0 - 0.1 - width else x1 + 0.1
		local b = a + width
		kit:Box("Shutter", a, b, y0, y1, d0, d1, color, M.Wood, { Shadow = false })
		if kind == "Louvered" then
			-- persiennes : cadre + lames (bandes en relief)
			local n = math.clamp(math.floor(h / 1.6), 3, 4)
			for k = 1, n do
				local y = y0 + k * h / (n + 1)
				kit:Box("Louver", a + 0.25, b - 0.25, y - 0.1, y + 0.1, d0 - 0.08, d0 + 0.05, rail, M.Wood, { Shadow = false })
			end
		elseif kind == "Panel" then
			-- 2 panneaux en creux
			local mid = y0 + h * 0.52
			kit:Box("ShutterPanel", a + 0.35, b - 0.35, y0 + 0.4, mid - 0.25, d0 - 0.07, d0 + 0.05, rail, M.Wood, { Shadow = false })
			kit:Box("ShutterPanel", a + 0.35, b - 0.35, mid + 0.25, y1 - 0.4, d0 - 0.07, d0 + 0.05, rail, M.Wood, { Shadow = false })
		else
			-- planches + barres en Z
			for _, by in ipairs({ y0 + h * 0.18, y1 - h * 0.18 }) do
				kit:Box("ShutterBar", a + 0.15, b - 0.15, by - 0.22, by + 0.22, d0 - 0.1, d0 + 0.05, rail, M.Wood, { Shadow = false })
			end
			HouseDetail.Rod(kit, "ShutterBrace", { a + 0.35, y0 + h * 0.18 + 0.2, d0 - 0.05 }, { b - 0.35, y1 - h * 0.18 - 0.2, d0 - 0.05 }, 0.34, 0.16, rail, M.Wood,
				{ Shadow = false }, Vector3.new(0, 0, 1))
		end
	end
end

-- Jardinière sous une fenêtre (y = haut de la jardinière)
function HouseDetail.FlowerBox(kit: any, x0: number, x1: number, y: number, face: number, color: Color3)
	kit:Box("FlowerBox", x0, x1, y - 0.95, y - 0.1, face - 1.35, face - 0.02, color, M.Wood, { Shadow = false })
	kit:Box("FlowerSoil", x0 + 0.12, x1 - 0.12, y - 0.1, y + 0.05, face - 1.23, face - 0.14, Color3.fromRGB(96, 70, 52), M.Ground, { Shadow = false })
	-- feuillage (un bourrelet) + quelques fleurs (budget de pièces)
	kit:CylX("Foliage", (x0 + x1) / 2, y + 0.3, face - 0.7, 0.95, x1 - x0 - 0.3, Color3.fromRGB(96, 156, 88), M.Grass, { Shadow = false })
	local count = math.clamp(math.floor((x1 - x0) / 1.5), 2, 4)
	local blooms = { Color3.fromRGB(236, 96, 128), Color3.fromRGB(255, 214, 110), WHITE, Color3.fromRGB(186, 150, 236), Color3.fromRGB(255, 160, 120) }
	for k = 1, count do
		local fx = x0 + (k - 0.5) * (x1 - x0) / count
		kit:Ball("Bloom", fx + 0.15, y + 0.72 + (k % 2) * 0.12, face - 0.95, 0.62, blooms[k % #blooms + 1], M.SmoothPlastic, { Shadow = false })
	end
end

----------------------------------------------------------------------
-- Cheminées
----------------------------------------------------------------------

-- Cheminée : souche de yBase à yTop (bien dans le toit), chapeau, mitrons ;
-- renvoie le haut (pour la fumée)
function HouseDetail.Chimney(kit: any, kind: string, x: number, d: number, yBase: number, yTop: number, color: Color3?): number
	if kind == "Flue" then
		local steel = Color3.fromRGB(176, 180, 186)
		kit:CylY("ChimneyFlue", x, yBase, d, 1.1, yTop - yBase + 1.2, steel, M.Metal, { Solid = true })
		kit:CylY("ChimneyCollar", x, yTop - 1.2, d, 1.6, 0.35, steel:Lerp(BLACK, 0.2), M.Metal, { Shadow = false })
		kit:Cone("ChimneyHat", x, yTop + 1.3, d, 1.2, 0.8, 6, steel:Lerp(BLACK, 0.1), M.Metal)
		return yTop + 1.3
	end
	local stone = kind == "Stone"
	local body = color or (if stone then Color3.fromRGB(176, 168, 158) else Color3.fromRGB(168, 84, 66))
	local mat = if stone then M.Cobblestone else M.Brick
	local w = if stone then 1.6 else 1.35
	kit:Box("Chimney", x - w, x + w, yBase, yTop, d - w, d + w, body, mat, { Solid = true })
	-- corniche (rangs en encorbellement) + chapeau de pierre
	kit:Box("ChimneyCorbel", x - w - 0.18, x + w + 0.18, yTop - 1.1, yTop - 0.6, d - w - 0.18, d + w + 0.18, body:Lerp(BLACK, 0.08), mat, { Shadow = false })
	kit:Box("ChimneyCap", x - w - 0.3, x + w + 0.3, yTop, yTop + 0.4, d - w - 0.3, d + w + 0.3, Color3.fromRGB(196, 192, 188), M.Concrete, { Shadow = false })
	if stone then
		-- dalle sur 4 plots (chapeau de pierre)
		for _, sx in ipairs({ -1, 1 }) do
			kit:Box("ChimneyPier", x + sx * (w - 0.35) - 0.25, x + sx * (w - 0.35) + 0.25, yTop + 0.4, yTop + 1.2, d - 0.25, d + 0.25, body, mat, { Shadow = false })
		end
		kit:Box("ChimneyHood", x - w - 0.2, x + w + 0.2, yTop + 1.2, yTop + 1.55, d - w - 0.2, d + w + 0.2, Color3.fromRGB(150, 146, 140), M.Slate, { Shadow = false })
		return yTop + 1.55
	end
	-- deux mitrons en terre cuite
	for _, sx in ipairs({ -1, 1 }) do
		kit:CylY("ChimneyPot", x + sx * 0.6, yTop + 0.4, d, 0.62, 1.1, Color3.fromRGB(196, 110, 80), M.Concrete, { Shadow = false })
		kit:CylY("ChimneyPotRim", x + sx * 0.6, yTop + 1.5, d, 0.78, 0.18, Color3.fromRGB(182, 98, 70), M.Concrete, { Shadow = false })
	end
	return yTop + 1.7
end

-- Fumée légère (particules douces)
function HouseDetail.Smoke(kit: any, x: number, y: number, d: number)
	local vent = kit:Box("Smoke", x - 0.3, x + 0.3, y, y + 0.2, d - 0.3, d + 0.3, WHITE, M.SmoothPlastic, { T = 1, Shadow = false })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ChimneySmoke"
	emitter.Color = ColorSequence.new(Color3.fromRGB(246, 244, 248), Color3.fromRGB(214, 212, 222))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 3) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(2.6, 3.6)
	emitter.Speed = NumberRange.new(2, 3)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Acceleration = Vector3.new(0.6, 0.4, 0)
	emitter.Rate = 1.2
	emitter.LightInfluence = 0.6
	emitter.Parent = vent
end

----------------------------------------------------------------------
-- Jardin de devant : clôtures, portillon, allées, boîte aux lettres
----------------------------------------------------------------------

-- Portillon FERMÉ (un battant par côté si large) : Micro = "Swing" (CONSTRUCT10
-- l'anime) ; non bloquant par sécurité (CanCollide = false)
local function gateLeaf(kit: any, x0: number, x1: number, y0: number, y1: number, d: number, color: Color3, material: Enum.Material, hingeLeft: boolean, style: string)
	local w = x1 - x0
	local leaf = kit:Box("GateLeaf", x0 + 0.05, x1 - 0.05, y0, y1, d - 0.08, d + 0.08, color, material, { Shadow = false })
	leaf.CanCollide = false
	leaf.CanQuery = false
	if style == "Iron" then
		leaf.Transparency = 1
		local n = math.max(3, math.floor(w / 0.55))
		for k = 0, n do
			local x = x0 + 0.15 + k * (w - 0.3) / n
			kit:Box("GateBar", x - 0.06, x + 0.06, y0, y1, d - 0.06, d + 0.06, color, material, { Shadow = false })
		end
	end
	local hingeX = if hingeLeft then x0 else x1
	local hingeLocal = CFrame.new(hingeX, y0, -d)
	local hingeWorld = kit.CF * hingeLocal
	leaf:SetAttribute("Micro", "Swing")
	leaf:SetAttribute("HingeCF", hingeWorld:ToObjectSpace(leaf.CFrame))
	leaf:SetAttribute("OpenAngle", if hingeLeft then 95 else -95)
	leaf:SetAttribute("Range", 7)
	return leaf
end

export type FenceSpec = { Kind: string, Color: Color3?, Post: Color3?, Gate0: number, Gate1: number, Height: number?, NoGate: boolean?, Cheap: boolean? }

-- Clôture le long de x (x0..x1) en d, avec un portillon FERMÉ entre Gate0 et Gate1
function HouseDetail.Fence(kit: any, x0: number, x1: number, d: number, spec: FenceSpec)
	local kind: string = spec.Kind
	if kind == "None" then
		return
	end
	local g0, g1 = spec.Gate0, spec.Gate1
	local spans = { { x0, g0 }, { g1, x1 } }
	if spec.NoGate then
		spans = { { x0, x1 } }
	end
	local realGate = gateLeaf
	local function gateLeaf(...: any): any
		if not spec.NoGate then
			return realGate(...)
		end
		return nil
	end
	local function posts(a: number, b: number, every: number): { number }
		local list = {}
		local n = math.max(1, math.floor((b - a) / every + 0.5))
		for k = 0, n do
			table.insert(list, a + k * (b - a) / n)
		end
		return list
	end
	-- version légère (côtés de la parcelle, LOD) : planches pleines + lisse + poteaux
	local lite = spec.Cheap == true and not (kind == "Hedge" or kind == "Stone")
	if lite then
		local wood = spec.Color or (if kind == "Picket" then Color3.fromRGB(250, 250, 246) elseif kind == "Iron" then IRON else Color3.fromRGB(150, 110, 76))
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				if kind == "Iron" or kind == "Rail" then
					kit:Box("FenceRail", a, b, 1.1, 1.35, d - 0.12, d + 0.12, wood, if kind == "Iron" then M.Metal else M.Wood, { Solid = true, Shadow = false })
					kit:Box("FenceRail", a, b, 2.5, 2.75, d - 0.12, d + 0.12, wood, if kind == "Iron" then M.Metal else M.Wood, { Shadow = false })
				else
					kit:Box("FenceBoard", a, b, 0.2, 2.5, d - 0.1, d + 0.1, wood, M.WoodPlanks, { Solid = true, Shadow = false })
					kit:Box("FenceRail", a, b, 2.5, 2.8, d - 0.18, d + 0.18, wood:Lerp(BLACK, 0.06), M.Wood, { Shadow = false })
				end
				for _, x in ipairs(posts(a, b, 9)) do
					kit:Box("FencePost", x - 0.3, x + 0.3, 0, 3.2, d - 0.3, d + 0.3, wood:Lerp(BLACK, 0.1), M.Wood, { Solid = true, Shadow = false })
				end
			end
		end
		return
	end
	if kind == "Picket" then
		local white = spec.Color or Color3.fromRGB(250, 250, 246)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				kit:Box("FenceRail", a, b, 0.9, 1.15, d + 0.05, d + 0.25, white, M.Wood, { Solid = true, Shadow = false })
				kit:Box("FenceRail", a, b, 2.1, 2.35, d + 0.05, d + 0.25, white, M.Wood, { Shadow = false })
				local n = math.max(2, math.floor((b - a) / 1.15))
				for k = 0, n do
					local x = a + 0.2 + k * (b - a - 0.4) / n
					-- piquet taillé en pointe (coin)
					kit:Box("Picket", x - 0.24, x + 0.24, 0, 2.55, d - 0.08, d + 0.05, white, M.Wood, { Shadow = false })
					if k % 2 == 0 then
						kit:Part("PicketTip", Vector3.new(0.34, 0.34, 0.12), CFrame.new(x, 2.55, -(d - 0.015)) * CFrame.Angles(0, 0, math.rad(45)), white, M.Wood, { Shadow = false })
					end
				end
				for _, px in ipairs({ a, b }) do
					kit:Box("FencePost", px - 0.3, px + 0.3, 0, 3.2, d - 0.18, d + 0.42, white, M.Wood, { Solid = true, Shadow = false })
					kit:Box("FencePostCap", px - 0.38, px + 0.38, 3.2, 3.4, d - 0.26, d + 0.5, white, M.Wood, { Shadow = false })
				end
			end
		end
		gateLeaf(kit, g0 + 0.3, g1 - 0.3, 0.2, 2.5, d, white, M.Wood, true, "Picket")
		return
	end
	if kind == "Hedge" then
		local leaf = Color3.fromRGB(78, 138, 74)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				kit:Box("Hedge", a, b, 0, 2.6, d - 0.7, d + 0.7, leaf, M.Grass, { Solid = true })
				local n = math.max(1, math.floor((b - a) / (if spec.Cheap then 12 else 5)))
				for k = 0, n - 1 do
					kit:CylX("HedgeTop", a + (k + 0.5) * (b - a) / n, 2.6, d, 1.4, (b - a) / n - 0.1, leaf:Lerp(WHITE, 0.05 + (k % 2) * 0.03), M.Grass, { Shadow = false })
				end
			end
		end
		-- portillon de bois entre deux piliers de haie
		gateLeaf(kit, g0 + 0.2, g1 - 0.2, 0.2, 2.4, d, Color3.fromRGB(150, 108, 70), M.WoodPlanks, true, "Wood")
		return
	end
	if kind == "Rail" then
		local wood = spec.Color or Color3.fromRGB(146, 106, 72)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				for _, x in ipairs(posts(a, b, 4.5)) do
					kit:CylY("FencePost", x, 0, d, 0.55, 3, wood:Lerp(BLACK, 0.1), M.Wood, { Solid = true, Shadow = false })
				end
				kit:CylX("FenceRail", (a + b) / 2, 1.2, d - 0.1, 0.36, b - a, wood, M.Wood, { Solid = true, Shadow = false })
				kit:CylX("FenceRail", (a + b) / 2, 2.4, d - 0.1, 0.36, b - a, wood, M.Wood, { Shadow = false })
			end
		end
		gateLeaf(kit, g0 + 0.2, g1 - 0.2, 0.3, 2.6, d, wood, M.Wood, true, "Wood")
		return
	end
	if kind == "Iron" then
		local iron = spec.Color or IRON
		local gold = Color3.fromRGB(214, 176, 92)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				kit:Box("FenceWall", a, b, 0, 1.1, d - 0.35, d + 0.35, Color3.fromRGB(214, 206, 196), M.Limestone, { Solid = true, Shadow = false })
				kit:Box("FenceRail", a, b, 1.3, 1.45, d - 0.08, d + 0.08, iron, M.Metal, { Solid = true, Shadow = false })
				kit:Box("FenceRail", a, b, 3.3, 3.45, d - 0.08, d + 0.08, iron, M.Metal, { Shadow = false })
				local n = math.max(2, math.floor((b - a) / 1.8))
				for k = 0, n do
					local x = a + 0.2 + k * (b - a - 0.4) / n
					kit:Box("FenceBar", x - 0.07, x + 0.07, 1.1, 3.8, d - 0.07, d + 0.07, iron, M.Metal, { Shadow = false })
					if k % 4 == 1 then
						kit:Ball("FenceFinial", x, 3.95, d, 0.3, gold, M.Metal, { Shadow = false })
					end
				end
			end
		end
		for _, px in ipairs(if spec.NoGate then {} else { g0 - 0.65, g1 + 0.65 }) do
			kit:Box("GatePillar", px - 0.7, px + 0.7, -0.05, 4.4, d - 0.7, d + 0.7, Color3.fromRGB(226, 218, 206), M.Limestone, { Solid = true })
			kit:Box("GatePillarCap", px - 0.9, px + 0.9, 4.4, 4.8, d - 0.9, d + 0.9, Color3.fromRGB(240, 234, 224), M.Limestone, { Shadow = false })
			kit:Ball("GatePillarBall", px, 5.2, d, 0.8, Color3.fromRGB(240, 234, 224), M.Limestone, { Shadow = false })
		end
		local mid = (g0 + g1) / 2
		gateLeaf(kit, g0, mid, 0.2, 3.9, d, iron, M.Metal, true, "Iron")
		gateLeaf(kit, mid, g1, 0.2, 3.9, d, iron, M.Metal, false, "Iron")
		return
	end
	if kind == "Stone" then
		local stone = spec.Color or Color3.fromRGB(190, 182, 170)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				kit:Box("FenceWall", a, b, 0, 2.1, d - 0.55, d + 0.55, stone, M.Cobblestone, { Solid = true })
				kit:Box("FenceCoping", a - 0.1, b + 0.1, 2.1, 2.45, d - 0.7, d + 0.7, stone:Lerp(WHITE, 0.25), M.Limestone, { Shadow = false })
			end
		end
		for _, px in ipairs(if spec.NoGate then {} else { g0 - 0.55, g1 + 0.55 }) do
			kit:Box("GatePillar", px - 0.6, px + 0.6, -0.05, 3, d - 0.78, d + 0.78, stone, M.Cobblestone, { Solid = true })
			kit:Box("GatePillarCap", px - 0.75, px + 0.75, 3, 3.35, d - 0.85, d + 0.85, stone:Lerp(WHITE, 0.25), M.Limestone, { Shadow = false })
		end
		gateLeaf(kit, g0, g1, 0.25, 2.5, d, Color3.fromRGB(140, 100, 66), M.WoodPlanks, true, "Wood")
		return
	end
	if kind == "Slats" then
		local wood = spec.Color or Color3.fromRGB(150, 110, 76)
		local post = spec.Post or Color3.fromRGB(52, 54, 60)
		for _, span in ipairs(spans) do
			local a, b = span[1], span[2]
			if b - a > 1 then
				for k = 0, 4 do
					local y = 0.35 + k * 0.62
					kit:Box("FenceSlat", a, b, y, y + 0.45, d - 0.1, d + 0.1, wood:Lerp(WHITE, (k % 2) * 0.05), M.WoodPlanks, { Solid = k == 1, Shadow = false })
				end
				for _, x in ipairs(posts(a, b, 4)) do
					kit:Box("FencePost", x - 0.2, x + 0.2, 0, 3.4, d + 0.1, d + 0.4, post, M.Metal, { Shadow = false })
				end
			end
		end
		gateLeaf(kit, g0 + 0.1, g1 - 0.1, 0.3, 3.2, d, wood, M.WoodPlanks, true, "Wood")
		return
	end
end

-- Allée : suite de segments (points { x, d }) ; `kind` = matière / motif
function HouseDetail.Path(kit: any, points: { { number } }, width: number, kind: string)
	local colors = {
		Stones = Color3.fromRGB(196, 192, 188),
		Gravel = Color3.fromRGB(214, 206, 190),
		Pavers = Color3.fromRGB(204, 200, 196),
		Brick = Color3.fromRGB(176, 92, 72),
		Deck = Color3.fromRGB(164, 120, 82),
	}
	local color = colors[kind] or colors.Pavers
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local dx, dd = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dd * dd)
		if len > 0.2 then
			local ux, ud = dx / len, dd / len
			if kind == "Stones" then
				-- (pas japonais espacés : jamais deux dalles l'une sur l'autre ; hauteurs variées)
				local n = math.max(1, math.floor(len / 2.6))
				for j = 0, n - 1 do
					local t = (j + 0.5) / n
					local x = a[1] + dx * t + (if j % 2 == 0 then -0.3 else 0.3) * ud
					local d = a[2] + dd * t - (if j % 2 == 0 then -0.3 else 0.3) * ux
					kit:CylY("SteppingStone", x, -0.1, d, 1.8 + (j % 3) * 0.18, 0.24 + ((j + k) % 4) * 0.035, color:Lerp(BLACK, (j % 3) * 0.05), M.Slate, { Shadow = false })
				end
			else
				local mat = if kind == "Gravel" then M.Pebble elseif kind == "Brick" then M.Brick elseif kind == "Deck" then M.WoodPlanks else M.Pavement
				local y1 = if kind == "Deck" then 0.3 else 0.08
				local ang = math.atan2(dd, dx)
				local cf = CFrame.new((a[1] + b[1]) / 2, (y1 - 0.12) / 2, -(a[2] + b[2]) / 2) * CFrame.Angles(0, ang, 0)
				kit:Part("Path", Vector3.new(len + width * 0.02, y1 + 0.12, width), cf, color, mat, { Shadow = false, Solid = kind == "Deck" })
				-- bordures (pavés, briques, gravier)
				if kind ~= "Deck" then
					for _, s in ipairs({ -1, 1 }) do
						kit:Part("PathEdge", Vector3.new(len, 0.2, 0.3), cf * CFrame.new(0, 0.07 - (y1 - 0.12) / 2, s * (width / 2 + 0.1)), color:Lerp(BLACK, 0.15), M.Concrete, { Shadow = false })
					end
				end
			end
		end
	end
end

-- Boîte aux lettres (face à la rue, dos à la maison) ; `num` = numéro affiché
function HouseDetail.Mailbox(kit: any, kind: string, x: number, d: number, color: Color3, num: string)
	local post = Color3.fromRGB(120, 86, 62)
	local flagColor = Color3.fromRGB(222, 56, 60)
	local function numberPlate(part: BasePart, face: Enum.NormalId)
		local label = kit:Text(part, face, num, Color3.fromRGB(40, 36, 44), Enum.Font.GothamBold, 30, 90)
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Position = UDim2.fromScale(0.05, 0.1)
	end
	local function flag(fx: number, fy: number, fd: number)
		-- drapeau levé (Micro = "Swing" autour de son pivot : CONSTRUCT10)
		local stem = kit:Box("MailFlag", fx - 0.06, fx + 0.06, fy, fy + 1.2, fd - 0.06, fd + 0.06, flagColor, M.SmoothPlastic, { Shadow = false })
		local tab = kit:Box("MailFlagTab", fx - 0.06, fx + 0.06, fy + 0.8, fy + 1.2, fd - 0.06, fd + 0.5, flagColor, M.SmoothPlastic, { Shadow = false })
		local hinge = kit.CF * CFrame.new(fx, fy + 0.1, -fd)
		for _, p in ipairs({ stem, tab }) do
			p:SetAttribute("Micro", "Swing")
			p:SetAttribute("HingeCF", hinge:ToObjectSpace(p.CFrame) * CFrame.Angles(0, 0, math.rad(90)))
			p:SetAttribute("HingeAxis", "X")
			p:SetAttribute("OpenAngle", -90)
			p:SetAttribute("Range", 6)
		end
	end
	if kind == "Wall" then
		return
	end
	if kind == "Pillar" then
		local body = Color3.fromRGB(64, 66, 72)
		kit:Box("MailPillar", x - 0.8, x + 0.8, 0, 4.2, d - 0.6, d + 0.6, body, M.Concrete, { Solid = true })
		kit:Box("MailSlot", x - 0.5, x + 0.5, 3.3, 3.45, d - 0.63, d - 0.55, Color3.fromRGB(20, 20, 22), M.Metal, { Shadow = false })
		local plate = kit:Box("MailNumber", x - 0.55, x + 0.55, 1.8, 2.8, d - 0.66, d - 0.58, Color3.fromRGB(226, 228, 232), M.Metal, { Shadow = false })
		numberPlate(plate, Enum.NormalId.Back)
		kit:Box("MailLight", x - 0.5, x + 0.5, 4.2, 4.35, d - 0.45, d + 0.45, LAMP, M.Neon, { Shadow = false })
		return
	end
	kit:Box("MailPost", x - 0.22, x + 0.22, 0, 3.6, d - 0.22, d + 0.22, post, M.Wood, { Solid = true, Shadow = false })
	if kind == "American" then
		kit:Box("MailArm", x - 0.3, x + 0.3, 3.5, 3.7, d - 1.1, d + 0.3, post, M.Wood, { Shadow = false })
		local box = kit:Box("MailBox", x - 0.65, x + 0.65, 3.7, 4.4, d - 1.3, d + 0.5, color, M.Metal, { Shadow = false })
		kit:CylD("MailTop", x, 4.4, d - 0.4, 1.3, 1.8, color, M.Metal, { Shadow = false })
		numberPlate(box, Enum.NormalId.Left)
		flag(x + 0.72, 3.9, d - 0.2)
		return
	end
	if kind == "Birdhouse" then
		local wood = Color3.fromRGB(196, 150, 108)
		local box = kit:Box("MailBox", x - 0.9, x + 0.9, 3.6, 5.1, d - 0.8, d + 0.8, wood, M.WoodPlanks, { Shadow = false })
		HouseDetail.GableX(kit, "MailRoof", d - 0.85, d + 0.85, x - 1.2, x + 1.2, 5.1, 6.1, color, M.RoofShingles, { Shadow = false })
		kit:Box("MailSlot", x - 0.55, x + 0.55, 4.6, 4.72, d - 0.84, d - 0.78, Color3.fromRGB(30, 26, 24), M.Wood, { Shadow = false })
		kit:CylD("MailPerch", x, 4.1, d - 0.95, 0.16, 0.35, Color3.fromRGB(120, 86, 62), M.Wood, { Shadow = false })
		numberPlate(box, Enum.NormalId.Left)
		flag(x + 0.96, 3.9, d)
		return
	end
	-- classique (boîte ronde sur poteau)
	local box = kit:Box("MailBox", x - 0.8, x + 0.8, 3.6, 4.6, d - 0.7, d + 0.7, color, M.Metal, { Shadow = false })
	kit:CylX("MailTop", x, 4.6, d, 1.4, 1.6, color, M.Metal, { Shadow = false })
	kit:Box("MailSlot", x - 0.5, x + 0.5, 4.3, 4.42, d - 0.74, d - 0.68, Color3.fromRGB(30, 26, 30), M.Metal, { Shadow = false })
	numberPlate(box, Enum.NormalId.Back)
	flag(x + 0.86, 3.9, d)
end

-- Plaque du numéro (émaillée) : x, y = centre, dWall = face du mur
function HouseDetail.NumberPlate(kit: any, x: number, y: number, dWall: number, num: string, modern: boolean?)
	local w = 0.9 + #num * 0.55
	if modern then
		local plate = kit:Box("HouseNumber", x - w / 2, x + w / 2, y - 0.7, y + 0.7, dWall - 0.12, dWall - 0.02, Color3.fromRGB(40, 42, 48), M.Metal, { Shadow = false })
		local label = kit:Text(plate, Enum.NormalId.Back, num, Color3.fromRGB(236, 238, 242), Enum.Font.GothamBold, 30, 160)
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Position = UDim2.fromScale(0.05, 0.1)
		return
	end
	kit:Box("HouseNumberRim", x - w / 2 - 0.12, x + w / 2 + 0.12, y - 0.72, y + 0.72, dWall - 0.1, dWall - 0.02, Color3.fromRGB(40, 70, 130), M.SmoothPlastic, { Shadow = false })
	local plate = kit:Box("HouseNumber", x - w / 2, x + w / 2, y - 0.6, y + 0.6, dWall - 0.16, dWall - 0.1, WHITE, M.SmoothPlastic, { Shadow = false })
	local label = kit:Text(plate, Enum.NormalId.Back, num, Color3.fromRGB(40, 70, 130), Enum.Font.GothamBold, 30, 160)
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
end

----------------------------------------------------------------------
-- Luminaires doux
----------------------------------------------------------------------

-- Applique moderne (cylindre, lumière vers le bas et le haut) contre le mur
function HouseDetail.Sconce(kit: any, x: number, y: number, dWall: number, withLight: boolean)
	local body = Color3.fromRGB(52, 54, 60)
	kit:Box("SconcePlate", x - 0.3, x + 0.3, y - 0.7, y + 0.7, dWall - 0.1, dWall - 0.02, body, M.Metal, { Shadow = false })
	kit:CylY("Sconce", x, y - 0.8, dWall - 0.45, 0.62, 1.6, body, M.Metal, { Shadow = false })
	local glow = kit:CylY("SconceGlow", x, y - 0.95, dWall - 0.45, 0.46, 0.14, LAMP, M.Neon, { Shadow = false })
	kit:CylY("SconceGlow", x, y + 0.81, dWall - 0.45, 0.46, 0.14, LAMP, M.Neon, { Shadow = false })
	if withLight then
		kit:Light(glow, Color3.fromRGB(255, 214, 160), 12, 0.7)
	end
end

-- Borne lumineuse d'allée
function HouseDetail.Bollard(kit: any, x: number, d: number, withLight: boolean)
	local body = Color3.fromRGB(58, 60, 66)
	kit:CylY("Bollard", x, 0, d, 0.55, 2, body, M.Metal, { Shadow = false })
	local glow = kit:CylY("BollardGlow", x, 1.35, d, 0.5, 0.35, LAMP, M.Neon, { Shadow = false })
	kit:CylY("BollardCap", x, 2, d, 0.7, 0.14, body, M.Metal, { Shadow = false })
	if withLight then
		kit:Light(glow, Color3.fromRGB(255, 214, 160), 10, 0.6)
	end
end

-- Guirlande d'ampoules entre deux points (x, y, d) avec un léger creux
function HouseDetail.StringLights(kit: any, a: { number }, b: { number }, count: number, sag: number)
	local colors = { Color3.fromRGB(255, 226, 170), Color3.fromRGB(255, 204, 150), Color3.fromRGB(255, 236, 196) }
	local prev: { number }? = nil
	for k = 0, count do
		local t = k / count
		local p = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t - math.sin(t * math.pi) * sag, a[3] + (b[3] - a[3]) * t }
		if prev then
			HouseDetail.Rod(kit, "LightString", prev, p, 0.05, 0.05, Color3.fromRGB(40, 40, 44), M.SmoothPlastic, { Shadow = false })
		end
		if k > 0 and k < count then
			kit:Ball("FairyBulb", p[1], p[2] - 0.2, p[3], 0.32, colors[k % #colors + 1], M.Neon, { Shadow = false })
		end
		prev = p
	end
end

----------------------------------------------------------------------
-- Balcons
----------------------------------------------------------------------

-- Balcon devant la façade : dalle x0..x1, profondeur `deep`, sol en y
function HouseDetail.Balcony(kit: any, kind: string, x0: number, x1: number, y: number, deep: number, face: number, trim: Color3)
	local d0 = face - deep
	if kind == "None" then
		return
	end
	if kind == "Glass" then
		kit:Box("BalconySlab", x0, x1, y - 0.45, y, d0, face - 0.02, Color3.fromRGB(230, 230, 228), M.Concrete, { Solid = true })
		kit:Box("BalconyGlass", x0 + 0.1, x1 - 0.1, y + 0.05, y + 3.3, d0 + 0.08, d0 + 0.2, GLASS, M.Glass, { T = 0.55, Shadow = false })
		kit:Box("BalconyHandrail", x0 + 0.05, x1 - 0.05, y + 3.3, y + 3.45, d0 + 0.02, d0 + 0.26, Color3.fromRGB(200, 204, 210), M.Metal, { Shadow = false })
		for _, sx in ipairs({ x0 + 0.1, x1 - 0.3 }) do
			kit:Box("BalconyGlass", sx, sx + 0.2, y + 0.05, y + 3.3, d0 + 0.26, face - 0.1, GLASS, M.Glass, { T = 0.55, Shadow = false })
		end
		return
	end
	if kind == "Wood" then
		local wood = Color3.fromRGB(150, 104, 66)
		kit:Box("BalconySlab", x0, x1, y - 0.5, y, d0, face - 0.02, wood:Lerp(BLACK, 0.1), M.WoodPlanks, { Solid = true })
		kit:Box("BalconyRail", x0, x1, y + 3, y + 3.35, d0, d0 + 0.35, wood, M.Wood, { Shadow = false })
		kit:Box("BalconyRail", x0, x1, y + 0.35, y + 0.6, d0 + 0.05, d0 + 0.3, wood, M.Wood, { Shadow = false })
		local n = math.max(2, math.floor((x1 - x0) / 2))
		for k = 0, n do
			local x = x0 + 0.2 + k * (x1 - x0 - 0.4) / n
			kit:Box("BalconyPlank", x - 0.26, x + 0.26, y + 0.6, y + 3, d0 + 0.1, d0 + 0.25, wood:Lerp(WHITE, (k % 2) * 0.06), M.Wood, { Shadow = false })
		end
		for _, sx in ipairs({ x0 + 0.5, x1 - 0.5 }) do
			HouseDetail.Rod(kit, "BalconyBracket", { sx, y - 2.2, face - 0.1 }, { sx, y - 0.45, d0 + 0.4 }, 0.35, 0.35, wood:Lerp(BLACK, 0.15), M.Wood, { Shadow = false })
		end
		return
	end
	if kind == "Stone" then
		kit:Box("BalustradeBase", x0, x1, y - 0.1, y + 0.35, d0, face - 0.02, trim, M.Limestone, { Solid = true, Shadow = false })
		kit:Box("Balustrade", x0, x1, y + 2.3, y + 2.7, d0 - 0.05, d0 + 0.75, trim, M.Limestone, { Shadow = false })
		local n = math.max(2, math.floor((x1 - x0) / 2.1))
		for k = 0, n do
			local x = x0 + 0.35 + k * (x1 - x0 - 0.7) / n
			kit:CylY("Baluster", x, y + 0.35, d0 + 0.35, 0.55, 1.95, trim, M.Limestone, { Shadow = false })
		end
		return
	end
	-- fer forgé (défaut)
	kit:Box("BalconySlab", x0, x1, y - 0.4, y, d0, face - 0.02, trim, M.Limestone, { Solid = true })
	kit:Box("BalconyRail", x0, x1, y + 3, y + 3.2, d0, d0 + 0.2, IRON, M.Metal, { Shadow = false })
	for _, sx in ipairs({ x0, x1 - 0.2 }) do
		kit:Box("BalconyRail", sx, sx + 0.2, y + 3, y + 3.2, d0 + 0.2, face - 0.05, IRON, M.Metal, { Shadow = false })
	end
	kit:Box("BalconyRail", x0 + 0.1, x1 - 0.1, y + 0.35, y + 0.5, d0 + 0.02, d0 + 0.16, IRON, M.Metal, { Shadow = false })
	local n = math.max(2, math.floor((x1 - x0) / 0.62))
	for k = 0, n do
		local x = x0 + 0.1 + k * (x1 - x0 - 0.2) / n
		kit:Box("BalconyBar", x - 0.05, x + 0.05, y, y + 3, d0 + 0.04, d0 + 0.14, IRON, M.Metal, { Shadow = false })
	end
end

----------------------------------------------------------------------
-- Garage / abri à voiture (maisons sans l'aile du manoir)
----------------------------------------------------------------------

export type GarageSpec = { Kind: string, Wall: Color3, WallMat: Enum.Material, Trim: Color3, Roof: Color3, RoofMat: Enum.Material, Door: Color3 }

-- Garage attenant à droite de la maison : x0..x1, d0..d1 (d0 = alignement de la façade)
function HouseDetail.Garage(kit: any, x0: number, x1: number, d0: number, d1: number, spec: GarageSpec)
	local H = 11
	if spec.Kind == "Carport" then
		local wood = Color3.fromRGB(150, 110, 76)
		for _, x in ipairs({ x0 + 0.6, x1 - 0.6 }) do
			for _, d in ipairs({ d0 + 0.6, (d0 + d1) / 2, d1 - 0.6 }) do
				kit:Box("CarportPost", x - 0.35, x + 0.35, 0, H - 1, d - 0.35, d + 0.35, wood, M.Wood, { Solid = true, Shadow = false })
			end
			kit:Box("CarportBeam", x - 0.4, x + 0.4, H - 1.8, H - 1, d0, d1, wood:Lerp(BLACK, 0.1), M.Wood, { Shadow = false })
		end
		kit:Box("CarportRoof", x0 - 0.6, x1 + 0.6, H - 1, H - 0.5, d0 - 0.6, d1 + 0.6, spec.Roof, spec.RoofMat, { Solid = true })
		kit:Box("CarportFascia", x0 - 0.7, x1 + 0.7, H - 1.2, H - 0.4, d0 - 0.75, d0 - 0.6, spec.Trim, M.Wood, { Shadow = false })
		kit:Box("CarportFloor", x0, x1, -0.05, 0.25, d0, d1, Color3.fromRGB(200, 198, 194), M.Concrete, { Shadow = false })
		return
	end
	local W = 0.8
	-- murs (même enduit que la maison), porte sectionnelle FERMÉE
	kit:Box("GarageWall", x1 - W, x1, 0, H, d0, d1, spec.Wall, spec.WallMat, { Solid = true })
	kit:Box("GarageWall", x0, x1 - W, 0, H, d1 - W, d1, spec.Wall, spec.WallMat, { Solid = true })
	local doorW = (x1 - x0) - 4.4
	local cx = (x0 + x1 - W) / 2 + 0.2
	local dx0, dx1 = cx - doorW / 2, cx + doorW / 2
	local doorH = 8.2
	kit:WallX("GarageFront", x0, x1, 0, H, d0, d0 + W, { { dx0, dx1, 0.25, doorH } }, spec.Wall, spec.WallMat, { Solid = true })
	kit:Box("GarageFloor", x0 + 0.05, x1 - W, -0.05, 0.25, d0 + W, d1 - W, Color3.fromRGB(200, 198, 194), M.Concrete, { Shadow = false })
	kit:Box("GarageRoof", x0 - 0.8, x1 + 0.8, H, H + 0.8, d0 - 0.8, d1 + 0.3, spec.Trim, M.SmoothPlastic, { Solid = true })
	kit:Box("GarageRoofTop", x0 - 0.6, x1 + 0.6, H + 0.8, H + 1, d0 - 0.6, d1 + 0.1, spec.Roof, spec.RoofMat, { Shadow = false })
	-- encadrement + porte sectionnelle (panneaux horizontaux, hublots)
	kit:Box("GarageJamb", dx0 - 0.4, dx0 + 0.05, 0.25, doorH + 0.4, d0 - 0.2, d0 + W - 0.1, spec.Trim, M.Wood, { Shadow = false })
	kit:Box("GarageJamb", dx1 - 0.05, dx1 + 0.4, 0.25, doorH + 0.4, d0 - 0.2, d0 + W - 0.1, spec.Trim, M.Wood, { Shadow = false })
	kit:Box("GarageHeader", dx0 - 0.4, dx1 + 0.4, doorH - 0.05, doorH + 0.4, d0 - 0.2, d0 + W - 0.1, spec.Trim, M.Wood, { Shadow = false })
	local dz = d0 + W * 0.5
	kit:Box("GarageDoor", dx0 + 0.05, dx1 - 0.05, 0.27, doorH - 0.02, dz - 0.1, dz + 0.1, spec.Door, M.SmoothPlastic, { Solid = true })
	for k = 1, 3 do
		local y = 0.25 + k * (doorH - 0.25) / 4
		kit:Box("GarageDoorRib", dx0 + 0.15, dx1 - 0.15, y - 0.07, y + 0.07, dz - 0.18, dz - 0.1, spec.Door:Lerp(BLACK, 0.15), M.SmoothPlastic, { Shadow = false })
	end
	kit:Box("GarageDoorWindows", dx0 + 0.8, dx1 - 0.8, doorH - 1.6, doorH - 0.9, dz - 0.16, dz - 0.1, GLASS, M.Glass, { T = 0.3, Shadow = false })
	kit:Box("GarageDoorHandle", cx - 0.5, cx + 0.5, 1.1, 1.3, dz - 0.3, dz - 0.1, Color3.fromRGB(190, 194, 200), M.Metal, { Shadow = false })
end

return HouseDetail
