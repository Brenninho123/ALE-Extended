package core.structures;

typedef JsonModchart = {
    > JsonBase,
    tracks:Array<JsonModchartTrack>,
    ?scrollSpeed:Float
}

typedef JsonModchartTrack = {
    name:String,
    events:Array<JsonModchartEvent>,
    ?enabled:Bool
}

typedef JsonModchartEvent = {
    type:String,
    ?time:Float,
    ?beat:Float,
    ?target:String,
    ?label:String,
    ?property:String,
    ?value:Dynamic,
    ?duration:Float,
    ?ease:String,
    ?delay:Float,
    ?tweenType:String,
    ?anim:String,
    ?forceAnim:Bool,
    ?intensity:Float,
    ?speed:Float,
    ?visible:Bool,
    ?func:String,
    ?args:Array<Dynamic>,
    ?shader:String,
    ?shaderParams:Dynamic
}
    
