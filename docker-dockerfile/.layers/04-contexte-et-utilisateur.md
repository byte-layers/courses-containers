---
title: "Ce qui entre dans l'image, et qui l'exécute"
description: "COPY . ., .dockerignore et USER"
---

Votre image fonctionne et elle se configure. Il lui reste deux défauts courants, invisibles tant que tout marche : elle peut embarquer des fichiers qui n'ont rien à y faire, et son application tourne en administrateur.

## Copier tout le projet, et voir un mot de passe entrer dans l'image

Jusqu'ici, vous copiez les fichiers un par un. Dès qu'un projet grandit, on écrit plutôt `COPY . .`, qui copie tout le contexte dans le dossier courant de l'image. Comme `pip` a besoin de `requirements.txt`, cette ligne passe avant `RUN` :

```diff
 WORKDIR /app
-COPY requirements.txt .
+COPY . .
 RUN pip install -r requirements.txt
-COPY app.py .
 ENV GREETING=Salut
```

⚖️ Cet ordre est le plus simple à lire, mais il refait l'installation à chaque modification du code. Un prochain cours, « Accélérer un build avec le cache », montre comment l'éviter.

C'est pratique, et cela demande une précaution. Pour la voir, ajoutez au projet un fichier sensible, comme un projet réel en contient souvent, avec un mot de passe fictif, en même temps que ce changement. Un fichier `.env` sert à ranger ce genre de valeur :

```exec
echo 'DB_PASSWORD=pas-dans-l-image' > ~/layers-l2/web/.env
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
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

Tout le dossier est là, y compris le `Dockerfile` et votre fichier sensible :

```text
.env
Dockerfile
app.py
requirements.txt
```

Quiconque récupère cette image peut donc lire votre mot de passe, comme cette commande le prouve :

```exec
docker run --rm layers-l2-web:1.3 cat .env
```

## Exclure des fichiers avec .dockerignore

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

Il ne reste que ce dont l'application a besoin :

```text
app.py
requirements.txt
```

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

⚖️ Un `.dockerignore` protège des oublis, mais ce n'est pas une gestion des secrets : un prochain cours, « Un secret ne va pas dans l'image », y revient. Le correctif ne vaut d'ailleurs que pour les images à venir. La version `1.3` contient toujours le mot de passe, car une image ne change jamais. Dans un vrai projet, il faudrait donc aussi changer ce mot de passe.

## Passer à un utilisateur ordinaire avec USER

Par défaut, un conteneur s'exécute avec l'utilisateur `root`, l'administrateur de Linux. `id -un` affiche le nom de l'utilisateur courant :

```exec
docker run --rm layers-l2-web:1.4 id -un
```

Vous lisez `root`. Si l'application a une faille, l'attaquant dispose de ces droits dans le conteneur, et il vaut mieux lui en laisser le moins possible. L'instruction `USER` change d'utilisateur pour la suite du Dockerfile et pour le démarrage du conteneur. Cet utilisateur doit exister : sur Alpine, `adduser -D app` en crée un, sans mot de passe. Deux lignes s'ajoutent après l'installation :

```diff
 RUN pip install -r requirements.txt
+RUN adduser -D app
+USER app
 ENV GREETING=Salut
```

`USER` vient après l'installation, car `pip install` et `adduser` ont besoin des droits d'administrateur. Faites la modification dans votre éditeur, ou laissez cette commande réécrire le fichier :

```exec
cat > ~/layers-l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
RUN adduser -D app
USER app
ENV GREETING=Salut
EXPOSE 5000
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Reconstruisez, vérifiez l'utilisateur, puis lancez le service et regardez son état :

```exec
docker build -t layers-l2-web:1.5 ~/layers-l2/web
docker run --rm layers-l2-web:1.5 id -un
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.5
docker ps
```

Vous devez lire `app`, puis la ligne du conteneur dans la liste. Demandez la page, en attendant une seconde si le serveur démarre encore :

```exec
curl http://localhost:28320
```

Vous lisez `Salut depuis Flask`. L'application n'écrit aucun fichier, donc ce changement ne la gêne pas. Une application qui écrit dans un dossier appartenant à `root` échouerait, et le lab [Conteneuriser une application pas à pas](https://byte-layers.com/fr/labs/docker-containerize-app) vous fait rencontrer ce cas.

```verify
if [ "$(docker run --rm layers-l2-web:1.5 id -un 2>/dev/null)" != "app" ]; then
  echo "L'image layers-l2-web:1.5 ne tourne pas avec l'utilisateur app. Vérifiez la ligne USER et reconstruisez."
  exit 1
fi
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28320) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"Salut depuis Flask"*) : ;;
  *) echo "Le port 28320 ne répond pas. Lisez : docker logs layers-l2-web"; exit 1 ;;
esac
echo "L'application répond sans être administrateur."
```

## Supprimer ce que ce cours a créé

Tout ce cours vit sous le préfixe `layers-l2-` et dans `~/layers-l2/`. `docker image rm` supprime des images, et il refuse celles qu'un conteneur utilise encore : supprimez donc le conteneur en premier. Vos dossiers partent ensuite avec `rm -rf`. Le dossier `~/layers-l2`, alors vide, peut rester, car les autres contenus de cette partie s'en servent.

```exec
docker rm -f layers-l2-web
docker image rm layers-l2-hello:1.0 layers-l2-hello:base-nue layers-l2-web:1.0 layers-l2-web:1.1 layers-l2-web:1.2 layers-l2-web:1.3 layers-l2-web:1.4 layers-l2-web:1.5
rm -rf ~/layers-l2/hello ~/layers-l2/web
```

```verify
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^layers-l2-(hello|web):')
if [ -n "$left" ]; then
  echo "Il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if docker container inspect layers-l2-web >/dev/null 2>&1; then
  echo "Le conteneur layers-l2-web existe encore."
  exit 1
fi
if [ -e "$HOME/layers-l2/web" ] || [ -e "$HOME/layers-l2/hello" ]; then
  echo "Un dossier de ce cours existe encore dans ~/layers-l2."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files) · [`USER`](https://docs.docker.com/reference/dockerfile/#user) · [Bonnes pratiques d'écriture](https://docs.docker.com/build/building/best-practices/)

## Ce qu'il faut retenir

- Un Dockerfile est une recette : `FROM` choisit la base, `COPY` apporte les fichiers, `RUN` prépare l'image au build et `CMD` dit quoi lancer au démarrage.
- `docker build -t nom:tag dossier` construit l'image, et ce dossier, le contexte, est tout ce que `COPY` peut voir.
- Chaque instruction qui change des fichiers ajoute une couche à l'image.
- `ENV` donne une valeur par défaut que `-e` remplace, et `EXPOSE` documente un port sans le publier.
- Un serveur dans un conteneur doit écouter sur `0.0.0.0`, pas sur `127.0.0.1`.
- `.dockerignore` garde des fichiers hors de l'image, et `USER` évite de tourner en administrateur.

Pour pratiquer, faites le lab [Conteneuriser une application pas à pas](https://byte-layers.com/fr/labs/docker-containerize-app), puis le challenge [Conteneuriser une application inconnue](https://byte-layers.com/fr/challenges/docker-dockerfile-challenge).

## Questions

```quiz
title: "Ce qui entre dans l'image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Vous ajoutez `.env` au `.dockerignore`, puis vous reconstruisez. L'ancienne image contient-elle encore ce fichier ?"
    answers:
      - "Oui : une image ne change jamais, et seule la nouvelle en est exempte"
      - "Non, le fichier en est retiré automatiquement"
      - "Non, à condition d'utiliser le même tag"
    correct: 1
    explanation: "Une image ne change jamais. Reconstruire en produit une nouvelle, et l'ancienne garde son contenu tant qu'elle existe."
  - prompt: "Pourquoi placer `USER app` après `RUN pip install` plutôt qu'avant ?"
    answers:
      - "Parce que `USER` doit être la dernière instruction"
      - "Parce que `pip` n'existe pas pour les autres utilisateurs"
      - "Parce que l'installation a besoin des droits d'administrateur, alors que l'application n'en a pas besoin"
    correct: 3
    explanation: "`USER` s'applique à toutes les instructions qui suivent et au démarrage du conteneur. On installe donc d'abord, puis on abandonne les droits."
```
