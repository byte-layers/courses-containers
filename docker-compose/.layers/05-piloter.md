---
title: "Piloter l'application"
description: "Arrêter sans supprimer, agir dans un service, lancer une commande ponctuelle, tout nettoyer"
---

Votre application tourne. Cette dernière étape rassemble les commandes du quotidien, puis supprime ce que vous avez créé.

## Arrêter sans supprimer

`down` supprime les conteneurs. Pour une simple pause, `docker compose stop` les arrête sans les supprimer, et `start` les relance. `-a` montre aussi les conteneurs arrêtés, et `--format` choisit les colonnes, comme pour `docker ps` :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose stop web
cd ~/byte-layers/docker/l7/counter && docker compose ps -a --format '{{.Service}} : {{.State}}'
```

Vous lisez `web : exited`, alors que `cache` et `probe` tournent toujours : ces commandes acceptent un nom de service, pour n'agir que sur lui. Relancez-le :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose start web
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

```verify
if [ "$(docker inspect layers-l7-counter-web-1 --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "web est arrêté. Lancez docker compose start web dans ~/byte-layers/docker/l7/counter."
  exit 1
fi
if [ "$(docker inspect layers-l7-counter-web-1 --format '{{.State.FinishedAt}}')" = "0001-01-01T00:00:00Z" ]; then
  echo "web n'a pas encore été arrêté. Lancez la commande docker compose stop web."
  exit 1
fi
echo "web a été arrêté puis relancé, sans être supprimé."
```

## Agir dans un service

`docker compose exec` lance une commande dans un service qui tourne, comme `docker exec`, mais avec le nom du service au lieu de celui du conteneur. Lisez le compteur directement dans Redis avec `redis-cli`, son outil en ligne de commande :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose exec cache redis-cli get visits
```

Pour un travail ponctuel, `docker compose run` crée au contraire un conteneur **neuf** à partir de la description d'un service, avec une autre commande, et `--rm` le supprime à la fin. Ici, ce nouveau conteneur est sur le même réseau, et `-h cache` dit à `redis-cli` d'interroger le service `cache` :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose run --rm cache redis-cli -h cache get visits
```

Ces deux commandes se distinguent ainsi :

| Commande | Dans quel conteneur | Quand l'utiliser |
|---|---|---|
| `docker compose exec` | un conteneur qui tourne déjà | regarder, déboguer |
| `docker compose run --rm` | un nouveau, supprimé à la fin | une tâche ponctuelle : une migration de base de données, une sauvegarde |

```ack
J'ai lu le compteur avec exec, puis avec run
```

## Suivre en direct

Sans `--tail`, `docker compose logs` affiche tout l'historique. Avec `-f`, il reste ouvert et suit les nouvelles lignes ; `Ctrl+C` l'arrête, sans toucher aux conteneurs. Cette commande est donnée avec `--tail 3` et sans `-f` pour se terminer d'elle-même ; ajoutez `-f` quand vous déboguez :

```exec
curl -s http://localhost:28370 >/dev/null
cd ~/byte-layers/docker/l7/counter && docker compose logs --tail 3 web
```

Vous devez voir une ligne contenant `"GET / HTTP/1.1" 200`.

```verify
if ! docker logs layers-l7-counter-web-1 2>&1 | grep -q 'GET / HTTP/1.1" 200'; then
  echo "Aucune requête réussie dans les logs de web. Demandez la page, puis relisez les logs."
  exit 1
fi
echo "Les requêtes apparaissent dans les logs de web."
```

## Tout supprimer

Il reste à ranger. `-v` supprime aussi le volume, et `--rmi local` supprime l'image que Compose a construite, sans toucher à `redis:8-alpine` ni à `alpine:3.22`. `rm -rf` efface ensuite vos fichiers, en commençant par quitter ce dossier s'il est le vôtre :

```exec
cd ~/byte-layers/docker/l7/counter && docker compose down -v --rmi local
cd ~ && rm -rf ~/byte-layers/docker/l7/counter
```

```verify
if [ -n "$(docker ps -a --filter name=layers-l7-counter --format '{{.Names}}')" ]; then
  echo "Il reste des conteneurs du projet. Lancez le docker compose down ci-dessus."
  exit 1
fi
if [ -n "$(docker volume ls --filter name=layers-l7-counter --format '{{.Name}}')" ]; then
  echo "Il reste un volume du projet. Lancez docker compose down -v."
  exit 1
fi
if docker image inspect layers-l7-counter-web >/dev/null 2>&1; then
  echo "L'image layers-l7-counter-web existe encore : docker rmi layers-l7-counter-web."
  exit 1
fi
if [ -e "$HOME/byte-layers/docker/l7/counter" ]; then
  echo "Le dossier ~/byte-layers/docker/l7/counter existe encore."
  exit 1
fi
echo "C'est propre."
```

## Récap

- Un fichier `compose.yaml` décrit une application : ses services, ses volumes, ses réseaux.
- `up` fait exister cette description et ne refait que la différence ; `down` retire tout sauf les volumes, et `down -v` les emporte aussi.
- Les services se joignent par leur nom, sur les réseaux qu'ils partagent.
- Le fichier `.env` sert à Compose, et la clé `environment:` sert au conteneur.
- `depends_on` règle l'ordre de démarrage, sans garantir que le service est prêt.

> 📖 [Référence de la commande `docker compose`](https://docs.docker.com/reference/cli/docker/compose/) · [Référence du fichier Compose](https://docs.docker.com/reference/compose-file/) · [`docker compose run`](https://docs.docker.com/reference/cli/docker/compose/run/) · [`docker compose exec`](https://docs.docker.com/reference/cli/docker/compose/exec/)

## Questions

```quiz
title: "Piloter l'application"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quelle est la différence entre `docker compose stop` et `docker compose down` ?"
    answers:
      - "Aucune"
      - "`stop` arrête les conteneurs sans les supprimer ; `down` les supprime, ainsi que le réseau"
      - "`stop` supprime les volumes"
    correct: 2
    explanation: "Après `stop`, un `start` les relance tels quels. Après `down`, il faut un `up`."
  - prompt: "Vous voulez lancer une migration de base une seule fois, dans un conteneur qui disparaît ensuite. Quelle commande convient ?"
    answers:
      - "`docker compose exec`"
      - "`docker compose run --rm`"
      - "`docker compose up`"
    correct: 2
    explanation: "`run` crée un conteneur neuf depuis la description d'un service, et `--rm` le supprime à la fin."
  - prompt: "Que supprime `docker compose down -v --rmi local` ? (plusieurs réponses)"
    answers:
      - "Les conteneurs et le réseau du projet"
      - "Les volumes déclarés par le projet"
      - "Les images construites par le projet"
      - "L'image `redis:8-alpine`, téléchargée telle quelle"
    correct: [1, 2, 3]
    explanation: "`--rmi local` ne supprime que les images sans tag personnalisé, donc celles que Compose a construites et nommées lui-même."
```
