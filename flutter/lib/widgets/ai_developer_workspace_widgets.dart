import 'package:flutter/material.dart';

import '../services/ai_developer_engineer_service.dart';
import '../services/ai_developer_workspace_service.dart';

class AiDeveloperEngineerPreviewPanel extends StatelessWidget {
  final AiDeveloperEngineerPreview preview;

  const AiDeveloperEngineerPreviewPanel({
    super.key,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hivra Engineer outbound preview',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          SelectableText('Capsule ${preview.capsuleSnapshotHashHex}'),
          SelectableText(
            'Developer context ${preview.developerContextHashHex}',
          ),
          Text('${preview.snippetCount} snippet(s)'),
          Text('${preview.payloadBytes} bytes'),
          const SizedBox(height: 6),
          const Text(
            'Advisory only: no file writes, patch application, git operations, release actions, ledger mutation, or plugin registry mutation.',
          ),
        ],
      ),
    );
  }
}

class AiDeveloperSelectedContextPanel extends StatelessWidget {
  final AiDeveloperWorkspaceSelectedContext contextData;
  final int? requestedFileCount;

  const AiDeveloperSelectedContextPanel({
    super.key,
    required this.contextData,
    required this.requestedFileCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected developer context', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText('Context ${contextData.contextHashHex}'),
          Text('${contextData.snippets.length} snippet(s)'),
          Text('${contextData.payloadBytes} bytes'),
          if (requestedFileCount != null &&
              requestedFileCount != contextData.snippets.length) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.10),
                border: Border.all(
                  color: Colors.amberAccent.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Selected $requestedFileCount file(s), included '
                '${contextData.snippets.length}. Missing files were skipped by '
                'workspace guards or were not present in the scan result.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.amberAccent,
                ),
              ),
            ),
          ],
          if (contextData.findings.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...contextData.findings.map(
              (finding) => Text('${finding.severity}: ${finding.title}'),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Preview JSON'),
            children: [
              SelectableText(contextData.toPrettyJson()),
            ],
          ),
        ],
      ),
    );
  }
}

class AiDeveloperWorkspaceRepoTile extends StatelessWidget {
  final AiDeveloperWorkspaceRepoSummary repo;
  final ValueChanged<String> onAddFile;

  const AiDeveloperWorkspaceRepoTile({
    super.key,
    required this.repo,
    required this.onAddFile,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(repo.rootPath),
      subtitle: Text(
        '${repo.scannedFileCount} files · '
        '${repo.skippedFileCount} skipped files · '
        '${repo.findings.length} finding(s)',
      ),
      children: [
        ...repo.files.take(12).map(
              (file) => ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text(file.relativePath),
                subtitle: SelectableText(
                  '${file.sizeBytes} bytes · ${file.sha256Hex}',
                ),
                trailing: TextButton.icon(
                  onPressed: () => onAddFile(file.relativePath),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ),
        if (repo.files.length > 12)
          ListTile(
            dense: true,
            title: Text('+${repo.files.length - 12} more file(s)'),
          ),
        if (repo.findings.isNotEmpty)
          ...repo.findings.map(
            (finding) => ListTile(
              dense: true,
              leading: Icon(
                finding.severity == 'critical'
                    ? Icons.error_outline
                    : Icons.info_outline,
                color:
                    finding.severity == 'critical' ? Colors.red : Colors.orange,
              ),
              title: Text(finding.title),
              subtitle: Text(
                '${finding.detail}\nAction: ${finding.recommendedAction}',
              ),
            ),
          ),
      ],
    );
  }
}

class AiDeveloperWorkspaceQuickAddPanel extends StatelessWidget {
  final List<String> availableFiles;
  final List<String> firstFiles;
  final List<String> coreFiles;
  final List<String> doctorFiles;
  final ValueChanged<Iterable<String>> onAddFiles;

  const AiDeveloperWorkspaceQuickAddPanel({
    super.key,
    required this.availableFiles,
    required this.firstFiles,
    required this.coreFiles,
    required this.doctorFiles,
    required this.onAddFiles,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (availableFiles.isEmpty) {
      return Text(
        'No selectable files found in the scanned repositories.',
        style: theme.textTheme.bodySmall,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick add context files', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Pick files before building selected context. Nothing is sent to AI until you press Ask Hivra Engineer.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (firstFiles.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: Text('Add first ${firstFiles.length}'),
                  onPressed: () => onAddFiles(firstFiles),
                ),
              if (coreFiles.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.menu_book_outlined),
                  label: Text('Add core docs (${coreFiles.length})'),
                  onPressed: () => onAddFiles(coreFiles),
                ),
              if (doctorFiles.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.psychology_alt_outlined),
                  label: Text('Add AI tooling files (${doctorFiles.length})'),
                  onPressed: () => onAddFiles(doctorFiles),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
