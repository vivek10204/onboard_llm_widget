//IMP: Diff from example (large)

// CHANGES:
// 1. Replaced logic in downloadModel (and added wrapper startDownload on top of it) to be able to do parallel, bg downloads and attach to running download, instead of using model manager logic for download.
// 2. Singleton: For parallel downloads of models. TBDO Check?
// 3. TBD Can the og logic be used? It has implemented the background download etc it seems? We want parallel, background and attachable downloads. Also, checkModelExistence and getFilePath have new definitions too.
// 4. Added a command uninstallModel in deleteModel, without which I noticed storage leaks

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'auth_token_service.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';

class ModelDownloadService {

  ///////////////////////////////////////////////////////////////////////////
  // IMP CHANGED: Added. For having one downloader instance per model to be able to run downloads in parallel. TBDO Check?

  final String modelUrl;
  final String modelFilename;
  final String licenseUrl;

  // ---------- Singleton management (one instance per model) ----------
  static final Map<String, ModelDownloadService> _instances = {};

  factory ModelDownloadService({
    required String modelUrl,
    required String modelFilename,
    required String licenseUrl,
  }) {
    final key = '$modelFilename|$modelUrl';
    return _instances.putIfAbsent(
      key,
          () => ModelDownloadService._internal(
        modelUrl: modelUrl,
        modelFilename: modelFilename,
        licenseUrl: licenseUrl,
      ),
    );
  }

  ModelDownloadService._internal({
    ///////////////////////////////////////////////////////////////////////////

    required this.modelUrl,
    required this.modelFilename,
    required this.licenseUrl,
  });

  ///////////////////////////////////////////////////////////////////////////
  // IMP CHANGED: Added for downloadModel/startDownload fn logic (instead of using model manager logic for download)
  // Sticky state
  bool _isDownloading = false;
  double _progress = 0.0;              // 0.0..1.0
  Object? _lastError;
  Future<void>? _activeDownload;       // in-flight future

  // Broadcast progress so any screen can listen
  final StreamController<double> _progressCtl =
  StreamController<double>.broadcast();

  Stream<double> get progressStream => _progressCtl.stream;
  double get currentProgress => _progress;
  bool get isDownloading => _isDownloading;
  Object? get lastError => _lastError;


  // --------------- Internal helpers ---------------
  void _emit(double p) {
    _progress = p.clamp(0.0, 1.0);
    if (!_progressCtl.isClosed) {
      _progressCtl.add(_progress);
    }
  }

  // Call this only on app shutdown if you want to reclaim streams
  Future<void> disposeManager() async {
    await _progressCtl.close();
  }


  // ---------------- Token helpers ----------------

  ///////////////////////////////////////////////////////////////////////////

  /// Load the token from SharedPreferences.
  Future<String?> loadToken() => AuthTokenService.loadToken();

  /// Save the token to SharedPreferences.
  Future<void> saveToken(String token) => AuthTokenService.saveToken(token);

  // ---------------- File helpers ----------------
  /// Helper method to get the file path.
  //////////////
  // IMP CHANGED: Replaced
  /*
  Future<String> getFilePath() async {
    // Use the same path correction logic as the unified system
    final directory = await getApplicationDocumentsDirectory();
    // Apply Android path correction for consistency with unified download system
    final correctedPath = directory.path.contains('/data/user/0/')
        ? directory.path.replaceFirst('/data/user/0/', '/data/data/')
        : directory.path;
    return '$correctedPath/$modelFilename';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence(String token) async {
    try {
      // Extract SAME filename that Modern API will use during download
      final uri = Uri.parse(modelUrl);
      final actualFilename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : modelFilename;

      // Modern API: Check if model is installed using actual filename
      final isInstalled = await FlutterGemma.isModelInstalled(actualFilename);

      if (isInstalled) {
        return true;
      }

      // Fallback: check physical file existence with size validation
      final filePath = await getFilePath();
      final file = File(filePath);

      if (!file.existsSync()) {
        return false;
      }

      // Validate size if possible
      final Map<String, String> headers =
          token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};

      try {
        final headResponse = await http.head(Uri.parse(modelUrl), headers: headers);
        if (headResponse.statusCode == 200) {
          final contentLengthHeader = headResponse.headers['content-length'];
          if (contentLengthHeader != null) {
            final remoteFileSize = int.parse(contentLengthHeader);
            return await file.length() == remoteFileSize;
          }
        }
      } catch (e) {
        // HEAD request failed (e.g., CORS on web), trust file existence
        if (kDebugMode) {
          debugPrint('HEAD request failed, trusting file existence: $e');
        }
        return true;
      }

      return true; // File exists, size validation failed/skipped
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking model existence: $e');
      }
    }
    return false;
  }
   */

  Future<String> getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$modelFilename';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence(String token) async {
    try {
      final filePath = await getFilePath();
      final file = File(filePath);

      // Check remote file size
      final Map<String, String> headers = token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
      final headResponse = await http.head(Uri.parse(modelUrl), headers: headers);

      if (headResponse.statusCode == 200) {
        final contentLengthHeader = headResponse.headers['content-length'];
        if (contentLengthHeader != null) {
          final remoteFileSize = int.parse(contentLengthHeader);
          if (file.existsSync() && await file.length() == remoteFileSize) {
            return true;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking model existence: $e');
      }
    }
    return false;
  }
  //////////////


  ///////////////////////////////////////////////////////////////////////////
  // IMP CHANGED: Added wrapper on top of downloadModel (to check if download is still running and attach to it)
  // --------------- Public entry: start or attach ---------------
  Future<void> startDownload({
    required String token,                     // may be empty if not needed
    void Function(double progress)? onProgress // optional per-caller hook
  }) async {

    // If already running, just attach to it
    if (_activeDownload != null) {
      final sub = progressStream.listen((p) => onProgress?.call(p));
      try {
        return await _activeDownload!;
      } finally {
        await sub.cancel();
      }
    }

    _isDownloading = true;
    _lastError = null;
    _emit(0.0);

    final completer = Completer<void>();
    _activeDownload = completer.future;

    // Kick off the actual HTTP stream download (no widget ties)
    () async {
      try {
        await downloadModel(
          token: token,
          onProgress: (p) {
            _emit(p);
            onProgress?.call(p);
          },
        );
        _emit(1.0);
        completer.complete();
      } catch (e) {
        _lastError = e;
        completer.completeError(e);
      } finally {
        _isDownloading = false;
        _activeDownload = null;
      }
    }();

    // Let caller await completion (and mirror progress if they want)
    final sub = progressStream.listen((p) => onProgress?.call(p));
    try {
      return await _activeDownload!;
    } finally {
      await sub.cancel();
    }
  }

  // --------------- Core download (your original logic) ---------------
  ///////////////////////////////////////////////////////////////////////////

  ///////////////////////////////////////////////////////////////////////////
  // IMP CHANGED: Replaced some parts of downloadModel: Manually creating HTTP request instead of relying on modelManager

  /// Downloads the model file and tracks progress using Modern API.
  Future<void> downloadModel({
    required String token,
    required Function(double) onProgress,
  }) async {
    ///////
    // IMP CHANGED: Added
    http.StreamedResponse? response;
    IOSink? fileSink;
    ///////

    try {

      ///////////
      // IMP CHANGED: Replaced

      /*
      // Convert empty string to null for cleaner API
      final authToken = token.isEmpty ? null : token;

      // Modern API: Install inference model from network with progress tracking
      await FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromNetwork(modelUrl, token: authToken).withProgress((progress) {
        onProgress(progress.toDouble());
      }).install();
       */

      final filePath = await getFilePath();
      final file = File(filePath);
      // Check if file already exists and partially downloaded
      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = await file.length();
      }

      // Create HTTP request
      final request = http.Request('GET', Uri.parse(modelUrl));
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Resume download if partially downloaded
      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      // Send request and handle response
      response = await request.send();

      if (response.statusCode == 416) {
        // Treat as fully downloaded if local file already matches remote
        try {
          final ok = await checkModelExistence(token);
          if (ok) {
            onProgress(1.0);
            return; // success path
          }
        } catch (_) {}
        throw Exception('Server returned 416, and local file is not complete.');
      }

      if (response.statusCode == 200 || response.statusCode == 206) {
        final contentLength = response.contentLength ?? 0;
        final totalBytes = downloadedBytes + contentLength;
        fileSink = file.openWrite(mode: FileMode.append);

        int received = downloadedBytes;

        // Listen to the stream and write to the file
        await for (final chunk in response.stream) {
          fileSink.add(chunk);
          received += chunk.length;

          // Update progress
          onProgress(totalBytes > 0 ? received / totalBytes : 0.0);
        }
      } else {
        if (kDebugMode) {
          print('Failed to download model. Status code: ${response.statusCode}');
          print('Headers: ${response.headers}');
          try {
            final errorBody = await response.stream.bytesToString();
            print('Error body: $errorBody');
          } catch (e) {
            print('Could not read error body: $e');
          }
        }
        throw Exception('Failed to download the model.');
      }

      ///////////


    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error downloading model: $e');
      }
      rethrow;
    }
    ///////////
    // IMP CHANGED: Added
    finally {
      if (fileSink != null) await fileSink.close();
    }
    ///////////

  }

  ///////////////////////////////////////////////////////////////////////////


  /// Deletes the downloaded file.
  Future<void> deleteModel() async {
    try {
      final filePath = await getFilePath();
      final file = File(filePath);

      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting model: $e');
      }
    }

    // IMP CHANGED: Added
    FlutterGemma.uninstallModel(modelFilename);
  }

}
