---
title: "Lancer un registre local"
description: "Un registre privé dans un conteneur, et son API"
---

Pour publier, il faut un registre où l'on a le droit d'écrire. Sur Docker Hub, il faudrait un compte. Or un registre n'est qu'un logiciel : son image officielle s'appelle `registry`, et il suffit de la lancer pour disposer du vôtre, sans compte, sur votre machine. Les gestes de publication sont les mêmes qu'avec un registre public, et vous ne risquez pas de publier quoi que ce soit par erreur.

## Démarrer le registre

Le registre écoute sur le port 5000 du conteneur. Publiez-le sur le port 28340 de votre machine :

```exec
docker run -d --name layers-l4-registry -p 28340:5000 registry:3
```

| Élément | Rôle |
|---|---|
| `-d` | le conteneur tourne en arrière-plan et vous rend la main |
| `--name layers-l4-registry` | un nom fixe, pour pouvoir le désigner ensuite |
| `-p 28340:5000` | le port 28340 de votre machine mène au port 5000 du conteneur |
| `registry:3` | le registre officiel, en version 3 |

```verify
if [ "$(docker inspect layers-l4-registry --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le conteneur layers-l4-registry ne tourne pas. Pour repartir de zéro : docker rm -fv layers-l4-registry (-f force la suppression, -v supprime aussi ses données), puis relancez la commande."
  exit 1
fi
echo "Le registre tourne."
```

## Lui parler

Un registre s'utilise à travers une API, c'est-à-dire des adresses web qui répondent à des programmes. Docker s'en sert à chaque `pull` et à chaque `push`, et vous pouvez l'interroger vous-même avec `curl`. Commencez par le point d'entrée `/v2/`, le nom de la version de cette API. `-i` affiche aussi l'en-tête de la réponse, où se lit le code de résultat, et `--retry` patiente le temps que le registre démarre :

```exec
curl -sS -i --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28340/v2/
```

Une ligne `curl: (56) Recv failure` au début n'a rien de grave : le registre n'était pas encore prêt, et `curl` a réessayé. La ligne `HTTP/1.1 200 OK` veut dire que le registre répond et n'exige aucun mot de passe. Le corps de la réponse se réduit à `{}`, ce qui est normal. Demandez ensuite la liste de ce qu'il contient :

```exec
curl -sS http://localhost:28340/v2/_catalog
```

Vous lisez `{"repositories":[]}` : ce registre ne contient encore aucun dépôt. C'est l'étape suivante qui va le remplir.

```verify
if ! curl -s --max-time 5 http://localhost:28340/v2/_catalog | grep -q 'repositories'; then
  echo "Le registre ne répond pas sur le port 28340. Vérifiez les ports avec : docker ps"
  exit 1
fi
echo "Le registre répond sur le port 28340."
```

## Un registre sans chiffrement

Votre registre parle en HTTP, sans chiffrement ni mot de passe. Docker l'accepte ici parce que l'adresse est `localhost`, qu'il considère comme sûre : pour toute autre adresse, il exige du HTTPS et refuse de publier. C'est un raccourci pour apprendre, à ne pas reproduire tel quel : un registre partagé par une équipe se met derrière HTTPS, avec une authentification.

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
      - "Une erreur, tant qu'aucune image n'a été publiée"
      - "`{\"repositories\":[]}`, une liste vide"
      - "La liste des images de Docker Hub"
    correct: 2
    explanation: "Le registre ne connaît que ce qu'on y a publié. Il ne recopie pas Docker Hub."
  - prompt: "Pourquoi Docker accepte-t-il ici un registre sans HTTPS ?"
    answers:
      - "Parce qu'il accepte tous les registres en HTTP"
      - "Parce que l'adresse est `localhost`, qu'il considère comme sûre"
      - "Parce que l'image `registry` est officielle"
    correct: 2
    explanation: "Pour toute autre adresse, Docker exige du HTTPS, à moins de le configurer explicitement. Un registre partagé se met derrière HTTPS."
```
