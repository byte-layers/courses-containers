---
title: "Données, réseaux, ordre de démarrage"
description: "Déclarer un volume, séparer les réseaux, et ce que depends_on garantit vraiment"
---

Le compteur vit dans la mémoire de Redis, donc dans le conteneur. Comme le montrait « Garder ses données : volumes et bind mounts », un conteneur est jetable : ce qui doit durer va dans un volume. Compose déclare ce volume dans le fichier, au même endroit que le reste.

## Constater la perte

Regardez la valeur actuelle du compteur, puis faites un `down` suivi d'un `up` :

```exec
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
cd ~/byte-layers/docker/l7/counter && docker compose down && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Le compteur repart à `1`. Les conteneurs ont été supprimés, et leurs données avec eux.

## Déclarer un volume

Un volume nommé demande deux choses dans le fichier : une section `volumes:` en bas, qui le déclare, et une clé `volumes:` dans le service, qui le monte. Redis doit aussi écrire sur le disque, ce qu'il ne fait pas assez souvent par défaut : `command` remplace la commande de l'image, et `--appendonly yes` lui demande d'y noter chaque écriture. Son dossier de données est `/data`.

Tant que vous y êtes, `depends_on` dit à Compose de démarrer `cache` avant `web` ; la dernière partie de cette étape dit ce que cela garantit, et ce que cela ne garantit pas.

```exec
cat > ~/byte-layers/docker/l7/counter/compose.yaml <<'EOF'
name: layers-l7-counter
services:
  web:
    build: .
    ports:
      - "${WEB_PORT:-28370}:8000"
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
```

Ce tableau détaille ce que ce fichier apporte :

| Écriture | Rôle |
|---|---|
| `cache-data:/data` | monte le volume `cache-data` sur le dossier `/data` du conteneur |
| `volumes:` en bas du fichier | déclare ce volume ; Compose le crée au premier `up` |
| `["redis-server", ...]` | une autre écriture d'une liste YAML, sur une seule ligne |

Appliquez ce fichier, puis faites monter le compteur et refaites le même `down` suivi d'un `up` :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
curl -s http://localhost:28370
cd ~/byte-layers/docker/l7/counter && docker compose down && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Le compteur continue : le dernier appel affiche `3`, ou plus. Le volume a survécu à `down`, et son nom est préfixé par celui du projet :

```exec
docker volume ls --filter name=layers-l7-counter
```

```verify
SRC=$(docker inspect layers-l7-counter-cache-1 --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}' 2>/dev/null)
if [ "$SRC" != "volume:layers-l7-counter_cache-data" ]; then
  echo "cache n'a pas le volume cache-data sur /data (trouvé : ${SRC:-rien}). Appliquez le fichier avec docker compose up -d."
  exit 1
fi
N=$(curl -s --max-time 5 http://localhost:28370 | sed -n 's/.*Visites : //p')
if [ -z "$N" ] || [ "$N" -lt 3 ]; then
  echo "Le compteur vaut ${N:-rien}, il devrait avoir survécu à un down. Rejouez la commande qui fait monter le compteur, puis celle du down et du up."
  exit 1
fi
echo "Le volume est monté et le compteur a survécu à un down : il vaut $N."
```

## Effacer vraiment

`down` seul garde les volumes nommés, parce qu'il serait trop facile de perdre des données par erreur. `-v` les supprime aussi. Essayez, et prévoyez la valeur avant de lancer :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose down -v && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Le compteur repart à `1`. Sur un serveur, `-v` efface donc la base de données : relisez toujours cette option à deux fois.

```ack
J'ai vu la différence entre down et down -v
```

## Séparer les réseaux

Le réseau créé par défaut laisse chaque service parler à tous les autres. Pour une petite application, cela suffit. Mais un service n'a pas à joindre ce qu'il n'utilise pas : si le serveur web tombe aux mains d'un attaquant, autant qu'il n'accède pas à tout. Vous pouvez donc déclarer vos propres réseaux. Commencez par arrêter l'application. Une fois le fichier réécrit, le réseau par défaut n'y figurerait plus, et `down` le laisserait derrière lui :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose down
```

Ce nouveau fichier crée deux réseaux, et ajoute `probe`, un conteneur qui ne fait qu'attendre, placé là pour tester ce qu'on voit depuis `front` :

```exec
cat > ~/byte-layers/docker/l7/counter/compose.yaml <<'EOF'
name: layers-l7-counter
services:
  web:
    build: .
    ports:
      - "${WEB_PORT:-28370}:8000"
    environment:
      REDIS_HOST: cache
      GREETING: ${GREETING:-Bonjour}
    depends_on:
      - cache
    networks:
      - front
      - back
  cache:
    image: redis:8-alpine
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - cache-data:/data
    networks:
      - back
  probe:
    image: alpine:3.22
    command: ["sleep", "3600"]
    networks:
      - front
volumes:
  cache-data:
networks:
  front:
  back:
EOF
```

`web` est sur les deux réseaux, `cache` seulement sur `back`, `probe` seulement sur `front`. Comme pour un volume, un réseau se déclare en bas du fichier et s'utilise dans le service. Appliquez, puis testez depuis `probe` :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose up -d
cd ~/byte-layers/docker/l7/counter && docker compose exec probe sh -c 'ping -c 1 -W 1 web; ping -c 1 -W 1 cache'
```

`ping` envoie un paquet et attend la réponse : `-c 1` en envoie un seul, et `-W 1` n'attend qu'une seconde. `probe` joint `web`, puisqu'ils partagent `front`. Pour `cache`, il répond `bad address 'cache'` : ce nom n'existe même pas de son côté. Et l'application marche toujours, car `web` est sur les deux réseaux :

```exec
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

```verify
P=layers-l7-counter-probe-1
if [ "$(docker inspect $P --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$P ne tourne pas. Appliquez le fichier avec docker compose up -d."
  exit 1
fi
if docker exec $P ping -c 1 -W 1 cache >/dev/null 2>&1; then
  echo "probe joint cache alors qu'il ne devrait pas. Vérifiez que cache n'est que sur le réseau back, et probe que sur front."
  exit 1
fi
if ! docker exec $P ping -c 1 -W 1 web >/dev/null 2>&1; then
  echo "probe ne joint pas web. Vérifiez que web est bien sur le réseau front."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28370 | grep -q 'Visites'; then
  echo "L'application ne répond plus. Vérifiez que web est aussi sur le réseau back."
  exit 1
fi
echo "probe joint web mais pas cache, et l'application fonctionne."
```

## Ce que depends_on garantit

Vous avez écrit `depends_on: [cache]` plus haut. Il ne garantit qu'une chose : Compose **démarre** `cache` avant `web`, et l'arrête après. Il n'attend pas que Redis soit prêt à répondre. Le conteneur peut être `Up` alors que le programme à l'intérieur s'initialise encore, et une base de données met souvent plusieurs secondes à le faire.

Le compteur ne s'en aperçoit pas : il ne contacte Redis qu'à la première visite, et Redis démarre vite. Une application qui se connecte à sa base dès le démarrage peut, elle, échouer si la base n'est pas prête. Attendre qu'un service soit réellement prêt demande un contrôle de santé, qu'un prochain cours met en place.

```ack
J'ai compris que depends_on règle l'ordre de démarrage, pas la disponibilité
```

> 📖 [Les volumes dans Compose](https://docs.docker.com/reference/compose-file/volumes/) · [Les réseaux dans Compose](https://docs.docker.com/reference/compose-file/networks/) · [`depends_on`](https://docs.docker.com/reference/compose-file/services/#depends_on)

## Questions

```quiz
title: "Données, réseaux, ordre de démarrage"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Après `docker compose down`, le volume nommé du projet existe-t-il encore ?"
    answers:
      - "Non, `down` supprime tout ce que le projet a créé"
      - "Oui, il faut `down -v` pour le supprimer"
      - "Oui, mais ses données sont vidées"
    correct: 2
    explanation: "C'est la raison pour laquelle le compteur a survécu à `down`, et pas à `down -v`."
  - prompt: "`web` a `depends_on: [db]`, et plante au démarrage avec « connection refused » vers `db`. Pourquoi est-ce possible ?"
    answers:
      - "`depends_on` ne marche qu'avec des images officielles"
      - "`depends_on` attend que `db` soit démarré, pas que son programme soit prêt à répondre"
      - "Il manque la clé `ports` sur `db`"
    correct: 2
    explanation: "L'ordre de démarrage est respecté, mais la base s'initialise encore. Il faut un contrôle de santé pour attendre vraiment."
  - prompt: "`cache` est sur le réseau `back`, `probe` sur le réseau `front`. Que se passe-t-il si `probe` appelle `cache` ?"
    answers:
      - "Ça marche, puisqu'ils sont dans le même projet"
      - "Le nom n'est pas résolu : `probe` ne partage aucun réseau avec `cache`"
      - "Ça marche seulement si `cache` publie un port"
    correct: 2
    explanation: "Sur un réseau déclaré, seuls ses membres se voient. Vous avez lu `bad address 'cache'`."
```
