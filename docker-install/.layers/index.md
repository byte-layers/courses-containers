---
title: "Installer Docker et vérifier son poste"
description: "Choisir un mode d'installation, comprendre ce qu'on installe, puis vérifier que le client et le moteur répondent et qu'un conteneur tourne."
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

Vous allez mettre Docker en place sur votre poste, comprendre ce que vous avez installé, puis vérifier que tout répond. À la fin, votre poste est prêt, et vous savez lire ses messages d'erreur.

**Niveau** : débutant. Il suffit de savoir ouvrir un terminal et d'y lancer une commande. Chaque commande est expliquée quand elle arrive.

**Prérequis** : savoir ce qu'est un conteneur, ce que dit [Pourquoi les conteneurs](https://byte-layers.com/fr/bits/containers-why).

**Ce qu'il faut** : un poste sur lequel vous avez le droit d'installer un logiciel, ou un poste hébergé fourni par votre formateur, c'est-à-dire un VS Code ouvert dans votre navigateur. Il faut aussi `curl`, une commande qui demande une page web depuis le terminal, et le port **28300** libre. Un **port** est le numéro auquel un service répond sur une machine.

# Choisir un mode d'installation

## Trois modes d'installation, selon ce que vous voulez

La première question n'est pas votre système, mais la façon d'installer. Docker s'installe de trois façons, et votre système dit seulement lesquelles vous sont ouvertes. Sur un poste hébergé, il n'y a rien à choisir : Docker y est déjà installé et démarré.

| Mode | Ce que vous obtenez | Systèmes | Ce qui peut bloquer |
|---|---|---|---|
| **Installateur** : Docker Desktop | une application clé en main, avec une interface graphique | macOS, Windows, Linux | sa licence : payant dans une grande entreprise |
| **Dépôts et gestionnaire de paquets** : Docker Engine | le moteur et ses outils, en ligne de commande | Linux | les droits d'administrateur |
| **Binaires** : les programmes seuls | des fichiers à copier, sans mise à jour automatique | surtout Linux | tout est à faire à la main |

Si vous hésitez, prenez Docker Desktop sur macOS ou sous Windows, si sa licence vous le permet, et Docker Engine sous Linux. Les binaires ne servent presque jamais. La [page d'installation officielle](https://docs.docker.com/get-started/get-docker/) est le point de départ, et les sections suivantes disent quoi y chercher.

## L'installateur : Docker Desktop, clé en main et sous licence

Docker Desktop s'installe comme n'importe quelle application : vous téléchargez un installateur, vous le lancez, et tout est là. C'est le plus simple, et c'est la seule façon d'avoir le moteur de Docker sur macOS ou sous Windows sans tout monter soi-même. Les conteneurs ont besoin d'un noyau Linux, et Docker Desktop démarre pour cela une petite machine virtuelle.

Il existe aussi [pour Linux](https://docs.docker.com/desktop/setup/install/linux/), en paquets pour Ubuntu, Debian, Fedora et RHEL. Il y tourne également dans une machine virtuelle, et ses conteneurs sont séparés de ceux d'un Docker Engine installé sur la même machine.

**C'est un produit commercial, soumis à licence.** Au moment où ce cours est écrit, il est gratuit pour un usage personnel, pour l'éducation, pour les projets open source non commerciaux et pour les entreprises de moins de 250 salariés et de moins de 10 millions de dollars de chiffre d'affaires annuel. Au-delà, un usage professionnel demande un abonnement payant. Avant de l'installer sur un poste de travail, vérifiez la [page de la licence](https://docs.docker.com/subscription/desktop-license/) et posez la question à votre entreprise. Il existe d'autres outils si cela vous bloque, comme Podman Desktop, mais ce parcours ne les couvre pas.

Une fois Docker Desktop installé ([macOS](https://docs.docker.com/desktop/setup/install/mac-install/), [Windows](https://docs.docker.com/desktop/setup/install/windows-install/)), ouvrez-le et attendez qu'il indique que le moteur tourne. Il doit rester ouvert pendant que vous travaillez : quand il est fermé, le moteur est arrêté.

Sous Windows, les commandes de ce parcours sont écrites pour un terminal de type Linux, ce que PowerShell n'est pas : travaillez dans le terminal de WSL, le Linux intégré à Windows, qui s'ouvre avec la commande `wsl`. Si `wsl` ne trouve aucune distribution, [installez-en une](https://learn.microsoft.com/windows/wsl/install) avec `wsl --install` dans PowerShell, puis redémarrez. Si `docker` y est introuvable, activez votre distribution dans Docker Desktop, sous **Settings > Resources > WSL Integration**.

## Les dépôts et le gestionnaire de paquets : Docker Engine sous Linux

Sous Linux, on installe le plus souvent **Docker Engine**, open source, avec le gestionnaire de paquets du système. La [page de votre distribution](https://docs.docker.com/engine/install/) vous fait d'abord ajouter le dépôt de Docker, c'est-à-dire la source où votre système ira chercher ces paquets, puis les installer. Sur [Debian](https://docs.docker.com/engine/install/debian/), l'installation elle-même tient dans cette commande :

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Ne la lancez pas seule : elle échoue tant que le dépôt n'est pas ajouté, et c'est la page officielle qui vous y conduit. Cette commande montre ce qu'est vraiment Docker : plusieurs composants, et non un seul programme. `ce` veut dire *Community Edition*. Voici à quoi sert chacun.

| Paquet | Ce qu'il apporte |
|---|---|
| `docker-ce` | le moteur, c'est-à-dire le daemon `dockerd`, qui tourne en tâche de fond |
| `docker-ce-cli` | le client, c'est-à-dire la CLI : la commande `docker` que vous tapez |
| `containerd.io` | containerd et runc, sur lesquels le moteur s'appuie pour faire vivre les conteneurs |
| `docker-buildx-plugin` | l'outil qui construit les images |
| `docker-compose-plugin` | Compose, qui décrit dans un fichier une application de plusieurs conteneurs ; un prochain cours s'en sert |

`apt` y ajoute quelques paquets système dont ils dépendent, comme `iptables`. Deux remarques vous éviteront des surprises :

- Le paquet `docker.io` de certaines distributions n'est pas fourni par Docker, et la page officielle demande de le retirer avant d'installer les siens.
- Après l'installation, seul l'administrateur peut utiliser Docker. Les [étapes après l'installation](https://docs.docker.com/engine/install/linux-postinstall/) expliquent comment ajouter votre utilisateur au groupe `docker`. Ce groupe donne des droits équivalents à ceux de l'administrateur : réservez-le à votre propre poste.

## Les binaires : pour des tests, pas en production

Docker publie aussi [ses programmes seuls](https://docs.docker.com/engine/install/binaries/), à copier à la main. Sa documentation réserve ce mode aux tests et le déconseille en production, parce qu'il n'apporte aucune mise à jour de sécurité automatique. Retenez qu'il existe, et préférez les paquets dès que vous le pouvez.

## Installer Docker sur votre poste

C'est à vous : suivez la page officielle du mode que vous avez choisi. L'installation dépend de votre poste et ne se fait qu'une fois, ce cours ne peut donc pas la vérifier à votre place. Les vérifications commencent à l'étape suivante.

```ack
Docker est installé, ou je suis sur un poste hébergé
```

# Les deux composants principaux : le client et le moteur

## Le client, ou CLI, parle au moteur, ou daemon

Quel que soit votre mode d'installation, vous retrouvez deux composants principaux. Le **client**, qu'on appelle aussi la **CLI** (*command line interface*), est la commande `docker` que vous tapez. Le **moteur**, qu'on appelle aussi le **daemon**, un programme qui tourne en tâche de fond, s'appelle `dockerd` : c'est lui qui crée et fait vivre les conteneurs. Le client ne fait que lui transmettre vos demandes.

```
vous  ──►  docker (le client, la CLI)  ──►  dockerd (le moteur, le daemon)  ──►  vos conteneurs
```

`docker version` demande sa version à chacun, et le montre donc bien :

```exec
docker version
```

La réponse a deux parties, `Client` et `Server`, et vous devez voir les deux. Voici ce qu'elle donne sur un Mac, raccourcie aux lignes qui comptent. Dans la partie `Server`, vous retrouvez aussi `containerd` et `runc`, sur lesquels le moteur s'appuie.

```text
Client:
 Version:           28.3.2
 OS/Arch:           darwin/arm64

Server: Docker Desktop 4.44.1 (201842)
 Engine:
  Version:          28.3.2
  OS/Arch:          linux/arm64
 containerd:
  Version:          1.7.27
 runc:
  Version:          1.2.5
```

Les deux numéros ne sont pas forcément égaux : sur un poste hébergé, par exemple, le client est plus récent que le moteur, et ce n'est pas un problème, car un client sait parler à un moteur plus ancien.

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

## Le client sans moteur : reconnaître le message d'erreur

Pour bien voir que ce sont deux programmes, faites parler le client à un moteur qui n'existe pas. La variable `DOCKER_HOST` indique au client à quelle adresse trouver le moteur. La placer devant la commande ne la change que pour cette commande, et le port 1 n'héberge aucun moteur.

```exec
DOCKER_HOST=tcp://localhost:1 docker version
```

La partie `Client` s'affiche normalement, puis le moteur manque à l'appel :

```text
Client:
 Version:           28.3.2
 ...
Cannot connect to the Docker daemon at tcp://localhost:1. Is the docker daemon running?
```

Vous reconnaissez le mot *daemon*. Quand vous verrez cette erreur plus tard, vous saurez que le client va bien et qu'il faut regarder du côté du moteur.

Sur un poste hébergé, `DOCKER_HOST` est déjà réglée pour vous, et c'est elle qui relie votre terminal à son moteur. Ne la modifiez pas pour de bon.

```ack
Je sais distinguer le client du moteur
```

## La fiche du moteur : système et architecture

`docker info` donne la fiche complète du moteur. Elle est longue, et deux lignes vous intéressent ici :

```exec
docker info
```

Cherchez `Operating System` et `Architecture`. Voici ces lignes sur un Mac :

```text
 Operating System: Docker Desktop
 Architecture: aarch64
```

Le système est celui du moteur, pas forcément le vôtre : sur un Mac, vous lisez `Docker Desktop`, car le moteur tourne dans sa machine virtuelle. L'**architecture** est la famille du processeur : `aarch64` ou `arm64` sur un Mac récent, `x86_64` ou `amd64` sur la plupart des PC. Une image doit exister pour votre architecture, et toutes celles de ce parcours existent pour les deux.

```verify
if ! docker info >/dev/null 2>&1; then
  echo "docker info ne répond pas. Le moteur est-il démarré ?"
  exit 1
fi
echo "Le moteur tourne sur l'architecture $(docker info --format '{{.Architecture}}')."
```

# Lancer un premier conteneur

## Télécharger une image et lancer un conteneur

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

Le moteur répond, il reste à lui faire faire quelque chose. Cette commande vérifie d'un coup qu'il sait télécharger une image et lancer un conteneur.

```exec
docker run --name layers-l0-hello alpine:3.22 echo "Docker fonctionne"
```

| Élément | Rôle |
|---|---|
| `docker run` | crée un conteneur depuis une image et le démarre |
| `--name layers-l0-hello` | lui donne un nom fixe, pour pouvoir le retrouver |
| `alpine:3.22` | l'image, ici Alpine, un Linux minimal, dans sa version `3.22` |
| `echo "Docker fonctionne"` | la commande que le conteneur exécute, puis il s'arrête |

Au premier lancement, Docker télécharge l'image depuis Docker Hub, puis vous lisez la phrase. Voici la fin de la réponse :

```text
Status: Downloaded newer image for alpine:3.22
Docker fonctionne
```

Si vous relancez la même commande, Docker répond `Conflict` : le nom est déjà pris par le conteneur que vous venez de créer. Pour recommencer, supprimez-le d'abord avec `docker rm layers-l0-hello`. Si le téléchargement échoue, c'est le réseau de votre poste ou la limite de Docker Hub qu'il faut regarder, pas votre installation.

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

## Lancer un serveur web et lire sa page

Reste une dernière pièce : le réseau. Beaucoup de cours de ce parcours lancent un serveur dans un conteneur et vont le lire depuis le terminal. Démarrez nginx, un serveur web. `-d` le fait tourner en arrière-plan pour vous rendre la main, et `-p 28300:80` relie le port 28300 de votre machine au port 80 du conteneur. Le tag `1.30-alpine` désigne nginx en version 1.30, construit sur Alpine :

```exec
docker run -d --name layers-l0-web -p 28300:80 nginx:1.30-alpine
```

La longue suite de chiffres et de lettres qui s'affiche est l'identifiant du conteneur. `docker ps` liste les conteneurs qui tournent, ce qui vous dit s'il a bien démarré :

```exec
docker ps
```

Dans la ligne `layers-l0-web`, la colonne `STATUS` commence par `Up`, et la colonne `PORTS` montre le lien entre les deux ports. Le conteneur tourne, vous pouvez donc lui demander sa page. `localhost` désigne votre propre machine :

```exec
curl http://localhost:28300
```

`curl` affiche le code de la page, un peu moins de trente lignes. Vous y trouvez ce titre :

```text
<h1>Welcome to nginx!</h1>
```

Si `curl` répond par une erreur, le serveur n'a sans doute pas fini de démarrer : attendez une seconde et relancez. Pour voir la page dans un navigateur, ouvrez `http://localhost:28300` sur votre poste. Sur un poste hébergé, utilisez plutôt l'onglet **PORTS** de VS Code, qui donne le lien de ce port.

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
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28300 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "Le serveur ne répond pas sur le port 28300. Regardez ses ports avec : docker ps"
  exit 1
fi
echo "Le serveur répond sur le port 28300."
```

# Nettoyer et récapituler

## Supprimer les deux conteneurs

Votre poste est vérifié, et ces deux conteneurs ne servent plus. `docker rm -f` les supprime, même celui qui tourne encore. Les images, elles, restent sur votre machine pour servir à nouveau.

```exec
docker rm -f layers-l0-hello layers-l0-web
```

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l0-(hello|web)$')
if [ -n "$left" ]; then
  echo "Il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
echo "C'est propre, et votre poste est prêt."
```

## Récap

- Docker s'installe de trois façons : Docker Desktop, soumis à licence ; les paquets de Docker Engine sous Linux ; les binaires, en dernier recours.
- Docker se compose de plusieurs paquets, dont deux principaux : le client (la CLI, `docker`) parle au moteur (le daemon, `dockerd`).
- `docker version` montre les deux, et son message d'erreur dit lequel manque.
- Un poste prêt sait télécharger une image, lancer un conteneur et servir une page sur un port.

> 📖 [Installer Docker](https://docs.docker.com/get-started/get-docker/) · [Licence de Docker Desktop](https://docs.docker.com/subscription/desktop-license/) · [Installer Docker Engine](https://docs.docker.com/engine/install/) · [`docker version`](https://docs.docker.com/reference/cli/docker/version/) · [`docker info`](https://docs.docker.com/reference/cli/docker/system/info/)

Pour vous tester sans guide, faites le challenge [Auditer une installation Docker](https://byte-layers.com/fr/challenges/docker-install-challenge).
