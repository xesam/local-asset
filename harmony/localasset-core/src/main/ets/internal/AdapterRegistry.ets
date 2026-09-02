import { SchemeAdapter } from '../api/SchemeAdapter';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

/**
 * 对齐 Kotlin `AdapterRegistry.select`：取第一个 canHandle 为真的 adapter，
 * 无匹配则抛 PARSE_ERROR('no adapter can handle url')。message 是跨平台契约。
 */
export class AdapterRegistry {
  private readonly adapters: SchemeAdapter[];

  constructor(adapters: SchemeAdapter[]) {
    this.adapters = adapters;
  }

  select(url: string): SchemeAdapter {
    for (const adapter of this.adapters) {
      if (adapter.canHandle(url)) {
        return adapter;
      }
    }
    throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'no adapter can handle url');
  }
}
