---
title: "Deux applications derrière nginx, puis Traefik"
description: "Cas pratique avec des blancs à compléter : une application Node.js et sa base MySQL, un second service, un reverse proxy nginx, puis son remplacement par Traefik."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 90
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Sur un serveur, plusieurs applications se partagent une seule adresse. Pour cela, on place devant elles un **reverse proxy** : un programme qui reçoit toutes les demandes (les requêtes HTTP) et transmet chacune à la bonne application.

Dans ce cas pratique, vous déployez deux applications conteneurisées, chacune dans son projet Compose et son réseau. Vous les placez ensuite derrière nginx, un reverse proxy que l'on configure dans un fichier. Vous remplacez enfin nginx par Traefik, un reverse proxy qui lit ses routes dans Docker, et vous comparez les deux. Vous complétez vous-même les `# TODO` : le bouton de vérification contrôle le résultat, les indices se dévoilent un par un, et la solution reste en dernier recours.

**Niveau** : vous savez écrire un fichier Compose avec des services, des volumes et des réseaux, comme dans « Décrire une application avec Compose », et vous savez qu'un conteneur en joint un autre par son nom, comme dans « Relier des conteneurs et publier un port ». Vous savez lire un `Dockerfile`, comme dans « Écrire le Dockerfile d'une application ». Vous n'avez besoin de connaître ni nginx, ni Traefik, ni Node.js : ce qu'il en faut est expliqué ici.

**Ce qu'il faut** : Docker et Compose qui répondent, un terminal bash ou zsh (sous Windows, celui de WSL), `curl`, un éditeur de texte, les ports **28386** à **28389** libres et environ 1 Go de mémoire pour les conteneurs, dont près de la moitié pour MySQL. Tout ce que vous créez porte le préfixe `layers-l8-web` ou `layers-l8-public`, et vos fichiers vivent dans `~/layers-l8/web`.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Le plan du cas pratique

## L'architecture à construire

Voici où vous arriverez. Une demande entre par un seul port, le 28387, et le reverse proxy choisit l'application d'après le début du chemin de l'adresse :

```
                                réseau public (layers-l8-public)
                  ┌─────────────────────────────────────────────┐
                  │                                             │
navigateur,       │                 /app1/ ──► app1:3000 ───────┼──► mysql:3306
curl ───► 28387 ──┼──► proxy                   (app1_net : app1 et mysql)
                  │                 /app2/ ──► app2:80
                  │                            (app2_net : app2 seul)
                  └─────────────────────────────────────────────┘
```

Ce schéma encode trois choix, et chacun a sa raison :

- **Seul le proxy publie un port.** Les applications ne sont joignables que par lui : c'est le seul endroit à surveiller et à protéger.
- **MySQL reste sur le réseau privé `app1_net`.** Le proxy n'a aucune raison de joindre la base. Comme il n'est pas sur ce réseau, il ne le peut pas, même en cas d'erreur dans sa configuration.
- **Le réseau public est créé à part.** Vous allez remplacer un proxy par un autre. Si le réseau appartenait au projet de nginx, `docker compose down` tenterait de le supprimer alors que les applications l'utilisent encore, et échouerait.

## Les ports utilisés par le lab

Chaque port du lab a un rôle. Les deux premiers ne servent qu'aux tests directs, avant l'arrivée du proxy, et vous les retirerez ensuite :

| Port | Rôle | Durée de vie |
|---|---|---|
| 28386 | `app1` en direct | jusqu'à l'arrivée du proxy |
| 28389 | `app2` en direct | jusqu'à l'arrivée du proxy |
| 28387 | l'entrée du reverse proxy, nginx puis Traefik | jusqu'à la fin |
| 28388 | le tableau de bord de Traefik | jusqu'à la fin |

Vous interrogerez ces ports avec `curl` dans le terminal, et avec le navigateur, à l'adresse `http://localhost:28387` pour l'entrée du proxy.

## Créer le dossier de travail

Vous allez créer un dossier par projet Compose, comme on le ferait sur un serveur :

```exec
mkdir -p ~/layers-l8/web/app1 ~/layers-l8/web/app2 ~/layers-l8/web/nginx/conf.d ~/layers-l8/web/traefik
```

Vous éditerez plusieurs fichiers de ce dossier. S'il n'apparaît pas dans votre éditeur, ouvrez chaque fichier par le menu **File > Open File**, en saisissant son chemin.

```ack
J'ai compris le plan, et le dossier est prêt
```

# Application 1 : Node.js et MySQL

## Les fichiers fournis de l'application

`app1` est une petite application Node.js, avec le framework web Express et une connexion à MySQL. Vous ne l'écrivez pas : ce lab porte sur son déploiement. Il faut néanmoins savoir ce qu'elle attend, et voici donc ses trois fichiers.

Le premier, `package.json`, liste les bibliothèques dont elle a besoin :

```exec
cat > ~/layers-l8/web/app1/package.json <<'EOF'
{
  "name": "app1",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "4.21.2",
    "mysql2": "3.14.1"
  }
}
EOF
```

Le second, `index.js`, est le programme. Lisez trois choses : il lit sa connexion dans quatre variables d'environnement, il tente de se connecter **une seule fois** au démarrage, et sa page d'accueil interroge vraiment la base. La page `/about` servira à voir quel chemin l'application reçoit derrière un proxy.

```exec
cat > ~/layers-l8/web/app1/index.js <<'EOF'
const express = require('express');
const mysql = require('mysql2');

const app = express();
const port = 3000;

// Les informations de connexion viennent des variables d'environnement
const connection = mysql.createConnection({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

// Une seule tentative au démarrage : sans base, l'application s'arrête
connection.connect(err => {
  if (err) {
    console.error('Connexion à MySQL impossible :', err.message);
    process.exit(1);
  }
  console.log('Connectée à MySQL');
});

// La page d'accueil interroge vraiment la base
app.get('/', (req, res) => {
  connection.query('SELECT VERSION() AS version', (err, rows) => {
    if (err) return res.status(500).send('Erreur MySQL : ' + err.message + '\n');
    res.send('App 1 : connectée à MySQL ' + rows[0].version + '\n');
  });
});

// Une seconde page, pour contrôler le chemin reçu derrière un proxy
app.get('/about', (req, res) => {
  res.send('App 1 : page about, chemin reçu ' + req.originalUrl + '\n');
});

app.listen(port, () => {
  console.log('App 1 écoute sur le port ' + port);
});
EOF
```

Le troisième est le `Dockerfile`, qui construit l'image. `USER node` fait tourner le programme sans les droits de root, avec un utilisateur déjà prévu dans l'image `node` :

```exec
cat > ~/layers-l8/web/app1/Dockerfile <<'EOF'
FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY index.js ./
USER node
EXPOSE 3000
CMD ["node", "index.js"]
EOF
```

⚖️ Un raccourci à connaître : pour garder ce lab court, il n'y a pas de fichier `package-lock.json`. Dans un vrai projet, on le versionne et on remplace `npm install` par `npm ci`, pour installer exactement les mêmes versions à chaque construction.

```verify
for F in package.json index.js Dockerfile; do
  if [ ! -s "$HOME/layers-l8/web/app1/$F" ]; then
    echo "Le fichier ~/layers-l8/web/app1/$F manque. Relancez le bloc qui le crée."
    exit 1
  fi
done
if ! grep -q 'SELECT VERSION' "$HOME/layers-l8/web/app1/index.js"; then
  echo "index.js n'a pas le contenu attendu. Relancez le bloc qui le crée."
  exit 1
fi
echo "Les trois fichiers de l'application sont en place."
```

````solution
Il n'y a rien à compléter ici : relancez les trois blocs de cette section, dans l'ordre, puis vérifiez à nouveau.
````

## Décrire l'application et sa base avec Compose

Vous disposez maintenant de l'application, et il reste à écrire le fichier qui la lance avec sa base. Plutôt que de lancer `docker build` vous-même, vous demandez à Compose de construire l'image. Il faut pour cela deux clés côte à côte dans le service :

| Clé | Rôle |
|---|---|
| `build: .` | construire l'image à partir du `Dockerfile` du dossier courant |
| `image: layers-l8-web-app1` | le nom donné à cette image, comme `docker build -t` |

L'application attend quatre variables d'environnement. Leurs valeurs doivent correspondre à ce que le service `mysql` crée à son premier démarrage :

| Variable de `app1` | Valeur | D'où elle vient |
|---|---|---|
| `DB_HOST` | `mysql` | le nom du service, qui sert d'adresse sur le réseau |
| `DB_USER` | `app1` | `MYSQL_USER` du service `mysql` |
| `DB_PASSWORD` | `app1-dev` | `MYSQL_PASSWORD` du service `mysql` |
| `DB_NAME` | `app1db` | `MYSQL_DATABASE` du service `mysql` |

Créez le fichier de départ, puis complétez ses blancs dans votre éditeur **avant** de le lancer. La clé `name` donne son nom au projet, et ce nom préfixe ceux des conteneurs, des réseaux et des volumes :

```exec
cat > ~/layers-l8/web/app1/compose.yaml <<'EOF'
name: layers-l8-web-app1
services:
  app1:
    build: .
    image: layers-l8-web-app1
    # TODO : les quatre variables d'environnement, sous la clé environment
    # TODO : publier le port 28386 de la machine vers le port 3000 du conteneur
    networks:
      - app1_net
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: root-dev
      MYSQL_DATABASE: app1db
      MYSQL_USER: app1
      MYSQL_PASSWORD: app1-dev
    volumes:
      - db_data:/var/lib/mysql
    # TODO : placer ce service sur le réseau app1_net
volumes:
  db_data:
networks:
  # TODO : déclarer le réseau app1_net
EOF
```

⚖️ Ces mots de passe sont écrits en clair pour un usage de développement, et ils n'iront nulle part ailleurs. Dans un vrai projet, ils sortent du fichier : le bonus « Sortir les variables dans un fichier .env » fait un premier pas dans ce sens.

Une fois le fichier complété, construisez et lancez le projet. `--build` demande de reconstruire l'image. Le premier lancement prend une minute, le temps de télécharger les images et les bibliothèques :

```exec
cd ~/layers-l8/web/app1 && docker compose up -d --build
```

Ne cherchez pas encore à ouvrir la page, et regardez d'abord l'état des deux conteneurs. `-a` affiche aussi ceux qui sont arrêtés :

```exec
cd ~/layers-l8/web/app1 && docker compose ps -a
```

Dans la colonne `STATUS`, vous devez voir MySQL en marche (`Up`), et `app1` arrêté (`Exited (1)`). C'est le résultat attendu à ce stade, et la section suivante l'explique. Vérifiez votre fichier, puis passez à la suite.

Si `app1` tourne, c'est que MySQL était déjà prêt, par exemple parce que vous aviez déjà lancé le projet. Pour reproduire ce démarrage à vide, lancez depuis `~/layers-l8/web/app1` la commande `docker compose down -v`, qui supprime aussi le volume de la base, puis la commande `up` ci-dessus.

```hint
`environment:` se place à la même indentation que `networks:`, avec une ligne par variable, décalée de deux espaces : `DB_HOST: mysql`. Pour le port : `ports:`, puis la ligne `- "28386:3000"`.
```

```hint
Le service `mysql` utilise la même écriture que `app1` : `networks:`, puis `- app1_net`. Tout en bas, sous `networks:`, écrivez `app1_net:` décalé de deux espaces, sans rien après les deux-points : Compose crée alors un réseau avec les réglages par défaut.
```

```verify
A=layers-l8-web-app1-app1-1
M=layers-l8-web-app1-mysql-1
if ! docker inspect $A >/dev/null 2>&1 || ! docker inspect $M >/dev/null 2>&1; then
  echo "Les conteneurs du projet n'existent pas. Complétez ~/layers-l8/web/app1/compose.yaml, puis lancez docker compose up -d --build depuis ce dossier."
  exit 1
fi
ENV=$(docker inspect $A --format '{{range .Config.Env}}{{println .}}{{end}}')
for V in DB_HOST=mysql DB_USER=app1 DB_PASSWORD=app1-dev DB_NAME=app1db; do
  if ! echo "$ENV" | grep -qx "$V"; then
    echo "Dans le service app1, la variable attendue $V n'est pas définie."
    exit 1
  fi
done
case "$(docker inspect $A --format '{{range $p, $b := .HostConfig.PortBindings}}{{$p}}={{range $b}}{{.HostPort}}{{end}}{{end}}')" in
  *3000/tcp=28386*) : ;;
  *) echo "Le port 28386 de la machine ne mène pas au port 3000 de app1."; exit 1 ;;
esac
for C in $A $M; do
  case "$(docker inspect $C --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
    *layers-l8-web-app1_app1_net*) : ;;
    *) echo "$C n'est pas sur le réseau app1_net."; exit 1 ;;
  esac
done
if [ "$(docker inspect $M --format '{{.State.Running}}')" != "true" ]; then
  echo "MySQL ne tourne pas. Lisez : docker compose logs mysql, depuis ~/layers-l8/web/app1."
  exit 1
fi
echo "Le fichier Compose est correct, et les deux services partagent le réseau app1_net."
```

````solution
```bash
cd ~/layers-l8/web/app1
docker compose down -v 2>/dev/null
cat > compose.yaml <<'EOF'
name: layers-l8-web-app1
services:
  app1:
    build: .
    image: layers-l8-web-app1
    environment:
      DB_HOST: mysql
      DB_USER: app1
      DB_PASSWORD: app1-dev
      DB_NAME: app1db
    ports:
      - "28386:3000"
    networks:
      - app1_net
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: root-dev
      MYSQL_DATABASE: app1db
      MYSQL_USER: app1
      MYSQL_PASSWORD: app1-dev
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - app1_net
volumes:
  db_data:
networks:
  app1_net:
EOF
docker compose up -d --build
```
````

## Faire attendre app1 que MySQL soit prêt

Votre fichier est juste, et `app1` s'arrête quand même. Pas d'inquiétude, c'est un problème classique. Ses journaux, que `docker compose logs` affiche, disent ce qui s'est passé :

```exec
cd ~/layers-l8/web/app1 && docker compose logs app1
```

- **Symptôme** : le message `Connexion à MySQL impossible : connect ECONNREFUSED`, suivi de l'arrêt du conteneur.
- **Cause** : Compose a démarré les deux conteneurs en même temps. L'application a tenté sa seule connexion à l'instant où MySQL s'initialisait encore, ce qui prend plusieurs secondes.
- **Correctif** : ne démarrer `app1` que lorsque MySQL répond vraiment. Il faut pour cela deux choses : un test qui dit si MySQL est prêt, le **healthcheck**, et une condition d'attente dans `app1`.

Voici la forme d'un healthcheck, à placer dans le service `mysql`. Le tableau qui suit en décompose les réglages :

```yaml
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 5s
      timeout: 3s
      retries: 30
```

| Clé | Rôle |
|---|---|
| `test` | la commande lancée dans le conteneur : un code de retour 0 veut dire « en bonne santé ». `mysqladmin ping` demande à MySQL s'il répond |
| `interval` | le temps entre deux essais |
| `timeout` | le temps laissé à la commande pour répondre |
| `retries` | le nombre d'échecs de suite avant de déclarer le conteneur `unhealthy` : ici 30 essais espacés de 5 secondes, soit environ deux minutes et demie |

Le `-h 127.0.0.1` a son importance. Pendant son initialisation, l'image MySQL lance un serveur temporaire qui écoute seulement sur un fichier local (un socket Unix), pas sur le réseau. Avec `localhost`, le test passerait par ce fichier, et il réussirait trop tôt. Avec l'adresse IP, il passe par le réseau et ne réussit qu'avec le vrai serveur.

Dans `app1`, `depends_on` dit d'attendre : sa forme longue précise la condition, ici `service_healthy`.

```yaml
    depends_on:
      mysql:
        condition: service_healthy
```

Ouvrez `~/layers-l8/web/app1/compose.yaml` et ajoutez ces deux blocs tels qu'ils sont indentés ci-dessus : le `healthcheck` dans le service `mysql`, et le `depends_on` dans le service `app1`. Relancez ensuite le projet. `up -d` ne recrée que ce qui a changé, et il attend maintenant que MySQL soit prêt :

```exec
cd ~/layers-l8/web/app1 && docker compose up -d
```

Contrôlez que l'application répond, après lui avoir laissé deux secondes pour démarrer. `curl` interroge directement le port :

```exec
sleep 2
curl http://localhost:28386/
```

Vous devez lire une ligne comme celle-ci, et elle prouve que l'application a réellement interrogé la base :

```
App 1 : connectée à MySQL 8.4.13
```

⚖️ `depends_on` ne couvre que le démarrage, et cette application de démonstration garde une seule connexion. Si MySQL redémarre plus tard, `app1` reste en marche, mais sa page répond `500` avec le message `Can't add new command when connection is in closed state`. Une clé `restart` n'y changerait rien, puisque le conteneur ne s'arrête pas. Si cela vous arrive pendant le lab, lancez `docker compose restart app1` depuis `~/layers-l8/web/app1`. Dans un vrai projet, l'application utilise un groupe de connexions, un *pool* (`mysql.createPool`), qui se reconnecte seul.

```hint
Le `healthcheck` se place sous `mysql:`, à la même indentation que `image:`. Le `depends_on` se place sous `app1:`, à la même indentation que `build:`.
```

```verify
A=layers-l8-web-app1-app1-1
M=layers-l8-web-app1-mysql-1
HEALTH=$(docker inspect $M --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
if [ -z "$HEALTH" ]; then
  echo "MySQL n'a pas de healthcheck. Ajoutez le bloc au service mysql, puis relancez docker compose up -d."
  exit 1
fi
if [ "$HEALTH" != "healthy" ]; then
  echo "MySQL n'est pas encore en bonne santé (état : $HEALTH). Attendez quelques secondes, puis vérifiez à nouveau."
  exit 1
fi
if ! (cd "$HOME/layers-l8/web/app1" && docker compose config 2>/dev/null) | grep -q 'condition: service_healthy'; then
  echo "app1 n'attend pas MySQL : il manque le depends_on avec condition: service_healthy."
  exit 1
fi
if [ "$(docker inspect $A --format '{{.State.Running}}')" != "true" ]; then
  echo "app1 ne tourne pas. Lisez : docker compose logs app1, depuis ~/layers-l8/web/app1."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28386/ | grep -q 'connectée à MySQL'; then
  echo "http://localhost:28386/ ne répond pas la version de MySQL."
  exit 1
fi
echo "app1 attend sa base, et lit vraiment MySQL."
```

````solution
```bash
cd ~/layers-l8/web/app1
cat > compose.yaml <<'EOF'
name: layers-l8-web-app1
services:
  app1:
    build: .
    image: layers-l8-web-app1
    environment:
      DB_HOST: mysql
      DB_USER: app1
      DB_PASSWORD: app1-dev
      DB_NAME: app1db
    ports:
      - "28386:3000"
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      - app1_net
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: root-dev
      MYSQL_DATABASE: app1db
      MYSQL_USER: app1
      MYSQL_PASSWORD: app1-dev
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 5s
      timeout: 3s
      retries: 30
    networks:
      - app1_net
volumes:
  db_data:
networks:
  app1_net:
EOF
docker compose up -d
sleep 2
```
````

> 📖 [`healthcheck` dans Compose](https://docs.docker.com/reference/compose-file/services/#healthcheck) · [`depends_on` dans Compose](https://docs.docker.com/reference/compose-file/services/#depends_on)

# Application 2 : le service whoami

## Écrire le fichier Compose de app2 sans modèle

Vous avez été guidé pas à pas pour `app1`. La seconde application est plus simple : vous écrivez cette fois le fichier en entier.

`app2` utilise l'image `traefik/whoami`. C'est un tout petit serveur web qui répond en affichant la demande qu'il a reçue : le chemin et les en-têtes, ces lignes de texte qui accompagnent une demande HTTP. Il est idéal pour voir ce qu'un reverse proxy transmet à une application.

**Objectif.** Créez le fichier `~/layers-l8/web/app2/compose.yaml`. Pour pouvoir l'ouvrir dans l'éditeur, créez-le d'abord vide, avec `touch ~/layers-l8/web/app2/compose.yaml`. Il doit avoir les caractéristiques suivantes :

| Élément | Valeur |
|---|---|
| Nom du projet | `layers-l8-web-app2` |
| Service | `app2` |
| Image | `traefik/whoami:v1.12.0` |
| Réseau | son propre réseau, `app2_net` |
| Port | le 28389 de la machine vers le port 80 du conteneur, sur lequel écoute le serveur |

Lancez-le, puis interrogez-le sur le chemin `/test`, un chemin inventé puisque ce serveur répond à tous :

```exec
cd ~/layers-l8/web/app2 && docker compose up -d
sleep 1
curl http://localhost:28389/test
```

Vous devez lire une réponse qui contient ces deux lignes, parmi d'autres :

```
Hostname: 74f5e3c9dd1e
GET /test HTTP/1.1
```

La ligne `GET` compte : `whoami` y montre le chemin qu'il a reçu. Le `Hostname` sera différent chez vous, car c'est l'identifiant court du conteneur.

```hint
Partez du fichier de `app1`, sans `build`, `environment`, `depends_on` ni `volumes`. Il reste `name`, le service avec `image`, `ports` et `networks`, puis la section `networks:` du bas.
```

```verify
A=layers-l8-web-app2-app2-1
if [ "$(docker inspect $A --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$A ne tourne pas. Écrivez ~/layers-l8/web/app2/compose.yaml, puis lancez docker compose up -d depuis ce dossier."
  exit 1
fi
case "$(docker inspect $A --format '{{.Config.Image}}')" in
  traefik/whoami:v1.12.0) : ;;
  *) echo "app2 doit utiliser l'image traefik/whoami:v1.12.0."; exit 1 ;;
esac
case "$(docker inspect $A --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
  *layers-l8-web-app2_app2_net*) : ;;
  *) echo "app2 n'est pas sur son propre réseau app2_net."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://localhost:28389/test | grep -q '^GET /test'; then
  echo "http://localhost:28389/test ne répond pas comme attendu : vérifiez que le port 28389 mène au port 80 du conteneur."
  exit 1
fi
echo "app2 répond, sur son propre réseau."
```

````solution
```bash
cd ~/layers-l8/web/app2
docker compose down 2>/dev/null
cat > compose.yaml <<'EOF'
name: layers-l8-web-app2
services:
  app2:
    image: traefik/whoami:v1.12.0
    ports:
      - "28389:80"
    networks:
      - app2_net
networks:
  app2_net:
EOF
docker compose up -d
sleep 1
```
````

# Le reverse proxy nginx

## Créer le réseau public et y brancher les applications

Vos deux applications tournent, chacune isolée sur son réseau et avec son port. Pour qu'un proxy puisse les joindre, il faut un réseau commun. Vous le créez à la main, car il doit survivre au passage de nginx à Traefik :

```exec
docker network create layers-l8-public
```

Il faut maintenant modifier les **deux** fichiers `compose.yaml`, ceux de `app1` et de `app2`, de trois façons :

1. **Retirer la clé `ports:`** du service `app1` et du service `app2`. C'est le proxy qui recevra les demandes : en laissant ces ports, on garderait une porte dérobée qui le contourne.
2. **Ajouter le service au réseau public.** Sous `networks:`, ajoutez une ligne `- public_net` dans le service `app1`, et de même dans `app2`. Le service `mysql` ne change pas.
3. **Déclarer ce réseau en bas du fichier**, comme un réseau qui existe déjà.

Voici le bloc à ajouter à la section `networks:` du bas de chacun des deux fichiers. `external: true` dit à Compose que ce réseau existe déjà, et qu'il ne doit donc ni le créer ni le supprimer. `name` donne son nom réel, car `public_net` n'est que le nom local à ce fichier :

```yaml
  public_net:
    name: layers-l8-public
    external: true
```

Appliquez ces changements dans les deux projets :

```exec
cd ~/layers-l8/web/app1 && docker compose up -d
cd ~/layers-l8/web/app2 && docker compose up -d
```

Vérifiez qui est sur le réseau public. `--format` n'affiche ici que les noms des conteneurs branchés :

```exec
docker network inspect layers-l8-public --format '{{range .Containers}}{{.Name}} {{end}}'
```

Vous devez lire `layers-l8-web-app1-app1-1` et `layers-l8-web-app2-app2-1`, dans un ordre quelconque, et pas le conteneur de MySQL.

Le nom du service sert déjà d'adresse sur chaque réseau du conteneur : le proxy pourra donc joindre `app1` et `app2` sans autre réglage. Sur ce réseau partagé, chaque service doit donc avoir un nom qui lui est propre.

```hint
Dans `app1`, la clé `networks:` du service contient maintenant deux lignes : `- app1_net` et `- public_net`. Dans `app2`, ce sont `- app2_net` et `- public_net`.
```

```verify
if ! docker network inspect layers-l8-public >/dev/null 2>&1; then
  echo "Le réseau layers-l8-public n'existe pas. Lancez docker network create layers-l8-public."
  exit 1
fi
for N in app1 app2; do
  A=layers-l8-web-$N-$N-1
  if [ "$(docker inspect $A --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
    echo "$A ne tourne pas. Lisez : docker compose logs, depuis ~/layers-l8/web/$N."
    exit 1
  fi
  case " $(docker inspect $A --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
    *" layers-l8-public "*) : ;;
    *) echo "$N n'est pas sur le réseau layers-l8-public. Vérifiez public_net, dans le service et en bas du fichier."; exit 1 ;;
  esac
  case " $(docker inspect $A --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
    *"_${N}_net "*) : ;;
    *) echo "$N n'est plus sur son réseau privé ${N}_net : gardez-le dans le service."; exit 1 ;;
  esac
  if [ -n "$(docker port $A)" ]; then
    echo "$N publie encore un port : retirez sa clé ports."
    exit 1
  fi
done
case " $(docker inspect layers-l8-web-app1-mysql-1 --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}' 2>/dev/null)" in
  *" layers-l8-public "*) echo "MySQL ne doit pas être sur le réseau public."; exit 1 ;;
esac
echo "Les deux applications sont sur le réseau public, et ne publient plus aucun port."
```

````solution
```bash
docker network create layers-l8-public 2>/dev/null
cd ~/layers-l8/web/app1
cat > compose.yaml <<'EOF'
name: layers-l8-web-app1
services:
  app1:
    build: .
    image: layers-l8-web-app1
    environment:
      DB_HOST: mysql
      DB_USER: app1
      DB_PASSWORD: app1-dev
      DB_NAME: app1db
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      - app1_net
      - public_net
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: root-dev
      MYSQL_DATABASE: app1db
      MYSQL_USER: app1
      MYSQL_PASSWORD: app1-dev
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 5s
      timeout: 3s
      retries: 30
    networks:
      - app1_net
volumes:
  db_data:
networks:
  app1_net:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
cd ~/layers-l8/web/app2
cat > compose.yaml <<'EOF'
name: layers-l8-web-app2
services:
  app2:
    image: traefik/whoami:v1.12.0
    networks:
      - app2_net
      - public_net
networks:
  app2_net:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
sleep 2
```
````

## Écrire la configuration de nginx

Les applications sont prêtes, et leur port direct a disparu : elles ne sont pour l'instant plus joignables de l'extérieur. Il reste à leur donner une porte d'entrée.

Dans nginx, chaque ligne se termine par un point-virgule, un bloc `server` décrit un site, et un bloc `location` dit quoi faire pour les chemins qui commencent d'une certaine façon. `proxy_pass` transmet la demande à une autre adresse et renvoie sa réponse :

```nginx
location /app1/ {
    proxy_pass http://app1:3000/;
}
```

Une application ne connaît pas le préfixe `/app1` : elle attend `/`, ou `/about`. Il faut donc que le proxy le retire, et c'est la barre oblique finale de `proxy_pass` qui s'en charge. Elle demande de remplacer le chemin de `location` par `/`. Ce détail casse beaucoup de configurations, et voici ce qu'on obtient réellement pour la demande `/app1/about` :

| `location` | `proxy_pass` | Chemin reçu par l'application | Résultat |
|---|---|---|---|
| `/app1/` | `http://app1:3000/` | `/about` | `200`, la bonne forme |
| `/app1` | `http://app1:3000/` | `//about` | `404`, seul `/app1` sans rien après fonctionne |
| `/app1/` | `http://app1:3000` | `/app1/about` | `404`, le préfixe n'est pas retiré |

Un proxy change aussi ce que voit l'application : chaque demande semble maintenant venir de lui. Pour transmettre ce qu'il a vu du visiteur, on ajoute des en-têtes avec `proxy_set_header`. Les noms qui commencent par `$` sont des variables, que nginx remplit à chaque demande :

| Ligne | Ce qu'elle transmet |
|---|---|
| `proxy_set_header Host $host;` | le nom de site demandé par le visiteur (le nom d'hôte, sans le port), sans quoi l'application lirait `app1:3000` |
| `proxy_set_header X-Real-IP $remote_addr;` | l'adresse du visiteur |
| `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` | la liste des adresses traversées |
| `proxy_set_header X-Forwarded-Proto $scheme;` | `http` ou `https`, tel que vu par le proxy |

L'image nginx lit tous les fichiers `.conf` du dossier `/etc/nginx/conf.d`, et le vôtre y remplacera sa page d'accueil par défaut. Créez ce fichier, puis complétez son blanc dans votre éditeur. La ligne `absolute_redirect off` évite un piège : quand nginx redirige `/app1` vers `/app1/`, il écrirait sinon une adresse complète, sans le port ni le domaine que vous utilisez :

```exec
cat > ~/layers-l8/web/nginx/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;

    location /app1/ {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://app1:3000/;
    }

    # TODO : le même bloc pour /app2/, vers le port 80 du service app2
}
EOF
```

Le contrôle et la solution de ce fichier viennent à la section suivante, une fois nginx lancé.

```hint
Le bloc `/app2/` reprend celui de `/app1/`, avec `proxy_pass http://app2:80/;` et sa barre oblique finale.
```

## Lancer nginx et ouvrir les deux applications

La configuration est écrite, et il reste à lancer nginx dans son propre projet Compose. Créez ce fichier, puis complétez ses blancs :

```exec
cat > ~/layers-l8/web/nginx/compose.yaml <<'EOF'
name: layers-l8-web-nginx
services:
  nginx:
    image: nginx:1.30-alpine
    # TODO : publier le port 28387 de la machine vers le port 80 du conteneur
    # TODO : monter le dossier ./conf.d sur /etc/nginx/conf.d, en lecture seule
    networks:
      - public_net
networks:
  public_net:
    name: layers-l8-public
    external: true
EOF
```

On monte le **dossier** `conf.d` et non le fichier seul : beaucoup d'éditeurs remplacent un fichier en l'enregistrant, et le conteneur, resté attaché à l'ancien, ne verrait pas vos modifications. Pour la lecture seule, une ligne de volume se termine par `:ro`.

Lancez nginx. Les applications doivent déjà tourner, ce qui est le cas :

```exec
cd ~/layers-l8/web/nginx && docker compose up -d
```

Interrogez les deux applications à travers la même porte :

```exec
curl http://localhost:28387/app1/
curl http://localhost:28387/app1/about
curl http://localhost:28387/app2/test
```

Voici ce que vous devez lire, avec `whoami` qui ajoute d'autres lignes. Notez que `whoami` affiche `GET /test`, sans le préfixe `/app2` :

```
App 1 : connectée à MySQL 8.4.13
App 1 : page about, chemin reçu /about
Hostname: 3e2c9b1f0a7d
GET /test HTTP/1.1
Host: localhost
X-Forwarded-For: 172.19.0.1
X-Forwarded-Proto: http
X-Real-Ip: 172.19.0.1
```

Si vous corrigez la configuration ensuite, nginx ne la relit pas tout seul. Lancez `docker compose exec nginx nginx -s reload` depuis `~/layers-l8/web/nginx`, ou `docker compose up -d` si nginx s'est arrêté. Dans ses journaux, la ligne `can not modify /etc/nginx/conf.d/default.conf` est normale : elle vient de la lecture seule, et ne signale aucune panne.

Le plan promettait que le proxy joindrait les applications, mais pas la base. Vérifiez-le depuis nginx, avec `getent hosts`, qui cherche l'adresse d'un nom :

```exec
cd ~/layers-l8/web/nginx
docker compose exec nginx getent hosts app1
docker compose exec nginx getent hosts mysql
```

La première commande affiche une adresse IP. La seconde n'affiche rien et se termine en erreur, ce qui est le résultat attendu : `mysql` n'existe pas sur le réseau public.

Ouvrez maintenant ces adresses dans le navigateur : `http://localhost:28387/app1/` et `http://localhost:28387/app2/`.

```hint
Dans le fichier Compose : `ports:` puis `- "28387:80"`, et `volumes:` puis `- ./conf.d:/etc/nginx/conf.d:ro`, à la même indentation que `networks:`.
```

```verify
P=layers-l8-web-nginx-nginx-1
if [ "$(docker inspect $P --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "nginx ne tourne pas. Complétez ~/layers-l8/web/nginx/compose.yaml et conf.d/default.conf, puis lancez docker compose up -d. En cas d'erreur, lisez : docker compose logs nginx"
  exit 1
fi
RW=$(docker inspect $P --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{.Type}} {{.RW}}{{end}}{{end}}')
if [ "$RW" != "bind false" ]; then
  echo "Le dossier conf.d n'est pas monté en lecture seule sur /etc/nginx/conf.d (trouvé : ${RW:-rien})."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app1/ | grep -q 'connectée à MySQL'; then
  echo "/app1/ ne répond pas la version de MySQL. Vérifiez le port 28387 et le bloc location /app1/."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app1/about | grep -q 'chemin reçu /about'; then
  echo "/app1/about n'arrive pas sur /about : vérifiez les barres obliques de location et de proxy_pass."
  exit 1
fi
OUT=$(curl -s --max-time 5 http://localhost:28387/app2/test)
if ! echo "$OUT" | grep -q '^GET /test '; then
  echo "/app2/test n'arrive pas sur /test : vérifiez le bloc /app2/ et sa barre oblique finale. Après une modification : docker compose exec nginx nginx -s reload"
  exit 1
fi
if ! echo "$OUT" | grep -q '^X-Real-Ip: '; then
  echo "app2 ne reçoit pas l'en-tête X-Real-IP : il manque les proxy_set_header dans le bloc /app2/."
  exit 1
fi
echo "Une seule porte d'entrée, et chaque chemin mène à la bonne application."
```

````solution
```bash
cat > ~/layers-l8/web/nginx/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;

    location /app1/ {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://app1:3000/;
    }

    location /app2/ {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://app2:80/;
    }
}
EOF
cd ~/layers-l8/web/nginx
docker compose down 2>/dev/null
cat > compose.yaml <<'EOF'
name: layers-l8-web-nginx
services:
  nginx:
    image: nginx:1.30-alpine
    ports:
      - "28387:80"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
    networks:
      - public_net
networks:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
sleep 1
```
````

> 📖 [`proxy_pass` de nginx](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass) · [Les réseaux externes dans Compose](https://docs.docker.com/reference/compose-file/networks/#external)

## Provoquer la panne de nginx quand une application manque

Tout marche, tant que tout est allumé. Essayez ce qui arrive quand le proxy redémarre alors qu'une application n'est pas encore revenue, par exemple après une mise à jour. Supprimez `app2`, relancez nginx, et regardez ses journaux. `--tail 1` n'affiche que la dernière ligne :

```exec
cd ~/layers-l8/web/app2 && docker compose down
cd ~/layers-l8/web/nginx
docker compose restart
sleep 2
docker compose logs nginx --tail 1
```

Vous devez lire que nginx s'est arrêté sur cette erreur :

```
nginx-1  | nginx: [emerg] host not found in upstream "app2" in /etc/nginx/conf.d/default.conf:18
```

Interrogez maintenant `app1`, qui n'a aucun problème. `-s` retire la barre de progression, `-o /dev/null` n'affiche pas la page, et `-w` écrit le code de réponse :

```exec
curl -s -o /dev/null -w 'app1 : %{http_code}\n' http://localhost:28387/app1/
```

Le code `000`, et l'erreur de `curl` qui l'accompagne, veulent dire que personne n'a répondu : une seule application absente, et **les deux** deviennent inaccessibles. La cause est que nginx traduit les noms écrits dans `proxy_pass` une seule fois, à son démarrage. On peut corriger cela en restant sur nginx, avec la directive `resolver 127.0.0.11` et une variable dans `proxy_pass`, comme le détaille le cours « Plusieurs applications derrière un reverse proxy ». Ici, retenez le constat : par défaut, nginx dépend de l'état du réseau au moment où il lit son fichier. Traefik fonctionne autrement.

Remettez tout en marche avant de continuer, `app2` d'abord :

```exec
cd ~/layers-l8/web/app2 && docker compose up -d
cd ~/layers-l8/web/nginx && docker compose up -d
```

```verify
if ! curl -s --max-time 5 http://localhost:28387/app2/test | grep -q '^GET /test '; then
  echo "/app2/test ne répond pas : relancez app2, puis nginx, avec le dernier bloc de commandes."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app1/ | grep -q 'connectée à MySQL'; then
  echo "/app1/ ne répond pas. Lisez : docker compose logs nginx, depuis ~/layers-l8/web/nginx."
  exit 1
fi
echo "Tout est revenu."
```

````solution
```bash
cd ~/layers-l8/web/app2 && docker compose up -d
cd ~/layers-l8/web/nginx && docker compose up -d
sleep 2
```
````

# Le passage à Traefik

## Ce que Traefik fait autrement

Avec nginx, ajouter une application veut dire modifier le fichier du proxy, puis le recharger. Traefik renverse le raisonnement : il surveille Docker, et chaque application décrit **elle-même** sa route, par des étiquettes (les *labels*) posées sur son conteneur. Il n'y a plus de fichier de routes à tenir.

Quatre mots de Traefik reviennent ensuite partout, et chacun a un équivalent dans ce que vous venez de faire avec nginx :

| Mot Traefik | Son rôle | Son équivalent chez nginx |
|---|---|---|
| **entrypoint** | le port d'écoute | `listen 80` |
| **router** | la règle qui reconnaît une demande | `location /app1/` |
| **middleware** | une transformation de la demande | la barre oblique finale qui retire le préfixe |
| **service** | l'application qui reçoit la demande | `proxy_pass http://app1:3000` |

Attention au mot « service » : celui de Traefik désigne une destination de ses routes, et n'est pas le service de Compose, même s'ils portent souvent le même nom.

## Libérer le port et lancer Traefik

Traefik va prendre la place de nginx, sur le même port 28387. Deux programmes ne peuvent pas écouter sur le même port. Si vous lanciez Traefik sans arrêter nginx, vous obtiendriez :

```
Bind for 0.0.0.0:28387 failed: port is already allocated
```

Arrêtez donc nginx. `down` supprime son conteneur, mais pas le réseau public, déclaré `external` : c'est pour cela qu'il a été créé à part. Les applications continuent de tourner.

```exec
cd ~/layers-l8/web/nginx && docker compose down
```

Le fichier de Traefik tient en peu de lignes. Sa configuration passe par des options, données sous `command`, et que ce tableau décompose :

| Option ou clé | Rôle |
|---|---|
| `--providers.docker=true` | lire les routes dans Docker |
| `--providers.docker.exposedbydefault=false` | n'exposer que les conteneurs qui portent `traefik.enable=true` |
| `--entrypoints.web.address=:80` | ouvrir un entrypoint nommé `web`, sur le port 80 du conteneur |
| `--api.insecure=true` | activer le tableau de bord sur le port 8080, sans mot de passe |
| le volume `/var/run/docker.sock` | le socket de Docker, le fichier par lequel on commande le moteur |

`exposedbydefault=false` compte vraiment : par défaut, Traefik crée une route pour **tous** les conteneurs qu'il voit, y compris MySQL et ceux de vos autres projets. Vous choisissez ainsi ce qui est exposé, plutôt que de le subir.

⚠️ Deux réglages sont à connaître avant de partir en production. Qui accède au socket de Docker contrôle tout le moteur, donc en pratique la machine : `:ro` limite le fichier, pas les commandes que l'on envoie par lui. Sur un serveur, on place souvent devant lui un proxy de socket, qui filtre ces commandes. Et `--api.insecure=true` ouvre le tableau de bord sans authentification : ce lab le publie donc sur `127.0.0.1` seulement, pour le fermer au reste du réseau, et ce réglage est à proscrire sur un serveur.

Créez le fichier, puis complétez ses blancs :

```exec
cat > ~/layers-l8/web/traefik/compose.yaml <<'EOF'
name: layers-l8-web-traefik
services:
  traefik:
    image: traefik:v3.7.17
    command:
      - --api.insecure=true
      - --providers.docker=true
      # TODO : n'exposer que les conteneurs qui le demandent
      # TODO : ouvrir l'entrypoint web sur le port 80 du conteneur
    # TODO : publier le port 28387 vers le 80, et le port 28388 de 127.0.0.1 vers le 8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - public_net
networks:
  public_net:
    name: layers-l8-public
    external: true
EOF
```

Lancez Traefik, puis demandez-lui la liste de ses routes, par l'API de son tableau de bord. La réponse est au format JSON, sur une seule longue ligne :

```exec
cd ~/layers-l8/web/traefik && docker compose up -d
sleep 3
curl http://localhost:28388/api/http/routers
```

Vous devez y lire deux routes internes de Traefik, `api@internal` et `dashboard@internal`, et rien pour `app1`, `app2` ni MySQL : c'est `exposedbydefault=false` qui agit. Ouvrez aussi le tableau de bord dans le navigateur, à l'adresse `http://localhost:28388/dashboard/`, avec la barre oblique finale.

```hint
Les deux options manquantes sont dans le tableau, à écrire comme les autres, précédées de `- `. Les deux ports vont sous une clé `ports:`, à la même indentation que `command:`, chacun sur sa ligne : `- "28387:80"` et `- "127.0.0.1:28388:8080"`.
```

```verify
if docker ps --format '{{.Names}}' | grep -q '^layers-l8-web-nginx-'; then
  echo "nginx tourne encore. Lancez docker compose down depuis ~/layers-l8/web/nginx."
  exit 1
fi
T=layers-l8-web-traefik-traefik-1
if [ "$(docker inspect $T --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Traefik ne tourne pas. Complétez ~/layers-l8/web/traefik/compose.yaml, puis lancez docker compose up -d. En cas d'erreur, lisez : docker compose logs traefik"
  exit 1
fi
ARGS=$(docker inspect $T --format '{{json .Args}}')
case "$ARGS" in
  *exposedbydefault=false*|*exposedByDefault=false*) : ;;
  *) echo "Traefik expose encore tous les conteneurs : il manque --providers.docker.exposedbydefault=false."; exit 1 ;;
esac
case "$ARGS" in
  *entrypoints.web.address=:80*|*entryPoints.web.address=:80*) : ;;
  *) echo "L'entrypoint web n'est pas ouvert sur le port 80 : il manque --entrypoints.web.address=:80."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://localhost:28388/api/http/routers | grep -q 'dashboard@internal'; then
  echo "L'API de Traefik ne répond pas sur le port 28388 : ce port doit mener au 8080 du conteneur."
  exit 1
fi
if [ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:28387/)" != "404" ]; then
  echo "Le port 28387 ne mène pas à Traefik : il doit mener au port 80 du conteneur. Traefik doit y répondre 404, faute de route."
  exit 1
fi
echo "Traefik écoute, et n'expose encore rien."
```

````solution
```bash
cd ~/layers-l8/web/nginx && docker compose down
cd ~/layers-l8/web/traefik
docker compose down 2>/dev/null
cat > compose.yaml <<'EOF'
name: layers-l8-web-traefik
services:
  traefik:
    image: traefik:v3.7.17
    command:
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
    ports:
      - "28387:80"
      - "127.0.0.1:28388:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - public_net
networks:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
sleep 3
```
````

## Donner une route à app2 avec des labels

Traefik attend des instructions, et c'est à l'application de les donner. Une clé `labels` s'ajoute au service, à la même indentation que `networks:`. Les labels de route suivent le même schéma : le type d'objet (`routers`), le nom que vous choisissez (`app2`), puis le réglage. Sans autre précision, un router écoute sur l'entrypoint `web`, et se rattache au seul service déclaré sur ce conteneur.

| Label | Rôle |
|---|---|
| `traefik.enable=true` | exposer ce conteneur |
| `` traefik.http.routers.app2.rule=PathPrefix(`/app2`) `` | la règle : les chemins qui commencent par `/app2`. Notez les accents graves autour du chemin |
| `traefik.http.services.app2.loadbalancer.server.port=80` | le port du conteneur à joindre. `loadbalancer` rappelle qu'un service Traefik peut répartir les demandes entre plusieurs conteneurs |
| `traefik.docker.network=layers-l8-public` | le réseau à utiliser pour joindre ce conteneur |

Ce dernier label n'a rien d'accessoire. Votre conteneur est sur deux réseaux, et Traefik ne sait pas lequel il partage avec lui. Sans ce label, il en choisit un au hasard, à chaque création du conteneur. Lors de la préparation de ce lab, sur 8 recréations de `app1` sans ce label, il a pris 2 fois le réseau privé, et la route répond alors `504 Gateway Timeout`, après 30 secondes d'attente. Une panne aléatoire de ce genre est difficile à diagnostiquer : il vaut donc mieux toujours le préciser.

Ajoutez ce bloc au service `app2`, dans `~/layers-l8/web/app2/compose.yaml`, en complétant les blancs à partir du tableau :

```yaml
    labels:
      - "traefik.enable=true"
      # TODO : la règle du router app2, sur le préfixe /app2
      # TODO : le port du service app2
      # TODO : le réseau à utiliser
```

Appliquez le changement, puis interrogez `app2`. Vous ne touchez pas au proxy, et il suffit de quelques secondes pour qu'il voie le nouveau label :

```exec
cd ~/layers-l8/web/app2 && docker compose up -d
sleep 3
curl http://localhost:28387/app2/test
```

Regardez la ligne qui commence par `GET` dans la réponse :

```
GET /app2/test HTTP/1.1
```

`whoami` a répondu, mais avec le préfixe : contrairement à nginx et sa barre oblique, Traefik transmet le chemin tel quel. `whoami` répond à n'importe quel chemin, ce qui cache le problème. La prochaine section le fait apparaître.

```hint
Une règle s'écrit entre guillemets doubles, avec des accents graves autour du chemin : `` - "traefik.http.routers.app2.rule=PathPrefix(`/app2`)" ``. Les deux autres se recopient du tableau, entre guillemets aussi.
```

```verify
A=layers-l8-web-app2-app2-1
L=$(docker inspect $A --format '{{range $k, $v := .Config.Labels}}{{println $k "=" $v}}{{end}}' 2>/dev/null)
if ! echo "$L" | grep -q '^traefik.enable = true'; then
  echo "Le service app2 n'a pas le label traefik.enable=true. Ajoutez le bloc labels, puis relancez docker compose up -d."
  exit 1
fi
if ! echo "$L" | grep -q '^traefik.docker.network = layers-l8-public'; then
  echo "Il manque le label traefik.docker.network=layers-l8-public."
  exit 1
fi
if ! echo "$L" | grep -q '^traefik.http.services.app2.loadbalancer.server.port = 80'; then
  echo "Il manque le label traefik.http.services.app2.loadbalancer.server.port=80."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app2/test | grep -q '^Hostname: '; then
  echo "http://localhost:28387/app2/test ne mène pas à whoami. Consultez les routes : curl http://localhost:28388/api/http/routers"
  exit 1
fi
echo "app2 a sa route, sans que Traefik ait été modifié."
```

````solution
```bash
cd ~/layers-l8/web/app2
cat > compose.yaml <<'EOF'
name: layers-l8-web-app2
services:
  app2:
    image: traefik/whoami:v1.12.0
    networks:
      - app2_net
      - public_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app2.rule=PathPrefix(`/app2`)"
      - "traefik.http.services.app2.loadbalancer.server.port=80"
      - "traefik.docker.network=layers-l8-public"
networks:
  app2_net:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
sleep 3
```
````

## Router app1 et retirer le préfixe avec un middleware

Faites maintenant la même chose pour `app1`, seul : ajoutez au service `app1` les mêmes labels, avec le router `app1`, la règle sur `/app1`, le service `app1` et son port 3000. Appliquez, puis interrogez l'application :

```exec
cd ~/layers-l8/web/app1 && docker compose up -d
sleep 3
curl http://localhost:28387/app1/
```

Cette fois, la page contient une erreur :

```
<pre>Cannot GET /app1/</pre>
```

- **Symptôme** : une erreur 404 dont le texte, `Cannot GET`, vient d'Express. La demande a donc bien traversé Traefik et atteint `app1`, et la route fonctionne.
- **Cause** : Traefik transmet le chemin tel quel, `/app1/`, alors que l'application ne connaît que `/` et `/about`.
- **Correctif** : ajouter un **middleware** `stripprefix`, qui retire le préfixe avant de transmettre.

Un middleware se déclare d'un côté, puis s'attache à un router de l'autre. Ajoutez donc ces deux labels au service `app1`. Le nom `app1-strip` est à votre choix, à condition d'être le même sur les deux lignes :

```yaml
      - "traefik.http.middlewares.app1-strip.stripprefix.prefixes=/app1"
      - "traefik.http.routers.app1.middlewares=app1-strip"
```

**Pour `app2`, à vous d'écrire ces deux labels**, avec le préfixe `/app2` et le nom `app2-strip`. Appliquez les changements :

```exec
cd ~/layers-l8/web/app1 && docker compose up -d
cd ~/layers-l8/web/app2 && docker compose up -d
```

Attendez quelques secondes, le temps que Traefik voie les changements, puis interrogez les deux applications à nouveau :

```exec
sleep 3
curl http://localhost:28387/app1/
curl http://localhost:28387/app1/about
curl http://localhost:28387/app2/test
```

Vous devez maintenant lire la version de MySQL, puis `chemin reçu /about`, puis `GET /test`, sans le préfixe. `whoami` affiche aussi un en-tête `X-Forwarded-Prefix: /app2` : Traefik y indique le préfixe retiré, ce qui permet à une application de reconstruire ses liens.

```hint
Pour `app1`, il faut à la fin six labels : `traefik.enable`, la règle, le middleware, son attachement au router, le port du service (3000) et le réseau.
```

```verify
for N in app1 app2; do
  A=layers-l8-web-$N-$N-1
  L=$(docker inspect $A --format '{{range $k, $v := .Config.Labels}}{{println $k "=" $v}}{{end}}' 2>/dev/null)
  if ! echo "$L" | grep -q '^traefik.docker.network = layers-l8-public'; then
    echo "$N n'a pas le label traefik.docker.network=layers-l8-public."
    exit 1
  fi
done
if ! curl -s --max-time 5 http://localhost:28387/app1/ | grep -q 'connectée à MySQL'; then
  echo "/app1/ ne répond pas la version de MySQL. « Cannot GET » : le middleware n'est pas attaché. « 404 page not found » : Traefik n'a pas de route. Consultez : curl http://localhost:28388/api/http/routers"
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app1/about | grep -q 'chemin reçu /about'; then
  echo "/app1/about n'arrive pas sur /about."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28387/app2/test | grep -q '^GET /test '; then
  echo "/app2/test garde son préfixe : il manque le middleware stripprefix de app2, ou son attachement au router."
  exit 1
fi
if curl -s --max-time 5 http://localhost:28388/api/http/routers | grep -qi 'mysql'; then
  echo "Traefik a une route vers MySQL : vérifiez --providers.docker.exposedbydefault=false."
  exit 1
fi
echo "Traefik sert les deux applications, sans préfixe, et rien d'autre."
```

````solution
```bash
cd ~/layers-l8/web/app1
cat > compose.yaml <<'EOF'
name: layers-l8-web-app1
services:
  app1:
    build: .
    image: layers-l8-web-app1
    environment:
      DB_HOST: mysql
      DB_USER: app1
      DB_PASSWORD: app1-dev
      DB_NAME: app1db
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      - app1_net
      - public_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app1.rule=PathPrefix(`/app1`)"
      - "traefik.http.routers.app1.middlewares=app1-strip"
      - "traefik.http.middlewares.app1-strip.stripprefix.prefixes=/app1"
      - "traefik.http.services.app1.loadbalancer.server.port=3000"
      - "traefik.docker.network=layers-l8-public"
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: root-dev
      MYSQL_DATABASE: app1db
      MYSQL_USER: app1
      MYSQL_PASSWORD: app1-dev
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 5s
      timeout: 3s
      retries: 30
    networks:
      - app1_net
volumes:
  db_data:
networks:
  app1_net:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
cd ~/layers-l8/web/app2
cat > compose.yaml <<'EOF'
name: layers-l8-web-app2
services:
  app2:
    image: traefik/whoami:v1.12.0
    networks:
      - app2_net
      - public_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app2.rule=PathPrefix(`/app2`)"
      - "traefik.http.routers.app2.middlewares=app2-strip"
      - "traefik.http.middlewares.app2-strip.stripprefix.prefixes=/app2"
      - "traefik.http.services.app2.loadbalancer.server.port=80"
      - "traefik.docker.network=layers-l8-public"
networks:
  app2_net:
  public_net:
    name: layers-l8-public
    external: true
EOF
docker compose up -d
sleep 4
```
````

> 📖 [Traefik et Docker](https://doc.traefik.io/traefik/reference/install-configuration/providers/docker/) · [Le middleware `stripPrefix`](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/stripprefix/) · [Les labels de routage](https://doc.traefik.io/traefik/reference/routing-configuration/other-providers/docker/)

## Rejouer la panne avec Traefik

Vous aviez fait tomber nginx en supprimant `app2`. Rejouez la même panne avec Traefik : supprimez `app2`, redémarrez le proxy, et interrogez les deux applications. La commande `curl` est celle de la panne de nginx :

```exec
cd ~/layers-l8/web/app2 && docker compose down
cd ~/layers-l8/web/traefik && docker compose restart
sleep 3
curl -s -o /dev/null -w 'app1 : %{http_code}\n' http://localhost:28387/app1/
curl -s -o /dev/null -w 'app2 : %{http_code}\n' http://localhost:28387/app2/
```

Vous devez lire que `app1` répond, et que seule `app2` est concernée :

```
app1 : 200
app2 : 404
```

Rallumez `app2`, sans toucher au proxy. Traefik la retrouve tout seul :

```exec
cd ~/layers-l8/web/app2 && docker compose up -d
sleep 3
curl -s -o /dev/null -w 'app2 : %{http_code}\n' http://localhost:28387/app2/
```

Vous devez lire `app2 : 200`. Rouvrez aussi le tableau de bord, à l'adresse `http://localhost:28388/dashboard/` : les routes de `app1` et `app2` y apparaissent à présent, avec leur middleware.

```verify
if [ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:28387/app2/)" != "200" ]; then
  echo "app2 ne répond pas : relancez-la avec docker compose up -d, depuis ~/layers-l8/web/app2, puis attendez quelques secondes."
  exit 1
fi
if [ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:28387/app1/)" != "200" ]; then
  echo "app1 ne répond pas."
  exit 1
fi
echo "La panne d'une application ne touche plus l'autre."
```

````solution
```bash
cd ~/layers-l8/web/app2 && docker compose up -d
sleep 3
```
````

# Le bilan des deux proxys

## Contrôler le cas pratique complet

Vous avez déployé les deux applications et les deux proxys. Ce dernier contrôle reprend toute l'architecture du début :

- `app1` et sa base tournent, et `app1` attend que MySQL soit prêt ;
- `app2` tourne sur son propre réseau ;
- seul Traefik publie des ports, et nginx est arrêté ;
- `/app1/` et `/app2/` répondent par un seul port, sans préfixe ;
- MySQL reste hors du réseau public.

```verify
fail() { echo "$1"; exit 1; }
for C in layers-l8-web-app1-app1-1 layers-l8-web-app1-mysql-1 layers-l8-web-app2-app2-1 layers-l8-web-traefik-traefik-1; do
  [ "$(docker inspect $C --format '{{.State.Running}}' 2>/dev/null)" = "true" ] || fail "$C ne tourne pas."
done
docker ps --format '{{.Names}}' | grep -q '^layers-l8-web-nginx-' && fail "nginx tourne encore."
for C in layers-l8-web-app1-app1-1 layers-l8-web-app1-mysql-1 layers-l8-web-app2-app2-1; do
  [ -z "$(docker port $C)" ] || fail "$C publie un port : seul le proxy doit le faire."
done
case " $(docker inspect layers-l8-web-app1-mysql-1 --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
  *" layers-l8-public "*) fail "MySQL ne doit pas être sur le réseau public." ;;
esac
[ "$(docker inspect layers-l8-web-app1-mysql-1 --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')" = "healthy" ] || fail "MySQL n'est pas en bonne santé : vérifiez son healthcheck."
(cd "$HOME/layers-l8/web/app1" && docker compose config 2>/dev/null) | grep -q 'condition: service_healthy' || fail "app1 n'attend pas MySQL : il manque le depends_on avec condition: service_healthy."
case " $(docker inspect layers-l8-web-app2-app2-1 --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
  *"_app2_net "*) : ;;
  *) fail "app2 n'est plus sur son réseau privé app2_net." ;;
esac
curl -s --max-time 5 http://localhost:28387/app1/ | grep -q 'connectée à MySQL' || fail "/app1/ ne répond pas la version de MySQL."
curl -s --max-time 5 http://localhost:28387/app2/test | grep -q '^GET /test ' || fail "/app2/test ne répond pas sans préfixe."
echo "L'architecture est complète : deux applications, une seule porte."
```

````solution
Ce contrôle ne demande rien de nouveau : si un élément manque, reprenez la section qui le construit. Ces commandes relancent les trois projets, dans l'ordre, et arrêtent nginx :

```bash
cd ~/layers-l8/web/nginx && docker compose down
cd ~/layers-l8/web/app1 && docker compose up -d
cd ~/layers-l8/web/app2 && docker compose up -d
cd ~/layers-l8/web/traefik && docker compose up -d
sleep 4
```
````

## Choisir entre nginx et Traefik

Vous avez maintenant utilisé les deux, et voici ce qu'il faut en retenir. Aucun n'est meilleur dans l'absolu : la question est de savoir qui tient les routes.

| | nginx | Traefik |
|---|---|---|
| Où sont les routes | dans un fichier du proxy | dans les labels de chaque application |
| Ajouter une application | modifier le fichier, puis recharger | lancer l'application avec ses labels |
| Une application manque au démarrage | le proxy refuse de démarrer, sauf avec `resolver` et une variable | seule cette route répond 404 |
| Retirer le préfixe | la barre oblique finale de `proxy_pass` | un middleware `stripprefix` |
| Accès nécessaire | aucun droit sur Docker | le socket de Docker, un droit fort |
| Dépendance créée | le proxy connaît les applications | chaque application porte des labels propres à Traefik |
| Voir l'état des routes | lire le fichier | le tableau de bord, ou son API |
| On le préfère pour | peu d'applications stables, tout voir dans un fichier | des applications qui vont et viennent sur un même hôte Docker |

⚖️ Ce lab route par préfixe de chemin, ce qui a une limite : une application qui écrit dans ses pages un lien absolu, comme `/style.css`, le demandera à la racine du site, où elle n'est plus. Router par nom de site, comme le fait le bonus « Router par nom de site », évite ce problème. De même, ce lab reste en HTTP vers le proxy. Sur un serveur, c'est au reverse proxy de porter le HTTPS, et Traefik sait obtenir seul des certificats, auprès de Let's Encrypt : c'est l'étape suivante à regarder.

```ack
J'ai compris ce qui distingue les deux proxys
```

# Aller plus loin : quatre bonus au choix

## Comment utiliser ces bonus

Ces bonus sont indépendants, et vous pouvez les faire dans l'ordre que vous voulez, ou aller directement au nettoyage. Vous êtes ici en autonomie, avec la documentation, et aucun contrôle ne les vérifie. Le dossier [`solution/bonus/`](../solution/bonus/) de ce contenu donne un exemple de chaque résultat.

## Sortir les variables dans un fichier .env

Les mots de passe de `app1` sont écrits dans son fichier Compose, qui finira dans un dépôt Git. La clé `env_file` les déplace dans un fichier à part, que l'on ne versionne pas.

1. Créez `~/layers-l8/web/app1/.env` avec les variables `DB_*` et `MYSQL_*`, en gardant les mêmes valeurs.
2. Remplacez les deux blocs `environment:` par `env_file: .env`.
3. Dans un vrai dépôt, ajoutez `.env` au `.gitignore`, et versionnez un `.env.example` sans vrais mots de passe.

Testez avec `docker compose up -d`, puis `curl http://localhost:28387/app1/`.

⚖️ Ce fichier unique a une limite : `app1` reçoit aussi `MYSQL_ROOT_PASSWORD`, dont elle n'a pas besoin. Un fichier par service éviterait cela.

⚠️ **Piège, si vous changez un mot de passe.** Le symptôme est `Access denied for user 'app1'` dans les journaux de `app1`. La cause est que l'image MySQL ne lit `MYSQL_PASSWORD` qu'à son tout premier démarrage, quand le volume est vide : ensuite, le mot de passe vit dans la base. Le correctif, en développement, est `docker compose down -v`, qui repart d'un volume vide et efface donc les données.

> 📖 [`env_file` dans Compose](https://docs.docker.com/reference/compose-file/services/#env_file)

## Ajouter Adminer pour administrer la base

Adminer est une interface web pour MySQL, en une seule image, qui montre l'intérêt d'avoir un proxy : une application de plus, et aucun nouveau port.

Ajoutez un service `adminer` au fichier de `app1`, avec l'image `adminer:5.4.2`, la variable `ADMINER_DEFAULT_SERVER: mysql`, et les deux réseaux : `app1_net` pour joindre la base, `public_net` pour le proxy. Donnez-lui les six labels vus pour `app1`, avec le préfixe `/adminer`, le port 8080 et un router et un middleware à son nom.

Ouvrez `http://localhost:28387/adminer/`, avec la barre oblique finale, et connectez-vous : serveur `mysql`, utilisateur `app1`, mot de passe `app1-dev`, base `app1db`.

⚠️ Sur un vrai serveur, Adminer ne reste pas ouvert à tous sans protection. Un middleware `basicauth` de Traefik, ou mieux, un accès réservé à un réseau d'administration, s'impose.

> 📖 [L'image Adminer](https://hub.docker.com/_/adminer)

## Router par nom de site

On peut aussi choisir l'application d'après le **nom de site** demandé (le nom d'hôte), et non le chemin. La règle devient `` Host(`app1.example.test`) ``, et le préfixe n'a plus de raison d'être.

Ajoutez à `app1` un second router, nommé `app1-host`, avec ce nom de site. Aucun DNS n'est nécessaire pour tester, car `-H` fixe l'en-tête `Host` de la demande :

```bash
curl -H 'Host: app1.example.test' http://localhost:28387/about
```

Vous devez lire `chemin reçu /about`. Avec un autre nom de site, cette même adresse répond `404`.

Pour un vrai déploiement, il faut un nom DNS par application.

> 📖 [Les règles de routage de Traefik](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/rules-and-priority/)

## Tout lancer d'un coup avec include

Vous lancez pour l'instant trois projets, un par dossier. Plutôt que d'écrire un script, sachez que Compose sait charger plusieurs fichiers depuis un fichier parent, avec la clé `include`.

Créez `~/layers-l8/web/compose.yaml` :

```yaml
name: layers-l8-web
include:
  - app1/compose.yaml
  - app2/compose.yaml
  - traefik/compose.yaml
```

Arrêtez d'abord les trois projets, chacun depuis son dossier, avec `docker compose down`, car ce fichier crée un seul projet, `layers-l8-web`, qui les remplace. Lancez-le ensuite depuis `~/layers-l8/web`, avec `docker compose up -d`.

⚖️ Le nom du projet entre dans le nom du volume : la base repart donc d'un volume neuf, `layers-l8-web_db_data`, et ne retrouve pas ses anciennes données. Vous gagnez une commande unique, mais vous perdez la possibilité de mettre à jour une application sans passer par le fichier parent, ce qui est un vrai choix d'organisation.

> 📖 [`include` dans Compose](https://docs.docker.com/compose/how-tos/multiple-compose-files/include/)

# Le nettoyage

## Supprimer ce que le lab a créé

Supprimez tout ce que ce lab a créé : les conteneurs, y compris ceux des bonus, les volumes, l'image construite, le réseau public et le dossier `~/layers-l8/web`.

Vous écrivez vous-même ces commandes, à partir de ces indications. L'ordre compte : les projets partent d'abord, chacun depuis son dossier, car Docker refuse de supprimer un réseau encore utilisé. `docker compose down -v` supprime aussi les volumes du projet, et donc les données de MySQL. L'image `layers-l8-web-app1` porte un nom choisi par vous, et `docker rmi` la supprime à part. `docker network rm` supprime le réseau public. Enfin, `cd ~` vous fait sortir du dossier avant de l'effacer.

Les images téléchargées, comme `mysql:8.4`, restent sur votre machine, ce qui vous évitera de les télécharger à nouveau.

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep '^layers-l8-web')" ]; then
  echo "Il reste des conteneurs : $(docker ps -a --format '{{.Names}}' | grep '^layers-l8-web' | tr '\n' ' ')"
  exit 1
fi
if docker network inspect layers-l8-public >/dev/null 2>&1; then
  echo "Le réseau layers-l8-public existe encore. Lancez docker network rm layers-l8-public, une fois les projets arrêtés."
  exit 1
fi
if [ -n "$(docker network ls --format '{{.Name}}' | grep '^layers-l8-web')" ]; then
  echo "Il reste des réseaux de projet : $(docker network ls --format '{{.Name}}' | grep '^layers-l8-web' | tr '\n' ' ')"
  exit 1
fi
if [ -n "$(docker volume ls --format '{{.Name}}' | grep '^layers-l8-web')" ]; then
  echo "Il reste des volumes : $(docker volume ls --format '{{.Name}}' | grep '^layers-l8-web' | tr '\n' ' ')"
  exit 1
fi
if docker image inspect layers-l8-web-app1 >/dev/null 2>&1; then
  echo "L'image layers-l8-web-app1 existe encore. Supprimez-la avec docker rmi."
  exit 1
fi
if [ -e "$HOME/layers-l8/web" ]; then
  echo "Le dossier ~/layers-l8/web existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
Si vous avez fait le bonus `include`, lancez d'abord `docker compose down -v` depuis `~/layers-l8/web`. Viennent ensuite les commandes du cas pratique :

```bash
cd ~/layers-l8/web/app1 && docker compose down -v
cd ~/layers-l8/web/app2 && docker compose down -v
cd ~/layers-l8/web/nginx && docker compose down -v
cd ~/layers-l8/web/traefik && docker compose down -v
docker network rm layers-l8-public
docker rmi layers-l8-web-app1
cd ~ && rm -rf ~/layers-l8/web
```
````

## Récap

- Un reverse proxy est la seule porte d'entrée : il publie un port, et les applications n'en publient aucun, ce qui se vérifie avec `docker port`.
- Chaque application garde un réseau privé, et rejoint un réseau public partagé, créé à part et déclaré `external: true` : il survit ainsi au changement de proxy.
- `depends_on` avec `service_healthy` et un `healthcheck` font attendre une base vraiment prête, et non un conteneur simplement démarré.
- Derrière un préfixe, l'application attend son chemin d'origine : nginx le retire par la barre oblique finale de `proxy_pass`, et Traefik par le middleware `stripprefix`.
- Un conteneur sur plusieurs réseaux doit dire à Traefik lequel utiliser, avec `traefik.docker.network`, sous peine de `504` aléatoires.
- nginx lit un fichier, Traefik lit Docker : le premier demande moins de droits, le second encaisse mieux les applications qui vont et viennent.

Tous les fichiers de ce lab se trouvent dans le dossier [`solution/`](../solution/) de ce contenu.
