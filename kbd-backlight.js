// Forceert toetsenbordverlichting: lichtsensor zat in het (verwijderde) scherm
// en leest nu altijd "maximaal fel", waardoor auto-helderheid de verlichting uitzet.
// Gebruik: osascript -l JavaScript kbd-backlight.js [niveau 0-1]
ObjC.import('Foundation');
function run(argv){
  $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/CoreBrightness.framework").load;
  var c = $.NSClassFromString("KeyboardBrightnessClient").alloc.init;
  var ids = c.copyKeyboardBacklightIDs;
  for (var i = 0; i < ids.count; i++) {
    var id = ids.objectAtIndex(i).intValue;
    c.enableAutoBrightnessForKeyboard(false, id);
    if (argv.length) c.setBrightnessForKeyboard(parseFloat(argv[0]), id);
    else if (c.brightnessForKeyboard(id) < 0.01) c.setBrightnessForKeyboard(0.6, id);
  }
  return "ok";
}
