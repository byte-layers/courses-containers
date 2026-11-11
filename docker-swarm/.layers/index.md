---
title: "Déployer sur un cluster Swarm"
description: "Cours pratique Docker : créer un swarm, y lancer un service répliqué, le mettre à jour sans coupure, le restaurer, et déployer une stack Compose."
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

À la fin de ce cours, vous savez créer un swarm, y lancer un service répliqué, le mettre à jour sans coupure, revenir en arrière, et déployer une application décrite dans un fichier Compose.

## Pour qui ?

**Débutant sur les orchestrateurs.** Vous savez construire une image et décrire une application avec Compose : c'est ce qu'enseignent les cours « Écrire le Dockerfile d'une application » et « Décrire une application avec Compose ». Vous n'avez jamais utilisé Swarm, et ce cours ne suppose rien à son sujet.

Lisez d'abord « Pourquoi un orchestrateur », qui explique ce qu'est un état voulu. Ce cours se suit aussi sans lui.

Il vous faut Docker qui répond à `docker ps`, `curl`, et les ports **28391** à **28393** libres. La plupart des images sont déjà sur votre machine si vous avez suivi le parcours : `nginx:1.30-alpine`, `busybox:1.37` et `redis:8-alpine`.

## Un swarm à un seul nœud

Un vrai cluster demande plusieurs machines, et vous n'en avez qu'une. Ce cours fait donc tout tourner sur un swarm d'**un seul nœud** : votre moteur Docker, ou celui de votre poste hébergé. Les commandes sont exactement celles d'un cluster. Deux points seulement diffèrent : la répartition entre plusieurs nœuds ne se voit pas, et une image peut rester locale alors qu'un cluster la demande à un registre, comme l'étape 3 l'explique. L'étape 5 vous montre à quoi ressemble cette répartition, avec la vraie sortie d'un cluster de deux nœuds.

## Comment ça se passe

Cinq étapes à suivre dans l'ordre, environ 2 heures en tout. Tout ce que vous créez porte le préfixe `layers-l9-`, et vos fichiers vont dans `~/byte-layers/docker/l9`.

**Une différence avec les cours précédents** : ce cours change l'état de votre moteur Docker lui-même, en le faisant entrer dans un swarm, et la dernière étape l'en fait sortir. La première étape vérifie donc que votre moteur n'est pas déjà dans un swarm, car en sortir dissoudrait celui-ci.

Pour vous tester ensuite sans guide : le challenge « Un service répliqué, mis à jour et restauré ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
