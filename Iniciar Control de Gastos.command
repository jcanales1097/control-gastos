#!/bin/bash
# Doble clic para abrir Control de Gastos con sincronización directa.
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Esta Mac no tiene Python 3."
  echo "Instálalo con: xcode-select --install   (o desde https://www.python.org/downloads/)"
  read -r -p "Presiona Enter para cerrar..."
  exit 1
fi
python3 servidor.py
