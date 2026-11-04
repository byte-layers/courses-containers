---
title: "Choisir et sauvegarder"
description: "Volume, bind mount ou tmpfs, et comment sauvegarder puis restaurer un volume"
---

Vous connaissez maintenant les deux outils principaux. Il reste à savoir lequel choisir, et à protéger ce que vous gardez, car un volume peut être perdu comme n'importe quel disque.

## Quel stockage pour quel besoin ?

Un troisième type existe : **tmpfs**, un stockage en mémoire qui disparaît à l'arrêt du conteneur. Il sert aux données temporaires qui ne doivent pas toucher le disque. Il s'active avec `--tmpfs <dossier>`, et la commande `mount` confirme ici son type :

```exec
docker run --rm --tmpfs /cache alpine:3.22 sh -c 'echo temporaire > /cache/x; mount | grep /cache'
```

Voici comment choisir entre les trois :

| | Volume | Bind mount | tmpfs |
|---|---|---|---|
| Où sont les données ? | géré par Docker | un dossier de votre machine, que vous choisissez | en mémoire |
| Survit au conteneur ? | oui | oui | non |
| Rempli par l'image si vide ? | oui | non, il la masque | non |
| Le bon usage | les données d'une base ou d'un service | votre code en développement, un fichier de configuration | des données temporaires ou sensibles |

La règle la plus simple tient en une phrase : **les données appartiennent à un volume, vos fichiers à un bind mount**. Un bind mount rend aussi une application dépendante du dossier d'une machine précise, ce qui convient mal en production.

## Sauvegarder un volume

Docker n'a pas de commande pour sauvegarder un volume, mais il n'en a pas besoin. On lance un conteneur temporaire qui voit à la fois le volume et un dossier de votre machine, puis on archive de l'un vers l'autre avec `tar`, l'outil d'archivage standard. Ce schéma montre le chemin des données :

```
volume layers-l6-data ──► /from (lecture seule) ──► tar ──► /to ──► ~/layers-l6/ sur votre machine
```

Dans cette commande, `czf` crée une archive compressée, et `-C /from .` archive le contenu de ce dossier sans son nom :

```exec
docker run --rm -v layers-l6-data:/from:ro -v "$HOME/layers-l6:/to" alpine:3.22 tar czf /to/sauvegarde.tar.gz -C /from .
tar tzf "$HOME/layers-l6/sauvegarde.tar.gz"
```

Vous lisez `./` et `./note.txt` : la seconde commande a listé le contenu de l'archive. Un simple conteneur et `tar` ont suffi pour sauvegarder le volume.

⚖️ Pour une base de données en service, arrêtez le conteneur avant d'archiver : sinon, des fichiers en cours d'écriture peuvent donner une sauvegarde incohérente. Les bases ont aussi leurs propres outils de sauvegarde, comme `pg_dump` pour PostgreSQL ou `mysqldump` pour MySQL.

```verify
if ! tar tzf "$HOME/layers-l6/sauvegarde.tar.gz" 2>/dev/null | grep -q 'note.txt'; then
  echo "L'archive ~/layers-l6/sauvegarde.tar.gz ne contient pas note.txt. Lancez la commande de cette section."
  exit 1
fi
echo "L'archive contient note.txt."
```

## Restaurer dans un volume neuf

Une sauvegarde qu'on n'a jamais restaurée n'est pas une sauvegarde. Faites le chemin inverse dans un nouveau volume, cette fois avec `xzf`, qui extrait l'archive :

```exec
docker volume create layers-l6-restaure
docker run --rm -v "$HOME/layers-l6:/from:ro" -v layers-l6-restaure:/to alpine:3.22 tar xzf /from/sauvegarde.tar.gz -C /to
docker run --rm -v layers-l6-restaure:/data alpine:3.22 cat /data/note.txt
```

Vous lisez `bonjour` : le contenu du premier volume vit maintenant dans un second, indépendant.

```verify
if ! docker volume inspect layers-l6-restaure >/dev/null 2>&1 || ! docker run --rm -v layers-l6-restaure:/data alpine:3.22 cat /data/note.txt 2>/dev/null | grep -q bonjour; then
  echo "Le volume layers-l6-restaure ne contient pas note.txt. Lancez les commandes de cette section."
  exit 1
fi
echo "La restauration a fonctionné."
```

## Ne rien laisser

Supprimez les deux volumes et votre dossier de travail. Vos autres volumes ne sont pas concernés, et il vaut mieux ne jamais utiliser de commande de nettoyage général sur une machine que vous partagez :

```exec
docker volume rm layers-l6-data layers-l6-restaure
rm -rf "$HOME/layers-l6"
```

```verify
if docker volume inspect layers-l6-data >/dev/null 2>&1 || docker volume inspect layers-l6-restaure >/dev/null 2>&1; then
  echo "Il reste un volume. Lancez le docker volume rm ci-dessus."
  exit 1
fi
if [ -e "$HOME/layers-l6" ]; then
  echo "Le dossier ~/layers-l6 existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Le stockage dans Docker](https://docs.docker.com/engine/storage/) · [Sauvegarder et restaurer un volume](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes) · [tmpfs](https://docs.docker.com/engine/storage/tmpfs/)

## Récap

- Un volume garde les données d'un service, indépendamment de ses conteneurs. Sur un volume neuf, Docker recopie ce que l'image contient à cet endroit.
- Un bind mount montre un dossier de votre machine dans le conteneur, en masquant le contenu de l'image à cet endroit.
- `:ro` limite un accès à la lecture, et `--mount` refuse un chemin absent.
- `docker rm -v` évite les volumes anonymes orphelins, et un volume nommé ne se supprime que par `docker volume rm`.
- Une sauvegarde se fait par un conteneur temporaire et `tar`, et elle se prouve en restaurant.

## Questions

```quiz
title: "Choisir et sauvegarder"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quel stockage pour les fichiers d'une base PostgreSQL en production ?"
    answers:
      - "Un volume"
      - "Un bind mount dans le dossier personnel de l'administrateur"
      - "tmpfs"
    correct: 1
    explanation: "Un volume est géré par Docker, et il survit au remplacement du conteneur. tmpfs perdrait tout à l'arrêt."
  - prompt: "Quel stockage pour le code que vous modifiez pendant le développement ?"
    answers:
      - "Un volume"
      - "Un bind mount"
      - "La couche d'écriture"
    correct: 2
    explanation: "C'est votre dossier, modifié par votre éditeur et vu tout de suite par le conteneur."
  - prompt: "Comment sauvegarder un volume, sachant que Docker n'a pas de commande pour cela ?"
    answers:
      - "En copiant `/var/lib/docker/volumes/` depuis l'explorateur de fichiers"
      - "Avec un conteneur temporaire qui voit le volume et un dossier de votre machine, et qui lance `tar`"
      - "Avec `docker commit`"
    correct: 2
    explanation: "Le conteneur temporaire marche sur toutes les installations de Docker. `docker commit` ne capture pas les volumes."
```
