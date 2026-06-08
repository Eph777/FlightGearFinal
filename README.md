# FlightGear Multiplayer Tracker

Track player positions from a FlightGear multiplayer server in real-time and visualize them on a live map inside QGIS.

## Architecture
`[FlightGear Clients] → [FGMS Server] → [fgms_tracker.py] → [PostgreSQL] → [QGIS]`

## Requirements
- Ubuntu 20.04+ or Debian 11+
- 2 GB RAM minimum
- A non-root user with `sudo` privileges

## Deployment on Ubuntu

Follow these simple steps to install everything in one go. You can run this anywhere (e.g., in your home directory).

```bash
# 1. Clone the repository
git clone https://github.com/Eph777/FlightGearFinal.git
cd FlightGearFinal

# 2. Run the installation script
bash install.sh
```

During the installation:
- It will ask you for database credentials (you can press Enter to use the defaults).
- It will automatically install `fgms`, PostgreSQL, and all Python dependencies in a safe virtual environment.
- It will configure and start `systemd` services for both the game server (`fgms`) and the position tracker (`fgms-tracker`).

## How to use

The services run automatically in the background. You do not need to start anything manually.

### Connect FlightGear
In the FlightGear launcher, go to **Multiplayer** → **Custom server**:
- **Server:** `<your-ubuntu-server-ip>`
- **Port:** `5000`

### Check Services (Optional)
If you need to view the logs or check the status:
```bash
# Check FlightGear server status
sudo systemctl status fgms

# Check tracker status
sudo systemctl status fgms-tracker
```

### View in QGIS
1. Open QGIS.
2. Go to **Layer** → **Add Layer** → **Add PostGIS Layers...**
3. Create a new connection to your PostgreSQL database (`flightgear` database, user `fguser`).
4. Select the `view_live_positions` view and add it to your map. It will automatically update with aircraft positions.
