---
title: "Un conteneur est un processus isolé"
description: "Pas de machine dans un conteneur : un processus ordinaire, à qui le noyau donne une vue à part et des limites."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.3.0"
---

# Un conteneur est un processus isolé

**Pour qui ?** Pour vous, si vous débutez avec les conteneurs. Il suffit de savoir utiliser un terminal, et que `docker ps` réponde. Lisez d'abord « L'image est immuable », qui explique ce qu'est une image.

On imagine souvent un conteneur comme une petite machine. Ce n'en est pas une : c'est un **processus**, c'est-à-dire un programme en cours d'exécution, qui tourne sur l'**hôte**, la machine qui l'héberge.

Ce qui l'isole vient du **noyau**, la partie du système qui gère les processus, la mémoire et le matériel. Le noyau Linux lui applique deux mécanismes :

| Mécanisme | La question à laquelle il répond | Exemples |
|---|---|---|
| **namespaces** | que peut-il **voir** ? | ses processus, son réseau, ses fichiers, son nom d'hôte |
| **cgroups** | combien peut-il **consommer** ? | mémoire, CPU |

Une machine virtuelle, elle, simule un ordinateur entier et démarre son propre noyau. Un conteneur partage celui de l'hôte : une fois l'image téléchargée, il démarre donc en une fraction de seconde. Sur macOS et Windows, où il n'y a pas de noyau Linux, Docker Desktop en fait tourner un dans une petite machine virtuelle.

## Ce qu'il voit

Vous n'avez pas besoin de connaître ces commandes pour lire la suite : le cours « Lancer, configurer et observer un conteneur » les détaille. Ce tableau suffit pour l'instant.

| Élément | Rôle |
|---|---|
| `docker run` | crée un conteneur depuis une image et le démarre |
| `-d` / `--name` | en arrière-plan / avec un nom fixe |
| `alpine:3.22` | l'image `alpine`, un Linux minimal, au tag `3.22` |
| `sleep 3600` | la commande du conteneur : elle attend une heure, ce qui le garde en vie |
| `docker exec` | lance une commande dans un conteneur qui tourne |
| `docker rm -f` | supprime un conteneur, même s'il tourne |
| `--rm` | supprime le conteneur à son arrêt |

Si un téléchargement échoue avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub pour les téléchargements anonymes. Attendez, ou créez un compte gratuit et lancez `docker login`.

Lancez un conteneur qui attend, puis listez les processus vus de l'intérieur :

```exec
docker run -d --name layers-l1-iso alpine:3.22 sleep 3600
docker exec layers-l1-iso ps
```

Un **PID** est le numéro d'un processus. Votre `sleep` est le **PID 1**, le premier processus de son monde, et l'autre ligne est le `ps` que vous venez de lancer. Le conteneur ne voit ni les autres conteneurs, ni les services de la machine.

Demandez maintenant à Docker le même processus, vu du système qui l'héberge, soit la machine virtuelle sur macOS et Windows :

```exec
docker top layers-l1-iso
```

C'est le même processus, avec un tout autre numéro : le **namespace PID** lui donne sa propre numérotation.

Le nom d'hôte, le nom de la machine sur le réseau, est isolé de la même façon. Ici, c'est le début de l'identifiant du conteneur :

```exec
docker exec layers-l1-iso hostname
```

Le noyau, lui, est partagé. `uname -sr` affiche son nom et sa version : ici, le conteneur alpine et un conteneur nginx, un serveur web sans rapport avec lui, affichent le même, car ce n'est le leur ni à l'un ni à l'autre.

```exec
docker exec layers-l1-iso uname -sr
docker run --rm nginx:1.30-alpine uname -sr
```

Sur Linux, c'est aussi celui de `uname -sr` sur votre machine. Sur macOS et Windows, c'est celui de la machine virtuelle de Docker Desktop.

## Ce qu'il peut consommer

Sans limite, un conteneur peut utiliser toute la mémoire de l'hôte. Avec `--memory`, Docker écrit une limite dans un **cgroup**, et on peut la lire depuis l'intérieur, sur les systèmes récents. Si le fichier ci-dessous est introuvable, votre système utilise l'ancienne version des cgroups : passez simplement à la suite.

Sans limite d'abord, le fichier contient `max` :

```exec
docker run --rm alpine:3.22 cat /sys/fs/cgroup/memory.max
```

Avec 64 Mio, le fichier contient 64 × 1024 × 1024, soit 67 108 864 octets :

```exec
docker run --rm --memory 64m alpine:3.22 cat /sys/fs/cgroup/memory.max
```

Il reste à ranger votre conteneur :

```exec
docker rm -f layers-l1-iso
```

> 📖 [Qu'est-ce qu'un conteneur ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/) · [Limiter les ressources](https://docs.docker.com/engine/containers/resource_constraints/)

## Ce qu'il faut retenir

- Un conteneur est un processus de l'hôte, pas une machine.
- Les namespaces décident de ce qu'il voit, les cgroups de ce qu'il consomme.
- Il partage le noyau de l'hôte, d'où sa rapidité de démarrage.

```quiz
prompt: "Pourquoi un conteneur démarre-t-il bien plus vite qu'une machine virtuelle ?"
answers:
  - "Parce que ses images sont compressées"
  - "Parce qu'il ne démarre pas de noyau : c'est un processus sur le noyau de l'hôte"
  - "Parce qu'il n'a pas de système de fichiers"
correct: 2
explanation: |
  Un conteneur est un processus isolé par les namespaces et limité par les cgroups. Lancer un processus prend une
  fraction de seconde ; démarrer un système complet, bien plus.
```

```ack
J'ai compris
```
