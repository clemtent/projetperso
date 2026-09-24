# 🧠 Dopamine Clicker

Un jeu Roblox de type **clicker**, inspiré du *concept* de « Stimulation Clicker » (neal.fun) : 
l'écran commence **tout simple** (un bouton gris « Clique-moi », un compteur, une rangée de cartes)… et **chaque amélioration achetée ajoute quelque chose à l'écran** : logos DVD qui rebondissent, fil d'actu, jeu de course, presse hydraulique, chambre lofi, live ASMR, bourse, machine à sous, papier bulle, orage, notifications, mails, pluie d'emojis, mode néon, boule disco… jusqu'à la **surcharge totale**.

Quand tu n'en peux plus : **🌊 Aller à l'océan**. Une cinématique calme, puis tout ce qui n'est pas permanent repart à zéro, avec un **multiplicateur de gains permanent** (rebirth / « détox »).

> Tout le code est en **Luau**, commenté en français, modulaire et **validé côté serveur** (anti-triche).
> Tout est dessiné en code (Frames, TextLabels, emojis, dégradés) : aucun asset externe ni marque déposée.
> Fonctionne sur PC, mobile et tablette.

---

## 🚀 Démarrage rapide

1. Télécharge le fichier de place **`build/DopamineClicker.rbxlx`** :
   - depuis le dépôt : [`build/DopamineClicker.rbxlx`](build/DopamineClicker.rbxlx) ;
   - ou en lien direct : `https://github.com/clemtent/projetperso/raw/<branche>/build/DopamineClicker.rbxlx`
     (branche principale : <https://github.com/clemtent/projetperso/raw/main/build/DopamineClicker.rbxlx>).
     Si la v2 n'est pas encore fusionnée dans `main`, remplace `main` par le nom de la branche de travail.
2. Ouvre-le dans **Roblox Studio** (double-clic ou **Fichier > Ouvrir depuis un fichier**) : tous les scripts sont déjà en place.
3. **Fichier > Publier sur Roblox** (nécessaire pour la sauvegarde et le classement).
4. **Accueil > Paramètres du jeu > Sécurité** : active **« Enable Studio Access to API Services »**.
5. Clique sur **Play** ▶️. Dans Studio, tape `/help` dans le chat pour voir les commandes de test.

Les autres méthodes (Rojo, copie manuelle) sont décrites dans [`docs/INSTALLATION.md`](docs/INSTALLATION.md).

---

## 🆕 Nouveautés v4

- **Visuels refaits** : personnage lofi dessiné (casque qui pulse, notes de musique), nouveaux logos DVD, moulin, live ASMR avec streameuse dessinée, presse qui évolue à chaque niveau (bois → acier → industrielle → or → diamant néon), machine à sous de luxe, bourse pro, vrais nuages d'orage, mails (74 différents), flash info complet (150+ titres), thèmes redessinés, Temps d'écran.
- **Musique lofi** : 4 musiques en boucle (déjà configurées). **Son de clic au choix** (5 claviers) dans ⚙️. Son de bulle et **beurre croustillant** 🧈 (*CROUNCH*) dans le live.
- **Live** : le bouton « Suivre » débloque des **dons** à cliquer ; chat bien plus vivant (badges, raids, réactions).
- **Dopamine hors-ligne** 😴 : tu gagnes une partie de ta production pendant ton absence, améliorable avec « Mode veille ». Fenêtre « Bon retour ! ».
- **Classement dès le début** : onglets 🏠 Serveur (en direct) et 🌍 Monde.
- **Succès = badges** : médailles dans le jeu + vrais **badges Roblox** (colle les IDs dans `Config.AchievementBadges`).
- **Boutiques redessinées** (objets et Robux). Sauvegarde toutes les 60 s + à la sortie.
- **Panneau 🛠️ Test** (Studio uniquement) : boutons pour tout tester (+Dopamine, tout débloquer, Rush, passes, boost, thème, hors-ligne...). Dans le chat : `/give`, `/unlockall`, `/aide`...

## 🆕 Nouveautés v3

- **🎵 Vraie musique lofi** : lecteur avec playlist, fondu enchaîné, bouton ⏭ et visualiseur dans la chambre lofi, volumes réglables dans ⚙️. **Ajoute tes musiques** dans `Config.Music.Playlist` : Studio > Boîte à outils > Audio > cherche « lofi », filtre par créateur **Roblox** (musiques sous licence utilisables partout), clic droit > *Copier l'ID de l'élément*, puis `Id = "rbxassetid://ID"`.
- **🎨 Thèmes / fonds animés** : Classique, Kawaii 🌸, Matcha 🍵, Coucher de soleil 🌅, Océan 🐠, Nuit lofi 🌙 (Dopamine) + Bonbon 🍭 et Synthwave 🌆 (Premium / VIP). Chaque thème peut aussi avoir son Game Pass.
- **💎 Boutique Robux** : Dopamine x10, x2, Auto-clic, VIP, packs de Dopamine, boosts x2/x5, Rush pour tout le serveur. Tu colles juste tes IDs : voir [`docs/MONETISATION.md`](docs/MONETISATION.md).
- **Finition pro** : écran de chargement, ombres douces, transitions des fenêtres, indicateurs VIP / boost / auto-clic, chances des coffres affichées.
- Commandes de test Studio en plus : `/pass X10`, `/boost 5 60`, `/theme Kawaii`.

---

## 🗂️ Arborescence dans l'Explorer de Roblox Studio

```
📁 ReplicatedStorage
│   📁 Shared                          (code partagé serveur + client)
│   │   📜 Config                      ModuleScript  ← TOUTE la config (améliorations, casino, sons…)
│   │   📜 Formulas                    ModuleScript  ← calculs : coûts, gains, features, casino, combo
│   │   📜 Net                         ModuleScript  ← liste des Remotes, les crée (serveur) / les récupère (client)
│   │   📜 DVDMath                     ModuleScript  ← trajectoire déterministe des logos DVD
│   │   📜 NumberFormatter             ModuleScript  ← 1K, 1M, 1B… / 1 234 / 4m 12s / x2
│   │   📜 Signal                      ModuleScript  ← petits événements (signaux)
│   📁 Client                          (interface, côté joueur uniquement)
│   │   📜 Theme                       ModuleScript  ← couleurs claires / sombres, polices
│   │   📜 UIUtil                      ModuleScript  ← création d'UI, animations, pastilles, badges
│   │   📜 Interface                   ModuleScript  ← ScreenGui + toile 1280×720 (UIScale) + calques
│   │   📜 ClientState                 ModuleScript  ← dernier état reçu, prédiction des clics, signaux
│   │   📜 SoundManager                ModuleScript  ← sons et musique
│   │   📜 Effects                     ModuleScript  ← « +X », particules, confettis, flash
│   │   📜 Slots                       ModuleScript  ← emplacements nommés de l'écran (L1, R1, C3…)
│   │   📜 StimulusManager             ModuleScript  ← lance / arrête les stimuli selon les Features
│   │   📁 Components
│   │   │   📜 Background              ModuleScript  ← fond blanc → gris clair (noir en mode néon)
│   │   │   📜 CenterColumn            ModuleScript  ← chapeau, bouton, compteur, pastilles, combo
│   │   │   📜 UpgradeBar              ModuleScript  ← rangée de cartes d'amélioration + infobulle
│   │   │   📜 PanelManager            ModuleScript  ← fenêtres pop-up (une à la fois)
│   │   │   📜 Notifications           ModuleScript  ← bandeaux (toasts) en bas de l'écran
│   │   │   📁 Panels
│   │   │       📜 Achievements        ModuleScript  ← 🏆 Succès
│   │   │       📜 Daily               ModuleScript  ← 🎁 Cadeau quotidien
│   │   │       📜 ItemShop            ModuleScript  ← 🛒 Boutique d'objets (chapeaux, skins)
│   │   │       📜 Leaderboard         ModuleScript  ← 🥇 Classement
│   │   │       📜 Quests              ModuleScript  ← 📜 Quêtes
│   │   │       📜 ScreenTime          ModuleScript  ← ⏱️ Temps d'écran
│   │   │       📜 Settings            ModuleScript  ← ⚙️ Paramètres
│   │   📁 Stimuli                     (un module par Feature, lancé par StimulusManager)
│   │       📜 BubbleWrap              ModuleScript  ← papier bulle (slot L2)
│   │       📜 Casino                  ModuleScript  ← machine à sous (slot R2)
│   │       📜 CursorTrail             ModuleScript  ← étincelles derrière la souris (Overlay)
│   │       📜 DVD                     ModuleScript  ← logos DVD rebondissants (Overlay)
│   │       📜 Disco                   ModuleScript  ← boule disco + faisceaux (Overlay)
│   │       📜 Email                   ModuleScript  ← mails qui arrivent en volant (Overlay)
│   │       📜 EmojiRain               ModuleScript  ← pluie d'emojis (Overlay)
│   │       📜 GoldenStar              ModuleScript  ← étoiles dorées à attraper (Overlay)
│   │       📜 LiveStream              ModuleScript  ← live ASMR + chat (slot L1)
│   │       📜 Lofi                    ModuleScript  ← chambre lofi (slot R3)
│   │       📜 LootBox                 ModuleScript  ← coffre mystère (slot CR)
│   │       📜 Megaphone               ModuleScript  ← mots criés à l'écran (Overlay)
│   │       📜 NeonMode                ModuleScript  ← fond néon animé + mode sombre (Background)
│   │       📜 NewsTicker              ModuleScript  ← bandeau rouge d'infos absurdes (slot Ticker)
│   │       📜 Ocean                   ModuleScript  ← cinématique « Aller à l'océan » (calque Cinematic)
│   │       📜 PhoneNotifs             ModuleScript  ← notifications de téléphone (Overlay)
│   │       📜 Pinwheel                ModuleScript  ← moulin à vent (slot CL)
│   │       📜 Press                   ModuleScript  ← presse hydraulique (slot C3)
│   │       📜 Runner                  ModuleScript  ← jeu de course infini (slot L3)
│   │       📜 Stocks                  ModuleScript  ← bourse DOPA (slot R1)
│   │       📜 Weather                 ModuleScript  ← orage + éclairs à cliquer (Overlay)
│   📁 Remotes                         ⚙️ créé AUTOMATIQUEMENT par le serveur (Net.Setup)
│
📁 ServerScriptService
│   📄 Main                            Script        ← point d'entrée serveur
│   📁 Services
│       📜 DataService                 ModuleScript  ← sauvegarde DataStore (retry, auto-save)
│       📜 GameService                 ModuleScript  ← clics, achats, gains passifs, détox, leaderstats
│       📜 EventService                ModuleScript  ← Dopamine Rush + objets à cliquer (étoile, éclair, notif, mail)
│       📜 DVDService                  ModuleScript  ← logos DVD : trajectoires, rebonds, clics, coins
│       📜 InteractService             ModuleScript  ← papier bulle, moulin, fil d'actu, presse
│       📜 StockService                ModuleScript  ← cours de bourse commun + achats / ventes
│       📜 CasinoService               ModuleScript  ← machine à sous (Dopamine du jeu uniquement)
│       📜 LootService                 ModuleScript  ← coffres mystère (recharge + ouverture)
│       📜 CosmeticService             ModuleScript  ← boutique d'objets (acheter / équiper)
│       📜 QuestService                ModuleScript  ← quêtes
│       📜 AchievementService          ModuleScript  ← succès
│       📜 DailyRewardService          ModuleScript  ← cadeau quotidien
│       📜 LeaderboardService          ModuleScript  ← classement global (OrderedDataStore)
│       📜 RateLimiter                 ModuleScript  ← anti-spam
│       📜 DebugService                ModuleScript  ← commandes de test (Studio seulement)
│
📁 StarterPlayer
│   📁 StarterPlayerScripts
│       📄 ClientMain                  LocalScript   ← point d'entrée client
│
📁 Workspace                           (fichier .rbxlx uniquement : Baseplate + SpawnLocation)
```

Dans le dépôt (`src/`), chaque fichier correspond à un objet :
`*.server.luau` = **Script**, `*.client.luau` = **LocalScript**, autre `*.luau` = **ModuleScript**, dossier = **Folder**.

---

## 🏗️ Architecture

```
          CLIENT (ClientMain + modules)                               SERVEUR (Main + services)
┌─────────────────────────────────────────────┐            ┌─────────────────────────────────────────────┐
│ Interface 100 % en code (toile 1280×720)    │   Click    │ GameService : limite de clics/s, combo,      │
│ Prédit le « +X » et le compteur             │ ─────────▶ │ gain = valeur de clic, ajoute la Dopamine    │
│                                             │ BuyUpgrade │ vérifie prix + argent, applique l'achat,     │
│ StimulusManager : lance un module Stimuli   │ ─────────▶ │ Notify "Unlock" / "Detox"                    │
│ par Feature possédée                        │            │                                             │
│                                             │ StateUpdate│ Tick passif : Dopamine/s, rebonds DVD,      │
│ ClientState : se recale sur le serveur      │ ◀───────── │ coffres, temps d'écran                       │
│ Ne décide JAMAIS d'un gain                  │  Notify…   │ DataService : sauvegarde                     │
└─────────────────────────────────────────────┘            └─────────────────────────────────────────────┘
```

- **Autorité du serveur** : le client n'envoie que des *demandes* (clic, achat, clic sur une étoile, bulle éclatée, mise au casino…). Le serveur vérifie tout : types, Feature possédée, prix, temps de recharge, limites (seau de jetons), objets en attente. Aucun `InvokeClient` n'est utilisé.
- **Prédiction côté client** : le « +X » et le compteur montent tout de suite. Chaque clic reçoit un numéro de séquence ; l'état serveur renvoie `ClickSeq` (clics reçus) et `ClientState` retire les clics déjà comptés, puis se recale sur la valeur du serveur.
- **DVD déterministe** : le serveur choisit la trajectoire de chaque logo (`X0, Y0, VX, VY, T0, W, H`) et l'envoie par `DVDSetup`. Le client calcule la position avec `DVDMath` et `workspace:GetServerTimeNow()`. Le serveur **compte lui-même les rebonds** (gains passifs) et **recalcule** si un coin a vraiment été touché avant de donner le jackpot. Les tests vérifient que le comptage client (60 images/s) et serveur (tick 0,25 s) sont identiques.
- **StimulusManager + contrat `ctx`** : pour chaque Feature possédée (`Formulas.GetFeatures`), s'il existe un module `Client > Stimuli > <Feature>`, le manager crée un cadre selon `Module.Slot`, construit un `ctx` et appelle `Module.Start(ctx)` dans un `pcall` (une erreur ne casse jamais le reste du jeu). Quand la Feature disparaît (après l'océan), il coupe toutes les connexions suivies, appelle `Module.Stop(ctx)` si présent et détruit le cadre. Il route aussi les `Notify { Type = "Bonus" }` vers `ctx.OnBonus(source, …)` et joue `Ocean.Play(ctx)` sur `Notify { Type = "Detox" }`.
  Le `ctx` fournit : `Feature, Container, Overlay, State, Config, Formulas, Format, Net, Theme, UIUtil, Effects, Sound, DVDMath, Notify, FloatText, GetLevel, HasFeature, ClaimSpawn, Interact, OnSpawn, OnBonus, Connect, OnRender, IsAlive, SetDarkMode` (+ `Slot, Interface, Random, EffectsEnabled`).
- **Slots** : emplacements nommés sur la toile 1280×720 (`Client > Slots`). La colonne centrale (x ∈ centre ± 300, y ∈ 30–425) reste toujours libre et lisible.

  | Slot | Ancrage | Position | Taille | Stimulus |
  |---|---|---|---|---|
  | `Ticker` | toute la largeur | y = 0 | × 30 | NewsTicker |
  | `L1` / `R1` | gauche / droite | 16, 40 | 288×190 | LiveStream / Stocks |
  | `L2` / `R2` | gauche / droite | 16, 240 | 288×180 | BubbleWrap / Casino |
  | `CL` / `CR` | centre −250 / +250 | y = 40 | 170×170 | Pinwheel / LootBox |
  | `L3` / `C3` / `R3` | gauche / centre / droite | y = 436 | 384×268 | Runner / Press / Lofi |
  | `Overlay` | plein écran (calque Overlay) | — | — | DVD, Megaphone, Weather, PhoneNotifs, Email, EmojiRain, GoldenStar, CursorTrail, Disco |
  | `Background` | plein écran (sous tout) | — | — | NeonMode |

  Les slots de la moitié basse sont accrochés en bas de l'écran : sur tablette (plus haut que 16:9), l'espace libre se retrouve au milieu.
- **Calques de l'interface** (du bas vers le haut) : `Background, Slots, Main, Overlay, Panels, Toasts, Effects, Cinematic`.
- **Services injectés** : `Main` appelle `Net.Setup()`, charge les services dans un ordre fixe et donne à chacun la table des autres (`Init(services)`), ce qui évite les `require` circulaires.

---

## 📈 Les 35 améliorations (ordre de progression)

La barre affiche les améliorations déjà achetées (non maximisées) + les **5 prochaines** pas encore achetées (`Config.UpgradeBar.RevealAhead`). « Niv. max » vide = illimité. Les améliorations marquées **♾️ Permanente** sont conservées après l'océan.

| # | Icône | Nom | Prix (niv. 1) | Niv. max | Ce que ça ajoute |
|---|---|---|---|---|---|
| 1 | 👆 | Doigt musclé | 10 | 15 | +1 Dopamine par clic et par niveau |
| 2 | 📀 | Logo DVD | 110 | 10 | +1 logo DVD rebondissant par niveau ; chaque rebond rapporte (2 de base) ; clic = bonus, coin = jackpot |
| 3 | 📰 | Fil d'actu | 450 | 1 | Bandeau rouge d'infos absurdes en haut ; +8 /s ; cliquer un titre = petit bonus |
| 4 | 📅 | Calendrier | 1 200 | 1 | ♾️ Pastille « 🎁 Cadeau » : récompense quotidienne avec série |
| 5 | 🔊 | Bruit du DVD | 3 500 | 1 | Son à chaque rebond ; gains par rebond x3 |
| 6 | 🏃 | Coureur infini | 5 500 | 1 | Jeu de course en boucle en bas à gauche ; +25 /s |
| 7 | 📢 | Mégaphone | 6 000 | 1 | Gros mots criés à l'écran toutes les 4–9 s ; clics x2 |
| 8 | 🎧 | Lofi Beats | 12 000 | 1 | Chambre lofi en bas à droite ; autorise la musique ; +40 /s |
| 9 | 🗜️ | Presse hydraulique | 18 000 | 10 | Presse qui écrase des objets en bas au centre ; +20 /s par niveau (plus rapide à chaque niveau) |
| 10 | 🏆 | Succès | 25 000 | 1 | ♾️ Pastille « 🏆 Succès » (les succès sont comptés dès le début) |
| 11 | 🌀 | Moulin à vent | 28 000 | 1 | Moulin à souffler (clic = accélération + petit bonus) ; +75 /s |
| 12 | 🔘 | Papier bulle | 30 000 | 1 | Feuille de 8×5 bulles à éclater ; chaque bulle = 50 % d'un clic |
| 13 | ⛈️ | Orage | 33 000 | 1 | Nuages + pluie ; des éclairs à cliquer vite ; +100 /s |
| 14 | 🧢 | Boutique d'objets | 55 000 | 1 | ♾️ Pastille « 🛒 Boutique » : chapeaux et skins pour le bouton |
| 15 | 📈 | Bourse | 60 000 | 1 | Carte bourse DOPA (cours commun au serveur) : acheter / vendre |
| 16 | ⬆️ | Flèche verte | 68 000 | 1 | Tous les gains x2 |
| 17 | 🥪 | Live ASMR | 100 000 | 1 | Faux live « mukbang » en haut à gauche ; +120 /s |
| 18 | 👥 | Abonnés | 150 000 | 15 | Plus de spectateurs sur le live ; +50 /s par niveau |
| 19 | 🔔 | Notifications | 200 000 | 1 | Notifications de téléphone à cliquer ; +150 /s |
| 20 | ⚡ | Combo | 260 000 | 1 | Jauge de combo sous le compteur : cliquer vite = clics jusqu'à x3 |
| 21 | 📧 | Boîte mail | 320 000 | 1 | Mails qui arrivent en volant ; les ouvrir = bonus |
| 22 | 📜 | Quêtes | 520 000 | 1 | ♾️ Pastille « 📜 Quêtes » (3 quêtes actives) |
| 23 | 🎰 | Machine à sous | 600 000 | 1 | Machine à sous (mise = % de ta Dopamine du jeu) |
| 24 | ⚙️ | Presse turbo | 650 000 | 1 | Bouton START sur la presse : écrase toi-même (bonus, recharge 3 s) |
| 25 | 💬 | Chat en direct | 800 000 | 1 | Colonne de chat sur le live ; clics x3 |
| 26 | 📱 | Temps d'écran | 1M | 1 | ♾️ Pastille « ⏱️ Temps d'écran » : aujourd'hui, session, total, 7 jours |
| 27 | 📦 | Coffre mystère | 1,2M | 1 | Coffre qui se remplit avec le temps de jeu ; l'ouvrir = récompense aléatoire |
| 28 | 😂 | Pluie d'emojis | 1,5M | 1 | Pluie d'emojis légère ; +1 000 /s |
| 29 | ✨ | Icônes HD | 1,9M | 1 | Cartes d'amélioration brillantes et colorées ; gains x1,5 |
| 30 | 🌟 | Étoile dorée | 2,8M | 1 | Étoiles dorées à attraper (gros bonus) |
| 31 | 🥇 | Classement | 3,8M | 1 | ♾️ Pastille « 🥇 Classement » (top 10 mondial) |
| 32 | 🌈 | Mode néon | 4,5M | 1 | Fond néon animé, interface en mode sombre ; gains x2 |
| 33 | 💫 | Traînée magique | 7,5M | 1 | Étincelles qui suivent la souris / le doigt ; clics x2 |
| 34 | 💃 | Boule disco | 12M | 1 | Boule disco + faisceaux de lumière ; gains x2 |
| 35 | 🌊 | Aller à l'océan | 45M (x2,5 par visite) | ∞ | Détox / rebirth : cinématique, remise à zéro, +50 % de gains permanents par visite |

Prix d'un niveau = `Cost × CostGrowth^niveau` (Doigt et DVD : x2,2 ; Presse : x1,75 ; Abonnés : x1,6).

---

## 🎮 Systèmes

| Système | Détails |
|---|---|
| Bouton « Clique-moi » | Squish au clic, « +X » flottant, particules (si « Effets » activé), chapeau et skin cosmétiques |
| Barre d'améliorations | Cartes carrées (pastille rouge = niveau), fanées si trop chères ; PC : survol = infobulle, clic = achat ; tactile : 1er appui = infobulle + « Acheter », 2e appui = achat ; l'océan demande toujours une confirmation |
| Détox (océan) | Dopamine = 0, seules les améliorations permanentes restent, bourse vidée, logos DVD et objets en attente supprimés ; succès, stats, cosmétiques, cadeau, réglages, coffres, temps d'écran et quêtes conservés ; multiplicateur `1 + 0,5 × rebirths` |
| Combo | Jauge 0–100 (+5 par clic, −15 /s), jusqu'à **x3** ; calculée par le serveur |
| Logos DVD | Jusqu'à 10 logos ; gains par rebond (comptés par le serveur), clic = bonus (recharge 6 s), coin = jackpot pour toi + annonce aux autres |
| Objets à cliquer | Étoile dorée, éclair, notification, mail : décidés par le serveur (3 max en attente par type), récompense = X secondes de production |
| Interactions | Papier bulle (12 bulles/s max), moulin (recharge 2 s), titres du fil d'actu (8 s), presse START (3 s) |
| Bourse | Cours DOPA commun au serveur (marche aléatoire + retour vers 100, borné 5–2 000), mise à jour chaque seconde ; boutons Acheter 10 / 50 / 100 % et Vendre (tout) |
| Machine à sous | 6 symboles pondérés, tirage serveur, taux de retour ~90–95 % (vérifié par les tests) ; **Dopamine du jeu uniquement** ; désactivable (`Config.Casino.Enabled`) |
| Coffre mystère | 1 coffre toutes les 120 s de jeu (max 5) ; rangs Commun 60 % / Rare 25 % / Épique 12 % / Légendaire 3 % |
| Boutique d'objets | 8 chapeaux + 5 skins, payés en Dopamine, gardés pour toujours, **+2 %** de gains chacun |
| Succès | 35 succès avec récompense + **+2 %** de gains permanents chacun |
| Quêtes | 3 actives, remplacées automatiquement ; types proposés selon les Features possédées |
| Cadeau quotidien | Jour UTC côté serveur, série jusqu'à +7 |
| Temps d'écran | Session, aujourd'hui, total, graphique 7 jours et commentaire (« C'est raisonnable. » → « Tu as un problème. ») |
| Dopamine Rush | x2 pour tout le serveur pendant 30 s, toutes les 150–300 s (5 fois plus souvent dans Studio) |
| Classement | Top 10 mondial (OrderedDataStore, mis à jour chaque minute) + leaderstats |
| Paramètres | Effets sonores, musique (avec Lofi Beats), particules ; sauvegardés |
| Sauvegarde | DataStore `DopamineClickerData_v2`, retry, auto-save toutes les 120 s, `BindToClose` ; jamais d'écrasement si le chargement a échoué |

Toutes les valeurs se modifient dans **`ReplicatedStorage > Shared > Config`**.

---

## 📚 Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) — 3 méthodes d'installation, liste complète des fichiers, Remotes, sons, ajouter un stimulus.
- [`docs/TESTS.md`](docs/TESTS.md) — checklist de test v2, commandes Studio, tests automatiques, erreurs courantes.
- [`docs/MONETISATION.md`](docs/MONETISATION.md) — Game Passes, boosts, règles Roblox (casino, coffres), promotion.
