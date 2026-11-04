---
title: "Publier une image : pull, tag, push"
description: "Cours pratique Docker : trouver une image, lancer un registre local, y publier la vôtre et la retrouver par son tag ou par son digest."
tags:
  - skill
  - docker
  - containers
difficulty: beginner
duration: 75
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

À la fin de ce cours, vous savez trouver une image, publier la vôtre dans un registre, la récupérer comme le ferait une autre machine, et choisir entre un tag et un digest pour la désigner.

## Pour qui ?

**Débutant sur la distribution des images.** Vous savez lancer un conteneur et écrire un petit Dockerfile : c'est ce qu'enseignent les cours « Lancer, configurer et observer un conteneur » et « Écrire le Dockerfile d'une application ». Vous n'avez jamais publié d'image.

Lisez d'abord « Nommer une image : registre, tag, digest », qui explique les mots employés ici. Ce cours se suit aussi sans lui : il redonne l'essentiel au passage.

Il vous faut Docker qui répond à `docker ps`, `curl`, et le port **28340** libre.

## Comment ça se passe

Cinq étapes à suivre dans l'ordre, environ 1 h 15 en tout. Vous n'aurez besoin ni de compte ni de mot de passe : le registre dans lequel vous publiez est un conteneur local, et rien ne sort de votre machine. Docker Hub n'est utilisé qu'en lecture.

Tout ce que vous créez porte le préfixe `layers-l4-`, vos fichiers vont dans `~/layers-l4`, et la dernière étape supprime le tout. Les étapes 2 à 5 s'enchaînent : le registre n'est supprimé qu'à la fin.

Pour vous tester ensuite sans guide : le challenge « Publier une image et la retrouver par son digest ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`. Cette connexion n'est demandée par ce cours que dans ce cas.
