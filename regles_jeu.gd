extends Node
const Sons := preload("res://sons.gd")      # les sons du jeu (voir sons.gd)
# RÈGLES DU JEU + RÉSEAU (créé automatiquement par main.gd quand on joue en ligne ; tu n'as rien à brancher).
# Enregistre ce fichier ici : res://regles_jeu.gd
#
# Les règles (1v1, 2v2 ou 3v3) :
#   - chaque fois qu'un adversaire tombe (eau, paradis...), ton ÉQUIPE marque 1 point
#   - une équipe gagne la manche à POINTS_PAR_MANCHE[mode] points : 1v1 = 3, 2v2 = 6, 3v3 = 15
#   - 2 manches gagnées = ton équipe gagne la partie (3 manches au maximum)
#   - l'hôte (le joueur qui a cliqué sur "Héberger") est le chef : c'est lui qui compte les points
#   - les équipes se forment dans l'ordre d'arrivée : 1er = équipe 1, 2e = équipe 2, 3e = équipe 1... (jamais d'équipe plus grande que l'autre :
#     la partie ne démarre que quand TOUT LE MONDE est là : 2, 4 ou 6 joueurs)
#   - points de départ : équipe 1 = 1_1, 1_2, 1_3 ; équipe 2 = 2_1, 2_2, 2_3

# MODE SERVEUR (dedie = vrai) : ce même fichier tourne aussi sur le serveur en ligne (sans écran, sans carte, sans perso).
# Il compte alors les points pour tout le monde. Voir serveur/serveur.gd.

const POINTS_PAR_MANCHE := {1: 3, 2: 6, 3: 15}      # selon le nombre de joueurs par équipe
const MANCHES_POUR_GAGNER := 2
const MANCHES_MAX := 3
const COMPTE_A_REBOURS := 5           # secondes avant le début de chaque manche
const PAUSE_MANCHE := 3.0             # secondes entre la fin d'une manche et le compte à rebours
const PAUSE_FIN := 6.0                # secondes entre la fin de la partie et le retour au menu

var carte: Node3D = null              # la map votée (chargée par main.gd au démarrage) : on y cherche les points de départ "1_1" (équipe 1) et "2_1" (équipe 2)
var joueurs := {}                     # numéro réseau -> perso
var choix := {}                       # (hôte) numéro réseau -> scène du perso choisi
var votes := {}                       # (hôte) numéro réseau -> carte votée ("" = pas de vote)
var ordre: Array = []                 # (hôte) numéros réseau dans l'ordre d'arrivée
var dispos := {}                      # (hôte) numéro réseau -> liste des cartes que ce joueur possède
var dedie := false                    # vrai = je tourne sur le serveur (réglé par serveur.gd)
var autorises: Array = []             # (serveur) les numéros des joueurs de cette partie
var mode := 1                         # joueurs par équipe : 1 (1v1), 2 (2v2) ou 3 (3v3)
var attendus := 2                     # (hôte) nombre de joueurs à attendre avant de démarrer
var equipe_de := {}                   # numéro réseau -> équipe (0 ou 1)
var place_de := {}                    # numéro réseau -> place dans son équipe (0, 1, 2) : sert à choisir le point de départ
var scores := {0: 0, 1: 0}            # (hôte) points de la manche en cours, par ÉQUIPE
var manches_gagnees := {0: 0, 1: 0}   # (hôte) manches gagnées, par ÉQUIPE
var manche := 1
var phase := "attente"                # (hôte) "attente", "compte", "jeu", "pause", "fini"
var etiquette_attente: Label
var parti := false
var fini := false                     # la partie est terminée (plus de message "l'adversaire est parti")
var mon_id := 0                       # mon numéro réseau (retenu au démarrage)


func _ready() -> void:
	add_to_group("regles")
	mon_id = multiplayer.get_unique_id()
	multiplayer.peer_disconnected.connect(_on_deconnecte)
	multiplayer.server_disconnected.connect(_on_deconnecte.bind(0))
	if dedie:
		# Sur le serveur : j'attends que les joueurs de la partie se déclarent prêts (90 s maximum, sinon j'annule)
		await get_tree().create_timer(90.0).timeout
		if phase == "attente":
			print("RESEAU : tous les joueurs ne sont pas arrivés à temps : partie annulée")
			_fermer_partie_serveur()
		return
	if multiplayer.is_server():
		mode = clampi(int(Engine.get_meta("mode_equipe", 1)), 1, 3)
		attendus = 2 * mode
	_afficher_attente()
	var mon_choix: String = Engine.get_meta("joueur_choisi", "res://joueur_1.tscn")
	var mon_vote: String = Engine.get_meta("vote_carte", "")
	var mes_cartes: Array = Array(Engine.get_meta("cartes_dispo", []))
	if multiplayer.is_server():
		_enregistrer(1, mon_choix, mon_vote, mes_cartes)
	else:
		rpc_id(1, "pret", mon_choix, mon_vote, mes_cartes)     # on dit à l'hôte quel perso on a choisi et pour quelle carte on vote


# ---------- Démarrage ----------
@rpc("any_peer", "call_remote", "reliable")
func pret(scene: String, vote: String = "", cartes: Array = []) -> void:
	if multiplayer.is_server():
		_enregistrer(multiplayer.get_remote_sender_id(), scene, vote, cartes)


func _enregistrer(id: int, scene: String, vote: String = "", cartes: Array = []) -> void:
	if phase != "attente" or choix.has(id):
		return
	if dedie and not autorises.has(id):
		return                                              # quelqu'un qui n'est pas de cette partie
	choix[id] = scene
	votes[id] = vote
	dispos[id] = cartes
	ordre.append(id)
	print("RESEAU : joueur ", id, " prêt avec ", scene, " (", choix.size(), "/", attendus, ")")
	_a_tous("attente", [choix.size(), attendus])
	if choix.size() == attendus:
		var ids: Array = ordre.duplicate()
		var scenes: Array = []
		var equipes: Array = []
		for i in ids.size():
			scenes.append(choix[ids[i]])
			equipes.append(i % 2)                        # arrivée alternée : équipe 1, équipe 2, équipe 1...
		phase = "compte"
		_a_tous("demarrer", [ids, scenes, _choisir_carte(), equipes])


# Met à jour le message d'attente chez tout le monde : "Joueurs 3/6"
@rpc("authority", "call_local", "reliable")
func attente(k: int, n: int) -> void:
	if etiquette_attente == null:
		return
	if multiplayer.is_server():
		etiquette_attente.text = "En attente des joueurs : " + str(k) + "/" + str(n) + "\nTon adresse IP : " + _mes_ips() + "\n(sur ce PC : 127.0.0.1)"
	else:
		etiquette_attente.text = "En attente des joueurs : " + str(k) + "/" + str(n)


@rpc("authority", "call_local", "reliable")
func demarrer(ids: Array, scenes: Array, carte_chemin: String = "", equipes: Array = []) -> void:
	if etiquette_attente != null:
		etiquette_attente.get_parent().queue_free()
		etiquette_attente = null
	mode = maxi(int(ids.size() * 0.5), 1)
	var compte_equipe := [0, 0]
	for i in ids.size():
		var eq: int = equipes[i] if i < equipes.size() else i % 2
		equipe_de[ids[i]] = eq
		place_de[ids[i]] = compte_equipe[eq]
		compte_equipe[eq] += 1
	if dedie:                                                          # le serveur ne charge ni carte ni perso : il compte les points
		scores = {0: 0, 1: 0}
		manches_gagnees = {0: 0, 1: 0}
		print("RESEAU : partie lancée sur le serveur (", mode, "v", mode, ")")
		_nouvelle_manche(1)
		return
	carte = get_parent().call("charger_carte", carte_chemin)       # la carte votée, chargée chez tous les joueurs
	for i in ids.size():
		var id: int = ids[i]
		var j = load(scenes[i]).instantiate()
		j.name = str(id)                              # même nom sur tous les ordinateurs : c'est ce qui les relie
		j.set("est_joueur", id == mon_id)             # mon perso : je le pilote
		j.set("distant", id != mon_id)                # les autres : des copies pilotées par leur ordinateur
		j.set("equipe", equipe_de[id])                # pour ne pas se blesser entre coéquipiers
		j.set_multiplayer_authority(id)
		get_parent().add_child(j)
		joueurs[id] = j
	scores = {0: 0, 1: 0}
	manches_gagnees = {0: 0, 1: 0}
	print("RESEAU : partie lancée (", mode, "v", mode, "), je suis le joueur ", mon_id, " dans l'équipe ", equipe_de.get(mon_id))
	_mm = 0
	_ma = 0
	_nouvelle_manche(1)


# Le vote des cartes : la carte qui a le plus de votes gagne ; égalité (ou personne n'a voté) = au hasard
func _choisir_carte() -> String:
	var compte := {}
	for id in votes:
		var v: String = votes[id]
		if v != "":
			compte[v] = compte.get(v, 0) + 1
	var gagnantes: Array = []
	if compte.is_empty():
		for id in dispos:                                            # personne n'a voté : au hasard parmi toutes les cartes des joueurs
			for c in dispos[id]:
				if not gagnantes.has(c):
					gagnantes.append(c)
		if gagnantes.is_empty():
			gagnantes = Array(Engine.get_meta("cartes_dispo", []))
	else:
		var meilleur: int = compte.values().max()
		for k in compte:
			if compte[k] == meilleur:
				gagnantes.append(k)
	var choisie: String = "" if gagnantes.is_empty() else gagnantes[randi() % gagnantes.size()]
	print("RESEAU : votes = ", votes, " -> carte = ", choisie)
	return choisie


# ---------- Manches ----------
@rpc("authority", "call_local", "reliable")
func nouvelle_manche(n: int) -> void:
	_nouvelle_manche(n)


func _nouvelle_manche(n: int) -> void:
	manche = n
	_pts_moi = 0
	_pts_adv = 0
	if multiplayer.is_server():
		phase = "compte"
		scores = {0: 0, 1: 0}
	if dedie:                                                         # serveur : juste le compte à rebours, puis la manche commence
		await get_tree().create_timer(float(COMPTE_A_REBOURS) + 0.5).timeout
		phase = "jeu"
		print("RESEAU : manche ", n, " en cours")
		return
	for id in joueurs:
		joueurs[id].call("reinitialiser", _pos_depart(id))
	var moi = joueurs.get(mon_id)
	if moi == null:
		return
	moi.set("gele", true)                              # personne ne bouge pendant le compte à rebours
	_maj_hud(0, 0)
	var hud = moi.get("hud_jeu")
	if hud != null:
		hud.call("definir_manche", n, MANCHES_MAX)
	for k in range(COMPTE_A_REBOURS, 0, -1):
		if hud != null:
			hud.call("message", str(k), 0.9)
		Sons.jouer(self, "bip")
		await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(moi):
		return
	if hud != null:
		hud.call("message", "GO !", 0.8)
	Sons.jouer(self, "go")
	moi.set("gele", false)
	if multiplayer.is_server():
		phase = "jeu"
		print("RESEAU : manche ", n, " en cours")


func _pos_depart(id: int) -> Vector3:
	var eq: int = equipe_de.get(id, 0)
	var place: int = place_de.get(id, 0)
	var nom := str(eq + 1) + "_" + str(place + 1)    # équipe 1 : 1_1, 1_2, 1_3 ; équipe 2 : 2_1, 2_2, 2_3
	var d: Node3D = null
	if carte != null:
		d = carte.find_child(nom, true, false)
		if d == null:
			d = carte.find_child(str(eq + 1) + "_1", true, false)      # pas assez de points de départ : le premier de l'équipe
		if d == null:
			d = carte.find_child("1_1", true, false)
	return (d.global_position if d != null else Vector3.ZERO) + Vector3(0, 1.0, 0)


# ---------- Points ----------
# Appelé par le perso quand il tombe à l'eau (voir joueur_1.gd)
func joueur_tombe(j) -> void:
	if j != joueurs.get(mon_id):
		return
	if multiplayer.is_server():
		_chute(1)
	else:
		rpc_id(1, "chute_recue")


@rpc("any_peer", "call_remote", "reliable")
func chute_recue() -> void:
	if multiplayer.is_server():
		_chute(multiplayer.get_remote_sender_id())


func _chute(id_tombe: int) -> void:
	if phase != "jeu" or not equipe_de.has(id_tombe):
		return
	var autre: int = 1 - int(equipe_de[id_tombe])      # l'équipe adverse marque
	scores[autre] += 1
	print("RESEAU : ", id_tombe, " est tombé -> point pour l'équipe ", autre, "  scores = ", scores)
	if scores[autre] < int(POINTS_PAR_MANCHE[mode]):
		_a_tous("etat", [manche, scores, manches_gagnees, -1])
		return
	phase = "pause"                                    # l'équipe adverse a gagné la manche
	manches_gagnees[autre] += 1
	print("RESEAU : manche ", manche, " gagnée par ", autre, "  manches = ", manches_gagnees)
	_a_tous("etat", [manche, scores, manches_gagnees, autre])
	if manches_gagnees[autre] >= MANCHES_POUR_GAGNER or manche >= MANCHES_MAX:
		phase = "fini"
		print("RESEAU : partie gagnée par ", autre)
		_a_tous("fin_partie", [autre])
	else:
		await get_tree().create_timer(PAUSE_MANCHE).timeout
		_a_tous("nouvelle_manche", [manche + 1])


@rpc("authority", "call_local", "reliable")
func etat(_n: int, sc: Dictionary, ma: Dictionary, gagnant: int) -> void:
	var mon_eq: int = equipe_de.get(mon_id, 0)
	var autre := 1 - mon_eq
	_mm = ma.get(mon_eq, 0)
	_ma = ma.get(autre, 0)
	var pts_moi: int = sc.get(mon_eq, 0)
	var pts_adv: int = sc.get(autre, 0)
	if pts_moi > _pts_moi:
		Sons.jouer(self, "point")
	elif pts_adv > _pts_adv:
		Sons.jouer(self, "point_adv")
	_pts_moi = pts_moi
	_pts_adv = pts_adv
	_maj_hud(pts_moi, pts_adv)
	if gagnant != -1:
		var hud = _hud()
		if hud != null:
			hud.call("message", "MANCHE GAGNÉE !" if gagnant == mon_eq else "MANCHE PERDUE", PAUSE_MANCHE - 0.5)


# moi, adv = points de la manche en cours ; _mm, _ma = manches gagnées par moi / par l'adversaire
var _mm := 0
var _ma := 0
var _pts_moi := 0                       # points de la manche déjà connus (pour jouer le son quand ça change)
var _pts_adv := 0

func _maj_hud(moi: int, adv: int) -> void:
	var hud = _hud()
	if hud != null:
		hud.call("definir_score", moi, adv, _mm, _ma)


@rpc("authority", "call_local", "reliable")
func fin_partie(gagnant: int) -> void:
	fini = true
	var gagne: bool = gagnant == int(equipe_de.get(mon_id, 0))
	Sons.jouer(self, "victoire" if gagne else "defaite")
	var hud = _hud()
	if hud != null:
		var l = hud.get("texte_message")
		if l != null:
			l.add_theme_color_override("font_color", Color(0.3, 1, 0.4) if gagne else Color(1, 0.3, 0.3))
		hud.call("message", "VICTOIRE !" if gagne else "DÉFAITE", 0.0)
	await get_tree().create_timer(PAUSE_FIN).timeout
	_retour_menu()


func _hud():
	var moi = joueurs.get(mon_id)
	return moi.get("hud_jeu") if moi != null else null


# ---------- Départ de l'adversaire / retour au menu ----------
func _on_deconnecte(_id: int = 0) -> void:
	if dedie or parti or fini:
		return
	if _id != 0 and not equipe_de.has(_id):
		return                                              # quelqu'un qui n'est pas dans MA partie (il cherchait une partie) : on s'en moque
	fini = true
	var hud = _hud()
	if hud != null:
		hud.call("message", "Un joueur a quitté la partie", 0.0)
	print("RESEAU : l'autre joueur est parti")
	await get_tree().create_timer(3.0).timeout
	_retour_menu()


func _retour_menu() -> void:
	if parti:
		return
	parti = true
	if dedie:
		_fermer_partie_serveur()
		return
	var chemin := "res://menu.tscn"
	var moi = joueurs.get(mon_id)        # (avant de fermer la connexion)
	if moi != null and moi.get("chemin_menu") != null:
		chemin = moi.get("chemin_menu")
	multiplayer.multiplayer_peer = null
	if Engine.has_meta("reseau"):
		Engine.remove_meta("reseau")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(chemin)


# ---------- Écran d'attente ----------
func _afficher_attente() -> void:
	var couche := CanvasLayer.new()
	couche.layer = 20
	add_child(couche)
	etiquette_attente = Label.new()
	if multiplayer.is_server():
		etiquette_attente.text = "En attente des joueurs : 0/" + str(attendus) + "\nTon adresse IP : " + _mes_ips() + "\n(sur ce PC : 127.0.0.1)"
	else:
		etiquette_attente.text = "Connexion à la partie…"
	etiquette_attente.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiquette_attente.add_theme_font_size_override("font_size", 36)
	etiquette_attente.add_theme_constant_override("outline_size", 10)
	etiquette_attente.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	couche.add_child(etiquette_attente)
	etiquette_attente.set_anchors_preset(Control.PRESET_CENTER)
	etiquette_attente.grow_horizontal = Control.GROW_DIRECTION_BOTH
	etiquette_attente.grow_vertical = Control.GROW_DIRECTION_BOTH


func _mes_ips() -> String:
	var res := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			res.append(a)
	return ", ".join(res) if res.size() > 0 else "inconnue"


# ---------- Envoi des messages ----------
# Les joueurs de MA partie (sans moi) : on leur écrit un par un, pour ne pas déranger les autres joueurs connectés au serveur
func cibles() -> Array:
	var res: Array = []
	var ids: Array = autorises if dedie else (equipe_de.keys() if not equipe_de.is_empty() else choix.keys())
	for id in ids:
		if id != mon_id:
			res.append(id)
	return res


# Appelle une fonction chez tous les joueurs de la partie ET chez moi (comme un rpc "call_local")
func _a_tous(methode: String, args: Array) -> void:
	for id in cibles():
		callv("rpc_id", [id, methode] + args)
	callv(methode, args)


# Pour les autres scripts (joueur, caisse...) : envoie "methode" du noeud aux autres joueurs de la partie seulement
static func envoyer(noeud: Node, methode: String, args: Array = []) -> void:
	var r = noeud.get_tree().get_first_node_in_group("regles")
	if r == null:
		noeud.callv("rpc", [methode] + args)               # pas de règles (cas rare) : à tout le monde, comme avant
		return
	for id in r.call("cibles"):
		noeud.callv("rpc_id", [id, methode] + args)


# (serveur) la partie est finie ou annulée : on renvoie tout le monde au menu et on libère la salle
func _fermer_partie_serveur() -> void:
	var p := multiplayer.multiplayer_peer
	for id in autorises:
		if p != null and multiplayer.get_peers().has(id):
			p.disconnect_peer(id)
	phase = "fini"
