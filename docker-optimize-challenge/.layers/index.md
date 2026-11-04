---
title: "Réduire et accélérer une image existante"
description: "Reprendre un Dockerfile lent et lourd, sans guide : le mesurer, le rendre rapide à reconstruire, en écarter ce qui ne sert à rien, et ne livrer que le résultat."
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

Ce challenge prouve que vous savez améliorer un Dockerfile qui fonctionne, mais qui est lourd et lent à reconstruire. Il n'y a **aucun fichier à recopier** : chaque tâche donne des critères, et un bouton vérifie l'état réel de Docker. Toute écriture qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseignent « Couches et copy-on-write », « Accélérer un build avec le cache » et « Réduire une image avec le multi-stage ».
- **Ce qu'il faut avoir** : Docker, `curl`, un éditeur de texte, et le port 28332 libre.
- **Votre dossier de travail** : `~/layers-l3/slow` est créé pour vous, avec un petit service web écrit en Go et son Dockerfile. Il écoute sur le port 8080. Ses dépendances sont décrites dans `go.mod` et `go.sum`, et `go mod download` les télécharge. Vous n'avez pas besoin de savoir programmer en Go.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l3-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche reprend le Dockerfile de la précédente, et la tâche 1 sert de point de comparaison.

# Tâche 1 : mesurer avant d'optimiser

```setup
mkdir -p ~/layers-l3/slow/docs
cat > ~/layers-l3/slow/go.mod <<'EOF'
module example.com/slow

go 1.24

require github.com/google/uuid v1.6.0
EOF
cat > ~/layers-l3/slow/go.sum <<'EOF'
github.com/google/uuid v1.6.0 h1:NIvaJDMOsjHA8n1jAhLSgzrAzy1Hgr+hNrb57e+94F0=
github.com/google/uuid v1.6.0/go.mod h1:TIyPZe4MgqvfeYDBFedMoGGpEw/LqOeaOT+nhxU+yHo=
EOF
cat > ~/layers-l3/slow/main.go <<'EOF'
package main

import (
    "fmt"
    "net/http"

    "github.com/google/uuid"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Bonjour, requête %s\n", uuid.NewString())
    })
    http.ListenAndServe(":8080", nil)
}
EOF
echo 'Notes de conception, sans intérêt pour le service.' > ~/layers-l3/slow/docs/notes.md
[ -f ~/layers-l3/slow/fixtures.bin ] || head -c 20000000 /dev/urandom > ~/layers-l3/slow/fixtures.bin
[ -f ~/layers-l3/slow/Dockerfile ] || cat > ~/layers-l3/slow/Dockerfile <<'EOF'
FROM golang:1.24-alpine
WORKDIR /src
COPY . .
RUN go mod download
RUN go build -o /usr/local/bin/slow .
EXPOSE 8080
CMD ["slow"]
EOF
```

On n'améliore bien que ce que l'on a mesuré. Lisez `~/layers-l3/slow/Dockerfile`, construisez-le tel quel, puis notez le poids de l'image.

**Critères :**

- une image s'appelle exactement `layers-l3-slow:before`, construite avec le Dockerfile fourni, sans le modifier ;
- le fichier `~/layers-l3/slow-mesure.txt` contient le poids de cette image, en octets, tel que le donne le champ `.Size` de sa fiche.

```hint
`docker image inspect` lit la fiche d'une image, et `--format` en extrait un champ. Une redirection `>` envoie le résultat dans un fichier.
```

```hint
Le fichier de mesure est volontairement rangé hors du dossier du projet : il n'entre donc pas dans le contexte de build.
```

```verify
I=layers-l3-slow:before
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $I n'existe pas. Construisez le Dockerfile fourni sous ce nom."
  exit 1
fi
if ! docker run --rm --entrypoint go "$I" version >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $I ne contient pas Go. Elle doit venir du Dockerfile fourni, tel quel."
  exit 1
fi
if ! docker run --rm --entrypoint sh "$I" -c 'test -f /src/fixtures.bin'; then
  echo "ÉCHEC : l'image $I ne contient pas fixtures.bin. Elle doit venir du Dockerfile fourni, sans .dockerignore."
  exit 1
fi
SIZE=$(docker image inspect "$I" --format '{{.Size}}')
REPORT="$HOME/layers-l3/slow-mesure.txt"
if [ ! -f "$REPORT" ]; then
  echo "ÉCHEC : le fichier $REPORT n'existe pas."
  exit 1
fi
if ! grep -q "$SIZE" "$REPORT"; then
  echo "ÉCHEC : $REPORT ne contient pas le poids de l'image, soit $SIZE octets selon Docker."
  exit 1
fi
echo "RÉUSSI : vous partez de $SIZE octets."
```

````solution
```bash
docker build -t layers-l3-slow:before ~/layers-l3/slow
docker image inspect layers-l3-slow:before --format '{{.Size}}' > ~/layers-l3/slow-mesure.txt
```
````

# Tâche 2 : ne plus tout refaire

Aujourd'hui, modifier une seule ligne de `main.go` retélécharge toutes les dépendances. Modifiez le Dockerfile pour que ce ne soit plus le cas.

**Critères :**

- le Dockerfile a toujours une étape `RUN` avec `go mod download` ;
- après une modification de `main.go`, cette étape reste **en cache**. La vérification le constate sur une copie temporaire de votre projet, sans toucher à vos fichiers.

```hint
Une instruction rejouée entraîne toutes celles qui la suivent. Quelle ligne du Dockerfile voit `main.go` avant le téléchargement ?
```

```hint
`go mod download` n'a besoin que de deux fichiers. Copiez-les seuls, téléchargez, puis copiez le reste.
```

```verify
SRC="$HOME/layers-l3/slow"
if [ ! -f "$SRC/Dockerfile" ]; then
  echo "ÉCHEC : le fichier $SRC/Dockerfile n'existe pas."
  exit 1
fi
TMP=$(mktemp -d)
cp -R "$SRC/." "$TMP/"
if ! FIRST=$(docker build -q -t layers-l3-slow:essai "$TMP" 2>/dev/null); then
  rm -rf "$TMP"
  echo "ÉCHEC : votre Dockerfile ne se construit pas. Lancez docker build à la main pour lire l'erreur."
  exit 1
fi
echo '// une ligne de plus' >> "$TMP/main.go"
OUT=$(docker build --progress=plain -t layers-l3-slow:essai "$TMP" 2>&1)
docker image rm layers-l3-slow:essai >/dev/null 2>&1
[ "$(docker image inspect "$FIRST" --format '{{len .RepoTags}}' 2>/dev/null)" = "0" ] && docker image rm "$FIRST" >/dev/null 2>&1
rm -rf "$TMP"
ID=$(printf '%s\n' "$OUT" | sed -n 's/^#\([0-9]*\) \[.*RUN .*go mod download.*/\1/p' | head -1)
if [ -z "$ID" ]; then
  echo "ÉCHEC : le build n'a plus d'étape RUN avec go mod download."
  exit 1
fi
if ! printf '%s\n' "$OUT" | grep -q "^#$ID CACHED"; then
  echo "ÉCHEC : après une modification de main.go, go mod download est rejoué."
  exit 1
fi
echo "RÉUSSI : modifier le code ne relance plus le téléchargement."
```

````solution
```bash
cat > ~/layers-l3/slow/Dockerfile <<'EOF'
FROM golang:1.24-alpine
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /usr/local/bin/slow .
EXPOSE 8080
CMD ["slow"]
EOF
```
````

# Tâche 3 : alléger le contexte

Le dossier contient `fixtures.bin`, un fichier de 20 Mo, et un dossier `docs`. Le service n'a besoin d'aucun des deux, alors qu'ils sont envoyés à Docker à chaque build, et que leur moindre changement fait sauter le cache de `COPY . .`.

**Critères :**

- `fixtures.bin` et `docs` **ne peuvent plus entrer** dans le contexte de build. La vérification construit un essai à partir de votre dossier pour le constater ;
- `main.go`, `go.mod` et `go.sum` y entrent toujours.

```hint
Un seul fichier suffit, à la racine du projet : il liste ce que Docker doit laisser de côté, un motif par ligne.
```

```verify
DIR="$HOME/layers-l3/slow"
OUT=$(mktemp -d)
if ! printf 'FROM scratch\nCOPY . /\n' | docker build -q -f - -o "type=local,dest=$OUT" "$DIR" >/dev/null 2>&1; then
  echo "ÉCHEC : l'essai de build a échoué sur le dossier $DIR. Le .dockerignore a-t-il exclu tout le projet ?"
  rm -rf "$OUT"
  exit 1
fi
bad=""
[ -e "$OUT/fixtures.bin" ] && bad="$bad fixtures.bin"
[ -e "$OUT/docs" ] && bad="$bad docs"
missing=""
for f in main.go go.mod go.sum; do
  [ -f "$OUT/$f" ] || missing="$missing $f"
done
rm -rf "$OUT"
if [ -n "$bad" ]; then
  echo "ÉCHEC : ces éléments entrent encore dans le contexte de build :$bad"
  exit 1
fi
if [ -n "$missing" ]; then
  echo "ÉCHEC : le .dockerignore en exclut trop, il manque :$missing"
  exit 1
fi
echo "RÉUSSI : le contexte ne contient plus que ce qui sert."
```

````solution
```bash
cat > ~/layers-l3/slow/.dockerignore <<'EOF'
fixtures.bin
docs
Dockerfile
.dockerignore
EOF
```
````

# Tâche 4 : ne livrer que le résultat

L'image contient encore le compilateur et votre code source, alors que le service n'a besoin que de son binaire. Réduisez-la, sans perdre ce que vous avez gagné à la tâche 2.

**Critères :**

- une image s'appelle exactement `layers-l3-slow:after` ;
- elle pèse **au moins cinq fois moins** que `layers-l3-slow:before`, d'après leur champ `.Size` ;
- elle ne contient ni le compilateur Go, ni `main.go` ;
- un conteneur `layers-l3-slow` tourne depuis cette image, et le port **28332** de la machine mène au port d'écoute du service, qui répond ;
- après une modification de `main.go`, `go mod download` reste en cache.

L'image finale peut partir de la base que vous voulez, parmi celles que vous connaissez.

```hint
Chaque `FROM` ouvre un stage, et seul le dernier devient l'image. Un `COPY --from=<nom>` y apporte ce qui vous intéresse.
```

```hint
Le binaire s'appelle `/usr/local/bin/slow` dans le Dockerfile fourni. Copiez-le dans le stage final, et adaptez la commande de démarrage en conséquence.
```

```hint
Sur `scratch`, il vous faut un binaire autonome : `CGO_ENABLED=0` devant `go build`, et `CMD` en forme exec avec le chemin complet du binaire. Si le conteneur s'arrête, lisez `docker logs layers-l3-slow`.
```

```verify
A=layers-l3-slow:after
B=layers-l3-slow:before
C=layers-l3-slow
E=layers-l3-slow-essai
SRC="$HOME/layers-l3/slow"
if ! docker image inspect "$A" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $A n'existe pas."
  exit 1
fi
if ! docker image inspect "$B" >/dev/null 2>&1; then
  echo "ÉCHEC : l'image $B n'existe plus, et il n'y a donc rien à comparer. Refaites la tâche 1 avec le Dockerfile d'origine."
  exit 1
fi
SA=$(docker image inspect "$A" --format '{{.Size}}')
SB=$(docker image inspect "$B" --format '{{.Size}}')
if [ "$((SA * 5))" -gt "$SB" ]; then
  echo "ÉCHEC : $A pèse $SA octets, et il faut au plus un cinquième de $SB octets."
  exit 1
fi
docker rm -f "$E" >/dev/null 2>&1
docker create --name "$E" "$A" >/dev/null 2>&1
FILES=$(docker export "$E" 2>/dev/null | tar -tf - 2>/dev/null)
docker rm -f "$E" >/dev/null 2>&1
if printf '%s\n' "$FILES" | grep -qE '(^|/)main\.go$'; then
  echo "ÉCHEC : main.go est encore dans $A."
  exit 1
fi
if printf '%s\n' "$FILES" | grep -qE '(^|/)bin/go$'; then
  echo "ÉCHEC : le compilateur Go est encore dans $A."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.Image}}')" != "$(docker image inspect "$A" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : $C ne vient pas de la dernière version de $A. Supprimez-le et recréez-le."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Ses derniers logs : $(docker logs "$C" 2>&1 | tail -2 | tr '\n' ' ')"
  exit 1
fi
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28332 | grep -q 'Bonjour'; then
  echo "ÉCHEC : le port 28332 ne répond pas. Rappel : le service écoute sur le port 8080."
  exit 1
fi
TMP=$(mktemp -d)
cp -R "$SRC/." "$TMP/"
FIRST=$(docker build -q -t layers-l3-slow:essai "$TMP" 2>/dev/null)
echo '// une ligne de plus' >> "$TMP/main.go"
OUT=$(docker build --progress=plain -t layers-l3-slow:essai "$TMP" 2>&1)
docker image rm layers-l3-slow:essai >/dev/null 2>&1
[ "$(docker image inspect "$FIRST" --format '{{len .RepoTags}}' 2>/dev/null)" = "0" ] && docker image rm "$FIRST" >/dev/null 2>&1
rm -rf "$TMP"
ID=$(printf '%s\n' "$OUT" | sed -n 's/^#\([0-9]*\) \[.*RUN .*go mod download.*/\1/p' | head -1)
if [ -z "$ID" ] || ! printf '%s\n' "$OUT" | grep -q "^#$ID CACHED"; then
  echo "ÉCHEC : l'image est légère, mais go mod download est de nouveau rejoué quand main.go change. Reprenez la tâche 2."
  exit 1
fi
echo "RÉUSSI : de $SB à $SA octets, et le service répond."
```

````solution
```bash
cat > ~/layers-l3/slow/Dockerfile <<'EOF'
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /slow .

FROM scratch
COPY --from=build /slow /slow
EXPOSE 8080
CMD ["/slow"]
EOF
docker build -t layers-l3-slow:after ~/layers-l3/slow
docker rm -f layers-l3-slow
docker run -d --name layers-l3-slow -p 28332:8080 layers-l3-slow:after
```
````

# Tâche 5 : ne rien laisser derrière soi

Supprimez tout ce que ce challenge a créé.

**Critères :** plus de conteneur `layers-l3-slow`, plus d'images `layers-l3-slow:before` et `layers-l3-slow:after`, plus de dossier `~/layers-l3/slow`, plus de fichier `~/layers-l3/slow-mesure.txt`. Vos autres images et vos autres conteneurs ne sont pas concernés. Si vous avez reconstruit plusieurs fois sous un même tag, d'anciennes versions peuvent rester sans nom, affichées `<none>` par `docker images` : la vérification ne les regarde pas, et `docker image rm <identifiant>` supprime celles que vous reconnaissez.

```hint
Le conteneur d'abord, les images ensuite, et les fichiers enfin : `docker rm -f`, `docker image rm`, `rm -rf`.
```

```verify
if docker container inspect layers-l3-slow >/dev/null 2>&1 || docker container inspect layers-l3-slow-essai >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur layers-l3-slow existe encore."
  exit 1
fi
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^layers-l3-slow:')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l3/slow" ] || [ -e "$HOME/layers-l3/slow-mesure.txt" ]; then
  echo "ÉCHEC : ~/layers-l3/slow ou ~/layers-l3/slow-mesure.txt existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez réduire et accélérer une image."
```

````solution
```bash
docker rm -f layers-l3-slow
docker image rm layers-l3-slow:before layers-l3-slow:after
rm -rf ~/layers-l3/slow ~/layers-l3/slow-mesure.txt
```
````
