import { ResourceLoader } from '../api/ResourceLoader';
import { TypedResourceLoader } from '../api/TypedResourceLoader';
import { ResourceData } from '../model/ResourceData';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

/**
 * 按注册顺序找第一个 canLoad 为 true 的 loader。
 *
 * 与 Kotlin 侧的差异：Kotlin 的构造参数是 `List<ResourceLoader>`，运行时用
 * `as? TypedResourceLoader` 过滤，因此错误消息里还会列出"未实现 TypedResourceLoader
 * 的 loader"。ArkTS 无法在运行时判定某对象是否满足某个 interface（interface 被擦除），
 * 所以这里把约束提到类型层：构造参数直接要求 TypedResourceLoader[]，
 * 不可能存在非 typed 成员，错误消息也就没有对应分支。
 */
export class CompositeResourceLoader implements ResourceLoader {
  private readonly loaders: TypedResourceLoader[];

  constructor(loaders: TypedResourceLoader[]) {
    this.loaders = loaders;
  }

  load(descriptor: ResourceDescriptor): ResourceData {
    for (const loader of this.loaders) {
      if (loader.canLoad(descriptor.source)) {
        return loader.load(descriptor);
      }
    }
    throw new ResourceException(
      ResourceErrorCategory.LOAD_ERROR,
      'no loader for source type ' + descriptor.source.kind +
        ' (' + this.loaders.length.toString() + ' typed loader(s) checked)',
    );
  }
}
