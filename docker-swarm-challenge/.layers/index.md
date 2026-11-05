---
title: "Un service répliqué, mis à jour et restauré"
description: "Créer un swarm, y faire vivre un service répliqué, le mettre à jour progressivement, le restaurer, et résister à une image cassée, à partir d'un cahier des charges, sans guide."
tags:
  - challenge
  - docker
  - containers
difficulty: beginner
duration: 60
introTitle: "Le défi"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Ce challenge prouve que vous savez conduire un service sur Swarm, de sa création à son retour en arrière. Il n'y a **aucune commande à recopier** : chaque tâche donne un objectif et des critères, puis un bouton vérifie l'état réel du swarm. Toute suite de commandes qui produit le bon résultat est acceptée.

Si vous êtes bloqué, les **indices** se dévoilent un par un, et la **solution** reste en dernier recours. Les utiliser ne coûte rien : seule la vérification compte.

## Avant de commencer

- **Ce qu'il faut savoir** : ce qu'enseigne le cours « Déployer sur un cluster Swarm », et écrire un petit Dockerfile.
- **Ce qu'il faut avoir** : Docker qui répond à `docker ps`, `curl`, et le port **28394** libre. Un seul nœud suffit, et le poste hébergé convient.
- **Votre moteur ne doit être dans aucun swarm** : la dernière tâche le fait sortir de celui que vous allez créer, et elle dissoudrait un swarm existant. Vérifiez avec `docker info --format '{{.Swarm.LocalNodeState}}'`, qui doit répondre `inactive`. La vérification de la tâche 1 refuse de continuer si ce n'est pas le cas.
- **Un dossier de travail** : `~/layers-l9` est créé pour vous, et la dernière tâche le supprime. La vérification y garde aussi deux fichiers cachés, `.etat-initial` et `.service-id`, qui lui servent à connaître l'état de départ et à reconnaître votre service.
- **Les noms comptent** : les vérifications cherchent les noms exacts, tous préfixés par `layers-l9-`. Rien d'autre n'est inspecté ni supprimé sur votre machine, à part le swarm lui-même.
- **L'ordre compte** : chaque tâche reprend le service de la précédente. Ne le supprimez pas pour le recréer.
- **Pour interroger le service**, utilisez `http://127.0.0.1:28394` plutôt que `localhost`.

# Tâche 1 : un swarm

## Ce qu'il faut faire

```setup
mkdir -p ~/layers-l9
[ -f ~/layers-l9/.etat-initial ] || docker info --format '{{.Swarm.LocalNodeState}}' > ~/layers-l9/.etat-initial
```

Faites de votre moteur le manager d'un swarm.

**Critères :**

- votre moteur est dans un swarm actif ;
- il en est manager.

```hint
Il n'y a rien à installer : une seule commande active ce mode.
```

```hint
Si Docker dit qu'il ne sait pas quelle adresse choisir, il cite les adresses possibles : prenez-en une avec `--advertise-addr`.
```

```verify
if [ "$(cat "$HOME/layers-l9/.etat-initial" 2>/dev/null)" = "active" ]; then
  echo "ÉCHEC : votre moteur était déjà dans un swarm avant ce challenge, et la dernière tâche le dissoudrait."
  echo "  Si rien n'en dépend : docker swarm leave --force, puis rm ~/layers-l9/.etat-initial, et rouvrez cette tâche."
  exit 1
fi
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" != "active" ]; then
  echo "ÉCHEC : votre moteur n'est pas dans un swarm actif."
  exit 1
fi
if [ "$(docker info --format '{{.Swarm.ControlAvailable}}')" != "true" ]; then
  echo "ÉCHEC : votre moteur est dans un swarm, mais il n'en est pas manager."
  exit 1
fi
echo "RÉUSSI : votre moteur est manager d'un swarm actif."
```

````solution
```bash
docker swarm init
```
````

# Tâche 2 : un service répliqué

## Ce qu'il faut faire

Construisez deux versions d'une image, et lancez la première en service. Chaque version répond sur le port 8000 avec un texte qui donne son numéro.

**Critères :**

- les images `layers-l9-svc:1` et `layers-l9-svc:2` existent, et ce sont deux images différentes ;
- la page de la première contient `VERSION-1`, celle de la seconde contient `VERSION-2`, ce que la tâche suivante vérifiera ;
- un service s'appelle exactement `layers-l9-front`, et il utilise `layers-l9-svc:1` ;
- il a **2 répliques** qui tournent ;
- le port **28394** mène au port **8000** de ses tâches.

```hint
Le Dockerfile de l'étape 3 du cours convient presque tel quel : il suffit de changer le texte de la page. Il sert une page avec le serveur web de `busybox:1.37`.
```

```hint
`docker service create` prend `--replicas` et `-p`, comme vous l'avez vu dans le cours. L'avertissement sur le registre est normal avec une image locale, sur un seul nœud.
```

```verify
S=layers-l9-front
for v in 1 2; do
  if ! docker image inspect "layers-l9-svc:$v" >/dev/null 2>&1; then
    echo "ÉCHEC : l'image layers-l9-svc:$v n'existe pas."
    exit 1
  fi
done
if ! docker service inspect "$S" >/dev/null 2>&1; then
  echo "ÉCHEC : aucun service ne s'appelle $S."
  exit 1
fi
IMG=$(docker service inspect "$S" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
case "$IMG" in
  layers-l9-svc:1|layers-l9-svc:1@*) : ;;
  *) echo "ÉCHEC : $S utilise « $IMG », et non layers-l9-svc:1."; exit 1 ;;
esac
WANT=$(docker service inspect "$S" --format '{{if .Spec.Mode.Replicated}}{{.Spec.Mode.Replicated.Replicas}}{{end}}')
if [ -z "$WANT" ]; then
  echo "ÉCHEC : $S n'est pas en mode répliqué."
  exit 1
fi
if [ "$WANT" != "2" ]; then
  echo "ÉCHEC : $S demande $WANT répliques, et 2 sont attendues."
  exit 1
fi
PORTS=$(docker service inspect "$S" --format '{{range .Spec.EndpointSpec.Ports}}{{.TargetPort}}={{.PublishedPort}} {{end}}')
case " $PORTS" in
  *" 8000=28394 "*) : ;;
  *) echo "ÉCHEC : le port 28394 ne mène pas au port 8000 des tâches (trouvé : ${PORTS:-aucun port})."; exit 1 ;;
esac
if [ "$(docker service ls --filter name="$S" --format '{{.Replicas}}')" != "2/2" ]; then
  echo "ÉCHEC : les 2 répliques ne tournent pas. Regardez : docker service ps $S"
  exit 1
fi
OK=""
for i in 1 2 3 4 5; do
  curl -s --max-time 3 http://127.0.0.1:28394 | grep -q 'VERSION-1' && OK=1 && break
  sleep 1
done
if [ -z "$OK" ]; then
  echo "ÉCHEC : le service ne répond pas VERSION-1 sur le port 28394."
  exit 1
fi
if [ "$(docker image inspect layers-l9-svc:1 --format '{{.Id}}')" = "$(docker image inspect layers-l9-svc:2 --format '{{.Id}}')" ]; then
  echo "ÉCHEC : layers-l9-svc:1 et layers-l9-svc:2 sont la même image."
  exit 1
fi
docker service inspect "$S" --format '{{.ID}}' > "$HOME/layers-l9/.service-id"
echo "RÉUSSI : $S tourne avec 2 répliques, sur le port 28394."
```

````solution
```bash
mkdir -p ~/layers-l9/app
cat > ~/layers-l9/app/Dockerfile <<'EOF'
FROM busybox:1.37
ARG VERSION=1
ENV VERSION=$VERSION
CMD ["sh", "-c", "mkdir -p /www; echo \"VERSION-$VERSION\" > /www/index.html; exec httpd -f -p 8000 -h /www"]
EOF
docker build -t layers-l9-svc:1 --build-arg VERSION=1 ~/layers-l9/app
docker build -t layers-l9-svc:2 --build-arg VERSION=2 ~/layers-l9/app
docker service create --name layers-l9-front --replicas 2 -p 28394:8000 layers-l9-svc:1
```
````

# Tâche 3 : monter en charge et mettre à jour

## Ce qu'il faut faire

Passez le service à 3 répliques, puis mettez-le à jour vers la seconde version, progressivement.

**Critères :**

- `layers-l9-front` a **3 répliques** qui tournent, et c'est toujours le même service ;
- il utilise `layers-l9-svc:2`, et le service répond `VERSION-2` ;
- sa mise à jour remplace **une tâche à la fois**, ce qui est le réglage par défaut, avec **au moins 2 secondes** d'attente entre deux remplacements.

```hint
Changer le nombre de répliques est une commande à part. Faites-la d'abord, puis la mise à jour.
```

```hint
`docker service update` prend l'image, et deux options qui règlent le rythme : `--update-parallelism` et `--update-delay`.
```

```verify
S=layers-l9-front
if ! docker service inspect "$S" >/dev/null 2>&1; then
  echo "ÉCHEC : le service $S n'existe pas."
  exit 1
fi
if [ "$(cat "$HOME/layers-l9/.service-id" 2>/dev/null)" != "$(docker service inspect "$S" --format '{{.ID}}')" ]; then
  echo "ÉCHEC : $S n'est plus le service de la tâche 2, ou celle-ci n'a pas été vérifiée. Il ne fallait pas le recréer."
  exit 1
fi
IMG=$(docker service inspect "$S" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
case "$IMG" in
  layers-l9-svc:2|layers-l9-svc:2@*) : ;;
  *) echo "ÉCHEC : $S utilise « $IMG », et non layers-l9-svc:2."; exit 1 ;;
esac
if [ "$(docker service inspect "$S" --format '{{.Spec.Mode.Replicated.Replicas}}')" != "3" ]; then
  echo "ÉCHEC : $S ne demande pas 3 répliques."
  exit 1
fi
PAR=$(docker service inspect "$S" --format '{{.Spec.UpdateConfig.Parallelism}}')
if [ "$PAR" != "1" ]; then
  echo "ÉCHEC : la mise à jour remplace $PAR tâche(s) à la fois, et 1 est attendu."
  exit 1
fi
DELAY=$(docker service inspect "$S" --format '{{json .Spec.UpdateConfig.Delay}}')
case "$DELAY" in
  ''|*[!0-9]*) DELAY=0 ;;
esac
if [ "$DELAY" -lt 2000000000 ]; then
  echo "ÉCHEC : l'attente entre deux remplacements est inférieure à 2 secondes."
  exit 1
fi
for i in 1 2 3 4 5 6 7 8; do
  R=$(docker service ls --filter name="$S" --format '{{.Replicas}}')
  ST=$(docker service inspect "$S" --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}')
  [ "$R" = "3/3" ] && { [ "$ST" = "completed" ] || [ -z "$ST" ]; } && break
  sleep 2
done
if [ "$R" != "3/3" ]; then
  echo "ÉCHEC : les 3 répliques ne tournent pas (trouvé : $R). Patientez, puis réessayez."
  exit 1
fi
if [ "$ST" != "completed" ] && [ -n "$ST" ]; then
  echo "ÉCHEC : la mise à jour n'est pas terminée (état : $ST). Patientez, puis réessayez."
  exit 1
fi
for i in 1 2 3 4 5; do
  if ! curl -s --max-time 3 http://127.0.0.1:28394 | grep -q 'VERSION-2'; then
    echo "ÉCHEC : une réponse du service ne dit pas VERSION-2."
    exit 1
  fi
done
echo "RÉUSSI : $S a 3 répliques en version 2, et une mise à jour progressive."
```

````solution
```bash
docker service scale layers-l9-front=3
```

```bash
docker service update --update-parallelism 1 --update-delay 2s --image layers-l9-svc:2 layers-l9-front
```
````

# Tâche 4 : restaurer

## Ce qu'il faut faire

La version 2 pose problème : revenez à la version précédente, sans redonner sa description à Swarm.

**Critères :**

- `layers-l9-front` utilise de nouveau `layers-l9-svc:1`, et il répond `VERSION-1` ;
- la dernière opération est un **retour en arrière** terminé : relancer une mise à jour vers l'ancienne image n'en est pas un.

```hint
Swarm garde la description précédente du service. Une sous-commande de `docker service` y revient.
```

```hint
Pour voir l'état de la dernière opération : `docker service inspect layers-l9-front --format '{{.UpdateStatus.State}}'`.
```

```verify
S=layers-l9-front
if ! docker service inspect "$S" >/dev/null 2>&1; then
  echo "ÉCHEC : le service $S n'existe pas."
  exit 1
fi
if [ "$(cat "$HOME/layers-l9/.service-id" 2>/dev/null)" != "$(docker service inspect "$S" --format '{{.ID}}')" ]; then
  echo "ÉCHEC : $S n'est plus le service de la tâche 2. Il ne fallait pas le recréer."
  exit 1
fi
IMG=$(docker service inspect "$S" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
case "$IMG" in
  layers-l9-svc:1|layers-l9-svc:1@*) : ;;
  *) echo "ÉCHEC : $S utilise « $IMG », et non layers-l9-svc:1."; exit 1 ;;
esac
for i in 1 2 3 4 5 6 7 8; do
  ST=$(docker service inspect "$S" --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}')
  [ "$ST" = "rollback_completed" ] && break
  case "$ST" in completed) break ;; esac
  sleep 2
done
if [ "$ST" != "rollback_completed" ]; then
  echo "ÉCHEC : la dernière opération est dans l'état « ${ST:-aucun} », et non rollback_completed."
  echo "  Il faut un retour en arrière, et non une nouvelle mise à jour."
  exit 1
fi
OK=""
for i in 1 2 3 4 5; do
  curl -s --max-time 3 http://127.0.0.1:28394 | grep -q 'VERSION-1' && OK=1 && break
  sleep 1
done
if [ -z "$OK" ]; then
  echo "ÉCHEC : le service ne répond pas VERSION-1."
  exit 1
fi
echo "RÉUSSI : $S est revenu à la version 1 par un retour en arrière."
```

````solution
```bash
docker service rollback layers-l9-front
```
````

# Tâche 5 : résister à une image cassée

## Ce qu'il faut faire

Prouvez que le service se protège seul quand une mauvaise image arrive.

**Critères :**

- l'image `layers-l9-svc:casse` existe, et un conteneur lancé depuis elle s'arrête aussitôt avec une erreur ;
- une mise à jour de `layers-l9-front` vers cette image a été tentée ;
- Swarm est revenu à `layers-l9-svc:1`, ce que montre l'état `rollback_completed` ;
- le service répond toujours `VERSION-1`.

Laissez Swarm revenir en arrière de lui-même, sans lancer `docker service rollback` : c'est le geste qui compte. La vérification ne peut pas faire la différence, elle vous fait confiance.

```hint
Une image cassée se construit en deux lignes de Dockerfile : une image de départ, et une commande qui sort avec le code 1.
```

```hint
Par défaut, Swarm se met seulement en pause quand une mise à jour échoue. Une option de `docker service update` dit quoi faire en cas d'échec.
```

```verify
S=layers-l9-front
if ! docker image inspect layers-l9-svc:casse >/dev/null 2>&1; then
  echo "ÉCHEC : l'image layers-l9-svc:casse n'existe pas."
  exit 1
fi
if ! docker service inspect "$S" >/dev/null 2>&1; then
  echo "ÉCHEC : le service $S n'existe pas."
  exit 1
fi
if ! docker service ps "$S" --format '{{.Image}} {{.Error}}' | grep 'layers-l9-svc:casse' | grep -q 'non-zero exit'; then
  echo "ÉCHEC : l'historique de $S ne montre aucune tâche de l'image cassée en échec."
  echo "  Regardez : docker service ps $S"
  exit 1
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  ST=$(docker service inspect "$S" --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}')
  [ "$ST" = "rollback_completed" ] && break
  sleep 2
done
if [ "$ST" != "rollback_completed" ]; then
  echo "ÉCHEC : la dernière opération est dans l'état « ${ST:-aucun} », et non rollback_completed."
  echo "  Si elle est en pause, il manque la politique qui revient en arrière en cas d'échec."
  exit 1
fi
IMG=$(docker service inspect "$S" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
case "$IMG" in
  layers-l9-svc:1|layers-l9-svc:1@*) : ;;
  *) echo "ÉCHEC : $S utilise « $IMG », et non layers-l9-svc:1."; exit 1 ;;
esac
OK=""
for i in 1 2 3 4 5; do
  curl -s --max-time 3 http://127.0.0.1:28394 | grep -q 'VERSION-1' && OK=1 && break
  sleep 1
done
if [ -z "$OK" ]; then
  echo "ÉCHEC : le service ne répond pas VERSION-1."
  exit 1
fi
echo "RÉUSSI : l'image cassée a échoué, et le service est revenu à la version 1."
```

````solution
```bash
printf 'FROM busybox:1.37\nCMD ["sh", "-c", "exit 1"]\n' | docker build -t layers-l9-svc:casse -
docker service update --update-failure-action rollback --image layers-l9-svc:casse layers-l9-front
```
````

# Tâche 6 : ne rien laisser derrière soi

## Ce qu'il faut faire

Supprimez tout ce que ce challenge a créé : le service `layers-l9-front`, le swarm, les images `layers-l9-svc` et le dossier `~/layers-l9`.

**Critères :** plus de service, un moteur dans l'état `inactive`, plus d'image à ce nom, plus de dossier. Vos autres images et conteneurs ne sont pas concernés.

```hint
Un manager seul ne quitte son swarm qu'avec une option qui force la décision, car ce geste dissout le cluster.
```

```hint
Attendez un instant entre la suppression du service et celle de ses images : Docker refuse de supprimer une image qu'un conteneur utilise encore.
```

```verify
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "inactive" ]; then
  echo "ÉCHEC : votre moteur est encore dans un swarm."
  exit 1
fi
left=$(docker images --format '{{.Repository}}' | grep 'layers-l9-svc')
if [ -n "$left" ]; then
  echo "ÉCHEC : il reste des images : $(echo "$left" | sort -u | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l9" ]; then
  echo "ÉCHEC : le dossier ~/layers-l9 existe encore."
  exit 1
fi
echo "RÉUSSI : tout est propre. Vous savez conduire un service sur Swarm."
```

````solution
```bash
docker service rm layers-l9-front
docker swarm leave --force
sleep 5
docker rmi layers-l9-svc:1 layers-l9-svc:2 layers-l9-svc:casse
rm -rf ~/layers-l9
```
````
