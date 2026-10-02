import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
bool cloudAuthReady = false;
const testMode = String.fromEnvironment('MILTV_TEST_MODE') == 'true';

Future<bool> initCloudAuth() async {
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) return false;
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
    cloudAuthReady = true;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final cloudAuth = await initCloudAuth();
  runApp(MiltvApp(cloudAuth: cloudAuth));
}

const defaultArgentinaM3u = 'https://iptv-org.github.io/iptv/countries/ar.m3u';
const defaultWorldM3u = 'https://iptv-org.github.io/iptv/index.m3u';

class Channel {
  final String name, url, logo, group, country;
  const Channel({required this.name, required this.url, this.logo = '', this.group = 'Sin categoría', this.country = ''});

  String get id => '${name.toLowerCase()}|$url';
}

List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  var name = '';
  var logo = '';
  var group = 'Sin categoría';
  var country = '';
  for (final raw in const LineSplitter().convert(text.replaceAll('\r', ''))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      name = comma >= 0 ? line.substring(comma + 1).trim() : 'Sin nombre';
      String attr(String key) => RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line)?.group(1)?.trim() ?? '';
      logo = attr('tvg-logo');
      group = attr('group-title').isEmpty ? 'Sin categoría' : attr('group-title');
      country = attr('tvg-country');
    } else if (!line.startsWith('#') && name.isNotEmpty) {
      out.add(Channel(name: name, url: line, logo: logo, group: group, country: country));
      name = '';
      logo = '';
      group = 'Sin categoría';
      country = '';
    }
  }
  return out;
}

class AuthService {
  static bool get cloudEnabled => cloudAuthReady;

  static Future<String?> register(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) return 'Ingresá un email válido.';
    if (password.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'\d').hasMatch(password)) {
      return 'La contraseña necesita 8 caracteres, letras y un número.';
    }
    if (cloudEnabled) {
      try {
        final response = await Supabase.instance.client.auth.signUp(email: normalized, password: password);
        if (response.session != null) return null;
        return 'Cuenta creada. Revisá tu email para confirmar la cuenta.';
      } on AuthException catch (e) {
        return e.message;
      } catch (_) {
        return 'No se pudo crear la cuenta.';
      }
    }
    final p = await SharedPreferences.getInstance();
    final users = p.getStringList('users') ?? <String>[];
    if (users.any((u) => u.startsWith('$normalized|'))) return 'Ya existe una cuenta con ese email.';
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final digest = sha256.convert(Uint8List.fromList([...salt, ...utf8.encode(password)])).toString();
    users.add('$normalized|${base64UrlEncode(salt)}|$digest');
    await p.setStringList('users', users);
    await p.setString('session', normalized);
    return null;
  }

  static Future<String?> login(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    if (cloudEnabled) {
      try {
        final response = await Supabase.instance.client.auth.signInWithPassword(email: normalized, password: password);
        return response.session == null ? 'No se pudo iniciar sesión.' : null;
      } on AuthException catch (e) {
        return e.message;
      } catch (_) {
        return 'No se pudo iniciar sesión.';
      }
    }
    final p = await SharedPreferences.getInstance();
    final users = p.getStringList('users') ?? <String>[];
    for (final u in users) {
      final parts = u.split('|');
      if (parts.length == 3 && parts[0] == normalized) {
        final salt = base64Url.decode(parts[1]);
        final digest = sha256.convert(Uint8List.fromList([...salt, ...utf8.encode(password)])).toString();
        if (digest == parts[2]) {
          await p.setString('session', normalized);
          return null;
        }
      }
    }
    return 'Email o contraseña incorrectos.';
  }

  static Future<void> logout() async {
    if (cloudEnabled) {
      await Supabase.instance.client.auth.signOut();
      return;
    }
    await (await SharedPreferences.getInstance()).remove('session');
  }

  static Future<String?> session() async {
    if (cloudEnabled) return Supabase.instance.client.auth.currentSession?.user.email;
    return (await SharedPreferences.getInstance()).getString('session');
  }
}

class AppStore {
  static Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  static Future<Set<String>> favorites() async => (await _prefs).getStringList('favorites')?.toSet() ?? <String>{};
  static Future<void> setFavorites(Set<String> values) async => (await _prefs).setStringList('favorites', values.toList());
  static Future<List<String>> sources() async => (await _prefs).getStringList('sources') ?? <String>[defaultArgentinaM3u, defaultWorldM3u];
  static Future<void> setSources(List<String> values) async => (await _prefs).setStringList('sources', values.toSet().toList());
  static Future<String?> lastSource() async => (await _prefs).getString('last_source');
  static Future<void> setLastSource(String value) async => (await _prefs).setString('last_source', value);
  static Future<bool> tvMode() async => (await _prefs).getBool('tv_mode') ?? false;
  static Future<void> setTvMode(bool value) async => (await _prefs).setBool('tv_mode', value);
}

class MiltvApp extends StatelessWidget {
  final bool cloudAuth;
  const MiltvApp({super.key, required this.cloudAuth});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MILTV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffff5a00), brightness: Brightness.dark),
          scaffoldBackgroundColor: const Color(0xff070b10),
          cardTheme: const CardThemeData(margin: EdgeInsets.zero),
        ),
        home: Gate(cloudAuth: cloudAuth),
      );
}

class Gate extends StatefulWidget {
  final bool cloudAuth;
  const Gate({super.key, required this.cloudAuth});
  @override State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? session;
  @override void initState() {
    super.initState();
    if (testMode) return;
    AuthService.session().then((v) { if (mounted) setState(() => session = v); });
  }
  @override Widget build(BuildContext context) => session == null
      ? AuthPage(onDone: (v) => setState(() => session = v), cloudAuth: widget.cloudAuth)
      : HomePage(email: session!, onLogout: () async { await AuthService.logout(); if (mounted) setState(() => session = null); });
}

class AuthPage extends StatefulWidget {
  final void Function(String) onDone;
  final bool cloudAuth;
  const AuthPage({super.key, required this.onDone, required this.cloudAuth});
  @override State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool register = false, busy = false, obscure = true;
  final email = TextEditingController();
  final pass = TextEditingController();
  String error = '';

  Future<void> submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { busy = true; error = ''; });
    final e = register ? await AuthService.register(email.text, pass.text) : await AuthService.login(email.text, pass.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (e != null) { setState(() => error = e); return; }
    widget.onDone(email.text.trim().toLowerCase());
  }

  @override void dispose() { email.dispose(); pass.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔥 MILTV', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(register ? 'Crear cuenta' : 'Ingresar', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: pass, obscureText: obscure, onSubmitted: (_) => submit(), autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: 'Contraseña', prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)))),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : submit, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login), label: Text(busy ? 'Procesando…' : (register ? 'Crear cuenta' : 'Ingresar')))),
            TextButton(onPressed: busy ? null : () => setState(() { register = !register; error = ''; }), child: Text(register ? 'Ya tengo una cuenta' : 'Crear una cuenta')),
            const SizedBox(height: 4),
            Text(widget.cloudAuth ? 'Cuenta cloud segura mediante Supabase.' : 'Modo local de desarrollo: para producción configurá Supabase Auth.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]))),
        ))),
      );
}

class HomePage extends StatefulWidget {
  final String email;
  final VoidCallback onLogout;
  const HomePage({super.key, required this.email, required this.onLogout});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final search = TextEditingController();
  final player = Player();
  late final video = VideoController(player);
  List<Channel> channels = [];
  Set<String> favorites = {};
  List<String> sources = [];
  bool loading = false, tvMode = false, onlyFavorites = false;
  String error = '', query = '', group = 'Todos';
  Channel? selected;
  String playerError = '';
  bool playerLoading = false;
  StreamSubscription<String>? _playerErrorSub;
  StreamSubscription<bool>? _bufferingSub;
  Timer? _playerTimeout;

  @override
  void initState() {
    super.initState();
    search.addListener(() { if (mounted) setState(() => query = search.text.trim().toLowerCase()); });
    _playerErrorSub = player.stream.error.listen((message) {
      if (!mounted || message.isEmpty) return;
      setState(() => playerError = message);
    });
    _init();
  }

  Future<void> _init() async {
    favorites = await AppStore.favorites();
    sources = await AppStore.sources();
    tvMode = await AppStore.tvMode();
    if (mounted) setState(() {});
    final saved = await AppStore.lastSource();
    final initial = (saved != null && sources.contains(saved)) ? saved : sources.first;
    await load(initial);
  }

  Future<void> load(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      if (mounted) setState(() => error = 'La fuente debe ser una URL http:// o https:// válida.');
      return;
    }
    setState(() { loading = true; error = ''; });
    try {
      final r = await http.get(uri, headers: {
        'User-Agent': 'MILTV/1.0',
        'Accept': 'audio/x-mpegurl, application/x-mpegURL, text/plain, */*',
      }).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = parseM3u(r.body);
      if (list.isEmpty) throw Exception('No se encontraron canales en la lista');
      setState(() { channels = list; group = 'Todos'; });
      await AppStore.setLastSource(url);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${list.length} canales cargados')));
    } catch (e) {
      if (mounted) setState(() => error = 'No se pudo cargar la lista: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Channel> get filtered {
    final result = channels.where((c) {
      final matchesGroup = group == 'Todos' || c.group == group;
      final matchesFavorite = !onlyFavorites || favorites.contains(c.id);
      final matchesQuery = query.isEmpty || c.name.toLowerCase().contains(query) || c.group.toLowerCase().contains(query) || c.country.toLowerCase().contains(query);
      return matchesGroup && matchesFavorite && matchesQuery;
    }).toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  void toggleFavorite(Channel ch) async {
    setState(() { favorites.contains(ch.id) ? favorites.remove(ch.id) : favorites.add(ch.id); });
    await AppStore.setFavorites(favorites);
  }

  Future<void> play(Channel ch) async {
    _playerTimeout?.cancel();
    setState(() { selected = ch; playerError = ''; playerLoading = true; });
    _playerTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && selected?.id == ch.id && playerLoading) {
        setState(() {
          playerLoading = false;
          playerError = 'El canal tardó demasiado en iniciar. Revisá la fuente o intentá nuevamente.';
        });
      }
    });
    try {
      await player.open(Media(ch.url), play: true);
    } catch (e) {
      if (mounted && selected?.id == ch.id) {
        setState(() { playerError = e.toString(); playerLoading = false; });
      }
    }
  }

  @override void dispose() {
    _playerTimeout?.cancel();
    _playerErrorSub?.cancel();
    _bufferingSub?.cancel();
    player.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final groups = ['Todos', ...{for (final c in channels) c.group}];
    final wide = width >= 1050;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MILTV', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Favoritos', onPressed: () => setState(() => onlyFavorites = !onlyFavorites), icon: Icon(onlyFavorites ? Icons.star : Icons.star_border)),
          IconButton(tooltip: 'Fuentes', onPressed: _sourceDialog, icon: const Icon(Icons.link)),
          IconButton(tooltip: 'Configuración', onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
          IconButton(tooltip: 'Cerrar sesión', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: wide ? Row(children: [Expanded(child: _catalog(groups)), SizedBox(width: 460, child: _playerPane())]) : _catalog(groups),
    );
  }

  Widget _catalog(List<String> groups) => FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(children: [
          if (selected != null && MediaQuery.sizeOf(context).width < 1050)
            Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: SizedBox(width: double.infinity, child: AspectRatio(aspectRatio: 16 / 9, child: _playerPane()))),
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: TextField(controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar canal, categoría o país', border: OutlineInputBorder(), suffixIcon: Icon(Icons.tune)))),
          SizedBox(height: 48, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 12), scrollDirection: Axis.horizontal, itemCount: groups.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) => ChoiceChip(label: Text(groups[i]), selected: group == groups[i], onSelected: (_) => setState(() => group = groups[i])))),
          Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : error.isNotEmpty ? _errorState() : filtered.isEmpty ? const Center(child: Text('No hay canales para este filtro.')) : GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: tvMode ? 340 : 300, childAspectRatio: tvMode ? 1.45 : 1.55, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: filtered.length, itemBuilder: (_, i) => _channelCard(filtered[i]))),
        ]),
      );

  Widget _channelCard(Channel ch) => FocusableActionDetector(
        autofocus: tvMode && selected?.id == ch.id,
        onFocusChange: (focused) { if (mounted && focused) setState(() {}); },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{ActivateIntent: CallbackAction<Intent>(onInvoke: (_) { play(ch); return null; })},
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: focused ? Theme.of(context).colorScheme.primary : Colors.transparent, width: focused ? 3 : 1),
            ),
            child: Card(
              elevation: focused ? 10 : 2,
              child: InkWell(onTap: () => play(ch), borderRadius: BorderRadius.circular(12), child: Padding(padding: EdgeInsets.all(tvMode ? 18 : 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Stack(children: [Center(child: ch.logo.isEmpty ? Icon(Icons.tv, size: tvMode ? 52 : 42) : Image.network(ch.logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.tv, size: tvMode ? 52 : 42))), Positioned(top: 0, right: 0, child: IconButton(onPressed: () => toggleFavorite(ch), icon: Icon(favorites.contains(ch.id) ? Icons.star : Icons.star_border), tooltip: 'Favorito'))])),
                const SizedBox(height: 8), Text(ch.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: tvMode ? 16 : 14)),
                Text(ch.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]))),
            ),
          );
        }),
      );

  Widget _playerPane() => Container(
        color: Colors.black,
        child: selected == null
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.live_tv, size: 64, color: Colors.white24), SizedBox(height: 12), Text('Elegí un canal para reproducir')]))
            : Stack(children: [
                Column(children: [
                  Expanded(child: Video(controller: video, fit: BoxFit.contain)),
                  Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                    Expanded(child: Text(selected!.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => player.playOrPause(), icon: const Icon(Icons.play_pause)),
                  ])),
                ]),
                if (playerLoading) const Positioned.fill(child: IgnorePointer(child: Center(child: Card(child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator()))))),
                if (playerError.isNotEmpty)
                  Positioned(left: 12, right: 12, bottom: 56, child: Card(color: Colors.red.shade900.withValues(alpha: .92), child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: Text('Error de reproducción: $playerError', maxLines: 3, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), IconButton(tooltip: 'Reintentar', onPressed: selected == null ? null : () => play(selected!), icon: const Icon(Icons.refresh))])))),
              ]));

  Widget _errorState() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 54), const SizedBox(height: 12), Text(error, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: sources.isEmpty ? null : () => load(sources.first), icon: const Icon(Icons.refresh), label: const Text('Reintentar'))])));

  Future<void> _sourceDialog() async {
    final ctl = TextEditingController();
    await showDialog(context: context, builder: (d) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: const Text('Fuentes M3U'),
      content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Nueva URL M3U', hintText: 'https://.../lista.m3u')),
        const SizedBox(height: 10),
        const Align(alignment: Alignment.centerLeft, child: Text('Fuentes guardadas', style: TextStyle(fontWeight: FontWeight.bold))),
        const SizedBox(height: 6),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260), child: ListView.builder(shrinkWrap: true, itemCount: sources.length, itemBuilder: (_, i) {
          final src = sources[i];
          return ListTile(dense: true, leading: Icon(src == sources.first ? Icons.star : Icons.link), title: Text(src, maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () async { Navigator.pop(d); await load(src); }, trailing: sources.length <= 1 ? null : IconButton(tooltip: 'Eliminar', onPressed: () async { sources.removeAt(i); await AppStore.setSources(sources); refresh(() {}); }, icon: const Icon(Icons.delete_outline)));
        })),
        const SizedBox(height: 8),
        const Text('Usá listas propias o autorizadas.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cerrar')),
        FilledButton(onPressed: () async { final url = ctl.text.trim(); if (url.isEmpty) return; final uri = Uri.tryParse(url); if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return; sources = [url, ...sources.where((x) => x != url)]; await AppStore.setSources(sources); if (mounted) Navigator.pop(d); await load(url); }, child: const Text('Agregar y cargar')),
      ],
    )));
    ctl.dispose();
  }

  Future<void> _settings() async {
    var localTv = tvMode;
    await showDialog(context: context, builder: (d) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(title: const Text('Configuración'), content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [SwitchListTile(title: const Text('Modo TV'), subtitle: const Text('Tarjetas grandes y navegación pensada para control remoto'), value: localTv, onChanged: (v) => setLocal(() => localTv = v)), const Divider(), ListTile(leading: const Icon(Icons.person_outline), title: Text(widget.email), subtitle: const Text('Cuenta local de prueba')), ListTile(leading: const Icon(Icons.source_outlined), title: Text('${sources.length} fuentes guardadas'), subtitle: const Text('Las fuentes se almacenan en este dispositivo'))])), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')), FilledButton(onPressed: () async { tvMode = localTv; await AppStore.setTvMode(tvMode); if (mounted) { setState(() {}); Navigator.pop(d); } }, child: const Text('Guardar'))]));
  }
}
