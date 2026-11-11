---
title: "Livrer dans une image durcie le JAR compilé par la CI"
description: "Compiler le JAR comme le ferait une chaîne d'intégration continue, puis écrire une image d'exécution sans aucun défaut de configuration"
---

L'image naïve compilait l'application elle-même. Ce n'est pourtant pas ainsi qu'on procède le plus souvent avec une application Java. Dans ce chapitre, vous séparez les deux métiers : un conteneur Maven compile le JAR, comme le ferait une chaîne d'intégration continue, et un `Dockerfile` durci ne fait plus que l'exécuter.

## Dans la vraie vie, la CI compile le JAR

Dans une équipe Java, le JAR est presque toujours produit en amont, par la **chaîne d'intégration continue** (la CI : GitLab CI, GitHub Actions, Jenkins…). Elle lance les tests unitaires, l'analyse de code et la compilation. Elle dépose ensuite le JAR, avec un numéro de version, dans un dépôt d'artefacts comme Nexus, Artifactory ou le registre de paquets de GitLab. Le `Dockerfile` ne fait alors qu'une chose : copier ce JAR dans une image qui sait l'exécuter.

Cette organisation a deux avantages. Le JAR livré est exactement celui qui a passé les tests, au bit près. Et l'image d'exécution ne contient aucun outil de construction : ni Maven, ni compilateur, ni code source.

## Simuler la CI : compiler le JAR dans un conteneur Maven

Votre poste n'a ni Java ni Maven, et vous n'allez pas les installer : un conteneur Maven jouera le rôle de la CI. Voici la commande, avant de la lancer :

```bash
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$PWD":/src -w /src \
  -v "$HOME/byte-layers/docker/l10/m2":/var/maven/.m2 -e MAVEN_CONFIG=/var/maven/.m2 \
  maven:3.9.16-eclipse-temurin-21-noble \
  mvn -B -q -Duser.home=/var/maven package -DskipTests
```

| Option | Rôle |
|---|---|
| `--rm` | supprime le conteneur à la fin de la compilation |
| `-u "$(id -u):$(id -g)"` | lance Maven avec votre utilisateur et votre groupe, et non en root : les fichiers produits dans `target/` vous appartiendront |
| `-v "$PWD":/src -w /src` | monte le dossier du projet dans le conteneur, et s'y place |
| `-v "$HOME/byte-layers/docker/l10/m2":/var/maven/.m2` | garde les dépendances téléchargées dans `~/byte-layers/docker/l10/m2` sur votre poste : la compilation suivante ne les retéléchargera pas, comme le cache d'une CI. Ce dossier est dédié au cas pratique, pour ne pas toucher au `~/.m2` d'un poste de développeur Java, qui contient souvent son `settings.xml` |
| `-e MAVEN_CONFIG` et `-Duser.home` | disent à Maven où trouver ce dossier, puisque votre utilisateur n'a pas de dossier personnel dans le conteneur |
| `maven:3.9.16-eclipse-temurin-21-noble` | Maven 3.9.16, avec le JDK Temurin 21, sur Ubuntu 24.04 : la version exacte, pas `latest` |
| `-B -q` | le mode non interactif d'une CI, et des journaux réduits aux erreurs |
| `package -DskipTests` | compiler et produire le JAR, sans lancer les tests |

⚖️ Deux raccourcis sont à connaître. `-DskipTests` saute les tests, parce qu'une vraie CI les lance avant, et parce que ceux de PetClinic démarrent eux-mêmes des bases de données dans Docker, ce qui serait long ici. Java 21 est par ailleurs plus récent que le Java 17 du `pom.xml`. C'est voulu : 17 est la version **minimale** du projet, et 21 est une version maintenue à long terme (LTS). Ce qui compte, c'est que la version soit choisie et écrite, et non subie comme avec `latest`.

Le dossier `~/byte-layers/docker/l10/m2` doit exister avant la commande. Sinon, Docker le créerait lui-même, avec root pour propriétaire, et Maven ne pourrait plus y écrire. Lancez maintenant la compilation, qui prend une à deux minutes la première fois :

```exec
mkdir -p ~/byte-layers/docker/l10/m2
cd ~/byte-layers/docker/l10/prod/petclinic && docker run --rm -u "$(id -u):$(id -g)" \
  -v "$PWD":/src -w /src \
  -v "$HOME/byte-layers/docker/l10/m2":/var/maven/.m2 -e MAVEN_CONFIG=/var/maven/.m2 \
  maven:3.9.16-eclipse-temurin-21-noble \
  mvn -B -q -Duser.home=/var/maven package -DskipTests
```

Avec `-q`, Maven n'affiche rien quand tout va bien. Contrôlez le résultat dans `target/` :

```exec
ls -l ~/byte-layers/docker/l10/prod/petclinic/target/*.jar
```

Vous devez lire un fichier `spring-petclinic-4.0.0-SNAPSHOT.jar` d'environ 66 Mo, dont vous êtes le propriétaire. Le suffixe `SNAPSHOT` est la convention de Maven pour une version en cours de développement, qui n'a pas encore été publiée. Sa date, en 2024, n'est pas une erreur : PetClinic fixe la date des fichiers du JAR, pour que deux compilations du même code produisent exactement le même fichier.

```verify
J=$(ls "$HOME"/byte-layers/docker/l10/prod/petclinic/target/spring-petclinic-*.jar 2>/dev/null | head -1)
if [ -z "$J" ]; then
  echo "Aucun JAR dans ~/byte-layers/docker/l10/prod/petclinic/target. Relancez la compilation, et lisez ses erreurs."
  exit 1
fi
if [ "$(stat -c %u "$J")" != "$(id -u)" ]; then
  echo "Le JAR appartient à root : l'option -u a été oubliée. Supprimez target/ avec un conteneur (docker run --rm -v \"\$PWD\":/src alpine:3.22 rm -rf /src/target), puis relancez la compilation."
  exit 1
fi
echo "Le JAR est compilé, et il vous appartient."
```

```hint
Si Maven répond `Permission denied` sur `/var/maven/.m2`, le dossier `~/byte-layers/docker/l10/m2` a été créé par Docker, en root. Supprimez-le avec un conteneur, `docker run --rm -v "$HOME/byte-layers/docker/l10":/h alpine:3.22 rm -rf /h/m2`, puis relancez `mkdir -p ~/byte-layers/docker/l10/m2` et la compilation.
```

````solution
```bash
mkdir -p ~/byte-layers/docker/l10/m2
cd ~/byte-layers/docker/l10/prod/petclinic
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$PWD":/src -w /src \
  -v "$HOME/byte-layers/docker/l10/m2":/var/maven/.m2 -e MAVEN_CONFIG=/var/maven/.m2 \
  maven:3.9.16-eclipse-temurin-21-noble \
  mvn -B -q -Duser.home=/var/maven package -DskipTests
ls -l target/*.jar
```
````

## Choisir l'image d'exécution et lire son tag

Le JAR n'a besoin que d'un JRE pour tourner. Vous allez partir de l'image `eclipse-temurin`, la distribution de Java d'Eclipse Adoptium, en version JRE. Son tag le plus précis se décompose ainsi :

```
eclipse-temurin:21.0.13_9-jre-noble
                └──┬──┘ ┬ └┬┘ └─┬─┘
                   │    │  │    └─── la distribution de base : Ubuntu 24.04, nom de code noble
                   │    │  └──────── jre : l'exécution seule, sans compilateur (jdk : tout le kit)
                   │    └─────────── le numéro de construction de cette version
                   └──────────────── la version exacte de Java
```

Il existe des tags plus courts, comme `21-jre` ou `21-jre-noble`. Ils sont pratiques, mais ils avancent avec chaque correctif. Pour une image de production, il vaut mieux le tag le plus précis : vous savez alors exactement ce que vous livrez, et vous changez de version par une modification visible du `Dockerfile`, que l'on peut relire et tester.

Eclipse Temurin est une distribution de Java libre et gratuite, y compris en production. Ce n'est pas le cas de toutes : l'Oracle JDK a ses propres conditions de licence, payantes dans certains cas, à vérifier avant de l'utiliser en entreprise.

🏢 Pour une application Java plus ancienne, la démarche est la même. Il existe des tags précis pour Java 8 et 11, de la forme `eclipse-temurin:8u…-jre` ou `11.0.…-jre-noble`. Une application livrée en WAR, et non en JAR exécutable, part plutôt de l'image officielle `tomcat`, avec un tag aussi précis, et copie le WAR dans son dossier `webapps/`. Les images distroless du dernier chapitre n'existent en revanche que pour les versions récentes de Java (17, 21 et 25).

⚖️ Même le tag le plus précis peut être republié. Seule l'**empreinte** de l'image, son `sha256`, garantit un contenu identique. Vous l'utiliserez au chapitre distroless, dont les images n'ont pas de tag de version.

## Écrire le Dockerfile d'exécution durci

Chaque instruction de ce `Dockerfile` corrige un défaut relevé sur l'image naïve, ou en prévient un. Le tableau les présente dans l'ordre du fichier :

| Instruction | Rôle |
|---|---|
| `FROM` | l'image de JRE, avec son tag complet |
| `LABEL` | des métadonnées au format standard [OCI](https://github.com/opencontainers/image-spec/blob/main/annotations.md) : nom, source, licence. Les registres et les scanners les affichent |
| `RUN groupadd … useradd …` | crée un groupe et un utilisateur système, `petclinic`, avec l'identifiant fixe 10001, sans dossier personnel ni shell de connexion |
| `WORKDIR /app` | le dossier de l'application |
| `ENV JAVA_TOOL_OPTIONS` | une variable que toute **JVM** (la machine virtuelle Java, le programme qui exécute le JAR) lit au démarrage. `-XX:MaxRAMPercentage=75` donne à Java 75 % de la mémoire accordée au conteneur. Sans elle, Java n'en prend qu'un quart |
| `EXPOSE 8080` | documente le port de l'application |
| `HEALTHCHECK` | la commande que Docker lance à intervalles réguliers, pour savoir si l'application répond |
| `COPY` | copie le JAR dans l'image |
| `USER` | passe à l'utilisateur sans droits, pour tout ce qui suit et pour l'exécution |
| `ENTRYPOINT [...]` | lance Java en **forme exec**, avec des crochets : Java devient le PID 1 et reçoit le signal d'arrêt |

L'**ordre** compte, à cause du cache de construction. Docker réutilise une couche tant que l'instruction et ce qu'elle lit n'ont pas changé, et il reconstruit tout ce qui suit la première couche modifiée. Ce qui change rarement vient donc en premier : l'utilisateur, les variables, le healthcheck. Le JAR, qui change à chaque version, vient en dernier.

Le healthcheck interroge l'adresse `/actuator/health` déjà vue. Cette image contient `curl`, ce qui le rend simple :

| Option | Rôle |
|---|---|
| `--interval=30s` | le temps entre deux tests |
| `--timeout=3s` | le temps laissé à la commande pour répondre |
| `--start-period=60s` | le délai de démarrage : un échec pendant cette minute ne compte pas |
| `--retries=3` | le nombre d'échecs de suite avant l'état `unhealthy` |
| `CMD curl -fsS … \|\| exit 1` | `-f` fait échouer `curl` sur une erreur HTTP, `-sS` le rend silencieux sauf en cas d'erreur, et `exit 1` renvoie le code que Docker attend pour un échec |

⚖️ Un healthcheck écrit dans le `Dockerfile` n'est qu'une proposition par défaut. C'est à celui qui exécute le conteneur de décider comment le surveiller : selon la charge ou la politique de l'équipe, il pourra changer l'intervalle, la commande ou l'adresse. Compose et Kubernetes ont chacun leur propre réglage, et le fichier Compose de la partie B remplacera celui-ci. Le mettre dans le `Dockerfile` reste utile : l'image se surveille déjà correctement avec un simple `docker run`.

Créez le fichier de départ, puis complétez ses blancs dans votre éditeur. Il remplace le `Dockerfile` naïf, dont l'image reste disponible sous le tag `1-naive` :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/Dockerfile <<'EOF'
# TODO : l'image eclipse-temurin, en JRE 21, avec son tag le plus précis

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN groupadd --system --gid 10001 petclinic \
 && useradd --system --uid 10001 --gid petclinic --no-create-home --shell /usr/sbin/nologin petclinic

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

# TODO : documenter le port 8080

# TODO : un healthcheck sur http://localhost:8080/actuator/health, avec les quatre options du tableau

# TODO : copier le JAR de target/ vers /app/petclinic.jar (le nom du JAR contient sa version : utilisez spring-petclinic-*.jar)

# TODO : passer à l'utilisateur petclinic

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
EOF
```

Le `COPY` copie le JAR en laissant root pour propriétaire. L'utilisateur `petclinic` peut le lire et l'exécuter, mais pas le modifier : une application compromise ne peut pas remplacer son propre code.

Avant de construire, il reste le **contexte de build** : les fichiers que `docker build` envoie au moteur. Sans précaution, il envoie tout le dossier. Un fichier `.dockerignore` filtre ce contexte, et l'écriture la plus sûre est une **liste blanche** : `*` exclut tout, puis chaque ligne qui commence par `!` réintègre ce qui est nécessaire. Ici, seul le JAR est nécessaire :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/.dockerignore <<'EOF'
# Le contexte de build ne contient que le JAR
*
!target/spring-petclinic-*.jar
EOF
```

Une liste blanche vous protège aussi d'un oubli. Un fichier `.env` ou une clé laissés dans le dossier ne partiront pas dans le contexte, même si un `COPY . .` est ajouté un jour.

Une fois le `Dockerfile` complété, construisez l'image avec le tag `2-jar`. Dans les journaux de construction, la ligne `transferring context` montre la taille du contexte, environ 66 Mo, c'est-à-dire le JAR seul :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker build -t layers-l10-petclinic:2-jar .
```

> 📖 [La référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck) · [Le fichier `.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files) · [L'image `eclipse-temurin`](https://hub.docker.com/_/eclipse-temurin)

```verify
I=layers-l10-petclinic:2-jar
F="$HOME/byte-layers/docker/l10/prod/petclinic/Dockerfile"
if ! docker image inspect $I >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Complétez le Dockerfile, puis lancez docker build -t $I ."
  exit 1
fi
if ! grep -qE '^FROM eclipse-temurin:21\.0\.[0-9]+_[0-9]+-jre-noble' "$F"; then
  echo "Le FROM doit utiliser eclipse-temurin avec son tag le plus précis, de la forme 21.0.13_9-jre-noble."
  exit 1
fi
if [ "$(docker image inspect $I --format '{{.Config.User}}')" != "petclinic" ]; then
  echo "L'image ne passe pas à l'utilisateur petclinic : il manque l'instruction USER petclinic."
  exit 1
fi
if [ -z "$(docker image inspect $I --format '{{if .Config.Healthcheck}}{{.Config.Healthcheck.Test}}{{end}}')" ]; then
  echo "L'image n'a pas de HEALTHCHECK."
  exit 1
fi
if ! docker image inspect $I --format '{{range $p, $x := .Config.ExposedPorts}}{{$p}} {{end}}' | grep -q '8080/tcp'; then
  echo "L'image ne documente pas le port 8080 : il manque EXPOSE 8080."
  exit 1
fi
echo "L'image 2-jar est construite, avec un utilisateur sans droits et un healthcheck."
```

```hint
Le `FROM` s'écrit `FROM eclipse-temurin:21.0.13_9-jre-noble`. Le port s'écrit `EXPOSE 8080`, et l'utilisateur `USER petclinic`.
```

```hint
Le healthcheck tient sur deux lignes : `HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \`, puis `  CMD curl -fsS http://localhost:8080/actuator/health || exit 1`. La copie s'écrit `COPY target/spring-petclinic-*.jar /app/petclinic.jar`.
```

````solution
```bash
cd ~/byte-layers/docker/l10/prod/petclinic
cat > Dockerfile <<'EOF'
FROM eclipse-temurin:21.0.13_9-jre-noble

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN groupadd --system --gid 10001 petclinic \
 && useradd --system --uid 10001 --gid petclinic --no-create-home --shell /usr/sbin/nologin petclinic

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

COPY target/spring-petclinic-*.jar /app/petclinic.jar

USER petclinic

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
EOF
docker build -t layers-l10-petclinic:2-jar .
```
````

## Lancer l'image durcie et contrôler ses corrections

Lancez un conteneur de cette image, sous le même nom et sur le même port qu'au chapitre précédent :

```exec
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:2-jar
```

Docker affiche maintenant l'état de santé du conteneur dans `docker ps`. Il commence par `health: starting`, puis passe à `healthy` une fois que le healthcheck a réussi. Relancez la commande jusqu'à lire `(healthy)` dans la colonne `STATUS`, ce qui prend une quinzaine de secondes. Pendant la période de démarrage, Docker ne respecte pas l'intervalle de 30 secondes : il teste toutes les 5 secondes, la valeur par défaut de l'option `--start-interval`, pour annoncer l'application prête au plus tôt :

```exec
docker ps --filter name=layers-l10-petclinic
```

Contrôlez ensuite deux corrections, l'utilisateur et l'arrêt. L'utilisateur est maintenant `uid=10001(petclinic)`. Et `docker stop` rend la main en quelques secondes au plus, au lieu de dix, parce que Java, devenu PID 1, reçoit le signal et s'arrête proprement :

```exec
docker exec layers-l10-petclinic id
time docker stop layers-l10-petclinic
```

Le code de sortie le confirme : `docker inspect layers-l10-petclinic --format '{{.State.ExitCode}}'` répond `143`, soit 128 + 15 : le signal 15, `SIGTERM`, l'arrêt demandé poliment, et non plus `137`. Au démarrage, les journaux contiennent aussi une ligne `Picked up JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75`. Ce n'est pas une erreur : la JVM signale qu'elle a lu la variable.

Relancez enfin le conteneur, que le contrôle vérifie en marche :

```exec
docker start layers-l10-petclinic
```

```verify
C=layers-l10-petclinic
if [ "$(docker inspect $C --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l10-petclinic:2-jar" ]; then
  echo "Le conteneur $C ne vient pas de l'image 2-jar. Supprimez-le avec docker rm -f $C, puis relancez docker run avec cette image."
  exit 1
fi
H=$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')
if [ "$H" != "healthy" ]; then
  echo "Le conteneur n'est pas encore healthy (état : ${H:-aucun}). Attendez une quinzaine de secondes, puis vérifiez à nouveau."
  exit 1
fi
if [ "$(docker exec $C id -u)" != "10001" ]; then
  echo "L'application ne tourne pas avec l'utilisateur 10001."
  exit 1
fi
echo "L'image durcie tourne, en bonne santé et sans droits."
```

````solution
```bash
docker rm -f layers-l10-petclinic 2>/dev/null
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:2-jar
sleep 20
docker ps --filter name=layers-l10-petclinic
```
````

Supprimez ce conteneur avant de passer à la suite :

```exec
docker rm -f layers-l10-petclinic
```

## Questions

```quiz
title: "L'image d'exécution"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi le `COPY` du JAR vient-il après le `HEALTHCHECK` et la création de l'utilisateur ?"
    answers:
      - "Parce que Docker l'exige"
      - "Parce que le JAR change à chaque version : placé en dernier, il ne force pas la reconstruction des couches qui ne changent pas"
      - "Parce que l'utilisateur doit exister pour lire le JAR"
    correct: 2
    explanation: "Docker reconstruit tout ce qui suit la première couche modifiée. Ce qui change souvent se place donc le plus bas possible."
  - prompt: "Qui devrait décider du healthcheck d'une application en production ?"
    answers:
      - "Uniquement l'auteur de l'image, dans le `Dockerfile`"
      - "Personne : Docker sait déjà si l'application répond"
      - "Celui qui exécute le conteneur, qui peut remplacer la proposition du `Dockerfile` dans Compose ou Kubernetes"
    correct: 3
    explanation: "Le `HEALTHCHECK` du `Dockerfile` est un défaut utile. L'exploitant le règle selon son contexte, et Docker, sans healthcheck, sait seulement que le processus tourne."
```
