---
title: "Configurer sans modifier le fichier"
description: "Les variables dans le fichier Compose, le fichier .env, et lire ce que Compose a compris"
---

Le port est écrit en dur dans le fichier, et le message dans le code. Or un même fichier doit servir sur votre poste et sur un serveur, avec des réglages différents. Compose sait remplacer des variables dans le fichier au moment de le lire : on appelle cela l'**interpolation**.

## Des variables dans le fichier

Le code lit déjà la variable `GREETING`. Réécrivez le fichier pour que le port et le message viennent de variables :

```exec
cat > ~/layers-l7/counter/compose.yaml <<'EOF'
name: layers-l7-counter
services:
  web:
    build: .
    ports:
      - "${WEB_PORT:-28370}:8000"
    environment:
      REDIS_HOST: cache
      GREETING: ${GREETING:-Bonjour}
  cache:
    image: redis:8-alpine
EOF
```

`${GREETING:-Bonjour}` veut dire : la valeur de la variable `GREETING` si elle existe, sinon `Bonjour`. Sans `:-valeur`, une variable absente devient une chaîne vide, avec un simple avertissement : le fichier se lit alors sans erreur, mais il ne dit pas ce que vous croyez.

Regardez ce que Compose comprend. `docker compose config` affiche le fichier après ce remplacement, et `grep` ne garde que la ligne du message :

```exec
cd ~/layers-l7/counter && docker compose config | grep GREETING
```

Vous devez lire `GREETING: Bonjour`, la valeur par défaut.

## Le fichier .env

Compose lit automatiquement un fichier nommé `.env`, placé à côté du fichier Compose, et s'en sert pour remplacer les variables. Créez-en un :

```exec
printf 'GREETING=Salut\n' > ~/layers-l7/counter/.env
cd ~/layers-l7/counter && docker compose config | grep GREETING
```

La valeur est maintenant `Salut`, sans que `compose.yaml` ait bougé. Appliquez ce changement. Compose voit que la configuration de `web` a changé et recrée ce seul conteneur :

```exec
cd ~/layers-l7/counter && docker compose up -d
sleep 1
curl -s --retry 10 --retry-delay 1 --retry-all-errors http://localhost:28370
```

Vous devez lire `Salut ! Visites : ...`, et le compteur continue : `cache` n'a pas été recréé.

```verify
if ! grep -q '^GREETING=' ~/layers-l7/counter/.env 2>/dev/null; then
  echo "~/layers-l7/counter/.env ne définit pas GREETING. Lancez la commande de cette section."
  exit 1
fi
V=$(docker inspect layers-l7-counter-web-1 --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^GREETING=//p')
F=$(sed -n 's/^GREETING=//p' ~/layers-l7/counter/.env)
if [ "$V" != "$F" ]; then
  echo "Le conteneur a GREETING=$V et le fichier .env dit $F. Lancez docker compose up -d pour appliquer."
  exit 1
fi
echo "Le conteneur a reçu GREETING=$V depuis le fichier .env."
```

## Deux mécanismes à ne pas confondre

Le mot « environnement » désigne ici deux choses différentes, et cette confusion coûte cher au début.

| Mécanisme | Qui s'en sert | À quel moment |
|---|---|---|
| le fichier `.env` et `${VAR}` | **Compose**, pour remplir son fichier | quand il lit le fichier |
| la clé `environment:` | **le programme** dans le conteneur | quand il tourne |

Un fichier `.env` ne donne donc rien au conteneur à lui seul : c'est la ligne `GREETING: ${GREETING:-Bonjour}` qui transmet la valeur. Le prouver prend une commande. Ajoutez au fichier `.env` une variable que `compose.yaml` ne mentionne pas, recréez le conteneur, puis cherchez-la dedans. `>>` ajoute à la fin d'un fichier sans l'effacer, et `grep -E` accepte plusieurs mots séparés par `|` :

```exec
printf 'FORGOTTEN=coucou\n' >> ~/layers-l7/counter/.env
cd ~/layers-l7/counter && docker compose up -d --force-recreate web
cd ~/layers-l7/counter && docker compose exec web env | grep -E 'GREETING|FORGOTTEN'
```

`--force-recreate` recrée le conteneur même si rien n'a changé, et `docker compose exec` lance une commande dans un service qui tourne. Seul `GREETING` apparaît. `FORGOTTEN` est resté du côté de Compose.

Une variable de votre terminal passe avant le fichier `.env`. Écrite devant une commande, `NOM=valeur` ne vaut que pour cette commande. C'est pratique pour un essai ponctuel, comme ici, où `config` lit la valeur sans rien démarrer :

```exec
cd ~/layers-l7/counter && GREETING=Essai docker compose config | grep GREETING
```

```ack
J'ai vu que le fichier .env sert à Compose, et environment au conteneur
```

> ⚠️ Ne versionnez jamais un `.env` qui contient de vrais mots de passe : ajoutez-le à `.gitignore` et fournissez un fichier `.env.example` sans valeurs réelles. Un prochain cours montre où ranger un secret.

> 📖 [L'interpolation](https://docs.docker.com/reference/compose-file/interpolation/) · [Variables d'environnement dans Compose](https://docs.docker.com/compose/how-tos/environment-variables/) · [Ordre de priorité des variables](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/)

## Questions

```quiz
title: "Configurer sans modifier le fichier"
tracksProgress: false
showNotice: false
questions:
  - prompt: "Que vaut `${WEB_PORT:-28370}` si `WEB_PORT` n'est définie nulle part ?"
    answers:
      - "Une chaîne vide"
      - "`28370`"
      - "Une erreur au démarrage"
    correct: 2
    explanation: "`:-` donne une valeur de repli quand la variable est absente ou vide."
  - prompt: "Vous ajoutez `API_KEY=abc` au fichier `.env`, sans toucher à compose.yaml. Le programme du conteneur voit-il cette variable ?"
    answers:
      - "Oui, tout ce qui est dans `.env` entre dans le conteneur"
      - "Non : `.env` sert à Compose ; il faut aussi la transmettre par `environment:`"
      - "Oui, mais seulement après un redémarrage de Docker"
    correct: 2
    explanation: "Vous l'avez constaté avec `FORGOTTEN` : le fichier `.env` remplit le fichier Compose, pas le conteneur."
  - prompt: "Quelle commande montre le fichier Compose après le remplacement des variables, sans rien démarrer ?"
    answers:
      - "`docker compose ps`"
      - "`docker compose config`"
      - "`docker compose logs`"
    correct: 2
    explanation: "`config` est aussi le premier réflexe quand une valeur ne semble pas arriver."
```
