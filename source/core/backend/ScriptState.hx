package core.backend;

#if HSCRIPT_ALLOWED
import ale.rulescript.RuleScriptGlobal;
import scripting.haxe.HScript;
import scripting.haxe.HScriptPresetBase;
import rulescript.Context;
#end

#if LUA_ALLOWED
import scripting.lua.LuaScript;
import scripting.lua.LuaPresetBase;
#end

import core.enums.ScriptCallType;
import core.interfaces.IScriptState;

import haxe.Exception;

/**
 * A `MusicBeatState` subclass that hosts and coordinates any number of
 * HScript and/or Lua scripts, providing a unified API for loading, calling,
 * variable sharing, and lifecycle management.
 *
 * ## Design goals
 * - **Safety first** — every call/load path is wrapped; a broken script
 *   never crashes the state.
 * - **Early-stop support** — `callOnScripts` / `scriptCallbackCall` respect
 *   `CoolVars.Function_Stop` and propagate a typed `ScriptCallResult`.
 * - **Correct teardown** — destroy loops use array copies so removing elements
 *   mid-iteration never skips entries.
 * - **Extensible** — override `onScriptLoaded` / `onScriptError` to hook into
 *   the script lifecycle without subclassing the entire load path.
 */
class ScriptState extends MusicBeatState implements IScriptState
{
    // ─── Singleton ─────────────────────────────────────────────────────────

    /** The most recently created `ScriptState`. Cleared on `destroy`. */
    public static var instance:ScriptState;

    // ─── HScript ───────────────────────────────────────────────────────────

    #if HSCRIPT_ALLOWED
    /** All successfully loaded HScript instances. */
    public var hScripts:Array<HScript> = [];

    /** Shared interpreter context injected into every HScript. */
    public var hScriptsContext:Context;

    /** Extra preset classes registered with each new HScript. */
    public var hsCustomCallbacks:Array<Class<HScriptPresetBase>> = [];
    #end

    // ─── Lua ───────────────────────────────────────────────────────────────

    #if LUA_ALLOWED
    /** All successfully loaded Lua script instances. */
    public var luaScripts:Array<LuaScript> = [];

    /** Extra preset classes registered with each new Lua script. */
    public var luaCustomCallbacks:Array<Class<LuaPresetBase>> = [];
    #end

    // ─── Accessors ─────────────────────────────────────────────────────────

    /** Total number of active scripts across both engines. */
    public var scriptCount(get, never):Int;

    private inline function get_scriptCount():Int
    {
        var n:Int = 0;
        #if HSCRIPT_ALLOWED n += hScripts.length; #end
        #if LUA_ALLOWED     n += luaScripts.length; #end
        return n;
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    public function new()
    {
        #if HSCRIPT_ALLOWED
        hScriptsContext = new Context();
        #end

        super();
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────

    override public function create():Void
    {
        instance = this;
        super.create();
    }

    override public function destroy():Void
    {
        destroyScripts();
        instance = null;
        super.destroy();
    }

    // ─── Loading ───────────────────────────────────────────────────────────

    /**
     * Smart-loads a script by inspecting its extension.
     *
     * - `.hx`  → HScript only.
     * - `.lua` → Lua only.
     * - No extension → attempts **both** engines (HScript first, then Lua),
     *   so the same base path can host companion scripts.
     *
     * @param path      Relative path with or without extension.
     * @param haxeArgs  Constructor arguments forwarded to HScript.
     * @param luaArgs   Constructor arguments forwarded to LuaScript.
     */
    public function loadScript(path:String, ?haxeArgs:Array<Dynamic>, ?luaArgs:Array<Dynamic>):Void
    {
        #if HSCRIPT_ALLOWED
        if (path.endsWith('.hx'))
        {
            loadHScript(_stripExt(path, '.hx'), haxeArgs);
            return;
        }
        #end

        #if LUA_ALLOWED
        if (path.endsWith('.lua'))
        {
            loadLuaScript(_stripExt(path, '.lua'), luaArgs);
            return;
        }
        #end

        // No extension — try both engines so one base path can host two scripts.
        #if HSCRIPT_ALLOWED
        loadHScript(path, haxeArgs);
        #end

        #if LUA_ALLOWED
        loadLuaScript(path, luaArgs);
        #end
    }

    /**
     * Loads a single HScript from `path` (without `.hx` extension).
     *
     * Skips silently when the file doesn't exist or when `HSCRIPT_ALLOWED`
     * is not defined.  Calls `onScriptLoaded` on success.
     */
    public function loadHScript(path:String, ?args:Array<Dynamic>):Void
    {
        #if HSCRIPT_ALLOWED
        final fullPath:String = path + RuleScriptGlobal.SCRIPT_EXTENSION;

        if (!Paths.exists(fullPath))
            return;

        if (_hScriptExists(path))
        {
            debugTrace('HScript "$path" is already loaded — skipping duplicate.', HSCRIPT);
            return;
        }

        try
        {
            final script:HScript = new HScript(path, hScriptsContext, args, STATE, hsCustomCallbacks);

            if (script.failedExecution)
            {
                debugTrace('HScript "$path.hx" failed to execute — not added.', ERROR);
                onScriptError(path, 'HScript execution failed.');
                return;
            }

            hScripts.push(script);
            debugTrace('"$path.hx" loaded successfully.', HSCRIPT);
            onScriptLoaded(path, HSCRIPT);
        }
        catch (e:Exception)
        {
            debugTrace('HScript "$path.hx" threw during load: ${e.message}', ERROR);
            onScriptError(path, e.message);
        }
        #end
    }

    /**
     * Loads a single Lua script from `path` (without `.lua` extension).
     *
     * Skips silently when the file doesn't exist or when `LUA_ALLOWED` is
     * not defined.  Calls `onScriptLoaded` on success.
     */
    public function loadLuaScript(path:String, ?args:Array<Dynamic>):Void
    {
        #if LUA_ALLOWED
        final fullPath:String = path + '.lua';

        if (!Paths.exists(fullPath))
            return;

        if (_luaScriptExists(path))
        {
            debugTrace('Lua script "$path" is already loaded — skipping duplicate.', LUA);
            return;
        }

        try
        {
            final script:LuaScript = new LuaScript(Paths.getPath(fullPath), STATE, args, luaCustomCallbacks);

            luaScripts.push(script);
            debugTrace('"$path.lua" loaded successfully.', LUA);
            onScriptLoaded(path, LUA);
        }
        catch (e:Exception)
        {
            debugTrace('Lua script "$path.lua" threw during load: ${e.message}', ERROR);
            onScriptError(path, e.message);
        }
        #end
    }

    // ─── Variable sharing ──────────────────────────────────────────────────

    /**
     * Sets a named variable on **all** active scripts (HScript and Lua).
     *
     * @param name  Variable name visible inside scripts.
     * @param value Value to expose.
     */
    public function setOnScripts(name:String, value:Dynamic):Void
    {
        #if HSCRIPT_ALLOWED setOnHScripts(name, value); #end
        #if LUA_ALLOWED     setOnLuaScripts(name, value); #end
    }

    /**
     * Exposes multiple variables at once to all active scripts.
     *
     * Equivalent to calling `setOnScripts` for every key/value pair in `vars`.
     *
     * @param vars  Map of variable names → values.
     */
    public function setManyOnScripts(vars:Map<String, Dynamic>):Void
    {
        for (name => value in vars)
            setOnScripts(name, value);
    }

    /** Sets a variable on every active HScript. */
    public function setOnHScripts(name:String, value:Dynamic):Void
    {
        #if HSCRIPT_ALLOWED
        for (script in hScripts)
            _safeScriptOp(() -> script.set(name, value), 'setOnHScripts', name);
        #end
    }

    /** Sets a variable on every active Lua script. */
    public function setOnLuaScripts(name:String, value:Dynamic):Void
    {
        #if LUA_ALLOWED
        for (script in luaScripts)
            _safeScriptOp(() -> script.set(name, value), 'setOnLuaScripts', name);
        #end
    }

    // ─── Calling ───────────────────────────────────────────────────────────

    /**
     * Calls `callback` on all active scripts and collects their return values.
     *
     * Iteration stops early (across both engines) if any script returns
     * `CoolVars.Function_Stop`.
     *
     * @param callback   Function name to invoke inside scripts.
     * @param arguments  Positional arguments forwarded to the function.
     * @return           `ScriptCallResult` carrying all return values and
     *                   whether execution was stopped early.
     */
    public function callOnScripts(callback:String, ?arguments:Array<Dynamic>):ScriptCallResult
    {
        final result:ScriptCallResult = new ScriptCallResult();

        #if HSCRIPT_ALLOWED
        final hxResult:ScriptCallResult = callOnHScripts(callback, arguments);
        result.merge(hxResult);
        if (result.stopped) return result;
        #end

        #if LUA_ALLOWED
        final luaResult:ScriptCallResult = callOnLuaScripts(callback, arguments);
        result.merge(luaResult);
        #end

        return result;
    }

    /**
     * Calls `callback` on all HScript instances.
     *
     * Stops early and marks the result if any script returns
     * `CoolVars.Function_Stop`.
     */
    public function callOnHScripts(callback:String, ?arguments:Array<Dynamic>):ScriptCallResult
    {
        final result:ScriptCallResult = new ScriptCallResult();

        #if HSCRIPT_ALLOWED
        for (script in hScripts)
        {
            if (script == null) continue;

            final ret:Dynamic = _safeScriptOp(() -> script.call(callback, arguments ?? []), 'callOnHScripts', callback);

            result.values.push(ret);

            if (ret == CoolVars.Function_Stop)
            {
                result.stopped = true;
                break;
            }
        }
        #end

        return result;
    }

    /**
     * Calls `callback` on all Lua script instances.
     *
     * Stops early and marks the result if any script returns
     * `CoolVars.Function_Stop`.
     */
    public function callOnLuaScripts(callback:String, ?arguments:Array<Dynamic>):ScriptCallResult
    {
        final result:ScriptCallResult = new ScriptCallResult();

        #if LUA_ALLOWED
        for (script in luaScripts)
        {
            if (script == null) continue;

            final ret:Dynamic = _safeScriptOp(() -> script.call(callback, arguments ?? []), 'callOnLuaScripts', callback);

            result.values.push(ret);

            if (ret == CoolVars.Function_Stop)
            {
                result.stopped = true;
                break;
            }
        }
        #end

        return result;
    }

    /**
     * Convenience helper that fires a typed callback event and returns
     * whether execution should **continue** (i.e. no script returned
     * `Function_Stop`).
     *
     * The final callback name is `Std.string(type) + id`, e.g. `"onUpdate"`.
     *
     * @param type       Prefix enum value (e.g. `ON`, `POST`).
     * @param id         Event identifier (e.g. `"Update"`).
     * @param globalArgs Arguments sent to both engines when engine-specific
     *                   ones are `null`.
     * @param hxArgs     Arguments sent only to HScript (overrides `globalArgs`).
     * @param luaArgs    Arguments sent only to Lua (overrides `globalArgs`).
     * @return           `true`  → all scripts allowed execution to continue.
     *                   `false` → at least one script returned `Function_Stop`.
     */
    public function scriptCallbackCall(
        type:ScriptCallType,
        id:String,
        ?globalArgs:Array<Dynamic>,
        ?hxArgs:Array<Dynamic>,
        ?luaArgs:Array<Dynamic>
    ):Bool
    {
        final name:String = Std.string(type) + id;

        final hxResult:ScriptCallResult  = callOnHScripts(name,  hxArgs  ?? globalArgs);
        if (hxResult.stopped)  return false;

        final luaResult:ScriptCallResult = callOnLuaScripts(name, luaArgs ?? globalArgs);
        if (luaResult.stopped) return false;

        return true;
    }

    // ─── Teardown ──────────────────────────────────────────────────────────

    /** Destroys all active scripts from both engines. */
    public function destroyScripts():Void
    {
        #if HSCRIPT_ALLOWED destroyHScripts(); #end
        #if LUA_ALLOWED     destroyLuaScripts(); #end
    }

    /**
     * Stops and removes all HScript instances.
     *
     * Uses an array copy before iterating so removal never skips entries.
     */
    public function destroyHScripts():Void
    {
        #if HSCRIPT_ALLOWED
        for (script in hScripts.copy())
        {
            _safeScriptOp(() -> script.destroy(), 'destroyHScripts', '(all)');
            hScripts.remove(script);
        }
        #end
    }

    /**
     * Closes and removes all Lua script instances.
     *
     * Uses an array copy before iterating so removal never skips entries.
     */
    public function destroyLuaScripts():Void
    {
        #if LUA_ALLOWED
        for (script in luaScripts.copy())
        {
            _safeScriptOp(() -> script.close(), 'destroyLuaScripts', '(all)');
            luaScripts.remove(script);
        }
        #end
    }

    /**
     * Destroys and removes the **first** HScript whose load path matches.
     *
     * @return `true` if a script was found and removed.
     */
    public function removeHScript(path:String):Bool
    {
        #if HSCRIPT_ALLOWED
        for (script in hScripts)
        {
            if (script.scriptPath == path)
            {
                _safeScriptOp(() -> script.destroy(), 'removeHScript', path);
                hScripts.remove(script);
                return true;
            }
        }
        #end
        return false;
    }

    /**
     * Closes and removes the **first** Lua script whose load path matches.
     *
     * @return `true` if a script was found and removed.
     */
    public function removeLuaScript(path:String):Bool
    {
        #if LUA_ALLOWED
        for (script in luaScripts)
        {
            if (script.scriptPath == path)
            {
                _safeScriptOp(() -> script.close(), 'removeLuaScript', path);
                luaScripts.remove(script);
                return true;
            }
        }
        #end
        return false;
    }

    // ─── Hooks ─────────────────────────────────────────────────────────────

    /**
     * Called after a script is successfully loaded.
     *
     * Override in subclasses to react to script load events (e.g. to call
     * an init callback on the newly loaded script).
     *
     * @param path   Base path that was loaded (no extension).
     * @param engine Which scripting engine loaded the script.
     */
    public function onScriptLoaded(path:String, engine:ScriptEngine):Void {}

    /**
     * Called when a script fails to load or execute.
     *
     * Override to show in-game error notifications or log to a file.
     *
     * @param path    Base path that was attempted.
     * @param reason  Human-readable error message.
     */
    public function onScriptError(path:String, reason:String):Void {}

    // ─── Private helpers ───────────────────────────────────────────────────

    /**
     * Runs `fn`, catches any exception, logs it, and returns `null` on failure.
     *
     * @param fn    Operation to attempt.
     * @param op    Calling method name (for tracing).
     * @param ctx   Context string (callback / variable name) for tracing.
     */
    private function _safeScriptOp<T>(fn:() -> T, op:String, ctx:String):Null<T>
    {
        try
            return fn()
        catch (e:Exception)
        {
            debugTrace('[$op] Error on "$ctx": ${e.message}', ERROR);
            return null;
        }
        catch (e:Dynamic)
        {
            debugTrace('[$op] Unknown error on "$ctx": $e', ERROR);
            return null;
        }
    }

    /** Strips `ext` from the end of `path` if present. */
    private inline function _stripExt(path:String, ext:String):String
        return path.endsWith(ext) ? path.substr(0, path.length - ext.length) : path;

    #if HSCRIPT_ALLOWED
    /** Returns `true` if an HScript with the given path is already loaded. */
    private function _hScriptExists(path:String):Bool
    {
        for (s in hScripts)
            if (s.scriptPath == path) return true;
        return false;
    }
    #end

    #if LUA_ALLOWED
    /** Returns `true` if a Lua script with the given path is already loaded. */
    private function _luaScriptExists(path:String):Bool
    {
        for (s in luaScripts)
            if (s.scriptPath == path) return true;
        return false;
    }
    #end
}

// ─── Supporting types ──────────────────────────────────────────────────────

/**
 * Identifies which scripting engine produced a result or event.
 *
 * Used in `onScriptLoaded` / `onScriptError` to let subclasses react
 * differently per engine.
 */
enum ScriptEngine
{
    HSCRIPT;
    LUA;
}

/**
 * Collects return values from a multi-script callback invocation and
 * records whether any script requested an early stop.
 *
 * ## Usage
 * ```haxe
 * final res = callOnScripts('onUpdate', [elapsed]);
 * if (!res.stopped) doNormalUpdate();
 * ```
 */
class ScriptCallResult
{
    /** Return values from every script that was called, in call order. */
    public var values:Array<Dynamic> = [];

    /**
     * `true` if any script returned `CoolVars.Function_Stop`, causing
     * iteration to end before all scripts were called.
     */
    public var stopped:Bool = false;

    public function new() {}

    /**
     * Merges another `ScriptCallResult` into this one.
     *
     * Values are appended; `stopped` is OR'd.
     */
    public function merge(other:ScriptCallResult):Void
    {
        for (v in other.values)
            values.push(v);

        if (other.stopped)
            stopped = true;
    }

    /**
     * Returns `true` if at least one script returned the given value.
     *
     * @param value  Value to search for (uses `==` equality).
     */
    public inline function contains(value:Dynamic):Bool
        return values.contains(value);

    /**
     * Filters out `null` entries and returns only meaningful return values.
     */
    public function validValues():Array<Dynamic>
        return values.filter(v -> v != null);
}
