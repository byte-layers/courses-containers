---
title: "Scanner un Dockerfile, une image et un fichier Compose"
description: "Un projet fictif, volontairement mal configuré, passé à Trivy, Grype et KICS : lire les résultats, corriger, scanner à nouveau."
tags:
  - lab
  - docker
  - security
difficulty: beginner
duration: 30
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Une application peut fonctionner parfaitement tout en embarquant une bibliothèque vulnérable, ou en donnant à un conteneur tous les droits sur la machine. Un **scanner** repère ces problèmes avant la mise en production, et il le fait à chaque modification, là où une relecture humaine finit par en laisser passer.

Dans ce lab, vous passez un petit projet fictif, `shop`, à trois outils. Il ne sera jamais déployé : on le construit seulement pour obtenir une image à analyser.

**Niveau** : vous savez lire un `Dockerfile` et un fichier Compose, et construire une image avec `docker build`. Vous n'avez besoin de connaître aucun des trois scanners.

**Ce qu'il faut** : Docker, un terminal et environ 4 Go d'espace disque, car les bases de vulnérabilités sont volumineuses. Vos fichiers vivent dans `~/byte-layers/docker/scan`, et la dernière étape libère tout cet espace.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Préparer le projet

## Qui scanne quoi

Les trois outils ne regardent pas la même chose, et c'est pour cela qu'on les combine. Le point à retenir concerne Grype : il ne lit pas un `Dockerfile`. Il analyse ce qui est installé dans une image déjà construite.

| Outil | Ce qu'il analyse dans ce lab | Ce qu'il trouve |
|---|---|---|
| [Trivy](https://trivy.dev/docs/latest/) | le `Dockerfile`, puis l'image | des erreurs de configuration, puis des vulnérabilités connues |
| [Grype](https://github.com/anchore/grype) | l'image | des vulnérabilités connues |
| [KICS](https://docs.kics.io/latest/) | le fichier Compose | des erreurs de configuration et des mots de passe en clair |

Une **vulnérabilité connue** est une faille publiée dans une version précise d'un paquet, souvent avec un identifiant `CVE-…`. Une **erreur de configuration** vient de vos propres choix, comme lancer un conteneur en root.

## Créer le projet fictif

Le projet contient quatre fichiers et des défauts volontaires : des dépendances anciennes, une image de base qui n'est plus maintenue, et un fichier Compose bien trop permissif. Ne reproduisez pas ces réglages ailleurs.

Commencez par l'application et ses dépendances :

```exec
mkdir -p ~/byte-layers/docker/scan/bin ~/byte-layers/docker/scan/shop
cd ~/byte-layers/docker/scan/shop
cat > package.json <<'EOF'
{
  "name": "shop",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "4.17.1",
    "lodash": "4.17.15"
  }
}
EOF
cat > index.js <<'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('ok\n'));
app.listen(3000);
EOF
printf 'node_modules\n*.tar\n' > .dockerignore
```

Le fichier `.dockerignore` a une raison précise : vous allez bientôt créer une archive `.tar` de l'image dans ce dossier, et elle ne doit pas se retrouver copiée dans l'image suivante.

Ajoutez ensuite le `Dockerfile` et le fichier Compose, qui sont les deux fichiers à analyser :

```exec
cd ~/byte-layers/docker/scan/shop
cat > Dockerfile <<'EOF'
FROM node:18-alpine3.18
ADD . /app
WORKDIR /app
RUN npm install
EXPOSE 3000
CMD ["node", "index.js"]
EOF
cat > compose.yaml <<'EOF'
services:
  web:
    build: .
    privileged: true
    ports:
      - "3000:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      DB_PASSWORD: secret123
  db:
    image: mysql:latest
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: secret123
EOF
```

## Préparer les trois scanners

Rien n'est à installer : chaque scanner tourne dans un conteneur. Pour éviter de retaper de longues commandes, vous allez créer trois petits scripts. Regardez d'abord celui de Trivy, car les deux autres suivent le même modèle :

```bash
docker run --rm \
  -v "$PWD:/work" -w /work \
  -v layers-scan-cache:/cache \
  aquasec/trivy:0.76.1@sha256:790fd66d... "$@"
```

| Option | Rôle |
|---|---|
| `--rm` | supprime le conteneur à la fin du scan |
| `-v "$PWD:/work" -w /work` | donne au scanner accès au dossier courant, et l'y place |
| `-v layers-scan-cache:/cache` | garde la base de vulnérabilités dans un volume, pour ne pas la télécharger à chaque scan |
| `:0.76.1@sha256:…` | fixe la version et l'empreinte exacte de l'image |
| `"$@"` | transmet au scanner les arguments que vous lui donnez |

Le `sha256` n'est pas un excès de prudence. En 2026, des [images `aquasec/trivy`](https://www.docker.com/blog/trivy-supply-chain-compromise-what-docker-hub-users-should-know/) et des [tags `checkmarx/kics`](https://thehackernews.com/2026/04/malicious-kics-docker-images-and-vs.html) ont été remplacés par des versions malveillantes. Un tag peut être réécrit, alors qu'une empreinte désigne toujours le même contenu. Pour la même raison, on ne monte pas ici le socket Docker dans les scanners : ils reçoivent seulement le dossier du projet.

Créez maintenant les trois scripts :

```exec
cd ~/byte-layers/docker/scan/bin
cat > trivy <<'EOF'
#!/bin/sh
exec docker run --rm -v "$PWD:/work" -w /work -v layers-scan-cache:/cache \
  aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
  "$@" --cache-dir /cache
EOF
cat > grype <<'EOF'
#!/bin/sh
exec docker run --rm -v "$PWD:/work" -w /work -v layers-scan-cache:/cache \
  -e GRYPE_DB_CACHE_DIR=/cache/grype \
  anchore/grype:v0.121.1@sha256:6b06708b036f74b2cd70e94b706b4586af96d1932e6ac46255940b2e39dd44a9 \
  "$@"
EOF
cat > kics <<'EOF'
#!/bin/sh
exec docker run --rm -v "$PWD:/work" -w /work \
  checkmarx/kics:v2.2.0@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003 \
  "$@"
EOF
chmod +x trivy grype kics
```

```verify
for F in shop/Dockerfile shop/compose.yaml shop/package.json bin/trivy bin/grype bin/kics; do
  if [ ! -s "$HOME/byte-layers/docker/scan/$F" ]; then
    echo "Le fichier ~/byte-layers/docker/scan/$F manque. Relancez le bloc qui le crée."
    exit 1
  fi
done
echo "Le projet et les trois scripts sont en place."
```

# Scanner le Dockerfile et l'image

## Le Dockerfile avec Trivy

La commande `trivy config` lit les fichiers sans rien construire, et elle ne télécharge pas de base de vulnérabilités. C'est donc le scan le plus rapide, et celui qu'on lance en premier :

```exec
cd ~/byte-layers/docker/scan/shop && ~/byte-layers/docker/scan/bin/trivy config .
```

Trivy signale trois points sur le `Dockerfile` :

| Règle | Sévérité | Ce qu'elle dit |
|---|---|---|
| `DS-0002` | HIGH | aucune instruction `USER` : le conteneur tourne en root |
| `DS-0005` | LOW | `ADD` au lieu de `COPY` |
| `DS-0026` | LOW | aucune instruction `HEALTHCHECK` |

Remarquez ce qu'il ne signale pas : l'image `node:18` ancienne et les dépendances anciennes. Lire le `Dockerfile` ne suffit pas pour cela, et il faut analyser l'image construite.

## L'image avec Trivy

Vous construisez donc l'image, puis vous l'exportez dans une archive avec `docker save`. Le scanner lit cette archive, ce qui évite de lui donner accès au socket Docker :

```exec
cd ~/byte-layers/docker/scan/shop
docker build -q -t layers-scan-shop:v1 .
docker save layers-scan-shop:v1 -o shop-v1.tar
```

Lancez ensuite le scan en ne gardant que les sévérités les plus graves. Le premier lancement télécharge une base d'environ 130 Mo :

```exec
cd ~/byte-layers/docker/scan/shop && ~/byte-layers/docker/scan/bin/trivy image --input shop-v1.tar --scanners vuln --severity HIGH,CRITICAL --no-progress
```

Le résultat est long, et il se lit par blocs. Le premier concerne les paquets du système Alpine, et les suivants les paquets Node.js de `node_modules`. Trivy avertit aussi que cette version d'Alpine n'est plus maintenue : même si de nouvelles failles sont publiées, elle ne recevra plus de correctifs.

## L'image avec Grype

Grype analyse la même archive, avec sa propre base de vulnérabilités. Le préfixe `docker-archive:` lui indique le type de source, et `--only-fixed` ne garde que les failles pour lesquelles une version corrigée existe, donc celles que vous pouvez traiter tout de suite :

```exec
cd ~/byte-layers/docker/scan/shop && ~/byte-layers/docker/scan/bin/grype docker-archive:shop-v1.tar --only-fixed
```

Comparez les deux listes. Elles ne seront pas identiques, car les deux outils n'utilisent pas les mêmes bases ni les mêmes règles de correspondance. Une faille vue par un seul outil n'est donc pas forcément une erreur, et c'est l'intérêt d'avoir un second avis.

```ack
J'ai lu les résultats de Trivy et de Grype
```

# Scanner le fichier Compose

## Lancer KICS

KICS analyse les fichiers d'infrastructure. L'option `-p` indique le chemin à scanner :

```exec
cd ~/byte-layers/docker/scan/shop && ~/byte-layers/docker/scan/bin/kics scan -p compose.yaml --no-progress; echo "Code de sortie : $?"
```

KICS trouve 13 résultats, dont 5 de sévérité HIGH. Voici les principaux :

| Résultat | Ligne concernée | Pourquoi c'est grave |
|---|---|---|
| Privileged Containers Enabled | `privileged: true` | le conteneur obtient presque tous les droits du noyau de la machine |
| Docker Socket Mounted In Container | `/var/run/docker.sock` | le conteneur peut piloter Docker, donc lancer ce qu'il veut sur la machine |
| Passwords And Secrets (2 résultats) | `DB_PASSWORD`, `MYSQL_ROOT_PASSWORD` | un mot de passe versionné dans Git se retrouve partout |

KICS signale aussi le montage du socket dans un cinquième résultat HIGH, sous un autre titre. Chaque résultat affiche un lien vers sa documentation : ouvrez-le, puis lisez aussi les résultats MEDIUM.

Le code de sortie mérite un regard : KICS renvoie `50`, et non `0`, parce qu'il a trouvé des résultats HIGH. C'est ce [code](https://docs.kics.io/latest/results/) qui permettra de bloquer une chaîne d'intégration continue.

⚠️ KICS peut afficher `A new version 'v2.2.0' of KICS is available` alors que c'est la version utilisée. Ignorez ce message : on ne change pas la version épinglée sur la foi d'un simple message, on vérifie d'abord la publication et son empreinte.

# Corriger et scanner à nouveau

## À vous de jouer

Un scan n'a de valeur que si on traite ce qu'il trouve. Vous avez été guidé jusqu'ici, et vous corrigez maintenant les fichiers à partir des résultats.

🚧 Dans `~/byte-layers/docker/scan/shop/Dockerfile`, remplacez le contenu par ce squelette, puis complétez les `# TODO` :

```dockerfile
# TODO : une image de base maintenue, par exemple la 22 en version alpine
WORKDIR /app
# TODO : copier le projet avec l'instruction recommandée par DS-0005
RUN npm install --omit=dev
# TODO : passer à l'utilisateur node, déjà prévu dans l'image (DS-0002)
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/ || exit 1
CMD ["node", "index.js"]
```

🚧 Dans `package.json`, passez `express` en `4.21.2` et `lodash` en `4.17.21`.

🚧 Dans `compose.yaml`, remplacez le contenu par ce squelette, puis complétez les `# TODO` :

```yaml
services:
  web:
    build: .
    # TODO : publier le port 3000 sur 127.0.0.1 uniquement
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
  db:
    # TODO : une version précise de mysql, par exemple 8.4, au lieu de latest
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password

secrets:
  db_password:
    file: ./db_password.txt
```

Le mot de passe sort ainsi du fichier versionné : il vit dans `db_password.txt`, qu'on ne versionne jamais. La base n'a plus de port publié, car seule l'application doit la joindre. `privileged` et le socket Docker ont disparu, car `shop` n'en a aucun besoin.

⚖️ Un raccourci à connaître : pour garder ce lab court, il n'y a pas de `package-lock.json`. Dans un vrai projet, on le versionne et on utilise `npm ci`, pour installer exactement les versions scannées.

```hint
La première ligne du Dockerfile est `FROM node:22-alpine`, et la copie s'écrit `COPY . /app`. Pour l'utilisateur, écrivez `USER node`.
```

```hint
Dans `compose.yaml`, sous `web:`, écrivez `ports:`, puis la ligne `- "127.0.0.1:3000:3000"`. Sous `db:`, écrivez `image: mysql:8.4`.
```

```verify
D="$HOME/byte-layers/docker/scan/shop"
if ! grep -q '^FROM node:22-alpine' "$D/Dockerfile" || ! grep -q '^USER node' "$D/Dockerfile" || ! grep -q '^COPY ' "$D/Dockerfile"; then
  echo "Le Dockerfile doit partir de node:22-alpine, utiliser COPY et passer à USER node."
  exit 1
fi
if grep -q '"4.17.1"\|"4.17.15"' "$D/package.json"; then
  echo "package.json contient encore une ancienne version."
  exit 1
fi
if grep -Eq 'privileged|docker.sock|secret123|:latest' "$D/compose.yaml"; then
  echo "compose.yaml contient encore un réglage à retirer : privileged, le socket, un mot de passe en clair ou latest."
  exit 1
fi
if ! grep -q '127.0.0.1:3000:3000' "$D/compose.yaml"; then
  echo "Le port de web doit être publié sur 127.0.0.1."
  exit 1
fi
echo "Les corrections sont en place."
```

````solution
Le `Dockerfile` :

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY . /app
RUN npm install --omit=dev
USER node
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/ || exit 1
CMD ["node", "index.js"]
```

Le service `web` publie son port avec `ports:` et `- "127.0.0.1:3000:3000"`. Le service `db` commence par `image: mysql:8.4`.
````

## Scanner la nouvelle version

Vous rejouez maintenant les mêmes scans, cette fois sur les fichiers corrigés et sur une nouvelle image :

```exec
cd ~/byte-layers/docker/scan/shop
~/byte-layers/docker/scan/bin/trivy config .
docker build -q -t layers-scan-shop:v2 .
docker save layers-scan-shop:v2 -o shop-v2.tar
~/byte-layers/docker/scan/bin/trivy image --input shop-v2.tar --scanners vuln --severity HIGH,CRITICAL --no-progress
~/byte-layers/docker/scan/bin/grype docker-archive:shop-v2.tar --only-fixed
~/byte-layers/docker/scan/bin/kics scan -p compose.yaml --no-progress; echo "Code de sortie : $?"
```

Les listes doivent avoir nettement raccourci. Elles ne seront pas forcément vides : de nouvelles failles sont publiées chaque jour, et le zéro n'est pas l'objectif. Il s'agit de savoir ce qui reste, et de décider en connaissance de cause.

## Faire échouer une chaîne d'intégration

En intégration continue, on veut qu'un job échoue au-delà d'un certain seuil. Chaque outil a son option, qui agit sur le code de sortie :

| Outil | Option | Effet |
|---|---|---|
| Trivy | `--exit-code 1 --severity CRITICAL` | renvoie `1` s'il trouve au moins une faille CRITICAL |
| Grype | `--fail-on critical` | échoue à partir de la sévérité CRITICAL |
| KICS | `--fail-on high` | n'échoue que pour les résultats HIGH |

Essayez avec Trivy, puis lisez le code de sortie :

```exec
cd ~/byte-layers/docker/scan/shop && ~/byte-layers/docker/scan/bin/trivy image --input shop-v1.tar --scanners vuln --exit-code 1 --severity CRITICAL --no-progress > /dev/null; echo "Code de sortie : $?"
```

🏢 En entreprise, on commence souvent par bloquer sur CRITICAL seulement, puis on abaisse le seuil. Un seuil trop strict dès le premier jour bloque toutes les livraisons, et l'équipe finit par désactiver le scan.

```ack
Je sais rejouer les scans et lire leur code de sortie
```

# Nettoyer

## Libérer l'espace

Les images et les bases de vulnérabilités occupent plusieurs gigaoctets. Vous les supprimez donc avec le dossier du lab :

```exec
docker rmi layers-scan-shop:v1 layers-scan-shop:v2
docker rmi aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c anchore/grype@sha256:6b06708b036f74b2cd70e94b706b4586af96d1932e6ac46255940b2e39dd44a9 checkmarx/kics@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003
docker volume rm layers-scan-cache
cd ~ && rm -rf ~/byte-layers/docker/scan
```

## Récap

- `trivy config` lit le `Dockerfile` sans le construire : c'est le premier contrôle, et le plus rapide.
- Trivy et Grype analysent le contenu d'une image construite. Grype ne lit pas de `Dockerfile`.
- KICS repère dans un fichier Compose le mode privilégié, le socket Docker et les mots de passe en clair.
- `docker save` permet de scanner une image sans donner le socket Docker au scanner.
- Un scanner est aussi un logiciel à risque : on épingle son image par son empreinte `sha256`.
- Le code de sortie transforme un scan en barrière d'intégration continue, et le seuil se choisit selon ce que l'équipe peut traiter.
