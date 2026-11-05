---
title: "getting-started-app en Compose"
description: "Pas à pas, avec des blancs à compléter : décrire une application Node et sa base MySQL dans un fichier Compose, puis prouver que les données survivent."
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

Vous allez décrire une vraie application dans un fichier Compose : `getting-started-app`, une liste de tâches écrite en Node.js, et sa base de données MySQL. Plus de longues commandes `docker run` à retenir : une seule description, et une commande pour la faire exister.

Ce lab ne vous donne pas le fichier complet. Vous le **construisez** en remplaçant des lignes `# TODO`, à partir de ce que le texte vient d'expliquer. Le bouton de vérification contrôle le résultat, les indices se dévoilent un par un, et la solution reste en dernier recours.

**Niveau** : débutant sur Compose. Vous savez construire une image, relier des conteneurs et garder des données dans un volume : ce sont les cours « Écrire le Dockerfile d'une application », « Relier des conteneurs et publier un port » et « Garder ses données : volumes et bind mounts ». Le lab n'en suppose rien d'autre : chaque clé de Compose est expliquée quand elle arrive.

**Ce qu'il faut** : Docker qui répond à `docker ps`, Compose qui répond à `docker compose version`, `curl`, un éditeur de texte et le port **28371** libre. Tout ce que vous créez porte le préfixe `layers-l7-`, et vos fichiers vivent dans `~/layers-l7/todo`. La vérification y garde aussi un fichier caché, `.mysql-id`, qui lui sert à reconnaître votre conteneur.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Préparer le projet

## Récupérer l'application

C'est la même application que dans le lab « Conteneuriser une application pas à pas », à la même version, le commit `6b025fc5`, pour que ce lab fonctionne encore quand le dépôt évoluera. Vous créez un dossier, puis `curl` télécharge l'archive et le `|` la passe à `tar`, qui la décompresse dedans. `-sSL` n'affiche que les erreurs et suit les redirections de GitHub, et `--strip-components=1` retire le dossier de premier niveau que contient l'archive.

```exec
mkdir -p ~/layers-l7/todo
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C ~/layers-l7/todo
ls ~/layers-l7/todo
```

Vous devez voir `package.json` et `src`, le code de l'application.

## Le Dockerfile

Le dépôt ne contient pas de Dockerfile. Vous prenez ici celui du lab « Conteneuriser une application pas à pas », redonné tel quel, car le sujet est Compose. Copiez cette commande : elle crée le fichier `Dockerfile` à la racine du projet avec ces huit lignes. `<<'EOF'` recopie dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` :

```exec
cat > ~/layers-l7/todo/Dockerfile <<'EOF'
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

Pour mémoire, l'image part de Node.js 22 sur Alpine, copie le code, installe les dépendances de production, prépare un dossier pour l'utilisateur `node`, qui n'est pas administrateur, puis lance `node src/index.js`, un serveur qui écoute sur le port 3000. Vous n'avez rien de plus à faire sur l'image dans ce lab.

```ack
J'ai le code et le Dockerfile dans ~/layers-l7/todo
```

# L'application seule

## Écrire le fichier

Un fichier Compose s'écrit en **YAML** : des lignes `clé: valeur`, où le décalage vers la droite (deux espaces, jamais une tabulation) dit ce qui appartient à quoi, et où `- ` marque un élément de liste. Il décrit un **projet**, composé de **services**, un service étant un conteneur désigné par son rôle dans l'application.

Commencez sans base de données : si aucune base n'est configurée, l'application range ses données dans un petit fichier, à l'intérieur du conteneur. Créez le fichier de départ, avec ses deux blancs :

```exec
cat > ~/layers-l7/todo/compose.yaml <<'EOF'
name: layers-l7-todo
services:
  app:
    # TODO : construire l'image à partir du Dockerfile de ce dossier
    # TODO : publier le port 28371 de la machine vers le port 3000 du conteneur
EOF
```

Ouvrez `~/layers-l7/todo/compose.yaml` dans votre éditeur et remplacez les deux lignes `# TODO` à l'aide de ce tableau :

| Clé | Rôle | Forme |
|---|---|---|
| `name` | le nom du projet, qui préfixe tout ce que Compose crée | déjà écrite |
| `build` | construit l'image à partir du `Dockerfile` du dossier indiqué ; `.` désigne le dossier du fichier Compose | une valeur |
| `ports` | publie des ports, comme `-p` : `port-machine:port-conteneur`, entre guillemets | une liste |

Ces clés s'écrivent au même décalage, quatre espaces, sous `app:`.

## Lancer

`docker compose up` fait exister ce que le fichier décrit. `-d` le laisse tourner en arrière-plan, et `--build` construit l'image d'abord. Cette commande commence par `cd`, car Compose cherche `compose.yaml` dans le dossier courant. Le premier lancement peut prendre une minute, le temps d'installer les dépendances :

```exec
cd ~/layers-l7/todo && docker compose up -d --build
```

Demandez ensuite la liste des tâches. `/items` est l'adresse que l'application réserve à ses données, et `--retry` patiente le temps que le serveur démarre :

```exec
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28371/items
```

Vous devez lire `[]`, une liste vide. Pour voir l'interface, ouvrez `http://localhost:28371` dans un navigateur, ou, sur un poste hébergé, passez par l'onglet **PORTS** de VS Code.

```hint
`build` prend une seule valeur : le dossier qui contient le Dockerfile, celui du fichier Compose.
```

```hint
Une liste YAML s'écrit avec un tiret, une ligne plus bas et deux espaces plus à droite que sa clé. Le port de la machine vient en premier.
```

```verify
C=layers-l7-todo-app-1
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas. Remplacez les TODO, puis lancez docker compose up -d --build dans ~/layers-l7/todo."
  echo "Pour lire l'erreur de Compose : cd ~/layers-l7/todo && docker compose config"
  exit 1
fi
if [ "$(docker inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C ne tourne pas. Lisez : docker compose logs app"
  exit 1
fi
MAP=$(docker port "$C" 3000/tcp 2>/dev/null)
case "$MAP" in
  *:28371*) : ;;
  *) echo "Le port 28371 de la machine ne mène pas au port 3000 du conteneur (trouvé : ${MAP:-aucun}). Rappel : port-machine:port-conteneur."; exit 1 ;;
esac
case "$(docker inspect "$C" --format '{{.Config.Image}}')" in
  node:*) echo "L'image de app ne vient pas de votre Dockerfile : utilisez la clé build, pas image."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://localhost:28371/items | grep -q '^\['; then
  echo "L'application ne répond pas sur http://localhost:28371/items. Attendez quelques secondes, ou lisez : docker compose logs app"
  exit 1
fi
echo "L'application tourne, construite et publiée par Compose."
```

````solution
Le fichier complet à cette étape, écrit par une commande, suivi du lancement :

```bash
cat > ~/layers-l7/todo/compose.yaml <<'EOF'
name: layers-l7-todo
services:
  app:
    build: .
    ports:
      - "28371:3000"
EOF
cd ~/layers-l7/todo && docker compose up -d --build
sleep 2
```
````

# Ajouter la base de données

## Deux services sur un même réseau

Pour l'instant, les tâches meurent avec le conteneur. L'application sait aussi utiliser MySQL : elle bascule dès que la variable d'environnement `MYSQL_HOST` existe, et lit ses réglages dans trois autres variables. Il vous faut donc un second service.

Vous n'avez pas à créer de réseau : Compose en fait un pour le projet et y place tous les services. Comme dans « Relier des conteneurs et publier un port », un conteneur en joint un autre **par son nom**, et ce nom est ici celui du service. Le service de la base ne publie aucun port : seule l'application lui parle.

Voici les clés qui arrivent :

| Clé | Rôle |
|---|---|
| `image` | l'image d'un service qui n'a rien à construire |
| `environment` | ses variables d'environnement, comme `-e`, sous la forme `NOM: valeur` |
| `depends_on` | une liste de services à démarrer avant celui-ci |
| `restart: on-failure` | relance le conteneur quand il s'arrête sur une erreur |

Les variables à donner viennent de la documentation de chaque image ou application :

| Service | Variable | Valeur attendue |
|---|---|---|
| `app` | `MYSQL_HOST` | l'adresse de la base, donc le nom de son service |
| `app` | `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DB` | déjà écrites ci-dessous |
| `mysql` | `MYSQL_ROOT_PASSWORD` | le mot de passe de l'administrateur `root`, le même que `MYSQL_PASSWORD` |
| `mysql` | `MYSQL_DATABASE` | la base à créer au premier démarrage, déjà écrite |

Pourquoi `restart: on-failure` ? `depends_on` règle seulement l'ordre de **démarrage** : il n'attend pas que MySQL soit prêt, et MySQL met plusieurs secondes à s'initialiser. L'application attend sa base 10 secondes. Si MySQL n'est toujours pas prêt, elle s'arrête sur une erreur, Docker la relance, et elle finit par se connecter. C'est un raccourci assumé : un prochain cours montre comment attendre vraiment qu'un service soit prêt.

## Compléter le fichier

Remplacez tout le contenu de `compose.yaml` dans votre éditeur par ce qui suit, puis complétez les quatre `# TODO` :

```yaml
name: layers-l7-todo
services:
  app:
    build: .
    ports:
      - "28371:3000"
    environment:
      # TODO : MYSQL_HOST, l'adresse de la base
      MYSQL_USER: root
      MYSQL_PASSWORD: secret
      MYSQL_DB: todos
    # TODO : démarrer le service mysql avant celui-ci
    restart: on-failure
  mysql:
    # TODO : l'image mysql, en version 8.4
    environment:
      # TODO : le mot de passe de root
      MYSQL_DATABASE: todos
```

Le mot de passe écrit en clair est un autre raccourci, à ne pas reproduire sur un serveur : un prochain cours montre où ranger un secret.

Appliquez le fichier. `up` compare ce qui tourne à ce que vous décrivez : il recrée `app`, dont la configuration a changé, et crée `mysql`. L'image existe déjà, `--build` n'est donc plus utile.

```exec
cd ~/layers-l7/todo && docker compose up -d
```

Ajoutez une tâche quand l'application est prête. `-X POST` envoie une création, `-H` dit que le corps est au format JSON, et `-d` donne ce corps. Pendant que MySQL s'initialise, la commande réessaie : elle peut prendre une trentaine de secondes.

```exec
curl -s --retry 20 --retry-delay 2 --retry-all-errors -X POST -H 'Content-Type: application/json' -d '{"name":"Apprendre Compose"}' http://localhost:28371/items
```

Vous devez lire un objet JSON avec un `id` et le nom de votre tâche. Regardez-la maintenant dans MySQL, depuis son service. `docker compose exec` lance une commande dans un service qui tourne. Le client `mysql` reçoit l'utilisateur avec `-uroot`, le mot de passe avec `-psecret`, collé à l'option, le nom de la base, `todos`, et avec `-e` une requête SQL qui lit le nom des tâches. MySQL vous prévient que ce mot de passe en clair n'est pas prudent, et il a raison : cela reste ici un essai sur votre poste. Vous devez lire `Apprendre Compose`.

```exec
cd ~/layers-l7/todo && docker compose exec mysql mysql -uroot -psecret todos -e 'SELECT name FROM todo_items'
```

```hint
L'adresse de la base est le nom que vous donnez à son service dans ce fichier : `mysql`.
```

```hint
`depends_on` prend une liste, comme `ports`, et se place au même décalage que `environment`. L'image s'écrit `image: nom:version`.
```

```verify
A=layers-l7-todo-app-1; M=layers-l7-todo-mysql-1
if ! docker container inspect "$M" >/dev/null 2>&1; then
  echo "Il n'y a pas de service mysql dans le projet layers-l7-todo. Complétez le fichier, puis lancez docker compose up -d."
  exit 1
fi
case "$(docker inspect "$M" --format '{{.Config.Image}}')" in
  mysql:8.4*) : ;;
  *) echo "Le service mysql doit utiliser l'image mysql:8.4 (trouvé : $(docker inspect "$M" --format '{{.Config.Image}}'))."; exit 1 ;;
esac
if [ "$(docker inspect "$M" --format '{{.State.Running}}')" != "true" ]; then
  echo "mysql ne tourne pas. Sans MYSQL_ROOT_PASSWORD, il refuse de démarrer. Lisez : docker compose logs mysql"
  exit 1
fi
if ! docker inspect "$A" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -q '^MYSQL_HOST=mysql$'; then
  echo "L'application n'a pas MYSQL_HOST=mysql. Vérifiez son bloc environment, puis relancez docker compose up -d."
  exit 1
fi
case "$(docker inspect "$A" --format '{{index .Config.Labels "com.docker.compose.depends_on"}}')" in
  *mysql*) : ;;
  *) echo "app ne dépend pas de mysql : il manque le depends_on."; exit 1 ;;
esac
if [ "$(docker inspect "$A" --format '{{.HostConfig.RestartPolicy.Name}}')" != "on-failure" ]; then
  echo "app n'a pas la politique restart: on-failure."
  exit 1
fi
if [ -n "$(docker port "$M")" ]; then
  echo "mysql publie un port alors que seule l'application lui parle : retirez sa clé ports."
  exit 1
fi
N=$(docker exec "$M" mysql -uroot -psecret todos -N -e 'SELECT COUNT(*) FROM todo_items' 2>/dev/null)
if [ -z "$N" ] || [ "$N" -lt 1 ]; then
  echo "Aucune tâche dans MySQL (trouvé : ${N:-pas de réponse}). MySQL est peut-être encore en train de s'initialiser : ajoutez une tâche avec la commande curl, puis réessayez."
  exit 1
fi
echo "L'application et MySQL se parlent : $N tâche(s) dans la base."
```

````solution
Le fichier complet à cette étape, le lancement, puis une première tâche :

```bash
cat > ~/layers-l7/todo/compose.yaml <<'EOF'
name: layers-l7-todo
services:
  app:
    build: .
    ports:
      - "28371:3000"
    environment:
      MYSQL_HOST: mysql
      MYSQL_USER: root
      MYSQL_PASSWORD: secret
      MYSQL_DB: todos
    depends_on:
      - mysql
    restart: on-failure
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: todos
EOF
cd ~/layers-l7/todo && docker compose up -d
curl -s --retry 20 --retry-delay 2 --retry-all-errors -X POST -H 'Content-Type: application/json' -d '{"name":"Apprendre Compose"}' http://localhost:28371/items
```
````

# Garder les données

## Déclarer un volume

Vos tâches sont maintenant dans MySQL, mais MySQL range ses fichiers dans `/var/lib/mysql`, et rien de ce que vous avez écrit ne les protège. Comme le montre « Garder ses données : volumes et bind mounts », ce qui doit durer va dans un volume.

Dans Compose, un volume nommé demande deux choses :

| Où | Quoi | Rôle |
|---|---|---|
| dans le service, clé `volumes` | une liste de `nom-du-volume:dossier-du-conteneur` | monte le volume dans le conteneur |
| en bas du fichier, au même décalage que `services`, clé `volumes` | le nom du volume suivi de `:` et de rien d'autre | le déclare, et Compose le crée au premier `up` |

Complétez `compose.yaml` avec un volume appelé `todo-data`, monté là où MySQL écrit. Voici les deux endroits à modifier :

```yaml
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: todos
    # TODO : monter le volume todo-data sur /var/lib/mysql

# TODO : déclarer le volume todo-data
```

Repartez d'une base vide : la table des tâches n'existera dans le nouveau volume qu'après un redémarrage de l'application. `docker compose down` supprime les conteneurs et le réseau du projet, et `-v` supprime aussi ses volumes, y compris celui, sans nom, que l'image de MySQL avait demandé d'elle-même. Rien d'utile n'y reste :

```exec
cd ~/layers-l7/todo && docker compose down -v && docker compose up -d
```

Ajoutez une tâche dans cette nouvelle base :

```exec
curl -s --retry 20 --retry-delay 2 --retry-all-errors -X POST -H 'Content-Type: application/json' -d '{"name":"Survivre à un down"}' http://localhost:28371/items
```

```hint
Dans le service : `volumes:`, puis une ligne `- todo-data:/var/lib/mysql`. La déclaration en bas du fichier s'écrit sur deux lignes : `volumes:` puis, décalé de deux espaces, `todo-data:`.
```

```verify
M=layers-l7-todo-mysql-1
SRC=$(docker inspect "$M" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Type}}:{{.Name}}{{end}}{{end}}' 2>/dev/null)
case "$SRC" in
  volume:layers-l7-todo_todo-data) : ;;
  *) echo "mysql n'a pas le volume nommé todo-data sur /var/lib/mysql (trouvé : ${SRC:-rien}). Complétez le fichier, puis lancez la commande down -v et up -d."
     exit 1 ;;
esac
if ! docker exec "$M" mysql -uroot -psecret todos -N -e 'SELECT name FROM todo_items' 2>/dev/null | grep -q 'Survivre'; then
  echo "La tâche « Survivre à un down » n'est pas dans la base. MySQL s'initialise peut-être encore : relancez la commande curl, puis réessayez."
  exit 1
fi
docker inspect "$M" --format '{{.Id}}' > ~/layers-l7/todo/.mysql-id
echo "Le volume $SRC est monté et contient votre tâche."
```

````solution
Le fichier complet, solution finale du lab, puis les deux commandes de cette section :

```bash
cat > ~/layers-l7/todo/compose.yaml <<'EOF'
name: layers-l7-todo
services:
  app:
    build: .
    ports:
      - "28371:3000"
    environment:
      MYSQL_HOST: mysql
      MYSQL_USER: root
      MYSQL_PASSWORD: secret
      MYSQL_DB: todos
    depends_on:
      - mysql
    restart: on-failure
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: todos
    volumes:
      - todo-data:/var/lib/mysql
volumes:
  todo-data:
EOF
cd ~/layers-l7/todo && docker compose down -v && docker compose up -d
curl -s --retry 20 --retry-delay 2 --retry-all-errors -X POST -H 'Content-Type: application/json' -d '{"name":"Survivre à un down"}' http://localhost:28371/items
```
````

## Prouver que les données survivent

À vous de faire cette preuve, sans bloc à copier. Vous connaissez les deux commandes : supprimez tous les conteneurs du projet avec `docker compose down`, **sans `-v`**, puis recréez-les avec `docker compose up -d`, depuis le dossier du projet. Redemandez ensuite la liste à `http://localhost:28371/items`, avec `curl`, en laissant à MySQL quelques secondes pour repartir.

Avant de lancer le tout, faites une prévision : votre tâche sera-t-elle là ?

```hint
Vérifiez d'abord avec `docker compose ps -a` que les conteneurs sont revenus. Le volume, lui, n'a jamais disparu : `docker volume ls --filter name=layers-l7-todo` le montre.
```

```verify
M=layers-l7-todo-mysql-1
REF=$(cat ~/layers-l7/todo/.mysql-id 2>/dev/null)
NOW=$(docker inspect "$M" --format '{{.Id}}' 2>/dev/null)
if [ -z "$NOW" ]; then
  echo "Le conteneur $M n'existe pas : après le down, il reste à faire docker compose up -d."
  exit 1
fi
if [ -n "$REF" ] && [ "$REF" = "$NOW" ]; then
  echo "C'est encore le même conteneur mysql : il n'a pas été supprimé. Faites docker compose down, sans -v, puis docker compose up -d."
  exit 1
fi
if ! docker exec "$M" mysql -uroot -psecret todos -N -e 'SELECT name FROM todo_items' 2>/dev/null | grep -q 'Survivre'; then
  echo "La tâche n'est pas dans la base : soit MySQL repart encore, attendez et réessayez, soit le volume a été supprimé par un -v. Dans ce cas, reprenez la section précédente."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28371/items | grep -q 'Survivre'; then
  echo "La tâche est dans la base, mais l'application ne la renvoie pas encore. Attendez quelques secondes, ou lisez : docker compose logs app"
  exit 1
fi
echo "Un nouveau conteneur, la même tâche : le volume a tenu."
```

````solution
```bash
cd ~/layers-l7/todo && docker compose down && docker compose up -d
curl -s --retry 20 --retry-delay 2 --retry-all-errors http://localhost:28371/items
```
````

# Nettoyer

## Ne rien laisser

Dernière chose à trouver seul : supprimez tout ce que ce lab a créé. Doivent disparaître : les conteneurs, le réseau, le volume, l'image construite et le dossier `~/layers-l7/todo`. Compose sait presque tout faire d'une commande : `docker compose down` accepte `-v` pour les volumes et `--rmi local` pour les images qu'il a lui-même construites. Il reste le dossier à effacer avec `rm -rf`, après être sorti du dossier du projet.

```verify
if [ -n "$(docker ps -a --filter name=layers-l7-todo --format '{{.Names}}')" ]; then
  echo "Il reste des conteneurs du projet. Lancez docker compose down -v --rmi local depuis ~/layers-l7/todo."
  exit 1
fi
if [ -n "$(docker network ls --filter name=layers-l7-todo --format '{{.Name}}')" ]; then
  echo "Il reste un réseau du projet : lancez docker compose down depuis ~/layers-l7/todo."
  exit 1
fi
if [ -n "$(docker volume ls --filter name=layers-l7-todo --format '{{.Name}}')" ]; then
  echo "Il reste un volume du projet : docker compose down n'a pas reçu -v."
  exit 1
fi
if docker image inspect layers-l7-todo-app >/dev/null 2>&1; then
  echo "L'image layers-l7-todo-app existe encore : docker rmi layers-l7-todo-app."
  exit 1
fi
if [ -e "$HOME/layers-l7/todo" ]; then
  echo "Le dossier ~/layers-l7/todo existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
cd ~/layers-l7/todo && docker compose down -v --rmi local
cd ~ && rm -rf ~/layers-l7/todo
```
````

## Récap

- Une seule description remplace le réseau, le volume et les longs `docker run` : `build` pour ce qui se construit, `image` pour ce qui est tout prêt.
- Les services se joignent par leur nom, sans publier de port entre eux.
- `depends_on` règle l'ordre de démarrage, pas la disponibilité : `restart: on-failure` a servi ici de filet.
- `docker compose down` garde les volumes nommés, et `-v` les supprime.

Le fichier final se trouve dans [`solution/compose.yaml`](../solution/compose.yaml), avec son [`Dockerfile`](../solution/Dockerfile).

> 📖 [Le Workshop Docker : Compose](https://docs.docker.com/get-started/workshop/08_using_compose/) · [Référence du fichier Compose](https://docs.docker.com/reference/compose-file/) · [`docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/) · [Image `mysql`](https://hub.docker.com/_/mysql)

Pour vous tester sans guide : le challenge « Une application multi-services, sans guide ».
