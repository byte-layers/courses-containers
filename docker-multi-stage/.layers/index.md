---
title: "Réduire une image avec le multi-stage"
description: "Cours pratique Docker : séparer la construction de l'exécution dans un même Dockerfile, ne livrer que le résultat, et aller jusqu'à une image partie de rien."
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

À la fin de ce cours, vous savez faire passer une image de plusieurs centaines de mégaoctets à une dizaine, sans rien changer à l'application. Vous saurez aussi ne construire qu'une partie d'un Dockerfile, par exemple pour lancer des tests.

## Pour qui ?

**Débutant sur le multi-stage.** Vous savez écrire un Dockerfile avec `FROM`, `WORKDIR`, `COPY`, `RUN` et `CMD`, et le construire avec `docker build`, ce qu'enseigne le cours « Écrire le Dockerfile d'une application ». Vous n'avez pas besoin de connaître le langage Go : la petite application de ce cours est fournie, et chaque commande propre à Go est expliquée.

Lisez d'abord le cours de 15 minutes « Couches et copy-on-write », qui explique pourquoi une image garde tout ce qu'elle a empilé. Ce cours se suit aussi sans lui, si vous retenez ceci : chaque instruction qui touche aux fichiers ajoute une **couche**, une couche ne se modifie jamais, et une suppression ne fait donc que masquer ce qui se trouve dessous.

Il faut `curl` et le port 28331 libre.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 1 h 15 en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques questions. Vos fichiers vont dans `~/layers-l3/multi`, où `~` désigne votre dossier personnel, et vos images portent le préfixe `layers-l3-`. La dernière étape supprime tout cela.

Pour vous tester sans guide : le challenge « Réduire et accélérer une image existante ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
