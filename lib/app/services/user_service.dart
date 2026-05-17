import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UserService extends GetxService {
  static UserService get to => Get.find();

  late String userId;
  final userName = RxString(''); // ← change to reactive

  Future<UserService> init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? _generateUserId(prefs);
    final saved = prefs.getString('userName') ?? '';
    userName.value = saved.isEmpty
        ? 'Rider ${userId.substring(0, 4).toUpperCase()}'
        : saved;
    return this;
  }

  bool get isNameDefault =>
      userName.value.startsWith('Rider ') && userName.value.length == 10;

  Future<void> setName(String name) async {
    userName.value = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name.trim());
  }

  String _generateUserId(SharedPreferences prefs) {
    final id = const Uuid().v4();
    prefs.setString('userId', id);
    return id;
  }
}
