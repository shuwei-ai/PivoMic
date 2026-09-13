export interface AppLifecycleListener { onBackground(): void; onForeground(): void; onDestroy(): void; }

export class AppLifecycleEvents {
  private listeners: Map<number, AppLifecycleListener> = new Map<number, AppLifecycleListener>();
  private nextId: number = 1;
  subscribe(listener: AppLifecycleListener): number { const id = this.nextId++; this.listeners.set(id, listener); return id; }
  unsubscribe(id: number): void { this.listeners.delete(id); }
  publishBackground(): void { this.listeners.forEach((listener: AppLifecycleListener) => listener.onBackground()); }
  publishForeground(): void { this.listeners.forEach((listener: AppLifecycleListener) => listener.onForeground()); }
  publishDestroy(): void { this.listeners.forEach((listener: AppLifecycleListener) => listener.onDestroy()); this.listeners.clear(); }
}

export const systemAppLifecycleEvents: AppLifecycleEvents = new AppLifecycleEvents();
