---
title: "Nommer et pousser une image"
description: "L'erreur d'un push sans le bon nom, docker tag qui le pose, docker push qui envoie"
---

Votre registre est prêt et vide. Il vous faut une image à y mettre, et un nom qui dit à Docker où l'envoyer.

## Construire une image à publier

Créez un dossier de travail et, dedans, un Dockerfile minimal. Cette image affiche simplement son numéro de version, ce qui permettra de reconnaître plus tard laquelle on a sous les yeux :

```exec
mkdir -p ~/byte-layers/docker/l4/app
cat > ~/byte-layers/docker/l4/app/Dockerfile <<'EOF'
FROM alpine:3.22
CMD ["echo", "Bonjour depuis la version 1"]
EOF
```

Construisez-la, puis lancez-la pour vérifier qu'elle dit ce qu'on attend :

```exec
docker build -t layers-l4-hello:1.0 ~/byte-layers/docker/l4/app
docker run --rm layers-l4-hello:1.0
```

Vous devez lire `Bonjour depuis la version 1`. Cette image n'existe pour l'instant que sur votre machine.

```verify
if ! docker image inspect layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l4-hello:1.0 n'existe pas. Lancez le docker build de cette section."
  exit 1
fi
if ! docker run --rm layers-l4-hello:1.0 | grep -q 'version 1'; then
  echo "L'image n'affiche pas le texte attendu. Vérifiez le Dockerfile, puis reconstruisez-la."
  exit 1
fi
echo "L'image layers-l4-hello:1.0 est construite."
```

## Essayer de pousser, et lire l'erreur

Publier une image se dit **pousser** : `push`. `docker push` ne prend pas de destination, car il la lit dans le nom de l'image, et un nom qui vise votre registre commence par son adresse. Essayez donc d'envoyer votre image à l'adresse de votre registre :

```exec
docker push localhost:28340/layers-l4-hello:1.0
```

Docker refuse. Selon votre installation, le message prend l'une de deux formes, qui disent la même chose. Sur certaines, vous lisez ceci :

```text
The push refers to repository [localhost:28340/layers-l4-hello]
tag does not exist: localhost:28340/layers-l4-hello:1.0
```

Sur d'autres installations, la seconde ligne est formulée ainsi :

```text
The push refers to repository [localhost:28340/layers-l4-hello]
An image does not exist locally with the tag: localhost:28340/layers-l4-hello
```

Sur votre machine, aucune image ne porte ce nom : la vôtre s'appelle `layers-l4-hello:1.0`. Et ce nom-là ne conviendrait pas non plus, car sans adresse au début, Docker comprendrait qu'il faut l'envoyer sur Docker Hub, où vous n'avez aucun droit d'écriture.

## Donner à l'image le nom de son registre avec docker tag

Il faut donc que l'image porte un nom qui commence par l'adresse du registre. C'est le rôle de `docker tag`, qui pose un nom de plus sur la même image :

```exec
docker tag layers-l4-hello:1.0 localhost:28340/layers-l4-hello:1.0
```

Ce nom se lit morceau par morceau :

| Morceau | Rôle |
|---|---|
| `localhost:28340` | le registre, votre conteneur |
| `layers-l4-hello` | le dépôt, qui sera créé à la première publication |
| `1.0` | le tag, la version publiée |

Listez vos images. `docker images` affiche tout, et le `|` passe cette liste à `grep`, qui ne garde que les lignes contenant ce mot :

```exec
docker images | grep layers-l4-hello
```

Vous avez deux noms, et la colonne de l'identifiant montre la même valeur sur les deux lignes. C'est la même image, sans aucune copie. La date et la taille dépendent de votre installation :

```text
localhost:28340/layers-l4-hello   1.0       7eb048320768   2 weeks ago   13.3MB
layers-l4-hello                   1.0       7eb048320768   2 weeks ago   13.3MB
```

```verify
if ! docker image inspect localhost:28340/layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "L'image n'a pas encore le nom localhost:28340/layers-l4-hello:1.0. Lancez docker tag."
  exit 1
fi
A=$(docker image inspect layers-l4-hello:1.0 --format '{{.Id}}' 2>/dev/null)
B=$(docker image inspect localhost:28340/layers-l4-hello:1.0 --format '{{.Id}}')
if [ "$A" != "$B" ]; then
  echo "Les deux noms ne désignent pas la même image. Reprenez le docker tag."
  exit 1
fi
echo "Les deux noms désignent la même image."
```

## Pousser l'image, et demander au registre ce qu'il contient

Relancez la même commande que tout à l'heure. Cette fois, le nom existe :

```exec
docker push localhost:28340/layers-l4-hello:1.0
```

Une image est un empilement de **couches** (*layers*) : chaque instruction du Dockerfile qui change des fichiers en ajoute une sur celles de sa base. Ici, `CMD` n'en ajoute aucune, et votre image se compose des couches d'`alpine:3.22` et de sa fiche ; [Couches et copy-on-write](https://byte-layers.com/fr/bits/image-layers) en donne le détail. Docker envoie ces morceaux un par un, leur nombre dépend de votre installation, puis il termine par le digest, l'empreinte de l'image telle que le registre la connaît désormais :

```text
d4660173dd5c: Pushed
281d5a96263b: Pushed
1.0: digest: sha256:7eb048320768fb5057b1bceb27e94612ca483caf8fc66f9f7a28c4ac9ea9de32 size: 855
```

Vos identifiants et votre digest seront différents. Demandez maintenant au registre ce qu'il contient, d'abord ses dépôts, puis les tags de votre dépôt :

```exec
curl http://localhost:28340/v2/_catalog
curl http://localhost:28340/v2/layers-l4-hello/tags/list
```

Votre image est publiée :

```text
{"repositories":["layers-l4-hello"]}
{"name":"layers-l4-hello","tags":["1.0"]}
```

```verify
if ! curl -s --max-time 5 http://localhost:28340/v2/layers-l4-hello/tags/list | grep -q '"1.0"'; then
  echo "Le registre ne connaît pas le tag 1.0 du dépôt layers-l4-hello. Lancez le docker push."
  exit 1
fi
echo "Le registre contient layers-l4-hello:1.0."
```

## Pousser une seconde fois : rien n'est renvoyé

Poussez à nouveau la même image, sans rien changer, et regardez ce qui diffère :

```exec
docker push localhost:28340/layers-l4-hello:1.0
```

Les couches sont maintenant marquées comme déjà présentes, et rien n'est renvoyé :

```text
281d5a96263b: Layer already exists
d4660173dd5c: Already exists
1.0: digest: sha256:7eb048320768fb5057b1bceb27e94612ca483caf8fc66f9f7a28c4ac9ea9de32 size: 855
```

Un registre ne stocke chaque couche qu'une fois, ce qui rend les publications suivantes rapides et explique pourquoi un dépôt de cent versions ne pèse pas cent images.

## Publier la même image sous un second tag

Une même image peut porter plusieurs tags, et il est courant de lui en donner plusieurs pour que chacun choisisse à quel point il veut suivre les nouveautés. Publiez-la aussi sous le tag `latest`, que l'on évite pour lancer une image, mais que l'on publie pour ceux qui le demandent :

```exec
docker tag layers-l4-hello:1.0 localhost:28340/layers-l4-hello:latest
docker push localhost:28340/layers-l4-hello:latest
curl http://localhost:28340/v2/layers-l4-hello/tags/list
```

Le registre connaît maintenant les deux tags :

```text
{"name":"layers-l4-hello","tags":["1.0","latest"]}
```

Le digest affiché est le même, et les couches n'ont pas été renvoyées : c'est la même image, avec deux étiquettes. Rien n'a déplacé `latest` tout seul, c'est votre commande qui l'a fait. S'il vous arrive de publier une nouvelle version sans déplacer ce tag, `latest` restera sur l'ancienne.

```verify
TAGS=$(curl -s --max-time 5 http://localhost:28340/v2/layers-l4-hello/tags/list)
case "$TAGS" in
  *'"latest"'*) : ;;
  *) echo "Le registre ne connaît pas le tag latest. Lancez les commandes de cette section."; exit 1 ;;
esac
echo "L'image est publiée sous deux tags."
```

> 📖 [`docker tag`](https://docs.docker.com/reference/cli/docker/image/tag/) · [`docker push`](https://docs.docker.com/reference/cli/docker/image/push/) · [L'API du registre](https://distribution.github.io/distribution/spec/api/)

## Récap

- `docker push` lit sa destination dans le nom de l'image : `docker tag` sert à écrire ce nom.
- Un registre ne stocke chaque couche qu'une fois.
- Une image peut porter plusieurs tags, et chacun n'est qu'une étiquette.

## Questions

```quiz
title: "Pousser une image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Comment Docker sait-il vers quel registre envoyer une image avec `docker push` ?"
    answers:
      - "Il le lit au début du nom de l'image, et prend Docker Hub s'il n'y en a pas"
      - "Grâce à une option `--registry`"
      - "Il l'envoie à tous les registres connus"
    correct: 1
    explanation: "C'est pour cela qu'on pose d'abord un nom complet avec `docker tag`."
  - prompt: "`docker tag app:1.0 localhost:28340/app:1.0` a-t-il copié l'image ?"
    answers:
      - "Oui, l'espace occupé double"
      - "Oui, et il l'a envoyée au registre"
      - "Non : c'est un nom de plus sur la même image"
    correct: 3
    explanation: "Un tag est une étiquette. Rien ne part vers le registre avant le `docker push`."
  - prompt: "Vous repoussez une image dont seule la dernière couche a changé. Que part vers le registre ?"
    answers:
      - "Toute l'image"
      - "Seule la couche nouvelle : le registre a déjà les autres"
      - "Rien, tant que le tag n'a pas changé"
    correct: 2
    explanation: "Le registre reconnaît les couches qu'il a déjà, grâce à leur empreinte."
```
