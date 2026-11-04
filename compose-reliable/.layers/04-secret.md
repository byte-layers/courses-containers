---
title: "Donner un secret à un service"
description: "Les secrets de Compose, le $$, et un contrôle de santé qui dit la vérité"
---

Redis accepte aujourd'hui toutes les connexions. Protégez-le par un mot de passe. Comme le montre « Un secret ne va pas dans l'image », un mot de passe ne va ni dans l'image ni, de préférence, dans une variable d'environnement : `docker inspect` la montrerait à quiconque peut interroger Docker.

## Le fichier du secret

La clé `secrets` de Compose prend la valeur dans un fichier de votre machine, et la place dans le conteneur, sous `/run/secrets/<nom>`. Préparez ce fichier. Le dossier est réservé à votre utilisateur avec `chmod 700`, et il n'entre jamais dans Git, ce que dit le fichier `.gitignore`. Le fichier `.dockerignore` le garde aussi hors des images construites :

```exec
mkdir -p ~/layers-l8/reliable/secrets
chmod 700 ~/layers-l8/reliable/secrets
printf 'mot-de-passe-de-demo' > ~/layers-l8/reliable/secrets/redis_password.txt
printf 'secrets/\n' > ~/layers-l8/reliable/.gitignore
printf 'secrets/\n' > ~/layers-l8/reliable/.dockerignore
```

Dans un vrai projet, vous fourniriez un fichier d'exemple, et chacun créerait le sien : la valeur ci-dessus, écrite dans ce cours, ne doit pas servir ailleurs.

## Le déclarer

Il faut deux choses, comme pour un volume : une section `secrets:` en bas du fichier, qui dit d'où vient le secret, et une clé `secrets:` dans chaque service qui en a besoin. `web` a besoin du mot de passe pour parler à Redis, et son code sait le lire dans le fichier désigné par la variable `REDIS_PASSWORD_FILE`. Celle-ci contient un chemin, pas un secret : elle peut sans risque rester visible.

Redis, lui, n'a pas d'option qui lise un mot de passe dans un fichier. Il faut un petit shell : il lit le fichier, puis lance Redis avec `--requirepass`. Dans un fichier Compose, `$` sert à remplacer les variables. Pour qu'un vrai `$` arrive au shell du conteneur, on l'écrit donc `$$`.

Voici le fichier complet, avec ces ajouts. Le contrôle de santé de `cache` change lui aussi : la section suivante dit pourquoi.

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
      REDIS_PASSWORD_FILE: /run/secrets/redis_password
    secrets:
      - redis_password
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
    user: redis
    tmpfs:
      - /tmp
    restart: unless-stopped
    secrets:
      - redis_password
    command: ["sh", "-c", "exec redis-server --appendonly yes --requirepass \"$$(cat /run/secrets/redis_password)\""]
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$(cat /run/secrets/redis_password)\" --no-auth-warning ping | grep -q PONG"]
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
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
cd ~/layers-l8/reliable && docker compose up -d --wait --wait-timeout 30
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28382
```

L'application répond : `web` a lu le fichier et s'est authentifié. Sans ce secret côté client, chaque requête échouerait. Protéger le serveur ne suffit jamais : il faut aussi donner la clé à ceux qui ont le droit d'entrer.

## Un contrôle de santé qui dit la vérité

Pourquoi avoir changé le contrôle de `cache` ? Essayez l'ancien, qui lance `redis-cli ping` sans mot de passe, et affichez son code de sortie :

```exec
cd ~/layers-l8/reliable && docker compose exec cache redis-cli ping; echo "code de sortie : $?"
```

Vous lisez `NOAUTH Authentication required`, et **`code de sortie : 0`**. Redis a répondu un refus, et `redis-cli` considère que l'échange s'est bien passé. Docker ne regarde que ce code : le service aurait donc été déclaré `healthy` quoi qu'il arrive au mot de passe. Un contrôle de santé doit vérifier la réponse attendue. Le nouveau y parvient de cette façon :

| Élément | Rôle |
|---|---|
| `CMD-SHELL` | lance la commande dans un shell, ce qui permet `$(...)` et le `\|` |
| `-a "$$(cat ...)"` | lit le mot de passe dans le fichier, au moment du contrôle |
| `--no-auth-warning` | retire l'avertissement que `redis-cli` affiche à l'usage de `-a` |
| `\| grep -q PONG` | ne sort avec le code 0 que si la réponse contient bien `PONG` |

Lancez la même chose à la main. Le premier appel doit répondre `PONG`, et le second, avec un faux mot de passe, doit échouer :

```exec
cd ~/layers-l8/reliable && docker compose exec cache sh -c 'redis-cli -a "$(cat /run/secrets/redis_password)" --no-auth-warning ping | grep PONG; echo "code : $?"; redis-cli -a faux --no-auth-warning ping | grep PONG; echo "code : $?"'
```

```verify
R=layers-l8-reliable-cache-1; W=layers-l8-reliable-web-1
if [ "$(docker inspect $R --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)" != "healthy" ]; then
  echo "cache n'est pas healthy. Lisez : docker compose logs cache"
  exit 1
fi
if ! docker exec $R redis-cli ping 2>/dev/null | grep -q NOAUTH; then
  echo "Redis répond sans mot de passe : le --requirepass n'est pas appliqué."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28382 | grep -q 'Visites : [0-9]'; then
  echo "L'application ne compte plus. Vérifiez que web a bien le secret et la variable REDIS_PASSWORD_FILE."
  exit 1
fi
case "$(docker inspect $R --format '{{json .Config.Healthcheck.Test}}')" in
  *grep*PONG*) : ;;
  *) echo "Le contrôle de santé de cache ne vérifie pas la réponse PONG."; exit 1 ;;
esac
echo "Redis exige son mot de passe, web le connaît, et le contrôle de santé vérifie la vraie réponse."
```

## Où se voit le secret ?

Vérifiez ce que vous avez gagné. Cherchez le mot de passe là où il ne doit plus être : dans l'environnement et la configuration des deux conteneurs, puis dans les couches de l'image. `grep -c` compte les lignes trouvées, et `0` est la réponse attendue :

```exec
docker inspect layers-l8-reliable-web-1 layers-l8-reliable-cache-1 | grep -c 'mot-de-passe-de-demo'
docker history --no-trunc layers-l8-reliable-web | grep -c 'mot-de-passe-de-demo'
```

Dans le conteneur, en revanche, le fichier est lisible, comme prévu :

```exec
cd ~/layers-l8/reliable && docker compose exec web cat /run/secrets/redis_password
```

Une limite à connaître : Redis reçoit ici le mot de passe sur sa ligne de commande. Il la masque dès son démarrage, et `cat /proc/1/cmdline` dans le conteneur ne montre plus que `redis-server *:6379`, mais un autre processus du conteneur pourrait la lire pendant ce court instant. Une application qui lit directement le fichier, comme `web`, n'a pas ce défaut, et il vaut mieux la privilégier. Le cas d'une équipe, où le fichier doit être partagé et chiffré, relève d'outils comme HashiCorp Vault, hors du champ de ce cours.

```verify
N=$(docker inspect layers-l8-reliable-web-1 layers-l8-reliable-cache-1 2>/dev/null | grep -c 'mot-de-passe-de-demo')
if [ "$N" != "0" ]; then
  echo "Le mot de passe apparaît dans docker inspect : il est passé par une variable d'environnement ou par une commande. Utilisez le fichier du secret."
  exit 1
fi
if ! docker image inspect layers-l8-reliable-web >/dev/null 2>&1; then
  echo "L'image layers-l8-reliable-web n'existe pas. Relancez docker compose up -d --build."
  exit 1
fi
if docker history --no-trunc layers-l8-reliable-web 2>/dev/null | grep -q 'mot-de-passe-de-demo'; then
  echo "Le mot de passe apparaît dans l'historique de l'image."
  exit 1
fi
if ! docker exec layers-l8-reliable-web-1 cat /run/secrets/redis_password 2>/dev/null | grep -q .; then
  echo "web ne voit pas le fichier /run/secrets/redis_password."
  exit 1
fi
echo "Le secret est absent de la configuration et de l'image, et présent en fichier dans le conteneur."
```

> 📖 [Les secrets dans Compose](https://docs.docker.com/compose/how-tos/use-secrets/) · [`secrets` dans le fichier Compose](https://docs.docker.com/reference/compose-file/secrets/) · [L'interpolation et `$$`](https://docs.docker.com/reference/compose-file/interpolation/)

## Questions

```quiz
title: "Donner un secret à un service"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Où un service lit-il un secret déclaré avec la clé `secrets` de Compose ?"
    answers:
      - "Dans une variable d'environnement du même nom"
      - "Dans un fichier, sous `/run/secrets/<nom>`"
      - "Dans une couche de son image"
    correct: 2
    explanation: "L'application lit ce fichier. D'où les variables en `_FILE`, qui contiennent le chemin et non la valeur."
  - prompt: "Dans un fichier Compose, pourquoi écrire `$$(cat fichier)` ?"
    answers:
      - "Pour exécuter la commande deux fois"
      - "Parce que `$` sert à Compose pour remplacer ses variables : `$$` fait arriver un vrai `$` au shell du conteneur"
      - "Parce que Redis l'exige"
    correct: 2
    explanation: "Sans ce doublement, Compose tenterait de lire la ligne à sa façon, et le shell ne recevrait jamais la commande."
  - prompt: "`redis-cli ping` affiche `NOAUTH Authentication required`. Avec quel code sort-il, et qu'en conclut un healthcheck écrit ainsi ?"
    answers:
      - "1 : le service est déclaré en échec"
      - "0 : le service est déclaré en bonne santé, sans que rien n'ait été vérifié"
      - "137 : le conteneur est tué"
    correct: 2
    explanation: "D'où le `grep -q PONG`, qui vérifie la réponse attendue. Vérifiez le code de sortie d'un contrôle avant de lui faire confiance."
```
