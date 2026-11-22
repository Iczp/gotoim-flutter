import 'package:flutter/foundation.dart';

/// 联系人条目项（系统公开条目 或 用户私有自定义条目）
@immutable
class ContactEntryItem {
  const ContactEntryItem({
    required this.entryNameId,
    required this.name,
    required this.title,
    required this.value,
    this.isStatic = false,
    this.isChoice = false,
    this.regex,
    this.errorMessage,
    this.options = const <String>[],
  });

  factory ContactEntryItem.fromJson(Map<String, dynamic> json) {
    final entryName = json['entryName'] as Map<String, dynamic>?;
    final entryValue = json['entryValue'] as Map<String, dynamic>?;

    final nameId = entryName?['id']?.toString() ??
        json['entryNameId']?.toString() ??
        '';
    final name = entryName?['name']?.toString() ??
        json['name']?.toString() ??
        '';
    final title = entryName?['title']?.toString() ??
        json['title']?.toString() ??
        name;

    final val = json['value']?.toString() ??
        entryValue?['value']?.toString() ??
        '';

    final optsRaw = entryName?['options'] ?? json['options'];
    final options = optsRaw is List
        ? optsRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    return ContactEntryItem(
      entryNameId: nameId,
      name: name,
      title: title.isEmpty ? name : title,
      value: val,
      isStatic: entryName?['isStatic'] == true || json['isStatic'] == true,
      isChoice: entryName?['isChoice'] == true || json['isChoice'] == true,
      regex: entryName?['regex']?.toString() ?? json['regex']?.toString(),
      errorMessage: entryName?['errorMessage']?.toString() ??
          json['errorMessage']?.toString(),
      options: options,
    );
  }

  final String entryNameId;
  final String name;
  final String title;
  final String value;
  final bool isStatic;
  final bool isChoice;
  final String? regex;
  final String? errorMessage;
  final List<String> options;

  Map<String, dynamic> toJson() => {
        'entryNameId': entryNameId,
        'name': name,
        'title': title,
        'value': value,
        'isStatic': isStatic,
        'isChoice': isChoice,
        'regex': regex,
        'errorMessage': errorMessage,
        'options': options,
      };
}

/// 系统字段定义
@immutable
class EntryNameDefinition {
  const EntryNameDefinition({
    required this.id,
    required this.name,
    required this.title,
    this.isRequired = false,
    this.isChoice = false,
    this.isStatic = false,
    this.regex,
    this.errorMessage,
    this.options = const <String>[],
    this.maxLength,
    this.minLength,
  });

  factory EntryNameDefinition.fromJson(Map<String, dynamic> json) {
    final optsRaw = json['options'];
    final options = optsRaw is List
        ? optsRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    return EntryNameDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      isRequired: json['isRequired'] == true,
      isChoice: json['isChoice'] == true,
      isStatic: json['isStatic'] == true,
      regex: json['regex']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      options: options,
      maxLength: json['maxLength'] is num ? (json['maxLength'] as num).toInt() : null,
      minLength: json['minLength'] is num ? (json['minLength'] as num).toInt() : null,
    );
  }

  final String id;
  final String name;
  final String title;
  final bool isRequired;
  final bool isChoice;
  final bool isStatic;
  final String? regex;
  final String? errorMessage;
  final List<String> options;
  final int? maxLength;
  final int? minLength;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'isRequired': isRequired,
        'isChoice': isChoice,
        'isStatic': isStatic,
        'regex': regex,
        'errorMessage': errorMessage,
        'options': options,
        'maxLength': maxLength,
        'minLength': minLength,
      };
}

/// 联系人详情信息（含系统条目与私有自定义条目）
@immutable
class ContactDetail {
  const ContactDetail({
    required this.id,
    required this.displayName,
    this.destinationId,
    this.systemEntries = const <ContactEntryItem>[],
    this.userEntries = const <ContactEntryItem>[],
  });

  factory ContactDetail.fromJson(Map<String, dynamic> json) {
    final dest = json['destination'] as Map<String, dynamic>?;
    final displayName = json['displayName']?.toString() ??
        json['rename']?.toString() ??
        dest?['name']?.toString() ??
        json['name']?.toString() ??
        '';

    final destEntriesRaw = dest?['entries'];
    final List<ContactEntryItem> systemEntries = destEntriesRaw is List
        ? destEntriesRaw
            .whereType<Map>()
            .map((e) => ContactEntryItem.fromJson(Map<String, dynamic>.from(e)))
            .where((item) => item.value.isNotEmpty)
            .toList(growable: false)
        : const <ContactEntryItem>[];

    final userEntriesRaw = json['entries'];
    final List<ContactEntryItem> userEntries = userEntriesRaw is List
        ? userEntriesRaw
            .whereType<Map>()
            .map((e) => ContactEntryItem.fromJson(Map<String, dynamic>.from(e)))
            .where((item) => item.value.isNotEmpty)
            .toList(growable: false)
        : const <ContactEntryItem>[];

    final destIdVal = dest?['id'] ?? dest?['Id'] ?? json['destinationId'];
    final int? destId = destIdVal is num ? destIdVal.toInt() : int.tryParse(destIdVal?.toString() ?? '');

    return ContactDetail(
      id: json['id']?.toString() ?? '',
      displayName: displayName,
      destinationId: destId,
      systemEntries: systemEntries,
      userEntries: userEntries,
    );
  }

  final String id;
  final String displayName;
  final int? destinationId;
  final List<ContactEntryItem> systemEntries;
  final List<ContactEntryItem> userEntries;
}
