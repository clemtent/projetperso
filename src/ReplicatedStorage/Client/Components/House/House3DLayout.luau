--[[
	House3DLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DLayout

	Passage 2D -> 3D des objets d'une pièce (v9.3), partagé par la vue 3D
	(House3DScene) et le monde (House3DScene.PlaceItems) :
	  - chaque objet posé devient un vrai modèle 3D (House3DRecipes.BuildModel) ;
	  - X de la pièce 2D -> x (les murs de côté en perspective de la pièce 2D
	    sont retirés), Y -> profondeur (les objets du fond vont contre le mur),
	    objets muraux à leur hauteur sur le mur du fond ;
	  - objets posés SUR un meuble (HouseSurfaces.SupportOf) : sur son vrai
	    dessus 3D ; chaises rangées à une table (HouseSurfaces.SeatedAt) :
	    de côté / derrière / devant, tournées vers elle ; F = miroir ;
	  - objets au sol qui se chevauchent : le suivant avance un peu.

	Repère de la pièce (`frame`) : x vers la droite (centré), y vers le haut
	(0 = dessus du sol), z vers l'avant (0 = face intérieure du mur du fond,
	D = bord avant). Les modèles regardent l'avant de la pièce (+z).

	API :
	  House3DLayout.Dims(sizeDef, px, depth, wallHeight?) -> Dims
	  House3DLayout.Entries(room) -> ({ Placed }, { index dans room.Placed })
	  House3DLayout.Prepare(entry, order, dims, options) -> Build?
	  House3DLayout.Layout(builds, dims, frame)       (Build.Pivot = pivot du modèle)
]]

local HouseCommon = require(script.Parent.HouseCommon)
local HouseSurfaces = require(script.Parent.HouseSurfaces)
local House3DRecipes = require(script.Parent.House3DRecipes)

type Placed = HouseCommon.Placed

local House3DLayout = {}

local ROOM_BASE_WIDTH = 760 -- (= HouseRoom.BASE_WIDTH)
local ROOM_HEIGHT = 440 -- (= HouseRoom.HEIGHT)
local SIDE_PX = 42 -- murs de côté en perspective de la pièce 2D (HouseRoom)
local DEPTH_CURVE = 1.35 -- (Y 2D -> profondeur) les objets du fond vont vraiment contre le mur
local TURN = CFrame.Angles(0, math.pi, 0) -- modèle (devant -Z) <-> repère de recette (devant +Z)

export type Dims = {
	PX: number, -- studs par px de la pièce 2D
	RoomWpx: number,
	RoomHpx: number,
	WallPx: number,
	WallRatio: number,
	W: number, -- (studs) largeur intérieure
	D: number, -- profondeur
	WH: number, -- hauteur des murs
}

export type Build = {
	Entry: Placed,
	Item: any,
	Model: Model,
	Data: House3DRecipes.ItemData,
	K: number,
	Kind: string, -- "Wall" | "Flat" | "Floor"
	Parent: Build?,
	Relation: string?, -- "On" | "At"
	SeatKind: string?,
	SurfaceIndex: number,
	Surface: any?,
	Origin: CFrame, -- repère de la recette (devant +z de la pièce)
	Pivot: CFrame, -- pivot du modèle (= Origin tourné d'un demi-tour)
	X: number,
	Z: number,
	FW: number, -- empreinte (studs) une fois tourné
	FD: number,
	Yaw: number,
	Placed: boolean,
	Order: number,
}

local function finite(value: any, default: number): number
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return default
	end
	return number
end

function House3DLayout.Dims(sizeDef: any, px: number, depth: number, wallHeight: number?): Dims
	local config = HouseCommon.Config
	local widthFactor = type(sizeDef) == "table" and tonumber(sizeDef.Width) or 1
	local roomWpx = math.floor(ROOM_BASE_WIDTH * (widthFactor or 1) + 0.5)
	local wallRatio = tonumber(config.WallRatio) or 0.46
	local wallPx = math.floor(ROOM_HEIGHT * wallRatio + 0.5)
	return {
		PX = px,
		RoomWpx = roomWpx,
		RoomHpx = ROOM_HEIGHT,
		WallPx = wallPx,
		WallRatio = wallRatio,
		W = roomWpx * px,
		D = depth,
		WH = wallHeight or wallPx * px,
	}
end

-- Rotation libre d'un objet (entry.R, degrés, multiple de 15 entre 15 et
-- 345 ; nil = 0). Ajoutée par le monde (Dopamine Town)
function House3DLayout.Rotation(value: any): number?
	local degrees = tonumber(value)
	if degrees == nil or degrees ~= degrees then
		return nil
	end
	degrees = math.floor(degrees / 15 + 0.5) * 15 % 360
	if degrees == 0 then
		return nil
	end
	return degrees
end

-- Objets posés valides d'une pièce (valeurs bornées ; objets inconnus ignorés)
function House3DLayout.Entries(room: any): ({ Placed }, { number })
	local entries: { Placed } = {}
	local indices: { number } = {}
	local list = type(room) == "table" and room.Placed or nil
	if type(list) ~= "table" then
		return entries, indices
	end
	for position, raw in ipairs(list) do
		if type(raw) == "table" and type(raw.I) == "string" and HouseCommon.ItemsById[raw.I] then
			local entry: any = {
				I = raw.I,
				X = math.clamp(finite(raw.X, 0.5), 0, 1),
				Y = math.clamp(finite(raw.Y, 0.8), 0, 1),
				S = math.clamp(finite(raw.S, 1), 0.2, 3),
				Z = finite(raw.Z, 0),
				F = raw.F == true or nil,
				C = type(raw.C) == "string" and raw.C or nil,
				R = House3DLayout.Rotation(raw.R),
			}
			table.insert(entries, entry)
			table.insert(indices, position)
		end
	end
	return entries, indices
end

-- 1. modèle 3D d'un objet (pas encore placé)
function House3DLayout.Prepare(entry: Placed, order: number, dims: Dims, options: House3DRecipes.BuildOptions?): Build?
	local item = HouseCommon.ItemsById[entry.I]
	if not item then
		return nil
	end
	local opts: any = table.clone(options or {})
	opts.Scale = dims.PX
	local model, data = House3DRecipes.BuildModel(entry.I, entry, opts)
	if not model or not data then
		return nil
	end
	local wall = item.Placement == "Wall"
	return {
		Entry = entry,
		Item = item,
		Model = model,
		Data = data,
		K = data.K,
		Kind = wall and "Wall" or (data.Info.Flat and "Flat" or "Floor"),
		Parent = nil,
		Relation = nil,
		SeatKind = nil,
		SurfaceIndex = 1,
		Surface = nil,
		Origin = CFrame.identity,
		Pivot = CFrame.identity,
		X = 0,
		Z = 0,
		FW = data.FW,
		FD = data.FD,
		Yaw = 0,
		Placed = false,
		Order = order,
	}
end

-- 2. relations (posé sur / rangé à) et positions dans le repère `frame`
function House3DLayout.Layout(builds: { Build }, dims: Dims, frame: CFrame)
	local W, D, WH, PX = dims.W, dims.D, dims.WH, dims.PX
	local roomWpx, roomHpx, wallPx = dims.RoomWpx, dims.RoomHpx, dims.WallPx
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	-- 2D (px de la pièce) -> 3D : les murs de côté 2D prennent SIDE_PX en perspective
	local function mapX(x: number, t: number, half: number): number
		local sidePx = SIDE_PX * (1 - math.clamp(t, 0, 1))
		local px = (x * roomWpx - sidePx) / math.max(1, roomWpx - 2 * sidePx) * roomWpx
		local studs = (px - roomWpx / 2) * PX
		local limit = math.max(0, W / 2 - half - 0.1)
		return math.clamp(studs, -limit, limit)
	end
	local function depthOf(y: number): number
		return math.clamp((y - dims.WallRatio) / math.max(0.05, 1 - dims.WallRatio), 0, 1)
	end

	local byEntry: { [Placed]: Build } = {}
	local list: { Placed } = {}
	for _, build in ipairs(builds) do
		byEntry[build.Entry] = build
		table.insert(list, build.Entry)
	end
	for _, build in ipairs(builds) do
		if build.Kind ~= "Wall" then
			local okSupport, support = pcall(HouseSurfaces.SupportOf, build.Entry, list, roomWpx, roomHpx)
			local supportEntry = okSupport and type(support) == "table" and support.Entry or nil
			if supportEntry and byEntry[supportEntry] and supportEntry ~= build.Entry then
				build.Parent = byEntry[supportEntry]
				build.Relation = "On"
				build.Surface = support
				build.SurfaceIndex = tonumber(support.Index) or 1
				if build.Kind == "Flat" then
					build.Kind = "Floor"
				end
			elseif build.Kind == "Floor" then
				local okSeat, seat = pcall(HouseSurfaces.SeatedAt, build.Entry, list, roomWpx, roomHpx)
				local tableEntry = okSeat and type(seat) == "table" and seat.Table or nil
				if tableEntry and byEntry[tableEntry] and tableEntry ~= build.Entry then
					build.Parent = byEntry[tableEntry]
					build.Relation = "At"
					build.SeatKind = tostring(seat.Kind)
				end
			end
		end
	end
	-- (boucles éventuelles coupées)
	for _, build in ipairs(builds) do
		local node = build
		local steps = 0
		while node.Parent and steps < 8 do
			node = node.Parent :: Build
			steps += 1
		end
		if steps >= 8 then
			build.Parent = nil
			build.Relation = nil
		end
	end

	-- Racines au sol : du fond vers l'avant ; on écarte ce qui se chevauche
	local roots: { Build } = {}
	for _, build in ipairs(builds) do
		if build.Parent == nil then
			table.insert(roots, build)
		end
	end
	table.sort(roots, function(a, b)
		if a.Entry.Y ~= b.Entry.Y then
			return a.Entry.Y < b.Entry.Y
		end
		return a.Order < b.Order
	end)
	local placedFloor: { Build } = {}
	local wallRank = 0
	for _, build in ipairs(roots) do
		local entry = build.Entry
		if build.Kind == "Wall" then
			local half = math.min(build.FW / 2, W / 2)
			build.X = mapX(entry.X, 0, half)
			local centerY = math.clamp((wallPx - entry.Y * roomHpx) * PX, 0.4, WH - 0.2)
			wallRank += 1
			build.Z = 0.02 + wallRank * 0.01
			build.Origin = at(build.X, centerY - 50 * build.K, build.Z)
		else
			local t = depthOf(entry.Y)
			local seat = HouseSurfaces.Seat(entry.I)
			if seat and seat.View == "Side" then
				-- (chaise de profil en 2D : un peu tournée vers où elle regarde)
				build.Yaw = entry.F and -math.rad(35) or math.rad(35)
			end
			local fw, fd = build.FW, build.FD
			build.X = mapX(entry.X, t, fw / 2)
			local zFront = (t ^ DEPTH_CURVE) * D
			local z
			if build.Data.Info.Wall and t < 0.55 then
				z = fd / 2 + 0.08
			else
				z = math.clamp(zFront - fd / 2, fd / 2 + 0.08, math.max(fd / 2 + 0.08, D - fd / 2 - 0.1))
			end
			if build.Kind == "Floor" then
				-- chevauchement avec un objet déjà posé : on avance un peu
				for _ = 1, 6 do
					local moved = false
					for _, other in ipairs(placedFloor) do
						local overlapX = math.abs(other.X - build.X) < (other.FW + fw) / 2 - 0.15
						local overlapZ = math.abs(other.Z - z) < (other.FD + fd) / 2
						if overlapX and overlapZ then
							local pushed = other.Z + (other.FD + fd) / 2 + 0.05
							if pushed + fd / 2 <= D + 0.5 then
								z = pushed
								moved = true
							end
						end
					end
					if not moved then
						break
					end
				end
				table.insert(placedFloor, build)
			end
			build.Z = z
			local lift = build.Kind == "Flat" and 0.01 + (#placedFloor % 5) * 0.004 or 0
			build.Origin = at(build.X, lift, z) * CFrame.Angles(0, build.Yaw, 0)
		end
		build.Placed = true
	end

	-- Membres des groupes (posés sur / rangés à)
	local rotation = frame.Rotation
	local function place(build: Build, guard: number)
		if build.Placed or guard > 10 then
			return
		end
		local parent = build.Parent
		if not parent then
			build.Placed = true
			return
		end
		place(parent, guard + 1)
		local entry = build.Entry
		if build.Relation == "On" then
			local surface = build.Surface
			local centerX = surface and ((tonumber(surface.L) or entry.X) + (tonumber(surface.R) or entry.X)) / 2 or parent.Entry.X
			local dx = (entry.X - centerX) * roomWpx * PX
			local top = parent.Data.Tops[build.SurfaceIndex] or parent.Data.Tops[1]
			local base: CFrame
			if top then
				local k = parent.K
				dx = math.clamp(dx, -top.W * k / 2, top.W * k / 2)
				base = parent.Origin * CFrame.new(top.X * k, top.Y * k, top.Z * k)
			else
				base = parent.Origin * CFrame.new(0, parent.Data.H, 0)
			end
			local world = base.Position + frame.RightVector * dx
			local rel = frame:PointToObjectSpace(world)
			build.X = rel.X
			build.Z = rel.Z
			build.Origin = CFrame.new(world) * rotation
		else
			-- chaise à une table : de côté (tournée vers elle), derrière ou devant
			local tableX, tableZ = parent.X, parent.Z
			local tw, td = parent.FW, parent.FD
			local cd = build.FD
			local tuck = math.min(cd * 0.3, 0.8)
			local kind = build.SeatKind or "Front"
			local x, z, yaw = tableX, tableZ, 0
			local dx = (entry.X - parent.Entry.X) * roomWpx * PX
			if kind == "Left" then
				x = tableX - tw / 2 - cd / 2 + tuck
				yaw = math.pi / 2
			elseif kind == "Right" then
				x = tableX + tw / 2 + cd / 2 - tuck
				yaw = -math.pi / 2
			elseif kind == "Behind" then
				x = tableX + math.clamp(dx, -tw / 2, tw / 2)
				z = tableZ - td / 2 - cd / 2 + tuck
				yaw = 0
			else
				x = tableX + math.clamp(dx, -tw / 2, tw / 2)
				z = tableZ + td / 2 + cd / 2 - tuck
				yaw = math.pi
			end
			x = math.clamp(x, -W / 2 + 0.3, W / 2 - 0.3)
			z = math.clamp(z, 0.3, D + 0.6)
			build.X, build.Z, build.Yaw = x, z, yaw
			build.Origin = at(x, 0, z) * CFrame.Angles(0, yaw, 0)
		end
		build.Placed = true
	end
	for _, build in ipairs(builds) do
		place(build, 0)
	end
	-- Rotation libre (entry.R) autour du centre de l'empreinte (objets au
	-- sol ; une chaise rangée à une table y reste tournée si R est absent)
	for _, build in ipairs(builds) do
		local degrees = (build.Entry :: any).R
		if build.Kind ~= "Wall" and type(degrees) == "number" and degrees ~= 0 then
			build.Origin = build.Origin * CFrame.Angles(0, math.rad(degrees), 0)
		end
		build.Pivot = build.Origin * TURN
	end
end

return House3DLayout
