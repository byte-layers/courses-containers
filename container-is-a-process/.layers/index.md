---
title: "Un conteneur est un processus isolé"
description: "Pas de machine dans un conteneur : en marche, c'est un processus ordinaire à qui le noyau donne une vue à part et des limites ; arrêté, il reste sa fiche et sa couche d'écriture."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

On imagine souvent un conteneur comme une petite machine. Ce n'en est pas une : en marche, c'est un processus de la machine qui l'héberge, à qui le noyau donne une vue à part et des limites. Vous saurez d'où vient cette isolation, ce qu'il reste d'un conteneur arrêté, et pourquoi il isole moins qu'une machine virtuelle.

**Prérequis** : savoir lancer et observer un conteneur, ce qu'enseigne [Lancer, configurer et observer un conteneur](https://byte-layers.com/fr/skills/docker-run). Pour la machine virtuelle, voir [Déployer une application : les possibilités](https://byte-layers.com/fr/bits/app-deployment).

# Un conteneur est un processus isolé

Un **processus** est un programme en cours d'exécution. Les commandes utilisées ici sont celles du prérequis : `docker run -d --name` lance le conteneur, `docker exec` y exécute une commande, `docker top` liste ses processus vus de la machine, `docker stop` l'arrête et `docker rm` le supprime.

## Le même processus, vu du conteneur et vu de la machine

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

Lancez un conteneur qui attend, puis listez ses processus vus de l'intérieur :

```exec
docker run -d --name layers-l1-iso alpine:3.22 sleep 3600
docker exec layers-l1-iso ps
```

Votre `sleep` est le **PID 1**, le premier processus de son monde, et l'autre ligne est le `ps` que vous venez de lancer. Dans sa liste de processus, il n'y a ni les autres conteneurs, ni les services de la machine.

```text
PID   USER     TIME  COMMAND
    1 root      0:00 sleep 3600
    7 root      0:00 ps
```

Demandez maintenant à Docker ce même processus, vu de la machine qui l'héberge, que l'on appelle l'**hôte**. Sur macOS et Windows, cet hôte est la machine virtuelle de Docker Desktop.

```exec
docker top layers-l1-iso
```

C'est le même `sleep 3600`, avec un tout autre numéro :

```text
UID      PID       PPID      C    STIME   TTY   TIME       CMD
root     3422005   3421982   0    22:25   ?     00:00:00   sleep 3600
```

Il existe donc bien sur l'hôte, comme n'importe quel programme. Le conteneur ne fait que lui donner sa propre numérotation.

## Ce qu'il voit : les namespaces, et un noyau partagé

Ce qui lui donne cette vue à part vient du **noyau**, la partie du système qui gère les processus, la mémoire et le matériel. Le mécanisme s'appelle les **namespaces**, et il répond à la question : que peut-il **voir** ? Le conteneur a ainsi sa propre liste de processus, et aussi son propre nom de machine, le *hostname* : ce n'est pas celui de l'hôte, mais le début de son identifiant.

```exec
docker exec layers-l1-iso hostname
```

Le noyau, lui, est partagé. `uname -sr` affiche son nom et sa version : le conteneur alpine et un conteneur nginx, un serveur web sans rapport avec lui, affichent le même, car c'est celui de l'hôte.

```exec
docker exec layers-l1-iso uname -sr
docker run --rm nginx:1.30-alpine uname -sr
```

Les deux lignes sont identiques. Le numéro dépend de votre machine. Sur Linux, c'est aussi celui de `uname -sr` sur votre poste ; sur macOS et Windows, c'est celui de la machine virtuelle de Docker Desktop.

```text
Linux 6.10.14-linuxkit
Linux 6.10.14-linuxkit
```

## Ce qu'il peut consommer : les cgroups

Le second mécanisme du noyau s'appelle les **cgroups**, et il répond à la question : combien peut-il **consommer** ? Avec `--memory`, Docker écrit une limite dans un cgroup, et on peut la lire depuis l'intérieur sur les systèmes récents. Si le fichier ci-dessous est introuvable, votre système utilise l'ancienne version des cgroups : passez simplement à la suite.

Sans limite, le fichier contient `max` :

```exec
docker run --rm alpine:3.22 cat /sys/fs/cgroup/memory.max
```

Avec 64 Mio, il contient 64 × 1024 × 1024, soit 67108864 octets :

```exec
docker run --rm --memory 64m alpine:3.22 cat /sys/fs/cgroup/memory.max
```

## Arrêté, un conteneur n'a plus de processus

Un conteneur existe pourtant encore après son arrêt : comment serait-il un processus ? Voyons-le. Arrêtez votre conteneur, ce qui prend 10 secondes avec `sleep`, puis redemandez ses processus :

```exec
docker stop layers-l1-iso
docker top layers-l1-iso
```

Il n'y a plus aucun processus à montrer :

```text
Error response from daemon: container aba0208eddad… is not running
```

`docker ps -a` le liste pourtant toujours, avec l'état `Exited` :

```exec
docker ps -a
```

La phrase exacte est donc celle-ci : **en marche, un conteneur est un processus. Arrêté, il ne reste que sa fiche, ses logs et sa couche d'écriture**, de quoi le relancer avec `docker start`. Il disparaît pour de bon avec `docker rm`, ce que vous faites maintenant :

```exec
docker rm layers-l1-iso
```

## Ce qui le distingue d'une machine virtuelle

Une machine virtuelle simule un ordinateur entier et démarre son propre noyau. Un conteneur partage celui de l'hôte, et deux conséquences en découlent :

- **Il démarre très vite.** Une fois l'image téléchargée, lancer un conteneur revient à lancer un processus, soit une fraction de seconde.
- **Il isole moins.** Une faille du noyau peut concerner tous les conteneurs de la machine, alors qu'une machine virtuelle a son noyau à elle. Pour faire cohabiter des applications qui ne se font pas confiance, ce point compte.

> 📖 [Qu'est-ce qu'un conteneur ?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/) · [Limiter les ressources](https://docs.docker.com/engine/containers/resource_constraints/) · [`docker top`](https://docs.docker.com/reference/cli/docker/container/top/)

## Récap

- En marche, un conteneur est un processus de l'hôte, pas une machine. Arrêté, il ne reste que sa fiche, ses logs et sa couche d'écriture.
- Les namespaces décident de ce qu'il voit, les cgroups de ce qu'il consomme.
- Il partage le noyau de l'hôte : il démarre vite, et il isole moins qu'une machine virtuelle.

```quiz
title: "Un conteneur est un processus isolé"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi un conteneur démarre-t-il bien plus vite qu'une machine virtuelle ?"
    answers:
      - "Parce que ses images sont compressées"
      - "Parce qu'il ne démarre pas de noyau : c'est un processus sur le noyau de l'hôte"
      - "Parce qu'il n'a pas de système de fichiers"
    correct: 2
    explanation: "Lancer un processus prend une fraction de seconde ; démarrer un système complet, bien plus."
  - prompt: "Que reste-t-il d'un conteneur arrêté ?"
    answers:
      - "Son processus, en attente"
      - "Sa fiche, ses logs et sa couche d'écriture, mais plus aucun processus"
      - "Rien : il est supprimé"
    correct: 2
    explanation: "`docker top` répond qu'il ne tourne pas, mais `docker ps -a` le liste, et `docker start` peut le relancer."
```

```ack
J'ai compris
```
