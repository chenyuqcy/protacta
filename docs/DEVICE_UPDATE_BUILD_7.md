# Build 7 iPhone update — 25 October 2026

**Installed, launched and independently process-verified; basic Dart entry observed.**
Protacta **0.1.0 (7)** replaced the independently observed Build 5 on the
iPhone 17 Pro Max, iOS 26.6.1, through a connected USB developer tunnel.
The first launch request was explicitly denied because the phone was locked.
After the user unlocked it, the launch request succeeded with activation and no
launch arguments; a separate query found the same app process, PID 5989.
The user then confirmed on the actual phone that **Paper & craft → Classic Dart
→ Practice the complete Dart** can be opened. This is basic navigation evidence;
camera accuracy, speech behavior, real-paper follow-through and learner outcomes
remain untested.

## Installed artifact and evidence

Runtime source commit: `739f2c01696750891441a8dc8a198df72eba80f7`.
Bundle ID: `org.realitycore.protacta.prototype`.
The existing signed Debug artifact was installed; no source change or new build
was needed for this update:

`output/DartVoiceCompletionDeviceDerivedData/Build/Products/Debug-iphoneos/Protacta.app`

Its strict signature verification passed, its executable matches the frozen
candidate, and its development profile includes the target phone. Executable
SHA-256: `fc6fd7da6df37a5da0142d7e90ea1357c359f5d744cd505717e8e62364f5a0dc`.

All paths below are under `output/device-install/build7-20261025/`.

| Gate | Actual result | Evidence |
| --- | --- | --- |
| Artifact preflight | Existing version 0.1.0/build 7 and signature verified | `update-preflight.json`; its installation-status field is an earlier pre-install snapshot |
| Initial wireless install | Failed: CoreDevice could not locate the unavailable device, error 1011 | `install.json`, `install-after-wireless-enable.json` and corresponding logs |
| First USB attempt | Failed before the tunnel was available, error 1011 | `install-usb.json`, `install-usb.log` |
| Connected USB path | `wired`, tunnel `connected`, developer mode enabled | `devices-usb-refreshed.json` |
| Prior phone version | Independent app query returned version 0.1.0/build 5 | `installed-app-usb-before.json` |
| Installation | Successful, correct bundle ID | `install-usb-connected.json`, `install-usb-connected.log` |
| Installed phone version | Separate app query returned version 0.1.0/`bundleVersion: 7` | `installed-app-after.json` |
| Initial launch | Failed: `FBSOpenApplicationErrorDomain` code 7, `Locked` | `launch.json`, `launch.log` |
| Initial lock state | `passcodeRequired: true`; snapshot before the successful unlock retry | `lock-state.json` |
| Launch after unlock | Successful; `activatedWhenStarted: true`, `arguments: []`, PID 5989 | `launch-after-unlock.json`, `launch-after-unlock.log` |
| Independent process query | Same PID 5989 and installed Protacta executable found in a later query | `running-process.json`, `running-process.log` |
| Basic course navigation | User confirmed Paper & craft → Classic Dart → complete Dart practice on the phone | User confirmation in this chat, 25 October 2026 |
| Remaining physical acceptance | Not executed | No completed paper, camera-accuracy, speech or learner record |

The failed attempts are retained. The successful USB installation does not prove
wireless installation now works. The process query establishes that process only
at the observed time, not indefinite stability. Basic course entry does not
establish real-paper or voice behavior. The prior 241 native and four
Simulator UI passes are local software evidence in [DART_VOICE_COMPLETION.md](DART_VOICE_COMPLETION.md).

## Matching practice paper

Use **PTC2 revision 2**, layout ID `protacta-dart-a4-ptc2`, introduced in Build 6.
The app, course and paper bytes are unchanged during this installation. A PTC1
sheet from Build 5 cannot establish alignment in Build 7.

Print [the bundled A4 PDF](../ios/PaperSteps/Resources/Protacta_Dart_Practice_A4.pdf)
on white A4 at **Actual Size / 100%**, with Fit to Page disabled. Keep all four
codes visible, both code rows nearest you, on a plain dark mat with even light.
PDF SHA-256: `eb9f9135f7abe67d7dc448e97080440384aa72aeef9c0d0759f04ec6b518a012`.

## 手机测试顺序 / Physical smoke-test order

**基本课程入口已由用户真机确认；以下其他功能仍待执行。** 安装、启动和
入口可用不能填写为相机、语音或真实跟做已通过。

1. **首页与入口 / Home and entry.** 用户已确认能进入 **Paper & craft → Classic
   Dart → Practice the complete Dart**。继续核对首页能看到
   **PAPER & CRAFT**、**EVERYDAY SKILLS** 和 **AERIS One**，记录黑屏、崩溃
   或卡住位置；其他课程／产品入口尚未逐项验收。
2. **生活技能 / Everyday skills.** 任选 T 恤、毛巾、平床单、方结或领带，试
   播放、暂停、慢放、Start/Target、Help、手动确认，再退出并回来检查对应课程
   的进度。它们是动画示意与手动对照，不提供衣物／绳结相机判断。
3. **第一折对齐 / Natural-paper guide.** 进入 **PAPER & CRAFT → Classic Dart →
   Guide on my paper**，用一张平整完整 A4，允许相机并确认标出的 TOP 朝向。
   缓慢移动、转动纸张，再遮挡／移出：记录提示是否跟随、失效是否隐藏，以及
   重新放平后是否要求正确的朝向确认。此模式只覆盖第一折平纸指导。
4. **完整课程 / Complete Dart.** 换用匹配的 PTC2 纸，进入 **Practice the
   complete Dart**，从 action 1 实际跟做到 action 10。测试 **Watch in 3D**、
   **I'm stuck**、**Previous action** 和 **Find sheet again**。只有本人确认按钮
   推进完成记录；动画、相机结果及语音 Next step 都不应替本人确认。
5. **固定检查 / Check my step.** 在 actions 2–6 的受支持平放状态测试清楚、
   故意不匹配和看不清的画面，记录实际返回。Action 2 外轮廓不能证明中心折痕；
   action 1 和 7–10 使用手动／3D 对照。可见轮廓匹配不代表隐藏纸层或整件作品正确。
6. **完成时停语音 / Voice completion.** 在 action 10 点 **Watch in 3D** 再返回，
   然后**重新开启 Hands-free**，再点 **I have finished · Save my progress**。
   切换模式本来就会停语音，漏掉重新开启便测不到完成边界。确认监听、朗读和
   麦克风指示停止；说 **Previous step / Restart lesson** 不应改动已完成进度。
   点 **Start again with a new practice sheet** 后应回 action 1，语音保持关闭，
   直到主动开启。另测试监听时打开 Setup／Help 会停止语音。
7. **中断恢复 / Interruption.** 在相机与语音使用期间切到后台再回来，确认旧
   叠加与旧检查不会直接恢复；按 **Find sheet again** 后重新对齐。生活技能在
   前台应保持亮屏，退出后恢复原系统锁屏设置。记录实际相机／权限／音频行为。
8. **产品说明 / AERIS.** 打开 **AERIS One**，试过滤器步骤的 **Press the highlighted
   tab**、重播、展开视图和 **View in AR**。确认虚拟零件交互与桌面模型能显示；
   这不能当成真实净化器自动对齐或维修正确性的验收。

用[真实跟做记录与试验说明](physical-review/README.md)记录观察、失败步骤和修正。
正常使用不保存相机照片；只有显式开启的 Debug 验证入口才可手动保存本地样本。
先完成真实课程审阅与独立相机样本，再进行约十人的探索性初学者比较。完整 MVP
仍未验收；云端 AI、其他类别的相机识别／自动对齐也未在此版本启用。
