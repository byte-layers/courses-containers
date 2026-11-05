---
title: "Auditer une installation Docker"
description: "Dresser la fiche d'un poste Docker et prouver qu'il fonctionne, à partir d'un cahier des charges, sans guide."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 20
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

On vous confie un poste, et on vous demande s'il est prêt pour le parcours. Ce challenge prouve que vous savez répondre à cette question. Il n'y a **aucune commande à recopier** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel de Docker. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

> ⚠️ **Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP, et une salle entière partage souvent la même. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

- **Ce qu'il faut savoir** : ce qu'enseigne le lab [Installer Docker et vérifier son poste](https://byte-layers.com/fr/labs/docker-install).
- **Ce qu'il faut avoir** : Docker installé, `curl`, et le port **28301** libre. Sur un poste hébergé, tout est déjà installé.
- **Un dossier de travail** : `~/layers-l0`, où `~` désigne votre dossier personnel, est créé pour vous, et la dernière tâche le supprime. Vous y écrirez deux petits fichiers à la main, avec l'éditeur de votre choix. Dans le terminal, `nano ~/layers-l0/audit.txt` ouvre le premier ; `Ctrl-O` puis `Entrée` enregistre, et `Ctrl-X` quitte.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l0-`. Rien d'autre n'est inspecté ni supprimé sur votre machine.

# Tâche 1 : la fiche du poste

## Noter les versions et l'architecture dans un fichier

```setup
mkdir -p ~/layers-l0
```

Créez le fichier `~/layers-l0/audit.txt` avec votre éditeur, et notez-y la fiche de ce poste, avec une ligne par information, au format `nom=valeur`.

**Critères :**

- `client=` donne la version du client Docker ;
- `moteur=` donne la version du moteur ;
- `architecture=` donne l'architecture du moteur.

Le fichier doit donc ressembler à ceci, avec les vraies valeurs de votre poste :

```text
client=29.0.0
moteur=27.0.0
architecture=arm64
```

```hint
Une commande du lab affiche les versions du client et du moteur. Lisez sa réponse, puis recopiez les valeurs dans le fichier.
```

```hint
Le client et le moteur ont chacun leur partie dans `docker version`, avec une ligne `Version`. L'architecture est dans `docker info`, ou à la fin de la ligne `OS/Arch` de la partie du moteur.
```

```verify
F="$HOME/layers-l0/audit.txt"
if [ ! -f "$F" ]; then
  echo "ÉCHEC : le fichier ~/layers-l0/audit.txt n'existe pas."
  exit 1
fi
val() { grep -iE "^[[:space:]]*$1[[:space:]]*=" "$F" | tail -n 1 | sed 's/^[^=]*=//' | tr -d ' \r'; }
fail=0
check() { # nom, valeur écrite, attendu
  if [ -z "$2" ]; then
    echo "ÉCHEC : il manque la ligne $1=."
    fail=1
  elif [ "$2" != "$3" ]; then
    echo "ÉCHEC : $1=$2 ne correspond pas à ce poste."
    fail=1
  fi
}
check client "$(val client)" "$(docker version --format '{{.Client.Version}}')"
check moteur "$(val moteur)" "$(docker version --format '{{.Server.Version}}')"
ARCH=$(val architecture)
A1=$(docker version --format '{{.Server.Arch}}')
A2=$(docker info --format '{{.Architecture}}')
if [ -z "$ARCH" ]; then
  echo "ÉCHEC : il manque la ligne architecture=."
  fail=1
elif [ "$ARCH" != "$A1" ] && [ "$ARCH" != "$A2" ]; then
  echo "ÉCHEC : architecture=$ARCH ne correspond pas à ce poste."
  fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "RÉUSSI : la fiche correspond à ce poste."
```

````solution
Recopier les valeurs à la main suffit. Cette commande fait la même chose sans rien retaper : `--format` n'affiche que la valeur demandée, `$(…)` la place dans la phrase, et `>` envoie le tout dans le fichier.

```bash
{
  echo "client=$(docker version --format '{{.Client.Version}}')"
  echo "moteur=$(docker version --format '{{.Server.Version}}')"
  echo "architecture=$(docker version --format '{{.Server.Arch}}')"
} > ~/layers-l0/audit.txt
```
````

# Tâche 2 : un conteneur témoin

## Lancer un conteneur qui se termine sans erreur

Prouvez que ce poste sait télécharger une image et lancer un conteneur qui se termine sans erreur.

**Critères :**

- un conteneur s'appelle exactement `layers-l0-probe` ;
- il vient d'une image `alpine` ;
- il s'est terminé sans erreur ;
- il a écrit `LAYERS-L0-OK` sur sa sortie.

```hint
Un seul `docker run` suffit. Le conteneur doit s'arrêter de lui-même une fois sa commande exécutée, sans être supprimé.
```

```hint
Reprenez la commande de la section « Télécharger une image et lancer un conteneur » du lab, en changeant le nom et la phrase.
```

```verify
C=layers-l0-probe
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
IMG=$(docker container inspect "$C" --format '{{.Config.Image}}')
case "$IMG" in
  alpine|alpine[:@]*|*/alpine|*/alpine[:@]*) : ;;
  *) echo "ÉCHEC : $C utilise l'image « $IMG », qui n'est pas une image alpine."; exit 1 ;;
esac
if [ "$(docker container inspect "$C" --format '{{.State.Status}}')" != "exited" ]; then
  echo "ÉCHEC : $C ne s'est pas terminé. Sa commande doit écrire la phrase, puis s'arrêter."
  exit 1
fi
CODE=$(docker container inspect "$C" --format '{{.State.ExitCode}}')
if [ "$CODE" != "0" ]; then
  echo "ÉCHEC : $C s'est terminé avec le code $CODE, et 0 est attendu."
  exit 1
fi
if ! docker logs "$C" 2>&1 | grep -q 'LAYERS-L0-OK'; then
  echo "ÉCHEC : la sortie de $C ne contient pas LAYERS-L0-OK."
  exit 1
fi
echo "RÉUSSI : $C a tourné et s'est terminé sans erreur."
```

````solution
```bash
docker run --name layers-l0-probe alpine:3.22 echo LAYERS-L0-OK
```
````

# Tâche 3 : un serveur joignable

## Lancer un serveur web et lire sa page

Prouvez que ce poste peut servir une page : lancez nginx dans un conteneur, puis demandez-lui sa page avec `curl`.

**Critères :**

- un conteneur s'appelle exactement `layers-l0-audit-web`, il tourne, et il vient d'une image `nginx` ;
- le port **28301** de la machine mène au port **80** du conteneur ;
- ce serveur répond à `curl http://localhost:28301`.

```hint
Il vous faut `docker run` avec l'option qui rend la main et celle qui relie les ports. Le port de la machine vient en premier.
```

```hint
Vérifiez avec `docker ps` qu'il tourne, puis demandez-lui sa page avec `curl`. S'il ne répond pas, attendez une seconde et relancez.
```

```verify
C=layers-l0-audit-web
if ! docker container inspect "$C" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun conteneur ne s'appelle $C."
  exit 1
fi
if [ "$(docker container inspect "$C" --format '{{.State.Running}}')" != "true" ]; then
  echo "ÉCHEC : $C ne tourne pas. S'il indique un port occupé, libérez le port 28301, puis recréez-le."
  exit 1
fi
IMG=$(docker container inspect "$C" --format '{{.Config.Image}}')
case "$IMG" in
  nginx|nginx[:@]*|*/nginx|*/nginx[:@]*) : ;;
  *) echo "ÉCHEC : $C utilise l'image « $IMG », qui n'est pas une image nginx."; exit 1 ;;
esac
MAPPED=$(docker container inspect "$C" --format '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}}={{.HostPort}} {{end}}{{end}}')
case " $MAPPED" in
  *" 80/tcp=28301 "*) : ;;
  *) echo "ÉCHEC : le port 28301 de la machine ne mène pas au port 80 du conteneur (trouvé : ${MAPPED:-aucun port}). Recréez le conteneur."
     exit 1 ;;
esac
ok=0
for i in 1 2 3 4 5; do
  if curl -s --max-time 5 http://localhost:28301 | grep -q 'Welcome to nginx'; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "ÉCHEC : le serveur ne répond pas sur le port 28301. Il démarre peut-être encore : réessayez."
  exit 1
fi
echo "RÉUSSI : le serveur répond sur le port 28301."
```

````solution
```bash
docker run -d --name layers-l0-audit-web -p 28301:80 nginx:1.30-alpine
docker ps
curl http://localhost:28301
```
````

# Tâche 4 : reconnaître une panne

## Garder le message du client sans moteur

Un collègue vous dira un jour que « Docker ne marche plus ». Faites parler le client à un moteur absent, sans rien arrêter sur votre poste, puis créez le fichier `~/layers-l0/panne.txt` avec votre éditeur et collez-y le message qu'il affiche.

**Critères :**

- le fichier `~/layers-l0/panne.txt` contient le message d'erreur du client ;
- ce message désigne l'adresse `tcp://localhost:1`, où aucun moteur n'écoute.

```hint
Le lab a montré comment faire parler le client à un moteur qui n'existe pas, le temps d'une seule commande.
```

```hint
Lancez cette commande, copiez la ligne d'erreur qu'elle affiche, puis collez-la dans le fichier avec votre éditeur.
```

```verify
F="$HOME/layers-l0/panne.txt"
if [ ! -f "$F" ]; then
  echo "ÉCHEC : le fichier ~/layers-l0/panne.txt n'existe pas."
  exit 1
fi
if ! grep -q 'Cannot connect to the Docker daemon' "$F"; then
  echo "ÉCHEC : le fichier ne contient pas le message d'erreur du client."
  echo "  Copiez la ligne qui commence par Cannot connect dans ce fichier."
  exit 1
fi
if ! grep -q 'tcp://localhost:1' "$F"; then
  echo "ÉCHEC : le message ne désigne pas tcp://localhost:1."
  exit 1
fi
echo "RÉUSSI : vous saurez reconnaître un moteur qui ne répond pas."
```

````solution
Copier la ligne à la main suffit. Cette commande fait la même chose : `>` envoie la sortie dans le fichier, et `2>&1` y ajoute les messages d'erreur, qui n'empruntent pas la sortie normale.

```bash
DOCKER_HOST=tcp://localhost:1 docker version > ~/layers-l0/panne.txt 2>&1
```
````

# Tâche 5 : ne rien laisser derrière soi

## Supprimer les conteneurs et le dossier

Supprimez ce que ce challenge a créé : les conteneurs `layers-l0-probe` et `layers-l0-audit-web`, et le dossier `~/layers-l0`.

**Critères :** plus aucun de ces conteneurs, plus de dossier. Vos autres conteneurs ne sont pas concernés.

```hint
`docker rm` refuse de supprimer un conteneur qui tourne. Une option force la suppression.
```

```hint
Pour un dossier et tout ce qu'il contient : `rm -r`, en vérifiant bien le chemin avant de valider, car rien ne vous sera demandé.
```

```verify
left=$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l0-(probe|audit-web)$')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l0" ]; then
  echo "ÉCHEC : le dossier ~/layers-l0 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre, et votre audit est terminé."
```

````solution
```bash
docker rm -f layers-l0-probe layers-l0-audit-web
rm -r ~/layers-l0
```
````
