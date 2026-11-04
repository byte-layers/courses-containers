---
title: "Nommer une image : registre, tag, digest"
description: "Le nom complet d'une image dit où la trouver et quelle version prendre. Un tag est une étiquette qui bouge, un digest ne change jamais."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Nommer une image : registre, tag, digest

**Pour qui ?** Pour vous, si vous savez lancer un conteneur et construire une image avec un Dockerfile. Il vous faut Docker qui répond à `docker ps`.

Jusqu'ici, vous avez écrit des noms d'image courts, comme `alpine:3.22`. Ce nom n'est que la version abrégée d'une adresse plus longue, et Docker complète le reste pour vous. Pour publier une image, il faut savoir lire cette adresse en entier.

## L'anatomie d'un nom

Un **registre** est un serveur qui stocke des images pour les partager. Le nom complet d'une image dit quel registre interroger, quel dépôt y chercher, et quelle version prendre. Voici un exemple, avec ses morceaux :

```
registry.example.com:5000/equipe/mon-app:1.2
└───────────┬───────────┘ └─────┬──────┘ └┬┘
         registre             dépôt      tag
```

Un **dépôt** rassemble les versions d'une même image. Le **tag**, lui, désigne l'une de ces versions. Quand vous omettez un morceau, Docker met sa valeur par défaut, comme le montre ce tableau.

| Ce que vous écrivez | Ce que Docker comprend | La valeur par défaut |
|---|---|---|
| `alpine:3.22` | `docker.io/library/alpine:3.22` | le registre `docker.io`, c'est-à-dire Docker Hub, et l'espace `library`, celui des images officielles |
| `marie/app:1.0` | `docker.io/marie/app:1.0` | le registre `docker.io` |
| `alpine` | `docker.io/library/alpine:latest` | le tag `latest` |
| `localhost:5000/app:1.0` | `localhost:5000/app:1.0` | aucune : le début du nom désigne un registre, parce qu'il contient `:` ou `.` |

Le tag `latest` n'a rien de magique : c'est le nom par défaut, et il ne garantit pas que l'image soit la plus récente. C'est pourquoi les cours de ce parcours écrivent toujours une version précise.

## Le constater

Vous n'avez pas besoin de connaître ces commandes pour lire la suite : le cours « Publier une image : pull, tag, push » les détaille. Ce tableau suffit pour l'instant.

| Élément | Rôle |
|---|---|
| `docker pull` | télécharge une image depuis un registre |
| `docker tag` | donne un nom de plus à une image qui existe déjà |
| `docker rmi` | retire un nom, et supprime l'image quand il ne lui en reste aucun |

Téléchargez une image avec son nom court, puis avec son nom complet :

```exec
docker pull alpine:3.22
docker pull docker.io/library/alpine:3.22
```

Chaque téléchargement se termine par la même ligne, `docker.io/library/alpine:3.22`, le nom que Docker a compris. Le second vous répond aussi `Image is up to date` : pour lui, c'est la même image.

Si un téléchargement échoue avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub pour les téléchargements anonymes. Attendez, ou créez un compte gratuit et lancez `docker login`.

## Le tag est une étiquette

Une image n'a pas de nom en elle-même : un tag est une étiquette posée dessus. Posez-en une seconde sur la même image, puis comparez ce que chaque nom désigne. `docker image inspect` lit la fiche d'une image, et `--format` en extrait l'identifiant :

```exec
docker tag alpine:3.22 layers-l4-demo:1
docker image inspect alpine:3.22 layers-l4-demo:1 --format '{{.Id}}'
```

Les deux lignes sont identiques : ces deux noms désignent une seule image, et rien n'a été copié. Retirez maintenant votre étiquette :

```exec
docker rmi layers-l4-demo:1
```

Docker répond `Untagged` : l'étiquette est partie, l'image `alpine:3.22` n'a pas bougé.

Une étiquette se déplace : un tag peut donc désigner demain une autre image qu'aujourd'hui. `3.22` recevra par exemple les correctifs de sécurité d'Alpine. Le même nom ne donne pas forcément le même contenu.

## Le digest ne bouge pas

Pour désigner une image sans aucune ambiguïté, il existe le **digest** : une empreinte calculée à partir de son contenu, qui commence par `sha256:`. Si le contenu change d'un octet, l'empreinte change. Une fois publiée, une image garde donc son digest, et ce digest ne peut désigner qu'elle. Lisez celui de votre image ; `RepoDigests` est le champ où Docker note le digest qu'il a reçu du registre, et `index … 0` en prend la première valeur :

```exec
docker image inspect alpine:3.22 --format '{{index .RepoDigests 0}}'
```

La réponse a la forme `alpine@sha256:…`, un nom de dépôt suivi du digest. Un `@` remplace le `:` du tag, et vous pouvez utiliser ce nom partout où un tag est accepté. La commande suivante lance un conteneur avec ce nom. `$(…)` exécute la commande entre parenthèses et met son résultat à cette place, ce qui vous évite de recopier le digest :

```exec
docker run --rm "$(docker image inspect alpine:3.22 --format '{{index .RepoDigests 0}}')" cat /etc/alpine-release
```

Vous lisez un numéro comme `3.22.7`, la version d'Alpine contenue dans cette image.

Le tableau suivant résume quand utiliser l'un ou l'autre. Il vaut mieux lire un tag quand on parle à un humain, et un digest quand il faut la garantie.

| | Tag | Digest |
|---|---|---|
| Exemple | `alpine:3.22` | `alpine@sha256:2e0b81d6…` |
| Facile à lire | oui | non |
| Peut changer de contenu | oui | jamais |
| On l'utilise pour | choisir une version, parler d'une version | figer ce qui part en production, prouver ce qui a tourné |

> 📖 [Qu'est-ce qu'un registre ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/) · [`docker tag`, et la forme d'un nom](https://docs.docker.com/reference/cli/docker/image/tag/) · [Tirer une image par son digest](https://docs.docker.com/reference/cli/docker/image/pull/)

## Ce qu'il faut retenir

- Le nom complet d'une image donne son registre, son dépôt et son tag ; Docker complète ce que vous omettez.
- Un tag est une étiquette : elle peut être déplacée vers une autre image.
- Un digest est une empreinte du contenu : il désigne toujours exactement la même image.

```quiz
prompt: "Hier et aujourd'hui, vous avez lancé `mon-app:1.2`, et le comportement a changé. Comment est-ce possible ?"
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
