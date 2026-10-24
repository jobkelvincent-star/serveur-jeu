extends SceneTree
# SERVEUR DU JEU (il écoute, note qui arrive / qui part, et gère la recherche de partie : voir lobby.gd).
# Il tourne SANS écran, sur l'hébergeur. Le port vient de la variable PORT (donnée par l'hébergeur), sinon 8080.

const PORT_PAR_DEFAUT := 8080

var peer: WebSocketMultiplayerPeer
var lobby: Node
var partie: Node = null                          # la partie en cours (noeud "main" + ReglesJeu, comme dans le jeu)


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
	lobby = Node.new()                                   # la recherche de partie (voir lobby.gd)
	lobby.name = "Lobby"
	lobby.set_script(load("res://lobby.gd"))
	root.add_child(lobby)
	lobby.connect("partie_formee", _lancer_partie)
	lobby.connect("salle_vide", _fermer_partie)
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().peer_connected.connect(_arrivee)
	get_multiplayer().peer_disconnected.connect(_depart)
	print("SERVEUR : prêt, j'écoute sur le port ", port, "  (Godot ", Engine.get_version_info()["string"], ")")


func _arrivee(id: int) -> void:
	print("SERVEUR : un joueur arrive (n° ", id, "). Joueurs connectés : ", get_multiplayer().get_peers().size())


func _depart(id: int) -> void:
	lobby.call("depart_joueur", id)
	print("SERVEUR : un joueur part (n° ", id, "). Joueurs connectés : ", get_multiplayer().get_peers().size())


# Une partie vient d'être formée : je crée les règles du jeu (au même endroit que dans le jeu : /root/main/ReglesJeu)
func _lancer_partie(groupe: Array, mode: int) -> void:
	_fermer_partie()
	partie = Node.new()
	partie.name = "main"                                  # même nom que la scène du jeu (main.tscn)
	root.add_child(partie)
	var regles := Node.new()
	regles.name = "ReglesJeu"
	regles.set_script(load("res://regles_jeu.gd"))
	var ids: Array = []
	for e in groupe:
		ids.append(e["id"])
	regles.set("dedie", true)
	regles.set("mode", mode)
	regles.set("attendus", mode * 2)
	regles.set("autorises", ids)
	partie.add_child(regles)
	print("SERVEUR : partie ", mode, "v", mode, " créée pour ", ids)


func _fermer_partie() -> void:
	if partie != null:
		partie.name = "ancienne_partie"                   # libère le nom "main" tout de suite
		partie.queue_free()
		partie = null
		print("SERVEUR : partie fermée")
