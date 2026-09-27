--[[
	TownEmotes (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownEmotes

	💃 Dopamine Town : les émotes de l'avatar, qui s'ARRÊTENT toujours.

	Cause du bug v9.3 ("je danse et je ne peux plus m'arrêter") : l'ancien
	playEmote chargeait l'animation "dance" du script Animate (en boucle)
	sur l'Animator, la jouait… et ne gardait AUCUNE référence : personne ne
	pouvait l'arrêter (le script Animate ne la connaît pas, marcher ou sauter
	ne la coupait pas). Humanoid:PlayEmote ne marche que pour les émotes
	équipées de l'avatar : en Studio c'était presque toujours ce chemin-là.

	Maintenant :
	  - la piste de l'émote en cours est GARDÉE (Tracks) ; nos propres pistes
	    (priorité Action) viennent du script Animate de l'avatar (R15 ET R6 :
	    wave, dance, cheer, point…) ; "dance" boucle, les autres (salut,
	    youpi, montrer) s'arrêtent toutes seules ;
	  - repli : Humanoid:PlayEmote (avatar sans script Animate) -> on repère
	    les pistes qu'il vient de lancer pour pouvoir les arrêter aussi ;
	  - ARRÊT (fondu 0,2 s) : bouger (MoveDirection ou manette > 0,1),
	    sauter (JumpRequest / Jumping / StateChanged), nouvelle émote,
	    s'asseoir, mode édition, bouton ⏹, sortie de la ville, mort ou
	    retrait du personnage (TownClient appelle Stop / Detach) ;
	  - "s'asseoir" (par terre) : bouger ou sauter relève l'avatar
	    (Humanoid.Sit = false) ; bouton "Se lever" pendant qu'on est assis
	    (sur un siège aussi : TownClient demande en plus au serveur de
	    détruire le Seat).
	État lu par le HUD : State() -> "Emote" | "Sit" | nil (OnChanged).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TownEmotes = {}
TownEmotes.__index = TownEmotes

local FADE = 0.2
local MOVE_THRESHOLD = 0.1
-- émotes qui bouclent jusqu'à l'arrêt ; les autres se jouent une fois
local LOOPED: { [string]: boolean } = { dance = true, dance2 = true, dance3 = true }
-- (sécurité) une émote "une fois" dont la durée est inconnue s'arrête au bout de…
local ONE_SHOT_MAX = 6

export type Hooks = {
	OnChanged: ((state: string?, name: string?) -> ())?,
	Toast: ((text: string) -> ())?,
}

-- Manette de Roblox (PlayerModule) : vecteur de déplacement même assis
local function controlsOf(): any
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, controls = pcall(function()
		return (require(module) :: any):GetControls()
	end)
	return ok and controls or nil
end

function TownEmotes.new(hooks: Hooks?)
	local self = setmetatable({
		Hooks = hooks or {},
		Character = nil :: Model?,
		Humanoid = nil :: Humanoid?,
		Tracks = {} :: { AnimationTrack },
		Name = nil :: string?,
		Looped = false,
		Own = false, -- pistes chargées par nous (détruites après l'arrêt)
		Started = 0,
		Length = 0,
		Sitting = false,
		Connections = {} :: { RBXScriptConnection },
		TrackConnections = {} :: { RBXScriptConnection },
		Controls = nil :: any,
		ControlsTried = false,
		LastState = nil :: string?,
		Stops = {} :: { [string]: number }, -- (tests) arrêts par raison
	}, TownEmotes)
	return self
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

function TownEmotes.State(self: any): string?
	if self.Name then
		return "Emote"
	end
	if self.Sitting then
		return "Sit"
	end
	return nil
end

function TownEmotes.IsPlaying(self: any): boolean
	return self.Name ~= nil
end

function TownEmotes.Notify(self: any)
	local state = self:State()
	local key = tostring(state) .. "|" .. tostring(self.Name)
	if key == self.LastState then
		return
	end
	self.LastState = key
	local hook = self.Hooks.OnChanged
	if hook then
		local ok, err = pcall(hook, state, self.Name)
		if not ok then
			warn("[TownEmotes] " .. tostring(err))
		end
	end
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

----------------------------------------------------------------------
-- Arrêt
----------------------------------------------------------------------

-- Arrête l'émote en cours (fondu 0,2 s). `reason` : "move", "jump", "new",
-- "sit", "edit", "button", "leave", "removed", "ended"…
function TownEmotes.Stop(self: any, reason: string?)
	local tracks = self.Tracks
	local had = self.Name ~= nil
	local own = self.Own
	local humanoid = self.Humanoid
	if had and #tracks == 0 and not own and humanoid then
		-- (émote équipée dont on n'a pas vu la piste : on coupe les pistes
		-- "Action" en cours, jamais la marche / l'attente du script Animate)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			pcall(function()
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if track.Priority.Value >= Enum.AnimationPriority.Action.Value then
						table.insert(tracks, track)
					end
				end
			end)
		end
	end
	self.Tracks = {}
	self.Own = false
	self.Name = nil
	self.Looped = false
	disconnectAll(self.TrackConnections)
	for _, track in ipairs(tracks) do
		pcall(function()
			track:Stop(FADE)
		end)
	end
	if own and #tracks > 0 then
		-- (pistes chargées par nous : libérées après le fondu)
		task.delay(FADE + 0.1, function()
			for _, track in ipairs(tracks) do
				pcall(function()
					if not track.IsPlaying then
						track:Destroy()
					end
				end)
			end
		end)
	end
	if had then
		local key = reason or "?"
		self.Stops[key] = (self.Stops[key] or 0) + 1
	end
	self:Notify()
end

-- Relève l'avatar (assis par terre ou sur un siège)
function TownEmotes.StandUp(self: any)
	local humanoid = self.Humanoid
	if not humanoid then
		return
	end
	local seated = humanoid.SeatPart ~= nil
	pcall(function()
		humanoid.Sit = false
	end)
	if seated then
		-- (comme la touche "sauter" : Roblox détache le siège)
		pcall(function()
			humanoid.Jump = true
		end)
	end
	self.Sitting = false
	self:Notify()
end

----------------------------------------------------------------------
-- Personnage
----------------------------------------------------------------------

function TownEmotes.RefreshSit(self: any)
	local humanoid = self.Humanoid
	local sitting = humanoid ~= nil and (humanoid.Sit or humanoid.SeatPart ~= nil)
	if sitting ~= self.Sitting then
		self.Sitting = sitting
		if sitting and self.Name then
			self:Stop("sit")
		end
		self:Notify()
	end
end

-- Mouvement demandé (manette, clavier, joystick tactile) ?
function TownEmotes.MoveMagnitude(self: any): number
	local humanoid = self.Humanoid
	local magnitude = humanoid and humanoid.MoveDirection.Magnitude or 0
	if not self.ControlsTried then
		self.ControlsTried = true
		self.Controls = controlsOf()
	end
	local controls = self.Controls
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			magnitude = math.max(magnitude, vector.Magnitude)
		end
	end
	return magnitude
end

-- Bouger : arrête l'émote ; relève l'avatar assis PAR TERRE (pas un siège :
-- on ne se lève pas d'un canapé en touchant le joystick par erreur)
function TownEmotes.OnMove(self: any)
	if self:MoveMagnitude() <= MOVE_THRESHOLD then
		return
	end
	if self.Name then
		self:Stop("move")
	end
	local humanoid = self.Humanoid
	if humanoid and humanoid.Sit and humanoid.SeatPart == nil then
		self:StandUp()
	end
end

-- Sauter : arrête l'émote et relève l'avatar (par terre ou siège)
function TownEmotes.OnJump(self: any)
	if self.Name then
		self:Stop("jump")
	end
	local humanoid = self.Humanoid
	if humanoid and (humanoid.Sit or humanoid.SeatPart ~= nil) then
		self:StandUp()
	end
end

function TownEmotes.Attach(self: any, character: Model?)
	self:Detach()
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	self.Character = character
	self.Humanoid = humanoid
	local list = self.Connections
	table.insert(list, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		self:OnMove()
	end))
	table.insert(list, humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
		self:RefreshSit()
	end))
	table.insert(list, humanoid.Seated:Connect(function()
		self:RefreshSit()
	end))
	table.insert(list, humanoid.Jumping:Connect(function(active: boolean)
		if active and self.Name then
			self:Stop("jump")
		end
	end))
	table.insert(list, humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			if self.Name then
				self:Stop("jump")
			end
		elseif new == Enum.HumanoidStateType.Seated then
			self:RefreshSit()
		elseif new == Enum.HumanoidStateType.Dead then
			self:Stop("removed")
		end
	end))
	table.insert(list, humanoid.Died:Connect(function()
		self:Stop("removed")
		self.Sitting = false
		self:Notify()
	end))
	table.insert(list, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.Character == character then
			self:Detach()
		end
	end))
	-- (touche "sauter" même assis : Humanoid.Jumping ne vient pas toujours)
	table.insert(list, UserInputService.JumpRequest:Connect(function()
		self:OnJump()
	end))
	self.Sitting = false
	self:RefreshSit()
	self:Notify()
end

-- Personnage retiré / sortie : tout s'arrête, plus aucune connexion
function TownEmotes.Detach(self: any)
	if self.Name then
		self:Stop("removed")
	end
	disconnectAll(self.Connections)
	disconnectAll(self.TrackConnections)
	self.Character = nil
	self.Humanoid = nil
	self.Sitting = false
	self:Notify()
end

----------------------------------------------------------------------
-- Jouer
----------------------------------------------------------------------

-- Animation du script Animate de l'avatar (R15 / R6) : Animate > nom > Animation
local function findAnimation(character: Model, name: string): Animation?
	local animate = character:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild(name)
	if not holder then
		return nil
	end
	if holder:IsA("Animation") then
		return holder
	end
	local choices: { Animation } = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(choices, child)
		end
	end
	if #choices == 0 then
		return nil
	end
	return choices[math.random(1, #choices)]
end

function TownEmotes.Track(self: any, tracks: { AnimationTrack }, name: string, looped: boolean, own: boolean)
	self.Tracks = tracks
	self.Own = own
	self.Name = name
	self.Looped = looped
	self.Started = os.clock()
	self.Length = 0
	for _, track in ipairs(tracks) do
		local ok, length = pcall(function()
			return track.Length
		end)
		if ok and type(length) == "number" then
			self.Length = math.max(self.Length, length)
		end
		-- (émote "une fois" : finie -> état remis ; une piste coupée par
		-- Roblox ou par le script Animate aussi)
		table.insert(self.TrackConnections, track.Stopped:Connect(function()
			if self.Name == name and table.find(self.Tracks, track) then
				local playing = false
				for _, other in ipairs(self.Tracks) do
					if other ~= track and other.IsPlaying then
						playing = true
					end
				end
				if not playing then
					self:Stop("ended")
				end
			end
		end))
	end
	self:Notify()
end

-- Joue une émote ; renvoie true si quelque chose se joue
function TownEmotes.Play(self: any, name: string): boolean
	local humanoid = self.Humanoid
	local character = self.Character
	if not humanoid or not character or humanoid.Health <= 0 then
		return false
	end
	-- une nouvelle émote remplace toujours l'ancienne
	self:Stop("new")
	if name == "sit" then
		pcall(function()
			humanoid.Sit = true
		end)
		self.Sitting = true
		self:Notify()
		return true
	end
	if humanoid.Sit or humanoid.SeatPart ~= nil then
		self:StandUp()
	end
	local looped = LOOPED[name] == true
	local animator = humanoid:FindFirstChildOfClass("Animator")
	-- 1) animation du script Animate (R15 ou R6), piste à nous
	local animation = findAnimation(character, name)
	if animation and animator then
		local ok, track = pcall(function()
			local t = animator:LoadAnimation(animation)
			t.Priority = Enum.AnimationPriority.Action
			t.Looped = looped
			t:Play(FADE)
			return t
		end)
		if ok and track then
			self:Track({ track }, name, looped, true)
			return true
		end
	end
	-- 2) émote équipée de l'avatar (Humanoid:PlayEmote) : on repère ses pistes
	local before: { [AnimationTrack]: boolean } = {}
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			before[track] = true
		end
	end
	local ok, played = pcall(humanoid.PlayEmote, humanoid, name)
	if ok and played then
		local started: { AnimationTrack } = {}
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if not before[track] then
					table.insert(started, track)
				end
			end
		end
		self:Track(started, name, looped, false)
		return true
	end
	local toast = self.Hooks.Toast
	if toast then
		pcall(toast, "This emote isn't available for your avatar")
	end
	return false
end

-- ~10 fois / s (TownClient) : filet de sécurité si un signal manque
function TownEmotes.Step(self: any)
	local humanoid = self.Humanoid
	if not humanoid then
		return
	end
	if humanoid.Parent == nil or humanoid.Health <= 0 then
		if self.Name then
			self:Stop("removed")
		end
		return
	end
	self:RefreshSit()
	if self.Name then
		self:OnMove()
	elseif humanoid.Sit and humanoid.SeatPart == nil then
		self:OnMove()
	end
	if self.Name and not self.Looped then
		local limit = (self.Length > 0 and self.Length + 0.4) or ONE_SHOT_MAX
		local anyPlaying = #self.Tracks == 0
		for _, track in ipairs(self.Tracks) do
			if track.IsPlaying then
				anyPlaying = true
			end
		end
		if not anyPlaying or os.clock() - self.Started > math.min(limit, ONE_SHOT_MAX) then
			self:Stop("ended")
		end
	end
end

return TownEmotes
