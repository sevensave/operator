class_name Transport
extends RefCounted
## Транспорт пакетов. Сейчас ENet (UDP, один порт); интерфейс позволяет подменить его
## на WebSocket за nginx, не трогая остальной код.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal packet(id: int, data: PackedByteArray)
signal connected
signal connection_failed

var peer: ENetMultiplayerPeer
var is_server := false
var _was_connected := false


func listen(port: int, max_clients := 256) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients, 2)
	if err != OK:
		return err
	is_server = true
	peer.peer_connected.connect(func(id): peer_connected.emit(id))
	peer.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	return OK


func connect_to(host: String, port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port, 2)
	if err != OK:
		return err
	peer.peer_disconnected.connect(func(_id): peer_disconnected.emit(1))
	return OK


func poll() -> void:
	if peer == null:
		return
	peer.poll()
	if not is_server:
		var st := peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED and not _was_connected:
			_was_connected = true
			connected.emit()
		elif st == MultiplayerPeer.CONNECTION_DISCONNECTED and not _was_connected:
			_was_connected = true  # чтобы не повторять
			connection_failed.emit()
			return
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var data := peer.get_packet()
		packet.emit(from, data)


func send(id: int, data: PackedByteArray, reliable := true) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.transfer_channel = 0 if reliable else 1
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.set_target_peer(id)
	peer.put_packet(data)


func kick(id: int) -> void:
	if peer and is_server:
		peer.disconnect_peer(id)


func close() -> void:
	if peer:
		peer.close()
	peer = null
