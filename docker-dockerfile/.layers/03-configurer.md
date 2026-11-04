---
title: "Configurer son image"
description: "ENV, EXPOSE, et la forme de CMD et ENTRYPOINT"
---

Votre image fonctionne, mais rien n'indique sur quel port elle écoute ni comment la régler. Ces informations aussi se rangent dans l'image. Cette étape ajoute trois instructions qui n'exécutent rien : elles enrichissent sa configuration.

## Une valeur par défaut, et un port documenté

`ENV` donne une valeur par défaut à une variable d'environnement, et `EXPOSE` indique le port sur lequel l'application écoute. Ajoutez-les au Dockerfile :

```exec
cat > ~/layers-l2/web/Dockerfile <<'EOF'
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

Reconstruisez sous le tag `1.2`, puis lisez ce qui a été enregistré dans la fiche de l'image :

```exec
docker build -t layers-l2-web:1.2 ~/layers-l2/web
docker image inspect layers-l2-web:1.2 --format '{{json .Config.ExposedPorts}}'
```

Vous devez lire `{"5000/tcp":{}}`.

Attention à ne pas surestimer `EXPOSE` : c'est une **documentation**, et cette instruction n'ouvre rien. Il faut toujours `-p` pour rendre un port accessible depuis votre machine. Elle reste utile, car elle dit à la personne qui lance votre image où se brancher.

`ENV` agit réellement, lui. Lancez un conteneur sans option, puis un second qui remplace la valeur avec `-e`, l'option que vous connaissez déjà. Ce second conteneur est lancé à l'avant-plan, et ce que vous écrivez après le nom de l'image remplace le `CMD` de l'image. Il affiche donc sa variable et s'arrête. `sh -c` fait lire la variable par le shell du conteneur, et les apostrophes empêchent celui de votre machine de le faire à sa place :

```exec
docker run -d --name layers-l2-web -p 28320:5000 layers-l2-web:1.2
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28320
docker run --rm -e GREETING=Coucou layers-l2-web:1.2 sh -c 'echo $GREETING'
```

La page dit `Salut depuis Flask`, et la dernière ligne dit `Coucou`. L'image fournit donc une valeur par défaut, et celui qui lance le conteneur garde la main.

```verify
ENVS=$(docker image inspect layers-l2-web:1.2 --format '{{json .Config.Env}}' 2>/dev/null)
case "$ENVS" in
  *GREETING=*) : ;;
  *) echo "L'image layers-l2-web:1.2 ne définit pas GREETING. Vérifiez la ligne ENV et reconstruisez."; exit 1 ;;
esac
if ! curl -s --max-time 5 http://localhost:28320 | grep -q 'Salut depuis Flask'; then
  echo "Le port 28320 ne répond pas « Salut depuis Flask ». Le conteneur layers-l2-web vient-il bien de l'image 1.2 ?"
  exit 1
fi
echo "La valeur par défaut est dans l'image, et l'application la lit."
```

Le conteneur a montré ce qu'il fallait, supprimez-le :

```exec
docker rm -f layers-l2-web
```

## Les deux écritures de CMD

Vous écrivez `CMD` sous forme de liste depuis le début, avec des crochets et des guillemets. C'est la **forme exec**. Il existe une autre écriture, la **forme shell**, sans crochets : `CMD flask run --host 0.0.0.0`. Le tableau suivant les compare.

| Écriture | Ce que Docker lance | Quand l'utiliser |
|---|---|---|
| `CMD ["flask", "run"]` | directement le programme | par défaut |
| `CMD flask run` | `/bin/sh -c "flask run"`, un shell qui lance le programme | quand il faut un shell, pour enchaîner ou utiliser une variable |

Il vaut mieux préférer la forme exec. Elle ne dépend pas de la présence d'un shell dans l'image, et le programme reçoit directement les signaux envoyés par `docker stop`. Le serveur de cette application n'en a pas besoin aujourd'hui, mais c'est une bonne habitude.

## CMD et ENTRYPOINT

Une dernière instruction fixe le programme de l'image : `ENTRYPOINT`. Vous venez de voir que ce qui suit le nom de l'image dans `docker run` remplace `CMD`. Avec `ENTRYPOINT`, ce qui est écrit après s'ajoute à ce programme. Essayez sur une petite image :

```exec
mkdir -p ~/layers-l2/greet
cat > ~/layers-l2/greet/Dockerfile <<'EOF'
FROM alpine:3.22
ENTRYPOINT ["echo", "Bonjour"]
CMD ["tout le monde"]
EOF
```

Construisez-la, puis lancez-la sans argument et avec un argument. `docker build -q` n'affiche que l'identifiant de l'image :

```exec
docker build -q -t layers-l2-greet:1.0 ~/layers-l2/greet
docker run --rm layers-l2-greet:1.0
docker run --rm layers-l2-greet:1.0 Ada
```

La première commande affiche `Bonjour tout le monde` et la seconde `Bonjour Ada`. `ENTRYPOINT` reste en place, et `CMD` fournit des arguments par défaut que l'on peut remplacer. Ce tableau résume le choix à faire.

| Besoin | Instruction |
|---|---|
| une commande de démarrage facile à remplacer, comme `sh` pour aller voir dedans | `CMD` seul |
| une image qui se comporte comme un seul programme, avec des arguments | `ENTRYPOINT`, et `CMD` pour les arguments par défaut |

Pour une application web comme la vôtre, `CMD` seul suffit. Il reste possible de remplacer `ENTRYPOINT`, mais il faut le demander explicitement avec l'option `--entrypoint` de `docker run`.

```verify
OUT=$(docker run --rm layers-l2-greet:1.0 Ada 2>/dev/null)
if [ "$OUT" != "Bonjour Ada" ]; then
  echo "L'image layers-l2-greet:1.0 devrait afficher « Bonjour Ada », et elle affiche : ${OUT:-rien}."
  exit 1
fi
OUT=$(docker run --rm layers-l2-greet:1.0 2>/dev/null)
if [ "$OUT" != "Bonjour tout le monde" ]; then
  echo "Sans argument, l'image devrait afficher « Bonjour tout le monde », et elle affiche : ${OUT:-rien}."
  exit 1
fi
echo "ENTRYPOINT reste, CMD se remplace."
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
      - "Oui, c'est le rôle de `EXPOSE`"
      - "Non : `EXPOSE` documente, et c'est `-p` qui publie"
      - "Oui, mais seulement avec Docker Desktop"
    correct: 2
    explanation: "`EXPOSE` enregistre une information dans l'image, sans rien ouvrir."
  - prompt: "Une image a `ENV MODE=prod`. Comment lancer un conteneur avec `MODE=test` sans reconstruire l'image ?"
    answers:
      - "`docker run -e MODE=test mon-image`"
      - "C'est impossible, l'image est immuable"
      - "`docker build --env MODE=test`"
    correct: 1
    explanation: "`ENV` donne une valeur par défaut. `-e` la remplace pour ce conteneur, et l'image ne change pas."
  - prompt: "Une image a `ENTRYPOINT [\"echo\", \"Salut\"]` et `CMD [\"Ada\"]`. Qu'affiche `docker run mon-image Linus` ?"
    answers:
      - "`Linus`"
      - "`Salut Ada`"
      - "`Salut Linus`"
    correct: 3
    explanation: "L'argument remplace `CMD`, et il s'ajoute à `ENTRYPOINT`."
```
