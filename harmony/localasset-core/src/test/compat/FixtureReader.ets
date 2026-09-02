import fs from '@ohos.file.fs';
import buffer from '@ohos.buffer';
import { FIXTURE_ROOT } from './FixtureRoot.generated';

/**
 * 跨端兼容性 fixture 的共享读取工具。`fs.readTextSync` 与 `util.TextDecoder` 在 hvigor 本地单元
 * 测试沙箱里静默返回空串（见 `harmony/README.md`「本地单元测试沙箱的系统能力限制」），可用组合是
 * statSync + openSync + readSync + closeSync + `@ohos.buffer` 解码。原先这段逻辑在
 * `CompatibilityFixture.test.ets` 与 `CorsHeadersFixture.test.ets` 各抄一份，抽到此处统一维护。
 */

/** 读取 fixture 文件的原始 JSON 文本（沙箱安全的读法）。 */
export function readJsonText(relativePath: string): string {
  const path = FIXTURE_ROOT + '/' + relativePath;
  const stat = fs.statSync(path);
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  const arrayBuffer = new ArrayBuffer(stat.size);
  try {
    fs.readSync(file.fd, arrayBuffer);
  } finally {
    fs.closeSync(file);
  }
  return buffer.from(arrayBuffer).toString('utf-8');
}

/** 读取并解析一个 fixture 文件为指定类型的数组。 */
export function loadJsonCases<T>(relativePath: string): T[] {
  return JSON.parse(readJsonText(relativePath)) as T[];
}
