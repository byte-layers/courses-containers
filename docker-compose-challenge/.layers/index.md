---
title: "Une application multi-services, sans guide"
description: "Écrire seul le fichier Compose d'une application de trois services : publication, configuration, persistance et réseaux séparés."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 60
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce challenge prouve que vous savez décrire une application avec Compose. Le code est fourni, mais **aucun fichier Compose ne l'est** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker. Toute écriture qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseignent le cours « Décrire une application avec Compose » et le lab « getting-started-app en Compose ».
- **Ce qu'il faut avoir** : Docker et Compose qui répondent, `curl`, un éditeur de texte et le port 28372 libre.
- **Votre dossier de travail** : `~/layers-l7/notes` est préparé pour vous à l'ouverture de la tâche 1. La vérification y garde aussi un fichier caché, `.cache-id`, qui lui sert à reconnaître votre conteneur.
- **Les noms comptent** : le projet s'appelle exactement `layers-l7-notes`, et ses services `front`, `api` et `cache`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche enrichit le fichier de la précédente. Faites-les dans l'ordre.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.

## L'application

Elle compte des visites, et ses trois parties se suivent ainsi :

```
votre machine ──► front (nginx, port 80) ──► api (Python, port 8080) ──► cache (Redis, port 6379)
```

Le dossier `~/layers-l7/notes` reçoit ce qu'il vous faut à l'ouverture de la tâche 1 :

| Fichier | Ce qu'il contient |
|---|---|
| `api/app.py` | le serveur Python, qui écoute sur le port 8080 et lit deux variables d'environnement : `REDIS_HOST`, l'adresse de Redis, et `GREETING`, le message d'accueil |
| `api/Dockerfile` | de quoi construire son image |
| `front/nginx.conf` | une configuration de nginx qui transmet tout au service nommé `api`, sur le port 8080 ; elle doit prendre la place du fichier `/etc/nginx/conf.d/default.conf` de l'image `nginx:1.30-alpine` |

Lisez ces fichiers à ce moment-là : ils disent ce qu'attend chaque service.

# Tâche 1 : trois services, une seule porte

```setup
mkdir -p ~/layers-l7/notes/api ~/layers-l7/notes/front
cat > ~/layers-l7/notes/api/app.py <<'EOF'
import os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
GREETING = os.environ.get("GREETING", "Bonjour")

def count_visit():
    with socket.create_connection((REDIS_HOST, 6379), timeout=2) as redis:
        redis.sendall(b"INCR notes\r\n")
        return int(redis.recv(64).strip().lstrip(b":"))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"{GREETING} : {count_visit()} visites\n".encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("", 8080), Handler).serve_forever()
EOF
cat > ~/layers-l7/notes/api/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF
cat > ~/layers-l7/notes/front/nginx.conf <<'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://api:8080;
    }
}
EOF
```

Écrivez `~/layers-l7/notes/compose.yaml` et démarrez l'application.

**Critères :**

- le projet s'appelle `layers-l7-notes`, et ses services `front`, `api` et `cache` tournent ;
- `api` est construit depuis `api/Dockerfile`, `cache` utilise `redis:8-alpine`, `front` utilise `nginx:1.30-alpine` avec le fichier `front/nginx.conf` ;
- `front` est le **seul** service à publier un port : le port **28372** de la machine mène à son port **80** ;
- `front` démarre après `api`, et `api` après `cache` ;
- `curl http://localhost:28372` répond avec un compteur de visites qui monte.

```hint
Un fichier se monte comme un dossier, dans la clé `volumes` du service : `./front/nginx.conf:/etc/nginx/conf.d/default.conf`. Le suffixe `:ro` le rend lisible seulement, ce qui suffit à nginx.
```

```hint
L'application a besoin de `REDIS_HOST`. Le nom du service `cache` sert d'adresse sur le réseau du projet.
```

```hint
Si `front` s'arrête aussitôt avec `host not found in upstream "api"`, c'est qu'il a démarré sans que `api` existe : c'est le rôle de `depends_on`.
```

```verify
P=layers-l7-notes
cid() { docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=$1" | head -1; }
for S in front api cache; do
  if [ -z "$(cid $S)" ]; then
    echo "ÉCHEC : aucun service $S ne tourne dans le projet $P."
    echo "  Écrivez ~/layers-l7/notes/compose.yaml et lancez docker compose up -d --build depuis ce dossier."
    echo "  Si un service s'arrête aussitôt : docker compose logs $S"
    exit 1
  fi
done
F=$(cid front); A=$(cid api); R=$(cid cache)
case "$(docker inspect "$F" --format '{{.Config.Image}}')" in nginx:1.30-alpine*) : ;; *) echo "ÉCHEC : front doit utiliser nginx:1.30-alpine."; exit 1 ;; esac
case "$(docker inspect "$R" --format '{{.Config.Image}}')" in redis:8-alpine*) : ;; *) echo "ÉCHEC : cache doit utiliser redis:8-alpine."; exit 1 ;; esac
case "$(docker inspect "$A" --format '{{.Config.Image}}')" in python:*) echo "ÉCHEC : api doit être construit depuis api/Dockerfile, pas lancé depuis une image toute prête."; exit 1 ;; esac
MAP=$(docker port "$F" 80/tcp 2>/dev/null)
case "$MAP" in
  *:28372*) : ;;
  *) echo "ÉCHEC : le port 28372 de la machine ne mène pas au port 80 de front (trouvé : ${MAP:-aucun})."; exit 1 ;;
esac
for C in "$A" "$R"; do
  if [ -n "$(docker port "$C")" ]; then
    echo "ÉCHEC : $(docker inspect "$C" --format '{{index .Config.Labels "com.docker.compose.service"}}') publie un port. front doit être la seule porte d'entrée."
    exit 1
  fi
done
case "$(docker inspect "$F" --format '{{index .Config.Labels "com.docker.compose.depends_on"}}')" in *api*) : ;; *) echo "ÉCHEC : front ne dépend pas de api."; exit 1 ;; esac
case "$(docker inspect "$A" --format '{{index .Config.Labels "com.docker.compose.depends_on"}}')" in *cache*) : ;; *) echo "ÉCHEC : api ne dépend pas de cache."; exit 1 ;; esac
N1=$(curl -s --max-time 5 http://localhost:28372 | sed -n 's/.* : \([0-9]*\) visites/\1/p')
N2=$(curl -s --max-time 5 http://localhost:28372 | sed -n 's/.* : \([0-9]*\) visites/\1/p')
if [ -z "$N1" ] || [ -z "$N2" ] || [ "$N2" -le "$N1" ]; then
  echo "ÉCHEC : http://localhost:28372 ne répond pas avec un compteur qui monte (lu : ${N1:-rien}, puis ${N2:-rien})."
  echo "  Lisez : docker compose logs api"
  exit 1
fi
echo "RÉUSSI : front est la seule porte, et le compteur monte."
```

````solution
```bash
cat > ~/layers-l7/notes/compose.yaml <<'EOF'
name: layers-l7-notes
services:
  front:
    image: nginx:1.30-alpine
    ports:
      - "28372:80"
    volumes:
      - ./front/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
    depends_on:
      - cache
  cache:
    image: redis:8-alpine
EOF
cd ~/layers-l7/notes && docker compose up -d --build
sleep 2
```
````

# Tâche 2 : un message réglable

Le message d'accueil doit pouvoir changer sans toucher à `compose.yaml`.

**Critères :**

- un fichier `~/layers-l7/notes/.env` définit `GREETING` ;
- `api` reçoit cette valeur ;
- le message n'est pas écrit en dur : si `GREETING` a une autre valeur au moment de lire le fichier, `docker compose config` montre cette autre valeur ;
- si aucune valeur n'est donnée, le message vaut `Bonjour`, et non une chaîne vide.

```hint
Une variable se remplace dans le fichier avec `${NOM}`, et une valeur de repli s'écrit `${NOM:-repli}`.
```

```hint
Après avoir créé le fichier `.env`, il faut relancer `docker compose up -d` : le conteneur ne reçoit la valeur qu'à sa création.
```

```verify
P=layers-l7-notes; D=~/layers-l7/notes
A=$(docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=api" | head -1)
if [ -z "$A" ]; then
  echo "ÉCHEC : le service api ne tourne pas. Faites d'abord la tâche 1."
  exit 1
fi
if ! grep -q '^GREETING=.' "$D/.env" 2>/dev/null; then
  echo "ÉCHEC : $D/.env ne définit pas GREETING."
  exit 1
fi
V=$(sed -n 's/^GREETING=//p' "$D/.env" | head -1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
if ! docker inspect "$A" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -qxF "GREETING=$V"; then
  echo "ÉCHEC : api n'a pas GREETING=$V. Transmettez la valeur dans son bloc environment, puis relancez docker compose up -d."
  exit 1
fi
if ! (cd "$D" && GREETING=ValeurDeControle docker compose config 2>/dev/null) | grep -q 'GREETING.*ValeurDeControle'; then
  echo "ÉCHEC : GREETING est écrit en dur dans compose.yaml. Utilisez une variable, avec \${...}."
  exit 1
fi
if ! (cd "$D" && mv .env .env.check && GREETING= docker compose config 2>/dev/null; mv .env.check .env) | grep -q 'GREETING.*Bonjour'; then
  echo "ÉCHEC : sans valeur, le message doit valoir Bonjour. Ajoutez une valeur de repli à votre variable."
  exit 1
fi
echo "RÉUSSI : le message vient du fichier .env, avec Bonjour en repli."
```

````solution
```bash
cd ~/layers-l7/notes && printf 'GREETING=Salut\n' > .env
cat > ~/layers-l7/notes/compose.yaml <<'EOF'
name: layers-l7-notes
services:
  front:
    image: nginx:1.30-alpine
    ports:
      - "28372:80"
    volumes:
      - ./front/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
      GREETING: ${GREETING:-Bonjour}
    depends_on:
      - cache
  cache:
    image: redis:8-alpine
EOF
cd ~/layers-l7/notes && docker compose up -d
```
````

# Tâche 3 : un compteur qui dure

Le compteur doit survivre à la suppression des conteneurs.

**Critères :**

- `cache` garde ses données dans un **volume nommé** du projet, monté sur `/data` ;
- Redis écrit ses données sur le disque : sa commande est `redis-server --appendonly yes` ;
- le compteur a déjà été incrémenté depuis l'arrivée de ce volume.

Quand cette vérification passe, supprimez les conteneurs et recréez-les : c'est la tâche 4.

```hint
Un volume nommé se déclare en bas du fichier et se monte dans le service. La clé `command` remplace la commande de l'image.
```

```hint
Le conteneur `cache` doit être recréé pour recevoir le volume : `docker compose up -d` s'en charge. Demandez ensuite la page une fois ou deux.
```

```verify
P=layers-l7-notes; D=~/layers-l7/notes
R=$(docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=cache" | head -1)
if [ -z "$R" ]; then
  echo "ÉCHEC : le service cache ne tourne pas."
  exit 1
fi
SRC=$(docker inspect "$R" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}')
case "$SRC" in
  volume:layers-l7-notes_*) : ;;
  *) echo "ÉCHEC : cache n'a pas de volume nommé du projet sur /data (trouvé : ${SRC:-rien})."
     echo "  Un volume nommé se déclare en bas du fichier : un bind mount vers un dossier ne compte pas ici."
     exit 1 ;;
esac
if ! docker exec "$R" redis-cli config get appendonly | grep -q yes; then
  echo "ÉCHEC : Redis n'a pas l'option appendonly. Remplacez la commande du service cache."
  exit 1
fi
V=$(docker exec "$R" redis-cli get notes)
if [ -z "$V" ]; then
  echo "ÉCHEC : le compteur est vide dans ce volume : demandez la page http://localhost:28372, puis réessayez."
  exit 1
fi
docker inspect "$R" --format '{{.Id}}' > "$D/.cache-id"
echo "$V" >> "$D/.cache-id"
echo "RÉUSSI : le compteur vaut $V, dans le volume ${SRC#volume:}. Passez à la tâche 4."
```

````solution
```bash
cat > ~/layers-l7/notes/compose.yaml <<'EOF'
name: layers-l7-notes
services:
  front:
    image: nginx:1.30-alpine
    ports:
      - "28372:80"
    volumes:
      - ./front/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
      GREETING: ${GREETING:-Bonjour}
    depends_on:
      - cache
  cache:
    image: redis:8-alpine
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - cache-data:/data
volumes:
  cache-data:
EOF
cd ~/layers-l7/notes && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28372
sleep 1
```
````

# Tâche 4 : le prouver

Supprimez tous les conteneurs du projet et recréez-les, sans perdre le compteur.

**Critères :**

- le conteneur `cache` n'est plus celui de la tâche 3 ;
- le compteur vaut au moins sa valeur de la tâche 3.

```hint
Une seule commande supprime tous les conteneurs du projet, et une seule les recrée. La première a une option qui emporte aussi les volumes : c'est celle à éviter ici.
```

```verify
P=layers-l7-notes; D=~/layers-l7/notes
R=$(docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=cache" | head -1)
if [ -z "$R" ]; then
  echo "ÉCHEC : le service cache ne tourne pas. Après la suppression, il reste à recréer les conteneurs."
  exit 1
fi
REF=$(sed -n 1p "$D/.cache-id" 2>/dev/null); OLD=$(sed -n 2p "$D/.cache-id" 2>/dev/null)
if [ -z "$REF" ]; then
  echo "ÉCHEC : la tâche 3 n'a pas encore été validée."
  exit 1
fi
if [ "$REF" = "$(docker inspect "$R" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : c'est encore le conteneur de la tâche 3 : il n'a pas été supprimé."
  exit 1
fi
V=$(docker exec "$R" redis-cli get notes)
if [ -z "$V" ] || [ "$V" -lt "$OLD" ]; then
  echo "ÉCHEC : le compteur vaut ${V:-rien}, alors qu'il valait $OLD. Le volume a-t-il été supprimé avec les conteneurs ?"
  echo "  Si oui, refaites la tâche 3."
  exit 1
fi
echo "RÉUSSI : un nouveau conteneur, et le compteur vaut $V."
```

````solution
```bash
cd ~/layers-l7/notes && docker compose down && docker compose up -d
```
````

# Tâche 5 : séparer les réseaux

`front` n'a aucune raison de joindre Redis : il ne parle qu'à `api`. Séparez les réseaux pour que cela devienne impossible.

**Critères :**

- le fichier déclare deux réseaux à vous ;
- depuis `front`, le nom `api` est joignable, et le nom `cache` ne l'est pas ;
- l'application répond toujours, avec le compteur conservé.

```hint
`api` doit être sur les deux réseaux, puisqu'il parle à `front` et à `cache`. Les deux autres n'en ont besoin que d'un.
```

```hint
Vous pouvez tester à la main avec `docker compose exec front ping -c 1 -W 1 cache`.
```

```hint
Faites `docker compose down` avant de réécrire le fichier : une fois que le réseau par défaut n'y figure plus, Compose ne le supprime plus. S'il reste, `docker network rm layers-l7-notes_default` le retire.
```

```verify
P=layers-l7-notes
F=$(docker ps -q --filter "label=com.docker.compose.project=$P" --filter "label=com.docker.compose.service=front" | head -1)
if [ -z "$F" ]; then
  echo "ÉCHEC : le service front ne tourne pas. Lisez : docker compose logs front"
  exit 1
fi
if [ -n "$(docker inspect "$F" --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}' | grep "${P}_default")" ]; then
  echo "ÉCHEC : front est encore sur le réseau par défaut du projet. Déclarez vos réseaux et placez-y chaque service."
  exit 1
fi
if docker exec "$F" ping -c 1 -W 1 cache >/dev/null 2>&1; then
  echo "ÉCHEC : front joint encore cache. Ces deux services ne doivent partager aucun réseau."
  exit 1
fi
if ! docker exec "$F" ping -c 1 -W 1 api >/dev/null 2>&1; then
  echo "ÉCHEC : front ne joint plus api. Ils doivent partager un réseau."
  exit 1
fi
OUT=$(curl -s --max-time 5 http://localhost:28372)
case "$OUT" in
  *visites*) : ;;
  *) echo "ÉCHEC : l'application ne répond plus sur le port 28372 : api doit aussi rester relié à cache."; exit 1 ;;
esac
OLD=$(sed -n 2p ~/layers-l7/notes/.cache-id 2>/dev/null)
N=$(echo "$OUT" | sed -n 's/.* : \([0-9]*\) visites/\1/p')
if [ -z "$N" ] || [ "$N" -lt "${OLD:-0}" ]; then
  echo "ÉCHEC : le compteur vaut ${N:-rien}, alors qu'il valait au moins $OLD. Le volume a-t-il été supprimé ? Si oui, faites monter le compteur et reprenez à la tâche 3."
  exit 1
fi
echo "RÉUSSI : front joint api mais pas cache, et l'application répond : $OUT"
```

````solution
Le fichier final du challenge se trouve aussi dans le dossier `solution/` de ce contenu.

```bash
cd ~/layers-l7/notes && docker compose down
cat > ~/layers-l7/notes/compose.yaml <<'EOF'
name: layers-l7-notes
services:
  front:
    image: nginx:1.30-alpine
    ports:
      - "28372:80"
    volumes:
      - ./front/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
    networks:
      - edge
  api:
    build: ./api
    environment:
      REDIS_HOST: cache
      GREETING: ${GREETING:-Bonjour}
    depends_on:
      - cache
    networks:
      - edge
      - back
  cache:
    image: redis:8-alpine
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - cache-data:/data
    networks:
      - back
volumes:
  cache-data:
networks:
  edge:
  back:
EOF
cd ~/layers-l7/notes && docker compose up -d
sleep 2
```
````

# Tâche 6 : ne rien laisser derrière soi

Supprimez tout ce que ce challenge a créé : les conteneurs, les réseaux, le volume, l'image construite et le dossier `~/layers-l7/notes`.

**Critères :** il ne doit plus rester aucun objet du projet `layers-l7-notes` dans Docker, ni le dossier. Vos autres conteneurs ne sont pas concernés.

```hint
`docker compose down` a une option pour les volumes et une pour les images qu'il a construites. Sortez du dossier avant de l'effacer.
```

```verify
P=layers-l7-notes
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
if [ -n "$(docker images -q --filter "label=com.docker.compose.project=$P")" ] || docker image inspect "$P-api" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image construite existe encore. Il faut l'option --rmi local."
  exit 1
fi
if [ -e "$HOME/layers-l7/notes" ]; then
  echo "ÉCHEC : le dossier ~/layers-l7/notes existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez décrire une application avec Compose."
```

````solution
```bash
cd ~/layers-l7/notes && docker compose down -v --rmi local
cd ~ && rm -rf ~/layers-l7/notes
```
````
