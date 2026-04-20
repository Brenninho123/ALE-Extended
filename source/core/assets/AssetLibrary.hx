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

class AssetLibrary extends OGAssetLibrary
{
    public var cachingEnabled:Bool;

    public var roots(get, never):Array<String>;
    inline function get_roots():Array<String> return _roots;

    private final _roots:Array<String>;

    private final _bytesCache:Map<String, Bytes>       = [];
    private final _imageCache:Map<String, Image>       = [];
    private final _bitmapCache:Map<String, BitmapData> = [];
    private final _audioCache:Map<String, AudioBuffer> = [];
    private final _soundCache:Map<String, Sound>       = [];
    private final _fontCache:Map<String, Font>         = [];
    private final _textCache:Map<String, String>       = [];

    public function new(roots:Array<String>, cachingEnabled:Bool = true)
    {
        _roots = roots;
        this.cachingEnabled = cachingEnabled;

        super();

        _loadManifest();
    }

    override public function exists(id:String, type:String):Bool
        return getPath(id) != null;

    override public function getPath(id:String):Null<String>
    {
        if (id == null || id.length == 0)
            return null;

        for (root in _roots)
        {
            final path = _join(root, id);

            if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
                return path;
        }

        return null;
    }

    override public function getBytes(id:String):Null<Bytes>
    {
        if (cachingEnabled && _bytesCache.exists(id))
            return _bytesCache[id];

        final path = getPath(id);

        if (path == null)
        {
            _warn('getBytes', id);
            return null;
        }

        final bytes = _safeRead(() -> File.getBytes(path), 'getBytes', id);

        if (bytes != null && cachingEnabled)
            _bytesCache[id] = bytes;

        return bytes;
    }

    override public function getText(id:String):Null<String>
    {
        if (cachingEnabled && _textCache.exists(id))
            return _textCache[id];

        final path = getPath(id);

        if (path == null)
        {
            _warn('getText', id);
            return null;
        }

        final text = _safeRead(() -> File.getContent(path), 'getText', id);

        if (text != null && cachingEnabled)
            _textCache[id] = text;

        return text;
    }

    override public function getAudioBuffer(id:String):Null<AudioBuffer>
    {
        if (cachingEnabled && _audioCache.exists(id))
            return _audioCache[id];

        final bytes = getBytes(id);

        if (bytes == null)
            return null;

        final buffer = _safeRead(() -> AudioBuffer.fromBytes(bytes), 'getAudioBuffer', id);

        if (buffer != null && cachingEnabled)
            _audioCache[id] = buffer;

        return buffer;
    }

    override public function getSound(id:String):Null<Sound>
    {
        if (cachingEnabled && _soundCache.exists(id))
            return _soundCache[id];

        final buffer = getAudioBuffer(id);

        if (buffer == null)
            return null;

        final sound = _safeRead(() -> Sound.fromAudioBuffer(buffer), 'getSound', id);

        if (sound != null && cachingEnabled)
            _soundCache[id] = sound;

        return sound;
    }

    override public function getImage(id:String):Null<Image>
    {
        if (cachingEnabled && _imageCache.exists(id))
            return _imageCache[id];

        final bytes = getBytes(id);

        if (bytes == null)
            return null;

        final image = _safeRead(() -> Image.fromBytes(bytes), 'getImage', id);

        if (image != null && cachingEnabled)
            _imageCache[id] = image;

        return image;
    }

    override public function getBitmapData(id:String):Null<BitmapData>
    {
        if (cachingEnabled && _bitmapCache.exists(id))
            return _bitmapCache[id];

        final image = getImage(id);

        if (image == null)
            return null;

        final bitmap = _safeRead(() -> BitmapData.fromImage(image), 'getBitmapData', id);

        if (bitmap != null && cachingEnabled)
            _bitmapCache[id] = bitmap;

        return bitmap;
    }

    override public function getFont(id:String):Null<Font>
    {
        if (cachingEnabled && _fontCache.exists(id))
            return _fontCache[id];

        final bytes = getBytes(id);

        if (bytes == null)
            return null;

        final limeFont = _safeRead(() ->
        {
            final f = Font.fromBytes(bytes);
            _registerOpenFLFont(f);
            return f;
        }, 'getFont', id);

        if (limeFont != null && cachingEnabled)
            _fontCache[id] = limeFont;

        return limeFont;
    }

    override public function getAsset(id:String, type:String):Dynamic
    {
        try
        {
            return switch (cast(type, AssetType))
            {
                case BINARY:        getBytes(id);
                case TEXT:          getText(id);
                case IMAGE:         getBitmapData(id);
                case SOUND, MUSIC:  getSound(id);
                case FONT:          getFont(id);
                default:
                    trace('[AssetLibrary] Unknown asset type "$type" for id "$id".');
                    null;
            }
        }
        catch (e)
        {
            trace('[AssetLibrary] getAsset("$id", "$type") cast failed: $e');
            return null;
        }
    }

    public function evict(id:String):Void
    {
        _bytesCache.remove(id);
        _textCache.remove(id);
        _imageCache.remove(id);
        _bitmapCache.remove(id);
        _audioCache.remove(id);
        _soundCache.remove(id);
        _fontCache.remove(id);
    }

    public function clearCache():Void
    {
        _bytesCache.clear();
        _textCache.clear();
        _imageCache.clear();
        _bitmapCache.clear();
        _audioCache.clear();
        _soundCache.clear();
        _fontCache.clear();
    }

    public function clearCacheFor(type:String):Void
    {
        switch (type.toLowerCase())
        {
            case 'bytes':   _bytesCache.clear();
            case 'text':    _textCache.clear();
            case 'image':   _imageCache.clear();
            case 'bitmap':  _bitmapCache.clear();
            case 'audio':   _audioCache.clear();
            case 'sound':   _soundCache.clear();
            case 'font':    _fontCache.clear();
            default:        trace('[AssetLibrary] clearCacheFor: unknown type "$type".');
        }
    }

    public function prependRoot(root:String):Void
    {
        if (_roots.contains(root))
            return;

        _roots.unshift(root);
        clearCache();
    }

    public function appendRoot(root:String):Void
    {
        if (!_roots.contains(root))
            _roots.push(root);
    }

    public function removeRoot(root:String):Bool
    {
        final removed = _roots.remove(root);

        if (removed)
            clearCache();

        return removed;
    }

    public function listAssets(?ext:String):Array<String>
    {
        final seen:Map<String, Bool> = [];
        final result:Array<String>   = [];

        for (root in _roots)
            _collectFiles(_normRoot(root), _normRoot(root), ext, seen, result);

        result.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);

        return result;
    }

    public function debugInfo():String
    {
        final sb = new StringBuf();
        sb.add('AssetLibrary {\n');
        sb.add('  roots         : [${_roots.join(", ")}]\n');
        sb.add('  caching       : $cachingEnabled\n');
        sb.add('  cache/bytes   : ${_countMap(_bytesCache)}\n');
        sb.add('  cache/text    : ${_countMap(_textCache)}\n');
        sb.add('  cache/image   : ${_countMap(_imageCache)}\n');
        sb.add('  cache/bitmap  : ${_countMap(_bitmapCache)}\n');
        sb.add('  cache/audio   : ${_countMap(_audioCache)}\n');
        sb.add('  cache/sound   : ${_countMap(_soundCache)}\n');
        sb.add('  cache/font    : ${_countMap(_fontCache)}\n');
        sb.add('}');
        return sb.toString();
    }

    private function _loadManifest():Void
    {
        final manifestPath = #if switch 'romfs:/' + #end 'manifest/default.json';

        try
        {
            final manifest = AssetManifest.fromFile(manifestPath);

            if (manifest != null)
                __fromManifest(manifest);
        }
        catch (e)
        {
            trace('[AssetLibrary] Could not load manifest at "$manifestPath": $e');
        }
    }

    private inline function _normRoot(root:String):String
        return root.endsWith('/') ? root.substr(0, root.length - 1) : root;

    private inline function _join(root:String, id:String):String
    {
        final r = root.endsWith('/')   ? root.substr(0, root.length - 1) : root;
        final i = id.startsWith('/')   ? id.substr(1) : id;
        return '$r/$i';
    }

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

    private inline function _warn(op:String, id:String):Void
        trace('[AssetLibrary] $op("$id"): file not found in any root.');

    private function _registerOpenFLFont(limeFont:Font):Void
    {
        final openFLFont = new OpenFLFont();
        @:privateAccess openFLFont.__fromLimeFont(limeFont);
        OpenFLFont.registerFont(openFLFont);
    }

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
            final full = _join(dir, entry);

            if (FileSystem.isDirectory(full))
            {
                _collectFiles(root, full, ext, seen, result);
            }
            else
            {
                final rel = full.substr(root.length + 1);

                if (seen.exists(rel))
                    continue;

                if (ext != null && !rel.toLowerCase().endsWith(ext.toLowerCase()))
                    continue;

                seen[rel] = true;
                result.push(rel);
            }
        }
    }

    private inline function _countMap<K, V>(map:Map<K, V>):Int
    {
        var n = 0;
        for (_ in map) n++;
        return n;
    }
}
