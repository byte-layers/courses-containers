---
title: "Déployer une application : les possibilités"
description: "Ce qui compose une application, et les façons de la faire tourner : serveur physique, machines virtuelles, conteneurs, orchestrateurs."
tags:
  - bit
  - docker
  - containers
  - deployment
difficulty: beginner
duration: 10
requires: "0.4.0"
---

Un site web ouvert dans votre navigateur repose le plus souvent sur trois pièces : un front-end, un back-end et une base de données. Pour le mettre en ligne, il faut les faire tourner quelque part : sur un serveur physique, dans des machines virtuelles, dans des conteneurs, ou avec un orchestrateur. Vous saurez ce que ces mots recouvrent et ce qui distingue ces quatre possibilités.

**Prérequis** : aucun.

# Déployer une application : les possibilités

Quand vous visitez une boutique en ligne, vous ne voyez qu'une page. Derrière cette page, plusieurs programmes travaillent ensemble, sur une ou plusieurs machines que quelqu'un a dû préparer. C'est ce travail de préparation qu'on appelle le déploiement.

## Une application est faite de plusieurs pièces

La plupart des applications web se découpent en trois pièces, que l'on désigne par leur nom anglais. Ce tableau les présente sur l'exemple de la boutique.

| Pièce | Ce qu'elle fait dans la boutique | Technologies courantes |
|---|---|---|
| **front-end** | les pages que le navigateur affiche, le catalogue et le panier ; ses fichiers sont servis par une machine et exécutés par le navigateur | HTML, CSS, JavaScript |
| **back-end** | applique les règles : calcule le total, valide la commande | Node.js, Python, Java, PHP |
| **base de données** | garde ce qui doit durer : les produits, les clients, les commandes | MySQL, PostgreSQL |

Une demande traverse ces pièces l'une après l'autre, comme le montre ce schéma. Le navigateur est le **client**, et ce qui lui répond est le **serveur** : on parle d'architecture client-serveur.

```
navigateur  ──►  front-end  ──►  back-end  ──►  base de données
```

Toutes les applications n'ont pas cette forme, mais ce qui suit vaut pour les autres. Chaque pièce a besoin de quelque chose pour tourner : un environnement d'exécution en version précise, comme Node.js, des bibliothèques, des fichiers de configuration. On appelle tout cela ses **dépendances**.

## Déployer, c'est choisir où et comment faire tourner ces pièces

**Déployer** une application, c'est installer ses pièces et leurs dépendances sur des machines, les configurer, puis les rendre accessibles à ses utilisateurs. Ces machines s'appellent des **serveurs**, le mot désignant ici l'ordinateur et non plus le programme. Il existe quatre grandes façons de s'y prendre, et les sections suivantes les prennent une par une.

| Possibilité | En une phrase |
|---|---|
| **Serveur physique** | on installe tout directement sur le système d'une vraie machine |
| **Machines virtuelles** | on découpe une vraie machine en plusieurs ordinateurs simulés |
| **Conteneurs** | on fait tourner chaque pièce à part, sur un même système |
| **Orchestrateur** | un logiciel répartit et surveille les conteneurs sur plusieurs machines |

## Sur un serveur physique : tout installer sur une même machine

C'est la façon la plus directe : un ordinateur, un système d'exploitation, et vous y installez chaque pièce, comme un logiciel sur votre poste. On parle souvent de *bare metal*, « sur le métal nu », pour dire qu'aucune couche ne s'intercale entre le système et le matériel.

```
┌───────────┬───────────┬─────────────────┐
│ front-end │ back-end  │ base de données │
├───────────┴───────────┴─────────────────┤
│         système d'exploitation          │
├─────────────────────────────────────────┤
│               la machine                │
└─────────────────────────────────────────┘
```

Tout le matériel sert directement l'application, et il n'y a qu'un système à connaître. En revanche, les pièces partagent tout : leurs dépendances peuvent entrer en conflit, une pièce qui consomme trop gêne les autres, et tenir plus de charge demande d'ajouter du matériel.

## Sur des machines virtuelles : une vraie machine découpée en plusieurs

Une **machine virtuelle**, ou VM, est un ordinateur simulé par un logiciel, l'**hyperviseur**. Chaque VM a son propre système d'exploitation complet, et elle se comporte comme une machine à part entière.

```
┌─────────────────────┐ ┌─────────────────────┐
│ front-end, back-end │ │ base de données     │
├─────────────────────┤ ├─────────────────────┤
│ son système         │ │ son système         │
└─────────────────────┘ └─────────────────────┘
┌───────────────────────────────────────────────┐
│                  hyperviseur                  │
├───────────────────────────────────────────────┤
│                  la machine                   │
└───────────────────────────────────────────────┘
```

La répartition est libre. On peut réunir le front-end et le back-end sur une même VM. On peut aussi réserver une VM à la base de données, pour des raisons de droits, parce que tout le monde n'a pas à l'administrer, ou pour régler cette VM finement selon les besoins de la base.

Les pièces sont maintenant bien séparées, mais chaque VM emporte un système entier : elle occupe souvent plusieurs gigaoctets, et met bien plus longtemps à démarrer qu'un simple programme. Pour tenir plus de charge ou remplacer une panne, on duplique toute la machine.

## Dans des conteneurs : chaque pièce à part, sur un même système

Un **conteneur** fait tourner une pièce à part du reste de la machine, avec ses propres fichiers et ses dépendances, mais sans système d'exploitation complet : tous les conteneurs d'une machine partagent le **noyau**, la partie du système qui gère les programmes et la mémoire. Un outil, le **moteur de conteneurs**, se charge de les lancer.

```
┌───────────┐ ┌───────────┐ ┌─────────────────┐
│ front-end │ │ back-end  │ │ base de données │
│ ses dép.  │ │ ses dép.  │ │ ses dépendances │
└───────────┘ └───────────┘ └─────────────────┘
┌───────────────────────────────────────────────┐
│               moteur de conteneurs            │
├───────────────────────────────────────────────┤
│            système d'exploitation             │
├───────────────────────────────────────────────┤
│                   la machine                  │
└───────────────────────────────────────────────┘
```

Comparez ce schéma au précédent : le système de chaque VM a disparu. Un conteneur est donc plus léger qu'une VM, il démarre bien plus vite, et il se duplique facilement. La contrepartie est une isolation moins forte, puisque le noyau est commun.

## Avec un orchestrateur : des conteneurs sur plusieurs machines

Quelques conteneurs sur une machine se gèrent à la main. Quand il y en a beaucoup, répartis sur plusieurs machines, il faut un logiciel qui décide où lancer chacun, qui le relance s'il tombe et qui en ajoute quand la charge monte. Ce logiciel est un **orchestrateur**, et Kubernetes et Docker Swarm en sont des exemples. Il suppose d'abord de savoir faire tourner des conteneurs, et il ajoute sa propre complexité : il répond à un besoin, il n'est pas une étape obligatoire.

## Ces possibilités se combinent

Aucune de ces façons n'est la meilleure dans tous les cas, et elles coexistent souvent dans une même entreprise. Passer par un hébergeur ou un cloud n'en ajoute pas une cinquième : on y loue ces mêmes serveurs, machines virtuelles ou orchestrateurs, et certaines offres vous cachent ce choix. Des conteneurs tournent couramment à l'intérieur de VM, et une base de données peut rester sur sa propre VM pendant que le reste de l'application passe en conteneurs. Ce tableau résume ce qui les distingue.

| | Ce qui sépare les pièces | Pour tenir plus de charge | Ce qu'il faut gérer en plus |
|---|---|---|---|
| **Serveur physique** | rien, sauf à prendre une machine par pièce | du matériel en plus | les conflits entre dépendances |
| **Machines virtuelles** | un système complet par VM | une VM de plus | un hyperviseur, et un système par VM |
| **Conteneurs** | une isolation fournie par le noyau commun | un conteneur de plus | un moteur, et le paquet de chaque pièce à préparer |
| **Orchestrateur** | la même, sur plusieurs machines | l'orchestrateur en ajoute lui-même | un cluster, c'est-à-dire un groupe de machines |

> 📖 [De la machine physique aux conteneurs, vue d'ensemble de Kubernetes](https://kubernetes.io/docs/concepts/overview/) · [Le modèle client-serveur, MDN](https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Server-side/First_steps/Client-Server_overview)

## Récap

- Une application web se compose souvent d'un front-end, d'un back-end et d'une base de données, chacun avec ses dépendances.
- Déployer, c'est installer ces pièces sur des machines : directement, dans des machines virtuelles, dans des conteneurs, ou avec un orchestrateur.
- Une VM a son propre système, un conteneur partage le noyau de la machine.

```quiz
prompt: "Quelle différence principale sépare une machine virtuelle d'un conteneur ?"
answers:
  - "La machine virtuelle a son propre système d'exploitation, le conteneur partage le noyau de la machine"
  - "Le conteneur a besoin d'un serveur physique, pas la machine virtuelle"
  - "La machine virtuelle ne peut héberger qu'une seule pièce de l'application"
correct: 1
explanation: |
  Chaque VM emporte un système complet, d'où son poids et son temps de démarrage. Un conteneur n'emporte que la pièce et ses dépendances. Rien n'empêche par ailleurs de réunir plusieurs pièces sur une même VM.
```

```ack
J'ai compris
```
