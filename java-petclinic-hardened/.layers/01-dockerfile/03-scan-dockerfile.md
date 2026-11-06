---
title: "Facultatif : scanner le Dockerfile avec Trivy"
description: "Vérifier qu'un Dockerfile n'a plus aucune mauvaise configuration connue, et comparer avec l'image naïve"
---

> 🔍 **Chapitre facultatif.** Ce scan télécharge l'image de Trivy, environ 250 Mo, et quelques centaines de kilo-octets de règles. Vous pouvez aussi le lire sans lancer les commandes : le résultat attendu est donné.

Votre `Dockerfile` corrige les défauts que vous avez relevés à la main. Un scanner de configuration fait ce travail de relecture automatiquement, avec des règles connues et numérotées, et une chaîne d'intégration continue peut le lancer à chaque modification.

## Les outils de scan, en bref

Le cours « Scanner un Dockerfile, une image et un fichier Compose » détaille ces outils et leurs résultats. Pour rappel, chacun a sa spécialité :

| Outil | Ce qu'il lit | Ce qu'il cherche |
|---|---|---|
| [Trivy](https://trivy.dev/docs/latest/) | un `Dockerfile` (`trivy config`), une image (`trivy image`) | des erreurs de configuration, puis des vulnérabilités connues |
| [Grype](https://github.com/anchore/grype) | une image | des vulnérabilités connues |
| [KICS](https://docs.kics.io/latest/) | un fichier Compose, Kubernetes, Terraform… | des erreurs de configuration et des mots de passe en clair |

La différence de coût entre les deux commandes de Trivy compte sur un poste partagé. `trivy config` lit des fichiers texte avec des règles légères, et il ne télécharge aucune base de vulnérabilités. `trivy image`, au contraire, télécharge des bases qui dépassent le gigaoctet : le chapitre facultatif sur les images y revient.

## Lancer Trivy sur le Dockerfile

Trivy tourne dans un conteneur, qui reçoit seulement le dossier du projet. L'image est désignée par sa version **et** par son empreinte `sha256`. En 2026, des [images `aquasec/trivy`](https://www.docker.com/blog/trivy-supply-chain-compromise-what-docker-hub-users-should-know/) ont été remplacées par des versions malveillantes sous un tag existant : un tag peut être réécrit, une empreinte désigne toujours le même contenu.

Vous visez le seul fichier `Dockerfile`, et non le dossier entier : le dépôt de PetClinic contient d'autres fichiers que Trivy sait lire, comme la configuration de son dossier `.devcontainer/`, qui ne vous concernent pas ici :

```exec
cd ~/layers-l10/prod/petclinic && docker run --rm -v "$PWD:/work" -w /work \
  aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
  config Dockerfile
```

La fin de la sortie résume le résultat. Le `0` de la colonne `Misconfigurations` veut dire qu'aucune règle n'a échoué :

```
┌────────────┬────────────┬───────────────────┐
│   Target   │    Type    │ Misconfigurations │
├────────────┼────────────┼───────────────────┤
│ Dockerfile │ dockerfile │         0         │
└────────────┴────────────┴───────────────────┘
```

Vous avez remplacé le `Dockerfile` naïf, et vous ne pouvez donc plus le scanner. Lancé sur lui, ce même scan trouvait trois défauts sur les 27 règles appliquées :

| Règle | Sévérité | Ce qu'elle dit |
|---|---|---|
| `DS-0001` | MEDIUM | aucun tag dans le `FROM` |
| `DS-0002` | HIGH | aucune instruction `USER` : le conteneur tourne en root |
| `DS-0026` | LOW | aucune instruction `HEALTHCHECK` |

## Ce que le scan ne voit pas

Zéro défaut ne veut pas dire zéro problème. Deux défauts de l'image naïve échappent à ces règles : le `CMD` en forme shell, qui empêche l'arrêt propre, et le `COPY .` placé avant la compilation, qui ruine le cache. Un linter spécialisé comme [Hadolint](https://github.com/hadolint/hadolint) en attrape davantage, mais aucun outil ne remplace la relecture : un scanner vérifie des règles connues, pas l'intention de celui qui a écrit le fichier.

Une fois le scan lancé, vous pouvez supprimer l'image de Trivy, si vous ne comptez pas faire l'autre chapitre facultatif :

```exec
docker rmi aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
```

```ack
J'ai lu, ou lancé, le scan du Dockerfile
```
