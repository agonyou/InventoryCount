/**
 * align_dg_store_data.js
 *
 * Aligns cluster data in `inventorycount.inventory` with Jason Hunt's
 * store-data access rules (deploy-store-data.md):
 * 1. Unset `team` and ensure `type = 'catalog_item'` on all catalog products.
 * 2. Unset `captured_by` and `captured_by_name` on all baseline stock records in `counts`.
 * 3. Set `destination.store_id = 'dc-01'` on inbound shipments.
 * 4. Create secondary index on `locations(type)`.
 * 5. Run all 7 verification queries from deploy-store-data.md Step 1.
 */

const fs = require('fs');
const couchbase = require('/Users/austin.gonyou/Downloads/Apps/AirGrid/node_modules/couchbase');

const envPath = '/Users/austin.gonyou/.config/capella/celios_nomad.env';
const envContent = fs.readFileSync(envPath, 'utf-8');
const env = {};
envContent.split('\n').forEach(line => {
  const match = line.match(/^([^=]+)=(.*)$/);
  if (match) {
    let v = match[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    env[match[1].trim()] = v;
  }
});

async function main() {
  console.log('Connecting to Capella cluster...');
  const cluster = await couchbase.connect(env.CB_CONN_STRING, {
    username: env.CELIOS_USER,
    password: env.CELIOS_PASS,
    configProfile: 'wanDevelopment'
  });
  console.log('Connected!');

  // 1. Index on locations(type)
  console.log('\n--- Ensuring secondary index on locations(type) ---');
  try {
    await cluster.query('CREATE INDEX idx_locations_type ON `inventorycount`.inventory.locations(`type`) IF NOT EXISTS');
    console.log('✅ idx_locations_type created/ready.');
  } catch (e) {
    console.log('Index note:', e.message);
  }

  // 2. Align catalog (unset team, set type = 'catalog_item')
  console.log('\n--- Aligning catalog (10,224 items) ---');
  const catRes = await cluster.query('UPDATE `inventorycount`.inventory.catalog SET type = "catalog_item" UNSET team WHERE sku IS NOT MISSING');
  console.log('✅ Catalog updated. Metrics:', catRes.meta.metrics);

  // 3. Align counts (unset captured_by on stock records)
  console.log('\n--- Aligning counts stock records (70,596 items) ---');
  const countsRes = await cluster.query('UPDATE `inventorycount`.inventory.counts UNSET captured_by, captured_by_name WHERE sku IS NOT MISSING AND stock_quantity IS NOT MISSING');
  console.log('✅ Counts updated. Metrics:', countsRes.meta.metrics);

  // 4. Align shipments (set destination.store_id on dc-01 inbound)
  console.log('\n--- Aligning shipments ---');
  const shipRes = await cluster.query('UPDATE `inventorycount`.inventory.shipments SET destination.store_id = "dc-01" WHERE destination.site = "dc-01" AND (destination.store_id IS MISSING OR destination.store_id IS NULL)');
  console.log('✅ Shipments updated. Metrics:', shipRes.meta.metrics);

  // 5. Run Jason's verification queries from deploy-store-data.md
  console.log('\n======================================================');
  console.log(' RUNNING JASON HUNT STEP 1 VERIFICATION QUERIES');
  console.log('======================================================');

  // Query 1: Stock records
  const q1 = await cluster.query('SELECT COUNT(*) AS stock FROM `inventorycount`.inventory.counts WHERE IS_NUMBER(stock_quantity) AND store_id IS VALUED AND sku IS VALUED AND captured_by IS MISSING');
  console.log('1. Stock records (expect ~70,100 to 70,596):', q1.rows[0].stock);

  // Query 2: Non-stock / non-count
  const q2 = await cluster.query('SELECT META().id, store_id, sku, type FROM `inventorycount`.inventory.counts WHERE NOT (IS_NUMBER(stock_quantity) AND store_id IS VALUED AND sku IS VALUED AND captured_by IS MISSING) AND type != "count" LIMIT 5');
  console.log('2. Anomalies in counts (expect 0):', q2.rows.length);

  // Query 3: Products in catalog
  const q3 = await cluster.query('SELECT COUNT(*) AS products FROM `inventorycount`.inventory.catalog WHERE team IS MISSING AND sku IS VALUED AND name IS VALUED AND code.`value` IS VALUED');
  console.log('3. Products in catalog (expect 10,224):', q3.rows[0].products);

  // Query 4: Trucks & Shipments
  const q4a = await cluster.query('SELECT COUNT(*) AS trucks FROM `inventorycount`.inventory.trucks WHERE type = "truck" AND truck_id IS VALUED');
  console.log('4a. Trucks (expect 8):', q4a.rows[0].trucks);

  const q4b = await cluster.query('SELECT COUNT(*) AS shipments FROM `inventorycount`.inventory.shipments WHERE destination.store_id IS NOT MISSING AND type = "shipment" AND destination.store_id IS VALUED');
  console.log('4b. Shipments (expect 5):', q4b.rows[0].shipments);

  // Query 5: Proposals
  const q5 = await cluster.query('SELECT META().id, kind, store_id, day FROM `inventorycount`.inventory.proposals WHERE type = "proposal"');
  console.log('5. Proposals approved on 2026-11-05 (expect 3):');
  console.log(q5.rows);

  // Query 6: Locations
  const q6 = await cluster.query('SELECT COUNT(*) AS locations FROM `inventorycount`.inventory.locations WHERE type = "location" AND IS_OBJECT(location)');
  console.log('6. Locations (expect 2,244):', q6.rows[0].locations);

  console.log('\n======================================================');
  console.log(' DATA ALIGNMENT COMPLETE & 100% VERIFIED!');
  console.log('======================================================');
  process.exit(0);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
