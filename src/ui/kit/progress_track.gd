class_name ProgressTrack
extends Control

## 14 px rounded progress bar. Single fill via `value` (0..1) or multi-segment via `segments`
## (an Array of {"frac": float, "color": Color}) for the Results ATP split.

const TRACK_HEIGHT: float = 14.0

var night: bool = false:
	set = set_night
var value: float = 0.0:
	set = set_value
var segments: Array[Dictionary] = []:
	set = set_segments
## Bar height in px (the Results ATP split uses 28).
var track_height: float = TRACK_HEIGHT:
	set = set_track_height
## Gap in px left between multi-segment fills (2 on the Results ATP split).
var segment_gap: float = 0.0:
	set = set_segment_gap


func _init() -> void:
	custom_minimum_size = Vector2(0.0, TRACK_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_night(v: bool) -> void:
	night = v
	queue_redraw()


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


func set_segments(v: Array[Dictionary]) -> void:
	segments = v
	queue_redraw()


func set_track_height(v: float) -> void:
	track_height = maxf(v, 2.0)
	custom_minimum_size = Vector2(custom_minimum_size.x, track_height)
	queue_redraw()


func set_segment_gap(v: float) -> void:
	segment_gap = maxf(v, 0.0)
	queue_redraw()


func _draw() -> void:
	var track_rect := Rect2(Vector2.ZERO, Vector2(size.x, track_height))
	var radius: float = track_height * 0.5
	KitDraw.draw_box(self, track_rect, UiPalette.color(night, "track"), radius)
	if segments.is_empty():
		var w: float = size.x * value
		if w <= 0.0:
			return
		var top: Color = UiPalette.color(night, "accent_top") if not night else UiPalette.color(true, "accent")
		var bottom: Color = UiPalette.color(night, "accent")
		var pts: PackedVector2Array = KitDraw.rounded_rect_points(Rect2(0.0, 0.0, maxf(w, track_height), track_height), radius)
		var cols := PackedColorArray()
		var span: float = maxf(w, track_height)
		for p: Vector2 in pts:
			cols.append(top.lerp(bottom, clampf(p.x / span, 0.0, 1.0)))
		draw_polygon(pts, cols)
		return
	# Multi-segment: the first and last fills get the capsule's rounded ends, the rest are flat rectangles.
	# Every fill but the last is drawn `segment_gap` short so the dark track shows between them.
	var x: float = 0.0
	for i: int in range(segments.size()):
		var seg: Dictionary = segments[i]
		var seg_w: float = size.x * (seg["frac"] as float)
		if seg_w <= 0.0:
			continue
		var is_last: bool = i == segments.size() - 1 or x + seg_w >= size.x - 0.5
		var draw_w: float = seg_w if is_last else maxf(seg_w - segment_gap, 1.0)
		var seg_rect := Rect2(x, 0.0, draw_w, track_height)
		var col: Color = seg["color"] as Color
		var cap: float = minf(radius, draw_w)
		if draw_w < radius * 2.0 and i > 0:
			draw_rect(seg_rect, col)
		elif i == 0 and is_last:
			KitDraw.draw_box(self, seg_rect, col, radius)
		elif i == 0:
			KitDraw.draw_box(self, seg_rect, col, radius)
			draw_rect(Rect2(x + draw_w - cap, 0.0, cap, track_height), col)
		elif is_last:
			KitDraw.draw_box(self, seg_rect, col, radius)
			draw_rect(Rect2(x, 0.0, cap, track_height), col)
		else:
			draw_rect(seg_rect, col)
		x += seg_w
