---
title: "Installer Traefik dans le dossier infra"
description: "Un fichier parent qui assemble l'infra avec include, Traefik durci, et le réseau partagé que l'infra crée pour les applications"
---

Vous avez déjà placé deux applications derrière Traefik dans le cas pratique « Deux applications derrière nginx, puis Traefik ». Dans ce chapitre, vous l'installez cette fois comme une pièce de l'infra d'un serveur : dans son propre dossier, assemblé par un fichier parent, durci comme le reste, et propriétaire du réseau que les applications rejoindront.

## Un dossier infra, assemblé par un fichier parent

Sur un serveur, chaque application a son dossier et son fichier Compose, et l'infra a le sien. Dans ce dossier, il vaut mieux un fichier par fonction qu'un seul gros fichier : chacun reste court, se lit seul, et se remplace sans toucher aux autres. Un fichier **parent** les assemble avec la clé `include` :

```yaml
name: layers-l10-infra
include:
  - traefik/compose.yaml          # chaque fichier inclus garde son dossier pour ses chemins relatifs
  - observability/compose.yaml    # ajouté au chapitre sur les journaux
```

| Ce que fait `include` | Ce que cela change pour vous |
|---|---|
| charge chaque fichier comme un projet Compose complet, puis fusionne le tout en un seul projet, `layers-l10-infra` | une seule commande, `docker compose up -d` depuis `infra/`, lance toute l'infra |
| résout les chemins relatifs d'un fichier inclus depuis **son** dossier | `./loki/config.yaml`, écrit dans `observability/compose.yaml`, désigne bien `observability/loki/config.yaml` |
| refuse deux ressources de même nom qui diffèrent, mais accepte une redéclaration identique | chaque fichier garde des noms de services uniques, et peut redéclarer à l'identique un réseau partagé |

⚖️ Un fichier inclus doit pouvoir se lire seul. S'il utilise un réseau défini dans un autre fichier, il le redéclare à l'identique, avec le même `name:`. Compose fusionne alors les deux déclarations en un seul réseau. Les ancres YAML, elles, ne traversent pas les fichiers : chaque fichier a son propre bloc `x-logging`.

> 📖 [`include` dans Compose](https://docs.docker.com/compose/how-tos/multiple-compose-files/include/) · [La référence de `include`](https://docs.docker.com/reference/compose-file/include/)

## Le réseau partagé appartient à l'infra

Traefik doit joindre les applications, et il le fait par un réseau commun, `layers-l10-proxy`. C'est l'infra qui le crée, parce qu'elle vit plus longtemps que chaque application. Les applications, elles, le déclareront `external: true` : elles l'utilisent sans le posséder, et `docker compose down` dans le dossier d'une application ne tentera pas de le supprimer.

## Traefik et le socket Docker

Traefik découvre les applications en lisant le moteur Docker : la liste des conteneurs, leurs réseaux et leurs **labels**, les étiquettes qui portent leurs règles de routage. Il le fait par le **socket Docker**, `/var/run/docker.sock`, le fichier par lequel la CLI `docker` elle-même parle au moteur.

⚠️ Ce socket est un accès complet au moteur Docker. Le suffixe `:ro` du montage empêche seulement de modifier le fichier, pas d'appeler l'API : un programme qui lit le socket peut lister, créer ou supprimer des conteneurs, et donc prendre la main sur l'hôte. Ne le montez que dans des conteneurs de confiance, à jour, et durcis. Pour aller plus loin, un **proxy de socket** comme [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) ne laisse passer que les appels en lecture dont Traefik a besoin.

## Les réglages de Traefik

Traefik se configure ici par les options de sa ligne de commande, sa **configuration statique**. Le tableau les présente dans l'ordre du fichier :

| Option | Rôle |
|---|---|
| `--entrypoints.web.address=:80` | crée le **point d'entrée** `web`, sur le port 80 du conteneur, publié sur le port 28402 de la machine |
| `--api.dashboard=true` et `--api.insecure=true` | ouvre le tableau de bord sur le port 8080 du conteneur, sans protection, publié sur le port 28403 et sur `127.0.0.1` seulement |
| `--ping=true` | ajoute l'adresse `/ping`, que le healthcheck `traefik healthcheck --ping` interroge |
| `--providers.docker=true` | lit les conteneurs dans le moteur Docker |
| `--providers.docker.exposedbydefault=false` | n'expose que les conteneurs qui portent le label `traefik.enable=true`. Sans cette option, tout conteneur du moteur deviendrait joignable |
| `--providers.docker.network=layers-l10-proxy` | joint les applications par ce réseau, même quand elles sont sur plusieurs réseaux |
| `--accesslog=true` et `--accesslog.format=json` | écrit une ligne par requête, en JSON : la pile de journaux saura la découper |

Le durcissement suit celui de la partie B, `cap_drop: [ALL]` compris. Traefik ouvre pourtant le port 80, alors que la capability `NET_BIND_SERVICE` sert justement à ouvrir un port inférieur à 1024. Depuis sa version 20.10, Docker règle en effet chaque conteneur pour que tout port y soit ouvrable sans capability (le réglage du noyau `net.ipv4.ip_unprivileged_port_start` vaut `0`). Sur un moteur qui ne le ferait pas, il faudrait rendre ce seul pouvoir avec `cap_add: [NET_BIND_SERVICE]`.

## Écrire et lancer l'infra

Créez d'abord le dossier de l'infra et son fichier parent. Pour l'instant, il n'inclut que Traefik :

```exec
mkdir -p ~/byte-layers/docker/l10/prod/infra/traefik
cat > ~/byte-layers/docker/l10/prod/infra/compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
EOF
```

Créez ensuite le fichier de Traefik, puis complétez ses deux blancs dans votre éditeur :

```exec
cat > ~/byte-layers/docker/l10/prod/infra/traefik/compose.yaml <<'EOF'
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
      # TODO : ne router que les conteneurs qui portent le label traefik.enable=true
      - --providers.docker.network=layers-l10-proxy
      - --accesslog=true
      - --accesslog.format=json
    ports:
      - "127.0.0.1:28402:80"
      - "127.0.0.1:28403:8080"
    volumes:
      # TODO : le socket Docker, monté en lecture seule
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
```

Lancez l'infra depuis son dossier. Compose crée le réseau `layers-l10-proxy`, puis démarre Traefik :

```exec
cd ~/byte-layers/docker/l10/prod/infra && docker compose up -d && docker compose ps
```

Ouvrez le tableau de bord de Traefik, `http://localhost:28403/dashboard/`, avec la barre oblique finale. La page **HTTP Routers** ne montre encore que les routes internes de Traefik : aucune application ne porte de label. L'entrée elle-même répond `404 page not found`, et c'est normal :

```exec
curl -i http://localhost:28402/
```

> 📖 [Traefik et Docker](https://doc.traefik.io/traefik/reference/install-configuration/providers/docker/) · [Les points d'entrée](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/) · [Le healthcheck de Traefik](https://doc.traefik.io/traefik/reference/install-configuration/observability/healthcheck/)

```verify
C=layers-l10-infra-traefik-1
H=$(docker inspect $C --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
[ "$H" = "healthy" ] || { echo "Traefik n'est pas en bonne santé (état : ${H:-absent}). Lancez docker compose up -d depuis ~/byte-layers/docker/l10/prod/infra, puis lisez docker compose logs traefik."; exit 1; }
docker network inspect layers-l10-proxy >/dev/null 2>&1 || { echo "Le réseau layers-l10-proxy n'existe pas."; exit 1; }
docker inspect $C --format '{{json .Config.Cmd}}' | grep -q 'exposedbydefault=false' || { echo "Traefik expose tous les conteneurs : il manque --providers.docker.exposedbydefault=false."; exit 1; }
docker inspect $C --format '{{range .Mounts}}{{.Destination}}:{{.RW}} {{end}}' | grep -q '/var/run/docker.sock:false' || { echo "Le socket Docker n'est pas monté, ou pas en lecture seule (:ro)."; exit 1; }
docker inspect $C --format '{{.HostConfig.CapDrop}}' | grep -qi 'all' || { echo "Traefik garde ses capabilities : il manque cap_drop: [ALL]."; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:28403/api/overview)" = "200" ] || { echo "Le tableau de bord ne répond pas sur le port 28403."; exit 1; }
echo "Traefik tourne dans l'infra, durci, et le réseau partagé existe."
```

```hint
Le socket se monte sous `volumes:`, avec la ligne `- /var/run/docker.sock:/var/run/docker.sock:ro`.
```

```hint
L'option manquante de la ligne de commande s'écrit `- --providers.docker.exposedbydefault=false`, après `--providers.docker=true`.
```

````solution
```bash
mkdir -p ~/byte-layers/docker/l10/prod/infra/traefik
cd ~/byte-layers/docker/l10/prod/infra
cat > compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
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
docker compose up -d
```
````
