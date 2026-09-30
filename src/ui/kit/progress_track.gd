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


func _draw() -> void:
	var track_rect := Rect2(Vector2.ZERO, Vector2(size.x, TRACK_HEIGHT))
	var radius: float = TRACK_HEIGHT * 0.5
	KitDraw.draw_box(self, track_rect, UiPalette.color(night, "track"), radius)
	if segments.is_empty():
		var w: float = size.x * value
		if w <= 0.0:
			return
		var top: Color = UiPalette.color(night, "accent_top") if not night else UiPalette.color(true, "accent")
		var bottom: Color = UiPalette.color(night, "accent")
		var pts: PackedVector2Array = KitDraw.rounded_rect_points(Rect2(0.0, 0.0, maxf(w, TRACK_HEIGHT), TRACK_HEIGHT), radius)
		var cols := PackedColorArray()
		var span: float = maxf(w, TRACK_HEIGHT)
		for p: Vector2 in pts:
			cols.append(top.lerp(bottom, clampf(p.x / span, 0.0, 1.0)))
		draw_polygon(pts, cols)
		return
	# Multi-segment: clip segments to the capsule by drawing it as flat rectangles inside the rounded ends.
	var x: float = 0.0
	for i: int in range(segments.size()):
		var seg: Dictionary = segments[i]
		var seg_w: float = size.x * (seg["frac"] as float)
		if seg_w <= 0.0:
			continue
		var seg_rect := Rect2(x, 0.0, seg_w, TRACK_HEIGHT)
		var col: Color = seg["color"] as Color
		if i == 0 and i == segments.size() - 1:
			KitDraw.draw_box(self, seg_rect, col, radius)
		elif i == 0:
			KitDraw.draw_box(self, seg_rect, col, radius)
			draw_rect(Rect2(x + seg_w - radius, 0.0, radius, TRACK_HEIGHT), col)
		elif i == segments.size() - 1 and x + seg_w >= size.x - 0.5:
			KitDraw.draw_box(self, seg_rect, col, radius)
			draw_rect(Rect2(x, 0.0, radius, TRACK_HEIGHT), col)
		else:
			draw_rect(seg_rect, col)
		x += seg_w
