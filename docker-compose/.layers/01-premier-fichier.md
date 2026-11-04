---
title: "Un premier fichier"
description: "Pourquoi Compose, le format YAML, et les quatre commandes de base"
---

Jusqu'ici, faire tourner une application de deux conteneurs demandait plusieurs commandes : créer un réseau, créer un volume, puis un long `docker run` par conteneur. Il fallait les retenir, les retaper dans le bon ordre, et les transmettre à vos collègues. **Docker Compose** remplace tout cela par un fichier qui décrit ce que vous voulez obtenir, et une commande qui le fait exister.

## Vérifier que Compose répond

Compose est une extension de la commande `docker`. Commencez par lui demander sa version :

```exec
docker compose version
```

Vous devez lire un numéro de version, `2.x` ou plus. Le message `'compose' is not a docker command` veut dire que l'extension manque : sous Linux, installez le paquet `docker-compose-plugin`.

```verify
if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose ne répond pas. Installez l'extension Compose, puis réessayez."
  exit 1
fi
echo "Compose répond."
```

## Le format du fichier

Le fichier s'écrit en **YAML**, un format texte fait de clés et de valeurs. Trois règles suffisent pour le lire :

| Écriture | Ce qu'elle veut dire |
|---|---|
| `clé: valeur` | une clé et sa valeur, avec une espace après les deux-points |
| le décalage vers la droite | ce qui est décalé appartient à la clé du dessus ; on décale de deux espaces, jamais avec une tabulation |
| `- élément` | un élément d'une liste |

Voici le fichier que vous allez créer. Il décrit un seul serveur web, nginx :

```yaml
name: layers-l7-counter
services:
  web:
    image: nginx:1.30-alpine
    ports:
      - "28370:80"
```

Ce fichier dit la même chose que la commande `docker run -d --name ... -p 28370:80 nginx:1.30-alpine`, avec des mots :

| Clé | Rôle |
|---|---|
| `name` | le nom du **projet**, l'ensemble de ce que ce fichier décrit ; Compose s'en sert pour nommer ce qu'il crée |
| `services` | la liste des **services**, un service étant un conteneur décrit par son rôle dans l'application |
| `web` | le nom que vous donnez à ce service, à votre choix |
| `image` | l'image à utiliser |
| `ports` | les ports à publier, sous la forme `port-machine:port-conteneur` ; les guillemets évitent que YAML lise ces chiffres autrement que comme du texte |

## Créer le fichier

Compose cherche par défaut un fichier nommé `compose.yaml` dans le dossier courant. Créez son dossier et son contenu. `cat > fichier <<'EOF'` écrit dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` ; vous pouvez aussi le créer avec votre éditeur :

```exec
mkdir -p ~/layers-l7/counter
cat > ~/layers-l7/counter/compose.yaml <<'EOF'
name: layers-l7-counter
services:
  web:
    image: nginx:1.30-alpine
    ports:
      - "28370:80"
EOF
```

Avant de démarrer quoi que ce soit, demandez à Compose de relire le fichier. `docker compose config` affiche ce qu'il a compris, avec toutes les valeurs par défaut, ou une erreur s'il y en a une. Dans tout ce cours, chaque commande commence par `cd ~/layers-l7/counter &&`, ce qui vous permet de la relancer depuis n'importe où :

```exec
cd ~/layers-l7/counter && docker compose config
```

Si le décalage est faux, Compose le dit à cet endroit, avec un message comme `did not find expected key`. C'est le premier réflexe à prendre : relire avant de lancer.

```verify
if ! (cd ~/layers-l7/counter 2>/dev/null && docker compose config -q) 2>/dev/null; then
  echo "Compose ne lit pas ~/layers-l7/counter/compose.yaml. Lancez la commande qui le crée, puis docker compose config pour lire l'erreur."
  exit 1
fi
echo "Compose lit votre fichier."
```

## Démarrer

`docker compose up` fait exister ce que le fichier décrit, et `-d` le laisse tourner en arrière-plan, comme pour `docker run` :

```exec
cd ~/layers-l7/counter && docker compose up -d
```

Lisez les lignes qui s'affichent : Compose a créé un réseau, `layers-l7-counter_default`, puis un conteneur, `layers-l7-counter-web-1`. Le nom du conteneur suit la forme `<projet>-<service>-<numéro>`. Vous n'avez écrit aucun de ces deux noms : ils viennent du fichier.

Demandez la page, puis voyez ce qui tourne. Pour `curl`, `-s` masque la progression, et `--retry 10 --retry-delay 1 --retry-all-errors` réessaie jusqu'à 10 fois, à 1 seconde d'intervalle, le temps que le serveur démarre. `docker compose ps` ne liste que les conteneurs de ce projet, contrairement à `docker ps` :

```exec
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370 | grep '<h1>'
cd ~/layers-l7/counter && docker compose ps
```

Vous devez lire `<h1>Welcome to nginx!</h1>`, puis une ligne par service.

```verify
if [ "$(docker inspect layers-l7-counter-web-1 --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l7-counter-web-1 ne tourne pas. Lancez docker compose up -d dans ~/layers-l7/counter."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28370 | grep -q 'Welcome to nginx'; then
  echo "La page ne répond pas sur le port 28370. Regardez la colonne PORTS de docker compose ps."
  exit 1
fi
echo "nginx tourne, décrit par votre fichier."
```

## Lire les logs, puis tout arrêter

`docker compose logs` affiche la sortie des conteneurs du projet, et préfixe chaque ligne par le service qui l'a écrite. `--tail 2` ne garde que les 2 dernières lignes de chacun :

```exec
cd ~/layers-l7/counter && docker compose logs --tail 2
```

`docker compose down` fait l'inverse de `up` : il arrête les conteneurs, les supprime, et supprime le réseau du projet.

```exec
cd ~/layers-l7/counter && docker compose down
```

Le fichier, lui, reste. C'est toute l'idée : l'application n'existe plus sur la machine, mais sa description est intacte, et un `up` la refait à l'identique.

```verify
if docker container inspect layers-l7-counter-web-1 >/dev/null 2>&1; then
  echo "Le conteneur existe encore. Lancez docker compose down."
  exit 1
fi
if docker network inspect layers-l7-counter_default >/dev/null 2>&1; then
  echo "Le réseau existe encore. Lancez docker compose down."
  exit 1
fi
if [ ! -f ~/layers-l7/counter/compose.yaml ]; then
  echo "Le fichier ~/layers-l7/counter/compose.yaml a disparu : reprenez la section qui le crée."
  exit 1
fi
echo "Conteneur et réseau supprimés, le fichier est toujours là."
```

> 📖 [Présentation de Compose](https://docs.docker.com/compose/) · [`docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/) · [`docker compose down`](https://docs.docker.com/reference/cli/docker/compose/down/) · [`docker compose config`](https://docs.docker.com/reference/cli/docker/compose/config/)

## Questions

```quiz
title: "Un premier fichier"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Dans un fichier Compose, qu'est-ce qu'un service ?"
    answers:
      - "Un programme installé sur votre machine"
      - "Un conteneur décrit par son rôle dans l'application, avec son image et ses réglages"
      - "Un synonyme de projet"
    correct: 2
    explanation: "Le projet est l'ensemble du fichier. Un service en est une partie : ici `web`, un conteneur nginx."
  - prompt: "Compose refuse un fichier où `image:` est écrite au même décalage que le nom du service `web:`, avec le message `services.image must be a mapping`. Pourquoi ?"
    answers:
      - "Il manque la clé `name`"
      - "`image` n'est pas décalée sous `web` : elle est lue comme un autre service"
      - "Le tag `1.30-alpine` n'existe pas"
    correct: 2
    explanation: "En YAML, le décalage dit ce qui appartient à quoi. Sans décalage sous `web`, `image` devient un service de plus, et sa valeur n'a pas la forme d'un service."
  - prompt: "Après `docker compose down`, que reste-t-il ?"
    answers:
      - "Rien, pas même le fichier"
      - "Le fichier compose.yaml et les images téléchargées"
      - "Le réseau du projet"
    correct: 2
    explanation: "`down` supprime les conteneurs et le réseau du projet. Il ne touche ni à votre fichier, ni aux images."
```
