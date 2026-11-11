---
title: "Ordonner le Dockerfile"
description: "Ce qui change rarement en haut, ce qui change souvent en bas"
---

Votre Dockerfile retélécharge les dépendances à chaque modification du code. Il suffit pourtant d'ajouter une ligne et d'en déplacer une autre, car la règle de l'étape précédente donne la méthode : **ce qui change rarement va en haut, ce qui change souvent va en bas**.

## Séparer les dépendances du code

Les dépendances ne dépendent que d'un fichier, `requirements.txt`. Copiez donc ce fichier seul, installez, et copiez le reste ensuite :

```exec
cat > ~/byte-layers/docker/l3/cache/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
docker build -t layers-l3-cache:2.0 ~/byte-layers/docker/l3/cache
```

Ce build rejoue l'installation, car vous avez changé ce qui se trouve au-dessus d'elle. Il prépare le cache pour la suite.

## Le constater

Modifiez le code une nouvelle fois, puis reconstruisez :

```exec
cat > ~/byte-layers/docker/l3/cache/app.py <<'EOF'
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "version 3\n"
EOF
time docker build -t layers-l3-cache:2.1 ~/byte-layers/docker/l3/cache
```

La ligne `RUN pip install` porte le mot `CACHED`, et seul le dernier `COPY . .` est rejoué. Le build est quasi instantané, alors que votre code a bien changé. Lancez l'image pour vous en assurer. Le port 28330 mène au port 5000, celui de Flask :

```exec
docker run -d --name layers-l3-cache -p 28330:5000 layers-l3-cache:2.1
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28330
```

Vous devez lire `version 3`. Ce conteneur a montré ce qu'il fallait : supprimez-le.

```exec
docker rm -f layers-l3-cache
```

La vérification suivante refait ce test sur une copie temporaire de votre projet : elle change une ligne de code, reconstruit, et regarde si l'installation est restée en cache.

```verify
SRC="$HOME/byte-layers/docker/l3/cache"
if [ ! -f "$SRC/Dockerfile" ]; then
  echo "Le dossier ~/byte-layers/docker/l3/cache n'est pas là. Reprenez l'étape précédente."
  exit 1
fi
TMP=$(mktemp -d)
cp -R "$SRC/." "$TMP/"
FIRST=$(docker build -q -t layers-l3-cache:essai "$TMP" 2>/dev/null)
echo '# une ligne de plus' >> "$TMP/app.py"
OUT=$(docker build --progress=plain -t layers-l3-cache:essai "$TMP" 2>&1)
docker image rm layers-l3-cache:essai >/dev/null 2>&1
[ "$(docker image inspect "$FIRST" --format '{{len .RepoTags}}' 2>/dev/null)" = "0" ] && docker image rm "$FIRST" >/dev/null 2>&1
rm -rf "$TMP"
ID=$(printf '%s\n' "$OUT" | sed -n 's/^#\([0-9]*\) \[.*RUN .*pip install.*/\1/p' | head -1)
if [ -z "$ID" ]; then
  echo "Le build n'a pas d'étape RUN pip install. Reprenez le Dockerfile de cette section."
  exit 1
fi
if ! printf '%s\n' "$OUT" | grep -q "^#$ID CACHED"; then
  echo "Après une modification du code, pip install est rejoué. Copiez requirements.txt seul, avant l'installation, et le reste du projet après."
  exit 1
fi
echo "Modifier le code ne relance plus l'installation."
```

## Quand les dépendances changent vraiment

Le cache n'empêche pas d'ajouter une dépendance : l'empreinte de `requirements.txt` change, et l'installation est rejouée à juste titre. Ajoutez une bibliothèque au fichier avec `>>`, qui écrit à la suite sans effacer :

```exec
echo 'requests==2.32.*' >> ~/byte-layers/docker/l3/cache/requirements.txt
docker build -t layers-l3-cache:2.2 ~/byte-layers/docker/l3/cache
```

Cette fois, `RUN pip install` n'est plus en cache, et tout ce qui le suit non plus.

```ack
Le cache a suivi le changement de dépendances
```

## Le même geste dans d'autres langages

Ce principe ne dépend pas de Python. Chaque écosystème a son fichier de dépendances, à copier seul avant l'installation, comme le montre ce tableau.

| Langage | Copier d'abord | Puis installer |
|---|---|---|
| Python | `requirements.txt` | `pip install -r requirements.txt` |
| Node.js | `package.json` et `package-lock.json` | `npm ci` |
| Go | `go.mod` et `go.sum` | `go mod download` |

Un seul `COPY` peut prendre plusieurs fichiers, à condition que sa destination soit un dossier : `COPY go.mod go.sum ./` les copie tous les deux dans le dossier courant de l'image.

⚖️ Un Dockerfile bien ordonné reste lisible, mais il n'est jamais figé : dès qu'une instruction change souvent, comme une version écrite dans un `ENV`, descendez-la le plus bas possible.

> 📖 [Optimiser l'usage du cache](https://docs.docker.com/build/cache/optimize/) · [Utiliser le cache de build](https://docs.docker.com/get-started/docker-concepts/building-images/using-the-build-cache/)

## Questions

```quiz
title: "Ordonner le Dockerfile"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Dans un projet Node.js, quel ordre évite de réinstaller les dépendances à chaque modification du code ?"
    answers:
      - "`COPY . .` puis `RUN npm ci`"
      - "`COPY package.json package-lock.json ./`, puis `RUN npm ci`, puis `COPY . .`"
      - "`RUN npm ci` puis `COPY . .`"
    correct: 2
    explanation: "L'installation ne dépend que des deux fichiers de dépendances. La dernière réponse échoue, car `npm ci` ne trouverait aucun `package.json`."
  - prompt: "Un Dockerfile commence par `ENV VERSION=2.4.1`, une valeur changée à chaque livraison. Quel est le problème ?"
    answers:
      - "Aucun : `ENV` n'a pas d'effet sur le cache"
      - "À chaque changement de version, toutes les instructions suivantes sont rejouées"
      - "`ENV` doit toujours être la dernière ligne"
    correct: 2
    explanation: "Son texte change, donc l'instruction est rejouée, et tout ce qui la suit aussi. Il vaut mieux la descendre."
```
