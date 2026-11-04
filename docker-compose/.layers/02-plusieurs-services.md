---
title: "Plusieurs services"
description: "Construire une image depuis Compose, et laisser les services se trouver par leur nom"
---

Un seul conteneur ne justifie pas un fichier. L'intérêt de Compose apparaît avec plusieurs services qui se parlent. Vous allez écrire une petite application : un serveur web qui compte ses visites et garde ce compteur dans **Redis**, une base de données très simple et très rapide, qui conserve des valeurs en mémoire.

## Le code de l'application

L'application tient dans un fichier Python, sans aucune dépendance. Vous n'avez pas besoin de lire Python pour suivre ce cours. Retenez deux choses : elle écoute sur le port 8000, et elle cherche Redis à l'adresse donnée par la variable d'environnement `REDIS_HOST`. Créez ce fichier :

```exec
cat > ~/layers-l7/counter/app.py <<'EOF'
import os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
GREETING = os.environ.get("GREETING", "Bonjour")

def count_visit():
    with socket.create_connection((REDIS_HOST, 6379), timeout=2) as redis:
        redis.sendall(b"INCR visits\r\n")
        return int(redis.recv(64).strip().lstrip(b":"))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"{GREETING} ! Visites : {count_visit()}\n".encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("", 8000), Handler).serve_forever()
EOF
```

Il lui faut une image. Ce `Dockerfile` part de Python, copie le fichier et dit quoi lancer. L'option `-u` demande à Python d'écrire ses logs sans attendre :

```exec
cat > ~/layers-l7/counter/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF
```

## Décrire les deux services

Remplacez maintenant le fichier Compose. Le service `web` n'a plus de clé `image` : il a une clé `build`, qui demande à Compose de construire l'image à partir du `Dockerfile` du dossier indiqué, ici `.`, le dossier courant. Le service `cache`, lui, utilise une image toute prête :

```exec
cat > ~/layers-l7/counter/compose.yaml <<'EOF'
name: layers-l7-counter
services:
  web:
    build: .
    ports:
      - "28370:8000"
    environment:
      REDIS_HOST: cache
  cache:
    image: redis:8-alpine
EOF
```

La nouveauté la plus importante est sur la ligne `REDIS_HOST: cache`. `environment` donne des variables d'environnement au conteneur, comme l'option `-e` de `docker run`. Et sa valeur, `cache`, est le **nom de l'autre service**.

Compose a en effet créé un réseau pour le projet, et il y place tous les services. Sur un tel réseau, Docker résout les noms : un conteneur joint l'autre par son nom de service. C'est le mécanisme vu dans « Relier des conteneurs et publier un port », sauf que vous n'avez plus rien à créer vous-même. Le schéma suivant montre ce que le fichier décrit :

```
votre machine                 réseau layers-l7-counter_default
┌──────────────┐  port 28370  ┌────────────┐   nom « cache »   ┌────────────┐
│ curl         │ ───────────► │ web :8000  │ ────────────────► │ cache :6379│
└──────────────┘              └────────────┘                   └────────────┘
```

`cache` ne publie aucun port : seul `web` a besoin de le joindre, et il le fait par le réseau. Un service qui n'a pas à être appelé depuis l'extérieur ne publie rien.

## Construire et démarrer

`--build` demande à Compose de construire l'image avant de démarrer. Lancez :

```exec
cd ~/layers-l7/counter && docker compose up -d --build
```

Compose construit l'image `layers-l7-counter-web`, puis crée deux conteneurs. Demandez deux fois la page. `--retry` patiente le temps que le serveur démarre :

```exec
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
curl -s http://localhost:28370
```

Vous devez lire `Bonjour ! Visites : 1`, puis `Bonjour ! Visites : 2`. Les deux services se parlent : `web` a trouvé `cache` par son nom.

```verify
for C in layers-l7-counter-web-1 layers-l7-counter-cache-1; do
  if [ "$(docker inspect "$C" --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
    echo "$C ne tourne pas. Lancez docker compose up -d --build dans ~/layers-l7/counter, puis lisez docker compose logs."
    exit 1
  fi
done
if ! curl -s --max-time 5 http://localhost:28370 | grep -q 'Visites : [0-9]'; then
  echo "L'application ne répond pas comme prévu sur le port 28370. Lisez : docker compose logs web"
  exit 1
fi
if [ -n "$(docker port layers-l7-counter-cache-1)" ]; then
  echo "cache publie un port alors qu'il n'en a pas besoin. Retirez la clé ports de ce service."
  exit 1
fi
echo "web joint cache par son nom, et cache ne publie rien."
```

## Une modification, une reconstruction

Compose ne reconstruit pas une image à chaque `up`. Modifiez le message d'accueil dans le code, avec `sed`, qui remplace ici `Bonjour` par `Bienvenue` directement dans le fichier. L'option `-i.bak` garde une copie de l'ancien fichier sous le nom `app.py.bak`, et cette écriture marche sur tous les systèmes. Puis relancez sans `--build` :

```exec
sed -i.bak 's/"Bonjour"/"Bienvenue"/' ~/layers-l7/counter/app.py
cd ~/layers-l7/counter && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Le message n'a pas changé : l'image existe déjà, Compose la réutilise et ne touche à rien. Votre code est dans l'image, et l'image n'a pas été refaite. Relancez cette fois avec `--build`. Comptez une dizaine de secondes, car Compose doit d'abord arrêter l'ancien `web` : notre programme Python, comme `sleep` dans « Lancer, configurer et observer un conteneur », ignore la demande d'arrêt, et Docker le tue à la fin du délai. Vous retrouverez cette attente à chaque arrêt de `web`.

```exec
cd ~/layers-l7/counter && docker compose up -d --build
sleep 1
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Vous devez lire `Bienvenue ! Visites : ...`. Le compteur continue, car seul `web` a été recréé : `cache` n'a pas changé. `up` compare ce que vous décrivez à ce qui tourne, et ne refait que la différence.

```verify
if ! curl -s --max-time 5 http://localhost:28370 | grep -q 'Bienvenue'; then
  echo "Le message n'est pas encore Bienvenue. Lancez docker compose up -d --build dans ~/layers-l7/counter."
  exit 1
fi
echo "L'image reconstruite est en service."
```

> 📖 [`build` dans Compose](https://docs.docker.com/reference/compose-file/build/) · [Les réseaux dans Compose](https://docs.docker.com/compose/how-tos/networking/) · [`environment`](https://docs.docker.com/reference/compose-file/services/#environment)

## Questions

```quiz
title: "Plusieurs services"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Le service `web` doit joindre le service `cache`. Quelle adresse utilise-t-il ?"
    answers:
      - "`localhost`, car ils sont dans le même projet"
      - "`cache`, le nom du service, que Docker résout sur le réseau du projet"
      - "L'adresse IP de la machine"
    correct: 2
    explanation: "Chaque conteneur a son propre `localhost`. Sur le réseau du projet, le nom du service sert d'adresse."
  - prompt: "Vous modifiez le code copié dans l'image, puis vous lancez `docker compose up -d`. Que se passe-t-il ?"
    answers:
      - "Compose détecte le changement et reconstruit"
      - "Rien : l'image existe déjà, il faut `--build` pour la refaire"
      - "Compose supprime tous les conteneurs et repart de zéro"
    correct: 2
    explanation: "Sans `--build`, `up` réutilise l'image existante. Le code modifié n'y entre pas."
  - prompt: "Pourquoi le service `cache` n'a-t-il pas de clé `ports` ?"
    answers:
      - "Redis ne sait pas utiliser de port"
      - "Parce que `web` le joint par le réseau du projet, et que rien d'autre n'a à l'appeler"
      - "Parce que Compose le publie automatiquement"
    correct: 2
    explanation: "`ports` ouvre un accès depuis la machine. Entre services du même réseau, ce n'est pas nécessaire, et ne rien publier réduit ce qui est exposé."
```
