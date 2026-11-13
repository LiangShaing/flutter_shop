const { createRequire } = require('node:module');
const { readFileSync } = require('node:fs');
const path = require('node:path');

const prefix = process.env.PGLITE_PREFIX;
if (!prefix) throw new Error('Set PGLITE_PREFIX to the directory containing the temporary PGlite installation');
const { PGlite } = createRequire(path.join(path.resolve(prefix), 'package.json'))('@electric-sql/pglite');

async function main() {
  const database = new PGlite();
  try {
    await database.exec(`
      CREATE ROLE anon;
      CREATE ROLE authenticated;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users (id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
        AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      CREATE PUBLICATION supabase_realtime;
    `);
    for (const relativePath of [
      '../migrations/20261112000000_initial_schema.sql',
      '../migrations/20261113010000_merchant_order_submission.sql',
      'merchant_order_submission.sql',
    ]) {
      await database.exec(readFileSync(path.join(__dirname, relativePath), 'utf8'));
    }
    console.log('Merchant order SQL tests passed.');
  } finally {
    await database.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});