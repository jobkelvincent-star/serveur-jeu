extends Node
# RECHERCHE DE PARTIE : ce fichier sert au SERVEUR et au JEU (le nœud doit s'appeler "Lobby" des deux côtés).
# Le serveur garde la liste des joueurs qui cherchent, et lance une partie quand elle est COMPLÈTE :
#   - 6 joueurs en attente  -> 3 contre 3, tout de suite
#   - sinon, quand le plus ancien attend depuis DELAI_3V3 secondes et qu'ils sont au moins 4  -> 2 contre 2
#   - sinon, quand le plus ancien attend depuis DELAI_2V2 secondes et qu'ils sont au moins 2  -> 1 contre 1
# On prend toujours les joueurs qui attendent depuis le plus longtemps, en nombre PAIR : jamais d'équipe plus grande que l'autre.
# Une seule partie à la fois sur le serveur gratuit : pendant une partie, les autres patientent.

const DELAI_3V3 := 20.0          # secondes à chercher une équipe de 6 avant d'accepter du 2v2
const DELAI_2V2 := 40.0          # secondes à chercher une équipe de 4 avant d'accepter du 1v1

# ---- Côté JEU : le menu écoute ces signaux ----
signal etat_recu(trouves: int, cible: int, occupe: bool)
signal partie_trouvee(mode: int, equipe: int, place: int)

# ---- Côté SERVEUR ----
signal partie_formee(groupe: Array, mode: int)
var attente: Array = []          # joueurs qui cherchent : {id, scene, vote, dispo, depuis}
var salle: Array = []            # numéros des joueurs de la partie en cours
var _tic := 0.0


# =============== Côté JEU ===============
func rechercher(scene: String, vote: String, dispo: Array) -> void:
	rpc_id(1, "chercher", scene, vote, dispo)


func annuler_recherche() -> void:
	rpc_id(1, "annuler")


@rpc("any_peer", "call_remote", "reliable")
func etat_recherche(trouves: int, cible: int, occupe: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		etat_recu.emit(trouves, cible, occupe)


@rpc("any_peer", "call_remote", "reliable")
func annonce_partie(mode: int, equipe: int, place: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		partie_trouvee.emit(mode, equipe, place)


# =============== Côté SERVEUR ===============
@rpc("any_peer", "call_remote", "reliable")
func chercher(scene: String, vote: String, dispo: Array) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	depart_joueur(id)
	attente.append({"id": id, "scene": scene, "vote": vote, "dispo": dispo, "depuis": _maintenant()})
	print("LOBBY : le joueur ", id, " cherche une partie (", attente.size(), " en attente)")
	_evaluer()


@rpc("any_peer", "call_remote", "reliable")
func annuler() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_retirer_attente(id)
	print("LOBBY : le joueur ", id, " annule (", attente.size(), " en attente)")
	_diffuser()


# Appelé par serveur.gd quand un joueur se déconnecte
func depart_joueur(id: int) -> void:
	_retirer_attente(id)
	if salle.has(id):
		salle.erase(id)
		if salle.is_empty():
			print("LOBBY : la partie est terminée, la salle est libre")


func _retirer_attente(id: int) -> void:
	for i in range(attente.size() - 1, -1, -1):
		if attente[i]["id"] == id:
			attente.remove_at(i)


func salle_libre() -> void:                  # appelé quand la partie se termine
	salle.clear()


func _maintenant() -> float:
	return Time.get_ticks_msec() * 0.001


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_tic += delta
	if _tic >= 1.0:
		_tic = 0.0
		_evaluer()


func _evaluer() -> void:
	if attente.is_empty():
		return
	if not salle.is_empty():
		_diffuser()                            # une partie est en cours : on patiente
		return
	var n := attente.size()
	var plus_ancien := _maintenant() - float(attente[0]["depuis"])
	var mode := 0
	if n >= 6:
		mode = 3
	elif plus_ancien >= DELAI_3V3 and n >= 4:
		mode = 2
	elif plus_ancien >= DELAI_2V2 and n >= 2:
		mode = 1
	if mode == 0:
		_diffuser()
		return
	var groupe: Array = attente.slice(0, mode * 2)
	attente = attente.slice(mode * 2)
	salle.clear()
	for i in groupe.size():
		var id: int = groupe[i]["id"]
		salle.append(id)
		rpc_id(id, "annonce_partie", mode, i % 2, int(i / 2))      # équipe 0/1 en alternance, place 0, 1, 2
	print("LOBBY : PARTIE ", mode, " contre ", mode, " avec ", salle)
	partie_formee.emit(groupe, mode)


# Dit à chaque joueur qui attend où en est la recherche : "3/6"
func _diffuser() -> void:
	if attente.is_empty():
		return
	var plus_ancien := _maintenant() - float(attente[0]["depuis"])
	var cible := 6
	if plus_ancien >= DELAI_2V2:
		cible = 2
	elif plus_ancien >= DELAI_3V3:
		cible = 4
	var trouves := mini(attente.size(), cible)
	for e in attente:
		rpc_id(e["id"], "etat_recherche", trouves, cible, not salle.is_empty())
