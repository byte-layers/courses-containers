---
title: "Durcir les services et mettre en commun les réglages"
description: "Des ancres YAML x-logging et x-hardening, un système de fichiers en lecture seule, aucune capability, des limites de ressources et un healthcheck décidé à l'exécution"
---

Votre projet fonctionne. Dans ce chapitre, vous le durcissez comme vous avez durci l'image. Plusieurs réglages sont identiques d'un service à l'autre : vous allez les écrire une seule fois, avec des **ancres YAML**, et chaque service en héritera.

## Écrire un réglage une fois, avec les ancres YAML

YAML sait nommer un bloc pour le réutiliser ailleurs dans le même fichier. Trois signes suffisent :

| Signe | Nom | Rôle |
|---|---|---|
| `&nom` | une **ancre** | nomme le bloc qui suit |
| `*nom` | un **alias** | recopie le bloc nommé à cet endroit |
| `<<: *nom` | une **fusion** (*merge key*) | recopie les clés du bloc nommé **dans** le bloc courant, qui peut en ajouter d'autres |

Compose ajoute une convention : toute clé de premier niveau qui commence par `x-` est une **extension**, que Compose ignore. C'est l'endroit prévu pour ranger les blocs à réutiliser. Voici les deux blocs de ce chapitre, et la façon dont un service les utilise :

```yaml
x-logging: &default-logging          # l'ancre default-logging nomme ce bloc
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

x-hardening: &hardening
  read_only: true
  restart: unless-stopped
  logging: *default-logging          # un alias : le bloc des journaux, recopié ici

services:
  db:
    <<: *hardening                   # une fusion : toutes les clés de x-hardening
    image: postgres:18.6-alpine3.24  # ... et celles propres au service
```

`docker compose config` affiche le fichier une fois les ancres résolues : c'est le moyen de vérifier ce que chaque service reçoit vraiment.

Les journaux méritent ce réglage commun. Avec le pilote `json-file`, le pilote par défaut de Docker, chaque conteneur écrit ses journaux dans un fichier sur l'hôte, **sans limite de taille** par défaut. Une application bavarde finit par remplir le disque. `max-size: "10m"` et `max-file: "3"` gardent au plus trois fichiers de 10 Mo par conteneur, et suppriment les plus anciens. Garder `json-file` a aussi un avantage pour la partie C : `docker logs` continue de fonctionner, et c'est par la même voie que la pile de journaux les lira.

⚖️ Une ancre ne traverse pas les fichiers. Elle n'existe que dans le fichier YAML qui la définit : la partie C, qui découpe l'infra en plusieurs fichiers, répétera son bloc `x-logging` dans chacun.

> 📖 [Les fragments YAML dans Compose](https://docs.docker.com/reference/compose-file/fragments/) · [Les extensions `x-`](https://docs.docker.com/reference/compose-file/extension/) · [Le pilote `json-file`](https://docs.docker.com/engine/logging/drivers/json-file/)

## Les réglages de durcissement

Le bloc `x-hardening` regroupe ce que tous les services reçoivent, et `tmpfs`, propre à chaque service, le complète. Chacun corrige un risque précis :

| Réglage | Ce qu'il fait | Le risque qu'il réduit |
|---|---|---|
| `read_only: true` | le système de fichiers du conteneur devient en lecture seule | un attaquant ne peut ni modifier l'application ni déposer un outil |
| `tmpfs:` | monte un dossier en mémoire, accessible en écriture, dans un conteneur en lecture seule | rien : il rend `read_only` possible pour les programmes qui écrivent des fichiers temporaires, comme Tomcat dans `/tmp` |
| `cap_drop: [ALL]` | retire toutes les **capabilities**, ces fragments des pouvoirs de root que Linux accorde un par un (changer le propriétaire d'un fichier, contourner les droits d'accès, changer d'utilisateur…) | un processus compromis, même root, ne peut presque rien faire sur le système |
| `security_opt: ["no-new-privileges:true"]` | interdit à un processus de gagner des droits en cours de route, par exemple avec un programme `setuid` | une élévation de privilèges à l'intérieur du conteneur |
| `restart: unless-stopped` | redémarre le conteneur s'il s'arrête, sauf si vous l'avez arrêté vous-même | une panne qui laisserait le service arrêté jusqu'à une intervention |

Deux services demandent un réglage de plus. PostgreSQL écrit son socket local dans `/var/run/postgresql`, qui a donc besoin d'un `tmpfs` en plus de `/tmp`. Et son script de démarrage commence en root, pour corriger les droits du volume avant de passer à l'utilisateur `postgres` : sans capabilities, il échouerait. `user: postgres` le lance directement avec cet utilisateur, qui possède déjà le volume, et le script n'a plus besoin de pouvoirs.

## Limiter les ressources

Sans limite, un conteneur peut prendre toute la mémoire ou tout le processeur de l'hôte, et faire tomber les autres. La clé `deploy.resources` fixe deux sortes de bornes :

| Clé | Rôle |
|---|---|
| `limits.cpus` | la part de processeur au plus : `"1.0"` vaut un cœur |
| `limits.memory` | la mémoire au plus. Au-delà, le noyau tue le processus (*OOM kill*) |
| `limits.pids` | le nombre de processus et de threads au plus, ce qui arrête une boucle qui en créerait sans fin |
| `reservations.memory` | une limite souple : quand la mémoire de l'hôte vient à manquer, Docker ramène d'abord le conteneur vers cette valeur. Sous Swarm, elle sert aussi à choisir le nœud qui a assez de mémoire libre |

Les limites de PetClinic tiennent compte de Java. Avec `-XX:MaxRAMPercentage=75`, réglé dans l'image, la JVM prend 75 % de la limite pour ses objets : 576 Mo sur 768. Le reste sert à la JVM elle-même et au healthcheck.

⚖️ Une limite trop basse est aussi un risque. Un service qui manque de mémoire peut être tué en boucle, ou rester bloqué au démarrage sans rien dire. Mesurez la consommation réelle avec `docker stats`, puis fixez la limite avec une marge.

> 📖 [`deploy.resources`](https://docs.docker.com/reference/compose-file/deploy/#resources) · [`read_only`, `tmpfs`, `cap_drop`](https://docs.docker.com/reference/compose-file/services/) · [Les capabilities Linux](https://man7.org/linux/man-pages/man7/capabilities.7.html)

## Décider du healthcheck à l'exécution

Au chapitre sur le JAR de la CI, vous aviez noté que c'est à celui qui exécute le conteneur de décider du healthcheck. C'est le moment de le faire. L'image propose un test toutes les 30 secondes. Ici, PetClinic démarre plus lentement, avec un seul cœur, et l'équipe veut être alertée plus vite. Le fichier Compose garde la même commande, mais change le rythme :

| Réglage | Dans l'image | Dans Compose | Pourquoi |
|---|---|---|---|
| `interval` | 30 s | 20 s | détecter une panne plus tôt |
| `start_period` | 60 s | 90 s | un cœur au plus : le démarrage prend près d'une minute |
| `start_interval` | 5 s, la valeur par défaut | 3 s | annoncer l'application prête au plus tôt |

## Écrire le fichier durci

Le fichier qui suit reprend celui du chapitre précédent, avec les deux blocs communs et le durcissement. Il remplace l'ancien. Créez-le, puis complétez ses blancs dans votre éditeur :

```exec
cat > ~/byte-layers/docker/l10/prod/petclinic/compose.yaml <<'EOF'
name: layers-l10-petclinic

# Les journaux : un seul réglage, réutilisé par tous les services
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

# Le durcissement commun : fusionné dans chaque service avec <<
x-hardening: &hardening
  read_only: true
  # TODO : retirer toutes les capabilities
  security_opt: ["no-new-privileges:true"]
  restart: unless-stopped
  logging: *default-logging

services:
  app:
    <<: *hardening
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
    tmpfs:
      - /tmp
    ports:
      - "127.0.0.1:28400:8080"
    healthcheck:
      test: ["CMD", "/usr/bin/java", "-Xmx16m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-cp", "/app/hc", "HealthCheck"]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 90s
      start_interval: 3s
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 768M
          pids: 200
        reservations:
          memory: 512M
    depends_on:
      db:
        condition: service_healthy
        restart: true
    networks:
      - backend
      - frontend

  db:
    # TODO : fusionner le bloc x-hardening
    image: postgres:18.6-alpine3.24
    user: postgres
    environment:
      POSTGRES_DB: petclinic
      POSTGRES_USER: petclinic
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - db_data:/var/lib/postgresql
    # TODO : deux dossiers en mémoire, /tmp et /var/run/postgresql
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "petclinic", "-d", "petclinic"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s
      start_interval: 2s
    # TODO : au plus un demi-cœur, 256 Mo de mémoire et 100 processus
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
```

Vérifiez d'abord ce que chaque service reçoit vraiment, une fois les ancres résolues. `docker compose config` affiche le fichier complet, et `grep` en extrait les lignes du durcissement :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose config | grep -E '^  [a-z]+:$|read_only|cap_drop|no-new-privileges|max-size'
```

Chaque service, `app` comme `db`, doit afficher `read_only: true`, `cap_drop`, `no-new-privileges:true` et `max-size: 10m`. Les lignes `backend:` et `frontend:` viennent de la section des réseaux, que le filtre attrape aussi. Appliquez ensuite le fichier. `up -d` recrée les conteneurs dont la configuration a changé, et les données restent dans le volume :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose up -d
```

```verify
P="$HOME/byte-layers/docker/l10/prod/petclinic"
(cd "$P" && docker compose config -q 2>/dev/null) || { echo "Le fichier Compose n'est pas valide : lancez docker compose config pour lire l'erreur."; exit 1; }
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1; do
  [ "$(docker inspect $C --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null)" = "true" ] || { echo "$C n'a pas de système de fichiers en lecture seule : le bloc x-hardening lui manque-t-il ?"; exit 1; }
  docker inspect $C --format '{{.HostConfig.CapDrop}}' | grep -qi 'all' || { echo "$C garde ses capabilities : il manque cap_drop: [ALL] dans x-hardening."; exit 1; }
  [ "$(docker inspect $C --format '{{.HostConfig.LogConfig.Config}}' | grep -c 'max-size:10m')" = "1" ] || { echo "$C n'a pas la limite de journaux de x-logging."; exit 1; }
done
[ "$(docker inspect layers-l10-petclinic-db-1 --format '{{.HostConfig.Memory}}')" = "268435456" ] || { echo "db n'a pas la limite de 256 Mo de mémoire (memory: 256M sous deploy.resources.limits)."; exit 1; }
[ "$(docker inspect layers-l10-petclinic-db-1 --format '{{.HostConfig.PidsLimit}}')" = "100" ] || { echo "db n'a pas la limite de 100 processus (pids: 100)."; exit 1; }
for C in layers-l10-petclinic-db-1 layers-l10-petclinic-app-1; do
  H=$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')
  [ "$H" = "healthy" ] || { echo "$C n'est pas en bonne santé (état : $H). Attendez une minute, ou lisez ses journaux avec docker compose logs."; exit 1; }
done
echo "Les deux services sont durcis, limités, et en bonne santé."
```

```hint
Dans `x-hardening`, ajoutez `cap_drop: [ALL]`. Dans `db`, la première ligne devient `<<: *hardening`, à la même indentation que `image:`.
```

```hint
Les dossiers en mémoire s'écrivent `tmpfs:`, puis `- /tmp` et `- /var/run/postgresql`. Les limites suivent la forme de celles de `app` : `deploy:`, `resources:`, `limits:`, puis `cpus: "0.5"`, `memory: 256M` et `pids: 100`.
```

````solution
Cette commande écrit le fichier complet, sans le service `adminer`, que le chapitre suivant ajoute, puis l'applique. Le même fichier, avec Adminer, est [`solution/05-compose/compose.yaml`](../../solution/05-compose/compose.yaml).

```bash
cd ~/byte-layers/docker/l10/prod/petclinic
cat > compose.yaml <<'EOF'
name: layers-l10-petclinic

# Les journaux : un seul réglage, réutilisé par tous les services
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

# Le durcissement commun : fusionné dans chaque service avec <<
x-hardening: &hardening
  read_only: true
  cap_drop: [ALL]
  security_opt: ["no-new-privileges:true"]
  restart: unless-stopped
  logging: *default-logging

services:
  app:
    <<: *hardening
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
    tmpfs:
      - /tmp
    ports:
      - "127.0.0.1:28400:8080"
    healthcheck:
      test: ["CMD", "/usr/bin/java", "-Xmx16m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-cp", "/app/hc", "HealthCheck"]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 90s
      start_interval: 3s
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 768M
          pids: 200
        reservations:
          memory: 512M
    depends_on:
      db:
        condition: service_healthy
        restart: true
    networks:
      - backend
      - frontend

  db:
    <<: *hardening
    image: postgres:18.6-alpine3.24
    user: postgres
    environment:
      POSTGRES_DB: petclinic
      POSTGRES_USER: petclinic
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - db_data:/var/lib/postgresql
    tmpfs:
      - /tmp
      - /var/run/postgresql
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "petclinic", "-d", "petclinic"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s
      start_interval: 2s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
          pids: 100
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
docker compose up -d
```
````
## Observer les limites et le redémarrage en cascade

`docker stats` affiche la consommation de chaque conteneur, face à sa limite. `--no-stream` donne une seule mesure, au lieu d'un affichage continu :

```exec
docker stats --no-stream layers-l10-petclinic-app-1 layers-l10-petclinic-db-1
```

La colonne `MEM USAGE / LIMIT` montre par exemple `366MiB / 768MiB` pour PetClinic et `100MiB / 256MiB` pour la base, et la colonne `PIDS` le nombre de processus et de threads.

Redémarrez maintenant la base, comme le ferait une mise à jour. Grâce à `restart: true` dans le `depends_on`, Compose redémarre aussi l'application, une fois la base de nouveau prête :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose restart db && docker compose ps
```

La colonne `STATUS` montre l'application qui redémarre, en `health: starting`, quelques secondes après la base. L'ordre de démarrage est ainsi respecté à chaque redémarrage, et pas seulement au premier `up`.

```ack
J'ai observé les limites et le redémarrage en cascade
```
