#!/bin/bash
# Version 2.38.2 (BBK/zone integration) "wow will this even work"
# Note: Some variables are named "bbk"-something since we're using the same zone functionallity

# Dont touch this
zone=x
ip_version=x
multivar=0

# For global zone, if you want something else than hostname, then edit below
probename="$(hostname -d)"

# Probe timer (default 5 sec) Note: This will be owerwritten if global zone is used
probetimer=5

# Should the script continue even if remote server is inresponsive? Default is true
force_start=true

# Link to bbk_api
bbk_apiurl="http://project-mayhem.se/probes/bbk_api.php"

# Functions and variables
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
bbk_remotestatusv2="curl -m 3 --retry 2 -s -o /dev/null -w \"%{http_code}\" \$bbk_apiurl"
globalzone_url="http://project-mayhem.se/probes/bbkzone_$probename"

reinit_status () {
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
bbk_remoteurl="http://project-mayhem.se/probes/bbk_status_zone-$zone"
bbk_remotestatus="$(curl -m 3 --retry 2 -s -XGET $bbk_remoteurl)"
 }

# In case two or more tests are executed exactly at the same time, create some random delay
# We only check abscence of bbk daemons, since the iperf3 server will take care of some collisions. It's a different story if more than one server is used in the same zone, this scenario currently not supported
multiple_bbk () {
if [ $(pgrep -f 'bbk' | wc -l) -ge 3 ] || [ $multivar -eq 1 ]; then
        if [ $ip_version = "4" ]; then
                if [ $multivar -eq 1 ]; then
                reinit_status; sleep $[ ( $RANDOM % 20 ) + $probetimer]s; reinit_status
                else
                reinit_status; sleep $[ ( $RANDOM % 20 ) + 1]s; reinit_status
                fi
                        elif [ $ip_version = "6" ]; then
                                if [ $multivar -eq 1 ]; then
                                reinit_status; sleep $[ ( $RANDOM % 30 ) + $probetimer]s; reinit_status
                                else
                        reinit_status; sleep $[ ( $RANDOM % 10 ) + 1]s; reinit_status
                                fi
        fi
else reinit_status
fi
 }

setzone () {
if [ $zone = "1" ] || [ $zone = "2" ] || [ $zone = "3" ] || [ $zone = "4" ] || [ $zone = "5" ]; then
curl -m 3 -s --retry 2 -XPOST -d "zone=$zone" -d "status=$1" $bbk_apiurl &> /dev/null && sleep 1
fi
 }

remotelocal_loop () {
# if [ $zone != "x" ]; then
#sleep $probetimer && reinit_status
#else
reinit_status
#fi
while [ $bbk_remotestatus -eq 1 ] || [ $localstatus -ge 1 ]
do reinit_status; echo "[$logtag] sleeping 3-$probetimer sec, reason: [remote: $bbk_remotestatus (zone=$zone). local: $localstatus"] | logger -p notice && sleep $[ ( $RANDOM % $probetimer ) + 3]s; multiple_bbk; reinit_status
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
Note: When using zones, your test might not start immediately
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
count=$(( ( RANDOM % 9999 )  + 1 ))

# Use cached ip if remote server is not responding
# Remote url stuff
ipfile="ip.txt"
cachefile="/var/ip_tcp.txt"
remoteurl_vars () {
ip_url="http://project-mayhem.se/probes/$1"
urlz="curl -m 3 --retry 2 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
urlcheck=$(eval $urlz)
}

# Select server to use
if [ $zone != "z" ]; then
# Use cached ip if remote server is not responding
	remoteurl_vars $ipfile
	if [ $urlcheck -ne 200 ]; then target="$(cat $cachefile)"
        else target="$(curl -m 3 --retry 2 -s $ip_url)" && curl -m 3 --retry 2 -s -o $cachefile $ip_url
	fi
else : # Do nothing, our server will be determined by our zone
fi

# Daemon settings
if [ $direction = "upstream" ]; then logtag=chprobe_iperf3tcp_us[$(echo $count)]
tcpdaemon () {
/bin/iperf3 --client $target -4 -T $direction -P 15 -t 12 -O 2 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility
}

elif [ $direction = "downstream" ]; then logtag=chprobe_iperf3tcp_ds[$(echo $count)]
tcpdaemon () {
/bin/iperf3 --client $target -4 -T $direction -R -P 15 -t 12 -O 2 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility
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

# Check if global zone is disabled
if [ $zone = "x" ];then echo "[$logtag] Seems that your global zone is disabled, hope this is what you want" | logger -p notice &&

# Change reinit function since we don't care about remote zone anymore
reinit_status () {
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
 }
bbk_remotestatus=0
fi

# If global zone, then set necessary variables before going further
if [ $zone = "z" ];then echo "[$logtag] Using global zone" | logger -p notice && zone="$(curl -m 3 --retry 2 -s -XGET $globalzone_url)"

# Run the remote check, then use a unique timer to better avoid collisionss
ip_url="http://project-mayhem.se/probes/$(hostname -d)_timer.txt"
urlz="curl -m 3 --retry 2 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
urlcheck=$(eval $urlz)

# Use cached ip if remote server is not responding
if [ $urlcheck -ne 200 ]; then probetimer="$(cat /var/prober_timer.txt)"
        else probetimer="$(curl -m 3 --retry 2 -s $ip_url)" && curl -m 3 --retry 2 -s -o /var/probe_timer.txt $ip_url

# Also use zone specific server
remoteurl_vars zone$zone-server && target="$(curl -m 3 --retry 2 -s $ip_url)" && curl -m 3 --retry 2 -s -o /var/ip_tcp.txt $ip_url
fi

# Sleep for a unique time and then reintroduce urls
remotelocal_loop; sleep $probetimer; remotelocal_loop
fi

# Iperf daemon and condititions
start_iperf3 () {
while [ `pgrep -f 'bbk_cli|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk_cli|wrk" | awk '{print $1}') && echo "[$logtag] We're overloaded with daemons, killing everything" | logger -p local5.err ; done

# Call the remote loop
remotelocal_loop

# We check the status of the iperf3 server and again if another tcp test is running 
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -4 -t 1 | grep busy; do remotelocal_loop; sleep $[ ( $RANDOM % $probetimer ) + 3]s;remotelocal_loop && echo "[$logtag] waiting cuz server is busy" | logger -p info;done; remotelocal_loop &&
    echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
    setzone 1; tcpdaemon && echo "[$logtag] tcp daemon finished" | logger -p info &&
        if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht && eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht && eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
;;
1)  echo "[$logtag] iperf tcp daemon is already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli|wrk' | wc -w` -ge 1 ];do remotelocal_loop; sleep $[ ( $RANDOM % $probetimer ) + 3]s; remotelocal_loop && echo "[$logtag] waiting cuz either an iperf3 or a bbk daemon is running" | logger -p info;done && remotelocal_loop &&
    echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
    setzone 1; tcpdaemon && echo "[$logtag] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info
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
then reinit_status; bs=$(eval $bbk_remotestatusv2)
	if [ $bs -ne 200 ]; then echo "[$logtag] It seems that we got a bad response, maybe the remote server is down? Treating zone as disabled (x) and running test anyway" | logger -p local5.err && zone=x && target="$(cat $cachefile)"
	else multivar=1 && multiple_bbk
	fi
			elif [ $zone = "x" ];then echo "[$logtag] No zone specified, other probes may collide with you" | logger -p notice && bbk_remotestatus=0
			  else
       			   echo "[$logtag] Invalid zone specified - $zone?" && exit 1
fi

# Informational message
echo "Running tests, look for messages/errors in journal or in your logdir. The test result is saved at /var/log/chprobe_bbk.log"

# Make sure no other test of relevance is running and that our zone is clear before going further
if [ $bbk_remotestatus -eq 1 ] || [ $localstatus -ge 1 ]; then
        remotelocal_loop
                elif [ $bbk_remotestatus -eq 0 ] || [ $localstatus -eq 0 ]
                        then echo "[$logtag] Zone should be either clear or disabled ($zone/$bbk_remotestatus) and local status is ok as well, let's continue" | logger -p notice
                                else echo "[$logtag] Unknown error, state returned: $? and bbk_remotestatus is $bbk_remotestatus" | logger -p notice
                                        if [ $force_start = "true" ]
                                        then echo "[$logtag] Starting test anyway (force_start is set to: $force_start)" | logger -p notice
                                                else echo "[$logtag] Aborting due to remote server errors. (for debugging: $bbk_remotestatus,$zone,$localstatus,$force_start)" | logger -p local5.err && exit 1
                                        fi
fi

# Allocate the zone and start the desired test
        case "$ip_version" in
                4)
remotelocal_loop
start_iperf3 &&

# Set zone status to 0 when done
setzone 0; echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;
		6)
remotelocal_loop
start_iperf3 &&

# Set zone status to 0 when done
setzone 0; echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;

# Return error if ip version isn't specified
		x) echo "-4 or -6 must be specified, aborting" && exit 1
	esac

echo "Done."
