import { describe, it, expect } from '@ohos/hypium';
import {
  generateUuidV4,
  allowInsecureRandomFallbackForTests,
} from '../../main/ets/internal/Uuid';

/**
 * Uuid 是 handle token 熵的唯一入口（design.md §5.4 capability 模型）。本套用例钉住
 * Finding 5 的核心约束：CSPRNG 不可用时**默认抛错**（生产安全，不静默降级），
 * 仅当测试沙箱显式 `allowInsecureRandomFallbackForTests(true)` 后才回退 `Math.random()`。
 *
 * 沙箱里 `cryptoFramework.generateRandomSync` 恰好返回空字节——即 CSPRNG 不可用——
 * 这正是生产环境遭遇 CSPRNG 故障时的同形条件，故可直接据此断言两种模式。
 */
export default function uuidTest() {
  describe('uuidTest', () => {
    it('throws when CSPRNG unavailable and insecure fallback is disallowed', 0, () => {
      allowInsecureRandomFallbackForTests(false);
      let threw = false;
      try {
        generateUuidV4();
      } catch (e) {
        threw = true;
      } finally {
        // 无论断言是否通过都恢复沙箱放行，避免污染后续用例。
        allowInsecureRandomFallbackForTests(true);
      }
      expect(threw).assertTrue();
    });

    it('falls back to Math.random when insecure fallback is allowed', 0, () => {
      allowInsecureRandomFallbackForTests(true);
      const a = generateUuidV4();
      const b = generateUuidV4();
      expect(a.length).assertEqual(36);
      expect(b.length).assertEqual(36);
      expect(a === b).assertFalse();
    });
  });
}
