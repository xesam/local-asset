import { ResourceData } from '../model/ResourceData';
import { ResourceDescriptor } from '../model/ResourceDescriptor';

/**
 * design.md §3 第 5 步：把 descriptor.source 变成实际字节。
 *
 * 与 Kotlin 侧的差异（已核对参考实现）：Kotlin 的 `TypedResourceLoader` 拆成
 * `load()` + `loadTyped()` 两个方法，`load()` 有默认实现委派给 `loadTyped()`。
 * ArkTS 的 interface 没有默认方法实现，多一层委派只会让每个实现类多写一个转发
 * 方法而不带来任何收益，因此这里只保留单一的 `load()`。
 */
export interface ResourceLoader {
  load(descriptor: ResourceDescriptor): ResourceData;
}
