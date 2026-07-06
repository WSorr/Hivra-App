import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_patch_proposal_service.dart';

void main() {
  group('AiPatchProposalService', () {
    test('previews unified diff without applying side effects', () {
      const service = AiPatchProposalService();

      final first = service.preview(const AiPatchProposalRequest(
        sourceLabel: 'hivra_engineer',
        proposalText: '''
diff --git a/docs/demo.md b/docs/demo.md
--- a/docs/demo.md
+++ b/docs/demo.md
@@ -1,2 +1,3 @@
 hello
-old
+new
+line
''',
      ));
      final second = service.preview(const AiPatchProposalRequest(
        sourceLabel: 'hivra_engineer',
        proposalText: '''
diff --git a/docs/demo.md b/docs/demo.md
--- a/docs/demo.md
+++ b/docs/demo.md
@@ -1,2 +1,3 @@
 hello
-old
+new
+line
''',
      ));

      expect(first.reportHashHex, second.reportHashHex);
      expect(first.previewOnly, isTrue);
      expect(first.applySkipped, isTrue);
      expect(first.gitSkipped, isTrue);
      expect(first.releaseSkipped, isTrue);
      expect(first.fileChanges.single.oldPath, 'docs/demo.md');
      expect(first.fileChanges.single.newPath, 'docs/demo.md');
      expect(first.fileChanges.single.addedLines, 2);
      expect(first.fileChanges.single.removedLines, 1);
    });

    test('rejects prose without unified diff', () {
      const service = AiPatchProposalService();

      expect(
        () => service.preview(const AiPatchProposalRequest(
          proposalText: 'Please edit docs/demo.md by hand.',
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects oversized proposal before preview', () {
      const service = AiPatchProposalService();

      expect(
        () => service.preview(AiPatchProposalRequest(
          proposalText: 'x' * (AiPatchProposalService.maxProposalBytes + 1),
        )),
        throwsA(isA<StateError>()),
      );
    });
  });
}
