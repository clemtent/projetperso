# 💰 Économie de Dopamine Clicker (v9.3)

Retour du joueur : « trop facile, rien ne coûte assez cher, et à partir de la 3e visite à l'océan ça va beaucoup trop vite ; trop de choses débloquées dès le début ».

Tous les chiffres ci-dessous viennent du **simulateur** `tests/economy_sim.luau`, qui joue avec les vrais modules `Config` / `Formulas` (voir [`docs/TESTS.md`](TESTS.md) pour le lancer et savoir ce qu'il simule). Le joueur simulé clique à 6 clics/s pendant 75 % du temps avec le combo, attrape les bonus, cueille le jardin, ouvre les coffres, fait des quêtes, achète ce qui se rembourse le plus vite (améliorations, maison, cosmétiques) et va à l'océan dès que possible.

## Avant / après : minutes de jeu actif (joueur actif, **sans Robux**)

| Visite à l'océan | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | R10 |
|---|---|---|---|---|---|---|---|---|---|---|
| **Avant** : durée de la partie | 35 | 3 | 2 | 2 | 2 | 0,5 | 1 | 1 | 1 | 1 |
| **Avant** : cumul | 35 | 37 | 40 | 42 | 43 | 43 | 45 | 45 | 46 | **47 min** |
| **Après** : durée de la partie | 57 | 66 | 88 | 107 | 108 | 110 | 123 | 151 | 155 | 158 |
| **Après** : cumul | 57 | 122 | 210 | 317 | 425 | 534 | 657 | 809 | 964 | **1 122 min (18 h 40)** |
| Objectif | 45–60 | 60–75 | 75–90 | ≥ R3 | 90–120 | ≥ R5 | ≥ R6 | ≥ 150 | ≥ R8 | ≥ R9 |

Chaque partie dure maintenant au moins autant que la précédente. Avec 3 h de jeu par jour (et les gains hors-ligne), la 10e visite arrive le **6e jour** (avant : au bout de 47 minutes).

### Avec des Robux

| Profil | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | R10 | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| x2 + VIP + auto-clic, **avant** | 10 | 1 | 1 | 0,5 | 1 | 0,5 | 0,5 | 0,5 | 0,5 | 0,5 | 14 min |
| x2 + VIP + auto-clic, **après** | 19 | 25 | 30 | 39 | 36 | 42 | 42 | 45 | 70 | 57 | 6 h 45 |
| Tous les Game Passes (x10 compris), **avant** | < 1 | < 1 | < 1 | < 1 | < 1 | < 1 | < 1 | < 1 | < 1 | < 1 | 2 min |
| Tous les Game Passes (x10 compris), **après** | 3 | 6 | 3 | 5 | 4 | 6 | 5 | 5 | 9 | 7 | 54 min |

Les Game Passes restent très intéressants (environ 3x plus rapide avec x2 + VIP + auto-clic), mais la courbe garde sa forme : les parties s'allongent toujours avec les visites. Les multiplicateurs vendus (x2, x10, VIP x1,25) n'ont **pas** été touchés : ce qui a été acheté reste vrai. Les packs de Dopamine (10 min / 1 h / 8 h de production) et les boosts sont inchangés : ils valent des secondes de production, donc ils suivent tout seuls la nouvelle économie ; ils font gagner du temps une fois, sans raccourcir les parties suivantes.

## Gains à quelques moments clés (joueur actif, sans Robux)

| Moment | Avant | Après |
|---|---|---|
| 10 min | 301 /s | 910 /s (le début est plus généreux) |
| 20 min | 762 /s | 25 K/s |
| 30 min | 20,8 K/s | 104 K/s |
| Fin de la 1re partie | 39 M/s (à 35 min, x25 000 en 9 min) | ~5 M/s (à 57 min, x50 en 25 min) |
| Début de la 2e partie (+1 min) | ~2 K/s, puis R2 en 3 min | ~3 K/s, puis R2 en 66 min |
| Multiplicateurs permanents après R1 (visites x maison x succès x cosmétiques) | x1,5 x2 x1,2 x1,2 = x4,3 | x1,5 x1,5 x1,2 x1,0 = x2,7 |
| Après R8 | toutes les parties en 1 min | parties de 2 h 30 |

## Ce qui faisait boule de neige (mesuré)

1. **Les dernières améliorations ne coûtaient presque rien.** À partir de « Flèche verte » (25 min), chaque carte coûtait 1 à 12 s de gains : Méga-doigt se remboursait en 3 s, puis Icônes HD, Néon, Traînée magique et Boule disco multipliaient les gains par 25 000 en 9 minutes.
2. **Rien ne devenait plus cher après l'océan.** Toutes les améliorations gardaient leur prix ; avec x4 de bonus permanents, la 2e partie rachetait tout en 3 minutes. Le prix de l'océan (x2,5 par visite) ne suivait pas non plus.
3. **Les nouveautés des visites** (Coquillage, Aurore, Distorsion temporelle, Singularité, Multivers) ajoutaient des x1,5 à x3 à des prix dépassés tout de suite.
4. **Les bonus permanents** arrivaient tous dès la 1re partie : +100 % de confort atteint avec ~200 points (quelques dizaines de petits objets), +2 % par cosmétique (39 objets pas chers), +2 % par succès, gros cadeaux fixes (« Zen total » : 1 milliard juste après l'océan).

## Les changements

### Prix qui montent avec les visites (`Config.Rebirth`, `Formulas`)
- **Améliorations non permanentes** : prix x `(1 + r)^1,7` après `r` visites (x3,2 après 1 visite, x6,5 après 2, x10,6 après 3, x21 après 5, x42 après 8). `Formulas.GetUpgradePriceScale(r)`. Les améliorations permanentes (calendrier, succès, mode veille, boutique, quêtes, temps d'écran, arcade) gardent leur prix.
- **Océan** : `5e8 x 3,5^r x (1 + r)^1,55` (1re visite : 500 M ; 2e : 5 B ; 5e : 910 B ; 10e : 1,4 Qa).
- **Multiplicateur des visites** : toujours +50 % par visite (réglable : `MultiplierDecay`).

### Barre d'améliorations refaite (`Config.Upgrades`)
- Les 8 premières cartes (doigt, DVD, fil d'actu, calendrier, bruit du DVD, coureur, mégaphone, clavier) ne changent pas : 13 achats pendant les 5 premières minutes.
- Ensuite, les prix montent régulièrement le long de la barre (Lofi 9 K … Boule disco 1,5 B) pour que chaque carte coûte environ 1 à 3 min de gains au moment de l'acheter. Plus d'explosion en fin de partie.
- Les cartes « Dopamine/s » rapportent enfin quelque chose (Lofi 150/s, Pluie d'emojis 15 K/s, Studio de stream 15 K/s…) : la production passive compte vraiment.
- Nouveautés des visites repositionnées pour qu'on les achète **pendant** la partie où elles apparaissent (Concentration 300 M, Coquillage 600 M, Machine à rêves 600 M, Aurore 1 B, Doigts quantiques 1,5 B, Singularité 20 B, Multivers 150 B…, puis x l'échelle des prix).
- **Débloqués plus tard** : 🕹️ Arcade, 🎰 Machine chanceuse et 🪴 Parterres après 1 visite ; 📦 Coffre mystère après 2 visites.

### Bonus permanents
- 🏠 **Confort** à rendements décroissants : `1 + 1,5 x c / (c + 750)` (+0,2 % par point au début, +50 % à 375 points, +75 % à 750, jamais plus de +150 %). Avant : +0,5 % par point, +100 % dès 200 points.
- 🧢 **Cosmétiques** : +1 % par objet (avant +2 %). 🏆 **Succès** : +1 % (avant +2 %).
- Gros cadeaux de succès réduits : « Zen total » 1 B → 5 M, « Machine humaine » et « Va toucher l'herbe » 100 M → 10 M.
- 😴 **Hors-ligne** : au mieux 35 % pendant 7 h (avant 60 % pendant 12 h).
- 🌻 **Jardin** : récoltes / 2 (8 parterres rapportaient 2,5x la production à eux seuls).

### Verrous des visites à l'océan (tous vérifiés par le serveur)
| Visites | Maison | Boutique d'objets | Thèmes |
|---|---|---|---|
| 0 | ~100 petits objets (< 8 K), studio (2 pièces), salon / chambre / cuisine / salle de bain, 1 façade, 1 toit, 1 motif de toit | 8 objets | Classique, Kawaii, Matcha |
| 1 | ~100 objets (prix x3), appartement, chambre d'enfant, salle de jeux, serre | 6 objets | Coucher de soleil, Océan |
| 2 | ~70 objets (x6), coin des animaux, bibliothèque | 5 objets | Nuit lofi |
| 3 | ~45 objets (x9), loft, salle de musique, spa | 6 objets | Street |
| 5 | ~25 objets (x18), manoir, grenier étoilé, salle de sport | 7 objets | Gamer |
| 8 | ~20 objets (x34), base spatiale | 7 objets | Station spatiale |

- Maison : `Config.House.RebirthGates` donne à chaque objet / style sans `RequiresRebirths` le palier de son prix de base et multiplie son prix (`Price`). C'est calculé une seule fois à la fin de `Config` (`BaseCost` garde le prix d'origine), donc le client et le serveur affichent et vérifient les mêmes prix. Les styles (papiers peints, sols, boiseries, ambiances, vues, façades, toits, jardin) suivent la même règle.
- Types de pièces : `RequiresRebirths` sur `Config.House.RoomTypes`, vérifié à l'achat et au changement de type d'une pièce (`HouseService`). Une pièce déjà créée garde son type.
- Thèmes : `RequiresRebirths` dans `Config.Themes`, vérifié par `ThemeService` (`Formulas.IsThemeUnlocked`). Les thèmes Robux / VIP ne sont jamais verrouillés.
- Cosmétiques : `RequiresRebirths` (déjà vérifié par `CosmeticService`).

## Pour ne pas casser le rythme

`python3 tests/run_tests.py` lance deux tests du simulateur :
- joueur actif sans Robux : chaque partie ≥ la précédente, R1 45–60 min, R2 60–75, R3 75–90, R5 90–120, R8 150–240, R10 jamais avant 16 h, 1er achat en moins de 30 s, au moins 8 achats pendant les 5 premières minutes ;
- avec x2 + VIP + auto-clic : chaque partie plus rapide que sans Robux, mais au moins 25 % de sa durée, et la courbe reste croissante.

Après un changement de prix, `python3 tests/run_tests.py --sim` affiche le nouveau tableau.
