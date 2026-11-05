---
title: "Une application et sa base, à la main"
description: "Scénario à réaliser en autonomie : brancher getting-started-app sur MySQL en créant vous-même le réseau et les conteneurs."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 60
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

**Scénario à réaliser en autonomie** : vous allez faire tourner une vraie application web avec sa base de données, chacune dans son conteneur, reliées par un réseau que vous créez vous-même. Vous complétez les blancs marqués `# TODO`, et une vérification contrôle chaque étape. Une solution reste disponible à chaque étape, à ne regarder qu'en cas de blocage.

**Niveau** : débutant. Vous savez lancer un conteneur, lire ses logs et utiliser `docker exec` (cours « Lancer, configurer et observer un conteneur »), et vous savez ce qu'est un Dockerfile (cours « Écrire le Dockerfile d'une application »). Toutes les options de réseau utiles sont expliquées ici au moment où elles servent.

**Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, et le port **28355** libre. Tout ce que vous créez porte le préfixe `layers-l5-`, et vos fichiers vont dans `~/layers-l5`. La dernière étape supprime le tout, sauf les images téléchargées, qui restent pour servir à nouveau.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

## Ce que vous allez construire

L'application `getting-started-app` est une petite liste de tâches écrite en Node.js. Sans configuration, elle garde ses données dans un fichier SQLite à l'intérieur de son conteneur. Dès qu'elle reçoit la variable `MYSQL_HOST`, elle se connecte à la place à un serveur MySQL. Voici l'architecture visée :

```
                 votre machine (l'hôte)
  ┌─────────────────────────────────────────────────────┐
  │  curl ou navigateur : localhost:28355               │
  │        │                                            │
  │        ▼  port publié 28355 vers 3000               │
  │   ┌─────────────────── réseau layers-l5-net ──────┐ │
  │   │  layers-l5-todo  ───────►  layers-l5-db       │ │
  │   │  (Node.js, port 3000)      nom : mysql        │ │
  │   │                            (MySQL, port 3306) │ │
  │   └───────────────────────────────────────────────┘ │
  └─────────────────────────────────────────────────────┘
```

Trois choix se cachent dans ce schéma, et ils sont volontaires :

- **Un réseau créé par vous** : un **réseau** relie des conteneurs entre eux. Sur un réseau que vous créez, un conteneur en trouve un autre par son nom, ce qu'on appelle **résoudre un nom**. Le réseau où arrivent les conteneurs par défaut ne le fait pas.
- **Un seul port publié** : seule l'application doit être joignable depuis l'hôte. La base ne publie rien, car l'application la joint par le réseau.
- **Un nom générique, `mysql`** : c'est un **alias**, un nom de plus pour le conteneur sur ce réseau. Si vous remplacez le conteneur de la base, l'application n'a rien à changer.

Ce lab prend deux raccourcis, à ne pas reproduire en production. Les mots de passe sont écrits en clair dans la commande, ce que traite un prochain cours sur les secrets. Et la base a une limite importante, que vous découvrirez à la fin du lab.

# Préparer l'application

## Récupérer le code

Ce code est sur GitHub, et vous en prenez la même version précise que dans le lab « Conteneuriser une application pas à pas » : le commit `6b025fc5`, c'est-à-dire un état enregistré du code, pour que ce lab fonctionne encore quand le dépôt évoluera. Vous créez un dossier, puis `curl` télécharge l'archive et le `|` la passe à `tar`, qui la décompresse dedans. `-sSL` n'affiche que les erreurs et suit les redirections de GitHub, et `--strip-components=1` retire le dossier de premier niveau que contient l'archive.

```exec
mkdir -p ~/layers-l5/app
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C ~/layers-l5/app
```

## Écrire le Dockerfile

Le dépôt ne contient pas de Dockerfile. Vous prenez ici celui du lab « Conteneuriser une application pas à pas », redonné tel quel, car le sujet est le réseau. Copiez cette commande : elle crée le fichier `Dockerfile` à la racine du projet avec ces huit lignes. `<<'EOF'` recopie dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` :

```exec
cat > ~/layers-l5/app/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
RUN mkdir -p /etc/todos && chown node /etc/todos
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
EOF
```

Pour mémoire, l'image part de Node.js 22 sur Alpine, copie le code, installe les dépendances de production, prépare un dossier pour l'utilisateur `node`, qui n'est pas administrateur, puis lance `node src/index.js`, un serveur qui écoute sur le port 3000.

## Construire l'image

🚧 **À compléter** : construisez l'image à partir du dossier `~/layers-l5/app`, sous le nom et le tag `layers-l5-todo:1.0`. Remplacez le `# TODO` par l'option qui donne un nom et un tag à l'image, sur une seule ligne :

```bash
docker build # TODO : l'option, le nom et le tag de l'image, puis le dossier
```

La première construction peut prendre jusqu'à une minute, le temps de télécharger les dépendances.

```hint
L'option `-t <nom>:<tag>` donne un nom et un tag à l'image construite. La commande tient sur une ligne : `docker build -t <nom>:<tag> <dossier>`.
```

```verify
if ! docker image inspect layers-l5-todo:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l5-todo:1.0 n'existe pas. Construisez-la avec le nom demandé."
  exit 1
fi
CMD=$(docker image inspect layers-l5-todo:1.0 --format '{{json .Config.Cmd}}')
case "$CMD" in
  *src/index.js*) : ;;
  *) echo "L'image layers-l5-todo:1.0 ne lance pas src/index.js (trouvé : $CMD). Construisez-la depuis ~/layers-l5/app."; exit 1 ;;
esac
echo "L'image layers-l5-todo:1.0 est prête."
```

````solution
```bash
docker build -t layers-l5-todo:1.0 ~/layers-l5/app
```
````

# Démarrer la base de données

## Créer le réseau

Deux conteneurs ne se joignent par leur nom que sur un réseau que vous avez créé. La commande `docker network create <nom>` s'en charge. Elle choisit par défaut le **pilote** `bridge`, c'est-à-dire le type de réseau qu'il vous faut, un commutateur virtuel sur cette machine.

🚧 **À compléter** : créez le réseau `layers-l5-net`.

```bash
# TODO : une seule commande, pour créer le réseau layers-l5-net
```

```verify
if [ "$(docker network inspect layers-l5-net --format '{{.Driver}}' 2>/dev/null)" != "bridge" ]; then
  echo "Le réseau layers-l5-net n'existe pas, ou n'utilise pas le pilote bridge."
  exit 1
fi
echo "Le réseau layers-l5-net existe."
```

````solution
```bash
docker network create layers-l5-net
```
````

## Lancer MySQL

L'image `mysql:8.4` crée sa base et ses utilisateurs au premier démarrage, d'après ses variables d'environnement. Le tableau donne les deux options de réseau et les quatre variables utiles, avec les valeurs à utiliser :

| Option | Rôle |
|---|---|
| `--network layers-l5-net` | branche le conteneur sur votre réseau |
| `--network-alias mysql` | ajoute le nom `mysql`, valable sur ce réseau |
| `-e MYSQL_ROOT_PASSWORD=rootsecret` | le mot de passe de l'administrateur de MySQL, obligatoire |
| `-e MYSQL_DATABASE=todos` | crée la base `todos` |
| `-e MYSQL_USER=todos` | crée un utilisateur `todos`, qui n'a de droits que sur cette base |
| `-e MYSQL_PASSWORD=secret` | son mot de passe |

L'application utilisera cet utilisateur limité plutôt que l'administrateur, pour ne lui donner que les droits dont elle a besoin. Aucun `-p` n'apparaît dans ce tableau, car seule l'application doit joindre la base.

🚧 **À compléter** : remplacez chaque ligne `# TODO` par les options du tableau, et finissez chaque ligne par `\`, qui prolonge la commande sur la ligne suivante.

```bash
docker run -d --name layers-l5-db \
  # TODO : les deux options de réseau
  # TODO : les quatre variables d'environnement
  mysql:8.4
```

```hint
Une variable d'environnement s'écrit `-e NOM=valeur`, et on répète `-e` pour chacune.
```

```verify
C=layers-l5-db
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C ne tourne pas. Lisez la raison avec docker logs $C, supprimez-le avec docker rm -f -v $C (ce -v supprime aussi le stockage créé par l'image), puis recommencez."
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  mysql:8.4) : ;;
  *) echo "$C n'utilise pas l'image mysql:8.4."; exit 1 ;;
esac
ENVS=$(docker container inspect "$C" --format '{{range .Config.Env}}{{.}} {{end}}')
for V in MYSQL_ROOT_PASSWORD=rootsecret MYSQL_DATABASE=todos MYSQL_USER=todos MYSQL_PASSWORD=secret; do
  case " $ENVS" in
    *" $V "*) : ;;
    *) echo "Il manque la variable $V. Une variable se fixe à la création : docker rm -f -v $C (ce -v supprime aussi le stockage créé par l'image), puis recommencez."; exit 1 ;;
  esac
done
NETS=$(docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}')
case "$NETS" in
  *layers-l5-net*) : ;;
  *) echo "$C n'est pas sur le réseau layers-l5-net (trouvé : $NETS). docker rm -f -v $C, puis recommencez avec --network."; exit 1 ;;
esac
if ! docker container inspect "$C" --format '{{range .NetworkSettings.Networks}}{{.Aliases}}{{end}}' | grep -qw mysql; then
  echo "$C n'a pas l'alias mysql. docker rm -f -v $C, puis recommencez avec --network-alias."
  exit 1
fi
if [ -n "$(docker port "$C")" ]; then
  echo "$C publie un port : la base n'a pas à être joignable depuis l'hôte. docker rm -f -v $C, puis recommencez sans -p."
  exit 1
fi
echo "MySQL tourne sur layers-l5-net, avec le nom mysql et sans port publié."
```

````solution
```bash
docker run -d --name layers-l5-db \
  --network layers-l5-net \
  --network-alias mysql \
  -e MYSQL_ROOT_PASSWORD=rootsecret \
  -e MYSQL_DATABASE=todos \
  -e MYSQL_USER=todos \
  -e MYSQL_PASSWORD=secret \
  mysql:8.4
```
````

## Attendre que MySQL soit prêt

Le conteneur tourne, mais le serveur n'est pas encore prêt : au premier démarrage, MySQL initialise ses fichiers, ce qui prend de quelques secondes à une demi-minute. Or l'application n'attend sa base que 10 secondes avant d'abandonner. Il vaut donc mieux attendre avant de la lancer.

`mysqladmin ping` demande au serveur s'il répond, avec l'utilisateur donné par `-u` et le mot de passe collé à `-p`. `--silent` réduit la sortie. `-h 127.0.0.1` force une connexion par le port réseau du conteneur : pendant l'initialisation, MySQL n'y répond pas encore, et ce test ne réussit donc que lorsque le vrai serveur est prêt. `until … do … done` répète la commande jusqu'à ce qu'elle réussisse, et `2>/dev/null` masque les erreurs d'attente :

```exec
until docker exec layers-l5-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent 2>/dev/null; do sleep 2; done
```

Vous lisez `mysqld is alive`. Si la commande tourne plus de deux minutes, interrompez-la avec **Ctrl+C** et lisez `docker logs layers-l5-db`.

# Démarrer l'application

## 🧪 Manip : pourquoi pas localhost ?

L'application doit savoir où trouver sa base. Avant de lui donner la bonne réponse, essayez la réponse la plus tentante : `MYSQL_HOST=localhost`. Lancez ce conteneur d'essai sur le même réseau que la base :

```exec
docker run -d --name layers-l5-essai --network layers-l5-net -e MYSQL_HOST=localhost -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret -e MYSQL_DB=todos layers-l5-todo:1.0
```

`docker wait` attend que le conteneur s'arrête, puis affiche son code de sortie. Comptez une dizaine de secondes, le temps que l'application abandonne. `grep` ne garde que la ligne d'erreur des logs :

```exec
docker wait layers-l5-essai
docker logs layers-l5-essai 2>&1 | grep -m1 '127.0.0.1:3306'
```

Vous lisez le code `1`, puis une ligne contenant `ECONNREFUSED 127.0.0.1:3306`. L'application a bien cherché MySQL, mais sur **son propre** localhost, où rien n'écoute sur ce port : dans un conteneur, localhost désigne ce conteneur. La bonne réponse est le nom que vous avez donné à la base sur le réseau. Supprimez cet essai :

```exec
docker rm layers-l5-essai
```

## Lancer l'application

Voici les options qui restent. Les quatre variables sont celles que lit `getting-started-app`, et leurs valeurs doivent correspondre à ce que vous avez donné à MySQL :

| Option | Rôle |
|---|---|
| `-p 28355:3000` | le port 28355 de l'hôte mène au port 3000 du conteneur : d'abord l'hôte, ensuite le conteneur |
| `-e MYSQL_HOST=…` | où trouver la base : le nom déclaré sur le réseau |
| `-e MYSQL_USER=…` | l'utilisateur limité de MySQL |
| `-e MYSQL_PASSWORD=…` | son mot de passe |
| `-e MYSQL_DB=…` | le nom de la base |

🚧 **À compléter** : lancez l'application sous le nom `layers-l5-todo`, sur le même réseau que la base.

```bash
docker run -d --name layers-l5-todo \
  # TODO : le réseau
  # TODO : le port publié
  # TODO : les quatre variables d'environnement
  layers-l5-todo:1.0
```

```hint
Sans `MYSQL_HOST`, l'application démarre quand même, mais sur son fichier SQLite interne : les logs disent alors `Using sqlite database`.
```

```hint
`MYSQL_HOST` prend l'alias que vous avez donné à la base, `mysql`. Les autres valeurs sont dans le tableau de MySQL : `todos`, `secret`, `todos`.
```

```verify
C=layers-l5-todo
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas."
  exit 1
fi
if ! docker port "$C" 3000 2>/dev/null | grep -q ':28355$'; then
  if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" = "true" ]; then
    echo "Le port 28355 de l'hôte ne mène pas au port 3000 de $C. docker rm -f $C, puis recommencez."
    exit 1
  fi
fi
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  [ "$(docker container inspect "$C" --format '{{.State.Running}}')" = "true" ] || break
  docker logs "$C" 2>&1 | grep -q 'Listening on port' && break
  sleep 2
done
LOGS=$(docker logs "$C" 2>&1)
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C s'est arrêté. Voici la fin de ses logs :"
  echo "$LOGS" | grep -m2 -E 'ECONNREFUSED|ENOTFOUND|Access denied|Unknown database'
  echo "Corrigez votre commande : docker rm -f $C, puis recommencez."
  exit 1
fi
case "$LOGS" in
  *"Using sqlite"*) echo "L'application utilise son fichier SQLite interne : elle n'a pas reçu MYSQL_HOST. docker rm -f $C, puis recommencez."; exit 1 ;;
esac
case "$LOGS" in
  *"Connected to mysql db"*) : ;;
  *) echo "L'application n'indique pas être connectée à MySQL. Lisez docker logs $C."; exit 1 ;;
esac
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28355/items | grep -q '^\['; then
  echo "L'application ne répond pas sur http://localhost:28355/items."
  exit 1
fi
echo "L'application tourne, elle parle à MySQL et répond sur le port 28355."
```

````solution
```bash
docker run -d --name layers-l5-todo \
  --network layers-l5-net \
  -p 28355:3000 \
  -e MYSQL_HOST=mysql \
  -e MYSQL_USER=todos \
  -e MYSQL_PASSWORD=secret \
  -e MYSQL_DB=todos \
  layers-l5-todo:1.0
```
````

# Vérifier de bout en bout

## Ajouter une tâche, et la retrouver dans la base

L'application répond à des requêtes HTTP. Ajoutez une tâche en lui envoyant un message JSON, comme le fait sa page web. `-X POST` demande un ajout, `-H` indique le format du message, et `-d` donne son contenu. La seconde commande relit ensuite la liste :

```exec
curl -sS -X POST -H 'Content-Type: application/json' -d '{"name":"Acheter du pain"}' http://localhost:28355/items
curl -sS http://localhost:28355/items
```

Vous lisez votre tâche en JSON, deux fois sur la même ligne : d'abord seule, en réponse à l'ajout, puis dans une liste entre crochets. Vous pouvez aussi ouvrir `http://localhost:28355` dans un navigateur pour voir la page. Sur un poste hébergé, utilisez l'onglet **PORTS** de VS Code, qui donne le lien de ce port.

🚧 **À compléter** : prouvez que la tâche est bien dans MySQL et non dans l'application. Le client `mysql` de l'image prend un utilisateur (`-u`), un mot de passe (`-p`, collé à sa valeur), le nom de la base, seul et sans option, puis une requête (`-e`, suivi de la requête entre apostrophes). La requête à lancer est `SELECT name FROM todo_items`, et la sortie doit aller dans le fichier `~/layers-l5/todos.txt`.

```bash
docker exec layers-l5-db mysql # TODO : l'utilisateur, le mot de passe, la base, la requête, puis la redirection
```

MySQL signale `Using a password on the command line interface can be insecure` : c'est vrai, et c'est le raccourci annoncé au départ.

```hint
La redirection `> ~/layers-l5/todos.txt` s'écrit à la fin de la commande, et elle s'exécute sur votre machine, ce que vous voulez ici.
```

```verify
if ! docker exec layers-l5-db mysql -u todos -psecret todos -e 'SELECT name FROM todo_items' 2>/dev/null | grep -q 'Acheter du pain'; then
  echo "La tâche Acheter du pain n'est pas dans la table todo_items. Lancez d'abord la commande curl de cette section."
  exit 1
fi
if ! grep -q 'Acheter du pain' "$HOME/layers-l5/todos.txt" 2>/dev/null; then
  echo "Le fichier ~/layers-l5/todos.txt ne contient pas la tâche. Redirigez-y la sortie de la requête."
  exit 1
fi
echo "La tâche est dans MySQL, et sa trace dans votre fichier."
```

````solution
```bash
docker exec layers-l5-db mysql -u todos -psecret todos -e 'SELECT name FROM todo_items' > ~/layers-l5/todos.txt
```
````

## Ce que donne ce nom, et pour qui

L'application a trouvé MySQL par le nom `mysql`. Voyez ce que donne ce nom, d'abord depuis un conteneur du réseau. `getent hosts` affiche l'adresse IP qui correspond à un nom :

```exec
docker exec layers-l5-todo getent hosts mysql
```

Vous lisez une adresse, suivie du nom. Depuis un conteneur placé hors de ce réseau, le même nom n'existe pas, et la commande n'affiche rien. `echo $?` montre son code de sortie, ici `2` :

```exec
docker run --rm alpine:3.22 getent hosts mysql; echo $?
```

# Constater la limite

## Supprimer la base

Une dernière expérience met le doigt sur le raccourci de ce lab. Supprimez le conteneur de la base. L'image `mysql:8.4` crée d'elle-même un **volume anonyme**, un espace de stockage sans nom, pour ses fichiers : `-v` le supprime en même temps que le conteneur, sinon il resterait sur votre disque.

```exec
docker rm -f -v layers-l5-db
curl -sS http://localhost:28355/items
```

L'application tourne encore, mais elle répond par une page d'erreur contenant `getaddrinfo ENOTFOUND mysql` : le nom a disparu du réseau avec le conteneur.

## Recréer la base

🚧 **À compléter** : remettez le service en route, en trois gestes. Pour le dernier, `docker restart <conteneur>` redémarre un conteneur sans le recréer.

```bash
# TODO : recréer layers-l5-db avec exactement la même commande qu'à l'étape « Lancer MySQL »
# TODO : attendre que MySQL soit prêt, avec la commande de l'étape « Attendre que MySQL soit prêt »
# TODO : redémarrer layers-l5-todo, car l'application ne crée sa table qu'à son démarrage
```

Avant de vérifier, faites une prévision : la tâche `Acheter du pain` sera-t-elle encore là ? Demandez ensuite la liste :

```exec
curl -sS http://localhost:28355/items
```

```hint
Sans le redémarrage, l'application répond par une page d'erreur : la table `todos.todo_items` n'existe pas.
```

```verify
if [ "$(docker inspect layers-l5-db --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l5-db ne tourne pas. Recréez-le avec la commande de l'étape « Lancer MySQL »."
  exit 1
fi
LISTE=$(curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28355/items)
case "$LISTE" in
  *"Acheter du pain"*) echo "La tâche est encore là : layers-l5-db n'a pas été supprimé et recréé. Supprimez-le et recréez-le, comme l'indique cette étape."; exit 1 ;;
  *todo_items*) echo "L'application ne trouve plus sa table : redémarrez layers-l5-todo, qui la crée à son démarrage."; exit 1 ;;
  "[]") : ;;
  *) echo "L'application ne renvoie pas une liste vide. Attendez que MySQL soit prêt, redémarrez layers-l5-todo, puis réessayez."; exit 1 ;;
esac
echo "La liste est vide : les données sont parties avec le conteneur."
```

````solution
```bash
docker run -d --name layers-l5-db --network layers-l5-net --network-alias mysql -e MYSQL_ROOT_PASSWORD=rootsecret -e MYSQL_DATABASE=todos -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret mysql:8.4
until docker exec layers-l5-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent 2>/dev/null; do sleep 2; done
docker restart layers-l5-todo
```
````

La liste est vide : `[]`. Le nom a suffi à retrouver le service, sans changer la configuration de l'application, mais les données sont perdues. Un conteneur se remplace facilement, ce qui ne convient pas à une base telle que vous l'avez lancée. C'est le sujet d'un prochain cours, « Garder ses données ».

# Nettoyer

## Ne rien laisser

🚧 **À compléter** : supprimez tout ce que ce lab a créé, dans le bon ordre, car un réseau occupé ne se supprime pas. Il s'agit des conteneurs `layers-l5-todo` et `layers-l5-db`, avec le volume anonyme de la base, du réseau `layers-l5-net`, de l'image `layers-l5-todo:1.0` et du dossier `~/layers-l5`. La vérification ne peut pas reconnaître un volume anonyme oublié : pensez bien au `-v`.

```bash
# TODO : les conteneurs, avec leur volume anonyme
# TODO : le réseau
# TODO : l'image
# TODO : le dossier
```

```hint
`docker rm -f -v` pour les conteneurs, `docker network rm`, `docker rmi` pour l'image, et `rm -rf` pour le dossier, en relisant bien le chemin.
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(todo|db|essai)$')" ]; then
  echo "Il reste des conteneurs layers-l5-."
  exit 1
fi
if docker network inspect layers-l5-net >/dev/null 2>&1; then
  echo "Le réseau layers-l5-net existe encore."
  exit 1
fi
if docker image inspect layers-l5-todo:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l5-todo:1.0 existe encore."
  exit 1
fi
if [ -e "$HOME/layers-l5" ]; then
  echo "Le dossier ~/layers-l5 existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
docker rm -f -v layers-l5-todo layers-l5-db
docker network rm layers-l5-net
docker rmi layers-l5-todo:1.0
rm -rf ~/layers-l5
```
````

## Récap

- Un réseau créé par vous résout les noms : l'application joint la base par `mysql`, jamais par une adresse IP.
- Dans un conteneur, localhost désigne ce conteneur : il ne mène pas à une base placée dans un autre.
- Seul ce qui doit être joignable depuis l'hôte publie un port.
- Une base lancée comme ici perd ses données quand son conteneur est supprimé.

Le dossier `solution/` du dépôt de ce cours, à côté de `.layers/`, garde le Dockerfile et un script `run.sh` qui rejoue tout le lab.

> 📖 [Applications à plusieurs conteneurs](https://docs.docker.com/get-started/workshop/07_multi_container/) · [`docker network create`](https://docs.docker.com/reference/cli/docker/network/create/) · [L'image `mysql` et ses variables](https://hub.docker.com/_/mysql) · [Le code de `getting-started-app`](https://github.com/docker/getting-started-app/tree/6b025fc5)

Pour vous tester sans guide, faites d'abord le cours « Relier des conteneurs et publier un port », puis le challenge « Isoler et relier des conteneurs, sans guide ».
