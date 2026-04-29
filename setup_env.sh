#!/bin/bash
# FlightGear - Saisie des credentials de la base de données

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error()   { echo -e "${RED}[ERREUR]${NC} $1"; }

INSTALL_DIR="/root/flightgear"

echo ""
print_info "=== Configuration de la base de données ==="
echo ""

read -p "Nom de la base     [flightgear]    : " DB_NAME
DB_NAME="${DB_NAME:-flightgear}"

read -p "Nom d'utilisateur  [fguser]        : " DB_USER
DB_USER="${DB_USER:-fguser}"

read -s -p "Mot de passe       [fgpassword123] : " DB_PASS
echo ""
DB_PASS="${DB_PASS:-fgpassword123}"

# Vérifier l'absence de caractères interdits pour systemd EnvironmentFile
if printf '%s' "$DB_PASS" | grep -qP '["\\n]'; then
    print_error "Le mot de passe ne doit pas contenir de guillemets (\") ni de sauts de ligne."
    exit 1
fi

mkdir -p "$INSTALL_DIR/config"
chmod 700 "$INSTALL_DIR/config"

# Format compatible bash 'source' ET systemd EnvironmentFile
cat > "$INSTALL_DIR/config/.env" << ENVEOF
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_HOST=localhost
DB_PORT=5432
ENVEOF

chmod 600 "$INSTALL_DIR/config/.env"
print_success "Credentials enregistrés dans $INSTALL_DIR/config/.env (permissions 600)"
echo ""
