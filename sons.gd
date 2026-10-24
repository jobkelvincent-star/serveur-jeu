extends RefCounted
# Faux "sons" pour le serveur : il n'a ni haut-parleur ni fichiers audio. Il remplace le vrai sons.gd du jeu (même nom, mêmes fonctions).

static func jouer(_depuis = null, _nom = "", _position = null) -> void:
	pass


static func musique(_depuis = null, _noms = null) -> void:
	pass
