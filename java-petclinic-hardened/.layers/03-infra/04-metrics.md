---
title: "Mesurer avec Prometheus et l'agent JMX exporter"
description: "Des métriques pour Traefik et pour la JVM de PetClinic, sans toucher à son code, puis deux tableaux de bord importés"
---

Les journaux racontent ce qui s'est passé, une ligne à la fois. Ils répondent mal à des questions comme « la mémoire de PetClinic monte-t-elle depuis ce matin ? » ou « combien de requêtes par seconde Traefik reçoit-il ? ». Ce sont des **métriques** : des nombres mesurés à intervalle régulier. Dans ce chapitre, vous ajoutez Prometheus à l'infra, et vous faites publier ses métriques à Traefik et à la JVM de PetClinic.

## Comment Prometheus collecte

Prometheus vient lui-même chercher les métriques : toutes les 15 secondes, il interroge une adresse HTTP de chaque **cible**, le plus souvent `/metrics`, qui répond par une liste de nombres en texte. On dit qu'il les **scrape**. Chaque cible doit donc publier une telle adresse :

| Cible | Comment elle publie ses métriques |
|---|---|
| Traefik | une seule option, `--metrics.prometheus=true`, ajoute `/metrics` sur son port d'administration, le 8080 |
| PetClinic | rien, pour l'instant. Spring Boot sait publier ses métriques avec Actuator, mais il lui faut une bibliothèque de plus dans le `pom.xml`, `micrometer-registry-prometheus`, que PetClinic n'a pas |

## Mesurer une application Java sans toucher à son code

Modifier le `pom.xml` demande de recompiler et de relivrer l'application. C'est souvent impossible avec une application ancienne, ou dont on n'a pas le code. Java offre une autre voie : un **agent**, un JAR que la JVM charge au démarrage avec l'option `-javaagent`, et qui s'exécute à côté de l'application.

L'agent [JMX exporter](https://github.com/prometheus/jmx_exporter) lit les indicateurs que toute JVM publie déjà par **JMX** (*Java Management Extensions*), sous forme d'objets appelés **MBeans** : la mémoire, le ramasse-miettes, les threads, les classes chargées. Spring Boot désactive par défaut les MBeans de son serveur Tomcat : on les activerait avec la propriété `server.tomcat.mbeanregistry.enabled=true`. Il les republie au format de Prometheus, sur un port à lui, ici le 9404. L'application ne voit rien, et fonctionne avec n'importe quelle version de Java depuis la 8.

Trois choix sont à faire dans le fichier de PetClinic :

| Choix | Pourquoi |
|---|---|
| l'agent passe par l'`entrypoint`, et non par `JAVA_TOOL_OPTIONS` (qui garde son réglage de mémoire, puisque l'image le définit par `ENV`) | toute JVM lit `JAVA_TOOL_OPTIONS`, y compris celle du healthcheck, toutes les 20 secondes. Elle chargerait l'agent, qui tenterait d'ouvrir le port 9404, déjà pris par celui de l'application |
| le JAR de l'agent est monté en lecture seule, depuis `./jmx` | l'image ne change pas : on ajoute la mesure à l'exécution, comme le healthcheck |
| un **alias** réseau, `petclinic`, sur le réseau `proxy` | sur ce réseau partagé, le nom de service `app` est trop générique : une autre application pourrait avoir le sien. L'alias donne à Prometheus une adresse unique, `petclinic:9404` |

## Télécharger et vérifier l'agent

L'agent est un JAR publié sur GitHub, avec son **empreinte** `sha256`. Vous le téléchargez, puis vous vérifiez qu'il correspond à cette empreinte, pour être sûr d'exécuter le fichier publié et pas un autre : c'est le même réflexe que le digest des images. `sha256sum -c` recalcule l'empreinte et la compare :

```exec
mkdir -p ~/layers-l10/prod/petclinic/jmx && cd ~/layers-l10/prod/petclinic/jmx
curl -LO https://github.com/prometheus/jmx_exporter/releases/download/1.7.0/jmx_prometheus_javaagent-1.7.0.jar
echo "0ad843261c567d1924a017d542e14c40f2afff523d940c25ee000742fde4b3a9  jmx_prometheus_javaagent-1.7.0.jar" | sha256sum -c
```

La réponse doit être `jmx_prometheus_javaagent-1.7.0.jar: OK`. Ce JAR téléchargé n'a pas sa place dans Git, et il reste hors du contexte de build grâce à la liste blanche du `.dockerignore`. Ajoutez le dossier au `.gitignore` :

```exec
cd ~/layers-l10/prod/petclinic && (grep -qx 'jmx/' .gitignore || echo 'jmx/' >> .gitignore)
```

 L'agent a besoin d'un fichier de règles, qui dit quels indicateurs JMX republier. Celui-ci les republie tous, et l'agent ajoute de lui-même les métriques de base de la JVM :

```exec
cat > ~/layers-l10/prod/petclinic/jmx/config.yaml <<'EOF'
# Republier tous les MBeans de la JVM, en plus des métriques JVM de base
rules:
  - pattern: ".*"
EOF
```

## Brancher l'agent sur PetClinic

Le fichier qui suit reprend celui du chapitre précédent, avec l'agent. L'option `-javaagent` suit la forme `-javaagent:<chemin du JAR>=<port>:<chemin des règles>`, et l'alias se déclare dans la [forme longue des réseaux](https://docs.docker.com/reference/compose-file/services/#aliases) d'un service. Créez le fichier, puis complétez ses deux blancs dans votre éditeur :

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
    # L'agent JMX exporter est ajouté à la ligne de commande, et non à JAVA_TOOL_OPTIONS :
    # la JVM du healthcheck le chargerait aussi, et ouvrirait le même port
    entrypoint:
      - /usr/bin/java
      # TODO : charger l'agent JMX exporter, qui écoute sur le port 9404 et lit /opt/jmx/config.yaml
      - -jar
      - /app/petclinic.jar
    command: ["--spring.config.additional-location=file:/run/secrets/petclinic-db.properties"]
    environment:
      SPRING_PROFILES_ACTIVE: postgres
      POSTGRES_URL: jdbc:postgresql://db:5432/petclinic
      POSTGRES_USER: petclinic
    secrets:
      - source: petclinic_db_properties
        target: petclinic-db.properties
    volumes:
      - ./jmx:/opt/jmx:ro
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
      backend:
      proxy:
        # TODO : l'alias petclinic sur ce réseau

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
```

Appliquez le fichier :

```exec
cd ~/layers-l10/prod/petclinic && docker compose --profile dev up -d
```

```verify
P="$HOME/layers-l10/prod/petclinic"
echo "0ad843261c567d1924a017d542e14c40f2afff523d940c25ee000742fde4b3a9  $P/jmx/jmx_prometheus_javaagent-1.7.0.jar" | sha256sum -c --status 2>/dev/null || { echo "Le JAR de l'agent manque dans $P/jmx, ou son empreinte ne correspond pas. Téléchargez-le à nouveau."; exit 1; }
docker inspect layers-l10-petclinic-app-1 --format '{{json .Config.Entrypoint}}' | grep -q 'javaagent:/opt/jmx/jmx_prometheus_javaagent-1.7.0.jar=9404:/opt/jmx/config.yaml' || { echo "L'entrypoint de app ne charge pas l'agent : vérifiez la ligne -javaagent."; exit 1; }
docker inspect layers-l10-petclinic-app-1 --format '{{json .NetworkSettings.Networks}}' | grep -q '"petclinic"' || { echo "app n'a pas l'alias petclinic sur le réseau proxy."; exit 1; }
H=$(docker inspect layers-l10-petclinic-app-1 --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')
[ "$H" = "healthy" ] || { echo "app n'est pas encore en bonne santé (état : $H). Attendez une minute, puis vérifiez à nouveau."; exit 1; }
echo "PetClinic tourne avec l'agent JMX exporter."
```

```hint
Dans l'`entrypoint`, la deuxième ligne s'écrit `- -javaagent:/opt/jmx/jmx_prometheus_javaagent-1.7.0.jar=9404:/opt/jmx/config.yaml`.
```

```hint
L'alias se déclare dans la forme longue des réseaux de `app` : sous `proxy:`, écrivez `aliases:`, puis `- petclinic`, chacun décalé de deux espaces de plus.
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
    # L'agent JMX exporter est ajouté à la ligne de commande, et non à JAVA_TOOL_OPTIONS :
    # la JVM du healthcheck le chargerait aussi, et ouvrirait le même port
    entrypoint:
      - /usr/bin/java
      - -javaagent:/opt/jmx/jmx_prometheus_javaagent-1.7.0.jar=9404:/opt/jmx/config.yaml
      - -jar
      - /app/petclinic.jar
    command: ["--spring.config.additional-location=file:/run/secrets/petclinic-db.properties"]
    environment:
      SPRING_PROFILES_ACTIVE: postgres
      POSTGRES_URL: jdbc:postgresql://db:5432/petclinic
      POSTGRES_USER: petclinic
    secrets:
      - source: petclinic_db_properties
        target: petclinic-db.properties
    volumes:
      - ./jmx:/opt/jmx:ro
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
      backend:
      proxy:
        aliases:
          - petclinic

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
```
````

## Ajouter Prometheus à l'infra

Prometheus rejoint deux réseaux : `monitoring`, pour que Grafana le lise, et `proxy`, pour joindre ses deux cibles, Traefik et PetClinic. Il garde ses mesures deux jours dans un volume, et il n'a aucun port publié : vous le lirez par Grafana. Sa configuration liste les cibles à interroger. Créez-la, en complétant son blanc :

```exec
mkdir -p ~/layers-l10/prod/infra/observability/prometheus
cat > ~/layers-l10/prod/infra/observability/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  # Traefik publie ses métriques sur son port d'administration
  - job_name: traefik
    static_configs:
      - targets: ["traefik:8080"]

  # PetClinic, par l'agent JMX exporter
  - job_name: petclinic
    static_configs:
      - labels:
          # un label de plus, qu'attend le dashboard JVM importé dans Grafana
          application: petclinic
        # TODO : la clé targets, avec l'adresse de PetClinic (son alias) et le port de l'agent
EOF
```

Le label `application` n'est pas nécessaire à Prometheus. Il est attendu par le tableau de bord JVM que vous importerez, qui range les applications par ce label.

Le fichier de la pile gagne le service `prometheus` et son volume, et Grafana attend aussi Prometheus pour démarrer. Il remplace le précédent :

```exec
cat > ~/layers-l10/prod/infra/observability/compose.yaml <<'EOF'
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

x-hardening: &hardening
  read_only: true
  cap_drop: [ALL]
  security_opt: ["no-new-privileges:true"]
  restart: unless-stopped
  logging: *default-logging

services:
  loki:
    <<: *hardening
    image: grafana/loki:3.7.9
    command: ["-config.file=/etc/loki/config.yaml"]
    volumes:
      - ./loki/config.yaml:/etc/loki/config.yaml:ro
      - loki_data:/loki
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - monitoring

  alloy:
    <<: *hardening
    image: grafana/alloy:v1.21.3
    command: ["run", "--storage.path=/alloy-data", "/etc/alloy/config.alloy"]
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - alloy_data:/alloy-data
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 256M
    depends_on:
      - loki
    networks:
      - monitoring

  prometheus:
    <<: *hardening
    image: prom/prometheus:v3.16.0
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=2d
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
      interval: 15s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - monitoring
      - proxy

  grafana:
    <<: *hardening
    image: grafana/grafana:13.2.5
    environment:
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin_password
      GF_SERVER_ROOT_URL: http://localhost:28402/grafana/
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"
    secrets:
      - grafana_admin_password
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana_data:/var/lib/grafana
    tmpfs:
      - /tmp
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/grafana/api/health"]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 60s
      start_interval: 3s
    labels:
      - traefik.enable=true
      - traefik.http.routers.grafana.rule=PathPrefix(`/grafana`)
      - traefik.http.routers.grafana.entrypoints=web
      - traefik.http.services.grafana.loadbalancer.server.port=3000
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    depends_on:
      - loki
      - prometheus
    networks:
      - monitoring
      - proxy

networks:
  monitoring:
    name: layers-l10-monitoring
    internal: true
  proxy:
    name: layers-l10-proxy

volumes:
  loki_data:
    name: layers-l10-loki-data
  alloy_data:
    name: layers-l10-alloy-data
  prometheus_data:
    name: layers-l10-prometheus-data
  grafana_data:
    name: layers-l10-grafana-data

secrets:
  grafana_admin_password:
    file: ./secrets/grafana_admin_password.txt
EOF
```

Déclarez Prometheus comme seconde source de données de Grafana. Loki reste la source par défaut :

```exec
cat > ~/layers-l10/prod/infra/observability/grafana/provisioning/datasources/datasources.yaml <<'EOF'
# Les sources de données, déclarées au démarrage de Grafana : rien à cliquer
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    uid: loki
    url: http://loki:3100
    access: proxy
    isDefault: true
  - name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://prometheus:9090
    access: proxy
EOF
```

Ouvrez enfin `~/layers-l10/prod/infra/traefik/compose.yaml`, et ajoutez la ligne `- --metrics.prometheus=true` à la fin de la liste `command:`, après `- --accesslog.format=json`, avec la même indentation.

Appliquez l'infra. Compose recrée Traefik, dont la ligne de commande a changé, et crée Prometheus. Grafana ne relit ses sources de données qu'au démarrage : redémarrez-le. Pendant son redémarrage, `/grafana/` répond `404` le temps que son healthcheck réussisse.

```exec
cd ~/layers-l10/prod/infra && docker compose up -d && docker compose restart grafana
```

Contrôlez les cibles de Prometheus. Il n'a pas de port publié, et `docker exec` lance donc la requête depuis son conteneur, avec `wget`. `grep` extrait l'état de chaque cible :

```exec
docker exec layers-l10-infra-prometheus-1 wget -qO- http://localhost:9090/api/v1/targets | grep -o '"job":"[a-z]*"\|"health":"[a-z]*"'
```

Vous devez lire les deux cibles, `traefik` et `petclinic`, chacune avec `"health":"up"`. Si vous corrigez `prometheus.yml` après ce démarrage, redémarrez Prometheus avec `docker compose restart prometheus` : `up -d` ne recrée pas un conteneur quand seul un fichier monté a changé, et Prometheus ne relit sa configuration qu'au démarrage.

> 📖 [La configuration de Prometheus](https://prometheus.io/docs/prometheus/latest/configuration/configuration/) · [Les métriques de Traefik](https://doc.traefik.io/traefik/reference/install-configuration/observability/metrics/) · [JMX exporter](https://prometheus.github.io/jmx_exporter/)

```verify
T=$(docker exec layers-l10-infra-prometheus-1 wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null)
[ -n "$T" ] || { echo "Prometheus ne répond pas. Lancez docker compose up -d depuis ~/layers-l10/prod/infra, puis lisez docker compose logs prometheus."; exit 1; }
for J in traefik petclinic; do
  echo "$T" | tr '{' '\n' | grep "\"job\":\"$J\"" >/dev/null || { echo "Prometheus n'a pas de cible $J : vérifiez prometheus.yml."; exit 1; }
  Q=$(docker exec layers-l10-infra-prometheus-1 wget -qO- "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22$J%22%7D" 2>/dev/null)
  echo "$Q" | grep -q '"1"\]' || { echo "La cible $J n'est pas joignable par Prometheus. Pour traefik, vérifiez --metrics.prometheus=true. Pour petclinic, vérifiez l'agent et l'alias."; exit 1; }
done
Q=$(docker exec layers-l10-infra-prometheus-1 wget -qO- 'http://localhost:9090/api/v1/query?query=jvm_memory_used_bytes%7Bapplication%3D%22petclinic%22%7D' 2>/dev/null)
echo "$Q" | grep -q '"area":"heap"' || { echo "Prometheus n'a pas encore la mémoire de la JVM, avec le label application. Attendez quinze secondes, puis vérifiez à nouveau."; exit 1; }
echo "Prometheus mesure Traefik et la JVM de PetClinic."
```

```hint
La cible s'écrit `targets: ["petclinic:9404"]`, l'alias réseau et le port de l'agent, à la même indentation que `labels:`, comme pour la cible de Traefik.
```

````solution
```bash
cd ~/layers-l10/prod/infra
cat > observability/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  # Traefik publie ses métriques sur son port d'administration
  - job_name: traefik
    static_configs:
      - targets: ["traefik:8080"]

  # PetClinic, par l'agent JMX exporter
  - job_name: petclinic
    static_configs:
      - targets: ["petclinic:9404"]
        # un label de plus, qu'attend le dashboard JVM importé dans Grafana
        labels:
          application: petclinic
EOF
cat > traefik/compose.yaml <<'EOF'
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  traefik:
    image: traefik:v3.7.17
    command:
      - --entrypoints.web.address=:80
      - --api.dashboard=true
      - --api.insecure=true
      - --ping=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=layers-l10-proxy
      - --accesslog=true
      - --accesslog.format=json
      - --metrics.prometheus=true
    ports:
      - "127.0.0.1:28402:80"
      - "127.0.0.1:28403:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    read_only: true
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 10s
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 128M
    logging: *default-logging
    networks:
      - proxy

networks:
  proxy:
    name: layers-l10-proxy
EOF
docker compose up -d && docker compose restart prometheus grafana
```
````

## Importer deux tableaux de bord de métriques

Il faut du trafic pour que les courbes bougent. Cette boucle envoie 600 requêtes à PetClinic, par Traefik, sur deux pages :

```exec
for i in $(seq 1 300); do curl -s -o /dev/null http://localhost:28402/owners/find; curl -s -o /dev/null http://localhost:28402/vets.html; done; echo "Terminé."
```

Importez ensuite deux tableaux, comme celui des journaux, par **Dashboards**, **New** puis **Import** :

| Numéro | Titre | La source à choisir | Ce qu'il montre |
|---|---|---|---|
| `19799` | JVM Overview | Prometheus, dans la liste **datasource** en haut du tableau. Saisissez ensuite `petclinic` dans le champ **job**, le nom de la cible dans Prometheus : la liste **application**, qui lit le label `application`, se remplit alors | la mémoire de la JVM par zone, le ramasse-miettes, les threads, les classes chargées |
| `17346` | Traefik Official Standalone Dashboard | Prometheus, au moment de l'import | les requêtes par point d'entrée et par service, leurs codes de retour et leurs durées |

Dans le tableau JVM, quelques panneaux restent vides, ceux de la section sur le système d'exploitation par exemple. Ils attendent des métriques que l'auteur du tableau produisait avec ses propres règles, comme `os_free_physical_memory_bytes`. Un tableau importé est un point de départ, que l'on adapte : c'est une bonne raison d'ouvrir un panneau en mode édition pour lire sa requête.

Dans le tableau de Traefik, le service `petclinic@docker` montre les requêtes de la boucle. Relancez-la pour voir la courbe monter.

```verify
PW=$(cat "$HOME/layers-l10/prod/infra/observability/secrets/grafana_admin_password.txt" 2>/dev/null)
R=$(curl -s --max-time 5 -u "admin:$PW" "http://localhost:28402/grafana/api/search?type=dash-db")
echo "$R" | grep -q '"JVM Overview"' || { echo "Grafana n'a pas de dashboard « JVM Overview ». Importez le dashboard 19799."; exit 1; }
echo "$R" | grep -q '"Traefik Official Standalone Dashboard"' || { echo "Grafana n'a pas de dashboard « Traefik Official Standalone Dashboard ». Importez le dashboard 17346, avec la source Prometheus."; exit 1; }
echo "Les deux tableaux de métriques sont importés."
```

````solution
L'import se fait dans l'interface de Grafana, en suivant le tableau de cette section. Si un tableau reste vide, vérifiez d'abord la source de données choisie en haut du tableau, puis relancez la boucle de requêtes : Prometheus a besoin de deux mesures au moins pour calculer un débit.
````
