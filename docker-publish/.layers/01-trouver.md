---
title: "Trouver et télécharger une image"
description: "Docker Hub en lecture : chercher une image, juger de son sérieux, la télécharger"
---

Avant d'écrire une image, il vaut mieux vérifier qu'elle n'existe pas déjà. La plupart des logiciels courants sont publiés sur **Docker Hub**, le registre public auquel Docker s'adresse par défaut, et c'est là que vos commandes `docker run` allaient déjà chercher leurs images.

## Chercher une image

`docker search` interroge Docker Hub depuis le terminal, et `--limit 3` ne garde que les 3 premières réponses. Aucun compte n'est nécessaire :

```exec
docker search nginx --limit 3
```

La réponse ressemble à ceci :

```text
NAME                              DESCRIPTION                                     STARS     OFFICIAL
nginx                             Official build of Nginx.                        21416     [OK]
nginx/nginx-ingress               NGINX and  NGINX Plus Ingress Controllers fo…   124
nginx/nginx-prometheus-exporter   NGINX Prometheus Exporter for NGINX and NGIN…   53
```

Tout le monde peut publier sur Docker Hub, et le nom d'une image ne prouve rien. C'est pourquoi on regarde d'abord la colonne `OFFICIAL`. Les images officielles sont relues et maintenues par Docker et par l'éditeur du logiciel. Leur nom n'a pas de préfixe, comme `nginx`, alors que les autres s'écrivent `compte/image`.

## Lire sa page

`docker search` ne montre ni les tags ni le mode d'emploi. Pour les trouver, ouvrez la page d'une image dans un navigateur : [nginx sur Docker Hub](https://hub.docker.com/_/nginx). Vous y trouverez la liste des tags, les ports, les variables d'environnement acceptées, et les architectures disponibles.

Pour choisir un tag, ce tableau résume les formes les plus courantes.

| Forme du tag | Exemple | Ce que vous obtenez |
|---|---|---|
| Version précise | `1.30.5` | cette version-là ; le tag ne bouge presque plus |
| Version mineure | `1.30` | la dernière `1.30.x` : vous recevez les correctifs |
| Variante | `1.30-alpine` | la même, construite sur Alpine : une image plus petite |
| Aucun | `latest` | ce que l'éditeur a choisi, qui peut changer du tout au tout |

Il vaut mieux éviter `latest` en dehors d'un essai : une même commande pourrait donner une version différente le mois suivant.

## Télécharger

`docker run` télécharge une image quand elle manque, mais on veut parfois le faire à l'avance, par exemple avant une formation sans réseau, ou pour vérifier qu'une mise à jour existe. C'est le rôle de `docker pull` :

```exec
docker pull nginx:1.30-alpine
```

Docker répond avec le digest de l'image, puis avec son nom complet, `docker.io/library/nginx:1.30-alpine`. Si vous avez déjà cette image, il vous le dit par `Image is up to date`, sans rien télécharger.

```verify
if ! docker image inspect nginx:1.30-alpine >/dev/null 2>&1; then
  echo "L'image nginx:1.30-alpine n'est pas sur votre machine. Lancez docker pull."
  exit 1
fi
echo "L'image nginx:1.30-alpine est sur votre machine."
```

> 📖 [`docker search`](https://docs.docker.com/reference/cli/docker/search/) · [`docker pull`](https://docs.docker.com/reference/cli/docker/image/pull/) · [Les images officielles](https://docs.docker.com/docker-hub/image-library/trusted-content/)

## Récap

- Docker Hub est le registre par défaut, et il se lit sans compte.
- Une image officielle se reconnaît à son nom sans préfixe et à la colonne `OFFICIAL`.
- On choisit un tag précis plutôt que `latest`.

## Questions

```quiz
title: "Trouver une image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Deux images répondent à votre recherche : `redis` et `jean42/redis`. Laquelle est l'image officielle ?"
    answers:
      - "`jean42/redis`, parce que son nom est plus précis"
      - "`redis` : une image officielle n'a pas de préfixe de compte"
      - "Les deux : le nom du logiciel suffit"
    correct: 2
    explanation: "Les images officielles sont dans l'espace `library`, que l'on n'écrit pas. Tout ce qui s'écrit `compte/image` a été publié par ce compte."
  - prompt: "Vous lancez `docker pull` sur une image déjà présente et à jour. Que se passe-t-il ?"
    answers:
      - "Docker la télécharge à nouveau entièrement"
      - "Docker répond `Image is up to date`, sans rien télécharger"
      - "Docker renvoie une erreur"
    correct: 2
    explanation: "Docker compare le digest du registre avec celui qu'il a déjà, et ne télécharge que ce qui manque."
```
