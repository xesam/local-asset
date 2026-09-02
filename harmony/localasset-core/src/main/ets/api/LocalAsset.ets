import { LocalAssetEngine } from './LocalAssetEngine';
import { Policy } from './Policy';
import { ResourceLoader } from './ResourceLoader';
import { ResourceRegistry } from './ResourceRegistry';
import { HandleRegistry } from './HandleRegistry';
import { SchemeAdapter } from './SchemeAdapter';
import { ResourceResolver } from './ResourceResolver';
import { EngineObserver } from './EngineObserver';
import { DefaultLocalAssetEngine } from '../engine/DefaultLocalAssetEngine';
import { DefaultLocalAssetSchemeAdapter } from '../engine/DefaultLocalAssetSchemeAdapter';
import { ResolverChain } from '../internal/ResolverChain';
import { DefaultPolicy } from '../policy/DefaultPolicy';
import { BytesResourceLoader } from '../loader/BytesResourceLoader';
import { FileResourceLoader } from '../loader/FileResourceLoader';
import { CompositeResourceLoader } from '../loader/CompositeResourceLoader';
import { InMemoryResourceRegistry } from '../registry/InMemoryResourceRegistry';
import { InMemoryHandleRegistry } from '../registry/InMemoryHandleRegistry';
import { HandleRegistryResolver } from '../resolver/HandleRegistryResolver';
import { RegistryResolver } from '../resolver/RegistryResolver';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceHandle, ResourceHandleRecord } from '../model/ResourceHandle';

/**
 * 公开门面：持有引擎与它背后的两个注册表，把最常用的注册/吊销动作收口成方法，
 * 免得调用方为了注册一条资源而自己去持有 registry 实例。
 *
 * **只能经 `LocalAssetBuilder.build()` 构造**：构造函数是 private 的，外部
 * `new LocalAsset(...)` 编译期即被拒（对齐 Kotlin 的 `class LocalAsset private constructor`）。
 * 这不只是风格 —— 它把"resolver 链序不可配置"从约定变成**受编译器强制**的属性：
 * 绕过 Builder 就无法拿到 LocalAsset，也就无法塞进一条自定义顺序的链。
 *
 * 与 Kotlin 的形态差异（ArkTS 限制，实测）：Kotlin 的 Builder 是**嵌套类**，因而天然
 * 能访问外层的 private constructor；ArkTS 的 private 严格按"仅本类声明内可见"执行，
 * 同文件的姊妹类 LocalAssetBuilder 也访问不到（实测报错：
 * `Constructor of class 'LocalAsset' is private and only accessible within the class declaration`）。
 * 故补一个类内 static 工厂 `createInternal` 作为唯一入口。它虽是 public，但
 * **不经 Index.ets 导出**，包外拿不到；名字里的 Internal 也标明它不属于公开 API。
 */
export class LocalAsset {
  readonly engine: LocalAssetEngine;
  private readonly registry: ResourceRegistry;
  private readonly handleRegistry: HandleRegistry;

  /**
   * 仅供 LocalAssetBuilder.build() 调用的内部工厂 —— 见类注释：ArkTS 的 private
   * 构造函数连同文件的姊妹类都挡，故用它开一道类内的口子。不导出，不属于公开 API。
   */
  static createInternal(
    engine: LocalAssetEngine,
    registry: ResourceRegistry,
    handleRegistry: HandleRegistry,
  ): LocalAsset {
    return new LocalAsset(engine, registry, handleRegistry);
  }

  private constructor(
    engine: LocalAssetEngine,
    registry: ResourceRegistry,
    handleRegistry: HandleRegistry,
  ) {
    this.engine = engine;
    this.registry = registry;
    this.handleRegistry = handleRegistry;
  }

  register(descriptor: ResourceDescriptor): void {
    this.registry.register(descriptor);
  }

  unregister(id: string): void {
    this.registry.remove(id);
  }

  registerHandle(handle: ResourceHandle): string {
    return this.handleRegistry.register(handle);
  }

  /** 未知或已过期时抛 ResourceException(RESOLUTION_ERROR) —— 能力凭证语义，见 HandleRegistry。 */
  resolveHandle(resourceUri: string): ResourceHandleRecord {
    return this.handleRegistry.resolve(resourceUri);
  }

  removeHandle(resourceUri: string): void {
    this.handleRegistry.remove(resourceUri);
  }

  cleanup(): void {
    this.registry.cleanup();
  }

  cleanupHandles(): void {
    this.handleRegistry.cleanup();
  }
}

/**
 * design.md §3.1：每个实例独立构建，不存在全局单例 —— 每个引擎实例配一个新的 Builder。
 *
 * **resolver 链顺序是安全属性，不是配置项**（design.md §3.4），本 Builder 刻意不提供
 * 任何重排入口，将来也不应提供：
 *   HandleRegistryResolver（永远第一）→ addResolver 的调用顺序 → RegistryResolver（永远兜底）。
 *
 * 为什么第一位不可让渡：Handle 路径是能力令牌模型，持有不透明 URI 即等于授权
 * （design.md §5.4）。若某个用户 resolver 能排到它前面，就能对一条 handle URI 抢先
 * 返回 Hit，把「凭证换资源」改写成「按 URL 猜资源」—— 凭证的不可伪造性当场作废。
 * 兜底位同理不可让渡：RegistryResolver 支撑 `LocalAsset.register`，被前置会让
 * 用户 resolver 再也拿不到「先于注册表」的机会，语义与两端不一致。
 * （对齐 Kotlin `LocalAsset.Builder.build()` 与 iOS 同名 builder。）
 *
 * 与 Kotlin Builder 的形态差异：Kotlin 用同名方法 `registry()`/`policy()`/`loader()`/
 * `observer()`，ArkTS 中属性名与方法名不能冲突，故一律改为 `setXxx`。行为一致。
 */
export class LocalAssetBuilder {
  private readonly adapters: SchemeAdapter[] = [];
  private readonly resolvers: ResourceResolver[] = [];
  private readonly allowedFileRoots: string[] = [];
  private readonly allowedNamespaces: string[] = [];
  private readonly allowedSchemes: string[] = [];
  private registry: ResourceRegistry | null = null;
  private handleRegistry: HandleRegistry | null = null;
  private policy: Policy | null = null;
  private loader: ResourceLoader | null = null;
  private observer: EngineObserver | null = null;

  addAdapter(adapter: SchemeAdapter): LocalAssetBuilder {
    this.adapters.push(adapter);
    return this;
  }

  /** 追加到链中**用户段**的末尾；无法借此挤到 HandleRegistryResolver 之前。 */
  addResolver(resolver: ResourceResolver): LocalAssetBuilder {
    this.resolvers.push(resolver);
    return this;
  }

  /**
   * 声明默认 DefaultPolicy 接受 `filePath` 资源的目录根。
   *
   * 默认 policy 是 fail-closed 的：一个根都不加时，任何 filePath descriptor 都会在
   * postCheck 被拒（'file source is outside allowed roots'）。
   * 仅在使用默认 policy 时生效 —— 一旦 `setPolicy` 注入了自定义 policy，本配置被忽略，
   * 请在自己的 Policy 里配置允许的根。
   */
  addAllowedFileRoot(root: string): LocalAssetBuilder {
    this.allowedFileRoots.push(root);
    return this;
  }

  /** addAllowedFileRoot 的批量版本。 */
  addAllowedFileRoots(roots: string[]): LocalAssetBuilder {
    for (const root of roots) {
      this.allowedFileRoots.push(root);
    }
    return this;
  }

  /**
   * 声明默认 policy 在 preCheck 放行的 namespace（design.md §5.2）。
   * 一个都不加时任何非空 namespace 均放行（fail-open 默认，保持既有行为）。
   * 注入自定义 policy 后被忽略。
   */
  addAllowedNamespace(namespace: string): LocalAssetBuilder {
    this.allowedNamespaces.push(namespace);
    return this;
  }

  /** addAllowedNamespace 的批量版本。 */
  addAllowedNamespaces(namespaces: string[]): LocalAssetBuilder {
    for (const namespace of namespaces) {
      this.allowedNamespaces.push(namespace);
    }
    return this;
  }

  /**
   * 声明默认 policy 在 preCheck 放行的 scheme（design.md §5.2）。
   * 一个都不加时任何非空 scheme 均放行。注入自定义 policy 后被忽略。
   */
  addAllowedScheme(scheme: string): LocalAssetBuilder {
    this.allowedSchemes.push(scheme);
    return this;
  }

  /** addAllowedScheme 的批量版本。 */
  addAllowedSchemes(schemes: string[]): LocalAssetBuilder {
    for (const scheme of schemes) {
      this.allowedSchemes.push(scheme);
    }
    return this;
  }

  setRegistry(registry: ResourceRegistry): LocalAssetBuilder {
    this.registry = registry;
    return this;
  }

  setHandleRegistry(handleRegistry: HandleRegistry): LocalAssetBuilder {
    this.handleRegistry = handleRegistry;
    return this;
  }

  setPolicy(policy: Policy): LocalAssetBuilder {
    this.policy = policy;
    return this;
  }

  setLoader(loader: ResourceLoader): LocalAssetBuilder {
    this.loader = loader;
    return this;
  }

  /**
   * 给默认引擎挂一个 EngineObserver，使流水线每一阶段（adapter parse、policy pre/post、
   * 每个 resolver 的决策、load、终态）都发出 EngineStageEvent —— design.md §8。
   */
  setObserver(observer: EngineObserver): LocalAssetBuilder {
    this.observer = observer;
    return this;
  }

  build(): LocalAsset {
    const resolvedRegistry: ResourceRegistry = this.registry ?? new InMemoryResourceRegistry();
    const resolvedHandleRegistry: HandleRegistry = this.handleRegistry ?? new InMemoryHandleRegistry();
    const resolvedAdapters: SchemeAdapter[] = this.adapters.length > 0
      ? this.adapters
      : [new DefaultLocalAssetSchemeAdapter()];

    // 固定链序，见类注释。这三段的先后不接受任何配置。
    const chainResolvers: ResourceResolver[] = [new HandleRegistryResolver(resolvedHandleRegistry)];
    for (const resolver of this.resolvers) {
      chainResolvers.push(resolver);
    }
    chainResolvers.push(new RegistryResolver(resolvedRegistry));

    const resolvedPolicy: Policy = this.policy ?? new DefaultPolicy({
      allowedFileRoots: this.allowedFileRoots,
      allowedNamespaces: this.allowedNamespaces,
      allowedSchemes: this.allowedSchemes,
    });
    // 与 Kotlin 的差异：那边默认还带一个 StreamResourceLoader；harmony 无 Stream 来源（`docs/design.md` §9.3）。
    const resolvedLoader: ResourceLoader = this.loader ?? new CompositeResourceLoader([
      new BytesResourceLoader(),
      new FileResourceLoader(),
    ]);

    const engine = new DefaultLocalAssetEngine({
      adapters: resolvedAdapters,
      resolverChain: new ResolverChain(chainResolvers),
      policy: resolvedPolicy,
      loader: resolvedLoader,
      observer: this.observer,
    });
    return LocalAsset.createInternal(engine, resolvedRegistry, resolvedHandleRegistry);
  }
}
