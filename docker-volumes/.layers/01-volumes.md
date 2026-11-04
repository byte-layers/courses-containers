---
title: "Les volumes"
description: "Créer, brancher, partager et supprimer un volume, et repérer les volumes anonymes"
---

Un **volume** est un espace de stockage géré par Docker, qui vit en dehors de tout conteneur. On le branche sur un dossier du conteneur, appelé **point de montage** : ce que le programme y écrit va dans le volume et non dans sa couche d'écriture. Le conteneur peut alors disparaître sans emporter les données.

## Créer un volume et y écrire

`docker volume create` crée un volume vide et lui donne un nom. `--filter name=` limite ensuite la liste aux volumes dont le nom contient ce texte :

```exec
docker volume create layers-l6-data
docker volume ls --filter name=layers-l6-data
```

L'option `-v <volume>:<dossier du conteneur>` branche ce volume au lancement. Écrivez un fichier depuis un premier conteneur. `--rm` le supprime dès qu'il a terminé :

```exec
docker run --rm -v layers-l6-data:/data alpine:3.22 sh -c 'echo bonjour > /data/note.txt'
```

Ce conteneur n'existe plus. Lisez maintenant le fichier depuis un second conteneur, tout neuf :

```exec
docker run --rm -v layers-l6-data:/data alpine:3.22 cat /data/note.txt
```

Vous lisez `bonjour` : la donnée a survécu à son conteneur.

```verify
if ! docker volume inspect layers-l6-data >/dev/null 2>&1; then
  echo "Le volume layers-l6-data n'existe pas. Lancez la première commande de cette section."
  exit 1
fi
if ! docker run --rm -v layers-l6-data:/data alpine:3.22 cat /data/note.txt 2>/dev/null | grep -q bonjour; then
  echo "Le fichier note.txt n'est pas dans le volume. Lancez la commande qui l'écrit."
  exit 1
fi
echo "Le volume garde note.txt."
```

## Où est-il rangé ?

Docker choisit l'emplacement du volume. `docker volume inspect` le montre, et `--format` n'affiche ici que le nom et ce chemin, appelé `Mountpoint` :

```exec
docker volume inspect layers-l6-data --format '{{.Name}} : {{.Mountpoint}}'
```

Vous lisez un chemin sous `/var/lib/docker/volumes/`. Il appartient à Docker, et il ne faut pas y écrire à la main. Sur Docker Desktop, il n'existe même pas sur votre Mac ou votre PC, car Docker y tourne dans une machine virtuelle. On accède donc à un volume **toujours par un conteneur**, comme vous venez de le faire.

## Deux écritures pour le même geste

Une seconde option fait la même chose que `-v`, en plus explicite : `--mount`. Comparez-les sur le même exemple :

| Écriture | Exemple |
|---|---|
| `-v` | `-v layers-l6-data:/data` |
| `--mount` | `--mount type=volume,src=layers-l6-data,dst=/data` |

`--mount` est plus long, mais chaque élément est nommé : `src`, la source, ici le volume, et `dst`, la destination dans le conteneur. Il est donc plus lisible dans un script. Les deux écritures sont valables, et ce cours utilise `-v` pour rester court. Relisez le fichier avec la seconde :

```exec
docker run --rm --mount type=volume,src=layers-l6-data,dst=/data alpine:3.22 cat /data/note.txt
```

## Partager, en lecture seule si besoin

Un volume peut être branché sur plusieurs conteneurs à la fois. Celui qui n'a qu'à lire le reçoit avec `:ro`, pour *read-only* : il ne pourra rien abîmer. Essayez d'écrire avec cette option :

```exec
docker run --rm -v layers-l6-data:/data:ro alpine:3.22 sh -c 'echo pirate > /data/note.txt'
```

Vous lisez `Read-only file system`, et le fichier n'a pas changé.

```verify
if ! docker volume inspect layers-l6-data >/dev/null 2>&1 || ! docker run --rm -v layers-l6-data:/data alpine:3.22 cat /data/note.txt 2>/dev/null | grep -q bonjour; then
  echo "note.txt ne contient plus bonjour. Récrivez-le : docker run --rm -v layers-l6-data:/data alpine:3.22 sh -c 'echo bonjour > /data/note.txt'"
  exit 1
fi
echo "note.txt est intact."
```

## Un volume neuf reçoit le contenu de l'image

Que se passe-t-il si l'on branche un volume sur un dossier où l'image contient déjà des fichiers ? Docker **recopie ces fichiers dans le volume s'il est vide**. Lancez nginx en branchant un volume neuf sur son dossier de pages, puis listez ce dossier. `-v` crée le volume s'il n'existe pas encore :

```exec
docker run --rm -v layers-l6-html:/usr/share/nginx/html nginx:1.30-alpine ls /usr/share/nginx/html
```

Vous lisez `50x.html` et `index.html`, qui viennent de l'image. Une image peut ainsi fournir des fichiers de départ, que le volume conserve ensuite. Le comportement d'un dossier de votre machine sera différent, comme le montre l'étape suivante.

```verify
if ! docker volume inspect layers-l6-html >/dev/null 2>&1 || ! docker run --rm -v layers-l6-html:/h alpine:3.22 ls /h 2>/dev/null | grep -q index.html; then
  echo "Le volume layers-l6-html ne contient pas les pages de nginx. Lancez la commande de cette section."
  exit 1
fi
echo "Le volume layers-l6-html a reçu les fichiers de l'image."
```

## Les volumes anonymes

Certaines images demandent d'elles-mêmes un volume pour leurs données, avec l'instruction `VOLUME` de leur Dockerfile. C'est le cas de MySQL, comme le montre sa fiche. `docker pull` télécharge d'abord l'image, car `docker image inspect` ne lit que les images présentes sur votre machine, et `{{json …}}` affiche le champ tel quel :

```exec
docker pull mysql:8.4
docker image inspect mysql:8.4 --format '{{json .Config.Volumes}}'
```

Si vous n'en fournissez pas, Docker en crée un au nom illisible, appelé **volume anonyme**. `docker create` crée un conteneur sans le démarrer, ce qui suffit pour l'observer. `{{range .Mounts}}` parcourt ce qui est branché sur le conteneur :

```exec
docker create --name layers-l6-anon mysql:8.4
docker inspect layers-l6-anon --format '{{range .Mounts}}{{.Type}} {{.Name}} {{.Destination}}{{end}}'
```

Le nom est une longue suite de chiffres et de lettres, que personne ne retrouvera. Ce volume reste sur le disque après un simple `docker rm`. L'option `-v` de `docker rm` le supprime avec le conteneur, et il vaut mieux y penser à chaque fois que l'image en déclare un. Cette option ne touche pas aux volumes nommés :

```exec
docker rm -v layers-l6-anon
```

```verify
if docker container inspect layers-l6-anon >/dev/null 2>&1; then
  echo "layers-l6-anon existe encore. Lancez : docker rm -v layers-l6-anon"
  exit 1
fi
echo "Le conteneur est supprimé. Si vous avez utilisé -v, son volume anonyme l'est aussi."
```

## Supprimer un volume

Un volume ne disparaît jamais tout seul, et Docker refuse de supprimer un volume utilisé. Vérifiez-le avec un conteneur qui garde `layers-l6-html` branché, en tentant de le supprimer :

```exec
docker run -d --name layers-l6-occupe -v layers-l6-html:/h alpine:3.22 sleep 3600
docker volume rm layers-l6-html
```

Vous lisez `volume is in use`. Supprimez d'abord le conteneur, puis le volume. Le volume `layers-l6-data` reste en place, car il servira à la dernière étape :

```exec
docker rm -f layers-l6-occupe
docker volume rm layers-l6-html
```

```verify
if docker container inspect layers-l6-occupe >/dev/null 2>&1 || docker volume inspect layers-l6-html >/dev/null 2>&1; then
  echo "layers-l6-occupe ou layers-l6-html existe encore. Lancez les deux commandes ci-dessus."
  exit 1
fi
echo "C'est propre, et layers-l6-data reste pour la suite."
```

> 📖 [Les volumes](https://docs.docker.com/engine/storage/volumes/) · [`docker volume`](https://docs.docker.com/reference/cli/docker/volume/) · [`docker volume rm`](https://docs.docker.com/reference/cli/docker/volume/rm/)

## Questions

```quiz
title: "Les volumes"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Vous supprimez un conteneur lancé avec `-v donnees:/data`, sans autre option. Que devient le volume `donnees` ?"
    answers:
      - "Il est supprimé avec le conteneur"
      - "Il reste intact, et un nouveau conteneur peut s'y brancher"
      - "Il reste, mais vide"
    correct: 2
    explanation: "Un volume nommé vit indépendamment des conteneurs. C'est tout son intérêt."
  - prompt: "Vous branchez un volume neuf sur `/usr/share/nginx/html`, où l'image nginx contient deux pages. Que contient le volume ensuite ?"
    answers:
      - "Les deux pages, car Docker recopie dans un volume vide ce que l'image contient à cet endroit"
      - "Rien, car un volume neuf reste vide tant qu'un programme n'y écrit pas"
      - "Une copie complète de tous les fichiers de l'image, à partir de sa racine"
    correct: 1
    explanation: "Seul le contenu du dossier concerné est recopié, et seulement si le volume est vide."
  - prompt: "`docker ps -a` est vide, mais `docker volume ls` liste des volumes aux noms illisibles. D'où viennent-ils ?"
    answers:
      - "De conteneurs dont l'image déclare `VOLUME`, supprimés sans l'option `-v`"
      - "Du cache de construction"
      - "De réseaux supprimés"
    correct: 1
    explanation: "Ce sont des volumes anonymes. `docker rm -v` les aurait supprimés avec leur conteneur."
  - prompt: "Comment lire un fichier d'un volume, de façon fiable sur toutes les installations de Docker ?"
    answers:
      - "En ouvrant `/var/lib/docker/volumes/` sur votre machine"
      - "En le lisant depuis un conteneur sur lequel le volume est branché"
      - "Avec `docker volume cat`"
    correct: 2
    explanation: "L'emplacement appartient à Docker, et sur Docker Desktop il n'est même pas sur votre système. `docker volume cat` n'existe pas."
```
