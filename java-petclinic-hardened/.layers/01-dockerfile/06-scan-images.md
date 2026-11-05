---
title: "Facultatif : comparer les vulnérabilités de deux images"
description: "Scanner l'image Ubuntu et l'image distroless avec Trivy, et découvrir où se trouvent vraiment les failles"
---

> 🔍 **Chapitre facultatif, et lourd.** Pour analyser une image Java, Trivy télécharge deux bases : celle des vulnérabilités des systèmes, environ 1,6 Go, et celle des bibliothèques Java, environ 1,5 Go. Sur un serveur de formation partagé, ces 3 Go par poste remplissent vite le disque. Vous pouvez aussi le lire sans lancer les commandes : les résultats sont donnés. Pour éviter de les lancer par mégarde, les commandes de ce chapitre sont affichées sans bouton d'exécution : copiez-les dans le terminal si vous décidez de les lancer.

Le chapitre sur distroless mesurait la taille des images. Celui-ci compare ce qu'elles contiennent de **vulnérabilités connues** (des CVE, pour *Common Vulnerabilities and Exposures*). Le résultat surprend souvent, et il dit où porter l'effort.

## Les deux images comparées

Vous comparez les images `3-multistage` et `4-distroless`, que vous avez encore toutes les deux. Elles contiennent le même JAR, et seules la distribution de base et la façon de lancer Java diffèrent : toute différence de résultat viendra donc de la base.

## Scanner les deux images

Trivy lit une image depuis une archive, que `docker save` produit. Il n'a ainsi pas besoin d'accéder au socket Docker, qui donnerait tous les droits sur le moteur. Le volume `layers-l10-scan-cache` garde les bases téléchargées, pour qu'un second scan ne les retélécharge pas :

```bash
cd ~/layers-l10/prod/petclinic
docker save layers-l10-petclinic:4-distroless -o distroless.tar
docker run --rm -v "$PWD:/work" -w /work -v layers-l10-scan-cache:/cache \
  aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
  image --input distroless.tar --scanners vuln --ignore-unfixed --severity HIGH,CRITICAL --cache-dir /cache
```

| Option | Rôle |
|---|---|
| `--input distroless.tar` | lire l'image depuis l'archive |
| `--scanners vuln` | chercher seulement des vulnérabilités, et pas de secrets ni de licences |
| `--ignore-unfixed` | ignorer les failles qui n'ont pas encore de correctif : on ne peut rien en faire aujourd'hui |
| `--severity HIGH,CRITICAL` | ne garder que les deux sévérités les plus graves |
| `--cache-dir /cache` | ranger les bases dans le volume |

Le même scan analyse ensuite l'image Ubuntu. Il réutilise les bases du volume, et il est donc bien plus rapide :

```bash
cd ~/layers-l10/prod/petclinic
docker save layers-l10-petclinic:3-multistage -o multistage.tar
docker run --rm -v "$PWD:/work" -w /work -v layers-l10-scan-cache:/cache \
  aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
  image --input multistage.tar --scanners vuln --ignore-unfixed --severity HIGH,CRITICAL --cache-dir /cache
```

## Lire le résultat

Trivy présente ses résultats par cible. Il analyse d'abord les paquets du système, puis les bibliothèques Java contenues dans le JAR. Voici les résultats du 5 novembre 2026, avec ces options : les failles HIGH et CRITICAL qui ont un correctif.

| Cible | Image Ubuntu (`noble`) | Image distroless (`debian13`) |
|---|---|---|
| les paquets du système | 2 HIGH | aucune |
| les bibliothèques du JAR | 7 CRITICAL, 7 HIGH | 7 CRITICAL, 7 HIGH |

Ces chiffres changent chaque semaine, au rythme des nouvelles failles publiées et des correctifs : vous trouverez sans doute d'autres valeurs. Deux enseignements, en revanche, ne changent pas.

Le premier : distroless supprime les failles **du système**, parce qu'il n'y a presque plus de système. C'est le gain attendu.

Le second, plus important : les failles les plus graves sont dans **le JAR**, et elles sont les mêmes dans les deux images. Elles viennent des dépendances de PetClinic : le serveur Tomcat embarqué (`tomcat-embed-core` 11.0.22), Spring MVC (`spring-webmvc` 7.0.8), la bibliothèque JSON Jackson et le pilote PostgreSQL. Aucune image de base ne les corrige. Il faut mettre à jour ces dépendances dans le `pom.xml`, le plus souvent en montant la version de Spring Boot, et c'est le travail de l'équipe de développement. Le scan d'image sert donc aussi à lui transmettre cette liste.

⚖️ Sans `--ignore-unfixed`, l'image distroless affiche 8 failles système HIGH ce même jour, au lieu d'aucune. Debian publie en effet les failles connues qu'il n'a pas encore corrigées, ou qu'il juge sans risque pour ses paquets. Comparer deux images sans cette option, c'est comparer surtout la politique de publication de deux distributions.

[Grype](https://github.com/anchore/grype) donne un second avis sur la même archive, avec ses propres bases. Le cours « Scanner un Dockerfile, une image et un fichier Compose » montre comment le lancer.

## Libérer l'espace disque du scan

Si vous avez lancé les scans, supprimez les archives, le volume des bases et l'image de Trivy. Ce sont les plus gros fichiers de ce cas pratique :

```bash
cd ~/layers-l10/prod/petclinic && rm -f distroless.tar multistage.tar
docker volume rm layers-l10-scan-cache
docker rmi aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
```

```ack
J'ai lu, ou lancé, la comparaison des vulnérabilités
```
