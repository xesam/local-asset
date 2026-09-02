import fs from '@ohos.file.fs';
import { TypedResourceLoader } from '../api/TypedResourceLoader';
import { ResourceData, bytesData } from '../model/ResourceData';
import { ResourceDescriptor, ResourceSource } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

/**
 * 与 Kotlin/iOS 的形态差异（有意，见 `docs/design.md` §9.3）：两端的 FileResourceLoader 返回
 * `ResourceData.Stream`——一个可重复 open 的流工厂，字节从不整体驻留内存。
 * harmony 的 ResourceData 只有 Bytes 一个变体（见 model/ResourceData.ets），
 * 所以这里做一次同步全量读，返回 ResourceData.Bytes。不要为此新增 Stream 变体。
 *
 * @ohos.file.fs 的两条实测行为（本任务中在该环境下实测，勿按 Node fs 的直觉改写）：
 * 1. `fs.accessSync(path)` 返回 boolean 且**不抛异常**，所以存在性判断必须取返回值，
 *    用 try/catch 包住它是无效的——路径不存在时它只是返回 false，catch 永远进不去。
 * 2. `fs.readTextSync` 在该环境下不可调用；statSync / openSync / readSync / closeSync 均可用。
 */
export class FileResourceLoader implements TypedResourceLoader {
  canLoad(source: ResourceSource): boolean {
    return source.kind === 'filePath';
  }

  load(descriptor: ResourceDescriptor): ResourceData {
    if (descriptor.source.kind !== 'filePath') {
      throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'unsupported source type');
    }
    const path = descriptor.source.value;
    // fs.accessSync 返回 boolean（不抛异常），不要用 try/catch 判存在性
    if (!fs.accessSync(path)) {
      throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'file source is not readable');
    }
    // file 在 try 外声明：openSync 之后的任何一步抛出（readSync 失败、ArrayBuffer 分配失败）
    // 都必须归还 fd，所以关闭动作放在 finally 里，而不是紧跟 readSync 之后。
    // 已实测（临时探针：在 openSync 后注入一次抛异常，连续 load 50 次，前后各开一个
    // 文件比较 fd 号）：关闭放在 readSync 之后时 fd 从 20 涨到 70——错误路径每次泄漏一个；
    // 放进 finally 后 fd 号前后一致。本仓的测试无一会因泄漏而变红，故此处只能靠代码结构保证。
    let file: fs.File | null = null;
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'file source is not readable');
      }
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const arrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, arrayBuffer);
      return bytesData(new Uint8Array(arrayBuffer), descriptor.mimeType);
    } catch (error) {
      if (error instanceof ResourceException) {
        throw error;
      }
      const message = (error as Error).message;
      throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'failed to read file source: ' + message);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }
}
