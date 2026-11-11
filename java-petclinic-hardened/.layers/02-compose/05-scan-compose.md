---
title: "Facultatif : scanner le fichier Compose avec KICS"
description: "Passer le fichier Compose durci à un scanner de configuration, et lire ce qu'il reste à dire"
---

> 🔍 **Chapitre facultatif.** Ce scan télécharge l'image de KICS, environ 200 Mo, et aucune base de vulnérabilités. Vous pouvez aussi le lire sans lancer les commandes : le résultat attendu est donné.

Trivy a relu le `Dockerfile`. [KICS](https://docs.kics.io/latest/), un scanner de configuration de Checkmarx, sait lire les fichiers Compose : il vérifie les healthchecks, les limites de ressources, les capabilities, les ports publiés, les mots de passe en clair, et bien d'autres règles. Le cours « Scanner un Dockerfile, une image et un fichier Compose » le présente en détail.

## Lancer KICS sur le fichier Compose

KICS tourne dans un conteneur, qui reçoit seulement le dossier du projet. Comme pour Trivy, l'image est désignée par sa version et par son empreinte : en 2026, des [tags `checkmarx/kics`](https://thehackernews.com/2026/04/malicious-kics-docker-images-and-vs.html) ont été remplacés par des versions malveillantes. `-p compose.yaml` limite le scan à ce seul fichier, et `--disable-secrets` désactive la recherche de mots de passe en clair, inutile ici puisqu'ils vivent dans des secrets :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker run --rm -v "$PWD:/work" -w /work \
  checkmarx/kics:v2.2.0@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003 \
  scan -p compose.yaml --no-progress --disable-secrets
```

La fin de la sortie résume le résultat par sévérité :

```
Results Summary:
CRITICAL: 0
HIGH: 0
MEDIUM: 0
LOW: 0
INFO: 1
TOTAL: 1
```

Le seul résultat, de niveau INFO, s'intitule `Shared Volumes Between Containers`. KICS signale ce volume nommé, parce qu'un volume partagé par plusieurs conteneurs peut leur servir à s'échanger des fichiers. Ici, seul `db` monte `db_data` : c'est une information, pas un défaut. KICS a aussi compris les ancres YAML, et il voit le durcissement que chaque service reçoit par la fusion de `x-hardening`.

Le même scan, lancé avant l'ajout du healthcheck d'Adminer, trouvait un défaut de plus, `Healthcheck Not Set`, de niveau MEDIUM. C'est la raison de ce healthcheck écrit en PHP.

## Supprimer l'image de KICS

Une fois le scan lancé, supprimez l'image de KICS, qui ne sert plus :

```exec
docker rmi checkmarx/kics:v2.2.0@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003
```

```ack
J'ai lu, ou lancé, le scan du fichier Compose
```
