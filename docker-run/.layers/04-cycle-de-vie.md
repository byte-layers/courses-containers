---
title: "Le cycle de vie"
description: "Arrêter, relancer, redémarrer, supprimer : les états d'un conteneur et ce qui les fait changer"
---

Vous l'avez vu à la première étape : un conteneur arrêté existe encore, et il garde son nom. Il passe donc par plusieurs états, et quelques commandes le font passer de l'un à l'autre.

## Les états d'un conteneur

Un conteneur est toujours dans un seul état, et ce schéma montre ce qui le fait passer de l'un à l'autre.

```
 created ── docker start ──► running ── stop, kill, fin du processus ──► exited ── docker rm ──► supprimé
                                ▲                                           │
                                └─────────────── docker start ──────────────┘
```

`docker run` enchaîne `docker create`, qui donne l'état `created`, et `docker start` : on utilise donc rarement `create` seul. Deux états s'ajoutent à ce schéma. `restarting` est celui d'un conteneur que Docker relance après un arrêt, comme vous le verrez à la fin de cette étape. `paused` est celui d'un conteneur figé par `docker pause`, repris par `docker unpause`, un geste qu'on croise rarement au quotidien.

## Arrêter, relancer et redémarrer un serveur

Lancez nginx, puis arrêtez-le avec `docker stop` :

```exec
docker run -d --name layers-l1-nginx -p 28082:80 nginx:1.30-alpine
docker stop layers-l1-nginx
```

Il a disparu de `docker ps`, mais `-a` le retrouve :

```exec
docker ps -a
```

Sa ligne indique `Exited (0)`, parce que nginx a accepté de s'arrêter et a terminé proprement. `docker start` relance **le même conteneur**, avec son nom, sa configuration et sa couche d'écriture :

```exec
docker start layers-l1-nginx
```

`docker restart` enchaîne les deux, l'arrêt puis le démarrage. C'est le geste courant quand un service ne répond plus, ou quand il doit relire sa configuration :

```exec
docker restart layers-l1-nginx
```

Regardez l'état, puis vérifiez qu'il répond. Sa colonne `STATUS` indique `Up` depuis quelques secondes, alors que `CREATED` est plus ancien et que `CONTAINER ID` n'a pas changé : c'est bien le même conteneur.

```exec
docker ps
```

La dernière vérification est la page elle-même. Si `curl` répond par une erreur, attendez une seconde et relancez.

```exec
curl http://localhost:28082
```

```verify
FIN=$(docker inspect layers-l1-nginx --format '{{.State.FinishedAt}}' 2>/dev/null)
case "$FIN" in
  ""|0001-01-01*) echo "layers-l1-nginx n'a pas encore été arrêté. Faites le docker stop."; exit 1 ;;
esac
if [ "$(docker inspect layers-l1-nginx --format '{{.State.Running}}')" != "true" ]; then
  echo "layers-l1-nginx est arrêté. Relancez-le : docker start layers-l1-nginx"
  exit 1
fi
echo "layers-l1-nginx a été arrêté, et il tourne de nouveau."
```

## Ce que fait docker stop : prévenir, attendre, tuer

Arrêter un conteneur se passe en trois temps. Le système communique avec un processus par des **signaux**, de courts messages :

1. **Prévenir.** `docker stop` envoie au processus principal un signal qui lui demande de s'arrêter : `SIGTERM` par défaut, ou celui que l'image a choisi, `SIGQUIT` pour nginx.
2. **Attendre.** Le processus a 10 secondes pour finir ce qu'il fait et sortir.
3. **Tuer.** Passé ce délai, Docker envoie `SIGKILL`, le signal numéro 9, qu'on ne peut pas ignorer.

nginx a réagi à ce signal : il s'est arrêté aussitôt, avec le code `0`. Essayez avec `sleep`. Le PID 1 d'un conteneur ne reçoit un signal que s'il a prévu d'y réagir, et `sleep` n'a rien prévu. **La commande `docker stop` va donc rester muette pendant 10 secondes**, c'est normal.

```exec
docker run -d --name layers-l1-dort alpine:3.22 sleep 3600
docker stop layers-l1-dort
```

Lisez son code de sortie, avec la forme de `docker inspect` vue à l'étape précédente :

```exec
docker inspect layers-l1-dort --format 'code de sortie : {{.State.ExitCode}}'
```

Le code est `137`. Au-dessus de 128, un code veut dire « arrêté par le signal numéro code - 128 » : ici 137 - 128 = 9, donc `SIGKILL`. Une application qui ne réagit pas à la demande est donc coupée net, et perd ce qu'elle était en train de traiter. `docker kill` envoie directement ce signal, sans le délai : il se réserve aux cas où `docker stop` n'aboutit pas.

```verify
B=$(docker inspect layers-l1-dort --format '{{.State.ExitCode}}' 2>/dev/null)
if [ "$B" != "137" ]; then
  echo "Code attendu pour layers-l1-dort : 137. Trouvé : ${B:-aucun}. Pour reprendre : docker rm -f layers-l1-dort, puis la commande de la section."
  exit 1
fi
echo "137 pour sleep : Docker a dû le tuer."
```

## Relancer un conteneur tout seul : les politiques de redémarrage

Un serveur qui plante la nuit doit repartir sans vous. Une **politique de redémarrage**, donnée à `docker run` par `--restart`, décide de ce que fait Docker quand le conteneur s'arrête. Il en existe quatre.

| Politique | Docker relance le conteneur… |
|---|---|
| `no` | jamais : c'est le comportement par défaut |
| `on-failure[:N]` | s'il sort avec une erreur, un code différent de 0, au plus N fois si `:N` est donné |
| `always` | toujours, y compris au redémarrage du moteur |
| `unless-stopped` | toujours aussi, sauf si vous l'aviez arrêté vous-même |

Essayez `on-failure` avec deux tentatives, sur un conteneur qui plante aussitôt. `sh -c` fait exécuter la phrase entre apostrophes par un shell, et `exit 3` le termine avec le code 3 :

```exec
docker run -d --name layers-l1-plante --restart on-failure:2 alpine:3.22 sh -c 'echo boum; exit 3'
```

Attendez quelques secondes, le temps des deux relances, puis regardez son état et ce qu'il a écrit :

```exec
sleep 5
docker inspect layers-l1-plante --format '{{.State.Status}}, code {{.State.ExitCode}}, {{.RestartCount}} redémarrages'
docker logs layers-l1-plante
```

Les trois lignes `boum` correspondent au premier essai et aux deux relances :

```text
exited, code 3, 2 redémarrages
boum
boum
boum
```

Sur un serveur, on préfère souvent `unless-stopped`. Cette politique relance sans limite : un conteneur qui plante en boucle continuera de le faire, il vaut donc mieux le surveiller.

```verify
N=$(docker inspect layers-l1-plante --format '{{.RestartCount}}' 2>/dev/null)
if [ "$N" != "2" ]; then
  echo "layers-l1-plante compte ${N:-0} redémarrage(s), 2 attendus. Attendez un peu et réessayez."
  exit 1
fi
echo "Docker a relancé le conteneur deux fois, puis a abandonné."
```

Il reste à tout supprimer :

```exec
docker rm -f layers-l1-nginx layers-l1-dort layers-l1-plante
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l1-(nginx|dort|plante)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker stop`](https://docs.docker.com/reference/cli/docker/container/stop/) · [`docker restart`](https://docs.docker.com/reference/cli/docker/container/restart/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/) · [Politiques de redémarrage](https://docs.docker.com/engine/containers/start-containers-automatically/)

## Récap

- `docker run` lance un conteneur, `docker ps` montre s'il tourne, et il tourne aussi longtemps que son processus principal.
- Les options viennent avant l'image, la commande après ; `-p machine:conteneur` publie un port.
- `docker exec -it` ouvre un shell dans un conteneur qui tourne.
- `docker logs`, `top`, `stats` et `inspect` disent ce qu'un conteneur fait et comment il est configuré.
- `stop` prévient puis tue, `start` relance, `restart` enchaîne les deux, `rm` supprime : seul `rm` efface la couche d'écriture et les logs.

## Questions sur le cycle de vie

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
      - "`sleep` n'a pas réagi à la demande d'arrêt, et Docker l'a tué à la fin du délai"
      - "Le conteneur a manqué de mémoire"
    correct: 2
    explanation: "`docker stop` demande d'abord l'arrêt par un signal, puis envoie SIGKILL après le délai. 137 = 128 + 9."
  - prompt: "Que fait `docker restart` sur un conteneur qui contient un fichier que vous avez créé ?"
    answers:
      - "Il recrée le conteneur depuis l'image, et le fichier disparaît"
      - "Il arrête puis redémarre le même conteneur, et le fichier reste"
      - "Il met à jour l'image du conteneur"
    correct: 2
    explanation: "Le conteneur reste le même : seul le processus repart. Seul `docker rm` efface la couche d'écriture."
  - prompt: "À chaque arrêt, une application coupe les demandes qu'elle traite. Qu'est-ce qui corrige cela le plus directement ?"
    answers:
      - "Utiliser `docker kill` au lieu de `docker stop`"
      - "Faire en sorte que l'application réagisse à la demande d'arrêt : finir son travail, puis sortir"
      - "Augmenter la limite de mémoire"
    correct: 2
    explanation: "Le délai de `docker stop` ne sert que si le processus réagit au signal. Sinon, il est tué à la fin du délai."
  - prompt: "Après quelles commandes la couche d'écriture et les logs sont-ils encore là ? (plusieurs réponses)"
    answers:
      - "`docker stop`"
      - "`docker restart`"
      - "`docker rm`"
    correct: [1, 2]
    explanation: "Seul `docker rm` supprime le conteneur. C'est pour cela que `docker logs` marche sur un conteneur arrêté."
```

Pour mettre tout cela en pratique, faites le lab [Héberger une page dans un conteneur](https://byte-layers.com/fr/labs/docker-first-web-page).
