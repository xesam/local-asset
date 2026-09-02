import {
  ResourceRegistry,
  RegistryLookupResult,
  registryHit,
  registryMissing,
  registryExpired,
} from '../api/ResourceRegistry';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

/**
 * 对齐 Kotlin `InMemoryResourceRegistry`（ConcurrentHashMap + putIfAbsent）与
 * iOS 同名类（Dictionary + NSLock）。三处行为逐条核对过：
 *
 * 1. 重复 id 抛 RESOLUTION_ERROR，message 为 'duplicate resource id: <id>'（跨平台契约），
 *    且**不覆盖**已有条目 —— Kotlin 用 putIfAbsent、iOS 用 `guard items[id] == nil`，
 *    两端都是先判重再写入。
 * 2. 到期判据是闭区间 `createdAtMillis + ttlMillis <= now`（注意是 <= 不是 <），
 *    lookup 与 cleanup 用同一条判据；ttlMillis 为 null 表示永不过期。
 * 3. lookup 只报告状态，不做惰性驱逐（Kotlin/iOS 的 lookup 均不写 map），
 *    过期条目要靠 cleanup 才真正移除。
 *
 * 差异：Kotlin/iOS 都做了并发保护（ConcurrentHashMap / NSLock），本实现用裸 Map。
 * ArkTS 每个 Worker 是独立 VM，同一事件循环内不存在数据竞争，所以这里不需要锁。
 *
 * 但由此带来的不是「需要加锁」而是**静默隔离**：裸 Map 不是 sendable 对象，
 * 根本无法跨 Worker 按引用共享。在 UI 线程注册的 descriptor 在 Worker 里直接查不到
 * （lookup 返回 missing），重复 id 检查也不跨 VM —— 两侧可以各自注册同一个 id 而都不报错。
 * 加锁解决不了这个问题（本来就没有竞争），要跨 VM 共享得改用 sendable/共享对象或显式序列化。
 * 因此：一个 registry 实例只服务于创建它的那个 VM，engine 与 registry 必须同线程使用。
 */
export class InMemoryResourceRegistry implements ResourceRegistry {
  private readonly items: Map<string, ResourceDescriptor> = new Map<string, ResourceDescriptor>();
  private readonly nowProvider: () => number;

  constructor(nowProvider: () => number = () => Date.now()) {
    this.nowProvider = nowProvider;
  }

  register(descriptor: ResourceDescriptor): void {
    if (this.items.has(descriptor.id)) {
      throw new ResourceException(
        ResourceErrorCategory.RESOLUTION_ERROR,
        'duplicate resource id: ' + descriptor.id,
      );
    }
    this.items.set(descriptor.id, descriptor);
  }

  lookup(id: string): RegistryLookupResult {
    const descriptor = this.items.get(id);
    if (descriptor === undefined) {
      return registryMissing();
    }
    const ttlMillis = descriptor.ttlMillis;
    if (ttlMillis === null) {
      return registryHit(descriptor);
    }
    if (descriptor.createdAtMillis + ttlMillis <= this.nowProvider()) {
      return registryExpired();
    }
    return registryHit(descriptor);
  }

  remove(id: string): void {
    this.items.delete(id);
  }

  cleanup(nowMillis: number = Date.now()): void {
    // 先收集再删除：遍历中直接 delete 会改动正在迭代的 Map。
    const doomed: string[] = [];
    this.items.forEach((descriptor: ResourceDescriptor, key: string) => {
      const ttlMillis = descriptor.ttlMillis;
      if (ttlMillis !== null && descriptor.createdAtMillis + ttlMillis <= nowMillis) {
        doomed.push(key);
      }
    });
    for (const key of doomed) {
      this.items.delete(key);
    }
  }
}
