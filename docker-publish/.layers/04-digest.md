---
title: "Retrouver une image, par son tag ou son digest"
description: "Une autre machine qui tire l'image, un tag qui bouge, un digest qui reste"
---

Publier ne sert à rien si l'on ne peut pas récupérer l'image ailleurs. Vous n'avez qu'une machine, mais vous pouvez la mettre dans la même situation qu'une autre : il suffit d'y effacer votre image.

## Partir de rien

Retirez les noms locaux de votre image. `docker rmi` retire un nom, et supprime l'image quand il ne lui en reste aucun. Le registre, lui, garde sa copie :

```exec
docker rmi layers-l4-hello:1.0 localhost:28340/layers-l4-hello:1.0 localhost:28340/layers-l4-hello:latest
```

Lancez ensuite l'image par son nom complet. Ne la trouvant plus sur votre machine, Docker la télécharge depuis votre registre, exactement comme il le ferait sur un serveur où elle n'a jamais été :

```exec
docker run --rm localhost:28340/layers-l4-hello:1.0
```

Vous lisez `Unable to find image … locally`, puis le téléchargement, puis `Bonjour depuis la version 1`. C'est tout l'intérêt d'un registre : construire à un endroit, lancer à un autre.

```verify
if ! docker image inspect localhost:28340/layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "L'image n'est pas redescendue du registre. Lancez le docker run de cette section."
  exit 1
fi
if docker image inspect layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "Le nom local layers-l4-hello:1.0 existe encore. Lancez le docker rmi de cette section."
  exit 1
fi
echo "L'image est redescendue du registre."
```

## Noter son digest

Avant de changer quoi que ce soit, gardez le digest de cette version dans un fichier. Docker l'a noté en téléchargeant l'image, dans le champ `RepoDigests` de sa fiche, et `index … 0` en prend la première valeur :

```exec
docker image inspect localhost:28340/layers-l4-hello:1.0 --format '{{index .RepoDigests 0}}' > ~/layers-l4/digest-v1.txt
cat ~/layers-l4/digest-v1.txt
```

Vous lisez `localhost:28340/layers-l4-hello@sha256:…`. Ce nom vous servira juste après.

Il ne faut pas le confondre avec l'identifiant affiché par `docker images`. Ce dernier est propre à votre moteur : selon sa configuration, il coïncide ou non avec le digest. Seul le digest est le même pour toutes les machines qui tirent cette image.

```verify
if ! grep -qE '^localhost:28340/layers-l4-hello@sha256:[0-9a-f]{64}$' ~/layers-l4/digest-v1.txt 2>/dev/null; then
  echo "~/layers-l4/digest-v1.txt ne contient pas un nom suivi d'un digest. Relancez les commandes de cette section."
  exit 1
fi
echo "Le digest de la version 1 est noté."
```

## Déplacer un tag

Imaginez maintenant qu'un collègue corrige l'image et la republie sous le même tag, ce qui arrive tous les jours. Modifiez le Dockerfile pour simuler ce qu'il a fait, puis reconstruisez et poussez l'image sous le même nom. `sed -i.bak` remplace le texte directement dans le fichier, et garde une copie en `.bak` :

```exec
sed -i.bak 's/version 1/version 2/' ~/layers-l4/app/Dockerfile
docker build -t localhost:28340/layers-l4-hello:1.0 ~/layers-l4/app
docker push localhost:28340/layers-l4-hello:1.0
```

Le digest affiché par le `push` n'est plus le même, puisque le contenu a changé. Quelle version va s'afficher, 1 ou 2 ? Faites votre prévision, puis lancez l'image avec le même nom qu'avant :

```exec
docker run --rm localhost:28340/layers-l4-hello:1.0
```

Vous lisez `Bonjour depuis la version 2` : **le même nom donne une autre image**. Voilà pourquoi un tag ne suffit pas pour savoir ce qui tourne en production. Sur un serveur qui avait déjà l'ancienne image, ce serait pire : tant qu'on n'y lance pas `docker pull`, il continue d'exécuter la version 1 sous le même nom.

```verify
if ! docker run --rm localhost:28340/layers-l4-hello:1.0 | grep -q 'version 2'; then
  echo "L'image taguée 1.0 n'affiche pas la version 2. Relancez les commandes de cette section."
  exit 1
fi
echo "Le tag 1.0 désigne désormais la version 2."
```

## Retrouver l'ancienne

Le registre n'a pas perdu la version 1 : seule l'étiquette a bougé. Pour le prouver, effacez d'abord la copie qui reste sur votre machine, puis demandez cette version par son digest. `$(cat …)` place dans la commande le nom que vous aviez noté :

```exec
docker rmi "$(cat ~/layers-l4/digest-v1.txt)"
docker run --rm "$(cat ~/layers-l4/digest-v1.txt)"
```

Selon votre installation, `docker rmi` peut répondre `No such image` : Docker n'a pas gardé ce nom-là en local quand vous avez reconstruit, et vous pouvez l'ignorer. Docker télécharge ensuite cette version, puis vous lisez `Bonjour depuis la version 1`. Quel que soit le nombre de fois où le tag a bougé, ce nom donnera toujours cette image, et c'est pourquoi on l'utilise pour figer ce qui part en production.

```verify
if [ ! -s ~/layers-l4/digest-v1.txt ]; then
  echo "Le fichier ~/layers-l4/digest-v1.txt est vide ou absent. Reprenez la section « Noter son digest »."
  exit 1
fi
if ! docker run --rm "$(cat ~/layers-l4/digest-v1.txt)" | grep -q 'version 1'; then
  echo "L'image désignée par ce digest n'affiche pas la version 1."
  exit 1
fi
echo "Le digest désigne toujours la version 1."
```

> 📖 [Tirer une image par son digest](https://docs.docker.com/reference/cli/docker/image/pull/) · [`docker image inspect`](https://docs.docker.com/reference/cli/docker/image/inspect/)

## Récap

- Un registre permet de construire à un endroit et de lancer à un autre.
- Republier sous le même tag déplace l'étiquette : le même nom donne une autre image.
- Le digest désigne toujours la même image, tant que le registre la garde.

## Questions

```quiz
title: "Tag et digest"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un serveur a déjà `app:1.0` et l'équipe republie une nouvelle image sous ce tag. Que fait le serveur au prochain `docker run app:1.0` ?"
    answers:
      - "Il télécharge la nouvelle image"
      - "Il lance l'ancienne, tant qu'on n'y fait pas `docker pull`"
      - "Il refuse de démarrer"
    correct: 2
    explanation: "`docker run` ne télécharge que ce qui manque. Le serveur a une image sous ce nom : il la lance, même si le registre en a une autre."
  - prompt: "Quelle écriture garantit de toujours lancer la même image ?"
    answers:
      - "`app:1.0`"
      - "`app:latest`"
      - "`app@sha256:…`"
    correct: 3
    explanation: "Seul le digest est calculé à partir du contenu. Les tags sont des étiquettes."
```
