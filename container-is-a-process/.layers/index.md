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

Un conteneur n'est pas une petite machine. C'est un **processus**, un programme en cours d'exécution, qui tourne sur le noyau Linux de l'hôte, la machine qui l'héberge. Le noyau lui applique deux mécanismes :

| Mécanisme | La question à laquelle il répond | Exemples |
|---|---|---|
| **namespaces** | que peut-il **voir** ? | ses processus, son réseau, ses fichiers, son nom d'hôte |
| **cgroups** | combien peut-il **consommer** ? | mémoire, CPU |

Une machine virtuelle embarque son propre noyau. Un conteneur partage celui de l'hôte : c'est pour cela qu'il démarre en une
fraction de seconde. Sur macOS et Windows, Docker Desktop fait tourner ce noyau Linux dans une petite machine virtuelle.

## Ce qu'il voit

Lancez un conteneur qui attend, puis listez les processus vus de l'intérieur :

```exec
docker run -d --name layers-l1-iso alpine:3.22 sleep 3600
docker exec layers-l1-iso ps
```

Un **PID** est le numéro d'un processus. Votre `sleep` est le **PID 1**, le premier processus de son monde ; l'autre ligne est le `ps` que vous venez de lancer. Il ne voit ni les autres conteneurs, ni les services de
la machine. Demandez maintenant à Docker le même processus, vu du système qui l'héberge :

```exec
docker top layers-l1-iso
```

C'est le même processus, avec un tout autre numéro. Le **namespace PID** lui donne sa propre numérotation.

Le nom d'hôte est isolé de la même façon. Ici, c'est le début de l'identifiant du conteneur :

```exec
docker exec layers-l1-iso hostname
```

Et le noyau, lui, est partagé. Deux images différentes affichent le même, car ce n'est pas le leur :

```exec
docker exec layers-l1-iso uname -sr
docker run --rm nginx:1.30-alpine uname -sr
```

Sur Linux, c'est aussi celui de `uname -sr` sur votre machine. Sur macOS et Windows, c'est celui de la machine virtuelle de Docker Desktop.

## Ce qu'il peut consommer

Sans limite, un conteneur peut utiliser toute la mémoire de l'hôte. Avec `--memory`, Docker écrit la limite dans un **cgroup**, et
on peut la lire depuis l'intérieur (sur les systèmes en cgroup v2, les plus courants aujourd'hui). Sans limite d'abord, le fichier contient simplement `max` :

```exec
docker run --rm alpine:3.22 cat /sys/fs/cgroup/memory.max
```

Puis avec 64 Mio, soit 64 × 1024 × 1024 = 67 108 864 octets :

```exec
docker run --rm --memory 64m alpine:3.22 cat /sys/fs/cgroup/memory.max
```

Rangez le conteneur :

```exec
docker rm -f layers-l1-iso
```

## Ce qu'il faut retenir

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
