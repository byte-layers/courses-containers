---
title: "Ajouter Adminer avec un profil de développement"
description: "Un service qui ne démarre qu'avec le profil dev, pour administrer la base sans l'exposer partout"
---

En développement, on aime voir le contenu de la base. En production, une interface d'administration ouverte est une porte de plus. Dans ce chapitre, vous ajoutez **Adminer**, une interface web pour les bases de données en une seule image, et vous le réservez au développement avec un **profil**.

## Ce qu'est un profil Compose

Un service qui porte la clé `profiles` ne démarre pas avec un simple `docker compose up`. Il ne démarre que si l'un de ses profils est activé, avec l'option `--profile`. Les services sans profil, eux, démarrent toujours :

| Commande | Ce qui démarre |
|---|---|
| `docker compose up -d` | `app` et `db`, les services sans profil |
| `docker compose --profile dev up -d` | `app`, `db` et `adminer` |

Le même fichier Compose sert donc partout. Sur un poste de développement, on active le profil `dev`, et sur un serveur de production, on ne l'active pas. Il n'y a pas de second fichier à maintenir, ni d'oubli possible d'un service de développement dans la configuration de production.

> 📖 [Les profils Compose](https://docs.docker.com/compose/how-tos/profiles/) · [L'image Adminer](https://hub.docker.com/_/adminer)

## Ajouter le service Adminer

Adminer reçoit le même durcissement que les autres services, par la fusion du bloc `x-hardening`. Il est écrit en PHP, et son serveur web intégré range ses sessions dans `/tmp`, qui a donc besoin d'un `tmpfs`. Il rejoint `backend` pour joindre la base, et `frontend` pour publier son port, le 28401. `ADMINER_DEFAULT_SERVER` préremplit le nom du serveur dans le formulaire de connexion.

Son healthcheck n'a pas `curl`, absent de l'image. Il utilise donc PHP, déjà présent : `file_get_contents` télécharge la page d'accueil, et le programme sort avec le code `1` si elle ne répond pas. C'est l'idée du healthcheck écrit en Java de la partie A : on teste avec ce que l'image contient.

Ouvrez `~/byte-layers/docker/l10/prod/petclinic/compose.yaml` et ajoutez ce service à la fin de la section `services:`, juste avant `networks:`, en complétant ses deux blancs :

```yaml
  adminer:
    <<: *hardening
    image: adminer:5.5.1
    # TODO : le profil dev
    environment:
      ADMINER_DEFAULT_SERVER: db
    healthcheck:
      test: ["CMD", "php", "-r", "exit(@file_get_contents('http://localhost:8080/') === false ? 1 : 0);"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    tmpfs:
      - /tmp
    ports:
      - "127.0.0.1:28401:8080"
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 64M
    depends_on:
      db:
        condition: service_healthy
    # TODO : les deux réseaux, backend et frontend
```

Lancez d'abord le projet sans profil, et constatez qu'Adminer ne démarre pas :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose up -d && docker compose ps --format '{{.Service}}'
```

La liste ne contient que `app` et `db`. Activez maintenant le profil :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose --profile dev up -d && docker compose --profile dev ps
```

Une dizaine de secondes plus tard, Adminer est `(healthy)`. Ouvrez `http://localhost:28401` dans votre navigateur, et connectez-vous avec ces réglages :

| Champ | Valeur |
|---|---|
| Système | PostgreSQL |
| Serveur | `db`, déjà rempli |
| Utilisateur | `petclinic` |
| Mot de passe | le contenu de `secrets/db_password.txt`, que `cat ~/byte-layers/docker/l10/prod/petclinic/secrets/db_password.txt` affiche |
| Base de données | `petclinic` |

Vous voyez les tables de PetClinic : `owners`, `pets`, `vets`, `visits`. Ouvrez `owners` pour retrouver les propriétaires, et celui que vous avez peut-être ajouté.

⚠️ Une interface comme Adminer ne doit jamais être ouverte à tous sur un serveur. Le profil la réserve au développement, et le port publié sur `127.0.0.1` la limite à la machine. Si on en a besoin sur un serveur, on la place derrière le reverse proxy, avec une authentification devant elle : la partie C la branche sur Traefik, et y revient.

```verify
P="$HOME/byte-layers/docker/l10/prod/petclinic"
(cd "$P" && docker compose config --services 2>/dev/null) | grep -qx adminer && { echo "adminer démarre sans profil : il manque profiles: [dev]."; exit 1; }
(cd "$P" && docker compose --profile dev config --services 2>/dev/null) | grep -qx adminer || { echo "Le service adminer n'existe pas dans le fichier Compose, même avec le profil dev."; exit 1; }
C=layers-l10-petclinic-adminer-1
H=$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
[ "$H" = "healthy" ] || { echo "Adminer n'est pas en bonne santé (état : ${H:-absent}). Lancez docker compose --profile dev up -d, puis attendez quelques secondes."; exit 1; }
case "$(docker inspect $C --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
  *layers-l10-petclinic-backend*layers-l10-petclinic-frontend*|*layers-l10-petclinic-frontend*layers-l10-petclinic-backend*) : ;;
  *) echo "Adminer doit être sur les deux réseaux, backend et frontend."; exit 1 ;;
esac
curl -s --max-time 5 http://localhost:28401/ | grep -q 'Adminer' || { echo "http://localhost:28401 ne répond pas la page d'Adminer."; exit 1; }
echo "Adminer tourne avec le profil dev, et seulement avec lui."
```

```hint
Le profil s'écrit `profiles: [dev]`, sous `image:`. Les réseaux s'écrivent comme ceux de `app` : `networks:`, puis `- backend` et `- frontend`.
```

````solution
Cette commande écrit le fichier complet de cette partie, le même que [`solution/05-compose/compose.yaml`](../../solution/05-compose/compose.yaml), puis lance le projet avec le profil `dev`.

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

  adminer:
    <<: *hardening
    image: adminer:5.5.1
    profiles: [dev]
    environment:
      ADMINER_DEFAULT_SERVER: db
    healthcheck:
      test: ["CMD", "php", "-r", "exit(@file_get_contents('http://localhost:8080/') === false ? 1 : 0);"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    tmpfs:
      - /tmp
    ports:
      - "127.0.0.1:28401:8080"
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 64M
    depends_on:
      db:
        condition: service_healthy
    networks:
      - backend
      - frontend

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
docker compose --profile dev up -d
```
````
## Récap de la partie B

- Un secret est un fichier monté dans `/run/secrets/`. PostgreSQL le lit par la convention `_FILE`, et Spring Boot par un fichier de configuration chargé avec `--spring.config.additional-location`. Le mot de passe n'apparaît alors dans aucune variable d'environnement.
- Des réseaux et un volume nommés explicitement restent stables et lisibles. Un réseau `internal: true` isole la base, et un second réseau permet à l'application de publier son port.
- Un healthcheck sur la base et un `depends_on` avec `service_healthy` et `restart: true` garantissent l'ordre de démarrage, au premier lancement comme à chaque redémarrage.
- Les ancres YAML et les extensions `x-` écrivent une fois les journaux et le durcissement, et chaque service en hérite par un alias ou une fusion.
- Un profil réserve un service, comme Adminer, au développement, dans le même fichier Compose.
