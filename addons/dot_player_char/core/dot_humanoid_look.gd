class_name DotHumanoidLook
extends RefCounted

## What one of the family's people looks like: which of the four bodies, and the colours of
## its skin, hair, top and bottom. Pure data, loads nothing, so a server can pick and send one
## without holding the art; [DotHumanoidFigure] draws it.
##
## [b]Colours, not textures.[/b] The four bodies share one flat-swatch atlas, and the figure's
## palette shader swaps the body's own skin, hair, top and bottom swatches for these, so any
## colour anybody picked anywhere (the site's avatar editor, a team, a class) can be worn
## without a texture per look. See docs/people.md.
##
## [b]Everything here is deterministic.[/b] [method stock] draws from a seed with its own
## generator (never the global one), so every client dresses the same player the same way.

## The bodies, in the order a seed or a site letter picks them. All four are on one rig with one
## clip set; their files are `people/people_<id>.glb`.
const BODIES: Array[StringName] = [&"matt", &"lis", &"sam", &"shaun"]

## Skin tones a stock look draws from: real ones, light to dark.
const SKIN_TONES: Array[String] = ["f1d2b6", "e8b994", "d9a07a", "c58a62", "a8714b", "8a5a3a", "6e4630", "523426"]

## Hair a stock look draws from; none near black, which reads as a flat blob under a dim map light.
const HAIR: Array[String] = ["4a3a30", "3b2a20", "5a3b24", "7a5230", "a5784a", "c9a26b", "8c8c8c", "444852", "6b2a1a"]

## Tops and bottoms a stock look draws from: ordinary clothes, nothing that reads as a team.
const TOPS: Array[String] = ["3f5f8a", "8a3f3f", "4f7a4a", "c9a24a", "5a5a62", "e0ddd5", "6a4a7a", "2f3a48", "b8653a", "3a7a78"]
const BOTTOMS: Array[String] = ["2f3a4f", "3a3a3a", "5a4a36", "4a5a3a", "6a6a70", "2a2f38", "7a6a52"]

## The site's built-in avatar is Kenney's blocky kit: eighteen painted people, `skin-a` to
## `skin-r`, chosen per face, top and legs. Measured from the kit's atlases (the colour under
## the most area of that part, `tools/kenney_site_colours.py`): per letter, the
## face's skin and hair, the torso's colour and the legs' colour. A member's site avatar is
## worn as those colours on one of the four bodies, so the person they dressed is recognisable
## without the blocky body itself.
const SITE_SKINS := {
	"a": ["f6d1a5", "4d505e", "cd8961", "37a177"],
	"b": ["8d5641", "3c3c44", "cb4248", "6078cc"],
	"c": ["f6d1a5", "de875f", "44ae7d", "e79a76"],
	"d": ["ffc044", "3d3f4b", "ffc044", "f5b63c"],
	"e": ["f6d1a5", "995a41", "a878e8", "e79a76"],
	"f": ["8d5641", "3c3c44", "58bd98", "8494c9"],
	"g": ["969dbc", "7d829e", "969dbc", "ee3855"],
	"h": ["969dbc", "7d829e", "969dbc", "9a61e7"],
	"i": ["f6d1a5", "969dbc", "d0e8ff", "b7d4f6"],
	"j": ["f6d1a5", "4d505e", "3c4674", "3c4674"],
	"k": ["f6d1a5", "995a41", "a35c41", "b16241"],
	"l": ["4db781", "4d505e", "444c66", "e79a76"],
	"m": ["cc8860", "4d505e", "599374", "599374"],
	"n": ["ffffff", "4d505e", "1abc9c", "1abc9c"],
	"o": ["1abc9c", "543b32", "a35c41", "a5accf"],
	"p": ["f6d1a5", "b56544", "5a60c2", "cd8961"],
	"q": ["8d5641", "3c3c44", "3c3c44", "3c3c44"],
	"r": ["f6d1a5", "4d505e", "4d505e", "484b59"],
}

var body: StringName = &"matt"
var skin: Color = Color("c58a62")
var hair: Color = Color("3b2a20")
var top: Color = Color("3f5f8a")
var bottom: Color = Color("2f3a4f")


static func make(p_body: StringName, p_skin: Color, p_hair: Color, p_top: Color, p_bottom: Color) -> DotHumanoidLook:
	var look := DotHumanoidLook.new()
	look.body = p_body if BODIES.has(p_body) else BODIES[0]
	look.skin = p_skin
	look.hair = p_hair
	look.top = p_top
	look.bottom = p_bottom
	return look


## A stock person from [param seed] (a game passes a hash of the player's id): every client
## makes the same one. Its own generator, never the global one.
static func stock(seed: int) -> DotHumanoidLook:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var look := DotHumanoidLook.new()
	look.body = BODIES[rng.randi_range(0, BODIES.size() - 1)]
	look.skin = Color(SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])
	look.hair = Color(HAIR[rng.randi_range(0, HAIR.size() - 1)])
	look.top = Color(TOPS[rng.randi_range(0, TOPS.size() - 1)])
	look.bottom = Color(BOTTOMS[rng.randi_range(0, BOTTOMS.size() - 1)])
	return look


## A member's site avatar (the site's `builtin` document) as a person: the face's letter picks
## the body and gives skin and hair, the top's and the legs' give the clothes. Null for a
## document that is not the site's, or one with no face, top or legs this table knows.
##
## [b]Duck-typed[/b] (`schema_id`, `part_in(slot)`), so this addon does not depend on
## dot-user-avatar; a [code]DotAvatar[/code] fits.
static func from_site(foreign: Object) -> DotHumanoidLook:
	if foreign == null or not foreign.has_method(&"part_in"):
		return null

	if StringName(str(foreign.get(&"schema_id"))) != &"builtin":
		return null

	var face := site_letter(foreign, &"face")
	var top_letter := site_letter(foreign, &"top")
	var legs := site_letter(foreign, &"legs")

	if face == "" and top_letter == "" and legs == "":
		return null

	# A slot left empty takes the top's (the one every site avatar has), so a member who only
	# chose a top is still dressed in it head to foot.
	var fallback := top_letter if top_letter != "" else (face if face != "" else legs)
	face = face if face != "" else fallback
	top_letter = top_letter if top_letter != "" else fallback
	legs = legs if legs != "" else fallback

	var look := DotHumanoidLook.new()
	look.body = BODIES[("abcdefghijklmnopqr".find(face)) % BODIES.size()]
	look.skin = Color(SITE_SKINS[face][0])
	look.hair = Color(SITE_SKINS[face][1])
	look.top = Color(SITE_SKINS[top_letter][2])
	look.bottom = Color(SITE_SKINS[legs][3])
	return look


## The person one of Kenney's eighteen skins (`a` to `r`) is, worn head to foot: the games that
## drew the blocky kit chose people by its atlas letter, and keep their choices this way. Accepts
## a letter or an atlas path (`.../texture-k.png`). Null for anything else.
static func from_letter(letter_or_path: String) -> DotHumanoidLook:
	var letter := letter_or_path
	if letter.length() != 1:
		var file := letter_or_path.get_file().get_basename()
		letter = file.substr(file.length() - 1, 1) if file.begins_with("texture-") else ""
	if not SITE_SKINS.has(letter):
		return null
	var look := DotHumanoidLook.new()
	look.body = BODIES["abcdefghijklmnopqr".find(letter) % BODIES.size()]
	look.skin = Color(SITE_SKINS[letter][0])
	look.hair = Color(SITE_SKINS[letter][1])
	look.top = Color(SITE_SKINS[letter][2])
	look.bottom = Color(SITE_SKINS[letter][3])
	return look


## The letter of the site's skin in [param slot], or "". The site files a part as
## `<slot>.<option>` (`top.skin-k`); a bare `skin-k` is read too (the trap every game's
## `_site_skin` once fell into, see the avatar-integration notes).
static func site_letter(foreign: Object, slot: StringName) -> String:
	var raw := String(foreign.call(&"part_in", slot)).trim_prefix(String(slot) + ".")

	if raw.length() != 6 or not raw.begins_with("skin-"):
		return ""

	var letter := raw.substr(5, 1)
	return letter if SITE_SKINS.has(letter) else ""


## This look with the top moved [param amount] of the way to [param colour]: a side's colour
## on the torso, which is the first thing anybody needs to read off a body when friendly fire
## is on.
func with_side(colour: Color, amount: float) -> DotHumanoidLook:
	var out := copy()
	out.top = top.lerp(colour, clampf(amount, 0.0, 1.0))
	return out


func copy() -> DotHumanoidLook:
	return DotHumanoidLook.make(body, skin, hair, top, bottom)


## What decides the material: two looks with one key share it.
func key() -> String:
	return "%s|%s|%s|%s|%s" % [body, skin.to_html(false), hair.to_html(false), top.to_html(false), bottom.to_html(false)]


func to_dict() -> Dictionary:
	return {
		"body": String(body),
		"skin": skin.to_html(false),
		"hair": hair.to_html(false),
		"top": top.to_html(false),
		"bottom": bottom.to_html(false),
	}


## The look a dictionary describes, or null for one that is not a look. Unknown bodies become
## the first body rather than a refusal: a body retired later still draws a person.
static func from_dict(data: Dictionary) -> DotHumanoidLook:
	for k in ["skin", "hair", "top", "bottom"]:
		if not data.has(k) or not Color.html_is_valid(str(data[k])):
			return null
	return DotHumanoidLook.make(StringName(str(data.get("body", ""))), Color(str(data["skin"])),
		Color(str(data["hair"])), Color(str(data["top"])), Color(str(data["bottom"])))


func describe() -> Dictionary:
	return to_dict()
