import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import {
  LocalAssetBuilder,
  createResolveContext,
  EngineResult,
  ResourceErrorCategory,
} from 'io.github.xesam.harmony.localasset.core';
import {
  errorProbeUrl,
  ErrorProbeResolver,
  PARSE_PROBE_URL,
  RESOLUTION_PROBE_URL,
  LOAD_PROBE_URL,
  SECURITY_PROBE_URL,
} from '../../main/ets/common/ErrorProbes';

/**
 * 场景 5（compatibility.md §13.5）的两组断言。
 *
 * ## 1. 四条探针 URL 的**跨端 fixture 契约**
 *
 * 断言的是逐字相等，不是"形状差不多"：
 * `docs/compatibility-fixtures/android-sample-flows.json` 的
 * `sample-error-categories-flow.input.cases` 把这四条 URL 一字不差地写死了，
 * 三端 sample 共用同一份 fixture。改动其中任何一条都必须先改 fixture，
 * 否则跨平台一致性断言会在别处失效 —— 而"别处"通常不会当场变红。
 *
 * ## 2. 每条探针**经完整引擎**必须落到的 (category, stage)
 *
 * 这一组才是本文件的重点。只钉 URL 那一侧是不够的：URL 常量与
 * `ErrorProbeResolver` 的匹配条件曾经分居两处、互不相干，改掉 resolver 里的
 * namespace 字面量，URL 侧的断言照样全绿，而页面上 LOAD 那一行会静默退化成
 * `RESOLUTION_ERROR @ resolve`（谁都不认领了）—— 正是 §13.5 存在的意义所要防的
 * 「类别错得悄无声息」。
 *
 * 现在两侧同源（都在 `ErrorProbes.ets` 里由 `LOAD_PROBE_HOST` / `LOAD_PROBE_PATH`
 * 派生），且下面的用例用**共享常量**驱动一个真实引擎，把 (category, stage)
 * 二元组直接断言掉。改坏任一侧，这些用例立刻变红。
 *
 * 引擎一律经 `new LocalAssetBuilder()....build()` 构造 —— 固定链序
 * （HandleRegistryResolver 永远第一、RegistryResolver 永远兜底）是安全属性，
 * 不接受配置，测试也不该绕过它。
 */

/** 允许的文件根。真实路径，但**其下的探针文件从不创建** —— 那正是 LOAD_ERROR 的来源。 */
const TMP_ROOT = '/tmp/localasset-errorprobes';
const MISSING_FILE = TMP_ROOT + '/never-created.bin';

/** 与 ErrorCategoriesPage 用的是同一个值；scope 判据依赖它。 */
const ENGINE_SCOPE = 'demo-engine';

/** 复刻 ErrorCategoriesPage.createErrorAsset 的配置，逐项对应。 */
function buildProbeEngine() {
  return new LocalAssetBuilder()
    .addResolver(new ErrorProbeResolver(MISSING_FILE))
    // 少了这行，LOAD 那条会提前变成 SECURITY_ERROR @ policy_post。
    .addAllowedFileRoot(TMP_ROOT)
    .build()
    .engine;
}

function resolveProbe(url: string): EngineResult {
  return buildProbeEngine().resolveUrl(url, createResolveContext({ engineScope: ENGINE_SCOPE }));
}

/** 断言一条探针落在预期的 (category, stage) 上，并把失败信息说清楚。 */
function assertFailure(
  result: EngineResult,
  category: ResourceErrorCategory,
  stage: string,
): void {
  // 成功即演示失真（页面上会显示 "OK" 哨兵），单独断言一次让失败信息更直白。
  expect(result.kind).assertEqual('failure');
  if (result.kind === 'failure') {
    expect(String(result.category)).assertEqual(String(category));
    expect(result.stage).assertEqual(stage);
  }
}

export default function errorProbesTest() {
  describe('ErrorProbes', () => {
    it('parse probe is a host-less URL so the adapter rejects it', 0, () => {
      // 无 host → DefaultLocalAssetSchemeAdapter 抛 'missing namespace'
      // → PARSE_ERROR @ adapter_parse。
      expect(PARSE_PROBE_URL).assertEqual('local-asset://');
      expect(errorProbeUrl('parse')).assertEqual('local-asset://');
    });

    it('resolution probe targets a host no resolver claims', 0, () => {
      expect(RESOLUTION_PROBE_URL).assertEqual('local-asset://nobody.demo.local/x');
      expect(errorProbeUrl('resolution')).assertEqual('local-asset://nobody.demo.local/x');
    });

    it('load probe targets the errorcat host the file-source resolver claims', 0, () => {
      // 这条必须被 resolver 命中并给出一条**允许根之下**的 filePath，
      // 才能过 postCheck 而栽在 loader 上（LOAD_ERROR @ load）。
      // 忘了 addAllowedFileRoot 时它会提前变成 SECURITY_ERROR @ policy_post。
      expect(LOAD_PROBE_URL).assertEqual('local-asset://errorcat.demo.local/load-boom');
      expect(errorProbeUrl('load')).assertEqual('local-asset://errorcat.demo.local/load-boom');
    });

    it('security probe reuses the same mismatch URL as the §13.4 flow', 0, () => {
      expect(SECURITY_PROBE_URL).assertEqual('local-asset://security.demo.local/engine-mismatch');
      expect(errorProbeUrl('security')).assertEqual('local-asset://security.demo.local/engine-mismatch');
    });

    it('the four probes are pairwise distinct', 0, () => {
      // 复制粘贴时最容易犯的错：两格填了同一条 URL。那样表格里会有两行显示同一个
      // (category, stage)，看着"都填上了"，实际少证明了一类错误。
      const urls: string[] = [
        PARSE_PROBE_URL,
        RESOLUTION_PROBE_URL,
        LOAD_PROBE_URL,
        SECURITY_PROBE_URL,
      ];
      const unique = new Set<string>(urls);
      expect(unique.size).assertEqual(4);
    });

    it('unknown kinds return null so the bridge can silently ignore them', 0, () => {
      // 对齐 Android ErrorCategoriesActivity.trigger 的 `else -> return`。
      expect(errorProbeUrl('nope')).assertNull();
      expect(errorProbeUrl('')).assertNull();
      // 大小写敏感：HTML 的 data-kind 是小写，桥不做归一化。
      expect(errorProbeUrl('PARSE')).assertNull();
    });

    // ---- 端到端：探针 URL × ErrorProbeResolver × 完整引擎 ----------------------

    it('PARSE probe lands on PARSE_ERROR at adapter_parse', 0, () => {
      assertFailure(
        resolveProbe(PARSE_PROBE_URL),
        ResourceErrorCategory.PARSE_ERROR,
        'adapter_parse',
      );
    });

    it('RESOLUTION probe lands on RESOLUTION_ERROR at resolve', 0, () => {
      // ErrorProbeResolver Skip + RegistryResolver 查不到 id 'x' → 链尽 → resource not found。
      assertFailure(
        resolveProbe(RESOLUTION_PROBE_URL),
        ResourceErrorCategory.RESOLUTION_ERROR,
        'resolve',
      );
    });

    it('LOAD probe lands on LOAD_ERROR at load, not SECURITY_ERROR at policy_post', 0, () => {
      // **本文件里最重要的一条。** 它同时钉住三件事：
      //  1. ErrorProbeResolver 认领的 host/path 与 LOAD_PROBE_URL 一致（否则退化成 RESOLUTION_ERROR）；
      //  2. descriptor 的 filePath 落在 allowed root 之下（否则是 SECURITY_ERROR @ policy_post）；
      //  3. 那个文件确实不存在（否则整条探针成功，页面显示 "OK" 哨兵）。
      // 三者任一被改坏，页面上都仍然"红一片"，肉眼看不出区别 —— 只有 stage 能分辨。
      expect(fs.accessSync(MISSING_FILE)).assertFalse();
      assertFailure(
        resolveProbe(LOAD_PROBE_URL),
        ResourceErrorCategory.LOAD_ERROR,
        'load',
      );
    });

    it('LOAD probe degrades to SECURITY_ERROR when the file root is not allowed', 0, () => {
      // 反证上一条的第 2 点：拿掉 addAllowedFileRoot，同一条 URL、同一个 resolver，
      // 失败点前移到 postCheck。这正是 §13.5 注释里反复告警的那个静默错误的样子 ——
      // 把它固化成断言，就不必只靠注释提醒后来者了。
      const engine = new LocalAssetBuilder()
        .addResolver(new ErrorProbeResolver(MISSING_FILE))
        .build()
        .engine;
      assertFailure(
        engine.resolveUrl(LOAD_PROBE_URL, createResolveContext({ engineScope: ENGINE_SCOPE })),
        ResourceErrorCategory.SECURITY_ERROR,
        'policy_post',
      );
    });

    it('SECURITY probe lands on SECURITY_ERROR at policy_post', 0, () => {
      assertFailure(
        resolveProbe(SECURITY_PROBE_URL),
        ResourceErrorCategory.SECURITY_ERROR,
        'policy_post',
      );
    });

    it('SECURITY probe would pass if the engine scope matched the descriptor namespace', 0, () => {
      // 反证：唯一变量是 engineScope。换成 descriptor 的 namespace（'other-engine'）后
      // 同一条 URL 顺利通过 postCheck 并加载成功 —— 证明被拒的原因确实是 scope 判据，
      // 而不是"这条资源压根没注册上"。
      const result = buildProbeEngine().resolveUrl(
        SECURITY_PROBE_URL,
        createResolveContext({ engineScope: 'other-engine' }),
      );
      expect(result.kind).assertEqual('success');
    });

    it('the four probes land on four distinct stages', 0, () => {
      // 四类错误各自停在自己的阶段 —— §13.5 的整句主张，一条断言收口。
      const stages = new Set<string>();
      const urls: string[] = [
        PARSE_PROBE_URL,
        RESOLUTION_PROBE_URL,
        LOAD_PROBE_URL,
        SECURITY_PROBE_URL,
      ];
      for (const url of urls) {
        const result = resolveProbe(url);
        if (result.kind === 'failure' && result.stage !== null) {
          stages.add(result.stage);
        }
      }
      expect(stages.size).assertEqual(4);
    });
  });
}
