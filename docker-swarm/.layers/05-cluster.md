---
title: "Ce que change un vrai cluster"
description: "Plusieurs nœuds, retirer une machine pour la maintenance, puis le ménage"
---

Les commandes que vous avez lancées seraient les mêmes sur plusieurs machines, à condition que l'image vienne d'un registre, comme l'a dit l'étape 3. Il vous a seulement manqué de voir les tâches se répartir, et un nœud se vider. Cette étape vous le montre, puis elle vous fait sortir du swarm.

## À quoi ressemblent plusieurs nœuds

Ce bloc n'est pas à lancer. C'est la vraie sortie d'un swarm de deux nœuds, `poste` et `layers-l9-node1`, avec un service de 4 répliques : Swarm a réparti les tâches à parts égales.

```text
NAME              NODE              CURRENT STATE
layers-l9-web.1   layers-l9-node1   Running 5 seconds ago
layers-l9-web.2   poste             Running 5 seconds ago
layers-l9-web.3   layers-l9-node1   Running 5 seconds ago
layers-l9-web.4   poste             Running 5 seconds ago
```

Pour faire la maintenance d'une machine, on la vide d'abord de ses tâches : on la met en **drain**. Voici le même service juste après `docker node update --availability drain layers-l9-node1`. Les tâches de ce nœud sont arrêtées, et elles repartent sur l'autre :

```text
NAME                  NODE              DESIRED STATE   CURRENT STATE
layers-l9-web.1       poste             Running         Running 10 seconds ago
 \_ layers-l9-web.1   layers-l9-node1   Shutdown        Shutdown 10 seconds ago
layers-l9-web.2       poste             Running         Running 17 seconds ago
layers-l9-web.3       poste             Running         Running 10 seconds ago
 \_ layers-l9-web.3   layers-l9-node1   Shutdown        Shutdown 10 seconds ago
layers-l9-web.4       poste             Running         Running 17 seconds ago
```

⚖️ **Pourquoi ne pas le faire ici ?** On peut simuler un second nœud avec un conteneur `docker:28-dind`, qui fait tourner un moteur Docker dans un conteneur. C'est ainsi que ces sorties ont été obtenues. Mais ce montage n'est pas assez fiable pour un cours : à l'essai, une requête sur deux n'arrivait pas aux tâches du second nœud, parce que le réseau `overlay` ne passait pas entre les deux moteurs imbriqués. Pour un vrai essai à plusieurs nœuds, prenez deux ou trois machines virtuelles.

```ack
Je vois ce que change un second nœud
```

## Le drain sur un seul nœud

Vous pouvez tout de même essayer le drain sur votre nœud, et voir ce qui arrive quand aucun autre nœud n'est là pour reprendre les tâches. Lancez un petit service. `--detach` rend la main sans attendre, et un service sans `-p` ne publie aucun port :

```exec
docker service create --detach --name layers-l9-drain --replicas 2 nginx:1.30-alpine
sleep 5
docker service ls --filter name=layers-l9-drain
```

Mettez votre nœud en drain. `docker info` donne son identifiant dans le champ `Swarm.NodeID`, que `$(…)` passe à la commande :

```exec
docker node update --availability drain "$(docker info --format '{{.Swarm.NodeID}}')"
sleep 5
docker service ls --filter name=layers-l9-drain
docker service ps layers-l9-drain --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Error}}'
```

Le service affiche `0/2`, et ses tâches restent à `Pending`, avec l'erreur `no suitable node` : Swarm cherche toujours à respecter l'état voulu, mais il ne trouve aucun nœud disponible. C'est la limite honnête d'un swarm d'un seul nœud. Rendez le nœud disponible, et le service repart tout seul :

```exec
docker node update --availability active "$(docker info --format '{{.Swarm.NodeID}}')"
sleep 5
docker service ls --filter name=layers-l9-drain
```

```verify
if [ "$(docker node ls --format '{{.Availability}}' 2>/dev/null | head -n 1)" != "Active" ]; then
  echo "Votre nœud n'est pas disponible. Lancez docker node update --availability active, comme ci-dessus."
  exit 1
fi
for i in 1 2 3 4 5 6; do
  R=$(docker service ls --filter name=layers-l9-drain --format '{{.Replicas}}')
  [ "$R" = "2/2" ] && break
  sleep 2
done
if [ "$R" != "2/2" ]; then
  echo "Le service layers-l9-drain n'a pas 2 répliques (trouvé : ${R:-rien}). Créez-le, s'il n'existe pas, ou patientez."
  exit 1
fi
echo "Le nœud est de nouveau disponible, et le service est reparti."
```

## Nettoyer

Il reste à tout ranger. Supprimez ce dernier service, puis faites sortir votre moteur du swarm. Pour un manager, `docker swarm leave` exige `--force`, car ce geste dissout le cluster : c'est la raison de la vérification faite à la première étape.

```exec
docker service rm layers-l9-drain
docker swarm leave --force
```

Supprimez enfin vos images et votre dossier de travail :

```exec
docker rmi layers-l9-app:1 layers-l9-app:2 layers-l9-app:casse
rm -rf ~/byte-layers/docker/l9
```

Le réseau `docker_gwbridge`, créé par Swarm, reste sur votre machine après son départ. Il ne porte aucun conteneur et ne gêne en rien : Swarm le réutilisera la prochaine fois.

```verify
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "inactive" ]; then
  echo "Votre moteur est encore dans un swarm. Lancez docker swarm leave --force."
  exit 1
fi
left=$(docker images --format '{{.Repository}}' | grep 'layers-l9-app')
if [ -n "$left" ]; then
  echo "Il reste des images : $(echo "$left" | sort -u | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/byte-layers/docker/l9" ]; then
  echo "Le dossier ~/byte-layers/docker/l9 existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Mettre un nœud en drain](https://docs.docker.com/engine/swarm/swarm-tutorial/drain-node/) · [`docker node update`](https://docs.docker.com/reference/cli/docker/node/update/)

## Récap

- Sur plusieurs nœuds, Swarm répartit les tâches, et le drain vide une machine avant sa maintenance.
- Un swarm d'un seul nœud enseigne les bonnes commandes, mais il ne survit pas à la perte de ce nœud.
- `docker swarm leave --force` dissout un swarm dont le moteur est le dernier manager.

Pour vous tester sans guide, faites maintenant le challenge « Un service répliqué, mis à jour et restauré ».

## Questions

```quiz
title: "Le cluster"
tracksProgress: false
showNotice: false
questions:
  - prompt: "À quoi sert `docker node update --availability drain` ?"
    answers:
      - "À supprimer le nœud du cluster"
      - "À vider un nœud de ses tâches, qui repartent sur les autres, avant sa maintenance"
      - "À libérer de l'espace disque"
    correct: 2
    explanation: "Le nœud reste dans le cluster, mais il ne reçoit plus de tâches tant qu'il n'est pas remis à `active`."
  - prompt: "Sur un swarm d'un seul nœud, vous le mettez en drain. Que deviennent les tâches ?"
    answers:
      - "Elles continuent de tourner"
      - "Elles restent à `Pending`, faute de nœud disponible"
      - "Le service est supprimé"
    correct: 2
    explanation: "L'état voulu reste le même, et Swarm attend qu'un nœud soit disponible pour le réaliser."
```
