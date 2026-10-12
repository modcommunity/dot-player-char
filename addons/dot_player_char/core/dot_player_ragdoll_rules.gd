@tool
class_name DotPlayerRagdollRules
extends DotConfig

## What a dead body does: become a jointed ragdoll, topple as one piece, fall over without
## physics, or vanish — for how long, how many at once, and which death reactions a server
## allows. A [DotConfig], and every field a game exposes as a server cvar through
## [method bind_cvars] (the [code]sv_ragdoll*[/code] set), replicated so each client draws
## under its server's rules.
##
## [b]Presentation only.[/b] A ragdoll collides with the world and nothing collides with it:
## no player trips on a corpse, no shot stops in one, so nothing here can change a match and a
## client that draws less (a phone, a low setting, a browser tab) loses a picture and nothing
## else. A dedicated server never builds one; it only picks the reaction
## ([DotPlayerDeath.decide]).


enum Style {
	## Jointed: one rigid body per part, joined at the hips, shoulders and neck.
	RAGDOLL,
	## One rigid body for the whole figure: it topples over like a felled post.
	STIFF,
	## No physics: a short scripted fall onto the floor, then the fade. The cheapest body that
	## still lies down, and the fallback when [member enabled] is off.
	TOPPLE,
	## Nothing: the body disappears at death, as every game did before this existed.
	HIDE,
}

const CVAR_ENABLED := "sv_ragdoll"
const CVAR_STYLE := "sv_ragdoll_style"
const CVAR_TIME := "sv_ragdoll_time"
const CVAR_MAX := "sv_ragdoll_max"
const CVAR_FORCE := "sv_ragdoll_force"
const CVAR_REACTIONS := "sv_ragdoll_reactions"

## Whether a dead body is physically simulated. Off, every death uses [constant Style.TOPPLE]
## unless [member style] is [constant Style.HIDE].
@export var enabled: bool = true

@export var style: Style = Style.RAGDOLL

## Seconds a body lies there before it starts to fade.
@export_range(0.0, 600.0, 0.5) var lifetime: float = 10.0

## Seconds the fade takes.
@export_range(0.05, 10.0, 0.05) var fade: float = 1.0

## How many bodies may lie about at once. The oldest goes (quickly faded) when a new one
## would pass it. A client may hold fewer: see [member DotPlayerRagdolls.local_cap].
@export_range(1, 64, 1) var max_count: int = 8

## Multiplies every push a reaction gives. 0 drops them all where they stood.
@export_range(0.0, 5.0, 0.05) var force_scale: float = 1.0

## Weights for the reactions, as [method DotPlayerDeathReactions.apply_weights] reads them.
## Empty keeps the stock weights. A weight of 0 turns a reaction off.
@export var reaction_weights: String = ""

## Total mass of a body, in kilograms, shared out over its parts.
@export_range(10.0, 300.0, 1.0) var mass: float = 70.0

## Slows a part's fall through the air. Low: a body should drop like one.
@export_range(0.0, 10.0, 0.01) var linear_damp: float = 0.1

## Slows a part's spin, which is what stops a body flapping on the floor.
@export_range(0.0, 20.0, 0.01) var angular_damp: float = 1.5

## Physics layers a body lands on. Not players: see the class note.
@export_flags_3d_physics var collision_mask: int = 1

## A body slower than this (m/s) on every part, for [member settle_time], has settled and is
## frozen, which is what makes eight bodies on a floor cost nothing.
@export_range(0.0, 2.0, 0.01) var settle_speed: float = 0.25

@export_range(0.05, 5.0, 0.05) var settle_time: float = 0.6

## Seconds after which a body is frozen however it is moving. A body wedged and jittering
## against a wall would otherwise simulate for the whole of [member lifetime].
@export_range(0.5, 60.0, 0.5) var max_sim_time: float = 6.0


func env_prefix() -> String:
	return "DOT_RAGDOLL_"


func cli_prefix() -> String:
	return "--ragdoll-"


## The style a death actually uses, with [member enabled] applied.
func effective_style() -> Style:
	if style == Style.HIDE:
		return Style.HIDE
	if not enabled:
		return Style.TOPPLE
	return style


func validate() -> DotResult:
	if max_count < 1:
		return DotResult.fail(DotError.CODE_INVALID, "max_count must be at least 1.")
	return DotResult.success(self)


static func style_name(value: Style) -> String:
	return String(Style.keys()[value]).to_lower()


## The style for text: a name ([code]ragdoll[/code], [code]stiff[/code], [code]topple[/code],
## [code]hide[/code]) or its number. -1 for neither.
static func style_from(text: String) -> int:
	var t := text.strip_edges().to_lower()
	if t.is_valid_int():
		var n := t.to_int()
		return n if n >= 0 and n < Style.size() else -1
	var at := Array(Style.keys()).map(func(k: String) -> String: return k.to_lower()).find(t)
	return at


# --- Server cvars ------------------------------------------------------------

## The cvars [method bind_cvars] makes: name, current value, description, and a range when it
## has one.
func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_ENABLED, "value": "1" if enabled else "0", "min": 0.0, "max": 1.0,
			"description": "Dead bodies: 1 physically simulated (sv_ragdoll_style), 0 a scripted fall with no physics"},
		{"name": CVAR_STYLE, "value": style_name(style),
			"description": "How a dead body goes down: ragdoll (jointed), stiff (one piece), topple (no physics), hide (vanishes)"},
		{"name": CVAR_TIME, "value": String.num(lifetime), "min": 0.0, "max": 600.0,
			"description": "Seconds a dead body lies there before it fades"},
		{"name": CVAR_MAX, "value": str(max_count), "min": 1.0, "max": 64.0,
			"description": "Most dead bodies at once; the oldest fades when another would pass it"},
		{"name": CVAR_FORCE, "value": String.num(force_scale), "min": 0.0, "max": 5.0,
			"description": "Multiplies every death push and launch; 0 drops bodies where they stood"},
		{"name": CVAR_REACTIONS, "value": reaction_weights,
			"description": "Death reaction weights, id=weight,... (limp, headshot_launch, power_launch, face_plant, crumple); 0 turns one off"},
	]


## Registers the [code]sv_ragdoll*[/code] cvars through [param add] and keeps these rules in
## step with them. [param add] is a server module's [code]add_cvar[/code] or anything shaped
## [code](name, default, description, flags) -> cvar[/code]; a cvar needs a
## [code]changed(old, new)[/code] signal and [code]get_string()[/code]. Returns the cvars.
##
## Duck-typed like dot-combat's [code]DotCombatManager.bind_cvars[/code], because dot-server is
## not a dependency here. [b]Pass dot-server's FLAG_REPLICATED[/b] and have each client
## [method follow_cvars] its link: a client draws the bodies, so it is the one that needs the
## lifetime, the cap and the style. The value a cvar already holds (argv, a config run early)
## is read back after registering.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if spec.has("min") and cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Keeps these rules on a server's values, as [param source] reports them: dot-server's
## [code]DotClientLink[/code] or anything with [code]replicated_cvar(name, fallback)[/code] and a
## [code]replicated_cvar_changed(name, value)[/code] signal. False when it cannot follow (an
## older shell's link), and the rules keep their own values.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var held := String(source.call(&"replicated_cvar", cvar_name, ""))
		if held != "":
			var _applied := set_cvar(cvar_name, held)
	var handler := _on_replicated_cvar
	if not source.is_connected(&"replicated_cvar_changed", handler):
		source.connect(&"replicated_cvar_changed", handler)
	return true


## Applies one cvar by name. False for a name that is not one of these or a value that does
## not parse; the rule keeps what it had.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	match cvar_name:
		CVAR_ENABLED:
			if not text.is_valid_int():
				return _refuse(cvar_name, value)
			enabled = text.to_int() != 0
		CVAR_STYLE:
			var s := style_from(text)
			if s < 0:
				return _refuse(cvar_name, value)
			style = s as Style
		CVAR_TIME:
			if not text.is_valid_float():
				return _refuse(cvar_name, value)
			lifetime = clampf(text.to_float(), 0.0, 600.0)
		CVAR_MAX:
			if not text.is_valid_int():
				return _refuse(cvar_name, value)
			max_count = clampi(text.to_int(), 1, 64)
		CVAR_FORCE:
			if not text.is_valid_float():
				return _refuse(cvar_name, value)
			force_scale = clampf(text.to_float(), 0.0, 5.0)
		CVAR_REACTIONS:
			reaction_weights = text
		_:
			return false
	changed.emit()
	return true


## These rules' weights laid over [param base], in place, or over a fresh stock set when it is
## null. A game that keeps its own catalogue and wants it untouched passes a fresh one.
func reactions(base: DotPlayerDeathReactions = null) -> DotPlayerDeathReactions:
	var out := base if base != null else DotPlayerDeathReactions.stock()
	if reaction_weights.strip_edges() != "":
		var _n := out.apply_weights(reaction_weights)
	return out


func _refuse(cvar_name: String, value: String) -> bool:
	DotLog.warn(CHANNEL, "cvar value not understood; left as it was", {"cvar": cvar_name, "value": value})
	return false


func _on_cvar_changed(_old: String, new_value: String, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, new_value)


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	if cvar_name.begins_with("sv_ragdoll"):
		var _applied := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	return {
		"enabled": enabled,
		"style": style_name(effective_style()),
		"lifetime": lifetime,
		"max": max_count,
		"force": force_scale,
		"weights": reaction_weights,
	}
