#!/bin/bash
# Version 2.0 (BBK/zone integration) "wow will this even work"
# Note: Some variables are named "bbk"-something since we're using the same zone functionallity

# Dont touch this
zone=x
ip_version=x

# For global zone, if you want something else than hostname, then edit below
probename="$(hostname -d)"

# Link to bbk_api
bbk_apiurl="http://project-mayhem.se/probes/bbk_api.php"

# Functions and variables
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
bbk_remotestatusv2="curl -m 3 -s -o /dev/null -w \"%{http_code}\" \$bbk_apiurl"
globalzone_url="http://project-mayhem.se/probes/bbkzone_$probename"

reinit_status () {
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
bbk_remoteurl="http://project-mayhem.se/probes/bbk_status_zone-$zone"
bbk_remotestatus="$(curl -m 3 -s -XGET $bbk_remoteurl)"
 }

setzone () { 
curl -XPOST -d "zone=$zone" -d "status=$1" $bbk_apiurl &> /dev/null
 }

remotelocal_loop () {
while [ $bbk_remotestatus -eq 1 ] || [ $localstatus -ge 1 ]
do reinit_status && echo "[$logtag] sleeping 3-5 sec, reason: [remote: $bbk_remotestatus (zone=$zone). local: $localstatus"] | logger -p notice && sleep $[ ( $RANDOM % 5 ) + 3]s && multiple_bbk && reinit_status
done
 }


usage () { 
cat <<USAGE
How to use: $0 -4 or -6 must be specified.
    -d) Measure downstream
    -u) Measure upstream
    -4) Force IPv4 
    -6) Force IPv6
    -z) Set collision zone (1,2,3,4 or 5) to avoid colliding with probes within the same zone.
    -g) Use remote global collision zone for the probe. (Use this if you've configured the zone on your remote server)
Example: $ ./iperf3script -d -4 -z 1
USAGE
 }

options=':z:46duhg'
while getopts $options option
do
    case $option in
        z  ) zone=${OPTARG}     ;;
        g  ) zone=z	  	;;
        4  ) ip_version=4 	;;
	6  ) ip_version=6 && echo 'Not implemented yet' && exit 0 	;;
        d  ) direction=downstream       ;;
        u  ) direction=upstream       ;;
        h  ) usage; exit;;
        \? ) echo "Unknown option: -$OPTARG" >&2; exit 1;;
        :  ) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
        *  ) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
    esac
done

shift $(($OPTIND - 1))

if [ $ip_version = "x" ]; then echo "-4 or -6 must be specified, aborting" && exit 1
fi

logfacility=local3.debug
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 1 ))

# Daemon settings
if [ $direction = "upstream" ]; then logtag=chprobe_iperf3tcp_us[$(echo $count)]
tcpdaemon () {
/bin/iperf3 --client $target -4 -T $direction -P 15 -t 12 -O 2 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility
}

elif [ $direction = "downstream" ]; then logtag=chprobe_iperf3tcp_ds[$(echo $count)]
tcpdaemon () {
/bin/iperf3 --client $target -4 -T $direction -R -P 15 -t 12 -O 2 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility
}
        else echo 'No direction specified, exiting.' && exit 1
fi

### WiFi stuff
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep up /sys/class/net/wl*/operstate | wc -l)" # Detect wireless interface state
wififreq="$(iw $iwnic link | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
phydetect="$(iw $iwnic link | grep VHT | wc -l)" # What PHY? (Legacy is not supported)
#phy=$1 # Use argument instead for PHY instead

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

# Iperf daemon and condititions
start_iperf3 () {
while [ `pgrep -f 'bbk_cli|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk_cli|wrk" | awk '{print $1}') && echo "[$logtag] We're overloaded with daemons, killing everything" | logger -p local5.err ; done
#        while [ `pgrep -f 'bbk_cli|wrk' | wc -w` -ge 1 ];do sleep 0.5;done

# Call the remote loop
remotelocal_loop

# We check the status of the iperf3 server and again if another tcp test is running 
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -4 -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo "[$logtag] waiting cuz server is busy" | logger -p info;done && remotelocal_loop &&
    echo "[$logtag] Starting the tcp daemon - $direction" | logger -p info
    tcpdaemon && echo "[$logtag] tcp daemon finished" | logger -p info &&
        if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht && eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht && eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
;;
1)  echo "[$logtag] iperf tcp daemon is already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli|wrk' | wc -w` -ge 1 ];do sleep $[ ( $RANDOM % 5 ) + 3]s && echo "[$logtag] waiting cuz either an iperf3 or a bbk daemon is running" | logger -p info;done && remotelocal_loop &&
echo "[$logtag] Starting the tcp daemon - $direction" | logger -p info
    tcpdaemon && echo "[$logtag] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info &
        if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht && eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht && eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
;;
*)  echo "[$logtag] multiple instances of iperf3 daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
}

# Check zone variable and errors
if [ $zone = "1" ] || [ $zone = "2" ] || [ $zone = "3" ] || [ $zone = "4" ] || [ $zone = "5" ] || [ $zone = "z" ]; 
then reinit_status && bs=$(eval $bbk_remotestatusv2)
	if [ $bs -ne 200 ]; then echo "[$logtag] Zone is okay but it seems that we got a bad response, maybe the remote server is down? You should disable the zone for now" | logger -p local5.err && exit 1
	fi
			elif [ $zone = "x" ];then echo "[$logtag] No zone specified, other probes may collide with you" | logger -p notice && bbk_remotestatus=0
			  else
       			   echo "[$logtag] Invalid zone specified - $zone?" && exit 1
fi

# If global zone, then set necessary variables before going further
if [ $zone = "z" ];then echo "[$logtag] Using global zone" | logger -p notice && zone="$(curl -m 3 -s -XGET $globalzone_url)" && 

# Also reintroduce the urls now
reinit_status
fi

# Check if global zone is disabled
if [ $zone = "x" ];then echo "[$logtag] Seems that your global zone is disabled, hope this is what you want" | logger -p notice &&

# Change reinit function since we don't care about remote zone anymore
reinit_status () {
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
 }
bbk_remotestatus=0 
fi 

# Informational message
echo "Running tests, look for messages/errors in journal or in your logdir. The test result is saved at /var/log/chprobe_bbk.log"

# In case two or more tests are executed exactly at the same time, create some random delay
multiple_bbk () {
if [ $(pgrep -f 'iperf3tcp|tcp_iperf3' | wc -l) -ge 3 ]; then
	if [ $ip_version = "4" ]; then
	sleep $[ ( $RANDOM % 30 ) + 1]s
	      elif [ $ip_version = "6" ]; then
		sleep $[ ( $RANDOM % 30 ) + 1]s
	fi
fi
 }

# Make sure no other test of relevance is running and that our zone is clear before going further
if [ $bbk_remotestatus -eq 1 ] || [ $localstatus -ge 1 ]; then
	remotelocal_loop
		elif [ $bbk_remotestatus -eq 0 ] || [ $localstatus -eq 0 ]
                	then echo "[$logtag] Zone should be either clear or disabled ($zone/$bbk_remotestatus) and local status is ok as well, let's continue" | logger -p notice
                        	else echo "[$logtag] Unknown error, state returned: $? and bbk_remotestatus is $bbk_remotestatus" | logger -p notice && exit 1
fi

# Allocate the zone and start the desired test
        case "$ip_version" in
                4)
remotelocal_loop
setzone 1 && sleep 1 && echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice &&
start_iperf3 &&

# Set zone status to 0 when done
setzone 0 && sleep 1 && echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;
		6)
remotelocal_loop
setzone 1 && sleep 1 && echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice &&
start_iperf3 &&

# Set zone status to 0 when done
setzone 0 && sleep 1 && echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;

# Return error if ip version isn't specified
		x) echo "-4 or -6 must be specified, aborting" && exit 1
	esac

echo "Done."
