---
title: "Conteneuriser une application pas à pas"
description: "Une liste de tâches en Node.js : écrire son Dockerfile à partir de ses fichiers, la lancer, garder un secret hors de l'image et lui retirer les droits d'administrateur."
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

Conteneuriser une application, c'est construire une image qui la contient avec tout ce qu'il lui faut, pour la lancer ensuite dans un conteneur sur n'importe quelle machine. Vous allez le faire pour une vraie application : une petite liste de tâches, une page web où l'on ajoute, coche et supprime des tâches qu'un serveur enregistre. Elle est écrite en Node.js, un environnement qui exécute du JavaScript côté serveur, et Docker la publie pour l'apprentissage sous le nom `getting-started-app`. Les prochains cours la reprendront pour la relier à une vraie base de données séparée.

**Scénario à réaliser en autonomie.** Le Dockerfile contient des blancs que vous remplacez vous-même, à partir des tableaux et des explications qui les précèdent, et un bouton vérifie ensuite le résultat réel. Les **indices** se dévoilent un par un, et la **solution** reste en dernier recours : les utiliser ne coûte rien.

**Niveau** : débutant. Il n'est pas nécessaire d'avoir déjà écrit un Dockerfile ni de connaître Node.js : chaque instruction est expliquée quand elle arrive. Si vous avez suivi [Écrire le Dockerfile d'une application](https://byte-layers.com/fr/skills/docker-dockerfile), vous reconnaîtrez ces instructions et vous irez plus vite.

**Prérequis** : savoir lancer un conteneur et publier un port, ce qu'enseigne [Héberger une page dans un conteneur](https://byte-layers.com/fr/labs/docker-first-web-page).

**Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, un éditeur de texte, et le port **28321** libre. Vos fichiers vont dans `~/byte-layers/docker/l2/app`, et tout ce que vous créez dans Docker porte le préfixe `layers-l2-`, pour ne pas toucher au reste de votre machine.

# Récupérer l'application

## Télécharger le code à une version fixée

Une image se construit à partir d'un code source, qu'il faut donc d'abord récupérer. Ce code est sur GitHub, et vous en prenez une version précise, le commit `6b025fc5`, c'est-à-dire un état enregistré du code, pour que ce lab fonctionne encore quand le code évoluera. Vous créez un dossier, puis `curl` télécharge l'archive et le `|` la passe à `tar`, qui la décompresse dedans. `-sSL` n'affiche que les erreurs et suit les redirections de GitHub, et `--strip-components=1` retire le dossier de premier niveau que contient l'archive.

```exec
mkdir -p ~/byte-layers/docker/l2/app
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C ~/byte-layers/docker/l2/app
```

Listez le dossier pour voir ce que vous avez reçu. `ls -A` montre aussi les fichiers dont le nom commence par un point :

```exec
ls -A ~/byte-layers/docker/l2/app
```

Vous devez lire ces fichiers et dossiers :

```text
.dockerignore
README.md
package-lock.json
package.json
spec
src
```

## Trouver dans ses fichiers ce qu'il faut pour la lancer

Avant d'écrire un Dockerfile, on regarde ce que l'application demande. Trois questions suffisent ici : ce qu'il faut installer, comment elle démarre, et sur quel port elle écoute. Le fichier `package.json` est la fiche d'un projet Node.js, et il répond aux deux premières. Lisez-le :

```exec
cat ~/byte-layers/docker/l2/app/package.json
```

Voici les parties qui vous intéressent :

```text
  "scripts": {
    "dev": "nodemon -L src/index.js"
  },
  "dependencies": {
    "express": "^5.2.1",
    ...
  },
  "devDependencies": {
    "nodemon": "^3.1.9"
  },
```

Ce tableau dit ce qu'il faut en tirer.

| Ce que vous lisez | Ce que cela vous apprend |
|---|---|
| `dependencies` | les bibliothèques dont l'application a besoin pour tourner, ses **dépendances** |
| `devDependencies` | les outils réservés au développement, comme `nodemon`, qui relance l'application à chaque modification du code. Ils n'ont rien à faire dans l'image |
| `scripts`, `dev` | le fichier que le développeur fait tourner, `src/index.js`. Sans `nodemon`, l'application démarre donc avec `node src/index.js` |
| le fichier `package-lock.json`, à côté | les versions exactes de ces bibliothèques. `npm` est l'outil qui les installe, et `npm ci` respecte exactement ces versions |

Il reste le port. `grep` cherche un mot dans un fichier, et un serveur Node.js écoute avec une fonction nommée `listen` :

```exec
grep listen ~/byte-layers/docker/l2/app/src/index.js
```

Vous devez lire la ligne qui donne la réponse, le port 3000 :

```text
    app.listen(3000, () => console.log('Listening on port 3000'));
```

Un mot prête à confusion dans la suite, car `node` désigne trois choses : le programme qui exécute Node.js, comme dans `node src/index.js`, l'image de base `node:22-alpine`, et un utilisateur fourni par cette image, que vous rencontrerez plus loin. Vous avez maintenant tout ce qu'il faut pour écrire le Dockerfile.

```ack
J'ai le code, et je sais ce qu'il installe, comment il démarre et sur quel port il écoute
```

# Compléter le Dockerfile

## Les six instructions dont vous avez besoin

Un **Dockerfile** est un fichier texte qui décrit comment fabriquer une image, une instruction par ligne. Voici celles qui vous serviront, avec leur forme générale.

| Instruction | Rôle |
|---|---|
| `FROM image:tag` | part d'une image existante, l'**image de base** |
| `WORKDIR /dossier` | se place dans ce dossier, créé s'il n'existe pas, pour la suite et pour le conteneur |
| `COPY source destination` | copie des fichiers du projet vers l'image. `COPY . .` copie tout le projet dans le dossier courant |
| `RUN commande` | exécute une commande **pendant la construction** et garde son résultat dans l'image. Ici, `npm ci --omit=dev` : cette option écarte les `devDependencies`, qui ne servent à rien en production et alourdissent l'image |
| `EXPOSE port` | documente le port d'écoute, sans rien publier |
| `CMD ["programme", "argument"]` | enregistre ce que chaque conteneur lance à son démarrage. C'est la **forme exec**, une liste entre crochets, à préférer |

⚖️ Ce lab copie tout le projet avant d'installer, parce que c'est le plus simple à lire. Cet ordre refait l'installation à chaque modification du code. Un prochain cours, « Accélérer un build avec le cache », montre comment l'éviter.

## Remplacer les blancs du Dockerfile

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

Créez le fichier avec ses blancs. La forme `cat > fichier <<'EOF'` écrit dans le fichier les lignes qui suivent, jusqu'à la ligne `EOF` :

```exec
cat > ~/byte-layers/docker/l2/app/Dockerfile <<'EOF'
# TODO : partir de l'image node:22-alpine, c'est-à-dire Node.js 22 sur Alpine, un Linux minimal

# TODO : se placer dans le dossier /app

# TODO : copier tout le projet dans le dossier courant de l'image

# TODO : installer les dépendances avec npm ci, sans celles de développement

# TODO : documenter le port d'écoute de l'application

# TODO : démarrer l'application avec node src/index.js, en forme exec
EOF
```

Ouvrez maintenant `~/byte-layers/docker/l2/app/Dockerfile` dans votre éditeur, remplacez chaque `# TODO` par l'instruction qu'il décrit, et enregistrez. Si vous n'avez pas d'éditeur graphique, `nano ~/byte-layers/docker/l2/app/Dockerfile` en ouvre un dans le terminal : `Ctrl+O` puis `Entrée` enregistrent, et `Ctrl+X` quitte. Une ligne qui commence par `#` est un commentaire : vous pouvez garder les vôtres ou les supprimer, Docker les ignore.

Construisez ensuite l'image. `-t` lui donne un nom et un tag, et le dernier argument est le **contexte de build**, le dossier dont `COPY` peut prendre des fichiers :

```exec
docker build -t layers-l2-todo:1.0 ~/byte-layers/docker/l2/app
```

Le build compte quatre étapes, de `[1/4]` à `[4/4]`, et celle de `npm ci` est la plus longue. Si Docker répond par une erreur, la ligne fautive est marquée `>>>` et la raison se trouve à la fin du message. Si c'est un `RUN` qui échoue, la dernière ligne dit seulement `exit code`, et la raison est plus haut, dans ce que la commande a écrit. Corrigez le fichier, puis relancez cette même commande autant de fois que nécessaire.

> 📖 [Référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [`docker build`](https://docs.docker.com/reference/cli/docker/build/)

```hint
Le fichier suit l'ordre des `# TODO` : une instruction par blanc, soit six en tout. Le premier se remplace par `FROM node:22-alpine`.
```

```hint
La ligne d'installation s'écrit `RUN npm ci --omit=dev`. Le premier point de `COPY . .` désigne le contexte de build, et le second le dossier courant de l'image.
```

```hint
Le port est celui que vous avez lu dans `src/index.js`. En forme exec, chaque mot de la commande est une chaîne : `["node", "src/index.js"]`.
```

```verify
I=layers-l2-todo:1.0
if [ ! -f "$HOME/byte-layers/docker/l2/app/package.json" ]; then
  echo "Le code de l'application n'est pas dans ~/byte-layers/docker/l2/app. Refaites l'étape précédente."
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
cat > ~/byte-layers/docker/l2/app/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
EXPOSE 3000
CMD ["node", "src/index.js"]
EOF
docker build -t layers-l2-todo:1.0 ~/byte-layers/docker/l2/app
```
````

# Lancer l'application

## Compléter le docker run, puis demander la page

Votre image est prête. Il reste à en faire un conteneur, en vous servant de ce que vous savez déjà de `docker run`. Voici la commande à compléter. Recopiez-la dans votre terminal en remplaçant les trois blancs entre `<` et `>`, sans garder ces signes :

```bash
docker run -d --name layers-l2-todo -p <port-machine>:<port-conteneur> <image>
```

Le port de votre machine est **28321**, celui du conteneur est le port d'écoute de l'application, et l'image est celle que vous venez de construire. Regardez ensuite l'état du conteneur :

```exec
docker ps
```

Sur la ligne de `layers-l2-todo`, la colonne `STATUS` doit commencer par `Up`, et la colonne `PORTS` doit montrer `28321->3000/tcp`. Si cette ligne manque, le conteneur s'est arrêté : `docker logs layers-l2-todo` vous dira pourquoi. Demandez maintenant la page. Si `curl` répond par une erreur de connexion, l'application démarrait encore : attendez une seconde et relancez.

```exec
curl http://localhost:28321
```

`curl` affiche le code HTML de la page, dans lequel vous devez repérer son titre :

```text
<title>Todo App</title>
```

> 📖 [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/)

```hint
Le port se donne sous la forme `<port-machine>:<port-conteneur>`, et l'image vient en dernier sur la ligne.
```

```hint
L'application écoute sur le port 3000 : `-p 28321:3000`. Si le nom est déjà pris après un essai, supprimez l'ancien conteneur avec `docker rm -f layers-l2-todo`.
```

## Ajouter une tâche pour prouver que l'application fonctionne

Une page qui répond ne prouve pas que l'application marche : ajoutez une tâche. Le plus parlant est d'ouvrir `http://localhost:28321` dans un navigateur, ou depuis l'onglet **PORTS** de VS Code sur un poste hébergé, d'y écrire une tâche et de cliquer sur le bouton d'ajout. Vous pouvez aussi utiliser cette commande, où `-X POST` envoie des données, `-H` précise leur format, ici JSON, et `-d` indique lesquelles :

```exec
curl -X POST -H 'Content-Type: application/json' -d '{"name":"Écrire mon Dockerfile"}' http://localhost:28321/items
```

La réponse reprend votre tâche, avec un identifiant. Relisez ensuite la liste des tâches. L'application les enregistre dans un petit fichier de base de données, et les renvoie à cette adresse :

```exec
curl http://localhost:28321/items
```

Vous devez lire votre tâche dans la réponse, avec un identifiant différent de celui-ci :

```text
[{"id":"1f0c9c7e-…","name":"Écrire mon Dockerfile","completed":false}]
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
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28321) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"Todo App"*) : ;;
  *) echo "Le port 28321 ne renvoie pas l'application. Rappel : -p <port-machine>:<port-conteneur>, et l'application écoute sur 3000."; exit 1 ;;
esac
ITEMS=$(curl -s --max-time 5 http://localhost:28321/items)
case "$ITEMS" in
  ""|"[]") echo "L'application répond, mais sa liste est vide. Ajoutez une tâche."; exit 1 ;;
esac
echo "L'application tourne et enregistre vos tâches."
```

````solution
```bash
docker run -d --name layers-l2-todo -p 28321:3000 layers-l2-todo:1.0
sleep 3 # laisse à l'application le temps de démarrer
curl -X POST -H 'Content-Type: application/json' -d '{"name":"Écrire mon Dockerfile"}' http://localhost:28321/items
```
````

# Garder un secret hors de l'image

## Voir un fichier .env entrer dans l'image

Un projet réel contient souvent un fichier `.env`, où se rangent des valeurs sensibles comme des mots de passe. Or `COPY . .` copie tout. Créez ce fichier, avec une valeur fictive, reconstruisez sous un autre tag, puis regardez ce que contient l'image. Ce qui suit le nom de l'image remplace la commande de démarrage :

```exec
echo 'SESSION_SECRET=valeur-fictive' > ~/byte-layers/docker/l2/app/.env
docker build -t layers-l2-todo:1.1 ~/byte-layers/docker/l2/app
docker run --rm layers-l2-todo:1.1 ls -A
```

`.env` figure dans la liste :

```text
.dockerignore
.env
README.md
node_modules
package-lock.json
package.json
spec
src
```

Toute personne qui récupère cette image peut lire ce secret. Le projet fournit déjà un `.dockerignore`, le fichier qui liste ce que Docker doit laisser de côté, un motif par ligne. Voyez ce qu'il contient :

```exec
cat ~/byte-layers/docker/l2/app/.dockerignore
```

Il n'exclut que deux noms :

```text
node_modules
Dockerfile
```

Rien ne protège donc `.env`. Exclure `node_modules` a aussi son importance : ce dossier, s'il existe sur votre machine, alourdirait le contexte pour rien, et `npm ci` le prépare de toute façon dans l'image.

## Exclure .env avec le .dockerignore

Ajoutez à `~/byte-layers/docker/l2/app/.dockerignore` la ligne qui exclut le fichier `.env`, en gardant les lignes existantes. Reconstruisez ensuite sous le tag `1.2`, et regardez à nouveau le dossier :

```exec
docker build -t layers-l2-todo:1.2 ~/byte-layers/docker/l2/app
docker run --rm layers-l2-todo:1.2 ls -A
```

`.env` ne doit plus apparaître dans la liste, alors que `src` doit toujours y être :

```text
.dockerignore
README.md
node_modules
package-lock.json
package.json
spec
src
```

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
  echo "Le fichier .env est encore dans $I. Ajoutez-le à ~/byte-layers/docker/l2/app/.dockerignore, puis reconstruisez."
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
echo '.env' >> ~/byte-layers/docker/l2/app/.dockerignore
docker build -t layers-l2-todo:1.2 ~/byte-layers/docker/l2/app
```
````

⚖️ L'image `1.1` contient toujours ce fichier, car une image ne change jamais. Dans un vrai projet, un secret qui a fuité doit aussi être changé. Un prochain cours, « Un secret ne va pas dans l'image », reprend ce sujet.

# Ne plus tourner en administrateur

## Voir l'application échouer sans les droits d'administrateur

Par défaut, l'application tourne avec l'utilisateur `root`, l'administrateur de Linux, sans en avoir besoin. L'image `node:22-alpine` fournit déjà un utilisateur ordinaire, nommé `node`. L'option `--user` de `docker run` permet d'essayer avec lui avant de toucher au Dockerfile :

```exec
docker run --rm --user node layers-l2-todo:1.2
```

L'application s'arrête aussitôt sur une erreur. Pas d'inquiétude, c'est ce qu'il fallait voir, et l'erreur se lit en trois temps.

- **Symptôme** : `Error: EACCES: permission denied, mkdir '/etc/todos'`.
- **Cause** : l'application range sa base de données dans `/etc/todos`, un dossier qu'elle tente de créer au démarrage. Sous `/etc`, seul `root` peut le faire.
- **Correctif** : préparer ce dossier pendant la construction, quand on a encore les droits, et le donner à l'utilisateur `node`.

## Préparer le dossier, puis passer à l'utilisateur node

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

Avant de lancer la suite, faites une prévision. Vous allez supprimer le conteneur actuel pour le remplacer. La tâche que vous avez ajoutée sera-t-elle encore là ? Gardez votre réponse en tête, puis construisez sous le tag `1.3` et remplacez le conteneur par un nouveau, avec le même nom et le même port :

```exec
docker build -t layers-l2-todo:1.3 ~/byte-layers/docker/l2/app
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
U=http://localhost:28321/items
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
NEW=""
for i in 1 2 3 4 5; do
  NEW=$(curl -s --max-time 2 -X POST -H 'Content-Type: application/json' -d '{"name":"Essai de la verification"}' "$U") && [ -n "$NEW" ] && break
  sleep 1
done
case "$NEW" in
  *"Essai de la verification"*) : ;;
  *) echo "L'application n'arrive pas à enregistrer une tâche. Le dossier de sa base lui appartient-il ? Lisez : docker logs $C"; exit 1 ;;
esac
ID=$(printf '%s' "$NEW" | sed 's/.*"id":"\([^"]*\)".*/\1/')
curl -s --max-time 5 -X DELETE "$U/$ID" >/dev/null
echo "L'application tourne avec l'utilisateur $(docker exec "$C" id -un) et enregistre ses tâches."
```

````solution
```bash
cat > ~/byte-layers/docker/l2/app/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
RUN mkdir -p /etc/todos && chown node /etc/todos
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
EOF
docker build -t layers-l2-todo:1.3 ~/byte-layers/docker/l2/app
docker rm -f layers-l2-todo
docker run -d --name layers-l2-todo -p 28321:3000 layers-l2-todo:1.3
```
````

## Constater ce qu'est devenue votre tâche

Revenez à votre prévision, et relisez la liste des tâches. Si `curl` répond par une erreur de connexion, attendez une seconde et relancez :

```exec
curl http://localhost:28321/items
```

La liste est vide :

```text
[]
```

Vos tâches étaient dans la couche d'écriture de l'ancien conteneur, l'espace qui lui est propre et qui a été supprimé avec lui. Elles ne pouvaient pas être dans l'image, qui ne change jamais. Un prochain cours, « Garder ses données », montre comment les conserver.

```ack
J'ai vu la liste vide, et je sais pourquoi
```

# Supprimer ce que le lab a créé

## Retirer le conteneur, les images et le dossier

Cette fois, la commande n'est pas donnée. Vous connaissez `docker rm -f`, pour le conteneur. `docker image rm` supprime des images, à condition de lui donner chaque nom et chaque tag, et `rm -rf` efface un dossier sans demander confirmation : vérifiez bien le chemin.

**Critères :**

- le conteneur `layers-l2-todo` n'existe plus ;
- les images `layers-l2-todo:1.0`, `1.1`, `1.2` et `1.3` n'existent plus ;
- le dossier `~/byte-layers/docker/l2/app` n'existe plus. Le dossier parent `~/byte-layers/docker/l2`, lui, peut rester.

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
if [ -e "$HOME/byte-layers/docker/l2/app" ]; then
  echo "Le dossier ~/byte-layers/docker/l2/app existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
docker rm -f layers-l2-todo
docker image rm layers-l2-todo:1.0 layers-l2-todo:1.1 layers-l2-todo:1.2 layers-l2-todo:1.3
rm -rf ~/byte-layers/docker/l2/app
```
````

## Récap

- Pour écrire un Dockerfile, on lit d'abord ce que l'application demande : ses dépendances, sa commande de démarrage, son port.
- `FROM`, `WORKDIR`, `COPY`, `RUN`, `EXPOSE` et `CMD` suffisent à conteneuriser une application courante.
- `.dockerignore` garde hors de l'image ce qui n'a rien à y faire.
- `USER` retire les droits d'administrateur, et ce qui en a besoin se prépare avant cette ligne, pendant le build.

Le [dossier `solution/` de ce lab](https://github.com/byte-layers/courses-containers/tree/main/docker-containerize-app/solution) garde le Dockerfile et le `.dockerignore` complets. Pour vous tester sans guide, faites le challenge [Conteneuriser une application inconnue](https://byte-layers.com/fr/challenges/docker-dockerfile-challenge).
