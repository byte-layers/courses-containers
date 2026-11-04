#!/usr/bin/env bash
# Rejoue le lab de bout en bout à partir des fichiers de ce dossier, et s'arrête à la première erreur.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
NAME=layers-l2-todo
IMAGE=layers-l2-todo:solution
URL=http://localhost:28321
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; docker image rm "$IMAGE" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C "$WORK"
cp "$HERE/Dockerfile" "$HERE/.dockerignore" "$WORK/"
echo 'SESSION_SECRET=fictif' > "$WORK/.env"

docker build -q -t "$IMAGE" "$WORK" >/dev/null
[ "$(docker run --rm "$IMAGE" id -un)" = "node" ]
! docker run --rm "$IMAGE" ls -A | grep -qx '.env'

docker run -d --name "$NAME" -p 28321:3000 "$IMAGE" >/dev/null
curl -s --retry 5 --retry-delay 1 --retry-all-errors "$URL" | grep -q 'Todo App'
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"Essai"}' "$URL/items" >/dev/null
curl -s "$URL/items" | grep -q 'Essai'

echo "Le lab se déroule comme prévu."
