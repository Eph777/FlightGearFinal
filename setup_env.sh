#!/bin/bash
# FlightGear - Configuration de la base de données

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
print_info "=== Configuration de la base de données ==="
echo ""

read -p "Nom de la base [flightgear] : " DB_NAME
DB_NAME=${DB_NAME:-flightgear}
read -p "Nom d'utilisateur [fguser] : " DB_USER
DB_USER=${DB_USER:-fguser}
read -s -p "Mot de passe [fgpassword123] : " DB_PASS
echo ""
DB_PASS=${DB_PASS:-fgpassword123}

read -p "Port PostgreSQL [5432] : " DB_PORT
DB_PORT=${DB_PORT:-5432}

sudo ufw allow $DB_PORT/tcp

mkdir -p "$INSTALL_DIR/config"
cat > $INSTALL_DIR/config/.env << ENVEOF
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_HOST=localhost
DB_PORT=$DB_PORT
ENVEOF

print_success "Fichier .env créé dans $INSTALL_DIR/config/.env !"
