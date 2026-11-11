---
title: "Partie C : l'infra, du reverse proxy à la vue d'ensemble"
description: "Un dossier infra assemblé avec include : Traefik, puis les journaux et les métriques, et Portainer pour finir"
---

PetClinic tourne, avec sa base, mais il publie lui-même ses ports, et personne ne voit ce qui s'y passe. Sur un serveur, ce travail revient à une **infra** partagée par toutes les applications : un reverse proxy, qui est la seule porte d'entrée, et une pile d'observabilité, qui garde les journaux et les métriques. Dans cette partie, vous montez cette infra dans son propre dossier, `~/byte-layers/docker/l10/prod/infra`, et vous y branchez PetClinic.

L'infra n'est pas un seul gros fichier. Un fichier Compose **parent** assemble plusieurs fichiers, un par fonction, avec la clé `include`. Vous l'enrichirez au fil des chapitres :

| Chapitre | Ce que vous ajoutez à l'infra | Ce que PetClinic y gagne |
|---|---|---|
| Installer Traefik dans le dossier infra | le fichier parent, et Traefik | rien encore |
| Brancher PetClinic et Adminer sur Traefik | rien | une seule porte d'entrée, et plus aucun port publié |
| Collecter les journaux avec Loki et Alloy | Loki, Alloy et Grafana | ses journaux, cherchables dans Grafana |
| Mesurer avec Prometheus et l'agent JMX exporter | Prometheus | ses métriques JVM, sans modifier son code |
| Finir avec une vue d'ensemble dans Portainer | Portainer, sous un profil de développement | une interface sur tout ce qui tourne |

Un dernier chapitre fait le bilan, nettoie le poste et ouvre sur les plateformes qui font ce travail pour vous. Comptez environ 1 h 30 pour cette partie.

Voici les ports et les adresses que vous utiliserez. À partir du chapitre sur le branchement, tout passe par Traefik, sur un seul port :

| Adresse | Ce qui répond |
|---|---|
| `http://localhost:28402/` | PetClinic |
| `http://localhost:28402/adminer/` | Adminer, avec le profil `dev` |
| `http://localhost:28402/grafana/` | Grafana |
| `http://localhost:28402/portainer/` | Portainer, avec le profil `dev` |
| `http://localhost:28403/dashboard/` | le tableau de bord de Traefik |
