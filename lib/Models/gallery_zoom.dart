import 'photo_item.dart';

const galleryColumnLevels = <double>[2, 3, 4, 5, 6, 8, 16];

enum GalleryGrouping { day, month, year }

double nearestGalleryColumnLevel(double value) {
  var nearest = galleryColumnLevels.first;
  var nearestDistance = (value - nearest).abs();
  for (final level in galleryColumnLevels.skip(1)) {
    final distance = (value - level).abs();
    if (distance < nearestDistance) {
      nearest = level;
      nearestDistance = distance;
    }
  }
  return nearest;
}

GalleryGrouping galleryGroupingForDensity(double columnCount) {
  final level = nearestGalleryColumnLevel(columnCount);
  if (level >= 16) return GalleryGrouping.year;
  if (level >= 8) return GalleryGrouping.month;
  return GalleryGrouping.day;
}

Map<String, List<PhotoItem>> groupGalleryItems(
  Map<String, List<PhotoItem>> dailyGroups,
  double columnCount,
) {
  final grouping = galleryGroupingForDensity(columnCount);
  if (grouping == GalleryGrouping.day) return dailyGroups;

  final items = dailyGroups.values.expand((group) => group).toList()
    ..sort((a, b) => b.createTime.compareTo(a.createTime));
  final groups = <String, List<PhotoItem>>{};
  for (final item in items) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.createTime);
    final label = grouping == GalleryGrouping.year
        ? '${date.year}年'
        : '${date.year}年${date.month}月';
    groups.putIfAbsent(label, () => []).add(item);
  }
  return groups;
}
