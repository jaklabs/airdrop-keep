// airdrop-send.js — open the AirDrop picker preloaded with the given files.
//
// Run by the Finder Quick Action (see install-quick-action.sh):
//     osascript -l JavaScript airdrop-send.js <path> [<path> ...]
//
// Why JavaScript and not AppleScript: the sharing service reports failures
// through sharingService:didFailToShareItems:error:, and AppleScript CANNOT
// implement that selector — `error` is a reserved word and may not appear as a
// handler label. So an AppleScript version is structurally blind to the one
// callback that says why a send failed, which is exactly the information needed
// when the picker opens, you click a person, and nothing happens.
//
// ⚠️ Do NOT "improve" this by (a) calling setActivationPolicy: /
// activateIgnoringOtherApps:, or (b) compiling it into an .app. Both were tried
// on macOS 26.5.1 and both stop the picker from ever being drawn, while every
// log line still says success.
ObjC.import('Foundation');
ObjC.import('AppKit');

var LOG = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Caches/airdrop-send.log';

function note(m) {
  try {
    var line = new Date().toISOString().replace('T', ' ').substr(0, 19) + '  ' + m + '\n';
    var path = $(LOG);
    var fm = $.NSFileManager.defaultManager;
    if (!fm.fileExistsAtPath(path)) {
      $(line).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
    } else {
      // Keep it from growing without bound; this is a breadcrumb trail, not an archive.
      var attrs = fm.attributesOfItemAtPathError(path, null);
      if (attrs && ObjC.unwrap(attrs.objectForKey('NSFileSize')) > 200000) {
        fm.removeItemAtPathError(path, null);
        $(line).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
        return;
      }
      var fh = $.NSFileHandle.fileHandleForWritingAtPath(path);
      fh.seekToEndOfFile;
      fh.writeData($(line).dataUsingEncoding($.NSUTF8StringEncoding));
      fh.closeFile;
    }
  } catch (e) { /* logging must never break sending */ }
}

ObjC.registerSubclass({
  name: 'AirDropSendDelegate',
  superclass: 'NSObject',
  methods: {
    'sharingService:willShareItems:': {
      types: ['void', ['id', 'id']],
      implementation: function (s, items) { note('willShareItems — recipient chosen, handoff starting'); }
    },
    'sharingService:didShareItems:': {
      types: ['void', ['id', 'id']],
      implementation: function (s, items) { note('didShareItems — service reports the send succeeded'); }
    },
    'sharingService:didFailToShareItems:error:': {
      types: ['void', ['id', 'id', 'id']],
      implementation: function (s, items, err) {
        try {
          note('didFailToShareItems — domain=' + ObjC.unwrap(err.domain) +
               ' code=' + err.code + ' — ' + ObjC.unwrap(err.localizedDescription));
        } catch (e) { note('didFailToShareItems (error unreadable): ' + e); }
      }
    }
  }
});

function run(argv) {
  if (argv.length === 0) { note('called with no files'); return 'no files'; }
  note('--- invoked with ' + argv.length + ' item(s) ---');

  var urls = $.NSMutableArray.array;
  for (var i = 0; i < argv.length; i++) {
    urls.addObject($.NSURL.fileURLWithPath($(argv[i])));
    note('  ' + argv[i]);
  }

  var svc = $.NSSharingService.sharingServiceNamed($.NSSharingServiceNameSendViaAirDrop);
  if (svc.isNil()) { note('AirDrop sharing service unavailable'); return 'no service'; }
  note('canPerformWithItems = ' + svc.canPerformWithItems(urls));

  // The delegate is held weakly by the service, so keep our own strong reference
  // or it is collected and the callbacks silently stop arriving.
  var del = $.AirDropSendDelegate.alloc.init;
  globalThis.__airdropDelegate = del;
  svc.delegate = del;

  svc.performWithItems(urls);
  note('performWithItems returned — picker should be on screen');

  // Outlive the transfer. The picker belongs to THIS process and dies with it,
  // and there is deliberately no early exit on didShareItems: that callback
  // fires when the recipient is PICKED, not when the file has landed.
  var rl = $.NSRunLoop.currentRunLoop;
  for (var k = 0; k < 3600; k++) {
    rl.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.25));
  }
  note('--- hold window ended ---');
  return 'done';
}
