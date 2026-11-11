---
title: "Tenir dans la durée"
description: "Redémarrer après une panne, limiter la mémoire, plafonner les logs"
---

Votre application sait attendre. Elle doit maintenant survivre à ce qui finit toujours par arriver : un processus qui s'arrête, une fuite de mémoire, des logs qui remplissent le disque.

## Repartir après une panne

Retirez d'abord le délai artificiel de Redis, qui n'a plus d'utilité, et donnez-lui un volume pour que ses données survivent, comme dans « Garder ses données : volumes et bind mounts ». Le fichier ne contient encore aucune politique de redémarrage :

```exec
cat > ~/byte-layers/docker/l8/reliable/compose.yaml <<'EOF'
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
    command: ["redis-server", "--appendonly", "yes"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 2s
      retries: 10
    volumes:
      - cache-data:/data
volumes:
  cache-data:
EOF
cd ~/byte-layers/docker/l8/reliable && docker compose up -d
```

Simulez une panne de l'application, en appelant l'adresse `/crash`. Le processus principal s'arrête sur une erreur, donc le conteneur aussi. `curl` n'affiche rien, car il n'a reçu aucune réponse :

```exec
sleep 2
curl -s --max-time 2 http://localhost:28382/crash
sleep 1
cd ~/byte-layers/docker/l8/reliable && docker compose ps -a --format '{{.Service}} : {{.Status}}'
```

`web` est `Exited (1)`, et il le restera : rien ne le relance. Sur un serveur, à trois heures du matin, c'est une panne jusqu'à ce que quelqu'un s'en aperçoive.

La clé `restart` règle cela, avec les mêmes valeurs que `--restart` dans « Lancer, configurer et observer un conteneur » :

| Valeur | Effet |
|---|---|
| `no` | jamais, c'est le défaut |
| `on-failure` | seulement après une sortie en erreur |
| `always` | toujours, y compris après un arrêt manuel, au redémarrage de Docker |
| `unless-stopped` | toujours, sauf si vous l'avez arrêté vous-même |

Sur un serveur, on préfère souvent `unless-stopped`. Ajoutez cette ligne aux deux services. `awk` recopie ici le fichier ligne à ligne, en écrivant `restart: unless-stopped` après chaque ligne `build:` ou `image:` ; vous pouvez aussi le faire dans votre éditeur :

```exec
cd ~/byte-layers/docker/l8/reliable && awk '{print} /^    (build|image):/{print "    restart: unless-stopped"}' compose.yaml > compose.new && mv compose.new compose.yaml
cd ~/byte-layers/docker/l8/reliable && docker compose up -d
```

Provoquez la même panne, puis lisez le nombre de redémarrages :

```exec
sleep 2
curl -s --max-time 2 http://localhost:28382/crash
sleep 3
docker inspect layers-l8-reliable-web-1 --format '{{.State.Status}}, {{.RestartCount}} redémarrage(s)'
```

Vous lisez `running, 1 redémarrage(s)`. La panne a duré quelques instants, et personne n'a eu à intervenir.

```verify
W=layers-l8-reliable-web-1
for C in web cache; do
  P=$(docker inspect layers-l8-reliable-$C-1 --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
  if [ "$P" != "unless-stopped" ]; then
    echo "$C a la politique « ${P:-aucune} », unless-stopped attendue. Vérifiez le fichier, puis lancez docker compose up -d."
    exit 1
  fi
done
N=$(docker inspect $W --format '{{.RestartCount}}')
if [ "$N" -lt 1 ]; then
  echo "web n'a pas encore redémarré. Lancez la commande de cette section qui appelle /crash."
  exit 1
fi
echo "web a redémarré tout seul $N fois."
```

## Limiter les ressources

Sans limite, un conteneur peut consommer toute la mémoire de la machine, et faire tomber les autres avec lui. Dans Compose, les limites s'écrivent sous `deploy.resources.limits`. Le mot `deploy` vient de Swarm, l'orchestrateur de Docker, mais `docker compose up` applique bien cette partie-là :

| Clé | Limite | Si elle est dépassée |
|---|---|---|
| `memory` | la mémoire, ici `128M` | le processus est tué par le système |
| `cpus` | la part de processeur, ici `"0.5"` pour un demi-cœur | le processus est ralenti |
| `pids` | le nombre de processus et de fils d'exécution, ici `100` | il ne peut plus en créer, ce qui bloque une *fork bomb*, un programme qui se multiplie jusqu'à saturer la machine |

Pour choisir une valeur, mesurez. `docker stats` montre la consommation réelle, et `--no-stream` affiche une seule mesure, sans rester ouvert :

```exec
docker stats --no-stream --format '{{.Name}} : {{.MemUsage}}, {{.PIDs}} processus' layers-l8-reliable-web-1 layers-l8-reliable-cache-1
```

`web` consomme environ 10 Mio, soit 10 mébioctets, l'unité que Docker affiche et que Compose écrit `M` : 128 Mio laissent une marge confortable. Ajoutez la limite à `web`, et plafonnez aussi ses logs. Par défaut, Docker les garde sans limite dans un fichier, et un serveur finit par manquer de disque pour cette seule raison. Le pilote `json-file` est celui que Docker utilise déjà, et `max-size` et `max-file` limitent ici à 3 fichiers de 1 Mio :

```exec
cat > ~/byte-layers/docker/l8/reliable/compose.yaml <<'EOF'
name: layers-l8-reliable
services:
  web:
    build: .
    restart: unless-stopped
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
volumes:
  cache-data:
EOF
cd ~/byte-layers/docker/l8/reliable && docker compose up -d
```

Vérifiez que la limite tient. Cette commande demande à Python de remplir 300 Mio. Elle doit échouer :

```exec
sleep 3
cd ~/byte-layers/docker/l8/reliable && docker compose exec web python -c "x = b'x' * (300 * 1024 * 1024); print('300 Mio obtenus')"; echo "code de sortie : $?"
```

Le code `137` veut dire `SIGKILL`, comme dans « Lancer, configurer et observer un conteneur » : le système a tué le processus, et le message `300 Mio obtenus` ne s'affiche pas. La fiche du conteneur le confirme :

```exec
docker inspect layers-l8-reliable-web-1 --format 'tué par manque de mémoire : {{.State.OOMKilled}}, état : {{.State.Status}}'
```

`OOM` veut dire *out of memory*. Seule cette commande a été tuée : le conteneur tourne toujours, et le reste de la machine n'a rien senti.

```verify
W=layers-l8-reliable-web-1
M=$(docker inspect $W --format '{{.HostConfig.Memory}}' 2>/dev/null)
if [ "$M" != "134217728" ]; then
  echo "La mémoire de web n'est pas limitée à 128 Mio (trouvé : ${M:-rien} octets, 0 veut dire aucune limite). Appliquez le fichier avec docker compose up -d."
  exit 1
fi
if [ "$(docker inspect $W --format '{{.HostConfig.PidsLimit}}')" != "100" ]; then
  echo "web n'a pas de limite de 100 processus."
  exit 1
fi
if [ "$(docker inspect $W --format '{{index .HostConfig.LogConfig.Config "max-size"}}')" != "1m" ]; then
  echo "Les logs de web ne sont pas plafonnés à 1 Mio par fichier."
  exit 1
fi
if [ "$(docker inspect $W --format '{{.State.OOMKilled}}')" != "true" ]; then
  echo "Le dépassement n'a pas encore eu lieu dans ce conteneur. Relancez la commande qui remplit 300 Mio."
  exit 1
fi
echo "La limite de 128 Mio a été appliquée, et elle a tenu."
```

> 📖 [`restart`](https://docs.docker.com/reference/compose-file/services/#restart) · [`deploy.resources`](https://docs.docker.com/reference/compose-file/deploy/#resources) · [Le pilote de logs `json-file`](https://docs.docker.com/engine/logging/drivers/json-file/) · [`docker stats`](https://docs.docker.com/reference/cli/docker/container/stats/)

## Questions

```quiz
title: "Tenir dans la durée"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quelle différence y a-t-il entre `always` et `unless-stopped` ?"
    answers:
      - "Aucune"
      - "Après un `docker stop` suivi d'un redémarrage de Docker, `always` relance le conteneur et `unless-stopped` le laisse arrêté"
      - "`unless-stopped` ne relance jamais après une erreur"
    correct: 2
    explanation: "`unless-stopped` respecte votre décision d'arrêter le conteneur, même après un redémarrage de la machine."
  - prompt: "Un conteneur limité à 128 Mio cherche à en utiliser 300. Que se passe-t-il ?"
    answers:
      - "Il est ralenti jusqu'à passer sous la limite"
      - "Le système tue le processus, et le code 137 apparaît"
      - "Docker augmente la limite automatiquement"
    correct: 2
    explanation: "La mémoire ne se ralentit pas : le dépassement se termine par SIGKILL. Le ralentissement concerne la limite `cpus`."
  - prompt: "Pourquoi plafonner les logs avec `max-size` et `max-file` ?"
    answers:
      - "Pour que les logs s'affichent plus vite"
      - "Parce que, par défaut, leur fichier grandit sans limite et peut remplir le disque"
      - "Parce que `docker logs` refuse les fichiers de plus de 1 Mio"
    correct: 2
    explanation: "Le pilote `json-file` garde tout par défaut. Avec ce plafond, Docker fait tourner les fichiers et supprime les plus anciens."
```
