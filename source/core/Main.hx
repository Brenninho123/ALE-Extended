package core;

import haxe.io.Path;
import haxe.Http;
import haxe.Timer;

import lime.app.Application;
import openfl.display.Sprite;
import openfl.Lib;
import openfl.ui.Mouse;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

import core.config.MainState;
import core.backend.SoundTray;
import core.plugins.*;
import core.Game;

import utils.Formatter;

#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
#end

#if LUA_ALLOWED
import hxluajit.wrapper.LuaError;
#end

#if android
import extension.androidtools.os.Environment as AndroidEnvironment;
import extension.androidtools.Settings as AndroidSettings;
import extension.androidtools.os.Build.VERSION as AndroidVersion;
import extension.androidtools.os.Build.VERSION_CODES as AndroidVersionCode;
#end

class Main extends Sprite
{
	// ================= ENGINE META =================

	public static inline var ENGINE_NAME:String = "ALE Extended";
	public static inline var ENGINE_VERSION:String = "0.1.0";

	private static var onlineVersion:String = "unknown";

	// ================= CONSTRUCTOR =================

	public function new()
	{
		super();

		boot();
	}

	// ================= BOOT SYSTEM =================

	private function boot():Void
	{
		initPlatform();
		setupCrashHandler();
		setupEnvironment();

		startGame();
		postBoot();
	}

	// ================= PLATFORM =================

	private function initPlatform():Void
	{
		#if android
		if (AndroidVersion.SDK_INT >= AndroidVersionCode.M)
		{
			if (!AndroidEnvironment.isExternalStorageManager())
			{
				AndroidSettings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');

				trace("[BOOT] Missing storage permission. Closing app...");
				Sys.exit(0);
			}
		}
		#end
	}

	// ================= CRASH HANDLER =================

	private function setupCrashHandler():Void
	{
		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(
			UncaughtErrorEvent.UNCAUGHT_ERROR,
			onCrash
		);
		#end
	}

	private function onCrash(e:UncaughtErrorEvent):Void
	{
		var msg:String = buildCrashReport(e);

		trace(msg);

		#if WINDOWS_API
		api.DesktopAPI.showMessageBox(msg, ENGINE_NAME + " Crash", ERROR);
		#else
		Application.current.window.alert(msg, ENGINE_NAME + " Crash");
		#end

		shutdown();
		Sys.exit(1);
	}

	private function buildCrashReport(e:Dynamic):String
	{
		var report:String = "=== CRASH REPORT ===\n";

		for (stackItem in CallStack.exceptionStack(true))
		{
			switch (stackItem)
			{
				case FilePos(_, file, line, _):
					report += file + ":" + line + "\n";
				default:
			}
		}

		report += "\nError: " + e.error;
		report += "\nEngine: " + ENGINE_NAME + " " + ENGINE_VERSION;

		return report;
	}

	// ================= ENV =================

	private function setupEnvironment():Void
	{
		#if android
		var path:String = AndroidEnvironment.getExternalStorageDirectory() + "/." + Lib.application.meta.get('file');

		if (!sys.FileSystem.exists(path))
			sys.FileSystem.createDirectory(path);

		Sys.setCwd(path);
		#end

		Lib.application.window.onClose.add(shutdown);
	}

	// ================= GAME START =================

	private function startGame():Void
	{
		addChild(new Game(MainState));
	}

	// ================= POST BOOT =================

	private function postBoot():Void
	{
		setupWindow();
		setupInput();
		setupVideo();
		checkVersionAsync();
	}

	// ================= WINDOW =================

	private function setupWindow():Void
	{
		#if WINDOWS_API
		untyped __cpp__("SetProcessDPIAware();");
		#end

		#if desktop
		centerWindow();
		#end
	}

	private function centerWindow():Void
	{
		var win = Application.current.window;

		win.x = Std.int((win.display.bounds.width - win.width) / 2);
		win.y = Std.int((win.display.bounds.height - win.height) / 2);
	}

	// ================= INPUT =================

	private function setupInput():Void
	{
		FlxG.stage.addEventListener('keyDown', (event) ->
		{
			if (event.altKey && event.keyCode == FlxKey.ENTER)
				event.stopImmediatePropagation();
		});
	}

	// ================= VIDEO =================

	private function setupVideo():Void
	{
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(['--no-lua']);
		#end
	}

	// ================= VERSION CHECK =================

	private function checkVersionAsync():Void
	{
		Timer.delay(() ->
		{
			try
			{
				var http = new Http("https://raw.githubusercontent.com/-Psych-Crew/-Psych/main/githubVersion.txt");

				http.onData = (data:String) ->
				{
					onlineVersion = data.split("\n")[0].trim();
					trace("[VERSION] Online: " + onlineVersion);
				};

				http.onError = (err) ->
				{
					trace("[VERSION ERROR] " + err);
				};

				http.request();
			}
			catch (e)
			{
				trace("[VERSION FAIL] " + e);
			}
		}, 1000);
	}

	// ================= SHUTDOWN =================

	public static function shutdown():Void
	{
		trace("[SYSTEM] Shutting down...");

		PluginsHandler.destroy();
		Discord.destroy();

		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		FlxTween.globalManager.clear();

		Conductor.destroy();
		CoolUtil.destroy();
	}

	// ================= RESET =================

	public static function reset():Void
	{
		trace("[SYSTEM] Resetting engine...");

		shutdown();

		FlxG.resetGame();
	}

	// ================= POST RESET =================

	public static function postReset():Void
	{
		trace("[SYSTEM] Post reset init...");

		FlxG.fixedTimestep = false;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		Paths.clear(true, true);
		Paths.init();
		Paths.initMod();

		CoolVars.loadMetadata();
		CoolUtil.init();
		Conductor.init();

		Formatter.init();
		HScriptConfig.config();

		PluginsHandler.init();

		#if LUA_ALLOWED
		LuaError.errorHandler = (e:String) ->
		{
			trace("[LUA ERROR] " + e);
		};
		#end
	}
}
