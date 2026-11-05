const express = require('express');
const mysql = require('mysql2');

const app = express();
const port = 3000;

// Les informations de connexion viennent des variables d'environnement
const connection = mysql.createConnection({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

// Une seule tentative au démarrage : sans base, l'application s'arrête
connection.connect(err => {
  if (err) {
    console.error('Connexion à MySQL impossible :', err.message);
    process.exit(1);
  }
  console.log('Connectée à MySQL');
});

// La page d'accueil interroge vraiment la base
app.get('/', (req, res) => {
  connection.query('SELECT VERSION() AS version', (err, rows) => {
    if (err) return res.status(500).send('Erreur MySQL : ' + err.message + '\n');
    res.send('App 1 : connectée à MySQL ' + rows[0].version + '\n');
  });
});

// Une seconde page, pour contrôler le chemin reçu derrière un proxy
app.get('/about', (req, res) => {
  res.send('App 1 : page about, chemin reçu ' + req.originalUrl + '\n');
});

app.listen(port, () => {
  console.log('App 1 écoute sur le port ' + port);
});
