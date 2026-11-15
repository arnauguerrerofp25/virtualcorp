#!/bin/sh
# S'executa des de l'instal·lador al final de la instal·lació.
# El sistema instal·lat és a /target; la ISO és a /cdrom.
set -e

# Claus SSH autoritzades de sysadmin (professor + alumne)
mkdir -p /target/home/sysadmin/.ssh
cp /cdrom/vcorp/authorized_keys /target/home/sysadmin/.ssh/authorized_keys
in-target chown -R sysadmin:sysadmin /home/sysadmin/.ssh
in-target chmod 700 /home/sysadmin/.ssh
in-target chmod 600 /home/sysadmin/.ssh/authorized_keys

# sudo sense contrasenya: el compte no en té, l'accés és només per clau
echo 'sysadmin ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/sysadmin
chmod 440 /target/etc/sudoers.d/sysadmin

# Preparar per clonar: cada clon tindrà identitat pròpia
cp /cdrom/vcorp/regen-ssh-host-keys.service /target/etc/systemd/system/
in-target systemctl enable regen-ssh-host-keys.service
rm -f /target/etc/ssh/ssh_host_*
: > /target/etc/machine-id
rm -f /target/var/lib/dbus/machine-id
