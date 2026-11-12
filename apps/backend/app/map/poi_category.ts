import type { Tags } from '#map/features'

/**
 * Categoría de un punto de interés, para su icono y color en el juego
 * (apps/game/scripts/map/poi_catalog.gd y assets/art/ui/poi/<cat>.png).
 */
export type PoiCategory =
  | 'food'
  | 'shop'
  | 'health'
  | 'education'
  | 'worship'
  | 'money'
  | 'transport'
  | 'culture'
  | 'lodging'
  | 'sport'
  | 'service'
  | 'other'

const AMENITY: Record<string, PoiCategory> = {
  restaurant: 'food',
  cafe: 'food',
  fast_food: 'food',
  bar: 'food',
  pub: 'food',
  ice_cream: 'food',
  food_court: 'food',
  biergarten: 'food',
  pharmacy: 'health',
  hospital: 'health',
  clinic: 'health',
  doctors: 'health',
  dentist: 'health',
  veterinary: 'health',
  school: 'education',
  university: 'education',
  college: 'education',
  kindergarten: 'education',
  library: 'education',
  language_school: 'education',
  driving_school: 'education',
  place_of_worship: 'worship',
  monastery: 'worship',
  bank: 'money',
  atm: 'money',
  bureau_de_change: 'money',
  money_transfer: 'money',
  bus_station: 'transport',
  fuel: 'transport',
  taxi: 'transport',
  bicycle_rental: 'transport',
  car_rental: 'transport',
  parking: 'transport',
  ferry_terminal: 'transport',
  charging_station: 'transport',
  theatre: 'culture',
  cinema: 'culture',
  arts_centre: 'culture',
  community_centre: 'culture',
  nightclub: 'culture',
  marketplace: 'shop',
  post_office: 'service',
  police: 'service',
  townhall: 'service',
  courthouse: 'service',
  fire_station: 'service',
  post_box: 'service',
  toilets: 'service',
  gym: 'sport',
}

const TOURISM: Record<string, PoiCategory> = {
  hotel: 'lodging',
  hostel: 'lodging',
  motel: 'lodging',
  guest_house: 'lodging',
  apartment: 'lodging',
  museum: 'culture',
  gallery: 'culture',
  attraction: 'culture',
  artwork: 'culture',
  viewpoint: 'culture',
  zoo: 'culture',
  theme_park: 'culture',
  information: 'service',
}

const SHOP_FOOD = new Set(['bakery', 'pastry', 'confectionery', 'coffee', 'deli', 'ice_cream'])

export function poiCategory(tags: Tags): PoiCategory {
  if (tags.amenity && AMENITY[tags.amenity]) return AMENITY[tags.amenity]
  if (tags.tourism && TOURISM[tags.tourism]) return TOURISM[tags.tourism]
  if (tags.shop) {
    if (SHOP_FOOD.has(tags.shop)) return 'food'
    if (tags.shop === 'chemist' || tags.shop === 'medical_supply' || tags.shop === 'optician')
      return 'health'
    return 'shop'
  }
  if (tags.historic) return 'culture'
  if (tags.leisure) {
    return [
      'sports_centre',
      'fitness_centre',
      'stadium',
      'pitch',
      'swimming_pool',
      'track',
    ].includes(tags.leisure)
      ? 'sport'
      : 'culture'
  }
  if (tags.public_transport === 'station' || tags.railway === 'station') return 'transport'
  if (tags.office || tags.craft) return 'service'
  return 'other'
}
