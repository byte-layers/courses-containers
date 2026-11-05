---
title: "Une stack prête pour la production"
description: "Sans guide : secret, reverse proxy, contrôles de santé, durcissement, limites et preuve de résistance sur une application de trois services."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 90
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce challenge prouve que vous savez exploiter une application avec Compose. Le code est fourni, mais **pas le fichier Compose, ni la configuration du proxy** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker. Toute écriture qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseignent « Un secret ne va pas dans l'image », le cours « Fiabiliser une application Compose » et le lab « Plusieurs applications derrière un reverse proxy ».
- **Ce qu'il faut avoir** : Docker et Compose qui répondent, `curl`, un éditeur de texte et le port 28385 libre.
- **Votre dossier de travail** : `~/layers-l8/prod` est préparé pour vous à l'ouverture de la tâche 1. La vérification y garde aussi un fichier caché, `.prod-id`, qui lui sert à reconnaître votre conteneur.
- **Les noms comptent** : le projet s'appelle exactement `layers-l8-prod`, et ses services `proxy`, `api` et `cache`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche enrichit le fichier de la précédente. Faites-les dans l'ordre.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.

## L'application

Elle compte des visites. Voici ce que vous allez mettre en place :

```
votre machine ──► proxy (nginx, port 80) ──► api (Python, port 8000) ──► cache (Redis, port 6379)
```

Le dossier `~/layers-l8/prod` reçoit les fichiers suivants à l'ouverture de la tâche 1. Lisez-les alors : ils disent ce qu'attend chaque service.

| Fichier | Ce qu'il contient |
|---|---|
| `api/app.py` | le serveur Python. Il écoute sur le port 8000 et lit deux variables : `REDIS_HOST`, l'adresse de Redis, et `REDIS_PASSWORD_FILE`, le chemin du fichier qui contient le mot de passe. Son adresse `/health` répond si Redis répond, et `/crash` arrête brutalement le programme |
| `api/Dockerfile` | de quoi construire son image, encore en `root` : c'est à vous de changer cela à la tâche 4 |

# Tâche 1 : un secret qui reste secret

## Ce qu'il faut faire

```setup
mkdir -p ~/layers-l8/prod/api ~/layers-l8/prod/proxy
cat > ~/layers-l8/prod/api/app.py <<'EOF'
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
cat > ~/layers-l8/prod/api/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF
```

Écrivez `~/layers-l8/prod/compose.yaml` pour les services `api` et `cache`, et protégez Redis par un mot de passe.

**Critères :**

- le mot de passe est dans `~/layers-l8/prod/secrets/redis_password.txt`, et ce chemin est écarté de Git par un `.gitignore` ;
- `api` et `cache` tournent : `api` construit depuis `api/Dockerfile`, `cache` depuis `redis:8-alpine` ;
- Redis refuse une commande sans mot de passe, et accepte celui du fichier ;
- `api` compte bien les visites ;
- le mot de passe n'apparaît ni dans `docker inspect`, ni dans l'historique de l'image : il arrive comme un fichier, dans `/run/secrets/redis_password` ;
- Redis écrit sur le disque, dans un **volume nommé** du projet monté sur `/data` ;
- aucun port n'est publié pour l'instant.

```hint
Le secret se déclare en bas du fichier et s'utilise dans chaque service qui en a besoin. Écrivez le fichier sans retour à la ligne final, avec `printf`.
```

```hint
Redis a besoin d'un petit shell pour lire son mot de passe, avec `--requirepass`, et d'un `$$` dans le fichier Compose pour faire arriver un vrai `$` à ce shell.
```

```hint
Pour tester `api` sans port publié : `docker compose exec api python -c "import urllib.request as u; print(u.urlopen('http://localhost:8000/').read())"`
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
A=$(cid api); R=$(cid cache)
if [ -z "$A" ] || [ -z "$R" ]; then
  echo "ÉCHEC : api et cache doivent tourner dans le projet $P. Écrivez $D/compose.yaml et lancez docker compose up -d --build depuis ce dossier."
  exit 1
fi
F=$D/secrets/redis_password.txt
if [ ! -s "$F" ]; then
  echo "ÉCHEC : le fichier $F est absent ou vide."
  exit 1
fi
PW=$(cat "$F")
if ! grep -Eq 'secrets|redis_password' "$D/.gitignore" 2>/dev/null; then
  echo "ÉCHEC : $D/.gitignore n'écarte pas le fichier du secret."
  exit 1
fi
case "$(docker inspect "$R" --format '{{.Config.Image}}')" in redis:8-alpine*) : ;; *) echo "ÉCHEC : cache doit utiliser redis:8-alpine."; exit 1 ;; esac
case "$(docker inspect "$A" --format '{{.Config.Image}}')" in python:*) echo "ÉCHEC : api doit être construit depuis api/Dockerfile."; exit 1 ;; esac
if ! docker exec "$R" redis-cli ping 2>/dev/null | grep -q NOAUTH; then
  echo "ÉCHEC : Redis répond sans mot de passe."
  exit 1
fi
if ! docker exec "$R" redis-cli -a "$PW" --no-auth-warning ping 2>/dev/null | grep -q PONG; then
  echo "ÉCHEC : Redis n'accepte pas le mot de passe du fichier."
  exit 1
fi
if ! docker exec "$A" python -c "import urllib.request as u; print(u.urlopen('http://localhost:8000/').read())" 2>/dev/null | grep -q Visites; then
  echo "ÉCHEC : api ne compte pas les visites. Il lui faut REDIS_HOST, REDIS_PASSWORD_FILE et le secret. Lisez : docker compose logs api"
  exit 1
fi
if docker inspect "$A" "$R" | grep -qF -- "$PW"; then
  echo "ÉCHEC : le mot de passe apparaît dans docker inspect : il est passé par une variable ou une commande en clair."
  exit 1
fi
if docker history --no-trunc "$(docker inspect "$A" --format '{{.Image}}')" | grep -qF -- "$PW"; then
  echo "ÉCHEC : le mot de passe apparaît dans l'historique de l'image."
  exit 1
fi
if [ "$(docker exec "$A" cat /run/secrets/redis_password 2>/dev/null)" != "$PW" ]; then
  echo "ÉCHEC : api ne lit pas le mot de passe dans /run/secrets/redis_password."
  exit 1
fi
SRC=$(docker inspect "$R" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}')
case "$SRC" in
  volume:layers-l8-prod_*) : ;;
  *) echo "ÉCHEC : cache n'a pas de volume nommé du projet sur /data (trouvé : ${SRC:-rien})."; exit 1 ;;
esac
if ! docker exec "$R" redis-cli -a "$PW" --no-auth-warning config get appendonly | grep -q yes; then
  echo "ÉCHEC : Redis n'écrit pas sur le disque : il lui manque --appendonly yes."
  exit 1
fi
for C in "$A" "$R"; do
  if [ -n "$(docker port "$C")" ]; then
    echo "ÉCHEC : un service publie un port. Aucun ne doit le faire à ce stade."
    exit 1
  fi
done
echo "RÉUSSI : Redis exige son mot de passe, et ce secret n'existe qu'en fichier."
```

````solution
```bash
cd ~/layers-l8/prod
mkdir -p secrets && chmod 700 secrets
printf 'un-mot-de-passe-de-demo' > secrets/redis_password.txt
printf 'secrets/\n' > .gitignore
printf 'secrets/\n' > api/.dockerignore
cat > ~/layers-l8/prod/compose.yaml <<'EOF'
name: layers-l8-prod
services:
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
      REDIS_PASSWORD_FILE: /run/secrets/redis_password
    secrets:
      - redis_password
    depends_on:
      - cache
  cache:
    image: redis:8-alpine
    user: redis
    command: ["sh", "-c", "exec redis-server --appendonly yes --requirepass \"$$(cat /run/secrets/redis_password)\""]
    secrets:
      - redis_password
    volumes:
      - cache-data:/data
volumes:
  cache-data:
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
cd ~/layers-l8/prod && docker compose up -d --build
sleep 3
```
````

# Tâche 2 : une seule porte d'entrée

## Ce qu'il faut faire

Ajoutez un service `proxy` devant l'application.

**Critères :**

- `proxy` utilise `nginx:1.30-alpine`, et lit sa configuration dans un dossier `~/layers-l8/prod/proxy` que vous remplissez ;
- le port **28385** de la machine mène à son port **80**, et c'est le seul port publié ;
- `http://localhost:28385/` répond avec un message de votre choix, sans appeler `api` ;
- `http://localhost:28385/api/` renvoie le compteur de `api`, qui reçoit l'adresse sans le préfixe ;
- le proxy résout le nom de `api` à chaque demande : il ne doit pas s'arrêter si `api` est absente à son démarrage ;
- `proxy` et `cache` ne partagent aucun réseau.

```hint
Il faut deux réseaux à vous : `api` est sur les deux. Faites `docker compose down` avant de changer les réseaux dans le fichier, pour ne pas laisser le réseau par défaut derrière vous.
```

```hint
Les trois lignes clés d'un bloc `location` : un `set` qui met l'adresse dans une variable, un `rewrite` qui retire le préfixe, un `proxy_pass` qui utilise la variable. Et `resolver 127.0.0.11` dans le bloc `server`. N'oubliez pas le port de `api`.
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
X=$(cid proxy)
if [ -z "$X" ]; then
  echo "ÉCHEC : le service proxy ne tourne pas. Lisez : docker compose logs proxy"
  exit 1
fi
case "$(docker inspect "$X" --format '{{.Config.Image}}')" in nginx:1.30-alpine*) : ;; *) echo "ÉCHEC : proxy doit utiliser nginx:1.30-alpine."; exit 1 ;; esac
case "$(docker port "$X" 80/tcp 2>/dev/null)" in
  *:28385*) : ;;
  *) echo "ÉCHEC : le port 28385 de la machine ne mène pas au port 80 du proxy."; exit 1 ;;
esac
for S in api cache; do
  if [ -n "$(docker port "$(cid $S)")" ]; then
    echo "ÉCHEC : $S publie un port. Le proxy doit être la seule porte d'entrée."
    exit 1
  fi
done
if ! curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:28385/ | grep -q 200; then
  echo "ÉCHEC : http://localhost:28385/ ne répond pas avec un code 200."
  exit 1
fi
if curl -s --max-time 5 http://localhost:28385/ | grep -q Visites; then
  echo "ÉCHEC : l'adresse / appelle api : elle doit répondre sans passer par lui."
  exit 1
fi
N1=$(curl -s --max-time 5 http://localhost:28385/api/ | sed -n 's/^Visites : //p')
if [ -z "$N1" ]; then
  echo "ÉCHEC : http://localhost:28385/api/ ne renvoie pas le compteur. Un 502 : mauvaise adresse, ou mauvais port pour api."
  exit 1
fi
if [ "$(curl -s --max-time 5 http://localhost:28385/api/health)" != "ok" ]; then
  echo "ÉCHEC : http://localhost:28385/api/health ne répond pas ok : api reçoit encore le préfixe /api. Il manque le rewrite."
  exit 1
fi
if ! docker inspect "$X" --format '{{range .Mounts}}{{.Source}} {{.Destination}}{{println}}{{end}}' | grep -Eq '/layers-l8/prod/proxy[^ ]* /etc/nginx/conf\.d'; then
  echo "ÉCHEC : proxy ne lit pas sa configuration dans ~/layers-l8/prod/proxy, monté sur /etc/nginx/conf.d."
  exit 1
fi
CONF=$(docker exec "$X" nginx -T 2>/dev/null)
if ! echo "$CONF" | grep -Eq '(^|[[:space:];{])resolver[[:space:]]+127\.0\.0\.11'; then
  echo "ÉCHEC : la configuration du proxy n'a pas de resolver vers 127.0.0.11."
  exit 1
fi
if ! echo "$CONF" | grep -Eq '(^|[[:space:];{])proxy_pass[[:space:]]+(http://)?\$'; then
  echo "ÉCHEC : proxy_pass n'utilise pas de variable : nginx résoudrait le nom seulement à son démarrage."
  exit 1
fi
if docker exec "$X" ping -c 1 -W 1 cache >/dev/null 2>&1; then
  echo "ÉCHEC : proxy joint cache. Ces deux services ne doivent partager aucun réseau."
  exit 1
fi
echo "RÉUSSI : une seule porte, et le proxy ne dépend plus de l'ordre de démarrage."
```

````solution
```bash
cd ~/layers-l8/prod && docker compose down
cat > ~/layers-l8/prod/proxy/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;
    resolver 127.0.0.11 valid=5s;

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /api/ {
        set $upstream http://api:8000;
        rewrite ^/api/(.*)$ /$1 break;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass $upstream;
    }
}
EOF
cat > ~/layers-l8/prod/compose.yaml <<'EOF'
name: layers-l8-prod
services:
  proxy:
    image: nginx:1.30-alpine
    ports:
      - "28385:80"
    volumes:
      - ./proxy:/etc/nginx/conf.d:ro
    networks:
      - edge
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
      REDIS_PASSWORD_FILE: /run/secrets/redis_password
    secrets:
      - redis_password
    depends_on:
      - cache
    networks:
      - edge
      - back
  cache:
    image: redis:8-alpine
    user: redis
    command: ["sh", "-c", "exec redis-server --appendonly yes --requirepass \"$$(cat /run/secrets/redis_password)\""]
    secrets:
      - redis_password
    volumes:
      - cache-data:/data
    networks:
      - back
volumes:
  cache-data:
networks:
  edge:
  back:
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
cd ~/layers-l8/prod && docker compose up -d --build
sleep 3
```
````

# Tâche 3 : savoir que tout va bien

## Ce qu'il faut faire

Docker doit savoir si chaque service répond vraiment, et relancer ceux qui s'arrêtent.

**Critères :**

- `proxy`, `api` et `cache` ont un contrôle de santé, et sont `healthy` ;
- le contrôle de `cache` vérifie la vraie réponse `PONG` : `redis-cli ping`, seul, sort avec le code 0 même après un refus ;
- `api` attend que `cache` soit `healthy` avant de démarrer ;
- les trois services ont une politique de redémarrage `unless-stopped` ou `always`.

```hint
L'image de nginx n'a pas `curl`, mais elle a `wget` : interrogez `http://127.0.0.1/`, car `localhost` peut viser une adresse IPv6 où ce nginx n'écoute pas. L'image de Python n'a aucun des deux, mais elle a Python.
```

```hint
Si vous utilisez `--wait` avec `docker compose up -d`, la commande attend que tout soit `healthy`, et échoue sinon.
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
for S in proxy api cache; do
  C=$(cid $S)
  if [ -z "$C" ]; then
    echo "ÉCHEC : le service $S ne tourne pas."
    exit 1
  fi
  H=$(docker inspect "$C" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}')
  if [ "$H" != "healthy" ]; then
    echo "ÉCHEC : $S a l'état de santé « $H ». Il faut un contrôle qui réussit : attendez quelques secondes, ou lisez docker inspect $C."
    exit 1
  fi
  case "$(docker inspect "$C" --format '{{.HostConfig.RestartPolicy.Name}}')" in
    unless-stopped|always) : ;;
    *) echo "ÉCHEC : $S n'a pas de politique unless-stopped ou always."; exit 1 ;;
  esac
done
case "$(docker inspect "$(cid cache)" --format '{{json .Config.Healthcheck.Test}}')" in
  *PONG*) : ;;
  *) echo "ÉCHEC : le contrôle de cache ne vérifie pas la réponse PONG."; exit 1 ;;
esac
case "$(docker inspect "$(cid api)" --format '{{index .Config.Labels "com.docker.compose.depends_on"}}')" in
  *cache:service_healthy*) : ;;
  *) echo "ÉCHEC : api n'attend pas que cache soit healthy."; exit 1 ;;
esac
echo "RÉUSSI : les trois services sont healthy, et ils repartiront tout seuls."
```

````solution
```bash
cat > ~/layers-l8/prod/compose.yaml <<'EOF'
name: layers-l8-prod
services:
  proxy:
    image: nginx:1.30-alpine
    restart: unless-stopped
    ports:
      - "28385:80"
    volumes:
      - ./proxy:/etc/nginx/conf.d:ro
    networks:
      - edge
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1/ >/dev/null"]
      interval: 5s
      timeout: 3s
      retries: 3
  api:
    build: ./api
    restart: unless-stopped
    environment:
      REDIS_HOST: cache
      REDIS_PASSWORD_FILE: /run/secrets/redis_password
    secrets:
      - redis_password
    depends_on:
      cache:
        condition: service_healthy
    networks:
      - edge
      - back
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health', timeout=2)"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 5s
  cache:
    image: redis:8-alpine
    restart: unless-stopped
    user: redis
    command: ["sh", "-c", "exec redis-server --appendonly yes --requirepass \"$$(cat /run/secrets/redis_password)\""]
    secrets:
      - redis_password
    volumes:
      - cache-data:/data
    networks:
      - back
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$(cat /run/secrets/redis_password)\" --no-auth-warning ping | grep -q PONG"]
      interval: 5s
      timeout: 3s
      retries: 5
volumes:
  cache-data:
networks:
  edge:
  back:
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
cd ~/layers-l8/prod && docker compose up -d --wait --wait-timeout 45
```
````

# Tâche 4 : durcir et borner

## Ce qu'il faut faire

Réduisez ce qu'un attaquant pourrait faire, et bornez les ressources de chaque service.

**Critères :**

- l'image de `api` tourne sous un utilisateur ordinaire, défini par `USER` dans `api/Dockerfile` ;
- `cache` ne tourne pas en `root` ;
- les trois services ont un système de fichiers en lecture seule, et `no-new-privileges` ;
- `api` et `cache` ont retiré toutes leurs capabilities ;
- les trois services ont une limite de mémoire, et leurs logs sont plafonnés avec `max-size` ;
- tout reste `healthy`, et `http://localhost:28385/api/` répond.

```hint
nginx a besoin d'écrire à quelques endroits, même en lecture seule : donnez-lui des `tmpfs` sur `/var/cache/nginx`, `/var/run` et `/tmp`. Il garde ses capabilities, car il démarre en `root` pour ouvrir le port 80.
```

```hint
Si Redis affiche `Permission denied` après `cap_drop`, il lui faut `user: redis`. Et si ses fichiers ont déjà été écrits en `root`, ce qui arrive quand sa commande passe par `sh -c`, le nouvel utilisateur ne peut plus y toucher : ici, le compteur n'est qu'un essai, donc repartez d'un volume neuf avec `docker compose down -v`.
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
A=$(cid api); R=$(cid cache); X=$(cid proxy)
if [ -z "$A" ] || [ -z "$R" ] || [ -z "$X" ]; then
  echo "ÉCHEC : les trois services doivent tourner. Lisez : docker compose ps -a, puis docker compose logs."
  exit 1
fi
IMG=$(docker inspect "$A" --format '{{.Image}}')
U=$(docker image inspect "$IMG" --format '{{.Config.User}}')
if [ -z "$U" ] || [ "$U" = "root" ] || [ "$U" = "0" ]; then
  echo "ÉCHEC : l'image de api n'a pas d'instruction USER. Ajoutez-la à api/Dockerfile, puis reconstruisez avec --build."
  exit 1
fi
if [ "$(docker exec "$A" id -u)" = "0" ]; then
  echo "ÉCHEC : api tourne en root."
  exit 1
fi
if [ "$(docker exec "$R" id -u)" = "0" ]; then
  echo "ÉCHEC : cache tourne en root."
  exit 1
fi
for C in "$X" "$A" "$R"; do
  S=$(docker inspect "$C" --format '{{index .Config.Labels "com.docker.compose.service"}}')
  if [ "$(docker inspect "$C" --format '{{.HostConfig.ReadonlyRootfs}}')" != "true" ]; then
    echo "ÉCHEC : $S n'a pas read_only: true."
    exit 1
  fi
  case "$(docker inspect "$C" --format '{{.HostConfig.SecurityOpt}}')" in
    *no-new-privileges*) : ;;
    *) echo "ÉCHEC : $S n'a pas no-new-privileges."; exit 1 ;;
  esac
  if [ "$(docker inspect "$C" --format '{{.HostConfig.Memory}}')" = "0" ]; then
    echo "ÉCHEC : $S n'a pas de limite de mémoire."
    exit 1
  fi
  if [ -z "$(docker inspect "$C" --format '{{index .HostConfig.LogConfig.Config "max-size"}}')" ]; then
    echo "ÉCHEC : les logs de $S ne sont pas plafonnés avec max-size."
    exit 1
  fi
  if [ "$(docker inspect "$C" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')" != "healthy" ]; then
    echo "ÉCHEC : $S n'est pas healthy. Attendez quelques secondes, ou lisez ses logs."
    exit 1
  fi
done
for C in "$A" "$R"; do
  case "$(docker inspect "$C" --format '{{.HostConfig.CapDrop}}')" in
    *ALL*) : ;;
    *) echo "ÉCHEC : $(docker inspect "$C" --format '{{index .Config.Labels "com.docker.compose.service"}}') n'a pas cap_drop: [ALL]."; exit 1 ;;
  esac
done
if ! curl -s --max-time 5 http://localhost:28385/api/ | grep -q Visites; then
  echo "ÉCHEC : http://localhost:28385/api/ ne répond plus."
  exit 1
fi
echo "RÉUSSI : sans root, en lecture seule, avec des limites, et tout répond."
```

````solution
Le fichier final se trouve aussi dans le dossier `solution/` de ce contenu.

```bash
cat > ~/layers-l8/prod/api/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
RUN adduser -D -u 10001 appuser
USER appuser
CMD ["python", "-u", "app.py"]
EOF
cat > ~/layers-l8/prod/compose.yaml <<'EOF'
name: layers-l8-prod
services:
  proxy:
    image: nginx:1.30-alpine
    restart: unless-stopped
    ports:
      - "28385:80"
    volumes:
      - ./proxy:/etc/nginx/conf.d:ro
    networks:
      - edge
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1/ >/dev/null"]
      interval: 5s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 64M
    logging:
      driver: json-file
      options:
        max-size: "1m"
        max-file: "3"
    read_only: true
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
    security_opt:
      - no-new-privileges:true
  api:
    build: ./api
    restart: unless-stopped
    init: true
    environment:
      REDIS_HOST: cache
      REDIS_PASSWORD_FILE: /run/secrets/redis_password
    secrets:
      - redis_password
    networks:
      - edge
      - back
    depends_on:
      cache:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health', timeout=2)"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 5s
    deploy:
      resources:
        limits:
          memory: 128M
          pids: 100
    logging:
      driver: json-file
      options:
        max-size: "1m"
        max-file: "3"
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
  cache:
    image: redis:8-alpine
    restart: unless-stopped
    user: redis
    command: ["sh", "-c", "exec redis-server --appendonly yes --requirepass \"$$(cat /run/secrets/redis_password)\""]
    secrets:
      - redis_password
    volumes:
      - cache-data:/data
    networks:
      - back
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$(cat /run/secrets/redis_password)\" --no-auth-warning ping | grep -q PONG"]
      interval: 5s
      timeout: 3s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 256M
          pids: 100
    logging:
      driver: json-file
      options:
        max-size: "1m"
        max-file: "3"
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
volumes:
  cache-data:
networks:
  edge:
  back:
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
cd ~/layers-l8/prod && docker compose down
cd ~/layers-l8/prod && docker compose up -d --build --wait --wait-timeout 45
```
````

# Tâche 5 : résister à une panne

## Ce qu'il faut faire

Provoquez une vraie panne de `api`, en appelant `http://localhost:28385/api/crash`, et laissez le système se rétablir sans intervenir.

**Critères :**

- `api` a redémarré tout seul au moins une fois depuis votre dernière recréation ;
- il est de nouveau `healthy` ;
- `http://localhost:28385/api/` répond.

La vérification note l'état du compteur : il servira à la tâche 6.

```hint
Une seule commande `curl` provoque la panne. Le proxy répond alors `502 Bad Gateway` : c'est normal, `api` vient de s'arrêter. Attendez quelques secondes avant de vérifier.
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
A=$(cid api); R=$(cid cache)
if [ -z "$A" ]; then
  echo "ÉCHEC : api ne tourne pas : il n'a pas redémarré tout seul. Vérifiez sa politique de redémarrage."
  exit 1
fi
N=$(docker inspect "$A" --format '{{.RestartCount}}')
if [ "$N" -lt 1 ]; then
  echo "ÉCHEC : api n'a jamais redémarré. Provoquez la panne avec curl, sur l'adresse /api/crash."
  exit 1
fi
if [ "$(docker inspect "$A" --format '{{.State.Health.Status}}')" != "healthy" ]; then
  echo "ÉCHEC : api n'est pas encore healthy. Attendez quelques secondes et réessayez."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28385/api/ | grep -q Visites; then
  echo "ÉCHEC : http://localhost:28385/api/ ne répond pas."
  exit 1
fi
PW=$(cat "$D/secrets/redis_password.txt")
V=$(docker exec "$R" redis-cli -a "$PW" --no-auth-warning get visits)
docker inspect "$R" --format '{{.Id}}' > "$D/.prod-id"
echo "$V" >> "$D/.prod-id"
echo "RÉUSSI : api a redémarré $N fois, seul, et le compteur vaut $V."
```

````solution
```bash
curl -s --max-time 2 -o /dev/null http://localhost:28385/api/crash
sleep 8
```
````

# Tâche 6 : garder les données

## Ce qu'il faut faire

Supprimez tous les conteneurs du projet, puis recréez-les, sans perdre le compteur.

**Critères :**

- le conteneur `cache` n'est plus celui de la tâche 5 ;
- le compteur vaut au moins sa valeur de la tâche 5 ;
- l'application répond de nouveau par le proxy, et tout est `healthy`.

```hint
Parmi les options de la commande qui supprime les conteneurs, l'une supprime aussi les volumes : c'est celle à éviter ici.
```

```verify
P=layers-l8-prod; D=~/layers-l8/prod
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
R=$(cid cache)
if [ -z "$R" ]; then
  echo "ÉCHEC : cache ne tourne pas. Après la suppression, il reste à recréer les conteneurs."
  exit 1
fi
REF=$(sed -n 1p "$D/.prod-id" 2>/dev/null); OLD=$(sed -n 2p "$D/.prod-id" 2>/dev/null)
if [ -z "$REF" ]; then
  echo "ÉCHEC : la tâche 5 n'a pas encore été validée."
  exit 1
fi
if [ "$REF" = "$(docker inspect "$R" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : c'est encore le conteneur de la tâche 5 : il n'a pas été supprimé."
  exit 1
fi
PW=$(cat "$D/secrets/redis_password.txt")
V=$(docker exec "$R" redis-cli -a "$PW" --no-auth-warning get visits)
if [ -z "$V" ] || [ "$V" -lt "${OLD:-0}" ]; then
  echo "ÉCHEC : le compteur vaut ${V:-rien}, alors qu'il valait $OLD. Le volume a-t-il été supprimé ? Si oui, reprenez à la tâche 5."
  exit 1
fi
for S in proxy api cache; do
  if [ "$(docker inspect "$(cid $S)" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)" != "healthy" ]; then
    echo "ÉCHEC : $S n'est pas encore healthy. Attendez quelques secondes et réessayez."
    exit 1
  fi
done
if ! curl -s --max-time 5 http://localhost:28385/api/ | grep -q Visites; then
  echo "ÉCHEC : http://localhost:28385/api/ ne répond pas."
  exit 1
fi
echo "RÉUSSI : de nouveaux conteneurs, et le compteur est intact."
```

````solution
```bash
cd ~/layers-l8/prod && docker compose down && docker compose up -d --wait --wait-timeout 45
```
````

# Tâche 7 : ne rien laisser derrière soi

## Ce qu'il faut faire

Supprimez tout ce que ce challenge a créé : les conteneurs, les réseaux, le volume, l'image construite et le dossier `~/layers-l8/prod`, secret compris.

**Critères :** il ne doit plus rester aucun objet du projet `layers-l8-prod` dans Docker, ni le dossier. Vos autres conteneurs ne sont pas concernés.

```hint
`docker compose down` a une option pour les volumes et une pour les images qu'il a construites. Sortez du dossier avant de l'effacer.
```

```verify
P=layers-l8-prod
if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$P")" ]; then
  echo "ÉCHEC : il reste des conteneurs du projet $P."
  exit 1
fi
if [ -n "$(docker network ls -q --filter "name=$P")" ]; then
  echo "ÉCHEC : il reste un réseau du projet $P : $(docker network ls --format '{{.Name}}' --filter "name=$P" | tr '\n' ' ')"
  echo "  S'il ne figure plus dans votre fichier, Compose ne le supprime plus : docker network rm <son nom>."
  exit 1
fi
if [ -n "$(docker volume ls -q --filter "name=$P")" ]; then
  echo "ÉCHEC : il reste un volume du projet $P. Il faut l'option -v."
  exit 1
fi
if docker image inspect "$P-api" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image construite existe encore. Il faut l'option --rmi local."
  exit 1
fi
if [ -e "$HOME/layers-l8/prod" ]; then
  echo "ÉCHEC : le dossier ~/layers-l8/prod existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Votre stack était prête pour la production."
```

````solution
```bash
cd ~/layers-l8/prod && docker compose down -v --rmi local
cd ~ && rm -rf ~/layers-l8/prod
```
````
