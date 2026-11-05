/**
 * seed_dc_logistics.js
 *
 * Seeds Distribution Center (DC), Shipments, and Fleet Trucks into:
 *   Bucket: inventorycount
 *   Scope:  inventory
 *   Collections: counts (for dc-01 stock), locations, trucks, shipments
 */

const fs = require('fs');
const couchbase = require('/Users/austin.gonyou/Downloads/Apps/AirGrid/node_modules/couchbase');

const envPath = '/Users/austin.gonyou/.config/capella/celios_nomad.env';
if (!fs.existsSync(envPath)) {
  console.error('Credentials file not found at', envPath);
  process.exit(1);
}

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
  console.log('Connecting to Couchbase Capella cluster...');
  const cluster = await couchbase.connect(env.CB_CONN_STRING, {
    username: env.CELIOS_USER,
    password: env.CELIOS_PASS,
    configProfile: 'wanDevelopment'
  });
  console.log('Connected successfully!');

  const bucket = cluster.bucket('inventorycount');
  const scope = bucket.scope('inventory');
  const catalogColl = scope.collection('catalog');
  const countsColl = scope.collection('counts');
  const locationsColl = scope.collection('locations');
  const trucksColl = scope.collection('trucks');
  const shipmentsColl = scope.collection('shipments');

  // 1. Fetch all Master Catalog Items from Capella
  console.log('Fetching master products from catalog...');
  const catResult = await cluster.query('SELECT c.* FROM `inventorycount`.inventory.catalog c');
  const catalogItems = catResult.rows.map(r => r);
  console.log(`Loaded ${catalogItems.length} products from catalog.`);

  const now = new Date();
  const nowISO = now.toISOString();

  // 2. Seed DC Locations
  console.log('Seeding DC warehouse locations...');
  const dcLocations = [
    // Receiving Docks
    { id: 'location::dc-01::dock_rec_01', type: 'location', name: 'Midwest DC / Receiving Dock / Door 1', location: { site: 'dc-01', rack: 'Receiving Dock', shelf: 'Dock Door', bin: 'Door 1' }, qr: 'LOC::DC01::REC-D01', notes: 'Inbound PO Unloading Bay - Dry Goods' },
    { id: 'location::dc-01::dock_rec_02', type: 'location', name: 'Midwest DC / Receiving Dock / Door 2', location: { site: 'dc-01', rack: 'Receiving Dock', shelf: 'Dock Door', bin: 'Door 2' }, qr: 'LOC::DC01::REC-D02', notes: 'Inbound PO Unloading Bay - Refrigerated / Cold Chain' },
    { id: 'location::dc-01::dock_rec_03', type: 'location', name: 'Midwest DC / Receiving Dock / Door 3', location: { site: 'dc-01', rack: 'Receiving Dock', shelf: 'Dock Door', bin: 'Door 3' }, qr: 'LOC::DC01::REC-D03', notes: 'Inbound PO Unloading Bay - Chemical & Cleaning Consumables' },
    // Shipping Docks
    { id: 'location::dc-01::dock_shp_14', type: 'location', name: 'Midwest DC / Shipping Dock / Door 14', location: { site: 'dc-01', rack: 'Shipping Dock', shelf: 'Dock Door', bin: 'Door 14' }, qr: 'LOC::DC01::SHP-D14', notes: 'Outbound Store Dispatch - Celios Downtown Supermarket' },
    { id: 'location::dc-01::dock_shp_15', type: 'location', name: 'Midwest DC / Shipping Dock / Door 15', location: { site: 'dc-01', rack: 'Shipping Dock', shelf: 'Dock Door', bin: 'Door 15' }, qr: 'LOC::DC01::SHP-D15', notes: 'Outbound Store Dispatch - Nomad Westside Market' },
    { id: 'location::dc-01::dock_shp_16', type: 'location', name: 'Midwest DC / Shipping Dock / Door 16', location: { site: 'dc-01', rack: 'Shipping Dock', shelf: 'Dock Door', bin: 'Door 16' }, qr: 'LOC::DC01::SHP-D16', notes: 'Outbound Store Dispatch - Nomad Express Route' },
    // Cold Vaults
    { id: 'location::dc-01::vault_cold_1', type: 'location', name: 'Midwest DC / Cold Vault 1 / Tier 1 / Pallet A', location: { site: 'dc-01', rack: 'Cold Vault 1 (Dairy & Eggs)', shelf: 'Tier 1', bin: 'Pallet Bay A' }, qr: 'LOC::DC01::VLT-C1-T1-PA', notes: '34°F Walk-in Cooler Bulk Reserve' },
    { id: 'location::dc-01::vault_cold_2', type: 'location', name: 'Midwest DC / Cold Vault 2 / Tier 1 / Pallet A', location: { site: 'dc-01', rack: 'Cold Vault 2 (Meat & Poultry)', shelf: 'Tier 1', bin: 'Pallet Bay A' }, qr: 'LOC::DC01::VLT-C2-T1-PA', notes: '32°F Meat & Poultry Vault' },
    // Bulk High-Bay Storage
    { id: 'location::dc-01::bay_10_t2_p01', type: 'location', name: 'Midwest DC / Bulk High-Bay Aisle 10 / Tier 2 / Pallet P01', location: { site: 'dc-01', rack: 'Bulk High-Bay Aisle 10', shelf: 'Tier 2', bin: 'Pallet P01' }, qr: 'LOC::DC01::BAY10-T2-P01', notes: 'Household Paper & Cleaning Products Bulk Pallets' },
    { id: 'location::dc-01::bay_12_t3_p04', type: 'location', name: 'Midwest DC / Bulk High-Bay Aisle 12 / Tier 3 / Pallet P04', location: { site: 'dc-01', rack: 'Bulk High-Bay Aisle 12', shelf: 'Tier 3', bin: 'Pallet P04' }, qr: 'LOC::DC01::BAY12-T3-P04', notes: 'Pet Food & Heavy Goods Bulk Pallets' },
    { id: 'location::dc-01::bay_14_t2_p08', type: 'location', name: 'Midwest DC / Bulk High-Bay Aisle 14 / Tier 2 / Pallet P08', location: { site: 'dc-01', rack: 'Bulk High-Bay Aisle 14', shelf: 'Tier 2', bin: 'Pallet P08' }, qr: 'LOC::DC01::BAY14-T2-P08', notes: 'Dry Grocery & Grains Bulk Pallets' },
    { id: 'location::dc-01::bay_16_t1_p12', type: 'location', name: 'Midwest DC / Bulk High-Bay Aisle 16 / Tier 1 / Pallet P12', location: { site: 'dc-01', rack: 'Bulk High-Bay Aisle 16', shelf: 'Tier 1', bin: 'Pallet P12' }, qr: 'LOC::DC01::BAY16-T1-P12', notes: 'Value Valley $1-$2 Grocery Fast-Pick Zone' }
  ];

  for (const loc of dcLocations) {
    await locationsColl.upsert(loc.id, loc);
  }
  console.log(`Seeded ${dcLocations.length} DC locations.`);

  // 3. Seed DC Bulk Inventory in `counts` (site: "dc-01")
  console.log('Seeding DC bulk inventory into "counts"...');
  let dcCount = 0;
  for (let i = 0; i < catalogItems.length; i++) {
    const item = catalogItems[i];
    const unitsPerCase = item.unit === 'gallon' ? 4 : (item.unit === 'pack' ? 12 : (item.unit === 'can' || item.unit === 'box' ? 24 : 12));
    const casesOnHand = Math.floor(item.reorder_quantity * (3 + (i % 4) * 0.5));
    const totalUnits = casesOnHand * unitsPerCase;
    const palletsOnHand = Math.max(1, Math.floor(casesOnHand / 40));
    const reservedUnits = (i % 5 === 0) ? Math.floor(totalUnits * 0.15) : 0;
    const availableToPromise = totalUnits - reservedUnits;

    let dcRack = 'Bulk High-Bay Aisle 14';
    if (item.category === 'Dairy' || item.category === 'Meat' || item.perishable) {
      dcRack = item.category === 'Meat' ? 'Cold Vault 2 (Meat & Poultry)' : 'Cold Vault 1 (Dairy & Eggs)';
    } else if (item.category === 'Household & Cleaning' || item.department === 'Dollar General Merchandise') {
      dcRack = 'Bulk High-Bay Aisle 10';
    } else if (item.category === 'Pet Supplies') {
      dcRack = 'Bulk High-Bay Aisle 12';
    }

    const tierNum = (i % 3) + 1;
    const palletNum = String((i % 20) + 1).padStart(2, '0');

    const dcDoc = {
      type: 'count',
      kind: 'entry',
      team: 'dc-logistics',
      sku: item.sku,
      item_name: item.name,
      count: totalUnits,
      count_is_estimate: false,
      attributes: item.attributes,
      annotation: `DC Bulk Reserve. ${casesOnHand} cases (${palletsOnHand} pallets) on hand.`,
      location: {
        site: 'dc-01',
        rack: dcRack,
        shelf: `Tier ${tierNum}`,
        bin: `Pallet P${palletNum}`
      },
      source: 'code',
      code: item.code,
      confidence: 100,
      needs_review: false,
      captured_at: nowISO,
      captured_by: 'dc_wms_system',
      captured_by_name: 'Celios-Nomad WMS',
      // DC Bulk Supply Chain Fields
      store_id: 'dc-01',
      store_name: 'Celios-Nomad Midwest Distribution Center',
      facility_type: 'DistributionCenter',
      stock_quantity: totalUnits,
      units_per_case: unitsPerCase,
      cases_on_hand: casesOnHand,
      pallets_on_hand: palletsOnHand,
      reserved_for_shipments: reservedUnits,
      available_to_promise: availableToPromise,
      reorder_level: item.reorder_level * 5,
      reorder_quantity: item.reorder_quantity * 8,
      stock_status: availableToPromise > (item.reorder_level * 5) ? 'in_stock' : 'low_stock',
      temperature_class: item.perishable ? 'refrigerated' : 'ambient',
      last_audit_date: nowISO
    };

    const countId = `count::dc-01::${item.sku}`;
    await countsColl.upsert(countId, dcDoc);
    dcCount++;
  }
  console.log(`Seeded ${dcCount} DC bulk inventory records into "counts".`);

  // 4. Seed Fleet / Trucks in `trucks`
  console.log('Seeding Fleet Trucks into "trucks"...');
  const trucks = [
    {
      type: 'truck',
      truck_id: 'TRK-101',
      name: 'Freightliner Cascadia #101 (Multi-Temp Reefer)',
      license_plate: 'IL-TRK-8821',
      vin: '1FUJGLDR7LL129841',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'reefer',
      temperature_zone: 'multi_temp',
      capabilities: ['refrigerated', 'frozen', 'ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 31200,
        current_pallets: 18
      },
      driver: {
        driver_id: 'DRV-501',
        name: 'Marcus Vance',
        phone: '217-555-0144',
        license_class: 'CDL-A'
      },
      current_status: 'en_route',
      current_route: {
        route_id: 'RT-CENTRAL-02',
        origin: 'dc-01',
        stops: ['store-002', 'store-003'],
        assigned_shipments: ['shipment::out::SHP-OUT-8001', 'shipment::out::SHP-OUT-8002']
      },
      telematics: {
        gps: { lat: 39.8403, lon: -88.9548 },
        speed_mph: 58,
        heading: 'NE',
        fuel_level_pct: 78,
        reefer_temp_f: 34.2,
        set_point_f: 34.0,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-102',
      name: 'Kenworth T680 #102 (53ft Dry Van)',
      license_plate: 'IL-TRK-8822',
      vin: '1XKDDP9X8LJ839102',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'dry_van',
      temperature_zone: 'ambient',
      capabilities: ['ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 38400,
        current_pallets: 22
      },
      driver: {
        driver_id: 'DRV-502',
        name: 'Elena Rostova',
        phone: '217-555-0155',
        license_class: 'CDL-A'
      },
      current_status: 'at_dock',
      current_route: {
        route_id: 'RT-DOWNTOWN-01',
        origin: 'dc-01',
        stops: ['store-001'],
        assigned_shipments: ['shipment::out::SHP-OUT-8003']
      },
      telematics: {
        gps: { lat: 39.7817, lon: -89.6501 },
        speed_mph: 0,
        heading: 'STATIONARY',
        fuel_level_pct: 92,
        reefer_temp_f: null,
        set_point_f: null,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-103',
      name: 'Peterbilt 579 #103 (Multi-Temp Reefer)',
      license_plate: 'IL-TRK-8823',
      vin: '1XPBD49X4KD392019',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'reefer',
      temperature_zone: 'multi_temp',
      capabilities: ['refrigerated', 'ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 39600,
        current_pallets: 24
      },
      driver: {
        driver_id: 'DRV-503',
        name: 'Derek Washington',
        phone: '217-555-0177',
        license_class: 'CDL-A'
      },
      current_status: 'en_route',
      current_route: {
        route_id: 'RT-INBOUND-DAIRY',
        origin: 'SUP-101',
        stops: ['dc-01'],
        assigned_shipments: ['shipment::in::SHP-IN-9001']
      },
      telematics: {
        gps: { lat: 40.1164, lon: -88.2434 },
        speed_mph: 62,
        heading: 'SW',
        fuel_level_pct: 64,
        reefer_temp_f: 33.8,
        set_point_f: 34.0,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-104',
      name: 'Volvo VNL 860 #104 (53ft Dry Van)',
      license_plate: 'IL-TRK-8824',
      vin: '4V4NC9EH1KN847291',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'dry_van',
      temperature_zone: 'ambient',
      capabilities: ['ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 18200,
        current_pallets: 10
      },
      driver: {
        driver_id: 'DRV-504',
        name: 'Samantha Cruz',
        phone: '217-555-0188',
        license_class: 'CDL-A'
      },
      current_status: 'staged',
      current_route: {
        route_id: 'RT-WESTSIDE-PET-03',
        origin: 'dc-01',
        stops: ['store-002'],
        assigned_shipments: ['shipment::out::SHP-OUT-8004']
      },
      telematics: {
        gps: { lat: 39.7820, lon: -89.6510 },
        speed_mph: 0,
        heading: 'STATIONARY',
        fuel_level_pct: 85,
        reefer_temp_f: null,
        set_point_f: null,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-105',
      name: 'Freightliner M2 106 #105 (26ft Box Truck with Liftgate)',
      license_plate: 'IL-TRK-8825',
      vin: '1FVACXDT2HH583920',
      carrier: 'Celios-Nomad Metro Logistics',
      trailer_type: 'box_truck',
      temperature_zone: 'ambient',
      capabilities: ['ambient', 'liftgate_delivery'],
      capacity: {
        max_weight_lbs: 16000,
        max_pallets: 10,
        current_weight_lbs: 8900,
        current_pallets: 5
      },
      driver: {
        driver_id: 'DRV-505',
        name: 'Toby Miller',
        phone: '217-555-0199',
        license_class: 'CDL-B'
      },
      current_status: 'en_route',
      current_route: {
        route_id: 'RT-METRO-EXP-01',
        origin: 'dc-01',
        stops: ['store-003'],
        assigned_shipments: ['shipment::out::SHP-OUT-8005']
      },
      telematics: {
        gps: { lat: 40.6936, lon: -89.5890 },
        speed_mph: 45,
        heading: 'N',
        fuel_level_pct: 70,
        reefer_temp_f: null,
        set_point_f: null,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-106',
      name: 'International LT625 #106 (Multi-Temp Reefer)',
      license_plate: 'IL-TRK-8826',
      vin: '3HSDJSJR8LN938210',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'reefer',
      temperature_zone: 'multi_temp',
      capabilities: ['refrigerated', 'frozen', 'ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 0,
        current_pallets: 0
      },
      driver: {
        driver_id: 'DRV-506',
        name: 'Arthur Pendelton',
        phone: '217-555-0211',
        license_class: 'CDL-A'
      },
      current_status: 'idle',
      current_route: null,
      telematics: {
        gps: { lat: 39.7815, lon: -89.6505 },
        speed_mph: 0,
        heading: 'STATIONARY',
        fuel_level_pct: 95,
        reefer_temp_f: 68.0,
        set_point_f: null,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-107',
      name: 'Kenworth T680 #107 (53ft Dry Van)',
      license_plate: 'IL-TRK-8827',
      vin: '1XKDDP9X2MJ849201',
      carrier: 'Celios-Nomad Private Fleet',
      trailer_type: 'dry_van',
      temperature_zone: 'ambient',
      capabilities: ['ambient'],
      capacity: {
        max_weight_lbs: 45000,
        max_pallets: 26,
        current_weight_lbs: 0,
        current_pallets: 0
      },
      driver: {
        driver_id: 'DRV-507',
        name: 'Hannah Abbott',
        phone: '217-555-0222',
        license_class: 'CDL-A'
      },
      current_status: 'maintenance',
      current_route: null,
      telematics: {
        gps: { lat: 39.7800, lon: -89.6490 },
        speed_mph: 0,
        heading: 'STATIONARY',
        fuel_level_pct: 45,
        reefer_temp_f: null,
        set_point_f: null,
        last_ping: nowISO
      }
    },
    {
      type: 'truck',
      truck_id: 'TRK-108',
      name: 'Hino 268A #108 (Refrigerated 26ft Box Truck)',
      license_plate: 'IL-TRK-8828',
      vin: '5PVNJ8JR8LH382910',
      carrier: 'Celios-Nomad Metro Logistics',
      trailer_type: 'box_truck_reefer',
      temperature_zone: 'refrigerated',
      capabilities: ['refrigerated', 'liftgate_delivery'],
      capacity: {
        max_weight_lbs: 15000,
        max_pallets: 8,
        current_weight_lbs: 11200,
        current_pallets: 6
      },
      driver: {
        driver_id: 'DRV-508',
        name: 'Carlos Ramos',
        phone: '217-555-0233',
        license_class: 'CDL-B'
      },
      current_status: 'at_dock',
      current_route: {
        route_id: 'RT-SEAFOOD-FRESH',
        origin: 'SUP-104',
        stops: ['dc-01'],
        assigned_shipments: ['shipment::in::SHP-IN-9005']
      },
      telematics: {
        gps: { lat: 39.7818, lon: -89.6502 },
        speed_mph: 0,
        heading: 'STATIONARY',
        fuel_level_pct: 88,
        reefer_temp_f: 32.5,
        set_point_f: 32.0,
        last_ping: nowISO
      }
    }
  ];

  for (const t of trucks) {
    await trucksColl.upsert(`truck::${t.truck_id}`, t);
  }
  console.log(`Seeded ${trucks.length} fleet trucks.`);

  // 5. Seed Inbound and Outbound Shipments in `shipments`
  console.log('Seeding Inbound and Outbound Shipments into "shipments"...');

  // Helper to find catalog item by SKU
  const findItem = (sku) => catalogItems.find(c => c.sku === sku) || catalogItems[0];

  const shipments = [
    // Outbound 1: Critical replenishment for Store 2 (Nomad Westside) - Resolving the paper/snacks stockout!
    {
      type: 'shipment',
      shipment_id: 'SHP-OUT-8001',
      direction: 'outbound',
      shipment_type: 'store_replenishment',
      priority: 'high',
      status: 'in_transit',
      origin: {
        site: 'dc-01',
        facility_name: 'Celios-Nomad Midwest Distribution Center',
        city: 'Springfield, IL',
        dock_door: 'Door 15'
      },
      destination: {
        store_id: 'store-002',
        site: 'nomad-westside',
        name: 'Nomad Westside Market',
        city: 'Decatur, IL',
        dock_door: 'Receiving Dock B'
      },
      assigned_truck: 'truck::TRK-101',
      carrier: 'Celios-Nomad Private Fleet',
      temperature_class: 'multi_temp',
      schedule: {
        created_at: new Date(now.getTime() - 14400000).toISOString(),
        picked_at: new Date(now.getTime() - 10800000).toISOString(),
        loaded_at: new Date(now.getTime() - 7200000).toISOString(),
        departed_at: new Date(now.getTime() - 3600000).toISOString(),
        estimated_delivery: new Date(now.getTime() + 5400000).toISOString()
      },
      metrics: {
        total_lines: 4,
        total_cases: 160,
        total_units: 1760,
        total_weight_lbs: 14800,
        pallets: 10
      },
      manifest: [
        {
          sku: 'SKU-DGM-CLN-2004',
          name: 'Scott 1000 Sheet Bath Tissue 4 Rolls',
          category: 'Household & Cleaning',
          cases: 40,
          units_per_case: 12,
          total_units: 480,
          weight_lbs: 2400,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 2 / Pallet P01'
        },
        {
          sku: 'SKU-DGM-CLN-2005',
          name: 'Sparkle Paper Towels Pick-A-Size 2 Big Rolls',
          category: 'Household & Cleaning',
          cases: 30,
          units_per_case: 12,
          total_units: 360,
          weight_lbs: 1800,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 2 / Pallet P02'
        },
        {
          sku: 'SKU-DGM-VAL-2039',
          name: 'Clover Valley Macaroni & Cheese Dinner 7.25oz',
          category: 'Value Valley Foods',
          cases: 50,
          units_per_case: 24,
          total_units: 1200,
          weight_lbs: 600,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 16 / Tier 1 / Pallet P12'
        },
        {
          sku: 'SKU-GRC-DAIR-1000',
          name: 'Organic Milk 1 Gallon',
          category: 'Dairy',
          cases: 40,
          units_per_case: 4,
          total_units: 160,
          weight_lbs: 1360,
          temperature_class: 'refrigerated',
          bin_location: 'Cold Vault 1 (Dairy & Eggs) / Tier 1 / Pallet A'
        }
      ]
    },

    // Outbound 2: Delivery to Store 3 (Nomad Express) - Stop 2 on TRK-101
    {
      type: 'shipment',
      shipment_id: 'SHP-OUT-8002',
      direction: 'outbound',
      shipment_type: 'store_replenishment',
      priority: 'standard',
      status: 'in_transit',
      origin: {
        site: 'dc-01',
        facility_name: 'Celios-Nomad Midwest Distribution Center',
        city: 'Springfield, IL',
        dock_door: 'Door 15'
      },
      destination: {
        store_id: 'store-003',
        site: 'nomad-express',
        name: 'Nomad Express & Convenience',
        city: 'Peoria, IL',
        dock_door: 'Rear Delivery Bay'
      },
      assigned_truck: 'truck::TRK-101',
      carrier: 'Celios-Nomad Private Fleet',
      temperature_class: 'multi_temp',
      schedule: {
        created_at: new Date(now.getTime() - 14400000).toISOString(),
        picked_at: new Date(now.getTime() - 10800000).toISOString(),
        loaded_at: new Date(now.getTime() - 7200000).toISOString(),
        departed_at: new Date(now.getTime() - 3600000).toISOString(),
        estimated_delivery: new Date(now.getTime() + 10800000).toISOString()
      },
      metrics: {
        total_lines: 3,
        total_cases: 120,
        total_units: 1680,
        total_weight_lbs: 16400,
        pallets: 8
      },
      manifest: [
        {
          sku: 'SKU-DGM-VAL-2042',
          name: 'Arizona Green Tea with Ginseng & Honey 23oz Tall Can',
          category: 'Value Valley Foods',
          cases: 60,
          units_per_case: 24,
          total_units: 1440,
          weight_lbs: 2200,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 14 / Tier 2 / Pallet P08'
        },
        {
          sku: 'SKU-DGM-HLT-2010',
          name: 'Tylenol Extra Strength Acetaminophen 500mg 50ct',
          category: 'Health & Beauty',
          cases: 20,
          units_per_case: 12,
          total_units: 240,
          weight_lbs: 180,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 3 / Pallet P05'
        },
        {
          sku: 'SKU-GRC-BEV-1007',
          name: 'Family Soda 12-pack',
          category: 'Beverages',
          cases: 40,
          units_per_case: 2,
          total_units: 80,
          weight_lbs: 800,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 14 / Tier 1 / Pallet P03'
        }
      ]
    },

    // Outbound 3: Flagship Store 1 (Celios Downtown) - Currently Loading at DC Door 14
    {
      type: 'shipment',
      shipment_id: 'SHP-OUT-8003',
      direction: 'outbound',
      shipment_type: 'store_replenishment',
      priority: 'high',
      status: 'loading',
      origin: {
        site: 'dc-01',
        facility_name: 'Celios-Nomad Midwest Distribution Center',
        city: 'Springfield, IL',
        dock_door: 'Door 14'
      },
      destination: {
        store_id: 'store-001',
        site: 'celios-downtown',
        name: 'Celios Downtown Supermarket',
        city: 'Springfield, IL',
        dock_door: 'Loading Bay 1'
      },
      assigned_truck: 'truck::TRK-102',
      carrier: 'Celios-Nomad Private Fleet',
      temperature_class: 'ambient',
      schedule: {
        created_at: new Date(now.getTime() - 7200000).toISOString(),
        picked_at: new Date(now.getTime() - 3600000).toISOString(),
        loaded_at: null,
        departed_at: null,
        estimated_delivery: new Date(now.getTime() + 7200000).toISOString()
      },
      metrics: {
        total_lines: 4,
        total_cases: 240,
        total_units: 2880,
        total_weight_lbs: 38400,
        pallets: 22
      },
      manifest: [
        {
          sku: 'SKU-DGM-CLN-2000',
          name: 'Clorox Disinfecting Wipes Fresh Scent 75ct',
          category: 'Household & Cleaning',
          cases: 80,
          units_per_case: 12,
          total_units: 960,
          weight_lbs: 1200,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 1 / Pallet P01'
        },
        {
          sku: 'SKU-DGM-CLN-2003',
          name: 'Gain Original Liquid Laundry Detergent 40oz',
          category: 'Household & Cleaning',
          cases: 60,
          units_per_case: 8,
          total_units: 480,
          weight_lbs: 1920,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 1 / Pallet P02'
        },
        {
          sku: 'SKU-DGM-CLN-2006',
          name: 'Glad Drawstring Trash Bags 13 Gallon 20ct',
          category: 'Household & Cleaning',
          cases: 50,
          units_per_case: 12,
          total_units: 600,
          weight_lbs: 900,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 10 / Tier 2 / Pallet P03'
        },
        {
          sku: 'SKU-DGM-PET-2026',
          name: 'Purina Dog Chow Complete Adult Dry Dog Food 4.4 lb',
          category: 'Pet Supplies',
          cases: 50,
          units_per_case: 6,
          total_units: 300,
          weight_lbs: 1320,
          temperature_class: 'ambient',
          bin_location: 'Bulk High-Bay Aisle 12 / Tier 1 / Pallet P01'
        }
      ]
    },

    // Inbound 1: PO from Valley Fresh Dairy Farms arriving on TRK-103
    {
      type: 'shipment',
      shipment_id: 'SHP-IN-9001',
      direction: 'inbound',
      shipment_type: 'supplier_po',
      po_number: 'PO-2026-DAIR-091',
      priority: 'standard',
      status: 'in_transit',
      origin: {
        supplier_id: 'SUP-101',
        name: 'Valley Fresh Dairy Farms',
        city: 'Champaign, IL',
        shipping_dock: 'Farm Gate 3'
      },
      destination: {
        site: 'dc-01',
        facility_name: 'Celios-Nomad Midwest Distribution Center',
        city: 'Springfield, IL',
        dock_door: 'Door 2 (Reefer Receiving)'
      },
      assigned_truck: 'truck::TRK-103',
      carrier: 'Valley Fresh Dedicated Logistics',
      temperature_class: 'refrigerated',
      schedule: {
        po_issued_at: new Date(now.getTime() - 86400000).toISOString(),
        dispatched_at: new Date(now.getTime() - 7200000).toISOString(),
        estimated_arrival: new Date(now.getTime() + 3600000).toISOString(),
        received_at: null
      },
      metrics: {
        total_lines: 2,
        total_cases: 600,
        total_units: 2400,
        total_weight_lbs: 39600,
        pallets: 24
      },
      manifest: [
        {
          sku: 'SKU-GRC-DAIR-1000',
          name: 'Organic Whole Milk 1 Gallon',
          category: 'Dairy',
          cases: 400,
          units_per_case: 4,
          total_units: 1600,
          weight_lbs: 13600,
          unit_cost: 3.20,
          lot_number: 'LOT-DAIR-20261102-01',
          temperature_class: 'refrigerated',
          destination_vault: 'Cold Vault 1 (Dairy & Eggs)'
        },
        {
          sku: 'SKU-GRC-DAIR-1001',
          name: 'Classic Cheese Cheddar Block 16oz',
          category: 'Dairy',
          cases: 200,
          units_per_case: 12,
          total_units: 2400,
          weight_lbs: 2400,
          unit_cost: 2.10,
          lot_number: 'LOT-CHED-20261101-04',
          temperature_class: 'refrigerated',
          destination_vault: 'Cold Vault 1 (Dairy & Eggs)'
        }
      ]
    },

    // Inbound 2: PO from Clorox Consumer Products - Currently Docked & Unloading at Door 3
    {
      type: 'shipment',
      shipment_id: 'SHP-IN-9002',
      direction: 'inbound',
      shipment_type: 'supplier_po',
      po_number: 'PO-2026-CLRX-448',
      priority: 'high',
      status: 'unloading',
      origin: {
        supplier_id: 'SUP-109',
        name: 'Clorox Consumer Products Div.',
        city: 'University Park, IL',
        shipping_dock: 'Dock 8'
      },
      destination: {
        site: 'dc-01',
        facility_name: 'Celios-Nomad Midwest Distribution Center',
        city: 'Springfield, IL',
        dock_door: 'Door 3'
      },
      assigned_truck: 'truck::TRK-108',
      carrier: 'Schneider National Logistics',
      temperature_class: 'ambient',
      schedule: {
        po_issued_at: new Date(now.getTime() - 172800000).toISOString(),
        dispatched_at: new Date(now.getTime() - 14400000).toISOString(),
        arrived_at: new Date(now.getTime() - 3600000).toISOString(),
        unloading_started_at: new Date(now.getTime() - 1800000).toISOString(),
        estimated_putaway: new Date(now.getTime() + 3600000).toISOString()
      },
      metrics: {
        total_lines: 3,
        total_cases: 550,
        total_units: 5400,
        total_weight_lbs: 22500,
        pallets: 18
      },
      manifest: [
        {
          sku: 'SKU-DGM-CLN-2000',
          name: 'Clorox Disinfecting Wipes Fresh Scent 75ct',
          category: 'Household & Cleaning',
          cases: 250,
          units_per_case: 12,
          total_units: 3000,
          weight_lbs: 3750,
          unit_cost: 3.10,
          destination_bin: 'Bulk High-Bay Aisle 10 / Tier 1 / Pallet P01'
        },
        {
          sku: 'SKU-DGM-CLN-2001',
          name: 'Clorox Regular Liquid Bleach 64oz',
          category: 'Household & Cleaning',
          cases: 150,
          units_per_case: 8,
          total_units: 1200,
          weight_lbs: 6000,
          unit_cost: 2.60,
          destination_bin: 'Bulk High-Bay Aisle 10 / Tier 1 / Pallet P02'
        },
        {
          sku: 'SKU-DGM-CLN-2008',
          name: 'Pine-Sol Multi-Surface Cleaner Original Pine 24oz',
          category: 'Household & Cleaning',
          cases: 150,
          units_per_case: 8,
          total_units: 1200,
          weight_lbs: 2700,
          unit_cost: 1.80,
          destination_bin: 'Bulk High-Bay Aisle 10 / Tier 2 / Pallet P04'
        }
      ]
    }
  ];

  for (const s of shipments) {
    const key = `shipment::${s.direction === 'inbound' ? 'in' : 'out'}::${s.shipment_id}`;
    await shipmentsColl.upsert(key, s);
  }
  console.log(`Seeded ${shipments.length} inbound/outbound shipments.`);

  // 6. Run Cross-Collection Supply Chain Validation Queries
  console.log('\n--- Running Supply Chain Validation Queries ---');

  // Query 1: Active Trucks and their assigned shipments
  const activeTrucks = await cluster.query(`
    SELECT t.truck_id, t.name, t.current_status, t.trailer_type, t.driver.name as driver_name,
           t.capacity.current_weight_lbs, t.capacity.max_weight_lbs,
           t.current_route.stops as route_stops
    FROM \`inventorycount\`.inventory.trucks t
    WHERE t.current_status IN ['en_route', 'at_dock', 'staged']
    ORDER BY t.truck_id ASC
  `);
  console.log('\nActive Fleet Trucks:');
  console.log(JSON.stringify(activeTrucks.rows, null, 2));

  // Query 2: Outbound Manifest Items in Transit to Nomad Westside
  const inTransitWestside = await cluster.query(`
    SELECT s.shipment_id, s.destination.name as destination_store, s.status, s.assigned_truck,
           m.sku, m.name as item_name, m.total_units, m.cases
    FROM \`inventorycount\`.inventory.shipments s
    UNNEST s.manifest as m
    WHERE s.destination.store_id = 'store-002' AND s.status = 'in_transit'
  `);
  console.log('\nOutbound Manifest in Transit to Nomad Westside (store-002):');
  console.log(JSON.stringify(inTransitWestside.rows, null, 2));

  // Query 3: Total Pipeline Stock for Sparkle Paper Towels (Store 1 + Store 2 + Store 3 + In-Transit + DC Bulk)
  const pipelineStock = await cluster.query(`
    SELECT 
      c.store_id, 
      c.store_name, 
      c.stock_quantity as on_hand_units,
      c.stock_status
    FROM \`inventorycount\`.inventory.counts c
    WHERE c.sku = 'SKU-DGM-CLN-2005'
    ORDER BY c.store_id ASC
  `);
  console.log('\nPipeline Stock for Sparkle Paper Towels (SKU-DGM-CLN-2005) across all locations:');
  console.log(JSON.stringify(pipelineStock.rows, null, 2));

  await cluster.close();
  console.log('\nDistribution Center & Logistics seeding completed successfully!');
}

main().catch(err => {
  console.error('Fatal error during logistics seeding:', err);
  process.exit(1);
});
