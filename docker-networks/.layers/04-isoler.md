---
title: "Isoler et rattacher"
description: "Deux réseaux qui ne se voient pas, et un conteneur branché sur les deux"
---

Mettre tous les conteneurs d'une application sur un même réseau marche, mais rien n'empêche alors un serveur web exposé d'atteindre directement une base de données. Mieux vaut ne relier que ce qui doit se parler : si le serveur web est compromis, la base reste hors de sa portée. Un réseau sert aussi à cela : **deux conteneurs sur des réseaux différents ne se voient pas**.

Voici l'architecture que vous allez construire. `api` est le seul à connaître les deux côtés :

```
   réseau layers-l5-front          réseau layers-l5-back
  ┌─────────────────────┐         ┌─────────────────────┐
  │   layers-l5-web     │         │    layers-l5-db     │
  │                     │         │                     │
  │       ┌─────────────┴─────────┴─────────────┐       │
  │       │            layers-l5-api            │       │
  │       └─────────────┬─────────┬─────────────┘       │
  └─────────────────────┘         └─────────────────────┘
```

## Deux réseaux, deux conteneurs

Créez les deux réseaux, puis un conteneur sur chacun. Ils attendent simplement, car seul le réseau compte ici :

```exec
docker network create layers-l5-front
docker network create layers-l5-back
docker run -d --name layers-l5-web --network layers-l5-front alpine:3.22 sleep 3600
docker run -d --name layers-l5-db --network layers-l5-back alpine:3.22 sleep 3600
```

Demandez au premier de joindre le second par son nom. `-W 2` limite l'attente à 2 secondes :

```exec
docker exec layers-l5-web ping -c 1 -W 2 layers-l5-db
```

Vous lisez `bad address 'layers-l5-db'`. Le serveur de noms de `layers-l5-front` ne connaît que les conteneurs de ce réseau : le nom n'existe même pas de ce côté.

```verify
if [ "$(docker inspect layers-l5-web --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}}{{end}}' 2>/dev/null)" != "layers-l5-front" ]; then
  echo "layers-l5-web n'est pas sur le seul réseau layers-l5-front. Supprimez les conteneurs (docker rm -f layers-l5-web layers-l5-db) et relancez la commande de cette section."
  exit 1
fi
if [ "$(docker inspect layers-l5-db --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}}{{end}}' 2>/dev/null)" != "layers-l5-back" ]; then
  echo "layers-l5-db n'est pas sur le seul réseau layers-l5-back. Supprimez les conteneurs (docker rm -f layers-l5-web layers-l5-db) et relancez la commande de cette section."
  exit 1
fi
if docker exec layers-l5-web ping -c 1 -W 2 layers-l5-db >/dev/null 2>&1; then
  echo "layers-l5-web joint layers-l5-db : ils ne devraient pas se voir."
  exit 1
fi
echo "Les deux conteneurs sont sur des réseaux séparés et ne se voient pas."
```

## Un conteneur sur les deux réseaux

Il faut pourtant bien un intermédiaire entre ces deux mondes. Un conteneur peut être branché sur plusieurs réseaux, et il reçoit alors une adresse sur chacun. Lancez `layers-l5-api` sur le réseau `back`, puis branchez-le aussi sur `front`, à chaud. C'est le rôle de `docker network connect <réseau> <conteneur>`, qui évite de recréer le conteneur. Dans le `--format` de la dernière ligne, `$n` est le nom de chaque réseau, `$v` ses informations, et `println` passe à la ligne :

```exec
docker run -d --name layers-l5-api --network layers-l5-back alpine:3.22 sleep 3600
docker network connect layers-l5-front layers-l5-api
docker inspect layers-l5-api --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{$v.IPAddress}}{{println}}{{end}}'
```

Vous lisez deux lignes, avec une adresse dans chaque réseau. `layers-l5-api` joint maintenant les deux autres. Le dernier des trois tests reste bloqué, ce qui est le but recherché :

```exec
docker exec layers-l5-api ping -c 1 -W 2 layers-l5-db
docker exec layers-l5-api ping -c 1 -W 2 layers-l5-web
docker exec layers-l5-web ping -c 1 -W 2 layers-l5-db
```

Les deux premiers affichent `1 packets received`, et le troisième `bad address`. **Se brancher sur deux réseaux ne les fusionne pas** : `layers-l5-api` les voit tous les deux, mais `layers-l5-web` ne gagne rien.

```verify
NETS=$(docker inspect layers-l5-api --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}' 2>/dev/null)
case "$NETS" in
  *layers-l5-back*) : ;;
  *) echo "layers-l5-api n'est pas sur layers-l5-back."; exit 1 ;;
esac
case "$NETS" in
  *layers-l5-front*) : ;;
  *) echo "layers-l5-api n'est pas sur layers-l5-front. Lancez le docker network connect."; exit 1 ;;
esac
if ! docker exec layers-l5-api ping -c 1 -W 2 layers-l5-db >/dev/null 2>&1 || ! docker exec layers-l5-api ping -c 1 -W 2 layers-l5-web >/dev/null 2>&1; then
  echo "layers-l5-api ne joint pas les deux autres conteneurs. Vérifiez qu'ils tournent : docker ps --filter name=layers-l5"
  exit 1
fi
if docker exec layers-l5-web ping -c 1 -W 2 layers-l5-db >/dev/null 2>&1; then
  echo "layers-l5-web joint layers-l5-db : l'isolation n'est plus assurée."
  exit 1
fi
echo "layers-l5-api relie les deux côtés, et les deux côtés restent séparés."
```

## Débrancher, et tout déclarer d'un coup

Le geste inverse, `docker network disconnect`, débranche un conteneur sans l'arrêter. C'est pratique pour couper un accès et constater que la connexion tombe. Le `ping` échoue donc à nouveau, avec `bad address` :

```exec
docker network disconnect layers-l5-front layers-l5-api
docker exec layers-l5-api ping -c 1 -W 2 layers-l5-web
```

Vous pouvez aussi déclarer tous les réseaux dès la création, en répétant `--network` : c'est possible depuis Docker 25, comme le dit `docker --version`, et `docker network connect` reste la solution sur une version plus ancienne. Recréez `layers-l5-api` de cette façon :

```exec
docker rm -f layers-l5-api
docker run -d --name layers-l5-api --network layers-l5-back --network layers-l5-front alpine:3.22 sleep 3600
docker exec layers-l5-api ping -c 1 -W 2 layers-l5-web
```

```verify
NETS=$(docker inspect layers-l5-api --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}' 2>/dev/null)
case "$NETS" in
  *layers-l5-back*layers-l5-front*|*layers-l5-front*layers-l5-back*) : ;;
  *) echo "layers-l5-api n'est pas branché sur les deux réseaux (trouvé : ${NETS:-rien})."; exit 1 ;;
esac
echo "layers-l5-api est branché sur les deux réseaux dès sa création."
```

Il reste à tout supprimer, les conteneurs d'abord et les réseaux ensuite :

```exec
docker rm -f layers-l5-web layers-l5-db layers-l5-api
docker network rm layers-l5-front layers-l5-back
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(web|db|api)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
if docker network inspect layers-l5-front >/dev/null 2>&1 || docker network inspect layers-l5-back >/dev/null 2>&1; then
  echo "Il reste un réseau. Lancez le docker network rm ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker network connect`](https://docs.docker.com/reference/cli/docker/network/connect/) · [`docker network disconnect`](https://docs.docker.com/reference/cli/docker/network/disconnect/) · [Le réseau dans Docker](https://docs.docker.com/engine/network/)

## Récap

- `-p <hôte>:<conteneur>` publie un port pour l'hôte, et `127.0.0.1` devant le limite à votre machine.
- Le réseau par défaut relie les conteneurs, mais ne résout pas leurs noms.
- Sur un réseau que vous créez, un conteneur en joint un autre par son nom ou par un alias, et sur le port du conteneur.
- Deux réseaux ne se voient pas : un conteneur sert de lien en se branchant sur les deux, sans les fusionner.

## Questions

```quiz
title: "Isoler et rattacher"
tracksProgress: false
showNotice: false
questions:
  - prompt: "`web` est sur le réseau `front`, et `db` sur le réseau `back`. Que répond `ping db` depuis `web` ?"
    answers:
      - "`bad address`, car ce nom n'existe pas sur le réseau `front`"
      - "`1 packets received`, car ils sont sur le même hôte"
      - "`Connection refused`, car le port 3306 n'est pas publié"
    correct: 1
    explanation: "Le serveur de noms de chaque réseau ne connaît que ses propres conteneurs."
  - prompt: "`api` est branché sur `front` et sur `back`. Que peut joindre `web`, qui n'est que sur `front` ?"
    answers:
      - "`api` et `db`, car `api` fusionne les deux réseaux"
      - "`api` seulement"
      - "Rien : un conteneur ne peut plus être joint dès qu'il a deux réseaux"
    correct: 2
    explanation: "Se brancher sur deux réseaux ne les fusionne pas : seul `api` voit les deux côtés."
  - prompt: "Quelle commande branche un conteneur qui tourne sur un réseau, sans le recréer ?"
    answers:
      - "`docker network connect <réseau> <conteneur>`"
      - "`docker run --network <réseau> <conteneur>`"
      - "`docker network create <réseau> <conteneur>`"
    correct: 1
    explanation: "`--network` ne vaut qu'à la création. `connect` et `disconnect` agissent sur un conteneur existant."
```
