class_name ModelRegistry
extends RefCounted

## type_id -> ModelPainter. Returns cached instances. Every id gets a PlaceholderPainter until a real
## painter is registered here (#67 to #70); UnitLayer never changes when that happens.

## Model heights in tiles, from docs/MVP_UI_SPEC.md section 4.
const HEIGHT_T: Dictionary = {
	"rhinovirus": 1.25,
	"bacteriophage": 3.0,
	"staphylococcus": 2.35,
	"macrophage": 3.0,
	"b_cell": 4.3,
	"nucleus": 4.1,
	"mucous_wall": 0.8,
}
const DEFAULT_HEIGHT_T: float = 3.0
const PATHOGEN_WIDTH_T: Dictionary = {
	"rhinovirus": 1.2,
	"bacteriophage": 1.9,
	"staphylococcus": 2.8,
}
const DEFAULT_PATHOGEN_WIDTH_T: float = 1.2
const STRUCTURE_WIDTH_SCALE: float = 1.4

static var _painters: Dictionary = {}


static func painter_for(type_id: String) -> ModelPainter:
	if not _painters.has(type_id):
		_painters[type_id] = _create(type_id)
	return _painters[type_id]


## Real painters by type id; everything else gets a placeholder.
static func _create(type_id: String) -> ModelPainter:
	match type_id:
		"rhinovirus":
			return RhinoPainter.new()
	var p := PlaceholderPainter.new()
	p.size_t = Vector2(DEFAULT_PATHOGEN_WIDTH_T, float(HEIGHT_T.get(type_id, DEFAULT_HEIGHT_T)))
	return p


## Gives each placeholder painter the shape, colour and size of its config definition. Safe to call again.
static func configure(config: GameConfig, iso_scale: float = IsoProjection.DEFAULT_SCALE) -> void:
	if config == null:
		return
	for id_var: Variant in config.pathogens:
		var id: String = id_var
		var def: PathogenDef = config.pathogens[id]
		var pp: ModelPainter = painter_for(id)
		if pp is PlaceholderPainter and def != null:
			var ph: PlaceholderPainter = pp
			ph.shape = def.placeholder_shape
			ph.color = def.placeholder_color
			ph.size_t = Vector2(float(PATHOGEN_WIDTH_T.get(id, DEFAULT_PATHOGEN_WIDTH_T)), float(HEIGHT_T.get(id, DEFAULT_HEIGHT_T)))
	for id_var: Variant in config.structures:
		var id: String = id_var
		var def: StructureDef = config.structures[id]
		var sp: ModelPainter = painter_for(id)
		if sp is PlaceholderPainter and def != null:
			var ph: PlaceholderPainter = sp
			ph.shape = def.placeholder_shape
			ph.color = def.placeholder_color
			ph.size_t = Vector2(float(def.footprint.x) * iso_scale * STRUCTURE_WIDTH_SCALE, float(HEIGHT_T.get(id, DEFAULT_HEIGHT_T)))
