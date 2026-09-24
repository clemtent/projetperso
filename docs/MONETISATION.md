# 💰 Monétisation et 📣 promotion

## ✅ Ce qui est déjà codé (v3)

La **💎 Boutique Robux** est prête : il suffit de coller tes IDs dans `ReplicatedStorage > Shared > Config`, section `Config.Monetization` (un ID à `0` = offre cachée).

| Offre | Type Roblox | Champ à remplir | Effet |
|---|---|---|---|
| 🚀 Dopamine x10 | Game Pass | `GamePasses > X10 > GamePassId` | Tous les gains x10, pour toujours |
| ⚡ Dopamine x2 | Game Pass | `GamePasses > X2 > GamePassId` | Tous les gains x2, pour toujours |
| 🤖 Auto-clic | Game Pass | `GamePasses > AutoClick > GamePassId` | 5 clics/s automatiques |
| 👑 VIP | Game Pass | `GamePasses > VIP > GamePassId` | +25 % de gains + thèmes Premium (Bonbon, Synthwave) |
| 💧💦🌊 Packs de Dopamine | Developer Product | `Products > PackS / PackM / PackL > ProductId` | 10 min / 1 h / 8 h de production |
| ⏱️🔥 Boosts | Developer Product | `Products > Boost2 / Boost5 > ProductId` | x2 pendant 15 min / x5 pendant 10 min |
| 🎉 Rush pour tous | Developer Product | `Products > ServerRush > ProductId` | Dopamine Rush pour tout le serveur |
| 🎨 Thèmes | Game Pass (optionnel) | `Config.Themes > <thème> > GamePassId` | Débloque ce thème avec des Robux |

### Où trouver les IDs
1. Publie le jeu, puis va sur **create.roblox.com > Créations > ton expérience > Monétisation**.
2. **Passes** : crée un pass (image + nom + prix), mets-le **en vente**, copie son **ID** (dans l'URL ou « Copier l'ID de l'élément »).
3. **Developer Products** : crée un produit, fixe le prix, copie son **ID**.
4. Colle chaque ID à la place du `0` correspondant, puis republie.

Le serveur (`MonetizationService`) vérifie la possession des passes, traite les achats de produits avec `ProcessReceipt` (jamais deux fois le même achat) et sauvegarde avant de confirmer. Les prix affichés viennent de Roblox (`GetProductInfo`).

> ⚠️ Dans Studio, les achats sont des **achats de test** (aucun Robux dépensé) : parfait pour vérifier.

## ⚠️ À lire avant de vendre quoi que ce soit : casino, coffres et règles Roblox

Dans la version actuelle :

- la **🎰 machine à sous** (`CasinoService`) et le **📦 coffre mystère** (`LootService`) fonctionnent **uniquement avec la Dopamine du jeu** : on ne peut pas y miser, ni les acheter, ni les recharger avec des Robux ;
- la Dopamine elle-même ne s'achète pas.

**Dès que tu vends de la Dopamine, des boosts de gains ou quoi que ce soit qui s'échange contre de la Dopamine** (packs, x2, auto-clic…), la Dopamine devient indirectement payante, et donc :

1. **Le casino se désactive automatiquement** dès qu'un ID Robux est rempli (`Config.Monetization.DisableCasinoWhenSelling = true`) : le serveur refuse les mises et la machine affiche « 🚧 Fermé ». Les règles de Roblox interdisent les jeux d'argent qui utilisent des Robux ou des objets ayant une valeur réelle, même indirectement.
2. **Affiche les probabilités des coffres** : un coffre mystère obtenu grâce à une ressource payante devient un « objet aléatoire payant » (paid random item / loot box). Roblox exige alors que **les chances de chaque récompense soient visibles avant l'ouverture**. Les chances (Commun 60 %, Rare 25 %, Épique 12 %, Légendaire 3 %) sont **affichées en jeu** via le bouton « ? » du coffre. Les coffres ne s'achètent pas avec des Robux (ils se rechargent avec le temps de jeu). Ne vends jamais de coffres directement contre des Robux sans cet affichage (et vérifie les restrictions par pays dans la politique Roblox).
3. **Remplis honnêtement le questionnaire de maturité** (Creator Dashboard > ton expérience > **Maturity & Compliance / Questionnaire**) : déclare la machine à sous (même en monnaie fictive), les coffres aléatoires et tout achat. Une déclaration fausse peut entraîner la modération de l'expérience.

Consulte toujours la version à jour des **Roblox Community Standards**, des **Terms of Use** et des règles sur les **paid random items** : elles changent régulièrement.

---

## Game Passes (achat unique, permanent)

| Game Pass | Effet | Prix indicatif | Remarque |
|---|---|---|---|
| **x2 Dopamine** | Double tous les gains, pour toujours | 199 R$ | ⚠️ Rend la Dopamine payante → casino OFF + chances des coffres visibles |
| **Combo Master** | Le combo descend 2 fois moins vite, maximum x4 | 149 R$ | Idem |
| **Chasseur d'étoiles** | Étoiles dorées / éclairs 2 fois plus fréquents | 149 R$ | Idem |
| **Chapeaux exclusifs** | Chapeaux et skins de bouton réservés (purement cosmétiques) | 49–99 R$ | Cosmétique sans avantage : option la plus sûre |
| **VIP** | Tag de chat, couleur de nom, logo DVD doré | 299 R$ | Sans bonus de gains = pas de souci casino |
| **Écran de veille premium** | Thèmes de stimuli alternatifs (néon bleu, rétro…) | 99 R$ | Cosmétique |

## Developer Products (achats répétables)

| Produit | Effet | Prix indicatif | Remarque |
|---|---|---|---|
| **Boost x2 (15 min)** | Double les gains pendant 15 minutes | 49 R$ | ⚠️ Casino OFF + chances des coffres visibles |
| **Pack de Dopamine** | = 1 heure de production (via `Formulas.ScaledReward`) | 25–199 R$ | ⚠️ Idem |
| **Rush pour tout le serveur** | Lance un Dopamine Rush pour TOUS (très social) | 79 R$ | ⚠️ Idem (boost de gains) |
| **Coin parfait garanti** | Un logo DVD touche un coin dans les 10 s | 99 R$ | ⚠️ Idem (jackpot = Dopamine) |

💡 La voie la plus simple et la plus sûre : **uniquement du cosmétique** (chapeaux, skins, thèmes). Dans ce cas, le casino et les coffres peuvent rester tels quels.

## Comment les brancher dans le code

1. Crée le Game Pass / Developer Product sur le **Creator Dashboard** et note son ID (par ex. dans une nouvelle section `Config.Monetization`).
2. Crée un `ModuleScript` **`MonetizationService`** dans `ServerScriptService > Services` et ajoute son nom dans la liste `ORDER` de `Main` (il recevra `Init(services)`, `Start()`, `PlayerReady(player, data)`).
3. **Game Pass** : dans `PlayerReady`, vérifie `MarketplaceService:UserOwnsGamePassAsync(player.UserId, ID)` (dans un `pcall`) et écoute `MarketplaceService.PromptGamePassPurchaseFinished`.
4. **Developer Product** : définis `MarketplaceService.ProcessReceipt` (**une seule fois** dans tout le jeu) ; donne l'objet, **sauvegarde** (`DataService:SaveAsync`), puis renvoie `Enum.ProductPurchaseDecision.PurchaseGranted` (sinon `NotProcessedYet`). Garde la liste des `PurchaseId` déjà traités pour ne jamais donner deux fois.
5. Pour un multiplicateur de gains : ajoute un facteur dans `Formulas.ComputeStats` (comme le multiplicateur d'événement) et passe-le depuis `GameService`. Relance `python3 tests/run_tests.py`.
6. Cosmétique payant : ajoute l'objet dans `Config.Cosmetics` avec un champ (ex. `GamePass = ID`) et fais vérifier la possession par `CosmeticService` avant `buy` / `equip`.
7. Côté client : un bouton « 🛒 Robux » (par ex. dans le panneau `ItemShop`) qui appelle `MarketplaceService:PromptGamePassPurchase` / `PromptProductPurchase`.

⚠️ Ne donne **jamais** un avantage payé sur simple demande du client : c'est le serveur qui vérifie l'achat.

## Autres idées de revenus

- **Publicités récompensées** (Rewarded Video Ads, selon disponibilité) : « Regarde une pub pour un boost x2 de 10 min » (même règle : c'est un boost de gains).
- **Premium Payouts** : un petit bonus cosmétique pour les abonnés Roblox Premium (`player.MembershipType`) augmente leur temps de jeu, donc tes revenus.
- **Pass saisonnier** avec des récompenses **cosmétiques** (chapeaux, skins de bouton).

---

## 📣 Promotion

- **Icône et miniatures** : montre le contraste « écran vide » vs « écran surchargé » ; texte court (« CLIQUE. ENCORE. »). Teste plusieurs versions (A/B testing des miniatures).
- **Titre avec des mises à jour** : `[🌊 v2] Dopamine Clicker`.
- **Description** avec des mots-clés : clicker, idle, satisfying, incremental, simulator.
- **Codes promo** partagés sur Discord / TikTok / YouTube Shorts (à coder : un RemoteFunction validé côté serveur).
- **Groupe Roblox** avec un bonus cosmétique pour les membres.
- **TikTok / Shorts** : filme la progression de l'écran vide à l'écran saturé, le jackpot du coin DVD, la cinématique de l'océan.
- **Événements** réguliers (week-end Rush, Halloween, Noël) pour faire revenir les joueurs.
- **Publicités Roblox (Ads Manager)** avec un petit budget au lancement.
- **Badges** pour les grands succès (première visite à l'océan, coin parfait).
- **Invitations d'amis** : `SocialService:PromptGameInvite`.

## Idées pour les prochaines mises à jour

- Nouveaux stimuli (voir « Ajouter un nouveau stimulus » dans `docs/INSTALLATION.md`) : aquarium, file de chats, horloge qui fond…
- Stimuli exclusifs débloqués après plusieurs visites à l'océan.
- Classements hebdomadaires.
- Afficher les probabilités des coffres et du casino directement en jeu (utile même sans monétisation).
