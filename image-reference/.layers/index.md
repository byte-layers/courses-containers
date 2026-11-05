---
title: "Nommer une image : registre, tag, digest"
description: "Le nom complet d'une image dit où la trouver et quelle version prendre. Un tag est une étiquette qui peut bouger, un digest désigne un contenu précis."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

`alpine:3.22` n'est que l'abrégé d'une adresse plus longue, qui dit sur quel serveur trouver une image et quelle version prendre. Or `docker pull alpine:3.22`, lancé à six mois d'écart, peut donner deux images différentes. À la fin de cette lecture, vous savez lire un nom d'image en entier, pourquoi un tag peut changer de contenu, et comment désigner une image avec la certitude d'obtenir toujours la même.

**Prérequis** : savoir lancer un conteneur et construire une image, ce qu'enseignent [Lancer, configurer et observer un conteneur](https://byte-layers.com/fr/skills/docker-run) et [Écrire le Dockerfile d'une application](https://byte-layers.com/fr/skills/docker-dockerfile).

# Nommer une image : registre, tag, digest

Vous avez jusqu'ici écrit des noms courts, et Docker complétait le reste pour vous. Pour publier une image, il faut savoir lire l'adresse entière.

## Lire un nom complet : registre, dépôt, tag

Un **registre** (*registry*) est un serveur qui stocke des images pour les partager, comme Docker Hub. Le nom complet d'une image dit quel registre interroger, quel dépôt y chercher, et quelle version prendre. Voici un exemple, avec ses morceaux :

```
registry.example.com:5000/equipe/mon-app:1.2
└───────────┬───────────┘ └─────┬──────┘ └┬┘
         registre             dépôt      tag
```

Un **dépôt** (*repository*, le mot qu'affichent les commandes de Docker) rassemble les versions d'une même image. Le **tag** désigne l'une de ces versions. Quand vous omettez un morceau, Docker met sa valeur par défaut, comme le montre ce tableau.

| Ce que vous écrivez | Ce que Docker comprend | La valeur par défaut |
|---|---|---|
| `alpine:3.22` | `docker.io/library/alpine:3.22` | le registre `docker.io`, c'est-à-dire Docker Hub, et l'espace de noms (*namespace*) `library`, celui des images officielles |
| `marie/app:1.0` | `docker.io/marie/app:1.0` | le registre `docker.io` |
| `alpine` | `docker.io/library/alpine:latest` | le tag `latest` |
| `localhost:5000/app:1.0` | `localhost:5000/app:1.0` | aucune : le début du nom désigne un registre, parce qu'il contient `:` ou `.`, ou qu'il vaut `localhost` |

Le tag `latest` n'a rien de magique : c'est le nom par défaut, et il ne garantit pas que l'image soit la plus récente. C'est pourquoi les cours de ce parcours lancent toujours leurs images avec un tag explicite, plutôt que `latest`.

## Le nom court et le nom complet désignent la même image

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

`docker pull` télécharge une image depuis un registre sans lancer de conteneur. Demandez-lui la même image avec son nom court, puis avec son nom complet :

```exec
docker pull alpine:3.22
docker pull docker.io/library/alpine:3.22
```

La seconde réponse ressemble à ceci, et la première aussi si vous aviez déjà l'image. La longue empreinte de la ligne `Digest:` sera sans doute différente chez vous :

```text
3.22: Pulling from library/alpine
Digest: sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
Status: Image is up to date for alpine:3.22
docker.io/library/alpine:3.22
```

La dernière ligne donne le nom que Docker a compris, et `Image is up to date` dit qu'il n'avait rien de plus à télécharger : pour lui, c'est la même image.

## Un tag est une étiquette posée sur une image

Une image n'a pas de nom en elle-même : un tag est une étiquette posée dessus. Le mot a deux sens que l'on croise partout : la fin du nom, comme `3.22`, et, dans la commande `docker tag`, le nom entier. `docker tag` pose donc une étiquette de plus, et `docker images` les liste. Posez une seconde étiquette sur la même image, puis comparez :

```exec
docker tag alpine:3.22 layers-l4-demo:1
docker images layers-l4-demo
docker images alpine:3.22
```

Les deux noms affichent le même identifiant de l'image sur votre machine, dans la colonne `IMAGE ID` (`ID` sur les versions récentes de Docker). Ces deux noms désignent donc une seule image, et rien n'a été copié :

```text
REPOSITORY       TAG       IMAGE ID       CREATED       SIZE
layers-l4-demo   1         2e0b81d60597   2 weeks ago   26.1MB
REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
alpine       3.22      2e0b81d60597   2 weeks ago   26.1MB
```

Retirez maintenant votre étiquette. `docker rmi`, l'abrégé de `docker image rm`, retire un nom, et ne supprime l'image que s'il ne lui en reste aucun :

```exec
docker rmi layers-l4-demo:1
```

Docker répond `Untagged` : l'étiquette est partie, et l'image `alpine:3.22` n'a pas bougé.

Une étiquette peut aussi se déplacer. Quand Alpine publie un correctif de sécurité, le tag `3.22` est reposé sur une nouvelle image : le même nom ne donne donc pas forcément le même contenu. Le cours [Publier une image : pull, tag, push](https://byte-layers.com/fr/skills/docker-publish) vous fait déplacer un tag sur votre propre registre.

## Un digest désigne un contenu précis

Pour désigner une image sans ambiguïté, il existe le **digest** : une empreinte calculée à partir de son contenu, qui commence par `sha256:`. Si le contenu change d'un octet, l'empreinte change. Un digest ne peut donc désigner qu'une seule image, et il ne bouge jamais. Vous l'avez déjà lu sur la ligne `Digest:` de `docker pull`, et `docker images --digests` l'ajoute à la liste :

```exec
docker images --digests alpine:3.22
```

La colonne `DIGEST` apparaît, à côté de l'identifiant :

```text
REPOSITORY   TAG       DIGEST                                                                    IMAGE ID       CREATED       SIZE
alpine       3.22      sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f   2e0b81d60597   2 weeks ago   26.1MB
```

Ne confondez pas ces deux valeurs. Le digest est celui du registre, le même pour toutes les machines qui téléchargent cette image. L'`IMAGE ID`, lui, est propre à votre moteur Docker (le daemon, `dockerd`) : selon sa configuration, il commence par les mêmes caractères que le digest, comme ici, ou il n'a aucun rapport avec lui.

Un nom avec digest s'écrit avec un `@` à la place du `:` du tag, et s'utilise partout où un tag est accepté. Pour lancer cette image, recopiez cette commande en remplaçant la fin par votre propre digest, puis lancez-la :

```bash
docker run --rm alpine@sha256:<votre-digest> cat /etc/alpine-release
```

Elle affiche un numéro comme `3.22.2`, la version d'Alpine contenue dans cette image. Tant que le registre garde cette image, ce nom donnera exactement ce contenu, quel que soit le nombre de fois où le tag `3.22` aura bougé.

Ce tableau résume quand utiliser l'un ou l'autre. Il vaut mieux lire un tag quand on parle à un humain, et un digest quand il faut la garantie.

| | Tag | Digest |
|---|---|---|
| Exemple | `alpine:3.22` | `alpine@sha256:2e0b81d6…` |
| Facile à lire | oui | non |
| Peut changer de contenu | oui | jamais |
| Reçoit les correctifs de sécurité | oui, si le tag est déplacé | non : il faut changer de digest soi-même |
| On l'utilise pour | choisir une version, parler d'une version | figer ce qui part en production, prouver ce qui a tourné |

> 📖 [Qu'est-ce qu'un registre ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/) · [`docker tag`, et la forme d'un nom](https://docs.docker.com/reference/cli/docker/image/tag/) · [Télécharger une image par son digest](https://docs.docker.com/reference/cli/docker/image/pull/)

## Ce qu'il faut retenir

- Le nom complet d'une image donne son registre, son dépôt et son tag, et Docker complète ce que vous omettez.
- Un tag est une étiquette : elle peut être déplacée vers une autre image.
- Un digest est une empreinte du contenu : il désigne toujours exactement la même image.

```quiz
prompt: "Hier et aujourd'hui, vous avez lancé `mon-app:1.2` sur un serveur neuf, et le comportement a changé. Comment est-ce possible ?"
answers:
  - "C'est impossible : un tag désigne toujours la même image"
  - "Quelqu'un a publié une autre image sous le même tag : l'étiquette a été déplacée"
  - "L'image s'est modifiée toute seule en cours d'exécution"
correct: 2
explanation: |
  Une image ne change jamais, mais son tag peut être reposé sur une autre image. Pour figer exactement ce que l'on lance, on utilise le digest.
```

```ack
J'ai compris
```
