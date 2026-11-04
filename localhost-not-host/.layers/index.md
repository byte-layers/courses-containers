---
title: "Localhost n'est pas l'hôte"
description: "Chaque conteneur a son propre réseau et son propre localhost. Une fois cette idée posée, la plupart des erreurs de connexion s'expliquent d'elles-mêmes."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Localhost n'est pas l'hôte

**Pour qui ?** Pour vous, si vous savez lancer un conteneur et lire ses logs : le cours « Lancer, configurer et observer un conteneur » suffit. Il faut que `docker ps` réponde, que `curl` soit installé et que les ports 28350 et 28351 soient libres. Aucune connaissance en réseau n'est nécessaire : les mots sont définis ci-dessous.

Une machine sur un réseau a une **adresse IP**, le numéro auquel les autres la joignent. Elle a aussi un **port** par service, le numéro de la porte à laquelle ce service répond. Enfin, le nom **localhost**, qui correspond à l'adresse `127.0.0.1`, veut dire « moi-même » : un programme qui l'utilise parle à la machine sur laquelle il tourne.

Sur votre machine, l'**hôte**, tout cela est simple. Un conteneur change la réponse à une question précise : qui est « moi-même » ? Un conteneur a sa propre pile réseau, c'est-à-dire ses adresses, ses ports et son propre localhost, isolés de ceux de l'hôte. Dans un conteneur, localhost désigne donc **ce conteneur et rien d'autre**. Voici ce que voit chacun de ces programmes quand il demande localhost :

```
                           hôte
  ┌──────────────────────────────────────────────────┐
  │   localhost = l'hôte                             │
  │                                                  │
  │   ┌─────────────────┐     ┌─────────────────┐    │
  │   │  conteneur A    │     │  conteneur B    │    │
  │   │  localhost = A  │     │  localhost = B  │    │
  │   │  172.17.0.5     │     │  172.17.0.6     │    │
  │   └─────────────────┘     └─────────────────┘    │
  └──────────────────────────────────────────────────┘
```

Deux erreurs de débutant en découlent, et vous allez provoquer les deux. La première : un conteneur cherche sur localhost un service qui tourne ailleurs. La seconde : un programme dans un conteneur n'écoute que sur son localhost, et personne d'autre ne peut le joindre.

## Le constater

Vous n'avez pas besoin de connaître toutes ces options pour suivre : ce tableau suffit pour l'instant.

| Élément | Rôle |
|---|---|
| `docker run -d --name x` | lance un conteneur en arrière-plan, avec un nom fixe |
| `-p 28350:80` | une recette à ce stade : le port 28350 de l'hôte mène au port 80 du conteneur |
| `docker exec` | lance une commande dans un conteneur qui tourne |
| `wget -qO- -T 3 <url>` | demande une page depuis un conteneur Alpine et l'affiche, en abandonnant après 3 secondes : `curl` n'y est pas installé |
| `--rm` | supprime le conteneur à son arrêt |

Si un téléchargement échoue avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub pour les téléchargements anonymes. Attendez, ou créez un compte gratuit et lancez `docker login`.

Commencez par lancer un serveur web, puis demandez-lui sa page depuis l'hôte. `-sS` n'affiche que les erreurs, `-o /dev/null` jette la page, `-w '%{http_code}'` affiche le code de réponse, 200 voulant dire que tout va bien, et `--retry` patiente le temps que le serveur démarre :

```exec
docker run -d --name layers-l5-web -p 28350:80 nginx:1.30-alpine
curl -sS -o /dev/null -w '%{http_code}\n' --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28350
```

Une erreur de connexion peut s'afficher le temps que nginx démarre, puis vous lisez `200` : depuis l'hôte, localhost mène bien au serveur. Posez maintenant la même question depuis un autre conteneur. Faites d'abord une prévision, puis lancez la commande :

```exec
docker run --rm alpine:3.22 wget -qO- -T 3 http://localhost:28350
```

Vous lisez `Connection refused`. Le serveur tourne pourtant toujours : c'est ce conteneur Alpine qui a cherché sur **son propre** localhost, où personne n'écoute. Le port 28350 n'existe d'ailleurs que sur l'hôte, comme le montre la même question posée au conteneur du serveur lui-même :

```exec
docker exec layers-l5-web wget -qO- -T 3 http://localhost:28350
```

Le refus est le même. Son port à lui, c'est le 80, et il répond bien quand on le lui demande. `grep` ne garde ici que la ligne du titre :

```exec
docker exec layers-l5-web wget -qO- -T 3 http://localhost:80 | grep '<h1>'
```

Chaque conteneur a également son adresse à lui, que `hostname -i` affiche. Chez vous, le numéro sera peut-être différent de celui du schéma :

```exec
docker exec layers-l5-web hostname -i
```

## Joindre vraiment l'hôte

Il arrive qu'un conteneur doive joindre un service de l'hôte, comme une base de données lancée hors de Docker. Il lui faut alors un nom qui désigne l'hôte, et c'est le rôle de `host.docker.internal`. Docker Desktop le fournit d'office, mais pas Docker sous Linux. L'option `--add-host=host.docker.internal:host-gateway` ajoute ce nom dans le conteneur et marche partout :

```exec
docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.22 wget -qO- -T 3 http://host.docker.internal:28350 | grep '<h1>'
```

Vous lisez `<h1>Welcome to nginx!</h1>` : le conteneur est sorti vers l'hôte, puis l'hôte l'a renvoyé vers le serveur par le port 28350. Pour que deux conteneurs se parlent, ce détour n'est pas la bonne méthode : un réseau commun fait mieux, et c'est le sujet du cours « Relier des conteneurs et publier un port ».

Ce serveur ne sert plus, supprimez-le avant la seconde expérience :

```exec
docker rm -f layers-l5-web
```

## L'autre sens : un service qui n'écoute que sur son localhost

Un serveur choisit l'adresse sur laquelle il écoute. Sur `127.0.0.1`, il n'accepte que les demandes venues de sa propre machine. Sur `0.0.0.0`, il les accepte d'où qu'elles viennent. Beaucoup d'outils de développement écoutent par défaut sur `127.0.0.1`, ce qui convient sur un poste, mais plus du tout dans un conteneur.

Lancez un petit serveur Python qui écoute seulement sur son localhost. `--bind` choisit cette adresse, et le serveur écoute sur le port 8000 :

```exec
docker run -d --name layers-l5-local -p 28351:8000 python:3.13-alpine python -m http.server 8000 --bind 127.0.0.1
```

Le port est publié et le conteneur tourne, et pourtant `curl` échoue. L'erreur est normale ici : selon votre machine, vous lirez `Connection reset by peer` ou `Empty reply from server`, puis `000`, le code affiché quand il n'y a aucune réponse. `--max-time 3` limite l'attente à 3 secondes :

```exec
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 3 http://localhost:28351
```

La demande arrive au conteneur par son adresse à lui, alors que le serveur n'écoute que sur son localhost : personne n'y répond. Recréez le conteneur en écoutant sur `0.0.0.0`, et seul ce mot change :

```exec
docker rm -f layers-l5-local
docker run -d --name layers-l5-local -p 28351:8000 python:3.13-alpine python -m http.server 8000 --bind 0.0.0.0
```

Demandez à nouveau la page. Une erreur peut s'afficher le temps que le serveur démarre, puis vous lisez `200` :

```exec
curl -sS -o /dev/null -w '%{http_code}\n' --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28351
```

Il reste à ranger ce dernier conteneur :

```exec
docker rm -f layers-l5-local
```

> 📖 [Le réseau dans Docker](https://docs.docker.com/engine/network/) · [Publier des ports](https://docs.docker.com/get-started/docker-concepts/running-containers/publishing-ports/) · [`host.docker.internal` sur Docker Desktop](https://docs.docker.com/desktop/features/networking/)

## Ce qu'il faut retenir

- Un conteneur a sa propre pile réseau. Dans un conteneur, localhost désigne ce conteneur.
- Un port publié existe sur l'hôte : un autre conteneur ne le trouve pas sur son localhost.
- Un serveur dans un conteneur doit écouter sur `0.0.0.0`, sinon le port publié ne mène à rien.

```quiz
prompt: "Votre application tourne dans un conteneur et sa base de données dans un autre. Vous configurez l'application avec `DB_HOST=localhost`, et elle affiche `ECONNREFUSED 127.0.0.1:3306`. Pourquoi ?"
answers:
  - "La base de données n'a pas publié le port 3306 sur l'hôte"
  - "Dans le conteneur de l'application, localhost désigne l'application elle-même, où rien n'écoute sur le port 3306"
  - "Le pare-feu de l'hôte bloque le port 3306"
correct: 2
explanation: |
  `ECONNREFUSED` est la forme que prend `Connection refused` dans Node.js. Le message donne la clé : `127.0.0.1`, c'est le conteneur de l'application. Publier le port de la base n'y changerait
  rien, puisque la demande ne quitte jamais ce conteneur.
```

```ack
J'ai compris
```
