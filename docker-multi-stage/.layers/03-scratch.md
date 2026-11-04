---
title: "Partir de rien : scratch"
description: "Un binaire autonome, et ce qu'on perd sans shell"
---

Votre image contient encore un système Alpine, dont le binaire ne se sert presque pas. Un binaire peut être **autonome**, sans aucune dépendance, et dans ce cas il n'a besoin de rien d'autre pour tourner. Docker fournit pour cela une image de base spéciale, `scratch`, qui est entièrement vide.

## Construire un binaire autonome

`scratch` ne contient aucune bibliothèque système, et le binaire doit donc les embarquer. En Go, cela passe par `CGO_ENABLED=0`, une variable qui interdit au compilateur d'utiliser des bibliothèques externes. Écrite devant la commande, elle ne vaut que pour celle-ci :

```exec
cat > ~/layers-l3/multi/Dockerfile <<'EOF'
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /hello .

FROM scratch
COPY --from=build /hello /hello
CMD ["/hello"]
EOF
docker build -t layers-l3-multi:scratch ~/layers-l3/multi
docker images layers-l3-multi
```

La version `scratch` pèse le poids du binaire, une dizaine de mégaoctets. Il n'y a rien d'autre dans l'image. Lancez-la :

```exec
docker run -d --name layers-l3-multi -p 28331:8080 layers-l3-multi:scratch
curl -s --retry 5 --retry-delay 1 --retry-all-errors http://localhost:28331
```

L'application répond toujours.

```verify
I=layers-l3-multi:scratch
if ! docker image inspect "$I" >/dev/null 2>&1; then
  echo "L'image $I n'existe pas. Relancez le docker build."
  exit 1
fi
if docker run --rm "$I" /bin/sh -c true >/dev/null 2>&1; then
  echo "L'image $I contient un shell : elle ne part pas de scratch."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28331 | grep -q 'Bonjour depuis Go'; then
  echo "Le port 28331 ne répond pas. Vérifiez avec : docker ps -a --filter name=layers-l3-multi"
  exit 1
fi
if [ "$(docker inspect layers-l3-multi --format '{{.Config.Image}}' 2>/dev/null)" != "$I" ]; then
  echo "Le conteneur layers-l3-multi doit venir de l'image $I."
  exit 1
fi
echo "Votre image ne contient que le binaire, et il répond."
```

## Ce qu'on perd

Sans système, il n'y a plus d'outils. Essayez d'ouvrir un shell dans ce conteneur :

```exec
docker exec layers-l3-multi sh
```

Docker répond `executable file not found`, car le conteneur n'a ni `sh`, ni `ls`, ni rien d'autre. Cela le rend plus difficile à attaquer, mais aussi plus difficile à examiner. `docker logs` et `docker inspect` restent disponibles, car ils fonctionnent depuis l'extérieur.

Il y a une conséquence directe sur le Dockerfile : la forme shell de `CMD` a besoin de `/bin/sh`. Essayez sur un Dockerfile à part, écrit dans un fichier que `-f` désigne :

```exec
printf 'FROM scratch\nCOPY hello.txt /\nCMD cat /hello.txt\n' > ~/layers-l3/multi/Dockerfile.shell
echo salut > ~/layers-l3/multi/hello.txt
docker build -q -f ~/layers-l3/multi/Dockerfile.shell -t layers-l3-multi:shell ~/layers-l3/multi
docker run --rm layers-l3-multi:shell
```

Le conteneur ne démarre pas, et le message contient `exec: "/bin/sh": stat /bin/sh: no such file or directory`. Avec `scratch`, on écrit donc toujours la forme exec.

Supprimez ces essais, ainsi que le conteneur :

```exec
docker rm -f layers-l3-multi
docker image rm layers-l3-multi:shell
rm ~/layers-l3/multi/Dockerfile.shell ~/layers-l3/multi/hello.txt
```

## Quelle image finale choisir ?

Il n'y a pas de meilleure réponse pour tous les cas. Il vaut mieux partir de ce tableau et de vos besoins, en gardant à l'esprit que certains binaires ne peuvent pas être rendus autonomes.

| Image finale | Poids | Quand la préférer |
|---|---|---|
| `alpine:3.22` | quelques mégaoctets de plus | quand on veut garder un shell pour examiner un conteneur, ou quand le binaire a besoin de fichiers du système |
| `scratch` | le binaire seul | pour un binaire autonome, quand la surface d'attaque compte le plus |

⚖️ `scratch` a un piège classique : il ne contient pas non plus les certificats qui permettent de vérifier une connexion HTTPS, ni les fuseaux horaires. Un programme qui appelle une API en HTTPS échoue tant que vous ne les copiez pas depuis le stage de construction.

⚖️ Pour rester centrée sur le poids, cette image tourne en `root`. Une vraie image ajouterait `USER`, avec un identifiant numérique comme `USER 1000`, puisque `scratch` n'a aucune liste d'utilisateurs.

> 📖 [Partir de `scratch`](https://docs.docker.com/build/building/base-images/#create-a-minimal-base-image-using-scratch) · [Les builds multi-stage](https://docs.docker.com/build/building/multi-stage/)

## Questions

```quiz
title: "Partir de rien"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Pourquoi `CMD /hello` échoue-t-il sur une image `scratch`, alors que `CMD [\"/hello\"]` fonctionne ?"
    answers:
      - "Parce que la forme shell passe par `/bin/sh`, absent de cette image"
      - "Parce que `scratch` interdit l'instruction `CMD`"
      - "Parce que le binaire n'est pas au bon endroit"
    correct: 1
    explanation: "La forme shell lance `/bin/sh -c`, et `scratch` ne contient rien. La forme exec lance directement le binaire."
  - prompt: "Comment lire ce que fait un conteneur issu de `scratch`, sans shell à l'intérieur ?"
    answers:
      - "C'est impossible"
      - "Avec `docker logs` et `docker inspect`, qui fonctionnent depuis l'extérieur"
      - "Avec `docker exec ls`"
    correct: 2
    explanation: "`docker exec` a besoin d'un programme dans le conteneur. `docker logs` et `docker inspect` passent par Docker."
```
