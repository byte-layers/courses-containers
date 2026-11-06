---
title: "Préparer les secrets de la base"
description: "Générer le mot de passe, le ranger dans des fichiers, et comprendre comment PostgreSQL et Spring Boot les liront"
---

PetClinic et PostgreSQL doivent partager un mot de passe. Avant d'écrire le fichier Compose, vous le générez et vous le rangez à part. Dans ce chapitre, vous verrez aussi pourquoi une variable d'environnement n'est pas un bon endroit pour un mot de passe, et comment chacun des deux programmes lira le sien.

## Pourquoi un secret plutôt qu'une variable d'environnement

Dans le cas pratique « Deux applications derrière nginx, puis Traefik », le mot de passe de MySQL était écrit dans le fichier Compose, sous `environment`. C'est simple, mais ce mot de passe se retrouve à trois endroits :

- dans le fichier Compose, qui part dans un dépôt Git ;
- dans la configuration du conteneur, que `docker inspect` affiche à quiconque a accès au moteur Docker ;
- dans l'environnement de tous les processus du conteneur, où une page d'erreur ou un outil de diagnostic peut le recopier.

Compose propose une autre voie, les **secrets**. Un secret est un fichier de votre poste que Compose monte, en lecture seule, dans `/run/secrets/` à l'intérieur des seuls conteneurs qui le demandent. Le fichier Compose ne contient que son chemin, et `docker inspect` n'affiche rien de son contenu.

## Comment chaque programme lit son secret

Un secret n'est qu'un fichier, et le programme doit savoir le lire. Les deux services ne le font pas de la même façon :

| Programme | Comment il lit le mot de passe |
|---|---|
| PostgreSQL | l'image officielle suit une convention répandue : toute variable suffixée par `_FILE` donne le **chemin** d'un fichier, dont le contenu remplace la variable. `POSTGRES_PASSWORD_FILE=/run/secrets/db_password` remplace donc `POSTGRES_PASSWORD` |
| PetClinic | Spring Boot ne connaît pas cette convention. Le secret sera donc un petit fichier de configuration, `petclinic-db.properties`, qui contient la ligne `spring.datasource.password=…`, et l'application sera lancée avec l'option `--spring.config.additional-location`, qui lui dit de charger ce fichier en plus de sa configuration |

La seconde technique fonctionne avec n'importe quelle application Spring Boot, y compris une application ancienne que l'on ne peut pas modifier : elle ne demande qu'une option au lancement. Spring Boot propose aussi, depuis sa version 2.4, une lecture native des secrets : avec `spring.config.import=configtree:/run/secrets/`, chaque fichier du dossier devient une propriété qui porte son nom. Les deux approches coexistent, et ce cas pratique utilise la première, plus explicite.

> 📖 [Les secrets dans Compose](https://docs.docker.com/compose/how-tos/use-secrets/) · [Les variables `_FILE` de l'image PostgreSQL](https://hub.docker.com/_/postgres#docker-secrets) · [Les emplacements de configuration de Spring Boot](https://docs.spring.io/spring-boot/reference/features/external-config.html#features.external-config.files)

## Générer le mot de passe et les deux fichiers

Un mot de passe de secret ne se choisit pas : il se génère. `openssl rand -base64 24` tire 24 octets au hasard et les écrit en caractères imprimables, et `tr -d '\n'` retire le retour à la ligne final, qui ferait partie du mot de passe. Le second fichier reprend ce mot de passe dans une ligne de configuration de Spring Boot :

```exec
cd ~/layers-l10/prod/petclinic && mkdir -p secrets
openssl rand -base64 24 | tr -d '\n' > secrets/db_password.txt
printf 'spring.datasource.password=%s\n' "$(cat secrets/db_password.txt)" > secrets/petclinic-db.properties
chmod 700 secrets
ls -la secrets
```

Le dossier `secrets` est réservé à votre utilisateur (`chmod 700`), pour que les autres utilisateurs du poste ne puissent pas le lire. Les deux fichiers, eux, restent lisibles par tous (`-rw-r--r--`). C'est voulu : sans Swarm, Compose monte le fichier tel quel, avec ses droits, et les deux conteneurs le liront avec leurs propres utilisateurs, `postgres` et `nonroot`. Le dossier fermé suffit à protéger les fichiers sur votre poste.

Ces fichiers ne doivent jamais partir dans Git. Le dépôt de PetClinic a déjà un `.gitignore`, et vous y ajoutez le dossier, si la ligne n'y est pas déjà :

```exec
cd ~/layers-l10/prod/petclinic && (grep -qx 'secrets/' .gitignore || echo 'secrets/' >> .gitignore) && tail -1 .gitignore
```

Ils ne partiront pas non plus dans une image : le `.dockerignore` en liste blanche de la partie A n'envoie au moteur que `pom.xml`, `src` et `healthcheck`, et le dossier `secrets/` reste hors du contexte de build.

⚖️ Le mot de passe est maintenant hors du fichier Compose, mais il reste en clair sur le disque du poste. C'est le premier niveau de la gestion des secrets. Sur un serveur, on le complète par un coffre-fort : Ansible Vault chiffre les fichiers dans le dépôt, et HashiCorp Vault ou le gestionnaire de secrets d'un fournisseur cloud les distribue au démarrage.

```verify
P="$HOME/layers-l10/prod/petclinic"
if [ ! -s "$P/secrets/db_password.txt" ] || [ ! -s "$P/secrets/petclinic-db.properties" ]; then
  echo "Les deux fichiers de secrets manquent dans $P/secrets. Relancez le bloc qui les génère."
  exit 1
fi
if [ "$(wc -c < "$P/secrets/db_password.txt")" -lt 20 ]; then
  echo "Le mot de passe est trop court : régénérez-le avec openssl rand -base64 24."
  exit 1
fi
if ! grep -qx "spring.datasource.password=$(cat "$P/secrets/db_password.txt")" "$P/secrets/petclinic-db.properties"; then
  echo "petclinic-db.properties ne contient pas le même mot de passe que db_password.txt. Relancez la ligne printf."
  exit 1
fi
if ! grep -qx 'secrets/' "$P/.gitignore"; then
  echo "Le dossier secrets/ n'est pas dans le .gitignore."
  exit 1
fi
echo "Les secrets sont prêts, et Git les ignorera."
```

````solution
```bash
cd ~/layers-l10/prod/petclinic && mkdir -p secrets
openssl rand -base64 24 | tr -d '\n' > secrets/db_password.txt
printf 'spring.datasource.password=%s\n' "$(cat secrets/db_password.txt)" > secrets/petclinic-db.properties
chmod 700 secrets
grep -qx 'secrets/' .gitignore || echo 'secrets/' >> .gitignore
```
````
