#!/bin/bash
# Version 1.47.0. Added configuration file support for stream bandwidths and length
# Also fix for iperf 3.3+ parse issue

while true
do
        case "$1" in
	-ds) direction="downstream" && break ;;
	-us) direction="upstream" && break ;;
	-h)  cat <<USAGE
usage: $0 [-ds] [-us] [-h]

    -h) See this help
    -us) Upstream UDP test
    -ds) Downstream UDP test
USAGE
            exit 1
            ;;
        *)
            echo Use -h for help!
            exit 1;
            ;;
    esac;done

logfacility=local4.debug
logtag=chprobe_iperf3udp
count=$(( ( RANDOM % 9999 )  + 1 ))

# Default settings
declare -i chprobe_iperf3udp_stream_b1=5
declare -i chprobe_iperf3udp_stream_b2=10
declare -i chprobe_iperf3udp_stream_b3=20
declare -i chprobe_iperf3udp_stream_t1=60
declare -i chprobe_iperf3udp_stream_t2=60
declare -i chprobe_iperf3udp_stream_t3=60

# Load configuration file
source /var/chprobe/$(hostname -d).cfg

# Remote url stuff
ip_url="http://project-mayhem.se/probes/ip-udp.txt"
urlz="curl -m 3 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
urlcheck=$(eval $urlz)

# Use cached ip if remote server is not responding
if [ $urlcheck -ne 200 ]; then target="$(cat /var/chprobe/ip-udp.txt)"
        else target="$(curl -m 3 -s $ip_url)"
fi

# Check if the target file actually contains any data.. If yes, save it in cache and use it.
if [ -z $target ]; then target="$(cat /var/chprobe/ip-udp.txt)" # Otherwise just use cache file
 else curl -m 3 -s -o /var/chprobe/ip-udp.txt $ip_url
fi

# Daemon settings
if [ $direction = "upstream" ]; then
udpdaemon="/usr/bin/iperf3 -u --client \$target -T \$direction -b \${arr[\$rand]}m -t \$DURATION -p \${portz[\$randport]} | egrep 'iperf Done' -B 3 | egrep 0.00-\$DURATION | grep -v sender | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"

elif [ $direction = "downstream" ]; then
udpdaemon="/usr/bin/iperf3 -u --client \$target -T \$direction -R -b \${arr[\$rand]}m -t \$DURATION -p \${portz[\$randport]} | egrep 'iperf Done' -B 3 | egrep 0.00-\$DURATION | grep -v sender | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"
	else echo 'No direction specified, exiting.' && exit 1
fi

### WiFi stuff
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep up /sys/class/net/wl*/operstate | wc -l)" # Detect wireless interface state
wififreq="$(iw $iwnic link | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
phydetect="$(iw $iwnic link | grep VHT | wc -l)" # What PHY? (Legacy is not supported)
#phy=$1 # Use argument for PHY instead

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

# Randomize stream bandwidth.
arr[0]="$chprobe_iperf3udp_stream_b1"
arr[1]="$chprobe_iperf3udp_stream_b2"
arr[2]="$chprobe_iperf3udp_stream_b3"
rand=$[ $RANDOM % 3 ]

# Randomize ports to connect to.
portz[0]="5210"
portz[1]="5215"
portz[2]="5220"
portz[3]="5225"
portz[4]="5230"
portz[5]="5235"
randport=$[ $RANDOM % 6 ]

# Only go into anti-collision loop if the bandwidth is 20 mbit or higher
if [ ${arr[$rand]} -ge 20 ]; then udp_anticollision=1
else udp_anticollision=0
fi

# Assign configured durations
if [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b1 ]; then DURATION=$chprobe_iperf3udp_stream_t1
elif [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b2 ]; then DURATION=$chprobe_iperf3udp_stream_t2
elif [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b3 ]; then DURATION=$chprobe_iperf3udp_stream_t3
fi

# Run tests and avoid collisions
while [ `pgrep -f 'bbk|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk|wrk" | awk '{print $1}') && echo "[chprobe_error] We're overloaded with daemons, killing everything" | logger -p local5.err ; done
	if [ $udp_anticollision -eq 1 ]; then
        	while [ `pgrep -f 'bbk|tcp_iperf3|iperf3tcp' | wc -w` -ge 1 ];do echo "[$logtag] bbk or iperf3tcp is running, waiting." | logger -p info && sleep 3
		done
	fi
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the udp daemon" | logger -p info
    while iperf3 -c $target -p ${portz[$randport]} -t 1 | grep busy; do randport=$[ $RANDOM % 6 ] && sleep $[ ( $RANDOM % 10 ) + 3]s && echo "[$logtag] server is busy. We slept a bit, now rolling the dice for the port" | logger -p info;done
    echo "[$logtag] udp daemon started - $direction" | logger -p info
	eval $udpdaemon &
	if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht & eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi    
;;
1)  echo "[$logtag] iperf daemon already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli' | wc -w` -ge 1 ];do sleep $[ ( $RANDOM % 5 ) + 3]s && echo "[$logtag] waiting cuz either an iperf3 or a bbk daemon is running" | logger -p info;done    
echo "[$logtag] udp daemon started - $direction" | logger -p info
	        eval $udpdaemon &
    if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht & eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi	
;;
*)  echo "[$logtag] multiple instances of iperf3 udp daemons currently running." | logger -p info
#    kill $(pgrep -f "iperf3 --client" | awk '{print $1}') # Disabled to allow bidirectional UDP tests
    ;;
esac;
