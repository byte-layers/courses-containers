---
title: "Pourquoi un orchestrateur"
description: "Compose fait tourner une application sur une machine. Un orchestrateur garde un état voulu sur plusieurs, et il le rétablit quand quelque chose tombe."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Pourquoi un orchestrateur

**Pour qui ?** Pour vous, si vous savez lancer une application avec Compose et que vous vous demandez ce qui vient après. Il vous faut Docker qui répond à `docker ps`, et le port **28390** libre.

Avec Compose, vous décrivez une application et elle tourne, sur **une** machine. Pour beaucoup de projets, cela suffit. Cette page montre où cela s'arrête, et ce qu'un **orchestrateur**, l'outil qui pilote des conteneurs sur plusieurs machines, apporte de plus.

## Les limites d'une seule machine

Quatre situations posent problème dès que l'application devient importante. Le tableau dit ce qui se passe avec une seule machine, et ce qu'on attend à la place.

| La situation | Sur une seule machine | Ce qu'on voudrait |
|---|---|---|
| La machine tombe en panne | tout s'arrête, jusqu'à ce qu'un humain intervienne | l'application repart ailleurs, sans intervention |
| Il faut plus de capacité | une machine plus grosse, avec une limite | plusieurs copies, sur plusieurs machines |
| Une nouvelle version arrive | une coupure, le temps de recréer les conteneurs | un remplacement progressif, sans coupure |
| La nouvelle version est mauvaise | on recommence à la main, dans l'urgence | un retour automatique à la version d'avant |

La politique `restart` n'aide que pour une partie de la première ligne : elle relance un conteneur qui s'arrête, mais sur la même machine. Si la machine tombe, elle tombe avec.

## Le constater

La deuxième ligne se voit tout de suite. Lancez un serveur web sur le port 28390 :

```exec
docker run -d --name layers-l9-copie1 -p 28390:80 nginx:1.30-alpine
```

Essayez maintenant d'en lancer une seconde copie sur le même port, pour répartir la charge. Docker va-t-il accepter ? Faites votre prévision avant de valider :

```exec
docker run -d --name layers-l9-copie2 -p 28390:80 nginx:1.30-alpine
```

Docker refuse, avec un message qui contient `port is already allocated`. Sur une machine, un port n'a qu'un seul propriétaire : pour avoir deux copies, il faudrait un second port et quelque chose devant pour répartir les requêtes. C'est précisément ce qu'un orchestrateur prend en charge. Rangez ces deux conteneurs ; le second existe, même s'il n'a pas pu démarrer :

```exec
docker rm -f layers-l9-copie1 layers-l9-copie2
```

## L'idée : un état voulu

Avec `docker run`, vous donnez des **ordres** : « lance ce conteneur ». Une fois l'ordre exécuté, personne ne s'occupe plus de savoir si le conteneur est toujours là.

Avec un orchestrateur, vous décrivez un **état voulu** : « je veux 3 copies de cette image, sur ce port ». L'orchestrateur compare sans arrêt cet état avec ce qu'il observe, et il corrige l'écart, comme le montre ce schéma.

```
   vous : « je veux 3 copies »
              │
              ▼
      ┌───────────────┐   3 voulues, 2 observées :
      │ orchestrateur │   il en démarre une de plus
      └───┬───────▲───┘
    agit  │       │  observe
          ▼       │
   ┌──────────────┴───┐
   │  les machines et │
   │  leurs conteneurs│
   └──────────────────┘
```

Ce changement explique tout le reste. Si un conteneur meurt, l'écart apparaît, et un autre démarre. Si une machine tombe, ses conteneurs manquent, et ils repartent sur les machines restantes. Pour changer de version, vous changez l'état voulu, et l'orchestrateur fait le chemin par étapes.

## Lequel choisir ?

Deux outils dominent, et ils partagent cette idée. Il vaut mieux commencer par le plus simple, et comprendre les notions avant d'affronter l'outil le plus riche.

| | Docker Swarm | Kubernetes |
|---|---|---|
| Installation | déjà dans Docker | un outil à part, à installer ou à louer |
| Fichier de description | le format de Compose, avec une section en plus | son propre format, plus long |
| Prise en main | quelques heures | plusieurs semaines |
| Écosystème | modeste | immense : c'est le standard de l'industrie |
| Convient à | une petite équipe, un petit cluster | une grande plateforme, beaucoup d'équipes |

Ce parcours utilise Swarm, qui est intégré à Docker, et réutilise ce que vous savez de Compose. Les notions d'état voulu, de réplique et de mise à jour progressive se retrouvent telles quelles dans Kubernetes, qui n'est pas traité ici.

## Il n'en faut pas toujours

Un orchestrateur a un coût : plusieurs machines à maintenir, un réseau de plus à comprendre, et davantage de façons de tomber en panne. Pour une application sur un seul serveur, avec une coupure de quelques secondes tolérable, Compose reste le bon choix.

> 📖 [Docker Swarm](https://docs.docker.com/engine/swarm/) · [Les notions de Swarm](https://docs.docker.com/engine/swarm/key-concepts/)

## Ce qu'il faut retenir

- Sur une seule machine, on ne peut ni survivre à sa panne ni multiplier les copies sur un même port.
- Un orchestrateur reçoit un état voulu, et il corrige sans cesse l'écart avec ce qu'il observe.
- Swarm est le plus simple à prendre en main, Kubernetes le plus répandu, et Compose suffit souvent.

```quiz
prompt: "Un service doit avoir 3 copies, et l'une d'elles s'arrête. Que fait un orchestrateur ?"
answers:
  - "Il prévient l'administrateur et attend sa décision"
  - "Il constate l'écart avec l'état voulu et démarre une nouvelle copie"
  - "Il arrête les deux autres copies, pour rester cohérent"
correct: 2
explanation: |
  Il compare en permanence l'état voulu avec ce qu'il observe, et il corrige l'écart sans qu'on le lui demande.
```

```ack
J'ai compris
```
