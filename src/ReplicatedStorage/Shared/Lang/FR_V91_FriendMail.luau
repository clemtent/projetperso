--[[
	Traductions françaises (v9.1) : mails entre amis Roblox
	(Client > Stimuli > Email, ServerScriptService > Services > FriendMailService)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V91_FriendMail
]]
return {
	fr = {
		-- Liste, dossiers, lecture
		["%d d"] = "%d j",
		["FRIEND 💌"] = "AMI 💌",
		["No friend mail yet. Tap ✏️ Write to send one to a Roblox friend!"] = "Aucun mail d'ami pour l'instant. Touche ✏️ Écrire pour en envoyer un à un ami Roblox !",
		["✏️ Write"] = "✏️ Écrire",
		["↩️ You answered this mail."] = "↩️ Tu as répondu à ce mail.",
		["💌 From your Roblox friend, filtered by Roblox. Friend mails give no Dopamine: just friendship!"] = "💌 De ton ami Roblox, filtré par Roblox. Les mails d'amis ne rapportent pas de Dopamine : juste de l'amitié !",
		["💌 Sent to your Roblox friend. Roblox filters it for them too."] = "💌 Envoyé à ton ami Roblox. Roblox le filtre aussi pour lui.",
		["🚩 Report"] = "🚩 Signaler",
		["⛔ Block"] = "⛔ Bloquer",
		["⚠️ Sure?"] = "⚠️ Sûr ?",
		["🗑️ Friend mail deleted"] = "🗑️ Mail d'ami supprimé",
		["🚩 Reported: mail hidden and %s blocked"] = "🚩 Signalé : mail caché et %s bloqué",
		["⛔ %s is blocked: no more mails from them"] = "⛔ %s est bloqué : plus aucun mail de sa part",
		["💌 A friend sent you a mail!"] = "💌 Un ami t'a envoyé un mail !",
		["💌 %d friend mails are waiting for you!"] = "💌 %d mails d'amis t'attendent !",

		-- Rédaction : onglets, amis, présence
		["🎭 Characters"] = "🎭 Personnages",
		["👥 Friends"] = "👥 Amis",
		["💌 Mail a friend"] = "💌 Écrire à un ami",
		["Here"] = "Ici",
		["Online"] = "En ligne",
		["Offline"] = "Hors ligne",
		["🚫 Blocked"] = "🚫 Bloqué",
		["👥 Pick a friend to write to"] = "👥 Choisis l'ami à qui écrire",
		["Pick a friend first 👆"] = "Choisis d'abord un ami 👆",
		["💌 %s is here: delivered instantly"] = "💌 %s est ici : livré tout de suite",
		["💌 %s is online: delivered in a few seconds"] = "💌 %s est en ligne : livré en quelques secondes",
		["💌 %s is offline: it will wait in their Dopamail"] = "💌 %s est hors ligne : le mail l'attendra dans son Dopamail",
		["Loading your Roblox friends…"] = "Chargement de tes amis Roblox…",
		["No Roblox friends yet. Add friends on Roblox, then mail them from here!"] = "Pas encore d'amis Roblox. Ajoute des amis sur Roblox, puis écris-leur d'ici !",
		["🔄 Retry"] = "🔄 Réessayer",
		["🚫 %s is blocked. Tap here to unblock"] = "🚫 %s est bloqué. Touche ici pour le débloquer",
		["✅ %s is unblocked"] = "✅ %s est débloqué",
		["⏳ Next friend mail in %s (1 every 10 min)"] = "⏳ Prochain mail d'ami dans %s (1 toutes les 10 min)",
		["⏳ Next reply in %s (1 every 2 min)"] = "⏳ Prochaine réponse dans %s (1 toutes les 2 min)",
		["💌 Delivered to %s!"] = "💌 Livré à %s !",
		["💌 Sent to %s! It's waiting in their Dopamail"] = "💌 Envoyé à %s ! Il l'attend dans son Dopamail",

		-- Indisponible (Studio, panne)
		["🛠️ Friend mail is unavailable in Studio: it works in the published game!"] = "🛠️ Mails d'amis indisponibles dans Studio : ça marche dans le jeu publié !",
		["Friend mail is unavailable in Studio (API services are off). It works in the published game!"] = "Mails d'amis indisponibles dans Studio (services API coupés). Ça marche dans le jeu publié !",
		["Friend mail is unavailable right now. Try again in a moment!"] = "Mails d'amis indisponibles pour le moment. Réessaie dans un instant !",
		["Friend mail is unavailable in Studio"] = "Mails d'amis indisponibles dans Studio",
		["Friend mail is unavailable right now"] = "Mails d'amis indisponibles pour le moment",
		["Couldn't load your friends"] = "Impossible de charger tes amis",

		-- Refus du serveur
		["Friend mail is busy, try again in a minute"] = "Les mails d'amis sont très demandés, réessaie dans une minute",
		["Next friend mail in %s"] = "Prochain mail d'ami dans %s",
		["This mail can't be answered anymore"] = "On ne peut plus répondre à ce mail",
		["You already answered this mail"] = "Tu as déjà répondu à ce mail",
		["You can only mail your Roblox friends"] = "Tu ne peux écrire qu'à tes amis Roblox",
		["Your account settings don't allow private messages"] = "Les réglages de ton compte n'autorisent pas les messages privés",
		["This friend can't receive messages (privacy settings)"] = "Cet ami ne peut pas recevoir de messages (réglages de confidentialité)",
		["Too many blocked players"] = "Trop de joueurs bloqués",
	},
}
