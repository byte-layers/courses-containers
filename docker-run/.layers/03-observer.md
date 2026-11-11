---
title: "Observer un conteneur"
description: "ps, logs, top, stats et inspect : savoir ce qu'un conteneur fait et comment il est configuré"
---

Face à un conteneur, on se pose toujours les mêmes questions : est-il en marche, qu'a-t-il écrit, comment est-il configuré ? Chacune a sa commande, que vous essayez ici sur un serveur web.

## Est-il en marche ? La colonne STATUS de docker ps

Lancez nginx avec la forme vue à l'étape précédente, sur le port 28082. Si ce port est déjà pris, Docker affiche `port is already allocated` : `docker ps` montre si un de vos conteneurs l'occupe, et sinon, fermez le programme concerné.

```exec
docker run -d --name layers-l1-obs -p 28082:80 nginx:1.30-alpine
```

Première question : est-il en marche ?

```exec
docker ps
```

La colonne `STATUS` répond. Voici ce que vous pouvez y lire, les deux dernières lignes n'apparaissant qu'avec `docker ps -a` :

| `STATUS` | Ce que ça veut dire |
|---|---|
| `Up 3 minutes` | il tourne |
| `Restarting (1) 5 seconds ago` | il plante en boucle, et Docker le relance, si on le lui a demandé à son lancement |
| `Exited (1) 2 minutes ago` | il est arrêté, et ce code de sortie donne le premier indice |
| `Created` | il existe, mais il n'a pas démarré, souvent à cause d'un port déjà pris |

```verify
if [ "$(docker inspect layers-l1-obs --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l1-obs ne tourne pas. Supprimez-le s'il existe (docker rm -f layers-l1-obs), puis lancez la commande du début de l'étape."
  exit 1
fi
if [ "$(docker port layers-l1-obs 80 2>/dev/null | head -1 | sed 's/.*://')" != "28082" ]; then
  echo "layers-l1-obs ne publie pas le port 28082. Supprimez-le (docker rm -f layers-l1-obs), vérifiez que le port est libre, puis relancez la commande."
  exit 1
fi
echo "layers-l1-obs tourne, sur le port 28082."
```

## Qu'a-t-il écrit ? docker logs

Docker enregistre ce que le processus principal écrit sur sa **sortie standard** (stdout) et sa **sortie d'erreur** (stderr). nginx y note chaque demande reçue, qu'on appelle une **requête**. Envoyez-lui une requête reconnaissable :

```exec
curl "http://localhost:28082/?moi=1"
```

Puis lisez ce qu'il a écrit. `--tail 2` ne garde que les deux dernières lignes :

```exec
docker logs --tail 2 layers-l1-obs
```

Votre requête y figure. L'adresse au début et la date dépendent de votre poste.

```text
172.17.0.1 - - [04/Nov/2026:22:25:20 +0000] "GET /?moi=1 HTTP/1.1" 200 896 "-" "curl/8.7.1" "-"
```

Ces options de `docker logs` servent au quotidien :

| Option | Effet |
|---|---|
| `--tail N` | les N dernières lignes seulement |
| `-f` | suit les nouvelles lignes en direct, jusqu'à `Ctrl-C` |
| `-t` | ajoute l'heure |

Retenez `-f`, celui qu'on utilise pour suivre un service en direct : ici il veut dire « suivre », alors qu'avec `docker rm` il veut dire « forcer ». Une application qui écrit ses logs dans un fichier, à l'intérieur du conteneur, reste invisible pour `docker logs`. Et les logs disparaissent avec le conteneur : ne mettez pas `--rm` si vous voulez les relire après son arrêt.

Pour garder ces logs, par exemple pour les transmettre à un collègue, envoyez-les dans un fichier. `~` désigne votre dossier personnel, `mkdir -p` y crée le dossier au besoin, et `>` envoie la réponse dans le fichier, dont il remplace le contenu s'il existe déjà :

```exec
mkdir -p ~/byte-layers/docker/l1
docker logs layers-l1-obs > ~/byte-layers/docker/l1/obs.txt
```

`cat` affiche ce fichier, pour vérifier qu'il contient bien votre requête :

```exec
cat ~/byte-layers/docker/l1/obs.txt
```

```verify
if ! docker logs layers-l1-obs 2>/dev/null | grep -q 'moi=1'; then
  echo "Votre requête n'est pas dans les logs. Relancez le curl."
  exit 1
fi
if ! grep -q 'moi=1' ~/byte-layers/docker/l1/obs.txt 2>/dev/null; then
  echo "~/byte-layers/docker/l1/obs.txt ne contient pas votre requête. Relancez la redirection."
  exit 1
fi
echo "Votre requête est dans les logs, et dans votre fichier."
```

## Quels processus, quelles ressources ? docker top et docker stats

`docker top` liste les processus du conteneur, avec les numéros vus de la machine qui l'héberge, soit la machine virtuelle de Docker Desktop sur macOS et Windows :

```exec
docker top layers-l1-obs
```

`docker exec ... ps` les liste vus de l'intérieur, comme à la première étape :

```exec
docker exec layers-l1-obs ps
```

Ce sont les mêmes processus, avec d'autres numéros : le conteneur a sa propre numérotation, et son processus principal y est le PID 1. Voici le début de ces deux réponses. nginx lance en plus des processus `worker`, dont le nombre dépend de votre machine.

```text
UID      PID       PPID      C    STIME   TTY   TIME       CMD
root     3420334   3420311   0    22:25   ?     00:00:00   nginx: master process nginx -g daemon off;

PID   USER     TIME  COMMAND
    1 root      0:00 nginx: master process nginx -g daemon off;
```

Pour la mémoire et le processeur, vous connaissez déjà `docker stats` :

```exec
docker stats --no-stream layers-l1-obs
```

```ack
Je sais voir les processus et la consommation
```

## Comment est-il configuré ? docker inspect

`docker inspect` donne toute la fiche d'un conteneur, en JSON, un format texte de champs imbriqués : près de 250 lignes. Le signe `|` passe cette réponse à `head -20`, qui n'en garde que le début :

```exec
docker inspect layers-l1-obs | head -20
```

On extrait une valeur avec `--format`, en suivant le chemin du champ : le champ `Status`, rangé dans `State`, s'écrit `.State.Status`. Cette option revient souvent dans les commandes de Docker, et les accolades doubles en font partie.

```exec
docker inspect layers-l1-obs --format '{{.State.Status}}'
docker inspect layers-l1-obs --format '{{json .Config.Cmd}}'
docker inspect layers-l1-obs --format '{{.Image}}'
```

Dans l'ordre, vous lisez son état, sa commande de démarrage et l'identifiant de son image. `json` affiche une liste lisible, plutôt que le format interne de Docker. Pour lire plusieurs champs d'un coup, mettez-les dans le même `--format`, séparés par un espace.

```text
running
["nginx","-g","daemon off;"]
sha256:0e52bd054126cdc040b1276c0af347aeb02a41b9cfe305d6094767ac30e97949
```

Il reste à ranger le conteneur et le dossier. `rm -r` supprime un dossier et son contenu :

```exec
docker rm -f layers-l1-obs
rm -r ~/byte-layers/docker/l1
```

```verify
if docker container inspect layers-l1-obs >/dev/null 2>&1 || [ -e ~/byte-layers/docker/l1 ]; then
  echo "Il reste le conteneur ou le dossier. Lancez les commandes ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker logs`](https://docs.docker.com/reference/cli/docker/container/logs/) · [`docker top`](https://docs.docker.com/reference/cli/docker/container/top/) · [`docker stats`](https://docs.docker.com/reference/cli/docker/container/stats/) · [`docker inspect`](https://docs.docker.com/reference/cli/docker/inspect/)

## Questions sur l'observation

```quiz
title: "Observer un conteneur"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Une application écrit ses logs dans `/var/log/app.log`, et `docker logs` n'affiche rien. Quelle est la bonne correction ?"
    answers:
      - "Lancer `docker logs --tail 1000`"
      - "Faire écrire l'application sur stdout et stderr, ce que Docker capture"
      - "Activer une option du daemon"
    correct: 2
    explanation: "Docker ne capture que stdout et stderr du processus principal."
  - prompt: "`docker ps` n'affiche rien, mais `docker ps -a` liste huit conteneurs. Qu'est-ce que cela veut dire ?"
    answers:
      - "Le daemon Docker dysfonctionne"
      - "Huit conteneurs sont arrêtés, et ils occupent encore le disque"
      - "Les huit conteneurs tournent, mais un filtre les cache"
    correct: 2
    explanation: "Sans `-a`, `docker ps` ne montre que ce qui tourne. Les conteneurs arrêtés gardent leur couche d'écriture et leurs logs."
  - prompt: "Pourquoi `docker top` montre-t-il un processus avec le PID 4821, alors que `docker exec ... ps` le montre avec le PID 1 ?"
    answers:
      - "Ce sont deux processus différents"
      - "Le conteneur a sa propre numérotation des processus"
      - "`docker top` se trompe"
    correct: 2
    explanation: "C'est le même processus, vu de deux endroits. Dans le conteneur, le processus principal est le PID 1."
  - prompt: "Le statut d'un conteneur affiche `Restarting (1) 5 seconds ago`. Que se passe-t-il ?"
    answers:
      - "Il est mis à jour vers une nouvelle image"
      - "Son processus sort avec le code 1, et Docker le relance en boucle"
      - "Il est en pause"
    correct: 2
    explanation: "C'est une boucle de plantage. Commencez par lire `docker logs` pour savoir pourquoi il sort."
```
