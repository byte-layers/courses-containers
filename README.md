# courses-containers

Les contenus du cluster conteneurs de byte_layers : cœur commun et stack Docker. Un dossier par contenu, à plat.

**Le stack Docker, de L0 à L9, avec les contenus obligatoires de chaque layer.** Le parcours qui les assemble est décrit dans `stacks/docker/stack.yml`. Chaque contenu a son tag, de la forme `<dossier>/vN`, et le stack a le sien, `stacks/docker/vN`.

Prérequis : un terminal, Docker qui répond à `docker ps`. Les objets sont préfixés `layers-lN-` et les fichiers vont dans `~/layers-lN/`, où N est le numéro du layer. Les ports sont `283N0` à `283N9`, sauf L1 qui utilise `28080` à `28082`.

Licence : CC BY-NC-SA 4.0.
