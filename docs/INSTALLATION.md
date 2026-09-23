# 🛠️ Installation pas à pas

Trois méthodes, de la plus simple à la plus manuelle. Choisis-en **une seule**.

---

## Méthode A : ouvrir le fichier de place (recommandé)

1. Télécharge `build/DopamineClicker.rbxlx` depuis ce dépôt.
2. Ouvre-le avec Roblox Studio (double-clic, ou **Fichier > Ouvrir depuis un fichier**).
3. Vérifie dans l'Explorer que tu as bien `ReplicatedStorage > Shared`, `ReplicatedStorage > Client`, `ServerScriptService > Main` et `StarterPlayer > StarterPlayerScripts > ClientMain`.
4. **Fichier > Publier sur Roblox** → crée une nouvelle expérience.
5. **Accueil > Paramètres du jeu > Sécurité** → active **Enable Studio Access to API Services** → Enregistrer.
6. ▶️ **Play**.

## Méthode B : Rojo (si tu codes dans VS Code)

```bash
# Installer Rojo : https://rojo.space/docs/v7/getting-started/installation/
rojo serve default.project.json
```
Dans Studio : plugin Rojo → **Connect**. Tous les scripts sont synchronisés.
Pour régénérer le fichier de place : `rojo build build.project.json -o build/DopamineClicker.rbxlx`.

## Méthode C : copier-coller à la main

Crée chaque objet (clic droit → **Insert Object**), renomme-le **exactement** comme indiqué, puis colle le contenu du fichier correspondant.

| Objet dans Studio | Type | Fichier à copier |
|---|---|---|
| `ReplicatedStorage > Shared` | Folder | — |
| `Shared > Config` | ModuleScript | `src/ReplicatedStorage/Shared/Config.luau` |
| `Shared > Formulas` | ModuleScript | `src/ReplicatedStorage/Shared/Formulas.luau` |
| `Shared > NumberFormatter` | ModuleScript | `src/ReplicatedStorage/Shared/NumberFormatter.luau` |
| `Shared > Net` | ModuleScript | `src/ReplicatedStorage/Shared/Net.luau` |
| `Shared > DVDMath` | ModuleScript | `src/ReplicatedStorage/Shared/DVDMath.luau` |
| `Shared > Signal` | ModuleScript | `src/ReplicatedStorage/Shared/Signal.luau` |
| `ReplicatedStorage > Client` | Folder | — |
| `Client > Theme` | ModuleScript | `src/ReplicatedStorage/Client/Theme.luau` |
| `Client > UIUtil` | ModuleScript | `src/ReplicatedStorage/Client/UIUtil.luau` |
| `Client > Interface` | ModuleScript | `src/ReplicatedStorage/Client/Interface.luau` |
| `Client > ClientState` | ModuleScript | `src/ReplicatedStorage/Client/ClientState.luau` |
| `Client > SoundManager` | ModuleScript | `src/ReplicatedStorage/Client/SoundManager.luau` |
| `Client > Effects` | ModuleScript | `src/ReplicatedStorage/Client/Effects.luau` |
| `Client > Components` | Folder | — |
| `Components > Background` | ModuleScript | `src/ReplicatedStorage/Client/Components/Background.luau` |
| `Components > HUD` | ModuleScript | `src/ReplicatedStorage/Client/Components/HUD.luau` |
| `Components > Clicker` | ModuleScript | `src/ReplicatedStorage/Client/Components/Clicker.luau` |
| `Components > Shop` | ModuleScript | `src/ReplicatedStorage/Client/Components/Shop.luau` |
| `Components > SideMenu` | ModuleScript | `src/ReplicatedStorage/Client/Components/SideMenu.luau` |
| `Components > PanelManager` | ModuleScript | `src/ReplicatedStorage/Client/Components/PanelManager.luau` |
| `Components > Notifications` | ModuleScript | `src/ReplicatedStorage/Client/Components/Notifications.luau` |
| `Components > DVDLogo` | ModuleScript | `src/ReplicatedStorage/Client/Components/DVDLogo.luau` |
| `Components > GoldenObject` | ModuleScript | `src/ReplicatedStorage/Client/Components/GoldenObject.luau` |
| `Components > Panels` | Folder | — |
| `Panels > Quests` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Quests.luau` |
| `Panels > Achievements` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Achievements.luau` |
| `Panels > Rebirth` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Rebirth.luau` |
| `Panels > Daily` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Daily.luau` |
| `Panels > Leaderboard` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Leaderboard.luau` |
| `Panels > Settings` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Settings.luau` |
| `ServerScriptService > Main` | **Script** | `src/ServerScriptService/Main.server.luau` |
| `ServerScriptService > Services` | Folder | — |
| `Services > DataService` | ModuleScript | `src/ServerScriptService/Services/DataService.luau` |
| `Services > GameService` | ModuleScript | `src/ServerScriptService/Services/GameService.luau` |
| `Services > AchievementService` | ModuleScript | `src/ServerScriptService/Services/AchievementService.luau` |
| `Services > QuestService` | ModuleScript | `src/ServerScriptService/Services/QuestService.luau` |
| `Services > DailyRewardService` | ModuleScript | `src/ServerScriptService/Services/DailyRewardService.luau` |
| `Services > EventService` | ModuleScript | `src/ServerScriptService/Services/EventService.luau` |
| `Services > DVDService` | ModuleScript | `src/ServerScriptService/Services/DVDService.luau` |
| `Services > LeaderboardService` | ModuleScript | `src/ServerScriptService/Services/LeaderboardService.luau` |
| `Services > RateLimiter` | ModuleScript | `src/ServerScriptService/Services/RateLimiter.luau` |
| `Services > DebugService` | ModuleScript | `src/ServerScriptService/Services/DebugService.luau` |
| `StarterPlayer > StarterPlayerScripts > ClientMain` | **LocalScript** | `src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau` |

⚠️ Les noms sont sensibles à la casse (`GameService` ≠ `Gameservice`).
⚠️ `Main` doit être un **Script**, `ClientMain` un **LocalScript**, tout le reste des **ModuleScript**.

Ensuite : étapes 4 à 6 de la méthode A.

---

## 🔌 RemoteEvents / RemoteFunctions

**Rien à créer à la main.** Au démarrage, `Main` appelle `Net.Setup()` qui crée `ReplicatedStorage > Remotes` avec :

| Nom | Type | Sens | Rôle |
|---|---|---|---|
| `ClientReady` | RemoteEvent | Client → Serveur | L'interface est prête, envoie-moi mes données |
| `Click` | RemoteEvent | Client → Serveur | Un clic sur le gros bouton |
| `StateUpdate` | RemoteEvent | Serveur → Client | État complet du joueur (5 fois/s max) |
| `Notify` | RemoteEvent | Serveur → Client | Succès, quêtes, bonus, jackpot, rush, erreurs |
| `DVDSetup` | RemoteEvent | Serveur → Client | Trajectoire du logo DVD |
| `DVDResize` | RemoteEvent | Client → Serveur | Taille du logo à l'écran |
| `DVDClick` | RemoteEvent | Client → Serveur | Clic sur le logo |
| `DVDCorner` | RemoteEvent | Client → Serveur | « J'ai vu un coin » (vérifié par le serveur) |
| `GoldenSpawn` | RemoteEvent | Serveur → Client | Un objet doré apparaît |
| `GoldenClick` | RemoteEvent | Client → Serveur | Clic sur l'objet doré |
| `EventUpdate` | RemoteEvent | Serveur → Client | Début / fin du Dopamine Rush |
| `LeaderboardUpdate` | RemoteEvent | Serveur → Client | Top 10 mondial |
| `BuyUpgrade` | RemoteFunction | Client → Serveur | Achat `(id, "x1" \| "x10" \| "max")` → `(ok, message)` |
| `Rebirth` | RemoteFunction | Client → Serveur | Rebirth → `(ok, message)` |
| `ClaimDaily` | RemoteFunction | Client → Serveur | Cadeau du jour → `(ok, message)` |
| `SetSetting` | RemoteFunction | Client → Serveur | Son / musique / effets |

Le serveur n'appelle **jamais** `InvokeClient` (dangereux : un client pourrait bloquer le serveur).

---

## 🎨 L'interface

L'interface est **entièrement créée par code** (`Client > Interface` et `Client > Components`). Il n'y a rien à dessiner à la main dans `StarterGui`.

- Toile virtuelle de **1280×720** mise à l'échelle par un `UIScale` : même rendu sur PC, tablette et téléphone.
- `UIAspectRatioConstraint` sur le bouton (cercle parfait), le logo DVD et l'objet doré.
- Orientation paysage forcée sur mobile.
- Couleurs et polices dans `Client > Theme`.

Disposition :
```
┌────────────────────────────────────────────────────────────────────┐
│        ┌──────────── HUD ─────────────┐              ┌── Shop ───┐ │
│ [📜]   │  🧠 DOPAMINE   1.23M          │              │ CLIC PASSIF│ │
│ [🏆]   │ +5/clic  +12/s  x1.5          │   📀 DOPA     │ [carte]   │ │
│ [♻️]   └──────────────────────────────┘   (rebondit) │ [carte]   │ │
│ [🎁]              ( 🧠 CLIQUE-MOI )                   │ [carte]   │ │
│ [🥇]              [== COMBO x2.1 ==]                  │ [carte]   │ │
│ [⚙️]              [ toasts / notifications ]          └───────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🔊 Mettre tes propres sons

Dans `Shared > Config`, section `Config.Sounds` :

```lua
Click = { Id = "rbxassetid://1234567890", Volume = 0.5 },
Music = { Id = "rbxassetid://9876543210", Volume = 0.3 },
```

- Trouve des sons gratuits : **Boîte à outils (Toolbox) > Audio**, clic droit → **Copier l'ID de l'élément**.
- Laisse `""` pour désactiver un son.
- Par défaut, des sons intégrés à Roblox (`rbxasset://sounds/...`) sont utilisés, et **pas de musique**.

## 🖼️ Mettre ton propre logo DVD / objet doré

- `Config.DVD.LogoImage = "rbxassetid://..."` : utilise une image **blanche** sur fond transparent (elle sera recolorée à chaque rebond). Vide = logo « DOPA VIDEO » dessiné en code.
- `Config.Events.Golden.Image = "rbxassetid://..."`. Vide = étoile 🌟 dorée.

⚠️ N'utilise pas le vrai logo « DVD Video » (marque déposée) : crée ton propre logo.
