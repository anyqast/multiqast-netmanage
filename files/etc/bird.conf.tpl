log stderr all;
router id {{ROUTER_ID}};
debug protocols { states, interfaces, events };
debug latency on;
debug latency limit 5 s;
watchdog warning 5 s;
watchdog timeout 30 s;
ipv4 table master4;
ipv6 table master6;
template bgp xbgp {
	ipv4 {
		add paths on;
		next hop self on;
		import none;
		export none;
	};
	ipv6 {
		add paths on;
		next hop self on;
		import none;
		export none;
	};
	graceful restart off;
	local as {{BGP_AS}};
	path metric off;
	igp metric off;
	allow local as;
	multihop;
	interpret communities off;
	error wait time 1,1;
	error forget time 1;
	keepalive time 1;
	startup hold time 60;
	hold time 30;
	connect delay time 5;
	connect retry time 60;
	enable route refresh on;
}
template bgp externalbgp from xbgp {
	ipv4 {
		add paths rx;
		export filter {
			if proto ~ "static4" then accept;
			reject;
		};
		preference 100;
	};
	ipv6 {
		add paths rx;
		export filter {
			if proto ~ "static6" then accept;
			reject;
		};
		preference 100;
	};
}
template bgp internalbgp from xbgp {
	rr client;
	enable extended messages on;
	graceful restart on;
	graceful restart time 3600;
	startup hold time 3600;
	hold time 3600;
	ipv4 {
		add paths tx;
		preference 200;
		export filter {
			if proto ~ "static4" then reject;
			accept;
		};
	};
	ipv6 {
		add paths tx;
		preference 200;
		export filter {
			if proto ~ "static6" then reject;
			accept;
		};
	};
}
include "/etc/bird.d/*.conf";
