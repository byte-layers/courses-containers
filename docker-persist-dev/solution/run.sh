#!/usr/bin/env bash
# Rejoue le lab de bout en bout et s'arrête à la première erreur. À lancer depuis le dossier solution/.
set -euo pipefail

WORK="$HOME/byte-layers/docker/l6"
APP="$WORK/app"
cleanup() {
  docker rm -f layers-l6-todo layers-l6-dev layers-l6-db >/dev/null 2>&1 || true
  docker volume rm layers-l6-db-data >/dev/null 2>&1 || true
  docker network rm layers-l6-net >/dev/null 2>&1 || true
  docker rmi layers-l6-todo:1.0 >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

start_db() {
  docker run -d --name layers-l6-db --network layers-l6-net --network-alias mysql \
    -v layers-l6-db-data:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=rootsecret -e MYSQL_DATABASE=todos -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret \
    mysql:8.4 >/dev/null
  until docker exec layers-l6-db mysqladmin ping -h 127.0.0.1 -u todos -psecret --silent >/dev/null 2>&1; do sleep 2; done
}
DB_ENV=(-e MYSQL_HOST=mysql -e MYSQL_USER=todos -e MYSQL_PASSWORD=secret -e MYSQL_DB=todos)

mkdir -p "$APP"
curl -sSL https://github.com/docker/getting-started-app/archive/6b025fc5.tar.gz | tar xz --strip-components=1 -C "$APP"
cp Dockerfile "$APP/Dockerfile"
docker build -q -t layers-l6-todo:1.0 "$APP" >/dev/null
docker network create layers-l6-net >/dev/null
docker volume create layers-l6-db-data >/dev/null
start_db

docker run -d --name layers-l6-todo --network layers-l6-net -p 28362:3000 "${DB_ENV[@]}" layers-l6-todo:1.0 >/dev/null
curl -sS -o /dev/null --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28362/items
curl -sS -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"name":"Apprendre les volumes"}' http://localhost:28362/items

# La base est remplacée, la tâche reste.
docker rm -f layers-l6-db >/dev/null
start_db
curl -s http://localhost:28362/items | grep -q 'Apprendre les volumes'

# Le code est servi depuis votre machine.
docker rm -f layers-l6-todo >/dev/null
docker run -d --name layers-l6-dev --network layers-l6-net -p 28363:3000 "${DB_ENV[@]}" \
  -v "$APP/src:/app/src" layers-l6-todo:1.0 node --watch src/index.js >/dev/null
curl -sS -o /dev/null --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28363/items
echo "app.get('/bonjour', (req, res) => res.send('Bonjour depuis mon poste\n'));" >> "$APP/src/index.js"
curl -sS --retry 10 --retry-delay 1 --retry-all-errors -f http://localhost:28363/bonjour | grep -q 'Bonjour depuis mon poste'

echo "Le lab se déroule comme prévu."
