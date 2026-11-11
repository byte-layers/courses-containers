---
title: "Le bilan, le nettoyage, et ce qui vient après"
description: "Contrôler l'ensemble, supprimer ce que le cas pratique a créé, et découvrir les plateformes qui font ce travail pour vous"
---

Vous avez livré une vraie application Java comme on la livrerait en production. Ce dernier chapitre contrôle l'ensemble une dernière fois, nettoie le poste, et regarde ce que l'on ferait ensuite.

## Contrôler le cas pratique complet

Ce contrôle reprend tout ce que les trois parties ont construit :

- PetClinic tourne sur une image distroless, sans droits, avec sa base PostgreSQL ;
- le mot de passe de la base n'apparaît dans aucune variable d'environnement ;
- seul Traefik publie des ports, et la base reste hors de son réseau ;
- les journaux de PetClinic arrivent dans Loki, et ses métriques dans Prometheus ;
- Grafana répond par Traefik.

```verify
fail() { echo "$1"; exit 1; }
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1 layers-l10-infra-traefik-1 layers-l10-infra-loki-1 layers-l10-infra-alloy-1 layers-l10-infra-prometheus-1 layers-l10-infra-grafana-1; do
  [ "$(docker inspect $C --format '{{.State.Running}}' 2>/dev/null)" = "true" ] || fail "$C ne tourne pas."
done
case "$(docker inspect layers-l10-petclinic-app-1 --format '{{.Config.User}}')" in nonroot|65532*) : ;; *) false ;; esac || fail "PetClinic ne tourne pas avec l'utilisateur nonroot de l'image distroless."
PW=$(cat "$HOME/byte-layers/docker/l10/prod/petclinic/secrets/db_password.txt" 2>/dev/null)
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1; do
  docker inspect $C --format '{{json .Config.Env}}' | grep -qF "$PW" && fail "Le mot de passe apparaît dans l'environnement de $C."
done
for C in layers-l10-petclinic-app-1 layers-l10-petclinic-db-1 layers-l10-infra-grafana-1 layers-l10-infra-prometheus-1 layers-l10-infra-loki-1; do
  [ -z "$(docker port $C)" ] || fail "$C publie un port : seul Traefik doit le faire."
done
docker inspect layers-l10-petclinic-db-1 --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}' | grep -q 'layers-l10-proxy' && fail "La base ne doit pas être sur le réseau du proxy."
curl -s --max-time 5 http://localhost:28402/ | grep -q 'PetClinic' || fail "http://localhost:28402/ ne répond pas la page de PetClinic."
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:28402/grafana/api/health)" = "200" ] || fail "Grafana ne répond pas sous /grafana."
docker exec layers-l10-infra-grafana-1 wget -qO- http://loki:3100/loki/api/v1/label/job/values 2>/dev/null | grep -q 'layers-l10-petclinic-app-1' || fail "Loki n'a pas de journaux de PetClinic."
docker exec layers-l10-infra-prometheus-1 wget -qO- 'http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22petclinic%22%7D' 2>/dev/null | grep -q '"1"\]' || fail "Prometheus ne joint pas l'agent de PetClinic."
echo "Le cas pratique est complet : une application durcie, une seule porte, et tout est observé."
```

````solution
Ce contrôle ne demande rien de nouveau : si un élément manque, reprenez le chapitre qui le construit. Ces commandes relancent les deux projets, l'infra d'abord, puisqu'elle crée le réseau partagé :

```bash
cd ~/byte-layers/docker/l10/prod/infra && docker compose --profile dev up -d
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose --profile dev up -d
```
````

## Les trois couches construites, et le risque que chacune réduit

Chaque partie a apporté une couche, et chaque choix répond à un risque précis :

| Couche | Les choix | Le risque réduit |
|---|---|---|
| l'image | des versions précises et un digest, un multi-stage, distroless, un utilisateur sans droits, un healthcheck, un `ENTRYPOINT` en forme exec | une construction non reproductible, une surface d'attaque large, un arrêt brutal |
| le fichier Compose | des secrets en fichiers, des réseaux nommés dont un interne, des ancres pour les journaux et le durcissement, des limites, un ordre de démarrage, un profil `dev` | un mot de passe qui fuit, une base exposée, un disque plein, un conteneur qui affame les autres |
| l'infra | un reverse proxy seul à publier des ports, une pile de journaux et de métriques, assemblés par `include`, et une interface sous profil | des ports ouverts partout, une panne que personne ne voit, une infra illisible |

## Supprimer ce que le cas pratique a créé

L'ordre compte : l'application part d'abord, car elle utilise le réseau de l'infra, que Docker refuse de supprimer tant qu'il sert. `--profile dev` arrête aussi les services de ce profil, et `-v` supprime les volumes, donc les données :

```exec
cd ~/byte-layers/docker/l10/prod/petclinic && docker compose --profile dev down -v
cd ~/byte-layers/docker/l10/prod/infra && docker compose --profile dev down -v
```

Supprimez ensuite les images que le cas pratique a construites ou téléchargées, puis le cache de construction de BuildKit, et enfin le dossier de travail :

```exec
docker images 'layers-l10-petclinic' -q | sort -u | xargs -r docker rmi -f
docker rmi postgres:18.6-alpine3.24 adminer:5.5.1 traefik:v3.7.17 grafana/loki:3.7.9 grafana/alloy:v1.21.3 prom/prometheus:v3.16.0 grafana/grafana:13.2.5 portainer/portainer-ce:2.45.3
docker builder prune -f
cd ~ && rm -rf ~/byte-layers/docker/l10
```

La première ligne supprime toutes les versions de l'image de PetClinic, quels que soient leurs tags. Si une image de la deuxième ligne est absente, parce que vous avez sauté un chapitre, `docker rmi` le signale et supprime les autres. `docker builder prune -f` vide le cache de BuildKit, qui garde aussi les images de base de la partie A : Maven, Temurin et distroless.

```verify
[ -z "$(docker ps -a --format '{{.Names}}' | grep '^layers-l10-')" ] || { echo "Il reste des conteneurs : $(docker ps -a --format '{{.Names}}' | grep '^layers-l10-' | tr '\n' ' ')"; exit 1; }
[ -z "$(docker network ls --format '{{.Name}}' | grep '^layers-l10-')" ] || { echo "Il reste des réseaux : $(docker network ls --format '{{.Name}}' | grep '^layers-l10-' | tr '\n' ' ')"; exit 1; }
[ -z "$(docker volume ls --format '{{.Name}}' | grep '^layers-l10-')" ] || { echo "Il reste des volumes : $(docker volume ls --format '{{.Name}}' | grep '^layers-l10-' | tr '\n' ' ')"; exit 1; }
[ -z "$(docker images --format '{{.Repository}}' | grep '^layers-l10-')" ] || { echo "Il reste des images layers-l10- : supprimez-les avec docker rmi."; exit 1; }
[ ! -e "$HOME/byte-layers/docker/l10" ] || { echo "Le dossier ~/byte-layers/docker/l10 existe encore."; exit 1; }
echo "C'est propre."
```

````solution
```bash
cd ~/byte-layers/docker/l10/prod/petclinic 2>/dev/null && docker compose --profile dev down -v
cd ~/byte-layers/docker/l10/prod/infra 2>/dev/null && docker compose --profile dev down -v
docker images 'layers-l10-petclinic' -q | sort -u | xargs -r docker rmi -f
docker rmi postgres:18.6-alpine3.24 adminer:5.5.1 traefik:v3.7.17 grafana/loki:3.7.9 grafana/alloy:v1.21.3 prom/prometheus:v3.16.0 grafana/grafana:13.2.5 portainer/portainer-ce:2.45.3 2>/dev/null
docker builder prune -f
cd ~ && rm -rf ~/byte-layers/docker/l10
```
````

## 🌉 Ouverture : les plateformes qui font ce travail pour vous

Vous avez tout monté à la main : le reverse proxy, ses labels, la pile de journaux, les métriques, les secrets, l'interface. C'est le meilleur moyen de comprendre ce qui se passe sur un serveur. C'est aussi beaucoup de fichiers à maintenir, application après application.

Des plateformes auto-hébergées font ce travail pour vous, sur votre propre serveur. On leur donne un dépôt Git ou un fichier Compose, et elles construisent l'image, la déploient derrière leur reverse proxy, obtiennent le certificat HTTPS, et affichent journaux et métriques. Deux d'entre elles sont très suivies :

| Plateforme | Ce qu'elle propose |
|---|---|
| [Coolify](https://coolify.io/) | le déploiement depuis Git ou depuis un fichier Compose, des bases de données en un clic avec leurs sauvegardes, des certificats automatiques, sur un ou plusieurs serveurs |
| [Dokploy](https://dokploy.com/) | les mêmes fonctions de déploiement, avec Traefik intégré, la supervision des ressources de chaque application, et Docker Swarm pour répartir les applications sur plusieurs serveurs |

Ces deux plateformes sont open source et s'installent sur votre serveur. Vérifiez leurs conditions de licence et leur modèle d'offre hébergée avant de les adopter en entreprise. Ce que vous avez appris ici reste utile avec elles : vous saurez lire ce qu'elles génèrent, et dépanner quand elles ne suffisent pas.

## Récap

- Une image se durcit dès le `Dockerfile` : une version précise, un utilisateur sans droits, une forme exec, un multi-stage et une base distroless. Le scan le confirme, il ne le remplace pas.
- Un fichier Compose se durcit service par service, et les ancres YAML écrivent une fois ce qui est commun. Les secrets passent par des fichiers, jamais par des variables.
- L'infra vit dans son propre dossier, avec un fichier parent qui assemble ses fichiers par `include`. Elle possède le réseau partagé, que les applications déclarent `external`.
- Traefik est la seule porte d'entrée. Les applications n'y publient rien, et lui donnent leurs routes par des labels.
- Les journaux se collectent depuis la sortie standard, sans changer l'application. Les métriques d'une application Java se publient par un agent, sans toucher à son code.

Tous les fichiers de ce cas pratique se trouvent dans le dossier [`solution/`](../../solution/) de ce contenu.
