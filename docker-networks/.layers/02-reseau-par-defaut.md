---
title: "Le réseau par défaut"
description: "Les réseaux existants, le bridge, et ce qui manque au réseau par défaut"
---

Publier un port relie l'hôte à un conteneur. Des conteneurs qui doivent se parler entre eux ne passent pas par là : ils ont besoin d'un **réseau** commun. Avant d'en créer un, regardez ce que Docker fournit d'office, car c'est sur ce réseau que vous avez travaillé jusqu'ici sans le savoir.

## Les réseaux existants

`docker network ls` liste les réseaux que connaît Docker. La colonne `DRIVER`, le **pilote**, dit de quel type est chacun :

```exec
docker network ls
```

Vous lisez au moins ces trois réseaux, livrés avec Docker, et peut-être d'autres selon votre machine :

| Réseau | Pilote | Ce qu'il fait |
|---|---|---|
| `bridge` | `bridge` | le réseau par défaut : un commutateur virtuel, comme une petite prise réseau partagée, sur lequel se branchent les conteneurs |
| `host` | `host` | supprime l'isolation réseau : le conteneur partage directement la pile de l'hôte |
| `none` | `null` | aucun réseau : le conteneur n'a que son localhost |

Ce cours ne travaille qu'avec le pilote `bridge`, celui dont vous aurez presque toujours besoin sur une seule machine.

## Deux conteneurs sur le réseau par défaut

Sans option `--network`, un conteneur rejoint le réseau `bridge` et y reçoit une adresse IP. Lancez deux conteneurs qui attendent, puis affichez leur adresse. `{{range .NetworkSettings.Networks}}` parcourt les réseaux du conteneur, et `{{.IPAddress}}` lit l'adresse sur chacun :

```exec
docker run -d --name layers-l5-a alpine:3.22 sleep 3600
docker run -d --name layers-l5-b alpine:3.22 sleep 3600
docker inspect layers-l5-a layers-l5-b --format '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Chacun a son adresse, le plus souvent en `172.17.x.x`. Le `/` devant les noms est une habitude d'affichage de Docker. Demandez au premier de joindre le second par cette adresse. `ping` envoie un petit message à une adresse et attend la réponse, et `-c 1` limite l'envoi à un seul message. Le `$(…)` lit l'adresse du second conteneur et la place dans la commande :

```exec
docker exec layers-l5-a ping -c 1 "$(docker inspect layers-l5-b --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
```

Vous lisez `1 packets received` : le réseau fonctionne, les deux conteneurs se voient.

```verify
for C in layers-l5-a layers-l5-b; do
  if [ "$(docker inspect "$C" --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
    echo "$C ne tourne pas. Supprimez-le s'il existe (docker rm -f $C), puis relancez la commande de cette section."
    exit 1
  fi
  if [ "$(docker inspect "$C" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}}{{end}}')" != "bridge" ]; then
    echo "$C n'est pas sur le réseau par défaut bridge. Recréez-le sans option --network."
    exit 1
  fi
done
echo "layers-l5-a et layers-l5-b sont sur le réseau par défaut."
```

## Ce qui manque : les noms

Une adresse IP est un mauvais moyen de désigner un conteneur : elle lui est attribuée au démarrage et peut changer quand il est recréé. On voudrait utiliser son nom. Essayez donc :

```exec
docker exec layers-l5-a ping -c 1 layers-l5-b
```

Vous lisez `bad address 'layers-l5-b'`. L'échec est normal : **le réseau par défaut ne résout pas les noms**. Résoudre un nom, c'est trouver l'adresse IP qui lui correspond. D'anciens tutoriels contournent le problème avec l'option `--link`, désormais déconseillée : la bonne réponse est un réseau que vous créez vous-même, à l'étape suivante.

Supprimez ces deux conteneurs :

```exec
docker rm -f layers-l5-a layers-l5-b
```

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l5-(a|b)$')" ]; then
  echo "Il reste des conteneurs. Lancez le docker rm -f ci-dessus."
  exit 1
fi
echo "C'est propre."
```

> 📖 [Le réseau dans Docker](https://docs.docker.com/engine/network/) · [Le pilote bridge](https://docs.docker.com/engine/network/drivers/bridge/)

## Questions

```quiz
title: "Le réseau par défaut"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Sur quel réseau arrive un conteneur lancé sans `--network` ?"
    answers:
      - "`host`"
      - "`bridge`"
      - "`none`"
    correct: 2
    explanation: "`bridge` est le réseau par défaut. `host` et `none` existent, mais il faut les demander."
  - prompt: "Sur le réseau par défaut, `ping layers-l5-b` répond `bad address`, alors que le ping par adresse IP marche. Pourquoi ?"
    answers:
      - "Le conteneur `layers-l5-b` est arrêté"
      - "Ce réseau ne résout pas les noms de conteneurs"
      - "Le nom d'un conteneur ne peut pas contenir de tiret"
    correct: 2
    explanation: "Le réseau fonctionne, la preuve par l'adresse IP. Il manque seulement la résolution de noms, que seuls les réseaux créés par vous apportent."
  - prompt: "Pourquoi éviter de noter l'adresse IP d'un conteneur dans la configuration d'un autre ?"
    answers:
      - "Une adresse IP de conteneur n'est pas routable"
      - "Elle est attribuée au démarrage et peut changer quand le conteneur est recréé"
      - "Docker interdit les adresses IP dans les variables d'environnement"
    correct: 2
    explanation: "Un conteneur se remplace facilement, et son adresse peut changer avec lui. Un nom reste valable."
```
