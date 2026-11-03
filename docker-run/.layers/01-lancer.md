---
title: "Lancer un conteneur"
description: "docker run, au premier plan, en arrière-plan, avec un nom, avec un shell"
---

Un **conteneur** est un programme lancé à partir d'une image, isolé du reste de votre machine, que l'on appelle l'**hôte**. Cette étape vous montre les quatre façons de le lancer, et pourquoi chacune existe.

## Vérifier que Docker répond

Commencez par demander sa version à Docker. Il se compose de deux parties : la commande `docker` que vous tapez, et un moteur qui tourne en tâche de fond, appelé **serveur** ou **démon**.

```exec
docker version --format '{{.Server.Version}}'
```

`--format` choisit ce qu'une commande affiche, ici la version du moteur. Vous en verrez le détail à l'étape 4.

Vous devez lire un numéro de version. `Cannot connect to the Docker daemon` veut dire que Docker n'est pas démarré : ouvrez Docker Desktop, ou lancez `sudo systemctl start docker` sous Linux. `permission denied` veut dire que votre utilisateur n'a pas le droit d'utiliser Docker : ajoutez-le au groupe `docker` avec `sudo usermod -aG docker $USER`, puis rouvrez votre session. Ce groupe donne des droits équivalents à l'administrateur de la machine : réservez-le à votre propre poste.

```verify
if ! docker info >/dev/null 2>&1; then
  echo "Docker ne répond pas. Démarrez-le, puis réessayez."
  exit 1
fi
echo "Docker répond."
```

## Une commande, et c'est fini

Une **image** contient les fichiers et la configuration d'un logiciel. `alpine:3.22` désigne l'image `alpine`, un Linux minimal, en version `3.22` : ce qui suit `:` s'appelle le **tag**.

`docker run` crée un conteneur depuis une image et le démarre. Si l'image n'est pas encore sur votre machine, Docker la télécharge d'abord.

```exec
docker run --rm alpine:3.22 cat /etc/alpine-release
```

Le conteneur a démarré, lancé `cat`, affiché la version, et s'est arrêté : **il vit aussi longtemps que son processus principal**.
`--rm` le supprime à l'arrêt, sinon il resterait sur le disque.

Le processus principal est le programme que le conteneur a lancé, ici `cat`. Quand il s'arrête, le conteneur s'arrête.

```verify
if ! docker image inspect alpine:3.22 >/dev/null 2>&1; then
  echo "L'image alpine:3.22 n'est pas là. Lancez la commande ci-dessus."
  exit 1
fi
echo "L'image alpine:3.22 est sur votre machine."
```

## En arrière-plan, avec un nom

Un service doit tourner sans bloquer votre terminal. C'est le rôle de `-d`, *detach*. Et `--name` lui donne un nom fixe, sinon
Docker en invente un.

```exec
docker run -d --name layers-l1-sleep alpine:3.22 sleep 3600
```

Docker affiche l'identifiant complet du conteneur et vous rend la main. Voyez ce qui tourne ; `docker ps` n'affiche que le début de cet identifiant. `--filter` limite la liste aux noms qui contiennent ce texte :

```exec
docker ps --filter name=layers-l1
```

```verify
if [ "$(docker inspect layers-l1-sleep --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l1-sleep ne tourne pas. Supprimez-le s'il existe (docker rm -f layers-l1-sleep), puis lancez la commande de cette section."
  exit 1
fi
echo "layers-l1-sleep tourne en arrière-plan."
```

## Agir dans un conteneur qui tourne

`docker exec` lance une commande **dans** un conteneur déjà démarré, sans le recréer. Listez les processus qu'il contient :

```exec
docker exec layers-l1-sleep ps
```

Un **PID** est le numéro d'un processus. Votre `sleep 3600` est le PID 1 : c'est le processus principal du conteneur. L'autre ligne est le `ps` que vous venez de lancer.

```ack
Je vois sleep en PID 1
```

## Un shell dans un conteneur

Pour travailler dans un conteneur, il faut un terminal. `-i` garde l'entrée ouverte et `-t` alloue un terminal. On les écrit
presque toujours ensemble.

```exec
docker run -it --name layers-l1-shell alpine:3.22 sh
```

Votre invite a changé, elle affiche `/ #` : vous êtes **dans** le conteneur. Tapez vous-même ces deux lignes, pour créer un fichier puis sortir. Ici, vous êtes l'administrateur du conteneur, d'où le dossier `/root` :

```sh
echo bonjour > /root/note.txt
exit
```

Quand vous quittez le shell, le processus principal se termine, donc le conteneur s'arrête. Il n'est pas supprimé pour autant : le
fichier reste dans sa **couche d'écriture**, l'espace où chaque conteneur garde ses propres modifications, au-dessus de l'image.

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

## L'erreur qu'on rencontre tous

Lancez un conteneur avec le même nom :

```exec
docker run -d --name layers-l1-shell alpine:3.22 sleep 3600
```

Erreur : `Conflict. The container name ... is already in use`. Pourtant, `docker ps` ne le montre pas :

```exec
docker ps --filter name=layers-l1-shell
```

C'est que `docker ps` ne liste que les conteneurs **en cours d'exécution**. Ajoutez `-a` :

```exec
docker ps -a --filter name=layers-l1-shell
```

Il est là, arrêté, et il garde son nom tant qu'il n'est pas supprimé. Supprimez ce que vous avez créé. `-f` force la suppression d'un
conteneur qui tourne :

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

> 📖 [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/) · [`docker exec`](https://docs.docker.com/reference/cli/docker/container/exec/) · [`docker ps`](https://docs.docker.com/reference/cli/docker/container/ls/) · [Droits après l'installation sous Linux](https://docs.docker.com/engine/install/linux-postinstall/)

## Questions

```quiz
title: "Lancer un conteneur"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`docker run -d --name attente alpine:3.22 sleep 600` rend la main et affiche une longue suite hexadécimale. Qu'est-ce que c'est ?"
    answers:
      - "L'empreinte de l'image"
      - "L'identifiant complet du conteneur, dont `docker ps` montre les 12 premiers caractères"
      - "Le numéro de processus de sleep sur l'hôte"
      - "L'adresse IP du conteneur"
    correct: 2
    explanation: "`-d` affiche l'identifiant complet du conteneur. L'identifiant court de `docker ps` en est le début, et les deux s'utilisent partout où l'on désigne un conteneur."
  - prompt: "Vous obtenez « The container name /api is already in use », mais `docker ps` n'affiche rien. Que s'est-il passé ?"
    answers:
      - "Le démon Docker doit être redémarré"
      - "Un conteneur arrêté existe encore et garde ce nom : `docker ps` ne liste que ceux qui tournent"
      - "Un nom reste réservé dix minutes après l'arrêt"
    correct: 2
    explanation: "Arrêter ne supprime pas. Le conteneur garde son nom, sa couche d'écriture et ses logs jusqu'au `docker rm`. `docker ps -a` le montre."
  - prompt: "Vous voulez un shell dans un conteneur. Quelles options vous faut-il ?"
    answers:
      - "`-d`"
      - "`-i` seul"
      - "`-it`"
      - "`-t` seul"
    correct: 3
    explanation: "`-i` transmet ce que vous tapez, `-t` fournit le terminal : l'invite et l'édition de ligne. Un shell a besoin des deux."
  - prompt: "Que fait `--rm` ?"
    answers:
      - "Il supprime l'image à l'arrêt du conteneur"
      - "Il supprime le conteneur à son arrêt, avec sa couche d'écriture"
      - "Il empêche le conteneur d'écrire sur le disque"
    correct: 2
    explanation: "L'image, elle, reste en place : seul le conteneur disparaît."
```
