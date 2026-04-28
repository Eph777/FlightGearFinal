#!/bin/bash
# FlightGear Multiplayer Tracker - Installation Script

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Config
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER=$(whoami)
FGMS_PORT=5000
FGMS_TELNET_PORT=5001

echo ""
print_info "=== FlightGear Multiplayer Tracker - Installation ==="
echo ""
print_warning "Ce script va :"
echo "  1. Configurer la base de données"
echo "  2. Mettre à jour le système"
echo "  3. Installer PostgreSQL et les dépendances"
echo "  4. Compiler et installer FGMS"
echo "  5. Configurer la base de données"
echo "  6. Configurer le pare-feu"
echo "  7. Créer les services systemd"
echo ""
read -p "Continuer ? (o/n) : " CONFIRM
[[ "$CONFIRM" != "o" ]] && exit 0

# Créer le .env
bash "$(dirname "$0")/setup_env.sh"

# Charger les variables depuis le .env
source $INSTALL_DIR/config/.env

# Étape 1 : Mise à jour
print_info "Étape 1/6 : Mise à jour du système..."
sudo apt update && sudo apt upgrade -y
print_success "Système mis à jour !"

# Étape 2 : Dépendances
print_info "Étape 2/6 : Installation des dépendances..."
sudo apt install -y git cmake build-essential postgresql python3-pip python3-venv ufw curl
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt


print_success "Dépendances installées !"

# Étape 3 : Compilation FGMS
print_info "Étape 3/6 : Compilation de FGMS..."
if command -v fgms &> /dev/null; then
    print_warning "FGMS déjà installé : $(fgms --version 2>&1 | grep version)"
    read -p "Réinstaller FGMS ? (o/n) : " REINSTALL_FGMS
    if [[ "$REINSTALL_FGMS" = "o" ]]; then
        cd $HOME
        rm -rf fgms
        git clone https://github.com/FlightGear/fgms.git
        cd fgms && mkdir -p build && cd build
        cmake .. && make
        sudo make install
        print_success "FGMS réinstallé !"
    else
        print_info "FGMS ignoré."
    fi
else
    cd $HOME
    if [ ! -d "fgms" ]; then
        git clone https://github.com/FlightGear/fgms.git
    fi
    cd fgms && mkdir -p build && cd build
    cmake .. && make
    sudo make install
    print_success "FGMS installé ! Version : $(fgms --version 2>&1 | grep version)"
fi

# Étape 4 : Configuration PostgreSQL
print_info "Étape 4/6 : Configuration PostgreSQL..."

sudo service postgresql start 2>/dev/null || sudo systemctl start postgresql 2>/dev/null || true

PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;' 2>/dev/null)
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;' 2>/dev/null)

[ -f "${PG_HBA}.backup" ] || sudo cp "$PG_HBA" "${PG_HBA}.backup"
[ -f "${PG_CONF}.backup" ] || sudo cp "$PG_CONF" "${PG_CONF}.backup"

if sudo grep -q "^listen_addresses" "$PG_CONF" 2>/dev/null; then
    sudo sed -i "s/^listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF"
else
    echo "listen_addresses = '*'" | sudo tee -a "$PG_CONF"
fi

if ! sudo grep -q "host    $DB_NAME" "$PG_HBA" 2>/dev/null; then
    echo "host    $DB_NAME    $DB_USER    0.0.0.0/0    md5" | sudo tee -a "$PG_HBA"
else
    print_warning "Règle pg_hba déjà présente, on passe..."
fi

sudo service postgresql restart 2>/dev/null || sudo systemctl restart postgresql 2>/dev/null || true

if sudo -u postgres psql -lqt 2>/dev/null | grep -q "$DB_NAME"; then
    print_warning "Base $DB_NAME existe déjà, on passe..."
else
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
    print_success "Base $DB_NAME créée !"
fi

if sudo -u postgres psql -c "\du" 2>/dev/null | grep -q "$DB_USER"; then
    print_warning "User $DB_USER existe déjà, on passe..."
else
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    print_success "User $DB_USER créé !"
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
sudo -u postgres psql -d $DB_NAME -c "CREATE TABLE IF NOT EXISTS aircraft_position (
    id SERIAL PRIMARY KEY,
    callsign VARCHAR(50) UNIQUE,
    latitude FLOAT,
    longitude FLOAT,
    heading FLOAT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);"
sudo -u postgres psql -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"

print_success "PostgreSQL configuré !"

# Étape 5 : Pare-feu
print_info "Étape 5/6 : Configuration du pare-feu..."
if command -v ufw &> /dev/null; then
    sudo ufw status | grep -q "$FGMS_PORT/udp" || sudo ufw allow $FGMS_PORT/udp
    sudo ufw status | grep -q "$FGMS_TELNET_PORT/tcp" || sudo ufw allow $FGMS_TELNET_PORT/tcp
    sudo ufw status | grep -q "5432/tcp" || sudo ufw allow 5432/tcp
    sudo ufw status | grep -q "22/tcp" || sudo ufw allow 22/tcp
    sudo ufw --force enable
    print_success "Pare-feu configuré !"
else
    print_warning "ufw non disponible, pare-feu ignoré."
fi

# Étape 6 : Services systemd
print_info "Étape 6/6 : Création des services systemd..."
if command -v systemctl &> /dev/null; then
    sudo tee /etc/systemd/system/fgms.service > /dev/null << EOF
[Unit]
Description=FlightGear Multiplayer Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
ExecStart=/usr/local/sbin/fgms -p $FGMS_PORT -a $FGMS_TELNET_PORT -d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/fgms-tracker.service > /dev/null << EOF
[Unit]
Description=FlightGear Position Tracker
After=network.target postgresql.service fgms.service

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
EnvironmentFile=$INSTALL_DIR/config/.env
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/fgms_tracker.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable fgms
    sudo systemctl enable fgms-tracker
    sudo systemctl start fgms
    sleep 3
    sudo systemctl start fgms-tracker
    print_success "Services systemd créés et démarrés !"
else
    print_warning "systemd non disponible (WSL2). Lance manuellement :"
fi

echo ""
print_success "=== Installation terminée ! ==="
echo ""
print_info "Ports ouverts :"
echo "  $FGMS_PORT UDP  - FlightGear multijoueur"
echo "  $FGMS_TELNET_PORT TCP  - Telnet FGMS"
echo "  5432 TCP - PostgreSQL"
echo ""
print_info "Commandes pour lancer manuellement :"
echo ""
echo "  # Terminal 1 - Lancer FGMS :"
echo "  fgms -p $FGMS_PORT -a $FGMS_TELNET_PORT -d"
echo ""
echo "  # Terminal 2 - Lancer le tracker :"
echo "  source $INSTALL_DIR/config/.env && $INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/fgms_tracker.py"
echo ""
print_info "Connexion FlightGear :"
echo "  Serveur : $(hostname -I | awk '{print $1}') port $FGMS_PORT"
