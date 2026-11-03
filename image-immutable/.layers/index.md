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

Une **image** contient tout ce qu'il faut pour lancer un logiciel : ses fichiers et sa configuration. C'est un modèle en lecture seule. Un **conteneur** est une instance de ce modèle en train de vivre. Tout le reste de Docker découle de cette séparation.

Vous n'avez pas besoin de connaître Docker pour lire ceci : lancez simplement les commandes. Le cours « Lancer, configurer et observer un conteneur » les détaille. D'ici là :

| Élément | Rôle |
|---|---|
| `docker run` | crée un conteneur depuis une image et le démarre |
| `-d` / `--name` | en arrière-plan / avec un nom fixe |
| `docker exec` | lance une commande dans un conteneur qui tourne |
| `docker rm -f` | supprime un conteneur, même s'il tourne |
| `--rm` | supprime le conteneur à son arrêt |
| `alpine:3.22` | l'image `alpine`, un Linux minimal, en version `3.22` (ce qui suit `:` s'appelle le *tag*) |

Il faut Docker qui répond à `docker ps`. Si le téléchargement échoue avec `429 Too Many Requests`, c'est la limite de Docker Hub pour les téléchargements anonymes : attendez, ou créez un compte gratuit et lancez `docker login`.

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

Quand un conteneur modifie un fichier, l'image ne bouge pas : la modification est écrite dans sa couche d'écriture.
Deux conséquences expliquent une bonne partie du comportement de Docker :

- **Les conteneurs sont légers.** Dix conteneurs d'une même image ne stockent l'image qu'une fois, plus dix petites couches.
- **Une image donne toujours le même départ**, sur votre poste comme en production.

## Le constater

Lancez deux conteneurs depuis la même image :

```exec
docker run -d --name layers-l1-a alpine:3.22 sleep 3600
docker run -d --name layers-l1-b alpine:3.22 sleep 3600
```

Écrivez un fichier dans le premier, puis cherchez-le dans le second :

```exec
docker exec layers-l1-a sh -c 'echo trace > /tmp/preuve.txt'
docker exec layers-l1-b cat /tmp/preuve.txt
```

`No such file or directory` : le second ne voit rien. Pourtant, les deux partent bien de la même image. Docker le confirme : les deux identifiants `sha256:` sont identiques.

```exec
docker inspect layers-l1-a layers-l1-b --format '{{.Name}} {{.Image}}'
```

`docker diff` montre ce qui distingue un conteneur de son image. `A` veut dire *added*, `C` veut dire *changed* :

```exec
docker diff layers-l1-a
```

Enfin, un conteneur tout neuf, créé depuis cette image, n'a pas ce fichier non plus :

```exec
docker run --rm alpine:3.22 cat /tmp/preuve.txt
```

L'image n'a donc pas changé. Rangez vos conteneurs :

```exec
docker rm -f layers-l1-a layers-l1-b
```

## Ce qu'il faut retenir

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
