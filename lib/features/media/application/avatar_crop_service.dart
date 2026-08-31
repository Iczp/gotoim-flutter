import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_navigation.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/widgets/avatar_preferences.dart';

class AvatarCropService {
  AvatarCropService(this._media);
  final MediaService _media;

  Future<SelectedFile?> chooseAndCrop({
    required AvatarShape previewShape,
  }) async {
    final files = await _media.chooseImage(
      const MediaPickRequest(allowMultiple: false),
    );
    if (files.isEmpty) return null;
    return crop(files.first, previewShape: previewShape);
  }

  Future<SelectedFile?> crop(
    SelectedFile source, {
    required AvatarShape previewShape,
  }) async {
    final path = source.originalPath;
    if (path != null) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        maxWidth: 1024,
        maxHeight: 1024,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle:
                previewShape == AvatarShape.circle ? '裁剪圆形头像预览' : '裁剪方形头像',
            lockAspectRatio: true,
          ),
          IOSUiSettings(title: '裁剪头像', aspectRatioLockEnabled: true),
          if (rootNavigatorKey.currentContext case final context?)
            WebUiSettings(context: context),
        ],
      );
      if (cropped == null) return null;
      return SelectedFile.fromXFile(
        XFile(cropped.path, name: '${_baseName(source.name)}_avatar.jpg'),
      );
    }
    return _centerCrop(source);
  }

  Future<SelectedFile> _centerCrop(SelectedFile source) async {
    final input = await source.readBytes();
    final decoded = image.decodeImage(input);
    if (decoded == null) throw const FormatException('无法解码所选头像图片。');
    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final cropped = image.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = image.copyResize(cropped, width: 1024, height: 1024);
    final bytes = Uint8List.fromList(image.encodeJpg(resized, quality: 92));
    return SelectedFile.fromXFile(
      XFile.fromData(
        bytes,
        name: '${_baseName(source.name)}_avatar.jpg',
        mimeType: 'image/jpeg',
      ),
    );
  }

  String _baseName(String value) => value.replaceFirst(RegExp(r'\.[^.]+$'), '');
}
