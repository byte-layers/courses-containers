---
title: "Configurer au lancement"
description: "Publier un port, passer une variable d'environnement, remplacer la commande, limiter la mémoire"
---

Une même image sert à des usages différents : c'est au lancement qu'on l'adapte. Tout passe par des options placées **avant** le nom de l'image, et la commande éventuelle vient **après**. Voici la forme générale, où les crochets marquent ce qui est facultatif.

```
docker run [options] image [commande]
```

## Publier un port pour joindre un serveur

Un **port** est le numéro auquel un service répond sur une machine. nginx, un serveur web, répond sur le port 80 de son conteneur. Lancez-le sans autre option :

```exec
docker run -d --name layers-l1-web nginx:1.30-alpine
```

Le tag `1.30-alpine` désigne nginx en version 1.30, construit sur Alpine.

`docker ps` montre qu'il tourne, avec `80/tcp` dans sa colonne `PORTS` :

```exec
docker ps
```

Le port 80 est donc bien ouvert dans le conteneur. Demandez la page à ce même port depuis votre machine, que `localhost` désigne :

```exec
curl http://localhost:80
```

Personne ne répond, car rien ne relie votre machine à ce conteneur : son réseau est à part, et il faut demander le passage. Si un autre service occupe déjà le port 80 de votre machine, c'est lui qui répond, et non nginx.

```text
curl: (7) Failed to connect to localhost port 80 after 0 ms: Couldn't connect to server
```

C'est le rôle de `-p`, qui **publie** un port. Son ordre est toujours `-p <port de la machine>:<port du conteneur>`. Une option se pose à la création, donc supprimez ce conteneur, puis recréez-le :

```exec
docker rm -f layers-l1-web
docker run -d --name layers-l1-web -p 28082:80 nginx:1.30-alpine
```

Regardez d'abord s'il tourne, puis ce que dit sa colonne `PORTS` :

```exec
docker ps
```

Elle affiche maintenant `0.0.0.0:28082->80/tcp`, suivi parfois d'une variante en `[::]`, ce qui se lit : le port 28082 de la machine mène au port 80 du conteneur. Redemandez la page :

```exec
curl http://localhost:28082
```

Vous lisez le code d'une page, avec ce titre. Si `curl` répond par une erreur, le serveur n'a pas fini de démarrer : attendez une seconde et relancez.

```text
<h1>Welcome to nginx!</h1>
```

```verify
if [ "$(docker port layers-l1-web 80 2>/dev/null | head -1 | sed 's/.*://')" != "28082" ]; then
  echo "layers-l1-web ne publie pas le port 28082. Supprimez-le (docker rm -f layers-l1-web), puis relancez la commande avec -p 28082:80."
  exit 1
fi
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28082 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "Le serveur ne répond pas sur le port 28082. Regardez ses ports avec : docker ps"
  exit 1
fi
echo "nginx répond sur le port 28082."
```

Le port du conteneur est fixé par l'image, mais celui de la machine est libre : 28082 est un choix de ce cours, pour éviter de gêner vos autres services. Vous pouvez donc lancer un second nginx, lui aussi sur son port 80, à condition de lui donner un autre port de machine :

```exec
docker run -d --name layers-l1-web2 -p 28080:80 nginx:1.30-alpine
```

Il répond à son tour, sur son propre port :

```exec
curl http://localhost:28080
```

Deux règles complètent ce geste :

- Un port de la machine ne sert qu'à un seul conteneur. Sinon Docker répond `port is already allocated`, et le conteneur est créé sans démarrer : libérez le port ou choisissez-en un autre, puis supprimez ce conteneur et recréez-le.
- `-p 28082:80` ouvre le port sur toutes les adresses de la machine, donc potentiellement au réseau. `-p 127.0.0.1:28082:80` le réserve à la machine elle-même. ⚖️ Ce parcours garde la forme courte pour rester lisible, mais il vaut mieux préférer celle-ci sur un poste exposé à un réseau partagé.

```verify
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28080 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "Le second serveur ne répond pas sur le port 28080. Regardez ses ports avec : docker ps"
  exit 1
fi
echo "Deux serveurs, deux ports de machine."
```

Ces deux serveurs ont fini leur travail, supprimez-les pour libérer les ports :

```exec
docker rm -f layers-l1-web layers-l1-web2
```

> 📖 [Publier des ports](https://docs.docker.com/get-started/docker-concepts/running-containers/publishing-ports/)

## Passer une variable d'environnement

La plupart des images se configurent par des **variables d'environnement**, des paires nom et valeur que le processus peut lire. `-e` en définit une, et la commande `env` affiche toutes celles du conteneur :

```exec
docker run --rm -e PRENOM=Ada alpine:3.22 env
```

Vous trouvez votre variable parmi celles que Docker a posées :

```text
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=be063888fdcd
PRENOM=Ada
HOME=/root
```

Une image de base de données se configure ainsi : le mot de passe de départ, par exemple, lui est passé par une variable.

```ack
J'ai lu PRENOM=Ada
```

## Remplacer la commande de l'image

Une image prévoit une commande par défaut, celle qu'exécute le conteneur si vous n'en donnez pas : le serveur pour nginx, un shell pour alpine. Tout ce que vous écrivez après le nom de l'image la remplace, ce que vous faites depuis le début avec `sleep` ou `cat` :

```exec
docker run --rm alpine:3.22 echo "cette commande remplace celle de l'image"
```

```ack
Je sais où mettre la commande
```

## Limiter la mémoire et le processeur

Sans limite, un conteneur peut consommer toute la mémoire de la machine. `--memory` et `--cpus` posent ces limites, ici 64 Mio et la moitié d'un cœur de processeur :

```exec
docker run -d --name layers-l1-limited --memory 64m --cpus 0.5 nginx:1.30-alpine
```

`docker stats` affiche ce que consomme un conteneur. Il se met à jour en continu, et `--no-stream` donne une seule mesure pour vous rendre la main :

```exec
docker stats --no-stream layers-l1-limited
```

Lisez la colonne `MEM USAGE / LIMIT` : la limite affichée est `64MiB`, et non la mémoire de votre machine.

```text
CONTAINER ID   NAME                CPU %     MEM USAGE / LIMIT   MEM %     NET I/O      BLOCK I/O     PIDS
c597c2280a15   layers-l1-limited   0.00%     11.37MiB / 64MiB    17.76%    390B / 84B   0B / 8.19kB   15
```

```verify
MEM=$(docker inspect layers-l1-limited --format '{{.HostConfig.Memory}}' 2>/dev/null)
CPU=$(docker inspect layers-l1-limited --format '{{.HostConfig.NanoCpus}}' 2>/dev/null)
if [ "$MEM" != "67108864" ] || [ "$CPU" != "500000000" ]; then
  echo "layers-l1-limited n'a pas les limites attendues (mémoire : ${MEM:-aucune}, CPU : ${CPU:-aucun})."
  echo "Supprimez-le (docker rm -f layers-l1-limited) et relancez la commande."
  exit 1
fi
echo "Limites en place : 64 Mio et un demi-CPU."
```

Ce conteneur n'a plus d'utilité, supprimez-le pour finir :

```exec
docker rm -f layers-l1-limited
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l1-(web|web2|limited)$')" ]; then
  echo "Il reste des conteneurs de cette étape. Supprimez-les avec docker rm -f."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Limiter les ressources](https://docs.docker.com/engine/containers/resource_constraints/) · [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/) · [`docker stats`](https://docs.docker.com/reference/cli/docker/container/stats/)

## Questions sur la configuration

```quiz
title: "Configurer au lancement"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que veut dire `-p 8080:80` ?"
    answers:
      - "Le port 8080 de la machine mène au port 80 du conteneur"
      - "Le port 80 de la machine mène au port 8080 du conteneur"
      - "Le conteneur n'accepte que 80 connexions sur le port 8080"
    correct: 1
    explanation: "L'ordre est toujours machine, puis conteneur."
  - prompt: "Un serveur tourne dans un conteneur, sans `-p`. `curl http://localhost:80` échoue depuis votre machine. Pourquoi ?"
    answers:
      - "Le serveur n'a pas démarré"
      - "Rien ne relie un port de la machine à ce conteneur : il faut le recréer avec `-p`"
      - "`curl` ne fonctionne pas avec les conteneurs"
    correct: 2
    explanation: "Le port 80 existe dans le conteneur, mais il n'est pas publié sur la machine. `-p` se donne à la création."
  - prompt: "Où placer l'option `-e` dans `docker run` ?"
    answers:
      - "Avant le nom de l'image"
      - "Après le nom de l'image"
      - "Où l'on veut"
    correct: 1
    explanation: "Tout ce qui suit le nom de l'image est la commande du conteneur : `docker run alpine:3.22 -e X=1` tenterait d'exécuter `-e`."
  - prompt: "Sans `--memory`, combien de mémoire un conteneur peut-il utiliser ?"
    answers:
      - "64 Mio par défaut"
      - "Autant que la machine en a de disponible"
      - "La moitié de la mémoire de la machine"
    correct: 2
    explanation: "Il n'y a aucune limite par défaut : un seul conteneur peut donc affamer tous les autres."
```
