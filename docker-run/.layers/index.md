---
title: "Lancer, configurer et observer un conteneur"
description: "Cours pratique Docker : docker run et ses options, le cycle de vie d'un conteneur, et comment savoir ce qu'il fait."
tags:
  - skill
  - docker
  - containers
difficulty: beginner
duration: 120
introTitle: "Présentation"
requires: "0.3.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

À la fin de ce cours, vous savez lancer un conteneur, le configurer au démarrage, le conduire à travers son cycle de vie et
comprendre ce qu'il fait.

## Pour qui ?

**Débutant sur les conteneurs.** Vous savez utiliser un terminal : vous déplacer, lancer une commande, lire une erreur. Vous
n'avez pas besoin de connaître Docker. Il doit simplement être installé.

Lisez d'abord deux cours de 15 minutes, qui expliquent ce que celui-ci montre : « L'image est immuable », puis « Un conteneur est un processus isolé ». Ce cours se suit aussi sans eux : il redonne l'essentiel.

Il faut aussi `curl`, pour interroger un serveur web depuis le terminal : vérifiez avec `curl --version`. L'étape 4 utilise le port 28082 de votre machine : il doit être libre.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 2 heures en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques
questions. Tout ce que vous créez porte le préfixe `layers-l1-` et chaque étape le supprime à la fin : vos autres conteneurs
ne sont jamais touchés. Les images téléchargées, elles, restent sur votre machine pour servir à nouveau.

Pour pratiquer ensuite sur un cas concret, faites le lab « Héberger une page dans un conteneur ». Pour vous tester sans guide : le challenge « Faire vivre un conteneur, sans guide ».

**Si `docker run` échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP.
Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
