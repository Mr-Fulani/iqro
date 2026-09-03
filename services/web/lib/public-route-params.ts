const DJANGO_SLUG_PATTERN = /^[-a-zA-Z0-9_]+$/;

export function isDuaCategorySlug(value: string): boolean {
  return value.length > 0 && value.length <= 120 && DJANGO_SLUG_PATTERN.test(value);
}

export function isDuaCollectionSlug(value: string): boolean {
  return value.length > 0 && value.length <= 100 && DJANGO_SLUG_PATTERN.test(value);
}
