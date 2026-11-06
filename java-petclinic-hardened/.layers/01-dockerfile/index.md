---
title: "Partie A : le Dockerfile, du naïf au distroless"
description: "Du Dockerfile naïf à l'image distroless, en mesurant à chaque étape"
---

Dans cette partie, vous construisez quatre versions de l'image de PetClinic, et chacune corrige les défauts de la précédente. Vous partez du `Dockerfile` que l'on écrit quand on veut seulement que ça marche. Vous livrez ensuite le JAR compilé par une chaîne d'intégration continue, puis vous faites la compilation dans l'image avec un multi-stage, et vous terminez avec une image distroless.

Les quatre images portent le même nom, `layers-l10-petclinic`, avec un tag par étape. Vous pourrez ainsi les comparer à la fin :

| Tag | Chapitre | L'idée |
|---|---|---|
| `1-naive` | Lancer PetClinic avec un Dockerfile naïf | tout dans une image, sans réfléchir |
| `2-jar` | Livrer dans une image durcie le JAR compilé par la CI | une image d'exécution seule, et durcie |
| `3-multistage` | Construire le JAR dans l'image avec le multi-stage | la compilation et l'exécution dans un même `Dockerfile` |
| `4-distroless` | Passer à une image distroless, et comparer les tailles | une image d'exécution sans shell ni gestionnaire de paquets |

Deux chapitres facultatifs scannent le résultat : le premier lit le `Dockerfile`, le second compare les vulnérabilités de deux images. Un dernier chapitre supprime les images devenues inutiles et résume la partie. Comptez environ 1 h 30, dont une dizaine de minutes de téléchargements et de compilations.
