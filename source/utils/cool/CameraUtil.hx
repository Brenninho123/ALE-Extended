package utils.cool;

class CameraUtil
{
    /**
     * Detaches the camera from Flixel's managed list and the game's display list,
     * preparing it for manual z-order repositioning.
     */
    static function prepareCameraPositionOverride(camera:FlxCamera):Void
    {
        if (camera == null || camera.flashSprite == null)
            return;

        FlxG.cameras.list.remove(camera);

        // Use parent check instead of contains() — we only care about direct children.
        if (camera.flashSprite.parent == FlxG.game)
            FlxG.game.removeChild(camera.flashSprite);
    }

    /**
     * Moves `camera` to the top of the render stack, just below the input container.
     * It will draw over all other cameras.
     */
    public static function moveCameraToTop(camera:FlxCamera):Void
    {
        if (camera == null || camera.flashSprite == null)
            return;

        prepareCameraPositionOverride(camera);

        @:privateAccess
        FlxG.game.addChildAt(camera.flashSprite, FlxG.game.getChildIndex(FlxG.game._inputContainer));

        FlxG.cameras.list.push(camera);
    }

    /**
     * Moves `camera` to the bottom of the render stack, beneath all other cameras.
     * Index 0 is the base game canvas — clamping to 1 keeps the camera visible.
     */
    public static function moveCameraToBottom(camera:FlxCamera):Void
    {
        if (camera == null || camera.flashSprite == null)
            return;

        prepareCameraPositionOverride(camera);

        // Avoid index 0 (base game canvas). Clamp in case numChildren is somehow 0.
        final safeIndex:Int = Std.int(Math.min(1, FlxG.game.numChildren));
        FlxG.game.addChildAt(camera.flashSprite, safeIndex);

        // Bottom of display list = first to render = unshift, not push.
        FlxG.cameras.list.unshift(camera);
    }
}
