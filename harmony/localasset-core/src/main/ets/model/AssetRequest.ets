export interface AssetRequest {
  scheme: string;
  namespace: string;
  identifier: string | null;
  path: string | null;
  query: Map<string, string>;
  fragment: string | null;
  metadata: Map<string, string>;
}

export interface AssetRequestParams {
  scheme: string;
  namespace: string;
  identifier: string | null;
  path: string | null;
  query?: Map<string, string>;
  fragment?: string | null;
  metadata?: Map<string, string>;
}

/**
 * design.md §4.1: identifier 与 path 至少一个非空。两者都留空是调用方错误，
 * 立即抛出，而不是让 resolver 后续静默 Skip。
 */
export function createAssetRequest(params: AssetRequestParams): AssetRequest {
  if (params.identifier === null && params.path === null) {
    throw new Error('AssetRequest requires identifier or path to be non-null');
  }
  return {
    scheme: params.scheme,
    namespace: params.namespace,
    identifier: params.identifier,
    path: params.path,
    query: params.query ?? new Map<string, string>(),
    fragment: params.fragment ?? null,
    metadata: params.metadata ?? new Map<string, string>(),
  };
}
