---
title: "Retrouver une image, par son tag ou son digest"
description: "Une autre machine qui télécharge l'image, un tag republié, un digest qui retrouve l'ancienne version"
---

Publier ne sert à rien si l'on ne peut pas récupérer l'image ailleurs. Vous n'avez qu'une machine, mais vous pouvez la mettre dans la même situation qu'une autre : il suffit d'y effacer votre image. Cette étape s'en sert pour voir ce que donne un tag quand il a bougé, et comment le digest, présenté dans [Nommer une image : registre, tag, digest](https://byte-layers.com/fr/bits/image-reference), permet de retrouver une version précise.

## Effacer l'image locale pour simuler une autre machine

Retirez les noms locaux de votre image. `docker rmi` retire un nom, et supprime l'image quand il ne lui en reste aucun. Le registre, lui, garde sa copie :

```exec
docker rmi layers-l4-hello:1.0 localhost:28340/layers-l4-hello:1.0 localhost:28340/layers-l4-hello:latest
```

Vérifiez qu'il ne reste rien. `grep` n'affiche aucune ligne quand il ne trouve pas le mot :

```exec
docker images | grep layers-l4-hello
```

## Télécharger l'image depuis le registre

Vous êtes maintenant dans la situation d'un serveur où cette image n'a jamais été : seule sa base, `alpine:3.22`, s'y trouve déjà, et Docker ne la téléchargera pas de nouveau. Téléchargez l'image par son nom complet, puis lancez-la :

```exec
docker pull localhost:28340/layers-l4-hello:1.0
docker run --rm localhost:28340/layers-l4-hello:1.0
```

Docker télécharge depuis votre registre et affiche le digest, puis le conteneur écrit sa phrase :

```text
1.0: Pulling from layers-l4-hello
Digest: sha256:7eb048320768fb5057b1bceb27e94612ca483caf8fc66f9f7a28c4ac9ea9de32
Status: Downloaded newer image for localhost:28340/layers-l4-hello:1.0
localhost:28340/layers-l4-hello:1.0
Bonjour depuis la version 1
```

C'est tout l'intérêt d'un registre : construire à un endroit, lancer à un autre.

⚖️ Une limite à connaître : une image est construite pour un type de processeur. Une image construite seulement sur un Mac récent (`arm64`) échoue sur un serveur `amd64`, avec le message `exec format error`. L'option `--platform` de `docker build` permet de viser une autre architecture.

```verify
if ! docker image inspect localhost:28340/layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "L'image n'est pas redescendue du registre. Lancez le docker pull de cette section."
  exit 1
fi
if docker image inspect layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "Le nom local layers-l4-hello:1.0 existe encore. Lancez le docker rmi de la section précédente."
  exit 1
fi
echo "L'image est redescendue du registre."
```

## Noter le digest de cette version

Avant de changer quoi que ce soit, gardez ce digest dans un fichier, car vous allez en avoir besoin. Docker l'a noté dans la fiche de l'image en la téléchargeant : `docker image inspect` lit cette fiche, `--format` en extrait le champ `RepoDigests`, et `index … 0` en prend la première valeur.

```exec
docker image inspect localhost:28340/layers-l4-hello:1.0 --format '{{index .RepoDigests 0}}' > ~/layers-l4/digest-v1.txt
cat ~/layers-l4/digest-v1.txt
```

Vous lisez le nom du dépôt, un `@`, puis le digest :

```text
localhost:28340/layers-l4-hello@sha256:7eb048320768fb5057b1bceb27e94612ca483caf8fc66f9f7a28c4ac9ea9de32
```

```verify
if ! grep -qE '^localhost:28340/layers-l4-hello@sha256:[0-9a-f]{64}$' ~/layers-l4/digest-v1.txt 2>/dev/null; then
  echo "~/layers-l4/digest-v1.txt ne contient pas un nom suivi d'un digest. Relancez les commandes de cette section."
  exit 1
fi
echo "Le digest de la version 1 est noté."
```

## Republier une correction sous le même tag

Imaginez maintenant qu'une correction soit republiée sous le même tag `1.0`. Rien ne l'interdit : un registre accepte de reposer un tag sur une autre image.

⚖️ Une version comme `1.0` ne devrait pourtant pas se republier : on en crée une nouvelle, comme `2.0`, pour que le nom continue de dire ce qu'il contient. On le fait ici pour voir ce qui se passe quand cette règle n'est pas respectée. Certains tags, eux, bougent par construction, comme `latest` ou `1.30`, qui suivent les correctifs.

Modifiez la phrase du Dockerfile, dans votre éditeur ou avec cette commande :

```exec
cat > ~/layers-l4/app/Dockerfile <<'EOF'
FROM alpine:3.22
CMD ["echo", "Bonjour depuis la version 2"]
EOF
```

Construisez, posez le nom complet sur cette nouvelle image, et poussez :

```exec
docker build -t layers-l4-hello:2.0 ~/layers-l4/app
docker tag layers-l4-hello:2.0 localhost:28340/layers-l4-hello:1.0
docker push localhost:28340/layers-l4-hello:1.0
```

Le digest affiché en fin de publication n'est plus celui de votre fichier, puisque le contenu a changé. Un raccourci existe : `docker build -t localhost:28340/layers-l4-hello:1.0 …` pose directement le nom complet au build, sans passer par `docker tag`.

```verify
if ! docker image inspect layers-l4-hello:2.0 >/dev/null 2>&1; then
  echo "L'image layers-l4-hello:2.0 n'existe pas. Lancez le docker build de cette section."
  exit 1
fi
A=$(docker image inspect layers-l4-hello:2.0 --format '{{.Id}}')
B=$(docker image inspect localhost:28340/layers-l4-hello:1.0 --format '{{.Id}}' 2>/dev/null)
if [ "$A" != "$B" ]; then
  echo "Le nom localhost:28340/layers-l4-hello:1.0 ne désigne pas la nouvelle image. Lancez le docker tag de cette section."
  exit 1
fi
if ! docker push localhost:28340/layers-l4-hello:1.0 >/dev/null 2>&1; then
  echo "Le registre refuse la publication. Vérifiez qu'il tourne avec : docker ps"
  exit 1
fi
echo "La nouvelle image est publiée sous le tag 1.0."
```

## Effacer la copie locale, et voir ce que le registre donne sous ce tag

Si vous lanciez l'image tout de suite, Docker prendrait la copie construite à l'instant sur votre machine, sans interroger le registre, et cela ne prouverait rien. Pour savoir ce que recevra une autre machine, effacez d'abord vos noms locaux :

```exec
docker rmi layers-l4-hello:2.0 localhost:28340/layers-l4-hello:1.0
```

Quelle version va s'afficher, 1 ou 2 ? Faites votre prévision, puis lancez l'image avec le même nom qu'au début de cette étape :

```exec
docker run --rm localhost:28340/layers-l4-hello:1.0
```

La ligne `Unable to find image` prouve que l'image vient bien du registre, et la dernière ligne donne la réponse. Comparez aussi la ligne `Digest:` avec le digest noté dans votre fichier :

```text
Unable to find image 'localhost:28340/layers-l4-hello:1.0' locally
1.0: Pulling from layers-l4-hello
Digest: sha256:663f7b8e5de908bda0a26ed727c60089233af8fef9bd8eaef6e44c1a9bb34c35
Status: Downloaded newer image for localhost:28340/layers-l4-hello:1.0
Bonjour depuis la version 2
```

**Le même nom donne une autre image**, avec un autre digest. Voilà pourquoi un tag ne suffit pas pour savoir ce qui tourne en production. Un serveur qui avait déjà la première image serait dans un cas plus trompeur encore : `docker run` ne télécharge que ce qui manque, et il continuerait donc d'exécuter la version 1 sous ce nom, tant qu'on n'y lance pas `docker pull`.

```verify
if docker image inspect layers-l4-hello:2.0 >/dev/null 2>&1; then
  echo "Le nom local layers-l4-hello:2.0 existe encore. Lancez le docker rmi de cette section."
  exit 1
fi
if ! docker run --rm --pull always localhost:28340/layers-l4-hello:1.0 2>/dev/null | grep -q 'version 2'; then
  echo "Le registre ne donne pas la version 2 sous le tag 1.0. Reprenez la section précédente."
  exit 1
fi
echo "Sous le tag 1.0, le registre donne désormais la version 2."
```

## Retrouver l'ancienne version par son digest

Le registre devrait avoir gardé la version 1, puisque seule l'étiquette a bougé. Pour le prouver, il faut encore effacer la copie locale, car votre machine a pu garder cette version. Retirez-la, puis demandez-la par le nom que vous aviez noté. `$(cat …)` place dans la commande le contenu du fichier, ce qui vous évite de recopier le digest :

```exec
docker rmi "$(cat ~/layers-l4/digest-v1.txt)"
docker run --rm "$(cat ~/layers-l4/digest-v1.txt)"
```

Docker ne trouve plus l'image sur votre machine, la télécharge depuis le registre, et la dernière ligne donne la réponse :

```text
Unable to find image 'localhost:28340/layers-l4-hello@sha256:7eb0…' locally
...
Bonjour depuis la version 1
```

Quel que soit le nombre de fois où le tag a bougé, ce nom donnera toujours cette image, et c'est pourquoi on l'utilise pour figer ce qui part en production. Une réserve : sur un vrai registre, un nettoyage peut retirer les images qui n'ont plus aucun tag. Gardez donc un tag sur ce que vous voulez retrouver.

```verify
if [ ! -s ~/layers-l4/digest-v1.txt ]; then
  echo "Le fichier ~/layers-l4/digest-v1.txt est vide ou absent. Reprenez la section sur le digest."
  exit 1
fi
if ! docker run --rm "$(cat ~/layers-l4/digest-v1.txt)" | grep -q 'version 1'; then
  echo "L'image désignée par ce digest n'affiche pas la version 1."
  exit 1
fi
echo "Le digest désigne toujours la version 1."
```

> 📖 [Télécharger une image par son digest](https://docs.docker.com/reference/cli/docker/image/pull/) · [`docker image inspect`](https://docs.docker.com/reference/cli/docker/image/inspect/)

## Récap

- Un registre permet de construire à un endroit et de lancer à un autre.
- Republier sous le même tag déplace l'étiquette : le même nom donne une autre image. On ne republie donc pas une version, on en crée une nouvelle.
- Le digest désigne toujours la même image, tant que le registre la garde.

## Questions

```quiz
title: "Tag et digest"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un serveur a déjà `app:1.0` et l'équipe republie une nouvelle image sous ce tag. Que fait le serveur au prochain `docker run app:1.0` ?"
    answers:
      - "Il lance l'ancienne, tant qu'on n'y fait pas `docker pull`"
      - "Il télécharge la nouvelle image"
      - "Il refuse de démarrer"
    correct: 1
    explanation: "`docker run` ne télécharge que ce qui manque. Le serveur a une image sous ce nom : il la lance, même si le registre en a une autre."
  - prompt: "Quelle écriture garantit de toujours lancer la même image ?"
    answers:
      - "`app:1.0`"
      - "`app:latest`"
      - "`app@sha256:…`"
    correct: 3
    explanation: "Seul le digest est calculé à partir du contenu. Les tags sont des étiquettes."
  - prompt: "Vous voulez corriger la version `1.0` d'une image déjà publiée. Quelle est la bonne pratique ?"
    answers:
      - "Republier sous le tag `1.0`"
      - "Supprimer le registre et recommencer"
      - "Publier une nouvelle version, par exemple `1.1`"
    correct: 3
    explanation: "Une version publiée ne se republie pas : le nom doit continuer de dire ce qu'il contient."
```
