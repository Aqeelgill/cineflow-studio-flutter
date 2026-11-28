enum MediaFilter { all, moviesVideo, dualAudio, hd4k1080, audioOnly }

extension MediaFilterX on MediaFilter {
  String get label {
    switch (this) {
      case MediaFilter.all: return 'All Media';
      case MediaFilter.moviesVideo: return 'Movies & Video (MP4/MKV)';
      case MediaFilter.dualAudio: return 'Dual Audio / Dubbed';
      case MediaFilter.hd4k1080: return '4K / 1080p HD';
      case MediaFilter.audioOnly: return 'Audio Only (MP3/M4A)';
    }
  }
}

class ScannedMediaItem {
  final String url;
  final String title;
  final String format;
  final String tag;
  bool selected;
  ScannedMediaItem({required this.url, required this.title, required this.format, required this.tag, this.selected = false});

  factory ScannedMediaItem.fromJson(Map<String, dynamic> j) => ScannedMediaItem(
    url: '${j['url'] ?? ''}'.trim(),
    title: '${j['title'] ?? j['url'] ?? ''}'.trim(),
    format: '${j['format'] ?? ''}'.trim().toUpperCase(),
    tag: '${j['tag'] ?? ''}'.trim(),
  );

  bool matches(MediaFilter filter) {
    final f = format.toLowerCase();
    final t = tag.toLowerCase();
    final u = url.toLowerCase();
    final text = '$f $t $u ${title.toLowerCase()}';
    final isAudio = ['mp3','m4a','aac','flac','wav','ogg'].contains(f) || RegExp(r'\.(mp3|m4a|aac|flac|wav|ogg)(\?|$)').hasMatch(u);
    final isVideo = ['mp4','mkv','avi','mov','wmv','flv','webm','m4v','ts','m3u8','mpd'].contains(f) || RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m3u8|mpd)(\?|$)').hasMatch(u) || u.contains('youtube') || u.contains('youtu.be') || u.contains('dailymotion') || u.contains('vimeo') || u.contains('facebook');
    switch (filter) {
      case MediaFilter.all: return true;
      case MediaFilter.moviesVideo: return isVideo && !isAudio;
      case MediaFilter.dualAudio: return text.contains('dual audio') || text.contains('multi audio') || text.contains('dubbed') || text.contains('hindi') || text.contains('urdu');
      case MediaFilter.hd4k1080: return text.contains('4k') || text.contains('2160p') || text.contains('1080p');
      case MediaFilter.audioOnly: return isAudio;
    }
  }
}
