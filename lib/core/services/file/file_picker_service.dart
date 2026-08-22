import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:uuid/uuid.dart';

/// Project-owned file-selection and saving contract.
///
/// [SelectedFile] retains a live [XFile] handle for the current application
/// session. Callers can read it or pass it to an upload repository; the JSON
/// representation exposes the original URI/path required by H5 use cases.
abstract class FilePickerService {
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request);

  Future<SavedFile?> saveFile(FileSaveRequest request);

  Future<bool> clearTemporaryFiles();
}

enum FileTypeCategory {
  any,
  image,
  video,
  audio,
  media,
  custom,
}

class FilePickerRequest {
  const FilePickerRequest({
    this.allowMultiple = false,
    this.maxCount,
    this.allowedExtensions = const <String>[],
    this.fileType = FileTypeCategory.any,
    this.dialogTitle,
  });

  final bool allowMultiple;
  final int? maxCount;
  final List<String> allowedExtensions;
  final FileTypeCategory fileType;
  final String? dialogTitle;
}

class FileSaveRequest {
  const FileSaveRequest({
    required this.fileName,
    required this.bytes,
    this.mimeType = 'application/octet-stream',
    this.dialogTitle,
    this.initialDirectory,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  final String? dialogTitle;
  final String? initialDirectory;
}

/// A usable file reference, valid for the current app session.
class SelectedFile {
  SelectedFile._({
    required this.id,
    required this.name,
    required this.size,
    required this.extension,
    required this.mimeType,
    required this.originalUri,
    required this.originalPath,
    required XFile file,
  }) : _file = file;

  final String id;
  final String name;
  final int size;
  final String? extension;
  final String? mimeType;
  final Uri originalUri;
  final String? originalPath;
  final XFile _file;

  bool get hasNativePath => originalPath != null;

  Future<Uint8List> readBytes() => _file.readAsBytes();

  Stream<Uint8List> readAsByteStream() => _file.openRead();

  /// Does not survive an app restart. Persist/upload the file before then.
  Map<String, Object?> toJson() => <String, Object?>{
    'fileId': id,
    'name': name,
    'size': size,
    'extension': extension,
    'mimeType': mimeType,
    'uri': originalUri.toString(),
    'path': originalPath,
    'hasNativePath': hasNativePath,
  };

  static Future<SelectedFile> fromXFile(XFile file, {Uuid? uuid}) async {
    final name = file.name;
    final extension = _extensionOf(name);
    return SelectedFile._(
      id: (uuid ?? const Uuid()).v4(),
      name: name,
      size: await file.length(),
      extension: extension,
      mimeType: _mimeTypeFor(extension),
      originalUri: _uriOf(file),
      originalPath: _nativePath(file),
      file: file,
    );
  }

  static String? _nativePath(XFile file) {
    final path = file.path;
    if (path.isEmpty || path.startsWith('blob:') || path.startsWith('data:')) {
      return null;
    }
    final uri = Uri.tryParse(path);
    return uri?.scheme == 'file' ? uri!.toFilePath() : path;
  }

  static Uri _uriOf(XFile file) {
    final path = file.path;
    if (path.isEmpty) return Uri();
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(path, windows: RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path));
  }

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : null;
  }

  static String? _mimeTypeFor(String? extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'opus' => 'audio/ogg',
    _ => null,
  };
}

class SavedFile {
  const SavedFile({required this.uri});

  final Uri uri;

  String? get path => uri.scheme == 'file' ? uri.toFilePath() : null;

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri.toString(),
    'path': path,
    'hasNativePath': path != null,
  };
}

class SystemFilePickerService implements FilePickerService {
  SystemFilePickerService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request) async {
    final type = switch (request.fileType) {
      FileTypeCategory.image => FileType.image,
      FileTypeCategory.video => FileType.video,
      FileTypeCategory.audio => FileType.audio,
      FileTypeCategory.media => FileType.media,
      FileTypeCategory.custom => FileType.custom,
      FileTypeCategory.any =>
        request.allowedExtensions.isEmpty ? FileType.any : FileType.custom,
    };
    final files = <PlatformFile>[];
    if (request.allowMultiple) {
      final picked = await FilePicker.pickFiles(
        dialogTitle: request.dialogTitle,
        type: type,
        allowedExtensions:
            request.allowedExtensions.isEmpty
                ? null
                : request.allowedExtensions,
      );
      if (request.maxCount != null && request.maxCount! > 0 && picked.length > request.maxCount!) {
        files.addAll(picked.take(request.maxCount!));
      } else {
        files.addAll(picked);
      }
    } else {
      final file = await FilePicker.pickFile(
        dialogTitle: request.dialogTitle,
        type: type,
        allowedExtensions:
            request.allowedExtensions.isEmpty
                ? null
                : request.allowedExtensions,
      );
      if (file != null) files.add(file);
    }
    return Future.wait(
      files.map((file) => SelectedFile.fromXFile(file.xFile, uuid: _uuid)),
    );
  }

  @override
  Future<SavedFile?> saveFile(FileSaveRequest request) async {
    final uri = await FilePicker.saveFile(
      fileName: request.fileName,
      bytes: request.bytes,
      mimeType: request.mimeType,
      dialogTitle: request.dialogTitle,
      initialDirectory: request.initialDirectory,
    );
    return uri == null ? null : SavedFile(uri: uri);
  }

  @override
  Future<bool> clearTemporaryFiles() async {
    await FilePicker.clearTemporaryFiles();
    return true;
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => SystemFilePickerService(),
);
