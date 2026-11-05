---
title: "Trouver et télécharger une image"
description: "Docker Hub en lecture : chercher une image, reconnaître qui la publie, choisir son tag, la télécharger"
---

Avant d'écrire une image, il vaut mieux vérifier qu'elle n'existe pas déjà. La plupart des logiciels courants sont publiés sur **Docker Hub**, le registre public auquel Docker s'adresse par défaut, et c'est là que vos commandes `docker run` allaient déjà chercher leurs images.

## Chercher une image avec docker search

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

Tout le monde peut publier sur Docker Hub, et le nom d'une image ne prouve rien. Il faut donc regarder qui la publie, et ce tableau donne les trois cas que vous croiserez.

| Ce que vous voyez | Qui publie | Ce que cela vous apprend |
|---|---|---|
| `[OK]` dans `OFFICIAL`, un nom sans préfixe, comme `nginx` | une équipe de Docker les relit, et l'éditeur ou une communauté les maintient | une image relue et suivie. C'est le premier choix |
| un badge *Verified Publisher* sur la page de l'image, un nom comme `nginx/nginx-ingress` | un éditeur dont Docker a vérifié l'identité | on sait qui est derrière |
| aucune marque, un nom comme `jean42/nginx` | un compte quelconque | rien : à lire de près avant de s'y fier |

La colonne `STARS` compte les étoiles laissées par les utilisateurs. Elle dit qu'une image est populaire, et non qu'elle est sûre ou à jour.

## Trouver le tag Alpine de nginx sur sa page

`docker search` ne montre ni les tags ni le mode d'emploi. Ouvrez la [page de nginx sur Docker Hub](https://hub.docker.com/_/nginx) dans un navigateur : vous y trouverez le mode d'emploi, et l'onglet **Tags** liste toutes les versions.

À vous de chercher : quel tag donne nginx en version 1.30, construit sur Alpine ? Tapez `alpine` dans le champ de recherche de l'onglet **Tags**, et regardez les noms proposés.

Un tag combine en général deux informations : une version, et parfois une variante. Voici d'abord les formes que prend la version.

| Forme de la version | Exemple | Ce que vous obtenez |
|---|---|---|
| Version complète | `1.30.5` | cette version-là. Le tag ne bouge presque plus |
| Version mineure | `1.30` | la dernière `1.30.x`. Le tag bouge à chaque correctif, et vous recevez ces correctifs |
| Aucune | `latest` | ce que l'éditeur a choisi, qui peut changer du tout au tout |

La variante s'ajoute après un tiret et dit sur quoi l'image est construite : `-alpine` pour Alpine, qui donne une image plus petite. La réponse à la question est donc `1.30-alpine`, la forme utilisée dans ce parcours.

Il vaut mieux éviter `latest` en dehors d'un essai : une même commande pourrait donner une version différente le mois suivant.

```ack
J'ai trouvé le tag 1.30-alpine sur la page de nginx
```

## Télécharger à l'avance avec docker pull

`docker run` télécharge une image quand elle manque, mais on veut parfois le faire à l'avance, par exemple avant une formation sans réseau, ou pour vérifier qu'une mise à jour existe. C'est le rôle de `docker pull`, vu dans [Nommer une image](https://byte-layers.com/fr/bits/image-reference), et l'on dit aussi **tirer** une image :

```exec
docker pull nginx:1.30-alpine
```

Docker répond par le digest de l'image, puis par son nom complet. Si vous avez déjà cette image, il le dit par `Image is up to date`, sans rien télécharger :

```text
1.30-alpine: Pulling from library/nginx
Digest: sha256:…
Status: Image is up to date for nginx:1.30-alpine
docker.io/library/nginx:1.30-alpine
```

```verify
if ! docker image inspect nginx:1.30-alpine >/dev/null 2>&1; then
  echo "L'image nginx:1.30-alpine n'est pas sur votre machine. Lancez docker pull."
  exit 1
fi
echo "L'image nginx:1.30-alpine est sur votre machine."
```

> 📖 [`docker search`](https://docs.docker.com/reference/cli/docker/search/) · [`docker pull`](https://docs.docker.com/reference/cli/docker/image/pull/) · [Les images de confiance](https://docs.docker.com/docker-hub/image-library/trusted-content/)

## Récap

- Docker Hub est le registre par défaut, et il se lit sans compte.
- On regarde qui publie une image : officielle, éditeur vérifié, ou compte quelconque.
- Un tag combine une version et parfois une variante, et l'on préfère un tag explicite à `latest`.

## Questions

```quiz
title: "Trouver une image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Deux images répondent à votre recherche : `redis` et `jean42/redis`. Laquelle est l'image officielle ?"
    answers:
      - "`redis` : une image officielle n'a pas de préfixe de compte"
      - "`jean42/redis`, parce que son nom est plus précis"
      - "Les deux : le nom du logiciel suffit"
    correct: 1
    explanation: "Les images officielles sont dans l'espace `library`, que l'on n'écrit pas. Tout ce qui s'écrit `compte/image` a été publié par ce compte."
  - prompt: "Vous lancez `docker pull` sur une image déjà présente et à jour. Que se passe-t-il ?"
    answers:
      - "Docker la télécharge à nouveau entièrement"
      - "Docker renvoie une erreur"
      - "Docker répond `Image is up to date`, sans rien télécharger"
    correct: 3
    explanation: "Docker compare le digest du registre avec celui qu'il a déjà, et ne télécharge que ce qui manque."
```
