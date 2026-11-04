#!/usr/bin/env bash
# Rejoue le lab de bout en bout et s'arrête à la première erreur. À lancer depuis le dossier solution/.
set -euo pipefail

WORK="$HOME/layers-l5"
URL=http://localhost:28355
cleanup() {
  docker rm -f -v layers-l5-todo layers-l5-db >/dev/null 2>&1 || true
  docker network rm layers-l5-net >/dev/null 2>&1 || true
  docker rmi layers-l5-todo:1.0 >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

start_db() {
  docker run -d --name layers-l5-db --network layers-l5-net --network-alias mysql \
    -e MYSQL_ROOT_PASSWORD=rootsecret -e MYSQL_DATABASE=todos -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret \
    mysql:8.4 >/dev/null
  until docker exec layers-l5-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent >/dev/null 2>&1; do sleep 2; done
}

mkdir -p "$WORK/app"
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C "$WORK/app"
cp Dockerfile "$WORK/app/Dockerfile"
docker build -q -t layers-l5-todo:1.0 "$WORK/app" >/dev/null

docker network create layers-l5-net >/dev/null
start_db

docker run -d --name layers-l5-todo --network layers-l5-net -p 28355:3000 \
  -e MYSQL_HOST=mysql -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret -e MYSQL_DB=todos \
  layers-l5-todo:1.0 >/dev/null
curl -sS -o /dev/null --retry 10 --retry-delay 1 --retry-all-errors "$URL/items"
curl -sS -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"name":"Acheter du pain"}' "$URL/items"
curl -s "$URL/items" | grep -q 'Acheter du pain'
docker exec layers-l5-db mysql -u todos -psecret todos -e 'SELECT name FROM todo_items' 2>/dev/null | grep -q 'Acheter du pain'

# Sans volume nommé, les données partent avec la base.
docker rm -f -v layers-l5-db >/dev/null
start_db
docker restart layers-l5-todo >/dev/null
curl -sS -o /dev/null --retry 10 --retry-delay 1 --retry-all-errors "$URL/items"
[ "$(curl -s "$URL/items")" = "[]" ]

echo "Le lab se déroule comme prévu."
