class_name NetUpnp
extends Node
## UPnP port mapping, so a host does not need to forward a port by hand. Split
## out of Net because it shares nothing with the rest of it: no RPCs, no
## registry, just a router being asked nicely on a worker thread.
##
## A Node rather than a plain object because the work is threaded and the
## results have to land back on the main thread — `call_deferred` needs
## somewhere to land, and the mapping has to be torn down on the way out.
## Failure is a NORMAL state: LAN joins still work, so nothing here is an error.

signal status_changed(status: String, ip: String)

## 24h lease: if the server is force-killed and never cleans up, the router
## drops the mapping on its own. Some routers reject leases -> permanent
## fallback, which the explicit cleanup below then handles on normal exits.
const LEASE := 86400

var status := "inactive"  # inactive / searching / ok / failed
var public_ip := ""

var _thread: Thread
var _cleanup_thread: Thread
var _mapper = null    # UPNP instance that owns the active mapping
var _mapped_port := 0 # 0 = nothing mapped on the router right now

func _exit_tree() -> void:
	_join(_thread)
	_join(_cleanup_thread)
	remove_mapping(true) # blocking: the app is quitting

static func _join(t: Thread) -> void:
	if t and t.is_started():
		t.wait_to_finish()

func start(port: int) -> void:
	if not ClassDB.class_exists("UPNP"):
		_finish("failed", "")
		return
	if _thread and _thread.is_started():
		if _thread.is_alive():
			return # previous attempt still running
		_thread.wait_to_finish()
	status = "searching"
	_thread = Thread.new()
	_thread.start(_worker.bind(port))

func _worker(port: int) -> void:
	var upnp := UPNP.new()
	if upnp.discover() != UPNP.UPNP_RESULT_SUCCESS or upnp.get_device_count() == 0 \
			or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		call_deferred("_finish", "failed", "")
		return
	var udp := _map(upnp, port, "UDP")
	_map(upnp, port, "TCP")
	var ip := upnp.query_external_address()
	if udp == UPNP.UPNP_RESULT_SUCCESS and not ip.is_empty():
		# set from the worker thread so a quit right after hosting can still
		# clean up after wait_to_finish (the deferred call may never run)
		_mapper = upnp
		_mapped_port = port
		call_deferred("_finish", "ok", ip)
	else:
		call_deferred("_finish", "failed", ip)

## Ask for the leased mapping, falling back to a permanent one on a router that
## refuses leases.
static func _map(upnp: UPNP, port: int, proto: String) -> int:
	var r := upnp.add_port_mapping(port, port, "Astria", proto, LEASE)
	if r != UPNP.UPNP_RESULT_SUCCESS:
		r = upnp.add_port_mapping(port, port, "Astria", proto, 0)
	return r

## Take the router mapping down: async normally, blocking when quitting.
func remove_mapping(blocking: bool) -> void:
	if _mapped_port == 0 or _mapper == null:
		return
	var mapper = _mapper
	var port := _mapped_port
	_mapper = null
	_mapped_port = 0
	var drop := func() -> void:
		mapper.delete_port_mapping(port, "UDP")
		mapper.delete_port_mapping(port, "TCP")
		print("[Net] UPnP mapping for port %d removed" % port)
	if blocking:
		drop.call()
		return
	_join(_cleanup_thread)
	_cleanup_thread = Thread.new()
	_cleanup_thread.start(drop)

func reset() -> void:
	remove_mapping(false)
	status = "inactive"
	public_ip = ""

func _finish(new_status: String, ip: String) -> void:
	status = new_status
	public_ip = ip
	if new_status == "ok":
		print("[Net] UPnP OK — friends can join at %s" % ip)
	else:
		print("[Net] UPnP unavailable — LAN joins still work; internet play needs a manual UDP port forward")
	status_changed.emit(new_status, ip)
