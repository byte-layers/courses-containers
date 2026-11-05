#!/usr/bin/env bash
# Écrit la fiche du poste demandée par la tâche 1, avec les valeurs de ce poste.
set -euo pipefail

mkdir -p ~/layers-l0
{
  echo "client=$(docker version --format '{{.Client.Version}}')"
  echo "moteur=$(docker version --format '{{.Server.Version}}')"
  echo "architecture=$(docker version --format '{{.Server.Arch}}')"
} > ~/layers-l0/audit.txt
cat ~/layers-l0/audit.txt
