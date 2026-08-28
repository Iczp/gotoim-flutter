import '../../../../core/network/api_client.dart';
import '../models/contact_group.dart';
import '../../../session/data/models/paged_result_dto.dart';

class ContactsApi {
  ContactsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ContactGroup>> getIndexedFriends({required int ownerId}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friends-indexed/$ownerId',
    );
    return PagedResultDto<ContactGroup>.fromJson(
      response,
      ContactGroup.fromJson,
    ).items.where((group) => group.contacts.isNotEmpty).toList(growable: false);
  }
}
