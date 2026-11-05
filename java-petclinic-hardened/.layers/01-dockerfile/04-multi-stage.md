---
title: "Construire le JAR dans l'image avec le multi-stage"
description: "Deux stages dans un même Dockerfile : Maven compile, le JRE exécute, et l'ordre des copies garde les dépendances en cache"
---

Au chapitre sur le JAR de la CI, une chaîne d'intégration continue fournissait le JAR. Dans ce chapitre, vous mettez la compilation et l'exécution dans un seul `Dockerfile`, avec un **multi-stage**, sans rien perdre du durcissement. Vous verrez aussi comment l'ordre des copies évite de retélécharger les dépendances à chaque modification du code.

## Pourquoi compiler dans l'image, si la CI le fait déjà ?

Soyons honnêtes : pour une application Java, le cas le plus courant reste celui du chapitre précédent, avec une CI qui compile, teste et fournit le JAR. Le multi-stage se justifie pourtant dans plusieurs situations réelles :

- la CI ne sait que construire des images, et tout passe par `docker build` ;
- les développeurs n'ont pas tous le même JDK, ou n'en ont pas, et `docker build` donne alors partout le même résultat ;
- le projet n'a pas encore de CI, et l'image doit pouvoir se construire depuis le seul code source.

C'est aussi un outil à maîtriser au-delà de Java. Il sert constamment pour Go, Rust ou les applications front-end, dont le résultat de la construction est bien plus léger que les outils qui le produisent. Ici, vous le pratiquez sur un cas que vous connaissez maintenant bien.

## Le principe : plusieurs FROM dans un même Dockerfile

Un `Dockerfile` peut contenir plusieurs `FROM`. Chacun ouvre un **stage**, une construction séparée, avec sa propre image de base et ses propres couches. L'image produite est le **dernier** stage, et lui seul. Il ne garde des stages précédents que ce qu'il copie explicitement, avec `COPY --from` :

```
┌─ stage build : maven + JDK ──────────────┐
│ pom.xml, src/  ->  mvn package  ->  JAR  │──┐
└──────────────────────────────────────────┘  │ COPY --from=build
┌─ stage runtime : JRE seul ───────────────┐  │ (le JAR, et rien d'autre)
│ utilisateur, healthcheck, JAR  <─────────┼──┘
└──────────────────────────────────────────┘
        └── l'image produite
```

| Élément | Rôle |
|---|---|
| `FROM image AS build` | ouvre un stage et lui donne un nom, ici `build` |
| `COPY --from=build /chemin /chemin` | copie un fichier depuis le stage `build`, au lieu du contexte de build |
| le dernier `FROM` | ouvre le stage qui devient l'image. Maven, le JDK et le code source restent dans le stage `build`, et ne sont pas livrés |

Le cours « Réduire une image avec le multi-stage » détaille ce mécanisme sur une application en Go, si vous voulez le voir sur un autre exemple.

## Ordonner les copies pour garder les dépendances en cache

L'image naïve copiait tout le projet, puis lançait Maven. Toute modification de code invalidait donc la couche du `COPY`, et Maven retéléchargeait toutes les dépendances. Or les dépendances sont décrites dans le seul `pom.xml`, qui change rarement, alors que le code de `src/` change sans cesse. On sépare donc la construction en deux temps :

| Instruction | Ce qu'elle produit | Quand Docker la refait |
|---|---|---|
| `COPY pom.xml ./` | la recette seule | quand `pom.xml` change |
| `RUN mvn -B -q dependency:go-offline` | toutes les dépendances, téléchargées dans une couche | quand `pom.xml` change |
| `COPY src ./src` | le code source | à chaque modification du code |
| `RUN mvn -B -q package -DskipTests` | la compilation et le JAR, avec les dépendances déjà présentes | à chaque modification du code |

`dependency:go-offline` est une commande de Maven qui télécharge à l'avance les dépendances et les extensions (les *plugins*) du projet, sans rien compiler. Elle ne prévoit pas tout : quelques plugins se téléchargent encore au moment de `package`. L'essentiel est pourtant en cache tant que `pom.xml` ne change pas, et une modification du code ne coûte plus, pour l'essentiel, que la compilation.

## Écrire le Dockerfile multi-stage

Le second stage, `runtime`, est votre `Dockerfile` du chapitre précédent. Une seule ligne change : le JAR ne vient plus de `target/`, mais du stage `build`. Le premier stage est nouveau, et c'est lui que vous complétez.

Le stage `build` copie le JAR produit sous un nom fixe, `/src/petclinic.jar`. Le nom du JAR contient en effet sa version, et un nom fixe évite au stage `runtime` de la connaître.

Créez le fichier de départ, puis complétez ses blancs dans votre éditeur :

```exec
cat > ~/layers-l10/prod/petclinic/Dockerfile <<'EOF'
# ---- Stage 1 : construire le JAR, avec Maven et un JDK ----
# TODO : partir de l'image Maven utilisée pour simuler la CI, et nommer ce stage build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
# TODO : copier pom.xml dans le dossier courant
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
# TODO : copier le dossier src vers ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# ---- Stage 2 : exécuter le JAR, avec un JRE seul ----
FROM eclipse-temurin:21.0.13_9-jre-noble AS runtime

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

# TODO : copier /src/petclinic.jar du stage build vers /app/petclinic.jar

USER petclinic
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
EOF
```

Le contexte de build change lui aussi. Le stage `build` a besoin de `pom.xml` et de `src/`, et plus du tout du JAR de `target/`, qu'il produit lui-même. Remplacez la liste blanche du `.dockerignore` :

```exec
cat > ~/layers-l10/prod/petclinic/.dockerignore <<'EOF'
# Le contexte de build ne contient que ce que le stage build copie
*
!pom.xml
!src
EOF
```

Construisez l'image avec le tag `3-multistage`. Ce premier passage prend une à deux minutes, car le stage `build` télécharge les dépendances dans sa propre couche : il ne connaît pas le dossier `~/layers-l10/m2` du chapitre sur le JAR de la CI. La ligne `transferring context` affiche cette fois environ 1 Mo, le code source seul :

```exec
cd ~/layers-l10/prod/petclinic && docker build -t layers-l10-petclinic:3-multistage .
```

> 📖 [Les builds multi-stage](https://docs.docker.com/build/building/multi-stage/) · [Le cache de construction](https://docs.docker.com/build/cache/) · [`dependency:go-offline`](https://maven.apache.org/plugins/maven-dependency-plugin/go-offline-mojo.html)

```verify
I=layers-l10-petclinic:3-multistage
F="$HOME/layers-l10/prod/petclinic/Dockerfile"
if ! docker image inspect $I >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Complétez le Dockerfile, puis lancez docker build -t $I ."
  exit 1
fi
if ! grep -qiE '^FROM maven:3\.9\.16-eclipse-temurin-21-noble +AS +build' "$F"; then
  echo "Le premier FROM doit être l'image maven:3.9.16-eclipse-temurin-21-noble, nommée build avec AS build."
  exit 1
fi
P=$(grep -nE '^COPY +pom\.xml' "$F" | head -1 | cut -d: -f1)
S=$(grep -nE '^COPY +src' "$F" | head -1 | cut -d: -f1)
if [ -z "$P" ] || [ -z "$S" ] || [ "$P" -gt "$S" ]; then
  echo "Le stage build doit copier pom.xml, puis src, dans cet ordre."
  exit 1
fi
if ! grep -qE '^COPY +--from=build +/src/petclinic\.jar +/app/petclinic\.jar' "$F"; then
  echo "Le stage runtime doit copier /src/petclinic.jar depuis le stage build, avec COPY --from=build."
  exit 1
fi
if docker run --rm --entrypoint sh $I -c 'command -v mvn' >/dev/null 2>&1; then
  echo "Maven est présent dans l'image $I : l'image produite doit être le stage runtime."
  exit 1
fi
if [ "$(docker image inspect $I --format '{{.Config.User}}')" != "petclinic" ]; then
  echo "L'image ne tourne pas avec l'utilisateur petclinic."
  exit 1
fi
echo "L'image multi-stage est construite : Maven est resté dans le stage build."
```

```hint
Le premier `FROM` s'écrit `FROM maven:3.9.16-eclipse-temurin-21-noble AS build`. Les deux copies s'écrivent `COPY pom.xml ./` et `COPY src ./src`.
```

```hint
Dans le stage `runtime`, la copie s'écrit `COPY --from=build /src/petclinic.jar /app/petclinic.jar`.
```

````solution
```bash
cd ~/layers-l10/prod/petclinic
cat > Dockerfile <<'EOF'
# ---- Stage 1 : construire le JAR, avec Maven et un JDK ----
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# ---- Stage 2 : exécuter le JAR, avec un JRE seul ----
FROM eclipse-temurin:21.0.13_9-jre-noble AS runtime

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

# Du stage build, on ne prend que le JAR
COPY --from=build /src/petclinic.jar /app/petclinic.jar

USER petclinic
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
EOF
printf '%s\n' '# Le contexte de build ne contient que ce que le stage build copie' '*' '!pom.xml' '!src' > .dockerignore
docker build -t layers-l10-petclinic:3-multistage .
```
````

## Modifier le code et observer le cache

Le gain se mesure quand le code change. 🧪 Cette expérience modifie un texte de l'application, puis reconstruit l'image en observant ce que Docker refait.

Changez d'abord le message d'accueil, défini dans le fichier de traductions de PetClinic. `sed -i` remplace le texte directement dans le fichier :

```exec
cd ~/layers-l10/prod/petclinic && sed -i 's/^welcome=Welcome$/welcome=Bienvenue à la clinique/' src/main/resources/messages/messages.properties
grep '^welcome=' src/main/resources/messages/messages.properties
```

Le `grep` doit afficher `welcome=Bienvenue à la clinique`. Reconstruisez ensuite l'image. L'option `--progress=plain` affiche chaque étape en clair, avec sa durée, et `grep` ne garde que les lignes utiles :

```exec
cd ~/layers-l10/prod/petclinic && docker build --progress=plain -t layers-l10-petclinic:3-multistage . 2>&1 | grep -E 'build [0-9]/6|CACHED|DONE [0-9]+\.[0-9]s'
```

Observez les étapes `[build 3/6] COPY pom.xml ./` et `[build 4/6] RUN mvn -B -q dependency:go-offline`. Chacune est suivie de `CACHED` : les dépendances viennent du cache. Seules la copie de `src/` et la compilation se refont, en une vingtaine de secondes, alors que l'image naïve aurait tout retéléchargé.

Lancez la nouvelle image pour voir le changement. La boucle `until` relance le premier `curl` jusqu'à ce que l'application soit prête, et `timeout 120` l'arrête au bout de deux minutes si elle ne démarre pas. Le second `curl` extrait le titre de la page d'accueil :

```exec
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:3-multistage
timeout 120 sh -c 'until curl -s http://localhost:28400/actuator/health | grep -q UP; do sleep 2; done'
curl -s http://localhost:28400/ | grep '<h2>'
```

Vous devez lire le nouveau message :

```
  <h2>Bienvenue à la clinique</h2>
```

```verify
C=layers-l10-petclinic
if [ "$(docker inspect $C --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l10-petclinic:3-multistage" ]; then
  echo "Le conteneur $C ne vient pas de l'image 3-multistage. Supprimez-le avec docker rm -f $C, puis relancez le bloc docker run."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28400/ | grep -q 'Bienvenue à la clinique'; then
  echo "La page d'accueil n'affiche pas le nouveau message. Vérifiez le fichier messages.properties, puis reconstruisez l'image et relancez le conteneur."
  exit 1
fi
echo "Le nouveau message est en ligne."
```

````solution
```bash
cd ~/layers-l10/prod/petclinic
sed -i 's/^welcome=Welcome$/welcome=Bienvenue à la clinique/' src/main/resources/messages/messages.properties
docker build -t layers-l10-petclinic:3-multistage .
docker rm -f layers-l10-petclinic 2>/dev/null
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:3-multistage
timeout 120 sh -c 'until curl -s http://localhost:28400/actuator/health | grep -q UP; do sleep 2; done'
curl -s http://localhost:28400/ | grep '<h2>'
```
````

Supprimez ce conteneur avant le chapitre suivant :

```exec
docker rm -f layers-l10-petclinic
```

## Les trois façons de produire une image Java

Vous avez maintenant pratiqué deux façons de produire l'image, et il en existe une troisième, très répandue dans l'écosystème Java. Elles coexistent, et le choix dépend surtout de l'endroit où l'on compile :

| Façon | Qui compile | Le Dockerfile | On la préfère quand |
|---|---|---|---|
| Le JAR de la CI, copié dans l'image | la CI, avant `docker build` | un seul stage, d'exécution | la CI existe déjà et teste le JAR : c'est le cas le plus courant |
| Le multi-stage | `docker build` | deux stages | tout doit passer par `docker build`, ou il n'y a pas de CI |
| [Jib](https://github.com/GoogleContainerTools/jib) ou les [Buildpacks](https://docs.spring.io/spring-boot/maven-plugin/build-image.html) (`mvn spring-boot:build-image`) | Maven, qui produit lui-même l'image | aucun | l'équipe Java ne veut pas maintenir de `Dockerfile` |

⚖️ Deux optimisations vont plus loin, et elles ne sont pas faites ici. La première est un **cache monté**, `RUN --mount=type=cache,target=/root/.m2`, qui garde les dépendances d'une construction à l'autre même quand `pom.xml` change. La seconde découpe le JAR de Spring Boot en **couches** (les dépendances d'un côté, le code de l'autre), pour que chaque nouvelle version ne pousse que quelques kilo-octets vers le registre. La documentation de Spring Boot sur les [images efficaces](https://docs.spring.io/spring-boot/reference/packaging/container-images/efficient-images.html) décrit ce découpage.

## Questions

```quiz
title: "Le multi-stage"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un Dockerfile a deux `FROM`, nommés `build` et `runtime`. Que contient l'image produite ?"
    answers:
      - "Le stage `runtime`, et ce qu'il a copié du stage `build`"
      - "Le stage `build`, qui contient le JAR"
      - "Les deux stages, empilés"
    correct: 1
    explanation: "Seul le dernier stage devient l'image. Maven et le code source restent dans le stage `build`."
  - prompt: "Pourquoi copier `pom.xml` avant `src/` ?"
    answers:
      - "Parce que Maven exige cet ordre"
      - "Pour que la couche des dépendances ne dépende que de `pom.xml`, et reste en cache quand seul le code change"
      - "Pour réduire la taille de l'image finale"
    correct: 2
    explanation: "Une couche se reconstruit quand ce qu'elle lit change. Séparer `pom.xml` de `src/` isole les dépendances, qui changent rarement, du code, qui change souvent."
```
