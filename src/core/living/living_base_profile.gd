class_name LivingBaseProfile
extends RefCounted

## Everything the Living Base persists between sessions (#156). Pure data and
## maths: the clock is passed in as `now_unix`, and file I/O lives in
## src/game/living_base_store.gd.

const FORMAT: String = "bio_siege.living_base"
const VERSION: int = 1

var seed: int = 0                    # chosen once at creation, drives every derived seed
var layout: Array[Dictionary] = []   # GridModel.to_layout() format
var wallet: Dictionary = {}          # currency -> int
var stored_atp: int = 0              # uncollected ATP inside Mitochondria
var atp_carry: int = 0               # AtpGenerator carry (ATP*seconds)
var last_clock_unix: int = 0         # last time advance_clock ran
var memory: Dictionary = {}          # ImmuneMemory.to_dict() of the player's base
var populations: Dictionary = {}     # type_id -> BreedPool.to_dict(): player's pathogen AND tower pools
var upgrades: Dictionary = {}        # upgrade id -> level (filled by LB-15)
## Unlocked strain variants as "type/variant" keys (AM-10). Empty while the `strains` flag is off.
var unlocked_strains: Array[String] = []
## AI bases: {id, tier, seed, layout, memory, populations, stored_atp, raids}. Layout origins are [x, y].
var opponents: Array[Dictionary] = []
var opponent_counter: int = 0        # AI bases generated so far; drives their seeds and ids
var ai_army_populations: Dictionary = {}       # pools of AI raiders (filled by LB-10)
var raid_counter: int = 0            # raids the player has launched
var ai_raid_counter: int = 0         # AI raids resolved against the player
var last_ai_raid_unix: int = 0
var defense_log: Array[Dictionary] = []        # newest first, capped (filled by LB-10)

static func create_new(cfg: GameConfig, p_seed: int, now_unix: int) -> LivingBaseProfile:
	var p := LivingBaseProfile.new()
	p.seed = p_seed
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	p.layout = grid.to_layout()
	p.wallet = cfg.lb_start_wallet.duplicate()
	p.last_clock_unix = now_unix
	p.last_ai_raid_unix = now_unix  # the first AI raid comes one interval after the first launch
	p.unlocked_strains = StrainUnlocks.normalize(cfg, [])
	return p

## Banks ATP generated since the last call. Returns the ATP generated.
## last_clock_unix always moves to now_unix, so a clock set back cannot bank time.
func advance_clock(cfg: GameConfig, now_unix: int) -> int:
	var elapsed: int = now_unix - last_clock_unix
	last_clock_unix = now_unix
	var res: Dictionary = AtpGenerator.accrue(
		stored_atp, atp_carry,
		AtpGenerator.rate_per_hour(cfg, layout), AtpGenerator.capacity(cfg, layout),
		elapsed, cfg.lb_max_offline_s)
	stored_atp = int(res["stored"])
	atp_carry = int(res["carry"])
	return int(res["generated"])

## Moves stored ATP into the wallet and returns the amount moved.
func collect() -> int:
	var amount: int = stored_atp
	if amount <= 0:
		return 0
	wallet["atp"] = int(wallet.get("atp", 0)) + amount
	stored_atp = 0
	return amount

## Fills the opponent slots, one per tier in order, until `ai_opponents_shown` are present.
func ensure_opponents(cfg: GameConfig) -> void:
	while opponents.size() < mini(cfg.ai_opponents_shown, cfg.ai_tiers.size()):
		opponents.append(_new_opponent(cfg, str(cfg.ai_tiers[opponents.size()]["id"])))

## Regenerates one slot (same tier) with the next counter. Returns false for an unknown id.
func replace_opponent(id: String, cfg: GameConfig) -> bool:
	var index: int = opponent_index(id)
	if index < 0:
		return false
	opponents[index] = _new_opponent(cfg, str(opponents[index]["tier"]))
	return true

## Index into `opponents` for an id, or -1.
func opponent_index(id: String) -> int:
	for i: int in range(opponents.size()):
		if str(opponents[i].get("id", "")) == id:
			return i
	return -1

func _new_opponent(cfg: GameConfig, tier_id: String) -> Dictionary:
	var n: int = opponent_counter
	opponent_counter += 1
	var opp_seed: int = seed + 7919 * n
	var gen: Dictionary = AiBaseGenerator.generate(cfg, tier_id, opp_seed)
	var layout: Array = []
	for entry: Dictionary in gen["layout"]:
		var o: Vector2i = _origin_of(entry)
		layout.append({"type": str(entry["type"]), "origin": [o.x, o.y]})
	var stored: int = 0
	for t: Dictionary in cfg.ai_tiers:
		if str(t["id"]) == tier_id:
			stored = int(t["stored_atp"])
	return {
		"id": "%s-%d" % [tier_id, n],
		"tier": tier_id,
		"seed": opp_seed,
		"layout": layout,
		"memory": {},
		"populations": {},
		"stored_atp": stored,
		"raids": 0,
	}

## Player raided an AI base: the looted ATP, Amino Acids and DNA go straight to the wallet.
func apply_raid_result(res: Dictionary) -> void:
	_add_currency("atp", int(res.get("atp_looted", 0)))
	_add_currency("amino_acids", int(res.get("amino_attacker", 0)))
	_add_currency("dna", int(res.get("dna_attacker", 0)))

## An AI raided the player: the looted ATP leaves the Mitochondria (never below 0) and kills pay Amino Acids.
func apply_defense_result(res: Dictionary) -> void:
	stored_atp = maxi(0, stored_atp - maxi(0, int(res.get("atp_looted", 0))))
	_add_currency("amino_acids", int(res.get("amino_defender", 0)))

func _add_currency(currency: String, amount: int) -> void:
	if amount != 0:
		wallet[currency] = int(wallet.get(currency, 0)) + amount

func push_defense_log(entry: Dictionary, cfg: GameConfig) -> void:
	defense_log.push_front(entry)
	var limit: int = maxi(1, cfg.lb_defense_log_size)
	while defense_log.size() > limit:
		defense_log.pop_back()

func to_dict() -> Dictionary:
	var layout_out: Array = []
	for entry: Dictionary in layout:
		var o: Vector2i = _origin_of(entry)
		layout_out.append({"type": str(entry.get("type", "")), "origin": [o.x, o.y]})
	var d: Dictionary = {
		"format": FORMAT,
		"version": VERSION,
		"seed": seed,
		"layout": layout_out,
		"wallet": wallet.duplicate(true),
		"stored_atp": stored_atp,
		"atp_carry": atp_carry,
		"last_clock_unix": last_clock_unix,
		"memory": memory.duplicate(true),
		"populations": populations.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"opponents": opponents.duplicate(true),
		"opponent_counter": opponent_counter,
		"ai_army_populations": ai_army_populations.duplicate(true),
		"raid_counter": raid_counter,
		"ai_raid_counter": ai_raid_counter,
		"last_ai_raid_unix": last_ai_raid_unix,
		"defense_log": defense_log.duplicate(true),
	}
	if not unlocked_strains.is_empty():
		d["unlocked_strains"] = unlocked_strains.duplicate()
	return SnapshotIO.sort_keys(d) as Dictionary

## Returns {"ok": bool, "profile": LivingBaseProfile, "error": String, "notices": Array[String]}.
static func from_dict(d: Dictionary, cfg: GameConfig) -> Dictionary:
	var notices: Array[String] = []
	if str(d.get("format", "")) != FORMAT:
		return _fail("Not a Living Base save (format is '%s')." % str(d.get("format", "")))
	var ver: Variant = d.get("version", 0)
	if not _is_whole(ver) or int(ver) < 1:
		return _fail("Living Base save has an invalid version.")
	if int(ver) > VERSION:
		return _fail("Living Base save version %d is newer than this game supports (%d)." % [int(ver), VERSION])

	var p := LivingBaseProfile.new()
	p.seed = _int_of(d, "seed", 0)
	p.stored_atp = maxi(0, _int_of(d, "stored_atp", 0))
	p.atp_carry = clampi(_int_of(d, "atp_carry", 0), 0, AtpGenerator.SECONDS_PER_HOUR - 1)
	p.last_clock_unix = maxi(0, _int_of(d, "last_clock_unix", 0))
	p.raid_counter = maxi(0, _int_of(d, "raid_counter", 0))
	p.ai_raid_counter = maxi(0, _int_of(d, "ai_raid_counter", 0))
	p.last_ai_raid_unix = maxi(0, _int_of(d, "last_ai_raid_unix", 0))
	p.opponent_counter = maxi(0, _int_of(d, "opponent_counter", 0))

	# Layout: drop unknown or disabled types, then prove the rest loads.
	var kept: Array = []
	var removed: int = 0
	var layout_val: Variant = d.get("layout", [])
	if typeof(layout_val) != TYPE_ARRAY:
		return _fail("Living Base save has an invalid layout.")
	for item: Variant in layout_val:
		if typeof(item) != TYPE_DICTIONARY:
			return _fail("Living Base save has an invalid layout entry.")
		var e: Dictionary = item
		var type_id: String = str(e.get("type", ""))
		if not cfg.is_structure_enabled(type_id):
			removed += 1
			continue
		kept.append({"type": type_id, "origin": _origin_of(e)})
	if removed > 0:
		notices.append("%d structures removed (no longer in the game)" % removed)
	var grid := GridModel.new(cfg)
	if grid.load_layout(kept, unlimited_wallet()) != GridModel.PlaceError.OK:
		# Keep what fits, one structure at a time, so one bad entry (an overlap after a footprint change)
		# does not cost the player the whole base.
		var fitting: Array = []
		for entry: Dictionary in kept:
			if grid.load_layout(fitting + [entry], unlimited_wallet()) == GridModel.PlaceError.OK:
				fitting.append(entry)
		if grid.load_layout(fitting, unlimited_wallet()) != GridModel.PlaceError.OK:
			return _fail("Living Base save has a base layout that does not fit the grid.")
		notices.append("%d structures removed (no longer fit the base)" % (kept.size() - fitting.size()))
	p.layout = grid.to_layout()

	# Wallet: known currencies only, never negative.
	var dropped_cur: bool = false
	var clamped_cur: bool = false
	var wallet_val: Variant = d.get("wallet", {})
	if typeof(wallet_val) == TYPE_DICTIONARY:
		for cur_var: Variant in (wallet_val as Dictionary).keys():
			var cur: String = str(cur_var)
			var amt_v: Variant = (wallet_val as Dictionary)[cur_var]
			if not GameConfig.KNOWN_CURRENCIES.has(cur) or not _is_whole(amt_v):
				dropped_cur = true
				continue
			if int(amt_v) < 0:
				clamped_cur = true
			p.wallet[cur] = maxi(0, int(amt_v))
	if dropped_cur:
		notices.append("Unknown currencies were removed from your wallet")
	if clamped_cur:
		notices.append("Negative wallet amounts were reset to 0")

	var up_val: Variant = d.get("upgrades", {})
	if typeof(up_val) == TYPE_DICTIONARY:
		for k_var: Variant in (up_val as Dictionary).keys():
			var lv: Variant = (up_val as Dictionary)[k_var]
			if _is_whole(lv) and int(lv) >= 0:
				p.upgrades[str(k_var)] = int(lv)

	p.unlocked_strains = StrainUnlocks.normalize(cfg, d.get("unlocked_strains", []))

	var mem_val: Variant = d.get("memory", {})
	if typeof(mem_val) == TYPE_DICTIONARY:
		p.memory = ImmuneMemory.from_dict(mem_val, cfg, BaseUpgrades.memory_slots(cfg, p.upgrades)).to_dict()
	p.populations = _clean_pools(d.get("populations", {}), cfg)
	p.ai_army_populations = _clean_pools(d.get("ai_army_populations", {}), cfg)

	p.opponents = _dict_list(d.get("opponents", []))
	p.defense_log = _dict_list(d.get("defense_log", []))
	while p.defense_log.size() > maxi(1, cfg.lb_defense_log_size):
		p.defense_log.pop_back()
	return {"ok": true, "profile": p, "error": "", "notices": notices}

static func _fail(message: String) -> Dictionary:
	var empty: Array[String] = []
	return {"ok": false, "profile": null, "error": message, "notices": empty}

## A wallet that affords anything, for building display or validation grids.
static func unlimited_wallet() -> Wallet:
	var amounts: Dictionary = {}
	for cur: String in GameConfig.KNOWN_CURRENCIES:
		amounts[cur] = 1000000000
	return Wallet.new(amounts)

static func _clean_pools(val: Variant, cfg: GameConfig) -> Dictionary:
	var out: Dictionary = {}
	if typeof(val) != TYPE_DICTIONARY:
		return out
	for type_id: String in cfg.coevo_types:
		var pool_val: Variant = (val as Dictionary).get(type_id, null)
		if typeof(pool_val) == TYPE_DICTIONARY:
			out[type_id] = BreedPool.from_dict(pool_val, type_id, cfg).to_dict()
	return out

static func _dict_list(val: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(val) != TYPE_ARRAY:
		return out
	for item: Variant in val:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(_whole_floats_to_ints(item) as Dictionary)
	return out

## JSON parses every number as a float; opaque records (AI bases, log entries) hold ints, so restore them.
static func _whole_floats_to_ints(val: Variant) -> Variant:
	if typeof(val) == TYPE_DICTIONARY:
		var out: Dictionary = {}
		for k: Variant in (val as Dictionary).keys():
			out[k] = _whole_floats_to_ints((val as Dictionary)[k])
		return out
	if typeof(val) == TYPE_ARRAY:
		var arr: Array = []
		for item: Variant in (val as Array):
			arr.append(_whole_floats_to_ints(item))
		return arr
	if typeof(val) == TYPE_FLOAT and _is_whole(val):
		return int(val)
	return val

static func _origin_of(entry: Dictionary) -> Vector2i:
	var o: Variant = entry.get("origin", Vector2i.ZERO)
	if o is Vector2i:
		return o
	if o is Array and (o as Array).size() >= 2:
		return Vector2i(int((o as Array)[0]), int((o as Array)[1]))
	return Vector2i.ZERO

static func _is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(float(v)) and floorf(float(v)) == float(v)

static func _int_of(d: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = d.get(key, fallback)
	return int(v) if _is_whole(v) else fallback
