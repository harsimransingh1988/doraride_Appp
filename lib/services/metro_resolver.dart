// lib/services/metro_resolver.dart
//
// Minimal world metro grouping for corridor matching.
// Add/extend as you like. Keys returned are canonical metro slugs.

library metro_resolver;

import 'geo_resolver.dart'; // for clean()

String metroKey(String cityTokenLower) {
  final c = clean(cityTokenLower);

  // Canada – GTA
  const gta = {
    'toronto',
    'scarborough',
    'etobicoke',
    'north york',
    'mississauga',
    'brampton',
    'vaughan',
    'markham',
    'richmond hill',
    'oakville',
    'milton',
    'ajax',
    'pickering',
    'whitby',
  };

  // Canada – Montreal CMA
  const gma = {
    'montreal',
    'montréal',
    'laval',
    'longueuil',
    'brossard',
    'terrebonne',
    'repentigny',
    'dorval',
  };

  // Canada – Ottawa/Gatineau
  const ott = {'ottawa', 'gatineau', 'kanata', 'orleans'};

  // Canada – Vancouver
  const yvr = {'vancouver', 'burnaby', 'richmond', 'surrey', 'coquitlam'};

  // USA – a couple of big ones (extend as needed)
  const nyc = {
    'new york',
    'manhattan',
    'brooklyn',
    'queens',
    'bronx',
    'staten island',
    'jersey city',
    'hoboken'
  };
  const la = {
    'los angeles',
    'la',
    'santa monica',
    'pasadena',
    'long beach',
    'hollywood',
  };

  // India (simple starters)
  const delhi = {'delhi', 'new delhi', 'gurgaon', 'noida', 'ghaziabad'};
  const mumbai = {'mumbai', 'bombay', 'thane', 'navi mumbai'};

  // Turkey (simple starters)
  const istanbul = {'istanbul', 'üsküdar', 'kadikoy', 'besiktas', 'bakirkoy'};
  const ankara = {'ankara', 'cankaya', 'yenimahalle', 'keçiören', 'kecioren'};

  // UK / France samples
  const london = {'london', 'croydon', 'watford', 'wembley', 'richmond'};
  const paris = {'paris', 'boulogne-billancourt', 'versailles', 'saint-denis'};

  if (gta.contains(c)) return 'toronto';
  if (gma.contains(c)) return 'montreal';
  if (ott.contains(c)) return 'ottawa';
  if (yvr.contains(c)) return 'vancouver';

  if (nyc.contains(c)) return 'newyork';
  if (la.contains(c)) return 'losangeles';

  if (delhi.contains(c)) return 'delhi';
  if (mumbai.contains(c)) return 'mumbai';

  if (istanbul.contains(c)) return 'istanbul';
  if (ankara.contains(c)) return 'ankara';

  if (london.contains(c)) return 'london';
  if (paris.contains(c)) return 'paris';

  // fallback: itself
  return c;
}
