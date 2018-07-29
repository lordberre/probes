#!/bin/bash
# This script can be loaded by any parent script in order to enable Wi-Fi statstics on various tests

# Required vars on parent are:
# count
# logfacility
# direction
# It's also assumed that all of these vars are correctly set in parent script.
echo $count $logfacility $direction
if [ -z ${count+x} ] || [ -z ${logfacility+x} ] || [ -z ${direction+x} ]; then
   echo "All of the required vars must be provided: count, logfacility, direction"
   exit 1
fi

# Script can be called with verbose argument to send everything to stdout if needed
if [[ $# -eq 0 ]] ; then
    REDIRECT="/dev/null"
elif [[ $# -eq 1 ]] ; then
    if [ $1 = "verbose" ]; then
    REDIRECT="/dev/stdout"
    else
        echo 'wrong argument given, must be "verbose"' 
        exit 1
    fi
else
    echo 'to many arguments given..'
    exit 1 
fi

logger_type=legacy

# Detect Wi-Fi NIC
iwnic=$(ifconfig 2> $REDIRECT | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep -c up /sys/class/net/wl*/operstate 2> $REDIRECT)" # Detect wireless interface state

# Wi-Fi parse pattern for iw
wifi_logger() {
if [ $iwdetect -gt 0 ] 2> $REDIRECT;then 

    wififreq="$(iw $iwnic link 2> $REDIRECT | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
    phydetect="$(iw $iwnic link 2> $REDIRECT | grep -c VHT)" # What PHY? (Legacy is not supported)

# TODO: Fix proper function instead of ugly/suboptimal eval oneliner. 
# Function should handle if logs are shipped with logger or directly appended to a generic log file
    template_logger() {
    if [ $logger_type = "legacy" ]; then
        stats_type=$1
        logger -t $stats_type[$(echo $count)] -p $logfacility

    elif [ $logger_type = "basic" ]; then
        echo 'not implemented yet' && exit 0
#    probe="`cut -d "." -f 2 <<< $(hostname)`"
#    return "sed -e "s/^/$(date "+%b %d %H:%M:%S") ${probe} $logfacility: /" >> $logfile"

    elif [ $logger_type = "logger" ]; then
        echo 'not implemented yet' && exit 0
    fi
    }

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger tx_linkstats_\$phy && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger rx_linkstats_\$phy && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | template_logger iw_counters"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger tx_linkstats_\$phy && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger rx_linkstats_\$phy && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | template_logger iw_counters"
####

    if [ $wififreq -lt 2500 ] 2> $REDIRECT; then
        phy=ht && eval $htparse
    else
        if [ $phydetect -ge 1 ] 2> $REDIRECT; then
            phy=vht && eval $vhtparse
        else 
            phy=ht && eval $htparse
        fi
    fi

else 
    echo 'No WiFi NIC detected'
fi
}
