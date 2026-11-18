#!/bin/sh
# Writes Mosquitto's password file from .env, then starts the broker through the
# image's own entrypoint. Mosquitto stores only salted hashes, so the file is
# rebuilt on every start rather than committed: changing MQTT_PASSWORD in .env and
# restarting the container is enough.
set -eu

: "${MQTT_USERNAME:?MQTT_USERNAME is not set}"
: "${MQTT_PASSWORD:?MQTT_PASSWORD is not set}"

passwd_file=/mosquitto/config/passwd
rm -f "$passwd_file"
# -c creates the file, -b takes the password from the command line.
mosquitto_passwd -c -b "$passwd_file" "$MQTT_USERNAME" "$MQTT_PASSWORD"
# Mosquitto refuses a password file that other users can read.
chown mosquitto:mosquitto "$passwd_file"
chmod 0600 "$passwd_file"

exec /docker-entrypoint.sh /usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf
