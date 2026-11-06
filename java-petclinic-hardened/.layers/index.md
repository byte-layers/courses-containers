---
title: "Livrer une application Java sécurisée (hardened) : Dockerfile, Compose et infra"
description: "Cas pratique de synthèse sur une vraie application Spring Boot, PetClinic : un Dockerfile durci jusqu'au multi-stage et à distroless, un fichier Compose sécurisé avec sa base, puis le routage, les logs et les métriques."
tags:
  - lab
  - docker
  - containers
  - security
  - java
difficulty: intermediate
duration: 225
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce cas pratique reprend tout ce que vous avez appris sur Docker, sur une vraie application : [Spring PetClinic](https://github.com/spring-projects/spring-petclinic), l'application de démonstration du framework Java Spring Boot. Elle gère une clinique vétérinaire, avec ses propriétaires, leurs animaux et les visites. Vous allez la livrer comme on la livrerait en production. Le fil rouge est la **qualité** et la **sécurité** : des versions d'image précises, un utilisateur sans droits, des healthchecks, un `Dockerfile` sans mauvaise configuration connue, des secrets hors des variables d'environnement, des ressources limitées et des journaux exploitables.

Vous complétez vous-même les `# TODO`. Le bouton de vérification contrôle le résultat, les indices se dévoilent un par un, et la solution reste en dernier recours.

**Niveau** : intermédiaire. Vous savez écrire un `Dockerfile` avec `FROM`, `COPY`, `RUN`, `USER`, `EXPOSE` et `HEALTHCHECK`, comme dans « Écrire le Dockerfile d'une application ». Vous savez lancer un projet Compose avec des réseaux, des volumes, un `healthcheck` et un `depends_on`, et vous avez déjà placé des applications derrière Traefik avec des labels, comme dans « Deux applications derrière nginx, puis Traefik ». Vous n'avez besoin de connaître ni Java ni Maven : chaque commande propre à Java est expliquée. Ce qui est nouveau est guidé pas à pas, en particulier le **multi-stage** et l'**observabilité** (les journaux et les métriques).

**Ce qu'il faut** : Docker et Compose qui répondent, un terminal bash ou zsh (sous Windows, celui de WSL), `curl`, `openssl` et `sha256sum`, un éditeur de texte, les ports **28400** à **28409** libres, environ 1,5 Go de mémoire, la consommation mesurée de l'ensemble des conteneurs de la partie C, et 5 Go d'espace disque pour les images et les caches. Tout ce que vous créez porte le préfixe `layers-l10-`, et vos fichiers vivent dans `~/layers-l10/prod`.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

## Les trois parties

Le cas pratique avance comme un vrai projet : d'abord l'image, puis l'application avec sa base, puis ce qui l'entoure sur un serveur.

| Partie | Ce que vous construisez | Ce qui est nouveau |
|---|---|---|
| A. Le `Dockerfile` | une image partie d'un `Dockerfile` naïf, durcie, construite en multi-stage, puis distroless | le multi-stage, l'image distroless |
| B. Le fichier Compose | PetClinic et PostgreSQL, avec secrets, healthchecks, limites, journaux communs et un profil de développement | les secrets, les ancres YAML `x-`, les profils |
| C. L'infra | Traefik, puis une pile de journaux et de métriques, assemblés avec `include`, et une vue d'ensemble pour finir | `include`, Loki, Alloy, Prometheus, Grafana, l'agent JMX exporter, Portainer |

## Les chapitres facultatifs : les scans

Certains chapitres portent un titre qui commence par « Facultatif ». Ils scannent un `Dockerfile` ou une image, avec les outils vus dans « Scanner un Dockerfile, une image et un fichier Compose ». Ils montrent le résultat que l'on attend, et vous pouvez les lire sans lancer les commandes.

> 🔍 **Pourquoi facultatifs ?** Un scanner télécharge son image, ses règles et, pour les images, des bases de vulnérabilités. Pour une application Java, cela représente environ 3 Go. Sur un serveur de formation partagé par plusieurs postes, ce volume multiplié par le nombre de stagiaires remplit vite le disque.

## Organiser le dossier de travail comme un serveur

Sur un serveur qui héberge des applications Docker, on range souvent chaque projet Compose dans son dossier, sous une racine commune comme `/srv/docker`. Ce cas pratique suit la même organisation, avec `~/layers-l10/prod` pour racine. Voici où vous arriverez à la fin des trois parties :

```
~/layers-l10/prod/
├── petclinic/          # partie A et partie B : le code, le Dockerfile, le fichier Compose
└── infra/              # partie C : ce que partagent toutes les applications du serveur
    ├── compose.yaml    # le fichier parent, qui inclut les deux suivants
    ├── traefik/
    └── observability/
```

L'application et l'infra vivent dans deux dossiers séparés, parce qu'elles n'ont pas le même cycle de vie. On met à jour PetClinic plusieurs fois par semaine. Le reverse proxy et la pile de journaux, eux, servent toutes les applications du serveur, et ils ne doivent pas s'arrêter quand une application redémarre.

```ack
J'ai compris le plan, et je sais repérer les chapitres facultatifs
```
