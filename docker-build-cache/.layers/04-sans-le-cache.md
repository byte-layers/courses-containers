---
title: "Se passer du cache, ou le garder autrement"
description: "--no-cache, --pull, et un cache de téléchargements"
---

Le cache a une limite : il ne sait pas ce qui se passe à l'extérieur. Cette dernière étape vous dit quand s'en méfier, et comment garder les téléchargements même quand une installation doit être rejouée.

## Le cache ne voit pas le monde extérieur

Pour `RUN`, Docker ne regarde que le texte de la commande. `RUN pip install flask` reste donc en cache, même si une nouvelle version de Flask corrige une faille de sécurité. L'image de base obéit à la même logique : tant que `python:3.13-alpine` est présente sur votre machine, Docker ne vérifie pas forcément qu'il en existe une plus récente sous ce tag. Deux options répondent à ce besoin.

| Option de `docker build` | Effet | Quand l'utiliser |
|---|---|---|
| `--pull` | vérifie sur le registre s'il existe une version plus récente de l'image de base | pour une construction destinée à être livrée |
| `--no-cache` | rejoue toutes les instructions | pour récupérer des mises à jour, ou en cas de doute sur le cache |

Essayez la seconde sur votre projet, en regardant la durée :

```exec
time docker build --no-cache -t layers-l3-cache:4.0 ~/layers-l3/cache
```

L'installation est rejouée, et Flask se télécharge à nouveau. Seul `WORKDIR` peut encore porter le mot `CACHED`, car il ne fait que créer un dossier vide. Sur un vrai projet, il vaut mieux réserver ce mode aux builds de livraison, et garder le cache au quotidien.

## Garder les téléchargements

Quand vous ajoutez une dépendance, `pip` retélécharge tout, y compris ce qu'il avait déjà récupéré. Une option de `RUN` permet de lui garder un dossier d'un build à l'autre : c'est un **cache mount**. Réécrivez le Dockerfile avec cette option :

```exec
cat > ~/layers-l3/cache/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
COPY . .
RUN python -m compileall -q .
CMD ["flask", "run", "--host", "0.0.0.0"]
EOF
docker build -t layers-l3-cache:4.1 ~/layers-l3/cache
```

Voici ce que dit chaque morceau de cette option.

| Élément | Rôle |
|---|---|
| `--mount=type=cache` | monte un dossier que Docker conserve entre deux builds, sans le mettre dans l'image |
| `target=/root/.cache/pip` | l'endroit où ce dossier apparaît pendant le `RUN`, ici celui où `pip` garde ses téléchargements |

Ajoutez une dépendance et reconstruisez. `--progress=plain` affiche la sortie de `pip`, `2>&1` envoie les messages de Docker dans le tube `|`, le premier `grep` n'en garde que les lignes `Using cached` et `Downloading`, et `grep -v metadata` retire celles qui parlent des fiches de description, pour ne laisser que les bibliothèques elles-mêmes :

```exec
echo 'pyyaml==6.0.*' >> ~/layers-l3/cache/requirements.txt
docker build --progress=plain -t layers-l3-cache:4.2 ~/layers-l3/cache 2>&1 | grep -E 'Using cached|Downloading' | grep -v metadata
```

Les bibliothèques déjà récupérées affichent `Using cached`, et seule la nouvelle, `pyyaml`, affiche `Downloading`. L'étape a été rejouée, mais elle n'a pas tout repris à zéro. Si vous refaites ce cours, cette étape peut déjà être en cache, et la commande n'affiche alors rien.

```verify
SRC="$HOME/layers-l3/cache"
if ! grep -q 'type=cache' "$SRC/Dockerfile" 2>/dev/null; then
  echo "Le Dockerfile de ~/layers-l3/cache ne monte pas de cache sur son RUN pip install."
  exit 1
fi
TMP=$(mktemp -d)
cp -R "$SRC/." "$TMP/"
echo "# essai $(date +%s)" >> "$TMP/requirements.txt"
docker build -q -t layers-l3-cache:essai "$TMP" >/dev/null 2>&1
echo "# essai $(date +%s) bis" >> "$TMP/requirements.txt"
OUT=$(docker build --progress=plain -t layers-l3-cache:essai2 "$TMP" 2>&1)
RC=$?
docker image rm layers-l3-cache:essai layers-l3-cache:essai2 >/dev/null 2>&1
rm -rf "$TMP"
if [ "$RC" -ne 0 ]; then
  echo "Le build a échoué. Relancez-le à la main pour lire l'erreur."
  exit 1
fi
if ! printf '%s\n' "$OUT" | grep -q 'Using cached'; then
  echo "pip n'a rien retrouvé dans son cache. Vérifiez le chemin target=/root/.cache/pip."
  exit 1
fi
echo "pip retrouve ses téléchargements, même quand l'installation est rejouée."
```

⚖️ Ce cache vit sur la machine qui construit. Un serveur qui construit vos images et repart de zéro à chaque fois ne le retrouve pas. `--cache-from` permet à un tel serveur de réutiliser les couches d'une image déjà publiée, mais pas le contenu d'un cache mount : la documentation liée plus bas détaille ces cas.

## Où vit le cache

Supprimer une image ne vide pas le cache de build, ce qui explique qu'un build reste rapide après un `docker image rm`. `docker system df` montre la place qu'il occupe, sur la ligne `Build Cache` :

```exec
docker system df
```

Il existe une commande pour le vider, `docker builder prune`. Elle touche à tous vos projets : ne la lancez qu'en connaissance de cause, et ce cours n'en a pas besoin.

## Nettoyer

Supprimez ce que ce cours a créé, images et dossier. Le conteneur est déjà parti. Une boucle `for` répète `docker image rm` pour chaque tag de la liste :

```exec
for t in 1.0 1.1 2.0 2.1 2.2 3.0 3.1 3.2 3.3 4.0 4.1 4.2; do docker image rm layers-l3-cache:$t; done
rm -rf ~/layers-l3/cache
```

```verify
left=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^layers-l3-cache:')
if [ -n "$left" ]; then
  echo "Il reste ces images : $(echo "$left" | tr '\n' ' ')"
  exit 1
fi
if [ -e "$HOME/layers-l3/cache" ]; then
  echo "Le dossier ~/layers-l3/cache existe encore."
  exit 1
fi
echo "C'est propre."
```

> 📖 [`docker build`](https://docs.docker.com/reference/cli/docker/build/) · [Optimiser l'usage du cache](https://docs.docker.com/build/cache/optimize/) · [`RUN --mount`](https://docs.docker.com/reference/dockerfile/#run---mount)

## Ce qu'il faut retenir

- Docker réutilise une instruction si elle n'a pas changé et si tout ce qui la précède est resté en cache. Une instruction rejouée entraîne toutes les suivantes.
- `RUN` se compare sur son texte, et `COPY` sur le contenu des fichiers.
- On place ce qui change rarement en haut : d'abord le fichier de dépendances et l'installation, ensuite le code.
- `.dockerignore` empêche un fichier inutile de faire sauter le cache.
- Le cache ne voit pas le monde extérieur : `--pull` et `--no-cache` servent aux builds de livraison.

Pour vous tester sans guide : le challenge « Réduire et accélérer une image existante ».

## Questions

```quiz
title: "Se passer du cache"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Une faille est corrigée dans une bibliothèque. Votre `RUN pip install` est `CACHED` et votre `requirements.txt` n'a pas changé. Comment récupérer la correction ?"
    answers:
      - "Relancer `docker build`, Docker le détecte"
      - "Construire avec `--no-cache`, car `RUN` ne regarde que le texte de la commande"
      - "Supprimer le conteneur"
    correct: 2
    explanation: "Docker ne regarde pas ce qui se passe sur le réseau. Il vaut d'ailleurs mieux épingler les versions pour décider soi-même de ces mises à jour."
  - prompt: "Que contient l'image finale après un `RUN --mount=type=cache,target=/root/.cache/pip pip install …` ?"
    answers:
      - "Les bibliothèques installées et le cache de téléchargement"
      - "Les bibliothèques installées, sans le cache de téléchargement"
      - "Ni l'un ni l'autre"
    correct: 2
    explanation: "Le dossier monté n'existe que pendant le `RUN`, et il n'entre pas dans la couche."
```
