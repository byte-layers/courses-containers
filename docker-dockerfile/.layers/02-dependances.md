---
title: "Installer des dépendances"
description: "WORKDIR, RUN, et deux erreurs à savoir lire"
---

L'application de l'étape précédente n'avait besoin que de Python. Une vraie application utilise des bibliothèques qu'il faut installer pendant la construction de l'image, et pas à chaque démarrage. C'est le rôle de l'instruction `RUN`, que cette étape ajoute avec `WORKDIR`.

## Une application avec une dépendance

Cette application utilise Flask, une bibliothèque Python pour écrire des serveurs web. Créez son dossier et son code :

```exec
mkdir -p ~/layers-l2/web
cat > ~/layers-l2/web/app.py <<'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return os.environ.get("GREETING", "Bonjour") + " depuis Flask\n"
EOF
```

Ce code répond une phrase dont le début vient de la variable d'environnement `GREETING`, avec `Bonjour` si elle n'existe pas. Vous en aurez besoin à l'étape suivante.

Un projet Python liste ses dépendances dans un fichier, appelé par habitude `requirements.txt`. Il n'y a ici qu'une ligne, qui demande Flask en version 3.1 :

```exec
echo 'flask==3.1.*' > ~/layers-l2/web/requirements.txt
```

## Écrire le Dockerfile

Ce Dockerfile introduit deux instructions et reste volontairement imparfait : vous allez le corriger plus bas.

```exec
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["flask", "run"]
EOF
```

Chaque nouvelle ligne a un rôle précis, que voici.

| Instruction | Rôle |
|---|---|
| `WORKDIR /app` | se place dans le dossier `/app`, créé s'il n'existe pas. Les instructions suivantes et le conteneur partent de là |
| `COPY requirements.txt .` | copie le fichier dans le dossier courant de l'image, `/app`, que le point désigne |
| `RUN pip install -r requirements.txt` | exécute une commande **pendant la construction**, et son résultat reste dans l'image. `pip` est l'installateur de Python, et `-r` lui fait lire la liste de ce fichier |
| `CMD ["flask", "run"]` | au démarrage, lance le serveur de Flask, qui cherche l'application dans le fichier `app.py` et écoute par défaut sur le port 5000 |

Vous remarquerez que `requirements.txt` et `app.py` sont copiés séparément. Cet ordre en deux temps accélère les builds suivants, ce qu'un prochain cours explique.

La différence entre `RUN` et `CMD` est le point essentiel de cette étape. `RUN` travaille une fois, au build, pour préparer l'image. `CMD` travaille à chaque démarrage de conteneur.

Construisez cette première version :

```exec
docker build -t layers-l2-web:1.0 ~/layers-l2/web
```

Le téléchargement de Flask apparaît sur la ligne `RUN`, et il faut compter quelques secondes. Il faut donc un accès au réseau pendant le build.

```verify
if ! docker image inspect layers-l2-web:1.0 >/dev/null 2>&1; then
  echo "L'image layers-l2-web:1.0 n'existe pas. Relancez le docker build et lisez son message d'erreur."
  exit 1
fi
if [ "$(docker image inspect layers-l2-web:1.0 --format '{{.Config.WorkingDir}}')" != "/app" ]; then
  echo "Le dossier de travail de l'image n'est pas /app : la ligne WORKDIR manque."
  exit 1
fi
if ! docker run --rm layers-l2-web:1.0 python -c 'import flask' 2>/dev/null; then
  echo "Flask n'est pas installé dans l'image : la ligne RUN n'a pas fait son travail."
  exit 1
fi
echo "L'image contient Flask et travaille dans /app."
```

## Lire une erreur de build

Avant de lancer l'image, voyez à quoi ressemble un build qui échoue, car vous en rencontrerez. Ce Dockerfile de test, écrit à part dans `Dockerfile.casse`, contient une faute de frappe dans le nom du fichier. `-f` indique à `docker build` quel fichier lire à la place de `Dockerfile` :

```exec
printf 'FROM python:3.13-alpine\nCOPY requirement.txt .\n' > ~/layers-l2/web/Dockerfile.casse
docker build -f ~/layers-l2/web/Dockerfile.casse ~/layers-l2/web
```

Docker s'arrête en montrant la ligne fautive, marquée `>>>`, puis la raison à la fin du message : `"/requirement.txt": not found`. Il faut lire ce chemin depuis le contexte de build : aucun fichier de ce nom ne se trouve dans `~/layers-l2/web`. Le reste de la ligne est interne à Docker, inutile de le déchiffrer.

Une commande qui échoue dans un `RUN` s'affiche autrement. Ici, le fichier a un nom correct, mais il n'a jamais été copié dans l'image :

```exec
printf 'FROM python:3.13-alpine\nRUN pip install -r requirements.txt\n' > ~/layers-l2/web/Dockerfile.casse
docker build -f ~/layers-l2/web/Dockerfile.casse ~/layers-l2/web
```

Le vrai message est écrit juste avant la fin, par `pip` lui-même : `Could not open requirements file`. La dernière ligne dit seulement que le processus a échoué, avec `exit code: 1`. Le réflexe est donc de remonter au-dessus de la dernière ligne.

Ce fichier de test ne sert plus, supprimez-le :

```exec
rm ~/layers-l2/web/Dockerfile.casse
```

```ack
Je sais où lire l'erreur d'un build
```

## Le serveur qui ne répond pas

Lancez maintenant votre image. Flask écoute sur le port 5000, que vous publiez sur le port 28320 :

```exec
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.0
```

Attendez deux secondes, puis demandez la page, avec `-sS` pour afficher une éventuelle erreur et `--max-time 3` pour ne pas attendre plus de trois secondes :

```exec
sleep 2
curl -sS --max-time 3 http://localhost:28320
```

Vous obtenez une erreur de connexion, par exemple `Connection reset by peer` : aucune page ne revient. Pourtant, le conteneur tourne et le port est publié. Pas d'inquiétude, le symptôme, la cause et le correctif tiennent en trois lignes, et les logs mettent sur la voie :

```exec
docker logs layers-l2-web
```

Repérez la ligne `Running on http://127.0.0.1:5000`.

- **Symptôme** : le conteneur tourne, mais le port publié ne répond pas.
- **Cause** : `127.0.0.1`, aussi appelée `localhost`, désigne « cette machine-ci ». Dans un conteneur, cela veut dire le conteneur lui-même. Le serveur n'accepte que les requêtes venues de l'intérieur, et celles de `-p` arrivent de l'extérieur.
- **Correctif** : demander au serveur d'écouter sur toutes ses adresses, ce qui s'écrit `0.0.0.0`.

Un prochain cours, « Localhost n'est pas l'hôte », reprend ce sujet en détail. Beaucoup de serveurs de développement ont ce réglage par défaut : retenez ce symptôme, il reviendra.

Corrigez le `CMD`, puis reconstruisez sous un nouveau tag et relancez :

```exec
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Le build va beaucoup plus vite cette fois. Un prochain cours explique pourquoi. L'ancien conteneur occupe encore le nom et le port : supprimez-le avant d'en créer un nouveau.

```exec
docker build -t layers-l2-web:1.1 ~/layers-l2/web
docker rm -f layers-l2-web
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.1
```

Redemandez la page, en laissant cette fois au serveur le temps de démarrer :

```exec
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28320
```

Vous devez lire `Bonjour depuis Flask`.

⚖️ `flask run` est un serveur de développement, et ses logs le rappellent d'ailleurs par un avertissement. Il suffit pour apprendre, mais en production on utilise un serveur dédié.

```verify
if ! curl -s --max-time 5 http://localhost:28320 | grep -q 'depuis Flask'; then
  echo "Le port 28320 ne renvoie pas la page de Flask. Lisez : docker logs layers-l2-web"
  exit 1
fi
if [ "$(docker inspect layers-l2-web --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l2-web:1.1" ]; then
  echo "Le conteneur layers-l2-web doit venir de l'image layers-l2-web:1.1. Reconstruisez, supprimez-le et recréez-le."
  exit 1
fi
echo "Flask répond, avec le serveur ouvert sur toutes ses adresses."
```

Supprimez ce conteneur, car l'étape suivante en crée un autre :

```exec
docker rm -f layers-l2-web
```

> 📖 [`RUN`](https://docs.docker.com/reference/dockerfile/#run) · [`WORKDIR`](https://docs.docker.com/reference/dockerfile/#workdir) · [`COPY`](https://docs.docker.com/reference/dockerfile/#copy)

## Questions

```quiz
title: "Installer des dépendances"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi installer les bibliothèques avec `RUN` plutôt qu'au démarrage dans `CMD` ?"
    answers:
      - "`CMD` ne sait pas lancer `pip`"
      - "Avec `RUN`, le résultat est dans l'image : chaque conteneur démarre prêt, sans réseau ni attente"
      - "`RUN` s'exécute à chaque démarrage, donc les bibliothèques sont à jour"
    correct: 2
    explanation: "`RUN` s'exécute une fois, au build. Le résultat fait partie de l'image, et tous les conteneurs en profitent."
  - prompt: "Le conteneur tourne, le port est publié, mais `curl` échoue, et les logs disent `Running on http://127.0.0.1:5000`. Que faire ?"
    answers:
      - "Changer le port publié"
      - "Faire écouter le serveur sur `0.0.0.0` : dans un conteneur, `127.0.0.1` est le conteneur lui-même"
      - "Relancer le conteneur avec `--rm`"
    correct: 2
    explanation: "Le serveur n'accepte que ce qui vient de l'intérieur du conteneur, alors qu'une requête publiée par `-p` vient de l'extérieur."
  - prompt: "Un build échoue sur un `RUN` et sa dernière ligne dit `exit code: 1`. Où est l'explication ?"
    answers:
      - "Au-dessus, dans ce que la commande a écrit avant d'échouer"
      - "Dans `docker logs`"
      - "Nulle part : il faut relancer avec plus de mémoire"
    correct: 1
    explanation: "La dernière ligne dit seulement que la commande a échoué. La raison est dans sa propre sortie, juste au-dessus."
```
