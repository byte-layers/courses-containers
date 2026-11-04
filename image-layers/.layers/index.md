---
title: "Couches et copy-on-write"
description: "Une image est un empilement de couches en lecture seule, partagées entre images. Un fichier modifié dans un conteneur est d'abord copié dans sa couche d'écriture."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Couches et copy-on-write

**Pour qui ?** Pour vous, si vous savez écrire un Dockerfile simple et construire une image avec `docker build`, ce qu'enseigne le cours « Écrire le Dockerfile d'une application ». Vous savez aussi qu'un conteneur écrit dans sa propre couche d'écriture, ce que rappelle « L'image est immuable ». Ce cours se lit avant « Accélérer un build avec le cache » et « Réduire une image avec le multi-stage » : il explique le mécanisme qu'ils exploitent.

Une image n'est pas un gros fichier d'un seul tenant. C'est un **empilement de couches**, et chaque couche ne contient que la différence avec celle du dessous : ce qui a été ajouté, modifié ou supprimé. Une instruction du Dockerfile qui touche aux fichiers, comme `RUN` ou `COPY`, produit une nouvelle couche. Le conteneur ajoute sa couche d'écriture au sommet de la pile, et un mécanisme de Linux présente le tout comme un seul système de fichiers.

Ce schéma montre l'image que vous allez construire, avec le conteneur au-dessus d'elle :

```
┌─────────────────────────────┐
│ couche d'écriture           │  propre au conteneur, supprimée avec lui
├─────────────────────────────┤
│ RUN rm /gros.bin            │  note que le fichier est supprimé
├─────────────────────────────┤
│ RUN head … > /gros.bin      │  ajoute un fichier de 30 Mo
├─────────────────────────────┤
│ FROM alpine:3.22            │  les couches de l'image de base
└─────────────────────────────┘
       image : lecture seule, partagée
```

## Voir les couches d'une image

Créez un dossier et un Dockerfile de démonstration. `head -c 30000000 /dev/urandom` produit 30 millions d'octets aléatoires : c'est un gros fichier qui ne se compresse pas. La ligne suivante le supprime aussitôt.

```exec
mkdir -p ~/layers-l3/layers
cat > ~/layers-l3/layers/Dockerfile <<'EOF'
FROM alpine:3.22
RUN head -c 30000000 /dev/urandom > /gros.bin
RUN rm /gros.bin
EOF
```

Construisez l'image, puis lisez ses couches avec `docker history`, du sommet vers la base. `-q` réduit la sortie de `docker build` à l'identifiant de l'image, et `--format` ne garde de l'historique que la taille et l'instruction d'origine :

```exec
docker build -q -t layers-l3-gros:1.0 ~/layers-l3/layers
docker history layers-l3-gros:1.0 --format '{{.Size}}  {{.CreatedBy}}'
```

Vous lisez une ligne par instruction du Dockerfile, puis celles de l'image de base. La couche de `head` pèse `30MB`, et celle de `rm` presque rien. Une ligne à `0B`, comme le `CMD` hérité d'Alpine, ne change aucun fichier : elle ne touche qu'à la configuration de l'image.

## Supprimer ne fait pas maigrir

Le fichier a pourtant disparu de l'image finale. Vérifiez-le, puis regardez le poids de l'image avec `docker images` :

```exec
docker run --rm layers-l3-gros:1.0 ls /gros.bin
docker images layers-l3-gros
docker images alpine:3.22
```

`ls` répond que le fichier n'existe pas, et l'image pèse pourtant au moins 30 Mo de plus qu'Alpine. La raison vient de l'empilement : une couche ne se modifie jamais. `rm` a donc seulement ajouté une marque qui masque le fichier, et les 30 Mo restent dans la couche du dessous.

Ce qui est fait dans une même couche, en revanche, ne laisse pas de trace. `&&` enchaîne les deux commandes dans une seule instruction `RUN` :

```exec
cat > ~/layers-l3/layers/Dockerfile <<'EOF'
FROM alpine:3.22
RUN head -c 30000000 /dev/urandom > /gros.bin && rm /gros.bin
EOF
docker build -q -t layers-l3-gros:1.1 ~/layers-l3/layers
docker images layers-l3-gros
docker images alpine:3.22
```

La version `1.1` ne pèse pas plus lourd qu'Alpine. Docker Desktop et un moteur Linux ne comptent pas les tailles de la même façon, donc vos chiffres peuvent différer d'une machine à l'autre : c'est l'écart entre les deux versions qui compte, d'au moins 30 Mo.

## Les couches se partagent

Une couche se reconnaît à son empreinte, le `sha256:` calculé sur son contenu, et Docker ne la stocke qu'une fois. `.RootFS.Layers` liste les empreintes d'une image. Comparez la version `1.0` et son image de base :

```exec
docker image inspect alpine:3.22 --format '{{json .RootFS.Layers}}'
docker image inspect layers-l3-gros:1.0 --format '{{json .RootFS.Layers}}'
```

La première empreinte est identique sur les deux lignes : dix images construites sur `alpine:3.22` ne stockent donc Alpine qu'une fois, et ne la téléchargent qu'une fois.

## Copier au moment d'écrire

Reste à comprendre comment un conteneur modifie un fichier qui appartient à une couche en lecture seule. Il ne le peut pas directement : le fichier **entier** est d'abord copié dans sa couche d'écriture, puis modifié là. C'est le **copy-on-write**, « copier à l'écriture ».

Pour l'observer, il vous faut une image qui garde son gros fichier, et un conteneur que `sleep 3600` maintient en vie pendant une heure :

```exec
cat > ~/layers-l3/layers/Dockerfile <<'EOF'
FROM alpine:3.22
RUN head -c 30000000 /dev/urandom > /gros.bin
EOF
docker build -q -t layers-l3-cow:1.0 ~/layers-l3/layers
docker run -d --name layers-l3-cow layers-l3-cow:1.0 sleep 3600
```

`docker ps -s` affiche la taille de la couche d'écriture, et entre parenthèses la taille totale vue par le conteneur. `--filter` ne retient que le vôtre. Mesurez après une lecture complète du fichier, où `wc -c` en compte les octets :

```exec
docker exec layers-l3-cow wc -c /gros.bin
docker ps -s --filter name=layers-l3-cow --format '{{.Size}}'
```

Le fichier fait 30 Mo, et la couche d'écriture est presque vide : lire ne copie rien. Ajoutez maintenant une seule ligne à ce fichier, puis mesurez encore :

```exec
docker exec layers-l3-cow sh -c 'echo x >> /gros.bin'
docker ps -s --filter name=layers-l3-cow --format '{{.Size}}'
```

Vous lisez `30MB` : pour écrire deux octets, le conteneur a dû copier les 30 Mo. `docker diff` confirme que `/gros.bin` a changé, avec la lettre `C` :

```exec
docker diff layers-l3-cow
```

Voilà pourquoi un conteneur démarre vite et n'occupe presque rien tant qu'il n'écrit pas, et aussi pourquoi une application qui écrit beaucoup dans de gros fichiers, comme une base de données, ne doit pas le faire dans cette couche. Un prochain cours, « Garder ses données », montre où le faire.

Il reste à ranger ce que vous avez créé :

```exec
docker rm -f layers-l3-cow
docker image rm layers-l3-gros:1.0 layers-l3-gros:1.1 layers-l3-cow:1.0
rm -rf ~/layers-l3/layers
```

> 📖 [Comprendre les couches d'une image](https://docs.docker.com/get-started/docker-concepts/building-images/understanding-image-layers/) · [Les pilotes de stockage et le copy-on-write](https://docs.docker.com/engine/storage/drivers/) · [`docker history`](https://docs.docker.com/reference/cli/docker/image/history/)

## Ce qu'il faut retenir

- Une image est un empilement de couches en lecture seule, et chaque instruction qui touche aux fichiers en ajoute une.
- Une couche ne se modifie jamais : supprimer un fichier dans une couche suivante ne fait pas maigrir l'image.
- Deux images qui ont une couche en commun ne la stockent qu'une fois.
- Un conteneur copie un fichier entier dans sa couche d'écriture au moment de le modifier, et lire ne copie rien.

```quiz
title: "Couches et copy-on-write"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un Dockerfile télécharge une archive de 200 Mo dans un `RUN`, puis la supprime dans le `RUN` suivant. Que pèse cette archive dans l'image finale ?"
    answers:
      - "Rien, elle a été supprimée"
      - "200 Mo : la couche qui la contient existe toujours, et la suivante ne fait que la masquer"
      - "100 Mo : les deux couches s'équilibrent"
    correct: 2
    explanation: "Une couche ne change jamais. Pour ne rien laisser, il faut télécharger et supprimer dans le même `RUN`."
  - prompt: "Un conteneur ajoute une ligne à la fin d'un fichier de 1 Go qui vient de son image. Qu'occupe sa couche d'écriture ?"
    answers:
      - "Une ligne"
      - "Environ 1 Go : le fichier entier y est copié avant d'être modifié"
      - "Rien : l'image est modifiée à la place"
    correct: 2
    explanation: "C'est le copy-on-write. L'image reste en lecture seule, et le fichier est d'abord copié entièrement."
  - prompt: "Dix images ont été construites sur `alpine:3.22`. Combien de fois les couches d'Alpine sont-elles stockées ?"
    answers:
      - "Une fois"
      - "Dix fois"
      - "Une fois par conteneur lancé"
    correct: 1
    explanation: "Une couche se reconnaît à l'empreinte de son contenu, et Docker ne la garde qu'en un exemplaire."
```

```ack
J'ai compris
```
