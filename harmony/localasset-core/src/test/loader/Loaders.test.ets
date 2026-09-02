import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import { BytesResourceLoader } from '../../main/ets/loader/BytesResourceLoader';
import { FileResourceLoader } from '../../main/ets/loader/FileResourceLoader';
import { CompositeResourceLoader } from '../../main/ets/loader/CompositeResourceLoader';
import {
  ResourceType,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';

const TMP_FILE = '/tmp/localasset-loader-probe.txt';

export default function loadersTest() {
  describe('loadersTest', () => {
    it('BytesResourceLoader returns the bytes as-is', 0, () => {
      const loader = new BytesResourceLoader();
      const descriptor = createResourceDescriptor({
        id: 'a',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1, 2, 3])),
        mimeType: 'image/png',
        createdAtMillis: 0,
      });
      expect(loader.canLoad(descriptor.source)).assertTrue();
      const data = loader.load(descriptor);
      expect(data.bytes.length).assertEqual(3);
      expect(data.mimeType).assertEqual('image/png');
    });

    it('BytesResourceLoader declines filePath sources', 0, () => {
      const loader = new BytesResourceLoader();
      expect(loader.canLoad(filePathSource('/tmp/x'))).assertFalse();
    });

    it('FileResourceLoader reads a real file', 0, () => {
      const file = fs.openSync(TMP_FILE, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'hello');
      fs.closeSync(file);

      const loader = new FileResourceLoader();
      const descriptor = createResourceDescriptor({
        id: 'a',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: filePathSource(TMP_FILE),
        mimeType: 'text/plain',
        createdAtMillis: 0,
      });
      const data = loader.load(descriptor);
      expect(data.bytes.length).assertEqual(5);
      expect(data.mimeType).assertEqual('text/plain');
    });

    it('FileResourceLoader raises LOAD_ERROR for a missing file', 0, () => {
      const loader = new FileResourceLoader();
      const descriptor = createResourceDescriptor({
        id: 'a',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: filePathSource('/tmp/localasset-definitely-missing.bin'),
        createdAtMillis: 0,
      });
      let caught: ResourceException | null = null;
      try {
        loader.load(descriptor);
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.LOAD_ERROR);
      expect((caught as ResourceException).message).assertEqual('file source is not readable');
    });

    it('CompositeResourceLoader dispatches by source kind', 0, () => {
      const loader = new CompositeResourceLoader([new BytesResourceLoader(), new FileResourceLoader()]);
      const descriptor = createResourceDescriptor({
        id: 'a',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([7, 7])),
        createdAtMillis: 0,
      });
      expect(loader.load(descriptor).bytes.length).assertEqual(2);
    });

    it('CompositeResourceLoader raises LOAD_ERROR when nothing can load', 0, () => {
      const loader = new CompositeResourceLoader([new FileResourceLoader()]);
      const descriptor = createResourceDescriptor({
        id: 'a',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      });
      let caught: ResourceException | null = null;
      try {
        loader.load(descriptor);
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.LOAD_ERROR);
      // 只断言 category 是不够的：若 Composite 无视 canLoad、直接把 descriptor 丢给
      // 第一个 loader，FileResourceLoader 也会抛 LOAD_ERROR('unsupported source type')，
      // 那条断言照样通过。所以必须断言消息来自 Composite 自己的「没有 loader」分支。
      // （已实测：去掉 canLoad 判断后，仅凭 category 断言本用例仍为绿。）
      expect((caught as ResourceException).message).assertEqual(
        'no loader for source type bytes (1 typed loader(s) checked)',
      );
    });
  });
}
