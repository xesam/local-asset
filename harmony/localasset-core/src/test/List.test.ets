import modelContractTest from './model/ModelContract.test';
import indexBarrelTest from './IndexBarrel.test';
import defaultLocalAssetSchemeAdapterTest from './engine/DefaultLocalAssetSchemeAdapter.test';
import resolverChainTest from './internal/ResolverChain.test';
import adapterRegistryTest from './internal/AdapterRegistry.test';
import inMemoryResourceRegistryTest from './registry/InMemoryResourceRegistry.test';
import inMemoryHandleRegistryTest from './registry/InMemoryHandleRegistry.test';
import resolversTest from './resolver/Resolvers.test';
import defaultPolicyTest from './policy/DefaultPolicy.test';
import loadersTest from './loader/Loaders.test';
import defaultLocalAssetEngineTest from './engine/DefaultLocalAssetEngine.test';
import resourceCachePolicyTest from './cache/ResourceCachePolicy.test';
import localAssetBuilderTest from './api/LocalAssetBuilder.test';
import compatibilityFixtureTest from './compat/CompatibilityFixture.test';
import corsHeadersFixtureTest from './compat/CorsHeadersFixture.test';
import uuidTest from './internal/Uuid.test';
import { allowInsecureRandomFallbackForTests } from '../main/ets/internal/Uuid';

export default function testsuite() {
  // hvigor 单测沙箱里 cryptoFramework.generateRandomSync 返回空字节，CSPRNG 不可用。
  // Uuid 默认对 CSPRNG 不可用抛错（生产安全）；测试套件统一放行 Math.random 回退，
  // 使注册/句柄用例能拿到可工作的不重复 token。Uuid.test 另行显式断言两种模式。
  allowInsecureRandomFallbackForTests(true);
  modelContractTest();
  indexBarrelTest();
  defaultLocalAssetSchemeAdapterTest();
  resolverChainTest();
  adapterRegistryTest();
  inMemoryResourceRegistryTest();
  inMemoryHandleRegistryTest();
  resolversTest();
  defaultPolicyTest();
  loadersTest();
  defaultLocalAssetEngineTest();
  resourceCachePolicyTest();
  localAssetBuilderTest();
  compatibilityFixtureTest();
  corsHeadersFixtureTest();
  uuidTest();
}
