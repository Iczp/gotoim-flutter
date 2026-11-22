import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../application/contacts_controller.dart';
import '../data/models/contact_entry_item.dart';

/// 联系人自定义条目项编辑表单行数据模型
class _EntryFormItem {
  _EntryFormItem({
    required this.definition,
    required this.controller,
    required this.selectedOption,
  });

  final EntryNameDefinition definition;
  final TextEditingController controller;
  String? selectedOption;
  String? errorText;

  void validate() {
    final value = definition.isChoice
        ? (selectedOption ?? '')
        : controller.text.trim();

    if (definition.isRequired && value.isEmpty) {
      errorText = '${definition.title}不能为空';
      return;
    }

    if (value.isNotEmpty) {
      if (definition.maxLength != null && value.length > definition.maxLength!) {
        errorText = '${definition.title}长度不能超过${definition.maxLength}个字符';
        return;
      }
      if (definition.minLength != null && value.length < definition.minLength!) {
        errorText = '${definition.title}长度不能少于${definition.minLength}个字符';
        return;
      }
      if (definition.regex != null && definition.regex!.isNotEmpty) {
        try {
          final reg = RegExp(definition.regex!);
          if (!reg.hasMatch(value)) {
            errorText = definition.errorMessage != null &&
                    definition.errorMessage!.isNotEmpty
                ? definition.errorMessage
                : '${definition.title}格式不正确';
            return;
          }
        } catch (_) {}
      }
    }

    errorText = null;
  }
}

/// 联系人自定义条目编辑弹窗
class ContactEntryEditorDialog extends ConsumerStatefulWidget {
  const ContactEntryEditorDialog({
    required this.sessionUnitId,
    required this.initialEntries,
    this.onSaved,
    super.key,
  });

  final String sessionUnitId;
  final List<ContactEntryItem> initialEntries;
  final VoidCallback? onSaved;

  static Future<void> show(
    BuildContext context, {
    required String sessionUnitId,
    required List<ContactEntryItem> initialEntries,
    VoidCallback? onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ContactEntryEditorDialog(
        sessionUnitId: sessionUnitId,
        initialEntries: initialEntries,
        onSaved: onSaved,
      ),
    );
  }

  @override
  ConsumerState<ContactEntryEditorDialog> createState() =>
      _ContactEntryEditorDialogState();
}

class _ContactEntryEditorDialogState
    extends ConsumerState<ContactEntryEditorDialog> {
  final List<_EntryFormItem> _formItems = [];
  List<EntryNameDefinition> _allDefinitions = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDefinitions();
  }

  @override
  void dispose() {
    for (final item in _formItems) {
      item.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDefinitions() async {
    final controller = ref.read(contactsControllerProvider);
    final defs = await controller.loadEntryNames();
    if (!mounted) return;

    setState(() {
      _allDefinitions = defs;
      _isLoading = false;

      // 绑定已有条目
      final defMap = {for (final d in defs) d.id: d};
      for (final entry in widget.initialEntries) {
        EntryNameDefinition def;
        if (defMap.containsKey(entry.entryNameId)) {
          def = defMap[entry.entryNameId]!;
        } else {
          def = EntryNameDefinition(
            id: entry.entryNameId,
            name: entry.name,
            title: entry.title,
            isChoice: entry.isChoice,
            options: entry.options,
            regex: entry.regex,
            errorMessage: entry.errorMessage,
          );
        }

        _formItems.add(
          _EntryFormItem(
            definition: def,
            controller: TextEditingController(text: entry.value),
            selectedOption: entry.isChoice ? entry.value : null,
          ),
        );
      }
    });
  }

  void _addNewField(EntryNameDefinition def) {
    if (_formItems.any((e) => e.definition.id == def.id)) {
      showToast('${def.title}已在列表中');
      return;
    }
    setState(() {
      _formItems.add(
        _EntryFormItem(
          definition: def,
          controller: TextEditingController(),
          selectedOption: def.isChoice && def.options.isNotEmpty
              ? def.options.first
              : null,
        ),
      );
    });
  }

  void _removeField(int index) {
    setState(() {
      _formItems[index].controller.dispose();
      _formItems.removeAt(index);
    });
  }

  Future<void> _handleSave() async {
    var hasError = false;
    for (final item in _formItems) {
      item.validate();
      if (item.errorText != null) {
        hasError = true;
      }
    }

    setState(() {});

    if (hasError) {
      showToast('请检查表单中未通过的输入项');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final Map<String, List<String>> payload = {};
      for (final item in _formItems) {
        final val = item.definition.isChoice
            ? (item.selectedOption ?? '')
            : item.controller.text.trim();
        if (val.isNotEmpty) {
          payload[item.definition.id] = [val];
        }
      }

      await ref
          .read(contactsControllerProvider)
          .saveContactEntries(widget.sessionUnitId, payload);

      if (!mounted) return;
      showToast('保存成功', type: ToastType.success);
      Navigator.of(context).pop();
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      showToast('保存失败: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 可添加的候选字段（排除已有的）
    final existingIds = _formItems.map((e) => e.definition.id).toSet();
    final availableDefs =
        _allDefinitions.where((d) => !existingIds.contains(d.id)).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '编辑联系人自定义资料',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    splashRadius: 18,
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '私有扩展字段仅自己可见，支持电话、邮箱、网址、客户级别与自定义备注。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 0.5),

              // 字段列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          if (_formItems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 36),
                              child: Center(
                                child: Text(
                                  '暂无自定义扩展字段，点击下方按钮添加',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            )
                          else
                            ...List.generate(_formItems.length, (index) {
                              final item = _formItems[index];
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _buildFieldRow(item, index),
                              );
                            }),

                          const SizedBox(height: 16),

                          // 添加新字段按钮/菜单
                          if (availableDefs.isNotEmpty)
                            PopupMenuButton<EntryNameDefinition>(
                              tooltip: '添加字段',
                              onSelected: _addNewField,
                              itemBuilder: (context) {
                                return availableDefs.map((def) {
                                  return PopupMenuItem(
                                    value: def,
                                    height: 38,
                                    child: Row(
                                      children: [
                                        Icon(
                                          def.isChoice
                                              ? Icons.list_alt_rounded
                                              : Icons.text_fields_rounded,
                                          size: 16,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          def.title,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList();
                              },
                              child: OutlinedButton.icon(
                                onPressed: null, // 由 PopupMenuButton 接管点击
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('添加字段'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 12),

              // 底部操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isSaving || _isLoading ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF07C160),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldRow(_EntryFormItem item, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final def = item.definition;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.errorText != null
              ? colorScheme.error
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                def.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (def.isRequired)
                Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const Spacer(),
              InkWell(
                onTap: () => _removeField(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: colorScheme.error.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (def.isChoice && def.options.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: item.selectedOption,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              items: def.options.map((opt) {
                return DropdownMenuItem(
                  value: opt,
                  child: Text(opt, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  item.selectedOption = val;
                  item.validate();
                });
              },
            )
          else
            TextFormField(
              controller: item.controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '请输入${def.title}',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                errorText: item.errorText,
                errorMaxLines: 2,
              ),
              onChanged: (_) {
                if (item.errorText != null) {
                  setState(() => item.validate());
                }
              },
            ),
          if (item.errorText != null && def.isChoice) ...[
            const SizedBox(height: 4),
            Text(
              item.errorText!,
              style: TextStyle(fontSize: 11, color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
