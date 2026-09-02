import { AssetRequest } from '../model/AssetRequest';

export interface SchemeAdapter {
  canHandle(url: string): boolean;

  parse(url: string): AssetRequest;
}
