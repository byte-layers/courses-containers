# Les solutions du cas pratique PetClinic

Chaque dossier contient les fichiers obtenus à la fin d'un chapitre. Ils sont à regarder en dernier recours, après les indices.

| Dossier | Chapitre | Les fichiers |
|---|---|---|
| `01-naive/` | Lancer PetClinic avec un Dockerfile naïf | le `Dockerfile` naïf, fourni tel quel |
| `02-jar/` | Livrer dans une image durcie le JAR compilé par la CI | le `Dockerfile` d'exécution et son `.dockerignore` |
| `03-multi-stage/` | Construire le JAR dans l'image avec le multi-stage | le `Dockerfile` en deux stages et son `.dockerignore` |
| `04-distroless/` | Passer à une image distroless | le `Dockerfile` distroless, son `.dockerignore` et le healthcheck en Java |
| `05-compose/` | la partie B | le fichier Compose de PetClinic, de PostgreSQL et d'Adminer |
| `06-infra/` | la partie C | le dossier `infra/` complet, et le fichier Compose de PetClinic branché sur Traefik, avec son agent JMX exporter |

Les fichiers de `Dockerfile`, de `.dockerignore` et de `healthcheck/` se placent dans le dossier du code de PetClinic, `~/byte-layers/docker/l10/prod/petclinic`.

Les secrets ne sont pas versionnés. Chaque dossier `secrets/` contient un fichier `.example` qui montre la forme attendue : générez les vrais fichiers avec les commandes `openssl rand` du cas pratique. L'agent JMX exporter n'est pas versionné non plus : téléchargez-le, avec la vérification de son empreinte, comme au chapitre sur les métriques.
