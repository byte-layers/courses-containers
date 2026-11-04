---
title: "Les bind mounts"
description: "Donner à un conteneur l'accès à un dossier de votre machine, et les pièges qui vont avec"
---

Un volume convient à des données qui appartiennent au conteneur. Parfois, on veut l'inverse : que le conteneur travaille sur **vos** fichiers, ceux que vous modifiez avec votre éditeur. C'est le rôle d'un **bind mount**, qui branche un dossier de votre machine sur un dossier du conteneur. Il s'agit du même dossier des deux côtés, sans aucune copie.

## Servir un dossier de votre machine

Créez un petit site dans votre dossier de travail. `$HOME` est le chemin de votre dossier personnel, et le shell le remplace par sa valeur :

```exec
mkdir -p "$HOME/layers-l6/site"
echo '<h1>Mon site</h1>' > "$HOME/layers-l6/site/index.html"
```

Lancez nginx en branchant ce dossier sur son dossier de pages. C'est toujours l'option `-v`, mais ce qui précède le `:` est maintenant **un chemin** et non un nom. `:ro` donne à nginx un accès en lecture seule, car il n'a pas à modifier votre site. Du côté de `curl`, `-sS` n'affiche que les erreurs, et les options `--retry` réessaient le temps que le serveur démarre :

```exec
docker run -d --name layers-l6-site -p 28360:80 -v "$HOME/layers-l6/site:/usr/share/nginx/html:ro" nginx:1.30-alpine
curl -sS --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28360
```

Une erreur de connexion peut s'afficher le temps que nginx démarre, puis vous lisez `<h1>Mon site</h1>`.

Si vous travaillez sur un poste hébergé, c'est-à-dire un VS Code ouvert dans votre navigateur et fourni par votre formateur, retenez cette règle : le moteur Docker ne voit que les dossiers placés sous `/home/student`. C'est pour cela que tous vos fichiers vont dans `~/layers-l6`.

```verify
MOUNT=$(docker inspect layers-l6-site --format '{{range .Mounts}}{{.Type}} {{.Destination}} {{.RW}}{{end}}' 2>/dev/null)
if [ "$MOUNT" != "bind /usr/share/nginx/html false" ]; then
  echo "layers-l6-site n'a pas le bind mount attendu en lecture seule (trouvé : ${MOUNT:-rien}). docker rm -f layers-l6-site, puis relancez la commande."
  exit 1
fi
if ! curl -s --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28360 | grep -q 'Mon site'; then
  echo "nginx ne sert pas votre page sur le port 28360."
  exit 1
fi
echo "nginx sert votre dossier."
```

## Changer un fichier, sans rien reconstruire

Puisque c'est le même dossier, toute modification de votre côté se voit immédiatement dans le conteneur. Modifiez la page sur votre machine, puis redemandez-la :

```exec
echo '<h1>Mon site, modifié</h1>' > "$HOME/layers-l6/site/index.html"
curl -sS http://localhost:28360
```

Vous lisez la nouvelle version, sans reconstruction et sans redémarrage. C'est ce qui rend les bind mounts si utiles en développement.

```verify
if ! curl -s --max-time 5 http://localhost:28360 | grep -q 'modifié'; then
  echo "nginx ne sert pas la page modifiée. Lancez la commande de cette section."
  exit 1
fi
echo "La modification est visible sans reconstruction."
```

## Le dossier du conteneur est masqué

Un bind mount **masque** ce que l'image contient à cet endroit. Il ne recopie rien, contrairement à un volume neuf. Vérifiez-le en branchant un dossier vide sur le dossier de pages de nginx, à la place de votre site. `-w '%{http_code}'` affiche le code de réponse :

```exec
docker rm -f layers-l6-site
mkdir -p "$HOME/layers-l6/vide"
docker run -d --name layers-l6-site -p 28360:80 -v "$HOME/layers-l6/vide:/usr/share/nginx/html:ro" nginx:1.30-alpine
curl -sS -o /dev/null -w '%{http_code}\n' --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28360
```

Vous lisez `403` : nginx n'a plus aucune page à servir, car ses fichiers `index.html` et `50x.html` sont cachés. Ils existent toujours dans l'image, et le prochain conteneur sans ce bind mount les retrouvera.

```verify
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --retry 3 --retry-delay 1 --retry-all-errors http://localhost:28360)" != "403" ]; then
  echo "nginx devrait répondre 403 avec un dossier vide. Lancez les commandes de cette section."
  exit 1
fi
echo "Le dossier vide masque bien les pages de l'image."
```

## ⚠️ Deux pièges d'écriture

**Piège : un nom au lieu d'un chemin.**

- *Symptôme :* ce que le conteneur écrit n'arrive pas dans votre dossier, et ce que vous y mettez n'arrive pas dans le conteneur.
- *Cause :* sans `/` ni `.` au début, Docker lit le premier terme de `-v` comme le nom d'un volume, et il le crée sans rien dire.
- *Correctif :* écrivez un chemin, comme `"$HOME/layers-l6/site"` ou `./site`.

Constatez-le avec un nom écrit sans `/` ni `.`, puis supprimez ce volume créé par erreur. `true` est une commande qui ne fait rien, car seul le montage compte ici :

```exec
docker run --rm -v layers-l6-oups:/x alpine:3.22 true
docker volume ls --filter name=layers-l6-oups
docker volume rm layers-l6-oups
```

**Piège : un chemin qui n'existe pas.**

- *Symptôme :* avec `-v`, le conteneur démarre sur un dossier vide, et un nouveau dossier est apparu sur votre machine, parfois appartenant à `root` sous Linux.
- *Cause :* `-v` crée le chemin manquant, quitte à masquer votre faute de frappe.
- *Correctif :* utilisez `--mount type=bind`, qui refuse un chemin absent et signale donc l'erreur tout de suite.

Voici ce refus, et `true` ne sera même pas lancée :

```exec
docker run --rm --mount type=bind,src="$HOME/layers-l6/absent",dst=/x alpine:3.22 true
```

Vous lisez `bind source path does not exist`.

## Qui possède les fichiers ?

Un fichier écrit par le conteneur dans un bind mount apparaît sur votre machine, et il appartient à l'utilisateur du conteneur, souvent `root`. Écrivez-en un pour voir le résultat. `ls -l` affiche le propriétaire en troisième colonne :

```exec
docker run --rm -v "$HOME/layers-l6/vide:/sortie" alpine:3.22 sh -c 'echo trace > /sortie/trace.txt'
ls -l "$HOME/layers-l6/vide/trace.txt"
```

Sur Docker Desktop, le partage de fichiers vous l'attribue. Sous Linux et sur un poste hébergé, vous voyez `root`, et vous ne pourrez pas modifier ce fichier sans droits supplémentaires. Vous pourrez toutefois le supprimer, puisque le dossier parent est à vous.

```verify
if [ ! -f "$HOME/layers-l6/vide/trace.txt" ]; then
  echo "Le fichier trace.txt n'est pas apparu sur votre machine. Lancez la commande de cette section."
  exit 1
fi
echo "Le fichier écrit par le conteneur est bien sur votre machine."
```

Cette étape est terminée. Supprimez le conteneur et les dossiers de cet essai, en gardant `~/layers-l6` pour la suite :

```exec
docker rm -f layers-l6-site
rm -rf "$HOME/layers-l6/site" "$HOME/layers-l6/vide"
```

```verify
if docker container inspect layers-l6-site >/dev/null 2>&1; then
  echo "layers-l6-site existe encore. Lancez la commande ci-dessus."
  exit 1
fi
if [ -e "$HOME/layers-l6/site" ] || [ -e "$HOME/layers-l6/vide" ]; then
  echo "Les dossiers site et vide existent encore. Lancez la commande ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Les bind mounts](https://docs.docker.com/engine/storage/bind-mounts/) · [Partager des fichiers locaux](https://docs.docker.com/get-started/docker-concepts/running-containers/sharing-local-files/)

## Questions

```quiz
title: "Les bind mounts"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quelle différence y a-t-il entre `-v donnees:/data` et `-v ./donnees:/data` ?"
    answers:
      - "Aucune : dans les deux cas, Docker utilise un dossier `donnees` à côté de vous"
      - "Le premier est un volume nommé `donnees`, le second un bind mount du dossier `./donnees`"
      - "Le premier est un bind mount en lecture seule, le second un volume en lecture et écriture"
    correct: 2
    explanation: "Sans `/` ni `.` au début, Docker lit un nom de volume. C'est une source classique de confusion."
  - prompt: "Vous branchez un dossier vide de votre machine sur `/usr/share/nginx/html`. Que voit nginx ?"
    answers:
      - "Ses pages habituelles, car Docker les recopie dans votre dossier s'il est vide"
      - "Un dossier vide, car un bind mount masque le contenu de l'image à cet endroit"
      - "Rien : nginx refuse de démarrer, et le conteneur s'arrête avec une erreur"
    correct: 2
    explanation: "Seul un volume neuf reçoit une copie du contenu de l'image. Un bind mount montre votre dossier tel quel."
  - prompt: "Pourquoi préférer `--mount type=bind` à `-v` dans un script ?"
    answers:
      - "Il donne de meilleures performances d'accès aux fichiers de votre machine"
      - "Il refuse un chemin absent au lieu de créer un dossier vide sans prévenir"
      - "Il est le seul à permettre de monter un dossier en lecture seule"
    correct: 2
    explanation: "Une faute de frappe dans le chemin devient une erreur visible."
```
