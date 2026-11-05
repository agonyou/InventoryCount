/**
 * seed_intepros_inventory.js
 *
 * Seeds comprehensive inventory data into Couchbase Capella cluster:
 *   Bucket: inventorycount
 *   Scope:  inventory
 *   Collections: catalog, catalogue, counts, locations
 *
 * Blends:
 *   1. Couchbase Labs retail demo dataset (80 core grocery items)
 *   2. Kaggle grocery inventory supply chain schema (reorder metrics, suppliers, turnover, dates)
 *   3. Dollar General merchandise (cleaning, paper, health/beauty/OTC, hardware, pet, school, $1-$2 value snacks)
 *   4. Consistent SKU scheme (SKU-GRC-*, SKU-DGM-*) & standard 12-digit UPCs
 *   5. Multi-store distribution across Celios Downtown, Nomad Westside, and Nomad Express
 */

const fs = require('fs');
const path = require('path');
const couchbase = require('/Users/austin.gonyou/Downloads/Apps/AirGrid/node_modules/couchbase');

// 1. Load Credentials
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

// Helper for UPC-A check digit calculation
function generateUPC(number) {
  const base11 = String(number).padStart(11, '0').slice(-11);
  let oddSum = 0;
  let evenSum = 0;
  for (let i = 0; i < 11; i++) {
    const digit = parseInt(base11[i], 10);
    if (i % 2 === 0) {
      oddSum += digit;
    } else {
      evenSum += digit;
    }
  }
  const total = (oddSum * 3) + evenSum;
  const checkDigit = (10 - (total % 10)) % 10;
  return base11 + checkDigit;
}

// 2. Define Suppliers (Kaggle Schema)
const SUPPLIERS = [
  { supplier_id: 'SUP-101', name: 'Valley Fresh Dairy Farms', lead_time_days: 2 },
  { supplier_id: 'SUP-102', name: 'Artisan Mill & Bakery Co.', lead_time_days: 1 },
  { supplier_id: 'SUP-103', name: 'Apex Meat & Poultry Packing', lead_time_days: 3 },
  { supplier_id: 'SUP-104', name: 'Pacific Coast Seafoods', lead_time_days: 2 },
  { supplier_id: 'SUP-105', name: 'Sunny Orchard Produce Inc.', lead_time_days: 2 },
  { supplier_id: 'SUP-106', name: 'Global Beverage Bottlers', lead_time_days: 4 },
  { supplier_id: 'SUP-107', name: 'National Cereal & Grain Mills', lead_time_days: 5 },
  { supplier_id: 'SUP-108', name: 'Procter & Hygiene Consumer Goods', lead_time_days: 4 },
  { supplier_id: 'SUP-109', name: 'Clorox Consumer Products Div.', lead_time_days: 3 },
  { supplier_id: 'SUP-110', name: 'Evergreen Paper & Towel Corp.', lead_time_days: 5 },
  { supplier_id: 'SUP-111', name: 'HealthCare Brands Alliance', lead_time_days: 4 },
  { supplier_id: 'SUP-112', name: 'Purina & Companion Pet Foods', lead_time_days: 4 },
  { supplier_id: 'SUP-113', name: 'Bic & Dixon Office Supply Co.', lead_time_days: 6 },
  { supplier_id: 'SUP-114', name: 'Rayovac & Hardware Essentials', lead_time_days: 5 },
  { supplier_id: 'SUP-115', name: 'Clover Valley Discount Foods', lead_time_days: 3 }
];

// 3. Define Stores for Multi-Store Challenges
const STORES = [
  {
    store_id: 'store-001',
    site: 'celios-downtown',
    name: 'Celios Downtown Supermarket',
    city: 'Springfield, IL',
    type: 'Supermarket Flagship'
  },
  {
    store_id: 'store-002',
    site: 'nomad-westside',
    name: 'Nomad Westside Market',
    city: 'Decatur, IL',
    type: 'Suburban Grocery & Variety'
  },
  {
    store_id: 'store-003',
    site: 'nomad-express',
    name: 'Nomad Express & Convenience',
    city: 'Peoria, IL',
    type: 'Urban Convenience Store'
  }
];

// 4. Build Dollar General Merchandise Catalog Items
const DOLLAR_GENERAL_ITEMS = [
  // Cleaning & Paper
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'WIP', name: 'Clorox Disinfecting Wipes Fresh Scent 75ct',
    brand: 'Clorox', price: 5.25, cost: 3.10, unit: 'canister', reorderLevel: 30, reorderQty: 60,
    attributes: '75 count, Fresh Scent, Bleach-Free', supplierId: 'SUP-109', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'BLE', name: 'Clorox Regular Liquid Bleach 64oz',
    brand: 'Clorox', price: 4.50, cost: 2.60, unit: 'bottle', reorderLevel: 25, reorderQty: 50,
    attributes: '64 fl oz, Concentrated, Whitens & Disinfects', supplierId: 'SUP-109', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'DSH', name: 'Dawn Ultra Dishwashing Liquid Original 16.2oz',
    brand: 'Dawn', price: 3.25, cost: 1.85, unit: 'bottle', reorderLevel: 40, reorderQty: 80,
    attributes: '16.2 fl oz, Original Blue Scent, 3X Grease Cleaner', supplierId: 'SUP-108', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'LAU', name: 'Gain Original Liquid Laundry Detergent 40oz',
    brand: 'Gain', price: 5.95, cost: 3.40, unit: 'bottle', reorderLevel: 30, reorderQty: 60,
    attributes: '40 fl oz, 32 loads, AromaBoost Original', supplierId: 'SUP-108', perishable: false, shelfLife: 540
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'PAP', name: 'Scott 1000 Sheet Bath Tissue 4 Rolls',
    brand: 'Scott', price: 4.95, cost: 2.90, unit: 'pack', reorderLevel: 50, reorderQty: 100,
    attributes: '4 rolls, 1000 sheets per roll, 1-ply', supplierId: 'SUP-110', perishable: false, shelfLife: 1825
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'PAP', name: 'Sparkle Paper Towels Pick-A-Size 2 Big Rolls',
    brand: 'Sparkle', price: 3.75, cost: 2.10, unit: 'pack', reorderLevel: 45, reorderQty: 90,
    attributes: '2 big rolls = 4 regular rolls, Spirited Prints', supplierId: 'SUP-110', perishable: false, shelfLife: 1825
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'TRH', name: 'Glad Drawstring Trash Bags 13 Gallon 20ct',
    brand: 'Glad', price: 5.50, cost: 3.20, unit: 'box', reorderLevel: 35, reorderQty: 70,
    attributes: '13 gallon, 20 count, ForceFlex OdorShield', supplierId: 'SUP-109', perishable: false, shelfLife: 1825
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'SPR', name: 'Lysol Disinfectant Spray Crisp Linen 19oz',
    brand: 'Lysol', price: 6.95, cost: 4.10, unit: 'can', reorderLevel: 25, reorderQty: 50,
    attributes: '19 oz aerosol, Crisp Linen Scent, Kills 99.9% germs', supplierId: 'SUP-109', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'PIN', name: 'Pine-Sol Multi-Surface Cleaner Original Pine 24oz',
    brand: 'Pine-Sol', price: 3.20, cost: 1.80, unit: 'bottle', reorderLevel: 30, reorderQty: 60,
    attributes: '24 fl oz, Concentrated Formula, Deodorizes', supplierId: 'SUP-109', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'CLN', catName: 'Household & Cleaning', sub: 'ERA', name: 'Mr. Clean Magic Eraser Extra Durable 2ct',
    brand: 'Mr. Clean', price: 3.50, cost: 1.95, unit: 'pack', reorderLevel: 30, reorderQty: 60,
    attributes: '2 pack cleaning pads, Durafoam technology', supplierId: 'SUP-108', perishable: false, shelfLife: 1095
  },

  // Health & OTC First Aid
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'TYL', name: 'Tylenol Extra Strength Acetaminophen 500mg 50ct',
    brand: 'Tylenol', price: 7.95, cost: 4.80, unit: 'bottle', reorderLevel: 20, reorderQty: 40,
    attributes: '50 caplets, 500mg each, Pain reliever & fever reducer', supplierId: 'SUP-111', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'ADV', name: 'Advil Pain Reliever Ibuprofen Tablets 200mg 50ct',
    brand: 'Advil', price: 7.50, cost: 4.50, unit: 'bottle', reorderLevel: 20, reorderQty: 40,
    attributes: '50 coated tablets, 200mg NSAID pain reliever', supplierId: 'SUP-111', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'PEP', name: 'Pepto Bismol 5 Symptom Relief Liquid 8oz',
    brand: 'Pepto Bismol', price: 5.25, cost: 3.00, unit: 'bottle', reorderLevel: 20, reorderQty: 40,
    attributes: '8 fl oz, Original Pink liquid, Upset stomach relief', supplierId: 'SUP-111', perishable: false, shelfLife: 540
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'BAN', name: 'Band-Aid Flexible Fabric Adhesive Bandages 30ct',
    brand: 'Band-Aid', price: 3.95, cost: 2.20, unit: 'box', reorderLevel: 30, reorderQty: 60,
    attributes: '30 count, Assorted sizes, Memory Weave fabric', supplierId: 'SUP-111', perishable: false, shelfLife: 1095
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'NEO', name: 'Neosporin Original Antibiotic Ointment 0.5oz',
    brand: 'Neosporin', price: 4.95, cost: 2.80, unit: 'tube', reorderLevel: 25, reorderQty: 50,
    attributes: '0.5 oz tube, 24-hour infection protection', supplierId: 'SUP-111', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'CLG', name: 'Colgate Total Whitening Toothpaste 4.8oz',
    brand: 'Colgate', price: 3.95, cost: 2.10, unit: 'tube', reorderLevel: 40, reorderQty: 80,
    attributes: '4.8 oz, Mint paste, Cavity & plaque protection', supplierId: 'SUP-111', perishable: false, shelfLife: 540
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'DIA', name: 'Dial Antibacterial Bar Soap Gold 3ct',
    brand: 'Dial', price: 2.85, cost: 1.50, unit: 'pack', reorderLevel: 35, reorderQty: 70,
    attributes: '3 bars, 4 oz each, Antibacterial Gold scent', supplierId: 'SUP-108', perishable: false, shelfLife: 1095
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'SVA', name: 'Suave Daily Clarifying Shampoo 30oz',
    brand: 'Suave', price: 2.50, cost: 1.30, unit: 'bottle', reorderLevel: 30, reorderQty: 60,
    attributes: '30 fl oz, pH-balanced for normal to oily hair', supplierId: 'SUP-108', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'DOV', name: 'Dove Deep Moisture Body Wash 12oz',
    brand: 'Dove', price: 4.75, cost: 2.70, unit: 'bottle', reorderLevel: 30, reorderQty: 60,
    attributes: '12 fl oz, 24hr Renewing MicroMoisture', supplierId: 'SUP-108', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'HLT', catName: 'Health & Beauty', sub: 'QTP', name: 'Q-tips Cotton Swabs Precision Tips 300ct',
    brand: 'Q-tips', price: 3.25, cost: 1.70, unit: 'box', reorderLevel: 35, reorderQty: 70,
    attributes: '300 count, 100% pure cotton swabs', supplierId: 'SUP-108', perishable: false, shelfLife: 1825
  },

  // Home Essentials & Hardware
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'BAT', name: 'Energizer Max Alkaline AA Batteries 4-Pack',
    brand: 'Energizer', price: 5.95, cost: 3.40, unit: 'pack', reorderLevel: 40, reorderQty: 80,
    attributes: '4 count AA batteries, 10-year shelf life', supplierId: 'SUP-114', perishable: false, shelfLife: 3650
  },
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'BAT', name: 'Energizer Max Alkaline AAA Batteries 4-Pack',
    brand: 'Energizer', price: 5.95, cost: 3.40, unit: 'pack', reorderLevel: 40, reorderQty: 80,
    attributes: '4 count AAA batteries, PowerSeal technology', supplierId: 'SUP-114', perishable: false, shelfLife: 3650
  },
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'BUL', name: 'General Electric 60W LED Soft White Bulbs 4-Pack',
    brand: 'GE', price: 6.50, cost: 3.80, unit: 'pack', reorderLevel: 25, reorderQty: 50,
    attributes: '4 bulbs, 800 lumens, Non-dimmable, A19 medium base', supplierId: 'SUP-114', perishable: false, shelfLife: 3650
  },
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'DUC', name: 'Gorilla Heavy Duty Duct Tape Black 30yd',
    brand: 'Gorilla', price: 7.95, cost: 4.60, unit: 'roll', reorderLevel: 20, reorderQty: 40,
    attributes: '1.88 in x 30 yd, Tough weather-resistant shell', supplierId: 'SUP-114', perishable: false, shelfLife: 1825
  },
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'EXT', name: 'HDX 3-Outlet Indoor Extension Cord 6ft White',
    brand: 'HDX', price: 4.25, cost: 2.30, unit: 'pack', reorderLevel: 20, reorderQty: 40,
    attributes: '6 foot, 3 grounded polarized outlets, 13 Amp', supplierId: 'SUP-114', perishable: false, shelfLife: 3650
  },
  {
    dept: 'DGM', cat: 'HRD', catName: 'Hardware & Electrical', sub: 'LGT', name: 'Bic Multi-Purpose Utility Lighter 2-Pack',
    brand: 'Bic', price: 6.25, cost: 3.50, unit: 'pack', reorderLevel: 25, reorderQty: 50,
    attributes: '2 pack, Child-resistant long wand lighter', supplierId: 'SUP-113', perishable: false, shelfLife: 1825
  },

  // Pet Supplies
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'DOG', name: 'Purina Dog Chow Complete Adult Dry Dog Food 4.4 lb',
    brand: 'Purina', price: 6.75, cost: 4.10, unit: 'bag', reorderLevel: 25, reorderQty: 50,
    attributes: '4.4 lb bag, High quality protein with real chicken', supplierId: 'SUP-112', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'DOG', name: 'Pedigree Chopped Ground Dinner Beef Canned Dog Food 13.2oz',
    brand: 'Pedigree', price: 1.85, cost: 1.05, unit: 'can', reorderLevel: 48, reorderQty: 96,
    attributes: '13.2 oz can, Hearty beef loaf, Optimal nutrition', supplierId: 'SUP-112', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'DOG', name: 'Milk-Bone Original Medium Dog Biscuits 24oz',
    brand: 'Milk-Bone', price: 4.25, cost: 2.40, unit: 'box', reorderLevel: 30, reorderQty: 60,
    attributes: '24 oz box, Crunchy bone treats, Cleans teeth', supplierId: 'SUP-112', perishable: false, shelfLife: 540
  },
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'CAT', name: 'Friskies Seafood Sensations Dry Cat Food 3.15 lb',
    brand: 'Friskies', price: 5.50, cost: 3.20, unit: 'bag', reorderLevel: 25, reorderQty: 50,
    attributes: '3.15 lb bag, Salmon, Tuna, Shrimp & Crab flavors', supplierId: 'SUP-112', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'CAT', name: 'Friskies Shreds Variety Pack Canned Cat Food 5.5oz 12ct',
    brand: 'Friskies', price: 10.95, cost: 6.80, unit: 'box', reorderLevel: 20, reorderQty: 40,
    attributes: '12 cans x 5.5 oz, Shredded chunks in savory gravy', supplierId: 'SUP-112', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'PET', catName: 'Pet Supplies', sub: 'LIT', name: 'Tidy Cats 24/7 Performance Clumping Cat Litter 20 lb',
    brand: 'Tidy Cats', price: 11.50, cost: 7.20, unit: 'jug', reorderLevel: 20, reorderQty: 40,
    attributes: '20 lb jug, Continuous odor control, Strong clumps', supplierId: 'SUP-112', perishable: false, shelfLife: 1825
  },

  // School & Office Supplies
  {
    dept: 'DGM', cat: 'OFF', catName: 'Office & School', sub: 'NOT', name: '1-Subject Spiral Notebook Wide Ruled 70 Sheets',
    brand: 'Mead', price: 1.50, cost: 0.70, unit: 'notebook', reorderLevel: 50, reorderQty: 100,
    attributes: '70 sheets, 10.5 x 8 in, 3-hole punched, Assorted covers', supplierId: 'SUP-113', perishable: false, shelfLife: 3650
  },
  {
    dept: 'DGM', cat: 'OFF', catName: 'Office & School', sub: 'PEN', name: 'Bic Round Stic Ballpoint Pens Black Medium 10pk',
    brand: 'Bic', price: 1.95, cost: 0.95, unit: 'pack', reorderLevel: 40, reorderQty: 80,
    attributes: '10 count, 1.0mm medium point, Reliable ink flow', supplierId: 'SUP-113', perishable: false, shelfLife: 1095
  },
  {
    dept: 'DGM', cat: 'OFF', catName: 'Office & School', sub: 'CRA', name: 'Crayola Classic Color Crayons 24ct',
    brand: 'Crayola', price: 2.25, cost: 1.10, unit: 'box', reorderLevel: 40, reorderQty: 80,
    attributes: '24 vibrant non-toxic wax crayons, Tuck box', supplierId: 'SUP-113', perishable: false, shelfLife: 1825
  },
  {
    dept: 'DGM', cat: 'OFF', catName: 'Office & School', sub: 'GLU', name: 'Elmers Disappearing Purple Washable Glue Sticks 2pk',
    brand: 'Elmers', price: 1.75, cost: 0.85, unit: 'pack', reorderLevel: 40, reorderQty: 80,
    attributes: '2 sticks, 0.21 oz each, Goes on purple dries clear', supplierId: 'SUP-113', perishable: false, shelfLife: 730
  },
  {
    dept: 'DGM', cat: 'OFF', catName: 'Office & School', sub: 'MRK', name: 'Sharpie Fine Point Permanent Markers Black 2pk',
    brand: 'Sharpie', price: 2.75, cost: 1.40, unit: 'pack', reorderLevel: 35, reorderQty: 70,
    attributes: '2 pack, Quick-drying water-resistant permanent ink', supplierId: 'SUP-113', perishable: false, shelfLife: 1095
  },

  // Dollar General Value Valley ($1 - $2 items) & Snacks
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'CKY', name: 'Clover Valley Chocolate Sandwich Cookies 13oz',
    brand: 'Clover Valley', price: 1.85, cost: 0.90, unit: 'pack', reorderLevel: 50, reorderQty: 100,
    attributes: '13 oz, Chocolate cookies with vanilla creme filling', supplierId: 'SUP-115', perishable: false, shelfLife: 270
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'CRK', name: 'Clover Valley Saltine Crackers Fresh Stacks 16oz',
    brand: 'Clover Valley', price: 1.75, cost: 0.85, unit: 'box', reorderLevel: 50, reorderQty: 100,
    attributes: '16 oz, 4 fresh stacks, Crisp lightly salted', supplierId: 'SUP-115', perishable: false, shelfLife: 240
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'MAC', name: 'Clover Valley Macaroni & Cheese Dinner 7.25oz',
    brand: 'Clover Valley', price: 0.85, cost: 0.38, unit: 'box', reorderLevel: 80, reorderQty: 160,
    attributes: '7.25 oz, Elbow macaroni with creamy cheese sauce mix', supplierId: 'SUP-115', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'PNT', name: 'Clover Valley Creamy Peanut Butter 16oz',
    brand: 'Clover Valley', price: 2.25, cost: 1.15, unit: 'jar', reorderLevel: 40, reorderQty: 80,
    attributes: '16 oz jar, Smooth roasted peanut spread, Gluten free', supplierId: 'SUP-115', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'CND', name: 'Haribo Goldbears Gummi Candy Share Size 5oz',
    brand: 'Haribo', price: 1.50, cost: 0.75, unit: 'bag', reorderLevel: 50, reorderQty: 100,
    attributes: '5 oz bag, Assorted fruit flavors, The original gummi bear', supplierId: 'SUP-115', perishable: false, shelfLife: 365
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'TEA', name: 'Arizona Green Tea with Ginseng & Honey 23oz Tall Can',
    brand: 'Arizona', price: 0.99, cost: 0.52, unit: 'can', reorderLevel: 72, reorderQty: 144,
    attributes: '23 fl oz big can, 100% natural tea with honey', supplierId: 'SUP-106', perishable: false, shelfLife: 540
  },
  {
    dept: 'DGM', cat: 'VAL', catName: 'Value Valley Foods', sub: 'NUT', name: 'Clover Valley Roasted & Salted Peanuts 16oz',
    brand: 'Clover Valley', price: 2.50, cost: 1.20, unit: 'canister', reorderLevel: 35, reorderQty: 70,
    attributes: '16 oz canister, Dry roasted peanuts seasoned with sea salt', supplierId: 'SUP-115', perishable: false, shelfLife: 365
  }
];

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

  // Load retail demo dataset (80 items)
  const retailDemoPath = '/Users/austin.gonyou/Downloads/Apps/couchbase-lite-retail-demo/dataset/demo-dataset/aa_store_inventory.json';
  const rawGrocery = JSON.parse(fs.readFileSync(retailDemoPath, 'utf-8'));

  console.log(`Loaded ${rawGrocery.length} items from retail demo dataset.`);

  // Mapping retail demo categories to SKU category codes
  const catCodeMap = {
    'Dairy': { code: 'DAIR', sup: 'SUP-101', shelfLife: 14 },
    'Beverages': { code: 'BEV', sup: 'SUP-106', shelfLife: 180 },
    'Meat': { code: 'MEAT', sup: 'SUP-103', shelfLife: 7 },
    'Seafood': { code: 'SEA', sup: 'SUP-104', shelfLife: 5 },
    'Bakery': { code: 'BAK', sup: 'SUP-102', shelfLife: 8 },
    'Produce': { code: 'PROD', sup: 'SUP-105', shelfLife: 10 },
    'Pantry': { code: 'PAN', sup: 'SUP-107', shelfLife: 365 },
    'Snacks': { code: 'SNK', sup: 'SUP-115', shelfLife: 180 },
    'Household': { code: 'HOU', sup: 'SUP-108', shelfLife: 730 },
    'Personal Care': { code: 'PER', sup: 'SUP-111', shelfLife: 540 }
  };

  const masterCatalog = [];
  let upcCounter = 10001;

  // Process Grocery Items
  rawGrocery.forEach((item, index) => {
    const meta = catCodeMap[item.category] || { code: 'GEN', sup: 'SUP-107', shelfLife: 180 };
    const num = String(1000 + index).padStart(4, '0');
    const sku = `SKU-GRC-${meta.code}-${num}`;
    const upc = generateUPC(1000000000 + upcCounter);
    upcCounter++;

    const price = Math.round(item.price * 100) / 100;
    const cost = Math.round((price * 0.6) * 100) / 100;
    const reorderLevel = Math.max(15, Math.floor((item.stockQty || 50) * 0.35));
    const reorderQty = reorderLevel * 2;

    const supplier = SUPPLIERS.find(s => s.supplier_id === meta.sup) || SUPPLIERS[0];

    masterCatalog.push({
      type: 'catalogue_item',
      team: 'crew-a',
      sku: sku,
      code: {
        type: 'upc',
        value: upc
      },
      name: item.name,
      brand: item.brand || 'BudgetBest',
      category: item.category,
      subcategory: item.category,
      department: 'Grocery',
      unit: item.unit || 'unit',
      unit_price: price,
      unit_cost: cost,
      reorder_level: reorderLevel,
      reorder_quantity: reorderQty,
      safety_stock: Math.floor(reorderLevel * 0.5),
      supplier: supplier,
      attributes: typeof item.attributes === 'object' ? Object.entries(item.attributes).map(([k, v]) => `${k}: ${v}`).join(', ') : (item.attributes || ''),
      perishable: item.attributes?.perishable === true || meta.shelfLife < 30,
      shelf_life_days: meta.shelfLife,
      captured_by: 'system_seed',
      captured_at: new Date().toISOString()
    });
  });

  // Process Dollar General Items
  DOLLAR_GENERAL_ITEMS.forEach((dg, index) => {
    const num = String(2000 + index).padStart(4, '0');
    const sku = `SKU-DGM-${dg.cat}-${num}`;
    const upc = generateUPC(2000000000 + upcCounter);
    upcCounter++;

    const supplier = SUPPLIERS.find(s => s.supplier_id === dg.supplierId) || SUPPLIERS[7];

    masterCatalog.push({
      type: 'catalogue_item',
      team: 'crew-a',
      sku: sku,
      code: {
        type: 'upc',
        value: upc
      },
      name: dg.name,
      brand: dg.brand,
      category: dg.catName,
      subcategory: dg.sub,
      department: 'Dollar General Merchandise',
      unit: dg.unit,
      unit_price: dg.price,
      unit_cost: dg.cost,
      reorder_level: dg.reorderLevel,
      reorder_quantity: dg.reorderQty,
      safety_stock: Math.floor(dg.reorderLevel * 0.5),
      supplier: supplier,
      attributes: dg.attributes,
      perishable: dg.perishable,
      shelf_life_days: dg.shelfLife,
      captured_by: 'system_seed',
      captured_at: new Date().toISOString()
    });
  });

  console.log(`Total Master Products generated: ${masterCatalog.length}`);

  // 5. Seed Catalog Documents
  console.log('Seeding Master Catalog to "catalog" collection...');
  for (const item of masterCatalog) {
    const docId = `catalogue::upc::${item.code.value}`;
    await catalogColl.upsert(docId, item);
  }
  console.log(`Seeded ${masterCatalog.length} products to catalog.`);

  // 6. Build and Seed Locations
  console.log('Building and seeding Locations...');
  const locations = [];
  const aisles = [
    { aisle: 'Aisle 1', name: 'Fresh Produce & Fruits', dept: 'Produce' },
    { aisle: 'Aisle 2', name: 'Bakery & Fresh Bread', dept: 'Bakery' },
    { aisle: 'Aisle 3', name: 'Meat & Poultry Counter', dept: 'Meat' },
    { aisle: 'Aisle 4', name: 'Dairy & Egg Coolers', dept: 'Dairy' },
    { aisle: 'Aisle 5', name: 'Pantry, Grains & Pasta', dept: 'Pantry' },
    { aisle: 'Aisle 6', name: 'Beverages, Coffee & Juices', dept: 'Beverages' },
    { aisle: 'Aisle 7', name: 'Snacks, Chips & Crackers', dept: 'Snacks' },
    { aisle: 'Aisle 8', name: 'Cleaning & Paper Consumables', dept: 'Household & Cleaning' },
    { aisle: 'Aisle 9', name: 'Health, Beauty & First Aid', dept: 'Health & Beauty' },
    { aisle: 'Aisle 10', name: 'Hardware, Batteries & Office', dept: 'Hardware & Electrical' },
    { aisle: 'Aisle 11', name: 'Pet Care & Companion Foods', dept: 'Pet Supplies' },
    { aisle: 'Aisle 12', name: 'Value Valley $1-$2 Specials', dept: 'Value Valley Foods' }
  ];

  for (const store of STORES) {
    for (const a of aisles) {
      for (let s = 1; s <= 3; s++) {
        for (let b = 1; b <= 4; b++) {
          const locDoc = {
            type: 'location',
            name: `${store.name} / ${a.aisle} / Shelf ${s} / Bin ${b}`,
            location: {
              site: store.site,
              rack: a.aisle,
              shelf: `Shelf ${s}`,
              bin: `Bin ${b}`
            },
            store_id: store.store_id,
            department: a.dept,
            qr: `LOC::${store.site.toUpperCase()}::A${a.aisle.replace('Aisle ', '')}-S0${s}-B0${b}`,
            notes: `${a.name} in ${store.city}`
          };
          const locId = `location::${store.site}::a${a.aisle.replace('Aisle ', '')}_s${s}_b${b}`;
          locations.push({ id: locId, doc: locDoc });
          await locationsColl.upsert(locId, locDoc);
        }
      }
    }
  }
  console.log(`Seeded ${locations.length} store locations.`);

  // 7. Generate Multi-Store Counts (inventory.counts)
  console.log('Generating Multi-Store Counts and Inventory Scenarios...');
  let countsCount = 0;
  const now = Date.now();

  for (const store of STORES) {
    for (let i = 0; i < masterCatalog.length; i++) {
      const item = masterCatalog[i];

      // Multi-store variation logic:
      // Store 1 (Downtown): High turnover flagship, well-stocked, occasional near-expiry on perishables
      // Store 2 (Nomad Westside): Moderate turnover, some items understocked
      // Store 3 (Nomad Express): Fast beverage/snack sales, stockouts on bulky cleaning/paper items
      let stockQty = 0;
      let status = 'in_stock';
      let confidence = 100;
      let needsReview = false;
      let countIsEstimate = false;

      const baseLevel = item.reorder_level;

      if (store.store_id === 'store-001') {
        // Flagship
        if (i % 11 === 0 && item.perishable) {
          // Near expiry / needs review scenario
          stockQty = Math.floor(baseLevel * 1.8);
          needsReview = true;
          confidence = 65;
        } else if (i % 17 === 0) {
          // Overstocked candidate for transfer
          stockQty = Math.floor(baseLevel * 2.8);
          status = 'overstocked';
        } else {
          stockQty = Math.floor(baseLevel * (1.2 + (i % 7) * 0.15));
        }
      } else if (store.store_id === 'store-002') {
        // Westside
        if (i % 17 === 0) {
          // Severely depleted item that store 1 has in excess! (Inter-store transfer trigger)
          stockQty = Math.floor(baseLevel * 0.15);
          status = stockQty === 0 ? 'out_of_stock' : 'low_stock';
        } else if (i % 9 === 0) {
          // Normal low stock trigger
          stockQty = Math.floor(baseLevel * 0.6);
          status = 'low_stock';
        } else {
          stockQty = Math.floor(baseLevel * (0.9 + (i % 5) * 0.2));
        }
      } else {
        // Express store (store-003)
        if (item.department === 'Dollar General Merchandise' && ['CLN', 'HRD', 'PAP'].includes(item.subcategory)) {
          // Out of stock on bulky general merchandise
          stockQty = (i % 4 === 0) ? 0 : Math.floor(baseLevel * 0.3);
          status = stockQty === 0 ? 'out_of_stock' : 'low_stock';
        } else if (item.category === 'Beverages' || item.category === 'Snacks' || item.category === 'Value Valley Foods') {
          // High turnover on grab-and-go
          stockQty = Math.floor(baseLevel * 1.4);
        } else {
          stockQty = Math.floor(baseLevel * 0.8);
        }

        // Random estimate audit test
        if (i % 13 === 0) {
          countIsEstimate = true;
          confidence = 70;
        }
      }

      if (stockQty <= 0) {
        stockQty = 0;
        status = 'out_of_stock';
      } else if (stockQty <= item.reorder_level) {
        status = 'low_stock';
      }

      // Pick an aisle matching category
      let aisleIndex = (i % aisles.length) + 1;
      const shelfNum = (i % 3) + 1;
      const binNum = (i % 4) + 1;

      // Dates
      const daysAgoReceived = (i % 14) + 1;
      const receivedDate = new Date(now - (daysAgoReceived * 86400000)).toISOString();
      const expirationDate = item.perishable
        ? new Date(now + ((item.shelf_life_days - daysAgoReceived) * 86400000)).toISOString()
        : new Date(now + (item.shelf_life_days * 86400000)).toISOString();

      const countDoc = {
        type: 'count',
        kind: 'entry',
        team: 'crew-a',
        item_name: item.name,
        count: stockQty,
        count_is_estimate: countIsEstimate,
        attributes: item.attributes,
        annotation: status === 'out_of_stock'
          ? 'Shelf empty. Reorder required.'
          : (status === 'low_stock' ? 'Low shelf facing. Backroom stock exhausted.' : 'Normal facing, audit verified.'),
        location: {
          site: store.site,
          rack: `Aisle ${aisleIndex}`,
          shelf: `Shelf ${shelfNum}`,
          bin: `Bin ${binNum}`
        },
        source: countIsEstimate ? 'voice' : 'code',
        code: item.code,
        confidence: confidence,
        needs_review: needsReview,
        captured_at: new Date(now - ((i % 12) * 3600000)).toISOString(),
        captured_by: 'agent-intepros-01',
        captured_by_name: 'IntePros Inventory Agent',
        // Rich Extrapolated Analytics & Supply Chain Fields:
        sku: item.sku,
        store_id: store.store_id,
        store_name: store.name,
        stock_quantity: stockQty,
        reserved_quantity: Math.min(3, Math.floor(stockQty * 0.1)),
        reorder_level: item.reorder_level,
        reorder_quantity: item.reorder_quantity,
        stock_status: status,
        sales_volume_30d: Math.floor(item.reorder_quantity * (1.5 + (i % 5) * 0.3)),
        inventory_turnover_rate: Math.round(((30 / Math.max(1, item.shelf_life_days)) * 2.5) * 10) / 10,
        date_received: receivedDate,
        expiration_date: expirationDate,
        last_audit_date: new Date().toISOString()
      };

      const countId = `count::${store.store_id}::${item.sku}`;
      await countsColl.upsert(countId, countDoc);
      countsCount++;
    }
  }

  console.log(`Seeded ${countsCount} multi-store count documents into "counts" collection.`);

  // Validation queries
  console.log('\n--- Running Validation Queries ---');
  const catCount = await cluster.query('SELECT count(*) as cnt FROM `inventorycount`.inventory.catalog');
  const countsTotal = await cluster.query('SELECT count(*) as cnt FROM `inventorycount`.inventory.counts');
  const locTotal = await cluster.query('SELECT count(*) as cnt FROM `inventorycount`.inventory.locations');

  console.log(`Verified collection counts:`);
  console.log(`  - catalog:   ${catCount.rows[0].cnt} items`);
  console.log(`  - counts:    ${countsTotal.rows[0].cnt} store records`);
  console.log(`  - locations: ${locTotal.rows[0].cnt} locations`);

  // Sample Multi-Store Agent Query: Low stock in Store 2 that is overstocked in Store 1
  const rebalanceQuery = await cluster.query(`
    SELECT s2.sku, s2.item_name, s2.stock_quantity as westside_qty, s1.stock_quantity as downtown_qty
    FROM \`inventorycount\`.inventory.counts s2
    JOIN \`inventorycount\`.inventory.counts s1 ON KEYS ('count::store-001::' || s2.sku)
    WHERE s2.store_id = 'store-002' AND s2.stock_status IN ['low_stock', 'out_of_stock']
      AND s1.stock_status = 'overstocked'
    LIMIT 5
  `);
  console.log('\n--- Sample Agent Query: Inter-Store Rebalancing Candidates ---');
  console.log(JSON.stringify(rebalanceQuery.rows, null, 2));

  await cluster.close();
  console.log('\nSeeding completed successfully!');
}

main().catch(err => {
  console.error('Fatal error during seeding:', err);
  process.exit(1);
});
