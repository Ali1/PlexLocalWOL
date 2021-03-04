# Plex Local WOL (Wake-On-Lan) for Raspberry Pi and other local devices

If you have a raspberry pi, why not save some energy and allow the server that hosts a Plex Media Server to go to sleep! The Raspberry Pi can act as an addition Plex server, but will work to also activate a sleeping local server via Wake-On-Lan features once a client device is connected.

## Requirements
* PHP with ext-sockets (default for ubuntu on raspberry)
* You need to know the MAC address of the ethernet port of your powerful PC
* Your powerful PC needs to accept Wake-On-Lan packets (https://www.howtogeek.com/70374/how-to-geek-explains-what-is-wake-on-lan-and-how-do-i-enable-it/)

## Installation

### Plex set up
First install Plex on the raspberry pi to act as a dummy server.
On ubuntu this can be done using apt - check the Plex website
Or if you are using Raspbian, check this https://thepi.io/how-to-set-up-a-raspberry-pi-plex-server/

Go to http://localhost:32400/web/index.html on the pi and link it to your Plex account.
It should automatically auto-start on every reboot.
This dummy server ensures that the Pi is kept in the loop when you are remotely trying to access Plex media.
Now that you have a Plex server on your raspberry pi, connections to the pi  will be made every time a Plex client opens on e.g. on your TV or your phone app.

Restart the pi and open a client device and ensure that connections to the pi Plex server work well both locally and also when you turn off Wifi and access via mobile internet to ensure Remote Access is working.

### Install and configure the app
```
cd ~/
git clone https://github.com/Ali1/PlexLocalWOL/
cd ~/PlexLocalWOL
cp src/config.php.new src/config.php
nano src/config.php # EDIT the mac and host field
```
### Now install as an auto-starting service
```
cd ~/PlexLocalWOL
nano plexlocalwol.service # check Exec command location of bin file is correct (is ubuntu your username?) - modify if needed
sudo bin/install
```

### Check status
```
cd ~/PlexLocalWOL
sudo bin/status
```

## FAQ
### My ethernet connection is slow. Can I use wifi and ethernet
On windows you can enable both and WOL should work. Make sure to prioritise your wifi connection to take advantage of the speed. https://www.windowscentral.com/how-change-priority-order-network-adapters-windows-10