package sidewinder.interfaces;

typedef User = {
  var id:Int;
  var name:String;
  var email:String;
  @:optional var permissions:Array<String>;
}
