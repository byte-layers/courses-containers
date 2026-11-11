---
title: "Conteneuriser une application inconnue"
description: "Écrire seul le Dockerfile d'une application jamais vue, à partir de sa documentation : image, réglages, utilisateur, contexte de build."
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

On vous confie une petite application jamais vue, avec sa documentation : à vous d'écrire son Dockerfile, de la faire répondre, de lui retirer les droits d'administrateur et d'écarter ses fichiers sensibles. Il n'y a **aucun fichier à recopier** : chaque tâche donne des critères qu'un bouton vérifie sur l'état réel de Docker. Toute écriture qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

- **Niveau** : ce challenge suppose ce qu'enseignent le cours [Écrire le Dockerfile d'une application](https://byte-layers.com/fr/skills/docker-dockerfile) et le lab [Conteneuriser une application pas à pas](https://byte-layers.com/fr/labs/docker-containerize-app).
- **Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, un éditeur de texte, et les ports 28322 et 28323 libres. La vérification se sert du second pour un essai rapide.
- **Votre dossier de travail** : `~/byte-layers/docker/l2/quotes` est créé pour vous, avec l'application dedans. Programmer n'est pas nécessaire : la documentation dit tout ce qu'il faut.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l2-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche reprend le Dockerfile de la précédente.
- **Le tag reste le même** : reconstruisez toujours sous `layers-l2-quotes:1.0`, puis recréez le conteneur. ⚖️ C'est un raccourci, pour que la vérification sache où regarder. Dans un vrai projet, chaque version aurait son propre tag.

# Tâche 1 : une image qui démarre

## Écrire le Dockerfile et construire l'image

```setup
mkdir -p ~/byte-layers/docker/l2/quotes/quotes ~/byte-layers/docker/l2/quotes/data ~/byte-layers/docker/l2/quotes/tests
cat > ~/byte-layers/docker/l2/quotes/README.md <<'EOF'
# quotes

Un service qui renvoie une citation au hasard.

- Il demande Python 3.13.
- Ses dépendances sont dans requirements.txt, à installer avec pip.
- Il se lance depuis la racine du projet avec : python -m quotes
- Il lit ses citations dans data/quotes.txt, relatif au dossier courant.
- Il note chaque requête dans var/hits.log, relatif au dossier courant, et crée var au démarrage si besoin.

## Réglages

Le service se règle par deux variables d'environnement.

| Variable | Rôle | Par défaut |
|---|---|---|
| HOST | l'adresse sur laquelle il écoute | 127.0.0.1 |
| PORT | le port sur lequel il écoute | 8080 |

## Adresses

- GET /        une citation au hasard
- GET /health  répond ok
- GET /hits    le nombre de requêtes notées dans var/hits.log
EOF
echo 'bottle==0.13.*' > ~/byte-layers/docker/l2/quotes/requirements.txt
touch ~/byte-layers/docker/l2/quotes/quotes/__init__.py
cat > ~/byte-layers/docker/l2/quotes/quotes/__main__.py <<'EOF'
import os
import pathlib
import random

from bottle import route, run

HITS = pathlib.Path("var/hits.log")
QUOTES = pathlib.Path("data/quotes.txt").read_text(encoding="utf-8").splitlines()
HITS.parent.mkdir(exist_ok=True)


@route("/")
def home():
    with HITS.open("a") as log:
        log.write("hit\n")
    return random.choice(QUOTES) + "\n"


@route("/health")
def health():
    return "ok\n"


@route("/hits")
def hits():
    return str(len(HITS.read_text().splitlines()) if HITS.exists() else 0) + "\n"


run(host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "8080")))
EOF
cat > ~/byte-layers/docker/l2/quotes/data/quotes.txt <<'EOF'
Une image ne change jamais.
Un conteneur est jetable.
Ce qui marche sur mon poste doit marcher ailleurs.
EOF
echo 'API_KEY=valeur-fictive-du-poste-de-dev' > ~/byte-layers/docker/l2/quotes/.env.local
echo 'def test_rien(): pass' > ~/byte-layers/docker/l2/quotes/tests/test_quotes.py
```

Lisez `~/byte-layers/docker/l2/quotes/README.md`, par exemple avec `cat`. Créez ensuite le fichier `~/byte-layers/docker/l2/quotes/Dockerfile` avec votre éditeur, puis construisez l'image avec `docker build`.

**Critères :**

- une image s'appelle exactement `layers-l2-quotes:1.0` ;
- elle contient Python **3.13** et les dépendances de l'application ;
- elle documente le port d'écoute de l'application ;
- sans autre précision, un conteneur créé depuis elle lance le service, en forme exec ou non.

```hint
Regardez d'abord ce que le README demande : la version de Python donne l'image de base, requirements.txt donne la ligne d'installation, et « se lance avec » donne le `CMD`.
```

```hint
L'application lit `data/quotes.txt` relativement au dossier courant : il faut donc un `WORKDIR`, et tout le projet copié dedans.
```

```hint
Le module se lance avec trois mots, ce qui s'écrit en forme exec `["python", "-m", "quotes"]`.
```

```verify
I=layers-l2-quotes:1.0
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $I n'existe pas. Écrivez le Dockerfile dans ~/byte-layers/docker/l2/quotes, puis construisez-la sous ce nom."
  exit 1
fi
V=$(docker run --rm --entrypoint python "$I" --version 2>&1)
case "$V" in
  "Python 3.13"*) : ;;
  *) echo "ÉCHEC : l'image doit contenir Python 3.13, et voici ce que répond python --version : $V"; exit 1 ;;
esac
if ! docker run --rm --entrypoint python "$I" -c 'import bottle' 2>/dev/null; then
  echo "ÉCHEC : les dépendances de requirements.txt ne sont pas installées dans l'image."
  exit 1
fi
case "$(docker image inspect "$I" --format '{{json .Config.ExposedPorts}}')" in
  *'"8080/tcp"'*) : ;;
  *) echo "ÉCHEC : l'image ne documente pas le port d'écoute, 8080."; exit 1 ;;
esac
START="$(docker image inspect "$I" --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}')"
case "$START" in
  *quotes*) : ;;
  *) echo "ÉCHEC : la commande de démarrage de l'image ne lance pas le service : $START"; exit 1 ;;
esac
echo "RÉUSSI : $I contient Python 3.13 et ses dépendances, et sait démarrer le service."
```

````solution
```bash
cat > ~/byte-layers/docker/l2/quotes/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8080
CMD ["python", "-m", "quotes"]
EOF
docker build -t layers-l2-quotes:1.0 ~/byte-layers/docker/l2/quotes
```
````

# Tâche 2 : un service qui répond

## Lancer le conteneur et le faire répondre

Lancez le service en arrière-plan avec `docker run`, et faites en sorte qu'il réponde depuis votre machine. S'il ne répond pas, modifiez le Dockerfile avec votre éditeur, reconstruisez l'image et recréez le conteneur.

**Critères :**

- un conteneur s'appelle exactement `layers-l2-quotes` et vient de l'image `layers-l2-quotes:1.0` ;
- le port **28322** de la machine mène au port d'écoute du service ;
- `http://localhost:28322/health` répond `ok`, et la page d'accueil renvoie une citation ;
- **l'image porte le réglage nécessaire** : un conteneur lancé depuis elle, sans aucune option `-e`, répond aussi. La vérification en lance un sur le port 28323, puis le supprime.

```hint
Si le conteneur tourne mais que le port ne répond pas, lisez ses logs : sur quelle adresse le service écoute-t-il ? Relisez la section « Réglages » du README.
```

```hint
Dans un conteneur, `127.0.0.1` désigne le conteneur lui-même. Le service doit écouter sur toutes ses adresses.
```

```hint
`ENV HOST=0.0.0.0` dans le Dockerfile donne ce réglage à tous les conteneurs. Reconstruisez, supprimez l'ancien conteneur, puis recréez-le.
```

```verify
I=layers-l2-quotes:1.0
C=layers-l2-quotes
P=layers-l2-quotes-essai
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $I n'existe pas. Faites d'abord la tâche 1."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Lisez : docker logs $C"
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Image}}')" != "$(docker image inspect "$I" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : $C ne vient pas de la dernière version de $I. Supprimez-le et recréez-le."
  exit 1
fi
HEALTH=$(curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28322/health)
if [ "$HEALTH" != "ok" ]; then
  echo "ÉCHEC : http://localhost:28322/health ne répond pas ok. Vérifiez le port publié et l'adresse d'écoute du service."
  echo "  Logs de $C : $(docker logs "$C" 2>&1 | tail -2 | tr '\n' ' ')"
  exit 1
fi
if ! grep -qxF "$(curl -s --max-time 5 http://localhost:28322/)" "$HOME/byte-layers/docker/l2/quotes/data/quotes.txt"; then
  echo "ÉCHEC : la page d'accueil de http://localhost:28322/ ne renvoie pas une citation du fichier data/quotes.txt."
  exit 1
fi
docker rm -f "$P" >/dev/null 2>&1
docker run -d --name "$P" -p 28323:8080 "$I" >/dev/null 2>&1
ESSAI=$(curl -s --max-time 5 --retry 4 --retry-delay 1 --retry-all-errors http://localhost:28323/health)
docker rm -f "$P" >/dev/null 2>&1
if [ "$ESSAI" != "ok" ]; then
  echo "ÉCHEC : $C répond, mais un conteneur lancé depuis l'image sans option -e ne répond pas."
  echo "  Le réglage doit être dans l'image, et non dans votre commande docker run."
  exit 1
fi
echo "RÉUSSI : le service répond sur le port 28322, et l'image porte son réglage."
```

````solution
```bash
cat > ~/byte-layers/docker/l2/quotes/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
ENV HOST=0.0.0.0
EXPOSE 8080
CMD ["python", "-m", "quotes"]
EOF
docker build -t layers-l2-quotes:1.0 ~/byte-layers/docker/l2/quotes
docker rm -f layers-l2-quotes
docker run -d --name layers-l2-quotes -p 28322:8080 layers-l2-quotes:1.0
```
````

# Tâche 3 : sans les droits d'administrateur

## Changer d'utilisateur dans le Dockerfile

Faites tourner le service avec un utilisateur ordinaire, sans lui faire perdre sa capacité à écrire `var/hits.log`. Modifiez le Dockerfile avec votre éditeur, reconstruisez l'image et recréez le conteneur.

**Critères :**

- le processus du conteneur `layers-l2-quotes` ne tourne pas en `root` ;
- le service écrit toujours : après une visite de la page d'accueil, `http://localhost:28322/hits` renvoie un nombre supérieur à 0.

```hint
Sur Alpine, `adduser -D <nom>` crée un utilisateur sans mot de passe. `USER <nom>` s'en sert pour la suite et au démarrage.
```

```hint
Le service crée `var/` dans le dossier courant. Si ce dossier appartient à `root`, il tombe sur `Permission denied` au démarrage : lisez ses logs.
```

```hint
Pendant le build, encore en `root`, donnez le dossier de travail à votre utilisateur avec `chown`, avant la ligne `USER`.
```

```verify
C=layers-l2-quotes
I=layers-l2-quotes:1.0
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C. Faites d'abord la tâche 2."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Image}}')" != "$(docker image inspect "$I" --format '{{.Id}}' 2>/dev/null)" ]; then
  echo "ÉCHEC : $C ne vient pas de la dernière version de $I. Supprimez-le et recréez-le."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Ses derniers logs : $(docker logs "$C" 2>&1 | tail -2 | tr '\n' ' ')"
  exit 1
fi
if [ "$(docker exec "$C" id -u)" = "0" ]; then
  echo "ÉCHEC : le service tourne encore en root."
  exit 1
fi
curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors -o /dev/null http://localhost:28322/
HITS=$(curl -s --max-time 5 http://localhost:28322/hits)
case "$HITS" in
  ""|0|*[!0-9]*) echo "ÉCHEC : le service ne note pas les requêtes : /hits répond « $HITS ». Peut-il écrire dans son dossier var ?"; exit 1 ;;
esac
echo "RÉUSSI : le service tourne avec l'identifiant d'utilisateur $(docker exec "$C" id -u), et il écrit son journal."
```

````solution
```bash
cat > ~/byte-layers/docker/l2/quotes/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
RUN adduser -D app && chown app /app
USER app
ENV HOST=0.0.0.0
EXPOSE 8080
CMD ["python", "-m", "quotes"]
EOF
docker build -t layers-l2-quotes:1.0 ~/byte-layers/docker/l2/quotes
docker rm -f layers-l2-quotes
docker run -d --name layers-l2-quotes -p 28322:8080 layers-l2-quotes:1.0
```
````

# Tâche 4 : un contexte propre

## Écarter les fichiers sensibles du contexte de build

Le dossier du projet contient un fichier de secrets de développement et des tests. Ils n'ont rien à faire dans une image de production. Créez à la racine du projet, avec votre éditeur, le fichier qui liste ce que Docker doit laisser de côté, reconstruisez l'image et recréez le conteneur.

**Critères :**

- `.env.local` et le dossier `tests` **ne peuvent plus entrer** dans le contexte de build ; la vérification construit un essai à partir de votre dossier pour le constater ;
- ils ne sont pas dans l'image `layers-l2-quotes:1.0`, ni dans le conteneur `layers-l2-quotes`, reconstruits après ce changement ;
- le service répond toujours sur le port 28322.

```hint
Un fichier placé à la racine du contexte liste ce que Docker doit laisser de côté, un motif par ligne.
```

```hint
Une fois `.dockerignore` écrit, reconstruisez l'image, supprimez le conteneur et recréez-le : l'ancienne image garde ses fichiers.
```

```verify
C=layers-l2-quotes
I=layers-l2-quotes:1.0
DIR="$HOME/byte-layers/docker/l2/quotes"
OUT=$(mktemp -d)
if ! printf 'FROM scratch\nCOPY . /\n' | docker build -q -f - -o "type=local,dest=$OUT" "$DIR" >/dev/null 2>&1; then
  echo "ÉCHEC : l'essai de build a échoué sur le dossier $DIR. Le .dockerignore a-t-il exclu tout le projet ?"
  rm -rf "$OUT"
  exit 1
fi
bad=""
[ -e "$OUT/.env.local" ] && bad="$bad .env.local"
[ -e "$OUT/tests" ] && bad="$bad tests"
missing=""
[ -f "$OUT/data/quotes.txt" ] || missing="$missing data/quotes.txt"
[ -d "$OUT/quotes" ] || missing="$missing quotes"
rm -rf "$OUT"
if [ -n "$bad" ]; then
  echo "ÉCHEC : ces éléments entrent encore dans le contexte de build :$bad"
  exit 1
fi
if [ -n "$missing" ]; then
  echo "ÉCHEC : le .dockerignore en exclut trop, il manque :$missing"
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Image}}' 2>/dev/null)" != "$(docker image inspect "$I" --format '{{.Id}}' 2>/dev/null)" ]; then
  echo "ÉCHEC : $C ne vient pas de la dernière version de $I. Reconstruisez, supprimez-le et recréez-le."
  exit 1
fi
if docker run --rm --entrypoint sh "$I" -c 'test -e .env.local || test -e tests'; then
  echo "ÉCHEC : l'image $I contient encore .env.local ou tests. Reconstruisez-la."
  exit 1
fi
if [ "$(curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28322/health)" != "ok" ]; then
  echo "ÉCHEC : le service ne répond plus sur le port 28322."
  exit 1
fi
echo "RÉUSSI : le contexte est propre, et le service répond toujours."
```

````solution
```bash
cat > ~/byte-layers/docker/l2/quotes/.dockerignore <<'EOF'
.env.local
tests
Dockerfile
.dockerignore
README.md
EOF
docker build -t layers-l2-quotes:1.0 ~/byte-layers/docker/l2/quotes
docker rm -f layers-l2-quotes
docker run -d --name layers-l2-quotes -p 28322:8080 layers-l2-quotes:1.0
```
````

# Tâche 5 : ne rien laisser derrière soi

## Retirer le conteneur, l'image et le dossier

Supprimez tout ce que ce challenge a créé, avec `docker rm`, `docker image rm` et `rm -rf`.

**Critères :** plus de conteneur `layers-l2-quotes`, plus d'image `layers-l2-quotes:1.0`, plus de dossier `~/byte-layers/docker/l2/quotes`. Vos autres images et vos autres conteneurs ne sont pas concernés. Comme vous avez reconstruit plusieurs fois sous le même tag, `docker images` peut montrer d'anciennes versions restées sans nom, marquées `<none>`. La vérification ne les regarde pas : elles sont sans danger, et `docker image rm <identifiant>` supprime celles que vous reconnaissez.

```hint
Le conteneur d'abord, l'image ensuite, le dossier enfin : `docker rm -f`, `docker image rm`, `rm -rf`.
```

```verify
if docker container inspect layers-l2-quotes >/dev/null 2>&1 || docker container inspect layers-l2-quotes-essai >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur layers-l2-quotes existe encore."
  exit 1
fi
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^layers-l2-quotes:')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/byte-layers/docker/l2/quotes" ]; then
  echo "ÉCHEC : le dossier ~/byte-layers/docker/l2/quotes existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez conteneuriser une application inconnue."
```

````solution
```bash
docker rm -f layers-l2-quotes
docker image rm layers-l2-quotes:1.0
rm -rf ~/byte-layers/docker/l2/quotes
```
````
