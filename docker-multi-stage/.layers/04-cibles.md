---
title: "Viser un stage : tests et --target"
description: "Construire une partie du Dockerfile"
---

Un Dockerfile multi-stage peut contenir plus que de la construction et une image finale : un stage peut lancer les tests dans le même environnement que la compilation. Il reste à pouvoir choisir ce qu'on construit.

## Ajouter un stage de test

Écrivez un petit test de l'application. Son contenu importe peu : `go test` lance la fonction `TestMessage`, qui vérifie la phrase renvoyée par `message()`, et `./...` veut dire « tout le projet ».

```exec
cat > ~/layers-l3/multi/main_test.go <<'EOF'
package main

import "testing"

func TestMessage(t *testing.T) {
    if message() != "Bonjour depuis Go" {
        t.Fatal("message inattendu")
    }
}
EOF
```

Ajoutez un stage `test` entre les deux autres. `FROM build AS test` repart du stage `build`, tel qu'il est à sa fin : un stage peut en prolonger un autre.

```exec
cat > ~/layers-l3/multi/Dockerfile <<'EOF'
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /hello .

FROM build AS test
RUN CGO_ENABLED=0 go test ./...

FROM scratch
COPY --from=build /hello /hello
CMD ["/hello"]
EOF
```

## Construire seulement ce qu'il faut

Sans option, Docker vise le dernier stage et ne construit que ce dont il dépend. `test` n'en fait pas partie, car le stage final ne copie rien de lui. Pour le constater, `--progress=plain` détaille les étapes, `2>&1` envoie les messages de Docker dans le tube `|`, et `grep` cherche celle du test. Elle ne doit pas apparaître, et `grep -c` compte donc `0` :

```exec
docker build --progress=plain -t layers-l3-multi:scratch ~/layers-l3/multi 2>&1 | grep -c 'go test'
```

L'option `--target` choisit le stage à construire. Docker s'arrête après lui, et l'image contient donc ce stage. Lancez les tests. Docker garde le résultat des étapes déjà faites et ne les réaffiche pas : `--no-cache` l'oblige à tout refaire, pour que la sortie de `go test` s'affiche. `grep -E` retient ici les lignes qui parlent de `go test` et celles qui disent `ok` :

```exec
docker build --no-cache --target test --progress=plain -t layers-l3-multi:test ~/layers-l3/multi 2>&1 | grep -E 'go test|^#[0-9]+ .*ok'
```

Vous devez lire la ligne `RUN CGO_ENABLED=0 go test ./...`, puis une ligne qui contient `ok  	example.com/hello`. C'est ainsi qu'un serveur qui vérifie chaque modification du code, ce qu'on appelle l'intégration continue, peut tester puis construire l'image avec un seul Dockerfile. Si un test échoue, `go test` sort en erreur, et le build échoue avec lui.

```verify
if ! docker image inspect layers-l3-multi:test >/dev/null 2>&1; then
  echo "L'image layers-l3-multi:test n'existe pas. Relancez le docker build avec --target test."
  exit 1
fi
if ! docker run --rm layers-l3-multi:test go version >/dev/null 2>&1; then
  echo "L'image layers-l3-multi:test ne contient pas Go : elle ne vient pas du stage test."
  exit 1
fi
if docker run --rm layers-l3-multi:scratch /bin/sh -c true >/dev/null 2>&1; then
  echo "L'image layers-l3-multi:scratch contient un shell. Elle doit venir du dernier stage, parti de scratch."
  exit 1
fi
echo "Un seul Dockerfile, deux images : le stage test pour vérifier, le stage final pour livrer."
```

## Nettoyer

Supprimez les images de ce cours et votre dossier. Le conteneur est déjà parti.

```exec
docker image rm layers-l3-multi:lourd layers-l3-multi:alpine layers-l3-multi:scratch layers-l3-multi:test
rm -rf ~/layers-l3/multi
```

```verify
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^layers-l3-multi:')
if [ -n "$left" ]; then
  echo "Il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if docker container inspect layers-l3-multi >/dev/null 2>&1; then
  echo "Le conteneur layers-l3-multi existe encore."
  exit 1
fi
if [ -e "$HOME/layers-l3/multi" ]; then
  echo "Le dossier ~/layers-l3/multi existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Viser un stage avec `--target`](https://docs.docker.com/build/building/multi-stage/#stop-at-a-specific-build-stage) · [`docker build`](https://docs.docker.com/reference/cli/docker/build/)

## Ce qu'il faut retenir

- Chaque `FROM` ouvre un stage, et seul le dernier devient l'image.
- `AS` nomme un stage, et `COPY --from` en extrait un résultat. Le reste ne part pas.
- On construit avec tous les outils, puis on livre sur une petite base : `alpine` si l'on veut garder un shell, `scratch` pour un binaire autonome.
- Sur `scratch`, il faut la forme exec de `CMD`, et il n'y a aucun outil pour examiner le conteneur.
- `--target` choisit le stage à construire, ce qui sert notamment aux tests.

Pour vous tester sans guide : le challenge « Réduire et accélérer une image existante ».

## Questions

```quiz
title: "Viser un stage"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Sans `--target`, le stage `test` de votre Dockerfile est-il construit ?"
    answers:
      - "Oui, tous les stages le sont toujours"
      - "Non : Docker ne construit que ce dont le dernier stage dépend"
      - "Oui, mais seulement au premier build"
    correct: 2
    explanation: "Le stage final ne copie rien de `test`, donc Docker le laisse de côté. Vous l'avez constaté avec `grep -c`."
  - prompt: "Que produit `docker build --target build -t mon-app:dev .` ?"
    answers:
      - "Une image qui contient le stage `build`, compilateur compris"
      - "Une image vide"
      - "L'image finale, sous un autre tag"
    correct: 1
    explanation: "Le build s'arrête à ce stage, et l'image en est le résultat. C'est utile pour travailler, moins pour livrer."
```
