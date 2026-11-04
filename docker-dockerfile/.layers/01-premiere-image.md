---
title: "Une première image"
description: "Le Dockerfile, docker build et le contexte de build"
---

Dans un conteneur, vous pouvez tout installer à la main avec `docker exec`, mais ce travail disparaît avec le conteneur et personne ne pourra le refaire à l'identique. Un **Dockerfile** règle ce problème : c'est un fichier texte qui décrit, instruction après instruction, comment fabriquer une image. Comme il est écrit, il se relit, se partage et se rejoue.

Cette étape construit la plus petite image utile : un serveur web d'une dizaine de lignes.

## Créer l'application

Commencez par créer un dossier pour ce projet. `mkdir -p` crée le dossier et ses parents, sans erreur s'ils existent déjà :

```exec
mkdir -p ~/layers-l2/hello
```

Écrivez maintenant l'application. La forme `cat > fichier <<'EOF'` écrit dans le fichier toutes les lignes qui suivent, jusqu'à la ligne `EOF`. Collez le bloc en entier dans le terminal. Si vous préférez, créez ce fichier dans votre éditeur : le résultat est le même.

```exec
cat > ~/layers-l2/hello/app.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer

class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Bonjour depuis mon image\n")

HTTPServer(("0.0.0.0", 8000), Page).serve_forever()
EOF
```

Vous n'avez pas besoin de lire ce code en détail : il écoute sur le port 8000 et répond une phrase à chaque requête. Pour qu'il tourne, il lui faut seulement Python, et c'est exactement ce que l'image va apporter.

## Écrire le Dockerfile

Le Dockerfile se place à côté de l'application et s'appelle `Dockerfile`, sans extension. Celui-ci tient en trois instructions :

```exec
cat > ~/layers-l2/hello/Dockerfile <<'EOF'
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
| `CMD ["python", "/app.py"]` | fixe la commande lancée au démarrage d'un conteneur, sans l'exécuter pendant la construction |

`FROM` vient en premier, car une image se construit toujours par-dessus une autre, appelée **image de base**. Vous n'installez donc pas Python : vous repartez d'une image où il se trouve déjà.

## Construire l'image

Passez à la construction, qu'on appelle aussi le **build**. `docker build` lit le Dockerfile et produit une image :

```exec
docker build -t layers-l2-hello:1.0 ~/layers-l2/hello
```

Cette commande a deux éléments à retenir.

| Élément | Rôle |
|---|---|
| `-t layers-l2-hello:1.0` | nomme l'image : `layers-l2-hello` est son nom et `1.0` son tag, comme dans `alpine:3.22` |
| `~/layers-l2/hello` | le **contexte de build** : le dossier dont Docker peut copier des fichiers, et où il cherche le `Dockerfile` |

Dans ce que Docker affiche, repérez les lignes `[1/2] FROM …python:3.13-alpine` et `[2/2] COPY app.py /app.py`, une par étape de construction. `CMD` n'a pas de ligne de ce genre, car il ne fait qu'écrire une information dans la configuration de l'image.

Le contexte est une notion à retenir : `COPY` ne voit que ce dossier. Un fichier situé ailleurs sur votre machine lui est inaccessible, quel que soit le chemin que vous écrivez.

`docker images` confirme que l'image existe, et `docker image inspect` lit sa fiche, comme `docker inspect` le fait pour un conteneur. `--format` n'en extrait qu'un champ, ici présenté en JSON, une simple écriture de données :

```exec
docker images layers-l2-hello
docker image inspect layers-l2-hello:1.0 --format '{{json .Config.Cmd}}'
```

Vous devez lire votre image avec le tag `1.0`, puis `["python","/app.py"]`. Le CMD a bien été enregistré dans l'image.

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

## Lancer votre image

Une image que vous avez construite se lance comme n'importe quelle autre. Le port 28320 de votre machine mène au port 8000 du conteneur, celui où l'application écoute :

```exec
docker run -d --name layers-l2-hello -p 28320:8000 layers-l2-hello:1.0
```

Demandez la page. `curl` la télécharge, `-s` masque sa barre de progression, et `--retry` patiente le temps que le serveur démarre :

```exec
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28320
```

Vous devez lire `Bonjour depuis mon image`. Vous avez écrit un Dockerfile, construit une image et lancé un conteneur à partir d'elle : tout le reste de ce cours affine ce même geste.

```verify
if ! curl -s --max-time 5 http://localhost:28320 | grep -q 'Bonjour depuis mon image'; then
  echo "Rien ne répond correctement sur le port 28320. Vérifiez avec : docker ps -a --filter name=layers-l2-hello"
  exit 1
fi
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

> 📖 [Référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [`docker build`](https://docs.docker.com/reference/cli/docker/build/) · [Le contexte de build](https://docs.docker.com/build/concepts/context/)

## Questions

```quiz
title: "Une première image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quand la commande écrite dans `CMD` est-elle exécutée ?"
    answers:
      - "Pendant `docker build`"
      - "Au démarrage de chaque conteneur créé depuis l'image"
      - "Une seule fois, au premier `docker run`"
    correct: 2
    explanation: "`CMD` ne fait qu'enregistrer une commande dans l'image. Chaque conteneur la lance à son démarrage."
  - prompt: "Dans `docker build -t mon-app:1.0 ./projet`, que désigne `./projet` ?"
    answers:
      - "Le nom de l'image"
      - "Le contexte de build, le seul dossier où `COPY` peut prendre des fichiers"
      - "Le dossier où l'image sera enregistrée"
    correct: 2
    explanation: "Le dernier argument est le contexte. L'image, elle, est rangée par Docker, et son nom vient de `-t`."
  - prompt: "Pourquoi un Dockerfile vaut-il mieux qu'une installation à la main dans un conteneur ?"
    answers:
      - "Il rend le conteneur plus rapide"
      - "Il se relit et se rejoue, alors que le travail à la main disparaît avec le conteneur"
      - "Il évite de télécharger une image de base"
    correct: 2
    explanation: "Le Dockerfile est une recette : n'importe qui peut reconstruire la même image à partir de lui."
```
