---
title: "Faire vivre un conteneur, sans guide"
description: "Lancer, configurer, inspecter et observer des conteneurs à partir d'un cahier des charges, sans guide."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 45
introTitle: "Le défi"
requires: "0.3.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce challenge prouve que vous savez lancer, configurer et observer un conteneur. Il n'y a **aucune
commande à recopier** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état
réel de Docker. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours.
Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseigne le cours « Lancer, configurer et observer un conteneur ».
  Le lab « Héberger une page dans un conteneur » montre aussi comment publier un port.
- **Ce qu'il faut avoir** : Docker qui répond à `docker ps`, et le port 28080 libre.
- **Un dossier de travail** : `~/layers-l1` est créé pour vous, et la dernière tâche le supprime. La vérification y garde aussi un fichier caché, `.web-id`, qui lui sert à reconnaître votre conteneur.
- **Si un téléchargement échoue** avec `429 Too Many Requests`, vous avez atteint la limite de Docker Hub. Attendez, ou créez un compte gratuit et lancez `docker login`.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l1-`.
  Rien d'autre n'est inspecté ni supprimé sur votre machine.
- **L'ordre compte** : les tâches 2 et 3 reprennent le conteneur de la tâche 1. Faites-les dans l'ordre.

# Tâche 1 : un serveur web en arrière-plan

Démarrez un conteneur nginx qui tourne en arrière-plan et répond sur le port **28080** de votre machine.

**Critères :**

- un conteneur s'appelle exactement `layers-l1-web` ;
- il est **en cours d'exécution** ;
- il vient d'une image `nginx` ;
- le port **28080** de la machine mène au port **80** du conteneur ;
- sa mémoire est limitée à **128 Mio**.

```hint
Trois choses doivent être vraies en même temps : le conteneur rend la main à votre terminal, il porte un nom fixe, et un port est publié.
```

```hint
On publie un port avec `-p <port-machine>:<port-conteneur>`. Le port de la machine vient en premier.
```

```hint
L'image `nginx:1.30-alpine` écoute sur le port 80. Il vous faut `docker run` avec l'option de détachement, celle du nom, celle du port et celle de la mémoire.
```

```verify
C=layers-l1-web
if ! docker info >/dev/null 2>&1; then
  echo "ÉCHEC : Docker ne répond pas. Démarrez-le et réessayez."
  exit 1
fi
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  echo "  Créez-le depuis une image nginx, en arrière-plan, en publiant le port 28080 vers le port 80."
  exit 1
fi
STATUS=$(docker container inspect "$C" --format '{{.State.Status}}')
ERR=$(docker container inspect "$C" --format '{{.State.Error}}')
RUNNING=$(docker container inspect "$C" --format '{{.State.Running}}')
if [ "$RUNNING" != "true" ]; then
  case "$ERR" in
    *"port is already allocated"*|*"address already in use"*|*"bind"*)
      echo "ÉCHEC : $C existe, mais n'a pas pu démarrer : le port 28080 est déjà pris."
      echo "  Votre commande a l'air juste, c'est le port qui pose problème."
      echo "  Libérez-le (docker ps --filter publish=28080), puis : docker rm $C, et recommencez."
      exit 1 ;;
  esac
  echo "ÉCHEC : $C existe, mais son état est « $STATUS » : il ne tourne pas."
  [ -n "$ERR" ] && echo "  Docker indique : $ERR"
  echo "  Démarrez-le, ou supprimez-le et recréez-le en arrière-plan."
  exit 1
fi
IMG=$(docker container inspect "$C" --format '{{.Config.Image}}')
case "$IMG" in
  *nginx*) : ;;
  *) echo "ÉCHEC : $C utilise l'image « $IMG », qui n'est pas une image nginx."
     exit 1 ;;
esac
MAPPED=$(docker container inspect "$C" --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}}={{.HostPort}} {{end}}{{end}}')
case " $MAPPED" in
  *" 80/tcp=28080 "*) : ;;
  *) echo "ÉCHEC : le port 28080 de la machine ne mène pas au port 80 du conteneur."
     if [ -z "$MAPPED" ]; then
       echo "  Aucun port n'est publié sur ce conteneur."
     else
       echo "  Trouvé à la place : $MAPPED"
       echo "  L'ordre est -p <port-machine>:<port-conteneur>."
     fi
     echo "  Supprimez le conteneur et recréez-le avec le bon port."
     exit 1 ;;
esac
MEM=$(docker container inspect "$C" --format '{{.HostConfig.Memory}}')
if [ "$MEM" != "134217728" ]; then
  echo "ÉCHEC : la mémoire de $C n'est pas limitée à 128 Mio (trouvé : $MEM octets, 0 veut dire aucune limite)."
  echo "  Une limite se pose à la création : supprimez le conteneur et recréez-le."
  exit 1
fi
mkdir -p "$HOME/layers-l1"
docker container inspect "$C" --format '{{.Id}}' > "$HOME/layers-l1/.web-id"
echo "RÉUSSI : $C utilise $IMG, avec 28080 vers 80."
```

````solution
```bash
docker run -d --name layers-l1-web -p 28080:80 --memory 128m nginx:1.30-alpine
```
````

# Tâche 2 : lire sa configuration

```setup
mkdir -p ~/layers-l1
```

Retrouvez ce que `layers-l1-web` est configuré pour exécuter, sans ouvrir de shell dans le conteneur, et
gardez une trace dans un fichier.

**Critères :**

- le fichier `~/layers-l1/inspect.txt` existe ;
- il contient la **commande de démarrage** du conteneur, son champ `.Config.Cmd` ;
- il contient l'**identifiant de son image**, qui commence par `sha256:`.

```hint
Docker conserve la configuration d'un conteneur, et on peut la lire sans rien exécuter dedans. Une seule sous-commande donne toute sa fiche en JSON.
```

```hint
`docker inspect` accepte `--format`. La commande de démarrage se trouve dans `.Config.Cmd`, l'identifiant de l'image dans `.Image`.
```

```hint
Rediriger toute la fiche JSON vers le fichier marche aussi : la vérification cherche les valeurs, peu importe la présentation.
```

```verify
C=layers-l1-web
REPORT="$HOME/layers-l1/inspect.txt"
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur $C n'existe pas. Faites d'abord la tâche 1."
  exit 1
fi
if [ ! -f "$REPORT" ]; then
  echo "ÉCHEC : le fichier $REPORT n'existe pas."
  echo "  Inspectez $C et notez-y sa commande de démarrage et l'identifiant de son image."
  exit 1
fi
IMGID=$(docker container inspect "$C" --format '{{.Image}}')
CMD=$(docker container inspect "$C" --format '{{range .Config.Cmd}}{{.}} {{end}}')
fail=0
if ! grep -qF "$IMGID" "$REPORT"; then
  SHORT=$(printf '%s' "$IMGID" | sed 's/^sha256://' | cut -c1-12)
  if ! grep -qF "$SHORT" "$REPORT"; then
    echo "ÉCHEC : l'identifiant de l'image de $C n'est pas dans le fichier."
    echo "  Attendu : $IMGID"
    fail=1
  fi
fi
for w in $CMD; do
  if ! grep -qF -- "$w" "$REPORT"; then
    echo "ÉCHEC : la commande de démarrage de $C n'est pas dans le fichier."
    echo "  Il y manque au moins : $w"
    fail=1
    break
  fi
done
if [ "$fail" -ne 0 ]; then
  echo "  Lisez-les avec : docker inspect $C"
  exit 1
fi
echo "RÉUSSI : le fichier contient la commande de démarrage et l'identifiant de l'image de $C."
```

````solution
```bash
docker inspect layers-l1-web --format '{{json .Config.Cmd}} {{.Image}}' > ~/layers-l1/inspect.txt
```
````

# Tâche 3 : le cycle de vie

Faites passer `layers-l1-web` par un arrêt et un redémarrage, et laissez-le **en pause**.

**Critères :**

- `layers-l1-web` a été **arrêté puis redémarré** au moins une fois ;
- il est maintenant **en pause** ;
- c'est **le même conteneur** : le supprimer et le recréer ne convient pas.

```hint
Trois verbes suffisent : deux pour le cycle arrêt et redémarrage, un pour figer le conteneur.
```

```hint
Docker note l'heure du dernier arrêt d'un conteneur. Un conteneur jamais arrêté n'a pas cette date : c'est ainsi que la vérification sait que le cycle a eu lieu.
```

```hint
Une pause fige les processus sans les terminer : le conteneur reste compté comme en cours d'exécution.
```

```verify
C=layers-l1-web
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : le conteneur $C n'existe pas."
  echo "  Il doit être celui de la tâche 1 : en recréer un n'est pas le même conteneur."
  exit 1
fi
ID_REF=$(cat "$HOME/layers-l1/.web-id" 2>/dev/null)
if [ -n "$ID_REF" ] && [ "$ID_REF" != "$(docker container inspect "$C" --format '{{.Id}}')" ]; then
  echo "ÉCHEC : $C n'est plus le conteneur de la tâche 1 : il a été recréé."
  echo "  Supprimez-le, refaites la tâche 1, puis conduisez ce conteneur-là."
  exit 1
fi
FIN=$(docker container inspect "$C" --format '{{.State.FinishedAt}}')
case "$FIN" in
  0001-01-01*|"")
    echo "ÉCHEC : $C n'a jamais été arrêté."
    echo "  Faites un arrêt puis un redémarrage avant la pause."
    exit 1 ;;
esac
STATUS=$(docker container inspect "$C" --format '{{.State.Status}}')
PAUSED=$(docker container inspect "$C" --format '{{.State.Paused}}')
if [ "$STATUS" = "exited" ] || [ "$STATUS" = "created" ]; then
  echo "ÉCHEC : $C est dans l'état « $STATUS » : il a été arrêté, mais pas redémarré."
  exit 1
fi
if [ "$PAUSED" != "true" ]; then
  echo "ÉCHEC : $C est dans l'état « $STATUS » et n'est pas en pause."
  echo "  Le cycle est fait, il reste à figer ses processus."
  exit 1
fi
echo "RÉUSSI : $C a été arrêté puis redémarré, et il est en pause."
```

````solution
```bash
docker stop layers-l1-web
docker start layers-l1-web
docker pause layers-l1-web
```
````

# Tâche 4 : un shell qui laisse une trace

Ouvrez un shell dans un nouveau conteneur et créez-y un fichier.

**Critères :**

- un conteneur s'appelle exactement `layers-l1-shell`, qu'il tourne encore ou non ;
- il a été créé avec une **entrée interactive** et un **terminal** ;
- le fichier `/root/preuve.txt` qu'il contient comporte le mot `layers`.

```hint
Deux options de `docker run` donnent un shell utilisable : l'une garde l'entrée ouverte, l'autre alloue un terminal. On les écrit presque toujours ensemble.
```

```hint
Quitter le shell arrête le conteneur sans le supprimer. N'utilisez donc pas l'option qui le supprime à la sortie : la vérification n'aurait plus rien à lire.
```

```hint
`docker run -it --name layers-l1-shell alpine:3.22 sh` vous donne le shell. Créez ensuite le fichier avec une simple redirection.
```

```verify
C=layers-l1-shell
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  echo "  Créez-le en mode interactif et faites-y le fichier demandé."
  echo "  Attention : --rm supprime le conteneur à la sortie, et il ne reste rien à vérifier."
  exit 1
fi
OPEN=$(docker container inspect "$C" --format '{{.Config.OpenStdin}}')
TTY=$(docker container inspect "$C" --format '{{.Config.Tty}}')
if [ "$OPEN" != "true" ] || [ "$TTY" != "true" ]; then
  echo "ÉCHEC : $C n'a pas été créé en mode interactif."
  echo "  Entrée ouverte : $OPEN, terminal alloué : $TTY. Il faut les deux."
  echo "  Supprimez-le et recréez-le avec un terminal interactif."
  exit 1
fi
CONTENT=$(docker cp "$C:/root/preuve.txt" - 2>/dev/null | tar -xO 2>/dev/null)
if [ -z "$CONTENT" ]; then
  echo "ÉCHEC : /root/preuve.txt est absent ou vide dans $C."
  echo "  Pour rentrer dans un conteneur arrêté : docker start -ai $C"
  exit 1
fi
case "$CONTENT" in
  *layers*) : ;;
  *) echo "ÉCHEC : /root/preuve.txt existe, mais ne contient pas le mot layers."
     echo "  Trouvé : $(echo "$CONTENT" | head -1)"
     exit 1 ;;
esac
echo "RÉUSSI : $C est interactif et /root/preuve.txt contient le mot layers."
```

````solution
```bash
docker run -it --name layers-l1-shell alpine:3.22 sh
```

Puis, dans le shell du conteneur :

```sh
echo layers > /root/preuve.txt
exit
```
````

# Tâche 5 : capturer une sortie

```setup
mkdir -p ~/layers-l1
```

Produisez un conteneur qui écrit une ligne reconnaissable sur sa sortie standard, et enregistrez cette sortie
dans un fichier de votre machine.

**Critères :**

- un conteneur s'appelle exactement `layers-l1-logger` ;
- sa sortie, telle que Docker l'a enregistrée, contient `LAYERS-LOG-OK` ;
- le fichier `~/layers-l1/logs.txt` contient cette même ligne.

Lisez cette sortie depuis Docker plutôt que de la retaper : c'est le geste qui compte. La vérification ne peut pas faire la différence, elle vous fait confiance.

```hint
Docker enregistre ce que le processus principal écrit sur stdout et stderr. Il suffit donc que le conteneur affiche la ligne : `echo` convient.
```

```hint
La sous-commande qui relit cette sortie porte le nom de ce qu'elle lit. Redirigez-la vers le fichier.
```

```hint
`docker run --name layers-l1-logger alpine:3.22 echo LAYERS-LOG-OK` crée le conteneur, sans `--rm` : celui-ci effacerait les logs. Il reste à envoyer `docker logs` de ce conteneur vers le fichier.
```

```verify
C=layers-l1-logger
REPORT="$HOME/layers-l1/logs.txt"
NEEDLE=LAYERS-LOG-OK
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  echo "  Créez-en un dont le processus principal affiche $NEEDLE."
  exit 1
fi
LOGS=$(docker logs "$C" 2>&1)
case "$LOGS" in
  *"$NEEDLE"*) : ;;
  *) echo "ÉCHEC : Docker n'a pas enregistré $NEEDLE dans la sortie de $C."
     if [ -z "$LOGS" ]; then
       echo "  Le conteneur n'a rien écrit. Docker ne capture que stdout et stderr du processus principal."
     else
       echo "  Docker a enregistré : $(echo "$LOGS" | head -2 | tr '\n' ' ')"
     fi
     exit 1 ;;
esac
if [ ! -f "$REPORT" ]; then
  echo "ÉCHEC : la sortie du conteneur est bonne, mais le fichier $REPORT n'existe pas."
  exit 1
fi
if ! grep -qF "$NEEDLE" "$REPORT"; then
  echo "ÉCHEC : $REPORT ne contient pas $NEEDLE."
  exit 1
fi
echo "RÉUSSI : $C a écrit $NEEDLE, et sa sortie est dans $REPORT."
```

````solution
```bash
docker run --name layers-l1-logger alpine:3.22 echo LAYERS-LOG-OK
docker logs layers-l1-logger > ~/layers-l1/logs.txt
```
````

# Tâche 6 : ne rien laisser derrière soi

Supprimez tout ce que ce challenge a créé : les conteneurs `layers-l1-web`, `layers-l1-shell` et
`layers-l1-logger`, et le dossier `~/layers-l1`.

**Critères :** plus aucun de ces conteneurs, plus de dossier. Vos autres conteneurs ne sont pas concernés.

```hint
`docker rm` refuse de supprimer un conteneur en cours d'exécution, et `layers-l1-web` est en pause. Une option force la suppression.
```

```hint
Pour un dossier et tout ce qu'il contient, y compris ses fichiers cachés : `rm -rf`, en vérifiant bien le chemin avant de valider.
```

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l1-(web|shell|logger)$')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l1" ]; then
  echo "ÉCHEC : le dossier ~/layers-l1 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez faire vivre un conteneur."
```

````solution
```bash
docker rm -f layers-l1-web layers-l1-shell layers-l1-logger
rm -rf ~/layers-l1
```
````
