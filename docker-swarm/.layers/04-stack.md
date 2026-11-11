---
title: "Déployer une stack"
description: "Un fichier Compose, la section deploy, un réseau qui relie les services"
---

Taper les options de chaque service n'est pas tenable au-delà d'un service, et rien ne garde la trace de ce que vous avez tapé. Vous connaissez déjà la réponse : un fichier Compose. Swarm sait le lire, et le résultat s'appelle une **stack**, un ensemble de services déployés ensemble.

## Écrire le fichier

Ce fichier décrit une application de deux services : votre image en 3 répliques, et un Redis, une base de données en mémoire. Il se place à côté du Dockerfile :

```exec
cat > ~/byte-layers/docker/l9/app/compose.yaml <<'EOF'
services:
  web:
    build: .
    image: layers-l9-app:1
    ports:
      - "28393:8000"
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 2s
  cache:
    image: redis:8-alpine
    deploy:
      replicas: 1
EOF
```

Vous retrouvez le format de Compose, avec une nouveauté : la section `deploy`. C'est elle qui porte ce que vous passiez en options à `docker service`.

| Champ | Rôle | L'option équivalente |
|---|---|---|
| `deploy.replicas` | le nombre de copies | `--replicas` |
| `deploy.update_config.parallelism` | les tâches remplacées à la fois | `--update-parallelism` |
| `deploy.update_config.delay` | l'attente entre deux remplacements | `--update-delay` |

## Déployer

`docker stack deploy` lit le fichier et crée tout ce qu'il décrit. `-c` désigne le fichier, le dernier mot est le nom de la stack, et `--detach=false` attend que les services soient prêts avant de vous rendre la main :

```exec
docker stack deploy -c ~/byte-layers/docker/l9/app/compose.yaml --detach=false layers-l9-demo
```

La première ligne dit `Ignoring unsupported options: build`, et c'est normal. Swarm ne construit pas d'image, comme vous l'avez vu à l'étape précédente : il ne tient compte que de `image`. Le champ `build` reste utile dans le même fichier : `docker compose build` s'en sert pour construire l'image sur votre poste, avant que vous ne la publiiez. L'avertissement `could not be accessed on a registry` peut aussi revenir, pour la raison vue à l'étape précédente.

Les deux commandes suivantes montrent les services de la stack, puis leurs tâches :

```exec
docker stack services layers-l9-demo
docker stack ps layers-l9-demo --format 'table {{.Name}}\t{{.CurrentState}}'
```

Chaque service porte le nom de la stack comme préfixe : `layers-l9-demo_web` et `layers-l9-demo_cache`. Le service web a `3/3` répliques, et le cache `1/1`.

```verify
W=$(docker service ls --filter name=layers-l9-demo_web --format '{{.Replicas}}')
C=$(docker service ls --filter name=layers-l9-demo_cache --format '{{.Replicas}}')
if [ "$W" != "3/3" ] || [ "$C" != "1/1" ]; then
  echo "La stack n'est pas prête (web : ${W:-absent}, cache : ${C:-absent}). Regardez : docker stack ps layers-l9-demo"
  exit 1
fi
echo "La stack layers-l9-demo tourne : web 3/3, cache 1/1."
```

## Le réseau entre les services

Comme Compose, une stack crée un réseau par défaut, sur lequel chaque service se joint par son nom. Mais ce réseau est d'un autre type :

```exec
docker network ls --filter name=layers-l9-demo
```

Le pilote est `overlay`, et sa portée est `swarm` : ce réseau traverse les nœuds, de sorte que deux tâches placées sur des machines différentes se parlent comme si elles étaient côte à côte. Vérifiez qu'une tâche de `web` joint bien le service `cache` par son nom. La commande va chercher un conteneur de `web`, et lui fait envoyer `PING` à Redis avec `nc`, un petit outil qui envoie du texte sur un port. `-w 2` n'attend la réponse que 2 secondes, et 6379 est le port de Redis :

```exec
docker exec "$(docker ps -q --filter label=com.docker.swarm.service.name=layers-l9-demo_web | head -n 1)" sh -c 'echo PING | nc -w 2 cache 6379'
```

Vous devez lire `+PONG`, la réponse de Redis.

```verify
W=$(docker ps -q --filter label=com.docker.swarm.service.name=layers-l9-demo_web | head -n 1)
if [ -z "$W" ]; then
  echo "Aucune tâche du service web ne tourne. Regardez : docker stack ps layers-l9-demo"
  exit 1
fi
if ! docker exec "$W" sh -c 'echo PING | nc -w 2 cache 6379' | grep -q PONG; then
  echo "Le service web ne joint pas le service cache sur le réseau de la stack."
  exit 1
fi
echo "Le service web joint le service cache par son nom."
```

## Mettre à jour par le fichier

Avec une stack, on ne lance plus `docker service update` : **le fichier reste la référence**. On le modifie, et on relance la même commande. Swarm compare, et ne touche qu'à ce qui a changé. `sed -i.bak` remplace le texte directement dans le fichier, et garde une copie en `.bak` :

```exec
sed -i.bak 's/layers-l9-app:1/layers-l9-app:2/' ~/byte-layers/docker/l9/app/compose.yaml
docker stack deploy -c ~/byte-layers/docker/l9/app/compose.yaml --detach=false layers-l9-demo
```

La commande affiche `Updating service` pour les deux services, car elle les présente tous à Swarm, et elle dure près d'une minute, le temps de remplacer les 3 tâches de `web`. Regardez les services, puis demandez la page :

```exec
docker stack services layers-l9-demo
curl -sS --retry 5 --retry-delay 1 --retry-all-errors --max-time 5 http://127.0.0.1:28393
```

Le service web est passé à `layers-l9-app:2`, et la page dit `version 2`. Le cache n'a pas été redémarré, malgré ce `Updating service`, puisque rien n'a changé pour lui.

```verify
IMG=$(docker service inspect layers-l9-demo_web --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null)
case "$IMG" in
  layers-l9-app:2*) : ;;
  *) echo "Le service web utilise « ${IMG:-rien} », et non layers-l9-app:2. Relancez les commandes de cette section."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://127.0.0.1:28393 | grep -q 'version 2'; then
  echo "La page ne répond pas encore « version 2 ». Attendez la fin de la mise à jour, puis réessayez."
  exit 1
fi
echo "La stack sert la version 2."
```

## Retirer la stack

`docker stack rm` retire les services et le réseau de la stack. Il rend la main avant que tout soit vraiment parti :

```exec
docker stack rm layers-l9-demo
```

```verify
for i in 1 2 3 4 5; do
  [ -z "$(docker stack ls --format '{{.Name}}' | grep '^layers-l9-demo$')" ] && break
  sleep 2
done
if docker stack ls --format '{{.Name}}' | grep -q '^layers-l9-demo$'; then
  echo "La stack layers-l9-demo existe encore. Lancez docker stack rm."
  exit 1
fi
echo "La stack est retirée."
```

> 📖 [Déployer une stack](https://docs.docker.com/engine/swarm/stack-deploy/) · [`docker stack deploy`](https://docs.docker.com/reference/cli/docker/stack/deploy/) · [La section `deploy` de Compose](https://docs.docker.com/reference/compose-file/deploy/)

## Récap

- Une stack est un fichier Compose déployé sur un swarm, et ses services portent son nom en préfixe.
- La section `deploy` décrit les répliques et le rythme des mises à jour, et Swarm ignore le champ `build`.
- Son réseau `overlay` relie les services par leur nom, à travers les nœuds.
- Pour mettre à jour, on modifie le fichier et on relance `docker stack deploy`.

## Questions

```quiz
title: "Les stacks"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`docker stack deploy` affiche `Ignoring unsupported options: build`. Que faut-il faire ?"
    answers:
      - "Corriger le fichier : il est invalide"
      - "Rien de particulier : Swarm ne construit pas, et il utilise le champ `image`"
      - "Relancer avec `--build`"
    correct: 2
    explanation: "L'image doit déjà exister, et, sur un cluster, être disponible dans un registre."
  - prompt: "Vous modifiez un service dans le fichier et vous relancez `docker stack deploy`. Qu'arrive-t-il aux autres services ?"
    answers:
      - "Ils sont tous redémarrés"
      - "Ils ne sont pas touchés, puisque rien n'a changé pour eux"
      - "Ils sont supprimés"
    correct: 2
    explanation: "Swarm compare l'état voulu avec l'existant, et ne corrige que l'écart."
```
