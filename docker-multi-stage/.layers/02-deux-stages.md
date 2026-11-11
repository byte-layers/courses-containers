---
title: "Deux stages : construire, puis livrer"
description: "AS, COPY --from et l'image finale"
---

Un Dockerfile peut contenir plusieurs `FROM`. Chacun ouvre un **stage**, une construction séparée, avec sa propre image de base et ses propres couches. L'image produite est le **dernier** stage, et lui seul : ce qui reste dans les stages précédents est tout simplement laissé de côté. C'est le **multi-stage**.

## Écrire le second stage

Le premier stage garde le compilateur et produit le binaire. Le second repart d'une petite image et n'y copie que ce binaire :

```exec
cat > ~/byte-layers/docker/l3/multi/Dockerfile <<'EOF'
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
RUN go build -o /hello .

FROM alpine:3.22
COPY --from=build /hello /hello
CMD ["/hello"]
EOF
```

Deux éléments sont nouveaux dans ce fichier, et ce tableau les explique.

| Élément | Rôle |
|---|---|
| `AS build` | donne un nom à ce stage. `build` est un nom libre, et c'est le nom habituel |
| `COPY --from=build /hello /hello` | copie un fichier **depuis le stage `build`**, et non depuis votre contexte |

La séparation se lit bien dans ce schéma, où seule la colonne de droite part avec l'image :

```
stage build                         stage final, l'image livrée
┌──────────────────────────┐        ┌─────────────────────┐
│ compilateur Go           │        │ alpine:3.22         │
│ code source              │        │                     │
│ /hello ──────────────────┼───────>│ /hello              │
└──────────────────────────┘        └─────────────────────┘
```

Construisez sous un autre tag, puis comparez :

```exec
docker build -t layers-l3-multi:alpine ~/byte-layers/docker/l3/multi
docker images layers-l3-multi
```

La version `alpine` pèse autour de 16 Mo ou 25 Mo selon le poste, soit une vingtaine de fois moins. Vérifiez qu'elle fonctionne :

```exec
docker run -d --name layers-l3-multi -p 28331:8080 layers-l3-multi:alpine
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28331
```

Vous devez lire la même phrase que tout à l'heure : pour l'application, rien n'a changé.

Cette fois, le compilateur n'est plus là. `docker exec` lance `which`, qui cherche un programme et ne dit rien s'il ne le trouve pas, puis `ls` regarde le dossier du code :

```exec
docker exec layers-l3-multi which go
docker exec layers-l3-multi ls /src
```

La première commande n'affiche rien, et la seconde répond que le dossier n'existe pas.

```verify
I=layers-l3-multi:alpine
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Relancez le docker build."
  exit 1
fi
if docker run --rm "$I" which go >/dev/null 2>&1; then
  echo "Le compilateur est encore dans $I : l'image doit venir du second stage."
  exit 1
fi
if docker run --rm "$I" test -e /src; then
  echo "Le code source est encore dans $I."
  exit 1
fi
A=$(docker image inspect layers-l3-multi:lourd --format '{{.Size}}' 2>/dev/null)
B=$(docker image inspect "$I" --format '{{.Size}}')
if [ -z "$A" ] || [ "$((B * 5))" -gt "$A" ]; then
  echo "L'image $I devrait peser au moins cinq fois moins que layers-l3-multi:lourd (trouvé : $B et ${A:-aucune} octets)."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28331 | grep -q 'Bonjour depuis Go'; then
  echo "Le port 28331 ne répond pas. Vérifiez avec : docker ps -a --filter name=layers-l3-multi"
  exit 1
fi
echo "L'image finale est légère, et l'application répond toujours."
```

Supprimez ce conteneur, car l'étape suivante en crée un autre :

```exec
docker rm -f layers-l3-multi
```

## Et pour les autres langages ?

Le geste ne se limite pas à Go, car beaucoup de projets ont une phase de construction. Le gain dépend de ce que l'exécution demande encore, et ce tableau donne trois cas courants.

| Application | Stage de construction | Image finale | Gain |
|---|---|---|---|
| Go, Rust | le compilateur | une image minimale et le binaire | très grand |
| Site statique, React, Angular | Node.js et `npm run build` | `nginx:1.30-alpine` et les fichiers produits | très grand |
| Node.js, Python | installer les dépendances, avec un compilateur si besoin | la même base, le code et les dépendances | plus modeste : il faut garder l'interpréteur |

> 📖 [Les builds multi-stage](https://docs.docker.com/build/building/multi-stage/) · [Bien utiliser le multi-stage](https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/)

## Questions

```quiz
title: "Deux stages"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Un Dockerfile a trois `FROM`. Sans option particulière, que contient l'image produite ?"
    answers:
      - "Les trois stages, empilés"
      - "Le dernier stage, et ce qu'il a copié des autres"
      - "Le premier stage"
    correct: 2
    explanation: "Seul le dernier stage devient l'image. Il ne garde des autres que ce qu'il copie explicitement."
  - prompt: "Que veut dire `COPY --from=build /hello /hello` ?"
    answers:
      - "Copier le fichier `/hello` du stage nommé `build` vers l'image en cours"
      - "Télécharger une image nommée `build`"
      - "Copier `/hello` de votre machine, puis le renommer"
    correct: 1
    explanation: "`--from` change l'origine de la copie : un stage, au lieu du contexte de build."
```
