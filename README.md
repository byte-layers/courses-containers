# courses-containers

Les contenus du cluster conteneurs de byte_layers : cœur commun et stack Docker. Un dossier par contenu, à plat.

**Pilote : le premier layer du stack Docker.** Ces contenus ne sont pas encore au catalogue de byte_layers. Chacun a son tag, de la forme `<dossier>/vN`.

| Contenu | Type | Sujet |
|---|---|---|
| `image-immutable` | bit | l'image est immuable, le conteneur en est une instance |
| `container-is-a-process` | bit | un conteneur est un processus isolé |
| `docker-run` | skill | lancer, configurer et observer un conteneur |
| `docker-first-web-page` | lab | héberger une page dans un conteneur |
| `docker-run-challenge` | challenge | la preuve du layer, sans guide |

Prérequis : un terminal, Docker qui répond à `docker ps`. Images : `alpine:3.22`, `nginx:1.30-alpine`. Objets préfixés
`layers-l1-`, ports `28080` à `28082`.

Licence : CC BY-NC-SA 4.0.
