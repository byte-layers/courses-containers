---
title: "Accélérer un build avec le cache"
description: "Cours pratique Docker : lire le cache de build, comprendre ce qui l'invalide, ordonner un Dockerfile pour ne plus tout refaire, et choisir quand s'en passer."
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

À la fin de ce cours, vous savez pourquoi un build prend une seconde ou une minute, et vous savez écrire un Dockerfile qui ne refait que ce qui a changé. Sur un vrai projet, on reconstruit une image des dizaines de fois par jour : cela change vraiment le travail quotidien.

## Pour qui ?

**Débutant sur le cache.** Vous savez écrire un Dockerfile avec `FROM`, `WORKDIR`, `COPY`, `RUN` et `CMD`, et le construire avec `docker build`, ce qu'enseigne le cours « Écrire le Dockerfile d'une application ». Vous n'avez pas besoin de savoir programmer : la petite application en Python de ce cours est fournie.

Lisez d'abord le cours de 15 minutes « Couches et copy-on-write », qui explique ce qu'est une couche. Ce cours se suit aussi sans lui : il suffit de savoir qu'une image s'empile, instruction après instruction, et que chaque instruction qui touche aux fichiers produit une couche.

Il faut `curl` et le port 28330 libre.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 1 h 15 en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques questions. Vos fichiers vont dans `~/byte-layers/docker/l3/cache`, où `~` désigne votre dossier personnel, et vos images portent le préfixe `layers-l3-`. La dernière étape supprime tout cela. Le cache de build, lui, reste sur votre machine : si vous refaites ce cours, des étapes annoncées comme lentes seront donc déjà `CACHED`.

Pour vous tester sans guide : le challenge « Réduire et accélérer une image existante ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
