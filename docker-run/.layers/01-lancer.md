---
title: "Lancer un conteneur"
description: "docker run, docker ps, en arrière-plan, avec un nom, et entrer dans un conteneur avec un shell"
---

`docker run` crée un conteneur depuis une image et le démarre. Vous l'utilisez ici pour une commande brève, puis pour un service qui dure ; `docker ps` montre ce qui tourne, et `docker exec` vous fait entrer dans un conteneur.

## Vérifier que Docker répond

`docker ps` liste les conteneurs qui tournent. C'est la commande que vous taperez le plus souvent, et elle dit aussi que le moteur répond :

```exec
docker ps
```

Vous devez lire au moins cette ligne de titres, avec éventuellement d'autres conteneurs en dessous. Si vous lisez une erreur, le lab [Installer Docker et vérifier son poste](https://byte-layers.com/fr/labs/docker-install) en donne le sens.

```text
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

```verify
if ! docker info >/dev/null 2>&1; then
  echo "Docker ne répond pas. Démarrez-le, puis réessayez."
  exit 1
fi
echo "Docker répond."
```

## Un conteneur qui exécute une commande puis s'arrête

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

`alpine:3.22` désigne l'image `alpine`, un Linux minimal, en version `3.22` : ce qui suit `:` s'appelle le **tag**. Ce conteneur affiche le contenu d'un fichier de l'image. `--name` lui donne un nom, sinon Docker en invente un.

```exec
docker run --name layers-l1-first alpine:3.22 cat /etc/alpine-release
```

Si l'image n'est pas encore sur votre machine, Docker la télécharge d'abord depuis Docker Hub. La dernière ligne est ce que le conteneur a écrit :

```text
3.22.7
```

Le dernier chiffre peut être différent chez vous, car le tag `3.22` suit les correctifs de cette version. Le conteneur a démarré, lancé `cat`, affiché la version, et s'est arrêté. Il a tout de suite rendu la main, parce qu'**un conteneur tourne aussi longtemps que son processus principal**, le programme qu'il a lancé, ici `cat`.

```verify
if ! docker container inspect layers-l1-first >/dev/null 2>&1; then
  echo "layers-l1-first n'existe pas. Lancez la commande de cette section."
  exit 1
fi
echo "Le conteneur layers-l1-first existe, et il s'est arrêté."
```

## Un conteneur arrêté existe encore : docker ps -a

`docker ps` ne montre plus rien de ce conteneur, puisqu'il ne tourne plus. Pour voir aussi les conteneurs arrêtés, ajoutez `-a` :

```exec
docker ps -a
```

Vous y trouvez cette ligne, parmi vos éventuels autres conteneurs :

```text
CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS                      PORTS     NAMES
05e7be4c82ea   alpine:3.22   "cat /etc/alpine-rel…"   10 seconds ago   Exited (0) 9 seconds ago              layers-l1-first
```

`Exited (0)` veut dire qu'il s'est terminé, et que `0` est le code de sortie de sa commande : tout s'est bien passé. Arrêté n'est donc pas supprimé. Il reste sur le disque jusqu'à ce que vous le supprimiez avec `docker rm` :

```exec
docker rm layers-l1-first
```

Quand un conteneur ne sert qu'une fois, `--rm` le supprime tout seul à son arrêt, et plus rien ne reste à ranger. L'image, elle, reste sur votre machine pour la prochaine fois, ce que `docker images` vous montre :

```exec
docker run --rm alpine:3.22 cat /etc/alpine-release
docker images
```

```verify
if docker container inspect layers-l1-first >/dev/null 2>&1; then
  echo "layers-l1-first existe encore. Lancez docker rm layers-l1-first."
  exit 1
fi
echo "Le conteneur est supprimé."
```

## Un conteneur en arrière-plan, qui dure

Un service doit tourner sans bloquer votre terminal. C'est le rôle de `-d`, pour *detach*. La commande `sleep 3600`, qui attend une heure, tient ici lieu de service : elle garde le conteneur en vie.

```exec
docker run -d --name layers-l1-sleep alpine:3.22 sleep 3600
```

Docker affiche l'identifiant complet du conteneur et vous rend la main. Vérifiez qu'il tourne :

```exec
docker ps
```

Sa colonne `STATUS` commence par `Up`, et `CONTAINER ID` montre le début de l'identifiant affiché à l'instant.

```text
CONTAINER ID   IMAGE         COMMAND        CREATED         STATUS         PORTS     NAMES
ea829e7f8ca6   alpine:3.22   "sleep 3600"   5 seconds ago   Up 4 seconds             layers-l1-sleep
```

```verify
if [ "$(docker inspect layers-l1-sleep --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l1-sleep ne tourne pas. Supprimez-le s'il existe (docker rm -f layers-l1-sleep), puis lancez la commande de cette section."
  exit 1
fi
echo "layers-l1-sleep tourne en arrière-plan."
```

## Entrer dans un conteneur qui tourne : docker exec

`docker exec` lance une commande **dans** un conteneur déjà démarré, sans le recréer. Listez les processus qu'il contient :

```exec
docker exec layers-l1-sleep ps
```

Un **PID** est le numéro d'un processus. Votre `sleep 3600` est le PID 1 : c'est le processus principal du conteneur. L'autre ligne est le `ps` que vous venez de lancer.

```text
PID   USER     TIME  COMMAND
    1 root      0:00 sleep 3600
    7 root      0:00 ps
```

Pour enchaîner plusieurs commandes, on préfère ouvrir un **shell** dans le conteneur, le programme qui lit et exécute ce que vous tapez. Sur Alpine, il s'appelle `sh`, car `bash` n'y est pas installé. `-i` garde l'entrée ouverte pour transmettre ce que vous tapez, et `-t` fournit un terminal, d'où l'**invite** (le *prompt*), ce texte qui attend votre commande. On les écrit presque toujours ensemble :

```exec
docker exec -it layers-l1-sleep sh
```

Votre invite a changé, elle affiche `/ #` : vous êtes **dans** le conteneur. Tapez vous-même ces lignes. `hostname` affiche le nom de la machine vu du conteneur, et `exit` vous fait sortir :

```sh
ps
hostname
exit
```

De retour sur votre machine, regardez ce que devient le conteneur :

```exec
docker ps
```

`layers-l1-sleep` tourne toujours : vous avez quitté le shell ajouté par `docker exec`, mais le processus principal, lui, n'a pas bougé. `docker exec` ne marche d'ailleurs que sur un conteneur qui tourne : sur un conteneur arrêté, Docker répond `is not running`.

```ack
Je suis entré dans le conteneur, et il tourne toujours
```

## Lancer un conteneur directement dans un shell

`-it` s'utilise aussi avec `docker run`. Cette fois, le shell **est** le processus principal du conteneur :

```exec
docker run -it --name layers-l1-shell alpine:3.22 sh
```

Vous êtes de nouveau devant `/ #`. Tapez ces deux lignes, pour créer un fichier puis sortir. Le signe `>` envoie dans un fichier ce qui se serait affiché, et vous êtes ici l'administrateur du conteneur, d'où le dossier `/root` :

```sh
echo bonjour > /root/note.txt
exit
```

Quitter ce shell termine le processus principal, donc le conteneur s'arrête. Il n'est pas supprimé pour autant : le fichier reste dans sa **couche d'écriture**, l'espace où chaque conteneur garde ses propres modifications, au-dessus de l'image. `docker diff` liste ce qu'elle contient, où `A` veut dire *added* et `C` veut dire *changed* :

```exec
docker diff layers-l1-shell
```

Votre fichier y est, à côté de l'historique que le shell a écrit lui-même :

```text
C /root
A /root/.ash_history
A /root/note.txt
```

```verify
C=layers-l1-shell
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "$C n'existe pas. Lancez la commande de cette section."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Config.Tty}}{{.Config.OpenStdin}}')" != "truetrue" ]; then
  echo "$C n'a pas de terminal. Supprimez-le (docker rm -f $C) et relancez avec -it."
  exit 1
fi
if ! docker cp "$C:/root/note.txt" - 2>/dev/null | tar -xO 2>/dev/null | grep -q bonjour; then
  echo "/root/note.txt n'est pas dans $C. docker start -ai $C redémarre le conteneur (-a affiche sa sortie, -i transmet ce que vous tapez) et vous y ramène."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Status}}')" != "exited" ]; then
  echo "$C tourne encore : quittez son shell avec exit."
  exit 1
fi
echo "Le fichier est bien dans la couche d'écriture de $C."
```

## Nom déjà pris : le conteneur arrêté garde son nom

Vous rencontrerez tôt ou tard cette erreur. Lancez un conteneur avec le nom de celui que vous venez de quitter :

```exec
docker run -d --name layers-l1-shell alpine:3.22 sleep 3600
```

Docker refuse, parce que ce nom est déjà pris :

```text
docker: Error response from daemon: Conflict. The container name "/layers-l1-shell" is already in use by container "e068f2da171b…".
```

`docker ps` ne le montrerait pas, mais `docker ps -a` le montre, arrêté : il garde son nom tant qu'il n'est pas supprimé. Supprimez ce que vous avez créé. `-f` force la suppression d'un conteneur qui tourne, ce qui est le cas de `layers-l1-sleep` :

```exec
docker rm -f layers-l1-sleep layers-l1-shell
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l1-(sleep|shell)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/) · [`docker ps`](https://docs.docker.com/reference/cli/docker/container/ls/) · [`docker exec`](https://docs.docker.com/reference/cli/docker/container/exec/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/)

## Questions sur le lancement

```quiz
title: "Lancer un conteneur"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`docker run -d --name attente alpine:3.22 sleep 600` rend la main et affiche une longue suite de chiffres et de lettres. Qu'est-ce que c'est ?"
    answers:
      - "L'empreinte de l'image"
      - "L'identifiant complet du conteneur, dont `docker ps` montre le début"
      - "Le numéro de processus de sleep sur l'hôte"
      - "L'adresse IP du conteneur"
    correct: 2
    explanation: "`-d` affiche l'identifiant complet du conteneur. L'identifiant court de `docker ps` en est le début."
  - prompt: "Vous obtenez « The container name /api is already in use », mais `docker ps` n'affiche rien. Que s'est-il passé ?"
    answers:
      - "Le daemon Docker doit être redémarré"
      - "Un conteneur arrêté existe encore et garde ce nom : `docker ps` ne liste que ceux qui tournent"
      - "Un nom reste réservé dix minutes après l'arrêt"
    correct: 2
    explanation: "Arrêter ne supprime pas. Le conteneur garde son nom et sa couche d'écriture jusqu'au `docker rm`. `docker ps -a` le montre."
  - prompt: "Vous quittez un shell ouvert avec `docker exec -it`. Que devient le conteneur ?"
    answers:
      - "Il s'arrête, comme après `docker run -it`"
      - "Il continue de tourner : le shell n'était pas son processus principal"
      - "Il est supprimé"
    correct: 2
    explanation: "Un conteneur tourne aussi longtemps que son processus principal. Avec `docker run -it ... sh`, le shell est ce processus ; avec `docker exec -it`, il s'y ajoute."
  - prompt: "Que fait `--rm` ?"
    answers:
      - "Il supprime l'image à l'arrêt du conteneur"
      - "Il supprime le conteneur à son arrêt, avec sa couche d'écriture"
      - "Il empêche le conteneur d'écrire sur le disque"
    correct: 2
    explanation: "L'image, elle, reste en place : seul le conteneur disparaît."
```
