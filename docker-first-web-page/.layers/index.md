---
title: "Héberger une page dans un conteneur"
description: "Pas à pas : servir une page avec nginx, entrer dans le conteneur, la modifier, redémarrer le conteneur, puis découvrir ce que la suppression emporte."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 30
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Vous allez héberger une page web dans un conteneur, sans rien installer d'autre que Docker, puis la modifier et voir ce qu'elle devient quand le conteneur redémarre et quand il est supprimé. Chaque commande est rappelée, et un bouton vérifie le résultat.

**Niveau** : débutant. Ce lab met en pratique ce que vous venez d'apprendre, sans nouvelle option de `docker run`.

**Prérequis** : [Lancer, configurer et observer un conteneur](https://byte-layers.com/fr/skills/docker-run), pour `docker run`, `docker ps`, `-p`, `docker exec -it`, `docker logs` et `docker restart`.

**Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, et le port **28081** de votre machine libre.

# Lancer le serveur

## Démarrer nginx sur le port 28081

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

nginx est un serveur web, un programme qui répond aux demandes de pages, appelées **requêtes**. Son image officielle contient déjà tout ce qu'il faut : pas d'installation, une seule commande.

```exec
docker run -d --name layers-l1-page -p 28081:80 nginx:1.30-alpine
```

| Élément | Rôle |
|---|---|
| `-d` | le conteneur tourne en arrière-plan et vous rend la main |
| `--name layers-l1-page` | un nom fixe, pour pouvoir le désigner ensuite |
| `-p 28081:80` | le port 28081 de votre machine mène au port 80 du conteneur, celui où nginx répond |
| `nginx:1.30-alpine` | l'image de départ : nginx en version 1.30, construit sur Alpine, un Linux minimal |

Vérifiez qu'il tourne avant de lui demander quoi que ce soit :

```exec
docker ps
```

Sur la ligne `layers-l1-page`, vous devez lire `Up` dans `STATUS`, et `0.0.0.0:28081->80/tcp` dans `PORTS`.

```verify
if [ "$(docker inspect layers-l1-page --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  case "$(docker inspect layers-l1-page --format '{{.State.Error}}' 2>/dev/null)" in
    *"port is already allocated"*|*"address already in use"*)
      echo "Le port 28081 est déjà pris sur votre machine. Libérez-le, puis : docker rm layers-l1-page, et relancez la commande."
      exit 1 ;;
  esac
  echo "Le conteneur layers-l1-page ne tourne pas. Pour repartir de zéro : docker rm -f layers-l1-page, puis relancez la commande."
  exit 1
fi
echo "layers-l1-page tourne."
```

## Voir la page dans le terminal et le navigateur

Il tourne, demandez-lui sa page :

```exec
curl http://localhost:28081
```

Vous lisez le code de la page, avec ce titre. Si `curl` répond par une erreur, le serveur n'a pas fini de démarrer : attendez une seconde et relancez.

```text
<h1>Welcome to nginx!</h1>
```

Pour la voir dans un navigateur, ouvrez `http://localhost:28081` si vous travaillez sur votre poste. Si vous suivez ce lab sur un poste hébergé, utilisez plutôt l'onglet **PORTS** de VS Code, qui donne le lien de ce port.

```verify
if ! command -v curl >/dev/null 2>&1; then
  echo "curl n'est pas installé sur cette machine."
  exit 1
fi
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28081 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "La page ne répond pas sur le port 28081. Vérifiez les ports avec : docker ps"
  exit 1
fi
echo "nginx répond sur le port 28081."
```

## Retrouver votre requête dans les logs

nginx note chaque requête, et `docker logs` vous la montre. Envoyez une requête reconnaissable :

```exec
curl "http://localhost:28081/?moi=1"
```

Puis lisez les dernières lignes écrites par le serveur :

```exec
docker logs --tail 3 layers-l1-page
```

Vous devez voir une ligne contenant `"GET /?moi=1 HTTP/1.1" 200`, où `200` est le code de réponse d'une requête réussie.

```verify
if ! docker logs layers-l1-page 2>/dev/null | grep -q 'moi=1'; then
  echo "Votre requête n'est pas dans les logs. Lancez la commande de cette section."
  exit 1
fi
echo "Votre requête est dans les logs."
```

# Modifier la page

## Entrer dans le conteneur pour trouver la page

Cette page, nginx la lit dans un fichier, à l'intérieur du conteneur. Ouvrez un shell dedans pour aller la voir :

```exec
docker exec -it layers-l1-page sh
```

Votre invite affiche `/ #`. nginx sert ses pages depuis le dossier `/usr/share/nginx/html` : tapez ces lignes pour y lister les fichiers, puis pour sortir.

```sh
ls /usr/share/nginx/html
exit
```

`index.html` est la page d'accueil. `50x.html` est la page qu'il affiche en cas d'erreur du serveur. Le conteneur tourne toujours : vous n'avez quitté que le shell.

```ack
J'ai vu index.html dans le conteneur
```

## Remplacer la page d'accueil

Pour changer un seul fichier, inutile de rester dans un shell : `docker exec` sans `-it` lance la commande puis revient. `sh -c` est là pour que la redirection `>` s'exécute dans le conteneur, et non sur votre machine :

```exec
docker exec layers-l1-page sh -c 'echo "<h1>Ma page dans un conteneur</h1>" > /usr/share/nginx/html/index.html'
```

Redemandez ensuite la page pour voir le résultat :

```exec
curl http://localhost:28081
```

Le serveur renvoie votre phrase, sans avoir eu besoin de redémarrer :

```text
<h1>Ma page dans un conteneur</h1>
```

```verify
if ! curl -s --max-time 5 http://localhost:28081 | grep -q 'Ma page dans un conteneur'; then
  echo "Le serveur ne renvoie pas encore votre page. Rejouez le docker exec."
  exit 1
fi
echo "nginx sert votre page."
```

## Voir où est allé ce changement : docker diff

L'image, elle, n'a pas changé. Votre écriture est allée dans la **couche d'écriture** du conteneur, l'espace où il garde ses propres modifications. `docker diff` liste ce qu'elle contient :

```exec
docker diff layers-l1-page
```

La liste est plus longue que prévu, car nginx écrit aussi quelques fichiers en démarrant. `A` veut dire *added*, et `C` veut dire *changed*. Cherchez votre fichier dans la liste :

```text
C /usr/share/nginx/html
C /usr/share/nginx/html/index.html
```

```ack
Je vois mon fichier dans docker diff
```

# Arrêter, redémarrer, supprimer

## La page survit à un arrêt et à un redémarrage

Arrêtez le conteneur, puis constatez qu'il existe toujours avec `-a` :

```exec
docker stop layers-l1-page
docker ps -a
```

Il est `Exited`, mais il est là. Relancez-le :

```exec
docker start layers-l1-page
```

Redemandez ensuite la page. Si `curl` répond par une erreur, attendez une seconde et relancez.

```exec
curl http://localhost:28081
```

Votre phrase est toujours là : **arrêter n'efface pas la couche d'écriture**. `docker restart`, qui enchaîne l'arrêt et le démarrage, donne le même résultat :

```exec
docker restart layers-l1-page
```

Le serveur a redémarré, et sa page doit être encore la vôtre :

```exec
curl http://localhost:28081
```

```verify
FIN=$(docker inspect layers-l1-page --format '{{.State.FinishedAt}}' 2>/dev/null)
case "$FIN" in
  ""|0001-01-01*) echo "Le conteneur n'a pas encore été arrêté. Faites le docker stop."; exit 1 ;;
esac
if [ "$(docker inspect layers-l1-page --format '{{.State.Running}}')" != "true" ]; then
  echo "Le conteneur est arrêté. Faites le docker start."
  exit 1
fi
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28081 | grep -q 'Ma page dans un conteneur'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "Votre page n'est plus servie. Rejouez le docker exec de l'étape précédente."
  exit 1
fi
echo "Arrêté, relancé, et la page est toujours là."
```

## La page disparaît quand on supprime le conteneur

Supprimez maintenant le conteneur et recréez-le avec exactement la même commande. `-f` force la suppression d'un conteneur qui tourne :

```exec
docker rm -f layers-l1-page
docker run -d --name layers-l1-page -p 28081:80 nginx:1.30-alpine
```

Avant de lancer la commande suivante, faites une prévision : que va afficher le serveur ? Si `curl` répond par une erreur, attendez une seconde et relancez.

```exec
curl http://localhost:28081
```

Vous lisez de nouveau `Welcome to nginx!` : **votre page a disparu**. La couche d'écriture appartenait à l'ancien conteneur, elle est partie avec lui, et le nouveau repart de l'image. C'est le comportement normal d'un conteneur, pas un défaut.

⚖️ Écrire une page avec `docker exec` a servi à observer tout cela, mais ce n'est pas ainsi qu'on héberge un site, puisque cette page ne survit pas au conteneur. Deux prochains cours donnent la bonne façon : le premier met la page dans une image, avec un Dockerfile, et « Garder ses données » conserve ce qui doit durer.

```verify
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28081 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "Le serveur ne renvoie pas la page d'origine. Avez-vous supprimé puis recréé le conteneur ?"
  exit 1
fi
echo "Le nouveau conteneur est reparti de l'image."
```

# Nettoyer et récapituler

## Supprimer le conteneur

Ce conteneur ne sert plus : supprimez-le pour libérer le port.

```exec
docker rm -f layers-l1-page
```

```verify
if docker container inspect layers-l1-page >/dev/null 2>&1; then
  echo "layers-l1-page existe encore."
  exit 1
fi
echo "C'est propre."
```

## Récap

- Une seule commande suffit pour faire tourner un serveur web dans un conteneur : `docker run`, puis `docker ps` pour voir s'il tourne, puis `curl` pour voir s'il répond.
- `docker logs` montre ce qu'il fait, et `docker exec` agit à l'intérieur.
- Arrêter ou redémarrer un conteneur garde sa couche d'écriture ; le supprimer l'efface.

> 📖 [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/) · [`docker exec`](https://docs.docker.com/reference/cli/docker/container/exec/) · [`docker restart`](https://docs.docker.com/reference/cli/docker/container/restart/) · [`docker diff`](https://docs.docker.com/reference/cli/docker/container/diff/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/)

Deux lectures expliquent ce que vous venez de voir : [L'image est immuable](https://byte-layers.com/fr/bits/image-immutable) et [Un conteneur est un processus isolé](https://byte-layers.com/fr/bits/container-is-a-process). Pour vous tester ensuite sans guide, faites le challenge [Faire vivre un conteneur, sans guide](https://byte-layers.com/fr/challenges/docker-run-challenge).
