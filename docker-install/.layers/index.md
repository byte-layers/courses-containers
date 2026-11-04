---
title: "Installer Docker et vérifier son poste"
description: "Pas à pas : installer Docker selon votre système, puis vérifier que le client, le moteur, Compose et le réseau répondent."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 30
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Vous allez mettre Docker en place sur votre poste, puis vérifier une à une les pièces dont tout le parcours aura besoin. À la fin, vous saurez que votre poste est prêt, et vous saurez lire ce qu'il répond quand il ne l'est pas.

**Niveau** : débutant. Il suffit de savoir ouvrir un terminal et d'y lancer une commande. Ce lab ne suppose aucune connaissance de Docker : chaque commande est expliquée quand elle arrive. Si vous ne savez pas encore à quoi servent les conteneurs, lisez d'abord « Pourquoi les conteneurs ».

**Ce qu'il faut** : un poste sur lequel vous avez le droit d'installer un logiciel, ou un poste hébergé fourni par votre formateur. Il faut aussi `curl`, une commande qui demande une page web depuis le terminal, et le port **28300** libre. Un **port** est le numéro auquel un service répond sur une machine.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Installer Docker

## Choisir selon votre système

L'installation dépend de votre système, et elle ne se fait qu'une fois. Ce cours ne peut donc pas la vérifier à votre place : il vous envoie vers la page officielle, toujours à jour, et les vérifications commencent à l'étape suivante. Trouvez votre cas dans ce tableau.

| Votre poste | Ce qu'il faut installer | La page à suivre |
|---|---|---|
| **Poste hébergé** (un VS Code dans le navigateur, fourni par votre formateur) | rien : Docker y est déjà installé et démarré | passez à l'étape suivante |
| **macOS** | Docker Desktop, en choisissant la version pour votre processeur : Apple Silicon ou Intel | [Installer sur Mac](https://docs.docker.com/desktop/setup/install/mac-install/) |
| **Windows** | WSL 2, le Linux intégré à Windows, puis Docker Desktop | [Installer sur Windows](https://docs.docker.com/desktop/setup/install/windows-install/) |
| **Linux** | Docker Engine, avec les paquets de votre distribution | [Installer Docker Engine](https://docs.docker.com/engine/install/), puis [les étapes après l'installation](https://docs.docker.com/engine/install/linux-postinstall/) |

Les conteneurs de ce parcours ont besoin d'un noyau Linux, la partie du système qui gère les programmes et la mémoire. C'est pourquoi macOS et Windows passent par Docker Desktop, qui démarre pour vous une petite machine virtuelle Linux, un ordinateur simulé par un logiciel. Linux, lui, n'a besoin que du moteur.

## Sur macOS et Windows

Une fois Docker Desktop installé, ouvrez-le comme n'importe quelle application et attendez qu'il indique que le moteur tourne. Il doit rester ouvert pendant que vous travaillez : quand il est fermé, le moteur est arrêté.

Sous Windows, les commandes de ce parcours sont écrites pour un terminal de type Linux, ce que PowerShell n'est pas : travaillez dans le terminal de WSL, qui s'ouvre avec la commande `wsl`.

Docker Desktop est gratuit pour un usage personnel, pour l'éducation et pour les petites entreprises. Dans une grande entreprise, il demande un abonnement : les conditions exactes sont sur la [page de la licence](https://docs.docker.com/subscription/desktop-license/).

## Sous Linux

La page de votre distribution vous fait ajouter le dépôt de paquets de Docker, c'est-à-dire la source où votre système va chercher ses logiciels, puis installer le moteur. Deux remarques vous éviteront des surprises :

- Le paquet `docker.io` de certaines distributions n'est pas celui de Docker, et peut être ancien. Suivez plutôt la page officielle.
- Après l'installation, seul l'administrateur peut utiliser Docker. Les étapes après l'installation expliquent comment ajouter votre utilisateur au groupe `docker`. Ce groupe donne des droits équivalents à ceux de l'administrateur : réservez-le à votre propre poste.

Quand l'installation est terminée, ou si vous êtes sur un poste hébergé, confirmez pour passer aux vérifications.

```ack
Docker est installé, ou je suis sur un poste hébergé
```

# Le client et le moteur

## Deux programmes, pas un

Docker se compose de deux programmes. Le **client** est la commande `docker` que vous tapez. Le **moteur**, aussi appelé serveur ou démon, tourne en tâche de fond : c'est lui qui crée et fait vivre les conteneurs. Le client ne fait que lui transmettre vos demandes. Demandez sa version à chacun :

```exec
docker version
```

La réponse a deux parties, `Client` et `Server`, et vous devez voir les deux. Elles n'ont pas forcément le même numéro : sur un poste hébergé, par exemple, le client est plus récent que le moteur, et ce n'est pas un problème, car un client sait parler à un moteur plus ancien.

Si la réponse se réduit à la partie `Client` et à une erreur, ou à une erreur seule, ce tableau dit ce qu'elle veut dire.

| Le message | Ce qu'il veut dire | Que faire |
|---|---|---|
| `Cannot connect to the Docker daemon` | le moteur ne répond pas | ouvrez Docker Desktop, lancez `sudo systemctl start docker` sous Linux, ou prévenez votre formateur sur un poste hébergé |
| `permission denied` | votre utilisateur n'a pas le droit de parler au moteur | ajoutez-le au groupe `docker` avec `sudo usermod -aG docker $USER`, puis rouvrez votre session |
| `command not found` | le client n'est pas installé ou pas trouvé | reprenez l'installation |

```verify
if ! command -v docker >/dev/null 2>&1; then
  echo "La commande docker est introuvable. Reprenez l'installation."
  exit 1
fi
if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo "Le client est là, mais le moteur ne répond pas. Lisez le tableau des messages de cette section."
  exit 1
fi
echo "Le client $(docker version --format '{{.Client.Version}}') parle au moteur $(docker version --format '{{.Server.Version}}')."
```

## Le client sans moteur

Pour bien voir que ce sont deux programmes, faites parler le client à un moteur qui n'existe pas. La variable `DOCKER_HOST` indique au client à quelle adresse trouver le moteur. La placer devant la commande ne la change que pour cette commande, et le port 1 n'héberge aucun moteur. `2>&1` envoie aussi les messages d'erreur vers la sortie normale, le signe `|` passe cette sortie à la commande suivante, et `tail -n 2` n'en garde que les 2 dernières lignes :

```exec
DOCKER_HOST=tcp://localhost:1 docker version 2>&1 | tail -n 2
```

Vous devez lire `Cannot connect to the Docker daemon at tcp://localhost:1`, précédé de la dernière ligne de la partie `Client`. Le client a donc répondu, seul le moteur manque. Quand vous verrez cette erreur plus tard, vous saurez où chercher.

Sur un poste hébergé, `DOCKER_HOST` est déjà réglée pour vous, et c'est elle qui relie votre terminal à son moteur. Ne la modifiez pas pour de bon.

```ack
Je sais distinguer le client du moteur
```

## Ce que le moteur dit de lui-même

`docker info` donne la fiche complète du moteur. Elle est longue : l'option `--format` n'en garde que ce que vous demandez, ici son système, son architecture, son nombre de processeurs et sa façon de stocker les images.

```exec
docker info --format 'Système : {{.OperatingSystem}}
Architecture : {{.Architecture}}
Processeurs : {{.NCPU}}
Stockage : {{.Driver}}'
```

Le système est celui du moteur, pas forcément le vôtre : sur un Mac, vous lirez `Docker Desktop`, car le moteur tourne dans sa machine virtuelle. L'**architecture** est la famille du processeur : `aarch64` ou `arm64` sur un Mac récent, `x86_64` ou `amd64` sur la plupart des PC. Une image doit exister pour votre architecture, et toutes celles de ce parcours existent pour les deux. Le **stockage**, appelé pilote de stockage, ne demande rien de votre part : `overlay2` ou `overlayfs` sont les réponses habituelles.

```verify
if ! docker info >/dev/null 2>&1; then
  echo "docker info ne répond pas. Le moteur est-il démarré ?"
  exit 1
fi
echo "Le moteur tourne sur $(docker info --format '{{.Architecture}}'), avec le stockage $(docker info --format '{{.Driver}}')."
```

# Compose

## Vérifier Compose

Compose est l'outil qui décrit une application de plusieurs conteneurs dans un fichier. Vous ne vous en servirez que plus tard dans ce parcours, mais autant savoir dès maintenant qu'il est là. Il est livré avec Docker Desktop, et s'installe avec le paquet `docker-compose-plugin` sous Linux. Demandez-lui sa version :

```exec
docker compose version
```

Vous devez lire `Docker Compose version` suivi d'un numéro. Si Docker répond `'compose' is not a docker command`, installez le paquet sous Linux, et notez que l'ancienne commande `docker-compose`, avec un tiret, n'est pas celle qu'utilise ce parcours.

```verify
if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose ne répond pas. Sous Linux, installez le paquet docker-compose-plugin."
  exit 1
fi
echo "$(docker compose version)"
```

# Un premier conteneur

## Télécharger et lancer

Le moteur répond, il reste à lui faire faire quelque chose. Cette commande vérifie d'un coup que le moteur sait télécharger une image et lancer un conteneur.

```exec
docker run --name layers-l0-hello alpine:3.22 echo "Docker fonctionne"
```

| Élément | Rôle |
|---|---|
| `docker run` | crée un conteneur depuis une image et le démarre |
| `--name layers-l0-hello` | lui donne un nom fixe, pour pouvoir le retrouver |
| `alpine:3.22` | l'image, ici Alpine, un Linux minimal, dans sa version `3.22` |
| `echo "Docker fonctionne"` | la commande que le conteneur exécute, puis il s'arrête |

Au premier lancement, Docker télécharge l'image depuis Docker Hub, puis vous lisez `Docker fonctionne`. Au lancement suivant, l'image sera déjà là. Si ce téléchargement échoue, c'est le réseau de votre poste ou la limite de Docker Hub qu'il faut regarder, pas votre installation.

Ne vous souciez pas du détail de `docker run` : un prochain cours l'explique. Ce qui compte ici, c'est que votre poste sait le faire.

```verify
if ! docker container inspect layers-l0-hello >/dev/null 2>&1; then
  echo "Le conteneur layers-l0-hello n'existe pas. Lancez la commande de cette section."
  exit 1
fi
if [ "$(docker container inspect layers-l0-hello --format '{{.State.ExitCode}}')" != "0" ]; then
  echo "Le conteneur s'est terminé en erreur. Lisez sa sortie : docker logs layers-l0-hello"
  exit 1
fi
if ! docker logs layers-l0-hello 2>&1 | grep -q 'Docker fonctionne'; then
  echo "Le conteneur n'a pas écrit la phrase attendue. Pour recommencer : docker rm layers-l0-hello, puis relancez la commande."
  exit 1
fi
echo "Votre poste sait télécharger une image et lancer un conteneur."
```

## Joindre un serveur

Reste une dernière pièce : le réseau. Beaucoup de cours de ce parcours lancent un serveur dans un conteneur et vont le lire depuis le terminal. Démarrez nginx, un serveur web. `-d` le fait tourner en arrière-plan pour vous rendre la main, et `-p 28300:80` relie le port 28300 de votre machine au port 80 du conteneur :

```exec
docker run -d --name layers-l0-web -p 28300:80 nginx:1.30-alpine
```

La longue suite de chiffres et de lettres qui s'affiche est l'identifiant du conteneur. Demandez-lui maintenant sa page. `curl` la télécharge, `-sS` masque sa barre de progression en gardant les erreurs, et `--retry` patiente le temps que le serveur démarre. `grep` ne garde que la ligne du titre, parmi celles que `|` lui passe :

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28300 | grep '<h1>'
```

Vous devez lire `<h1>Welcome to nginx!</h1>`. Une ligne qui commence par `curl:` à côté de ce titre, comme `curl: (56) Recv failure`, n'a rien de grave : le serveur n'était pas encore prêt, et `curl` a réessayé. Pour voir la page dans un navigateur, ouvrez `http://localhost:28300` sur votre poste. Sur un poste hébergé, utilisez plutôt l'onglet **PORTS** de VS Code, qui donne le lien de ce port.

Si le conteneur ne démarre pas et que Docker indique `port is already allocated`, un autre programme occupe ce port. Fermez-le, supprimez le conteneur avec `docker rm -f layers-l0-web`, puis relancez la commande.

```verify
if ! command -v curl >/dev/null 2>&1; then
  echo "curl n'est pas installé sur cette machine. Installez-le, car ce parcours s'en sert souvent."
  exit 1
fi
if [ "$(docker container inspect layers-l0-web --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le conteneur layers-l0-web ne tourne pas. Pour repartir de zéro : docker rm -f layers-l0-web, puis relancez la commande."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28300 | grep -q 'Welcome to nginx'; then
  echo "Le serveur ne répond pas sur le port 28300. Regardez ses ports avec : docker ps"
  exit 1
fi
echo "Le serveur répond sur le port 28300."
```

# Nettoyer

## Ne rien laisser

Votre poste est vérifié, et ces deux conteneurs ne servent plus. `docker rm -f` les supprime, même celui qui tourne encore :

```exec
docker rm -f layers-l0-hello layers-l0-web
```

Les images, elles, restent sur votre machine pour servir à nouveau. `docker system df` montre la place que Docker occupe sur le disque, ligne par ligne :

```exec
docker system df
```

Vous lisez une ligne pour les images, une pour les conteneurs, une pour les volumes et une pour le cache de construction, avec leur taille respective.

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l0-(hello|web)$')
if [ -n "$left" ]; then
  echo "Il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
echo "C'est propre, et votre poste est prêt."
```

## Récap

- Docker est un client, la commande `docker`, qui parle à un moteur qui tourne en tâche de fond.
- `docker version` montre les deux, et son message d'erreur dit lequel manque.
- Un poste prêt sait télécharger une image, lancer un conteneur et servir une page sur un port.

> 📖 [Installer Docker](https://docs.docker.com/get-started/get-docker/) · [`docker version`](https://docs.docker.com/reference/cli/docker/version/) · [`docker info`](https://docs.docker.com/reference/cli/docker/system/info/) · [`docker compose version`](https://docs.docker.com/reference/cli/docker/compose/version/)

Pour vous tester sans guide, faites le challenge « Auditer une installation Docker ».
