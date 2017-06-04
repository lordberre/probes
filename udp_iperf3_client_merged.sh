#!/bin/bash
# Version 1.1

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
target="$(curl -s project-mayhem.se/probes/ip-udp.txt)"
count=$(( ( RANDOM % 9999 )  + 1 ))

# Daemon settings
if [ $direction = "upstream" ]; then
udpdaemon="/usr/bin/iperf3 --client \$target -u -T \$direction -b \${arr[\$rand]} -t 60 -p \${portz[\$randport]} | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"

elif [ $direction = "downstream" ]; then
udpdaemon="/usr/bin/iperf3 --client \$target -u -T \$direction -R -b \${arr[\$rand]} -t 60 -p \${portz[\$randport]} | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"
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
arr[0]="5m"
arr[1]="10m"
arr[2]="20m"
rand=$[ $RANDOM % 3 ]

# Randomize ports to connect to.
portz[0]="5210"
portz[1]="5215"
portz[2]="5220"
randport=$[ $RANDOM % 3 ]


# Run tests and avoid collisions
while [ `pgrep -f 'bbk_cli|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk_cli|wrk" | awk '{print $1}') && echo "[chprobe_error] We're overloaded with daemons, killing everything" | logger -p local5.err ; done
        while [ `pgrep -f 'bbk_cli|tcp_iperf3' | wc -w` -ge 1 ];do echo "[$logtag] Some test is running, waiting." | logger -p info && sleep 2;done
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the udp daemon" | logger -p info
    while iperf3 -c $target -p ${portz[$randport]} -t 1 | grep busy; do randport=$[ $RANDOM % 3 ] && sleep $[ ( $RANDOM % 10 ) + 3]s && echo "[$logtag] server is busy. We slept a bit, now rolling the dice for the port" | logger -p info;done
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
