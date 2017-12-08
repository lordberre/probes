#!/bin/bash
# Version 2.45.0 (added udp support for high throughput use cases. IP targets are shared with tcp tests for coexist purposes)
# select-server fix for when global zone is disabled, changed dir temp files.
# Note: Some variables are named "bbk"-something since we're using the same zone functionallity

# New in 2.39.0: Fetch retransmits - Removed -T argument in iperf and using sed instead due to two columns. Also logstash needs rework
# iperf3 -c iperf.comhem.com -P 5 -t 5 -p 5210 -R | egrep 'SUM.*receiver|SUM.*sender|busy' | awk '{print $6,$8}' | tr -d ':|receiver' | xargs | sed -e "s/^/$direction /"
# New arguments/features in 2.44.0: Skip config files, force server, load probe-wide configuration for (for now just for target ip)

# Dont touch this
zone=x
ip_version=x
multivar=0
skip_configfile=false
forced_server=false

# For global zone, if you want something else than hostname, then edit below
probename="$(hostname -d)"

# Variables to load in case the config file is skipped or fails to load
# Default sessions: 15 sessions
# Default duration: 12 sec
declare -i chprobe_iperf3tcp_sessions=15
declare -i chprobe_iperf3tcp_duration=12
declare -i chprobe_iperf3tcp_omitduration=2

# Probe timer (default 5 sec) Note: This will be owerwritten if global zone is used
probetimer=5

# File used for storing target ip regardless of source (configuration or url)
cachefile="/var/chprobe/ip_tcp.txt"

# Standard protocol
protocol=tcp

# UDP high speed default settings
declare -i udp_bandwidth=50
declare -i chprobe_iperf3udp_sessions=2
declare -i chprobe_iperf3udp_length=60

# Ridrect flag
REDIRECT="/dev/null"

# Logdir
iperf3log="/var/log/iperf3udp.log"

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
# We only check abscence of bbk daemons, since the iperf3 server will take care of some collisions. It's a different story if more than one server is used in the same zone, this scenario is currently not supported
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
    -s) Skip loading configuration file (use only if you've got issues)
    -f) Force the server target (implies '-s'), must be used with server ip/hostname as argument, e.g: ./iperf3script -f x.x.x.x
    -p) Use udp protocol rather than tcp
    -b) Set bandwidth (udp only) - Input must be an INTEGER and in mbit/s (default is 100mbit)
Note: When using zones, your test might not start immediately
Example: $ ./iperf3script -d -4 -z 1
USAGE
 }

options=':z:f:b:46duhgsp'
while getopts $options option
do
    case $option in
        z  ) zone=${OPTARG}     ;;
        g  ) zone=z	  	;;
        p  ) protocol=udp       ;;
        b  ) bandwidth=${OPTARG};udp_bandwidth=`expr $bandwidth / $chprobe_iperf3udp_sessions`       ;;
        4  ) ip_version=4 	;;
	6  ) ip_version=6 && echo 'Not implemented yet' && exit 0 	;;
        d  ) direction=downstream       ;;
        u  ) direction=upstream       ;;
        s  ) skip_configfile=true;chprobe_iperf3tcp_target=disable       ;;
        f  ) skip_configfile=true;forced_server=true;chprobe_iperf3tcp_target=${OPTARG}       ;;
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

# Load configuration file
if [ $skip_configfile = "false" ]; then
source /var/chprobe/$(hostname -d).cfg || skip_configfile=true

# Also update the cache file, in case the script was run with '-s' or '-f' in between configuration commits
echo $chprobe_iperf3tcp_target > $cachefile
fi

if [ $chprobe_iperf3tcp_target = "disable" ] 2> $REDIRECT; then
# Use cached ip if remote server is not responding
# Remote url stuff
ipfile="ip.txt"
remoteurl_vars () {
ip_url="http://project-mayhem.se/probes/$1"
urlz="curl -m 3 --retry 2 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
urlcheck=$(eval $urlz)
}


# Select server to use
select_server () {
if [ $zone != "z" ]; then
# Use cached ip if remote server is not responding
	remoteurl_vars $ipfile
	if [ $urlcheck -ne 200 ]; then target="$(cat $cachefile)"
        else target="$(curl -m 3 --retry 2 -s $ip_url)" && curl -m 3 --retry 2 -s -o $cachefile $ip_url
	fi
else : # Do nothing, our server will be determined by our zone
fi
}
select_server 2> $REDIRECT
fi

# Daemon settings

serverbusy_loop () {
while iperf3 -c $target -4 -t 1 | grep busy; do
sleep $[ ( $RANDOM % $probetimer ) + 3]s && echo "[$logtag] waiting cuz server is busy" | logger -p info
done
remotelocal_loop
}


# Protocol

if [ $protocol = tcp ];then
 if [ $direction = "upstream" ]; then logtag=chprobe_iperf3tcp_us[$(echo $count)]
 iperf_daemon () {
 /usr/bin/iperf3 --client $target -4 -P $chprobe_iperf3tcp_sessions -t $chprobe_iperf3tcp_duration -O $chprobe_iperf3tcp_omitduration | egrep 'SUM.*receiver|SUM.*sender|busy' | awk '{print $6,$8}' | tr -d ':|receiver' | xargs | sed -e "s/^/$direction /" | logger -t iperf3tcp[$(echo $count)] -p $logfacility
 }

 elif [ $direction = "downstream" ]; then logtag=chprobe_iperf3tcp_ds[$(echo $count)]
 iperf_daemon () {
 /usr/bin/iperf3 --client $target -4 -R -P $chprobe_iperf3tcp_sessions -t $chprobe_iperf3tcp_duration -O $chprobe_iperf3tcp_omitduration | egrep 'SUM.*receiver|SUM.*sender|busy' | awk '{print $6,$8}' | tr -d ':|receiver' | xargs | sed -e "s/^/$direction /" | logger -t iperf3tcp[$(echo $count)] -p $logfacility
 }
 fi

elif [ $protocol = udp ];then logfacility=local4.debug 

 if [ $direction = "upstream" ]; then logtag=chprobe_iperf3highudp_us[$(echo $count)]
 iperf_daemon () {
 /usr/bin/iperf3 --client $target -4 -u -T $direction -b ${udp_bandwidth}m -P $chprobe_iperf3udp_sessions -t $chprobe_iperf3udp_length | egrep 'iperf Done|iperf3: error' -B 3 | egrep "0.00-${chprobe_iperf3udp_length}.00|busy" | grep -v sender | awk '{print $1,$5,$7,$9,$12,$14}' | tr -d '(%)|:' | logger -t iperf3udp[$(echo $count)] -p $logfacility
 }

 elif [ $direction = "downstream" ]; then logtag=chprobe_iperf3highudp_ds[$(echo $count)]
 iperf_daemon () {
 /usr/bin/iperf3 --client $target -4 -u -T $direction -b ${udp_bandwidth}m -R -P $chprobe_iperf3udp_sessions -t $chprobe_iperf3udp_length | egrep 'iperf Done|iperf3: error' -B 3 | egrep "0.00-${chprobe_iperf3udp_length}.00|busy" | grep -v sender | awk '{print $1,$5,$7,$9,$12,$14}' | tr -d '(%)|:' | logger -t iperf3udp[$(echo $count)] -p $logfacility
 }
        else echo 'No direction specified, exiting.' && exit 1
 fi
fi

# Make sure that the test is performed and not "skipped" due to the server becoming busy after we exited the first busy loop
busy_failcheck () {
checkbusy="$(tail -1 $iperf3log | grep $count | grep later | wc -l)"
busyfail=0
while [ $checkbusy -eq 1 ]; do
echo "[$logtag] Everything seemed ok but we didn't run any test, looping until server is not busy ($busyfail)" | logger -p info && 
sleep $[ ( $RANDOM % 20 ) + 11]s && 
iperf_daemon
checkbusy="$(tail -1 $iperf3log | grep $count | grep later | wc -l)"

# Anti fail
busyfail=$(( $busyfail + 1 ))
if [ $busyfail -ge 20 ]; then
echo "[$logtag] Giving up, since we didn't manage to access the server for over $busyfail retries. How can it be this busy?" | logger -p local5.err && break
fi
done
}

### WiFi stuff
iwnic=$(ifconfig 2> $REDIRECT | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep up /sys/class/net/wl*/operstate 2> $REDIRECT | wc -l)" # Detect wireless interface state
wififreq="$(iw $iwnic link 2> $REDIRECT | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
phydetect="$(iw $iwnic link 2> $REDIRECT | grep VHT | wc -l)" # What PHY? (Legacy is not supported)
#phy=$1 # Use argument instead for PHY instead

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

# If global zone, then set necessary variables before going further.
if [ $zone = "z" ];then echo "[$logtag] Using global zone" | logger -p notice && zone="$(curl -m 3 --retry 2 -s -XGET $globalzone_url)"

# Go into offline mode if the remote server is inresponsive
if [ $? -ne 0 ]; then
zone=x && echo "[$logtag] Zone disabled due to remote server errors ($?). We're in offline mode" | logger -p local5.err && target="$(cat $cachefile)" && probetimer="$(cat /var/chprobe/probe_timer.txt)"
fi

# Sleep for a unique time and then reintroduce urls
remotelocal_loop; sleep $probetimer; remotelocal_loop
fi

if [ $chprobe_iperf3tcp_target = "disable" ] 2> $REDIRECT; then
# Run the remote check, then use a unique timer to better avoid collisionss
	if [ $zone != "x" ]; then
	ip_url="http://project-mayhem.se/probes/$(hostname -d)_timer.txt"
	urlz="curl -m 3 --retry 2 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
	urlcheck=$(eval $urlz)

# Use cached ip if remote server is not responding
	if [ $urlcheck -ne 200 ]; then probetimer="$(cat /var/chprobe/probe_timer.txt)" || probetimer=5
        else probetimer="$(curl -m 3 --retry 2 -s $ip_url)" &&
	curl -m 3 --retry 2 -s -o /var/chprobe/probe_timer.txt $ip_url

# Also use zone specific server
 	remoteurl_vars zone$zone-server && target="$(curl -m 3 --retry 2 -s $ip_url)" &&
	curl -m 3 --retry 2 -s -o /var/chprobe/ip_tcp.txt $ip_url
	fi
	fi
elif [ $forced_server = "true" ]; then target=$chprobe_iperf3tcp_target
else target="$(cat $cachefile)" # Use server from configuration file
fi

# Check if global zone is disabled
if [ $zone = "x" ];then echo "[$logtag] Seems that your global zone is disabled, hope this is what you want" | logger -p notice &&

# Select server since we skipped it earlier (script was ran with -g)
select_server

# Change reinit function since we don't care about remote zone anymore
reinit_status () {
localstatus="$(pgrep -f 'bbk_cli|wrk|iperf3 --client' | wc -l)"
 }
bbk_remotestatus=0
fi

# Iperf daemon and condititions
start_iperf3 () {
while [ `pgrep -f 'bbk_cli|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk_cli|wrk" | awk '{print $1}') && echo "[$logtag] We're overloaded with daemons, killing everything" | logger -p local5.err ; done

# Call the remote loop
remotelocal_loop

# We check the status of the iperf3 server and again if another test is running 
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the daemon" | logger -p info
    serverbusy_loop
    echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
    setzone 1; iperf_daemon;busy_failcheck && echo "[$logtag] daemon finished" | logger -p info &&
        if [ $iwdetect -gt 0 ] 2> $REDIRECT; then
            if [ $wififreq -lt 2500 ] 2> $REDIRECT; then phy=ht && eval $htparse;else
                    if [ $phydetect -ge 1 ] 2> $REDIRECT; then phy=vht && eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
;;
1)  echo "[$logtag] iperf daemon is already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli|wrk' | wc -w` -ge 1 ];do remotelocal_loop; sleep $[ ( $RANDOM % $probetimer ) + 3]s; remotelocal_loop && echo "[$logtag] waiting cuz either an iperf3 or a bbk daemon is running" | logger -p info;done
	    serverbusy_loop
    echo "[$logtag] Starting $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
    setzone 1; iperf_daemon;busy_failcheck && echo "[$logtag] daemon finished" | logger -p info
        if [ $iwdetect -gt 0 ] 2> $REDIRECT; then
            if [ $wififreq -lt 2500 ] 2> $REDIRECT; then phy=ht && eval $htparse;else
                    if [ $phydetect -ge 1 ] 2> $REDIRECT; then phy=vht && eval $vhtparse;else phy=ht eval $htparse;fi;fi
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
echo "Running tests, look for messages/errors in journal or in your logdir. The test result is saved at /var/log/chprobe_iperf3\${PROTOCOL}.log"

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

unique_sleep () {
if [ $zone != "x" ];then
remotelocal_loop;sleep $probetimer;remotelocal_loop
else remotelocal_loop
fi
}

# Allocate the zone and start the desired test
        case "$ip_version" in
                4)
unique_sleep
start_iperf3 &&

# Set zone status to 0 when done
setzone 0; echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;
		6)
unique_sleep
start_iperf3 &&

# Set zone status to 0 when done
setzone 0; echo "[$logtag] Finished $logtag [debug: $localstatus | $(pgrep -f 'bbk_cli|iperf3 --client' | wc -l)]" | logger -p notice
;;

# Return error if ip version isn't specified
		x) echo "-4 or -6 must be specified, aborting" && exit 1
	esac

echo "Done."
