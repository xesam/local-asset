import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import {
  normalizePathPrefix,
  matchesPrefix,
  guessMimeType,
  extractRelativePath,
  BaseDirectoryResolver,
  RawfileDirectoryResolver,
  RawfileDirectoryResolverOptions,
  FileDirectoryResolver,
  FileDirectoryResolverOptions,
} from '../../../Index';
import {
  AssetRequest,
  createAssetRequest,
  createResolveContext,
  ResourceSource,
  ResourceType,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 本文件与 SchemeRequestHandler.test.ets 一样兼任 **barrel 守卫**：上方从
 * `../../../Index` 具名导入的每个符号，只要 Index.ets 漏导或拼错，编译期就会在这条
 * import 语句上报 `has no exported member`，与它后续是否被使用无关。
 */

const TMP_ROOT = '/tmp/localasset-dirres';

function request(namespace: string, path: string): AssetRequest {
  return createAssetRequest({
    scheme: 'local-asset',
    namespace: namespace,
    identifier: 'x',
    path: path,
  });
}

function ensureTmpRoot(): void {
  // mkdirSync 对已存在的目录会抛 EEXIST；accessSync 返回 boolean 且不抛，先探再建。
  if (!fs.accessSync(TMP_ROOT)) {
    fs.mkdirSync(TMP_ROOT, true);
  }
}

function writeFile(path: string, content: string): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, content);
  fs.closeSync(file);
}

/**
 * 把 protected 的 resolveSource 暴露出来，好让「根包含校验」这道纵深防御可被直接验证。
 * 走 resolve() 是够不到它的：extractRelativePath 已经拒掉了所有 `..` 段，
 * 于是 root + '/' + relative 恒落在根下，包含校验在正常路径上永不为假。
 * 少了这条探针，把包含校验整段删掉不会让任何用例变红。
 */
class ProbeFileDirectoryResolver extends FileDirectoryResolver {
  probe(relativePath: string): ResourceSource | null {
    return this.resolveSource(relativePath);
  }
}

export default function directoryResolversTest() {
  describe('directoryResolversTest', () => {
    it('normalizes path prefixes', 0, () => {
      expect(normalizePathPrefix('static')).assertEqual('/static');
      expect(normalizePathPrefix('/static')).assertEqual('/static');
      expect(normalizePathPrefix('/static/')).assertEqual('/static');
      expect(normalizePathPrefix('/')).assertEqual('');
    });

    /**
     * 第三条断言是承重的：裸 startsWith 会把 /static-evil 判成 /static 之下，
     * 兄弟目录就能借前缀同形逃出映射范围（与 DefaultPolicy 文件根门禁同一类缺陷）。
     */
    it('matches only the prefix or a path under it', 0, () => {
      expect(matchesPrefix('/static', '/static')).assertTrue();
      expect(matchesPrefix('/static/a.css', '/static')).assertTrue();
      expect(matchesPrefix('/static-evil/a.css', '/static')).assertFalse();
      expect(matchesPrefix('/other/a.css', '/static')).assertFalse();
    });

    it('guesses mime types from the extension', 0, () => {
      expect(guessMimeType('a.css')).assertEqual('text/css');
      expect(guessMimeType('a.js')).assertEqual('text/javascript');
      expect(guessMimeType('a.png')).assertEqual('image/png');
      expect(guessMimeType('a.svg')).assertEqual('image/svg+xml');
      expect(guessMimeType('a.json')).assertEqual('application/json');
      expect(guessMimeType('a.html')).assertEqual('text/html');
      expect(guessMimeType('noextension')).assertNull();
      expect(guessMimeType('a.unknownext')).assertNull();
    });

    /** 扩展名比对必须大小写无关，且末位裸点（'a.'）不算扩展名。 */
    it('guesses mime types case-insensitively', 0, () => {
      expect(guessMimeType('A.CSS')).assertEqual('text/css');
      expect(guessMimeType('logo.PNG')).assertEqual('image/png');
      expect(guessMimeType('trailingdot.')).assertNull();
    });

    it('extracts the relative path and rejects traversal', 0, () => {
      expect(extractRelativePath('/static/css/a.css', '/static')).assertEqual('css/a.css');
      expect(extractRelativePath('/static', '/static')).assertNull();
      expect(extractRelativePath('/static/../secret', '/static')).assertNull();
    });

    /**
     * `..` 只在**整段**相等时才算穿越：`..hidden` / `a..b` 是合法文件名，
     * 一个写成 `relative.includes('..')` 的实现会把它们一并拒掉。
     * 同时钉住尾部 `..` 与根前缀（''）两种形态。
     */
    it('rejects only whole .. segments, at any position', 0, () => {
      expect(extractRelativePath('/static/a/../b.css', '/static')).assertNull();
      expect(extractRelativePath('/static/a/..', '/static')).assertNull();
      expect(extractRelativePath('/static/..hidden.css', '/static')).assertEqual('..hidden.css');
      expect(extractRelativePath('/static/a..b.css', '/static')).assertEqual('a..b.css');
      expect(extractRelativePath('/a.css', '')).assertEqual('a.css');
    });

    it('RawfileDirectoryResolver hits an existing rawfile', 0, () => {
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: 'demo/static',
        readRawfile: (path: string) => {
          return path === 'demo/static/a.css' ? new Uint8Array([1, 2]) : null;
        },
      });
      const result = resolver.resolve(request('assets.demo.local', '/static/a.css'), createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('assets.demo.local:/static/a.css');
        expect(result.descriptor.namespace).assertEqual('assets.demo.local');
        expect(result.descriptor.type).assertEqual(ResourceType.STATIC);
        expect(result.descriptor.mimeType).assertEqual('text/css');
        expect(result.descriptor.scope).assertNull();
        expect(result.descriptor.ttlMillis).assertNull();
        expect(result.descriptor.source.kind).assertEqual('bytes');
        if (result.descriptor.source.kind === 'bytes') {
          expect(result.descriptor.source.value.length).assertEqual(2);
          expect(result.descriptor.source.value[0]).assertEqual(1);
          expect(result.descriptor.source.value[1]).assertEqual(2);
        }
      }
    });

    /**
     * rawfileDirectory 必须真的拼进查询路径：替身只认带前缀的完整路径，
     * 一个忽略 rawfileDirectory 的实现会拿 'a.css' 去查，于是 Skip 而非 Hit。
     * 这条与上一条共同钉死拼接规则；同时验证前后斜杠被裁掉（不会拼出 '//'）。
     */
    it('RawfileDirectoryResolver trims slashes around the rawfile directory', 0, () => {
      const seen: string[] = [];
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: '/demo/static/',
        readRawfile: (path: string) => {
          seen.push(path);
          return path === 'demo/static/a.css' ? new Uint8Array([7]) : null;
        },
      });
      const result = resolver.resolve(request('assets.demo.local', '/static/a.css'), createResolveContext());
      expect(result.kind).assertEqual('hit');
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual('demo/static/a.css');
    });

    /** 省略 rawfileDirectory 时按 rawfile 根查询，relativePath 原样传下去（不带前导斜杠）。 */
    it('RawfileDirectoryResolver queries the rawfile root when no directory is given', 0, () => {
      const seen: string[] = [];
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        readRawfile: (path: string) => {
          seen.push(path);
          return new Uint8Array([1]);
        },
      });
      expect(resolver.resolve(request('assets.demo.local', '/static/css/a.css'), createResolveContext()).kind)
        .assertEqual('hit');
      expect(seen[0]).assertEqual('css/a.css');
    });

    it('RawfileDirectoryResolver skips a missing rawfile', 0, () => {
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: 'demo/static',
        readRawfile: (path: string) => null,
      });
      const result = resolver.resolve(request('assets.demo.local', '/static/missing.css'), createResolveContext());
      expect(result.kind).assertEqual('skip');
    });

    /**
     * 真机上 resourceManager 读不到 rawfile 是**抛异常**而非返回 null。
     * 必须收敛成 Skip，让失败停在 RESOLVE 阶段（跨端错误阶段语义一致）；
     * 不收敛的话异常会穿透 ResolverChain，变成另一个 category。
     */
    it('RawfileDirectoryResolver turns a throwing reader into a skip', 0, () => {
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        readRawfile: (path: string) => {
          throw new Error('resource not found');
        },
      });
      expect(resolver.resolve(request('assets.demo.local', '/static/a.css'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    it('RawfileDirectoryResolver skips other hosts and prefixes', 0, () => {
      const options: RawfileDirectoryResolverOptions = {
        host: 'assets.demo.local',
        pathPrefix: '/static',
        readRawfile: (path: string) => new Uint8Array([1]),
      };
      const resolver = new RawfileDirectoryResolver(options);
      expect(resolver.resolve(request('other.local', '/static/a.css'), createResolveContext()).kind)
        .assertEqual('skip');
      expect(resolver.resolve(request('assets.demo.local', '/elsewhere/a.css'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    /**
     * 前缀同形的兄弟目录必须 Skip —— 这是 matchesPrefix 的分隔符要求在 resolver
     * 层面的体现。替身对任何路径都返回字节，所以裸 startsWith 的实现会在这里 Hit。
     */
    it('RawfileDirectoryResolver skips a sibling directory sharing the prefix', 0, () => {
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        readRawfile: (path: string) => new Uint8Array([1]),
      });
      expect(resolver.resolve(request('assets.demo.local', '/static-evil/a.css'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    /** `..` 在任何 source 查询发生**之前**就被拒：替身一次都不该被调用。 */
    it('RawfileDirectoryResolver rejects traversal before touching the reader', 0, () => {
      const seen: string[] = [];
      const resolver = new RawfileDirectoryResolver({
        host: 'assets.demo.local',
        pathPrefix: '/static',
        rawfileDirectory: 'demo/static',
        readRawfile: (path: string) => {
          seen.push(path);
          return new Uint8Array([1]);
        },
      });
      expect(resolver.resolve(request('assets.demo.local', '/static/../secret.css'), createResolveContext()).kind)
        .assertEqual('skip');
      expect(seen.length).assertEqual(0);
    });

    it('FileDirectoryResolver hits a real file under the root', 0, () => {
      ensureTmpRoot();
      const filePath = TMP_ROOT + '/a.css';
      writeFile(filePath, 'body{}');

      const resolver = new FileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT,
      });
      const result = resolver.resolve(request('cdn.demo.local', '/pkg/a.css'), createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('cdn.demo.local:/pkg/a.css');
        expect(result.descriptor.type).assertEqual(ResourceType.STATIC);
        expect(result.descriptor.mimeType).assertEqual('text/css');
        expect(result.descriptor.source.kind).assertEqual('filePath');
        if (result.descriptor.source.kind === 'filePath') {
          expect(result.descriptor.source.value).assertEqual(filePath);
        }
      }
    });

    /** rootDirectory 带尾斜杠时不得拼出 '//'，否则产出的 filePath 与 policy 的根比对形态不一致。 */
    it('FileDirectoryResolver trims a trailing slash on the root', 0, () => {
      ensureTmpRoot();
      writeFile(TMP_ROOT + '/b.css', 'body{}');
      const resolver = new FileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT + '/',
      });
      const result = resolver.resolve(request('cdn.demo.local', '/pkg/b.css'), createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        // source.kind 单独断言：折进上面的 if 条件会让一个 kind 不对的实现
        // 静默跳过下面那条 value 断言，整条用例照绿。
        expect(result.descriptor.source.kind).assertEqual('filePath');
        if (result.descriptor.source.kind === 'filePath') {
          expect(result.descriptor.source.value).assertEqual(TMP_ROOT + '/b.css');
        }
      }
    });

    it('FileDirectoryResolver skips a missing file', 0, () => {
      const options: FileDirectoryResolverOptions = {
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT,
      };
      const resolver = new FileDirectoryResolver(options);
      expect(resolver.resolve(request('cdn.demo.local', '/pkg/nope.css'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    /** 目录是存在的，但不是可读的资源 —— accessSync 为真，必须再靠 statSync 判掉。 */
    it('FileDirectoryResolver skips a directory', 0, () => {
      ensureTmpRoot();
      const nested = TMP_ROOT + '/nested';
      if (!fs.accessSync(nested)) {
        fs.mkdirSync(nested, true);
      }
      const resolver = new FileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT,
      });
      expect(resolver.resolve(request('cdn.demo.local', '/pkg/nested'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    /**
     * **这是一条 belt-and-braces 的集成用例，没有独占的区分力 —— 别指望它单独变红。**
     *
     * 走完整 resolve() 路径，穿越会被**两道彼此独立**的门各自拦下，任一道成立它就绿：
     *   1. `extractRelativePath` 的整段 `..` 拒绝（先短路，正常情况下走的是这条）；
     *   2. `FileDirectoryResolver.resolveSource` 的 `isLexicallyWithin` 包含校验 ——
     *      折叠后 `/tmp/localasset-dirres/../../etc/passwd` → `/etc/passwd`，不在根下。
     * 只删其中一道，另一道仍然拦得住，本用例照绿。变异表可印证：M2（删 `..` 拒绝）
     * 打红的是另外三条，M4/M5（打掉包含校验）打红的是下面那条探针用例，
     * **没有任何单点变异能杀死这一条**。
     *
     * 它的价值在于证明两层**组合**起来在真实入口上确实闭合（`/etc/passwd` 在测试机上
     * 真实存在，accessSync 会为真，所以一旦两道门都失效它会立刻变红）。
     * 真正钉住各自行为的是：`..` 拒绝 → `rejects only whole .. segments, at any position`
     * 与 `RawfileDirectoryResolver rejects traversal before touching the reader`；
     * 包含校验 → 下面的 `refuses a relative path that escapes the root`。
     */
    it('FileDirectoryResolver refuses traversal out of the root', 0, () => {
      const resolver = new FileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT,
      });
      expect(resolver.resolve(request('cdn.demo.local', '/pkg/../../etc/passwd'), createResolveContext()).kind)
        .assertEqual('skip');
    });

    /**
     * 直接驱动 resolveSource，验证根包含校验本身。走 resolve() 够不到这条分支
     * （见 ProbeFileDirectoryResolver 的注释），只有这条用例能让它变红。
     *
     * 三条断言各司其职，缺一不可：
     *  1. 正常路径命中 —— 否则下面的 assertNull 可能只是探针根本不工作；
     *  2. **不过度拒绝**：`nested/../a.css` 折叠后是 `<root>/a.css`，仍在根内，必须放行。
     *     少了这条，一个"target 里出现 `..` 子串就拒"的过严实现能让全部用例变绿
     *     （已实测：移除本条断言后该变异 43/43 全绿，加回后精确打红本条）；
     *  3. 真正逃出根的路径必须拒。
     */
    it('FileDirectoryResolver refuses a relative path that escapes the root', 0, () => {
      ensureTmpRoot();
      const probe = new ProbeFileDirectoryResolver({
        host: 'cdn.demo.local',
        pathPrefix: '/pkg',
        rootDirectory: TMP_ROOT,
      });
      writeFile(TMP_ROOT + '/c.css', 'body{}');
      writeFile(TMP_ROOT + '/a.css', 'body{}');
      // nested/ 目录由 'skips a directory' 用例建出；这里自建一次，不依赖用例执行顺序。
      const nested = TMP_ROOT + '/nested';
      if (!fs.accessSync(nested)) {
        fs.mkdirSync(nested, true);
      }
      expect(probe.probe('c.css') !== null).assertTrue();
      // 内部 `..` 折叠后仍落在根内 —— 词法折叠必须放行，不能退化成"含 `..` 就拒"。
      expect(probe.probe('nested/../a.css') !== null).assertTrue();
      expect(probe.probe('../../etc/passwd')).assertNull();
    });

    /** BaseDirectoryResolver 是公开的扩展点：第三方 resolver 应能复用同一套路由骨架。 */
    it('BaseDirectoryResolver is extensible by third parties', 0, () => {
      class ConstantResolver extends BaseDirectoryResolver {
        protected resolveSource(relativePath: string): ResourceSource | null {
          return relativePath === 'a.txt' ? { kind: 'bytes', value: new Uint8Array([9]) } : null;
        }
      }
      const resolver = new ConstantResolver('demo.local', 'files');
      const hit = resolver.resolve(request('demo.local', '/files/a.txt'), createResolveContext());
      expect(hit.kind).assertEqual('hit');
      if (hit.kind === 'hit') {
        expect(hit.descriptor.mimeType).assertEqual('text/plain');
      }
      expect(resolver.resolve(request('demo.local', '/files/b.txt'), createResolveContext()).kind)
        .assertEqual('skip');
    });
  });
}
