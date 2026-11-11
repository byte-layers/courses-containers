---
title: "Finir avec une vue d'ensemble dans Portainer"
description: "Un troisième fichier dans l'infra, sous un profil dev : une interface sur tout ce qui tourne"
---

Vous avez monté, fichier par fichier, une application durcie, sa base, un reverse proxy, des journaux et des métriques. Pour finir, vous ajoutez une interface qui montre tout cela d'un coup d'œil : [Portainer](https://www.portainer.io/), une interface web pour Docker. Elle rejoint l'infra comme un troisième fichier inclus, et sous un profil `dev`, comme Adminer.

## Ce que Portainer apporte, et ce qu'il coûte

Portainer liste les conteneurs, les images, les réseaux et les volumes du moteur Docker, avec leurs journaux, leurs statistiques et un terminal. Il sait aussi lancer des projets Compose, qu'il appelle des *stacks*. C'est pratique pour voir un serveur sans ligne de commande, ou pour le confier à quelqu'un qui ne la connaît pas.

Deux points sont à connaître avant de l'installer :

| Point | Ce qu'il implique |
|---|---|
| Portainer monte le socket Docker, et il s'en sert pour **agir** : arrêter, supprimer, lancer | quiconque a un compte Portainer a la main sur le moteur, et donc sur l'hôte. Le profil `dev` le réserve au développement, et un vrai serveur le protégerait par un réseau d'administration et une authentification forte |
| L'édition **Community** (CE) est gratuite et open source. L'édition **Business** (BE) ajoute des fonctions, comme la gestion fine des droits, sous licence payante : vérifiez ses conditions actuelles avant de la choisir | ce cas pratique utilise l'édition CE |

## Le fichier de Portainer

Le fichier suit le modèle des deux autres : son propre bloc `x-logging`, le réseau `proxy` redéclaré à l'identique, et des labels pour Traefik. Trois réglages lui sont propres :

| Réglage | Rôle |
|---|---|
| `profiles: [dev]` | Portainer ne démarre qu'avec `docker compose --profile dev up -d`, comme Adminer |
| `-H unix:///var/run/docker.sock` | dit à Portainer de gérer le moteur local par le socket. Il crée alors seul son environnement `primary`, sans assistant |
| `--admin-password-file` | lit le mot de passe de l'administrateur dans un fichier, le secret `portainer_admin_password`. Sans lui, Portainer demande de créer le compte au premier accès, et le premier venu le crée |

Comme Adminer, Portainer vit sous un préfixe, `/portainer`, retiré par un middleware `stripprefix`. Son interface charge ses fichiers par des chemins relatifs : ouvrez donc toujours l'adresse avec sa barre oblique finale, `/portainer/`.

Créez le dossier, le secret de l'administrateur, puis le fichier, en complétant son blanc dans votre éditeur :

```exec
mkdir -p ~/byte-layers/docker/l10/prod/infra/portainer/secrets && cd ~/byte-layers/docker/l10/prod/infra/portainer
openssl rand -base64 18 | tr -d '\n' > secrets/portainer_admin_password.txt && chmod 700 secrets
cat > compose.yaml <<'EOF'
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  portainer:
    image: portainer/portainer-ce:2.45.3
    # Seulement avec le profil dev : une interface d'administration n'a pas sa place partout
    profiles: [dev]
    command:
      - -H
      - unix:///var/run/docker.sock
      # TODO : lire le mot de passe de l'administrateur dans le fichier /run/secrets/portainer_admin_password
    secrets:
      - portainer_admin_password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    read_only: true
    tmpfs:
      - /tmp
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=PathPrefix(`/portainer`)
      - traefik.http.routers.portainer.entrypoints=web
      - traefik.http.routers.portainer.middlewares=portainer-strip
      - traefik.http.middlewares.portainer-strip.stripprefix.prefixes=/portainer
      - traefik.http.services.portainer.loadbalancer.server.port=9000
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    logging: *default-logging
    networks:
      - proxy

networks:
  proxy:
    name: layers-l10-proxy

volumes:
  portainer_data:
    name: layers-l10-portainer-data

secrets:
  portainer_admin_password:
    file: ./secrets/portainer_admin_password.txt
EOF
```

Ajoutez ce troisième fichier au parent de l'infra, qui prend sa forme finale :

```exec
cat > ~/byte-layers/docker/l10/prod/infra/compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
  - observability/compose.yaml
  - portainer/compose.yaml
EOF
```

Lancez l'infra sans profil, puis avec le profil `dev`, et comparez les deux listes de services :

```exec
cd ~/byte-layers/docker/l10/prod/infra && docker compose up -d && docker compose ps --format '{{.Service}}'
cd ~/byte-layers/docker/l10/prod/infra && docker compose --profile dev up -d && docker compose --profile dev ps --format '{{.Service}}'
```

La première liste n'a pas `portainer`, la seconde l'a.

> 📖 [Installer Portainer CE avec Docker](https://docs.portainer.io/start/install-ce/server/docker/linux) · [Les options de Portainer](https://docs.portainer.io/advanced/cli)

```verify
P="$HOME/byte-layers/docker/l10/prod/infra"
(cd "$P" && docker compose config --services 2>/dev/null) | grep -qx portainer && { echo "portainer démarre sans profil : il manque profiles: [dev]."; exit 1; }
[ "$(docker inspect layers-l10-infra-portainer-1 --format '{{.State.Running}}' 2>/dev/null)" = "true" ] || { echo "Portainer ne tourne pas. Lancez docker compose --profile dev up -d depuis $P."; exit 1; }
docker inspect layers-l10-infra-portainer-1 --format '{{json .Config.Cmd}}' | grep -q 'admin-password-file' || { echo "Portainer ne lit pas le mot de passe de l'administrateur dans un fichier : il manque --admin-password-file."; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:28402/portainer/api/system/status)" = "200" ] || { echo "Portainer ne répond pas sous /portainer/ : vérifiez ses labels et son middleware."; exit 1; }
echo "Portainer tourne dans l'infra, sous le profil dev."
```

```hint
L'option manquante s'écrit sur deux lignes de la liste `command:`, `- --admin-password-file`, puis `- /run/secrets/portainer_admin_password`.
```

````solution
```bash
mkdir -p ~/byte-layers/docker/l10/prod/infra/portainer/secrets && cd ~/byte-layers/docker/l10/prod/infra
[ -s portainer/secrets/portainer_admin_password.txt ] || openssl rand -base64 18 | tr -d '\n' > portainer/secrets/portainer_admin_password.txt
chmod 700 portainer/secrets
cat > portainer/compose.yaml <<'EOF'
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  portainer:
    image: portainer/portainer-ce:2.45.3
    # Seulement avec le profil dev : une interface d'administration n'a pas sa place partout
    profiles: [dev]
    command:
      - -H
      - unix:///var/run/docker.sock
      - --admin-password-file
      - /run/secrets/portainer_admin_password
    secrets:
      - portainer_admin_password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    read_only: true
    tmpfs:
      - /tmp
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=PathPrefix(`/portainer`)
      - traefik.http.routers.portainer.entrypoints=web
      - traefik.http.routers.portainer.middlewares=portainer-strip
      - traefik.http.middlewares.portainer-strip.stripprefix.prefixes=/portainer
      - traefik.http.services.portainer.loadbalancer.server.port=9000
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    logging: *default-logging
    networks:
      - proxy

networks:
  proxy:
    name: layers-l10-proxy

volumes:
  portainer_data:
    name: layers-l10-portainer-data

secrets:
  portainer_admin_password:
    file: ./secrets/portainer_admin_password.txt
EOF
cat > compose.yaml <<'EOF'
name: layers-l10-infra

# Le fichier parent : il ne décrit aucun service, il assemble ceux de l'infra
include:
  - traefik/compose.yaml
  - observability/compose.yaml
  - portainer/compose.yaml
EOF
docker compose --profile dev up -d
```
````

## Parcourir tout ce que vous avez construit

Ouvrez `http://localhost:28402/portainer/`, et connectez-vous avec l'utilisateur `admin` et le mot de passe que cette commande affiche :

```exec
cat ~/byte-layers/docker/l10/prod/infra/portainer/secrets/portainer_admin_password.txt; echo
```

Choisissez l'environnement **primary**, puis parcourez ce que vous avez monté :

- **Stacks** montre les deux projets Compose, `layers-l10-petclinic` et `layers-l10-infra`. Ils ont été créés en dehors de Portainer, qui n'a donc sur eux qu'un contrôle limité : il ne connaît pas leurs fichiers.
- **Containers** liste les neuf conteneurs. Les colonnes montrent leur état de santé, et l'icône de journaux de PetClinic affiche les mêmes lignes que Loki.
- **Networks** montre les trois réseaux nommés : `layers-l10-petclinic-backend` et `layers-l10-monitoring`, internes, et `layers-l10-proxy`, partagé par les deux projets.
- **Volumes** montre les volumes nommés de la base, de Loki, de Prometheus, de Grafana, d'Alloy et de Portainer.

C'est le serveur que vous avez construit, vu d'en haut : chaque choix de ce cas pratique, du réseau interne au volume nommé, s'y lit d'un coup d'œil.

```ack
J'ai parcouru l'infra et l'application dans Portainer
```
