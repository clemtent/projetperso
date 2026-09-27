--[[
	FR_V9_Arcade (ModuleScript) — traductions françaises (v9, agent ARCADESHOP)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V9_Arcade

	🎟️ Tickets achetables (packs de la boutique Robux, fenêtre "Pas assez de
	tickets"), 🏆 trophées (mises des duels), onglets / sections / "Bientôt"
	de la boutique Robux, combos et objets stylés (Config.Monetization).
]]

return {
	fr = {
		-- Packs de tickets (Config.Monetization.Products)
		["Pocket tickets"] = "Tickets de poche",
		["5 arcade tickets"] = "5 tickets d'arcade",
		["Ticket strip"] = "Bande de tickets",
		["10 arcade tickets"] = "10 tickets d'arcade",
		["Ticket bundle"] = "Paquet de tickets",
		["25 arcade tickets"] = "25 tickets d'arcade",
		["Ticket basket"] = "Panier de tickets",
		["50 arcade tickets"] = "50 tickets d'arcade",
		["Ticket crate"] = "Caisse de tickets",
		["100 arcade tickets"] = "100 tickets d'arcade",

		-- Bientôt : combos et objets stylés
		["Starter combo"] = "Combo débutant",
		["20 tickets + 30 minutes of production"] = "20 tickets + 30 minutes de production",
		["Mega combo"] = "Méga combo",
		["60 tickets + 2 hours of production"] = "60 tickets + 2 heures de production",
		["Ultimate combo"] = "Combo ultime",
		["150 tickets + 8 hours of production"] = "150 tickets + 8 heures de production",
		["Golden trail"] = "Traînée dorée",
		["Golden sparkles follow your cursor"] = "Des étincelles dorées suivent ton curseur",
		["Rainbow aura"] = "Aura arc-en-ciel",
		["Every click bursts into a rainbow ring"] = "Chaque clic éclate en arc-en-ciel",
		["Neon name tag"] = "Tag néon",
		["A glowing neon tag next to your name"] = "Un tag néon brillant près de ton nom",
		["Diamond button"] = "Bouton diamant",
		["Your big button, cut like a diamond"] = "Ton gros bouton taillé en diamant",
		["Animated frame"] = "Cadre animé",
		["An animated frame around your avatar"] = "Un cadre animé autour de ton avatar",

		-- Boutique Robux : onglets, sections, cartes
		["♾️ Passes"] = "♾️ Passes",
		["💧 Dopamine"] = "💧 Dopamine",
		["⚡ Boosts"] = "⚡ Boosts",
		["🎟️ Tickets"] = "🎟️ Tickets",
		["🔜 Soon"] = "🔜 Bientôt",
		["♾️ Game Passes"] = "♾️ Game Passes",
		["Bought once, yours forever"] = "Achetés une fois, à toi pour toujours",
		["💧 Dopamine packs"] = "💧 Packs de Dopamine",
		["Instant Dopamine, scaled to your production"] = "Dopamine immédiate, selon ta production",
		["Earn more for a little while"] = "Gagne plus pendant un moment",
		["🎟️ Arcade tickets"] = "🎟️ Tickets d'arcade",
		["🎁 Combos"] = "🎁 Combos",
		["Tickets + Dopamine in one pack"] = "Tickets + Dopamine dans un seul pack",
		["✨ Stylish items"] = "✨ Objets stylés",
		["Cosmetics: just for the look"] = "Cosmétiques : juste pour le style",
		["🔜 Coming soon"] = "🔜 Bientôt",
		["COMING SOON"] = "BIENTÔT",
		["💸 −%s%% per ticket"] = "💸 −%s %% par ticket",
		["🕹️ For the arcade"] = "🕹️ Pour l'arcade",
		["✨ Just for style"] = "✨ Juste pour le style",
		["👉 Best fit"] = "👉 Conseillé",
		["You have %s %s"] = "Tu as %s %s",
		["For the 🕹️ arcade ticket shop"] = "Pour la boutique à tickets de l'🕹️ arcade",
		["🎟️ Tickets buy treats, boosts and badges in the arcade. %s Duel trophies can't be bought: they're earned only by playing."] =
			"🎟️ Les tickets achètent friandises, boosts et badges à l'arcade. %s Les trophées des duels ne s'achètent pas : ils se gagnent seulement en jouant.",

		-- Achat confirmé (MonetizationService)
		["💎 Thank you! %s %s: +%s 🎟️ tickets (you have %s)"] = "💎 Merci ! %s %s : +%s 🎟️ tickets (tu en as %s)",
		["🎟️ +%s TICKETS!"] = "🎟️ +%s TICKETS !",
		["💎 Thank you! %s %s: +%s 🎟️ tickets and +%s %s"] = "💎 Merci ! %s %s : +%s 🎟️ tickets et +%s de %s",
		["🎁 COMBO UNLOCKED!"] = "🎁 COMBO DÉBLOQUÉ !",

		-- Pas assez de tickets (NeedTickets)
		["Not enough tickets!"] = "Pas assez de tickets !",
		["You need %s more tickets for %s."] = "Il te manque %s tickets pour %s.",
		["You need %s more tickets."] = "Il te manque %s tickets.",
		["Best fit: %s • +%s tickets"] = "Le plus adapté : %s • +%s tickets",
		["🕹️ Win arcade games to earn tickets!"] = "🕹️ Gagne des parties d'arcade pour avoir des tickets !",
		["🕹️ Or win arcade games: tickets are free to earn."] = "🕹️ Ou gagne des parties d'arcade : les tickets se gagnent gratuitement.",
		["🎟️ Buy tickets"] = "🎟️ Acheter des tickets",

		-- Arcade : portefeuille, 🏆 trophées (mises des duels)
		["🎟️ Tickets: for the ticket shop • 🏆 Trophies: duel stakes, earned only by playing"] =
			"🎟️ Tickets : pour la boutique • 🏆 Trophées : mises des duels, gagnés seulement en jouant",
		["🏅 Records"] = "🏅 Records",
		["for the shop"] = "pour la boutique",
		["for duels"] = "pour les duels",
		["Today: %s / %s %s • %s / %s %s"] = "Aujourd'hui : %s / %s %s • %s / %s %s",
		["Challenge a player of this server • stakes in %s trophies"] = "Défie un joueur de ce serveur • mises en %s trophées",
		["2. Stake in %s trophies (you have %s)"] = "2. Mise en %s trophées (tu en as %s)",
		["🏆 Stakes in trophies, never sold\n🥇 Winner: both stakes + Dopamine + bonus 🎟️\n🏳️ Leaving or giving up = defeat"] =
			"🏆 Mises en trophées, jamais vendus\n🥇 Gagnant : les deux mises + Dopamine + 🎟️ bonus\n🏳️ Partir ou abandonner = défaite",
		["Win tickets by playing, or get more in the 💎 shop. Duels use 🏆 trophies instead."] =
			"Gagne des tickets en jouant, ou prends-en dans la boutique 💎. Les duels se jouent en 🏆 trophées.",
		["🎟️ Get tickets"] = "🎟️ Avoir des tickets",
		["Trophies earned"] = "Trophées gagnés",
		["Not enough 🏆"] = "Pas assez de 🏆",
		["Not enough trophies: win arcade games to earn some!"] = "Pas assez de trophées : gagne des parties d'arcade pour en avoir !",
		["%s doesn't have enough trophies for this stake"] = "%s n'a pas assez de trophées pour cette mise",
		["%s doesn't have enough trophies anymore"] = "%s n'a plus assez de trophées",
		["⚔️ %s beat %s at %s and won %s 🏆!"] = "⚔️ %s a battu %s (%s) et gagne %s 🏆 !",
		["Up to 🎟️ %s · 🏆 %s · 🧠 %s"] = "Jusqu'à 🎟️ %s · 🏆 %s · 🧠 %s",
	},
}
