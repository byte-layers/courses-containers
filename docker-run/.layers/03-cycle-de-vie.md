---
title: "Le cycle de vie"
description: "Créer, démarrer, arrêter, figer, supprimer : les états d'un conteneur et ce qui les fait changer"
---

## Les états

Un conteneur est toujours dans un seul état.

```
            docker create           docker start
                 │                       │
                 ▼                       ▼
              created ──────────────► running ◄────► paused
                                       │  ▲    pause / unpause
          fin du processus, stop, kill │  │  start
                                       ▼  │
                                      exited ──► supprimé
                                            rm
```

`docker run` enchaîne `create` et `start`. Essayez-les séparément, `docker ps -a` montrant l'état :

```exec
docker create --name layers-l1-etapes alpine:3.22 echo bonjour
docker ps -a --filter name=layers-l1-etapes --format '{{.Names}} : {{.Status}}'
```

Il est `Created` : il existe, mais rien ne tourne. Démarrez-le. `-a` affiche sa sortie :

```exec
docker start -a layers-l1-etapes
docker ps -a --filter name=layers-l1-etapes --format '{{.Names}} : {{.Status}}'
```

Il est `Exited (0)` : sa commande a fini, et `0` veut dire « tout s'est bien passé ».

```verify
if [ "$(docker inspect layers-l1-etapes --format '{{.State.Status}}' 2>/dev/null)" != "exited" ]; then
  echo "layers-l1-etapes n'est pas dans l'état exited. Lancez les deux commandes ci-dessus."
  exit 1
fi
echo "Created, puis running, puis exited."
```

## Figer et reprendre

Lancez nginx, un serveur web, puis figez-le. `pause` suspend ses processus sans les terminer : ils restent en mémoire et ne consomment plus de CPU. La dernière commande utilise `docker inspect`, qui lit la fiche d'un conteneur, pour en extraire l'état ; l'étape 4 la détaille.

```exec
docker run -d --name layers-l1-nginx nginx:1.30-alpine
docker pause layers-l1-nginx
docker inspect layers-l1-nginx --format '{{.State.Status}}'
```

```verify
if [ "$(docker inspect layers-l1-nginx --format '{{.State.Paused}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l1-nginx n'est pas en pause. Si vous l'avez déjà repris : docker pause layers-l1-nginx. Sinon, pour repartir de zéro : docker rm -f layers-l1-nginx, puis les commandes ci-dessus."
  exit 1
fi
echo "layers-l1-nginx est figé."
```

Reprenez maintenant son exécution avec `unpause` :

```exec
docker unpause layers-l1-nginx
```

## Arrêter proprement

Un **signal** est un message que le système envoie à un processus. `docker stop` en envoie un qui demande de s'arrêter, souvent `SIGTERM`. Si le processus n'a pas fini après 10 secondes, Docker le tue avec `SIGKILL`, le signal numéro 9, qu'on ne peut pas ignorer. Le **code de sortie** raconte ce qui s'est passé. Arrêtez nginx, qui sait gérer cette demande :

```exec
docker stop layers-l1-nginx
docker inspect layers-l1-nginx --format 'code de sortie : {{.State.ExitCode}}'
```

`0` : il s'est arrêté proprement, presque tout de suite. Essayez maintenant avec `sleep`, qui ignore la demande quand il est le PID 1 d'un conteneur. **La commande va rester muette pendant 10 secondes**, c'est normal :

```exec
docker run -d --name layers-l1-dort alpine:3.22 sleep 3600
docker stop layers-l1-dort
docker inspect layers-l1-dort --format 'code de sortie : {{.State.ExitCode}}'
```

Le code est `137`. Au-dessus de 128, un code veut dire « arrêté par le signal numéro code - 128 » : ici 137 - 128 = 9, donc `SIGKILL`. `docker kill` envoie directement ce signal, sans laisser au processus la moindre chance de finir ce qu'il fait.

Une application qui ne gère pas cette demande perd donc ses requêtes en cours à chaque arrêt.

Un conteneur arrêté se relance avec `docker start`. Sans `-a`, qui affiche sa sortie, il rend aussitôt la main, ce qui convient à un serveur :

```exec
docker start layers-l1-nginx
docker inspect layers-l1-nginx --format '{{.State.Status}}'
```

```verify
FIN=$(docker inspect layers-l1-nginx --format '{{.State.FinishedAt}}' 2>/dev/null)
case "$FIN" in
  ""|0001-01-01*) echo "layers-l1-nginx n'a pas encore été arrêté. Avez-vous fait le docker unpause, puis le docker stop ?"; exit 1 ;;
esac
if [ "$(docker inspect layers-l1-nginx --format '{{.State.Running}}')" != "true" ]; then
  echo "layers-l1-nginx est arrêté. Relancez-le : docker start layers-l1-nginx"
  exit 1
fi
B=$(docker inspect layers-l1-dort --format '{{.State.ExitCode}}' 2>/dev/null)
if [ "$B" != "137" ]; then
  echo "Code attendu pour layers-l1-dort : 137. Trouvé : ${B:-aucun}. Pour reprendre : docker rm -f layers-l1-dort, puis la commande de la section."
  exit 1
fi
echo "nginx arrêté puis relancé, 137 pour sleep."
```

## Redémarrer tout seul

Une **politique de redémarrage** relance un conteneur selon la façon dont il s'est arrêté. `on-failure` ne le relance que s'il sort avec une erreur, c'est-à-dire un code différent de 0, et `:2` limite à deux tentatives. Ce conteneur plante aussitôt, avec le code 3 :

```exec
docker run -d --name layers-l1-plante --restart on-failure:2 alpine:3.22 sh -c 'echo boum; exit 3'
```

Attendez quelques secondes, le temps des deux relances, puis regardez. `docker logs` affiche ce que le conteneur a écrit :

```exec
sleep 5
docker inspect layers-l1-plante --format '{{.State.Status}}, code {{.State.ExitCode}}, {{.RestartCount}} redémarrages'
docker logs layers-l1-plante
```

Trois lignes `boum` : le premier essai et deux relances. Sur un serveur, on préfère souvent `unless-stopped`, qui relance aussi après un redémarrage de la machine, sauf si vous aviez arrêté le conteneur vous-même. Cette politique relance sans limite : un conteneur qui plante en boucle continuera de le faire, il vaut donc mieux le surveiller.

```verify
N=$(docker inspect layers-l1-plante --format '{{.RestartCount}}' 2>/dev/null)
if [ "$N" != "2" ]; then
  echo "layers-l1-plante compte ${N:-0} redémarrage(s), 2 attendus. Attendez un peu et réessayez."
  exit 1
fi
echo "Docker a relancé le conteneur deux fois, puis a abandonné."
```

Il reste à tout supprimer. `-f` fonctionne sur un conteneur qui tourne ou qui est en pause :

```exec
docker rm -f layers-l1-etapes layers-l1-nginx layers-l1-dort layers-l1-plante
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l1-(etapes|nginx|dort|plante)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker stop`](https://docs.docker.com/reference/cli/docker/container/stop/) · [`docker pause`](https://docs.docker.com/reference/cli/docker/container/pause/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/) · [Politiques de redémarrage](https://docs.docker.com/engine/containers/start-containers-automatically/)

## Questions

```quiz
title: "Le cycle de vie"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Lesquelles de ces affirmations sur `docker run` sont vraies ? (plusieurs réponses)"
    answers:
      - "Il revient à `docker create` suivi de `docker start`"
      - "Il télécharge toujours l'image, même si elle est déjà là"
      - "Deux `docker run` de la même image donnent deux conteneurs indépendants"
    correct: [1, 3]
    explanation: "`docker run` enchaîne la création et le démarrage. Docker ne télécharge l'image que si elle manque, et chaque conteneur a sa propre couche d'écriture."
  - prompt: "Un conteneur qui exécute `sleep 3600` s'arrête après `docker stop` avec le code 137. Pourquoi ?"
    answers:
      - "`docker stop` envoie toujours SIGKILL"
      - "`sleep` a ignoré la demande d'arrêt, et Docker l'a tué à la fin du délai"
      - "Le conteneur a manqué de mémoire"
    correct: 2
    explanation: "`docker stop` demande d'abord l'arrêt par un signal, puis envoie SIGKILL après le délai. 137 = 128 + 9."
  - prompt: "Quelle est la différence entre `docker pause` et `docker stop` ?"
    answers:
      - "Aucune, `pause` est l'ancien nom"
      - "`pause` fige les processus, qui restent en mémoire ; `stop` les termine"
      - "`pause` garde la couche d'écriture et `stop` la supprime"
    correct: 2
    explanation: "Un conteneur en pause reprend exactement là où il en était. Et `stop` ne supprime pas la couche d'écriture : seul `rm` le fait."
  - prompt: "À chaque arrêt, une application coupe les requêtes qu'elle traite. Qu'est-ce qui corrige cela le plus directement ?"
    answers:
      - "Utiliser `docker kill` au lieu de `docker stop`"
      - "Faire en sorte que l'application réagisse à la demande d'arrêt : finir ses requêtes, puis sortir"
      - "Augmenter la limite de mémoire"
    correct: 2
    explanation: "Le délai de `docker stop` ne sert que si le processus réagit au signal. Sinon, il est tué à la fin du délai."
  - prompt: "Après quelles commandes la couche d'écriture et les logs sont-ils encore là ? (plusieurs réponses)"
    answers:
      - "`docker stop`"
      - "`docker kill`"
      - "`docker rm`"
      - "`docker pause`"
    correct: [1, 2, 4]
    explanation: "Seul `docker rm` supprime le conteneur. C'est pour cela que `docker logs` marche sur un conteneur arrêté."
```
