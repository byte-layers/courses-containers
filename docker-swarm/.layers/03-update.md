---
title: "Mettre à jour et revenir en arrière"
description: "Un remplacement progressif, un retour en arrière à la main, puis automatique"
---

Changer de version sans coupure est la raison pour laquelle beaucoup d'équipes adoptent un orchestrateur. Pour le voir, il faut une image dont on reconnaît la version et la copie qui répond. Vous allez donc en construire une.

## Préparer deux versions

Créez un dossier et un Dockerfile. Cette image part de `busybox:1.37`, un Linux minimal qui contient un petit serveur web. `cat > fichier <<'EOF'` écrit dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` :

```exec
mkdir -p ~/layers-l9/app
cat > ~/layers-l9/app/Dockerfile <<'EOF'
FROM busybox:1.37
ARG VERSION=1
ENV VERSION=$VERSION
CMD ["sh", "-c", "mkdir -p /www; echo \"version $VERSION servie par $(hostname)\" > /www/index.html; exec httpd -f -p 8000 -h /www"]
EOF
```

Le tableau suivant détaille ce que fait ce Dockerfile.

| Élément | Rôle |
|---|---|
| `ARG VERSION=1` | une valeur donnée au moment du build, avec `1` par défaut |
| `ENV VERSION=$VERSION` | la garde dans l'image, pour qu'elle soit lisible au démarrage |
| `$(hostname)` | le nom du conteneur, différent pour chaque tâche |
| `exec httpd -f -p 8000 -h /www` | le serveur web, au premier plan, sur le port 8000, qui sert le dossier `/www` ; `exec` lui fait prendre la place du shell, et il devient le processus principal du conteneur |

Construisez les deux versions. `--build-arg` donne sa valeur à `VERSION` :

```exec
docker build -t layers-l9-app:1 ~/layers-l9/app
docker build -t layers-l9-app:2 --build-arg VERSION=2 ~/layers-l9/app
```

```verify
for v in 1 2; do
  if ! docker image inspect "layers-l9-app:$v" >/dev/null 2>&1; then
    echo "L'image layers-l9-app:$v n'existe pas. Lancez les commandes de cette section."
    exit 1
  fi
done
echo "Les deux versions sont construites."
```

## Lancer la version 1

Créez un service de 3 répliques avec la première version :

```exec
docker service create --name layers-l9-api --replicas 3 -p 28392:8000 layers-l9-app:1
```

Docker vous avertit d'abord : `image layers-l9-app:1 could not be accessed on a registry`. Cette image n'existe que sur votre machine, et Swarm ne peut donc pas noter son digest. C'est sans conséquence sur un seul nœud, mais c'est un vrai problème sur un cluster : **Swarm ne construit pas d'image et ne les transporte pas**, et un autre nœud ne trouverait pas celle-ci. Sur un cluster, on pousse donc d'abord l'image dans un registre, comme l'a montré le cours « Publier une image : pull, tag, push ». Ce raccourci n'est acceptable ici que parce que vous n'avez qu'un seul nœud.

Interrogez maintenant le service plusieurs fois de suite. `seq 1 6` compte de 1 à 6, et la boucle lance `curl` à chaque tour :

```exec
for i in $(seq 1 6); do curl -sS --retry 3 --retry-delay 1 --retry-all-errors --max-time 5 http://127.0.0.1:28392; done
```

Vous lisez la même version six fois, mais avec trois noms différents, qui reviennent à tour de rôle : le routing mesh répartit bien les requêtes.

```text
version 1 servie par 7884839e0f8e
version 1 servie par b466b86be3b5
version 1 servie par 3f9f5f1df82c
version 1 servie par 7884839e0f8e
version 1 servie par b466b86be3b5
version 1 servie par 3f9f5f1df82c
```

```verify
if [ "$(docker service ls --filter name=layers-l9-api --format '{{.Replicas}}')" != "3/3" ]; then
  echo "Le service layers-l9-api n'a pas 3 répliques en cours d'exécution. Regardez : docker service ps layers-l9-api"
  exit 1
fi
if ! curl -s --max-time 5 http://127.0.0.1:28392 | grep -q 'version 1'; then
  echo "Le service ne répond pas « version 1 » sur le port 28392."
  exit 1
fi
echo "La version 1 tourne, avec 3 répliques."
```

## Mettre à jour progressivement

Remplacer les trois copies d'un coup provoquerait une coupure. `docker service update` les remplace donc par groupes, selon un rythme que vous choisissez :

```exec
docker service update --update-parallelism 1 --update-delay 2s --image layers-l9-app:2 layers-l9-api
```

| Option | Rôle |
|---|---|
| `--image layers-l9-app:2` | le changement d'état voulu : la nouvelle image |
| `--update-parallelism 1` | remplacer une tâche à la fois ; c'est la valeur par défaut, écrite ici pour la voir |
| `--update-delay 2s` | attendre 2 secondes entre deux remplacements |

La commande dure près d'une minute, et c'est normal. Ce petit serveur ignore la demande d'arrêt, comme `sleep` dans « Lancer, configurer et observer un conteneur » : chaque ancienne tâche attend donc les 10 secondes du délai avant d'être tuée, puis Swarm surveille la nouvelle et respecte votre attente de 2 secondes.

Swarm retient ces réglages pour les mises à jour suivantes. Regardez l'historique ; l'option `--format` limite l'affichage aux colonnes utiles :

```exec
docker service ps layers-l9-api --format 'table {{.Name}}\t{{.Image}}\t{{.CurrentState}}'
```

Chaque tâche a maintenant une ligne en version 2 qui tourne, et, en dessous, une ligne `\_` en version 1 arrêtée. Swarm garde ces anciennes tâches pour que vous puissiez comprendre ce qui s'est passé. Si vous aviez lancé des requêtes pendant la mise à jour, certaines auraient reçu la version 1 et d'autres la version 2 : les deux versions coexistent un moment, et l'application doit le supporter.

⚖️ **« Sans coupure » a une limite.** Le service reste disponible dans son ensemble, mais par défaut Swarm arrête une tâche avant de démarrer la suivante, et une requête isolée peut échouer pendant ce remplacement. En production, on ajoute un healthcheck à l'image, et `--update-order start-first`, qui démarre la nouvelle tâche avant d'arrêter l'ancienne.

```verify
IMG=$(docker service inspect layers-l9-api --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null)
case "$IMG" in
  layers-l9-app:2*) : ;;
  *) echo "Le service utilise « $IMG », et non layers-l9-app:2. Lancez docker service update."; exit 1 ;;
esac
if [ "$(docker service inspect layers-l9-api --format '{{.Spec.UpdateConfig.Parallelism}}')" != "1" ]; then
  echo "Le réglage --update-parallelism n'est pas à 1."
  exit 1
fi
if ! curl -s --max-time 5 http://127.0.0.1:28392 | grep -q 'version 2'; then
  echo "Le service ne répond pas encore « version 2 ». Attendez la fin de la mise à jour, puis réessayez."
  exit 1
fi
echo "La version 2 tourne."
```

## Revenir en arrière

La version 2 pose problème ? Swarm a gardé la description précédente du service, et `docker service rollback` y revient sans que vous ayez à la redonner. Comptez là aussi près d'une minute :

```exec
docker service rollback layers-l9-api
```

Demandez ensuite la page, et le champ `UpdateStatus` de la fiche du service, qui décrit la dernière opération :

```exec
sleep 2
curl -sS --max-time 5 http://127.0.0.1:28392
docker service inspect layers-l9-api --format '{{.UpdateStatus.State}}'
```

Vous lisez `version 1 servie par …`, puis `rollback_completed`. Ce retour en arrière ne remonte que d'un cran : le lancer une seconde fois ramènerait la version 2.

```verify
IMG=$(docker service inspect layers-l9-api --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null)
case "$IMG" in
  layers-l9-app:1*) : ;;
  *) echo "Le service utilise « $IMG », et non layers-l9-app:1. Lancez docker service rollback."; exit 1 ;;
esac
if [ "$(docker service inspect layers-l9-api --format '{{.UpdateStatus.State}}')" != "rollback_completed" ]; then
  echo "La dernière opération n'est pas un retour en arrière terminé. Patientez, ou relancez docker service rollback."
  exit 1
fi
echo "Le service est revenu à la version 1."
```

## Laisser Swarm décider

Vous ne serez pas toujours là quand une mise à jour échoue. Construisez une image volontairement cassée, qui s'arrête aussitôt avec une erreur. Le `-` à la fin de `docker build` lui fait lire le Dockerfile depuis ce qui suit, sans fichier :

```exec
printf 'FROM busybox:1.37\nCMD ["sh", "-c", "echo je plante; exit 1"]\n' | docker build -t layers-l9-app:casse -
```

Demandez la mise à jour, en disant à Swarm ce qu'il doit faire en cas d'échec :

```exec
docker service update --update-failure-action rollback --update-monitor 5s --image layers-l9-app:casse layers-l9-api
```

| Option | Rôle |
|---|---|
| `--update-monitor 5s` | surveiller chaque nouvelle tâche pendant 5 secondes : une tâche qui s'arrête dans ce délai compte comme un échec ; c'est la valeur par défaut, écrite ici pour la voir |
| `--update-failure-action rollback` | en cas d'échec, revenir en arrière ; par défaut, Swarm se met seulement en pause |

La commande dure une trentaine de secondes, puis elle vous rend la main. Vous n'avez rien eu à faire d'autre. Vérifiez ce qui s'est passé :

```exec
docker service inspect layers-l9-api --format '{{.Spec.TaskTemplate.ContainerSpec.Image}} {{.UpdateStatus.State}}'
docker service ps layers-l9-api --filter desired-state=shutdown --format '{{.Image}} {{.Error}}' | grep casse
curl -sS --max-time 5 http://127.0.0.1:28392
```

Le service est de retour sur `layers-l9-app:1` avec l'état `rollback_completed`, l'historique garde la trace de l'échec avec `task: non-zero exit (1)`, et la page répond toujours : l'application n'a pas cessé de servir, puisque seule une partie des tâches a été touchée avant l'arrêt de la mise à jour.

Une surprise à connaître : le retour en arrière restaure **toute** la description précédente du service, y compris ses options. La politique `rollback` que vous venez de donner a donc disparu avec lui. Pour qu'elle reste, il faut la poser à la création du service, ou lors d'une mise à jour réussie.

```verify
IMG=$(docker service inspect layers-l9-api --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null)
case "$IMG" in
  layers-l9-app:1*) : ;;
  *) echo "Le service utilise « $IMG ». S'il n'est pas revenu à la version 1, attendez un peu, puis réessayez."; exit 1 ;;
esac
if ! docker service ps layers-l9-api --format '{{.Image}}' | grep -q casse; then
  echo "L'historique ne contient aucune tâche de l'image cassée. Lancez la mise à jour de cette section."
  exit 1
fi
if [ "$(docker service inspect layers-l9-api --format '{{.UpdateStatus.State}}')" != "rollback_completed" ]; then
  echo "Le retour en arrière n'est pas terminé. Patientez, puis réessayez."
  exit 1
fi
echo "Swarm a refusé l'image cassée et il est revenu en arrière tout seul."
```

Ce service ne vous servira plus, et vous pouvez le supprimer.

```exec
docker service rm layers-l9-api
```

> 📖 [Le tutoriel sur les mises à jour](https://docs.docker.com/engine/swarm/swarm-tutorial/rolling-update/) · [`docker service update`](https://docs.docker.com/reference/cli/docker/service/update/) · [`docker service rollback`](https://docs.docker.com/reference/cli/docker/service/rollback/)

## Récap

- `docker service update --image` remplace les tâches par groupes, au rythme choisi.
- `docker service rollback` revient à la description précédente du service.
- `--update-failure-action rollback` laisse Swarm revenir en arrière tout seul.
- Swarm ne construit ni ne transporte les images : sur un cluster, elles passent par un registre.

## Questions

```quiz
title: "Mises à jour"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que fait `--update-parallelism 1 --update-delay 10s` sur un service de 6 répliques ?"
    answers:
      - "Il arrête tout, attend 10 secondes, puis relance les 6"
      - "Il remplace une tâche, attend 10 secondes, et continue avec la suivante"
      - "Il lance 10 tâches en parallèle"
    correct: 2
    explanation: "Il reste toujours des tâches en service pendant la mise à jour, ce qui évite la coupure."
  - prompt: "Par défaut, que fait Swarm si une nouvelle tâche échoue pendant une mise à jour ?"
    answers:
      - "Il revient en arrière"
      - "Il se met en pause, et attend votre décision"
      - "Il continue quand même"
    correct: 2
    explanation: "C'est la valeur `pause`, visible dans `docker service inspect --pretty`. Pour un retour automatique, il faut `--update-failure-action rollback`."
  - prompt: "Sur un cluster de 3 nœuds, vous créez un service avec une image construite sur le manager, sans registre. Que se passe-t-il ?"
    answers:
      - "Swarm copie l'image vers les autres nœuds"
      - "Les tâches placées sur les autres nœuds ne trouvent pas l'image"
      - "Swarm reconstruit l'image sur chaque nœud"
    correct: 2
    explanation: "Chaque nœud télécharge l'image pour lui-même. Elle doit donc être dans un registre que tous peuvent joindre."
```
