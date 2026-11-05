---
title: "Prouver que les données survivent"
description: "Garder les données d'une base au-delà de son conteneur, servir un dossier de votre machine, puis sauvegarder et restaurer, sans guide."
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

Ce challenge prouve que vous savez garder des données au-delà d'un conteneur, donner accès à un dossier de votre machine, et sauvegarder puis restaurer un volume. Il n'y a **aucune commande à recopier**, en dehors des outils de PostgreSQL donnés à la tâche 2 : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseignent les cours « Le conteneur est jetable » et « Garder ses données : volumes et bind mounts ». Le lab « Persister une base, développer en direct » est un bon entraînement.
- **Ce qu'il faut avoir** : Docker qui répond à `docker ps`, `curl`, `tar`, et le port 28365 libre.
- **Un dossier de travail** : `~/layers-l6` est créé pour vous, et la dernière tâche le supprime. La vérification y garde un fichier caché, `.pg-id`, qui lui sert à reconnaître votre conteneur. Sur un poste hébergé, seuls les dossiers sous `/home/student` sont visibles du moteur Docker, ce qui est bien le cas de celui-ci.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l6-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche s'appuie sur la précédente, sauf la tâche 4.

# Tâche 1 : une base sur un volume

## Ce qu'il faut faire

```setup
mkdir -p ~/layers-l6
```

Lancez une base PostgreSQL dont les données vivent dans un volume nommé.

**Critères :**

- un volume s'appelle exactement `layers-l6-data` ;
- un conteneur s'appelle exactement `layers-l6-pg`, il tourne, et il vient d'une image `postgres`, `postgres:17-alpine` convient ;
- le volume est branché **sur le dossier où PostgreSQL écrit ses données**, ce qui est à vous de trouver.

L'image démarre à condition de recevoir la variable `POSTGRES_PASSWORD`, avec la valeur de votre choix.

```hint
Une image qui attend un volume le déclare, et sa fiche le montre : après l'avoir téléchargée avec `docker pull`, cherchez dans `docker image inspect`, au champ `.Config.Volumes`.
```

```hint
Si le volume n'est pas branché au bon endroit, PostgreSQL écrit ailleurs, dans un volume anonyme, et la tâche 3 échouerait.
```

```verify
C=layers-l6-pg
if ! docker volume inspect layers-l6-data >/dev/null 2>&1; then
  echo "ÉCHEC : le volume layers-l6-data n'existe pas."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Lisez docker logs $C. Lui avez-vous donné POSTGRES_PASSWORD ?"
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  *postgres*) : ;;
  *) echo "ÉCHEC : $C ne vient pas d'une image postgres."; exit 1 ;;
esac
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Type}} {{.Name}}{{end}}{{end}}')
if [ "$MOUNT" != "volume layers-l6-data" ]; then
  echo "ÉCHEC : le dossier de données de PostgreSQL n'est pas branché sur layers-l6-data (trouvé : ${MOUNT:-rien})."
  echo "  Trouvez ce dossier dans la fiche de l'image, supprimez le conteneur et recréez-le."
  exit 1
fi
mkdir -p "$HOME/layers-l6"
[ -f "$HOME/layers-l6/.pg-id" ] || docker container inspect "$C" --format '{{.Id}}' > "$HOME/layers-l6/.pg-id"
echo "RÉUSSI : PostgreSQL écrit ses données dans layers-l6-data."
```

````solution
```bash
docker volume create layers-l6-data
docker run -d --name layers-l6-pg -e POSTGRES_PASSWORD=secret -v layers-l6-data:/var/lib/postgresql/data postgres:17-alpine
```
````

# Tâche 2 : écrire une preuve

## Ce qu'il faut faire

Écrivez une donnée reconnaissable dans la base.

**Critères :**

- la table `preuve` existe dans la base `postgres` ;
- elle contient la ligne `survivant`.

PostgreSQL n'est pas prêt dès le lancement du conteneur. Pour savoir s'il répond, utilisez `docker exec layers-l6-pg pg_isready -U postgres -h 127.0.0.1`. Quand il répond `accepting connections`, créez la donnée avec le client `psql` de l'image, en lui donnant cette instruction en SQL, le langage des bases de données. Elle crée une table, puis y ajoute une ligne :

```sql
CREATE TABLE preuve (texte text); INSERT INTO preuve VALUES ('survivant');
```

```hint
`psql -U postgres -c "..."` exécute une instruction SQL. Il doit tourner dans le conteneur, ce que permet `docker exec`.
```

```verify
if ! docker exec layers-l6-pg psql -U postgres -tAc 'SELECT texte FROM preuve' 2>/dev/null | grep -q survivant; then
  echo "ÉCHEC : la table preuve ne contient pas la ligne survivant, ou PostgreSQL n'est pas encore prêt."
  echo "  Testez avec : docker exec layers-l6-pg pg_isready -U postgres -h 127.0.0.1"
  exit 1
fi
echo "RÉUSSI : la ligne survivant est dans la table preuve."
```

````solution
```bash
until docker exec layers-l6-pg pg_isready -U postgres -h 127.0.0.1 -q; do sleep 1; done
docker exec layers-l6-pg psql -U postgres -c "CREATE TABLE preuve (texte text); INSERT INTO preuve VALUES ('survivant');"
```
````

# Tâche 3 : détruire le conteneur

## Ce qu'il faut faire

Prouvez que la donnée ne dépend pas de ce conteneur : remplacez-le par un conteneur neuf, sur le même volume.

**Critères :**

- un conteneur s'appelle toujours `layers-l6-pg`, et il tourne ;
- ce **n'est plus le même** qu'à la tâche 1 : un simple redémarrage ne convient pas ;
- il est branché sur `layers-l6-data` ;
- la ligne `survivant` s'y lit toujours, sans l'avoir récrite.

```hint
Une option de `docker rm` force la suppression d'un conteneur qui tourne. Le volume nommé n'est pas concerné.
```

```hint
Ce nouveau conteneur met quelques secondes à répondre : `pg_isready` vous le dit.
```

```verify
C=layers-l6-pg
ID_REF=$(cat "$HOME/layers-l6/.pg-id" 2>/dev/null)
if [ -z "$ID_REF" ]; then
  echo "ÉCHEC : la tâche 1 n'a pas été vérifiée. Vérifiez-la d'abord : elle note l'identifiant du conteneur."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C. Recréez-le sur le même volume."
  exit 1
fi
if [ "$ID_REF" = "$(docker container inspect "$C" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : $C est toujours le conteneur de la tâche 1. Un redémarrage ne prouve rien : supprimez-le et recréez-le."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas."
  exit 1
fi
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')
if [ "$MOUNT" != "layers-l6-data" ]; then
  echo "ÉCHEC : le nouveau $C n'est pas branché sur layers-l6-data (trouvé : ${MOUNT:-rien})."
  exit 1
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec "$C" pg_isready -U postgres -h 127.0.0.1 -q 2>/dev/null && break
  sleep 2
done
if ! docker exec "$C" psql -U postgres -tAc 'SELECT texte FROM preuve' 2>/dev/null | grep -q survivant; then
  echo "ÉCHEC : la ligne survivant ne se lit pas dans le nouveau $C."
  exit 1
fi
echo "RÉUSSI : le conteneur est neuf, et la donnée a survécu."
```

````solution
```bash
docker rm -f layers-l6-pg
docker run -d --name layers-l6-pg -e POSTGRES_PASSWORD=secret -v layers-l6-data:/var/lib/postgresql/data postgres:17-alpine
until docker exec layers-l6-pg pg_isready -U postgres -h 127.0.0.1 -q; do sleep 1; done
```
````

# Tâche 4 : servir un dossier de votre machine

## Ce qu'il faut faire

Faites servir par nginx une page qui reste sur votre machine.

**Critères :**

- le fichier `~/layers-l6/site/index.html` contient le mot `layers-l6-ok` ;
- un conteneur s'appelle exactement `layers-l6-web`, il tourne, et il vient d'une image `nginx` ;
- ce dossier `site` est branché par un **bind mount**, en **lecture seule**, sur `/usr/share/nginx/html` ;
- le port **28365** de l'hôte mène à son port 80, et `curl http://localhost:28365` affiche votre page.

```hint
`-v` et `--mount type=bind` conviennent tous les deux. Le chemin de votre machine doit être absolu : `$HOME` vous y aidera.
```

```verify
C=layers-l6-web
if ! grep -q layers-l6-ok "$HOME/layers-l6/site/index.html" 2>/dev/null; then
  echo "ÉCHEC : ~/layers-l6/site/index.html n'existe pas ou ne contient pas layers-l6-ok."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "ÉCHEC : le conteneur $C ne tourne pas."
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  *nginx*) : ;;
  *) echo "ÉCHEC : $C ne vient pas d'une image nginx."; exit 1 ;;
esac
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/usr/share/nginx/html"}}{{.Type}} {{.RW}} {{.Source}}{{end}}{{end}}')
case "$MOUNT" in
  "bind false "*layers-l6/site) : ;;
  *) echo "ÉCHEC : /usr/share/nginx/html n'est pas un bind mount en lecture seule de ~/layers-l6/site (trouvé : ${MOUNT:-rien})."
     echo "  Un montage se fixe à la création : supprimez $C et recréez-le."
     exit 1 ;;
esac
if ! docker port "$C" 80 2>/dev/null | grep -q ':28365$'; then
  echo "ÉCHEC : le port 28365 de l'hôte ne mène pas au port 80 de $C."
  exit 1
fi
if ! curl -s --max-time 5 --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28365 | grep -q layers-l6-ok; then
  echo "ÉCHEC : http://localhost:28365 n'affiche pas votre page."
  exit 1
fi
echo "RÉUSSI : nginx sert votre dossier, en lecture seule."
```

````solution
```bash
mkdir -p ~/layers-l6/site
echo '<h1>layers-l6-ok</h1>' > ~/layers-l6/site/index.html
docker run -d --name layers-l6-web -p 28365:80 -v "$HOME/layers-l6/site:/usr/share/nginx/html:ro" nginx:1.30-alpine
```
````

# Tâche 5 : sauvegarder le volume

## Ce qu'il faut faire

Sauvegardez le contenu du volume dans une archive sur votre machine.

**Critères :**

- le fichier `~/layers-l6/sauvegarde.tar.gz` existe ;
- c'est une archive `tar` compressée, qui contient directement les fichiers du volume, dont `PG_VERSION`.

Arrêtez la base avant d'archiver, pour que ses fichiers soient cohérents. Relancez-la ensuite. La vérification ne peut pas savoir que vous l'avez arrêtée, mais elle regarde que la base tourne de nouveau.

```hint
Un conteneur temporaire doit voir le volume et un dossier de votre machine. Une image comme `alpine:3.22` contient `tar`.
```

```hint
`tar czf <archive> -C <dossier> .` archive le contenu de ce dossier, sans le nom du dossier lui-même.
```

```verify
A="$HOME/layers-l6/sauvegarde.tar.gz"
if [ ! -f "$A" ]; then
  echo "ÉCHEC : le fichier ~/layers-l6/sauvegarde.tar.gz n'existe pas."
  exit 1
fi
if ! tar tzf "$A" >/dev/null 2>&1; then
  echo "ÉCHEC : ce fichier n'est pas une archive tar compressée."
  exit 1
fi
if ! tar tzf "$A" | grep -qE '^(\./)?PG_VERSION$'; then
  echo "ÉCHEC : l'archive ne contient pas PG_VERSION à sa racine."
  echo "  Archivez le contenu du volume, sans dossier intermédiaire : -C <dossier> ."
  exit 1
fi
if [ "$(docker container inspect layers-l6-pg --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "ÉCHEC : layers-l6-pg ne tourne pas. Relancez-le après l'archivage."
  exit 1
fi
echo "RÉUSSI : le contenu du volume est dans l'archive."
```

````solution
```bash
docker stop layers-l6-pg
docker run --rm -v layers-l6-data:/from:ro -v "$HOME/layers-l6:/to" alpine:3.22 tar czf /to/sauvegarde.tar.gz -C /from .
docker start layers-l6-pg
```
````

# Tâche 6 : restaurer ailleurs

## Ce qu'il faut faire

Une sauvegarde ne compte que si elle se restaure. Remontez-la dans un volume neuf, et faites-la lire par un second serveur.

**Critères :**

- un volume s'appelle exactement `layers-l6-restaure`, distinct de `layers-l6-data` ;
- un conteneur s'appelle exactement `layers-l6-pg2`, il tourne depuis une image `postgres`, avec ce volume sur le dossier de données ;
- la ligne `survivant` s'y lit, depuis ce second serveur.

```hint
Le chemin inverse de la tâche précédente : `tar xzf <archive> -C <dossier>` extrait l'archive dans ce dossier.
```

```hint
Le dossier de données contient déjà une base : PostgreSQL ne l'initialise pas à nouveau, et `POSTGRES_PASSWORD` n'est plus nécessaire.
```

```verify
C=layers-l6-pg2
if ! docker volume inspect layers-l6-restaure >/dev/null 2>&1; then
  echo "ÉCHEC : le volume layers-l6-restaure n'existe pas."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "ÉCHEC : le conteneur $C ne tourne pas."
  exit 1
fi
case "$(docker container inspect "$C" --format '{{.Config.Image}}')" in
  *postgres*) : ;;
  *) echo "ÉCHEC : $C ne vient pas d'une image postgres."; exit 1 ;;
esac
MOUNT=$(docker container inspect "$C" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')
if [ "$MOUNT" != "layers-l6-restaure" ]; then
  echo "ÉCHEC : le dossier de données de $C n'est pas branché sur layers-l6-restaure (trouvé : ${MOUNT:-rien})."
  exit 1
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec "$C" pg_isready -U postgres -h 127.0.0.1 -q 2>/dev/null && break
  sleep 2
done
if ! docker exec "$C" psql -U postgres -tAc 'SELECT texte FROM preuve' 2>/dev/null | grep -q survivant; then
  echo "ÉCHEC : la ligne survivant ne se lit pas dans $C. Avez-vous extrait l'archive dans le volume avant de lancer le serveur ?"
  exit 1
fi
echo "RÉUSSI : la sauvegarde est restaurée, et la donnée se lit sur un second serveur."
```

````solution
```bash
docker volume create layers-l6-restaure
docker run --rm -v "$HOME/layers-l6:/from:ro" -v layers-l6-restaure:/to alpine:3.22 tar xzf /from/sauvegarde.tar.gz -C /to
docker run -d --name layers-l6-pg2 -v layers-l6-restaure:/var/lib/postgresql/data postgres:17-alpine
until docker exec layers-l6-pg2 pg_isready -U postgres -h 127.0.0.1 -q; do sleep 1; done
```
````

# Tâche 7 : ne rien laisser derrière soi

## Ce qu'il faut faire

Supprimez tout ce que ce challenge a créé : les conteneurs `layers-l6-pg`, `layers-l6-pg2` et `layers-l6-web`, les volumes `layers-l6-data` et `layers-l6-restaure`, et le dossier `~/layers-l6`.

**Critères :** plus aucun de ces objets, plus de dossier. Vos autres conteneurs et volumes ne sont pas concernés.

```hint
Un volume utilisé ne se supprime pas : commencez par les conteneurs. Un volume nommé ne part jamais tout seul.
```

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l6-(pg|pg2|web)$')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
for V in layers-l6-data layers-l6-restaure; do
  if docker volume inspect "$V" >/dev/null 2>&1; then
    echo "ÉCHEC : le volume $V existe encore."
    exit 1
  fi
done
if [ -e "$HOME/layers-l6" ]; then
  echo "ÉCHEC : le dossier ~/layers-l6 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez prouver que vos données survivent."
```

````solution
```bash
docker rm -f layers-l6-pg layers-l6-pg2 layers-l6-web
docker volume rm layers-l6-data layers-l6-restaure
rm -rf ~/layers-l6
```
````
