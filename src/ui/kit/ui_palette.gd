class_name UiPalette
extends RefCounted

## Day (blue and white) and Night (crimson and green) colour tokens for the HUD kit.
## Values come from the mockup canvas sources and spec section 5.

const DAY: Dictionary = {
	"bg_center": Color("#f4faff"),
	"bg_mid": Color("#d8e9f7"),
	"bg_edge": Color("#b5d2ea"),
	"ink": Color("#12304f"),
	"muted": Color("#576574"),
	"accent": Color("#1e5aa8"),
	"accent_top": Color("#3a7bd0"),
	"on_accent": Color("#ffffff"),
	"accent_shadow": Color(0.1176, 0.3529, 0.6588, 0.4),
	"accent_glow": Color(0.0, 0.0, 0.0, 0.0),
	"accent_ring": Color(0.1176, 0.3529, 0.6588, 0.2),
	"panel": Color(1.0, 1.0, 1.0, 0.9),
	"panel_border": Color("#ffffff"),
	"panel_shadow": Color(0.0706, 0.1882, 0.3098, 0.16),
	"chip": Color("#eaf3fb"),
	"track": Color("#dbe9f6"),
	"secondary_btn_bg": Color("#ffffff"),
	"secondary_btn_border": Color("#c5d9ed"),
	"danger": Color("#b3261e"),
	"danger_tint": Color("#fdf1ef"),
	"danger_border": Color("#f3c6c0"),
	"atp_badge": Color("#fff3c4"),
	"stepper_bg": Color("#eaf3fb"),
	"stepper_border": Color("#c5d9ed"),
	"stepper_card": Color(1.0, 1.0, 1.0, 0.9),
	"dim_overlay": Color(0.0392, 0.098, 0.1765, 0.55),
	"disabled_fill": Color("#dfe7ef"),
	"disabled_text": Color("#8fa3b8"),
	"toggle_off": Color("#9fb3c8"),
	"knob": Color("#ffffff"),
	"dashed_border": Color("#576574"),
	"dashed_fill": Color(1.0, 1.0, 1.0, 0.75),
	"cell_fill": Color(1.0, 1.0, 1.0, 0.45),
	"cell_ring": Color(0.549, 0.7255, 0.8824, 0.55),
	"vignette": Color(0.1569, 0.3529, 0.5882, 0.18),
}

const NIGHT: Dictionary = {
	"bg_center": Color("#3d141c"),
	"bg_mid": Color("#240a10"),
	"bg_edge": Color("#14050a"),
	"ink": Color("#f5e6e8"),
	"muted": Color("#d3aab0"),
	"accent": Color("#2ecc71"),
	"accent_top": Color("#48e595"),
	"on_accent": Color("#0a2414"),
	"accent_shadow": Color(0.1804, 0.8, 0.4431, 0.4),
	"accent_glow": Color(0.1804, 0.8, 0.4431, 0.35),
	"accent_ring": Color(0.1804, 0.8, 0.4431, 0.2),
	"panel": Color(0.1647, 0.0431, 0.0627, 0.9),
	"panel_border": Color(1.0, 1.0, 1.0, 0.1),
	"panel_shadow": Color(0.0, 0.0, 0.0, 0.45),
	"chip": Color(1.0, 1.0, 1.0, 0.07),
	"track": Color(0.0, 0.0, 0.0, 0.45),
	"secondary_btn_bg": Color(1.0, 1.0, 1.0, 0.05),
	"secondary_btn_border": Color(1.0, 1.0, 1.0, 0.16),
	"danger": Color("#ff8a7e"),
	"danger_tint": Color(0.0, 0.0, 0.0, 0.0),
	"danger_border": Color("#ff8a7e"),
	"atp_badge": Color(1.0, 1.0, 1.0, 0.07),
	"stepper_bg": Color("#1a0709"),
	"stepper_border": Color("#59202a"),
	"stepper_card": Color(0.2275, 0.0588, 0.0863, 0.95),
	"dim_overlay": Color(0.0392, 0.0118, 0.0196, 0.72),
	"disabled_fill": Color(1.0, 1.0, 1.0, 0.12),
	"disabled_text": Color(0.9608, 0.902, 0.9098, 0.45),
	"toggle_off": Color(1.0, 1.0, 1.0, 0.15),
	"knob": Color("#ffffff"),
	"dashed_border": Color("#d3aab0"),
	"dashed_fill": Color(1.0, 1.0, 1.0, 0.05),
	"cell_fill": Color(0.4706, 0.1373, 0.1961, 0.22),
	"cell_ring": Color(1.0, 1.0, 1.0, 0.05),
	"vignette": Color(0.0, 0.0, 0.0, 0.45),
}

const PLUS_DISABLED_FILL: Color = Color("#4a2a30")
const PLUS_DISABLED_TEXT: Color = Color("#b89aa0")


## Returns the token dictionary for a theme. (`get` is reserved by Object, so this is `for_theme`.)
static func for_theme(night: bool) -> Dictionary:
	return NIGHT if night else DAY


static func color(night: bool, token: String) -> Color:
	var theme: Dictionary = NIGHT if night else DAY
	return theme.get(token, Color.MAGENTA) as Color
