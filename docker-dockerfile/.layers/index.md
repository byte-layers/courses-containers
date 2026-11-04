---
title: "Écrire le Dockerfile d'une application"
description: "Cours pratique Docker : écrire un Dockerfile, construire une image, installer des dépendances, la configurer et garder hors de l'image ce qui n'a rien à y faire."
tags:
  - skill
  - docker
  - containers
difficulty: beginner
duration: 120
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

À la fin de ce cours, vous savez écrire le Dockerfile d'une petite application, en faire une image et la lancer. Jusqu'ici, vous utilisiez les images des autres ; vous allez maintenant fabriquer les vôtres.

## Pour qui ?

**Débutant sur les images.** Vous savez lancer un conteneur et lire ce qu'il fait : `docker run` et ses options `-d`, `--name`, `-e`, `--rm`, puis `docker logs`, `docker exec` et `docker inspect`. C'est ce qu'enseigne le cours « Lancer, configurer et observer un conteneur ». Vous avez aussi vu `-p` comme une recette : le port de votre machine vient d'abord, celui du conteneur ensuite.

Vous n'avez pas besoin de savoir programmer. Les petites applications de ce cours sont fournies et écrites en Python, et chaque ligne utile est expliquée.

Il faut `curl`, pour interroger un serveur depuis le terminal, et le port 28320 libre.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 2 heures en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques questions. Vos fichiers vont dans `~/layers-l2/`, où `~` désigne votre dossier personnel, et tout ce que vous créez dans Docker porte le préfixe `layers-l2-`. La dernière étape supprime ce que ce cours a créé, et seul le dossier `~/layers-l2`, alors vide, peut rester : vos autres images et vos autres conteneurs ne sont jamais touchés.

Pour pratiquer ensuite sur une vraie application, faites le lab « Conteneuriser getting-started-app ». Pour vous tester sans guide : le challenge « Conteneuriser une application inconnue ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
