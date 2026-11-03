/// The Open sites: companion web services on their own openpak.org hosts. The
/// directory and the game mapping mirror the website's pages/sites.go.
library;

class OpenSite {
  const OpenSite(this.key, this.name, this.url);

  /// Selects the copy (sites.KEY.line) and the mark under /static/sites.
  final String key;
  final String name;
  final String url;

  /// Site-relative path of the mark, served by the website.
  String get mark => '/static/sites/$key.svg';
}

/// In the order the website's /sites page shows them.
const openSites = [
  OpenSite('opensplat', 'OpenSplat', 'https://splat.openpak.org'),
  OpenSite('openkart', 'OpenKart', 'https://kart.openpak.org'),
  OpenSite('openmaker', 'OpenMaker', 'https://maker.openpak.org'),
  OpenSite('openverse', 'OpenVerse', 'https://verse.openpak.org'),
];

/// Which Open site covers a title, by catalogue name and console.
const _titleSites = {
  ('Splatoon', 'Wii U'): 'opensplat',
  ('Mario Kart 8', 'Wii U'): 'openkart',
  ('Mario Kart 8 Deluxe', 'Switch'): 'openkart',
  ('Mario Kart 7', '3DS'): 'openkart',
  ('Mario Kart Wii', 'Wii'): 'openkart',
  ('Super Mario Maker', 'Wii U'): 'openmaker',
  ('Super Mario Maker for Nintendo 3DS', '3DS'): 'openmaker',
  ('Super Mario Maker', '3DS'): 'openmaker',
  ('Super Mario Maker 2', 'Switch'): 'openmaker',
};

/// The Open site for a title, null when it has none.
OpenSite? siteFor(String name, String console) {
  final key = _titleSites[(name, console)];
  if (key == null) return null;
  for (final s in openSites) {
    if (s.key == key) return s;
  }
  return null;
}
