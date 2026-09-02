import hilog from '@ohos.hilog';
import { EngineObserver, EngineStageEvent } from 'io.github.xesam.harmony.localasset.core';

/**
 * hilog domain。0x0000 是"未申请业务域"的通用取值，与本库不上报到任何具体
 * 业务域这一事实相符；接入方若有自己的 domain 规划，观测器本身不阻碍 ——
 * 换掉 sink 即可把消息导向任意通道。
 */
const DOMAIN = 0x0000;

/** 缺省 tag，与 Android `LoggingEngineObserver.DEFAULT_TAG` / iOS 的 log category 逐字一致。 */
const DEFAULT_TAG = 'LocalAssetObserver';

/**
 * hilog 的级别常量。**不直接 re-export `hilog.LogLevel`**：那是 SDK 枚举，
 * 把它塞进本模块的公开导出面等于让调用方（和测试）被迫依赖 `@ohos.hilog` 的类型，
 * 而本模块的其余部分刻意保持对平台类型的最小依赖。数值与 `hilog.LogLevel.DEBUG/WARN`
 * 一致（3 / 5，已核对 SDK @ohos.hilog.d.ts:227/251）。
 */
export const LOG_LEVEL_DEBUG = 3;
export const LOG_LEVEL_WARN = 5;

/**
 * 日志落地通道。抽出这个函数类型有两个作用：
 *
 * 1. **可测**：hilog 写进系统日志缓冲区，宿主侧单测读不回来。注入 sink 后，
 *    "拼成什么字符串、用什么级别"这些真正会出错的部分就能被断言 ——
 *    对齐 iOS `LoggingEngineObserver.init(sink:)` 与 Android 构造函数里的
 *    `logger: (level, tag, message) -> Unit` 参数，三端同一手法。
 * 2. **可改道**：接入方想把管线轨迹送到自己的埋点/文件，换 sink 即可，
 *    不必重写一个 EngineObserver。
 */
export type LogSink = (level: number, tag: string, message: string) => void;

/**
 * design.md §8：把管线每个阶段落到 hilog —— adapter parse、两次 policy、
 * 链上每个 resolver 的 skip/hit/failure、load、终态，开发期 `hdc hilog` 一眼看全决策链。
 *
 * 接法：`new LocalAssetBuilder().setObserver(new LoggingEngineObserver())`。
 *
 * ⚠️ **不要把它当作唯一的可观测通道**：hilog 在 release 构建 / 默认级别过滤下常被丢弃。
 * 需要把失败上报到崩溃平台或埋点时，用 `SchemeRequestHandler` 的 `onFailure` 回调 ——
 * 那条回调只在终态失败时触发，且不受日志级别影响。两者分工与 Android
 * （`WebViewAssetInterceptor.onFailure` vs 本观测器）、iOS（同名两者）一致。
 *
 * 与 Android 的一处形态差异：Android 的 resolver 段会打 resolver 的 `javaClass.simpleName`，
 * 本实现打的是决策 kind（`resolver[1]=hit`）。原因在 core `EngineStageEvent` 的注释里：
 * ArkTS 拿不到稳定的运行时类名，故 `EngineStageEvent` 根本不带 `resolver` 字段，
 * resolverIndex + kind 已足以定位是链上第几个 resolver、它做了什么决策。
 */
export class LoggingEngineObserver implements EngineObserver {
  private readonly tag: string;
  private readonly sink: LogSink;

  constructor(tag: string = DEFAULT_TAG, sink: LogSink = defaultSink) {
    this.tag = tag;
    this.sink = sink;
  }

  onStage(event: EngineStageEvent): void {
    const message = formatStageEvent(event);
    const level = event.failure === null ? LOG_LEVEL_DEBUG : LOG_LEVEL_WARN;
    // 观测器是旁路：sink 抛异常绝不能把一次正常的资源请求变成失败。
    // 对齐 Android 的 `runCatching { logger(...) }`。
    try {
      this.sink(level, this.tag, message);
    } catch (error) {
      // 故意吞掉：日志通道本身故障时，除了不打这条日志之外无事可做。
    }
  }
}

/**
 * 按字段存在性拼接，缺席的字段整段省略（而不是输出 `ns=-` 这类占位）——
 * 与 Android 的 `buildList { ... ?.let { add(...) } }` / iOS 的 `if let` 链同构。
 * 段间用单空格分隔，`stage=` 恒为第一段。
 */
function formatStageEvent(event: EngineStageEvent): string {
  const parts: string[] = ['stage=' + event.stage];
  if (event.request !== null) {
    parts.push('ns=' + event.request.namespace);
  }
  if (event.resolverIndex !== null) {
    const kind = event.resolverResult === null ? '-' : event.resolverResult.kind;
    parts.push('resolver[' + event.resolverIndex.toString() + ']=' + kind);
  }
  if (event.descriptor !== null) {
    parts.push('descriptor=' + event.descriptor.id);
  }
  if (event.failure !== null) {
    // stage 为 null 时补 '-'：`failure[CAT/null]` 读起来像个真实阶段名，容易误导。
    parts.push(
      'failure[' + event.failure.category + '/' + (event.failure.stage ?? '-') + '] ' +
      event.failure.reason,
    );
  }
  return parts.join(' ');
}

/**
 * 缺省 sink：直连 hilog。消息整体作为一个 `%{public}s` 参数传入，而不是把
 * 拼好的字符串当 format —— 消息里若含 `%`（资源路径里完全可能有），
 * 直接当 format 会被 hilog 误当作占位符解析。
 */
function defaultSink(level: number, tag: string, message: string): void {
  if (level >= LOG_LEVEL_WARN) {
    hilog.warn(DOMAIN, tag, '%{public}s', message);
    return;
  }
  hilog.debug(DOMAIN, tag, '%{public}s', message);
}
