class_name NetCopy
extends RefCounted

## Player-facing text for server error codes (docs/SERVER_PLAN.md, "Error codes"). One dictionary for every online screen.

const TEXT: Dictionary = {
	"insufficient_funds": "Not enough resources for that change.",
	"invalid_layout": "The server rejected that base layout. Your base was restored.",
	"layout_too_expensive": "That base costs more than a new base can afford.",
	"maxed": "That upgrade is already at its top level.",
	"unknown_upgrade": "That upgrade is not available.",
	"profile_not_fresh": "Your online base already has raids, so it can't be replaced.",
	"invalid_profile": "The server could not read that base.",
	"busy": "The server is still working on your last change. Try again in a moment.",
	"conflict": "Your base changed on the server. It was reloaded.",
	"rate_limited": "Slow down a little and try again.",
	"update_required": "Update the game to play online.",
	"timeout": "The server is slow to answer. Try again in a moment.",
	"network_error": "Can't reach the server.",
	"not_connected": "Can't reach the server.",
	"offline": "Can't reach the server.",
	"auth_failed": "Could not sign in to the server.",
	"unauthorized": "Could not sign in to the server.",
	"no_profile": "Your online base is not ready yet.",
	"too_many_attempts": "The server could not process that change. Try again.",
	"raid_in_progress": "You already have a raid in progress.",
	"self_raid": "You can't raid your own base.",
	"shielded": "That base is shielded. Try another one.",
	"under_attack": "Someone is raiding that base right now. Try another one.",
	"unknown_player": "That player is no longer available.",
	"unknown_raid": "That raid is no longer available.",
	"not_open": "That raid is already over.",
	"expired": "Raid expired. Your army was spent.",
	"invalid_army": "The server rejected that army.",
	"no_raid": "There is no raid in progress.",
}


static func error_text(code: String) -> String:
	if TEXT.has(code):
		return TEXT[code] as String
	return "Something went wrong (%s)." % code if not code.is_empty() else "Something went wrong."
