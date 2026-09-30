--[[
	NPCSeatGuard (ModuleScript)
	Emplacement : ServerScriptService > Services > World > NPCSeatGuard

	v9.9 (NPC99) 🪑 "Si un PNJ est assis, je ne m'assois pas DANS lui : je
	m'assois à côté."

	Les passants assis sur les bancs sont construits côté client (TownPeople),
	mais leurs places sont DÉTERMINISTES (NPCSeats.BenchPlan(graine de
	l'emplacement "SitBench")). Le serveur connaît donc exactement les places
	prises. Pour chaque emplacement "SitBench" publié (StreetLife) on retrouve
	le Seat du banc (le plus proche, ≤ 1,5 stud à l'horizontale) puis :
	  - banc PLEIN (2 PNJ) : Seat.Disabled = true (on ne s'y assoit plus) ;
	  - sinon, quand un joueur s'assoit (Roblox crée la soudure "SeatWeld"),
	    la soudure est décalée le long du banc vers la place LIBRE la plus
	    proche de l'avatar : tout le monde le voit à côté du PNJ (soudure du
	    serveur, répliquée) ;
	  - attributs sur le Seat : NpcSlots = "10" / "01" / "11" / "00",
	    NpcSlotX = "-1.3,1.3" (pour les invites "S'asseoir" éventuelles) ;
	  - publie StreetLife > NpcBenches (attribut Data : lignes
	    "x;y;z;dessus;masque") : TownPeople y lit la hauteur exacte du siège.

	API :
	  NPCSeatGuard.Apply(townRoot) -> number   (bancs gardés) ; à appeler
	    APRÈS TownKit.PublishLife (fin de TownMap.Build). Sans danger si
	    rappelé (reconstruction de la ville).
	  NPCSeatGuard.SlotFor(seat, position) -> number? (x local de la place)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCSeats = require(ReplicatedStorage.Shared.NPCSeats)

local NPCSeatGuard = {}

local MATCH_RADIUS = 1.5

type Spot = { Pos: Vector3, Seed: number }

local conns: { RBXScriptConnection } = {}

local function readSpots(life: Instance): { Spot }
	local spots = {}
	for _, child in ipairs(life:GetChildren()) do
		local text = child:GetAttribute("Data")
		if child.Name ~= "NpcBenches" and type(text) == "string" then
			for _, line in ipairs(string.split(text, "\n")) do
				local f = string.split(line, ";")
				if f[1] == "SitBench" then
					local x, y, z = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
					if x and y and z then
						table.insert(spots, { Pos = Vector3.new(x, y, z), Seed = tonumber(f[6]) or 0 })
					end
				end
			end
		end
	end
	return spots
end

-- x local (le long du banc) de la place libre la plus proche de `position`
function NPCSeatGuard.SlotFor(seat: BasePart, position: Vector3): number?
	local mask = seat:GetAttribute("NpcSlots")
	if type(mask) ~= "string" then
		return nil
	end
	local rel = seat.CFrame:PointToObjectSpace(position).X
	local best, bestD = nil, math.huge
	for i, x in ipairs(NPCSeats.BENCH_SLOTS) do
		if string.sub(mask, i, i) ~= "1" then
			local d = math.abs(x - rel)
			if d < bestD then
				best, bestD = x, d
			end
		end
	end
	return best
end

local function guard(seat: Seat)
	table.insert(
		conns,
		seat.ChildAdded:Connect(function(child)
			if child.Name ~= "SeatWeld" or not child:IsA("Weld") then
				return
			end
			local weld = child :: Weld
			local root = weld.Part1
			if not root then
				return
			end
			local x = NPCSeatGuard.SlotFor(seat, root.Position)
			if x then
				-- (décalage le long du banc, dans le repère du Seat)
				weld.C0 = CFrame.new(x, 0, 0) * weld.C0
			end
		end)
	)
end

function NPCSeatGuard.Apply(townRoot: Instance): number
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	local life = townRoot:FindFirstChild("StreetLife")
	if not life then
		return 0
	end
	local spots = readSpots(life)
	if #spots == 0 then
		return 0
	end
	local seats: { Seat } = {}
	for _, d in ipairs(townRoot:GetDescendants()) do
		if d:IsA("Seat") then
			table.insert(seats, d)
		end
	end
	local lines = {}
	local count = 0
	for _, spot in ipairs(spots) do
		local best: Seat? = nil
		local bestD = MATCH_RADIUS
		for _, seat in ipairs(seats) do
			local p = seat.Position
			local dy = p.Y - spot.Pos.Y
			local d = Vector3.new(p.X - spot.Pos.X, 0, p.Z - spot.Pos.Z).Magnitude
			if d < bestD and dy > 0.2 and dy < 3 then
				best, bestD = seat, d
			end
		end
		if best then
			local plan = NPCSeats.BenchPlan(spot.Seed)
			local top = best.Position.Y + best.Size.Y / 2 - spot.Pos.Y
			best:SetAttribute("NpcSlots", plan.Mask)
			best:SetAttribute("NpcSlotX", table.concat(NPCSeats.BENCH_SLOTS, ","))
			if plan.Mask == "11" then
				best.Disabled = true
			elseif plan.Mask ~= "00" then
				guard(best)
			end
			table.insert(lines, string.format("%.2f;%.2f;%.2f;%.3f;%s", spot.Pos.X, spot.Pos.Y, spot.Pos.Z, top, plan.Mask))
			count += 1
		end
	end
	local old = life:FindFirstChild("NpcBenches")
	if old then
		old:Destroy()
	end
	local cfg = Instance.new("Configuration")
	cfg.Name = "NpcBenches"
	cfg:SetAttribute("Data", table.concat(lines, "\n"))
	cfg:SetAttribute("Count", count)
	cfg.Parent = life
	return count
end

return NPCSeatGuard
