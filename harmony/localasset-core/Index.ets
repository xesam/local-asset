export { ResourceErrorCategory } from './src/main/ets/error/ResourceErrorCategory';
export { ResourceException } from './src/main/ets/error/ResourceException';
export { AssetRequest, AssetRequestParams, createAssetRequest } from './src/main/ets/model/AssetRequest';
export { ResolveContext, ResolveContextParams, createResolveContext, REQUEST_HEADER_PREFIX, requestHeader } from './src/main/ets/model/ResolveContext';
export {
  ResourceType,
  ResourceScope,
  BytesSource,
  FilePathSource,
  ResourceSource,
  bytesSource,
  filePathSource,
  ResourceDescriptor,
  ResourceDescriptorParams,
  createResourceDescriptor,
} from './src/main/ets/model/ResourceDescriptor';
export { ResourceData, bytesData } from './src/main/ets/model/ResourceData';
export {
  ResourceHandle,
  ResourceHandleParams,
  createResourceHandle,
  ResourceHandleRecord,
} from './src/main/ets/model/ResourceHandle';
export { SchemeAdapter } from './src/main/ets/api/SchemeAdapter';
export { DefaultLocalAssetSchemeAdapter } from './src/main/ets/engine/DefaultLocalAssetSchemeAdapter';
export {
  ResolverHit,
  ResolverSkip,
  ResolverFailure,
  ResolverResult,
  ResourceResolver,
  resolverHit,
  resolverSkip,
  resolverFailure,
} from './src/main/ets/api/ResourceResolver';
export {
  RegistryHit,
  RegistryMissing,
  RegistryExpired,
  RegistryLookupResult,
  ResourceRegistry,
  registryHit,
  registryMissing,
  registryExpired,
} from './src/main/ets/api/ResourceRegistry';
export { InMemoryResourceRegistry } from './src/main/ets/registry/InMemoryResourceRegistry';
export { HandleRegistry, CACHE_BUST_PARAM, reconstructUriFromRequest } from './src/main/ets/api/HandleRegistry';
export { InMemoryHandleRegistry } from './src/main/ets/registry/InMemoryHandleRegistry';
export { RegistryResolver } from './src/main/ets/resolver/RegistryResolver';
export { HandleRegistryResolver } from './src/main/ets/resolver/HandleRegistryResolver';
export { StaticMapResolver } from './src/main/ets/resolver/StaticMapResolver';
export { Policy } from './src/main/ets/api/Policy';
export { DefaultPolicy, DefaultPolicyOptions } from './src/main/ets/policy/DefaultPolicy';
export { ResourceLoader } from './src/main/ets/api/ResourceLoader';
export { TypedResourceLoader } from './src/main/ets/api/TypedResourceLoader';
export { BytesResourceLoader } from './src/main/ets/loader/BytesResourceLoader';
export { FileResourceLoader } from './src/main/ets/loader/FileResourceLoader';
export { CompositeResourceLoader } from './src/main/ets/loader/CompositeResourceLoader';
export {
  EngineObserver,
  EngineStageEvent,
  EngineFailureInfo,
  STAGE_ADAPTER_PARSE,
  STAGE_POLICY_PRE,
  STAGE_RESOLVE,
  STAGE_POLICY_POST,
  STAGE_LOAD,
  STAGE_COMPLETE,
} from './src/main/ets/api/EngineObserver';
export {
  LocalAssetEngine,
  EngineResult,
  EngineSuccess,
  EngineFailure,
  engineSuccess,
  engineFailure,
} from './src/main/ets/api/LocalAssetEngine';
export {
  DefaultLocalAssetEngine,
  DefaultLocalAssetEngineOptions,
} from './src/main/ets/engine/DefaultLocalAssetEngine';
export { CacheDecision, DEFAULT_MAX_AGE_SECONDS, decideCache } from './src/main/ets/cache/ResourceCachePolicy';
export { ALLOW_ANY_ORIGIN, corsHeaders } from './src/main/ets/cors/CorsPolicy';
export { LocalAsset, LocalAssetBuilder } from './src/main/ets/api/LocalAsset';
export { normalizeAbsolutePath } from './src/main/ets/policy/DefaultPolicy';
// Test-only escape hatch for the handle-token CSPRNG (see internal/Uuid.ets). Exported so the
// webview module's hvigor sandbox can opt into the Math.random fallback; production code must not call it.
export { allowInsecureRandomFallbackForTests } from './src/main/ets/internal/Uuid';
