---
title: "Décrire PetClinic et sa base dans un fichier Compose"
description: "Deux services, deux réseaux nommés dont un interne, un volume, des secrets et un démarrage dans le bon ordre"
---

Les secrets sont prêts. Dans ce chapitre, vous écrivez le fichier Compose qui lance PetClinic avec PostgreSQL. Vous partez d'un fichier dont la structure est donnée, et vous complétez ce qui fait sa solidité : le démarrage dans le bon ordre, le mot de passe lu dans un secret, le healthcheck de la base et l'isolement de son réseau.

## Comment PetClinic trouve sa base

PetClinic contient déjà une configuration pour PostgreSQL. Elle vit dans le fichier `src/main/resources/application-postgres.properties`, et Spring Boot ne la charge que si le **profil** `postgres` est actif. Voici ses trois lignes de connexion :

```
spring.datasource.url=${POSTGRES_URL:jdbc:postgresql://localhost/petclinic}
spring.datasource.username=${POSTGRES_USER:petclinic}
spring.datasource.password=${POSTGRES_PASS:petclinic}
```

La syntaxe `${VARIABLE:défaut}` lit une variable d'environnement, avec une valeur par défaut si elle est absente. Vous donnerez donc quatre réglages à l'application :

| Réglage | Valeur | Comment |
|---|---|---|
| le profil | `postgres` | la variable `SPRING_PROFILES_ACTIVE`, que Spring Boot lit au démarrage |
| l'adresse de la base | `jdbc:postgresql://db:5432/petclinic` | la variable `POSTGRES_URL`. `db` est le nom du service, qui sert d'adresse sur le réseau |
| l'utilisateur | `petclinic` | la variable `POSTGRES_USER`, qui n'a rien de secret |
| le mot de passe | celui de `secrets/db_password.txt` | **pas** `POSTGRES_PASS` : le fichier `petclinic-db.properties` du secret définit `spring.datasource.password` et remplace la valeur par défaut |

Le fichier chargé par `--spring.config.additional-location` l'emporte sur la configuration embarquée dans le JAR, profil compris : c'est l'ordre de priorité de Spring Boot pour les fichiers externes.

## Les choix du fichier Compose

Le fichier que vous allez compléter encode plusieurs choix. Chacun a sa raison :

| Choix | Pourquoi |
|---|---|
| des réseaux et un volume avec une clé `name:` explicite | Compose préfixe sinon chaque nom par celui du projet. Un nom fixe se lit dans `docker network ls`, et il ne change pas si le projet est renommé. La partie C s'en servira pour brancher l'infra |
| un réseau `backend` **interne** (`internal: true`) | la base n'a aucune raison de joindre Internet, ni d'être jointe depuis l'extérieur. Sur un réseau interne, Docker ne crée aucune route vers l'extérieur |
| un second réseau, `frontend`, pour l'application | un conteneur qui n'est que sur un réseau interne ne peut pas publier de port. PetClinic rejoint donc aussi `frontend`, et la base, elle, reste seule sur `backend` |
| la forme longue du secret de PetClinic, avec `target:` | Spring Boot reconnaît le format d'un fichier de configuration à son extension. Le fichier monté doit donc s'appeler `petclinic-db.properties` dans `/run/secrets/` |
| le volume monté sur `/var/lib/postgresql` | depuis la version 18, l'image PostgreSQL range ses données dans un sous-dossier de version, `/var/lib/postgresql/18/docker`. Monter le dossier parent facilite les montées de version |
| `image: layers-l10-petclinic:1.0.0` à côté de `build: .` | Compose construit l'image depuis le `Dockerfile`, et lui donne un nom et une version lisibles |

Deux réglages, enfin, font démarrer les services dans le bon ordre. Le **healthcheck** de la base utilise `pg_isready`, l'outil de PostgreSQL qui répond dès que le serveur accepte des connexions. Le `depends_on` de l'application, dans sa forme longue, attend cette bonne santé :

```yaml
    depends_on:
      db:
        condition: service_healthy   # attendre que le healthcheck de db réussisse
        restart: true                # redémarrer l'application quand Compose redémarre db
```

## Écrire le fichier Compose

Créez le fichier de départ, puis complétez ses quatre blancs dans votre éditeur :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/compose.yaml <<'EOF'
name: layers-l10-petclinic

services:
  app:
    build: .
    image: layers-l10-petclinic:1.0.0
    command: ["--spring.config.additional-location=file:/run/secrets/petclinic-db.properties"]
    environment:
      SPRING_PROFILES_ACTIVE: postgres
      POSTGRES_URL: jdbc:postgresql://db:5432/petclinic
      POSTGRES_USER: petclinic
    secrets:
      - source: petclinic_db_properties
        target: petclinic-db.properties
    ports:
      - "127.0.0.1:28400:8080"
    # TODO : attendre que db soit en bonne santé, et redémarrer avec elle (le depends_on ci-dessus)
    networks:
      - backend
      - frontend

  db:
    image: postgres:18.6-alpine3.24
    environment:
      POSTGRES_DB: petclinic
      POSTGRES_USER: petclinic
      # TODO : POSTGRES_PASSWORD_FILE, le chemin du secret db_password dans le conteneur
    secrets:
      - db_password
    volumes:
      - db_data:/var/lib/postgresql
    # TODO : un healthcheck qui lance pg_isready -U petclinic -d petclinic, toutes les 10 secondes
    networks:
      - backend

networks:
  backend:
    name: layers-l10-petclinic-backend
    # TODO : un réseau interne
  frontend:
    name: layers-l10-petclinic-frontend

volumes:
  db_data:
    name: layers-l10-petclinic-db-data

secrets:
  db_password:
    file: ./secrets/db_password.txt
  petclinic_db_properties:
    file: ./secrets/petclinic-db.properties
EOF
```

La commande `command:` ne remplace pas le lancement de Java. Dans une image qui a un `ENTRYPOINT`, la `command` de Compose est ajoutée **à la suite** de celui-ci : le conteneur lance donc `/usr/bin/java -jar /app/petclinic.jar --spring.config.additional-location=…`, et Spring Boot lit tout argument qui commence par `--` comme une propriété.

Le service `db` reçoit son secret par la forme courte, `- db_password`. Compose le monte alors dans `/run/secrets/`, sous le nom du secret.

`docker compose config` lit le fichier, le complète et l'affiche, ou signale l'erreur. `-q` n'affiche rien si tout va bien. Lancez-le avant de démarrer quoi que ce soit, car c'est le contrôle le plus rapide :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose config -q && echo "Le fichier est valide."
```

Démarrez ensuite le projet. Compose construit l'image, que le cache de la partie A rend rapide, puis attend que la base soit prête avant de lancer l'application :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose up -d --build
```

> 📖 [`depends_on`](https://docs.docker.com/reference/compose-file/services/#depends_on) · [`healthcheck`](https://docs.docker.com/reference/compose-file/services/#healthcheck) · [Les réseaux internes](https://docs.docker.com/reference/compose-file/networks/#internal) · [`secrets` dans un service](https://docs.docker.com/reference/compose-file/services/#secrets)

```verify
P="$HOME/byte-layers/docker/l10/prod/petclinic"
CFG=$(cd "$P" && docker compose config 2>&1) || { echo "Le fichier Compose n'est pas valide : $(echo "$CFG" | tail -1)"; exit 1; }
echo "$CFG" | grep -q 'condition: service_healthy' || { echo "app n'attend pas db : il manque le depends_on avec condition: service_healthy."; exit 1; }
echo "$CFG" | grep -q 'POSTGRES_PASSWORD_FILE: /run/secrets/db_password' || { echo "db ne lit pas son mot de passe dans le secret : il manque POSTGRES_PASSWORD_FILE: /run/secrets/db_password."; exit 1; }
[ "$(docker network inspect layers-l10-petclinic-backend --format '{{.Internal}}' 2>/dev/null)" = "true" ] || { echo "Le réseau layers-l10-petclinic-backend n'existe pas, ou n'est pas interne (internal: true)."; exit 1; }
H=$(docker inspect layers-l10-petclinic-db-1 --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
[ "$H" = "healthy" ] || { echo "db n'est pas en bonne santé (état : ${H:-aucun healthcheck}). Lisez docker compose logs db."; exit 1; }
H=$(docker inspect layers-l10-petclinic-app-1 --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
[ "$H" = "healthy" ] || { echo "app n'est pas encore en bonne santé (état : ${H:-absent}). Attendez une minute, ou lisez docker compose logs app."; exit 1; }
echo "PetClinic et sa base tournent, et la base attend sur son réseau interne."
```

```hint
Le `depends_on` se place sous `app:`, à la même indentation que `ports:`. Copiez le bloc donné plus haut, avec `condition: service_healthy` et `restart: true`.
```

```hint
Sous `environment:` de `db`, ajoutez `POSTGRES_PASSWORD_FILE: /run/secrets/db_password`. Le healthcheck s'écrit comme celui de MySQL dans le cas pratique sur Traefik, avec `test: ["CMD", "pg_isready", "-U", "petclinic", "-d", "petclinic"]`, `interval: 10s`, `timeout: 3s`, `retries: 5` et `start_period: 30s`. Le réseau interne s'écrit `internal: true`, sous `name:`.
```

````solution
```bash
cd ~/byte-layers/docker/l10/prod/petclinic
cat > compose.yaml <<'EOF'
name: layers-l10-petclinic

services:
  app:
    build: .
    image: layers-l10-petclinic:1.0.0
    command: ["--spring.config.additional-location=file:/run/secrets/petclinic-db.properties"]
    environment:
      SPRING_PROFILES_ACTIVE: postgres
      POSTGRES_URL: jdbc:postgresql://db:5432/petclinic
      POSTGRES_USER: petclinic
    secrets:
      - source: petclinic_db_properties
        target: petclinic-db.properties
    ports:
      - "127.0.0.1:28400:8080"
    depends_on:
      db:
        condition: service_healthy
        restart: true
    networks:
      - backend
      - frontend

  db:
    image: postgres:18.6-alpine3.24
    environment:
      POSTGRES_DB: petclinic
      POSTGRES_USER: petclinic
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - db_data:/var/lib/postgresql
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "petclinic", "-d", "petclinic"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s
    networks:
      - backend

networks:
  backend:
    name: layers-l10-petclinic-backend
    internal: true
  frontend:
    name: layers-l10-petclinic-frontend

volumes:
  db_data:
    name: layers-l10-petclinic-db-data

secrets:
  db_password:
    file: ./secrets/db_password.txt
  petclinic_db_properties:
    file: ./secrets/petclinic-db.properties
EOF
docker compose up -d --build
```
````

## Contrôler que PetClinic utilise PostgreSQL

`docker compose ps` affiche l'état des deux services. Relancez-le jusqu'à lire `(healthy)` pour les deux, ce qui prend une à deux minutes la première fois :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose ps
```

Les journaux de l'application confirment le profil et la base. `grep` ne garde que les lignes qui en parlent :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose logs app | grep -E 'profile is active|Database driver|Database version'
```

Vous devez lire le profil `postgres`, le pilote `PostgreSQL JDBC Driver` et la version 18.6 de la base. PetClinic a aussi créé ses tables et chargé ses données de démonstration au démarrage. `psql`, le client de PostgreSQL, les compte depuis le conteneur de la base :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose exec db psql -U petclinic -d petclinic -c 'select count(*) from owners'
```

La réponse est `10`, les dix propriétaires de démonstration. Ajoutez-en un depuis le navigateur, avec **Find owners** puis **Add Owner** sur `http://localhost:28400` : contrairement à H2, il survivra à un redémarrage, parce que ses données vivent dans le volume.

Vérifiez enfin que le mot de passe n'apparaît nulle part dans la configuration des conteneurs. `docker inspect` affiche leurs variables d'environnement, et `grep -c` compte les lignes qui contiennent le mot de passe :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1; do docker inspect $C --format '{{json .Config.Env}}' | grep -c "$(cat secrets/db_password.txt)"; done
```

Les deux comptes sont `0`. Le mot de passe n'existe que dans les fichiers de `/run/secrets/`, et la variable `POSTGRES_PASSWORD_FILE` ne contient que son chemin.

```verify
P="$HOME/byte-layers/docker/l10/prod/petclinic"
N=$(cd "$P" && docker compose exec -T db psql -U petclinic -d petclinic -tAc 'select count(*) from owners' 2>/dev/null)
[ -n "$N" ] && [ "$N" -ge 10 ] || { echo "La table owners n'est pas lisible dans PostgreSQL : PetClinic ne s'est pas connecté à sa base. Lisez docker compose logs app."; exit 1; }
docker logs layers-l10-petclinic-app-1 2>&1 | grep -q 'profile is active: "postgres"' || { echo "Le profil postgres n'est pas actif : vérifiez SPRING_PROFILES_ACTIVE."; exit 1; }
PW=$(cat "$P/secrets/db_password.txt")
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1; do
  if docker inspect $C --format '{{json .Config.Env}}' | grep -qF "$PW"; then echo "Le mot de passe apparaît dans l'environnement de $C."; exit 1; fi
done
echo "PetClinic lit sa base PostgreSQL, et le mot de passe n'est dans aucune variable."
```

````solution
Ce contrôle ne demande rien de nouveau. Si la table `owners` n'est pas lisible, l'application ne s'est pas connectée : `docker compose logs app` en donne la raison. Une erreur `password authentication failed` signale que les deux fichiers de secrets ne contiennent pas le même mot de passe, et la section sur les secrets les régénère. Après une régénération, repartez d'une base vide, car PostgreSQL ne lit son mot de passe qu'à sa première initialisation :

```bash
cd ~/byte-layers/docker/l10/prod/petclinic
docker compose down -v
docker compose up -d
```
````

⚠️ **Piège, si vous changez le mot de passe.** Le symptôme est `password authentication failed for user "petclinic"` dans les journaux de l'application. La cause est que l'image PostgreSQL ne lit `POSTGRES_PASSWORD_FILE` qu'au tout premier démarrage, quand le volume est vide : ensuite, le mot de passe vit dans la base. Le correctif, en développement, est `docker compose down -v`, qui supprime le volume et donc les données. En production, on change le mot de passe dans la base avec `ALTER USER`, puis dans le secret.
