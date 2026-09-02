import { TypedResourceLoader } from '../api/TypedResourceLoader';
import { ResourceData, bytesData } from '../model/ResourceData';
import { ResourceDescriptor, ResourceSource } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

/**
 * 字节来源直通：不复制、不转换，原样交出 source.value（与 Kotlin 侧一致）。
 * 因此调用方拿到的 Uint8Array 与 descriptor 内的是同一个对象，改它等于改 descriptor。
 */
export class BytesResourceLoader implements TypedResourceLoader {
  canLoad(source: ResourceSource): boolean {
    return source.kind === 'bytes';
  }

  load(descriptor: ResourceDescriptor): ResourceData {
    if (descriptor.source.kind !== 'bytes') {
      throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'unsupported source type');
    }
    return bytesData(descriptor.source.value, descriptor.mimeType);
  }
}
