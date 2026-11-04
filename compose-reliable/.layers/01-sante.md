---
title: "Savoir qu'un service est prêt"
description: "Le contrôle de santé, depends_on avec condition, et ce que unhealthy ne fait pas"
---

Pour Docker, un conteneur va bien tant que son processus principal tourne. Cela ne dit pas que le service répond : une base de données peut tourner et s'initialiser encore, un serveur peut tourner et ne plus rien servir. Cette étape apprend à Docker à poser la vraie question.

## L'application de départ

Créez son code. Vous n'avez pas besoin de lire Python : l'application écoute sur le port 8000 et compte les visites dans Redis. Son adresse `/health` répond seulement si Redis répond : une telle adresse existe précisément pour les contrôles de santé. Son adresse `/crash` arrête brutalement le programme, pour que ce cours puisse simuler une panne. `cat > fichier <<'EOF'` écrit dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` :

```exec
mkdir -p ~/layers-l8/reliable
cat > ~/layers-l8/reliable/app.py <<'EOF'
import os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
PASSWORD_FILE = os.environ.get("REDIS_PASSWORD_FILE")

def redis_call(command):
    with socket.create_connection((REDIS_HOST, 6379), timeout=2) as redis:
        if PASSWORD_FILE:
            password = open(PASSWORD_FILE).read().strip()
            redis.sendall(f"AUTH {password}\r\n".encode())
            redis.recv(64)
        redis.sendall(command + b"\r\n")
        return redis.recv(64).decode().strip()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/crash":
            os._exit(1)
        if self.path == "/health":
            if redis_call(b"PING") != "+PONG":
                raise RuntimeError("Redis ne répond pas PONG")
            body = "ok\n"
        else:
            body = f"Visites : {redis_call(b'INCR visits').lstrip(':')}\n"
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body.encode())

HTTPServer(("", 8000), Handler).serve_forever()
EOF
cat > ~/layers-l8/reliable/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF
```

## Le problème

Voici le fichier Compose, sans aucune protection. Pour rendre la panne visible, `cache` attend 6 secondes avant de lancer Redis, comme le ferait une base de données qui s'initialise. `sh -c` fait exécuter la phrase par un shell, et `exec` lui fait céder sa place à Redis, qui devient le processus principal :

```exec
cat > ~/layers-l8/reliable/compose.yaml <<'EOF'
name: layers-l8-reliable
services:
  web:
    build: .
    ports:
      - "28382:8000"
    environment:
      REDIS_HOST: cache
    depends_on:
      - cache
  cache:
    image: redis:8-alpine
    command: ["sh", "-c", "sleep 6 && exec redis-server"]
EOF
```

Démarrez et demandez la page aussitôt. Pour `curl`, `-s` masque la progression, `-o /dev/null` jette le contenu de la page, `--max-time 2` abandonne après 2 secondes, et `-w` affiche le code de la réponse HTTP :

```exec
cd ~/layers-l8/reliable && docker compose up -d --build
sleep 1
curl -s --max-time 2 -o /dev/null -w 'code HTTP : %{http_code}\n' http://localhost:28382
```

Vous lisez `code HTTP : 000` : aucune réponse. `up` a rendu la main, `depends_on` a bien démarré `cache` en premier, et pourtant l'application échoue. Le conteneur `cache` tourne, mais Redis n'a pas encore démarré. Le `docker compose ps` le confirme, puisqu'il voit deux services `Up` :

```exec
cd ~/layers-l8/reliable && docker compose ps --format '{{.Service}} : {{.Status}}'
```

```ack
J'ai vu l'application échouer alors que tout semble démarré
```

## Le contrôle de santé

Un **contrôle de santé**, ou *healthcheck*, est une commande que Docker lance régulièrement dans le conteneur. Si elle sort avec le code 0, le service va bien. Le voici sur `cache`, où `redis-cli ping` interroge Redis :

```yaml
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 2s
      retries: 10
```

Voici le rôle de chaque clé :

| Clé | Rôle |
|---|---|
| `test` | la commande ; `CMD` veut dire qu'elle se lance directement, sans shell |
| `interval` | le temps entre deux contrôles |
| `timeout` | au-delà, le contrôle compte comme un échec |
| `retries` | le nombre d'échecs de suite avant de déclarer le service `unhealthy` |
| `start_period` | un temps de démarrage pendant lequel un échec ne compte pas ; vous le verrez plus bas |

Le conteneur passe alors par trois états : `starting`, puis `healthy` ou `unhealthy`. Reste à s'en servir : la forme longue de `depends_on` accepte une **condition**, et `service_healthy` demande à Compose d'attendre.

Réécrivez le fichier avec ces deux ajouts, plus un contrôle de santé sur `web`, qui appelle `/health` avec le Python de l'image, puisque cette image n'a pas `curl` :

```exec
cat > ~/layers-l8/reliable/compose.yaml <<'EOF'
name: layers-l8-reliable
services:
  web:
    build: .
    ports:
      - "28382:8000"
    environment:
      REDIS_HOST: cache
    depends_on:
      cache:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health', timeout=2)"]
      interval: 3s
      timeout: 3s
      retries: 2
      start_period: 5s
  cache:
    image: redis:8-alpine
    command: ["sh", "-c", "sleep 6 && exec redis-server"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 2s
      retries: 10
EOF
```

Repartez de zéro et lancez la même séquence. Cette fois, prévoyez ce que vous allez voir. `--retry` recommence quelques fois en cas d'erreur, à 1 seconde d'intervalle, ce qui laisse à `web` le temps de démarrer :

```exec
cd ~/layers-l8/reliable && docker compose down && docker compose up -d
sleep 1
curl -s --retry 5 --retry-delay 1 --retry-all-errors --max-time 2 -o /dev/null -w 'code HTTP : %{http_code}\n' http://localhost:28382
```

`up` affiche `Waiting`, attend plusieurs secondes sur `cache`, affiche `Healthy`, et seulement alors démarre `web`. La page répond `200`. Regardez les états : `ps` les affiche entre parenthèses.

```exec
sleep 5
cd ~/layers-l8/reliable && docker compose ps --format '{{.Service}} : {{.Status}}'
```

```verify
for C in cache web; do
  H=$(docker inspect layers-l8-reliable-$C-1 --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}' 2>/dev/null)
  if [ "$H" != "healthy" ]; then
    echo "$C n'est pas healthy (état : ${H:-conteneur absent}). Attendez quelques secondes, ou lisez : docker compose logs $C"
    exit 1
  fi
done
case "$(docker inspect layers-l8-reliable-web-1 --format '{{index .Config.Labels "com.docker.compose.depends_on"}}')" in
  *service_healthy*) : ;;
  *) echo "web n'attend pas que cache soit healthy : il manque condition: service_healthy."; exit 1 ;;
esac
echo "Les deux services sont healthy, et web attend cache."
```

## Ce que unhealthy ne fait pas

Provoquez une panne : arrêtez Redis, attendez, regardez. Il faut deux échecs de suite, à 3 secondes d'intervalle :

```exec
cd ~/layers-l8/reliable && docker compose stop cache
sleep 12
cd ~/layers-l8/reliable && docker compose ps --format '{{.Service}} : {{.Status}}'
```

`web` s'affiche `Up ... (unhealthy)`. Il est signalé, **mais il tourne toujours** : sur un seul serveur, Compose et Docker n'agissent pas sur cet état. Un conteneur `unhealthy` n'est pas relancé tout seul. Ce signal sert aux humains, aux outils de surveillance, aux dépendances, et à un orchestrateur comme Swarm, qu'un prochain cours présente.

La fiche du conteneur garde les derniers résultats. Cette commande affiche le code de sortie de chacun :

```exec
docker inspect layers-l8-reliable-web-1 --format '{{range .State.Health.Log}}{{.ExitCode}} {{end}}'
```

Un `1` veut dire échec. Relancez Redis et attendez le retour à la normale :

```exec
cd ~/layers-l8/reliable && docker compose start cache
sleep 12
cd ~/layers-l8/reliable && docker compose ps --format '{{.Service}} : {{.Status}}'
```

```verify
if [ "$(docker inspect layers-l8-reliable-web-1 --format '{{.State.Health.Status}}' 2>/dev/null)" != "healthy" ]; then
  echo "web n'est pas redevenu healthy. Vérifiez que cache tourne (docker compose start cache), puis attendez quelques secondes."
  exit 1
fi
if ! docker inspect layers-l8-reliable-web-1 --format '{{range .State.Health.Log}}{{.ExitCode}} {{end}}' >/dev/null 2>&1; then
  echo "La fiche de web n'a pas de journal de santé."
  exit 1
fi
if [ "$(docker inspect layers-l8-reliable-cache-1 --format '{{.State.FinishedAt}}')" = "0001-01-01T00:00:00Z" ]; then
  echo "cache n'a pas encore été arrêté. Lancez la commande docker compose stop cache."
  exit 1
fi
echo "La panne a été vue, puis le service est redevenu healthy."
```

> 📖 [`healthcheck` dans Compose](https://docs.docker.com/reference/compose-file/services/#healthcheck) · [`depends_on`](https://docs.docker.com/reference/compose-file/services/#depends_on) · [Contrôler l'ordre de démarrage](https://docs.docker.com/compose/how-tos/startup-order/) · [`HEALTHCHECK` dans un Dockerfile](https://docs.docker.com/reference/dockerfile/#healthcheck)

## Questions

```quiz
title: "Savoir qu'un service est prêt"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`web` a `depends_on: [db]` sous sa forme courte. Qu'attend Compose avant de démarrer `web` ?"
    answers:
      - "Que `db` réponde à ses requêtes"
      - "Que le conteneur `db` soit démarré, sans rien savoir de ce qu'il fait"
      - "Rien du tout"
    correct: 2
    explanation: "C'est la condition `service_started`. Pour attendre que le service soit prêt, il faut un healthcheck et `condition: service_healthy`."
  - prompt: "Un conteneur passe `unhealthy`. Que fait Docker, sur une seule machine et sans orchestrateur ?"
    answers:
      - "Il le relance aussitôt"
      - "Il le supprime et en crée un autre"
      - "Il le signale dans son état, et le laisse tourner"
    correct: 3
    explanation: "Vous l'avez constaté : `web` était `Up (unhealthy)`. La politique de redémarrage réagit à la fin du processus, pas au contrôle de santé."
  - prompt: "À quoi sert `start_period` ?"
    answers:
      - "À retarder le démarrage du conteneur"
      - "À laisser au service le temps de démarrer, sans compter ses échecs"
      - "À fixer le temps entre deux contrôles"
    correct: 2
    explanation: "Pendant cette période, un échec ne compte pas dans `retries`, et un succès fait passer aussitôt à `healthy`."
```
