#!/bin/bash
# FlightGear Multiplayer Tracker - Installation Script
# Conçu pour un serveur Linux avec des services existants (web, etc.)
# Résolution automatique des conflits — aucune intervention manuelle requise.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERREUR]${NC} $1"; }

INSTALL_DIR="/root/flightgear"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FGMS_PORT=5000
FGMS_TELNET_PORT=5001
DB_PORT=5432

echo ""
print_info "=== FlightGear Multiplayer Tracker - Installation ==="
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 0 : Credentials DB (seule saisie manuelle requise)
# ─────────────────────────────────────────────────────────────────────────────
bash "$SCRIPT_DIR/setup_env.sh"
source "$INSTALL_DIR/config/.env"

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 0b : Résolution automatique des conflits de ports
# ─────────────────────────────────────────────────────────────────────────────
print_info "Analyse et résolution automatique des ports..."
echo ""

# Retourne 0 si le port TCP est occupé
tcp_in_use() { ss -tlnp 2>/dev/null | grep -q ":$1 "; }
# Retourne 0 si le port UDP est occupé
udp_in_use() { ss -ulnp 2>/dev/null | grep -q ":$1 "; }
# Trouve le premier port TCP libre à partir de $1
free_tcp_from() {
    local p=$1
    while tcp_in_use $p; do p=$((p + 1)); done
    echo $p
}
# Trouve le premier port UDP libre à partir de $1
free_udp_from() {
    local p=$1
    while udp_in_use $p; do p=$((p + 1)); done
    echo $p
}
# Identifie le processus qui utilise un port TCP
who_tcp() { ss -tlnp 2>/dev/null | awk "/:$1 /{print \$NF}" | head -1 || echo "inconnu"; }
who_udp() { ss -ulnp 2>/dev/null | awk "/:$1 /{print \$NF}" | head -1 || echo "inconnu"; }

# — Port FGMS (UDP)
if udp_in_use $FGMS_PORT; then
    OLD=$FGMS_PORT
    FGMS_PORT=$(free_udp_from $((FGMS_PORT + 1)))
    print_warning "Port $OLD/UDP occupé par $(who_udp $OLD) → FGMS déplacé sur $FGMS_PORT/UDP (automatique)"
else
    print_success "Port $FGMS_PORT/UDP libre"
fi

# — Port FGMS Telnet (TCP) — doit être différent du port FGMS
if tcp_in_use $FGMS_TELNET_PORT || [ $FGMS_TELNET_PORT -eq $FGMS_PORT ]; then
    OLD=$FGMS_TELNET_PORT
    FGMS_TELNET_PORT=$(free_tcp_from $((FGMS_TELNET_PORT + 1)))
    # éviter collision avec FGMS_PORT
    [ $FGMS_TELNET_PORT -eq $FGMS_PORT ] && FGMS_TELNET_PORT=$(free_tcp_from $((FGMS_TELNET_PORT + 1)))
    print_warning "Port $OLD/TCP occupé ou en conflit → FGMS Telnet déplacé sur $FGMS_TELNET_PORT/TCP (automatique)"
else
    print_success "Port $FGMS_TELNET_PORT/TCP libre"
fi

# — Port PostgreSQL (TCP)
POSTGRES_CONFLICT=0
if tcp_in_use $DB_PORT; then
    PROC="$(who_tcp $DB_PORT)"
    if echo "$PROC" | grep -qi "postgres"; then
        print_success "Port $DB_PORT/TCP utilisé par PostgreSQL existant → conservation"
    else
        OLD_DB_PORT=$DB_PORT
        DB_PORT=$(free_tcp_from $((DB_PORT + 1)))
        POSTGRES_CONFLICT=1
        print_warning "Port $OLD_DB_PORT/TCP occupé par $PROC → PostgreSQL déplacé sur $DB_PORT/TCP (automatique)"
    fi
else
    print_success "Port $DB_PORT/TCP libre"
fi

# Mettre à jour le .env avec le port DB résolu
sed -i "s|^DB_PORT=.*|DB_PORT=${DB_PORT}|" "$INSTALL_DIR/config/.env"
source "$INSTALL_DIR/config/.env"

# — Résumé de la configuration finale
echo ""
print_info "Configuration finale résolue :"
echo "  Port FGMS (UDP)         : $FGMS_PORT"
echo "  Port FGMS Telnet (TCP)  : $FGMS_TELNET_PORT"
echo "  Port PostgreSQL (TCP)   : $DB_PORT"
echo "  Base de données         : $DB_NAME (sur localhost)"
echo ""

# — Confirmation finale (unique)
print_warning "Ce script va :"
echo "  1. Installer les paquets nécessaires (sans apt upgrade)"
echo "  2. Compiler et installer FGMS"
echo "  3. Configurer PostgreSQL pour les connexions externes (QGIS/Mac)"
echo "  4. Créer un venv Python isolé + installer requirements.txt"
echo "  5. Configurer le pare-feu UFW automatiquement"
echo "  6. Créer et démarrer les services systemd"
echo ""
print_warning "Aucun service existant ne sera modifié ou redémarré."
echo ""
read -p "Lancer l'installation ? (o/n) : " CONFIRM
[[ "$CONFIRM" != "o" ]] && { print_info "Installation annulée."; exit 0; }
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : Dépendances (apt update UNIQUEMENT — jamais de apt upgrade)
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 1/6 : Installation des dépendances..."
apt-get update -qq
apt-get install -y git cmake build-essential postgresql python3 python3-venv python3-pip ufw curl
print_success "Dépendances installées !"

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 2 : Compilation FGMS
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 2/6 : Installation de FGMS..."
if command -v fgms &>/dev/null; then
    print_success "FGMS déjà installé — ignoré pour ne pas perturber le serveur."
else
    print_info "Compilation de FGMS (peut prendre quelques minutes)..."
    (
        set -e
        cd "$HOME"
        [ -d fgms ] && rm -rf fgms
        git clone https://github.com/FlightGear/fgms.git
        cd fgms && mkdir -p build && cd build
        cmake .. && make -j"$(nproc)"
        make install
    ) || { print_error "Échec de la compilation FGMS. Vérifiez les dépendances ci-dessus."; exit 1; }
    print_success "FGMS installé !"
fi

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 3 : Configuration PostgreSQL
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 3/6 : Configuration PostgreSQL..."

# Démarrer PostgreSQL si pas encore actif
if ! systemctl is-active --quiet postgresql 2>/dev/null; then
    systemctl start postgresql
    sleep 2
fi

PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;'  2>/dev/null | tr -d '[:space:]')
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;' 2>/dev/null | tr -d '[:space:]')

if [ -z "$PG_HBA" ] || [ -z "$PG_CONF" ]; then
    print_error "Impossible de localiser les fichiers de config PostgreSQL."
    exit 1
fi

# Sauvegardes (idempotent — une seule fois)
[ -f "${PG_CONF}.backup" ] || cp "$PG_CONF" "${PG_CONF}.backup"
[ -f "${PG_HBA}.backup"  ] || cp "$PG_HBA"  "${PG_HBA}.backup"

# Configurer le port PostgreSQL si déplacé
if [ $POSTGRES_CONFLICT -eq 1 ]; then
    if grep -qE "^port\s*=" "$PG_CONF" 2>/dev/null; then
        sed -i "s|^port\s*=.*|port = ${DB_PORT}|" "$PG_CONF"
    elif grep -qE "^#port" "$PG_CONF" 2>/dev/null; then
        sed -i "s|^#port.*|port = ${DB_PORT}|" "$PG_CONF"
    else
        echo "port = ${DB_PORT}" >> "$PG_CONF"
    fi
    print_success "PostgreSQL configuré sur le port $DB_PORT."
fi

# listen_addresses = '*' (nécessaire pour QGIS depuis Mac)
PG_RESTART=0
if grep -qE "^listen_addresses\s*=\s*'\*'" "$PG_CONF" 2>/dev/null; then
    print_info "listen_addresses = '*' déjà configuré."
else
    if grep -qE "^listen_addresses" "$PG_CONF" 2>/dev/null; then
        sed -i "s|^listen_addresses\s*=.*|listen_addresses = '*'|" "$PG_CONF"
    elif grep -qE "^#listen_addresses" "$PG_CONF" 2>/dev/null; then
        sed -i "s|^#listen_addresses.*|listen_addresses = '*'|" "$PG_CONF"
    else
        echo "listen_addresses = '*'" >> "$PG_CONF"
    fi
    PG_RESTART=1
    print_success "listen_addresses = '*' activé (connexions QGIS/Mac autorisées)."
fi

# pg_hba.conf : autoriser les connexions TCP externes
# md5 = compatible avec tous les clients (QGIS, pgAdmin) sur toutes versions PG
if grep -qE "host\s+${DB_NAME}\s+${DB_USER}\s+0\.0\.0\.0/0" "$PG_HBA" 2>/dev/null; then
    print_info "Règle pg_hba pour $DB_USER@$DB_NAME déjà présente."
else
    echo "host    ${DB_NAME}    ${DB_USER}    0.0.0.0/0    md5" >> "$PG_HBA"
    print_success "Accès externe autorisé pour $DB_USER@$DB_NAME."
fi

# Restart si nécessaire (listen_addresses ou port), sinon reload sans coupure
if [ $PG_RESTART -eq 1 ] || [ $POSTGRES_CONFLICT -eq 1 ]; then
    print_info "Redémarrage de PostgreSQL (changement de configuration réseau)..."
    systemctl restart postgresql
else
    print_info "Rechargement de PostgreSQL (pg_hba, sans couper les connexions)..."
    systemctl reload postgresql 2>/dev/null || systemctl restart postgresql
fi
sleep 2

# Créer la base si elle n'existe pas
if sudo -u postgres psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "$DB_NAME"; then
    print_info "Base $DB_NAME déjà existante → conservée."
else
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
    print_success "Base $DB_NAME créée."
fi

# Créer l'utilisateur si il n'existe pas
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER';" 2>/dev/null | grep -q 1; then
    print_info "Utilisateur $DB_USER déjà existant → conservé."
else
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    print_success "Utilisateur $DB_USER créé."
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
# GRANT SCHEMA nécessaire pour PostgreSQL 15+
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;" 2>/dev/null || true
sudo -u postgres psql -d "$DB_NAME" -c "
CREATE TABLE IF NOT EXISTS aircraft_position (
    id         SERIAL PRIMARY KEY,
    callsign   VARCHAR(50) UNIQUE,
    latitude   FLOAT,
    longitude  FLOAT,
    heading    FLOAT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"

print_success "PostgreSQL configuré !"

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 4 : Venv Python isolé + requirements.txt
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 4/6 : Création du venv Python..."
mkdir -p "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi

"$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
"$INSTALL_DIR/venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
cp "$SCRIPT_DIR/fgms_tracker.py" "$INSTALL_DIR/fgms_tracker.py"

print_success "Venv Python prêt ($INSTALL_DIR/venv), requirements.txt installé."

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 5 : Pare-feu UFW — automatique et sans risque de lockout SSH
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 5/6 : Configuration du pare-feu..."
if command -v ufw &>/dev/null; then

    # Détecter le port SSH actif depuis le daemon en cours d'écoute
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{match($4,/:([0-9]+)$/,m); if(m[1]) print m[1]}' | head -1)
    [ -z "$SSH_PORT" ] && SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    SSH_PORT="${SSH_PORT:-22}"
    print_info "Port SSH détecté : $SSH_PORT"

    # Vérifier l'état actuel de UFW
    UFW_WAS_ACTIVE=0
    ufw status 2>/dev/null | head -1 | grep -qi "active" && UFW_WAS_ACTIVE=1

    # Ajouter toutes les règles nécessaires (SSH EN PREMIER pour éviter tout lockout)
    ufw allow "$SSH_PORT/tcp"           comment "SSH" 2>/dev/null || true
    ufw allow "$FGMS_PORT/udp"          comment "FGMS-UDP" 2>/dev/null || true
    ufw allow "$FGMS_TELNET_PORT/tcp"   comment "FGMS-Telnet" 2>/dev/null || true
    ufw allow "$DB_PORT/tcp"            comment "PostgreSQL" 2>/dev/null || true

    if [ $UFW_WAS_ACTIVE -eq 1 ]; then
        # UFW déjà actif : juste un reload, pas de coupure
        ufw reload
        print_success "Règles UFW mises à jour (reload sans interruption)."
    else
        # UFW inactif : SSH est déjà autorisé ci-dessus, activation sécurisée
        ufw --force enable
        print_success "UFW activé. SSH ($SSH_PORT/tcp) autorisé en premier — pas de risque de lockout."
    fi
else
    print_warning "ufw non disponible, configuration du pare-feu ignorée."
fi

# ─────────────────────────────────────────────────────────────────────────────
# ÉTAPE 6 : Services systemd
# ─────────────────────────────────────────────────────────────────────────────
print_info "Étape 6/6 : Création des services systemd..."
CURRENT_USER=$(whoami)

tee /etc/systemd/system/fgms.service > /dev/null << EOF
[Unit]
Description=FlightGear Multiplayer Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
ExecStart=/usr/local/sbin/fgms -p $FGMS_PORT -a $FGMS_TELNET_PORT -d
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/fgms-tracker.service > /dev/null << EOF
[Unit]
Description=FlightGear Position Tracker
After=network.target postgresql.service fgms.service

[Service]
Type=simple
User=$CURRENT_USER
EnvironmentFile=$INSTALL_DIR/config/.env
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/fgms_tracker.py
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fgms
systemctl enable fgms-tracker
systemctl start fgms
sleep 3
systemctl start fgms-tracker
print_success "Services systemd créés et démarrés !"

# ─────────────────────────────────────────────────────────────────────────────
# Résumé final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
print_success "=== Installation terminée ! ==="
echo ""
print_info "Ports actifs :"
echo "  $FGMS_PORT     UDP  — FlightGear multijoueur"
echo "  $FGMS_TELNET_PORT    TCP  — Telnet FGMS (tracker)"
echo "  $DB_PORT   TCP  — PostgreSQL (connexions externes autorisées)"
echo ""
print_info "Services :"
echo "  systemctl status fgms"
echo "  systemctl status fgms-tracker"
echo "  journalctl -u fgms-tracker -f   ← logs en temps réel"
echo ""
print_info "Connexion QGIS / pgAdmin depuis Mac :"
echo "  Hôte    : $(hostname -I | awk '{print $1}')"
echo "  Port    : $DB_PORT"
echo "  Base    : $DB_NAME"
echo "  User    : $DB_USER"
echo ""
print_info "Connexion FlightGear :"
echo "  Serveur : $(hostname -I | awk '{print $1}') port $FGMS_PORT"
