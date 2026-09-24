# ✅ Tester Dopamine Clicker

Deux niveaux de test :

1. **Tests automatiques** (hors Roblox) : `python3 tests/run_tests.py` vérifie la config, les formules, l'équilibrage de la progression, le casino et les maths du DVD.
2. **Checklist dans Roblox Studio** (ci-dessous), avec les commandes de test `/give`, `/unlockall`, etc.

---

## 🤖 Tests automatiques : `tests/run_tests.py`

Le script assemble les modules `Shared` (`Config`, `NumberFormatter`, `Formulas`, `DVDMath`) en un seul script Luau, avec de faux objets Roblox (`Vector2`, `Color3`, `require`), et l'exécute avec le **Luau CLI**.

```bash
# Depuis la racine du dépôt
python3 tests/run_tests.py                         # Luau attendu dans /tmp/luau/luau
python3 tests/run_tests.py --luau /chemin/vers/luau  # autre emplacement
```

- Il faut **Python 3** et le binaire **`luau`** (https://github.com/luau-lang/luau/releases).
- Chaque test affiche `PASS` ou `FAIL` (avec le détail), puis `RÉSULTAT GLOBAL : PASS` / `FAIL`. Code de sortie `1` en cas d'échec.

| Test | Ce qui est vérifié |
|---|---|
| `NumberFormatter.Format` | `1K`, `1.23K`, `1M`… jusqu'à 10^65, négatifs, NaN, infini, notation scientifique |
| `NumberFormatter.WithSpaces / Time / Multiplier` | `1 234 567`, `4m 12s`, `x1.5` |
| `Config : cohérence des améliorations` | Id uniques, `Order`, `Effect` connu, `Value` présente, Features uniques, océan en dernier, Features des spawners / interactions / quêtes / bourse / casino / coffre existantes, cosmétiques valides |
| `Formulas.ComputeStats` | Gains de clic, par seconde, par rebond, multiplicateurs (boost, rebirth, succès, cosmétiques, rush), Features, pas de NaN / infini même avec tout au max, `ScaledReward` |
| `Formulas.GetUpgradeCost` | Coûts croissants, prix de l'océan (`BaseCost × CostGrowth^rebirths`), `IsMaxed` |
| `Formulas.GetVisibleUpgrades : progression` | Simulation d'une partie complète : chaque amélioration devient visible, jamais plus de 5 nouvelles à la fois, à la fin il ne reste que l'océan ; après la détox, seules les Features permanentes restent |
| `Formulas.DescribeUpgrade` | Aucun `%s` ni `nan` dans les descriptions ; l'océan affiche le prochain multiplicateur |
| `Formulas casino` | Taux de retour (RTP) entre **0,90 et 0,95**, paires / triples, fractions de mise valides |
| `Formulas combo` | x1 à x3, 10 clics/s remplissent la jauge |
| `DVDMath` (2 tests) | 200 trajectoires aléatoires : le logo reste dans l'écran, le nombre de rebonds compté par le client (60 images/s) = celui du serveur (tick 0,25 s), taux théorique respecté ; coins et directions |
| `Config : toutes les clés utilisées dans src/ existent` | Chaque chemin `Config.X.Y` écrit dans `src/` existe vraiment dans `Config.luau` (attrape les fautes de frappe) |

Lance-le après **chaque** modification de `Config` ou de `Formulas` (prix, valeurs, casino…).

---

## 🛠️ Avant de tester dans Studio

- [ ] Le jeu est **publié** (Fichier > Publier sur Roblox).
- [ ] **Enable Studio Access to API Services** est activé (Paramètres du jeu > Sécurité).
- [ ] La fenêtre **Sortie** est ouverte (Affichage > Sortie).
- [ ] Au lancement, la Sortie affiche `[Dopamine Clicker] Serveur prêt (1 joueur(s))`.

## ⌨️ Commandes de test (Studio uniquement)

Implémentées dans `ServerScriptService > Services > DebugService`. Elles ne sont branchées **que si `RunService:IsStudio()`** : elles n'existent pas dans le jeu publié. Tape-les dans le **chat** pendant un test **Play**. Le message est mis en minuscules ; format : `/commande argument`. Chaque commande répond par un bandeau « 🛠️ … ».

| Commande | Effet exact |
|---|---|
| `/give` | Donne **1 000 000** de Dopamine |
| `/give <nombre>` | Donne ce montant (`/give 5e9`, `/give 250000`). Montant ≤ 0, NaN ou infini → « Montant invalide » |
| `/rush` | Lance immédiatement un Dopamine Rush (pour tout le serveur) |
| `/daily` | Rend le cadeau quotidien à nouveau disponible (il faut posséder « Calendrier » pour voir la pastille) |
| `/save` | Force une sauvegarde : « 💾 Sauvegardé ! » ou « 💾 Sauvegarde impossible (voir la sortie) » |
| `/corner` | Le **1er** logo DVD touchera un coin dans ~2 s (test du jackpot). Sans logo : « Il faut au moins un logo DVD » |
| `/unlockall` | Met **toutes** les améliorations à leur niveau max (niveau 1 pour les illimitées), **sauf** « Aller à l'océan » ; régénère les quêtes |
| `/spawn golden` | Fait apparaître une étoile dorée |
| `/spawn lightning` | Fait apparaître un éclair |
| `/spawn notif` | Fait apparaître une notification de téléphone |
| `/spawn email` | Fait apparaître un mail |
| `/golden` | Raccourci de `/spawn golden` |
| `/detox` | Va à l'océan **gratuitement** (même effet qu'un achat : remise à zéro, rebirth +1, cinématique) |
| `/chest` | Ajoute 1 coffre mystère (le stock reste plafonné à `Config.LootBox.MaxStored` = 5) |
| `/chest <n>` | Ajoute `n` coffres (même plafond) |
| `/reset` | Remet **toutes** les données à zéro (sauf les paramètres Son / Musique / Effets), vide combo, objets en attente et logos DVD, puis resynchronise |
| `/help` | Affiche la liste des commandes |

Remarques :
- `/spawn` refuse s'il y a déjà 3 objets du même type en attente (« Trop d'objets … à l'écran »). Le serveur crée l'objet même si tu ne possèdes pas la Feature, mais il ne s'affiche que si le stimulus correspondant est lancé (Étoile dorée, Orage, Notifications, Boîte mail) : fais `/unlockall` d'abord.
- Dans Studio, le Dopamine Rush et les objets à cliquer arrivent **5 fois plus souvent** (`Config.Events.StudioSpeedup`).
- Scénario rapide : `/unlockall` → `/give 1e9` → tout est à l'écran.

---

## 📋 Checklist v2

### Écran de départ
- [ ] Fond blanc → gris clair, bouton gris « Clique-moi », « 0 Dopamine », « 0 Dopamine par seconde », pastille ⚙️ seule, et **5** cartes d'amélioration (Doigt musclé en premier).
- [ ] Cliquer : le bouton s'écrase, un « +1 » s'envole, le compteur monte **tout de suite**.
- [ ] Les cartes trop chères sont **fanées** ; survol (PC) = infobulle (nom, description, coût en rouge si trop cher).
- [ ] Spam de clics (> 20/s) : les clics en trop sont ignorés par le serveur, le compteur se recale sans à-coup.

### Progression
- [ ] Acheter une carte : son, petite gerbe, la Dopamine baisse, la pastille rouge affiche le niveau (améliorations à plusieurs niveaux), le prix augmente.
- [ ] Carte trop chère cliquée : elle tremble + son d'erreur.
- [ ] Chaque achat d'amélioration à Feature affiche le bandeau « ✨ Nouveau : <icône> <nom> ! » et le nouvel élément **apparaît en « pop »** à sa place.
- [ ] Les cartes suivantes se dévoilent au fur et à mesure (toujours 5 pas encore achetées visibles) ; une carte au max disparaît.
- [ ] Les pastilles apparaissent avec leur amélioration : ⏱️ Temps d'écran, 🛒 Boutique, 🏆 Succès, 📜 Quêtes, 🥇 Classement, 🎁 Cadeau.
- [ ] Mode **« Icônes HD »** : les cartes deviennent colorées et brillantes.

### Chaque stimulus (utilise `/give 1e9` ou `/unlockall`)
- [ ] **📀 Logo DVD** : un logo par niveau, rebonds fluides, nouvelle couleur à chaque rebond, « +X » à chaque rebond ; clic = bonus puis logo transparent pendant la recharge (6 s) ; `/corner` → jackpot (message, confettis) et bandeau chez les autres joueurs. Redimensionner la fenêtre : les logos restent dans l'écran.
- [ ] **🔊 Bruit du DVD** : son à chaque rebond, « +X » par rebond x3.
- [ ] **📰 Fil d'actu** : bandeau rouge en haut, titres qui défilent, ralentit au survol ; clic sur un titre = « +X » (max 1 fois / 8 s).
- [ ] **🏃 Coureur infini** (bas gauche) : 3 voies, trains, barrières, pièces, score.
- [ ] **📢 Mégaphone** : un gros mot « crié » toutes les 4–9 s, sans bloquer les clics.
- [ ] **🎧 Lofi Beats** (bas droite) : chambre animée ; la musique démarre si `Config.Sounds.Music.Id` est rempli et « Musique » activé.
- [ ] **🗜️ Presse hydraulique** (bas centre) : écrase en boucle, plus vite à chaque niveau.
- [ ] **⚙️ Presse turbo** : bouton START rouge → écrasement manuel + « +X », recharge 3 s visible.
- [ ] **🌀 Moulin à vent** : tourne ; clic = accélération + « +X » (max 1 fois / 2 s).
- [ ] **🔘 Papier bulle** : chaque bulle éclate (son, « +X ») ; feuille neuve quand tout est éclaté ; au-delà de 12 bulles/s la bulle résiste.
- [ ] **⛈️ Orage** : nuages + pluie ; `/spawn lightning` → éclair cliquable ~2,5 s → « +X ».
- [ ] **📈 Bourse** : graphique qui bouge chaque seconde, Acheter 10 / 50 / 100 %, Vendre ; plus/moins-value correcte ; message si rien à vendre.
- [ ] **🥪 Live ASMR** (haut gauche) : « 🔴 EN DIRECT », spectateurs (augmentent avec **👥 Abonnés**), assiette mangée.
- [ ] **💬 Chat en direct** : colonne de chat sur le live.
- [ ] **🔔 Notifications** : `/spawn notif` → bannière en haut à gauche (3 max), clic = « +X », disparaît seule.
- [ ] **⚡ Combo** : jauge sous le compteur ; > 3 clics/s la font monter jusqu'à x3.
- [ ] **📧 Boîte mail** : `/spawn email` → enveloppe ; clic = fenêtre de mail + « +X » ; ignorée = compteur « non lus ».
- [ ] **🎰 Machine à sous** : voir « Casino » plus bas.
- [ ] **📦 Coffre mystère** : voir « Coffres » plus bas.
- [ ] **😂 Pluie d'emojis** : emojis semi-transparents, ne bloquent pas les clics.
- [ ] **🌟 Étoile dorée** : `/golden` → étoile ~6 s, clic = gros « +X ».
- [ ] **🌈 Mode néon** : fond animé sombre, interface en mode sombre (textes blancs, cartes sombres).
- [ ] **💫 Traînée magique** : étincelles derrière la souris / le doigt.
- [ ] **💃 Boule disco** : boule + faisceaux, les clics passent à travers.
- [ ] Avec **tout** débloqué : la colonne centrale (bouton, compteur, cartes) reste lisible et cliquable.

### Détox / océan
- [ ] La carte 🌊 « Aller à l'océan » demande **toujours** une confirmation (PC et tactile) et affiche le prochain multiplicateur.
- [ ] Achat (ou `/detox`) : cinématique plein écran (~6 s : vagues, « Respire... », « Tout est calme. », « Rebirth x1.5 »), clics bloqués pendant ce temps.
- [ ] Après : Dopamine = 0, tous les stimuli non permanents disparaissent, actions de bourse remises à 0, plus de logos DVD.
- [ ] Conservés : Calendrier, Succès, Boutique d'objets, Quêtes, Temps d'écran, Classement (pastilles toujours là), cosmétiques, coffres en stock, stats, succès.
- [ ] Les gains sont multipliés (x1,5 après 1 visite) ; le prix de la visite suivante est x2,5.
- [ ] Les autres joueurs voient « 🌊 <nom> est allé(e) à l'océan (x1) ».

### Cosmétiques (🛒 Boutique)
- [ ] La pastille affiche le nombre d'objets abordables non possédés.
- [ ] Acheter un chapeau : il apparaît **sur** le bouton ; acheter un skin : le bouton change de couleurs.
- [ ] Équiper / déséquiper fonctionne ; les objets restent après `/detox` et après relance.
- [ ] Chaque objet possédé ajoute +2 % aux gains.

### Bourse
- [ ] Le cours est **le même** pour deux joueurs (Test > Clients et serveurs > 2 joueurs).
- [ ] Achat 100 % puis vente : la Dopamine revient selon le prix du moment (gain ou perte).

### Casino
- [ ] Choisir une mise (1 / 5 / 10 / 25 % de ta Dopamine), JOUER : les rouleaux tournent puis s'arrêtent sur le résultat **du serveur**.
- [ ] Gain : confettis / flash + « +X » ; perte : petite secousse.
- [ ] Spam du bouton : refusé pendant la recharge (1,5 s).
- [ ] `Config.Casino.Enabled = false` : la machine affiche « 🚧 FERMÉ POUR TRAVAUX 🚧 », le bouton est désactivé et le serveur refuse les mises.

### Coffres
- [ ] La jauge « Prochain : X % » monte avec le temps de jeu (1 coffre / 120 s, max 5).
- [ ] `/chest 3` → pastille « 3 » ; clic → le coffre tremble, s'ouvre, rang (Commun / Rare / Épique / LÉGENDAIRE) + montant.
- [ ] Sans coffre en stock : rien ne se passe côté serveur.

### Temps d'écran
- [ ] Pastille ⏱️ → session, aujourd'hui, total, graphique des 7 derniers jours.
- [ ] Le commentaire change avec le temps du jour : « C'est raisonnable. » (< 10 min) → « Ça commence à faire beaucoup... » → « Il faudrait peut-être sortir... » (< 1 h) → « Tes yeux ne te remercient pas. » → « Tu as un problème. » (> 3 h).
- [ ] Le temps est conservé après relance.

### Autres systèmes
- [ ] **Succès** : après 100 clics, bandeau de succès (si le menu Succès est débloqué ; sinon compté en silence) ; badge sur la pastille.
- [ ] **Quêtes** : 3 quêtes, progression, récompense automatique, remplacement.
- [ ] **Cadeau quotidien** : s'ouvre tout seul s'il est disponible ; après récupération, compte à rebours ; `/daily` le rend disponible.
- [ ] **Rush** (`/rush`) : bannière avec compte à rebours, gains x2.
- [ ] **Classement** : se remplit dans un jeu publié (mise à jour toutes les 60 s).
- [ ] **Paramètres ⚙️** : Effets sonores, Musique, Particules ; conservés après relance.

### Sauvegarde
- [ ] Gagne, achète, **Stop**, puis **Play** : tout est conservé (améliorations, Dopamine, cosmétiques, temps d'écran…).
- [ ] `/save` affiche « 💾 Sauvegardé ! ».

### Mobile / tablette
- [ ] **Test > Appareil** : iPhone, iPad, Android, 4K : rien ne dépasse, tout reste lisible, orientation paysage.
- [ ] Tactile : 1er appui sur une carte = infobulle avec bouton « Acheter », 2e appui = achat.
- [ ] Papier bulle, moulin, START, étoiles, notifications, mails, coffre et casino fonctionnent au doigt.
- [ ] Traînée magique : les étincelles suivent le doigt.
- [ ] Tablette (4:3) : les stimuli du bas sont collés en bas, l'espace libre est au milieu.

---

# 🐞 Erreurs courantes

| Symptôme / message | Cause | Solution |
|---|---|---|
| `StudioAccessToApisNotAllowed` / `[DataService] Active 'Enable Studio Access to API Services'…` | Accès API désactivé ou jeu non publié | Publie le jeu et active **Enable Studio Access to API Services**. Le jeu fonctionne quand même, sans sauvegarde. |
| Bandeau « ⚠️ Sauvegarde indisponible : ta progression ne sera pas enregistrée. » | Le chargement DataStore a échoué | Même solution. La progression n'est volontairement **pas** sauvegardée pour ne pas écraser une vraie sauvegarde. |
| `Infinite yield possible on 'ReplicatedStorage:WaitForChild("Remotes")'` | Le Script `Main` ne tourne pas | `Main` doit être un **Script** dans **ServerScriptService** ; regarde la première erreur rouge de la Sortie. |
| `Infinite yield possible on … WaitForChild("Client")` / `("Components")` / `("Panels")` | Dossier mal nommé ou mal placé | Respecte l'arborescence du README (casse comprise). |
| `X is not a valid member of Folder "Services"` | Un service manque ou est mal nommé | Compare avec le tableau de `docs/INSTALLATION.md` (15 services). |
| `Requested module experienced an error while loading` | Erreur dans un ModuleScript (copier-coller incomplet) | Clique l'erreur pour voir la ligne ; recolle le fichier **en entier**. |
| Une amélioration achetée n'ajoute rien à l'écran | Module absent ou mal nommé dans `Client > Stimuli` (il est ignoré sans erreur) | Le nom doit être **exactement** la `Feature` (ex. `NewsTicker`, `PhoneNotifs`). |
| `[StimulusManager] Erreur dans Stimuli.X.Start : …` | Bug dans un stimulus | Le reste du jeu continue ; corrige la ligne indiquée. |
| `[StimulusManager] Stimuli.X : Slot invalide (…), Overlay utilisé` | `Module.Slot` inconnu | Utilise un nom de `Client > Slots` ou `Overlay` / `Background`. |
| Rien ne s'affiche à l'écran | `ClientMain` n'est pas un **LocalScript** dans **StarterPlayerScripts** | Déplace-le / recrée-le au bon endroit. |
| Les commandes `/give`… ne font rien | Jeu publié (commandes Studio seulement), faute de frappe, ou message pas envoyé | Teste dans Studio (**Play**) ; `/help` doit répondre par un bandeau 🛠️. |
| `/spawn …` n'affiche rien | Tu ne possèdes pas la Feature (le stimulus n'est pas lancé) | Fais `/unlockall` d'abord. |
| Pas de son | IDs invalides / privés, ou « Effets sonores » coupé | Remplace les IDs dans `Config.Sounds`. |
| Pas de musique | `Config.Sounds.Music.Id` est vide par défaut, ou Lofi Beats pas acheté | Mets un ID de musique et achète Lofi Beats. |
| `Failed to load sound rbxassetid://…` | Son non autorisé pour ton expérience | Utilise des sons publics ou tes propres sons importés. |
| Le classement reste vide | Place non publiée, ou pas encore de mise à jour (toutes les 60 s) | Attends 1 minute dans un jeu publié. |
| Les clics « disparaissent » quand je spamme | Normal : au-delà de 20 clics/s, le serveur les ignore (anti-autoclicker) | Change `Config.Game.MaxClicksPerSecond` si besoin. |
| La machine à sous affiche « FERMÉ POUR TRAVAUX » | `Config.Casino.Enabled = false` | Voulu (voir `docs/MONETISATION.md`). |
| `DataStore request was added to queue` | Trop de requêtes DataStore (tests rapides, `/save` répétés) | Sans gravité ; espace tes tests. |
| `tests/run_tests.py` : `FAIL : Luau CLI introuvable` | Binaire `luau` absent | Télécharge Luau et passe `--luau <chemin>`. |
| `tests/run_tests.py` : `Config.X.Y (fichier:ligne)` en échec | Clé de config utilisée dans le code mais absente de `Config.luau` | Corrige la faute de frappe ou ajoute la clé. |

> 💡 Pour repartir de zéro : `/reset` dans Studio, ou change `Config.DataStore.Name` (ex. `"DopamineClickerData_v3"`) pour ignorer toutes les anciennes sauvegardes.
