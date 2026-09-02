import { ResourceLoader } from './ResourceLoader';
import { ResourceSource } from '../model/ResourceDescriptor';

/**
 * 声明自己能处理哪种 ResourceSource。CompositeResourceLoader 按注册顺序调用 canLoad，
 * 用第一个接受该来源的 loader。
 */
export interface TypedResourceLoader extends ResourceLoader {
  canLoad(source: ResourceSource): boolean;
}
