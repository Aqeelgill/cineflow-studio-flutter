import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/engine/handlers/handler_registry.dart';

void main() {
  test('priority routing for manifest, ftp, media, and https', () {
    final reg = HandlerRegistry();
    expect(reg.resolveHandlerForUri(Uri.parse('https://example.com/video.m3u8')).name, 'stream-manifest');
    expect(reg.resolveHandlerForUri(Uri.parse('https://example.com/video.mpd')).name, 'stream-manifest');
    expect(reg.resolveHandlerForUri(Uri.parse('ftp://example.com/file.zip')).name, 'ftp');
    expect(reg.resolveHandlerForUri(Uri.parse('https://www.youtube.com/watch?v=abc')).name, 'media-extractor');
    expect(reg.resolveHandlerForUri(Uri.parse('https://example.com/file.bin')).name, 'http-range');
  });
}
