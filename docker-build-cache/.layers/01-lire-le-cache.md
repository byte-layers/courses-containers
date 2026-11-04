---
title: "Lire le cache"
description: "CACHED, et ce qui fait qu'une instruction est rejouée"
---

Quand vous construisez une image, Docker garde le résultat de chaque instruction. Au build suivant, si rien n'a changé pour une instruction, il réutilise ce résultat au lieu de la rejouer : c'est le **cache de build**. Cette étape vous apprend à le lire, puis à comprendre ce qui le fait sauter.

## Un premier build, sans cache

Créez une petite application et son Dockerfile. Celui-ci est écrit comme on l'écrit spontanément, et vous allez découvrir son défaut :

```exec
mkdir -p ~/layers-l3/cache
cat > ~/layers-l3/cache/app.py <<'EOF'
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "version 1\n"
EOF
echo 'flask==3.1.*' > ~/layers-l3/cache/requirements.txt
```

Voici le Dockerfile. Il copie tout le projet, puis installe les dépendances :

```exec
cat > ~/layers-l3/cache/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Construisez-le avec `--no-cache`, qui oblige Docker à tout refaire. Ainsi, vous partez du même point, même si vous avez déjà construit quelque chose de semblable. `time` affiche la durée de la commande, sur la ligne `real` ou `total` selon votre shell :

```exec
time docker build --no-cache -t layers-l3-cache:1.0 ~/layers-l3/cache
```

Vous voyez passer le téléchargement de Flask sur la ligne `RUN`, et cela prend plusieurs secondes. Notez cette durée.

```verify
if ! docker run --rm layers-l3-cache:1.0 python -c 'import flask' 2>/dev/null; then
  echo "L'image layers-l3-cache:1.0 n'existe pas, ou Flask n'y est pas. Relancez le docker build et lisez son message d'erreur."
  exit 1
fi
echo "L'image est construite."
```

## Le même build, avec le cache

Relancez la construction, sans `--no-cache` et sans rien changer :

```exec
time docker build -t layers-l3-cache:1.0 ~/layers-l3/cache
```

La commande se termine presque aussitôt, et chaque étape après `FROM` porte le mot `CACHED`, par exemple `CACHED [4/4] RUN pip install -r requirements.txt`. Le téléchargement n'a pas eu lieu : Docker a réutilisé les couches déjà faites.

## Ce qui fait sauter le cache

Pour chaque instruction, Docker se pose une question : ai-je déjà exécuté exactement cela, à partir de la même couche ? La réponse dépend du type d'instruction.

| Instruction | Docker la rejoue si… |
|---|---|
| `FROM` | l'image de base locale a changé |
| `RUN` | le **texte** de la commande a changé, et il ne regarde rien d'autre |
| `COPY` | le **contenu** des fichiers copiés a changé. Il calcule une empreinte de chaque fichier |
| toutes | une instruction au-dessus a été rejouée : **tout ce qui suit est rejoué** |

Cette dernière ligne est la règle la plus importante. Une couche se pose sur celle du dessous : si le socle change, le résultat de ce qui est posé dessus ne vaut plus rien.

Vérifiez d'abord que seul le contenu compte. `touch` change la date d'un fichier sans toucher à son contenu :

```exec
touch ~/layers-l3/cache/app.py
docker build -t layers-l3-cache:1.0 ~/layers-l3/cache
```

Tout reste `CACHED` après `FROM`. Changez maintenant le code. Cette commande réécrit `app.py` avec une autre réponse :

```exec
cat > ~/layers-l3/cache/app.py <<'EOF'
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "version 2\n"
EOF
time docker build -t layers-l3-cache:1.1 ~/layers-l3/cache
```

Vous n'avez modifié qu'une ligne de votre application, et Flask se télécharge à nouveau. `COPY . .` a vu un fichier changer, et le `RUN` situé dessous a donc été rejoué, alors que vos dépendances n'ont pas bougé. C'est le défaut annoncé, et la prochaine étape le corrige.

```verify
V=$(docker run --rm layers-l3-cache:1.1 grep -c 'version 2' app.py 2>/dev/null)
if [ "$V" != "1" ]; then
  echo "L'image layers-l3-cache:1.1 ne contient pas le code modifié. Refaites la commande de cette section."
  exit 1
fi
echo "La nouvelle image contient votre modification."
```

> 📖 [Le cache de build](https://docs.docker.com/build/cache/) · [Ce qui invalide le cache](https://docs.docker.com/build/cache/invalidation/)

## Questions

```quiz
title: "Lire le cache"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Sur quel critère Docker décide-t-il de rejouer une instruction `COPY` ?"
    answers:
      - "La date de modification des fichiers"
      - "Le contenu des fichiers copiés"
      - "Il la rejoue à chaque build"
    correct: 2
    explanation: "Docker calcule une empreinte du contenu. Vous l'avez constaté avec `touch` : la date change, et l'étape reste `CACHED`."
  - prompt: "Un Dockerfile a cinq instructions, et la troisième est rejouée. Que deviennent la quatrième et la cinquième ?"
    answers:
      - "Elles restent en cache"
      - "Elles sont rejouées aussi, car elles se posent sur une couche qui a changé"
      - "Le build échoue"
    correct: 2
    explanation: "Une instruction rejouée invalide tout ce qui la suit."
  - prompt: "Votre `RUN pip install` s'est rejoué alors que `requirements.txt` n'a pas changé. Quelle est l'explication la plus probable ?"
    answers:
      - "Une instruction placée au-dessus a été rejouée"
      - "`pip` refuse le cache"
      - "Le cache expire après une heure"
    correct: 1
    explanation: "Dans cette étape, c'est `COPY . .`, placé au-dessus, qui a changé. Le `RUN` en a hérité."
```
