---
title: "Publier un port"
description: "-p, l'ordre de ses deux numéros, les conflits, et l'écoute limitée à votre machine"
---

Un conteneur a sa propre pile réseau, isolée de celle de votre machine, l'**hôte**. Un serveur peut donc tourner dans un conteneur sans qu'aucun port de l'hôte ne mène à lui. **Publier un port**, c'est ouvrir une porte précise de l'hôte et la relier à une porte du conteneur.

## Un serveur sans port publié

Commencez par le cas sans publication, pour voir ce qu'il manque. Lancez un serveur nginx, puis regardez sa ligne dans `docker ps`. `--filter` ne garde que ce conteneur, et `--format` choisit les colonnes affichées :

```exec
docker run -d --name layers-l5-nopub nginx:1.30-alpine
docker ps --filter name=layers-l5-nopub --format '{{.Names}} : {{.Ports}}'
```

Vous lisez `80/tcp`, sans flèche. Le serveur écoute sur le port 80 **de son conteneur**, et rien ne relie ce port à l'hôte. Cette mention vient de l'instruction `EXPOSE` du Dockerfile de l'image, qui documente le port du service sans rien ouvrir.

```verify
if [ "$(docker inspect layers-l5-nopub --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l5-nopub ne tourne pas. Lancez la commande de cette section."
  exit 1
fi
if [ -n "$(docker port layers-l5-nopub 2>/dev/null)" ]; then
  echo "layers-l5-nopub a un port publié. Supprimez-le (docker rm -f layers-l5-nopub) et relancez la commande telle quelle."
  exit 1
fi
echo "layers-l5-nopub tourne, sans port publié."
```

## Publier avec -p

C'est l'option `-p <port de l'hôte>:<port du conteneur>` qui crée le lien. On retient l'ordre ainsi : **d'abord chez vous, ensuite chez lui**. Lancez un second serveur, avec cette option :

```exec
docker run -d --name layers-l5-pub -p 28352:80 nginx:1.30-alpine
docker ps --filter name=layers-l5-pub --format '{{.Names}} : {{.Ports}}'
```

La colonne affiche maintenant `0.0.0.0:28352->80/tcp`, et une flèche est apparue : l'hôte à gauche, le conteneur à droite. Vous pouvez aussi lire une entrée `[::]`, qui dit la même chose pour IPv6, la version récente des adresses IP. Demandez la page depuis l'hôte, en n'affichant que son titre. `-sS` n'affiche que les erreurs, et `--retry` patiente le temps que le serveur démarre :

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28352 | grep '<h1>'
```

Si vous travaillez sur un poste hébergé, c'est-à-dire un VS Code ouvert dans votre navigateur et fourni par votre formateur, `curl` marche de la même façon, et l'onglet **PORTS** de VS Code donne le lien à ouvrir dans le navigateur.

```verify
BINDINGS=$(docker inspect layers-l5-pub --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}}={{.HostPort}} {{end}}{{end}}' 2>/dev/null)
case " $BINDINGS" in
  *" 80/tcp=28352 "*) : ;;
  *) echo "Le port 28352 de l'hôte ne mène pas au port 80 de layers-l5-pub (trouvé : ${BINDINGS:-rien}). Rappel : -p <hôte>:<conteneur>."; exit 1 ;;
esac
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28352 | grep -q 'Welcome to nginx'; then
  echo "Le port est publié, mais la page ne répond pas. Regardez : docker logs layers-l5-pub"
  exit 1
fi
echo "nginx répond sur le port 28352 de l'hôte."
```

## Un port de l'hôte n'a qu'un seul occupant

Vos deux conteneurs écoutent tous les deux sur le port 80, et cela ne gêne personne, puisque chacun a sa pile réseau. L'hôte, lui, n'a qu'un seul port 28352. Demandez-le une seconde fois pour voir l'erreur :

```exec
docker run -d --name layers-l5-conflit -p 28352:80 nginx:1.30-alpine
```

Docker répond `port is already allocated`. C'est l'erreur de publication la plus fréquente, et elle laisse un conteneur créé mais jamais démarré, qui garde son nom. Il faut le supprimer avant de recommencer. `-a` fait apparaître dans `docker ps` les conteneurs qui ne tournent pas :

```exec
docker ps -a --filter name=layers-l5-conflit --format '{{.Names}} : {{.Status}}'
docker rm layers-l5-conflit
```

Le correctif tient en un chiffre : prenez un autre port de l'hôte. Le port du conteneur, lui, ne change pas. `docker port <conteneur>` liste ensuite les ports publiés, en affichant cette fois le conteneur à gauche et l'hôte à droite :

```exec
docker run -d --name layers-l5-conflit -p 28353:80 nginx:1.30-alpine
docker port layers-l5-conflit
```

```verify
if [ "$(docker inspect layers-l5-conflit --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l5-conflit ne tourne pas. Supprimez-le (docker rm -f layers-l5-conflit), puis relancez-le sur le port 28353."
  exit 1
fi
if ! docker port layers-l5-conflit 80 2>/dev/null | grep -q ':28353$'; then
  echo "layers-l5-conflit n'est pas publié sur le port 28353 de l'hôte."
  exit 1
fi
echo "Deux serveurs sur le port 80 de leur conteneur, deux ports différents sur l'hôte."
```

## Ne publier que pour votre machine

`docker port` affichait `0.0.0.0:28353`. L'adresse `0.0.0.0` veut dire « toutes les adresses de l'hôte » : le port est joignable depuis votre réseau, par exemple par vos voisins sur le Wi-Fi d'une salle. Sous Linux, Docker écrit de plus ses propres règles réseau, si bien qu'un port publié passe outre un pare-feu comme `ufw`.

Pour un service de développement, il vaut mieux limiter le port à votre machine, en plaçant l'adresse `127.0.0.1` devant. Recréez le conteneur de cette façon :

```exec
docker rm -f layers-l5-conflit
docker run -d --name layers-l5-conflit -p 127.0.0.1:28353:80 nginx:1.30-alpine
docker port layers-l5-conflit
```

Vous lisez `80/tcp -> 127.0.0.1:28353`, et `curl localhost:28353` marche toujours depuis votre machine.

```verify
HOSTIP=$(docker inspect layers-l5-conflit --format '{{range .HostConfig.PortBindings}}{{range .}}{{.HostIp}} {{.HostPort}}{{end}}{{end}}' 2>/dev/null)
if [ "$HOSTIP" != "127.0.0.1 28353" ]; then
  echo "Le port n'est pas limité à votre machine (trouvé : ${HOSTIP:-rien}). Recréez le conteneur avec -p 127.0.0.1:28353:80."
  exit 1
fi
echo "Le port 28353 n'écoute que sur votre machine."
```

## Laisser Docker choisir le port

Quand le numéro n'a pas d'importance, `-P` (en majuscule) publie tous les ports déclarés par `EXPOSE`, chacun sur un port libre choisi par Docker. C'est utile pour des essais, moins pour une adresse à communiquer, car le numéro change à chaque création :

```exec
docker run -d --name layers-l5-auto -P nginx:1.30-alpine
docker port layers-l5-auto
```

Vous lisez un grand numéro, souvent au-dessus de 32000 : c'est lui qu'il faudrait demander à `curl`. Cet essai est terminé, supprimez les quatre conteneurs de cette étape :

```exec
docker rm -f layers-l5-nopub layers-l5-pub layers-l5-conflit layers-l5-auto
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(nopub|pub|conflit|auto)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Publier des ports](https://docs.docker.com/get-started/docker-concepts/running-containers/publishing-ports/) · [`docker port`](https://docs.docker.com/reference/cli/docker/container/port/) · [Les ports et les règles du pare-feu](https://docs.docker.com/engine/network/packet-filtering-firewalls/)

## Questions

```quiz
title: "Publier un port"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que veut dire `-p 8080:80` ?"
    answers:
      - "Le port 8080 du conteneur mène au port 80 de l'hôte"
      - "Le port 8080 de l'hôte mène au port 80 du conteneur"
      - "Le conteneur écoute sur les ports 8080 et 80"
    correct: 2
    explanation: "D'abord chez vous, ensuite chez lui : l'hôte à gauche, le conteneur à droite."
  - prompt: "`docker ps` affiche `80/tcp` sans flèche pour un conteneur nginx. Que pouvez-vous en conclure ?"
    answers:
      - "Le port 80 de l'hôte mène au conteneur"
      - "Le port est déclaré par l'image, mais aucun port de l'hôte n'y mène"
      - "nginx ne s'est pas lancé"
    correct: 2
    explanation: "Sans flèche, il n'y a pas de publication. `EXPOSE` documente le port du service, seul `-p` ou `-P` relie l'hôte au conteneur."
  - prompt: "Vous lancez deux conteneurs nginx avec `-p 8080:80` tous les deux. Que se passe-t-il ?"
    answers:
      - "Le second échoue : le port 8080 de l'hôte est déjà pris"
      - "Le second échoue : le port 80 est déjà pris dans le premier conteneur"
      - "Docker répartit les requêtes entre les deux"
    correct: 1
    explanation: "Chaque conteneur a son propre port 80. Seul le port 8080 de l'hôte n'existe qu'en un exemplaire, d'où `port is already allocated`."
  - prompt: "Pourquoi écrire `-p 127.0.0.1:8080:80` sur un poste de développement ?"
    answers:
      - "Pour que le conteneur écoute sur son localhost"
      - "Pour que le port de l'hôte ne soit joignable que depuis votre machine"
      - "Pour accélérer les requêtes"
    correct: 2
    explanation: "Sans adresse, le port est ouvert sur `0.0.0.0`, c'est-à-dire sur toutes les adresses de l'hôte, donc depuis votre réseau."
```
