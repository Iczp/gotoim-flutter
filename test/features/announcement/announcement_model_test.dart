import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/announcement/data/models/session_announcement.dart';

void main() {
  group('SessionAnnouncement Models Test', () {
    test('SessionAnnouncement fromJson & copyWith', () {
      final json = {
        'id': 'ann-123',
        'sessionId': 'session-456',
        'chatObjectId': 'obj-789',
        'publisherSessionUnitId': 'unit-1',
        'publisherChatObjectId': 'user-1',
        'publisherName': '管理员小张',
        'publisherAvatar': 'https://example.com/avatar.png',
        'title': '测试群公告',
        'content': '请大家遵守群规',
        'editorType': 1,
        'status': 1,
        'isPinned': true,
        'pinnedTime': '2026-11-23T00:00:00Z',
        'isPopup': true,
        'requireConfirm': true,
        'confirmedCount': 3,
        'readCount': 5,
        'linkedMessageId': 'msg-999',
        'creationTime': '2026-11-23T00:00:00Z',
        'isSelfConfirmed': false,
        'isSelfRead': false,
      };

      final announcement = SessionAnnouncement.fromJson(json);

      expect(announcement.id, 'ann-123');
      expect(announcement.sessionId, 'session-456');
      expect(announcement.chatObjectId, 'obj-789');
      expect(announcement.title, '测试群公告');
      expect(announcement.content, '请大家遵守群规');
      expect(announcement.isPinned, isTrue);
      expect(announcement.requireConfirm, isTrue);
      expect(announcement.publisherName, '管理员小张');
      expect(announcement.readCount, 5);
      expect(announcement.confirmedCount, 3);
      expect(announcement.isSelfConfirmed, isFalse);
      expect(announcement.isSelfRead, isFalse);

      // copyWith test
      final updated = announcement.copyWith(
        isSelfRead: true,
        isSelfConfirmed: true,
        confirmedCount: 4,
      );
      expect(updated.isSelfRead, isTrue);
      expect(updated.isSelfConfirmed, isTrue);
      expect(updated.confirmedCount, 4);
      expect(updated.id, 'ann-123');
    });

    test('SessionAnnouncementStat fromJson', () {
      final json = {
        'announcementId': 'ann-123',
        'totalMemberCount': 100,
        'readCount': 80,
        'unreadCount': 20,
        'confirmedCount': 65,
        'unconfirmedCount': 35,
        'readRate': 0.8,
        'confirmedRate': 0.65,
      };

      final stat = SessionAnnouncementStat.fromJson(json);
      expect(stat.announcementId, 'ann-123');
      expect(stat.totalMemberCount, 100);
      expect(stat.readCount, 80);
      expect(stat.unreadCount, 20);
      expect(stat.confirmedCount, 65);
      expect(stat.unconfirmedCount, 35);
      expect(stat.readRate, 0.8);
      expect(stat.confirmedRate, 0.65);
    });

    test('SessionAnnouncementMember fromJson', () {
      final json = {
        'sessionUnitId': 'unit-101',
        'chatObjectId': 'user-202',
        'name': '李四',
        'portrait': 'https://example.com/lisi.png',
        'isConfirmed': true,
        'confirmedTime': '2026-11-23T00:15:00Z',
        'firstReadTime': '2026-11-23T00:10:00Z',
        'isCreator': false,
        'isAdmin': true,
      };

      final member = SessionAnnouncementMember.fromJson(json);
      expect(member.sessionUnitId, 'unit-101');
      expect(member.name, '李四');
      expect(member.isConfirmed, isTrue);
      expect(member.confirmedTime, '2026-11-23T00:15:00Z');
      expect(member.firstReadTime, '2026-11-23T00:10:00Z');
      expect(member.isAdmin, isTrue);
    });
  });
}
