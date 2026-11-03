---
title: "Héberger une page dans un conteneur"
description: "Pas à pas : servir une page avec nginx, la modifier, arrêter et relancer le conteneur, puis découvrir ce que la suppression emporte."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 30
introTitle: "Présentation"
requires: "0.3.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Vous allez héberger une page web dans un conteneur, sans rien installer d'autre que Docker. Chaque
étape donne la commande, explique ce qu'elle fait, puis vérifie le résultat.

**Niveau** : débutant. Il suffit de savoir utiliser un terminal. Si le mot « conteneur » est tout neuf pour vous, lisez d'abord « L'image est immuable ».

**Ce qu'il faut** : Docker qui répond à `docker ps`, `curl` (pour demander une page depuis le terminal), et le port **28081** libre. Un **port** est le numéro auquel un service répond sur une machine.

**Si vous êtes bloqué** : toutes les commandes du lab, dans l'ordre, sont dans `solution/run.sh`, à côté du dossier `.layers` de ce cours.

**Si `docker run` échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par
adresse IP. Une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Lancer le serveur

## Démarrer nginx

nginx est un serveur web. Son image officielle contient déjà tout ce qu'il faut : pas d'installation, une seule
commande.

```exec
docker run -d --name layers-l1-page -p 28081:80 nginx:1.30-alpine
```

| Élément | Rôle |
|---|---|
| `-d` | le conteneur tourne en arrière-plan et vous rend la main |
| `--name layers-l1-page` | un nom fixe, pour pouvoir le désigner ensuite |
| `-p 28081:80` | le port 28081 de votre machine mène au port 80 du conteneur |
| `nginx:1.30-alpine` | l'image de départ, à une version précise |

`-p` est donné ici comme une recette, le temps de voir votre page. Le cours « Relier des conteneurs et publier un port » explique ce qu'il fait vraiment.

```verify
if [ "$(docker inspect layers-l1-page --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le conteneur layers-l1-page ne tourne pas. Regardez : docker ps -a"
  exit 1
fi
echo "layers-l1-page tourne."
```

## Voir la page

Demandez la page à votre machine. `curl` la télécharge, `-sS` n'affiche que les erreurs, et `--retry` patiente le temps que le serveur démarre. `grep` ne garde que la ligne du titre :

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28081 | grep '<h1>'
```

Vous devez lire `<h1>Welcome to nginx!</h1>`. Pour la voir dans un navigateur :

| Environnement | Adresse |
|---|---|
| Votre poste | `http://localhost:28081` |
| Lab hébergé | `https://labN-28081.<domaine-du-lab>`, avec `N` le numéro de votre poste, ou l'onglet **PORTS** de VS Code |

```verify
if ! command -v curl >/dev/null 2>&1; then
  echo "curl n'est pas installé sur cette machine."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28081 | grep -q 'Welcome to nginx'; then
  echo "La page ne répond pas sur le port 28081. Vérifiez les ports avec : docker ps"
  exit 1
fi
echo "nginx répond sur le port 28081."
```

# Lire ce qui se passe

## Les logs

nginx écrit chaque requête sur sa sortie standard, et Docker l'enregistre. Envoyez une requête reconnaissable, puis lisez les dernières lignes :

```exec
curl -sS -o /dev/null "http://localhost:28081/?moi=1"
docker logs --tail 3 layers-l1-page
```

Vous devez voir une ligne contenant `"GET /?moi=1 HTTP/1.1" 200`.

```verify
if ! docker logs layers-l1-page 2>/dev/null | grep -q 'moi=1'; then
  echo "Votre requête n'est pas dans les logs. Lancez la commande de cette section."
  exit 1
fi
echo "Votre requête est dans les logs."
```

# Modifier la page

## Écrire dans le conteneur

`docker exec` lance une commande **dans un conteneur qui tourne déjà**. nginx sert ses pages depuis le dossier `/usr/share/nginx/html`. Remplacez la page d'accueil ; `sh -c` est là pour que la redirection `>` s'exécute dans le conteneur, et non sur votre machine :

```exec
docker exec layers-l1-page sh -c 'echo "<h1>Ma page dans un conteneur</h1>" > /usr/share/nginx/html/index.html'
```

Puis redemandez-la :

```exec
curl -s http://localhost:28081
```

```verify
if ! curl -s --max-time 5 http://localhost:28081 | grep -q 'Ma page dans un conteneur'; then
  echo "Le serveur ne renvoie pas encore votre page. Rejouez le docker exec."
  exit 1
fi
echo "nginx sert votre page."
```

## Où est passé ce changement ?

L'image, elle, n'a pas changé : une image ne se modifie jamais. Votre écriture est allée dans la **couche d'écriture** du conteneur, l'espace où il garde ses propres modifications. `docker diff` la montre :

```exec
docker diff layers-l1-page | grep index.html
```

Le `C` veut dire *changed* : ce fichier diffère de celui de l'image.

```ack
Je vois mon fichier dans docker diff
```

# Arrêter, relancer

## La page survit à un arrêt

Arrêtez le conteneur, puis constatez qu'il existe toujours. `docker ps -a` liste aussi les conteneurs arrêtés :

```exec
docker stop layers-l1-page
```

```exec
docker ps -a --filter name=layers-l1-page --format '{{.Names}} : {{.Status}}'
```

Il est `Exited`, mais il est là. Relancez-le, puis redemandez la page :

```exec
docker start layers-l1-page
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28081
```

Votre page est toujours là : **arrêter n'efface pas la couche d'écriture**.

```verify
FIN=$(docker inspect layers-l1-page --format '{{.State.FinishedAt}}' 2>/dev/null)
case "$FIN" in
  ""|0001-01-01*) echo "Le conteneur n'a pas encore été arrêté. Faites le docker stop."; exit 1 ;;
esac
if [ "$(docker inspect layers-l1-page --format '{{.State.Running}}')" != "true" ]; then
  echo "Le conteneur est arrêté. Faites le docker start."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28081 | grep -q 'Ma page dans un conteneur'; then
  echo "Votre page n'est plus servie. Rejouez le docker exec de l'étape précédente."
  exit 1
fi
echo "Arrêté, relancé, et la page est toujours là."
```

# Supprimer, recréer

## Ce que la suppression emporte

Supprimez maintenant le conteneur et recréez-le avec exactement la même commande. `-f` force la suppression d'un conteneur
qui tourne :

```exec
docker rm -f layers-l1-page
```

```exec
docker run -d --name layers-l1-page -p 28081:80 nginx:1.30-alpine
```

Avant de lancer la commande suivante, faites une prévision : que va afficher le serveur ?

```exec
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28081 | grep '<h1>'
```

`Welcome to nginx!` : **votre page a disparu**. La couche d'écriture appartenait à l'ancien conteneur, elle est partie avec lui,
et le nouveau repart de l'image.

C'est le comportement normal d'un conteneur. Le cours « Garder ses données » montre comment garder ce qui doit durer.

```verify
if ! curl -s --max-time 5 http://localhost:28081 | grep -q 'Welcome to nginx'; then
  echo "Le serveur ne renvoie pas la page d'origine. Avez-vous supprimé puis recréé le conteneur ?"
  exit 1
fi
echo "Le nouveau conteneur est reparti de l'image."
```

# Nettoyer

## Ne rien laisser

```exec
docker rm -f layers-l1-page
```

```verify
if docker container inspect layers-l1-page >/dev/null 2>&1; then
  echo "layers-l1-page existe encore."
  exit 1
fi
echo "C'est propre. Vous pouvez essayer le challenge « Faire vivre un conteneur » : il ne vous guidera plus."
```
