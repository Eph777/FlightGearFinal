import socket
import time
import psycopg2
import psycopg2.extras
import math
import os

DB_NAME = os.getenv("DB_NAME", "flightgear")
DB_USER = os.getenv("DB_USER", "fguser")
DB_PASS = os.getenv("DB_PASS", "fgpassword123")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))

FGMS_HOST = "127.0.0.1"
FGMS_TELNET_PORT = 5001
POLL_INTERVAL = 2


def connect_db(max_attempts=10, wait=5):
    for attempt in range(1, max_attempts + 1):
        try:
            conn = psycopg2.connect(
                dbname=DB_NAME, user=DB_USER, password=DB_PASS,
                host=DB_HOST, port=DB_PORT, connect_timeout=5
            )
            print(f"Connecté à PostgreSQL ({DB_HOST}:{DB_PORT}/{DB_NAME})")
            return conn
        except psycopg2.OperationalError as e:
            print(f"DB indisponible (tentative {attempt}/{max_attempts}) : {e}")
            if attempt < max_attempts:
                time.sleep(wait)
    raise RuntimeError("Impossible de se connecter à PostgreSQL après plusieurs tentatives.")


def get_positions():
    """
    Interroge le port Telnet de FGMS et retourne la liste des avions.
    Retourne une liste vide si FGMS n'est pas disponible (pas de crash).
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect((FGMS_HOST, FGMS_TELNET_PORT))
        s.send(b'list\r\n')
        time.sleep(0.2)
        data = s.recv(16384).decode(errors="replace")
        s.close()
    except (socket.error, OSError) as e:
        print(f"FGMS non disponible sur {FGMS_HOST}:{FGMS_TELNET_PORT} : {e}")
        return []

    players = []
    for line in data.split('\n'):
        if '@LOCAL:' not in line:
            continue
        parts = line.split()
        if len(parts) < 8:
            continue
        try:
            callsign = parts[0].split('@')[0]
            lat = float(parts[4])
            lon = float(parts[5])
            heading = math.degrees(float(parts[7])) % 360
            players.append((callsign, lat, lon, heading))
        except (ValueError, IndexError):
            continue
    return players


conn = connect_db()
print("Tracker démarré !")

while True:
    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM aircraft_position WHERE updated_at < NOW() - INTERVAL '10 seconds'")

        players = get_positions()
        for callsign, lat, lon, heading in players:
            cursor.execute("""
                INSERT INTO aircraft_position (callsign, latitude, longitude, heading, updated_at)
                VALUES (%s, %s, %s, %s, NOW())
                ON CONFLICT (callsign) DO UPDATE SET
                    latitude   = EXCLUDED.latitude,
                    longitude  = EXCLUDED.longitude,
                    heading    = EXCLUDED.heading,
                    updated_at = NOW()
            """, (callsign, lat, lon, heading))

        conn.commit()
        cursor.close()
        print(f"{len(players)} joueur(s) tracké(s)")

    except psycopg2.OperationalError as e:
        print(f"Connexion DB perdue : {e} — reconnexion...")
        try:
            conn.close()
        except Exception:
            pass
        conn = connect_db()

    except Exception as e:
        print(f"Erreur : {e}")
        try:
            conn.rollback()
            cursor.close()
        except Exception:
            pass

    time.sleep(POLL_INTERVAL)
