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

Lisez d'abord deux notions de 15 minutes, elles expliquent ce que ce cours montre : « L'image est immuable », puis « Un conteneur est un processus isolé ». Le cours se suit quand même sans elles.

Il faut aussi `curl`, pour interroger un serveur web depuis le terminal : vérifiez avec `curl --version`.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 2 heures en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques
questions. Tout ce que vous créez porte le préfixe `layers-l1-` et chaque étape le supprime à la fin : vos autres conteneurs
ne sont jamais touchés.

Pour vous tester sans guide ensuite : le challenge « Faire vivre un conteneur ».

**Si `docker run` échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP.
Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
