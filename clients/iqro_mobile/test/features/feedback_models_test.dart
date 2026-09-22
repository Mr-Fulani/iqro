import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/feedback/feedback_models.dart';

void main() {
  test('parses a feedback detail with messages and context', () {
    final ticket = FeedbackTicket.fromJson(<String, Object?>{
      'public_id': 'FB-test',
      'category': 'audio',
      'subject': 'The reciter timing is off',
      'status': 'in_progress',
      'priority': 'high',
      'locale': 'ru',
      'channel': 'android',
      'sla_response_due_at': null,
      'first_response_at': '2026-09-20T10:00:00Z',
      'created_at': '2026-09-20T09:00:00Z',
      'updated_at': '2026-09-20T10:30:00Z',
      'client_request_id': 'request-id',
      'contact_email': 'reader@example.com',
      'team': 'content_quality',
      'resolved_at': null,
      'closed_at': null,
      'reopened_at': null,
      'reopen_count': 0,
      'context': <String, Object?>{
        'route': '/feedback',
        'app_version': '1.0.0',
        'app_build': '1',
        'client_platform': 'android',
        'os_version': '15',
      },
      'messages': <Object?>[
        <String, Object?>{
          'id': 'message-id',
          'client_message_id': 'client-message-id',
          'author_type': 'reporter',
          'body': 'Please review this timestamp.',
          'created_at': '2026-09-20T09:00:00Z',
        },
      ],
    });

    expect(ticket.publicId, 'FB-test');
    expect(ticket.messages.single.body, 'Please review this timestamp.');
    expect(ticket.context?.clientPlatform, 'android');
    expect(ticket.canReply, isTrue);
    expect(ticket.canReopen, isFalse);
  });

  test('does not offer reporter actions for rejected tickets', () {
    final ticket = FeedbackTicket.fromJson(<String, Object?>{
      'public_id': 'FB-rejected',
      'category': 'other',
      'subject': 'A request',
      'status': 'rejected',
      'priority': 'normal',
      'locale': 'en',
      'channel': 'android',
      'created_at': '2026-09-20T09:00:00Z',
      'updated_at': '2026-09-20T09:00:00Z',
    });

    expect(ticket.isTerminal, isTrue);
    expect(ticket.canReply, isFalse);
    expect(ticket.canReopen, isFalse);
  });
}
