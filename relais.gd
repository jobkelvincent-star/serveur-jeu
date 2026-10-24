extends Node
# TEST DU RELAIS : un message envoyé par un joueur à un autre en passant par le serveur.
# Ce même fichier est utilisé par le serveur ET par le jeu (le nœud doit avoir le même nom des deux côtés : "TestRelais").

@rpc("any_peer", "call_remote", "reliable")
func dire(texte: String) -> void:
	print("RELAIS : message reçu de ", multiplayer.get_remote_sender_id(), " : ", texte)
