---
title: "Créer un réseau"
description: "docker network create, la résolution de noms, les alias, et le bon numéro de port"
---

Le réseau par défaut ne sait pas résoudre les noms. Un réseau que vous créez, lui, le sait, et c'est la façon normale de relier des conteneurs. On l'appelle un réseau **bridge défini par l'utilisateur** : même pilote, mais avec un serveur de noms en plus.

## Créer le réseau

`docker network create` prend un nom, et le pilote `bridge` est celui par défaut. Créez le réseau, puis relisez sa fiche pour voir le bloc d'adresses qu'il a reçu, appelé **sous-réseau**. `.IPAM.Config` est le champ de la fiche qui le contient :

```exec
docker network create layers-l5-net
docker network inspect layers-l5-net --format '{{.Driver}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Vous lisez `bridge`, suivi d'un bloc comme `172.20.0.0/16`, où `/16` indique la taille du bloc : tous les conteneurs de ce réseau recevront une adresse dedans.

```verify
if [ "$(docker network inspect layers-l5-net --format '{{.Driver}}' 2>/dev/null)" != "bridge" ]; then
  echo "Le réseau layers-l5-net n'existe pas, ou n'utilise pas le pilote bridge. Lancez la commande de cette section."
  exit 1
fi
echo "Le réseau layers-l5-net existe."
```

## Se joindre par le nom

L'option `--network` branche un conteneur sur ce réseau dès sa création. Lancez un serveur web, sans publier de port, puis demandez-lui sa page depuis un second conteneur placé sur le même réseau, en utilisant son **nom** :

```exec
docker run -d --name layers-l5-web --network layers-l5-net nginx:1.30-alpine
sleep 2
docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://layers-l5-web | grep '<h1>'
```

`sleep 2` laisse à nginx le temps de démarrer. `wget` demande une page, comme `curl`, et il est déjà présent dans Alpine : `-qO-` affiche la page sans autre message, et `-T 5` abandonne après 5 secondes.

Vous lisez `<h1>Welcome to nginx!</h1>`. Comment le nom a-t-il été trouvé ? Chaque conteneur de ce réseau utilise un serveur de noms intégré à Docker, à l'adresse `127.0.0.11`, que Docker intercepte dans le conteneur. Vérifiez-le dans le fichier `/etc/resolv.conf`, celui où Linux note son serveur de noms. Vous y lirez `nameserver 127.0.0.11` :

```exec
docker run --rm --network layers-l5-net alpine:3.22 cat /etc/resolv.conf
```

```verify
if [ "$(docker inspect layers-l5-web --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l5-web ne tourne pas. Supprimez-le s'il existe (docker rm -f layers-l5-web), puis relancez la commande de cette section."
  exit 1
fi
if [ "$(docker inspect layers-l5-web --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}}{{end}}')" != "layers-l5-net" ]; then
  echo "layers-l5-web n'est pas sur le réseau layers-l5-net. Recréez-le avec --network layers-l5-net."
  exit 1
fi
if ! docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://layers-l5-web 2>/dev/null | grep -q 'Welcome to nginx'; then
  echo "Le nom layers-l5-web ne répond pas sur le réseau. Regardez : docker logs layers-l5-web"
  exit 1
fi
echo "Sur layers-l5-net, le nom layers-l5-web mène à nginx."
```

## Quel port demander ?

Sur un réseau, un conteneur en joint un autre directement. Il demande donc le **port du conteneur**, pas celui publié sur l'hôte, qui n'existe que sur l'hôte. Vérifiez-le en publiant ce même serveur. Une publication ne s'ajoute pas à un conteneur existant : il faut le recréer. Ensuite, demandez le port publié depuis le réseau :

```exec
docker rm -f layers-l5-web
docker run -d --name layers-l5-web --network layers-l5-net -p 28352:80 nginx:1.30-alpine
sleep 2
docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://layers-l5-web:28352
```

Vous lisez `Connection refused`. Le conteneur n'écoute en effet que sur son port 80. Le même serveur répond donc sur deux chemins différents :

| Qui demande | Adresse à utiliser |
|---|---|
| l'hôte, ou un navigateur sur l'hôte | `localhost:28352`, le port publié |
| un conteneur du même réseau | `layers-l5-web:80`, le nom et le port du conteneur |

Confirmez les deux, chacun depuis sa place. `--retry` laisse à nginx le temps de démarrer :

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28352 | grep '<h1>'
docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://layers-l5-web:80 | grep '<h1>'
```

```verify
if ! docker port layers-l5-web 80 2>/dev/null | grep -q ':28352$'; then
  echo "layers-l5-web n'est pas publié sur le port 28352. Recréez-le avec la commande de cette section."
  exit 1
fi
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28352 | grep -q 'Welcome to nginx'; then
  echo "Le port 28352 ne répond pas depuis l'hôte."
  exit 1
fi
if ! docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://layers-l5-web:80 2>/dev/null | grep -q 'Welcome to nginx'; then
  echo "layers-l5-web:80 ne répond pas sur le réseau."
  exit 1
fi
echo "Le même serveur répond sur le port publié et sur le réseau."
```

## Donner un autre nom : l'alias

Le nom d'un conteneur est unique, et une application préfère souvent un nom générique comme `db` ou `cache`, qui ne change pas quand on remplace le conteneur. C'est le rôle de `--network-alias`, qui ajoute un nom valable sur ce réseau uniquement. Lancez un serveur portant l'alias `site`, puis joignez-le par ce nom :

```exec
docker run -d --name layers-l5-web2 --network layers-l5-net --network-alias site nginx:1.30-alpine
sleep 2
docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://site | grep '<h1>'
```

Vous lisez encore le titre de nginx. Si vous recréez ce conteneur plus tard avec le même alias, ceux qui l'appellent `site` n'auront rien à changer.

```verify
if ! docker inspect layers-l5-web2 --format '{{range .NetworkSettings.Networks}}{{.Aliases}}{{end}}' 2>/dev/null | grep -qw site; then
  echo "layers-l5-web2 n'a pas l'alias site. Recréez-le avec --network-alias site."
  exit 1
fi
if ! docker run --rm --network layers-l5-net alpine:3.22 wget -qO- -T 5 http://site 2>/dev/null | grep -q 'Welcome to nginx'; then
  echo "Le nom site ne répond pas sur layers-l5-net. Regardez : docker logs layers-l5-web2"
  exit 1
fi
echo "L'alias site mène à layers-l5-web2."
```

## Ranger

Un réseau occupé ne peut pas être supprimé. Essayez de le supprimer tout de suite, pour lire l'erreur :

```exec
docker network rm layers-l5-net
```

Le message contient `has active endpoints` : des conteneurs y sont encore branchés. Supprimez-les d'abord, puis le réseau :

```exec
docker rm -f layers-l5-web layers-l5-web2
docker network rm layers-l5-net
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(web|web2)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
if docker network inspect layers-l5-net >/dev/null 2>&1; then
  echo "Le réseau layers-l5-net existe encore. Lancez le docker network rm ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker network create`](https://docs.docker.com/reference/cli/docker/network/create/) · [Le pilote bridge et ses différences avec le réseau par défaut](https://docs.docker.com/engine/network/drivers/bridge/) · [`docker network`](https://docs.docker.com/reference/cli/docker/network/)

## Questions

```quiz
title: "Créer un réseau"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quelle différence y a-t-il entre le réseau `bridge` par défaut et un réseau créé avec `docker network create` ?"
    answers:
      - "Le second résout les noms des conteneurs"
      - "Le second est le seul à donner des adresses IP"
      - "Le second relie plusieurs machines"
    correct: 1
    explanation: "Ils utilisent le même pilote. Le réseau créé apporte le serveur de noms intégré, à l'adresse `127.0.0.11`."
  - prompt: "`web` est publié avec `-p 8080:80`. Un autre conteneur du même réseau veut sa page. Quelle adresse doit-il demander ?"
    answers:
      - "`localhost:8080`"
      - "`web:8080`"
      - "`web:80`"
    correct: 3
    explanation: "Sur le réseau, on demande le port du conteneur. Le 8080 n'existe que sur l'hôte, et `localhost` désignerait le conteneur qui pose la question."
  - prompt: "À quoi sert `--network-alias db` ?"
    answers:
      - "À renommer le conteneur"
      - "À ajouter le nom `db`, valable sur ce réseau, qui peut survivre au remplacement du conteneur"
      - "À créer un réseau appelé `db`"
    correct: 2
    explanation: "L'alias n'existe que sur le réseau où il est déclaré, et il s'ajoute au nom du conteneur."
  - prompt: "`docker network rm` répond `has active endpoints`. Que faut-il faire ?"
    answers:
      - "Redémarrer Docker"
      - "Supprimer ou débrancher d'abord les conteneurs de ce réseau"
      - "Recréer le réseau avec le même nom"
    correct: 2
    explanation: "Un réseau occupé ne se supprime pas. Il faut d'abord libérer les conteneurs."
```
