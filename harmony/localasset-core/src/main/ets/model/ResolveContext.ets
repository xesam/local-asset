export interface ResolveContext {
  engineScope: string | null;
  callerScope: string | null;
  pageScope: string | null;
  sessionScope: string | null;
  requestMetadata: Map<string, string>;
}

/**
 * 平台桥接层把请求头发布进 `requestMetadata` 时的 key 前缀，header 名统一小写
 * （`header.origin`、`header.referer`……）。Android/iOS/HarmonyOS 共享同一约定，
 * 让一个 `Policy` 可跨端移植。
 */
export const REQUEST_HEADER_PREFIX = 'header.';

/**
 * 大小写不敏感地读一个平台桥接层捕获的请求头。桥接层未捕获头（原生调用方）时返回 null——
 * 基于 `Origin` 做闸的 `Policy` 必须自行决定「头缺失」的语义，而非假定头为空。
 */
export function requestHeader(context: ResolveContext, name: string): string | null {
  return context.requestMetadata.get(REQUEST_HEADER_PREFIX + name.toLowerCase()) ?? null;
}

export interface ResolveContextParams {
  engineScope?: string | null;
  callerScope?: string | null;
  pageScope?: string | null;
  sessionScope?: string | null;
  requestMetadata?: Map<string, string>;
}

export function createResolveContext(params?: ResolveContextParams): ResolveContext {
  return {
    engineScope: params?.engineScope ?? null,
    callerScope: params?.callerScope ?? null,
    pageScope: params?.pageScope ?? null,
    sessionScope: params?.sessionScope ?? null,
    requestMetadata: params?.requestMetadata ?? new Map<string, string>(),
  };
}
