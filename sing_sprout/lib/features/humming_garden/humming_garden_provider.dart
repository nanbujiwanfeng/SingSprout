import 'package:flutter/foundation.dart';
import '../../shared/models/music_work.dart';
import '../../shared/services/work_repository.dart';

/// 哼唱花园状态管理
class HummingGardenProvider extends ChangeNotifier {
  final List<MusicWork> _works = [];
  bool _isLoading = false;

  List<MusicWork> get works => List.unmodifiable(_works);
  bool get isLoading => _isLoading;

  /// 添加作品
  void addWork(MusicWork work) {
    _works.insert(0, work);
    notifyListeners();
  }

  /// 删除作品
  void deleteWork(String id) {
    _works.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  /// 加载本地作品
  Future<void> loadWorks() async {
    _isLoading = true;
    notifyListeners();

    final repo = WorkRepository();
    final loaded = await repo.getWorks();
    _works.clear();
    _works.addAll(loaded);

    _isLoading = false;
    notifyListeners();
  }
}
