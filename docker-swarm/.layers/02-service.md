---
title: "Lancer un service"
description: "Des répliques, un port partagé, une tâche qui revient toute seule"
---

Votre swarm tourne, mais il ne fait rien. Un **service** décrit ce que vous voulez qu'il maintienne. C'est l'équivalent de `docker run`, à une grande différence près : Swarm continuera à y veiller une fois la commande terminée.

## Créer un service

Demandez deux copies, appelées **répliques**, d'un serveur nginx, publiées sur un seul port :

```exec
docker service create --name layers-l9-web --replicas 2 -p 28391:80 nginx:1.30-alpine
```

| Élément | Rôle |
|---|---|
| `docker service create` | déclare un service ; Swarm crée les tâches pour le réaliser |
| `--name layers-l9-web` | le nom du service |
| `--replicas 2` | le nombre de copies voulues |
| `-p 28391:80` | le port 28391 du cluster mène au port 80 des tâches |

La commande affiche sa progression, puis `verify: Service … converged` : les tâches tournent, et sont restées stables pendant 5 secondes. Regardez ce que Swarm a compris, puis ce qu'il a fait :

```exec
docker service ls
docker service ps layers-l9-web
```

`docker service ls` donne l'état d'ensemble, et `2/2` se lit « 2 tournent sur 2 voulues ». `docker service ps` détaille les tâches, nommées `layers-l9-web.1` et `layers-l9-web.2`, avec le nœud où chacune tourne.

```verify
if [ "$(docker service ls --filter name=layers-l9-web --format '{{.Replicas}}')" != "2/2" ]; then
  echo "Le service layers-l9-web n'a pas 2 répliques en cours d'exécution. Regardez : docker service ps layers-l9-web"
  exit 1
fi
echo "Les 2 répliques de layers-l9-web tournent."
```

## Un port pour plusieurs copies

Deux conteneurs ne pouvaient pas partager un port sur une machine, et pourtant vos deux répliques répondent sur le même. Swarm publie ce port sur le nœud, et répartit les requêtes entre les tâches, grâce à un réseau interne appelé **routing mesh**. Sur un vrai cluster, ce port répond sur **tous** les nœuds, même ceux où aucune tâche ne tourne.

Demandez la page. L'adresse `127.0.0.1` désigne votre machine, tout comme `localhost`, mais elle est préférable ici : le routing mesh n'écoute qu'en IPv4, et `localhost` peut d'abord tenter l'IPv6, où `curl` resterait sans réponse.

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors --max-time 5 http://127.0.0.1:28391 | grep '<h1>'
```

Vous devez lire `<h1>Welcome to nginx!</h1>`.

```verify
if ! curl -s --max-time 5 http://127.0.0.1:28391 | grep -q 'Welcome to nginx'; then
  echo "Le service ne répond pas sur le port 28391. Vérifiez ses ports avec : docker service ls"
  exit 1
fi
echo "Le service répond sur le port 28391."
```

## Une tâche qui revient

Voici ce qu'un conteneur ordinaire ne fait pas. Supprimez de force l'un des conteneurs du service. Ces conteneurs sont visibles avec `docker ps`, et Swarm leur pose à chacun une étiquette qui donne le nom de leur service, ce qui permet de les filtrer. `head -n 1` n'en garde qu'un, et `$(…)` donne son identifiant à `docker rm -f` :

```exec
docker rm -f "$(docker ps -q --filter label=com.docker.swarm.service.name=layers-l9-web | head -n 1)"
```

Attendez quelques secondes, puis regardez à nouveau les tâches :

```exec
sleep 8
docker service ps layers-l9-web
```

Swarm a constaté l'écart entre 2 voulues et 1 observée, et il a créé une nouvelle tâche. L'ancienne reste dans l'historique : son nom est précédé de `\_` dans la colonne `NAME`, son état voulu est `Shutdown`, son état courant `Failed`, et l'erreur `task: non-zero exit (137)` donne le code d'un processus tué de force. C'est l'état voulu à l'œuvre : **on ne répare pas un conteneur, on le remplace**.

```verify
for i in 1 2 3 4 5 6 7 8; do
  HIST=$(docker service ps layers-l9-web --filter desired-state=shutdown -q 2>/dev/null)
  RUN=$(docker service ls --filter name=layers-l9-web --format '{{.Replicas}}' 2>/dev/null)
  [ -n "$HIST" ] && [ "$RUN" = "2/2" ] && break
  sleep 2
done
if [ -z "$HIST" ]; then
  echo "Aucune tâche remplacée dans l'historique. Lancez le docker rm -f de cette section."
  exit 1
fi
if [ "$RUN" != "2/2" ]; then
  echo "Le service n'est pas revenu à 2 répliques (trouvé : ${RUN:-rien}). Patientez, puis réessayez."
  exit 1
fi
echo "Swarm a remplacé la tâche supprimée."
```

## Changer le nombre de copies

Pour tenir plus de charge, il suffit de changer l'état voulu. `docker service scale` modifie le nombre de répliques, et Swarm fait le reste :

```exec
docker service scale layers-l9-web=4
docker service ls
```

Vous devez lire `4/4`. Sur un vrai cluster, ces tâches se répartiraient entre les nœuds.

```verify
if [ "$(docker service ls --filter name=layers-l9-web --format '{{.Replicas}}')" != "4/4" ]; then
  echo "Le service n'a pas 4 répliques. Lancez docker service scale, puis attendez qu'elles démarrent."
  exit 1
fi
echo "Le service a 4 répliques."
```

## Lire ce qu'il dit

Les logs d'un service réunissent ceux de toutes ses tâches, chaque ligne étant précédée du nom de la tâche qui l'a écrite. Envoyez une requête, en jetant la page avec `-o /dev/null`, puis lisez les 2 dernières lignes de chaque tâche :

```exec
curl -sS -o /dev/null http://127.0.0.1:28391
docker service logs --tail 2 layers-l9-web
```

Vous lisez des lignes de la forme `layers-l9-web.2.r6kcfxr8ng8m@poste    | …`, où l'on reconnaît la tâche, puis le nœud. Ce service a joué son rôle : `docker service rm` le supprime avec toutes ses tâches :

```exec
docker service rm layers-l9-web
```

```verify
if docker service inspect layers-l9-web >/dev/null 2>&1; then
  echo "Le service layers-l9-web existe encore. Lancez docker service rm."
  exit 1
fi
echo "Le service est supprimé, et le swarm reste actif pour l'étape suivante."
```

> 📖 [`docker service create`](https://docs.docker.com/reference/cli/docker/service/create/) · [`docker service scale`](https://docs.docker.com/reference/cli/docker/service/scale/) · [Le routing mesh](https://docs.docker.com/engine/swarm/ingress/)

## Récap

- Un service déclare un état voulu, et `docker service ps` montre les tâches qui le réalisent.
- Le routing mesh répartit les requêtes d'un même port entre les tâches.
- Une tâche supprimée est remplacée, et l'échelle se change d'une seule commande.

## Questions

```quiz
title: "Les services"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`docker service ls` affiche `3/5` pour un service. Qu'est-ce que cela veut dire ?"
    answers:
      - "3 services sur 5 fonctionnent"
      - "3 tâches tournent, sur les 5 voulues"
      - "La version 3 sur 5 est déployée"
    correct: 2
    explanation: "Swarm travaille encore à atteindre l'état voulu. `docker service ps` dit où en est chaque tâche."
  - prompt: "Vous supprimez un conteneur d'un service avec `docker rm -f`. Que se passe-t-il ?"
    answers:
      - "Le service compte une réplique de moins, définitivement"
      - "Swarm constate l'écart et crée une nouvelle tâche"
      - "Docker refuse de supprimer un conteneur géré par Swarm"
    correct: 2
    explanation: "Pour réduire vraiment le nombre de répliques, c'est l'état voulu qu'il faut changer, avec `docker service scale`."
  - prompt: "Comment deux répliques peuvent-elles répondre sur un même port ?"
    answers:
      - "Chacune a son propre port, et le premier arrivé répond"
      - "Le routing mesh reçoit les requêtes sur ce port et les répartit entre les tâches"
      - "Elles partagent un seul processus"
    correct: 2
    explanation: "Ce port appartient au routing mesh, et non aux conteneurs."
```
