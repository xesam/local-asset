import { ResourceErrorCategory } from './ResourceErrorCategory';

export class ResourceException extends Error {
  readonly category: ResourceErrorCategory;
  readonly stage: string | null;

  constructor(category: ResourceErrorCategory, message: string, stage: string | null = null) {
    super(message);
    this.name = 'ResourceException';
    this.category = category;
    this.stage = stage;
  }
}
