/** A reader-local window. Pending requests are shared with foreground navigation. */
export class MushafPageCache<T> {
  private pages = new Map<number, T>();
  private pending = new Map<number, Promise<T>>();
  private center = 1;
  private generation = 0;
  private fetchPage: (page: number) => Promise<T>;
  private prepare: (data: T) => Promise<void>;
  private pageCount: number;

  constructor(
    fetchPage: (page: number) => Promise<T>,
    prepare: (data: T) => Promise<void>,
    pageCount: number,
  ) { this.fetchPage = fetchPage; this.prepare = prepare; this.pageCount = pageCount; }

  peek(page: number): T | undefined { return this.pages.get(page); }

  focus(page: number) {
    this.center = page;
    this.generation += 1;
    for (const cachedPage of this.pages.keys()) {
      if (Math.abs(cachedPage - page) > 2) this.pages.delete(cachedPage);
    }
  }

  load(page: number): Promise<T> {
    const cached = this.pages.get(page);
    if (cached) return Promise.resolve(cached);
    const pending = this.pending.get(page);
    if (pending) return pending;
    const request = this.fetchPage(page).then(async (data) => {
      if (Math.abs(page - this.center) <= 2) {
        await this.prepare(data);
        if (Math.abs(page - this.center) <= 2) this.pages.set(page, data);
      }
      return data;
    }).finally(() => { this.pending.delete(page); });
    this.pending.set(page, request);
    return request;
  }

  prefetch() {
    const generation = this.generation;
    const center = this.center;
    // One chain per direction avoids flooding the connection on rapid swipes.
    for (const direction of [1, -1]) {
      void (async () => {
        for (let offset = 1; offset <= 2; offset += 1) {
          const page = center + direction * offset;
          if (generation !== this.generation || page < 1 || page > this.pageCount) return;
          try { await this.load(page); } catch { /* Retry if this page is opened. */ }
        }
      })();
    }
  }

  stopPrefetch() { this.generation += 1; }
}
