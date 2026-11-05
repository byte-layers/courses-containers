---
title: "Pourquoi les conteneurs"
description: "Ce qu'est un conteneur, le problème qu'il résout, et pourquoi on apprend à s'en servir avec Docker."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 10
requires: "0.4.0"
---

Un conteneur fait tourner une application à part du reste de la machine, avec ce dont elle a besoin, pour qu'elle se comporte de la même façon partout. Vous saurez quel problème il résout, ce qu'il faut pour en lancer un, et pourquoi on apprend à s'en servir avec Docker.

**Prérequis** : [Déployer une application : les possibilités](https://byte-layers.com/fr/bits/app-deployment).

# Pourquoi les conteneurs

Parmi les façons de déployer une application, les conteneurs sont celle que ce parcours vous apprend. Leur raison d'être tient en une phrase que tous les développeurs ont entendue : « Ça marche sur ma machine. »

## Une application dépend de sa machine

Une application a besoin de ses **dépendances** : un environnement d'exécution en version précise, comme Node.js ou Python, des bibliothèques, des fichiers de configuration. Quand on les installe directement sur une machine, trois ennuis reviennent sans cesse :

| Ce qui arrive | Pourquoi |
|---|---|
| L'application marche chez vous, et plante en production, c'est-à-dire sur le serveur qu'utilisent ses vrais utilisateurs | les deux machines n'ont pas les mêmes versions de ses dépendances |
| Installer la seconde application casse la première | l'une veut Node.js 18, l'autre Node.js 22, et la machine n'en a qu'un seul pour les deux |
| Un nouveau collègue met deux jours à tout faire tourner | la procédure d'installation est longue, et elle n'est jamais tout à fait à jour |

Ces trois ennuis ont la même cause : l'application dépend de l'état de la machine, et cet état change d'une machine à l'autre.

## Un conteneur fait tourner l'application à part, avec ce dont elle a besoin

Un **conteneur** fait tourner une application isolée du reste de la machine, avec ses propres fichiers. Ses dépendances viennent avec elle : au lieu d'adapter la machine à l'application, on y installe seulement un outil capable de lancer des conteneurs. Le schéma suivant compare les deux situations sur un même serveur.

```
      Sans conteneur                     Avec des conteneurs

┌─────────┐  ┌─────────┐          ┌───────────┐  ┌───────────┐
│  App A  │  │  App B  │          │  App A    │  │  App B    │
└────┬────┘  └────┬────┘          │ Node.js 18│  │ Node.js 22│
     └─────┬──────┘               └─────┬─────┘  └─────┬─────┘
     ┌─────▼──────┐                ┌────▼──────────────▼────┐
     │ un seul    │                │        Docker          │
     │ Node.js,   │                ├────────────────────────┤
     │ pour deux  │                │        la machine      │
     ├────────────┤                └────────────────────────┘
     │ la machine │
     └────────────┘
```

À gauche, les deux applications doivent s'entendre sur une version. À droite, chacune emporte la sienne. Trois choses en découlent :

- **La même chose partout.** Ce qui tourne sur votre poste est ce qui tourne en production, ce qui supprime une grande partie des surprises.
- **Des applications qui ne se gênent pas.** Chacune a ses fichiers et ses versions, sans toucher à celles de sa voisine.
- **Un lancement simple, et rien à défaire.** Une seule commande lance l'application, et supprimer le conteneur ne touche pas au reste de la machine.

## Pour lancer un conteneur : une image, venue d'un registre

Pour lancer un conteneur, il faut un point de départ. Retenez cette chaîne : un conteneur se lance à partir d'une **image**, et cette image se télécharge depuis un **registre**.

```
registre  ──téléchargement──►  image  ──lancement──►  conteneur
```

Vous croiserez ces trois mots très vite, et un prochain cours les met en pratique. Ce tableau vous donne simplement une première idée de ce qu'ils désignent.

| Mot | Ce qu'il désigne |
|---|---|
| **image** | le paquet : l'application, ses dépendances et sa configuration, en lecture seule |
| **conteneur** | un programme lancé à partir d'une image ; il existe jusqu'à ce qu'on le supprime, même une fois arrêté |
| **registre** | un serveur qui stocke des images pour les partager, comme Docker Hub, le registre public de Docker |

## Ce que les conteneurs ne font pas

Un conteneur ne rend pas une application meilleure, et il vaut mieux le savoir dès le départ :

- Il ne corrige pas ses bogues : il les transporte fidèlement d'une machine à l'autre.
- Il n'isole pas autant qu'une machine virtuelle, parce que tous les conteneurs d'une machine partagent le même noyau. Un prochain cours, « Un conteneur est un processus isolé », explique ce point.
- Par défaut, il ne garde pas ses données quand on le supprime. Un prochain cours, « Garder ses données », montre comment les conserver.

## Pourquoi Docker : il a rendu les conteneurs faciles à utiliser

Docker n'est pas le seul outil, mais il est l'un des premiers, sinon le premier, à avoir rendu les conteneurs accessibles à tous. Le système Linux savait déjà isoler des programmes, mais c'était réservé à des connaisseurs. Docker, sorti en 2013, a ramené cela à quelques commandes et à des images faciles à partager.

En partie grâce à lui, un standard a suivi : l'[Open Container Initiative](https://opencontainers.org/), ou OCI, qui fixe le format des images et la façon de lancer un conteneur. Plusieurs outils se sont développés autour de ce standard, chacun avec son rôle. Vous croiserez par exemple Podman, qui s'utilise presque comme Docker, et containerd, qui fait vivre les conteneurs en coulisse, y compris sous Docker.

Ce parcours utilise Docker parce que c'est aujourd'hui l'outil le plus répandu pour conteneuriser des applications, c'est-à-dire pour les emballer dans des images. Pour faire tourner ces images en production, le paysage est plus varié, mais le standard joue en votre faveur : une image construite avec Docker tourne avec les autres outils, et ce que vous apprenez ici vous servira ailleurs.

> 📖 [Vue d'ensemble de Docker](https://docs.docker.com/get-started/docker-overview/) · [Qu'est-ce qu'un conteneur ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/)

## Récap

- Une application dépend de sa machine, et c'est la source du « ça marche sur ma machine ».
- Un conteneur fait tourner l'application à part, avec ses dépendances. Il se lance à partir d'une image, qui se télécharge depuis un registre.
- Docker a popularisé cet usage, et le standard OCI permet à d'autres outils de lire les mêmes images.

```quiz
title: "Pourquoi les conteneurs"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Deux applications ont besoin de deux versions différentes de Python sur le même serveur. Qu'apportent les conteneurs ?"
    answers:
      - "Rien : un serveur ne peut avoir qu'une version de Python"
      - "Chaque application emporte sa version de Python dans son image, et elles cohabitent sans se gêner"
      - "Docker choisit automatiquement la version la plus récente pour les deux"
    correct: 2
    explanation: "Les dépendances voyagent avec l'application. La machine n'a besoin que de Docker, et chaque conteneur a sa propre version de Python."
  - prompt: "D'où vient l'image à partir de laquelle on lance un conteneur ?"
    answers:
      - "Elle est créée par le conteneur au premier lancement"
      - "Elle se télécharge depuis un registre, comme Docker Hub"
      - "Elle fait partie du système d'exploitation"
    correct: 2
    explanation: "Le registre stocke les images, l'image sert de point de départ, et le conteneur est ce qu'on lance à partir d'elle."
```

```ack
J'ai compris
```
