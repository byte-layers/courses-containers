---
title: "Collecter les journaux avec Loki et Alloy"
description: "Une pile de journaux dans l'infra : Alloy lit les journaux de chaque conteneur, Loki les garde, Grafana les affiche"
---

Tout communique, et tout fonctionne. Mais si PetClinic renvoie une erreur cette nuit, où lirez-vous ce qui s'est passé ? `docker logs` ne montre qu'un conteneur à la fois, sur une seule machine, et les journaux disparaissent avec le conteneur. Dans ce chapitre, vous ajoutez à l'infra une **pile de journaux** : un outil qui les collecte, un autre qui les garde, et un troisième pour les chercher.

PetClinic n'a rien à changer : il écrit déjà ses journaux sur sa sortie standard, comme toute application Spring Boot, et le pilote `json-file` de la partie B les garde sur l'hôte. La pile va les demander au moteur Docker, par la même voie que `docker logs`.

## Les trois outils de la pile

Chaque outil a un rôle, et ils se parlent dans cet ordre :

```
conteneurs ──► journaux json-file ──► Alloy ──► Loki ──► Grafana ──► vous
               (sur l'hôte)           collecte   garde    affiche
                                      et étiquette
```

| Outil | Son rôle |
|---|---|
| [Alloy](https://grafana.com/docs/alloy/latest/) | le **collecteur** : il découvre les conteneurs par le socket Docker, lit leurs journaux, leur ajoute des **labels** (le nom du conteneur, du projet, du service) et les envoie à Loki |
| [Loki](https://grafana.com/docs/loki/latest/) | la **base de journaux** : il garde les lignes, et n'indexe que leurs labels, ce qui le rend léger. On y cherche avec le langage LogQL, par exemple `{compose_service="app"} \|= "ERROR"` |
| [Grafana](https://grafana.com/docs/grafana/latest/) | l'**interface** : on y cherche les journaux, et on y affiche des tableaux de bord |

Alloy remplace Promtail, l'ancien collecteur de Loki, dont la maintenance s'est arrêtée en mars 2026. Vous trouverez encore Promtail dans beaucoup de tutoriels : la logique est la même, mais il ne reçoit plus de correctifs.

⚖️ Alloy monte le socket Docker, comme Traefik, et il a donc lui aussi un accès complet au moteur. C'est le prix de la découverte automatique des conteneurs. Une autre voie existe : le **pilote de journaux Loki**, un plugin de Docker qui envoie les journaux directement à Loki. Il évite le socket, mais il s'installe sur chaque hôte, et il faut changer le pilote de journaux de chaque conteneur.

## Les fichiers de configuration de la pile

La pile vit dans un nouveau dossier de l'infra, `observability/`. Créez-le, avec un sous-dossier par outil :

```exec
mkdir -p ~/layers-l10/prod/infra/observability/{loki,alloy,grafana/provisioning/datasources,secrets}
```

Loki tourne ici en un seul processus, avec ses données sur un disque local, ce qui convient à un poste ou à un petit serveur. Le fichier garde les journaux 48 heures, et le **compacteur** supprime les plus anciens. Vous n'avez pas besoin de comprendre chaque ligne : le schéma de stockage, en particulier, se recopie de la documentation de Loki. Créez-le :

```exec
cat > ~/layers-l10/prod/infra/observability/loki/config.yaml <<'EOF'
# Loki en un seul processus, avec un stockage sur disque : la configuration d'un poste de test
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules

schema_config:
  configs:
    - from: 2026-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 48h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
EOF
```

La configuration d'Alloy est écrite dans son propre langage, l'**Alloy syntax**. Elle enchaîne quatre **composants**, dans l'ordre du schéma : trouver les conteneurs, transformer leurs métadonnées en labels, lire leurs journaux, les envoyer à Loki. Docker fournit les métadonnées sous des noms qui commencent par `__meta_docker_`, et chaque `rule` en recopie une dans un label lisible. Créez-la :

```exec
cat > ~/layers-l10/prod/infra/observability/alloy/config.alloy <<'EOF'
// 1. Trouver les conteneurs, en interrogeant le moteur Docker
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// 2. Transformer les métadonnées de Docker en labels lisibles
discovery.relabel "containers" {
  targets = []

  // le nom du conteneur, sans la barre oblique que Docker ajoute devant
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
  // le même nom, sous le label job qu'attendent beaucoup de dashboards
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "job"
  }
  // le projet et le service Compose
  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_project"]
    target_label  = "compose_project"
  }
  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label  = "compose_service"
  }
  // la sortie : stdout ou stderr
  rule {
    source_labels = ["__meta_docker_container_log_stream"]
    target_label  = "stream"
  }
}

// 3. Lire les journaux de chaque conteneur, et les envoyer à Loki
loki.source.docker "containers" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.containers.targets
  relabel_rules = discovery.relabel.containers.rules
  forward_to    = [loki.write.local.receiver]
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
EOF
```

Un mot sur le vocabulaire : le mot **label** revient ici dans un autre sens. Les labels Docker, ceux de Traefik, sont des étiquettes posées sur un conteneur. Les labels de Loki, comme ceux de Prometheus au chapitre suivant, sont des étiquettes posées sur chaque série de journaux ou de mesures, et c'est sur eux que l'on cherche.

Le label `job` reprend le nom du conteneur, comme `container`. Il n'est pas redondant : beaucoup de tableaux de bord de journaux, dont celui que vous importerez, filtrent sur `job`.

Grafana peut lire sa configuration au démarrage, dans des fichiers de **provisioning**. Celui-ci déclare Loki comme source de données, pour que vous n'ayez rien à cliquer :

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
EOF
```

Le mot de passe de l'administrateur de Grafana est un secret, généré comme celui de la base :

```exec
cd ~/layers-l10/prod/infra/observability && openssl rand -base64 18 | tr -d '\n' > secrets/grafana_admin_password.txt && chmod 700 secrets
```

## Le fichier Compose de la pile

Les trois services reçoivent le durcissement de la partie B, par un bloc `x-hardening` que ce fichier redéfinit, puisque les ancres ne traversent pas les fichiers. Plusieurs points sont propres à cette pile :

| Point | Pourquoi |
|---|---|
| un réseau `monitoring`, interne | Alloy, Loki et Grafana se parlent sur un réseau sans accès à l'extérieur. Loki n'a aucune raison d'être joignable d'ailleurs |
| Grafana sur `monitoring` **et** `proxy` | Traefik le route, sous `/grafana`. Le réseau `proxy` est redéclaré à l'identique, comme dans le fichier de Traefik |
| `GF_SERVER_ROOT_URL` et `GF_SERVER_SERVE_FROM_SUB_PATH` | Grafana sait vivre sous un préfixe, sans `stripprefix` : ces deux variables lui donnent son adresse publique, `http://localhost:28402/grafana/`, et lui font servir ses pages sous `/grafana` |
| `GF_SECURITY_ADMIN_PASSWORD__FILE` | Grafana suit la même convention que PostgreSQL, avec un double soulignement : la variable donne le chemin du fichier qui contient le mot de passe |
| Alloy écrit son état dans `/alloy-data` | son dossier prévu, `/var/lib/alloy`, appartient à l'utilisateur `alloy`. Alloy tourne en root, et root sans capabilities ne peut pas y entrer. Un volume monté ailleurs appartient à root, et lui suffit |

⚖️ Deux réglages de la partie B manquent ici, et c'est un choix. Seul Grafana a un healthcheck, parce que son image contient `wget`, comme celle de Prometheus au chapitre suivant. Les images de Loki et d'Alloy n'ont pas d'outil pour interroger une adresse : c'est le même compromis que l'image distroless de PetClinic, et leur état se lit dans leurs journaux ou dans Grafana. Les services de l'infra n'ont pas non plus de limite `pids`, pour garder les fichiers courts : sur un vrai serveur, on l'ajouterait comme pour PetClinic.

⚠️ **Piège : une limite de mémoire trop basse.** Avec une limite de 128 Mo, Alloy démarre et reste bloqué. Il n'écrit aucun journal, n'ouvre pas son port, et Docker ne le tue pas pour autant : `docker inspect` affiche `OOMKilled: false`. Rien n'arrive dans Loki, sans message d'erreur. Le correctif, mesuré sur ce cas pratique, est une limite de 256 Mo. Une fois démarré, Alloy n'en utilise qu'environ 80 Mo, mais son démarrage en demande davantage. C'est l'illustration de la remarque de la partie B : on fixe une limite après avoir mesuré, avec une marge.

Créez le fichier, puis complétez ses trois blancs dans votre éditeur :

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
      # TODO : le socket Docker, monté en lecture seule
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

  grafana:
    <<: *hardening
    image: grafana/grafana:13.2.5
    environment:
      # TODO : le mot de passe de l'administrateur, lu dans le secret grafana_admin_password
      GF_SERVER_ROOT_URL: http://localhost:28402/grafana/
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"
    secrets:
      - grafana_admin_password
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana_data:/var/lib/grafana
    tmpfs:
      - /tmp
    labels:
      - traefik.enable=true
      # TODO : le router grafana reçoit les adresses qui commencent par /grafana
      - traefik.http.routers.grafana.entrypoints=web
      - traefik.http.services.grafana.loadbalancer.server.port=3000
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    depends_on:
      - loki
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
  grafana_data:
    name: layers-l10-grafana-data

secrets:
  grafana_admin_password:
    file: ./secrets/grafana_admin_password.txt
EOF
```

Ajoutez enfin ce fichier au parent de l'infra. Le fichier parent devient :

```exec
cat > ~/layers-l10/prod/infra/compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
  - observability/compose.yaml
EOF
```

Lancez l'infra. Traefik ne change pas, et Compose ne crée que les trois nouveaux services :

```exec
cd ~/layers-l10/prod/infra && docker compose up -d && docker compose ps
```

> 📖 [Alloy et les journaux Docker](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/) · [La configuration de Loki](https://grafana.com/docs/loki/latest/configure/) · [Grafana derrière un reverse proxy](https://grafana.com/tutorials/run-grafana-behind-a-proxy/) · [Le provisioning de Grafana](https://grafana.com/docs/grafana/latest/administration/provisioning/)

```verify
for S in loki alloy grafana; do
  [ "$(docker inspect layers-l10-infra-$S-1 --format '{{.State.Running}}' 2>/dev/null)" = "true" ] || { echo "Le service $S ne tourne pas. Lancez docker compose up -d depuis ~/layers-l10/prod/infra, puis lisez docker compose logs $S."; exit 1; }
done
docker inspect layers-l10-infra-alloy-1 --format '{{range .Mounts}}{{.Destination}} {{end}}' | grep -q '/var/run/docker.sock' || { echo "Alloy n'a pas le socket Docker : il ne peut pas lire les journaux."; exit 1; }
J=$(docker exec layers-l10-infra-grafana-1 wget -qO- http://loki:3100/loki/api/v1/label/job/values 2>/dev/null)
echo "$J" | grep -q 'layers-l10-petclinic-app-1' || { echo "Loki n'a pas encore de journaux de PetClinic. Attendez trente secondes, puis vérifiez à nouveau. Si rien n'arrive, lisez docker compose logs alloy, et vérifiez sa limite de mémoire."; exit 1; }
C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:28402/grafana/api/health)
[ "$C" = "200" ] || { echo "Grafana ne répond pas sous /grafana (code $C). Traefik ne le route qu'une fois son healthcheck réussi, ce qui prend jusqu'à une minute : vérifiez à nouveau, puis contrôlez sa règle de routage."; exit 1; }
echo "Les journaux de PetClinic arrivent dans Loki, et Grafana répond par Traefik."
```

```hint
Le socket se monte dans `alloy`, sous `volumes:`, avec `- /var/run/docker.sock:/var/run/docker.sock:ro`. Dans `grafana`, la variable s'écrit `GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin_password`.
```

```hint
La règle de Grafana s'écrit `- traefik.http.routers.grafana.rule=PathPrefix(`/grafana`)`, sans middleware : Grafana sert lui-même ses pages sous ce préfixe.
```

````solution
```bash
cd ~/layers-l10/prod/infra
cat > observability/compose.yaml <<'EOF'
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
  grafana_data:
    name: layers-l10-grafana-data

secrets:
  grafana_admin_password:
    file: ./secrets/grafana_admin_password.txt
EOF
cat > compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
  - observability/compose.yaml
EOF
docker compose up -d
```
````

## Chercher dans les journaux

Grafana met jusqu'à une minute à démarrer. Tant que son healthcheck n'a pas réussi, Traefik répond `404 page not found` sur `/grafana/` : il ne route que les conteneurs en bonne santé, et ignore ceux qui sont encore en `health: starting`. Attendez que `docker compose ps` affiche Grafana `(healthy)`. Ouvrez ensuite `http://localhost:28402/grafana/`, et connectez-vous avec l'utilisateur `admin` et le mot de passe que cette commande affiche :

```exec
cat ~/layers-l10/prod/infra/observability/secrets/grafana_admin_password.txt; echo
```

Ouvrez le menu **Explore**, choisissez la source **Loki**, passez l'éditeur en mode **Code**, et lancez ces requêtes LogQL une à une :

| Requête | Ce qu'elle montre |
|---|---|
| `{compose_project="layers-l10-petclinic"}` | tous les journaux du projet PetClinic : l'application, la base et Adminer |
| `{compose_service="app"} \|= "Started"` | les lignes de l'application qui contiennent `Started` : ses démarrages |
| `{container="layers-l10-infra-traefik-1"} \| json` | les requêtes reçues par Traefik, découpées en champs grâce au format JSON : la méthode, l'adresse, le code de retour, la durée |

Le `|=` filtre les lignes qui contiennent un texte, et le `| json` découpe une ligne JSON en champs que l'on peut filtrer à leur tour, par exemple `| DownstreamStatus >= 400` pour ne garder que les erreurs.

> 📖 [Le langage LogQL](https://grafana.com/docs/loki/latest/query/)

```ack
J'ai cherché dans les journaux de PetClinic et de Traefik
```

## Importer un tableau de bord de journaux

Explore sert à enquêter. Pour suivre une application au quotidien, on préfère un **tableau de bord** (*dashboard*), et la communauté en publie des milliers sur [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/), chacun avec un numéro. Vous allez importer le dashboard **13639**, « Logs / App », un tableau de journaux simple et très utilisé :

1. Dans Grafana, ouvrez le menu **Dashboards**, puis **New** et **Import**.
2. Saisissez `13639` dans le champ de l'identifiant, puis cliquez sur **Load**.
3. Choisissez la source **Loki** dans la liste, puis cliquez sur **Import**.
4. En haut du tableau, dans la liste **App**, choisissez `layers-l10-petclinic-app-1`.

Le tableau montre le nombre de lignes de journaux dans le temps, puis les lignes elles-mêmes. Le champ **Search** filtre les lignes par un texte. La liste **App** propose tous les conteneurs, parce qu'elle lit les valeurs du label `job` qu'Alloy pose.

Vous pouvez essayer d'autres tableaux de la bibliothèque. Un tableau importé suppose des labels précis, et beaucoup sont faits pour Kubernetes, avec des labels comme `namespace` ou `pod` : ceux-là resteront vides ici.

```verify
PW=$(cat "$HOME/layers-l10/prod/infra/observability/secrets/grafana_admin_password.txt" 2>/dev/null)
R=$(curl -s --max-time 5 -u "admin:$PW" "http://localhost:28402/grafana/api/search?type=dash-db")
echo "$R" | grep -q '"Logs / App"' || { echo "Grafana n'a pas de dashboard « Logs / App ». Importez le dashboard 13639, avec la source Loki."; exit 1; }
echo "Le dashboard de journaux est importé."
```

````solution
L'import se fait dans l'interface de Grafana, en suivant les quatre étapes de cette section. Si la liste **App** reste vide, Loki n'a pas encore reçu de journaux : revenez à la section précédente, et vérifiez qu'Alloy tourne.
````
