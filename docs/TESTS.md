# ✅ Checklist de test dans Roblox Studio

## Avant de tester

- [ ] Le jeu est **publié** (Fichier > Publier sur Roblox).
- [ ] **Enable Studio Access to API Services** est activé (Paramètres du jeu > Sécurité).
- [ ] La fenêtre **Sortie** est ouverte (Affichage > Sortie) : elle affiche les erreurs.
- [ ] Au lancement, la Sortie affiche `[Dopamine Clicker] Serveur prêt`.

## Commandes de test (Studio uniquement)

Tape-les dans le chat pendant un test **Play** :

| Commande | Effet |
|---|---|
| `/give 1e6` | Donne 1 million de Dopamine (n'importe quel nombre : `/give 5e12`) |
| `/rush` | Lance un Dopamine Rush immédiatement |
| `/golden` | Fait apparaître un objet doré |
| `/corner` | Le logo DVD touchera un coin dans ~2 s (test du jackpot) |
| `/daily` | Rend le cadeau du jour à nouveau disponible |
| `/save` | Force une sauvegarde |

Ces commandes sont **désactivées** automatiquement dans le jeu publié. Dans Studio, les événements aléatoires arrivent aussi **5 fois plus vite** (`Config.Events.StudioSpeedup`).

## Gameplay

- [ ] Le gros bouton s'écrase et rebondit à chaque clic.
- [ ] Un « +X » apparaît, monte et disparaît, à une position légèrement différente à chaque fois.
- [ ] Des particules jaillissent et un son est joué (plus aigu avec le combo).
- [ ] Le compteur de Dopamine augmente instantanément et affiche `1K`, `1M`… (teste avec `/give 1e9`).
- [ ] « / clic » et « / s » sont corrects après un achat.
- [ ] En cliquant vite (> 5 clics/s), la barre de combo se remplit jusqu'à `x3` et « COMBO MAX ! » apparaît.
- [ ] La barre de combo redescend quand tu arrêtes.

## Boutique

- [ ] Les 3 onglets (CLIC / PASSIF / MULTI) affichent les bonnes cartes.
- [ ] Un bouton est **grisé** si tu n'as pas assez de Dopamine ; cliquer dessus le fait trembler.
- [ ] Un achat retire la Dopamine, augmente le niveau et le coût, joue un son.
- [ ] Le mode **x1 → x10 → MAX** change le nombre de niveaux et le prix affiché.
- [ ] Un multiplicateur acheté affiche « ACHETÉ ✔ » et le multiplicateur du HUD augmente.
- [ ] Les générateurs passifs font monter la Dopamine sans cliquer.

## Logo DVD

- [ ] Le logo se déplace en diagonale de façon fluide et rebondit sur les 4 bords.
- [ ] Il change de couleur à chaque rebond.
- [ ] Le cliquer donne un bonus « +X » ; il devient transparent pendant la recharge.
- [ ] `/corner` → **JACKPOT !!! COIN PARFAIT** + confettis + son + bandeau.
- [ ] Redimensionne la fenêtre de Studio / teste en mode appareil (Test > Appareil) : le logo reste dans l'écran.

## Systèmes

- [ ] **Quêtes** : la progression avance, une quête finie donne sa récompense et est remplacée.
- [ ] **Succès** : après 100 clics, « SUCCÈS DÉBLOQUÉ » s'affiche avec confettis ; le panneau le montre débloqué.
- [ ] **Rebirth** : avec `/give 1e6`, la pastille « ! » apparaît ; le rebirth demande une confirmation, remet à zéro et augmente le multiplicateur.
- [ ] **Cadeau quotidien** : s'ouvre automatiquement au premier lancement ; après récupération, affiche le compte à rebours.
- [ ] **Rush** (`/rush`) : bannière jaune avec compte à rebours, gains doublés, fond qui s'accélère.
- [ ] **Objet doré** (`/golden`) : apparaît, tourne, disparaît après 6 s ; le cliquer donne un gros bonus.
- [ ] **Paramètres** : couper le son coupe les clics ; l'option est conservée après avoir relancé.
- [ ] **Classement** : se remplit après ~5 s (uniquement dans un jeu publié avec l'accès aux API).

## Sauvegarde

- [ ] Gagne de la Dopamine, achète des améliorations, attends quelques secondes, **Stop**, puis **Play** : tout est conservé.
- [ ] Test à plusieurs : **Test > Clients et serveurs > 2 joueurs** : chaque joueur a ses propres données ; le Rush s'applique à tous.

## Responsive / mobile

- [ ] **Test > Appareil** : teste iPhone, iPad, téléphone Android et un écran 4K : rien ne dépasse, tout reste lisible.

---

# 🐞 Erreurs courantes

| Symptôme / message | Cause | Solution |
|---|---|---|
| `StudioAccessToApisNotAllowed` ou « You must publish this place » | Accès API désactivé ou jeu non publié | Publie le jeu et active **Enable Studio Access to API Services**. Le jeu fonctionne quand même, sans sauvegarde. |
| Bandeau rouge « Sauvegarde indisponible » | Le chargement du DataStore a échoué | Même solution ; la progression n'est volontairement **pas** sauvegardée pour ne pas écraser tes vraies données. |
| `Infinite yield possible on 'ReplicatedStorage:WaitForChild("Remotes")'` | Le Script `Main` ne tourne pas | Vérifie que `Main` est un **Script** (pas un LocalScript) dans **ServerScriptService**, et regarde la première erreur dans la Sortie. |
| `Infinite yield possible on ... WaitForChild("Client")` ou `("Components")` | Dossier mal nommé ou mal placé | Respecte exactement l'arborescence du README (casse comprise). |
| `X is not a valid member of Folder "Services"` | Un ModuleScript manque ou est mal nommé | Compare avec la liste de `docs/INSTALLATION.md`. |
| `Requested module experienced an error while loading` | Erreur dans un ModuleScript (souvent un copier-coller incomplet) | Clique sur l'erreur dans la Sortie pour voir la ligne ; recolle le fichier **en entier**. |
| Rien ne s'affiche à l'écran | `ClientMain` n'est pas un **LocalScript** ou n'est pas dans **StarterPlayerScripts** | Déplace-le au bon endroit. |
| Pas de son | IDs privés ou supprimés, ou son coupé dans les paramètres | Remplace les IDs dans `Config.Sounds` par des sons de la Toolbox (onglet Audio). |
| `Failed to load sound rbxassetid://...` | Son non autorisé pour ton jeu | Utilise des sons publics de Roblox ou tes propres sons importés. |
| Le classement reste vide | Place non publiée, ou pas encore de score envoyé (1 fois/minute) | Attends 1 minute dans un jeu publié. |
| Les clics « disparaissent » quand je spamme | Normal : au-delà de 20 clics/s, le serveur ignore les clics (anti-autoclicker) | Change `Config.Game.MaxClicksPerSecond` si besoin. |
| `DataStore request was added to queue` | Trop de requêtes DataStore (tests très rapides) | Sans gravité ; espace tes tests ou augmente `AutoSaveInterval`. |

> 💡 Pour repartir de zéro pendant les tests, change `Config.DataStore.Name` (ex. `"DopamineClickerData_v2"`).
