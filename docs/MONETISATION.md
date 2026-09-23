# 💰 Monétisation et 📣 promotion

## Game Passes (achat unique, permanent)

| Game Pass | Effet | Prix conseillé |
|---|---|---|
| **x2 Dopamine** | Double tous les gains, pour toujours | 199 R$ |
| **Auto-Clic VIP** | Clique automatiquement 5 fois/s (même limite anti-triche) | 299 R$ |
| **Combo Master** | Le combo descend 2 fois moins vite, maximum x4 | 149 R$ |
| **Chasseur d'or** | Les objets dorés apparaissent 2 fois plus souvent | 149 R$ |
| **Skins de bouton** | Bouton en forme de cœur, pizza, planète… (cosmétique) | 49–99 R$ |
| **VIP** | Tag de chat, couleur de nom, +10 % de gains, logo DVD doré | 399 R$ |

## Developer Products (achats répétables)

| Produit | Effet | Prix conseillé |
|---|---|---|
| **Boost x2 (15 min)** | Double les gains pendant 15 minutes | 49 R$ |
| **Boost x3 (15 min)** | Triple les gains pendant 15 minutes | 99 R$ |
| **Pack de Dopamine** | = 1 heure de production (adapté à la progression) | 25–199 R$ |
| **Rush instantané** | Lance un Dopamine Rush pour TOUT le serveur (très social !) | 79 R$ |
| **Coin parfait garanti** | Le logo DVD touche un coin dans les 10 s | 99 R$ |

## Comment les brancher dans le code

1. Crée le Game Pass / Developer Product sur le **Creator Dashboard** et note son ID.
2. Crée un nouveau `ModuleScript` **`MonetizationService`** dans `ServerScriptService > Services` et ajoute son nom dans la liste `ORDER` de `Main`.
3. **Game Pass** : dans `PlayerReady`, vérifie avec `MarketplaceService:UserOwnsGamePassAsync(player.UserId, ID)` (dans un `pcall`) et écoute `PromptGamePassPurchaseFinished`.
4. **Developer Product** : définis `MarketplaceService.ProcessReceipt` (une seule fois dans tout le jeu !) ; donne l'objet, **sauvegarde**, puis renvoie `Enum.ProductPurchaseDecision.PurchaseGranted`.
5. Pour un multiplicateur : ajoute un paramètre à `Formulas.ComputeStats` (comme `eventMultiplier`) et passe-le depuis `GameService:GetStats`.
6. Côté client : un bouton « 🛒 BOUTIQUE ROBUX » qui appelle `MarketplaceService:PromptGamePassPurchase` / `PromptProductPurchase`.

⚠️ Ne donne **jamais** un avantage payé depuis le client : c'est le serveur qui vérifie l'achat.

## Autres idées de revenus

- **Publicités récompensées** (Rewarded Video Ads, si disponible dans ton pays) : « Regarde une pub pour un boost x2 de 10 min ».
- **Premium Payouts** : ajoute un petit bonus pour les abonnés Roblox Premium (`player.MembershipType`), ça augmente leur temps de jeu, donc tes revenus.
- **Battle Pass saisonnier** avec des récompenses cosmétiques.

---

## 📣 Promotion

- **Icône et miniatures** : couleurs néon, gros bouton, texte court (« CLIQUE ! », « 1 000 000 000 DOPAMINE »). Teste plusieurs versions.
- **Titre avec des mises à jour** : `[🌀 UPDATE 2] Dopamine Clicker` (les joueurs adorent les mises à jour).
- **Description** avec des mots-clés : clicker, simulator, idle, tapping, satisfying.
- **Codes promo** (`/code DOPAMINE`) partagés sur Discord, TikTok, YouTube Shorts.
- **Groupe Roblox** avec bonus pour les membres (+10 %) : ça crée une communauté.
- **Serveur Discord** : annonces de mises à jour, sondages, captures du coin parfait.
- **TikTok / Shorts** : filme les jackpots du logo DVD (le concept est très « viral »).
- **Événements réguliers** (week-end x2, Halloween, Noël) pour faire revenir les joueurs.
- **Publicités Roblox (Ads Manager)** avec un petit budget au lancement, et **Sponsored Experiences**.
- **Badges** pour les succès importants (ils apparaissent sur les profils des joueurs).
- **Invitations d'amis** : bonus quand un ami rejoint (`SocialService:PromptGameInvite`).

## Idées pour les prochaines mises à jour

- Nouveaux mondes après plusieurs rebirths (thèmes, nouveaux générateurs).
- Animaux de compagnie (« pets ») qui boostent les gains.
- Mini-jeux : attraper des neurones qui tombent, roue de la chance quotidienne.
- Classements hebdomadaires avec récompenses.
- Échanges ou cadeaux entre joueurs.
