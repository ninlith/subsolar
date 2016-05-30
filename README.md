## Subsolar
![screenshot](screenshot.png?raw=true)

## Features
- 12- and 24-hour clocks.
- Calendar agenda and monthly view.
- Sun rising and setting times.
- Weather forecast.
- Currently playing track of an MPRIS2 compliant media player.
- Orthographic map projections.
- Positions of astronomical and artificial objects.
- Current geolocation.
- Magnetic declination.

## Installation
###Debian:
```
git clone https://github.com/ninlith/subsolar.git ~/.conky/subsolar
sudo apt-get install \
qdbus librsvg2-bin xmlstarlet fonts-cantarell gmt gmt-gshhg \
geoclue-2.0 geographiclib-tools python3-ephem gnome-icon-theme-symbolic \
conky-all gcalcli inxi
sudo /usr/sbin/geographiclib-get-magnetic wmm2015
```

## License
GNU GPLv3
