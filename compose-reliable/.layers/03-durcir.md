---
title: "Réduire les dégâts possibles"
description: "Ne pas tourner en root, un système de fichiers en lecture seule, retirer les capabilities"
---

Une application peut avoir une faille. La question devient alors : si quelqu'un en prend le contrôle, que peut-il faire ? Cette étape lui retire le plus de moyens possible. Ce n'est pas magique : chaque réglage retire quelque chose, et certains cassent une application mal préparée. Vous allez voir les pannes, et comment les résoudre.

## Regarder ce que l'application peut faire

Par défaut, un conteneur tourne en administrateur, `root`, et peut écrire partout dans son système de fichiers. Vérifiez sur `web` : `id` dit qui vous êtes, et `touch` crée un fichier vide.

```exec
cd ~/layers-l8/reliable && docker compose exec web sh -c 'id; touch /app/fichier-pirate; ls /app'
```

Vous lisez `uid=0(root)`, et le fichier a bien été créé à côté du code.

## Les réglages

Ce tableau liste les réglages qui réduisent cela, l'exception `tmpfs` et le cas du port :

| Réglage | Où | Ce qu'il retire |
|---|---|---|
| `USER` | `Dockerfile` | les droits de `root` : le programme tourne sous un utilisateur ordinaire |
| `read_only: true` | service | l'écriture sur tout le système de fichiers du conteneur |
| `tmpfs: [/tmp]` | service | rend une exception : un dossier inscriptible, gardé en mémoire et perdu à l'arrêt |
| `cap_drop: [ALL]` | service | les **capabilities**, ces privilèges précis que Linux découpe dans les droits de `root` : changer de propriétaire un fichier, ouvrir un port bas, et ainsi de suite |
| `security_opt: ["no-new-privileges:true"]` | service | la possibilité de gagner des droits en cours de route par un programme spécial, dit *setuid* |
| `127.0.0.1:` devant le port | service | l'accès depuis les autres machines : le port n'écoute que sur la machine elle-même |

`init: true` s'ajoute souvent à la liste, sans rien retirer : Docker place alors un petit programme en PID 1, le numéro du processus principal d'un conteneur, qui transmet les signaux à l'application et fait le ménage parmi les processus terminés.

## D'abord le Dockerfile

Le meilleur endroit pour ne pas être `root`, c'est l'image : l'utilisateur y existe vraiment, et la protection vaut partout où l'image tourne. La clé `user:` de Compose force un utilisateur au démarrage, sans le créer, ce qui dépanne quand vous ne pouvez pas reconstruire l'image. Créez cet utilisateur après avoir copié le code. `adduser -D` le crée sans mot de passe, et `-u` fixe son numéro :

```exec
cat > ~/layers-l8/reliable/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
RUN adduser -D -u 10001 appuser
USER appuser
CMD ["python", "-u", "app.py"]
EOF
```

## Puis le fichier Compose

Appliquez les autres réglages aux deux services. Le fichier commence à être long, mais il ne contient rien d'autre que ce qui a déjà été expliqué :

```exec
cat > ~/layers-l8/reliable/compose.yaml <<'EOF'
name: layers-l8-reliable
services:
  web:
    build: .
    restart: unless-stopped
    init: true
    ports:
      - "127.0.0.1:28382:8000"
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
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: "0.5"
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
    command: ["redis-server", "--appendonly", "yes"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 2s
      retries: 10
    volumes:
      - cache-data:/data
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
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
volumes:
  cache-data:
EOF
```

Reconstruisez et démarrez. `--wait` demande à `up` d'attendre que les services soient `healthy`, et `--wait-timeout` limite cette attente à 20 secondes. Attendez-vous à une erreur :

```exec
cd ~/layers-l8/reliable && docker compose up -d --build --wait --wait-timeout 20
```

## La panne de Redis

Vous lisez un échec, `container layers-l8-reliable-cache-1 is unhealthy` : `cache` n'atteint jamais l'état `healthy`. Regardez ce qu'il en dit, et son état. `grep -m 1` s'arrête à la première ligne trouvée. Pas d'inquiétude, voici le symptôme, la cause et le correctif.

```exec
cd ~/layers-l8/reliable && docker compose logs cache | grep -m 1 'Permission denied'
cd ~/layers-l8/reliable && docker compose ps -a --format '{{.Service}} : {{.Status}}'
```

- **Symptôme** : `cache` redémarre en boucle, son état affiche `Restarting` ou quelques secondes de `Up`, et ses logs disent `Opening the temp file for AOF rewrite in rewriteAppendOnlyFile(): Permission denied`. L'AOF est le journal où Redis note chaque écriture, l'option `--appendonly`.
- **Cause** : au démarrage, l'image de Redis passe normalement de `root` à l'utilisateur `redis`, propriétaire de `/data`. Avec `cap_drop: [ALL]`, elle n'en a plus le droit : le programme reste donc `root`, mais sans la capability qui permet à `root` d'ignorer les droits des fichiers. Il ne peut donc pas écrire dans `/data`.
- **Correctif** : démarrer directement sous l'utilisateur `redis` avec `user: redis`, puisque l'image le prévoit. Il n'y a plus de changement à faire, donc aucune capability à rendre. Il vaut mieux cela que de rendre des droits à `root`, ce que permettrait `cap_add`.

Ajoutez donc `user: redis` au service. Redis y gagne aussi un `tmpfs` sur `/tmp`, pour ses fichiers temporaires. Comme à l'étape précédente, `awk` insère ces lignes après celle de l'image ; vous pouvez le faire dans votre éditeur. L'essai raté a pu laisser le volume dans un état bancal, et il ne contient que des visites de test : `down -v` le supprime avec le reste.

```exec
cd ~/layers-l8/reliable && awk '{print} /^    image: redis/{print "    user: redis"; print "    tmpfs:"; print "      - /tmp"}' compose.yaml > compose.new && mv compose.new compose.yaml
cd ~/layers-l8/reliable && docker compose down -v
cd ~/layers-l8/reliable && docker compose up -d --wait --wait-timeout 30
```

Cette fois, `up` se termine sans erreur : les deux services sont `healthy`. Vérifiez que l'application fonctionne et rejouez les deux essais du début :

```exec
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28382
cd ~/layers-l8/reliable && docker compose exec web sh -c 'id; touch /app/fichier-pirate'
```

Vous lisez `uid=10001(appuser)`, puis `Read-only file system`. Le fichier ne peut plus être déposé, et l'application tourne quand même.

```verify
W=layers-l8-reliable-web-1; R=layers-l8-reliable-cache-1
for C in $W $R; do
  if [ "$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)" != "healthy" ]; then
    echo "$C n'est pas healthy. Lisez ses logs avec docker compose logs. Pour Redis, il faut user: redis."
    exit 1
  fi
  if [ "$(docker inspect $C --format '{{.HostConfig.ReadonlyRootfs}}')" != "true" ]; then
    echo "$C n'a pas read_only: true."
    exit 1
  fi
  if [ "$(docker inspect $C --format '{{.HostConfig.CapDrop}}')" != "[ALL]" ]; then
    echo "$C n'a pas cap_drop: [ALL]."
    exit 1
  fi
  case "$(docker inspect $C --format '{{.HostConfig.SecurityOpt}}')" in
    *no-new-privileges*) : ;;
    *) echo "$C n'a pas no-new-privileges."; exit 1 ;;
  esac
done
if [ "$(docker exec $W id -u)" = "0" ]; then
  echo "web tourne encore en root. Vérifiez USER dans le Dockerfile, puis reconstruisez avec --build."
  exit 1
fi
if [ "$(docker exec $R id -u)" = "0" ]; then
  echo "cache tourne en root. Il lui faut user: redis."
  exit 1
fi
case "$(docker port $W 8000/tcp)" in
  127.0.0.1:28382*) : ;;
  *) echo "Le port de web n'écoute pas que sur 127.0.0.1 : écrivez 127.0.0.1:28382:8000."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://localhost:28382 | grep -q Visites; then
  echo "L'application ne répond plus. Lisez : docker compose logs web"
  exit 1
fi
echo "Les deux services tournent sans root, en lecture seule, sans capabilities, et l'application répond."
```

> 📖 [`read_only`](https://docs.docker.com/reference/compose-file/services/#read_only) · [`cap_drop` et `cap_add`](https://docs.docker.com/reference/compose-file/services/#cap_add) · [`security_opt`](https://docs.docker.com/reference/compose-file/services/#security_opt) · [`user`](https://docs.docker.com/reference/compose-file/services/#user) · [`USER`](https://docs.docker.com/reference/dockerfile/#user) · [`init`](https://docs.docker.com/reference/compose-file/services/#init)

## Questions

```quiz
title: "Réduire les dégâts possibles"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi préférer `USER` dans le Dockerfile à `user:` dans Compose ?"
    answers:
      - "`user:` n'existe pas dans Compose"
      - "L'utilisateur existe alors vraiment dans l'image, et la protection vaut partout où l'image tourne"
      - "`USER` rend l'image plus petite"
    correct: 2
    explanation: "`user:` reste utile pour une image que vous ne pouvez pas reconstruire, comme ici avec Redis, dont l'image prévoit déjà un utilisateur."
  - prompt: "Avec `read_only: true`, votre application ne peut plus écrire dans `/tmp`. Que faire ?"
    answers:
      - "Retirer `read_only`"
      - "Déclarer `/tmp` en `tmpfs`, un dossier inscriptible gardé en mémoire"
      - "Lancer le conteneur en root"
    correct: 2
    explanation: "Le reste du système de fichiers reste protégé, et ce qui va dans `tmpfs` disparaît à l'arrêt."
  - prompt: "Après `cap_drop: [ALL]`, Redis ne peut plus écrire dans `/data`, en affichant `Permission denied`. Quel est le meilleur correctif ?"
    answers:
      - "`cap_add: [ALL]`"
      - "`user: redis`, pour démarrer directement sous l'utilisateur propriétaire des données"
      - "Passer le volume en lecture seule"
    correct: 2
    explanation: "Tourner sous le bon utilisateur évite d'avoir à rendre des droits à `root`."
```
