import 'package:dostr_blossom_url/dostr_blossom_url.dart';

import 'blossom_blobs.dart';

enum UploadPhase { hashing, uploading, mirroring }

/// Progress information for blob uploads
class BlobUploadProgress {
  /// the server this progress is about, null while hashing and in the
  /// progress about no server, such as the first and the last of an upload
  final BlossomServerUrl? currentServer;
  final int sentBytes;
  final int totalBytes;
  final List<BlobUploadResult> completedUploads;
  final bool isComplete;

  final UploadPhase phase; // hashing | uploading | mirroring

  /// the phases this upload goes through, in order, which [progress] splits
  /// evenly. One that turns out to have nothing to do, such as mirroring once
  /// the last server took the blob, is skipped at once.
  final List<UploadPhase> phases;

  final double progressPhase; // 0.0 - 1.0 for current phase
  final double percentagePhase; // 0.0 - 100.0 for current phase

  // For mirroring phase
  final int mirrorsTotal;
  final int mirrorsCompleted;

  BlobUploadProgress({
    this.currentServer,
    required this.sentBytes,
    required this.totalBytes,
    required this.completedUploads,
    this.phase = UploadPhase.uploading,
    this.phases = UploadPhase.values,
    double? progressPhase,
    int? mirrorsTotal,
    int? mirrorsCompleted,
    this.isComplete = false,
  }) : progressPhase =
           ((progressPhase ?? (totalBytes > 0 ? sentBytes / totalBytes : 0))
                   .clamp(0.0, 1.0))
               .toDouble(),
       percentagePhase =
           ((progressPhase ?? (totalBytes > 0 ? sentBytes / totalBytes : 0))
                   .clamp(0.0, 1.0))
               .toDouble() *
           100,
       mirrorsTotal = mirrorsTotal ?? 0,
       mirrorsCompleted = mirrorsCompleted ?? 0;

  /// this progress, for an upload that goes through [phases]
  BlobUploadProgress withPhases(List<UploadPhase> phases) => BlobUploadProgress(
    currentServer: currentServer,
    sentBytes: sentBytes,
    totalBytes: totalBytes,
    completedUploads: completedUploads,
    phase: phase,
    phases: phases,
    progressPhase: progressPhase,
    mirrorsTotal: mirrorsTotal,
    mirrorsCompleted: mirrorsCompleted,
    isComplete: isComplete,
  );

  double get uploadProgress => totalBytes > 0 ? sentBytes / totalBytes : 0;

  /// Overall progress, each of [phases] taking an equal share
  double get progress {
    if (isComplete) return 1;
    final index = phases.indexOf(phase);
    return index < 0 ? progressPhase : (index + progressPhase) / phases.length;
  }

  double get percentage => progress * 100;
}
