---
title: "Configurer son image"
description: "ENV, EXPOSE, et la forme à donner à CMD"
---

Votre image fonctionne, mais rien n'indique sur quel port elle écoute ni comment la régler. Ces informations aussi se rangent dans l'image. Cette étape ajoute deux instructions qui n'exécutent rien, car elles enrichissent seulement sa fiche.

## Donner une valeur par défaut avec ENV

`ENV` donne une valeur par défaut à une variable d'environnement, et `EXPOSE` indique le port d'écoute, sur lequel vous reviendrez un peu plus bas. Ajoutez ces deux lignes au Dockerfile de `web`, juste avant `CMD` :

```diff
 COPY app.py .
+ENV GREETING=Salut
+EXPOSE 5000
 CMD ["flask", "run", "--host", "0.0.0.0"]
```

Faites-le dans votre éditeur, ou laissez cette commande réécrire le fichier :

```exec
cat > ~/byte-layers/docker/l2/web/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
ENV GREETING=Salut
EXPOSE 5000
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
```

Reconstruisez sous le tag `1.2`, lancez un conteneur sans aucune option de réglage, et regardez son état :

```exec
docker build -t layers-l2-web:1.2 ~/byte-layers/docker/l2/web
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.2
docker ps
```

Demandez la page. Si `curl` répond par une erreur de connexion, attendez une seconde et relancez.

```exec
curl http://localhost:28320
```

L'application lit bien la valeur de l'image :

```text
Salut depuis Flask
```

```verify
ENVS=$(docker image inspect layers-l2-web:1.2 --format '{{json .Config.Env}}' 2>/dev/null)
case "$ENVS" in
  *GREETING=*) : ;;
  *) echo "L'image layers-l2-web:1.2 ne définit pas GREETING. Vérifiez la ligne ENV et reconstruisez."; exit 1 ;;
esac
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28320) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"Salut depuis Flask"*) : ;;
  *) echo "Le port 28320 ne répond pas « Salut depuis Flask ». Le conteneur layers-l2-web vient-il bien de l'image 1.2 ?"; exit 1 ;;
esac
echo "La valeur par défaut est dans l'image, et l'application la lit."
```

## Remplacer cette valeur avec -e, sans reconstruire

Celui qui lance un conteneur garde la main sur cette valeur, avec l'option `-e` que vous connaissez déjà. Remplacez le conteneur par un autre, depuis la même image, en changeant seulement la variable :

```exec
docker rm -f layers-l2-web
docker run -d --name layers-l2-web -p 28320:5000 -e GREETING=Coucou layers-l2-web:1.2
docker ps
```

Redemandez la page, toujours en attendant une seconde si le serveur démarre encore :

```exec
curl http://localhost:28320
```

La même image répond maintenant autrement :

```text
Coucou depuis Flask
```

```verify
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28320) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *"Coucou depuis Flask"*) : ;;
  *) echo "Le port 28320 ne répond pas « Coucou depuis Flask ». Avez-vous recréé le conteneur avec -e GREETING=Coucou ?"; exit 1 ;;
esac
if [ "$(docker inspect layers-l2-web --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l2-web:1.2" ]; then
  echo "Le conteneur layers-l2-web doit venir de l'image layers-l2-web:1.2, sans reconstruction."
  exit 1
fi
echo "La même image répond avec une autre valeur."
```

Le conteneur a montré ce qu'il fallait, supprimez-le :

```exec
docker rm -f layers-l2-web
```

## Documenter le port avec EXPOSE

Lisez ce que `EXPOSE` a enregistré dans la fiche de l'image. `docker image inspect` lit cette fiche, comme `docker inspect` le fait pour un conteneur, et `--format` n'en extrait qu'un champ :

```exec
docker image inspect layers-l2-web:1.2 --format '{{json .Config.ExposedPorts}}'
```

Vous devez lire le port, tel qu'il a été noté :

```text
{"5000/tcp":{}}
```

Attention à ne pas surestimer `EXPOSE` : c'est une **documentation**, et cette instruction n'ouvre rien. Il faut toujours `-p` pour rendre un port accessible depuis votre machine. Elle reste utile, car elle dit à la personne qui lance votre image où se brancher.

## Choisir la forme exec pour CMD

Vous écrivez `CMD` sous forme de liste depuis le début, avec des crochets et des guillemets. C'est la **forme exec**. Il existe une autre écriture, la **forme shell**, sans crochets, et ce tableau les compare.

| Écriture | Ce que Docker lance | Quand l'utiliser |
|---|---|---|
| `CMD ["flask", "run"]` | directement le programme | par défaut |
| `CMD flask run` | `/bin/sh -c "flask run"`, un shell chargé de lancer le programme | quand il faut un shell, pour enchaîner des commandes ou lire une variable |

Il vaut mieux préférer la forme exec, pour deux raisons. Elle ne dépend pas de la présence d'un shell dans l'image, et `hello-world`, construite sur `scratch`, n'en a aucun. Et elle ne place aucun programme entre Docker et le vôtre : selon les images, un shell intermédiaire peut garder pour lui la demande d'arrêt de `docker stop`, la commande qui arrête un conteneur. Ce n'est pas le cas ici, car le shell d'Alpine se retire au profit de Flask, mais toutes les images ne se comportent pas ainsi.

> **Pour aller plus loin, facultatif : `ENTRYPOINT`.** Cette instruction fixe le programme de l'image. Ce qui suit le nom de l'image dans `docker run` remplace `CMD`, mais s'ajoute à `ENTRYPOINT`. Avec `ENTRYPOINT ["echo", "Bonjour"]` et `CMD ["tout le monde"]`, `docker run image` affiche `Bonjour tout le monde`, et `docker run image Ada` affiche `Bonjour Ada`. On s'en sert pour une image qui se comporte comme un seul programme. Pour une application web comme la vôtre, `CMD` seul suffit.

```ack
Je sais à quoi servent ENV, EXPOSE et la forme exec
```

> 📖 [`ENV`](https://docs.docker.com/reference/dockerfile/#env) · [`EXPOSE`](https://docs.docker.com/reference/dockerfile/#expose) · [`CMD`](https://docs.docker.com/reference/dockerfile/#cmd) · [`ENTRYPOINT`](https://docs.docker.com/reference/dockerfile/#entrypoint)

## Questions

```quiz
title: "Configurer son image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un Dockerfile contient `EXPOSE 5000`, et vous lancez `docker run -d mon-image`. Le port 5000 est-il accessible depuis votre machine ?"
    answers:
      - "Non : `EXPOSE` documente, et c'est `-p` qui publie"
      - "Oui, c'est le rôle de `EXPOSE`"
      - "Oui, mais seulement avec Docker Desktop"
    correct: 1
    explanation: "`EXPOSE` enregistre une information dans l'image, sans rien ouvrir."
  - prompt: "Une image a `ENV MODE=prod`. Comment lancer un conteneur avec `MODE=test` sans reconstruire l'image ?"
    answers:
      - "`docker run -e MODE=test mon-image`"
      - "C'est impossible, une image ne change jamais"
      - "`docker build --env MODE=test`"
    correct: 1
    explanation: "`ENV` donne une valeur par défaut. `-e` la remplace pour ce conteneur, et l'image ne change pas."
  - prompt: "Pourquoi préférer `CMD [\"flask\", \"run\"]` à `CMD flask run` ?"
    answers:
      - "La forme exec ne dépend pas d'un shell, et ne place aucun programme entre Docker et le vôtre"
      - "La forme shell est refusée par `docker build`"
      - "La forme exec construit l'image plus vite"
    correct: 1
    explanation: "Les deux formes se construisent. La forme shell lance `/bin/sh -c`, ce qui suppose un shell dans l'image."
```
