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
| `Client` | `ReplicatedStorage > Client` |
| `Components` | `ReplicatedStorage > Client > Components` |
| `House` | `ReplicatedStorage > Client > Components > House` |
| `Art` | `ReplicatedStorage > Client > Components > House > Art` |
| `GardenArt` | `ReplicatedStorage > Client > Components > House > GardenArt` |
| `Panels` | `ReplicatedStorage > Client > Components > Panels` |
| `Minigames` | `ReplicatedStorage > Client > Minigames` |
| `Stimuli` | `ReplicatedStorage > Client > Stimuli` |
| `Cosmos` | `ReplicatedStorage > Client > Stimuli > Cosmos` |
| `Gear` | `ReplicatedStorage > Client > Stimuli > Gear` |
| `Live` | `ReplicatedStorage > Client > Stimuli > Live` |
| `World` | `ReplicatedStorage > Client > World` |
| `Shared` | `ReplicatedStorage > Shared` |
| `Lang` | `ReplicatedStorage > Shared > Lang` |
| `Services` | `ServerScriptService > Services` |
| `Arcade` | `ServerScriptService > Services > Arcade` |
| `World` | `ServerScriptService > Services > World` |

`StarterPlayer > StarterPlayerScripts` existe déjà. **Ne crée pas** `ReplicatedStorage > Remotes` : le serveur le crée tout seul.

### 2. Puis chaque script (liste complète, 316 fichiers)

Crée l'objet du bon type à l'emplacement indiqué, renomme-le **exactement**, ouvre-le et colle **tout** le contenu du fichier.

| Objet dans Studio (emplacement exact) | Type | Fichier à copier |
|---|---|---|
| `ReplicatedStorage > Client > ClientState` | ModuleScript | `src/ReplicatedStorage/Client/ClientState.luau` |
| `ReplicatedStorage > Client > Components > AchievementPopup` | ModuleScript | `src/ReplicatedStorage/Client/Components/AchievementPopup.luau` |
| `ReplicatedStorage > Client > Components > Background` | ModuleScript | `src/ReplicatedStorage/Client/Components/Background.luau` |
| `ReplicatedStorage > Client > Components > CenterColumn` | ModuleScript | `src/ReplicatedStorage/Client/Components/CenterColumn.luau` |
| `ReplicatedStorage > Client > Components > CosmeticArt` | ModuleScript | `src/ReplicatedStorage/Client/Components/CosmeticArt.luau` |
| `ReplicatedStorage > Client > Components > DebugTools` | ModuleScript | `src/ReplicatedStorage/Client/Components/DebugTools.luau` |
| `ReplicatedStorage > Client > Components > FoodBoostBadge` | ModuleScript | `src/ReplicatedStorage/Client/Components/FoodBoostBadge.luau` |
| `ReplicatedStorage > Client > Components > GraphicsControls` | ModuleScript | `src/ReplicatedStorage/Client/Components/GraphicsControls.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Cool92Adventure` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Cool92Adventure.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Cool92Gaming` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Cool92Gaming.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Cool92Music` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Cool92Music.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Cool92Sports` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Cool92Sports.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Cozy91` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Cozy91.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Critters` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Critters.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Decor` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Decor.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Doors` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Doors.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Electronics` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Electronics.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Fun91` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Fun91.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Furniture` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Furniture.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Kitchen` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Kitchen.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Lights` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Lights.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Luxe98` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Luxe98.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Modern98` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Modern98.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Nature91` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Nature91.luau` |
| `ReplicatedStorage > Client > Components > House > Art > PetFurniture` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/PetFurniture.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Pets` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Pets.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Plants` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Plants.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Setup95` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Setup95.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Tables` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Tables.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Tabletop` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Tabletop.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Toys` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Toys.luau` |
| `ReplicatedStorage > Client > Components > House > Art > Windows` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/Art/Windows.luau` |
| `ReplicatedStorage > Client > Components > House > GardenArt > Cool92Garden` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/GardenArt/Cool92Garden.luau` |
| `ReplicatedStorage > Client > Components > House > GardenArt > Garden` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/GardenArt/Garden.luau` |
| `ReplicatedStorage > Client > Components > House > House3D` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3D.luau` |
| `ReplicatedStorage > Client > Components > House > House3DCritters` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DCritters.luau` |
| `ReplicatedStorage > Client > Components > House > House3DFloor` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DFloor.luau` |
| `ReplicatedStorage > Client > Components > House > House3DKit` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DKit.luau` |
| `ReplicatedStorage > Client > Components > House > House3DLayout` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DLayout.luau` |
| `ReplicatedStorage > Client > Components > House > House3DLuxe` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DLuxe.luau` |
| `ReplicatedStorage > Client > Components > House > House3DObjects` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DObjects.luau` |
| `ReplicatedStorage > Client > Components > House > House3DRecipes` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DRecipes.luau` |
| `ReplicatedStorage > Client > Components > House > House3DScene` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DScene.luau` |
| `ReplicatedStorage > Client > Components > House > House3DSetup` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DSetup.luau` |
| `ReplicatedStorage > Client > Components > House > House3DToys` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/House3DToys.luau` |
| `ReplicatedStorage > Client > Components > House > HouseArt` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseArt.luau` |
| `ReplicatedStorage > Client > Components > House > HouseButtons` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseButtons.luau` |
| `ReplicatedStorage > Client > Components > House > HouseCommon` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseCommon.luau` |
| `ReplicatedStorage > Client > Components > House > HouseEditor` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseEditor.luau` |
| `ReplicatedStorage > Client > Components > House > HouseExterior` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseExterior.luau` |
| `ReplicatedStorage > Client > Components > House > HouseLookCards` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseLookCards.luau` |
| `ReplicatedStorage > Client > Components > House > HouseMiniRoom` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseMiniRoom.luau` |
| `ReplicatedStorage > Client > Components > House > HouseMoods` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseMoods.luau` |
| `ReplicatedStorage > Client > Components > House > HouseOverview` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseOverview.luau` |
| `ReplicatedStorage > Client > Components > House > HousePatterns` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HousePatterns.luau` |
| `ReplicatedStorage > Client > Components > House > HousePets` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HousePets.luau` |
| `ReplicatedStorage > Client > Components > House > HousePicker` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HousePicker.luau` |
| `ReplicatedStorage > Client > Components > House > HouseRoom` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseRoom.luau` |
| `ReplicatedStorage > Client > Components > House > HouseScenery` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseScenery.luau` |
| `ReplicatedStorage > Client > Components > House > HouseShop` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseShop.luau` |
| `ReplicatedStorage > Client > Components > House > HouseSurfaces` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseSurfaces.luau` |
| `ReplicatedStorage > Client > Components > House > HouseTints` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseTints.luau` |
| `ReplicatedStorage > Client > Components > House > HouseViews` | ModuleScript | `src/ReplicatedStorage/Client/Components/House/HouseViews.luau` |
| `ReplicatedStorage > Client > Components > LoadingScreen` | ModuleScript | `src/ReplicatedStorage/Client/Components/LoadingScreen.luau` |
| `ReplicatedStorage > Client > Components > NeedDopamine` | ModuleScript | `src/ReplicatedStorage/Client/Components/NeedDopamine.luau` |
| `ReplicatedStorage > Client > Components > NeedTickets` | ModuleScript | `src/ReplicatedStorage/Client/Components/NeedTickets.luau` |
| `ReplicatedStorage > Client > Components > Notifications` | ModuleScript | `src/ReplicatedStorage/Client/Components/Notifications.luau` |
| `ReplicatedStorage > Client > Components > OfferPopup` | ModuleScript | `src/ReplicatedStorage/Client/Components/OfferPopup.luau` |
| `ReplicatedStorage > Client > Components > OfflinePopup` | ModuleScript | `src/ReplicatedStorage/Client/Components/OfflinePopup.luau` |
| `ReplicatedStorage > Client > Components > PanelManager` | ModuleScript | `src/ReplicatedStorage/Client/Components/PanelManager.luau` |
| `ReplicatedStorage > Client > Components > Panels > Achievements` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Achievements.luau` |
| `ReplicatedStorage > Client > Components > Panels > Arcade` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Arcade.luau` |
| `ReplicatedStorage > Client > Components > Panels > Daily` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Daily.luau` |
| `ReplicatedStorage > Client > Components > Panels > Debug` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Debug.luau` |
| `ReplicatedStorage > Client > Components > Panels > House` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/House.luau` |
| `ReplicatedStorage > Client > Components > Panels > ItemShop` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/ItemShop.luau` |
| `ReplicatedStorage > Client > Components > Panels > Leaderboard` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Leaderboard.luau` |
| `ReplicatedStorage > Client > Components > Panels > Quests` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Quests.luau` |
| `ReplicatedStorage > Client > Components > Panels > RobuxShop` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/RobuxShop.luau` |
| `ReplicatedStorage > Client > Components > Panels > ScreenTime` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/ScreenTime.luau` |
| `ReplicatedStorage > Client > Components > Panels > Settings` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Settings.luau` |
| `ReplicatedStorage > Client > Components > Panels > Themes` | ModuleScript | `src/ReplicatedStorage/Client/Components/Panels/Themes.luau` |
| `ReplicatedStorage > Client > Components > UpgradeBar` | ModuleScript | `src/ReplicatedStorage/Client/Components/UpgradeBar.luau` |
| `ReplicatedStorage > Client > DarkSkin` | ModuleScript | `src/ReplicatedStorage/Client/DarkSkin.luau` |
| `ReplicatedStorage > Client > Effects` | ModuleScript | `src/ReplicatedStorage/Client/Effects.luau` |
| `ReplicatedStorage > Client > Interface` | ModuleScript | `src/ReplicatedStorage/Client/Interface.luau` |
| `ReplicatedStorage > Client > Minigames > DuelKit` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/DuelKit.luau` |
| `ReplicatedStorage > Client > Minigames > Duel_Connect4` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Duel_Connect4.luau` |
| `ReplicatedStorage > Client > Minigames > Duel_ReactionDuel` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Duel_ReactionDuel.luau` |
| `ReplicatedStorage > Client > Minigames > Duel_SpotRace` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Duel_SpotRace.luau` |
| `ReplicatedStorage > Client > Minigames > Duel_TicTacToe` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Duel_TicTacToe.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Game2048` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Game2048.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Kit` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Kit.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Logic` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Logic.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Memory` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Memory.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Minesweeper` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Minesweeper.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Simon` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Simon.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_Snake` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_Snake.luau` |
| `ReplicatedStorage > Client > Minigames > Solo_WhackAMole` | ModuleScript | `src/ReplicatedStorage/Client/Minigames/Solo_WhackAMole.luau` |
| `ReplicatedStorage > Client > Slots` | ModuleScript | `src/ReplicatedStorage/Client/Slots.luau` |
| `ReplicatedStorage > Client > SoundManager` | ModuleScript | `src/ReplicatedStorage/Client/SoundManager.luau` |
| `ReplicatedStorage > Client > Stimuli > Aurora` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Aurora.luau` |
| `ReplicatedStorage > Client > Stimuli > BubbleWrap` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/BubbleWrap.luau` |
| `ReplicatedStorage > Client > Stimuli > Casino` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Casino.luau` |
| `ReplicatedStorage > Client > Stimuli > CoralKeys` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/CoralKeys.luau` |
| `ReplicatedStorage > Client > Stimuli > Cosmos > Kit` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Cosmos/Kit.luau` |
| `ReplicatedStorage > Client > Stimuli > Cosmos > Zones` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Cosmos/Zones.luau` |
| `ReplicatedStorage > Client > Stimuli > CursorTrail` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/CursorTrail.luau` |
| `ReplicatedStorage > Client > Stimuli > DVD` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/DVD.luau` |
| `ReplicatedStorage > Client > Stimuli > DeepFocus` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/DeepFocus.luau` |
| `ReplicatedStorage > Client > Stimuli > Disco` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Disco.luau` |
| `ReplicatedStorage > Client > Stimuli > DreamMachine` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/DreamMachine.luau` |
| `ReplicatedStorage > Client > Stimuli > Email` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Email.luau` |
| `ReplicatedStorage > Client > Stimuli > EmojiRain` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/EmojiRain.luau` |
| `ReplicatedStorage > Client > Stimuli > Finger` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Finger.luau` |
| `ReplicatedStorage > Client > Stimuli > GalaxyStream` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/GalaxyStream.luau` |
| `ReplicatedStorage > Client > Stimuli > Garden` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Garden.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > ClickableKeys` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/ClickableKeys.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > GearClick` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/GearClick.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > GearKit` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/GearKit.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > GearLayout` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/GearLayout.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > GearPiece` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/GearPiece.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > HandArt` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/HandArt.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > KeyInput` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/KeyInput.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > KeyboardArt` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/KeyboardArt.luau` |
| `ReplicatedStorage > Client > Stimuli > Gear > KeyboardPanel` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Gear/KeyboardPanel.luau` |
| `ReplicatedStorage > Client > Stimuli > GoldenStar` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/GoldenStar.luau` |
| `ReplicatedStorage > Client > Stimuli > InfiniteScroll` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/InfiniteScroll.luau` |
| `ReplicatedStorage > Client > Stimuli > Keyboard` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Keyboard.luau` |
| `ReplicatedStorage > Client > Stimuli > Live > ChatInput` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Live/ChatInput.luau` |
| `ReplicatedStorage > Client > Stimuli > Live > ChatPanel` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Live/ChatPanel.luau` |
| `ReplicatedStorage > Client > Stimuli > Live > ChatReplies` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Live/ChatReplies.luau` |
| `ReplicatedStorage > Client > Stimuli > Live > Hud` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Live/Hud.luau` |
| `ReplicatedStorage > Client > Stimuli > LiveStream` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/LiveStream.luau` |
| `ReplicatedStorage > Client > Stimuli > Lofi` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Lofi.luau` |
| `ReplicatedStorage > Client > Stimuli > LootBox` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/LootBox.luau` |
| `ReplicatedStorage > Client > Stimuli > MegaFinger` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/MegaFinger.luau` |
| `ReplicatedStorage > Client > Stimuli > Megaphone` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Megaphone.luau` |
| `ReplicatedStorage > Client > Stimuli > Mouse` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Mouse.luau` |
| `ReplicatedStorage > Client > Stimuli > Multiverse` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Multiverse.luau` |
| `ReplicatedStorage > Client > Stimuli > NeonMode` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/NeonMode.luau` |
| `ReplicatedStorage > Client > Stimuli > NeuralLink` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/NeuralLink.luau` |
| `ReplicatedStorage > Client > Stimuli > NewsTicker` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/NewsTicker.luau` |
| `ReplicatedStorage > Client > Stimuli > Ocean` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Ocean.luau` |
| `ReplicatedStorage > Client > Stimuli > PhoneNotifs` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/PhoneNotifs.luau` |
| `ReplicatedStorage > Client > Stimuli > Pinwheel` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Pinwheel.luau` |
| `ReplicatedStorage > Client > Stimuli > Press` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Press.luau` |
| `ReplicatedStorage > Client > Stimuli > QuantumFinger` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/QuantumFinger.luau` |
| `ReplicatedStorage > Client > Stimuli > Runner` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Runner.luau` |
| `ReplicatedStorage > Client > Stimuli > Seashell` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Seashell.luau` |
| `ReplicatedStorage > Client > Stimuli > Singularity` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Singularity.luau` |
| `ReplicatedStorage > Client > Stimuli > SleepMode` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/SleepMode.luau` |
| `ReplicatedStorage > Client > Stimuli > TimeWarp` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/TimeWarp.luau` |
| `ReplicatedStorage > Client > Stimuli > Weather` | ModuleScript | `src/ReplicatedStorage/Client/Stimuli/Weather.luau` |
| `ReplicatedStorage > Client > StimulusManager` | ModuleScript | `src/ReplicatedStorage/Client/StimulusManager.luau` |
| `ReplicatedStorage > Client > Theme` | ModuleScript | `src/ReplicatedStorage/Client/Theme.luau` |
| `ReplicatedStorage > Client > UIUtil` | ModuleScript | `src/ReplicatedStorage/Client/UIUtil.luau` |
| `ReplicatedStorage > Client > World > CarClient` | ModuleScript | `src/ReplicatedStorage/Client/World/CarClient.luau` |
| `ReplicatedStorage > Client > World > DealerShowroom` | ModuleScript | `src/ReplicatedStorage/Client/World/DealerShowroom.luau` |
| `ReplicatedStorage > Client > World > DeskGames` | ModuleScript | `src/ReplicatedStorage/Client/World/DeskGames.luau` |
| `ReplicatedStorage > Client > World > DeskMode` | ModuleScript | `src/ReplicatedStorage/Client/World/DeskMode.luau` |
| `ReplicatedStorage > Client > World > FairFx` | ModuleScript | `src/ReplicatedStorage/Client/World/FairFx.luau` |
| `ReplicatedStorage > Client > World > FurnitureEdit` | ModuleScript | `src/ReplicatedStorage/Client/World/FurnitureEdit.luau` |
| `ReplicatedStorage > Client > World > GardenBuilder` | ModuleScript | `src/ReplicatedStorage/Client/World/GardenBuilder.luau` |
| `ReplicatedStorage > Client > World > GardenEdit` | ModuleScript | `src/ReplicatedStorage/Client/World/GardenEdit.luau` |
| `ReplicatedStorage > Client > World > HouseBuilder` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseBuilder.luau` |
| `ReplicatedStorage > Client > World > HouseFacade` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseFacade.luau` |
| `ReplicatedStorage > Client > World > HouseGarden` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseGarden.luau` |
| `ReplicatedStorage > Client > World > HouseKit` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseKit.luau` |
| `ReplicatedStorage > Client > World > HouseStairs` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseStairs.luau` |
| `ReplicatedStorage > Client > World > HouseToggles` | ModuleScript | `src/ReplicatedStorage/Client/World/HouseToggles.luau` |
| `ReplicatedStorage > Client > World > LiveProps` | ModuleScript | `src/ReplicatedStorage/Client/World/LiveProps.luau` |
| `ReplicatedStorage > Client > World > LiveScreens` | ModuleScript | `src/ReplicatedStorage/Client/World/LiveScreens.luau` |
| `ReplicatedStorage > Client > World > MarketInterior` | ModuleScript | `src/ReplicatedStorage/Client/World/MarketInterior.luau` |
| `ReplicatedStorage > Client > World > PetRoam` | ModuleScript | `src/ReplicatedStorage/Client/World/PetRoam.luau` |
| `ReplicatedStorage > Client > World > Reflections` | ModuleScript | `src/ReplicatedStorage/Client/World/Reflections.luau` |
| `ReplicatedStorage > Client > World > ShopInteriors` | ModuleScript | `src/ReplicatedStorage/Client/World/ShopInteriors.luau` |
| `ReplicatedStorage > Client > World > ShopUI` | ModuleScript | `src/ReplicatedStorage/Client/World/ShopUI.luau` |
| `ReplicatedStorage > Client > World > SitAnimator` | ModuleScript | `src/ReplicatedStorage/Client/World/SitAnimator.luau` |
| `ReplicatedStorage > Client > World > StimulusScreen` | ModuleScript | `src/ReplicatedStorage/Client/World/StimulusScreen.luau` |
| `ReplicatedStorage > Client > World > TownArrival` | ModuleScript | `src/ReplicatedStorage/Client/World/TownArrival.luau` |
| `ReplicatedStorage > Client > World > TownAtmosphere` | ModuleScript | `src/ReplicatedStorage/Client/World/TownAtmosphere.luau` |
| `ReplicatedStorage > Client > World > TownClient` | ModuleScript | `src/ReplicatedStorage/Client/World/TownClient.luau` |
| `ReplicatedStorage > Client > World > TownEmotes` | ModuleScript | `src/ReplicatedStorage/Client/World/TownEmotes.luau` |
| `ReplicatedStorage > Client > World > TownFacades` | ModuleScript | `src/ReplicatedStorage/Client/World/TownFacades.luau` |
| `ReplicatedStorage > Client > World > TownFountainFx` | ModuleScript | `src/ReplicatedStorage/Client/World/TownFountainFx.luau` |
| `ReplicatedStorage > Client > World > TownGraphics` | ModuleScript | `src/ReplicatedStorage/Client/World/TownGraphics.luau` |
| `ReplicatedStorage > Client > World > TownGreenery` | ModuleScript | `src/ReplicatedStorage/Client/World/TownGreenery.luau` |
| `ReplicatedStorage > Client > World > TownHud` | ModuleScript | `src/ReplicatedStorage/Client/World/TownHud.luau` |
| `ReplicatedStorage > Client > World > TownPeople` | ModuleScript | `src/ReplicatedStorage/Client/World/TownPeople.luau` |
| `ReplicatedStorage > Client > World > TownPigeons` | ModuleScript | `src/ReplicatedStorage/Client/World/TownPigeons.luau` |
| `ReplicatedStorage > Client > World > TownPlazaFx` | ModuleScript | `src/ReplicatedStorage/Client/World/TownPlazaFx.luau` |
| `ReplicatedStorage > Client > World > TownStreetLife` | ModuleScript | `src/ReplicatedStorage/Client/World/TownStreetLife.luau` |
| `ReplicatedStorage > Client > World > TownTraffic` | ModuleScript | `src/ReplicatedStorage/Client/World/TownTraffic.luau` |
| `ReplicatedStorage > Client > World > Weather3D` | ModuleScript | `src/ReplicatedStorage/Client/World/Weather3D.luau` |
| `ReplicatedStorage > Client > World > WorldLink` | ModuleScript | `src/ReplicatedStorage/Client/World/WorldLink.luau` |
| `ReplicatedStorage > Shared > ArcadeConfig` | ModuleScript | `src/ReplicatedStorage/Shared/ArcadeConfig.luau` |
| `ReplicatedStorage > Shared > CarModels` | ModuleScript | `src/ReplicatedStorage/Shared/CarModels.luau` |
| `ReplicatedStorage > Shared > ChatTopics` | ModuleScript | `src/ReplicatedStorage/Shared/ChatTopics.luau` |
| `ReplicatedStorage > Shared > Config` | ModuleScript | `src/ReplicatedStorage/Shared/Config.luau` |
| `ReplicatedStorage > Shared > DVDMath` | ModuleScript | `src/ReplicatedStorage/Shared/DVDMath.luau` |
| `ReplicatedStorage > Shared > DeskRunnerLogic` | ModuleScript | `src/ReplicatedStorage/Shared/DeskRunnerLogic.luau` |
| `ReplicatedStorage > Shared > FairRides` | ModuleScript | `src/ReplicatedStorage/Shared/FairRides.luau` |
| `ReplicatedStorage > Shared > FoodModels` | ModuleScript | `src/ReplicatedStorage/Shared/FoodModels.luau` |
| `ReplicatedStorage > Shared > FoodRules` | ModuleScript | `src/ReplicatedStorage/Shared/FoodRules.luau` |
| `ReplicatedStorage > Shared > Formulas` | ModuleScript | `src/ReplicatedStorage/Shared/Formulas.luau` |
| `ReplicatedStorage > Shared > FriendMailRules` | ModuleScript | `src/ReplicatedStorage/Shared/FriendMailRules.luau` |
| `ReplicatedStorage > Shared > GarageLayout` | ModuleScript | `src/ReplicatedStorage/Shared/GarageLayout.luau` |
| `ReplicatedStorage > Shared > GardenSnapshot` | ModuleScript | `src/ReplicatedStorage/Shared/GardenSnapshot.luau` |
| `ReplicatedStorage > Shared > GraphicsQuality` | ModuleScript | `src/ReplicatedStorage/Shared/GraphicsQuality.luau` |
| `ReplicatedStorage > Shared > Greenery` | ModuleScript | `src/ReplicatedStorage/Shared/Greenery.luau` |
| `ReplicatedStorage > Shared > Lang > FR_Config` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_Config.luau` |
| `ReplicatedStorage > Shared > Lang > FR_House` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_House.luau` |
| `ReplicatedStorage > Shared > Lang > FR_HouseRooms` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_HouseRooms.luau` |
| `ReplicatedStorage > Shared > Lang > FR_HouseShop` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_HouseShop.luau` |
| `ReplicatedStorage > Shared > Lang > FR_HouseUI` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_HouseUI.luau` |
| `ReplicatedStorage > Shared > Lang > FR_Server` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_Server.luau` |
| `ReplicatedStorage > Shared > Lang > FR_StimuliLive` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_StimuliLive.luau` |
| `ReplicatedStorage > Shared > Lang > FR_StimuliMisc` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_StimuliMisc.luau` |
| `ReplicatedStorage > Shared > Lang > FR_StimuliText` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_StimuliText.luau` |
| `ReplicatedStorage > Shared > Lang > FR_UI` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_UI.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_Arcade` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_Arcade.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_House` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_House.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_LiveLofi` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_LiveLofi.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_Perf` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_Perf.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_PressDVD` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_PressDVD.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_Runner` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_Runner.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_SlotGarden` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_SlotGarden.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_Solo` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_Solo.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V8_UIShop` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V8_UIShop.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V91_FriendMail` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V91_FriendMail.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V91_Gear91` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V91_Gear91.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V91_House` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V91_House.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V92_Shop` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V92_Shop.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V93_UIFix` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V93_UIFix.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V93_World` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V93_World.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V94_Entry` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V94_Entry.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V94_Houses` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V94_Houses.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V94_Town` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V94_Town.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V95_Garden3D` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V95_Garden3D.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V95_Setup3D` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V95_Setup3D.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V95_SetupData` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V95_SetupData.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V96_Fixes` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V96_Fixes.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V96_Garage` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V96_Garage.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V96_Place` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V96_Place.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V96_Shops` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V96_Shops.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V97_Buildings` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V97_Buildings.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V97_Plaza` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V97_Plaza.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V97_Vehicles` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V97_Vehicles.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Cars` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Cars.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Catalog` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Catalog.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_City` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_City.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Desk` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Desk.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Fair` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Fair.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Garden` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Garden.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_House` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_House.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Market` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Market.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Realism` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Realism.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V98_Seat` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V98_Seat.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Arcade` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Arcade.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Cosmos` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Cosmos.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Fun` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Fun.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Gear` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Gear.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_House` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_House.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_House3D` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_House3D.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Lead` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Lead.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Live` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Live.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Mail` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Mail.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_Runner` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_Runner.luau` |
| `ReplicatedStorage > Shared > Lang > FR_V9_UX` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/FR_V9_UX.luau` |
| `ReplicatedStorage > Shared > Lang > README` | ModuleScript | `src/ReplicatedStorage/Shared/Lang/README.luau` |
| `ReplicatedStorage > Shared > Locale` | ModuleScript | `src/ReplicatedStorage/Shared/Locale.luau` |
| `ReplicatedStorage > Shared > NPCModels` | ModuleScript | `src/ReplicatedStorage/Shared/NPCModels.luau` |
| `ReplicatedStorage > Shared > Net` | ModuleScript | `src/ReplicatedStorage/Shared/Net.luau` |
| `ReplicatedStorage > Shared > NumberFormatter` | ModuleScript | `src/ReplicatedStorage/Shared/NumberFormatter.luau` |
| `ReplicatedStorage > Shared > Signal` | ModuleScript | `src/ReplicatedStorage/Shared/Signal.luau` |
| `ReplicatedStorage > Shared > VehicleModels` | ModuleScript | `src/ReplicatedStorage/Shared/VehicleModels.luau` |
| `ReplicatedStorage > Shared > WorldLayout` | ModuleScript | `src/ReplicatedStorage/Shared/WorldLayout.luau` |
| `ServerScriptService > Main` | Script | `src/ServerScriptService/Main.server.luau` |
| `ServerScriptService > Services > AchievementService` | ModuleScript | `src/ServerScriptService/Services/AchievementService.luau` |
| `ServerScriptService > Services > Arcade > SoloGames` | ModuleScript | `src/ServerScriptService/Services/Arcade/SoloGames.luau` |
| `ServerScriptService > Services > CarService` | ModuleScript | `src/ServerScriptService/Services/CarService.luau` |
| `ServerScriptService > Services > CasinoService` | ModuleScript | `src/ServerScriptService/Services/CasinoService.luau` |
| `ServerScriptService > Services > ChatService` | ModuleScript | `src/ServerScriptService/Services/ChatService.luau` |
| `ServerScriptService > Services > CosmeticService` | ModuleScript | `src/ServerScriptService/Services/CosmeticService.luau` |
| `ServerScriptService > Services > DVDService` | ModuleScript | `src/ServerScriptService/Services/DVDService.luau` |
| `ServerScriptService > Services > DailyRewardService` | ModuleScript | `src/ServerScriptService/Services/DailyRewardService.luau` |
| `ServerScriptService > Services > DataService` | ModuleScript | `src/ServerScriptService/Services/DataService.luau` |
| `ServerScriptService > Services > DebugService` | ModuleScript | `src/ServerScriptService/Services/DebugService.luau` |
| `ServerScriptService > Services > EventService` | ModuleScript | `src/ServerScriptService/Services/EventService.luau` |
| `ServerScriptService > Services > FoodService` | ModuleScript | `src/ServerScriptService/Services/FoodService.luau` |
| `ServerScriptService > Services > FriendMailService` | ModuleScript | `src/ServerScriptService/Services/FriendMailService.luau` |
| `ServerScriptService > Services > GameService` | ModuleScript | `src/ServerScriptService/Services/GameService.luau` |
| `ServerScriptService > Services > GardenService` | ModuleScript | `src/ServerScriptService/Services/GardenService.luau` |
| `ServerScriptService > Services > HouseService` | ModuleScript | `src/ServerScriptService/Services/HouseService.luau` |
| `ServerScriptService > Services > InteractService` | ModuleScript | `src/ServerScriptService/Services/InteractService.luau` |
| `ServerScriptService > Services > LeaderboardService` | ModuleScript | `src/ServerScriptService/Services/LeaderboardService.luau` |
| `ServerScriptService > Services > LootService` | ModuleScript | `src/ServerScriptService/Services/LootService.luau` |
| `ServerScriptService > Services > MinigameService` | ModuleScript | `src/ServerScriptService/Services/MinigameService.luau` |
| `ServerScriptService > Services > MonetizationService` | ModuleScript | `src/ServerScriptService/Services/MonetizationService.luau` |
| `ServerScriptService > Services > QuestService` | ModuleScript | `src/ServerScriptService/Services/QuestService.luau` |
| `ServerScriptService > Services > RateLimiter` | ModuleScript | `src/ServerScriptService/Services/RateLimiter.luau` |
| `ServerScriptService > Services > ThemeService` | ModuleScript | `src/ServerScriptService/Services/ThemeService.luau` |
| `ServerScriptService > Services > World > TownBuildings` | ModuleScript | `src/ServerScriptService/Services/World/TownBuildings.luau` |
| `ServerScriptService > Services > World > TownEntrance` | ModuleScript | `src/ServerScriptService/Services/World/TownEntrance.luau` |
| `ServerScriptService > Services > World > TownFair` | ModuleScript | `src/ServerScriptService/Services/World/TownFair.luau` |
| `ServerScriptService > Services > World > TownKit` | ModuleScript | `src/ServerScriptService/Services/World/TownKit.luau` |
| `ServerScriptService > Services > World > TownMap` | ModuleScript | `src/ServerScriptService/Services/World/TownMap.luau` |
| `ServerScriptService > Services > World > TownMarket` | ModuleScript | `src/ServerScriptService/Services/World/TownMarket.luau` |
| `ServerScriptService > Services > World > TownNature` | ModuleScript | `src/ServerScriptService/Services/World/TownNature.luau` |
| `ServerScriptService > Services > World > TownPlaza` | ModuleScript | `src/ServerScriptService/Services/World/TownPlaza.luau` |
| `ServerScriptService > Services > World > TownShops` | ModuleScript | `src/ServerScriptService/Services/World/TownShops.luau` |
| `ServerScriptService > Services > World > TownStreets` | ModuleScript | `src/ServerScriptService/Services/World/TownStreets.luau` |
| `ServerScriptService > Services > World > TownVehicles` | ModuleScript | `src/ServerScriptService/Services/World/TownVehicles.luau` |
| `ServerScriptService > Services > WorldService` | ModuleScript | `src/ServerScriptService/Services/WorldService.luau` |
| `StarterPlayer > StarterPlayerScripts > ClientMain` | LocalScript | `src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau` |

⚠️ `Main` doit être un **Script**, `ClientMain` un **LocalScript**, tout le reste des **ModuleScript**.
⚠️ Un nouveau Script/ModuleScript contient déjà `print("Hello world!")` ou `local module = {} return module` : **remplace tout**.
💡 Le nom d'un module du dossier `Stimuli` doit être **exactement** le nom de sa Feature (voir `Config.Upgrades`), sinon il ne sera jamais lancé (aucune erreur : il est simplement ignoré).

Ensuite : étapes 4 à 6 de la méthode A.

---

## 🔌 RemoteEvents / RemoteFunctions

**Rien à créer à la main.** Au démarrage, `Main` appelle `Net.Setup()` (`Shared > Net`) qui crée `ReplicatedStorage > Remotes` avec tous les remotes ci-dessous. Le client les récupère avec `Net.Event("Nom")` / `Net.Function("Nom")`.
C → S = le client **demande**, le serveur valide tout. S → C = le serveur **informe**. Le serveur n'appelle **jamais** `InvokeClient`.

### RemoteEvents

| Nom | Rôle (sens, arguments) |
|---|---|
| `ClientReady` | C -> S () : l'interface est prête, envoie-moi tout |
| `Click` | C -> S () : un clic sur le bouton |
| `StateUpdate` | S -> C (state) : état complet du joueur |
| `StateTick` | S -> C (tick) : petite mise à jour fréquente (Dopamine, clics...) entre deux états complets |
| `Notify` | S -> C (payload) : succès, quêtes, bonus, jackpot, détox... |
| `DVDSetup` | S -> C ({ Logos = { params... } }) : trajectoires des logos DVD |
| `DVDResize` | C -> S (w, h) : taille d'un logo à l'écran (fraction de l'écran) |
| `DVDClick` | C -> S (index) : clic sur le logo numéro `index` |
| `DVDCorner` | C -> S (index, k) : le logo `index` a touché un coin au rebond k |
| `Spawn` | S -> C (info) : un objet à cliquer apparaît (étoile, éclair, notif, mail) |
| `SpawnClick` | C -> S (id) : le joueur a cliqué cet objet |
| `Interact` | C -> S (kind, arg) : papier bulle, moulin, titre du fil d'actu, presse |
| `EventUpdate` | S -> C (rush) : début / fin d'un Dopamine Rush |
| `LeaderboardUpdate` | S -> C (top) : top du classement |
| `ArcadeEvent` | S <-> C (kind, payload) : arcade en temps réel (invitations, coups des duels...) |
| `FriendMailEvent` | S -> C ("New", mail filtré) : un mail d'ami Roblox arrive (FriendMailService) |
| `WorldEvent` | S -> C (kind, payload) : 🚶 Dopamine Town (maisons, "j'aime", messages) (WorldService) |

### RemoteFunctions (C → S, avec réponse)

| Nom | Rôle (arguments -> réponse) |
|---|---|
| `BuyUpgrade` | C -> S (upgradeId) -> (succès, message) |
| `ClaimDaily` | C -> S () -> (succès, message) |
| `SetSetting` | C -> S (nom, valeur) -> succès |
| `CasinoSpin` | C -> S () -> (succès, résultat \| message) : tour GRATUIT (1 jeton) de la machine chanceuse |
| `OpenChest` | C -> S () -> (succès, résultat \| message) |
| `ItemShop` | C -> S ("buy" \| "equip" \| "unequip", cosmeticId) -> (succès, message) |
| `ThemeShop` | C -> S ("buy" \| "equip", themeId) -> (succès, message) |
| `House` | C -> S (action, argument) -> (succès, message) : maison (achats, papier peint, sol, disposition) |
| `Garden` | C -> S (action, argument) -> (succès, résultat \| message) : jardin de Dopamine |
| `Arcade` | C -> S (action, argument) -> (succès, résultat \| message) : mini-jeux, tickets, duels |
| `FilterText` | C -> S (purpose "Live" \| "Mail", texte) -> (succès, { Text, Topics } \| message) : texte tapé, filtré par Roblox |
| `FriendMail` | C -> S (action, argument) -> (succès, résultat \| message, état?) : mails entre amis Roblox (FriendMailService) |
| `World` | C -> S (action, argument) -> (succès, résultat \| message) : 🚶 Dopamine Town (entrer, visiter, s'asseoir, j'aime) (WorldService) |
| `Car` | C -> S (action, a, b) -> (succès, message, extra?) : 🚗 voitures (acheter, couleur, choisir, garage, conduire, klaxon) (CarService) |
| `Food` | C -> S ("buy", foodId, stallId \| "bite") -> (succès, message, manquant?) : 🍦 nourriture de Dopamine Town (FoodService, v9.8) |
| `DebugCommand` | C -> S (commande, argument) -> (succès, message) : UNIQUEMENT dans Studio |

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
