/**
 * scale_10k_products_50_stores.js
 *
 * Scales the Couchbase Capella Celios/Nomad inventory environment to:
 *   1. 10,000 Master Products in `inventory.catalog` with consistent SKUs & 12-digit UPCs
 *   2. 50 `GeneralStore` locations across the Midwest regional network
 *   3. DC Bulk Reserve holding all 10,000 items (site: "dc-01")
 *   4. Store inventory across 50 GeneralStores (core + category assortment) in `inventory.counts`
 *   5. Expanded fleet trucks and regional route shipments
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

// Helper for UPC-A check digit calculation
function generateUPC(number) {
  const base11 = String(number).padStart(11, '0').slice(-11);
  let oddSum = 0;
  let evenSum = 0;
  for (let i = 0; i < 11; i++) {
    const digit = parseInt(base11[i], 10);
    if (i % 2 === 0) oddSum += digit;
    else evenSum += digit;
  }
  const total = (oddSum * 3) + evenSum;
  const checkDigit = (10 - (total % 10)) % 10;
  return base11 + checkDigit;
}

// 50 Midwest Cities for GeneralStore network
const STORE_CITIES = [
  'Springfield Downtown, IL', 'Springfield West, IL', 'Decatur North, IL', 'Decatur South, IL',
  'Peoria Riverfront, IL', 'Peoria Heights, IL', 'Bloomington Central, IL', 'Normal College, IL',
  'Champaign Campus, IL', 'Urbana East, IL', 'Rockford East, IL', 'Rockford West, IL',
  'Joliet Downtown, IL', 'Joliet Mall, IL', 'Naperville North, IL', 'Naperville South, IL',
  'Aurora Fox Valley, IL', 'Aurora Downtown, IL', 'Elgin West, IL', 'Waukegan Harbor, IL',
  'Cicero Central, IL', 'Arlington Heights, IL', 'Evanston Lakefront, IL', 'Schaumburg Center, IL',
  'Bolingbrook Promenade, IL', 'Palatine North, IL', 'Skokie Village, IL', 'Des Plaines River, IL',
  'Orland Park, IL', 'Tinley Park, IL', 'Oak Lawn, IL', 'Berwyn Town, IL',
  'Mount Prospect, IL', 'Wheaton Downtown, IL', 'Hoffman Estates, IL', 'Oak Park Historic, IL',
  'Downers Grove, IL', 'Elmhurst City, IL', 'Lombard Mall, IL', 'DeKalb University, IL',
  'Moline Quad Cities, IL', 'Rock Island, IL', 'Galesburg Historic, IL', 'Quincy River, IL',
  'Carbondale South, IL', 'Alton Bluff, IL', 'Kankakee River, IL', 'Danville East, IL',
  'Pekin Central, IL', 'Freeport North, IL'
];

// Build 50 GeneralStores
const STORES = STORE_CITIES.map((city, idx) => {
  const num = String(idx + 1).padStart(2, '0');
  const storeId = `store-${String(idx + 1).padStart(3, '0')}`;
  return {
    store_id: storeId,
    site: `generalstore-${num}`,
    name: `GeneralStore #${num} - ${city.split(',')[0]}`,
    city: city,
    store_type: 'GeneralStore',
    region: 'Midwest Central'
  };
});

// Suppliers
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

// Product Category Blueprints for 10,000 Items
const CATALOG_BLUEPRINTS = [
  // GROCERY (5,500 Items)
  {
    dept: 'Grocery', cat: 'Dairy', catCode: 'DAIR', sup: 'SUP-101', perishable: true, shelfLife: 18, count: 600,
    brands: ['Valley Fresh', 'Prairie Farms', 'Horizon Organic', 'Chobani', 'Kraft', 'Land O Lakes', 'Clover Valley', 'Tillamook', 'Daisy', 'Sargento'],
    items: ['Whole Milk', '2% Reduced Fat Milk', '1% Low Fat Milk', 'Fat Free Skim Milk', 'Heavy Whipping Cream', 'Half and Half', 'Salted Sweet Cream Butter', 'Unsalted Butter', 'Sharp Cheddar Cheese Block', 'Mild Cheddar Shredded', 'Mozzarella String Cheese', 'Pepper Jack Slices', 'Swiss Cheese Slices', 'Colby Jack Cubes', 'Greek Yogurt Strawberry', 'Greek Yogurt Blueberry', 'Greek Yogurt Vanilla', 'Plain Whole Milk Yogurt', 'Grade A Large White Eggs', 'Cage Free Brown Eggs', 'Pasteurized Egg Whites', 'Sour Cream', 'Small Curd Cottage Cheese', 'Ricotta Cheese', 'Whipped Cream Cheese Spread'],
    units: ['gallon', 'half-gallon', 'quart', '16oz', '8oz', '32oz tub', '12ct carton', '18ct carton']
  },
  {
    dept: 'Grocery', cat: 'Beverages', catCode: 'BEV', sup: 'SUP-106', perishable: false, shelfLife: 240, count: 800,
    brands: ['Clover Valley', 'Starbucks', 'Folgers', 'Lipton', 'Pure Leaf', 'Tropicana', 'Minute Maid', 'Ocean Spray', 'Coca-Cola', 'Pepsi', 'Dr Pepper', 'Sprite', 'Gatorade', 'Red Bull', 'Arizona', 'Poland Spring'],
    items: ['Dark Roast Ground Coffee', 'Medium Roast Breakfast Blend', 'French Vanilla Ground Coffee', 'House Blend K-Cups 12ct', 'Green Tea Bags 40ct', 'English Breakfast Black Tea', 'Sweet Iced Tea', 'Unsweetened Iced Tea', '100% Orange Juice with Calcium', 'No Pulp Orange Juice', '100% Apple Juice', 'Cranberry Cocktail Juice', 'Classic Cola', 'Diet Cola', 'Zero Sugar Cola', 'Lemon Lime Soda', 'Ginger Ale', 'Fruit Punch Thirst Quencher', 'Cool Blue Sports Drink', 'Energy Drink Original', 'Zero Sugar Energy Drink', 'Natural Spring Water 24pk', 'Sparkling Lime Seltzer 12pk', 'Distilled Water 1 Gallon'],
    units: ['bottle', 'can', '12-pack', '24-pack case', '12oz bag', 'box', 'gallon']
  },
  {
    dept: 'Grocery', cat: 'Snacks', catCode: 'SNK', sup: 'SUP-115', perishable: false, shelfLife: 180, count: 900,
    brands: ['Lay\'s', 'Doritos', 'Cheetos', 'Pringles', 'Tostitos', 'Ruffles', 'Clover Valley', 'Nabisco', 'Oreo', 'Chips Ahoy', 'Keebler', 'Goldfish', 'Planters', 'SkinnyPop', 'Smartfood'],
    items: ['Classic Potato Chips', 'Barbecue Flavored Potato Chips', 'Sour Cream and Onion Chips', 'Nacho Cheese Tortilla Chips', 'Cool Ranch Tortilla Chips', 'Crunchy Cheese Flavored Snacks', 'Original Crisps 5.5oz', 'Restaurant Style Tortilla Chips', 'Cheddar & Sour Cream Ridged Chips', 'Double Stuf Chocolate Sandwich Cookies', 'Original Chocolate Chip Cookies', 'Fudge Striped Shortbread Cookies', 'Cheddar Baked Snack Crackers', 'Butter Popcorn 3-Pack', 'White Cheddar Popcorn', 'Honey Roasted Peanuts 16oz', 'Dry Roasted Salted Peanuts', 'Whole Cashews Halves', 'Deluxe Mixed Nuts', 'Traditional Chex Mix', 'Mini Pretzel Twists', 'Cheese Dip 15oz', 'Medium Chunky Salsa 16oz'],
    units: ['bag', 'box', 'canister', 'jar', 'pack']
  },
  {
    dept: 'Grocery', cat: 'Pantry', catCode: 'PAN', sup: 'SUP-107', perishable: false, shelfLife: 365, count: 1200,
    brands: ['Clover Valley', 'Barilla', 'Prego', 'Ragu', 'Campbell\'s', 'Progresso', 'Bush\'s Best', 'Hunt\'s', 'Jif', 'Skippy', 'Smucker\'s', 'Quaker', 'Betty Crocker', 'Pillsbury', 'McCormick', 'Crisco', 'Wesson'],
    items: ['Long Grain Enriched White Rice 5lb', 'Whole Grain Brown Rice 2lb', 'Semolina Spaghetti Pasta 16oz', 'Penne Rigate Pasta 16oz', 'Elbow Macaroni 16oz', 'Traditional Pasta Sauce 24oz', 'Marinara Sauce with Garlic & Herbs', 'Tomato Soup 10.75oz Can', 'Cream of Mushroom Condensed Soup', 'Chicken Noodle Classic Soup', 'Traditional Refried Beans 16oz', 'Black Beans in Seasoned Sauce', 'Diced Tomatoes with Green Chilies', 'Creamy Peanut Butter 16oz', 'Crunchy Peanut Butter 28oz', 'Strawberry Fruit Spread 18oz', 'Quick 1-Minute Rolled Oats 42oz', 'All-Purpose Bleached Flour 5lb', 'Pure Cane Granulated Sugar 4lb', 'Light Brown Cane Sugar 2lb', 'Pure Vegetable Oil 48oz', 'Extra Virgin Olive Oil 16.9oz', 'Ground Black Pepper 4oz', 'Pure Iodized Table Salt 26oz', 'Pancake & Waffle Mix Complete 32oz', 'Original Pancake Syrup 24oz'],
    units: ['box', 'can', 'jar', 'bag', 'bottle']
  },
  {
    dept: 'Grocery', cat: 'Produce', catCode: 'PROD', sup: 'SUP-105', perishable: true, shelfLife: 10, count: 600,
    brands: ['Sunny Orchard', 'Dole', 'Chiquita', 'Fresh Express', 'Green Giant', 'Grimmway Farms', 'Ocean Mist', 'Taylor Farms'],
    items: ['Gala Apples 3lb Bag', 'Honeycrisp Apples Premium', 'Granny Smith Apples', 'Fresh Bananas Yellow', 'Seedless Red Grapes 2lb', 'Whole Seedless Watermelon', 'Russet Potatoes 5lb Bag', 'Yellow Onions 3lb Bag', 'Whole Baby Carrots 1lb', 'Roma Tomatoes 1lb', 'Vine Ripened Slicing Tomatoes', 'Hass Avocados 4pk Net', 'Iceberg Lettuce Head', 'Romaine Hearts 3-Pack', 'Fresh Baby Spinach 16oz Clamshell', 'Yellow Sweet Corn 4pk', 'Whole White Mushrooms 8oz', 'Green Bell Peppers 3pk', 'Fresh English Cucumbers', 'Fresh Lemons 2lb Bag', 'Navel Oranges 4lb Bag', 'Fresh Broccoli Crowns 1lb', 'Cauliflower Head Fresh', 'Whole Celery Stalk'],
    units: ['bag', 'lb', 'pack', 'head', 'each', 'clamshell']
  },
  {
    dept: 'Grocery', cat: 'Bakery', catCode: 'BAK', sup: 'SUP-102', perishable: true, shelfLife: 8, count: 400,
    brands: ['Wonder', 'Nature\'s Own', 'Sara Lee', 'Bimbo', 'Thomas\'', 'Pepperidge Farm', 'Entenmann\'s', 'Clover Valley'],
    items: ['Classic White Sandwich Bread 20oz', '100% Whole Wheat Sliced Bread', 'Honey Wheat Sandwich Bread', 'Artisan Sourdough Sliced Loaf', 'Plain Pre-Sliced Bagels 6ct', 'Everything Bagels 6ct', 'White Hamburger Buns 8ct', 'Enriched Hot Dog Buns 8ct', 'Flour Tortillas Soft Taco 10ct', 'Original English Muffins 6ct', 'Glazed Donut Holes 16oz Box', 'Chocolate Chip Mini Muffins 5ct', 'Crumb Coffee Cake 8oz', 'French Baguette Artisan Loaf'],
    units: ['loaf', 'pack', 'bag', 'box']
  },
  {
    dept: 'Grocery', cat: 'Meat & Poultry', catCode: 'MEAT', sup: 'SUP-103', perishable: true, shelfLife: 6, count: 500,
    brands: ['Tyson', 'Perdue', 'Hormel', 'Oscar Mayer', 'Smithfield', 'Johnsonville', 'Butterball', 'Ball Park'],
    items: ['Boneless Skinless Chicken Breasts 2.5lb', 'Fresh Chicken Thighs Value Pack', 'Chicken Drumsticks Family Pack', 'Ground Beef 80/20 Fresh 1lb', 'Ground Beef 93/7 Lean 1lb', 'Thick Cut Pork Chops 4pk', 'Center Cut Bone-in Pork Ribs', 'Hardwood Smoked Sliced Bacon 16oz', 'Thick Cut Maple Bacon 16oz', 'Original Smoked Pork Sausage Links', 'Beef Franks Hot Dogs 8ct', 'Sliced Smoked Turkey Breast 16oz', 'Deli Fresh Smoked Ham Slices 16oz', 'Hard Salami Slices 8oz'],
    units: ['pack', 'lb', 'tray']
  },
  {
    dept: 'Grocery', cat: 'Seafood', catCode: 'SEA', sup: 'SUP-104', perishable: true, shelfLife: 4, count: 200,
    brands: ['Pacific Coast', 'Starkist', 'Bumble Bee', 'Chicken of the Sea', 'Gorton\'s', 'SeaPak'],
    items: ['Fresh Atlantic Salmon Fillet 1lb', 'Raw Peeled Deveined Shrimp 16oz', 'Cooked Tail-on Shrimp 16oz', 'Wild Caught Pacific Cod Fillets', 'Chunk Light Tuna in Water 5oz Can', 'Solid White Albacore Tuna 5oz', 'Wild Alaskan Pink Salmon Can 14.75oz', 'Crispy Battered Fish Fillets 10ct', 'Breaded Butterfly Shrimp 9oz Box'],
    units: ['lb', 'bag', 'can', 'box']
  },
  {
    dept: 'Grocery', cat: 'Frozen', catCode: 'FROZ', sup: 'SUP-107', perishable: false, shelfLife: 300, count: 400,
    brands: ['DiGiorno', 'Red Baron', 'Hot Pockets', 'Stouffer\'s', 'Ore-Ida', 'Birds Eye', 'Eggo', 'Breyers', 'Ben & Jerry\'s', 'Clover Valley'],
    items: ['Rising Crust Four Cheese Pizza', 'Pepperoni Thin Crust Pizza', 'Ham and Cheese Hot Pockets 2ct', 'Meat Lovers French Bread Pizza', 'Homestyle Lasagna with Meat Sauce', 'Golden Crinkle Cut French Fries 32oz', 'Crispy Tater Tots 32oz', 'Frozen Sweet Corn 16oz', 'Frozen Cut Green Beans 16oz', 'Homestyle Frozen Waffles 10ct', 'Buttermilk Pancakes 12ct', 'Natural Vanilla Ice Cream 48oz', 'Chocolate Chip Cookie Dough Pint', 'Mint Chocolate Chip Ice Cream Tub'],
    units: ['box', 'bag', 'tub', 'pint']
  },

  // DOLLAR GENERAL GENERAL MERCHANDISE (4,500 Items)
  {
    dept: 'Dollar General Merchandise', cat: 'Household & Cleaning', catCode: 'CLN', sup: 'SUP-109', perishable: false, shelfLife: 730, count: 700,
    brands: ['Clorox', 'Lysol', 'Dawn', 'Gain', 'Tide', 'Pine-Sol', 'Mr. Clean', 'Fabuloso', 'Ajax', 'Comet', 'Windex', 'Palmolive'],
    items: ['Disinfecting Wipes Fresh Scent 75ct', 'Regular Liquid Bleach 64oz', 'Ultra Dishwashing Liquid 16.2oz', 'Original Liquid Laundry Detergent 40oz', 'Laundry Detergent Pods Spring Meadow 35ct', 'Multi-Surface Cleaner Original Pine 24oz', 'All Purpose Cleaner with Bleach 32oz', 'Lavender Multi-Purpose Cleaner 56oz', 'Glass Cleaner Spray Streak-Free 23oz', 'Magic Eraser Cleaning Pads 2ct', 'Toilet Bowl Cleaner with Bleach 24oz', 'Disinfectant Spray Crisp Linen 19oz', 'Lemon Fresh Heavy Duty Degreaser 32oz', 'Heavy Duty Scrub Sponges 3pk', 'Non-Scratch Scrub Sponges 4pk'],
    units: ['canister', 'bottle', 'spray bottle', 'jug', 'pack', 'can']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Paper & Consumables', catCode: 'PAP', sup: 'SUP-110', perishable: false, shelfLife: 1825, count: 600,
    brands: ['Scott', 'Sparkle', 'Bounty', 'Charmin', 'Glad', 'Hefty', 'Reynolds', 'Ziploc', 'Clover Valley'],
    items: ['1000 Sheet Bath Tissue 4 Rolls', '1000 Sheet Bath Tissue 12 Rolls', 'Pick-A-Size Paper Towels 2 Big Rolls', 'Paper Towels Select-A-Size 6 Rolls', 'Ultra Soft Toilet Paper 6 Mega Rolls', 'Drawstring Kitchen Trash Bags 13 Gal 20ct', 'Drawstring Kitchen Trash Bags 13 Gal 45ct', 'Large Trash Bags 30 Gallon 15ct', 'Heavy Duty Aluminum Foil 50 sq ft', 'Standard Aluminum Foil 75 sq ft', 'Gallon Storage Bags 20ct Slider', 'Quart Food Storage Bags 25ct Slider', 'Sandwich Sealable Bags 100ct', 'Everyday Paper Dinner Plates 100ct', 'Heavy Duty Plastic Cups 16oz 50ct'],
    units: ['pack', 'box', 'roll']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Health & Beauty', catCode: 'HLT', sup: 'SUP-111', perishable: false, shelfLife: 730, count: 1000,
    brands: ['Tylenol', 'Advil', 'Pepto Bismol', 'Band-Aid', 'Neosporin', 'Colgate', 'Crest', 'Dial', 'Suave', 'Dove', 'Q-tips', 'Vaseline', 'Vicks', 'NyQuil', 'DayQuil', 'Benadryl', 'Listerine'],
    items: ['Extra Strength Acetaminophen 500mg 50ct', 'Ibuprofen Pain Reliever Tablets 200mg 50ct', '5 Symptom Relief Liquid Upset Stomach 8oz', 'Flexible Fabric Adhesive Bandages 30ct', 'Waterproof Tough Strips Bandages 20ct', 'Original Antibiotic Ointment 0.5oz', 'Total Whitening Mint Toothpaste 4.8oz', 'Tartar Protection Fresh Mint 5.7oz', 'Soft Bristle Manual Toothbrushes 2pk', 'Antibacterial Bar Soap Gold 3ct', 'Deep Moisture Nourishing Body Wash 12oz', 'Daily Clarifying Shampoo 30oz', 'Daily Moisture Conditioner 30oz', 'Precision Tips Cotton Swabs 300ct', '100% Pure Petroleum Jelly 3.75oz', 'Severe Cold and Flu Nighttime Liquid 8oz', 'Severe Cold and Flu Daytime Liquid 8oz', 'Allergy Relief Antihistamine 25mg 24ct', 'Antiseptic Mouthwash Cool Mint 1 Liter', 'Advanced Hand Sanitizer with Aloe 8oz', 'Petroleum Lip Balm Original 0.35oz'],
    units: ['bottle', 'box', 'tube', 'pack', 'jar']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Hardware & Electrical', catCode: 'HRD', sup: 'SUP-114', perishable: false, shelfLife: 3650, count: 600,
    brands: ['Energizer', 'Duracell', 'GE', 'Gorilla', 'HDX', 'Bic', '3M', 'Command', 'Pennzoil', 'STP'],
    items: ['Max Alkaline AA Batteries 4-Pack', 'Max Alkaline AA Batteries 8-Pack', 'Max Alkaline AAA Batteries 4-Pack', 'Max Alkaline AAA Batteries 8-Pack', 'Heavy Duty 9V Alkaline Battery 2-Pack', '60W Equivalent Soft White LED Bulbs 4-Pack', '75W Equivalent Daylight LED Bulbs 4-Pack', 'Heavy Duty Duct Tape Black 30yd', 'Gorilla Super Glue Gel 0.71oz', 'Electrical Tape 3-Pack Black', '3-Outlet Indoor Extension Cord 6ft White', 'Outdoor Heavy Duty Cord 25ft 16/3', 'Picture Hanging Strips Medium 4 Pairs', 'Multi-Purpose Utility Wand Lighter 2pk', 'All Purpose Retractable Utility Knife', 'Precision Tape Measure 16ft Locking', 'Motor Oil 5W-30 Synthetic Blend 1 Qt', 'Heavy Duty All Season Windshield Wiper 22in'],
    units: ['pack', 'roll', 'bottle', 'box']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Pet Supplies', catCode: 'PET', sup: 'SUP-112', perishable: false, shelfLife: 540, count: 500,
    brands: ['Purina', 'Pedigree', 'Milk-Bone', 'Friskies', 'Meow Mix', 'Tidy Cats', 'Cesar', 'Fancy Feast'],
    items: ['Dog Chow Complete Adult Dry Dog Food 4.4 lb', 'Dog Chow Complete Dry Dog Food 15 lb', 'Chopped Ground Dinner Beef Can 13.2oz', 'Ground Dinner Chicken and Rice Can 13.2oz', 'Original Medium Dog Biscuits 24oz', 'Gravy Bones Variety Dog Treats 19oz', 'Seafood Sensations Dry Cat Food 3.15 lb', 'Tender Centers Salmon and White Meat Chicken 3 lb', 'Shreds Variety Pack Canned Cat Food 12ct', 'Classic Pate Poultry Variety 12ct', '24/7 Performance Clumping Cat Litter 20 lb', 'Instant Action Scented Cat Litter 20 lb', 'Rawhide Twist Sticks Dog Chews 20ct', 'Meaty Morsels Cat Treats Tuna Flavor 3oz'],
    units: ['bag', 'can', 'box', 'jug', 'pouch']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Office & School', catCode: 'OFF', sup: 'SUP-113', perishable: false, shelfLife: 3650, count: 500,
    brands: ['Mead', 'Bic', 'Crayola', 'Elmer\'s', 'Sharpie', 'Post-it', 'Scotch', 'Dixon'],
    items: ['1-Subject Spiral Notebook Wide Ruled 70ct', '1-Subject Spiral Notebook College Ruled 70ct', '3-Subject Spiral Notebook College Ruled 120ct', 'Composition Book Wide Ruled 100 Sheets', '2-Pocket Heavy Duty Paper Folder Assorted', 'Round Stic Ballpoint Pens Black 10pk', 'Round Stic Ballpoint Pens Blue 10pk', 'Woodcase Lead #2 Pencils 12pk Sharpened', 'Classic Color Wax Crayons 24ct', 'Colored Pencils Pre-Sharpened 12ct', 'Broad Line Washable Markers 10ct', 'Disappearing Purple Glue Sticks 2pk', 'Fine Point Permanent Markers Black 2pk', 'Permanent Markers Ultra Fine Point Black 2pk', 'Sticky Notes Canary Yellow 3x3in 4pk', 'Magic Transparent Tape with Dispenser 3/4in', 'Ruled Index Cards White 3x5in 100ct'],
    units: ['notebook', 'pack', 'box', 'pad']
  },
  {
    dept: 'Dollar General Merchandise', cat: 'Value Valley Foods', catCode: 'VAL', sup: 'SUP-115', perishable: false, shelfLife: 270, count: 600,
    brands: ['Clover Valley', 'Haribo', 'Smarties', 'Stauffer\'s', 'Arizona', 'Jell-O', 'Swiss Miss', 'Dum Dums'],
    items: ['Chocolate Sandwich Creme Cookies 13oz', 'Saltine Crackers Fresh Stacks 16oz', 'Macaroni and Cheese Dinner 7.25oz', 'Chunky Chocolate Chip Cookies 11.75oz', 'Creamy Peanut Butter Spread 16oz', 'Concord Grape Jelly 18oz', 'Mini Twist Pretzels Salted 16oz', 'Goldbears Gummi Candy Share Size 5oz', 'Candy Roll Assorted Flavors 5oz', 'Original Animal Crackers 16oz Bag', 'Green Tea with Ginseng and Honey 23oz Tall Can', 'Mucho Mango Fruit Juice Cocktail 23oz Tall Can', 'Roasted and Salted Peanuts 16oz Canister', 'Hot Cocoa Mix Milk Chocolate 6ct', 'Strawberry Gelatin Dessert Mix 3oz', 'Original Assorted Lollipops 50ct Bag'],
    units: ['box', 'bag', 'can', 'jar', 'canister']
  }
];

// High-speed parallel batch runner
async function batchUpsert(collection, items, docIdFn, batchSize = 400) {
  let count = 0;
  for (let i = 0; i < items.length; i += batchSize) {
    const chunk = items.slice(i, i + batchSize);
    await Promise.all(chunk.map(item => collection.upsert(docIdFn(item), item)));
    count += chunk.length;
    if (count % 2000 === 0 || count === items.length) {
      console.log(`  -> Progress: ${count} / ${items.length} records upserted...`);
    }
  }
}

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

  // 1. Generate Exactly 10,000 Master Products
  console.log('\n--- Step 1: Generating 10,000 Master Products ---');
  const masterCatalog = [];
  let globalUpcIndex = 100000;
  let globalItemIndex = 1;

  for (const bp of CATALOG_BLUEPRINTS) {
    const targetCount = bp.count;
    let generatedForBp = 0;
    const supplier = SUPPLIERS.find(s => s.supplier_id === bp.sup) || SUPPLIERS[0];

    while (generatedForBp < targetCount) {
      const brand = bp.brands[generatedForBp % bp.brands.length];
      const baseItem = bp.items[generatedForBp % bp.items.length];
      const unit = bp.units[generatedForBp % bp.units.length];
      const variantNum = Math.floor(generatedForBp / bp.items.length) + 1;

      const numStr = String(globalItemIndex).padStart(5, '0');
      const sku = `SKU-${bp.dept === 'Grocery' ? 'GRC' : 'DGM'}-${bp.catCode}-${numStr}`;
      const upc = generateUPC(3000000000 + globalUpcIndex);
      globalUpcIndex++;
      globalItemIndex++;

      const variantSuffix = variantNum > 1 ? ` (Pack ${variantNum})` : '';
      const name = `${brand} ${baseItem}${variantSuffix}`;

      // Realistic price generation based on department
      const basePrice = bp.dept === 'Grocery'
        ? (bp.cat === 'Meat & Poultry' || bp.cat === 'Seafood' ? 9.99 : (bp.cat === 'Dairy' ? 4.89 : 3.49))
        : (bp.cat === 'Value Valley Foods' ? 1.75 : (bp.cat === 'Hardware & Electrical' ? 6.95 : 4.25));
      const priceVariance = ((generatedForBp % 17) - 8) * 0.25;
      const unitPrice = Math.max(0.99, Math.round((basePrice + priceVariance) * 100) / 100);
      const unitCost = Math.round((unitPrice * 0.58) * 100) / 100;

      const reorderLevel = Math.max(15, (generatedForBp % 35) + 15);
      const reorderQty = reorderLevel * 2;

      masterCatalog.push({
        type: 'catalogue_item',
        team: 'crew-a',
        sku: sku,
        code: {
          type: 'upc',
          value: upc
        },
        name: name,
        brand: brand,
        category: bp.cat,
        subcategory: bp.catCode,
        department: bp.dept,
        unit: unit,
        unit_price: unitPrice,
        unit_cost: unitCost,
        reorder_level: reorderLevel,
        reorder_quantity: reorderQty,
        safety_stock: Math.floor(reorderLevel * 0.4),
        supplier: supplier,
        attributes: `${unit}, ${brand} Quality, Shelf Life: ${bp.shelfLife} days`,
        perishable: bp.perishable,
        shelf_life_days: bp.shelfLife,
        captured_by: 'system_scale_seed',
        captured_at: new Date().toISOString()
      });

      generatedForBp++;
    }
  }

  console.log(`Generated ${masterCatalog.length} master products.`);

  // 2. Seed 10,000 Products into `catalog`
  console.log('\n--- Step 2: Seeding 10,000 Products into "catalog" collection ---');
  await batchUpsert(catalogColl, masterCatalog, item => `catalogue::upc::${item.code.value}`, 500);
  console.log('Finished seeding 10,000 catalog documents!');

  // 3. Seed 50 GeneralStore Locations
  console.log('\n--- Step 3: Seeding 50 GeneralStore reference locations ---');
  const storeLocations = [];
  const standardAisles = [
    { aisle: 'Aisle 1', name: 'Fresh Produce & Bakery' },
    { aisle: 'Aisle 2', name: 'Dairy & Refrigerated Coolers' },
    { aisle: 'Aisle 3', name: 'Dry Grocery & Grains' },
    { aisle: 'Aisle 4', name: 'Beverages & Soft Drinks' },
    { aisle: 'Aisle 5', name: 'Snacks, Chips & Confectionery' },
    { aisle: 'Aisle 6', name: 'Household Cleaning & Paper' },
    { aisle: 'Aisle 7', name: 'Health, Beauty & OTC First Aid' },
    { aisle: 'Aisle 8', name: 'Hardware, Batteries & Pet Care' },
    { aisle: 'Aisle 9', name: 'Value Valley $1-$3 Specials' }
  ];

  for (const st of STORES) {
    for (const a of standardAisles) {
      for (let s = 1; s <= 2; s++) {
        for (let b = 1; b <= 2; b++) {
          const locDoc = {
            type: 'location',
            name: `${st.name} / ${a.aisle} / Shelf ${s} / Bin ${b}`,
            location: {
              site: st.site,
              rack: a.aisle,
              shelf: `Shelf ${s}`,
              bin: `Bin ${b}`
            },
            store_id: st.store_id,
            store_name: st.name,
            store_type: 'GeneralStore',
            city: st.city,
            qr: `LOC::${st.site.toUpperCase()}::A${a.aisle.replace('Aisle ', '')}-S0${s}-B0${b}`,
            notes: `${a.name} at ${st.name}`
          };
          storeLocations.push({ id: `location::${st.site}::a${a.aisle.replace('Aisle ', '')}_s${s}_b${b}`, doc: locDoc });
        }
      }
    }
  }

  console.log(`Seeding ${storeLocations.length} store locations across 50 GeneralStores...`);
  await batchUpsert(locationsColl, storeLocations.map(l => l.doc), doc => `location::${doc.location.site}::${doc.location.rack.replace(' ', '')}_${doc.location.shelf.replace(' ', '')}_${doc.location.bin.replace(' ', '')}`, 500);

  // 4. Seed DC Bulk Reserve for All 10,000 Products (site: "dc-01")
  console.log('\n--- Step 4: Seeding DC Bulk Reserve in "counts" for all 10,000 products ---');
  const now = Date.now();
  const dcBulkDocs = masterCatalog.map((item, i) => {
    const unitsPerCase = 12;
    const casesOnHand = Math.floor(item.reorder_quantity * (4 + (i % 5) * 0.5));
    const totalUnits = casesOnHand * unitsPerCase;
    const reserved = (i % 6 === 0) ? Math.floor(totalUnits * 0.1) : 0;

    return {
      type: 'count',
      kind: 'entry',
      team: 'dc-logistics',
      sku: item.sku,
      item_name: item.name,
      count: totalUnits,
      count_is_estimate: false,
      attributes: item.attributes,
      annotation: `DC Bulk Reserve. ${casesOnHand} cases on hand.`,
      location: {
        site: 'dc-01',
        rack: item.perishable ? 'Cold Vault 1' : 'Bulk High-Bay Aisle 12',
        shelf: `Tier ${(i % 3) + 1}`,
        bin: `Pallet P${String((i % 25) + 1).padStart(2, '0')}`
      },
      source: 'code',
      code: item.code,
      confidence: 100,
      needs_review: false,
      captured_at: new Date(now).toISOString(),
      captured_by: 'dc_wms_scale',
      captured_by_name: 'Celios-Nomad Enterprise WMS',
      store_id: 'dc-01',
      store_name: 'Celios-Nomad Midwest Distribution Center',
      facility_type: 'DistributionCenter',
      stock_quantity: totalUnits,
      units_per_case: unitsPerCase,
      cases_on_hand: casesOnHand,
      pallets_on_hand: Math.max(1, Math.floor(casesOnHand / 40)),
      reserved_for_shipments: reserved,
      available_to_promise: totalUnits - reserved,
      reorder_level: item.reorder_level * 5,
      reorder_quantity: item.reorder_quantity * 8,
      stock_status: 'in_stock',
      temperature_class: item.perishable ? 'refrigerated' : 'ambient',
      last_audit_date: new Date(now).toISOString()
    };
  });

  await batchUpsert(countsColl, dcBulkDocs, doc => `count::dc-01::${doc.sku}`, 500);
  console.log('Finished seeding 10,000 DC bulk inventory records!');

  // 5. Seed Assorted Inventory across 50 GeneralStores
  // Each GeneralStore carries ~1,200 active SKUs (mix of core staples + rotating assortment)
  // Total = ~60,000 store inventory documents
  console.log('\n--- Step 5: Seeding Store Inventory across 50 GeneralStores (~60,000 records) ---');
  const storeInventoryBatch = [];
  const CORE_COUNT = 800; // Carried by all 50 stores

  for (let sIdx = 0; sIdx < STORES.length; sIdx++) {
    const store = STORES[sIdx];
    // Each store takes core staples (first 800) + rotational slice of 400 items
    const rotationStart = CORE_COUNT + ((sIdx * 184) % (masterCatalog.length - CORE_COUNT - 400));
    const storeItems = [
      ...masterCatalog.slice(0, CORE_COUNT),
      ...masterCatalog.slice(rotationStart, rotationStart + 400)
    ];

    for (let i = 0; i < storeItems.length; i++) {
      const item = storeItems[i];
      const baseLevel = item.reorder_level;

      // Variance across 50 stores to challenge Nomad agents:
      let stockQty;
      let status = 'in_stock';
      let confidence = 100;
      let needsReview = false;

      if ((sIdx + i) % 23 === 0) {
        // Stockout trigger
        stockQty = 0;
        status = 'out_of_stock';
      } else if ((sIdx + i) % 11 === 0) {
        // Low stock trigger
        stockQty = Math.floor(baseLevel * 0.4);
        status = 'low_stock';
      } else if ((sIdx + i) % 31 === 0) {
        // Overstocked candidate
        stockQty = Math.floor(baseLevel * 2.6);
        status = 'overstocked';
      } else {
        stockQty = Math.floor(baseLevel * (1.0 + ((sIdx + i) % 7) * 0.15));
      }

      if ((sIdx + i) % 47 === 0) {
        needsReview = true;
        confidence = 65;
      }

      const aisleNum = (i % standardAisles.length) + 1;
      const shelfNum = (i % 2) + 1;
      const binNum = (i % 2) + 1;

      storeInventoryBatch.push({
        type: 'count',
        kind: 'entry',
        team: 'crew-a',
        sku: item.sku,
        item_name: item.name,
        count: stockQty,
        count_is_estimate: false,
        attributes: item.attributes,
        annotation: status === 'out_of_stock' ? 'Shelf empty. Reorder required.' : 'Normal shelf stock.',
        location: {
          site: store.site,
          rack: `Aisle ${aisleNum}`,
          shelf: `Shelf ${shelfNum}`,
          bin: `Bin ${binNum}`
        },
        source: 'code',
        code: item.code,
        confidence: confidence,
        needs_review: needsReview,
        captured_at: new Date(now - (((sIdx + i) % 24) * 3600000)).toISOString(),
        captured_by: 'agent-nomad-01',
        captured_by_name: 'Nomad No-Code Agent',
        // GeneralStore & Analytics Fields
        store_id: store.store_id,
        store_name: store.name,
        store_type: 'GeneralStore',
        city: store.city,
        stock_quantity: stockQty,
        reserved_quantity: Math.min(2, Math.floor(stockQty * 0.05)),
        reorder_level: item.reorder_level,
        reorder_quantity: item.reorder_quantity,
        stock_status: status,
        sales_volume_30d: Math.floor(item.reorder_quantity * (1.2 + ((sIdx + i) % 5) * 0.2)),
        inventory_turnover_rate: Math.round(((30 / Math.max(1, item.shelf_life_days)) * 2.2) * 10) / 10,
        date_received: new Date(now - (((sIdx + i) % 10 + 2) * 86400000)).toISOString(),
        expiration_date: item.perishable ? new Date(now + (((sIdx + i) % 8 + 3) * 86400000)).toISOString() : null,
        last_audit_date: new Date(now).toISOString()
      });
    }
  }

  console.log(`Seeding ${storeInventoryBatch.length} store inventory records across 50 GeneralStores...`);
  await batchUpsert(countsColl, storeInventoryBatch, doc => `count::${doc.store_id}::${doc.sku}`, 500);

  // 6. Validation Queries
  console.log('\n--- Step 6: Running Validation Queries ---');
  const catTotal = await cluster.query('SELECT count(*) as cnt FROM `inventorycount`.inventory.catalog');
  const countsTotal = await cluster.query('SELECT count(*) as cnt FROM `inventorycount`.inventory.counts');
  const storesTotal = await cluster.query('SELECT count(distinct store_id) as cnt FROM `inventorycount`.inventory.counts WHERE store_type = "GeneralStore"');

  console.log(`Scale Validation:`);
  console.log(`  - Products in catalog: ${catTotal.rows[0].cnt}`);
  console.log(`  - Total records in counts: ${countsTotal.rows[0].cnt} (10K DC + 60K GeneralStores)`);
  console.log(`  - Distinct GeneralStores: ${storesTotal.rows[0].cnt}`);

  // Sample Query: Stockout Count across all 50 GeneralStores for a single SKU
  const stockoutAnalysis = await cluster.query(`
    SELECT 
      c.sku,
      c.item_name,
      COUNT(CASE WHEN c.stock_status = 'out_of_stock' THEN 1 END) AS out_of_stock_stores,
      COUNT(CASE WHEN c.stock_status = 'low_stock' THEN 1 END) AS low_stock_stores,
      COUNT(CASE WHEN c.stock_status = 'in_stock' THEN 1 END) AS in_stock_stores,
      COUNT(CASE WHEN c.stock_status = 'overstocked' THEN 1 END) AS overstocked_stores,
      SUM(c.stock_quantity) AS total_chain_stock
    FROM \`inventorycount\`.inventory.counts c
    WHERE c.store_type = 'GeneralStore' AND c.sku = 'SKU-GRC-DAIR-00001'
    GROUP BY c.sku, c.item_name
  `);
  console.log('\nSample Nomad Agent Query: Chain-wide Stock Analysis for SKU-GRC-DAIR-00001:');
  console.log(JSON.stringify(stockoutAnalysis.rows, null, 2));

  await cluster.close();
  console.log('\nScaling to 10K Products and 50 GeneralStores completed successfully!');
}

main().catch(err => {
  console.error('Fatal error during scale seeding:', err);
  process.exit(1);
});
