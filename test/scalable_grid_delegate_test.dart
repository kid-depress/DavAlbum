import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_2/Widgets/scalable_grid_delegate.dart';

void main() {
  testWidgets('tile size and position follow fractional columns', (
    tester,
  ) async {
    Future<void> pumpGrid(double columnCount) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: CustomScrollView(
                slivers: [
                  SliverGrid(
                    gridDelegate: ScalableGridDelegate(
                      columnCount: columnCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, index) => SizedBox(key: ValueKey(index)),
                      childCount: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await pumpGrid(4);
    final fourColumnSize = tester.getSize(find.byKey(const ValueKey(0)));
    final fourColumnPosition = tester.getTopLeft(find.byKey(const ValueKey(3)));

    await pumpGrid(3.5);
    final transitionSize = tester.getSize(find.byKey(const ValueKey(0)));
    final transitionPosition = tester.getTopLeft(find.byKey(const ValueKey(3)));

    await pumpGrid(3);
    final threeColumnSize = tester.getSize(find.byKey(const ValueKey(0)));
    final threeColumnPosition = tester.getTopLeft(
      find.byKey(const ValueKey(3)),
    );

    expect(
      transitionSize.width,
      inInclusiveRange(fourColumnSize.width, threeColumnSize.width),
    );
    expect(
      transitionPosition.dx,
      inInclusiveRange(threeColumnPosition.dx, fourColumnPosition.dx),
    );
    expect(
      transitionPosition.dy,
      inInclusiveRange(fourColumnPosition.dy, threeColumnPosition.dy),
    );
    expect(transitionSize.aspectRatio, 1);
  });
}
