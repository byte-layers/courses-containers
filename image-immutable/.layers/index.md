---
title: "L'image est immuable"
description: "Une image ne change jamais. Un conteneur en est une instance, avec une fine couche d'écriture qui n'appartient qu'à lui."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.3.0"
---

# L'image est immuable

**Pour qui ?** Pour vous, si vous débutez avec les conteneurs. Il suffit de savoir utiliser un terminal. Aucune connaissance de Docker n'est nécessaire, mais il doit être installé : `docker ps` doit répondre.

Une **image** contient tout ce qu'il faut pour lancer un logiciel : ses fichiers et sa configuration. C'est un modèle en lecture seule. Un **conteneur** est une instance de ce modèle en train de vivre. Tout le reste de Docker découle de cette séparation.

Quand un conteneur modifie un fichier, l'image ne bouge pas : la modification est écrite dans sa **couche d'écriture**, l'espace qui n'appartient qu'à lui. Voici deux conteneurs issus d'une même image :

```
   conteneur A            conteneur B
┌───────────────┐      ┌───────────────┐
│ couche        │      │ couche        │   en écriture, propre à chaque
│ d'écriture    │      │ d'écriture    │   conteneur, supprimée avec lui
└───────┬───────┘      └───────┬───────┘
        └──────────┬───────────┘
          ┌────────▼────────┐
          │      image      │   en lecture seule, partagée
          └─────────────────┘
```

Deux conséquences expliquent une bonne partie du comportement de Docker :

- **Les conteneurs sont légers.** Dix conteneurs d'une même image ne stockent l'image qu'une fois, plus dix petites couches.
- **Une image donne toujours le même départ**, sur votre poste comme en production.

Une nuance à garder en tête : l'image est immuable, mais son **tag**, le nom après les deux-points comme `3.22`, est une étiquette qui peut être déplacée vers une image plus récente.

## Le constater

Vous n'avez pas besoin de connaître ces commandes pour lire la suite : le cours « Lancer, configurer et observer un conteneur » les détaille. Ce tableau suffit pour l'instant.

| Élément | Rôle |
|---|---|
| `docker run` | crée un conteneur depuis une image et le démarre |
| `-d` / `--name` | en arrière-plan / avec un nom fixe |
| `alpine:3.22` | l'image `alpine`, un Linux minimal, au tag `3.22` |
| `sleep 3600` | la commande du conteneur : elle attend une heure, ce qui le garde en vie |
| `docker exec` | lance une commande dans un conteneur qui tourne |
| `sh -c '…'` | fait exécuter la phrase entre apostrophes par le shell du conteneur |
| `docker rm -f` | supprime un conteneur, même s'il tourne |
| `--rm` | supprime le conteneur à son arrêt |

Si un téléchargement échoue avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub pour les téléchargements anonymes. Attendez, ou créez un compte gratuit et lancez `docker login`.

Lancez deux conteneurs depuis la même image :

```exec
docker run -d --name layers-l1-a alpine:3.22 sleep 3600
docker run -d --name layers-l1-b alpine:3.22 sleep 3600
```

Écrivez maintenant un fichier dans le premier, puis cherchez-le dans le second :

```exec
docker exec layers-l1-a sh -c 'echo trace > /tmp/preuve.txt'
docker exec layers-l1-b cat /tmp/preuve.txt
```

Le message `No such file or directory` montre que le second ne voit rien. Pourtant, les deux partent bien de la même image. `docker inspect` lit la fiche de chaque conteneur, et `--format` en extrait ici son nom et l'identifiant de son image :

```exec
docker inspect layers-l1-a layers-l1-b --format '{{.Name}} {{.Image}}'
```

Les deux identifiants `sha256:` sont identiques. Le `/` devant les noms est une habitude d'affichage de Docker, sans conséquence.

Qu'est-ce qui distingue alors un conteneur de son image ? `docker diff` répond en listant sa couche d'écriture, où `A` veut dire *added* et `C` veut dire *changed* :

```exec
docker diff layers-l1-a
```

Un conteneur tout neuf, créé depuis cette image, n'a pas ce fichier non plus, ce qui prouve que l'image n'a pas changé :

```exec
docker run --rm alpine:3.22 cat /tmp/preuve.txt
```

Il reste à ranger vos deux conteneurs :

```exec
docker rm -f layers-l1-a layers-l1-b
```

> 📖 [Qu'est-ce qu'une image ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-an-image/) · [Les couches et le stockage](https://docs.docker.com/engine/storage/drivers/)

## Ce qu'il faut retenir

- L'image est en lecture seule et partagée entre ses conteneurs.
- Chaque conteneur écrit dans sa propre couche, qui disparaît avec lui.
- Un conteneur neuf repart toujours de l'image.

```quiz
prompt: "Vous modifiez un fichier dans un conteneur en cours d'exécution, puis vous en créez un nouveau depuis la même image. Que contient le nouveau ?"
answers:
  - "Le fichier modifié, car l'image a été mise à jour"
  - "Le fichier d'origine, car la modification est restée dans la couche d'écriture du premier conteneur"
  - "Rien : le fichier a été verrouillé par le premier conteneur"
correct: 2
explanation: |
  L'image est en lecture seule. La modification ne quitte pas la couche d'écriture du premier conteneur, et chaque
  nouveau conteneur repart de l'image.
```

```ack
J'ai compris
```
