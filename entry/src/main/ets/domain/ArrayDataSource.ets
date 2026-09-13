export class ArrayDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: T[] = [];

  constructor(initialData?: T[]) {
    if (initialData) {
      this.originDataArray = initialData;
    }
  }

  public totalCount(): number {
    return this.originDataArray.length;
  }

  public getData(index: number): T {
    return this.originDataArray[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  public notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  public notifyDataAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index);
    });
  }

  public notifyDataChange(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataChange(index);
    });
  }

  public notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }

  public notifyDataMove(from: number, to: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataMove(from, to);
    });
  }

  public setData(data: T[]): void {
    this.originDataArray = data || [];
    this.notifyDataReload();
  }

  public pushData(data: T): void {
    this.originDataArray.push(data);
    this.notifyDataAdd(this.originDataArray.length - 1);
  }

  public pushArray(data: T[]): void {
    if (!data || data.length === 0) return;
    for (let i = 0; i < data.length; i++) {
      this.originDataArray.push(data[i]);
    }
    this.notifyDataReload();
  }

  public deleteData(index: number): void {
    if (index >= 0 && index < this.originDataArray.length) {
      this.originDataArray.splice(index, 1);
      this.notifyDataDelete(index);
    }
  }

  public getRawData(): T[] {
    return this.originDataArray;
  }
}
