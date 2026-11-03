#!/usr/bin/env bash
# Rejoue le lab de bout en bout et s'arrête à la première erreur.
set -euo pipefail

NAME=layers-l1-page
URL=http://localhost:28081
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$NAME" -p 28081:80 nginx:1.30-alpine >/dev/null
sleep 1
curl -s "$URL" | grep -q 'Welcome to nginx'
curl -s -o /dev/null "$URL/?moi=1"
docker logs "$NAME" 2>/dev/null | grep -q 'moi=1'

docker exec "$NAME" sh -c 'echo "<h1>Ma page dans un conteneur</h1>" > /usr/share/nginx/html/index.html'
curl -s "$URL" | grep -q 'Ma page dans un conteneur'
docker diff "$NAME" | grep -q index.html

docker stop "$NAME" >/dev/null
docker start "$NAME" >/dev/null
sleep 1
curl -s "$URL" | grep -q 'Ma page dans un conteneur'

docker rm -f "$NAME" >/dev/null
docker run -d --name "$NAME" -p 28081:80 nginx:1.30-alpine >/dev/null
sleep 1
curl -s "$URL" | grep -q 'Welcome to nginx'

echo "Le lab se déroule comme prévu."
