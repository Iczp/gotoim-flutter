import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Project-owned file-selection contract.
///
/// Absolute paths and file bytes deliberately stay inside the platform service.
/// The public [SelectedFile] result is safe to return to diagnostics and H5.
abstract class FilePickerService {
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request);
}

class FilePickerRequest {
  const FilePickerRequest({
    this.allowMultiple = false,
    this.allowedExtensions = const <String>[],
    this.dialogTitle,
  });

  final bool allowMultiple;
  final List<String> allowedExtensions;
  final String? dialogTitle;
}

class SelectedFile {
  const SelectedFile({
    required this.name,
    required this.size,
    required this.extension,
    required this.hasNativePath,
  });

  final String name;
  final int size;
  final String? extension;
  final bool hasNativePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'size': size,
    'extension': extension,
    'hasNativePath': hasNativePath,
  };
}

class SystemFilePickerService implements FilePickerService {
  const SystemFilePickerService();

  @override
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request) async {
    final type =
        request.allowedExtensions.isEmpty ? FileType.any : FileType.custom;
    final files = <PlatformFile>[];
    if (request.allowMultiple) {
      files.addAll(
        await FilePicker.pickFiles(
          dialogTitle: request.dialogTitle,
          type: type,
          allowedExtensions:
              request.allowedExtensions.isEmpty
                  ? null
                  : request.allowedExtensions,
        ),
      );
    } else {
      final file = await FilePicker.pickFile(
        dialogTitle: request.dialogTitle,
        type: type,
        allowedExtensions:
            request.allowedExtensions.isEmpty
                ? null
                : request.allowedExtensions,
      );
      if (file != null) {
        files.add(file);
      }
    }
    return Future.wait(files.map(_toSelectedFile));
  }

  Future<SelectedFile> _toSelectedFile(PlatformFile file) async {
    final dot = file.name.lastIndexOf('.');
    return SelectedFile(
      name: file.name,
      size: await file.length(),
      extension:
          dot > 0 && dot < file.name.length - 1
              ? file.name.substring(dot + 1).toLowerCase()
              : null,
      hasNativePath: file.path != null,
    );
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const SystemFilePickerService(),
);
