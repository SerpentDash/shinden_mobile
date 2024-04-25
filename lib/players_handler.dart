part of 'download_kit.dart';

//
// Video providers that utilize requests from servers
//

const List<MapEntry<String, Function>> playersHandlers = [
  MapEntry('open_cda', cdaPlayer),
  MapEntry('open_gdrive', gdrivePlayer),
  MapEntry('open_sibnet', sibnetPlayer),
  MapEntry('open_streamtape', streamtapePlayer),
  MapEntry('open_mp4upload', mp4uploadPlayer),
  MapEntry('open_dood', doodPlayer),
  MapEntry('open_dailymotion', dailymotionPlayer),
  MapEntry('open_supervideo', supervideoPlayer),
  MapEntry('open_vk', vkPlayer),
  MapEntry('open_okru', okruPlayer),
  MapEntry('open_yourupload', youruploadPlayer),
  MapEntry('open_aparat', aparatPlayer),
  MapEntry('open_default', defaultPlayer),
  MapEntry('open_mega', megaPlayer),
];

void cdaPlayer(controller, url, mode) async {
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
  final directLink =
      pick(json.decode(r.body), 'result', 'resp').asStringOrNull().toString();

  process(controller, directLink, "${Uri.decodeFull(title!)} [${quality.key}]",
      mode);
}

void gdrivePlayer(controller, url, mode) async {
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

  final directLink =
      "https://drive.usercontent.google.com/download?id=$id&export=download&authuser=0&confirm=t";
  //"${uri.scheme}://${uri.host}/uc?id=$id&confirm=t&export=download";

  process(controller, directLink, title, mode);
}

void sibnetPlayer(controller, url, mode) async {
  var r1 = await http.get(Uri.parse(url));

  // Get video url
  RegExp urlRegExp = RegExp(r'player.src\(\[\{src: "(.*?)",');
  String? urlMatch = urlRegExp.firstMatch(r1.body)?.group(1);

  if (urlMatch == null) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }
  //log("http://video.sibnet.ru$urlMatch");

  // Get video title
  RegExp titleRegExp = RegExp(r"title: '([^']+)'");
  String? titleMatch = titleRegExp.firstMatch(r1.body)?.group(1);

  // Send request for direct link
  Dio dio = Dio();
  final r2 = await dio.head(
    "https://video.sibnet.ru$urlMatch",
    options: Options(
      validateStatus: (status) => true,
      headers: {"referer": "$url"},
    ),
  );

  // Format direct link
  var directLink = r2.realUri.toString();
  log(directLink);

  process(controller, "https:$directLink", titleMatch, mode);
}

void streamtapePlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url));
  final responseBody = response.body;

  // Find first occurrence of 'robotlink'
  int r1 = responseBody.indexOf('robotlink');

  // Video not found
  if (r1 == -1) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Find second occurrence of 'robotlink'
  int r2 = responseBody.indexOf('robotlink', r1 + 1);

  // Find start and end index of url
  int linkStart = responseBody.indexOf("'//", r2 + 1);
  int linkEnd = responseBody.indexOf("')", linkStart);

  // Extract url
  String encrypted = responseBody.substring(linkStart + 3, linkEnd);

  // Extract clear url
  List<String> parts = encrypted.split("'+ ('");
  String clearUrl = parts[0] + parts[1].substring(3);
  //log(clearUrl);

  // Send request for direct link
  Dio dio = Dio();
  final head = await dio.head(
    "https://$clearUrl&stream=1",
    options: Options(
      validateStatus: (status) => true,
      headers: {"referer": "$url"},
    ),
  );
  //log(head.realUri.toString());

  // Get title
  int titleStart =
      responseBody.indexOf('"showtitle":"') + '"showtitle":"'.length;
  int titleEnd = responseBody.indexOf('"', titleStart);

  String title = responseBody.substring(titleStart, titleEnd);

  process(controller, head.realUri.toString(), title, mode);
}

void mp4uploadPlayer(controller, url, mode) async {
  url = url.toString().replaceAll("embed-", "");

  RegExp regex = RegExp(r"/([^/]+)\.html");
  var mp4Id = regex.firstMatch(url)?.group(1);

  var response = await http.post(
    Uri.parse(url),
    body:
        "op=download2&id=$mp4Id&rand=&referer=https%3A%2F%2Fwww.mp4upload.com%2F&method_free=Free+Download&method_premium=",
    headers: {
      "Referer": url,
      "content-type": "application/x-www-form-urlencoded",
    },
  );

  final directLink = response.headers.entries.elementAt(1).value;

  if (directLink == "") {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final title = url.split('/').last.split('.').first;

  NotificationController.startIsolate(mp4uploadTask, [directLink, title]);

  // Won't work without passing headers to external video player app
  //process(controller, directLink, title, mode);
}

void doodPlayer(controller, url, mode) async {
  var r1 = await http.get(Uri.parse(url));
  final body = r1.body;

  final newUrl = url.toString().replaceFirst("dood.yt", "d0000d.com");
  /* r1.headers.entries.firstWhere((element) => element.key == "domain").value; */
  //log("newUrl: $newUrl");

  final watchRegex = RegExp(r'\/dood\?op=watch[^"]+');
  final watch = watchRegex.firstMatch(body)?.group(0);
  log("watch: $watch");

  if (watch == null) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }
  log('request 2: https://d0000d.com${watch}1&ref2=&adb=0&ftor=0');
  await http.get(
    Uri.parse("https://d0000d.com${watch}1&ref2=&adb=0&ftor=0"),
    headers: {"Referer": newUrl},
  );

  final md5Regex = RegExp("'/pass_md5/([^/]+)/([^/]+)'");
  final md5 = md5Regex
      .allMatches(body)
      .map((str) => str.group(0))
      .single
      ?.replaceAll("'", '');
  //log("MD5: $md5");

  final tokenRegex = RegExp(r'token=([^&]+)');
  final token = tokenRegex.firstMatch(body)!.group(1);
  //log("Token: $token");

  //log('request 3: https://d0000d.com$md5');
  var r3 = await http
      .get(Uri.parse("https://d0000d.com$md5"), headers: {"Referer": newUrl});

  final directLink = "${r3.body}${generateRandomString(token)}";

  RegExp titleRegex = RegExp(r'<title>(.*?)</title>');
  final title =
      titleRegex.firstMatch(body)?.group(1)!.replaceAll(" - DoodStream", "");

  download(directLink, "$title.mp4", headers: {"referer": "$url"});

  // Won't work without passing headers to external video player app
  //process(controller, directLink, "test", mode);
}

void dailymotionPlayer(controller, url, mode) async {
  RegExp regExp = RegExp(r'\/video\/([^?/]+)');
  final id = regExp.firstMatch(url)!.group(1);

  var jsonResponse = await http.get(
    Uri.parse("https://www.dailymotion.com/player/metadata/video/$id"),
    headers: {"Referer": "https://www.dailymotion.com/"},
  );

  Map<String, dynamic> json = jsonDecode(jsonResponse.body);

  if (json['error'] != null) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final title = json['title'];

  final target = json["qualities"]["auto"][0]["url"];

  var m3uResponse = await http.get(
    Uri.parse(target),
    headers: {
      "Referer": "https://www.dailymotion.com/",
    },
  );

  RegExp pattern = RegExp(r'PROGRESSIVE-URI="([^"]*)"');

  final directLink = pattern.allMatches(m3uResponse.body).last.group(1);
  log(directLink.toString());

  process(controller, directLink, title, mode);
}

void supervideoPlayer(controller, url, mode) async {
  //url = url.replaceFirst("tv", "cc");

  // Send request for direct link
  Dio dio = Dio();
  final response = await dio.get(
    url,
    options: Options(
      validateStatus: (status) => true,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0'
      },
    ),
  );

  if (response.statusCode != 200) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final body = response.data;

  RegExp idRegex = RegExp(r"urlset\|([^']*)");
  final ids = idRegex.firstMatch(body)!.group(1);

  List<String>? parts = ids?.split("|");
  String id = parts![2] + parts[0];

  RegExp hostRegex = RegExp(r"serversicuro\|([^|]*)");
  final host = hostRegex.firstMatch(body)!.group(1);

  final directLink = "https://$host.serversicuro.cc/hls/$id/index-v1-a1.m3u8";
  //log(directLink);

  Uri u = Uri.parse(url);
  final title = u.pathSegments[u.pathSegments.length - 1];

  switch (mode) {
    case 'stream':
      AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: directLink,
        arguments: {'title': title},
      ).launch();
      break;
    case 'download':
      ffmpegTask(directLink, title);
      break;
    default:
      break;
  }
}

void vkPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url), headers: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.118 Mobile Safari/537.36',
  });
  final body = response.body;

  // Find url any valid video link (starting from the highest quality)
  String directLink = "";
  final qualities = ['url1080', 'url720', 'url480'];
  for (String key in qualities) {
    if (body.contains(key)) {
      int keyIndex = body.indexOf(key);
      directLink = body
          .substring(keyIndex + key.length)
          .split('"')[2]
          .replaceAll("\\/", "/");
      break;
    }
  }

  if (directLink.isEmpty) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Find title
  int titleIndex = body.indexOf('md_title');
  String title = body.substring(titleIndex + 'md_title'.length).split('"')[2];

  await File("$savePath/$title.mp4").exists().then((value) {
    if (value) title = "$title [${DateTime.now().toString()}]";
  });

  //log("Title: $title, Target: $directLink");
  process(controller, directLink, title, mode);
}

void okruPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url), headers: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.118 Mobile Safari/537.36',
  });
  String body = response.body;

  body = body
      .replaceAll("\\", "")
      .replaceAll("u0026", "&")
      .replaceAll("&quot;", '"')
      .replaceAll("%3B", ";");

  // Find any valid video link (starting from the highest quality)
  String directLink = "";
  final qualities = ['full', 'hd', 'sd'];
  for (var key in qualities) {
    int keyIndex = body.indexOf('"name":"$key"');

    // If 'key' not found, iterate over next 'key'
    if (keyIndex == -1) continue;

    int urlIndexStart = body.indexOf('"url":"', keyIndex);
    int urlIndexEnd = body.indexOf('"', urlIndexStart + 7);

    // Extract the URL substring
    directLink = body.substring(urlIndexStart + 7, urlIndexEnd);
  }

  if (directLink.isEmpty) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Find title
  RegExp exp = RegExp(r'"title":"([^"]+)"');
  String title = exp.firstMatch(body)!.group(1)!;

  await File("$savePath/$title.mp4").exists().then((value) {
    if (value) title = "$title [${DateTime.now().toString()}]";
  });

  //log("Title: $title, Target: $directLink");
  process(controller, directLink, title, mode);
}

void youruploadPlayer(controller, url, mode) async {
  url = url.toString().replaceAll("embed", "watch");

  var r1 = await http.get(Uri.parse(url));
  final doc1 = parse(r1.body);

  final title =
      doc1.querySelector('title')!.innerHtml.replaceFirst("Downloading ", "");

  if (title == "Error") {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  RegExp regExp = RegExp(r'\/download\?file=\d+');
  final urlWithoutToken =
      'https://www.yourupload.com${regExp.firstMatch(r1.body)!.group(0)!}';

  // Trigger download (without token)
  var r2 = await http.get(
    Uri.parse(urlWithoutToken),
    headers: {"referer": url},
  );

  // Get download link with token
  final doc2 = parse(r2.body);
  final directLink =
      'https://www.yourupload.com${doc2.querySelector('[data-url]')!.attributes['data-url']}';

  //log("Title: $title, Target: $directLink");

  download(directLink, title, headers: {"referer": urlWithoutToken});

  // Won't work without passing headers to external video player app
  //process(controller, response2.realUri.toString(), "title", mode);
}

void aparatPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url), headers: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.118 Mobile Safari/537.36',
  });

  final body = response.body;

  RegExp regExp = RegExp(r'file:\s*\"(.*?)\"');

  final directLink = regExp.firstMatch(body)?.group(1);

  if (directLink == null) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }
  //log(directLink);

  Uri u = Uri.parse(url);
  final title = u.pathSegments[u.pathSegments.length - 1].split('.').first;

  switch (mode) {
    case 'stream':
      AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: directLink,
        arguments: {'title': title},
      ).launch();
      break;
    case 'download':
      var master = await http.get(Uri.parse(directLink), headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.118 Mobile Safari/537.36',
      });

      RegExp regex = RegExp(r'https?://[^\s]+index[^\s]*');
      Iterable<Match> matches = regex.allMatches(master.body);

      log(matches.last.group(0)!);
      ffmpegTask(matches.last.group(0)!, title);
      break;
    default:
      break;
  }
}

void defaultPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url));
  final body = response.body;

  // Get obfuscated url
  RegExp regExp = RegExp(r'\"\d[a-z]://([^"]*)');
  RegExpMatch? match = regExp.firstMatch(body);
  String obfuscatedUrl = "https://${match?.group(1) ?? "null"}";

  if (obfuscatedUrl.contains("null")) {
    controller.evaluateJavascript(
        source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Get big array with values to replace obfuscated url
  String pattern2 = r"'\|(.*?)\.split\('\|'\)";
  RegExp regExp2 = RegExp(pattern2);
  RegExpMatch? matches = regExp2.firstMatch(body);
  List<String> array = "|${matches!.group(1)}".split('|');

  // Get radix-36 values from obfuscated url
  RegExp regex = RegExp(r'\b[a-z0-9]{2}\b');
  Iterable<RegExpMatch> matches2 = regex.allMatches(obfuscatedUrl);

  // Find replacement from array
  List<List<int>> replacements = [];
  for (RegExpMatch match in matches2) {
    String matchStr = match.group(0)!;
    int value = int.parse(matchStr, radix: 36);
    if (value >= 0 && array[value] != '') {
      replacements.add([match.start, match.end, value]);
    }
  }

  // Replace radix-36 values with replacements
  String directLink = obfuscatedUrl;
  replacements.sort((a, b) => b[0].compareTo(a[0]));
  for (List<int> replacement in replacements) {
    int start = replacement[0];
    int end = replacement[1];
    int newValue = replacement[2];
    directLink = directLink.replaceRange(start, end, array[newValue]);
  }

  //log(directLink);

  Uri u = Uri.parse(url);
  final title = u.pathSegments[u.pathSegments.length - 1].split('.').first;

  switch (mode) {
    case 'stream':
      AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: directLink,
        arguments: {'title': title},
      ).launch();
      break;
    case 'download':
      log(directLink);
      var master = await http.get(Uri.parse(directLink));

      RegExp regex = RegExp(r'https?://[^\s]+index[^\s]*');
      Iterable<Match> matches = regex.allMatches(master.body);

      ffmpegTask(matches.last.group(0)!, title);

      break;
    default:
      break;
  }
}

void megaPlayer(controller, url, mode) async {
  NotificationController.startIsolate(megaTask, [url]);
}

//Helper function for dood provider
String generateRandomString(token) {
  var result = '';
  var characters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  var charLength = characters.length;
  var random = Random();

  for (var i = 0; i < 10; i++) {
    result += characters[random.nextInt(charLength)];
  }

  return '$result?token=$token&expiry=${DateTime.now().millisecondsSinceEpoch}';
}
