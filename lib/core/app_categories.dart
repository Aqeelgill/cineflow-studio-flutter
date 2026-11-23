class AppCategory {
  final String id;
  final String label;
  final String folderName;
  const AppCategory({required this.id, required this.label, required this.folderName});
}

class AppCategories {
  static const webSeries = AppCategory(id: 'web_series', label: 'Web Series', folderName: 'Web Series');
  static const dramaShows = AppCategory(id: 'drama_shows', label: 'Drama Shows', folderName: 'Drama Shows');
  static const hollywoodMovies = AppCategory(id: 'hollywood_movies', label: 'Hollywood Movies', folderName: 'Hollywood Movies');
  static const indianMovies = AppCategory(id: 'indian_movies', label: 'Indian Movies', folderName: 'Indian Movies');
  static const stageShows = AppCategory(id: 'stage_shows', label: 'Stage Shows', folderName: 'Stage Shows');
  static const mp3Songs = AppCategory(id: 'mp3_songs', label: 'MP3 Songs', folderName: 'MP3 Songs');
  static const mp4Songs = AppCategory(id: 'mp4_songs', label: 'MP4 Songs', folderName: 'MP4 Songs');
  static const cartoons = AppCategory(id: 'cartoons', label: 'Cartoons', folderName: 'Cartoons');
  static const poems = AppCategory(id: 'poems', label: 'Poems', folderName: 'Poems');

  static const List<AppCategory> all = [
    webSeries, dramaShows, hollywoodMovies, indianMovies, stageShows,
    mp3Songs, mp4Songs, cartoons, poems,
  ];

  static AppCategory byId(String? id) =>
      all.where((c) => c.id == id).cast<AppCategory?>().firstOrNull ?? webSeries;
}
