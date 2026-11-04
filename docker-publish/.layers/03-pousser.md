---
title: "Nommer et pousser une image"
description: "docker tag donne l'adresse, docker push envoie"
---

Votre registre est prêt et vide. Il vous faut une image à y mettre, et un nom qui dit à Docker où l'envoyer.

## Construire une image

Créez un dossier de travail et, dedans, un Dockerfile minimal. Cette image affiche simplement son numéro de version, ce qui permettra de reconnaître plus tard laquelle on a sous les yeux :

```exec
mkdir -p ~/layers-l4/app
cat > ~/layers-l4/app/Dockerfile <<'FIN'
FROM alpine:3.22
CMD ["echo", "Bonjour depuis la version 1"]
FIN
```

Construisez-la, puis lancez-la pour vérifier qu'elle dit ce qu'on attend :

```exec
docker build -t layers-l4-hello:1.0 ~/layers-l4/app
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

## Lui donner une adresse

`docker push` ne prend pas de destination : il la lit **dans le nom de l'image**. Avec le nom actuel, `layers-l4-hello:1.0`, Docker comprendrait qu'il faut l'envoyer sur Docker Hub, et il refuserait, faute de compte. Pour viser votre registre, il faut un nom qui commence par son adresse. C'est le rôle de `docker tag`, qui pose un nom de plus sur la même image :

```exec
docker tag layers-l4-hello:1.0 localhost:28340/layers-l4-hello:1.0
```

Ce nom se lit morceau par morceau :

| Morceau | Rôle |
|---|---|
| `localhost:28340` | le registre, votre conteneur |
| `layers-l4-hello` | le dépôt, qui sera créé à la première publication |
| `1.0` | le tag, la version publiée |

Vérifiez que les deux noms désignent bien la même image, sans aucune copie. `docker image inspect` lit la fiche d'une image, et `--format` en extrait l'identifiant : les deux lignes doivent être identiques.

```exec
docker image inspect layers-l4-hello:1.0 localhost:28340/layers-l4-hello:1.0 --format '{{.Id}}'
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

## Pousser

Publier une image se dit **pousser** : `push`. Envoyez-la :

```exec
docker push localhost:28340/layers-l4-hello:1.0
```

Docker envoie l'image couche par couche, puis termine par une ligne qui ressemble à celle-ci :

```text
1.0: digest: sha256:1adfdbd32f0b30653f969a745f93353800413cf39da71def8685ec0a1dd98ce1 size: 855
```

Votre digest sera différent. C'est l'empreinte de l'image telle que le registre la connaît désormais. Demandez maintenant au registre ce qu'il contient, d'abord ses dépôts, puis les tags de votre dépôt :

```exec
curl -sS http://localhost:28340/v2/_catalog
curl -sS http://localhost:28340/v2/layers-l4-hello/tags/list
```

Le registre répond `{"repositories":["layers-l4-hello"]}`, puis `{"name":"layers-l4-hello","tags":["1.0"]}`. Votre image est publiée.

```verify
if ! curl -s --max-time 5 http://localhost:28340/v2/layers-l4-hello/tags/list | grep -q '"1.0"'; then
  echo "Le registre ne connaît pas le tag 1.0 du dépôt layers-l4-hello. Lancez le docker push."
  exit 1
fi
echo "Le registre contient layers-l4-hello:1.0."
```

## Pousser une seconde fois

Poussez à nouveau la même image, sans rien changer, et regardez ce qui diffère :

```exec
docker push localhost:28340/layers-l4-hello:1.0
```

Les couches sont marquées `Layer already exists` ou `Already exists`, et rien n'est renvoyé. Un registre ne stocke chaque couche qu'une fois, ce qui rend les publications suivantes rapides et explique pourquoi un dépôt de cent versions ne pèse pas cent images.

## Plusieurs tags pour une version

Une même image peut porter plusieurs tags, et il est courant de lui en donner plusieurs pour que chacun choisisse à quel point il veut suivre les nouveautés. Publiez-la aussi sous le tag `latest` :

```exec
docker tag layers-l4-hello:1.0 localhost:28340/layers-l4-hello:latest
docker push localhost:28340/layers-l4-hello:latest
curl -sS http://localhost:28340/v2/layers-l4-hello/tags/list
```

Le digest affiché est le même, et les couches n'ont pas été renvoyées : c'est la même image, avec deux étiquettes. Rien n'a déplacé `latest` tout seul : c'est votre commande qui l'a fait. S'il vous arrive de publier une nouvelle version sans déplacer ce tag, `latest` restera sur l'ancienne.

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
      - "Grâce à une option `--registry`"
      - "Il le lit au début du nom de l'image, et prend Docker Hub s'il n'y en a pas"
      - "Il l'envoie à tous les registres connus"
    correct: 2
    explanation: "C'est pour cela qu'on pose d'abord un nom complet avec `docker tag`."
  - prompt: "`docker tag app:1.0 localhost:28340/app:1.0` a-t-il copié l'image ?"
    answers:
      - "Oui, l'espace occupé double"
      - "Non : c'est un nom de plus sur la même image"
      - "Oui, et il l'a envoyée au registre"
    correct: 2
    explanation: "Un tag est une étiquette. Rien ne part vers le registre avant le `docker push`."
  - prompt: "Vous repoussez une image dont seule la dernière couche a changé. Que part vers le registre ?"
    answers:
      - "Toute l'image"
      - "Seule la couche nouvelle : le registre a déjà les autres"
      - "Rien, tant que le tag n'a pas changé"
    correct: 2
    explanation: "Le registre reconnaît les couches qu'il a déjà, grâce à leur empreinte."
```
