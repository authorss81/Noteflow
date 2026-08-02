import 'package:flutter/foundation.dart';

@immutable
class Notebook {
  final String id;
  final String name;
  final DateTime createdAt;

  const Notebook({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Notebook copyWith({String? name}) =>
      Notebook(id: id, name: name ?? this.name, createdAt: createdAt);
}

@immutable
class Section {
  final String id;
  final String notebookId;
  final String name;
  final DateTime createdAt;

  const Section({
    required this.id,
    required this.notebookId,
    required this.name,
    required this.createdAt,
  });

  Section copyWith({String? name}) => Section(
      id: id, notebookId: notebookId, name: name ?? this.name, createdAt: createdAt);
}

@immutable
class NotePage {
  final String id;
  final String sectionId;
  final String title;
  final String? sourceFilePath;
  final String? sourceFileType; // pdf, image, text, none
  final int pageIndex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final bool deleted;
  final String? template; // blank, lined, grid, dots

  const NotePage({
    required this.id,
    required this.sectionId,
    required this.title,
    this.sourceFilePath,
    this.sourceFileType,
    this.pageIndex = 0,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.deleted = false,
    this.template,
  });

  NotePage copyWith({
    String? title,
    String? sourceFilePath,
    String? sourceFileType,
    int? pageIndex,
    DateTime? updatedAt,
    bool? pinned,
    bool? deleted,
    String? template,
  }) {
    return NotePage(
      id: id,
      sectionId: sectionId,
      title: title ?? this.title,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      sourceFileType: sourceFileType ?? this.sourceFileType,
      pageIndex: pageIndex ?? this.pageIndex,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      deleted: deleted ?? this.deleted,
      template: template ?? this.template,
    );
  }
}
