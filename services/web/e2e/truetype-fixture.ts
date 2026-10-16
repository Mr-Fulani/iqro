/**
 * A two-glyph TrueType file for heading tests: an empty .notdef and a 200×100
 * glyph whose top-right corner is a quadratic curve through one off-curve
 * point. The real KFGQPC heading font is never stored in this project.
 */
export function syntheticHeadingFont(): Uint8Array {
  const int16 = (values: number[]) => {
    const view = new DataView(new ArrayBuffer(values.length * 2));
    values.forEach((value, index) => view.setInt16(index * 2, value));
    return new Uint8Array(view.buffer);
  };
  const glyf = new Uint8Array([
    ...int16([1, 0, 0, 200, 100, 3, 0]),
    1, 1, 0, 1,
    ...int16([0, 200, 0, -200, 0, 0, 100, 0]),
  ]);
  const head = new Uint8Array(54);
  new DataView(head.buffer).setInt16(50, 1);
  const maxp = new Uint8Array(6);
  new DataView(maxp.buffer).setUint32(0, 0x00005000);
  new DataView(maxp.buffer).setUint16(4, 2);
  const loca = new Uint8Array(12);
  new DataView(loca.buffer).setUint32(8, glyf.length);
  const tables: [string, Uint8Array][] = [["glyf", glyf], ["head", head], ["loca", loca], ["maxp", maxp]];
  const directory = new DataView(new ArrayBuffer(12 + 16 * tables.length));
  directory.setUint32(0, 0x00010000);
  directory.setUint16(4, tables.length);
  const chunks: Uint8Array[] = [new Uint8Array(directory.buffer)];
  let offset = directory.byteLength;
  tables.forEach(([tag, data], index) => {
    const record = 12 + 16 * index;
    [...tag].forEach((char, position) => directory.setUint8(record + position, char.charCodeAt(0)));
    directory.setUint32(record + 8, offset);
    directory.setUint32(record + 12, data.length);
    const padded = new Uint8Array((data.length + 3) & ~3);
    padded.set(data);
    chunks.push(padded);
    offset += padded.length;
  });
  const font = new Uint8Array(offset);
  let position = 0;
  for (const chunk of chunks) {
    font.set(chunk, position);
    position += chunk.length;
  }
  return font;
}
