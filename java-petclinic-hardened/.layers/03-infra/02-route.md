---
title: "Brancher PetClinic et Adminer sur Traefik"
description: "Le réseau partagé déclaré external, des labels de routage, et plus aucun port publié par les applications"
---

Traefik attend des applications. Dans ce chapitre, vous branchez PetClinic et Adminer sur le réseau de l'infra, vous leur donnez leurs routes par des labels, et vous retirez leurs ports : à la fin, Traefik est la seule porte d'entrée.

## Ce qui change dans le fichier de PetClinic

Le fichier Compose de PetClinic change sur quatre points, et le reste ne bouge pas :

| Changement | Pourquoi |
|---|---|
| le réseau `frontend` disparaît, remplacé par `proxy`, déclaré `name: layers-l10-proxy` et `external: true` | les applications rejoignent le réseau de l'infra sans le posséder |
| `app` et `adminer` perdent leur clé `ports` | seul le reverse proxy publie un port : c'est le seul endroit à surveiller et à protéger |
| `app` et `adminer` reçoivent des labels | ce sont les règles de routage que Traefik lit dans Docker |
| `db` ne change pas | la base reste seule sur `backend`, hors de portée de Traefik |

## Les routes, et pourquoi PetClinic reçoit la racine

Les labels de routage sont ceux du cas pratique sur Traefik. Voici ceux de PetClinic :

| Label | Rôle |
|---|---|
| `traefik.enable=true` | demande à Traefik de router ce conteneur, puisque `exposedbydefault` est à `false` |
| `traefik.http.routers.petclinic.rule=PathPrefix(`/`)` | le router `petclinic` reçoit toutes les adresses |
| `traefik.http.routers.petclinic.entrypoints=web` | sur le point d'entrée `web` |
| `traefik.http.services.petclinic.loadbalancer.server.port=8080` | le port de l'application dans le conteneur |

PetClinic reçoit la racine, `/`, et non un préfixe comme `/petclinic`. Ses pages contiennent en effet des liens absolus, comme `/owners/find` ou `/resources/css/petclinic.css`. Derrière un préfixe retiré par un middleware, le navigateur demanderait ces adresses à la racine, où elles n'existent pas, et les pages s'afficheraient sans style ni navigation.

Une route sur `/` capte-t-elle alors tout, Adminer et Grafana compris ? Non, car Traefik départage les routes par leur **priorité**, qui vaut par défaut la longueur de la règle. `PathPrefix(`/adminer`)` est plus longue que `PathPrefix(`/`)`, donc prioritaire : la racine ne reçoit que ce qu'aucune autre route ne prend.

Adminer, lui, sait vivre sous un préfixe, avec le middleware `stripprefix` déjà vu : Traefik reçoit `/adminer/…`, retire `/adminer`, et Adminer reçoit `/…`. Ses labels sont donnés tels quels.

> 📖 [Les règles et la priorité des routers](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/rules-and-priority/) · [Le middleware `stripprefix`](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/stripprefix/) · [Les réseaux externes](https://docs.docker.com/reference/compose-file/networks/#external)

## Modifier le fichier de PetClinic

Le fichier qui suit remplace celui de la partie B. Créez-le, puis complétez ses trois blancs dans votre éditeur :

```exec
cat > ~/layers-l10/prod/petclinic/compose.yaml <<'EOF'
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
    labels:
      - traefik.enable=true
      # TODO : le router petclinic reçoit toutes les adresses, à partir de la racine
      - traefik.http.routers.petclinic.entrypoints=web
      # TODO : le port de l'application dans le conteneur
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
      - proxy

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
    labels:
      - traefik.enable=true
      - traefik.http.routers.adminer.rule=PathPrefix(`/adminer`)
      - traefik.http.routers.adminer.entrypoints=web
      - traefik.http.routers.adminer.middlewares=adminer-strip
      - traefik.http.middlewares.adminer-strip.stripprefix.prefixes=/adminer
      - traefik.http.services.adminer.loadbalancer.server.port=8080
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
      - proxy

networks:
  backend:
    name: layers-l10-petclinic-backend
    internal: true
  # TODO : le réseau proxy, nommé layers-l10-proxy, qui appartient à l'infra

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

Appliquez-le avec le profil `dev`, pour qu'Adminer suive. Compose recrée `app` et `adminer`, qui changent de réseau et de ports :

```exec
cd ~/layers-l10/prod/petclinic && docker compose --profile dev up -d
```

Compose ne supprime pas tout seul un réseau qui a disparu du fichier. Supprimez l'ancien réseau `frontend`, que plus aucun conteneur n'utilise :

```exec
docker network rm layers-l10-petclinic-frontend
```

```verify
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-adminer-1; do
  [ "$(docker inspect $C --format '{{.State.Running}}' 2>/dev/null)" = "true" ] || { echo "$C ne tourne pas. Lancez docker compose --profile dev up -d depuis ~/layers-l10/prod/petclinic."; exit 1; }
  [ -z "$(docker port $C)" ] || { echo "$C publie encore un port : retirez sa clé ports, seul Traefik publie."; exit 1; }
  docker inspect $C --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}' | grep -q 'layers-l10-proxy' || { echo "$C n'est pas sur le réseau layers-l10-proxy."; exit 1; }
done
docker inspect layers-l10-petclinic-db-1 --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}' | grep -q 'layers-l10-proxy' && { echo "La base ne doit pas être sur le réseau du proxy."; exit 1; }
R=$(curl -s --max-time 5 http://localhost:28403/api/http/routers)
echo "$R" | grep -q '"petclinic@docker"' || { echo "Traefik ne connaît pas de router petclinic : vérifiez les labels de app."; exit 1; }
echo "$R" | grep -q '"adminer@docker"' || { echo "Traefik ne connaît pas de router adminer : Adminer tourne-t-il, avec le profil dev ?"; exit 1; }
echo "Les deux applications sont branchées sur Traefik, sans port publié."
```

```hint
Les deux labels manquants de `app` s'écrivent `- traefik.http.routers.petclinic.rule=PathPrefix(`/`)` et `- traefik.http.services.petclinic.loadbalancer.server.port=8080`.
```

```hint
Tout en bas, le réseau s'écrit `proxy:`, puis, décalés de deux espaces, `name: layers-l10-proxy` et `external: true`.
```

````solution
```bash
cd ~/layers-l10/prod/petclinic
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
    labels:
      - traefik.enable=true
      - traefik.http.routers.petclinic.rule=PathPrefix(`/`)
      - traefik.http.routers.petclinic.entrypoints=web
      - traefik.http.services.petclinic.loadbalancer.server.port=8080
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
      - proxy

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
    labels:
      - traefik.enable=true
      - traefik.http.routers.adminer.rule=PathPrefix(`/adminer`)
      - traefik.http.routers.adminer.entrypoints=web
      - traefik.http.routers.adminer.middlewares=adminer-strip
      - traefik.http.middlewares.adminer-strip.stripprefix.prefixes=/adminer
      - traefik.http.services.adminer.loadbalancer.server.port=8080
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
      - proxy

networks:
  backend:
    name: layers-l10-petclinic-backend
    internal: true
  proxy:
    name: layers-l10-proxy
    external: true

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
docker network rm layers-l10-petclinic-frontend 2>/dev/null
```
````

## Ouvrir PetClinic et Adminer par Traefik

Interrogez maintenant PetClinic par Traefik, sur le port 28402. `grep` extrait le titre de la page d'accueil :

```exec
curl -s http://localhost:28402/ | grep '<h2>'
```

Vous devez lire le titre de la page d'accueil, `<h2>Welcome</h2>`.

Ouvrez ensuite `http://localhost:28402/` dans votre navigateur. La page s'affiche avec son style, et les liens comme **Find owners** fonctionnent : tous passent par la route de la racine. Ouvrez aussi `http://localhost:28402/adminer/`, avec la barre oblique finale, et connectez-vous comme au chapitre sur Adminer.

L'ancien port, lui, ne répond plus, puisque l'application ne le publie plus :

```exec
curl -s -o /dev/null -w '%{http_code}\n' --max-time 3 http://localhost:28400/
```

La réponse est `000` : aucune connexion possible.

⚠️ Adminer est maintenant joignable par Traefik, sans autre protection que son propre formulaire de connexion. C'est acceptable sur un poste, avec le profil `dev`. Sur un serveur, on ajoute une authentification devant lui, par exemple le middleware [`basicauth`](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/basicauth/) de Traefik, avec un fichier de mots de passe chiffrés monté en secret, ou mieux, on le réserve à un réseau d'administration. Dans le tableau de bord de Traefik, `http://localhost:28403/dashboard/`, la page **HTTP Routers** montre maintenant `petclinic@docker` et `adminer@docker`, avec leurs règles.

```verify
curl -s --max-time 5 http://localhost:28402/ | grep -q 'PetClinic' || { echo "http://localhost:28402/ ne répond pas la page de PetClinic."; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:28402/resources/css/petclinic.css)" = "200" ] || { echo "La feuille de style de PetClinic ne passe pas par Traefik."; exit 1; }
curl -s --max-time 5 http://localhost:28402/adminer/ | grep -q 'Adminer' || { echo "http://localhost:28402/adminer/ ne répond pas la page d'Adminer : vérifiez son middleware stripprefix."; exit 1; }
echo "Tout passe par Traefik, sur un seul port."
```

````solution
Ce contrôle ne demande rien de nouveau. Si la racine ne répond pas, vérifiez les labels de `app` dans le tableau de bord de Traefik, page **HTTP Routers**. Une route en erreur y est marquée en rouge, avec la raison. Relancez ensuite le projet :

```bash
cd ~/layers-l10/prod/petclinic && docker compose --profile dev up -d
```
````
