---
title: "Passer à une image distroless, et comparer les tailles"
description: "Une image d'exécution sans shell ni gestionnaire de paquets, un healthcheck écrit en Java, puis le bilan des quatre images"
---

Votre image multi-stage ne contient plus d'outils de construction. Elle contient pourtant encore une distribution Ubuntu presque complète : un shell, le gestionnaire de paquets `apt`, `curl` et des centaines de fichiers dont Java n'a pas besoin. Dans ce chapitre, vous passez à une image **distroless**, puis vous comparez les quatre images de cette partie.

## Ce qu'est une image distroless

Une image [distroless](https://github.com/GoogleContainerTools/distroless), publiée par Google, contient l'environnement d'exécution d'un langage et les bibliothèques système dont il a besoin, et rien d'autre. Elle n'a ni shell, ni gestionnaire de paquets, ni outils comme `curl` ou `ls`. Ce que l'image ne contient pas, un attaquant ne peut pas s'en servir : sans shell, une faille dans l'application ne donne pas de ligne de commande. Il y a aussi moins de logiciels à surveiller, et moins de vulnérabilités à corriger.

Ce choix a trois conséquences sur votre `Dockerfile` :

| Conséquence | Pourquoi | Ce que vous faites |
|---|---|---|
| plus de `RUN` dans le stage `runtime` | `RUN` passe par un shell, et il n'y en a pas | vous retirez la création de l'utilisateur |
| un utilisateur déjà prévu | l'image `:nonroot` contient l'utilisateur `nonroot`, d'identifiant 65532 | vous le déclarez avec `USER nonroot`, pour que le `Dockerfile` le dise et que les scanners le voient |
| plus de `curl` pour le healthcheck | l'outil n'existe pas dans l'image | vous écrivez le healthcheck en Java, la seule chose que l'image sait exécuter |

L'image utilisée ici est `gcr.io/distroless/java21-debian13` : Java 21 sur une base Debian 13. Ses tags ne portent pas de numéro de version précis. On en trouve seulement de mouvants, comme `latest`, `nonroot` ou `debug`. Vous allez donc l'**épingler par son empreinte**, avec la forme `image:tag@sha256:…`. Docker télécharge alors exactement ce contenu, et le tag `nonroot` ne sert plus qu'à la lecture humaine :

```
gcr.io/distroless/java21-debian13:nonroot@sha256:b22857e939bd95abd69d9d747f0421a274f9f70855ecfc335f7d97f6eeef578d
```

⚖️ Une empreinte figée ne reçoit plus de correctifs. C'est le prix de la reproductibilité : il faut la mettre à jour régulièrement, et des outils comme Renovate ou Dependabot le font automatiquement, en proposant une modification que l'on relit.

## Écrire un healthcheck en Java

Le healthcheck interroge toujours `/actuator/health`, mais avec un petit programme Java plutôt qu'avec `curl`. Il envoie la requête, attend deux secondes au plus, et sort avec le code `0` si l'application répond `200`, ou `1` sinon, comme Docker l'attend. Créez-le :

```exec
mkdir -p ~/byte-layers/docker/l10/prod/petclinic/healthcheck
cat > ~/byte-layers/docker/l10/prod/petclinic/healthcheck/HealthCheck.java <<'EOF'
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

// Interroge /actuator/health : code de sortie 0 si l'application répond 200, 1 sinon
public class HealthCheck {
    public static void main(String[] args) {
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/actuator/health"))
                    .timeout(Duration.ofSeconds(2))
                    .build();
            HttpResponse<Void> response = HttpClient.newHttpClient()
                    .send(request, HttpResponse.BodyHandlers.discarding());
            System.exit(response.statusCode() == 200 ? 0 : 1);
        } catch (Exception e) {
            System.exit(1);
        }
    }
}
EOF
```

L'image distroless contient un JRE, sans compilateur. Le programme est donc compilé dans le stage `build`, qui a le JDK, avec `javac`, le compilateur Java. Le stage `runtime` ne copie que le résultat, un fichier `.class` dans le dossier `/src/hc`.

Dans le stage `runtime`, le healthcheck s'écrit forcément en **forme exec**, avec des crochets. En forme shell, Docker chercherait un shell pour interpréter la commande, et il n'y en a pas. Les options de `java` gardent ce petit programme léger :

| Option | Rôle |
|---|---|
| `-Xmx16m` | 16 Mo de mémoire au plus, au lieu des 75 % que `JAVA_TOOL_OPTIONS` donnerait aussi à ce programme |
| `-XX:+UseSerialGC` | le ramasse-miettes (le *garbage collector*, qui libère la mémoire inutilisée) le plus simple, qui démarre le plus vite |
| `-XX:TieredStopAtLevel=1` | une compilation rapide, sans optimisation poussée, inutile pour un programme qui dure une demi-seconde |
| `-cp /app/hc HealthCheck` | lancer la classe `HealthCheck`, cherchée dans le dossier `/app/hc` |

⚖️ Ce healthcheck a un coût : toutes les 30 secondes, Docker démarre une seconde JVM dans le conteneur, pendant environ 0,7 seconde et quelques dizaines de mégaoctets. C'est acceptable ici, mais ce n'est pas gratuit. Kubernetes ne connaît pas ce problème : ses sondes peuvent interroger une adresse HTTP directement, sans lancer de commande dans le conteneur. C'est un argument de plus pour laisser celui qui exécute le conteneur décider du healthcheck.

## Écrire le Dockerfile distroless

Le stage `build` gagne deux lignes, qui copient et compilent le healthcheck. Le stage `runtime` change de base, perd son `RUN` et copie un fichier de plus. Créez le fichier de départ, puis complétez ses blancs dans votre éditeur :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/Dockerfile <<'EOF'
# ---- Stage 1 : construire le JAR et le healthcheck, avec Maven et un JDK ----
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# Le healthcheck, compilé ici : l'image finale n'a ni curl, ni shell, ni compilateur
COPY healthcheck/HealthCheck.java ./
RUN javac -d /src/hc HealthCheck.java

# ---- Stage 2 : exécuter le JAR, avec un JRE distroless ----
# TODO : l'image distroless java21-debian13, au tag nonroot, épinglée par son empreinte sha256

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution distroless" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
EXPOSE 8080

# La forme exec est obligatoire : il n'y a pas de shell pour interpréter une chaîne
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/bin/java", "-Xmx16m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-cp", "/app/hc", "HealthCheck"]

COPY --from=build /src/petclinic.jar /app/petclinic.jar
# TODO : copier le dossier /src/hc du stage build vers /app/hc

# TODO : déclarer l'utilisateur nonroot, déjà prévu dans l'image

ENTRYPOINT ["/usr/bin/java", "-jar", "/app/petclinic.jar"]
EOF
```

Le `ENTRYPOINT` et le healthcheck désignent Java par son chemin complet, `/usr/bin/java`, celui qu'utilise l'image distroless elle-même dans son propre `ENTRYPOINT`. Le `--timeout` du healthcheck passe aussi de 3 à 5 secondes : il faut maintenant démarrer une JVM avant de pouvoir interroger l'application.

Le stage `build` copie maintenant le dossier `healthcheck/`, qu'il faut ajouter à la liste blanche du contexte :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/.dockerignore <<'EOF'
# Le contexte de build ne contient que ce que le stage build copie
*
!pom.xml
!src
!healthcheck
EOF
```

Construisez l'image avec le tag `4-distroless`. Les dépendances viennent du cache du chapitre précédent, et seule l'image distroless est à télécharger :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker build -t layers-l10-petclinic:4-distroless .
```

> 📖 [Les images distroless](https://github.com/GoogleContainerTools/distroless) · [Les images Java distroless](https://github.com/GoogleContainerTools/distroless/blob/main/java/README.md) · [Désigner une image par son empreinte](https://docs.docker.com/reference/cli/docker/image/pull/#pull-an-image-by-digest-immutable-identifier)

```verify
I=layers-l10-petclinic:4-distroless
F="$HOME/byte-layers/docker/l10/prod/petclinic/Dockerfile"
if ! docker image inspect $I >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Complétez le Dockerfile, puis lancez docker build -t $I ."
  exit 1
fi
if ! grep -qE '^FROM gcr\.io/distroless/java21-debian13:nonroot@sha256:[0-9a-f]{64}' "$F"; then
  echo "Le second FROM doit être gcr.io/distroless/java21-debian13:nonroot, suivi de @sha256: et de l'empreinte."
  exit 1
fi
if [ "$(docker image inspect $I --format '{{.Config.User}}')" != "nonroot" ]; then
  echo "L'image ne déclare pas l'utilisateur nonroot : il manque l'instruction USER nonroot."
  exit 1
fi
if docker run --rm --entrypoint /bin/sh $I -c true >/dev/null 2>&1; then
  echo "L'image $I contient un shell : elle ne vient pas de l'image distroless."
  exit 1
fi
CID=$(docker create $I)
if ! docker cp "$CID:/app/hc/HealthCheck.class" - >/dev/null 2>&1; then
  docker rm "$CID" >/dev/null
  echo "La classe HealthCheck manque dans /app/hc : vérifiez la copie depuis le stage build."
  exit 1
fi
docker rm "$CID" >/dev/null
echo "L'image distroless est construite, sans shell et avec son healthcheck."
```

```hint
Le `FROM` du second stage s'écrit `FROM gcr.io/distroless/java21-debian13:nonroot@sha256:b22857e939bd95abd69d9d747f0421a274f9f70855ecfc335f7d97f6eeef578d AS runtime`, sur une seule ligne.
```

```hint
La copie s'écrit `COPY --from=build /src/hc /app/hc`, et l'utilisateur `USER nonroot`. Si la construction échoue sur `COPY healthcheck/HealthCheck.java`, vérifiez la ligne `!healthcheck` du `.dockerignore`.
```

````solution
```bash
cd ~/byte-layers/docker/l10/prod/petclinic
cat > Dockerfile <<'EOF'
# ---- Stage 1 : construire le JAR et le healthcheck, avec Maven et un JDK ----
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# Le healthcheck, compilé ici : l'image finale n'a ni curl, ni shell, ni compilateur
COPY healthcheck/HealthCheck.java ./
RUN javac -d /src/hc HealthCheck.java

# ---- Stage 2 : exécuter le JAR, avec un JRE distroless ----
# distroless ne publie pas de tag de version précis : on épingle l'empreinte
FROM gcr.io/distroless/java21-debian13:nonroot@sha256:b22857e939bd95abd69d9d747f0421a274f9f70855ecfc335f7d97f6eeef578d AS runtime

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution distroless" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
EXPOSE 8080

# La forme exec est obligatoire : il n'y a pas de shell pour interpréter une chaîne
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/bin/java", "-Xmx16m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-cp", "/app/hc", "HealthCheck"]

COPY --from=build /src/petclinic.jar /app/petclinic.jar
COPY --from=build /src/hc /app/hc

# L'utilisateur nonroot (UID 65532) existe déjà dans l'image : on le déclare
USER nonroot
ENTRYPOINT ["/usr/bin/java", "-jar", "/app/petclinic.jar"]
EOF
printf '%s\n' '# Le contexte de build ne contient que ce que le stage build copie' '*' '!pom.xml' '!src' '!healthcheck' > .dockerignore
docker build -t layers-l10-petclinic:4-distroless .
```
````

## Lancer l'image distroless

Lancez un conteneur, sous le même nom et sur le même port :

```exec
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:4-distroless
```

Comme au chapitre sur le JAR, relancez `docker ps` jusqu'à lire `(healthy)` dans la colonne `STATUS`. Cette fois, c'est votre programme Java qui l'a décidé :

```exec
docker ps --filter name=layers-l10-petclinic
```

`docker inspect` garde les derniers résultats du healthcheck, avec leur code de sortie et leurs horaires. `.State.Health.Log` est la liste de ces résultats :

```exec
docker inspect layers-l10-petclinic --format '{{json .State.Health.Log}}'
```

Chaque essai affiche `"ExitCode":0`, et environ 0,7 seconde sépare son début de sa fin. La sortie contient aussi la ligne `Picked up JAVA_TOOL_OPTIONS` : la JVM du healthcheck lit la même variable que celle de l'application.

Tentez enfin d'ouvrir un shell dans le conteneur. Cette commande doit échouer :

```exec
docker exec layers-l10-petclinic sh
```

Docker répond `exec: "sh": executable file not found in $PATH`. Il n'y a pas de shell, et c'est exactement le but.

⚖️ Sans shell, le dépannage change. Pour enquêter sur un conteneur qui se comporte mal, on reconstruit temporairement l'image avec le tag `:debug-nonroot` de distroless, qui ajoute un shell minimal (BusyBox). Ce tag ne sert qu'au diagnostic, jamais en production.

```verify
C=layers-l10-petclinic
if [ "$(docker inspect $C --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l10-petclinic:4-distroless" ]; then
  echo "Le conteneur $C ne vient pas de l'image 4-distroless. Supprimez-le avec docker rm -f $C, puis relancez docker run avec cette image."
  exit 1
fi
H=$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')
if [ "$H" != "healthy" ]; then
  echo "Le conteneur n'est pas encore healthy (état : ${H:-aucun}). Attendez une quinzaine de secondes, puis vérifiez à nouveau."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28400/actuator/health | grep -q '"status":"UP"'; then
  echo "http://localhost:28400/actuator/health ne répond pas UP."
  exit 1
fi
echo "L'image distroless tourne, et son healthcheck en Java répond."
```

````solution
```bash
docker rm -f layers-l10-petclinic 2>/dev/null
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:4-distroless
sleep 20
docker ps --filter name=layers-l10-petclinic
```
````

## Comparer la taille des quatre images

Vous avez maintenant les quatre images de cette partie, et `docker images` les liste côte à côte. Selon la version de Docker, la taille se lit dans la colonne `SIZE` ou `DISK USAGE` :

```exec
docker images layers-l10-petclinic
```

Voici les valeurs mesurées sur un poste Linux :

| Image | Taille | Ce qu'elle contient |
|---|---|---|
| `1-naive` | 792 Mo | Ubuntu, Maven, le JDK, le code source, les dépendances téléchargées et le JAR |
| `2-jar` | 354 Mo | Ubuntu, le JRE et le JAR |
| `3-multistage` | 354 Mo | la même chose : le multi-stage change la façon de construire, pas le résultat |
| `4-distroless` | 258 Mo | Debian réduite au minimum, le JRE, le JAR et le healthcheck |

Trois enseignements se dégagent de ce tableau. L'image passe de 792 à 258 Mo, soit les deux tiers en moins, sans toucher à l'application. Le multi-stage n'allège rien par rapport au JAR de la CI : il déplace la compilation, et son intérêt est ailleurs. Enfin, le JRE (165 Mo) et le JAR (66 Mo) représentent près de 90 % de l'image distroless, comme le montre la commande `docker history layers-l10-petclinic:4-distroless`, qui liste les couches de l'image avec leur taille : lancez-la pour le constater. Pour descendre encore, il faudrait réduire Java lui-même, et non plus ce qui l'entoure.

## Ce que la taille d'une image change vraiment

La taille n'est pas qu'une question d'esthétique, et elle a des effets concrets. Une image plus petite se télécharge plus vite, ce qui compte à chaque déploiement et à chaque démarrage sur une nouvelle machine. Elle occupe moins de disque sur chaque serveur et dans le registre : sur un serveur qui garde plusieurs versions de plusieurs applications, la différence se compte en dizaines de gigaoctets. Et elle contient moins de logiciels, donc moins de failles possibles.

La taille n'est pourtant pas le seul critère. Une image distroless se dépanne moins facilement, et l'équipe doit apprendre à s'en servir. Le nombre de vulnérabilités, lui, dépend aussi de la distribution de base, et surtout des dépendances de l'application : le chapitre facultatif qui suit le montre sur ces images. Deux autres pistes existent pour aller plus loin :

| Piste | Le principe | Ce qu'elle coûte |
|---|---|---|
| un JRE sur Alpine (`eclipse-temurin:21.0.13_9-jre-alpine-3.24`, par exemple) | une distribution de base de quelques mégaoctets | Alpine utilise une autre bibliothèque C, `musl`, et certains comportements de Java ou de bibliothèques natives diffèrent |
| un JRE sur mesure avec `jlink` | ne garder que les modules de Java dont l'application se sert | une étape de construction de plus, à maintenir, et un gain modeste avec Spring Boot, qui utilise beaucoup de modules |

> 📖 Pour aller plus loin : [Réduire la taille d'une image Docker](https://enix.io/fr/blog/reduire-taille-image-docker/), un article d'Enix sur le sujet.

## Questions

```quiz
title: "Distroless et taille d'image"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi le healthcheck de l'image distroless s'écrit-il en forme exec, avec des crochets ?"
    answers:
      - "Parce que la forme shell a besoin d'un shell pour interpréter la commande, et que l'image n'en a pas"
      - "Parce que la forme exec est plus rapide"
      - "Parce que Java l'exige"
    correct: 1
    explanation: "En forme shell, Docker lance `/bin/sh -c`. Sans shell dans l'image, seule la forme exec, qui lance directement le programme, fonctionne."
  - prompt: "L'image distroless n'a pas de tag de version précis. Comment la figer ?"
    answers:
      - "Avec le tag `latest`"
      - "Avec son empreinte : `image:tag@sha256:…`"
      - "Ce n'est pas possible"
    correct: 2
    explanation: "L'empreinte désigne un contenu exact. Il faut la mettre à jour régulièrement pour recevoir les correctifs, ce que Renovate ou Dependabot automatisent."
  - prompt: "Passer de l'image `2-jar` à l'image `3-multistage` a-t-il réduit la taille ?"
    answers:
      - "Oui, de moitié"
      - "Non, l'image a grossi"
      - "Non : le stage final est le même, seule la façon de produire le JAR a changé"
    correct: 3
    explanation: "Les deux images ont le même stage d'exécution. Le multi-stage déplace la compilation dans `docker build`, il n'allège pas l'image par rapport à un JAR fourni par la CI."
```
