#!/bin/bash

# Copyright (C) 2013 Matthew D. Mower
# Copyright (C) 2012 AntonioCS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

# Functions

function usage() {
    console_error "$0 [-c /path/to/config] [-i 123.123.123.123]"
    exit 1
}

function cmd_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Adapted from one of the more readable answers by Gilles at
# https://unix.stackexchange.com/questions/60653/urlencode-function/60698#60698
function urlencode() {
    local string="$1"
    while [ -n "$string" ]; do
        local tail="${string#?}"
        local head="${string%"$tail"}"
        case "$head" in
            [-._~0-9A-Za-z])
                printf "%c" "$head";;
            *)
                printf "%%%02x" "'$head"
        esac
        string="$tail"
    done
}

function http_get() {
    if cmd_exists curl; then
        curl -s --user-agent "$USERAGENT" "$1"
    elif cmd_exists wget; then
        wget -q -O - --user-agent="$USERAGENT" "$1"
    else
        console_error "No http tool found. Install curl or wget."
        exit 1
    fi
}

function parse_date() {
    local string="$1"
    PARSED_DATE=$(date -d "$string" +'%s' 2>/dev/null || true)
    if [ -z "$PARSED_DATE" ] && cmd_exists gdate; then
        PARSED_DATE=$(gdate -d "$string" +'%s' 2>/dev/null || true)
    fi
    if [ -z "$PARSED_DATE" ]; then
        PARSED_DATE=$(date -jf "%Y-%m-%d %H:%M:%S" "$string" +'%s' 2>/dev/null || true)
    fi
    if [ -z "$PARSED_DATE" ]; then
        console_error "Could not parse date."
        exit 1
    fi
    return 0
}

# IP Validator
# http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi

    return $stat
}

function get_logline() {
    local host
    local response
    local response_a
    local response_b

    host="$1"
    response=$(echo "$2" | tr -cd "[:print:]")
    response_a=$(echo "$response" | awk '{ print $1 }')

    case $response_a in
        "good")
            response_b=$(echo "$response" | awk '{ print $2 }')
            LOGLINE="(good) [$host] DNS hostname successfully updated to $response_b."
            ;;
        "nochg")
            response_b=$(echo "$response" | awk '{ print $2 }')
            LOGLINE="(nochg) [$host] IP address is current: $response_b; no update performed."
            ;;
        "nohost")
            LOGLINE="(nohost) [$host] Hostname supplied does not exist under specified account. Revise config file."
            ;;
        "badauth")
            LOGLINE="(badauth) [$host] Invalid username password combination."
            ;;
        "badagent")
            LOGLINE="(badagent) [$host] Client disabled - No-IP is no longer allowing requests from this update script."
            ;;
        '!donator')
            LOGLINE='(!donator)'" [$host] An update request was sent including a feature that is not available."
            ;;
        "abuse")
            LOGLINE="(abuse) [$host] Username is blocked due to abuse."
            ;;
        "911")
            LOGLINE="(911) [$host] A fatal error on our side such as a database outage. Retry the update in no sooner than 30 minutes."
            ;;
        "")
            LOGLINE="(empty) [$host] No response received from No-IP. This may be due to rate limiting or a server-side problem."
            ;;
        *)
            LOGLINE="(error) [$host] Could not understand the response from No-IP. The DNS update server may be down."
            ;;
    esac

    return 0
}

function console_info() {
    local msg="$1"
    local lvl="$CONSOLE_OUTPUT_LEVEL"

    if [ -z "$lvl" ] || (( lvl < 3 )); then
        echo "$msg"
    fi
}

function console_error() {
    local msg="$1"
    local lvl="$CONSOLE_OUTPUT_LEVEL"

    if [ -z "$lvl" ] || (( lvl < 5 )); then
        echo "$msg" >&2
    fi
}

# Defines

CONFIGFILE=""
NEWIP=""
while getopts 'c:i:' flag; do
    case "${flag}" in
        c) CONFIGFILE="${OPTARG}" ;;
        i) NEWIP="${OPTARG}" ;;
        *) usage ;;
    esac
done

if [ -z "$CONFIGFILE" ]; then
    CONFIGFILE="$( cd "$( dirname "$0" )" && pwd )/config"
fi

if [ -e "$CONFIGFILE" ]; then
    source "$CONFIGFILE"
else
    console_error "Config file not found."
    exit 1
fi

if ! (( CONSOLE_OUTPUT_LEVEL >= 0 && CONSOLE_OUTPUT_LEVEL <= 6 )); then
    CONSOLE_OUTPUT_LEVEL=0
fi

if [ -n "$NEWIP" ] && ! valid_ip "$NEWIP"; then
    console_error "Invalid IP address specified."
    exit 1
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
   console_error "USERNAME or PASSWORD has not been set in the config file."
   exit 1
fi

USERAGENT="Bash No-IP Updater/1.3 $USERNAME"

NOW=$(date +'%s')

# Program

USERNAME=$(urlencode "$USERNAME")
PASSWORD=$(urlencode "$PASSWORD")
ENCODED_HOST=$(urlencode "$HOST")

REQUEST_URL="https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$ENCODED_HOST"
if [ -n "$NEWIP" ]; then
    NEWIP=$(urlencode "$NEWIP")
    REQUEST_URL="$REQUEST_URL&myip=$NEWIP"
fi

RESPONSE=$(http_get "$REQUEST_URL")
OIFS=$IFS
IFS=$'\n'
SPLIT_RESPONSE=( $(echo "$RESPONSE" | grep -o '[0-9a-z!]\+\( [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)\?') )
IFS=','
SPLIT_HOST=( $HOST )
IFS=$OIFS

for index in "${!SPLIT_HOST[@]}"; do
    get_logline "${SPLIT_HOST[index]}" "${SPLIT_RESPONSE[index]}"
    console_info "$LOGLINE"
done

exit 0
