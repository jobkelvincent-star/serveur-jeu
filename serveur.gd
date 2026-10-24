extends SceneTree
# SERVEUR DU JEU (étape 1 : il écoute et note qui arrive / qui part ; la recherche de partie viendra à l'étape suivante).
# Il tourne SANS écran, sur l'hébergeur. Le port vient de la variable PORT (donnée par l'hébergeur), sinon 8080.

const PORT_PAR_DEFAUT := 8080

var peer: WebSocketMultiplayerPeer


func _initialize() -> void:
	Engine.max_fps = 30                                  # inutile de tourner à fond : on économise le processeur gratuit
	var texte := OS.get_environment("PORT")
	var port := int(texte) if texte != "" else PORT_PAR_DEFAUT
	peer = WebSocketMultiplayerPeer.new()
	var erreur := peer.create_server(port, "*")
	if erreur != OK:
		print("SERVEUR : impossible d'ouvrir le port ", port, " (erreur ", erreur, ")")
		quit(1)
		return
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().peer_connected.connect(_arrivee)
	get_multiplayer().peer_disconnected.connect(_depart)
	print("SERVEUR : prêt, j'écoute sur le port ", port, "  (Godot ", Engine.get_version_info()["string"], ")")


func _arrivee(id: int) -> void:
	print("SERVEUR : un joueur arrive (n° ", id, "). Joueurs connectés : ", get_multiplayer().get_peers().size())


func _depart(id: int) -> void:
	print("SERVEUR : un joueur part (n° ", id, "). Joueurs connectés : ", get_multiplayer().get_peers().size())
