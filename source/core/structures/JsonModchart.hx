package core.structures;

import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;

// =============================================================================
//  JsonModchart — Root document
// =============================================================================

/**
 * Root modchart document loaded from a JSON file alongside a song chart.
 *
 * Resolved file locations (in priority order):
 *   data/<song>/<difficulty>-modchart.json   ← difficulty-specific
 *   data/<song>/modchart.json                ← shared across difficulties
 *
 * Minimal valid JSON:
 * ```json
 * {
 *   "version": "1.0.0",
 *   "tracks": []
 * }
 * ```
 */
typedef JsonModchart =
{
    /**
     * Semantic version of this modchart format.
     * The loader will warn on mismatched major versions.
     * Current: `"1.0.0"`.
     */
    var version:String;

    /** All event tracks in this modchart. Processed in declaration order. */
    var tracks:Array<ModchartTrack>;

    /** Optional informational block — not used at runtime. */
    @:optional var meta:ModchartMeta;
}

// =============================================================================
//  ModchartMeta — Informational block
// =============================================================================

/**
 * Optional metadata embedded in the modchart JSON.
 * Not parsed at runtime; useful for editors and documentation.
 */
typedef ModchartMeta =
{
    /** Human-readable name for this modchart (e.g. `"Week 7 Stress Modchart"`). */
    @:optional var name:String;

    /** Author(s) of the modchart. */
    @:optional var author:String;

    /** Free-form description or notes. */
    @:optional var description:String;

    /** URL to a preview video, image, or documentation page. */
    @:optional var previewUrl:String;
}

// =============================================================================
//  ModchartTrack — Named event group
// =============================================================================

/**
 * A named, ordered list of events.
 *
 * Tracks are evaluated in the order they appear in `JsonModchart.tracks`.
 * Multiple tracks can overlap in time — they are independent sequences.
 *
 * Use tracks to organise events by concern:
 *   `"camera"`, `"strumlines"`, `"characters"`, `"shaders"`, `"misc"` …
 *
 * Example JSON:
 * ```json
 * {
 *   "name": "camera",
 *   "enabled": true,
 *   "events": [ ... ]
 * }
 * ```
 */
typedef ModchartTrack =
{
    /**
     * Unique name for this track.
     * Referenced by `ModchartLoader.getTrack(name)`.
     */
    var name:String;

    /** All events in this track, sorted ascending by `time` before processing. */
    var events:Array<ModchartEvent>;

    /**
     * When `false` the entire track is skipped.
     * Useful for disabling WIP tracks without removing them.
     * Defaults to `true` if absent.
     */
    @:optional var enabled:Bool;
}

// =============================================================================
//  ModchartEvent — Single event / keyframe
// =============================================================================

/**
 * A single modchart action scheduled at a point in time.
 *
 * **Timing** — provide exactly one of:
 *  - `time`  — time in **milliseconds** from song start.
 *  - `beat`  — time in **beats** (converted to ms using chart BPM at that beat).
 *
 * If both are present `time` takes priority.
 *
 * **Target syntax** — a dot-separated address string:
 * | String                    | Resolved object                              |
 * |---------------------------|----------------------------------------------|
 * | `"game"`                  | The PlayState instance                       |
 * | `"camera"` / `"cam.game"` | The main game camera                         |
 * | `"cam.hud"`               | The HUD camera                               |
 * | `"cam.other"`             | The "other" utility camera                   |
 * | `"strumline.0"`           | Strumline at index 0                         |
 * | `"strumline.1"`           | Strumline at index 1                         |
 * | `"note.0.3"`              | Note index 3 inside strumline 0              |
 * | `"receptor.0.2"`          | Receptor (strum) index 2 inside strumline 0  |
 * | `"character.bf"`          | Player character (tag `bf`)                  |
 * | `"character.dad"`         | Opponent character (tag `dad`)               |
 * | `"character.gf"`          | GF/spectator character (tag `gf`)            |
 * | `"sprite.NAME"`           | Named sprite registered via scripts          |
 * | `"hud"`                   | The root HUD group                           |
 *
 * Example JSON:
 * ```json
 * {
 *   "beat": 16,
 *   "type": "tween",
 *   "target": "cam.game",
 *   "property": "zoom",
 *   "value": 1.3,
 *   "duration": 0.5,
 *   "ease": "quadOut"
 * }
 * ```
 */
typedef ModchartEvent =
{
    // -------------------------------------------------------------------------
    // Timing (one of the two must be present)
    // -------------------------------------------------------------------------

    /**
     * Trigger time in **milliseconds** from song start.
     * Takes priority over `beat` if both are supplied.
     */
    @:optional var time:Float;

    /**
     * Trigger time in **beats**.
     * Converted to ms at load-time using the song's BPM map.
     */
    @:optional var beat:Float;

    // -------------------------------------------------------------------------
    // Core fields
    // -------------------------------------------------------------------------

    /**
     * Event type string. Must match a key in `ModchartEventType`.
     * See `ModchartEventType` abstract for the full list.
     */
    var type:String;

    /**
     * Dot-separated address of the object to act on.
     * See the target syntax table in the typedef doc above.
     */
    @:optional var target:String;

    /**
     * A human-readable label for this event.
     * Displayed in editor timelines and debug overlays.
     */
    @:optional var label:String;

    // -------------------------------------------------------------------------
    // Property / value fields  (used by: set, tween, add, multiply)
    // -------------------------------------------------------------------------

    /**
     * The property path to read/write on `target`.
     * Supports dot-notation: `"scale.x"`, `"color"`, `"alpha"`, `"zoom"` …
     */
    @:optional var property:String;

    /**
     * Target value for `set`, `tween`, `add`, and `multiply`.
     * Type depends on the property being animated:
     *   - Numeric properties → `Float` or `Int`
     *   - Color properties   → hex string `"0xFFFF0000"` or ARGB int
     *   - Bool properties    → `Bool`
     */
    @:optional var value:Dynamic;

    // -------------------------------------------------------------------------
    // Tween fields  (used by: tween)
    // -------------------------------------------------------------------------

    /**
     * Duration of the tween in **seconds**.
     * Required for `type: "tween"`.
     */
    @:optional var duration:Float;

    /**
     * Name of the easing function to apply.
     * Must be a valid key in `ModchartEase.fromString`.
     *
     * Common values: `"linear"`, `"quadIn"`, `"quadOut"`, `"quadInOut"`,
     * `"cubeIn"`, `"cubeOut"`, `"elasticOut"`, `"bounceOut"`, `"sineInOut"` …
     *
     * Defaults to `"linear"` if absent.
     */
    @:optional var ease:String;

    /**
     * Delay in **seconds** before the tween starts.
     * Defaults to `0`.
     */
    @:optional var delay:Float;

    /**
     * Tween type string for looping behaviour.
     * Maps to `FlxTweenType`: `"oneShot"`, `"looping"`, `"pingPong"`, `"backward"`.
     * Defaults to `"oneShot"`.
     */
    @:optional var tweenType:String;

    // -------------------------------------------------------------------------
    // Animation fields  (used by: playAnim)
    // -------------------------------------------------------------------------

    /**
     * Name of the animation to play on the target sprite/character.
     * Required for `type: "playAnim"`.
     */
    @:optional var anim:String;

    /**
     * When `true`, restarts the animation even if it is already playing.
     * Defaults to `false`.
     */
    @:optional var forceAnim:Bool;

    // -------------------------------------------------------------------------
    // Camera shake / flash fields  (used by: shake, flash)
    // -------------------------------------------------------------------------

    /**
     * Shake/flash intensity as a fraction of screen size (0.0 – 1.0).
     * Defaults to `0.05`.
     */
    @:optional var intensity:Float;

    // -------------------------------------------------------------------------
    // Scroll speed fields  (used by: scrollSpeed)
    // -------------------------------------------------------------------------

    /**
     * Target scroll speed multiplier.
     * `1.0` = normal, `2.0` = double, `0.5` = half.
     */
    @:optional var speed:Float;

    // -------------------------------------------------------------------------
    // Function call fields  (used by: function)
    // -------------------------------------------------------------------------

    /**
     * Name of the script function to invoke.
     * The function must be registered in the active script environment.
     */
    @:optional var func:String;

    /**
     * Arguments passed to `func` in order.
     * Each element can be any JSON-serialisable value.
     */
    @:optional var args:Array<Dynamic>;

    // -------------------------------------------------------------------------
    // Shader fields  (used by: shader)
    // -------------------------------------------------------------------------

    /**
     * Shader preset name (resolved via `ShaderRegistry`) or `null` to remove
     * the current shader from the target.
     */
    @:optional var shader:String;

    /**
     * Key/value pairs forwarded as uniform overrides to the shader.
     * The exact keys depend on the shader implementation.
     */
    @:optional var shaderParams:Dynamic;

    // -------------------------------------------------------------------------
    // Toggle / visibility  (used by: toggle, show, hide)
    // -------------------------------------------------------------------------

    /**
     * Explicit visibility state for `type: "toggle"`.
     * Omit to flip the current state.
     * For `type: "show"` / `"hide"` this field is ignored.
     */
    @:optional var visible:Bool;
}

// =============================================================================
//  ModchartEventType — Type-safe event type constants
// =============================================================================

/**
 * All recognised `type` strings for `ModchartEvent`.
 *
 * Use the static inline fields to avoid typos:
 * ```haxe
 * event.type == ModchartEventType.TWEEN
 * ```
 */
abstract ModchartEventType(String) from String to String
{
    // --- Property manipulation -----------------------------------------------

    /** Instantly set a property to `value`. */
    public static inline var SET:ModchartEventType           = "set";

    /** Tween a numeric property from its current value to `value`. */
    public static inline var TWEEN:ModchartEventType         = "tween";

    /** Add `value` to a numeric property (relative offset). */
    public static inline var ADD:ModchartEventType           = "add";

    /** Multiply a numeric property by `value`. */
    public static inline var MULTIPLY:ModchartEventType      = "multiply";

    // --- Animation -----------------------------------------------------------

    /** Play an animation on the target sprite or character. */
    public static inline var PLAY_ANIM:ModchartEventType     = "playAnim";

    // --- Visibility ----------------------------------------------------------

    /** Show the target (`visible = true`). */
    public static inline var SHOW:ModchartEventType          = "show";

    /** Hide the target (`visible = false`). */
    public static inline var HIDE:ModchartEventType          = "hide";

    /** Flip the target's current visibility, or set it via `visible`. */
    public static inline var TOGGLE:ModchartEventType        = "toggle";

    // --- Camera effects ------------------------------------------------------

    /** Shake a camera. Uses `target`, `intensity`, `duration`. */
    public static inline var SHAKE:ModchartEventType         = "shake";

    /** Flash a camera to a color. Uses `target`, `value` (color), `duration`. */
    public static inline var FLASH:ModchartEventType         = "flash";

    /** Fade a camera in or out. Uses `target`, `value` (color), `duration`. */
    public static inline var FADE:ModchartEventType          = "fade";

    // --- Gameplay ------------------------------------------------------------

    /** Change chart scroll speed. Uses `speed`, optional `duration` + `ease`. */
    public static inline var SCROLL_SPEED:ModchartEventType  = "scrollSpeed";

    /** Lock or unlock player input. Uses `value` (Bool). */
    public static inline var INPUT_LOCK:ModchartEventType    = "inputLock";

    // --- Scripting -----------------------------------------------------------

    /** Call a named script function with optional `args`. */
    public static inline var FUNCTION:ModchartEventType      = "function";

    // --- Shaders -------------------------------------------------------------

    /** Apply or remove a shader on the target. Uses `shader`, `shaderParams`. */
    public static inline var SHADER:ModchartEventType        = "shader";
}

// =============================================================================
//  ModchartEase — Ease name → FlxEase function resolver
// =============================================================================

/**
 * Resolves a string ease name (as stored in JSON) to the corresponding
 * `FlxEase` function pointer at runtime.
 *
 * Usage:
 * ```haxe
 * final easeFn = ModchartEase.fromString(event.ease); // never null
 * FlxTween.tween(target, {alpha: 0}, 0.5, {ease: easeFn});
 * ```
 */
class ModchartEase
{
    /** Fallback used when the name is unrecognised or null. */
    public static final DEFAULT:EaseFunction = FlxEase.linear;

    static final _map:Map<String, EaseFunction> = [
        // Linear
        "linear"        => FlxEase.linear,
        // Quadratic
        "quadIn"        => FlxEase.quadIn,
        "quadOut"       => FlxEase.quadOut,
        "quadInOut"     => FlxEase.quadInOut,
        // Cubic
        "cubeIn"        => FlxEase.cubeIn,
        "cubeOut"       => FlxEase.cubeOut,
        "cubeInOut"     => FlxEase.cubeInOut,
        // Quartic
        "quartIn"       => FlxEase.quartIn,
        "quartOut"      => FlxEase.quartOut,
        "quartInOut"    => FlxEase.quartInOut,
        // Quintic
        "quintIn"       => FlxEase.quintIn,
        "quintOut"      => FlxEase.quintOut,
        "quintInOut"    => FlxEase.quintInOut,
        // Sine
        "sineIn"        => FlxEase.sineIn,
        "sineOut"       => FlxEase.sineOut,
        "sineInOut"     => FlxEase.sineInOut,
        // Bounce
        "bounceIn"      => FlxEase.bounceIn,
        "bounceOut"     => FlxEase.bounceOut,
        "bounceInOut"   => FlxEase.bounceInOut,
        // Back
        "backIn"        => FlxEase.backIn,
        "backOut"       => FlxEase.backOut,
        "backInOut"     => FlxEase.backInOut,
        // Elastic
        "elasticIn"     => FlxEase.elasticIn,
        "elasticOut"    => FlxEase.elasticOut,
        "elasticInOut"  => FlxEase.elasticInOut,
        // Expo
        "expoIn"        => FlxEase.expoIn,
        "expoOut"       => FlxEase.expoOut,
        "expoInOut"     => FlxEase.expoInOut,
        // Circ
        "circIn"        => FlxEase.circIn,
        "circOut"       => FlxEase.circOut,
        "circInOut"     => FlxEase.circInOut,
        // Smooth / smoother (Flixel extras)
        "smoothStep"    => FlxEase.smoothStepIn,
        "smoothStepIn"  => FlxEase.smoothStepIn,
        "smoothStepOut" => FlxEase.smoothStepOut,
        "smootherStep"  => FlxEase.smootherStepInOut,
    ];

    /**
     * Returns the `EaseFunction` for `name`, or `DEFAULT` (`FlxEase.linear`)
     * if `name` is `null`, empty, or not in the table.
     */
    public static function fromString(name:String):EaseFunction
    {
        if (name == null || name.length == 0)
            return DEFAULT;

        final fn = _map.get(name);
        if (fn == null)
        {
            FlxG.log.warn('[ModchartEase] Unknown ease "$name" — falling back to linear.');
            return DEFAULT;
        }

        return fn;
    }

    /**
     * Returns `true` if `name` is a recognised ease identifier.
     * Useful for editor validation.
     */
    public static function isValid(name:String):Bool
        return name != null && _map.exists(name);

    /** All registered ease names, sorted alphabetically. For editor dropdowns. */
    public static function allNames():Array<String>
    {
        final names = [for (k in _map.keys()) k];
        names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
        return names;
    }
}

// =============================================================================
//  ModchartLoader — JSON parsing, validation, and beat→ms conversion
// =============================================================================

/**
 * Static utility class for loading, parsing, and pre-processing `JsonModchart`
 * documents from disk or from a raw JSON string.
 *
 * **Typical usage:**
 * ```haxe
 * final modchart = ModchartLoader.fromPath('assets/data/stress/hard-modchart.json');
 * if (modchart != null)
 *     ModchartLoader.resolveTimings(modchart, bpmMap);
 * ```
 */
class ModchartLoader
{
    /** Modchart format version this loader targets. */
    public static inline final SUPPORTED_VERSION:String = "1.0.0";

    // -------------------------------------------------------------------------
    // Loading
    // -------------------------------------------------------------------------

    /**
     * Loads and parses a modchart JSON from an absolute or asset-relative path.
     *
     * Returns `null` if the file does not exist, cannot be read, or fails to
     * parse. All errors are logged via `FlxG.log`.
     *
     * @param path  File path to the `.json` modchart document.
     */
    public static function fromPath(path:String):Null<JsonModchart>
    {
        if (!sys.FileSystem.exists(path))
        {
            FlxG.log.warn('[ModchartLoader] File not found: $path');
            return null;
        }

        try
        {
            final raw:String = sys.io.File.getContent(path);
            return fromString(raw, path);
        }
        catch (e:Dynamic)
        {
            FlxG.log.error('[ModchartLoader] Failed to read "$path": $e');
            return null;
        }
    }

    /**
     * Parses a raw JSON string into a `JsonModchart`.
     *
     * @param json    Raw JSON source.
     * @param origin  Optional label used in log messages (e.g. the file path).
     */
    public static function fromString(json:String, ?origin:String):Null<JsonModchart>
    {
        final label = origin ?? "<string>";

        try
        {
            final data:JsonModchart = haxe.Json.parse(json);
            return validate(data, label) ? data : null;
        }
        catch (e:Dynamic)
        {
            FlxG.log.error('[ModchartLoader] JSON parse error in "$label": $e');
            return null;
        }
    }

    // -------------------------------------------------------------------------
    // Validation
    // -------------------------------------------------------------------------

    /**
     * Validates the basic structure of a parsed modchart.
     * Logs warnings for non-fatal issues (e.g. version mismatch) and errors
     * for fatal issues (missing required fields).
     *
     * @return `true` if the modchart is safe to use, `false` if it is broken.
     */
    public static function validate(chart:JsonModchart, ?origin:String):Bool
    {
        final label = origin ?? "<unknown>";

        if (chart == null)
        {
            FlxG.log.error('[ModchartLoader] "$label" parsed to null.');
            return false;
        }

        if (chart.version == null || chart.version.length == 0)
        {
            FlxG.log.warn('[ModchartLoader] "$label" has no version field — assuming $SUPPORTED_VERSION.');
            chart.version = SUPPORTED_VERSION;
        }
        else
        {
            final major = chart.version.split(".")[0];
            final supported = SUPPORTED_VERSION.split(".")[0];
            if (major != supported)
                FlxG.log.warn('[ModchartLoader] "$label" version ${chart.version} may be incompatible (loader targets $SUPPORTED_VERSION).');
        }

        if (chart.tracks == null)
        {
            FlxG.log.error('[ModchartLoader] "$label" missing required "tracks" array.');
            return false;
        }

        // Validate individual events for minimum required fields.
        var valid = true;
        for (trackIdx in 0...chart.tracks.length)
        {
            final track = chart.tracks[trackIdx];
            if (track == null) continue;

            if (track.name == null || track.name.length == 0)
                FlxG.log.warn('[ModchartLoader] "$label" track[$trackIdx] has no name.');

            if (track.events == null)
            {
                FlxG.log.warn('[ModchartLoader] "$label" track "${track.name}" has null events — replacing with [].');
                track.events = [];
                continue;
            }

            for (evIdx in 0...track.events.length)
            {
                final ev = track.events[evIdx];
                if (ev == null) continue;

                if (ev.type == null || ev.type.length == 0)
                {
                    FlxG.log.error('[ModchartLoader] "$label" track "${track.name}" event[$evIdx] missing "type".');
                    valid = false;
                }

                if (!ev.fields().contains("time") && !ev.fields().contains("beat"))
                {
                    FlxG.log.error('[ModchartLoader] "$label" track "${track.name}" event[$evIdx] (${ev.type}) missing both "time" and "beat".');
                    valid = false;
                }
            }
        }

        return valid;
    }

    // -------------------------------------------------------------------------
    // Beat → ms conversion
    // -------------------------------------------------------------------------

    /**
     * Converts all `beat`-based event timings to `time` (milliseconds),
     * then sorts each track's events by `time` ascending.
     *
     * Must be called **after** parsing and **before** runtime processing.
     *
     * @param chart   The modchart to mutate in-place.
     * @param bpmMap  Ordered list of `{beat, bpm}` pairs from the song chart.
     *                At minimum `[{beat: 0, bpm: <startBpm>}]`.
     */
    public static function resolveTimings(chart:JsonModchart, bpmMap:Array<{beat:Float, bpm:Float}>):Void
    {
        if (bpmMap == null || bpmMap.length == 0)
        {
            FlxG.log.warn('[ModchartLoader] resolveTimings: empty BPM map — beat timings will be wrong.');
            return;
        }

        for (track in chart.tracks)
        {
            if (track == null || track.events == null) continue;

            for (ev in track.events)
            {
                if (ev == null) continue;

                // `time` already present — ms is authoritative, skip conversion.
                if (ev.fields().contains("time") && ev.time != null)
                    continue;

                if (ev.beat != null)
                    ev.time = beatToMs(ev.beat, bpmMap);
            }

            // Sort ascending by resolved ms time.
            track.events.sort((a, b) ->
            {
                final ta = (a != null && a.time != null) ? a.time : 0.0;
                final tb = (b != null && b.time != null) ? b.time : 0.0;
                return ta < tb ? -1 : ta > tb ? 1 : 0;
            });
        }
    }

    /**
     * Converts a beat position to milliseconds using a piecewise-constant
     * BPM map.
     *
     * @param beat    The beat position to convert.
     * @param bpmMap  Ordered list of `{beat, bpm}` BPM change points.
     */
    public static function beatToMs(beat:Float, bpmMap:Array<{beat:Float, bpm:Float}>):Float
    {
        var ms:Float = 0.0;
        var prevBeat:Float = 0.0;
        var prevBpm:Float = bpmMap[0].bpm;

        for (change in bpmMap)
        {
            if (change.beat >= beat) break;

            // Accumulate ms for the segment [prevBeat, change.beat].
            ms += (change.beat - prevBeat) * (60000.0 / prevBpm);
            prevBeat = change.beat;
            prevBpm  = change.bpm;
        }

        // Remaining beats after the last BPM change before `beat`.
        ms += (beat - prevBeat) * (60000.0 / prevBpm);
        return ms;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Returns the first track whose `name` matches, or `null` if not found.
     *
     * @param chart  The parsed modchart.
     * @param name   Track name to look up (case-sensitive).
     */
    public static function getTrack(chart:JsonModchart, name:String):Null<ModchartTrack>
    {
        if (chart == null || name == null) return null;
        for (track in chart.tracks)
            if (track != null && track.name == name)
                return track;
        return null;
    }

    /**
     * Returns all events across all enabled tracks, merged and sorted by `time`.
     * Useful for a simple single-pass playback loop.
     *
     * @param chart  The parsed, timing-resolved modchart.
     */
    public static function mergedEvents(chart:JsonModchart):Array<ModchartEvent>
    {
        final all:Array<ModchartEvent> = [];

        for (track in chart.tracks)
        {
            if (track == null || track.events == null) continue;
            if (track.enabled == false) continue;

            for (ev in track.events)
                if (ev != null)
                    all.push(ev);
        }

        all.sort((a, b) ->
        {
            final ta = (a.time != null) ? a.time : 0.0;
            final tb = (b.time != null) ? b.time : 0.0;
            return ta < tb ? -1 : ta > tb ? 1 : 0;
        });

        return all;
    }
}
