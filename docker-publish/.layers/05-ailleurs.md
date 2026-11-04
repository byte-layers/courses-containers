---
title: "Publier ailleurs, et nettoyer"
description: "Ce qui change sur Docker Hub, puis le ménage"
---

Vous avez fait tous les gestes de la publication sur votre registre. Avec un registre public ou celui de votre entreprise, ces gestes restent les mêmes, et seuls deux points changent.

## Sur un registre public

Ces commandes ne sont pas à lancer : ce cours ne publie rien en dehors de votre machine. Elles montrent seulement à quoi ressemblerait une publication sur Docker Hub, pour un compte nommé `votre-compte`.

```bash
docker login
docker tag layers-l4-hello:1.0 votre-compte/layers-l4-hello:1.0
docker push votre-compte/layers-l4-hello:1.0
```

La première différence est l'**identification** : `docker login` demande votre compte, et Docker garde ensuite le droit d'écrire. Sans elle, le `push` échoue avec un message comme `denied: requested access to the resource is denied`.

La seconde est le **nom** : sur Docker Hub, un dépôt appartient à un compte, d'où `votre-compte/` devant le nom, et il n'y a pas de registre à écrire, puisque Docker Hub est le registre par défaut. Pour un registre d'entreprise, on écrirait son adresse, comme vous l'avez fait pour le vôtre.

Une image publique est lisible par tout le monde : n'y laissez jamais de secret. Et si vous ne voulez pas de cette exposition, Docker Hub propose aussi des dépôts privés.

```ack
J'ai compris ce qui change sur un registre public
```

## Nettoyer

Il ne reste qu'à tout ranger. Supprimez d'abord le registre. Il garde ses images dans un **volume**, un espace de stockage que Docker crée pour lui ; un prochain cours, « Garder ses données », détaille cette notion. L'option `-v` supprime ce volume avec le conteneur, sans quoi il resterait sur votre disque :

```exec
docker rm -fv layers-l4-registry
```

Retirez ensuite vos images, le tag et le digest noté, puis supprimez votre dossier de travail :

```exec
docker rmi localhost:28340/layers-l4-hello:1.0 "$(cat ~/layers-l4/digest-v1.txt)"
rm -rf ~/layers-l4
```

```verify
if docker container inspect layers-l4-registry >/dev/null 2>&1; then
  echo "Le conteneur layers-l4-registry existe encore."
  exit 1
fi
left=$(docker images --format '{{.Repository}}' | grep 'layers-l4-')
if [ -n "$left" ]; then
  echo "Il reste des images : $(echo "$left" | sort -u | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l4" ]; then
  echo "Le dossier ~/layers-l4 existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker login`](https://docs.docker.com/reference/cli/docker/login/) · [Publier sur Docker Hub](https://docs.docker.com/get-started/introduction/build-and-push-first-image/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/)

## Récap

- `docker login` donne le droit d'écrire sur un registre qui l'exige.
- Sur Docker Hub, un dépôt s'écrit `compte/nom` ; ailleurs, le nom commence par l'adresse du registre.
- Les gestes sont les mêmes partout : `tag`, `push`, `pull`.

Pour vous tester sans guide, faites maintenant le challenge « Publier une image et la retrouver par son digest ».

## Questions

```quiz
title: "Publier ailleurs"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pour publier sur Docker Hub avec le compte `marie`, quel nom faut-il donner à l'image ?"
    answers:
      - "`app:1.0`"
      - "`marie/app:1.0`"
      - "`hub.docker.com/app:1.0`"
    correct: 2
    explanation: "Un dépôt de Docker Hub appartient à un compte. Le registre, lui, n'a pas besoin d'être écrit : c'est celui par défaut."
```
