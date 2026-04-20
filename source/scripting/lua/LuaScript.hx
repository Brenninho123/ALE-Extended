package scripting.lua;

#if LUA_ALLOWED

import cpp.RawPointer;
import hxluajit.wrapper.LuaUtils;
import hxluajit.wrapper.LuaConverter;
import hxluajit.wrapper.LuaError;
import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;
import scripting.lua.callbacks.LuaImport;
import scripting.ScriptConfig;
import haxe.ds.StringMap;
import core.enums.StateType;

/**
 * Wraps a single hxluajit Lua state, providing a safe Haxe-friendly interface
 * for loading scripts, calling functions, and exchanging variables.
 *
 * Lifecycle:
 *   1. `new()` — creates the state, registers callbacks, and runs the file/string.
 *   2. `call()` / `set()` / `get()` — interact with the running script.
 *   3. `close()` — tears down the state; all further calls become no-ops.
 */
class LuaScript
{
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /** Maximum Haxe-side call depth to prevent mutual-recursion stack overflows. */
    static inline final MAX_CALL_DEPTH:Int = 64;

    // -------------------------------------------------------------------------
    // Static state
    // -------------------------------------------------------------------------

    /** The LuaScript currently executing a `call()`. Used by callback handlers
     *  to route back to the correct instance. Saved/restored around every call. */
    public static var current:LuaScript;

    // -------------------------------------------------------------------------
    // Instance fields
    // -------------------------------------------------------------------------

    /** Raw Lua state pointer. Null after `close()`. */
    public var state:LuaStatePointer;

    /** Which game state this script belongs to (PlayState, MenuState, etc.). */
    public var type:StateType;

    /** Absolute or relative path used to load this script. */
    public var name:String;

    /** True once `close()` has been called. All public methods become no-ops. */
    public var closed:Bool = false;

    /**
     * Arbitrary Haxe-side key/value store available to the script via callbacks.
     * `'this'` is pre-populated with the LuaScript instance itself.
     */
    public var variables:StringMap<Dynamic> = new StringMap();

    // Tracks Haxe-side call depth to catch runaway mutual recursion.
    var _callDepth:Int = 0;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * Creates a new Lua state and executes the script at `name`.
     *
     * @param name            Path to the `.lua` file to load.
     * @param type            The game state context this script runs in.
     * @param args            Optional arguments forwarded to the script's `new()` function.
     * @param customCallbacks Extra `LuaPresetBase` subclasses to register before execution.
     */
    public function new(name:String, type:StateType, ?args:Array<Dynamic>, ?customCallbacks:Array<Class<LuaPresetBase>>)
    {
        this.name = name;
        this.type = type;

        variables.set('this', this);

        state = LuaL.newstate();
        LuaCallbackHandler.applyID(state, name);

        final lastLua:LuaScript = current;
        current = this;

        try
        {
            // Register built-in presets and user-configured classes/typedefs.
            new LuaPreset(this);

            for (cls in ScriptConfig.CLASSES)
                LuaImport.importClass(Type.getClassName(cls));

            for (def in ScriptConfig.TYPEDEFS.keys())
                LuaImport.importClass(Type.getClassName(ScriptConfig.TYPEDEFS.get(def)), def);

            for (callbacks in (customCallbacks ?? []))
                Type.createInstance(callbacks, [this]);

            LuaL.openlibs(state);

            // Verify the file exists before handing it to Lua, so we get a
            // meaningful Haxe-level message rather than a cryptic Lua error.
            if (!sys.FileSystem.exists(name))
            {
                debugTrace('[$name] Script file not found — skipping load.', ERROR);
                closed = true;
                return;
            }

            if (LuaL.dofile(state, name) != 0)
            {
                final msg:String = LuaError.getMessage(state, -1);
                Lua.pop(state, 1); // pop the error string off the stack
                LuaError.errorHandler('[$name] Load error: $msg');
                closed = true;
                return;
            }
        }
        finally
        {
            // Always restore the previous script context, even on exception.
            current = lastLua;
        }

        // Fire the script's optional `new` entry-point.
        call('new', args ?? []);
    }

    // -------------------------------------------------------------------------
    // Script loading from string
    // -------------------------------------------------------------------------

    /**
     * Alternative constructor: loads Lua source from a raw `code` string
     * instead of a file path. `name` is used only for error messages.
     *
     * @param name  A human-readable label (e.g. `"inline:myMod"`).
     * @param code  Raw Lua source code.
     * @param type  The game state context.
     * @param args  Forwarded to the script's `new()` function.
     */
    public static function fromString(name:String, code:String, type:StateType, ?args:Array<Dynamic>):LuaScript
    {
        final script = new LuaScript.__noLoad(name, type);

        final lastLua:LuaScript = current;
        current = script;

        try
        {
            new LuaPreset(script);
            LuaL.openlibs(script.state);

            if (LuaL.dostring(script.state, code) != 0)
            {
                final msg:String = LuaError.getMessage(script.state, -1);
                Lua.pop(script.state, 1);
                LuaError.errorHandler('[$name] String load error: $msg');
                script.closed = true;
                return script;
            }
        }
        finally
        {
            current = lastLua;
        }

        script.call('new', args ?? []);
        return script;
    }

    // Private constructor used by `fromString` to skip the file-loading path.
    @:noCompletion
    function __noLoad(name:String, type:StateType)
    {
        this.name = name;
        this.type = type;
        variables.set('this', this);
        state = LuaL.newstate();
        LuaCallbackHandler.applyID(state, name);
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Calls a global Lua function by `name`, passing `args`, and returns its
     * first return value (or `CoolVars.Function_Continue` if absent/error).
     *
     * Re-entrant: saves and restores `current` even when called from within
     * another Lua callback.
     *
     * @param name  Global function name in the Lua state.
     * @param args  Arguments to push. May be null (treated as empty).
     * @return      First return value, or `CoolVars.Function_Continue`.
     */
    public function call(name:String, args:Array<Dynamic>):Dynamic
    {
        if (closed || state == null)
            return CoolVars.Function_Continue;

        if (_callDepth >= MAX_CALL_DEPTH)
        {
            debugTrace('[$this.name] Max call depth ($MAX_CALL_DEPTH) reached while calling "$name" — possible infinite recursion.', ERROR);
            return CoolVars.Function_Continue;
        }

        final lastLua:LuaScript = current;
        current = this;
        _callDepth++;

        try
        {
            Lua.getglobal(state, name);

            // Function doesn't exist in this script — silently skip.
            if (Lua.isnil(state, -1) != 0)
            {
                Lua.pop(state, 1);
                return CoolVars.Function_Continue;
            }

            args ??= [];
            for (arg in args)
                LuaConverter.toLua(state, arg);

            final status:Int = Lua.pcall(state, args.length, 1, 0);

            if (status != Lua.OK)
            {
                final msg:String = LuaError.getMessage(state, -1);
                Lua.pop(state, 1);
                if (LuaError.errorHandler != null)
                    LuaError.errorHandler('[$this.name] Runtime error in "$name": $msg');
                return CoolVars.Function_Continue;
            }

            // pcall with nresults=1 always pushes exactly one value (nil if the
            // function returned nothing), so we can unconditionally read and pop.
            final result:Dynamic = cast LuaConverter.fromLua(state, -1);
            Lua.pop(state, 1);
            return result;
        }
        catch (error:Dynamic)
        {
            debugTrace('[$this.name] Unexpected exception in call("$name"): $error', ERROR);
            return CoolVars.Function_Continue;
        }
        finally
        {
            _callDepth--;
            current = lastLua;
        }
    }

    /**
     * Sets a global variable or registers a Haxe function in the Lua state.
     *
     * @param name   The global name to assign.
     * @param value  Any Haxe value. Functions are registered as Lua callbacks.
     */
    public function set(name:String, value:Dynamic):Void
    {
        if (closed || state == null)
            return;

        final lastLua:LuaScript = current;
        current = this;

        try
        {
            if (Reflect.isFunction(value))
                LuaCallbackHandler.addFunction(state, name, value);
            else
                LuaUtils.setVariable(state, name, value);
        }
        catch (error:Dynamic)
        {
            debugTrace('[$this.name] Failed to set "$name": $error', ERROR);
        }
        finally
        {
            current = lastLua;
        }
    }

    /**
     * Reads a global variable from the Lua state and returns it as a Haxe value.
     * Returns `null` if the script is closed or the global doesn't exist.
     *
     * @param name  Global variable name in the Lua state.
     */
    public function get(name:String):Dynamic
    {
        if (closed || state == null)
            return null;

        final lastLua:LuaScript = current;
        current = this;

        try
        {
            Lua.getglobal(state, name);

            if (Lua.isnil(state, -1) != 0)
            {
                Lua.pop(state, 1);
                return null;
            }

            final value:Dynamic = cast LuaConverter.fromLua(state, -1);
            Lua.pop(state, 1);
            return value;
        }
        catch (error:Dynamic)
        {
            debugTrace('[$this.name] Failed to get "$name": $error', ERROR);
            return null;
        }
        finally
        {
            current = lastLua;
        }
    }

    /**
     * Returns `true` if a non-nil global named `name` exists in the Lua state.
     * Useful for conditional calls without the overhead of a full `call()`.
     *
     * @param name  Global name to check.
     */
    public function exists(name:String):Bool
    {
        if (closed || state == null)
            return false;

        Lua.getglobal(state, name);
        final exists:Bool = Lua.isnil(state, -1) == 0;
        Lua.pop(state, 1);
        return exists;
    }

    /**
     * Tears down this Lua state, cleans up all registered C callbacks,
     * and marks the script as closed. Safe to call multiple times.
     */
    public function close():Void
    {
        if (closed)
            return;

        closed = true;
        LuaCallbackHandler.cleanupStateFunctions(state);
        Lua.close(state);
        state = null; // prevent dangling-pointer access after close
    }
}

#end
