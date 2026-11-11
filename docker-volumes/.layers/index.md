---
title: "Garder ses données : volumes et bind mounts"
description: "Cours pratique Docker : conserver des données au-delà d'un conteneur, partager un dossier de votre machine, sauvegarder et restaurer."
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

À la fin de ce cours, vous savez garder des données au-delà de la vie d'un conteneur, donner à un conteneur l'accès à un dossier de votre machine, choisir entre les deux, et sauvegarder un volume.

## Pour qui ?

**Débutant sur le stockage des conteneurs.** Vous savez lancer un conteneur, utiliser `docker exec` et publier un port : les cours « Lancer, configurer et observer un conteneur » et « Relier des conteneurs et publier un port » suffisent. Il faut aussi savoir ce qu'est un chemin de fichier, comme `/home/moi/site`.

Lisez d'abord le cours de 15 minutes « Le conteneur est jetable », qui explique pourquoi les données doivent sortir du conteneur. Pour rappel, la **couche d'écriture** est l'espace où un conteneur garde ses modifications, et elle disparaît avec lui.

Il faut également `curl` et `tar`, et le port 28360 de votre machine doit être libre.

## Comment ça se passe

Trois étapes à suivre dans l'ordre, environ 1 h 15 en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques questions. Tout ce que vous créez porte le préfixe `layers-l6-`, vos fichiers vont dans `~/byte-layers/docker/l6`, et la dernière étape supprime le tout. Vos autres conteneurs et volumes ne sont jamais touchés.

Pour pratiquer ensuite sur une vraie application, faites le lab « Persister une base, développer en direct ». Pour vous tester sans guide : le challenge « Prouver que les données survivent ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
