package core.assets;

import lime.utils.Bytes;

import openfl.utils.AssetLibrary as OGAssetLibrary;
import openfl.display.BitmapData;
import openfl.utils.AssetManifest;
import openfl.utils.AssetType;
import openfl.media.Sound;
import openfl.text.Font as OpenFLFont;

import lime.media.AudioBuffer;
import lime.graphics.Image;
import lime.text.Font;

import sys.io.File;
import sys.FileSystem;

/**
 * A multi-root asset library that resolves files from an ordered list of
 * directories (e.g. mod folder → base assets), with optional per-type
 * in-memory caching and runtime cache control.
 *
 * Root priority is **first-wins**: the first root that contains the
 * requested file is used, allowing mods to shadow base assets simply by
 * placing a file with the same relative path in a higher-priority root.
 *
 * ## Example
 * ```haxe
 * final lib = new AssetLibrary(['mods/myMod', 'assets'], true);
 * Assets.registerLibrary('default', lib);
 * ```
 */
class AssetLibrary extends OGAssetLibrary
{
    // ─── Public ────────────────────────────────────────────────────────────

    /** Ordered list of root directories. First entry has highest priority. */
    public final roots:Array<String>;

    /** Whether in-memory caching is active. Can be toggled at runtime. */
    public var cachingEnabled:Bool;

    // ─── Private caches ────────────────────────────────────────────────────

    /** Raw byte cache, shared by all binary assets. */
    private final _bytesCache:Map<String, Bytes> = [];

    /** Decoded image cache. */
    private final _imageCache:Map<String, Image> = [];

    /** Decoded audio buffer cache. */
    private final _audioCache:Map<String, AudioBuffer> = [];

    /** Lime font cache (keyed by id). */
    private final _fontCache:Map<String, Font> = [];

    /** Loaded text content cache. */
    private final _textCache:Map<String, String> = [];

    // ─── Constructor ───────────────────────────────────────────────────────

    /**
     * @param roots          Ordered list of asset root directories.
     * @param cachingEnabled Whether to cache decoded assets in memory.
     *                       Defaults to `true`.
     */
    public function new(roots:Array<String>, cachingEnabled:Bool = true)
    {
        this.roots = roots;
        this.cachingEnabled = cachingEnabled;

        super();

        _loadManifest();
    }

    // ─── OGAssetLibrary overrides ──────────────────────────────────────────

    /** Returns `true` if any root contains a file at the given relative `id`. */
    override public function exists(id:String, type:String):Bool
        return getPath(id) != null;

    /**
     * Resolves the first real filesystem path for `id` across all roots.
     *
     * @return Absolute path, or `null` if no root contains the file.
     */
    override public function getPath(id:String):Null<String>
    {
        if (id == null || id.length == 0)
            return null;

        for (root in roots)
        {
            final path:String = _join(root, id);

            if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
                return path;
        }

        return null;
    }

    /** Loads raw bytes for `id`, optionally from cache. */
    override public function getBytes(id:String):Null<Bytes>
    {
        if (cachingEnabled && _bytesCache.exists(id))
            return _bytesCache[id];

        final path:String = getPath(id);

        if (path == null)
        {
            _warn('getBytes', id);
            return null;
        }

        final bytes:Bytes = _safeRead(() -> File.getBytes(path), 'getBytes', id);

        if (bytes != null && cachingEnabled)
            _bytesCache[id] = bytes;

        return bytes;
    }

    /** Loads UTF-8 text for `id`, optionally from cache. */
    override public function getText(id:String):Null<String>
    {
        if (cachingEnabled && _textCache.exists(id))
            return _textCache[id];

        final path:String = getPath(id);

        if (path == null)
        {
            _warn('getText', id);
            return null;
        }

        final text:String = _safeRead(() -> File.getContent(path), 'getText', id);

        if (text != null && cachingEnabled)
            _textCache[id] = text;

        return text;
    }

    /** Decodes an `AudioBuffer` from the file at `id`. */
    override public function getAudioBuffer(id:String):Null<AudioBuffer>
    {
        if (cachingEnabled && _audioCache.exists(id))
            return _audioCache[id];

        final bytes:Bytes = getBytes(id);

        if (bytes == null)
            return null;

        final buffer:AudioBuffer = _safeRead(() -> AudioBuffer.fromBytes(bytes), 'getAudioBuffer', id);

        if (buffer != null && cachingEnabled)
            _audioCache[id] = buffer;

        return buffer;
    }

    /** Decodes a `lime.graphics.Image` from the file at `id`. */
    override public function getImage(id:String):Null<Image>
    {
        if (cachingEnabled && _imageCache.exists(id))
            return _imageCache[id];

        final bytes:Bytes = getBytes(id);

        if (bytes == null)
            return null;

        final image:Image = _safeRead(() -> Image.fromBytes(bytes), 'getImage', id);

        if (image != null && cachingEnabled)
            _imageCache[id] = image;

        return image;
    }

    /**
     * Loads and registers a `lime.text.Font` from the file at `id`.
     *
     * The font is automatically registered with OpenFL so it can be used
     * in `TextField`s and `FlxText` without any extra steps.
     */
    override public function getFont(id:String):Null<Font>
    {
        if (cachingEnabled && _fontCache.exists(id))
            return _fontCache[id];

        final bytes:Bytes = getBytes(id);

        if (bytes == null)
            return null;

        final limeFont:Font = _safeRead(() ->
        {
            final f:Font = Font.fromBytes(bytes);
            _registerOpenFLFont(f);
            return f;
        }, 'getFont', id);

        if (limeFont != null && cachingEnabled)
            _fontCache[id] = limeFont;

        return limeFont;
    }

    /**
     * Generic asset getter dispatched by `AssetType`.
     *
     * Falls back to `null` for unrecognised types instead of throwing.
     */
    override public function getAsset(id:String, type:String):Dynamic
    {
        return switch (cast(type, AssetType))
        {
            case BINARY:        getBytes(id);
            case TEXT:          getText(id);
            case IMAGE:         getImage(id);
            case SOUND, MUSIC:  getAudioBuffer(id);
            case FONT:          getFont(id);
            default:
                trace('[AssetLibrary] Unknown asset type "$type" for id "$id".');
                null;
        }
    }

    // ─── Cache control ─────────────────────────────────────────────────────

    /**
     * Removes all cached entries for a specific `id` across every cache map.
     *
     * Useful when a mod hot-reloads a single file.
     */
    public function evict(id:String):Void
    {
        _bytesCache.remove(id);
        _textCache.remove(id);
        _imageCache.remove(id);
        _audioCache.remove(id);
        _fontCache.remove(id);
    }

    /**
     * Clears **all** caches.
     *
     * Call this between state transitions to free memory.
     */
    public function clearCache():Void
    {
        _bytesCache.clear();
        _textCache.clear();
        _imageCache.clear();
        _audioCache.clear();
        _fontCache.clear();
    }

    /**
     * Clears only the cache for a given asset category.
     *
     * @param type One of: `"bytes"`, `"text"`, `"image"`, `"audio"`, `"font"`.
     */
    public function clearCacheFor(type:String):Void
    {
        switch (type.toLowerCase())
        {
            case 'bytes':   _bytesCache.clear();
            case 'text':    _textCache.clear();
            case 'image':   _imageCache.clear();
            case 'audio':   _audioCache.clear();
            case 'font':    _fontCache.clear();
            default:        trace('[AssetLibrary] clearCacheFor: unknown type "$type".');
        }
    }

    // ─── Root management ───────────────────────────────────────────────────

    /**
     * Adds a new root directory at the **front** of the priority list and
     * clears all caches so stale shadow files are not returned.
     *
     * @param root Path to the directory to prepend.
     */
    public function prependRoot(root:String):Void
    {
        if (roots.contains(root))
            return;

        roots.unshift(root);
        clearCache();
    }

    /**
     * Adds a new root directory at the **back** of the priority list
     * (lowest priority, used as a fallback).
     *
     * @param root Path to the directory to append.
     */
    public function appendRoot(root:String):Void
    {
        if (!roots.contains(root))
            roots.push(root);
    }

    /**
     * Removes a root directory and clears all caches.
     *
     * @return `true` if the root was found and removed.
     */
    public function removeRoot(root:String):Bool
    {
        final removed:Bool = roots.remove(root);

        if (removed)
            clearCache();

        return removed;
    }

    // ─── Utility ───────────────────────────────────────────────────────────

    /**
     * Lists all relative asset IDs visible from any root that match an
     * optional file extension filter.
     *
     * Files in higher-priority roots shadow same-path files in lower ones,
     * so each relative path appears at most once in the result.
     *
     * @param ext  Optional extension filter, e.g. `".png"`. Case-insensitive.
     *             Pass `null` to list every file.
     * @return     Sorted array of unique relative asset IDs.
     */
    public function listAssets(?ext:String):Array<String>
    {
        final seen:Map<String, Bool> = [];
        final result:Array<String> = [];

        for (root in roots)
            _collectFiles(root, root, ext, seen, result);

        result.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);

        return result;
    }

    /**
     * Returns a compact debug summary of the library state.
     *
     * Includes root list and per-cache entry counts.
     */
    public function debugInfo():String
    {
        final sb = new StringBuf();
        sb.add('AssetLibrary {\n');
        sb.add('  roots       : [${roots.join(", ")}]\n');
        sb.add('  caching     : $cachingEnabled\n');
        sb.add('  cache/bytes : ${_countMap(_bytesCache)}\n');
        sb.add('  cache/text  : ${_countMap(_textCache)}\n');
        sb.add('  cache/image : ${_countMap(_imageCache)}\n');
        sb.add('  cache/audio : ${_countMap(_audioCache)}\n');
        sb.add('  cache/font  : ${_countMap(_fontCache)}\n');
        sb.add('}');
        return sb.toString();
    }

    // ─── Private helpers ───────────────────────────────────────────────────

    /** Loads and applies the OpenFL asset manifest. */
    private function _loadManifest():Void
    {
        final manifestPath:String = #if switch 'romfs:/' + #end 'manifest/default.json';

        try
        {
            final manifest:AssetManifest = AssetManifest.fromFile(manifestPath);

            if (manifest != null)
                __fromManifest(manifest);
        }
        catch (e)
        {
            trace('[AssetLibrary] Could not load manifest at "$manifestPath": $e');
        }
    }

    /**
     * Joins a root and a relative id with exactly one `/` separator,
     * normalising duplicate slashes.
     */
    private inline function _join(root:String, id:String):String
    {
        final r:String = StringTools.endsWith(root, '/') ? root.substr(0, root.length - 1) : root;
        final i:String = StringTools.startsWith(id, '/')  ? id.substr(1) : id;
        return '$r/$i';
    }

    /**
     * Wraps a potentially-throwing read operation, returning `null` on failure.
     *
     * @param fn    The operation to attempt.
     * @param op    Name of the calling method (for tracing).
     * @param id    Asset id (for tracing).
     */
    private function _safeRead<T>(fn:() -> T, op:String, id:String):Null<T>
    {
        try
            return fn()
        catch (e)
        {
            trace('[AssetLibrary] $op("$id") failed: $e');
            return null;
        }
    }

    /** Logs a missing-asset warning. */
    private inline function _warn(op:String, id:String):Void
        trace('[AssetLibrary] $op("$id"): file not found in any root.');

    /**
     * Wraps a Lime font in an OpenFL font object and registers it globally
     * so it can be referenced by name in `openfl.text.TextFormat`.
     */
    private function _registerOpenFLFont(limeFont:Font):Void
    {
        final openFLFont:OpenFLFont = new OpenFLFont();
        @:privateAccess openFLFont.__fromLimeFont(limeFont);
        OpenFLFont.registerFont(openFLFont);
    }

    /**
     * Recursively walks `dir`, collecting relative paths (relative to `root`)
     * that haven't been seen yet, optionally filtered by `ext`.
     */
    private function _collectFiles(
        root:String,
        dir:String,
        ext:Null<String>,
        seen:Map<String, Bool>,
        result:Array<String>
    ):Void
    {
        if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
            return;

        for (entry in FileSystem.readDirectory(dir))
        {
            final full:String = _join(dir, entry);

            if (FileSystem.isDirectory(full))
            {
                _collectFiles(root, full, ext, seen, result);
            }
            else
            {
                // Build the relative id by stripping the root prefix.
                final rel:String = full.substr(root.length + 1);

                if (seen.exists(rel))
                    continue;

                if (ext != null && !StringTools.endsWith(rel.toLowerCase(), ext.toLowerCase()))
                    continue;

                seen[rel] = true;
                result.push(rel);
            }
        }
    }

    /** Returns the number of entries in a `Map` without materialising an array. */
    private inline function _countMap<K, V>(map:Map<K, V>):Int
    {
        var n:Int = 0;
        for (_ in map) n++;
        return n;
    }
}
