# 🧠 Dopamine Clicker

Un jeu Roblox de type **clicker**, style néon / cyberpunk / arcade.
Clique sur le gros bouton, gagne de la **Dopamine**, achète des améliorations, attrape le logo DVD… et vise le **COIN PARFAIT** 📀.

> Tout le code est en **Luau**, commenté en français, modulaire et **100 % validé côté serveur** (anti-triche).

---

## 🚀 Démarrage rapide (le plus simple)

1. Télécharge [`build/DopamineClicker.rbxlx`](build/DopamineClicker.rbxlx).
2. Double-clique dessus : il s'ouvre dans **Roblox Studio** avec tous les scripts déjà en place.
3. **Fichier > Publier sur Roblox** (obligatoire pour la sauvegarde).
4. **Accueil > Paramètres du jeu > Sécurité** : active **« Enable Studio Access to API Services »**.
5. Clique sur **Play** ▶️.

Les autres méthodes (Rojo ou copier-coller à la main) sont décrites dans [`docs/INSTALLATION.md`](docs/INSTALLATION.md).

---

## 🗂️ Arborescence dans l'Explorer de Roblox Studio

```
📁 ReplicatedStorage
│   📁 Shared                      (code partagé serveur + client)
│   │   📜 Config                  ModuleScript  ← TOUTE la config du jeu
│   │   📜 Formulas                ModuleScript  ← calculs (coûts, gains, combo)
│   │   📜 NumberFormatter         ModuleScript  ← 1K, 1M, 1B, 1T...
│   │   📜 Net                     ModuleScript  ← crée/récupère les Remotes
│   │   📜 DVDMath                 ModuleScript  ← trajectoire du logo DVD
│   │   📜 Signal                  ModuleScript  ← petits événements
│   📁 Client                      (interface, uniquement côté joueur)
│   │   📜 Theme                   ModuleScript  ← couleurs, polices
│   │   📜 UIUtil                  ModuleScript  ← création d'UI + animations
│   │   📜 Interface               ModuleScript  ← ScreenGui responsive (UIScale)
│   │   📜 ClientState             ModuleScript  ← état reçu + prédiction des clics
│   │   📜 SoundManager            ModuleScript  ← sons et musique
│   │   📜 Effects                 ModuleScript  ← "+X", particules, confettis
│   │   📁 Components
│   │   │   📜 Background          ModuleScript  ← fond dégradé animé
│   │   │   📜 HUD                 ModuleScript  ← compteurs du haut
│   │   │   📜 Clicker             ModuleScript  ← gros bouton + combo
│   │   │   📜 Shop                ModuleScript  ← boutique
│   │   │   📜 SideMenu            ModuleScript  ← menu de gauche
│   │   │   📜 PanelManager        ModuleScript  ← fenêtres pop-up
│   │   │   📜 Notifications       ModuleScript  ← bandeaux + réactions
│   │   │   📜 DVDLogo             ModuleScript  ← logo qui rebondit
│   │   │   📜 GoldenObject        ModuleScript  ← objet doré
│   │   │   📁 Panels
│   │   │       📜 Quests          ModuleScript
│   │   │       📜 Achievements    ModuleScript
│   │   │       📜 Rebirth         ModuleScript
│   │   │       📜 Daily           ModuleScript
│   │   │       📜 Leaderboard     ModuleScript
│   │   │       📜 Settings        ModuleScript
│   📁 Remotes                     ⚙️ créé AUTOMATIQUEMENT par le serveur
│
📁 ServerScriptService
│   📄 Main                        Script        ← point d'entrée serveur
│   📁 Services
│       📜 DataService             ModuleScript  ← sauvegarde DataStore
│       📜 GameService             ModuleScript  ← clics, achats, passif, rebirth
│       📜 AchievementService      ModuleScript
│       📜 QuestService            ModuleScript
│       📜 DailyRewardService      ModuleScript
│       📜 EventService            ModuleScript  ← Dopamine Rush + objet doré
│       📜 DVDService              ModuleScript  ← validation du coin parfait
│       📜 LeaderboardService      ModuleScript  ← classement global
│       📜 RateLimiter             ModuleScript  ← anti-spam
│       📜 DebugService            ModuleScript  ← commandes de test (Studio seulement)
│
📁 StarterPlayer
    📁 StarterPlayerScripts
        📄 ClientMain              LocalScript   ← point d'entrée client
```

Dans le dépôt, chaque fichier correspond à un objet :
`*.server.luau` = **Script**, `*.client.luau` = **LocalScript**, `*.luau` = **ModuleScript** (dans `src/`).

---

## 🏗️ Architecture

```
          CLIENT (LocalScript + modules)                          SERVEUR (Script + services)
┌──────────────────────────────────────────┐          ┌──────────────────────────────────────────┐
│ Affiche l'interface, joue sons/effets    │  Click   │ GameService : limite 20 clics/s, combo,  │
│ Prédit le "+X" pour un retour instantané │ ───────▶ │ calcule le gain, ajoute la Dopamine      │
│                                          │ BuyUpgrade│ Vérifie prix + argent, applique l'achat │
│ Ne décide JAMAIS d'un gain               │ ───────▶ │                                          │
│                                          │          │ Boucle passive (Dopamine/s)              │
│ ClientState : se recale sur le serveur   │StateUpdate│ Succès, quêtes, événements, DVD         │
│                                          │ ◀─────── │ DataService : sauvegarde (retry, auto)   │
└──────────────────────────────────────────┘          └──────────────────────────────────────────┘
```

- **Le serveur est la seule source de vérité** : le client envoie des *demandes* (clic, achat, rebirth…), le serveur valide tout (types, montants, temps de recharge, limite de clics/s).
- **Prédiction côté client** : le « +X » et le compteur montent instantanément, puis se recalent sur la valeur du serveur (aucune triche possible, aucune latence ressentie).
- **Logo DVD déterministe** : le serveur choisit la trajectoire, le client l'affiche. Le serveur **recalcule** lui-même si un coin a vraiment été touché avant de donner le jackpot.
- **Services injectés** : `Main` charge les services dans l'ordre et donne à chacun la liste des autres (`Init(services)`), ce qui évite les `require` circulaires.
- **Interface 100 % en code** : responsive grâce à une « toile virtuelle » 1280×720 + `UIScale` + `UIAspectRatioConstraint`.

---

## 🎮 Fonctionnalités

| Système | Détails |
|---|---|
| Gros bouton | Squish/rebond (TweenService), « +X » flottant aléatoire, particules, son qui monte avec le combo |
| Combo | Jauge 0–100 remplie en cliquant vite (> 5 clics/s), jusqu'à **x3** |
| Boutique | 6 améliorations de clic, 7 générateurs passifs, 4 multiplicateurs globaux ; modes **x1 / x10 / MAX** |
| Logo DVD | Rebondit, change de couleur, cliquable (bonus), **jackpot** au coin parfait (confettis, son, message) |
| Rebirth | Remise à zéro contre **+50 %** de gains permanents par rebirth |
| Succès | 19 succès avec récompenses + **+2 %** de gains permanents chacun |
| Quêtes | 3 quêtes actives, remplacées automatiquement, récompenses adaptées à ta progression |
| Cadeau quotidien | Série de 7 jours, heure du serveur (non trichable) |
| Événements | **Dopamine Rush** x2 pendant 30 s (tout le serveur), **objet doré** qui disparaît vite |
| Classement | Top 10 mondial (OrderedDataStore) + leaderstats |
| Paramètres | Son, musique, particules (sauvegardés) |

Toutes les valeurs se modifient dans **`ReplicatedStorage > Shared > Config`**.

---

## 📚 Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) — mise en place pas à pas, liste des Remotes, sons, logo.
- [`docs/TESTS.md`](docs/TESTS.md) — checklist de test dans Studio + erreurs courantes.
- [`docs/MONETISATION.md`](docs/MONETISATION.md) — Game Passes, boosts, idées de promotion.
