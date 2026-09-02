import schemeRequestHandlerTest from './interceptor/SchemeRequestHandler.test';
import directoryResolversTest from './mapping/DirectoryResolvers.test';
import loggingEngineObserverTest from './observer/LoggingEngineObserver.test';
import customSchemeTest from './api/CustomScheme.test';
import { allowInsecureRandomFallbackForTests } from 'io.github.xesam.harmony.localasset.core';

export default function testsuite() {
  // hvigor 单测沙箱里 CSPRNG 不可用，而 handle 端到端用例要 registerHandle 取得真实 token。
  // 放行 Math.random 回退（仅测试沙箱；Uuid.test 在 core 模块另行断言抛错默认）。
  allowInsecureRandomFallbackForTests(true);
  schemeRequestHandlerTest();
  directoryResolversTest();
  loggingEngineObserverTest();
  customSchemeTest();
}
