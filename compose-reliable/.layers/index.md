---
title: "Fiabiliser une application Compose"
description: "Cours pratique Docker : contrôles de santé, redémarrages, limites de ressources, durcissement, secrets et fichier de production."
tags:
  - skill
  - docker
  - containers
difficulty: beginner
duration: 150
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Une application qui démarre sur votre poste n'est pas prête pour un serveur. Elle doit attendre ce dont elle a besoin, repartir après une panne, ne pas asphyxier la machine et donner le moins de prises possible. À la fin de ce cours, vous savez ajouter tout cela à un fichier Compose, et vous savez le prouver.

## Pour qui ?

Ce cours suppose que **vous savez déjà écrire un fichier Compose** : services, volumes, réseaux, variables. C'est ce qu'enseigne « Décrire une application avec Compose ». Vous savez aussi écrire un `Dockerfile`. Lisez d'abord « Un secret ne va pas dans l'image », en 15 minutes : l'étape 4 s'appuie dessus. Tout ce qui est nouveau est expliqué quand il arrive.

Il faut `curl`, et les ports 28382 et 28383 de votre machine doivent être libres.

## Comment ça se passe

Cinq étapes à suivre dans l'ordre, environ 2 h 30 en tout. Vous partez d'une petite application, un compteur de visites et sa base Redis, et vous lui ajoutez une protection à chaque étape, en provoquant à chaque fois la panne qu'elle évite. Vos fichiers vivent dans `~/byte-layers/docker/l8/reliable`, et tout ce que Docker crée commence par `layers-l8-`. La dernière étape supprime le tout.

Pour pratiquer ensuite : le lab « Plusieurs applications derrière un reverse proxy ». Pour vous tester sans guide : le challenge « Une stack prête pour la production ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
