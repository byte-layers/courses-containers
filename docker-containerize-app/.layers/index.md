---
title: "Conteneuriser getting-started-app"
description: "Pas à pas et avec des blancs à compléter : écrire le Dockerfile d'une vraie application web, la lancer, puis garder un secret hors de l'image et abandonner les droits d'administrateur."
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

Vous allez fabriquer l'image d'une vraie application : `getting-started-app`, une petite liste de tâches écrite en Node.js et publiée par Docker pour l'apprentissage. C'est la même application qui reviendra dans les prochains cours.

**Scénario à réaliser en autonomie.** Ce lab ne donne pas tout : le Dockerfile contient des lignes `# TODO` que vous remplacez vous-même, à partir des tableaux et des explications qui les précèdent. Un bouton vérifie ensuite le résultat réel. Les **indices** se dévoilent un par un, et la **solution** reste en dernier recours : les utiliser ne coûte rien.

**Niveau** : débutant. Vous savez lancer un conteneur avec `docker run`, ses options `-d`, `--name`, `-e`, `--rm`, et publier un port avec `-p`, comme le montre le lab « Héberger une page dans un conteneur ». Ce lab ne suppose ni que vous ayez écrit un Dockerfile, ni que vous connaissiez Node.js : chaque instruction est expliquée quand elle arrive.

**Ce qu'il faut** : Docker, `curl`, un éditeur de texte, et le port **28321** libre. Vos fichiers vont dans `~/layers-l2/app`, et tout ce que vous créez dans Docker porte le préfixe `layers-l2-`.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Récupérer l'application

## Télécharger le code

Une image se construit à partir d'un code source, qu'il faut donc d'abord récupérer. Ce code est sur GitHub, et vous en prenez une version précise, le commit `6b025fc5`, c'est-à-dire un état enregistré du code, pour que ce lab fonctionne encore quand le dépôt évoluera. Vous créez un dossier, puis `curl` télécharge l'archive et le `|` la passe à `tar`, qui la décompresse dedans. `-sSL` n'affiche que les erreurs et suit les redirections de GitHub, et `--strip-components=1` retire le dossier de premier niveau que contient l'archive.

```exec
mkdir -p ~/layers-l2/app
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C ~/layers-l2/app
```

## Lire ce qu'il faut pour la lancer

Avant d'écrire un Dockerfile, on regarde ce que l'application demande. Listez le dossier. `ls -A` montre aussi les fichiers dont le nom commence par un point :

```exec
ls -A ~/layers-l2/app
```

Vous devez lire notamment `package.json`, `package-lock.json` et `src`. Ce tableau dit ce qu'il faut en tirer pour une application Node.js.

| Élément | Ce qu'il vous apprend |
|---|---|
| `package.json` | la liste des bibliothèques de l'application, ses **dépendances** |
| `package-lock.json` | leurs versions exactes. `npm` est l'outil qui installe les bibliothèques de Node.js, et `npm ci` installe exactement ces versions |
| `src/index.js` | le point d'entrée : l'application démarre avec `node src/index.js` |
| `.dockerignore` | la liste de ce que Docker ne doit pas copier, déjà présente ici |

Reste à savoir sur quel port elle écoute. `grep` cherche le mot dans le fichier de démarrage :

```exec
grep listen ~/layers-l2/app/src/index.js
```

La ligne affichée contient `app.listen(3000, …)` : l'application écoute sur le port 3000. Vous avez maintenant tout ce qu'il faut pour écrire son Dockerfile.

```ack
J'ai le code, et je sais comment il démarre
```

# Compléter le Dockerfile

## Les instructions dont vous avez besoin

Un **Dockerfile** est un fichier texte qui décrit comment fabriquer une image, une instruction par ligne. Voici celles qui vous serviront, avec leur forme générale.

| Instruction | Rôle |
|---|---|
| `FROM image:tag` | part d'une image existante, l'**image de base** |
| `WORKDIR /dossier` | se place dans ce dossier, créé s'il n'existe pas, pour la suite et pour le conteneur |
| `COPY source destination` | copie des fichiers du projet vers l'image. `COPY . .` copie tout le projet dans le dossier courant |
| `RUN commande` | exécute une commande **pendant la construction** et garde son résultat dans l'image |
| `EXPOSE port` | documente le port d'écoute, sans rien publier |
| `CMD ["programme", "argument"]` | enregistre ce que chaque conteneur lance à son démarrage. C'est la **forme exec**, une liste entre crochets, à préférer |

L'option `--omit=dev` de `npm ci` n'installe pas les outils réservés au développement, comme `nodemon` ici. En production, ils ne servent à rien et alourdissent l'image.

⚖️ Ce lab copie tout le projet avant d'installer, parce que c'est le plus simple à lire. Cet ordre refait l'installation à chaque modification du code, et un prochain cours montre comment l'éviter.

## 🚧 À compléter

Créez le fichier avec ses blancs. Vous allez ensuite remplacer chaque `# TODO` par l'instruction qu'il décrit :

```exec
cat > ~/layers-l2/app/Dockerfile <<'EOF'
# TODO : partir de l'image node:22-alpine, c'est-à-dire Node.js 22 sur Alpine, un Linux minimal

# TODO : se placer dans le dossier /app

# TODO : copier tout le projet dans le dossier courant de l'image

# TODO : installer les dépendances avec npm ci, sans celles de développement

# TODO : documenter le port d'écoute de l'application

# TODO : démarrer l'application avec node src/index.js, en forme exec
EOF
```

La forme `cat > fichier <<'EOF'` écrit dans le fichier les lignes qui suivent, jusqu'à la ligne `EOF`. Ouvrez maintenant `~/layers-l2/app/Dockerfile` dans votre éditeur, remplissez les blancs et enregistrez. Si vous n'avez pas d'éditeur graphique, `nano ~/layers-l2/app/Dockerfile` en ouvre un dans le terminal : `Ctrl+O` puis `Entrée` enregistrent, et `Ctrl+X` quitte.

Une ligne qui commence par `#` est un commentaire : vous pouvez garder les vôtres ou les supprimer, Docker les ignore.

Construisez ensuite l'image. `-t` lui donne un nom et un tag, et le dernier argument est le **contexte de build**, le dossier dont `COPY` peut prendre des fichiers :

```exec
docker build -t layers-l2-todo:1.0 ~/layers-l2/app
```

Si Docker répond par une erreur, la ligne fautive est marquée `>>>` et la raison se trouve à la fin du message. Corrigez le fichier, puis relancez cette même commande autant de fois que nécessaire.

> 📖 [Référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [`docker build`](https://docs.docker.com/reference/cli/docker/build/)

```hint
Le fichier suit l'ordre des `# TODO` : une instruction par blanc, soit six en tout. Le premier se remplace par `FROM node:22-alpine`.
```

```hint
La ligne d'installation s'écrit `RUN npm ci --omit=dev`. Le point de `COPY . .` désigne d'abord le contexte de build, puis le dossier courant de l'image.
```

```hint
Le port est celui que vous avez lu dans `src/index.js`. En forme exec, chaque mot de la commande est une chaîne : `["node", "src/index.js"]`.
```

```verify
I=layers-l2-todo:1.0
if [ ! -f "$HOME/layers-l2/app/package.json" ]; then
  echo "Le code de l'application n'est pas dans ~/layers-l2/app. Refaites l'étape précédente."
  exit 1
fi
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Complétez le Dockerfile, puis lancez le docker build."
  exit 1
fi
if ! docker run --rm "$I" node --version >/dev/null 2>&1; then
  echo "Node.js n'est pas dans l'image : l'image de base doit être node:22-alpine."
  exit 1
fi
if [ "$(docker image inspect "$I" --format '{{.Config.WorkingDir}}')" != "/app" ]; then
  echo "Le dossier de travail de l'image n'est pas /app. Vérifiez la ligne WORKDIR."
  exit 1
fi
if ! docker run --rm "$I" test -f /app/src/index.js; then
  echo "Le code n'est pas dans /app. Vérifiez la ligne COPY."
  exit 1
fi
if ! docker run --rm "$I" test -d /app/node_modules/express; then
  echo "Les dépendances ne sont pas installées dans l'image. Vérifiez la ligne RUN."
  exit 1
fi
if docker run --rm "$I" test -d /app/node_modules/nodemon; then
  echo "Les dépendances de développement sont dans l'image : ajoutez --omit=dev à npm ci."
  exit 1
fi
case "$(docker image inspect "$I" --format '{{json .Config.ExposedPorts}}')" in
  *'"3000/tcp"'*) : ;;
  *) echo "L'image ne documente pas le port 3000. Vérifiez la ligne EXPOSE."; exit 1 ;;
esac
case "$(docker image inspect "$I" --format '{{json .Config.Cmd}}')" in
  *index.js*) : ;;
  *) echo "La commande de démarrage ne lance pas src/index.js. Vérifiez la ligne CMD."; exit 1 ;;
esac
echo "L'image contient l'application, ses dépendances, et sait comment démarrer."
```

````solution
Le Dockerfile complet, écrit par une seule commande, suivie du build :

```bash
cat > ~/layers-l2/app/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
EXPOSE 3000
CMD ["node", "src/index.js"]
EOF
docker build -t layers-l2-todo:1.0 ~/layers-l2/app
```
````

# Lancer l'application

## 🚧 À compléter

Votre image est prête. Il reste à en faire un conteneur, en vous servant de ce que vous savez déjà de `docker run`. Voici la commande à compléter, dans laquelle les deux blancs sont le port publié et l'image :

```bash
docker run -d --name layers-l2-todo -p # TODO port-machine:port-conteneur    # TODO image
```

Le port de votre machine est **28321**, et celui du conteneur est le port d'écoute de l'application. L'image est celle que vous venez de construire.

Ajoutez ensuite une tâche, pour prouver que l'application fonctionne et pas seulement qu'elle répond. Vous pouvez le faire dans un navigateur, en ouvrant `http://localhost:28321`, ou depuis l'onglet **PORTS** de VS Code sur un poste hébergé. Vous pouvez aussi utiliser cette commande, où `-X POST` envoie des données, `-H` précise leur format, ici JSON, et `-d` indique lesquelles :

```exec
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"Écrire mon Dockerfile"}' http://localhost:28321/items
```

La réponse reprend votre tâche, avec un identifiant. Si rien ne s'affiche, l'application démarrait encore : relancez la commande. Relisez ensuite la liste des tâches. L'application les enregistre dans un petit fichier de base de données, et les renvoie à cette adresse :

```exec
curl -s http://localhost:28321/items
```

Vous devez lire votre tâche dans la réponse.

> 📖 [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/)

```hint
Le port se donne sous la forme `<port-machine>:<port-conteneur>`, et l'image vient en dernier sur la ligne.
```

```hint
L'application écoute sur le port 3000 : `-p 28321:3000`. Si le nom est déjà pris après un essai, supprimez l'ancien conteneur avec `docker rm -f layers-l2-todo`.
```

```verify
C=layers-l2-todo
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "Aucun conteneur ne s'appelle $C. Complétez et lancez la commande docker run."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C ne tourne pas. Lisez : docker logs $C"
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Config.Image}}')" != "layers-l2-todo:1.0" ]; then
  echo "$C ne vient pas de l'image layers-l2-todo:1.0."
  exit 1
fi
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28321 | grep -q 'Todo App'; then
  echo "Le port 28321 ne renvoie pas l'application. Rappel : -p <port-machine>:<port-conteneur>, et l'application écoute sur 3000."
  exit 1
fi
ITEMS=$(curl -s --max-time 5 http://localhost:28321/items)
case "$ITEMS" in
  ""|"[]") echo "L'application répond, mais sa liste est vide. Ajoutez une tâche."; exit 1 ;;
esac
echo "L'application tourne et enregistre vos tâches."
```

````solution
```bash
docker run -d --name layers-l2-todo -p 28321:3000 layers-l2-todo:1.0
curl -s --retry 5 --retry-delay 1 --retry-all-errors -X POST -H 'Content-Type: application/json' -d '{"name":"Écrire mon Dockerfile"}' http://localhost:28321/items
```
````

# Garder un secret hors de l'image

## Le problème

Un projet réel contient souvent un fichier `.env`, où se rangent des valeurs sensibles comme des mots de passe. Or `COPY . .` copie tout. Créez ce fichier, avec une valeur fictive, reconstruisez sous un autre tag, puis regardez ce que contient l'image. Ce qui suit le nom de l'image remplace la commande de démarrage :

```exec
echo 'SESSION_SECRET=valeur-fictive' > ~/layers-l2/app/.env
docker build -t layers-l2-todo:1.1 ~/layers-l2/app
docker run --rm layers-l2-todo:1.1 ls -A
```

`.env` figure dans la liste : toute personne qui récupère cette image peut lire ce secret. Le dépôt fournit déjà un `.dockerignore`, le fichier qui liste ce que Docker doit laisser de côté, un motif par ligne. Voyez ce qu'il contient :

```exec
cat ~/layers-l2/app/.dockerignore
```

Il exclut `node_modules` et `Dockerfile`, mais rien ne protège `.env`. Exclure `node_modules` a aussi son importance : un dossier installé sur votre machine ne doit pas remplacer celui que `npm ci` prépare dans l'image.

## 🚧 À compléter

Ajoutez à `~/layers-l2/app/.dockerignore` la ligne qui exclut le fichier `.env`, en gardant les lignes existantes. Reconstruisez ensuite sous le tag `1.2`, et regardez à nouveau le dossier :

```exec
docker build -t layers-l2-todo:1.2 ~/layers-l2/app
docker run --rm layers-l2-todo:1.2 ls -A
```

`.env` ne doit plus apparaître, alors que `src` doit toujours y être.

> 📖 [Les fichiers `.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files)

```hint
Le motif s'écrit tel quel, sur sa propre ligne : le nom du fichier suffit.
```

```verify
I=layers-l2-todo:1.2
LS=$(docker run --rm "$I" ls -A 2>/dev/null)
if [ -z "$LS" ]; then
  echo "L'image $I n'existe pas. Modifiez .dockerignore, puis lancez le docker build."
  exit 1
fi
if printf '%s\n' "$LS" | grep -qx '.env'; then
  echo "Le fichier .env est encore dans $I. Ajoutez-le à ~/layers-l2/app/.dockerignore, puis reconstruisez."
  exit 1
fi
if ! printf '%s\n' "$LS" | grep -qx 'src'; then
  echo "Le dossier src manque dans $I. Votre .dockerignore en exclut trop."
  exit 1
fi
echo "Le fichier .env reste hors de l'image, et le code y est toujours."
```

````solution
```bash
echo '.env' >> ~/layers-l2/app/.dockerignore
docker build -t layers-l2-todo:1.2 ~/layers-l2/app
```
````

⚖️ L'image `1.1` contient toujours ce fichier, car une image ne change jamais. Dans un vrai projet, un secret qui a fuité doit aussi être changé. Un prochain cours, « Un secret ne va pas dans l'image », reprend ce sujet.

# Ne plus tourner en administrateur

## Le problème

Par défaut, l'application tourne avec l'utilisateur `root`, l'administrateur de Linux, sans en avoir besoin. L'image `node:22-alpine` fournit déjà un utilisateur ordinaire, nommé `node`. L'option `--user` de `docker run` permet d'essayer avec lui avant de toucher au Dockerfile :

```exec
docker run --rm --user node layers-l2-todo:1.2
```

L'application s'arrête aussitôt sur une erreur. Pas d'inquiétude, c'est ce qu'il fallait voir, et l'erreur se lit en trois temps.

- **Symptôme** : `Error: EACCES: permission denied, mkdir '/etc/todos'`.
- **Cause** : l'application range sa base de données dans `/etc/todos`, un dossier qu'elle tente de créer au démarrage. Sous `/etc`, seul `root` peut le faire.
- **Correctif** : préparer ce dossier pendant la construction, quand on a encore les droits, et le donner à l'utilisateur `node`.

## 🚧 À compléter

Le correctif tient en deux instructions, un `RUN` et un `USER`, et ce tableau donne tout ce qu'il leur faut.

| Élément | Rôle |
|---|---|
| `mkdir -p /etc/todos` | crée le dossier, dans un `RUN` |
| `chown node /etc/todos` | donne ce dossier à l'utilisateur `node`, dans le même `RUN` |
| `USER node` | utilise cet utilisateur pour la suite du Dockerfile et au démarrage du conteneur |
| `&&` | enchaîne deux commandes sur une même ligne, la seconde seulement si la première réussit |

Ajoutez ces deux blancs à votre Dockerfile, juste après la ligne `RUN npm ci`, puis remplacez chacun par son instruction. L'ordre compte, car l'installation et la préparation du dossier ont besoin des droits d'administrateur :

```dockerfile
# TODO : créer /etc/todos et le donner à l'utilisateur node, en une seule instruction RUN
# TODO : passer à l'utilisateur node
```

Construisez sous le tag `1.3`, puis remplacez le conteneur par un nouveau, avec le même nom et le même port :

```exec
docker build -t layers-l2-todo:1.3 ~/layers-l2/app
docker rm -f layers-l2-todo
docker run -d --name layers-l2-todo -p 28321:3000 layers-l2-todo:1.3
```

Demandez à ce conteneur qui il est. `docker exec` lance une commande à l'intérieur, et `id -un` affiche le nom de l'utilisateur :

```exec
docker exec layers-l2-todo id -un
```

Vous devez lire `node`. Si le conteneur s'est arrêté, lisez son erreur avec `docker logs layers-l2-todo`.

> 📖 [`USER`](https://docs.docker.com/reference/dockerfile/#user) · [Bonnes pratiques d'écriture](https://docs.docker.com/build/building/best-practices/)

```hint
La première ligne s'écrit `RUN mkdir -p /etc/todos && chown node /etc/todos`.
```

```hint
Si le conteneur tombe encore sur `permission denied`, vérifiez que le `RUN` précède bien `USER`, et que l'image a été reconstruite.
```

```verify
C=layers-l2-todo
if [ "$(docker container inspect "$C" --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l2-todo:1.3" ]; then
  echo "Le conteneur $C doit venir de l'image layers-l2-todo:1.3. Reconstruisez, supprimez-le et recréez-le."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "$C s'est arrêté. Lisez son erreur : docker logs $C"
  exit 1
fi
if [ "$(docker exec "$C" id -u)" = "0" ]; then
  echo "$C tourne encore en root. Ajoutez USER node au Dockerfile, puis reconstruisez."
  exit 1
fi
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28321/items >/dev/null; then
  echo "Le port 28321 ne répond pas. Lisez : docker logs $C"
  exit 1
fi
NEW=$(curl -s --max-time 5 -X POST -H 'Content-Type: application/json' -d '{"name":"Essai sans root"}' http://localhost:28321/items)
case "$NEW" in
  *"Essai sans root"*) : ;;
  *) echo "L'application n'arrive pas à enregistrer une tâche. Le dossier de sa base lui appartient-il ?"; exit 1 ;;
esac
echo "L'application tourne avec l'utilisateur $(docker exec "$C" id -un) et enregistre ses tâches."
```

````solution
```bash
cat > ~/layers-l2/app/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
RUN mkdir -p /etc/todos && chown node /etc/todos
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
EOF
docker build -t layers-l2-todo:1.3 ~/layers-l2/app
docker rm -f layers-l2-todo
docker run -d --name layers-l2-todo -p 28321:3000 layers-l2-todo:1.3
```
````

Vos tâches précédentes ont disparu : elles étaient dans la couche d'écriture de l'ancien conteneur, supprimée avec lui. Si vous relisez la liste, la tâche `Essai sans root` vient de la vérification, qui l'a créée pour tester l'écriture. Un prochain cours, « Garder ses données », montre comment les conserver.

# Nettoyer

## Ne rien laisser

Supprimez ce que ce lab a créé, sans la commande cette fois. Vous connaissez `docker rm -f`, pour le conteneur. `docker image rm` supprime des images, à condition de lui donner chaque nom et chaque tag, et `rm -rf` efface un dossier sans demander confirmation : vérifiez bien le chemin.

**Critères :**

- le conteneur `layers-l2-todo` n'existe plus ;
- les images `layers-l2-todo:1.0`, `1.1`, `1.2` et `1.3` n'existent plus ;
- le dossier `~/layers-l2/app` n'existe plus. Le dossier parent `~/layers-l2`, lui, peut rester.

```hint
Le conteneur d'abord : `docker image rm` refuse une image qu'un conteneur utilise encore.
```

```verify
if docker container inspect layers-l2-todo >/dev/null 2>&1; then
  echo "Le conteneur layers-l2-todo existe encore."
  exit 1
fi
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^layers-l2-todo:')
if [ -n "$left" ]; then
  echo "Il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l2/app" ]; then
  echo "Le dossier ~/layers-l2/app existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
docker rm -f layers-l2-todo
docker image rm layers-l2-todo:1.0 layers-l2-todo:1.1 layers-l2-todo:1.2 layers-l2-todo:1.3
rm -rf ~/layers-l2/app
```
````

## Récap

- Pour écrire un Dockerfile, on lit d'abord ce que l'application demande : ses dépendances, sa commande de démarrage, son port.
- `FROM`, `WORKDIR`, `COPY`, `RUN`, `EXPOSE` et `CMD` suffisent à conteneuriser une application courante.
- `.dockerignore` garde hors de l'image ce qui n'a rien à y faire.
- `USER` retire les droits d'administrateur, et ce qui en a besoin se prépare avant cette ligne, pendant le build.

Le dossier `solution/` du dépôt de ce cours, à côté de `.layers/`, garde le Dockerfile et le `.dockerignore` complets. Pour vous tester sans guide : le challenge « Conteneuriser une application inconnue ».
