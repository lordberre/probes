#!/bin/bash
# This script can be loaded by any parent script in order to enable Wi-Fi statstics on various tests
# Or run the script interactively with "./script main".

# Required vars on parent are:
# count
# logfacility
# direction
# It's also assumed that all of these vars are correctly set in parent script.
main=false
REDIRECT="/dev/null"
probe="`cut -d "." -f 2 <<< $(hostname)`"

if [[ $1 = "main" ]]; then
    main=true
    INTERVAL_SEC=5
    logger_type=basic
    logfacility=wifi_logger
    direction=none # Something to fill the iperf direction column
    count=$(( ( RANDOM % 9999 )  + 1 ))
fi

if [[ $main = false ]]; then
        logger_type=legacy
	echo $count $logfacility $direction
	if [ -z ${count+x} ] || [ -z ${logfacility+x} ] || [ -z ${direction+x} ]; then
	   echo "All of the required vars must be provided: count, logfacility, direction"
	   exit 1
	fi
fi

# Script can be called with verbose argument to send everything to stdout if needed
if [[ $main = false ]]; then
	if [[ $# -eq 0 ]]; then
	    REDIRECT="/dev/null"
	elif [[ $# -eq 1 ]] ; then
	    if [ $2 = "verbose" ]; then
	    REDIRECT="/dev/stdout"
	    else
		echo 'wrong argument given, must be "verbose"' 
		exit 1
	    fi
	else
	    echo 'to many arguments given..'
	    exit 1 
	fi
fi

# Default config
default_cfg () {
logfile="/var/log/chprobe_wifistats.log"
}

# Load configuration file
default_cfg # Fallback to default if there are issues with the probe cfg
chprobe_configfile="/var/chprobe/chprobe.cfg"
if [ ! -f $chprobe_configfile ]; then
    default_cfg
else
    source $chprobe_configfile
    if [ $? -ne 0 ]; then
        default_cfg
    fi
fi


# Detect Wi-Fi NIC
iwnic=$(ifconfig 2> $REDIRECT | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep -c up /sys/class/net/wl*/operstate 2> $REDIRECT)" # Detect wireless interface state

# Wi-Fi parse pattern for iw
wifi_logger() {
if [ $iwdetect -gt 0 ] 2> $REDIRECT;then 
    if [ `iw $iwnic station dump | wc -l` -eq 0 ]; then echo "no iw output, skipping";return 1;fi
    wififreq="$(iw $iwnic link 2> $REDIRECT | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
    phydetect="$(iw $iwnic link 2> $REDIRECT | grep -c VHT)" # What PHY? (Legacy is not supported)

# TODO: Fix proper function instead of ugly/suboptimal eval oneliner. 
# Function should handle if logs are shipped with logger or directly appended to a generic log file
    template_logger() {
    if [ $logger_type = "legacy" ]; then
        stats_type=$1
        logger -t $stats_type[$(echo $count)] -p $logfacility

    elif [ $logger_type = "basic" ]; then
        stats_type=$1
        sed -e "s/^/$(date "+%b %d %H:%M:%S") $probe $stats_type[$(echo $count)]: /" >> $logfile

    elif [ $logger_type = "logger" ]; then
        echo 'not implemented yet' && exit 0
    fi
    }

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger tx_linkstats_\$phy && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger rx_linkstats_\$phy && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | template_logger iw_counters_\$phy"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger tx_linkstats_\$phy && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | template_logger rx_linkstats_\$phy && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | tr -d 'rx|tx|bytes|packets|retries|failed:' | xargs | tr -s ' ' | template_logger iw_counters_\$phy"
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

if [[ $main = true ]]; then
    while true;do 
        wifi_logger
        sleep $INTERVAL_SEC
    done
fi

