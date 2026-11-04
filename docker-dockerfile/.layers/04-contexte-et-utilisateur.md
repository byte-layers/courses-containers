---
title: "Ce qui entre dans l'image, et qui l'exécute"
description: "COPY . ., .dockerignore et USER"
---

Votre image fonctionne et elle se configure. Il lui reste deux défauts courants, invisibles tant que tout marche : elle peut embarquer des fichiers qui n'ont rien à y faire, et son application tourne en administrateur.

## Le contexte entre tout entier

Jusqu'ici, vous copiez les fichiers un par un. Dès qu'un projet grandit, on écrit plutôt `COPY . .`, qui copie tout le contexte dans le dossier courant de l'image. On garde le `COPY requirements.txt .` du début, pour la raison annoncée à l'étape 2. C'est pratique, et cela demande une précaution. Pour la voir, ajoutez au projet un fichier sensible, comme un projet réel en contient souvent, avec un mot de passe fictif :

```exec
echo 'DB_PASSWORD=pas-dans-l-image' > ~/layers-l2/web/.env
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
ENV GREETING=Salut
EXPOSE 5000
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Construisez, puis lisez le contenu du dossier `/app` dans l'image. Ce qui suit le nom de l'image remplace son `CMD`, et `ls -A` liste aussi les fichiers dont le nom commence par un point :

```exec
docker build -t layers-l2-web:1.3 ~/layers-l2/web
docker run --rm layers-l2-web:1.3 ls -A
```

`.env` est dans la liste, et le `Dockerfile` aussi. Quiconque récupère cette image peut donc lire votre mot de passe, comme cette commande le prouve :

```exec
docker run --rm layers-l2-web:1.3 cat .env
```

## Écrire un .dockerignore

Le fichier `.dockerignore`, placé à la racine du contexte, liste ce que Docker doit ignorer : ces fichiers n'entrent même pas dans le contexte, et `COPY . .` ne peut plus les voir. Il s'écrit avec un motif par ligne, et `*.log` désigne par exemple tous les fichiers finissant par `.log`. Créez-le à la racine du projet. Cette liste nomme aussi `Dockerfile` et `.dockerignore` : `docker build` les lit quand même, mais ils n'atteignent plus `COPY`.

```exec
cat > ~/layers-l2/web/.dockerignore <<'EOF'
.env
Dockerfile
.dockerignore
*.log
EOF
```

Reconstruisez sous le tag `1.4` et relisez le dossier :

```exec
docker build -t layers-l2-web:1.4 ~/layers-l2/web
docker run --rm layers-l2-web:1.4 ls -A
```

Il ne reste que `app.py` et `requirements.txt`.

```verify
LS=$(docker run --rm layers-l2-web:1.4 ls -A 2>/dev/null)
if [ -z "$LS" ]; then
  echo "L'image layers-l2-web:1.4 n'existe pas ou ne démarre pas. Relancez le docker build."
  exit 1
fi
if printf '%s\n' "$LS" | grep -qx '.env'; then
  echo "Le fichier .env est encore dans l'image. Vérifiez ~/layers-l2/web/.dockerignore, puis reconstruisez."
  exit 1
fi
if ! printf '%s\n' "$LS" | grep -qx 'app.py'; then
  echo "app.py manque dans l'image. Le .dockerignore en exclut peut-être trop."
  exit 1
fi
echo "Le fichier .env reste hors de l'image, et l'application y est."
```

⚖️ Un `.dockerignore` protège des oublis, mais ce n'est pas une gestion des secrets. Un prochain cours, « Un secret ne va pas dans l'image », y revient. Le correctif ne vaut d'ailleurs que pour les images à venir : la version `1.3` contient toujours le mot de passe, car une image ne change jamais. Dans un vrai projet, il faudrait donc aussi changer ce mot de passe.

## Ne pas tourner en administrateur

Par défaut, un conteneur s'exécute avec l'utilisateur `root`, l'administrateur de Linux. `id -un` affiche le nom de l'utilisateur courant :

```exec
docker run --rm layers-l2-web:1.4 id -un
```

Vous lisez `root`. Si l'application a une faille, l'attaquant dispose de ces droits dans le conteneur, et il vaut mieux lui en laisser le moins possible. L'instruction `USER` change d'utilisateur pour la suite du Dockerfile et pour le démarrage du conteneur. Cet utilisateur doit exister : sur Alpine, `adduser -D app` en crée un, sans mot de passe.

```exec
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
RUN adduser -D app
USER app
ENV GREETING=Salut
EXPOSE 5000
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

`USER` vient après l'installation, car `pip install` et `adduser` ont besoin des droits d'administrateur. Reconstruisez, puis vérifiez l'utilisateur et le service :

```exec
docker build -t layers-l2-web:1.5 ~/layers-l2/web
docker run --rm layers-l2-web:1.5 id -un
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.5
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28320
```

Vous devez lire `app`, puis `Salut depuis Flask`. L'application n'écrit aucun fichier, donc ce changement ne la gêne pas. Une application qui écrit dans un dossier appartenant à `root` échouerait, et le lab « Conteneuriser getting-started-app » vous fait rencontrer ce cas.

```verify
if [ "$(docker run --rm layers-l2-web:1.5 id -un 2>/dev/null)" != "app" ]; then
  echo "L'image layers-l2-web:1.5 ne tourne pas avec l'utilisateur app. Vérifiez la ligne USER et reconstruisez."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28320 | grep -q 'Salut depuis Flask'; then
  echo "Le port 28320 ne répond pas. Lisez : docker logs layers-l2-web"
  exit 1
fi
echo "L'application répond sans être administrateur."
```

## Nettoyer

Tout ce cours vit sous le préfixe `layers-l2-` et dans `~/layers-l2/`. `docker image rm` supprime des images, et il refuse celles qu'un conteneur utilise encore : supprimez donc le conteneur en premier. Vos dossiers partent ensuite avec `rm -rf`, qui efface sans demander confirmation. Le dossier `~/layers-l2`, alors vide, peut rester.

```exec
docker rm -f layers-l2-web
docker image rm layers-l2-hello:1.0 layers-l2-greet:1.0 layers-l2-web:1.0 layers-l2-web:1.1 layers-l2-web:1.2 layers-l2-web:1.3 layers-l2-web:1.4 layers-l2-web:1.5
rm -rf ~/layers-l2/hello ~/layers-l2/web ~/layers-l2/greet
```

```verify
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^layers-l2-(hello|greet|web):')
if [ -n "$left" ]; then
  echo "Il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if docker container inspect layers-l2-web >/dev/null 2>&1; then
  echo "Le conteneur layers-l2-web existe encore."
  exit 1
fi
if [ -e "$HOME/layers-l2/web" ] || [ -e "$HOME/layers-l2/hello" ] || [ -e "$HOME/layers-l2/greet" ]; then
  echo "Un dossier de ce cours existe encore dans ~/layers-l2."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files) · [`USER`](https://docs.docker.com/reference/dockerfile/#user) · [Bonnes pratiques d'écriture](https://docs.docker.com/build/building/best-practices/)

## Ce qu'il faut retenir

- Un Dockerfile est une recette : `FROM` choisit la base, `COPY` apporte les fichiers, `RUN` prépare l'image au build et `CMD` dit quoi lancer au démarrage.
- `docker build -t nom:tag dossier` construit l'image, et ce dossier, le contexte, est tout ce que `COPY` peut voir.
- `ENV` donne une valeur par défaut que `-e` remplace, et `EXPOSE` documente un port sans le publier.
- Un serveur dans un conteneur doit écouter sur `0.0.0.0`, pas sur `127.0.0.1`.
- `.dockerignore` garde des fichiers hors de l'image, et `USER` évite de tourner en administrateur.

Pour pratiquer, faites le lab « Conteneuriser getting-started-app », puis le challenge « Conteneuriser une application inconnue ».

## Questions

```quiz
title: "Ce qui entre dans l'image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Vous ajoutez `.env` au `.dockerignore`, puis vous reconstruisez. L'ancienne image contient-elle encore ce fichier ?"
    answers:
      - "Non, le fichier en est retiré automatiquement"
      - "Oui : une image ne change jamais, et seule la nouvelle en est exempte"
      - "Non, à condition d'utiliser le même tag"
    correct: 2
    explanation: "Une image est immuable. Reconstruire en produit une nouvelle, et l'ancienne garde son contenu tant qu'elle existe."
  - prompt: "Pourquoi placer `USER app` après `RUN pip install` plutôt qu'avant ?"
    answers:
      - "Parce que `USER` doit être la dernière instruction"
      - "Parce que l'installation a besoin des droits d'administrateur, alors que l'application n'en a pas besoin"
      - "Parce que `pip` n'existe pas pour les autres utilisateurs"
    correct: 2
    explanation: "`USER` s'applique à toutes les instructions qui suivent et au démarrage du conteneur. On installe donc d'abord, puis on abandonne les droits."
```
