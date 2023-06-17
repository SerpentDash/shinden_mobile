part of 'main.dart';

// Providers for js injection
// Check map 'key' to see if the url contains it,
// and then use map 'value' as the 'target' in the subsequent function.
Map<String, String> providers = {
  //"ebd.cda": "cda",
  //"drive.google": "gdrive",
  "dailymotion": "dailymotion",
  "sibnet": "sibnet",
  "streamtape": "streamtape",
  "streamadblockplus": "streamtape",
  "mega.nz": "mega",
  "mp4upload": "mp4upload",
  "yourupload": "yourupload",
};

// add correct js file
void setJS(controller, target) async {
  if (target == null) return;
  await SessionManager().get('mode').then((val) async {
    if (val == null) return;
    await controller.injectJavascriptFileFromAsset(
        assetFilePath: 'assets/js/players/${target}_min.js');
  });
}

// Providers that utilize requests from servers

void cdaPlayer(url, controller) async {
  var response = await http.get(Uri.parse(url));
  final document = parse(response.body);

  String? playerDataJSON;
  try {
    playerDataJSON =
        document.querySelector('[player_data]')!.attributes['player_data'];
  } catch (err) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final quality = pick(json.decode(playerDataJSON!), "video", "qualities")
      .asMapOrNull<String, String>()
      ?.entries
      .last;

  final id = pick(json.decode(playerDataJSON), "video", "id").asStringOrNull();
  final ts = pick(json.decode(playerDataJSON), "video", "ts").asStringOrNull();
  final hash2 =
      pick(json.decode(playerDataJSON), "video", "hash2").asStringOrNull();
  final title =
      pick(json.decode(playerDataJSON), "video", "title").asStringOrNull();

  var data =
      '{"jsonrpc":"2.0","method":"videoGetLink","params":["$id","${quality!.value}","$ts","$hash2",{}],"id":1}';

  http.Response r = await http.post(
    Uri.parse("https://www.cda.pl/"),
    headers: {
      'Content-Type': 'application/json',
    },
    body: data,
  );
  final target =
      pick(json.decode(r.body), 'result', 'resp').asStringOrNull().toString();

  downloadOrStream(
      controller, target, "${Uri.decodeFull(title!)} [${quality.key}]");
}

void gdrivePlayer(url, controller) async {
  Uri uri = Uri.parse(url);

  var response = await http.get(uri);
  final document = parse(response.body);

  if (document.getElementsByClassName('errorMessage').isNotEmpty) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final title =
      document.querySelector('[itemprop=name]')!.attributes['content'] ??
          "gdrive";

  final regex = RegExp('/file/d/([^/]+)');
  final id = regex.allMatches(uri.path).map((str) => str.group(1)).single;

  final target =
      "${uri.scheme}://${uri.host}/uc?id=$id&confirm=t&export=download";

  downloadOrStream(controller, target, title);
}

// STILL WIP!!!
void doodPlayer(url, controller) async {
  var r1 = await http.get(
    Uri.parse(url),
  );
  log(r1.toString());
  log(r1.statusCode.toString());
  log(r1.headers.toString());
  final body = r1.body;
  //log(body);
  final regex = RegExp("'/pass_md5/([^/]+)/([^/]+)'");
  final id = regex.allMatches(body).map((str) => str.group(0)).single;
  log(id.toString());
  var r2 = await http.get(Uri.parse("https://dood.yt/$id"), headers: {
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0",
    "Accept": "*/*",
    "Accept-Language": "pl,en-US;q=0.7,en;q=0.3",
    "X-Requested-With": "XMLHttpRequest",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-origin",
    "Sec-GPC": "1",
    "Referrer": "https://dood.yt",
    "Cookie": "lang=1"
  });
  log(r2.toString());
  log(r2.statusCode.toString());
  log(r2.headers.toString());
  log(r2.body);
}
