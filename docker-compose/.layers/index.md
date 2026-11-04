---
title: "Décrire une application avec Compose"
description: "Cours pratique Docker : écrire un fichier compose.yaml, faire tourner plusieurs services ensemble, les configurer, garder leurs données et les piloter."
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

À la fin de ce cours, vous savez décrire une application de plusieurs conteneurs dans un seul fichier, la démarrer et l'arrêter d'une commande, et lire ce que Compose a créé pour vous.

## Pour qui ?

Ce cours s'adresse aux **débutants sur Compose**. Il suppose que vous avez déjà construit une image, relié des conteneurs sur un réseau et gardé des données dans un volume. Les cours « Écrire le Dockerfile d'une application », « Relier des conteneurs et publier un port » et « Garder ses données : volumes et bind mounts » enseignent ces trois gestes. Chaque notion utile est rappelée en une phrase quand elle revient.

Vous n'avez pas besoin de connaître YAML, le format du fichier : l'étape 1 donne ce qu'il faut. Il faut aussi `curl`, et le port 28370 de votre machine doit être libre. Compose est livré avec Docker Desktop ; sous Linux, `docker compose version` doit répondre, sinon installez le paquet `docker-compose-plugin`.

## Comment ça se passe

Cinq étapes à suivre dans l'ordre, environ 2 heures en tout. Vous construisez une seule application, un compteur de visites, du premier fichier jusqu'à son pilotage. Vos fichiers vivent dans `~/layers-l7/counter`, et tout ce que Docker crée commence par `layers-l7-`. La dernière étape supprime le tout : vos autres conteneurs ne sont jamais touchés.

Pour pratiquer ensuite sur une vraie application, faites le lab « getting-started-app en Compose ». Pour vous tester sans guide : le challenge « Une application multi-services, sans guide ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
