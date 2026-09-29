--[[
	FR_V98_Fair (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V98_Fair

	Traductions françaises de FAIR98 (v9.8) : fête foraine (manèges,
	invites, panneaux), nourriture (Config.Food, FoodService, menu des
	stands, badge du boost). Clés déjà ailleurs (réutilisées) : "Invalid
	request", "Not enough %s", "Slow down a little!", "Buy", "Network
	error, try again.", "You need %s more Dopamine", "👆 Click to earn
	more!", "Snacks".
]]

return {
	fr = {
		-- manèges
		["Big wheel"] = "Grande roue",
		["Carousel"] = "Manège",
		["Teacups"] = "Tasses",
		["Swing ride"] = "Chaises volantes",
		["Drop tower"] = "Tour de chute",
		["Bumper cars"] = "Autos tamponneuses",
		["Ride"] = "Monter",
		["Order"] = "Commander",
		["Fun fair"] = "Fête foraine",
		["Duck fishing"] = "Pêche aux canards",
		["Snack corner"] = "Coin gourmand",
		["Departure in %s s"] = "Départ dans %s s",
		["Running"] = "En marche",
		-- stands
		["🥖 Churros & crêpes"] = "🥖 Churros & crêpes",
		["🍩 Donuts & shakes"] = "🍩 Beignets & milkshakes",
		["🍿 Popcorn & candy floss"] = "🍿 Pop-corn & barbe à papa",
		["🌭 Hot dogs & candy apples"] = "🌭 Hot-dogs & pommes d'amour",
		["🍦 Ice cream & shakes"] = "🍦 Glaces & milkshakes",
		["🌮 Tacos & pizza"] = "🌮 Tacos & pizza",
		-- aliments (Config.Food)
		["Ice cream cone"] = "Cornet de glace",
		["Candy floss"] = "Barbe à papa",
		["Churros"] = "Churros",
		["Popcorn"] = "Pop-corn",
		["Crêpe"] = "Crêpe",
		["Pizza slice"] = "Part de pizza",
		["Taco"] = "Taco",
		["Milkshake"] = "Milkshake",
		["Hot dog"] = "Hot-dog",
		["Candy apple"] = "Pomme d'amour",
		["Donut"] = "Beignet",
		-- menu, badge, bouchées
		["Eat it for a Dopamine boost! One boost at a time, it stacks up to 5 min."] = "Mange-le pour un boost de Dopamine ! Un boost à la fois, cumulable jusqu'à 5 min.",
		["Take a bite"] = "Croquer",
		["Boost"] = "Boost",
		["Dopamine boost %s for %s!"] = "Boost de Dopamine %s pendant %s !",
		-- serveur (FoodService)
		["Walk to a food stall in Dopamine Town"] = "Va à un stand de nourriture de Dopamine Town",
		["Walk closer to the stall"] = "Approche-toi du stand",
		["Finish what you're eating first! 🍴"] = "Finis d'abord ce que tu manges ! 🍴",
		["%s %s! Click to take a bite (%s)"] = "%s %s ! Clique pour croquer (%s)",
		["You're not holding any food"] = "Tu n'as rien à manger en main",
	},
}
