import 'package:flutter_test/flutter_test.dart';
import 'package:miltv_universal/main.dart';

void main() {
  test('parseM3u extracts channel metadata', () {
    const input = '#EXTM3U\n#EXTINF:-1 tvg-logo="https://logo.test/a.png" group-title="Noticias" tvg-country="AR",Canal Uno\nhttps://stream.test/live.m3u8\n';
    final result = parseM3u(input);
    expect(result, hasLength(1));
    expect(result.single.name, 'Canal Uno');
    expect(result.single.group, 'Noticias');
    expect(result.single.country, 'AR');
    expect(result.single.logo, 'https://logo.test/a.png');
    expect(result.single.url, 'https://stream.test/live.m3u8');
  });

  test('parseM3u ignores comments and blank lines', () {
    const input = '#EXTM3U\n\n#EXTINF:-1,Test\n# comment\nhttps://stream.test/a\n';
    expect(parseM3u(input), hasLength(1));
  });

  test('parseM3u handles EXTINF names containing commas', () {
    const input = '#EXTM3U\n#EXTINF:-1 group-title="General",Canal, Noticias\nhttps://stream.test/news.m3u8\n';
    final result = parseM3u(input);
    expect(result.single.name, 'Canal, Noticias');
  });

  test('parseM3u resets metadata between entries', () {
    const input = '#EXTM3U\n#EXTINF:-1 tvg-logo="https://logo.test/a.png" group-title="A",Uno\nhttps://stream.test/1\n#EXTINF:-1,Dos\nhttps://stream.test/2\n';
    final result = parseM3u(input);
    expect(result[0].group, 'A');
    expect(result[1].group, 'Sin categoría');
    expect(result[1].logo, '');
  });

  test('parseM3u skips orphan stream URLs', () {
    const input = '#EXTM3U\nhttps://stream.test/orphan\n#EXTINF:-1,Valid\nhttps://stream.test/valid\n';
    final result = parseM3u(input);
    expect(result, hasLength(1));
    expect(result.single.name, 'Valid');
  });
}
