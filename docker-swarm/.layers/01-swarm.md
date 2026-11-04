---
title: "Créer le swarm"
description: "Les mots de Swarm, le passage en mode swarm, et ce qu'il faudrait pour ajouter un nœud"
---

Swarm est déjà dans Docker : il n'y a rien à installer, seulement un mode à activer. Avant cela, il faut poser les mots que vous allez rencontrer à chaque commande.

## Les mots de Swarm

Ces cinq mots suffisent pour tout ce cours, et vous les verrez apparaître l'un après l'autre.

| Mot | Ce qu'il désigne |
|---|---|
| **nœud** (*node*) | une machine du cluster, ou plus exactement un moteur Docker |
| **manager** | un nœud qui garde l'état voulu et décide où placer les conteneurs |
| **worker** | un nœud qui exécute seulement les conteneurs qu'on lui confie |
| **service** | l'état voulu : « je veux N copies de cette image » |
| **tâche** (*task*) | une copie d'un service, c'est-à-dire un conteneur placé sur un nœud |

Un manager exécute aussi des tâches par défaut. C'est ce qui permet à un swarm d'un seul nœud de fonctionner : votre moteur sera à la fois celui qui décide et celui qui exécute.

## Vérifier le point de départ

Votre moteur ne doit pas déjà faire partie d'un swarm, car la dernière étape l'en fera sortir. Regardez son état :

```exec
docker info --format '{{.Swarm.LocalNodeState}}'
```

Vous devez lire `inactive`. Si vous lisez `active`, votre moteur est déjà dans un swarm, peut-être parce que vous avez essayé un jour. La vérification s'arrête là pour vous protéger. Si vous savez que rien n'en dépend, sortez-en avec `docker swarm leave --force`. Sinon, suivez ce cours sur une autre machine.

```verify
STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
if [ -z "$STATE" ]; then
  echo "Docker ne répond pas. Démarrez-le, puis réessayez."
  exit 1
fi
if [ "$STATE" != "inactive" ]; then
  echo "Votre moteur est dans l'état « $STATE », et non « inactive »."
  echo "Il est déjà dans un swarm, que la fin de ce cours dissoudrait. Lisez le texte de cette section avant de continuer."
  exit 1
fi
echo "Votre moteur n'est dans aucun swarm : vous pouvez continuer."
```

## Activer le mode swarm

`docker swarm init` fait de votre moteur le premier manager d'un nouveau swarm :

```exec
docker swarm init
```

La réponse commence ainsi, avec votre propre identifiant et votre propre adresse :

```text
Swarm initialized: current node (sgr8dzgq9i5b9pkzawjzq5c47) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-… 172.17.0.3:2377
```

Votre moteur a créé un cluster, et il vous indique la commande à lancer sur une autre machine pour la faire entrer. Vous n'en aurez pas besoin ici. Le **jeton** (*token*) qu'elle contient donne le droit de rejoindre ce swarm : traitez-le comme un mot de passe.

⚠️ **Si la commande échoue.**

- *Symptôme :* `could not choose an IP address to advertise since this system has multiple addresses on different interfaces`.
- *Cause :* votre machine a plusieurs adresses, par exemple un Wi-Fi et un VPN, et Docker ne sait pas laquelle annoncer aux autres nœuds. Le message les cite toutes.
- *Correctif :* choisissez-en une parmi celles qu'il affiche : `docker swarm init --advertise-addr <adresse>`.

```verify
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" != "active" ]; then
  echo "Votre moteur n'est pas en mode swarm. Lancez docker swarm init."
  exit 1
fi
if [ "$(docker info --format '{{.Swarm.ControlAvailable}}')" != "true" ]; then
  echo "Votre moteur est dans un swarm, mais il n'en est pas manager."
  exit 1
fi
echo "Votre moteur est le manager de ce swarm."
```

## Voir le cluster

`docker node ls` liste les nœuds. Cette commande n'existe que sur un manager, car c'est lui qui garde cette information :

```exec
docker node ls
```

Vous lisez une seule ligne, votre nœud, avec l'état `Ready`, la disponibilité `Active` et la mention `Leader`. Le **leader** est le manager qui prend les décisions ; ici, il est seul. L'astérisque marque le nœud auquel votre client parle.

Avec plusieurs managers, le cluster survit à la perte de l'un d'eux, à condition qu'une majorité reste en vie. On compte donc 3 ou 5 managers en production, jamais 2, parce que la perte de l'un des deux ferait perdre la majorité.

## Retrouver le jeton

La commande pour ajouter un nœud n'a pas besoin d'être notée quand elle apparaît : le manager la redonne à la demande, en lecture seule.

```exec
docker swarm join-token worker
```

Sur une autre machine, c'est tout ce qu'il y aurait à lancer. Il faudrait aussi que le port 2377 du manager soit joignable depuis cette machine. Vous verrez à l'étape 5 ce que cela donne.

```ack
Je sais où retrouver la commande pour ajouter un nœud
```

> 📖 [Les notions de Swarm](https://docs.docker.com/engine/swarm/key-concepts/) · [`docker swarm init`](https://docs.docker.com/reference/cli/docker/swarm/init/) · [Le tutoriel officiel](https://docs.docker.com/engine/swarm/swarm-tutorial/)

## Récap

- Un swarm se crée avec `docker swarm init`, sans rien installer.
- Un manager décide, un worker exécute, et un manager exécute aussi par défaut.
- `docker swarm join-token worker` redonne la commande pour ajouter un nœud.

## Questions

```quiz
title: "Le swarm"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Quelle est la différence entre un service et une tâche ?"
    answers:
      - "Aucune, ce sont deux mots pour un conteneur"
      - "Le service est l'état voulu, et une tâche est l'une de ses copies, placée sur un nœud"
      - "Un service tourne sur un manager, une tâche sur un worker"
    correct: 2
    explanation: "Vous décrivez le service, et Swarm crée les tâches pour le réaliser. Chaque tâche correspond à un conteneur."
  - prompt: "Pourquoi un swarm d'un seul nœud peut-il exécuter des conteneurs ?"
    answers:
      - "Parce qu'un manager exécute aussi des tâches par défaut"
      - "Parce que Swarm crée un worker caché"
      - "Il ne peut pas : il faut au moins deux nœuds"
    correct: 1
    explanation: "Par défaut, un manager est aussi disponible pour exécuter des tâches. En production, on l'en empêche souvent pour le préserver."
  - prompt: "Pourquoi préfère-t-on 3 managers à 2 ?"
    answers:
      - "Pour aller plus vite"
      - "Parce qu'il faut garder une majorité : avec 2, la perte de l'un d'eux la fait perdre"
      - "Parce que Docker refuse d'en créer 2"
    correct: 2
    explanation: "Avec 3 managers, la majorité est de 2 : on peut en perdre un. Avec 2, la majorité est de 2 : on ne peut en perdre aucun."
```
