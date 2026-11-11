---
title: "Une première image, du Dockerfile au conteneur"
description: "Le chemin d'un projet jusqu'au conteneur : Dockerfile, docker build, docker run"
---

Dans un conteneur, vous pouvez tout installer à la main avec `docker exec`, mais ce travail disparaît avec le conteneur et personne ne pourra le refaire à l'identique. Un **Dockerfile** règle ce problème : c'est un fichier texte qui décrit, instruction après instruction, comment fabriquer une image. Comme il est écrit, il se relit, se partage et se rejoue.

## Du projet au conteneur, le chemin complet

Vous partez d'un projet, c'est-à-dire un dossier avec du code et un Dockerfile. `docker build` en fabrique une image, et `docker run` lance un conteneur à partir de cette image.

```mermaid
flowchart LR
  P["Projet : code et Dockerfile"] -->|docker build| I["Image"]
  I -->|docker run| C["Conteneur"]
```

Une **image** est le modèle figé dont part un conteneur : des fichiers, plus une fiche de réglages (ses métadonnées), dont la commande à lancer au démarrage. Elle ne change jamais une fois construite. Vous connaissez déjà la partie droite du schéma, `docker run`, et ce cours ajoute la partie gauche. En entreprise, le Dockerfile vit avec le code du projet, et il est écrit par l'équipe de développement ou par la personne chargée de conteneuriser l'application.

## Créer le projet : un petit serveur web en Python

Commencez par créer le dossier du projet. `mkdir -p` crée le dossier et ses parents, sans erreur s'ils existent déjà :

```exec
mkdir -p ~/byte-layers/docker/l2/hello
```

Écrivez maintenant l'application, un programme Python qui écoute sur le port 8000 et répond une phrase à chaque requête. La forme `cat > fichier <<'EOF'` écrit dans le fichier toutes les lignes qui suivent, jusqu'à la ligne `EOF`. Collez le bloc en entier dans le terminal, ou créez ce fichier dans votre éditeur : le résultat est le même.

```exec
cat > ~/byte-layers/docker/l2/hello/app.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer

class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Bonjour depuis mon image\n")

HTTPServer(("0.0.0.0", 8000), Page).serve_forever()
EOF
```

Pour tourner, ce programme n'a besoin que de Python, et c'est exactement ce que l'image va lui apporter.

## Écrire le Dockerfile en trois instructions

Le Dockerfile se place à côté de l'application et s'appelle `Dockerfile`, sans extension. Celui-ci tient en trois lignes :

```exec
cat > ~/byte-layers/docker/l2/hello/Dockerfile <<'EOF'
FROM python:3.13-alpine
COPY app.py /app.py
CMD ["python", "/app.py"]
EOF
```

Chaque ligne commence par une **instruction**, écrite en majuscules par convention, et ce tableau donne le rôle de chacune.

| Instruction | Rôle |
|---|---|
| `FROM python:3.13-alpine` | part d'une image existante, ici Python 3.13 sur Alpine, un Linux minimal |
| `COPY app.py /app.py` | copie un fichier de votre projet vers un chemin de l'image |
| `CMD ["python", "/app.py"]` | enregistre la commande que lancera chaque conteneur à son démarrage. Rien n'est exécuté pendant la construction |

`FROM` vient en premier, car une image se construit toujours par-dessus une autre, appelée **image de base**. Vous n'installez donc pas Python : vous repartez d'une image où il se trouve déjà.

## Construire l'image avec docker build

Passez à la construction, qu'on appelle aussi le **build**. `docker build` lit le Dockerfile et produit une image :

```exec
docker build -t layers-l2-hello:1.0 ~/byte-layers/docker/l2/hello
```

Cette commande a deux éléments à retenir.

| Élément | Rôle |
|---|---|
| `-t layers-l2-hello:1.0` | nomme l'image : `layers-l2-hello` est son nom et `1.0` son **tag**, le nom de cette version, comme dans `alpine:3.22` |
| `~/byte-layers/docker/l2/hello` | le **contexte de build** : le dossier dont Docker peut copier des fichiers, et où il cherche le `Dockerfile` |

Le contexte a une conséquence : `COPY` ne voit que ce dossier. Un fichier situé ailleurs sur votre machine lui est inaccessible, quel que soit le chemin que vous écrivez. Vous verrez aussi souvent `docker build -t nom:tag .` : le point désigne le dossier courant, pour qui se trouve déjà dans le projet.

Dans ce que Docker affiche, repérez une ligne par étape de construction, `[1/2]` pour `FROM` et `[2/2]` pour `COPY`. `CMD` n'a pas de ligne de ce genre, car il ne fait qu'écrire une information dans la fiche de l'image. Listez ensuite l'image que vous venez de fabriquer :

```exec
docker images layers-l2-hello
```

Vous devez lire une ligne de ce genre, avec votre propre identifiant et une taille qui dépend de votre machine :

```text
REPOSITORY        TAG       IMAGE ID       CREATED          SIZE
layers-l2-hello   1.0       df8ebdccce7d   10 seconds ago   73.7MB
```

```verify
CMD=$(docker image inspect layers-l2-hello:1.0 --format '{{json .Config.Cmd}}' 2>/dev/null)
if [ -z "$CMD" ]; then
  echo "L'image layers-l2-hello:1.0 n'existe pas. Relancez le docker build et lisez son message d'erreur."
  exit 1
fi
if [ "$CMD" != '["python","/app.py"]' ]; then
  echo "La commande de l'image est $CMD, alors que le Dockerfile de ce cours attend [\"python\",\"/app.py\"]."
  exit 1
fi
echo "L'image existe et connaît sa commande de démarrage."
```

## Lancer l'image, voir son état, demander la page

Une image que vous avez construite se lance comme n'importe quelle autre. Le port 28320 de votre machine mène au port 8000 du conteneur, celui où l'application écoute :

```exec
docker run -d --name layers-l2-hello -p 28320:8000 layers-l2-hello:1.0
```

Regardez d'abord si le conteneur tourne. S'il s'est déjà arrêté, inutile d'aller plus loin : ses logs diront pourquoi.

```exec
docker ps
```

Sur la ligne de `layers-l2-hello`, la colonne `STATUS` doit commencer par `Up`, et la colonne `PORTS` doit montrer `28320->8000/tcp`. Demandez maintenant la page :

```exec
curl http://localhost:28320
```

Vous devez lire la phrase de votre programme :

```text
Bonjour depuis mon image
```

Si `curl` répond par une erreur de connexion, le programme démarrait encore : attendez une seconde et relancez la même commande.

Vous avez écrit un Dockerfile, construit une image et lancé un conteneur à partir d'elle. Tout le reste de ce cours affine ce même geste.

```verify
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28320) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"Bonjour depuis mon image"*) : ;;
  *) echo "Rien ne répond correctement sur le port 28320. Vérifiez avec : docker ps -a"; exit 1 ;;
esac
if [ "$(docker inspect layers-l2-hello --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l2-hello:1.0" ]; then
  echo "Le port répond, mais pas avec un conteneur layers-l2-hello issu de l'image layers-l2-hello:1.0."
  exit 1
fi
echo "Votre image tourne et répond."
```

Ce conteneur a fait son travail : supprimez-le pour libérer le port.

```exec
docker rm -f layers-l2-hello
```

## Retrouver ces trois instructions dans une image publique

Les images que vous téléchargez sont fabriquées de la même façon, et leurs Dockerfile sont souvent publics. Celui de `hello-world`, l'image de démonstration de Docker, est [publié sur GitHub](https://github.com/docker-library/hello-world/tree/master/amd64), à côté de son programme compilé, un fichier nommé `hello`. Le voici en entier :

```dockerfile
FROM scratch
COPY hello /
CMD ["/hello"]
```

Vous reconnaissez `FROM`, `COPY` et `CMD`. `scratch` est un cas particulier : c'est une image de base vide, sans système ni shell, qui ne contiendra donc que le programme copié.

> 📖 [Référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [`docker build`](https://docs.docker.com/reference/cli/docker/build/) · [Le contexte de build](https://docs.docker.com/build/concepts/context/)

## Questions

```quiz
title: "Une première image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quand la commande écrite dans `CMD` est-elle exécutée ?"
    answers:
      - "Au démarrage de chaque conteneur créé depuis l'image"
      - "Pendant `docker build`"
      - "Une seule fois, au premier `docker run`"
    correct: 1
    explanation: "`CMD` ne fait qu'enregistrer une commande dans l'image. Chaque conteneur la lance à son démarrage."
  - prompt: "Dans `docker build -t mon-app:1.0 ./projet`, que désigne `./projet` ?"
    answers:
      - "Le nom de l'image"
      - "Le dossier où l'image sera enregistrée"
      - "Le contexte de build, le seul dossier où `COPY` peut prendre des fichiers"
    correct: 3
    explanation: "Le dernier argument est le contexte. L'image, elle, est rangée par Docker, et son nom vient de `-t`."
  - prompt: "Pourquoi un Dockerfile vaut-il mieux qu'une installation à la main dans un conteneur ?"
    answers:
      - "Il rend le conteneur plus rapide"
      - "Il se relit et se rejoue, alors que le travail à la main disparaît avec le conteneur"
      - "Il évite de télécharger une image de base"
    correct: 2
    explanation: "Le Dockerfile est une recette : n'importe qui peut reconstruire l'image à partir de lui."
```
