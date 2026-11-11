---
title: "Lancer PetClinic avec un Dockerfile naïf"
description: "Récupérer le code à une version figée, le construire et le lancer, puis relever ce qui ne va pas"
---

Avant de durcir une image, il faut savoir ce qu'on lui reproche. Dans ce chapitre, vous lancez PetClinic avec le `Dockerfile` le plus court qui fonctionne. Vous relevez ensuite ses défauts, un par un, et les chapitres suivants les corrigeront.

## Récupérer le code de PetClinic à une version figée

Le code de PetClinic est sur GitHub. Vous allez le télécharger à un **commit** précis, c'est-à-dire à un état exact du dépôt, identifié par une empreinte. C'est la même idée qu'une version d'image précise : dans six mois, la commande téléchargera exactement le même code, et le cas pratique fonctionnera toujours.

GitHub sert une archive de n'importe quel commit. `curl -L` la télécharge en suivant les redirections, et `tar xz` la décompresse au fil de l'eau. `--strip-components=1` retire le dossier racine de l'archive, pour que les fichiers arrivent directement dans le dossier courant :

```exec
mkdir -p ~/byte-layers/docker/l10/prod/petclinic && cd ~/byte-layers/docker/l10/prod/petclinic
curl -L https://codeload.github.com/spring-projects/spring-petclinic/tar.gz/500158f732419217507c7656904b8e6aa1bcc0d6 | tar xz --strip-components=1
ls
```

Parmi les fichiers listés, trois comptent pour la suite :

| Fichier ou dossier | Rôle |
|---|---|
| `pom.xml` | la recette de construction pour **Maven**, l'outil de construction le plus courant en Java : la version de Java visée, les bibliothèques dont l'application dépend (ses **dépendances**), et comment produire le résultat |
| `src/` | le code Java, les pages HTML et la configuration de l'application |
| `mvnw` | le *Maven wrapper* : un script qui télécharge la bonne version de Maven. Vous ne l'utiliserez pas, car Maven viendra d'une image Docker |

Le résultat de la construction est un **JAR** : une archive qui contient l'application compilée et toutes ses dépendances. Spring Boot y embarque même le serveur web, Tomcat. Un seul fichier suffit donc pour lancer l'application, avec la commande `java -jar`, et il ne faut rien d'autre qu'un environnement d'exécution Java, le **JRE**.

Le dépôt contient aussi un `docker-compose.yml` et un dossier `k8s/`, fournis par les auteurs de PetClinic. Vous écrirez les vôtres, et ceux-ci ne feraient que gêner : Compose afficherait un avertissement en trouvant deux fichiers dans le même dossier, et un scanner les analyserait aussi. Supprimez-les :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && rm -r docker-compose.yml k8s
```

```verify
P="$HOME/byte-layers/docker/l10/prod/petclinic"
if [ ! -s "$P/pom.xml" ] || [ ! -d "$P/src/main/java" ]; then
  echo "Le code de PetClinic manque dans $P. Relancez le bloc de téléchargement."
  exit 1
fi
if [ -e "$P/docker-compose.yml" ] || [ -e "$P/k8s" ]; then
  echo "Le docker-compose.yml ou le dossier k8s/ du dépôt est encore là. Supprimez-les avec rm -r docker-compose.yml k8s, depuis $P."
  exit 1
fi
if ! grep -q '<java.version>17</java.version>' "$P/pom.xml"; then
  echo "Le pom.xml n'est pas celui du commit attendu. Videz $P, puis relancez le bloc de téléchargement."
  exit 1
fi
echo "Le code de PetClinic est en place."
```

````solution
```bash
rm -rf ~/byte-layers/docker/l10/prod/petclinic
mkdir -p ~/byte-layers/docker/l10/prod/petclinic && cd ~/byte-layers/docker/l10/prod/petclinic
curl -L https://codeload.github.com/spring-projects/spring-petclinic/tar.gz/500158f732419217507c7656904b8e6aa1bcc0d6 | tar xz --strip-components=1
rm -r docker-compose.yml k8s
```
````

## Écrire un Dockerfile naïf, qui marche et rien de plus

Voici un `Dockerfile` comme on en trouve beaucoup : il part d'une image qui contient Maven, copie tout le projet, le compile et lance le JAR. Il fonctionne, et c'est son seul mérite :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/Dockerfile <<'EOF'
FROM maven
COPY . /app
WORKDIR /app
RUN mvn package -DskipTests
EXPOSE 8080
CMD java -jar target/*.jar
EOF
```

| Instruction | Ce qu'elle fait |
|---|---|
| `FROM maven` | part de l'image officielle `maven`, qui contient Maven et un JDK, l'environnement de développement Java complet avec le compilateur |
| `COPY . /app` | copie tout le dossier du projet dans l'image |
| `RUN mvn package -DskipTests` | télécharge les dépendances, compile et produit le JAR dans `target/`, sans lancer les tests |
| `EXPOSE 8080` | indique que l'application écoute sur le port 8080, celui de Tomcat par défaut |
| `CMD java -jar target/*.jar` | lance le JAR au démarrage du conteneur |

```verify
F="$HOME/byte-layers/docker/l10/prod/petclinic/Dockerfile"
if [ ! -s "$F" ] || ! grep -q '^FROM maven$' "$F"; then
  echo "Le Dockerfile naïf manque dans ~/byte-layers/docker/l10/prod/petclinic. Relancez le bloc qui le crée."
  exit 1
fi
echo "Le Dockerfile naïf est en place."
```

````solution
Il n'y a rien à compléter ici : relancez le bloc qui crée le `Dockerfile`, puis vérifiez à nouveau.
````

## Construire l'image et lancer PetClinic

Construisez l'image avec le tag `1-naive`. Le premier lancement prend une à deux minutes, le temps de télécharger l'image `maven`, puis les dépendances de PetClinic :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker build -t layers-l10-petclinic:1-naive .
```

Lancez ensuite un conteneur, en publiant le port 8080 du conteneur sur le port 28400 de la machine. L'adresse `127.0.0.1` devant le port limite cette publication à la machine elle-même : sans elle, le port serait ouvert sur toutes ses interfaces réseau, et donc joignable depuis l'extérieur d'un serveur :

```exec
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:1-naive
```

Une application Spring Boot met quelques secondes à démarrer. Ses journaux disent quand elle est prête :

```exec
docker logs layers-l10-petclinic
```

Cherchez vers la fin une ligne comme celle-ci. Si elle n'y est pas encore, relancez la commande quelques secondes plus tard :

```
o.s.s.petclinic.PetClinicApplication     : Started PetClinicApplication in 3.379 seconds (process running for 3.651)
```

Un peu plus haut, les journaux indiquent aussi `Database driver: H2 JDBC Driver`. Sans configuration, PetClinic utilise **H2**, une base de données en mémoire, lancée dans le même processus. C'est pratique pour un premier essai, sans aucune base à installer. Le revers est que les données disparaissent à chaque arrêt : la partie B la remplacera par PostgreSQL.

Interrogez maintenant l'application. Spring Boot fournit, avec son module **Actuator**, une adresse qui dit si l'application va bien, `/actuator/health` :

```exec
curl http://localhost:28400/actuator/health
```

Vous devez lire cette réponse, où `UP` veut dire que l'application est prête :

```
{"groups":["liveness","readiness"],"status":"UP"}
```

Ouvrez aussi `http://localhost:28400` dans votre navigateur. Vous y trouvez la page d'accueil de la clinique, et le menu **Find owners** liste les propriétaires de démonstration.

```verify
C=layers-l10-petclinic
if [ "$(docker inspect $C --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le conteneur $C ne tourne pas. Lancez docker run, puis lisez docker logs $C."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28400/actuator/health | grep -q '"status":"UP"'; then
  echo "http://localhost:28400/actuator/health ne répond pas UP. Attendez quelques secondes, puis vérifiez à nouveau."
  exit 1
fi
echo "PetClinic répond sur le port 28400."
```

```hint
Si `docker run` répond que le nom `layers-l10-petclinic` est déjà utilisé, supprimez l'ancien conteneur avec `docker rm -f layers-l10-petclinic`, puis relancez-le.
```

````solution
```bash
cd ~/byte-layers/docker/l10/prod/petclinic
docker build -t layers-l10-petclinic:1-naive .
docker rm -f layers-l10-petclinic 2>/dev/null
docker run -d --name layers-l10-petclinic -p 127.0.0.1:28400:8080 layers-l10-petclinic:1-naive
sleep 15
curl http://localhost:28400/actuator/health
```
````

## Relever les défauts de l'image naïve

L'application tourne, et c'est maintenant que le travail commence. Voici cinq observations, chacune avec sa commande.

La première porte sur l'utilisateur. `docker exec` lance une commande dans le conteneur, et `id` affiche l'utilisateur courant :

```exec
docker exec layers-l10-petclinic id
```

La réponse est `uid=0(root)` : l'application tourne en **root**. Si une faille de PetClinic ou de Tomcat est exploitée, l'attaquant obtient ces droits dans le conteneur.

La deuxième porte sur les versions. Le `pom.xml` vise Java 17, et voici ce que l'image contient vraiment, pour Java puis pour Maven :

```exec
docker exec layers-l10-petclinic java -version
docker exec layers-l10-petclinic mvn -v
```

Le 5 novembre 2026, cette commande affichait `openjdk version "27"`, et l'image contenait aussi Maven 3.10.0. Sans tag, `FROM maven` veut dire `FROM maven:latest`, et `latest` suit la dernière version publiée. Vous avez donc compilé avec un Java dix versions plus récent que celui du projet, et la même commande, lancée dans trois mois, produira une autre image. Une construction qui ne donne pas toujours le même résultat n'est pas **reproductible**.

La troisième porte sur la taille. `docker images` liste les images d'un nom donné :

```exec
docker images layers-l10-petclinic
```

L'image pèse près de 800 Mo, alors que le JAR, que vous verrez au chapitre suivant, n'en fait que 66. Elle contient Maven, le JDK complet avec son compilateur, le code source, et toutes les dépendances téléchargées par Maven. Aucun de ces éléments ne sert à faire tourner l'application.

La quatrième porte sur l'arrêt du conteneur. `docker top` liste ses processus :

```exec
docker top layers-l10-petclinic
```

Le premier processus n'est pas `java`, mais `/bin/sh -c java -jar target/*.jar`. Écrite sans crochets, l'instruction `CMD` est en **forme shell** : Docker lance un shell, qui lance Java à son tour. Or c'est le premier processus, le PID 1, qui reçoit le signal d'arrêt `SIGTERM` de `docker stop`, et le shell de cette image ne le transmet pas à Java. Docker attend alors dix secondes, puis tue le conteneur. Mesurez-le :

```exec
time docker stop layers-l10-petclinic
```

Vous lisez un peu plus de dix secondes. L'application n'a pas pu s'arrêter proprement, par exemple pour finir les requêtes en cours ou fermer ses connexions à la base. `docker inspect layers-l10-petclinic --format '{{.State.ExitCode}}'` répond d'ailleurs `137`. Un code au-dessus de 128 veut dire « arrêté par un signal », et 137 = 128 + 9 : le signal 9, `SIGKILL`, celui qui tue sans laisser le temps de finir.

La cinquième observation est un constat qui ne demande pas de commande. Tout le projet est copié avant la compilation, et Docker garde donc en cache une couche qui dépend de **tous** les fichiers. Modifier une seule ligne de code invalide cette couche et toutes les suivantes : Maven retélécharge alors toutes les dépendances, à chaque construction.

Le tableau résume ces défauts, avec le chapitre qui corrige chacun :

| Défaut | Pourquoi c'est un problème | Corrigé dans |
|---|---|---|
| `FROM maven`, sans tag | la construction n'est pas reproductible, et la version de Java ne correspond pas au projet | le JAR compilé par la CI |
| l'application tourne en root | une faille donne tous les droits dans le conteneur | le JAR compilé par la CI |
| près de 800 Mo | des outils de construction inutiles à l'exécution, plus lents à télécharger et autant de logiciels à surveiller | le JAR compilé par la CI, puis l'image distroless |
| `CMD` en forme shell | l'application ne reçoit pas le signal d'arrêt, et Docker la tue au bout de dix secondes | le JAR compilé par la CI |
| aucun `HEALTHCHECK` | Docker sait que le processus tourne, pas que l'application répond | le JAR compilé par la CI |
| `COPY .` avant la compilation | chaque modification retélécharge toutes les dépendances | le multi-stage |

Supprimez ce conteneur, car le chapitre suivant en crée un autre sous le même nom :

```exec
docker rm -f layers-l10-petclinic
```

```ack
J'ai relevé les défauts de l'image naïve
```

## Questions

```quiz
title: "L'image naïve"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que désigne `FROM maven`, sans tag ?"
    answers:
      - "`maven:latest`, la dernière version publiée, qui change avec le temps"
      - "La version de Maven indiquée dans le `pom.xml`"
      - "La première version de l'image `maven`"
    correct: 1
    explanation: "Sans tag, Docker utilise `latest`. Ce tag suit les nouvelles versions : ici, il a apporté Java 27 à un projet qui vise Java 17."
  - prompt: "Pourquoi `docker stop` attend-il dix secondes avec `CMD java -jar target/*.jar` ?"
    answers:
      - "Parce que Java met dix secondes à s'arrêter"
      - "Parce que le PID 1 est un shell, qui ne transmet pas le signal d'arrêt à Java : Docker finit par tuer le conteneur"
      - "Parce que le port 8080 reste ouvert"
    correct: 2
    explanation: "En forme shell, `sh -c` est le PID 1. La forme exec, `[\"java\", \"-jar\", …]`, fait de Java le PID 1, qui reçoit `SIGTERM` et s'arrête proprement."
```
