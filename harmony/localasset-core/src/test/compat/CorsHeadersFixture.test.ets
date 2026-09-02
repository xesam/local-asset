import { describe, it, expect } from '@ohos/hypium';
import { readJsonText } from './FixtureReader';
import { corsHeaders, ALLOW_ANY_ORIGIN } from '../../main/ets/cors/CorsPolicy';

/**
 * 跨端 CORS 头契约（design.md §6.1）：`docs/compatibility-fixtures/cors-headers.json` 是
 * Android / iOS / HarmonyOS 三端共用的行为契约。Android 侧由 `CorsHeadersFixtureTest.kt` 消费，
 * iOS 侧由 `CorsHeadersFixtureTests.swift` 消费，本文件是 HarmonyOS 侧。
 */

interface CorsInput {
  allowedOrigins: (string)[];
  requestOrigin: string | null;
}

interface CorsCase {
  name: string;
  input: CorsInput;
  expected: Record<string, string>;
}

function mapToRecord(map: Map<string, string>): Record<string, string> {
  const record: Record<string, string> = {};
  map.forEach((value: string, key: string) => {
    record[key] = value;
  });
  return record;
}

export default function corsHeadersFixtureTest() {
  describe('corsHeadersFixtureTest', () => {
    it('loads the shared cors-headers fixture', 0, () => {
      const cases = JSON.parse(readJsonText('cors-headers.json')) as CorsCase[];
      expect(cases.length).assertEqual(6);
    });

    it('cors_headers_fixture_matches_policy', 0, () => {
      const cases = JSON.parse(readJsonText('cors-headers.json')) as CorsCase[];
      for (const fixture of cases) {
        const allowedOrigins = new Set<string>(fixture.input.allowedOrigins);
        const requestOrigin = fixture.input.requestOrigin;
        const actual = corsHeaders(allowedOrigins, requestOrigin);
        const actualRecord = mapToRecord(actual);
        const expectedKeys = Object.keys(fixture.expected);
        // 先断言键集相同：多发或少发一条头都是跨端偏离。
        const actualKeys = Object.keys(actualRecord);
        expect(actualKeys.length).assertEqual(expectedKeys.length);
        for (const key of expectedKeys) {
          expect(actualRecord[key]).assertEqual(fixture.expected[key]);
        }
      }
    });

    it('allow_any_origin_constant_is_star', 0, () => {
      // 三端共用字面量，改它等于换掉整套契约。
      expect(ALLOW_ANY_ORIGIN).assertEqual('*');
    });
  });
}
