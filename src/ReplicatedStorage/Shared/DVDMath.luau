--[[
	DVDMath (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > DVDMath

	Mathématiques du logo DVD, partagées entre serveur et client.

	Le mouvement est DÉTERMINISTE : à partir de quelques paramètres
	(position de départ, vitesse, heure de départ), on peut calculer la
	position exacte à n'importe quel instant. Avantages :
	  - mouvement parfaitement fluide, quel que soit le nombre d'images/s ;
	  - le serveur peut vérifier qu'un "coin touché" est réel (anti-triche).

	Coordonnées normalisées : 0 = bord gauche/haut, 1 = bord droit/bas.
	Le coin haut-gauche du logo se déplace dans [0, 1 - largeurLogo].
]]

local DVDMath = {}

export type Params = {
	X0: number, -- position de départ (normalisée)
	Y0: number,
	VX: number, -- vitesse (fraction d'écran par seconde, signe = direction)
	VY: number,
	T0: number, -- heure serveur de départ (workspace:GetServerTimeNow())
	W: number, -- taille du logo (fraction de l'écran)
	H: number,
}

-- "Onde triangle" : fait rebondir une valeur qui avance tout droit entre 0 et range
function DVDMath.Triangle(u: number, range: number): number
	if range <= 0 then
		return 0
	end
	local m = u % (2 * range) -- toujours positif en Luau
	if m <= range then
		return m
	end
	return 2 * range - m
end

function DVDMath.Ranges(params: Params): (number, number)
	return math.max(0.001, 1 - params.W), math.max(0.001, 1 - params.H)
end

-- Distance "dépliée" parcourue (sans rebond) sur chaque axe au temps t
function DVDMath.Unfolded(params: Params, t: number): (number, number)
	local dt = t - params.T0
	return params.X0 + params.VX * dt, params.Y0 + params.VY * dt
end

-- Position réelle (avec rebonds) au temps t
function DVDMath.Position(params: Params, t: number): (number, number)
	local rangeX, rangeY = DVDMath.Ranges(params)
	local u, v = DVDMath.Unfolded(params, t)
	return DVDMath.Triangle(u, rangeX), DVDMath.Triangle(v, rangeY)
end

-- Numéro du "segment" entre deux rebonds sur chaque axe.
-- Quand ce numéro change, le logo vient de rebondir.
function DVDMath.BounceIndex(params: Params, t: number): (number, number)
	local rangeX, rangeY = DVDMath.Ranges(params)
	local u, v = DVDMath.Unfolded(params, t)
	return math.floor(u / rangeX), math.floor(v / rangeY)
end

-- Heure exacte du rebond horizontal numéro k (quand u = k * rangeX)
function DVDMath.BounceTimeX(params: Params, k: number): number
	local rangeX = DVDMath.Ranges(params)
	return params.T0 + (k * rangeX - params.X0) / params.VX
end

-- Au moment du rebond horizontal k, le logo est-il aussi contre un bord
-- vertical ? Si oui : COIN !
function DVDMath.IsCornerAtBounceX(params: Params, k: number, tolerance: number): boolean
	local _, rangeY = DVDMath.Ranges(params)
	local t = DVDMath.BounceTimeX(params, k)
	local _, y = DVDMath.Position(params, t)
	return y <= tolerance or y >= rangeY - tolerance
end

-- Direction actuelle (+1 / -1) sur chaque axe, utile pour garder la
-- continuité quand l'écran change de taille
function DVDMath.Directions(params: Params, t: number): (number, number)
	local rangeX, rangeY = DVDMath.Ranges(params)
	local u, v = DVDMath.Unfolded(params, t)
	local dirX = (u % (2 * rangeX) <= rangeX) and 1 or -1
	local dirY = (v % (2 * rangeY) <= rangeY) and 1 or -1
	return dirX * math.sign(params.VX), dirY * math.sign(params.VY)
end

return DVDMath
