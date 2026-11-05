---
title: "Isoler et relier des conteneurs, sans guide"
description: "Construire deux réseaux et trois conteneurs qui ne se parlent que là où il le faut, à partir d'un cahier des charges, sans guide."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 45
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce challenge prouve que vous savez publier un port, relier des conteneurs par leur nom et isoler ceux qui n'ont pas à se parler. Il n'y a **aucune commande à recopier** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

Voici l'architecture demandée : `api` est le seul conteneur à voir les deux réseaux, et seul `web` est joignable depuis l'hôte, sur votre machine uniquement.

```
    hôte : 127.0.0.1:28356
        │
        ▼
   réseau layers-l5-front          réseau layers-l5-back
  ┌─────────────────────┐         ┌─────────────────────┐
  │   layers-l5-web     │         │   layers-l5-cache   │
  │                     │         │   nom : cache       │
  │       ┌─────────────┴─────────┴─────────────┐       │
  │       │            layers-l5-api            │       │
  │       └─────────────┬─────────┬─────────────┘       │
  └─────────────────────┘         └─────────────────────┘
```

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseignent les cours « Localhost n'est pas l'hôte » et « Relier des conteneurs et publier un port ». Le lab « Une application et sa base, à la main » est un bon entraînement.
- **Ce qu'il faut avoir** : Docker qui répond à `docker ps`, `curl`, et le port 28356 libre.
- **Un dossier de travail** : `~/layers-l5` est créé pour vous, et la dernière tâche le supprime. La vérification y garde un fichier caché, `.api-id`, qui lui sert à reconnaître votre conteneur.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l5-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : les tâches 3 et 4 portent sur le même conteneur. Faites-les dans l'ordre.

# Tâche 1 : deux réseaux

## Ce qu'il faut faire

Créez les deux réseaux de l'architecture.

**Critères :**

- deux réseaux s'appellent exactement `layers-l5-front` et `layers-l5-back` ;
- ils utilisent tous les deux le pilote `bridge`, celui qui résout les noms sur un réseau que vous créez.

```hint
Une seule sous-commande, à lancer deux fois. Le pilote `bridge` est celui par défaut.
```

```verify
for N in layers-l5-front layers-l5-back; do
  D=$(docker network inspect "$N" --format '{{.Driver}}' 2>/dev/null)
  if [ -z "$D" ]; then
    echo "ÉCHEC : le réseau $N n'existe pas."
    exit 1
  fi
  if [ "$D" != "bridge" ]; then
    echo "ÉCHEC : le réseau $N utilise le pilote $D au lieu de bridge."
    echo "  Supprimez-le et recréez-le."
    exit 1
  fi
done
echo "RÉUSSI : les deux réseaux existent."
```

````solution
```bash
docker network create layers-l5-front
docker network create layers-l5-back
```
````

# Tâche 2 : un cache sans port publié

## Ce qu'il faut faire

Lancez un serveur Redis, un serveur de données en mémoire, que seul le réseau `back` peut joindre.

**Critères :**

- un conteneur s'appelle exactement `layers-l5-cache`, et il tourne en arrière-plan ;
- il vient d'une image `redis`, `redis:8-alpine` convient ;
- il n'est branché que sur `layers-l5-back` ;
- il répond aussi au nom `cache` sur ce réseau ;
- **il ne publie aucun port**.

```hint
Redis n'a pas besoin de configuration : il écoute sur le port 6379 dès son lancement.
```

```hint
Deux options de `docker run` portent sur le réseau : l'une branche le conteneur, l'autre ajoute un nom.
```

```verify
C=layers-l5-cache
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Lisez docker logs $C."
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  *redis*) : ;;
  *) echo "ÉCHEC : $C ne vient pas d'une image redis."; exit 1 ;;
esac
NETS=$(docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}')
if [ "$NETS" != "layers-l5-back " ]; then
  echo "ÉCHEC : $C doit être sur layers-l5-back et sur rien d'autre (trouvé : $NETS)."
  exit 1
fi
if ! docker container inspect "$C" --format '{{range .NetworkSettings.Networks}}{{.Aliases}}{{end}}' | grep -qw cache; then
  echo "ÉCHEC : $C ne répond pas au nom cache sur ce réseau."
  echo "  Un alias se donne à la création : supprimez le conteneur et recréez-le."
  exit 1
fi
if [ -n "$(docker port "$C")" ]; then
  echo "ÉCHEC : $C publie un port, alors que l'hôte n'a pas à le joindre."
  echo "  Une publication ne se retire pas : supprimez-le et recréez-le."
  exit 1
fi
echo "RÉUSSI : $C n'est joignable que sur layers-l5-back, sous le nom cache."
```

````solution
```bash
docker run -d --name layers-l5-cache --network layers-l5-back --network-alias cache redis:8-alpine
```
````

# Tâche 3 : une API côté back

## Ce qu'il faut faire

```setup
mkdir -p ~/layers-l5
```

Lancez l'API : un petit serveur web Python sur le réseau `back`. Pour l'instant, elle ne voit que ce réseau.

**Critères :**

- un conteneur s'appelle exactement `layers-l5-api`, et il tourne en arrière-plan ;
- il exécute `python -m http.server 8000`, depuis l'image `python:3.13-alpine`, ce qui sert une page sur le port 8000 ;
- il n'est branché que sur `layers-l5-back` ;
- il **joint le cache par le nom `cache`**, sur le port 6379. Pour le tester vous-même : `docker exec layers-l5-api nc -z -w 2 cache 6379; echo $?`, où `nc -z` teste un port sans rien envoyer, `-w 2` limite l'attente à 2 secondes, et `0` veut dire que le port répond.

```hint
Tout ce qui suit le nom de l'image, dans `docker run`, remplace la commande de l'image.
```

```verify
C=layers-l5-api
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Lisez docker logs $C."
  exit 1
fi
case "$(docker container inspect "$C" --format '{{json .Config.Cmd}}')" in
  *http.server*8000*) : ;;
  *) echo "ÉCHEC : $C n'exécute pas python -m http.server 8000."; exit 1 ;;
esac
NETS=$(docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}')
if [ "$NETS" != "layers-l5-back " ]; then
  echo "ÉCHEC : à cette étape, $C doit être sur layers-l5-back seulement (trouvé : $NETS)."
  echo "  La tâche suivante le branche sur l'autre réseau."
  exit 1
fi
if ! docker exec "$C" nc -z -w 2 cache 6379 2>/dev/null; then
  echo "ÉCHEC : $C ne joint pas cache sur le port 6379. Le cache de la tâche 2 tourne-t-il ?"
  exit 1
fi
mkdir -p "$HOME/layers-l5"
docker container inspect "$C" --format '{{.Id}}' > "$HOME/layers-l5/.api-id"
echo "RÉUSSI : $C joint le cache par son nom."
```

````solution
```bash
docker run -d --name layers-l5-api --network layers-l5-back python:3.13-alpine python -m http.server 8000
```
````

# Tâche 4 : brancher l'API sans la recréer

## Ce qu'il faut faire

L'API doit maintenant être joignable depuis le réseau `front`. Elle tourne et il ne faut pas l'interrompre : branchez-la sans la recréer.

**Critères :**

- `layers-l5-api` est branché sur `layers-l5-front` **et** sur `layers-l5-back` ;
- c'est **le même conteneur** qu'à la tâche 3 : le supprimer et le recréer ne convient pas.

```hint
Une sous-commande de `docker network` agit sur un conteneur qui tourne.
```

```verify
C=layers-l5-api
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur $C n'existe pas. Faites d'abord la tâche 3."
  exit 1
fi
ID_REF=$(cat "$HOME/layers-l5/.api-id" 2>/dev/null)
if [ -z "$ID_REF" ]; then
  echo "ÉCHEC : la tâche 3 n'a pas été vérifiée. Vérifiez-la d'abord : elle note l'identifiant de $C."
  exit 1
fi
if [ "$ID_REF" != "$(docker container inspect "$C" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : $C n'est plus le conteneur de la tâche 3 : il a été recréé."
  echo "  Supprimez-le, refaites la tâche 3, puis branchez ce conteneur-là."
  exit 1
fi
NETS=$(docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}')
case "$NETS" in
  *layers-l5-front*) : ;;
  *) echo "ÉCHEC : $C n'est pas branché sur layers-l5-front (trouvé : $NETS)."; exit 1 ;;
esac
case "$NETS" in
  *layers-l5-back*) : ;;
  *) echo "ÉCHEC : $C a quitté layers-l5-back (trouvé : $NETS). Il doit rester sur les deux réseaux."; exit 1 ;;
esac
echo "RÉUSSI : $C est sur les deux réseaux, sans avoir été recréé."
```

````solution
```bash
docker network connect layers-l5-front layers-l5-api
```
````

# Tâche 5 : le serveur web, joignable depuis votre machine seulement

## Ce qu'il faut faire

Lancez le serveur web qui fait face à l'hôte. Il joint l'API, mais il ne doit pas pouvoir joindre le cache.

**Critères :**

- un conteneur s'appelle exactement `layers-l5-web`, il tourne et il vient d'une image `nginx`, `nginx:1.30-alpine` convient ;
- il n'est branché que sur `layers-l5-front` ;
- le port **28356** de l'hôte mène à son port **80**, sur l'adresse `127.0.0.1` uniquement ;
- `curl http://localhost:28356` répond depuis l'hôte ;
- il joint l'API sur `layers-l5-api`, port 8000 ;
- il **ne joint pas** le cache, ni par `cache` ni par `layers-l5-cache`.

```hint
Le port se limite à votre machine en plaçant l'adresse devant les deux numéros, dans `-p`.
```

```hint
Sur un réseau, on demande le port du conteneur : 8000 pour l'API. `docker exec layers-l5-web wget -qO- -T 3 http://layers-l5-api:8000` vous permet de le tester.
```

```verify
C=layers-l5-web
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Docker indique : $(docker container inspect "$C" --format '{{.State.Error}}')"
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  *nginx*) : ;;
  *) echo "ÉCHEC : $C ne vient pas d'une image nginx."; exit 1 ;;
esac
NETS=$(docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}')
if [ "$NETS" != "layers-l5-front " ]; then
  echo "ÉCHEC : $C doit être sur layers-l5-front et sur rien d'autre (trouvé : $NETS)."
  exit 1
fi
B=$(docker container inspect "$C" --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}}={{.HostIp}}:{{.HostPort}} {{end}}{{end}}')
if [ "$B" != "80/tcp=127.0.0.1:28356 " ]; then
  echo "ÉCHEC : le port publié n'est pas celui demandé (trouvé : ${B:-rien}, attendu : 127.0.0.1:28356 vers le port 80)."
  echo "  Une publication se fixe à la création : supprimez $C et recréez-le."
  exit 1
fi
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28356 | grep -q 'Welcome to nginx'; then
  echo "ÉCHEC : http://localhost:28356 ne répond pas depuis l'hôte."
  exit 1
fi
if ! docker exec "$C" wget -qO- -T 3 http://layers-l5-api:8000 >/dev/null 2>&1; then
  echo "ÉCHEC : $C ne joint pas layers-l5-api sur le port 8000. L'API est-elle branchée sur layers-l5-front ?"
  exit 1
fi
for N in cache layers-l5-cache; do
  if docker exec "$C" nc -z -w 2 "$N" 6379 2>/dev/null; then
    echo "ÉCHEC : $C joint le cache par le nom $N, alors qu'il devrait en être isolé."
    exit 1
  fi
done
echo "RÉUSSI : $C répond sur votre machine, joint l'API et ne voit pas le cache."
```

````solution
```bash
docker run -d --name layers-l5-web --network layers-l5-front -p 127.0.0.1:28356:80 nginx:1.30-alpine
```
````

# Tâche 6 : ne rien laisser derrière soi

## Ce qu'il faut faire

Supprimez tout ce que ce challenge a créé : les conteneurs `layers-l5-web`, `layers-l5-api` et `layers-l5-cache`, les réseaux `layers-l5-front` et `layers-l5-back`, et le dossier `~/layers-l5`.

**Critères :** plus aucun de ces objets, plus de dossier. Vos autres conteneurs et réseaux ne sont pas concernés.

```hint
Un réseau occupé ne se supprime pas : commencez par les conteneurs.
```

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(web|api|cache)$')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
for N in layers-l5-front layers-l5-back; do
  if docker network inspect "$N" >/dev/null 2>&1; then
    echo "ÉCHEC : le réseau $N existe encore."
    exit 1
  fi
done
if [ -e "$HOME/layers-l5" ]; then
  echo "ÉCHEC : le dossier ~/layers-l5 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez isoler et relier des conteneurs."
```

````solution
```bash
docker rm -f layers-l5-web layers-l5-api layers-l5-cache
docker network rm layers-l5-front layers-l5-back
rm -rf ~/layers-l5
```
````
