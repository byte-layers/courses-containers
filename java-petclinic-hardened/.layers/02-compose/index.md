---
title: "Partie B : PetClinic et PostgreSQL avec Compose"
description: "Des secrets, une base, un fichier Compose durci et un profil de développement"
---

Votre image est prête, et il lui manque une vraie base de données. Dans cette partie, vous décrivez PetClinic et PostgreSQL dans un fichier Compose. Vous le rendez ensuite aussi solide que le `Dockerfile` : un mot de passe qui ne passe jamais par une variable d'environnement, des healthchecks, des réseaux nommés, des ressources limitées, des journaux communs et un outil d'administration réservé au développement.

Vous construisez le fichier en quatre chapitres, et chacun ajoute une couche :

| Chapitre | Ce que vous ajoutez |
|---|---|
| Préparer les secrets de la base | le mot de passe, généré et rangé hors du fichier Compose |
| Décrire PetClinic et sa base dans un fichier Compose | les deux services, leurs réseaux, leur volume et l'ordre de démarrage |
| Durcir les services et mettre en commun les réglages | le durcissement, les limites de ressources, et les ancres YAML qui évitent de le répéter |
| Ajouter Adminer avec un profil de développement | une interface pour la base, lancée seulement sur demande |

Un chapitre facultatif scanne enfin le fichier Compose avec KICS. Comptez environ une heure pour cette partie.

Vous travaillez toujours dans `~/layers-l10/prod/petclinic`, avec le `Dockerfile` distroless de la partie A.
