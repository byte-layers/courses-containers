---
title: "Configurer au lancement"
description: "Variables d'environnement, commande remplacée, limites de ressources"
---

Une même image sert à des usages différents : c'est au lancement qu'on l'adapte. Tout passe par des options placées **avant** le nom de l'image, et la commande éventuelle vient **après**.

```
docker run [options] image [commande]
```

## Passer une variable d'environnement

La plupart des images se configurent par des **variables d'environnement**, des paires nom et valeur que le processus peut lire. `-e` en définit une :

```exec
docker run --rm -e PRENOM=Ada alpine:3.22 sh -c 'echo "Bonjour $PRENOM"'
```

`sh -c` est nécessaire ici : c'est le shell du conteneur qui remplace `$PRENOM` par sa valeur, et les apostrophes empêchent votre propre shell de le faire avant lui.

```ack
J'ai lu « Bonjour Ada »
```

## Remplacer la commande

Une image prévoit une commande par défaut. `docker image inspect` lit sa fiche, et `--format` en extrait un champ :

```exec
docker image inspect alpine:3.22 --format '{{json .Config.Cmd}}'
```

C'est `/bin/sh`, présenté comme une liste. Tout ce que vous écrivez après le nom de l'image la remplace, ce que vous faites depuis le début :

```exec
docker run --rm alpine:3.22 echo "cette commande remplace /bin/sh"
```

```ack
Je sais où mettre la commande
```

## Limiter les ressources

Sans limite, un conteneur peut consommer toute la mémoire de la machine. `--memory` et `--cpus` posent ces limites, ici 64 Mio et la moitié d'un cœur de processeur. L'image est celle de nginx, un serveur web, qui tourne tout seul en arrière-plan :

```exec
docker run -d --name layers-l1-limited --memory 64m --cpus 0.5 nginx:1.30-alpine
```

`docker stats` affiche la consommation. `--no-stream` donne une seule mesure, sans occuper votre terminal :

```exec
docker stats --no-stream layers-l1-limited
```

Dans la colonne `MEM USAGE / LIMIT`, la limite affichée est `64MiB`, et non la mémoire de votre machine.

```verify
MEM=$(docker inspect layers-l1-limited --format '{{.HostConfig.Memory}}' 2>/dev/null)
CPU=$(docker inspect layers-l1-limited --format '{{.HostConfig.NanoCpus}}' 2>/dev/null)
if [ "$MEM" != "67108864" ] || [ "$CPU" != "500000000" ]; then
  echo "layers-l1-limited n'a pas les limites attendues (mémoire : ${MEM:-aucune}, CPU : ${CPU:-aucun})."
  echo "Supprimez-le (docker rm -f layers-l1-limited) et relancez la commande."
  exit 1
fi
echo "Limites en place : 64 Mio et un demi-CPU."
```

Supprimez le conteneur :

```exec
docker rm -f layers-l1-limited
```

```verify
if docker container inspect layers-l1-limited >/dev/null 2>&1; then
  echo "layers-l1-limited existe encore. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

## Questions

```quiz
title: "Configurer au lancement"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Où placer l'option `-e` dans `docker run` ?"
    answers:
      - "Avant le nom de l'image"
      - "Après le nom de l'image"
      - "Où l'on veut"
    correct: 1
    explanation: "Tout ce qui suit le nom de l'image est la commande du conteneur : `docker run alpine:3.22 -e X=1` tenterait d'exécuter `-e`."
  - prompt: "Sans `--memory`, combien de mémoire un conteneur peut-il utiliser ?"
    answers:
      - "64 Mo par défaut"
      - "Autant que l'hôte en a de disponible"
      - "La moitié de la mémoire de l'hôte"
    correct: 2
    explanation: "Il n'y a aucune limite par défaut : un seul conteneur peut donc affamer tous les autres."
```
