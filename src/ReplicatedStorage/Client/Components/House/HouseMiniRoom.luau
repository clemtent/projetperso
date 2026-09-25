--[[
	HouseMiniRoom (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseMiniRoom

	Petite pièce "maison de poupée" dessinée dans une case de l'immeuble
	(vue d'ensemble de la maison) :
	  - papier peint et sol de la pièce (HousePatterns, motif réduit),
	    murs de côté en perspective, plinthe, ombre du plafond ;
	  - les objets de la pièce en petit (dessins statiques de HouseArt),
	    placés d'après leurs X / Y / S : au plus MAX_ITEMS objets (les plus
	    gros d'abord) pour garder peu de Frames ;
	  - la nuit : voile bleu nuit + lumière chaude de plafonnier (la pièce
	    a l'air allumée), halo des lampes.
	Reconstruction partielle : le fond n'est redessiné que si le papier
	peint / le sol / la taille changent, les objets seulement si la
	disposition change.

	API :
	  HouseMiniRoom.new(parent, width, height) -> Mini
	    mini.Frame
	    mini.Set(room, size, placed?)     (placed = disposition en cours)
	    mini.SetDark(dark)
	    mini.Destroy()
]]

local Client = script.Parent.Parent.Parent
local UIUtil = require(Client.UIUtil)
local HouseCommon = require(script.Parent.HouseCommon)
local HousePatterns = require(script.Parent.HousePatterns)
local HouseArt = require(script.Parent.HouseArt)

type Room = HouseCommon.Room
type SizeDef = HouseCommon.SizeDef
type Placed = HouseCommon.Placed

local HouseMiniRoom = {}

HouseMiniRoom.MAX_ITEMS = 12
local ROOM_BASE_WIDTH = 760 -- (= HouseRoom.BASE_WIDTH, sans dépendre du module)
local ROOM_HEIGHT = 440
local PATTERN_UNIT = 0.8 -- motifs un peu plus fins que dans la pièce

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle

export type Mini = {
	Frame: Frame,
	Set: (room: Room, size: SizeDef, placed: { Placed }?) -> (),
	SetDark: (dark: boolean) -> (),
	Destroy: () -> (),
}

local function placedSignature(list: { Placed }): string
	local parts = table.create(#list)
	for index, entry in ipairs(list) do
		parts[index] = string.format("%s:%.3f:%.3f:%.2f:%d", entry.I, entry.X, entry.Y, entry.S, math.floor(entry.Z))
	end
	return table.concat(parts, ";")
end

function HouseMiniRoom.new(parent: Instance, width: number, height: number): Mini
	local wallHeight = math.floor(height * HouseCommon.Config.WallRatio + 0.5)
	local dark = false
	local styleKey = ""
	local itemsKey = ""
	local lamps: { Frame } = {}

	local frame = UIUtil.Create("Frame", {
		Name = "MiniRoom",
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.PinkSoft,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
	})
	frame:SetAttribute("DarkSkinIgnore", true)
	local wall = UIUtil.Create("Frame", {
		Name = "Wall",
		Size = UDim2.fromOffset(width, wallHeight),
		BackgroundColor3 = C.PinkSoft,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = frame,
	})
	local floor = UIUtil.Create("Frame", {
		Name = "Floor",
		Position = UDim2.fromOffset(0, wallHeight),
		Size = UDim2.fromOffset(width, height - wallHeight),
		BackgroundColor3 = C.Lilac,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = frame,
	})
	local decor = UIUtil.Create("Frame", {
		Name = "Decor",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = frame,
	})
	local items = UIUtil.Create("Frame", {
		Name = "Items",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = frame,
	})
	local night = UIUtil.Create("Frame", {
		Name = "Night",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(34, 26, 92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = frame,
	})
	-- Lumière chaude du plafonnier (la nuit)
	local lampGlow = UIUtil.Create("Frame", {
		Name = "Lamp",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = frame,
	})
	for index, ring in ipairs({ { 1.4, 0.93 }, { 0.8, 0.88 } }) do
		local size = height * ring[1]
		local glow = Circle(lampGlow, width / 2, height * 0.12, size * 1.6, size, Color3.fromRGB(255, 214, 140), ring[2], index)
		glow.Name = "Glow" .. index
	end
	local bulb = Circle(lampGlow, width / 2, 4, 14, 10, Color3.fromRGB(255, 236, 170), 0, 4)
	bulb.Name = "Bulb"
	frame.Parent = parent

	local function paintNight()
		night.BackgroundTransparency = dark and 0.72 or 1
		lampGlow.Visible = dark
		for _, lamp in ipairs(lamps) do
			lamp.BackgroundTransparency = dark and 0.72 or 0.9
		end
	end

	-- Fond : papier peint, sol, murs de côté, plinthe, ombres
	local function buildBackground(room: Room)
		local wallpaper = HouseCommon.GetRoomWallpaper(room)
		local floorStyle = HouseCommon.GetRoomFloor(room)
		HousePatterns.BuildWall(wall, width, wallHeight, wallpaper, PATTERN_UNIT)
		HousePatterns.BuildFloor(floor, width, height - wallHeight, floorStyle, PATTERN_UNIT)
		for _, child in ipairs(decor:GetChildren()) do
			child:Destroy()
		end
		local wallA = wallpaper and wallpaper.A or C.PinkSoft
		local wallB = wallpaper and wallpaper.B or C.Pink
		local floorB = floorStyle and floorStyle.B or C.Lilac
		local side = math.floor(width * 0.06)
		local floorHeight = height - wallHeight
		local slices = 6
		for _, info in ipairs({ { X = 0, Dir = 1, Tone = 0.14 }, { X = width - side, Dir = -1, Tone = 0.06 } }) do
			local color = wallA:Lerp(wallB, 0.35):Lerp(BLACK, info.Tone)
			Box(decor, info.X, 0, side, wallHeight, color, 0, 1)
			for index = 0, slices - 1 do
				local sliceW = side * (1 - index / slices)
				local x = info.Dir > 0 and 0 or width - sliceW
				Box(decor, x, wallHeight + index * floorHeight / slices, sliceW, floorHeight / slices + 0.6, color, 0, 1)
			end
			local edgeX = info.Dir > 0 and side - 1 or width - side - 1
			Box(decor, edgeX, 0, 1.5, wallHeight, wallB:Lerp(BLACK, 0.35), 0.5, 2)
		end
		-- Plinthe, ombre au pied du mur, ombre du plafond, avant plus sombre
		Box(decor, side, wallHeight - 5, width - side * 2, 5, C.Cream, 0, 2)
		local ao = Box(decor, 0, wallHeight, width, 12, BLACK, 0.75, 1)
		UIUtil.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = ao })
		local ceiling = Box(decor, 0, 0, width, 14, BLACK, 0.7, 2)
		UIUtil.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = ceiling })
		local front = Box(decor, 0, height - 18, width, 18, BLACK, 0.8, 2)
		UIUtil.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.3), Parent = front })
		Box(decor, 0, height - 2, width, 2, floorB:Lerp(BLACK, 0.4), 0.4, 2)
	end

	-- Objets : les MAX_ITEMS plus gros, dessinés en statique
	local function buildItems(room: Room, size: SizeDef, placed: { Placed })
		for _, child in ipairs(items:GetChildren()) do
			child:Destroy()
		end
		table.clear(lamps)
		local roomWidth = ROOM_BASE_WIDTH * (tonumber(size.Width) or 1)
		local k = math.min(width / roomWidth, height / ROOM_HEIGHT)
		local chosen = {}
		for _, entry in ipairs(placed) do
			local item = HouseCommon.ItemsById[entry.I]
			if item then
				table.insert(chosen, { Entry = entry, Item = item, Area = item.Size * entry.S })
			end
		end
		table.sort(chosen, function(a, b)
			return a.Area > b.Area
		end)
		while #chosen > HouseMiniRoom.MAX_ITEMS do
			table.remove(chosen)
		end
		local drawn = {}
		for _, pick in ipairs(chosen) do
			local item, entry = pick.Item, pick.Entry
			local isWall = item.Placement == "Wall"
			local holder = UIUtil.Create("Frame", {
				Name = item.Id,
				Size = UDim2.fromOffset(100, 100),
				AnchorPoint = isWall and Vector2.new(0.5, 0.5) or Vector2.new(0.5, 1),
				Position = UDim2.fromScale(entry.X, entry.Y),
				BackgroundTransparency = 1,
			})
			UIUtil.Create("UIScale", { Scale = item.Size * entry.S / 100 * k, Parent = holder })
			local body = UIUtil.Create("Frame", {
				Name = "Body",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Parent = holder,
			})
			local result = HouseArt.Paint(body, item, true)
			local flat = result ~= nil and result.Flat == true
			if result == nil or result.ShowEmoji == true then
				UIUtil.Create("TextLabel", {
					Name = "Emoji",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Font = Enum.Font.BuilderSansMedium,
					Text = item.Icon,
					TextColor3 = WHITE,
					TextSize = 80,
					ZIndex = 3,
					Parent = body,
				})
			end
			if not isWall and not flat then
				Circle(holder, 50, 97, 90, 14, BLACK, 0.86, 1)
			end
			local glowColor = result and result.Glow or (item.Category == "Lights" and C.Butter or nil)
			if glowColor then
				local glow = Circle(holder, 50, 50, 150, 150, glowColor, 0.9, 1)
				table.insert(lamps, glow)
			end
			local rank = isWall and 0 or (flat and 1 or 2)
			table.insert(drawn, { Holder = holder, Rank = rank, Entry = entry })
		end
		table.sort(drawn, function(a, b)
			if a.Rank ~= b.Rank then
				return a.Rank < b.Rank
			end
			if a.Entry.Z ~= b.Entry.Z then
				return a.Entry.Z < b.Entry.Z
			end
			return a.Entry.Y < b.Entry.Y
		end)
		for index, info in ipairs(drawn) do
			info.Holder.ZIndex = index
			info.Holder.Parent = items
		end
	end

	local mini: Mini
	mini = {
		Frame = frame,
		Set = function(room: Room, size: SizeDef, placed: { Placed }?)
			local list = placed or room.Placed
			local newStyleKey = string.format("%s|%s|%d", room.Wallpaper, room.Floor, width)
			if newStyleKey ~= styleKey then
				styleKey = newStyleKey
				buildBackground(room)
			end
			local newItemsKey = tostring(size.Width) .. "#" .. placedSignature(list)
			if newItemsKey ~= itemsKey then
				itemsKey = newItemsKey
				buildItems(room, size, list)
				paintNight()
			end
		end,
		SetDark = function(value: boolean)
			if dark == value then
				return
			end
			dark = value
			paintNight()
		end,
		Destroy = function()
			frame:Destroy()
		end,
	}
	paintNight()
	return mini
end

return HouseMiniRoom
