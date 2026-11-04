---
title: "Le conteneur est jetable"
description: "Un conteneur se supprime et se remplace sans regret, à condition de ne rien y garder de précieux. Cette idée décide de l'endroit où vont vos données."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Le conteneur est jetable

**Pour qui ?** Pour vous, si vous savez lancer un conteneur et utiliser `docker exec` : le cours « Lancer, configurer et observer un conteneur » suffit. Il faut que `docker ps` réponde.

Sur une machine classique, on installe un logiciel une fois, puis on le soigne : on le met à jour sur place, on le répare, on garde ses fichiers au même endroit pendant des années. Un conteneur fonctionne à l'inverse. Pour le mettre à jour ou le reconfigurer, on le **supprime et on en crée un autre** depuis une image. On dit qu'il est **jetable**.

Tout conteneur a une **couche d'écriture**, l'espace où il garde ses modifications au-dessus de son image. Elle disparaît avec lui. Un conteneur peut donc disparaître à tout moment sans regret, à une condition : **rien de précieux ne doit y être resté**. Voici ce qui arrive à cette couche selon le geste que vous faites :

| Geste | Le conteneur | Sa couche d'écriture |
|---|---|---|
| `docker stop`, puis `docker start` | le même | conservée |
| `docker restart` | le même | conservée |
| `docker rm`, puis `docker run` | un nouveau | perdue |

## Le constater

Ce tableau rappelle les commandes utiles, et le cours « Lancer, configurer et observer un conteneur » les détaille.

| Élément | Rôle |
|---|---|
| `docker run -d --name x` | lance un conteneur en arrière-plan, avec un nom fixe |
| `sleep 3600` | la commande du conteneur : elle attend une heure, ce qui le garde en vie |
| `docker exec x sh -c '…'` | fait exécuter la phrase entre apostrophes par un shell dans le conteneur |
| `docker rm -f` | supprime un conteneur, même s'il tourne |

Si un téléchargement échoue avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub pour les téléchargements anonymes. Attendez, ou créez un compte gratuit et lancez `docker login`.

Lancez un conteneur et écrivez-y une donnée, puis relisez-la après un redémarrage :

```exec
docker run -d --name layers-l6-note alpine:3.22 sleep 3600
docker exec layers-l6-note sh -c 'echo précieux > /root/note.txt'
docker restart -t 1 layers-l6-note
docker exec layers-l6-note cat /root/note.txt
```

Vous lisez `précieux` : un redémarrage garde la couche d'écriture, car c'est le même conteneur. `-t 1` limite à une seconde l'attente de l'arrêt. Remplacez maintenant ce conteneur par un neuf, ce qui est le geste d'une mise à jour. Avant de lancer ces commandes, faites une prévision : la note sera-t-elle encore là ?

```exec
docker rm -f layers-l6-note
docker run -d --name layers-l6-note alpine:3.22 sleep 3600
docker exec layers-l6-note cat /root/note.txt
```

Vous lisez `No such file or directory`. Le nom est le même, l'image aussi, mais la donnée a disparu avec l'ancien conteneur.

## Chaque chose à sa place

Ce comportement n'est pas un défaut à contourner. C'est lui qui permet de remplacer un conteneur en une seconde, d'en lancer dix identiques, ou de redémarrer sans se demander dans quel état on l'a laissé. La bonne question devient donc : où ranger ce qui ne doit pas disparaître ?

| Ce que c'est | Où cela va | Pourquoi |
|---|---|---|
| le code et ses dépendances | l'image | identiques à chaque création |
| la configuration | les options de `docker run`, comme `-e` | changer de configuration, c'est recréer |
| les logs | la sortie standard, lue par `docker logs` | Docker les recueille, rien à conserver dans le conteneur |
| **les données** (base, fichiers envoyés) | **hors du conteneur, dans un volume** | elles doivent survivre au remplacement |

Un **volume** est un espace de stockage géré par Docker, qui existe indépendamment des conteneurs. Voici un premier aperçu : `-v` branche le volume sur un dossier du conteneur, et il est créé s'il n'existe pas. Un conteneur y écrit puis disparaît, grâce à `--rm`, et un autre conteneur relit le fichier :

```exec
docker run --rm -v layers-l6-apercu:/data alpine:3.22 sh -c 'echo précieux > /data/note.txt'
docker run --rm -v layers-l6-apercu:/data alpine:3.22 cat /data/note.txt
```

Vous lisez `précieux` : la donnée a survécu à deux conteneurs. Le cours « Garder ses données : volumes et bind mounts » détaille tout cela. Rangez ce que vous avez créé, car un volume n'est jamais supprimé tout seul :

```exec
docker rm -f layers-l6-note
docker volume rm layers-l6-apercu
```

> 📖 [Persister les données d'un conteneur](https://docs.docker.com/get-started/docker-concepts/running-containers/persisting-container-data/) · [Le stockage dans Docker](https://docs.docker.com/engine/storage/)

## Ce qu'il faut retenir

- Mettre à jour un conteneur, c'est le supprimer et en créer un autre.
- Ce qui reste dans la couche d'écriture disparaît avec le conteneur : `restart` la garde, `rm` l'efface.
- Le code va dans l'image, la configuration dans les options, les logs sur la sortie standard, et les données dans un volume.

```quiz
prompt: "Vous redémarrez une base de données conteneurisée avec `docker restart`, et ses données sont intactes. Votre collègue en conclut que le conteneur suffit à les garder. Que lui répondez-vous ?"
answers:
  - "Il a raison : les données restent tant que l'image existe"
  - "Le redémarrage garde la couche d'écriture, mais une mise à jour remplace le conteneur et l'efface : il faut un volume"
  - "Il a tort : `docker restart` efface toujours les données, il a eu de la chance"
correct: 2
explanation: |
  `restart` garde le même conteneur. Le risque arrive au premier `docker rm`, qui est le geste normal d'une mise à jour.
```

```ack
J'ai compris
```
