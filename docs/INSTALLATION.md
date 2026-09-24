# 🛠️ Installation pas à pas

Trois méthodes, de la plus simple à la plus manuelle. Choisis-en **une seule**.

| Méthode | Pour qui | Durée |
|---|---|---|
| **A** — fichier `.rbxlx` | Tout le monde | 1 minute |
| **B** — Rojo | Si tu codes dans VS Code | 5 minutes |
| **C** — copie manuelle | Sans téléchargement de fichier de place | 30–45 minutes (64 scripts) |

---

## Méthode A : ouvrir le fichier de place (recommandé)

1. Télécharge **`build/DopamineClicker.rbxlx`** :
   - depuis la page GitHub du dépôt (fichier `build/DopamineClicker.rbxlx` → bouton **Download raw file**) ;
   - ou en lien direct : `https://github.com/clemtent/projetperso/raw/<branche>/build/DopamineClicker.rbxlx`
     (ex. <https://github.com/clemtent/projetperso/raw/main/build/DopamineClicker.rbxlx> pour `main`).
2. Ouvre-le avec Roblox Studio (double-clic, ou **Fichier > Ouvrir depuis un fichier**).
3. Vérifie dans l'Explorer : `ReplicatedStorage > Shared`, `ReplicatedStorage > Client` (avec `Components` et `Stimuli`), `ServerScriptService > Main` + `Services`, `StarterPlayer > StarterPlayerScripts > ClientMain`.
4. **Fichier > Publier sur Roblox** → crée une nouvelle expérience (ou remplace une existante).
5. **Accueil > Paramètres du jeu > Sécurité** → active **Enable Studio Access to API Services** → Enregistrer.
6. ▶️ **Play**. La fenêtre **Sortie** doit afficher `[Dopamine Clicker] Serveur prêt (1 joueur(s))`.

Le fichier de place contient aussi un `Workspace` minimal (une `Baseplate` et un `SpawnLocation` invisible) : le jeu se joue entièrement dans l'interface 2D.

## Méthode B : Rojo (si tu codes dans VS Code)

```bash
# Installer Rojo 7 : https://rojo.space/docs/v7/getting-started/installation/
rojo serve default.project.json
```

Dans Studio : plugin Rojo → **Connect**. Tous les scripts de `src/` sont synchronisés en direct.

| Fichier projet | Contenu | Usage |
|---|---|---|
| `default.project.json` | `ReplicatedStorage`, `ServerScriptService`, `StarterPlayer > StarterPlayerScripts` | `rojo serve` (synchronisation) |
| `build.project.json` | La même chose + `Workspace` (Baseplate + SpawnLocation) | génération du fichier de place |

Pour régénérer le fichier de place après une modification :

```bash
rojo build build.project.json -o build/DopamineClicker.rbxlx
```

Puis étapes 4 à 6 de la méthode A.

## Méthode C : copier-coller à la main

Règle de correspondance : `*.server.luau` = **Script**, `*.client.luau` = **LocalScript**, tout autre `*.luau` = **ModuleScript**, dossier = **Folder**. Le nom de l'objet = le nom du fichier **sans** l'extension (`Main.server.luau` → `Main`).

### 1. Crée d'abord les dossiers (Folder)

Clic droit sur le parent → **Insert Object** → **Folder**, puis renomme-le.

| Dossier | Emplacement exact |
|---|---|
| `Shared` | `ReplicatedStorage > Shared` |
| `Client` | `ReplicatedStorage > Client` |
| `Components` | `ReplicatedStorage > Client > Components` |
| `Panels` | `ReplicatedStorage > Client > Components > Panels` |
| `Stimuli` | `ReplicatedStorage > Client > Stimuli` |
| `Services` | `ServerScriptService > Services` |

`StarterPlayer > StarterPlayerScripts` existe déjà. **Ne crée pas** `ReplicatedStorage > Remotes` : le serveur le crée tout seul.

### 2. Puis chaque script (liste complète, 64 fichiers)

Crée l'objet du bon type à l'emplacement indiqué, renomme-le **exactement**, ouvre-le et colle **tout** le contenu du fichier.

| Objet dans Studio (emplacement exact) | Type | Fichier à copier |
|---|---|---|
| `ReplicatedStorage > Client > ClientState` | ModuleScript | `src/ReplicatedStorage/Client/ClientState.luau` |
| `ReplicatedStorage > Client > Components > Background` | ModuleScript | `src/ReplicatedStorage/Client/Components/Background.luau` |
| `ReplicatedStorage > Client > Components > CenterColumn` | ModuleScript | `src/ReplicatedStorage/Client/Components/CenterColumn.luau` |
| `ReplicatedStorage > Client > Components > Notifications` | ModuleScript | `src/ReplicatedStorage/Client/Components/Notifications.luau` |
| `ReplicatedStorage > Client > Components > PanelManager` | ModuleScript | `src/ReplicatedStorage/Client/Components/PanelManager.luau` |
| `ReplicatedStorage > Client > Components > Panels > Achievements` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Achievements.luau` |
| `ReplicatedStorage > Client > Components > Panels > Daily` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Daily.luau` |
| `ReplicatedStorage > Client > Components > Panels > ItemShop` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/ItemShop.luau` |
| `ReplicatedStorage > Client > Components > Panels > Leaderboard` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Leaderboard.luau` |
| `ReplicatedStorage > Client > Components > Panels > Quests` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Quests.luau` |
| `ReplicatedStorage > Client > Components > Panels > ScreenTime` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/ScreenTime.luau` |
| `ReplicatedStorage > Client > Components > Panels > Settings` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Settings.luau` |
| `ReplicatedStorage > Client > Components > UpgradeBar` | ModuleScript | `src/ReplicatedStorage/Client/Components/UpgradeBar.luau` |
| `ReplicatedStorage > Client > Effects` | ModuleScript | `src/ReplicatedStorage/Client/Effects.luau` |
| `ReplicatedStorage > Client > Interface` | ModuleScript | `src/ReplicatedStorage/Client/Interface.luau` |
| `ReplicatedStorage > Client > Slots` | ModuleScript | `src/ReplicatedStorage/Client/Slots.luau` |
| `ReplicatedStorage > Client > SoundManager` | ModuleScript | `src/ReplicatedStorage/Client/SoundManager.luau` |
| `ReplicatedStorage > Client > Stimuli > BubbleWrap` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/BubbleWrap.luau` |
| `ReplicatedStorage > Client > Stimuli > Casino` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Casino.luau` |
| `ReplicatedStorage > Client > Stimuli > CursorTrail` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/CursorTrail.luau` |
| `ReplicatedStorage > Client > Stimuli > DVD` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/DVD.luau` |
| `ReplicatedStorage > Client > Stimuli > Disco` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Disco.luau` |
| `ReplicatedStorage > Client > Stimuli > Email` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Email.luau` |
| `ReplicatedStorage > Client > Stimuli > EmojiRain` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/EmojiRain.luau` |
| `ReplicatedStorage > Client > Stimuli > GoldenStar` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/GoldenStar.luau` |
| `ReplicatedStorage > Client > Stimuli > LiveStream` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/LiveStream.luau` |
| `ReplicatedStorage > Client > Stimuli > Lofi` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Lofi.luau` |
| `ReplicatedStorage > Client > Stimuli > LootBox` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/LootBox.luau` |
| `ReplicatedStorage > Client > Stimuli > Megaphone` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Megaphone.luau` |
| `ReplicatedStorage > Client > Stimuli > NeonMode` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/NeonMode.luau` |
| `ReplicatedStorage > Client > Stimuli > NewsTicker` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/NewsTicker.luau` |
| `ReplicatedStorage > Client > Stimuli > Ocean` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Ocean.luau` |
| `ReplicatedStorage > Client > Stimuli > PhoneNotifs` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/PhoneNotifs.luau` |
| `ReplicatedStorage > Client > Stimuli > Pinwheel` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Pinwheel.luau` |
| `ReplicatedStorage > Client > Stimuli > Press` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Press.luau` |
| `ReplicatedStorage > Client > Stimuli > Runner` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Runner.luau` |
| `ReplicatedStorage > Client > Stimuli > Stocks` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Stocks.luau` |
| `ReplicatedStorage > Client > Stimuli > Weather` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Weather.luau` |
| `ReplicatedStorage > Client > StimulusManager` | ModuleScript | `src/ReplicatedStorage/Client/StimulusManager.luau` |
| `ReplicatedStorage > Client > Theme` | ModuleScript | `src/ReplicatedStorage/Client/Theme.luau` |
| `ReplicatedStorage > Client > UIUtil` | ModuleScript | `src/ReplicatedStorage/Client/UIUtil.luau` |
| `ReplicatedStorage > Shared > Config` | ModuleScript | `src/ReplicatedStorage/Shared/Config.luau` |
| `ReplicatedStorage > Shared > DVDMath` | ModuleScript | `src/ReplicatedStorage/Shared/DVDMath.luau` |
| `ReplicatedStorage > Shared > Formulas` | ModuleScript | `src/ReplicatedStorage/Shared/Formulas.luau` |
| `ReplicatedStorage > Shared > Net` | ModuleScript | `src/ReplicatedStorage/Shared/Net.luau` |
| `ReplicatedStorage > Shared > NumberFormatter` | ModuleScript | `src/ReplicatedStorage/Shared/NumberFormatter.luau` |
| `ReplicatedStorage > Shared > Signal` | ModuleScript | `src/ReplicatedStorage/Shared/Signal.luau` |
| `ServerScriptService > Main` | **Script** | `src/ServerScriptService/Main.server.luau` |
| `ServerScriptService > Services > AchievementService` | ModuleScript | `src/ServerScriptService/Services/AchievementService.luau` |
| `ServerScriptService > Services > CasinoService` | ModuleScript | `src/ServerScriptService/Services/CasinoService.luau` |
| `ServerScriptService > Services > CosmeticService` | ModuleScript | `src/ServerScriptService/Services/CosmeticService.luau` |
| `ServerScriptService > Services > DVDService` | ModuleScript | `src/ServerScriptService/Services/DVDService.luau` |
| `ServerScriptService > Services > DailyRewardService` | ModuleScript | `src/ServerScriptService/Services/DailyRewardService.luau` |
| `ServerScriptService > Services > DataService` | ModuleScript | `src/ServerScriptService/Services/DataService.luau` |
| `ServerScriptService > Services > DebugService` | ModuleScript | `src/ServerScriptService/Services/DebugService.luau` |
| `ServerScriptService > Services > EventService` | ModuleScript | `src/ServerScriptService/Services/EventService.luau` |
| `ServerScriptService > Services > GameService` | ModuleScript | `src/ServerScriptService/Services/GameService.luau` |
| `ServerScriptService > Services > InteractService` | ModuleScript | `src/ServerScriptService/Services/InteractService.luau` |
| `ServerScriptService > Services > LeaderboardService` | ModuleScript | `src/ServerScriptService/Services/LeaderboardService.luau` |
| `ServerScriptService > Services > LootService` | ModuleScript | `src/ServerScriptService/Services/LootService.luau` |
| `ServerScriptService > Services > QuestService` | ModuleScript | `src/ServerScriptService/Services/QuestService.luau` |
| `ServerScriptService > Services > RateLimiter` | ModuleScript | `src/ServerScriptService/Services/RateLimiter.luau` |
| `ServerScriptService > Services > StockService` | ModuleScript | `src/ServerScriptService/Services/StockService.luau` |
| `StarterPlayer > StarterPlayerScripts > ClientMain` | **LocalScript** | `src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau` |

⚠️ Les noms sont sensibles à la casse (`GameService` ≠ `Gameservice`, `NewsTicker` ≠ `Newsticker`).
⚠️ `Main` doit être un **Script**, `ClientMain` un **LocalScript**, tout le reste des **ModuleScript**.
⚠️ Un nouveau Script/ModuleScript contient déjà `print("Hello world!")` ou `local module = {} return module` : **remplace tout**.
💡 Le nom d'un module du dossier `Stimuli` doit être **exactement** le nom de sa Feature (voir `Config.Upgrades`), sinon il ne sera jamais lancé (aucune erreur : il est simplement ignoré).

Ensuite : étapes 4 à 6 de la méthode A.

---

## 🔌 RemoteEvents / RemoteFunctions

**Rien à créer à la main.** Au démarrage, `Main` appelle `Net.Setup()` (`Shared > Net`) qui crée `ReplicatedStorage > Remotes` avec tous les remotes ci-dessous. Le client les récupère avec `Net.Event("Nom")` / `Net.Function("Nom")`.
C → S = le client **demande**, le serveur valide tout. S → C = le serveur **informe**. Le serveur n'appelle **jamais** `InvokeClient`.

### RemoteEvents

| Nom | Sens | Arguments | Rôle |
|---|---|---|---|
| `ClientReady` | C → S | *(aucun)* | L'interface est prête : le serveur renvoie tout (état, logos DVD, rush, classement, bourse) |
| `Click` | C → S | *(aucun)* | Un clic sur le bouton « Clique-moi » |
| `StateUpdate` | S → C | `state` | État complet du joueur (Dopamine, améliorations, Features, stats, combo, bourse, coffres, cosmétiques, temps d'écran, `ClickSeq`…) |
| `Notify` | S → C | `payload` | `Type` = `Info`, `Error`, `Achievement`, `Quest`, `Bonus` (`Source`, `Amount`), `Jackpot`, `Rush`, `Unlock` (`Feature`, `UpgradeId`, `Text`), `Detox` (`Rebirths`, `Multiplier`) |
| `DVDSetup` | S → C | `{ Logos = { {X0, Y0, VX, VY, T0, W, H}, … } }` | Trajectoires des logos DVD |
| `DVDResize` | C → S | `w, h` | Taille d'un logo à l'écran (fraction de l'écran) |
| `DVDClick` | C → S | `index` | Clic sur le logo numéro `index` |
| `DVDCorner` | C → S | `index, k` | « Le logo `index` a touché un coin au rebond `k` » (recalculé par le serveur) |
| `Spawn` | S → C | `{ Kind, Id, X, Y, Lifetime, Variant }` | Un objet à cliquer apparaît (`Kind` = `Golden`, `Lightning`, `Notif`, `Email`) |
| `SpawnClick` | C → S | `id` | Le joueur a cliqué cet objet |
| `Interact` | C → S | `kind, arg` | `kind` = `Bubble`, `Spin`, `Headline`, `Press` (papier bulle, moulin, titre du fil d'actu, presse) |
| `EventUpdate` | S → C | `rush` | Début / fin d'un Dopamine Rush |
| `LeaderboardUpdate` | S → C | `top` | Top du classement |
| `StockUpdate` | S → C | `{ Symbol, Price, History }` | Cours de la bourse (commun à tout le serveur) |

### RemoteFunctions (C → S, avec réponse)

| Nom | Arguments | Réponse | Rôle |
|---|---|---|---|
| `BuyUpgrade` | `upgradeId` | `(succès, message)` | Acheter un niveau d'amélioration (ou « Aller à l'océan ») |
| `ClaimDaily` | *(aucun)* | `(succès, message)` | Récupérer le cadeau du jour |
| `SetSetting` | `nom, valeur` | `succès` | `Sound`, `Music` ou `Effects` (booléen) |
| `StockTrade` | `"buy"` \| `"sell"`, `fraction` | `(succès, message)` | Acheter / vendre des actions DOPA |
| `CasinoSpin` | `fraction` | `(succès, résultat \| message)` | Un tour de machine à sous ; `résultat = { Reels, Bet, Payout, Multiplier }` |
| `OpenChest` | *(aucun)* | `(succès, résultat \| message)` | Ouvrir un coffre ; `résultat = { Tier, Amount }` |
| `ItemShop` | `"buy"` \| `"equip"` \| `"unequip"`, `cosmeticId` | `(succès, message)` | Boutique d'objets |

---

## 🎨 L'interface

L'interface est **entièrement créée par code** (`Client > Interface`, `Client > Components`, `Client > Stimuli`). Il n'y a rien à dessiner dans `StarterGui`.

- Toile virtuelle de **1280×720** mise à l'échelle par un `UIScale` : même rendu sur PC, tablette et téléphone.
- Orientation paysage sur mobile (`LandscapeSensor`).
- Couleurs et polices dans `Client > Theme` (palette claire ; palette sombre pour le mode néon).
- Emplacements des stimuli dans `Client > Slots` (voir le tableau « Slots » du [README](../README.md)).

---

## 🔊 Mettre tes propres sons

Dans `Shared > Config`, section `Config.Sounds` (22 entrées : `Click`, `Buy`, `Error`, `Bounce`, `Bonus`, `Achievement`, `Jackpot`, `Golden`, `Rush`, `Detox`, `Open`, `Pop`, `Crush`, `Thunder`, `Notif`, `Mail`, `SlotSpin`, `SlotWin`, `Chest`, `Cash`, `Megaphone`, `Music`) :

```lua
Click = { Id = "rbxassetid://1234567890", Volume = 0.5 },
Music = { Id = "rbxassetid://9876543210", Volume = 0.3 },
```

- Trouve des sons : **Boîte à outils (Toolbox) > Audio**, clic droit → **Copier l'ID de l'élément**.
- Laisse `""` pour désactiver un son.
- Par défaut, des sons intégrés à Roblox (`rbxasset://sounds/...`) sont utilisés et **il n'y a pas de musique** (`Music.Id = ""`).
- La musique (jouée en boucle) ne démarre que si le joueur possède **Lofi Beats** et que le réglage « 🎵 Musique » est activé.

## 🖼️ Images

Tout est dessiné en code (logo « DOPA », étoiles, coffre, machine à sous…). Une seule image est personnalisable :

- `Config.DVD.LogoImage = "rbxassetid://..."` : ton propre logo DVD. Utilise une image **blanche** sur fond transparent : elle est recolorée (`ImageColor3`) à chaque rebond. Vide (`""`) = logo « DOPA » dessiné en code.

⚠️ N'utilise pas le vrai logo « DVD Video », ni des images de jeux, de vidéos ou de chaînes existantes (marques déposées / droits d'auteur).

---

## ➕ Ajouter un nouveau stimulus

Un stimulus = un **ModuleScript** dans `ReplicatedStorage > Client > Stimuli`, nommé comme la **Feature** qui le débloque. `StimulusManager` le lance tout seul dès que le joueur possède la Feature, et l'arrête après l'océan.

**1. Déclare l'amélioration** dans `Config.Upgrades` (à la position voulue dans la progression) :

```lua
{ Id = "Aquarium", Name = "Aquarium", Icon = "🐠", Description = "Des poissons qui nagent. +%s Dopamine / s",
	Cost = 2e6, MaxLevel = 1, Effect = "PerSecond", Value = 500, Feature = "Aquarium",
	Color = Color3.fromRGB(0, 170, 220) },
```

Chaque `Feature` doit être unique (vérifié par `tests/run_tests.py`). L'océan doit rester la **dernière** amélioration.

**2. Crée le module** `Client > Stimuli > Aquarium` :

```lua
local Aquarium = {}

-- Emplacement : "Ticker", "L1", "R1", "L2", "R2", "CL", "CR", "L3", "C3", "R3",
-- ou "Overlay" (plein écran, au-dessus) / "Background" (plein écran, sous tout).
Aquarium.Slot = "L2"

function Aquarium.Start(ctx)
	-- Construis TOUT dans ctx.Container (déjà créé à la bonne taille / position)
	local fish = ctx.UIUtil.Label({
		Text = "🐠",
		Size = UDim2.fromOffset(60, 60),
		Parent = ctx.Container,
	})

	-- Connexions : toujours via ctx.Connect / ctx.OnRender (coupées automatiquement)
	local t = 0
	ctx.OnRender(function(dt)
		t += dt
		fish.Position = UDim2.new(0.5 + 0.35 * math.sin(t), -30, 0.5, -30)
	end)

	-- Boucles : toujours vérifier ctx.IsAlive()
	task.spawn(function()
		while ctx.IsAlive() do
			task.wait(3)
			if ctx.EffectsEnabled() then
				ctx.FloatText(ctx.Container, UDim2.fromScale(0.5, 0.2), "blub", ctx.Theme.Colors.Blue)
			end
		end
	end)
end

-- Optionnel : nettoyage en plus (sons, objets créés dans ctx.Overlay...)
function Aquarium.Stop(ctx)
end

return Aquarium
```

**Règles** :
- `Start(ctx)` ne doit pas bloquer indéfiniment (lance les boucles avec `task.spawn`).
- Toute connexion passe par `ctx.Connect(signal, fn)`, `ctx.OnRender(fn)`, `ctx.OnSpawn(kind, fn)` ou `ctx.OnBonus(source, fn)`.
- Un gain doit **toujours** passer par le serveur : `ctx.Interact(kind, arg)` : ajoute simplement une entrée dans `Config.Interactions` (`Feature`, `Cooldown`, `RewardSeconds`, `MinReward`, `Stat`) ; `InteractService` la gère sans autre code (recharge + récompense + `Notify` "Bonus" avec `Source = kind`, à écouter avec `ctx.OnBonus(kind, fn)`) ou `ctx.ClaimSpawn(id)` pour un objet reçu par `ctx.OnSpawn`.
- Les appels de RemoteFunction (`ctx.Net.Function("...")`) se font dans un `pcall`.
- Ce que tu mets dans `ctx.Overlay` (et non dans `ctx.Container`) doit être détruit dans `Stop`.
- Pas de module pour la Feature ? Aucune erreur : l'amélioration marche quand même (effet économique seul).

Champs disponibles dans `ctx` : `Feature`, `Container`, `Overlay`, `State` (ClientState), `Config`, `Formulas`, `Format` (NumberFormatter), `Net`, `Theme`, `UIUtil`, `Effects`, `Sound` (SoundManager), `DVDMath`, `Notify(text, color?)`, `FloatText(parent, position, text, color?, size?)`, `GetLevel(upgradeId)`, `HasFeature(feature)`, `ClaimSpawn(id)`, `Interact(kind, arg?)`, `OnSpawn(kind, fn)`, `OnBonus(source, fn)`, `Connect(signal, fn)`, `OnRender(fn)`, `IsAlive()`, `SetDarkMode(bool)`, `EffectsEnabled()`, `Slot`, `Interface`, `Random`.

**3. Vérifie** : `python3 tests/run_tests.py` (voir [`TESTS.md`](TESTS.md)), puis dans Studio `/give 1e9` et achète l'amélioration.
