--[[
	FR_V11_Train (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V11_Train

	Traductions françaises de TRAIN11 (v11) : le train de Dopamine Town
	(Shared/TrainLine, TrainService, TrainClient, TrainModels, TrainHud) et
	le braquage du convoi de diamants (étapes passées au HeistKit de BANK11).
]]

return {
	fr = {
		-- trains et gares (TrainLine)
		["Dopamine Express"] = "Dopamine Express",
		["Belt shuttle"] = "Navette de la ceinture",
		["Lofts station"] = "Gare des Lofts",
		["Sports park station"] = "Gare du Parc des Sports",
		["Hills station"] = "Gare des Collines",
		["Cottages station"] = "Gare des Cottages",
		["Train"] = "Train",
		["Station"] = "Gare",
		-- serveur (TrainService)
		["Finish the heist first!"] = "Termine d'abord le braquage !",
		["Wait for the train to stop"] = "Attends que le train s'arrête",
		["This carriage is full"] = "Cette voiture est pleine",
		["Diamond convoy"] = "Convoi de diamants",
		["🚂💎 The diamond convoy is coming! Gather on the station platform"] = "🚂💎 Le convoi de diamants arrive ! Rendez-vous sur le quai de la gare",
		["Pry open the armoured wagon door"] = "Force le volet du wagon blindé",
		["Hack the security box"] = "Pirate le boîtier de sécurité",
		["Drill the safe"] = "Perce le coffre-fort",
		["Fill the bags with diamonds"] = "Remplis les sacs de diamants",
		["Bring the loot to the hideout"] = "Apporte le butin à la planque",
		["The convoy left the station!"] = "Le convoi est reparti !",
		-- client (TrainClient, TrainHud, TrainModels)
		["Board"] = "Monter",
		["Sit"] = "S'asseoir",
		["Get off"] = "Descendre",
		["Next stop: %s"] = "Prochain arrêt : %s",
		["departs in %s"] = "départ dans %s",
		["At platform"] = "À quai",
		["AT PLATFORM"] = "À QUAI",
		["Belt line · 4 stations"] = "Ligne de ceinture · 4 gares",
		["The diamond convoy stops at %s in %s"] = "Le convoi de diamants s'arrête à %s dans %s",
		["%d studs away · gather on the platform"] = "à %d studs · rendez-vous sur le quai",
		["The convoy is at %s: %s left to crack the vault!"] = "Le convoi est à %s : %s pour ouvrir le coffre !",
		["%d studs away"] = "à %d studs",
		["The diamond convoy stops at %s in 2 min!"] = "Le convoi de diamants s'arrête à %s dans 2 min !",
		["The diamond convoy is at %s!"] = "Le convoi de diamants est à %s !",
		["DIAMOND CONVOY"] = "CONVOI DE DIAMANTS",
		["ACCESS GRANTED"] = "ACCÈS AUTORISÉ",
		["LOCKED"] = "VERROUILLÉ",
		["Hideout"] = "Planque",
	},
}
