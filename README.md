# FlightGearFinal
Track player positions from a FlightGear multiplayer server in real time and visualize them on a live map inside QGIS.

## Architecture
[FlightGear Clients] → [FGMS Server] → [fgms_tracker.py] → [PostgreSQL] → [QGIS]

## Requirements
- Ubuntu 20.04+ or Debian 11+
- 2 GB RAM minimum
- Root or sudo access

## Installation
```bash

#1. Clone the repo : 
git clone https://github.com/Eph777/FlightGearFinal.git
cd FlightGearTest

# 2. Run the install script
bash install.sh

## Connect FlightGear
In FlightGear launcher → Multiplayer → Custom server :
Server : <your-server-ip>
Port   : 5000

## Run The fgms_tracker 
python3 fgms_tracker.py
  








