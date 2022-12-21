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
### Debian Stretch:
```
git clone https://github.com/ninlith/subsolar.git ~/.conky/subsolar
sudo apt-get install \
qdbus librsvg2-bin xmlstarlet fonts-cantarell gmt gmt-gshhg \
geoclue-2.0 geographiclib-tools python3-ephem gnome-icon-theme-symbolic \
conky-all gcalcli inxi
sudo /usr/sbin/geographiclib-get-magnetic wmm2015
gcalcli agenda
```
### Debian Jessie:
```
git clone https://github.com/ninlith/subsolar.git ~/.conky/subsolar
sudo apt-get -t jessie-backports install gmt gmt-gshhg
sudo apt-get install virtualenv python-dev gcc qdbus librsvg2-bin xmlstarlet \
fonts-cantarell geoclue-2.0 geographiclib-tools gnome-icon-theme-symbolic \
conky-all inxi
sudo /usr/sbin/geographiclib-get-magnetic wmm2010
cd ~/.conky/subsolar
virtualenv venv
source venv/bin/activate
pip install pyephem gcalcli
gcalcli agenda
deactivate

source ~/.conky/subsolar/venv/bin/activate
conky -c ~/.conky/subsolar/subsolar.conkyrc-old_syntax &
conky -c ~/.conky/subsolar/bottom.conkyrc-old_syntax &
deactivate
```

## License
GNU GPLv3
