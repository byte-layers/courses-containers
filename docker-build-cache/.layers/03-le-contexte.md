---
title: "Le contexte invalide aussi"
description: "Un fichier sans importance peut faire sauter le cache"
---

Votre Dockerfile est bien ordonné, mais `COPY . .` regarde encore tous les fichiers du contexte. Un fichier sans rapport avec l'application peut donc le faire rejouer, avec tout ce qui le suit.

## Un fichier qui n'a rien à voir

Pour rendre le coût visible, ajoutez après `COPY . .` une étape de préparation. `python -m compileall .` précompile le code Python pour un démarrage un peu plus rapide, et `-q` le rend silencieux. Puis simulez ce qui arrive sur un poste de développement : un fichier de logs apparaît dans le dossier.

```exec
cat > ~/byte-layers/docker/l3/cache/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
RUN python -m compileall -q .
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
docker build -t layers-l3-cache:3.0 ~/byte-layers/docker/l3/cache
```

Écrivez une ligne dans un fichier de logs, puis reconstruisez :

```exec
echo "$(date) une requête" >> ~/byte-layers/docker/l3/cache/app.log
docker build -t layers-l3-cache:3.1 ~/byte-layers/docker/l3/cache
```

`COPY . .` et `RUN python -m compileall` ne sont plus en cache, alors que votre application n'a pas changé d'une ligne. Pire, ce fichier de logs vient d'entrer dans votre image.

## Le correctif : .dockerignore

Un fichier ignoré n'entre pas dans le contexte. Il n'a donc plus aucun effet sur l'empreinte calculée par `COPY`. Cette liste nomme aussi `Dockerfile` et `.dockerignore` : `docker build` les lit quand même, mais ils n'atteignent plus `COPY`. Écrivez ce fichier et construisez une première fois, ce qui prépare le cache :

```exec
cat > ~/byte-layers/docker/l3/cache/.dockerignore <<'EOF'
*.log
Dockerfile
.dockerignore
EOF
docker build -t layers-l3-cache:3.2 ~/byte-layers/docker/l3/cache
```

Modifiez à nouveau les logs, et reconstruisez :

```exec
echo "$(date) une autre requête" >> ~/byte-layers/docker/l3/cache/app.log
docker build -t layers-l3-cache:3.3 ~/byte-layers/docker/l3/cache
```

Tout est `CACHED` après `FROM`. Sur un vrai projet, les habitués de ce fichier sont `.git`, dont le contenu change à chaque commit, les dossiers de dépendances locaux et les fichiers générés.

```verify
SRC="$HOME/byte-layers/docker/l3/cache"
TMP=$(mktemp -d)
cp -R "$SRC/." "$TMP/" 2>/dev/null
if [ ! -f "$TMP/Dockerfile" ]; then
  rm -rf "$TMP"
  echo "Le dossier ~/byte-layers/docker/l3/cache n'est pas là. Reprenez le cours depuis le début."
  exit 1
fi
FIRST=$(docker build -q -t layers-l3-cache:essai "$TMP" 2>/dev/null)
echo 'encore une ligne' >> "$TMP/app.log"
OUT=$(docker build --progress=plain -t layers-l3-cache:essai "$TMP" 2>&1)
FOUND=$(docker run --rm layers-l3-cache:essai ls -A 2>/dev/null)
docker image rm layers-l3-cache:essai >/dev/null 2>&1
[ "$(docker image inspect "$FIRST" --format '{{len .RepoTags}}' 2>/dev/null)" = "0" ] && docker image rm "$FIRST" >/dev/null 2>&1
rm -rf "$TMP"
ID=$(printf '%s\n' "$OUT" | sed -n 's/^#\([0-9]*\) \[.*COPY \. \..*/\1/p' | head -1)
if [ -z "$ID" ] || ! printf '%s\n' "$OUT" | grep -q "^#$ID CACHED"; then
  echo "Un fichier de logs fait encore rejouer COPY . . : vérifiez ~/byte-layers/docker/l3/cache/.dockerignore."
  exit 1
fi
if printf '%s\n' "$FOUND" | grep -q '\.log$'; then
  echo "Un fichier de logs est encore dans l'image : vérifiez ~/byte-layers/docker/l3/cache/.dockerignore."
  exit 1
fi
echo "Les logs ne touchent plus au cache, et ils restent hors de l'image."
```

> 📖 [Les fichiers `.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files)

## Questions

```quiz
title: "Le contexte invalide aussi"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi un `.git` non ignoré fait-il sauter le cache de `COPY . .` à chaque commit ?"
    answers:
      - "Parce que Docker lit l'historique du projet"
      - "Parce que le contenu du dossier `.git` change, et qu'il fait partie du contexte copié"
      - "Parce que `COPY` refuse les dossiers cachés"
    correct: 2
    explanation: "`COPY . .` prend tout le contexte. Tout fichier modifié, même inutile, change l'empreinte."
  - prompt: "Ajouter `*.log` au `.dockerignore` a deux effets. Lesquels ? (plusieurs réponses)"
    answers:
      - "Les logs n'invalident plus le cache"
      - "Les logs n'entrent plus dans l'image"
      - "Les logs sont supprimés de votre machine"
    correct: [1, 2]
    explanation: "Le fichier reste sur votre machine : Docker fait seulement comme s'il n'existait pas."
```
