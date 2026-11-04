---
title: "Un secret ne va pas dans l'image"
description: "Ce qui entre dans une image y reste, même effacé plus tard. Où ranger un mot de passe, et pourquoi."
tags:
  - bit
  - docker
  - containers
difficulty: beginner
duration: 15
requires: "0.4.0"
---

# Un secret ne va pas dans l'image

**Pour qui ?** Pour vous, si vous savez écrire un `Dockerfile` et construire une image, ce qu'enseigne « Écrire le Dockerfile d'une application ». Lisez ce texte avant les autres contenus de cette partie : ils s'appuient dessus.

Un **secret** est une valeur qui donne un accès : un mot de passe, une clé d'API, un jeton. Une image, elle, est faite pour circuler : on la pousse dans un registre, d'autres la tirent, elle reste en cache sur des serveurs. Et comme le montre « L'image est immuable », elle ne change plus une fois construite. Tout ce que vous y mettez part donc avec elle, pour toujours. Cela a l'air évident, mais le secret entre souvent par des chemins moins visibles : voici les deux plus courants.

## Le constater

Ce tableau rappelle ce qui sert ici et donne ce qui n'a pas encore été vu.

| Élément | Rôle |
|---|---|
| `docker build -t nom .` | construit une image à partir du `Dockerfile` du dossier |
| `docker inspect` | affiche la fiche d'une image ou d'un conteneur ; `--format` en extrait une partie |
| `docker save` | écrit une image sous forme d'archive `tar`, couches comprises |
| `docker history` | liste les couches d'une image et l'instruction qui a créé chacune |

Préparez un dossier, avec un faux secret dans un fichier :

```exec
mkdir -p ~/layers-l8/secret
printf 'faux-jeton-1234\n' > ~/layers-l8/secret/token.txt
```

### Par une variable d'environnement

`ENV` a l'air de fixer une simple configuration. Écrivez ce `Dockerfile`, et construisez l'image. `cat > fichier <<'EOF'` écrit dans le fichier tout ce qui suit, jusqu'à la ligne `EOF`, et `-q` n'affiche de la construction que l'identifiant de l'image :

```exec
cat > ~/layers-l8/secret/Dockerfile <<'EOF'
FROM alpine:3.22
ENV API_TOKEN=faux-jeton-1234
EOF
cd ~/layers-l8/secret && docker build -q -t layers-l8-secret-env .
```

Sans démarrer de conteneur, n'importe qui disposant de l'image lit la valeur dans sa fiche :

```exec
docker inspect layers-l8-secret-env --format '{{.Config.Env}}'
```

Vous lisez `API_TOKEN=faux-jeton-1234` à côté du `PATH`.

### Par un fichier effacé ensuite

Le second réflexe est de copier le fichier, de s'en servir, puis de l'effacer. Dans ce `Dockerfile`, `wc -c` compte les octets du fichier et joue le rôle d'une étape qui aurait besoin du secret, comme une installation de dépendances privées :

```exec
cat > ~/layers-l8/secret/Dockerfile <<'EOF'
FROM alpine:3.22
COPY token.txt /tmp/token.txt
RUN wc -c /tmp/token.txt && rm /tmp/token.txt
EOF
cd ~/layers-l8/secret && docker build -q -t layers-l8-secret-rm .
```

Dans un conteneur issu de cette image, le fichier a bien disparu :

```exec
docker run --rm layers-l8-secret-rm cat /tmp/token.txt
```

Vous lisez `No such file or directory`. Pourtant, chaque instruction d'un `Dockerfile` crée une **couche**, et une couche ne se modifie plus : `rm` n'efface rien, il ajoute une couche qui masque le fichier. L'historique le montre, avec une couche `COPY` qui garde son contenu :

```exec
docker history --format '{{.Size}}  {{.CreatedBy}}' layers-l8-secret-rm
```

Il suffit alors d'ouvrir l'image comme une archive. Cette commande envoie l'archive à un conteneur jetable, dont `-i` ouvre l'entrée. Il la décompresse dans `/tmp`, puis cherche le fichier dans chaque couche, rangée dans `blobs/sha256`, et `tar -xOf` affiche son contenu :

```exec
docker save layers-l8-secret-rm | docker run --rm -i alpine:3.22 sh -c 'tar -x -C /tmp; cd /tmp/blobs/sha256; for b in *; do tar -xOf "$b" tmp/token.txt 2>/dev/null; done'
```

`faux-jeton-1234` s'affiche : le secret « effacé » est toujours dans l'image.

## Où le mettre, alors ?

Un secret se donne au conteneur **quand il démarre**, jamais à l'image quand on la construit. Voici les solutions, de la plus simple à la plus sûre :

| Solution | Où le secret se voit | Pour quoi |
|---|---|---|
| dans l'image, par `ENV` ou `COPY` | partout où l'image circule | jamais |
| `docker run -e`, ou `environment:` dans Compose | dans `docker inspect` et l'environnement du processus | un essai sur votre poste |
| un fichier monté dans le conteneur, lu par l'application | dans le conteneur, à cet endroit seulement | un serveur |
| un gestionnaire de secrets, comme HashiCorp Vault | selon les droits qu'il donne | une équipe, plusieurs serveurs |

La variable d'environnement au démarrage est déjà bien mieux que l'image, mais reste visible de quiconque peut interroger Docker. Comparez avec un fichier monté. `-v fichier:chemin:ro` le place dans le conteneur, en lecture seule, et la commande affiche ensuite l'environnement du conteneur :

```exec
docker run -d --name layers-l8-secret-run -v ~/layers-l8/secret/token.txt:/run/secrets/token:ro alpine:3.22 sleep 60
docker exec layers-l8-secret-run cat /run/secrets/token
docker inspect layers-l8-secret-run --format '{{.Config.Env}}'
```

Le programme lit la valeur dans `/run/secrets/token`, et la fiche du conteneur n'en dit rien. C'est aussi pour cela que tant d'images officielles acceptent une variable finissant par `_FILE`, comme `MYSQL_PASSWORD_FILE`, qui désigne un fichier au lieu de contenir la valeur.

Si la **construction** elle-même a besoin du secret, pour télécharger une dépendance privée par exemple, BuildKit, le moteur de construction de Docker, sait le prêter à une seule instruction `RUN`, sans l'écrire dans aucune couche. Le secret est présent le temps de cette instruction, à l'adresse `/run/secrets/<id>` :

```exec
cat > ~/layers-l8/secret/Dockerfile <<'EOF'
FROM alpine:3.22
RUN --mount=type=secret,id=token wc -c /run/secrets/token
EOF
cd ~/layers-l8/secret && docker build -q --secret id=token,src=token.txt -t layers-l8-secret-mount .
docker save layers-l8-secret-mount | docker run --rm -i alpine:3.22 sh -c 'tar -x -C /tmp; cd /tmp/blobs/sha256; for b in *; do tar -xOf "$b" run/secrets/token 2>/dev/null; done; echo "fin de la recherche"'
```

Seul `fin de la recherche` s'affiche : aucune couche ne contient le fichier.

Il reste à ranger ce que vous avez créé :

```exec
docker rm -f layers-l8-secret-run
docker rmi layers-l8-secret-env layers-l8-secret-rm layers-l8-secret-mount
rm -rf ~/layers-l8/secret
```

Deux habitudes complètent tout cela. Ne versionnez jamais un fichier de secret : ajoutez-le à `.gitignore`. Et ajoutez-le aussi à `.dockerignore`, sans quoi un `COPY . .` l'embarque sans que vous l'ayez demandé. Si un vrai secret a fini dans une image publiée, le retirer ne suffit plus, d'autres ont pu la tirer : changez-le.

> 📖 [Secrets à la construction](https://docs.docker.com/build/building/secrets/) · [`docker save`](https://docs.docker.com/reference/cli/docker/image/save/) · [`docker history`](https://docs.docker.com/reference/cli/docker/image/history/) · [Les secrets dans Compose](https://docs.docker.com/compose/how-tos/use-secrets/)

## Ce qu'il faut retenir

- Tout ce qui entre dans une image y reste, même si une instruction suivante l'efface, car une couche ne se modifie plus.
- Un secret se donne au démarrage du conteneur, de préférence comme un fichier monté.
- Si la construction en a besoin, `RUN --mount=type=secret` le prête sans l'écrire dans une couche.
- Un secret qui a fui se change.

```quiz
prompt: "Un Dockerfile fait `COPY cle.pem /tmp/` puis `RUN installer.sh && rm /tmp/cle.pem`. La clé est-elle dans l'image ?"
answers:
  - "Non, elle a été effacée avant la fin de la construction"
  - "Oui, elle reste dans la couche créée par `COPY`, et s'en extrait avec `docker save`"
  - "Oui, mais seul un administrateur du registre peut la lire"
correct: 2
explanation: |
  `rm` crée une couche de plus qui masque le fichier, sans toucher à la précédente. Toute personne qui tire l'image
  peut ouvrir ses couches.
```

```ack
J'ai compris
```
