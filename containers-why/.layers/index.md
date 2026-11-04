---
title: "Pourquoi les conteneurs"
description: "Le problème que les conteneurs résolvent : une application qui marche partout de la même façon, sans se battre avec la machine qui l'héberge."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 10
requires: "0.4.0"
---

# Pourquoi les conteneurs

**Pour qui ?** Pour vous, si vous n'avez jamais utilisé de conteneur. Il suffit de savoir ce qu'est un programme et un serveur. Rien n'est à installer pour lire cette page, et elle ne contient aucune commande.

Avant d'installer un outil, il vaut mieux savoir quel problème il résout. Celui des conteneurs tient en une phrase que tous les développeurs ont entendue : « Ça marche sur ma machine. »

## Le problème

Une application n'est jamais seule. Elle a besoin d'un environnement d'exécution, comme Node ou Python, en version précise, de bibliothèques, de fichiers de configuration. On appelle tout cela ses **dépendances**. Quand on installe directement une application sur une machine, trois ennuis reviennent sans cesse :

| Ce qui arrive | Pourquoi |
|---|---|
| L'application marche chez vous, et plante en production, c'est-à-dire sur le serveur qu'utilisent ses vrais utilisateurs | les deux machines n'ont pas les mêmes versions de ses dépendances |
| Installer la seconde application casse la première | l'une veut Node 18, l'autre Node 22, et il n'y en a qu'un sur la machine |
| Un nouveau collègue met deux jours à tout faire tourner | la procédure d'installation est longue, et elle n'est jamais tout à fait à jour |

Ces trois ennuis ont la même cause : l'application dépend de l'état de la machine, et cet état change d'une machine à l'autre.

## La réponse

Un conteneur renverse le problème : au lieu d'adapter la machine à l'application, on emballe l'application **avec** ses dépendances. Le schéma suivant compare les deux situations sur un même serveur.

```
      Sans conteneur                     Avec des conteneurs

┌─────────┐  ┌─────────┐          ┌───────────┐  ┌───────────┐
│  App A  │  │  App B  │          │  App A    │  │  App B    │
└────┬────┘  └────┬────┘          │  Node 18  │  │  Node 22  │
     └─────┬──────┘               └─────┬─────┘  └─────┬─────┘
     ┌─────▼──────┐                ┌────▼──────────────▼────┐
     │ un seul    │                │        Docker          │
     │ Node, pour │                ├────────────────────────┤
     │ les deux   │                │        la machine      │
     ├────────────┤                └────────────────────────┘
     │ la machine │
     └────────────┘
```

À gauche, les deux applications doivent s'entendre sur une version. À droite, chacune emporte la sienne, et la machine n'a besoin que de Docker. Trois choses en découlent :

- **Le même paquet partout.** Ce qui tourne sur votre poste est ce qui tourne en production, ce qui supprime une grande partie des surprises.
- **Des applications qui ne se gênent pas.** Chacune a ses fichiers et ses versions, sans toucher à celles de sa voisine.
- **Un démarrage immédiat et sans regret.** Une seule commande lance l'application. Supprimer le conteneur ne touche pas au reste de la machine, et seule son image reste, prête à resservir.

## Trois mots pour la suite

Vous croiserez ces trois mots très vite, et un prochain cours les explique en détail. Ce tableau vous donne simplement une première idée de ce qu'ils désignent.

| Mot | Ce qu'il désigne |
|---|---|
| **image** | le paquet : l'application, ses dépendances et sa configuration, en lecture seule |
| **conteneur** | un programme lancé à partir d'une image ; il existe jusqu'à ce qu'on le supprime, même une fois arrêté |
| **registre** | un serveur qui stocke des images pour les partager ; Docker Hub est le plus connu |

## Ce que les conteneurs ne font pas

Un conteneur ne rend pas une application meilleure, et il vaut mieux le savoir dès le départ :

- Il ne corrige pas ses bogues : il les transporte fidèlement d'une machine à l'autre.
- Il n'isole pas autant qu'une machine virtuelle, c'est-à-dire un ordinateur entier simulé par un logiciel, parce que tous les conteneurs d'une machine partagent le même système. Un prochain cours, « Un conteneur est un processus isolé », explique ce point.
- Par défaut, il ne garde pas ses données quand on le supprime. Un prochain cours, « Garder ses données », montre comment les conserver.

## Et pourquoi Docker ?

Docker n'est pas le seul outil. Podman s'utilise presque de la même façon, et containerd fait tourner les conteneurs de nombreux clusters, ces groupes de serveurs qui travaillent ensemble. Ces outils partagent un même format d'image, standardisé par l'Open Container Initiative : une image construite avec l'un tourne avec les autres. Ce parcours utilise Docker, parce que c'est le plus répandu et le mieux documenté, et ce que vous y apprendrez vous servira ailleurs.

> 📖 [Vue d'ensemble de Docker](https://docs.docker.com/get-started/docker-overview/) · [Qu'est-ce qu'un conteneur ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/)

## Ce qu'il faut retenir

- Une application dépend de sa machine, et c'est la source du « ça marche sur ma machine ».
- Un conteneur emballe l'application avec ses dépendances, pour qu'elle tourne de la même façon partout.
- Il ne corrige pas les bogues, et ne garde pas ses données sans qu'on le lui demande.

```quiz
prompt: "Deux applications ont besoin de deux versions différentes de Python sur le même serveur. Qu'apportent les conteneurs ?"
answers:
  - "Rien : un serveur ne peut avoir qu'une version de Python"
  - "Chaque application emporte sa version de Python dans son image, et elles cohabitent sans se gêner"
  - "Docker choisit automatiquement la version la plus récente pour les deux"
correct: 2
explanation: |
  Les dépendances voyagent avec l'application. La machine n'a besoin que de Docker, et chaque conteneur a sa propre version de Python.
```

```ack
J'ai compris
```
