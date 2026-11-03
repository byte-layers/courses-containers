---
title: "Observer un conteneur"
description: "ps, logs, top, stats et inspect : savoir ce qu'un conteneur fait et comment il est configuré"
---

Lancez un serveur web à observer. Un **port** est le numéro auquel un service répond sur une machine. `-p 28082:80` rend le port 80 du conteneur accessible sur le port 28082 de votre machine ; le cours « Relier des conteneurs et publier un port » y reviendra.

```exec
docker run -d --name layers-l1-obs -p 28082:80 nginx:1.30-alpine
```

## Qu'est-ce qui tourne ?

```exec
docker ps --filter name=layers-l1-obs
```

Regardez bien la colonne `STATUS`. `Up 3 minutes` : il tourne. `Restarting (1)` : il plante en boucle. Avec `docker ps -a`, vous verrez aussi `Exited (1) 2 minutes ago` : il s'est arrêté, et le code donne le premier indice.

```verify
if [ "$(docker inspect layers-l1-obs --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "layers-l1-obs ne tourne pas. Supprimez-le s'il existe (docker rm -f layers-l1-obs), puis lancez la commande du début de l'étape."
  exit 1
fi
if [ "$(docker port layers-l1-obs 80 2>/dev/null | head -1 | sed 's/.*://')" != "28082" ]; then
  echo "layers-l1-obs ne publie pas le port 28082. Supprimez-le et relancez la commande."
  exit 1
fi
echo "layers-l1-obs tourne, sur le port 28082."
```

## Qu'a-t-il écrit ?

Docker enregistre ce que le processus principal écrit sur sa **sortie standard** (stdout) et sa **sortie d'erreur** (stderr). Provoquez une requête : `curl` demande la page, `-sS` ne garde que les erreurs, `-o /dev/null` jette le contenu.

```exec
curl -sS -o /dev/null http://localhost:28082
docker logs --tail 2 layers-l1-obs
```

| Option | Effet |
|---|---|
| `--tail N` | les N dernières lignes seulement |
| `-f` | suit les nouvelles lignes en direct, jusqu'à `Ctrl-C` |
| `-t` | ajoute l'heure |

Retenez `-f` : c'est lui qu'on utilise pour suivre un service en direct. Une application qui écrit ses logs dans un fichier, à l'intérieur du conteneur, reste invisible pour `docker logs`.

```verify
if ! docker logs layers-l1-obs 2>/dev/null | grep -q 'GET / HTTP'; then
  echo "Aucune requête dans les logs. Relancez le curl."
  exit 1
fi
echo "Votre requête est dans les logs."
```

## Quels processus, quelles ressources ?

`docker top` liste les processus du conteneur, avec les numéros vus de la machine qui l'héberge. `docker exec ... ps` les liste vus de l'intérieur :

```exec
docker top layers-l1-obs
docker exec layers-l1-obs ps
```

Ce sont les mêmes processus, avec d'autres numéros : le conteneur a sa propre numérotation, son **namespace PID**. Le processus principal y est le PID 1.

Et `docker stats` donne la consommation :

```exec
docker stats --no-stream layers-l1-obs
```

```ack
Je sais voir les processus et la consommation
```

## Comment est-il configuré ?

`docker inspect` donne toute la fiche d'un conteneur, en JSON, un format texte de champs imbriqués : près de 250 lignes. En voici le début :

```exec
docker inspect layers-l1-obs | head -20
```

On extrait une valeur avec `--format`, en suivant le chemin du champ : le champ `Status`, rangé dans `State`, s'écrit `.State.Status`.

```exec
docker inspect layers-l1-obs --format '{{.State.Status}}'
docker inspect layers-l1-obs --format '{{json .Config.Cmd}}'
docker inspect layers-l1-obs --format '{{.Image}}'
```

Dans l'ordre : son état, sa commande de démarrage, et l'identifiant de son image. `json` affiche une liste lisible, plutôt que le format interne de Docker.

La commande de démarrage, `.Config.Cmd`, ne ressemble pas à la colonne `COMMAND` de `docker ps` : cette colonne ajoute devant le script que l'image lance d'abord, `/docker-entrypoint.sh`.

Pour garder plusieurs valeurs dans un fichier, mettez-les dans le même `--format`, puis redirigez la sortie avec `>` :

```exec
docker inspect layers-l1-obs --format '{{json .Config.Cmd}} {{.Image}}' > /tmp/layers-l1-fiche.txt
cat /tmp/layers-l1-fiche.txt
```

```verify
if ! grep -q 'nginx' /tmp/layers-l1-fiche.txt 2>/dev/null || ! grep -q 'sha256:' /tmp/layers-l1-fiche.txt; then
  echo "/tmp/layers-l1-fiche.txt ne contient pas les deux valeurs. Lancez la commande ci-dessus."
  exit 1
fi
echo "La commande de démarrage et l'identifiant de l'image sont dans votre fichier."
```

Rangez tout :

```exec
docker rm -f layers-l1-obs
rm -f /tmp/layers-l1-fiche.txt
```

```verify
if docker container inspect layers-l1-obs >/dev/null 2>&1 || [ -e /tmp/layers-l1-fiche.txt ]; then
  echo "Il reste le conteneur ou le fichier. Lancez les commandes ci-dessus."
  exit 1
fi
echo "C'est propre."
```

## Questions

```quiz
title: "Observer un conteneur"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Une application écrit ses logs dans `/var/log/app.log`, et `docker logs` n'affiche rien. Quelle est la bonne correction ?"
    answers:
      - "Lancer `docker logs --tail 1000`"
      - "Faire écrire l'application sur stdout et stderr, ce que Docker capture"
      - "Activer une option du démon"
    correct: 2
    explanation: "Docker ne capture que stdout et stderr du processus principal. C'est aussi ce que lisent les outils de collecte de logs."
  - prompt: "`docker ps` n'affiche rien, mais `docker ps -a` liste huit conteneurs. Qu'est-ce que cela veut dire ?"
    answers:
      - "Le démon Docker dysfonctionne"
      - "Huit conteneurs sont arrêtés, et ils occupent encore le disque"
      - "Les huit conteneurs tournent, mais un filtre les cache"
    correct: 2
    explanation: "Sans `-a`, `docker ps` ne montre que ce qui tourne. Les conteneurs arrêtés gardent leur couche d'écriture et leurs logs."
  - prompt: "Pourquoi `docker top` montre-t-il un processus avec le PID 4821, alors que `docker exec ... ps` le montre avec le PID 1 ?"
    answers:
      - "Ce sont deux processus différents"
      - "Le conteneur a sa propre numérotation des processus : son namespace PID"
      - "`docker top` se trompe"
    correct: 2
    explanation: "C'est le même processus, vu de deux endroits. Dans le conteneur, le processus principal est toujours le PID 1."
  - prompt: "Le statut d'un conteneur affiche `Restarting (1) 5 seconds ago`. Que se passe-t-il ?"
    answers:
      - "Il est mis à jour vers une nouvelle image"
      - "Son processus sort avec le code 1, et une politique de redémarrage le relance en boucle"
      - "Il est en pause"
    correct: 2
    explanation: "C'est une boucle de plantage. Commencez par lire `docker logs` pour savoir pourquoi il sort."
```
