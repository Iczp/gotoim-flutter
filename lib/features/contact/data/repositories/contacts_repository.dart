import '../datasources/contacts_api.dart';
import '../models/contact_group.dart';

class ContactsRepository {
  ContactsRepository(this._api);

  final ContactsApi _api;

  Future<List<ContactGroup>> loadIndexedFriends({required int ownerId}) =>
      _api.getIndexedFriends(ownerId: ownerId);
}
