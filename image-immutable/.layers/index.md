---
title: "L'image est immuable"
description: "Une image ne change jamais : ce qu'un conteneur modifie reste dans sa couche d'écriture, et disparaît avec lui."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

Vous modifiez un fichier dans un conteneur, puis vous supprimez ce conteneur et vous en recréez un : votre modification a disparu. Rien n'est cassé, l'image n'a simplement jamais changé. Vous saurez où va ce qu'écrit un conteneur, et pourquoi dix conteneurs d'une même image ne stockent celle-ci qu'une fois.

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

**Prérequis** : savoir lancer un conteneur, ce qu'enseigne [Lancer, configurer et observer un conteneur](https://byte-layers.com/fr/skills/docker-run). Le lab [Héberger une page dans un conteneur](https://byte-layers.com/fr/labs/docker-first-web-page) en donne un exemple.

# L'image est immuable

Une **image** contient tout ce qu'il faut pour lancer un logiciel : ses fichiers et sa configuration. Elle est **immuable**, c'est-à-dire qu'elle ne change jamais une fois construite. Un **conteneur** est un programme lancé depuis cette image, avec en plus sa **couche d'écriture**, l'espace qui n'appartient qu'à lui : tout ce qu'il modifie y va.

Les commandes utilisées ici sont celles du prérequis : `docker run -d --name` lance un conteneur en arrière-plan, `docker exec` y exécute une commande, `docker inspect --format` lit un champ de sa fiche, et `docker rm -f` le supprime.

## Deux conteneurs, un seul fichier modifié

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

Lancez deux conteneurs depuis la même image. `sleep 3600` les garde en vie pendant une heure :

```exec
docker run -d --name layers-l1-a alpine:3.22 sleep 3600
docker run -d --name layers-l1-b alpine:3.22 sleep 3600
```

Écrivez un fichier dans le premier. `sh -c` fait exécuter la phrase entre apostrophes par le shell du conteneur, pour que la redirection `>` ait lieu dans le conteneur et non sur votre machine :

```exec
docker exec layers-l1-a sh -c 'echo trace > /tmp/preuve.txt'
```

Cherchez maintenant ce fichier dans le second :

```exec
docker exec layers-l1-b cat /tmp/preuve.txt
```

Le second ne voit rien :

```text
cat: can't open '/tmp/preuve.txt': No such file or directory
```

Pourtant, les deux partent bien de la même image. Demandez à chacun l'identifiant de la sienne :

```exec
docker inspect layers-l1-a layers-l1-b --format '{{.Name}} {{.Image}}'
```

Les deux identifiants sont identiques. Le `/` devant les noms est une habitude d'affichage de Docker, sans conséquence.

```text
/layers-l1-a sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
/layers-l1-b sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
```

## La couche d'écriture : ce que montre docker diff

Ce qui distingue un conteneur de son image, `docker diff` le liste : c'est le contenu de sa couche d'écriture. `A` veut dire *added* et `C` veut dire *changed*.

```exec
docker diff layers-l1-a
```

Votre fichier est bien là, dans le dossier `/tmp` qu'il a modifié :

```text
C /tmp
A /tmp/preuve.txt
```

## Un conteneur neuf repart de l'image

Si l'image avait changé, un nouveau conteneur aurait ce fichier. Lancez-en un, qui se supprimera seul grâce à `--rm` :

```exec
docker run --rm alpine:3.22 cat /tmp/preuve.txt
```

Il répond la même erreur : l'image n'a pas bougé. C'est pour cela qu'une même image, reconnue à son identifiant `sha256:`, donne toujours le même départ, sur votre poste comme en production. Et comme elle est partagée, dix conteneurs d'une même image ne la stockent qu'une fois, plus dix petites couches.

Il reste à ranger vos deux conteneurs :

```exec
docker rm -f layers-l1-a layers-l1-b
```

> 📖 [Qu'est-ce qu'une image ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-an-image/) · [`docker diff`](https://docs.docker.com/reference/cli/docker/container/diff/) · [Les couches et le stockage](https://docs.docker.com/engine/storage/drivers/)

## Récap

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
  L'image est en lecture seule. La modification ne quitte pas la couche d'écriture du premier conteneur, et chaque nouveau conteneur repart de l'image.
```

```ack
J'ai compris
```
