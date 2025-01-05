# Plex Local WOL (Wake-On-Lan) for Raspberry Pi and other local devices

If you have a raspberry pi, why not save some energy and allow the server that hosts a Plex Media Server to go to sleep! The Raspberry Pi can act as an addition Plex server, but will work to also activate a sleeping local server via Wake-On-Lan features once a client device is connected.

## Requirements
* PHP with ext-sockets (you may need to install PHP `sudo apt install -y php`
* Composer  `sudo apt install -y composer`
* You need to know the MAC address and IP address of the ethernet port of your powerful PC with a Plex Server
* Your powerful PC needs to accept Wake-On-Lan packets (https://www.howtogeek.com/70374/how-to-geek-explains-what-is-wake-on-lan-and-how-do-i-enable-it/)

## Installation

### Plex set up
First install Plex on the raspberry pi to act as a dummy server.
On rasperry pi OS/ubuntu this can be done using apt - there are a number of tutorials to set this up

Go to http://localhost:32400/web/index.html on the pi and link it to your Plex account.
It should automatically auto-start on every reboot.
This dummy server ensures that the Pi is kept in the loop when you are remotely trying to access Plex media.
Now that you have a Plex server on your raspberry pi, connections to the pi  will be made every time a Plex client opens on e.g. on your TV or your phone app.

Restart the pi and open a client device and ensure that connections to the pi Plex server work well both locally and also when you turn off Wifi and access via mobile internet to ensure Remote Access is working.

**In Plex settings, "Enable Plex Media Server debug logging" is enabled on the Pi Plex server (under Settings -> General). Verbose logging is not required.

### Install and configure the app
```
sudo adduser --system --no-create-home --group plexlocalwol
sudo mkdir /usr/local/plexlocalwol
sudo cd /usr/local/plexlocalwol
sudo git clone https://github.com/Ali1/PlexLocalWOL/ ./
sudo composer install
cp config/config.php.new config/config.php
nano config/config.php # EDIT the mac and host IP address fields
sudo chown -R plexlocalwol:plexlocalwol /usr/local/plexlocalwol/
```
### Now install as an auto-starting service
```
sudo cd /usr/local/plexlocalwol
sudo bin/install
```

### Check status
```
systemctl status plexlocalwol
```

## FAQ
### My ethernet connection is slow. Can I use wifi and ethernet
On windows you can enable both and WOL should work. Make sure to prioritise your wifi connection to take advantage of the speed. https://www.windowscentral.com/how-change-priority-order-network-adapters-windows-10
