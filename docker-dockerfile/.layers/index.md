---
title: "Écrire le Dockerfile d'une application"
description: "Cours pratique Docker : écrire un Dockerfile, construire une image, choisir sa base, installer des dépendances, configurer l'image et garder dehors ce qui n'a rien à y faire."
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

Un Dockerfile est la recette d'une image : quelques lignes de texte, et n'importe qui peut reconstruire l'image à partir d'elles. Ce cours part d'un petit serveur web et vous fait écrire la recette, la construire, puis l'améliorer : choisir une base, installer des bibliothèques, régler l'image, en écarter un mot de passe, retirer les droits d'administrateur. À la fin, vous savez fabriquer l'image d'une petite application et la lancer.

**Prérequis** : savoir lancer un conteneur et lire ce qu'il fait, c'est-à-dire `docker run` et ses options `-d`, `--name`, `-e`, `-p`, `--rm`, puis `docker ps`, `docker logs` et `docker exec`. Ces commandes s'apprennent dans [Lancer, configurer et observer un conteneur](https://byte-layers.com/fr/skills/docker-run) et [Héberger une page dans un conteneur](https://byte-layers.com/fr/labs/docker-first-web-page). Programmer n'est pas nécessaire : les petites applications Python sont fournies, et le texte dit ce que fait chacune.

## Ce qu'il vous faut

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

Il vous faut Docker qui répond à `docker ps`, `curl` pour interroger un serveur depuis le terminal, un éditeur de texte, et le port 28320 libre. Un numéro aussi haut a été choisi pour ne pas gêner ce qui tourne déjà sur votre machine.

## Comment ça se passe

Le cours compte quatre étapes à suivre dans l'ordre, pour environ 2 heures en tout. Chacune fait lancer de vraies commandes, vérifie le résultat, puis se termine par quelques questions.

Vos fichiers vont dans `~/layers-l2/`, où `~` désigne votre dossier personnel, et tout ce que vous créez dans Docker porte le préfixe `layers-l2-`. La dernière étape supprime ce que ce cours a créé, sans toucher à vos autres images ni à vos autres conteneurs.

Pour pratiquer ensuite sur une vraie application, faites le lab [Conteneuriser une application pas à pas](https://byte-layers.com/fr/labs/docker-containerize-app). Pour vous tester sans guide, faites le challenge [Conteneuriser une application inconnue](https://byte-layers.com/fr/challenges/docker-dockerfile-challenge).
