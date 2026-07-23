/// 温柔引导话术 — 面向 8-13 岁儿童
/// 全程防挫败设计：禁用"错误""失败""不准""噪音""不足"等负面词汇
class GentleCopy {
  GentleCopy._();

  // ── 哼唱花园页面 ──
  static const String pageTitle = '哼唱花园';
  static const String pandaGreeting = '嘿！今天想哼点什么？\n试试对着手机哼一句～';
  static const String hintLongPress = '按住开始哼唱，5-15秒';
  static const String recentWorksTitle = '最近作品';
  static const String viewAll = '查看全部';
  static const String emptyWorks = '还没有作品哦，按住按钮开始你的第一首歌吧～';

  // ── 录音边界异常 ──
  static const String tooShortTitle = '再哼长一点点会更好哦';
  static const String tooShortContent = '才哼了一下下，要不要再试试？按住按钮，哼满5秒就好～';
  static const String tooShortRetry = '再试一次';
  static const String noSoundTitle = '好像没听到你的声音';
  static const String noSoundContent = '换个安静的地方，对着手机轻轻哼出来吧～';
  static const String noSoundRetry = '我准备好了';
  static const String tooNoisyTitle = '风有点大，咱们找个安静角落？';
  static const String tooNoisyContent = '周围有点热闹，换个安静的地方，你的歌声会更清晰哦～';
  static const String tooNoisyRetry = '换个地方';
  static const String recordingDone = '哼唱完成，正在为你创作中...';
  static const String maxTimeReached = '已经哼了15秒啦，很棒！让我们听听看～';

  // ── 权限 ──
  static const String micPermissionHint = '需要麦克风才能听到你的歌声哦，去设置里打开吧～';
  static const String checkingMic = '正在检查麦克风权限...';
  static const String micGranted = '麦克风权限已就绪 ✓';
  static const String permissionDeniedForever = '你之前拒绝了该权限，现在去设置里打开吧～';
  static const String goToSettings = '去设置';
  static const String notNow = '先不用';

  // ── 风格种子（儿童易懂文案） ──
  static const String selectStyle = '选一种你喜欢的风格';
  static const String stylePreviewHint = '按住卡片试听3秒';
  static const String stylePreviewPlaying = '试听中…';
  // 兼容旧引用
  static const String previewHint = '按住卡片试听3秒';
  static const String previewPlaying = '试听中…';
  static const String modelFallback = '离线版已生成，联网可解锁更丰富版本～';
  static const String modelFallbackHint = '正在用简化引擎继续为你创作…';
  static const String styleMorningDew = '晨露';
  static const String styleMorningDewDesc = '像清晨露珠一样清澈的钢琴声';
  static const String styleMountainStream = '山溪';
  static const String styleMountainStreamDesc = '像山间小溪哗啦啦的流水声';
  static const String styleFrogDrum = '蛙鼓';
  static const String styleFrogDrumDesc = '像小青蛙在池塘边快乐打鼓';
  static const String styleRandom = '随机惊喜';
  static const String styleRandomDesc = '每次都不一样，像拆盲盒一样！';

  // ── AI 生成 ──
  static const String sprouting = '你的音乐正在发芽…';
  static const String sproutPhase1 = '种子破土中…';
  static const String sproutPhase2 = '嫩芽正在生长…';
  static const String sproutPhase3 = '叶片正在舒展…';
  static const String generationTimeout = '离线版已生成，联网可解锁更丰富版本～';
  static const String generationTimeoutHint = '正在用简化引擎继续为你创作…';
  static const String generationDone = '创作完成！来听听看吧～';
  static const String processing = '正在分析你的旋律…';
  static const String pitchAnalyzing = '听听音高…';
  static const String rhythmExtracting = '感受节奏…';
  static const String melodyMatching = '搭配旋律…';

  // ── 编辑器 ──
  static const String secondTrack = '第二段哼唱';
  static const String secondTrackHint = '再哼一段，让音乐更丰富～';
  static const String undo = '撤销';
  static const String reset = '重置';
  static const String resetConfirm = '确定要重置所有参数吗？';
  static const String savedAndShare = '保存并分享';
  static const String sendToParents = '发给爸妈';
  static const String shareToTree = '种到音乐树';
  static const String shareToTreeHint = '种下一棵音乐树，看着它慢慢长大～';
  static const String continueCreating = '继续创作';
  static const String musicTemp = '音乐温度';
  static const String musicSpeed = '速度';
  static const String instrumentMix = '乐器比重';
  static const String softWarm = '柔和';
  static const String intense = '热烈';
  static const String slow = '慢';
  static const String fast = '快';
  static const String pureVocal = '纯人声';
  static const String richInstrument = '丰富配器';

  // ── 存储与设备 ──
  static const String storageLowTitle = '手机空间快满了';
  static const String storageLowContent = '要不要清理一些旧文件？你的作品都好好地保存着呢～';
  static const String storageLowOk = '好的，知道了';
  static const String deviceLowMem = '检测到你的设备内存较小，已自动加载轻量版本～';
  static const String savedSuccess = '作品保存成功！';
  static const String jumpToPostOffice = '生成音乐明信片';
  static const String jumpToPostOfficeHint = '想做成明信片发给家人吗？';

  // ── 来电中断恢复 ──
  static const String callInterruptedTitle = '上次还没录完';
  static const String callInterruptedContent = '要接着上次的继续来吗？之前录的已经帮你保存好啦～';
  static const String callInterruptedResume = '接着来';
  static const String callInterruptedDiscard = '重新开始';

  // ── 通用鼓励 ──
  static const String greatJob = '太棒了！';
  static const String keepGoing = '继续加油～';
  static const String tryAgain = '没关系，再试一次吧！';
  static const String wonderful = '真好听！';
  static const String okGotIt = '好的～';
  static const String save = '保存作品';
  static const String share = '分享';
}
