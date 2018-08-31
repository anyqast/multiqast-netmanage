#!/usr/bin/env bash

cd /tmp

function log() {
    echo "$(date -u) ${*}"
}

function ip2long() {
	local o1 o2 o3 o4 IFS
	IFS=. read -r o1 o2 o3 o4 <<< "${1}"
	echo -n "$(($((${o4}))+$((${o3}*256))+$((${o2}*256*256))+$((${o1}*256*256*256))))"
}
function long2ip() {
	echo -n "$((${1}>>24&255)).$((${1}>>16&255)).$((${1}>>8&255)).$((${1}&255))"
}

PRIMARY_IP4=$(ip route get 255.255.255.255 | tr -s ' ' | grep -oE 'src [0-9\.]+' | cut -d' ' -f2)
PRIMARY_IP6=$(ip route get ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff | tr -s ' ' | grep -oE 'src [0-9a-f:]+' | cut -d' ' -f2)

function iptrb() {
	while "${@}" 2> /dev/null; do true; done
}

iptrb iptables  -t raw -D PREROUTING -j NOTRACK
iptrb ip6tables -t raw -D PREROUTING -j NOTRACK

iptrb iptables  -t raw -D OUTPUT -j NOTRACK
iptrb ip6tables -t raw -D OUTPUT -j NOTRACK

iptrb iptables  -t raw -D PREROUTING -i lo -j ACCEPT
iptrb ip6tables -t raw -D PREROUTING -i lo -j ACCEPT

iptrb iptables  -t raw -D PREROUTING -m set --match-set managed4 dst -m set ! --match-set v4 dst,dst -j DROP
iptrb ip6tables -t raw -D PREROUTING -m set --match-set managed6 dst -m set ! --match-set v6 dst,dst -j DROP

ipset create v4 hash:ip,port family inet
ipset create v6 hash:ip,port family inet6
ipset create managed4 hash:net family inet
ipset create managed6 hash:net family inet6

iptables  -t raw -A PREROUTING -j NOTRACK
ip6tables -t raw -A PREROUTING -j NOTRACK

iptables  -t raw -A OUTPUT -j NOTRACK
ip6tables -t raw -A OUTPUT -j NOTRACK

iptables  -t raw -A PREROUTING -i lo -j ACCEPT
ip6tables -t raw -A PREROUTING -i lo -j ACCEPT

iptables  -t raw -A PREROUTING -m set --match-set managed4 dst -m set ! --match-set v4 dst,dst -j DROP
ip6tables -t raw -A PREROUTING -m set --match-set managed6 dst -m set ! --match-set v6 dst,dst -j DROP

echo 1 > /proc/sys/net/ipv4/ip_nonlocal_bind
echo 1 > /proc/sys/net/ipv6/ip_nonlocal_bind

function parse_neighbor() {
	local bgptype bgpaddr bgpas bgppass IFS=','
	read bgptype bgpaddr bgpas bgppass <<< "${2}"
	echo "protocol bgp bgp${1} from ${bgptype}bgp {"
	echo "	neighbor ${bgpaddr} as ${bgpas};"
	test -n "${bgppass}" && echo '	password "'"${bgppass}"'";'
	echo "}"
}

bgpid=0

for bgpneigh in ${BGP_NEIGHBORS}; do
	bgpid="$((${bgpid}+1))"
	parse_neighbor "${bgpid}" "${bgpneigh}" > "/etc/bird.d/bgp${bgpid}.conf"
done

tmptable=$(head -c128 /dev/urandom | md5sum | head -c 8)

ipset create "${tmptable}-managed4" hash:net family inet
ipset create "${tmptable}-managed6" hash:net family inet6

(
	echo "protocol static static4 {"
	echo "	ipv4 {"
	echo "		import none;"
	echo "	};"
	echo "	disabled on;"
	for bgpprefix in ${BGP_PREFIXES}; do
		echo "${bgpprefix}" | fgrep -q . && echo "	route ${bgpprefix} unreachable;" && ipset add "${tmptable}-managed4" "${bgpprefix}" 1>&2
	done
	echo "}"
) > "/etc/bird.d/static4.conf"

(
	echo "protocol static static6 {"
	echo "	ipv6 {"
	echo "		import none;"
	echo "	};"
	echo "	disabled yes;"
	for bgpprefix in ${BGP_PREFIXES}; do
		echo "${bgpprefix}" | fgrep -q : && echo "	route ${bgpprefix} unreachable;" && ipset add "${tmptable}-managed6" "${bgpprefix}" 1>&2
	done
	echo "}"
) > "/etc/bird.d/static6.conf"

ipset swap "managed4" "${tmptable}-managed4"
ipset swap "managed6" "${tmptable}-managed6"

ipset destroy "${tmptable}-managed4"
ipset destroy "${tmptable}-managed6"

if test "${MANAGED_ROUTES}" == "static"; then
	ip link add dummy0 type dummy
	log "Adding (static) prefixes ..."
	for bgpprefix in ${BGP_PREFIXES}; do
		log "... ${bgpprefix}"
		ip route add local "${bgpprefix}" dev dummy0
	done
fi

cat "/etc/bird.conf.tpl" | sed "s|{{BGP_AS}}|${BGP_AS}|g;s|{{ROUTER_ID}}|${PRIMARY_IP4}|g" > "/etc/bird.d/bird"

exec "/usr/bin/supervisord" "-kc/etc/supervisord.conf"
