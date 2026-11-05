---
title: "Lancer un registre local"
description: "Un registre privé dans un conteneur, et son API"
---

Pour publier, il faut un registre où l'on a le droit d'écrire. Sur Docker Hub, il faudrait un compte. Or un registre n'est qu'un logiciel : son image officielle s'appelle `registry`, et il suffit de la lancer pour disposer du vôtre, sans compte, sur votre machine. Les gestes de publication sont les mêmes qu'avec un registre public, et vous ne risquez pas de publier quoi que ce soit par erreur.

## Démarrer le registre dans un conteneur

Le registre écoute sur le port 5000 du conteneur. Lancez-le avec la même forme de `docker run` que d'habitude, en publiant ce port sur le port 28340 de votre machine, puis regardez son état :

```exec
docker run -d --name layers-l4-registry -p 28340:5000 registry:3
docker ps
```

Sur la ligne de `layers-l4-registry`, la colonne `STATUS` doit commencer par `Up`.

```verify
if [ "$(docker inspect layers-l4-registry --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le conteneur layers-l4-registry ne tourne pas. Pour repartir de zéro : docker rm -fv layers-l4-registry (-f force la suppression, -v supprime aussi ses données), puis relancez la commande."
  exit 1
fi
echo "Le registre tourne."
```

## Interroger le registre avec curl

Un registre s'utilise à travers une API, c'est-à-dire des adresses web qui répondent à des programmes. Docker s'en sert à chaque `pull` et à chaque `push`, et vous pouvez l'interroger vous-même avec `curl`. Commencez par le point d'entrée `/v2/`, le nom de la version de cette API. `-i` affiche aussi l'en-tête de la réponse, où se lit le code de résultat. Si `curl` répond par une erreur de connexion, le registre démarrait encore : attendez une seconde et relancez.

```exec
curl -i http://localhost:28340/v2/
```

Vous devez lire ceci, entre autres lignes d'en-tête :

```text
HTTP/1.1 200 OK
Docker-Distribution-Api-Version: registry/2.0

{}
```

`200 OK` veut dire que le registre répond et n'exige aucun mot de passe, et le corps de la réponse se réduit à `{}`, ce qui est normal. Demandez ensuite la liste de ce qu'il contient :

```exec
curl http://localhost:28340/v2/_catalog
```

Le registre n'a encore aucun dépôt, et c'est l'étape suivante qui va le remplir :

```text
{"repositories":[]}
```

```verify
OUT=""
for i in 1 2 3 4 5; do
  OUT=$(curl -s --max-time 2 http://localhost:28340/v2/_catalog) && [ -n "$OUT" ] && break
  sleep 1
done
case "$OUT" in
  *repositories*) : ;;
  *) echo "Le registre ne répond pas sur le port 28340. Vérifiez les ports avec : docker ps"; exit 1 ;;
esac
echo "Le registre répond sur le port 28340."
```

## Savoir pourquoi ce registre ne convient qu'à votre machine

Votre registre parle en HTTP, sans chiffrement ni mot de passe. Docker l'accepte ici parce que l'adresse est `localhost`, qu'il considère comme sûre : pour toute autre adresse, il exige du HTTPS et refuse de publier.

⚖️ C'est un raccourci pour apprendre, à ne pas reproduire tel quel : un registre partagé par une équipe se met derrière HTTPS, avec une authentification.

```ack
J'ai compris que ce registre ne convient qu'à ma machine
```

> 📖 [Le registre sur Docker Hub](https://hub.docker.com/_/registry) · [La documentation du registre](https://distribution.github.io/distribution/) · [Registres sans HTTPS](https://distribution.github.io/distribution/about/insecure/)

## Récap

- Un registre est un logiciel comme un autre : il se lance dans un conteneur.
- Il s'utilise à travers une API, que `curl` sait interroger.
- Docker n'accepte le HTTP que pour un registre local.

## Questions

```quiz
title: "Le registre"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que répond `/v2/_catalog` sur un registre qui vient de démarrer ?"
    answers:
      - "`{\"repositories\":[]}`, une liste vide"
      - "Une erreur, tant qu'aucune image n'a été publiée"
      - "La liste des images de Docker Hub"
    correct: 1
    explanation: "Le registre ne connaît que ce qu'on y a publié. Il ne recopie pas Docker Hub."
  - prompt: "Pourquoi Docker accepte-t-il ici un registre sans HTTPS ?"
    answers:
      - "Parce qu'il accepte tous les registres en HTTP"
      - "Parce que l'image `registry` est officielle"
      - "Parce que l'adresse est `localhost`, qu'il considère comme sûre"
    correct: 3
    explanation: "Pour toute autre adresse, Docker exige du HTTPS, à moins de le configurer explicitement. Un registre partagé se met derrière HTTPS."
```
