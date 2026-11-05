---
title: "Faire le ménage et retenir l'essentiel de la partie A"
description: "Supprimer les images devenues inutiles, voir où BuildKit garde les images de base, et le récap de la partie"
---

Vous avez construit quatre images pour les comparer, et vous n'en garderez qu'une. Ce court chapitre libère l'espace disque, puis résume ce que la partie A vous a appris.

## Supprimer les images intermédiaires

La partie B utilisera l'image `4-distroless`, et les trois autres n'ont plus d'utilité. Sur un poste partagé, il vaut mieux libérer cet espace dès maintenant :

```exec
docker rm -f layers-l10-petclinic
docker rmi layers-l10-petclinic:1-naive layers-l10-petclinic:2-jar layers-l10-petclinic:3-multistage
docker image prune -f
```

`docker image prune -f` supprime en plus les images **orphelines** (*dangling*), celles qui n'ont plus de nom : chaque reconstruction de `3-multistage` a laissé l'ancienne version sans nom.

La simulation de la CI a laissé deux choses dont vous n'avez plus besoin, puisque le multi-stage compile maintenant dans l'image : l'image Maven lancée avec `docker run`, environ 540 Mo, et le dossier `~/layers-l10/m2` de ses dépendances, environ 200 Mo. Supprimez-les aussi :

```exec
docker rmi maven:3.9.16-eclipse-temurin-21-noble
rm -rf ~/layers-l10/m2
```

Vous ne trouverez pas, en revanche, les images `maven` ou `eclipse-temurin` des `FROM` dans `docker images`. Le moteur de construction, **BuildKit**, les garde dans son propre **cache de construction**, avec les couches des stages `build` et leurs dépendances Maven. `docker system df` affiche sa taille à la ligne `Build Cache`, près d'un gigaoctet :

```exec
docker system df
```

Gardez ce cache pour l'instant : il évitera à la partie B de tout retélécharger. À la fin du cas pratique, `docker builder prune -f` le videra.

```verify
for T in 1-naive 2-jar 3-multistage; do
  if docker image inspect layers-l10-petclinic:$T >/dev/null 2>&1; then
    echo "L'image layers-l10-petclinic:$T existe encore. Supprimez-la avec docker rmi."
    exit 1
  fi
done
if ! docker image inspect layers-l10-petclinic:4-distroless >/dev/null 2>&1; then
  echo "L'image layers-l10-petclinic:4-distroless a disparu : la partie B en a besoin. Reconstruisez-la depuis ~/layers-l10/prod/petclinic."
  exit 1
fi
echo "Il ne reste que l'image distroless, celle de la suite."
```

````solution
```bash
docker rm -f layers-l10-petclinic 2>/dev/null
docker rmi layers-l10-petclinic:1-naive layers-l10-petclinic:2-jar layers-l10-petclinic:3-multistage
docker image prune -f
docker rmi maven:3.9.16-eclipse-temurin-21-noble
rm -rf ~/layers-l10/m2
```
````

## Récap de la partie A

- Une version d'image précise, `21.0.13_9-jre-noble` plutôt que `latest`, rend la construction reproductible. Une empreinte `sha256` le garantit, et elle s'impose quand l'image n'a pas de tag de version.
- Un utilisateur sans droits, un healthcheck et un `ENTRYPOINT` en forme exec corrigent trois défauts que l'on ne voit pas tant que tout va bien.
- L'ordre des instructions décide du cache : `pom.xml` d'abord, le code ensuite, et ce qui change le plus en dernier. Un `.dockerignore` en liste blanche limite le contexte de build à ce que le `Dockerfile` copie vraiment.
- Le multi-stage sépare la construction de l'exécution dans un même `Dockerfile`. En Java, le JAR fourni par la CI reste le cas le plus courant.
- Une image distroless retire le shell et le gestionnaire de paquets. Elle oblige à écrire autrement ce qui en dépendait, comme le healthcheck.
