import { createHash } from 'node:crypto';

const order = ['correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator'];
export function canonicalRecordIdentityV1(record) {
  const parts = [Buffer.from('AIW-CORRECTION-RECORD-V1\n','utf8')];
  for (const field of order) {
    if (typeof record[field] !== 'string') throw new Error(`FIELD:${field}`);
    const name = Buffer.from(field,'utf8');
    const value = Buffer.from(record[field],'utf8');
    parts.push(Buffer.from(`${name.length}:`,'ascii'),name,Buffer.from(`${value.length}:`,'ascii'),value);
  }
  const bytes = Buffer.concat(parts);
  return `${bytes.length}|${createHash('sha256').update(bytes).digest('hex').toUpperCase()}`;
}

if (process.argv[1] && import.meta.url === new URL(`file:///${process.argv[1].replace(/\\/g,'/')}`).href) {
  const input = JSON.parse(process.argv[2]);
  process.stdout.write(canonicalRecordIdentityV1(input));
}
