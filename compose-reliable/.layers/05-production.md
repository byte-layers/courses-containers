---
title: "Un fichier pour la production"
description: "Séparer les réglages de production dans un second fichier, et tout nettoyer"
---

Tout est maintenant dans un seul fichier, et il est difficile à vivre pour travailler : le système de fichiers en lecture seule, les limites et les redémarrages gênent sur un poste de développement. Compose sait **empiler** des fichiers. Un fichier de base décrit l'application, et un second n'ajoute que ce qui change en production.

## Séparer

Voici le fichier de base : il garde ce qui vaut partout, c'est-à-dire ce que l'application **est**.

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
  cache:
    image: redis:8-alpine
    user: redis
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
volumes:
  cache-data:
secrets:
  redis_password:
    file: ./secrets/redis_password.txt
EOF
```

Le second fichier ne contient que les différences. Il s'appelle ici `compose.prod.yaml` ; ce nom n'a rien d'obligatoire. Sur le port, une précaution s'impose. Quand deux fichiers définissent une même **liste**, Compose additionne les éléments au lieu de remplacer, et le port de développement resterait ouvert. L'étiquette `!override` demande de remplacer :

```exec
cat > ~/layers-l8/reliable/compose.prod.yaml <<'EOF'
services:
  web:
    restart: unless-stopped
    init: true
    ports: !override
      - "127.0.0.1:28383:8000"
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
    restart: unless-stopped
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
EOF
```

## Lire le résultat

`-f` choisit les fichiers à lire, et le dernier complète le précédent. Avant de lancer quoi que ce soit, comparez ce que Compose comprend dans les deux cas. `grep -c` compte les lignes, et `grep -A` affiche aussi celle qui suit :

```exec
cd ~/layers-l8/reliable && docker compose config | grep -c read_only
cd ~/layers-l8/reliable && docker compose -f compose.yaml -f compose.prod.yaml config | grep -c read_only
cd ~/layers-l8/reliable && docker compose -f compose.yaml -f compose.prod.yaml config | grep -A1 'published'
```

Le fichier de base seul donne `0`, et les deux ensemble donnent `2`. Le seul port publié est `28383`.

## Lancer en mode production

Appliquez les deux fichiers. Compose remplace les conteneurs dont la configuration change :

```exec
cd ~/layers-l8/reliable && docker compose -f compose.yaml -f compose.prod.yaml up -d --build --wait --wait-timeout 30
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28383
```

Le compteur reprend là où il en était : le volume n'a pas bougé. L'ancien port ne répond plus :

```exec
curl -s --max-time 2 -o /dev/null -w 'code HTTP sur 28382 : %{http_code}\n' http://localhost:28382
```

Vous lisez `code HTTP sur 28382 : 000`. Comme ces `-f` sont longs à retaper, vous pouvez les placer dans la variable `COMPOSE_FILE`, par exemple dans le fichier `.env` du serveur, avec `COMPOSE_FILE=compose.yaml:compose.prod.yaml`. Compose les lira alors tout seul.

```verify
W=layers-l8-reliable-web-1
case "$(docker port $W 8000/tcp 2>/dev/null)" in
  127.0.0.1:28383*) : ;;
  *) echo "web n'écoute pas sur 127.0.0.1:28383. Lancez la commande avec les deux -f."; exit 1 ;;
esac
if [ "$(docker port $W 8000/tcp | wc -l | tr -d ' ')" != "1" ]; then
  echo "web publie plusieurs ports : vérifiez le !override dans compose.prod.yaml."
  exit 1
fi
if [ "$(docker inspect $W --format '{{.HostConfig.ReadonlyRootfs}}')" != "true" ]; then
  echo "web n'est pas en lecture seule : compose.prod.yaml n'a pas été appliqué."
  exit 1
fi
if [ "$(docker inspect $W --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')" != "healthy" ]; then
  echo "web n'est pas healthy. Attendez un peu, ou lisez ses logs."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28383 | grep -q Visites; then
  echo "L'application ne répond pas sur le port 28383."
  exit 1
fi
echo "La production tourne avec les deux fichiers, sur un seul port, en lecture seule."
```

## Tout supprimer

Il reste à ranger. `-v` supprime le volume, `--rmi local` l'image construite, et `rm -rf` le dossier et ses fichiers, secret compris :

```exec
cd ~/layers-l8/reliable && docker compose -f compose.yaml -f compose.prod.yaml down -v --rmi local
cd ~ && rm -rf ~/layers-l8/reliable
```

```verify
if [ -n "$(docker ps -a --filter name=layers-l8-reliable --format '{{.Names}}')" ]; then
  echo "Il reste des conteneurs du projet. Lancez le docker compose down ci-dessus."
  exit 1
fi
if [ -n "$(docker volume ls --filter name=layers-l8-reliable --format '{{.Name}}')" ]; then
  echo "Il reste un volume du projet : il manque -v."
  exit 1
fi
if [ -n "$(docker network ls --filter name=layers-l8-reliable --format '{{.Name}}')" ]; then
  echo "Il reste un réseau du projet : docker network rm layers-l8-reliable_default."
  exit 1
fi
if [ -e "$HOME/layers-l8/reliable" ]; then
  echo "Le dossier ~/layers-l8/reliable existe encore."
  exit 1
fi
echo "C'est propre."
```

## Récap

- Un `healthcheck` dit si le service répond vraiment, et `condition: service_healthy` fait attendre ceux qui en dépendent. Vérifiez la réponse attendue, pas seulement que la commande a tourné.
- `unhealthy` signale sans rien relancer. `restart` réagit à la fin du processus.
- Les limites protègent la machine : la mémoire tue, le processeur ralentit, `pids` bloque la multiplication. Les logs se plafonnent.
- `USER`, `read_only`, `cap_drop` et `no-new-privileges` réduisent les dégâts possibles, et chaque réglage se teste.
- Un secret arrive comme un fichier, dans `/run/secrets`, et reste hors de l'image et de l'environnement.
- Un second fichier, ajouté avec `-f`, ne décrit que les différences de production.

> 📖 [Fusionner plusieurs fichiers Compose](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/) · [Compose en production](https://docs.docker.com/compose/how-tos/production/) · [`COMPOSE_FILE`](https://docs.docker.com/compose/how-tos/environment-variables/envvars/#compose_file) · [`docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/)

## Questions

```quiz
title: "Un fichier pour la production"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Avec `docker compose -f compose.yaml -f compose.prod.yaml up`, quel fichier l'emporte quand les deux donnent une valeur à la même clé ?"
    answers:
      - "Le premier"
      - "Le dernier"
      - "Compose refuse de démarrer"
    correct: 2
    explanation: "Le dernier complète et remplace. Attention aux listes, comme `ports`, qui s'additionnent."
  - prompt: "Le fichier de base publie `28382:8000`, et le fichier de production `127.0.0.1:28383:8000`. Sans `!override`, que se passe-t-il ?"
    answers:
      - "Seul le port 28383 est publié"
      - "Les deux ports sont publiés, et celui de développement reste ouvert"
      - "Compose affiche une erreur"
    correct: 2
    explanation: "Les listes s'additionnent lors de la fusion. `!override` demande de remplacer la liste entière."
  - prompt: "Que doit contenir `compose.prod.yaml` ?"
    answers:
      - "Une copie complète de `compose.yaml`, modifiée"
      - "Seulement ce qui diffère en production"
      - "Seulement les secrets"
    correct: 2
    explanation: "Moins de répétition, donc moins de risque que les deux fichiers divergent sans qu'on le voie."
```
