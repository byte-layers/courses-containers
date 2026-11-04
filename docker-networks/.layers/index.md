---
title: "Relier des conteneurs et publier un port"
description: "Cours pratique Docker : rendre un conteneur joignable depuis l'hôte, faire parler des conteneurs par leur nom, et séparer ceux qui n'ont pas à se parler."
tags:
  - skill
  - docker
  - containers
difficulty: beginner
duration: 90
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

À la fin de ce cours, vous savez rendre un conteneur joignable depuis votre machine, faire communiquer des conteneurs par leur nom, et isoler ceux qui n'ont pas à se parler.

## Pour qui ?

**Débutant sur le réseau des conteneurs.** Vous savez lancer un conteneur, lire ses logs et utiliser `docker exec` : le cours « Lancer, configurer et observer un conteneur » suffit. Vous n'avez pas besoin de connaître les réseaux : chaque mot est défini quand il arrive.

Lisez d'abord le cours de 15 minutes « Localhost n'est pas l'hôte », qui explique pourquoi un conteneur ne voit pas les ports de ses voisins. Pour rappel, une **adresse IP** est le numéro qui identifie une machine sur un réseau, et un **port** est le numéro de la porte à laquelle un service répond.

Il faut aussi `curl`, pour interroger un serveur web depuis le terminal : vérifiez avec `curl --version`. Les ports 28352 et 28353 de votre machine doivent être libres.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 1 h 30 en tout. Chacune donne de vraies commandes à lancer, vérifie le résultat, puis se termine par quelques questions. Tout ce que vous créez porte le préfixe `layers-l5-` et chaque étape le supprime à la fin : vos autres conteneurs et réseaux ne sont jamais touchés.

Pour pratiquer ensuite sur une vraie application, faites le lab « Une application et sa base, à la main ». Pour vous tester sans guide : le challenge « Isoler et relier des conteneurs, sans guide ».

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.
