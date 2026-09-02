import cryptoFramework from '@ohos.security.cryptoFramework';

const HEX = '0123456789abcdef';
const UUID_BYTES = 16;

/**
 * 生成 UUID v4，优先使用系统 CSPRNG（`@ohos.security.cryptoFramework`），不可用时——
 * **默认抛错**，而不是静默回退。
 *
 * ## 为什么不直接用 `util.generateRandomUUID()`
 *
 * 实测（hvigor 本地单元测试沙箱）：`util.generateRandomUUID()` 返回**空字符串**。
 * 这条 API 一旦用作 handle token，所有 handle URI 会退化成同一条
 * `local-asset://<host>/<prefix>//<fileName>`——而只断言 URI 前后缀的测试对此毫无察觉。
 * 后果不是功能 bug 而是安全洞：Handle 路径是 capability 模型（design.md §5.4），
 * token 的不可猜测性**就是**全部授权，token 恒定即等于「任何人构造一次这条 URI
 * 就能读到别人最后注册的资源」。
 *
 * ## 失败语义：默认抛错，而非静默降级
 *
 * 本文件是 handle token 熵的**唯一入口**。CSPRNG 不可用时若静默回退到 `Math.random()`，
 * token 可预测性会让 capability 授权在真机上无声失效——这正是 threat-model.md 标注的
 * 「fail-open」反模式。因此默认行为是抛 `Error`，把失败暴露给调用方与崩溃平台。
 *
 * 沙箱中 `generateRandomSync` **不抛异常**，而是静默返回长度为 0 的 `data`。
 * 因此判据是「返回值是否含 16 字节」，而不是 try-catch——只靠异常捕获会漏过静默退化。
 *
 * ## 测试沙箱的显式放行
 *
 * hvigor 单测沙箱里 CSPRNG 不可用（`generateRandomSync` 返回空），而 `InMemoryHandleRegistry`
 * 的用例需要能生成可工作的不重复 token。故提供一个**仅用于测试**的显式开关
 * `allowInsecureRandomFallbackForTests(true)`：开启后 CSPRNG 不可用即回退到 `Math.random()`。
 * 开关默认关闭——真机若 CSPRNG 不可用，`generateUuidV4()` 直接抛错，绝不静默降级。
 *
 * 在真机上，层级 1 提供与 Kotlin `UUID.randomUUID()`（SecureRandom）和 iOS `UUID()`
 * 同等质量的密码学随机源，满足 design.md §5.4「token 不可猜测」的要求。
 *
 * ## 替换约束
 *
 * 本文件是 handle token 熵的**唯一入口**——`InMemoryHandleRegistry.register()` 只
 * 调用 `generateUuidV4()`。若要修改 token 生成策略，改这一处即可。
 */

/** 测试沙箱显式放行 `Math.random()` 回退；默认 false = CSPRNG 不可用即抛错。 */
let insecureFallbackAllowed = false;

/**
 * **仅用于测试**：放行 `Math.random()` 回退。hvigor 单测沙箱里 CSPRNG 不可用，
 * 调用方需先 `allowInsecureRandomFallbackForTests(true)` 才能拿到可工作的 token。
 * 真机生产环境**不应**调用——CSPRNG 不可用应当抛错暴露，而不是静默降级。
 */
export function allowInsecureRandomFallbackForTests(allowed: boolean): void {
  insecureFallbackAllowed = allowed;
}

export function generateUuidV4(): string {
  const cryptoBytes = tryCryptoRandom(UUID_BYTES);
  if (cryptoBytes !== null) {
    return formatUuidV4(cryptoBytes);
  }
  if (!insecureFallbackAllowed) {
    throw new Error(
      'LocalAsset: CSPRNG unavailable for handle token (cryptoFramework.generateRandomSync returned no bytes). ' +
      'Refusing to fall back to Math.random() in production — call allowInsecureRandomFallbackForTests(true) ' +
      'only in a test sandbox.'
    );
  }
  return uuidFromMathRandom();
}

/**
 * 尝试通过 `@ohos.security.cryptoFramework` 获取密码学随机字节。
 *
 * 返回 null 的两种情形（均为沙箱特有，真机不会触发）：
 *   1. `createRandom()` 或 `generateRandomSync()` 抛异常；
 *   2. 返回的 `data` 长度 ≠ 请求长度（沙箱中实测为 0）。
 *
 * 两种情形都意味着 CSPRNG 不可用，调用方必须回退。
 */
function tryCryptoRandom(length: number): Uint8Array | null {
  try {
    const random = cryptoFramework.createRandom();
    const blob = random.generateRandomSync(length);
    if (blob && blob.data && blob.data.length === length) {
      return blob.data;
    }
    return null;
  } catch (e) {
    return null;
  }
}

/**
 * 从 16 字节密码学随机源构造标准 UUID v4 字符串。
 *
 * 固定 version 位（byte[6] 高 4 位 = 0x4）和 variant 位（byte[8] 高 2 位 = 0b10），
 * 其余 122 位全部取自 CSPRNG 输出。
 */
function formatUuidV4(bytes: Uint8Array): string {
  // version: 4
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // variant: 10xx
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  let out: string = '';
  for (let i = 0; i < UUID_BYTES; i++) {
    if (i === 4 || i === 6 || i === 8 || i === 10) {
      out += '-';
    }
    out += HEX.charAt((bytes[i] >> 4) & 0x0f);
    out += HEX.charAt(bytes[i] & 0x0f);
  }
  return out;
}

/**
 * Math.random() 回退路径：与旧实现完全一致，保留用于本地单元测试沙箱。
 *
 * 熵来源为 `Math.random()`，不是 CSPRNG——仅作为 CSPRNG 不可用时的兜底，
 * 不应在生产环境中作为 token 生成器依赖。
 */
function uuidFromMathRandom(): string {
  let out: string = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      out += '-';
    } else if (i === 14) {
      out += '4';
    } else if (i === 19) {
      out += HEX.charAt(8 + Math.floor(Math.random() * 4));
    } else {
      out += HEX.charAt(Math.floor(Math.random() * 16));
    }
  }
  return out;
}
