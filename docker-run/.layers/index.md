---
title: "Lancer, configurer et observer un conteneur"
description: "Cours pratique Docker : docker run et ses options, publier un port, entrer dans un conteneur, savoir ce qu'il fait et le conduire à travers son cycle de vie."
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

Vous allez lancer des conteneurs, les configurer au démarrage, entrer dedans, lire ce qu'ils font, puis les arrêter et les relancer. À la fin, face à un conteneur qui ne répond pas, vous savez voir son état, lire ses logs, entrer dedans et le redémarrer.

**Niveau** : débutant. Vous savez utiliser un terminal : vous déplacer, lancer une commande, lire une erreur. Chaque commande Docker est expliquée quand elle arrive.

**Prérequis** : Docker installé et vérifié, ce que fait le lab [Installer Docker et vérifier son poste](https://byte-layers.com/fr/labs/docker-install), et savoir ce que sont une image et un conteneur, ce que dit [Pourquoi les conteneurs](https://byte-layers.com/fr/bits/containers-why).

**Ce qu'il faut** : `curl`, pour interroger un serveur web depuis le terminal, et les ports **28080** et **28082** de votre machine libres.

## Comment ça se passe

Quatre étapes à suivre dans l'ordre, environ 2 heures en tout : lancer, configurer, observer, puis arrêter et relancer. Chacune fait taper les commandes, vérifie le résultat, puis se termine par quelques questions. Tout ce que vous créez porte le préfixe `layers-l1-`, et chaque étape le supprime à la fin : vos autres conteneurs ne sont jamais touchés. Les images téléchargées, elles, restent sur votre machine pour servir à nouveau.
