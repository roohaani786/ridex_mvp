import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UserService extends GetxService {
  static UserService get to => Get.find();

  late String userId;
  late String userName;

  Future<UserService> init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? _generateUserId(prefs);
    userName = prefs.getString('userName') ?? 'Rider ${userId.substring(0, 4).toUpperCase()}';
    return this;
  }

  String _generateUserId(SharedPreferences prefs) {
    final id = const Uuid().v4();
    prefs.setString('userId', id);
    return id;
  }

  Future<void> setName(String name) async {
    userName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
  }
}
