import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import {
  copyTree,
  ensureDir,
  removeTree,
  writeBytes,
  toArrayBuffer,
  RawfileTreeReader,
} from '../../main/ets/common/SampleFiles';

/**
 * `SampleFiles` 里那段「rawfile 目录树 → 沙箱」的落地逻辑。
 *
 * 之所以能测：`copyTree` 收的是注入的 `RawfileTreeReader`，而不是 UIAbilityContext。
 * 与 `RawfileDirectoryResolver.readRawfile` 是同一手法、同一理由 —— 测试沙箱里
 * 没有 Context，注入之后这段递归/落盘逻辑才能被真正验证，而不是只被编译。
 *
 * 目标侧走的是真实文件系统（`/tmp` 下的临时根），因为 `copyTree` 的一半价值
 * 正在于 mkdir/write/rm 这几个 fs 调用的边界行为（EEXIST、非空目录删除）。
 */

const TMP_ROOT = '/tmp/localasset-samplefiles';

/** 用一张 Map 假扮 rawfile 树：key 是路径，value 是内容；目录不出现在 key 里。 */
function fakeReader(files: Map<string, string>): RawfileTreeReader {
  return {
    list: (dir: string): string[] => {
      const names = new Set<string>();
      const prefix = dir.length === 0 ? '' : dir + '/';
      files.forEach((value: string, path: string) => {
        if (!path.startsWith(prefix)) {
          return;
        }
        const rest = path.substring(prefix.length);
        if (rest.length === 0) {
          return;
        }
        const slash = rest.indexOf('/');
        names.add(slash < 0 ? rest : rest.substring(0, slash));
      });
      const out: string[] = [];
      names.forEach((name: string) => {
        out.push(name);
      });
      return out;
    },
    read: (path: string): Uint8Array | null => {
      const content = files.get(path);
      if (content === undefined) {
        // 目录路径与不存在的路径都落这里 —— 与 rawfile 的真实行为一致：
        // getRawFileContentSync 读目录会抛，被 readRawfileBytes 收敛成 null。
        return null;
      }
      const bytes = new Uint8Array(content.length);
      for (let i = 0; i < content.length; i++) {
        bytes[i] = content.charCodeAt(i);
      }
      return bytes;
    },
  };
}

function readBackAsString(path: string): string {
  const stat = fs.statSync(path);
  const buffer = new ArrayBuffer(stat.size);
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    fs.readSync(file.fd, buffer);
  } finally {
    fs.closeSync(file);
  }
  const view = new Uint8Array(buffer);
  let out = '';
  for (let i = 0; i < view.length; i++) {
    out += String.fromCharCode(view[i]);
  }
  return out;
}

function demoTree(): Map<string, string> {
  const files = new Map<string, string>();
  files.set('demo/pkg/home.css', 'body{}');
  files.set('demo/pkg/home.js', 'console.log(1)');
  files.set('demo/pkg/cards/card-a.svg', '<svg>a</svg>');
  files.set('demo/pkg/cards/card-b.svg', '<svg>b</svg>');
  // 树外的兄弟文件：不得被拷进来。
  files.set('demo/static/styles.css', 'p{}');
  return files;
}

export default function sampleFilesTest() {
  describe('SampleFiles', () => {
    it('copyTree lands a whole rawfile subtree, recursing into subdirectories', 0, () => {
      const dest = TMP_ROOT + '/copy-basic';
      const copied = copyTree(fakeReader(demoTree()), 'demo/pkg', dest);

      expect(copied).assertEqual(4);
      expect(fs.accessSync(dest + '/home.css')).assertTrue();
      expect(fs.accessSync(dest + '/home.js')).assertTrue();
      // 子目录必须被递归建出来 —— 这是 read() 返回 null 那条分支的唯一证据。
      expect(fs.statSync(dest + '/cards').isDirectory()).assertTrue();
      expect(fs.accessSync(dest + '/cards/card-a.svg')).assertTrue();
      expect(fs.accessSync(dest + '/cards/card-b.svg')).assertTrue();
    });

    it('copyTree preserves file contents byte for byte', 0, () => {
      const dest = TMP_ROOT + '/copy-content';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dest);

      expect(readBackAsString(dest + '/home.css')).assertEqual('body{}');
      expect(readBackAsString(dest + '/cards/card-b.svg')).assertEqual('<svg>b</svg>');
    });

    it('copyTree copies only the requested subtree, not sibling directories', 0, () => {
      const dest = TMP_ROOT + '/copy-scoped';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dest);

      // demo/static/styles.css 与 demo/pkg 同级，不属于被请求的子树。
      expect(fs.accessSync(dest + '/styles.css')).assertFalse();
      expect(fs.accessSync(dest + '/static')).assertFalse();
    });

    it('copyTree is idempotent — a second run yields the same result', 0, () => {
      const dest = TMP_ROOT + '/copy-idempotent';
      const first = copyTree(fakeReader(demoTree()), 'demo/pkg', dest);
      const second = copyTree(fakeReader(demoTree()), 'demo/pkg', dest);

      expect(second).assertEqual(first);
      expect(readBackAsString(dest + '/home.css')).assertEqual('body{}');
    });

    it('copyTree clears stale files left over from a previous run', 0, () => {
      const dest = TMP_ROOT + '/copy-stale';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dest);
      writeBytes(dest + '/STALE.txt', new Uint8Array([65]));
      expect(fs.accessSync(dest + '/STALE.txt')).assertTrue();

      // 先删后拷（与 sync-harmony-demo 同一条房规）：源树里删掉的文件不得作为残留滞留。
      copyTree(fakeReader(demoTree()), 'demo/pkg', dest);
      expect(fs.accessSync(dest + '/STALE.txt')).assertFalse();
      expect(fs.accessSync(dest + '/home.css')).assertTrue();
    });

    it('copyTree reflects a file removed from the source tree', 0, () => {
      const dest = TMP_ROOT + '/copy-shrink';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dest);
      expect(fs.accessSync(dest + '/cards/card-b.svg')).assertTrue();

      const shrunk = demoTree();
      shrunk.delete('demo/pkg/cards/card-b.svg');
      const copied = copyTree(fakeReader(shrunk), 'demo/pkg', dest);

      expect(copied).assertEqual(3);
      expect(fs.accessSync(dest + '/cards/card-b.svg')).assertFalse();
      expect(fs.accessSync(dest + '/cards/card-a.svg')).assertTrue();
    });

    it('copyTree on an empty source still produces the destination directory', 0, () => {
      const dest = TMP_ROOT + '/copy-empty';
      const copied = copyTree(fakeReader(new Map<string, string>()), 'demo/nope', dest);

      expect(copied).assertEqual(0);
      expect(fs.statSync(dest).isDirectory()).assertTrue();
    });

    it('ensureDir is idempotent — mkdirSync alone throws EEXIST', 0, () => {
      const dir = TMP_ROOT + '/ensure';
      removeTree(dir);
      ensureDir(dir);
      // 第二次调用不得抛：fs.mkdirSync 对已存在目录会抛 EEXIST，
      // ensureDir 必须先用 accessSync 探过。
      ensureDir(dir);
      expect(fs.statSync(dir).isDirectory()).assertTrue();
    });

    it('ensureDir creates missing parent directories', 0, () => {
      // fs.mkdirSync(path, true) 的 recursion 参数在本沙箱实测**不**创建父目录
      // （对父目录缺失的路径抛 ENOENT），所以 ensureDir 必须自己逐段走。
      const deep = TMP_ROOT + '/deep-a/deep-b/deep-c';
      removeTree(TMP_ROOT + '/deep-a');
      ensureDir(deep);
      expect(fs.statSync(deep).isDirectory()).assertTrue();
      expect(fs.statSync(TMP_ROOT + '/deep-a').isDirectory()).assertTrue();
    });

    it('removeTree deletes a non-empty directory tree', 0, () => {
      const dir = TMP_ROOT + '/remove-nested';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dir);
      expect(fs.accessSync(dir + '/cards/card-a.svg')).assertTrue();

      removeTree(dir);
      expect(fs.accessSync(dir)).assertFalse();
    });

    it('removeTree does not depend on fs.listFileSync, which is absent in this sandbox', 0, () => {
      // 实测：`typeof fs.listFileSync === 'undefined'`，调用即 "undefined is not callable"。
      // removeTree 的主路径因此走 rmdirSync（实测能直删非空嵌套树），枚举只作兜底。
      // 这条断言在 SDK 补上 listFileSync 后会变红 —— 那时把它连同 removeTree 的
      // 兜底注释一起更新即可，别直接删掉：它记录的是「主路径为什么不是遍历」。
      expect(typeof fs.listFileSync).assertEqual('undefined');

      const dir = TMP_ROOT + '/remove-no-list';
      copyTree(fakeReader(demoTree()), 'demo/pkg', dir);
      removeTree(dir);
      expect(fs.accessSync(dir)).assertFalse();
    });

    it('removeTree unlinks a plain file', 0, () => {
      const dir = TMP_ROOT + '/remove-file';
      ensureDir(dir);
      const path = dir + '/f.txt';
      writeBytes(path, new Uint8Array([65]));
      removeTree(path);
      expect(fs.accessSync(path)).assertFalse();
      // 只删那个文件，不动它所在的目录。
      expect(fs.accessSync(dir)).assertTrue();
    });

    it('removeTree is a no-op on a missing path', 0, () => {
      const dir = TMP_ROOT + '/remove-missing';
      removeTree(dir);
      removeTree(dir);
      expect(fs.accessSync(dir)).assertFalse();
    });

    it('toArrayBuffer copies only the view, not the whole backing buffer', 0, () => {
      // 这是本函数存在的全部理由：直接取 bytes.buffer 会把视图之外的字节
      // 一并写进目标，落地内容当场损坏。
      const backing = new Uint8Array([1, 2, 3, 4, 5, 6]);
      const view = backing.subarray(2, 5);

      const result = new Uint8Array(toArrayBuffer(view));
      expect(result.length).assertEqual(3);
      expect(result[0]).assertEqual(3);
      expect(result[1]).assertEqual(4);
      expect(result[2]).assertEqual(5);
    });

    it('writeBytes truncates existing content instead of appending', 0, () => {
      const dir = TMP_ROOT + '/write';
      ensureDir(dir);
      const path = dir + '/f.txt';
      writeBytes(path, new Uint8Array([65, 66, 67, 68]));
      writeBytes(path, new Uint8Array([88]));

      expect(readBackAsString(path)).assertEqual('X');
    });
  });
}
