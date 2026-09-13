import 'package:flutter_application_2/Models/gallery_zoom.dart';
import 'package:flutter_application_2/Models/photo_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snaps continuous density to supported column levels', () {
    expect(nearestGalleryColumnLevel(5.8), 6);
    expect(nearestGalleryColumnLevel(7.2), 8);
    expect(nearestGalleryColumnLevel(13), 16);
  });

  test('groups 8-column view by month and 16-column view by year', () {
    PhotoItem item(int year, int month, int day) => PhotoItem(
      id: '$year-$month-$day',
      createTime: DateTime(year, month, day).millisecondsSinceEpoch,
    );

    final dailyGroups = <String, List<PhotoItem>>{
      '第一天': [item(2026, 9, 13)],
      '第二天': [item(2026, 9, 1)],
      '第三天': [item(2026, 8, 20)],
      '去年': [item(2025, 12, 31)],
    };

    final monthGroups = groupGalleryItems(dailyGroups, 8);
    expect(monthGroups.keys, ['2026年9月', '2026年8月', '2025年12月']);
    expect(monthGroups['2026年9月'], hasLength(2));

    final yearGroups = groupGalleryItems(dailyGroups, 16);
    expect(yearGroups.keys, ['2026年', '2025年']);
    expect(yearGroups['2026年'], hasLength(3));
  });
}
