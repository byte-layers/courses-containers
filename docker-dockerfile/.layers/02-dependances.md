---
title: "Choisir sa base et installer des dépendances"
description: "Base nue ou base prête, le tag à prendre, WORKDIR, RUN, et les erreurs à savoir lire"
---

Votre première image avait une base toute prête et aucune bibliothèque à installer. Une vraie application pose deux questions de plus : de quelle image partir, et comment installer ce dont elle a besoin. L'instruction `RUN` répond à la seconde.

## Partir d'une base nue ou d'une base déjà prête

Pour faire tourner la même application, vous avez deux façons de partir : prendre une base générale et y installer vous-même ce qu'il faut, ou prendre une base déjà proche de votre besoin. Vous avez utilisé la seconde. Essayez la première sur votre projet `hello`, en partant d'Alpine seul. Trois lignes changent :

```diff
-FROM python:3.13-alpine
+FROM alpine:3.22
+RUN apk add --no-cache python3
 COPY app.py /app.py
-CMD ["python", "/app.py"]
+CMD ["python3", "/app.py"]
```

`RUN` exécute une commande **pendant la construction**, et son résultat reste dans l'image. `apk` est le gestionnaire de paquets d'Alpine, et `--no-cache` lui évite de garder son index dans l'image. Ce paquet fournit la commande `python3`, d'où le changement dans `CMD`. Faites cette modification dans votre éditeur, c'est le meilleur entraînement, ou laissez cette commande écrire le même fichier :

```exec
cat > ~/byte-layers/docker/l2/hello/Dockerfile <<'EOF'
FROM alpine:3.22
RUN apk add --no-cache python3
COPY app.py /app.py
CMD ["python3", "/app.py"]
EOF
```

Construisez cette variante sous un autre tag, puis comparez les deux images :

```exec
docker build -t layers-l2-hello:base-nue ~/byte-layers/docker/l2/hello
docker images layers-l2-hello
```

Les deux images existent côte à côte, et leurs tailles sont proches, comme ici sur une machine arm64 :

```text
REPOSITORY        TAG        IMAGE ID       CREATED          SIZE
layers-l2-hello   base-nue   2f53d7d1667b   2 seconds ago    75.9MB
layers-l2-hello   1.0        df8ebdccce7d   59 seconds ago   73.7MB
```

Les tailles ne départagent donc pas ces deux chemins, et ce tableau dit ce qui les départage vraiment.

| Point de départ | Ce que vous gagnez | Ce que vous payez |
|---|---|---|
| Base générale (`alpine:3.22`) | vous décidez de chaque paquet | vous écrivez et entretenez chaque installation. Ici, il manquerait encore `pip` pour installer des bibliothèques |
| Base proche du besoin (`python:3.13-alpine`) | Python et `pip` sont là, et l'image est maintenue par ses auteurs | vous prenez ce qu'ils y ont mis |

On préfère en général la base la plus proche du besoin, et c'est ce que fait la suite de ce cours.

```verify
if [ "$(docker image inspect layers-l2-hello:base-nue --format '{{json .Config.Cmd}}' 2>/dev/null)" != '["python3","/app.py"]' ]; then
  echo "L'image layers-l2-hello:base-nue n'existe pas, ou sa commande n'est pas python3. Vérifiez le Dockerfile et relancez le build."
  exit 1
fi
if ! docker run --rm layers-l2-hello:base-nue python3 --version >/dev/null 2>&1; then
  echo "Python n'est pas dans l'image layers-l2-hello:base-nue. Vérifiez la ligne RUN."
  exit 1
fi
echo "Vous avez construit la même application depuis deux bases."
```

## Choisir le tag de son image de base : quatre critères

Une image publique se décline en dizaines de tags. Ouvrez la [page des tags de Python sur Docker Hub](https://hub.docker.com/_/python/tags) pour les voir. Quatre critères aident à choisir, et ils se lisent sur cette page.

| Critère | La question à se poser |
|---|---|
| **Version** | Quelle version mon application demande-t-elle ? C'est le premier critère : sa documentation le dit |
| **Architecture** | Ce tag existe-t-il pour les processeurs de mes machines, `amd64` et `arm64` par exemple ? Chaque tag liste les siens |
| **Vulnérabilités** | Contient-il des failles connues ? Une **CVE** est l'identifiant public d'une faille. Docker Hub en affiche pour beaucoup d'images officielles, et un outil de scan donne la même information pour les autres |
| **Taille** | Combien pèse-t-il ? Une variante comme `-alpine` part d'un système minimal, et `-slim` d'une Debian allégée. Une image lourde se télécharge plus lentement et embarque plus de logiciels à surveiller |

Essayez sur cette page : quel tag donne Python 3.13 sur Alpine ? C'est `3.13-alpine`, celui de ce cours. Vous pouvez aussi lire ce qu'il y a dedans, car les sources sont souvent publiques : le [dépôt GitHub de l'image Python](https://github.com/docker-library/python) contient ses Dockerfile.

```ack
Je sais ce qui décide du choix d'une image de base
```

## Une application qui dépend d'une bibliothèque

Passons à une application qui a besoin d'installer quelque chose. Celle-ci utilise Flask, une bibliothèque Python pour écrire des serveurs web. Créez son dossier et son code :

```exec
mkdir -p ~/byte-layers/docker/l2/web
cat > ~/byte-layers/docker/l2/web/app.py <<'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return os.environ.get("GREETING", "Bonjour") + " depuis Flask\n"
EOF
```

Ce code répond une phrase dont le début vient de la variable d'environnement `GREETING`, avec `Bonjour` si elle n'existe pas. Vous vous en servirez à l'étape suivante.

Un projet Python liste ses dépendances dans un fichier, appelé par habitude `requirements.txt`. Il n'y a ici qu'une ligne, qui demande Flask en version 3.1 :

```exec
echo 'flask==3.1.*' > ~/byte-layers/docker/l2/web/requirements.txt
```

## Écrire le Dockerfile avec WORKDIR et RUN

Ce Dockerfile ajoute `WORKDIR` et `RUN pip`. Il contient aussi un défaut volontaire, que vous allez rencontrer puis corriger un peu plus bas.

```exec
cat > ~/byte-layers/docker/l2/web/Dockerfile <<'EOF'
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
| `COPY requirements.txt .` | copie le fichier dans le dossier courant de l'image, `/app`, que le point désigne. Il vient avant `RUN`, car `pip` en a besoin |
| `RUN pip install -r requirements.txt` | installe les bibliothèques pendant le build. `pip` est l'installateur de Python, et `-r` lui fait lire la liste de ce fichier |
| `CMD ["flask", "run"]` | au démarrage, lance le serveur de Flask, qui cherche l'application dans le fichier `app.py` et écoute par défaut sur le port 5000 |

La différence entre `RUN` et `CMD` est le point essentiel de cette étape. `RUN` travaille une fois, au build, pour préparer l'image. `CMD` travaille à chaque démarrage de conteneur.

Construisez cette première version. Il faut un accès au réseau, car Flask se télécharge sur la ligne `RUN`, et compter quelques secondes :

```exec
docker build -t layers-l2-web:1.0 ~/byte-layers/docker/l2/web
```

Vous voyez passer une ligne par étape, de `[1/5]` à `[5/5]`. Chaque instruction qui change des fichiers, comme `COPY` ou `RUN`, ajoute une **couche** à l'image (*layer* en anglais) : une tranche de fichiers posée sur les précédentes. Une image est donc un empilement de couches, à commencer par celles de sa base.

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

## Un serveur qui tourne mais ne répond pas

Lancez maintenant votre image. Flask écoute sur le port 5000, que vous publiez sur le port 28320 :

```exec
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.0
```

Regardez son état, comme tout à l'heure :

```exec
docker ps
```

Sur la ligne de `layers-l2-web`, la colonne `STATUS` commence par `Up`, et le port est bien publié. Demandez la page :

```exec
curl http://localhost:28320
```

Cette fois, `curl` répond par une erreur, même si vous attendez et relancez :

```text
curl: (56) Recv failure: Connection reset by peer
```

Le message peut varier selon votre machine, mais aucune page ne revient. Pas d'inquiétude, c'est le défaut annoncé, et les logs mettent sur la voie :

```exec
docker logs layers-l2-web
```

Repérez cette ligne dans ce que Flask a écrit :

```text
 * Running on http://127.0.0.1:5000
```

Le problème se lit en trois temps.

- **Symptôme** : le conteneur tourne, mais le port publié ne répond pas.
- **Cause** : `127.0.0.1`, aussi appelée `localhost`, désigne « cette machine-ci ». Dans un conteneur, cela veut dire le conteneur lui-même. Le serveur n'accepte que les requêtes venues de l'intérieur, et celles qui passent par `-p` arrivent de l'extérieur. Votre premier serveur répondait parce que son code écrivait déjà `0.0.0.0`.
- **Correctif** : demander au serveur d'écouter sur toutes ses adresses, ce qui s'écrit `0.0.0.0`.

Beaucoup de serveurs de développement ont ce réglage par défaut : retenez ce symptôme, il reviendra. Un prochain cours, « Localhost n'est pas l'hôte », reprend le sujet en détail.

## Corriger le CMD, et voir Docker réutiliser ce qui n'a pas changé

Le correctif ne touche que la dernière ligne du Dockerfile :

```diff
-CMD ["flask", "run"]
+CMD ["flask", "run", "--host", "0.0.0.0"]
```

Modifiez-la dans votre éditeur, ou laissez cette commande réécrire le fichier :

```exec
cat > ~/byte-layers/docker/l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Reconstruisez sous un nouveau tag, et regardez la ligne du `RUN` :

```exec
docker build -t layers-l2-web:1.1 ~/byte-layers/docker/l2/web
```

Le build ne prend qu'un instant, et les lignes qui n'ont pas changé portent le mot `CACHED` :

```text
=> CACHED [4/5] RUN pip install -r requirements.txt
```

Docker a réutilisé les couches déjà construites, au lieu de télécharger Flask une seconde fois. Un prochain cours, « Accélérer un build avec le cache », montre comment en tirer parti. L'ancien conteneur occupe encore le nom et le port : supprimez-le avant d'en créer un nouveau, puis vérifiez son état.

```exec
docker rm -f layers-l2-web
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.1
docker ps
```

Redemandez la page. Si `curl` répond par une erreur de connexion, le serveur démarrait encore : attendez une seconde et relancez.

```exec
curl http://localhost:28320
```

Vous devez lire la phrase de Flask :

```text
Bonjour depuis Flask
```

⚖️ `flask run` est un serveur de développement, et ses logs le rappellent d'ailleurs par un avertissement. Il suffit pour apprendre, mais en production on utilise un serveur dédié.

```verify
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28320) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"depuis Flask"*) : ;;
  *) echo "Le port 28320 ne renvoie pas la page de Flask. Lisez : docker logs layers-l2-web"; exit 1 ;;
esac
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

## Lire une erreur de build

Votre Dockerfile fonctionne. Vous rencontrerez pourtant des builds qui échouent, et il vaut mieux savoir où regarder. Ce dossier d'essai contient un Dockerfile avec une faute de frappe : le fichier demandé à `COPY` n'existe pas.

```exec
mkdir -p ~/byte-layers/docker/l2/erreur
cat > ~/byte-layers/docker/l2/erreur/Dockerfile <<'EOF'
FROM python:3.13-alpine
COPY requirement.txt .
EOF
docker build ~/byte-layers/docker/l2/erreur
```

Docker s'arrête en montrant la ligne fautive, marquée `>>>`, et donne la raison à la fin de son message :

```text
   1 |     FROM python:3.13-alpine
   2 | >>> COPY requirement.txt .
   3 |
--------------------
ERROR: failed to build: failed to solve: failed to compute cache key: failed to calculate checksum of ref 9vrv…: "/requirement.txt": not found
```

Ce chemin se lit depuis le contexte de build : aucun fichier de ce nom ne se trouve dans le dossier. Le reste de la ligne est interne à Docker. Une commande qui échoue dans un `RUN` s'affiche autrement. Essayez avec un `pip` à qui il manque son fichier, jamais copié dans l'image :

```exec
cat > ~/byte-layers/docker/l2/erreur/Dockerfile <<'EOF'
FROM python:3.13-alpine
RUN pip install -r requirements.txt
EOF
docker build ~/byte-layers/docker/l2/erreur
```

La dernière ligne dit seulement que le processus a échoué, avec `exit code: 1`. Le vrai message est plus haut, écrit par `pip` lui-même, sous le rappel de la ligne fautive :

```text
ERROR: Could not open requirements file: [Errno 2] No such file or directory: 'requirements.txt'
```

Le réflexe est donc de remonter au-dessus de la dernière ligne. Ce dossier d'essai ne sert plus, supprimez-le. `rm -rf` efface sans demander confirmation, et il faut donc vérifier le chemin :

```exec
rm -rf ~/byte-layers/docker/l2/erreur
```

```ack
Je sais où lire l'erreur d'un build
```

> 📖 [`RUN`](https://docs.docker.com/reference/dockerfile/#run) · [`WORKDIR`](https://docs.docker.com/reference/dockerfile/#workdir) · [`COPY`](https://docs.docker.com/reference/dockerfile/#copy) · [Choisir son image de base](https://docs.docker.com/build/building/best-practices/#choose-the-right-base-image)

## Questions

```quiz
title: "Choisir sa base et installer des dépendances"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi installer les bibliothèques avec `RUN` plutôt qu'au démarrage dans `CMD` ?"
    answers:
      - "Avec `RUN`, le résultat est dans l'image : chaque conteneur démarre prêt, sans réseau ni attente"
      - "`CMD` ne sait pas lancer `pip`"
      - "`RUN` s'exécute à chaque démarrage, donc les bibliothèques sont à jour"
    correct: 1
    explanation: "`RUN` s'exécute une fois, au build. Le résultat fait partie de l'image, et tous les conteneurs en profitent."
  - prompt: "Le conteneur tourne, le port est publié, mais `curl` échoue, et les logs disent `Running on http://127.0.0.1:5000`. Que faire ?"
    answers:
      - "Changer le port publié"
      - "Relancer le conteneur avec `--rm`"
      - "Faire écouter le serveur sur `0.0.0.0` : dans un conteneur, `127.0.0.1` est le conteneur lui-même"
    correct: 3
    explanation: "Le serveur n'accepte que ce qui vient de l'intérieur du conteneur, alors qu'une requête publiée par `-p` vient de l'extérieur."
  - prompt: "Un build échoue sur un `RUN` et sa dernière ligne dit `exit code: 1`. Où est l'explication ?"
    answers:
      - "Au-dessus, dans ce que la commande a écrit avant d'échouer"
      - "Dans `docker logs`"
      - "Nulle part : il faut relancer avec plus de mémoire"
    correct: 1
    explanation: "La dernière ligne dit seulement que la commande a échoué. La raison est dans sa propre sortie, juste au-dessus."
  - prompt: "Qu'est-ce qui produit une nouvelle couche dans une image ?"
    answers:
      - "Une instruction qui change des fichiers, comme `COPY` ou `RUN`"
      - "Chaque `docker run` lancé depuis cette image"
      - "Le tag donné avec `-t`"
    correct: 1
    explanation: "Une image est un empilement de couches. Lancer un conteneur ne change pas l'image, et un tag n'est qu'un nom."
```
