---
title: "Plusieurs applications derrière un reverse proxy"
description: "Avec des blancs à compléter : une seule porte d'entrée, deux projets Compose indépendants derrière elle, reliés par un réseau partagé."
tags:
  - lab
  - docker
  - containers
difficulty: beginner
duration: 75
introTitle: "Présentation"
requires: "0.4.0"
options:
  allowManualProgress: false
  autoCompleteOnNext: unverifiable
---

Sur un serveur, vous ne voulez pas un port par application, à retenir et à ouvrir un par un. Vous voulez **une seule porte d'entrée**, qui oriente chaque demande vers la bonne application selon son adresse. C'est le rôle d'un **reverse proxy**.

Vous allez organiser deux applications comme sur un vrai serveur : un dossier et un projet Compose pour chacune, et un troisième projet pour le reverse proxy. Ce lab vous guide moins que les précédents : il explique, puis vous laisse compléter les `# TODO`, et vers la fin écrire un fichier entier. Le bouton de vérification contrôle le résultat, et la solution reste en dernier recours.

**Niveau** : vous savez écrire un fichier Compose avec des services, des volumes et des réseaux, comme dans « Décrire une application avec Compose ». Vous savez qu'un conteneur joint un autre par son nom sur un réseau partagé, comme dans « Relier des conteneurs et publier un port ». Vous n'avez pas besoin de connaître nginx : ce qu'il en faut est expliqué ici.

**Ce qu'il faut** : Docker et Compose qui répondent, `curl`, un éditeur de texte et le port **28380** libre. Tout ce que vous créez porte le préfixe `layers-l8-`, et vos fichiers vivent dans `~/byte-layers/docker/l8/proxy`.

**Si un téléchargement échoue avec `429 Too Many Requests`** : Docker Hub limite les téléchargements anonymes par adresse IP. Attendez, ou créez un compte gratuit sur Docker Hub et lancez `docker login`.

# Le plan

## Ce que vous allez construire

Voici l'organisation visée. Une demande entre par le port 28380, et le proxy choisit l'application d'après le début de l'adresse :

```
                 port 28380             réseau partagé layers-l8-edge
                                 ┌────────────────────────────────────┐
navigateur, curl ───────────────►│  proxy ──── /app1/ ────► app1      │
                                 │        └─── /app2/ ────► app2      │
                                 └────────────────────────────────────┘
```

Trois choix expliquent ce schéma :

- **Seul le proxy publie un port.** Les applications ne sont joignables que par lui : c'est le seul endroit à surveiller et à protéger.
- **Un projet Compose par application.** Vous pouvez mettre à jour ou arrêter l'une sans toucher aux autres, et ajouter une application sans modifier les fichiers des autres.
- **Un réseau partagé entre les projets.** Par défaut, chaque projet a son propre réseau, isolé des autres. Le proxy doit pourtant joindre les applications : le projet du proxy crée donc un réseau que les autres viennent rejoindre.

## Pourquoi nginx ?

Plusieurs outils font ce travail. Ce lab utilise nginx, parce que sa configuration se lit, et qu'on voit donc exactement ce qu'un reverse proxy fait.

| Outil | Son principe | Quand on le préfère |
|---|---|---|
| **nginx** | un fichier de configuration, écrit à la main | très répandu, très performant, rien de caché |
| **Traefik** | il lit l'état de Docker et s'y configure seul, à partir d'étiquettes, les *labels*, posées sur les conteneurs ; il lui faut donc un accès au socket de Docker, le fichier par lequel on commande le moteur, ce qui est un droit fort | beaucoup d'applications qui vont et viennent |
| **Caddy** | une configuration très courte, et HTTPS automatique | un petit serveur, simple à tenir |
| **HAProxy** | spécialisé dans la répartition de charge | de gros volumes, de la répartition fine |

⚖️ Ce lab reste en HTTP. Le HTTPS demande un vrai nom de domaine et un certificat, que votre poste n'a pas. Sur un serveur, c'est au reverse proxy de le porter, et il n'y a rien à changer dans les applications.

## Préparer le dossier

Vous allez créer un dossier par projet. Sur un serveur, on trouverait la même organisation, par exemple sous `/srv/docker`.

```exec
mkdir -p ~/byte-layers/docker/l8/proxy/edge/conf.d ~/byte-layers/docker/l8/proxy/app1/html ~/byte-layers/docker/l8/proxy/app2/conf.d
```

```ack
J'ai compris le plan, et le dossier est prêt
```

# Le proxy

## Une première configuration

nginx lit tous les fichiers `.conf` du dossier `/etc/nginx/conf.d`. Pour l'instant, le vôtre ne fait que répondre. Un bloc `server` décrit un site, `listen` donne le port, et un bloc `location` dit quoi faire pour les adresses qui commencent ainsi. `/` les prend donc toutes. `return` répond directement, sans appeler personne. `cat > fichier <<'EOF'` écrit dans le fichier tout ce qui suit, jusqu'à la ligne `EOF` :

```exec
cat > ~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;

    location / {
        return 200 "Porte d'entrée\n";
    }
}
EOF
```

`absolute_redirect off` évite un piège : quand nginx redirige `/app1` vers `/app1/`, il écrirait sinon une adresse complète avec son port interne, 80, au lieu de votre port 28380.

## Le fichier Compose du proxy

Créez le fichier de départ, puis complétez ses trois blancs dans votre éditeur :

```exec
cat > ~/byte-layers/docker/l8/proxy/edge/compose.yaml <<'EOF'
name: layers-l8-edge
services:
  proxy:
    image: nginx:1.30-alpine
    # TODO : publier le port 28380 de la machine vers le port 80 du conteneur
    # TODO : monter le dossier ./conf.d sur /etc/nginx/conf.d, en lecture seule
    networks:
      - edge
networks:
  edge:
    # TODO : donner à ce réseau le nom réel layers-l8-edge
EOF
```

Ce tableau donne les deux clés qui servent à remplir ces blancs, en plus de `ports`, que vous connaissez :

| Clé | Rôle |
|---|---|
| `volumes` | avec `./conf.d:/etc/nginx/conf.d:ro`, un bind mount : le dossier de votre machine apparaît dans le conteneur, et `:ro` le rend lisible seulement |
| `name`, dans un réseau | le nom réel du réseau. Sans lui, Compose le préfixe par celui du projet, `layers-l8-edge_edge`, ce qui est peu pratique à partager |

On monte le **dossier** et non le seul fichier : beaucoup d'éditeurs remplacent un fichier en l'enregistrant, et le conteneur, resté attaché à l'ancien, ne verrait jamais vos modifications.

Démarrez le proxy et interrogez-le. `--retry` patiente pendant son démarrage :

```exec
cd ~/byte-layers/docker/l8/proxy/edge && docker compose up -d
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28380
```

Vous devez lire `Porte d'entrée`.

```hint
Le bind mount s'écrit comme un volume : la clé `volumes:` et une ligne `- ./conf.d:/etc/nginx/conf.d:ro`, au même décalage que `networks:`.
```

```hint
Sous `edge:`, décalez de deux espaces de plus et écrivez `name: layers-l8-edge`.
```

```verify
P=layers-l8-edge-proxy-1
if [ "$(docker inspect $P --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$P ne tourne pas. Complétez ~/byte-layers/docker/l8/proxy/edge/compose.yaml, puis lancez docker compose up -d depuis ce dossier."
  exit 1
fi
if ! docker network inspect layers-l8-edge >/dev/null 2>&1; then
  echo "Le réseau layers-l8-edge n'existe pas : il manque son nom réel, name: layers-l8-edge. Faites docker compose down, puis relancez."
  exit 1
fi
case "$(docker port $P 80/tcp 2>/dev/null)" in
  *:28380*) : ;;
  *) echo "Le port 28380 de la machine ne mène pas au port 80 du proxy."; exit 1 ;;
esac
RW=$(docker inspect $P --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{.Type}} {{.RW}}{{end}}{{end}}')
if [ "$RW" != "bind false" ]; then
  echo "Le dossier conf.d n'est pas monté en lecture seule sur /etc/nginx/conf.d (trouvé : ${RW:-rien})."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28380 | grep -q "Porte d'entrée"; then
  echo "Le proxy ne répond pas « Porte d'entrée » sur le port 28380. Lisez : docker compose logs proxy"
  exit 1
fi
echo "La porte d'entrée répond, et le réseau partagé existe."
```

````solution
```bash
cd ~/byte-layers/docker/l8/proxy/edge && docker compose down
cat > ~/byte-layers/docker/l8/proxy/edge/compose.yaml <<'EOF'
name: layers-l8-edge
services:
  proxy:
    image: nginx:1.30-alpine
    ports:
      - "28380:80"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
    networks:
      - edge
networks:
  edge:
    name: layers-l8-edge
EOF
cd ~/byte-layers/docker/l8/proxy/edge && docker compose up -d
sleep 1
```
````

# La première application

## Un site statique dans son propre projet

`app1` est un site statique : une page, et une image qui la copie dans nginx. Ce second nginx n'a rien à voir avec le proxy : c'est un programme de plus, qui sert ici de site web.

```exec
echo '<h1>App 1 : un site statique</h1>' > ~/byte-layers/docker/l8/proxy/app1/html/index.html
cat > ~/byte-layers/docker/l8/proxy/app1/Dockerfile <<'EOF'
FROM nginx:1.30-alpine
COPY html/ /usr/share/nginx/html/
EOF
```

Le fichier Compose de ce projet doit **rejoindre** le réseau du proxy, sans le créer. C'est la clé `external` qui le dit : `external: true` veut dire que ce réseau existe déjà, créé ailleurs, et que ce projet ne s'occupera ni de le créer ni de le supprimer.

Le nom du service compte, car il sert d'adresse sur le réseau partagé. Sur ce réseau, deux projets qui appelleraient tous deux leur service `web` répondraient au même nom. Donnez donc à chaque application un nom qui lui soit propre : `app1`, et non `web`.

```exec
cat > ~/byte-layers/docker/l8/proxy/app1/compose.yaml <<'EOF'
name: layers-l8-app1
services:
  app1:
    build: .
    # TODO : placer ce service sur le réseau edge. Et aucun port publié.
networks:
  edge:
    # TODO : le nom réel du réseau partagé
    # TODO : dire qu'il existe déjà
EOF
```

Complétez ce fichier, lancez-le, puis vérifiez depuis le proxy que l'application est joignable par son nom. `wget -qO-` affiche une page sans rien écrire d'autre, et il est présent dans l'image, contrairement à `curl` :

```exec
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose up -d --build
cd ~/byte-layers/docker/l8/proxy/edge && docker compose exec proxy wget -qO- http://app1/
```

Vous devez lire le titre de la page. Depuis votre machine, en revanche, `app1` n'a aucun port : seul le proxy pourra l'appeler.

```hint
Le service utilise le réseau sous son nom local, `edge`. Dans la section `networks:` du bas, deux clés sont à ajouter sous ce nom : `name` et `external`.
```

```verify
A=layers-l8-app1-app1-1
if [ "$(docker inspect $A --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$A ne tourne pas. Complétez ~/byte-layers/docker/l8/proxy/app1/compose.yaml, puis lancez docker compose up -d --build depuis ce dossier."
  exit 1
fi
if [ -n "$(docker port $A)" ]; then
  echo "app1 publie un port. Seul le proxy doit le faire : retirez sa clé ports."
  exit 1
fi
case " $(docker inspect $A --format '{{range $n, $x := .NetworkSettings.Networks}}{{$n}} {{end}}')" in
  *" layers-l8-edge "*) : ;;
  *) echo "app1 n'est pas sur le réseau layers-l8-edge. Vérifiez name et external dans son fichier."; exit 1 ;;
esac
if [ "$(docker network inspect layers-l8-edge --format '{{index .Labels "com.docker.compose.project"}}')" != "layers-l8-edge" ]; then
  echo "Le réseau layers-l8-edge n'appartient pas au projet du proxy : c'est ce projet-là qui doit le créer."
  exit 1
fi
if ! docker exec layers-l8-edge-proxy-1 wget -qO- http://app1/ 2>/dev/null | grep -q 'App 1'; then
  echo "Le proxy ne joint pas http://app1/. Le service doit s'appeler app1, et le proxy doit tourner."
  exit 1
fi
echo "app1 est joignable par le proxy, et ne publie rien."
```

````solution
```bash
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose down
cat > ~/byte-layers/docker/l8/proxy/app1/compose.yaml <<'EOF'
name: layers-l8-app1
services:
  app1:
    build: .
    networks:
      - edge
networks:
  edge:
    name: layers-l8-edge
    external: true
EOF
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose up -d --build
sleep 1
```
````

## Ouvrir la route

Il reste à dire au proxy d'orienter `/app1/` vers cette application. C'est `proxy_pass`, qui transmet la demande à une autre adresse et renvoie sa réponse.

La barre oblique à la fin de `proxy_pass http://app1/` compte. Avec elle, nginx remplace le début de l'adresse, `/app1/`, par `/` : `app1` reçoit donc `/index.html` et non `/app1/index.html`, qu'il ne connaît pas. On dit qu'il **retire le préfixe**.

Remplacez le contenu de `~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf` dans votre éditeur par ce qui suit, en complétant le blanc :

```nginx
server {
    listen 80;
    absolute_redirect off;

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /app1/ {
        # TODO : transmettre à http://app1/, en retirant le préfixe
    }
}
```

nginx ne relit pas sa configuration tout seul. `nginx -t` vérifie le fichier sans rien changer, et il vaut mieux le lancer avant `nginx -s reload`, qui applique la configuration sans interrompre le service. Comme le dossier est monté, vous n'avez pas à recréer le conteneur :

```exec
cd ~/byte-layers/docker/l8/proxy/edge && docker compose exec proxy sh -c 'nginx -t && nginx -s reload'
```

Demandez ensuite la page par la porte d'entrée :

```exec
sleep 1
curl -s --max-time 5 http://localhost:28380/app1/
```

Vous devez lire le titre de `app1`, obtenu par la porte d'entrée. Un `404 Not Found` veut dire que le préfixe n'a pas été retiré : vérifiez la barre oblique finale.

```hint
Une seule ligne manque, terminée par un point-virgule, comme toutes les lignes d'une configuration nginx : `proxy_pass http://app1/;`
```

```verify
if ! curl -s --max-time 5 http://localhost:28380/app1/ | grep -q 'App 1'; then
  echo "http://localhost:28380/app1/ ne renvoie pas la page de app1."
  echo "Vérifiez la configuration avec : cd ~/byte-layers/docker/l8/proxy/edge && docker compose exec proxy nginx -t"
  echo "Puis appliquez-la avec nginx -s reload."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28380/ | grep -q "Porte d'entrée"; then
  echo "L'adresse / ne répond plus « Porte d'entrée » : gardez ce bloc location."
  exit 1
fi
echo "La porte d'entrée oriente /app1/ vers app1."
```

````solution
```bash
cat > ~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /app1/ {
        proxy_pass http://app1/;
    }
}
EOF
docker exec layers-l8-edge-proxy-1 nginx -s reload
sleep 1
```
````

# La panne à connaître

## La provoquer

Votre proxy marche, tant que tout est allumé. Essayez maintenant ce qui arrive sur un serveur qui redémarre : les conteneurs ne reviennent pas dans un ordre garanti. Arrêtez `app1`, relancez le proxy avec `docker compose restart`, qui arrête puis redémarre les conteneurs sans les recréer, et regardez son état :

```exec
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose down
cd ~/byte-layers/docker/l8/proxy/edge && docker compose restart
sleep 2
cd ~/byte-layers/docker/l8/proxy/edge && docker compose ps -a --format '{{.Service}} : {{.Status}}'
cd ~/byte-layers/docker/l8/proxy/edge && docker compose logs proxy --tail 1
```

Le proxy est `Exited (1)`. Une seule application absente, et **toutes** tombent, puisque la porte d'entrée est fermée. Pas d'inquiétude, voici la cause et le remède.

- **Symptôme** : le message `host not found in upstream "app1"` apparaît, et le proxy s'arrête.
- **Cause** : nginx résout les noms écrits dans `proxy_pass` **une seule fois, à son démarrage**. Si `app1` n'existe pas à ce moment-là, il refuse de démarrer. Et s'il démarre, il garde l'adresse IP trouvée, même si `app1` en change plus tard.
- **Correctif** : lui demander de résoudre le nom **à chaque demande**.

## La corriger

Quatre directives y suffisent : `resolver` une fois dans le bloc `server`, et les trois autres pour chaque application, dans cet ordre. Le **DNS** est le service qui traduit un nom en adresse IP.

| Directive | Rôle |
|---|---|
| `resolver 127.0.0.11 valid=5s;` | l'adresse du DNS interne de Docker, présent dans tout réseau créé par l'utilisateur ; une réponse reste valable 5 secondes |
| `set $upstream http://app1;` | met l'adresse dans une **variable** : nginx ne résoudra plus le nom au démarrage, mais à chaque demande |
| `rewrite ^/app1/(.*)$ /$1 break;` | retire le préfixe, car une variable dans `proxy_pass` désactive le retrait automatique de la section précédente ; `(.*)` capture la suite de l'adresse, `$1` la réutilise, et `break` dit de s'arrêter là |
| `proxy_pass $upstream;` | transmet à l'adresse contenue dans la variable |

Comme `app1` est à présent absent, vous verrez une erreur `502 Bad Gateway`, qui concerne cette application et elle seule, au lieu d'une porte fermée pour tout le monde. Remplacez le contenu de `~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf` dans votre éditeur, en complétant les blancs :

```nginx
server {
    listen 80;
    absolute_redirect off;
    # TODO : le DNS interne de Docker, valable 5 secondes

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /app1/ {
        # TODO : mettre http://app1 dans la variable $upstream
        # TODO : retirer le préfixe /app1/
        # TODO : transmettre à cette variable
    }
}
```

Le proxy est arrêté, donc il ne s'agit pas d'un rechargement : redémarrez-le, sans que `app1` soit là, et demandez la page :

```exec
cd ~/byte-layers/docker/l8/proxy/edge && docker compose up -d
sleep 2
curl -s --max-time 5 http://localhost:28380/
curl -s --max-time 5 -o /dev/null -w 'app1 absente, code HTTP : %{http_code}\n' http://localhost:28380/app1/
```

La porte répond, et `/app1/` donne le code `502`. Rallumez `app1`, sans toucher au proxy :

```exec
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose up -d
sleep 6
curl -s --max-time 5 http://localhost:28380/app1/
```

La page revient toute seule. C'est ce que vous cherchiez : les applications peuvent aller et venir.

```hint
Dans le bloc `location /app1/`, recopiez les trois dernières lignes du tableau, dans l'ordre : le `set`, le `rewrite`, le `proxy_pass`. N'oubliez pas les points-virgules.
```

```verify
P=layers-l8-edge-proxy-1
if [ "$(docker inspect $P --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "Le proxy ne tourne pas. Lisez : docker compose logs proxy, depuis ~/byte-layers/docker/l8/proxy/edge."
  exit 1
fi
CONF=$(docker exec $P nginx -T 2>/dev/null)
if ! echo "$CONF" | grep -Eq '(^|[[:space:];{])resolver[[:space:]]+127\.0\.0\.11'; then
  echo "La configuration active n'a pas de resolver vers 127.0.0.11."
  exit 1
fi
if ! echo "$CONF" | grep -Eq '(^|[[:space:];{])proxy_pass[[:space:]]+(http://)?\$'; then
  echo "proxy_pass n'utilise pas de variable : nginx résout encore le nom à son démarrage."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28380/app1/ | grep -q 'App 1'; then
  echo "http://localhost:28380/app1/ ne renvoie pas la page de app1. Un 404 : le préfixe n'est pas retiré. Un 502 : app1 n'est pas lancée."
  exit 1
fi
echo "Le proxy résout les noms à chaque demande, et ne dépend plus de l'ordre de démarrage."
```

````solution
```bash
cat > ~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;
    resolver 127.0.0.11 valid=5s;

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /app1/ {
        set $upstream http://app1;
        rewrite ^/app1/(.*)$ /$1 break;
        proxy_pass $upstream;
    }
}
EOF
cd ~/byte-layers/docker/l8/proxy/edge && docker compose up -d
docker exec layers-l8-edge-proxy-1 nginx -s reload
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose up -d
sleep 6
```
````

# La seconde application

## À vous, avec moins d'aide

Vous avez été guidé pas à pas jusqu'ici. La seconde application suit le même schéma : vous écrivez cette fois le fichier en entier.

`app2` n'a rien à construire : c'est un nginx qui affiche simplement ce qu'il reçoit, ce qui permet de voir ce qu'un reverse proxy transmet. Voici sa configuration, à déposer dans son dossier :

```exec
cat > ~/byte-layers/docker/l8/proxy/app2/conf.d/default.conf <<'EOF'
server {
    listen 80;
    default_type text/plain;
    location / {
        return 200 "App 2 : ce que je reçois\nHost: $host\nX-Real-IP: $http_x_real_ip\nX-Forwarded-For: $http_x_forwarded_for\nX-Forwarded-Proto: $http_x_forwarded_proto\nURI: $request_uri\n";
    }
}
EOF
```

**Objectif 1.** Écrivez `~/byte-layers/docker/l8/proxy/app2/compose.yaml`, sur le modèle de `app1` : le projet s'appelle `layers-l8-app2`, le service `app2`, avec l'image `nginx:1.30-alpine`, le dossier `./conf.d` monté en lecture seule sur `/etc/nginx/conf.d`, le réseau partagé, et aucun port publié.

**Objectif 2.** Ajoutez dans la configuration du proxy un bloc `location /app2/`, sur le modèle de celui de `app1`.

**Objectif 3.** Faites savoir à `app2` ce qui s'est passé avant lui. Vue de l'application, chaque demande vient du proxy, et non du visiteur. Pour que l'adresse de celui-ci et le nom du site demandé ne se perdent pas, un proxy les transmet dans des **en-têtes**, ces lignes de texte qui accompagnent une demande HTTP. `proxy_set_header` en pose un. Ajoutez ces quatre lignes au bloc de `app2`, avant le `proxy_pass` :

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

Voici ce que porte chacun de ces en-têtes :

| En-tête | Ce qu'il transmet |
|---|---|
| `Host` | le nom de site demandé par le visiteur ; sans cette ligne, `app2` lirait son propre nom |
| `X-Real-IP` | l'adresse du visiteur |
| `X-Forwarded-For` | la liste des adresses traversées, à laquelle le proxy ajoute celle du visiteur |
| `X-Forwarded-Proto` | `http` ou `https`, tel que vu par le proxy |

Lancez `app2` et appliquez la configuration :

```exec
cd ~/byte-layers/docker/l8/proxy/app2 && docker compose up -d
cd ~/byte-layers/docker/l8/proxy/edge && docker compose exec proxy nginx -s reload
```

Testez maintenant avec un nom de site inventé. `-H` ajoute un en-tête à la demande, et aucun DNS n'est nécessaire, puisque `curl` s'adresse à `localhost` :

```exec
sleep 1
curl -s --max-time 5 -H 'Host: demo.example.com' http://localhost:28380/app2/une-page
```

Vous devez lire `Host: demo.example.com`, des adresses IP dans `X-Real-IP` et `X-Forwarded-For`, et `URI: /une-page`, sans le préfixe `/app2`.

```hint
Le fichier de `app2` ressemble à celui de `app1`, avec `image:` au lieu de `build:`, et une clé `volumes:` comme celle du proxy.
```

```hint
Le bloc `location /app2/` reprend les trois lignes de celui de `app1`, en remplaçant `app1` par `app2` sur la ligne `set` et sur la ligne `rewrite`.
```

```verify
A=layers-l8-app2-app2-1
if [ "$(docker inspect $A --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "$A ne tourne pas. Écrivez ~/byte-layers/docker/l8/proxy/app2/compose.yaml, puis lancez docker compose up -d depuis ce dossier."
  exit 1
fi
if [ -n "$(docker port $A)" ]; then
  echo "app2 publie un port. Seul le proxy doit le faire."
  exit 1
fi
RW=$(docker inspect $A --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{.Type}} {{.RW}}{{end}}{{end}}')
if [ "$RW" != "bind false" ]; then
  echo "Le dossier conf.d de app2 n'est pas monté en lecture seule sur /etc/nginx/conf.d (trouvé : ${RW:-rien})."
  exit 1
fi
OUT=$(curl -s --max-time 5 -H 'Host: controle.example.com' http://localhost:28380/app2/controle)
case "$OUT" in
  *"App 2"*) : ;;
  *) echo "/app2/ ne renvoie pas la réponse de app2. Vérifiez le bloc location, puis appliquez avec nginx -s reload."; exit 1 ;;
esac
case "$OUT" in
  *"URI: /controle"*) : ;;
  *) echo "app2 reçoit encore le préfixe : il manque le rewrite du bloc /app2/."; exit 1 ;;
esac
case "$OUT" in
  *"Host: controle.example.com"*) : ;;
  *) echo "app2 ne reçoit pas le nom de site demandé : il manque proxy_set_header Host."; exit 1 ;;
esac
for H in X-Real-IP X-Forwarded-For; do
  if ! echo "$OUT" | grep -Eq "^$H: [0-9a-f.:]+"; then
    echo "app2 ne reçoit pas l'en-tête $H."
    exit 1
  fi
done
if ! echo "$OUT" | grep -q '^X-Forwarded-Proto: http'; then
  echo "app2 ne reçoit pas l'en-tête X-Forwarded-Proto."
  exit 1
fi
if ! curl -s --max-time 5 http://localhost:28380/app1/ | grep -q 'App 1'; then
  echo "/app1/ ne répond plus : les deux routes doivent coexister."
  exit 1
fi
echo "Deux applications, une seule porte, et app2 sait qui demande quoi."
```

````solution
La solution complète se trouve aussi dans le dossier `solution/` de ce contenu.

```bash
cat > ~/byte-layers/docker/l8/proxy/app2/compose.yaml <<'EOF'
name: layers-l8-app2
services:
  app2:
    image: nginx:1.30-alpine
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
    networks:
      - edge
networks:
  edge:
    name: layers-l8-edge
    external: true
EOF
cat > ~/byte-layers/docker/l8/proxy/edge/conf.d/default.conf <<'EOF'
server {
    listen 80;
    absolute_redirect off;
    resolver 127.0.0.11 valid=5s;

    location / {
        return 200 "Porte d'entrée\n";
    }

    location /app1/ {
        set $upstream http://app1;
        rewrite ^/app1/(.*)$ /$1 break;
        proxy_pass $upstream;
    }

    location /app2/ {
        set $upstream http://app2;
        rewrite ^/app2/(.*)$ /$1 break;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass $upstream;
    }
}
EOF
cd ~/byte-layers/docker/l8/proxy/app2 && docker compose up -d
docker exec layers-l8-edge-proxy-1 nginx -s reload
sleep 2
```
````

⚖️ Une limite à connaître : avec un préfixe, une application qui écrit dans ses pages un lien absolu, comme `/style.css`, le demandera à la racine du site, où elle n'est plus. Router par nom de site, avec un bloc `server` par nom et `server_name`, évite ce problème, mais demande un nom DNS, ce que ce lab n'a pas.

# Nettoyer

## Dans le bon ordre

Supprimez ce que ce lab a créé : les conteneurs, l'image construite, le réseau partagé et le dossier `~/byte-layers/docker/l8/proxy` doivent disparaître. L'ordre compte : Compose refuse de supprimer un réseau encore utilisé, et le réseau appartient au projet du proxy. Les applications partent donc d'abord, et le proxy en dernier. `--rmi local` supprime l'image construite, et `cd ~` vous fait sortir du dossier avant de l'effacer.

```verify
if [ -n "$(docker ps -a --format '{{.Names}}' | grep -E '^layers-l8-(edge|app1|app2)-')" ]; then
  echo "Il reste des conteneurs : $(docker ps -a --format '{{.Names}}' | grep -E '^layers-l8-(edge|app1|app2)-' | tr '\n' ' ')"
  exit 1
fi
if docker network inspect layers-l8-edge >/dev/null 2>&1; then
  echo "Le réseau layers-l8-edge existe encore. Lancez docker compose down depuis ~/byte-layers/docker/l8/proxy/edge, après les deux applications."
  exit 1
fi
if docker image inspect layers-l8-app1-app1 >/dev/null 2>&1; then
  echo "L'image layers-l8-app1-app1 existe encore. Supprimez-la avec docker rmi."
  exit 1
fi
if [ -e "$HOME/byte-layers/docker/l8/proxy" ]; then
  echo "Le dossier ~/byte-layers/docker/l8/proxy existe encore."
  exit 1
fi
echo "C'est propre."
```

````solution
```bash
cd ~/byte-layers/docker/l8/proxy/app1 && docker compose down --rmi local
cd ~/byte-layers/docker/l8/proxy/app2 && docker compose down
cd ~/byte-layers/docker/l8/proxy/edge && docker compose down
cd ~ && rm -rf ~/byte-layers/docker/l8/proxy
```
````

## Récap

- Un reverse proxy est la seule porte d'entrée : il publie un port, et les applications n'en publient aucun.
- Chaque application a son projet Compose, et un réseau partagé les relie : le projet du proxy le crée, et les autres le rejoignent avec `external: true`.
- nginx résout un nom écrit en dur à son démarrage seulement : le `resolver` et une variable dans `proxy_pass` lui font résoudre le nom à chaque demande.
- Les en-têtes `X-Forwarded-*` transmettent à l'application ce que le proxy a vu du visiteur.

Tous les fichiers se trouvent dans le dossier [`solution/`](../solution/) de ce contenu.

> 📖 [Les réseaux externes dans Compose](https://docs.docker.com/reference/compose-file/networks/#external) · [`proxy_pass` de nginx](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass) · [`resolver` de nginx](https://nginx.org/en/docs/http/ngx_http_core_module.html#resolver) · [Le DNS de Docker](https://docs.docker.com/engine/network/#dns-services) · [Traefik et Docker](https://doc.traefik.io/traefik/providers/docker/)

Pour vous tester sans guide : le challenge « Une stack prête pour la production ».
