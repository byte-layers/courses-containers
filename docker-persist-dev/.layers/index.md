---
title: "Persister une base, développer en direct"
description: "Scénario à réaliser en autonomie : brancher MySQL sur un volume pour garder ses données, puis modifier le code de l'application sans reconstruire l'image."
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

**Scénario à réaliser en autonomie** : vous allez reprendre l'application `getting-started-app` et corriger ses deux défauts. Sa base perd ses données quand on la remplace, et chaque modification du code oblige à reconstruire l'image. Vous complétez les blancs marqués `# TODO`, et une vérification contrôle chaque étape. Une solution reste disponible à chaque étape, à ne regarder qu'en cas de blocage.

Vous avez déjà été guidé pour relier une application et sa base : vous aborderez donc cette partie plus librement, avec moins de commandes données. Les nouveautés, elles, sont expliquées pas à pas.

**Niveau** : débutant. Vous savez créer un réseau, y lancer des conteneurs et publier un port (cours « Relier des conteneurs et publier un port »), et vous savez ce qu'est un Dockerfile (cours « Écrire le Dockerfile d'une application »). Ce qui concerne le stockage est expliqué ici au moment où cela sert. Si vous n'avez jamais relié une application à une base, faites d'abord le lab « Une application et sa base, à la main », qui en donne chaque détail.

**Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, un éditeur de texte, et les ports **28362** et **28363** libres. Tout ce que vous créez porte le préfixe `layers-l6-`, et vos fichiers vont dans `~/layers-l6`. La dernière étape supprime le tout, sauf les images téléchargées, qui restent pour servir à nouveau.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

## Ce que vous allez construire

Le schéma montre les deux stockages, et chacun répond à un besoin différent :

```
  votre machine                  conteneurs (réseau layers-l6-net)
  ┌──────────────────┐
  │ ~/layers-l6/app/ │  bind mount    ┌────────────────┐      ┌──────────────┐
  │  src             │ ─────────────► │ layers-l6-dev  │ ───► │ layers-l6-db │
  │ (votre code)     │                │ node --watch   │      │ MySQL        │
  └──────────────────┘                └────────────────┘      └──────┬───────┘
                                                                     │ volume
                                                            ┌────────▼──────────┐
                                                            │ layers-l6-db-data │
                                                            └───────────────────┘
```

- **Un volume pour la base** : les données appartiennent au service, et elles doivent survivre au remplacement de son conteneur. Docker gère leur emplacement.
- **Un bind mount pour le code** : un dossier de votre machine, branché dans le conteneur. Vous modifiez vos fichiers avec votre éditeur, et le conteneur voit le changement.

Les mots de passe restent en clair dans les commandes, un raccourci que traite un prochain cours sur les secrets.

# Préparer l'application

## Récupérer le code et le Dockerfile

Ce code est sur GitHub, et vous en prenez la même version précise que dans le lab « Conteneuriser une application pas à pas » : le commit `6b025fc5`, c'est-à-dire un état enregistré du code, pour que ce lab fonctionne encore quand le dépôt évoluera. Vous créez un dossier, puis `curl` télécharge l'archive et le `|` la passe à `tar`, qui la décompresse dedans. `-sSL` n'affiche que les erreurs et suit les redirections de GitHub, et `--strip-components=1` retire le dossier de premier niveau que contient l'archive.

```exec
mkdir -p ~/layers-l6/app
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C ~/layers-l6/app
```

Le dépôt n'a pas de Dockerfile. Vous prenez ici celui du lab « Conteneuriser une application pas à pas », redonné tel quel, car le sujet est le stockage. Il copie le projet dans `/app`, donc le code dans `/app/src`, installe les dépendances dans `/app/node_modules`, passe à l'utilisateur `node`, qui n'est pas administrateur, et lance `node src/index.js`. Retenez cette organisation, car elle servira pour le bind mount :

```exec
cat > ~/layers-l6/app/Dockerfile <<'EOF'
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

## Construire l'image et créer le réseau

🚧 **À compléter** : construisez l'image `layers-l6-todo:1.0` depuis le dossier `~/layers-l6/app`, et créez le réseau `layers-l6-net`.

```bash
# TODO : construire l'image layers-l6-todo:1.0 depuis ~/layers-l6/app
# TODO : créer le réseau layers-l6-net
```

```hint
`docker build -t <nom>:<tag> <dossier>` construit une image et lui donne un nom et un tag. `docker network create <nom>` crée un réseau.
```

```verify
if ! docker image inspect layers-l6-todo:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l6-todo:1.0 n'existe pas."
  exit 1
fi
case "$(docker image inspect layers-l6-todo:1.0 --format '{{json .Config.Cmd}}')" in
  *src/index.js*) : ;;
  *) echo "L'image layers-l6-todo:1.0 ne lance pas src/index.js. Construisez-la depuis ~/layers-l6/app."; exit 1 ;;
esac
if [ "$(docker network inspect layers-l6-net --format '{{.Driver}}' 2>/dev/null)" != "bridge" ]; then
  echo "Le réseau layers-l6-net n'existe pas, ou n'utilise pas le pilote bridge."
  exit 1
fi
echo "L'image et le réseau sont prêts."
```

````solution
```bash
docker build -t layers-l6-todo:1.0 ~/layers-l6/app
docker network create layers-l6-net
```
````

# Une base qui garde ses données

## Trouver où MySQL écrit

Un **volume** est un espace de stockage géré par Docker, indépendant des conteneurs. Pour garder les données, il faut le brancher exactement sur le dossier où le programme écrit. Sinon, celui-ci continue d'écrire ailleurs et le volume reste vide. La fiche de l'image répond à cette question : l'instruction `VOLUME` d'un Dockerfile y note le dossier de données. `docker pull` télécharge d'abord l'image, car `docker image inspect` ne lit que les images présentes sur votre machine, et `{{json …}}` affiche le champ tel quel :

```exec
docker pull mysql:8.4
docker image inspect mysql:8.4 --format '{{json .Config.Volumes}}'
```

Vous lisez `{"/var/lib/mysql":{}}` : MySQL garde ses fichiers dans `/var/lib/mysql`.

## Lancer MySQL sur un volume

Voici les deux gestes à connaître :

| Geste | Rôle |
|---|---|
| `docker volume create <nom>` | crée un volume vide |
| `-v <nom>:<dossier>` | au lancement de `docker run`, branche le volume sur ce dossier du conteneur |

Sur un volume vide, MySQL s'initialise normalement au premier démarrage. Aux démarrages suivants, il trouve ses fichiers et ne touche à rien.

🚧 **À compléter** : créez le volume `layers-l6-db-data`, puis lancez le conteneur `layers-l6-db` depuis `mysql:8.4`, branché sur ce volume et sur le réseau `layers-l6-net`, avec l'alias `mysql`, c'est-à-dire un second nom valable sur ce réseau. Les variables sont `MYSQL_ROOT_PASSWORD=rootsecret`, `MYSQL_DATABASE=todos`, `MYSQL_USER=todos` et `MYSQL_PASSWORD=secret`. La base ne publie aucun port. Dans le modèle, chaque ligne sauf la dernière finit par `\`, qui prolonge la commande.

```bash
# TODO : créer le volume layers-l6-db-data
docker run -d --name layers-l6-db \
  # TODO : les options de réseau
  # TODO : le volume
  # TODO : les quatre variables d'environnement
  mysql:8.4
```

```hint
Le réseau se donne avec `--network`, l'alias avec `--network-alias`, et chaque variable avec `-e NOM=valeur`.
```

```verify
C=layers-l6-db
if ! docker volume inspect layers-l6-db-data >/dev/null 2>&1; then
  echo "Le volume layers-l6-db-data n'existe pas."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C ne tourne pas. Lisez la raison avec docker logs $C, supprimez-le avec docker rm -f $C, puis recommencez."
  exit 1
fi
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Type}} {{.Name}}{{end}}{{end}}')
if [ "$MOUNT" != "volume layers-l6-db-data" ]; then
  echo "/var/lib/mysql n'est pas branché sur le volume layers-l6-db-data (trouvé : ${MOUNT:-rien}). Un montage se fixe à la création : docker rm -f -v $C (ce -v supprime aussi le volume sans nom que MySQL a pu créer), puis recommencez."
  exit 1
fi
ENVS=$(docker container inspect "$C" --format '{{range .Config.Env}}{{.}} {{end}}')
for V in MYSQL_DATABASE=todos MYSQL_USER=todos MYSQL_PASSWORD=secret; do
  case " $ENVS" in
    *" $V "*) : ;;
    *) echo "Il manque la variable $V. docker rm -f $C, supprimez aussi le volume (docker volume rm layers-l6-db-data), car il est déjà initialisé, puis recommencez."; exit 1 ;;
  esac
done
if ! docker container inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{$v.Aliases}}{{println}}{{end}}' | grep '^layers-l6-net ' | grep -qw mysql; then
  echo "$C n'est pas sur layers-l6-net avec l'alias mysql. docker rm -f $C, puis recommencez."
  exit 1
fi
if [ -n "$(docker port "$C")" ]; then
  echo "$C publie un port, alors que l'hôte n'a pas à le joindre. docker rm -f $C, puis recommencez sans -p."
  exit 1
fi
mkdir -p "$HOME/layers-l6"
[ -f "$HOME/layers-l6/.db-id" ] || docker container inspect "$C" --format '{{.Id}}' > "$HOME/layers-l6/.db-id"
echo "MySQL écrit ses données dans le volume layers-l6-db-data."
```

````solution
```bash
docker volume create layers-l6-db-data
docker run -d --name layers-l6-db \
  --network layers-l6-net \
  --network-alias mysql \
  -v layers-l6-db-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=rootsecret \
  -e MYSQL_DATABASE=todos \
  -e MYSQL_USER=todos \
  -e MYSQL_PASSWORD=secret \
  mysql:8.4
```
````

La vérification note aussi l'identifiant de ce conteneur dans le fichier caché `~/layers-l6/.db-id`, pour pouvoir constater plus tard qu'il a bien été remplacé.

⚠️ **Piège — un mot de passe qui ne change plus.**

- *Symptôme :* vous corrigez une variable, vous recréez le conteneur, et MySQL refuse toujours la connexion.
- *Cause :* ces variables ne servent qu'à la première initialisation. Le volume garde les fichiers d'origine, mots de passe compris.
- *Correctif :* pendant ce lab, supprimez le conteneur, puis le volume avec `docker volume rm layers-l6-db-data`, et recommencez.

## Attendre, puis lancer l'application

Au premier démarrage, MySQL met de quelques secondes à une demi-minute à s'initialiser, et l'application abandonne si sa base ne répond pas sous 10 secondes. Attendez donc qu'il réponde. `mysqladmin ping` interroge le serveur, `-h 127.0.0.1` passe par le réseau, qu'il n'ouvre qu'une fois prêt, et `until … do … done` répète la commande jusqu'à ce qu'elle réussisse. `2>/dev/null` masque les erreurs d'attente :

```exec
until docker exec layers-l6-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent 2>/dev/null; do sleep 2; done
```

Vous lisez `mysqld is alive`. Si la commande tourne plus de deux minutes, interrompez-la avec **Ctrl+C** et lisez `docker logs layers-l6-db`.

🚧 **À compléter** : cette fois sans modèle, lancez l'application dans le conteneur `layers-l6-todo`, depuis l'image `layers-l6-todo:1.0`, sur le réseau `layers-l6-net`. Le port **28362** de l'hôte mène à son port 3000. Elle attend quatre variables : `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_PASSWORD` et `MYSQL_DB`.

```bash
# TODO : docker run de l'application, en reprenant le nom donné à la base sur le réseau
```

```hint
`MYSQL_HOST` prend le nom de la base sur le réseau, `mysql`. Les autres valeurs sont celles données à MySQL : `todos`, `secret` et `todos`.
```

```verify
C=layers-l6-todo
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas."
  exit 1
fi
if ! docker port "$C" 3000 2>/dev/null | grep -q ':28362$'; then
  if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" = "true" ]; then
    echo "Le port 28362 de l'hôte ne mène pas au port 3000 de $C. docker rm -f $C, puis recommencez."
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
  echo "$C s'est arrêté. Voici ses erreurs :"
  echo "$LOGS" | grep -m2 -E 'ECONNREFUSED|ENOTFOUND|Access denied|Unknown database'
  echo "Corrigez votre commande : docker rm -f $C, puis recommencez."
  exit 1
fi
case "$LOGS" in
  *"Connected to mysql db"*) : ;;
  *) echo "L'application n'est pas connectée à MySQL : a-t-elle bien reçu MYSQL_HOST ? docker rm -f $C, puis recommencez."; exit 1 ;;
esac
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28362/items | grep -q '^\['; then
  echo "L'application ne répond pas sur http://localhost:28362/items."
  exit 1
fi
echo "L'application tourne et parle à MySQL."
```

````solution
```bash
docker run -d --name layers-l6-todo --network layers-l6-net -p 28362:3000 -e MYSQL_HOST=mysql -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret -e MYSQL_DB=todos layers-l6-todo:1.0
```
````

## Remplacer la base, sans perdre la tâche

Ajoutez une tâche, puis relisez la liste. `-X POST` demande un ajout, `-H` indique le format du message et `-d` donne son contenu. Cette tâche vous servira de témoin :

```exec
curl -sS -X POST -H 'Content-Type: application/json' -d '{"name":"Apprendre les volumes"}' http://localhost:28362/items
curl -sS http://localhost:28362/items
```

Faites maintenant ce qu'une mise à jour de la base ferait : supprimez son conteneur, et recréez-le. Le volume nommé n'est pas concerné par `docker rm -f`.

🚧 **À compléter** : supprimez `layers-l6-db`, recréez-le à l'identique, puis attendez qu'il réponde. Avant de vérifier, faites une prévision : la tâche sera-t-elle encore là ?

```bash
# TODO : supprimer le conteneur layers-l6-db
# TODO : le recréer, avec la même commande qu'à l'étape « Lancer MySQL sur un volume »
# TODO : attendre que MySQL réponde
curl -sS http://localhost:28362/items
```

```verify
C=layers-l6-db
ID_REF=$(cat "$HOME/layers-l6/.db-id" 2>/dev/null)
if [ -z "$ID_REF" ]; then
  echo "La vérification de « Lancer MySQL sur un volume » n'a pas été faite : refaites-la avant celle-ci."
  exit 1
fi
if [ "$ID_REF" = "$(docker container inspect "$C" --format '{{.Id}}' 2>/dev/null)" ]; then
  echo "$C est toujours le même conteneur. Supprimez-le, puis recréez-le : un redémarrage ne prouve rien."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$C ne tourne pas. Recréez-le avec la commande de l'étape « Lancer MySQL sur un volume »."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Name}}{{end}}{{end}}')" != "layers-l6-db-data" ]; then
  echo "Le nouveau $C n'est pas branché sur layers-l6-db-data. Supprimez-le et recréez-le avec le volume."
  exit 1
fi
if ! curl -s --max-time 5 --retry 5 --retry-delay 2 --retry-all-errors http://localhost:28362/items | grep -q 'Apprendre les volumes'; then
  echo "La tâche Apprendre les volumes n'apparaît pas. Attendez que MySQL réponde. Si vous l'avez bien ajoutée, regardez : docker logs layers-l6-todo"
  exit 1
fi
echo "Le conteneur est neuf, et la tâche est toujours là."
```

````solution
```bash
docker rm -f layers-l6-db
docker run -d --name layers-l6-db --network layers-l6-net --network-alias mysql -v layers-l6-db-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=rootsecret -e MYSQL_DATABASE=todos -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret mysql:8.4
until docker exec layers-l6-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent 2>/dev/null; do sleep 2; done
```
````

La tâche est toujours là, alors que le conteneur est neuf. L'application n'a même pas eu besoin de redémarrer : elle a retrouvé sa base par le même nom, et sa table existe encore. **Le conteneur est jetable, les données ne le sont plus.**

# Développer en direct

## Le problème, et l'idée

L'image contient une copie de votre code. Pour voir la moindre modification, il faudrait donc reconstruire l'image et recréer le conteneur. C'est le bon chemin pour livrer, mais il est lent pour développer. On veut que le conteneur utilise directement les fichiers de votre machine et que l'application redémarre quand ils changent. Il faut pour cela deux choses :

| Élément | Rôle |
|---|---|
| un **bind mount** : `-v <chemin sur votre machine>:<dossier du conteneur>` | le même dossier des deux côtés, sans copie. Ce qui précède le `:` est un chemin et non un nom, ce qui distingue un bind mount d'un volume |
| `node --watch src/index.js` | Node.js relance l'application dès qu'un fichier du code change. Écrite après le nom de l'image, cette commande remplace celle de l'image |

Le chemin doit commencer par `/` ou `./`. Il vaut mieux écrire un chemin absolu, pour ne pas dépendre du dossier courant : `"$HOME/layers-l6/…"` convient, car le shell remplace `$HOME` par votre dossier personnel. Sur un poste hébergé, c'est-à-dire un VS Code ouvert dans votre navigateur et fourni par votre formateur, le moteur Docker ne voit que les dossiers placés sous `/home/student`, ce qui est bien le cas ici.

Le conteneur de développement utilisera le port 28363. Supprimez d'abord l'ancien conteneur de l'application, qui ne sert plus :

```exec
docker rm -f layers-l6-todo
```

## Monter uniquement le code source

⚠️ **Piège — monter tout le projet.**

- *Symptôme :* avec `-v "$HOME/layers-l6/app:/app"`, le conteneur tourne mais l'application ne répond pas, et ses logs affichent `Cannot find module 'express'`. `node --watch` attend alors simplement le prochain changement de fichier.
- *Cause :* un bind mount **masque** ce que l'image contient à cet endroit. Or vos dépendances sont dans `/app/node_modules`, dans l'image, et ce dossier n'existe pas sur votre machine.
- *Correctif :* ne montez que ce qui change, soit `src` sur `/app/src`.

🚧 **À compléter** : lancez le conteneur `layers-l6-dev`, sur le réseau `layers-l6-net`, avec le port 28363 de l'hôte vers le port 3000, les quatre variables de la base, et le bind mount du dossier `src`.

```bash
docker run -d --name layers-l6-dev \
  # TODO : le réseau et le port
  # TODO : les quatre variables d'environnement
  # TODO : le bind mount de ~/layers-l6/app/src sur /app/src
  layers-l6-todo:1.0 \
  node --watch src/index.js
```

```verify
C=layers-l6-dev
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Le conteneur $C n'existe pas."
  exit 1
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(docker container inspect "$C" --format '{{.State.Running}}')" = "true" ] || break
  docker logs "$C" 2>&1 | grep -qE 'Listening on port|Cannot find module' && break
  sleep 2
done
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ] || docker logs "$C" 2>&1 | grep -q 'Cannot find module'; then
  echo "$C ne tourne pas correctement. Avez-vous monté tout le projet au lieu de src ? Regardez docker logs $C, puis : docker rm -f $C, et recommencez."
  exit 1
fi
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/app/src"}}{{.Type}} {{.Source}}{{end}}{{end}}')
case "$MOUNT" in
  bind*layers-l6/app/src) : ;;
  *) echo "/app/src n'est pas un bind mount de ~/layers-l6/app/src (trouvé : ${MOUNT:-rien}). Écrivez le chemin en entier, avec $HOME : docker rm -f $C, puis recommencez."; exit 1 ;;
esac
case "$(docker container inspect "$C" --format '{{json .Config.Cmd}}')" in
  *--watch*) : ;;
  *) echo "$C n'exécute pas node --watch src/index.js. docker rm -f $C, puis recommencez."; exit 1 ;;
esac
if ! docker port "$C" 3000 2>/dev/null | grep -q ':28363$'; then
  echo "Le port 28363 de l'hôte ne mène pas au port 3000 de $C. docker rm -f $C, puis recommencez."
  exit 1
fi
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28363/items | grep -q 'Apprendre les volumes'; then
  echo "L'application ne renvoie pas votre tâche sur le port 28363. A-t-elle bien reçu MYSQL_HOST et les autres variables ? docker rm -f $C, puis recommencez."
  exit 1
fi
docker container inspect "$C" --format '{{.Id}}' > "$HOME/layers-l6/.dev-id"
echo "Le code est monté depuis votre machine, et l'application relit la même base."
```

````solution
```bash
docker run -d --name layers-l6-dev --network layers-l6-net -p 28363:3000 -e MYSQL_HOST=mysql -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret -e MYSQL_DB=todos -v "$HOME/layers-l6/app/src:/app/src" layers-l6-todo:1.0 node --watch src/index.js
```
````

Votre tâche est toujours servie, ce qui montre que ce nouveau conteneur relit la même base. La vérification a aussi noté l'identifiant de ce conteneur dans le fichier caché `~/layers-l6/.dev-id`, pour constater ensuite que vous ne l'avez pas recréé.

## Modifier le code

Ajoutez une route à l'application, sur votre machine, en écrivant une ligne à la fin de `src/index.js`. Une **route** est une adresse à laquelle le serveur répond, ici `/bonjour`. `>>` ajoute à la fin du fichier sans effacer le reste, et `<<'EOF'` donne le texte à écrire, jusqu'à la ligne `EOF` :

```exec
cat >> ~/layers-l6/app/src/index.js <<'EOF'
app.get('/bonjour', (req, res) => res.send('Bonjour depuis mon poste\n'));
EOF
```

Regardez ce qu'a fait le conteneur : `--tail 5` affiche les 5 dernières lignes de ses logs, où vous lisez `Restarting 'src/index.js'`. Demandez ensuite la nouvelle route. `--retry` laisse à l'application le temps de redémarrer, et une erreur de connexion peut s'afficher entre-temps :

```exec
sleep 2
docker logs --tail 5 layers-l6-dev
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28363/bonjour
```

Vous lisez `Bonjour depuis mon poste`, sans reconstruction et sans recréation. Rien de tout cela n'est dans l'image, comme le montre un conteneur créé sans le bind mount. `grep -c` compte les lignes qui contiennent le mot `bonjour` :

```exec
docker run --rm layers-l6-todo:1.0 grep -c bonjour src/index.js
```

Vous lisez `0`. ⚖️ Le bind mount est un outil de développement. Pour livrer, il faut reconstruire l'image, car c'est elle qu'on déploie.

🚧 **À compléter** : avec votre éditeur, modifiez cette ligne dans `~/layers-l6/app/src/index.js`, pour que la route `/bonjour` réponde `Bonjour, layers`. N'exécutez aucune commande Docker : c'est tout l'intérêt.

```hint
Le fichier est sur votre machine, ouvrez-le avec n'importe quel éditeur. Si vous n'avez pas d'éditeur graphique, `nano ~/layers-l6/app/src/index.js` en ouvre un dans le terminal : `Ctrl+O` puis `Entrée` enregistrent, et `Ctrl+X` quitte. Node.js relance l'application dès que vous enregistrez.
```

```verify
if [ "$(docker container inspect layers-l6-dev --format '{{.Id}}' 2>/dev/null)" != "$(cat "$HOME/layers-l6/.dev-id" 2>/dev/null)" ]; then
  echo "layers-l6-dev a été recréé ou n'existe plus. Le but est de ne rien recréer : refaites l'étape précédente et sa vérification."
  exit 1
fi
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28363/bonjour | grep -q 'Bonjour, layers'; then
  echo "La route /bonjour ne répond pas Bonjour, layers. Vérifiez le fichier, puis lisez docker logs --tail 5 layers-l6-dev."
  exit 1
fi
echo "Votre modification est servie, sans avoir touché à Docker."
```

````solution
Modifiez la ligne à la main dans votre éditeur, ou lancez cette commande. `-i.bak` modifie le fichier en gardant une copie, et cette écriture marche sous Linux comme sur macOS :

```bash
sed -i.bak 's/Bonjour depuis mon poste/Bonjour, layers/' ~/layers-l6/app/src/index.js && rm ~/layers-l6/app/src/index.js.bak
sleep 2
```
````

# Nettoyer

## Ne rien laisser

🚧 **À compléter** : supprimez tout ce que ce lab a créé. Il s'agit des conteneurs `layers-l6-dev` et `layers-l6-db`, du volume `layers-l6-db-data`, du réseau `layers-l6-net`, de l'image `layers-l6-todo:1.0` et du dossier `~/layers-l6`. Le volume doit être supprimé explicitement : c'est lui qui garde vos données, et personne d'autre ne le fera à votre place.

```bash
# TODO : les conteneurs
# TODO : le volume
# TODO : le réseau
# TODO : l'image
# TODO : le dossier
```

```hint
Dans l'ordre : `docker rm -f`, `docker volume rm`, `docker network rm`, `docker rmi`, puis `rm -rf`. Un volume ou un réseau occupé refuse de partir : les conteneurs viennent donc en premier.
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l6-(todo|dev|db)$')" ]; then
  echo "Il reste des conteneurs layers-l6-."
  exit 1
fi
if docker volume inspect layers-l6-db-data >/dev/null 2>&1; then
  echo "Le volume layers-l6-db-data existe encore."
  exit 1
fi
if docker network inspect layers-l6-net >/dev/null 2>&1; then
  echo "Le réseau layers-l6-net existe encore."
  exit 1
fi
if docker image inspect layers-l6-todo:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l6-todo:1.0 existe encore."
  exit 1
fi
if [ -e "$HOME/layers-l6" ]; then
  echo "Le dossier ~/layers-l6 existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
docker rm -f layers-l6-dev layers-l6-db
docker volume rm layers-l6-db-data
docker network rm layers-l6-net
docker rmi layers-l6-todo:1.0
rm -rf ~/layers-l6
```
````

## Récap

- Le volume se branche sur le dossier où le programme écrit : `docker image inspect` le donne pour une image qui déclare `VOLUME`.
- Le conteneur de la base devient remplaçable, et ses données ne bougent pas.
- Un bind mount montre vos fichiers au conteneur et masque ce que l'image contient à cet endroit : on n'y monte que ce qui change.
- En développement, le bind mount et `node --watch` évitent de reconstruire. Pour livrer, on reconstruit l'image.

Vos commandes commencent à être longues et difficiles à retenir : un prochain cours décrit tout cela dans un seul fichier, avec Compose.

Le dossier `solution/` du dépôt de ce cours, à côté de `.layers/`, garde le Dockerfile et un script `run.sh` qui rejoue tout le lab.

> 📖 [Persister la base de données](https://docs.docker.com/get-started/workshop/05_persisting_data/) · [Utiliser des bind mounts](https://docs.docker.com/get-started/workshop/06_bind_mounts/) · [Les volumes](https://docs.docker.com/engine/storage/volumes/) · [Les bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)

Pour vous tester sans guide, faites d'abord le cours « Garder ses données : volumes et bind mounts », puis le challenge « Prouver que les données survivent ».
