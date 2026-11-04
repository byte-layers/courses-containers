---
title: "Le problème : on livre l'atelier"
description: "Une image qui contient de quoi se construire"
---

Pour fabriquer un meuble, il faut un atelier, mais on ne livre pas l'atelier avec le meuble. Une image construite d'un seul tenant fait pourtant exactement cela : les outils qui ont servi à la fabriquer restent dedans. Cette étape mesure ce que cela coûte.

## Une application compilée

Votre application est écrite en Go, un langage **compilé** : un programme, le compilateur, traduit le code source en un seul fichier exécutable, appelé **binaire**. Une fois le binaire produit, ni le compilateur ni le code ne sont utiles pour le lancer. Créez le projet :

```exec
mkdir -p ~/layers-l3/multi
cat > ~/layers-l3/multi/main.go <<'EOF'
package main

import (
    "fmt"
    "net/http"
)

func message() string {
    return "Bonjour depuis Go"
}

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, message())
    })
    http.ListenAndServe(":8080", nil)
}
EOF
```

Ce programme écoute sur le port 8080 et répond une phrase. Un projet Go se décrit aussi dans un petit fichier, `go.mod`, qui lui donne un nom et indique sa version de Go :

```exec
printf 'module example.com/hello\n\ngo 1.24\n' > ~/layers-l3/multi/go.mod
```

## Le Dockerfile d'un seul tenant

Ce Dockerfile part de l'image officielle de Go, qui contient le compilateur. `go build -o /hello .` compile le dossier courant et écrit le binaire dans `/hello` :

```exec
cat > ~/layers-l3/multi/Dockerfile <<'EOF'
FROM golang:1.24-alpine
WORKDIR /src
COPY . .
RUN go build -o /hello .
CMD ["/hello"]
EOF
docker build -t layers-l3-multi:lourd ~/layers-l3/multi
```

Lancez cette image pour vérifier qu'elle fonctionne. Le port 28331 mène au port 8080 du conteneur :

```exec
docker run -d --name layers-l3-multi -p 28331:8080 layers-l3-multi:lourd
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28331
```

Vous devez lire `Bonjour depuis Go`. L'application marche, il reste à regarder ce que vous livrez.

```verify
if ! curl -s --max-time 5 http://localhost:28331 | grep -q 'Bonjour depuis Go'; then
  echo "Le port 28331 ne répond pas. Vérifiez avec : docker ps -a --filter name=layers-l3-multi"
  exit 1
fi
if [ "$(docker inspect layers-l3-multi --format '{{.Config.Image}}' 2>/dev/null)" != "layers-l3-multi:lourd" ]; then
  echo "Le conteneur layers-l3-multi doit venir de l'image layers-l3-multi:lourd."
  exit 1
fi
echo "L'application répond."
```

## Ce que contient l'image

`docker images` donne le poids de l'image, et ce conteneur peut aussi vous dire ce qu'il transporte :

```exec
docker images layers-l3-multi
docker exec layers-l3-multi go version
docker exec layers-l3-multi ls /src
```

L'image pèse plusieurs centaines de mégaoctets, pour un binaire d'une dizaine. Le compilateur répond, et votre code source est présent. Docker Desktop et un moteur Linux classique ne comptent pas les tailles de la même façon : la même image y affiche 507 Mo et 350 Mo. Ce tableau résume ce que ce poids coûte.

| Coût | Raison |
|---|---|
| Du temps | chaque machine qui récupère l'image télécharge le compilateur |
| De la surface d'attaque | un attaquant qui entre dans le conteneur trouve des outils pour compiler ce qu'il veut, et chaque outil peut avoir ses failles |
| Du code exposé | quiconque récupère l'image lit votre code source |

Supprimer ces outils dans un `RUN` suivant ne servirait à rien, car ils resteraient dans une couche du dessous. Il faut une autre approche, et c'est l'objet de l'étape suivante.

Ce conteneur n'est plus utile, supprimez-le :

```exec
docker rm -f layers-l3-multi
```

> 📖 [Les builds multi-stage](https://docs.docker.com/build/building/multi-stage/)

## Questions

```quiz
title: "Le problème"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Une fois le binaire compilé, à quoi sert encore le compilateur dans l'image ?"
    answers:
      - "À lancer le binaire"
      - "À rien : il alourdit l'image et élargit sa surface d'attaque"
      - "À accélérer le démarrage du conteneur"
    correct: 2
    explanation: "Un binaire compilé s'exécute seul. Le compilateur n'a servi qu'à le produire."
  - prompt: "Pourquoi ne pas simplement ajouter `RUN rm -rf /usr/local/go` à la fin du Dockerfile ?"
    answers:
      - "Parce que `rm` n'existe pas dans l'image"
      - "Parce que les fichiers restent dans la couche du dessous : l'image ne maigrit pas"
      - "Parce que Docker refuse cette commande"
    correct: 2
    explanation: "Une couche ne se modifie jamais. Une suppression ne fait que masquer ce qui se trouve dessous."
```
