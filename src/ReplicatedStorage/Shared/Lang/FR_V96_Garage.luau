--[[
	FR_V96_Garage (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V96_Garage

	Traductions françaises de v9.6 (GARAGE96) : 🚗 voitures (Config.Cars :
	modèles, peintures), 🏎️ garage du manoir (Config.House.Garage),
	CarService (achats, conduite) et CarClient (HUD de conduite, "Mes
	voitures", invite "Conduire").
]]

return {
	fr = {
		-- Config.Cars : modèles
		["Bubble car"] = "Voiture bulle",
		["A tiny round kawaii car"] = "Une toute petite voiture ronde et kawaii",
		["City car"] = "Citadine",
		["Small, cute and easy to park"] = "Petite, mignonne et facile à garer",
		["Hatchback"] = "Compacte",
		["Five doors and a roof spoiler"] = "Cinq portes et un becquet",
		["Pickup truck"] = "Pick-up",
		["Big wheels and a cargo bed"] = "Grosses roues et une benne",
		["Family SUV"] = "SUV familial",
		["Tall, comfy, roof rails and spare wheel"] = "Haut, confortable, barres de toit et roue de secours",
		["Camper van"] = "Combi",
		["Two-tone camper for road trips"] = "Combi bicolore pour les road trips",
		["Sports roadster"] = "Roadster sport",
		["Convertible, rear wing, twin exhausts"] = "Décapotable, aileron, double échappement",
		["Stretch limo"] = "Limousine",
		["The longest car in town, chrome everywhere"] = "La plus longue voiture de la ville, des chromes partout",
		-- Config.Cars : peintures (les autres existent déjà)
		["Cherry red"] = "Rouge cerise",
		["Tangerine"] = "Mandarine",
		["Racing green"] = "Vert anglais",
		["Pearl white"] = "Blanc nacré",
		["Midnight black"] = "Noir minuit",
		-- Config.House.Garage
		["Mansion garage"] = "Garage du manoir",
		-- CarService
		["Walk around the town first"] = "Entre d'abord dans la ville",
		["🚗 Buy a car at the car dealership first!"] = "🚗 Achète d'abord une voiture à la concession !",
		["🚫 Go outside to take your car"] = "🚫 Sors dehors pour prendre ta voiture",
		["%s Let's drive! WASD / arrows, jump to get out"] = "%s En route ! ZQSD / flèches, saute pour sortir",
		["🔒 This is %s's car"] = "🔒 C'est la voiture de %s",
		["🚗 Your car went back to the garage"] = "🚗 Ta voiture est rentrée au garage",
		["🔄 Back on its wheels!"] = "🔄 De nouveau sur ses roues !",
		["You already own this car"] = "Tu as déjà cette voiture",
		["%s %s is yours! Drive it in Dopamine Town (%s)"] = "%s %s est à toi ! Conduis-la dans Dopamine Town (%s)",
		["You already have a garage"] = "Tu as déjà un garage",
		["🏰 You need the %s first"] = "🏰 Il te faut d'abord le %s",
		["%s Your garage is built! Your cars are parked inside"] = "%s Ton garage est construit ! Tes voitures y sont garées",
		["🎨 %s applied"] = "🎨 %s appliquée",
		["%s %s selected"] = "%s %s choisie",
		["🚫 No cars inside!"] = "🚫 Pas de voiture à l'intérieur !",
		-- CarClient
		["Drive"] = "Conduire",
		["My car"] = "Ma voiture",
		["My cars"] = "Mes voitures",
		["Honk"] = "Klaxon",
		["Reset car"] = "Remettre",
		["Get out"] = "Sortir",
		["🏎️ My cars"] = "🏎️ Mes voitures",
		["Drive this one"] = "Conduire celle-ci",
		["No car yet: visit the 🚗 car dealership next to the welcome square!"] = "Pas encore de voiture : va à la 🚗 concession, à côté de la place d'accueil !",
		["🏎️ Your garage is built: your cars are parked in front of your mansion"] = "🏎️ Ton garage est construit : tes voitures sont garées devant ton manoir",
		["🏎️ Garage: only for the %s"] = "🏎️ Garage : seulement pour le %s",
		["🏎️ Build a 3-car garage next to your mansion"] = "🏎️ Construis un garage de 3 places devant ton manoir",
		["WASD / arrows to drive · Space to get out"] = "ZQSD / flèches pour conduire · Espace pour sortir",
	},
}
