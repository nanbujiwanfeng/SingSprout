/// 温柔引导话术 — 面向 8-13 岁儿童
/// 禁用"失败""错误""噪音""不足"等负面词汇
class GentleCopy {
  GentleCopy._();

  // ── 哼唱花园页面 ──
  static const String pageTitle = '哼唱花园';
  static const String pandaGreeting = '嘿！今天想哼点什么？\n试试对着手机哼一句～';
  static const String hintLongPress = '长按5-15秒开始哼唱';
  static const String recentWorksTitle = '最近作品';
  static const String viewAll = '查看全部';
  static const String emptyWorks = '还没有作品哦，长按开始你的第一首歌吧～';

  // ── 录音反馈 ──
  static const String tooShort = '再哼一小会儿吧～';
  static const String tooShortHint = '哼唱时间有点短，试试哼满3秒哦！';
  static const String tooNoisy = '这里有点吵，换个安静的地方试试吧～';
  static const String noSound = '我好像没听到声音，再试一次？';
  static const String recordingDone = '哼唱完成，正在为你创作中...';
  static const String maxTimeReached = '已经哼了30秒啦，很棒！让我们听听看～';
  static const String micPermissionHint = '需要麦克风才能听到你的歌声哦，去设置里打开吧～';

  // ── 处理与生成 ──
  static const String processing = '正在用 AI 听懂你的旋律...';
  static const String generationDone = '创作完成！来听听看吧～';

  // ── 芽苗加载动画 ──
  static const String sprouting = '你的音乐正在发芽…';
  static const String sproutPhase1 = '种子破土中…';
  static const String sproutPhase2 = '嫩芽正在生长…';
  static const String sproutPhase3 = '叶片正在舒展…';
  static const String modelFallback = '正在用更轻快的模式为你创作～';
  static const String modelFallbackHint = '稍微多等一会儿，好音乐值得等待～';

  // ── 风格预览 ──
  static const String previewHint = '长按试听3秒片段';
  static const String previewPlaying = '试听中…';
  static const String selectStyle = '选择风格';

  // ── 编辑器 ──
  static const String secondTrack = '第二段哼唱';
  static const String secondTrackHint = '再哼一段，让音乐更丰富～';
  static const String undo = '撤销';
  static const String reset = '重置';
  static const String resetConfirm = '确定要重置所有参数吗？';
  static const String savedAndShare = '保存并分享';
  static const String sendToParents = '发给爸妈';
  static const String musicTemp = '🎵 音乐温度';
  static const String musicSpeed = '⏱ 速度';
  static const String instrumentMix = '🎹 乐器比重';
  static const String softWarm = '柔和';
  static const String intense = '热烈';
  static const String slow = '慢';
  static const String fast = '快';
  static const String pureVocal = '纯人声';
  static const String richInstrument = '丰富配器';

  // ── 存储与设备 ──
  static const String storageLow = '存储空间有点紧张了～';
  static const String storageLowHint = '手机空间不太够，但别担心，你的作品不会被删掉的。可以请爸妈帮忙清理一下手机哦！';
  static const String lightModelLoaded = '已为你切换到轻量模式～';
  static const String deviceLowMem = '检测到你的设备内存较小，已自动加载轻量版本～';
  static const String savedSuccess = '作品保存成功！';
  static const String jumpToPostOffice = '生成音乐明信片';
  static const String jumpToPostOfficeHint = '想做成明信片发给家人吗？';

  // ── 通用鼓励 ──
  static const String greatJob = '太棒了！';
  static const String keepGoing = '继续加油～';
  static const String tryAgain = '没关系，再试一次吧！';
  static const String wonderful = '真好听！';
  static const String okGotIt = '好的～';
  static const String notNow = '先不用';
}
