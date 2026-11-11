---
title: "Publier ailleurs, et nettoyer"
description: "Les registres possibles, ce qui change sur Docker Hub, puis le ménage"
---

Vous avez fait tous les gestes de la publication sur votre registre. Ces gestes restent les mêmes partout : `tag`, `push`, `pull`. Il reste à savoir où publier pour de vrai, et ce qui change alors.

## Les registres où l'on publie, et ce qui peut bloquer

Votre registre local vous a servi à apprendre. En situation réelle, le choix se fait d'après qui doit lire l'image et où vit votre code, et ce tableau donne les quatre familles que vous croiserez.

| Famille | Exemples | Quand on la choisit | Ce qui peut bloquer |
|---|---|---|---|
| Registre public | Docker Hub | pour partager largement. C'est le registre par défaut de Docker | un compte est nécessaire pour publier, et les [limites d'usage](https://docs.docker.com/docker-hub/usage/) et le nombre de dépôts privés dépendent du plan |
| Registre de votre hébergeur de code | [GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [GitLab](https://docs.gitlab.com/user/packages/container_registry/) | pour garder les images à côté du code et de son pipeline | un compte, et les quotas du plan |
| Registre d'un fournisseur cloud | Amazon ECR, Google Artifact Registry, Azure Container Registry | quand les serveurs tournent déjà chez ce fournisseur | un compte payant, et le stockage est facturé |
| Registre d'entreprise, installé chez vous | [Harbor](https://goharbor.io), Nexus, Artifactory | quand les images doivent rester dans l'entreprise | il faut l'installer, le sécuriser et le maintenir |

```ack
Je connais les familles de registres et ce qui peut les bloquer
```

## Ce qui change sur un registre qui exige un compte

Deux points changent par rapport à ce que vous venez de faire. Le premier est l'**identification** : `docker login` demande votre compte, et Docker garde ensuite le droit d'écrire. Sans elle, le `push` échoue avec un message comme `denied: requested access to the resource is denied`.

Le second est le **nom** : sur Docker Hub, un dépôt appartient à un compte, d'où `votre-compte/` devant le nom, et il n'y a pas de registre à écrire, puisque Docker Hub est le registre par défaut. Pour tout autre registre, on écrit son adresse, comme vous l'avez fait pour le vôtre.

## ✅ Bonus : publier pour de vrai sur Docker Hub

Ce bonus est facultatif, et rien ne le vérifie : il faut un compte Docker Hub, et votre image sera publique. Une image publique est lisible par tout le monde : n'y laissez jamais de secret, ce qui ne risque rien avec celle-ci. Si vous voulez essayer, remplacez `votre-compte` par le nom de votre compte :

```bash
docker login
docker tag localhost:28340/layers-l4-hello:1.0 votre-compte/layers-l4-hello:1.0
docker push votre-compte/layers-l4-hello:1.0
```

Votre image apparaît alors sur votre page Docker Hub, d'où vous pourrez la supprimer. Retirez aussi ce nom de votre machine avec `docker rmi votre-compte/layers-l4-hello:1.0`, et fermez la session avec `docker logout`.

## Supprimer le registre, vos images et le dossier

Il ne reste qu'à tout ranger. Supprimez d'abord le registre. Il garde ses images dans un **volume**, un espace de stockage que Docker crée pour lui ; un prochain cours, « Garder ses données », détaille cette notion. L'option `-v` supprime ce volume avec le conteneur, sans quoi il resterait sur votre disque :

```exec
docker rm -fv layers-l4-registry
```

Retirez ensuite vos images, celle du tag et celle du digest noté, puis supprimez votre dossier de travail. Les images `alpine:3.22`, `registry:3` et `nginx:1.30-alpine` restent sur votre machine, car d'autres cours s'en servent. `rm -rf` efface sans demander confirmation, et il faut donc vérifier le chemin.

```exec
docker rmi localhost:28340/layers-l4-hello:1.0 "$(cat ~/byte-layers/docker/l4/digest-v1.txt)"
rm -rf ~/byte-layers/docker/l4
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
if [ -e "$HOME/byte-layers/docker/l4" ]; then
  echo "Le dossier ~/byte-layers/docker/l4 existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker login`](https://docs.docker.com/reference/cli/docker/login/) · [Publier sur Docker Hub](https://docs.docker.com/get-started/introduction/build-and-push-first-image/) · [`docker rm`](https://docs.docker.com/reference/cli/docker/container/rm/)

## Récap

- Un registre se choisit d'après qui doit lire l'image et où vit le code, et il peut exiger un compte, un plan payant ou de l'entretien.
- `docker login` donne le droit d'écrire sur un registre qui l'exige.
- Sur Docker Hub, un dépôt s'écrit `compte/nom` ; ailleurs, le nom commence par l'adresse du registre.
- Les gestes sont les mêmes partout : `tag`, `push`, `pull`.

Pour vous tester sans guide, faites maintenant le challenge [Publier une image et la retrouver par son digest](https://byte-layers.com/fr/challenges/docker-publish-challenge).

## Questions

```quiz
title: "Publier ailleurs"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pour publier sur Docker Hub avec le compte `marie`, quel nom faut-il donner à l'image ?"
    answers:
      - "`marie/app:1.0`"
      - "`app:1.0`"
      - "`hub.docker.com/app:1.0`"
    correct: 1
    explanation: "Un dépôt de Docker Hub appartient à un compte. Le registre, lui, n'a pas besoin d'être écrit : c'est celui par défaut."
```
