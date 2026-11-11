---
title: "Publier une image et la retrouver par son digest"
description: "Lancer un registre, y publier une image, déplacer un tag, puis retrouver l'ancienne version par son digest, à partir d'un cahier des charges, sans guide."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 45
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Vous lancez votre propre registre, vous y publiez une image, une correction déplace son tag, et c'est à vous de retrouver l'ancienne version et de la remettre en avant. Il n'y a **aucune commande à recopier** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker et du registre. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

- **Niveau** : ce challenge suppose ce qu'enseigne le cours [Publier une image : pull, tag, push](https://byte-layers.com/fr/skills/docker-publish), et de savoir écrire un petit Dockerfile.
- **Ce qu'il faut** : Docker qui répond à `docker ps`, `curl`, un éditeur de texte, et le port **28341** libre. Aucun compte n'est nécessaire, et rien ne quitte votre machine.
- **Un dossier de travail** : `~/byte-layers/docker/l4` est créé pour vous, et la dernière tâche le supprime.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l4-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : chaque tâche reprend le résultat de la précédente.

# Tâche 1 : un registre

## Démarrer le registre dans un conteneur

```setup
mkdir -p ~/byte-layers/docker/l4
```

Démarrez votre propre registre d'images, dans un conteneur lancé avec `docker run`.

**Critères :**

- un conteneur s'appelle exactement `layers-l4-registry`, et il tourne ;
- il vient d'une image `registry` ;
- le port **28341** de la machine mène au port **5000** du conteneur ;
- le registre répond sur `http://localhost:28341/v2/`.

```hint
Un registre est un conteneur comme un autre : il se lance avec `docker run`, en arrière-plan.
```

```hint
L'image `registry:3` écoute sur le port 5000. Le port de la machine vient en premier dans `-p`.
```

```verify
C=layers-l4-registry
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. Si le port 28341 est occupé, libérez-le, puis recréez le conteneur."
  exit 1
fi
IMG=$(docker container inspect "$C" --format '{{.Config.Image}}')
case "$IMG" in
  *registry*) : ;;
  *) echo "ÉCHEC : $C utilise l'image « $IMG », qui n'est pas un registre."; exit 1 ;;
esac
MAPPED=$(docker container inspect "$C" --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}}={{.HostPort}} {{end}}{{end}}')
case " $MAPPED" in
  *" 5000/tcp=28341 "*) : ;;
  *) echo "ÉCHEC : le port 28341 de la machine ne mène pas au port 5000 du conteneur (trouvé : ${MAPPED:-aucun port})."
     exit 1 ;;
esac
OK=""
for i in 1 2 3 4 5; do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:28341/v2/)" = "200" ] && OK=1 && break
  sleep 1
done
if [ -z "$OK" ]; then
  echo "ÉCHEC : le registre ne répond pas sur http://localhost:28341/v2/."
  exit 1
fi
echo "RÉUSSI : le registre répond sur le port 28341."
```

````solution
```bash
docker run -d --name layers-l4-registry -p 28341:5000 registry:3
```
````

# Tâche 2 : publier une première version

## Écrire le Dockerfile, construire l'image et la pousser

Créez le fichier `~/byte-layers/docker/l4/Dockerfile` avec votre éditeur, construisez l'image avec `docker build`, puis publiez-la dans votre registre avec `docker push`.

**Critères :**

- le fichier `~/byte-layers/docker/l4/Dockerfile` existe, et son image de départ a une **version précise**, ni `latest` ni rien ;
- un conteneur lancé depuis cette image écrit `PUBLICATION-V1`, puis s'arrête ;
- le registre connaît l'image sous le nom `localhost:28341/layers-l4-app:1.0`.

```hint
`alpine:3.22` fait une bonne image de départ. Une instruction `CMD` avec `echo` suffit pour écrire le texte.
```

```hint
`docker push` lit sa destination dans le nom de l'image. Il faut donc que ce nom commence par l'adresse du registre : soit vous le donnez à `docker build -t`, soit vous l'ajoutez avec `docker tag`.
```

```hint
Vérifiez vous-même ce que contient le registre : `curl http://localhost:28341/v2/layers-l4-app/tags/list`.
```

```verify
D="$HOME/byte-layers/docker/l4/Dockerfile"
R=localhost:28341/layers-l4-app
if [ ! -f "$D" ]; then
  echo "ÉCHEC : le fichier ~/byte-layers/docker/l4/Dockerfile n'existe pas."
  exit 1
fi
FROM=$(grep -iE '^[[:space:]]*FROM[[:space:]]' "$D" | head -n 1 | awk '{print $2}')
if [ -z "$FROM" ]; then
  echo "ÉCHEC : le Dockerfile n'a pas d'instruction FROM."
  exit 1
fi
case "$FROM" in
  *:latest|*:latest@*) echo "ÉCHEC : l'image de départ $FROM utilise le tag latest. Choisissez une version précise."; exit 1 ;;
  *:*|*@*) : ;;
  *) echo "ÉCHEC : l'image de départ $FROM n'a pas de version. Choisissez une version précise."; exit 1 ;;
esac
TAGS=$(curl -s --max-time 5 http://localhost:28341/v2/layers-l4-app/tags/list)
case "$TAGS" in
  *'"1.0"'*) : ;;
  *) echo "ÉCHEC : le registre ne connaît pas $R:1.0. L'image a-t-elle été poussée ?"; exit 1 ;;
esac
if ! docker pull -q "$R:1.0" >/dev/null 2>&1; then
  echo "ÉCHEC : impossible de tirer $R:1.0 depuis le registre."
  exit 1
fi
CID=$(docker run -d "$R:1.0" 2>/dev/null)
sleep 2
ST=$(docker inspect "$CID" --format '{{.State.Status}}' 2>/dev/null)
OUT=$(docker logs "$CID" 2>&1)
docker rm -f "$CID" >/dev/null 2>&1
if [ "$ST" != "exited" ]; then
  echo "ÉCHEC : un conteneur lancé depuis $R:1.0 ne s'arrête pas de lui-même (état : ${ST:-inconnu})."
  exit 1
fi
case "$OUT" in
  *PUBLICATION-V1*) : ;;
  *) echo "ÉCHEC : l'image publiée sous $R:1.0 n'écrit pas PUBLICATION-V1."; exit 1 ;;
esac
echo "RÉUSSI : le registre contient $R:1.0, qui écrit PUBLICATION-V1."
```

````solution
```bash
cat > ~/byte-layers/docker/l4/Dockerfile <<'EOF'
FROM alpine:3.22
CMD ["echo", "PUBLICATION-V1"]
EOF
docker build -t localhost:28341/layers-l4-app:1.0 ~/byte-layers/docker/l4
docker push localhost:28341/layers-l4-app:1.0
```
````

# Tâche 3 : noter le digest

## Garder le digest dans un fichier

Avant que quelqu'un ne republie sous ce tag, gardez de quoi retrouver cette version : créez le fichier `~/byte-layers/docker/l4/digest.txt`, avec votre éditeur ou une redirection `>`, et mettez-y le digest.

**Critères :**

- le fichier `~/byte-layers/docker/l4/digest.txt` contient, sur une ligne, le nom de cette version avec son digest, c'est-à-dire `localhost:28341/layers-l4-app@sha256:…` ;
- ce digest est celui que le registre donne pour le tag `1.0`.

Cliquez sur la vérification de cette tâche avant de passer à la suivante : elle garde le digest pour les tâches 4 et 5, et elle ne pourra plus réussir une fois le tag déplacé.

```hint
`docker push` affiche ce digest en fin de publication. `docker pull` l'affiche aussi, à la ligne `Digest:`.
```

```hint
La fiche d'une image le garde dans le champ `RepoDigests`, que `docker image inspect` sait lire. L'identifiant de l'image, `.Id`, n'est pas la bonne réponse : il n'est pas forcément égal au digest.
```

```verify
F="$HOME/byte-layers/docker/l4/digest.txt"
REG=http://localhost:28341/v2/layers-l4-app/manifests/1.0
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'
if [ ! -f "$F" ]; then
  echo "ÉCHEC : le fichier ~/byte-layers/docker/l4/digest.txt n'existe pas."
  exit 1
fi
WANT=$(curl -sI --max-time 5 -H "Accept: $ACCEPT" "$REG" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" {print $2}')
if [ -z "$WANT" ]; then
  echo "ÉCHEC : le registre ne connaît pas le tag 1.0. Reprenez la tâche 2."
  exit 1
fi
if ! grep -qE '^localhost:28341/layers-l4-app@sha256:[0-9a-f]{64}$' "$F"; then
  echo "ÉCHEC : le fichier doit contenir le nom complet : localhost:28341/layers-l4-app@sha256: suivi de 64 caractères."
  exit 1
fi
GOT=$(grep -oE 'sha256:[0-9a-f]{64}' "$F" | head -n 1)
if [ "$GOT" != "$WANT" ]; then
  echo "ÉCHEC : $GOT n'est pas le digest que le registre donne pour le tag 1.0."
  echo "  L'identifiant affiché par docker images n'est pas le digest. Lisez plutôt la ligne de docker push ou de docker pull."
  exit 1
fi
echo "$WANT" > "$HOME/byte-layers/docker/l4/.digest-v1"
echo "RÉUSSI : le digest est noté. La vérification en garde une copie dans ~/byte-layers/docker/l4/.digest-v1 pour les tâches suivantes."
```

````solution
```bash
docker pull localhost:28341/layers-l4-app:1.0
docker image inspect localhost:28341/layers-l4-app:1.0 --format '{{index .RepoDigests 0}}' > ~/byte-layers/docker/l4/digest.txt
```
````

# Tâche 4 : déplacer le tag

## Republier sous le même tag, puis lancer la version 1

Une correction arrive, et elle est republiée sous le même tag. Modifiez `~/byte-layers/docker/l4/Dockerfile` avec votre éditeur, reconstruisez et poussez sous le même nom, puis lancez l'ancienne version par son digest et enregistrez ce qu'elle écrit dans un fichier, avec une redirection `>`.

**Critères :**

- l'image publiée sous `localhost:28341/layers-l4-app:1.0` écrit maintenant `PUBLICATION-V2` ;
- le fichier `~/byte-layers/docker/l4/ancienne.txt` contient ce qu'écrit la **version 1**, obtenue en lançant l'image par son **digest**.

⚖️ Republier sous le même tag est une mauvaise pratique : on le fait ici pour voir ce qui se passe quand cela arrive. La vérification contrôle que ce digest donne bien la version 1, mais elle ne voit pas comment vous avez rempli le fichier : c'est le geste qui compte.

```hint
Changez le Dockerfile, reconstruisez sous le même nom, et poussez. Le tag se déplace tout seul.
```

```hint
Un nom avec digest s'écrit `dépôt@sha256:…`, et s'utilise partout où un tag est accepté, y compris avec `docker run`. La version 1 est encore dans le registre.
```

```verify
R=localhost:28341/layers-l4-app
F="$HOME/byte-layers/docker/l4/ancienne.txt"
V1=$(cat "$HOME/byte-layers/docker/l4/.digest-v1" 2>/dev/null)
if [ -z "$V1" ]; then
  echo "ÉCHEC : la vérification de la tâche 3 n'a pas encore réussi. Faites-la d'abord."
  exit 1
fi
if ! docker pull -q "$R:1.0" >/dev/null 2>&1; then
  echo "ÉCHEC : impossible de tirer $R:1.0 depuis le registre."
  exit 1
fi
if ! docker run --rm "$R:1.0" 2>&1 | grep -q 'PUBLICATION-V2'; then
  echo "ÉCHEC : $R:1.0 n'écrit pas PUBLICATION-V2. Reconstruisez et poussez sous le même tag."
  exit 1
fi
if ! docker run --rm "$R@$V1" 2>&1 | grep -q 'PUBLICATION-V1'; then
  echo "ÉCHEC : le registre ne donne plus la version 1 pour le digest noté."
  exit 1
fi
if [ ! -f "$F" ]; then
  echo "ÉCHEC : le tag a bien bougé, mais le fichier ~/byte-layers/docker/l4/ancienne.txt n'existe pas."
  exit 1
fi
if ! grep -q 'PUBLICATION-V1' "$F"; then
  echo "ÉCHEC : ~/byte-layers/docker/l4/ancienne.txt ne contient pas ce qu'écrit la version 1."
  exit 1
fi
echo "RÉUSSI : le tag désigne la version 2, et le digest retrouve la version 1."
```

````solution
```bash
cat > ~/byte-layers/docker/l4/Dockerfile <<'EOF'
FROM alpine:3.22
CMD ["echo", "PUBLICATION-V2"]
EOF
docker build -t localhost:28341/layers-l4-app:1.0 ~/byte-layers/docker/l4
docker push localhost:28341/layers-l4-app:1.0
docker run --rm "$(cat ~/byte-layers/docker/l4/digest.txt)" > ~/byte-layers/docker/l4/ancienne.txt
```
````

# Tâche 5 : republier l'ancienne version

## Poser le tag stable sur la version 1

La correction pose problème, et la version 1 doit redevenir celle que l'on conseille, sans la reconstruire. Téléchargez-la par son digest, donnez-lui un nouveau nom avec `docker tag`, et poussez ce nom.

**Critères :**

- le registre connaît le tag `stable` du dépôt `layers-l4-app` ;
- ce tag désigne **la version 1 telle qu'elle a été publiée**, retrouvée par son digest et non reconstruite ;
- le tag `1.0`, lui, désigne toujours la version 2.

> **Si les digests diffèrent, ce n'est pas votre faute.** Le digest affiché par ce nouveau `docker push` peut être différent de celui que vous avez noté : selon votre installation, ce `push` peut n'envoyer que la variante de l'image pour votre processeur, qui a son propre digest. La vérification accepte ce cas, et elle ne peut pas toujours distinguer une image retrouvée d'une image reconstruite à l'identique : c'est le geste qui compte.

```hint
Un tag n'est qu'une étiquette : on peut en poser une sur une image désignée par son digest, à condition de l'avoir d'abord tirée.
```

```hint
`docker pull` avec le digest, puis `docker tag` vers le nouveau nom, puis `docker push`.
```

```verify
REG=http://localhost:28341/v2/layers-l4-app/manifests
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'
digest_of() { curl -sI --max-time 5 -H "Accept: $ACCEPT" "$REG/$1" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" {print $2}'; }
V1=$(cat "$HOME/byte-layers/docker/l4/.digest-v1" 2>/dev/null)
if [ -z "$V1" ]; then
  echo "ÉCHEC : la vérification de la tâche 3 n'a pas encore réussi. Faites-la d'abord."
  exit 1
fi
STABLE=$(digest_of stable)
if [ -z "$STABLE" ]; then
  echo "ÉCHEC : le registre ne connaît pas le tag stable."
  exit 1
fi
if [ "$STABLE" != "$V1" ] && ! curl -s --max-time 5 -H "Accept: $ACCEPT" "$REG/$V1" | grep -qF "$STABLE"; then
  echo "ÉCHEC : le tag stable désigne $STABLE, qui n'est pas la version 1."
  exit 1
fi
TAG10=$(digest_of 1.0)
if [ "$TAG10" = "$V1" ] || [ "$TAG10" = "$STABLE" ]; then
  echo "ÉCHEC : le tag 1.0 désigne encore la version 1. Il devait rester sur la version 2."
  exit 1
fi
echo "RÉUSSI : le tag stable désigne la version 1."
```

````solution
```bash
docker pull "$(cat ~/byte-layers/docker/l4/digest.txt)"
docker tag "$(cat ~/byte-layers/docker/l4/digest.txt)" localhost:28341/layers-l4-app:stable
docker push localhost:28341/layers-l4-app:stable
```
````

# Tâche 6 : ne rien laisser derrière soi

## Retirer le registre, les images et le dossier

Supprimez tout ce que ce challenge a créé, avec `docker rm`, `docker rmi` et `rm -rf` : le conteneur `layers-l4-registry` et ses données, les images de `localhost:28341/layers-l4-app`, et le dossier `~/byte-layers/docker/l4`.

**Critères :** plus de conteneur, plus d'image à ce nom, plus de dossier. La vérification ne peut pas voir le volume du registre une fois le conteneur parti : à vous de le supprimer avec lui.

Ce ménage n'est pas le sujet du challenge, et la liste des images à retirer peut être longue, car une image téléchargée par son digest garde ce nom-là. `docker images --digests | grep layers-l4-app` les montre toutes, et la solution donne les commandes si vous préférez aller droit au but.

```hint
`docker rm` a une option pour le volume d'un conteneur, et une autre pour un conteneur qui tourne.
```

```hint
`docker rmi` prend un nom ou un identifiant, et `-f` retire une image même si elle porte plusieurs noms.
```

```verify
if docker container inspect layers-l4-registry >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur layers-l4-registry existe encore."
  exit 1
fi
left=$(docker images --format '{{.Repository}}' | grep 'layers-l4-app')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste des images : $(echo "$left" | sort -u | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/byte-layers/docker/l4" ]; then
  echo "ÉCHEC : le dossier ~/byte-layers/docker/l4 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez publier une image et retrouver une version précise."
```

````solution
`docker images -q` ne donne que les identifiants des images de ce dépôt, `sort -u` retire les doublons, et `-f` les supprime même si une image porte plusieurs noms. Le `$(…)` place cette liste dans la commande `docker rmi`.

```bash
docker rm -fv layers-l4-registry
docker rmi -f $(docker images -q localhost:28341/layers-l4-app | sort -u)
rm -rf ~/byte-layers/docker/l4
```
````
