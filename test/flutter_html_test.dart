import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    "Check that widget does not fail on empty data",
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Html(
            data: "",
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    "Check that selectable widget does not fail on empty data",
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableHtml(
            data: '',
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    "Check that widget displays given text",
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Html(
            data: "Text",
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Text', findRichText: true), findsOneWidget);
    },
  );

  testWidgets('Check that a simple element is displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Html(
          data: "<p>Text</p>",
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Text', findRichText: true), findsOneWidget);
  });

  testWidgets(
      'Check that a simple element is hidden when tagsList does not contain it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Html(
          data: "<p>Text</p>",
          tagsList: const ['div'], //Anything but `p`
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Text', findRichText: true), findsNothing);
  });

  testWidgets(
      'Check that a simple element is displayed when it is included in tagsList',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Html(
          data: "<p>Text</p>",
          tagsList: const ['html', 'body', 'p'],
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Text', findRichText: true), findsOneWidget);
  });

  testWidgets('Check that a custom element is not displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Html(
          data: "<custom>Text</custom>",
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Text', findRichText: true), findsNothing);
  });

  testWidgets('Check that a custom element is not displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Html(
          data: "<custom>Text</custom>",
          tagsList: Html.tags..add('custom'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Text', findRichText: true), findsOneWidget);
  });
}
