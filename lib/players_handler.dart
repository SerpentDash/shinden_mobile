part of 'download_kit.dart';

//
// Video providers that utilize requests from servers
//

// Supported host names with their handlers
final List<MapEntry<List<String>, Function>> handlers = [
  MapEntry(['cda'], cdaPlayer),
  MapEntry(['drive.google'], gdrivePlayer),
  MapEntry(['sibnet'], sibnetPlayer),
  MapEntry(['streamtape'], streamtapePlayer),
  MapEntry(['mp4upload'], mp4uploadPlayer),
  MapEntry(['dood', 'd000d', 'd0000d'], doodPlayer), // ...
  MapEntry(['dailymotion'], dailymotionPlayer),
  MapEntry(['supervideo'], supervideoPlayer),
  MapEntry(['vk'], vkPlayer),
  MapEntry(['ok.ru'], okruPlayer),
  MapEntry(['yourupload'], youruploadPlayer),
  MapEntry(['wolfstream'], aparatPlayer),
  MapEntry(['filemoon'], defaultPlayer), // 'streamvid' there are more hosts...
  MapEntry(['mega'], megaPlayer),
  MapEntry(['lycoris'], lycorisPlayer),
  MapEntry(['pixeldrain'], pixeldrainPlayer),
  //MapEntry(['lulu'], luluPlayer), // not yet
  MapEntry(['rumble'], rumblePlayer),
  MapEntry(['streamwish', 'playerwish'], streamwishPlayer),
];

void handleLink(controller, url, mode) async {
  // Handle direct browser opening
  if (mode == 'direct') {
    await AndroidIntent(
      action: 'action_view',
      data: url,
    ).launch();
    return;
  }

  final link = Uri.parse(url);
  //log("Link: ${link.host}");

  // Use correct handler for current url
  for (final handler in handlers) {
    if (handler.key.any((host) => link.host.contains(host))) {
      handler.value(controller, url, mode);
      return;
    }
  }

  // No match found, open in browser
  AndroidIntent(
    action: 'action_view',
    data: url,
  ).launch();
}

void cdaPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url));
  final document = parse(response.body);

  String? playerDataJSON;
  try {
    playerDataJSON = document.querySelector('[player_data]')!.attributes['player_data'];
  } catch (err) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final qualities = pick(json.decode(playerDataJSON!), "video", "qualities").asMapOrNull<String, String>()?.entries.toList();
  final quality = (qualities != null && qualities.isNotEmpty)
      ? (qualities.last.value == 'auto' && qualities.length > 1 ? qualities[qualities.length - 2] : qualities.last)
      : null;

  final id = pick(json.decode(playerDataJSON), "video", "id").asStringOrNull();
  final ts = pick(json.decode(playerDataJSON), "video", "ts").asStringOrNull();
  final hash2 = pick(json.decode(playerDataJSON), "video", "hash2").asStringOrNull();
  final title = pick(json.decode(playerDataJSON), "video", "title").asStringOrNull();

  var data = '{"jsonrpc":"2.0","method":"videoGetLink","params":["$id","${quality!.value}","$ts","$hash2",{}],"id":1}';

  http.Response r = await http.post(
    Uri.parse("https://www.cda.pl/"),
    headers: {
      'Content-Type': 'application/json',
    },
    body: data,
  );
  final directLink = pick(json.decode(r.body), 'result', 'resp').asStringOrNull().toString();

  process(controller, directLink, "${Uri.decodeFull(title!)} [${quality.key}]", mode);
}

void gdrivePlayer(controller, url, mode) async {
  Uri uri = Uri.parse(url);

  var response = await http.get(uri);
  final document = parse(response.body);

  if (document.getElementsByClassName('errorMessage').isNotEmpty) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final title = document.querySelector('[itemprop=name]')!.attributes['content'] ?? "gdrive";

  final regex = RegExp('/file/d/([^/]+)');
  final id = regex.allMatches(uri.path).map((str) => str.group(1)).single;

  final directLink = "https://drive.usercontent.google.com/download?id=$id&export=download&authuser=0&confirm=t";
  //"${uri.scheme}://${uri.host}/uc?id=$id&confirm=t&export=download";

  process(controller, directLink, title, mode);
}

void sibnetPlayer(controller, url, mode) async {
  var r1 = await http.get(Uri.parse(url));

  // Get video url
  RegExp urlRegExp = RegExp(r'player.src\(\[\{src: "(.*?)",');
  String? urlMatch = urlRegExp.firstMatch(r1.body)?.group(1);

  if (urlMatch == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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
  int titleStart = responseBody.indexOf('"showtitle":"') + '"showtitle":"'.length;
  int titleEnd = responseBody.indexOf('"', titleStart);

  String title = responseBody.substring(titleStart, titleEnd);

  process(controller, head.realUri.toString(), title, mode);
}

void mp4uploadPlayer(controller, url, mode) async {
  await requestIgnoreBatteryOptimizations();

  url = url.toString().replaceAll("embed-", "");

  RegExp regex = RegExp(r"/([^/]+)\.html");
  var mp4Id = regex.firstMatch(url)?.group(1);

  var response = await http.post(
    Uri.parse(url),
    body: "op=download2&id=$mp4Id&rand=&referer=https%3A%2F%2Fwww.mp4upload.com%2F&method_free=Free+Download&method_premium=",
    headers: {
      "Referer": url,
      "content-type": "application/x-www-form-urlencoded",
    },
  );

  final directLink = response.headers.entries.elementAt(1).value;

  if (directLink == "") {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final title = url.split('/').last.split('.').first;

  switch (mode) {
    case 'stream':
      await VideoServer().start();

      await AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: 'http://localhost:8069?${Uri(queryParameters: {'url': directLink, 'referer': url}).query}',
        arguments: {'title': title},
      ).launch().catchError((error) {
        ScaffoldMessenger.of(controller).showSnackBar(
          SnackBar(content: Text('Failed to open video player: $error')),
        );
      });
      break;
    case 'download':
      NotificationController.startIsolate(mp4uploadTask, [directLink, title]);
      break;
    default:
      break;
  }
}

void doodPlayer(controller, url, mode) async {
  await requestIgnoreBatteryOptimizations();

  var r1 = await http.get(Uri.parse(url));
  final body = r1.body;

  // In case domain changed after request
  RegExp regExp = RegExp(r'domain=\.([^.]+\.com)');
  final host = regExp.firstMatch(r1.headers.toString())!.group(1)!;
  url = Uri.parse(url).replace(host: host).toString();

  final watchRegex = RegExp(r'\/dood\?op=watch[^"]+');
  final watch = watchRegex.firstMatch(body)?.group(0);

  if (watch == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  await http.get(
    Uri.parse("https://$host${watch}1&ref2=&adb=0&ftor=0"),
    headers: {"Referer": url},
  );

  final md5Regex = RegExp("'/pass_md5/([^/]+)/([^/]+)'");
  final md5 = md5Regex.allMatches(body).map((str) => str.group(0)).single?.replaceAll("'", '');
  //log("MD5: $md5");

  final tokenRegex = RegExp(r'token=([^&]+)');
  final token = tokenRegex.firstMatch(body)!.group(1);
  //log("Token: $token");

  var r3 = await http.get(Uri.parse("https://$host$md5"), headers: {"Referer": url});

  final directLink = "${r3.body}${generateRandomString(token)}";

  RegExp titleRegex = RegExp(r'<title>(.*?)</title>');
  final title = titleRegex.firstMatch(body)?.group(1)!.replaceAll(" - DoodStream", "");

  switch (mode) {
    case 'stream':
      await VideoServer().start();

      log("Direct link: $directLink\nReferer: $url");

      await AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: 'http://localhost:8069?${Uri(queryParameters: {'url': directLink, 'referer': url}).query}',
        arguments: {'title': title},
      ).launch().catchError((error) {
        ScaffoldMessenger.of(controller).showSnackBar(
          SnackBar(content: Text('Failed to open video player: $error')),
        );
      });
      break;
    case 'download':
      download(directLink, "$title.mp4", headers: {"referer": "$url"});
      break;
    default:
      break;
  }
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
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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
  final headers = {'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"};

  // Send request for direct link
  Dio dio = Dio();
  final response = await dio.get(
    url,
    options: Options(
      validateStatus: (status) => true,
      headers: headers,
    ),
  );

  if (response.statusCode != 200) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final body = response.data;

  RegExp idRegex = RegExp(r"urlset\|([^']*)");
  final ids = idRegex.firstMatch(body)!.group(1);

  List<String>? parts = ids?.split("|");
  String id = parts![2] + parts[0];
  id = id.replaceFirst("sources", "");

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
      NotificationController.startIsolate(playlistTask, [directLink, title, headers]);
      break;
    default:
      break;
  }
}

void vkPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url), headers: {
    'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36",
  });
  final body = response.body;

  // Find url any valid video link (starting from the highest quality)
  String directLink = "";
  final qualities = ['url1080', 'url720', 'url480'];
  for (String key in qualities) {
    if (body.contains(key)) {
      int keyIndex = body.indexOf(key);
      directLink = body.substring(keyIndex + key.length).split('"')[2].replaceAll("\\/", "/");
      break;
    }
  }

  if (directLink.isEmpty) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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
    'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36",
  });
  String body = response.body;

  body = body.replaceAll("\\", "").replaceAll("u0026", "&").replaceAll("&quot;", '"').replaceAll("%3B", ";");

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
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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
  await requestIgnoreBatteryOptimizations();

  url = url.toString().replaceAll("embed", "watch");

  var r1 = await http.get(Uri.parse(url));
  final doc1 = parse(r1.body);

  final title = doc1.querySelector('title')!.innerHtml.replaceFirst("Downloading ", "");

  if (title == "Error" || title == "Content Restricted") {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  RegExp regExp = RegExp(r'\/download\?file=\d+');
  final urlWithoutToken = 'https://www.yourupload.com${regExp.firstMatch(r1.body)!.group(0)!}';

  // Trigger download (without token)
  var r2 = await http.get(
    Uri.parse(urlWithoutToken),
    headers: {"referer": url},
  );

  // Get download link with token
  final doc2 = parse(r2.body);
  final directLink = 'https://www.yourupload.com${doc2.querySelector('[data-url]')!.attributes['data-url']}';

  //log("Title: $title, Target: $directLink");

  switch (mode) {
    case 'stream':
      await VideoServer().start();

      await AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: 'http://localhost:8069?${Uri(queryParameters: {'url': directLink, 'referer': urlWithoutToken}).query}',
        arguments: {'title': title},
      ).launch().catchError((error) {
        ScaffoldMessenger.of(controller).showSnackBar(
          SnackBar(content: Text('Failed to open video player: $error')),
        );
      });
      break;
    case 'download':
      download(directLink, title, headers: {"referer": urlWithoutToken});
      break;
    default:
      break;
  }
}

void aparatPlayer(controller, url, mode) async {
  final headers = {'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"};

  var response = await http.get(Uri.parse(url), headers: headers);

  final body = response.body;

  RegExp regExp = RegExp(r'file:\s*\"(.*?)\"');

  var directLink = regExp.firstMatch(body)?.group(1);

  if (directLink == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

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
      NotificationController.startIsolate(playlistTask, [directLink, title, headers]);
      break;
    default:
      break;
  }
}

void defaultPlayer(controller, url, mode) async {
  // Add user agent to be able to open url in external video player
  final Map<String, String> headers = mode == "stream"
      ? {'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"}
      : const {};

  var response = await http.get(Uri.parse(url), headers: headers);
  final body = response.body;

  // Get obfuscated url
  RegExp regExp = RegExp(r'\"\d[a-z]://([^"]*)');
  RegExpMatch? match = regExp.firstMatch(body);
  String obfuscatedUrl = "https://${match?.group(1) ?? "null"}";

  if (obfuscatedUrl.contains("null")) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
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

  Uri u = Uri.parse(url);
  final title = u.pathSegments[u.pathSegments.length - 1].split('.').first;

/*   // Get highest quality link
	var master = await http.get(Uri.parse(directLink), headers: headers);
	RegExp masterRegex = RegExp(r'https?://[^\s]+index[^\s]*');

	directLink = masterRegex.allMatches(master.body).last.group(0)!;
	//log(directLink); */

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
      NotificationController.startIsolate(playlistTask, [directLink, title, headers]);
      break;
    default:
      break;
  }
}

void megaPlayer(controller, url, mode) async {
  final status = await Permission.ignoreBatteryOptimizations.request();
  if (status.isGranted) {
    final packageName = Platform.resolvedExecutable.split('/').last.split('-')[0];
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$packageName',
    );
    await intent.launch();
  }

  switch (mode) {
    case 'stream':
      String? paramId = extractIdFromUrl(url);
      String? paramKey = extractKeyFromUrl(url);

      // Prepare Key and IV
      String keyHex;
      try {
        keyHex = HEX.encode((base64.decode(paramKey!)));
      } on Exception catch (_) {
        keyHex = HEX.encode((base64.decode(addBase64Padding(paramKey!))));
      }

      Uint8List iv = Uint8List.fromList(HEX.decode(keyHex.substring(32, 48) + '0' * 16));

      BigInt key1 = BigInt.parse(keyHex.substring(0, 16), radix: 16) ^ BigInt.parse(keyHex.substring(32, 48), radix: 16);
      BigInt key2 = BigInt.parse(keyHex.substring(16, 32), radix: 16) ^ BigInt.parse(keyHex.substring(48, 64), radix: 16);
      Uint8List key = Uint8List.fromList(HEX.decode('${key1.toRadixString(16).padLeft(16, '0')}${key2.toRadixString(16).padLeft(16, '0')}'));

      // Get json from API request
      final apiResponse = await http.post(
        Uri.parse('https://eu.api.mega.co.nz/cs'),
        body: jsonEncode([
          {"a": "g", "g": 1, "p": paramId}
        ]),
      );

      // Parse json
      final jsonResponse = jsonDecode(apiResponse.body);

      String fileUrl = jsonResponse[0]['g'];

      String info = jsonResponse[0]['at'].replaceAll('-', '+').replaceAll('_', '/');

      // Decrypt info variable to get file name
      Uint8List input;
      try {
        input = base64.decode(info);
      } on Exception catch (_) {
        input = base64.decode(addBase64Padding(info));
      }

      final cipher = pc.CBCBlockCipher(pc.AESEngine())..init(false, pc.ParametersWithIV(pc.KeyParameter(key), Uint8List(16)));

      Uint8List output = Uint8List(input.length);

      var offset = 0;
      while (offset < input.length) {
        offset += cipher.processBlock(input, offset, output, offset);
      }

      RegExp pattern = RegExp(r'"n":"(.*?)"');
      String fileName = pattern.firstMatch(utf8.decode(output))!.group(1)!;

      await VideoServer().start();

      await AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: 'http://localhost:8069/mega?${Uri(queryParameters: {'url': fileUrl, 'key': base64UrlEncode(key), 'iv': base64UrlEncode(iv)}).query}',
        arguments: {'title': fileName},
      ).launch().catchError((error) {
        ScaffoldMessenger.of(controller).showSnackBar(
          SnackBar(content: Text('Failed to open video player: $error')),
        );
      });
      break;
    case 'download':
      NotificationController.startIsolate(megaTask, [url]);
      break;
    default:
      break;
  }
}

void lycorisPlayer(controller, url, mode) async {
  var response = await http.get(Uri.parse(url));
  final body = response.body;

  // Extract url to pass to API
  RegExp sourceRegex = RegExp(r'burstSource\\":\\"([^\\]+)');
  final burstSource = sourceRegex.firstMatch(body)?.group(1);

  if (burstSource == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  RegExp numberRegex = RegExp(r'\\"number\\":(\d+)');
  RegExp titleRegex = RegExp(r'\\"title\\":\\"([^\\]+)');
  final number = numberRegex.firstMatch(body)?.group(1);
  final episodeTitle = titleRegex.firstMatch(body)?.group(1);

  // Get download URL from API
  var apiResponse = await http.get(
    Uri.parse('https://www.lycoris.cafe/api/watch/getBurstLink?link=$burstSource'),
  );

  Map<String, dynamic> json = jsonDecode(apiResponse.body);
  final directLink = json['downloadUrl'];
  final title = "$number. $episodeTitle";

  process(controller, directLink, title, mode);
}

void pixeldrainPlayer(controller, url, mode) async {
  // Extract file ID from URL
  RegExp regExp = RegExp(r'/u/([^/?]+)');
  final id = regExp.firstMatch(url)!.group(1);

  if (id == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Create direct link and get title from its headers
  final directLink = "https://pixeldrain.com/api/file/$id?download";
  Dio dio = Dio();
  final response = await dio.head(
    directLink,
    options: Options(validateStatus: (status) => true),
  );

  if (response.statusCode != 200) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final disposition = response.headers.value('content-disposition');

  RegExp filenameRegex = RegExp(r'filename="(.*?)"');
  final match = filenameRegex.firstMatch(disposition ?? '');

  final title = match?.group(1) ?? id;

  process(controller, directLink, title, mode);
}

// [WIP] Still needs some changes
void luluPlayer(controller, url, mode) async {
  final Map<String, String> headers = {
    'User-Agent': "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36",
    'Referer': url
  };

  var response = await http.get(Uri.parse(url), headers: headers);
  final body = response.body;

  // Make the dl url
  RegExp dlRegex = RegExp(r'dl\?op=view&file_code=([^&]+)&hash=([^&"]+)');
  final dlMatch = dlRegex.firstMatch(body);
  if (dlMatch == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Returns int (counter of requests for this file?)
  final dlUrl = "https://lulu.st/dl?op=view&file_code=${dlMatch.group(1)}&hash=${dlMatch.group(2)}&embed=1&adb=0";
  await http.get(Uri.parse(dlUrl), headers: headers);

  // Get playlist URL from html
  RegExp regExp = RegExp(r'sources:\s*\[\{file:"([^"]+)"');
  final match = regExp.firstMatch(body);
  if (match == null) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  // Get master playlist URL
  String masterUrl = match.group(1)!.replaceAll('master', 'index');
  // masterUrl = masterUrl.replaceAll('master', 'index');

  // Make a request (playlist url) to ensure cookies are set
  await http.get(Uri.parse(masterUrl), headers: headers);

  // Extract title from URL path (for testing)
  Uri u = Uri.parse(url);
  final title = u.pathSegments[u.pathSegments.length - 1];

  log("Title: $title, Target: $masterUrl");

  switch (mode) {
    case 'stream':
      // Playlist url needs headers to respond data...
      await VideoServer().start();

      // Use the proxy server to handle the streaming with proper headers
      await AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: 'http://localhost:8069?${Uri(queryParameters: {'url': masterUrl, 'referer': url}).query}',
        arguments: {'title': title},
      ).launch().catchError((error) {
        log("Error launching video player: $error");
      });
      break;
    case 'download':
      // Output file is corupted...
      NotificationController.startIsolate(playlistTask, [masterUrl, title, headers]);
      break;
    default:
      break;
  }
}

void rumblePlayer(controller, url, mode) async {
  final response = await http.get(
    Uri.parse(url),
    headers: {'User-Agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"},
  );

  if (response.statusCode != 200) {
    controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
    return;
  }

  final html = response.body;

  // Extract title
  RegExp titleRegex = RegExp(r'"title":"([^"]+)"');
  var title = titleRegex.firstMatch(html)?.group(1) ?? 'Rumble Video';

  // Get URL for highest quality
  // If it doesn't exist, it will fall back to lower qualities or default
  final qualityOrder = ["1080", "720", "480", "360"];
  String? directLink;

  for (final quality in qualityOrder) {
    final match = RegExp('"$quality":\\s*{.*?"url":\\s*"(https:\\\\/\\\\/[^"]+\\.mp4)"', dotAll: true).firstMatch(html);
    if (match != null) {
      directLink = match.group(1);
      title += ' [${quality}p]';
      break;
    }
  }

  // If no quality-specific URL found, try the default URL
  if (directLink == null) {
    final matchDefault = RegExp(r'"url":"(https:\\\/\\\/[^"]+\.mp4)"').firstMatch(html);
    directLink = matchDefault?.group(1);
  }

  if (directLink == null) {
    controller.evaluateJavascript(source: 'alert(`Could not extract video URL from Rumble page`)');
    return;
  }

  // Decode the URL (handle escape sequences)
  directLink = directLink.replaceAll(r'\/', '/');

  process(controller, directLink, title, mode);
}

void streamwishPlayer(controller, url, mode) async {
  try {
    final headers = {
      'User-Agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    };

    // Fetch HTML
    var response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode != 200) {
      controller.evaluateJavascript(source: 'alert(`Video does not exist!\nChoose other player.`)');
      return;
    }

    // Extract title
    final document = parse(response.body);
    String title = document.querySelector('title')?.text ?? 'StreamWish Video';
    title = title.replaceAll(' - StreamWish', '').replaceAll(' - Stream', '');

    // Extract JS
    RegExp scriptRegex = RegExp(r"<script type='text/javascript'>(eval\(function\(p,a,c,k,e,d\).*?)</script>", dotAll: true);
    RegExp partsRegex = RegExp(r"eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.*?)',(\d+),(\d+),'(.*?)'.split\('\|'\)\)\)", dotAll: true);

    final scriptMatch = scriptRegex.firstMatch(response.body);
    if (scriptMatch == null) {
      controller.evaluateJavascript(source: 'alert(`Could not extract video code`)');
      return;
    }

    final partsMatch = partsRegex.firstMatch(scriptMatch.group(1)!);
    if (partsMatch == null) {
      controller.evaluateJavascript(source: 'alert(`Could not extract video code parameters`)');
      return;
    }

    // Unpack JS
    final unpacked = _unpack(partsMatch.group(1)!, int.parse(partsMatch.group(2)!), int.parse(partsMatch.group(3)!), partsMatch.group(4)!.split('|'));

    // Extract video URL
    RegExp linksRegex = RegExp(r'"hls\d*"\s*:\s*"(https?://[^"]+\.m3u8[^"]*)"', dotAll: true);
    final match = linksRegex.firstMatch(unpacked);

    if (match == null) {
      controller.evaluateJavascript(source: 'alert(`Could not find video URL`)');
      return;
    }

    // Process the extracted video URL
    process(controller, match.group(1)!, title, mode);
  } catch (e) {
    controller.evaluateJavascript(source: 'alert(`Error: ${e.toString()}`)');
  }
}

/// [streamwishPlayer] Core unpacker algorithm
String _unpack(String p, int a, int c, List<String> k) {
  int counter = c;
  while (counter > 0) {
    counter--;
    if (k[counter].isNotEmpty) {
      final regex = RegExp('\\b${_baseEncode(counter, a)}\\b', caseSensitive: false);
      p = p.replaceAll(regex, k[counter]);
    }
  }
  return p;
}

/// [streamwishPlayer] Mimics toString(base) method in JS for base encoding
String _baseEncode(int num, int base) {
  if (num < 0) {
    return '-${_baseEncode(-num, base)}';
  }

  const String digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  if (num < base) {
    return digits[num];
  }

  return _baseEncode(num ~/ base, base) + digits[num % base];
}

//Helper function for dood provider
String generateRandomString(token) {
  var result = '';
  var characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  var charLength = characters.length;
  var random = Random();

  for (var i = 0; i < 10; i++) {
    result += characters[random.nextInt(charLength)];
  }

  return '$result?token=$token&expiry=${DateTime.now().millisecondsSinceEpoch}';
}

Future<void> requestIgnoreBatteryOptimizations() async {
  final status = await Permission.ignoreBatteryOptimizations.request();
  if (status.isGranted) {
    final packageName = Platform.resolvedExecutable.split('/').last.split('-')[0];
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$packageName',
    );
    await intent.launch();
  }
}
