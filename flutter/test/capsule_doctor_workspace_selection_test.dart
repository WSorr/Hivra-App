import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/capsule_doctor_screen.dart';

void main() {
  test('quick add extends and deduplicates developer workspace selection', () {
    final merged = mergeDeveloperWorkspaceFileSelections(
      currentPaths: const <String>[
        'docs/roadmap.md',
        'docs/specification.md',
        ' docs/roadmap.md ',
      ],
      suggestedPaths: const <String>[
        'README.md',
        'docs/specification.md',
        'Cargo.toml',
      ],
    );

    expect(merged, const <String>[
      'Cargo.toml',
      'README.md',
      'docs/roadmap.md',
      'docs/specification.md',
    ]);
  });

  test('quick add never exceeds the developer workspace selection limit', () {
    final merged = mergeDeveloperWorkspaceFileSelections(
      currentPaths: const <String>['one.md', 'two.md', 'three.md'],
      suggestedPaths: const <String>['four.md', 'five.md', 'six.md'],
      maxPaths: 4,
    );

    expect(merged, const <String>['four.md', 'one.md', 'three.md', 'two.md']);
  });
}
