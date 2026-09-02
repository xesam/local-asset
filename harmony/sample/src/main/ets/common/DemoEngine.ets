import common from '@ohos.app.ability.common';
import {
  LocalAsset,
  LocalAssetBuilder,
  InMemoryHandleRegistry,
  DefaultPolicy,
  ResourceScope,
  ResourceType,
  bytesSource,
  createResourceHandle,
  createResourceDescriptor,
} from 'io.github.xesam.harmony.localasset.core';
import {
  RawfileDirectoryResolver,
  FileDirectoryResolver,
} from 'io.github.xesam.harmony.localasset.webview';
import { readRawfileBytes, sandboxDir, copyRawfileDirToSandbox } from './SampleFiles';
import { BannerOverrideResolver, CHAIN_HOST, CHAIN_BASE_PREFIX } from './OverrideBanner';
import { ErrorProbeResolver } from './ErrorProbes';

export const LOGO_RAWFILE = 'demo/static/images/logo.svg';

/**
 * 统一的 engineScope。
 *
 * 合并前 security-models / error-categories 用 'demo-engine'，其余各用各的；现在统一。
 * security-models 演示的「作用域不匹配」靠 resolver 返回 `namespace = 'other-engine'`
 * 实现，与本值取什么无关，故统一不影响该场景。
 */
export const ENGINE_SCOPE = 'demo-engine';

/**
 * 演示引擎：8 条 sample flow 共用**一个** LocalAsset 实例。
 *
 * ## 为什么必须合并
 *
 * 演示的首页与页间跳转都在 Web 侧（`shared/demo/pages/index.html` 里的 `<a href>`），
 * 原生不再感知「当前是哪个场景」，也就没有任何时机去换引擎。八套配置必须一次装进同一个引擎。
 *
 * ## 合并为什么是安全的（逐条核实过）
 *
 * - **host 互不重叠**：assets. / cdn. / chain. / resilient. / security. / errorcat.demo.local
 *   各占一个命名空间，resolver 不命中即 Skip 落到下一条。
 * - **handleRegistry 只能有一个**（`setHandleRegistry` 是单值），而原先四个场景各配一个。
 *   `InMemoryHandleRegistry` 的 host 只影响 register() 生成的 URI 字面量，反查按完整 URI
 *   查表、不校验 host；那四个场景都是先 registerHandle() 拿 URI 再用，从不硬编码 host。
 * - **`/engine-mismatch` 被 security-models 与 error-categories 共用**，两者期望一致
 *   （都要 SECURITY_ERROR），字节内容不参与断言 —— postCheck 在 load 之前就拒了。
 *
 * 与 Android `DemoEngine.kt` / iOS `DemoEngine.swift` 一一对应。
 */
export class DemoEngine {
  readonly localAsset: LocalAsset;
  /** 已吊销的 handle URI —— graceful-degradation 用，必须在页面加载前备好。 */
  readonly revokedHandleUri: string;

  constructor(context: common.UIAbilityContext) {
    const logo: Uint8Array | null = readRawfileBytes(context, LOGO_RAWFILE);
    const logoBytes: Uint8Array = logo ?? new Uint8Array(0);

    // directory-routing 需要一个真实沙箱目录才能演示 FilePath 链路 —— rawfile 不是文件系统路径。
    const packageDirectory: string = sandboxDir(context, 'sample-pkg');
    copyRawfileDirToSandbox(context, 'demo/pkg', packageDirectory);

    // LOAD_ERROR 需要一条「在允许的根之下、但文件不存在」的路径：postCheck 的包含校验通过，
    // 随后 FileResourceLoader 才因读不到而失败 —— 这正是 LOAD_ERROR 与 SECURITY_ERROR 的分界。
    const cacheRoot: string = context.cacheDir;
    const missingFilePath: string = cacheRoot + '/missing-boom-bin';

    this.localAsset = new LocalAssetBuilder()
      .setHandleRegistry(new InMemoryHandleRegistry('handles.demo.local', '/handles'))
      // 默认 policy 对 filePath 是 fail-closed：不声明允许的根，一条都不放行。
      // 两个根都要：cacheDir 给 LOAD_ERROR 探针，sample-pkg 给目录路由。
      .setPolicy(new DefaultPolicy({ allowedFileRoots: [cacheRoot, packageDirectory] }))
      // 链首：resolver-chain 的覆盖 resolver。先加即先跑，Hit 即短路（design.md §3.4）。
      .addResolver(new BannerOverrideResolver())
      // security-models：走 **Registry 路径**（`register()`），不是自定义 resolver。
      // §13.4 要的正是 Registry 路径与 Handle 路径的对照，故保持这个实现。
      // 注册在 build() 之后，见下方。
      // error-categories（LOAD / SECURITY 两条探针）
      .addResolver(new ErrorProbeResolver(missingFilePath))
      // static-mapping
      .addResolver(new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: 'demo/static',
        readRawfile: (path: string) => readRawfileBytes(context, path),
      }))
      // resolver-chain 的兜底目录 resolver：仅在上面那条覆盖 resolver Skip 时才到达。
      .addResolver(new RawfileDirectoryResolver({
        host: CHAIN_HOST,
        pathPrefix: CHAIN_BASE_PREFIX,
        rawfileDirectory: 'demo/base',
        readRawfile: (path: string) => readRawfileBytes(context, path),
      }))
      // graceful-degradation
      .addResolver(new RawfileDirectoryResolver({
        host: 'resilient.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: 'demo/static',
        readRawfile: (path: string) => readRawfileBytes(context, path),
      }))
      // directory-routing
      .addResolver(new FileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: packageDirectory,
      }))
      .build();

    // security-models 走 **Registry 路径**：两条 descriptor 都是 scope = ENGINE，
    // 唯一差别是 namespace —— 一条等于 engineScope，一条不等。判据在
    // DefaultPolicy.postCheck，这里只负责如实注册。§13.4 要的正是这条路径与
    // Handle 路径（capability）的对照。
    //
    // RegistryResolver 按 request.identifier 反查，故 id 必须等于 URL 的末段
    // （'local-asset://security.demo.local/engine-matched' → identifier 'engine-matched'）。
    //
    // 注：`engine-mismatch` 也会被链中更靠前的 ErrorProbeResolver 命中（error-categories
    // 的 SECURITY 探针用同一条 URL）。两条路径的结论一致 —— 都是 SECURITY_ERROR @ policy_post
    // —— 故谁先命中不影响任一场景的断言。`engine-matched` 不在探针的匹配条件里，
    // 会如期落到这里的 Registry。
    this.localAsset.register(createResourceDescriptor({
      id: 'engine-matched',
      namespace: ENGINE_SCOPE,
      type: ResourceType.DYNAMIC,
      source: bytesSource(logoBytes),
      mimeType: 'image/svg+xml',
      createdAtMillis: Date.now(),
      scope: ResourceScope.ENGINE,
    }));

    // 注册后立刻吊销：页面请求这条 URI 会 404，用以演示失效的 capability 优雅降级。
    const uri: string = this.localAsset.registerHandle(createResourceHandle({
      source: bytesSource(logoBytes),
      fileName: 'logo.svg',
      mimeType: 'image/svg+xml',
    }));
    this.localAsset.removeHandle(uri);
    this.revokedHandleUri = uri;
  }
}
